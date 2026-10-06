## Сборщик пробы «Перегон: машина» (docs/plan-demo/CONVOY.md, MODES_PACK.md §7): пишет res://scenes/playground_convoy.tscn — участок
## ~100 м слева направо и игровое (машина, камера, ConvoyMatch, ConvoyHud, узел кукол). Груз и доски кладёт площадка при запуске
## (из Tuning — без пересборки сцены). Повторный запуск перезаписывает сцену.
## Запуск: godot --headless --path godot --import && godot --headless --path godot res://tools/build_convoy_probe.tscn
## (сценой, а не -s: скрипты тянут автозагрузку Tuning — в -s её нет).
##
## Профиль дороги (верх земли, м): старт x 2 → ровно до 22 → поле кочек 22…44 (7 кочек 0.28–0.5 м) → ровно → подъём 22° с x 50 на
## 5.5 м → площадка 7.4 м → провал 71…74.4 (3.4 м, глубина 3 м; шире колёсной базы 3.0 м — без доски машина падает) → площадка →
## спуск 20° → финиш-площадка, линия финиша x 99. Над площадкой за провалом — стеллаж с досками (перелети и принеси). Стены по краям (x −11 и 108).
## Земля — один многоугольник: коллизии — выпуклые куски (Geometry2D.decompose_polygon_in_convex) толщиной 4 м по z, вид — призма
## (лицевая грань к камере на z = +1.2, тыл — z = −3). Кочки — цилиндры осью по z. Всё твёрдое — в плоскости кукол (z = 0).
## Дерево:
##   PlaygroundConvoy (playground_convoy.gd)
##   ├── Environment (scrap_env.tres), Sun
##   ├── Course: Ground (StaticBody3D), Bumps (StaticBody3D), Shelf (StaticBody3D), Walls, Look (меши), Signs (Label3D), Decor
##   ├── Car (scenes/convoy/convoy_car.tscn)
##   ├── Dolls, Camera (DynamicCamera), Match (ConvoyMatch), HUD (ConvoyHud)
extends Node

const OUT := "res://scenes/playground_convoy.tscn"
const PLAYGROUND := "res://scenes/convoy/playground_convoy.gd"
const CAR := "res://scenes/convoy/convoy_car.tscn"
const MATCH := "res://scripts/convoy/convoy_match.gd"
const HUD := "res://scenes/convoy/convoy_hud.gd"
const CAMERA := "res://scenes/camera/dynamic_camera.gd"
const ENV := "res://assets/environments/scrap_env.tres"
const TEX := {
	"dirt": "res://assets/textures/pbr/scrap_dirt/",
	"stone": "res://assets/textures/pbr/stone/",
	"wood": "res://assets/textures/pbr/wood_plank/",
	"iron": "res://assets/textures/pbr/iron/",
}
const DECOR := [
	["res://assets/models/scrap/props/Junk_Cart_Loaded.glb", Vector3(-6.0, 0.0, -2.4), 0.0, 1.0],
	["res://assets/models/scrap/props/Metal_Barrel_Dented.glb", Vector3(14.0, 0.0, -2.2), 0.4, 1.0],
	["res://assets/models/scrap/props/Wooden_Pallet.glb", Vector3(19.0, 0.0, -2.5), 0.0, 1.0],
	["res://assets/models/scrap/props/Pipe_Bundle.glb", Vector3(46.0, 0.0, -2.4), 0.0, 1.0],
	["res://assets/models/scrap/props/Overturned_Junk_Cart.glb", Vector3(96.0, 0.0, -2.6), 0.3, 1.0],
	["res://assets/models/scrap/props/Rail_Scrap_Wagon.glb", Vector3(104.0, 0.0, -2.4), 0.0, 1.0],
	["res://assets/models/scrap/props/Wooden_Beam_Stack.glb", Vector3(76.5, 5.5, -2.3), 0.0, 1.0],
]

# --- профиль (м) ---
const X_LEFT := -11.0
const X_RIGHT := 108.0
const BASE_Y := -1.5
const BUMPS_X0 := 22.0
const BUMPS_X1 := 44.0
## Кочки: [x вершины, высота, полуширина основания].
const BUMPS := [[24.6, 0.32, 1.1], [27.6, 0.45, 1.3], [30.4, 0.28, 0.9], [33.3, 0.5, 1.4], [36.6, 0.35, 1.0], [39.3, 0.42, 1.2],
	[42.0, 0.3, 1.0]]
const HILL_X0 := 50.0
const HILL_H := 5.5
const HILL_DEG := 22.0
const PIT_X0 := 71.0
const PIT_X1 := 74.4
const PIT_DEPTH := 3.0
const DESC_X0 := 78.6
const DESC_DEG := 20.0
const FINISH_X := 99.0
const START_X := 2.0
const FRONT_Z := 1.2
const BACK_Z := -3.0
const COLL_DEPTH := 4.0
## Стеллаж с досками: над площадкой за провалом (машина, вставшая перед провалом, к нему не мешает подлететь), низ на SHELF_UP
## над дорогой (машина с грузом проходит под ним).
const SHELF_X0 := 74.6
const SHELF_X1 := 79.8
const SHELF_UP := 3.7
const SHELF_STEP := 1.2
## Концы досок свисают с кронштейнов на столько (м): правый конец берут рукой справа от стеллажа (рука-хват у куклы — на экране слева).
const SHELF_OVERHANG := 0.65

var root: Node3D
var mats := {}


func _ready() -> void:
	if not _build():
		get_tree().quit(1)
		return
	get_tree().quit(0)


func hill_x1() -> float:
	return HILL_X0 + HILL_H / tan(deg_to_rad(HILL_DEG))


func desc_x1() -> float:
	return DESC_X0 + HILL_H / tan(deg_to_rad(DESC_DEG))


func _build() -> bool:
	root = Node3D.new()
	root.name = "PlaygroundConvoy"
	root.set_script(load(PLAYGROUND))
	_materials()
	_environment()
	var course := Node3D.new()
	course.name = "Course"
	root.add_child(course)
	var look := Node3D.new()
	look.name = "Look"
	course.add_child(look)
	_ground(course, look)
	_bumps(course, look)
	_walls(course, look)
	var spots := _shelf(course, look)
	_signs(course)
	_decor(course)
	var car := (load(CAR) as PackedScene).instantiate() as Node3D
	car.name = "Car"
	var r: float = Tuning.CONVOY_WHEEL_RADIUS
	var sag: float = Tuning.CONVOY_CHASSIS_MASS * 2.0 * Tuning.CONVOY_CAR_G_SCALE / 3.0 / Tuning.CONVOY_SPRING_K - Tuning.CONVOY_TRAVEL_DOWN
	var car_start := Vector3(START_X, r - sag + 0.02, 0.0)
	car.position = car_start
	root.add_child(car)
	var dolls := Node3D.new()
	dolls.name = "Dolls"
	root.add_child(dolls)
	_camera()
	var m := Node.new()
	m.name = "Match"
	m.set_script(load(MATCH))
	root.add_child(m)
	m.set("camera_path", NodePath("../Camera"))
	m.set("arena_path", NodePath(".."))
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.set_script(load(HUD))
	root.add_child(hud)
	root.set("car_start", car_start)
	root.set("start_x", START_X)
	root.set("finish_x", FINISH_X)
	root.set("pit_x0", PIT_X0)
	root.set("pit_x1", PIT_X1)
	root.set("pit_top_y", HILL_H)
	root.set("plank_spots", spots)
	root.set("level_rect", Rect2(X_LEFT - 1.0, -3.0, X_RIGHT - X_LEFT + 2.0, 26.0))
	root.set("sections", [[-100.0, "flat"], [BUMPS_X0, "bumps"], [BUMPS_X1, "runup"], [HILL_X0, "hill"],
		[hill_x1(), "pit"], [PIT_X1 + 1.0, "descent"], [desc_x1(), "finish"]])
	_own(root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		push_error("pack failed: %d" % err)
		return false
	err = ResourceSaver.save(ps, OUT)
	if err != OK:
		push_error("save failed: %d" % err)
		return false
	print("saved ", OUT, ": nodes=", _count(root), " hill_x1=", snappedf(hill_x1(), 0.01), " desc_x1=", snappedf(desc_x1(), 0.01))
	root.free()
	return true


# ---------------------------------------------------------------- helpers

func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


func _own(n: Node) -> void:
	for c in n.get_children():
		if c.owner == null:
			c.owner = root
		if c.scene_file_path == "":
			_own(c)


func _mat(kind: String, tint: Color, scale: float = 0.35, metal: float = 0.1) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	var dir: String = TEX.get(kind, "")
	if dir != "":
		if ResourceLoader.exists(dir + "albedo.png"):
			m.albedo_texture = load(dir + "albedo.png")
		if ResourceLoader.exists(dir + "normal.png"):
			m.normal_enabled = true
			m.normal_texture = load(dir + "normal.png")
		if ResourceLoader.exists(dir + "roughness.png"):
			m.roughness_texture = load(dir + "roughness.png")
	m.metallic = metal
	m.roughness = 0.9
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	return m


func _materials() -> void:
	mats["dirt"] = _mat("dirt", Color(0.86, 0.78, 0.68), 0.35)
	mats["stone"] = _mat("stone", Color(0.62, 0.58, 0.56), 0.22)
	mats["wood"] = _mat("wood", Color(0.9, 0.82, 0.7), 0.6)
	mats["iron"] = _mat("iron", Color(0.65, 0.66, 0.68), 0.5, 0.5)
	mats["hazard"] = ConvoyGeo.flat(Color(1.0, 0.75, 0.15), 0.2, 0.6)
	mats["dark"] = ConvoyGeo.flat(Color(0.07, 0.07, 0.08), 0.3, 0.7)
	mats["white"] = ConvoyGeo.flat(Color(0.93, 0.93, 0.9), 0.1, 0.6)


func _environment() -> void:
	var env := WorldEnvironment.new()
	env.name = "Environment"
	if ResourceLoader.exists(ENV):
		env.environment = load(ENV) as Environment
	else:
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.4, 0.45, 0.6)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.7, 0.7, 0.75)
		env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.basis = Basis.looking_at(Vector3(-0.35, -0.65, -0.68).normalized(), Vector3.UP)
	sun.light_color = Color(1.0, 0.9, 0.78)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.shadow_blur = 1.0
	sun.directional_shadow_max_distance = 60.0
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.basis = Basis.looking_at(Vector3(0.4, -0.3, -0.85).normalized(), Vector3.UP)
	fill.light_color = Color(0.7, 0.78, 1.0)
	fill.light_energy = 0.35
	fill.shadow_enabled = false
	root.add_child(fill)


## Профиль земли (верх), по часовой снизу не нужен — многоугольник замыкается низом на BASE_Y.
func _profile() -> PackedVector2Array:
	var h1 := hill_x1()
	var d1 := desc_x1()
	var top := HILL_H
	var bot := HILL_H - PIT_DEPTH
	return PackedVector2Array([
		Vector2(X_LEFT, 0.0), Vector2(HILL_X0, 0.0), Vector2(h1, top), Vector2(PIT_X0, top), Vector2(PIT_X0, bot),
		Vector2(PIT_X1, bot), Vector2(PIT_X1, top), Vector2(DESC_X0, top), Vector2(d1, 0.0), Vector2(X_RIGHT, 0.0),
		Vector2(X_RIGHT, BASE_Y), Vector2(X_LEFT, BASE_Y)])


func _ground(course: Node3D, look: Node3D) -> void:
	var st := StaticBody3D.new()
	st.name = "Ground"
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	st.physics_material_override = pm
	course.add_child(st)
	var poly := _profile()
	var parts := Geometry2D.decompose_polygon_in_convex(poly)
	var k := 0
	for part in parts:
		var pts := PackedVector3Array()
		for p in part:
			pts.append(Vector3(p.x, p.y, -COLL_DEPTH * 0.5))
			pts.append(Vector3(p.x, p.y, COLL_DEPTH * 0.5))
		var cs := CollisionShape3D.new()
		cs.name = "Piece%d" % k
		var sh := ConvexPolygonShape3D.new()
		sh.points = pts
		cs.shape = sh
		st.add_child(cs)
		k += 1
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = _prism(poly, FRONT_Z, BACK_Z, mats["stone"], mats["dirt"])
	look.add_child(mi)
	# линии старта и финиша — полосы на лицевой грани земли
	ConvoyGeo.box_xy(look, "StartLine", START_X - 0.08, START_X + 0.08, BASE_Y, 0.0, 0.04, mats["white"], FRONT_Z + 0.02)
	for i in 6:
		var y0 := BASE_Y + (0.0 - BASE_Y) * i / 6.0
		var y1 := BASE_Y + (0.0 - BASE_Y) * (i + 1) / 6.0
		for j in 2:
			ConvoyGeo.box_xy(look, "Finish%d_%d" % [i, j], FINISH_X - 0.3 + 0.3 * j, FINISH_X + 0.3 * j, y0, y1, 0.04,
				mats["white"] if (i + j) % 2 == 0 else mats["dark"], FRONT_Z + 0.02)
	# предупреждающие полосы на кромках провала
	for x in [PIT_X0 - 0.15, PIT_X1 + 0.15]:
		ConvoyGeo.box_xy(look, "PitEdge%d" % int(x), x - 0.15, x + 0.15, HILL_H - 0.12, HILL_H + 0.01, FRONT_Z - BACK_Z, mats["hazard"], (FRONT_Z + BACK_Z) * 0.5)


## Призма из многоугольника poly (XY): торцы на z_front / z_back — материал cap, боковые грани — side. Нормали явные.
func _prism(poly: PackedVector2Array, z_front: float, z_back: float, cap: Material, side: Material) -> ArrayMesh:
	var am := ArrayMesh.new()
	var idx := Geometry2D.triangulate_polygon(poly)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for zi in 2:
		var z := z_front if zi == 0 else z_back
		var n := Vector3(0, 0, 1) if zi == 0 else Vector3(0, 0, -1)
		for t in range(0, idx.size(), 3):
			var tri := [poly[idx[t]], poly[idx[t + 1]], poly[idx[t + 2]]]
			var a: Vector2 = tri[0]
			var b: Vector2 = tri[1]
			var c: Vector2 = tri[2]
			var ccw := (b - a).cross(c - a) > 0.0
			# Godot: лицевая грань — по часовой, если смотреть на неё
			var order := [a, c, b] if (ccw == (zi == 0)) else [a, b, c]
			for p in order:
				st.set_normal(n)
				st.add_vertex(Vector3((p as Vector2).x, (p as Vector2).y, z))
	st.set_material(cap)
	st.commit(am)
	var ss := SurfaceTool.new()
	ss.begin(Mesh.PRIMITIVE_TRIANGLES)
	var area := 0.0
	for i in poly.size():
		area += poly[i].cross(poly[(i + 1) % poly.size()])
	var ccw_poly := area > 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var d := (b - a).normalized()
		var out := Vector2(d.y, -d.x) if ccw_poly else Vector2(-d.y, d.x)
		var n3 := Vector3(out.x, out.y, 0.0)
		var p0 := Vector3(a.x, a.y, z_front)
		var p1 := Vector3(b.x, b.y, z_front)
		var p2 := Vector3(b.x, b.y, z_back)
		var p3 := Vector3(a.x, a.y, z_back)
		# снаружи смотрим против нормали: по часовой
		var cw := (p1 - p0).cross(p2 - p0).dot(n3) < 0.0
		var quad := [p0, p1, p2, p0, p2, p3] if cw else [p0, p2, p1, p0, p3, p2]
		for p in quad:
			ss.set_normal(n3)
			ss.add_vertex(p)
	ss.set_material(side)
	ss.commit(am)
	return am


func _bumps(course: Node3D, look: Node3D) -> void:
	var st := StaticBody3D.new()
	st.name = "Bumps"
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	st.physics_material_override = pm
	course.add_child(st)
	for i in BUMPS.size():
		var b: Array = BUMPS[i]
		var x: float = b[0]
		var h: float = b[1]
		var w: float = b[2]
		var r := (w * w + h * h) / (2.0 * h)
		var c := Vector3(x, h - r, 0.0)
		ConvoyGeo.disc_shape(st, "Bump%d" % i, r, COLL_DEPTH, c)
		var mi := ConvoyGeo.disc_mesh(look, "Bump%d" % i, r, FRONT_Z - 0.05 - BACK_Z, Vector3(x, h - r, (FRONT_Z - 0.05 + BACK_Z) * 0.5), mats["dirt"], 48)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _walls(course: Node3D, look: Node3D) -> void:
	var st := StaticBody3D.new()
	st.name = "Walls"
	course.add_child(st)
	ConvoyGeo.shape_xy(st, "Left", X_LEFT - 1.0, X_LEFT, BASE_Y, 20.0, COLL_DEPTH)
	ConvoyGeo.shape_xy(st, "Right", X_RIGHT, X_RIGHT + 1.0, BASE_Y, 20.0, COLL_DEPTH)
	ConvoyGeo.box_xy(look, "WallL", X_LEFT - 1.0, X_LEFT, BASE_Y, 9.0, FRONT_Z - BACK_Z, mats["stone"], (FRONT_Z + BACK_Z) * 0.5)
	ConvoyGeo.box_xy(look, "WallR", X_RIGHT, X_RIGHT + 1.0, BASE_Y, 9.0, FRONT_Z - BACK_Z, mats["stone"], (FRONT_Z + BACK_Z) * 0.5)
	# дальний гребень — фон по всей дороге
	ConvoyGeo.box_xy(look, "Ridge", X_LEFT - 20.0, X_RIGHT + 20.0, BASE_Y, 3.0, 1.0, mats["stone"], -9.0)
	ConvoyGeo.box_xy(look, "RidgeHigh", 40.0, 95.0, 3.0, 9.0, 1.0, mats["stone"], -10.0)


## Стеллаж с досками над площадкой за провалом: по паре кронштейнов на каждую доску (ярусы через SHELF_STEP); концы досок свисают
## на SHELF_OVERHANG — кукла справа от стеллажа берёт конец, вытягивает доску вправо, опускает ниже стеллажа и несёт к провалу;
## тяги вверх (вид). Возвращает центры досок.
func _shelf(course: Node3D, look: Node3D) -> PackedVector3Array:
	var st := StaticBody3D.new()
	st.name = "Shelf"
	course.add_child(st)
	var bw := 0.6
	var spots := PackedVector3Array()
	var cx := (SHELF_X0 + SHELF_X1) * 0.5
	var top := HILL_H + SHELF_UP + SHELF_STEP * (Tuning.CONVOY_PLANKS - 1)
	var inset := (SHELF_X1 - SHELF_X0 - Tuning.CONVOY_PLANK_LEN) * 0.5 + SHELF_OVERHANG   # концы досок свисают с кронштейнов
	for i in Tuning.CONVOY_PLANKS:
		var y0 := HILL_H + SHELF_UP + SHELF_STEP * i
		for side in 2:
			var bx0 := SHELF_X0 + inset if side == 0 else SHELF_X1 - inset - bw
			var bx1 := bx0 + bw
			var tag := "%d%s" % [i, "L" if side == 0 else "R"]
			ConvoyGeo.shape_xy(st, "Bracket" + tag, bx0, bx1, y0, y0 + 0.1, 1.2)
			ConvoyGeo.box_xy(look, "Bracket" + tag, bx0, bx1, y0, y0 + 0.1, 1.2, mats["iron"])
			ConvoyGeo.box_xy(look, "Stripe" + tag, bx0, bx1, y0 - 0.05, y0, 1.22, mats["hazard"])
		spots.append(Vector3(cx, y0 + 0.1 + 0.08, 0.0))
	for side in 2:
		var rx := SHELF_X0 + inset + 0.3 if side == 0 else SHELF_X1 - inset - 0.3
		ConvoyGeo.box_xy(look, "Rod%d" % side, rx - 0.04, rx + 0.04, HILL_H + SHELF_UP, top + 8.0, 0.08, mats["dark"], -0.55)
	return spots


func _sign(parent: Node3D, n: String, text: String, x: float, ground: float, colour := Color(1.0, 0.92, 0.75)) -> void:
	ConvoyGeo.box_xy(parent, n + "Post", x - 0.06, x + 0.06, ground, ground + 2.6, 0.12, mats["dark"], -1.7)
	ConvoyGeo.box_xy(parent, n + "Board", x - 1.3, x + 1.3, ground + 2.0, ground + 2.9, 0.08, mats["dark"], -1.62)
	var l := ConvoyGeo.label(parent, n, text, Vector3(x, ground + 2.45, -1.56), 64, colour)
	l.pixel_size = 0.0045


func _signs(course: Node3D) -> void:
	var s := Node3D.new()
	s.name = "Signs"
	course.add_child(s)
	_sign(s, "Start", "СТАРТ", START_X + 1.5, 0.0)
	_sign(s, "Bumps", "КОЧКИ", BUMPS_X0, 0.0)
	_sign(s, "Hill", "ПОДЪЁМ — толкай", HILL_X0 - 3.0, 0.0)
	_sign(s, "Pit", "ПРОВАЛ — положи доску", hill_x1() + 1.6, HILL_H)
	_sign(s, "Finish", "ФИНИШ", FINISH_X, 0.0, Color(0.6, 1.0, 0.65))
	var planks := ConvoyGeo.label(s, "Planks", "ДОСКИ", Vector3((SHELF_X0 + SHELF_X1) * 0.5, HILL_H + SHELF_UP + SHELF_STEP * 3.0, -0.5), 40,
		Color(1.0, 0.85, 0.4))
	planks.pixel_size = 0.004


func _decor(course: Node3D) -> void:
	var d := Node3D.new()
	d.name = "Decor"
	course.add_child(d)
	var k := 0
	for e in DECOR:
		var path := String(e[0])
		if not ResourceLoader.exists(path):
			continue
		var m := (load(path) as PackedScene).instantiate() as Node3D
		m.name = "Decor%d" % k
		m.position = e[1]
		m.rotation.y = float(e[2])
		m.scale = Vector3.ONE * float(e[3])
		d.add_child(m)
		k += 1


func _camera() -> void:
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.set_script(load(CAMERA))
	cam.add_to_group("camera", true)
	cam.fov = 40.0
	cam.position = Vector3(6, 3, 20)
	root.add_child(cam)
	cam.set("arena_path", NodePath(".."))
	cam.set("floor_inset", 0.0)
	cam.set("target_group", "convoy_cam")
	cam.set("follow_mode", "all")
	cam.set("min_half_height", 5.2)
	cam.set("max_half_height", 8.5)
	cam.set("padding", 3.0)
	cam.set("follow_tau", 0.25)
	cam.set("lead_time", 0.5)
