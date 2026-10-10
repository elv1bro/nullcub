## Проба «Перетягивания каната 2 на 2» (docs/plan-demo/TUG.md) на настоящей площадке scenes/playground_tug.tscn (спорт-зал, канат TugRope,
## четыре куклы с ArmAssist, TugMatch, TugBrain, TugHud).
##   rules (P1 — бот, мозги выключаются там, где проба ведёт сама): четыре куклы, по две в командах (синие — чётный player_index слева,
##     красные — справа), канат 10 м ≈ 40 кг из звеньев, метка посередине; канат не рвётся 10 с под рывком двух кукол (по одной на конец,
##     очки выключены); рука хватает звено своей половины, чужой — нет (и can_grab, и клавиша захвата у звена); держащий и тянущий к
##     своей стене — тяга × TUG_PULL_MULT; метка за чертой меньше TUG_HOLD_S — очка нет, TUG_HOLD_S — очко, после паузы канат и куклы
##     заново; KO → возврат у своей стены через TUG_RESPAWN_S; до TUG_SCORE_TO_WIN → итоги (табличка HUD); R — всё заново;
##   bots: матч 2×2 ботов уровня level доигрывается (≤ 5 мин игры, сам матч — TUG_TIME_S), время до очка — в info; никто не застрял
##     (без каната в руке на месте < STUCK_LIMIT_S), все в границах зала; сильные против слабых: STRONG_N коротких матчей до 1 очка
##     (ур. 3 против ур. 1, стороны чередуются) — сильные берут ≥ STRONG_MIN.
## Обе секции: ошибок скриптов (errors_script) и движка (errors_engine) — 0; ресурсы, не загрузившиеся с диска (нет .ogg в git), —
## отдельно в info.errors_assets (не режим, пробу не валят).
## Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/tug_probe.tscn -- "only=rules|bots|strong|rules+bots+strong,level=2,trace=1,out=<json>"
## → JSON между === TUG PROBE === и === OK / FAIL ===, exit 0/1. Без only — все три секции.
extends Node

const SCENE := "res://scenes/playground_tug.tscn"
const TICK := 1.0 / 60.0
const STUCK_M := 1.0
const STUCK_LIMIT_S := 20.0
const BOTS_MAX_S := 300.0
const STRONG_N := 5
const STRONG_MIN := 4
const STRONG_MAX_S := 150.0
const PHYS_WARN_MS := 6.0
const PACE_S := Vector2(20.0, 60.0)   # ур. 2 против ур. 2: медиана розыгрыша до очка (игровые с)
## Канат цел: зазор на стыке звеньев больше GAP_MAX_M не держится дольше GAP_HOLD_S подряд (сварка кисти со звеном подтягивает звено
## скачком — короткий всплеск, суставы цепи его выбирают) и ни разу не больше GAP_TEAR_M.
const GAP_MAX_M := 0.2
const GAP_HOLD_S := 0.3
const GAP_TEAR_M := 0.5

class ScriptErrors extends Logger:
	var count := 0
	var first := ""
	var engine := 0
	var engine_first := ""
	var assets := 0
	var assets_first := ""
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
var pg: TugPlayground
var tm: TugMatch
var over_results: Dictionary = {}
var over_count := 0
var errs := ScriptErrors.new()


func _check(id: String, cond: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": cond, "detail": str(detail)})
	if not cond:
		ok = false
	print("  %-30s %s  %s" % [id, "ok  " if cond else "FAIL", str(detail)])


func _args() -> Dictionary:
	var out := {"only": "", "level": "2", "trace": "0", "out": "", "n": str(STRONG_N)}
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
	print("=== TUG PROBE ===")
	var a := _args()
	if _want(a, "rules"):
		await _rules()
	if _want(a, "bots"):
		await _bots(int(a["level"]), String(a["trace"]) == "1")
	if _want(a, "strong"):
		await _strong(int(a["n"]), String(a["trace"]) == "1")
	await _unload()
	_check("errors_script", errs.count == 0, "ошибок скриптов %d; первая: %s" % [errs.count, errs.first])
	_check("errors_engine", errs.engine == 0, "ошибок движка %d; первая: %s" % [errs.engine, errs.engine_first])
	info["errors_assets"] = {"count": errs.assets, "first": errs.assets_first}
	if errs.assets > 0:
		print("  (не загрузились ресурсы с диска: %d, первая: %s — не режим, см. info.errors_assets)" % [errs.assets, errs.assets_first])
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

func _load(level := 2, countdown := 0.3, score_to_win := Tuning.TUG_SCORE_TO_WIN) -> void:
	await _unload()
	Engine.time_scale = 1.0
	pg = (load(SCENE) as PackedScene).instantiate() as TugPlayground
	pg.p1_bot = true
	pg.p2_human = false
	pg.bot_level = level
	tm = pg.get_node("Match") as TugMatch
	tm.feel_enabled = false
	tm.countdown_s = countdown
	tm.score_to_win = score_to_win
	over_results = {}
	over_count = 0
	tm.match_over.connect(func(_w: Doll, r: Dictionary) -> void:
		over_results = r
		over_count += 1)
	add_child(pg)
	await _until(func() -> bool: return tm.play_state == "play" and tm.dolls().size() == Tuning.TUG_TEAM * 2, 10.0)


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
	for d in tm.dolls():
		if is_instance_valid(d) and (d as Doll).player_index == index:
			return d
	return null


func _brain(d: Doll) -> TugBrain:
	return d.get_node_or_null(TugPlayground.BRAIN) as TugBrain if d != null else null


func _brains_off(except: Array = []) -> void:
	for d in tm.dolls():
		if except.has((d as Doll).player_index):
			continue
		var b := _brain(d)
		if b != null:
			b.let_go()
			b.set_physics_process(false)
		(d as Doll).input_vec = Vector2.ZERO


## Поставить куклу торсом в точку p (все детали — сдвигом, скорости — 0).
func _place(d: Doll, p: Vector2) -> void:
	var t := d.torso().global_position
	var off := Vector3(p.x - t.x, p.y - t.y, 0.0)
	for b in d.parts.values():
		var rb := b as RigidBody3D
		rb.global_position += off
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		rb.reset_physics_interpolation()


## Все куклы, кроме except, — к своим стенам (на пол, у x = ±9.5).
func _park(except: Array = []) -> void:
	for d in tm.dolls():
		var dd := d as Doll
		if except.has(dd.player_index) or not dd.alive:
			continue
		_place(dd, Vector2(TugMatch.home_dir(TugMatch.team_of(dd)) * (9.0 + 0.8 * float(dd.player_index / 2)), 0.9))


## Рука куклы d тянется к звену link (кукла над ним), потом жмёт захват; true — держит звено той же половины (link или соседа).
func _try_grab(d: Doll, link: RigidBody3D) -> bool:
	var arm := TugPlayground.arm_of(d)
	var lp := link.global_position
	_place(d, Vector2(lp.x, lp.y + 0.55))
	arm.set_target_override(lp)
	await _wait(0.5)
	arm.press_grab()
	await _wait(0.15)
	arm.clear_target_override()
	return arm.is_holding() and tm.rope.side_of(arm.held) == tm.rope.side_of(link)


# ------------------------------------------------------------------ правила

func _rules() -> void:
	print("--- rules")
	await _load(2, 0.3)
	_brains_off()
	_park()
	await _wait(0.3)
	var rope := tm.rope
	var n := tm.dolls().size()
	var groups_ok := true
	for d in tm.dolls():
		var dd := d as Doll
		var t := TugMatch.team_of(dd)
		groups_ok = groups_ok and dd.team == TugMatch.TEAM_PREFIX + str(t) and TugPlayground.arm_of(dd) != null \
			and signf(Tuning.TUG_SPAWN[dd.player_index].x) == TugMatch.home_dir(t)
	_check("four_dolls_two_teams", n == 4 and tm.team_dolls(0).size() == 2 and tm.team_dolls(1).size() == 2 and groups_ok and tm.play_state == "play",
		"кукол %d, синих %d, красных %d, команды / руки / стороны: %s" % [n, tm.team_dolls(0).size(), tm.team_dolls(1).size(), str(groups_ok)])
	var mass := 0.0
	for b in rope.links:
		mass += (b as RigidBody3D).mass
	var span: float = (rope.links[-1] as Node3D).global_position.x - (rope.links[0] as Node3D).global_position.x + rope.seg
	_check("rope_built", rope.links.size() == Tuning.TUG_ROPE_LINKS and absf(mass - Tuning.TUG_ROPE_MASS_KG) < 0.5 and absf(span - Tuning.TUG_ROPE_M) < 0.3
		and absf(rope.mark_x()) < 0.1 and rope.lowest_y() > 0.0 and rope.highest_y() < 0.3 and rope.side_links(0).size() == rope.links.size() / 2,
		"звеньев %d, масса %.1f кг, длина %.2f м, метка x %.2f, y %.2f…%.2f" % [rope.links.size(), mass, span, rope.mark_x(), rope.lowest_y(), rope.highest_y()])
	# --- хват: своя половина — да, чужая — нет
	var p1 := _doll(0)
	var arm1 := TugPlayground.arm_of(p1)
	var own: RigidBody3D = rope.links[rope.links.size() / 2 - 3]
	var foreign: RigidBody3D = rope.links[rope.links.size() / 2 + 3]
	var can_own := arm1.can_grab(own)
	var can_foreign := arm1.can_grab(foreign)
	var got_foreign := await _try_grab(p1, foreign)
	var holding_foreign := arm1.is_holding()
	_check("grab_foreign_half_refused", not can_foreign and not got_foreign and not holding_foreign,
		"can_grab(чужое звено) %s, захват у чужого звена: держит %s" % [str(can_foreign), str(holding_foreign)])
	var got_own := await _try_grab(p1, own)
	await _wait(0.3)
	_check("grab_own_half", can_own and got_own and tm.is_holding(p1) and rope.side_of(tm.held_link(p1)) == 0,
		"can_grab(своё) %s, захват: %s, матч видит хват: %s, сварено: %s" % [str(can_own), str(got_own), str(tm.is_holding(p1)), str(arm1.is_welded())])
	# --- тяга × TUG_PULL_MULT, когда держит и тянет к своей стене
	p1.input_vec = Vector2(-1.0, 0.0)
	await _wait(0.1)
	var mult_away := p1.thrust_mult
	p1.input_vec = Vector2(1.0, 0.0)
	await _wait(0.1)
	var mult_in := p1.thrust_mult
	p1.input_vec = Vector2.ZERO
	arm1.release("drop")
	await _wait(0.1)
	_check("pull_mult", is_equal_approx(mult_away, Tuning.TUG_PULL_MULT) and is_equal_approx(mult_in, 1.0) and is_equal_approx(p1.thrust_mult, 1.0),
		"к своей стене ×%.2f, к центру ×%.2f, отпустил ×%.2f" % [mult_away, mult_in, p1.thrust_mult])
	# --- канат не рвётся 10 с под рывком двух кукол (боты ур. 3 на обоих концах, очки выключены)
	tm.scoring = false
	_park()
	rope.reset()
	await _wait(0.2)
	for i in [0, 1]:
		var b := _brain(_doll(i))
		b.level = 3
		b._brain_ready()
		b.set_physics_process(true)
		_place(_doll(i), Vector2(TugMatch.home_dir(i) * 4.0, 0.8))
	var gap_max := 0.0
	var gap_at := 0.0
	var gap_run := 0.0
	var gap_run_max := 0.0
	var both_t := 0.0
	var mark_min := INF
	var mark_max := -INF
	for k in int(10.0 / TICK):
		await get_tree().physics_frame
		var gnow := rope.max_gap()
		if gnow > gap_max:
			gap_at = k * TICK
		gap_max = maxf(gap_max, gnow)
		gap_run = gap_run + TICK if gnow > GAP_MAX_M else 0.0
		gap_run_max = maxf(gap_run_max, gap_run)
		if k % 30 == 0 and OS.get_cmdline_user_args().has("gaps"):
			print("    t=%.1f gap %.3f mark %.2f" % [k * TICK, gnow, rope.mark_x()])
		if tm.is_holding(_doll(0)) and tm.is_holding(_doll(1)):
			both_t += TICK
		mark_min = minf(mark_min, rope.mark_x())
		mark_max = maxf(mark_max, rope.mark_x())
	info["rope_jerk"] = {"gap_max_m": snappedf(gap_max, 0.001), "gap_over_s": snappedf(gap_run_max, 0.01), "gap_max_at_s": snappedf(gap_at, 0.01), "both_hold_s": snappedf(both_t, 0.1), "mark": [snappedf(mark_min, 0.01), snappedf(mark_max, 0.01)]}
	_check("rope_holds_10s", gap_max < GAP_TEAR_M and gap_run_max < GAP_HOLD_S and both_t > 5.0 and rope.links.size() == Tuning.TUG_ROPE_LINKS and rope.lowest_y() > -0.1,
		"наибольший зазор звеньев %.3f м (разрыв — %.2f), больше %.2f м подряд %.2f с (предел %.1f), оба держат %.1f из 10 с, метка %.2f…%.2f" % [
			gap_max, GAP_TEAR_M, GAP_MAX_M, gap_run_max, GAP_HOLD_S, both_t, mark_min, mark_max])
	tm.scoring = true
	_brains_off()
	_park()
	rope.reset()
	await _wait(0.3)
	# --- метка за чертой: меньше TUG_HOLD_S — нет очка, TUG_HOLD_S — очко, потом расстановка
	rope.shift(-(Tuning.TUG_LINE_M + 0.4))
	await _wait(Tuning.TUG_HOLD_S * 0.6)
	var early: Array = tm.score.duplicate()
	var got_point := await _until(func() -> bool: return int(tm.score[0]) == 1, Tuning.TUG_HOLD_S)
	_check("mark_over_line_point", early == [0, 0] and got_point and tm.score == [1, 0] and tm.play_state == "point" and not tm.points.is_empty()
		and float(tm.points[0]["mark_x"]) <= -Tuning.TUG_LINE_M,
		"через %.1f с счёт %s; потом %s, метка %.2f, фаза %s" % [Tuning.TUG_HOLD_S * 0.6, str(early), str(tm.score), tm.mark_x(), tm.play_state])
	_park()
	var f0 := Engine.get_physics_frames()
	var replay := await _until(func() -> bool: return tm.play_state == "play", Tuning.TUG_POINT_PAUSE_S + Tuning.TUG_RESET_COUNTDOWN_S + 1.0)
	var replay_s := float(Engine.get_physics_frames() - f0) * TICK
	await _wait(0.05)
	var at_spawn := true
	for d in tm.dolls():
		var dd := d as Doll
		at_spawn = at_spawn and dd.alive and absf(dd.global_position.x - float(Tuning.TUG_SPAWN[dd.player_index].x)) < 1.5
	_check("point_resets", replay and absf(replay_s - Tuning.TUG_POINT_PAUSE_S - Tuning.TUG_RESET_COUNTDOWN_S) < 0.2 and absf(tm.mark_x()) < 0.15 and at_spawn and tm.score == [1, 0],
		"розыгрыш снова: %s через %.1f с, метка x %.2f, куклы на местах: %s" % [str(replay), replay_s, tm.mark_x(), str(at_spawn)])
	_brains_off()
	_park()
	# --- KO → возврат у своей стены через TUG_RESPAWN_S
	var p4 := _doll(3)
	var ko_t := tm.fight_time
	p4.knock_out()
	await _wait(Tuning.TUG_RESPAWN_S - 0.4)
	var still_out := not _doll(3).alive
	var back := await _until(func() -> bool:
		var d := _doll(3)
		return d != null and d.alive, 1.0)
	var dt := tm.fight_time - ko_t
	var np4 := _doll(3)
	_check("ko_respawn_3s", still_out and back and absf(dt - Tuning.TUG_RESPAWN_S) < 0.15 and np4.global_position.x > 6.0 and _brain(np4) != null
		and TugPlayground.arm_of(np4) != null and np4.team == "tug_1",
		"через %.1f с ещё выбит: %s; вернулся через %.2f с (ждём %.1f), x %.1f, мозг и рука: %s" % [Tuning.TUG_RESPAWN_S - 0.4, str(still_out), dt,
			Tuning.TUG_RESPAWN_S, np4.global_position.x, str(_brain(np4) != null and TugPlayground.arm_of(np4) != null)])
	_brains_off()
	_park()
	# --- до 3 → итоги
	for k in Tuning.TUG_SCORE_TO_WIN - 1:
		await _until(func() -> bool: return tm.play_state == "play", 6.0)
		_brains_off()
		_park()
		rope.reset()
		rope.shift(-(Tuning.TUG_LINE_M + 0.4))
		await _until(func() -> bool: return tm.play_state != "play", Tuning.TUG_HOLD_S + 0.5)
	var done := await _until(func() -> bool: return over_count > 0, Tuning.TUG_POINT_PAUSE_S + 1.0)
	var places: Array = over_results.get("places", [])
	_check("to_3_results", done and over_count == 1 and int(over_results.get("winner_team", -1)) == 0 and tm.phase == Match.Phase.OVER
		and tm.score == [Tuning.TUG_SCORE_TO_WIN, 0] and String(over_results.get("reason", "")) == "score" and places.size() == 4
		and TugMatch.team_of(places[0]) == 0,
		"итогов %d, победили %s, счёт %s, причина %s" % [over_count, str(over_results.get("winner_team", "?")), str(tm.score), str(over_results.get("reason", "?"))])
	await _wait(1.2)
	_check("hud_end_panel", pg.hud.end_panel.visible and pg.hud.end_title.text != "" and pg.hud.end_table.get_child_count() == 4 * 5,
		"табличка: «%s» · %s · клеток %d" % [pg.hud.end_title.text, pg.hud.end_sub.text, pg.hud.end_table.get_child_count()])
	# --- R: заново
	tm.restart()
	await _until(func() -> bool: return tm.play_state == "play", 6.0)
	await _wait(0.1)
	_check("restart_resets", tm.score == [0, 0] and tm.points.is_empty() and tm.alive_dolls().size() == 4 and not pg.hud.end_panel.visible
		and tm.phase == Match.Phase.FIGHT and absf(tm.mark_x()) < 0.15,
		"счёт %s, живых %d, фаза %d, метка %.2f" % [str(tm.score), tm.alive_dolls().size(), tm.phase, tm.mark_x()])


# ------------------------------------------------------------------ матчи ботов

## Один матч ботов до конца (или max_s игры): возвращает сводку. levels — уровень по команде [синие, красные] (−1 — общий).
func _run_match(levels: Array, max_s: float, trace: bool, acc: Dictionary) -> Dictionary:
	for d in tm.dolls():
		var b := _brain(d)
		var lv := int(levels[TugMatch.team_of(d)])
		if b != null and lv > 0:
			b.level = lv
			b._brain_ready()
	var t0: Dictionary = TugBrain.total.duplicate()
	var last_pos: Dictionary = {}
	var b: AABB = pg.arena.call("bounds")
	var trace_t := 0.0
	while over_count == 0 and tm.fight_time < max_s:
		await get_tree().physics_frame
		acc["frames"] = int(acc["frames"]) + 1
		var pm := float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		acc["phys_sum"] = float(acc["phys_sum"]) + pm
		acc["phys_max"] = maxf(float(acc["phys_max"]), pm)
		var gnow := tm.rope.max_gap()
		if gnow > float(acc["gap_max"]):
			var welds := []
			for d in tm.dolls():
				var ar := TugPlayground.arm_of(d)
				if ar != null and ar.held != null:
					welds.append("%s:%.2f%s" % [d.name, ar._time - ar._grab_t, "w" if ar.is_welded() else ""])
			acc["gap_at"] = "t %.2f, %s, розыгрыш %.2f с, метка %.2f, хваты %s" % [tm.fight_time, tm.play_state, tm.round_time, tm.mark_x(), str(welds)]
		acc["gap_max"] = maxf(float(acc["gap_max"]), gnow)
		acc["gap_run"] = float(acc["gap_run"]) + TICK if gnow > GAP_MAX_M else 0.0
		acc["gap_run_max"] = maxf(float(acc["gap_run_max"]), float(acc["gap_run"]))
		var playing := tm.play_state == "play"
		for d in tm.dolls():
			var dd := d as Doll
			# новые куклы после KO / расстановки — с тем же уровнем
			var br := _brain(dd)
			var lv := int(levels[TugMatch.team_of(dd)])
			if br != null and lv > 0 and br.level != lv:
				br.level = lv
				br._brain_ready()
			if not dd.alive or not playing or tm.is_holding(dd):
				last_pos.erase(dd.player_index)
				continue
			var c := dd.centre_of_mass()
			if c.x < b.position.x - 0.5 or c.x > b.end.x + 0.5 or c.y < b.position.y - 0.5 or c.y > b.end.y + 0.5:
				acc["oob"] = int(acc["oob"]) + 1
			var lp: Array = last_pos.get(dd.player_index, [])
			if lp.is_empty() or (lp[0] as Vector3).distance_to(c) > STUCK_M:
				last_pos[dd.player_index] = [c, tm.fight_time]
			elif tm.fight_time - float(lp[1]) > float(acc["stuck_max"]):
				acc["stuck_max"] = tm.fight_time - float(lp[1])
				acc["stuck_who"] = "%s в (%.1f, %.1f), %s" % [TugMatch.doll_name(dd), c.x, c.y, br.state if br != null else "-"]
		if trace and tm.fight_time - trace_t >= 5.0:
			trace_t = tm.fight_time
			var row := []
			for d in tm.dolls():
				var br := _brain(d)
				var cc := (d as Doll).centre_of_mass()
				row.append("%s:%s(%.1f,%.1f)%s%s" % [TugMatch.doll_name(d), br.state if br != null else "-", cc.x, cc.y,
					"H" if tm.is_holding(d) else "", "" if (d as Doll).alive else "†"])
			print("  t=%6.1f счёт %s метка %+.2f  %s" % [tm.fight_time, str(tm.score), tm.mark_x(), " ".join(row)])
	var grabs := int(TugBrain.total["grabs"]) - int(t0["grabs"])
	var drops := int(TugBrain.total["drops"]) - int(t0["drops"])
	var strikes := int(TugBrain.total["strikes"]) - int(t0["strikes"])
	return {"over": over_count, "fight_s": snappedf(tm.fight_time, 0.1), "score": tm.score.duplicate(), "winner_team": int(over_results.get("winner_team", -1)),
		"reason": String(over_results.get("reason", "")), "points": tm.points.duplicate(true), "max_mark_abs": snappedf(tm.max_mark_abs, 0.01),
		"grabs": grabs, "drops": drops, "strikes": strikes}


func _new_acc() -> Dictionary:
	return {"frames": 0, "phys_sum": 0.0, "phys_max": 0.0, "gap_max": 0.0, "gap_at": "", "gap_run": 0.0, "gap_run_max": 0.0, "oob": 0, "stuck_max": 0.0, "stuck_who": ""}


func _bots(level: int, trace: bool) -> void:
	print("--- bots (2×2, уровень %d)" % level)
	await _load(level, 3.0)
	var acc := _new_acc()
	var t0 := Time.get_ticks_usec()
	var r := await _run_match([level, level], BOTS_MAX_S, trace, acc)
	var wall_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var pts: Array = r["points"]
	var gaps: Array = []
	var prev := 0.0
	for p in pts:
		gaps.append(snappedf(float(p["t"]) - prev, 0.1))
		prev = float(p["t"])   # fight_time стоит на паузе после очка и в отсчёте
	var sorted := gaps.duplicate()
	sorted.sort()
	var median := float(sorted[sorted.size() / 2]) if not sorted.is_empty() else -1.0
	_check("bots_match_done", int(r["over"]) == 1 and float(r["fight_s"]) <= BOTS_MAX_S,
		"итогов %d за %.0f с игры (предел %.0f), счёт %s, причина %s" % [int(r["over"]), float(r["fight_s"]), BOTS_MAX_S, str(r["score"]), str(r["reason"])])
	_check("bots_points", pts.size() >= 1 and int(r["grabs"]) >= 4,
		"очков %d, хватов %d, выпало из руки %d" % [pts.size(), int(r["grabs"]), int(r["drops"])])
	_check("bots_point_pace", level != 2 or (median >= PACE_S.x and median <= PACE_S.y),
		"розыгрыш до очка %s с, медиана %.1f (цель %.0f–%.0f)" % [str(gaps), median, PACE_S.x, PACE_S.y])
	_check("bots_not_stuck", float(acc["stuck_max"]) < STUCK_LIMIT_S,
		"без каната на месте дольше всех %.1f с (%s; предел %.0f)" % [float(acc["stuck_max"]), String(acc["stuck_who"]), STUCK_LIMIT_S])
	_check("bots_in_bounds", int(acc["oob"]) == 0, "тиков за границей зала %d" % int(acc["oob"]))
	_check("bots_rope_intact", float(acc["gap_max"]) < GAP_TEAR_M and float(acc["gap_run_max"]) < GAP_HOLD_S,
		"наибольший зазор звеньев за матч %.3f м (%s), больше %.2f м подряд %.2f с" % [float(acc["gap_max"]), String(acc["gap_at"]), GAP_MAX_M, float(acc["gap_run_max"])])
	var frames := maxf(float(acc["frames"]), 1.0)
	var phys_ms := float(acc["phys_sum"]) / frames
	info["phys_ms"] = snappedf(phys_ms, 0.01)
	info["phys_ms_max"] = snappedf(float(acc["phys_max"]), 0.01)
	var wall_frame := wall_ms / frames
	_check("phys_ms_measured", int(acc["frames"]) > 0, "физика (монитор) %.2f мс / тик (пик %.2f), весь тик по часам %.2f мс, 4 куклы + 20 звеньев%s" % [
		phys_ms, float(acc["phys_max"]), wall_frame, "" if wall_frame <= PHYS_WARN_MS else " — выше %.0f мс (headless, сообщить автору)" % PHYS_WARN_MS])
	r["point_gaps_s"] = gaps
	r["point_gap_median_s"] = median
	r["stuck_max_s"] = snappedf(float(acc["stuck_max"]), 0.1)
	r["ms_per_physics_frame_wall"] = snappedf(wall_ms / frames, 0.01)
	r["tally"] = over_results.get("tally", {})
	info["bots"] = r


func _strong(n: int, trace: bool) -> void:
	print("--- strong (ур. 3 против ур. 1, %d матчей до 1 очка)" % n)
	var wins := 0
	var strikes_all := 0
	var rows: Array = []
	var acc := _new_acc()
	for i in n:
		var strong := i % 2   # 0 — синие сильные, 1 — красные
		await _load(2, 0.3, 1)
		var lv := [1, 1]
		lv[strong] = 3
		var r := await _run_match(lv, STRONG_MAX_S, trace, acc)
		var won := int(r["winner_team"]) == strong
		if won:
			wins += 1
		strikes_all += int(r["strikes"])
		rows.append({"strong": "blue" if strong == 0 else "red", "won": won, "fight_s": r["fight_s"], "score": r["score"], "reason": r["reason"],
			"strikes": r["strikes"]})
		print("  матч %d: сильные %s, победили %s за %.1f с (счёт %s)" % [i + 1, "синие" if strong == 0 else "красные",
			str(r["winner_team"]), float(r["fight_s"]), str(r["score"])])
	_check("strong_beats_weak", wins >= STRONG_MIN, "ур. 3 победил в %d из %d (нужно ≥ %d)" % [wins, n, STRONG_MIN])
	_check("strong_not_stuck", float(acc["stuck_max"]) < STUCK_LIMIT_S and int(acc["oob"]) == 0,
		"на месте дольше всех %.1f с (%s), за границей %d тиков" % [float(acc["stuck_max"]), String(acc["stuck_who"]), int(acc["oob"])])
	info["strong"] = {"wins": wins, "of": n, "strikes": strikes_all, "matches": rows}

