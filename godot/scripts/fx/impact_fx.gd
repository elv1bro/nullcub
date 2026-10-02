## Ударные эффекты (ART_DIRECTION.md v3 §5, R22; INSPIRATION_GAMES.md): вспышка-блик, щепки + клуб пыли в точке контакта. Без autoload:
##   ImpactFx.spawn_impact(parent, position, normal, strength, kind, mat = "", tint = прозрачный, metal_striker = false)
## С 02.10 обломки — по материалу ударенной детали (FxMaterial, HIT_FX.md §13): щепки, хлопья краски, искры, сколы кости, пыль.
## Вспышка (как в Ragdoll Masters): мягкий диск + два луча из квадов с радиальным градиентом, аддитивно, без теста глубины,
## лицом к камере (+Z), цвет по kind — body белая, head красно-оранжевая, weapon жёлтая, environment/self голубоватая;
## размер по strength; поведение и время жизни — scripts/fx/impact_flash.gd (ImpactFlash). Яркость × FxPreset.flash() (§11.2), при 0 звезды нет. Материалы вспышки общие на kind
## (flash_material); prewarm(parent) в начале матча создаёт их заранее, чтобы первый удар не ловил стал компиляции шейдера.
## инстанцирует res://scenes/fx/splinters.tscn и res://scenes/fx/dust_puff.tscn под общим Node3D, ориентирует их
## +Z вдоль нормали (щепки летят от поверхности), масштабирует число частиц и скорость по strength (м/с относительной
## скорости удара; STRENGTH_REF — «номинальный» удар) и освобождает узел, когда обе системы отработали
## (сигнал finished у one-shot GPUParticles3D; страховка — таймер MAX_LIFE_S).
class_name ImpactFx
extends RefCounted

const SPLINTERS: PackedScene = preload("res://scenes/fx/splinters.tscn")
const DUST_PUFF: PackedScene = preload("res://scenes/fx/dust_puff.tscn")
const SPARKS: PackedScene = preload("res://scenes/fx/sparks.tscn")
const CHIPS: PackedScene = preload("res://scenes/fx/chips.tscn")   # серые осколки: цвет — FxMaterial.chip_ramp (краска, кость, ржавчина)
const STRENGTH_REF := 8.0
const MAX_LIFE_S := 3.0
const FLASH_SIZE_MIN := 0.42
const FLASH_SIZE_PER_K := 0.38
# стиль «серьёзный» (HIT_FX.md §13): горячее пятно и свет удара; k = сила удара / STRENGTH_REF (0.25…2)
const CORE_SIZE_MIN := 0.1
const CORE_SIZE_PER_K := 0.07
const CORE_LIFE_S := 0.04
const LIGHT_ENERGY_MIN := 1.5
const LIGHT_ENERGY_PER_K := 2.5
const LIGHT_RANGE_MIN := 1.6
const LIGHT_RANGE_PER_K := 0.7
const LIGHT_LIFE_S := 0.07
const FLASH_COLOURS := {
	"body": Color(1.0, 1.0, 1.0),
	"head": Color(1.0, 0.42, 0.22),
	"weapon": Color(1.0, 0.86, 0.32),
	"environment": Color(0.78, 0.88, 1.0),
	"self": Color(0.78, 0.88, 1.0),
}

static var _flash_tex: GradientTexture2D
static var _flash_mats: Dictionary = {}


## mat — id материала ударенной детали (FxMaterial.id_of; "" — дерево, как до 02.10), tint — цвет хлопьев краски (FxMaterial.tint_of,
## a = 0 — без хлопьев), metal_striker — бьёт металл. Обломки по классу материала (HIT_FX.md §13): дерево — щепки своего тона (и хлопья
## краски tint), краска — хлопья краски и дерево под ней, кость — белые сколы, ржавчина — рыжие хлопья + искры, металл — искры (без щепок;
## металл о металл — сноп гуще), резина — только пыль. Систем частиц на удар не больше, чем было (щепки или искры + пыль; ржавчина — три).
static func spawn_impact(parent: Node, position: Vector3, normal: Vector3, strength: float, kind: String = "", mat: String = "",
		tint: Color = Color(0, 0, 0, 0), metal_striker: bool = false) -> Node3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var k := clampf(strength / STRENGTH_REF, 0.25, 2.0)
	var root := Node3D.new()
	root.name = "ImpactFx"
	parent.add_child(root, true)   # читаемое имя ImpactFx2… (не «@Node3D@N»): пробы и директоры узнают корни по префиксу
	var n := normal
	if n.length_squared() < 1e-6:
		n = Vector3.UP
	n = n.normalized()
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	root.global_transform = Transform3D(Basis.looking_at(-n, up), position)
	_spawn_flash(root, position, k, kind)  # после установки transform корня: вспышка ставится в мировых координатах
	var c := FxMaterial.cls(mat) if mat != "" else FxMaterial.WOOD
	var scenes: Array = []
	# дерево без краски — щепки с текстурой дерева; всё цветное (краска, мазки цвета игрока, кость, ржавчина) — серые осколки × градиент
	var chips_scene: PackedScene = SPLINTERS if (c == FxMaterial.WOOD or c == FxMaterial.WOOD_DARK) and tint.a <= 0.0 else CHIPS
	if c != FxMaterial.METAL and c != FxMaterial.RUBBER:
		scenes.append(chips_scene)
	if FxMaterial.is_metal(c):
		scenes.append(SPARKS)
	scenes.append(DUST_PUFF)
	for scene in scenes:
		var p := (scene as PackedScene).instantiate() as GPUParticles3D
		if p == null:
			continue
		root.add_child(p)
		var pm := p.process_material as ParticleProcessMaterial
		if pm != null:
			pm = pm.duplicate() as ParticleProcessMaterial
			pm.initial_velocity_min *= k
			pm.initial_velocity_max *= k
			if scene == CHIPS or (scene == SPLINTERS and c != FxMaterial.WOOD):
				pm.color_initial_ramp = FxMaterial.chip_ramp(c, tint)
			p.process_material = pm
		p.amount_ratio = clampf(0.5 + 0.5 * k, 0.3, 1.0)
		if scene == SPARKS:
			# металл о металл — сноп целиком; по ржавчине и мягким ударом — реже
			p.amount_ratio = clampf(p.amount_ratio * (1.0 if metal_striker else 0.6) * (0.5 if c == FxMaterial.RUST else 1.0), 0.15, 1.0)
		p.finished.connect(func() -> void: _on_finished(root))
		p.restart()
		p.emitting = true
	# weakref: если сцену/родителя освободили раньше таймера (смена арены, конец теста), лямбда не держит мёртвую ссылку
	var wr: WeakRef = weakref(root)
	parent.get_tree().create_timer(MAX_LIFE_S).timeout.connect(func() -> void: _free_if_valid(wr.get_ref() as Node3D))
	return root


static func _flash_texture() -> GradientTexture2D:
	if _flash_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.width = 128
		t.height = 128
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		_flash_tex = t
	return _flash_tex


## Общий материал вспышки для типа удара (кэш): аддитивный, без освещения и теста глубины, радиальный градиент.
static func flash_material(kind: String) -> StandardMaterial3D:
	var key := kind if FLASH_COLOURS.has(kind) else "body"
	if _flash_mats.has(key):
		return _flash_mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.disable_receive_shadows = true
	m.albedo_texture = _flash_texture()
	m.albedo_color = FLASH_COLOURS[key]
	m.render_priority = 10
	_flash_mats[key] = m
	return m


## Прогрев: материалы вспышек всех типов и по одному экземпляру систем частиц, чтобы шейдеры собрались до первого удара.
static func prewarm(parent: Node) -> void:
	for kind in FLASH_COLOURS.keys():
		flash_material(kind)
	core_material()
	if parent == null or not parent.is_inside_tree():
		return
	for m in ["", "iron", "bone"]:   # щепки и пыль; искры металла; серые осколки (HIT_FX.md §13)
		var root := spawn_impact(parent, Vector3(0.0, -500.0, 0.0), Vector3.UP, 0.1, "body", m)
		if root != null:
			root.visible = false


## Вспышка: ImpactFlash (диск + два луча) к камере (+Z), чуть перед точкой контакта; размер по силе удара.
## Стиль «серьёзный» (HitJuice.impact_style, HIT_FX.md §13): вместо звезды — маленькое горячее пятно без лучей на 2–3 кадра и короткий
## тёплый свет ImpactLight, который освещает куклы и пол (сила удара читается светом, а не наклейкой).
static func _spawn_flash(root: Node3D, position: Vector3, k: float, kind: String) -> void:
	var alpha := FxPreset.flash()   # пресет FX игрока (HIT_FX.md §11.2): reduced — тусклее, off — без звезды
	if alpha <= 0.001:
		return
	if HitJuice.impact_style == "serious":
		var core := ImpactFlash.new()
		core.name = "Flash"
		root.add_child(core)
		core.global_transform = Transform3D(Basis.IDENTITY, position + Vector3(0.0, 0.0, 0.18))
		core.setup(core_material(), CORE_SIZE_MIN + CORE_SIZE_PER_K * k, alpha * 0.85, false, CORE_LIFE_S)
		ImpactLight.flash(root, position, LIGHT_ENERGY_MIN + LIGHT_ENERGY_PER_K * k, LIGHT_RANGE_MIN + LIGHT_RANGE_PER_K * k,
			LIGHT_LIFE_S, ImpactLight.WARM)
		return
	var size := FLASH_SIZE_MIN + FLASH_SIZE_PER_K * k
	var flash := ImpactFlash.new()
	flash.name = "Flash"
	root.add_child(flash)
	flash.global_transform = Transform3D(Basis.IDENTITY, position + Vector3(0.0, 0.0, 0.18))
	flash.setup(flash_material(kind), size, alpha)


static var _core_mat: StandardMaterial3D


## Горячее пятно стиля «серьёзный»: тёплый белый, аддитивно, без теста глубины (как звезда), один на все типы удара.
static func core_material() -> StandardMaterial3D:
	if _core_mat == null:
		var m := flash_material("body").duplicate() as StandardMaterial3D
		m.albedo_color = Color(1.0, 0.86, 0.66)
		_core_mat = m
	return _core_mat


static func _on_finished(root: Node3D) -> void:
	if not is_instance_valid(root):
		return
	for c in root.get_children():
		if c is GPUParticles3D and (c as GPUParticles3D).emitting:
			return
	root.queue_free()


static func _free_if_valid(root: Node3D) -> void:
	if is_instance_valid(root):
		root.queue_free()
