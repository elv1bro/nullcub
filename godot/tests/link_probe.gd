## Связки (KitLink, LinkBuilder, docs/plan-demo/WORKSHOP_V4.md «Связки», 06.10.2026): headless-проба.
##   godot --headless --path godot --fixed-fps 60 res://tests/link_probe.tscn
## На kit_human ставится связка каждого вида (левая кисть ↔ левое бедро — контур через плечо и торс); кукла стоит на полу:
##   • собирается: тела связки в parts, суставы не в joints (не мышцы), масса бойца выросла, ❤ у связки есть;
##   • 4 с покоя без разрыва: концы связки у своих деталей (≤ 3 см), кукла не разлетелась (скорости малы);
##   • стержень держит длину и угол кисти к бедру, тяга — длину, пружина возвращается к длине после толчка, трос не даёт разойтись
##     дальше длины, поршень по set_piston выдвигается и разводит концы;
##   • удар в связку копит износ — на пороге она рвётся (link_broken, тела — обломки, суставы освобождены), без связки кисть
##     отходит от бедра свободно; в «Запасе из деталей» запас бойца теряет ❤ связки;
##   • отрыв детали на конце рвёт связку; KO освобождает суставы связок;
##   • чертёж: энергия связки входит в energy_used, битая связка (нет узла) пропускается, кукла собирается.
## В stdout — «=== LINK PROBE ===» и JSON.
extends Node3D

const DOLL := preload("res://scenes/body/modular_doll.tscn")
const HUMAN := "res://data/body/blueprints/kit_human.tres"
const EPS := 0.03

var checks: Array = []
var ok := true
var _x := 0.0
var _n := 0


func _check(pass_: bool, what: String, detail: Variant = null) -> void:
	checks.append({"ok": pass_, "check": what, "detail": detail})
	ok = ok and pass_
	print("  %s %s  %s" % ["ok  " if pass_ else "FAIL", what, "" if detail == null else str(detail)])


## kit_human со связками links: [[вид, uid a, pa, uid b, pb, канал?], …].
func _doll(links: Array) -> ModularDoll:
	var bp := (load(HUMAN) as BodyBlueprint).duplicate(true) as BodyBlueprint
	var ls: Array[Dictionary] = []
	for k in range(links.size()):
		var l: Array = links[k]
		var e := {"id": str(k + 1), "type": String(l[0]), "a": String(l[1]), "pa": l[2], "b": String(l[3]), "pb": l[4], "len": 0.6}
		if l.size() > 5:
			e[KitLink.CHANNEL_KEY] = int(l[5])
		ls.append(e)
	bp.links = ls
	bp.energy_budget = 1000
	_n += 1
	bp.id = "link_probe_%d" % _n
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


## Мировые концы связки ln (по чертежу) и её длина.
func _ends(d: ModularDoll, id: String) -> Array:
	var l := d.blueprint.find_link(id)
	var ba := d.parts[d.uid_body[String(l["a"])]] as RigidBody3D
	var bb := d.parts[d.uid_body[String(l["b"])]] as RigidBody3D
	var wa: Vector3 = ba.global_transform * (l["pa"] as Vector3)
	var wb: Vector3 = bb.global_transform * (l["pb"] as Vector3)
	return [wa, wb, wa.distance_to(wb), ba, bb]


## Насколько концы тел связки разошлись с точками на деталях (м): сустав держит?
func _gap(d: ModularDoll, ln: String) -> float:
	var rec: Dictionary = d.links_rt.get(ln, {})
	if rec.is_empty():
		return 99.0
	var worst := 0.0
	# расхождение: каждый сустав — его точка в кадрах обоих тел, снятых при сборке
	for k in range(rec["joints"].size()):
		var jj := rec["joints"][k] as Generic6DOFJoint3D
		if not jj.has_meta("pa_local") or jj == rec.get("strut"):
			continue   # телескоп пружины и поршня ходит по оси — это не расхождение
		var a := jj.get_node_or_null(jj.node_a) as RigidBody3D
		var b := jj.get_node_or_null(jj.node_b) as RigidBody3D
		if a == null or b == null:
			continue
		worst = maxf(worst, (a.global_transform * (jj.get_meta("pa_local") as Vector3)).distance_to(b.global_transform * (jj.get_meta("pb_local") as Vector3)))
	return worst


func _mark(d: ModularDoll) -> void:
	for ln in d.links_rt:
		for j in d.links_rt[ln]["joints"]:
			var jj := j as Generic6DOFJoint3D
			var a := jj.get_node_or_null(jj.node_a) as RigidBody3D
			var b := jj.get_node_or_null(jj.node_b) as RigidBody3D
			if a != null and b != null:
				jj.set_meta("pa_local", a.global_transform.affine_inverse() * jj.global_position)
				jj.set_meta("pb_local", b.global_transform.affine_inverse() * jj.global_position)


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
	PartHp.set_on(false)
	await _types()
	await _break()
	await _detach_ko()
	_blueprint()
	await _workshop()
	PartHp.set_on(was_parts)
	print("=== LINK PROBE ===")
	print(JSON.stringify({"ok": ok, "checks": checks}))
	print("=== %s ===" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


const HAND := Vector3(0.0, 0.08, 0.0)
const THIGH := Vector3(0.05, 0.2, 0.0)


func _types() -> void:
	var base := _doll([])
	var ds := {}
	for t in KitLink.ORDER:
		ds[t] = _doll([[t, "3", HAND, "4", THIGH, 1]])
	await _frames(2)
	for t in ds:
		_mark(ds[t])
	var d0: ModularDoll = ds["rod"]
	var rec: Dictionary = d0.links_rt.get("Link_1", {})
	_check(not rec.is_empty() and d0.parts.has("Link_1") and not d0.joints.has("Link_1_JA") and d0.total_mass > base.total_mass + 0.1
		and float(rec["hp"]) >= 3.0, "стержень собран: тело в parts, суставы не мышцы, масса бойца выросла, ❤ %.0f" % float(rec.get("hp", 0.0)),
		[d0.total_mass, base.total_mass])
	var counts := {}
	for t in ds:
		counts[t] = (ds[t] as ModularDoll).links_rt.get("Link_1", {}).get("bodies", []).size()
	_check(int(counts["rod"]) == 1 and int(counts["bar"]) == 1 and int(counts["spring"]) == 2 and int(counts["piston"]) == 2 and int(counts["rope"]) >= 2,
		"тела видов: стержень и тяга — 1, пружина и поршень — корпус и шток, трос — звенья", counts)
	var len0 := {}
	var ang0 := {}
	for t in ds:
		var e := _ends(ds[t], "1")
		len0[t] = float(e[2])
		ang0[t] = wrapf((e[3] as RigidBody3D).global_rotation.z - (e[4] as RigidBody3D).global_rotation.z, -PI, PI)
	await _frames(240)   # 4 с покоя
	var gaps := {}
	var calm := true
	var lens := {}
	for t in ds:
		var d: ModularDoll = ds[t]
		gaps[t] = snappedf(_gap(d, "Link_1"), 0.001)
		for b in d.parts.values():
			calm = calm and (b as RigidBody3D).linear_velocity.length() < 1.5
		lens[t] = snappedf(float(_ends(d, "1")[2]), 0.001)
	var gap_ok := true
	for t in gaps:
		gap_ok = gap_ok and float(gaps[t]) < EPS
	_check(gap_ok and calm, "4 с покоя: суставы связок держат (≤ 3 см), куклы не разлетелись", {"gaps": gaps, "calm": calm})
	var rod_e := _ends(ds["rod"], "1")
	var rod_ang := wrapf((rod_e[3] as RigidBody3D).global_rotation.z - (rod_e[4] as RigidBody3D).global_rotation.z, -PI, PI)
	_check(absf(float(lens["rod"]) - float(len0["rod"])) < EPS and absf(float(lens["bar"]) - float(len0["bar"])) < EPS,
		"стержень и тяга держат длину", {"rod": [len0["rod"], lens["rod"]], "bar": [len0["bar"], lens["bar"]]})
	# толчок: кисть тянут прочь от бедра — стержень не пускает ни длину, ни угол, тяга — длину, трос — дальше длины, пружина тянется
	for t in ds:
		var hand := (ds[t] as ModularDoll).parts["Hand_L"] as RigidBody3D
		hand.apply_central_impulse(Vector3(-3.0, 2.0, 0.0))
	var base_hand := base.parts["Hand_L"] as RigidBody3D
	var bh0 := base_hand.global_position.distance_to((base.parts["UpperLeg_L"] as RigidBody3D).global_position)
	base_hand.apply_central_impulse(Vector3(-3.0, 2.0, 0.0))
	await _frames(6)
	var stretch := {}
	for t in ds:
		stretch[t] = snappedf(float(_ends(ds[t], "1")[2]) - float(len0[t]), 0.001)
	var bh := base_hand.global_position.distance_to((base.parts["UpperLeg_L"] as RigidBody3D).global_position) - bh0
	_check(float(stretch["rod"]) < 0.04 and float(stretch["bar"]) < 0.04 and float(stretch["rope"]) < 0.06 and float(stretch["spring"]) > 0.02
		and bh > 0.08, "рывок кисти: стержень, тяга и трос не пускают дальше длины, пружина тянется, без связки кисть отходит на %.2f м" % bh, stretch)
	await _frames(120)
	var sp := float(_ends(ds["spring"], "1")[2])
	_check(absf(sp - float(len0["spring"])) < 0.05, "пружина вернулась к длине (%.3f против %.3f)" % [sp, float(len0["spring"])], sp)
	# поршень: выдвинуть — концы расходятся на ход
	var pd: ModularDoll = ds["piston"]
	var p0 := float(_ends(pd, "1")[2])
	_check(pd.active_rig != null and pd.active_rig.pistons.size() == 1, "поршень: ActiveRig есть и знает поршень на канале 1", pd.active_rig.pistons if pd.active_rig != null else null)
	var c0 := pd.active_rig.charge if pd.active_rig != null else 0.0
	if pd.active_rig != null:
		pd.active_rig.held[0] = true   # клавиша канала 1 (I) — как в бою: ActiveRig каждый кадр ставит поршень по клавише
	await _frames(40)
	var p1 := float(_ends(pd, "1")[2])
	var spent := c0 - (pd.active_rig.charge if pd.active_rig != null else 0.0)
	if pd.active_rig != null:
		pd.active_rig.held[0] = false
	await _frames(60)
	var p2 := float(_ends(pd, "1")[2])
	_check(p1 > p0 + 0.08 and p2 < p1 - 0.05 and spent > 1.0, "поршень: клавиша канала — концы разошлись (%.2f → %.2f м, заряд −%.0f), отпустил — сошлись (%.2f)" % [p0, p1, spent, p2], [p0, p1, p2])
	for t in ds:
		(ds[t] as Node).queue_free()
	base.queue_free()
	await _frames(2)


func _break() -> void:
	var d := _doll([["bar", "3", HAND, "4", THIGH]])
	await _frames(2)
	d.max_hp = 1000.0
	d.hp = 1000.0
	var got: Array = []
	d.link_broken.connect(func(ln: String, _by: Node, _p: Vector3) -> void: got.append(ln))
	var mx := float(d.link_wear_max.get("Link_1", 0.0))
	d.take_damage(mx - 5.0, null, "Link_1", Vector3.ZERO, Vector3.UP, "body")
	await _frames(2)
	_check(d.links_rt.has("Link_1") and absf(float(d.link_wear["Link_1"]) - 5.0) < 0.01, "удар в связку копит износ (порог %.0f)" % mx, d.link_wear.get("Link_1"))
	var body := d.parts["Link_1"] as RigidBody3D
	var j: Generic6DOFJoint3D = d.links_rt["Link_1"]["joints"][0]
	d.take_damage(10.0, null, "Link_1", Vector3.ZERO, Vector3.UP, "body")
	await _frames(3)
	_check(got == ["Link_1"] and not d.links_rt.has("Link_1") and not d.parts.has("Link_1") and body.has_meta("detached_from")
		and not is_instance_valid(j) and int(d.stats.get("links_broken", 0)) == 1, "на пороге связка порвалась: тело — обломок, суставы освобождены", got)
	d.queue_free()
	# в «Запасе из деталей» — запас бойца теряет ❤ связки
	PartHp.set_on(true)
	var p := _doll([["rod", "3", HAND, "4", THIGH]])
	await _frames(2)
	var m := Match.new()
	m._parts_hp(p)
	p.refresh_wear()
	var hp0 := p.hp
	var lhp := float(p.links_rt["Link_1"]["hp"])
	var thr := float(p.link_wear_max["Link_1"])
	_check(absf(thr - PartHp.break_hp(lhp)) < 0.01 and absf(p.max_hp - (100.0 + lhp)) < 0.01, "запас из деталей: ❤ связки в запасе (%.0f), порог %.0f" % [lhp, thr], [p.max_hp, thr])
	p.take_damage(thr + 0.5, null, "Link_1", Vector3.ZERO, Vector3.UP, "body")
	await _frames(3)
	_check(not p.links_rt.has("Link_1") and absf(p.hp - (hp0 - thr - 0.5 - lhp)) < 0.01, "порвалась — запас бойца потерял и её ❤", [hp0, p.hp])
	PartHp.set_on(false)
	m.free()
	p.queue_free()
	await _frames(2)


func _detach_ko() -> void:
	var d := _doll([["rope", "3", HAND, "4", THIGH]])
	await _frames(2)
	var segs: Array = d.links_rt["Link_1"]["bodies"]
	d.detach_part("LowerArm_L")
	await _frames(2)
	_check(not d.links_rt.has("Link_1") and not d.parts.has(String((segs[0] as Node).name)), "отрыв предплечья рвёт трос, что шёл к кисти")
	var k := _doll([["rod", "3", HAND, "4", THIGH]])
	await _frames(2)
	var kj: Array = k.links_rt["Link_1"]["joints"].duplicate()
	k.knock_out()
	await _frames(2)
	var freed := true
	for j in kj:
		freed = freed and not is_instance_valid(j)
	_check(freed and k.links_rt.is_empty(), "KO освобождает суставы связок")
	d.queue_free()
	k.queue_free()
	await _frames(2)


func _blueprint() -> void:
	var bp := (load(HUMAN) as BodyBlueprint).duplicate(true) as BodyBlueprint
	var e0 := bp.energy_used()
	bp.links = [{"id": "1", "type": "rod", "a": "3", "pa": HAND, "b": "4", "pb": THIGH, "len": 1.0}]
	_check(bp.energy_used() == e0 + KitLink.energy_of("rod", 1.0) and bp.validate().is_empty(), "энергия связки в energy_used (+%d), чертёж валиден" % KitLink.energy_of("rod", 1.0))
	# шаблон мастерской «Поршневой»: три связки собираются, длины чертежа ≈ настоящим, энергия в бюджете (и в «Запасе из деталей»)
	var tp := load("res://data/body/blueprints/kit_pistons.tres") as BodyBlueprint
	var td := DOLL.instantiate() as ModularDoll
	td.blueprint = tp
	td.position = Vector3(_x, 0.0, 0.0)
	_x += 6.0
	add_child(td)
	var lens_ok := true
	var lens := []
	for l in tp.links:
		var rec: Dictionary = td.links_rt.get("Link_" + String(l["id"]), {})
		lens.append([float(l["len"]), snappedf(float(rec.get("len", -1.0)), 0.01)])
		lens_ok = lens_ok and not rec.is_empty() and absf(float(rec["len"]) - float(l["len"])) < 0.06
	PartHp.set_on(true)
	var fits_parts := tp.energy_used() <= tp.energy_cap()
	PartHp.set_on(false)
	_check(td.links_rt.size() == 3 and lens_ok and tp.energy_used() <= tp.energy_cap() and fits_parts and tp.validate().is_empty()
		and CraftEdit.BODY_PRESETS.has("kit_pistons"), "шаблон «Поршневой»: 3 связки, длины чертежа ≈ настоящим, энергия %d / %d" % [tp.energy_used(), tp.energy_cap()], lens)
	td.queue_free()
	bp.links = [{"id": "1", "type": "rod", "a": "3", "pa": HAND, "b": "Z", "pb": THIGH, "len": 0.5}]
	_check(bp.validate().is_empty(), "битая связка (нет узла Z) чертёж не бракует")
	var d := DOLL.instantiate() as ModularDoll
	d.blueprint = bp
	d.position = Vector3(_x, 0.0, 0.0)
	add_child(d)
	_check(d.build_errors.is_empty() and d.links_rt.is_empty() and d.parts.size() == 14, "кукла с битой связкой собирается без неё", d.parts.size())
	d.queue_free()


## Мастерская: инструмент «Связка» — два клика ставят связку (энергия, тело на стенде), клик по связке снимает, Ctrl+Z возвращает,
## поршень своим инструментом меняет канал, снятая деталь уносит свою связку.
func _workshop() -> void:
	WorkshopBuild.prefs_path = "user://workshop_prefs_link_probe.cfg"
	var ws := (load("res://scenes/workshop/workshop_build.tscn") as PackedScene).instantiate() as WorkshopBuild
	ws.load_autosave = false
	ws.autosave_on_test = false
	ws.probe_input = true
	add_child(ws)
	await _frames(10)
	ws.set_preset("kit_human")
	await _frames(4)
	var e0 := ws.blueprint.energy_used()
	ws.set_link_pick("rod")
	var hand := ws.stand.parts["Hand_L"] as RigidBody3D
	var thigh := ws.stand.parts["UpperLeg_L"] as RigidBody3D
	ws._link_click({"target": "body", "uid": "3", "pos": hand.global_position})
	_check(not ws.link_from.is_empty() and ws.blueprint.links.is_empty(), "мастерская: первый клик — первый конец, связки ещё нет")
	ws._link_click({"target": "body", "uid": "4", "pos": thigh.global_position})
	await _frames(2)
	var l: Dictionary = ws.blueprint.links[0] if ws.blueprint.links.size() == 1 else {}
	_check(ws.blueprint.links.size() == 1 and String(l.get("type", "")) == "rod" and ws.stand.links_rt.has("Link_1") and ws.blueprint.energy_used() > e0
		and ws.link_from.is_empty(), "второй клик — стержень: в чертеже, телом на стенде, энергия %d → %d" % [e0, ws.blueprint.energy_used()], l)
	ws._link_click({"target": "link", "link": "1"})
	await _frames(2)
	_check(ws.blueprint.links.is_empty() and not ws.stand.links_rt.has("Link_1"), "клик по связке — снята")
	ws.undo()
	await _frames(2)
	_check(ws.blueprint.links.size() == 1 and ws.stand.links_rt.has("Link_1"), "отмена — связка вернулась")
	ws.set_link_pick("piston")
	ws._link_click({"target": "body", "uid": "9", "pos": (ws.stand.parts["Hand_R"] as Node3D).global_position})
	ws._link_click({"target": "body", "uid": "T", "pos": (ws.stand.parts["Torso"] as Node3D).global_position + Vector3(0.1, 0.1, 0.0)})
	await _frames(2)
	var pid := ""
	for x in ws.blueprint.links:
		if String(x.get("type", "")) == "piston":
			pid = String(x["id"])
	var ch0 := int(ws.blueprint.find_link(pid).get(KitLink.CHANNEL_KEY, 0))
	ws._link_click({"target": "link", "link": pid})
	await _frames(2)
	_check(pid != "" and ch0 == 1 and int(ws.blueprint.find_link(pid).get(KitLink.CHANNEL_KEY, 0)) == 2, "поршень: новый на канале 1, клик тем же инструментом — канал 2")
	ws.clear_tools()
	ws.unscrew("3", "body")   # снять левую кисть — стержень к ней уходит, поршень остаётся
	await _frames(2)
	var left := []
	for x in ws.blueprint.links:
		left.append(String(x.get("type", "")))
	_check(left == ["piston"], "снятая кисть унесла свой стержень, поршень остался", left)
	ws.queue_free()
	await _frames(2)
