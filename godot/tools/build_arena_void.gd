## Builder арены «Void» (пустое чёрное поле как в Ragdoll Masters; docs/plan-demo/05-arena.md, раздел «Void»): собирает
## res://scenes/arena/void.tscn из моделей tools/blender/arena_void.py (assets/models/arena/void/*.glb) и сохраняет
## пресет окружения res://assets/environments/void_env.tres. Ничего не строится в _ready().
## Запуск: godot --headless --path godot --import && godot --headless --path godot -s res://tools/build_arena_void.gd
## Повторный запуск перезаписывает сцену и пресет: правки, которые нужно сохранить, вносятся сюда.
##
## Система координат: X вбок, Y вверх, физика в плоскости XY (z=0 — плоскость кукол), +Z к камере. Пол y=0.
## Поле 14 × 8 м: внутренние грани стен x=±HALF_W, невидимый потолок CEIL_Y = верх стен; ям и DeathZone нет.
## v6 (вид RM): стены и плита пола толщиной 1 м → arena_bounds = x −8..8 × y −1..8 (16 × 9 м = аспект 16:9): камера
## playground_void.tscn с fit_bounds во весь зум показывает ровно поле с полосами стен и пола по краям, без пустоты за ними.
## Дерево: Node3D "Void" (script void.gd, arena_bounds)
##   ├── WorldEnvironment "Environment" (void_env.tres: чёрный фон, ambient цветом, ACES, glow только для FX;
##   │     без неба, тумана, SSAO/SSIL/SDFGI, без camera_attributes → без DOF)
##   ├── DirectionalLight3D "Sun" (слабый, спереди-сверху-слева, мягкие тени 2 сплита), "Rim" (контровой сзади-сверху, без теней)
##   ├── MeshInstance-модель "Backdrop" (Grid_Backdrop.glb, unshaded) на z=BACKDROP_Z — сетка RM
##   ├── StaticBody3D "Floor": модель Floor_Slab (видимая глубина 1 м) + коллизия 16 × 1 × 3 (верх y=0)
##   ├── StaticBody3D "WallL" / "WallR": модель Wall_Side (глубина 1 м) + коллизия 1 × 8 × 3 (внутренняя грань x=∓HALF_W)
##   ├── StaticBody3D "Bounds": невидимые потолок y=CEIL_Y и страховочный пол под плитой
##   └── Node3D "Spawns": Marker3D Spawn0..3 на x = −3, 3, −5.5, 5.5 (y=SPAWN_Y)
extends SceneTree

const OUT := "res://scenes/arena/void.tscn"
const SCENE_UID := "uid://voidarena001"
const ENV_OUT := "res://assets/environments/void_env.tres"
const ENV_UID := "uid://voidenv00001"
const GLB := "res://assets/models/arena/void/%s.glb"
const SCRIPT := "res://scenes/arena/void.gd"

# Геометрия (м) — синхронно с tools/blender/arena_void.py (FLOOR_*, WALL_*, BACK_*)
const HALF_W := 7.0             # внутренние грани стен
const WALL_T := 1.0             # внешняя грань x=±(HALF_W + WALL_T) = край кадра камеры во весь зум
const WALL_H := 8.0
const CEIL_Y := 8.0             # невидимый потолок = верх стен
const FLOOR_W := 16.0
const FLOOR_T := 1.0            # передняя грань — полоса пола внизу кадра (как RM)
const DEPTH := 3.0              # глубина коллизий пола/стен по z (куклы на z=0); видимая глубина моделей — 1 м
const BACKDROP_Z := -6.0
const BACKDROP_Y := 4.0         # центр квада 40 × 24 (целые координаты → линии сетки на целых метрах)
const SPAWN_X: Array[float] = [-3.0, 3.0, -5.5, 5.5]
const SPAWN_Y := 0.05

# Свет: ровный — ambient + слабый направленный (дерево куклы должно читаться на чёрном)
const AMBIENT_COLOR := Color(0.86, 0.88, 0.92)
const AMBIENT_ENERGY := 0.75
const SUN_DIR := Vector3(0.35, -0.6, -0.72)      # куда светит: от камеры-сверху-слева к задней стене
const SUN_COLOR := Color(1.0, 0.96, 0.9)
const SUN_ENERGY := 1.0
const RIM_DIR := Vector3(-0.25, -0.5, 0.83)      # контровой: сзади-сверху к камере — обводка по силуэту ореха на чёрном
const RIM_COLOR := Color(0.78, 0.86, 1.0)
const RIM_ENERGY := 0.45
const EXPOSURE := 1.0

var arena_root: Node3D


func _init() -> void:
	arena_root = Node3D.new()
	arena_root.name = "Void"
	arena_root.set_script(load(SCRIPT))
	arena_root.set("arena_bounds", AABB(Vector3(-HALF_W - WALL_T, -FLOOR_T, -1.0), Vector3(2.0 * (HALF_W + WALL_T), CEIL_Y + FLOOR_T, 2.0)))
	if not _environment():
		return
	_lights()
	_backdrop()
	_floor()
	_walls()
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
	print("saved ", OUT, ": nodes=", _count(arena_root))
	arena_root.free()
	quit(0)


# ---------------------------------------------------------------- helpers
func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


## owner для узлов, созданных здесь; внутренности инстансов glb принадлежат своим сценам и не трогаются.
func _set_owner(n: Node) -> void:
	for c in n.get_children():
		if c.owner == null:
			c.owner = arena_root
		_set_owner(c)


func _model(parent: Node, glb: String, name: String, pos: Vector3) -> Node3D:
	var ps: PackedScene = load(GLB % glb)
	if ps == null:
		push_error("missing " + (GLB % glb) + " — run Blender tools/blender/arena_void.py and godot --import")
		quit(1)
		return Node3D.new()
	var n: Node3D = ps.instantiate()
	n.name = name
	n.position = pos
	parent.add_child(n)
	return n


func _box_shape(parent: Node, name: String, x0: float, x1: float, y0: float, y1: float, depth: float) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.name = name
	var bs := BoxShape3D.new()
	bs.size = Vector3(x1 - x0, y1 - y0, depth)
	cs.shape = bs
	cs.position = Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0.0)
	parent.add_child(cs)
	return cs


func _static(name: String) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = name
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.05
	b.physics_material_override = pm
	arena_root.add_child(b)
	return b


# ---------------------------------------------------------------- layout
func _backdrop() -> void:
	_model(arena_root, "Grid_Backdrop", "Backdrop", Vector3(0.0, BACKDROP_Y, BACKDROP_Z))


func _floor() -> void:
	var f := _static("Floor")
	_model(f, "Floor_Slab", "Mesh", Vector3.ZERO)
	_box_shape(f, "Shape", -FLOOR_W * 0.5, FLOOR_W * 0.5, -FLOOR_T, 0.0, DEPTH)


func _walls() -> void:
	for side in [-1.0, 1.0]:
		var w := _static("WallL" if side < 0.0 else "WallR")
		var x: float = side * (HALF_W + WALL_T * 0.5)
		w.position = Vector3(x, 0.0, 0.0)
		_model(w, "Wall_Side", "Mesh", Vector3.ZERO)
		_box_shape(w, "Shape", -WALL_T * 0.5, WALL_T * 0.5, 0.0, WALL_H, DEPTH)


func _bounds() -> void:
	var b := StaticBody3D.new()
	b.name = "Bounds"
	arena_root.add_child(b)
	_box_shape(b, "Ceiling", -HALF_W - WALL_T, HALF_W + WALL_T, CEIL_Y, CEIL_Y + 0.5, 8.0)
	_box_shape(b, "FloorSafety", -20.0, 20.0, -FLOOR_T - 1.0, -FLOOR_T - 0.5, 12.0)


func _spawns() -> void:
	var holder := Node3D.new()
	holder.name = "Spawns"
	arena_root.add_child(holder)
	for i in SPAWN_X.size():
		var m := Marker3D.new()
		m.name = "Spawn%d" % i
		m.position = Vector3(SPAWN_X[i], SPAWN_Y, 0.0)
		holder.add_child(m)


func _lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.basis = Basis.looking_at(SUN_DIR.normalized(), Vector3.UP)
	sun.position = Vector3(0, 8, 4)
	sun.light_color = SUN_COLOR
	sun.light_energy = SUN_ENERGY
	sun.light_indirect_energy = 0.0
	sun.light_volumetric_fog_energy = 0.0
	sun.light_angular_distance = 1.0
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.5
	sun.shadow_blur = 1.5
	sun.shadow_opacity = 0.75
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	# камера fov 24° стоит в 13–21 м от кукол: первый сплит (0.6 × 40 = 24 м) накрывает кукол при любом зуме
	sun.directional_shadow_split_1 = 0.6
	sun.directional_shadow_max_distance = 40.0
	arena_root.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.name = "Rim"
	rim.basis = Basis.looking_at(RIM_DIR.normalized(), Vector3.UP)
	rim.position = Vector3(0, 8, -4)
	rim.light_color = RIM_COLOR
	rim.light_energy = RIM_ENERGY
	rim.light_indirect_energy = 0.0
	rim.light_volumetric_fog_energy = 0.0
	rim.light_specular = 0.8
	rim.shadow_enabled = false
	arena_root.add_child(rim)


## Пресет void_env.tres (сохраняется отдельным ресурсом, сцена ссылается на него): чёрный фон, ambient цветом.
func _environment() -> bool:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = AMBIENT_COLOR
	e.ambient_light_energy = AMBIENT_ENERGY
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = EXPOSURE
	e.tonemap_white = 1.0
	e.ssao_enabled = false
	e.ssil_enabled = false
	e.sdfgi_enabled = false
	e.fog_enabled = false
	e.volumetric_fog_enabled = false
	# glow только для ярких FX (вспышка удара, HDR > 1.4); bloom 0 — чёрный фон и серый пол не «плывут»
	e.glow_enabled = true
	e.glow_normalized = false
	e.glow_intensity = 0.55
	e.glow_strength = 1.0
	e.glow_bloom = 0.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.glow_hdr_threshold = 1.4
	e.glow_hdr_scale = 2.0
	var err := ResourceSaver.save(e, ENV_OUT, ResourceSaver.FLAG_CHANGE_PATH)
	if err != OK:
		push_error("save env failed: %d" % err)
		quit(1)
		return false
	ResourceSaver.set_uid(ENV_OUT, ResourceUID.text_to_id(ENV_UID))
	e.take_over_path(ENV_OUT)   # сцена ссылается на файл (ext_resource), а не встраивает копию
	var env := WorldEnvironment.new()
	env.name = "Environment"
	env.environment = e
	arena_root.add_child(env)
	return true
