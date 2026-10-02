## Выход бойца на арену купола (docs/plan-demo/16-fighter-entrance.md; лор §7 «Fighter entrances»). Узел площадки с куполом:
## перед боем каждый боец выходит по очереди, потом — отсчёт и FIGHT! (Match.begin, у матча autostart = false).
## Один выход (Tuning.ENTRANCE_*):
##   1. свет зала гаснет до ENTRANCE_DIM_ENERGY (лампы Lights арены), табло пишет имя бойца, карточка внизу — имя, сборка, масса,
##      счёт; камера выхода (EntranceCam) смотрит на ворота бойца;
##   2. створки ворот (GateA / GateB, узлы Gate_Door_L / Gate_Door_R с петлями) открываются;
##   3. кукла не ходит — её везёт «платформа ворот»: тела заморожены (FREEZE_MODE_KINEMATIC; мембрана NullField замороженные
##      не трогает) и едут от ворот (за полем, z ворот) к плоскости боя и сквозь мембрану внутрь купола;
##   4. за мембраной тела отпускаются со скоростью ENTRANCE_RELEASE_SPEED внутрь: поле NULL подхватывает бойца, конечности
##      всплывают — главный кадр выхода; толпа заводится, у N0 — EXCITED;
##   5. кадр держится ENTRANCE_HOLD_S, следующий боец. Ждущий боец спрятан у своих ворот.
## Урона нет: пока идёт выход, у кукол управление выключено, а матч не начат. Кнопка (любая клавиша / кнопка мыши / геймпада):
## первая — выход в ENTRANCE_FAST раз быстрее, вторая — пропуск: куклы сразу на точках спавна, отпущены, бой начинается.
## Сигнал finished — площадка зовёт Match.begin(). Пробы: play() / skip() без ввода, timeline — время шагов.
class_name FighterEntrance
extends Node

signal finished(skipped: bool)

const GATES := ["GateA", "GateB"]               # P1 — левые ворота, P2 — правые
const DOOR_OPEN_DEG := 100.0
const PLATFORM_Z := 0.0                         # плоскость боя

@export var arena_path: NodePath = ^"../NullHall"
@export var camera_path: NodePath = ^"../EntranceCam"
@export var fight_camera_path: NodePath = ^"../Camera"
@export var card_path: NodePath = ^"Card"
## Скрывать на время выхода (HUD, стрелки за экраном).
@export var hide_paths: Array[NodePath] = [^"../HUD", ^"../Offscreen"]

var running := false
var speed := 1.0
var skipped := false
var presses := 0
var timeline: Array = []      # [{fighter, step, t}] — время шагов (физическое, с начала выхода; ускорение кнопкой — быстрее)
var clock := 0.0
var arena: Node3D
var cam: Camera3D
var card: Node
var _lights: Dictionary = {}  # Light3D -> исходная энергия
var _board: Label3D = null
var _board_text := ""
var _fighters: Array = []


func _ready() -> void:
	arena = get_node_or_null(arena_path) as Node3D
	cam = get_node_or_null(camera_path) as Camera3D
	card = get_node_or_null(card_path)
	if arena != null:
		_board = arena.find_child("Text_NULL_FIELD", true, false) as Label3D
		var lights := arena.get_node_or_null("Lights")
		if lights != null:
			for l in lights.find_children("*", "Light3D", true, false):
				_lights[l] = (l as Light3D).light_energy


func _input(event: InputEvent) -> void:
	if not running:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) or (event is InputEventJoypadButton and event.pressed)
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	presses += 1
	if presses == 1:
		speed = Tuning.ENTRANCE_FAST
	else:
		skip()


## Выход бойцов по очереди. fighters: [{doll: Doll, name, build, mass, record}] — порядок = порядок ворот GATES.
func play(fighters: Array) -> void:
	_fighters = fighters
	running = true
	skipped = false
	presses = 0
	speed = 1.0
	timeline.clear()
	clock = 0.0
	if _board != null:
		_board_text = _board.text
	for p in hide_paths:
		var n := get_node_or_null(p)
		if n != null and "visible" in n:
			n.set("visible", false)
	for i in fighters.size():
		var d: Doll = fighters[i]["doll"]
		d.control_enabled = false
		_freeze(d, true)
		_place_at_gate(d, i)
		d.visible = false
	if cam != null:
		cam.make_current()
	_dim(true)
	for i in fighters.size():
		if skipped:
			break
		await _one(i)
	if not skipped:
		_finish(false)


## Пропуск: все бойцы — на точки спавна, отпущены, свет и камера как в бою.
func skip() -> void:
	if not running or skipped:
		return
	skipped = true
	var spawns: Array = arena.call("spawn_points") if arena != null and arena.has_method("spawn_points") else []
	for i in _fighters.size():
		var d: Doll = _fighters[i]["doll"]
		if not is_instance_valid(d):
			continue
		var target: Vector3 = spawns[i] if i < spawns.size() else Vector3(-5.0 + 10.0 * i, 2.5, 0.0)
		_move_to(d, target)
		_freeze(d, false)
		d.visible = true
	for i in GATES.size():
		_doors(i, false, 0.01)
	_finish(true)


func _finish(was_skipped: bool) -> void:
	running = false
	_dim(false)
	if card != null:
		card.call("hide_now")
	if _board != null and _board_text != "":
		_board.text = _board_text
	for p in hide_paths:
		var n := get_node_or_null(p)
		if n != null and "visible" in n:
			n.set("visible", true)
	var fc := get_node_or_null(fight_camera_path) as Camera3D
	if fc != null:
		fc.make_current()
		if fc.has_method("snap"):
			fc.call("snap")
	_mark(-1, "finished")
	finished.emit(was_skipped)


func _one(i: int) -> void:
	var f: Dictionary = _fighters[i]
	var d: Doll = f["doll"]
	var side := -1.0 if i % 2 == 0 else 1.0
	_mark(i, "start")
	d.visible = true
	if _board != null:
		_board.text = String(f.get("name", tr("FIGHTER"))).to_upper()
	if card != null:
		card.call("show_fighter", f, i)
	var gate := _gate_pos(i)
	_frame_camera(gate + Vector3(-side * 2.0, 1.5, 0.0), gate)
	await _wait(Tuning.ENTRANCE_GATE_S * 0.5)
	if skipped:
		return
	_doors(i, true, Tuning.ENTRANCE_GATE_S / speed)
	_mark(i, "gate_open")
	await _wait(Tuning.ENTRANCE_GATE_S)
	if skipped:
		return
	# путь: из ворот к плоскости боя, потом вдоль пола сквозь мембрану внутрь
	var spawns: Array = arena.call("spawn_points") if arena.has_method("spawn_points") else []
	var inside: Vector3 = spawns[i] if i < spawns.size() else Vector3(side * 5.0, 2.5, 0.0)
	var field: Node = arena.get_node_or_null("Field")
	var edge_x := float(field.get("axes").x) if field != null else 16.0
	var p0 := _torso_pos(d)
	var p1 := Vector3(gate.x + (-side) * 1.5, inside.y, PLATFORM_Z)
	var p2 := Vector3(side * (edge_x - 1.2), inside.y, PLATFORM_Z)
	var released := false
	var t := 0.0
	var dur := Tuning.ENTRANCE_CARRY_S
	while t < dur and not skipped:
		await get_tree().physics_frame
		if skipped:
			return   # пропуск пришёл, пока ждали кадр: куклы уже на спавне — не двигать
		t += get_physics_process_delta_time() * speed
		var k := clampf(t / dur, 0.0, 1.0)
		var target := p0.lerp(p1, smoothstep(0.0, 1.0, k / 0.35)) if k < 0.35 else p1.lerp(p2, smoothstep(0.0, 1.0, (k - 0.35) / 0.65))
		_move_to(d, target)
		cam.global_position = cam.global_position.lerp(Vector3(target.x - side * 1.0, target.y + 1.2, 8.5), 0.12)
		cam.look_at(target + Vector3(0.0, 0.4, 0.0), Vector3.UP)
		if not released and field != null and field.has_method("stretch_at") \
				and float(field.call("stretch_at", Vector2(target.x, target.y))[0]) <= -0.6:
			released = true   # на 0.6 м внутри контура — отпустить: дальше несёт поле
			_release(d, side)
			_mark(i, "membrane")
	if skipped:
		return
	if not released:
		_release(d, side)
		_mark(i, "membrane")
	_doors(i, false, Tuning.ENTRANCE_GATE_S / speed)
	var hold := 0.0
	while hold < Tuning.ENTRANCE_HOLD_S and not skipped:
		await get_tree().physics_frame
		if skipped:
			return
		hold += get_physics_process_delta_time() * speed
		var c := _torso_pos(d)
		cam.global_position = cam.global_position.lerp(Vector3(c.x - side * 1.0, c.y + 1.2, 8.5), 0.08)
		cam.look_at(c + Vector3(0.0, 0.4, 0.0), Vector3.UP)
	_mark(i, "done")


func _release(d: Doll, side: float) -> void:
	_freeze(d, false)
	for rb in _bodies(d):
		(rb as RigidBody3D).linear_velocity = Vector3(-side * Tuning.ENTRANCE_RELEASE_SPEED, 0.6, 0.0)
	if arena.has_method("excite"):
		arena.call("excite", 0.8)
	var n0 := get_parent().get_node_or_null("N0")
	if n0 != null and n0.has_method("flash_expression"):
		n0.call("flash_expression", "excited", 1.5)


# --- куклы ---

## Тела куклы и оружия у неё в руках (WeaponPickup.held).
func _bodies(d: Doll) -> Array:
	var out: Array = []
	for rb in d.parts.values():
		if rb is RigidBody3D and is_instance_valid(rb):
			out.append(rb)
	var wp := d.get_node_or_null("WeaponPickup")
	if wp != null:
		for e in (wp.get("held") as Dictionary).values():
			var w: Node = (e as Dictionary).get("weapon")
			if w is RigidBody3D:
				out.append(w)
			if w != null:
				for c in w.find_children("*", "RigidBody3D", true, false):
					out.append(c)
	return out


func _freeze(d: Doll, on: bool) -> void:
	for rb in _bodies(d):
		var b := rb as RigidBody3D
		b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		b.freeze = on
		if not on:
			b.linear_velocity = Vector3.ZERO
			b.angular_velocity = Vector3.ZERO


func _torso_pos(d: Doll) -> Vector3:
	var t: Node3D = d.parts.get("Torso", null)
	if t == null and not d.parts.is_empty():
		t = d.parts.values()[0]
	return t.global_position if t != null else d.global_position


## Сдвинуть всю куклу (и оружие) так, чтобы торс оказался в target. Тела заморожены — позиции ставятся напрямую.
func _move_to(d: Doll, target: Vector3) -> void:
	var delta := target - _torso_pos(d)
	for rb in _bodies(d):
		(rb as Node3D).global_position += delta


func _place_at_gate(d: Doll, i: int) -> void:
	var g := _gate_pos(i)
	_move_to(d, Vector3(g.x, 1.4, g.z))


func _gate_pos(i: int) -> Vector3:
	var gate := arena.find_child(GATES[i % GATES.size()], true, false) as Node3D if arena != null else null
	if gate == null:
		return Vector3((-1.0 if i % 2 == 0 else 1.0) * 21.0, 0.0, -4.0)
	return gate.global_position


func _doors(i: int, open: bool, secs: float) -> void:
	var gate := arena.find_child(GATES[i % GATES.size()], true, false) as Node3D if arena != null else null
	if gate == null:
		return
	for pair in [["Gate_Door_L", 1.0], ["Gate_Door_R", -1.0]]:
		var door := gate.find_child(String(pair[0]), true, false) as Node3D
		if door == null:
			continue
		if not door.has_meta("closed_y"):
			door.set_meta("closed_y", door.rotation.y)
		var to := float(door.get_meta("closed_y")) + (deg_to_rad(DOOR_OPEN_DEG) * float(pair[1]) if open else 0.0)
		var tw := door.create_tween().set_ignore_time_scale(true)
		tw.tween_property(door, "rotation:y", to, maxf(secs, 0.01))


# --- свет, камера, время ---

func _dim(on: bool) -> void:
	for l in _lights.keys():
		if not is_instance_valid(l):
			continue
		var to: float = float(_lights[l]) * (Tuning.ENTRANCE_DIM_ENERGY if on else 1.0)
		var tw := (l as Node).create_tween().set_ignore_time_scale(true)
		tw.tween_property(l, "light_energy", to, Tuning.ENTRANCE_DIM_S)


func _frame_camera(pos: Vector3, look: Vector3) -> void:
	if cam == null:
		return
	cam.global_position = Vector3(pos.x, pos.y + 1.0, 8.5)
	cam.look_at(look + Vector3(0.0, 1.0, 0.0), Vector3.UP)


func _wait(secs: float) -> void:
	var t := 0.0
	while t < secs and not skipped:
		await get_tree().physics_frame
		t += get_physics_process_delta_time() * speed


func _physics_process(delta: float) -> void:
	if running:
		clock += delta


func _mark(i: int, step: String) -> void:
	timeline.append({"fighter": i, "step": step, "t": snappedf(clock, 0.01)})
