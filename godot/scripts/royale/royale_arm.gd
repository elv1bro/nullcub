## Рука с оружием «Королевской битвы» (docs/plan-demo/ROYALE.md; MODES_PACK.md §2 «Риски из стычки»: в стычке синие держат ствол в
## левой, красные — в правой, и одна рука не достаёт целей с «чужой» стороны кадра; в битве враг с любой стороны). Наследник SquadArm:
## ствол перекладывается в руку со стороны цели руки (игрок — курсор, бот — цель; площадка и мозг ставят её через set_target_override):
## цель правее торса больше чем на Tuning.ROYALE_HAND_DEADBAND_M — кисть Hand_L (кукла смотрит в камеру: её левая — справа на экране),
## левее — Hand_R. Переклад: прежняя рука отпускается (поза — назад), управление — на другую кисть (control_part + _rebind: цепь и IK
## заново), ствол молчит Tuning.ROYALE_HAND_SWAP_S (SquadGun.cooldown), следующий — не раньше ROYALE_HAND_SWAP_GAP_S. Модель ствола и
## точка вылета пули сами идут за рукой (SquadGun берёт кисть у ArmAssist). Руку с оружием оторвало (прочность суставов) — ствол сразу во
## вторую. auto_switch = false — рука как в стычке (проба прицела сравнивает).
class_name RoyaleArm
extends SquadArm

const HAND_SCREEN_RIGHT := "Hand_L"
const HAND_SCREEN_LEFT := "Hand_R"

var auto_switch := true
## Перекладов за жизнь куклы (пробы).
var swaps := 0
var _swap_t := -10.0


func _physics_process(delta: float) -> void:
	_auto_hand()
	super._physics_process(delta)


## Кисть по стороне цели; оторвана — другая.
func _auto_hand() -> void:
	if not auto_switch or not _ready_done or doll == null or not doll.alive or doll.is_broken():
		return
	if part_name != "" and not doll.parts.has(part_name):
		var other := HAND_SCREEN_LEFT if part_name == HAND_SCREEN_RIGHT else HAND_SCREEN_RIGHT
		if doll.parts.has(other):
			switch_to(other)
		return
	if not _override_active or _time - _swap_t < Tuning.ROYALE_HAND_SWAP_GAP_S:
		return
	var t := doll.torso()
	if t == null:
		return
	var dx := _override_target.x - t.global_position.x
	var want := part_name
	if dx > Tuning.ROYALE_HAND_DEADBAND_M:
		want = HAND_SCREEN_RIGHT
	elif dx < -Tuning.ROYALE_HAND_DEADBAND_M:
		want = HAND_SCREEN_LEFT
	if want != part_name and doll.parts.has(want):
		switch_to(want)


## Управление — на кисть name: прежняя отпускает предмет и позу, цепь и IK собираются заново; ствол молчит ROYALE_HAND_SWAP_S.
func switch_to(name_: String) -> bool:
	if name_ == part_name or not doll.parts.has(name_):
		return false
	if held != null:
		release("switch")
	if part != null and is_instance_valid(part):
		_set_flex(false)
	arm_active = false
	control_part = name_
	_rebind()
	_swap_t = _time
	swaps += 1
	var g := SquadMatch.gun_of(doll)
	if g != null:
		g.cooldown = maxf(g.cooldown, Tuning.ROYALE_HAND_SWAP_S)
		g.charge = 0.0
	return part != null


## Кисть на экране справа (Hand_L) или слева (Hand_R) — для HUD и проб.
func screen_side() -> float:
	return 1.0 if part_name == HAND_SCREEN_RIGHT else -1.0
