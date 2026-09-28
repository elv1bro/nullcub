## Builder арены «Руины» v2 (ART_DIRECTION.md §2, листы R15/R17): собирает res://scenes/arena/ruins.tscn
## ИЗ КОМПОНЕНТНЫХ СЦЕН scenes/props/*.tscn (их делает tools/build_props_scenes.gd из моделей props.py).
## Каждый компонент — PackedScene.instantiate() с owner = корень арены; внутренности инстансов принадлежат своим
## сценам (в ruins.tscn сохраняются только позиция и переопределённые экспорты, например solid=false / color / open).
## Запуск: godot --headless --path godot --import && godot --headless --path godot -s res://tools/build_arena_ruins.gd
## Повторный запуск перезаписывает сцену: правки, которые нужно сохранить, вносятся сюда.
##
## Система координат: X вбок, Y вверх, физика в плоскости XY (z=0 — плоскость кукол). Верх плит земли G=0.4.
## Кладка (башни, стены, ворота) стоит ЗА плоскостью кукол на z=WALL_Z без коллизии (solid=false / пилоны ворот
## вне плоскости): иначе под мостом и в воротах получались замкнутые карманы. Твёрдое: плиты земли, палубы,
## верёвочный мост, каменный мост, верхняя площадка, балка виселицы, обломки-блоки, пропсы.
## Дерево: Node3D "Ruins" (script ruins.gd)
##   ├── WorldEnvironment "Environment", DirectionalLight3D "Sun"
##   ├── "Parallax": инстанс scenes/arena/parallax_background.tscn (если файл есть; иначе пустой Node3D-заглушка)
##   ├── Node3D "Ground": stone_platform_4m ×7 (x −14..14), фундамент wall_segment ×14 (декор, y −3..0), блоки-обломки
##   ├── Node3D "Left": wooden_deck (верх DECK_Y), rope_bridge_6m к центральному мосту, руины стены, знамя red
##   ├── Node3D "Centre": башни wall_segment ×2×2, gate (open), stone_platform_5m мост (верх 4.0), задняя стена,
##   │     верхняя площадка wooden_deck_3m ×3 (верх TOP_DECK_Y), руина-арка (gate без створок), знамя red
##   ├── Node3D "Right": стены, wooden_deck, знамя blue, gallows + cage в точке Beam/Hook
##   ├── Node3D "Torches": torch ×6 на лицах кладки
##   ├── Node3D "Props": barrel/crate (Breakable) — обломки спавнятся сюда же
##   ├── StaticBody3D "Bounds": невидимые стены x=±HALF_W и потолок y=CEIL_Y
##   ├── Area3D "DeathZone": ямы у краёв (|x|>14, ниже земли) + страховочный низ
##   └── Node3D "Spawns": Marker3D Spawn0..3 (каменный мост, под воротами, левая и правая палубы)
extends SceneTree

const OUT := "res://scenes/arena/ruins.tscn"
const SCENE_UID := "uid://ruinsarena01"
const PROPS := "res://scenes/props/%s.tscn"
const SCRIPT := "res://scenes/arena/ruins.gd"
const PARALLAX := "res://scenes/arena/parallax_background.tscn"
const ENV_RES := "res://assets/environments/ruins_env.tres"        # look-dev v3 (R22): SSIL, depth fog, тёплый LUT, DOF; SDFGI в пресете выключен (1080p на M2 <55 fps)
const CAM_RES := "res://assets/environments/ruins_camera.tres"     # DOF дальнего плана (параллакс)

const G := 0.4                  # верх плит земли (плиты y=0..0.4)
const WALL_Z := -0.7            # центр кладки: глубина 0.8 → лицо на z≈−0.3 (голова куклы r=0.24 не входит в стену)
const TORCH_Z := 0.05           # origin факела: плита кронштейна (z −0.3 от origin) прижата к лицу стены
const HALF_W := 16.0            # невидимые стены
const CEIL_Y := 12.0
const DECK_Y := G + 2.25        # верх боковых палуб (wooden_deck: столбы 2 м + настил 0.25)
const BRIDGE_Y := G + 3.2       # низ каменного моста (плита 0.4 → верх 4.0 = верх арки ворот + 0.4)
const TOWER_TOP := G + 6.0      # две стены 2×3
const TOP_DECK_Y := TOWER_TOP + 0.25
const SKY_TOP := Color(0.40, 0.53, 0.76)
const SKY_HORIZON := Color(0.62, 0.66, 0.74)

var arena_root: Node3D
var props: Node3D
var _scenes: Dictionary = {}
var _names: Dictionary = {}


func _init() -> void:
	arena_root = Node3D.new()
	arena_root.name = "Ruins"
	arena_root.set_script(load(SCRIPT))
	_environment()
	_parallax()
	_ground()
	_left()
	_centre()
	_right()
	_torches()
	_props()
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
			push_error("missing component scene " + (PROPS % kind) + " — run tools/build_props_scenes.gd")
			quit(1)
		_scenes[kind] = ps
	return _scenes[kind]


func _group(name: String) -> Node3D:
	var n := Node3D.new()
	n.name = name
	arena_root.add_child(n)
	return n


## Инстанс компонента: origin компонента — центр основания; overrides — экспорты (solid, color, open, doors…);
## rot_y — градусы вокруг Y.
func _inst(parent: Node, kind: String, name: String, pos: Vector3, overrides := {}, rot_y := 0.0) -> Node3D:
	var inst: Node3D = _scene(kind).instantiate()
	inst.name = _uniq(name)
	inst.position = pos
	if rot_y != 0.0:
		inst.rotation_degrees = Vector3(0, rot_y, 0)
	for k in overrides.keys():
		inst.set(k, overrides[k])
	parent.add_child(inst)
	return inst


## Обломок на верху кладки (декор): блок сплющен в плиту и слегка завален, чтобы не читался «кубиком».
func _rubble(parent: Node, name: String, pos: Vector3, rot_y: float, tilt_z := 0.0) -> Node3D:
	var b := _inst(parent, "stone_block", name, pos, {"solid": false}, rot_y)
	b.scale = Vector3(1.25, 0.55, 1.1)
	b.rotation_degrees.z = tilt_z
	return b


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
func _ground() -> void:
	var g := _group("Ground")
	for i in 7:
		_inst(g, "stone_platform_4m", "Ground", Vector3(-12.0 + 4.0 * i, 0.0, 0), {}, 180.0 if i % 2 == 1 else 0.0)
	# фундамент под террасой: рельефная кладка лицом к камере, чуть выступает под кромкой плит; коллизии нет
	for i in 14:
		_inst(g, "wall_segment", "Foundation", Vector3(-13.0 + 2.0 * i, -3.0, 0.55), {"solid": false})
	# редкие блоки на земле как обломки (твёрдые)
	_inst(g, "stone_block", "Rubble", Vector3(-13.5, G, 0.5), {}, 20.0)
	_inst(g, "stone_block", "Rubble", Vector3(3.9, G, 0.55), {}, -15.0)
	_inst(g, "stone_block", "Rubble", Vector3(-6.2, G, 0.6), {}, 35.0)


func _left() -> void:
	var l := _group("Left")
	# палуба на столбах x −12.5..−8.5 (верх DECK_Y); верёвочный мост от её правого края к каменному мосту (верх 4.0)
	_inst(l, "wooden_deck", "DeckL", Vector3(-10.5, G, 0))
	_inst(l, "rope_bridge_6m", "RopeBridge", Vector3(-8.4, DECK_Y, 0.2))
	# руины стены под мостом: сегменты утоплены на 1 м (верх 2.4 — ниже нижней точки моста 2.7), сверху блоки
	_inst(l, "wall_segment", "WallL", Vector3(-7.5, G - 1.0, WALL_Z), {"solid": false})
	_inst(l, "wall_segment", "WallL", Vector3(-5.5, G - 1.0, WALL_Z), {"solid": false})
	_rubble(l, "WallL_Top", Vector3(-8.2, G + 2.0, WALL_Z + 0.05), 12.0, 4.0)
	_rubble(l, "WallL_Top", Vector3(-6.4, G + 2.0, WALL_Z - 0.05), -20.0, -6.0)
	_rubble(l, "WallL_Top", Vector3(-4.9, G + 2.0, WALL_Z), 8.0, 3.0)
	_inst(l, "banner", "BannerL", Vector3(-9.3, DECK_Y, -0.5), {"color": "red"})


func _centre() -> void:
	var c := _group("Centre")
	# башни x∈[−4.5,−2.5] и [2.5,4.5]: две стены 2×3 друг на друге (декор за плоскостью кукол)
	for s in [-1.0, 1.0]:
		_inst(c, "wall_segment", "Tower", Vector3(3.5 * s, G, WALL_Z), {"solid": false})
		_inst(c, "wall_segment", "Tower", Vector3(3.5 * s, G + 3.0, WALL_Z), {"solid": false}, 180.0 if s > 0 else 0.0)
	# ворота 3 м между башнями: створки открыты (пилоны и створки вне плоскости кукол — прохода не запирают)
	_inst(c, "gate", "Gate", Vector3(0, G, WALL_Z), {"open": true})
	# каменный мост над воротами (твёрдый), задняя стена над ним до верхней площадки (декор)
	_inst(c, "stone_platform_5m", "Bridge", Vector3(0, BRIDGE_Y, 0))
	for s in [-1.0, 1.0]:
		_inst(c, "wall_segment", "BackWall", Vector3(1.0 * s, BRIDGE_Y - 0.2, WALL_Z), {"solid": false}, 180.0 if s > 0 else 0.0)
	# верхняя площадка 9 м из трёх настилов по 3 м (твёрдая), руина-арка слева, знамя справа
	for i in 3:
		_inst(c, "wooden_deck_3m", "TopDeck", Vector3(-3.0 + 3.0 * i, TOWER_TOP, 0))
	_inst(c, "gate", "TopRuin", Vector3(-2.0, TOP_DECK_Y, WALL_Z), {"open": true, "doors": false})
	_rubble(c, "TopRuin_Rubble", Vector3(3.6, TOP_DECK_Y, WALL_Z + 0.1), -10.0, 5.0)
	_inst(c, "banner", "BannerTop", Vector3(2.4, TOP_DECK_Y, -0.5), {"color": "red"})


func _right() -> void:
	var r := _group("Right")
	# стена 3 м у башни, дальше руина (утоплена, верх 2.4), сверху блоки
	_inst(r, "wall_segment", "WallR", Vector3(5.5, G, WALL_Z), {"solid": false}, 180.0)
	_inst(r, "wall_segment", "WallR", Vector3(7.5, G - 1.0, WALL_Z), {"solid": false})
	_rubble(r, "WallR_Top", Vector3(6.9, G + 2.0, WALL_Z + 0.05), 15.0, -5.0)
	_rubble(r, "WallR_Top", Vector3(8.1, G + 2.0, WALL_Z - 0.05), -25.0, 4.0)
	_rubble(r, "WallR_Top", Vector3(5.2, G + 3.0, WALL_Z), 5.0, -3.0)
	_inst(r, "wooden_deck", "DeckR", Vector3(10.5, G, 0))
	_inst(r, "banner", "BannerR", Vector3(9.3, DECK_Y, -0.5), {"color": "blue"})
	# виселица у задней кромки палубы; балка выходит вперёд, клетка висит в точке Beam/Hook в плоскости кукол
	var gal := _inst(r, "gallows", "Gallows", Vector3(11.9, DECK_Y, -0.65))
	var beam := gal.get_node("Beam") as Node3D
	var hook := beam.get_node("Hook") as Node3D
	var hook_pos: Vector3 = gal.transform * (beam.transform * hook.position)
	hook_pos.z = 0.0
	_inst(r, "cage", "Cage", hook_pos)


func _torches() -> void:
	var t := _group("Torches")
	# на пилонах ворот, на верхней части башен и на боковых стенах (кронштейн к лицу кладки z≈−0.3)
	for p in [[-2.0, G + 1.5], [2.0, G + 1.5], [-3.5, G + 4.3], [3.5, G + 4.3], [-6.5, G + 0.9], [6.5, G + 1.3]]:
		_inst(t, "torch", "Torch", Vector3(p[0], p[1], TORCH_Z))


func _props() -> void:
	props = _group("Props")
	var crates := [
		[-5.0, G], [4.9, G], [8.0, G], [12.9, G],                       # на земле
		[-11.9, DECK_Y], [-12.6, G], [-11.9, G], [-11.9, G + 0.72],    # левая палуба и под ней
		[0.3, TOP_DECK_Y], [1.0, TOP_DECK_Y], [0.65, TOP_DECK_Y + 0.72],   # верхняя площадка
		[11.7, DECK_Y], [11.0, DECK_Y], [11.35, DECK_Y + 0.72],        # правая палуба
	]
	for c in crates:
		_inst(props, "crate", "Crate", Vector3(c[0], c[1] + 0.02, 0))
	for b in [[-10.4, DECK_Y], [3.7, TOP_DECK_Y], [9.6, G], [-13.0, G]]:
		_inst(props, "barrel", "Barrel", Vector3(b[0], b[1] + 0.02, 0))


func _bounds() -> void:
	var b := StaticBody3D.new()
	b.name = "Bounds"
	arena_root.add_child(b)
	_box_shape(b, "WallL", -HALF_W - 1.0, -HALF_W, -10.0, 30.0, 0.0, 8.0)
	_box_shape(b, "WallR", HALF_W, HALF_W + 1.0, -10.0, 30.0, 0.0, 8.0)
	_box_shape(b, "Ceiling", -HALF_W - 1.0, HALF_W + 1.0, CEIL_Y, CEIL_Y + 1.0, 0.0, 8.0)
	var dz := Area3D.new()
	dz.name = "DeathZone"
	dz.monitoring = true
	arena_root.add_child(dz)
	# ямы не касаются невидимых стен (иначе StaticBody3D "Bounds" сам попадает в зону)
	_box_shape(dz, "PitL", -HALF_W + 0.1, -14.0, -9.0, -3.0, 0.0, 6.0)
	_box_shape(dz, "PitR", 14.0, HALF_W - 0.1, -9.0, -3.0, 0.0, 6.0)
	_box_shape(dz, "Floor", -HALF_W - 2.0, HALF_W + 2.0, -15.0, -14.0, 0.0, 8.0)


func _spawns() -> void:
	var holder := _group("Spawns")
	var pts := [Vector3(-1.5, BRIDGE_Y + 0.45, 0), Vector3(1.0, G + 0.05, 0), Vector3(-10.5, DECK_Y + 0.05, 0), Vector3(10.5, DECK_Y + 0.05, 0)]
	for i in pts.size():
		var m := Marker3D.new()
		m.name = "Spawn%d" % i
		m.position = pts[i]
		holder.add_child(m)


func _parallax() -> void:
	var n: Node3D
	if ResourceLoader.exists(PARALLAX):
		var ps: PackedScene = load(PARALLAX)
		n = ps.instantiate()
		# линия земли среднего плана — чуть выше кромки террасы при полном кадре (камера y≈5.5, z≈22)
		n.set("layer2_y_offset", -0.6)
	else:
		n = Node3D.new()   # заглушка для интегратора: сюда встанет parallax_background.tscn
	n.name = "Parallax"
	arena_root.add_child(n)


func _environment() -> void:
	var env := WorldEnvironment.new()
	env.name = "Environment"
	# Look-dev v3 (R22): пресет из assets/environments; без него — встроенное окружение v2 (_fallback_environment).
	if ResourceLoader.exists(ENV_RES):
		env.environment = load(ENV_RES)
		if ResourceLoader.exists(CAM_RES):
			env.camera_attributes = load(CAM_RES)
	else:
		env.environment = _fallback_environment()
	arena_root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	# тёплый свет спереди-слева-сверху, как на R15 (освещены верх и левые грани блоков)
	sun.basis = Basis.looking_at(Vector3(0.55, -0.75, -0.45).normalized(), Vector3.UP)
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.25
	sun.light_indirect_energy = 1.5   # SDFGI (ruins_env.tres): отскок от плит и кладки
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.shadow_bias = 0.03
	sun.directional_shadow_max_distance = 60.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = 0.15
	sun.directional_shadow_split_2 = 0.35
	sun.directional_shadow_split_3 = 0.6
	arena_root.add_child(sun)


## Встроенное окружение v2 (только если пресета ruins_env.tres нет).
func _fallback_environment() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = SKY_TOP
	sm.sky_horizon_color = SKY_HORIZON
	sm.ground_bottom_color = Color(0.30, 0.26, 0.22)
	sm.ground_horizon_color = SKY_HORIZON
	sm.sun_angle_max = 20.0
	sm.sun_curve = 0.2
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 1.0
	e.ambient_light_energy = 0.55
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 0.95
	e.tonemap_white = 1.0
	e.ssao_enabled = true
	e.ssao_radius = 0.8
	e.ssao_intensity = 2.0
	e.ssao_power = 1.5
	e.glow_enabled = true
	e.glow_intensity = 0.35
	e.glow_bloom = 0.02
	e.glow_hdr_threshold = 1.1
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	e.fog_enabled = false
	return e
