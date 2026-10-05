## Броня защищает, детали ломаются (Tuning.PART_ARMOR, PART_BREAK, 04.10.2026): headless-проба.
##   godot --headless --path godot --fixed-fps 60 res://tests/armor_probe.tscn
## Проверки (exit 1): таблица брони и сложение щитков; ModularDoll пишет meta "armor" телу, с которым слит щиток (kit_skull: наруч
## на правом предплечье), и не пишет телам без брони; урон В тело с бронёй = урон × (1 − броня) — и через Damage.target_mult_of_body,
## и через DollCombat._raw_damage; у ядер с толстыми стенками своя броня (клетка 0.1, котёл 0.2), у бочки её нет. Прочность: у тел, кроме ядра и головы, есть запас (материал × PART_INTEGRITY, щиток добавляет);
## при Tuning.PART_BREAK урон в деталь тратит запас, на нуле деталь отлетает вместе с тем, что на ней висит, кукла жива; при
## выключенном (релиз 0.0.3) запас не тратится и деталь на месте; ядро и голова не ломаются в обоих случаях.
## В stdout — «=== ARMOR PROBE ===» и JSON.
extends Node3D

const PRESET := "res://scenes/body/presets/kit_skull.tscn"
const EPS := 0.0005

var checks: Array = []
var ok := true


func _check(pass_: bool, what: String, detail: Variant = null) -> void:
	checks.append({"ok": pass_, "check": what, "detail": detail})
	ok = ok and pass_


func _ready() -> void:
	# таблица: размеры _s / _l идут одной строкой, детали без строки — не броня
	var table := {}
	for id in ["kit_deco_gauntlet_s", "kit_deco_gauntlet_l", "kit_deco_pauldron", "shield_plate", "kit_limb_basic_s", "kit_deco_crown"]:
		table[id] = Damage.part_armor(id)
	_check(is_equal_approx(table["kit_deco_gauntlet_s"], 0.2) and is_equal_approx(table["kit_deco_gauntlet_l"], 0.2)
		and is_equal_approx(table["kit_deco_pauldron"], 0.25) and is_equal_approx(table["shield_plate"], 0.35)
		and table["kit_limb_basic_s"] == 0.0 and table["kit_deco_crown"] == 0.0, "part_armor: таблица Tuning.PART_ARMOR", table)
	_check(absf(Damage.armor_stack(0.2, 0.25) - 0.4) < EPS, "armor_stack: 0.2 + 0.25 = 1 − 0.8 × 0.75", Damage.armor_stack(0.2, 0.25))
	var three := Damage.armor_stack(Damage.armor_stack(0.35, 0.35), 0.35)
	_check(absf(three - Tuning.ARMOR_MAX) < EPS, "armor_stack: три щитка упираются в ARMOR_MAX", three)

	# кукла: наруч на правом предплечье скелета
	var d := (load(PRESET) as PackedScene).instantiate() as ModularDoll
	d.external_input = true
	add_child(d)
	var armored := d.parts.get("LowerArm_R") as RigidBody3D
	var bare := d.parts.get("LowerArm_L") as RigidBody3D
	_check(d.build_errors.is_empty() and armored != null and bare != null, "kit_skull собран, оба предплечья есть", d.build_errors)
	if armored == null or bare == null:
		_finish()
		return
	var a := float(armored.get_meta("armor", 0.0))
	_check(absf(a - 0.2) < EPS, "meta armor у тела с наручем = 0.2", a)
	_check(not bare.has_meta("armor"), "у тела без брони меты armor нет")
	_check(absf(Damage.armor_mult_of_body(armored) - 0.8) < EPS and Damage.armor_mult_of_body(bare) == 1.0,
		"armor_mult_of_body: 0.8 с наручем, 1.0 без", [Damage.armor_mult_of_body(armored), Damage.armor_mult_of_body(bare)])

	# урон одним и тем же ударом в оба предплечья
	var hit_a := Damage.compute(4.0, 8.0, 1.0, 1.0, 1.0, 1.0, Damage.target_mult_of_body(armored))
	var hit_b := Damage.compute(4.0, 8.0, 1.0, 1.0, 1.0, 1.0, Damage.target_mult_of_body(bare))
	_check(hit_b > 0.0 and absf(hit_a / hit_b - 0.8) < EPS, "Damage.compute: удар в броню = 0.8 удара без брони", [hit_a, hit_b])
	var combat := DollCombat.new()
	var c := {"victim_part": armored, "striker": bare, "kind": "body", "mass": 4.0, "speed": 8.0, "body_mult": 1.0, "weapon_mult": 1.0}
	var raw_a: float = combat._raw_damage(c, 1.0)
	c["victim_part"] = bare
	var raw_b: float = combat._raw_damage(c, 1.0)
	combat.free()
	_check(raw_b > 0.0 and absf(raw_a / raw_b - 0.8) < EPS, "DollCombat._raw_damage: удар в броню = 0.8 удара без брони", [raw_a, raw_b])

	# своя броня ядра: клетка скелета 0.1, котёл фонарщика 0.2, бочка человечка — без брони
	var torso := d.parts.get("Torso") as RigidBody3D
	_check(torso != null and absf(float(torso.get_meta("armor", 0.0)) - 0.1) < EPS, "ядро-клетка: meta armor 0.1",
		torso.get_meta("armor", 0.0) if torso != null else null)
	var core_armor := {}
	for id in ["kit_lantern", "kit_human"]:
		var x := (load("res://scenes/body/presets/%s.tscn" % id) as PackedScene).instantiate() as ModularDoll
		x.external_input = true
		x.position = Vector3(6.0 if id == "kit_lantern" else -6.0, 0.0, 0.0)
		add_child(x)
		var t := x.parts.get("Torso") as RigidBody3D
		core_armor[id] = float(t.get_meta("armor", 0.0)) if t != null else -1.0
		x.queue_free()
	_check(absf(core_armor["kit_lantern"] - 0.2) < EPS and core_armor["kit_human"] == 0.0, "ядро-котёл 0.2, ядро-бочка 0", core_armor)
	# прочность: запас у конечностей есть, у ядра и головы нет; щиток добавляет запас своему телу
	var bone := Tuning.PART_INTEGRITY * Damage.part_durability(BodyBlueprint.part_def("kit_limb_bone_s"))
	_check(not d.part_integrity.has("Torso") and not d.part_integrity.has("Head"), "у ядра и головы запаса прочности нет")
	_check(absf(float(d.part_integrity.get("LowerArm_L", 0.0)) - bone) < EPS, "запас костяного предплечья = PART_INTEGRITY × прочность",
		[d.part_integrity.get("LowerArm_L"), bone])
	_check(absf(float(d.part_integrity.get("LowerArm_R", 0.0)) - bone - Tuning.PART_INTEGRITY * Tuning.ARMOR_INTEGRITY_BONUS) < EPS,
		"наруч добавляет запас своему предплечью", d.part_integrity.get("LowerArm_R"))
	# урон в левое предплечье. PART_BREAK включён: сначала запас тратится, потом деталь отлетает вместе с кистью, кукла жива.
	# Выключен (релиз 0.0.3): запас не тратится и деталь на месте, сколько бы урона в неё ни пришло.
	d.max_hp = 1000.0
	d.hp = 1000.0
	d.grace_until = -1.0
	var p0 := bare.global_position
	var broken: Array = []
	d.part_broken.connect(func(n: String, _by: Node) -> void: broken.append(n))
	d.take_damage(bone - 5.0, null, "LowerArm_L", p0, Vector3.UP, "body")
	await get_tree().physics_frame
	await get_tree().physics_frame
	if Tuning.PART_BREAK:
		_check(d.parts.has("LowerArm_L") and absf(float(d.part_integrity.get("LowerArm_L", 0.0)) - 5.0) < 0.01,
			"урон тратит запас, деталь на месте", d.part_integrity.get("LowerArm_L"))
		d.take_damage(10.0, null, "LowerArm_L", p0, Vector3.UP, "body")
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(broken == ["LowerArm_L"] and not d.parts.has("LowerArm_L") and not d.parts.has("Hand_L") and d.alive,
			"запас кончился — предплечье отлетело вместе с кистью, кукла жива", {"broken": broken, "parts": d.parts.keys()})
		_check(not d.part_integrity.has("Hand_L"), "запас отлетевшей кисти снят")
	else:
		d.take_damage(bone * 2.0, null, "LowerArm_L", p0, Vector3.UP, "body")
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(broken.is_empty() and d.parts.has("LowerArm_L") and d.parts.has("Hand_L")
			and absf(float(d.part_integrity.get("LowerArm_L", 0.0)) - bone) < EPS,
			"PART_BREAK выключен: запас не тратится, деталь на месте", {"broken": broken, "запас": d.part_integrity.get("LowerArm_L")})
	d.take_damage(200.0, null, "Torso", p0, Vector3.UP, "body")
	await get_tree().physics_frame
	_check(d.alive and d.parts.has("Torso"), "ядро не ломается от урона", d.hp)
	_finish()


func _finish() -> void:
	print("=== ARMOR PROBE ===")
	print(JSON.stringify({"ok": ok, "checks": checks}, "\t"))
	print("=== OK ===" if ok else "=== FAIL ===")
	get_tree().quit(0 if ok else 1)
