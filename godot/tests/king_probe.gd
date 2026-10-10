## Проба «Царя горы» (docs/plan-demo/KING.md) на настоящей площадке scenes/playground_king.tscn (купол, пятеро, KingMatch, KingZone,
## KingHud).
##   rules (все пятеро — боты с выключенными мозгами, куклы ставит проба): пятеро; точек зоны 6–8, все внутри купола; любой переезд —
##     не ближе KING_ZONE_MIN_MOVE_M; один в зоне — очко в секунду, остальным ничего; двое — никому, кольцо красное; один 10 с подряд —
##     «ЦАРЬ!», очки ×2; KO царя — корона снята, в нокауте очков нет, возврат через KING_RESPAWN_S вне зоны; переезд по таймеру: за
##     KING_ZONE_WARN_S мигает, призрак на новой точке, новая не ближе 6 м; до KING_SCORE_TO_WIN → итоги (победитель, места, табличка
##     HUD); R — всё заново; время вышло → победа по очкам;
##   bots (все пятеро — боты): матч доигрывается за ≤ max_s (6 мин); зона посетила ≥ 5 разных точек; очки набирали; никто не застрял
##     (вне зоны и не в ожидании у кромки — lurk — на месте < STUCK_LIMIT_S, жмёт тягу и стоит < PRESS_LIMIT_S), все в границах арены; физика на кадр (info.phys_ms).
## Обе секции: ошибок скриптов и ошибок движка — 0 (ошибки загрузки ресурсов с диска — отдельно, info.errors_assets).
## Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/king_probe.tscn -- "only=rules|bots|rules+bots,max_s=360,level=2,trace=1,seed=0,out=<json>"
## → JSON между === KING PROBE === и === OK / FAIL ===, exit 0/1.
extends Node

const SCENE := "res://scenes/playground_king.tscn"
const TICK := 1.0 / 60.0
const STUCK_M := 1.5
const STUCK_LIMIT_S := 30.0         # вне зоны не сдвинулся на STUCK_M
const PRESS_LIMIT_S := 4.0          # жмёт тягу, а торс стоит
const FAR := [Vector2(-12.0, 2.5), Vector2(12.0, 2.5), Vector2(-9.0, 10.0), Vector2(9.0, 10.0), Vector2(-12.0, 6.0)]
const HOME_SPOT := 1                # точка зоны на полу по центру (0, 2.2) — куклы лежат, не падают из неё


## Счётчик SCRIPT ERROR за прогон (как infection_probe): ошибка скрипта обрывает только свою функцию — проба могла бы молча потерять
## проверки. Ошибки загрузки ресурсов с диска (нет исходника .ogg в репозитории) — к режиму не относятся: отдельно, в info.
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
var pg: KingPlayground
var km: KingMatch
var over_results: Dictionary = {}
var over_count := 0
var errs := ScriptErrors.new()


func _check(id: String, cond: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": cond, "detail": str(detail)})
	if not cond:
		ok = false
	print("  %-30s %s  %s" % [id, "ok  " if cond else "FAIL", str(detail)])


func _args() -> Dictionary:
	var out := {"only": "", "max_s": "360", "level": "2", "trace": "0", "out": "", "seed": "0"}
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
	print("=== KING PROBE ===")
	var a := _args()
	if _want(a, "rules"):
		await _rules()
	if _want(a, "bots"):
		await _bots(float(a["max_s"]), int(a["level"]), String(a["trace"]) == "1", int(a["seed"]))
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

func _load(level := 2, countdown := 0.3, seed_ := 0) -> void:
	await _unload()
	Engine.time_scale = 1.0
	pg = (load(SCENE) as PackedScene).instantiate() as KingPlayground
	pg.p1_bot = true
	pg.p2_bot = true
	pg.bot_level = level
	km = pg.get_node("Match") as KingMatch
	km.feel_enabled = false
	km.countdown_s = countdown
	km.rng_seed = seed_
	over_results = {}
	over_count = 0
	km.match_over.connect(func(_w: Doll, r: Dictionary) -> void:
		over_results = r
		over_count += 1)
	add_child(pg)
	await _until(func() -> bool: return km.play_state == "play" and km.dolls().size() == Tuning.KING_DOLLS, 8.0)


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
	for d in km.dolls():
		if is_instance_valid(d) and (d as Doll).player_index == index:
			return d
	return null


func _brains_off() -> void:
	for d in km.dolls():
		var b := (d as Node).get_node_or_null(KingPlayground.BOT_NAME)
		if b != null:
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


func _spread_all() -> void:
	var i := 0
	for d in km.dolls():
		if (d as Doll).alive:
			_place(d, FAR[i % FAR.size()])
		i += 1


## Зона — на точке i, до переезда далеко (проба сама решает, когда ей переехать).
func _pin_zone(i: int) -> void:
	km._set_zone(i)
	km.zone_left = 1000.0


func _score(pi: int) -> float:
	return float(km.scores.get(pi, 0.0))


func _others_sum(pi: int) -> float:
	var s := 0.0
	for k in km.scores:
		if int(k) != pi:
			s += float(km.scores[k])
	return s


func _zone_dist(d: Doll) -> float:
	var c := d.centre_of_mass()
	return Vector2(c.x, c.y).distance_to(km.zone_pos)


# ------------------------------------------------------------------ правила

func _rules() -> void:
	print("--- rules")
	await _load(2, 0.3, 4242)
	_brains_off()
	_check("five_dolls", km.dolls().size() == Tuning.KING_DOLLS and km.play_state == "play", "кукол %d, фаза %s" % [km.dolls().size(), km.play_state])
	# --- точки зоны: 6–8, внутри купола; переезд всегда не ближе 6 м
	var spots: Array = Tuning.KING_ZONE_SPOTS
	var b: AABB = pg.arena.call("bounds")
	var inside := true
	var ys: Array = []
	for s in spots:
		var v := s as Vector2
		ys.append(v.y)
		inside = inside and v.x - Tuning.KING_ZONE_R > b.position.x and v.x + Tuning.KING_ZONE_R < b.end.x \
			and v.y > b.position.y and v.y + Tuning.KING_ZONE_R < b.end.y
	_check("zone_spots", spots.size() >= 6 and spots.size() <= 8 and inside and float(ys.max()) - float(ys.min()) >= 8.0,
		"точек %d, внутри купола %s (границы %s), высоты %.1f…%.1f м" % [spots.size(), inside, str(b), float(ys.min()), float(ys.max())])
	var min_move := INF
	for i in spots.size():
		for k in 20:
			var n := km.pick_next(i)
			min_move = minf(min_move, (spots[i] as Vector2).distance_to(spots[n]))
	_check("pick_next_far", min_move >= Tuning.KING_ZONE_MIN_MOVE_M, "ближайший переезд из 160 выборов %.2f м (предел %.1f)" % [min_move, Tuning.KING_ZONE_MIN_MOVE_M])

	# --- один в зоне: очко в секунду
	_spread_all()
	_pin_zone(HOME_SPOT)
	await _wait(0.5)
	var a := _doll(2)
	var s0 := _score(2)
	var o0 := _others_sum(2)
	_place(a, Vector2(0.0, 1.4))
	await _wait(0.4)
	var t0 := km.fight_time
	var sa := _score(2)
	await _wait(3.0)
	var rate := (_score(2) - sa) / maxf(km.fight_time - t0, 0.01)
	_check("one_scores", km.holder == a and km.zone_state == "held" and absf(rate - Tuning.KING_POINT_PER_S) < 0.1 and _others_sum(2) == o0 and s0 == 0.0,
		"%s в зоне один (до центра %.2f м): %.2f очка/с, у других %.1f" % [KingMatch.doll_name(a), _zone_dist(a), rate, _others_sum(2)])
	var col_held := KingZone.colour_for(km)
	# --- двое: никому
	var c := _doll(3)
	_place(c, Vector2(1.2, 1.4))
	await _wait(0.4)
	var sa2 := _score(2)
	var sc2 := _score(3)
	await _wait(2.0)
	_check("two_nobody", km.zone_state == "contested" and km.holder == null and _score(2) == sa2 and _score(3) == sc2
		and KingZone.colour_for(km) == KingMatch.ZONE_COLOUR_CONTESTED and col_held != KingMatch.ZONE_COLOUR_CONTESTED,
		"в зоне %d, состояние %s, очки %.2f / %.2f не растут, кольцо %s" % [km.occupants.size(), km.zone_state, _score(2), _score(3), str(KingZone.colour_for(km))])
	_check("hud_contested", pg.hud.king_label.text == tr("ЗОНА СПОРНАЯ"), "HUD: «%s»" % pg.hud.king_label.text)
	# --- стрик: один 10 с подряд — «ЦАРЬ!», ×2
	_place(c, FAR[3])
	var crowned_at := {"t": -1.0}
	var on_crown := func(d: Doll) -> void: crowned_at["t"] = km.fight_time
	km.king_crowned.connect(on_crown)
	var t_alone := km.fight_time
	var got := await _until(func() -> bool: return km.crowned, Tuning.KING_STREAK_S + 2.0)
	var streak_t := float(crowned_at["t"]) - t_alone
	var sb := _score(2)
	var tb := km.fight_time
	await _wait(2.0)
	var rate2 := (_score(2) - sb) / maxf(km.fight_time - tb, 0.01)
	_check("streak_crown", got and km.holder == a and km.crowns.size() == 1 and int(km.crowns[0]["pi"]) == 2
		and streak_t >= Tuning.KING_STREAK_S - 0.6 and streak_t <= Tuning.KING_STREAK_S + 0.6,
		"корона через %.2f с одиночества (стрик %.0f с), корон %d" % [streak_t, Tuning.KING_STREAK_S, km.crowns.size()])
	_check("streak_double", absf(rate2 - Tuning.KING_POINT_PER_S * Tuning.KING_STREAK_MULT) < 0.15, "с короной %.2f очка/с" % rate2)
	await get_tree().process_frame
	_check("hud_king", pg.hud.king_label.text == tr("ЦАРЬ: %s") % KingMatch.doll_name(a), "HUD: «%s»" % pg.hud.king_label.text)
	# --- KO царя: корона снята, очков нет, возврат через 3 с вне зоны
	var lost := {"n": 0}
	km.king_lost.connect(func(_d: Doll) -> void: lost["n"] = int(lost["n"]) + 1)
	var back := {"d": null, "t": -1.0}
	km.doll_respawned.connect(func(d: Doll) -> void:
		back["d"] = d
		back["t"] = km.fight_time)
	var sk := _score(2)
	var t_ko := km.fight_time
	a.knock_out()
	await get_tree().physics_frame
	var no_crown := not km.crowned and km.holder == null and int(lost["n"]) == 1
	await _wait(Tuning.KING_RESPAWN_S - 0.5)
	var ko_still := not a.alive and is_instance_valid(a)
	var ko_score := _score(2)
	var came := await _until(func() -> bool: return back["d"] != null, 2.0)
	_brains_off()
	var nd: Doll = back["d"]
	var dist := _zone_dist(nd) if nd != null else -1.0
	_check("ko_crown_lost", no_crown and km.ko_log.size() == 1 and int(km.ko_log[0]["victim"]) == 2, "корона снята %s, сигналов king_lost %d" % [no_crown, int(lost["n"])])
	_check("ko_no_points", ko_still and absf(ko_score - sk) < 1e-4, "в нокауте очки %.2f → %.2f" % [sk, ko_score])
	_check("ko_respawn_outside", came and nd != null and nd.alive and nd.player_index == 2 and dist > Tuning.KING_ZONE_R
		and absf(float(back["t"]) - t_ko - Tuning.KING_RESPAWN_S) < 0.2,
		"возврат через %.2f с, до центра зоны %.2f м (радиус %.1f)" % [float(back["t"]) - t_ko, dist, Tuning.KING_ZONE_R])
	await _wait(0.5)
	_check("ko_respawn_no_score", _zone_dist(nd) > Tuning.KING_ZONE_R and absf(_score(2) - ko_score) < 1e-4, "после возврата очки %.2f" % _score(2))

	# --- переезд по таймеру: мигание, призрак, новая точка не ближе 6 м
	_spread_all()
	var from_i := km.zone_i
	var moves0 := km.moves.size()
	km.zone_left = Tuning.KING_ZONE_WARN_S + 0.5
	var warned := await _until(func() -> bool: return km.warning(), 1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var ghost_ok := pg.ghost.visible and pg.ghost.global_position.distance_to(km.next_centre()) < 0.01
	var nxt := km.next_i
	var moved := await _until(func() -> bool: return km.moves.size() > moves0, Tuning.KING_ZONE_WARN_S + 1.0)
	var mv: Dictionary = km.moves[-1] if moved else {}
	await get_tree().process_frame
	_check("zone_warn_ghost", warned and ghost_ok and nxt >= 0, "мигает %s, призрак на новой точке %s" % [warned, ghost_ok])
	_check("zone_moves", moved and int(mv["from"]) == from_i and int(mv["to"]) == nxt and float(mv["dist"]) >= Tuning.KING_ZONE_MIN_MOVE_M
		and absf(km.zone_left - km.zone_period_s) < 0.1 and not pg.ghost.visible and pg.zone.global_position.distance_to(km.zone_centre()) < 0.01,
		"переезд %s, до следующего %.1f с" % [str(mv), km.zone_left])
	_check("zone_in_focus", pg.zone.is_in_group(KingPlayground.FOCUS_GROUP), "зона в кадре камеры (людей нет)")

	# --- до 60 → итоги
	_pin_zone(HOME_SPOT)
	var w := _doll(4)
	km.scores[4] = float(km.score_to_win) - 0.5
	_place(w, Vector2(0.0, 1.4))
	var done := await _until(func() -> bool: return over_count > 0, 3.0)
	var places: Array = over_results.get("places", [])
	var sorted_ok := not places.is_empty()
	for i in range(1, places.size()):
		sorted_ok = sorted_ok and km.score_of(places[i]) <= km.score_of(places[i - 1])
	_check("win_at_score", done and over_count == 1 and over_results.get("winner") == w and String(over_results.get("reason", "score")) == "score"
		and km.phase == Match.Phase.OVER and sorted_ok and places[0] == w and int((over_results.get("scores", {}) as Dictionary).get(4, 0)) >= Tuning.KING_SCORE_TO_WIN,
		"итогов %d, победил %s, очки %s" % [over_count, KingMatch.doll_name(over_results.get("winner")), str(over_results.get("scores"))])
	await _wait(1.2)
	_check("hud_end_panel", pg.hud.end_panel.visible and pg.hud.end_title.text != "" and pg.hud.end_table.get_child_count() == 5 * (Tuning.KING_DOLLS + 1),
		"табличка: «%s» · %s, ячеек %d" % [pg.hud.end_title.text, pg.hud.end_sub.text, pg.hud.end_table.get_child_count()])
	# --- R: заново
	km.restart()
	await _until(func() -> bool: return km.play_state == "play", 6.0)
	_brains_off()
	var zero := true
	for k in km.scores:
		zero = zero and float(km.scores[k]) == 0.0
	_check("restart_resets", zero and km.scores.size() == Tuning.KING_DOLLS and km.alive_dolls().size() == Tuning.KING_DOLLS and km.moves.is_empty()
		and km.crowns.is_empty() and km.ko_log.is_empty() and not pg.hud.end_panel.visible and over_count == 1 and km.zone_left > km.zone_period_s - 1.0,
		"очки %s, живых %d, панель %s" % [str(km.scores), km.alive_dolls().size(), pg.hud.end_panel.visible])
	# --- время вышло → больше очков
	_spread_all()
	km.scores[1] = 12.0
	km.scores[3] = 20.0
	km.fight_time = km.time_limit_s - 0.3
	var timed := await _until(func() -> bool: return over_count > 1, 2.0)
	_check("timeout_most_points", timed and over_results.get("winner") == _doll(3) and not bool(over_results.get("draw", true)),
		"итогов %d, победил %s, очки %s" % [over_count, KingMatch.doll_name(over_results.get("winner")), str(over_results.get("scores"))])


# ------------------------------------------------------------------ матч ботов

func _bots(max_s: float, level: int, trace: bool, seed_: int) -> void:
	print("--- bots (уровень %d)" % level)
	await _load(level, 3.0, seed_)
	var acc := {"hits": 0, "dmg": 0.0}
	km.hit.connect(func(_v: Doll, att: Node, dmg: float, _k: String, _p: Vector3) -> void:
		if att is Doll:
			acc["hits"] = int(acc["hits"]) + 1
		acc["dmg"] = float(acc["dmg"]) + dmg)
	var last_pos: Dictionary = {}
	var stuck_max := 0.0
	var stuck_who := ""
	var press_t: Dictionary = {}
	var press_max := 0.0
	var press_who := ""
	var out_of_bounds := 0
	var b: AABB = pg.arena.call("bounds")
	var t0 := Time.get_ticks_usec()
	var frames := 0
	var trace_t := 0.0
	var phys_us := 0
	var held_t := 0.0
	var contested_t := 0.0
	while over_count == 0 and km.fight_time < max_s:
		var f0 := Time.get_ticks_usec()
		await get_tree().physics_frame
		phys_us += Time.get_ticks_usec() - f0
		frames += 1
		var playing := km.play_state == "play"
		if playing:
			if km.zone_state == "held":
				held_t += TICK
			elif km.zone_state == "contested":
				contested_t += TICK
		for d in km.dolls():
			var dd := d as Doll
			if not dd.alive or not playing:
				last_pos.erase(dd.player_index)
				press_t.erase(dd.player_index)
				continue
			var c := dd.centre_of_mass()
			if c.x < b.position.x - 0.5 or c.x > b.end.x + 0.5 or c.y < b.position.y - 0.5 or c.y > b.end.y + 0.5:
				out_of_bounds += 1
			var br := dd.get_node_or_null(KingPlayground.BOT_NAME) as KingBrain
			var lp: Array = last_pos.get(dd.player_index, [])
			var waiting := km.in_zone(c) or (br != null and br.state == "lurk")   # держит зону / ждёт у кромки — не застрял
			if lp.is_empty() or (lp[0] as Vector3).distance_to(c) > STUCK_M or waiting:
				last_pos[dd.player_index] = [c, km.fight_time]
			elif km.fight_time - float(lp[1]) > stuck_max:
				stuck_max = km.fight_time - float(lp[1])
				stuck_who = "%s в (%.1f, %.1f), %s" % [KingMatch.doll_name(dd), c.x, c.y, br.state if br != null else "-"]
			if dd.input_vec.length() >= 0.5 and dd.torso().linear_velocity.length() < 0.35 and not km.in_zone(c):
				press_t[dd.player_index] = float(press_t.get(dd.player_index, 0.0)) + TICK
				if float(press_t[dd.player_index]) > press_max:
					press_max = float(press_t[dd.player_index])
					press_who = "%s в (%.1f, %.1f), %s" % [KingMatch.doll_name(dd), c.x, c.y, br.state if br != null else "-"]
			else:
				press_t.erase(dd.player_index)
		if trace and km.fight_time - trace_t >= 10.0:
			trace_t = km.fight_time
			var row := []
			for d in km.dolls():
				var br := (d as Node).get_node_or_null(KingPlayground.BOT_NAME) as KingBrain
				var cc := (d as Doll).centre_of_mass()
				row.append("%s:%s(%.0f,%.0f)%.0f%s" % [KingMatch.doll_name(d), br.state if br != null else "-", cc.x, cc.y,
					_score((d as Doll).player_index), "" if (d as Doll).alive else "†"])
			print("  t=%6.1f зона %d (%.0f,%.0f) %s  %s" % [km.fight_time, km.zone_i, km.zone_pos.x, km.zone_pos.y, km.zone_state, " ".join(row)])
	var wall_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var winner: Doll = over_results.get("winner")
	var sc: Dictionary = over_results.get("scores", {})
	var top := 0
	for k in sc:
		top = maxi(top, int(sc[k]))
	_check("bots_match_done", over_count == 1 and km.fight_time <= max_s and top > 0,
		"итогов %d за %.0f с игры (предел %.0f), причина %s, победил %s, очки %s" % [over_count, km.fight_time, max_s,
		str(over_results.get("reason", "?")), KingMatch.doll_name(winner), str(sc)])
	var spots_seen := km.visited.keys().size()
	_check("bots_zone_visited", spots_seen >= 5, "зона стояла на %d разных точках из %d (переездов %d)" % [spots_seen, Tuning.KING_ZONE_SPOTS.size(), km.moves.size()])
	var far_ok := true
	for m in km.moves:
		far_ok = far_ok and float(m["dist"]) >= Tuning.KING_ZONE_MIN_MOVE_M
	_check("bots_moves_far", far_ok, "все переезды не ближе %.0f м" % Tuning.KING_ZONE_MIN_MOVE_M)
	_check("bots_fight", int(acc["hits"]) > 10 and km.ko_log.size() >= 1 and contested_t > 1.0,
		"ударов кукла о куклу %d, нокаутов %d, зона спорная %.0f с, занята %.0f с" % [int(acc["hits"]), km.ko_log.size(), contested_t, held_t])
	_check("bots_not_stuck", stuck_max < STUCK_LIMIT_S and press_max < PRESS_LIMIT_S,
		"вне зоны (не lurk) на месте дольше всех %.1f с (%s; предел %.0f); упёрся %.1f с (%s; предел %.0f)" % [
		stuck_max, stuck_who, STUCK_LIMIT_S, press_max, press_who, PRESS_LIMIT_S])
	_check("bots_in_bounds", out_of_bounds == 0, "тиков за границей арены %d" % out_of_bounds)
	var states := {}
	for d in km.dolls():
		var br := (d as Node).get_node_or_null(KingPlayground.BOT_NAME) as KingBrain
		if br != null:
			for k in br.counters:
				states[k] = int(states.get(k, 0)) + int(br.counters[k])
	info["bots"] = {"level": level, "fight_s": snappedf(km.fight_time, 0.1), "reason": over_results.get("reason", "?"), "scores": sc,
		"visited": km.visited.duplicate(), "moves": km.moves.size(), "crowns": km.crowns.duplicate(true), "kos": km.ko_log.size(),
		"hits": acc["hits"], "held_s": snappedf(held_t, 0.1), "contested_s": snappedf(contested_t, 0.1),
		"stuck_max_s": snappedf(stuck_max, 0.1), "press_max_s": snappedf(press_max, 0.1), "brain_counters": states,
		"ms_per_physics_frame": snappedf(wall_ms / maxf(frames, 1), 0.01),
		"phys_ms": snappedf(float(phys_us) / 1000.0 / maxf(frames, 1), 0.01), "tally": over_results.get("tally", {})}
