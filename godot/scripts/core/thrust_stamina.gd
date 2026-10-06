## Запас тяги (О4, docs/plan-demo/CLIMB.md, MODES_PACK.md «Общая основа»): полёт тратит запас, опора восполняет, при 0 тяги нет —
## только руки. Узел-ребёнок куклы; повесить — ThrustStamina.attach_to(doll). Без узла (все режимы, кроме пробы «Подъём») кукла летает
## как раньше: Doll.stamina = null, хук в тяге Doll._physics_process не делает ничего.
##
## Хук: Doll._physics_process зовёт gate(ввод, Shift, dt) до тяги — тратит запас и возвращает ввод, который пойдёт в тягу (ноль —
## запаса нет, выдохся или mute). Расход — Tuning.CLIMB_STAMINA_FLY_PER_S × |ввод| (с рывком — DASH_PER_S). Выдохся до нуля — тяга
## заперта, пока запас не вернётся до CLIMB_STAMINA_RESTART (не мерцает на нуле).
## Опора (_physics_process, после тяги куклы — узел-ребёнок идёт позже родителя): уступ (нога / голень / бедро / торс касается статики
## снизу: нормаль |y| ≥ CLIMB_LEDGE_NORMAL_Y, точка ниже центра детали) или руки на стене (ArmAssist.is_wall_holding() у детей куклы).
## Засчитывается, когда держится CLIMB_SUPPORT_HOLD_S подряд; после траты — пауза CLIMB_STAMINA_REGEN_PAUSE_S:
##   уступ — +LEDGE_PER_S; обе руки — +TWO_HANDS_PER_S; одна рука — ONE_HAND_PER_S (< 0, тает); в воздухе — не меняется.
## CLIMB_SLIP_AT_ZERO: одна рука, не на уступе и запас 0 — рука срывается (ArmAssist.wall_release("tired")).
## mute — тяга молчит без траты (руки P2 с клавиатуры: пока клавиша руки зажата, стрелки ведут руки, ClimbKeyHands).
class_name ThrustStamina
extends Node

const NODE_NAME := "ThrustStamina"
## Детали-опоры (базовое имя Doll.part_base_name).
const SUPPORT_PARTS := ["Foot", "LowerLeg", "UpperLeg", "Torso"]

var doll: Doll
var value: float = Tuning.CLIMB_STAMINA_MAX
var max_value: float = Tuning.CLIMB_STAMINA_MAX
## Запас кончился — тяга заперта до CLIMB_STAMINA_RESTART.
var locked := false
var mute := false
## Опора этого тика (для HUD и проб): "ledge" | "hands2" | "hand1" | "".
var support := ""
## Руки на стене в этом тике и стоит ли кукла на уступе.
var hands := 0
var on_ledge := false
## Тратит ли запас в этом тике (тяга шла).
var spending := false
## Счётчики для проб: потрачено / восполнено / растаяло на одной руке, сколько раз выдохся, сколько срывов «устал».
var spent_total := 0.0
var regen_total := 0.0
var drain_total := 0.0
var empty_count := 0
var slips := 0

var _time := 0.0
var _regen_at := 0.0
var _support_t := 0.0
var _support_kind := ""
var _spend_tick := -1


## Повесить запас на куклу (или вернуть уже висящий).
static func attach_to(d: Doll) -> ThrustStamina:
	var have := d.get_node_or_null(NODE_NAME) as ThrustStamina
	if have != null:
		return have
	var s := ThrustStamina.new()
	s.name = NODE_NAME
	d.add_child(s)
	return s


func _ready() -> void:
	doll = get_parent() as Doll
	if doll == null:
		push_error("ThrustStamina must be a child of Doll")
		return
	doll.stamina = self
	_watch_contacts()


func _exit_tree() -> void:
	if doll != null and is_instance_valid(doll) and doll.stamina == self:
		doll.stamina = null


## Полный бак (старт, рестарт).
func refill() -> void:
	value = max_value
	locked = false
	_regen_at = _time


## Доля запаса 0..1 (HUD).
func frac() -> float:
	return clampf(value / maxf(max_value, 1.0), 0.0, 1.0)


## Хук тяги (Doll._physics_process): ввод v → что пойдёт в тягу; тратит запас за этот тик.
func gate(v: Vector2, boost: bool, delta: float) -> Vector2:
	if mute:
		return Vector2.ZERO
	var mag := minf(v.length(), 1.0)
	if mag < 0.01:
		return v
	if locked or value <= 0.0:
		return Vector2.ZERO
	var rate := (Tuning.CLIMB_STAMINA_DASH_PER_S if boost else Tuning.CLIMB_STAMINA_FLY_PER_S) * mag
	var spent := minf(value, rate * delta)
	value -= spent
	spent_total += spent
	_regen_at = _time + Tuning.CLIMB_STAMINA_REGEN_PAUSE_S
	_spend_tick = Engine.get_physics_frames()
	if value <= 0.0:
		value = 0.0
		locked = true
		empty_count += 1
	return v


func _physics_process(delta: float) -> void:
	_time += delta
	if doll == null or not is_instance_valid(doll):
		return
	spending = _spend_tick == Engine.get_physics_frames()
	hands = 0
	var holders: Array = []
	for c in doll.get_children():
		if c is ArmAssist and (c as ArmAssist).is_wall_holding():
			hands += 1
			holders.append(c)
	on_ledge = doll.alive and _ledge_contact()
	var kind := "ledge" if on_ledge else ("hands2" if hands >= 2 else ("hand1" if hands == 1 else ""))
	if kind != _support_kind:
		_support_kind = kind
		_support_t = 0.0
	else:
		_support_t += delta
	support = kind if _support_t >= Tuning.CLIMB_SUPPORT_HOLD_S else ""
	if not doll.alive or spending:
		return
	var rate := 0.0
	match support:
		"ledge":
			rate = Tuning.CLIMB_STAMINA_LEDGE_PER_S
		"hands2":
			rate = Tuning.CLIMB_STAMINA_TWO_HANDS_PER_S
		"hand1":
			rate = Tuning.CLIMB_STAMINA_ONE_HAND_PER_S
	if rate > 0.0 and _time >= _regen_at and value < max_value:
		var add := minf(max_value - value, rate * delta)
		value += add
		regen_total += add
	elif rate < 0.0 and value > 0.0:
		var sub := minf(value, -rate * delta)
		value -= sub
		drain_total += sub
		if value <= 0.0:
			value = 0.0
			locked = true
			empty_count += 1
	if locked and value >= Tuning.CLIMB_STAMINA_RESTART:
		locked = false
	if Tuning.CLIMB_SLIP_AT_ZERO and value <= 0.0 and hands == 1 and not on_ledge:
		for a in holders:
			(a as ArmAssist).wall_release("tired")
		slips += 1


## Детали-опоры шлют контакты (contact_monitor): DollCombat включает их у стоп, голеней и торса; бёдра — здесь.
func _watch_contacts() -> void:
	for b in doll.parts.values():
		var rb := b as RigidBody3D
		if rb == null or not SUPPORT_PARTS.has(Doll.part_base_name(String(rb.name))):
			continue
		if not rb.contact_monitor:
			rb.contact_monitor = true
		rb.max_contacts_reported = maxi(rb.max_contacts_reported, 4)


## Касается ли нога / голень / бедро / торс статики снизу (уступ, пол).
func _ledge_contact() -> bool:
	for b in doll.parts.values():
		var rb := b as RigidBody3D
		if rb == null or not is_instance_valid(rb) or not SUPPORT_PARTS.has(Doll.part_base_name(String(rb.name))):
			continue
		var st := PhysicsServer3D.body_get_direct_state(rb.get_rid())
		if st == null:
			continue
		var centre_y := rb.global_position.y + st.center_of_mass.y
		for i in st.get_contact_count():
			var other := st.get_contact_collider_object(i)
			if not (other is StaticBody3D or other is AnimatableBody3D):
				continue
			var n := st.get_contact_local_normal(i)
			if absf(n.y) < Tuning.CLIMB_LEDGE_NORMAL_Y:
				continue
			if st.get_contact_local_position(i).y < centre_y:
				return true
	return false
