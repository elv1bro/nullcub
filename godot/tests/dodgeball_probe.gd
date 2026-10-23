## Проба «Вышибал 3 на 3» (docs/plan-demo/DODGEBALL.md) на настоящей площадке scenes/playground_dodgeball.tscn (спорт-зал, стенка по
## черте, четыре мяча, шесть кукол с ArmAssist, DodgeballMatch, DodgeballBrain, DodgeballHud).
##   rules (P1 — бот, мозги выключены — бросает и ловит сама проба настоящей рукой ArmAssist): шесть кукол, по три в командах, мячи
##     приняты; стенка держит куклу и пропускает мяч; мёртвый мяч берёт только своя половина; бросок рукой — мяч «живой», попал в
##     чужого быстро — тот выбит (и через OUT_FADE_S на скамейке), медленный — нет; мяч коснулся пола — мёртвый, потом не выбивает;
##     поймал рукой — выбит бросивший, к ловцу вернулся выбитый свой; команда без кукол на поле — раунд сопернику, пауза и новый раунд
##     (все шестеро, мячи на вводе); вторая победа — итоги (табличка HUD); тосты «ВЫБИТ …» и «ПОЙМАЛ!», кружки команд; R — заново;
##   bots: матч шести ботов уровня level доигрывается до победителя за 1–6 минут игры, броски / попадания есть, ловля бывает (ур. 2),
##     все в границах зала, никто не перелез через черту.
## Обе секции: ошибок скриптов (errors_script) и движка (errors_engine) — 0; ресурсы, не загрузившиеся с диска, — в info.errors_assets;
## ошибки пустышки рендера headless (servers/rendering/dummy, известные, есть и в футболе / хоккее) — в info.errors_dummy_render.
## Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/dodgeball_probe.tscn -- "only=rules|bots,level=2,trace=1,out=<json>"
## → JSON между === DODGEBALL PROBE === и === OK / FAIL ===, exit 0/1. Без only — обе секции. Без --fixed-fps тоже работает (дольше).
extends Node

const SCENE := "res://scenes/playground_dodgeball.tscn"
const TICK := 1.0 / 60.0
const BOTS_MIN_S := 60.0
const BOTS_MAX_S := 360.0
const HALL_X := 11.5

class ScriptErrors extends Logger:
	var count := 0
	var first := ""
	var engine := 0
	var engine_first := ""
	var assets := 0
	var assets_first := ""
	## Пустышка рендера headless (servers/rendering/dummy): «Parameter "material" is null» в material_get_instance_shader_parameters —
	## известная, есть в футболе и хоккее (hockey_probe, release-004); к режиму не относится — отдельно, info.errors_dummy_render.
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
		elif error_type == ERROR_TYPE_ERROR and file.begins_with("servers/rendering/dummy"):
			dummy += 1
			if dummy_first == "":
				dummy_first = "%s (%s:%d %s)" % [code, file, line, function]
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
var pg: DodgeballPlayground
var dm: DodgeballMatch
var over_results: Dictionary = {}
var over_count := 0
var errs := ScriptErrors.new()


func _check(id: String, cond: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": cond, "detail": str(detail)})
	if not cond:
		ok = false
	print("  %-30s %s  %s" % [id, "ok  " if cond else "FAIL", str(detail)])


func _args() -> Dictionary:
	var out := {"only": "", "level": "2", "trace": "0", "out": ""}
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
	print("=== DODGEBALL PROBE ===")
	var a := _args()
	if _want(a, "rules"):
		await _rules()
	if _want(a, "bots"):
		await _bots(int(a["level"]), String(a["trace"]) == "1")
	await _unload()
	_check("errors_script", errs.count == 0, "ошибок скриптов %d; первая: %s" % [errs.count, errs.first])
	_check("errors_engine", errs.engine == 0, "ошибок движка %d; первая: %s" % [errs.engine, errs.engine_first])
	info["errors_assets"] = {"count": errs.assets, "first": errs.assets_first}
	info["errors_dummy_render"] = {"count": errs.dummy, "first": errs.dummy_first}
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

func _load(level := 2, countdown := 0.3) -> void:
	await _unload()
	Engine.time_scale = 1.0
	pg = (load(SCENE) as PackedScene).instantiate() as DodgeballPlayground
	pg.p1_bot = true
	pg.p2_human = false
	pg.bot_level = level
	dm = pg.get_node("Match") as DodgeballMatch
	dm.feel_enabled = false
	dm.countdown_s = countdown
	over_results = {}
	over_count = 0
	dm.match_over.connect(func(_w: Doll, r: Dictionary) -> void:
		over_results = r
		over_count += 1)
	add_child(pg)
	await _until(func() -> bool: return dm.play_state == "play" and dm.dolls().size() == Tuning.DODGEBALL_TEAM * 2, 10.0)


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
	for d in dm.dolls():
		if is_instance_valid(d) and (d as Doll).player_index == index:
			return d
	return null


func _brain(d: Doll) -> DodgeballBrain:
	return d.get_node_or_null(DodgeballPlayground.BRAIN) as DodgeballBrain if d != null else null


func _brains_off() -> void:
	for d in dm.dolls():
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


## Все куклы на поле — к местам: синие x −3 / −6 / −9, красные +3 / +6 / +9, в воздухе на 1.2 м.
func _park() -> void:
	for d in dm.dolls():
		var dd := d as Doll
		if not dm.in_play(dd):
			continue
		var slot := dd.player_index / 2
		_place(dd, Vector2(DodgeballMatch.home_dir(DodgeballMatch.team_of(dd)) * (3.0 + 3.0 * slot), 1.2))


func _ball(i: int) -> SportBall:
	var bs := dm.balls()
	bs.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
	return bs[i] as SportBall


## Мяч в точку p со скоростью v (вне руки, отпущен).
func _shoot(b: SportBall, p: Vector3, v: Vector3) -> void:
	b.freeze = false
	b.global_position = Vector3(p.x, p.y, 0.0)
	b.linear_velocity = v
	b.angular_velocity = Vector3.ZERO
	b.reset_physics_interpolation()


## Настоящий бросок рукой: мяч в кисть куклы d, рука к точке aim, через 0.25 с release("toggle"). true — мяч стал «живым».
func _throw(d: Doll, b: SportBall, aim: Vector3) -> bool:
	var arm := DodgeballMatch.arm_of(d)
	arm.set_target_override(aim)
	await _wait(0.2)
	_shoot(b, arm.grip_global(), Vector3.ZERO)
	await get_tree().physics_frame
	_shoot(b, arm.grip_global(), Vector3.ZERO)
	var got := arm.grab(b)
	await _wait(0.25)
	if not got or not arm.is_holding():
		arm.clear_target_override()
		return false
	arm.release("toggle")
	arm.clear_target_override()
	await get_tree().physics_frame
	await get_tree().physics_frame
	return dm.ball_is(b, "live")


func _max_part_x(d: Doll) -> float:
	var m := -INF
	for p in d.parts.values():
		m = maxf(m, (p as Node3D).global_position.x)
	return m


func _toasted(key: String) -> bool:
	var want := tr(key).split("%")[0].strip_edges()
	for t in pg.hud.toasts:
		if String(t).contains(want):
			return true
	return false


# ------------------------------------------------------------------ правила

func _rules() -> void:
	print("--- rules")
	await _load(2, 0.3)
	_brains_off()
	dm.round_rules = false
	_park()
	await _wait(0.3)
	var n := dm.dolls().size()
	var groups_ok := true
	for d in dm.dolls():
		var dd := d as Doll
		var t := DodgeballMatch.team_of(dd)
		groups_ok = groups_ok and dd.team == DodgeballMatch.TEAM_PREFIX + str(t) and DodgeballMatch.arm_of(dd) != null \
			and signf(Tuning.DODGEBALL_SPAWN[dd.player_index].x) == DodgeballMatch.home_dir(t) and dd.is_in_group(DodgeballMatch.team_group(t))
	var adopted := 0
	for b in dm.balls():
		if dm.ball_is(b, "dead") and not (b as SportBall).has_meta(&"no_grab") and not (b as SportBall).freeze:
			adopted += 1
	_check("six_dolls_four_balls", n == 6 and dm.team_dolls(0).size() == 3 and dm.team_dolls(1).size() == 3 and groups_ok
		and adopted == Tuning.DODGEBALL_BALLS and dm.play_state == "play",
		"кукол %d (синих %d, красных %d), команды / руки / стороны %s, мячей принято и отпущено %d, фаза %s" % [n, dm.team_dolls(0).size(),
			dm.team_dolls(1).size(), str(groups_ok), adopted, dm.play_state])
	# --- стенка: кукла не проходит, мяч проходит
	var p1 := _doll(0)
	_place(p1, Vector2(-1.2, 2.0))
	var mx := -INF
	for k in int(1.5 / TICK):
		p1.input_vec = Vector2(1.0, 0.0)
		await get_tree().physics_frame
		mx = maxf(mx, _max_part_x(p1))
	p1.input_vec = Vector2.ZERO
	var b0 := _ball(0)
	_shoot(b0, Vector3(-2.5, 3.0, 0.0), Vector3(8.0, 0.0, 0.0))
	await _wait(0.6)
	var bx := b0.global_position.x
	_check("line_blocks_dolls_not_balls", mx < 0.25 and bx > 1.5,
		"кукла жмёт в черту 1.5 с: дальняя деталь x %.2f (предел 0.25); мяч через черту: x %.2f" % [mx, bx])
	# --- мёртвый мяч: своя половина
	_park()
	_shoot(b0, Vector3(-3.0, 0.42, 0.0), Vector3.ZERO)
	await _wait(0.3)
	var p2 := _doll(1)
	var a1 := DodgeballMatch.arm_of(p1)
	var a2 := DodgeballMatch.arm_of(p2)
	_check("dead_ball_own_half", String(b0.get_meta(&"grab_team", "")) == "dodge_0" and a1.can_grab(b0) and not a2.can_grab(b0),
		"мяч x %.1f: grab_team %s, синий берёт %s, красный %s" % [b0.global_position.x, str(b0.get_meta(&"grab_team", "")),
			str(a1.can_grab(b0)), str(a2.can_grab(b0))])
	# --- бросок рукой → живой; попал в чужого быстро → выбит
	_park()
	await _wait(0.2)
	var p4 := _doll(3)
	var live := await _throw(p1, b0, p4.centre_of_mass())
	var throws1 := int(dm.tally[0]["throws"])
	var tp := p4.torso().global_position
	_shoot(b0, tp + Vector3(-1.2, 0.0, 0.0), Vector3(9.0, 0.0, 0.0))
	var hit := await _until(func() -> bool: return dm.out.has(p4), 1.0)
	var ev_out: Dictionary = {}
	for e in dm.events:
		if String(e["kind"]) == "out" and int(e["who"]) == 3:
			ev_out = e
	_check("throw_live_hit_out", live and throws1 == 1 and hit and String(ev_out.get("how", "")) == "hit" and int(ev_out.get("by", -1)) == 0
		and int(dm.tally[0]["hits"]) == 1 and int(dm.tally[3]["outs"]) == 1 and not dm.in_play(p4) and not dm.ball_is(b0, "live"),
		"бросок живой %s (бросков %d), выбит %s: %s, попаданий P1 %d" % [str(live), throws1, str(hit), str(ev_out), int(dm.tally[0]["hits"])])
	await _wait(Tuning.DODGEBALL_OUT_FADE_S + 0.2)
	_check("out_benched", is_instance_valid(p4) and not p4.visible and p4.process_mode == Node.PROCESS_MODE_DISABLED
		and not p4.is_in_group(DodgeballMatch.CAM_GROUP) and dm.on_court(1) == 2,
		"через %.1f с выбитый невидим %s, вне физики %s, на поле красных %d" % [Tuning.DODGEBALL_OUT_FADE_S + 0.2, str(not p4.visible),
			str(p4.process_mode == Node.PROCESS_MODE_DISABLED), dm.on_court(1)])
	# --- медленный мяч не выбивает
	var p6 := _doll(5)
	var b1 := _ball(1)
	_park()
	await _wait(0.2)
	var live_slow := await _throw(_doll(2), b1, p6.centre_of_mass())
	tp = p6.torso().global_position
	_shoot(b1, tp + Vector3(-0.9, 0.0, 0.0), Vector3(Tuning.DODGEBALL_HIT_SPEED * 0.6, 0.0, 0.0))
	await _wait(0.6)
	_check("slow_ball_no_out", live_slow and dm.in_play(p6) and not dm.ball_is(b1, "live"),
		"бросок живой %s, мяч %.1f м/с в P6: на поле %s, мяч %s (%s)" % [str(live_slow), Tuning.DODGEBALL_HIT_SPEED * 0.6, str(dm.in_play(p6)),
			str(dm.ball_info(b1).get("state")), str(dm.ball_info(b1).get("why"))])
	# --- касание пола: мяч мёртвый, потом не выбивает
	_park()
	await _wait(0.2)
	var live_floor := await _throw(p1, b1, p2.centre_of_mass())
	_shoot(b1, Vector3(1.3, 1.6, 0.0), Vector3(0.0, -8.0, 0.0))
	var dead_floor := await _until(func() -> bool: return dm.ball_is(b1, "dead"), 1.0)
	var why_floor := String(dm.ball_info(b1).get("why", ""))
	tp = p2.torso().global_position
	_shoot(b1, tp + Vector3(-1.2, 0.0, 0.0), Vector3(9.0, 0.0, 0.0))
	await _wait(0.5)
	_check("floor_kills_ball", live_floor and dead_floor and why_floor == "floor" and dm.in_play(p2),
		"бросок живой %s → пол: мёртвый %s (%s); потом 9 м/с в P2 — P2 на поле %s" % [str(live_floor), str(dead_floor), why_floor,
			str(dm.in_play(p2))])
	# --- поймал: выбит бросивший, к ловцу вернулся выбитый свой (P4)
	_park()
	await _wait(0.2)
	var p3 := _doll(2)
	_place(p2, Vector2(4.0, 2.0))
	a2.set_target_override(Vector3(2.6, 2.0, 0.0))
	var live_c := await _throw(p3, b1, p2.centre_of_mass())
	var grip := a2.grip_global()
	_shoot(b1, grip + Vector3(-1.4, 0.0, 0.0), Vector3(8.0, 0.0, 0.0))
	var got := await _until(func() -> bool: return dm.out.has(p3) or dm.out.has(p2), 1.0)
	a2.clear_target_override()
	var back := _doll(3)
	_check("catch_returns_mate", live_c and got and dm.out.has(p3) and not dm.out.has(p2) and int(dm.tally[1]["catches"]) == 1
		and back != null and back != p4 and dm.in_play(back) and back.visible and dm.on_court(1) == 3 and a2.is_holding(),
		"бросок P3 живой %s; P2 поймал %d, P3 выбит %s, P2 на поле %s; P4 снова в игре %s, красных на поле %d" % [str(live_c),
			int(dm.tally[1]["catches"]), str(dm.out.has(p3)), str(not dm.out.has(p2)), str(back != null and dm.in_play(back)), dm.on_court(1)])
	if a2.is_holding():
		a2.release("drop")
	_check("hud_toasts", _toasted("ВЫБИТ %s") and _toasted("ПОЙМАЛ!") and pg.hud.caption.text != "",
		"тосты: %s" % str(pg.hud.toasts))
	# --- команда без кукол на поле — раунд сопернику, новый раунд — все шестеро
	dm.round_rules = true
	for d in dm.team_dolls(0, true):
		dm.knock_out(d, null, "probe")
	var r1 := dm.score == [0, 1] and dm.play_state == "round_over" and dm.rounds.size() == 1
	await get_tree().process_frame
	var dots_out := pg.hud.dots_on
	var replay := await _until(func() -> bool: return dm.play_state == "play",
		Tuning.DODGEBALL_ROUND_PAUSE_S + Tuning.DODGEBALL_RESET_COUNTDOWN_S + 1.0)
	var spots_ok := true
	for b in dm.balls():
		spots_ok = spots_ok and dm.ball_is(b, "dead") and (b as SportBall).global_position.y < 1.0
	_check("team_out_round", r1 and replay and dm.round_n == 2 and dm.on_court(0) == 3 and dm.on_court(1) == 3 and dm.out.is_empty() and spots_ok
		and dots_out == 3,
		"счёт %s, раунд %d, на поле %d : %d, мячи на вводе %s, кружков «на поле» после раунда %d (ждали 3)" % [str(dm.score), dm.round_n,
			dm.on_court(0), dm.on_court(1), str(spots_ok), dots_out])
	# --- вторая победа — итоги
	_brains_off()
	for d in dm.team_dolls(0, true):
		dm.knock_out(d, null, "probe")
	var over := await _until(func() -> bool: return over_count > 0, Tuning.DODGEBALL_ROUND_PAUSE_S + 1.0)
	await _wait(1.0)
	_check("two_rounds_results", over and dm.score == [0, 2] and dm.play_state == "over" and int(over_results.get("winner_team", -1)) == 1
		and over_results.get("tally", {}).size() == 6 and (over_results.get("places", []) as Array).size() == 6 and pg.hud.end_panel.visible
		and pg.hud.end_table.get_child_count() == 4 * 7,
		"итоги %s, счёт %s, победа команды %d, строк таблицы %d, табличка %s" % [str(over), str(dm.score),
			int(over_results.get("winner_team", -1)), pg.hud.end_table.get_child_count() / 4, str(pg.hud.end_panel.visible)])
	# --- R — всё заново
	dm.restart()
	var again := await _until(func() -> bool: return dm.play_state == "play", 5.0)
	_check("restart", again and dm.score == [0, 0] and dm.round_n == 1 and dm.on_court(0) == 3 and dm.on_court(1) == 3 and over_count == 1
		and not pg.hud.end_panel.visible,
		"фаза %s, счёт %s, раунд %d, на поле %d : %d" % [dm.play_state, str(dm.score), dm.round_n, dm.on_court(0), dm.on_court(1)])


# ------------------------------------------------------------------ боты

func _bots(level: int, trace: bool) -> void:
	print("--- bots (level %d)" % level)
	DodgeballBrain.total = {"throws": 0, "grabs": 0, "dodges": 0, "catch_tries": 0}
	await _load(level, Tuning.COUNTDOWN_S)
	var t := 0.0
	var out_of_hall := 0
	var crossed := 0
	var crossed_first := ""
	var next_trace := 0.0
	while over_count == 0 and t < BOTS_MAX_S + 30.0:
		await get_tree().physics_frame
		t += TICK
		if dm.play_state != "play":
			continue
		for d in dm.dolls():
			var dd := d as Doll
			if not dm.in_play(dd):
				continue
			var c := dd.centre_of_mass()
			if absf(c.x) > HALL_X or c.y < -0.5 or c.y > 10.5:
				out_of_hall += 1
			if c.x * DodgeballMatch.home_dir(DodgeballMatch.team_of(dd)) < -0.4:
				crossed += 1
				if crossed_first == "":
					crossed_first = "%s x %.2f t %.1f" % [dd.name, c.x, t]
		if trace and t >= next_trace:
			next_trace = t + 5.0
			var states: Array = []
			for d in dm.dolls():
				var b := _brain(d)
				states.append("%s:%s%s" % [(d as Node).name, b.state if b != null else "-", "" if dm.in_play(d) else "(out)"])
			print("    t=%5.1f раунд %d счёт %s на поле %d:%d  %s" % [t, dm.round_n, str(dm.score), dm.on_court(0), dm.on_court(1), " ".join(states)])
	var hits := 0
	var catches := 0
	var throws := 0
	for k in dm.tally:
		hits += int(dm.tally[k]["hits"])
		catches += int(dm.tally[k]["catches"])
		throws += int(dm.tally[k]["throws"])
	var why := {}
	for e in dm.events:
		if String(e["kind"]) == "dead":
			why[e["why"]] = int(why.get(e["why"], 0)) + 1
	info["bots"] = {"level": level, "match_s": snappedf(dm.fight_time, 0.1), "score": dm.score, "rounds": dm.rounds, "throws": throws,
		"hits": hits, "catches": catches, "brain_total": DodgeballBrain.total, "dead_why": why, "outs": dm.events.filter(
			func(e: Dictionary) -> bool: return String(e["kind"]) == "out").size()}
	var wt := int(over_results.get("winner_team", -1))
	_check("bots_match_finishes", over_count == 1 and wt >= 0 and dm.fight_time >= BOTS_MIN_S and dm.fight_time <= BOTS_MAX_S,
		"итоги %d, победа команды %d, счёт %s, матч %.0f с (окно %d–%d)" % [over_count, wt, str(dm.score), dm.fight_time, int(BOTS_MIN_S),
			int(BOTS_MAX_S)])
	_check("bots_throw_and_hit", throws >= 10 and hits >= 2 and hits + catches >= 4,   # выбивают и попаданием, и ловлей
		"бросков %d, попаданий %d, поймано %d, мёртвые мячи %s" % [throws, hits, catches, str(why)])
	_check("bots_in_hall_own_half", out_of_hall == 0 and crossed == 0,
		"вне зала тиков %d, за чертой тиков %d (первый: %s)" % [out_of_hall, crossed, crossed_first])
