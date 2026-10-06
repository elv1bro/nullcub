## Руки P2 с клавиатуры в пробе «Подъём» (docs/plan-demo/CLIMB.md): у второго игрока за той же клавиатурой мыши нет. Ребёнок куклы P2
## рядом с двумя её ArmAssist (wall_grip); ставит только ClimbMatch.rig, в других режимах рука P2 прежняя. Руками управляет через
## открытый вход ArmAssist (set_target_override / clear_target_override) — сама рука не меняется.
##   • [ — левая рука на экране (Hand_R, как ЛКМ у P1), ] — правая (Hand_L, как ПКМ). Держишь клавишу — рука тянется и хватается за
##     камень; отпустил — отпустил стену (как кнопка мыши у P1).
##   • Пока зажата хоть одна клавиша руки, стрелки ведут руки, а не тягу (ThrustStamina.mute — запас не тратится):
##     свободная рука — к плечу + стрелки × досягаемость; без стрелок — к ближнему камню в досягаемости + CLIMB_KEY_REACH_EXTRA_M
##     (выше — лучше, CLIMB_KEY_UP_BIAS); держащая рука — грудь тянется в сторону стрелок (подтягивание), без стрелок — висит.
##   • Отпустил обе клавиши — стрелки снова тяга.
## Почему [ и ]: рядом со стрелками свободных клавиш нет — «/» фоторежим, «.» и «,» масштаб, «;» запас из деталей, «'» панель ВИД,
## правый Shift — тот же KEY_SHIFT, что рывок P1; у ноутбука автора нет цифрового блока. Геймпад P2 — как везде (стик ведёт руку).
## Для проб: keys_override = [левая, правая] (bool), arrows_override = Vector2 (null — клавиатура).
class_name ClimbKeyHands
extends Node

const NODE_NAME := "ClimbKeyHands"
const ACTIONS := ["p2_climb_hand_l", "p2_climb_hand_r"]
const KEYS := [KEY_BRACKETLEFT, KEY_BRACKETRIGHT]
## Тела рук по порядку клавиш: левая на экране — Hand_R (кукла смотрит на камеру), правая — Hand_L.
const HAND_PARTS := ["Hand_R", "Hand_L"]

var doll: Doll
var keys_override: Variant = null
var arrows_override: Variant = null
## Клавиши этого тика (для HUD и проб).
var held := [false, false]

var _overriding := [false, false]
static var _actions_done := false


static func ensure_actions() -> void:
	if _actions_done:
		return
	_actions_done = true
	for i in ACTIONS.size():
		if InputMap.has_action(ACTIONS[i]):
			continue
		InputMap.add_action(ACTIONS[i], 0.5)
		var e := InputEventKey.new()
		e.physical_keycode = KEYS[i]
		InputMap.action_add_event(ACTIONS[i], e)


static func attach_to(d: Doll) -> ClimbKeyHands:
	var have := d.get_node_or_null(NODE_NAME) as ClimbKeyHands
	if have != null:
		return have
	var k := ClimbKeyHands.new()
	k.name = NODE_NAME
	d.add_child(k)
	return k


func _ready() -> void:
	ensure_actions()
	doll = get_parent() as Doll
	process_physics_priority = -1   # раньше тяги куклы и рук: mute и цели рук — в том же тике, что нажатие


## Руки куклы по порядку клавиш (null — нет такой).
func arms() -> Array:
	var out: Array = [null, null]
	if doll == null:
		return out
	for c in doll.get_children():
		if c is ArmAssist and (c as ArmAssist).wall_grip:
			var i := HAND_PARTS.find((c as ArmAssist).part_name)
			if i >= 0:
				out[i] = c
	return out


func arrows() -> Vector2:
	if arrows_override is Vector2:
		var o: Vector2 = arrows_override
		return o.normalized() if o.length() > 0.01 else Vector2.ZERO
	var v := Vector2(
		float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_DOWN)))
	return v.normalized() if v.length() > 0.01 else Vector2.ZERO


func _keys() -> Array:
	if keys_override is Array:
		return [bool(keys_override[0]), bool(keys_override[1])]
	if doll == null or doll.external_input or not doll.control_enabled:
		return [false, false]
	return [Input.is_action_pressed(ACTIONS[0]), Input.is_action_pressed(ACTIONS[1])]


func _physics_process(_delta: float) -> void:
	if doll == null or not is_instance_valid(doll):
		return
	var a := arms()
	held = _keys() if doll.alive else [false, false]
	var any: bool = held[0] or held[1]
	if doll.stamina != null:
		doll.stamina.mute = any
	var dir := arrows()
	for i in 2:
		var arm := a[i] as ArmAssist
		if arm == null or arm.part == null or not is_instance_valid(arm.part):
			continue
		if not held[i]:
			if _overriding[i]:
				arm.clear_target_override()
				_overriding[i] = false
			continue
		var tgt: Vector3
		if arm.is_wall_holding():
			tgt = arm.chest_point() + Vector3(dir.x, dir.y, 0.0)
		elif dir != Vector2.ZERO:
			tgt = arm.root_point() + Vector3(dir.x, dir.y, 0.0) * arm.reach
		else:
			tgt = best_hold(arm)
		arm.set_target_override(tgt)
		_overriding[i] = true


## Ближняя точка камня для свободной руки без стрелок: в досягаемости + запас, выше плеча — лучше; нет камня — вверх на досягаемость.
func best_hold(arm: ArmAssist) -> Vector3:
	var root := arm.root_point()
	var up := root + Vector3.UP * arm.reach
	if arm.part == null or not arm.part.is_inside_tree():
		return up
	var space := arm.part.get_world_3d().direct_space_state
	var r := arm.reach + Tuning.CLIMB_KEY_REACH_EXTRA_M
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
	var best := up
	var best_s := INF
	var aim := root + Vector3.UP * arm.reach * Tuning.CLIMB_KEY_UP_BIAS   # ближняя точка камня к точке над плечом — тянемся вверх
	for hit in space.intersect_shape(q, 24):
		var b := hit.get("collider") as CollisionObject3D
		if b == null or not ArmAssist.is_climbable(b):
			continue
		var cp := ArmAssist._static_closest(b, int(hit.get("shape", 0)), aim)
		cp.z = 0.0
		if cp.distance_to(root) > r:
			continue
		var s := cp.distance_to(aim)
		if s < best_s:
			best_s = s
			best = cp
	return best
