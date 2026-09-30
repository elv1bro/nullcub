## Проба мастерской (scenes/workshop/workshop_build.tscn) — через API WorkshopBuild, без мыши:
##   headless: godot --headless --path . --fixed-fps 60 res://tests/workshop_probe.tscn        → tests/workshop_probe_report.json, 0/1
##   кадры:    godot --path . --resolution 1920x1080 res://tests/workshop_probe.tscn -- "shots=/abs/dir"
##             → <dir>/workshop-build-v1-{build,drag,weapon,test}.png (кукла испытания идёт на манекен сама) и кадры кита v2
##               workshop-build-v1-kit-{mat,joint,armor,limb,head,core}.png (кисть, шарниры, призрак рогов, полки с иконками кита),
##               покраска workshop-build-v1-paint{,-stencil,-presets}.png (баллончик с кольцом, трафарет и наклейка; сетка трафаретов
##               с превью; витрина kit_graffiti на раскрасках)
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
##   save_*     — сохранить / загрузить чертёж (user://blueprints): одинаковые узлы, управление и оружие;
##   кит тела v2 (docs/plan-demo/BODY_KIT.md §5.5):
##   shelves_*  — вкладки полки: ядро / головы / конечности / кисти-стопы / броня-декор со своими деталями кита, «Шарниры» и
##                «Материал» — инструменты (плашки в UI: 15 материалов, 5 типов шарнира); детали второй волны — на своих вкладках
##                (навершия kit_weapons — на «Броня, декор»); kit_human_* на полках нет (дубли wood_*), но PartDef грузится;
##   kit_preset_<id>_loads — каждый пресет кита: без ошибок, на стенде столько тел, сколько узлов не is_fixed;
##   mat_*      — кисть: железо на плечо kit_human (узел mat, поверхность Base_ → Base_Iron, физматериал, масса ×2.2), материал по
##                умолчанию стирает ключ, Ctrl+Z; деревянная деталь human — отказ «не красится»; клик мышью кистью; ПКМ кладёт кисть,
##                а не откручивает; замена детали сохраняет mat только у детали с base_mat; сохранение / загрузка с mat и joint;
##   joint_*    — шарнир: свободный локоть (meta joint_type сустава стенда), мотор (+8 энергии), сварка кисти (тел на одно меньше,
##                луч по сваренной кисти — её узел), отказы (корень, голова, рука мышью, auto-сустав ребёнка, декор), Ctrl+Z,
##                клик мышью, Esc кладёт инструмент, кружки типов на суставах;
##   kit_test_live — сборка кита с материалом и шарнирами оживает в испытании: 1.5 с без взрыва;
##   покраска (docs/plan-demo/BODY_PAINT.md §6; WorkshopPaint, курсор — из API, virtual_mouse):
##   paint_*    — вкладка «Покраска» (полка, шаблоны спрятаны, баллончик); штрих баллончиком по экранным точкам меняет живой слой
##                плеча и node.paint (тот же слой), одна запись истории на штрих; симметрия красит правое плечо; Shirt* / Face* без
##                краски; ластик; Ctrl+Z; сохранить / загрузить (узлы, байты слоя, наклейка, фото); раскраска всей куклы — по кадрам,
##                каждая деталь, одна запись; старая кукла human тоже красится; поворот стенда (тела едут, физлуч попадает);
##                Esc и «Испытать» кладут баллончик; витрина kit_graffiti / kit_camo собирается с краской и трафаретами;
##   sticker_*  — трафарет-звезда на груди (одна, у оси симметрии; меш-наклейка, не Decal), колесо — больше, Q — +15°, тащить —
##                переезд, ПКМ — снять; наклейка на плечо — с парой на другом плече;
##   face_import_fixture — tests/fixtures/paint/sticker_fixture.png через import_files → node.face головы, плашка лица с картинкой;
##   paint_replace_drops — замена детали снимает её paint / stickers, фото на заменённой голове кита остаётся;
##   правки ревью покраски (_paint_fixes): paint_brush_min_radius — кисть 1 см на ядре kit_human (ячейка 14 мм): каждый мазок
##                красит; paint_noop_stroke — штрих, который ничего не поменял, — без записи истории и «*»; paint_trackpad_size —
##                прокрутка / щипок трекпада (InputEventPanGesture / MagnifyGesture) меняют размер кисти и наклейки;
##                sticker_axis_single — наклейка 12 см в 3 см от оси — одна, на оси; face_legacy_* — старая голова: фото
##                наклейкой одно (повтор — без записи), клик в 3D мимо головы — ничего, «Снять фото» снимает, повторно — нечего;
##                face_kit_same_noop — то же фото на голову кита — без записи; paint_replace_face — замена головы кита на
##                wood_head / metal_head / junk_head_sad снимает face (face_lost), у kit_head_* — остаётся; face_replace_live —
##                в мастерской фото переезжает наклейкой на новую старую голову той же записью истории; pattern_legacy_mirror —
##                раскраска плеча старой human: правое — зеркальная копия левого (байт в байт), у кита — одинаковые байты;
##                pattern_frame_budget — раскраска всей куклы: кадр очереди ≤ PATTERN_FRAME_MAX_MS; import_async — импорт в
##                потоке; image_delete_used — картинку на кукле не удалить; autosave_edits — правка краски через 2 с — в файле
##                автосейва (своё имя, не _autosave);
##   правки ревью кита: control_rehost_* — навершие вместо управляемой кисти (kit_devil — бур, human — шар булавы): рука мышью на
##                теле-хозяине, в испытании ArmAssist ведёт предплечье; control_cleared_on_core — хозяин ядро: пометка снята;
##                joint_motor_ankle_refused — мотор на стопе (сустав без мышцы) — отказ; joint_refusal_words — отказы словами
##                игрока (без uid / Anchor_ / auto), «приваренный конец» — код welded; limb_elbow_name — конечность кита на локте —
##                тело LowerArm_<uid>.
extends Node

const SCENE := "res://scenes/workshop/workshop_build.tscn"
const REPORT := "res://tests/workshop_probe_report.json"
const HUMAN_ENERGY := 82       # энергия human с ценой выноса (BodyBlueprint.reach_mult, WORKSHOP_V3.md §2); без выноса было 58
const STABLE_S := 3.0
const MAX_SPEED := 8.0          # м/с: покой после оживления (g = 2) — быстрее = «взрыв»
const MAX_REACH := 2.6          # м от торса до любой части (самая длинная цепь сборки ≈ 1.6 м)
const MAX_JOINT_GAP := 0.06     # м
const HIT_TIMEOUT_S := 9.0
const GHOST_POS_TOL := 0.01
const GHOST_ANG_TOL := 1.0
const PATTERN_FRAME_MAX_MS := 20.0   # шаг очереди раскраски (бюджет 4 мс + срез) — с запасом на headless под нагрузкой

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

## Σ BodyBlueprint.node_energy — energy_used() обязан совпадать с ценами узлов, которые видит игрок.
func _sum_node_energy(bp: BodyBlueprint) -> int:
	var t := 0
	for n in bp.nodes:
		t += bp.node_energy(String(n["uid"]))
	return t


## UI v0.2 (мастерская «как в ААА»): характеристики, выбор, УСТАНОВИТЬ / ДУБЛИКАТ / ЗЕРКАЛО / УДАЛИТЬ, Redo, Physics Overlay.
func _ui_v02() -> void:
	ws.set_preset("kit_human")
	await _frames(2)
	var st := ws.body_stats()
	var in01 := true
	for k in ["handling", "stability", "durability"]:
		in01 = in01 and float(st[k]) >= 0.0 and float(st[k]) <= 1.0
	_check("v02_stats", in01 and float(st["stability"]) > 0.05 and ws.stand_com().y > 0.2, "характеристики 0…1, ЦМ над полом",
		[st["handling"], st["stability"], st["durability"], snappedf(ws.stand_com().y, 0.01)])
	# УСТАНОВИТЬ: левая кисть снята → из каталога ставится на свободный разъём, выбор — на неё
	ws.detach_part("3")
	await _frames(1)
	var n0 := ws.blueprint.nodes.size()
	ws.select_shelf("kit_human_hand")
	var ri := ws.install_part("kit_hand_mitten")
	await _frames(1)
	_check("v02_install", bool(ri.get("ok", false)) and ws.blueprint.nodes.size() == n0 + 1 and String(ws.selected.get("source", "")) == "stand"
		and ws.blueprint.validate().is_empty(), "УСТАНОВИТЬ: деталь на свободный разъём, выбрана на кукле", [ri.get("code", ""), ws.selected])
	# ЗЕРКАЛО: левая рука снята целиком → копия правой (плечо, предплечье, кисть) на левую сторону; голова — по центру, отказ
	ws.set_preset("kit_human")
	await _frames(1)
	ws.detach_part("1")
	var n1 := ws.blueprint.nodes.size()
	var rm := ws.mirror_part("7")
	await _frames(1)
	var left_ok := CraftEdit.occupant(ws.blueprint, "T", "Anchor_Shoulder_L") != ""
	_check("v02_mirror", bool(rm.get("ok", false)) and int(rm.get("count", 0)) == 3 and ws.blueprint.nodes.size() == n1 + 3 and left_ok
		and ws.blueprint.validate().is_empty(), "ЗЕРКАЛО: правая рука (3 детали) — на левое плечо", [rm.get("count", 0), rm.get("reason", "")])
	var rc := ws.mirror_part("H")
	_check("v02_mirror_center", not bool(rc.get("ok", true)) and String(rc.get("code", "")) == "center", "голова по центру — зеркалить некуда", rc.get("code", ""))
	# Undo / Redo
	var n_after := ws.blueprint.nodes.size()
	ws.undo()
	await _frames(1)
	var n_undo := ws.blueprint.nodes.size()
	ws.redo()
	await _frames(1)
	_check("v02_redo", n_undo == n1 and ws.blueprint.nodes.size() == n_after and ws.redo_stack.is_empty(), "Ctrl+Z → без руки, Ctrl+Y → снова с рукой",
		[n_undo, ws.blueprint.nodes.size()])
	ws.undo()
	ws.detach_part("H")
	_check("v02_redo_cleared", ws.redo_stack.is_empty(), "новая правка чистит Redo", ws.redo_stack.size())
	# ДУБЛИКАТ: правое плечо (7) — на свободный разъём (бок), материал тот же
	ws.set_preset("kit_human")
	await _frames(1)
	var n2 := ws.blueprint.nodes.size()
	var rd := ws.duplicate_part("7")
	await _frames(1)
	_check("v02_duplicate", bool(rd.get("ok", false)) and ws.blueprint.nodes.size() == n2 + 1
		and String(CraftEdit.find(ws.blueprint, String(rd.get("uid", ""))).get("part", "")) == String(CraftEdit.find(ws.blueprint, "7").get("part", "")),
		"ДУБЛИКАТ: та же деталь на свободный разъём", [rd.get("uid", ""), rd.get("reason", "")])
	# УДАЛИТЬ выбранное
	ws.select_stand("C")
	var gone := ws.delete_selected()
	_check("v02_delete", gone.size() >= 1 and ws.selected.is_empty() and CraftEdit.find(ws.blueprint, "C").is_empty(), "УДАЛИТЬ: выбранная стопа снята, выбор сброшен", gone)
	# Physics Overlay: при протяжке несовместимые разъёмы приглушены, у выбранного разъёма — сдвиг ЦМ
	ws.set_preset("kit_human")
	await _frames(1)
	ws.detach_part("3")
	await _frames(1)
	var cam := get_viewport().get_camera_3d()
	ws.begin_drag("kit_hand_mitten", Vector2(300, 600))
	var tgt := _find_target(ws.targets_for("kit_hand_mitten"), "2", "Anchor_End")
	if tgt.is_empty():
		tgt = _find_target(ws.targets_for("kit_hand_mitten"), "2", "Anchor_Wrist")
	var dims := 0
	var com_items := 0
	if not tgt.is_empty():
		ws.update_drag(ws.target_screen_pos(tgt))
		await _frames(1)
		for it in ws.overlay_items():
			dims += 1 if String(it["state"]) == "dim" else 0
			com_items += 1 if String(it["state"]) in ["com", "com_ghost"] else 0
	var dc: Variant = ws.drag_com()
	ws.cancel_drag()
	_check("v02_overlay", dims > 0 and com_items == 2 and dc is Vector3, "протяжка: несовместимые разъёмы приглушены, ЦМ и его сдвиг", [dims, com_items, dc])
	ws.set_preset("human")
	ws.history.clear()
	ws.redo_stack.clear()
	await _frames(1)


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
	await _ui_v02()
	await _kit_shelves()
	await _kit_presets()
	await _kit_material()
	await _kit_joint()
	await _kit_save_live()
	await _kit_fixes()
	await _paint()
	await _paint_fixes()
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
	# энергия по расстоянию (WORKSHOP_V3.md §2): 58 без выноса → 82 (кисти и стопы дальше от ядра — дороже)
	_check("preset_energy", bp.energy_used() == HUMAN_ENERGY and bp.energy_used() == _sum_node_energy(bp), "энергия human = %d" % HUMAN_ENERGY,
		bp.energy_used())
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
	# плечо на левый бок: призрак = посадка. Здесь проверяется посадка, не энергия: 4 новых узла на human не влезли бы в 100
	ws.blueprint.energy_budget = 1000
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
	ws.blueprint.energy_budget = 100
	_check("attach_undo", ws.blueprint.nodes.size() == 14 and ws.blueprint.energy_used() == HUMAN_ENERGY, "Ctrl+Z ×4 → снова human", ws.blueprint.nodes.size())


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
	# энергия по расстоянию (WORKSHOP_V3.md §2): сначала снять левую ногу — на human (82 / 100) две руки с железом не встанут
	var e0 := ws.blueprint.energy_used()
	var leg := 0
	for u in ["4", "5", "6"]:
		leg += ws.blueprint.node_energy(u)
	ws.detach_part("4", "body")
	var r1 := ws.attach_part("wood_upper_arm", "T", "Anchor_Side_L", "body")
	var u1 := String(r1.get("uid", ""))
	var r2 := ws.attach_part("metal_forearm", u1, "Anchor_Elbow", "body")
	var r3 := ws.attach_part("wood_upper_arm", "T", "Anchor_Side_R", "body")
	var u3 := String(r3.get("uid", ""))
	var used := ws.blueprint.energy_used()
	var want := e0 - leg
	for u in [u1, String(r2.get("uid", "")), u3]:
		want += ws.blueprint.node_energy(u)
	_check("energy_filled", bool(r1["ok"]) and bool(r2["ok"]) and bool(r3["ok"]) and used == want and used == _sum_node_energy(ws.blueprint),
		"human − левая нога + плечо + железное предплечье + плечо = Σ цен узлов", [used, want])
	_check("energy_reach_costs_more", ws.blueprint.node_energy(String(r2.get("uid", ""))) > CraftEdit.part("metal_forearm").energy,
		"железное предплечье на локте дороже своей базовой цены (вынос от ядра)", ws.blueprint.node_energy(String(r2.get("uid", ""))))
	var c := CraftEdit.check(ws.blueprint, "metal_forearm", u3, "Anchor_Elbow")
	var n0 := ws.blueprint.nodes.size()
	var sig := CraftEdit.signature(ws.blueprint)
	var r4 := ws.attach_part("metal_forearm", u3, "Anchor_Elbow", "body")
	_check("energy_refused", not bool(r4["ok"]) and String(c["code"]) == "energy" and ws.blueprint.nodes.size() == n0
		and CraftEdit.signature(ws.blueprint) == sig and ws.blueprint.energy_used() == used, "второе железное предплечье не влезает", c["reason"])
	_check("energy_reason_text", String(c["reason"]).contains("энерги"), "причина — про энергию", c["reason"])
	var t := _find_target(ws.targets_for("metal_forearm", "body"), u3, "Anchor_Elbow")
	_check("energy_anchor_dark", bool(t.get("accepts", false)) and not bool(t.get("ok", true)), "якорь не светится (принимает вид, но энергии нет)")
	var r5 := ws.attach_part("wood_lower_arm", u3, "Anchor_Elbow", "body")
	_check("energy_small_fits", bool(r5["ok"]) and ws.blueprint.energy_used() == used + ws.blueprint.node_energy(String(r5.get("uid", "")))
		and ws.blueprint.energy_used() <= ws.blueprint.energy_budget, "а деревянное влезает", ws.blueprint.energy_used())


func _stable() -> void:
	# сборка из _energy: human без левой ноги + две руки на боках (одна с железным предплечьем)
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
	# тяги (WORKSHOP_V3.md §3): клик — тяга ЛКМ (вторая и дальше — ⚡ × вынос), ещё клик — ПКМ, ещё — снять
	_check("control_preset", ws.blueprint.control == PackedStringArray(["9"]), "human: главная тяга — кисть 9")
	var e0 := ws.blueprint.energy_used()
	var r := ws.set_control("8")
	var pe := ws.blueprint.pull_energy("8")
	_check("control_add", bool(r["ok"]) and ws.blueprint.control == PackedStringArray(["9", "8"]) and ws.blueprint.pull_button("8") == "lmb"
		and pe > 0 and ws.blueprint.energy_used() == e0 + pe, "вторая тяга ЛКМ на предплечье: + ⚡ × вынос", [ws.blueprint.control, pe])
	var glow := false
	for m in ws.part_meshes("body", "8"):
		glow = glow or _has_overlay(m)
	_check("control_glow", glow, "помеченная деталь светится (material_overlay)")
	var r2 := ws.set_control("8")
	_check("control_rmb", bool(r2["ok"]) and ws.blueprint.control_rmb == PackedStringArray(["8"]) and ws.blueprint.pull_button("8") == "rmb"
		and ws.blueprint.energy_used() == e0 + pe, "ещё клик — та же тяга на ПКМ (энергия та же)", ws.blueprint.control_rmb)
	var rt := ws.set_control("T")
	_check("control_core_refused", not bool(rt["ok"]) and ws.blueprint.control == PackedStringArray(["9", "8"]), "ядро нельзя", rt.get("reason", ""))
	var rc := ws.set_control("8")
	_check("control_toggle_off", bool(rc["ok"]) and ws.blueprint.control == PackedStringArray(["9"]) and ws.blueprint.control_rmb.is_empty()
		and ws.blueprint.energy_used() == e0, "третий клик снимает тягу", ws.blueprint.control)
	ws.set_control("9")
	ws.set_control("9")
	_check("control_warning", ws.blueprint.control.is_empty() and CraftEdit.warnings(ws.blueprint).size() == 1, "без тяг — подсказка",
		CraftEdit.warnings(ws.blueprint))
	# энергия — предел: тяги на все детали human не влезают в 100
	ws.set_preset("human")
	await _frames(1)
	var refused := {}
	for u in ["3", "8", "2", "7", "6", "C", "5", "B", "H", "1", "4", "A"]:
		var rr := ws.set_control(u)
		if not bool(rr["ok"]):
			refused = rr
			break
	_check("control_energy_refused", String(refused.get("code", "")) == "energy" and ws.blueprint.energy_used() <= ws.blueprint.energy_budget
		and String(refused.get("reason", "")).contains("энерги"), "тяги кончаются по энергии (%d тяг)" % ws.blueprint.control.size(),
		refused.get("reason", ""))
	# и технический потолок MAX_PULLS
	ws.set_preset("human")
	await _frames(1)
	ws.blueprint.energy_budget = 1000
	var last := {}
	for u in ["3", "8", "2", "7", "6", "C", "5", "B", "H", "1", "4", "A"]:
		last = ws.set_control(u)
	_check("control_max", ws.blueprint.control.size() == BodyBlueprint.MAX_PULLS and String(last.get("code", "")) == "max",
		"не больше %d тяг" % BodyBlueprint.MAX_PULLS, ws.blueprint.control.size())
	# испытание: две тяги — две руки ArmAssist, ПКМ-тяга ведёт свою деталь к цели
	ws.set_preset("human")
	await _frames(1)
	ws.set_control("C")
	ws.set_control("C")
	var ok_t := ws.start_test()
	await _frames(3)
	var arms: Array = []
	if ws.test_doll != null:
		for c in ws.test_doll.get_children():
			if c is ArmAssist:
				arms.append(c)
	var sister: ArmAssist = null
	for a in arms:
		if not (a as ArmAssist).primary:
			sister = a
	_check("pull_test_arms", ok_t and arms.size() == 2 and sister != null and sister.button == "rmb" and sister.part_name == "Foot_R",
		"испытание: главная рука + тяга ПКМ на правой стопе", [arms.size(), sister.part_name if sister else "", sister.button if sister else ""])
	if sister != null and sister.part != null:
		var goal := sister.root_point() + Vector3(0.55, -0.35, 0.0)   # пинок вперёд на уровне колена (мах выше бедра сила 80 Н не тянет)
		var d0 := sister.grip_global().distance_to(goal)
		sister.set_target_override(goal)
		for i in range(60):
			await get_tree().physics_frame
		var d1 := sister.grip_global().distance_to(sister.target)
		sister.clear_target_override()
		_check("pull_test_moves", d1 < 0.35 and d1 < d0 * 0.5, "тяга ПКМ дотянула стопу к цели (м; нога втрое тяжелее руки)", [snappedf(d0, 0.01), snappedf(d1, 0.01)])
	ws.stop_test()
	await _frames(1)
	ws.set_preset("human")
	ws.history.clear()   # десятки пометок тяг выше упёрлись бы в потолок истории — дальше пробы считают history.size()
	await _frames(1)


## То, что делает мышь, но через экранные точки: луч по детали на стенде (и по слитой броне), протяжка → отпускание у якоря.
func _mouse_path() -> void:
	ws.set_preset("human")
	await _frames(2)
	var cam := get_viewport().get_camera_3d()
	var hand := ws.stand.parts["Hand_R"] as Node3D
	var h := ws.pick(cam.unproject_position(hand.global_position))
	_check("pick_hand", String(h.get("uid", "")) == "9" and String(h.get("target", "")) == "body", "луч из камеры по кисти → узел 9", h)
	# железное предплечье вместо деревянного (замена, кисть остаётся) и щиток на него (fixed: сливается с предплечьем). Энергия
	# по расстоянию: сначала снять левую ногу, иначе щиток на железное предплечье не влезает в 100
	ws.detach_part("4", "body")
	var e0 := ws.blueprint.energy_used()
	var old8 := ws.blueprint.node_energy("8")
	var r1 := ws.attach_part("metal_forearm", "7", "Anchor_Elbow", "body")
	var r2 := ws.attach_part("shield_plate", "8", "Anchor_Plate", "body")
	await _frames(2)
	var plate := String(r2.get("uid", ""))
	_check("pick_replace_keeps_child", bool(r1["ok"]) and String(r1.get("replace", "")) == "8" and not CraftEdit.find(ws.blueprint, "9").is_empty()
		and ws.blueprint.energy_used() == e0 - old8 + ws.blueprint.node_energy(String(r1.get("uid", ""))) + ws.blueprint.node_energy(plate)
		and ws.blueprint.energy_used() <= ws.blueprint.energy_budget, "замена предплечья: кисть осталась, энергия − старое + железное + щиток",
		[ws.blueprint.energy_used(), e0, old8])
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
	# «сок» боя на испытании (WORKSHOP_V3.md §5): TrainingFeel с режиссёрами эффектов и звука, удар по манекену — через hit_fx
	var feel := ws.feel
	_check("test_feel", feel != null and feel.get_node_or_null("HitFxDirector") != null and feel.get_node_or_null("SfxDirector") != null
		and feel.hit_fx_count > 0 and d.get_node("DollCombat").get("match_ref") == feel,
		"испытание: TrainingFeel (эффекты, звук), удары идут в hit_fx", [feel.hit_fx_count if feel else -1])
	# медленное касание манекена рукой (ниже MIN_IMPACT_SPEED): урона 0, но сигнал weak_contact — у манекена «0 · 1.2 м/с»
	var weak0 := feel.weak_count if feel else 0
	var hp0 := float(ws.dummy.call("hp"))
	dummy_doll = ws.dummy.get("doll")
	if arm != null and dummy_doll != null and is_instance_valid(dummy_doll) and feel != null:
		for i in range(150):
			if feel.weak_count > weak0:
				break
			var tp := dummy_doll.torso().global_position
			arm.set_target_override(arm.grip_global().move_toward(tp, 0.012))   # ~0.7 м/с к торсу манекена
			await get_tree().physics_frame
		arm.clear_target_override()
	_check("test_weak_contact", feel != null and feel.weak_count > weak0, "медленное касание — weak_contact (урона нет, видно скорость)",
		[weak0, feel.weak_count if feel else -1, snappedf(hp0 - float(ws.dummy.call("hp")), 0.1)])
	ws.stop_test()
	await _frames(1)
	_check("test_time_scale_back", is_equal_approx(Engine.time_scale, 1.0), "после испытания время снова 1×", Engine.time_scale)
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


# ------------------------------------------------------------------ кит тела v2 (BODY_KIT.md §5.5)

## Вкладки полки: у каждой вкладки деталей — детали кита, «Шарниры» и «Материал» — инструменты; то же в UI (плашки).
func _kit_shelves() -> void:
	var counts := {}
	var ok := true
	for id in ["core", "head", "limb", "end", "armor"]:
		var n := 0
		for d in CraftEdit.parts_of_kinds(CraftEdit.shelf_of(CraftEdit.BODY_SHELVES, id).get("kinds", [])):
			if d.id.begins_with("kit_"):
				n += 1
		counts[id] = n
		ok = ok and n > 0
	var deco := CraftEdit.parts_of_kinds(["deco", "armor"]).size()
	var jt_tab := CraftEdit.shelf_of(CraftEdit.BODY_SHELVES, "joint")
	var mat_tab := CraftEdit.shelf_of(CraftEdit.BODY_SHELVES, "mat")
	counts["deco_armor"] = deco
	counts["materials"] = MaterialDef.all_ids().size()
	_check("shelves_have_kit", ok and deco >= 6 and String(jt_tab.get("tool", "")) == "joint" and String(mat_tab.get("tool", "")) == "material"
		and MaterialDef.all_ids().size() == MaterialDef.ORDER.size() and CraftEdit.KIND_ORDER.has("deco") and CraftEdit.KIND_ORDER.has("armor"),
		"вкладки: детали кита на своих полках, декор/броня, инструменты «Шарниры» и «Материал»", counts)
	# UI: плашки инструментов на вкладках
	var tabs: Dictionary = ws.ui.get("shelf_tab")
	var was := String(tabs["body"])
	tabs["body"] = "mat"
	ws.ui.call("_build_left")
	var n_mat := (ws.ui.get("_tool_cards") as Dictionary).size()
	tabs["body"] = "joint"
	ws.ui.call("_build_left")
	var n_jt := (ws.ui.get("_tool_cards") as Dictionary).size()
	var n_jparts := (ws.ui.get("_cards") as Dictionary).size()
	# UI v0.2: «Броня» и «Декор» — разные категории
	tabs["body"] = "deco"
	ws.ui.call("_build_left")
	var deco_cards: Dictionary = (ws.ui.get("_cards") as Dictionary).duplicate()
	tabs["body"] = "armor"
	ws.ui.call("_build_left")
	var armor_cards: Dictionary = ws.ui.get("_cards")
	var has_crown := deco_cards.has("kit_deco_crown") and armor_cards.has("kit_deco_pauldron")   # наплечник — вид armor
	var armor_new := armor_cards.has("kit_drill_head") and deco_cards.has("kit_deco_wings")   # _cards чистится при пересборке
	var armor_human := armor_cards.has("kit_human_torso") or deco_cards.has("kit_human_torso")
	tabs["body"] = was
	ws.ui.call("_build_left")
	# kit_human_* (дубли wood_* под риг v3 для пресета kit_human) на полках не показываются, но PartDef грузится
	var hidden: Array = []
	for d in CraftEdit.all_parts():
		if d.id.begins_with("kit_human_"):
			hidden.append(d.id)
	# детали второй волны кита — на своих вкладках (навершия — на «Броня, декор», §5.5)
	var want := {"kit_head_lantern": "head", "kit_head_skull": "head", "kit_core_boiler": "core", "kit_core_cage": "core",
		"kit_limb_curved_s": "limb", "kit_limb_rope_l": "limb", "kit_hand_clamp": "end", "kit_foot_wheel": "end",
		"kit_deco_wings": "deco", "kit_deco_gauntlet_s": "armor", "kit_drill_head": "armor", "kit_pick_head": "armor"}
	var misplaced: Array = []
	for pid in want:
		var on := false
		for d in CraftEdit.parts_of_kinds(CraftEdit.shelf_of(CraftEdit.BODY_SHELVES, String(want[pid])).get("kinds", [])):
			on = on or d.id == pid
		if not on:
			misplaced.append(pid)
	_check("shelves_new_kit", misplaced.is_empty() and armor_new,
		"новые детали кита на своих вкладках, на броне — бур и крылья", misplaced)
	var human_def := BodyBlueprint.part_def("kit_human_torso")
	_check("shelves_hide_kit_human", hidden.is_empty() and human_def != null and not armor_human,
		"полки без kit_human_* (CraftEdit.SHELF_HIDDEN_PREFIXES), PartDef kit_human_torso грузится", hidden)
	_check("shelves_ui_tools", n_mat == MaterialDef.all_ids().size() and n_jt == KitJoint.ORDER.size()
		and n_jparts == CraftEdit.parts_of_kinds(["joint", "chain"]).size() and has_crown,
		"UI: 15 плашек материала, 5 типов шарнира (+ детали суставов), корона в декоре, наплечник в броне", [n_mat, n_jt, n_jparts, has_crown])


## Пресеты кита на стенде: без ошибок, тел столько, сколько узлов со своим телом.
func _kit_presets() -> void:
	for id in CraftEdit.BODY_PRESETS:
		if not String(id).begins_with("kit_"):
			continue
		var set_ok := ws.set_preset(String(id))
		await _frames(1)
		var bp := ws.blueprint
		var own := 0
		for n in bp.nodes:
			if not CraftEdit.is_fixed(bp, String(n["uid"])):
				own += 1
		var built := ws.stand != null and ws.stand.build_errors.is_empty() and ws.stand.parts.size() == own
		_check("kit_preset_%s_loads" % id, set_ok and bp.id == id and CraftEdit.friendly_errors(bp).is_empty() and built,
			"пресет %s: без ошибок, на стенде %d тел" % [id, own],
			{"bodies": ws.stand.parts.size() if ws.stand else -1, "energy": bp.energy_used(), "mass": snappedf(bp.total_mass(), 0.1),
			"errors": CraftEdit.friendly_errors(bp)})


## Поверхность с override-материалом m где-то под n.
func _has_surface(n: Node, m: Material) -> bool:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		for s in range((n as MeshInstance3D).mesh.get_surface_count()):
			if (n as MeshInstance3D).get_surface_override_material(s) == m:
				return true
	for c in n.get_children():
		if _has_surface(c, m):
			return true
	return false


## Клик мышью по экранной точке — как WorkshopBuild._unhandled_input (кнопка, нажатие).
func _click(p: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.position = p
	ev.global_position = p
	ws._unhandled_input(ev)


func _key(k: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.keycode = k
	ev.pressed = true
	ws._unhandled_input(ev)


## Экранная точка меша детали uid на стенде (центр габарита).
func _part_screen(uid: String) -> Vector2:
	var ms := ws.part_meshes("body", uid)
	var cam := get_viewport().get_camera_3d()
	if ms.is_empty() or cam == null:
		return Vector2(-1, -1)
	return cam.unproject_position(WorkshopBuild._visual_aabb(ms[0]).get_center())


func _kit_material() -> void:
	ws.set_preset("kit_human")
	await _frames(1)
	var sig0 := CraftEdit.signature(ws.blueprint)
	var m0 := float(ws.body_stats()["mass"])
	var h0 := ws.history.size()
	var iron := MaterialDef.get_def("iron")
	var r := ws.set_material("1", "iron")
	await _frames(1)
	var n1 := CraftEdit.find(ws.blueprint, "1")
	var ua := ws.stand.parts.get("UpperArm_L") as RigidBody3D if ws.stand else null
	var surf := ua != null and iron != null and _has_surface(ua.get_node("Mesh"), iron.surface)
	var pm: PhysicsMaterial = ua.physics_material_override if ua != null else null
	_check("mat_set", bool(r["ok"]) and String(n1.get("mat", "")) == "iron" and ws.history.size() == h0 + 1 and surf and pm != null
		and is_equal_approx(pm.friction, iron.friction) and is_equal_approx(pm.bounce, iron.bounce),
		"кисть: плечо kit_human → железо (mat, поверхность Base_Iron, физматериал 0.5 / 0.1)", [n1.get("mat", ""), surf, pm.friction if pm else -1.0])
	var m1 := float(ws.body_stats()["mass"])
	var want := 2.0 * (iron.density - 1.0)
	_check("mat_mass", absf(m1 - m0 - want) < 0.01 and ua != null and absf(ua.mass - 2.0 * iron.density) < 0.01
		and absf(float(r["mass_after"]) - 2.0 * iron.density) < 0.01, "масса: 2.0 кг × 2.2 = 4.4 (сборка +%.1f)" % want,
		[snappedf(m0, 0.01), snappedf(m1, 0.01), snappedf(ua.mass, 0.01) if ua else -1.0])
	var r2 := ws.set_material("1", "wood")
	await _frames(1)
	_check("mat_default_erases", bool(r2["ok"]) and not CraftEdit.find(ws.blueprint, "1").has("mat") and absf(float(ws.body_stats()["mass"]) - m0) < 0.01,
		"материал по умолчанию (дерево) — ключ mat стёрт, масса как была")
	ws.undo()
	var back_iron := String(CraftEdit.find(ws.blueprint, "1").get("mat", "")) == "iron"
	ws.undo()
	await _frames(1)
	_check("mat_undo", back_iron and CraftEdit.signature(ws.blueprint) == sig0 and absf(float(ws.body_stats()["mass"]) - m0) < 0.01
		and ws.stand != null and ws.stand.parts.has("UpperArm_L") and not _has_surface(ws.stand.parts["UpperArm_L"], iron.surface),
		"Ctrl+Z ×2: снова железо, потом дерево (узлы как у пресета)")
	# подсветка кистью и подсказка
	ws.set_paint_mat("iron")
	ws.set_hover({"target": "body", "uid": "7"})
	var lit := false
	for mm in ws.part_meshes("body", "7"):
		lit = lit or _has_overlay(mm)
	var hint := ws.hint_text()
	_check("mat_hover", ws.active_tool() == "material" and lit and hint.contains("Железо") and hint.contains("4.4"),
		"кисть над плечом: подсветка и «дерево → железо, 2.0 → 4.4 кг»", hint)
	ws.set_hover({})
	ws.set_paint_mat("")
	# старая деталь не красится
	ws.set_preset("human")
	await _frames(1)
	var sig_h := CraftEdit.signature(ws.blueprint)
	var hh := ws.history.size()
	var rw := ws.set_material("1", "iron")
	_check("mat_refused_wood", not bool(rw["ok"]) and String(rw["code"]) == "paint" and String(rw["reason"]).contains("не красится")
		and CraftEdit.signature(ws.blueprint) == sig_h and ws.history.size() == hh, "human: деревянное плечо — отказ «не красится»", rw["reason"])
	# мышью: кисть «ржавчина» + клик по правой кисти kit_human; ПКМ кладёт кисть и ничего не откручивает
	ws.set_preset("kit_human")
	await _frames(2)
	ws.set_paint_mat("rust")
	_click(_part_screen("9"))
	await _frames(1)
	var n9 := CraftEdit.find(ws.blueprint, "9")
	_check("mat_click", String(n9.get("mat", "")) == "rust" and ws.paint_mat == "rust", "клик кистью по кисти куклы → ржавчина (кисть остаётся в руке)", n9.get("mat", ""))
	var nodes0 := ws.blueprint.nodes.size()
	_click(_part_screen("9"), MOUSE_BUTTON_RIGHT)
	await _frames(1)
	_check("mat_rmb_clears", ws.paint_mat == "" and ws.blueprint.nodes.size() == nodes0, "ПКМ с кистью — кисть убрана, деталь на месте")
	# замена детали: mat остаётся у детали кита (есть base_mat), у старой — стирается
	ws.set_material("1", "iron")
	var rk := ws.attach_part("kit_limb_thick_s", "T", "Anchor_Shoulder_L", "body")
	var mat_kit := String(CraftEdit.find(ws.blueprint, "1").get("mat", ""))
	var rwd := ws.attach_part("wood_upper_arm", "T", "Anchor_Shoulder_L", "body")
	var n1w := CraftEdit.find(ws.blueprint, "1")
	_check("mat_replace", bool(rk["ok"]) and mat_kit == "iron" and bool(rwd["ok"]) and not n1w.has("mat") and ws.blueprint.validate().is_empty(),
		"замена: толстая рука — железо осталось; деревянное плечо — mat стёрт", [mat_kit, n1w.get("mat", "")])


func _kit_joint() -> void:
	ws.set_preset("kit_human")
	await _frames(1)
	var sig0 := CraftEdit.signature(ws.blueprint)
	var e0 := ws.blueprint.energy_used()
	var r := ws.set_joint("2", "free")
	await _frames(1)
	var jn := String(ws.stand.uid_joint.get("2", "")) if ws.stand else ""
	var j := ws.stand.joints.get(jn) as Node if ws.stand else null
	_check("joint_set_free", bool(r["ok"]) and String(CraftEdit.find(ws.blueprint, "2").get("joint", "")) == "free" and j != null
		and String(j.get_meta("joint_type", "")) == "free" and ws.blueprint.energy_used() == e0,
		"локоть левой руки — свободный (узел joint, meta joint_type сустава %s, энергия та же)" % jn, j.get_meta("joint_type", "") if j else "")
	# энергия по расстоянию (WORKSHOP_V3.md §2): мотор 8 дорожает вместе с узлом колена — Δ = цена(база + 8) − цена(база)
	var b5 := BodyBlueprint.node_base_energy(CraftEdit.find(ws.blueprint, "5"))
	var d5 := float(ws.blueprint.node_reach().get("5", 0.0))
	var want_m := e0 + BodyBlueprint.reach_cost(b5 + KitJoint.energy_of("motor"), d5) - BodyBlueprint.reach_cost(b5, d5)
	var rm := ws.set_joint("5", "motor")
	_check("joint_motor_energy", bool(rm["ok"]) and ws.blueprint.energy_used() == want_m, "мотор на колено: энергия +8 × вынос колена",
		[ws.blueprint.energy_used(), want_m])
	var bodies0 := ws.stand.parts.size() if ws.stand else -1
	var rw := ws.set_joint("3", "weld")
	await _frames(2)
	var hp := ws.pick(_part_screen("3"))
	_check("joint_weld_bodies", bool(rw["ok"]) and ws.stand != null and ws.stand.parts.size() == bodies0 - 1 and not ws.stand.parts.has("Hand_L")
		and String(ws.stand.uid_body.get("3", "")) == "LowerArm_L" and int(ws.body_stats()["bodies"]) == bodies0 - 1,
		"сварка кисти: тел на одно меньше, кисть — часть предплечья", [bodies0, ws.stand.parts.size() if ws.stand else -1, ws.stand.uid_body.get("3", "") if ws.stand else ""])
	_check("joint_weld_pick", String(hp.get("uid", "")) == "3", "луч по сваренной кисти — её узел (формы в хозяине)", hp)
	# отказы
	var sig1 := CraftEdit.signature(ws.blueprint)
	var rr := ws.set_joint("T", "free")
	_check("joint_refused_root", not bool(rr["ok"]) and String(rr["code"]) == "root" and CraftEdit.signature(ws.blueprint) == sig1,
		"ядро — корень: шарнира нет", rr["reason"])
	var rh := ws.set_joint("H", "weld")
	var rc := ws.set_joint("9", "weld")
	ws.set_preset("kit_skull")   # D — султан на голове (декор; у Громилы наплечники сняты ради энергии, WORKSHOP_V3.md §2)
	await _frames(1)
	var sig_b := CraftEdit.signature(ws.blueprint)
	var ra := ws.set_joint("1", "weld")
	var rd := ws.set_joint("D", "spring")
	_check("joint_refused_rules", not bool(rh["ok"]) and not bool(rc["ok"]) and not bool(ra["ok"]) and not bool(rd["ok"]) and String(rd["code"]) == "fixed"
		and CraftEdit.signature(ws.blueprint) == sig_b, "нельзя: сварить голову, руку мышью, плечо с локтем на auto-суставе; шарнир у декора",
		[rh["reason"], rc["reason"], ra["reason"], rd["reason"]])
	ws.undo()   # set_preset(kit_skull) → назад к kit_human со сваркой
	await _frames(1)
	var welded := String(CraftEdit.find(ws.blueprint, "3").get("joint", "")) == "weld"
	ws.undo()
	ws.undo()
	ws.undo()
	await _frames(1)
	_check("joint_undo", welded and CraftEdit.signature(ws.blueprint) == sig0 and ws.stand != null and ws.stand.parts.size() == 14
		and ws.blueprint.energy_used() == e0, "Ctrl+Z: сварка, мотор, свободный сняты — снова kit_human (14 тел)", ws.stand.parts.size() if ws.stand else -1)
	# мышью: инструмент «Пружина» + клик по правой кисти; кружки типов на суставах; Esc кладёт инструмент
	await _frames(1)
	ws.set_joint_pick("spring")
	var n_j := 0
	for it in ws.overlay_items():
		if String(it["state"]).begins_with("joint"):
			n_j += 1
	_click(_part_screen("9"))
	await _frames(1)
	_check("joint_click", String(CraftEdit.find(ws.blueprint, "9").get("joint", "")) == "spring" and ws.joint_pick == "spring" and n_j == 13,
		"клик инструментом по кисти → пружина; на 13 суставах кружки типов", [CraftEdit.find(ws.blueprint, "9").get("joint", ""), n_j])
	_key(KEY_ESCAPE)
	_check("joint_esc_clears", ws.joint_pick == "" and ws.active_tool() == "", "Esc — инструмент шарнира убран")
	# сварили кисть с оружием: оружие переезжает в другую кисть (сваренная — не держатель)
	ws.set_preset("kit_human")
	ws.set_control("9")   # тяга с кисти снята (ЛКМ → ПКМ → нет): приваривать можно, главная тяга — предплечье
	ws.set_control("9")
	ws.set_control("8")
	var eq := ws.weapon_to_hand()
	var on0 := ws.blueprint.weapon_on
	var rwh := ws.set_joint("9", "weld")
	await _frames(1)
	_check("joint_weld_weapon", bool(eq.get("ok", false)) and on0 == "9" and bool(rwh["ok"]) and ws.blueprint.weapon_on == "3"
		and String(ws._mount()["uid"]) == "3" and ws.held_weapon != null, "сварили кисть с оружием — оружие в другой кисти",
		[on0, ws.blueprint.weapon_on])


## Сохранение с mat / joint и испытание такой сборки.
func _kit_save_live() -> void:
	ws.set_preset("kit_human")
	await _frames(1)
	ws.set_material("1", "iron")
	ws.set_material("T", "planks")
	ws.set_joint("2", "free")
	ws.set_joint("B", "motor")
	ws.set_joint("3", "weld")
	var sig := CraftEdit.signature(ws.blueprint)
	var path := ws.save_as("Проба кита")
	ws.set_preset("human")
	await _frames(1)
	var ok := ws.load_path(path)
	await _frames(1)
	_check("mat_save_roundtrip", path != "" and ok and CraftEdit.signature(ws.blueprint) == sig
		and String(CraftEdit.find(ws.blueprint, "1").get("mat", "")) == "iron" and String(CraftEdit.find(ws.blueprint, "2").get("joint", "")) == "free",
		"сохранить / загрузить: те же узлы с mat и joint", sig.size())
	if path != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var nb := int(ws.body_stats()["bodies"])
	var started := ws.start_test()
	await _frames(1)
	var d := ws.test_doll
	var max_v := 0.0
	var finite := true
	for i in range(90):
		await get_tree().physics_frame
		if not is_instance_valid(d):
			break
		for b in d.parts.values():
			max_v = maxf(max_v, (b as RigidBody3D).linear_velocity.length())
			finite = finite and (b as RigidBody3D).global_position.is_finite()
	_check("kit_test_live", started and d != null and d.build_errors.is_empty() and d.parts.size() == nb and finite and max_v < MAX_SPEED,
		"кит с железом, досками, свободным локтем, мотором и сваркой оживает: 1.5 с без взрыва", [d.parts.size() if d else -1, snappedf(max_v, 0.01)])
	ws.stop_test()
	await _frames(1)
	ws.set_preset("human")


## Правки ревью кита (29.09): рука мышью после замены кисти на навершие, мотор на суставе без мышцы, отказы шарниров словами игрока,
## имя тела конечности кита на локте.
func _kit_fixes() -> void:
	# (a) kit_devil: бур вместо управляемой кисти 9 (конец предплечья 8) — рука мышью переезжает на предплечье, испытание её ведёт
	ws.set_preset("kit_devil")
	await _frames(1)
	var ra := ws.attach_part("kit_drill_head", "8", "Anchor_End", "body")
	var ok_a := bool(ra.get("ok", false)) and ws.blueprint.control == PackedStringArray(["8"]) and CraftEdit.friendly_errors(ws.blueprint).is_empty()
	var started := ws.start_test()
	await _frames(2)
	var arm := ws.test_doll.get_node_or_null("ArmAssist") as ArmAssist if ws.test_doll != null else null
	_check("control_rehost_on_replace", ok_a and started and arm != null and arm.part != null and arm.part_name == "LowerArm_R",
		"бур вместо управляемой кисти: рука мышью на предплечье, в испытании ArmAssist ведёт LowerArm_R",
		[ra.get("code", ""), Array(ws.blueprint.control), arm.part_name if arm else ""])
	ws.stop_test()
	await _frames(1)
	# (b) рука мышью на плече 7, бур на плечевой якорь ядра вместо него — хозяин ядро: пометка снимается, подсказка
	ws.set_preset("kit_devil")
	await _frames(1)
	ws.set_control("7")
	var rb := ws.attach_part("kit_drill_head", "T", "Anchor_Shoulder_R", "body")
	_check("control_cleared_on_core", bool(rb.get("ok", false)) and ws.blueprint.control.is_empty() and not CraftEdit.warnings(ws.blueprint).is_empty()
		and ws.blueprint.validate().is_empty(), "бур вместо управляемого плеча: хозяин — ядро, пометка снята, подсказка",
		[rb.get("code", ""), Array(ws.blueprint.control), CraftEdit.warnings(ws.blueprint)])
	# (c) human (старые детали): шар булавы вместо кисти 9 — рука мышью на предплечье 8
	ws.set_preset("human")
	await _frames(1)
	var rc := ws.attach_part("head_mace_ball", "8", "Anchor_Wrist", "body")
	_check("control_rehost_legacy", bool(rc.get("ok", false)) and ws.blueprint.control == PackedStringArray(["8"]) and ws.blueprint.validate().is_empty(),
		"human: шар булавы вместо кисти — рука мышью на предплечье", [rc.get("reason", ""), Array(ws.blueprint.control)])
	# (d) мотор на стопе (сустав Ankle без мышцы) — отказ, энергия та же
	ws.set_preset("kit_human")
	await _frames(1)
	var e0 := ws.blueprint.energy_used()
	var rm := ws.set_joint("6", "motor")
	_check("joint_motor_ankle_refused", not bool(rm["ok"]) and String(rm["code"]) == "rule" and ws.blueprint.energy_used() == e0
		and not CraftEdit.find(ws.blueprint, "6").has("joint"), "мотор на стопе (сустав без мышцы) — отказ, энергия та же", rm["reason"])
	# (e) отказы сварки и «приваренный конец» — словами игрока: без uid, имён якорей и «auto»
	ws.set_preset("kit_brawler")
	await _frames(1)
	var reasons: Array = [rm["reason"]]
	for u in ["H", "9", "2"]:
		reasons.append(String(ws.set_joint(u, "weld")["reason"]))
	ws.detach_part("3")
	var rw := ws.set_joint("2", "weld")
	var ch := CraftEdit.check(ws.blueprint, "kit_hand_mitten", "2", "Anchor_End")
	reasons.append(String(ch["reason"]))
	var re := RegEx.create_from_string("«[0-9A-Z]»|Anchor_|auto")
	var raw: Array = reasons.filter(func(x: Variant) -> bool: return String(x) == "" or re.search(String(x)) != null)
	_check("joint_refusal_words", bool(rw["ok"]) and String(ch["code"]) == "welded" and raw.is_empty(),
		"отказы сварки, мотора и «приваренный конец» — словами (без uid, Anchor_, auto)", reasons)
	# (f) конечность кита (размер S, префикс UpperArm) на локте — тело LowerArm_<uid>: удар и монитор контактов предплечья
	ws.set_preset("kit_brawler")
	await _frames(1)
	ws.detach_part("2")
	var rl := ws.attach_part("kit_limb_thick_s", "1", "Anchor_End", "body")
	var nu := String(rl.get("uid", ""))
	var bn := ws.blueprint.body_name_of(nu)
	await _frames(1)
	_check("limb_elbow_name", bool(rl.get("ok", false)) and bn.begins_with("LowerArm_") and ws.stand != null and ws.stand.parts.has(bn)
		and ws.stand.combat_monitored(bn) and is_equal_approx(Damage.body_mult_of(bn), float(Tuning.BODY_MULT["LowerArm"])),
		"конечность кита на локте — тело LowerArm_<uid> (удар и монитор предплечья)", [nu, bn])
	ws.set_preset("human")
	await _frames(1)


# ------------------------------------------------------------------ покраска (docs/plan-demo/BODY_PAINT.md §6)

const PAINT_FIXTURE := "res://tests/fixtures/paint/sticker_fixture.png"


## Штрих баллончиком / ластиком: n физкадров, курсор идёт от p на step за кадр.
func _stroke(pt: WorkshopPaint, p: Vector2, n := 12, step := Vector2(0, 2)) -> PackedStringArray:
	pt.stroke_begin(p)
	for i in n:
		pt.stroke_move(p + step * float(i))
		await _frames(1)
	return pt.stroke_end()


## Слой краски узла uid из чертежа (null — ключа нет / битый).
func _node_layer(uid: String) -> PaintLayer:
	var n := CraftEdit.find(ws.blueprint, uid)
	return PaintLayer.from_dict(n["paint"]) if n.has("paint") else null


## [число поверхностей Shirt* / Face* с краской, число красимых поверхностей с краской] под узлом n.
func _paint_surfaces(n: Node) -> Array:
	var bad := 0
	var good := 0
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D and (cur as MeshInstance3D).mesh != null:
			var m3 := cur as MeshInstance3D
			for s in range(m3.mesh.get_surface_count()):
				var m := m3.get_active_material(s)
				if m == null or BodyPaint.paint_pass(m) == null:
					continue
				if m.resource_name.begins_with("Shirt") or m.resource_name.begins_with("Face") or String(cur.name).begins_with("Connector_"):
					bad += 1
				else:
					good += 1
		for c in cur.get_children():
			stack.append(c)
	return [bad, good]


func _paint() -> void:
	var pt: WorkshopPaint = ws.paint
	pt.virtual_mouse = true
	pt.hold_check = false
	ws.set_preset("kit_human")
	ws.history.clear()   # история ограничена HISTORY_MAX (50) — счёт записей ниже с чистого листа
	await _frames(2)
	# вкладка «Покраска»: полка покраски, шаблоны спрятаны, баллончик в руке
	ws.ui.call("open_paint_tab")
	pt.set_tool("spray")
	await _frames(1)
	var panel := ws.ui.find_child("PaintPanel", true, false)
	var presets_hidden := not (ws.ui.get("presets_box") as Control).visible
	_check("paint_tab_ui", panel != null and presets_hidden and pt.tab_open and ws.active_tool() == "paint" and ws.paint_tool == "spray"
		and ws.overlay_items().is_empty(), "вкладка «Покраска»: полка, шаблоны спрятаны, баллончик в руке, точек якорей нет",
		[panel != null, presets_hidden, ws.paint_tool])
	# штрих баллончиком по левому плечу (узел 1), симметрия — правое (7)
	pt.symmetry = true
	pt.set_color(Color(0.1, 0.8, 0.25))
	var p1 := pt.screen_point_on("1")
	var h0 := ws.history.size()
	var touched := await _stroke(pt, p1)
	var hd: Dictionary = ws.stand.paint_handle("1")
	var live: PaintLayer = hd.get("layer")
	var l1 := _node_layer("1")
	_check("paint_spray_changes_layer", p1.x >= 0.0 and live != null and not live.is_empty() and l1 != null and not l1.is_empty()
		and l1.data == live.data, "штрих по плечу: живой слой и node.paint — одна и та же краска", [p1, touched])
	_check("paint_stroke_one_history", ws.history.size() == h0 + 1, "штрих — одна запись истории (12 кадров мазков)", ws.history.size() - h0)
	var l7 := _node_layer("7")
	_check("paint_symmetry_right_arm", touched.has("7") and l7 != null and not l7.is_empty() and not ws.stand.paint_handle("7").is_empty(),
		"симметрия: правое плечо (7) покрашено тем же штрихом", touched)
	var ps := _paint_surfaces(ws.stand)
	_check("paint_shirt_untouched", int(ps[0]) == 0 and int(ps[1]) > 0, "Shirt* / Face* / коннекторы без краски, красимые — с краской", ps)
	# ластик: альфа слоя падает
	var sum0 := 0
	for i in range(3, live.data.size(), 4):
		sum0 += live.data[i]
	pt.set_tool("erase")
	pt.pressure = 1.0
	var erase_cm0 := pt.size_cm
	pt.set_size_cm(erase_cm0 * 2.0)
	await _stroke(pt, p1, 20)   # по тому же штриху, что баллончик, ластиком вдвое шире (точкой — доля стёртого зависит от кадра стенда)
	pt.set_size_cm(erase_cm0)
	var live2: PaintLayer = ws.stand.paint_handle("1").get("layer")
	var sum1 := 0
	for i in range(3, live2.data.size(), 4):
		sum1 += live2.data[i]
	_check("paint_erase", sum1 < sum0 * 0.8 and ws.history.size() == h0 + 2, "ластик: краски на плече меньше, ещё одна запись", [sum0, sum1])
	pt.pressure = 0.85
	# Ctrl+Z ×2 — как до штриха: ключа paint нет, стенд без слоя
	_key_ctrl_z()
	_key_ctrl_z()
	await _frames(1)
	_check("paint_undo", not CraftEdit.find(ws.blueprint, "1").has("paint") and not CraftEdit.find(ws.blueprint, "7").has("paint")
		and ws.stand.paint_handle("1").is_empty() and ws.history.size() == h0, "Ctrl+Z ×2: ластик и штрих отменены, слоя нет")
	# трафарет: звезда на груди (у оси — одна), колесо, Q, тащить, ПКМ
	pt.set_tool("stencil")
	pt.stencil = "star"
	pt.sticker_cm = 12.0
	pt.sticker_rot = 0.0
	var pc := pt.screen_point_on("T")
	var hs := ws.history.size()
	var rs := pt.place_sticker(pc)
	var stT: Array = CraftEdit.find(ws.blueprint, "T").get("stickers", [])
	var decs := ws.stand.stickers_of("T")
	_check("sticker_place", bool(rs.get("ok", false)) and stT.size() == 1 and decs.size() == 1 and String(rs.get("twin_uid", "x")) == ""
		and decs[0] is MeshInstance3D and (decs[0] as MeshInstance3D).mesh.get_surface_count() == 1 and String(stT[0]["img"]) == "stencil:star"
		and ws.history.size() == hs + 1, "звезда на груди: node.stickers, живая меш-наклейка на груди, у оси — без пары", [rs, stT.size(), decs.size()])
	var d0 := decs[0] as MeshInstance3D
	var size0 := BodyPaint.sticker_dims(d0).x
	var x0 := d0.global_basis.x.normalized()
	_click(pc, MOUSE_BUTTON_WHEEL_UP)
	_click(pc, MOUSE_BUTTON_WHEEL_UP)
	_key(KEY_Q)
	var st1: Dictionary = (CraftEdit.find(ws.blueprint, "T").get("stickers", [{}]) as Array)[0]
	var ang := rad_to_deg(x0.angle_to(d0.global_basis.x.normalized()))
	var dims0 := BodyPaint.sticker_dims(d0)
	_check("sticker_rotate_scale", absf(dims0.x - size0 * WorkshopPaint.SCALE_STEP * WorkshopPaint.SCALE_STEP) < 0.002
		and absf((st1["size"] as Vector2).x - dims0.x) < 1e-4 and absf(ang - 15.0) < 0.5 and ws.history.size() == hs + 3,
		"колесо ×2 — больше (одна запись), Q — +15° (ещё одна), чертёж = наклейка", [snappedf(size0, 0.001), snappedf(dims0.x, 0.001),
		snappedf(ang, 0.1), ws.history.size() - hs])
	# тащить: ЛКМ на наклейке, курсор ниже, отпустить — наклейка там
	var o0 := d0.global_position
	_mouse_button(pc, MOUSE_BUTTON_LEFT, true)
	_mouse_move(pc + Vector2(0, 40))
	_mouse_button(pc + Vector2(0, 40), MOUSE_BUTTON_LEFT, false)
	var decs2 := ws.stand.stickers_of("T")
	var moved := decs2.size() == 1 and (decs2[0] as Node3D).global_position.distance_to(o0) > 0.02
	var st2: Array = CraftEdit.find(ws.blueprint, "T").get("stickers", [])
	var xf2: Transform3D = st2[0]["xf"] if st2.size() == 1 else Transform3D.IDENTITY
	var root_t := BodyPaint.mesh_root_of(ws.stand, "T")
	_check("sticker_move", moved and root_t != null and (root_t.global_transform * xf2).origin.distance_to((decs2[0] as Node3D).global_position) < 0.002
		and (decs2[0] as MeshInstance3D).mesh.get_surface_count() == 1,
		"тащить наклейку: переехала вниз, кадр в чертеже = наклейка, меш пересобран", [snappedf((decs2[0] as Node3D).global_position.distance_to(o0), 0.001) if not decs2.is_empty() else -1.0])
	_click(pc + Vector2(0, 40), MOUSE_BUTTON_RIGHT)
	_check("sticker_remove", not CraftEdit.find(ws.blueprint, "T").has("stickers") and ws.stand.stickers_of("T").is_empty()
		and ws.paint_tool == "stencil", "ПКМ по наклейке — снята (инструмент остался в руке)")
	# наклейка на плечо — с парой (симметрия)
	var fx_id := KitImages.import_file(PAINT_FIXTURE)
	pt.set_tool("sticker")
	pt.image = fx_id
	var ra := pt.place_sticker(pt.screen_point_on("1"))
	_check("sticker_symmetry", bool(ra.get("ok", false)) and String(ra.get("uid", "")) == "1" and String(ra.get("twin_uid", "")) == "7"
		and ws.stand.stickers_of("7").size() == 1, "наклейка на левое плечо — пара на правом", ra)
	# фото: импорт фикстуры (как из диалога — путь ОС) → голова
	pt.set_tool("face")
	var ids := pt.import_files(PackedStringArray([ProjectSettings.globalize_path(PAINT_FIXTURE)]))
	var rf := pt.set_face_image(ids[0] if not ids.is_empty() else "")
	var tex := KitImages.texture(ids[0]) if not ids.is_empty() else null
	var on_plate := false
	var hroot := BodyPaint.mesh_root_of(ws.stand, "H")
	for mi in BodyPaint.meshes(hroot):
		for s in range((mi as MeshInstance3D).mesh.get_surface_count()):
			var m := (mi as MeshInstance3D).get_active_material(s)
			if m is BaseMaterial3D and m.resource_name.begins_with("Face") and (m as BaseMaterial3D).albedo_texture == tex:
				on_plate = true
	_check("face_import_fixture", ids.size() == 1 and ids[0] == fx_id and bool(rf.get("ok", false)) and String(rf.get("mode", "")) == "face"
		and String(CraftEdit.find(ws.blueprint, "H").get("face", "")) == fx_id and on_plate, "фикстура: импорт → node.face головы, плашка с картинкой",
		[ids, rf])
	# сохранить / загрузить: слой, наклейки, фото
	pt.set_tool("spray")
	await _stroke(pt, pt.screen_point_on("2"))
	var sig := CraftEdit.signature(ws.blueprint)
	var data2 := _node_layer("2").data if _node_layer("2") != null else PackedByteArray()
	var path := ws.save_as("Проба покраски")
	ws.set_preset("human")
	await _frames(1)
	var ok_load := ws.load_path(path)
	await _frames(1)
	var l2 := _node_layer("2")
	_check("paint_save_roundtrip", path != "" and ok_load and CraftEdit.signature(ws.blueprint) == sig and not data2.is_empty() and l2 != null
		and l2.data == data2 and not ws.stand.paint_handle("2").is_empty() and ws.stand.stickers_of("1").size() == 1
		and String(CraftEdit.find(ws.blueprint, "H").get("face", "")) == fx_id, "сохранить / загрузить: те же узлы, байты слоя, наклейки, фото",
		sig.size())
	if path != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# подпись ловит потерю краски
	var lost := CraftEdit.dup_body(ws.blueprint)
	CraftEdit.find(lost, "2").erase("paint")
	_check("paint_signature", CraftEdit.signature(lost) != sig, "signature видит пропажу слоя краски")
	# раскраска всей куклы: по кадрам, каждая деталь, одна запись
	ws.set_preset("kit_human")
	await _frames(1)
	pt.set_tool("pattern")
	var hp := ws.history.size()
	var np := pt.apply_pattern("T", true, "camo")
	var frames := 0
	while pt.busy() and frames < 240:
		await _frames(1)
		frames += 1
	var painted := 0
	for n in ws.blueprint.nodes:
		var lay := _node_layer(String(n["uid"]))
		if lay != null and not lay.is_empty() and not ws.stand.paint_handle(String(n["uid"])).is_empty():
			painted += 1
	_check("paint_pattern_whole_doll", np == ws.blueprint.nodes.size() and painted == np and frames >= 2 and ws.history.size() == hp + 1,
		"Shift+клик «Камуфляж»: все %d деталей, волной за %d кадров, одна запись истории" % [np, frames], [np, painted, frames])
	# замена детали: слой и наклейки — в кадре меша прежней детали, снимаются; фото на голове остаётся (новая голова — своя плашка)
	var bp_r := CraftEdit.dup_body(ws.blueprint)
	CraftEdit.find(bp_r, "1")["stickers"] = [{"img": "stencil:star", "xf": Transform3D.IDENTITY, "size": Vector2(0.1, 0.1), "color": Color.WHITE}]
	CraftEdit.find(bp_r, "H")["face"] = fx_id
	var had := CraftEdit.find(bp_r, "1").has("paint") and CraftEdit.find(bp_r, "H").has("paint")
	var ra1 := CraftEdit.attach(bp_r, "kit_limb_thick_s", "T", "Anchor_Shoulder_L")
	var rh1 := CraftEdit.attach(bp_r, "kit_head_crate", "T", "Anchor_Neck")
	var n1r := CraftEdit.find(bp_r, "1")
	var nhr := CraftEdit.find(bp_r, "H")
	_check("paint_replace_drops", had and bool(ra1["ok"]) and bool(rh1["ok"]) and not n1r.has("paint") and not n1r.has("stickers")
		and not nhr.has("paint") and String(nhr.get("face", "")) == fx_id and String(rh1.get("face_lost", "x")) == "" and CraftEdit.find(bp_r, "4").has("paint"),
		"замена детали: краска и наклейки сняты, фото на новой голове кита осталось, соседи (бедро) не тронуты",
		[had, ra1["code"], rh1["code"], n1r.keys(), nhr.keys()])
	# старая кукла (wood_*) тоже красится
	ws.set_preset("human")
	await _frames(2)
	pt.set_tool("spray")
	var ph := pt.screen_point_on("1")
	await _stroke(pt, ph)
	var lh := _node_layer("1")
	_check("paint_legacy_human", ph.x >= 0.0 and lh != null and not lh.is_empty(), "старая кукла human: баллончик красит плечо", ph)
	# поворот стенда (R): кукла повернулась, замороженные тела едут с корнем — и в физике (луч выбора), кольцо / штрих по-прежнему
	# попадают
	var torso := ws.stand.parts["Torso"] as Node3D
	var rel0 := ws.stand.global_transform.affine_inverse() * torso.global_transform
	_key(KEY_R)
	await _wait(WorkshopPaint.TURN_S + 0.1)
	var arm := ws.stand.parts["UpperArm_L"] as RigidBody3D
	var phys: Transform3D = PhysicsServer3D.body_get_state(arm.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	var pa := pt.screen_point_on("T")
	var side_ok := false
	if pa.x >= 0.0:
		await _stroke(pt, pa, 6)
		var lt := _node_layer("T")
		side_ok = lt != null and not lt.is_empty()
	var rot_ok := absf(wrapf(ws.stand.rotation.y - PI * 0.5, -PI, PI)) < 0.01
	var rel1 := ws.stand.global_transform.affine_inverse() * torso.global_transform   # торс в кадре куклы — как до поворота
	var turned := ws.stand.global_basis.z.normalized().dot(Vector3.RIGHT) > 0.99 and rel1.origin.distance_to(rel0.origin) < 0.001 \
		and rel1.basis.x.distance_to(rel0.basis.x) < 0.001 and rel1.basis.z.distance_to(rel0.basis.z) < 0.001
	_check("paint_turn_stand", pt.turn_degrees() == 90 and rot_ok and turned and phys.origin.distance_to(arm.global_position) < 0.005
		and side_ok, "R: стенд на 90°, кукла повёрнута целиком (физтело плеча там же, где узел), бок торса красится",
		[pt.turn_degrees(), rot_ok, turned, snappedf(phys.origin.distance_to(arm.global_position), 0.0001), pa, side_ok])
	# Esc кладёт баллончик; «Испытать» — тоже и стенд прямо
	_key(KEY_ESCAPE)
	var esc_ok := ws.paint_tool == ""
	pt.set_tool("spray")
	var started := ws.start_test()
	await _frames(1)
	_check("paint_mode_cleared_on_test", esc_ok and started and ws.paint_tool == "" and ws.active_tool() == "" and pt.turn_degrees() == 0,
		"Esc — баллончик положен; «Испытать» — инструмент снят, стенд прямо", [esc_ok, ws.paint_tool])
	ws.stop_test()
	await _frames(1)
	# витрина: пресеты с краской и трафаретами
	var pres := {}
	var pres_ok := true
	for id in ["kit_graffiti", "kit_camo"]:
		ws.set_preset(id)
		await _frames(1)
		var np2 := 0
		var ns2 := 0
		var ok2 := ws.stand != null and CraftEdit.friendly_errors(ws.blueprint).is_empty()
		for n in ws.blueprint.nodes:
			var u := String(n["uid"])
			if n.has("paint"):
				np2 += 1
				ok2 = ok2 and not ws.stand.paint_handle(u).is_empty()
			if n.has("stickers"):
				ns2 += (n["stickers"] as Array).size()
				ok2 = ok2 and ws.stand.stickers_of(u).size() == (n["stickers"] as Array).size()
		pres[id] = [np2, ns2]
		pres_ok = pres_ok and ok2 and np2 >= 12 and ns2 >= 1
	_check("paint_preset_loads", pres_ok, "витрина kit_graffiti / kit_camo: слои и трафареты на стенде", pres)
	ws.clear_tools()
	ws.ui.set("shelf_tab", {"body": "limb", "weapon": "weapon_head"})
	ws.ui.call("_build_left")
	pt.virtual_mouse = false
	pt.hold_check = true
	ws.set_preset("human")
	await _frames(1)


## Правки ревью покраски (docs/plan-demo/BODY_PAINT.md §6.2): мелкая кисть, пустой штрих, трекпад, наклейка у оси, фото на старой
## голове, замена головы, зеркальная раскраска старой куклы, бюджет кадра раскраски, импорт в потоке, удаление картинки, автосейв.
func _paint_fixes() -> void:
	var pt: WorkshopPaint = ws.paint
	pt.virtual_mouse = true
	pt.hold_check = false
	ws.set_view(WorkshopBuild.View.BODY)
	ws.set_preset("kit_human")
	ws.history.clear()
	await _frames(2)
	ws.ui.call("open_paint_tab")
	pt.reset_turn()
	pt.symmetry = false
	# кисть 1 см на ядре (ячейка ≈ 14 мм): каждый мазок-клик красит (раньше ≈ 80 % не задевали ни одного центра ячейки)
	pt.set_tool("spray")
	pt.set_size_cm(1.0)
	pt.set_color(Color(0.9, 0.2, 0.6))
	var pc := pt.screen_point_on("T")
	var tried := 0
	var painted := 0
	for k in 16:
		var p := pc + Vector2((k % 4) * 9.0 - 13.0, (k / 4) * 11.0 - 17.0)
		if String(pt.surface_hit(p).get("uid", "")) != "T" or pt.protected_hit(pt.surface_hit(p)):
			continue
		tried += 1
		pt.stroke_begin(p)
		if pt.stroke_end().has("T"):
			painted += 1
	var cell_t := pt.cell_world("T")
	_check("paint_brush_min_radius", tried >= 8 and painted == tried and pt.eff_radius("T") >= cell_t * WorkshopPaint.BRUSH_CELL_MIN - 1e-6
		and cell_t > 0.012, "кисть 1 см на ядре (ячейка %.1f мм): каждый мазок красит, кольцо — не мельче 0.9 ячейки" % (cell_t * 1000.0),
		[tried, painted, snappedf(pt.eff_radius("T") * 1000.0, 0.1)])
	# штрих, который ничего не поменял (ластик по голове без краски): ни записи истории, ни «*»
	pt.set_tool("erase")
	var h0 := ws.history.size()
	var title0 := ws.blueprint.title
	var out := await _stroke(pt, pt.screen_point_on("H"), 6)
	_check("paint_noop_stroke", out.is_empty() and ws.history.size() == h0 and ws.blueprint.title == title0,
		"ластик по детали без краски: штрих пустой — без записи истории и «*»", [out, ws.history.size() - h0, ws.blueprint.title])
	# трекпад: прокрутка жестом (не колесом) — размер кисти; щипок над пустым местом — размер следующей наклейки
	pt.set_tool("spray")
	pt.set_size_cm(4.0)
	var pg := InputEventPanGesture.new()
	pg.delta = Vector2(0, -2.0)
	pg.position = pc
	ws._unhandled_input(pg)
	var size_pan := pt.size_cm
	pt.set_tool("stencil")
	pt.stencil = "star"
	pt.set_sticker_cm(12.0)
	var mg := InputEventMagnifyGesture.new()
	mg.factor = WorkshopPaint.SCALE_STEP * WorkshopPaint.SCALE_STEP * 1.01
	mg.position = Vector2(4, 4)
	ws._unhandled_input(mg)
	_check("paint_trackpad_size", is_equal_approx(size_pan, 5.0) and absf(pt.sticker_cm - 12.0 * WorkshopPaint.SCALE_STEP * WorkshopPaint.SCALE_STEP) < 0.01,
		"трекпад: прокрутка вверх ×2 — кисть 4 → 5 см, щипок — наклейка ×1.12²", [size_pan, snappedf(pt.sticker_cm, 0.01)])
	# наклейка 12 см в 3 см от оси симметрии: одна (две легли бы наполовину друг на друга), ровно на оси
	pt.symmetry = true
	pt.set_sticker_cm(12.0)
	pt.sticker_rot = 0.0
	var hc := pt.surface_hit(pc)
	var dx := 0.03 * pt._ppm(hc["point"]) if not hc.is_empty() else 13.0
	var n0 := ws.stand.stickers_of("T").size()
	var ra := pt.place_sticker(pc + Vector2(dx, 0))
	var sts := ws.stand.stickers_of("T")
	var ax := absf(pt._to_doll((sts[sts.size() - 1] as Node3D).global_position).x) if sts.size() > n0 else 1.0
	_check("sticker_axis_single", bool(ra.get("ok", false)) and String(ra.get("twin_uid", "x")) == "" and sts.size() == n0 + 1 and ax < 0.006,
		"наклейка 12 см в 3 см от оси — одна, на оси (|x| = %.1f мм)" % (ax * 1000.0), [ra, sts.size() - n0])
	# фото на старой голове (human, wood_head): одна фото-наклейка, повтор — без записи, клик мимо головы — ничего, «Снять фото»
	var fx_id := KitImages.import_file(PAINT_FIXTURE)
	ws.set_preset("human")
	await _frames(2)
	pt.set_tool("face")
	var hf := ws.history.size()
	var r1 := pt.set_face_image(fx_id)
	var r2 := pt.set_face_image(fx_id)
	_mouse_button(pt.screen_point_on("T"), MOUSE_BUTTON_LEFT, true)
	_mouse_button(pt.screen_point_on("T"), MOUSE_BUTTON_LEFT, false)
	var hn: Dictionary = CraftEdit.find(ws.blueprint, "H")
	var hst: Array = hn.get("stickers", [])
	_check("face_legacy_single", String(r1.get("mode", "")) == "sticker" and bool(r2.get("same", false)) and hst.size() == 1
		and bool((hst[0] as Dictionary).get("face", false)) and ws.stand.stickers_of("H").size() == 1 and ws.history.size() == hf + 1
		and not hn.has("face"), "старая голова: фото — одна наклейка с пометкой face, повтор и клик по торсу — без изменений, одна запись",
		[r1, r2, hst.size(), ws.history.size() - hf])
	var c1 := pt.clear_face()
	var c2 := pt.clear_face()
	_check("face_legacy_clear", c1 and not c2 and not CraftEdit.find(ws.blueprint, "H").has("stickers") and ws.stand.stickers_of("H").is_empty()
		and ws.history.size() == hf + 2, "«Снять фото» снимает фото-наклейку старой головы (одна запись), повторно — нечего", [c1, c2])
	# голова кита: то же фото повторно — без новой записи истории
	ws.set_preset("kit_human")
	await _frames(1)
	var hk := ws.history.size()
	var k1 := pt.set_face_image(fx_id)
	var k2 := pt.set_face_image(fx_id)
	_check("face_kit_same_noop", String(k1.get("mode", "")) == "face" and bool(k2.get("same", false)) and ws.history.size() == hk + 1,
		"голова кита: то же фото повторно — без записи истории", [k1, k2, ws.history.size() - hk])
	# замена головы кита на старую / мусорную: face снимается (face_lost), у головы кита — остаётся
	var lost_ok := true
	var lost_info := {}
	for hid in ["wood_head", "metal_head", "junk_head_sad", "kit_head_round"]:
		var b := CraftEdit.dup_body(ws.blueprint)
		CraftEdit.find(b, "H")["face"] = fx_id
		var rr := CraftEdit.attach(b, hid, "T", "Anchor_Neck")
		var kit := String(hid).begins_with("kit_")
		var keeps := String(CraftEdit.find(b, "H").get("face", "")) == fx_id
		var fl := String(rr.get("face_lost", ""))
		lost_info[hid] = [bool(rr["ok"]), keeps, fl != ""]
		lost_ok = lost_ok and bool(rr["ok"]) and keeps == kit and (fl == "" if kit else fl == fx_id)
	_check("paint_replace_face", lost_ok, "замена головы: у wood / metal / junk face снят (face_lost), у головы кита — остался", lost_info)
	# в мастерской: фото с головы кита переезжает наклейкой на лицо новой старой головы — той же записью истории
	var hr := ws.history.size()
	var rw := ws.attach_part("wood_head", "T", "Anchor_Neck", "body")
	var hn2: Dictionary = CraftEdit.find(ws.blueprint, "H")
	var hst2: Array = hn2.get("stickers", [])
	_check("face_replace_live", bool(rw.get("ok", false)) and not hn2.has("face") and hst2.size() == 1 and bool((hst2[0] as Dictionary).get("face", false))
		and String((hst2[0] as Dictionary).get("img", "")) == fx_id and ws.stand.stickers_of("H").size() == 1 and ws.history.size() == hr + 1,
		"голова кита → wood_head: фото наклейкой на новое лицо, одна запись истории", [rw.get("face_lost", ""), hst2.size(), ws.history.size() - hr])
	# раскраска плеча старой human: правое (Mesh_R, корень не зеркальный) — отражённая копия левого, байт в байт
	ws.set_preset("human")
	await _frames(2)
	pt.set_tool("pattern")
	pt.symmetry = true
	pt.apply_pattern("1", false, "camo")
	var fr := 0
	while pt.busy() and fr < 120:
		await _frames(1)
		fr += 1
	var l1 := _node_layer("1")
	var l7 := _node_layer("7")
	var mism := -1
	if l1 != null and l7 != null and l1.res == l7.res:
		mism = 0
		for z in l1.res.z:
			for y in l1.res.y:
				for x in l1.res.x:
					var a := ((z * l1.res.y + y) * l1.res.x + x) * 4
					var b := ((z * l1.res.y + y) * l1.res.x + (l1.res.x - 1 - x)) * 4
					if l1.data.slice(a, a + 4) != l7.data.slice(b, b + 4):
						mism += 1
	ws.set_preset("kit_human")
	await _frames(2)
	pt.apply_pattern("1", false, "camo")
	fr = 0
	while pt.busy() and fr < 120:
		await _frames(1)
		fr += 1
	var k1l := _node_layer("1")
	var k7l := _node_layer("7")
	_check("pattern_legacy_mirror", mism == 0 and k1l != null and k7l != null and k1l.data == k7l.data,
		"раскраска пары: у старой human правое плечо — зеркальная копия левого, у кита — те же байты (корень правой уже зеркальный)", mism)
	# бюджет кадра: раскраска всей куклы очередью — ни один шаг рисования не держит кадр (последний шаг ещё и будит правую панель
	# мастерской — ws.changed → WorkshopUI._refresh → BodyBlueprint.validate, как после любой правки; его время — отдельно)
	pt.apply_pattern("T", true, "camo")
	var steps_ms: Array = []
	while pt.busy() and steps_ms.size() < 600:
		var t0 := Time.get_ticks_usec()
		pt._pattern_step()
		steps_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
	var worst := 0.0
	for i in steps_ms.size() - 1:
		worst = maxf(worst, float(steps_ms[i]))
	var last_ms: float = steps_ms[steps_ms.size() - 1] if not steps_ms.is_empty() else -1.0
	_check("pattern_frame_budget", not pt.busy() and steps_ms.size() >= 6 and worst <= PATTERN_FRAME_MAX_MS,
		"камуфляж на всю куклу — %d шагов очереди, самый долгий %.1f мс (≤ %.0f); последний с обновлением панели — %.0f мс"
		% [steps_ms.size(), worst, PATTERN_FRAME_MAX_MS, last_ms], [steps_ms.size(), snappedf(worst, 0.1), snappedf(last_ms, 0.1)])
	# импорт в потоке
	var got: Array = []
	pt.import_files_async(PackedStringArray([ProjectSettings.globalize_path(PAINT_FIXTURE)]), func(ids: PackedStringArray) -> void:
		got.append_array(Array(ids)))
	var wf := 0
	while got.is_empty() and wf < 240:
		await _frames(1)
		wf += 1
	_check("import_async", got.size() == 1 and String(got[0]) == fx_id, "импорт в потоке (WorkerThreadPool): тот же id, колбэк на главном потоке", [got, wf])
	# картинку на кукле не удалить
	pt.set_face_image(fx_id)
	_check("image_delete_used", not pt.delete_image(fx_id) and FileAccess.file_exists(KitImages.image_path(fx_id)),
		"картинку на кукле из «Моих картинок» не удалить (кукла потеряла бы наклейку)")
	# автосейв правок: через AUTOSAVE_DELAY_S после мазка — файл (своё имя — сборку игрока не трогаем), в нём та же краска
	var an := "_probe_autosave"
	var apath := CraftEdit.save_path(an)
	if FileAccess.file_exists(apath):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(apath))
	ws.autosave_name = an
	ws.autosave_on_test = true
	pt.set_tool("spray")
	pt.set_size_cm(4.0)
	await _stroke(pt, pt.screen_point_on("2"), 6)
	await _wait(WorkshopBuild.AUTOSAVE_DELAY_S + 0.4)
	var saved := CraftEdit.load_saved(apath) if FileAccess.file_exists(apath) else null
	_check("autosave_edits", saved != null and CraftEdit.signature(saved) == CraftEdit.signature(ws.blueprint)
		and CraftEdit.find(saved, "2").has("paint"), "правка краски без «Испытать» — через %.0f с в автосейве" % WorkshopBuild.AUTOSAVE_DELAY_S,
		apath)
	ws.autosave_on_test = false
	ws.autosave_name = CraftEdit.AUTOSAVE
	if FileAccess.file_exists(apath):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(apath))
	pt.set_tool("")
	ws.clear_tools()
	ws.ui.set("shelf_tab", {"body": "limb", "weapon": "weapon_head"})
	ws.ui.call("_build_left")
	pt.symmetry = true
	pt.virtual_mouse = false
	pt.hold_check = true
	ws.set_preset("human")
	await _frames(1)


func _key_ctrl_z() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_Z
	ev.keycode = KEY_Z
	ev.ctrl_pressed = true
	ev.pressed = true
	ws._unhandled_input(ev)


func _mouse_button(p: Vector2, button: MouseButton, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = p
	ev.global_position = p
	ws._unhandled_input(ev)


func _mouse_move(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	ws._unhandled_input(ev)


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
	ws.stop_test()
	await _kit_shots()
	await _paint_shots()
	get_tree().quit(0)


## Кадры кита v2: вкладка «Материал» с кистью над плечом громилы, «Шарниры» с кружками типов, «Броня, декор» с призраком рогов.
func _kit_shots() -> void:
	var tabs: Dictionary = ws.ui.get("shelf_tab")
	ws.set_view(WorkshopBuild.View.BODY)
	ws.set_preset("kit_brawler")
	tabs["body"] = "mat"
	ws.ui.call("_build_left")
	ws.set_paint_mat("iron")
	await _wait(1.0)
	ws.set_hover({"target": "body", "uid": "7"})
	await _wait(0.2)
	await _shot("kit-mat")
	ws.set_hover({})
	tabs["body"] = "joint"
	ws.ui.call("_build_left")
	ws.set_joint_pick("motor")
	ws.set_hover({"target": "body", "uid": "2"})
	await _wait(0.3)
	await _shot("kit-joint")
	ws.set_hover({})
	ws.clear_tools()
	tabs["body"] = "armor"
	ws.ui.call("_build_left")
	ws.set_preset("kit_king")
	await _wait(0.6)
	ws.begin_drag("kit_deco_horns", Vector2(300, 700))
	var tt := {}
	for tg in ws.drag["targets"]:
		if bool(tg["ok"]) and String(tg["anchor"]) == "Anchor_Top":
			tt = tg
	if tt.is_empty():
		for tg in ws.drag["targets"]:
			if bool(tg["ok"]) and tt.is_empty():
				tt = tg
	if not tt.is_empty():
		var p := ws.target_screen_pos(tt) + Vector2(18, 12)
		for i in range(10):
			ws.update_drag(Vector2(300, 700).lerp(p, float(i + 1) / 10.0))
			await get_tree().process_frame
	await _wait(0.3)
	await _shot("kit-armor")
	ws.cancel_drag()
	tabs["body"] = "limb"
	ws.ui.call("_build_left")
	ws.set_preset("kit_bot")
	await _wait(0.6)
	await _shot("kit-limb")
	tabs["body"] = "head"
	ws.ui.call("_build_left")
	ws.set_preset("kit_horned")
	await _wait(0.6)
	await _shot("kit-head")
	tabs["body"] = "core"
	ws.ui.call("_build_left")
	ws.set_preset("kit_spider")
	await _wait(0.6)
	await _shot("kit-core")
	# UI v0.2: выбранная деталь — паспорт и действия справа; шаблоны «Вертушка» и «Пустой»
	tabs["body"] = "end"
	ws.ui.call("_build_left")
	ws.set_preset("kit_bot")
	await _wait(0.4)
	ws.select_stand("9")
	await _wait(0.4)
	await _shot("select-stand")
	ws.select_shelf("kit_hand_claw")
	await _wait(0.4)
	await _shot("select-shelf")
	ws.clear_selection()
	tabs["body"] = "limb"
	ws.ui.call("_build_left")
	ws.set_preset("kit_spinner")
	await _wait(0.6)
	await _shot("spinner")
	ws.set_preset("kit_empty")
	await _wait(0.6)
	await _shot("empty")


## Кадры покраски: вкладка «Покраска», баллончик над плечом (кольцо и кольцо пары), штрихи, звезда-трафарет, наклейка-фикстура;
## трафарет-молния с превью и сеткой масок; витрина kit_graffiti и полка раскрасок с превью узоров.
func _paint_shots() -> void:
	var pt: WorkshopPaint = ws.paint
	pt.virtual_mouse = true
	pt.hold_check = false
	ws.set_view(WorkshopBuild.View.BODY)
	ws.set_preset("kit_human")
	ws.ui.call("open_paint_tab")
	pt.set_tool("spray")
	await _wait(1.2)
	pt.size_cm = 5.0
	pt.pressure = 0.9
	pt.set_color(Color("ff4fa0"))
	var ct := pt.screen_point_on("T")
	# полоса поверху бочки и две волны по бокам окошка (симметрия: левая волна рисует и правую)
	var p0 := ct + Vector2(-75, -95)
	pt.stroke_begin(p0)
	for i in 26:
		pt.stroke_move(p0 + Vector2(i * 6.0, sin(i * 0.25) * 5.0))
		await _frames(1)
	pt.stroke_end()
	pt.set_color(Color("f26a1b"))
	pt.size_cm = 4.0
	var p1 := ct + Vector2(-58, -70)
	pt.stroke_begin(p1)
	for i in 24:
		pt.stroke_move(p1 + Vector2(sin(i * 0.4) * 8.0, i * 5.0))
		await _frames(1)
	pt.stroke_end()
	pt.size_cm = 5.0
	pt.set_color(Color("35c6d9"))
	var a := pt.screen_point_on("1")
	var b := pt.screen_point_on("2")
	pt.stroke_begin(a)
	for i in 24:
		pt.stroke_move(a.lerp(b, float(i) / 23.0) + Vector2(0, sin(i * 0.9) * 6.0))
		await _frames(1)
	pt.stroke_end()
	pt.set_tool("stencil")
	pt.stencil = "star"
	pt.set_color(Color("f7c21a"))
	pt.sticker_cm = 10.0
	pt.place_sticker(ct + Vector2(0, -72))   # над окошком ядра
	var id := KitImages.import_file(PAINT_FIXTURE)
	pt.set_tool("sticker")
	pt.image = id
	pt.sticker_cm = 11.0
	pt.place_sticker(pt.screen_point_on("4"))
	pt.set_tool("spray")
	pt.set_color(Color("ff4fa0"))
	pt.set_mouse(pt.screen_point_on("7"))
	await _wait(0.5)
	await _shot("paint")
	pt.set_tool("stencil")
	pt.stencil = "lightning"
	pt.set_color(Color("35c6d9"))
	pt.set_mouse(pt.screen_point_on("5"))
	await _wait(0.4)
	await _shot("paint-stencil")
	ws.set_preset("kit_graffiti")
	pt.set_tool("pattern")
	pt.set_mouse(Vector2(-1, -1))
	await _wait(1.0)
	await _shot("paint-presets")
	pt.virtual_mouse = false
	pt.hold_check = true


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := shots_dir.path_join("workshop-build-v1-%s.png" % tag)
	var err := img.save_png(path)
	print("saved ", path, " (", err, ")")
