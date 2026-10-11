## Проба хоккея (docs/plan-demo/HOCKEY.md) на настоящей площадке scenes/playground_sport_hockey.tscn (спорт-зал, двое, шайба,
## SportMatch с видом "hockey", SportHud).
##   rules (P2 — человек без ввода, P1 — человек с рукой мышью; шайбу ставит проба): шайба вместо мяча (мяч выключен), низкие ворота
##     видны и в физике одни, лёд на полу, числа матча (4:00, до 3); клюшка у обоих (P1 с рукой мышью — в Hand_R, P2 — в кисти со стороны атаки); вбрасывание — шайба с 2 м по
##     центру, ложится без подскока; удар 6 м/с — скользит ≥ 8 м без подскока; рука не хватает шайбу (ArmAssist.can_grab); гол только
##     через линию (над перекладиной и появление за линией — не гол); расстановка после гола (шайба на точке вбрасывания, куклы
##     заново у своих ворот, клюшки снова); нокаут — возврат через HOCKEY_KO_RESPAWN_S, не раньше, с новой клюшкой; до 3 → итоги;
##     заново; F (next_sport) — футбол без шайбы, клюшек и льда, и по кругу обратно в хоккей;
##   bots (HockeyBrain за обоих): матч доигрывается за ≤ 5 мин игрового времени, шайба не покидает зал, никто не застрял, куклы в зале;
##     физика на кадр (info.phys_ms).
## Обе секции: ошибок скриптов и ошибок движка — 0; ошибки загрузки ресурсов с диска (нет .ogg) — отдельно, info.errors_assets;
## ошибки пустышки рендера headless (servers/rendering/dummy, есть и в футболе без хоккея) — отдельно, info.errors_dummy_render.
## Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/hockey_probe.tscn -- "only=rules|bots|rules+bots,max_s=330,level=2,trace=1,out=<json>"
## → JSON между === HOCKEY PROBE === и === OK / FAIL ===, exit 0/1.
extends Node

const SCENE := "res://scenes/playground_sport_hockey.tscn"
const TICK := 1.0 / 60.0
const STUCK_M := 1.5
const STUCK_LIMIT_S := 25.0         # кукла не сдвинулась на STUCK_M столько игрового времени (розыгрыш, не пауза)


## Счётчик SCRIPT ERROR за прогон (как infection_probe): ошибка скрипта обрывает только свою функцию — проба могла бы молча
## потерять проверки. Загрузка ресурса с диска (нет исходника звука) — отдельно, пробу не валит.
class ScriptErrors extends Logger:
	var count := 0
	var first := ""
	var engine := 0
	var engine_first := ""
	var assets := 0
	var assets_first := ""
	## Пустышка рендера headless (servers/rendering/dummy): «Parameter "material" is null» на расстановке кукол — есть и в футболе с
	## ботами на ветке до хоккея (10.10, красная и до моих правок); к режиму не относится, считаем отдельно (info.errors_dummy_render).
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
var pg: Node
var sm: SportMatch
var puck: Puck
var over_results: Dictionary = {}
var over_winner: Doll = null
var over_count := 0
var errs := ScriptErrors.new()


func _check(id: String, cond: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": cond, "detail": str(detail)})
	if not cond:
		ok = false
	print("  %-30s %s  %s" % [id, "ok  " if cond else "FAIL", str(detail)])


func _args() -> Dictionary:
	var out := {"only": "", "max_s": "330", "level": "2", "trace": "0", "out": ""}
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
	print("=== HOCKEY PROBE ===")
	var a := _args()
	if _want(a, "rules"):
		await _rules()
	if _want(a, "bots"):
		await _bots(float(a["max_s"]), int(a["level"]), String(a["trace"]) == "1")
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

func _load(bots: bool, level := 2, countdown := 0.3, kickoff := 0.3) -> void:
	await _unload()
	Engine.time_scale = 1.0
	pg = (load(SCENE) as PackedScene).instantiate()
	sm = pg.get_node("Match") as SportMatch
	sm.feel_enabled = false
	sm.countdown_s = countdown
	sm.kickoff_s = kickoff
	pg.set("p2_bot", bots)
	pg.set("bot_level", level)
	over_results = {}
	over_winner = null
	over_count = 0
	sm.match_over.connect(func(w: Doll, r: Dictionary) -> void:
		over_winner = w
		over_results = r
		over_count += 1)
	add_child(pg)
	puck = pg.get_node("Puck") as Puck
	await _until(func() -> bool: return sm.play_state == "play", 6.0)


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


func _x(d: Doll) -> float:
	return d.centre_of_mass().x if d != null else NAN


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
	var st := HockeySticks.stick_of(d)
	if st != null:
		st.global_position += off
		st.linear_velocity = Vector3.ZERO
		st.angular_velocity = Vector3.ZERO


## Шайба в точку (на лёд, если y не задан) со скоростью; прошлый тик матча — там же (пересечения линии не было).
func _put_puck(pos: Vector2, vel := Vector2.ZERO) -> void:
	puck.freeze = false
	puck.global_transform = Transform3D(Basis.IDENTITY, Vector3(pos.x, pos.y, 0.0))
	puck.linear_velocity = Vector3(vel.x, vel.y, 0.0)
	puck.angular_velocity = Vector3.ZERO
	puck.untouched_s = 0.0
	puck.reset_physics_interpolation()
	sm._ball_prev = pos


func _ice_y() -> float:
	return Puck.rest_y() + 0.01


## Гол команды team ударом у линии: шайба в 0.3 м перед линией, 4 м/с в ворота.
func _slide_goal(team: int) -> bool:
	var before := int(sm.score[team])
	var s := 1.0 if team == 0 else -1.0
	var gx := float(Tuning.SPORTS["hockey"]["goal_x"])
	_put_puck(Vector2(s * (gx - 0.3), _ice_y()), Vector2(s * 4.0, 0.0))
	puck.last_touch = _doll(team)
	return await _until(func() -> bool: return int(sm.score[team]) == before + 1, 2.0)


func _sticks_ok() -> bool:
	for d in sm.dolls():
		var dd := d as Doll
		if dd.alive and HockeySticks.stick_of(dd) == null:
			return false
	return true


func _stick_hand(d: Doll) -> String:
	var wp := HockeySticks.pickup_of(d)
	if wp == null:
		return ""
	for hn in wp.held.keys():
		if (wp.held[hn]["weapon"] as Weapon).weapon_id == HockeySticks.STICK_ID:
			return String(hn)
	return ""


# ------------------------------------------------------------------ правила

func _rules() -> void:
	print("--- rules")
	await _load(false)
	var arena := pg.get_node("SportHall") as SportHallArena
	var ball := pg.get_node("Ball") as SportBall
	var p1 := _doll(0)
	var p2 := _doll(1)
	var r: Dictionary = Tuning.SPORTS["hockey"]
	_check("scene", sm.sport == "hockey" and sm.ball == puck and p1 != null and p2 != null and arena.sport == "hockey",
		"вид %s, снаряд %s" % [sm.sport, sm.ball.name if sm.ball != null else "-"])
	_check("ball_off", not ball.visible and ball.process_mode == Node.PROCESS_MODE_DISABLED and not ball.is_in_group(SportBall.GROUP)
		and puck.is_in_group(SportBall.GROUP) and puck.is_in_group("sport_cam") and not ball.is_in_group("sport_cam"),
		"мяч виден %s, в группе %s" % [ball.visible, ball.is_in_group(SportBall.GROUP)])
	var fx_ok := arena.get_node_or_null("Fixtures/hockey") != null
	for f in arena.get_node("Fixtures").get_children():
		var on := String(f.name) == "hockey"
		if (f as Node3D).visible != on or (f.process_mode == Node.PROCESS_MODE_DISABLED) == on:
			fx_ok = false
	_check("fixtures_hockey", fx_ok, "видны и в физике только ворота хоккея")
	var cross := arena.get_node_or_null("Fixtures/hockey/Crossbar_R") as Node3D
	_check("goal_low", cross != null and absf(cross.global_position.y - Tuning.HOCKEY_GOAL_H) < 0.1 and is_equal_approx(float(r["goal_h"]), Tuning.HOCKEY_GOAL_H),
		"перекладина y=%.2f" % (cross.global_position.y if cross != null else -1.0))
	var fb := arena.get_node("Floor/FloorBody") as StaticBody3D
	_check("ice", HockeyRink.is_ice(arena) and fb.physics_material_override != null and is_equal_approx(fb.physics_material_override.friction, Tuning.HOCKEY_ICE_FRICTION),
		"трение пола %s" % (fb.physics_material_override.friction if fb.physics_material_override != null else "нет"))
	_check("puck_body", is_equal_approx(puck.mass, 0.5) and is_equal_approx(puck.physics_material_override.friction, 0.02)
		and puck.angular_damp >= 5.0 and puck.axis_lock_angular_z and puck.axis_lock_linear_z and puck.is_in_group(Puck.PUCK_GROUP),
		"масса %.2f, трение %.2f, угл. дамп %.1f" % [puck.mass, puck.physics_material_override.friction, puck.angular_damp])
	_check("numbers", is_equal_approx(sm.time_limit_s, Tuning.HOCKEY_TIME_S) and sm.goals_to_win == 3
		and sm.hard_timeout_s <= 300.0 + 0.01 and is_equal_approx(sm.ko_respawn_s(), 3.0),
		"время %.0f с (+золотой до %.0f), до %d" % [sm.time_limit_s, sm.hard_timeout_s, sm.goals_to_win])
	# клюшки у обоих: P1 (рука мышью) — Hand_R, P2 (атакует влево) — Hand_R
	await _until(_sticks_ok, 2.0)
	_check("sticks_start", _sticks_ok() and _stick_hand(p1) == Tuning.HOCKEY_STICK_HAND and _stick_hand(p2) == "Hand_R"
		and sm.sticks != null and sm.sticks.given == 2, "P1 %s, P2 %s, выдано %d" % [_stick_hand(p1), _stick_hand(p2), sm.sticks.given if sm.sticks != null else -1])
	# вбрасывание: шайба падает с 2 м по центру и ложится без подскока
	var spawn := arena.ball_spawn(0)
	_check("faceoff_spot", spawn.distance_to(Vector3(0.0, 2.0, 0.0)) < 0.01, str(spawn))
	var landed := await _until(func() -> bool: return puck.global_position.y < Puck.rest_y() + 0.03, 3.0)
	var top := puck.global_position.y
	for i in 60:
		await get_tree().physics_frame
		top = maxf(top, puck.global_position.y)
	_check("faceoff_no_bounce", landed and top < Puck.rest_y() + 0.06 and absf(puck.global_position.x) < 0.6,
		"после касания льда макс. y %.3f (лежит %.3f), x %.2f, подскоков погашено %d" % [top, Puck.rest_y(), puck.global_position.x, puck.hops_killed])
	# рука не хватает шайбу
	var arm := p1.get_node_or_null("ArmAssist") as ArmAssist
	var probe_body := RigidBody3D.new()
	pg.add_child(probe_body)
	var cs := CollisionShape3D.new()
	cs.shape = BoxShape3D.new()
	probe_body.add_child(cs)
	probe_body.global_position = Vector3(0.0, 3.0, 0.0)
	_check("arm_no_grab", arm != null and not arm.can_grab(puck) and arm.can_grab(probe_body) and puck.has_meta(&"no_grab"),
		"рука %s, шайба %s, контрольный ящик %s" % [arm != null, arm.can_grab(puck) if arm != null else null, arm.can_grab(probe_body) if arm != null else null])
	probe_body.queue_free()
	# скольжение: удар 6 м/с от левой стены вправо, куклы за шайбой у левой стены
	_place(p1, Vector2(-10.2, 1.0))
	_place(p2, Vector2(-10.2, 3.0))
	var x0 := -8.0
	_put_puck(Vector2(x0, _ice_y()), Vector2(6.0, 0.0))
	puck.max_y_seen = puck.global_position.y
	var stop_x := float(r["goal_x"]) - 0.4
	var t := 0.0
	while t < 6.0 and puck.global_position.x < stop_x and not (t > 0.3 and puck.linear_velocity.length() < 0.2):
		await get_tree().physics_frame
		t += TICK
	var dist := puck.global_position.x - x0
	var hop := puck.max_y_seen - Puck.rest_y()
	info["slide"] = {"dist_m": snappedf(dist, 0.01), "t_s": snappedf(t, 0.01), "v_end": snappedf(puck.linear_velocity.length(), 0.01), "hop_m": snappedf(hop, 0.001)}
	_check("slide_8m", dist >= 8.0, "прошла %.1f м за %.1f с, скорость в конце %.1f м/с" % [dist, t, puck.linear_velocity.length()])
	_check("slide_no_hop", hop < 0.05, "выше лёжки на %.3f м" % hop)
	# гол только через линию: та же шайба доезжает до линии справа → гол команде 0
	var crossed := await _until(func() -> bool: return int(sm.score[0]) == 1, 3.0)
	_check("goal_through_line", crossed and sm.score == [1, 0] and sm.play_state == "goal", "счёт %s, состояние %s" % [sm.score, sm.play_state])
	var hud_l: Label = (pg.get_node("SportHud") as SportHud).labels[0]
	_check("hud_score", hud_l.text == "1" and arena.score == [1, 0], "HUD «%s», табло %s" % [hud_l.text, arena.score])
	# расстановка после гола
	var old_p1 := _doll(0)
	var got_kick := await _until(func() -> bool: return sm.play_state == "kickoff", Tuning.SPORT_GOAL_PAUSE_S + 1.0)
	p1 = _doll(0)
	p2 = _doll(1)
	_check("reset_after_goal", got_kick and puck.freeze and puck.global_position.distance_to(arena.ball_spawn(sm.serve_team)) < 0.05
		and sm.phase == Match.Phase.COUNTDOWN and p1 != old_p1 and absf(_x(p1) + Tuning.SPORT_SPAWN_X) < 1.0 and absf(_x(p2) - Tuning.SPORT_SPAWN_X) < 1.0,
		"шайба %s, P1 x=%.1f, P2 x=%.1f" % [puck.global_position, _x(p1), _x(p2)])
	await _until(func() -> bool: return sm.play_state == "play", 3.0)
	await _until(_sticks_ok, 2.0)
	_check("sticks_after_goal", _sticks_ok() and sm.sticks.given >= 4, "выдано %d" % sm.sticks.given)
	# не гол: над перекладиной в сторону ворот, и шайба «появилась» за линией без пересечения
	var gx := float(r["goal_x"])
	_put_puck(Vector2(gx - 0.6, Tuning.HOCKEY_GOAL_H + 0.45), Vector2(5.0, 0.0))
	puck.last_touch = _doll(0)
	await _wait(1.5)
	var over_bar := sm.score == [1, 0]
	_put_puck(Vector2(gx + 0.9, _ice_y()))
	await _wait(0.8)
	var inside := sm.score == [1, 0]
	_check("no_goal_over_bar", over_bar, "счёт %s" % [sm.score])
	_check("no_goal_without_line", inside, "шайба за линией без пересечения: счёт %s" % [sm.score])
	_put_puck(Vector2(0.0, _ice_y()))
	await _wait(0.2)
	# нокаут: возврат через 3 с (не раньше), с клюшкой
	p2 = _doll(1)
	var given0 := sm.sticks.given
	p2.knock_out()
	await _wait(Tuning.HOCKEY_KO_RESPAWN_S - 0.4)
	var early := _doll(1) == p2
	_check("ko_not_over", sm.phase != Match.Phase.OVER and over_count == 0 and early and not p2.alive, "до %.1f с — ещё лежит: %s" % [Tuning.HOCKEY_KO_RESPAWN_S - 0.4, early])
	await _wait(0.9)
	var p2n := _doll(1)
	_check("ko_respawn", p2n != null and p2n != p2 and p2n.alive and p2n.control_enabled and absf(_x(p2n) - Tuning.SPORT_SPAWN_X) < 1.5,
		"P2 x=%.1f, жив %s" % [_x(p2n), p2n.alive if p2n != null else false])
	await _until(_sticks_ok, 2.0)
	_check("ko_new_stick", HockeySticks.stick_of(p2n) != null and sm.sticks.given > given0, "выдано %d → %d" % [given0, sm.sticks.given])
	# до 3 → итоги
	await _slide_goal(0)
	await _until(func() -> bool: return sm.play_state == "play", Tuning.SPORT_GOAL_PAUSE_S + 3.0)
	await _slide_goal(0)
	await _until(func() -> bool: return sm.phase == Match.Phase.OVER, Tuning.SPORT_GOAL_PAUSE_S + 1.0)
	var w_idx := over_winner.player_index if over_winner != null and is_instance_valid(over_winner) else -1
	_check("match_to_3", sm.phase == Match.Phase.OVER and over_count == 1 and w_idx == 0 and over_results.get("score", []) == [3, 0]
		and String(over_results.get("reason", "")) == "goals" and String(over_results.get("sport", "")) == "hockey",
		"победитель P%d, счёт %s, причина %s" % [w_idx + 1, over_results.get("score", []), over_results.get("reason", "")])
	# заново
	await _wait(0.6)
	sm.restart()
	await _until(func() -> bool: return sm.play_state == "play", 3.0)
	_check("restart", sm.score == [0, 0] and sm.play_state == "play" and sm.ball == puck, "счёт %s" % [sm.score])
	# F: следующий вид — футбол без шайбы, клюшек и льда; по кругу — снова хоккей
	_check("order", Tuning.SPORT_ORDER.has("hockey"), str(Tuning.SPORT_ORDER))
	sm.next_sport()
	await _until(func() -> bool: return sm.play_state == "play", 3.0)
	await _wait(0.3)
	var sticks_left := 0
	for w in get_tree().get_nodes_in_group(Weapon.GROUP):
		if (w as Weapon).weapon_id == HockeySticks.STICK_ID and not (w as Node).is_queued_for_deletion():
			sticks_left += 1
	_check("f_to_football", sm.sport == "football" and sm.ball == ball and ball.visible and not puck.visible and sm.sticks == null and sticks_left == 0
		and not HockeyRink.is_ice(arena) and is_equal_approx(sm.time_limit_s, Tuning.SPORT_TIME_LIMIT_S) and _doll(0).get_node_or_null("ArmAssist") == null,
		"вид %s, клюшек %d, лёд %s, время %.0f" % [sm.sport, sticks_left, HockeyRink.is_ice(arena), sm.time_limit_s])
	for i in 3:
		sm.next_sport()
	await _until(func() -> bool: return sm.play_state == "play", 3.0)
	await _until(_sticks_ok, 2.0)
	_check("f_back_to_hockey", sm.sport == "hockey" and sm.ball == puck and puck.visible and not ball.visible and _sticks_ok() and HockeyRink.is_ice(arena)
		and _doll(0).get_node_or_null("ArmAssist") != null, "вид %s" % sm.sport)


# ------------------------------------------------------------------ боты

func _bots(max_s: float, level: int, trace: bool) -> void:
	print("--- bots (уровень %d)" % level)
	await _load(true, level, 0.5, Tuning.SPORT_KICKOFF_S)
	var p1 := _doll(0)
	SportBrain.default_level = level
	var b := HockeyBrain.new()
	b.name = "SportBrain"
	p1.add_child(b)
	p1.external_input = true
	pg.call("_sync_arm")   # P1 — бот: рука мышью снимается, как у площадки
	HockeySticks.pickup_of(p1).drop_all()   # клюшка — заново в кисть со стороны атаки (у бота — Hand_L)
	var brain2 := _doll(1).get_node_or_null("SportBrain")
	_check("bots_brains", brain2 is HockeyBrain and (brain2 as HockeyBrain).level == level, str(brain2))
	var bounds := (pg.get_node("SportHall") as SportHallArena).bounds()
	var half := Tuning.SPORT_FIELD_HALF_W + 0.6
	var t := 0.0
	var escaped := 0
	var out_dolls := 0
	var kos := 0
	var touches0 := puck.touches
	sm.ko.connect(func(_v: Doll, _a: Node, _r: Dictionary) -> void: kos += 1)
	var anchor := {}       # player_index → [точка, с игры на месте]
	var stuck_max := 0.0
	var stuck_who := ""
	var phys_sum := 0.0
	var phys_max := 0.0
	var phys_n := 0
	var tick_sum := 0.0      # время тика по часам (физика + скрипты + пустышка рендера), мс
	var tick_n := 0
	var tick_prev := Time.get_ticks_usec()
	var top := 0.0
	while sm.phase != Match.Phase.OVER and t < max_s:
		await get_tree().physics_frame
		t += TICK
		var ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		var now := Time.get_ticks_usec()
		if t > 10.0:   # монитор обновляется редко и первые секунды держит кадр загрузки сцены
			phys_sum += ms
			phys_max = maxf(phys_max, ms)
			phys_n += 1
			tick_sum += float(now - tick_prev) / 1000.0
			tick_n += 1
		tick_prev = now
		var p := puck.pos2()
		if is_nan(p.x) or absf(p.x) > half or p.y < -0.6 or p.y > Tuning.SPORT_FIELD_H + 0.6:
			escaped += 1
		if not puck.freeze:
			top = maxf(top, p.y)
		for d in sm.dolls():
			var dd := d as Doll
			if not dd.alive:
				anchor.erase(dd.player_index)
				continue
			var c := dd.centre_of_mass()
			if not bounds.grow(0.5).has_point(c):
				out_dolls += 1
			if sm.play_state != "play":
				anchor.erase(dd.player_index)
				continue
			var a: Array = anchor.get(dd.player_index, [c, 0.0])
			if (a[0] as Vector3).distance_to(c) > STUCK_M:
				a = [c, 0.0]
			else:
				a[1] = float(a[1]) + TICK
				if float(a[1]) > stuck_max:
					stuck_max = float(a[1])
					stuck_who = "P%d у (%.1f, %.1f), состояние %s" % [dd.player_index + 1, c.x, c.y,
						(dd.get_node_or_null("SportBrain") as SportBrain).state if dd.get_node_or_null("SportBrain") != null else "-"]
			anchor[dd.player_index] = a
		if trace and int(t / TICK) % 60 == 0:
			var line := "    t=%5.1f %s шайба (%5.1f, %4.2f) v=%4.1f счёт %s физика %.1f мс" % [t, sm.play_state, p.x, p.y, puck.linear_velocity.length(), sm.score, ms]
			for d in sm.dolls():
				var br := (d as Doll).get_node_or_null("SportBrain") as SportBrain
				var c := (d as Doll).centre_of_mass()
				line += "  P%d %s (%5.1f, %4.1f)" % [(d as Doll).player_index + 1, br.state if br != null else "-", c.x, c.y]
			print(line)
	info["bots"] = {"level": level, "sim_s": snappedf(t, 0.1), "clock_s": snappedf(sm.fight_time, 0.1), "score": sm.score.duplicate(),
		"goals": sm.goals.duplicate(true), "reason": String(over_results.get("reason", "")), "touches": puck.touches - touches0,
		"rescues": sm.ball_rescues, "kos": kos, "escaped_ticks": escaped, "dolls_out_ticks": out_dolls, "puck_top_y": snappedf(top, 0.01),
		"stuck_max_s": snappedf(stuck_max, 0.1), "stuck_who": stuck_who, "sticks_given": sm.sticks.given if sm.sticks != null else -1}
	info["phys_ms"] = {"avg": snappedf(phys_sum / maxf(1.0, phys_n), 0.01), "max": snappedf(phys_max, 0.01),
		"tick_wall_avg": snappedf(tick_sum / maxf(1.0, tick_n), 0.01)}
	_check("bots_match_ends", sm.phase == Match.Phase.OVER and sm.fight_time <= 300.0 + 0.5,
		"за %.0f с игры (%.0f с всего), счёт %s, причина «%s»" % [sm.fight_time, t, sm.score, info["bots"]["reason"]])
	_check("bots_puck_in_hall", escaped == 0, "тиков вне зала: %d, выше всего %.1f м" % [escaped, top])
	_check("bots_dolls_in_hall", out_dolls == 0, "тиков кукол вне зала: %d" % out_dolls)
	_check("bots_not_stuck", stuck_max < STUCK_LIMIT_S, "дольше всех на месте %.1f с: %s" % [stuck_max, stuck_who])
	_check("bots_touch_puck", puck.touches - touches0 >= 10, "касаний %d, голов %d, нокаутов %d" % [puck.touches - touches0, int(sm.score[0]) + int(sm.score[1]), kos])
