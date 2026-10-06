## Проба спорт-зала (docs/plan-demo/SPORT.md): правила трёх видов спорта и матч ботов на настоящих площадках
## (scenes/playground_sport*.tscn — зал, куклы, мяч, SportMatch, HUD).
##   правила (без ботов, мяч ставится руками): ввод мяча, гол и счёт, расстановка после гола, гол в свои ворота, мяч над
##   перекладиной — не гол и скатывается с крыши ворот, нокаут — возврат через SPORT_KO_RESPAWN_S без конца матча, матч до
##   SPORT_GOALS_TO_WIN голов и итоги (победитель по счёту), заново, время вышло (ведущий победил / золотой гол);
##   баскетбол — кольцо сверху вниз, снизу вверх не считается; волейбол — подача, пол чужой половины, сетка держит мяч,
##   стенка над сеткой держит куклу и пропускает мяч;
##   боты (SportBrain за обоих): матч доигрывается (голы или время), есть голы, мяч не покидает зал, скорость мяча ≤ потолка.
##   «как есть» (автор 06.10, Tuning.SPORT_PARTHP / SPORT_KEEP_DAMAGE): в зале включён «Запас из деталей»; оторванное не отрастает
##   после гола и после нокаута, запас и износ после гола те же; новый матч — куклы целые; режим выключен — чинится, как раньше;
##   вышли из зала — режимы отрыва как были; то же для куклы из мастерской (ModularDoll «Поршневой»: узлы чертежа и порванные связки).
## Headless:
##   godot --headless --path . --fixed-fps 60 res://tests/sport_probe.tscn -- "sports=football,basketball,volleyball,bots=1,max_s=300,out=<json>"
## → код выхода 0/1, JSON между === SPORT PROBE === и === OK / FAIL ===. only=rules | bots — половина пробы.
extends Node

const SCENES := {
	"football": "res://scenes/playground_sport.tscn",
	"basketball": "res://scenes/playground_sport_basketball.tscn",
	"volleyball": "res://scenes/playground_sport_volleyball.tscn",
}
const TICK := 1.0 / 60.0

var ok := true
var checks: Array = []
var report := {"sports": {}}
var pg: Node
var sm: SportMatch
var ball: SportBall
var over_results: Dictionary = {}
var over_winner: Doll = null
var over_count := 0


func _check(id: String, cond: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": cond, "detail": str(detail)})
	if not cond:
		ok = false
	print("  %-44s %s  %s" % [id, "ok  " if cond else "FAIL", str(detail)])


func _args() -> Dictionary:
	var out := {"sports": "football,basketball,volleyball", "bots": "1", "max_s": "300", "out": "", "only": "", "trace": "0"}
	for a in OS.get_cmdline_user_args():
		var key := ""
		for part in String(a).split(","):
			var kv := part.split("=")
			if kv.size() == 2 and out.has(kv[0]):
				key = kv[0]
				out[key] = kv[1]
			elif key == "sports":
				out[key] = String(out[key]) + "," + part   # sports=a,b,c — список через запятую
	return out


func _ready() -> void:
	print("=== SPORT PROBE ===")
	var a := _args()
	for id in String(a["sports"]).split(",", false):
		if not SCENES.has(id):
			continue
		print("--- %s" % id)
		report["sports"][id] = {}
		if String(a["only"]) != "bots":
			await _rules_common(id)
			match id:
				"football":
					await _rules_football()
				"basketball":
					await _rules_basketball()
				"volleyball":
					await _rules_volleyball()
			await _rules_keep_damage(id)
			if id == "football":
				await _rules_keep_damage_modular()
		if String(a["bots"]) == "1" and String(a["only"]) != "rules":
			await _bot_match(id, float(a["max_s"]), String(a["trace"]) == "1")
	report["ok"] = ok
	report["checks"] = checks
	print(JSON.stringify(report, " "))
	if String(a["out"]) != "":
		var f := FileAccess.open(String(a["out"]), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(report, " "))
			f.close()
	print("=== OK ===" if ok else "=== FAIL ===")
	get_tree().quit(0 if ok else 1)


# ------------------------------------------------------------------ помощники

## prep(площадка) — до add_child: подменить куклу и т. п.
func _load(id: String, countdown := 0.2, kickoff := 0.2, bot := false, prep := Callable()) -> void:
	if pg != null:
		remove_child(pg)
		pg.queue_free()
		await get_tree().physics_frame
	Engine.time_scale = 1.0
	pg = (load(SCENES[id]) as PackedScene).instantiate()
	sm = pg.get_node("Match") as SportMatch
	sm.feel_enabled = false
	sm.countdown_s = countdown
	sm.kickoff_s = kickoff
	pg.set("p2_bot", bot)
	over_results = {}
	over_winner = null
	over_count = 0
	sm.match_over.connect(func(w: Doll, r: Dictionary) -> void:
		over_winner = w
		over_results = r
		over_count += 1)
	if prep.is_valid():
		prep.call(pg)
	add_child(pg)
	ball = pg.get_node("Ball") as SportBall
	await _until(func() -> bool: return sm.play_state == "play", 6.0)


func _until(cond: Callable, max_s: float) -> bool:
	var n := int(max_s / TICK)
	for i in n:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _wait(s: float) -> void:
	for i in int(s / TICK):
		await get_tree().physics_frame


func _put_ball(pos: Vector2, vel := Vector2.ZERO) -> void:
	ball.freeze = false
	ball.global_transform = Transform3D(Basis.IDENTITY, Vector3(pos.x, pos.y, 0.0))
	ball.linear_velocity = Vector3(vel.x, vel.y, 0.0)
	ball.angular_velocity = Vector3.ZERO
	ball.untouched_s = 0.0
	sm._ball_prev = pos


func _doll(index: int) -> Doll:
	for d in sm.dolls():
		if (d as Doll).player_index == index:
			return d
	return null


func _x(d: Doll) -> float:
	return d.centre_of_mass().x if d != null else NAN


## Точка, из которой мяч сразу засчитывается команде team (её гол / очко).
func _scoring_spot(id: String, team: int) -> Array:
	var r: Dictionary = Tuning.SPORTS[id]
	var s := 1.0 if team == 0 else -1.0
	match id:
		"basketball":
			return [Vector2(s * float(r["hoop_x"]), float(r["hoop_y"]) + 0.5), Vector2(0.0, -3.0)]
		"volleyball":
			return [Vector2(s * 8.5, Tuning.SPORT_BALL_RADIUS + 0.3), Vector2(0.0, -3.0)]   # в стороне от куклы на точке ввода
	return [Vector2(s * (float(r["goal_x"]) + 1.0), 1.0), Vector2.ZERO]


func _force_goal(id: String, team: int) -> bool:
	var before := int(sm.score[team])
	var spot := _scoring_spot(id, team)
	_put_ball(spot[0], spot[1])
	ball.last_touch = _doll(team)
	return await _until(func() -> bool: return int(sm.score[team]) == before + 1, 2.0)


# ------------------------------------------------------------------ общие правила

func _rules_common(id: String) -> void:
	await _load(id)
	var arena := pg.get_node("SportHall") as SportHallArena
	var p1 := _doll(0)
	var p2 := _doll(1)
	_check(id + ".scene", arena != null and ball != null and p1 != null and p2 != null and sm.sport == id, "sport=%s" % sm.sport)
	var fx_ok := true
	for f in arena.get_node("Fixtures").get_children():
		var on := String(f.name) == id
		if (f as Node3D).visible != on or (f.process_mode == Node.PROCESS_MODE_DISABLED) == on:
			fx_ok = false
	_check(id + ".fixtures_one_sport", fx_ok, "виден и в физике только снаряд вида")
	_check(id + ".kickoff_sides", _x(p1) < -2.0 and _x(p2) > 2.0, "P1 x=%.1f, P2 x=%.1f" % [_x(p1), _x(p2)])
	_check(id + ".start_score", sm.score == [0, 0] and sm.phase == Match.Phase.FIGHT and not ball.freeze, "счёт %s, фаза %d" % [sm.score, sm.phase])
	_check(id + ".ball_mass", is_equal_approx(ball.mass, float(Tuning.SPORTS[id]["mass"])), "%.1f кг" % ball.mass)
	# гол команды 0, пауза, расстановка
	var scored := await _force_goal(id, 0)
	_check(id + ".goal_counts", scored and sm.score == [1, 0] and sm.play_state == "goal", "счёт %s, состояние %s" % [sm.score, sm.play_state])
	_check(id + ".board", arena.score == [1, 0] and (arena.get_node("Board/ScoreL") as Label3D).text == "1", "табло %s" % [arena.score])
	var hud_l: Label = (pg.get_node("SportHud") as SportHud).labels[0]
	_check(id + ".hud_score", hud_l.text == "1", "HUD слева «%s»" % hud_l.text)
	var old_p1 := p1
	var got_kick := await _until(func() -> bool: return sm.play_state == "kickoff", Tuning.SPORT_GOAL_PAUSE_S + 1.0)
	var spawn := arena.ball_spawn(sm.serve_team)
	p1 = _doll(0)
	p2 = _doll(1)
	_check(id + ".kickoff_after_goal", got_kick and ball.freeze and ball.global_position.distance_to(spawn) < 0.05 and sm.phase == Match.Phase.COUNTDOWN,
		"мяч %s, ввод %s" % [ball.global_position, spawn])
	_check(id + ".dolls_reset", p1 != old_p1 and absf(_x(p1) + Tuning.SPORT_SPAWN_X) < 1.0 and absf(_x(p2) - Tuning.SPORT_SPAWN_X) < 1.0 and is_equal_approx(p1.hp, p1.max_hp),
		"P1 x=%.1f, P2 x=%.1f" % [_x(p1), _x(p2)])
	_check(id + ".serve_to_conceded", sm.serve_team == 1, "ввод команде %d" % sm.serve_team)
	await _until(func() -> bool: return sm.play_state == "play", 3.0)
	_check(id + ".play_resumes", sm.play_state == "play" and not ball.freeze and sm.phase == Match.Phase.FIGHT, sm.play_state)
	# гол в свои: последним мяча коснулся P1, мяч — в очко команды 1
	var spot := _scoring_spot(id, 1)
	_put_ball(spot[0], spot[1])
	ball.last_touch = _doll(0)
	await _until(func() -> bool: return int(sm.score[1]) == 1, 2.0)
	var g: Dictionary = sm.goals[-1] if not sm.goals.is_empty() else {}
	_check(id + ".own_goal", sm.score == [1, 1] and bool(g.get("own_goal", false)) and int(g.get("scorer", -1)) == 0 and int(g.get("team", -1)) == 1, str(g))
	await _until(func() -> bool: return sm.play_state == "play", Tuning.SPORT_GOAL_PAUSE_S + 3.0)
	# нокаут — удаление, матч идёт
	p2 = _doll(1)
	p2.knock_out()
	await _wait(0.3)
	_check(id + ".ko_not_over", sm.phase != Match.Phase.OVER and not p2.alive and over_count == 0, "фаза %d" % sm.phase)
	await _wait(Tuning.SPORT_KO_RESPAWN_S + 0.4)
	var p2n := _doll(1)
	_check(id + ".ko_respawn", p2n != null and p2n != p2 and p2n.alive and is_equal_approx(p2n.hp, p2n.max_hp) and absf(_x(p2n) - Tuning.SPORT_SPAWN_X) < 1.5 and p2n.control_enabled,
		"P2 x=%.1f alive=%s" % [_x(p2n), p2n.alive if p2n != null else false])
	# до победы: ещё два гола команды 0
	if sm.play_state != "play":
		await _until(func() -> bool: return sm.play_state == "play", Tuning.SPORT_GOAL_PAUSE_S + 3.0)
	await _force_goal(id, 0)
	await _until(func() -> bool: return sm.play_state == "play", Tuning.SPORT_GOAL_PAUSE_S + 3.0)
	await _force_goal(id, 0)
	await _until(func() -> bool: return sm.phase == Match.Phase.OVER, Tuning.SPORT_GOAL_PAUSE_S + 1.0)
	var w_idx := over_winner.player_index if over_winner != null and is_instance_valid(over_winner) else -1
	_check(id + ".match_to_3", sm.phase == Match.Phase.OVER and over_count == 1 and w_idx == 0 and over_results.get("score", []) == [3, 1] and
		String(over_results.get("reason", "")) == "goals" and String(over_results.get("sport", "")) == id and not bool(over_results.get("draw", true)),
		"победитель P%d, счёт %s, причина %s" % [w_idx + 1, over_results.get("score", []), over_results.get("reason", "")])
	var places: Array = over_results.get("places", [])
	_check(id + ".results_places", places.size() == 2 and (places[0] as Doll).player_index == 0 and over_results.get("ranks", []) == [0, 1] and sm.goals_of(0) == 3,
		"голы P1 %d, места %s" % [sm.goals_of(0), over_results.get("ranks", [])])
	# заново (после таймера итогов HUD: его лямбда держит куклу-победителя)
	await _wait(0.6)
	sm.restart()
	await _until(func() -> bool: return sm.play_state == "play", 3.0)
	_check(id + ".restart", sm.score == [0, 0] and sm.goals.is_empty() and sm.play_state == "play" and sm.phase == Match.Phase.FIGHT, "счёт %s" % [sm.score])
	# время вышло при счёте 1:0 — победил ведущий
	await _force_goal(id, 1)
	await _until(func() -> bool: return sm.play_state == "play", Tuning.SPORT_GOAL_PAUSE_S + 3.0)
	sm.fight_time = sm.time_limit_s - 0.05
	await _until(func() -> bool: return sm.phase == Match.Phase.OVER, 1.0)
	w_idx = over_winner.player_index if over_winner != null and is_instance_valid(over_winner) else -1
	_check(id + ".timeout_leader_wins", sm.phase == Match.Phase.OVER and w_idx == 1 and String(over_results.get("reason", "")) == "timeout",
		"победитель P%d, причина %s" % [w_idx + 1, over_results.get("reason", "")])
	# время вышло при равном счёте — золотой гол
	await _wait(0.6)
	sm.restart()
	await _until(func() -> bool: return sm.play_state == "play", 3.0)
	sm.fight_time = sm.time_limit_s - 0.05
	await _until(func() -> bool: return sm.phase == Match.Phase.SUDDEN_DEATH, 1.0)
	_check(id + ".golden_goal_phase", sm.phase == Match.Phase.SUDDEN_DEATH and sm.golden and is_equal_approx(sm.knockback_mult(), 1.0), "фаза %d" % sm.phase)
	await _force_goal(id, 0)
	await _until(func() -> bool: return sm.phase == Match.Phase.OVER, Tuning.SPORT_GOAL_PAUSE_S + 1.0)
	w_idx = over_winner.player_index if over_winner != null and is_instance_valid(over_winner) else -1
	_check(id + ".golden_goal_ends", sm.phase == Match.Phase.OVER and w_idx == 0 and over_results.get("score", []) == [1, 0], "победитель P%d, счёт %s" % [w_idx + 1, over_results.get("score", [])])
	# ничья: золотое время вышло
	await _wait(0.6)
	sm.restart()
	await _until(func() -> bool: return sm.play_state == "play", 3.0)
	sm.fight_time = sm.time_limit_s - 0.05
	await _until(func() -> bool: return sm.phase == Match.Phase.SUDDEN_DEATH, 1.0)
	sm.fight_time = sm.hard_timeout_s - 0.05
	await _until(func() -> bool: return sm.phase == Match.Phase.OVER, 1.0)
	_check(id + ".draw", sm.phase == Match.Phase.OVER and over_winner == null and bool(over_results.get("draw", false)), "ничья %s" % over_results.get("draw", false))


# ------------------------------------------------------------------ куклы не чинятся между розыгрышами

## Деталей нет у куклы: ни тела в parts и в дереве, ни суставов к ним.
func _lacks(d: Doll, names: Array) -> bool:
	for n in names:
		if d.parts.has(n) or d.get_node_or_null(NodePath(String(n))) != null:
			return false
	return true


func _rules_keep_damage(id: String) -> void:
	if pg != null:
		remove_child(pg)
		pg.queue_free()
		pg = null
		await get_tree().physics_frame
	var modes_out := [PartHp.on, JointBreak.on]
	await _load(id)
	var p1 := _doll(0)
	var full_max := p1.max_hp
	_check(id + ".parthp_default", PartHp.on and not JointBreak.on and sm.keeps_damage() and is_equal_approx(full_max, roundf(p1.parts_hp_total())),
		"PartHp %s, JointBreak %s, запас %.0f из деталей %.0f" % [PartHp.on, JointBreak.on, full_max, p1.parts_hp_total()])
	# рука оторвана, урон, износ ноги — гол — на вводе всё как было
	p1.detach_part("UpperArm_L")
	p1.hp -= 7.0
	p1.joint_hp["UpperLeg_R"] = float(p1.joint_hp["UpperLeg_R"]) - 5.0
	var max_before := p1.max_hp
	var arm := ["UpperArm_L", "LowerArm_L", "Hand_L", "Shoulder_L", "Elbow_L", "Wrist_L"]
	var swap := {}   # старая кукла в момент замены: запас, максимум, износ бедра (между отрывом и голом могла задеть свою руку)
	var on_swap := func(o: Doll, _n: Doll) -> void:
		if o.player_index == 0 and swap.is_empty():
			swap.merge({"hp": o.hp, "max": o.max_hp, "leg": float(o.joint_hp.get("UpperLeg_R", -1.0))})
	sm.doll_replaced.connect(on_swap)
	await _force_goal(id, 0)
	await _until(func() -> bool: return sm.play_state == "kickoff", Tuning.SPORT_GOAL_PAUSE_S + 1.0)
	sm.doll_replaced.disconnect(on_swap)
	var p1g := _doll(0)
	_check(id + ".kept_after_goal", p1g != p1 and _lacks(p1g, arm) and p1g.parts.has("UpperArm_R") and p1g.parts.has("Head") and p1g.parts.size() == 11,
		"деталей %d, нет %s" % [p1g.parts.size(), p1g.lost_part_names()])
	var leg_now := float(p1g.joint_hp.get("UpperLeg_R", -1.0))
	_check(id + ".hp_kept_after_goal", not swap.is_empty() and is_equal_approx(p1g.max_hp, max_before) and max_before < full_max
		and is_equal_approx(p1g.hp, float(swap["hp"])) and float(swap["hp"]) < max_before and is_equal_approx(leg_now, float(swap["leg"]))
		and leg_now < float(p1g.joint_hp_max.get("UpperLeg_R", 0.0)),
		"запас %.1f/%.0f (было %s, целый %.0f), износ бедра %.1f" % [p1g.hp, p1g.max_hp, swap, full_max, leg_now])
	# нокаут: голова на месте, рука — нет, запас — полный из того, что осталось
	await _until(func() -> bool: return sm.play_state == "play", 3.0)
	p1g.knock_out()
	await _wait(Tuning.SPORT_KO_RESPAWN_S + 0.4)
	var p1k := _doll(0)
	_check(id + ".kept_after_ko", p1k != p1g and p1k.alive and _lacks(p1k, arm) and p1k.parts.has("Head") and is_equal_approx(p1k.hp, p1k.max_hp)
		and is_equal_approx(p1k.max_hp, max_before), "деталей %d, запас %.0f/%.0f" % [p1k.parts.size(), p1k.hp, p1k.max_hp])
	# вторая потеря копится к первой
	p1k.detach_part("Foot_R")
	await _force_goal(id, 0)
	await _until(func() -> bool: return sm.play_state == "kickoff", Tuning.SPORT_GOAL_PAUSE_S + 1.0)
	var p1f := _doll(0)
	_check(id + ".losses_add_up", _lacks(p1f, arm + ["Foot_R", "Ankle_R"]) and p1f.parts.has("LowerLeg_R") and p1f.parts.size() == 10,
		"нет %s" % [p1f.lost_part_names()])
	# новый матч — куклы целые
	await _until(func() -> bool: return sm.play_state == "play", 3.0)
	sm.restart()
	await _until(func() -> bool: return sm.play_state == "play", 3.0)
	var p1r := _doll(0)
	_check(id + ".new_match_whole", p1r.parts.size() == 14 and is_equal_approx(p1r.max_hp, full_max) and is_equal_approx(p1r.hp, full_max),
		"деталей %d, запас %.0f/%.0f" % [p1r.parts.size(), p1r.hp, p1r.max_hp])
	# режим выключили («;») — после гола кукла снова целая
	PartHp.set_on(false)
	p1r.detach_part("UpperArm_R")
	await _force_goal(id, 0)
	await _until(func() -> bool: return sm.play_state == "kickoff", Tuning.SPORT_GOAL_PAUSE_S + 1.0)
	_check(id + ".off_repairs", not sm.keeps_damage() and _doll(0).parts.size() == 14, "деталей %d" % _doll(0).parts.size())
	PartHp.set_on(true)
	# вышли из зала — режимы отрыва как были до него
	remove_child(pg)
	pg.queue_free()
	pg = null
	await get_tree().physics_frame
	_check(id + ".modes_restored", [PartHp.on, JointBreak.on] == modes_out, "PartHp %s, JointBreak %s" % [PartHp.on, JointBreak.on])


## Кукла из мастерской за P1 (чертёж «Поршневой» в памяти: поршни Link_1 бедро L — кисть L и Link_2 бедро R — кисть R, пружина
## Link_3 между голенями): кисть L оторвана (Link_1 рвётся с ней), Link_3 порвана — после гола и нокаута их нет, новый матч — целая.
func _rules_keep_damage_modular() -> void:
	var id := "football"
	var bp := (load("res://data/body/blueprints/kit_pistons.tres") as BodyBlueprint).duplicate(true) as BodyBlueprint
	await _load(id, 0.2, 0.2, false, func(root: Node) -> void:
		var old := root.get_node("P1") as Doll
		var md := (load("res://scenes/body/modular_doll.tscn") as PackedScene).instantiate() as ModularDoll
		md.blueprint = bp
		md.name = old.name
		md.transform = old.transform
		md.player_index = old.player_index
		md.input_prefix = old.input_prefix
		for g in old.get_groups():
			md.add_to_group(g)
		var idx := old.get_index()
		root.remove_child(old)
		old.free()
		root.add_child(md)
		root.move_child(md, idx))
	var p1 := _doll(0) as ModularDoll
	var links3 := func(d: ModularDoll) -> Array: return [d.links_rt.has("Link_1"), d.links_rt.has("Link_2"), d.links_rt.has("Link_3")]
	_check("football.modular_start", p1 != null and links3.call(p1) == [true, true, true] and p1.active_rig != null and p1.parts.has("Hand_L"),
		"связки %s, деталей %d" % [links3.call(p1) if p1 != null else [], p1.parts.size() if p1 != null else 0])
	if p1 == null:
		return
	var full_max := p1.max_hp
	var full_n := p1.parts.size()
	p1.break_link("Link_3")
	p1.detach_part("Hand_L")
	p1.hp -= 6.0
	var swap := {}
	var on_swap := func(o: Doll, _n: Doll) -> void:
		if o.player_index == 0 and swap.is_empty():
			swap.merge({"hp": o.hp, "max": o.max_hp, "lost": o.lost_part_names()})
	sm.doll_replaced.connect(on_swap)
	await _force_goal(id, 0)
	await _until(func() -> bool: return sm.play_state == "kickoff", Tuning.SPORT_GOAL_PAUSE_S + 1.0)
	sm.doll_replaced.disconnect(on_swap)
	var p1g := _doll(0) as ModularDoll
	_check("football.modular_kept_after_goal", p1g != null and p1g != p1 and _lacks(p1g, ["Hand_L"]) and not p1g.uid_body.has("3") and p1g.parts.has("LowerArm_L")
		and links3.call(p1g) == [false, true, false] and p1g.active_rig != null,
		"связки %s, нет %s (было %s)" % [links3.call(p1g) if p1g != null else [], p1g.lost_part_names() if p1g != null else [], swap.get("lost", [])])
	_check("football.modular_hp_kept", p1g != null and not swap.is_empty() and is_equal_approx(p1g.max_hp, float(swap["max"])) and float(swap["max"]) < full_max
		and is_equal_approx(p1g.hp, float(swap["hp"])) and float(swap["hp"]) < float(swap["max"]), "запас %.1f/%.1f (было %s, целый %.0f)" % [p1g.hp, p1g.max_hp, swap, full_max])
	await _until(func() -> bool: return sm.play_state == "play", 3.0)
	p1g.knock_out()
	await _wait(Tuning.SPORT_KO_RESPAWN_S + 0.4)
	var p1k := _doll(0) as ModularDoll
	_check("football.modular_kept_after_ko", p1k != null and p1k != p1g and p1k.alive and _lacks(p1k, ["Hand_L"]) and links3.call(p1k) == [false, true, false]
		and p1k.parts.has("Head") and is_equal_approx(p1k.hp, p1k.max_hp), "связки %s, запас %.0f/%.0f" % [links3.call(p1k) if p1k != null else [], p1k.hp, p1k.max_hp])
	sm.restart()
	await _until(func() -> bool: return sm.play_state == "play", 3.0)
	var p1r := _doll(0) as ModularDoll
	_check("football.modular_new_match_whole", p1r != null and p1r.parts.size() == full_n and links3.call(p1r) == [true, true, true] and is_equal_approx(p1r.max_hp, full_max),
		"деталей %d из %d, связки %s, запас %.0f/%.0f" % [p1r.parts.size(), full_n, links3.call(p1r), p1r.hp, p1r.max_hp])


# ------------------------------------------------------------------ футбол

func _rules_football() -> void:
	var id := "football"
	var r: Dictionary = Tuning.SPORTS[id]
	await _load(id)
	# мяч над перекладиной за линией ворот — не гол; с крыши ворот скатывается в поле
	_put_ball(Vector2(float(r["goal_x"]) + 0.9, float(r["goal_h"]) + 1.6))
	await _wait(0.5)
	_check("football.above_bar_no_goal", sm.score == [0, 0], "счёт %s, мяч %s" % [sm.score, ball.pos2()])
	await _wait(6.0)
	var on_roof := ball.pos2().x > float(r["goal_x"]) and ball.pos2().y > float(r["goal_h"])
	_check("football.roof_rolls_off", not on_roof, "мяч %s" % ball.pos2())
	# мяч перед линией ворот — не гол
	sm.restart()
	await _until(func() -> bool: return sm.play_state == "play", 3.0)
	_put_ball(Vector2(float(r["goal_x"]) - 0.6, 0.5))
	await _wait(0.4)
	_check("football.before_line_no_goal", sm.score == [0, 0], "счёт %s" % [sm.score])
	# удар телом: кукла с разбега выбивает мяч
	sm.restart()
	await _until(func() -> bool: return sm.play_state == "play", 3.0)
	_put_ball(Vector2(-2.5, 1.0))
	await _wait(0.6)
	var p1 := _doll(0)
	p1.external_input = true
	p1.input_vec = Vector2(1.0, 0.0)
	var x0 := ball.pos2().x
	var t0 := ball.touches
	await _until(func() -> bool: return ball.touches > t0, 3.0)
	await _wait(0.5)
	p1.input_vec = Vector2.ZERO
	_check("football.body_kick", ball.touches > t0 and ball.last_touch == p1 and ball.pos2().x > x0 + 0.5,
		"касаний %d, мяч x %.1f → %.1f, скорость %.1f" % [ball.touches - t0, x0, ball.pos2().x, ball.max_speed_seen])


# ------------------------------------------------------------------ баскетбол

func _rules_basketball() -> void:
	var id := "basketball"
	var r: Dictionary = Tuning.SPORTS[id]
	await _load(id)
	var hx := float(r["hoop_x"])
	var hy := float(r["hoop_y"])
	# снизу вверх сквозь кольцо — не очко
	_put_ball(Vector2(hx, hy - 1.2), Vector2(0.0, 9.0))
	await _until(func() -> bool: return ball.pos2().y > hy + 0.3, 1.0)
	_check("basketball.up_through_no_score", sm.score == [0, 0] and ball.pos2().y > hy, "счёт %s, мяч y=%.1f" % [sm.score, ball.pos2().y])
	# мимо кольца (перед дужкой) сверху вниз — не очко
	sm.restart()
	await _until(func() -> bool: return sm.play_state == "play", 3.0)
	_put_ball(Vector2(hx - float(r["hoop_r"]) - 1.2, hy + 1.0), Vector2(0.0, -2.0))
	await _wait(1.0)
	_check("basketball.outside_ring_no_score", sm.score == [0, 0], "счёт %s" % [sm.score])
	# сверху в кольцо — очко, и мяч физически проходит кольцо (ниже него через секунду)
	_put_ball(Vector2(hx, hy + 1.5))
	await _until(func() -> bool: return int(sm.score[0]) == 1, 3.0)
	await _wait(0.8)
	_check("basketball.drop_scores", sm.score == [1, 0] and ball.pos2().y < hy, "счёт %s, мяч y=%.1f" % [sm.score, ball.pos2().y])


# ------------------------------------------------------------------ волейбол

func _rules_volleyball() -> void:
	var id := "volleyball"
	var r: Dictionary = Tuning.SPORTS[id]
	var nh := float(r["net_h"])
	await _load(id, 0.2, 0.6)
	# подача: первый ввод — над половиной команды 0
	sm.restart()
	await _until(func() -> bool: return sm.play_state == "kickoff", 1.0)
	_check("volleyball.first_serve_side", ball.global_position.x < -1.0 and ball.freeze, "мяч x=%.1f" % ball.global_position.x)
	await _until(func() -> bool: return sm.play_state == "play", 3.0)
	# сетка держит мяч ниже верха
	_put_ball(Vector2(-2.0, nh * 0.5), Vector2(9.0, 0.0))
	await _wait(0.5)
	_check("volleyball.net_blocks_ball", ball.pos2().x < 0.0, "мяч x=%.2f" % ball.pos2().x)
	# над сеткой мяч проходит стенку для кукол
	sm.restart()
	await _until(func() -> bool: return sm.play_state == "play", 3.0)
	_put_ball(Vector2(-2.0, nh + 2.5), Vector2(9.0, 1.0))
	await _wait(0.5)
	_check("volleyball.ball_passes_barrier", ball.pos2().x > 0.8, "мяч x=%.2f" % ball.pos2().x)
	# куклу стенка над сеткой не пускает
	sm.restart()
	await _until(func() -> bool: return sm.play_state == "play", 3.0)
	_put_ball(Vector2(-9.0, 8.0))
	var p1 := _doll(0)
	p1.external_input = true
	var max_x := -INF
	for i in int(5.0 / TICK):
		p1 = _doll(0)
		if p1 == null:
			break
		p1.external_input = true
		p1.input_vec = Vector2(1.0, 0.75 if p1.centre_of_mass().y < nh + 2.0 else 0.0)
		max_x = maxf(max_x, p1.centre_of_mass().x)
		if sm.play_state != "play":
			break
		await get_tree().physics_frame
	_check("volleyball.doll_stays_on_side", max_x < 0.3, "P1 max x=%.2f" % max_x)


# ------------------------------------------------------------------ матч ботов

func _bot_match(id: String, max_s: float, trace := false) -> void:
	await _load(id, 0.5, Tuning.SPORT_KICKOFF_S, true)
	var p1 := _doll(0)
	var b := SportBrain.new()
	b.name = "SportBrain"
	p1.add_child(b)
	p1.external_input = true
	var t := 0.0
	var escaped := 0
	var speed_max := 0.0
	var touches0 := ball.touches
	var kos := 0
	sm.ko.connect(func(_v: Doll, _a: Node, _r: Dictionary) -> void: kos += 1)
	var bx := Tuning.SPORT_FIELD_HALF_W + 0.6
	while sm.phase != Match.Phase.OVER and t < max_s:
		await get_tree().physics_frame
		t += TICK
		var p := ball.pos2()
		if is_nan(p.x) or absf(p.x) > bx or p.y < -0.6 or p.y > Tuning.SPORT_FIELD_H + 0.6:
			escaped += 1
		speed_max = maxf(speed_max, ball.linear_velocity.length())
		if trace and int(t / TICK) % 30 == 0:   # trace=1: раз в полсекунды — мяч и боты (состояние, позиция)
			var line := "    t=%5.1f %s мяч (%5.1f, %4.1f) v=%4.1f" % [t, sm.play_state, p.x, p.y, ball.linear_velocity.length()]
			for d in sm.dolls():
				var br := (d as Doll).get_node_or_null("SportBrain") as SportBrain
				var c := (d as Doll).centre_of_mass()
				line += "  P%d %s (%5.1f, %4.1f)" % [(d as Doll).player_index + 1, br.state if br != null else "-", c.x, c.y]
			print(line)
	var info := {"sim_s": snappedf(t, 0.1), "clock_s": snappedf(sm.fight_time, 0.1), "score": sm.score.duplicate(), "goals": sm.goals.duplicate(true),
		"reason": String(over_results.get("reason", "")), "touches": ball.touches - touches0, "ball_rescues": sm.ball_rescues,
		"ball_speed_max": snappedf(speed_max, 0.01), "kos": kos, "escaped_ticks": escaped, "parts_lost": {}}
	for d in sm.dolls():   # к концу матча: чего у куклы нет (между розыгрышами не чинится — Tuning.SPORT_KEEP_DAMAGE)
		info["parts_lost"]["P%d" % ((d as Doll).player_index + 1)] = (d as Doll).lost_part_names()
	report["sports"][id]["bots"] = info
	var total := int(sm.score[0]) + int(sm.score[1])
	_check(id + ".bots_match_ends", sm.phase == Match.Phase.OVER, "за %.0f с игры, причина «%s»" % [sm.fight_time, info["reason"]])
	_check(id + ".bots_score", total >= 1, "счёт %s за %.0f с, касаний %d, нокаутов %d, оторвано %s" % [sm.score, sm.fight_time, info["touches"], kos, info["parts_lost"]])
	_check(id + ".bots_ball_in_hall", escaped == 0, "тиков вне зала: %d" % escaped)
	_check(id + ".bots_ball_speed_cap", speed_max <= Tuning.SPORT_BALL_MAX_SPEED + 0.5, "макс %.1f м/с (потолок %.1f)" % [speed_max, Tuning.SPORT_BALL_MAX_SPEED])
