## Проба «Испытания» (docs/plan-demo/GAUNTLET.md): GauntletRun (логика забега), gauntlet_fight.tscn (бой ступени) и
## playground_gauntlet.tscn (экраны и поток). Рекорд — свой файл (user://gauntlet_probe.cfg), настоящий не трогаем.
##   rules  — чистая логика: 10 боёв, арены по кругу; до первого боя чинить нечего; победа — следующая ступень, оторванное / урон /
##            износ переносятся; ровно одна починка за антракт (ветка целиком или «Подлатать корпус»), вторая — нет; запас на старт
##            не ниже GAUNTLET_MIN_HP_FRAC; ничья = поражение; конец забега — рекорд на диск (лучший, забеги, полные проходы);
##            10 побед — «пройдено»; после конца ничего не меняется;
##   ladder — бой каждой ступени: арена ступени, соперник = пресет, уровень и тяга ступени, запас × hp ступени на FIGHT!, бот —
##            параметры уровня; «сила» ступени строго растёт; перенос в бою: оторванной детали в кукле нет, запас = max − урон;
##   flow   — площадка: старт → бой → антракт (итог, соперник, починки) → починка одна, кнопки гаснут → следующий бой (непринятая
##            починка сгорает, оторванное не вернулось) → поражение → итог «пройдено N из 10», рекорд; «СДАТЬСЯ», выход посреди
##            забега — забег засчитан;
##   bots   — автопилот: за игрока бот, антракт сам; забег доходит до поражения или конца без зависаний, соперники от боя к бою
##            сильнее (уровень не падает, «сила» по живым числам сцены растёт), каждый бой кончился, рекорд записан.
## Ошибок скриптов и движка — 0 (ошибки загрузки ресурсов с диска — отдельно, info.errors_assets; пустышка рендера headless
## servers/rendering/dummy «Parameter "material" is null» в бою с ударами — отдельно, info.errors_dummy_render, как в hockey_probe).
## Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/gauntlet_probe.tscn -- "only=rules|ladder|flow|bots|rules+ladder,max_s=1500,fight_s=45,out=<json>"
##   bots: edge=2.0, pilot_level=5, armor=0.15 — фора автопилоту (тяга × edge, уровень бота, входящий урон × armor); seed=1 —
##         сид глобального ГСЧ; trace=1 — строка раз в 5 с боя (удары, ❤ и центр масс P1/P2); pilot=0 — без автопилота (отладка).
##   Прогоны параллельно не запускать: рекорд пробы — один файл в user://.
## → JSON между === GAUNTLET PROBE === и === OK / FAIL ===, exit 0/1.
extends Node

const SCENE := "res://scenes/playground_gauntlet.tscn"
const FIGHT_SCENE := "res://scenes/gauntlet/gauntlet_fight.tscn"
const SAVE := "user://gauntlet_probe.cfg"
const TICK := 1.0 / 60.0
const COUNTDOWN_S := 0.2


## Счётчик SCRIPT ERROR за прогон (как king_probe): ошибка скрипта обрывает только свою функцию — проба могла бы молча потерять
## проверки. Ошибки загрузки ресурсов с диска — к режиму не относятся: отдельно, в info.
class ScriptErrors extends Logger:
	var count := 0
	var first := ""
	var engine := 0
	var engine_first := ""
	var assets := 0
	var assets_first := ""
	var dummy := 0
	var dummy_first := ""
	var _mx := Mutex.new()

	static func _is_asset_load(file: String, code: String, rationale: String) -> bool:
		var msg := code + " " + rationale
		return file.begins_with("core/io/resource") or file.begins_with("scene/resources/resource_format_text") \
			or msg.contains("Failed loading resource") or msg.contains("res://.godot/imported/")

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		_mx.lock()
		if error_type == ERROR_TYPE_SCRIPT:
			count += 1
			if first == "":
				first = "%s %s (%s:%d %s)" % [code, rationale, file, line, function]
		elif error_type == ERROR_TYPE_ERROR and _is_asset_load(file, code, rationale):
			assets += 1
			if assets_first == "":
				assets_first = "%s %s (%s:%d)" % [code, rationale, file, line]
		elif error_type == ERROR_TYPE_ERROR and file.begins_with("servers/rendering/dummy"):
			dummy += 1
			if dummy_first == "":
				dummy_first = "%s (%s:%d %s)" % [code, file, line, function]
		elif error_type == ERROR_TYPE_ERROR:
			engine += 1
			if engine_first == "":
				var where := ""
				if not script_backtraces.is_empty() and script_backtraces[0].get_frame_count() > 0:
					where = " ← %s:%d" % [script_backtraces[0].get_frame_file(0), script_backtraces[0].get_frame_line(0)]
				engine_first = "%s (%s:%d)%s" % [code, file, line, where]
		_mx.unlock()


var ok := true
var checks: Array = []
var info := {}
var pg: GauntletPlayground
var errs := ScriptErrors.new()
var _save_before := ""
var _modes_before: Array = []


func _check(id: String, cond: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": cond, "detail": str(detail)})
	if not cond:
		ok = false
	print("  %-32s %s  %s" % [id, "ok  " if cond else "FAIL", str(detail)])


func _args() -> Dictionary:
	var out := {"only": "", "max_s": "1500", "fight_s": "45", "out": "", "trace": "0", "pilot": "1", "edge": "2.0", "pilot_level": "5", "seed": "1", "armor": "0.15"}
	for a in OS.get_cmdline_user_args():
		for part in String(a).split(","):
			var kv := part.split("=")
			if kv.size() == 2 and out.has(kv[0]):
				out[kv[0]] = kv[1]
	return out


func _want(a: Dictionary, section: String) -> bool:
	return String(a["only"]) == "" or section in String(a["only"]).split("+")


func _ready() -> void:
	OS.add_logger(errs)
	print("=== GAUNTLET PROBE ===")
	_save_before = GauntletRun.save_path
	GauntletRun.save_path = SAVE
	_modes_before = [PartHp.on, JointBreak.on]
	var a := _args()
	if _want(a, "rules"):
		_rules()
	if _want(a, "ladder"):
		await _ladder()
	if _want(a, "flow"):
		await _flow()
	if _want(a, "bots"):
		await _bots(float(a["max_s"]), float(a["fight_s"]), String(a["trace"]) == "1")
	await _unload()
	GauntletRun.erase_record()
	GauntletRun.save_path = _save_before
	PartHp.set_on(bool(_modes_before[0]))
	JointBreak.on = bool(_modes_before[1])
	_check("modes_restored", PartHp.on == bool(_modes_before[0]), "PartHp %s → %s" % [_modes_before[0], PartHp.on])
	_check("errors_script", errs.count == 0, "ошибок скриптов %d; первая: %s" % [errs.count, errs.first])
	_check("errors_engine", errs.engine == 0, "ошибок движка %d; первая: %s" % [errs.engine, errs.engine_first])
	info["errors_assets"] = {"count": errs.assets, "first": errs.assets_first}
	info["errors_dummy_render"] = {"count": errs.dummy, "first": errs.dummy_first}
	var report := {"ok": ok, "checks": checks, "info": info}
	print(JSON.stringify(report, " "))
	if String(a["out"]) != "":
		var f := FileAccess.open(String(a["out"]), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(report, " "))
			f.close()
	print("=== OK ===" if ok else "=== FAIL ===")
	OS.remove_logger(errs)
	get_tree().quit(0 if ok else 1)


# ------------------------------------------------------------------ rules

func _fake_body(r: GauntletRun) -> void:
	r.part_max = {"Torso": 40.0, "Head": 20.0, "UpperArm_L": 10.0, "LowerArm_L": 8.0, "Hand_L": 4.0, "Thigh_R": 12.0, "Shin_R": 6.0}
	r.parent_of = {"Head": "Torso", "UpperArm_L": "Torso", "LowerArm_L": "UpperArm_L", "Hand_L": "LowerArm_L", "Thigh_R": "Torso",
		"Shin_R": "Thigh_R"}
	r.part_title = {"UpperArm_L": "Плечо", "LowerArm_L": "Предплечье", "Hand_L": "Кисть", "Thigh_R": "Бедро", "Shin_R": "Голень"}


func _rules() -> void:
	print("— rules")
	GauntletRun.erase_record()
	_check("rules_fights_10", GauntletRun.fights() == 10 and (Tuning.GAUNTLET_LADDER as Array).size() == 10,
		"боёв %d, ступеней %d" % [GauntletRun.fights(), (Tuning.GAUNTLET_LADDER as Array).size()])
	var arenas: PackedStringArray = []
	var scenes_ok := true
	for i in GauntletRun.fights():
		arenas.append(GauntletRun.arena(i))
		var a: Dictionary = Tuning.GAUNTLET_ARENA.get(GauntletRun.arena(i), {})
		scenes_ok = scenes_ok and ResourceLoader.exists(String(a.get("scene", ""))) and (a.get("spawn", []) as Array).size() == 2
	var distinct := {}
	for k in arenas:
		distinct[k] = true
	_check("rules_arenas_rotate", distinct.size() == 5 and arenas[0] == arenas[5] and arenas[0] != arenas[1] and scenes_ok,
		", ".join(arenas))
	var presets_ok := true
	for i in GauntletRun.fights():
		presets_ok = presets_ok and GauntletRun.rival_blueprint(i) != null
	_check("rules_presets_exist", presets_ok, "все пресеты лестницы грузятся")

	var r := GauntletRun.new()
	_fake_body(r)
	_check("rules_no_repair_before_first", not r.apply_repair(0) and r.step == 0 and not r.over, "до первого боя починки нет")
	# бой 1: победа, оторвана рука от плеча, урон 20, износ бедра
	r.record_result(true, {"duration_s": 31.0}, {"lost": ["UpperArm_L", "LowerArm_L", "Hand_L"], "deficit": 20.0,
		"wear": {"Thigh_R": 5.0}, "hp": 30.0, "max_hp": 78.0})
	_check("rules_win_advances", r.step == 1 and r.cleared == 1 and not r.over and not r.repair_used,
		"step %d cleared %d over %s repair_used %s" % [r.step, r.cleared, r.over, r.repair_used])
	_check("rules_carry_lost", Array(r.lost) == ["UpperArm_L", "LowerArm_L", "Hand_L"] and is_equal_approx(r.deficit, 20.0)
		and r.wear.has("Thigh_R") and (r.last["lost_now"] as PackedStringArray).size() == 3,
		"lost %s deficit %.0f wear %s" % [r.lost, r.deficit, r.wear])
	var pool := r.pool_max()
	_check("rules_pool_without_lost", is_equal_approx(pool, 78.0), "запас без оторванного %.0f (ждём 78)" % pool)
	_check("rules_start_hp", is_equal_approx(r.start_hp(78.0), 58.0), "на старт %.0f (78 − 20)" % r.start_hp(78.0))
	var opts := r.repair_options()
	_check("rules_repair_options", opts.size() == 2 and String(opts[0]["kind"]) == "branch" and String(opts[0]["part"]) == "UpperArm_L"
		and int(opts[0]["parts"]) == 3 and is_equal_approx(float(opts[0]["hp"]), 22.0) and String(opts[1]["kind"]) == "patch",
		str(opts))
	# не принятая починка: поражение в следующем бою не должно ничего «починить»
	var ok1 := r.apply_repair(0)
	var ok2 := r.apply_repair(1)
	_check("rules_exactly_one_repair", ok1 and not ok2 and r.lost.is_empty() and r.repair_used and r.repaired != ""
		and is_equal_approx(r.deficit, 20.0) and not r.wear.has("UpperArm_L"),
		"первая %s, вторая %s, lost %s, deficit %.0f" % [ok1, ok2, r.lost, r.deficit])
	# бой 2: победа; урон копится (снимок — итог, не прибавка), голень оторвана
	r.record_result(true, {"duration_s": 40.0}, {"lost": ["Shin_R"], "deficit": 60.0, "wear": {"Thigh_R": 9.0}, "hp": 34.0,
		"max_hp": 94.0})
	_check("rules_second_win", r.step == 2 and r.cleared == 2 and Array(r.lost) == ["Shin_R"] and is_equal_approx(r.deficit, 60.0)
		and not r.repair_used, "step %d lost %s deficit %.0f" % [r.step, r.lost, r.deficit])
	var patch_i := r.repair_options().size() - 1
	var pool2 := r.pool_max()
	r.apply_repair(patch_i)
	var want_def := maxf(60.0 - pool2 * Tuning.GAUNTLET_REPAIR_POOL_FRAC, 0.0)
	_check("rules_patch_repair", is_equal_approx(r.deficit, want_def) and r.wear.is_empty() and Array(r.lost) == ["Shin_R"],
		"deficit %.1f (ждём %.1f), wear %s, lost %s" % [r.deficit, want_def, r.wear, r.lost])
	_check("rules_min_hp_floor", is_equal_approx(GauntletRun.new().start_hp(100.0), 100.0) and _floor_ok(),
		"запас не ниже %.0f %%" % (Tuning.GAUNTLET_MIN_HP_FRAC * 100.0))
	# бой 3: ничья = поражение, конец забега, рекорд
	r.record_result(true, {"draw": true, "reason": "time"}, {"lost": [], "deficit": 10.0, "hp": 50.0, "max_hp": 94.0})
	var rec := GauntletRun.load_record()
	_check("rules_draw_is_loss", r.over and not r.won_all and r.cleared == 2 and not bool(r.last["won"]) and bool(r.last["draw"]),
		"over %s cleared %d last %s" % [r.over, r.cleared, r.last])
	_check("rules_loss_saves_record", int(rec["best"]) == 2 and int(rec["runs"]) == 1 and int(rec["wins"]) == 0, str(rec))
	r.record_result(true, {}, {"lost": ["Torso"]})
	_check("rules_frozen_after_over", r.cleared == 2 and r.history.size() == 3 and not r.apply_repair(0), "после конца ничего не меняется")
	# полный проход
	var w := GauntletRun.new()
	for i in GauntletRun.fights():
		w.record_result(true, {"duration_s": 20.0}, {"lost": [], "deficit": 0.0, "hp": 100.0, "max_hp": 100.0})
	rec = GauntletRun.load_record()
	_check("rules_ten_wins", w.over and w.won_all and w.cleared == 10 and w.repair_used and not w.apply_repair(0),
		"cleared %d won_all %s" % [w.cleared, w.won_all])
	_check("rules_record_best", int(rec["best"]) == 10 and int(rec["runs"]) == 2 and int(rec["wins"]) == 1, str(rec))
	var l := GauntletRun.new()
	l.record_result(false, {"reason": "ko"}, {})
	rec = GauntletRun.load_record()
	_check("rules_record_keeps_best", int(rec["best"]) == 10 and int(rec["runs"]) == 3 and l.best_before == 10 and l.cleared == 0, str(rec))
	GauntletRun.erase_record()
	_check("rules_record_erased", int(GauntletRun.load_record()["runs"]) == 0, "файл пробы стёрт")


func _floor_ok() -> bool:
	var r := GauntletRun.new()
	r.deficit = 95.0
	return is_equal_approx(r.start_hp(100.0), 100.0 * Tuning.GAUNTLET_MIN_HP_FRAC)


# ------------------------------------------------------------------ ladder

func _drive_k() -> float:
	return Tuning.DRIVE_MAX_HP / Tuning.MAX_HP if Drive.on else 1.0


func _ladder() -> void:
	print("— ladder")
	PartHp.set_on(true)
	var ps := (load(FIGHT_SCENE) as PackedScene)
	var player := CampaignLeague.preset(CampaignLeague.START_PRESET)
	var rows: Array = []
	var prev_power := -1.0
	var prev_level := 0
	var power_up := true
	var level_up := true
	var all_ok := true
	var bad := ""
	var limb := ""
	for i in GauntletRun.fights():
		var r := GauntletRun.new()
		r.step = i
		if i == 1 and limb != "":
			r.lost = PackedStringArray([limb])
			r.deficit = 25.0
		var f := ps.instantiate()
		f.set("result_delay_s", 0.1)
		f.call("setup_gauntlet", player, r, i, false)
		var m := f.get_node("Match") as Match
		m.countdown_s = COUNTDOWN_S
		m.feel_enabled = false
		add_child(f)
		var p1 := f.get_node("P1") as Doll
		var p2 := f.get_node("P2") as Doll
		var brain := f.get_node("P2/Brain") as GauntletBrain
		for k in 90:
			if m.phase == Match.Phase.FIGHT:
				break
			await get_tree().physics_frame
		await get_tree().physics_frame
		var step: Dictionary = GauntletRun.rival(i)
		var want_hp := roundf(GauntletRun.rival_max_hp(i) * _drive_k())
		var arena := f.get_node_or_null("Arena")
		var arena_scene := String((Tuning.GAUNTLET_ARENA[GauntletRun.arena(i)] as Dictionary)["scene"])
		var lp := GauntletRun.level_params(int(step["level"]))
		var row := {"i": i + 1, "preset": String(step["preset"]), "title": GauntletRun.rival_title(i), "arena": GauntletRun.arena(i),
			"level": brain.level, "thrust": p2.thrust_mult, "max_hp": p2.max_hp, "want_hp": want_hp,
			"body_hp": (p2 as ModularDoll).blueprint.parts_hp_total(), "reaction_s": brain.reaction_s, "power": GauntletRun.power(i),
			"phase_fight": m.phase == Match.Phase.FIGHT}
		rows.append(row)
		var good := m.phase == Match.Phase.FIGHT and arena != null and arena.scene_file_path == arena_scene and arena.is_in_group("arena") \
			and (p2 as ModularDoll).blueprint.id == String(step["preset"]) and brain.level == int(step["level"]) \
			and is_equal_approx(p2.thrust_mult, float(step["thrust"])) and absf(p2.max_hp - want_hp) <= 1.5 \
			and is_equal_approx(p2.hp, p2.max_hp) and is_equal_approx(brain.reaction_s, float(lp["reaction_s"])) \
			and is_equal_approx(p1.hp, r.start_hp(p1.max_hp))
		if not good:
			all_ok = false
			if bad == "":
				bad = str(row)
		if GauntletRun.power(i) <= prev_power:
			power_up = false
		if brain.level < prev_level:
			level_up = false
		prev_power = GauntletRun.power(i)
		prev_level = brain.level
		if i == 0:
			limb = _pick_limb(r)
			info["ladder_limb"] = limb
		elif i == 1 and limb != "":
			_check("ladder_carry_missing", not p1.parts.has(limb) and p1.lost_part_names().has(limb),
				"«%s» в кукле нет: %s; lost %s" % [limb, not p1.parts.has(limb), p1.lost_part_names()])
			_check("ladder_carry_deficit", is_equal_approx(p1.hp, maxf(p1.max_hp - 25.0, p1.max_hp * Tuning.GAUNTLET_MIN_HP_FRAC)),
				"запас %.0f из %.0f (урон 25)" % [p1.hp, p1.max_hp])
		remove_child(f)
		f.queue_free()
		await get_tree().physics_frame
	info["ladder"] = rows
	_check("ladder_fights_match_table", all_ok, "первая не та ступень: %s" % bad if bad != "" else "10 ступеней сходятся с таблицей")
	_check("ladder_power_strictly_up", power_up, "сила: %s" % str(rows.map(func(x: Dictionary) -> float: return snappedf(x["power"], 0.01))))
	_check("ladder_level_not_down", level_up, "уровни: %s" % str(rows.map(func(x: Dictionary) -> int: return x["level"])))
	_check("ladder_limb_found", limb != "", "деталь для переноса: %s" % limb)


## Деталь игрока с самой большой веткой, без головы в ней (её отрыв — не KO).
func _pick_limb(r: GauntletRun) -> String:
	var best := ""
	var best_n := -1
	for n in r.part_title:
		var sub := 0
		var has_head := false
		for c in r.part_max:
			var p := String(c)
			var guard := 0
			while p != "" and p != n and guard < 64:
				p = String(r.parent_of.get(p, ""))
				guard += 1
			if p == n:
				sub += 1
				if String(c).begins_with("Head"):
					has_head = true
		if has_head or String(n).begins_with("Torso") or String(n).begins_with("Head"):
			continue
		if sub > best_n or (sub == best_n and String(n) < best):
			best = String(n)
			best_n = sub
	return best


# ------------------------------------------------------------------ flow

func _load(autopilot := false, fight_s := -1.0, delay := 0.1) -> void:
	await _unload()
	Engine.time_scale = 1.0
	pg = (load(SCENE) as PackedScene).instantiate() as GauntletPlayground
	pg.autopilot = autopilot
	pg.use_workshop = false   # кит «Человек»: проба не зависит от автосейва мастерской на этой машине
	pg.fight_time_limit_s = fight_s
	pg.result_delay_s = delay
	pg.fight_created.connect(func(f: Node) -> void:
		var m := f.get_node("Match") as Match
		m.countdown_s = COUNTDOWN_S
		m.feel_enabled = false)
	add_child(pg)
	await get_tree().physics_frame


func _unload() -> void:
	if Flow.is_paused():
		Flow.close_pause()
	if pg != null and is_instance_valid(pg):
		remove_child(pg)
		pg.queue_free()
		pg = null
		await get_tree().physics_frame


func _until(cond: Callable, max_s: float) -> bool:
	for i in int(max_s / TICK):
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _fight_match() -> Match:
	if pg == null or pg.fight == null or not is_instance_valid(pg.fight):
		return null
	return pg.fight.get_node_or_null("Match") as Match


func _in_fight() -> bool:
	var m := _fight_match()
	return m != null and m.phase == Match.Phase.FIGHT


func _flow() -> void:
	print("— flow")
	GauntletRun.erase_record()
	var part_was := PartHp.on
	PartHp.set_on(false)
	await _load()
	_check("flow_parthp_on", PartHp.on, "в Испытании «Запас из деталей» включён")
	_check("flow_start_screen", pg.screen == GauntletPlayground.Screen.START and pg.start_ui.visible and not pg.break_ui.visible
		and pg._start_ladder.get_child_count() == 10, "старт: лестница %d строк" % pg._start_ladder.get_child_count())
	pg.start_run()
	await _until(_in_fight, 5.0)
	var p1 := pg.fight.get_node("P1") as Doll
	_check("flow_fight_1", pg.screen == GauntletPlayground.Screen.FIGHT and not pg.start_ui.visible and pg.fight.get_parent() == pg.stage
		and _in_fight() and int(pg.fight.get("index")) == 0, "бой 1 в Stage, фаза FIGHT")
	# снимок как после боя: оторвана крупная ветка, урон 25
	var limb := _pick_limb(pg.run)
	var snap := GauntletRun.snapshot(p1)
	snap["lost"] = PackedStringArray([limb])
	snap["deficit"] = 25.0
	await get_tree().process_frame   # отложенные вызовы кадра физики (env_slam) — до снятия боя
	pg.finish_fight(true, {"won": true, "duration_s": 30.0, "snapshot": snap})
	await get_tree().physics_frame
	var opts := pg.run.repair_options()
	_check("flow_break_screen", pg.screen == GauntletPlayground.Screen.BREAK and pg.break_ui.visible and pg.fight == null
		and pg.stage.get_child_count() == 0, "антракт после победы, бой убран")
	_check("flow_break_next_rival", pg._rival_name.text.contains(GauntletRun.rival_title(1)) and pg._rival_stats.text.contains(
		GauntletRun.arena_title(1)) and pg._rival_tex != null, pg._rival_name.text + " | " + pg._rival_stats.text.replace("\n", " "))
	_check("flow_break_repairs", pg._break_repairs.get_child_count() == opts.size() and opts.size() >= 2 and _buttons_enabled(true),
		"кнопок починки %d (вариантов %d)" % [pg._break_repairs.get_child_count(), opts.size()])
	var r1 := pg.apply_repair(0)
	await get_tree().physics_frame
	var r2 := pg.apply_repair(1)
	await get_tree().physics_frame
	_check("flow_one_repair", r1 and not r2 and not pg.run.lost.has(limb) and _buttons_enabled(false),
		"первая %s, вторая %s, «%s» вернули: %s, кнопки погасли: %s" % [r1, r2, limb, not pg.run.lost.has(limb), _buttons_enabled(false)])
	pg.start_fight()
	await _until(_in_fight, 5.0)
	p1 = pg.fight.get_node("P1") as Doll
	_check("flow_fight_2", int(pg.fight.get("index")) == 1 and p1.parts.has(limb) and is_equal_approx(p1.hp, pg.run.start_hp(p1.max_hp))
		and p1.hp < p1.max_hp, "бой 2: «%s» на месте (починили), запас %.0f из %.0f" % [limb, p1.hp, p1.max_hp])
	# бой 2 — снова оторвали, починку не берём
	snap = GauntletRun.snapshot(p1)
	snap["lost"] = PackedStringArray([limb])
	snap["deficit"] = 10.0
	await get_tree().process_frame   # отложенные вызовы кадра физики (env_slam) — до снятия боя
	pg.finish_fight(true, {"won": true, "duration_s": 20.0, "snapshot": snap})
	await get_tree().physics_frame
	pg.start_fight()   # починку не взяли — сгорела
	await _until(_in_fight, 5.0)
	p1 = pg.fight.get_node("P1") as Doll
	_check("flow_parts_not_repaired", pg.run.repair_used and not p1.parts.has(limb) and p1.lost_part_names().has(limb)
		and not pg.apply_repair(0), "бой 3 без «%s», починка сгорела" % limb)
	# бой 3 — поражение
	await get_tree().process_frame   # отложенные вызовы кадра физики (env_slam) — до снятия боя
	pg.finish_fight(false, {"won": false, "reason": "ko", "duration_s": 12.0, "snapshot": GauntletRun.snapshot(p1)})
	await get_tree().physics_frame
	var rec := GauntletRun.load_record()
	_check("flow_loss_result", pg.screen == GauntletPlayground.Screen.RESULT and pg.result_ui.visible and pg.run.over
		and pg._result_detail.text.contains(tr("Пройдено %d из %d") % [2, 10]), pg._result_detail.text.replace("\n", " | "))
	_check("flow_record_saved", int(rec["best"]) == 2 and int(rec["runs"]) == 1, str(rec))
	# ЕЩЁ РАЗ → бой 1 нового забега, «СДАТЬСЯ» в антракте
	pg.start_run()
	await _until(_in_fight, 5.0)
	_check("flow_again", pg.run.step == 0 and pg.run.cleared == 0 and pg.run.lost.is_empty() and int(pg.fight.get("index")) == 0,
		"новый забег с боя 1")
	await get_tree().process_frame   # отложенные вызовы кадра физики (env_slam) — до снятия боя
	pg.finish_fight(true, {"won": true, "duration_s": 10.0, "snapshot": GauntletRun.snapshot(pg.fight.get_node("P1") as Doll)})
	await get_tree().physics_frame
	pg.give_up_to_result()
	rec = GauntletRun.load_record()
	_check("flow_give_up", pg.screen == GauntletPlayground.Screen.RESULT and pg.run.over and pg.run.cleared == 1
		and int(rec["runs"]) == 2 and int(rec["best"]) == 2, "сдался после 1 победы: %s" % rec)
	# «ЗАНОВО» в паузе боя: сдаться и сначала
	pg.start_run()
	await _until(_in_fight, 5.0)
	await get_tree().process_frame
	pg.fight.call("_give_up")
	await _until(_in_fight, 5.0)
	rec = GauntletRun.load_record()
	_check("flow_restart_in_fight", int(rec["runs"]) == 3 and pg.run.step == 0 and not pg.run.over and _in_fight(),
		"ЗАНОВО — забег засчитан, новый идёт: %s" % rec)
	# выход посреди забега — забег засчитан, режимы вернулись
	await _unload()
	rec = GauntletRun.load_record()
	_check("flow_exit_counts_run", int(rec["runs"]) == 4, str(rec))
	_check("flow_parthp_restored", PartHp.on == false, "после выхода PartHp как был (выкл.)")
	PartHp.set_on(part_was)
	GauntletRun.erase_record()


func _buttons_enabled(want: bool) -> bool:
	for b in pg._break_repairs.get_children():
		if (b as Button).disabled == want:
			return false
	return pg._break_repairs.get_child_count() > 0


# ------------------------------------------------------------------ bots

func _bots(max_s: float, fight_s: float, trace := false) -> void:
	print("— bots")
	seed(int(_args()["seed"]))   # исход боёв зависит от глобального ГСЧ (боты, голосование зрителей): без сида — от прошлых секций
	GauntletRun.erase_record()
	await _load(String(_args()["pilot"]) != "0", fight_s, 0.3)
	var fights: Array = []
	var hard := fight_s * 2.0 + 15.0
	# Фора автопилоту (только проба): бот за игрока — уровень pilot_level, тяга × edge. Кит «Человек» (100 ❤) против kit_horned (192 ❤)
	# без форы падает в первом же бою — так и в «Истории»; проба проверяет поток и рост соперников (≥ 2 боёв), не баланс.
	# Исход боя хаотичен: тот же сид после секции flow (другие RID и порядок тел в физике) давал проигрыш боя 1 за 12 с при тяге × 2 и
	# уровне 5 — поэтому ещё и броня (incoming_mult): урон по P1 × armor (не 0: урон и износ всё ещё переносятся между боями).
	var edge := float(_args()["edge"])
	var pilot_level := int(_args()["pilot_level"])
	var armor := float(_args()["armor"])
	pg.fight_created.connect(func(f: Node) -> void:   # лямбда ловит локальные по значению: строку боя кладём в массив (он общий по ссылке)
		var d1 := f.get_node("P1") as Doll
		d1.thrust_mult *= edge
		d1.incoming_mult = armor
		var ab := d1.get_node_or_null("AutoBrain")
		if is_instance_valid(ab) and ab is GauntletBrain:
			(ab as GauntletBrain).level = pilot_level
		fights.append({"i": int(f.get("index")) + 1, "t": 0.0, "fight": f}))
	pg.start_run()
	var t := 0.0
	var stuck := ""
	var fx := 0
	while t < max_s and not pg.run.over:
		await get_tree().physics_frame
		t += TICK
		var cur: Dictionary = fights.back() if not fights.is_empty() else {}
		if not cur.is_empty():
			cur["t"] = float(cur["t"]) + TICK
			var f: Variant = cur["fight"]   # бой уже освобождён после итога — в типизированную переменную не кладём
			if is_instance_valid(f) and not cur.has("level"):
				var m := f.get_node_or_null("Match") as Match
				if m != null and m.phase == Match.Phase.FIGHT:
					var p2 := f.get_node("P2") as Doll
					var br := f.get_node("P2/Brain") as GauntletBrain
					var base := (p2 as ModularDoll).blueprint.parts_hp_total() * _drive_k()
					cur["level"] = br.level
					cur["thrust"] = p2.thrust_mult
					cur["max_hp"] = p2.max_hp
					cur["reaction_s"] = br.reaction_s
					cur["power"] = p2.thrust_mult * (p2.max_hp / maxf(base, 1.0)) * (0.5 / maxf(br.reaction_s, 0.05))
					cur["p1_hp"] = (f.get_node("P1") as Doll).hp
					cur["p1_max"] = (f.get_node("P1") as Doll).max_hp
					cur["p1_lost"] = (f.get_node("P1") as Doll).lost_part_names().size()
			if is_instance_valid(f):
				var m2 := f.get_node_or_null("Match") as Match
				if m2 != null:
					fx = maxi(fx, m2.hit_fx_count)
				if trace and int(round(float(cur["t"]) / TICK)) % 300 == 1:
					var line := "    бой %d t=%.0f удары %d" % [int(cur["i"]), float(cur["t"]), m2.hit_fx_count if m2 != null else -1]
					for nm in ["P1", "P2"]:
						var d := f.get_node_or_null(nm) as Doll
						if is_instance_valid(d):
							line += " | %s %.0f/%.0f ❤ ЦМ %s" % [nm, d.hp, d.max_hp, str(d.centre_of_mass().snapped(Vector3.ONE * 0.1))]
					print(line)
			if float(cur["t"]) > hard and stuck == "":
				stuck = "бой %d идёт %.0f с" % [int(cur["i"]), float(cur["t"])]
				break
	var rows: Array = []
	for c in fights:
		var row: Dictionary = c.duplicate()
		row.erase("fight")
		row["t"] = snappedf(float(row["t"]), 0.1)
		if row.has("power"):
			row["power"] = snappedf(float(row["power"]), 0.001)
		rows.append(row)
	var rec := GauntletRun.load_record()
	info["bots"] = {"t": snappedf(t, 0.1), "cleared": pg.run.cleared, "won_all": pg.run.won_all, "history": pg.run.history,
		"fights": rows, "record": rec, "lost_end": pg.run.lost, "deficit_end": pg.run.deficit}
	print("  забег: пройдено %d из 10 за %.0f с; бои: %s" % [pg.run.cleared, t, str(rows.map(func(x: Dictionary) -> String:
		return "%d:L%d/%.2f/%.0f❤ %.0fс" % [int(x["i"]), int(x.get("level", 0)), float(x.get("power", 0.0)), float(x.get("max_hp", 0.0)), float(x["t"])]))])
	_check("bots_run_over", pg.run.over and stuck == "", "забег кончился (%s)" % (stuck if stuck != "" else "%.0f с" % t))
	_check("bots_fights_count", fights.size() == pg.run.history.size() and fights.size() == pg.run.cleared + (0 if pg.run.won_all else 1),
		"боёв %d, в истории %d, пройдено %d" % [fights.size(), pg.run.history.size(), pg.run.cleared])
	var stronger := true
	var lvl := true
	var measured := true
	for k in rows.size():
		measured = measured and rows[k].has("power")
		if k > 0 and rows[k].has("power") and rows[k - 1].has("power"):
			stronger = stronger and float(rows[k]["power"]) > float(rows[k - 1]["power"])
			lvl = lvl and int(rows[k]["level"]) >= int(rows[k - 1]["level"])
	_check("bots_two_fights", fights.size() >= 2 or pg.run.won_all, "боёв в забеге %d (рост соперников виден с двух)" % fights.size())
	_check("bots_each_fight_started", measured, "каждый бой дошёл до FIGHT!")
	_check("bots_rivals_stronger", stronger and lvl, "сила по сцене: %s" % str(rows.map(func(x: Dictionary) -> float: return float(x.get("power", 0.0)))))
	_check("bots_ladder_values", _rows_match_ladder(rows), "уровень/тяга соперника = таблице")
	_check("bots_hits", fx > 0, "ударов с эффектом (макс. за бой) %d" % fx)
	_check("bots_record", int(rec["runs"]) == 1 and int(rec["best"]) == pg.run.cleared and pg.screen == GauntletPlayground.Screen.RESULT,
		"рекорд %s, экран итога" % rec)
	# перенос между боями у живого забега: запас P1 на FIGHT! не выше полного и не ниже пола
	var carry := true
	for row in rows:
		if row.has("p1_hp"):
			carry = carry and float(row["p1_hp"]) <= float(row["p1_max"]) + 0.01 \
				and float(row["p1_hp"]) >= float(row["p1_max"]) * Tuning.GAUNTLET_MIN_HP_FRAC - 0.01
	_check("bots_carry_sane", carry, "запас P1 на старт боёв: %s" % str(rows.map(func(x: Dictionary) -> String:
		return "%.0f/%.0f −%d" % [float(x.get("p1_hp", 0.0)), float(x.get("p1_max", 0.0)), int(x.get("p1_lost", 0))])))
	await _unload()
	GauntletRun.erase_record()


func _rows_match_ladder(rows: Array) -> bool:
	for row in rows:
		var i := int(row["i"]) - 1
		var st: Dictionary = GauntletRun.rival(i)
		if not row.has("level") or int(row["level"]) != int(st["level"]) or not is_equal_approx(float(row["thrust"]), float(st["thrust"])):
			return false
	return true
