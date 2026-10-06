## Площадка «Головоломки вдвоём (демо)» (docs/plan-demo/PUZZLE.md; автор 06.10: «физические головоломки: рычаги, двери, ящики на
## кнопки, вдвоём — посмотреть демо интересно»). Сцена scenes/playground_puzzle.tscn собирается tools/build_puzzle_demo.gd: шесть
## закрытых комнат (PuzzleRoom) в ряд по x, у каждой выходная дверь справа и тамбур за ней. Здесь — игроки, переходы, время, клавиши.
##   • Игроки: P1 — «Человек» (kit_human) с рукой мышью (ArmAssist: ЛКМ — рука к курсору, E — взять / отпустить, ЛКМ+E — бросок).
##     P2 входит первым нажатием своей клавиши (стрелки, правый Ctrl, Enter, «/», Num 0, геймпад 2) или клавишей U; U ещё раз — P2
##     уходит (соло). Рука P2 — клавиатура (PuzzleKeyArm: «/» или Num 0 — взять / положить / со стрелкой бросок) или геймпад (как везде).
##   • Комнаты: ЦМ любого игрока в тамбуре за открытой выходной дверью — комната пройдена, следующая; все игроки переносятся к её
##     точкам появления (что было в руке — отпускается). Последняя — итоги: общее время и время каждой комнаты.
##   • Камера — DynamicCamera с границами текущей комнаты (bounds()): кадр больше комнаты, поэтому стоит и показывает её целиком;
##     смена комнаты — быстрый проезд.
##   • Клавиши: R — комната заново (ящики и механизмы на места, игроки — к входу), [ / ] — предыдущая / следующая комната (для пробы),
##     U — P2, Esc — пауза (продолжить / заново / в гараж), M / N — музыка / толпа, H — скин HUD; после финиша Enter — с начала.
## Площадка — «арена» для Match и камеры: spawn_points() и bounds() — текущей комнаты.
class_name PuzzlePlayground
extends Node3D

signal room_changed(index: int)
signal room_solved(index: int, seconds: float)
signal demo_finished(total_s: float)
signal p2_changed(joined: bool)

const DOLL_SCENE := preload("res://scenes/body/modular_doll.tscn")
const BLUEPRINT := "res://data/body/blueprints/kit_human.tres"
const PLAYERS_GROUP := "players"
## ЦМ стоящей куклы над точкой появления (маркер — у ног), м.
const COM_LIFT := 1.0

## Комната на старте (пробы, отладка).
@export var start_room := 0
## P2 сразу в игре (пробы); обычно — с первого нажатия.
@export var p2_on_start := false
## Сам заходит ли P2 по первому нажатию своих клавиш (пробы выключают).
@export var auto_join := true

var rooms: Array[PuzzleRoom] = []
var current := 0
var total_time := 0.0
var room_time := 0.0
## Время каждой пройденной комнаты, с (по порядку).
var room_times: Array = []
var done := false
var p1: Doll
var p2: Doll
var _zoom_before := 1.0

@onready var match_node: PuzzleMatch = $Match
@onready var hud: PuzzleHud = $HUD
@onready var cam: DynamicCamera = $Camera
@onready var dolls_root: Node3D = $Dolls


func _enter_tree() -> void:
	_zoom_before = DynamicCamera.user_zoom
	DynamicCamera.user_zoom = 1.0


func _exit_tree() -> void:
	DynamicCamera.user_zoom = _zoom_before


func _ready() -> void:
	PuzzleKeyArm.ensure_action()
	var holder := get_node_or_null("Rooms")
	if holder != null:
		for c in holder.get_children():
			if c is PuzzleRoom:
				rooms.append(c)
	rooms.sort_custom(func(a: PuzzleRoom, b: PuzzleRoom) -> bool: return a.index < b.index)
	current = clampi(start_room, 0, maxi(rooms.size() - 1, 0))
	p1 = _spawn_player(0)
	if p2_on_start:
		join_p2()
	hud.bind(self)
	match_node.doll_replaced.connect(_on_doll_replaced)
	goto_room(current)
	cam.snap()


# --- арена для Match и камеры ---

func bounds() -> AABB:
	if rooms.is_empty():
		return AABB(Vector3(-9, -1, -1), Vector3(18, 11, 2))
	return rooms[current].bounds()


func spawn_points() -> Array[Vector3]:
	if rooms.is_empty():
		return [Vector3(-6, 0.45, 0), Vector3(-4.5, 0.45, 0)]
	return rooms[current].spawn_points()


func room() -> PuzzleRoom:
	return rooms[current] if not rooms.is_empty() else null


# --- игроки ---

## Кукла игрока i: «Человек», рубашка — цвет игрока, человек (ввод с клавиатуры / мыши / геймпада).
static func make_player(i: int) -> ModularDoll:
	var bp := (load(BLUEPRINT) as BodyBlueprint).duplicate(true) as BodyBlueprint
	bp.id = "puzzle_%d" % i
	var d := DOLL_SCENE.instantiate() as ModularDoll
	d.blueprint = bp
	d.name = "P%d" % (i + 1)
	d.player_index = i
	d.input_prefix = "p%d" % (i + 1)
	d.external_input = false
	d.add_to_group("dolls")
	d.add_to_group(PLAYERS_GROUP)
	return d


func _spawn_player(i: int) -> Doll:
	var d := make_player(i)
	var pts := spawn_points()
	d.position = pts[mini(i, pts.size() - 1)]
	dolls_root.add_child(d)
	ArmAssist.attach_to(d)
	PuzzleCarry.attach_to(d)
	if i == 1:
		PuzzleKeyArm.attach_to(d)
	match_node.register(d)
	return d


func players() -> Array:
	var out: Array = []
	for d in [p1, p2]:
		if d != null and is_instance_valid(d) and d.is_inside_tree():
			out.append(d)
	return out


func join_p2() -> void:
	if p2 != null and is_instance_valid(p2):
		return
	p2 = _spawn_player(1)
	p2_changed.emit(true)


func leave_p2() -> void:
	if p2 == null or not is_instance_valid(p2):
		p2 = null
		return
	var a := _arm(p2)
	if a != null:
		a.release("leave")
	dolls_root.remove_child(p2)
	p2.queue_free()
	p2 = null
	p2_changed.emit(false)


func _on_doll_replaced(old: Doll, new_doll: Doll) -> void:
	if old == p1:
		p1 = new_doll
	elif old == p2:
		p2 = new_doll


static func _arm(d: Doll) -> ArmAssist:
	if d == null or not is_instance_valid(d):
		return null
	for c in d.get_children():
		if c is ArmAssist and (c as ArmAssist).primary:
			return c
	return null


## Перенести куклу целиком (все детали) так, чтобы её ЦМ встал над точкой to (маркер у ног); скорости — ноль. Что в руке — отпускается.
func teleport(d: Doll, to: Vector3) -> void:
	var a := _arm(d)
	if a != null:
		a.release("room")
		a.clear_target_override()
	var shift := to + Vector3(0, COM_LIFT, 0) - d.centre_of_mass()
	shift.z = 0.0
	for p in d.parts.values():
		var b := p as RigidBody3D
		if b == null or not is_instance_valid(b):
			continue
		b.global_position += shift
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO


# --- комнаты ---

func goto_room(i: int) -> void:
	if rooms.is_empty():
		return
	current = clampi(i, 0, rooms.size() - 1)
	room_time = 0.0
	var pts := spawn_points()
	var k := 0
	for d in players():
		teleport(d, pts[mini(k, pts.size() - 1)])
		k += 1
	room_changed.emit(current)


## R: комната заново — пропсы и механизмы на места, игроки к входу.
func reset_room() -> void:
	var r := room()
	if r == null:
		return
	r.reset()
	var pts := spawn_points()
	var k := 0
	for d in players():
		teleport(d, pts[mini(k, pts.size() - 1)])
		k += 1


## С начала: все комнаты заново, время с нуля, первая комната.
func restart_demo() -> void:
	for r in rooms:
		r.reset()
	total_time = 0.0
	room_times.clear()
	done = false
	goto_room(0)
	hud.hide_end()


func _physics_process(delta: float) -> void:
	if done or rooms.is_empty():
		return
	total_time += delta
	room_time += delta
	var ex := rooms[current].exit_global()
	for d in players():
		var dd := d as Doll
		if not dd.alive:
			continue
		var c := dd.centre_of_mass()
		if ex.has_point(Vector2(c.x, c.y)):
			_advance()
			return


func _advance() -> void:
	room_times.append(room_time)
	room_solved.emit(current, room_time)
	if current >= rooms.size() - 1:
		done = true
		demo_finished.emit(total_time)
		return
	goto_room(current + 1)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_R:
				reset_room()
				hud.toast(tr("Комната заново"))
				return
			KEY_U:
				if p2 != null and is_instance_valid(p2):
					leave_p2()
					hud.toast(tr("P2 ушёл — играешь один"))
				else:
					join_p2()
					hud.toast(tr("P2 в игре: стрелки, рука — «/» или Num 0"))
				return
			KEY_BRACKETLEFT:
				if current > 0:
					goto_room(current - 1)
				return
			KEY_BRACKETRIGHT:
				if current < rooms.size() - 1:
					room_times.append(room_time)
					goto_room(current + 1)
				return
			KEY_ENTER, KEY_KP_ENTER:
				if done:
					restart_demo()
					return
			KEY_ESCAPE:
				Flow.toggle_pause(restart_demo)
				return
			KEY_M:
				hud.toast(get_node("/root/GameAudio").toggle_music())
				return
			KEY_N:
				hud.toast(get_node("/root/GameAudio").toggle_crowd())
				return
			KEY_H:
				hud.toast(tr("HUD: ") + HudSkin.cycle())
				return
	if auto_join and (p2 == null or not is_instance_valid(p2)) and event.is_pressed():
		for a in ["p2_left", "p2_right", "p2_up", "p2_down", "p2_dash", "p2_flip", "p2_grab", PuzzleKeyArm.ACTION]:
			if InputMap.has_action(a) and event.is_action(a):
				join_p2()
				hud.toast(tr("P2 в игре: стрелки, рука — «/» или Num 0"))
				return
