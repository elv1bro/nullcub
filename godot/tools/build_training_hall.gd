## Builder тренировочного зала за воротами мастерской (docs/plan-demo/MENU_GARAGE.md, «Тренировочный зал»): сцена
##   scenes/arena/training_hall.tscn — Node3D «TrainingHall» (training_hall.gd) ← Floor, Walls, Structure, Lights, Props, Bag, Screens, Grids.
## Модули — кит Old NULL Hall (assets/models/arena/null_hall/*.glb, материалы по ролям ставит импорт) и новые Heavy_Bag / Chain_Link /
## Tire_Column / Hang_Beam (tools/blender/arena_null_hall.py). Порядок: blender … --export Heavy_Bag Chain_Link Tire_Column Hang_Beam;
## godot --headless --path godot --import; godot --headless --path godot res://tools/build_training_hall.tscn   (сценой, а не -s: скриптам зала нужны autoload Tuning / Flow).
## Координаты мира гаража: зал — влево от гаража вдоль плоскости боя z = 0; ворота в стене гаража на x = −4.7, пол y = 0.
extends Node

const OUT := "res://scenes/arena/training_hall.tscn"
const SCRIPT := "res://scenes/arena/training_hall.gd"
const KIT := "res://assets/models/arena/null_hall/%s.glb"
const GRID_SHADER := "res://assets/shaders/energy_grid.gdshader"
const BAG_SCENE := "res://scenes/props/heavy_bag.tscn"
const SCREEN_SCRIPT := "res://scenes/arena/hall_screen.gd"

const X_NEAR := -4.7
const X_FAR := -47.0
const Z_BACK := -5.2
const HEIGHT := 10.0
## балка груши: низ нижней полки; проушина — на 0.12 ниже; цепь 4.1 + ушко 0.62 → центр шара у пола ≈ 1.9
const BAG_X := -30.0
const BEAM_BAG_Y := 6.6
const DUMMY_X := -17.0
const BEAM_DUMMY_Y := 4.4

var hall: Node3D
var errors := 0
var _kit_cache := {}


func _ready() -> void:
	hall = Node3D.new()
	hall.name = "TrainingHall"
	hall.set_script(load(SCRIPT))
	_floor()
	_walls()
	_structure()
	_lights()
	_props()
	_bag()
	_screens()
	_grids()
	var ps := PackedScene.new()
	var err := ps.pack(hall)
	if err == OK:
		err = ResourceSaver.save(ps, OUT)
	print("training_hall → %s (%s) errors=%d" % [OUT, error_string(err), errors])
	get_tree().quit(1 if errors > 0 or err != OK else 0)


func _group(n: String) -> Node3D:
	var g := Node3D.new()
	g.name = n
	hall.add_child(g)
	g.owner = hall
	return g


func _kit(module: String) -> PackedScene:
	if not _kit_cache.has(module):
		var path := KIT % module
		if not ResourceLoader.exists(path):
			push_error("нет модуля %s" % path)
			errors += 1
			_kit_cache[module] = null
		else:
			_kit_cache[module] = load(path)
	return _kit_cache[module]


func _place(module: String, parent: Node3D, pos: Vector3, yaw := 0.0, node_name := "", scl := Vector3.ONE) -> Node3D:
	var ps := _kit(module)
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	n.name = node_name if node_name != "" else module
	parent.add_child(n, true)
	n.owner = hall
	n.position = pos
	n.rotation_degrees = Vector3(0.0, yaw, 0.0)
	n.scale = scl
	return n


func _body(parent: Node3D, n: String, size: Vector3, pos: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = n
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	parent.add_child(b)
	b.owner = hall
	cs.owner = hall
	b.position = pos
	return b


# ------------------------------------------------------------------ пол и стены

func _floor() -> void:
	var g := _group("Floor")
	for ix in 7:
		for zi in 3:
			_place("Floor_Platform", g, Vector3(-8.0 - 6.0 * ix, -0.6, -3.0 + 6.0 * zi), 0.0, "Plate_%d_%d" % [ix, zi])
	_body(g, "FloorBody", Vector3(44.0, 1.0, 20.0), Vector3(-25.5, -0.5, 3.0))
	_body(g, "CeilingBody", Vector3(44.0, 1.0, 20.0), Vector3(-25.5, HEIGHT + 0.5, 3.0))
	_body(g, "FarWallBody", Vector3(1.0, 14.0, 20.0), Vector3(X_FAR - 0.5, 5.0, 3.0))
	_body(g, "LintelBody", Vector3(1.0, HEIGHT - 3.4, 8.0), Vector3(X_NEAR - 0.3, 3.4 + (HEIGHT - 3.4) * 0.5, 1.2))


func _walls() -> void:
	var g := _group("Walls")
	for i in 7:
		var x := -8.1 - 6.06 * i
		_place("Wall_Panel_01" if i == 3 else "Wall_Panel", g, Vector3(x, 0.0, Z_BACK), 0.0, "Back_%d" % i)
		_place("Wall_Panel", g, Vector3(x, 8.0, Z_BACK), 0.0, "BackTop_%d" % i, Vector3(1.0, 0.3, 1.0))
	for zi in 3:
		var z := -3.0 + 6.1 * zi
		_place("Wall_Panel", g, Vector3(X_FAR - 0.05, 0.0, z), 90.0, "End_%d" % zi)
		_place("Wall_Panel", g, Vector3(X_FAR - 0.05, 8.0, z), 90.0, "EndTop_%d" % zi, Vector3(1.0, 0.3, 1.0))


func _structure() -> void:
	var g := _group("Structure")
	for x in [-10.5, -22.5, -34.5, -45.5]:
		_place("Support_Column", g, Vector3(x, 0.0, Z_BACK + 0.9), 0.0, "Column_%d" % int(-x))
	for x in [-13.0, -19.0, -25.0, -31.0, -37.0]:
		_place("Catwalk", g, Vector3(x - 0.0, 5.4, Z_BACK + 0.8), 0.0, "Catwalk_%d" % int(-x))
	for x in [-9.0, -18.0, -27.0, -36.0, -44.0]:
		_place("Light_Rig", g, Vector3(x, 9.0, -1.6), 0.0, "Rig_%d" % int(-x))
	for i in 3:
		var banner: String = ["Banner_Red", "Banner_Blue", "Banner_Red"][i]
		_place(banner, g, Vector3(-15.0 - 11.5 * i, 9.8, Z_BACK + 0.15), 0.0, "Banner_%d" % i)
	_place("Banner_Fighting", g, Vector3(-26.5, 9.9, Z_BACK + 0.2), 0.0, "BannerBig", Vector3.ONE * 0.8)
	# подвесные балки: манекен (ROPE_UP) и груша
	_place("Hang_Beam", g, Vector3(DUMMY_X, BEAM_DUMMY_Y, 0.0), 0.0, "BeamDummy")
	_place("Hang_Beam", g, Vector3(BAG_X, BEAM_BAG_Y, 0.0), 0.0, "BeamBag")


func _lights() -> void:
	var g := _group("Lights")
	var i := 0
	for x in [-9.0, -18.0, -27.0, -36.0, -44.0]:
		var s := SpotLight3D.new()
		s.name = "Spot_%d" % i
		g.add_child(s)
		s.owner = hall
		s.position = Vector3(x, 8.6, -1.2)
		s.look_at_from_position(s.position, Vector3(x + 1.0, 0.0, 0.8), Vector3.UP)
		s.light_color = Color(1.0, 0.9, 0.78)
		s.light_energy = 6.5
		s.spot_range = 26.0
		s.spot_angle = 42.0
		s.spot_attenuation = 0.9
		s.shadow_enabled = false
		i += 1
	i = 0
	for spec in [[-12.0, Color(1.0, 0.58, 0.25)], [-26.0, Color(1.0, 0.62, 0.3)], [-40.0, Color(1.0, 0.58, 0.25)]]:
		var o := OmniLight3D.new()
		o.name = "Fill_%d" % i
		g.add_child(o)
		o.owner = hall
		o.position = Vector3(float(spec[0]), 2.8, 4.0)
		o.light_color = spec[1]
		o.light_energy = 1.8
		o.omni_range = 18.0
		o.omni_attenuation = 1.2
		o.shadow_enabled = false
		i += 1
	# ряд тёплых ламп вдоль задней стены: стена и экраны читаются, а не тонут во тьме
	for k in 5:
		var w := OmniLight3D.new()
		w.name = "Wall_%d" % k
		g.add_child(w)
		w.owner = hall
		w.position = Vector3(-9.0 - 9.0 * k, 3.6, -3.4)
		w.light_color = Color(1.0, 0.78, 0.55)
		w.light_energy = 2.2
		w.omni_range = 11.0
		w.omni_attenuation = 1.1
		w.shadow_enabled = false
	var cool := OmniLight3D.new()
	cool.name = "Cool"
	g.add_child(cool)
	cool.owner = hall
	cool.position = Vector3(-24.0, 7.5, 2.0)
	cool.light_color = Color(0.45, 0.65, 1.0)
	cool.light_energy = 0.9
	cool.omni_range = 34.0
	cool.omni_attenuation = 1.0
	cool.shadow_enabled = false


func _props() -> void:
	var g := _group("Props")
	_place("Crate", g, Vector3(-8.6, 0.0, -3.9), 12.0, "Crate_0")
	_place("Crate", g, Vector3(-8.7, 1.34, -3.85), -9.0, "Crate_1", Vector3.ONE * 0.8)
	_place("Crate", g, Vector3(-43.0, 0.0, -3.7), -15.0, "Crate_2")
	_place("Crate", g, Vector3(-41.2, 0.0, -4.0), 6.0, "Crate_3", Vector3.ONE * 0.8)
	_place("Cables_Pipes", g, Vector3(-30.0, 3.6, Z_BACK + 0.35), 0.0, "Cables_0")
	_place("Cables_Pipes", g, Vector3(-18.0, 3.4, Z_BACK + 0.35), 0.0, "Cables_1")
	_place("Speaker", g, Vector3(-13.0, 9.6, -3.0), 0.0, "Speaker_0")
	_place("Speaker", g, Vector3(-40.0, 9.6, -3.0), 0.0, "Speaker_1")
	_place("Debris", g, Vector3(-34.0, 0.0, 2.6), 20.0, "Debris_0")
	_place("Railing", g, Vector3(-13.0, 5.4, Z_BACK + 1.6), 0.0, "Rail_0")
	_place("Floor_Seam", g, Vector3(-5.2, 0.0, 1.2), 0.0, "Seam_Gate")
	# колонна из покрышек в плоскости боя — с коллайдером
	var t := _place("Tire_Column", g, Vector3(-40.0, 0.0, 0.0), 0.0, "TireColumn")
	if t != null:
		var body := StaticBody3D.new()
		body.name = "TireBody"
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.52
		cyl.height = 2.56
		cs.shape = cyl
		cs.position = Vector3(0, 1.28, 0)
		body.add_child(cs)
		t.add_child(body)
		body.owner = hall
		cs.owner = hall


func _bag() -> void:
	var ps := load(BAG_SCENE) as PackedScene
	var b := ps.instantiate() as Node3D
	b.name = "Bag"
	hall.add_child(b, true)
	b.owner = hall
	var eye_y := BEAM_BAG_Y - 0.12
	var center_y := eye_y - 4.1 - 0.62
	b.position = Vector3(BAG_X, center_y, 0.0)
	b.set("anchor", Vector3(BAG_X, eye_y, 0.0))


# ------------------------------------------------------------------ экраны и сетка

func _screens() -> void:
	var g := _group("Screens")
	var s := 1.5
	for spec in [["speed", -10.0], ["dummy", -21.5], ["impact", -27.0]]:
		var kind := String(spec[0])
		var x := float(spec[1])
		var frame := _place("Small_Scoreboard", g, Vector3(x, 1.0, Z_BACK + 0.2), 0.0, "Frame_" + kind, Vector3.ONE * s)
		var sc := Node3D.new()
		sc.name = kind
		sc.set_script(load(SCREEN_SCRIPT))
		sc.set("kind", kind)
		g.add_child(sc)
		sc.owner = hall
		sc.position = Vector3(x, 1.0 + 1.02 * s, Z_BACK + 0.2 + 0.06 * s + 0.012)
		if frame == null:
			errors += 1


func _grid_material(color: Color, cells: Vector2, glow := 1.7, base := 0.06, fade_v := 0.0, fade_top := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(GRID_SHADER)
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("cells", cells)
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("base_alpha", base)
	m.set_shader_parameter("fade_v", fade_v)
	m.set_shader_parameter("fade_top", fade_top)
	return m


func _grid(parent: Node3D, n: String, size: Vector2, pos: Vector3, yaw: float, mat: ShaderMaterial, pitch := 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.name = n
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.owner = hall
	mi.position = pos
	mi.rotation_degrees = Vector3(pitch, yaw, 0.0)


func _grids() -> void:
	var g := _group("Grids")
	var cyan := Color(0.25, 0.62, 1.0)
	var white := Color(0.7, 0.88, 1.0)
	# дальняя стена: во всю высоту (лицом к +X)
	_grid(g, "FarGrid", Vector2(20.0, HEIGHT), Vector3(X_FAR + 0.12, HEIGHT * 0.5, 3.0), 90.0, _grid_material(cyan, Vector2(40, 20), 1.9, 0.08))
	# края задней стены: у ворот и у дальнего конца
	_grid(g, "BackGridNear", Vector2(4.2, HEIGHT), Vector3(X_NEAR - 2.6, HEIGHT * 0.5, Z_BACK + 0.14), 0.0, _grid_material(cyan, Vector2(8, 20), 1.7, 0.07))
	_grid(g, "BackGridFar", Vector2(6.0, HEIGHT), Vector3(-44.0, HEIGHT * 0.5, Z_BACK + 0.14), 0.0, _grid_material(cyan, Vector2(12, 20), 1.8, 0.07))
	# полосы вдоль всей задней стены: у пола и под потолком
	_grid(g, "FloorBand", Vector2(41.0, 1.4), Vector3(-26.0, 0.7, Z_BACK + 0.15), 0.0, _grid_material(white, Vector2(82, 3), 1.5, 0.05, 0.0, 0.7))
	_grid(g, "CeilBand", Vector2(41.0, 1.8), Vector3(-26.0, HEIGHT - 0.9, Z_BACK + 0.15), 0.0, _grid_material(white, Vector2(82, 4), 1.5, 0.05, 0.7, 0.0))
	# потолок над полем — слабой сеткой
	_grid(g, "CeilGrid", Vector2(41.0, 6.0), Vector3(-26.0, HEIGHT - 0.12, -2.0), 0.0, _grid_material(cyan, Vector2(82, 12), 0.9, 0.02), -90.0)
