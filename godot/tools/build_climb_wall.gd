## Сборщик стены пробы «Подъём» (docs/plan-demo/CLIMB.md): собирает res://scenes/climb/climb_wall.tscn (скрипт ClimbWall).
## Запуск: godot --headless --path godot --import && godot --headless --path godot res://tools/build_climb_wall.tscn
## (сценой, а не -s: скрипт стены читает Tuning — в -s автозагрузок нет). Повторный запуск перезаписывает сцену.
##
## Шахта 30 м между двумя скалами (вид сбоку, куклы в плоскости z = 0, X вбок, Y вверх, пол старта — y = 0):
##   левая скала (лицо x ≈ −3): камень 0–6 м с маленьким уступом на 2.85; ГЛАДКАЯ плита 6–10.6; широкая полка (2.2 м) на 11.1; камень
##     11.1–15.4 с выступами; узкий уступ (0.5 м) на 15.45; камень до 19.4; НАВИСАЮЩИЙ КАРНИЗ 19.4–20.2 (выступ 3.6 м в шахту, низ и
##     край — камень, верх — полка); над карнизом ГЛАДКО 20.2–24 (перелёт с полки); камень 24–30 с уступом на 27; плато финиша —
##     верх левой скалы (y = 30, левее x = −3);
##   правая скала (лицо x ≈ +3): камень 0–4.6, уступ 1.2 м на 5.0, камень 5–13 с выступами, ГЛАДКО 13–17; выше — пусто (обход карниза).
## Только полётом от пола до верха не долететь: между правым уступом (5.0) и полкой (11.1) — 6 м без опоры.
## Дерево: Node3D "ClimbWall" (climb_wall.gd) ├ WorldEnvironment "Environment", DirectionalLight3D "Sun"
##   ├ Node3D "Rock": StaticBody3D-куски (группа climbable) и "Smooth": гладкие (без группы); у каждого CollisionShape3D + MeshInstance3D
##   ├ Node3D "Backdrop" — фон за плоскостью (без коллизий), "Marks" — Label3D высоты каждые 5 м (текст — скрипт стены, tr)
##   ├ Node3D "Finish" — флаг и подпись на плато, StaticBody3D "Bounds" — невидимые стены шахты и потолок
##   ├ Area3D "Gravity" — сила тяжести шахты (Tuning.CLIMB_GRAVITY), Node3D "Spawns" — Marker3D Spawn0/1
extends Node

const OUT := "res://scenes/climb/climb_wall.tscn"
const SCRIPT := "res://scenes/climb/climb_wall.gd"
const ENV_RES := "res://assets/environments/ruins_env.tres"
const STONE := "res://assets/textures/pbr/stone/%s.png"
const IRON := "res://assets/textures/pbr/iron/%s.png"
const DEPTH := 2.0     # толщина кусков по z (плоскость кукол — середина)
const LEFT := -12.0    # тыльная сторона левой скалы
const RIGHT := 12.0

## [имя, x0, x1, y0, y1, вид]: rock — камень (хватается), smooth — гладкое, ground — пол/плато (камень).
const PIECES := [
	["Ground", -12.0, 12.0, -1.0, 0.0, "rock"],
	# левая скала
	["L_Rock_0", LEFT, -3.0, 0.0, 6.0, "rock"],
	["L_Ledge_2", -3.0, -2.2, 2.5, 2.85, "rock"],
	["L_Smooth_6", LEFT, -2.9, 6.0, 10.6, "smooth"],
	["L_Shelf_11", -3.2, -1.0, 10.6, 11.1, "rock"],
	["L_Rock_11", LEFT, -3.2, 10.6, 15.4, "rock"],
	["L_Bump_12", -3.2, -2.9, 12.3, 12.6, "rock"],
	["L_Bump_14", -3.2, -2.95, 13.8, 14.05, "rock"],
	["L_Ledge_15", -3.2, -2.7, 15.15, 15.45, "rock"],
	["L_Rock_15", LEFT, -3.0, 15.4, 19.4, "rock"],
	["L_Bump_17", -3.0, -2.75, 17.2, 17.45, "rock"],
	["L_Rock_19", LEFT, -3.0, 19.4, 20.2, "rock"],
	["L_Overhang_20", -3.0, 0.6, 19.4, 20.2, "rock"],
	["L_Smooth_20", LEFT, -3.4, 20.2, 24.0, "smooth"],
	["L_Rock_24", LEFT, -3.0, 24.0, 30.0, "rock"],
	# правая скала
	["R_Rock_0", 3.0, RIGHT, 0.0, 4.6, "rock"],
	["R_Ledge_5", 1.8, 3.0, 4.6, 5.0, "rock"],
	["R_Rock_5", 3.0, RIGHT, 4.6, 13.0, "rock"],
	["R_Bump_7", 2.75, 3.0, 7.4, 7.7, "rock"],
	["R_Bump_10", 2.7, 3.0, 9.9, 10.2, "rock"],
	["R_Smooth_13", 2.9, RIGHT, 13.0, 17.0, "smooth"],
]

var root: Node3D
var _rock_mat: StandardMaterial3D
var _smooth_mat: StandardMaterial3D
var _back_mat: StandardMaterial3D


func _ready() -> void:
	if not _build():
		get_tree().quit(1)
		return
	get_tree().quit(0)


func _build() -> bool:
	root = Node3D.new()
	root.name = "ClimbWall"
	var scr := load(SCRIPT) as Script
	if scr == null:
		push_error("no script " + SCRIPT)
		return false
	root.set_script(scr)
	_materials()
	_environment()
	var rock := _group("Rock")
	var smooth := _group("Smooth")
	for p in PIECES:
		var kind := String(p[5])
		_piece(smooth if kind == "smooth" else rock, String(p[0]), p[1], p[2], p[3], p[4], kind)
	_backdrop()
	_marks()
	_finish()
	_bounds()
	_gravity()
	_spawns()
	_set_owner(root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		push_error("pack failed: %d" % err)
		return false
	err = ResourceSaver.save(ps, OUT)
	if err != OK:
		push_error("save failed: %d" % err)
		return false
	print("saved ", OUT, ": pieces=", PIECES.size())
	root.free()
	return true


func _set_owner(n: Node) -> void:
	for c in n.get_children():
		if c.owner == null:
			c.owner = root
		_set_owner(c)


func _group(n: String, parent: Node = null) -> Node3D:
	var g := Node3D.new()
	g.name = n
	(parent if parent != null else root).add_child(g)
	return g


func _tex(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _materials() -> void:
	_rock_mat = StandardMaterial3D.new()
	_rock_mat.albedo_texture = _tex(STONE % "albedo")
	_rock_mat.albedo_color = Color(0.86, 0.8, 0.72)
	_rock_mat.normal_enabled = true
	_rock_mat.normal_texture = _tex(STONE % "normal")
	_rock_mat.normal_scale = 1.4
	_rock_mat.roughness_texture = _tex(STONE % "roughness")
	_rock_mat.uv1_triplanar = true
	_rock_mat.uv1_world_triplanar = true
	_rock_mat.uv1_scale = Vector3(0.45, 0.45, 0.45)
	# гладкое: тёмно-синий лёд / полированная плита — блестит, без рельефа камня (читается «не схватиться»)
	_smooth_mat = StandardMaterial3D.new()
	_smooth_mat.albedo_texture = _tex(IRON % "albedo")
	_smooth_mat.albedo_color = Color(0.5, 0.68, 0.86)
	_smooth_mat.metallic = 0.55
	_smooth_mat.roughness = 0.12
	_smooth_mat.uv1_triplanar = true
	_smooth_mat.uv1_world_triplanar = true
	_smooth_mat.uv1_scale = Vector3(0.3, 0.3, 0.3)
	_smooth_mat.rim_enabled = true
	_smooth_mat.rim = 0.4
	_back_mat = _rock_mat.duplicate() as StandardMaterial3D
	_back_mat.albedo_color = Color(0.36, 0.34, 0.33)
	_back_mat.uv1_scale = Vector3(0.18, 0.18, 0.18)


func _environment() -> void:
	var env := WorldEnvironment.new()
	env.name = "Environment"
	if ResourceLoader.exists(ENV_RES):
		var e := (load(ENV_RES) as Environment).duplicate() as Environment
		e.fog_density *= 0.4
		env.environment = e
	var cam := CameraAttributesPractical.new()
	cam.dof_blur_far_enabled = false
	cam.dof_blur_near_enabled = false
	cam.auto_exposure_enabled = false
	env.camera_attributes = cam
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.basis = Basis.looking_at(Vector3(0.5, -0.7, -0.5).normalized(), Vector3.UP)
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	root.add_child(sun)


## Кусок скалы: StaticBody3D с одним боксом (CollisionShape3D "Shape") и мешем того же размера; камень — в группе climbable.
func _piece(parent: Node, n: String, x0: float, x1: float, y0: float, y1: float, kind: String) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = n
	b.position = Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0.0)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.15 if kind == "smooth" else 0.9
	pm.bounce = 0.05
	b.physics_material_override = pm
	if kind != "smooth":
		b.add_to_group(ArmAssist.CLIMBABLE, true)
	b.set_meta("kind", kind)
	var size := Vector3(x1 - x0, y1 - y0, DEPTH)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var bm := BoxMesh.new()
	bm.size = size + Vector3(0, 0, 0.6)   # видимая толщина чуть больше (скала уходит за плоскость)
	mi.mesh = bm
	mi.position = Vector3(0, 0, -0.3)
	mi.material_override = _smooth_mat if kind == "smooth" else _rock_mat
	b.add_child(mi)
	parent.add_child(b)
	return b


## Фон за плоскостью кукол: дальняя стена ущелья (без коллизий).
func _backdrop() -> void:
	var g := _group("Backdrop")
	var mi := MeshInstance3D.new()
	mi.name = "FarWall"
	var bm := BoxMesh.new()
	bm.size = Vector3(40.0, 46.0, 1.0)
	mi.mesh = bm
	mi.position = Vector3(0.0, 16.0, -3.2)
	mi.material_override = _back_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(mi)


## Отметки высоты каждые 5 м на дальней стене справа (текст ставит ClimbWall._ready через tr).
func _marks() -> void:
	var g := _group("Marks")
	for h in range(5, int(Tuning.CLIMB_WALL_H) + 1, 5):
		var l := Label3D.new()
		l.name = "Mark_%d" % h
		l.set_meta("height", h)
		l.position = Vector3(5.6, float(h), -2.6)
		l.font_size = 64
		l.pixel_size = 0.006
		l.outline_size = 12
		l.modulate = Color(1.0, 0.92, 0.7, 0.85)
		l.outline_modulate = Color(0.05, 0.04, 0.03, 0.8)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		g.add_child(l)
		var tick := MeshInstance3D.new()
		tick.name = "Tick_%d" % h
		var tm := BoxMesh.new()
		tm.size = Vector3(1.2, 0.05, 0.05)
		tick.mesh = tm
		tick.position = Vector3(5.0, float(h), -2.6)
		var mm := StandardMaterial3D.new()
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mm.albedo_color = Color(1.0, 0.9, 0.6, 0.8)
		mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tick.material_override = mm
		g.add_child(tick)


## Флаг финиша на плато (декор) и подпись.
func _finish() -> void:
	var g := _group("Finish")
	g.position = Vector3(-5.5, ClimbWall.FINISH_Y, -0.4)
	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.04
	cm.bottom_radius = 0.05
	cm.height = 3.0
	pole.mesh = cm
	pole.position = Vector3(0, 1.5, 0)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.85, 0.85, 0.82)
	pmat.metallic = 0.6
	pmat.roughness = 0.35
	pole.material_override = pmat
	g.add_child(pole)
	var flag := MeshInstance3D.new()
	flag.name = "Flag"
	var qm := QuadMesh.new()
	qm.size = Vector2(1.4, 0.9)
	flag.mesh = qm
	flag.position = Vector3(0.72, 2.5, 0)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(1.0, 0.55, 0.12)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.45, 0.05)
	fmat.emission_energy_multiplier = 0.6
	fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flag.material_override = fmat
	g.add_child(flag)
	var l := Label3D.new()
	l.name = "Label"
	l.position = Vector3(0.7, 3.4, 0.2)
	l.font_size = 72
	l.pixel_size = 0.006
	l.outline_size = 14
	l.modulate = Color(1.0, 0.85, 0.4)
	l.outline_modulate = Color(0.05, 0.03, 0.0, 0.85)
	g.add_child(l)


## Невидимые стены шахты (x = ±7.5 — выше правой скалы) и потолок; не лазаемые.
func _bounds() -> void:
	var b := StaticBody3D.new()
	b.name = "Bounds"
	for e in [["WallL", Vector3(-8.0, 17.0, 0), Vector3(1.0, 36.0, DEPTH)], ["WallR", Vector3(8.0, 17.0, 0), Vector3(1.0, 36.0, DEPTH)],
			["Ceiling", Vector3(0.0, 34.5, 0), Vector3(17.0, 1.0, DEPTH)]]:
		var cs := CollisionShape3D.new()
		cs.name = String(e[0])
		var bs := BoxShape3D.new()
		bs.size = e[2]
		cs.shape = bs
		cs.position = e[1]
		b.add_child(cs)
	root.add_child(b)


func _gravity() -> void:
	var a := Area3D.new()
	a.name = "Gravity"
	a.gravity_space_override = Area3D.SPACE_OVERRIDE_REPLACE
	a.gravity_direction = Vector3.DOWN
	a.gravity = Tuning.CLIMB_GRAVITY
	# как поле купола (NullField): замена гравитации работает, только пока зона следит за телами (monitoring) всех слоёв
	a.collision_layer = 0
	a.collision_mask = 0xFFFFFFFF
	a.monitoring = true
	a.monitorable = false
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var bs := BoxShape3D.new()
	bs.size = Vector3(30.0, 44.0, 6.0)
	cs.shape = bs
	cs.position = Vector3(0, 16.0, 0)
	a.add_child(cs)
	root.add_child(a)


func _spawns() -> void:
	var g := _group("Spawns")
	for i in ClimbWall.SPAWNS.size():
		var m := Marker3D.new()
		m.name = "Spawn%d" % i
		m.position = ClimbWall.SPAWNS[i]
		g.add_child(m)
