## Builder арены 01 «Old NULL Hall» (docs/plan-demo/ART_NULL.md, лист 5): материалы по ролям, пост-импорт кита, сцена.
##   assets/materials/null_hall/<Роль>.tres           — Hall_Steel, Hall_Yellow, Hall_LightWarm, Hall_Screen, Hall_NullGlow, …
##   assets/models/arena/null_hall/*.glb.import       — import_script/path = tools/import/role_import.gd
##   scenes/arena/null_hall.tscn                      — зал «STANDARD (1v1)» с листа (ниже)
## Порядок: blender -b --python tools/blender/arena_null_hall.py -- --export
##          godot --headless --path godot --import
##          godot --headless --path godot -s res://tools/build_null_hall.gd
##          godot --headless --path godot --import        (если builder напишет, что материалы/импорт новые)
##
## Координаты: X вбок, Y вверх, бой в плоскости z = 0, камера с +Z. Зал — полукольцо позади поля (центр кольца в нуле):
## три яруса трибун по 11 секций (радиусы 24 / 25.5 / 27 м, высоты 0 / 6.5 / 13 м), колонны на стыках, мостки над
## верхним ярусом, стена с «01» по центру, большой экран справа сверху, табло слева, баннеры, фермы света, ворота бойцов
## по краям нижнего яруса. Поле: эллипс якорей мембраны 30 × 21 м (центр (0, 10.5), z = −2.5), эмиттеры внизу по краям,
## пол из платформ. Зрители — два MultiMesh (сидят / болеют) с цветом на экземпляр.
## Дерево: Node3D "NullHall" (null_hall.gd) ← Environment, Lights, Floor, Stands, Structure, Boards, Decor, Crowd,
##   Membrane (якоря Anchor_<i>), Spawns (Spawn0..3).
extends SceneTree

const OUT := "res://scenes/arena/null_hall.tscn"
const SCRIPT := "res://scenes/arena/null_hall.gd"
const KIT := "res://assets/models/arena/null_hall/%s.glb"
const KIT_DIR := "res://assets/models/arena/null_hall/"
const MAT_DIR := "res://assets/materials/null_hall/"
const IMPORT_SCRIPT := "res://tools/import/role_import.gd"
const CROWD_SCRIPT := "res://scenes/arena/crowd_multimesh.gd"
const PBR := "res://assets/textures/pbr/%s/%s.png"

# трибуны
const HALL_R := [24.0, 25.5, 27.0]
const TIER_Y := [0.0, 6.5, 13.0]
const SEGMENTS := 11
const ARC_FROM := 196.0          # градусы в плоскости XZ: 180 — слева (−X), 270 — позади (−Z), 360 — справа
const ARC_TO := 344.0
const STAND_ROWS := 5
const SEATS := 10
# поле и мембрана
## купол поля (лор §4: «LARGE HEMISPHERE / DOME»): полуэллипс над полом, центр — середина пола
const DOME_A := 16.0             # полуширина
const DOME_B := 19.0             # высота
const DOME_DEPTH := 2.5          # полуглубина ленты мембраны по z (лента z = −2.5..2.5)
const ANCHORS := 9               # якоря по дуге (без ног — там эмиттеры)
const ANCHOR_Z := -3.0           # за задним краем ленты
const SPAWN_X: Array[float] = [-5.0, 5.0, -9.0, 9.0]
const SPAWN_Y := 2.5
const FIELD_SCRIPT := "res://scenes/arena/null_field.gd"
const MEMBRANE_SHADER := "res://assets/shaders/null_membrane.gdshader"
const PLAYGROUND_OUT := "res://scenes/playground_null_hall.tscn"
const BEAM_SHADER := "res://assets/shaders/light_beam.gdshader"
const DRONE_SCRIPT := "res://scenes/arena/drone_orbit.gd"
const N0_HOST_SCRIPT := "res://scripts/n0/n0_host.gd"
## толпа: спрайты модульных существ (tools/blender/crowd_sprites.py), приглушены в шейдере (brightness) — фон не спорит с бойцами
const CROWD_ATLAS := "res://assets/textures/crowd/crowd_atlas.png"
const CROWD_META := "res://assets/textures/crowd/crowd_atlas.json"
const CROWD_SHADER := "res://assets/shaders/crowd_sprite.gdshader"
const CROWD_EMPTY := 0.12                  # доля пустых мест
const CROWD_SCALE := Vector2(0.62, 0.74)   # масштаб спрайта (кукла кита ~1.8 м → зритель 1.1–1.35 м)

const MATS := {
	"Hall_Steel": {"pbr": "paint_marks", "tint": [0.085, 0.09, 0.105], "rough": 0.75, "metal": 0.35},
	"Hall_SteelDark": {"flat": [0.028, 0.029, 0.033], "rough": 0.45, "metal": 0.6},
	"Hall_Plate": {"pbr": "stone", "tint": [0.24, 0.24, 0.27], "rough": 0.85},
	"Hall_Yellow": {"pbr": "paint_marks", "tint": [1.0, 0.52, 0.02], "rough": 0.8},
	"Hall_ClothRed": {"pbr": "fabric_red", "tint": [1.0, 1.0, 1.0], "rough": 0.9},
	"Hall_ClothBlue": {"pbr": "fabric_blue", "tint": [1.0, 1.0, 1.0], "rough": 0.9},
	"Hall_Seat": {"flat": [0.05, 0.07, 0.12], "rough": 0.6},
	"Hall_PrintWhite": {"flat": [0.55, 0.55, 0.54], "rough": 0.6},
	"Hall_PrintDark": {"flat": [0.035, 0.036, 0.04], "rough": 0.7},
	"Hall_Rubber": {"flat": [0.02, 0.02, 0.02], "rough": 0.8},
	"Hall_LightWarm": {"flat": [0.9, 0.5, 0.2], "rough": 0.3, "glow": [1.0, 0.52, 0.16], "energy": 3.0},
	"Hall_LightCool": {"flat": [0.9, 0.92, 1.0], "rough": 0.2, "glow": [1.0, 0.95, 0.88], "energy": 4.0},
	"Hall_Screen": {"flat": [0.01, 0.02, 0.05], "rough": 0.15, "glow": [0.03, 0.12, 0.42], "energy": 1.0},
	"Hall_NullGlow": {"flat": [0.1, 0.3, 0.6], "rough": 0.2, "glow": [0.25, 0.62, 1.0], "energy": 3.0},
	"Hall_Glass": {"flat": [0.02, 0.03, 0.05], "rough": 0.05, "metal": 0.2},
}

var errors := 0
var hall: Node3D
var rng := RandomNumberGenerator.new()
var scenes := {}


func _init() -> void:
	rng.seed = 1101
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAT_DIR))
	var fresh := _build_materials()
	var patched := _patch_imports()
	if fresh or patched:
		print("build_null_hall: материалы или import_script новые — нужен переимпорт: godot --headless --path godot --import")
	_build_scene()
	print("build_null_hall: done, errors=%d" % errors)
	quit(1 if errors > 0 else 0)


# --- материалы ---

func _build_materials() -> bool:
	var fresh := false
	for role in MATS:
		var d: Dictionary = MATS[role]
		var path: String = MAT_DIR + role + ".tres"
		if not FileAccess.file_exists(path):
			fresh = true
		var m := StandardMaterial3D.new()
		m.resource_name = role
		m.roughness = float(d.get("rough", 0.7))
		m.metallic = float(d.get("metal", 0.0))
		if d.has("pbr"):
			var alb := _tex(String(d["pbr"]), "albedo")
			if alb == null:
				_err("%s: нет текстур %s" % [role, d["pbr"]])
				continue
			m.albedo_texture = alb
			var t: Array = d["tint"]
			m.albedo_color = Color(t[0], t[1], t[2]).linear_to_srgb()
			var r := _tex(String(d["pbr"]), "roughness")
			if r != null:
				m.roughness_texture = r
			var n := _tex(String(d["pbr"]), "normal")
			if n != null:
				m.normal_enabled = true
				m.normal_texture = n
		else:
			var f: Array = d["flat"]
			m.albedo_color = Color(f[0], f[1], f[2]).linear_to_srgb()
		if d.get("vertex_color", false):
			m.vertex_color_use_as_albedo = true
		if d.has("glow"):
			var g: Array = d["glow"]
			m.emission_enabled = true
			m.emission = Color(g[0], g[1], g[2]).linear_to_srgb()
			m.emission_energy_multiplier = float(d.get("energy", 1.0))
		if ResourceSaver.save(m, path) != OK:
			_err("не сохранить " + path)
	return fresh


func _tex(folder: String, ch: String) -> Texture2D:
	var p := PBR % [folder, ch]
	return load(p) if ResourceLoader.exists(p) else null


func _patch_imports() -> bool:
	var patched := false
	var dir := DirAccess.open(KIT_DIR)
	if dir == null:
		_err("нет " + KIT_DIR)
		return false
	var line := "import_script/path=\"%s\"" % IMPORT_SCRIPT
	var re := RegEx.create_from_string("(?m)^import_script/path=.*$")
	for fn in dir.get_files():
		if not fn.ends_with(".glb"):
			continue
		var ipath := KIT_DIR + fn + ".import"
		var text := FileAccess.get_file_as_string(ipath) if FileAccess.file_exists(ipath) else ""
		if text.contains(line):
			continue
		if text == "":
			text = "[remap]\n\nimporter=\"scene\"\nimporter_version=1\n\n[params]\n\n%s\n" % line
		elif re.search(text) != null:
			text = re.sub(text, line)
		elif text.contains("[params]"):
			text = text.replace("[params]\n", "[params]\n\n%s\n" % line)
		else:
			text += "\n[params]\n\n%s\n" % line
		var f := FileAccess.open(ipath, FileAccess.WRITE)
		f.store_string(text)
		f.close()
		patched = true
	return patched


# --- сцена ---

func _kit(name: String) -> PackedScene:
	if not scenes.has(name):
		var p := KIT % name
		scenes[name] = load(p) if ResourceLoader.exists(p) else null
		if scenes[name] == null:
			_err("нет модуля " + p)
	return scenes[name]


func _group(name: String, parent: Node = null) -> Node3D:
	var g := Node3D.new()
	g.name = name
	(parent if parent != null else hall).add_child(g)
	g.owner = hall
	return g


## Модуль кита: позиция, поворот вокруг Y (градусы), масштаб.
func _place(module: String, parent: Node3D, pos: Vector3, yaw_deg := 0.0, node_name := "", scl := 1.0) -> Node3D:
	var ps := _kit(module)
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	n.name = node_name if node_name != "" else module
	parent.add_child(n, true)
	n.owner = hall
	n.position = pos
	n.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	if scl != 1.0:
		n.scale = Vector3.ONE * scl
	return n


## Точка кольца зала: угол в плоскости XZ (180 — слева, 270 — позади, 360 — справа).
static func ring(r: float, deg: float, y: float) -> Vector3:
	var a := deg_to_rad(deg)
	return Vector3(r * cos(a), y, r * sin(a))


## Поворот модуля, чтобы его лицо (+Z) смотрело в центр зала.
static func face_center_yaw(p: Vector3) -> float:
	var d := Vector3(-p.x, 0.0, -p.z).normalized()
	return rad_to_deg(atan2(d.x, d.z))


func _build_scene() -> void:
	hall = Node3D.new()
	hall.name = "NullHall"
	hall.set_script(load(SCRIPT))
	_environment()
	_lights()
	_floor()
	_stands()
	_structure()
	_boards()
	_decor()
	_details()
	_membrane()
	_field()
	_spawns()
	var ps := PackedScene.new()
	var err := ps.pack(hall)
	if err == OK:
		err = ResourceSaver.save(ps, OUT)
	if err != OK:
		_err("сцена %s: %d" % [OUT, err])
	else:
		print("build_null_hall: %s" % OUT)
	hall.free()
	_build_playground()


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.65)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.09, 0.11, 0.2)
	env.fog_density = 0.014
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	hall.add_child(we)
	we.owner = hall


func _lights() -> void:
	var g := _group("Lights")
	var key := DirectionalLight3D.new()
	key.name = "Key"
	key.rotation_degrees = Vector3(-38.0, -20.0, 0.0)
	key.light_color = Color(1.0, 0.86, 0.7)
	key.light_energy = 0.9
	key.shadow_enabled = true
	g.add_child(key)
	key.owner = hall
	var rim := DirectionalLight3D.new()
	rim.name = "Rim"
	rim.rotation_degrees = Vector3(-25.0, 165.0, 0.0)
	rim.light_color = Color(0.5, 0.62, 1.0)
	rim.light_energy = 0.8
	g.add_child(rim)
	rim.owner = hall
	# тёплые практики вдоль ярусов и прожекторы ферм на поле
	for t in range(3):
		for k in range(5):
			var o := OmniLight3D.new()
			o.name = "Warm_%d_%d" % [t, k]
			o.position = ring(HALL_R[t] - 3.0, ARC_FROM + 12.0 + k * (ARC_TO - ARC_FROM - 24.0) / 4.0, TIER_Y[t] + 2.0)
			o.light_color = Color(1.0, 0.58, 0.25)
			o.light_energy = 3.0
			o.omni_range = 11.0
			g.add_child(o)
			o.owner = hall
	for i in range(4):
		var s := SpotLight3D.new()
		s.name = "Spot_%d" % i
		var sp := Vector3(-12.0 + i * 8.0, 26.0, -6.0)
		s.transform = Transform3D(Basis.looking_at(Vector3(-6.0 + i * 4.0, 8.0, 0.0) - sp, Vector3.UP), sp)
		s.light_color = Color(1.0, 0.95, 0.88)
		s.light_energy = 6.0
		s.spot_range = 40.0
		s.spot_angle = 22.0
		s.shadow_enabled = i % 2 == 0
		g.add_child(s)
		s.owner = hall


func _floor() -> void:
	var g := _group("Floor")
	for i in range(8):
		_place("Floor_Platform", g, Vector3(-21.0 + i * 6.0, -0.6, 0.0), 0.0, "Platform_%d" % i)
	# пол зала за полем: платформы сеткой внутри нижнего яруса
	for zi in range(1, 4):
		for xi in range(-3, 4):
			var p := Vector3(xi * 6.0, -0.6, -zi * 6.0)
			if Vector2(p.x, p.z).length() + 4.2 < HALL_R[0]:
				_place("Floor_Platform", g, p, 0.0, "Deck_%d_%d" % [xi + 3, zi])
	# коллизия пола поля (сверху y = 0)
	var body := StaticBody3D.new()
	body.name = "FloorBody"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(46.0, 1.0, 8.0)
	cs.shape = bs
	cs.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(cs)
	g.add_child(body)
	body.owner = hall
	cs.owner = hall


func _stands() -> void:
	var g := _group("Stands")
	var meta := _crowd_meta()
	var variants := int(meta.get("variants", 16))
	var xfs: Array[Transform3D] = []
	var customs: Array[Color] = []
	var step := (ARC_TO - ARC_FROM) / SEGMENTS
	for t in range(3):
		for s in range(SEGMENTS):
			var deg := ARC_FROM + step * (s + 0.5)
			var p := ring(HALL_R[t], deg, TIER_Y[t])
			var yaw := face_center_yaw(p)
			var seg := _place("Stand_Segment", g, p, yaw, "Stand_%d_%d" % [t, s])
			if seg == null:
				continue
			var basis := Basis(Vector3.UP, deg_to_rad(yaw))
			for r in range(STAND_ROWS):
				for k in range(SEATS):
					if rng.randf() < CROWD_EMPTY:
						continue   # свободные места
					# стоят на ступени ряда, чуть за линией сидений; поворот не нужен — спрайт сам смотрит в камеру
					var local := Vector3(-3.0 + 0.3 + k * 0.6 + rng.randf_range(-0.08, 0.08), 0.9 + r * 0.5, -r * 0.9 - 0.9 * 0.5)
					var sc := rng.randf_range(CROWD_SCALE.x, CROWD_SCALE.y)
					xfs.append(Transform3D(Basis.from_scale(Vector3.ONE * sc), p + basis * local))
					customs.append(Color(float(rng.randi() % variants), rng.randf(), rng.randf_range(0.8, 1.15), 0.0))
	var cg := _group("Crowd")
	_crowd_sprites(cg, xfs, customs, meta)


## Метаданные атласа толпы (tools/blender/crowd_sprites.py): сетка, число вариантов и поз, размер ячейки в метрах.
func _crowd_meta() -> Dictionary:
	if not FileAccess.file_exists(CROWD_META):
		_err("нет %s — blender -b --python tools/blender/crowd_sprites.py -- --atlas" % CROWD_META)
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(CROWD_META))
	return d if d is Dictionary else {}


## Толпа — один MultiMesh квадов-спрайтов (CrowdMultiMesh + crowd_sprite.gdshader): квад размером с ячейку атласа, низ — ноги.
func _crowd_sprites(parent: Node3D, xfs: Array[Transform3D], customs: Array[Color], meta: Dictionary) -> void:
	if not ResourceLoader.exists(CROWD_ATLAS):
		_err("нет %s — сначала атлас и --import" % CROWD_ATLAS)
		return
	var cell: Array = meta.get("cell_m", [1.25, 2.25])
	var quad := QuadMesh.new()
	quad.size = Vector2(float(cell[0]), float(cell[1]))
	quad.center_offset = Vector3(0.0, float(cell[1]) * 0.5, 0.0)
	var mat := ShaderMaterial.new()
	mat.shader = load(CROWD_SHADER)
	mat.set_shader_parameter("atlas", load(CROWD_ATLAS))
	mat.set_shader_parameter("cols", float(meta.get("cols", 8)))
	mat.set_shader_parameter("rows", float(meta.get("rows", 6)))
	mat.set_shader_parameter("poses", float(meta.get("poses", 3)))
	var data := PackedFloat32Array()
	var colors := PackedColorArray()
	for xf in xfs:
		data.append_array([xf.basis.x.x, xf.basis.x.y, xf.basis.x.z, xf.basis.y.x, xf.basis.y.y, xf.basis.y.z,
			xf.basis.z.x, xf.basis.z.y, xf.basis.z.z, xf.origin.x, xf.origin.y, xf.origin.z])
		colors.append(Color.WHITE)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Spectators"
	mmi.set_script(load(CROWD_SCRIPT))
	mmi.set("mesh", quad)
	mmi.set("xforms", data)
	mmi.set("colors", colors)
	mmi.set("customs", PackedColorArray(customs))
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.add_to_group("null_hall_crowd", true)
	parent.add_child(mmi)
	mmi.owner = hall
	print("build_null_hall: зрители-спрайты × %d (вариантов %d)" % [xfs.size(), int(meta.get("variants", 0))])


func _structure() -> void:
	var g := _group("Structure")
	var step := (ARC_TO - ARC_FROM) / SEGMENTS
	# колонны на каждом втором стыке, по две друг на друге
	for s in range(0, SEGMENTS + 1, 2):
		var deg := ARC_FROM + step * s
		for lvl in range(2):
			var p := ring(HALL_R[0] - 1.2, deg, lvl * 12.0)
			_place("Support_Column", g, p, face_center_yaw(p), "Column_%d_%d" % [s, lvl])
	# мостки над верхним ярусом и перед стеной
	for s in range(SEGMENTS):
		var deg := ARC_FROM + step * (s + 0.5)
		var p := ring(HALL_R[2] - 1.0, deg, 19.2)
		_place("Catwalk", g, p, face_center_yaw(p), "Catwalk_%d" % s)
	# стены за ярусами (закрывают провалы между ярусами)
	for t in range(3):
		for s in range(SEGMENTS):
			var deg := ARC_FROM + step * (s + 0.5)
			var p := ring(HALL_R[t] + 4.75, deg, TIER_Y[t])
			_place("Wall_Panel", g, p, face_center_yaw(p), "TierWall_%d_%d" % [t, s])
	# стена за верхним ярусом: панели, по центру «01»
	for s in range(SEGMENTS):
		var deg := ARC_FROM + step * (s + 0.5)
		var p := ring(HALL_R[2] + 1.6, deg, 17.4)
		var mid := s == SEGMENTS / 2
		_place("Wall_Panel_01" if mid else "Wall_Panel", g, p, face_center_yaw(p), "Wall_%d" % s)
	# лестницы между ярусами (по краям)
	for side in [0, SEGMENTS - 1]:
		var deg: float = ARC_FROM + step * (side + 0.5)
		for t in range(2):
			var p := ring(HALL_R[t] - 3.4, deg + (6.0 if side == 0 else -6.0), TIER_Y[t] + 3.5)
			_place("Stairs", g, p, face_center_yaw(p) + 180.0, "Stairs_%d_%d" % [side, t])
	# ворота бойцов по краям нижнего яруса
	for i in range(2):
		var deg: float = [ARC_FROM - 5.0, ARC_TO + 5.0][i]
		var p := ring(HALL_R[0] - 2.0, deg, 0.0)
		_place("Fighter_Gate", g, p, face_center_yaw(p), ["GateA", "GateB"][i])
	# фермы света над полем, динамики и камеры
	for i in range(4):
		_place("Light_Rig", g, Vector3(-12.0 + i * 8.0, 25.0, -6.0), 0.0, "Rig_%d" % i)
	for i in range(2):
		_place("Speaker", g, Vector3([-17.0, 17.0][i], 24.0, -5.0), [25.0, -25.0][i], "Speaker_%d" % i)
	for i in range(2):
		var p := ring(HALL_R[0] - 1.8, [ARC_FROM + step * 2.0, ARC_TO - step * 2.0][i], 13.0)
		_place("Camera_Broadcast", g, p, face_center_yaw(p) + 90.0, "BroadcastCam_%d" % i)


func _boards() -> void:
	var g := _group("Boards")
	var screen := _place("Big_Screen", g, Vector3(10.5, 20.5, -18.0), -18.0, "BigScreen")
	if screen != null:
		_label(screen, "NULL FIELD", Vector3(0.0, 4.0, 0.05), 0.009, 64, Color(0.6, 0.8, 1.0), "")
		_label(screen, "", Vector3(0.0, 2.55, 0.05), 0.011, 160, Color(0.85, 0.95, 1.0), "null_hall_gravity")
		_label(screen, "", Vector3(0.0, 1.05, 0.05), 0.009, 64, Color(0.6, 0.8, 1.0), "null_hall_membrane")
	var board := _place("Small_Scoreboard", g, Vector3(-11.0, 21.0, -16.0), 16.0, "Scoreboard")
	if board != null:
		_label(board, "GRAVITY", Vector3(0.0, 1.55, 0.08), 0.007, 48, Color(0.6, 0.8, 1.0), "")
		_label(board, "", Vector3(0.0, 0.85, 0.08), 0.008, 96, Color(0.85, 0.95, 1.0), "null_hall_gravity")
	var bg := _group("Banners")
	var step := (ARC_TO - ARC_FROM) / SEGMENTS
	for i in range(5):
		var deg := ARC_FROM + step * (1.0 + i * 2.2)
		var p := ring(HALL_R[2] - 1.4, deg, 18.6)
		_place("Banner_Blue" if i % 2 == 0 else "Banner_Red", bg, p, face_center_yaw(p), "Banner_%d" % i)


func _label(parent: Node3D, text: String, pos: Vector3, pixel: float, size: int, col: Color, group: String) -> void:
	var l := Label3D.new()
	l.name = "Text_%s" % (group if group != "" else text.replace(" ", "_"))
	l.text = text if text != "" else ("↘ 0.35G" if group == "null_hall_gravity" else "MEMBRANE 98%")
	l.position = pos
	l.pixel_size = pixel
	l.font_size = size
	l.outline_size = 0
	l.modulate = col
	l.shaded = false
	l.double_sided = false
	l.font = _board_font()
	if group != "":
		l.add_to_group(group, true)
	parent.add_child(l)
	l.owner = hall


var _font: SystemFont


func _board_font() -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["DejaVu Sans", "Helvetica Neue", "Arial", "Noto Sans"])
		_font.font_weight = 700
	return _font


func _decor() -> void:
	var g := _group("Decor")
	var step := (ARC_TO - ARC_FROM) / SEGMENTS
	for i in range(6):
		var deg := ARC_FROM + step * (0.6 + i * 1.9)
		var p := ring(HALL_R[0] - 3.6, deg, 0.0)
		_place("Crate", g, p, face_center_yaw(p) + rng.randf_range(-20.0, 20.0), "Crate_%d" % i)
	for i in range(4):
		var deg := ARC_FROM + step * (1.5 + i * 2.7)
		var p := ring(HALL_R[1] - 1.6, deg, 6.4)
		_place("Tech_Box", g, p, face_center_yaw(p), "TechBox_%d" % i)
	for i in range(3):
		var deg := ARC_FROM + step * (2.0 + i * 3.5)
		var p := ring(HALL_R[2] + 0.4, deg, 22.5)
		_place("Cables_Pipes", g, p, face_center_yaw(p), "Pipes_%d" % i)
	for i in range(2):   # обломки у ног купола, за лентой мембраны
		_place("Debris", g, Vector3([-19.5, 19.5][i], 0.0, -4.0), rng.randf_range(0.0, 360.0), "Debris_%d" % i, 0.8)


## Детали (на мой вкус, 30.09): лучи прожекторов в дымке, дроны-камеры снаружи купола, большие баннеры под крышей,
## светящиеся швы у ног купола. Всё — фон: не спорит с бойцами (лист камеры, правило «без визуального перегруза»).
func _details() -> void:
	var g := _group("Details")
	# швы купола на полу — там, где мембрана встаёт на пол
	for i in range(2):
		_place("Floor_Seam", g, Vector3([-DOME_A, DOME_A][i], 0.0, 0.0), 0.0, ["Seam_L", "Seam_R"][i])
	# большие баннеры NULL FIGHTING под крышей, по бокам от стены «01»
	for i in range(2):
		var p := ring(HALL_R[2] + 0.2, [252.0, 288.0][i], 27.2)
		_place("Banner_Fighting", g, p, face_center_yaw(p), "BigBanner_%d" % i)
	# лучи прожекторов: по два от каждой фермы (ферма y = 25, z = −6; лампы x ±0.7 и ±2.1 от центра, смотрят вниз-вперёд)
	var beam_ps := _kit("Light_Beam")
	if beam_ps != null:
		var inst := beam_ps.instantiate()
		var mesh: Mesh = null
		for c in inst.find_children("*", "MeshInstance3D", true, false):
			mesh = (c as MeshInstance3D).mesh
			break
		inst.free()
		var mat := ShaderMaterial.new()
		mat.shader = load(BEAM_SHADER)
		mat.set_shader_parameter("intensity", 0.045)
		var aim := Vector3(0.0, -0.8, 0.6).normalized()
		for r in range(4):
			for k in [1, 2]:
				var lamp := Vector3(-12.0 + r * 8.0 + [-2.1, -0.7, 0.7, 2.1][k], 25.0 - 0.66, -6.0 + 0.05)
				var mi := MeshInstance3D.new()
				mi.name = "Beam_%d_%d" % [r, k]
				mi.mesh = mesh
				mi.material_override = mat
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				# локальная −Y луча → aim; длина 24 м, радиус у пола 3.2 м
				var y_axis := -aim
				var x_axis := y_axis.cross(Vector3.FORWARD).normalized()
				var z_axis := x_axis.cross(y_axis).normalized()
				mi.transform = Transform3D(Basis(x_axis * 3.2, y_axis * 24.0, z_axis * 3.2), lamp)
				g.add_child(mi)
				mi.owner = hall
	# дроны-камеры: дугой снаружи купола туда-обратно
	for i in range(3):
		var holder := Node3D.new()
		holder.name = "Drone_%d" % i
		holder.set_script(load(DRONE_SCRIPT))
		holder.set("phase", [0.0, 2.1, 4.2][i])
		holder.set("speed", [0.16, 0.12, 0.2][i])
		holder.set("radii", [Vector2(19.5, 22.0), Vector2(21.0, 23.5), Vector2(18.5, 21.0)][i])
		holder.set("z_base", [1.5, -1.0, 3.0][i])
		g.add_child(holder)
		holder.owner = hall
		_place("Camera_Drone", holder, Vector3.ZERO, 0.0, "Model")


## Якоря по дуге купола за лентой (светящимся торцом вперёд, к ленте) и эмиттеры у ног купола; лента мембраны.
func _membrane() -> void:
	var g := _group("Anchors")
	for i in range(ANCHORS):
		var a := PI * (i + 1) / (ANCHORS + 1)
		var p := Vector3(DOME_A * cos(a), DOME_B * sin(a), ANCHOR_Z)
		var module := "Membrane_Anchor_A" if i % 2 == 0 else "Membrane_Anchor_B"
		_place(module, g, p, 0.0, "Anchor_%d" % i, 0.85)
	for i in range(2):
		var x: float = [-DOME_A - 1.4, DOME_A + 1.4][i]
		_place("Null_Emitter", g, Vector3(x, 0.0, -0.8), [90.0, -90.0][i], ["Emitter_L", "Emitter_R"][i])
	# лента мембраны: полуокружность радиуса 1 из кита, растянута до купола; вид и прогиб — шейдер
	var ps := _kit("Membrane_Strip")
	if ps == null:
		return
	var inst := ps.instantiate()
	var mesh: Mesh = null
	for c in inst.find_children("*", "MeshInstance3D", true, false):
		mesh = (c as MeshInstance3D).mesh
		break
	inst.free()
	var mi := MeshInstance3D.new()
	mi.name = "Membrane"
	mi.mesh = mesh
	mi.scale = Vector3(DOME_A, DOME_B, DOME_DEPTH)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0
	var mat := ShaderMaterial.new()
	mat.shader = load(MEMBRANE_SHADER)
	mat.set_shader_parameter("centre", Vector2.ZERO)
	mat.set_shader_parameter("axes", Vector2(DOME_A, DOME_B))
	mi.material_override = mat
	hall.add_child(mi)
	mi.owner = hall


## Поле NULL: Area3D на весь зал — гравитация (замена) и мембрана (null_field.gd).
func _field() -> void:
	var f := Area3D.new()
	f.name = "Field"
	f.set_script(load(FIELD_SCRIPT))
	f.set("centre", Vector2.ZERO)
	f.set("axes", Vector2(DOME_A, DOME_B))
	f.set("membrane_path", NodePath("../Membrane"))
	f.collision_layer = 0
	f.collision_mask = 0xFFFFFFFF
	f.monitorable = false
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var bs := BoxShape3D.new()
	bs.size = Vector3(80.0, 60.0, 16.0)
	cs.shape = bs
	cs.position = Vector3(0.0, 24.0, 0.0)
	f.add_child(cs)
	hall.add_child(f)
	f.owner = hall
	cs.owner = hall


func _spawns() -> void:
	var g := _group("Spawns")
	for i in range(SPAWN_X.size()):
		var m := Marker3D.new()
		m.name = "Spawn%d" % i
		m.position = Vector3(SPAWN_X[i], SPAWN_Y, 0.0)
		g.add_child(m)
		m.owner = hall


func _err(msg: String) -> void:
	errors += 1
	push_error("build_null_hall: " + msg)


# --- площадка: зал + две куклы + камера по листу камеры + Match + HUD + стрелки за экраном + N0 ---
## Как playground_void.tscn (скрипт scenes/playground.gd, arena_id "null_hall"), но камера по листу камеры (ART_NULL.md, лист 1)
## с поправкой автора 02.10.2026: камера за игроком (follow_mode "humans" — соперник-бот в кадр не тянет), полувысота кадра 3.6 м
## (кукла 1.8 м — четверть высоты; до 11 м, если в бою двое людей), без fit_bounds; соперник за кадром — стрелка с метрами
## от игрока (scenes/ui/offscreen_markers.gd); N0 (scripts/n0/n0_host.gd) летает за плечом игрока, за плоскостью боя, и говорит
## реплики облачком.
func _build_playground() -> void:
	var pg := Node3D.new()
	pg.name = "Playground"
	pg.set_script(load("res://scenes/playground.gd"))
	pg.set("arena_id", "null_hall")
	var arena := (load(OUT) as PackedScene).instantiate()
	arena.name = "NullHall"
	pg.add_child(arena)
	arena.owner = pg
	arena.add_to_group("arena", true)
	var doll_scenes := ["res://scenes/doll/doll.tscn", "res://scenes/doll/doll_dark.tscn"]
	for i in range(2):
		var d := (load(doll_scenes[i]) as PackedScene).instantiate() as Node3D
		d.name = "P%d" % (i + 1)
		d.position = Vector3(SPAWN_X[i], 0.05, 0.0)
		d.set("player_index", i)
		d.set("input_prefix", "p%d" % (i + 1))
		pg.add_child(d)
		d.owner = pg
		d.add_to_group("dolls", true)
	var w := Node3D.new()
	w.name = "Weapons"
	pg.add_child(w)
	w.owner = pg
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.set_script(load("res://scenes/camera/dynamic_camera.gd"))
	cam.fov = 40.0
	cam.far = 400.0
	cam.position = Vector3(0.0, 8.0, 24.0)
	cam.set("arena_path", NodePath("../NullHall"))
	cam.set("floor_inset", 0.0)
	cam.set("padding", 3.0)
	cam.set("padding_y", 2.0)
	cam.set("follow_mode", "humans")
	cam.set("min_half_height", 3.6)
	cam.set("max_half_height", 11.0)
	cam.set("fit_bounds", false)
	cam.set("zoom_out_tau", 0.25)
	cam.set("zoom_in_tau", 1.0)
	cam.set("follow_tau", 0.3)
	pg.add_child(cam)
	cam.owner = pg
	cam.add_to_group("camera", true)
	var m := Node.new()
	m.name = "Match"
	m.set_script(load("res://scripts/core/match.gd"))
	m.set("camera_path", NodePath("../Camera"))
	m.set("arena_path", NodePath("../NullHall"))
	pg.add_child(m)
	m.owner = pg
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	hud.name = "HUD"
	pg.add_child(hud)
	hud.owner = pg
	var marks := CanvasLayer.new()
	marks.name = "Offscreen"
	marks.layer = 5
	marks.set_script(load("res://scenes/ui/offscreen_markers.gd"))
	pg.add_child(marks)
	marks.owner = pg
	var n0 := (load("res://scenes/n0/n0.tscn") as PackedScene).instantiate() as Node3D
	n0.name = "N0"
	n0.position = Vector3(SPAWN_X[0] - 2.0, 4.0, -1.4)
	n0.scale = Vector3.ONE * 0.6
	pg.add_child(n0)
	n0.owner = pg
	var host := Node.new()
	host.name = "Host"
	host.set_script(load(N0_HOST_SCRIPT))
	n0.add_child(host)
	host.owner = pg
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
	hint.offset_right = 1800.0
	hint.offset_bottom = -12.0
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hint.add_theme_constant_override("outline_size", 7)
	hint.add_theme_font_size_override("font_size", 22)
	hint.text = "P1: WASD + Shift + Space, каналы I O P    P2: стрелки + правый Ctrl + Enter    G: поле NULL    L: чемпион лиги    R: заново    1–8: площадки    Esc: пауза"
	ui.add_child(hint)
	hint.owner = pg
	var ps := PackedScene.new()
	var err := ps.pack(pg)
	if err == OK:
		err = ResourceSaver.save(ps, PLAYGROUND_OUT)
	if err != OK:
		_err("площадка %s: %d" % [PLAYGROUND_OUT, err])
	else:
		print("build_null_hall: %s" % PLAYGROUND_OUT)
	pg.free()
