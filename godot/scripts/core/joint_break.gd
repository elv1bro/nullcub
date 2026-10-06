## Прочность суставов — пробный режим (docs/plan-demo/JOINT_BREAK.md; автор 04.10: «при ударах суставы имеют прочность и может
## отвалиться рука, нога или ещё что; чем дальше от центра, тем сустав меньше HP имеет»). Клавиша C в бою (HitJuice) включает и
## выключает; выключен — игра как раньше. Состояние общее на все площадки и переживает смену арены (как Drive), на диск не пишется.
##   • запас сустава — по глубине от ядра: hp_for_depth (Tuning.JOINT_HP_BASE × JOINT_HP_FALLOFF^(глубина − 1), не ниже JOINT_HP_MIN);
##   • запас тратит урон в деталь, которая на суставе висит: Doll.take_damage → wear(); кончился — Doll.detach_part;
##   • сами запасы лежат в кукле (Doll.joint_hp / joint_hp_max / joint_depth, ключ — имя детали), сигнал Doll.joint_broken.
class_name JointBreak
extends RefCounted

static var on: bool = Tuning.JOINT_BREAK_DEFAULT


## Один механизм отрыва — два режима сразу не ведём: включили «Прочность суставов» — «Запас из деталей» (PartHp, стандарт с 06.10) гаснет.
static func set_on(v: bool) -> void:
	on = v
	if on:
		PartHp.on = false


static func toggle() -> bool:
	set_on(not on)
	return on


static func title() -> String:
	return TranslationServer.translate("Прочность суставов") + ": " + TranslationServer.translate("вкл" if on else "выкл")


## Запас сустава на глубине depth от ядра (1 — сустав на самом ядре: плечо, бедро; 2 — локоть, колено; 3 — запястье, лодыжка).
static func hp_for_depth(depth: int) -> float:
	return maxf(Tuning.JOINT_HP_BASE * pow(Tuning.JOINT_HP_FALLOFF, maxi(depth, 1) - 1), Tuning.JOINT_HP_MIN)


## Износ сустава от урона dealt (HP, реально снятые с куклы) в деталь part_name. Блок кистью (TargetMult < 1) режет HP, но не
## износ: запястье получает удар целиком — как отброс в DollCombat._deliver.
static func wear(dealt: float, part_name: String) -> float:
	var tm := Damage.target_mult_of(part_name)
	return (dealt / tm if tm > 0.0 and tm < 1.0 else dealt) * Tuning.JOINT_WEAR_MULT
