## Builder арены «Свалка» v1 (биом 1 THE SCRAP — первый уровень: Core игрока просыпается в куче хлама на дне Башни;
## docs/plan-demo/BIOMES.md §1, LORE.md, композиция — docs/refs/biomes/01-scrap/scenes.png, свет — parallax.png): собирает
## res://scenes/arena/scrap.tscn ИЗ КОМПОНЕНТНЫХ СЦЕН scenes/props/scrap/*.tscn — модульный кит kit_* (tools/blender/scrap_kit.py
## → tools/build_scrap_kit_scenes.gd), кучи и куски листа 01 bodies_* / bit_* (scrap_bodies.py → build_scrap_bodies_scenes.gd),
## физпропсы листа 02 prop_* (scrap_props.py → build_scrap_props_scenes.gd). Своих мешей нет. Каждый компонент —
## PackedScene.instantiate() с owner = корень арены; внутренности инстансов принадлежат своим сценам (в scrap.tscn сохраняются
## только позиция/масштаб). Ничего не строится в _ready(); поведение — scenes/arena/scrap.gd.
## Запуск: godot --headless --path godot --import && godot --headless --path godot -s res://tools/build_arena_scrap.gd
## Повторный запуск перезаписывает сцену: правки, которые нужно сохранить, вносятся сюда.
##
## Система координат: X вбок, Y вверх, +Z к камере; физика в плоскости XY (z=0 — плоскость кукол). Пол y=0. Ширина 36 м
## (невидимые стены x=±HALF_W), потолок CEIL_Y. Кит — сетка 2 м (snap: опора S/M/L высотой 3/4/6 м, платформа на ней
## origin-ом на H + 1 → ярусы 4 / 5 / 7 м; «3 м» из задания по снапу кита не собирается — настил на опоре 3 м стоит на 4 м).
## ОПОРЫ СТОЯТ ЗА ПЛОСКОСТЬЮ КУКОЛ на z=SUPPORT_Z (коллизия колонны z −2.4..−0.4 кукол не касается): колонна 1 × 3..6 м
## на z=0 была бы стеной, а пролёт между двумя такими стенами под настилом — замкнутым карманом (как кладка «Руин» на z=−0.7).
## Настилы, скат, балка, пол и кучи старта — на z=0 (по ним ходят). Задние ножки настилов стоят на крышках опор, передние
## (z=+0.9) висят перед опорой — с камеры читается как крепление к опоре. Декор с коллизией (рамы, перила, лестницы) — на
## z ≤ −0.65 (тонкие коллизии 0.6 м не доходят до z=−0.3: голова куклы r=0.24).
##
## Слева направо (x), пол из kit_platform_lower (верх y=0, модули 2 м, за стены выходят на 3.5 м — кадр их видит):
##   СТАРТ     x −18…−10   куча пробуждения Scrap_Heap_Medium (по ней ходят) → куча-сюрприз Mystery_Scrap_Heap (тёплый свет,
##                         сундучок; ходибельная) → скат Slope_30 (x −14…−10, 0 → 2 м) с кучей рук Puppet_Limb_Pile под ним;
##                         сзади выброшенные куклы (Broken/Half_Puppet), на заднем плане гора Scrap_Heap_Massive
##   ПЛАТФОРМЫ x −10…−2    опоры S на x −10 / −6 / −2; настилы на 4 м: Platform_Gap (−10…−6, разрыв над пропастью),
##                         Platform_M (−6…−2); балка на цепях Hanging_Beam (верх y=2, x −10…−6) продолжает скат через пропасть;
##                         куча голов Puppet_Head_Pile у правого края пропасти (порог перед краем, головы можно спихнуть);
##                         цепи с крюками под настилом, перила сзади; рамы с флагами-коронами на заднем плане
##   ПРОПАСТЬ  x −9.5…−6.5 («провал в недра», 3 м): дыра в полу под балкой, Area3D DeathZone/Pit с y=−3 (KO kind self — через
##                         площадку), тёплый OmniLight3D снизу без теней, искры GPUParticles3D; дно Bounds/PitBottom на y=−9
##   ЦЕНТР     x −2…+6     открытый пол; пропсы на z=0 (в меру): ящики (один на настиле), бочка, железная бочка, поддон,
##                         брус поперёк разрыва Platform_Gap; свободные куски хлама bit_* (Junk)
##   ВЕРТИКАЛЬ x +6…+16    ярусы-«этажерки» на одной опоре (Platform_End_L + End_R): S x=8 (настил 4 м), M x=12 (5 м),
##                         L x=16 (7 м); лестницы-декор (5 → 8 и 7 → 10), перила, цепи; тележка и большой ящик на полу
##   ВЫХОД     x +16…+18   на верхнем ярусе рама Banner_Frame с большим флагом-короной — «выход наверх» (дверь Мастерской —
##                         следующая волна) и лестница вверх рядом
##   ЗАДНИЙ ПЛАН z −2…−10  вал из куч листа 01 (z≈−2.5, разные: металл, шестерни, цепи, флаги, оружие, доспехи), рамы с флагами,
##                         опоры с мостком (z −4…−5.5), две горы хлама и башня из опор (z −7…−9.5)
##   ПЕРЕДНИЙ ПЛАН z +1.4…+3  вал куч под передней кромкой пола (разрыв у пропасти; вершины на плоскости боя ниже линии
##                         ног — кукол не закрывают) и передний слой параллакса, опущенный на 1 м (LAYER1_Y)
##
## Дерево: Node3D "Scrap" (script scrap.gd)
##   ├── WorldEnvironment "Environment" (assets/environments/scrap_env.tres + DOF дали), DirectionalLight3D "Sun" (тёплое низкое
##   │   солнце сзади-справа, тени, 2 сплита), "Fill" (холодный лилово-синий спереди-слева, без теней), "Rim" (холодный
##   │   контровой сзади-слева, без теней — кромка силуэтов кукол), SpotLight3D "CameraKey" (едет за камерой — scrap.gd; с
##   │   затуханием по расстоянию плоскость кукол светлее заднего плана: контраст головы ореха с фоном +0.02…0.07 → +0.13…0.21)
##   ├── "Parallax": инстанс scenes/arena/parallax_scrap.tscn (layer*_y_offset — подгонка линии земли / переднего хлама)
##   ├── Node3D "Ground" (пол), "Start", "Platforms", "Vertical", "Back", "Front" — компоненты по зонам
##   ├── Node3D "Pit": куча у задней стенки провала Heap_PitWall, OmniLight3D "Glow", GPUParticles3D "Embers" и "Haze"
##   ├── Node3D "Props": физпропсы листа 02 (Breakable и R) — обломки Breakable спавнятся сюда же (узел для обломков)
##   ├── Node3D "Junk": свободные куски bit_* на полу
##   ├── GPUParticles3D "Dust": пыль по всему объёму
##   ├── StaticBody3D "Bounds": стены x=±HALF_W, потолок CEIL_Y, дно пропасти PitBottom, страховочный BackFloor под задником
##   ├── Area3D "DeathZone": Pit (x пропасти, y −8…−3) + страховочный Floor (y −15)
##   └── Node3D "Spawns": Marker3D Spawn0..3 (пол центра ×2, настил Platform_M, нижний ярус вертикали)
extends SceneTree

const OUT := "res://scenes/arena/scrap.tscn"
const SCENE_UID := "uid://scraparena01"
const KIT := "res://scenes/props/scrap/%s.tscn"
const SCRIPT := "res://scenes/arena/scrap.gd"
const PARALLAX := "res://scenes/arena/parallax_scrap.tscn"
const ENV_RES := "res://assets/environments/scrap_env.tres"
const MOTE_TEX := "res://assets/textures/fx/mote.png"

const HALF_W := 18.0            # невидимые стены
const CEIL_Y := 12.0            # невидимый потолок
const SUPPORT_Z := -1.4         # опоры за плоскостью кукол: колонна (глубина 2.0) — z −2.4..−0.4, крышка до −0.37
const RAIL_Z := -0.9            # перила по задней кромке настила (коллизия −1.2..−0.6)
const LADDER_Z := -0.75         # лестницы (коллизия −1.05..−0.45)
const CHAIN_Z := -0.85          # цепи с крюками под задней балкой настила
const DECK_S := 4.0             # настил на Support_S (3 + 1)
const DECK_M := 5.0             # на Support_M (4 + 1)
const DECK_L := 7.0             # на Support_L (6 + 1)
const DECK_UNDER := 0.38        # низ балки настила под поверхностью (узлы −0.38)
const PIT_X0 := -9.5            # пропасть: между модулями пола
const PIT_X1 := -6.5
const PIT_KO_Y := -3.0          # верх зоны KO
const BEAM_Y := 2.0             # верх балки на цепях = верх ската
const FLOOR_X0 := -21.5         # пол заходит за стены: кадр у края видит его в перспективе
const FLOOR_X1 := 21.5
const LAYER1_Y := -1.0          # передний хлам параллакса ниже на 1 м: на любом зуме его кромка под линией пола (ноги кукол
                                # и пропасть видны), под полом — вал куч Front/Heap_Bank

# Свет заката (parallax.png, scenes.png): солнце низко сзади-справа — тёплый контровой и тени вперёд-влево; спереди-слева —
# холодный лилово-синий заполняющий, чтобы лица и грудь кукол (смотрят в +Z) не проваливались в тень.
const SUN_DIR := Vector3(-0.60, -0.45, 0.66)       # направление лучей (к камере и влево)
const SUN_COLOR := Color(1.0, 0.72, 0.48)
const SUN_ENERGY := 2.2
const FILL_DIR := Vector3(0.45, -0.45, -0.77)
const FILL_COLOR := Color(0.62, 0.64, 1.0)
const FILL_ENERGY := 0.85
const RIM_DIR := Vector3(0.55, -0.25, 0.8)          # холодный контровой сзади-слева: кромка силуэтов кукол (ореха) на ржавчине
const RIM_COLOR := Color(0.72, 0.76, 1.0)
const RIM_ENERGY := 0.6
const KEY_COLOR := Color(1.0, 0.93, 0.86)
const KEY_ENERGY := 14.0                           # спот на 10–25 м: энергия с запасом на затухание
const BERM_Y := -0.45                               # вал куч за полом утоплен: за верхом кукол на полу — дымка, а не хлам
const PIT_COLOR := Color(1.0, 0.46, 0.16)
const PIT_ENERGY := 6.0

var arena_root: Node3D
var _scenes: Dictionary = {}
var _names: Dictionary = {}
var _failed := false


func _init() -> void:
	arena_root = Node3D.new()
	arena_root.name = "Scrap"
	arena_root.set_script(load(SCRIPT))
	_environment()
	_parallax()
	_ground()
	_start()
	_platforms()
	_pit()
	_vertical()
	_back()
	_front()
	_props()
	_junk()
	_dust()
	_bounds()
	_spawns()
	if _failed:
		quit(1)
		return
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
		var ps: PackedScene = load(KIT % kind) if ResourceLoader.exists(KIT % kind) else null
		if ps == null:
			push_error("missing component scene " + (KIT % kind) + " — run tools/build_scrap_{kit,props,bodies}_scenes.gd")
			_failed = true
			return null
		_scenes[kind] = ps
	return _scenes[kind]


func _group(name: String, parent: Node = null) -> Node3D:
	var n := Node3D.new()
	n.name = name
	(parent if parent != null else arena_root).add_child(n)
	return n


## Инстанс компонента (origin — как в шапке его builder-а); rot_y — градусы вокруг Y (только малые углы: у модулей кита
## удалены невидимые с камеры задние грани), s — равномерный масштаб (только декор заднего плана).
func _inst(parent: Node, kind: String, name: String, pos: Vector3, rot_y := 0.0, s := 1.0) -> Node3D:
	var ps := _scene(kind)
	if ps == null:
		return Node3D.new()
	var inst: Node3D = ps.instantiate()
	inst.name = _uniq(name)
	inst.position = pos
	if rot_y != 0.0:
		inst.rotation_degrees = Vector3(0, rot_y, 0)
	if s != 1.0:
		inst.scale = Vector3.ONE * s
	parent.add_child(inst)
	return inst


## Ярус-«этажерка»: опора `support` на x (за плоскостью кукол), по обе стороны — концевые платформы End_L / End_R на
## deck_y (стыковые ножки на крышке опоры, свободные торцы в x ∓ 2 со скошенными ногами).
func _shelf(parent: Node, name: String, support: String, x: float, deck_y: float) -> void:
	_inst(parent, support, name + "_Support", Vector3(x, 0.0, SUPPORT_Z))
	_inst(parent, "kit_platform_end_l", name + "_DeckL", Vector3(x - 1.0, deck_y, 0.0))
	_inst(parent, "kit_platform_end_r", name + "_DeckR", Vector3(x + 1.0, deck_y, 0.0))


func _box_shape(parent: Node, name: String, x0: float, x1: float, y0: float, y1: float, z := 0.0, depth := 2.0) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.name = _uniq(name)
	var bs := BoxShape3D.new()
	bs.size = Vector3(x1 - x0, y1 - y0, depth)
	cs.shape = bs
	cs.position = Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, z)
	parent.add_child(cs)
	return cs


func _mote_material(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = colour
	mat.albedo_texture = load(MOTE_TEX)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	return mat


func _ramp(offsets: Array, colours: Array) -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array(offsets)
	grad.colors = PackedColorArray(colours)
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	return ramp


# ---------------------------------------------------------------- layout
## Пол: ряд kit_platform_lower (2 м, верх y=0, низ −0.5) от FLOOR_X0 до края пропасти и от другого края до FLOOR_X1.
func _ground() -> void:
	var g := _group("Ground")
	var x := PIT_X0 - 1.0
	while x - 1.0 >= FLOOR_X0 - 0.01:
		_inst(g, "kit_platform_lower", "Floor", Vector3(x, 0.0, 0.0))
		x -= 2.0
	x = PIT_X1 + 1.0
	while x + 1.0 <= FLOOR_X1 + 0.01:
		_inst(g, "kit_platform_lower", "Floor", Vector3(x, 0.0, 0.0))
		x += 2.0


## Старт: Core просыпается в куче. Слева направо на z=0: куча пробуждения (ходибельная) → куча-сюрприз (сундучок и тёплый
## свет в «пещере», тоже ходибельная) → скат к балке над пропастью; под скатом — куча рук (свободные руки сверху — RigidBody,
## спят до толчка); сзади — выброшенные куклы. Куча голов — у правого края пропасти (см. _platforms).
func _start() -> void:
	var s := _group("Start")
	_inst(s, "bodies_scrap_heap_medium", "Heap_Awakening", Vector3(-17.0, 0.0, 0.0), 8.0)
	_inst(s, "bodies_mystery_scrap_heap", "Heap_Mystery", Vector3(-14.9, 0.0, 0.0), -4.0)
	_inst(s, "kit_slope_30", "Slope", Vector3(-12.0, 0.0, 0.0))
	_inst(s, "bodies_puppet_limb_pile", "Heap_Limbs", Vector3(-11.2, 0.0, 0.0), 4.0)
	_inst(s, "bodies_broken_puppet", "BrokenPuppet", Vector3(-12.6, 0.0, -1.6), 12.0)
	_inst(s, "bodies_half_puppet", "HalfPuppet", Vector3(-16.2, 0.0, -1.5), -10.0)
	# за стартом — «огромная гора хлама»: две вершины, флаг-корона на шесте (часть модели)
	_inst(s, "bodies_scrap_heap_massive", "Heap_Mountain", Vector3(-12.5, -1.2, -9.0), 6.0, 1.5)


## Платформы: опоры S за плоскостью, настилы на 4 м; балка на цепях (верх 2 м) продолжает скат через пропасть, её анкеры
## (±1.7, +2.0) — под половинами Platform_Gap.
func _platforms() -> void:
	var p := _group("Platforms")
	for x in [-10.0, -6.0, -2.0]:
		_inst(p, "kit_support_s", "Support", Vector3(x, 0.0, SUPPORT_Z))
	_inst(p, "kit_platform_gap", "DeckGap", Vector3(-8.0, DECK_S, 0.0))
	_inst(p, "kit_platform_m", "DeckM", Vector3(-4.0, DECK_S, 0.0))
	_inst(p, "kit_hanging_beam", "HangingBeam", Vector3(-8.0, BEAM_Y, 0.0))
	for x in [-3.6, -2.5]:
		_inst(p, "kit_chain_hook", "ChainHook", Vector3(x, DECK_S - DECK_UNDER, CHAIN_Z))
	# куча голов у правого края пропасти: головы (свободные RigidBody) можно спихнуть вниз; сама куча — порог перед краем,
	# кукла, отлетевшая с пола центра влево, упирается в неё, а не сразу падает в пропасть
	_inst(p, "bodies_puppet_head_pile", "Heap_Heads", Vector3(-5.4, 0.0, 0.05), -6.0)
	_inst(p, "kit_railing", "Railing", Vector3(-3.0, DECK_S, RAIL_Z))
	# флаги-короны на рамах сзади: рама-ворота за пропастью, высокая рама за Platform_M
	_inst(p, "kit_wall_frame", "WallFrame", Vector3(-8.0, 0.0, -3.9))
	_inst(p, "kit_banner_frame", "BannerFrame", Vector3(-3.6, 0.0, -3.5))


## Пропасть: дыра в полу (модулей там нет). Внутри у задней стенки — куча хлама (z −2, вершина ≈ −0.3): камера смотрит
## в провал сверху-спереди и видит её, а не дымку параллакса за полом; её освещает тёплый свет снизу (без теней). Над
## провалом — искры и мягкое оранжевое марево (крупные аддитивные пятна): опасность читается на любом зуме.
func _pit() -> void:
	var pit := _group("Pit")
	var cx := (PIT_X0 + PIT_X1) * 0.5
	_inst(pit, "bodies_scrap_heap_medium", "Heap_PitWall", Vector3(cx, -2.0, -2.0), 10.0)
	var glow := OmniLight3D.new()
	glow.name = "Glow"
	glow.position = Vector3(cx, -0.9, -0.3)
	glow.light_color = PIT_COLOR
	glow.light_energy = PIT_ENERGY
	glow.light_indirect_energy = 0.5
	glow.light_specular = 0.3
	glow.omni_range = 4.8
	glow.omni_attenuation = 1.3
	glow.shadow_enabled = false
	pit.add_child(glow)
	var p := GPUParticles3D.new()
	p.name = "Embers"
	p.position = Vector3(cx, -0.6, 0.1)
	p.amount = 110
	p.lifetime = 3.2
	p.preprocess = 3.2
	p.randomness = 0.4
	p.visibility_aabb = AABB(Vector3(-3, -1, -2), Vector3(6, 7, 4))
	var pm := ParticleProcessMaterial.new()
	pm.lifetime_randomness = 0.4
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1.3, 0.2, 0.7)
	pm.direction = Vector3.UP
	pm.spread = 16.0
	pm.initial_velocity_min = 0.7
	pm.initial_velocity_max = 1.7
	pm.gravity = Vector3(0, 0.1, 0)
	pm.damping_min = 0.15
	pm.damping_max = 0.35
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.color_ramp = _ramp([0.0, 0.12, 0.6, 1.0], [Color(3.0, 1.4, 0.45, 0.0), Color(3.0, 1.4, 0.45, 1.0), Color(2.2, 0.6, 0.15, 0.8), Color(1.0, 0.22, 0.05, 0.0)])
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	pm.turbulence_noise_scale = 2.5
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	quad.material = _mote_material(Color(1, 1, 1, 1))
	p.draw_pass_1 = quad
	pit.add_child(p)
	var h := GPUParticles3D.new()
	h.name = "Haze"
	h.position = Vector3(cx, -0.4, -0.2)
	h.amount = 14
	h.lifetime = 4.5
	h.preprocess = 4.5
	h.randomness = 0.5
	h.visibility_aabb = AABB(Vector3(-4, -2, -3), Vector3(8, 7, 6))
	var hm := ParticleProcessMaterial.new()
	hm.lifetime_randomness = 0.3
	hm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	hm.emission_box_extents = Vector3(1.1, 0.2, 0.5)
	hm.direction = Vector3.UP
	hm.spread = 10.0
	hm.initial_velocity_min = 0.2
	hm.initial_velocity_max = 0.45
	hm.gravity = Vector3.ZERO
	hm.scale_min = 0.8
	hm.scale_max = 1.5
	hm.color_ramp = _ramp([0.0, 0.3, 1.0], [Color(1.0, 0.42, 0.12, 0.0), Color(1.0, 0.42, 0.12, 0.16), Color(0.9, 0.3, 0.1, 0.0)])
	h.process_material = hm
	var hq := QuadMesh.new()
	hq.size = Vector2(1.8, 1.8)
	hq.material = _mote_material(Color(1, 1, 1, 1))
	h.draw_pass_1 = hq
	pit.add_child(h)


## Вертикаль: три «этажерки» лесенкой вправо-вверх (4 / 5 / 7 м), лестницы и перила по задней кромке, цепи; выход наверх —
## рама с большим флагом-короной на верхнем ярусе и лестница из кадра вверх.
func _vertical() -> void:
	var v := _group("Vertical")
	_shelf(v, "Tier1", "kit_support_s", 8.0, DECK_S)
	_shelf(v, "Tier2", "kit_support_m", 12.0, DECK_M)
	_shelf(v, "Tier3", "kit_support_l", 16.0, DECK_L)
	_inst(v, "kit_railing", "Railing", Vector3(9.1, DECK_S, RAIL_Z))
	_inst(v, "kit_railing", "Railing", Vector3(10.9, DECK_M, RAIL_Z))
	_inst(v, "kit_ladder", "Ladder", Vector3(13.5, DECK_M, LADDER_Z))
	_inst(v, "kit_ladder", "LadderUp", Vector3(14.8, DECK_L, LADDER_Z))
	_inst(v, "kit_chain_hook", "ChainHook", Vector3(13.4, DECK_M - DECK_UNDER, CHAIN_Z))
	_inst(v, "kit_chain_hook", "ChainHook", Vector3(17.4, DECK_L - DECK_UNDER, CHAIN_Z))
	_inst(v, "kit_banner_frame", "ExitBanner", Vector3(16.6, DECK_L, -0.65))


## Задний план: вал куч листа 01 вдоль задней кромки пола (z≈−2.5, чуть утоплены), рамы с флагами и опоры с мостком
## (z −4…−5.5), дальние горы хлама и башня из опор (z −7…−9.5). Коллизии задника плоскости кукол не касаются.
func _back() -> void:
	var b := _group("Back")
	var berm := [
		["bodies_chain_heap", -19.4, -2.4, 10.0],
		["bodies_scrap_heap_medium", -16.6, -2.9, -12.0],
		["bodies_cloth_scrap_heap", -13.6, -2.7, 6.0],
		["bodies_broken_weapons_pile", -10.9, -2.5, -8.0],
		["bodies_scrap_heap_medium", -8.0, -2.8, 4.0],
		["bodies_gear_heap", -5.0, -2.5, -10.0],
		["bodies_scrap_heap_small", -2.3, -2.3, 14.0],
		["bodies_broken_armor_heap", 0.6, -2.6, -6.0],
		["bodies_metal_parts_heap", 3.5, -2.4, 8.0],
		["bodies_scrap_heap_medium", 6.5, -2.9, -4.0],
		["bodies_chain_heap", 9.7, -2.4, 12.0],
		["bodies_cloth_scrap_heap", 12.3, -2.7, -10.0],
		["bodies_scrap_heap_medium", 15.2, -2.9, 6.0],
		["bodies_broken_weapons_pile", 18.6, -2.5, -6.0],
	]
	for h in berm:
		_inst(b, h[0], "Heap_Berm", Vector3(h[1], BERM_Y, h[2]), h[3])
	# рамы с флагами и опоры с мостком
	_inst(b, "kit_banner_frame", "BannerFrame", Vector3(-15.6, 0.0, -4.4))
	_inst(b, "kit_support_l", "SupportBack", Vector3(-1.0, 0.0, -5.2))
	_inst(b, "kit_banner_frame", "BannerFrame", Vector3(-1.0, 6.0, -5.2))
	for x in [3.0, 7.0]:
		_inst(b, "kit_support_m", "SupportBack", Vector3(x, 0.0, -5.6))
	_inst(b, "kit_platform_m", "BridgeBack", Vector3(5.0, DECK_M, -5.6))
	_inst(b, "kit_railing", "RailingBack", Vector3(5.0, DECK_M, -6.5))
	_inst(b, "kit_chain_hook", "ChainHookBack", Vector3(5.6, DECK_M - DECK_UNDER, -5.6))
	_inst(b, "kit_banner_frame", "BannerFrame", Vector3(10.2, 0.0, -4.3))
	_inst(b, "kit_wall_frame", "WallFrameBack", Vector3(14.2, 0.0, -4.8))
	# даль: гора справа и башня из опор с флагом над всем уровнем (читается и на полном отъезде камеры)
	_inst(b, "bodies_scrap_heap_massive", "Heap_MountainR", Vector3(8.5, -1.3, -9.5), -8.0, 1.15)
	_inst(b, "kit_support_l", "TowerFar", Vector3(-6.0, -0.6, -9.6))
	_inst(b, "kit_support_l", "TowerFar", Vector3(-6.0, 5.4, -9.6))
	_inst(b, "kit_banner_frame", "TowerFarBanner", Vector3(-6.0, 11.4, -9.6))


## Передний план. Вал под передней кромкой пола (z≈1.5, вершины на y≈0 — на плоскости боя ниже линии ног): прячет пустоту
## под модулями пола, когда передний слой параллакса опущен (layer1_y_offset), у пропасти — разрыв, чтобы свет и искры
## были видны спереди; в тени пола он тёмный, крайние кучи (x ±17…±20.6) — тёмный хлам у нижних углов кадра.
## Отдельные кучи-силуэты у углов на z≈2.7 пробовались (v1): светлый грунт куч под заполняющим светом читался бледным
## пятном, а не тёмным силуэтом, — убраны; тёмную кромку кадра снизу даёт передний слой параллакса.
func _front() -> void:
	var f := _group("Front")
	var bank := [
		["bodies_scrap_heap_medium", -20.0, -1.6, 1.6, 10.0],
		["bodies_metal_parts_heap", -17.3, -0.8, 1.4, -8.0],
		["bodies_scrap_heap_medium", -14.8, -1.62, 1.6, -14.0],
		["bodies_broken_weapons_pile", -12.2, -0.95, 1.4, 6.0],
		["bodies_scrap_heap_small", -10.5, -0.95, 1.5, 12.0],
		["bodies_scrap_heap_small", -5.5, -0.95, 1.5, -10.0],
		["bodies_scrap_heap_medium", -3.3, -1.6, 1.6, 6.0],
		["bodies_chain_heap", -0.6, -0.66, 1.4, -6.0],
		["bodies_scrap_heap_medium", 2.0, -1.62, 1.6, -12.0],
		["bodies_metal_parts_heap", 4.7, -0.8, 1.4, 8.0],
		["bodies_scrap_heap_medium", 7.3, -1.6, 1.6, 4.0],
		["bodies_broken_armor_heap", 10.0, -1.0, 1.4, -8.0],
		["bodies_scrap_heap_medium", 12.6, -1.62, 1.6, 14.0],
		["bodies_gear_heap", 15.2, -0.98, 1.4, -4.0],
		["bodies_scrap_heap_medium", 17.8, -1.6, 1.6, -6.0],
		["bodies_metal_parts_heap", 20.6, -0.8, 1.4, 10.0],
	]
	for h in bank:
		_inst(f, h[0], "Heap_Bank", Vector3(h[1], h[2], h[3]), h[4])


## Физпропсы листа 02 на z=0 (центр — «в меру»: есть что швырять, но пол открыт) + брус поперёк разрыва Platform_Gap
## (столкнуть в пропасть). Breakable-обломки спавнятся в этот же узел.
func _props() -> void:
	var p := _group("Props")
	var items := [
		["prop_wooden_crate", "Crate", -1.0, 0.0],
		["prop_reinforced_crate", "ReinforcedCrate", -1.05, 1.02],
		["prop_wooden_crate", "Crate", -5.0, DECK_S],
		["prop_wooden_pallet", "Pallet", 2.3, 0.0],
		["prop_wooden_barrel", "Barrel", 5.9, 0.0],
		["prop_metal_barrel", "MetalBarrel", 6.9, 0.0],
		["prop_wooden_beam", "Beam", -8.0, DECK_S],
		["prop_junk_cart", "JunkCart", 10.9, 0.0],
		["prop_large_shipping_crate", "ShippingCrate", 16.6, 0.0],
		["prop_wooden_barrel", "Barrel", 11.4, DECK_M],
	]
	for it in items:
		_inst(p, it[0], it[1], Vector3(it[2], it[3] + 0.02, 0.0))


## Свободный хлам на плоскости боя: несколько кусков bit_* (головы, шестерня, доска, шлем) — толкаются, не мешают.
func _junk() -> void:
	var j := _group("Junk")
	var bits := [
		["bit_doll_head_cracked", -1.9, 0.15],
		["bit_gear_medium", 3.4, 0.25],
		["bit_scrap_board", -2.9, 0.04],
		["bit_helmet", 9.2, 0.13],
		["bit_doll_head_sad", 13.2, DECK_M + 0.15],
		["bit_shield_crown", 17.3, DECK_L + 0.37],
	]
	for b in bits:
		_inst(j, b[0], "Bit", Vector3(b[1], b[2] + 0.02, 0.0))


func _dust() -> void:
	var p := GPUParticles3D.new()
	p.name = "Dust"
	p.position = Vector3(0, 5.0, 0.6)
	p.amount = 500
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.randomness = 0.3
	p.visibility_aabb = AABB(Vector3(-20, -6, -4), Vector3(40, 13, 8))
	var pm := ParticleProcessMaterial.new()
	pm.lifetime_randomness = 0.4
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(18.0, 4.8, 2.4)
	pm.direction = Vector3(-1, 0.2, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.04
	pm.initial_velocity_max = 0.14
	pm.gravity = Vector3(0, -0.005, 0)
	pm.damping_min = 0.05
	pm.damping_max = 0.2
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.color_ramp = _ramp([0.0, 0.2, 0.8, 1.0], [Color(1, 0.8, 0.6, 0), Color(1, 0.8, 0.6, 0.5), Color(1, 0.8, 0.6, 0.5), Color(1, 0.8, 0.6, 0)])
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.06
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	quad.material = _mote_material(Color(1, 0.84, 0.66, 0.35))
	p.draw_pass_1 = quad
	arena_root.add_child(p)


func _bounds() -> void:
	var b := StaticBody3D.new()
	b.name = "Bounds"
	arena_root.add_child(b)
	_box_shape(b, "WallL", -HALF_W - 1.0, -HALF_W, -10.0, 30.0, 0.0, 8.0)
	_box_shape(b, "WallR", HALF_W, HALF_W + 1.0, -10.0, 30.0, 0.0, 8.0)
	_box_shape(b, "Ceiling", -HALF_W - 1.0, HALF_W + 1.0, CEIL_Y, CEIL_Y + 1.0, 0.0, 8.0)
	# дно пропасти: всё, что упало (оружие, пропсы, части KO-нутой куклы), ложится здесь, а не падает бесконечно
	_box_shape(b, "PitBottom", PIT_X0 - 1.5, PIT_X1 + 1.5, -9.5, -9.0, 0.0, 6.0)
	# под задним планом (z −12…−1.3): спящие куски на кучах вала (SR), если их разбудят, падают сюда (ниже видимой земли)
	_box_shape(b, "BackFloor", -HALF_W - 4.0, HALF_W + 4.0, -2.9, -2.5, -6.65, 10.7)
	var dz := Area3D.new()
	dz.name = "DeathZone"
	dz.monitoring = true
	arena_root.add_child(dz)
	# зона KO не касается ни пола (низ модулей −0.5), ни дна (−9): иначе StaticBody сам попадает в зону
	_box_shape(dz, "Pit", PIT_X0 + 0.1, PIT_X1 - 0.1, -8.0, PIT_KO_Y, 0.0, 6.0)
	_box_shape(dz, "Floor", -HALF_W - 2.0, HALF_W + 2.0, -15.0, -14.0, 0.0, 8.0)


func _spawns() -> void:
	var holder := _group("Spawns")
	var pts := [Vector3(0.6, 0.05, 0), Vector3(4.4, 0.05, 0), Vector3(-3.4, DECK_S + 0.05, 0), Vector3(8.9, DECK_S + 0.05, 0)]
	for i in pts.size():
		var m := Marker3D.new()
		m.name = "Spawn%d" % i
		m.position = pts[i]
		holder.add_child(m)


func _parallax() -> void:
	var ps: PackedScene = load(PARALLAX) if ResourceLoader.exists(PARALLAX) else null
	if ps == null:
		push_error("нет " + PARALLAX)
		_failed = true
		return
	var n: Node3D = ps.instantiate()
	n.name = "Parallax"
	n.set("layer2_y_offset", -0.2)
	n.set("layer1_y_offset", LAYER1_Y)
	arena_root.add_child(n)


func _environment() -> void:
	var env := WorldEnvironment.new()
	env.name = "Environment"
	var e: Environment = load(ENV_RES) if ResourceLoader.exists(ENV_RES) else null
	if e == null:
		push_error("нет пресета " + ENV_RES)
		_failed = true
		return
	env.environment = e
	# DOF дали (как ruins_camera.tres): мягкий разм параллакса — полосы листа увеличены ×3–4
	var ca := CameraAttributesPractical.new()
	ca.dof_blur_far_enabled = true
	ca.dof_blur_far_distance = 24.0
	ca.dof_blur_far_transition = 40.0
	ca.dof_blur_amount = 0.05
	env.camera_attributes = ca
	arena_root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.basis = Basis.looking_at(SUN_DIR.normalized(), Vector3.UP)
	sun.position = Vector3(0, 10, 0)
	sun.light_color = SUN_COLOR
	sun.light_energy = SUN_ENERGY
	sun.light_indirect_energy = 1.0
	sun.light_angular_distance = 0.8
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.5
	sun.shadow_blur = 1.2
	# 2 сплита (как «Мастерская»): камера боя в 10–24 м, вся арена во втором сплите
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.3
	sun.directional_shadow_max_distance = 50.0
	arena_root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.basis = Basis.looking_at(FILL_DIR.normalized(), Vector3.UP)
	fill.position = Vector3(0, 8, 10)
	fill.light_color = FILL_COLOR
	fill.light_energy = FILL_ENERGY
	fill.light_indirect_energy = 0.0
	fill.light_specular = 0.4
	fill.shadow_enabled = false
	arena_root.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.name = "Rim"
	rim.basis = Basis.looking_at(RIM_DIR.normalized(), Vector3.UP)
	rim.position = Vector3(0, 8, -10)
	rim.light_color = RIM_COLOR
	rim.light_energy = RIM_ENERGY
	rim.light_indirect_energy = 0.0
	rim.light_specular = 0.6
	rim.shadow_enabled = false
	arena_root.add_child(rim)
	# «ключ камеры»: прожектор без теней едет за активной камерой (scrap.gd) и светит в плоскость кукол; с затуханием по
	# расстоянию плоскость боя (D = 10…25 м) светлее заднего плана (D + 3…10 м) — орех не сливается с ржавчиной
	var key := SpotLight3D.new()
	key.name = "CameraKey"
	key.position = Vector3(0, 6, 14)
	key.light_color = KEY_COLOR
	key.light_energy = KEY_ENERGY
	key.light_indirect_energy = 0.0
	key.light_specular = 0.25
	key.light_volumetric_fog_energy = 0.0
	key.spot_range = 45.0
	key.spot_attenuation = 1.6
	key.spot_angle = 40.0
	key.spot_angle_attenuation = 0.6
	key.shadow_enabled = false
	arena_root.add_child(key)
