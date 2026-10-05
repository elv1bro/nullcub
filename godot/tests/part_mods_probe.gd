## Модули — пассивные детали со свойствами (PartMods, docs/plan-demo/WORKSHOP_V4.md «Модули», 05.10.2026): headless-проба.
##   godot --headless --path godot --fixed-fps 60 res://tests/part_mods_probe.tscn
## Каждый из 9 модулей ставится на kit_human и сравнивается с таким же «Человеком» без него (двойник рядом, тот же ввод):
##   • данные: у всех модулей есть деталь (вид deco), имя для игрока, своя полка «Модули», строка в паспорте;
##   • сервопривод — тяга руки к цели × 1.6 (и кисти ниже по цепочке), мышцы локтя мягче;
##   • батарея — запас Заряда 130, оторвали предплечье с батареей — взрыв, хозяин теряет больше, чем ❤ отлетевшего;
##   • парус-щит — броня 0.3 и дамп детали выше, разгон под тягой ниже двойника;
##   • маховик — раскрутка быстрее и дешевле, удар в кисть крутит её вдвое меньше;
##   • отбойник — отскок 0.8 у детали, её удар × 0.8;
##   • обтекатель — дамп ниже, разгон выше двойника, урон в голову × 1.15;
##   • амортизатор — стан × 0.6 у ветки, порог отрыва × 1.5 (запас из деталей), мышцы мягче;
##   • ремкомплект — износ детали чинится 2 в секунду (запас бойца — нет);
##   • наждак — износ чужой детали × 1.6, своя деталь стирается на 30 % урона.
## В stdout — «=== PART MODS PROBE ===» и JSON.
extends Node3D

const DOLL := preload("res://scenes/body/modular_doll.tscn")
const HUMAN := "res://data/body/blueprints/kit_human.tres"
const EPS := 0.01
const DRIVE_S := 2.5

var checks: Array = []
var ok := true
var _x := 0.0
var _n := 0


func _check(pass_: bool, what: String, detail: Variant = null) -> void:
	checks.append({"ok": pass_, "check": what, "detail": detail})
	ok = ok and pass_
	print("  %s %s  %s" % ["ok  " if pass_ else "FAIL", what, "" if detail == null else str(detail)])


## kit_human с модулями mods: [[id детали, uid родителя, якорь], …].
func _doll(mods: Array) -> ModularDoll:
	var bp := (load(HUMAN) as BodyBlueprint).duplicate(true) as BodyBlueprint
	var nodes: Array[Dictionary] = []
	for n in bp.nodes:
		nodes.append((n as Dictionary).duplicate(true))
	var uids := "DEFGIJKLMN"
	for k in range(mods.size()):
		nodes.append({"uid": uids[k], "part": String(mods[k][0]), "parent": String(mods[k][1]), "anchor": String(mods[k][2])})
	bp.nodes = nodes
	bp.energy_budget = 1000
	_n += 1
	bp.id = "mods_probe_%d" % _n
	var d := DOLL.instantiate() as ModularDoll
	d.blueprint = bp
	d.external_input = true
	d.position = Vector3(_x, 0.0, 0.0)
	_x += 6.0
	d.add_to_group("dolls")
	add_child(d)
	d.grace_until = -1.0
	return d


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _ready() -> void:
	var floor := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(400.0, 1.0, 4.0)
	cs.shape = bx
	floor.add_child(cs)
	floor.position = Vector3(150.0, -0.5, 0.0)
	add_child(floor)
	var was_parts := PartHp.on
	var was_joints := JointBreak.on
	PartHp.set_on(false)
	JointBreak.set_on(false)
	_data()
	await _servo()
	await _battery()
	await _drag()
	await _flywheel()
	_bumper()
	await _damper()
	await _repair()
	await _grinder()
	PartHp.set_on(was_parts)
	JointBreak.set_on(was_joints)
	print("=== PART MODS PROBE ===")
	print(JSON.stringify({"ok": ok, "checks": checks}))
	print("=== %s ===" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _data() -> void:
	var missing: Array = []
	for id in PartMods.DEFS:
		var pd := BodyBlueprint.part_def(String(id))
		if pd == null or pd.kind != "deco" or PartNames.of(pd) == String(id) or not CraftEdit.part_desc(pd).contains(TranslationServer.translate(String(PartMods.DEFS[id]["hint"]))):
			missing.append(id)
	_check(missing.is_empty() and PartMods.DEFS.size() == 9, "9 модулей: деталь вида deco, имя для игрока, строка в паспорте", missing)
	var sh := CraftEdit.shelf_of(CraftEdit.BODY_SHELVES, "mods")
	var on_shelf := 0
	var leak := 0
	for id in PartMods.DEFS:
		var pd := BodyBlueprint.part_def(String(id))
		if pd != null and CraftEdit.shelf_allows(sh, pd):
			on_shelf += 1
		if pd != null and CraftEdit.shelf_allows(CraftEdit.shelf_of(CraftEdit.BODY_SHELVES, "deco"), pd):
			leak += 1
	_check(on_shelf == 9 and leak == 0, "полка «Модули» — все 9, на «Декоре» их нет", [on_shelf, leak])


func _servo() -> void:
	var a := _doll([["kit_mod_servo", "8", "Anchor_Deco"]])
	var b := _doll([])
	await _frames(2)
	_check(absf(PartMods.of(a.parts["LowerArm_R"], "pull_mult") - 1.6) < EPS and absf(PartMods.of(a.parts["Hand_R"], "pull_mult") - 1.6) < EPS
		and absf(PartMods.of(a.parts["UpperArm_R"], "pull_mult") - 1.0) < EPS, "сервопривод на предплечье: тяга × 1.6 у предплечья и кисти, плечо — нет")
	var fa := await _pull_force(a)
	var fb := await _pull_force(b)
	_check(fa > fb * 1.5, "сервопривод: сила тяги руки к далёкой цели %.0f Н против %.0f" % [fa, fb], [fa, fb])
	var ka := _pair_k(a, "Elbow_R")
	var kb := _pair_k(b, "Elbow_R")
	_check(ka > 0.0 and ka < kb * 0.8, "сервопривод: мышца локтя мягче (рука вялее без тяги)", [ka, kb])
	a.queue_free()
	b.queue_free()


func _pull_force(d: ModularDoll) -> float:
	var arm := ArmAssist.new()
	arm.control_part = "Hand_R"
	arm.show_hints = false
	d.add_child(arm)
	await _frames(3)
	arm.set_target_override(d.parts["Hand_R"].global_position + Vector3(3.0, 2.0, 0.0))
	await _frames(4)
	var f := arm.last_assist_force.length()
	arm.clear_target_override()
	return f


func _pair_k(d: Doll, joint: String) -> float:
	for e in d.get("_muscle_pairs"):
		if String(e[Doll.MP_NAME]) == joint:
			return float(e[Doll.MP_K])
	return -1.0


func _battery() -> void:
	var a := _doll([["kit_mod_battery", "8", "Anchor_Deco"]])
	await _frames(2)
	a.reset_charge()
	_check(absf(a.charge_cap() - (Tuning.CHARGE_MAX + 30.0)) < EPS and absf(a.charge - a.charge_cap()) < EPS, "батарея: запас Заряда 130, полный бак — 130", [a.charge, a.charge_cap()])
	PartHp.set_on(true)
	var m := Match.new()   # не в дереве: Match в дереве сам начнёт раунд и пересчитает запас после отрыва
	m._parts_hp(a)
	a.refresh_wear()
	var hp0 := a.hp
	var lost := float(a.part_hp["LowerArm_R"]) + float(a.part_hp["Hand_R"])
	var thr := float(a.joint_hp_max["LowerArm_R"])
	a.take_damage(thr + 0.5, null, "LowerArm_R", Vector3.ZERO, Vector3.UP, "body")
	await _frames(4)
	var blasts := find_children("Explosion", "Explosion", true, false).size()
	_check(not a.parts.has("LowerArm_R") and int(a.stats.get("batteries_blown", 0)) == 1 and blasts >= 1, "батарея: предплечье оторвалось — взрыв", [a.stats.get("batteries_blown"), blasts])
	_check(a.hp < hp0 - thr - lost - 3.0, "батарея: взрыв бьёт и по хозяину (%.0f → %.0f, без взрыва было бы %.0f)" % [hp0, a.hp, hp0 - thr - 0.5 - lost], a.hp)
	PartHp.set_on(false)
	m.free()
	a.queue_free()
	await _frames(2)


## Разгон под тягой вправо: скорость ЦМ по x через DRIVE_S с.
func _drive(ds: Array) -> Array:
	for d in ds:
		(d as Doll).input_vec = Vector2(1.0, 0.0)
	await _frames(int(DRIVE_S * 60.0))
	var out: Array = []
	for d in ds:
		out.append((d as Doll).com_velocity().x)
		(d as Doll).input_vec = Vector2.ZERO
	return out


func _drag() -> void:
	var sail := _doll([["kit_mod_sail", "2", "Anchor_Deco"]])
	var fair := _doll([["kit_mod_fairing", "H", "Anchor_Top"]])
	var base := _doll([])
	await _frames(30)
	var la := sail.parts["LowerArm_L"] as RigidBody3D
	_check(float(la.get_meta("armor", 0.0)) >= 0.3 - EPS and la.linear_damp > (base.parts["LowerArm_L"] as RigidBody3D).linear_damp + 2.0,
		"парус-щит: броня 0.3 у предплечья, дамп выше", [la.get_meta("armor", 0.0), la.linear_damp])
	var hd := fair.parts["Head"] as RigidBody3D
	_check(hd.linear_damp < (base.parts["Head"] as RigidBody3D).linear_damp - 0.3 and absf(Damage.armor_mult_of_body(hd) - 1.15) < EPS,
		"обтекатель: дамп головы ниже, урон в неё × 1.15", [hd.linear_damp, Damage.armor_mult_of_body(hd)])
	var v: Array = await _drive([sail, fair, base])
	_check(float(v[0]) < float(v[2]) - 0.05 and float(v[1]) > float(v[2]) + 0.05, "под тягой: парус медленнее, обтекатель быстрее двойника (м/с)",
		{"sail": snappedf(v[0], 0.01), "fairing": snappedf(v[1], 0.01), "base": snappedf(v[2], 0.01)})
	for d in [sail, fair, base]:
		d.queue_free()


func _flywheel() -> void:
	var a := _doll([["kit_mod_flywheel", "T", "Anchor_Back"]])
	var b := _doll([])
	await _frames(30)
	_check(absf(a.spin_torque_mult - 1.6) < EPS and absf(a.spin_cost_mult - 0.6) < EPS and absf(a.knock_spin_mult - 0.5) < EPS,
		"маховик: раскрутка × 1.6, расход × 0.6, закрутка от удара × 0.5", [a.spin_torque_mult, a.spin_cost_mult, a.knock_spin_mult])
	# удар в кисть: доля импульса в саму кисть вдвое меньше — кисть разгоняется меньше
	var j := Vector3(6.0, 0.0, 0.0)   # слабый удар: кисть не упирается в потолок KNOCKBACK_PART_MAX_DV
	var ha := a.parts["Hand_L"] as RigidBody3D
	var hb := b.parts["Hand_L"] as RigidBody3D
	var va := ha.linear_velocity
	var vb := hb.linear_velocity
	a.apply_knockback(j, ha)
	b.apply_knockback(j, hb)
	var da := (ha.linear_velocity - va).length()
	var db := (hb.linear_velocity - vb).length()
	_check(da < db * 0.7, "маховик: удар в кисть разгоняет её меньше (%.2f против %.2f м/с)" % [da, db], [da, db])
	await _frames(90)
	# раскрутка 1 с: быстрее и дешевле
	a.reset_charge()
	b.reset_charge()
	for i in range(60):
		for d in [a, b]:
			(d as Doll).input_vec = Vector2(1.0, 0.0)
			(d as Doll).request_spin()
		await get_tree().physics_frame
	var wa := absf(a.torso().angular_velocity.z)
	var wb := absf(b.torso().angular_velocity.z)
	var sa := float(a.stats["charge_spent"])
	var sb := float(b.stats["charge_spent"])
	for d in [a, b]:
		(d as Doll).input_vec = Vector2.ZERO
	_check(wa > wb * 1.05 and sa < sb * 0.8, "маховик: раскрутка быстрее (ω %.2f против %.2f) и дешевле (Заряд %.0f против %.0f)" % [wa, wb, sa, sb], [wa, wb, sa, sb])
	a.queue_free()
	b.queue_free()


func _bumper() -> void:
	var a := _doll([["kit_mod_bumper", "5", "Anchor_Deco"]])
	var b := _doll([])
	var ll := a.parts["LowerLeg_L"] as RigidBody3D
	var pm := ll.physics_material_override
	var bm_a := Damage.body_mult_of_body(ll)
	var bm_b := Damage.body_mult_of_body(b.parts["LowerLeg_L"])
	_check(pm != null and pm.bounce >= 0.8 - EPS and absf(bm_a - bm_b * 0.8) < EPS, "отбойник: отскок 0.8 у голени, её удар × 0.8", [pm.bounce if pm != null else -1.0, bm_a, bm_b])
	a.queue_free()
	b.queue_free()


func _damper() -> void:
	var a := _doll([["kit_mod_damper", "2", "Anchor_Deco"]])
	var b := _doll([])
	await _frames(2)
	_check(absf(PartMods.of(a.parts["LowerArm_L"], "stun_mult") - 0.6) < EPS and absf(PartMods.of(a.parts["Hand_L"], "stun_mult") - 0.6) < EPS
		and absf(PartMods.of(a.parts["UpperArm_L"], "stun_mult") - 1.0) < EPS, "амортизатор: стан × 0.6 у предплечья и кисти, плечо — нет")
	_check(_pair_k(a, "Elbow_L") < _pair_k(b, "Elbow_L") * 0.8, "амортизатор: мышца локтя мягче", [_pair_k(a, "Elbow_L"), _pair_k(b, "Elbow_L")])
	PartHp.set_on(true)
	a.refresh_wear()
	b.refresh_wear()
	var want := PartHp.break_hp(float(a.part_hp["LowerArm_L"])) * 1.5   # своя масса амортизатора тоже прибавляет предплечью ❤
	_check(absf(float(a.joint_hp_max["LowerArm_L"]) - want) < EPS, "амортизатор: порог отрыва предплечья × 1.5",
		[a.joint_hp_max["LowerArm_L"], want])
	# стан от настоящего удара: DollCombat.deliver режет стан ветки — проверяем множитель тем же путём, что в бою
	var stun_a := Damage.stun_seconds(20.0) * PartMods.of(a.parts["LowerArm_L"], "stun_mult")
	_check(stun_a < Damage.stun_seconds(20.0) * 0.7, "амортизатор: стан удара 20 HP в предплечье %.2f с против %.2f" % [stun_a, Damage.stun_seconds(20.0)])
	PartHp.set_on(false)
	a.queue_free()
	b.queue_free()


func _repair() -> void:
	PartHp.set_on(true)
	var a := _doll([["kit_mod_repair", "T", "Anchor_Back"]])
	var b := _doll([])
	await _frames(2)
	for d in [a, b]:
		(d as Doll).max_hp = 1000.0
		(d as Doll).hp = 1000.0
		(d as Doll).refresh_wear()
		(d as Doll).take_damage(10.0, null, "UpperArm_L", Vector3.ZERO, Vector3.UP, "body")
	var wa0 := float(a.joint_hp["UpperArm_L"])
	var hp_a := a.hp
	await _frames(120)
	var gained := float(a.joint_hp["UpperArm_L"]) - wa0
	_check(gained > 3.5 and gained < 4.5 and absf(float(b.joint_hp["UpperArm_L"]) - (float(b.joint_hp_max["UpperArm_L"]) - 10.0)) < EPS and is_equal_approx(a.hp, hp_a),
		"ремкомплект: износ плеча чинится 2/с (+%.1f за 2 с), у двойника нет, запас бойца не лечится" % gained, [gained, a.hp])
	PartHp.set_on(false)
	a.queue_free()
	b.queue_free()


func _grinder() -> void:
	PartHp.set_on(true)
	var atk := _doll([["kit_mod_grinder", "8", "Anchor_Deco"]])
	var vic := _doll([])
	var ref := _doll([])
	await _frames(2)
	for d in [atk, vic, ref]:
		(d as Doll).max_hp = 1000.0
		(d as Doll).hp = 1000.0
		(d as Doll).refresh_wear()
	var striker: RigidBody3D = atk.parts["LowerArm_R"]
	var own0 := float(atk.joint_hp["LowerArm_R"])
	vic.hit_meta = {"striker": striker}
	vic.take_damage(5.0, atk, "UpperArm_L", Vector3.ZERO, Vector3.UP, "body")
	ref.hit_meta = {"striker": ref.parts["LowerArm_R"]}
	ref.take_damage(5.0, atk, "UpperArm_L", Vector3.ZERO, Vector3.UP, "body")
	var wv := float(vic.joint_hp_max["UpperArm_L"]) - float(vic.joint_hp["UpperArm_L"])
	var wr := float(ref.joint_hp_max["UpperArm_L"]) - float(ref.joint_hp["UpperArm_L"])
	_check(absf(wv - wr * 1.6) < EPS, "наждак: износ чужой детали × 1.6 (%.1f против %.1f)" % [wv, wr], [wv, wr])
	_check(absf((own0 - float(atk.joint_hp["LowerArm_R"])) - 5.0 * 0.3) < EPS, "наждак: своё предплечье стёрлось на 30 % урона", own0 - float(atk.joint_hp["LowerArm_R"]))
	PartHp.set_on(false)
	for d in [atk, vic, ref]:
		d.queue_free()
