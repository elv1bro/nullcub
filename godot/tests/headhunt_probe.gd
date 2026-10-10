## Проба «Охоты за головами» (docs/plan-demo/HEADHUNT.md) на настоящей площадке scenes/playground_headhunt.tscn (Полигон, шесть кукол,
## HeadhuntMatch, HeadCarry, HeadBasket, HeadhuntBrain, HeadhuntHud).
##   rules (все шесть — боты с выключенными мозгами, куклы ставит проба): шесть кукол, по три в двух командах (синие — чётный
##     player_index слева, красные — справа), свои не ранят, две корзины у баз; KO оставляет голову (RigidBody3D в группе heads, meta
##     owner_team); выбитый возвращается через HEADHUNT_RESPAWN_S на своей стороне, голова лежит; подбор касанием (дальше
##     HEADHUNT_PICK_M — нет, вплотную — да; сразу после KO — запрет HEADHUNT_DROP_LOCK_S), тяга × HEADHUNT_CARRY_THRUST за голову;
##     своя голова в своей корзине — без очка (возвращена), чужая — +1; носитель выбит — головы рассыпаются; на спине не больше
##     HEADHUNT_CARRY_MAX; до HEADHUNT_SCORE_TO_WIN → итоги (победившая команда, табличка HUD); R (restart) — всё заново;
##   bots (все шесть — боты): матч ботов кончается за ≤ HEADHUNT_TIME_S игрового времени, очков суммарно ≥ MIN_POINTS, никто не
##     застрял (на месте < STUCK_LIMIT_S, жмёт тягу и стоит < PRESS_LIMIT_S), все в границах арены; info.phys_ms — физика за тик.
## Обе секции: ошибок скриптов (errors_script) и движка (errors_engine) — 0; ресурсы, не загрузившиеся с диска (нет .ogg в git), —
## отдельно в info.errors_assets (не режим, пробу не валят).
## Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/headhunt_probe.tscn -- "only=rules|bots|rules+bots,level=2,trace=1,out=<json>"
## → JSON между === HEADHUNT PROBE === и === OK / FAIL ===, exit 0/1.
extends Node

const SCENE := "res://scenes/playground_headhunt.tscn"
const TICK := 1.0 / 60.0
const STUCK_M := 1.5
const STUCK_LIMIT_S := 30.0
const PRESS_LIMIT_S := 4.0
const MIN_POINTS := 3
const PHYS_WARN_MS := 6.0

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
var pg: HeadhuntPlayground
var hm: HeadhuntMatch
var over_results: Dictionary = {}
var over_count := 0
var errs := ScriptErrors.new()


func _check(id: String, cond: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": cond, "detail": str(detail)})
	if not cond:
		ok = false
	print("  %-30s %s  %s" % [id, "ok  " if cond else "FAIL", str(detail)])


func _args() -> Dictionary:
	var out := {"only": "", "max_s": str(Tuning.HEADHUNT_TIME_S + 5.0), "level": "2", "trace": "0", "out": ""}
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
	print("=== HEADHUNT PROBE ===")
	var a := _args()
	if _want(a, "rules"):
		await _rules()
	if _want(a, "bots"):
		await _bots(float(a["max_s"]), int(a["level"]), String(a["trace"]) == "1")
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

func _load(level := 2, countdown := 0.3) -> void:
	await _unload()
	Engine.time_scale = 1.0
	pg = (load(SCENE) as PackedScene).instantiate() as HeadhuntPlayground
	pg.p1_bot = true
	pg.p2_human = false
	pg.bot_level = level
	hm = pg.get_node("Match") as HeadhuntMatch
	hm.feel_enabled = false
	hm.countdown_s = countdown
	over_results = {}
	over_count = 0
	hm.match_over.connect(func(_w: Doll, r: Dictionary) -> void:
		over_results = r
		over_count += 1)
	add_child(pg)
	await _until(func() -> bool: return hm.play_state == "play" and hm.dolls().size() == Tuning.HEADHUNT_TEAM * 2, 10.0)


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
	for d in hm.dolls():
		if is_instance_valid(d) and (d as Doll).player_index == index:
			return d
	return null


func _brains_off() -> void:
	for d in hm.dolls():
		var b := (d as Node).get_node_or_null("HeadhuntBrain")
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


## Голова — в точку p, неподвижно.
func _put_head(h: RigidBody3D, p: Vector2) -> void:
	h.global_position = Vector3(p.x, p.y, 0.0)
	h.linear_velocity = Vector3.ZERO
	h.angular_velocity = Vector3.ZERO
	h.reset_physics_interpolation()


## Расставить всех по своим базам высоко (никто ни с кем не сталкивается), кроме except.
func _park(except: Array) -> void:
	for d in hm.dolls():
		if except.has(d) or not (d as Doll).alive:
			continue
		var dd := d as Doll
		var x := (-20.0 - 2.5 * float(dd.player_index / 2)) if HeadhuntMatch.team_of(dd) == 0 else (20.0 + 2.5 * float(dd.player_index / 2))
		_place(dd, Vector2(x, 11.0))


## Выбить куклу i и дождаться её головы на полу; возвращает голову или null.
func _ko(i: int) -> RigidBody3D:
	var d := _doll(i)
	var before := hm.carry.extracted
	d.knock_out()
	await _until(func() -> bool: return hm.carry.extracted > before, 0.5)
	for h in hm.carry.all_heads():
		if int((h as Node).get_meta("owner_index", -1)) == i and not (h as Node).has_meta("carrier"):
			return h
	return null


## Кукла d касается головы h: торс прямо в голову, ждать подбора (не дольше s).
func _touch(d: Doll, h: RigidBody3D, s := 0.5) -> bool:
	var hp := h.global_position
	_place(d, Vector2(hp.x, hp.y))
	return await _until(func() -> bool: return h.has_meta("carrier") and h.get_meta("carrier") == d, s)


## Носитель d касается своей корзины.
func _to_basket(d: Doll) -> void:
	var bp := hm.basket_of(HeadhuntMatch.team_of(d)).point()
	_place(d, Vector2(bp.x, bp.y + 0.2))


func _min_part_dist(d: Doll, p: Vector3) -> float:
	var best := INF
	for b in d.parts.values():
		best = minf(best, (b as Node3D).global_position.distance_to(p))
	return best


# ------------------------------------------------------------------ правила

func _rules() -> void:
	print("--- rules")
	await _load(2, 0.3)
	_brains_off()
	_park([])
	var n := hm.dolls().size()
	var blue := hm.team_alive(0)
	var red := hm.team_alive(1)
	var groups_ok := true
	for d in hm.dolls():
		var dd := d as Doll
		var t := HeadhuntMatch.team_of(dd)
		groups_ok = groups_ok and dd.team == "headhunt_%d" % t and dd.is_in_group(HeadhuntMatch.team_group(t)) \
			and not dd.is_in_group(HeadhuntMatch.team_group(1 - t)) and dd.team_damage_mult == 0.0
	_check("six_dolls_two_teams", n == 6 and blue.size() == 3 and red.size() == 3 and groups_ok and hm.play_state == "play",
		"кукол %d, синих %d, красных %d, Doll.team / группы / свои не ранят: %s" % [n, blue.size(), red.size(), str(groups_ok)])
	var b0 := hm.basket_of(0)
	var b1 := hm.basket_of(1)
	_check("baskets", b0 != null and b1 != null and b0.point().x < -25.0 and b1.point().x > 25.0,
		"корзины: синяя x %.1f, красная x %.1f" % [b0.point().x if b0 else 0.0, b1.point().x if b1 else 0.0])
	# --- KO оставляет голову
	var p2 := _doll(1)
	var ko_t := hm.fight_time
	var rh := await _ko(1)
	_check("ko_leaves_head", rh != null and rh is RigidBody3D and rh.is_in_group("heads") and HeadCarry.owner_team(rh) == 1
		and rh.get_parent() != p2 and not p2.parts.has("Head"),
		"голова: %s, группа heads, owner_team %d" % [str(rh), HeadCarry.owner_team(rh)])
	_check("head_drop_lock", rh != null and not hm.carry.pickable(rh), "сразу после KO брать нельзя %.1f с" % Tuning.HEADHUNT_DROP_LOCK_S)
	_put_head(rh, Vector2(0.0, 1.0))
	# --- возрождение через 4 с на своей стороне, голова лежит
	var back := await _until(func() -> bool:
		var d := _doll(1)
		return d != null and d.alive, Tuning.HEADHUNT_RESPAWN_S + 1.0)
	var dt := hm.fight_time - ko_t
	var np2 := _doll(1)
	_check("respawn_4s", back and absf(dt - Tuning.HEADHUNT_RESPAWN_S) < 0.15 and np2.centre_of_mass().x > 15.0
		and is_instance_valid(rh) and hm.carry.loose().has(rh),
		"вернулся через %.2f с (ждём %.1f), x %.1f, голова лежит: %s" % [dt, Tuning.HEADHUNT_RESPAWN_S, np2.centre_of_mass().x, str(hm.carry.loose().has(rh))])
	_brains_off()
	_park([])
	# --- подбор касанием: далеко — нет, вплотную — да
	var p1 := _doll(0)
	_put_head(rh, Vector2(0.0, 1.0))
	_place(p1, Vector2(3.0, 1.2))
	await _wait(0.05)
	var far := _min_part_dist(p1, rh.global_position)
	var not_far := hm.carry.carry_count(p1) == 0 and far > Tuning.HEADHUNT_PICK_M
	var picked := await _touch(p1, rh)
	_check("pick_by_touch", not_far and picked and hm.carry.carry_count(p1) == 1 and is_equal_approx(p1.thrust_mult, Tuning.HEADHUNT_CARRY_THRUST),
		"в %.1f м — не взял: %s; касанием — взял: %s, на спине %d, тяга ×%.2f" % [far, str(not_far), str(picked), hm.carry.carry_count(p1), p1.thrust_mult])
	# --- своя голова в своей корзине — без очка
	var bh := await _ko(2)   # синий P3
	_park([p1])
	await _wait(Tuning.HEADHUNT_DROP_LOCK_S + 0.1)
	_put_head(bh, Vector2(-3.0, 1.0))
	var p5 := _doll(4)
	var picked_own := await _touch(p5, bh)
	var s0: Array = hm.score.duplicate()
	_to_basket(p5)
	await _until(func() -> bool: return hm.carry.carry_count(p5) == 0, 0.5)
	var last: Dictionary = hm.deliveries[-1] if not hm.deliveries.is_empty() else {}
	_check("own_head_no_point", picked_own and hm.carry.carry_count(p5) == 0 and int(hm.score[0]) == int(s0[0]) and int(last.get("returned", 0)) == 1
		and int(last.get("scored", -1)) == 0 and not is_instance_valid(bh),
		"своя голова: взял %s, счёт %s → %s, сдача %s" % [str(picked_own), str(s0), str(hm.score), str(last)])
	# --- чужая +1
	_to_basket(p1)
	await _until(func() -> bool: return hm.carry.carry_count(p1) == 0, 0.5)
	last = hm.deliveries[-1] if not hm.deliveries.is_empty() else {}
	_check("enemy_head_point", int(hm.score[0]) == int(s0[0]) + 1 and int(hm.score[1]) == int(s0[1]) and int(last.get("scored", 0)) == 1
		and is_equal_approx(p1.thrust_mult, 1.0) and hm.basket_of(0).count == 2,
		"счёт %s, сдача %s, тяга ×%.2f, в синей корзине %d" % [str(hm.score), str(last), p1.thrust_mult, hm.basket_of(0).count])
	await _wait(Tuning.HEADHUNT_RESPAWN_S + 0.3)
	_brains_off()
	_park([])
	# --- носитель выбит — головы рассыпаются
	var h4 := await _ko(3)
	var h6 := await _ko(5)
	await _wait(Tuning.HEADHUNT_DROP_LOCK_S + 0.1)
	p1 = _doll(0)
	_put_head(h4, Vector2(-2.0, 1.0))
	_put_head(h6, Vector2(2.0, 1.0))
	var g1 := await _touch(p1, h4)
	var g2 := await _touch(p1, h6)
	var carried := hm.carry.carry_count(p1)
	var loose0 := hm.carry.loose().size()
	var drops0 := hm.carry.drops
	await _ko(0)
	await _wait(0.1)
	var scattered := hm.carry.loose().has(h4) and hm.carry.loose().has(h6)
	var own_left := hm.carry.loose().size() - loose0
	_check("carrier_ko_scatter", g1 and g2 and carried == 2 and scattered and own_left == 3 and hm.carry.drops - drops0 == 2
		and not hm.carry.pickable(h4),
		"нёс %d; после KO на полу +%d (две его + своя), рассыпаны: %s, сразу брать нельзя: %s" % [carried, own_left, str(scattered), str(not hm.carry.pickable(h4))])
	# --- не больше трёх на спине
	await _wait(Tuning.HEADHUNT_RESPAWN_S + 0.3)
	_brains_off()
	_park([])
	var h2 := await _ko(1)
	await _wait(Tuning.HEADHUNT_DROP_LOCK_S + 0.1)
	var p3 := _doll(2)   # синий, который берёт всё подряд
	var pool: Array = hm.carry.loose()
	var got := 0
	var refused := false
	var k := 0
	for h in pool:
		_put_head(h, Vector2(-6.0 + 3.0 * float(k), 1.0))
		k += 1
	for h in pool:
		var took := await _touch(p3, h, 0.25)
		if took:
			got += 1
		elif got >= Tuning.HEADHUNT_CARRY_MAX:
			refused = true
	_check("carry_max", pool.size() >= 4 and got == Tuning.HEADHUNT_CARRY_MAX and refused and hm.carry.carry_count(p3) == Tuning.HEADHUNT_CARRY_MAX
		and is_equal_approx(p3.thrust_mult, pow(Tuning.HEADHUNT_CARRY_THRUST, Tuning.HEADHUNT_CARRY_MAX)),
		"голов на полу %d, взял %d, лишнюю не взял: %s, тяга ×%.3f" % [pool.size(), got, str(refused), p3.thrust_mult])
	info["rules_h2"] = str(h2 != null)
	# --- до 10 → итоги
	var enemy_on := 0
	for h in hm.carry.carried(p3):
		if HeadCarry.owner_team(h) == 1:
			enemy_on += 1
	hm.score[0] = Tuning.HEADHUNT_SCORE_TO_WIN - 1
	_to_basket(p3)
	var done := await _until(func() -> bool: return over_count > 0, 1.0)
	var places: Array = over_results.get("places", [])
	_check("to_10_results", enemy_on >= 1 and done and over_count == 1 and int(over_results.get("winner_team", -1)) == 0 and hm.phase == Match.Phase.OVER
		and int(hm.score[0]) >= Tuning.HEADHUNT_SCORE_TO_WIN and not places.is_empty() and HeadhuntMatch.team_of(places[0]) == 0,
		"чужих на спине %d; итогов %d, победили %s, счёт %s" % [enemy_on, over_count, str(over_results.get("winner_team", "?")), str(hm.score)])
	await _wait(1.2)
	_check("hud_end_panel", pg.hud.end_panel.visible and pg.hud.end_title.text != "" and pg.hud.end_table.get_child_count() >= 5 * 7,
		"табличка: «%s» · %s · клеток %d" % [pg.hud.end_title.text, pg.hud.end_sub.text, pg.hud.end_table.get_child_count()])
	# --- R: заново
	hm.restart()
	await _until(func() -> bool: return hm.play_state == "play", 6.0)
	await _wait(0.1)
	_check("restart_resets", int(hm.score[0]) == 0 and int(hm.score[1]) == 0 and hm.deliveries.is_empty() and hm.carry.all_heads().is_empty()
		and hm.alive_dolls().size() == 6 and not pg.hud.end_panel.visible and hm.phase == Match.Phase.FIGHT and hm.basket_of(0).count == 0,
		"счёт %s, голов %d, живых %d, фаза %d" % [str(hm.score), hm.carry.all_heads().size(), hm.alive_dolls().size(), hm.phase])


# ------------------------------------------------------------------ матч ботов

func _bots(max_s: float, level: int, trace: bool) -> void:
	print("--- bots (уровень %d)" % level)
	await _load(level, 3.0)
	var acc := {"hits": 0, "friendly_dmg": 0.0}
	hm.hit.connect(func(v: Doll, a: Node, dmg: float, _k: String, _p: Vector3) -> void:
		if a is Doll:
			acc["hits"] = int(acc["hits"]) + 1
			if HeadhuntMatch.team_of(a) == HeadhuntMatch.team_of(v):
				acc["friendly_dmg"] = float(acc["friendly_dmg"]) + dmg)
	var last_pos: Dictionary = {}
	var stuck_max := 0.0
	var stuck_who := ""
	var press_t: Dictionary = {}
	var press_max := 0.0
	var press_who := ""
	var out_of_bounds := 0
	var b: AABB = pg.arena.call("bounds")
	var frames := 0
	var phys_sum := 0.0
	var phys_max := 0.0
	var trace_t := 0.0
	var t0 := Time.get_ticks_usec()
	while over_count == 0 and hm.fight_time < max_s:
		await get_tree().physics_frame
		frames += 1
		var pm := float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		phys_sum += pm
		phys_max = maxf(phys_max, pm)
		var playing := hm.play_state == "play"
		for d in hm.dolls():
			var dd := d as Doll
			if not dd.alive or not playing:
				last_pos.erase(dd.player_index)
				press_t.erase(dd.player_index)
				continue
			var c := dd.centre_of_mass()
			if c.x < b.position.x - 0.5 or c.x > b.end.x + 0.5 or c.y < b.position.y - 0.5 or c.y > b.end.y + 0.5:
				out_of_bounds += 1
			var br := dd.get_node_or_null("HeadhuntBrain") as HeadhuntBrain
			var lp: Array = last_pos.get(dd.player_index, [])
			# защитник у корзины стоит по делу — для него «застрял» не считается, пока он в guard
			if lp.is_empty() or (lp[0] as Vector3).distance_to(c) > STUCK_M or (br != null and br.state == "guard"):
				last_pos[dd.player_index] = [c, hm.fight_time]
			elif hm.fight_time - float(lp[1]) > stuck_max:
				stuck_max = hm.fight_time - float(lp[1])
				stuck_who = "%s в (%.1f, %.1f), %s" % [HeadhuntMatch.doll_name(dd), c.x, c.y, br.state if br != null else "-"]
			if dd.input_vec.length() >= 0.5 and dd.torso().linear_velocity.length() < 0.35:
				press_t[dd.player_index] = float(press_t.get(dd.player_index, 0.0)) + TICK
				if float(press_t[dd.player_index]) > press_max:
					press_max = float(press_t[dd.player_index])
					press_who = "%s в (%.1f, %.1f), %s" % [HeadhuntMatch.doll_name(dd), c.x, c.y, br.state if br != null else "-"]
			else:
				press_t.erase(dd.player_index)
		if trace and hm.fight_time - trace_t >= 15.0:
			trace_t = hm.fight_time
			var row := []
			for d in hm.dolls():
				var br := (d as Node).get_node_or_null("HeadhuntBrain") as HeadhuntBrain
				var cc := (d as Doll).centre_of_mass()
				row.append("%s:%s(%.0f,%.0f)x%d%s" % [HeadhuntMatch.doll_name(d), br.state if br != null else "-", cc.x, cc.y,
					hm.carry.carry_count(d), "" if (d as Doll).alive else "†"])
			print("  t=%6.1f счёт %s голов на полу %d  %s" % [hm.fight_time, str(hm.score), hm.carry.loose().size(), " ".join(row)])
	var wall_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var total := int(hm.score[0]) + int(hm.score[1])
	_check("bots_match_done", over_count == 1 and hm.fight_time <= Tuning.HEADHUNT_TIME_S + 0.1,
		"итогов %d за %.0f с игры (предел %.0f), счёт %s, причина %s" % [over_count, hm.fight_time, Tuning.HEADHUNT_TIME_S, str(hm.score), str(over_results.get("reason", "?"))])
	_check("bots_points", total >= MIN_POINTS, "очков суммарно %d (нужно ≥ %d), сдач %d, нокаутов %d" % [total, MIN_POINTS, hm.deliveries.size(), hm.kos.size()])
	_check("bots_no_friendly_damage", float(acc["friendly_dmg"]) == 0.0, "урон своим %.1f" % float(acc["friendly_dmg"]))
	_check("bots_not_stuck", stuck_max < STUCK_LIMIT_S and press_max < PRESS_LIMIT_S,
		"на месте дольше всех %.1f с (%s; предел %.0f); упёрся %.1f с (%s; предел %.0f)" % [stuck_max, stuck_who, STUCK_LIMIT_S, press_max, press_who, PRESS_LIMIT_S])
	_check("bots_in_bounds", out_of_bounds == 0, "тиков за границей арены %d" % out_of_bounds)
	var phys_ms := phys_sum / maxf(frames, 1.0)
	info["phys_ms"] = snappedf(phys_ms, 0.01)
	info["phys_ms_max"] = snappedf(phys_max, 0.01)
	_check("phys_ms_measured", frames > 0, "физика %.2f мс / тик (пик %.2f), 6 кукол%s" % [phys_ms, phys_max, "" if phys_ms <= PHYS_WARN_MS else " — выше %.0f мс (headless, сообщить автору)" % PHYS_WARN_MS])
	var states := {}
	for d in hm.dolls():
		var br := (d as Node).get_node_or_null("HeadhuntBrain") as HeadhuntBrain
		if br != null:
			for k in br.counters:
				states[k] = int(states.get(k, 0)) + int(br.counters[k])
	info["bots"] = {"level": level, "fight_s": snappedf(hm.fight_time, 0.1), "score": hm.score.duplicate(), "deliveries": hm.deliveries.size(),
		"kos": hm.kos.size(), "hits": acc["hits"], "picks": hm.carry.picks, "stuck_max_s": snappedf(stuck_max, 0.1),
		"press_max_s": snappedf(press_max, 0.1), "brain_counters": states, "ms_per_physics_frame_wall": snappedf(wall_ms / maxf(frames, 1), 0.01),
		"tally": over_results.get("tally", {})}
