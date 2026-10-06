## Builder карты «Полигон» для пробного режима «Стычка 3 на 3» (docs/plan-demo/SQUAD.md): собирает res://scenes/arena/proving_ground.tscn
## (день) и proving_ground_night.tscn (ночь: тёмное небо, луна, фонари цвета команд, тёплый свет у башни; фон-параллакс затемняет и
## посыпает звёздами сам скрипт карты — ProvingGround.night)
## ИЗ КОМПОНЕНТНЫХ СЦЕН Руин scenes/props/*.tscn (как tools/build_arena_ruins.gd) — карта вдвое шире Руин (64 × 16 м), зеркальная:
## база синих слева, красных справа, между ними укрытия, парящие плиты и башня в центре. Повторный запуск перезаписывает сцену.
## Запуск: godot --headless --path godot --import && godot --headless --path godot res://tools/build_proving_ground.tscn
## (сценой, а не -s: скрипт карты наследует RuinsArena, а тот через Breakable → Match тянет автозагрузки — в -s их нет, и сцена
## сохранилась бы без скрипта).
##
## Система координат как у Руин: X вбок, Y вверх, куклы в плоскости z = 0, верх плит земли G = 0.4. Кладка-декор — за плоскостью
## кукол (z = WALL_Z, solid = false). Твёрдое в плоскости кукол: плиты земли, палубы баз, укрытия (стены, утопленные в землю — верх
## на высоте груди), парящие плиты, мост и верхняя площадка башни, пропсы. Ям нет: карта для перестрелки, а не для выталкивания.
## Дерево: Node3D "ProvingGround" (script proving_ground.gd)
##   ├── WorldEnvironment "Environment" (день — окружение Руин с половиной дымки, ночь — своё), DirectionalLight3D "Sun" (ночью —
##   │     лунный), камера без глубины резкости (автор 05.10: «как-то размыто всё»: Руины размывают всё дальше 24 м), "Parallax"
##   │     (parallax_background.tscn, слои едут за камерой), ночью — Node3D "Lamps" (OmniLight3D)
##   ├── Node3D "Ground": stone_platform_4m ×16 (x −32..32), фундамент wall_segment (декор, y −3..0)
##   ├── Node3D "BaseBlue" / "BaseRed": палуба базы, башни-декор, знамя цвета команды, укрытия CoverNear / CoverFar, парящая плита
##   ├── Node3D "Centre": башни-декор, ворота, каменный мост (верх 4.0), верхняя площадка (верх 6.65), высокие плиты (верх 9.0)
##   ├── Node3D "Torches", Node3D "Props": ящики, бочки (Breakable) и взрывные бочки Свалки (ExplosiveBarrel)
##   ├── StaticBody3D "Bounds": стены x = ±HALF_W, потолок y = CEIL_Y; Area3D "DeathZone" — страховочный низ
##   └── Node3D "Spawns": Marker3D Spawn0..5 в порядке player_index — чётные (синие) слева, нечётные (красные) справа
extends Node

const OUT := "res://scenes/arena/proving_ground.tscn"
const OUT_NIGHT := "res://scenes/arena/proving_ground_night.tscn"
const PROPS := "res://scenes/props/%s.tscn"
const SCRIPT := "res://scenes/arena/proving_ground.gd"
const PARALLAX := "res://scenes/arena/parallax_background.tscn"
const ENV_RES := "res://assets/environments/ruins_env.tres"
const METAL_BARREL := "res://scenes/props/scrap/prop_metal_barrel.tscn"

const G := 0.4
const WALL_Z := -0.7
const TORCH_Z := 0.05
const HALF_W := 32.0
const CEIL_Y := 16.0
const DECK_Y := G + 2.25          # верх палубы базы (wooden_deck: столбы 2 м + настил 0.25)
const BASE_X := 28.0              # центр палубы базы
const COVER_FAR_X := 21.0         # укрытие у базы
const COVER_NEAR_X := 11.0        # укрытие у центра
const FLOAT_X := 16.0             # парящая плита между укрытиями
const FLOAT_Y := 4.4              # её низ (верх 4.8)
const BRIDGE_Y := G + 3.2         # низ каменного моста башни (верх 4.0)
const TOWER_TOP := G + 6.0
const HIGH_X := 8.0               # высокие парящие плиты над серединой (верх HIGH_Y + 0.4)
const HIGH_Y := 8.6

var arena_root: Node3D
var props: Node3D
var _scenes: Dictionary = {}
var _names: Dictionary = {}


var night := false


func _ready() -> void:
	for n in [false, true]:
		if not _build(n):
			get_tree().quit(1)
			return
	get_tree().quit(0)


func _build(is_night: bool) -> bool:
	night = is_night
	_names.clear()
	arena_root = Node3D.new()
	arena_root.name = "ProvingGround"
	var scr := load(SCRIPT) as Script
	if scr == null:
		push_error("no script " + SCRIPT)
		return false
	arena_root.set_script(scr)
	arena_root.set("night", night)
	_environment()
	_parallax()
	_ground()
	_base(-1.0)
	_base(1.0)
	_centre()
	_props()
	_bounds()
	_spawns()
	if night:
		_lamps()
	_set_owner(arena_root)
	var ps := PackedScene.new()
	var err := ps.pack(arena_root)
	var out := OUT_NIGHT if night else OUT
	if err != OK:
		push_error("pack failed: %d" % err)
		return false
	err = ResourceSaver.save(ps, out)
	if err != OK:
		push_error("save failed: %d" % err)
		return false
	print("saved ", out, ": nodes=", _count(arena_root), " components=", _scenes.size(), " kinds")
	arena_root.free()
	return true


# ---------------------------------------------------------------- helpers
func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


func _set_owner(n: Node) -> void:
	for c in n.get_children():
		if c.owner == null:
			c.owner = arena_root
		_set_owner(c)


func _uniq(base: String) -> String:
	var k := int(_names.get(base, 0))
	_names[base] = k + 1
	return base if k == 0 else "%s_%d" % [base, k]


func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		var ps: PackedScene = load(path)
		if ps == null:
			push_error("missing component scene " + path)
			get_tree().quit(1)
		_scenes[path] = ps
	return _scenes[path]


func _group(name: String, parent: Node = null) -> Node3D:
	var n := Node3D.new()
	n.name = name
	(parent if parent != null else arena_root).add_child(n)
	return n


## Инстанс компонента Руин (kind — имя сцены в scenes/props/): origin — центр основания; overrides — экспорты; rot_y — градусы.
func _inst(parent: Node, kind: String, name: String, pos: Vector3, overrides := {}, rot_y := 0.0) -> Node3D:
	return _inst_path(parent, PROPS % kind, name, pos, overrides, rot_y)


func _inst_path(parent: Node, path: String, name: String, pos: Vector3, overrides := {}, rot_y := 0.0) -> Node3D:
	var inst: Node3D = _scene(path).instantiate()
	inst.name = _uniq(name)
	inst.position = pos
	if rot_y != 0.0:
		inst.rotation_degrees = Vector3(0, rot_y, 0)
	for k in overrides.keys():
		inst.set(k, overrides[k])
	parent.add_child(inst)
	return inst


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
	for i in 16:
		_inst(g, "stone_platform_4m", "Ground", Vector3(-30.0 + 4.0 * i, 0.0, 0), {}, 180.0 if i % 2 == 1 else 0.0)
	for i in 32:
		_inst(g, "wall_segment", "Foundation", Vector3(-31.0 + 2.0 * i, -3.0, 0.55), {"solid": false})


## База команды: s = −1 — синие (слева), +1 — красные (справа). Палуба с ящиками, башни-декор у стены, знамя цвета команды,
## укрытия — стены в плоскости кукол, утопленные в землю (верх на высоте груди: из-за них стреляют, через них перелетают).
func _base(s: float) -> void:
	var b := _group("BaseBlue" if s < 0.0 else "BaseRed")
	var colour := "blue" if s < 0.0 else "red"
	_inst(b, "wooden_deck", "Deck", Vector3(BASE_X * s, G, 0))
	for x in [30.5, 25.5]:
		_inst(b, "wall_segment", "Tower", Vector3(x * s, G, WALL_Z), {"solid": false}, 180.0 if s > 0.0 else 0.0)
		_inst(b, "wall_segment", "Tower", Vector3(x * s, G + 3.0, WALL_Z), {"solid": false})
	_rubble(b, "Tower_Top", Vector3(30.3 * s, G + 6.0, WALL_Z + 0.05), 10.0 * s, 4.0)
	_inst(b, "banner", "Banner", Vector3((BASE_X - 0.6) * s, DECK_Y, -0.5), {"color": colour})
	_inst(b, "banner", "Banner", Vector3(25.5 * s, G + 6.0, -0.5), {"color": colour})
	# укрытие у базы: стена 2 × 3 в плоскости кукол, утоплена на 1.2 м (верх G + 1.8) + обломки сверху (декор)
	_inst(b, "wall_segment", "CoverFar", Vector3(COVER_FAR_X * s, G - 1.2, 0))
	_rubble(b, "CoverFar_Top", Vector3(COVER_FAR_X * s, G + 1.8, 0.0), 15.0, -4.0 * s)
	# парящая плита: полка для стрельбы сверху между укрытиями
	_inst(b, "stone_platform_4m", "Float", Vector3(FLOAT_X * s, FLOAT_Y, 0))
	# укрытие у центра: ниже (верх G + 1.4) — из-за него видна голова
	_inst(b, "wall_segment", "CoverNear", Vector3(COVER_NEAR_X * s, G - 1.6, 0))
	_rubble(b, "CoverNear_Top", Vector3(COVER_NEAR_X * s, G + 1.4, 0.0), -20.0, 3.0 * s)
	# руины стены за укрытиями (декор, глубина)
	_inst(b, "wall_segment", "Ruin", Vector3(18.5 * s, G - 1.0, WALL_Z), {"solid": false})
	_inst(b, "wall_segment", "Ruin", Vector3(13.5 * s, G - 0.5, WALL_Z), {"solid": false}, 180.0)
	_rubble(b, "Ruin_Top", Vector3(18.2 * s, G + 2.0, WALL_Z), 12.0, 5.0)
	var t := arena_root.get_node_or_null("Torches") as Node3D
	if t == null:
		t = _group("Torches")
	for p in [[30.5, G + 4.3], [25.5, G + 1.6], [13.5, G + 1.9]]:
		_inst(t, "torch", "Torch", Vector3(float(p[0]) * s, float(p[1]), TORCH_Z))


func _centre() -> void:
	var c := _group("Centre")
	for s in [-1.0, 1.0]:
		_inst(c, "wall_segment", "Tower", Vector3(3.5 * s, G, WALL_Z), {"solid": false})
		_inst(c, "wall_segment", "Tower", Vector3(3.5 * s, G + 3.0, WALL_Z), {"solid": false}, 180.0 if s > 0 else 0.0)
		_inst(c, "stone_platform_5m", "High", Vector3(HIGH_X * s, HIGH_Y, 0))
	_inst(c, "gate", "Gate", Vector3(0, G, WALL_Z), {"open": true})
	_inst(c, "stone_platform_5m", "Bridge", Vector3(0, BRIDGE_Y, 0))
	for s in [-1.0, 1.0]:
		_inst(c, "wall_segment", "BackWall", Vector3(1.0 * s, BRIDGE_Y - 0.2, WALL_Z), {"solid": false}, 180.0 if s > 0 else 0.0)
	for i in 3:
		_inst(c, "wooden_deck_3m", "TopDeck", Vector3(-3.0 + 3.0 * i, TOWER_TOP, 0))
	_inst(c, "gate", "TopRuin", Vector3(-2.0, TOWER_TOP + 0.25, WALL_Z), {"open": true, "doors": false})
	_rubble(c, "TopRuin_Rubble", Vector3(3.6, TOWER_TOP + 0.25, WALL_Z + 0.1), -10.0, 5.0)
	var t := arena_root.get_node("Torches") as Node3D
	for p in [[-2.0, G + 1.5], [2.0, G + 1.5], [-3.5, G + 4.3], [3.5, G + 4.3]]:
		_inst(t, "torch", "Torch", Vector3(float(p[0]), float(p[1]), TORCH_Z))


func _props() -> void:
	props = _group("Props")
	var top := TOWER_TOP + 0.25
	var crates := []
	for s in [-1.0, 1.0]:
		crates.append_array([
			[(BASE_X + 1.3) * s, DECK_Y], [(BASE_X + 1.3) * s, DECK_Y + 0.72],    # палуба базы
			[(COVER_FAR_X + 1.4) * s, G], [(COVER_NEAR_X + 1.3) * s, G], [(COVER_NEAR_X + 1.3) * s, G + 0.72],   # у укрытий
			[(FLOAT_X - 1.2) * s, FLOAT_Y + 0.4],                                  # парящая плита
			[(HIGH_X + 1.5) * s, HIGH_Y + 0.4],                                    # высокая плита
			[1.0 * s, top],                                                         # верх башни
		])
	for c in crates:
		_inst(props, "crate", "Crate", Vector3(float(c[0]), float(c[1]) + 0.02, 0))
	for b in [[-16.8, G], [16.8, G], [-0.6, top]]:
		_inst(props, "barrel", "Barrel", Vector3(float(b[0]), float(b[1]) + 0.02, 0))
	# взрывные бочки Свалки (ExplosiveBarrel): в стрельбе их рвут очередью — у середины, где сходятся отряды
	if ResourceLoader.exists(METAL_BARREL):
		for x in [-6.5, 6.5]:
			_inst_path(props, METAL_BARREL, "MetalBarrel", Vector3(x, G + 0.02, 0))


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
	_box_shape(dz, "Floor", -HALF_W - 2.0, HALF_W + 2.0, -15.0, -14.0, 0.0, 8.0)


## Точки возрождения в порядке player_index (Match.spawn_point_for): 0, 2, 4 — синие слева, 1, 3, 5 — красные справа.
func _spawns() -> void:
	var holder := _group("Spawns")
	# не под палубой базы: у земли под настилом бот рвался вверх к своей «полке» и упирался головой в доски (проба 06.10) — первая
	# точка — в воздухе над палубой (поле NULL держит, кукла зависает)
	var per_team := [Vector2(BASE_X + 0.5, DECK_Y + 2.0), Vector2(BASE_X, DECK_Y + 0.05), Vector2(23.8, G + 0.05)]
	var i := 0
	for p in per_team:
		for s in [-1.0, 1.0]:
			var m := Marker3D.new()
			m.name = "Spawn%d" % i
			m.position = Vector3((p as Vector2).x * s, (p as Vector2).y, 0.0)
			holder.add_child(m)
			i += 1


func _parallax() -> void:
	var n: Node3D
	if ResourceLoader.exists(PARALLAX):
		var ps: PackedScene = load(PARALLAX)
		n = ps.instantiate()
		n.set("layer2_y_offset", -0.6)
		# карта вдвое шире Руин: квады фона рассчитаны на кадр Руин — небо приклеено к камере, дальние слои едут за ней частично
		n.set("layer4_scroll", 0.0)
		n.set("layer3_scroll", 0.25)
		n.set("layer2_scroll", 0.55)
		n.set("layer1_scroll", 0.8)
		n.set("scroll_vertical", false)
	else:
		n = Node3D.new()
	n.name = "Parallax"
	arena_root.add_child(n)


func _environment() -> void:
	var env := WorldEnvironment.new()
	env.name = "Environment"
	if night:
		env.environment = _night_environment()
	elif ResourceLoader.exists(ENV_RES):
		var e := (load(ENV_RES) as Environment).duplicate() as Environment   # своя копия: окружение Руин не трогаем
		e.fog_density *= 0.5            # карта вдвое шире Руин: дальние планы тонули в молочной дымке
		e.fog_aerial_perspective = 0.2
		env.environment = e
	# своя камера без глубины резкости: у Руин (ruins_camera.tres) всё дальше 24 м размыто, а на этой карте камера отъезжает до 22 м
	var cam := CameraAttributesPractical.new()
	cam.dof_blur_far_enabled = false
	cam.dof_blur_near_enabled = false
	cam.auto_exposure_enabled = false
	env.camera_attributes = cam
	arena_root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	if night:
		# луна: холодный слабый свет сверху-слева, тени остаются — силуэты читаются
		sun.basis = Basis.looking_at(Vector3(0.45, -0.8, -0.4).normalized(), Vector3.UP)
		sun.light_color = Color(0.62, 0.72, 1.0)
		sun.light_energy = 0.55
		sun.light_indirect_energy = 0.6
	else:
		sun.basis = Basis.looking_at(Vector3(0.55, -0.75, -0.45).normalized(), Vector3.UP)
		sun.light_color = Color(1.0, 0.93, 0.82)
		sun.light_energy = 1.25
		sun.light_indirect_energy = 1.5
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.shadow_bias = 0.03
	sun.directional_shadow_max_distance = 60.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = 0.15
	sun.directional_shadow_split_2 = 0.35
	sun.directional_shadow_split_3 = 0.6
	arena_root.add_child(sun)


## Ночь: тёмно-синее небо (отражения и окружающий свет), окружающий свет — синий и слабый, чтобы бойцы не пропадали; сильнее свечение
## (glow) — шарики пуль, факелы, фонари и кольца ящиков светятся; лёгкая синяя дымка.
func _night_environment() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.015, 0.02, 0.055)
	sm.sky_horizon_color = Color(0.05, 0.07, 0.13)
	sm.ground_bottom_color = Color(0.01, 0.012, 0.02)
	sm.ground_horizon_color = Color(0.05, 0.07, 0.13)
	sm.sun_angle_max = 1.0
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.32, 0.38, 0.6)
	e.ambient_light_energy = 0.55
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.05
	e.ssao_enabled = true
	e.ssao_radius = 0.8
	e.ssao_intensity = 1.6
	e.ssil_enabled = true
	e.ssil_radius = 4.0
	e.ssil_intensity = 1.2
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_strength = 1.0
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 0.95
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	e.fog_enabled = true
	e.fog_light_color = Color(0.1, 0.13, 0.24)
	e.fog_light_energy = 1.0
	e.fog_density = 0.003
	e.fog_aerial_perspective = 0.25
	return e


## Ночные фонари: у баз — цвета команды (над палубой и у башен), у башни в центре — тёплые, над парящими плитами — холодные.
func _lamps() -> void:
	var l := _group("Lamps")
	var blue := Color(0.45, 0.6, 1.0)
	var red := Color(1.0, 0.45, 0.4)
	for s in [-1.0, 1.0]:
		var team := blue if s < 0.0 else red
		_lamp(l, "BaseLamp", Vector3(BASE_X * s, DECK_Y + 2.6, 1.2), team, 3.0, 10.0)
		_lamp(l, "TowerLamp", Vector3(25.5 * s, G + 6.6, 0.8), team, 2.0, 8.0)
		_lamp(l, "CoverLamp", Vector3(COVER_FAR_X * s, G + 3.4, 1.0), team.lerp(Color.WHITE, 0.4), 1.2, 6.5)
		_lamp(l, "FloatLamp", Vector3(FLOAT_X * s, FLOAT_Y + 2.4, 1.2), Color(0.7, 0.8, 1.0), 1.4, 7.0)
		_lamp(l, "HighLamp", Vector3(HIGH_X * s, HIGH_Y + 2.0, 1.2), Color(0.7, 0.8, 1.0), 1.2, 6.5)
		_lamp(l, "MidLamp", Vector3(6.5 * s, G + 2.6, 1.4), Color(1.0, 0.7, 0.42), 1.6, 7.0)
	_lamp(l, "CentreLamp", Vector3(0.0, TOWER_TOP + 2.2, 1.4), Color(1.0, 0.72, 0.45), 2.4, 10.0)
	_lamp(l, "GateLamp", Vector3(0.0, G + 2.4, 1.2), Color(1.0, 0.7, 0.42), 1.6, 7.0)


func _lamp(parent: Node, name: String, pos: Vector3, col: Color, energy: float, rng: float) -> void:
	var o := OmniLight3D.new()
	o.name = _uniq(name)
	o.position = pos
	o.light_color = col
	o.light_energy = energy
	o.omni_range = rng
	o.omni_attenuation = 1.2
	o.shadow_enabled = false
	parent.add_child(o)
