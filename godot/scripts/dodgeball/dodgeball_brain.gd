## Бот «Вышибал» (docs/plan-demo/DODGEBALL.md). Каркас — EnemyBrain (тяга с плавным разворотом, стан — молчит, выход из застревания,
## восприятие цели с запаздыванием reaction_s), без EnemyLook. Мяч берёт и бросает рукой ArmAssist куклы (set_target_override + grab,
## бросок — release("toggle"): ArmAssist._throw к цели руки). Всё на своей половине (цель по x — от 0.8 до 10.3 м от черты). Приоритеты:
##   • threat — чужой живой мяч пройдёт ближе Tuning.DODGEBALL_BOT_DODGE_M в ближайшую секунду (замечен через reaction_s): один бросок
##     кубика на мяч — ловить (catch уровня: рука на путь мяча, хватает DodgeballMatch) или уворачиваться (dodge: прочь от точки
##     сближения, с ускорением на ур. 2–3), иначе — не заметил;
##   • aim — держит мяч: к броску у черты (Tuning.DODGEBALL_BOT_THROW_X), рука на ближайшего соперника с упреждением и поправкой на
##     провисание, через aim_s — бросок;
##   • fetch — к ближайшему мёртвому мячу своей половины (meta grab_team), который не взял на себя свой; кисть вплотную
##     (DODGEBALL_BOT_GRAB_M) — схватить;
##   • roam — мячей нет: тыл своей половины, новое место раз в 2–3 с.
## Уровень 1..3 — Tuning.DODGEBALL_BOT_LEVELS; Match.respawn_doll создаёт мозг заново без настроек — уровень из default_level.
class_name DodgeballBrain
extends EnemyBrain

const FETCH_GIVE_UP_S := 5.0     # не дотянулся до мяча за столько — другой
const REACH_SPEED := 5.5         # м/с подлёта к мячу
const AIM_GIVE_UP_S := 6.0       # держит мяч дольше — бросает как есть
const HALF_MIN_X := 0.8          # ближе к черте цель не ставится (стенка)
const HALF_MAX_X := 10.3
const LOOK_AHEAD_S := 1.0

static var default_level := 2
## Счётчики всех мозгов (пробы: мозг пересоздаётся после возврата и раунда, свои счётчики теряет).
static var total := {"throws": 0, "grabs": 0, "dodges": 0, "catch_tries": 0}

@export var level := -1

var dm: DodgeballMatch
var arm: ArmAssist
var max_in := 0.88
var aim_range := Vector2(0.45, 0.9)
var throw_speed := 9.0           # м/с: скорость броска уровня (DodgeballMatch._after_release ставит её мячу), по ней — упреждение
var dodge_p := 0.6
var catch_p := 0.25
var use_dash := true
var goal_ball: SportBall = null
var _rolled: Dictionary = {}      # instance_id мяча → "catch" | "dodge" | "none"
var _aim_s := 0.6
var _fetch_t := 0.0
var _roam_goal := Vector2.ZERO
var _roam_t := 0.0
var _threat: SportBall = null
var _threat_c := Vector2.ZERO     # смещение точки сближения мяча от моего ЦМ


func _setup() -> void:
	if _ready_done:
		return
	_ready_done = true
	doll.external_input = true
	arena = get_tree().get_first_node_in_group("arena")
	doll.damaged.connect(_on_damaged)
	doll.knocked_out.connect(func(_a: Node, _r: Dictionary) -> void: _on_ko())
	_rng.seed = hash(String(doll.name)) ^ Engine.get_physics_frames()
	_find_refs()
	_brain_ready()


func _brain_ready() -> void:
	players_group = "dodge_nobody"
	enemies_group = DodgeballMatch.team_group(my_team())
	var lv := level if level > 0 else default_level
	var p: Dictionary = Tuning.DODGEBALL_BOT_LEVELS.get(lv, Tuning.DODGEBALL_BOT_LEVELS[2])
	max_in = float(p["max_in"])
	aim_error_m = float(p["aim_error_m"])
	aim_range = p["aim_s"]
	reaction_s = float(p["reaction_s"])
	dodge_p = float(p["dodge"])
	catch_p = float(p["catch"])
	use_dash = bool(p["dash"])
	throw_speed = float(p["throw"])
	go("idle")


func _find_refs() -> void:
	if dm == null or not is_instance_valid(dm):
		dm = get_tree().get_first_node_in_group(Match.GROUP) as DodgeballMatch
	if arm == null or not is_instance_valid(arm):
		arm = DodgeballMatch.arm_of(doll)
		if arm != null:
			arm.show_hints = false
			arm.set_control_part(TugBrain.rope_hand(doll, home()))   # кисть со стороны черты


func my_team() -> int:
	return DodgeballMatch.team_of(doll)


func home() -> float:
	return DodgeballMatch.home_dir(my_team())


## Цели EnemyBrain (_pick_target): соперники на поле.
func players() -> Array:
	_find_refs()
	if dm == null:
		return []
	return dm.team_dolls(1 - my_team(), true)


func holding_ball() -> bool:
	return arm != null and arm.is_holding() and arm.held is SportBall


## Отпустить мяч и руку (смена режима, выбит, P2 стал человеком).
func let_go() -> void:
	if arm != null and is_instance_valid(arm):
		arm.clear_target_override()
		if arm.is_holding():
			arm.release("drop")


func _silenced(_why: String) -> void:
	if arm != null and is_instance_valid(arm):
		arm.clear_target_override()


## Точка на своей половине: x — от HALF_MIN_X до HALF_MAX_X от черты в свою сторону, y — над полом и под потолком.
func clamp_half(p: Vector2) -> Vector2:
	var x := clampf(p.x * home(), HALF_MIN_X, HALF_MAX_X) * home()
	return Vector2(x, clampf(p.y, 0.9, 8.5))


func _think(delta: float) -> void:
	_find_refs()
	if dm == null or arm == null or dm.play_state != "play" or not dm.in_play(doll):
		if state != "idle":
			_silenced("idle")
		go("idle")
		goal_ball = null
		want = hover_vec()
		return
	_forget_rolls()
	if _check_threat():
		_react()
		return
	if holding_ball():
		_aim(delta)
		return
	_fetch(delta)


## Броски кубика по мячам, которые уже не летят, — забыть (тот же мяч, брошенный снова, — новый бросок кубика).
func _forget_rolls() -> void:
	for id in _rolled.keys():
		var b := instance_from_id(int(id)) as SportBall
		if b == null or not dm.ball_is(b, "live"):
			_rolled.erase(id)


## Летит ли в меня чужой живой мяч (замеченный через reaction_s): ближайший по времени сближения.
func _check_threat() -> bool:
	_threat = null
	var me := my_pos()
	var best_t := INF
	for b in dm.balls():
		var sb := b as SportBall
		var st := dm.ball_info(sb)
		if String(st.get("state", "")) != "live" or int(st.get("team", -1)) == my_team():
			continue
		if float(st.get("live_t", 0.0)) < reaction_s:
			continue
		var p := Vector2(sb.global_position.x, sb.global_position.y) - me
		var v := Vector2(sb.linear_velocity.x, sb.linear_velocity.y)
		var vv := v.length_squared()
		if vv < 1.0:
			continue
		var t := -p.dot(v) / vv
		if t <= 0.0 or t > LOOK_AHEAD_S:
			continue
		var c := p + v * t
		if c.length() > Tuning.DODGEBALL_BOT_DODGE_M or t >= best_t:
			continue
		best_t = t
		_threat = sb
		_threat_c = c
	if _threat == null:
		return false
	var id := _threat.get_instance_id()
	if not _rolled.has(id):
		var r := _rng.randf()
		var can_catch := not holding_ball()
		if can_catch and r < catch_p:
			_rolled[id] = "catch"
			total["catch_tries"] = int(total["catch_tries"]) + 1
		elif r < catch_p + dodge_p:
			_rolled[id] = "dodge"
			total["dodges"] = int(total["dodges"]) + 1
		else:
			_rolled[id] = "none"
	return String(_rolled[id]) != "none"


func _react() -> void:
	var how := String(_rolled[_threat.get_instance_id()])
	if how == "catch" and not holding_ball():
		go("catch")
		arm.set_target_override(_threat.global_position + _threat.linear_velocity * 0.08)
		want = hover_vec()
		return
	go("dodge")
	var away := -_threat_c
	if away.length() < 0.05:
		var v := Vector2(_threat.linear_velocity.x, _threat.linear_velocity.y)
		away = Vector2(-v.y, v.x)
	away = away.normalized()
	var me := my_pos()
	# не в стенку черты и не в пол: уклон вдоль своей половины
	if (me.x + away.x * 0.8) * home() < HALF_MIN_X:
		away.x = absf(away.x) * home()
	if me.y < 1.2 and away.y < 0.0:
		away.y = absf(away.y)
	want = hover_vec() + away * max_in
	if use_dash:
		dash()


func _aim(delta: float) -> void:
	if state != "aim":
		go("aim")
		_aim_s = _rng.randf_range(aim_range.x, aim_range.y)
		goal_ball = null
	var tgt := target if target != null and is_instance_valid(target) and dm.in_play(target) else null
	var me := my_pos()
	var spot := clamp_half(Vector2(home() * Tuning.DODGEBALL_BOT_THROW_X, 1.6 + 0.4 * sin(state_t * 2.0)))
	if tgt != null:
		spot.y = clampf(com2(tgt).y, 1.2, 4.5)
	want = steer(spot, max_in)
	if tgt == null:
		arm.set_target_override(Vector3(me.x - home() * 2.0, me.y + 0.4, 0.0))
		if state_t > AIM_GIVE_UP_S:
			_throw()
		return
	var aim := predicted()
	var dist := aim.distance_to(me)
	var t := dist / throw_speed
	var tv := seen()[1] as Vector2
	aim += tv * t * 0.5
	aim.y += 0.5 * Tuning.GRAVITY * Tuning.DODGEBALL_BALL_GRAVITY * t * t
	arm.set_target_override(Vector3(aim.x, aim.y, 0.0))
	var ready_pos := absf(me.x) <= Tuning.DODGEBALL_BOT_THROW_X + 2.5
	if (state_t >= _aim_s and ready_pos and arm.arm_active) or state_t > AIM_GIVE_UP_S:
		_throw()


func _throw() -> void:
	if not holding_ball():
		return
	if not arm.arm_active:
		return
	arm.release("toggle")
	arm.clear_target_override()
	total["throws"] = int(total["throws"]) + 1
	go("recover")


func _fetch(delta: float) -> void:
	_fetch_t += delta
	if goal_ball == null or not is_instance_valid(goal_ball) or _fetch_t > FETCH_GIVE_UP_S or not _ball_ok(goal_ball):
		var exclude := goal_ball if _fetch_t > FETCH_GIVE_UP_S else null
		goal_ball = _pick_ball(exclude)
		_fetch_t = 0.0
	if goal_ball == null:
		_roam(delta)
		return
	if state != "fetch":
		go("fetch")
	var bp := goal_ball.global_position
	var bv := goal_ball.linear_velocity
	var g := clamp_half(Vector2(bp.x + home() * 0.35 + bv.x * 0.25, bp.y + 0.55))
	want = steer_speed(g, REACH_SPEED, max_in)
	arm.set_target_override(bp + bv * 0.05)
	var grip := arm.grip_global()
	if grip.distance_to(bp) - Tuning.SPORT_BALL_RADIUS <= Tuning.DODGEBALL_BOT_GRAB_M and arm.can_grab(goal_ball):
		if arm.grab(goal_ball):
			total["grabs"] = int(total["grabs"]) + 1
			goal_ball = null


## Мяч можно брать: мёртвый, своей половины, отпущен (не на вводе), ни в чьей руке.
func _ball_ok(b: SportBall) -> bool:
	if b.freeze or not dm.ball_is(b, "dead") or ArmAssist.holder_of(b) != null:
		return false
	return String(b.get_meta(&"grab_team", "")) == doll.team


func _pick_ball(exclude: SportBall) -> SportBall:
	var me := my_pos()
	var best: SportBall = null
	var best_d := INF
	for b in dm.balls():
		var sb := b as SportBall
		if sb == exclude or not _ball_ok(sb) or _claimed(sb):
			continue
		var d := me.distance_to(Vector2(sb.global_position.x, sb.global_position.y))
		if d < best_d:
			best_d = d
			best = sb
	return best


## Мяч уже взял на себя свой бот (ближе к нему, чем мы, — его).
func _claimed(b: SportBall) -> bool:
	for d in dm.team_dolls(my_team(), true):
		if d == doll:
			continue
		var ob := (d as Doll).get_node_or_null(DodgeballPlayground.BRAIN) as DodgeballBrain
		if ob != null and ob.goal_ball == b:
			return true
	return false


func _roam(delta: float) -> void:
	if state != "roam":
		go("roam")
		_roam_t = 0.0
	_roam_t -= delta
	if _roam_t <= 0.0:
		_roam_t = _rng.randf_range(2.0, 3.0)
		_roam_goal = clamp_half(Vector2(home() * _rng.randf_range(3.5, 9.0), _rng.randf_range(1.2, 3.5)))
	arm.clear_target_override()
	want = steer(_roam_goal, max_in * 0.7)


func _stuck_allowed() -> bool:
	return state in ["fetch", "roam", "idle", "recover"]
