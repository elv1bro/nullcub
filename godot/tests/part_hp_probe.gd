## Запас из деталей — пробный режим (PartHp, docs/plan-demo/WORKSHOP_V4.md, 05.10.2026): headless-проба.
##   godot --headless --path godot --fixed-fps 60 res://tests/part_hp_probe.tscn
## Проверки (exit 1):
##   • формулы: множитель материала, ❤ по массе с полом PARTHP_MIN, порог отрыва (голова — свой множитель), энергия ядра 12 кг = 80 и
##     головы 4 кг = 20, тяга 480 Н;
##   • ❤ обычной куклы и kit_human совпадают по телам, Σ = запас «Человека»; ❤ чертежа (BodyBlueprint.parts_hp) = ❤ собранной куклы
##     (Doll.part_hp) у всех пресетов; все пресеты и враги PvE (data/enemies) собираются и в режиме (энергия в потолке ядра и головы);
##   • режим выключен: потолок энергии = energy_budget, голова стоит энергии, запас 100, тяга как раньше, суставы по глубине;
##   • режим включён: Match ставит запас = Σ ❤ (с ДРАЙВОМ × 1.5), порог отрыва — от ❤ детали, голова в таблице; урон в предплечье
##     копится, на пороге предплечье отлетает с кистью и уносит их ❤ из запаса и максимума (сигнал parts_hp_changed), reattach_part
##     возвращает; голова на пороге — KO (kind detach); отрыв, после которого запас 0, — KO; выключили — запас снова 100;
##   • ModularDoll: тяга из ядра и головы (thrust_mass), явный thrust_ref_mass важнее;
##   • мастерская: «;» включает режим — в сводке строка «Запас», на карточках ❤, у головы энергия «+N»; выключение возвращает как было.
## В stdout — «=== PART HP PROBE ===» и JSON.
extends Node3D

const DOLL := "res://scenes/doll/doll.tscn"
const PRESETS := "res://scenes/body/presets/"
const HUMAN := "res://scenes/body/presets/kit_human.tscn"
const WORKSHOP := "res://scenes/workshop/workshop_build.tscn"
const EPS := 0.001
const HUMAN_HP := 100.0   # запас «Человека» из деталей — ровно 100 (решение автора 05.10)

var checks: Array = []
var ok := true
var _x := 0.0


func _check(pass_: bool, what: String, detail: Variant = null) -> void:
	checks.append({"ok": pass_, "check": what, "detail": detail})
	ok = ok and pass_
	print("  %s %s  %s" % ["ok  " if pass_ else "FAIL", what, "" if detail == null else str(detail)])


func _spawn(path: String) -> Doll:
	var d := (load(path) as PackedScene).instantiate() as Doll
	d.external_input = true
	d.position = Vector3(_x, 0.0, 0.0)
	_x += 8.0
	add_child(d)
	d.grace_until = -1.0
	return d


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _ready() -> void:
	var was_parts := PartHp.on
	var was_joints := JointBreak.on
	var was_drive := Drive.on
	PartHp.set_on(false)
	JointBreak.set_on(false)
	Drive.set_on(false)
	await _formulas()
	await _consistency()
	await _mode_off()
	await _mode_on()
	await _workshop()
	PartHp.set_on(was_parts)
	JointBreak.set_on(was_joints)
	Drive.set_on(was_drive)
	print("=== PART HP PROBE ===")
	print(JSON.stringify({"ok": ok, "checks": checks}))
	print("=== %s ===" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _formulas() -> void:
	_check(absf(PartHp.mat_factor(0.5) - 1.0) < EPS and absf(PartHp.mat_factor(1.0) - 4.0 / 3.0) < EPS, "множитель материала: дерево 1.0, железо 1.33",
		[PartHp.mat_factor(0.5), PartHp.mat_factor(1.0)])
	_check(PartHp.hp_of(0.5, 0.5) == int(Tuning.PARTHP_MIN) and PartHp.hp_of(4.0, 0.5) == roundi(4.0 * Tuning.PARTHP_PER_KG),
		"❤ = масса × PARTHP_PER_KG × материал, не меньше PARTHP_MIN", [PartHp.hp_of(0.5, 0.5), PartHp.hp_of(4.0, 0.5)])
	_check(absf(PartHp.break_hp(3.0) - Tuning.PARTHP_BREAK_MIN) < EPS and absf(PartHp.break_hp(9.0) - 9.0 * Tuning.PARTHP_BREAK_MULT) < EPS
		and absf(PartHp.break_hp(9.0, true) - 9.0 * Tuning.PARTHP_HEAD_BREAK_MULT) < EPS, "порог отрыва: ❤ × множитель (голова — свой), не меньше PARTHP_BREAK_MIN",
		[PartHp.break_hp(3.0), PartHp.break_hp(9.0), PartHp.break_hp(9.0, true)])
	var core := BodyBlueprint.part_def("kit_human_torso")
	var head := BodyBlueprint.part_def("kit_human_head")
	_check(PartHp.energy_of_core(core) == 80 and PartHp.energy_of_head(head) == 20, "энергия: торс «Человека» 12 кг → 80, голова 4 кг → 20",
		[PartHp.energy_of_core(core), PartHp.energy_of_head(head)])
	_check(absf(PartHp.thrust_n(core) - Tuning.MOVE_FORCE_PER_KG * 40.0) < EPS, "тяга ядра и головы «Человека» = 480 Н, как сейчас", PartHp.thrust_n(core))
	var reactor := BodyBlueprint.part_def("kit_core_pro_reactor")
	var cage := BodyBlueprint.part_def("kit_core_cage")
	_check(PartHp.thrust_of_core(reactor) > PartHp.thrust_of_core(core) and PartHp.thrust_of_core(cage) < PartHp.thrust_of_core(core),
		"моторы разные: реактор сильнее обычного, клетка слабее", [PartHp.thrust_of_core(reactor), PartHp.thrust_of_core(core), PartHp.thrust_of_core(cage)])
	var missing: Array = []
	for id in Tuning.PARTHP_CORE_THRUST:
		var pd := BodyBlueprint.part_def(String(id))
		if pd == null or pd.kind != "core":
			missing.append(id)
	_check(missing.is_empty(), "в таблице моторов только настоящие ядра", missing)


func _consistency() -> void:
	var plain := _spawn(DOLL)
	var kit := _spawn(HUMAN)
	var same := true
	for n in plain.part_hp:
		same = same and int(kit.part_hp.get(n, -1)) == int(plain.part_hp[n])
	_check(same and plain.part_hp.size() == 14 and kit.part_hp.size() == 14, "❤ обычной куклы и kit_human совпадают по телам", plain.part_hp)
	_check(absf(plain.parts_hp_total() - HUMAN_HP) < EPS, "запас «Человека» из деталей — ровно 100", plain.parts_hp_total())
	_check(int(plain.part_hp["Torso"]) > int(plain.part_hp["UpperLeg_L"]) and int(plain.part_hp["UpperLeg_L"]) > int(plain.part_hp["UpperArm_L"])
		and int(plain.part_hp["UpperArm_L"]) > int(plain.part_hp["Hand_L"]), "тяжелее деталь — больше ❤: торс > бедро > плечо > кисть", plain.part_hp)
	plain.queue_free()
	kit.queue_free()
	# ❤ чертежа = ❤ куклы; все пресеты собираются и в режиме
	var mism: Array = []
	var bad_build: Array = []
	var files := DirAccess.get_files_at(PRESETS)
	for f in files:
		if not f.ends_with(".tscn"):
			continue
		var d := _spawn(PRESETS + f) as ModularDoll
		var by := d.blueprint.parts_hp()
		for uid in by:
			var bn := String(d.uid_body.get(uid, ""))
			if int(d.part_hp.get(bn, -1)) != int(by[uid]):
				mism.append("%s:%s %d≠%d" % [f.get_basename(), bn, int(by[uid]), int(d.part_hp.get(bn, -1))])
		if by.size() != d.part_hp.size() or d.blueprint.parts_hp_total() != roundi(d.parts_hp_total()):
			mism.append("%s: тел %d / %d" % [f.get_basename(), by.size(), d.part_hp.size()])
		PartHp.set_on(true)
		var errs := d.blueprint.validate()
		PartHp.set_on(false)
		if not errs.is_empty():
			bad_build.append("%s: %s" % [f.get_basename(), errs[0]])
		d.queue_free()
		await _frames(1)
	_check(mism.is_empty(), "❤ чертежа (BodyBlueprint.parts_hp) = ❤ собранной куклы у всех пресетов", mism.slice(0, 6))
	for f in DirAccess.get_files_at("res://data/enemies/"):   # враги PvE тоже: в режиме (стандарт с 06.10) и без
		var eb := load("res://data/enemies/" + f) as BodyBlueprint
		if eb == null:
			continue
		for on in [true, false]:
			PartHp.set_on(on)
			var ee := eb.validate()
			if not ee.is_empty():
				bad_build.append("%s (режим %s): %s" % [f.get_basename(), on, ee[0]])
		PartHp.set_on(false)
	_check(bad_build.is_empty(), "в режиме и без все пресеты и враги PvE собираются (энергия в потолке ядра и головы)", bad_build)


func _mode_off() -> void:
	var d := _spawn(HUMAN) as ModularDoll
	var m := Match.new()   # не в дереве (см. _mode_on)
	m._parts_hp(d)
	var bp := d.blueprint
	_check(bp.energy_cap() == bp.energy_budget and bp.node_energy(_head_uid(bp)) > 0, "выкл: потолок энергии = energy_budget, голова стоит энергии",
		[bp.energy_cap(), bp.node_energy(_head_uid(bp))])
	_check(is_equal_approx(d.max_hp, Tuning.MAX_HP) and not d.has_meta("parts_hp") and absf(d.thrust_mass() - 40.0) < EPS,
		"выкл: запас 100, тяга как раньше (40 кг)", [d.max_hp, d.thrust_mass()])
	_check(not d.joint_hp.has("Head") and absf(float(d.joint_hp_max["LowerArm_L"]) - JointBreak.hp_for_depth(2)) < EPS,
		"выкл: запасы отрыва по глубине, головы нет", d.joint_hp_max.get("LowerArm_L"))
	var arm := float(d.parts.size())
	d.max_hp = 1000.0
	d.hp = 1000.0
	d.take_damage(200.0, null, "LowerArm_L", Vector3.ZERO, Vector3.UP, "body")
	await _frames(2)
	_check(d.parts.size() == int(arm) and d.alive, "выкл: урон детали не отрывает", d.parts.size())
	d.queue_free()
	m.queue_free()


func _head_uid(bp: BodyBlueprint) -> String:
	for n in bp.nodes:
		var pd := BodyBlueprint.part_def(String(n["part"]))
		if pd != null and pd.kind == "head":
			return String(n["uid"])
	return ""


func _mode_on() -> void:
	PartHp.set_on(true)
	var m := Match.new()   # не в дереве: Match в дереве сам начнёт раунд (begin) и пересчитает запасы по ходу пробы
	var d := _spawn(HUMAN) as ModularDoll
	m._parts_hp(d)
	var bp := d.blueprint
	_check(is_equal_approx(d.max_hp, HUMAN_HP) and is_equal_approx(d.hp, HUMAN_HP) and d.has_meta("parts_hp"), "вкл: Match ставит запас = Σ ❤ деталей (100)", d.max_hp)
	_check(bp.energy_cap() == 100 and bp.node_energy(_head_uid(bp)) == 0, "вкл: энергия от ядра и головы (80 + 20), голова сама не стоит",
		[bp.energy_cap(), bp.node_energy(_head_uid(bp))])
	_check(absf(d.thrust_mass() - PartHp.thrust_n() / Tuning.MOVE_FORCE_PER_KG) < EPS, "вкл: тяга из ядра и головы (thrust_mass)", d.thrust_mass())
	d.refresh_wear()
	_check(absf(float(d.joint_hp_max.get("LowerArm_L", 0.0)) - PartHp.break_hp(float(d.part_hp["LowerArm_L"]))) < EPS
		and absf(float(d.joint_hp_max.get("Head", 0.0)) - PartHp.break_hp(float(d.part_hp["Head"]), true)) < EPS,
		"вкл: порог отрыва — от ❤ детали, голова в таблице", [d.joint_hp_max.get("LowerArm_L"), d.joint_hp_max.get("Head")])
	# износ и отрыв предплечья с кистью
	var deltas: Array = []
	d.parts_hp_changed.connect(func(delta: float, part: String) -> void: deltas.append([delta, part]))
	var thr := float(d.joint_hp_max["LowerArm_L"])
	var lost_hp := float(d.part_hp["LowerArm_L"]) + float(d.part_hp["Hand_L"])
	d.take_damage(thr - 2.0, null, "LowerArm_L", Vector3.ZERO, Vector3.UP, "body")
	await _frames(2)
	_check(d.parts.has("LowerArm_L") and is_equal_approx(d.hp, HUMAN_HP - (thr - 2.0)), "урон копится в предплечье, деталь на месте", d.hp)
	var hp_before := d.hp
	d.take_damage(4.0, null, "LowerArm_L", Vector3.ZERO, Vector3.UP, "body")
	await _frames(2)
	_check(not d.parts.has("LowerArm_L") and not d.parts.has("Hand_L") and d.alive, "на пороге предплечье отлетело вместе с кистью", d.parts.size())
	_check(is_equal_approx(d.max_hp, HUMAN_HP - lost_hp) and is_equal_approx(d.hp, hp_before - 4.0 - lost_hp)
		and deltas.size() == 1 and is_equal_approx(float(deltas[0][0]), -lost_hp) and is_equal_approx(float(d.stats.get("parts_hp_lost", 0.0)), lost_hp),
		"отрыв унёс ❤ предплечья и кисти из запаса и максимума (%d)" % lost_hp, {"hp": d.hp, "max": d.max_hp, "deltas": deltas})
	var lost: Array = d.detached_parts()
	if lost.size() == 1:
		d.reattach_part(lost[0])
		_check(is_equal_approx(d.max_hp, HUMAN_HP) and is_equal_approx(d.hp, hp_before - 4.0) and d.parts.has("Hand_L"), "reattach_part вернул ❤ в запас и максимум", [d.hp, d.max_hp])
	else:
		_check(false, "reattach_part вернул ❤ в запас и максимум", lost.size())
	# голова на пороге — KO
	var ko_kind := [""]
	d.knocked_out.connect(func(_a: Node, rec: Dictionary) -> void: ko_kind[0] = String(rec.get("kind", "")))
	d.max_hp = 1000.0
	d.hp = 1000.0
	d.take_damage(float(d.joint_hp_max["Head"]) + 1.0, null, "Head", Vector3.ZERO, Vector3.UP, "head")
	await _frames(2)
	_check(not d.alive and ko_kind[0] == "detach", "голова на пороге отлетела — KO (kind detach)", ko_kind[0])
	# отрыв, после которого запас 0, — KO
	var k := _spawn(HUMAN) as ModularDoll
	m._parts_hp(k)
	var ko2 := [""]
	k.knocked_out.connect(func(_a: Node, rec: Dictionary) -> void: ko2[0] = String(rec.get("kind", "")))
	var thr2 := float(k.joint_hp_max["UpperLeg_R"])
	k.hp = thr2 + 3.0   # удар отрывает бедро (сам не кладёт), а бедро с голенью и стопой уносит больше, чем осталось
	k.take_damage(thr2 + 1.0, null, "UpperLeg_R", Vector3.ZERO, Vector3.UP, "body")
	await _frames(2)
	_check(not k.alive and ko2[0] == "detach", "отрыв, после которого запас 0, — KO (добивание)", [ko2[0], k.hp])
	# ДРАЙВ
	Drive.set_on(true)
	var dr := _spawn(HUMAN)
	m._parts_hp(dr)
	_check(is_equal_approx(dr.max_hp, roundf(HUMAN_HP * Tuning.DRIVE_MAX_HP / Tuning.MAX_HP)), "с ДРАЙВОМ запас из деталей × 1.5", dr.max_hp)
	Drive.set_on(false)
	dr.queue_free()
	# мотор ядра пресета: титан на реакторе
	var ti := _spawn(PRESETS + "pro_titan.tscn") as ModularDoll
	_check(absf(ti.thrust_mass() - (Tuning.PARTHP_CORE_THRUST["kit_core_pro_reactor"] + Tuning.PARTHP_HEAD_THRUST_N) / Tuning.MOVE_FORCE_PER_KG) < EPS,
		"вкл: у титана тяга от мотора реактора", ti.thrust_mass())
	ti.queue_free()
	# явная тяга пресета важнее
	var t := _spawn(HUMAN) as ModularDoll
	t.thrust_ref_mass = 55.0
	_check(absf(t.thrust_mass() - 55.0) < EPS, "thrust_ref_mass сцены важнее тяги ядра и головы", t.thrust_mass())
	t.queue_free()
	# выключили — запас снова обычный
	var o := _spawn(HUMAN)
	m._parts_hp(o)
	PartHp.set_on(false)
	m._parts_hp(o)
	_check(is_equal_approx(o.max_hp, Tuning.MAX_HP) and is_equal_approx(o.hp, Tuning.MAX_HP) and not o.has_meta("parts_hp"), "режим выключили — запас снова 100", o.max_hp)
	o.queue_free()
	# особый запас (враги PvE) не трогается
	PartHp.set_on(true)
	var e := _spawn(HUMAN)
	e.max_hp = 50.0
	e.hp = 50.0
	m._parts_hp(e)
	_check(is_equal_approx(e.max_hp, 50.0) and not e.has_meta("parts_hp"), "особый запас (враг PvE 50) режим не трогает", e.max_hp)
	e.queue_free()
	PartHp.set_on(false)
	d.queue_free()
	k.queue_free()
	m.queue_free()
	await _frames(2)


func _workshop() -> void:
	WorkshopBuild.prefs_path = "user://workshop_prefs_part_hp_probe.cfg"
	var ws := (load(WORKSHOP) as PackedScene).instantiate() as WorkshopBuild
	ws.load_autosave = false
	ws.autosave_on_test = false
	ws.probe_input = true
	add_child(ws)
	await _frames(10)
	ws.set_preset("kit_human")
	await _frames(4)
	var ui: Node = ws.ui
	var rows_off := _labels(ui.get("summary_rows") as Node)
	ws.toggle_parts_hp()
	await _frames(4)
	var rows_on := _labels(ui.get("summary_rows") as Node)
	var s := ws.body_stats()
	_check(PartHp.on and not rows_off.has(tr("Запас")) and rows_on.has(tr("Запас")) and rows_on.has(str(int(s["hp"]))) and int(s["hp"]) == int(HUMAN_HP),
		"мастерская: «;» включает режим, в сводке «Запас 100»", {"on": rows_on, "hp": s["hp"]})
	_check(int(s["budget"]) == 100 and int(s["energy"]) == ws.blueprint.energy_used(), "мастерская: энергия — потолок ядра и головы", [s["energy"], s["budget"]])
	var cards: Dictionary = ui.get("_cards")
	var hearts := 0
	var head_plus := false
	for id in cards:
		var c: Node = cards[id]
		if not is_instance_valid(c):
			continue
		for n in c.find_children("*", "WsIcon", true, false):
			if String((n as WsIcon).icon) == "heart":
				hearts += 1
		var pd := BodyBlueprint.part_def(String(id))
		if pd != null and pd.kind == "head":
			for l in c.find_children("*", "Label", true, false):
				head_plus = head_plus or String((l as Label).text).begins_with("+")
	_check(hearts > 0 and hearts == cards.size(), "мастерская: на всех карточках полки ❤", [hearts, cards.size()])
	_check(head_plus, "мастерская: голова на полке показывает «+N» энергии (даёт, а не стоит)", head_plus)
	ws.toggle_parts_hp()
	await _frames(4)
	var rows_back := _labels(ui.get("summary_rows") as Node)
	_check(not PartHp.on and not rows_back.has(tr("Запас")) and int(ws.body_stats()["budget"]) == 100, "мастерская: «;» ещё раз — как было", rows_back)
	ws.queue_free()
	await _frames(2)


func _labels(n: Node) -> Array:
	var out: Array = []
	if n == null:
		return out
	for c in n.get_children():
		if c is Label:
			out.append((c as Label).text)
	return out
