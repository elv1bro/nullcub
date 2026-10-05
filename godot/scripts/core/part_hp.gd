## Запас из деталей — пробный режим (docs/plan-demo/WORKSHOP_V4.md; автор 05.10: «каждая деталь даёт общее HP, у детали своё HP — кончилось,
## отрывается; ядро и голова дают базовый разгон и энергию, любая деталь его уменьшает весом; голова оторвана — KO»). Клавиша «;» в бою
## (HitJuice) и в мастерской включает и выключает; выключен — игра как раньше. Состояние общее на все площадки (как JointBreak), на диск
## не пишется. Числа — Tuning.PARTHP_*.
##   • ❤ детали — hp_of(масса тела, прочность материала); запас бойца — Doll.parts_hp_total(), ставит Match в начале раунда;
##   • порог отрыва — break_hp(❤): копит тот же механизм, что у «Прочности суставов» (Doll.joint_hp / _wear_joint), отрыв уносит ❤ поддерева;
##   • энергия и тяга сборки — energy_of_core / energy_of_head, thrust_of_core / thrust_n (BodyBlueprint.energy_cap, ModularDoll.thrust_mass).
class_name PartHp
extends RefCounted

static var on: bool = Tuning.PARTHP_DEFAULT


static func set_on(v: bool) -> void:
	on = v


static func toggle() -> bool:
	on = not on
	return on


static func title() -> String:
	return TranslationServer.translate("Запас из деталей") + ": " + TranslationServer.translate("вкл" if on else "выкл")


## Множитель материала по прочности (Damage.part_durability, 0…1): дерево 0.5 → 1.0, железо 1.0 → 1.33, ткань 0.3 → 0.87.
static func mat_factor(durability: float) -> float:
	return (1.0 + durability) / 1.5


## ❤ детали: масса тела (кг, со слитыми щитками и декором) × PARTHP_PER_KG × mat_factor, вверх до целого (у «Человека» Σ ровно 100),
## не меньше PARTHP_MIN.
static func hp_of(mass_kg: float, durability: float) -> int:
	return maxi(_up(maxf(mass_kg, 0.0) * Tuning.PARTHP_PER_KG * mat_factor(durability)), int(Tuning.PARTHP_MIN))


static func _up(x: float) -> int:
	return ceili(x - 0.001)   # 4.0000001 от плавающей точки — 4, а не 5


## Сколько ❤ прибавит деталь без своего тела (декор, броня, сварка): её масса уходит в тело-хозяина — без минимума PARTHP_MIN.
static func hp_added_of(mass_kg: float, durability: float) -> int:
	return _up(maxf(mass_kg, 0.0) * Tuning.PARTHP_PER_KG * mat_factor(durability))


## ❤ детали с полки мастерской (одна, без сборки): своя масса и материал; fixed-виды — прибавка к хозяину (hp_added_of).
static func hp_of_part(d: PartDef, mat_id: String = "") -> int:
	if d == null:
		return 0
	var dur := Damage.part_durability(d, mat_id)
	return hp_added_of(d.mass, dur) if PartDef.FIXED_KINDS.has(d.kind) or d.attach == "fixed" else hp_of(d.mass, dur)


## Сколько урона деталь с ❤ part_hp выдержит, прежде чем оторваться (голова — свой множитель).
static func break_hp(part_hp: float, is_head: bool = false) -> float:
	var k := Tuning.PARTHP_HEAD_BREAK_MULT if is_head else Tuning.PARTHP_BREAK_MULT
	return maxf(part_hp * k, Tuning.PARTHP_BREAK_MIN)


## Энергия, которую даёт ядро / голова: по базовой массе детали (PartDef.mass, без материала — железное ядро не даёт втрое больше).
static func energy_of_core(d: PartDef) -> int:
	return roundi(d.mass * Tuning.PARTHP_CORE_ENERGY_PER_KG) if d != null else 0


static func energy_of_head(d: PartDef) -> int:
	return roundi(d.mass * Tuning.PARTHP_HEAD_ENERGY_PER_KG) if d != null else 0


## Мотор ядра, Н: Tuning.PARTHP_CORE_THRUST по id, иначе PARTHP_CORE_THRUST_N.
static func thrust_of_core(d: PartDef) -> float:
	return float(Tuning.PARTHP_CORE_THRUST.get(d.id, Tuning.PARTHP_CORE_THRUST_N)) if d != null else Tuning.PARTHP_CORE_THRUST_N


## Тяга сборки, Н: мотор ядра core + голова (у всех голов одна — PARTHP_HEAD_THRUST_N). Разгон = тяга / масса сборки.
static func thrust_n(core: PartDef = null, has_head: bool = true) -> float:
	return thrust_of_core(core) + (Tuning.PARTHP_HEAD_THRUST_N if has_head else 0.0)
