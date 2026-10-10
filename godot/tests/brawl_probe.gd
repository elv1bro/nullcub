## Проба «Стенки на стенку 5×5» (docs/plan-demo/BRAWL.md) на настоящей площадке scenes/playground_brawl.tscn (Полигон, десять кукол,
## BrawlMatch, BrawlBrain, BrawlHud).
##   rules (все десять — боты с выключенными мозгами, куклы ставит проба): десять кукол, по пять в двух командах (синие — чётный
##     player_index слева, красные — справа), свои не ранят своих (удар — урон 0, запас цел), чужих — ранят; выбывший в раунде не
##     возвращается; раунд кончается последней живой командой (победа ей, счёт, пауза), следующий раунд — все снова живы на своих
##     точках; лимит раунда → Sudden Death (отброс растёт), на жёстком лимите раунд — команде с большим запасом; матч до
##     BRAWL_WINS_TO_WIN → итоги (победившая команда, медали, табличка HUD); R (restart) — всё заново;
##   bots (все десять — боты): матч до wins побед доигрывается за ≤ max_s игрового времени (по умолчанию 600 с), у каждого раунда есть
##     исход, нокаутов много, свои своих не выбивают, никто не застрял (на месте < STUCK_LIMIT_S, жмёт тягу и стоит < PRESS_LIMIT_S), все
##     в границах арены; перф — среднее время физического тика info.phys_ms (Performance.TIME_PHYSICS_PROCESS), отдельная проверка
##     не валит (headless без рендера — только сообщение в отчёте, порог PHYS_WARN_MS).
## Обе секции: ошибок скриптов (errors_script) и движка (errors_engine) — 0.
## Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/brawl_probe.tscn -- "only=rules|bots|rules+bots,max_s=600,level=2,wins=2,trace=1,out=<json>"
## → JSON между === BRAWL PROBE === и === OK / FAIL ===, exit 0/1.
extends Node

const SCENE := "res://scenes/playground_brawl.tscn"
const TICK := 1.0 / 60.0
const STUCK_M := 1.5
const STUCK_LIMIT_S := 30.0         # не сдвинулся на STUCK_M (боец обязан драться, а не висеть)
const PRESS_LIMIT_S := 4.0          # жмёт тягу, а торс стоит
const PHYS_WARN_MS := 6.0

## Счётчик SCRIPT ERROR за прогон (как bomb_probe): ошибка скрипта обрывает только свою функцию — проба могла бы молча потерять проверки.
class ScriptErrors extends Logger:
	var count := 0
	var first := ""
	var engine := 0
	var engine_first := ""
	var _mx := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		_mx.lock()
		if error_type == ERROR_TYPE_SCRIPT:
			count += 1
			if first == "":
				first = "%s %s (%s:%d %s)" % [code, rationale, file, line, function]
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
var pg: BrawlPlayground
var bm: BrawlMatch
var over_results: Dictionary = {}
var over_count := 0
var errs := ScriptErrors.new()


func _check(id: String, cond: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": cond, "detail": str(detail)})
	if not cond:
		ok = false
	print("  %-30s %s  %s" % [id, "ok  " if cond else "FAIL", str(detail)])


func _args() -> Dictionary:
	var out := {"only": "", "max_s": "600", "level": "2", "trace": "0", "out": "", "wins": str(Tuning.BRAWL_WINS_TO_WIN)}
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
	print("=== BRAWL PROBE ===")
	var a := _args()
	if _want(a, "rules"):
		await _rules()
	if _want(a, "bots"):
		await _bots(float(a["max_s"]), int(a["level"]), int(a["wins"]), String(a["trace"]) == "1")
	await _unload()
	_check("errors_script", errs.count == 0, "ошибок скриптов %d; первая: %s" % [errs.count, errs.first])
	_check("errors_engine", errs.engine == 0, "ошибок движка %d; первая: %s" % [errs.engine, errs.engine_first])
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

func _load(level := 2, countdown := 0.3) -> void:
	await _unload()
	Engine.time_scale = 1.0
	pg = (load(SCENE) as PackedScene).instantiate() as BrawlPlayground
	pg.p1_bot = true
	pg.p2_human = false
	pg.bot_level = level
	bm = pg.get_node("Match") as BrawlMatch
	bm.feel_enabled = false
	bm.countdown_s = countdown
	over_results = {}
	over_count = 0
	bm.match_over.connect(func(_w: Doll, r: Dictionary) -> void:
		over_results = r
		over_count += 1)
	add_child(pg)
	await _until(func() -> bool: return bm.play_state == "play" and bm.dolls().size() == Tuning.BRAWL_PER_TEAM * 2, 10.0)


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
	for d in bm.dolls():
		if is_instance_valid(d) and (d as Doll).player_index == index:
			return d
	return null


func _brains_off() -> void:
	for d in bm.dolls():
		var b := (d as Node).get_node_or_null("BrawlBrain")
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


func _launch(d: Doll, v: Vector3) -> void:
	for b in d.parts.values():
		(b as RigidBody3D).linear_velocity = v


func _speed(d: Doll) -> float:
	return d.torso().linear_velocity.length()


## Развести всех по дальним углам (чтобы никто ни с кем не сталкивался), кроме except.
func _park(except: Array) -> void:
	var k := 0
	for d in bm.dolls():
		if except.has(d):
			continue
		var dd := d as Doll
		var x := -29.0 + 2.6 * float(k % 5) if BrawlMatch.team_of(dd) == 0 else 29.0 - 2.6 * float(k % 5)
		_place(dd, Vector2(x, 9.0 + 2.0 * float(k / 5)))
		k += 1


## Удар a по b: разгон a на 9 м/с к b на расстоянии 3.2 м; возвращает {hits, dmg, peak} по сигналу hit за 50 тиков.
func _collide(a: Doll, b: Doll) -> Dictionary:
	_place(a, Vector2(0.0, 6.0))
	_place(b, Vector2(3.2, 6.0))
	await _wait(0.2)
	var acc := {"hits": 0, "dmg": 0.0, "peak": 0.0}
	var on_hit := func(v: Doll, att: Node, dmg: float, _k: String, _p: Vector3) -> void:
		if v == b and att == a:
			acc["hits"] = int(acc["hits"]) + 1
			acc["dmg"] = float(acc["dmg"]) + dmg
	bm.hit.connect(on_hit)
	_launch(a, Vector3(9.0, 0.0, 0.0))
	for i in 50:
		await get_tree().physics_frame
		acc["peak"] = maxf(float(acc["peak"]), _speed(b))
	bm.hit.disconnect(on_hit)
	return acc


# ------------------------------------------------------------------ правила

func _rules() -> void:
	print("--- rules")
	await _load(2, 0.3)
	_brains_off()
	var n := bm.dolls().size()
	_check("ten_dolls", n == Tuning.BRAWL_PER_TEAM * 2 and bm.play_state == "play", "кукол %d, фаза %s" % [n, bm.play_state])
	var blue := bm.team_dolls(0)
	var red := bm.team_dolls(1)
	var teams_ok := blue.size() == Tuning.BRAWL_PER_TEAM and red.size() == Tuning.BRAWL_PER_TEAM
	var sides_ok := true
	var groups_ok := true
	var mult_ok := true
	for d in bm.dolls():
		var dd := d as Doll
		var t := BrawlMatch.team_of(dd)
		var x := dd.centre_of_mass().x
		sides_ok = sides_ok and ((t == 0 and x < -15.0) or (t == 1 and x > 15.0))
		groups_ok = groups_ok and dd.team == "brawl_%d" % t and dd.is_in_group(BrawlMatch.team_group(t)) and not dd.is_in_group(BrawlMatch.team_group(1 - t))
		mult_ok = mult_ok and is_equal_approx(dd.team_damage_mult, Tuning.BRAWL_TEAM_DAMAGE_MULT)
	_check("two_teams", teams_ok and groups_ok, "синих %d, красных %d, Doll.team и группы по командам" % [blue.size(), red.size()])
	_check("sides", sides_ok, "синие слева (x < −15), красные справа (x > 15)")
	_check("team_damage_mult", mult_ok, "team_damage_mult %.2f у всех" % Tuning.BRAWL_TEAM_DAMAGE_MULT)
	var p1 := _doll(0)
	var p3 := _doll(2)
	var p2 := _doll(1)
	_park([p1, p3, p2])
	_place(p2, Vector2(20.0, 9.0))
	# --- свой своего не ранит
	var own: Dictionary = await _collide(p1, p3)
	_check("no_friendly_damage", int(own["hits"]) > 0 and float(own["dmg"]) == 0.0 and p3.hp == p3.max_hp and p3.alive and float(own["peak"]) > 1.5,
		"ударов %d, урон %.1f, HP %.0f / %.0f, отброс до %.1f м/с" % [int(own["hits"]), float(own["dmg"]), p3.hp, p3.max_hp, float(own["peak"])])
	_place(p3, Vector2(-29.0, 9.0))
	await _wait(0.3)
	# --- чужого ранит
	var hp0 := p2.hp
	var foe: Dictionary = await _collide(p1, p2)
	_check("enemy_damage", int(foe["hits"]) > 0 and float(foe["dmg"]) > 0.0 and p2.hp < hp0,
		"ударов %d, урон %.1f, HP %.0f → %.0f" % [int(foe["hits"]), float(foe["dmg"]), hp0, p2.hp])
	_park([])
	await _wait(0.3)
	# --- выбывший в раунде не возвращается
	var alive0 := bm.alive_dolls().size()
	p2.knock_out()
	await _wait(3.0)
	_check("no_respawn_in_round", bm.alive_dolls().size() == alive0 - 1 and bm.play_state == "play" and bm.team_alive(1).size() == Tuning.BRAWL_PER_TEAM - 1,
		"живых %d → %d, фаза %s" % [alive0, bm.alive_dolls().size(), bm.play_state])
	# --- раунд кончается последней живой командой
	var wins0: Array = bm.wins.duplicate()
	for d in bm.team_alive(1):
		(d as Doll).knock_out()
		await get_tree().physics_frame
	await _wait(0.2)
	var r0: Dictionary = bm.rounds[-1] if not bm.rounds.is_empty() else {}
	_check("round_last_team", bm.play_state == "round_end" and int(bm.wins[0]) == int(wins0[0]) + 1 and int(bm.wins[1]) == int(wins0[1])
		and int(r0.get("winner", -2)) == 0 and String(r0.get("reason", "")) == "ko" and bm.phase != Match.Phase.OVER,
		"фаза %s, счёт %s, раунд %d взяли %s (%s)" % [bm.play_state, str(bm.wins), int(r0.get("round", 0)), str(r0.get("winner", "?")), str(r0.get("reason", "?"))])
	_check("no_self_ko_count", bm.kos.size() == Tuning.BRAWL_PER_TEAM and bm.kos.all(func(k: Dictionary) -> bool: return int(k["team"]) == 1),
		"нокаутов %d, все у красных" % bm.kos.size())
	# --- пауза и новая расстановка
	var t_end := bm.fight_time
	var next_ok := await _until(func() -> bool: return bm.round_i == 2 and bm.play_state == "play", Tuning.BRAWL_ROUND_PAUSE_S + Tuning.BRAWL_COUNTDOWN_S + 1.5)
	var paused := bm.fight_time - t_end
	var placed := true
	for d in bm.dolls():
		var dd := d as Doll
		var sp := BrawlMatch.spawn_for(dd.player_index)
		placed = placed and dd.alive and absf(dd.centre_of_mass().x - sp.x) < 2.5 and absf(dd.centre_of_mass().y - sp.y) < 3.5
	_check("next_round", next_ok and bm.alive_dolls().size() == Tuning.BRAWL_PER_TEAM * 2 and placed and int(bm.wins[0]) == 1
		and paused >= Tuning.BRAWL_ROUND_PAUSE_S - TICK and bm.round_time < 0.5,
		"раунд %d, живых %d, все у своих точек: %s, пауза %.1f с, счёт %s" % [bm.round_i, bm.alive_dolls().size(), str(placed), paused, str(bm.wins)])
	_brains_off()
	_park([])
	# --- лимит раунда → Sudden Death
	bm.round_time = Tuning.BRAWL_ROUND_LIMIT_S - 0.1
	await _wait(0.3)
	var sd0 := bm.phase == Match.Phase.SUDDEN_DEATH and bm.sd_step == 0
	bm.round_time = Tuning.BRAWL_ROUND_LIMIT_S + Tuning.SUDDEN_DEATH_STEP_S * 2.0 + 0.1
	await _wait(0.1)
	_check("round_limit_sudden_death", sd0 and bm.phase == Match.Phase.SUDDEN_DEATH and bm.sd_step == 2 and bm.knockback_mult() > 1.0 and bm.play_state == "play",
		"фаза %d (SD %d), шаг %d, отброс ×%.2f" % [bm.phase, Match.Phase.SUDDEN_DEATH, bm.sd_step, bm.knockback_mult()])
	# --- жёсткий лимит: раунд — команде с большим запасом (красные целы, синим снимаем)
	for d in bm.team_alive(0):
		(d as Doll).hp = 40.0
	bm.round_time = Tuning.BRAWL_ROUND_HARD_S - 0.1
	await _wait(0.3)
	var r1: Dictionary = bm.rounds[-1] if bm.rounds.size() >= 2 else {}
	_check("hard_limit_by_hp", bm.play_state == "round_end" and int(r1.get("winner", -2)) == 1 and String(r1.get("reason", "")) == "time"
		and int(bm.wins[0]) == 1 and int(bm.wins[1]) == 1,
		"фаза %s, раунд %d взяли %s (%s), запас %s, счёт %s" % [bm.play_state, int(r1.get("round", 0)), str(r1.get("winner", "?")), str(r1.get("reason", "?")), str(r1.get("hp", [])), str(bm.wins)])
	# --- третий раунд: мышцы снова целы (новые куклы), затем матч до BRAWL_WINS_TO_WIN
	var round3 := await _until(func() -> bool: return bm.round_i == 3 and bm.play_state == "play", Tuning.BRAWL_ROUND_PAUSE_S + Tuning.BRAWL_COUNTDOWN_S + 1.5)
	_check("round3_fresh", round3 and bm.phase == Match.Phase.FIGHT and bm.sd_step == -1 and bm.knockback_mult() == 1.0 and bm.alive_dolls().size() == Tuning.BRAWL_PER_TEAM * 2,
		"раунд %d, фаза %d, шаг SD %d, живых %d" % [bm.round_i, bm.phase, bm.sd_step, bm.alive_dolls().size()])
	_brains_off()
	_park([])
	for d in bm.team_alive(1):
		(d as Doll).knock_out()
		await get_tree().physics_frame
	var done := await _until(func() -> bool: return over_count > 0, Tuning.BRAWL_ROUND_PAUSE_S + 1.0)
	var wt := int(over_results.get("winner_team", -2))
	var places: Array = over_results.get("places", [])
	var medals: Dictionary = over_results.get("medals", {})
	_check("match_to_wins", done and over_count == 1 and wt == 0 and bm.phase == Match.Phase.OVER and int(bm.wins[0]) == Tuning.BRAWL_WINS_TO_WIN
		and bm.rounds.size() == 3 and not places.is_empty() and BrawlMatch.team_of(places[0]) == 0 and over_results.get("winner") != null,
		"итогов %d, победили %s, счёт %s, раундов %d, первый в местах %s" % [over_count, str(wt), str(bm.wins), bm.rounds.size(), BrawlMatch.doll_name(places[0] if not places.is_empty() else null)])
	var winner_blue := medals.has("Winner") and BrawlMatch.team_of(medals["Winner"]) == 0
	_check("medals", winner_blue and medals.size() >= 2, "медали: %s" % ", ".join(medals.keys().map(func(k: String) -> String: return "%s:%s" % [k, BrawlMatch.doll_name(medals[k])])))
	await _wait(1.2)
	_check("hud_end_panel", pg.hud.end_panel.visible and pg.hud.end_title.text != "" and pg.hud.end_table.get_child_count() >= 4 * 11,
		"табличка: «%s» · %s · клеток %d" % [pg.hud.end_title.text, pg.hud.end_sub.text, pg.hud.end_table.get_child_count()])
	# --- R: заново
	bm.restart()
	await _until(func() -> bool: return bm.play_state == "play", 6.0)
	_check("restart_resets", int(bm.wins[0]) == 0 and int(bm.wins[1]) == 0 and bm.round_i == 1 and bm.rounds.is_empty() and bm.kos.is_empty()
		and bm.alive_dolls().size() == Tuning.BRAWL_PER_TEAM * 2 and not pg.hud.end_panel.visible and bm.phase == Match.Phase.FIGHT,
		"раунд %d, счёт %s, живых %d" % [bm.round_i, str(bm.wins), bm.alive_dolls().size()])


# ------------------------------------------------------------------ матч ботов

func _bots(max_s: float, level: int, wins_n: int, trace: bool) -> void:
	print("--- bots (уровень %d, до %d побед)" % [level, wins_n])
	await _load(level, 3.0)
	bm.wins_to_win = wins_n
	var acc := {"hits": 0, "dmg": 0.0, "friendly_dmg": 0.0}
	bm.hit.connect(func(v: Doll, a: Node, dmg: float, _k: String, _p: Vector3) -> void:
		if a is Doll:
			acc["hits"] = int(acc["hits"]) + 1
			if BrawlMatch.team_of(a) == BrawlMatch.team_of(v):
				acc["friendly_dmg"] = float(acc["friendly_dmg"]) + dmg
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
	var phys_sum := 0.0
	var phys_max := 0.0
	var trace_t := 0.0
	var round_seen := bm.round_i
	while over_count == 0 and bm.fight_time < max_s:
		await get_tree().physics_frame
		frames += 1
		var pm := float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		phys_sum += pm
		phys_max = maxf(phys_max, pm)
		if bm.round_i != round_seen:
			round_seen = bm.round_i
			last_pos.clear()
			press_t.clear()
		var playing := bm.play_state == "play"
		for d in bm.dolls():
			var dd := d as Doll
			if not dd.alive or not playing:
				last_pos.erase(dd.player_index)
				press_t.erase(dd.player_index)
				continue
			var c := dd.centre_of_mass()
			if c.x < b.position.x - 0.5 or c.x > b.end.x + 0.5 or c.y < b.position.y - 0.5 or c.y > b.end.y + 0.5:
				out_of_bounds += 1
			var br := dd.get_node_or_null("BrawlBrain") as BrawlBrain
			var lp: Array = last_pos.get(dd.player_index, [])
			if lp.is_empty() or (lp[0] as Vector3).distance_to(c) > STUCK_M:
				last_pos[dd.player_index] = [c, bm.fight_time]
			elif bm.fight_time - float(lp[1]) > stuck_max:
				stuck_max = bm.fight_time - float(lp[1])
				stuck_who = "%s в (%.1f, %.1f), %s" % [BrawlMatch.doll_name(dd), c.x, c.y, br.state if br != null else "-"]
			if dd.input_vec.length() >= 0.5 and _speed(dd) < 0.35:
				press_t[dd.player_index] = float(press_t.get(dd.player_index, 0.0)) + TICK
				if float(press_t[dd.player_index]) > press_max:
					press_max = float(press_t[dd.player_index])
					press_who = "%s в (%.1f, %.1f), %s" % [BrawlMatch.doll_name(dd), c.x, c.y, br.state if br != null else "-"]
			else:
				press_t.erase(dd.player_index)
		if trace and bm.fight_time - trace_t >= 10.0:
			trace_t = bm.fight_time
			var row := []
			for d in bm.dolls():
				var br := (d as Node).get_node_or_null("BrawlBrain") as BrawlBrain
				var cc := (d as Doll).centre_of_mass()
				row.append("%s:%s(%.0f,%.0f)%s" % [BrawlMatch.doll_name(d), br.state if br != null else "-", cc.x, cc.y, "" if (d as Doll).alive else "†"])
			print("  t=%6.1f раунд %d (%.0f с) счёт %s живых %d:%d  %s" % [bm.fight_time, bm.round_i, bm.round_time, str(bm.wins),
				bm.team_alive(0).size(), bm.team_alive(1).size(), " ".join(row)])
	var wall_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var wt := int(over_results.get("winner_team", -2))
	_check("bots_match_done", over_count == 1 and wt >= 0 and int(bm.wins[wt]) == wins_n and bm.fight_time <= max_s,
		"итогов %d, победили %s, счёт %s за %.0f с игры, раундов %d" % [over_count, str(wt), str(bm.wins), bm.fight_time, bm.rounds.size()])
	var decided := true
	var by_ko := 0
	for r in bm.rounds:
		decided = decided and (int(r["winner"]) >= 0)
		if String(r["reason"]) == "ko":
			by_ko += 1
	_check("bots_rounds_decided", decided and not bm.rounds.is_empty(), "раундов %d, нокаутом %d, по запасу %d: %s" % [bm.rounds.size(), by_ko, bm.rounds.size() - by_ko,
		str(bm.rounds.map(func(r: Dictionary) -> String: return "%d:%s/%s/%.0fс" % [int(r["round"]), str(r["winner"]), String(r["reason"]), float(r["t"])]))])
	var friendly_ko := 0
	for k in bm.kos:
		var a := int(k["attacker"])
		if a >= 0 and a % 2 == int(k["team"]):
			friendly_ko += 1
	_check("bots_no_friendly_ko", friendly_ko == 0 and float(acc["friendly_dmg"]) == 0.0, "нокаутов своих %d из %d, урон своим %.1f" % [friendly_ko, bm.kos.size(), float(acc["friendly_dmg"])])
	_check("bots_hits", int(acc["hits"]) > 30 and bm.kos.size() >= Tuning.BRAWL_PER_TEAM, "ударов %d, урон %.0f, нокаутов %d" % [int(acc["hits"]), float(acc["dmg"]), bm.kos.size()])
	_check("bots_not_stuck", stuck_max < STUCK_LIMIT_S and press_max < PRESS_LIMIT_S,
		"на месте дольше всех %.1f с (%s; предел %.0f); упёрся %.1f с (%s; предел %.0f)" % [stuck_max, stuck_who, STUCK_LIMIT_S, press_max, press_who, PRESS_LIMIT_S])
	_check("bots_in_bounds", out_of_bounds == 0, "тиков за границей арены %d" % out_of_bounds)
	var phys_ms := phys_sum / maxf(frames, 1.0)
	info["phys_ms"] = snappedf(phys_ms, 0.01)
	info["phys_ms_max"] = snappedf(phys_max, 0.01)
	_check("phys_ms_measured", frames > 0, "физика %.2f мс / тик (пик %.2f), 10 кукол%s" % [phys_ms, phys_max, "" if phys_ms <= PHYS_WARN_MS else " — ВЫШЕ %.0f мс (сообщить автору)" % PHYS_WARN_MS])
	var states := {}
	for d in bm.dolls():
		var br := (d as Node).get_node_or_null("BrawlBrain") as BrawlBrain
		if br != null:
			for k in br.counters:
				states[k] = int(states.get(k, 0)) + int(br.counters[k])
	info["bots"] = {"level": level, "wins_to_win": wins_n, "fight_s": snappedf(bm.fight_time, 0.1), "rounds": bm.rounds.duplicate(true),
		"wins": bm.wins.duplicate(), "kos": bm.kos.size(), "hits": acc["hits"], "damage": snappedf(float(acc["dmg"]), 0.1),
		"stuck_max_s": snappedf(stuck_max, 0.1), "press_max_s": snappedf(press_max, 0.1), "brain_counters_last_round": states,
		"ms_per_physics_frame_wall": snappedf(wall_ms / maxf(frames, 1), 0.01), "tally": over_results.get("tally", {})}
