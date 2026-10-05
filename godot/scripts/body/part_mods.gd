## Модули — пассивные детали со свойствами (docs/plan-demo/WORKSHOP_V4.md «Модули»; автор 05.10: «что-то будет давать, а что-то
## тормозить» → «делаем все детали вместе»). Деталь вида deco (модели — tools/blender/kit_mods.py) сливается с телом-хозяином, как
## декор и активные блоки, и работает всегда, без клавиши. У каждого модуля есть плюс и цена (масса, энергия и свой минус).
##
## Как доходит до боя (ModularDoll._build): свойства модулей, слитых с телом, складываются (combine) в meta "mods" тела; у сервопривода
## и амортизатора (chain) свойства ещё и спускаются на всё, что висит на хозяине (рука ниже серво тоже «серво»). Читают:
##   • тело — PartMods.of(тело, ключ): ArmAssist (pull_mult), ModularDoll._update_pair_gains (muscle_mult), Doll._part_linear_damp
##     (drag_add, drag_mult), DollCombat._deliver (stun_mult), Doll._init_joint_hp (break_mult), Doll.take_damage (wear_mult и
##     self_wear бьющего тела), Doll.detach_part (blast); bounce и hit_mult ModularDoll вписывает в физматериал и meta body_mult,
##     frail — в meta "frail" (Damage.armor_mult_of_body); броня паруса — обычная строка Tuning.PART_ARMOR;
##   • вся кукла — totals(ModularDoll): charge_bonus (Doll.charge_cap и заряд активных блоков), spin_mult / spin_cost_mult /
##     knock_spin_mult (Doll: раскрутка и отброс), repair_per_s (ModularDoll._physics_process).
## Свой урон в износ (wear_mult, self_wear, repair_per_s, break_mult) работает там, где детали изнашиваются: «Запас из деталей» («;»)
## и «Прочность суставов» (C). Остальное — в любом бою.
class_name PartMods
extends RefCounted

## id детали → свойства. Ключи: множители (MULT — перемножаются), прибавки (ADD — складываются), bounce — большее.
const DEFS := {
	"kit_mod_servo": {"pull_mult": 1.6, "muscle_mult": 0.7, "chain": true,
		"hint": "тяга этой руки к курсору × 1.6; без тяги рука вялее"},
	"kit_mod_battery": {"charge_bonus": 30.0, "blast": 0.5,
		"hint": "+30 к запасу Заряда; оторвали деталь с батареей — взрыв, бьёт и по тебе"},
	"kit_mod_sail": {"drag_add": 3.0,
		"hint": "броня 0.3 на этой детали; в воздухе тормозит — разгон и скорость ниже"},
	"kit_mod_flywheel": {"spin_mult": 1.6, "spin_cost_mult": 0.6, "knock_spin_mult": 0.5,
		"hint": "раскрутка сильнее и дешевле, удары меньше крутят; тяжёлый — разворот медленнее"},
	"kit_mod_bumper": {"bounce": 0.8, "hit_mult": 0.8,
		"hint": "отскок от стен и пола сильнее; удар этой деталью мягче × 0.8"},
	"kit_mod_fairing": {"drag_mult": 0.6, "frail": 0.15,
		"hint": "воздух меньше тормозит — скорость выше; тонкая жесть: урон в эту деталь × 1.15"},
	"kit_mod_damper": {"stun_mult": 0.6, "break_mult": 1.5, "muscle_mult": 0.65, "chain": true,
		"hint": "оглушение от ударов в эту ветку × 0.6, деталь труднее оторвать × 1.5; конечность мягче"},
	"kit_mod_repair": {"repair_per_s": 2.0,
		"hint": "чинит износ деталей, 2 в секунду; запас бойца не лечит"},
	"kit_mod_grinder": {"wear_mult": 1.6, "self_wear": 0.3,
		"hint": "удар этой деталью изнашивает чужую деталь × 1.6; своя тоже стирается (30 % урона)"},
}
const MULT := ["pull_mult", "muscle_mult", "spin_mult", "spin_cost_mult", "knock_spin_mult", "hit_mult", "drag_mult", "stun_mult",
	"break_mult", "wear_mult"]
const ADD := ["charge_bonus", "blast", "drag_add", "frail", "repair_per_s", "self_wear"]
## Свойства, которые спускаются по цепочке от хозяина ко всему, что на нём висит (у модулей с "chain").
const CHAIN_KEYS := ["pull_mult", "muscle_mult", "stun_mult"]
## Свойства всей куклы (totals) — где бы модуль ни стоял.
const DOLL_KEYS := ["charge_bonus", "spin_mult", "spin_cost_mult", "knock_spin_mult", "repair_per_s"]
const META := "mods"


static func is_mod(part_id: String) -> bool:
	return DEFS.has(part_id)


static func def_of(part_id: String) -> Dictionary:
	return DEFS.get(part_id, {})


## Сложить свойства модуля d в накопитель acc (новый словарь): множители перемножаются, прибавки складываются, отскок — больший.
static func combine(acc: Dictionary, d: Dictionary) -> Dictionary:
	var out := acc.duplicate()
	for k in d:
		if MULT.has(k):
			out[k] = float(out.get(k, 1.0)) * float(d[k])
		elif ADD.has(k):
			out[k] = float(out.get(k, 0.0)) + float(d[k])
		elif k == "bounce":
			out[k] = maxf(float(out.get(k, 0.0)), float(d[k]))
	return out


## Свойство ниже по цепочке: берётся сильнейшее из своего и хозяйского (два серво на одной руке не дают ×2.56 кисти).
static func chain_merge(own: Dictionary, from_host: Dictionary) -> Dictionary:
	var out := own.duplicate()
	for k in CHAIN_KEYS:
		if not from_host.has(k):
			continue
		var v := float(from_host[k])
		var o := float(out.get(k, 1.0))
		out[k] = maxf(o, v) if v >= 1.0 else minf(o, v)
	return out


## Значение свойства key тела b (meta "mods"); нет — def (1 у множителей, 0 у прибавок).
static func of(b: Object, key: String, def: float = NAN) -> float:
	var d := def if not is_nan(def) else (1.0 if MULT.has(key) else 0.0)
	if b == null or not is_instance_valid(b) or not b.has_meta(META):
		return d
	return float((b.get_meta(META) as Dictionary).get(key, d))


## Свойства всей куклы по её телам (свой модуль на каждом теле — один раз, без спуска по цепочке).
static func totals(bodies: Array) -> Dictionary:
	var t := {}
	for b in bodies:
		if b == null or not is_instance_valid(b) or not (b as Object).has_meta("mods_own"):
			continue
		var own: Dictionary = (b as Object).get_meta("mods_own")
		for k in DOLL_KEYS:
			if own.has(k):
				t = combine(t, {k: own[k]})
	return t
