## Проба мастерской (scenes/workshop/workshop_build.tscn) — через API WorkshopBuild, без мыши:
##   headless: godot --headless --path . --fixed-fps 60 res://tests/workshop_probe.tscn        → tests/workshop_probe_report.json, 0/1
##   кадры:    godot --path . --resolution 1920x1080 res://tests/workshop_probe.tscn -- "shots=/abs/dir"
##             → <dir>/workshop-build-v1-{build,drag,weapon,test}.png (кукла испытания идёт на манекен сама)
## Проверки (checks[].id):
##   preset_*   — шаблон human: чертёж без ошибок, кукла на стенде собрана (14 тел), тела заморожены и только на слое выбора;
##   targets_*  — для плеча светятся свободные якоря Side_L / Side_R (ok), занятые плечевые — замена; голова — только шея;
##   attach_*   — прикрутить плечо на Side_L и предплечье на его локоть: узел в чертеже, validate() пуст, тело на стенде; призрак
##                (ghost_transform) совпадает с посадкой детали на пересобранном стенде (≤ 1 см, ≤ 1°) — и справа (зеркало);
##   detach_*   — открутить деталь / руку с поддеревом (3 узла), отменить (Ctrl+Z); без головы — понятная ошибка и «испытать» нельзя;
##   energy_*   — перебор энергии: деталь, которая не влезает, не прикручивается, чертёж не меняется, причина «энергии»;
##   stable_*   — пересобранная кукла (плечи на боках, железное предплечье) оживает в испытании: 3 с без взрыва (скорости частей,
##                расстояние до торса), суставы целы;
##   control_*  — пометка управляемой детали: одна (новая заменяет), ядро нельзя, повторный клик снимает;
##   weapon_*   — верстак: пресет молота, гвозди на головку (урон ×1.25, масса +0.4), снять; своё оружие с нуля (длинная рукоять +
##                головка), «В руку» — кисть; без кисти — конец управляемой детали, без управления и кисти — подсказка;
##   test_*     — «испытать»: оружие в кисти (WeaponPickup), кукла летит на манекен — урон по манекену > 0; назад — чертёж тот же;
##   save_*     — сохранить / загрузить чертёж (user://blueprints): одинаковые узлы, управление и оружие.
extends Node

const SCENE := "res://scenes/workshop/workshop_build.tscn"
const REPORT := "res://tests/workshop_probe_report.json"
const STABLE_S := 3.0
const MAX_SPEED := 8.0          # м/с: покой после оживления (g = 2) — быстрее = «взрыв»
const MAX_REACH := 2.6          # м от торса до любой части (самая длинная цепь сборки ≈ 1.6 м)
const MAX_JOINT_GAP := 0.06     # м
const HIT_TIMEOUT_S := 9.0
const GHOST_POS_TOL := 0.01
const GHOST_ANG_TOL := 1.0

var ws: WorkshopBuild
var report := {"ok": true, "checks": []}
var shots_dir := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "shots":
				shots_dir = p[1]
	var ps := load(SCENE) as PackedScene
	ws = ps.instantiate() as WorkshopBuild
	ws.load_autosave = false
	ws.autosave_on_test = false
	ws.probe_input = true
	add_child(ws)
	if shots_dir != "":
		_shots.call_deferred()
	else:
		_run.call_deferred()


func _check(id: String, ok: bool, what: String, value: Variant = null) -> void:
	report["checks"].append({"id": id, "ok": ok, "what": what, "value": value})
	if not ok:
		report["ok"] = false
	print("  %s %-28s %s  %s" % ["ok  " if ok else "FAIL", id, what, "" if value == null else str(value)])


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _wait(s: float) -> void:
	await _frames(int(ceil(s * 60.0)))


func _finish() -> void:
	var f := FileAccess.open(REPORT, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  ", false))
		f.close()
	var fails := 0
	for c in report["checks"]:
		if not bool(c["ok"]):
			fails += 1
	print("WORKSHOP PROBE ", "OK (%d checks)" % report["checks"].size() if fails == 0 else "FAILED (%d of %d)" % [fails, report["checks"].size()])
	get_tree().quit(0 if fails == 0 else 1)


# ------------------------------------------------------------------ headless

func _run() -> void:
	print("=== WORKSHOP PROBE ===")
	await _frames(2)
	await _presets()
	await _targets_attach()
	await _detach()
	await _energy()
	await _stable()
	await _control()
	await _mouse_path()
	await _weapon()
	await _test_hit()
	await _save_load()
	_finish()


func _presets() -> void:
	ws.set_preset("human")
	await _frames(1)
	var bp := ws.blueprint
	_check("preset_human_valid", CraftEdit.friendly_errors(bp).is_empty(), "human без ошибок", CraftEdit.friendly_errors(bp))
	_check("preset_stand_built", ws.stand != null and ws.stand.parts.size() == 14, "кукла на стенде: 14 тел", ws.stand.parts.size() if ws.stand else -1)
	var frozen := true
	var layer_ok := true
	for b in ws.stand.parts.values():
		frozen = frozen and (b as RigidBody3D).freeze
		layer_ok = layer_ok and (b as RigidBody3D).collision_layer == WorkshopBuild.PICK_LAYER
	_check("preset_stand_frozen", frozen and layer_ok, "тела заморожены, только слой выбора")
	_check("preset_energy", bp.energy_used() == 58, "энергия human = 58", bp.energy_used())
	for id in CraftEdit.BODY_PRESETS:
		var p := CraftEdit.load_body_preset(String(id))
		_check("preset_%s_loads" % id, p != null and CraftEdit.friendly_errors(p).is_empty(), "пресет %s собирается" % id)


func _find_target(ts: Array, uid: String, anchor: String) -> Dictionary:
	for t in ts:
		if String(t["uid"]) == uid and String(t["anchor"]) == anchor:
			return t
	return {}


## Кадр детали uid на стенде (её тело) против призрака: [расстояние, угол °].
func _ghost_vs_stand(ghost: Transform3D, uid: String) -> Array:
	var name := String(ws.stand.uid_body.get(uid, ""))
	var body := ws.stand.parts.get(name) as Node3D
	if body == null:
		return [INF, INF]
	var xf := body.global_transform
	var dang := rad_to_deg(absf(wrapf(ModularDoll._rot_z(xf.basis) - ModularDoll._rot_z(ghost.basis), -PI, PI)))
	return [xf.origin.distance_to(ghost.origin), dang]


func _targets_attach() -> void:
	var ts := ws.targets_for("wood_upper_arm", "body")
	var side_l := _find_target(ts, "T", "Anchor_Side_L")
	var side_r := _find_target(ts, "T", "Anchor_Side_R")
	var sh := _find_target(ts, "T", "Anchor_Shoulder_L")
	var neck := _find_target(ts, "T", "Anchor_Neck")
	_check("targets_free_sides", bool(side_l.get("ok", false)) and bool(side_r.get("ok", false)), "Side_L / Side_R светятся для плеча")
	_check("targets_replace", bool(sh.get("ok", false)) and String(sh.get("replace", "")) == "1", "занятое плечо — замена узла 1", sh.get("code", ""))
	_check("targets_neck_dark", not bool(neck.get("accepts", true)), "шея не принимает плечо")
	var hs := ws.targets_for("wood_head", "body")
	var n_head := 0
	for t in hs:
		if bool(t["accepts"]):
			n_head += 1
	_check("targets_head_only_neck", n_head == 1 and String(_find_target(hs, "T", "Anchor_Neck").get("code", "")) == "replace",
		"голова — только на шею (замена)", n_head)
	# плечо на левый бок: призрак = посадка
	var g1: Transform3D = ws.ghost_transform("wood_upper_arm", side_l)["xf"]
	var n0 := ws.blueprint.nodes.size()
	var r := ws.attach_part("wood_upper_arm", "T", "Anchor_Side_L", "body")
	await _frames(1)
	var uid := String(r.get("uid", ""))
	_check("attach_upper_arm", bool(r["ok"]) and ws.blueprint.nodes.size() == n0 + 1 and ws.blueprint.validate().is_empty(),
		"плечо на Side_L: узел + validate пуст", uid)
	var bn := ws.blueprint.body_name_of(uid)
	_check("attach_stand_rebuilt", ws.stand != null and ws.stand.parts.has(bn), "на стенде есть тело %s" % bn)
	var gd := _ghost_vs_stand(g1, uid)
	_check("attach_ghost_side", float(gd[0]) < GHOST_POS_TOL and float(gd[1]) < GHOST_ANG_TOL, "призрак = посадка (м, °)", gd)
	# предплечье на его локоть: поза покоя Elbow (Tuning.POSE 10°)
	var t2 := _find_target(ws.targets_for("wood_lower_arm", "body"), uid, "Anchor_Elbow")
	var g2: Transform3D = ws.ghost_transform("wood_lower_arm", t2)["xf"]
	var r2 := ws.attach_part("wood_lower_arm", uid, "Anchor_Elbow", "body")
	await _frames(1)
	var gd2 := _ghost_vs_stand(g2, String(r2.get("uid", "")))
	_check("attach_ghost_elbow", bool(r2["ok"]) and float(gd2[0]) < GHOST_POS_TOL and float(gd2[1]) < GHOST_ANG_TOL,
		"призрак предплечья = посадка (м, °)", gd2)
	# справа (зеркало): плечо на Side_R и кисть на локоть правой руки человека (узел 8 → Wrist занят → замена)
	var t3 := _find_target(ws.targets_for("wood_upper_arm", "body"), "T", "Anchor_Side_R")
	var g3: Transform3D = ws.ghost_transform("wood_upper_arm", t3)["xf"]
	var r3 := ws.attach_part("wood_upper_arm", "T", "Anchor_Side_R", "body")
	await _frames(1)
	var gd3 := _ghost_vs_stand(g3, String(r3.get("uid", "")))
	_check("attach_ghost_mirror", bool(r3["ok"]) and float(gd3[0]) < GHOST_POS_TOL and float(gd3[1]) < GHOST_ANG_TOL,
		"призрак справа (зеркало) = посадка (м, °)", gd3)
	var t4 := _find_target(ws.targets_for("wood_lower_arm", "body"), String(r3.get("uid", "")), "Anchor_Elbow")
	var g4: Transform3D = ws.ghost_transform("wood_lower_arm", t4)["xf"]
	var r4 := ws.attach_part("wood_lower_arm", String(r3.get("uid", "")), "Anchor_Elbow", "body")
	await _frames(1)
	var gd4 := _ghost_vs_stand(g4, String(r4.get("uid", "")))
	_check("attach_ghost_mirror_elbow", bool(r4["ok"]) and float(gd4[0]) < GHOST_POS_TOL and float(gd4[1]) < GHOST_ANG_TOL,
		"призрак правого предплечья = посадка (м, °)", gd4)
	_check("attach_names_unique", ws.blueprint.validate().is_empty(), "4 новых узла: имена тел/суставов не спорят с human", ws.blueprint.validate())
	# 4 новых узла в историю — откат к human
	for i in range(4):
		ws.undo()
	await _frames(1)
	_check("attach_undo", ws.blueprint.nodes.size() == 14 and ws.blueprint.energy_used() == 58, "Ctrl+Z ×4 → снова human", ws.blueprint.nodes.size())


func _detach() -> void:
	var gone := ws.detach_part("1", "body")
	await _frames(1)
	_check("detach_subtree", gone.size() == 3 and ws.blueprint.nodes.size() == 11 and ws.blueprint.validate().is_empty(),
		"левая рука с поддеревом: 3 узла", gone)
	_check("detach_stand", ws.stand != null and ws.stand.parts.size() == 11, "на стенде 11 тел", ws.stand.parts.size() if ws.stand else -1)
	ws.undo()
	var root_gone := ws.detach_part("T", "body")
	_check("detach_root_refused", root_gone.is_empty() and ws.blueprint.nodes.size() == 14, "ядро не откручивается")
	ws.detach_part("H", "body")
	await _frames(1)
	var errs := CraftEdit.friendly_errors(ws.blueprint)
	_check("detach_head_error", errs.size() >= 1 and String(errs[0]).begins_with("Голова обязательна"), "без головы — «Голова обязательна…»", errs)
	_check("detach_head_stand", ws.stand != null and not ws.stand.parts.has("Head") and ws.stand.parts.size() == 13, "стенд без головы всё равно собран")
	_check("detach_head_no_test", not ws.start_test() and ws.mode == WorkshopBuild.Mode.BUILD, "«испытать» без головы нельзя")
	var rh := ws.attach_part("junk_head_sad", "T", "Anchor_Neck", "body")
	_check("detach_head_back", bool(rh["ok"]) and CraftEdit.friendly_errors(ws.blueprint).is_empty(), "другая голова на шею — снова можно")
	ws.set_preset("human")
	await _frames(1)


func _energy() -> void:
	var r1 := ws.attach_part("wood_upper_arm", "T", "Anchor_Side_L", "body")
	var u1 := String(r1.get("uid", ""))
	var r2 := ws.attach_part("metal_forearm", u1, "Anchor_Elbow", "body")
	var r3 := ws.attach_part("wood_upper_arm", "T", "Anchor_Side_R", "body")
	var u3 := String(r3.get("uid", ""))
	var used := ws.blueprint.energy_used()
	_check("energy_filled", bool(r1["ok"]) and bool(r2["ok"]) and bool(r3["ok"]) and used == 84, "58 + 4 + 18 + 4 = 84", used)
	var c := CraftEdit.check(ws.blueprint, "metal_forearm", u3, "Anchor_Elbow")
	var n0 := ws.blueprint.nodes.size()
	var sig := CraftEdit.signature(ws.blueprint)
	var r4 := ws.attach_part("metal_forearm", u3, "Anchor_Elbow", "body")
	_check("energy_refused", not bool(r4["ok"]) and String(c["code"]) == "energy" and ws.blueprint.nodes.size() == n0
		and CraftEdit.signature(ws.blueprint) == sig and ws.blueprint.energy_used() == 84, "железное предплечье (18) не влезает в 16", c["reason"])
	_check("energy_reason_text", String(c["reason"]).contains("энерги"), "причина — про энергию", c["reason"])
	var t := _find_target(ws.targets_for("metal_forearm", "body"), u3, "Anchor_Elbow")
	_check("energy_anchor_dark", bool(t.get("accepts", false)) and not bool(t.get("ok", true)), "якорь не светится (принимает вид, но энергии нет)")
	var r5 := ws.attach_part("wood_lower_arm", u3, "Anchor_Elbow", "body")
	_check("energy_small_fits", bool(r5["ok"]) and ws.blueprint.energy_used() == 88, "а деревянное (4) влезает", ws.blueprint.energy_used())


func _stable() -> void:
	# сборка из _energy: human + две руки на боках (одна с железным предплечьем)
	var nodes := ws.blueprint.nodes.size()
	var ok := ws.start_test()
	await _frames(1)
	_check("stable_test_started", ok and ws.test_doll != null and ws.test_doll.parts.size() == nodes and ws.test_doll.build_errors.is_empty(),
		"кукла ожила: %d тел, без ошибок сборки" % nodes, ws.test_doll.parts.size() if ws.test_doll else -1)
	var d := ws.test_doll
	var max_v := 0.0
	var max_reach := 0.0
	var max_gap := 0.0
	var finite := true
	for i in range(int(STABLE_S * 60.0)):
		await get_tree().physics_frame
		if not is_instance_valid(d):
			break
		var tp := d.torso().global_position
		for b in d.parts.values():
			var rb := b as RigidBody3D
			max_v = maxf(max_v, rb.linear_velocity.length())
			max_reach = maxf(max_reach, rb.global_position.distance_to(tp))
			finite = finite and rb.global_position.is_finite()
		for j in d.joints.values():
			max_gap = maxf(max_gap, _joint_gap(j as Generic6DOFJoint3D, d))
	_check("stable_speed", finite and max_v < MAX_SPEED, "3 с покоя: скорость частей < %.0f м/с" % MAX_SPEED, snappedf(max_v, 0.01))
	_check("stable_reach", max_reach < MAX_REACH, "части не разлетелись (< %.1f м от торса)" % MAX_REACH, snappedf(max_reach, 0.001))
	_check("stable_joints", max_gap < MAX_JOINT_GAP, "суставы целы (зазор < %.2f м)" % MAX_JOINT_GAP, snappedf(max_gap, 0.0001))
	ws.stop_test()
	await _frames(1)
	_check("stable_back", ws.mode == WorkshopBuild.Mode.BUILD and ws.stand != null and ws.blueprint.nodes.size() == nodes, "назад к сборке, чертёж тот же")


## Расхождение точки сустава на двух телах (по кадрам сборки ModularDoll.assembly).
func _joint_gap(j: Generic6DOFJoint3D, d: ModularDoll) -> float:
	var a := j.get_node_or_null(j.node_a) as RigidBody3D
	var b := j.get_node_or_null(j.node_b) as RigidBody3D
	if a == null or b == null:
		return 0.0
	var pa := a.global_transform * ((d.assembly[String(a.name)] as Transform3D).affine_inverse() * j.position)
	var pb := b.global_transform * ((d.assembly[String(b.name)] as Transform3D).affine_inverse() * j.position)
	return pa.distance_to(pb)


func _control() -> void:
	ws.set_preset("human")
	await _frames(1)
	_check("control_preset", ws.blueprint.control == PackedStringArray(["9"]), "human: рука мышью — кисть 9")
	var r := ws.set_control("8")
	_check("control_replace", bool(r["ok"]) and ws.blueprint.control == PackedStringArray(["8"]), "новая пометка заменяет (≤ 1)", ws.blueprint.control)
	var glow := false
	for m in ws.part_meshes("body", "8"):
		glow = glow or _has_overlay(m)
	_check("control_glow", glow, "помеченная деталь светится (material_overlay)")
	var rt := ws.set_control("T")
	_check("control_core_refused", not bool(rt["ok"]) and ws.blueprint.control == PackedStringArray(["8"]), "ядро нельзя", rt.get("reason", ""))
	var rc := ws.set_control("8")
	_check("control_toggle_off", bool(rc["ok"]) and ws.blueprint.control.is_empty(), "повторный клик снимает")
	_check("control_warning", CraftEdit.warnings(ws.blueprint).size() == 1, "без руки мышью — подсказка", CraftEdit.warnings(ws.blueprint))
	ws.set_control("9")


## То, что делает мышь, но через экранные точки: луч по детали на стенде (и по слитой броне), протяжка → отпускание у якоря.
func _mouse_path() -> void:
	ws.set_preset("human")
	await _frames(2)
	var cam := get_viewport().get_camera_3d()
	var hand := ws.stand.parts["Hand_R"] as Node3D
	var h := ws.pick(cam.unproject_position(hand.global_position))
	_check("pick_hand", String(h.get("uid", "")) == "9" and String(h.get("target", "")) == "body", "луч из камеры по кисти → узел 9", h)
	# железное предплечье вместо деревянного (замена, кисть остаётся) и щиток на него (fixed: сливается с предплечьем)
	var r1 := ws.attach_part("metal_forearm", "7", "Anchor_Elbow", "body")
	var r2 := ws.attach_part("shield_plate", "8", "Anchor_Plate", "body")
	await _frames(2)
	var plate := String(r2.get("uid", ""))
	_check("pick_replace_keeps_child", bool(r1["ok"]) and String(r1.get("replace", "")) == "8" and not CraftEdit.find(ws.blueprint, "9").is_empty()
		and ws.blueprint.energy_used() == 84, "замена предплечья: кисть осталась, энергия 58 − 4 + 18 + 12", ws.blueprint.energy_used())
	var ms := ws.part_meshes("body", plate)
	var hp := {}
	if not ms.is_empty():
		hp = ws.pick(cam.unproject_position(WorkshopBuild._visual_aabb(ms[0]).get_center()))
	_check("pick_fixed_part", bool(r2["ok"]) and String(hp.get("uid", "")) == plate, "луч по щитку → его узел (слит с предплечьем)", [plate, hp])
	# протяжка экранными точками: плечо на свободный бок
	ws.set_preset("human")
	await _frames(1)
	ws.begin_drag("wood_upper_arm", Vector2(200, 600))
	var n_ok := 0
	for it in ws.overlay_items():
		if String(it["state"]) == "ok" or String(it["state"]) == "target":
			n_ok += 1
	_check("drag_overlay", n_ok == 2, "светятся 2 свободных якоря (бока)", n_ok)
	var t := _find_target(ws.drag["targets"], "T", "Anchor_Side_R")
	var sp := ws.target_screen_pos(t)
	ws.update_drag(sp + Vector2(30, -20))
	var chosen := ws.drag_target()
	_check("drag_snap", String(chosen.get("anchor", "")) == "Anchor_Side_R" and ws.get("_ghost") != null, "у якоря — прилипание и призрак")
	var n0 := ws.blueprint.nodes.size()
	var r := ws.end_drag(sp + Vector2(30, -20))
	_check("drag_drop_attach", bool(r.get("ok", false)) and ws.blueprint.nodes.size() == n0 + 1 and ws.drag.is_empty(), "отпустил — прикручено")
	ws.begin_drag("wood_upper_arm", Vector2(200, 600))
	var r_miss := ws.end_drag(Vector2(960, 60))
	_check("drag_miss", not bool(r_miss.get("ok", true)) and ws.blueprint.nodes.size() == n0 + 1, "мимо якоря — ничего не поменялось")
	ws.set_preset("human")


func _has_overlay(n: Node) -> bool:
	if n is GeometryInstance3D and (n as GeometryInstance3D).material_overlay != null:
		return true
	for c in n.get_children():
		if _has_overlay(c):
			return true
	return false


func _weapon() -> void:
	ws.set_view(WorkshopBuild.View.WEAPON)
	ws.set_weapon_preset("hammer")
	await _frames(1)
	_check("weapon_bench_built", ws.bench_weapon != null and ws.weapon_bp.nodes.size() == 2, "молот на верстаке")
	var s0: Dictionary = ws.bench_weapon.summary()
	var ts := ws.targets_for("mod_nails", "weapon")
	var n_ok := 0
	for t in ts:
		if bool(t["ok"]):
			n_ok += 1
	_check("weapon_targets", n_ok >= 2, "гвозди: светятся якоря головки/рукояти", n_ok)
	var r := ws.attach_part("mod_nails", "1", "Anchor_Face_L", "weapon")
	await _frames(1)
	var s1: Dictionary = ws.bench_weapon.summary() if ws.bench_weapon else {}
	_check("weapon_nails", bool(r["ok"]) and ws.weapon_bp.nodes.size() == 3 and is_equal_approx(float(s1.get("damage_mult", 0)), 1.25)
		and absf(float(s1.get("mass", 0)) - float(s0["mass"]) - 0.4) < 0.01, "гвозди: урон ×1.25, масса +0.4",
		[s0["mass"], s1.get("mass"), s1.get("damage_mult")])
	var wr := ws.weapon_stats()
	_check("weapon_words", (wr["rows"] as Array).size() == 5 and String((wr["rows"] as Array)[4]["word"]) != "", "характеристики словами", (wr["rows"] as Array).map(func(x: Dictionary) -> String: return "%s: %s — %s" % [x["label"], x["value"], x["word"]]))
	ws.detach_part(String(r.get("uid", "")), "weapon")
	await _frames(1)
	_check("weapon_detach", ws.weapon_bp.nodes.size() == 2, "гвозди сняты")
	ws.clear_weapon()
	await _frames(1)
	_check("weapon_clear", ws.weapon_bp.nodes.is_empty() and ws.bench_weapon == null, "верстак пуст")
	var rr := ws.attach_part("handle_long", "", "", "weapon")
	var rh := ws.attach_part("head_hammer", "0", "Anchor_Head", "weapon")
	await _frames(1)
	var s2: Dictionary = ws.bench_weapon.summary() if ws.bench_weapon else {}
	var want := CraftEdit.part("handle_long").mass + CraftEdit.part("head_hammer").mass
	_check("weapon_from_scratch", bool(rr["ok"]) and bool(rh["ok"]) and absf(float(s2.get("mass", 0)) - want) < 0.01 and float(s2.get("length", 0)) > 1.0,
		"своё оружие: длинная рукоять + головка", [s2.get("mass"), s2.get("length"), s2.get("com_from_grip"), s2.get("inertia_grip")])
	var eq := ws.weapon_to_hand()
	_check("weapon_to_hand", bool(eq["ok"]) and ws.blueprint.weapon != null and ws.blueprint.weapon_on == "9" and String(eq["kind"]) == "hand",
		"«В руку» → кисть 9 (рука мышью)", eq)
	_check("weapon_held_on_stand", ws.held_weapon != null, "на стенде оружие в кисти")
	# крепление без кисти
	var bp := CraftEdit.load_body_preset("human")
	CraftEdit.detach(bp, "9")
	var m1 := CraftEdit.weapon_mount(bp)
	_check("weapon_mount_other_hand", String(m1["uid"]) == "3" and String(m1["kind"]) == "hand", "нет правой кисти — левая", m1)
	CraftEdit.detach(bp, "3")
	var m2 := CraftEdit.weapon_mount(bp)
	_check("weapon_mount_none", String(m2["uid"]) == "" and String(m2["reason"]) != "", "без кистей и руки мышью — подсказка", m2["reason"])
	CraftEdit.set_control(bp, "8")
	var m3 := CraftEdit.weapon_mount(bp)
	_check("weapon_mount_end", String(m3["uid"]) == "8" and String(m3["kind"]) == "end", "без кистей — конец управляемой детали", m3)
	ws.set_view(WorkshopBuild.View.BODY)


func _test_hit() -> void:
	var sig := CraftEdit.signature(ws.blueprint)
	var ok := ws.start_test()
	await _frames(2)
	var d := ws.test_doll
	var pickup := d.get_node_or_null("WeaponPickup") as WeaponPickup if d != null else null
	var hand := String(d.uid_body.get("9", "")) if d != null else ""
	_check("test_started", ok and d != null and ws.dummy != null, "испытание: кукла и манекен")
	_check("test_weapon_in_hand", pickup != null and pickup.is_holding(hand) and pickup.weapon_in(hand) is CraftedWeapon,
		"крафтовое оружие в кисти %s" % hand)
	_check("test_arm_assist", d != null and d.get_node_or_null("ArmAssist") != null, "рука мышью (ArmAssist) на кукле")
	var dummy_doll: Doll = ws.dummy.get("doll")
	var arm := d.get_node_or_null("ArmAssist") as ArmAssist if d != null else null
	var t := 0.0
	var dmg := 0.0
	var first_t := -1.0
	var hits: Array = []
	ws.dummy_hit.connect(func(a: float, _p: Vector3, part: String, kind: String) -> void: hits.append("%s %s %.1f" % [kind, part, a]))
	# на манекен с разбега, у манекена — мах рукой с оружием (рука мышью к голове манекена, вверх-вниз)
	while t < HIT_TIMEOUT_S:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if not is_instance_valid(d) or not d.alive:
			break
		dummy_doll = ws.dummy.get("doll")
		if dummy_doll != null and is_instance_valid(dummy_doll) and dummy_doll.alive:
			var dx := dummy_doll.torso().global_position.x - d.torso().global_position.x
			var dy := dummy_doll.torso().global_position.y - d.torso().global_position.y
			d.input_vec = Vector2(signf(dx), clampf(dy, -0.5, 0.6)).limit_length(1.0)
			if arm != null and absf(dx) < 2.0:
				arm.set_target_override(dummy_doll.head().global_position + Vector3(0.0, 0.6 * sin(t * 8.0), 0.0))
		dmg = float(ws.dummy.get("total_damage"))
		if dmg > 0.0 and first_t < 0.0:
			first_t = t
		if first_t >= 0.0 and (t - first_t > 2.5 or dmg >= 20.0):
			break
	d.input_vec = Vector2.ZERO
	var lh: Dictionary = ws.dummy.get("last_hit")
	_check("test_dummy_damaged", dmg > 0.0, "удар по манекену даёт урон", {"damage": snappedf(dmg, 0.1), "first_hit_t": snappedf(first_t, 0.01),
		"hits": hits, "hp_left": snappedf(float(ws.dummy.call("hp")), 0.1)})
	report["test_hits"] = hits
	ws.stop_test()
	await _frames(1)
	_check("test_back_same", ws.mode == WorkshopBuild.Mode.BUILD and CraftEdit.signature(ws.blueprint) == sig and ws.stand != null,
		"Esc — назад, чертёж тот же")


func _save_load() -> void:
	ws.set_control("8")
	var sig := CraftEdit.signature(ws.blueprint)
	var wsig := CraftEdit.signature(ws.blueprint.weapon) if ws.blueprint.weapon != null else PackedStringArray()
	var ctrl := ws.blueprint.control.duplicate()
	var path := ws.save_as("Проба мастерской")
	_check("save_file", path != "" and FileAccess.file_exists(path), "сохранено в %s" % path)
	ws.set_preset("spider")
	await _frames(1)
	var ok := ws.load_path(path)
	await _frames(1)
	var wsig2 := CraftEdit.signature(ws.blueprint.weapon) if ws.blueprint.weapon != null else PackedStringArray()
	_check("save_same_nodes", ok and CraftEdit.signature(ws.blueprint) == sig, "загрузка: те же узлы", ws.blueprint.nodes.size())
	_check("save_same_extra", ws.blueprint.control == ctrl and wsig2 == wsig and not wsig.is_empty(), "та же рука мышью и оружие", [ws.blueprint.control, wsig2.size()])
	var listed := false
	for it in CraftEdit.list_saved():
		listed = listed or String(it["path"]) == path
	_check("save_listed", listed, "в списке «Загрузить»")
	if path != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ------------------------------------------------------------------ кадры (не headless)

func _shots() -> void:
	DirAccess.make_dir_recursive_absolute(shots_dir)
	get_viewport().msaa_3d = Viewport.MSAA_4X
	await _frames(3)
	var icons: PartIcons = ws.ui.get("icons")
	# все иконки полок — заранее (карточки берут из кэша)
	for d in CraftEdit.all_parts():
		icons.request(d.id)
	var t := 0.0
	while icons.pending() > 0 and t < 15.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	ws.set_preset("human")
	ws.set_view(WorkshopBuild.View.WEAPON)
	ws.set_weapon_preset("hammer")
	ws.attach_part("mod_nails", "1", "Anchor_Face_L", "weapon")
	ws.weapon_to_hand()
	ws.set_view(WorkshopBuild.View.BODY)
	ws.attach_part("wood_upper_arm", "T", "Anchor_Side_L", "body")
	await _wait(1.2)
	await _shot("build")
	# протяжка: кисть-колотушка к локтю нового плеча (свободный якорь) — якоря светятся, призрак на месте
	var nu := ""
	for n in ws.blueprint.nodes:
		if String(n.get("part", "")) == "wood_upper_arm" and String(n.get("anchor", "")) == "Anchor_Side_L":
			nu = String(n["uid"])
	ws.begin_drag("wood_lower_arm", Vector2(300, 700))
	var tt := _find_target(ws.drag["targets"], nu, "Anchor_Elbow")
	if not tt.is_empty():
		var p := ws.target_screen_pos(tt) + Vector2(24, 18)
		for i in range(12):
			ws.update_drag(Vector2(300, 700).lerp(p, float(i + 1) / 12.0))
			await get_tree().process_frame
	await _wait(0.3)
	await _shot("drag")
	ws.cancel_drag()
	# верстак: тяжёлый молот, тащим гвозди с полки «Моды» — якоря головки и рукояти светятся
	ws.set_view(WorkshopBuild.View.WEAPON)
	(ws.ui.get("shelf_tab") as Dictionary)["weapon"] = "mod"
	ws.ui.call("_build_left")
	ws.set_weapon_preset("heavy_hammer")
	await _wait(0.8)
	ws.begin_drag("mod_nails", Vector2(300, 700))
	var wt := {}
	for tg in ws.drag["targets"]:
		if bool(tg["ok"]) and String(tg["replace"]) == "" and (wt.is_empty() or String(tg["anchor"]).begins_with("Anchor_Face")):
			wt = tg
	if not wt.is_empty():
		var p2 := ws.target_screen_pos(wt) + Vector2(20, 14)
		for i in range(10):
			ws.update_drag(Vector2(300, 700).lerp(p2, float(i + 1) / 10.0))
			await get_tree().process_frame
	await _wait(0.3)
	await _shot("weapon")
	ws.cancel_drag()
	ws.set_view(WorkshopBuild.View.BODY)
	# испытание: подлёт к манекену с замахом (рука мышью за спину и вверх), удар молотом сверху; кадр сразу после удара
	ws.start_test()
	await _frames(2)
	var d := ws.test_doll
	var arm: ArmAssist = d.get_node_or_null("ArmAssist")
	var hit_t := -1.0
	var swing_t := -1.0
	var best := 0.0
	t = 0.0
	while t < 12.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		var dd: Doll = ws.dummy.get("doll")
		if dd == null or not is_instance_valid(dd) or not is_instance_valid(d) or not d.alive:
			continue
		var tp := d.torso().global_position
		var dx := dd.torso().global_position.x - tp.x
		var s := signf(dx)
		if swing_t < 0.0:
			d.input_vec = Vector2(s, 0.15) if absf(dx) > 1.35 else Vector2.ZERO
			if arm != null:
				arm.set_target_override(tp + Vector3(-s * 0.35, 0.75, 0))   # замах: за голову
			if absf(dx) <= 1.35 and t > 1.2:
				swing_t = t
		else:
			d.input_vec = Vector2(s * 0.5, 0.0)
			if arm != null:
				arm.set_target_override(dd.head().global_position + Vector3(-s * 0.1, -0.35, 0))
			if t - swing_t > 0.9 and hit_t < 0.0:
				swing_t = -1.0   # мимо — ещё замах
		var dmg := float(ws.dummy.get("total_damage"))
		var lh: Dictionary = ws.dummy.get("last_hit")
		if dmg > best:
			best = dmg
			if float(lh.get("amount", 0.0)) >= 4.0 and hit_t < 0.0:
				hit_t = t
		if hit_t >= 0.0 and t - hit_t > 0.2:
			break
	await _shot("test")
	get_tree().quit(0)


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := shots_dir.path_join("workshop-build-v1-%s.png" % tag)
	var err := img.save_png(path)
	print("saved ", path, " (", err, ")")
