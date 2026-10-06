## Матч «Гольф: кукла — мяч» (docs/plan-demo/GOLF.md, MODES_PACK.md §3; автор 06.10: «гольф не понимаю, как это может быть прикольно
## тут, подумай» — план: весело, только если мяч — сама кукла). Наследник Match: от него регистрация кукол, DollCombat (толчки кукол
## друг о друга), эффекты и звук, отсчёт. Своё:
##   • кукла — мяч: всегда обмякшая (Doll.stun — мышц нет), без управления (control_enabled = false), урона нет (incoming_mult = 0),
##     дамп всех деталей один Tuning.GOLF_DAMP (Doll.damp_override), предел полёта поднят (set_flight_cap) — удар и взрыв не режутся;
##   • удар (shoot): из состояния AIM, сила 0..1 (полоска — GolfShot.power_at), направление — прицел; одинаковая скорость всем деталям
##     + кувырок (GolfShot.launch). Удары все бьют одновременно, без очереди;
##   • поправка в полёте (nudge): одна за удар — добавка GOLF_NUDGE_DV м/с в сторону ввода; дальше до конца удара — только ragdoll;
##   • конец удара: ЦМ медленнее GOLF_REST_SPEED GOLF_REST_S подряд или через GOLF_SHOT_MAX_S — следующий удар с этого места; в столбе пара
##     кукла висит и качается — там порог GOLF_HOVER_REST_SPEED;
##   • яма (GolfCourse.in_hazard по ЦМ) или вылет — +GOLF_PENALTY и кукла назад на место прошлого удара (GolfShot.place);
##   • лунка: ЦМ в чаше GOLF_CUP_HOLD_S подряд — засчитано (кукла уходит с поля до следующей лунки); выбили раньше — счёт заново;
##     в чаше скорость деталей гаснет (GOLF_CUP_GRIP — «сетка»);
##   • прочность суставов (клавиша C, JointBreak): деталь сменила скорость за тик больше GOLF_BREAK_DV — износ её сустава
##     (Doll._wear_joint); потерял деталь за удар — +1 в конце удара;
##   • больше пар + GOLF_CAP_OVER_PAR ударов — лунка закрыта для игрока (пар + CAP + 1); лунка идёт не дольше GOLF_HOLE_MAX_S;
##   • три лунки подряд (GolfCourse.build_hole), пауза GOLF_HOLE_PAUSE_S с карточкой, потом итоги (match_over, build_results — места
##     по сумме ударов).
## Фазы Match: COUNTDOWN — отсчёт лунки, FIGHT — лунка идёт, OVER — итоги. play_state: countdown | play | hole_end | over.
## Боты: GolfBrain ребёнком куклы — матч спрашивает у него удар (plan) и поправку (nudge_dir).
## Журналы для проб: shots ({hole, pi, stroke, power, dir, origin, end, reason, t}), holes_log ({hole, pi, strokes, par, holed}),
## penalties ({hole, pi, reason}).
class_name GolfMatch
extends Match

signal hole_started(hole_i: int, par: int)
signal hole_over(hole_i: int)
signal shot_taken(d: Doll, strokes: int, power: float)
signal shot_ended(d: Doll, reason: String)
signal holed(d: Doll, strokes: int, par: int)
signal penalized(d: Doll, reason: String, strokes: int)
signal nudged(d: Doll)
signal strokes_changed(player_index: int, strokes: int)

enum S { AIM, FLIGHT, HOLED }
const STATE_NAMES := ["aim", "flight", "holed"]
const BOT_NAME := "GolfBrain"
const SHOVE_FX_MIN_SPEED := 2.5
const OUT_Y := -2.0                 # ЦМ ниже — «за картой» (под полом)
const PARK := Vector3(0.0, -40.0, 0.0)

@export var course_path: NodePath
@export var start_hole := 0
@export var holes_n := 3
## Сид случайностей ботов; 0 — каждый раз новый.
@export var rng_seed := 0

var course: GolfCourse
var hole_i := 0
var play_state := "idle"
var hole_time := 0.0
## player_index → состояние игрока (Dictionary, поля — _new_player).
var players: Dictionary = {}
var shots: Array = []
var holes_log: Array = []
var penalties: Array = []
## Наибольшая смена скорости детали за тик (м/с) при включённой прочности суставов — для проб и подбора GOLF_BREAK_DV.
var max_impact_dv := 0.0
## Пробы: сколько раз за матч деталь сменила скорость за тик сильнее порога — по целым м/с (ключ — м/с, значение — раз).
var impact_hist: Dictionary = {}
## Пробы: в журнал удара пишется путь ЦМ и скорость каждые 0.5 с (поле "path").
var trace_shots := false
var _hole_end_left := -1.0
var _rng := RandomNumberGenerator.new()
var _restart_pending := false
var _in_tick := false
var _respawn_at: Dictionary = {}    # player_index → Vector3 (ноги новой куклы) — возврат после KO


func _ready() -> void:
	time_limit_s = 1.0e9     # часов нет: лунка кончается, когда все в чашах
	hard_timeout_s = 1.0e9
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	super._ready()
	crit_enabled = false


func _find_course() -> GolfCourse:
	if course != null and is_instance_valid(course):
		return course
	var c: Node = get_node_or_null(course_path) if course_path != NodePath() else null
	if c == null and get_parent() != null:
		for s in get_parent().get_children():
			if s is GolfCourse:
				c = s
				break
	course = c as GolfCourse
	return course


# --- куклы ---

static func _new_player() -> Dictionary:
	return {"doll": null, "state": S.AIM, "strokes": 0, "card": [], "origin": Vector3.ZERO, "shot_t": 0.0, "rest_t": 0.0, "cup_t": 0.0,
		"nudge_used": false, "lost": false, "charging": false, "charge_t": 0.0, "aim": Vector2(1.0, 1.0).normalized(), "think": -1.0,
		"picked": false, "prev_v": {}, "ko": false}


func register(d: Doll) -> void:
	super.register(d)
	d.incoming_mult = 0.0
	d.control_enabled = false
	_golfify(d)
	var pi := d.player_index
	if not players.has(pi):
		players[pi] = _new_player()
		(players[pi] as Dictionary)["aim"] = _default_aim(d)
	players[pi]["doll"] = d
	players[pi]["prev_v"] = {}
	if not d.part_detached.is_connected(_on_part_lost):
		d.part_detached.connect(_on_part_lost.bind(d))


## Кукла-мяч: обмякшая (стан без конца), дамп деталей один, гравитация обычная (ДРАЙВ режет её у кукол — в гольфе нет), полёт не режется.
func _golfify(d: Doll) -> void:
	var k := Tuning.GOLF_DAMP
	d.damp_override = {"core": k, "limb": k, "flight_core": k, "flight_limb": k, "brake": 0.0}
	for b in d.parts.values():
		var rb := b as RigidBody3D
		if rb != null:
			rb.linear_damp = k
			rb.gravity_scale = 1.0
	if d.alive:
		d.stun(1.0e6)
		d.set_flight_cap(Tuning.GOLF_FLIGHT_CAP, 2.0)


func _default_aim(d: Doll) -> Vector2:
	var c := _find_course()
	if c != null and c.cup != null:
		var com := d.centre_of_mass()
		return Vector2(signf(c.cup.global_position.x - com.x) if absf(c.cup.global_position.x - com.x) > 0.1 else 1.0, 1.0).normalized()
	return Vector2(1.0, 1.0).normalized()


## Точка появления: возврат после KO, иначе места старта текущей лунки по player_index.
func spawn_point_for(d: Doll) -> Vector3:
	if _respawn_at.has(d.player_index):
		return _respawn_at[d.player_index]
	var c := _find_course()
	if c != null and not c.data.is_empty():
		var slots := c.tee_slots(maxi(players.size(), Tuning.GOLF_PLAYERS))
		return slots[clampi(d.player_index, 0, slots.size() - 1)]
	return super.spawn_point_for(d)


func doll_of_index(pi: int) -> Doll:
	var p: Dictionary = players.get(pi, {})
	var d: Variant = p.get("doll")
	return d as Doll if d != null and is_instance_valid(d) else null


func player_of(d: Doll) -> Dictionary:
	return players.get(d.player_index, {}) if d != null else {}


func is_bot(d: Doll) -> bool:
	return d != null and d.external_input and d.get_node_or_null(BOT_NAME) != null


func state_of(d: Doll) -> String:
	var p := player_of(d)
	return STATE_NAMES[int(p["state"])] if not p.is_empty() else ""


func strokes_of(pi: int) -> int:
	return int(players[pi]["strokes"]) if players.has(pi) else 0


## Сумма ударов игрока по сыгранным лункам (+ текущая, если она ещё идёт).
func total_of(pi: int) -> int:
	if not players.has(pi):
		return 0
	var t := 0
	for s in players[pi]["card"]:
		t += int(s)
	if play_state != "over" and (players[pi]["card"] as Array).size() < hole_i - start_hole + 1:
		t += int(players[pi]["strokes"])
	return t


func par() -> int:
	return course.par() if course != null else 3


func par_total(upto := -1) -> int:
	var n := holes_n if upto < 0 else upto
	var t := 0
	for i in n:
		t += int(Tuning.GOLF_PARS[clampi(start_hole + i, 0, Tuning.GOLF_PARS.size() - 1)])
	return t


func cap() -> int:
	return par() + Tuning.GOLF_CAP_OVER_PAR


func power_of(pi: int) -> float:
	var p: Dictionary = players.get(pi, {})
	if p.is_empty() or not bool(p["charging"]):
		return 0.0
	return GolfShot.power_at(float(p["charge_t"]))


# --- фазы ---

func begin() -> void:
	hole_i = start_hole
	var c := _find_course()
	if c != null and c.hole_i != hole_i:
		c.build_hole(hole_i)
	shots.clear()
	holes_log.clear()
	penalties.clear()
	for pi in players:
		var d: Variant = players[pi]["doll"]
		var aim: Vector2 = players[pi]["aim"]
		players[pi] = _new_player()
		players[pi]["doll"] = d
		players[pi]["aim"] = aim
	play_state = "countdown"
	super.begin()
	for d in dolls():
		_golfify(d as Doll)
	hole_started.emit(hole_i, par())


## R / «Заново»: куклы пересоздаются только в своём тике (как BombMatch.restart — мембрана купола не должна увидеть вынутые детали).
func restart() -> void:
	if not _in_tick:
		_restart_pending = true
		return
	_restart_pending = false
	hole_i = start_hole
	_respawn_at.clear()
	var c := _find_course()
	if c != null:
		c.build_hole(hole_i)   # старт лунки — до пересоздания кукол (spawn_point_for)
	super.restart()


func _start_fight() -> void:
	for d in dolls():
		var dd := d as Doll
		dd.reset_for_match()
		dd.control_enabled = false
		var c := combat_of(dd)
		if c != null:
			c.reset()
		_golfify(dd)
	hole_time = 0.0
	_set_phase(Phase.FIGHT)
	play_state = "play"
	for pi in players:
		var p: Dictionary = players[pi]
		p["state"] = S.AIM
		var d := doll_of_index(pi)
		if d != null:
			p["origin"] = d.centre_of_mass()
			p["aim"] = _default_aim(d)
			p["think"] = _brain(d).think_s() + Tuning.GOLF_BOT_FIRST_S if is_bot(d) else -1.0
	announce.emit(tr("ЛУНКА %d") % (hole_i + 1), ANNOUNCE_COLORS["fight"], "fight")


func _physics_process(delta: float) -> void:
	_scan_t += delta
	if _scan_t >= SCAN_INTERVAL_S:
		_scan_t = 0.0
		_scan_dolls()
	if _restart_pending:
		_in_tick = true
		restart()
		_in_tick = false
		return
	if not _started:
		return
	match phase:
		Phase.COUNTDOWN:
			var n := int(ceil(_countdown_left))
			if n != _countdown_shown and n > 0:
				_countdown_shown = n
				announce.emit(str(n), ANNOUNCE_COLORS["countdown"], "countdown")
			_countdown_left -= delta
			if _countdown_left <= 0.0:
				_start_fight()
		Phase.FIGHT, Phase.SUDDEN_DEATH:
			fight_time += delta
			match play_state:
				"play":
					_tick_play(delta)
				"hole_end":
					_hole_end_left -= delta
					if _hole_end_left <= 0.0:
						if hole_i + 1 < start_hole + holes_n and hole_i + 1 < GolfCourse.hole_count():
							_next_hole()
						else:
							_finish("holes")


func stasis_allowed() -> bool:
	return false   # гольф без СТАЗИСА: удар — один щелчок, время ждать некому


func _check_over() -> void:
	pass


func _finish(reason: String) -> void:
	play_state = "over"
	super._finish(reason)


# --- лунка ---

func _tick_play(delta: float) -> void:
	hole_time += delta
	if course != null:
		course.tick(delta, dolls())
	for pi in players:
		_tick_player(players[pi], delta)
	var all_done := true
	for pi in players:
		if doll_of_index(pi) != null and int(players[pi]["state"]) != S.HOLED:
			all_done = false
	if not all_done and hole_time >= Tuning.GOLF_HOLE_MAX_S:
		for pi in players:
			if int(players[pi]["state"]) != S.HOLED:
				_pick_up(players[pi])
		all_done = true
	if all_done:
		_end_hole()


func _tick_player(p: Dictionary, delta: float) -> void:
	var d: Doll = p["doll"] if p["doll"] != null and is_instance_valid(p["doll"]) else null
	if d == null or int(p["state"]) == S.HOLED:
		return
	if not d.alive or bool(p["ko"]):
		_respawn_ko(p)
		return
	if not d.flight_cap_active():
		d.set_flight_cap(Tuning.GOLF_FLIGHT_CAP, 2.0)
	var com := d.centre_of_mass()
	var c2 := Vector2(com.x, com.y)
	if JointBreak.on:
		_wear(p, d)
	if course != null and (course.in_hazard(c2) or com.y < OUT_Y or absf(com.x) > 30.0 or com.y > 40.0):
		_penalty(p, "hazard")
		return
	if course != null and course.cup != null and course.cup.contains(c2):
		p["cup_t"] = float(p["cup_t"]) + delta
		_cup_grip(d, delta)
		if float(p["cup_t"]) >= Tuning.GOLF_CUP_HOLD_S:
			_hole_out(p)
			return
	else:
		p["cup_t"] = 0.0
	match int(p["state"]):
		S.AIM:
			if is_bot(d):
				if float(p["cup_t"]) > 0.0:
					return   # лежит в чаше — ждёт засчитывания
				p["think"] = float(p["think"]) - delta
				if float(p["think"]) <= 0.0:
					var plan := _brain(d).plan(course, d)
					p["aim"] = plan["dir"]
					if shoot(d, plan["dir"], float(plan["power"])):
						p["target"] = plan["target"]
						shots[-1]["target"] = [snappedf((plan["target"] as Vector2).x, 0.1), snappedf((plan["target"] as Vector2).y, 0.1)]
			elif bool(p["charging"]):
				p["charge_t"] = float(p["charge_t"]) + delta
		S.FLIGHT:
			p["shot_t"] = float(p["shot_t"]) + delta
			if trace_shots and int(round(float(p["shot_t"]) / delta)) % 30 == 0:
				for i in range(shots.size() - 1, -1, -1):
					if int(shots[i]["pi"]) == d.player_index:
						if not shots[i].has("path"):
							shots[i]["path"] = []
						(shots[i]["path"] as Array).append([snappedf(c2.x, 0.1), snappedf(c2.y, 0.1), snappedf(d.com_velocity().length(), 0.01)])
						break
			if is_bot(d) and not bool(p["nudge_used"]) and float(p["shot_t"]) > 0.4:
				var nd := _brain(d).nudge_dir(course, d, p.get("target", course.cup.aim_point()))
				if nd != Vector2.ZERO:
					nudge(d, nd)
			var rest_v := Tuning.GOLF_HOVER_REST_SPEED if course != null and course.in_vent(c2) else Tuning.GOLF_REST_SPEED
			if d.com_velocity().length() < rest_v:
				p["rest_t"] = float(p["rest_t"]) + delta
			else:
				p["rest_t"] = 0.0
			if float(p["rest_t"]) >= Tuning.GOLF_REST_S and float(p["shot_t"]) >= 0.3:
				_end_shot(p, "rest")
			elif float(p["shot_t"]) >= Tuning.GOLF_SHOT_MAX_S:
				_end_shot(p, "time")


func _brain(d: Doll) -> GolfBrain:
	var b := d.get_node_or_null(BOT_NAME) as GolfBrain
	if b != null and rng_seed != 0 and not b.has_meta("seeded"):
		b.rng.seed = _rng.randi()
		b.set_meta("seeded", true)
	return b


## Удар: кукла d в прицеле (AIM), лунка идёт. dir — направление, power 0..1. true — запущена.
func shoot(d: Doll, dir: Vector2, power: float) -> bool:
	var p := player_of(d)
	if p.is_empty() or play_state != "play" or int(p["state"]) != S.AIM or not d.alive:
		return false
	p["strokes"] = int(p["strokes"]) + 1
	p["origin"] = d.centre_of_mass()
	p["state"] = S.FLIGHT
	p["shot_t"] = 0.0
	p["rest_t"] = 0.0
	p["nudge_used"] = false
	p["lost"] = false
	p["charging"] = false
	p["charge_t"] = 0.0
	var n := dir.normalized() if dir.length_squared() > 1e-6 else Vector2.UP
	p["aim"] = n
	GolfShot.launch(d, n, power)
	d.set_flight_cap(Tuning.GOLF_FLIGHT_CAP, Tuning.GOLF_SHOT_MAX_S + 2.0)
	_snap_prev(p, d)
	var o: Vector3 = p["origin"]
	shots.append({"hole": hole_i, "pi": d.player_index, "stroke": int(p["strokes"]), "power": snappedf(power, 0.001),
		"dir": [snappedf(n.x, 0.001), snappedf(n.y, 0.001)], "origin": [snappedf(o.x, 0.01), snappedf(o.y, 0.01)], "t": snappedf(hole_time, 0.01)})
	shot_taken.emit(d, int(p["strokes"]), power)
	strokes_changed.emit(d.player_index, int(p["strokes"]))
	return true


## Поправка в полёте: одна за удар. dir — сторона ввода (нулевой — не тратится). true — сделана.
func nudge(d: Doll, dir: Vector2) -> bool:
	var p := player_of(d)
	if p.is_empty() or int(p["state"]) != S.FLIGHT or bool(p["nudge_used"]) or dir.length() < 0.1:
		return false
	p["nudge_used"] = true
	p["rest_t"] = 0.0
	var n := dir.normalized()
	GolfShot.add_velocity(d, Vector3(n.x, n.y, 0.0) * Tuning.GOLF_NUDGE_DV)
	_snap_prev(p, d)
	d.dashed.emit()   # звук ускорения (DollAudio)
	if not shots.is_empty():
		for i in range(shots.size() - 1, -1, -1):
			if int(shots[i]["pi"]) == d.player_index:
				shots[i]["nudge"] = [snappedf(n.x, 0.01), snappedf(n.y, 0.01)]
				break
	nudged.emit(d)
	return true


# --- ввод людей (площадка) ---

func charge_start(pi: int) -> void:
	var p: Dictionary = players.get(pi, {})
	if p.is_empty() or play_state != "play" or int(p["state"]) != S.AIM:
		return
	p["charging"] = true
	p["charge_t"] = 0.0


func charge_release(pi: int) -> void:
	var p: Dictionary = players.get(pi, {})
	if p.is_empty() or not bool(p["charging"]):
		return
	var pw := GolfShot.power_at(float(p["charge_t"]))
	p["charging"] = false
	var d := doll_of_index(pi)
	if d != null:
		shoot(d, p["aim"], pw)


func set_aim(pi: int, dir: Vector2) -> void:
	if players.has(pi) and dir.length_squared() > 1e-6:
		players[pi]["aim"] = dir.normalized()


func turn_aim(pi: int, radians: float) -> void:
	if players.has(pi):
		players[pi]["aim"] = (players[pi]["aim"] as Vector2).rotated(radians)


func nudge_input(pi: int, dir: Vector2) -> bool:
	var d := doll_of_index(pi)
	return nudge(d, dir) if d != null else false


# --- конец удара, штрафы, лунка ---

func _end_shot(p: Dictionary, reason: String) -> void:
	var d: Doll = p["doll"]
	p["state"] = S.AIM
	p["rest_t"] = 0.0
	var com := d.centre_of_mass()
	for i in range(shots.size() - 1, -1, -1):
		if int(shots[i]["pi"]) == d.player_index and not shots[i].has("reason"):
			shots[i]["reason"] = reason
			shots[i]["end"] = [snappedf(com.x, 0.01), snappedf(com.y, 0.01)]
			shots[i]["dur"] = snappedf(float(p["shot_t"]), 0.01)
			break
	shot_ended.emit(d, reason)
	if bool(p["lost"]):
		p["lost"] = false
		_add_penalty(p, "part")
	if int(p["strokes"]) >= cap():
		_pick_up(p)
		return
	if is_bot(d):
		p["think"] = _brain(d).think_s()


func _add_penalty(p: Dictionary, reason: String) -> void:
	var d: Doll = p["doll"]
	p["strokes"] = int(p["strokes"]) + Tuning.GOLF_PENALTY
	penalties.append({"hole": hole_i, "pi": d.player_index, "reason": reason, "t": snappedf(hole_time, 0.01)})
	penalized.emit(d, reason, int(p["strokes"]))
	strokes_changed.emit(d.player_index, int(p["strokes"]))


## Яма / вылет: +1 и назад на место прошлого удара (ЦМ — в точку старта удара, чуть выше).
func _penalty(p: Dictionary, reason: String) -> void:
	var d: Doll = p["doll"]
	if int(p["state"]) == S.FLIGHT:
		for i in range(shots.size() - 1, -1, -1):
			if int(shots[i]["pi"]) == d.player_index and not shots[i].has("reason"):
				shots[i]["reason"] = reason
				shots[i]["dur"] = snappedf(float(p["shot_t"]), 0.01)
				break
		shot_ended.emit(d, reason)
	p["state"] = S.AIM
	p["rest_t"] = 0.0
	p["cup_t"] = 0.0
	p["charging"] = false
	var o: Vector3 = p["origin"]
	GolfShot.place(d, o + Vector3(0.0, 0.35, 0.0))
	_snap_prev(p, d)
	_add_penalty(p, reason)
	if bool(p["lost"]):
		p["lost"] = false
		_add_penalty(p, "part")
	if int(p["strokes"]) >= cap():
		_pick_up(p)
		return
	if is_bot(d):
		p["think"] = _brain(d).think_s()


func _hole_out(p: Dictionary) -> void:
	var d: Doll = p["doll"]
	if int(p["state"]) == S.FLIGHT:
		for i in range(shots.size() - 1, -1, -1):
			if int(shots[i]["pi"]) == d.player_index and not shots[i].has("reason"):
				shots[i]["reason"] = "holed"
				shots[i]["dur"] = snappedf(float(p["shot_t"]), 0.01)
				break
		shot_ended.emit(d, "holed")
	if bool(p["lost"]):
		p["lost"] = false
		_add_penalty(p, "part")
	p["state"] = S.HOLED
	p["charging"] = false
	(p["card"] as Array).append(int(p["strokes"]))
	holes_log.append({"hole": hole_i, "pi": d.player_index, "strokes": int(p["strokes"]), "par": par(), "holed": true,
		"t": snappedf(hole_time, 0.01)})
	if course != null and course.cup != null:
		course.cup.flash(colour_of(d.player_index))
	holed.emit(d, int(p["strokes"]), par())
	_park(d)


## Лунка закрыта для игрока (лимит ударов или времени): в карточку пар + CAP + 1.
func _pick_up(p: Dictionary) -> void:
	var d: Doll = p["doll"] if p["doll"] != null and is_instance_valid(p["doll"]) else null
	p["state"] = S.HOLED
	p["picked"] = true
	p["charging"] = false
	var s := cap() + 1
	p["strokes"] = s
	(p["card"] as Array).append(s)
	holes_log.append({"hole": hole_i, "pi": d.player_index if d != null else -1, "strokes": s, "par": par(), "holed": false,
		"t": snappedf(hole_time, 0.01)})
	if d != null:
		strokes_changed.emit(d.player_index, s)
		_park(d)


## Кукла ушла с поля до следующей лунки: не видна, заморожена, без столкновений, под полом.
func _park(d: Doll) -> void:
	d.visible = false
	for b in d.parts.values():
		var rb := b as RigidBody3D
		if rb == null or not is_instance_valid(rb):
			continue
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		rb.collision_layer = 0
		rb.collision_mask = 0
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		rb.freeze = true
	var c := d.centre_of_mass()
	for b in d.parts.values():
		var rb := b as RigidBody3D
		if rb != null and is_instance_valid(rb):
			rb.global_position += PARK - c
			rb.reset_physics_interpolation()


func _end_hole() -> void:
	play_state = "hole_end"
	_hole_end_left = Tuning.GOLF_HOLE_PAUSE_S
	hole_over.emit(hole_i)


func _next_hole() -> void:
	hole_i += 1
	_respawn_at.clear()
	course.build_hole(hole_i)
	ko_records.clear()
	_ko_order.clear()
	for d in dolls():
		respawn_doll(d)
	for pi in players:
		var p: Dictionary = players[pi]
		p["state"] = S.AIM
		p["strokes"] = 0
		p["cup_t"] = 0.0
		p["picked"] = false
		p["charging"] = false
		p["ko"] = false
	for d in dolls():
		(d as Doll).control_enabled = false
		var c := combat_of(d as Doll)
		if c != null:
			c.reset()
	play_state = "countdown"
	_set_phase(Phase.COUNTDOWN)
	_countdown_left = countdown_s
	_countdown_shown = -1
	hole_started.emit(hole_i, par())
	if _countdown_left <= 0.0:
		_start_fight()


## Выбыл (KO — только при «запасе из деталей» или оторванной голове): новая кукла на месте прошлого удара, +1.
func _respawn_ko(p: Dictionary) -> void:
	var d: Doll = p["doll"]
	var o: Vector3 = p["origin"]
	_respawn_at[d.player_index] = Vector3(o.x, o.y - 0.15, 0.0)
	p["ko"] = false
	p["state"] = S.AIM
	p["cup_t"] = 0.0
	var nd := respawn_doll(d)
	_respawn_at.erase(nd.player_index)
	nd.control_enabled = false
	nd.reset_for_match()
	_golfify(nd)
	_add_penalty(p, "lost")
	if is_bot(nd):
		p["think"] = _brain(nd).think_s()


func _on_doll_ko(_attacker: Node, _record: Dictionary, victim: Doll) -> void:
	if phase == Phase.OVER:
		return
	var p := player_of(victim)
	if not p.is_empty():
		p["ko"] = true


func _on_part_lost(_part_name: String, _by: Node, d: Doll) -> void:
	var p := player_of(d)
	if not p.is_empty() and int(p["state"]) == S.FLIGHT:
		p["lost"] = true


## «Сетка» чаши: скорость деталей гаснет (кукла не выпрыгивает от удара о дно).
func _cup_grip(d: Doll, delta: float) -> void:
	var k := exp(-Tuning.GOLF_CUP_GRIP * delta)
	for b in d.parts.values():
		var rb := b as RigidBody3D
		if rb != null and is_instance_valid(rb):
			rb.linear_velocity *= k


## Прочность суставов: резкая смена скорости детали за тик (удар о стену, пол, куклу) изнашивает её сустав.
func _wear(p: Dictionary, d: Doll) -> void:
	var prev: Dictionary = p["prev_v"]
	for n in d.parts.keys():
		var rb := d.parts[n] as RigidBody3D
		if rb == null or not is_instance_valid(rb):
			continue
		var v := rb.linear_velocity
		if prev.has(rb):
			var dv := (v - (prev[rb] as Vector3)).length()
			max_impact_dv = maxf(max_impact_dv, dv)
			if dv > 3.0:
				impact_hist[int(dv)] = int(impact_hist.get(int(dv), 0)) + 1
			if dv > Tuning.GOLF_BREAK_DV:
				d._wear_joint(String(n), (dv - Tuning.GOLF_BREAK_DV) * Tuning.GOLF_BREAK_WEAR / maxf(Tuning.JOINT_WEAR_MULT, 0.01), null)
		prev[rb] = v


func _snap_prev(p: Dictionary, d: Doll) -> void:
	var prev: Dictionary = {}
	for rb in d.parts.values():
		if rb != null and is_instance_valid(rb):
			prev[rb] = (rb as RigidBody3D).linear_velocity
	p["prev_v"] = prev


# --- удары кукол друг о друга ---

## Толчок куклы о куклу: урона нет, но вспышка с пылью (как в бомбе) — видно, что сбили.
func on_hit(victim: Doll, attacker: Node, damage: float, kind: String, position: Vector3, combo_n: int, double_blow: bool, weapon_id: String, speed: float) -> void:
	super.on_hit(victim, attacker, damage, kind, position, combo_n, double_blow, weapon_id, speed)
	if damage <= 0.0 and kind != "environment" and speed >= SHOVE_FX_MIN_SPEED:
		ImpactFx.spawn_impact(self, position, Vector3.UP, clampf(2.0 + speed * 0.7, 3.0, 10.0), kind, FxMaterial.RUBBER)


static func colour_of(pi: int) -> Color:
	return Tuning.PLAYER_COLORS[posmod(pi, Tuning.PLAYER_COLORS.size())]


# --- итоги ---

## Места по сумме ударов (меньше — выше; равные делят место), победитель — единственный лучший. card: {pi: [удары по лункам]}.
func build_results(reason: String = "holes") -> Dictionary:
	var r := super.build_results(reason)
	var all := dolls()
	all.sort_custom(func(a: Doll, b: Doll) -> bool:
		var ta := total_of(a.player_index)
		var tb := total_of(b.player_index)
		if ta != tb:
			return ta < tb
		return a.player_index < b.player_index)
	var ranks: Array = []
	for i in all.size():
		ranks.append(ranks[i - 1] if i > 0 and total_of((all[i] as Doll).player_index) == total_of((all[i - 1] as Doll).player_index) else i)
	var winner: Doll = null
	if all.size() == 1 or (all.size() >= 2 and int(ranks[1]) != 0):
		winner = all[0]
	var card := {}
	var totals := {}
	for pi in players:
		card[pi] = (players[pi]["card"] as Array).duplicate()
		totals[pi] = total_of(pi)
	var pars: Array = []
	for i in holes_n:
		pars.append(int(Tuning.GOLF_PARS[clampi(start_hole + i, 0, Tuning.GOLF_PARS.size() - 1)]))
	var medals: Dictionary = r.get("medals", {})
	medals.erase("Winner")
	medals.erase("Survivor")
	if winner != null:
		medals["Winner"] = winner
	r["places"] = all
	r["ranks"] = ranks
	r["winner"] = winner
	r["draw"] = winner == null
	r["medals"] = medals
	r["card"] = card
	r["totals"] = totals
	r["pars"] = pars
	r["par_total"] = par_total()
	r["penalties"] = penalties.size()
	return r
