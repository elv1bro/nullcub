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
}
const ORDER := ["pin", "free", "spring", "motor", "weld"]
## Радиус шара коннектора по группе сустава (м), если у якоря нет meta joint_r.
const RADIUS := {"Neck": 0.05, "Shoulder": 0.064, "Elbow": 0.054, "Wrist": 0.044, "Hip": 0.076, "Knee": 0.066, "Ankle": 0.052}
const CONNECTOR_DIR := "res://scenes/body/kit/connectors/"


static func is_type(t: String) -> bool:
	return TYPES.has(t)


static func info(t: String) -> Dictionary:
	return TYPES.get(t if t != "" else DEFAULT, TYPES[DEFAULT])


static func is_weld(t: String) -> bool:
	return bool(info(t).get("fixed", false))


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
