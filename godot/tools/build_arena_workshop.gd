## Builder арены «Мастерская» (ART_DIRECTION.md v3 §5, лист R22, docs/plan-demo/05-arena.md): собирает
## res://scenes/arena/workshop.tscn ИЗ КОМПОНЕНТНЫХ СЦЕН scenes/props/workshop_*.tscn (их делает
## tools/build_workshop_props_scenes.gd из моделей workshop_props.py) + barrel/crate (Breakable) + декор из glb мастерской.
## Каждый компонент — PackedScene.instantiate() с owner = корень арены; внутренности инстансов принадлежат своим сценам
## (в workshop.tscn сохраняются только позиция и переопределённые экспорты). Ничего не строится в _ready().
## Запуск: godot --headless --path godot --import && godot --headless --path godot -s res://tools/build_arena_workshop.gd
## Повторный запуск перезаписывает сцену: правки, которые нужно сохранить, вносятся сюда.
##
## Система координат: X вбок, Y вверх, физика в плоскости XY (z=0 — плоскость кукол), +Z к камере. Пол y=0.
## Закрытое помещение ≈ 26 × 10 м (невидимые стены x=±HALF_W, потолок CEIL_Y), ям и DeathZone нет.
## Задняя стена стоит на z=WALL_Z (внутренняя плоскость досок) без коллизии — куклы туда не долетают (z заперта).
## Полки крепятся к стене: их коллизия тянется от стены до z≈+0.4, поэтому кукла на z=0 «стоит на полке».
## Дерево: Node3D "Workshop" (script workshop.gd)
##   ├── WorldEnvironment "Environment" (копия assets/environments/workshop_env.tres: туман под масштаб арены, SDFGI выкл.),
##   │   DirectionalLight3D "Sun" (тёплый, из-за окон слева-сзади, лучи в объёмном тумане), "Fill" (холодный, без теней)
##   ├── Node3D "Room": пол из плиток workshop_floor_planks (3 × 2, z −1.2..2.8), брус-фасция Edge_Beam и дощатый фасад
##   │     под кромкой сцены, задняя стена 2 ряда × 9 сегментов (окна на x=−8, 0, 8; верхний ряд без задника), боковые
##   │     стены x=±16, потолочные балки Ceiling_Beams (низ на CEIL_BEAM_Y), точёные стойки за краями
##   ├── Node3D "Left": штабель (0.5) → верстак (0.85) → штабель; полки на стене y=2.7 и 4.4
##   ├── Node3D "Centre": токарный станок (станина 0.95 — средняя площадка)
##   ├── Node3D "Right": верстак (0.85); полки y=2.5 и 4.2
##   ├── Node3D "Decor": щиты с инструментом между окнами, стружка на полу
##   ├── Node3D "Lamps": workshop_lamp ×3 (крюк на балке CEIL_BEAM_Y над верстаками и станком; абажур y≈5.6)
##   ├── Node3D "Props": barrel/crate (Breakable) и Sawhorse ×2 (RigidBody3D 8 кг) — обломки спавнятся сюда же
##   ├── GPUParticles3D "Dust": взвешенная пыль по всему объёму; Node3D "ShaftDust": пылинки в лучах трёх нижних окон
##   ├── Room/RoofShadow: плоскость 80 × 52 на y=10.5 от стены вперёд, только для теней (объём перед сценой без крыши засвечивал туман)
##   ├── StaticBody3D "Bounds": невидимые стены x=±HALF_W, потолок y=CEIL_Y, страховочный пол под плитками
##   └── Node3D "Spawns": Marker3D Spawn0..3 (пол слева/справа от станка, левый и правый верстаки)
extends SceneTree

const OUT := "res://scenes/arena/workshop.tscn"
const SCENE_UID := "uid://wsarena00001"
const PROPS := "res://scenes/props/%s.tscn"
const GLB := "res://assets/models/workshop/%s.glb"
const SCRIPT := "res://scenes/arena/workshop.gd"
const ENV_RES := "res://assets/environments/workshop_env.tres"
const MOTE_TEX := "res://assets/textures/fx/mote.png"

const HALF_W := 13.0            # невидимые стены
const CEIL_Y := 10.0            # невидимый потолок
const WALL_Z := -1.2            # внутренняя плоскость задней стены
const FRONT_Z := 2.8            # передняя кромка пола
const FLOOR_Z: Array[float] = [-0.2, 1.8]              # центры рядов плиток 12 × 2
const FLOOR_X: Array[float] = [-12.0, 0.0, 12.0]
const WALL_X: Array[float] = [-16.0, -12.0, -8.0, -4.0, 0.0, 4.0, 8.0, 12.0, 16.0]
const WINDOW_X: Array[float] = [-8.0, 0.0, 8.0]
const CEIL_BEAM_Y := 9.7        # низ стропил (балка на z=0.4 не режет плоскость кукол под потолком y=10)
const BENCH_TOP := 0.85
const STACK_TOP := 0.5
const LAMP_Y := 9.7

# Свет как в look-dev (scenes/lookdev/workshop_lookdev.tscn): солнце сзади-слева-сверху, лучи в объёмном тумане.
const SUN_DIR := Vector3(0.611, -0.407, 0.679)
const SUN_COLOR := Color(1.0, 0.86, 0.66)
const FOG_DENSITY := 0.0065     # look-dev 0.014 на 7 м; камера арены в 20–30 м — плотность ниже, иначе молоко
const SUN_FOG_ENERGY := 7.0     # look-dev 8
const SUN_ENERGY := 3.3         # look-dev 3
const FILL_ENERGY := 0.55       # look-dev 0.4
const AMBIENT_ENERGY := 0.7     # look-dev 0.3 + SDFGI; здесь SDFGI выключен (см. _environment), тени добирает ambient + SSIL
const EXPOSURE := 1.05

var arena_root: Node3D
var _scenes: Dictionary = {}
var _names: Dictionary = {}


func _init() -> void:
	arena_root = Node3D.new()
	arena_root.name = "Workshop"
	arena_root.set_script(load(SCRIPT))
	_environment()
	_room()
	_left()
	_centre()
	_right()
	_decor()
	_lamps()
	_props()
	_dust()
	_shaft_dust()
	_bounds()
	_spawns()
	_set_owner(arena_root)
	var ps := PackedScene.new()
	var err := ps.pack(arena_root)
	if err != OK:
		push_error("pack failed: %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(ps, OUT)
	if err != OK:
		push_error("save failed: %d" % err)
		quit(1)
		return
	ResourceSaver.set_uid(OUT, ResourceUID.text_to_id(SCENE_UID))
	print("saved ", OUT, ": nodes=", _count(arena_root), " components=", _scenes.size(), " kinds")
	arena_root.free()
	quit(0)


# ---------------------------------------------------------------- helpers
func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


## owner для узлов, созданных здесь; внутренности инстансов уже принадлежат своим сценам и не трогаются.
func _set_owner(n: Node) -> void:
	for c in n.get_children():
		if c.owner == null:
			c.owner = arena_root
		_set_owner(c)


func _uniq(base: String) -> String:
	var k := int(_names.get(base, 0))
	_names[base] = k + 1
	return base if k == 0 else "%s_%d" % [base, k]


func _scene(kind: String) -> PackedScene:
	if not _scenes.has(kind):
		var ps: PackedScene = load(PROPS % kind)
		if ps == null:
			push_error("missing component scene " + (PROPS % kind) + " — run tools/build_workshop_props_scenes.gd / build_props_scenes.gd")
			quit(1)
		_scenes[kind] = ps
	return _scenes[kind]


func _group(name: String) -> Node3D:
	var n := Node3D.new()
	n.name = name
	arena_root.add_child(n)
	return n


## Инстанс компонента; overrides — экспорты (exterior_visible, foliage_visible, …); rot_y — градусы вокруг Y.
func _inst(parent: Node, kind: String, name: String, pos: Vector3, overrides: Dictionary = {}, rot_y := 0.0) -> Node3D:
	var inst: Node3D = _scene(kind).instantiate()
	inst.name = _uniq(name)
	inst.position = pos
	if rot_y != 0.0:
		inst.rotation_degrees = Vector3(0, rot_y, 0)
	for k in overrides.keys():
		inst.set(k, overrides[k])
	parent.add_child(inst)
	return inst


## Декоративная модель мастерской без коллизии (glb напрямую: балки, стойки, фасад).
func _deco(parent: Node, glb: String, name: String, pos: Vector3, rot_y := 0.0) -> Node3D:
	var ps: PackedScene = load(GLB % glb)
	if ps == null:
		push_error("missing " + (GLB % glb) + " — run Blender workshop_props.py and godot --import")
		quit(1)
		return Node3D.new()
	var n: Node3D = ps.instantiate()
	n.name = _uniq(name)
	n.position = pos
	if rot_y != 0.0:
		n.rotation_degrees = Vector3(0, rot_y, 0)
	parent.add_child(n)
	return n


func _box_shape(parent: Node, name: String, x0: float, x1: float, y0: float, y1: float, z := 0.0, depth := 2.0) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.name = _uniq(name)
	var bs := BoxShape3D.new()
	bs.size = Vector3(x1 - x0, y1 - y0, depth)
	cs.shape = bs
	cs.position = Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, z)
	parent.add_child(cs)
	return cs


# ---------------------------------------------------------------- layout
func _room() -> void:
	var r := _group("Room")
	for z in FLOOR_Z:
		for x in FLOOR_X:
			_inst(r, "workshop_floor_planks", "Floor", Vector3(x, 0.0, z))
	# фасция и дощатый фасад под передней кромкой: камера при полном кадре видит ниже пола
	for x in FLOOR_X:
		_deco(r, "Edge_Beam", "EdgeBeam", Vector3(x, 0.0, FRONT_Z + 0.2))
	for x in WALL_X:
		_deco(r, "Wall_Plank", "StageFront", Vector3(x, -5.0, FRONT_Z + 0.25))
	# задняя стена: два ряда по 5 м; окна на x=−8, 0, 8 в обоих рядах, у верхнего ряда задник/листва выключены
	for row in 2:
		var y := 5.0 * row
		for x in WALL_X:
			if x in WINDOW_X:
				_inst(r, "workshop_window_wall", "WindowWall", Vector3(x, y, WALL_Z),
					{"exterior_visible": row == 0, "foliage_visible": row == 0})
			else:
				_deco(r, "Wall_Plank", "BackWall", Vector3(x, y, WALL_Z))
	# боковые стены (лицом внутрь): local +Z → +X при +90°
	for row in 2:
		var y := 5.0 * row
		_deco(r, "Wall_Plank", "SideWallL", Vector3(-16.1, y, 0.8), 90.0)
		_deco(r, "Wall_Plank", "SideWallR", Vector3(16.1, y, 0.8), -90.0)
	# потолок: стропила вдоль X (в Godot на z = zc − {±0.8, ±2.4}), два ряда в глубину
	for z in [1.2, 7.2]:
		for x in FLOOR_X:
			_deco(r, "Ceiling_Beams", "Ceiling", Vector3(x, CEIL_BEAM_Y, z))
	# точёные стойки за краями площадки (закрывают невидимые стены)
	_deco(r, "Turned_Post", "Post", Vector3(-15.3, 0.0, 0.5), 20.0)
	_deco(r, "Turned_Post", "Post", Vector3(15.2, 0.0, 0.4), -35.0)
	# «крыша» только для теней над объёмом перед сценой (z до +36) и по бокам: иначе солнце засвечивает туман между
	# камерой и комнатой (у комнаты нет передней стены), и весь кадр заливает молочным ореолом
	var roof := MeshInstance3D.new()
	roof.name = "RoofShadow"
	var pm := PlaneMesh.new()
	pm.size = Vector2(80.0, 52.0)
	roof.mesh = pm
	roof.position = Vector3(0, CEIL_Y + 0.5, WALL_Z - 0.4 + 26.0)   # от тыльной грани стены вперёд: окнам солнце не перекрывает
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	roof.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	r.add_child(roof)


func _left() -> void:
	var l := _group("Left")
	_inst(l, "workshop_plank_stack", "StackA", Vector3(-12.2, 0.0, 0.0))
	_inst(l, "workshop_bench", "BenchL", Vector3(-9.4, 0.0, 0.0))
	_inst(l, "workshop_plank_stack", "StackB", Vector3(-6.8, 0.0, 0.05), {}, 180.0)
	_inst(l, "workshop_shelf", "ShelfL1", Vector3(-10.9, 2.7, WALL_Z))
	_inst(l, "workshop_shelf", "ShelfL2", Vector3(-5.2, 4.4, WALL_Z))


func _centre() -> void:
	var c := _group("Centre")
	_inst(c, "workshop_lathe", "Lathe", Vector3(0.3, 0.0, 0.0))


func _right() -> void:
	var r := _group("Right")
	_inst(r, "workshop_bench", "BenchR", Vector3(8.6, 0.0, 0.0))
	_inst(r, "workshop_shelf", "ShelfR1", Vector3(11.0, 2.5, WALL_Z))
	_inst(r, "workshop_shelf", "ShelfR2", Vector3(5.2, 4.2, WALL_Z))


func _decor() -> void:
	var d := _group("Decor")
	for x in [-12.0, -4.0, 4.0, 12.0]:
		_inst(d, "workshop_tool_board", "ToolBoard", Vector3(x, 1.25, WALL_Z + 0.02))
	for s in [[-8.3, 0.9, 0.0], [-11.4, 1.3, 40.0], [-1.6, 1.0, 120.0], [2.2, 0.8, -70.0], [7.6, 1.1, 200.0], [11.2, 0.7, 15.0]]:
		_inst(d, "workshop_shavings", "Shavings", Vector3(s[0], 0.0, s[1]), {}, s[2])


func _lamps() -> void:
	var l := _group("Lamps")
	for x in [-9.4, 0.3, 8.6]:
		_inst(l, "workshop_lamp", "Lamp", Vector3(x, LAMP_Y, 0.0))


func _props() -> void:
	var p := _group("Props")
	for b in [[-10.3, BENCH_TOP], [-2.0, 0.0], [2.3, 0.0], [14.1, 0.0]]:
		_inst(p, "barrel", "Barrel", Vector3(b[0], b[1] + 0.02, 0))
	for c in [[-12.2, STACK_TOP], [-14.0, 0.0], [-14.0, 0.72], [9.4, BENCH_TOP], [11.7, 0.0], [12.45, 0.0], [12.1, 0.72], [14.9, 0.0]]:
		_inst(p, "crate", "Crate", Vector3(c[0], c[1] + 0.02, 0))
	for x in [-3.2, 3.6]:
		_inst(p, "workshop_sawhorse", "Sawhorse", Vector3(x, 0.02, 0.0))


func _bounds() -> void:
	var b := StaticBody3D.new()
	b.name = "Bounds"
	arena_root.add_child(b)
	_box_shape(b, "WallL", -HALF_W - 0.5, -HALF_W, -2.0, 14.0, 0.0, 8.0)
	_box_shape(b, "WallR", HALF_W, HALF_W + 0.5, -2.0, 14.0, 0.0, 8.0)
	_box_shape(b, "Ceiling", -HALF_W - 0.5, HALF_W + 0.5, CEIL_Y, CEIL_Y + 0.5, 0.0, 8.0)
	_box_shape(b, "FloorSafety", -20.0, 20.0, -1.0, -0.5, 0.0, 12.0)


func _spawns() -> void:
	var holder := _group("Spawns")
	var pts := [Vector3(-5.6, 0.05, 0), Vector3(5.6, 0.05, 0), Vector3(-9.0, BENCH_TOP + 0.05, 0), Vector3(8.1, BENCH_TOP + 0.05, 0)]
	for i in pts.size():
		var m := Marker3D.new()
		m.name = "Spawn%d" % i
		m.position = pts[i]
		holder.add_child(m)


func _dust() -> void:
	var p := GPUParticles3D.new()
	p.name = "Dust"
	p.position = Vector3(0, 5.0, 0.8)
	p.amount = 900
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.randomness = 0.3
	p.visibility_aabb = AABB(Vector3(-14, -6, -3), Vector3(28, 12, 7))
	var pm := ParticleProcessMaterial.new()
	pm.lifetime_randomness = 0.4
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(13.0, 4.8, 1.9)
	pm.direction = Vector3.ZERO
	pm.spread = 180.0
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.08
	pm.gravity = Vector3(0, -0.01, 0)
	pm.damping_min = 0.1
	pm.damping_max = 0.3
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	grad.colors = PackedColorArray([Color(1, 0.9, 0.7, 0), Color(1, 0.9, 0.7, 0.6), Color(1, 0.9, 0.7, 0.6), Color(1, 0.9, 0.7, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	pm.color_ramp = ramp
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.06
	p.process_material = pm
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 0.88, 0.66, 0.35)
	mat.albedo_texture = load(MOTE_TEX)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.045, 0.045)
	quad.material = mat
	p.draw_pass_1 = quad
	arena_root.add_child(p)


## Пылинки в лучах нижних окон: эмиттер-бокс, повёрнутый по солнцу, от середины окна на 2.5 м внутрь комнаты.
func _shaft_dust() -> void:
	var holder := _group("ShaftDust")
	var basis := Basis.looking_at(SUN_DIR.normalized(), Vector3.UP)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 0.9, 0.7, 0.8)
	mat.albedo_texture = load(MOTE_TEX)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	quad.material = mat
	for x in WINDOW_X:
		var p := GPUParticles3D.new()
		p.name = _uniq("Shaft")
		p.basis = basis
		p.position = Vector3(x, 2.7, WALL_Z) + SUN_DIR.normalized() * 3.0
		p.amount = 220
		p.lifetime = 12.0
		p.preprocess = 12.0
		p.randomness = 0.3
		p.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
		var pm := ParticleProcessMaterial.new()
		pm.lifetime_randomness = 0.4
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(1.0, 1.7, 3.2)
		pm.direction = Vector3.ZERO
		pm.spread = 180.0
		pm.initial_velocity_min = 0.02
		pm.initial_velocity_max = 0.08
		pm.gravity = Vector3(0, -0.01, 0)
		pm.damping_min = 0.1
		pm.damping_max = 0.3
		pm.scale_min = 0.5
		pm.scale_max = 1.2
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
		grad.colors = PackedColorArray([Color(1, 0.9, 0.7, 0), Color(1, 0.9, 0.7, 0.6), Color(1, 0.9, 0.7, 0.6), Color(1, 0.9, 0.7, 0)])
		var ramp := GradientTexture1D.new()
		ramp.gradient = grad
		pm.color_ramp = ramp
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 0.6
		pm.turbulence_noise_scale = 4.0
		pm.turbulence_influence_min = 0.02
		pm.turbulence_influence_max = 0.06
		p.process_material = pm
		p.draw_pass_1 = quad
		holder.add_child(p)


func _environment() -> void:
	var env := WorldEnvironment.new()
	env.name = "Environment"
	var e: Environment = load(ENV_RES)
	if e == null:
		push_error("нет пресета " + ENV_RES)
		quit(1)
		return
	# Копия пресета look-dev: туман под масштаб арены (камера в 20–30 м); SDFGI выключен — на M2 при 1440p он стоил
	# ~10 мс/кадр (22 → 32 fps) и делал кадр плоским (засветка теней), а без него картина контрастнее и ближе к R22;
	# отражённый свет — SSIL пресета + ambient. Остальное как у look-dev.
	e = e.duplicate(true)
	e.volumetric_fog_density = FOG_DENSITY
	e.volumetric_fog_length = 48.0
	e.sdfgi_enabled = false
	e.ambient_light_energy = AMBIENT_ENERGY
	e.tonemap_exposure = EXPOSURE
	env.environment = e
	arena_root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.basis = Basis.looking_at(SUN_DIR.normalized(), Vector3.UP)
	sun.position = Vector3(0, 8, 0)
	sun.light_color = SUN_COLOR
	sun.light_energy = SUN_ENERGY
	sun.light_indirect_energy = 2.0
	sun.light_volumetric_fog_energy = SUN_FOG_ENERGY
	sun.light_angular_distance = 0.8
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.5
	sun.shadow_blur = 1.2
	# 2 сплита: камера боя стоит в 12–30 м, вся арена помещается во второй; 4 сплита удваивали draw calls (605 → 350)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.3
	sun.directional_shadow_max_distance = 48.0
	arena_root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.basis = Basis.looking_at(Vector3(-0.5, -0.55, -0.7).normalized(), Vector3.UP)
	fill.position = Vector3(0, 6, 8)
	fill.light_color = Color(0.6, 0.8, 1.0)
	fill.light_energy = FILL_ENERGY
	fill.light_indirect_energy = 0.0
	fill.light_volumetric_fog_energy = 0.0
	fill.light_specular = 0.4
	fill.shadow_enabled = false
	arena_root.add_child(fill)
