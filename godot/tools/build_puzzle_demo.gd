## Сборщик демо «Головоломки вдвоём» (docs/plan-demo/PUZZLE.md, MODES_PACK.md §6): пишет res://scenes/playground_puzzle.tscn — шесть
## закрытых комнат 16 × 9 м в ряд по x (центры через Tuning.PUZZLE_ROOM_PITCH), механизмы из scenes/puzzle/*.tscn, связи NodePath,
## кабели по задней стене, ящики и бочки, свет; плюс игровое: камера (DynamicCamera), PuzzleMatch, PuzzleHud, узел кукол.
## Повторный запуск перезаписывает сцену.
## Запуск: godot --headless --path godot --import && godot --headless --path godot res://tools/build_puzzle_demo.tscn
## (сценой, а не -s: скрипты механизмов тянут автозагрузку Tuning — в -s её нет).
##
## Координаты комнаты (локально, origin — середина пола): внутренность x −8…8, y 0…9, пол — y −1…0, стены x ±(8…9), потолок y 9…10.
## Твёрдое — в плоскости кукол (z = 0, глубина коллизий 4 м); задняя стена — только вид (z ≈ −1.4), на ней кабели и коробки логики.
## Выходная дверь — в правой стене на высоте door_y, за ней тамбур 2.4 м (exit_rect комнаты): ЦМ игрока в тамбуре — комната пройдена.
## Дерево:
##   PlaygroundPuzzle (playground_puzzle.gd)
##   ├── Environment, Sun
##   ├── Rooms/Room1..Room6 (PuzzleRoom): Static (StaticBody3D: формы), Visual (меши), Mech (механизмы, кабели), Props (ящики, бочки,
##   │     стена с трещиной), Spawns (Spawn0, Spawn1), Lamp (OmniLight3D)
##   ├── Dolls, Camera (DynamicCamera), Match (PuzzleMatch), HUD (PuzzleHud)
extends Node

const OUT := "res://scenes/playground_puzzle.tscn"
const PLAYGROUND := "res://scenes/puzzle/playground_puzzle.gd"
const ROOM := "res://scripts/puzzle/puzzle_room.gd"
const MATCH := "res://scripts/puzzle/puzzle_match.gd"
const HUD := "res://scenes/puzzle/puzzle_hud.gd"
const CAMERA := "res://scenes/camera/dynamic_camera.gd"
const PZ := "res://scenes/puzzle/%s.tscn"
const BARREL := "res://scenes/props/scrap/prop_metal_barrel.tscn"
const TEX := {
	"wall": "res://assets/textures/garage/paint_metal/",
	"floor": "res://assets/textures/garage/floor/",
	"back": "res://assets/textures/pbr/rust_metal/",
	"iron": "res://assets/textures/pbr/iron/",
	"hazard": "res://assets/textures/garage/hazard/",
}
const BACK_Z := -1.4
const CABLE_Z := -1.15

var root: Node3D
var mats := {}
var _scenes := {}

var W := 16.0
var H := 9.0
var PITCH := 26.0
var DOOR_H := 2.8


func _ready() -> void:
	W = Tuning.PUZZLE_ROOM_W
	H = Tuning.PUZZLE_ROOM_H
	PITCH = Tuning.PUZZLE_ROOM_PITCH
	DOOR_H = Tuning.PUZZLE_DOOR_H
	if not _build():
		get_tree().quit(1)
		return
	get_tree().quit(0)


func _build() -> bool:
	root = Node3D.new()
	root.name = "PlaygroundPuzzle"
	root.set_script(load(PLAYGROUND))
	_materials()
	_environment()
	var rooms := Node3D.new()
	rooms.name = "Rooms"
	root.add_child(rooms)
	_room1(_room(rooms, 0, 0.0))
	_room2(_room(rooms, 1, 0.0))
	_room3(_room(rooms, 2, 3.0))
	_room4(_room(rooms, 3, 0.0))
	_room5(_room(rooms, 4, 5.0))
	_room6(_room(rooms, 5, 5.6))
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
	print("saved ", OUT, ": nodes=", _count(root))
	root.free()
	return true


# ---------------------------------------------------------------- helpers

func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


## Владелец — корень (кроме внутренностей инстансов сцен: их сохраняет сама сцена).
func _own(n: Node) -> void:
	for c in n.get_children():
		if c.owner == null:
			c.owner = root
		if c.scene_file_path == "":
			_own(c)


func _scene(kind: String) -> PackedScene:
	var path := PZ % kind if not kind.begins_with("res://") else kind
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


func _inst(parent: Node, kind: String, n: String, pos: Vector3, set_props := {}) -> Node3D:
	var node := _scene(kind).instantiate() as Node3D
	node.name = n
	node.position = pos
	for k in set_props:
		node.set(k, set_props[k])
	parent.add_child(node)
	return node


func _mat(kind: String, tint: Color, scale: float = 0.35, metal: float = 0.4) -> StandardMaterial3D:
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
		if ResourceLoader.exists(dir + "metallic.png"):
			m.metallic_texture = load(dir + "metallic.png")
	m.metallic = metal
	m.roughness = 0.8
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	return m


func _materials() -> void:
	mats["wall"] = _mat("wall", Color(0.62, 0.66, 0.7), 0.3, 0.5)
	mats["floor"] = _mat("floor", Color(0.75, 0.74, 0.72), 0.3, 0.2)
	mats["back"] = _mat("back", Color(0.42, 0.44, 0.48), 0.22, 0.4)
	mats["iron"] = _mat("iron", Color(0.7, 0.72, 0.75), 0.4, 0.6)
	mats["hazard"] = _mat("hazard", Color(1, 1, 1), 0.5, 0.2)
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.1, 0.11, 0.13)
	trim.metallic = 0.6
	trim.roughness = 0.5
	mats["trim"] = trim


## Твёрдый блок комнаты: форма (глубина 4 м) в Static и меш (глубина 2.4 м) в Visual. x0..x1, y0..y1 — локально.
func _solid(r: Node3D, n: String, x0: float, x1: float, y0: float, y1: float, mat := "wall") -> void:
	var st := r.get_node("Static") as StaticBody3D
	PuzzlePart.box_shape(st, n, Vector3(x1 - x0, y1 - y0, 4.0), Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0))
	PuzzlePart.box_mesh(r.get_node("Visual"), n, Vector3(x1 - x0, y1 - y0, 2.4), Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0), mats[mat])


## Только вид (без формы): задняя стена, рамки.
func _decor(r: Node3D, n: String, size: Vector3, pos: Vector3, mat := "back") -> MeshInstance3D:
	return PuzzlePart.box_mesh(r.get_node("Visual"), n, size, pos, mats[mat])


## Кабель по задней стене: points — локальные точки комнаты (x, y).
func _cable(r: Node3D, n: String, source: Node, pts: Array) -> void:
	var c := _inst(r.get_node("Mech"), "cable", n, Vector3(0, 0, CABLE_Z))
	var arr := PackedVector2Array()
	for p in pts:
		arr.append(p)
	c.set("points", arr)
	c.set("source", c.get_path_to(source))


## Каркас комнаты i: пол, стены, потолок, проём выхода (door_y — низ проёма) с тамбуром, задняя стена, свет, точки появления.
func _room(holder: Node, i: int, door_y: float) -> Node3D:
	var r := Node3D.new()
	r.name = "Room%d" % (i + 1)
	r.set_script(load(ROOM))
	r.position = Vector3(i * PITCH, 0, 0)
	holder.add_child(r)
	r.set("index", i)
	r.set("exit_rect", Rect2(W * 0.5 + 1.2, door_y, 2.4, DOOR_H))
	for n in ["Visual", "Mech", "Props", "Spawns"]:
		var c := Node3D.new()
		c.name = n
		r.add_child(c)
	var st := StaticBody3D.new()
	st.name = "Static"
	r.add_child(st)
	r.move_child(st, 0)
	var hw := W * 0.5
	_solid(r, "Floor", -hw - 1.0, hw + 1.0, -1.0, 0.0, "floor")
	_solid(r, "Ceiling", -hw - 1.0, hw + 1.0, H, H + 1.0)
	_solid(r, "WallL", -hw - 1.0, -hw, 0.0, H)
	if door_y > 0.0:
		_solid(r, "WallR_Low", hw, hw + 1.0, 0.0, door_y)
	_solid(r, "WallR_High", hw, hw + 1.0, door_y + DOOR_H, H)
	# тамбур за дверью: пол, потолок, торец
	_solid(r, "ExitFloor", hw + 1.0, hw + 4.5, door_y - 1.0, door_y, "floor")
	_solid(r, "ExitCeiling", hw + 1.0, hw + 4.5, door_y + DOOR_H, door_y + DOOR_H + 1.0)
	_solid(r, "ExitEnd", hw + 3.6, hw + 4.5, door_y, door_y + DOOR_H)
	_decor(r, "Back", Vector3(W + 2.0, H + 2.0, 0.3), Vector3(0, H * 0.5, BACK_Z), "back")
	_decor(r, "ExitBack", Vector3(3.6, DOOR_H + 1.0, 0.3), Vector3(hw + 2.6, door_y + DOOR_H * 0.5, BACK_Z), "back")
	# полосы-плинтусы на задней стене (масштаб и «цех»)
	_decor(r, "TrimLow", Vector3(W, 0.3, 0.1), Vector3(0, 0.15, BACK_Z + 0.2), "trim")
	_decor(r, "TrimHigh", Vector3(W, 0.3, 0.1), Vector3(0, H - 0.15, BACK_Z + 0.2), "trim")
	# номер комнаты — крупно на задней стене
	var num := PuzzlePart.label(r.get_node("Visual"), "Number", "%d" % (i + 1), Vector3(-hw + 1.6, H - 1.6, BACK_Z + 0.2), 420, Color(1, 1, 1, 0.08))
	num.outline_size = 0
	num.pixel_size = 0.006
	# вход — закрытая дверь в левой стене (вид)
	_decor(r, "EntryDoor", Vector3(0.12, DOOR_H, 1.9), Vector3(-hw + 0.06, DOOR_H * 0.5, 0), "iron")
	_decor(r, "EntryFrame", Vector3(0.14, 0.2, 2.0), Vector3(-hw + 0.07, DOOR_H + 0.1, 0), "hazard")
	var door := _inst(r.get_node("Mech"), "door", "ExitDoor", Vector3(hw + 0.5, door_y, 0), {"height": DOOR_H, "thickness": 1.0})
	r.set("exit_door", r.get_path_to(door))
	_decor(r, "DoorFrame", Vector3(1.04, 0.2, 2.42), Vector3(hw + 0.5, door_y + DOOR_H + 0.1, 0), "hazard")
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.position = Vector3(0, H - 1.2, 3.0)
	lamp.light_color = Color(1.0, 0.92, 0.8)
	lamp.light_energy = 1.6
	lamp.omni_range = 16.0
	lamp.omni_attenuation = 0.8
	lamp.shadow_enabled = false
	r.add_child(lamp)
	for k in 2:
		var m := Marker3D.new()
		m.name = "Spawn%d" % k
		m.position = Vector3(-hw + 1.4 + 1.4 * k, 0.05, 0)
		r.get_node("Spawns").add_child(m)
	return r


func _crate(r: Node3D, n: String, kind: String, x: float, y_bottom: float) -> Node3D:
	var size: float = float(Tuning.PUZZLE_CRATES[kind]["size"])
	return _inst(r.get_node("Props"), "crate", n, Vector3(x, y_bottom + size * 0.5 + 0.01, 0), {"kind": kind})


func _texts(r: Node3D, title: String, hint: String, solo: String) -> void:
	r.set("title", title)
	r.set("hint", hint)
	r.set("solo", solo)


# ---------------------------------------------------------------- комнаты

## 1. Ящик на плиту → дверь (учит хватать и носить). Ящик 10 кг — на полке справа под потолком, плита — посередине пола: встать
## самому мало (сошёл — дверь захлопнулась раньше, чем долетишь), груз должен остаться на плите.
func _room1(r: Node3D) -> void:
	_texts(r, "Ящик на плиту",
		"Дверь открыта, пока на плите груз. Слетай за ящиком на полку, возьми его (E, у P2 — «/»), положи на плиту — и к выходу.", "")
	_solid(r, "Shelf", 4.4, 8.0, 4.2, 4.5, "iron")
	_crate(r, "Crate", "light", 6.4, 4.5)
	var plate := _inst(r.get_node("Mech"), "plate", "Plate", Vector3(-1.5, 0, 0), {"threshold_kg": 8.0, "width": 2.0})
	var door := r.get_node("Mech/ExitDoor")
	door.set("input", door.get_path_to(plate))
	_cable(r, "Cable", plate, [Vector2(-1.5, 0.15), Vector2(-1.5, 3.2), Vector2(7.4, 3.2), Vector2(7.4, 3.0)])


## 2. Две плиты сразу: встать обоим или кукла + ящик 35 кг (его только волоком). И → ТАЙМЕР 4 с → дверь: обе плиты нажаты —
## дверь открыта и держится 4 с после того, как с плит ушли.
func _room2(r: Node3D) -> void:
	_texts(r, "Две плиты сразу",
		"Обе плиты по 30 кг сразу — и таймер держит дверь 4 с. Вдвоём: встаньте каждый на свою плиту и летите к выходу.",
		"Один: ящик 35 кг не поднять — дотащи его волоком на одну плиту, сам встань на другую.")
	var a := _inst(r.get_node("Mech"), "plate", "PlateA", Vector3(-3.6, 0, 0), {"threshold_kg": 30.0, "width": 2.0})
	var b := _inst(r.get_node("Mech"), "plate", "PlateB", Vector3(3.6, 0, 0), {"threshold_kg": 30.0, "width": 2.0})
	var and_ := _inst(r.get_node("Mech"), "logic", "And", Vector3(0.0, 4.6, CABLE_Z), {"mode": PuzzleLogic.Mode.AND})
	and_.set("inputs", [and_.get_path_to(a), and_.get_path_to(b)] as Array[NodePath])
	var tm := _inst(r.get_node("Mech"), "logic", "Timer", Vector3(5.0, 4.6, CABLE_Z), {"mode": PuzzleLogic.Mode.TIMER, "hold_s": 4.0})
	tm.set("inputs", [tm.get_path_to(and_)] as Array[NodePath])
	var door := r.get_node("Mech/ExitDoor")
	door.set("input", door.get_path_to(tm))
	_cable(r, "CableA", a, [Vector2(-3.6, 0.15), Vector2(-3.6, 4.6), Vector2(-0.55, 4.6)])
	_cable(r, "CableB", b, [Vector2(3.6, 0.15), Vector2(3.6, 3.6), Vector2(0.0, 3.6), Vector2(0.0, 4.25)])
	_cable(r, "CableAnd", and_, [Vector2(0.55, 4.6), Vector2(4.45, 4.6)])
	_cable(r, "CableTimer", tm, [Vector2(5.55, 4.6), Vector2(7.4, 4.6), Vector2(7.4, 3.0)])
	_crate(r, "Medium", "medium", -0.4, 0.0)
	_crate(r, "LightA", "light", 6.6, 0.0)
	_crate(r, "LightB", "light", 1.6, 0.0)


## 3. Тяжёлый ящик вдвоём на весы: уступ справа (верх 3 м), на нём грузовые весы 55 кг (куклы не в счёт), дверь — над уступом.
## Ящик 60 кг одной рукой не поднять (210 Н > 150), двумя — да. Соло: четыре ящика по 15 кг.
func _room3(r: Node3D) -> void:
	_texts(r, "Тяжёлый ящик вдвоём",
		"Весы на уступе ждут 55 кг груза — куклы не в счёт. Ящик 60 кг одной рукой не поднять: возьмитесь вдвоём и несите наверх.",
		"Один: отнеси на весы четыре ящика по 15 кг, по одному.")
	_solid(r, "Ledge", 2.6, 8.0, 0.0, 3.0, "iron")
	_decor(r, "LedgeEdge", Vector3(0.2, 0.18, 2.44), Vector3(2.7, 2.91, 0), "hazard")
	var scale := _inst(r.get_node("Mech"), "plate", "Scale", Vector3(5.0, 3.0, 0), {"threshold_kg": 55.0, "width": 2.6,
		"count_dolls": false, "pad_colour": Color(0.3, 0.65, 1.0)})
	var door := r.get_node("Mech/ExitDoor")
	door.set("input", door.get_path_to(scale))
	_cable(r, "Cable", scale, [Vector2(5.0, 3.15), Vector2(5.0, 6.4), Vector2(7.4, 6.4), Vector2(7.4, 6.0)])
	_crate(r, "Duo", "duo", -3.0, 0.0)
	_crate(r, "Box1", "box15", -0.2, 0.0)
	_crate(r, "Box2", "box15", 0.5, 0.0)
	_crate(r, "Box3", "box15", 1.2, 0.0)
	_crate(r, "Box4", "box15", 0.15, 0.64)


## 4. Рычаг гравитации: рычаг поворачивает «низ» комнаты вправо; чугунный ящик 90 кг на полке посередине съезжает и падает на
## грузовую плиту на правой стене (50 кг) → дверь внизу той же стены. Руками и телом ящик к плите не поднять.
func _room4(r: Node3D) -> void:
	_texts(r, "Рычаг гравитации",
		"Рычаг поворачивает «низ» комнаты. Чугунный ящик 90 кг не поднять — пусть упадёт на плиту на стене сам. Рычаг: схвати рукоять и перекинь или толкни телом.", "")
	var g := _inst(r.get_node("Mech"), "gravity_zone", "Gravity", Vector3(0, H * 0.5, 0), {"size": Vector2(W, H),
		"on_dir": Vector2(1, 0), "off_dir": Vector2(0, -1), "sign_offset": Vector3(-3.4, 2.2, BACK_Z + 0.25)})
	var lever := _inst(r.get_node("Mech"), "lever", "Lever", Vector3(-3.6, 0, 0), {"start_on": false})
	g.set("input", g.get_path_to(lever))
	_solid(r, "Shelf", -3.0, 0.6, 4.1, 4.5, "iron")
	_decor(r, "Bracket", Vector3(0.5, 4.1, 0.3), Vector3(-1.2, 2.05, BACK_Z + 0.25), "iron")   # кронштейн полки — на задней стене, пол свободен
	_crate(r, "Iron", "iron", -1.6, 4.5)
	var wp := _inst(r.get_node("Mech"), "plate", "WallPlate", Vector3(8.0, 5.3, 0), {"threshold_kg": 50.0, "width": 2.8,
		"count_dolls": false, "pad_colour": Color(0.3, 0.65, 1.0)})
	wp.rotation_degrees = Vector3(0, 0, 90)
	var door := r.get_node("Mech/ExitDoor")
	door.set("input", door.get_path_to(wp))
	_cable(r, "CableLever", lever, [Vector2(-3.6, 0.3), Vector2(-3.6, 1.2), Vector2(-4.4, 1.2), Vector2(-4.4, 6.7), Vector2(-4.15, 6.7)])
	_cable(r, "CablePlate", wp, [Vector2(7.6, 6.9), Vector2(6.6, 6.9), Vector2(6.6, 3.4), Vector2(7.4, 3.4), Vector2(7.4, 3.0)])
	_crate(r, "LightA", "light", 2.6, 0.0)
	_crate(r, "LightB", "light", 4.6, 0.0)


## 5. Лифт: чугунный ящик закатить на лифт (в яме у пола), лифт едет вверх, пока горит ТАЙМЕР 8 с от плиты; наверху — балкон с
## грузовыми весами 50 кг → дверь над балконом. Соло: ящик 35 кг с полки слева — на плиту (лифт ждёт) или успеть за 8 с.
func _room5(r: Node3D) -> void:
	_texts(r, "Лифт",
		"Лифт едет вверх, пока горит таймер от плиты. Закатите чугунный ящик на лифт; один держит плиту, другой наверху сталкивает ящик на весы.",
		"Один: положи на плиту ящик 35 кг с полки — лифт будет ждать. Или встань на плиту и успей наверх за 8 с.")
	# яма лифта: пол x 0…3 ниже на 0.35 (платформа вровень с полом)
	var fl := r.get_node("Static/Floor")
	r.get_node("Static").remove_child(fl)
	fl.free()
	var fv := r.get_node("Visual/Floor")
	r.get_node("Visual").remove_child(fv)
	fv.free()
	_solid(r, "FloorL", -W * 0.5 - 1.0, 0.0, -1.0, 0.0, "floor")
	_solid(r, "FloorR", 3.0, W * 0.5 + 1.0, -1.0, 0.0, "floor")
	_solid(r, "Pit", 0.0, 3.0, -1.0, -0.35, "iron")
	_solid(r, "Balcony", 3.05, 8.0, 4.6, 5.0, "iron")
	_decor(r, "BalconyEdge", Vector3(0.2, 0.18, 2.44), Vector3(3.15, 4.91, 0), "hazard")
	_solid(r, "Shelf", -8.0, -6.2, 2.7, 3.0, "iron")
	var plate := _inst(r.get_node("Mech"), "plate", "Plate", Vector3(-3.6, 0, 0), {"threshold_kg": 30.0, "width": 2.0})
	var tm := _inst(r.get_node("Mech"), "logic", "Timer", Vector3(-1.4, 6.6, CABLE_Z), {"mode": PuzzleLogic.Mode.TIMER, "hold_s": 8.0})
	tm.set("inputs", [tm.get_path_to(plate)] as Array[NodePath])
	var lift := _inst(r.get_node("Mech"), "lift", "Lift", Vector3(1.5, 0, 0), {"width": 2.96, "travel": 5.0})
	lift.set("input", lift.get_path_to(tm))
	var scale := _inst(r.get_node("Mech"), "plate", "Scale", Vector3(5.8, 5.0, 0), {"threshold_kg": 50.0, "width": 2.4,
		"count_dolls": false, "pad_colour": Color(0.3, 0.65, 1.0)})
	var door := r.get_node("Mech/ExitDoor")
	door.set("input", door.get_path_to(scale))
	_cable(r, "CablePlate", plate, [Vector2(-3.6, 0.15), Vector2(-3.6, 6.6), Vector2(-1.95, 6.6)])
	_cable(r, "CableTimer", tm, [Vector2(-0.85, 6.6), Vector2(1.5, 6.6), Vector2(1.5, 5.9)])
	_cable(r, "CableScale", scale, [Vector2(5.8, 5.15), Vector2(5.8, 8.3), Vector2(7.4, 8.3), Vector2(7.4, 7.8)])
	_crate(r, "Iron", "iron", -1.4, 0.0)
	_crate(r, "Medium", "medium", -7.1, 3.0)


## 6. Финал: бочку — в трещину стены (Breakable рвётся только от взрыва), за стеной в нише — плита → ТАЙМЕР 6 с → дверь наверху
## справа: успеть. Раздатчик под потолком роняет новую бочку, если бочек не осталось, а стена цела.
func _room6(r: Node3D) -> void:
	_texts(r, "Финал: трещина",
		"Брось взрывную бочку в трещину (P1: ЛКМ + E, P2: стрелка + «/»). За стеной плита: дверь наверху откроется на 6 с — успейте.", "")
	_solid(r, "NicheRoof", 4.9, 8.0, 3.0, 3.4, "iron")
	_solid(r, "DoorLedge", 6.4, 8.0, 5.2, 5.6, "iron")
	var wall := _inst(r.get_node("Props"), "crack_wall", "CrackWall", Vector3(5.2, 0, 0), {"size": Vector2(0.6, 3.0)})
	var plate := _inst(r.get_node("Mech"), "plate", "Plate", Vector3(6.85, 0, 0), {"threshold_kg": 30.0, "width": 1.9})
	var tm := _inst(r.get_node("Mech"), "logic", "Timer", Vector3(3.6, 7.2, CABLE_Z), {"mode": PuzzleLogic.Mode.TIMER, "hold_s": 6.0})
	tm.set("inputs", [tm.get_path_to(plate)] as Array[NodePath])
	var door := r.get_node("Mech/ExitDoor")
	door.set("input", door.get_path_to(tm))
	_cable(r, "CablePlate", plate, [Vector2(6.85, 0.15), Vector2(6.85, 2.6), Vector2(4.6, 2.6), Vector2(4.6, 6.4), Vector2(3.6, 6.4), Vector2(3.6, 6.85)])
	_cable(r, "CableTimer", tm, [Vector2(4.15, 7.2), Vector2(7.4, 7.2), Vector2(7.4, 8.5)])
	_inst(r.get_node("Props"), BARREL, "BarrelA", Vector3(-3.6, 0.02, 0))
	_inst(r.get_node("Props"), BARREL, "BarrelB", Vector3(-2.4, 0.02, 0))
	var disp := _inst(r.get_node("Mech"), "dispenser", "Dispenser", Vector3(-3.0, H - 0.25, 0), {"keep": 1})
	disp.set("until", disp.get_path_to(wall))
	disp.set("into", disp.get_path_to(r.get_node("Props")))


# ---------------------------------------------------------------- игровое

func _camera() -> void:
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.set_script(load(CAMERA))
	cam.add_to_group("camera", true)
	cam.fov = 40.0
	cam.position = Vector3(0, H * 0.5, 16)
	root.add_child(cam)
	cam.set("arena_path", NodePath(".."))
	cam.set("floor_inset", 0.0)
	cam.set("target_group", "dolls")
	cam.set("min_half_height", 5.25)
	cam.set("max_half_height", 5.25)
	cam.set("padding", 2.0)
	cam.set("follow_tau", 0.25)


func _environment() -> void:
	var env := WorldEnvironment.new()
	env.name = "Environment"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.035, 0.045)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.7)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.05
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_bloom = 0.03
	e.glow_hdr_threshold = 1.0
	env.environment = e
	var cam := CameraAttributesPractical.new()
	cam.dof_blur_far_enabled = false
	cam.dof_blur_near_enabled = false
	env.camera_attributes = cam
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.basis = Basis.looking_at(Vector3(0.35, -0.7, -0.62).normalized(), Vector3.UP)
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.shadow_blur = 1.0
	sun.directional_shadow_max_distance = 40.0
	root.add_child(sun)
