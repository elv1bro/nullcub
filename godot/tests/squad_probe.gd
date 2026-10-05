## Проба «Стычки 3 на 3» (docs/plan-demo/SQUAD.md) на настоящей площадке scenes/playground_squad.tscn (Полигон, шесть бойцов с
## пулемётами, SquadMatch, SquadHud).
##   aim (боты молчат): обе руки (цель — точка в 8 м, через GunAim) наводят стволы у бойца каждой команды — угол лучшего ствола к
##     цели в восьми направлениях, медиана и худший; одна команда не должна целиться заметно хуже другой;
##   rules (P1 — человек без ввода, боты молчат): шесть бойцов, команды 3 / 3 по чётности, свои не ранят, по стволу на каждом
##     предплечье с числами стычки (общие ActiveBlocks.DEFS не тронуты) и своей рукой, каналы игрока жмёт площадка, точки баз по
##     сторонам, KO — очко сопернику и фраг добившему, возврат на базу через SQUAD_RESPAWN_S со щитом возрождения (руки, мозг, стволы —
##     как были), падение — очко сопернику, матч до score_to_win, время вышло (ведущий / ничья), заново — счёт 0 и все живы;
##   bots (P1 тоже бот): матч ботов до конца (очки или время) — все стреляют, пули попадают, урона по своим нет, фраги у обеих
##     команд, первый фраг не поздно, никто не застрял надолго, все в границах карты; темп — в info (длительность, счёт, доля урона
##     пулемётом, выстрелы, отменённые из-за своих на линии огня, мс на тик физики).
## Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/squad_probe.tscn -- "only=aim|rules|bots,max_s=330,level=2,trace=1,out=<json>"
## → JSON между === SQUAD PROBE === и === OK / FAIL ===, exit 0/1. errors_script — SCRIPT ERROR за прогон (Logger).
extends Node

const SCENE := "res://scenes/playground_squad.tscn"
const TICK := 1.0 / 60.0

## Счётчик SCRIPT ERROR за прогон (как stasis_probe): ошибка скрипта обрывает только свою функцию — проба могла бы молча потерять проверки.
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
var pg: SquadPlayground
var sm: SquadMatch
var over_results: Dictionary = {}
var over_count := 0
var errs := ScriptErrors.new()


func _check(id: String, cond: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": cond, "detail": str(detail)})
	if not cond:
		ok = false
	print("  %-34s %s  %s" % [id, "ok  " if cond else "FAIL", str(detail)])


func _args() -> Dictionary:
	var out := {"only": "", "max_s": "330", "level": "2", "trace": "0", "out": ""}
	for a in OS.get_cmdline_user_args():
		for part in String(a).split(","):
			var kv := part.split("=")
			if kv.size() == 2 and out.has(kv[0]):
				out[kv[0]] = kv[1]
	return out


func _ready() -> void:
	OS.add_logger(errs)
	print("=== SQUAD PROBE ===")
	var a := _args()
	if String(a["only"]) in ["", "rules", "aim"]:
		await _aim()
	if String(a["only"]) in ["", "rules"]:
		await _rules()
	if String(a["only"]) in ["", "bots"]:
		await _bots(float(a["max_s"]), int(a["level"]), String(a["trace"]) == "1")
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

func _load(p1_bot: bool, level := 2, countdown := 0.3) -> void:
	await _unload()
	Engine.time_scale = 1.0
	pg = (load(SCENE) as PackedScene).instantiate() as SquadPlayground
	pg.p1_bot = p1_bot
	pg.bot_level = level
	sm = pg.get_node("Match") as SquadMatch
	sm.feel_enabled = false
	sm.countdown_s = countdown
	over_results = {}
	over_count = 0
	sm.match_over.connect(func(_w: Doll, r: Dictionary) -> void:
		over_results = r
		over_count += 1)
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
	for i in int(s / TICK):
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
			var r: Variant = (d as Doll).get("active_rig")
			if r is ActiveRig:
				(r as ActiveRig).held[0] = false


# ------------------------------------------------------------------ прицел

## Восемь направлений по кругу (два круга, мерится второй): точка в 8 м, обе руки — на неё через GunAim, как у бота и игрока; через
## 0.9 с — угол оси каждого ствола к цели (от дула); в зачёт — лучший ствол (стреляет тот, что смотрит на цель). Кукла держится в
## воздухе на месте (тяга = вес, как бот на «полке»), чтобы мерить руку, а не полёт.
func _aim() -> void:
	print("--- aim")
	await _load(false)
	_brains_off()
	await _wait(0.8)
	var res := {}
	for pi in [2, 3]:
		var d := _doll(pi)
		var aims := {}
		var by_dir: Array = []
		var per_gun: Dictionary = {}
		for k in 16:   # два круга: первый — руки выходят из позы спавна, мерится второй
			var ang := TAU * float(k % 8) / 8.0
			var c := d.centre_of_mass()
			var tgt := Vector3(c.x, maxf(c.y, 3.0), 0.0) + Vector3(cos(ang), sin(ang), 0.0) * 8.0
			for i in 54:
				var br := d.get_node_or_null("SquadBrain") as SquadBrain
				if br != null:
					d.input_vec = br.hover_vec()
				for g in SquadMatch.guns_of(d):
					var arm := SquadMatch.arm_for(d, g)
					if arm == null:
						continue
					if not aims.has(g["side"]):
						aims[g["side"]] = GunAim.new()
					arm.set_target_override((aims[g["side"]] as GunAim).point_for(arm, g, tgt))
				await get_tree().physics_frame
			if k < 8:
				continue
			var best := 180.0
			for g in SquadMatch.guns_of(d):
				var e := rad_to_deg(GunAim.error_to(g, tgt))
				best = minf(best, e)
				if not per_gun.has(g["side"]):
					per_gun[g["side"]] = []
				(per_gun[g["side"]] as Array).append(snappedf(e, 0.1))
			by_dir.append(snappedf(best, 0.1))
		var errs_deg: Array = by_dir.duplicate()
		errs_deg.sort()
		res[pi] = {"median": float(errs_deg[4]), "worst": float(errs_deg[7]), "best_by_dir_0_right_ccw": by_dir, "per_gun": per_gun}
		for c2 in d.get_children():
			if c2 is ArmAssist:
				(c2 as ArmAssist).clear_target_override()
	info["aim"] = res
	print("  " + JSON.stringify(res))
	var mb := float(res[2]["median"])
	var mr := float(res[3]["median"])
	_check("aim_blue", mb < 8.0 and float(res[2]["worst"]) < 25.0, "синий, лучший ствол: медиана %.1f°, худший %.1f°" % [mb, float(res[2]["worst"])])
	_check("aim_red", mr < 8.0 and float(res[3]["worst"]) < 25.0, "красный, лучший ствол: медиана %.1f°, худший %.1f°" % [mr, float(res[3]["worst"])])
	_check("aim_fair", absf(mb - mr) < 5.0, "разница медиан %.1f°" % absf(mb - mr))
	await _unload()


# ------------------------------------------------------------------ правила

func _rules() -> void:
	print("--- rules")
	await _load(false)
	_brains_off()
	var ds := sm.dolls()
	var teams := [0, 0]
	var team_ok := true
	for d in ds:
		var t := SquadMatch.team_of(d)
		teams[t] += 1
		team_ok = team_ok and (d as Doll).team == "squad_%d" % t and is_equal_approx((d as Doll).team_damage_mult, 0.0) \
			and (d as Node).is_in_group(SquadMatch.team_group(t)) and not (d as Node).is_in_group(SquadMatch.team_group(1 - t))
	_check("six_fighters", ds.size() == 6 and teams == [3, 3] and team_ok, "бойцов %d, синих / красных %s, команды и группы %s" % [ds.size(), str(teams), str(team_ok)])
	var guns := 0
	var armed := 0
	for d in ds:
		var gs := SquadMatch.guns_of(d)
		var chans := {}
		for g in gs:
			if is_equal_approx(float((g["def"] as Dictionary)["range"]), float(Tuning.SQUAD_GUN["range"])):
				guns += 1
			chans[int(g["channel"])] = SquadMatch.arm_for(d, g)
		if chans.has(1) and chans.has(2) and chans[1] != null and chans[2] != null and chans[1] != chans[2]:
			armed += 1
	var shared := float((ActiveBlocks.DEFS[SquadMatch.GUN_PART] as Dictionary)["range"])
	_check("guns_tuned", guns == 12 and not is_equal_approx(shared, float(Tuning.SQUAD_GUN["range"])),
		"стволов с числами стычки %d из 12, общий DEFS — дальность %.0f м (не тронут)" % [guns, shared])
	_check("two_guns_two_arms", armed == 6, "у %d из 6 — ствол на канале 1 и 2, у каждого своя рука" % armed)
	var p1rig := _doll(0).get("active_rig") as ActiveRig
	_check("p1_manual_fire", p1rig != null and p1rig.manual and not _doll(0).external_input, "каналы игрока жмёт площадка (ActiveRig.manual)")
	var side_ok := true
	for d in ds:
		var x := (d as Doll).centre_of_mass().x
		side_ok = side_ok and ((x < -18.0) if SquadMatch.team_of(d) == 0 else (x > 18.0))
	_check("bases", side_ok, "синие на x < −18, красные на x > 18")
	var outlines := 0
	for d in ds:
		if (d as Node).has_meta(DollOutline.META):
			outlines += 1
	_check("team_outline", outlines == 6, "обводка цвета команды у %d из 6" % outlines)
	await _wait(1.0)   # щит появления (Tuning.SPAWN_GRACE_S) кончился
	var b0 := _doll(0)
	var b2 := _doll(2)
	var r1 := _doll(1)
	var hp0 := b2.hp
	b2.take_damage(20.0, b0, "Torso", b2.centre_of_mass(), Vector3.UP, "body")
	var hp1 := r1.hp
	r1.take_damage(20.0, b0, "Torso", r1.centre_of_mass(), Vector3.UP, "body")
	_check("no_friendly_damage", is_equal_approx(b2.hp, hp0) and r1.hp < hp1 - 10.0, "свой %.0f → %.0f HP, чужой %.0f → %.0f HP" % [hp0, b2.hp, hp1, r1.hp])
	# пулемёт по своему: синий 0 стреляет вплотную в синего 2 — урона нет, толчок есть
	var rig0 := b0.get("active_rig") as ActiveRig
	var blk: Dictionary = SquadMatch.gun_of(b0)["block"]
	var hp_b2 := b2.hp
	for k in 5:
		rig0._deal(b2, 5.0, "Torso", b2.centre_of_mass(), Vector3.UP, "active_gun")
	_check("no_friendly_bullets", is_equal_approx(b2.hp, hp_b2) and blk != null, "пуля по своему: %.0f → %.0f HP" % [hp_b2, b2.hp])
	# нокаут: очко сопернику, фраг добившему, возврат на базу
	var frag_seen: Array = []
	sm.frag.connect(func(k: Doll, v: Doll, t: int) -> void: frag_seen.append([k, v, t]))
	r1.knock_out(b0, {"kind": "body"})
	await get_tree().physics_frame
	_check("ko_scores", sm.score == [1, 0] and int(sm.tally[0]["kills"]) == 1 and int(sm.tally[1]["deaths"]) == 1 and frag_seen.size() == 1
		and frag_seen[0][0] == b0, "счёт %s, фраги P0 %d, выбывания P1 %d, сигналов frag %d" % [str(sm.score), int(sm.tally[0]["kills"]),
		int(sm.tally[1]["deaths"]), frag_seen.size()])
	_check("ko_respawn_queued", sm.respawn_left(r1) > Tuning.SQUAD_RESPAWN_S - 0.2, "до возврата %.2f с" % sm.respawn_left(r1))
	await _wait(Tuning.SQUAD_RESPAWN_S + 0.2)
	var nr1 := _doll(1)
	var back_ok := nr1 != null and nr1 != r1 and nr1.alive and nr1.centre_of_mass().x > 18.0
	_check("respawn_at_base", back_ok, "новая кукла P1 жива на x = %.1f" % (nr1.centre_of_mass().x if nr1 != null else 0.0))
	_check("respawn_shield", nr1 != null and not nr1.can_take_damage(), "сразу после возврата урон не проходит (щит %.1f с)" % Tuning.SQUAD_SPAWN_SHIELD_S)
	_check("respawn_keeps_team", nr1 != null and nr1.team == "squad_1" and nr1.is_in_group("squad_1") and nr1.has_meta(DollOutline.META)
		and nr1.get_node_or_null("SquadBrain") != null and _arms_ok(nr1) and SquadMatch.guns_of(nr1).size() == 2,
		"команда, группа, обводка, мозг, две руки (правая и левая), два ствола")
	await _wait(0.2)
	var ng := SquadMatch.gun_of(nr1) if nr1 != null else {}
	_check("respawn_gun_tuned", not ng.is_empty() and is_equal_approx(float((ng["def"] as Dictionary)["range"]), float(Tuning.SQUAD_GUN["range"])),
		"пулемёт новой куклы — с числами стычки")
	# падение / самоубийство — очко сопернику, фрага нет
	_doll(4).knock_out(null, {"kind": "self"})
	await get_tree().physics_frame
	_check("self_ko_scores", sm.score == [1, 1] and frag_seen.size() == 2 and frag_seen[1][0] == null, "счёт %s" % str(sm.score))
	# до score_to_win: ещё два нокаута красных — конец, победа синих
	sm.score_to_win = 3
	_doll(3).knock_out(_doll(0), {"kind": "body"})
	await get_tree().physics_frame
	_doll(5).knock_out(_doll(2), {"kind": "body"})
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("win_by_score", over_count == 1 and int(over_results.get("winner_team", -1)) == 0 and sm.play_state == "over"
		and sm.phase == Match.Phase.OVER, "итогов %d, победила команда %d, счёт %s" % [over_count, int(over_results.get("winner_team", -1)), str(sm.score)])
	await _wait(Tuning.SQUAD_RESPAWN_S + 0.5)
	_check("no_respawn_after_over", _doll(3) != null and not _doll(3).alive, "после конца матча возвратов нет")
	# заново
	sm.restart()
	await _until(func() -> bool: return sm.play_state == "play", 6.0)
	var all_alive := sm.dolls().size() == 6 and sm.alive_dolls().size() == 6
	_check("restart", sm.score == [0, 0] and all_alive and over_count == 1, "счёт %s, живых %d из %d" % [str(sm.score), sm.alive_dolls().size(), sm.dolls().size()])
	# время вышло: ведущий победил; равный счёт — ничья
	_brains_off()
	sm.score_to_win = 99
	sm.time_limit_s = sm.fight_time + 0.5
	await _until(func() -> bool: return over_count == 2, 3.0)
	_check("timeout_draw", over_count == 2 and int(over_results.get("winner_team", 0)) == -1 and bool(over_results.get("draw", false)),
		"0 : 0 к концу времени — ничья")
	sm.time_limit_s = Tuning.SQUAD_TIME_LIMIT_S
	sm.restart()
	await _until(func() -> bool: return sm.play_state == "play", 6.0)
	_brains_off()
	await _wait(1.0)
	_doll(0).knock_out(_doll(1), {"kind": "body"})
	sm.time_limit_s = sm.fight_time + 0.5
	await _until(func() -> bool: return over_count == 3, 3.0)
	_check("timeout_leader", over_count == 3 and int(over_results.get("winner_team", -1)) == 1, "0 : 1 к концу времени — победа красных")
	sm.time_limit_s = Tuning.SQUAD_TIME_LIMIT_S
	await _unload()


## Ровно две руки: правая (кисть Hand_R) и левая (Hand_L) — копии после возрождения не задвоились и не потеряли сторону.
func _arms_ok(d: Doll) -> bool:
	var parts := []
	for c in d.get_children():
		if c is ArmAssist and not c.is_queued_for_deletion():
			parts.append((c as ArmAssist).part_name)
	parts.sort()
	return parts == ["Hand_L", "Hand_R"]


# ------------------------------------------------------------------ матч ботов

func _bots(max_s: float, level: int, trace: bool) -> void:
	print("--- bots (level %d)" % level)
	await _load(true, level, 3.0)
	var acc := {"friendly": 0.0, "all": 0.0}
	sm.hit.connect(func(v: Doll, a: Node, dmg: float, _k: String, _p: Vector3) -> void:
		acc["all"] = float(acc["all"]) + dmg
		if a is Doll and SquadMatch.team_of(a) == SquadMatch.team_of(v) and a != v:
			acc["friendly"] = float(acc["friendly"]) + dmg)
	var gun_dmg := 0.0
	var last_gun: Dictionary = {}       # instance id ActiveRig → block_damage
	var ff := {"t": -1.0}
	sm.frag.connect(func(_k: Doll, _v: Doll, _t: int) -> void:
		if float(ff["t"]) < 0.0:
			ff["t"] = sm.fight_time)
	var shots: Dictionary = {}          # player_index → выстрелов за матч (по всем жизням)
	var last_shots: Dictionary = {}     # instance id ActiveRig → shots
	var blocked := 0
	var last_pos: Dictionary = {}       # player_index → [pos, fight_time]
	var stuck_max := 0.0
	var out_of_bounds := 0
	var b: AABB = pg.arena.call("bounds")
	var props0: int = (pg.arena.call("breakables") as Array).size()
	var t0 := Time.get_ticks_usec()
	var frames := 0
	var trace_t := 0.0
	while over_count == 0 and sm.fight_time < max_s:
		await get_tree().physics_frame
		frames += 1
		for d in sm.dolls():
			var dd := d as Doll
			var rig: Variant = dd.get("active_rig")
			if rig is ActiveRig and is_instance_valid(rig):
				var id := (rig as Object).get_instance_id()
				var s := (rig as ActiveRig).shots
				shots[dd.player_index] = int(shots.get(dd.player_index, 0)) + maxi(s - int(last_shots.get(id, 0)), 0)
				last_shots[id] = s
				var bd := (rig as ActiveRig).block_damage
				gun_dmg += maxf(bd - float(last_gun.get(id, 0.0)), 0.0)
				last_gun[id] = bd
			if not dd.alive:
				last_pos.erase(dd.player_index)
				continue
			var c := dd.centre_of_mass()
			if c.x < b.position.x - 0.5 or c.x > b.end.x + 0.5 or c.y < b.position.y - 0.5 or c.y > b.end.y + 0.5:
				out_of_bounds += 1
			var lp: Array = last_pos.get(dd.player_index, [])
			if lp.is_empty() or (lp[0] as Vector3).distance_to(c) > 1.5:
				last_pos[dd.player_index] = [c, sm.fight_time]
			else:
				stuck_max = maxf(stuck_max, sm.fight_time - float(lp[1]))
		if trace and sm.fight_time - trace_t >= 10.0:
			trace_t = sm.fight_time
			var row := []
			for d in sm.dolls():
				var br := (d as Node).get_node_or_null("SquadBrain") as SquadBrain
				row.append("%d:%s(%.0f,%.0f)%s" % [(d as Doll).player_index, br.state if br != null else "-", (d as Doll).centre_of_mass().x,
					(d as Doll).centre_of_mass().y, "" if (d as Doll).alive else "†"])
			print("  t=%5.1f score=%s  %s" % [sm.fight_time, str(sm.score), " ".join(row)])
	var wall_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var brains := {}
	for d in sm.dolls():
		var br := (d as Node).get_node_or_null("SquadBrain") as SquadBrain
		if br != null:
			blocked += br.shots_blocked
			brains[(d as Doll).player_index] = {"blocked": br.shots_blocked, "c": br.counters.duplicate()}
	var tally := sm.tally.duplicate(true)
	var kills := [0, 0]
	for pi in tally:
		kills[int(pi) % 2] += int(tally[pi]["kills"])
	var first_frag := float(ff["t"])
	var friendly := float(acc["friendly"])
	var all_dmg := float(acc["all"])
	var shooters := 0
	for pi in shots:
		if int(shots[pi]) > 20:
			shooters += 1
	info["bots"] = {"level": level, "fight_s": snappedf(sm.fight_time, 0.1), "score": sm.score.duplicate(), "frags": sm.frags.size(),
		"first_frag_s": snappedf(first_frag, 0.1), "kills_by_team": kills, "shots": shots, "gun_damage_share": snappedf(gun_dmg / maxf(all_dmg, 1.0), 0.01),
		"damage_total": snappedf(all_dmg, 0.1), "blocked_by_friend": blocked, "stuck_max_s": snappedf(stuck_max, 0.1),
		"ms_per_physics_frame": snappedf(wall_ms / maxf(frames, 1), 0.01), "tally": tally, "brains": brains,
		"props_broken": props0 - (pg.arena.call("breakables") as Array).size(), "props": props0}
	print("  " + JSON.stringify(info["bots"]))
	_check("bots_match_ends", over_count == 1, "матч кончился: %s за %.0f с, счёт %s" % [str(over_count == 1), sm.fight_time, str(sm.score)])
	_check("bots_all_shoot", shooters == 6, "стреляли (> 20 выстрелов) %d из 6" % shooters)
	_check("bots_guns_hit", gun_dmg > 100.0, "урон пулемётами %.0f HP" % gun_dmg)
	_check("bots_no_friendly", friendly <= 0.01, "урон по своим %.1f HP" % friendly)
	_check("bots_both_frag", kills[0] > 0 and kills[1] > 0, "фраги синих / красных %s" % str(kills))
	_check("bots_first_frag", first_frag >= 0.0 and first_frag < 60.0, "первый фраг на %.1f с" % first_frag)
	_check("bots_not_stuck", stuck_max < 25.0, "дольше всего на месте (в радиусе 1.5 м) %.1f с" % stuck_max)
	_check("bots_in_bounds", out_of_bounds == 0, "тиков вне границ карты %d" % out_of_bounds)
	await _unload()
