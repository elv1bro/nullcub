## Builder арены «Свалка» v3 (биом 1 THE SCRAP — первый уровень: Core игрока просыпается в куче хлама на дне Башни;
## docs/plan-demo/BIOMES.md §1, LORE.md, композиция — docs/refs/biomes/01-scrap/scenes.png, свет — parallax.png, механизмы —
## sheet-04.png и kit-02.png): собирает res://scenes/arena/scrap.tscn ИЗ КОМПОНЕНТНЫХ СЦЕН scenes/props/scrap/*.tscn — модульный
## кит kit_* (tools/blender/scrap_kit.py → tools/build_scrap_kit_scenes.gd), кучи и куски листа 01 bodies_* / bit_* (scrap_bodies.py
## → build_scrap_bodies_scenes.gd), физпропсы листа 02 prop_* (scrap_props.py → build_scrap_props_scenes.gd), механизмы листа 04
## machine_* и цепи deco_chain_long, лут loot_* (scrap_machines.py → build_scrap_machines_scenes.gd). Своих мешей нет. Каждый
## компонент — PackedScene.instantiate() с owner = корень арены; внутренности инстансов принадлежат своим сценам (в scrap.tscn
## сохраняются только позиция/масштаб/свойства корня инстанса). Ничего не строится в _ready(); поведение — scenes/arena/scrap.gd
## и скрипты механизмов.
## Запуск: godot --headless --path godot --import && godot --headless --path godot -s res://tools/build_arena_scrap.gd
## Повторный запуск перезаписывает сцену: правки, которые нужно сохранить, вносятся сюда.
##
## v3 (просторнее, автор: «предметы должны быть, но с интересной механикой; разным предметам разный вес»): центр — открытый
## воздух (пол и висящий островок), платформы — по краям, опоры и рамы — только за плоскостью боя, флагов и рам в кадре меньше,
## задний план дальше, потолок выше (14 м — верх arena_bounds: диапазон камеры docs/plan-demo/PARALLAX.md не меняется: зум
## z 10…24, y камеры 2.5…10, arena_bounds x ±18). Четыре механизма с циклом OFF → WARNING → ACTIVE → COOLDOWN, пропсы по весу,
## лут из разбитых ящиков и бочек (scrap.gd).
##
## Система координат: X вбок, Y вверх, +Z к камере; физика в плоскости XY (z=0 — плоскость кукол). Пол y=0. Ширина 36 м
## (невидимые стены x=±HALF_W), потолок CEIL_Y. Кит — сетка 2 м (snap: опора S/M/L высотой 3/4/6 м, платформа на ней
## origin-ом на H + 1 → ярусы 4 / 5 / 7 м).
## ОПОРЫ СТОЯТ ЗА ПЛОСКОСТЬЮ БОЯ на z=SUPPORT_Z: коллизия колонны (глубина 2.0) — z −2.7…−0.7, ящик глубиной 1 м (z ±0.5) её не
## касается (tests/scrap_machines_probe: коллизии опор, рам, перил, лестниц и заднего плана не заходят в |z| < 0.6). Настилы,
## скат, балки на цепях, пол и кучи старта — на z=0 (по ним ходят). Задние ножки настилов стоят на крышках опор (крышка 2.06 по
## глубине: до z −0.67), передние (z=+0.9) висят перед опорой. Декор с коллизией (перила, лестницы, рама выхода) — z ≤ −1.05
## (тонкие коллизии 0.6 м: −1.35…−0.75).
##
## Слева направо (x), пол из kit_platform_lower (верх y=0, модули 2 м, за стены выходят на 3.5 м — кадр их видит):
##   СТАРТ      x −18…−10   куча пробуждения Heap_Awakening (ходибельная) → куча-сюрприз Heap_Mystery (тёплый свет, сундучок)
##                          → скат Slope_30 (x −14…−10, 0 → 2 м) с кучей рук под ним; сзади выброшенные куклы, гора хлама;
##                          над стартом — уступ Ledge на 5 м (опора M x=−16, x −18…−14) с кучей голов (спихнуть вниз)
##   ПРОПАСТЬ   x −9.5…−6.5 («провал в недра», 3 м): балка на цепях PitBeam (верх y=2, x −10…−6) продолжает скат, цепи — вверх
##                          из кадра (deco_chain_long); Area3D DeathZone/Pit с y=−3 (KO kind self — через площадку), тёплый
##                          свет снизу, искры, марево; дно Bounds/PitBottom на y=−9
##   ЦЕНТР      x −6.5…+10  открытый пол: у края пропасти — большой ящик ShippingCrate 80 кг (препятствие, столкнуть в провал
##                          тяжело); паровой клапан SteamVent x=−2.8; над ним высоко — раструб желоба Chute (x −6, y 11);
##                          спавны P1 x 0.6 / P2 x 4.4 (как куклы в playground_scrap.tscn); висящий островок Island
##                          (балка на цепях, верх y 5.2, x 0.5…4.5) — спавн 2 и бочка сверху; магнит на цепи Magnet (подвес x 7.4, y 12.8, полюс y ≈ 3.6, качка ±11°:
##                          x 5.65…9.15) над железной бочкой 40 кг, рядом тележка 30 кг; лёгкие ящики/бочки у пола — метать
##   ПРЕСС      x 10.35…12.85  пресс Press (ползун x 10.6…12.6, низ 3.3 м; станина за плоскостью) с ящиком на наковальне —
##                          первый удар ломает его и роняет лут
##   ПРАВЫЙ КРАЙ x 13…18    ярусы на опорах: R1 на 4 м (опора S x=15, x 13…17) — спавн 3; R2 на 7 м (опора L x=16.8,
##                          x 14.8…18.8) с рамой выхода за плоскостью; лестница R1 → R2 и перила — за плоскостью
##   ЗАДНИЙ ПЛАН z −3…−12   вал из куч листа 01 (z −3.4…−4.2, утоплен, в центре ниже), дальние горы; рамы, мостки и башни —
##                          только в параллаксе
##   ПЕРЕДНИЙ ПЛАН z +1.4…+3  вал куч под передней кромкой пола (разрыв у пропасти) и передний слой параллакса (LAYER1_Y)
##
## Пропсы по весу (tools/build_scrap_props_scenes.gd, классы захвата ArmAssist): лёгкие ≤ 15 кг (ящик 10, бочка 15 — летят) у пола
## и на островке; средние (усиленный ящик 20, тележка 30, железная бочка 40 — тащатся); тяжёлый — большой ящик 80 (не поднять).
## Железные пропсы и куски — meta material = "iron" (тянет магнит), деревянные — "wood".
##
## Дерево: Node3D "Scrap" (script scrap.gd)
##   ├── WorldEnvironment "Environment" (assets/environments/scrap_env.tres + DOF дали), DirectionalLight3D "Sun", "Fill", "Rim",
##   │   SpotLight3D "CameraKey" (едет за камерой — scrap.gd)
##   ├── "Parallax": инстанс PARALLAX (layer*_y_offset — подгонка линии земли / переднего хлама)
##   ├── Node3D "Ground" (пол), "Start", "Platforms" (пропасть, островок, края), "Back", "Front" — компоненты по зонам
##   ├── Node3D "Pit": куча у задней стенки провала Heap_PitWall, OmniLight3D "Glow", GPUParticles3D "Embers" и "Haze"
##   ├── Node3D "Machines": Magnet, SteamVent, Press, Chute (machine_*.tscn; фазы циклов разнесены phase_offset_s)
##   ├── Node3D "Props": физпропсы листа 02 (Breakable и R) — обломки Breakable спавнятся сюда же; первые два — Crate и
##   │   ReinforcedCrate (их позиции переопределяет scenes/playground_arm.tscn)
##   ├── Node3D "Junk": свободные куски bit_* (и куски, высыпанные желобом), "Loot": лут из разбитых пропсов
##   ├── GPUParticles3D "Dust": пыль по всему объёму
##   ├── StaticBody3D "Bounds": стены x=±HALF_W, потолок CEIL_Y, дно пропасти PitBottom, страховочный BackFloor под задником
##   ├── Area3D "DeathZone": Pit (x пропасти, y −8…−3) + страховочный Floor (y −15)
##   ├── Node3D "Spawns": Marker3D Spawn0..3 (пол центра ×2, островок, ярус R1)
##   └── CanvasLayer "LootCounter" (scenes/ui/run_inventory_counter.gd): счётчик материалов RunInventory в правом нижнем углу
extends SceneTree

const OUT := "res://scenes/arena/scrap.tscn"
const SCENE_UID := "uid://scraparena01"
const KIT := "res://scenes/props/scrap/%s.tscn"
const SCRIPT := "res://scenes/arena/scrap.gd"
const PARALLAX := "res://scenes/arena/parallax_scrap_scatter.tscn"  # фон из запечённых 3D-конструкций; v2 (слои картинок) — parallax_scrap_v2.tscn, v1 (полосы листа) — parallax_scrap.tscn
const ENV_RES := "res://assets/environments/scrap_env.tres"
const MOTE_TEX := "res://assets/textures/fx/mote.png"

const HALF_W := 18.0            # невидимые стены
const CEIL_Y := 14.0            # невидимый потолок = верх arena_bounds (y −6 + 20): камера его не меняет
const SUPPORT_Z := -1.7         # опоры за плоскостью боя: колонна (глубина 2.0) — z −2.7..−0.7, крышка (2.06) до −0.67
const RAIL_Z := -1.05           # перила по задней кромке настила (коллизия −1.35..−0.75)
const LADDER_Z := -1.05         # лестницы (коллизия −1.35..−0.75)
const FRAME_Z := -1.3           # рама выхода на R2 (коллизия −1.6..−1.0)
const CHAIN_Z := -0.95          # цепи с крюками под задней балкой настила (без коллизии)
const DECK_S := 4.0             # настил на Support_S (3 + 1)
const DECK_M := 5.0             # на Support_M (4 + 1)
const DECK_L := 7.0             # на Support_L (6 + 1)
const DECK_UNDER := 0.38        # низ балки настила под поверхностью (узлы −0.38)
const PIT_X0 := -9.5            # пропасть: между модулями пола
const PIT_X1 := -6.5
const PIT_KO_Y := -3.0          # верх зоны KO
const BEAM_Y := 2.0             # верх балки на цепях над пропастью = верх ската
const ISLAND_X := 2.5           # висящий островок (балка на цепях) в центре: x 0.5…4.5
const ISLAND_Y := 5.2
const HANG_ANCHOR := 2.0        # анкеры цепей балки над её верхом (kit_hanging_beam Anchor_L/R: ±1.7, +2.0)
const CHAIN_TOP := 17.4         # цепи подвесов уходят выше кадра: полный отъезд камеры видит до y ≈ 16.8
const LEDGE_X := -16.0          # уступ над стартом (опора M): настил на 5 м, x −18…−14
const R1_X := 15.0              # правый ярус R1: опора S, настил на 4 м, x 13…17
const R2_X := 16.8              # правый ярус R2: опора L, настил на 7 м, x 14.8…18.8
const MAGNET_PIVOT := Vector3(7.4, 12.8, 0.0)      # точка подвеса маятника (цепь 8 м: полюс y ≈ 3.6, диск до 4.8)
## Качка ±11°: полюс x 5.65…9.15, диск (r 0.78) не заходит ни на островок (x ≤ 4.5), ни на пресс (x ≥ 10.3).
const MAGNET_SWING := 11.0
const VENT_X := -2.8
const PRESS_X := 11.6
const CHUTE_MOUTH := Vector3(-6.0, 11.0, 0.0)
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
const BERM_CENTER_Y := -0.9                         # в центре (за полом боя) — ещё ниже: за куклами дальний фон
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
	_back()
	_front()
	_machines()
	_props()
	_junk()
	_group("Loot")
	_dust()
	_bounds()
	_spawns()
	_loot_counter()
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
## спят до толчка); сзади — выброшенные куклы; над стартом — уступ на 5 м (опора M за плоскостью) с кучей голов.
func _start() -> void:
	var s := _group("Start")
	_inst(s, "bodies_scrap_heap_medium", "Heap_Awakening", Vector3(-17.0, 0.0, 0.0), 8.0)
	_inst(s, "bodies_mystery_scrap_heap", "Heap_Mystery", Vector3(-14.9, 0.0, 0.0), -4.0)
	_inst(s, "kit_slope_30", "Slope", Vector3(-12.0, 0.0, 0.0))
	_inst(s, "bodies_puppet_limb_pile", "Heap_Limbs", Vector3(-11.2, 0.0, 0.0), 4.0)
	_inst(s, "bodies_broken_puppet", "BrokenPuppet", Vector3(-12.6, 0.0, -1.7), 12.0)
	_inst(s, "bodies_half_puppet", "HalfPuppet", Vector3(-16.2, 0.0, -1.7), -10.0)
	_shelf(s, "Ledge", "kit_support_m", LEDGE_X, DECK_M)
	_inst(s, "kit_railing", "Railing", Vector3(LEDGE_X - 0.9, DECK_M, RAIL_Z))
	_inst(s, "kit_chain_hook", "ChainHook", Vector3(LEDGE_X + 1.4, DECK_M - DECK_UNDER, CHAIN_Z))
	# куча голов на уступе: головы (свободные RigidBody) можно спихнуть вниз, на кучи старта
	_inst(s, "bodies_puppet_head_pile", "Heap_Heads", Vector3(LEDGE_X - 0.5, DECK_M, 0.05), -6.0)
	# за стартом — «огромная гора хлама»: две вершины, флаг-корона на шесте (часть модели)
	_inst(s, "bodies_scrap_heap_massive", "Heap_Mountain", Vector3(-14.0, -2.0, -12.5), 6.0, 1.5)


## Платформы — только по краям и на цепях: балка над пропастью (верх 2 м, продолжает скат), висящий островок в центре (балка
## на цепях, верх ISLAND_Y) — цепи обоих уходят вверх из кадра (deco_chain_long от анкеров балки); порог у правого края
## пропасти — большой ящик (Props/ShippingCrate); правый край — ярусы R1 (4 м) и R2 (7 м) на опорах за плоскостью, перила и
## лестница — за плоскостью, рама выхода — на R2 за плоскостью.
func _platforms() -> void:
	var p := _group("Platforms")
	_inst(p, "kit_hanging_beam", "PitBeam", Vector3(-8.0, BEAM_Y, 0.0))
	_chains_up(p, "PitChain", -8.0, BEAM_Y + HANG_ANCHOR)
	_inst(p, "kit_hanging_beam", "Island", Vector3(ISLAND_X, ISLAND_Y, 0.0))
	_chains_up(p, "IslandChain", ISLAND_X, ISLAND_Y + HANG_ANCHOR)
	# правый край
	_shelf(p, "R1", "kit_support_s", R1_X, DECK_S)
	_shelf(p, "R2", "kit_support_l", R2_X, DECK_L)
	_inst(p, "kit_railing", "Railing", Vector3(R1_X - 1.1, DECK_S, RAIL_Z))
	_inst(p, "kit_railing", "Railing", Vector3(R2_X + 0.9, DECK_L, RAIL_Z))
	_inst(p, "kit_ladder", "LadderUp", Vector3(R1_X + 1.2, DECK_S, LADDER_Z))
	_inst(p, "kit_chain_hook", "ChainHook", Vector3(R1_X + 1.4, DECK_S - DECK_UNDER, CHAIN_Z))
	_inst(p, "kit_banner_frame", "ExitBanner", Vector3(R2_X + 0.6, DECK_L, FRAME_Z))


## Две цепи 2-метровыми модулями от анкеров балки на цепях (x ± 1.7, y_anchor) вверх до CHAIN_TOP.
func _chains_up(parent: Node, name: String, x: float, y_anchor: float) -> void:
	for sx in [-1.7, 1.7]:
		var top := y_anchor + 2.0
		while top - 2.0 < CHAIN_TOP:
			_inst(parent, "deco_chain_long", name, Vector3(x + sx, top, 0.0))
			top += 2.0


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


## Задний план — дальше и тише, чем в v1: вал куч листа 01 вдоль задней кромки пола отодвинут (z −3.2…−4.2) и утоплен; в центре
## (за полом боя, x −4…10) — низкие кучи глубже (BERM_CENTER_Y), чтобы за куклами на полу был дальний фон, а не хлам; рам,
## флагов, мостков и башен из опор в 3D нет — даль целиком даёт параллакс; горы хлама — по краям, z −12.5…−13. Коллизии задника плоскости
## боя не касаются (|z| ≥ 2.6).
func _back() -> void:
	var b := _group("Back")
	var berm := [
		["bodies_chain_heap", -19.4, -3.4, 10.0, BERM_Y],
		["bodies_scrap_heap_medium", -16.6, -3.8, -12.0, BERM_Y],
		["bodies_cloth_scrap_heap", -13.6, -3.6, 6.0, BERM_Y],
		["bodies_broken_weapons_pile", -10.9, -3.4, -8.0, BERM_Y],
		["bodies_scrap_heap_medium", -8.0, -3.8, 4.0, BERM_Y],
		["bodies_gear_heap", -5.0, -3.6, -10.0, BERM_Y],
		["bodies_scrap_heap_small", -2.3, -4.2, 14.0, BERM_CENTER_Y],
		["bodies_metal_parts_heap", 0.9, -4.2, -6.0, BERM_CENTER_Y],
		["bodies_scrap_heap_small", 4.0, -4.2, 8.0, BERM_CENTER_Y],
		["bodies_broken_armor_heap", 7.2, -4.2, -4.0, BERM_CENTER_Y],
		["bodies_chain_heap", 10.2, -3.6, 12.0, BERM_Y],
		["bodies_cloth_scrap_heap", 12.8, -3.6, -10.0, BERM_Y],
		["bodies_scrap_heap_medium", 15.4, -3.8, 6.0, BERM_Y],
		["bodies_broken_weapons_pile", 18.6, -3.4, -6.0, BERM_Y],
	]
	for h in berm:
		_inst(b, h[0], "Heap_Berm", Vector3(h[1], h[4], h[2]), h[3])
	# даль: гора хлама справа, за ярусами (за полом боя в центре — только параллакс: куклы читаются на нём, а не на куче)
	_inst(b, "bodies_scrap_heap_massive", "Heap_MountainR", Vector3(15.0, -2.0, -13.0), -8.0, 1.15)


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


## Механизмы листа 04 (machine_*.tscn, поведение — scenes/props/scrap/machines/): циклы разнесены phase_offset_s — после отсчёта
## (3 с) первым бьёт пресс (ящик на наковальне → лут), потом включается магнит, пар, желоб. Желоб сыплет куски в Junk.
func _machines() -> void:
	var m := _group("Machines")
	var mag := _inst(m, "machine_magnet", "Magnet", MAGNET_PIVOT)
	mag.set("phase_offset_s", 1.0)
	mag.set("swing_deg", MAGNET_SWING)
	var vent := _inst(m, "machine_steam_vent", "SteamVent", Vector3(VENT_X, 0.0, 0.0))
	vent.set("phase_offset_s", 0.0)
	var press := _inst(m, "machine_press", "Press", Vector3(PRESS_X, 0.0, 0.0))
	press.set("phase_offset_s", 1.5)
	var chute := _inst(m, "machine_chute", "Chute", CHUTE_MOUTH)
	chute.set("phase_offset_s", 4.0)
	chute.set("junk_path", NodePath("../../Junk"))


## Физпропсы листа 02 на z=0 по весу (центр открыт): лёгкие ящики и бочки у пола и на островке — метать; средние (усиленный
## ящик, тележка, железная бочка под магнитом) — тащатся; тяжёлый большой ящик у края пропасти — препятствие. Ящик на наковальне
## пресса — первый удар ломает его. Breakable-обломки спавнятся в этот же узел. Первые два — Crate и ReinforcedCrate (пути
## узлов переопределяет scenes/playground_arm.tscn). material — для магнита.
func _props() -> void:
	var p := _group("Props")
	var items := [
		["prop_wooden_crate", "Crate", -0.9, 0.0, "wood"],
		["prop_reinforced_crate", "ReinforcedCrate", -0.95, 1.02, "wood"],
		["prop_wooden_barrel", "Barrel", 9.35, 0.0, "wood"],
		["prop_junk_cart", "JunkCart", 5.7, 0.0, "wood"],
		["prop_metal_barrel", "MetalBarrel", 7.6, 0.0, "iron"],
		["prop_wooden_crate", "CrateAnvil", PRESS_X - 0.2, 0.12, "wood"],
		["prop_wooden_crate", "Crate", 13.7, 0.0, "wood"],
		["prop_wooden_barrel", "Barrel", ISLAND_X + 1.4, ISLAND_Y, "wood"],
		["prop_large_shipping_crate", "ShippingCrate", -5.0, 0.0, "wood"],
		["prop_metal_barrel_dented", "MetalBarrel", R1_X + 1.3, DECK_S, "iron"],
	]
	for it in items:
		var n := _inst(p, it[0], it[1], Vector3(it[2], it[3] + 0.02, 0.0))
		n.set_meta("material", it[4])


## Свободный хлам на плоскости боя: несколько кусков bit_* — толкаются, не мешают; железные (meta material) тянет магнит.
func _junk() -> void:
	var j := _group("Junk")
	var bits := [
		["bit_doll_head_cracked", -1.9, 0.15, "wood"],
		["bit_gear_medium", 8.55, 0.25, "iron"],
		["bit_scrap_board", -3.9, 0.04, "wood"],
		["bit_helmet", 6.9, 0.13, "iron"],
		["bit_bolt", 8.2, 0.1, "iron"],
		["bit_doll_head_sad", R1_X - 0.8, DECK_S + 0.15, "wood"],
		["bit_shield_crown", R2_X + 0.2, DECK_L + 0.37, "iron"],
	]
	for b in bits:
		var n := _inst(j, b[0], "Bit", Vector3(b[1], b[2] + 0.02, 0.0))
		n.set_meta("material", b[3])


## Счётчик материалов забега (RunInventory) в правом нижнем углу — поверх HUD площадки, скрыт, пока пусто.
func _loot_counter() -> void:
	var cl := CanvasLayer.new()
	cl.name = "LootCounter"
	cl.layer = 5
	cl.set_script(load("res://scenes/ui/run_inventory_counter.gd"))
	arena_root.add_child(cl)
	var l := Label.new()
	l.name = "Text"
	l.anchor_left = 1.0
	l.anchor_top = 1.0
	l.anchor_right = 1.0
	l.anchor_bottom = 1.0
	l.offset_left = -760.0
	l.offset_top = -52.0
	l.offset_right = -24.0
	l.offset_bottom = -14.0
	l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_color_override("font_color", Color(1.0, 0.93, 0.8, 0.85))
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02, 0.9))
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_font_size_override("font_size", 24)
	l.visible = false
	cl.add_child(l)


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


## Спавны: P1 / P2 — пол центра (между ними открыто, над ними островок), Spawn2 — островок, Spawn3 — ярус R1.
func _spawns() -> void:
	var holder := _group("Spawns")
	var pts := [Vector3(0.6, 0.05, 0), Vector3(4.4, 0.05, 0), Vector3(ISLAND_X, ISLAND_Y + 0.05, 0), Vector3(R1_X - 0.6, DECK_S + 0.05, 0)]
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
	# DOF дали: фон v2 резкий (увеличение ≤ ×1.6), размытие только отделяет дальние планы от боя. В v1 было
	# 24 / 40 / 0.05 — прятало полосы листа, растянутые ×3–4.
	var ca := CameraAttributesPractical.new()
	ca.dof_blur_far_enabled = true
	ca.dof_blur_far_distance = 45.0
	ca.dof_blur_far_transition = 70.0
	ca.dof_blur_amount = 0.03
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
