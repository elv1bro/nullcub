## Сборщик карты «Гонка: трасса» (docs/plan-demo/RACE_TRACK.md; автор 06.10: «в гонке мы можем сделать длинную сложную карту с разными
## сложностями на ней?» → «делаем»): собирает res://scenes/arena/race_track.tscn. Повторный запуск перезаписывает сцену — правки вносятся
## сюда. Запуск (сценой, а не -s: скрипты карты и деталей тянут автозагрузки):
##   godot --headless --path godot --import && godot --headless --path godot res://tools/build_race_track.tscn
##
## Как устроено. Трасса — разрез «внутри свалки»: коридоры (AIR — прямоугольники воздуха) вырезаны в сплошной массе мира WORLD. Твёрдое =
## WORLD минус AIR, нарезанное на прямоугольники (_decompose) по участкам; у каждого участка — одно тело StaticBody3D (коробки коллизии
## глубиной COLL_DEPTH) и один меш (коробки z Z_BACK…Z_FRONT, свой материал участка — участки различаются цветом). Над открытыми залами
## (SKY) масса невидима — там небо и параллакс Свалки, а сквозь потолок всё равно не пролететь (тонкая полоса-балка показывает край).
## Закрытые коридоры (флаг back) — с задней стенкой и светом; в трубах (флаг pipe) у каждой стенки — слой-мембрана (TrackMembrane).
## Куклы — в плоскости z = 0, x — вдоль трассы (старт x ≈ 0, финиш x = FINISH_X), y — вверх, пол старта y = 0.
##
## Участки (x):
##   1 РАЗГОН        −8…64    открытый зал 14 м, кольца TrackRing на линии (+Заряд)
##   2 ПРЕССЫ        64…136   развилка A: низом (трудный, короткий) — коридор 4.4 м под тремя прессами Свалки (в такт); верхом (лёгкий,
##                            длиннее: шахта вверх, верхний коридор 5 м, шахта вниз) с двумя магнитами на цепях (TrackMagnetPull тянет
##                            куклу к полюсу)
##   3 ТРУБЫ         136…206  развилка B: короткий путь — пара порталов (PortalPair, scripts/portal/, docs/plan-demo/PORTAL.md): щель A в
##                            правой стене зала (x 146, y 7, нормаль −X) → щель B в левой стене выхода (x 200, нормаль +X), всегда под током;
##                            сквозной щели больше нет (на её месте — карманы порталов); метки PortalSlotA / B — там же; лёгкий — змейка
##                            труб 3.4 м вниз-вверх (~91 м); стенки труб — мембраны
##   4 ГРАВИТАЦИЯ    206…288  зал со встречным полем вбок (TrackZone, TRACK_SIDE_G); развилка C: верхом короб 3.4 м с полем вверх и сеткой KO
##                            в потолке (трудный, 34 м), низом — тоннель через шахты (лёгкий, ~60 м)
##   5 ТЯЖЁЛАЯ ЗОНА  288…342  низкий вход 6.5 м → зона TRACK_HEAVY_G (x 298…318): стена x 306…310 до 7.5 м, подняться над ней — только с
##                            ускорением (Заряд); перед зоной — кольцо (+Заряд)
##   6 ЯМА           342…426  яма 46 м: шесть столбов, семь верёвочных мостов (TrackBridgeSlot — рвутся), бочки на столбах (TrackBarrelSlot —
##                            рвутся рядом), поле вниз TRACK_PIT_G, низкий потолок 6 м; дно — зона KO; финиш x = FINISH_X
## Контрольные точки (TrackCheckpoint) — в начале каждого участка; линия ботов (Route) — отрезки main0, A_easy / A_hard, main1, B_easy /
## B_hard, main2, C_easy / C_hard, main3 (TrackRoute).
##
## Дерево: Node3D "RaceTrack" (script scenes/arena/race_track.gd)
##   ├── WorldEnvironment "Environment", DirectionalLight3D "Sun" / "Fill" / "Rim", SpotLight3D "CameraKey" (едет за камерой), "Parallax"
##   ├── Node3D "Solid": StaticBody3D "Body_S<n>" (коробки) + MeshInstance3D "Mass_S<n>"; "Back" — задние стенки; "Beams" — края неба
##   ├── Node3D "Lights" (OmniLight3D в закрытых коридорах), "Decor" (кучи хлама за плоскостью)
##   ├── Node3D "Machines": Press1..3 (machine_press), Magnet1..2 (machine_magnet) + MagnetPull1..2 (TrackMagnetPull)
##   ├── Node3D "Hazards": TrackMembrane "Membranes", TrackZone (поля), TrackGrid (сетка KO, дно ямы), TrackBridgeSlot ×7, TrackBarrelSlot ×6
##   ├── Node3D "Rings" (TrackRing), "Checkpoints" (TrackCheckpoint CP0..CP5), TrackFinish "Finish", "Portal" (PortalSlotA / PortalSlotB)
##   ├── Node3D "Sections" (S1..S6: мета index, x0, x1), "Route" (отрезки линии ботов), "Spawns" (Spawn0..3 — старт)
extends Node

const OUT := "res://scenes/arena/race_track.tscn"
const SCRIPT := "res://scenes/arena/race_track.gd"
const PARALLAX := "res://scenes/arena/parallax_scrap_scatter.tscn"
const ENV_RES := "res://assets/environments/scrap_env.tres"
const KIT := "res://scenes/props/scrap/%s.tscn"
const PBR := "res://assets/textures/pbr/%s/%s.png"

const WORLD := Rect2(-16.0, -22.0, 446.0, 54.0)   # x −16…430, y −22…32
const Z_FRONT := 0.6
const Z_BACK := -2.2
const COLL_DEPTH := 2.4
const FINISH_X := 404.0
const GROUND_DEPTH := 12.0

## Участки: [номер, x0, x1 (границы для HUD), ключ материала]. Куски нарезки твёрдого — по CHUNKS (первый и последний — до края мира).
const SECTIONS := [
	[1, -8.0, 64.0, "sand"], [2, 64.0, 136.0, "iron"], [3, 136.0, 206.0, "pipe"],
	[4, 206.0, 288.0, "blue"], [5, 288.0, 342.0, "heavy"], [6, 342.0, 426.0, "stone"],
]
const CHUNKS := [-16.0, 64.0, 136.0, 206.0, 288.0, 342.0, 430.0]

## Воздух: [x0, x1, y0, y1, флаги] (back — закрытый коридор: задняя стенка и свет; wall — только задняя стенка (яма); pipe — стенки-
## мембраны). Открытые залы (без флагов) — с землёй за плоскостью боя (GROUND_DEPTH) и небом сзади.
const AIR := [
	# 1 разгон + вход в развилку A
	[-8.0, 74.0, 0.0, 14.0, ""],
	# 2 развилка A: низом под прессами / верхом с магнитами
	[74.0, 132.0, 0.0, 4.4, "back"],
	[74.0, 80.0, 8.4, 21.0, "back"], [74.0, 132.0, 16.0, 21.0, "back"], [126.0, 132.0, 8.4, 21.0, "back"],
	[132.0, 146.0, 0.0, 14.0, ""],
	# 3 развилка B: пара порталов (A — в правой стене зала, B — в левой стене выхода) / змейка труб
	[146.0, 147.6, 5.7, 8.3, "wall"], [198.4, 200.0, 5.7, 8.3, "wall"],   # карманы пары порталов (щель между ними закрыта)
	[146.0, 158.0, 0.0, 3.4, "back,pipe"], [154.6, 158.0, -6.0, 3.4, "back,pipe"], [154.6, 172.0, -6.0, -2.6, "back,pipe"],
	[168.6, 172.0, -6.0, 3.4, "back,pipe"], [168.6, 186.0, 0.0, 3.4, "back,pipe"], [182.6, 186.0, -6.0, 3.4, "back,pipe"],
	[182.6, 200.0, -6.0, -2.6, "back,pipe"], [196.6, 200.0, -6.0, 3.4, "back,pipe"], [196.6, 202.0, 0.0, 3.4, "back,pipe"],
	# 4 зал со встречным полем, развилка C: короб с полем вверх / тоннель низом
	[200.0, 236.0, 0.0, 14.0, ""],
	[236.0, 270.0, 9.0, 12.4, "back"],
	[236.0, 240.4, -8.0, 5.0, "back"], [236.0, 270.0, -8.0, -3.4, "back"], [265.6, 270.0, -8.0, 5.0, "back"],
	[270.0, 288.0, 0.0, 14.0, ""],
	# 5 тяжёлая зона: низкий вход, подъём, проход над стеной
	[288.0, 300.0, 0.0, 6.5, "back"], [300.0, 306.0, 0.0, 12.0, "back"], [306.0, 310.0, 7.5, 12.0, "back"], [310.0, 342.0, 0.0, 12.0, "back"],
	# 6 яма: подход, над мостами, просветы между столбами, дно; финиш
	[342.0, 346.0, 0.0, 12.0, ""],
	[346.0, 392.0, 0.0, 6.0, "wall"],
	[346.0, 350.0, -13.0, 0.0, "wall"], [353.0, 357.0, -13.0, 0.0, "wall"], [360.0, 364.0, -13.0, 0.0, "wall"], [367.0, 371.0, -13.0, 0.0, "wall"],
	[374.0, 378.0, -13.0, 0.0, "wall"], [381.0, 385.0, -13.0, 0.0, "wall"], [388.0, 392.0, -13.0, 0.0, "wall"],
	[346.0, 392.0, -18.0, -13.0, "wall"],
	[392.0, 426.0, 0.0, 12.0, ""],
]
## Небо: твёрдое здесь невидимо (коллизия остаётся).
const SKY := [
	Rect2(-16.0, 16.0, 90.0, 16.0),      # над залом разгона (потолок — плита 14…16)
	Rect2(200.0, 16.0, 88.0, 16.0),      # над участком 4
	Rect2(342.0, 14.0, 88.0, 18.0),      # над ямой и финишем
]
const MATS := {
	"sand": ["scrap_dirt", Color(1.0, 0.88, 0.72), 0.0],
	"iron": ["rust_metal", Color(0.72, 0.66, 0.62), 0.45],
	"pipe": ["iron", Color(0.62, 0.74, 0.78), 0.5],
	"blue": ["rust_metal", Color(0.56, 0.62, 0.82), 0.4],
	"heavy": ["rust_painted_red", Color(0.82, 0.5, 0.44), 0.35],
	"stone": ["stone", Color(0.86, 0.8, 0.74), 0.0],
}

const SUN_DIR := Vector3(-0.60, -0.45, 0.66)
const SUN_COLOR := Color(1.0, 0.72, 0.48)
const FILL_DIR := Vector3(0.45, -0.45, -0.77)
const RIM_DIR := Vector3(0.55, -0.25, 0.8)

## Прессы (x) и их сдвиг фазы (с); магниты: x подвеса, полюс на MAGNET_POLE_Y.
const PRESSES := [[88.0, 0.0], [102.0, 1.15], [116.0, 2.3]]
const MAGNETS := [[94.0, 0.0], [114.0, 2.0]]
const MAGNET_POLE_Y := 20.2
const MAGNET_CHAIN := 9.17                # от подвеса до полюса (machine_magnet.tscn: Head −8, Pole −1.17)
## Кольца: разгон и перед тяжёлой зоной.
const RINGS := [Vector2(16.0, 4.0), Vector2(25.0, 8.0), Vector2(34.0, 4.5), Vector2(43.0, 8.5), Vector2(52.0, 5.5), Vector2(60.0, 7.0),
	Vector2(293.0, 3.2)]
## Контрольные точки: [x, высота ворот]; первая — старт.
const CHECKPOINTS := [[4.0, 14.0], [66.0, 14.0], [138.0, 14.0], [208.0, 14.0], [290.0, 6.5], [345.0, 12.0]]
## Старт (корень куклы): по player_index.
const STARTS := [Vector2(0.0, 0.05), Vector2(2.5, 0.05), Vector2(5.0, 0.05), Vector2(7.5, 0.05)]
## Поля: [x0, x1, y0, y1, направление, ключ Tuning, где подпись силы (от центра зоны)].
const ZONES := [
	[214.0, 236.0, 0.0, 14.0, Vector2(-1.0, 0.0), "TRACK_SIDE_G", Vector2(0.0, 6.2)],
	[236.0, 270.0, 9.0, 12.4, Vector2(0.0, 1.0), "TRACK_UP_G", Vector2(-14.0, -1.1)],
	[298.0, 318.0, 0.0, 12.0, Vector2(0.0, -1.0), "TRACK_HEAVY_G", Vector2(-2.0, 5.2)],
	[346.0, 392.0, -18.0, 6.0, Vector2(0.0, -1.0), "TRACK_PIT_G", Vector2(-20.0, 11.2)],
]
## Пара порталов развилки B: середины щелей на поверхности стен (A — вход, нормаль −X; B — выход, нормаль +X), ширина щели, цвет
## (Tuning.PORTAL_COLOURS: 1 — бирюзовый).
const PORTAL_A := Vector3(146.0, 7.0, 0.0)
const PORTAL_B := Vector3(200.0, 7.0, 0.0)
const PORTAL_WIDTH := 2.6
const PORTAL_COLOUR := 1
const PORTAL_SCENE := "res://scenes/portal/portal_pair.tscn"
## Яма: мосты (x столба A, пол y 0), бочки (x на столбе).
const BRIDGES := [346.0, 353.0, 360.0, 367.0, 374.0, 381.0, 388.0]
const BARRELS := [351.5, 358.5, 365.5, 372.5, 379.5, 386.5]

## Линия ботов: [имя, kind, fork, next, точки [x, y, {мета}]].
const ROUTE := [
	["main0", "main", "", ["A_easy", "A_hard"], [
		[4.0, 1.2], [10.0, 2.5], [16.0, 4.0], [25.0, 8.0], [34.0, 4.5], [43.0, 8.5], [52.0, 5.5], [60.0, 7.0], [68.0, 6.5], [71.0, 6.5]]],
	["A_easy", "easy", "A", ["main1"], [
		[71.0, 6.5], [75.5, 11.0, {"v": 5.0}], [77.0, 17.5, {"v": 5.0}], [82.0, 18.2], [94.0, 18.2], [104.0, 18.2], [114.0, 18.2],
		[124.0, 18.2], [129.0, 17.5, {"v": 5.0}], [130.0, 11.0, {"v": 5.0}], [134.5, 8.0], [138.5, 6.5]]],
	["A_hard", "hard", "A", ["main1"], [
		[71.0, 6.5], [75.0, 1.9, {"v": 6.0}], [85.0, 1.7, {"press": "Machines/Press1"}], [91.5, 1.7],
		[99.0, 1.7, {"press": "Machines/Press2"}], [105.5, 1.7], [113.0, 1.7, {"press": "Machines/Press3"}], [119.5, 1.7], [130.0, 1.9],
		[134.0, 4.5], [138.5, 6.5]]],
	["main1", "main", "", ["B_easy", "B_hard"], [[138.5, 6.5], [142.0, 6.5], [144.0, 6.5]]],
	["B_easy", "easy", "B", ["main2"], [
		[144.0, 6.5], [145.0, 2.0, {"v": 4.0}], [148.0, 1.7, {"v": 4.0, "look": 2.0}], [156.3, 1.7, {"v": 2.5, "look": 1.6}],
		[156.3, -4.3, {"v": 2.5, "look": 1.6}], [170.3, -4.3, {"v": 2.5, "look": 1.6}], [170.3, 1.7, {"v": 2.5, "look": 1.6}],
		[184.3, 1.7, {"v": 2.5, "look": 1.6}], [184.3, -4.3, {"v": 2.5, "look": 1.6}], [198.3, -4.3, {"v": 2.5, "look": 1.6}],
		[198.3, 1.7, {"v": 2.5, "look": 1.6}], [201.0, 1.9, {"v": 4.0}], [207.0, 5.0]]],
	["B_hard", "hard", "B", ["main2"], [
		[144.0, 6.5], [145.0, 7.0, {"v": 5.0, "look": 2.5}], [146.7, 7.0, {"jump": true, "v": 5.0}], [201.2, 7.0, {"v": 5.0}],
		[203.0, 6.0], [207.0, 5.0]]],
	["main2", "main", "", ["C_easy", "C_hard"], [[207.0, 5.0], [214.0, 5.5], [226.0, 6.0], [233.0, 6.0]]],
	["C_easy", "easy", "C", ["main3"], [
		[233.0, 6.0], [238.2, 2.5, {"v": 4.0}], [238.2, -5.7, {"v": 3.0}], [267.8, -5.7, {"v": 3.0}], [267.8, 2.5, {"v": 3.0}],
		[272.5, 4.5], [276.0, 6.5]]],
	["C_hard", "hard", "C", ["main3"], [
		[233.0, 6.0], [236.5, 10.3, {"v": 4.0, "look": 2.5}], [269.0, 10.3, {"v": 5.0, "look": 2.5}], [272.5, 8.0], [276.0, 6.5]]],
	["main3", "main", "", [], [
		[276.0, 6.5], [285.0, 4.0], [293.0, 3.2], [298.5, 3.4, {"charge": 90.0, "v": 3.0}], [301.5, 7.8, {"dash": true, "v": 4.0}],
		[304.0, 9.6, {"dash": true}], [311.0, 9.6, {"dash": true}], [313.5, 8.4], [318.0, 6.5], [326.0, 5.0], [334.0, 4.5], [340.0, 4.0],
		[344.0, 2.8], [348.0, 2.9],
		[370.0, 2.9], [390.0, 2.9], [395.0, 2.6], [404.0, 2.4], [414.0, 2.4]]],
]

var root: Node3D
var _names := {}
var _scenes := {}
var _mats := {}
var _solids_all: Array = []   # [Rect2]


func _ready() -> void:
	if not _build():
		get_tree().quit(1)
		return
	get_tree().quit(0)


func _build() -> bool:
	root = Node3D.new()
	root.name = "RaceTrack"
	var scr := load(SCRIPT) as Script
	if scr == null:
		push_error("no script " + SCRIPT)
		return false
	root.set_script(scr)
	_environment()
	_parallax()
	_solid()
	_lights()
	_machines()
	_hazards()
	_rings()
	_checkpoints()
	_portal_slots()
	_sections()
	_route()
	_spawns()
	_decor()
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
	print("saved ", OUT, ": nodes=", _count(root), " solids=", _solids_all.size())
	root.free()
	return true


# ---------------------------------------------------------------- помощники

func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


func _set_owner(n: Node) -> void:
	for c in n.get_children():
		if c.owner == null:
			c.owner = root
		_set_owner(c)


func _uniq(base: String) -> String:
	var k := int(_names.get(base, 0))
	_names[base] = k + 1
	return base if k == 0 else "%s%d" % [base, k + 1]


func _group(name_: String, parent: Node = null) -> Node3D:
	var n := Node3D.new()
	n.name = name_
	(parent if parent != null else root).add_child(n)
	return n


func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


func _inst(parent: Node, path: String, name_: String, pos: Vector3) -> Node3D:
	var ps := _scene(path)
	if ps == null:
		push_error("missing " + path)
		return null
	var n := ps.instantiate() as Node3D
	n.name = name_
	n.position = pos
	parent.add_child(n)
	return n


func _air_rects() -> Array:
	var out: Array = []
	for a in AIR:
		out.append(Rect2(float(a[0]), float(a[2]), float(a[1]) - float(a[0]), float(a[3]) - float(a[2])))
	return out


func _has_flag(a: Array, f: String) -> bool:
	return f in String(a[4]).split(",")


# ---------------------------------------------------------------- твёрдое

## Нарезка: кусок [x0, x1] мира без воздуха → прямоугольники твёрдого. Сетка по всем краям воздуха и неба внутри куска; клетка твёрдая,
## если её центр не в воздухе; «небо» — если центр в SKY. Слияние: подряд идущие клетки строки одного вида → полоса; одинаковые
## полосы соседних строк → один прямоугольник. → {solid: [Rect2], sky: [Rect2]}.
func _decompose(x0: float, x1: float, airs: Array) -> Dictionary:
	var xs := {x0: true, x1: true}
	var ys := {WORLD.position.y: true, WORLD.end.y: true}
	for r in airs + SKY:
		var rr := r as Rect2
		for x in [rr.position.x, rr.end.x]:
			if x > x0 and x < x1:
				xs[snappedf(x, 0.001)] = true
		for y in [rr.position.y, rr.end.y]:
			if y > WORLD.position.y and y < WORLD.end.y:
				ys[snappedf(y, 0.001)] = true
	var xl: Array = xs.keys()
	xl.sort()
	var yl: Array = ys.keys()
	yl.sort()
	# вид клетки: 0 — воздух, 1 — твёрдое, 2 — твёрдое под небом
	var kinds: Array = []
	for j in yl.size() - 1:
		var row: Array = []
		var cy := (float(yl[j]) + float(yl[j + 1])) * 0.5
		for i in xl.size() - 1:
			var cx := (float(xl[i]) + float(xl[i + 1])) * 0.5
			var p := Vector2(cx, cy)
			var k := 1
			for r in airs:
				if (r as Rect2).has_point(p):
					k = 0
					break
			if k == 1:
				for s in SKY:
					if (s as Rect2).has_point(p):
						k = 2
						break
			row.append(k)
		kinds.append(row)
	var out := {"solid": [], "sky": []}
	var open := {}   # "i0:i1:k" → [j0, j1]
	for j in yl.size() - 1:
		var runs := {}
		var row: Array = kinds[j]
		var i := 0
		while i < row.size():
			var k := int(row[i])
			if k == 0:
				i += 1
				continue
			var i0 := i
			while i < row.size() and int(row[i]) == k:
				i += 1
			runs["%d:%d:%d" % [i0, i, k]] = true
		for key in open.keys():
			if not runs.has(key):
				_emit(out, key, open[key], xl, yl)
				open.erase(key)
		for key in runs.keys():
			if open.has(key):
				open[key][1] = j + 1
			else:
				open[key] = [j, j + 1]
	for key in open.keys():
		_emit(out, key, open[key], xl, yl)
	return out


func _emit(out: Dictionary, key: String, js: Array, xl: Array, yl: Array) -> void:
	var p := key.split(":")
	var r := Rect2(float(xl[int(p[0])]), float(yl[int(js[0])]), float(xl[int(p[1])]) - float(xl[int(p[0])]),
		float(yl[int(js[1])]) - float(yl[int(js[0])]))
	(out["sky" if p[2] == "2" else "solid"] as Array).append(r)


func _material(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var spec: Array = MATS[key]
	var m := StandardMaterial3D.new()
	m.resource_name = "Track_" + key
	var tex := String(spec[0])
	m.albedo_texture = load(PBR % [tex, "albedo"])
	m.albedo_color = spec[1]
	if ResourceLoader.exists(PBR % [tex, "normal"]):
		m.normal_enabled = true
		m.normal_texture = load(PBR % [tex, "normal"])
	if ResourceLoader.exists(PBR % [tex, "roughness"]):
		m.roughness_texture = load(PBR % [tex, "roughness"])
	m.metallic = float(spec[2])
	if ResourceLoader.exists(PBR % [tex, "metallic"]) and float(spec[2]) > 0.0:
		m.metallic_texture = load(PBR % [tex, "metallic"])
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.28, 0.28, 0.28)
	m.uv1_triplanar_sharpness = 4.0
	_mats[key] = m
	return m


func _back_material() -> StandardMaterial3D:
	if _mats.has("_back"):
		return _mats["_back"]
	var m := (_material("iron").duplicate() as StandardMaterial3D)
	m.resource_name = "Track_back"
	m.albedo_color = Color(0.36, 0.34, 0.36)
	m.metallic = 0.2
	_mats["_back"] = m
	return m


## Коробка в меш: передняя грань (+z), верх, низ, бока; задняя не нужна (её не видно).
static func _box_faces(st: SurfaceTool, r: Rect2, z0: float, z1: float) -> void:
	var x0 := r.position.x
	var x1 := r.end.x
	var y0 := r.position.y
	var y1 := r.end.y
	_quad(st, Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3(0, 0, 1))
	_quad(st, Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3(0, 1, 0))
	_quad(st, Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3(0, -1, 0))
	_quad(st, Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3(-1, 0, 0))
	_quad(st, Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(1, 0, 0))


## Четырёхугольник a b c d (против часовой при взгляде по −n) — два треугольника (Godot: по часовой — лицевая).
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	for v in [a, c, b, a, d, c]:
		st.set_normal(n)
		st.set_uv(Vector2((v as Vector3).x, (v as Vector3).y) * 0.25)
		st.add_vertex(v)


func _solid() -> void:
	var g := _group("Solid")
	var back := _group("Back")
	var beams := _group("Beams")
	var airs := _air_rects()
	for c in CHUNKS.size() - 1:
		var x0 := float(CHUNKS[c])
		var x1 := float(CHUNKS[c + 1])
		var mat_key: String = SECTIONS[c][3]
		var dec := _decompose(x0, x1, airs)
		var body := StaticBody3D.new()
		body.name = "Body_S%d" % (c + 1)
		g.add_child(body)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var k := 0
		for r in dec["solid"] + dec["sky"]:
			var rr := r as Rect2
			var cs := CollisionShape3D.new()
			cs.name = "B%d" % k
			k += 1
			var bs := BoxShape3D.new()
			bs.size = Vector3(rr.size.x, rr.size.y, COLL_DEPTH)
			cs.shape = bs
			cs.position = Vector3(rr.get_center().x, rr.get_center().y, 0.0)
			body.add_child(cs)
			_solids_all.append(rr)
		for r in dec["solid"]:
			_box_faces(st, r, Z_BACK, Z_FRONT)
		st.generate_tangents()
		var mesh := st.commit()
		mesh.surface_set_material(0, _material(mat_key))
		var mi := MeshInstance3D.new()
		mi.name = "Mass_S%d" % (c + 1)
		mi.mesh = mesh
		g.add_child(mi)
		# край неба: балка по низу невидимой массы, где под ней воздух
		for r in dec["sky"]:
			var rr2 := r as Rect2
			for a in airs:
				var ar := a as Rect2
				if not is_equal_approx(ar.end.y, rr2.position.y):
					continue
				var ox0 := maxf(ar.position.x, rr2.position.x)
				var ox1 := minf(ar.end.x, rr2.end.x)
				if ox1 - ox0 > 0.1:
					_beam(beams, Rect2(ox0, rr2.position.y, ox1 - ox0, 0.35))
	# задние стенки закрытых коридоров и ямы; у открытых залов — земля за плоскостью боя (иначе пол — тонкий уступ над пустотой)
	var bst := SurfaceTool.new()
	bst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for a in AIR:
		var r := Rect2(float(a[0]), float(a[2]), float(a[1]) - float(a[0]), float(a[3]) - float(a[2]))
		if _has_flag(a, "back") or _has_flag(a, "wall"):
			_box_faces(bst, r, Z_BACK - 0.4, Z_BACK)
		elif String(a[4]) == "" and is_zero_approx(r.position.y):
			_box_faces(bst, Rect2(r.position.x, -6.0, r.size.x, 6.0), Z_BACK - GROUND_DEPTH, Z_BACK)
	bst.generate_tangents()
	var bm := bst.commit()
	bm.surface_set_material(0, _back_material())
	var bmi := MeshInstance3D.new()
	bmi.name = "BackWalls"
	bmi.mesh = bm
	back.add_child(bmi)


var _beam_mesh: BoxMesh
var _beam_mat: StandardMaterial3D

## Балка края неба (видна снизу: «потолок здесь»).
func _beam(parent: Node, r: Rect2) -> void:
	if _beam_mesh == null:
		_beam_mesh = BoxMesh.new()
		_beam_mesh.size = Vector3(1.0, 1.0, 1.0)
		_beam_mat = _material("iron").duplicate() as StandardMaterial3D
		_beam_mat.albedo_color = Color(0.45, 0.4, 0.38)
	var mi := MeshInstance3D.new()
	mi.name = _uniq("Beam")
	mi.mesh = _beam_mesh
	mi.material_override = _beam_mat
	mi.transform = Transform3D(Basis.IDENTITY.scaled(Vector3(r.size.x, r.size.y, Z_FRONT - Z_BACK)),
		Vector3(r.get_center().x, r.get_center().y, (Z_FRONT + Z_BACK) * 0.5))
	parent.add_child(mi)


# ---------------------------------------------------------------- свет и окружение

func _environment() -> void:
	var env := WorldEnvironment.new()
	env.name = "Environment"
	var e := (load(ENV_RES) as Environment).duplicate() as Environment
	env.environment = e
	var ca := CameraAttributesPractical.new()
	ca.dof_blur_far_enabled = true
	ca.dof_blur_far_distance = 45.0
	ca.dof_blur_far_transition = 70.0
	ca.dof_blur_amount = 0.03
	env.camera_attributes = ca
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.basis = Basis.looking_at(SUN_DIR.normalized(), Vector3.UP)
	sun.position = Vector3(0, 10, 0)
	sun.light_color = SUN_COLOR
	sun.light_energy = 2.0
	sun.light_indirect_energy = 1.0
	sun.light_angular_distance = 0.8
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.5
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.3
	sun.directional_shadow_max_distance = 50.0
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.basis = Basis.looking_at(FILL_DIR.normalized(), Vector3.UP)
	fill.light_color = Color(0.62, 0.64, 1.0)
	fill.light_energy = 0.9
	fill.light_indirect_energy = 0.0
	fill.light_specular = 0.4
	fill.shadow_enabled = false
	root.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.name = "Rim"
	rim.basis = Basis.looking_at(RIM_DIR.normalized(), Vector3.UP)
	rim.light_color = Color(0.72, 0.76, 1.0)
	rim.light_energy = 0.6
	rim.light_indirect_energy = 0.0
	rim.light_specular = 0.6
	rim.shadow_enabled = false
	root.add_child(rim)
	var key := SpotLight3D.new()
	key.name = "CameraKey"
	key.position = Vector3(0, 6, 14)
	key.light_color = Color(1.0, 0.93, 0.86)
	key.light_energy = 14.0
	key.light_indirect_energy = 0.0
	key.light_specular = 0.25
	key.spot_range = 45.0
	key.spot_attenuation = 1.6
	key.spot_angle = 42.0
	key.spot_angle_attenuation = 0.6
	key.shadow_enabled = false
	root.add_child(key)


## Фон Свалки (небо, дальний план, силуэты-разброс): слои стоят посреди трассы и едут за камерой на половину (иначе на 420 м края
## квадов уходили бы в кадр); разброс силуэтов рассчитан на весь диапазон камеры вдоль трассы.
func _parallax() -> void:
	var ps := load(PARALLAX) as PackedScene
	if ps == null:
		push_error("нет " + PARALLAX)
		return
	var n: Node3D = ps.instantiate()
	n.name = "Parallax"
	n.position = Vector3(205.0, 0.0, 0.0)
	n.set("layer4_scroll", 0.0)
	n.set("layer3_scroll", 0.45)
	n.set("layer2_scroll", 0.45)
	n.set("layer1_scroll", 0.45)
	n.set("scroll_vertical", false)
	n.set("camera_origin", Vector3(205.0, 6.0, 18.0))
	var sc := n.get_node_or_null("Scatter")
	if sc != null:
		var pts := PackedVector3Array()
		for x in [-215.0, 215.0]:
			for z in [10.0, 24.0]:
				pts.append(Vector3(x, 2.5, z))
				pts.append(Vector3(x, 12.0, z))
		sc.set("cam_points", pts)
	var fog := n.get_node_or_null("Layer2Fog") as Node3D
	if fog != null:
		fog.visible = false
	root.add_child(n)


## Свет закрытых коридоров: тёплые лампы без теней по длинной оси через LIGHT_STEP_M.
const LIGHT_STEP_M := 12.0

func _lights() -> void:
	var g := _group("Lights")
	for a in AIR:
		if not _has_flag(a, "back"):
			continue
		var r := Rect2(float(a[0]), float(a[2]), float(a[1]) - float(a[0]), float(a[3]) - float(a[2]))
		var horiz := r.size.x >= r.size.y
		var l := r.size.x if horiz else r.size.y
		var n := maxi(1, int(round(l / LIGHT_STEP_M)))
		var pipe := _has_flag(a, "pipe")
		for i in n:
			var f := (float(i) + 0.5) / float(n)
			var p := Vector2(r.position.x + r.size.x * f, r.get_center().y) if horiz else Vector2(r.get_center().x, r.position.y + r.size.y * f)
			var o := OmniLight3D.new()
			o.name = _uniq("Lamp")
			o.position = Vector3(p.x, p.y, -1.2)
			o.light_color = Color(0.55, 0.8, 1.0) if pipe else Color(1.0, 0.72, 0.45)
			o.light_energy = 1.4
			o.omni_range = 8.0
			o.omni_attenuation = 1.2
			o.shadow_enabled = false
			g.add_child(o)


# ---------------------------------------------------------------- механизмы и препятствия

func _machines() -> void:
	var g := _group("Machines")
	for i in PRESSES.size():
		var p := _inst(g, KIT % "machine_press", "Press%d" % (i + 1), Vector3(float(PRESSES[i][0]), 0.0, 0.0))
		if p != null:
			p.set("phase_offset_s", float(PRESSES[i][1]))
	for i in MAGNETS.size():
		var m := _inst(g, KIT % "machine_magnet", "Magnet%d" % (i + 1), Vector3(float(MAGNETS[i][0]), MAGNET_POLE_Y + MAGNET_CHAIN, 0.0))
		if m != null:
			m.set("phase_offset_s", float(MAGNETS[i][1]))
			m.set("swing_deg", 12.0)
			m.set("swing_period_s", 6.0)
		var pull := TrackMagnetPull.new()
		pull.name = "MagnetPull%d" % (i + 1)
		pull.machine_path = NodePath("../Magnet%d" % (i + 1))
		g.add_child(pull)


func _hazards() -> void:
	var g := _group("Hazards")
	# мембраны: слои у стенок труб и щели — где воздух с флагом pipe граничит с твёрдым
	var mem := TrackMembrane.new()
	mem.name = "Membranes"
	var bands: Array[Rect2] = []
	var normals := PackedVector2Array()
	var skin := Tuning.TRACK_MEMBRANE_SKIN
	for a in AIR:
		if not _has_flag(a, "pipe"):
			continue
		var ar := Rect2(float(a[0]), float(a[2]), float(a[1]) - float(a[0]), float(a[3]) - float(a[2]))
		for s in _solids_all:
			var sr := s as Rect2
			var ox0 := maxf(ar.position.x, sr.position.x)
			var ox1 := minf(ar.end.x, sr.end.x)
			var oy0 := maxf(ar.position.y, sr.position.y)
			var oy1 := minf(ar.end.y, sr.end.y)
			if ox1 - ox0 > 0.05 and is_equal_approx(sr.end.y, ar.position.y):
				bands.append(Rect2(ox0, ar.position.y, ox1 - ox0, skin))
				normals.append(Vector2(0.0, 1.0))
			if ox1 - ox0 > 0.05 and is_equal_approx(sr.position.y, ar.end.y):
				bands.append(Rect2(ox0, ar.end.y - skin, ox1 - ox0, skin))
				normals.append(Vector2(0.0, -1.0))
			if oy1 - oy0 > 0.05 and is_equal_approx(sr.end.x, ar.position.x):
				bands.append(Rect2(ar.position.x, oy0, skin, oy1 - oy0))
				normals.append(Vector2(1.0, 0.0))
			if oy1 - oy0 > 0.05 and is_equal_approx(sr.position.x, ar.end.x):
				bands.append(Rect2(ar.end.x - skin, oy0, skin, oy1 - oy0))
				normals.append(Vector2(-1.0, 0.0))
	mem.bands = bands
	mem.normals = normals
	g.add_child(mem)
	print("membrane bands: ", bands.size())
	for z in ZONES:
		var tz := TrackZone.new()
		tz.name = _uniq("Zone")
		var r := Rect2(float(z[0]), float(z[2]), float(z[1]) - float(z[0]), float(z[3]) - float(z[2]))
		tz.size = r.size
		tz.dir = z[4]
		tz.g_key = String(z[5])
		tz.label_offset = z[6]
		tz.position = Vector3(r.get_center().x, r.get_center().y, 0.0)
		g.add_child(tz)
	var grid := TrackGrid.new()
	grid.name = "ShockGrid"
	grid.size = Vector2(33.0, 0.4)
	grid.kind = "grid"
	grid.position = Vector3(253.0, 12.2, 0.0)
	g.add_child(grid)
	var pit := TrackGrid.new()
	pit.name = "PitFloor"
	pit.size = Vector2(46.0, 5.0)
	pit.kind = "pit"
	pit.position = Vector3(369.0, -15.5, 0.0)
	g.add_child(pit)
	var glow := OmniLight3D.new()
	glow.name = "PitGlow"
	glow.position = Vector3(369.0, -10.0, 1.0)
	glow.light_color = Color(1.0, 0.46, 0.16)
	glow.light_energy = 3.0
	glow.omni_range = 26.0
	glow.shadow_enabled = false
	g.add_child(glow)
	for i in BRIDGES.size():
		var b := TrackBridgeSlot.new()
		b.name = "Bridge%d" % (i + 1)
		b.position = Vector3(float(BRIDGES[i]), 0.0, 0.0)
		g.add_child(b)
	for i in BARRELS.size():
		var br := TrackBarrelSlot.new()
		br.name = "Barrel%d" % (i + 1)
		br.position = Vector3(float(BARRELS[i]), 0.0, 0.0)
		g.add_child(br)


func _rings() -> void:
	var g := _group("Rings")
	for i in RINGS.size():
		var r := TrackRing.new()
		r.name = "Ring%d" % (i + 1)
		r.position = Vector3(RINGS[i].x, RINGS[i].y, 0.0)
		g.add_child(r)


func _checkpoints() -> void:
	var g := _group("Checkpoints")
	for i in CHECKPOINTS.size():
		var c := TrackCheckpoint.new()
		c.name = "CP%d" % i
		c.index = i
		c.gate_h = float(CHECKPOINTS[i][1])
		c.position = Vector3(float(CHECKPOINTS[i][0]), 0.0, 0.0)
		g.add_child(c)
	var f := TrackFinish.new()
	f.name = "Finish"
	f.gate_h = 12.0
	f.position = Vector3(FINISH_X, 0.0, 0.0)
	f.set_meta("x", FINISH_X)
	root.add_child(f)


## Пара порталов развилки B (PortalPair, docs/plan-demo/PORTAL.md): A — в правой стене зала перед трубами (нормаль −X, смотрит на
## подлетающих), B — в левой стене зала выхода (нормаль +X, куда вылетают); всегда под током (input пуст). Карманы за щелями — воздух
## AIR (глубина PORTAL_DEPTH + 0.2), дно и щёки кармана пара ставит сама. Метки PortalSlotA / B — середины щелей (нормаль — локальная +X
## метки и мета normal; мета opening — толщина щели и её ширина вдоль стены, м). Бот входит в A по линии B_hard (точка с метой jump).
func _portal_slots() -> void:
	var g := _group("Portal")
	var ps := load(PORTAL_SCENE) as PackedScene
	if ps != null:
		var pair := ps.instantiate()
		pair.name = "PortalPairB"
		pair.set("a_position", PORTAL_A)
		pair.set("a_angle_deg", 90.0)
		pair.set("b_position", PORTAL_B)
		pair.set("b_angle_deg", -90.0)
		pair.set("width", PORTAL_WIDTH)
		pair.set("colour_index", PORTAL_COLOUR)
		g.add_child(pair)
	else:
		push_error("нет " + PORTAL_SCENE)
	for s in [["PortalSlotA", PORTAL_A, Vector3(-1.0, 0.0, 0.0)], ["PortalSlotB", PORTAL_B, Vector3(1.0, 0.0, 0.0)]]:
		var m := Marker3D.new()
		m.name = String(s[0])
		var n: Vector3 = s[2]
		m.transform = Transform3D(Basis(n, Vector3.UP, n.cross(Vector3.UP)), s[1])
		m.set_meta("normal", n)
		m.set_meta("opening", Vector2(0.6, PORTAL_WIDTH))
		m.set_meta("fork", "B")
		g.add_child(m)


func _sections() -> void:
	var g := _group("Sections")
	for s in SECTIONS:
		var m := Marker3D.new()
		m.name = "S%d" % int(s[0])
		m.position = Vector3(float(s[1]), 0.0, 0.0)
		m.set_meta("index", int(s[0]))
		m.set_meta("x0", float(s[1]))
		m.set_meta("x1", float(s[2]))
		g.add_child(m)


func _route() -> void:
	var g := _group("Route")
	for seg in ROUTE:
		var s := Node3D.new()
		s.name = String(seg[0])
		s.set_meta("kind", String(seg[1]))
		s.set_meta("fork", String(seg[2]))
		s.set_meta("next", PackedStringArray(seg[3]))
		g.add_child(s)
		var pts: Array = seg[4]
		for i in pts.size():
			var p: Array = pts[i]
			var w := Marker3D.new()
			w.name = "W%02d" % i
			w.position = Vector3(float(p[0]), float(p[1]), 0.0)
			if p.size() > 2:
				for k in (p[2] as Dictionary).keys():
					w.set_meta(String(k), p[2][k])
			s.add_child(w)


func _spawns() -> void:
	var g := _group("Spawns")
	for i in STARTS.size():
		var m := Marker3D.new()
		m.name = "Spawn%d" % i
		m.position = Vector3(STARTS[i].x, STARTS[i].y, 0.0)
		g.add_child(m)


## Декор за плоскостью боя в открытых залах: кучи хлама и пропсы (без коллизий для кукол — далеко за плоскостью).
const DECOR := [
	["bodies_scrap_heap_medium", Vector3(-4.0, -0.3, -4.5)], ["bodies_scrap_heap_small", Vector3(20.0, -0.2, -4.0)],
	["bodies_gear_heap", Vector3(38.0, -0.2, -4.2)], ["bodies_scrap_heap_massive", Vector3(56.0, -0.6, -6.0)],
	["bodies_broken_puppet", Vector3(12.0, 0.0, -3.2)], ["prop_rail_scrap_wagon", Vector3(29.0, 0.0, -3.4)],
	["bodies_scrap_heap_medium", Vector3(212.0, -0.3, -4.5)], ["bodies_chain_heap", Vector3(226.0, -0.2, -3.8)],
	["bodies_scrap_heap_small", Vector3(280.0, -0.2, -4.0)], ["bodies_metal_parts_heap", Vector3(398.0, -0.2, -4.0)],
	["bodies_scrap_heap_massive", Vector3(418.0, -0.6, -6.0)], ["prop_junk_cart_loaded", Vector3(410.0, 0.0, -3.4)],
]

func _decor() -> void:
	var g := _group("Decor")
	for d in DECOR:
		var path := KIT % String(d[0])
		if not ResourceLoader.exists(path):
			continue
		var n := _inst(g, path, _uniq(String(d[0]).capitalize().replace(" ", "")), d[1])
		if n is RigidBody3D:
			(n as RigidBody3D).freeze = true
