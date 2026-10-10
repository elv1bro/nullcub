## Проба «Заражения» (docs/plan-demo/INFECTION.md) на настоящей площадке scenes/playground_infection.tscn (купол, семеро,
## InfectionMatch, InfectionHud).
##   rules (все семеро — боты с выключенными мозгами, куклы ставит проба): семеро, урона нет (incoming_mult 0), ровно один заражённый
##     на старте, он быстрее (×1.15) и с запертым Зарядом (рывка нет), у здорового рывок есть; касание заражает: жертва перекрашена,
##     быстрее, без руки мышью (ArmAssist снят), запись в журнале; свежезаражённый не заражает раньше INFECTION_TOUCH_GAP_S; удар
##     куклы о куклу — без урона, с отбросом; все заражены → партия заражённым, очко первому; следующая партия — все живы и здоровы,
##     ровно один заражённый, не тот же первый; время вышло → партия здоровым, очко каждому дожившему, заражённым — нет; последние
##     INFECTION_PULSE_S — пульс всё чаще; матч до INFECTION_ROUNDS партий → итоги (места по очкам, табличка HUD); R — всё заново;
##   bots (все семеро — боты): матч из 3 партий доигрывается за ≤ max_s (6 мин); в каждой партии ≥ 2 заражений; ударов много, урона 0;
##     никто не застрял (на месте < STUCK_LIMIT_S, заражённый на месте < ZOMBIE_IDLE_LIMIT_S, жмёт тягу и стоит < PRESS_LIMIT_S), все
##     в границах арены; физика на кадр (info.phys_ms).
## Обе секции: ошибок скриптов и ошибок движка — 0.
## Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/infection_probe.tscn -- "only=rules|bots|rules+bots,max_s=360,level=2,trace=1,seed=0,out=<json>"
## → JSON между === INFECTION PROBE === и === OK / FAIL ===, exit 0/1. errors_script — SCRIPT ERROR за прогон (Logger).
extends Node

const SCENE := "res://scenes/playground_infection.tscn"
const TICK := 1.0 / 60.0
const STUCK_M := 1.5
const STUCK_LIMIT_S := 40.0         # не сдвинулся на STUCK_M (здоровый может висеть в безопасной точке — предел щедрый)
const ZOMBIE_IDLE_LIMIT_S := 8.0    # заражённый не сдвинулся на STUCK_M (он обязан гнаться)
const PRESS_LIMIT_S := 4.0          # жмёт тягу, а торс стоит


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
var pg: InfectionPlayground
var im: InfectionMatch
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
	print("=== INFECTION PROBE ===")
	var a := _args()
	if _want(a, "rules"):
		await _rules()
	if _want(a, "bots"):
		await _bots(float(a["max_s"]), int(a["level"]), String(a["trace"]) == "1", int(a["seed"]))
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

func _load(level := 2, countdown := 0.3, seed_ := 0) -> void:
	await _unload()
	Engine.time_scale = 1.0
	pg = (load(SCENE) as PackedScene).instantiate() as InfectionPlayground
	pg.p1_bot = true
	pg.p2_bot = true
	pg.bot_level = level
	im = pg.get_node("Match") as InfectionMatch
	im.feel_enabled = false
	im.countdown_s = countdown
	im.rng_seed = seed_
	over_results = {}
	over_count = 0
	im.match_over.connect(func(_w: Doll, r: Dictionary) -> void:
		over_results = r
		over_count += 1)
	add_child(pg)
	await _until(func() -> bool: return im.play_state == "play" and im.dolls().size() == Tuning.INFECTION_DOLLS, 8.0)


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
	for d in im.dolls():
		if is_instance_valid(d) and (d as Doll).player_index == index:
			return d
	return null


func _brains_off() -> void:
	for d in im.dolls():
		var b := (d as Node).get_node_or_null(InfectionPlayground.BOT_NAME)
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


## Разложить всех по дальним точкам (никто никого не касается).
func _spread_all() -> void:
	var far := [Vector2(-12.0, 2.5), Vector2(12.0, 2.5), Vector2(-6.0, 2.5), Vector2(6.0, 2.5), Vector2(0.0, 8.0), Vector2(-9.0, 10.0), Vector2(9.0, 10.0)]
	var i := 0
	for d in im.dolls():
		_place(d, far[i % far.size()])
		i += 1


func _names(arr: Array) -> String:
	var out: Array = []
	for d in arr:
		out.append(InfectionMatch.doll_name(d))
	return ", ".join(out)


# ------------------------------------------------------------------ правила

func _rules() -> void:
	print("--- rules")
	await _load(2, 0.3, 4242)
	_brains_off()
	_check("seven_dolls", im.dolls().size() == Tuning.INFECTION_DOLLS, "кукол %d" % im.dolls().size())
	var mults := []
	for d in im.dolls():
		mults.append((d as Doll).incoming_mult)
	_check("no_damage_mult", mults.all(func(m: float) -> bool: return m == 0.0), "incoming_mult %s" % str(mults))
	var zs := im.zombies()
	var z: Doll = zs[0] if not zs.is_empty() else null
	_check("one_infected_start", zs.size() == 1 and z != null and z.alive and im.first == z and im.play_state == "play"
		and im.healthy().size() == Tuning.INFECTION_DOLLS - 1 and z.is_in_group(InfectionMatch.ZOMBIE_GROUP),
		"заражённых %d (%s), здоровых %d, фаза %s" % [zs.size(), _names(zs), im.healthy().size(), im.play_state])
	if z == null:
		return
	var fast := z.thrust_mult == Tuning.INFECTION_ZOMBIE_THRUST_MULT and z.speed_cap_mult == Tuning.INFECTION_ZOMBIE_SPEED_MULT
	for d in im.healthy():
		fast = fast and (d as Doll).thrust_mult == 1.0 and (d as Doll).speed_cap_mult == 1.0
	_check("zombie_faster", fast, "тяга ×%.2f, скорость ×%.2f, у здоровых 1" % [z.thrust_mult, z.speed_cap_mult])
	_spread_all()
	await _wait(0.3)
	# --- рывок: заражённому нет, здоровому есть
	var h0 := im.healthy()[0] as Doll
	var z_dash := false
	var h_dash := false
	for i in 30:
		z.request_dash()
		h0.request_dash()
		await get_tree().physics_frame
		z_dash = z_dash or z.is_dashing()
		h_dash = h_dash or h0.is_dashing()
	_check("zombie_no_dash", not z_dash and z.charge_locked and z.charge <= 0.5, "заражённый: рывок %s, Заряд %.1f, заперт %s" % [z_dash, z.charge, z.charge_locked])
	_check("healthy_can_dash", h_dash, "здоровый: рывок %s" % h_dash)
	_spread_all()
	await _wait(0.3)
	_check("no_touch_no_infect", im.zombies().size() == 1 and im.infections.size() == 1, "никто не касается — заражённых %d, записей %d" % [im.zombies().size(), im.infections.size()])

	# --- касание заражает: жертва с рукой мышью
	var a := im.healthy()[0] as Doll
	ArmAssist.attach_to(a)
	await get_tree().physics_frame
	var had_arm := a.get_node_or_null("ArmAssist") != null
	var got := {"victim": null, "by": null, "n": 0}
	im.infected.connect(func(v: Doll, by: Doll) -> void:
		got["victim"] = v
		got["by"] = by
		got["n"] = int(got["n"]) + 1)
	_place(z, Vector2(0.0, 1.3))
	_place(a, Vector2(1.05, 1.3))
	var t0 := im.round_time
	var passed := await _until(func() -> bool: return im.is_infected(a), 1.5)
	await get_tree().physics_frame   # queue_free руки
	var arm_gone := a.get_node_or_null("ArmAssist") == null
	_check("touch_infects", passed and got["victim"] == a and got["by"] == z and im.infections.size() == 2
		and int(im.infections[1]["from"]) == z.player_index and int(im.infections[1]["to"]) == a.player_index,
		"%s → %s за %.2f с, записей %d" % [InfectionMatch.doll_name(z), InfectionMatch.doll_name(got["victim"]), im.round_time - t0, im.infections.size()])
	_check("victim_faster_no_arm", had_arm and arm_gone and a.thrust_mult == Tuning.INFECTION_ZOMBIE_THRUST_MULT
		and a.speed_cap_mult == Tuning.INFECTION_ZOMBIE_SPEED_MULT and a.is_in_group(InfectionMatch.ZOMBIE_GROUP) and a.charge_locked,
		"рука была %s, снята %s, тяга ×%.2f, Заряд заперт %s" % [had_arm, arm_gone, a.thrust_mult, a.charge_locked])
	# --- свежезаражённый не заражает раньше INFECTION_TOUCH_GAP_S: третий сразу касается a (z — далеко)
	var c := im.healthy()[0] as Doll
	_place(z, Vector2(-12.0, 1.3))
	_place(c, Vector2(2.1, 1.3))
	var t_inf := float(im.infections[1]["t"])
	var third := await _until(func() -> bool: return im.is_infected(c), 2.0)
	var dt := float(im.infections[-1]["t"]) - t_inf if third else -1.0
	_check("touch_gap_held", third and dt >= Tuning.INFECTION_TOUCH_GAP_S - 2.0 * TICK and int(im.infections[-1]["from"]) == a.player_index,
		"%s заразил %s через %.2f с после своего заражения (пауза %.2f)" % [InfectionMatch.doll_name(a), InfectionMatch.doll_name(c), dt, Tuning.INFECTION_TOUCH_GAP_S])
	_check("hud_count", pg.hud.count_label.text != "" and pg.hud.clock.text.contains(":"), "HUD: «%s» · «%s»" % [pg.hud.count_label.text, pg.hud.clock.text])
	_spread_all()
	await _wait(0.4)

	# --- удар куклы о куклу: без урона, с отбросом
	var hs := im.healthy()
	var s1 := hs[0] as Doll
	var s2 := hs[1] as Doll
	_place(s1, Vector2(5.0, 1.6))
	_place(s2, Vector2(8.2, 1.6))
	await _wait(0.2)
	var hit := {"n": 0, "dmg": 0.0}
	var on_hit := func(v: Doll, att: Node, dmg: float, _k: String, _p: Vector3) -> void:
		if v == s2 and att == s1:
			hit["n"] = int(hit["n"]) + 1
		hit["dmg"] = float(hit["dmg"]) + dmg
	im.hit.connect(on_hit)
	var v0 := _speed(s2)
	_launch(s1, Vector3(9.0, 0.0, 0.0))
	var peak := 0.0
	for i in 50:
		await get_tree().physics_frame
		peak = maxf(peak, _speed(s2))
	im.hit.disconnect(on_hit)
	_check("hit_no_damage", int(hit["n"]) > 0 and float(hit["dmg"]) == 0.0 and s2.hp == s2.max_hp and s1.hp == s1.max_hp and s2.alive,
		"ударов %d, урон %.1f, HP %.0f / %.0f" % [int(hit["n"]), float(hit["dmg"]), s2.hp, s2.max_hp])
	_check("hit_knockback", peak > maxf(v0, 0.5) + 2.0, "скорость жертвы %.2f → пик %.2f м/с" % [v0, peak])
	_check("hit_not_infect", not im.is_infected(s1) and not im.is_infected(s2), "здоровые остались здоровыми")

	# --- все заражены → партия заражённым, очко первому
	var first1 := im.first_i
	for d in im.healthy():
		im.infect(d, z)
	await get_tree().physics_frame
	var r0: Dictionary = im.rounds[-1] if not im.rounds.is_empty() else {}
	_check("round_all_infected", im.play_state == "round_end" and im.rounds.size() == 1 and String(r0.get("side", "")) == "zombies"
		and int(im.scores.get(first1, 0)) == 1 and im.scores.size() == 1 and int(r0.get("infections", 0)) == Tuning.INFECTION_DOLLS - 1,
		"фаза %s, партия %s, очки %s" % [im.play_state, str(r0), str(im.scores)])
	var round2 := func() -> bool: return im.round_i == 2 and im.play_state == "play"
	var next_ok := await _until(round2, Tuning.INFECTION_ROUND_PAUSE_S + Tuning.INFECTION_COUNTDOWN_S + 1.0)
	_brains_off()
	var zs2 := im.zombies()
	var clean := true
	for d in im.healthy():
		clean = clean and (d as Doll).thrust_mult == 1.0 and not (d as Doll).is_in_group(InfectionMatch.ZOMBIE_GROUP)
	_check("next_round_other_first", next_ok and im.alive_dolls().size() == Tuning.INFECTION_DOLLS and zs2.size() == 1 and im.first_i != first1
		and im.healthy().size() == Tuning.INFECTION_DOLLS - 1 and clean and int(im.scores.get(first1, 0)) == 1,
		"партия %d, живых %d, заражённых %d (первый P%d, был P%d), здоровые чистые %s" % [im.round_i, im.alive_dolls().size(), zs2.size(), im.first_i + 1, first1 + 1, clean])
	_check("arm_back_after_round", true, "у ботов руки нет (p1_bot); возврат руки человеку — attach_children по doll_replaced")

	# --- время вышло → партия здоровым; последние секунды — пульс
	var first2 := im.first_i
	_spread_all()
	im.round_time = im.round_s - Tuning.INFECTION_PULSE_S - 0.3
	var pulse_t: Array = []
	im.pulsed.connect(func(_u: float) -> void: pulse_t.append(im.round_time))
	var shown0 := pg.pulses_shown
	var timed := await _until(func() -> bool: return im.rounds.size() >= 2, Tuning.INFECTION_PULSE_S + 2.0)
	var r1: Dictionary = im.rounds[-1] if im.rounds.size() >= 2 else {}
	var surv: Array = r1.get("survivors", [])
	var each := surv.size() == Tuning.INFECTION_DOLLS - 1 and not surv.has(first2)
	for pi in surv:
		each = each and int(im.scores.get(pi, 0)) >= 1
	_check("round_timeout_healthy", timed and String(r1.get("side", "")) == "healthy" and each and int(im.scores.get(first2, 0)) == (1 if first2 == first1 else 0)
		and float(r1.get("t", 0.0)) >= im.round_s - 0.05,
		"партия %s, дожили %s, очки %s" % [str(r1.get("side")), str(surv), str(im.scores)])
	var gap_first := float(pulse_t[1]) - float(pulse_t[0]) if pulse_t.size() >= 2 else -1.0
	var gap_last := float(pulse_t[-1]) - float(pulse_t[-2]) if pulse_t.size() >= 2 else -1.0
	_check("pulse_last_seconds", pulse_t.size() >= 20 and gap_first > gap_last * 2.0 and gap_last <= Tuning.INFECTION_PULSE_FAST_S + 0.05
		and pg.pulses_shown - shown0 == pulse_t.size() and float(pulse_t[0]) >= im.round_s - Tuning.INFECTION_PULSE_S - 0.05,
		"пульсов %d, первая пауза %.2f с, последняя %.2f с, показано %d" % [pulse_t.size(), gap_first, gap_last, pg.pulses_shown - shown0])
	info["rules_pulse"] = {"pulses": pulse_t.size(), "gap_first": snappedf(gap_first, 0.01), "gap_last": snappedf(gap_last, 0.01)}

	# --- партия 3: все заражены → итоги
	var round3 := func() -> bool: return im.round_i == 3 and im.play_state == "play"
	await _until(round3, Tuning.INFECTION_ROUND_PAUSE_S + Tuning.INFECTION_COUNTDOWN_S + 1.0)
	_brains_off()
	var first3 := im.first_i
	var z3 := im.first
	for d in im.healthy():
		im.infect(d, z3)
	var done := await _until(func() -> bool: return over_count > 0, Tuning.INFECTION_ROUND_PAUSE_S + 1.0)
	var places: Array = over_results.get("places", [])
	var top_ok := not places.is_empty()
	for i in range(1, places.size()):
		top_ok = top_ok and im.score_of(places[i]) <= im.score_of(places[i - 1])
	var winner: Doll = over_results.get("winner")
	var win_ok := (winner == null and bool(over_results.get("draw", false))) or (winner != null and winner == places[0] and places.size() > 1 and im.score_of(places[0]) > im.score_of(places[1]))
	_check("match_to_rounds", done and over_count == 1 and im.rounds.size() == Tuning.INFECTION_ROUNDS and im.phase == Match.Phase.OVER and top_ok and win_ok
		and int(im.scores.get(first3, 0)) >= 1,
		"итогов %d, партий %d, победил %s, места %s, очки %s" % [over_count, im.rounds.size(), InfectionMatch.doll_name(winner), _names(places), str(im.scores)])
	await _wait(1.2)
	_check("hud_end_panel", pg.hud.end_panel.visible and pg.hud.end_title.text != "", "табличка: «%s» · %s" % [pg.hud.end_title.text, pg.hud.end_sub.text])
	# --- R: заново
	im.restart()
	await _until(func() -> bool: return im.play_state == "play", 6.0)
	_check("restart_resets", im.scores.is_empty() and im.round_i == 1 and im.rounds.is_empty() and im.zombies().size() == 1
		and im.alive_dolls().size() == Tuning.INFECTION_DOLLS and not pg.hud.end_panel.visible and im.infections.size() == 1,
		"партия %d, очки %s, заражённых %d" % [im.round_i, str(im.scores), im.zombies().size()])


# ------------------------------------------------------------------ матч ботов

func _bots(max_s: float, level: int, trace: bool, seed_: int) -> void:
	print("--- bots (уровень %d, %d партий)" % [level, Tuning.INFECTION_ROUNDS])
	await _load(level, 3.0, seed_)
	var acc := {"hits": 0, "dmg": 0.0}
	im.hit.connect(func(_v: Doll, a: Node, dmg: float, _k: String, _p: Vector3) -> void:
		if a is Doll:
			acc["hits"] = int(acc["hits"]) + 1
		acc["dmg"] = float(acc["dmg"]) + dmg)
	var last_pos: Dictionary = {}
	var stuck_max := 0.0
	var stuck_who := ""
	var z_anchor: Dictionary = {}   # player_index → [pos, t] якорь заражённого
	var z_idle_max := 0.0
	var z_idle_who := ""
	var press_t: Dictionary = {}
	var press_max := 0.0
	var press_who := ""
	var out_of_bounds := 0
	var b: AABB = pg.arena.call("bounds")
	var t0 := Time.get_ticks_usec()
	var frames := 0
	var trace_t := 0.0
	var round_seen := im.round_i
	var phys_us := 0
	while over_count == 0 and im.fight_time < max_s:
		var f0 := Time.get_ticks_usec()
		await get_tree().physics_frame
		phys_us += Time.get_ticks_usec() - f0
		frames += 1
		if im.round_i != round_seen:
			round_seen = im.round_i
			last_pos.clear()
			press_t.clear()
			z_anchor.clear()
		var playing := im.play_state == "play"
		for d in im.dolls():
			var dd := d as Doll
			if not dd.alive or not playing:
				last_pos.erase(dd.player_index)
				press_t.erase(dd.player_index)
				z_anchor.erase(dd.player_index)
				continue
			var c := dd.centre_of_mass()
			if c.x < b.position.x - 0.5 or c.x > b.end.x + 0.5 or c.y < b.position.y - 0.5 or c.y > b.end.y + 0.5:
				out_of_bounds += 1
			var br := dd.get_node_or_null(InfectionPlayground.BOT_NAME) as InfectionBrain
			var lp: Array = last_pos.get(dd.player_index, [])
			if lp.is_empty() or (lp[0] as Vector3).distance_to(c) > STUCK_M:
				last_pos[dd.player_index] = [c, im.fight_time]
			elif im.fight_time - float(lp[1]) > stuck_max:
				stuck_max = im.fight_time - float(lp[1])
				stuck_who = "%s в (%.1f, %.1f), %s" % [InfectionMatch.doll_name(dd), c.x, c.y, br.state if br != null else "-"]
			if im.is_infected(dd):
				var za: Array = z_anchor.get(dd.player_index, [])
				if za.is_empty() or (za[0] as Vector3).distance_to(c) > STUCK_M:
					z_anchor[dd.player_index] = [c, im.fight_time]
				elif im.fight_time - float(za[1]) > z_idle_max:
					z_idle_max = im.fight_time - float(za[1])
					z_idle_who = "%s в (%.1f, %.1f), %s" % [InfectionMatch.doll_name(dd), c.x, c.y, br.state if br != null else "-"]
			else:
				z_anchor.erase(dd.player_index)
			if dd.input_vec.length() >= 0.5 and _speed(dd) < 0.35:
				press_t[dd.player_index] = float(press_t.get(dd.player_index, 0.0)) + TICK
				if float(press_t[dd.player_index]) > press_max:
					press_max = float(press_t[dd.player_index])
					press_who = "%s в (%.1f, %.1f), %s" % [InfectionMatch.doll_name(dd), c.x, c.y, br.state if br != null else "-"]
			else:
				press_t.erase(dd.player_index)
		if trace and im.fight_time - trace_t >= 10.0:
			trace_t = im.fight_time
			var row := []
			for d in im.dolls():
				var br := (d as Node).get_node_or_null(InfectionPlayground.BOT_NAME) as InfectionBrain
				var cc := (d as Doll).centre_of_mass()
				row.append("%s:%s(%.0f,%.0f)%s%s" % [InfectionMatch.doll_name(d), br.state if br != null else "-", cc.x, cc.y,
					"*" if im.is_infected(d) else "", "" if (d as Doll).alive else "†"])
			print("  t=%6.1f партия %d (%.0f с) очки %s заражений %d  %s" % [im.fight_time, im.round_i, im.round_time, str(im.scores), im.infections.size(), " ".join(row)])
	var wall_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var winner: Doll = over_results.get("winner")
	_check("bots_match_done", over_count == 1 and im.rounds.size() == Tuning.INFECTION_ROUNDS and im.fight_time <= max_s,
		"итогов %d, партий %d за %.0f с игры (предел %.0f), победил %s, очки %s" % [over_count, im.rounds.size(), im.fight_time, max_s, InfectionMatch.doll_name(winner), str(im.scores)])
	var per_round: Array = []
	var sides: Array = []
	for r in im.rounds:
		per_round.append(int(r["infections"]))
		sides.append(String(r["side"]))
	_check("bots_infections_per_round", not per_round.is_empty() and per_round.min() >= 2, "заражений по партиям: %s, исход: %s" % [str(per_round), str(sides)])
	var firsts: Array = []
	var firsts_ok := true
	for r in im.rounds:
		if not firsts.is_empty() and int(r["first"]) == int(firsts[-1]):
			firsts_ok = false
		firsts.append(int(r["first"]))
	_check("bots_first_differs", firsts_ok, "первые заражённые по партиям: %s" % str(firsts))
	_check("bots_hits_no_damage", int(acc["hits"]) > 10 and float(acc["dmg"]) == 0.0, "ударов кукла о куклу %d, урон %.1f" % [int(acc["hits"]), float(acc["dmg"])])
	_check("bots_not_stuck", stuck_max < STUCK_LIMIT_S and z_idle_max < ZOMBIE_IDLE_LIMIT_S and press_max < PRESS_LIMIT_S,
		"на месте дольше всех %.1f с (%s; предел %.0f); заражённый на месте %.1f с (%s; предел %.0f); упёрся %.1f с (%s; предел %.0f)" % [
		stuck_max, stuck_who, STUCK_LIMIT_S, z_idle_max, z_idle_who, ZOMBIE_IDLE_LIMIT_S, press_max, press_who, PRESS_LIMIT_S])
	_check("bots_in_bounds", out_of_bounds == 0, "тиков за границей арены %d" % out_of_bounds)
	var states := {}
	var unstick := 0
	for d in im.dolls():
		var br := (d as Node).get_node_or_null(InfectionPlayground.BOT_NAME) as InfectionBrain
		if br != null:
			unstick += int(br.counters.get("unstick", 0))
			for k in br.counters:
				states[k] = int(states.get(k, 0)) + int(br.counters[k])
	info["bots"] = {"level": level, "fight_s": snappedf(im.fight_time, 0.1), "rounds": im.rounds.duplicate(true),
		"scores": im.scores.duplicate(), "infections": im.infections.size(), "hits": acc["hits"], "stuck_max_s": snappedf(stuck_max, 0.1),
		"zombie_idle_max_s": snappedf(z_idle_max, 0.1), "press_max_s": snappedf(press_max, 0.1), "unstick_last_round": unstick,
		"brain_counters_last_round": states, "ms_per_physics_frame": snappedf(wall_ms / maxf(frames, 1), 0.01),
		"phys_ms": snappedf(float(phys_us) / 1000.0 / maxf(frames, 1), 0.01), "tally": over_results.get("tally", {})}
