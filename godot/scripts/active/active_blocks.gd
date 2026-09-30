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

## Клавиши каналов: P1 — Q / F / C (свободны в бою: WASD, Shift, Space, E, ЛКМ, ПКМ заняты), P2 — цифры 1–3 на Numpad; геймпад
## игрока pN (устройство N − 1) — X, Y, правый курок.
const KEYS := {"p1": [KEY_Q, KEY_F, KEY_C], "p2": [KEY_KP_1, KEY_KP_2, KEY_KP_3]}
const KEY_LABELS := {"p1": ["Q", "F", "C"], "p2": ["Num1", "Num2", "Num3"]}
const PAD_LABELS := ["X", "Y", "RT"]

## id детали → действие и параметры. Точки (nozzles / muzzle) — в кадре детали: +Y — ось действия (на конечности — к кисти / стопе,
## на спине и макушке — вверх), +Z — к камере. cost — заряда в секунду, пока канал зажат (у пулемёта — за выстрел).
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
}

## Пассивы деталей лиги (особые свойства без клавиш; LORE_NULL.md «одна цивилизация, но разная»).
const PASSIVE := {
	"kit_core_league_crystal": {"charge_max": 50.0, "hint": "энергокристалл копит заряд: +50 к запасу"},
	"kit_core_league_gyro": {"charge_regen": 3.0, "hint": "гироскоп раскручивает поле: +3 заряда в секунду"},
	"kit_core_league_orb": {"dealt_mult": 1.5, "hint": "око видит удар: заряд за нанесённый урон × 1.5"},
	"kit_core_league_flesh": {"hp_regen": 1.0, "hint": "живая ткань зарастает: +1 HP в секунду"},
}


static func is_active(part_id: String) -> bool:
	return DEFS.has(part_id)


static func def_of(part_id: String) -> Dictionary:
	return DEFS.get(part_id, {})


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
