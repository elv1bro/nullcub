## Проба «Захвата точек» (docs/plan-demo/DOMINATION.md) на настоящей площадке scenes/playground_domination.tscn (Полигон, шесть бойцов,
## DominationMatch, DominationZone, DominationHud, DominationBrain). Площадка — без экрана настроек (use_settings = false).
##   rules (P1 — человек без ввода, боты молчат, ящики выключены; бойцов в зоны переносит проба — настоящая физика и счёт присутствия):
##     три зоны и их узлы, всё нейтрально, режим и числа; присутствие (центр масс в круге); один захватывает за DOM_CAPTURE_S, событие,
##     опыт и «захваты» в итоги; очко в секунду за зону; трое — с потолком скорости (DOM_CAPTURE_MAX); начатая полоска пустой
##     нейтральной стекает; спорная стоит; чужая начатая сначала стекает, потом захват; чужая своя — нейтрализация, потом захват;
##     пустая своя доливается; выбывание очков не даёт; до score_to_win — победа (счёт не выше цели); заново — сброс, узлы зон не
##     дублируются; по времени — побеждает ведущая; план ботов (по зоне каждому); настройки (SquadSettings «dom») и сцена под них;
##   bots (P1 тоже бот): матч ботов 3 на 3 до конца (DOM_SCORE_TO_WIN или DOM_TIME_S) — зоны берут обе команды, победитель есть,
##     огонь по своим не ранит, все в границах карты, никто не застрял вне зоны; темп, счёт и журнал зон — в info.
## Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/domination_probe.tscn -- "only=rules|bots|rules+bots,max_s=420,level=2,score=100,trace=1,out=<json>"
## → JSON между === DOMINATION PROBE === и === OK / FAIL ===, exit 0/1. errors_script — SCRIPT ERROR за прогон (Logger).
extends Node

const SCENE := "res://scenes/playground_domination.tscn"
const TICK := 1.0 / 60.0
const A := 0
const B := 1
const C := 2

## Счётчик SCRIPT ERROR за прогон: ошибка скрипта обрывает только свою функцию — проба могла бы молча потерять проверки.
class ScriptErrors extends Logger:
	var count := 0
	var first := ""
	var _mx := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mx.lock()
		count += 1
		if first == "":
			first = "%s %s (%s:%d %s)" % [code, rationale, file, line, function]
		_mx.unlock()


var ok := true
var checks: Array = []
var info := {}
var pg: DominationPlayground
var sm: DominationMatch
var over_results: Dictionary = {}
var over_count := 0
var events: Array = []
var errs := ScriptErrors.new()


func _check(id: String, cond: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": cond, "detail": str(detail)})
	if not cond:
		ok = false
	print("  %-34s %s  %s" % [id, "ok  " if cond else "FAIL", str(detail)])


func _args() -> Dictionary:
	var out := {"only": "", "max_s": "420", "level": "2", "trace": "0", "out": "", "score": str(Tuning.DOM_SCORE_TO_WIN)}
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
	print("=== DOMINATION PROBE ===")
	var a := _args()
	if _want(a, "rules"):
		await _rules()
	if _want(a, "bots"):
		await _bots(float(a["max_s"]), int(a["level"]), String(a["trace"]) == "1", int(a["score"]))
	await _unload()
	_check("errors_script", errs.count == 0, "ошибок скриптов %d; первая: %s" % [errs.count, errs.first])
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


# ------------------------------------------------------------------ помощники

func _load(p1_bot: bool, level := 2, countdown := 0.3, supplies := false) -> void:
	await _unload()
	Engine.time_scale = 1.0
	pg = (load(SCENE) as PackedScene).instantiate() as DominationPlayground
	pg.p1_bot = p1_bot
	pg.bot_level = level
	pg.use_settings = false
	sm = pg.get_node("Match") as DominationMatch
	sm.feel_enabled = false
	sm.countdown_s = countdown
	sm.supplies = supplies
	over_results = {}
	over_count = 0
	events.clear()
	sm.match_over.connect(func(_w: Doll, r: Dictionary) -> void:
		over_results = r
		over_count += 1)
	sm.zone_event.connect(func(z: int, what: String, t: int) -> void:
		events.append({"t": sm.fight_time, "zone": z, "what": what, "team": t}))
	add_child(pg)
	await _until(func() -> bool: return sm.play_state == "play" and sm.dolls().size() == 6, 8.0)


func _unload() -> void:
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


func _wait(s: float) -> void:
	for i in int(round(s / TICK)):
		await get_tree().physics_frame


func _doll(index: int) -> Doll:
	for d in sm.dolls():
		if is_instance_valid(d) and (d as Doll).player_index == index:
			return d
	return null


func _brains_off() -> void:
	for d in sm.dolls():
		var b := (d as Node).get_node_or_null("SquadBrain")
		if b != null:
			b.set_physics_process(false)
		(d as Doll).input_vec = Vector2.ZERO
		var g := SquadMatch.gun_of(d)
		if g != null:
			g.trigger = false


## Перенести куклу: центр масс — в точку to (z = 0), скорости — ноль.
func _put(index: int, to: Vector3) -> void:
	var d := _doll(index)
	if d == null:
		return
	var shift := to - d.centre_of_mass()
	shift.z = 0.0
	for p in d.parts.values():
		var b := p as RigidBody3D
		if b == null or not is_instance_valid(b):
			continue
		b.global_position += shift
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO


## Точка внутри зоны i для бойца: низ зоны (лежит на полу / настиле), со сдвигом по x.
func _spot(i: int, dx := 0.0) -> Vector3:
	var c := sm.zone_centre(i)
	match i:
		B:
			return Vector3(c.x + dx, 7.6, 0.0)   # на настиле башни (верх 6.65)
	return Vector3(c.x + dx, 1.3, 0.0)           # на полу (верх 0.4), под плитой ±16 (низ 4.4)


## Подальше от зон: у своей базы (база ±28, настил 2.65).
func _home(index: int) -> Vector3:
	var x := -27.0 if index % 2 == 0 else 27.0
	return Vector3(x + 0.8 * float(index / 2) * (1.0 if index % 2 == 0 else -1.0), 4.0, 0.0)


func _all_home() -> void:
	for i in 6:
		_put(i, _home(i))


## Секунды до cond (шаг — физический тик), не дольше max_s; −1 — не дождались.
func _time_until(cond: Callable, max_s: float) -> float:
	var t0 := sm.fight_time
	for i in int(max_s / TICK):
		if cond.call():
			return sm.fight_time - t0
		await get_tree().physics_frame
	return sm.fight_time - t0 if cond.call() else -1.0


func _zone(i: int) -> Dictionary:
	return sm.zones[i]


# ------------------------------------------------------------------ rules

func _rules() -> void:
	print("--- rules")
	await _load(false)
	_brains_off()
	sm.time_limit_s = 3600.0
	sm.hard_timeout_s = 3600.0
	_check("rules_loaded", sm.play_state == "play" and sm.dolls().size() == 6, "состояние %s, бойцов %d" % [sm.play_state, sm.dolls().size()])
	_check("rules_mode", sm.mode == "dom" and not sm.frags_score() and not sm.is_ctf() and sm.flags.is_empty(),
		"режим %s, флагов %d" % [sm.mode, sm.flags.size()])
	_check("rules_numbers", sm.score_to_win == Tuning.DOM_SCORE_TO_WIN and is_equal_approx(sm.time_limit_s, 3600.0)
		and Tuning.DOM_ZONES.size() == 3, "до %d, зон %d" % [sm.score_to_win, Tuning.DOM_ZONES.size()])
	var nodes := get_tree().get_nodes_in_group(DominationZone.GROUP)
	var at_ok := nodes.size() == 3
	for n in nodes:
		var zn := n as DominationZone
		if zn.global_position.distance_to(sm.zone_centre(zn.index)) > 0.01:
			at_ok = false
	_check("rules_zone_nodes", at_ok, "узлов %d" % nodes.size())
	var neutral := true
	for i in 3:
		if sm.zone_owner(i) != -1 or sm.zone_progress(i) != 0.0:
			neutral = false
	_check("rules_start_neutral", neutral and sm.score == [0, 0], "зоны %s, счёт %s" % [str(sm.zones), str(sm.score)])
	_all_home()
	await _wait(0.6)
	var empty := true
	for i in 3:
		if sm.count_in(i) != [0, 0]:
			empty = false
	_check("rules_presence_empty", empty, "у баз — ни в одной зоне")

	# Один синий в A: захват за DOM_CAPTURE_S, событие, опыт, «захваты».
	var xp0 := float(sm.loadout(0)["xp"])
	_put(0, _spot(A))
	await get_tree().physics_frame
	_check("rules_presence_one", sm.count_in(A) == [1, 0], "в A: %s" % str(sm.count_in(A)))
	var t_solo := await _time_until(func() -> bool: return sm.zone_owner(A) == 0, Tuning.DOM_CAPTURE_S + 3.0)
	_check("rules_capture_solo", absf(t_solo - Tuning.DOM_CAPTURE_S) <= 0.15, "%.2f с (DOM_CAPTURE_S %.1f)" % [t_solo, Tuning.DOM_CAPTURE_S])
	var ev_ok := not events.is_empty() and int(events[-1]["zone"]) == A and String(events[-1]["what"]) == "captured" and int(events[-1]["team"]) == 0
	_check("rules_capture_event", ev_ok, str(events))
	_check("rules_capture_xp", float(sm.loadout(0)["xp"]) - xp0 >= Tuning.DOM_XP_CAPTURE - 0.01
		and int((sm.tally.get(0, {}) as Dictionary).get("captures", 0)) == 1,
		"опыт +%.0f, захватов %s" % [float(sm.loadout(0)["xp"]) - xp0, str((sm.tally.get(0, {}) as Dictionary).get("captures", 0))])

	# Очко в секунду за зону.
	var p0 := float(sm.points[0])
	await _wait(3.0)
	var dp := float(sm.points[0]) - p0
	_check("rules_points_one_zone", absf(dp - 3.0 * Tuning.DOM_POINTS_PER_S) <= 0.05 and sm.score[0] == int(floor(float(sm.points[0]) + 1e-6))
		and float(sm.points[1]) == 0.0, "за 3 с +%.2f, счёт %s" % [dp, str(sm.score)])

	# Трое синих в C: потолок скорости DOM_CAPTURE_MAX.
	_put(0, _spot(C, -1.2))
	_put(2, _spot(C, 0.0))
	_put(4, _spot(C, 1.2))
	await get_tree().physics_frame
	_check("rules_presence_three", sm.count_in(C) == [3, 0], "в C: %s" % str(sm.count_in(C)))
	var mult := minf(1.0 + Tuning.DOM_CAPTURE_EXTRA * 2.0, Tuning.DOM_CAPTURE_MAX)
	var t_trio := await _time_until(func() -> bool: return sm.zone_owner(C) == 0, Tuning.DOM_CAPTURE_S + 3.0)
	_check("rules_capture_trio", absf(t_trio - Tuning.DOM_CAPTURE_S / mult) <= 0.15, "%.2f с (ожидание %.2f, ×%.1f)" % [t_trio, Tuning.DOM_CAPTURE_S / mult, mult])
	_check("rules_capture_trio_tally", int((sm.tally.get(2, {}) as Dictionary).get("captures", 0)) == 1
		and int((sm.tally.get(4, {}) as Dictionary).get("captures", 0)) == 1, "захваты P2/P4 за C")
	p0 = float(sm.points[0])
	await _wait(2.0)
	dp = float(sm.points[0]) - p0
	_check("rules_points_two_zones", absf(dp - 4.0 * Tuning.DOM_POINTS_PER_S) <= 0.05, "2 зоны, за 2 с +%.2f" % dp)

	# B: синий начал — вышел — полоска стекает за DOM_IDLE_S.
	_put(2, _home(2))
	_put(4, _home(4))
	_put(0, _spot(B))
	await _wait(2.0)
	var pb := sm.zone_progress(B)
	_check("rules_partial", sm.zone_owner(B) == -1 and int(_zone(B)["prog_team"]) == 0 and absf(pb - 2.0 / Tuning.DOM_CAPTURE_S) <= 0.03,
		"B: %.3f у %d" % [pb, int(_zone(B)["prog_team"])])
	_put(0, _home(0))
	await _wait(1.0)
	var pd := sm.zone_progress(B)
	_check("rules_neutral_decay", absf((pb - pd) - 1.0 / Tuning.DOM_IDLE_S) <= 0.03, "за 1 с пусто −%.3f (1/%.0f)" % [pb - pd, Tuning.DOM_IDLE_S])

	# Спорная: синий и красный в B — прогресс стоит.
	_put(0, _spot(B, -1.0))
	_put(1, _spot(B, 1.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var pc := sm.zone_progress(B)
	await _wait(2.0)
	_check("rules_contested", bool(_zone(B)["contested"]) and absf(sm.zone_progress(B) - pc) < 0.001 and sm.zone_owner(B) == -1,
		"B спорная %s, %.3f → %.3f" % [str(_zone(B)["contested"]), pc, sm.zone_progress(B)])

	# Синий ушёл, красный один: синяя полоска стекает, потом захват красными.
	_put(0, _home(0))
	var left := sm.zone_progress(B)
	var t_flip := await _time_until(func() -> bool: return sm.zone_owner(B) == 1, 2.0 * Tuning.DOM_CAPTURE_S + 3.0)
	var want_flip := (left + 1.0) * Tuning.DOM_CAPTURE_S
	_check("rules_drain_then_capture", absf(t_flip - want_flip) <= 0.25, "%.2f с (ожидание %.2f: стечь %.2f + захват)" % [t_flip, want_flip, left])

	# Чужая своя: красный в A (синяя) — нейтрализация за DOM_CAPTURE_S, потом захват ещё за DOM_CAPTURE_S.
	_put(1, _spot(A))
	var n0 := events.size()
	var t_neu := await _time_until(func() -> bool: return sm.zone_owner(A) == -1, Tuning.DOM_CAPTURE_S + 3.0)
	_check("rules_neutralize", absf(t_neu - Tuning.DOM_CAPTURE_S) <= 0.15 and events.size() > n0 and String(events[n0]["what"]) == "neutralized"
		and int(events[n0]["team"]) == 1, "%.2f с, событие %s" % [t_neu, str(events.slice(n0))])
	var t_cap := await _time_until(func() -> bool: return sm.zone_owner(A) == 1, Tuning.DOM_CAPTURE_S + 3.0)
	_check("rules_capture_after_neutral", absf(t_cap - Tuning.DOM_CAPTURE_S) <= 0.15, "%.2f с" % t_cap)

	# Своя пустая доливается: синий в A на 3 с (сбил половину) — ушли все — запас растёт 1/DOM_IDLE_S.
	_put(1, _home(1))
	_put(0, _spot(A))
	await _wait(3.0)
	_put(0, _home(0))
	await get_tree().physics_frame
	var pr := sm.zone_progress(A)
	await _wait(2.0)
	var pr2 := sm.zone_progress(A)
	_check("rules_owner_refill", sm.zone_owner(A) == 1 and pr < 0.6 and absf((pr2 - pr) - 2.0 / Tuning.DOM_IDLE_S) <= 0.03,
		"A красная, запас %.3f → %.3f" % [pr, pr2])

	# Выбывание очков не даёт.
	var s0: Array = sm.score.duplicate()
	var p_before: Array = sm.points.duplicate()
	var v := _doll(3)
	v.knock_out()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var frag_pts := int(sm.score[0]) - int(s0[0])
	var by_points := int(floor(float(sm.points[0]) + 1e-6)) - int(floor(float(p_before[0]) + 1e-6))
	_check("rules_no_frag_points", frag_pts == by_points and sm.frags.size() >= 1, "счёт %s → %s, от зон %d" % [str(s0), str(sm.score), by_points])
	await _wait(sm.respawn_s + 1.0)
	_brains_off()

	# Конец по очкам: у синих C — до цели полсекунды; счёт не выше цели.
	sm.points[0] = float(sm.score_to_win) - 0.5
	var won := await _until(func() -> bool: return over_count > 0, 3.0)
	_check("rules_finish_score", won and int(over_results.get("winner_team", -1)) == 0 and String(over_results.get("reason", "")) == "score"
		and int((over_results.get("score", [0, 0]) as Array)[0]) == sm.score_to_win,
		"итоги: %s, счёт %s" % [str(over_results.get("reason", "")), str(over_results.get("score", []))])
	_check("rules_results", (over_results.get("zones", []) as Array).size() == 3 and (over_results.get("zone_log", []) as Array).size() >= 4
		and String(over_results.get("mode", "")) == "dom", "журнал зон %d" % (over_results.get("zone_log", []) as Array).size())

	# Заново — сброс; узлы зон не дублируются.
	sm.begin()
	await _until(func() -> bool: return sm.play_state == "play", 8.0)
	_brains_off()
	sm.time_limit_s = 3600.0
	var reset_ok := sm.score == [0, 0] and float(sm.points[0]) == 0.0 and float(sm.points[1]) == 0.0
	for i in 3:
		if sm.zone_owner(i) != -1 or sm.zone_progress(i) != 0.0:
			reset_ok = false
	_check("rules_restart", reset_ok and get_tree().get_nodes_in_group(DominationZone.GROUP).size() == 3,
		"счёт %s, узлов %d" % [str(sm.score), get_tree().get_nodes_in_group(DominationZone.GROUP).size()])

	# План ботов: всё нейтрально — каждому красному своя зона.
	var plan := sm.plan_team(1)
	var zs := {}
	for k in plan:
		zs[int(plan[k])] = true
	_check("rules_bot_plan_spread", plan.size() == 3 and zs.size() == 3, "план красных %s" % str(plan))
	var plan0 := sm.plan_team(0)
	_check("rules_bot_plan_human", plan0.size() == 2 and not plan0.has(0), "план синих (P1 — человек) %s" % str(plan0))

	# Время вышло — побеждает ведущая.
	_all_home()
	sm.points = [10.0, 20.0]
	sm.score = [10, 20]
	sm.time_limit_s = sm.fight_time + 0.5
	over_count = 0
	var timed := await _until(func() -> bool: return over_count > 0, 3.0)
	_check("rules_timeout", timed and String(over_results.get("reason", "")) == "timeout" and int(over_results.get("winner_team", -1)) == 1,
		"итоги: %s, победа %s" % [str(over_results.get("reason", "")), str(over_results.get("winner_team", -1))])

	# Настройки: «dom» — своя цель, время и сцена.
	SquadSettings.reset()
	SquadSettings.mode = "dom"
	var st_ok := SquadSettings.goal() == Tuning.DOM_SCORE_TO_WIN and SquadSettings.minutes() == int(Tuning.DOM_TIME_S / 60.0) \
		and SquadPlayground._scene_for() == SquadPlayground.SCENE_DOM_DAY
	SquadSettings.night = true
	st_ok = st_ok and SquadPlayground._scene_for() == SquadPlayground.SCENE_DOM_NIGHT
	SquadSettings.mode = "dm"
	st_ok = st_ok and SquadPlayground._scene_for() == SquadPlayground.SCENE_NIGHT and SquadSettings.minutes() == SquadSettings.time_min
	SquadSettings.reset()
	_check("rules_settings", st_ok and SquadSettings.MODES.has("dom"), "цель/время/сцена «dom»")
	var su := SquadSetup.new()
	SquadSettings.mode = "dom"
	var vals: Array = su._values("goal")
	var tvals: Array = su._values("time")
	su._set_value("goal", 150)
	su._set_value("time", 8)
	var set_ok := vals == Tuning.DOM_SCORE_CHOICES and tvals == Tuning.DOM_TIME_CHOICES and SquadSettings.dom_score_to_win == 150 \
		and SquadSettings.dom_time_min == 8 and SquadSettings.score_to_win == Tuning.SQUAD_SCORE_TO_WIN and SquadSettings.time_min == 20
	su.free()
	SquadSettings.reset()
	_check("rules_setup_values", set_ok, "варианты цели %s, времени %s" % [str(vals), str(tvals)])
	await _unload()

	# Сцена из настроек: use_settings — режим «dom» при любом SquadSettings.mode, цель и время из настроек.
	SquadSettings.reset()
	SquadSettings.mode = "dm"
	SquadSettings.dom_score_to_win = 150
	SquadSettings.dom_time_min = 4
	var p2 := (load(SCENE) as PackedScene).instantiate() as DominationPlayground
	p2.p1_bot = true
	add_child(p2)
	await get_tree().physics_frame
	var m2 := p2.get_node("Match") as DominationMatch
	_check("rules_settings_scene", m2.mode == "dom" and m2.score_to_win == 150 and is_equal_approx(m2.time_limit_s, 240.0)
		and (p2.get_node("Dolls").get_child(1).get_node_or_null("SquadBrain") is DominationBrain),
		"режим %s, до %d, %.0f с" % [m2.mode, m2.score_to_win, m2.time_limit_s])
	remove_child(p2)
	p2.queue_free()
	SquadSettings.reset()
	await get_tree().physics_frame


# ------------------------------------------------------------------ bots

func _bots(max_s: float, level: int, trace: bool, score_to_win: int) -> void:
	print("--- bots (level %d, до %d)" % [level, score_to_win])
	await _load(true, level, 3.0, true)
	sm.score_to_win = score_to_win
	var acc := {"friendly": 0.0, "all": 0.0, "shots": 0}
	sm.hit.connect(func(vv: Doll, a: Node, dmg: float, _k: String, _p: Vector3) -> void:
		acc["all"] = float(acc["all"]) + dmg
		if is_instance_valid(a) and a is Doll and SquadMatch.team_of(a) == SquadMatch.team_of(vv) and a != vv:
			acc["friendly"] = float(acc["friendly"]) + dmg)
	var last_pos: Dictionary = {}
	var stuck_max := 0.0
	var stuck_who := ""
	var out_of_bounds := 0
	var in_zone_s := [0.0, 0.0]
	var b: AABB = pg.arena.call("bounds")
	var t0 := Time.get_ticks_usec()
	var trace_t := 0.0
	var lead_changes := 0
	var leader := -1
	while over_count == 0 and sm.fight_time < max_s:
		await get_tree().physics_frame
		var ld := -1 if sm.score[0] == sm.score[1] else (0 if sm.score[0] > sm.score[1] else 1)
		if ld >= 0 and ld != leader:
			if leader >= 0:
				lead_changes += 1
			leader = ld
		for d in sm.dolls():
			var dd := d as Doll
			if not dd.alive:
				last_pos.erase(dd.player_index)
				continue
			var c := dd.centre_of_mass()
			if c.x < b.position.x - 0.5 or c.x > b.end.x + 0.5 or c.y < b.position.y - 0.5 or c.y > b.end.y + 0.5:
				out_of_bounds += 1
			var inside := false
			for i in 3:
				var zc := sm.zone_centre(i)
				if Vector2(c.x - zc.x, c.y - zc.y).length() <= Tuning.DOM_ZONE_R:
					inside = true
			if inside:
				in_zone_s[dd.player_index % 2] = float(in_zone_s[dd.player_index % 2]) + TICK
				last_pos.erase(dd.player_index)   # стоять в зоне — работа, не застревание
				continue
			var lp: Array = last_pos.get(dd.player_index, [])
			if lp.is_empty() or (lp[0] as Vector3).distance_to(c) > 1.5:
				last_pos[dd.player_index] = [c, sm.fight_time]
			elif sm.fight_time - float(lp[1]) > stuck_max:
				stuck_max = sm.fight_time - float(lp[1])
				var br := dd.get_node_or_null("SquadBrain") as SquadBrain
				stuck_who = "P%d %s в (%.1f, %.1f), состояние %s" % [dd.player_index, String(sm.loadout(dd.player_index)["class"]), c.x, c.y,
					br.state if br != null else "-"]
		if trace and sm.fight_time - trace_t >= 10.0:
			trace_t = sm.fight_time
			var row := []
			for i in 3:
				var z: Dictionary = sm.zones[i]
				row.append("%s:%d/%.2f%s%s" % [sm.zone_name(i), int(z["owner"]), float(z["prog"]), str(z["n"]), "!" if bool(z["contested"]) else ""])
			var bots := []
			for d in sm.dolls():
				var br := (d as Node).get_node_or_null("SquadBrain") as DominationBrain
				bots.append("%d:%s>%d(%.0f,%.0f)%s" % [(d as Doll).player_index, br.state if br != null else "-", br.zone if br != null else -1,
					(d as Doll).centre_of_mass().x, (d as Doll).centre_of_mass().y, "" if (d as Doll).alive else "†"])
			print("  t=%5.1f score=%s  %s  %s" % [sm.fight_time, str(sm.score), " ".join(row), " ".join(bots)])
	var wall_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var caps := [0, 0]
	var neus := [0, 0]
	for e in sm.zone_log:
		if String(e["what"]) == "captured":
			caps[int(e["team"])] += 1
		else:
			neus[int(e["team"])] += 1
	var kills := [0, 0]
	for pi in sm.tally:
		kills[int(pi) % 2] += int(sm.tally[pi]["kills"])
	var shots := 0
	for d in sm.dolls():
		var g := SquadMatch.gun_of(d)
		if g != null:
			shots += g.shots
	info["bots"] = {"fight_s": snappedf(sm.fight_time, 0.1), "wall_ms": int(wall_ms), "score": sm.score.duplicate(),
		"points": [snappedf(float(sm.points[0]), 0.1), snappedf(float(sm.points[1]), 0.1)], "reason": String(over_results.get("reason", "")),
		"winner_team": int(over_results.get("winner_team", -1)), "captures": caps, "neutralized": neus, "kills": kills,
		"held_s": [snappedf(float(sm.held_s[0]), 0.1), snappedf(float(sm.held_s[1]), 0.1)],
		"in_zone_s": [snappedf(float(in_zone_s[0]), 0.1), snappedf(float(in_zone_s[1]), 0.1)], "lead_changes": lead_changes,
		"stuck_max_s": snappedf(stuck_max, 0.1), "stuck_who": stuck_who, "damage": int(acc["all"]), "zone_log": sm.zone_log.size()}
	_check("bots_finished", over_count == 1 and String(over_results.get("reason", "")) in ["score", "timeout"],
		"конец: %s за %.0f с, счёт %s" % [String(over_results.get("reason", "")), sm.fight_time, str(sm.score)])
	_check("bots_winner", int(over_results.get("winner_team", -1)) in [0, 1], "победа %d, очки %s" % [int(over_results.get("winner_team", -1)), str(sm.points)])
	_check("bots_both_capture", int(caps[0]) >= 1 and int(caps[1]) >= 1, "захваты синих/красных %s" % str(caps))
	_check("bots_zones_change_hands", int(neus[0]) + int(neus[1]) >= 1, "нейтрализаций %s" % str(neus))
	# Бой есть: урон заметный и либо стрельба, либо фраги (громилы и рукопашные бьют без выстрелов — на level 3 их больше).
	_check("bots_fight", float(acc["all"]) > 200.0 and (shots >= 20 or int(kills[0]) + int(kills[1]) >= 2),
		"выстрелов %d, урона %d, фрагов %s" % [shots, int(acc["all"]), str(kills)])
	_check("bots_no_friendly_damage", float(acc["friendly"]) == 0.0, "по своим %.1f" % float(acc["friendly"]))
	_check("bots_in_bounds", out_of_bounds == 0, "тиков вне границ %d" % out_of_bounds)
	_check("bots_not_stuck", stuck_max < 25.0, "дольше всех на месте вне зоны: %.1f с (%s)" % [stuck_max, stuck_who])
	_check("bots_hold_zones", float(in_zone_s[0]) > 20.0 and float(in_zone_s[1]) > 20.0, "боец-секунд в зонах %s" % str(in_zone_s))
