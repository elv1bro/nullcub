## Деталь на связке и налог на ветвление (KitJoint on_rope / on_bar / on_spring / on_piston, BodyBlueprint.ends_energy / branch_energy;
## docs/plan-demo/WORKSHOP_V4.md «Деталь на связке», 06.10.2026): headless-проба.
##   godot --headless --path godot --fixed-fps 60 res://tests/tether_probe.tscn
## Проверки:
##   • типы есть, длины по кругу; голову на связку не повесить (validate);
##   • правая нога на тросе 0.6 м: сустава бедра нет, связка «Link_TA», бедро висит на длине троса от якоря, 3 с без разрыва и NaN;
##   • энергия: трос и вынос ноги дальше от ядра дороже обычной ноги;
##   • кистень: стопа ноги на тросе — тяга мыши, центр круга — крепление троса; мышь крутит ногу — стопа разгоняется;
##   • перебили трос — нога улетела целиком (бедро, голень, стопа — обломки); в «Запасе из деталей» запас потерял трос и ногу;
##   • оторвали предплечье — трос к кисти порвался, кисть улетела тоже; отрыв самой детали на связке рвёт её связку;
##   • кисть на поршне выстреливает по клавише канала; на тяге и пружине собирается и стоит;
##   • налог: «Человек» — 4 конца, без налога; звезда с пятью кистями — 8 концов (+24) и налог на боковые выходы; все пресеты в бюджете;
##   • мастерская: инструмент «На тросе» ставит трос 0.6 м, клик ещё раз — 0.9 м (на 100 энергии «Человеку» не хватает — отказ),
##     «Ось» возвращает сустав.
## В stdout — «=== TETHER PROBE ===» и JSON.
extends Node3D

const DOLL := preload("res://scenes/body/modular_doll.tscn")
const HUMAN := "res://data/body/blueprints/kit_human.tres"

var checks: Array = []
var ok := true
var _x := 0.0
var _n := 0


func _check(pass_: bool, what: String, detail: Variant = null) -> void:
	checks.append({"ok": pass_, "check": what, "detail": detail})
	ok = ok and pass_
	print("  %s %s  %s" % ["ok  " if pass_ else "FAIL", what, "" if detail == null else str(detail)])


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


## kit_human, у узлов uid → {joint, tether_len?, channel?}; extra — добавочные узлы, drop — убрать узлы.
func _bp(sets: Dictionary, extra: Array = [], drop: Array = []) -> BodyBlueprint:
	var bp := (load(HUMAN) as BodyBlueprint).duplicate(true) as BodyBlueprint
	var nodes: Array[Dictionary] = []
	for n in bp.nodes:
		if drop.has(String(n["uid"])):
			continue
		var c := (n as Dictionary).duplicate(true)
		if sets.has(String(c["uid"])):
			c.merge(sets[String(c["uid"])], true)
		nodes.append(c)
	for e in extra:
		nodes.append(e)
	bp.nodes = nodes
	bp.energy_budget = 1000
	_n += 1
	bp.id = "tether_probe_%d" % _n
	return bp


func _doll(bp: BodyBlueprint) -> ModularDoll:
	var d := DOLL.instantiate() as ModularDoll
	d.blueprint = bp
	d.external_input = true
	d.position = Vector3(_x, 0.0, 0.0)
	_x += 6.0
	d.add_to_group("dolls")
	add_child(d)
	d.grace_until = -1.0
	return d


func _ready() -> void:
	var floor := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(400.0, 1.0, 4.0)
	cs.shape = bx
	floor.add_child(cs)
	floor.position = Vector3(150.0, -0.5, 0.0)
	add_child(floor)
	var was := PartHp.on
	PartHp.set_on(false)
	_types()
	await _rope_leg()
	await _breaks()
	await _piston_bar_spring()
	_taxes()
	await _workshop()
	PartHp.set_on(was)
	print("=== TETHER PROBE ===")
	print(JSON.stringify({"ok": ok, "checks": checks}))
	print("=== %s ===" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _types() -> void:
	var t := ["on_rope", "on_bar", "on_spring", "on_piston"]
	var good := true
	for x in t:
		good = good and KitJoint.is_tether(x) and KitJoint.tether_link(x) != "" and KitJoint.ORDER.has(x)
	_check(good and KitJoint.tether_len_of({"joint": "on_rope"}) == 0.6 and not KitJoint.is_tether("pin"), "4 типа «на связке», длина по умолчанию 0.6", t)
	var hb := _bp({"H": {"joint": "on_rope"}})
	var errs := hb.validate()
	_check(not errs.is_empty() and String(errs[0]).contains("голова"), "голову на связку не повесить", errs)


func _rope_leg() -> void:
	var bp := _bp({"A": {"joint": "on_rope", KitJoint.TETHER_KEY: 0.6}})
	var base := (load(HUMAN) as BodyBlueprint)
	_check(bp.validate().is_empty() and bp.energy_used() >= base.energy_used() + KitLink.energy_of("rope", 0.6) + 2,
		"нога на тросе дороже обычной: энергия %d против %d (трос + вынос ноги)" % [bp.energy_used(), base.energy_used()], [bp.energy_used(), base.energy_used()])
	var d := _doll(bp)
	await _frames(2)
	var rec: Dictionary = d.links_rt.get("Link_TA", {})
	var thigh := d.parts.get("UpperLeg_R") as RigidBody3D
	var ends := [Vector3.ZERO, Vector3.ZERO]
	if not rec.is_empty():
		ends = [(rec["a"] as RigidBody3D).global_transform * (rec["pa"] as Vector3), thigh.global_transform * (rec["pb"] as Vector3)]
	_check(not rec.is_empty() and String(rec["tether_child"]) == "UpperLeg_R" and not d.joints.has("Hip_R") and absf((ends[0] as Vector3).distance_to(ends[1]) - 0.6) < 0.05
		and String(rec["type"]) == "rope", "сустава бедра нет, нога висит на тросе 0.6 м (%.2f)" % (ends[0] as Vector3).distance_to(ends[1]), rec.keys())
	var nan := false
	var gap := 0.0
	for f in range(180):
		await get_tree().physics_frame
		for j in rec.get("joints", []):
			var jj := j as Generic6DOFJoint3D
			var a := jj.get_node_or_null(jj.node_a) as RigidBody3D
			var b := jj.get_node_or_null(jj.node_b) as RigidBody3D
			if a == null or b == null:
				continue
			if not (a.global_position.is_finite() and b.global_position.is_finite()):
				nan = true
	var thigh_ok := is_instance_valid(thigh) and d.parts.has("UpperLeg_R") and thigh.global_position.is_finite()
	_check(not nan and thigh_ok and d.alive, "3 с покоя: нога на тросе на месте, без NaN")
	d.queue_free()
	# кистень: стопа ноги на тросе — тяга; мышь крутит её вокруг крепления троса
	var fb := _bp({"A": {"joint": "on_rope"}})
	fb.control = PackedStringArray(["C"])
	var f := _doll(fb)
	await _frames(2)
	var aa := ArmAssist.attach_to(f)
	aa.show_hints = false
	await _frames(3)
	var frec: Dictionary = f.links_rt.get("Link_TA", {})
	var anchor := (frec["a"] as RigidBody3D).to_global(frec["pa"] as Vector3) if not frec.is_empty() else Vector3.INF
	_check(aa.part_name == "Foot_R" and aa.root_point().distance_to(anchor) < 0.01 and aa.reach > 1.1 and aa.reach < 1.8,
		"тяга на стопе ноги на тросе: центр круга — крепление троса, досягаемость %.2f м (нога + трос)" % aa.reach, [aa.part_name, aa.reach])
	var foot := f.parts.get("Foot_R") as RigidBody3D
	var vmax := 0.0
	for i in range(150):
		var ang := -PI * 0.5 + i * 0.1
		aa.set_target_override(aa.root_point() + Vector3(cos(ang), sin(ang), 0.0) * 1.6)
		await get_tree().physics_frame
		vmax = maxf(vmax, foot.linear_velocity.length())
	aa.clear_target_override()
	_check(vmax > 3.0 and f.links_rt.has("Link_TA"), "кистень: мышь крутит ногу на тросе — стопа до %.1f м/с" % vmax, vmax)
	f.queue_free()
	await _frames(2)


func _breaks() -> void:
	# перебили трос — нога улетела целиком
	var d := _doll(_bp({"A": {"joint": "on_rope"}}))
	await _frames(2)
	d.max_hp = 1000.0
	d.hp = 1000.0
	var mx := float(d.link_wear_max.get("Link_TA", 0.0))
	d.take_damage(mx + 1.0, null, "Link_TA", Vector3.ZERO, Vector3.UP, "body")
	await _frames(3)
	_check(not d.links_rt.has("Link_TA") and not d.parts.has("UpperLeg_R") and not d.parts.has("LowerLeg_R") and not d.parts.has("Foot_R") and d.alive,
		"перебили трос (%.0f урона) — нога улетела целиком: бедро, голень, стопа" % mx, d.parts.size())
	d.queue_free()
	# в «Запасе из деталей» — запас потерял трос и ногу
	PartHp.set_on(true)
	var p := _doll(_bp({"A": {"joint": "on_rope"}}))
	await _frames(2)
	var m := Match.new()
	m._parts_hp(p)
	p.refresh_wear()
	var hp0 := p.hp
	var leg := float(p.part_hp["UpperLeg_R"]) + float(p.part_hp["LowerLeg_R"]) + float(p.part_hp["Foot_R"])
	var rope := float(p.links_rt["Link_TA"]["hp"])
	var thr := float(p.link_wear_max["Link_TA"])
	p.take_damage(thr + 0.5, null, "Link_TA", Vector3.ZERO, Vector3.UP, "body")
	await _frames(3)
	_check(absf(p.hp - (hp0 - thr - 0.5 - rope - leg)) < 0.01, "запас из деталей: запас потерял трос (%.0f) и ногу (%.0f)" % [rope, leg], [hp0, p.hp])
	PartHp.set_on(false)
	m.free()
	p.queue_free()
	# оторвали предплечье — кисть на тросе улетела тоже; отрыв самой детали на связке рвёт связку
	var h := _doll(_bp({"9": {"joint": "on_rope"}}))
	await _frames(2)
	h.detach_part("LowerArm_R")
	await _frames(2)
	_check(not h.links_rt.has("Link_T9") and not h.parts.has("Hand_R") and not h.parts.has("LowerArm_R"), "оторвали предплечье — трос порвался, кисть на нём улетела тоже")
	var k := _doll(_bp({"A": {"joint": "on_rope"}}))
	await _frames(2)
	var got := k.detach_part("UpperLeg_R")
	await _frames(2)
	_check(got != null and not k.links_rt.has("Link_TA") and not k.parts.has("Foot_R"), "отрыв самой детали на связке рвёт её трос")
	h.queue_free()
	k.queue_free()
	await _frames(2)


func _piston_bar_spring() -> void:
	var d := _doll(_bp({"9": {"joint": "on_piston", KitJoint.TETHER_KEY: 0.5}}))
	var bar := _doll(_bp({"9": {"joint": "on_bar"}, "C": {"joint": "on_spring"}}))
	await _frames(2)
	var rec: Dictionary = d.links_rt.get("Link_T9", {})
	var dist := func() -> float:
		return ((rec["a"] as RigidBody3D).global_transform * (rec["pa"] as Vector3)).distance_to((rec["b"] as RigidBody3D).global_transform * (rec["pb"] as Vector3))
	await _frames(30)
	var l0: float = dist.call() if not rec.is_empty() else 0.0
	if d.active_rig != null:
		d.active_rig.held[0] = true
	await _frames(40)
	var l1: float = dist.call() if not rec.is_empty() else 0.0
	if d.active_rig != null:
		d.active_rig.held[0] = false
	_check(not rec.is_empty() and d.active_rig != null and l1 > l0 + 0.15, "кисть на поршне: клавиша канала — выстрелила (%.2f → %.2f м)" % [l0, l1], [l0, l1])
	await _frames(120)
	var calm := true
	for b in bar.parts.values():
		calm = calm and (b as RigidBody3D).global_position.is_finite() and (b as RigidBody3D).linear_velocity.length() < 3.0
	_check(bar.links_rt.has("Link_T9") and bar.links_rt.has("Link_TC") and calm and bar.alive, "кисть на тяге и стопа на пружине: собираются и стоят")
	d.queue_free()
	bar.queue_free()
	await _frames(2)


func _taxes() -> void:
	var base := load(HUMAN) as BodyBlueprint
	_check(base.ends_count() == 4 and base.ends_energy() == 0, "«Человек»: 4 конца — без налога", base.ends_count())
	var extra := [{"uid": "9", "part": "kit_hub_star", "parent": "8", "anchor": "Anchor_Wrist"}]
	var hands := [["F", "Anchor_End"], ["G", "Anchor_Side_L"], ["I", "Anchor_Side_R"], ["J", "Anchor_SideB_L"], ["K", "Anchor_SideB_R"]]
	for h in hands:
		extra.append({"uid": h[0], "part": "kit_human_hand", "parent": "9", "anchor": h[1]})
	var sb := _bp({}, extra, ["9"])
	sb.control = PackedStringArray(["F"])
	var br := 0
	for u in ["G", "I", "J", "K"]:
		br += sb.branch_energy(u)
	_check(sb.ends_count() == 8 and sb.ends_energy() == 4 * BodyBlueprint.END_ENERGY and br >= 4 * BodyBlueprint.BRANCH_ENERGY and sb.branch_energy("F") == 0,
		"звезда с пятью кистями: 8 концов — налог %d, боковые выходы — ещё %d" % [sb.ends_energy(), br], [sb.ends_count(), sb.ends_energy(), br])
	var w := CraftEdit.warnings(sb)
	_check(w.size() == 1 and String(w[0]).contains("24") and CraftEdit.warnings(base).is_empty(), "мастерская подсказывает налог на концы", w)
	var over: Array = []
	for f in DirAccess.get_files_at("res://data/body/blueprints/"):
		if not f.ends_with(".tres"):
			continue
		var bp := load("res://data/body/blueprints/" + f) as BodyBlueprint
		if not bp.validate().is_empty():
			over.append("%s: %s" % [f, bp.validate()[0]])
	_check(over.is_empty(), "все пресеты в бюджете и собираются с налогом", over)


func _workshop() -> void:
	WorkshopBuild.prefs_path = "user://workshop_prefs_tether_probe.cfg"
	var ws := (load("res://scenes/workshop/workshop_build.tscn") as PackedScene).instantiate() as WorkshopBuild
	ws.load_autosave = false
	ws.autosave_on_test = false
	ws.probe_input = true
	add_child(ws)
	await _frames(10)
	ws.set_preset("kit_human")
	await _frames(4)
	var e0 := ws.blueprint.energy_used()
	ws.set_joint_pick("on_rope")
	ws.set_joint("A")
	await _frames(2)
	var n := ws.blueprint.find_node("A")
	_check(String(n.get("joint", "")) == "on_rope" and absf(float(n.get(KitJoint.TETHER_KEY, 0.0)) - 0.6) < 0.001 and ws.stand.links_rt.has("Link_TA")
		and ws.blueprint.energy_used() > e0, "мастерская: «На тросе» — нога на тросе 0.6 м, связка на стенде, энергия %d → %d" % [e0, ws.blueprint.energy_used()], n)
	ws.set_joint("A")
	await _frames(2)
	var refused := not bool(ws.last_result.get("ok", true)) and String(ws.last_result.get("reason", "")).contains("0.9")
	ws.blueprint.energy_budget = 140
	ws.set_joint("A")
	await _frames(2)
	_check(refused and absf(float(ws.blueprint.find_node("A").get(KitJoint.TETHER_KEY, 0.0)) - 0.9) < 0.001,
		"клик ещё раз — 0.9 м (у «Человека» на 100 не хватает энергии — отказ, при запасе 140 — длиннее)", [ws.blueprint.find_node("A").get(KitJoint.TETHER_KEY), ws.last_result])
	ws.set_joint_pick("pin")
	ws.set_joint("A")
	await _frames(2)
	n = ws.blueprint.find_node("A")
	_check(not n.has("joint") and not n.has(KitJoint.TETHER_KEY) and not ws.stand.links_rt.has("Link_TA") and ws.stand.joints.has("Hip_R"), "«Ось» — снова сустав бедра, троса нет")
	ws.queue_free()
	await _frames(2)
