## Типы шарниров кита тела v2 (docs/plan-demo/BODY_KIT.md §5.2): ключ узла чертежа "joint" описывает связь узла с родителем
## (нет ключа — "pin"). Меняет мышцу сустава (ModularDoll._update_pair_gains: k, tmax ×; c × √k-множителя), трение (force_limit
## мотора-трения × friction), лимиты и визуал коннектора; weld — узел сливается с родителем, как fixed-деталь.
class_name KitJoint
extends RefCounted

const DEFAULT := "pin"
const TYPES := {
	"pin": {"title": "Ось", "hint": "обычный сустав: мышца тянет в позу", "k": 1.0, "tmax": 1.0, "friction": 1.0,
		"limits": "group", "energy": 0, "connector": "pin"},
	"free": {"title": "Свободный", "hint": "болтается без мышцы — кистень, хлыст", "k": 0.0, "tmax": 0.0, "friction": 0.3,
		"limits": Vector2(-160, 160), "energy": 0, "connector": "free"},
	"spring": {"title": "Пружина", "hint": "мягкая мышца, шире ход — пружинит и раскачивается", "k": 0.45, "tmax": 0.6,
		"friction": 0.5, "limits": "group+20", "energy": 2, "connector": "spring"},
	"motor": {"title": "Мотор", "hint": "сильная мышца: держит тяжёлое, резче бьёт", "k": 1.8, "tmax": 2.2, "friction": 1.3,
		"limits": "group", "energy": 8, "connector": "motor"},
	"weld": {"title": "Сварка", "hint": "намертво: деталь становится частью родителя", "fixed": true, "energy": 0,
		"connector": ""},
	# на связке (06.10, WORKSHOP_V4.md «Деталь на связке»): деталь со всем, что на ней, висит на родителе через связку KitLink длиной
	# tether_len — сустава и мышцы нет; энергия — связка по длине (KitLink.energy_of) и вынос всей ветки дальше от ядра
	"on_rope": {"title": "На тросе", "hint": "висит на тросе: кистень — дай ей тягу и крути мышью", "tether": "rope", "k": 0.0,
		"lens": [0.3, 0.6, 0.9, 1.2], "energy": 0, "connector": ""},
	"on_bar": {"title": "На тяге", "hint": "на жёсткой тяге с шарнирами: молот на длинной рукояти", "tether": "bar", "k": 0.0,
		"lens": [0.3, 0.6, 0.9, 1.2], "energy": 0, "connector": ""},
	"on_spring": {"title": "На пружине", "hint": "на пружине: отскакивает и бьёт с оттяжкой", "tether": "spring", "k": 0.0,
		"lens": [0.3, 0.5, 0.7, 0.9], "energy": 0, "connector": ""},
	"on_piston": {"title": "На поршне", "hint": "на поршне: выстреливает по клавише канала (I)", "tether": "piston", "k": 0.0,
		"lens": [0.3, 0.5, 0.7, 0.9], "energy": 0, "connector": ""},
}
const ORDER := ["pin", "free", "spring", "motor", "weld", "on_rope", "on_bar", "on_spring", "on_piston"]
## Ключ узла чертежа: длина связки у детали «на связке», м (нет ключа — вторая из lens типа).
const TETHER_KEY := "tether_len"
## Радиус шара коннектора по группе сустава (м), если у якоря нет meta joint_r.
const RADIUS := {"Neck": 0.05, "Shoulder": 0.064, "Elbow": 0.054, "Wrist": 0.044, "Hip": 0.076, "Knee": 0.066, "Ankle": 0.052}
const CONNECTOR_DIR := "res://scenes/body/kit/connectors/"


static func is_type(t: String) -> bool:
	return TYPES.has(t)


## Запись типа: title / hint тут русские ключи перевода — игроку их показывают через title_of / hint_of (или tr в месте показа).
static func info(t: String) -> Dictionary:
	return TYPES.get(t if t != "" else DEFAULT, TYPES[DEFAULT])


## Название типа шарнира на языке игрока.
static func title_of(t: String) -> String:
	return String(TranslationServer.translate(String(info(t).get("title", t))))


## Подсказка к типу шарнира на языке игрока.
static func hint_of(t: String) -> String:
	return String(TranslationServer.translate(String(info(t).get("hint", ""))))


static func is_weld(t: String) -> bool:
	return bool(info(t).get("fixed", false))


## Деталь висит на родителе через связку (on_rope / on_bar / on_spring / on_piston), а не на суставе.
static func is_tether(t: String) -> bool:
	return info(t).has("tether")


## Вид связки KitLink у типа «на связке» ("" — не такой тип).
static func tether_link(t: String) -> String:
	return String(info(t).get("tether", ""))


static func tether_lens(t: String) -> Array:
	return info(t).get("lens", [0.6])


## Длина связки узла n (ключ TETHER_KEY, иначе вторая длина типа).
static func tether_len_of(n: Dictionary) -> float:
	var t := String(n.get("joint", ""))
	var lens := tether_lens(t)
	return float(n.get(TETHER_KEY, lens[mini(1, lens.size() - 1)]))


static func energy_of(t: String) -> int:
	return int(info(t).get("energy", 0))


## Лимиты сустава по типу: group_lim — лимиты группы (ModularDoll._limits_for), в градусах.
static func limits(t: String, group_lim: Vector2) -> Vector2:
	var l: Variant = info(t).get("limits", "group")
	if l is Vector2:
		return l
	if String(l) == "group+20":
		return Vector2(group_lim.x - 20.0, group_lim.y + 20.0)
	return group_lim


static func connector_scene(t: String) -> String:
	var c := String(info(t).get("connector", ""))
	return "" if c == "" else CONNECTOR_DIR + c + ".tscn"


static func radius_for(group: String) -> float:
	return float(RADIUS.get(group, 0.05))
