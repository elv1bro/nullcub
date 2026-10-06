## Сборщик сцены главного меню «Гараж + эфир»: scenes/menu/garage_menu.tscn (скрипт поведения — scenes/menu/garage_menu.gd).
## Раскладка — по кадру стиля автора docs/refs/menu-garage/G01-garage-keyframe.png: ворота лифта на скошенном левом углу,
## верстак с перфопанелью и чертежом, разметка стенда (стенд с куклой — спящей мастерской), телевизор на тумбе с полкой трофеев,
## ящики с кружкой на ковре, справа тумба с радио и щиток. 06.10 (мир людей, гараж от первого лица): точки камер — на высоте глаз
## героя, на верстаке консоль связи с нейрошлемом и кресло пилота рядом, в правом углу — стенд экранов с показателями бойца,
## N0-помощник. Модели — assets/models/garage (tools/blender/garage_kit.py).
##   godot --headless --path godot --import                       (после новых glb — сначала импорт)
##   godot --headless --path godot -s res://tools/build_garage_menu.gd
## ВНИМАНИЕ: сборщик перезаписывает сцену целиком — правки в редакторе переносить сюда (таблицы ниже), иначе пропадут.
## Ещё он прописывает import_script/path = tools/garage_import.gd во все Garage_*.glb.import (если поменял — повторить --import).
## Координаты Godot: X вправо, Y вверх, Z к зрителю. Задняя стена z = −3.0, пол y = 0, потолок 3.4.
extends SceneTree

const M := "res://assets/models/garage/Garage_%s.glb"
const OUT := "res://scenes/menu/garage_menu.tscn"
const IMPORT_SCRIPT := "res://tools/garage_import.gd"
const BACK := -3.0
## Глаза героя (06.10: гараж от первого лица — точки камер на этой высоте).
const EYE := 1.66
## Консоль связи на правом краю верстака (верх столешницы 0.92) и точка, где на её подставке лежит нейрошлем (центр обода; в модели
## Garage_LinkConsole — HEADSET_REST, tools/blender/garage_kit.py).
const CONSOLE_POS := Vector3(0.2, 0.92, -2.42)
const CONSOLE_YAW := -12.0
const HEADSET_REST := Vector3(0.13, 0.33, 0.0)
## Стенд экранов поперёк правого заднего угла, лицом в комнату (−X, +Z).
const RACK_POS := Vector3(3.95, 0, -1.87)
const RACK_YAW := -45.0
## Мониторы стенда: модель, место на ферме (x вбок, y высота, z вперёд), что показывает (GarageStatsWall.draw_panel).
const RACK_SCREENS := [
	["Flat", Vector3(-0.71, 2.2, 0.07), "energy"], ["Small", Vector3(-0.19, 2.24, 0.07), "pulse"],
	["Small", Vector3(0.19, 2.24, 0.07), "link"], ["Flat", Vector3(0.71, 2.2, 0.07), "parts"],
	["Small", Vector3(-0.82, 1.62, 0.07), "weapon"], ["Wide", Vector3(0.0, 1.62, 0.07), "main"],
	["Small", Vector3(0.82, 1.62, 0.07), "thrust"],
	["Flat", Vector3(-0.6, 1.1, 0.07), "mass"], ["Small", Vector3(0.0, 1.1, 0.07), "hp"], ["Flat", Vector3(0.6, 1.1, 0.07), "joints"],
	["CRT", Vector3(-0.5, 0.66, 0.3), "league"], ["CRT", Vector3(0.5, 0.66, 0.3), "hall"],
]

var scene_root: Node3D


func _initialize() -> void:
	var patched := _patch_imports()
	scene_root = Node3D.new()
	scene_root.name = "GarageMenu"
	scene_root.set_script(load("res://scenes/menu/garage_menu.gd"))
	_env()
	var room := _group(scene_root, "Room")
	var props := _group(scene_root, "Props")
	var lights := _group(scene_root, "Lights")
	_room(room)
	_props(props)
	_lights(lights)
	_spots(_group(scene_root, "CamSpots"))
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 50.0
	cam.near = 0.03
	scene_root.add_child(cam)
	cam.owner = scene_root
	var ps := PackedScene.new()
	var err := ps.pack(scene_root)
	if err == OK:
		err = ResourceSaver.save(ps, OUT)
	print("build_garage_menu: ", OUT, " err=", err, "  nodes=", scene_root.get_child_count(), "  import patched=", patched)
	if patched > 0:
		print("build_garage_menu: обновлён import_script у %d glb — запусти --import и собери ещё раз" % patched)
	quit(0 if err == OK else 1)


func _patch_imports() -> int:
	var n := 0
	var dir := "res://assets/models/garage/"
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".glb.import"):
			continue
		var p := dir + f
		var txt := FileAccess.get_file_as_string(p)
		if txt.find('import_script/path="%s"' % IMPORT_SCRIPT) >= 0:
			continue
		txt = txt.replace('import_script/path=""', 'import_script/path="%s"' % IMPORT_SCRIPT)
		var fa := FileAccess.open(p, FileAccess.WRITE)
		fa.store_string(txt)
		fa.close()
		n += 1
	return n


func _group(parent: Node, name: String) -> Node3D:
	var g := Node3D.new()
	g.name = name
	parent.add_child(g)
	g.owner = scene_root
	return g


## Ставит модель: pos, поворот вокруг Y (градусы), доп. поворот rot (градусы, XYZ), имя узла.
func put(parent: Node, model: String, pos: Vector3, yaw := 0.0, node_name := "", rot := Vector3.ZERO, path := "") -> Node3D:
	var p := path if path != "" else M % model
	var ps := load(p) as PackedScene
	if ps == null:
		push_error("нет модели " + p)
		return null
	var n := ps.instantiate() as Node3D
	n.name = node_name if node_name != "" else model
	n.position = pos
	n.rotation_degrees = Vector3(rot.x, yaw + rot.y, rot.z)
	parent.add_child(n, true)
	n.owner = scene_root
	return n


# ---------------------------------------------------------------- окружение

func _env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.006, 0.006, 0.01)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.33, 0.46)
	env.ambient_light_energy = 0.07
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.ssao_enabled = true
	env.ssao_intensity = 1.8
	env.ssil_enabled = true
	env.ssil_intensity = 0.8
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.03
	env.volumetric_fog_albedo = Color(0.85, 0.85, 0.9)
	env.volumetric_fog_anisotropy = 0.5
	env.volumetric_fog_length = 20.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.1
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	scene_root.add_child(we)
	we.owner = scene_root


# ---------------------------------------------------------------- комната

func _room(g: Node3D) -> void:
	put(g, "Floor", Vector3(0, 0, 0.5))
	put(g, "Ceiling", Vector3(0, 3.4, 0.5))
	for z in [-2.35, -0.85, 0.65, 2.15]:
		put(g, "Beam", Vector3(0, 3.08, z), 0.0, "Beam")
	# задняя стена (z = −3): x от −2.3 до 4.7
	for x in [-1.3, 0.7, 2.7]:
		put(g, "Wall", Vector3(x, 0, BACK), 0.0, "WallBack")
	put(g, "Wall_Short", Vector3(4.2, 0, BACK), 0.0, "WallBack")
	# скошенный угол с воротами: от (−2.3, −3.0) до (−4.7, −0.6); лицом к (+1, 0, +1)
	put(g, "Gate", Vector3(-3.5, 0, -1.8), 45.0)
	put(g, "Post_Hazard", Vector3(-2.24, 0, -2.86), 0.0, "PostGateR")
	put(g, "Post", Vector3(-4.56, 0, -0.66), 90.0, "PostGateL")
	# левая стена (x = −4.7, лицом в +X) и правая (x = 4.7, лицом в −X)
	# вместо двух секций стены (z −0.6…3.4) — двустворчатые ворота в тренировочный зал (scenes/menu/garage_hall_gate.gd): модуль
	# Fighter_Gate кита Old NULL Hall × 0.58 (проём 2.9 × 2.9), лицом в +X; на время испытания мастерской створки открываются в зал
	var hg := put(g, "HallGate", Vector3(-4.7, 0, 1.2), 90.0, "HallGate", Vector3.ZERO, "res://assets/models/arena/null_hall/Fighter_Gate.glb")
	if hg != null:
		hg.scale = Vector3.ONE * 0.58
		hg.set_script(load("res://scenes/menu/garage_hall_gate.gd"))
	put(g, "Wall_Short", Vector3(-4.7, 0, 3.9), 90.0, "WallLeft")
	for z in [-2.0, 0.0, 2.0]:
		put(g, "Wall", Vector3(4.7, 0, z), -90.0, "WallRight")
	put(g, "Wall_Short", Vector3(4.7, 0, 3.5), -90.0, "WallRight")
	put(g, "Post", Vector3(4.56, 0, -2.86), 0.0, "PostCornerR")
	# трубы под потолком вдоль задней стены, вентиль, колено вниз у ворот
	put(g, "Pipe", Vector3(-0.8, 3.0, -2.82), 0.0, "Pipe")
	put(g, "Pipe", Vector3(2.2, 3.0, -2.82), 0.0, "Pipe")
	put(g, "Valve", Vector3(3.05, 3.0, -2.62), 0.0)
	put(g, "Pipe", Vector3(4.0, 3.0, -1.2), 90.0, "Pipe")


# ---------------------------------------------------------------- предметы

func _props(g: Node3D) -> void:
	# ИСТОРИЯ: телевизор на тумбе, ящики с кружкой, ковёр
	put(g, "Sideboard", Vector3(1.8, 0, -2.68))
	put(g, "TV", Vector3(1.8, 0.62, -2.62), 0.0, "TV")
	put(g, "Rug", Vector3(1.6, 0.0, -0.75), 4.0)
	put(g, "Crate", Vector3(1.62, 0, -1.3), 7.0)
	put(g, "Crate_Small", Vector3(2.28, 0, -1.18), -9.0)
	put(g, "Mug", Vector3(1.48, 0.5, -1.36), 30.0)
	put(g, "Toolbox", Vector3(2.95, 0, -1.65), 22.0)
	# ТРОФЕИ: полка над телевизором и вещи на ней / на телевизоре
	put(g, "Shelf_Wall", Vector3(1.8, 2.32, BACK), 0.0, "TrophyShelf")
	put(g, "Plant", Vector3(0.66, 2.32, -2.86), 0.0, "PlantShelf")
	put(g, "Helmet", Vector3(1.06, 2.32, -2.84), 15.0)
	put(g, "Boombox", Vector3(1.65, 2.32, -2.86), -5.0)
	put(g, "QBox", Vector3(2.22, 2.32, -2.84), 8.0)
	put(g, "Cup_A", Vector3(2.65, 2.32, -2.84))
	put(g, "Cup_B", Vector3(2.96, 2.32, -2.84), 20.0)
	put(g, "Cup_B", Vector3(1.22, 1.64, -2.74), -10.0, "CupTV")
	put(g, "Books", Vector3(2.22, 1.64, -2.74), 8.0)
	put(g, "Plant", Vector3(2.6, 1.64, -2.76), 120.0, "PlantTV")
	# (06.10: кукла больше не сидит на ящике — гараж от первого лица, герой — человек; кукла висит на стенде мастерской всегда:
	# это стенд и кукла спящей встроенной мастерской, scenes/menu/garage_workshop.gd, «витрина»)
	# МАСТЕРСКАЯ: верстак, перфопанель, чертёж, разметка стенда (сам стенд — BuildStand мастерской), лампа
	put(g, "Workbench", Vector3(-0.6, 0, -2.62))
	put(g, "Pegboard", Vector3(-0.6, 0.97, BACK))
	put(g, "Card_Blueprint", Vector3(-1.1, 2.42, BACK), 0.0, "Blueprint")
	put(g, "HazardSquare", Vector3(-0.75, 0.0, -1.2))
	put(g, "Lamp", Vector3(-0.55, 3.4, -2.05), 0.0, "Lamp")
	# пилотское место (06.10, LORE_V2 §2а п. 3): консоль связи с нейрошлемом на правом краю верстака, кресло пилота рядом
	# (кресло брата — он пилотирует отсюда); шлем — отдельный узел: его берут руки героя (scenes/menu/garage_headset.gd)
	var console := put(g, "LinkConsole", CONSOLE_POS, CONSOLE_YAW, "LinkConsole")
	var rest := CONSOLE_POS + Basis(Vector3.UP, deg_to_rad(CONSOLE_YAW)) * HEADSET_REST
	put(g, "NeuroHeadset", rest, CONSOLE_YAW, "Headset")
	if console != null:
		console.set_meta("headset_rest", rest)
	var chair := Vector3(0.95, 0, -1.98)
	var to_stand := Vector3(-0.75, 0, -1.2) - chair
	put(g, "PilotChair", chair, rad_to_deg(atan2(to_stand.x, to_stand.z)) + 25.0, "PilotChair")
	# стена между верстаком и ТВ: флаг лиги, фото, афиша
	put(g, "Banner", Vector3(0.15, 2.86, -2.97), 0.0, "Banner")
	var photos := [["A", Vector3(-1.95, 2.3, BACK), 4.0], ["B", Vector3(-1.9, 1.95, BACK), -6.0], ["C", Vector3(-0.33, 2.58, BACK), 3.0],
		["D", Vector3(-0.31, 2.18, BACK), -4.0], ["E", Vector3(0.66, 1.72, BACK), 6.0], ["F", Vector3(0.7, 2.06, BACK), -3.0]]
	for ph in photos:
		put(g, "Card_Photo_" + String(ph[0]), ph[1], 0.0, "Photo", Vector3(0, 0, float(ph[2])))
	put(g, "Card_Poster_A", Vector3(-4.69, 1.75, 3.9), 90.0, "Poster")
	put(g, "Card_Poster_B", Vector3(4.69, 1.8, -1.9), -90.0, "Poster")
	# БЫСТРЫЙ БОЙ: пульт лифта, ящики и бочка у ворот
	put(g, "ControlBox", Vector3(-1.98, 1.12, BACK))
	# (левая стена теперь с воротами в зал — ящики и бочка переехали к переднему левому углу)
	put(g, "Crate", Vector3(-4.1, 0, 3.55), 25.0, "CrateGate")
	put(g, "Crate_Small", Vector3(-4.05, 0.5, 3.5), 10.0, "CrateGate")
	put(g, "Jerrycan", Vector3(-3.4, 0, 3.85), -30.0)
	put(g, "Metal_Barrel", Vector3(-3.5, 0, 3.0), 0.0, "Barrel", Vector3.ZERO, "res://assets/models/scrap/props/Metal_Barrel.glb")
	# правый угол — стенд экранов с показателями бойца (06.10, scenes/menu/garage_stats_wall.gd): ферма поперёк угла лицом в комнату,
	# мониторы по RACK_SCREENS (у каждого meta panel — что показывает, model — размер экрана); стеллаж сдвинут к правой стене
	var rack := put(g, "ScreenRack", RACK_POS, RACK_YAW, "ScreenRack")
	if rack != null:
		for sc in RACK_SCREENS:
			var mon := put(rack, "Monitor_" + String(sc[0]), sc[1], 0.0, "Screen_" + String(sc[2]))
			if mon != null:
				mon.set_meta("panel", String(sc[2]))
				mon.set_meta("model", String(sc[0]))
	put(g, "Storage", Vector3(4.45, 0, 0.05), -90.0)
	put(g, "Case_Navy", Vector3(4.45, 0.14, 0.2), -80.0)
	put(g, "Crate_Small", Vector3(4.45, 0.64, -0.25), -95.0, "CrateShelf")
	put(g, "Books", Vector3(4.45, 1.14, 0.3), -70.0, "BooksShelf")
	put(g, "Case_Olive", Vector3(4.05, 0, -0.95), -60.0)
	put(g, "Tire", Vector3(3.7, 0, 0.95), 0.0)
	put(g, "Tire", Vector3(3.7, 0.18, 0.97), 25.0, "Tire2")
	put(g, "Cone", Vector3(3.3, 0, 1.5), 0.0)
	# НАСТРОЙКИ / ВЫХОД: тумба с радио, щиток с рубильником на правой стене
	put(g, "Cabinet", Vector3(4.42, 0, 1.25), -90.0)
	put(g, "Radio", Vector3(4.42, 0.88, 1.25), -90.0)
	put(g, "Breaker", Vector3(4.7, 1.2, 2.05), -90.0)
	# передний план слева (размыт в кадре): ящик
	put(g, "Crate", Vector3(-2.3, 0, 2.7), 18.0, "CrateFront")
	# N0 — помощник в гараже (06.10, scenes/menu/garage_n0.gd): парит у того, на что смотрит герой
	var n0 := Node3D.new()
	n0.name = "N0"
	n0.set_script(load("res://scenes/menu/garage_n0.gd"))
	n0.position = Vector3(1.15, 1.95, -1.1)
	g.add_child(n0)
	n0.owner = scene_root


# ---------------------------------------------------------------- свет (meta zone → garage_menu.gd)

func _light(g: Node3D, kind: String, name: String, zone: String, pos: Vector3, col: Color, energy: float, rng: float,
		target := Vector3.ZERO, angle := 45.0, shadow := false, vol := 1.0) -> Light3D:
	var l: Light3D
	if kind == "spot":
		var s := SpotLight3D.new()
		s.spot_range = rng
		s.spot_angle = angle
		s.spot_angle_attenuation = 0.9
		l = s
	else:
		var o := OmniLight3D.new()
		o.omni_range = rng
		l = o
	l.name = name
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.shadow_enabled = shadow
	l.light_volumetric_fog_energy = vol
	l.set_meta("zone", zone)
	g.add_child(l, true)
	l.owner = scene_root
	if kind == "spot":
		var up := Vector3.UP if absf((target - pos).normalized().y) < 0.95 else Vector3.FORWARD
		l.transform = Transform3D(Basis(), pos).looking_at(target, up)
	return l


func _lights(g: Node3D) -> void:
	var warm := Color(1.0, 0.7, 0.42)
	var tv := Color(0.55, 0.7, 1.0)
	var null_c := Color(0.62, 0.4, 1.0)
	# ТВ: заливка комнаты от экрана и луч в туман
	_light(g, "omni", "TvFill", "tv", Vector3(1.62, 1.15, -1.7), tv, 1.4, 5.5, Vector3.ZERO, 0, true, 1.0)
	_light(g, "spot", "TvBeam", "tv", Vector3(1.62, 1.15, -2.2), tv, 3.0, 7.0, Vector3(1.5, 0.6, 1.5), 48.0, true, 2.0)
	# верстак: лампа вниз и мягкий свет абажура на стену
	_light(g, "spot", "LampCone", "bench", Vector3(-0.55, 2.12, -2.05), warm, 9.0, 4.5, Vector3(-0.7, 0.0, -1.7), 58.0, true, 1.6)
	_light(g, "omni", "LampGlow", "bench", Vector3(-0.55, 2.2, -2.2), warm, 0.9, 2.4, Vector3.ZERO, 0, false, 0.4)
	_light(g, "spot", "BlueprintWash", "bench", Vector3(-0.9, 3.15, -2.15), Color(1.0, 0.74, 0.48), 3.0, 2.2, Vector3(-1.1, 2.35, -3.0), 42.0, false, 0.3)
	_light(g, "omni", "PegboardWarm", "bench", Vector3(-0.6, 1.25, -2.55), Color(1.0, 0.62, 0.35), 0.6, 1.8)
	# ворота: свет поля из-под шторы, иллюминатор, общая подсветка
	_light(g, "spot", "GateFloor", "gate", Vector3(-3.45, 0.08, -1.75), null_c, 5.0, 5.0, Vector3(-1.2, 0.0, 0.5), 70.0, false, 1.0)
	_light(g, "omni", "GateGlow", "gate", Vector3(-2.8, 0.25, -1.05), null_c, 0.8, 3.5, Vector3.ZERO, 0, false, 1.5)
	_light(g, "spot", "Porthole", "gate", Vector3(-3.8, 1.65, -2.05), Color(0.75, 0.6, 1.0), 2.5, 5.0, Vector3(-0.5, 1.1, 1.0), 16.0, false, 1.0)
	# полка трофеев
	for x in [1.1, 1.9, 2.75]:
		_light(g, "spot", "ShelfSpot", "shelf", Vector3(x, 3.0, -2.55), Color(1.0, 0.8, 0.55), 3.2, 2.4, Vector3(x, 2.32, -2.85), 36.0, true, 0.5)
	# радио и щиток
	_light(g, "omni", "RadioDial", "radio", Vector3(3.95, 1.05, 1.25), Color(1.0, 0.62, 0.28), 0.2, 1.1)
	_light(g, "spot", "BreakerSpot", "radio", Vector3(3.6, 3.0, 1.6), Color(1.0, 0.82, 0.62), 2.0, 3.5, Vector3(4.6, 1.2, 1.7), 40.0, true, 0.6)
	# прочее: красная лампа пульта, слабая холодная подсветка со стороны камеры
	_light(g, "omni", "ControlRed", "room", Vector3(-1.98, 1.6, -2.75), Color(1.0, 0.12, 0.06), 0.7, 1.3)
	_light(g, "omni", "Fill", "room", Vector3(0.8, 2.6, 2.6), Color(0.5, 0.55, 0.8), 0.35, 9.0, Vector3.ZERO, 0, false, 0.0)
	# стенд экранов: холодное свечение мониторов на пол и стены угла; консоль связи — голубое кольцо на верстаке
	_light(g, "omni", "RackGlow", "rack", Vector3(3.55, 1.6, -1.45), Color(0.45, 0.75, 1.0), 0.9, 3.4, Vector3.ZERO, 0, false, 0.6)
	_light(g, "spot", "RackTop", "rack", Vector3(3.3, 3.1, -1.1), Color(0.75, 0.85, 1.0), 1.6, 4.0, Vector3(3.95, 0.4, -1.87), 50.0, false, 0.4)
	_light(g, "omni", "LinkGlow", "bench", Vector3(0.3, 1.35, -2.2), Color(0.35, 0.85, 1.0), 0.35, 1.2, Vector3.ZERO, 0, false, 0.2)
	# тёплая подсветка ящиков и ковра спереди (в концепте они в тёплом свете, а не силуэтом против экрана)
	_light(g, "omni", "CrateWarm", "tv", Vector3(1.0, 1.3, 0.3), Color(1.0, 0.66, 0.4), 0.9, 3.6, Vector3.ZERO, 0, false, 0.2)


# ---------------------------------------------------------------- точки камеры (Marker3D, meta fov)

## Камера в pos смотрит так, чтобы subj оказался на доле frac ширины кадра 16:9 (меню справа → frac ≈ 0.33).
func _spot(g: Node3D, name: String, pos: Vector3, subj: Vector3, frac: float, fov: float) -> void:
	var xf := Transform3D(Basis(), pos).looking_at(subj, Vector3.UP)
	var tan_h := tan(deg_to_rad(fov * 0.5)) * 16.0 / 9.0
	var yaw := atan(-(frac - 0.5) * 2.0 * tan_h)
	xf.basis = Basis(Vector3.UP, -yaw) * xf.basis
	var m := Marker3D.new()
	m.name = name
	m.transform = xf
	m.set_meta("fov", fov)
	g.add_child(m)
	m.owner = scene_root


## Камера в pos с поворотом yaw (влево +) и наклоном pitch (вверх +), градусы.
func _spot_yp(g: Node3D, name: String, pos: Vector3, yaw: float, pitch: float, fov: float) -> void:
	var m := Marker3D.new()
	m.name = name
	m.position = pos
	m.rotation_degrees = Vector3(pitch, yaw, 0.0)
	m.set_meta("fov", fov)
	g.add_child(m)
	m.owner = scene_root


func _spots(g: Node3D) -> void:
	# 06.10: от первого лица — камера на высоте глаз героя (EYE); между пунктами он ходит по комнате у ковра (scenes/menu/garage_view.gd)
	_spot_yp(g, "Title", Vector3(2.75, EYE, 2.3), 18.0, -6.0, 55.0)
	_spot(g, "Story", Vector3(2.45, EYE - 0.04, 0.55), Vector3(1.7, 1.15, -2.6), 0.34, 48.0)
	_spot(g, "Quick", Vector3(-0.2, EYE, 0.9), Vector3(-3.45, 1.3, -1.75), 0.36, 52.0)
	_spot(g, "Workshop", Vector3(1.15, EYE, 0.75), Vector3(-0.6, 1.05, -1.75), 0.36, 52.0)
	_spot(g, "Fighter", Vector3(1.5, EYE, 0.62), RACK_POS + Vector3(0, 1.55, 0), 0.31, 55.0)
	_spot(g, "FighterClose", Vector3(2.55, EYE - 0.04, -0.62), RACK_POS + Vector3(0, 1.6, 0), 0.4, 58.0)
	_spot(g, "Trophies", Vector3(2.35, EYE, 0.6), Vector3(1.8, 2.45, -2.85), 0.33, 44.0)
	_spot(g, "Settings", Vector3(2.0, EYE, 1.0), Vector3(4.55, 1.2, 1.55), 0.36, 50.0)
	_spot(g, "SettingsClose", Vector3(3.0, EYE - 0.06, 2.3), Vector3(4.5, 1.3, 1.55), 0.34, 46.0)
	# у верстака: шлем на подставке консоли перед глазами, руки дотягиваются (scenes/menu/garage_headset.gd)
	var rest := CONSOLE_POS + Basis(Vector3.UP, deg_to_rad(CONSOLE_YAW)) * HEADSET_REST
	_spot(g, "Pilot", Vector3(0.38, EYE - 0.02, -1.62), rest + Vector3(0, -0.08, 0), 0.5, 62.0)
	# ныряние при входе: в экран телевизора, к иллюминатору ворот, к стенду
	_spot(g, "IntoTV", Vector3(1.62, 1.155, -1.66), Vector3(1.62, 1.155, -2.27), 0.5, 50.0)
	_spot(g, "IntoGate", Vector3(-2.75, 1.5, -1.0), Vector3(-3.84, 1.6, -2.1), 0.5, 50.0)
	_spot(g, "IntoStand", Vector3(-0.55, 1.4, -0.3), Vector3(-0.75, 1.0, -1.2), 0.5, 50.0)
