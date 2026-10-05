## Builder спорт-зала (docs/plan-demo/SPORT.md): сцены
##   scenes/arena/sport_hall.tscn — Node3D «SportHall» (sport_hall.gd) ← Environment, Floor, Walls, Structure, Lights, Grids, Board,
##                                   Spawns, Fixtures/{football, basketball, volleyball};
##   scenes/sport/sport_ball.tscn — мяч SportBall (сфера + три модели);
##   scenes/playground_sport.tscn (+ _basketball, _volleyball) — площадка: зал, P1 / P2, мяч, камера, SportMatch, HUD, SportHud.
## Модули — кит Old NULL Hall и Sport_* (tools/blender/arena_null_hall.py). Порядок:
##   blender -b --python tools/blender/arena_null_hall.py -- --export Sport_Ball_Foot Sport_Ball_Basket Sport_Ball_Volley Sport_Goal Sport_Hoop Sport_Net
##   godot --headless --path godot --import
##   godot --headless --path godot res://tools/build_sport_hall.tscn     (сценой, а не -s: нужен autoload Tuning)
##   godot --headless --path godot --import                               (если builder написал «нужен переимпорт»: материалы по ролям)
## Числа поля и снарядов — Tuning.SPORT_* / Tuning.SPORTS (правило 3 ASSET_PIPELINE): поменял число — пересобери сцену.
extends Node

const OUT := "res://scenes/arena/sport_hall.tscn"
const BALL_OUT := "res://scenes/sport/sport_ball.tscn"
const PLAYGROUNDS := {
	"football": "res://scenes/playground_sport.tscn",
	"basketball": "res://scenes/playground_sport_basketball.tscn",
	"volleyball": "res://scenes/playground_sport_volleyball.tscn",
}
const SCRIPT := "res://scenes/arena/sport_hall.gd"
const KIT := "res://assets/models/arena/null_hall/%s.glb"
const KIT_DIR := "res://assets/models/arena/null_hall/"
const IMPORT_SCRIPT := "res://tools/import/role_import.gd"
const GRID_SHADER := "res://assets/shaders/energy_grid.gdshader"
const SPORT_MODULES := ["Sport_Ball_Foot", "Sport_Ball_Basket", "Sport_Ball_Volley", "Sport_Goal", "Sport_Hoop", "Sport_Net"]
const BALL_MODELS := {"football": "Sport_Ball_Foot", "basketball": "Sport_Ball_Basket", "volleyball": "Sport_Ball_Volley"}

const Z_BACK := -5.2
## ворота Sport_Goal: глубина до стены, высота спинки (крыша поднимается от перекладины к стене)
const GOAL_BACK_H := 3.7
const ROOF_T := 0.14
## кольцо Sport_Hoop: центр кольца от стены и радиус осевой окружности дужки
const HOOP_CX := 1.5
const HOOP_RIM := 1.04
const NET_BODY_W := 0.3

var hall: Node3D
var errors := 0
var _kit_cache := {}
var _half_w: float = Tuning.SPORT_FIELD_HALF_W
var _height: float = Tuning.SPORT_FIELD_H


func _ready() -> void:
	var patched := _patch_imports()
	hall = Node3D.new()
	hall.name = "SportHall"
	hall.set_script(load(SCRIPT))
	_environment()
	_floor()
	_walls()
	_structure()
	_lights()
	_grids()
	_board()
	_spawns()
	_fixtures()
	var err := _save(hall, OUT)
	hall.free()
	if err == OK:
		err = _build_ball()
	if err == OK:
		for id in PLAYGROUNDS:
			var e := _build_playground(String(id), String(PLAYGROUNDS[id]))
			if e != OK:
				err = e
	print("build_sport_hall → %s (%s) errors=%d" % [OUT, error_string(err), errors])
	if patched:
		print("build_sport_hall: import_script у Sport_*.glb новый — нужен переимпорт: godot --headless --path godot --import")
	get_tree().quit(1 if errors > 0 or err != OK else 0)


func _save(root: Node, path: String) -> Error:
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err == OK:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		err = ResourceSaver.save(ps, path)
	if err != OK:
		push_error("не сохранить %s: %s" % [path, error_string(err)])
		errors += 1
	return err


## Модули Sport_* получают материалы по ролям (assets/materials/null_hall/<Роль>.tres) — как остальной кит зала.
func _patch_imports() -> bool:
	var patched := false
	var line := "import_script/path=\"%s\"" % IMPORT_SCRIPT
	var re := RegEx.create_from_string("(?m)^import_script/path=.*$")
	for m in SPORT_MODULES:
		var ipath: String = KIT_DIR + String(m) + ".glb.import"
		if not FileAccess.file_exists(ipath):
			push_error("нет %s — сначала godot --headless --path godot --import" % ipath)
			errors += 1
			continue
		var text := FileAccess.get_file_as_string(ipath)
		if text.contains(line):
			continue
		if re.search(text) != null:
			text = re.sub(text, line)
		else:
			text = text.replace("[params]\n", "[params]\n\n%s\n" % line)
		var f := FileAccess.open(ipath, FileAccess.WRITE)
		f.store_string(text)
		f.close()
		patched = true
	return patched


func _group(n: String, parent: Node3D = null) -> Node3D:
	var g := Node3D.new()
	g.name = n
	(parent if parent != null else hall).add_child(g)
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


func _body(parent: Node3D, n: String, shape: Shape3D, pos: Vector3, roll_deg := 0.0) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = n
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = shape
	b.add_child(cs)
	parent.add_child(b)
	b.owner = hall
	cs.owner = hall
	b.position = pos
	b.rotation_degrees = Vector3(0.0, 0.0, roll_deg)
	return b


func _box(size: Vector3) -> BoxShape3D:
	var bs := BoxShape3D.new()
	bs.size = size
	return bs


# ------------------------------------------------------------------ зал

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.68)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.09, 0.11, 0.2)
	env.fog_density = 0.008
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	hall.add_child(we)
	we.owner = hall


func _floor() -> void:
	var g := _group("Floor")
	for ix in 5:
		for zi in 2:
			_place("Floor_Platform", g, Vector3(-12.0 + 6.0 * ix, -0.6, -3.0 + 6.0 * zi), 0.0, "Plate_%d_%d" % [ix, zi])
	var w := _half_w * 2.0 + 4.0
	_body(g, "FloorBody", _box(Vector3(w, 1.0, 14.0)), Vector3(0.0, -0.5, 0.0))
	_body(g, "CeilingBody", _box(Vector3(w, 1.0, 14.0)), Vector3(0.0, _height + 0.5, 0.0))
	for sx: float in [-1.0, 1.0]:
		_body(g, "WallBody_L" if sx < 0.0 else "WallBody_R", _box(Vector3(2.0, _height + 4.0, 14.0)), Vector3(sx * (_half_w + 1.0), _height * 0.5, 0.0))
	# центральная линия поля — светящийся шов поперёк пола
	_place("Floor_Seam", g, Vector3(0.0, 0.0, 0.0), 0.0, "CentreLine")


func _walls() -> void:
	var g := _group("Walls")
	for i in 4:
		var x := -9.09 + 6.06 * i
		_place("Wall_Panel_01" if i == 1 else "Wall_Panel", g, Vector3(x, 0.0, Z_BACK), 0.0, "Back_%d" % i)
		_place("Wall_Panel", g, Vector3(x, 8.0, Z_BACK), 0.0, "BackTop_%d" % i, Vector3(1.0, 0.5, 1.0))
	for sx: float in [-1.0, 1.0]:
		var tag := "L" if sx < 0.0 else "R"
		for zi in 2:
			var z := -3.0 + 6.1 * zi
			_place("Wall_Panel", g, Vector3(sx * (_half_w + 0.05), 0.0, z), 90.0 * -sx, "Side%s_%d" % [tag, zi])
			_place("Wall_Panel", g, Vector3(sx * (_half_w + 0.05), 8.0, z), 90.0 * -sx, "Side%sTop_%d" % [tag, zi], Vector3(1.0, 0.5, 1.0))


func _structure() -> void:
	var g := _group("Structure")
	for x in [-10.4, -5.6, 5.6, 10.4]:
		_place("Support_Column", g, Vector3(x, 0.0, Z_BACK + 0.9), 0.0, "Column_%d" % int(x))
	for x in [-8.0, 0.0, 8.0]:
		_place("Light_Rig", g, Vector3(x, _height + 0.7, -1.6), 0.0, "Rig_%d" % int(x))
	# цвета команд: P1 синий слева, P2 красный справа (Tuning.PLAYER_COLORS)
	_place("Banner_Blue", g, Vector3(-8.2, 9.6, Z_BACK + 0.15), 0.0, "Banner_L")
	_place("Banner_Red", g, Vector3(8.2, 9.6, Z_BACK + 0.15), 0.0, "Banner_R")
	_place("Speaker", g, Vector3(-5.6, 9.6, -3.0), 0.0, "Speaker_L")
	_place("Speaker", g, Vector3(5.6, 9.6, -3.0), 0.0, "Speaker_R")
	_place("Cables_Pipes", g, Vector3(-8.0, 3.4, Z_BACK + 0.35), 0.0, "Cables_L")
	_place("Cables_Pipes", g, Vector3(8.0, 3.4, Z_BACK + 0.35), 0.0, "Cables_R")
	_place("Crate", g, Vector3(-10.2, 0.0, -4.0), 12.0, "Crate_0")
	_place("Crate", g, Vector3(10.1, 0.0, -3.9), -9.0, "Crate_1")
	_place("Tech_Box", g, Vector3(4.6, 0.0, -4.3), 0.0, "TechBox")


func _lights() -> void:
	var g := _group("Lights")
	var i := 0
	for x in [-8.0, 0.0, 8.0]:
		var s := SpotLight3D.new()
		s.name = "Spot_%d" % i
		g.add_child(s)
		s.owner = hall
		s.position = Vector3(x, _height + 0.4, -1.2)
		s.look_at_from_position(s.position, Vector3(x, 0.0, 0.6), Vector3.UP)
		s.light_color = Color(1.0, 0.92, 0.82)
		s.light_energy = 7.0
		s.spot_range = 26.0
		s.spot_angle = 46.0
		s.spot_attenuation = 0.9
		s.shadow_enabled = false
		i += 1
	i = 0
	for spec in [[-7.5, Color(0.5, 0.68, 1.0)], [0.0, Color(1.0, 0.8, 0.6)], [7.5, Color(1.0, 0.55, 0.45)]]:
		var o := OmniLight3D.new()
		o.name = "Fill_%d" % i
		g.add_child(o)
		o.owner = hall
		o.position = Vector3(float(spec[0]), 3.2, 5.0)
		o.light_color = spec[1]
		o.light_energy = 2.0
		o.omni_range = 18.0
		o.omni_attenuation = 1.1
		o.shadow_enabled = false
		i += 1
	for k in 4:
		var w := OmniLight3D.new()
		w.name = "Wall_%d" % k
		g.add_child(w)
		w.owner = hall
		w.position = Vector3(-9.0 + 6.0 * k, 3.8, -3.4)
		w.light_color = Color(1.0, 0.8, 0.58)
		w.light_energy = 2.0
		w.omni_range = 11.0
		w.omni_attenuation = 1.1
		w.shadow_enabled = false


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


## Энергетическая сетка (как в тренировочном зале): боковые стены в цветах команд, полосы у пола и под потолком задней стены.
func _grids() -> void:
	var g := _group("Grids")
	var blue := Color(0.25, 0.55, 1.0)
	var red := Color(1.0, 0.32, 0.25)
	var white := Color(0.7, 0.88, 1.0)
	_grid(g, "SideGrid_L", Vector2(12.0, _height), Vector3(-_half_w + 0.12, _height * 0.5, 0.6), 90.0, _grid_material(blue, Vector2(24, 20), 1.9, 0.08))
	_grid(g, "SideGrid_R", Vector2(12.0, _height), Vector3(_half_w - 0.12, _height * 0.5, 0.6), -90.0, _grid_material(red, Vector2(24, 20), 1.9, 0.08))
	_grid(g, "FloorBand", Vector2(22.0, 1.4), Vector3(0.0, 0.7, Z_BACK + 0.15), 0.0, _grid_material(white, Vector2(44, 3), 1.5, 0.05, 0.0, 0.7))
	_grid(g, "CeilBand", Vector2(22.0, 1.8), Vector3(0.0, _height - 0.9, Z_BACK + 0.15), 0.0, _grid_material(white, Vector2(44, 4), 1.5, 0.05, 0.7, 0.0))


func _board_font() -> Font:
	var path := "res://assets/fonts/Oswald.ttf"
	return load(path) as Font if ResourceLoader.exists(path) else null


func _label(parent: Node3D, n: String, text: String, pos: Vector3, px: int, col: Color) -> void:
	var l := Label3D.new()
	l.name = n
	l.text = text
	l.position = pos
	l.pixel_size = 0.01
	l.font_size = px
	l.outline_size = 0
	l.modulate = col
	l.shaded = false
	l.double_sided = false
	var f := _board_font()
	if f != null:
		l.font = f
	parent.add_child(l)
	l.owner = hall


## Табло на задней стене: большой экран кита, на нём счёт цветами команд и строка «ВИД · ДО N». Стоит низко — в кадре и при
## ближнем плане камеры (верх кадра занят HUD).
func _board() -> void:
	var g := _group("Board")
	g.position = Vector3(0.0, 3.4, Z_BACK + 0.55)
	_place("Big_Screen", g, Vector3.ZERO, 0.0, "Screen", Vector3.ONE * 0.75)
	var blue: Color = (Tuning.PLAYER_COLORS[0] as Color).lightened(0.45)
	var red: Color = (Tuning.PLAYER_COLORS[1] as Color).lightened(0.4)
	_label(g, "ScoreL", "0", Vector3(-1.45, 2.1, 0.06), 180, blue)
	_label(g, "Colon", ":", Vector3(0.0, 2.2, 0.06), 140, Color(0.9, 0.93, 1.0))
	_label(g, "ScoreR", "0", Vector3(1.45, 2.1, 0.06), 180, red)
	_label(g, "Sub", "", Vector3(0.0, 0.66, 0.06), 50, Color(1.0, 0.82, 0.35))


func _spawns() -> void:
	var g := _group("Spawns")
	var xs := [-Tuning.SPORT_SPAWN_X, Tuning.SPORT_SPAWN_X, -Tuning.SPORT_SPAWN_X - 2.6, Tuning.SPORT_SPAWN_X + 2.6]
	for i in xs.size():
		var m := Marker3D.new()
		m.name = "Spawn%d" % i
		g.add_child(m)
		m.owner = hall
		m.position = Vector3(float(xs[i]), 0.05, 0.0)


# ------------------------------------------------------------------ снаряды

func _fixtures() -> void:
	var fx := _group("Fixtures")
	_football(_group("football", fx))
	_basketball(_group("basketball", fx))
	_volleyball(_group("volleyball", fx))


func _football(g: Node3D) -> void:
	var r: Dictionary = Tuning.SPORTS["football"]
	var gx := float(r["goal_x"])
	var gh := float(r["goal_h"])
	var depth := _half_w - gx
	for sx: float in [-1.0, 1.0]:
		var tag := "L" if sx < 0.0 else "R"
		# модель: проём смотрит в +X, значит левые ворота без поворота, правые — на 180°; глубина модели 1.8 м → до стены
		_place("Sport_Goal", g, Vector3(sx * gx, 0.0, 0.0), 0.0 if sx < 0.0 else 180.0, "Goal_" + tag, Vector3(depth / 1.8, 1.0, 1.0))
		_place("Floor_Seam", g, Vector3(sx * gx, 0.0, 0.0), 0.0, "GoalLine_" + tag, Vector3(0.6, 1.0, 0.5))
		# крыша ворот: от перекладины (gx, gh) вверх к стене (GOAL_BACK_H) — мяч сверху скатывается в поле
		var rise := GOAL_BACK_H - gh
		var len := sqrt(depth * depth + rise * rise)
		var ang := rad_to_deg(atan2(rise, depth))
		_body(g, "GoalRoof_" + tag, _box(Vector3(len, ROOF_T, 3.0)),
			Vector3(sx * (gx + depth * 0.5), gh + rise * 0.5 + ROOF_T * 0.5, 0.0), ang * sx)
		var bar := SphereShape3D.new()
		bar.radius = 0.09
		_body(g, "Crossbar_" + tag, bar, Vector3(sx * gx, gh + 0.06, 0.0))


func _basketball(g: Node3D) -> void:
	var r: Dictionary = Tuning.SPORTS["basketball"]
	var hy := float(r["hoop_y"])
	if not is_equal_approx(_half_w - float(r["hoop_x"]), HOOP_CX):
		push_error("SPORTS.basketball.hoop_x не совпадает с моделью Sport_Hoop (центр кольца %.2f м от стены)" % HOOP_CX)
		errors += 1
	for sx: float in [-1.0, 1.0]:
		var tag := "L" if sx < 0.0 else "R"
		var wx := sx * _half_w
		_place("Sport_Hoop", g, Vector3(wx, hy, 0.0), 0.0 if sx < 0.0 else 180.0, "Hoop_" + tag)
		_body(g, "Board_" + tag, _box(Vector3(0.26, 2.0, 3.0)), Vector3(wx - sx * 0.13, hy + 0.75, 0.0))
		_body(g, "RimBack_" + tag, _box(Vector3(0.24, 0.12, 3.0)), Vector3(wx - sx * (HOOP_CX - HOOP_RIM - 0.02), hy, 0.0))
		var rim := SphereShape3D.new()
		rim.radius = 0.06
		_body(g, "RimFront_" + tag, rim, Vector3(wx - sx * (HOOP_CX + HOOP_RIM), hy, 0.0))


func _volleyball(g: Node3D) -> void:
	var r: Dictionary = Tuning.SPORTS["volleyball"]
	var nh := float(r["net_h"])
	_place("Sport_Net", g, Vector3.ZERO, 0.0, "Net", Vector3(1.0, nh / 3.4, 1.0))
	_body(g, "NetBody", _box(Vector3(NET_BODY_W, nh, 3.0)), Vector3(0.0, nh * 0.5, 0.0))
	# над сеткой — стенка только для кукол (мяч её не замечает: SportHallArena.ball_passthrough → исключение столкновений)
	_body(g, "DollBarrier", _box(Vector3(NET_BODY_W, _height - nh, 3.0)), Vector3(0.0, nh + (_height - nh) * 0.5, 0.0))
	var mat := _grid_material(Color(0.7, 0.88, 1.0), Vector2(1, 12), 0.9, 0.02, 0.25, 0.0)
	_grid(g, "BarrierGlow", Vector2(3.0, _height - nh), Vector3(0.0, nh + (_height - nh) * 0.5, 0.0), 90.0, mat)


# ------------------------------------------------------------------ мяч и площадки

func _build_ball() -> Error:
	var ball := RigidBody3D.new()
	ball.name = "SportBall"
	ball.set_script(load("res://scripts/sport/sport_ball.gd"))
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var sh := SphereShape3D.new()
	sh.radius = Tuning.SPORT_BALL_RADIUS
	cs.shape = sh
	ball.add_child(cs)
	cs.owner = ball
	for id in BALL_MODELS:
		var ps := _kit(String(BALL_MODELS[id]))
		if ps == null:
			continue
		var m := ps.instantiate() as Node3D
		m.name = "Model_" + String(id)
		m.scale = Vector3.ONE * (Tuning.SPORT_BALL_RADIUS / 0.4)
		m.visible = String(id) == "football"
		ball.add_child(m)
		m.owner = ball
	var err := _save(ball, BALL_OUT)
	ball.free()
	return err


func _build_playground(id: String, out: String) -> Error:
	var pg := Node3D.new()
	pg.name = "Playground"
	pg.set_script(load("res://scenes/sport/playground_sport.gd"))
	pg.set("arena_id", "sport")
	pg.set("sport", id)
	var arena := (load(OUT) as PackedScene).instantiate()
	arena.name = "SportHall"
	pg.add_child(arena)
	arena.owner = pg
	arena.add_to_group("arena", true)
	var doll_scenes := ["res://scenes/doll/doll.tscn", "res://scenes/doll/doll_dark.tscn"]
	for i in 2:
		var d := (load(doll_scenes[i]) as PackedScene).instantiate() as Node3D
		d.name = "P%d" % (i + 1)
		d.position = Vector3(Tuning.SPORT_SPAWN_X * (-1.0 if i == 0 else 1.0), 0.05, 0.0)
		d.set("player_index", i)
		d.set("input_prefix", "p%d" % (i + 1))
		pg.add_child(d)
		d.owner = pg
		d.add_to_group("dolls", true)
		d.add_to_group("sport_cam", true)
	var ball := (load(BALL_OUT) as PackedScene).instantiate() as Node3D
	ball.name = "Ball"
	ball.position = Vector3(0.0, float(Tuning.SPORTS[id]["ball_y"]), 0.0)
	pg.add_child(ball)
	ball.owner = pg
	ball.add_to_group("sport_cam", true)
	var w := Node3D.new()
	w.name = "Weapons"
	pg.add_child(w)
	w.owner = pg
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.set_script(load("res://scenes/camera/dynamic_camera.gd"))
	cam.fov = 30.0
	cam.far = 300.0
	cam.position = Vector3(0.0, 5.0, 26.0)
	cam.set("arena_path", NodePath("../SportHall"))
	cam.set("target_group", "sport_cam")
	cam.set("floor_inset", 0.0)
	cam.set("padding", 3.2)
	cam.set("padding_y", 2.4)
	cam.set("min_half_height", 4.6)
	cam.set("fit_bounds", true)
	cam.set("zoom_out_tau", 0.25)
	cam.set("zoom_in_tau", 1.1)
	cam.set("follow_tau", 0.3)
	pg.add_child(cam)
	cam.owner = pg
	cam.add_to_group("camera", true)
	var m := Node.new()
	m.name = "Match"
	m.set_script(load("res://scripts/sport/sport_match.gd"))
	m.set("camera_path", NodePath("../Camera"))
	m.set("arena_path", NodePath("../SportHall"))
	m.set("ball_path", NodePath("../Ball"))
	m.set("sport", id)
	pg.add_child(m)
	m.owner = pg
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	hud.name = "HUD"
	pg.add_child(hud)
	hud.owner = pg
	var sh := CanvasLayer.new()
	sh.name = "SportHud"
	sh.set_script(load("res://scenes/sport/sport_hud.gd"))
	sh.layer = 11
	pg.add_child(sh)
	sh.owner = pg
	var ui := CanvasLayer.new()
	ui.name = "UI"
	pg.add_child(ui)
	ui.owner = pg
	var hint := Label.new()
	hint.name = "Hint"
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = 20.0
	hint.offset_top = -46.0
	hint.offset_right = 1900.0
	hint.offset_bottom = -12.0
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hint.add_theme_constant_override("outline_size", 7)
	hint.add_theme_font_size_override("font_size", 22)
	ui.add_child(hint)
	hint.owner = pg
	var err := _save(pg, out)
	pg.free()
	return err
