## Головы «Охоты за головами» (docs/plan-demo/HEADHUNT.md): отрыв головы у выбитого, головы на полу, подбор касанием, стопка голов на
## спине носителя, рассыпание, сдача в корзину. Узел — ребёнок HeadhuntMatch; правила очков — в матче (deliver), здесь — тела и касания.
##   • extract(victim) — после KO (Doll.knock_out уже порвал суставы) голова (RigidBody3D «Head») выносится из куклы в узел Heads
##     площадки: группа HEADS_GROUP, meta owner_team (чья команда) и drop_until (до этого времени матча брать нельзя — разлетается);
##     из Doll.parts и мониторов DollCombat вычёркивается (кукла вот-вот пересоздастся — Match.respawn_doll освободит старую без головы);
##   • loose() — головы на полу; carried(doll) — на спине; tick(delta) каждый тик боя: любая деталь живой куклы ближе
##     Tuning.HEADHUNT_PICK_M к лежащей голове — подбор (до HEADHUNT_CARRY_MAX), носитель с головами коснулся своей корзины
##     (HeadBasket.point(), ближе HEADHUNT_BASKET_M) — HeadhuntMatch.deliver;
##   • на спине: голова заморожена (freeze, коллизия выключена) и переставлена в HeadStack носителя — узел без интерполяции, который в
##     _process идёт за видимым торсом (как бомба BombCarry), головы стопкой за спиной; тяга носителя × HEADHUNT_CARRY_THRUST за голову;
##   • scatter(doll) — выбили носителя: головы снова на полу с разлётом HEADHUNT_DROP_SPEED и запретом подбора HEADHUNT_DROP_LOCK_S;
##   • rescue(head) — голова упала в страховочный низ арены: возвращается сверху над серединой (HEADHUNT_RESCUE).
## Журнал для проб: picks, drops, extracted.
class_name HeadCarry
extends Node

const HEADS_GROUP := "heads"
const HEADS_NODE := "Heads"
const STACK_OFFSET := Vector3(0.0, -0.02, -0.3)   # первая голова: за спиной торса (кукла смотрит в камеру +Z)
const STACK_STEP := 0.3

## Стопка голов на спине носителя: следует за торсом по видимому положению, головы — её дети.
class HeadStack extends Node3D:
	var carrier: Doll = null
	var heads: Array = []

	func _init() -> void:
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	func follow() -> void:
		if carrier == null or not is_instance_valid(carrier) or not carrier.parts.has("Torso"):
			return
		var t := carrier.torso()
		global_transform = t.get_global_transform_interpolated() * Transform3D(Basis.IDENTITY, STACK_OFFSET)

	func _process(_delta: float) -> void:
		follow()

var match_node: Node = null
var picks := 0
var drops := 0
var extracted := 0
var _stacks: Dictionary = {}   # Doll → HeadStack
var _rng := RandomNumberGenerator.new()


func bind(m: Node) -> void:
	match_node = m
	_rng.randomize()


func _root() -> Node3D:
	var parent := match_node.get_parent() if match_node != null else get_parent()
	if parent == null:
		return null
	var n := parent.get_node_or_null(HEADS_NODE) as Node3D
	if n == null:
		n = Node3D.new()
		n.name = HEADS_NODE
		parent.add_child(n)
	return n


func _now() -> float:
	return float(match_node.get("fight_time")) if match_node != null else 0.0


# --- головы ---

## Все головы (на полу и на спинах), живые тела.
func all_heads() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group(HEADS_GROUP):
		if is_instance_valid(n) and not (n as Node).is_queued_for_deletion():
			out.append(n)
	return out


## Головы на полу (не на спине).
func loose() -> Array:
	var out: Array = []
	for h in all_heads():
		if not (h as Node).has_meta("carrier"):
			out.append(h)
	return out


## Головы на спине d (пустой массив — нет).
func carried(d: Doll) -> Array:
	var s: HeadStack = _stacks.get(d) as HeadStack if d != null else null
	if s == null or not is_instance_valid(s):
		return []
	return s.heads.duplicate()


func carry_count(d: Doll) -> int:
	return carried(d).size()


static func owner_team(h: Node) -> int:
	return int(h.get_meta("owner_team", -1)) if h != null and is_instance_valid(h) else -1


## Голову можно взять (не на спине, запрет после падения прошёл).
func pickable(h: Node) -> bool:
	return is_instance_valid(h) and not h.has_meta("carrier") and _now() >= float(h.get_meta("drop_until", 0.0))


## Вынести голову выбитой куклы из неё в узел Heads: группа heads, владелец — её команда. Возвращает тело или null (головы нет).
func extract(victim: Doll, team: int) -> RigidBody3D:
	if victim == null or not is_instance_valid(victim) or not victim.is_inside_tree():
		return null
	var head := victim.parts.get("Head") as RigidBody3D
	if head == null or not is_instance_valid(head) or head.get_parent() != victim:
		return null
	var root := _root()
	if root == null:
		return null
	var rest: Array = []
	for p in victim.parts.values():
		if p != head and is_instance_valid(p):
			rest.append(p)
	victim.parts.erase("Head")
	for con in head.body_entered.get_connections():   # мониторы DollCombat мёртвой куклы (как Doll.detach_part)
		var cal: Callable = con["callable"]
		var o: Object = cal.get_object()
		if o != null and o.has_method("_on_part_contact"):
			head.body_entered.disconnect(cal)
	for c in victim.get_children():
		var mon: Variant = c.get("_monitored")
		if mon is Array:
			(mon as Array).erase(head)
	var xf := head.global_transform
	var lv := head.linear_velocity
	var av := head.angular_velocity
	victim.remove_child(head)
	head.name = "Head_%d_%d" % [victim.player_index, extracted]
	root.add_child(head)
	head.global_transform = xf
	head.linear_velocity = lv
	head.angular_velocity = av
	head.reset_physics_interpolation()
	head.set_meta("owner_team", team)
	head.set_meta("owner_index", victim.player_index)
	head.set_meta("drop_until", _now() + Tuning.HEADHUNT_DROP_LOCK_S)
	head.add_to_group(HEADS_GROUP)
	extracted += 1
	# исключения коллизий со своими деталями снимаются чуть позже (в точке сустава тела перекрываются — Jolt растолкал бы их)
	get_tree().create_timer(0.25).timeout.connect(func() -> void:
		if not is_instance_valid(head):
			return
		for p in rest:
			if is_instance_valid(p):
				head.remove_collision_exception_with(p))
	return head


func _stack_for(d: Doll) -> HeadStack:
	var s: HeadStack = _stacks.get(d) as HeadStack
	if s != null and is_instance_valid(s):
		return s
	s = HeadStack.new()
	s.name = "Stack_%d" % d.player_index
	s.carrier = d
	add_child(s)
	_stacks[d] = s
	s.follow()
	return s


func _apply_thrust(d: Doll) -> void:
	if d != null and is_instance_valid(d):
		d.thrust_mult = pow(Tuning.HEADHUNT_CARRY_THRUST, carry_count(d))


## Кукла d берёт голову h на спину.
func pick(d: Doll, h: RigidBody3D) -> bool:
	if d == null or h == null or not is_instance_valid(h) or not d.alive or h.has_meta("carrier"):
		return false
	if carry_count(d) >= Tuning.HEADHUNT_CARRY_MAX:
		return false
	var s := _stack_for(d)
	h.set_meta("carrier", d)
	h.set_meta("layer", h.collision_layer)
	h.set_meta("mask", h.collision_mask)
	h.collision_layer = 0
	h.collision_mask = 0
	h.linear_velocity = Vector3.ZERO
	h.angular_velocity = Vector3.ZERO
	h.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	h.freeze = true
	h.get_parent().remove_child(h)
	s.add_child(h)
	h.position = Vector3(0.0, STACK_STEP * float(s.heads.size()), 0.0)
	h.rotation = Vector3.ZERO
	h.reset_physics_interpolation()
	s.heads.append(h)
	picks += 1
	_apply_thrust(d)
	if match_node != null and match_node.has_signal("head_picked"):
		match_node.emit_signal("head_picked", h, d)
	return true


## Голова h снова на полу в точке at со скоростью v.
func _release(h: RigidBody3D, at: Vector3, v: Vector3) -> void:
	var root := _root()
	if root == null or not is_instance_valid(h):
		return
	if h.get_parent() != null:
		h.get_parent().remove_child(h)
	root.add_child(h)
	h.global_transform = Transform3D(Basis.IDENTITY, Vector3(at.x, at.y, 0.0))
	h.freeze = false
	h.collision_layer = int(h.get_meta("layer", 1))
	h.collision_mask = int(h.get_meta("mask", 1))
	h.remove_meta("carrier")
	h.set_meta("drop_until", _now() + Tuning.HEADHUNT_DROP_LOCK_S)
	h.linear_velocity = v
	h.angular_velocity = Vector3(0.0, 0.0, _rng.randf_range(-4.0, 4.0))
	h.reset_physics_interpolation()
	drops += 1


## Выбили носителя: все его головы рассыпаются вокруг.
func scatter(d: Doll) -> Array:
	var s: HeadStack = _stacks.get(d) as HeadStack
	var out: Array = []
	if s == null or not is_instance_valid(s):
		_stacks.erase(d)
		return out
	var base := s.global_position
	if d != null and is_instance_valid(d) and d.parts.has("Torso"):
		base = d.torso().global_position
	for h in s.heads:
		if not is_instance_valid(h):
			continue
		var ang := _rng.randf_range(0.35, PI - 0.35)
		var sp := _rng.randf_range(Tuning.HEADHUNT_DROP_SPEED.x, Tuning.HEADHUNT_DROP_SPEED.y)
		_release(h, base + Vector3(cos(ang) * 0.3, 0.25, 0.0), Vector3(cos(ang) * sp, sin(ang) * sp, 0.0))
		out.append(h)
	s.heads.clear()
	_stacks.erase(d)
	s.queue_free()
	_apply_thrust(d)
	return out


## Сдать головы носителя d: тела освобождаются; возвращает их команды-владельцы (матч считает очки).
func take_all(d: Doll) -> Array:
	var s: HeadStack = _stacks.get(d) as HeadStack
	var teams: Array = []
	if s == null or not is_instance_valid(s):
		_stacks.erase(d)
		return teams
	for h in s.heads:
		if is_instance_valid(h):
			teams.append(owner_team(h))
			(h as Node).remove_from_group(HEADS_GROUP)
			(h as Node).queue_free()
	s.heads.clear()
	_stacks.erase(d)
	s.queue_free()
	_apply_thrust(d)
	return teams


## Голова упала в страховочный низ — наверх над серединой.
func rescue(h: RigidBody3D) -> void:
	if h == null or not is_instance_valid(h) or h.has_meta("carrier"):
		return
	var r: Vector2 = Tuning.HEADHUNT_RESCUE
	h.global_transform = Transform3D(Basis.IDENTITY, Vector3(_rng.randf_range(-r.x, r.x), r.y, 0.0))
	h.linear_velocity = Vector3.ZERO
	h.angular_velocity = Vector3.ZERO
	h.reset_physics_interpolation()


## Все головы и стопки прочь (заново / конец).
func clear() -> void:
	for h in all_heads():
		(h as Node).remove_from_group(HEADS_GROUP)
		(h as Node).queue_free()
	for d in _stacks.keys():
		var s: HeadStack = _stacks[d] as HeadStack
		if s != null and is_instance_valid(s):
			s.queue_free()
		if d != null and is_instance_valid(d):
			(d as Doll).thrust_mult = 1.0
	_stacks.clear()


# --- касания ---

## Тик боя: подбор лежащих голов касанием, сдача в свою корзину.
func tick(_delta: float) -> void:
	if match_node == null:
		return
	var alive: Array = match_node.call("alive_dolls")
	var r2 := Tuning.HEADHUNT_PICK_M * Tuning.HEADHUNT_PICK_M
	for h in loose():
		if not pickable(h):
			continue
		var hp := (h as Node3D).global_position
		var best: Doll = null
		var best_d2 := r2
		for d in alive:
			var dd := d as Doll
			if not dd.is_inside_tree() or carry_count(dd) >= Tuning.HEADHUNT_CARRY_MAX:
				continue
			if dd.centre_of_mass().distance_squared_to(hp) > 9.0:
				continue
			for p in dd.parts.values():
				if not is_instance_valid(p):
					continue
				var d2 := (p as Node3D).global_position.distance_squared_to(hp)
				if d2 <= best_d2:
					best_d2 = d2
					best = dd
		if best != null:
			pick(best, h)
	var b2 := Tuning.HEADHUNT_BASKET_M * Tuning.HEADHUNT_BASKET_M
	for d in alive:
		var dd := d as Doll
		if carry_count(dd) == 0 or not dd.is_inside_tree():
			continue
		var basket: Node = match_node.call("basket_of", match_node.call("team_of", dd))
		if basket == null:
			continue
		var bp: Vector3 = basket.call("point")
		if dd.centre_of_mass().distance_squared_to(bp) > 12.0:
			continue
		for p in dd.parts.values():
			if is_instance_valid(p) and (p as Node3D).global_position.distance_squared_to(bp) <= b2:
				match_node.call("deliver", dd)
				break
