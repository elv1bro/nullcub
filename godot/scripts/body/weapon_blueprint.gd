## Чертёж крафтового оружия (docs/plan-demo/BODY_CRAFT.md §4): рукоять → головка → моды, цепь — свободные шарниры.
## nodes — как у BodyBlueprint ({uid, part, parent, anchor, rest_deg?}); корень — деталь вида handle.
## Собирается в CraftedWeapon (extends Weapon): fixed-детали сливаются в одно тело, chain — отдельные тела.
class_name WeaponBlueprint
extends Resource

@export var id := ""
@export var title := "":
	get:
		# в .tres лежит русский ключ перевода; " *" — пометка «не сохранено» мастерской (CraftEdit), её не переводим
		return tr(title.trim_suffix(" *")) + (" *" if title.ends_with(" *") else "")
@export var nodes: Array[Dictionary] = []


func root_node() -> Dictionary:
	for n in nodes:
		if String(n.get("parent", "")) == "":
			return n
	return {}


func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	var root := root_node()
	if root.is_empty():
		errors.append(tr("нет корня (рукояти)"))
	else:
		var d := BodyBlueprint.part_def(String(root.get("part", "")))
		if d == null or d.kind != "handle":
			errors.append(tr("корень оружия должен быть рукоятью"))
	var uids := {}
	for n in nodes:
		uids[String(n.get("uid", ""))] = true
		if BodyBlueprint.part_def(String(n.get("part", ""))) == null:
			errors.append(tr("нет детали «%s»") % n.get("part", ""))
	for n in nodes:
		var p := String(n.get("parent", ""))
		if p != "" and not uids.has(p):
			errors.append(tr("у «%s» нет родителя «%s»") % [n.get("uid", ""), p])
	return errors
