## Бот «Собери себя» (docs/plan-demo/SCAVENGER.md). Каркас — EnemyBrain (тяга с плавным разворотом, восприятие с задержкой,
## стан — молчит, выход из застревания, ускорение за Заряд), без EnemyLook. Цели — все живые куклы, кроме себя (все против всех).
## Приоритеты каждый тик:
##   • flee (уровни 2–3) — рядом (Tuning.SCAV_BOT_FEAR_M) соперник, у которого деталей больше на SCAV_BOT_FEAR_GAP: уходит от него,
##     по пути подбирая детали;
##   • fetch — деталей меньше want или нужная деталь ближе SCAV_BOT_PART_M: к ближайшей детали, которую можно прикрутить
##     (ScavMatch.token_wanted_by); не дотянулся за SCAV_BOT_GIVEUP_S — деталь в «бан» на SCAV_BOT_BAN_S;
##   • approach / retreat — наскок на соперника (как в «Охоте за головами»): выбирает того, у кого деталей меньше, с учётом
##     расстояния;
##   • idle — раунд не идёт: висит на месте.
## Загнанный в угол не бегает вечно: если в flee за FLEE_STALL_S не оторвался от сильного ещё на FLEE_GAIN_M (упёрся в стену, в угол
## арены или в настил снизу, или тот не отстаёт; эпизод не рвётся, пока сильный пропадает из виду меньше чем на FLEE_FORGET_S —
## иначе бот дёргается flee ↔ fetch у детали рядом с сильным, проба 23.10: 49 с у тележки), страх выключается на BRAVE_S — бот берёт детали и дерётся как обычно. Застревание — по площади, как у SquadBrain: под настилом выход
## вбок к центру арены и вниз, а не вверх (проба 23.10: бот 29–104 с жал вверх под настилом Свалки у края, bots_not_stuck).
## Уровень 1..3 — Tuning.SCAV_BOT_LEVELS; Match.respawn_doll создаёт мозг заново — уровень из default_level.
class_name ScavBrain
extends EnemyBrain

const NEAR_X_M := 1.3
const NEAR_Y_M := 1.2
const DASH_FROM_M := 2.5
const CLIMB_FROM_M := 0.8
const CLIMB_SCALE_M := 1.5
const FAR_DASH_M := 7.0
const PREY_PARTS_M := 2.0   # выбор цели: −1 деталь у соперника ≈ на 2 м ближе
const FLEE_STALL_S := 2.5   # в бегстве столько не оторвался от сильного ещё на FLEE_GAIN_M — загнан, страх выключается
const FLEE_GAIN_M := 1.0
const FLEE_FORGET_S := 3.0  # сильного не было рядом дольше — новый эпизод бегства; короче — тот же (дёрганье flee ↔ fetch у одной детали)
const BRAVE_S := 6.0
const STUCK_RADIUS_M := 0.8 # «жмёт, а топчется»: ЦМ не вышел из круга за STUCK_AREA_S
const STUCK_AREA_S := 2.0
## Выход из застревания по кругу: x — от центра арены «к центру» (+), y — вверх.
const UNSTICK_DIRS := [Vector2(0.9, -0.45), Vector2(0.6, 0.85), Vector2(-0.6, 0.85), Vector2(1.0, 0.0)]

static var default_level := 2

@export var level := -1

var sm: ScavMatch
var max_in := 0.92
var retreat_s := 1.3
var use_dash := true
var fear := true
var want_parts := 6
var goal_part: RigidBody3D = null
var _goal_t := 0.0
var _ban: Dictionary = {}   # instance_id жетона → время бана (до)
var _brave_until := -1.0
var _flee_best := 0.0
var _flee_anchor_t := 0.0
var _flee_seen_t := -100.0
var _stuck_anchor := Vector2.ZERO
var _stuck_anchor_t := 0.0
var _unstick_n := 0


func _setup() -> void:
	if _ready_done:
		return
	_ready_done = true
	doll.external_input = true
	arena = get_tree().get_first_node_in_group("arena")
	doll.damaged.connect(_on_damaged)
	doll.knocked_out.connect(func(_a: Node, _r: Dictionary) -> void: _on_ko())
	_brain_ready()


func _brain_ready() -> void:
	players_group = "scav_nobody"
	enemies_group = "scav_none"
	var lv := level if level > 0 else default_level
	var p: Dictionary = Tuning.SCAV_BOT_LEVELS.get(lv, Tuning.SCAV_BOT_LEVELS[2])
	max_in = float(p["max_in"])
	reaction_s = float(p["reaction_s"])
	aim_error_m = float(p["aim_error_m"])
	lead_s = float(p["lead_s"])
	retreat_s = float(p["retreat_s"])
	use_dash = bool(p["dash"])
	fear = bool(p["fear"])
	want_parts = int(p["want"])
	go("idle")


func _find_refs() -> void:
	if sm == null or not is_instance_valid(sm):
		sm = get_tree().get_first_node_in_group(Match.GROUP) as ScavMatch


## Цели для EnemyBrain (_pick_target — ближайшая): живые соперники. Своя оценка цели — в _prey().
func players() -> Array:
	_find_refs()
	if sm == null:
		return []
	var out: Array = []
	for d in sm.alive_dolls():
		if d != doll and (d as Node).is_inside_tree():
			out.append(d)
	return out


## Удержание веса: тяга куклы здесь ещё × thrust_mult (ход по числу деталей), иначе голый торс «подпрыгивает».
func hover_vec() -> Vector2:
	var thrust := Tuning.MOVE_FORCE_PER_KG * doll.thrust_mass() * maxf(doll.thrust_mult, 0.05)
	return (-gravity_vec() * doll.total_mass / maxf(thrust, 1.0)).limit_length(0.9)


## Ближайшая деталь, которую можно прикрутить (не в бане), ближе r — или null.
func nearest_part(r: float) -> RigidBody3D:
	if sm == null:
		return null
	var me := my_pos()
	var best: RigidBody3D = null
	var best_d := r
	for t in sm.tokens():
		var id := (t as Object).get_instance_id()
		if float(_ban.get(id, -1.0)) > _time:
			continue
		if not sm.token_wanted_by(t, doll):
			continue
		var tp := (t as Node3D).global_position
		var dist := me.distance_to(Vector2(tp.x, tp.y))
		if dist < best_d:
			best_d = dist
			best = t
	return best


## Соперник, от которого стоит уйти (сильно больше деталей и близко), или null.
func threat() -> Doll:
	if sm == null or not fear or _time < _brave_until:
		return null
	var mine := sm.parts_count(doll)
	var best: Doll = null
	var best_d := Tuning.SCAV_BOT_FEAR_M
	for d in players():
		var dd := d as Doll
		if sm.parts_count(dd) < mine + Tuning.SCAV_BOT_FEAR_GAP:
			continue
		var dist := my_pos().distance_to(com2(dd))
		if dist < best_d:
			best_d = dist
			best = dd
	return best


## Кого бить: ближний с поправкой на детали (у кого меньше — тот вкуснее).
func _prey() -> Doll:
	var best: Doll = null
	var best_s := INF
	for d in players():
		var dd := d as Doll
		var s := my_pos().distance_to(com2(dd)) + float(sm.parts_count(dd)) * PREY_PARTS_M
		if s < best_s:
			best_s = s
			best = dd
	return best


func _think(delta: float) -> void:
	_find_refs()
	if sm == null or sm.play_state != "play":
		go("idle")
		goal_part = null
		want = hover_vec()
		return
	var mine := sm.parts_count(doll)
	# --- уйти от сильного
	var th := threat()
	if th != null:
		var gap := my_pos().distance_to(com2(th))
		if _time - _flee_seen_t > FLEE_FORGET_S or gap > _flee_best + FLEE_GAIN_M:
			_flee_best = gap
			_flee_anchor_t = _time
		elif _time - _flee_anchor_t > FLEE_STALL_S:
			_brave_until = _time + BRAVE_S   # загнан в угол: дальше без страха
			counters["cornered"] = int(counters.get("cornered", 0)) + 1
			th = null
		_flee_seen_t = _time
	if th != null:
		go("flee")
		var away := my_pos() - com2(th)
		if away.length() < 0.05:
			away = Vector2(1.0, 0.0)
		var p := nearest_part(3.0)
		var goal := my_pos() + away.normalized() * 4.0 + Vector2(0.0, 1.0)
		if p != null:
			goal = Vector2(p.global_position.x, p.global_position.y)
		goal = _inside(goal)
		want = steer_speed(goal, 7.0, max_in)
		if use_dash and want.length() > 0.5:
			dash()
		return
	# --- деталь
	var reach := INF if mine < want_parts else Tuning.SCAV_BOT_PART_M
	var part := nearest_part(reach)
	if part != null:
		if part != goal_part:
			goal_part = part
			_goal_t = 0.0
		_goal_t += delta
		if _goal_t > Tuning.SCAV_BOT_GIVEUP_S:
			_ban[part.get_instance_id()] = _time + Tuning.SCAV_BOT_BAN_S
			goal_part = null
			_goal_t = 0.0
		else:
			go("fetch")
			var pp := part.global_position
			var to := Vector2(pp.x, pp.y) - my_pos()
			want = steer_speed(Vector2(pp.x, pp.y), 7.0, max_in)
			if use_dash and to.length() > FAR_DASH_M and want.length() > 0.5 and want.normalized().dot(to.normalized()) > DASH_ALIGN:
				dash()
			return
	goal_part = null
	var prey := _prey()
	if prey != null:
		target = prey
	_attack()


func _inside(p: Vector2) -> Vector2:
	var b := arena_bounds()
	if b.size.x <= 0.0:
		return p
	return Vector2(clampf(p.x, b.position.x + 1.5, b.end.x - 1.5), clampf(p.y, b.position.y + 1.5, b.end.y - 1.5))


## Наскок на цель: approach → удар → retreat → approach.
func _attack() -> void:
	if target == null or not is_instance_valid(target) or not target.alive:
		if state != "idle":
			go("idle")
		want = hover_vec()
		return
	var me := my_pos()
	var aim := predicted()
	var to := aim - me
	if to.length() > 8.0:
		go("approach")
		want = steer_speed(aim, 8.0, max_in)
		if use_dash and absf(to.x) > DASH_FROM_M and want.normalized().dot(to.normalized()) > 0.5:
			dash()
		return
	var sgn := signf(to.x) if absf(to.x) > 0.05 else 1.0
	var vy := clampf(to.y / CLIMB_SCALE_M, -1.0, 1.0) if absf(to.y) > CLIMB_FROM_M else hover_vec().y
	match state:
		"retreat":
			want = Vector2(-sgn * max_in, hover_vec().y)
			if state_t >= Drive.rival_retreat_s(retreat_s):
				go("approach")
		_:
			if absf(to.x) < NEAR_X_M and absf(to.y) < NEAR_Y_M:
				note_attack()
				go("retreat")
				want = Vector2(-sgn * max_in, hover_vec().y)
				return
			go("approach")
			want = Vector2(sgn, vy) * max_in
			if use_dash and absf(to.x) > DASH_FROM_M and want.normalized().dot(to.normalized()) > 0.5:
				dash()


func _stuck_allowed() -> bool:
	return state in ["approach", "retreat", "idle", "fetch", "flee"]


## Застревание поверх EnemyBrain (там «жмёт, а стоит» и выход всегда вверх-вбок): ещё «жмёт, а топчется» в круге STUCK_RADIUS_M
## за STUCK_AREA_S. Выход — по кругу UNSTICK_DIRS; если жмёт вверх, первым — вбок к центру и вниз (из-под настила).
func _tick_stuck(delta: float) -> void:
	if _time < _unstick_until:
		want = _unstick_dir
		return
	var me := my_pos()
	var pushing := _stuck_allowed() and want.length() >= STUCK_INPUT
	if not pushing or me.distance_to(_stuck_anchor) > STUCK_RADIUS_M:
		_stuck_anchor = me
		_stuck_anchor_t = _time
		if not pushing:
			_unstick_n = 0
	_stuck_t = _stuck_t + delta if pushing and my_vel().length() < STUCK_SPEED else 0.0
	if _stuck_t < STUCK_S and (state == "idle" or _time - _stuck_anchor_t < STUCK_AREA_S):
		return
	_stuck_t = 0.0
	_stuck_anchor = me
	_stuck_anchor_t = _time
	_unstick_until = _time + UNSTICK_S
	var b := arena_bounds()
	var cx := b.get_center().x if b.size.x > 0.0 else 0.0
	var sx := signf(cx - me.x) if absf(cx - me.x) > 0.5 else (-signf(want.x) if absf(want.x) > 0.2 else 1.0)
	var i := _unstick_n if want.y > 0.3 else _unstick_n + 1
	var d: Vector2 = UNSTICK_DIRS[i % UNSTICK_DIRS.size()]
	_unstick_n += 1
	_unstick_dir = Vector2(d.x * sx, d.y)
	counters["unstick"] = int(counters.get("unstick", 0)) + 1
