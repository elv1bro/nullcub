## Проба «Собери себя» (docs/plan-demo/SCAVENGER.md) на настоящей площадке scenes/playground_scavenger.tscn (Свалка, пятеро,
## ScavMatch, ScavHud, детали-жетоны).
##   rules (все пятеро — боты с выключенными мозгами; жетоны, кроме проверяемого, заперты): пятеро «Человеков», у каждого только торс
##     и голова (12 деталей в запасе), ход × SCAV_BARE_SPEED; на карте SCAV_PARTS_N деталей, все светятся (material_overlay), все в
##     границах арены; касание детали прикручивает её (деталей +1, запас ❤ растёт, вспышка, журнал, жетон пропал, ход быстрее);
##     предплечье без плеча не прикручивается, после плеча — да; отрыв в бою: деталь снова жетон там, где отлетела, свой замок
##     (хозяину нельзя SCAV_OWN_LOCK_S, чужому — после SCAV_DROP_LOCK_S), ветка → по жетону на деталь; KO — все конечности
##     выбитого рассыпаются жетонами; инвариант «жетоны + детали живых = SCAV_PARTS_N» на каждом шаге; остался один — конец «last»,
##     победа ему; R (restart) — снова все голые, 20 деталей, журналы пусты; время вышло — места по деталям, при равенстве — по
##     запасу, полностью равные первые — ничья; HUD: плашки N/12, «ДЕТАЛИ», кольца на деталях, табличка итогов.
##   bots (все пятеро — боты): матч доигрывается (один живой или время), деталей подобрано ≥ 8 и первая — не позже 30 с, кто-то
##     собрал ≥ 4, был KO, инвариант держался, все живые в границах арены, никто не застрял.
## Обе секции: ошибок скриптов (Logger, SCRIPT ERROR) и ошибок движка — 0.
## Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/scavenger_probe.tscn -- "only=rules|bots|rules+bots,max_s=400,level=2,seed=0,out=<json>"
## → JSON между === SCAVENGER PROBE === и === OK / FAIL ===, exit 0/1.
extends Node

const SCENE := "res://scenes/playground_scavenger.tscn"
const TICK := 1.0 / 60.0
const STUCK_M := 1.5
const STUCK_LIMIT_S := 40.0
const LOCKED := 1.0e9

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
var pg: ScavengerPlayground
var sm: ScavMatch
var over_results: Dictionary = {}
var over_count := 0
var errs := ScriptErrors.new()


func _check(id: String, cond: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": cond, "detail": str(detail)})
	if not cond:
		ok = false
	print("  %-30s %s  %s" % [id, "ok  " if cond else "FAIL", str(detail)])


func _args() -> Dictionary:
	var out := {"only": "", "max_s": "400", "level": "2", "out": "", "seed": "0"}
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
	print("=== SCAVENGER PROBE ===")
	var a := _args()
	if _want(a, "rules"):
		await _rules()
	if _want(a, "bots"):
		await _bots(float(a["max_s"]), int(a["level"]), int(a["seed"]))
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
	pg = (load(SCENE) as PackedScene).instantiate() as ScavengerPlayground
	pg.p1_bot = true
	pg.bot_level = level
	sm = pg.get_node("Match") as ScavMatch
	sm.feel_enabled = false
	sm.countdown_s = countdown
	sm.rng_seed = seed_
	over_results = {}
	over_count = 0
	sm.match_over.connect(func(_w: Doll, r: Dictionary) -> void:
		over_results = r
		over_count += 1)
	add_child(pg)
	await _until(func() -> bool: return sm.play_state == "play" and sm.dolls().size() == Tuning.SCAV_DOLLS, 8.0)


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
		var b := (d as Node).get_node_or_null("ScavBrain")
		if b != null:
			b.set_physics_process(false)
		(d as Doll).input_vec = Vector2.ZERO


func _lock_all() -> void:
	for t in sm.tokens():
		(t as Node).set_meta("scav_lock_until", LOCKED)


## Жетон вида kind (любой), отпертый и поставленный в точку at (скорость 0).
func _token_to(kind: String, at: Vector3) -> RigidBody3D:
	for t in sm.tokens():
		if ScavMatch.kind_of_body(t) == kind and float((t as Node).get_meta("scav_lock_until", 0.0)) >= LOCKED:
			var b := t as RigidBody3D
			b.global_position = Vector3(at.x, at.y, 0.0)
			b.linear_velocity = Vector3.ZERO
			b.angular_velocity = Vector3.ZERO
			b.reset_physics_interpolation()
			b.set_meta("scav_lock_until", 0.0)
			return b
	return null


## Сумма: жетоны на карте + детали на живых куклах.
func _total() -> int:
	var n := sm.tokens().size()
	for d in sm.alive_dolls():
		n += sm.parts_count(d)
	return n


func _limbs_only_torso_head(d: Doll) -> bool:
	var keys: Array = d.parts.keys().map(func(k: Variant) -> String: return String(k))
	keys.sort()
	return keys == ["Head", "Torso"]


## Метка карты, дальше всех от живых кукол (там жетон никто не заденет).
func _far_point() -> Vector3:
	var best := Vector3.ZERO
	var best_d := -1.0
	for m in ScavMatch.MARKS:
		var p := Vector3((m as Vector2).x, (m as Vector2).y, 0.0)
		var near := INF
		for d in sm.alive_dolls():
			near = minf(near, (d as Doll).centre_of_mass().distance_to(p))
		if near > best_d:
			best_d = near
			best = p
	return best


func _hud() -> ScavHud:
	return pg.get_node("HUD") as ScavHud


## Дать кукле d деталь вида kind сразу (через attach_token на отпертом жетоне).
func _give(d: Doll, kind: String) -> bool:
	var t := _token_to(kind, d.torso().global_position + Vector3(0.0, 6.0, 0.0))
	if t == null:
		return false
	return sm.attach_token(d, t)


# ------------------------------------------------------------------ правила

func _rules() -> void:
	print("--- rules")
	await _load(2, 0.3, 4242)
	_brains_off()
	_lock_all()
	var n := sm.dolls().size()
	_check("five_dolls", n == Tuning.SCAV_DOLLS, "кукол %d" % n)
	var bare := true
	var stash_ok := true
	var speed_ok := true
	var colours := {}
	for d in sm.dolls():
		var dd := d as Doll
		bare = bare and _limbs_only_torso_head(dd) and sm.parts_count(dd) == 0
		stash_ok = stash_ok and sm.stash_of(dd).size() == Tuning.SCAV_MAX_PARTS
		speed_ok = speed_ok and is_equal_approx(dd.speed_cap_mult, Tuning.SCAV_BARE_SPEED)
		colours[dd.team] = true
	_check("start_bare", bare, "у P1: %s" % str(_doll(0).parts.keys()))
	_check("start_stash", stash_ok, "в запасе у каждого %d деталей" % Tuning.SCAV_MAX_PARTS)
	_check("start_speed", speed_ok, "ход × %.2f" % Tuning.SCAV_BARE_SPEED)
	_check("all_vs_all", colours.size() == n, "команд %d" % colours.size())
	var toks := sm.tokens()
	var glow := true
	var inside := true
	var box := AABB(Vector3(-18.0, -1.0, -1.0), Vector3(36.0, 16.0, 2.0))
	for t in toks:
		var meshes := (t as Node).find_children("*", "MeshInstance3D", true, false)
		glow = glow and not meshes.is_empty() and (meshes[0] as MeshInstance3D).material_overlay != null
		inside = inside and box.has_point((t as Node3D).global_position)
	_check("tokens_n", toks.size() == Tuning.SCAV_PARTS_N, "деталей на карте %d" % toks.size())
	_check("tokens_glow", glow, "подсветка на всех")
	_check("tokens_inside", inside, "все в границах арены")
	# Старт честный: ни одна деталь не лежит у точки появления (иначе бот берёт её на 0-й секунде).
	var near_spawn := INF
	for t in toks:
		var p := (t as Node3D).global_position
		for s in Tuning.SCAV_SPAWN:
			near_spawn = minf(near_spawn, Vector2(p.x, p.y).distance_to(s as Vector2))
	_check("start_clear", near_spawn >= 1.5, "ближайшая деталь к точке появления %.2f м" % near_spawn)
	_check("invariant_start", _total() == Tuning.SCAV_PARTS_N, "жетоны + детали = %d" % _total())
	await _wait(0.2)
	var hud := _hud()
	_check("hud_plates", hud.plates.size() == Tuning.SCAV_DOLLS and (hud.plates[0][2] as Label).text == "0/%d" % Tuning.SCAV_MAX_PARTS,
		"плашек %d, у P1 «%s»" % [hud.plates.size(), (hud.plates[0][2] as Label).text])
	_check("hud_rings", hud.rings_drawn > 0, "колец на деталях в кадре %d" % hud.rings_drawn)

	# --- касание прикручивает
	var a := _doll(0)
	var b := _doll(1)
	var hp0 := a.max_hp
	var tk0 := sm.tokens().size()
	var t1 := _token_to("upper_arm", a.torso().global_position + Vector3(0.3, 0.0, 0.0))
	var got := await _until(func() -> bool: return sm.parts_count(a) == 1, 1.0)
	_check("pickup", got and not is_instance_valid(t1) or got and (t1 as Node).is_queued_for_deletion(), "деталей у P1 %d" % sm.parts_count(a))
	_check("pickup_reserve", a.max_hp > hp0 + 1.0, "запас %.0f → %.0f" % [hp0, a.max_hp])
	_check("pickup_fx", sm.fx_count >= 1 and sm.pickups.size() == 1 and String(sm.pickups[0]["kind"]) == "upper_arm",
		"вспышек %d, журнал %s" % [sm.fx_count, str(sm.pickups)])
	_check("pickup_token_gone", sm.tokens().size() == tk0 - 1, "жетонов %d → %d" % [tk0, sm.tokens().size()])
	_check("pickup_speed", a.speed_cap_mult > Tuning.SCAV_BARE_SPEED, "ход × %.3f" % a.speed_cap_mult)
	_check("invariant_pickup", _total() == Tuning.SCAV_PARTS_N, "жетоны + детали = %d" % _total())

	# --- предплечье без плеча — нет; после плеча — да
	var la := _token_to("lower_arm", b.torso().global_position + Vector3(0.25, 0.0, 0.0))
	await _wait(0.5)
	_check("chain_needs_parent", sm.parts_count(b) == 0 and is_instance_valid(la) and not la.is_queued_for_deletion(),
		"предплечье без плеча: деталей у P2 %d" % sm.parts_count(b))
	var ua_ok := _give(b, "upper_arm")
	if is_instance_valid(la):
		var pp := b.torso().global_position
		la.global_position = Vector3(pp.x, pp.y, 0.0)
		la.linear_velocity = Vector3.ZERO
	var chain := await _until(func() -> bool: return sm.parts_count(b) == 2, 1.5)
	_check("chain_after_parent", ua_ok and chain, "плечо → предплечье: деталей у P2 %d" % sm.parts_count(b))
	_check("invariant_chain", _total() == Tuning.SCAV_PARTS_N, "жетоны + детали = %d" % _total())

	# --- отрыв в бою: деталь снова жетон, свой замок
	var arm_name := ""
	for k in a.parts.keys():
		if Doll.part_base_name(String(k)) == "UpperArm":
			arm_name = String(k)
	var tk1 := sm.tokens().size()
	var mh1 := a.max_hp
	a.detach_part(arm_name, b)
	await _wait(0.1)
	var torn: Node = null
	for t in sm.tokens():
		if int((t as Node).get_meta("scav_owner", 0)) == a.get_instance_id():
			torn = t
	_check("tear_token", torn != null and sm.tokens().size() == tk1 + 1 and sm.parts_count(a) == 0,
		"жетонов %d → %d, деталей у P1 %d" % [tk1, sm.tokens().size(), sm.parts_count(a)])
	_check("tear_reserve", a.max_hp < mh1 - 1.0 and sm.stash_of(a).size() == Tuning.SCAV_MAX_PARTS, "запас %.0f → %.0f" % [mh1, a.max_hp])
	if torn != null:
		var early := not sm.token_free_for(torn, b) and not sm.token_free_for(torn, a)
		# пока ждём замки — подальше от всех и неподвижно, чтобы никто не подобрал
		var tb := torn as RigidBody3D
		tb.freeze = true
		tb.global_position = _far_point()
		await _wait(Tuning.SCAV_DROP_LOCK_S + 0.1)
		var mid := is_instance_valid(torn) and sm.token_free_for(torn, b) and not sm.token_free_for(torn, a)
		await _wait(Tuning.SCAV_OWN_LOCK_S - Tuning.SCAV_DROP_LOCK_S)
		var late := is_instance_valid(torn) and sm.token_free_for(torn, a)
		if is_instance_valid(torn):
			tb.freeze = false
		_check("tear_own_lock", early and mid and late,
			"сразу никому %s; через %.2f с чужому да, хозяину нет %s; через %.1f с хозяину да %s"
			% [early, Tuning.SCAV_DROP_LOCK_S, mid, Tuning.SCAV_OWN_LOCK_S, late])
	_check("invariant_tear", _total() == Tuning.SCAV_PARTS_N, "жетоны + детали = %d" % _total())
	if torn != null and is_instance_valid(torn):
		torn.set_meta("scav_lock_until", LOCKED)
	# ветка: плечо с предплечьем — два жетона
	var b_arm := ""
	for k in b.parts.keys():
		if Doll.part_base_name(String(k)) == "UpperArm":
			b_arm = String(k)
	var tk2 := sm.tokens().size()
	b.detach_part(b_arm, a)
	await _wait(0.1)
	_check("tear_branch", sm.tokens().size() == tk2 + 2 and sm.parts_count(b) == 0 and sm.stash_of(b).size() == Tuning.SCAV_MAX_PARTS,
		"жетонов %d → %d, деталей у P2 %d, в запасе %d" % [tk2, sm.tokens().size(), sm.parts_count(b), sm.stash_of(b).size()])
	_check("invariant_branch", _total() == Tuning.SCAV_PARTS_N, "жетоны + детали = %d" % _total())
	_lock_all()

	# --- KO: все конечности выбитого — жетоны
	var c := _doll(2)
	for k in ["upper_arm", "upper_arm", "upper_leg", "lower_arm"]:
		_give(c, k)
	var had := sm.parts_count(c)
	var tk3 := sm.tokens().size()
	c.knock_out(a, {"kind": "test"})
	await _wait(0.1)
	_check("ko_scatter", had == 4 and sm.tokens().size() == tk3 + had, "было %d, жетонов %d → %d" % [had, tk3, sm.tokens().size()])
	_check("ko_log", sm.kos.size() == 1 and int(sm.kos[0]["victim"]) == 2 and int(sm.kos[0]["parts"]) == had, str(sm.kos))
	_check("invariant_ko", _total() == Tuning.SCAV_PARTS_N, "жетоны + детали = %d" % _total())
	var hidden := true
	for p in c.parts.values():
		if ScavMatch.kind_of_body(p) != "":
			hidden = hidden and not (p as Node3D).visible
	_check("ko_bodies_hidden", hidden, "конечности выбитого спрятаны")
	_check("not_over_yet", over_count == 0, "живых %d" % sm.alive_dolls().size())

	# --- последний живой
	_give(a, "upper_leg")
	for i in [1, 3, 4]:
		_doll(i).knock_out(a, {"kind": "test"})
		await _wait(0.05)
	var fin := await _until(func() -> bool: return over_count > 0, 1.0)
	_check("last_alive_wins", fin and String(over_results.get("reason", "")) == "last" and over_results.get("winner") == a,
		"конец %s, победитель %s" % [str(over_results.get("reason", "")), ScavMatch.doll_name(over_results.get("winner"))])
	var places: Array = over_results.get("places", [])
	_check("last_places", places.size() == n and places[0] == a and places[1] == _doll(4),
		"места %s" % str(places.map(func(d: Doll) -> String: return ScavMatch.doll_name(d))))
	_check("invariant_over", _total() == Tuning.SCAV_PARTS_N, "жетоны + детали = %d" % _total())
	await _wait(1.2)
	_check("hud_end", hud.end_panel.visible and hud.end_title.text != "" and hud.end_table.get_child_count() == 5 * (n + 1),
		"табличка «%s», ячеек %d" % [hud.end_title.text, hud.end_table.get_child_count()])

	# --- R: всё заново
	sm.restart()
	var again := await _until(func() -> bool: return sm.play_state == "play" and sm.alive_dolls().size() == n, 3.0)
	_brains_off()
	_lock_all()
	var bare2 := true
	for d in sm.dolls():
		bare2 = bare2 and _limbs_only_torso_head(d) and sm.stash_of(d).size() == Tuning.SCAV_MAX_PARTS
	_check("restart", again and bare2 and sm.tokens().size() == Tuning.SCAV_PARTS_N and sm.pickups.is_empty() and sm.kos.is_empty()
		and not hud.end_panel.visible, "живых %d, голые %s, жетонов %d, журналы %d/%d, итоги видны %s" % [sm.alive_dolls().size(), bare2,
		sm.tokens().size(), sm.pickups.size(), sm.kos.size(), hud.end_panel.visible])

	# --- время вышло: места по деталям, затем по запасу; равные первые — ничья
	var d3 := _doll(3)
	var d4 := _doll(4)
	var d1 := _doll(1)
	for k in ["upper_arm", "upper_arm", "upper_leg"]:
		_give(d3, k)
	for k in ["upper_arm", "upper_leg"]:
		_give(d4, k)
	for k in ["upper_arm", "upper_leg"]:
		_give(d1, k)
	d4.hp = d4.max_hp
	d1.hp = d1.max_hp - 15.0
	var r0 := sm.build_results("timeout")
	var p0: Array = r0["places"]
	_check("timeout_rank", p0[0] == d3 and p0[1] == d4 and p0[2] == d1 and r0["winner"] == d3 and not bool(r0["draw"]),
		"места %s" % str(p0.map(func(d: Doll) -> String: return ScavMatch.doll_name(d))))
	_give(d4, "upper_leg")
	d3.hp = 50.0
	d4.hp = 50.0
	var r1 := sm.build_results("timeout")
	_check("timeout_draw", bool(r1["draw"]) and r1["winner"] == null and int(r1["ranks"][0]) == int(r1["ranks"][1]),
		"равные первые: ранги %s" % str(r1["ranks"]))
	d3.hp = 60.0
	sm.fight_time = sm.time_limit_s - 0.05
	var fin2 := await _until(func() -> bool: return over_count > 1, 1.0)
	_check("timeout_finish", fin2 and String(over_results.get("reason", "")) == "timeout" and over_results.get("winner") == d3,
		"конец %s, победитель %s" % [str(over_results.get("reason", "")), ScavMatch.doll_name(over_results.get("winner"))])
	info["rules_pickups"] = sm.pickups.size()


# ------------------------------------------------------------------ боты

func _bots(max_s: float, level: int, seed_: int) -> void:
	print("--- bots (level %d)" % level)
	await _load(level, 0.3, seed_ if seed_ != 0 else 777)
	var box := AABB(Vector3(-19.5, -4.0, -1.5), Vector3(39.0, 22.0, 3.0))
	var inv_bad := 0
	var inv_first := ""
	var out_bad := 0
	var out_first := ""
	var first_pick := -1.0
	var last_pos := {}
	var still := {}
	var stuck_max := 0.0
	var stuck_who := ""
	var tok_max := 0
	var t := 0.0
	var sample := 0.0
	while over_count == 0 and t < max_s:
		await get_tree().physics_frame
		t += TICK
		sample += TICK
		if first_pick < 0.0 and not sm.pickups.is_empty():
			first_pick = sm.fight_time
		if sample < 0.5:
			continue
		sample = 0.0
		var tot := _total()
		tok_max = maxi(tok_max, sm.tokens().size())
		if tot != Tuning.SCAV_PARTS_N:
			inv_bad += 1
			if inv_first == "":
				inv_first = "t=%.1f сумма %d" % [sm.fight_time, tot]
		for d in sm.alive_dolls():
			var dd := d as Doll
			var p := dd.centre_of_mass()
			if not box.has_point(p):
				out_bad += 1
				if out_first == "":
					out_first = "%s в %s" % [ScavMatch.doll_name(dd), str(p)]
			var id := dd.get_instance_id()
			if last_pos.has(id) and (last_pos[id] as Vector3).distance_to(p) < STUCK_M:
				still[id] = float(still.get(id, 0.0)) + 0.5
			else:
				last_pos[id] = p
				still[id] = 0.0
			var st := float(still.get(id, 0.0))
			if st > stuck_max:
				stuck_max = st
				if st >= 10.0 and fmod(st, 5.0) < 0.01:
					stuck_who = _stuck_note(dd)
					print("  stuck %.1f с: %s" % [st, stuck_who])
	var finished := over_count > 0
	var reason := String(over_results.get("reason", ""))
	_check("bots_finish", finished, "конец %s за %.0f с" % [reason, sm.fight_time])
	var tally: Dictionary = over_results.get("tally", sm.tally)
	var best := 0
	for k in tally.keys():
		best = maxi(best, int((tally[k] as Dictionary).get("max_parts", 0)))
	_check("bots_pickups", sm.pickups.size() >= 8, "подобрано %d" % sm.pickups.size())
	_check("bots_first_pick", first_pick >= 0.0 and first_pick <= 30.0, "первая деталь на %.1f с" % first_pick)
	_check("bots_built", best >= 4, "лучший набор %d/%d" % [best, Tuning.SCAV_MAX_PARTS])
	_check("bots_ko", sm.kos.size() >= 1, "KO %d" % sm.kos.size())
	_check("bots_invariant", inv_bad == 0, "нарушений %d; первое: %s; жетонов максимум %d" % [inv_bad, inv_first, tok_max])
	_check("bots_in_bounds", out_bad == 0, "вне арены %d; первое: %s" % [out_bad, out_first])
	_check("bots_not_stuck", stuck_max < STUCK_LIMIT_S, "дольше всех на месте %.1f с%s" % [stuck_max, ("; " + stuck_who) if stuck_who != "" else ""])
	var winner: Object = over_results.get("winner")
	if finished:
		# Ничья в «last» честна только при двойном KO в один тик физики (оба последних выбыли в одном Engine physics frame,
		# живых нет) — так по правилам SCAVENGER.md («равны первые двое — ничья»); любая другая ничья в «last» — дефект.
		# Тик берём из Match.ko_records["physics_frame"], не из kos[t]: fight_time между KO двух кукол одного тика может
		# прибавить delta (Match стоит в дереве между ними) — 81.38 / 81.40 в одном тике.
		var last2: Array = sm.kos.slice(maxi(sm.kos.size() - 2, 0))
		var rec2: Array = sm.ko_records.slice(maxi(sm.ko_records.size() - 2, 0))
		var double_ko := sm.alive_dolls().is_empty() and rec2.size() == 2 \
			and int((rec2[0] as Dictionary).get("physics_frame", -1)) == int((rec2[1] as Dictionary).get("physics_frame", -2))
		_check("bots_winner", reason != "last" or (is_instance_valid(winner) and (winner as Doll).alive) or double_ko,
			"победитель %s, ничья %s%s; последние KO %s" % [ScavMatch.doll_name(winner), str(over_results.get("draw", false)),
			" (двойной KO в один тик)" if double_ko else "", str(last2)])
	info["bots"] = {"reason": reason, "time_s": snappedf(sm.fight_time, 0.1), "pickups": sm.pickups.size(), "kos": sm.kos.size(),
		"drops": sm.drops.size(), "best_parts": best, "winner": ScavMatch.doll_name(winner), "tally": tally}


## Что делает кукла, стоящая на месте (для разбора bots_not_stuck).
func _stuck_note(d: Doll) -> String:
	var b := d.get_node_or_null("ScavBrain")
	var p := d.centre_of_mass()
	var v := Vector2.ZERO
	var tor: RigidBody3D = d.parts.get("Torso", null)
	if tor != null:
		v = Vector2(tor.linear_velocity.x, tor.linear_velocity.y)
	var s := "%s t=%.1f pos=(%.1f,%.1f) v=%.2f in=%s parts=%d stun=%s ctl=%s" % [ScavMatch.doll_name(d), sm.fight_time, p.x, p.y, v.length(),
		str(d.input_vec), sm.parts_count(d), d.is_stunned(), d.control_enabled]
	if b != null:
		var tg: Variant = b.get("target")
		var gp: Variant = b.get("goal_part")
		s += " state=%s want=%s target=%s goal=%s active=%s proc=%s" % [str(b.get("state")), str(b.get("want")),
			ScavMatch.doll_name(tg) if is_instance_valid(tg) else "-", str((gp as Node3D).global_position) if is_instance_valid(gp) else "-",
			str(b.call("is_active")), str(b.is_physics_processing())]
	# кто рядом из чужих тел (во что упёрся): шар 0.9 м у ЦМ, без своих деталей
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.9
	q.shape = sph
	q.transform = Transform3D(Basis(), p)
	var own: Array[RID] = []
	for part in d.parts.values():
		if part is CollisionObject3D:
			own.append((part as CollisionObject3D).get_rid())
	q.exclude = own
	var near: PackedStringArray = []
	for h in d.get_world_3d().direct_space_state.intersect_shape(q, 8):
		var c: Object = h.get("collider")
		if c is Node:
			near.append("%s@%s" % [(c as Node).name, str((c as Node).get_parent().name)])
	s += " near=[%s]" % ", ".join(near)
	return s
