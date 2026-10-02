## Проба событий купола: голосование зрителей (этап 15) и выход бойца (этап 16) — docs/plan-demo/15-audience-vote.md, 16-fighter-entrance.md.
##   godot --headless --path godot --fixed-fps 60 res://tests/arena_events_probe.tscn
## Сцена — бой кампании scenes/campaign/campaign_fight.tscn (купол Old NULL Hall), соперник стоит (мозг выключен), время голосования
## укорочено. Проверки (exit 1, если не прошли), отчёт — tests/arena_events_probe_report.json:
##   vote_starts        через first_s боя: голосование, три разных варианта, панель видна, табло «AUDIENCE EVENT»
##   vote_result        через duration_s: проценты — целые, сумма 100, победил наибольший, поле включило победителя (или обломки упали)
##   vote_restore       через effect_s: поле снова по регламенту (0.20 G вниз), обломки убраны, табло «NULL FIELD», голосование молчит
##   vote_sudden_death  Sudden Death — второе голосование; больше VOTE_MAX_PER_MATCH за матч не бывает
##   vote_twenty        20 голосований подряд (разные зёрна, короткие времена): каждое применило победителя и вернуло регламент,
##                      ни одно не зависло и не наложилось
##   vote_anomaly       бой с anomaly "vote_mismatch": LOW GRAVITY 74 %, а поле — GRAVITY INVERSION (вверх), табло мигает
##   entrance_runs      выход двух бойцов ≤ 12 с; оба прошли мембрану, после выхода — внутри купола, отпущены, HP полные, ударов
##                      не было, матч начал отсчёт; камера выхода была текущей, после — боевая; свет гас и вернулся
##   entrance_skip      две кнопки: пропуск ≤ 1 с, бойцы на точках спавна ±1 м, отпущены, отсчёт начался
extends Node

const FIGHT := preload("res://scenes/campaign/campaign_fight.tscn")
const DT := 1.0 / 60.0

var checks: Array = []
var info := {}


func _ready() -> void:
	await _run()


func _run() -> void:
	await _vote_basic()
	await _vote_twenty()
	await _vote_anomaly()
	await _entrance()
	await _entrance_skip()
	_finish()


# ------------------------------------------------------------------ помощники

func _fight(r: Dictionary, entrance: bool, still_rival := true) -> Node:
	var f := FIGHT.instantiate()
	f.call("setup", CampaignLeague.start_blueprint(), CampaignLeague.rival_blueprint(CampaignLeague.LOCAL, r), r,
		CampaignLeague.rival_title(r), {"entrance": entrance})
	add_child(f)
	var m: Match = f.get_node("Match")
	m.feel_enabled = false
	if still_rival:
		var b: Node = f.get_node("P2/Brain")
		b.process_mode = Node.PROCESS_MODE_DISABLED
	return f


func _field(f: Node) -> NullField:
	return f.get_node("NullHall/Field") as NullField


func _board(f: Node) -> String:
	var l := f.get_node("NullHall").find_child("Text_NULL_FIELD", true, false) as Label3D
	return l.text if l != null else ""


func _secs(s: float) -> void:
	var n := int(ceil(s / DT))
	for i in n:
		await get_tree().physics_frame


func _until(cond: Callable, max_s: float) -> float:
	var t := 0.0
	while t < max_s and not bool(cond.call()):
		await get_tree().physics_frame
		t += DT
	return t


## Поле «сейчас нацелено» на: [g, dir] (цель плавной смены, а не текущее значение).
func _field_target(fl: NullField) -> Array:
	return [float(fl.get("_g_to")), (fl.get("_dir_to") as Vector2)]


func _matches(fl: NullField, g: float, dir: Vector2) -> bool:
	var tg: Array = _field_target(fl)
	var ok_g := absf(float(tg[0]) - g) < 0.01
	return ok_g and (g < 0.005 or (tg[1] as Vector2).distance_to(dir.normalized()) < 0.05)


func _applied_ok(v: AudienceVote, f: Node) -> bool:
	var id := String(v.result.get("applied", ""))
	if id == "debris":
		return v.debris.size() == Tuning.VOTE_DEBRIS_COUNT and v.debris.all(func(c: Node) -> bool: return is_instance_valid(c))
	var o: Dictionary = AudienceVote.INVERSION if id == "inversion" else {}
	for opt in v.options:
		if String(opt["id"]) == id:
			o = opt
	return not o.is_empty() and _matches(_field(f), float(o["g"]), o["dir"])


func _restored(v: AudienceVote, f: Node) -> bool:
	return v.state == "idle" and _matches(_field(f), Tuning.GRAVITY / Tuning.G_EARTH, Vector2(0.0, -1.0)) \
		and v.debris.is_empty() and _board(f) == "NULL FIELD"


# ------------------------------------------------------------------ голосование

func _vote_basic() -> void:
	var r: Dictionary = CampaignLeague.ladder()[0]
	var f := _fight(r, false)
	var v: AudienceVote = f.get_node("AudienceVote")
	v.first_s = 2.0
	v.duration_s = 1.5
	v.effect_s = 3.0
	v.rng_seed = 1234
	var m: Match = f.get_node("Match")
	await _until(func() -> bool: return v.state == "voting", Tuning.COUNTDOWN_S + 4.0)
	var ids := v.options.map(func(o: Dictionary) -> String: return String(o["id"]))
	var panel_box: Control = v.get_node("Panel/Box")
	_check("vote_starts", v.state == "voting" and ids.size() == 3 and ids[0] != ids[1] and ids[1] != ids[2] and ids[0] != ids[2]
		and panel_box.visible and _board(f) == "AUDIENCE EVENT" and absf(m.fight_time - v.first_s) < 0.2,
		"варианты %s на %.2f с боя, табло «%s»" % [ids, m.fight_time, _board(f)])
	await _until(func() -> bool: return v.state == "effect", 3.0)
	var pct: Array = v.result.get("pct", [])
	var sum := 0
	var best := 0
	for i in pct.size():
		sum += int(pct[i])
		if int(pct[i]) > int(pct[best]):
			best = i
	_check("vote_result", sum == 100 and String(v.result["winner"]) == ids[best] and String(v.result["applied"]) == String(v.result["winner"])
		and _applied_ok(v, f) and _board(f).ends_with("WINS"),
		"проценты %s, победил %s, включено %s, табло «%s»" % [pct, v.result.get("winner"), v.result.get("applied"), _board(f)])
	await _until(func() -> bool: return v.state == "idle", v.effect_s + 1.0)
	await _secs(0.1)
	_check("vote_restore", _restored(v, f), "поле → %s, обломков %d, табло «%s»" % [_field_target(_field(f)), v.debris.size(), _board(f)])
	# Sudden Death — второе голосование
	m.time_limit_s = m.fight_time + 0.5
	await _until(func() -> bool: return v.state == "voting", 3.0)
	var second := v.state == "voting" and m.phase == Match.Phase.SUDDEN_DEATH
	await _until(func() -> bool: return v.state == "idle", v.duration_s + v.effect_s + 2.0)
	v.start_vote()   # третье — только по SD-правилу: вручную можно, но движок сам больше не начинает
	v._abort()
	await _secs(1.0)
	_check("vote_sudden_death", second and v.votes_done == 2 and v.history.size() == 2 and v.state == "idle",
		"второе на SD %s, голосований %d, журнал %d" % [second, v.votes_done, v.history.size()])
	info["vote_history"] = v.history
	f.queue_free()
	await _secs(0.2)


func _vote_twenty() -> void:
	var r: Dictionary = CampaignLeague.ladder()[1]
	var f := _fight(r, false)
	var v: AudienceVote = f.get_node("AudienceVote")
	v.enabled = false   # движок не начинает сам — голосования по одному вручную
	v.duration_s = 0.1
	v.effect_s = 0.2
	await _until(func() -> bool: return (f.get_node("Match") as Match).phase == Match.Phase.FIGHT, Tuning.COUNTDOWN_S + 1.0)
	v.enabled = true
	v.votes_done = 1   # первое уже «было» — не мешает ручным
	var bad: Array = []
	var applied: Dictionary = {}
	for i in 20:
		v._rng.seed = 900 + i
		v.chaos = float(i % 5) / 4.0
		v.start_vote()
		var t1 := await _until(func() -> bool: return v.state == "effect", 1.0)
		var ok_apply := v.state == "effect" and _applied_ok(v, f)
		var t2 := await _until(func() -> bool: return v.state == "idle", 1.0)
		await _secs(0.05)
		var ok_back := _restored(v, f)
		applied[String(v.result.get("applied", "?"))] = int(applied.get(String(v.result.get("applied", "?")), 0)) + 1
		if not (ok_apply and ok_back) or t1 >= 1.0 or t2 >= 1.0:
			bad.append({"i": i, "apply": ok_apply, "back": ok_back, "result": v.result})
	info["vote_twenty"] = applied
	_check("vote_twenty", bad.is_empty() and applied.size() >= 4, "варианты %s, сбои %s" % [applied, bad])
	f.queue_free()
	await _secs(0.2)


func _vote_anomaly() -> void:
	var r: Dictionary = {}
	for x in CampaignLeague.ladder():
		if String((x as Dictionary).get("anomaly", "")) == "vote_mismatch":
			r = x
	var f := _fight(r, false)
	var v: AudienceVote = f.get_node("AudienceVote")
	v.first_s = 1.0
	v.duration_s = 1.0
	v.effect_s = 4.0
	await _until(func() -> bool: return v.state == "effect", Tuning.COUNTDOWN_S + 4.0)
	var fl := _field(f)
	var boards: Dictionary = {}
	for i in 60:
		await get_tree().physics_frame
		boards[_board(f)] = true
	var li := v.options.map(func(o: Dictionary) -> String: return String(o["id"])).find("low_gravity")
	_check("vote_anomaly", v.anomaly == "vote_mismatch" and li >= 0 and int(v.result["pct"][li]) == 74 and String(v.result["winner"]) == "low_gravity"
		and String(v.result["applied"]) == "inversion" and bool(v.result["anomaly"]) and _matches(fl, 0.35, Vector2(0.0, 1.0))
		and boards.has("GRAVITY INVERSION") and boards.has("LOW GRAVITY WINS"),
		"итог %s, поле → %s, табло %s" % [v.result, _field_target(fl), boards.keys()])
	f.queue_free()
	await _secs(0.2)


# ------------------------------------------------------------------ выход бойца

func _entrance() -> void:
	var r: Dictionary = CampaignLeague.ladder()[0]
	var f := _fight(r, true)
	var ent: FighterEntrance = f.get_node("Entrance")
	var m: Match = f.get_node("Match")
	var p1: Doll = f.get_node("P1")
	var p2: Doll = f.get_node("P2")
	var hall: Node = f.get_node("NullHall")
	var lamp: Light3D = null
	for l in hall.get_node("Lights").find_children("*", "Light3D", true, false):
		lamp = l
		break
	var lamp0 := lamp.light_energy if lamp != null else 0.0
	var hits := [0]
	m.hit.connect(func(_v: Doll, _a: Node, _d: float, _k: String, _p: Vector3) -> void: hits[0] += 1)
	var min_lamp := [lamp0]
	var cam_seen := [false]
	var t := 0.0
	while t < 16.0 and (ent.running or t < 0.2):
		await get_tree().physics_frame
		t += DT
		if lamp != null:
			min_lamp[0] = minf(min_lamp[0], lamp.light_energy)
		if ent.running and (f.get_node("EntranceCam") as Camera3D).is_current():
			cam_seen[0] = true
	var dur := ent.clock
	var steps := ent.timeline.filter(func(e: Dictionary) -> bool: return String(e["step"]) == "membrane").size()
	await _secs(0.6)
	var fl := _field(f)
	var inside := true
	var frozen := false
	for d in [p1, p2]:
		for rb in (d as Doll).parts.values():
			frozen = frozen or (rb as RigidBody3D).freeze
		var c := (d as Doll).centre_of_mass()
		inside = inside and float(fl.stretch_at(Vector2(c.x, c.y))[0]) < 0.0 and absf(c.z) < 0.2
	var hp_full := p1.hp >= p1.max_hp and p2.hp >= p2.max_hp
	var fight_cam := (f.get_node("Camera") as Camera3D).is_current()
	var lamp_back := lamp == null or absf(lamp.light_energy - lamp0) < 0.01 * maxf(lamp0, 1.0)
	info["entrance"] = {"clock": snappedf(dur, 0.01), "timeline": ent.timeline, "lamp0": lamp0, "lamp_min": min_lamp[0]}
	_check("entrance_runs", dur <= 12.0 and steps == 2 and inside and not frozen and hp_full and hits[0] == 0
		and (m.phase == Match.Phase.COUNTDOWN or m.phase == Match.Phase.FIGHT) and cam_seen[0] and fight_cam
		and (lamp == null or min_lamp[0] < lamp0 * 0.5) and lamp_back,
		"%.1f с, мембрана пройдена %d раз, внутри %s, заморожены %s, HP полные %s, ударов %d, фаза %d, камера выхода %s → боевая %s, свет %.2f → %.2f → %s" % [
		dur, steps, inside, frozen, hp_full, hits[0], m.phase, cam_seen[0], fight_cam, lamp0, min_lamp[0], lamp_back])
	f.queue_free()
	await _secs(0.3)


func _entrance_skip() -> void:
	var r: Dictionary = CampaignLeague.ladder()[1]
	var f := _fight(r, true)
	var ent: FighterEntrance = f.get_node("Entrance")
	var m: Match = f.get_node("Match")
	await _secs(1.0)
	for i in 2:
		var e := InputEventKey.new()
		e.physical_keycode = KEY_SPACE
		e.keycode = KEY_SPACE
		e.pressed = true
		get_viewport().push_input(e)
		await get_tree().physics_frame
	var t := await _until(func() -> bool: return not ent.running, 2.0)
	await _secs(0.1)
	var spawns: Array = f.get_node("NullHall").call("spawn_points")
	var near := true
	var frozen := false
	for i in 2:
		var d: Doll = f.get_node("P%d" % (i + 1))
		var c: Vector3 = d.parts["Torso"].global_position if d.parts.has("Torso") else d.centre_of_mass()
		near = near and Vector2(c.x - spawns[i].x, c.y - spawns[i].y).length() <= 1.0
		for rb in d.parts.values():
			frozen = frozen or (rb as RigidBody3D).freeze
	_check("entrance_skip", ent.skipped and t <= 1.0 and near and not frozen and m.phase == Match.Phase.COUNTDOWN,
		"пропуск %s за %.2f с, у спавна %s, заморожены %s, фаза %d" % [ent.skipped, t, near, frozen, m.phase])
	f.queue_free()
	await _secs(0.3)


# ------------------------------------------------------------------ отчёт

func _check(id: String, ok: bool, text: String) -> void:
	checks.append({"id": id, "ok": ok, "info": text})
	print("%s %s — %s" % ["PASS" if ok else "FAIL", id, text])


func _finish() -> void:
	var ok := true
	for c in checks:
		ok = ok and bool(c["ok"])
	var fa := FileAccess.open("res://tests/arena_events_probe_report.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify({"ok": ok, "checks": checks, "info": info}, "  "))
	fa.close()
	print("arena_events_probe: %s (%d checks)" % ["OK" if ok else "FAIL", checks.size()])
	get_tree().quit(0 if ok else 1)
