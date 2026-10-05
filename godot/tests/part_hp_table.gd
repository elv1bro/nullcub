## Таблица «запаса из деталей» (PartHp, docs/plan-demo/WORKSHOP_V4.md) по всем пресетам: ❤, энергия, разгон — для калибровки чисел.
##   godot --headless --path godot res://tests/part_hp_table.tscn
## В stdout — «=== PART HP TABLE ===», строки и JSON. Проверок нет (проба — tests/part_hp_probe.tscn).
extends Node3D

const PRESETS := "res://scenes/body/presets/"
const DOLL := "res://scenes/doll/doll.tscn"


func _row(path: String) -> Dictionary:
	var d := (load(path) as PackedScene).instantiate() as Doll
	d.external_input = true
	add_child(d)
	var r := {"id": path.get_file().get_basename(), "mass": snappedf(d.total_mass, 0.1), "bodies": d.parts.size(), "hp": d.parts_hp_total()}
	var bp: BodyBlueprint = d.get("blueprint") as BodyBlueprint
	if bp != null:
		var was := PartHp.on
		PartHp.set_on(false)
		r["e_old"] = "%d/%d" % [bp.energy_used(), bp.energy_budget]
		PartHp.set_on(true)
		r["e_new"] = "%d/%d" % [bp.energy_used(), bp.energy_cap()]
		r["over"] = bp.energy_used() > bp.energy_cap()
		r["thrust_kg"] = (d as ModularDoll).thrust_mass()
		PartHp.set_on(false)
		r["thrust_kg_old"] = (d as ModularDoll).thrust_mass()
		PartHp.set_on(was)
		for n in bp.nodes:
			var pd := BodyBlueprint.part_def(String(n["part"]))
			if pd != null and pd.kind == "core" and String(n.get("parent", "")) == "":
				r["core"] = "%s %.0f" % [pd.id.trim_prefix("kit_core_"), pd.mass]
			elif pd != null and pd.kind == "head":
				r["head"] = "%s %.1f" % [pd.id.trim_prefix("kit_head_"), pd.mass]
	else:
		r["thrust_kg"] = d.total_mass
		r["thrust_kg_old"] = d.total_mass
	r["acc_old"] = snappedf(float(r["thrust_kg_old"]) / d.total_mass, 0.01)
	r["acc_new"] = snappedf(float(r["thrust_kg"]) / d.total_mass, 0.01)
	var hp_by := {}
	for n in d.part_hp:
		hp_by[n] = d.part_hp[n]
	r["parts"] = hp_by
	d.queue_free()
	return r


func _ready() -> void:
	var rows: Array = [_row(DOLL)]
	var files := DirAccess.get_files_at(PRESETS)
	files.sort()
	for f in files:
		if f.ends_with(".tscn"):
			rows.append(_row(PRESETS + f))
	print("=== PART HP TABLE ===")
	print("%-15s %6s %4s %5s  %-11s %-11s %-18s %-14s %5s %5s" % ["id", "кг", "тел", "❤", "⚡ сейчас", "⚡ режим", "ядро", "голова", "разг", "разг*"])
	for r in rows:
		print("%-15s %6.1f %4d %5.0f  %-11s %-11s %-18s %-14s %5.2f %5.2f%s" % [r["id"], r["mass"], r["bodies"], r["hp"], r.get("e_old", "-"),
			r.get("e_new", "-"), r.get("core", "-"), r.get("head", "-"), r["acc_old"], r["acc_new"], "  ПЕРЕРАСХОД" if r.get("over", false) else ""])
	print(JSON.stringify(rows))
	print("=== OK ===")
	get_tree().quit(0)
