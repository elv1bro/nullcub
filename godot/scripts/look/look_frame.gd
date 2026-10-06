## Проход по картинке, направление look-frame (docs/plan-demo/look/frame.md): «правило кадра» — боец самое читаемое в кадре, фон
## отступает; «дорогой пластик». Автозагрузка «LookFrame». Пункты панели «ВИД» (Look, клавиша Э), каждый по умолчанию включён,
## выключение возвращает ровно прежний вид:
##   Кадр:    frame_rim      — контровой свет: два DirectionalLight3D сзади-сбоку («кикеры» слева и справа) светят только на меши
##                             кукол (бит FrameDress.RIM_BIT, light_cull_mask) — светлый край силуэта, арена не светлеет;
##            frame_glow     — свечение цвета игрока (обмотки, краска цвета игрока, шары суставов, окошко ядра кита) — FrameDress;
##            frame_shadow   — тень-пятно у пола и стен (Decal по лучу из центра масс) — FrameShadows;
##            frame_backdrop — фон отступает: туман глубины за плоскостью боя, цветокоррекция, фон-параллакс темнее — FrameArena;
##            frame_lamps    — полосы ламп купола и спорт-зала на 38 % тише — FrameArena;
##   Пластик: plastic_coat   — лак (clearcoat) на краске и пластике кита — FrameDress;
##            plastic_probe  — ReflectionProbe интерьера купола и спорт-зала (один снимок, отражения только на куклах) — FrameArena.
## Применяется и снимается СРАЗУ в обработчике Look.changed (снимки «до / после» снимаются на паузе дерева). Куклы — группа "dolls":
## новая кукла одевается в ближайший кадр (по одной за кадр), раз в RESCAN_S — пересмотр подписи мешей и материалов (SquadLook меняет
## меши по классу, _recolor — цвет команды, возрождение — новая кукла). Арены — WorldEnvironment сцен из FrameArena.PROFILES.
## В headless — ничего не делает (числа проб не должны зависеть от вида), пока проба не включит headless_enabled (look_frame_probe).
extends Node

const ITEMS := [
	[&"frame_rim", "Контровой свет на бойцов", "Кадр"],
	[&"frame_glow", "Свечение цвета игрока", "Кадр"],
	[&"frame_shadow", "Тень-пятно у пола и стен", "Кадр"],
	[&"frame_backdrop", "Фон отступает: туман глубины, цвет", "Кадр"],
	[&"frame_lamps", "Лампы купола тише", "Кадр"],
	[&"plastic_coat", "Лак на краске и пластике", "Пластик"],
	[&"plastic_probe", "Отражения арены", "Пластик"],
]
const RESCAN_S := 1.0                # новые куклы и уход кукол; подпись материалов — по одной кукле за кадр
const RIM_COLOUR := Color(0.8, 0.88, 1.0)
const RIM_ENERGY := 0.9
const RIM_SPECULAR := 0.9
## Куда идёт свет кикеров: из-за спины бойцов (−Z) сбоку и чуть сверху — к камере (+Z). Лицевые грани (нормаль к камере) не светлеют,
## светлеет крайняя треть каждой детали — край силуэта.
const RIM_DIRS := [Vector3(0.85, -0.3, 0.43), Vector3(-0.85, -0.3, 0.43)]

static var headless_enabled := false

var shadows: FrameShadows
var rim_lights: Array[DirectionalLight3D] = []
var arenas: Array = []              # FrameArena
var _dressed := {}                  # instance id куклы → {"sig": int, "rim": bool, "glow": bool, "coat": bool}
var _queue: Array = []              # куклы, которые надо (пере)одеть, по одной за кадр
var _scan_list: Array = []          # куклы на проверку подписи, по одной за кадр
var _new_meshes: Array = []         # [кукла, меш] — новые меши одетых кукол, одеваются в следующем кадре
var _rescan_t := 0.0
var _look: Node
var _items_added := false


func _ready() -> void:
	_look = get_node_or_null("/root/Look")
	if _look != null:
		_look.connect("changed", _on_look)
	shadows = FrameShadows.new()
	add_child(shadows)
	for i in RIM_DIRS.size():
		var l := DirectionalLight3D.new()
		l.name = "FrameRimLight_%s" % ["L", "R"][i]
		l.light_color = RIM_COLOUR
		l.light_energy = RIM_ENERGY
		l.light_specular = RIM_SPECULAR
		l.light_cull_mask = FrameDress.RIM_BIT
		l.shadow_enabled = false
		l.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
		l.visible = false
		l.transform = Transform3D(Basis.looking_at(RIM_DIRS[i], Vector3.UP), Vector3.ZERO)
		add_child(l)
		rim_lights.append(l)
	shadows.enabled = active() and on(&"frame_shadow")
	_update_rim_light()
	get_tree().node_added.connect(_on_node_added)
	for n in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		_add_we.call_deferred(n)


## Пункты в панели «ВИД» — когда в сцене появилась арена или кукла (панель показывает пробы этой сцены; меню без кукол — без них).
func _ensure_items() -> void:
	if _items_added or _look == null:
		return
	_items_added = true
	for it in ITEMS:
		_look.call("add", it[0], tr(String(it[1])), tr(String(it[2])))


## Работает ли проход: с окном — всегда, в headless — только по просьбе пробы.
func active() -> bool:
	return headless_enabled or DisplayServer.get_name() != "headless"


## Пересобрать всё по текущим галочкам (проба включила headless_enabled уже после старта).
func refresh() -> void:
	shadows.enabled = active() and on(&"frame_shadow")
	if not active():
		return
	_ensure_items()
	for n in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		_add_we(n)
	for d in _dolls():
		_dress_all(d)
	_update_rim_light()


func on(id: StringName) -> bool:
	return _look == null or bool(_look.call("on", id))


func _on_node_added(n: Node) -> void:
	if n is WorldEnvironment:
		_add_we.call_deferred(n)   # environment ставится уже после add_child (как у Gfx)
	elif n is Doll and not _items_added:
		_doll_added.call_deferred(n)   # группу "dolls" площадки дают и после add_child
	elif n is MeshInstance3D and not _dressed.is_empty():
		_mesh_added(n)


## Новый меш внутри одетой куклы (SquadLook сменил класс, деталь прикрутили, оружие в руке): одеть только его — в следующем кадре
## (материал ему ставят уже после add_child), без обхода всей куклы.
func _mesh_added(n: Node) -> void:
	if not FrameDress.eligible(n) and not (n is MeshInstance3D and (n as MeshInstance3D).mesh == null):
		return
	var p := n.get_parent()
	for i in 10:
		if p == null:
			return
		if p is Doll:
			if _dressed.has(p.get_instance_id()):
				_new_meshes.append([p, n])
			return
		p = p.get_parent()


func _dress_new_meshes() -> void:
	var by_doll := {}
	for pair in _new_meshes:
		var d: Variant = pair[0]
		var m: Variant = pair[1]
		if is_instance_valid(d) and is_instance_valid(m) and (m as Node).is_inside_tree() and FrameDress.eligible(m):
			var id := (d as Node).get_instance_id()
			if not by_doll.has(id):
				by_doll[id] = [d, []]
			(by_doll[id][1] as Array).append(m)
	_new_meshes.clear()
	for id in by_doll:
		var d: Node = by_doll[id][0]
		var list: Array = by_doll[id][1]
		var st: Dictionary = _dressed.get(id, {})
		if st.is_empty():
			continue
		FrameDress.set_rim(d, on(&"frame_rim"), list)
		FrameDress.set_glow(d, on(&"frame_glow"), st.get("colour", colour_of(d)), list)
		FrameDress.set_coat(d, on(&"plastic_coat"), list)
		FrameDress.set_layer(d, FrameDress.PROBE_BIT, on(&"plastic_probe"), list)
		var meshes: Array = st.get("meshes", [])
		meshes.append_array(list)
		st["sig"] = _signature(d, meshes)


## Первая кукла боя — пункты в панели (и в headless: проба вёрстки открывает панель над куполом).
func _doll_added(n: Node) -> void:
	if is_instance_valid(n) and n.is_in_group("dolls"):
		_ensure_items()


func _add_we(n: Node) -> void:
	if not active() or n == null or not is_instance_valid(n) or not n.is_inside_tree():
		return
	for a in arenas:
		if (a as FrameArena).we == n:
			return
	var a := FrameArena.find(n as WorldEnvironment)
	if a == null:
		return
	_ensure_items()
	arenas.append(a)
	n.tree_exiting.connect(_on_we_exit.bind(a), CONNECT_ONE_SHOT)
	a.set_backdrop(on(&"frame_backdrop"))
	a.set_lamps(on(&"frame_lamps"))
	a.set_probe(on(&"plastic_probe"), self)
	_update_rim_light()


func _on_we_exit(a: FrameArena) -> void:
	a.release()
	arenas.erase(a)
	if arenas.is_empty():
		FrameDress.clear_caches()
	_update_rim_light()


func _on_look(id: StringName, v: bool) -> void:
	if not active():
		return
	match id:
		&"frame_rim", &"frame_glow", &"plastic_coat":
			for d in _dolls():
				_dress(d, id, v)
			_update_rim_light()
			return
		&"frame_shadow":
			shadows.enabled = v
		&"frame_backdrop":
			for a in arenas:
				(a as FrameArena).set_backdrop(v)
		&"frame_lamps":
			for a in arenas:
				(a as FrameArena).set_lamps(v)
		&"plastic_probe":
			for a in arenas:
				(a as FrameArena).set_probe(v, self)
			for d in _dolls():
				_dress(d, id, v)


func _process(delta: float) -> void:
	if not active():
		return
	_rescan_t -= delta
	if _rescan_t <= 0.0:
		_rescan_t = RESCAN_S
		_rescan()
	if not _new_meshes.is_empty():
		_dress_new_meshes()
	var done := false
	while not _queue.is_empty() and not done:   # одеть — одну куклу за кадр
		var d: Variant = _queue.pop_front()
		if d is Doll and is_instance_valid(d) and (d as Node).is_inside_tree():
			_dress_all(d)
			done = true
	while not done and not _scan_list.is_empty():   # проверить подпись — тоже одну за кадр (без всплеска раз в секунду)
		var d: Variant = _scan_list.pop_back()
		if d is Doll and is_instance_valid(d) and (d as Node).is_inside_tree():
			if _stale(d) and not _queue.has(d):
				_queue.append(d)
			done = true
	var cam := get_viewport().get_camera_3d()
	for a in arenas:
		if (a as FrameArena).valid():
			(a as FrameArena).update_camera(cam)


func _dolls() -> Array:
	var out: Array = []
	if not is_inside_tree():
		return out
	for d in get_tree().get_nodes_in_group("dolls"):
		if d is Doll and (d as Node).is_inside_tree():
			out.append(d)
	return out


## Пересмотр раз в RESCAN_S: новые куклы — сразу в очередь, остальные — в список проверки подписи (по одной за кадр); ушедшие — из учёта.
func _rescan() -> void:
	var seen := {}
	var dolls := _dolls()
	if not dolls.is_empty():
		_ensure_items()
	_scan_list.clear()
	for d in dolls:
		var id := (d as Node).get_instance_id()
		seen[id] = true
		if not _dressed.has(id):
			if not _queue.has(d):
				_queue.append(d)
		else:
			_scan_list.append(d)
	for id in _dressed.keys():
		if not seen.has(id):
			_dressed.erase(id)
	_update_rim_light()


## Одета не так: сменились материалы (цвет команды) или галочки. Новые меши ловит _mesh_added; подпись — по мешам с прошлого
## одевания, без обхода дерева куклы.
func _stale(d: Node) -> bool:
	var st: Dictionary = _dressed.get(d.get_instance_id(), {})
	return st.is_empty() or int(st["sig"]) != _signature(d, st.get("meshes", [])) or bool(st["rim"]) != on(&"frame_rim") \
		or bool(st["glow"]) != on(&"frame_glow") or bool(st["coat"]) != on(&"plastic_coat") or bool(st["probe"]) != on(&"plastic_probe")


## Подпись куклы: меши и их override-материалы (meshes — готовый список, иначе обход дерева).
func _signature(d: Node, meshes: Array = []) -> int:
	var h := 0
	for mi in (meshes if not meshes.is_empty() else FrameDress.meshes(d)):
		if not is_instance_valid(mi):
			continue
		var m := mi as MeshInstance3D
		h = (h * 31 + m.get_instance_id()) & 0x7FFFFFFF
		for s in m.mesh.get_surface_count():
			var o := m.get_surface_override_material(s)
			h = (h * 31 + (o.get_instance_id() if o != null else 1)) & 0x7FFFFFFF
	return h


func _dress_all(d: Node) -> void:
	_dress(d, &"frame_rim", on(&"frame_rim"), false)
	_dress(d, &"frame_glow", on(&"frame_glow"), false)
	_dress(d, &"plastic_coat", on(&"plastic_coat"), false)
	_dress(d, &"plastic_probe", on(&"plastic_probe"), false)
	var meshes := FrameDress.meshes(d)
	_dressed[d.get_instance_id()] = {"sig": _signature(d, meshes), "meshes": meshes, "colour": colour_of(d), "rim": on(&"frame_rim"),
		"glow": on(&"frame_glow"), "coat": on(&"plastic_coat"), "probe": on(&"plastic_probe")}


func _dress(d: Node, id: StringName, v: bool, record := true) -> void:
	match id:
		&"frame_rim":
			FrameDress.set_rim(d, v)
		&"frame_glow":
			FrameDress.set_glow(d, v, colour_of(d))
		&"plastic_coat":
			FrameDress.set_coat(d, v)
		&"plastic_probe":
			FrameDress.set_layer(d, FrameDress.PROBE_BIT, v)
	var st: Dictionary = _dressed.get(d.get_instance_id(), {})
	if record and not st.is_empty():
		st[{&"frame_rim": "rim", &"frame_glow": "glow", &"plastic_coat": "coat", &"plastic_probe": "probe"}[id]] = v
		st["sig"] = _signature(d, st.get("meshes", []))


## Цвет куклы для свечения ядра: краска цвета игрока / команды (Shirt*), иначе — цвет игрока по номеру.
static func colour_of(d: Node) -> Color:
	for mi in FrameDress.meshes(d):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var o := m.get_surface_override_material(s) as BaseMaterial3D
			if o != null and o.resource_name.begins_with("Shirt"):
				return Color(o.albedo_color.r, o.albedo_color.g, o.albedo_color.b)
	return HitJuice.paint_colour(d)


## Кикеры видимы всегда, пока проход работает (и в меню): число направленных источников в кадре не меняется — галочка «контровой
## свет» не пересобирает пайплайны всех материалов сцены; выключение — снятый бит RIM_BIT у кукол (кикерам светить не на что).
func _update_rim_light() -> void:
	if rim_lights.is_empty():
		return
	var mult := 1.0
	for a in arenas:
		if (a as FrameArena).valid():
			mult = (a as FrameArena).rim_mult()
	for l in rim_lights:
		l.light_energy = RIM_ENERGY * mult
		l.visible = active()


## Контровой свет сейчас ложится на кукол: кикеры видимы и у кукол есть бит слоя.
func rim_visible() -> bool:
	if rim_lights.is_empty() or not rim_lights[0].visible:
		return false
	for d in _dolls():
		for mi in FrameDress.meshes(d):
			if (mi as MeshInstance3D).layers & FrameDress.RIM_BIT:
				return true
	return false


## Для проб: сколько кукол одето и в каком состоянии.
func dressed_count() -> int:
	return _dressed.size()
