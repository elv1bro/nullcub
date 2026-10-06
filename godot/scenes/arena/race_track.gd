## Карта «Гонка: трасса» (docs/plan-demo/RACE_TRACK.md) — только поведение; сцену race_track.tscn собирает tools/build_race_track.gd.
## Длинная трасса старт → финиш вбок (~420 м, x −8…426), шесть участков: разгон с кольцами, прессы и магниты Свалки, узкие трубы со
## стенками-мембранами, поля гравитации, тяжёлая зона, яма с рвущимися мостами и бочками → финиш. Развилки A, B, C — длинный лёгкий и
## короткий трудный путь; на развилке B короткий путь — пара порталов (Portal/PortalPairB: A на метке PortalSlotA → B на PortalSlotB).
## Здесь: границы для камеры, старт (Spawns/Spawn0..3), контрольные точки (Checkpoints/*, TrackCheckpoint), линия ботов (Route — её
## читает TrackRoute), участки (Sections/S1..S6: мета x0, x1), финиш (Finish: мета x), сигнал body_fell от всех зон KO (группа
## TrackArena.DEATH_GROUP: яма, сетка в потолке короткого пути развилки C).
class_name TrackArena
extends Node3D

signal body_fell(body: Node3D)

const DEATH_GROUP := "track_death"

## Границы для камеры (кадр не выходит за них): вся трасса.
@export var arena_bounds := AABB(Vector3(-12.0, -18.0, -1.0), Vector3(436.0, 46.0, 2.0))

## «Ключ камеры» (SpotLight3D CameraKey, как на Свалке): едет за активной камерой — закрытые коридоры светлые там, где игрок.
@export var key_offset := Vector3(-2.0, 2.5, 0.0)

var _route: TrackRoute
var _key: SpotLight3D


func _ready() -> void:
	for a in find_children("*", "Area3D", true, false):
		if (a as Node).is_in_group(DEATH_GROUP):
			(a as Area3D).body_entered.connect(func(b: Node3D) -> void: body_fell.emit(b))
	# циклы машин — из Tuning (сдвиги фаз — в сцене, их ставит сборщик)
	for p in presses():
		_cycle(p as ScrapMachine, Tuning.TRACK_PRESS_CYCLE)
	for m in magnets():
		_cycle(m as ScrapMachine, Tuning.TRACK_MAGNET_CYCLE)
	_key = get_node_or_null("CameraKey") as SpotLight3D
	if _key != null:
		_key.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


static func _cycle(m: ScrapMachine, c: Array) -> void:
	m.auto_cycle = true
	m.off_s = float(c[0])
	m.warning_s = float(c[1])
	m.active_s = float(c[2])
	m.cooldown_s = float(c[3])


func _process(_delta: float) -> void:
	if _key == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := cam.global_position
	_key.global_position = c + key_offset
	_key.look_at(Vector3(c.x, c.y, 0.0), Vector3.UP)


func bounds() -> AABB:
	return arena_bounds


## Старт (мировые точки) в порядке player_index.
func spawn_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var holder := get_node_or_null("Spawns")
	if holder != null:
		for m in holder.get_children():
			if m is Node3D:
				out.append((m as Node3D).global_position)
	return out


## Контрольные точки по порядку (0 — старт).
func checkpoints() -> Array:
	var out: Array = []
	var holder := get_node_or_null("Checkpoints")
	if holder != null:
		for c in holder.get_children():
			if c is TrackCheckpoint:
				out.append(c)
	return out


## Линия трассы (строится один раз, после входа в дерево — нужны мировые координаты точек).
func route() -> TrackRoute:
	if _route == null or not _route.ready():
		_route = TrackRoute.new()
		_route.build(get_node_or_null("Route"))
	return _route


## Участки: [{index (1..6), x0, x1}] по x.
func sections() -> Array:
	var out: Array = []
	var holder := get_node_or_null("Sections")
	if holder != null:
		for s in holder.get_children():
			out.append({"index": int(s.get_meta("index", out.size() + 1)), "x0": float(s.get_meta("x0", 0.0)), "x1": float(s.get_meta("x1", 0.0))})
	return out


## Номер участка (1..6) по x.
func section_at(x: float) -> int:
	var n := 1
	for s in sections():
		if x >= float(s["x0"]):
			n = int(s["index"])
	return n


## Линия финиша (x).
func finish_x() -> float:
	var f := get_node_or_null("Finish")
	return float(f.get_meta("x", 404.0)) if f != null else 404.0


## Пара порталов развилки B (PortalPair) или null.
func portal_pair() -> PortalPair:
	return get_node_or_null("Portal/PortalPairB") as PortalPair


## Метки пары порталов (развилка B): [PortalSlotA, PortalSlotB] или пусто.
func portal_slots() -> Array:
	var a := find_child("PortalSlotA", true, false)
	var b := find_child("PortalSlotB", true, false)
	return [a, b] if a != null and b != null else []


func rings() -> Array:
	return find_children("*", "TrackRing", true, false)


func bridges() -> Array:
	return find_children("*", "TrackBridgeSlot", true, false)


func barrels() -> Array:
	return find_children("*", "TrackBarrelSlot", true, false)


func presses() -> Array:
	return find_children("*", "PressMachine", true, false)


func magnets() -> Array:
	return find_children("*", "MagnetMachine", true, false)
