## Активные блоки (docs/plan-demo/ACTIVE_BLOCKS.md; лор — LORE_NULL.md «Заряд и три канала»): данные и правила, без состояния.
## Блок — деталь кита вида deco (tools/blender/kit_active.py; сливается с телом-хозяином, якоря Deco / Back / Top) с действием из DEFS.
## В чертеже у узла блока ключ "channel" = 1…3 — канал (клавиша), на котором он работает; несколько блоков на одном канале работают
## вместе и тратят заряд вместе. Пока клавиша канала зажата, блоки канала работают; заряд ядра — общий на бойца (ActiveRig):
## копится сам (CHARGE_REGEN) и от ударов (CHARGE_PER_DEALT за 1 HP урона ударом, CHARGE_PER_TAKEN — за полученный).
## Пассивы деталей лиги (PASSIVE) меняют заряд и здоровье без клавиш. Состояние в бою — scripts/active/active_rig.gd.
class_name ActiveBlocks
extends RefCounted

const CHANNELS := 3
const NODE_KEY := "channel"
const CHARGE_MAX := 100.0
const CHARGE_REGEN := 4.0            # заряда в секунду само
const CHARGE_PER_DEALT := 1.0        # заряда за 1 HP урона, нанесённого ударом (урон самих блоков заряд не даёт)
const CHARGE_PER_TAKEN := 0.4        # заряда за 1 HP полученного урона
const CHARGE_START := 1.0            # доля полного заряда на старте боя
const STUN_BLOCKS := true            # в стане каналы молчат (как остальное управление)

## Клавиши каналов (выбор автора 30.09): P1 — I / O / P, рядом на правой стороне клавиатуры (WASD, Shift, Space, E, ЛКМ, ПКМ заняты),
## P2 — цифры 1–3 на Numpad; геймпад игрока pN (устройство N − 1) — X, Y, правый курок.
const KEYS := {"p1": [KEY_I, KEY_O, KEY_P], "p2": [KEY_KP_1, KEY_KP_2, KEY_KP_3]}
const KEY_LABELS := {"p1": ["I", "O", "P"], "p2": ["Num1", "Num2", "Num3"]}
const PAD_LABELS := ["X", "Y", "RT"]

## id детали → действие и параметры. Точки (nozzles / muzzle) — в кадре детали: +Y — ось действия (на конечности — к кисти / стопе,
## на спине и макушке — вверх), +Z — к камере. cost — заряда в секунду, пока канал зажат (у пулемёта — за выстрел); use "press" —
## разовое действие по нажатию (cost_use за раз, cooldown с между), у крюка — выстрел по нажатию (cost_use) и тяга, пока зажато (cost).
const DEFS := {
	"kit_active_booster": {"action": "thrust", "title": "Ускоритель", "cost": 14.0, "force": 170.0,
		"nozzles": [Vector3(0.0, 0.0, 0.085)], "hint": "тянет конечность вдоль неё, к кисти / стопе"},
	"kit_active_jetpack": {"action": "thrust", "title": "Реактивный ранец", "cost": 22.0, "force": 300.0,
		"nozzles": [Vector3(0.17, -0.2, -0.05), Vector3(-0.17, -0.2, -0.05)], "hint": "на спине — тянет вверх, полёт"},
	"kit_active_flamer": {"action": "flame", "title": "Огнемёт", "cost": 20.0, "dps": 14.0, "range": 1.7, "cone_deg": 24.0,
		"push": 70.0, "muzzle": Vector3(0.0, 0.29, 0.095), "hint": "конус огня вдоль конечности: урон всем в конусе"},
	"kit_active_gun": {"action": "gun", "title": "Пулемёт", "cost": 2.0, "rate": 12.0, "damage": 1.5, "range": 14.0, "impulse": 5.0,
		"recoil": 2.5, "spread_deg": 3.0, "muzzle": Vector3(0.0, 0.28, 0.085), "hint": "очередь вдоль конечности, отдача назад"},
	"kit_active_magnet": {"action": "magnet", "title": "Магнит", "cost": 12.0, "force": 45.0, "radius": 3.0,
		"muzzle": Vector3(0.0, 0.22, 0.085), "hint": "тянет чужие детали из железа (сила × кг железа)"},
	"kit_active_league_gravity": {"action": "gravity", "title": "Гравиядро (лига)", "cost": 28.0, "accel": 6.0, "radius": 3.5,
		"muzzle": Vector3(0.0, 0.22, -0.05), "hint": "стягивает к себе чужих бойцов и оружие в радиусе"},
	"kit_active_league_shield": {"action": "shield", "title": "Энергощит (лига)", "cost": 20.0, "mult": 0.25,
		"muzzle": Vector3(0.0, 0.1, 0.085), "hint": "купол: входящий урон × 0.25"},
	"kit_active_league_phase": {"action": "phase", "title": "Фаза (лига)", "cost": 32.0,
		"muzzle": Vector3(0.0, 0.2, -0.05), "hint": "проходит сквозь чужих бойцов, урон не берёт"},
	"kit_active_league_repair": {"action": "repair", "title": "Самопочинка (лига)", "cost": 30.0, "hps": 8.0,
		"muzzle": Vector3(0.0, 0.16, -0.05), "hint": "заряд → здоровье"},
	# вторая волна (ACTIVE_BLOCKS.md v2)
	"kit_active_jet_boots": {"action": "thrust", "title": "Ранец для ног", "cost": 12.0, "force": 150.0, "sign": -1.0,
		"nozzles": [Vector3(0.0, 0.21, 0.1)], "hint": "выхлоп к стопе: тянет конечность к бедру — на ногах подскок и полёт"},
	"kit_active_grapple": {"action": "grapple", "title": "Крюк-кошка", "cost": 8.0, "cost_use": 6.0, "range": 9.0, "pull": 260.0,
		"muzzle": Vector3(0.0, 0.3, 0.085), "hint": "по нажатию — трос вдоль конечности; пока зажато — тянет к зацепу, зацепленного — к себе"},
	"kit_active_spring": {"action": "spring", "title": "Пружина-катапульта", "use": "press", "cost_use": 15.0, "cooldown": 0.8,
		"impulse": 60.0, "hit": 45.0, "damage": 6.0, "reach": 0.5, "muzzle": Vector3(0.0, 0.23, 0.085),
		"hint": "по нажатию — удар тарелкой вдоль конечности: кто перед ней — отлетает, бойца толкает назад"},
	"kit_active_smoke": {"action": "smoke", "title": "Дымовая шашка", "cost": 10.0, "radius": 1.4, "life": 5.0, "every": 0.3,
		"muzzle": Vector3(0.0, 0.16, -0.06), "hint": "облака дыма: боец в дыму невидим для ботов"},
	"kit_active_shock": {"action": "shock", "title": "Разрядник", "cost": 18.0, "dps": 12.0, "reach": 0.5, "stun": 0.12, "every": 0.2,
		"muzzle": Vector3(0.0, 0.245, -0.05), "hint": "бьёт током всех, кто вплотную: урон и короткий стан"},
	"kit_active_mine": {"action": "mine", "title": "Минный лоток", "use": "press", "cost_use": 25.0, "cooldown": 0.6, "max": 3,
		"arm_s": 0.8, "life": 12.0, "muzzle": Vector3(0.0, 0.23, 0.085), "hint": "по нажатию — мина; взводится за 0.8 с, рвётся от касания бойца (и своего)"},
	"kit_active_searchlight": {"action": "light", "title": "Прожектор", "cost": 6.0, "range": 7.0, "cone_deg": 18.0,
		"muzzle": Vector3(0.0, 0.18, 0.09), "hint": "луч вдоль конечности слепит ботов: целятся мимо"},
	"kit_active_anchor": {"action": "anchor", "title": "Тормоз-якорь", "cost": 10.0, "stiff": 400.0, "max_force": 2500.0,
		"muzzle": Vector3(0.0, 0.2, 0.085), "hint": "деталь стоит намертво там, где нажал: упор для удара или против отброса"},
}

## Пассивы деталей лиги (особые свойства без клавиш; LORE_NULL.md «одна цивилизация, но разная»).
const PASSIVE := {
	"kit_core_league_crystal": {"charge_max": 50.0, "hint": "энергокристалл копит заряд: +50 к запасу"},
	"kit_core_league_gyro": {"charge_regen": 3.0, "hint": "гироскоп раскручивает поле: +3 заряда в секунду"},
	"kit_core_league_orb": {"dealt_mult": 1.5, "hint": "око видит удар: заряд за нанесённый урон × 1.5"},
	"kit_core_league_flesh": {"hp_regen": 1.0, "hint": "живая ткань зарастает: +1 HP в секунду"},
	# наборы 04.10 (tools/blender/kit_pro.py, kit_aoe.py)
	"kit_core_pro_gyro": {"dealt_mult": 1.3, "hint": "маховик гиростаба раскручивается от ударов: заряд за нанесённый урон × 1.3"},
	"kit_core_pro_reactor": {"charge_max": 40.0, "hint": "реактор держит большой запас: +40 к заряду"},
	"kit_core_aoe_heart": {"hp_regen": 0.7, "hint": "живое сердце зарастает: +0.7 HP в секунду"},
}


## Дым и ослепление (действия smoke / light; их читают боты — ActiveRig.auto, EnemyBrain): зоны дыма [центр, радиус, до кадра физики],
## ослеплённые куклы: instance_id → до кадра физики.
static var smoke_zones: Array = []
static var blind_until: Dictionary = {}


static func add_smoke(pos: Vector3, radius: float, life_s: float) -> void:
	smoke_zones.append([pos, radius, Engine.get_physics_frames() + int(life_s * Engine.physics_ticks_per_second)])


## Кукла в дыму (ЦМ внутри живой зоны): боты её не видят, кроме как вплотную.
static func is_hidden(d: Doll) -> bool:
	if d == null or smoke_zones.is_empty():
		return false
	var now := Engine.get_physics_frames()
	smoke_zones = smoke_zones.filter(func(z: Array) -> bool: return int(z[2]) > now)
	var c := d.centre_of_mass()
	for z in smoke_zones:
		if c.distance_to(z[0]) <= float(z[1]):
			return true
	return false


static func blind(d: Doll, seconds: float) -> void:
	var until := Engine.get_physics_frames() + int(seconds * Engine.physics_ticks_per_second)
	blind_until[d.get_instance_id()] = maxi(int(blind_until.get(d.get_instance_id(), 0)), until)


## Кукла ослеплена прожектором: бот целится мимо (ошибка прицела ×4).
static func is_blinded(d: Doll) -> bool:
	return d != null and int(blind_until.get(d.get_instance_id(), 0)) > Engine.get_physics_frames()


static func is_press(d: Dictionary) -> bool:
	return String(d.get("use", "")) == "press"


static func is_active(part_id: String) -> bool:
	return DEFS.has(part_id)


static func def_of(part_id: String) -> Dictionary:
	return DEFS.get(part_id, {})


## Название активного блока на языке игрока (в DEFS — русский ключ перевода).
static func title_of(part_id: String) -> String:
	return String(TranslationServer.translate(String(def_of(part_id).get("title", part_id))))


## Описание активного блока на языке игрока.
static func hint_of(part_id: String) -> String:
	return String(TranslationServer.translate(String(def_of(part_id).get("hint", ""))))


## Описание пассива детали лиги на языке игрока ("" — пассива нет).
static func passive_hint(part_id: String) -> String:
	return String(TranslationServer.translate(String((PASSIVE.get(part_id, {}) as Dictionary).get("hint", ""))))


static func channel_of(n: Dictionary) -> int:
	var c := int(n.get(NODE_KEY, 0))
	return c if c >= 1 and c <= CHANNELS else 0


## Есть ли в чертеже что-то для ActiveRig: активный блок (даже без канала) или деталь с пассивом.
static func has_any(bp: BodyBlueprint) -> bool:
	if bp == null:
		return false
	for n in bp.nodes:
		var p := String(n.get("part", ""))
		if DEFS.has(p) or PASSIVE.has(p):
			return true
	return false


static func action_name(prefix: String, ch: int) -> String:
	return "%s_act%d" % [prefix, ch]


## Подпись клавиши канала для игрока (мастерская, подсказки).
static func key_label(prefix: String, ch: int) -> String:
	var ks: Array = KEY_LABELS.get(prefix, [])
	if ch >= 1 and ch <= ks.size():
		return String(ks[ch - 1])
	return PAD_LABELS[clampi(ch - 1, 0, 2)]


## Экшены pN_act1…3 (как ArmAssist.ensure_input_actions: создаются, только если их нет). Клавиатура — KEYS, геймпад игрока pN —
## устройство N − 1: X, Y, правый курок (ось, value 1).
static func ensure_input_actions() -> void:
	for pi in range(1, 5):
		var prefix := "p%d" % pi
		for ch in range(1, CHANNELS + 1):
			var a := action_name(prefix, ch)
			if InputMap.has_action(a):
				continue
			InputMap.add_action(a, 0.3)
			var keys: Array = KEYS.get(prefix, [])
			if ch <= keys.size():
				var k := InputEventKey.new()
				k.physical_keycode = keys[ch - 1]
				InputMap.action_add_event(a, k)
			if ch < 3:
				var b := InputEventJoypadButton.new()
				b.device = pi - 1
				b.button_index = JOY_BUTTON_X if ch == 1 else JOY_BUTTON_Y
				InputMap.action_add_event(a, b)
			else:
				var m := InputEventJoypadMotion.new()
				m.device = pi - 1
				m.axis = JOY_AXIS_TRIGGER_RIGHT
				m.axis_value = 1.0
				InputMap.action_add_event(a, m)
