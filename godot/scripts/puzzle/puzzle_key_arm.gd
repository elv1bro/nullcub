## Рука P2 с клавиатуры (docs/plan-demo/PUZZLE.md «Клавиши»): у второго игрока за той же клавиатурой мыши нет, а рука ArmAssist у P2
## ведётся только геймпадом (правый стик + RB). Этот узел — ребёнок куклы P2 рядом с её ArmAssist; ставит его только площадка
## головоломок (PuzzlePlayground), в других режимах рука P2 прежняя. Рукой управляет через открытый вход ArmAssist для ботов и проб
## (set_target_override / clear_target_override / press_grab) — сам ArmAssist не меняется.
##   • Клавиша хвата — действие p2_grab_kb: «/» (рядом с правым Shift и стрелками) и Num 0. Правый Shift занят: KEY_SHIFT без стороны —
##     рывок P1 (input_setup.gd), он сработал бы и у P1.
##   • Пусто в руке, нажал — рука тянется к ближнему хватаемому (ArmAssist.can_grab) в сторону зажатых стрелок (без стрелок — просто
##     к ближнему) в круге досягаемости + Tuning.PUZZLE_KEY_REACH_EXTRA_M и хватает, как только кисть достала (кандидат ArmAssist), но
##     не дольше Tuning.PUZZLE_KEY_REACH_S. Рядом ничего — обычное нажатие (подсказка «слишком тяжело», своя оторванная деталь).
##   • С предметом: стрелки зажаты — рука держит предмет на PUZZLE_KEY_HOLD_FRAC досягаемости в их сторону (несёшь «перед собой»),
##     клавиша со стрелками — бросок в их сторону (ArmAssist бросает к цели активной руки); без стрелок — рука не активна, предмет
##     висит, клавиша — положить (отпустить без броска).
##   • Геймпад P2 по-прежнему: правый стик или RB — узел снимает свою цель и не мешает; подпись над предметом — снова «RB».
## Стрелки читаются физическими клавишами (не действиями p2_left…: в них и левый стик геймпада P2).
## Для проб: press() — как нажатие клавиши; arrows_override — стрелки вместо клавиатуры (Vector2, null — клавиатура).
class_name PuzzleKeyArm
extends Node

const ACTION := "p2_grab_kb"
const KEYS := [KEY_SLASH, KEY_KP_0]
const NODE_NAME := "PuzzleKeyArm"

var doll: Doll
var arm: ArmAssist
## Последнее действие (для проб): "reach" | "grab" | "throw" | "drop" | "press" | "".
var last_action := ""
var reach_target: RigidBody3D = null
var arrows_override: Variant = null

var _time := 0.0
var _reach_until := -1.0
var _overriding := false
var _press_req := false
var _pad_used := false
static var _actions_done := false


static func ensure_action() -> void:
	if _actions_done and InputMap.has_action(ACTION):
		return
	_actions_done = true
	if InputMap.has_action(ACTION):
		return
	InputMap.add_action(ACTION, 0.5)
	for k in KEYS:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(ACTION, e)


## Повесить на куклу (рядом с её ArmAssist), если ещё нет.
static func attach_to(d: Doll) -> PuzzleKeyArm:
	var have := d.get_node_or_null(NODE_NAME) as PuzzleKeyArm
	if have != null:
		return have
	var k := PuzzleKeyArm.new()
	k.name = NODE_NAME
	d.add_child(k)
	return k


func _ready() -> void:
	ensure_action()
	doll = get_parent() as Doll


## Как нажатие клавиши хвата (срабатывает в ближайшем физическом тике).
func press() -> void:
	_press_req = true


func _find_arm() -> ArmAssist:
	if arm != null and is_instance_valid(arm):
		return arm
	arm = null
	if doll == null:
		return null
	for c in doll.get_children():
		if c is ArmAssist and (c as ArmAssist).primary:
			arm = c
			break
	return arm


## Стрелки (физические клавиши) → единичный вектор или ноль.
func arrows() -> Vector2:
	if arrows_override is Vector2:
		var o: Vector2 = arrows_override
		return o.normalized() if o.length() > 0.01 else Vector2.ZERO
	var v := Vector2(
		float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_DOWN)))
	return v.normalized() if v.length() > 0.01 else Vector2.ZERO


## Геймпад P2 в деле: правый стик отклонён или RB зажат — клавиатурная рука уступает.
func _pad_active() -> bool:
	if doll == null:
		return false
	var p := doll.input_prefix
	if not InputMap.has_action(p + "_arm_left"):
		return false
	var s := Input.get_vector(p + "_arm_left", p + "_arm_right", p + "_arm_down", p + "_arm_up")
	return s.length() > ArmAssist.STICK_DEADZONE or Input.is_action_pressed(p + "_grab")


func _physics_process(delta: float) -> void:
	_time += delta
	var a := _find_arm()
	if a == null or doll == null or not doll.alive or a.part == null or not is_instance_valid(a.part):
		_drop_override()
		_press_req = false
		return
	var pressed := _press_req
	_press_req = false
	if not doll.external_input and doll.control_enabled and InputMap.has_action(ACTION) and Input.is_action_just_pressed(ACTION):
		pressed = true
	if _pad_active():
		_pad_used = true
		_reach_until = -1.0
		_drop_override()
		_hint_keys(a)
		return
	if pressed:
		_pad_used = false
	_hint_keys(a)
	var dir := arrows()
	if a.is_holding():
		_reach_until = -1.0
		reach_target = null
		if dir != Vector2.ZERO:
			a.set_target_override(a.root_point() + Vector3(dir.x, dir.y, 0.0) * a.reach * Tuning.PUZZLE_KEY_HOLD_FRAC)
			_overriding = true
		else:
			_drop_override()
		if pressed:
			last_action = "throw" if a.arm_active else "drop"
			a.press_grab()
		return
	if pressed:
		var c := best_candidate(dir)
		if c == null:
			last_action = "press"
			a.press_grab()
		else:
			reach_target = c
			_reach_until = _time + Tuning.PUZZLE_KEY_REACH_S
			last_action = "reach"
	if _reach_until > _time and reach_target != null and is_instance_valid(reach_target) and a.can_grab(reach_target):
		var cp := a.closest_point(reach_target, a.grip_global())
		a.set_target_override(cp)
		_overriding = true
		if a.grip_global().distance_to(cp) <= ArmAssist.GRAB_RADIUS * 0.9:
			a.press_grab()
			last_action = "grab"
			_reach_until = -1.0
		return
	_reach_until = -1.0
	reach_target = null
	_drop_override()


func _drop_override() -> void:
	if _overriding and arm != null and is_instance_valid(arm):
		arm.clear_target_override()
	_overriding = false


## Подпись над предметом: «/» и «стрелки», пока P2 не взялся за геймпад.
func _hint_keys(a: ArmAssist) -> void:
	var key := "" if _pad_used else "/"
	if a.hint_grab_key != key:
		a.hint_grab_key = key
		a.hint_aim = "" if _pad_used else tr("стрелки")


## Лучший предмет для руки: хватаемый (ArmAssist.can_grab), ближняя точка в круге досягаемости + запас; со стрелками — только те, что
## в их сторону (косинус между стрелками и направлением от плеча ≥ DIR_MIN_COS; таких нет — все), счёт — расстояние от кисти минус
## Tuning.PUZZLE_KEY_DIR_BIAS × косинус (без стрелок — только расстояние).
func best_candidate(dir: Vector2) -> RigidBody3D:
	var best := _best(dir, true)
	return best if best != null or dir == Vector2.ZERO else _best(dir, false)


const DIR_MIN_COS := 0.3


func _best(dir: Vector2, cone: bool) -> RigidBody3D:
	var a := _find_arm()
	if a == null or a.part == null or not a.part.is_inside_tree():
		return null
	var space := a.part.get_world_3d().direct_space_state
	var root := a.root_point()
	var r := a.reach + Tuning.PUZZLE_KEY_REACH_EXTRA_M
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = r
	q.shape = sph
	q.transform = Transform3D(Basis.IDENTITY, root)
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var ex: Array[RID] = []
	for p in doll.parts.values():
		if is_instance_valid(p):
			ex.append((p as RigidBody3D).get_rid())
	q.exclude = ex
	var grip := a.grip_global()
	var best: RigidBody3D = null
	var best_s := INF
	for hit in space.intersect_shape(q, 32):
		var b := hit.get("collider") as RigidBody3D
		if b == null or not a.can_grab(b):
			continue
		var cp := a.closest_point(b, grip)
		var from_root := Vector2(cp.x - root.x, cp.y - root.y)
		if from_root.length() > r:
			continue
		var s := grip.distance_to(cp)
		if dir != Vector2.ZERO and from_root.length() > 0.05:
			var cosv := dir.dot(from_root.normalized())
			if cone and cosv < DIR_MIN_COS:
				continue
			s -= Tuning.PUZZLE_KEY_DIR_BIAS * cosv
		if s < best_s:
			best_s = s
			best = b
	return best
