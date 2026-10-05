## Бот спорт-зала (docs/plan-demo/SPORT.md): играет в мяч, а не дерётся. Каркас — EnemyBrain (ввод тягой с плавным разворотом,
## стан — молчит, выход из застревания, ускорение за Заряд), но без EnemyLook (это боец, а не сломанный робот) и без цели-куклы:
## цель — мяч (SportBall) с упреждением lead_s и ошибкой прицела.
## Одно правило на все виды спорта: «встань за мяч со стороны, противоположной точке прицела, и пройди сквозь него»:
##   • chase  — к точке за мячом (STRIKE_GAP_M от центра против направления удара); если бот оказался перед мячом — облёт
##     сбоку (AROUND_M), чтобы не катить мяч в свои ворота;
##   • strike — бот за мячом и на линии удара: полная тяга сквозь мяч к точке прицела, издалека — с ускорением;
##   • wait   — мяч прижат к стене и за него не зайти: отойти в поле и дать ему отскочить;
##   • home   — волейбол, мяч на чужой половине: ждать на своей.
## Точка прицела (_aim_point): футбол — чужие ворота; баскетбол — над чужим кольцом, а когда мяч уже над ним — в кольцо;
## волейбол — высоко над чужой половиной (удар снизу вверх через сетку).
## Команду и сторону бот берёт у своей куклы (SportMatch.team_of): Match.respawn_doll пересоздаёт мозг без настроек.
## Уровень 1..3 — Tuning.SPORT_BOT_LEVELS (тяга, прицел, упреждение, ускорение).
class_name SportBrain
extends EnemyBrain

const STRIKE_GAP_M := 0.95
const ALIGN_M := 0.5
const AROUND_M := 1.5
const DASH_FROM_M := 1.6
const BEHIND_M := 0.15
const LOW_BALL_M := 1.1
const GIVE_SPACE_M := 2.2

@export var level := 2

var ball: SportBall
var sm: SportMatch
var team := 1
var dir := -1.0
var max_in := 0.88
var use_dash := true


func _setup() -> void:
	if _ready_done:
		return
	_ready_done = true
	doll.external_input = true
	arena = get_tree().get_first_node_in_group("arena")
	doll.knocked_out.connect(func(_a: Node, _r: Dictionary) -> void: _on_ko())
	_brain_ready()


func _brain_ready() -> void:
	players_group = "sport_nobody"
	enemies_group = "sport_nobody"
	team = SportMatch.team_of(doll)
	dir = SportMatch.attack_dir(team)
	var p: Dictionary = Tuning.SPORT_BOT_LEVELS.get(level, Tuning.SPORT_BOT_LEVELS[2])
	max_in = float(p["max_in"])
	aim_error_m = float(p["aim_error_m"])
	lead_s = float(p["lead_s"])
	use_dash = bool(p["dash"])
	go("chase")


func _find_refs() -> void:
	if sm == null or not is_instance_valid(sm):
		sm = get_tree().get_first_node_in_group(Match.GROUP) as SportMatch
	if ball == null or not is_instance_valid(ball):
		ball = get_tree().get_first_node_in_group(SportBall.GROUP) as SportBall


func _think(_delta: float) -> void:
	_find_refs()
	if ball == null or sm == null:
		want = hover_vec()
		return
	var me := my_pos()
	var b := ball.pos2() + ball.vel2() * lead_s + _noise
	if not _ball_is_mine(b):
		go("home")
		want = steer(_home_point(), max_in)
		return
	var to_aim := _aim_point(b) - b
	var ad := to_aim.normalized() if to_aim.length() > 0.01 else Vector2(dir, 0.0)
	if b.y < LOW_BALL_M and ad.y > 0.5:
		# мяч у пола, а бить надо вверх: под него не подлезть — гонит вдоль пола в сторону прицела
		ad = Vector2(signf(to_aim.x) if absf(to_aim.x) > 0.05 else dir, 0.3).normalized()
	var rel := me - b
	var along := rel.dot(ad)
	var side := rel - ad * along
	if along < -BEHIND_M and side.length() < ALIGN_M + (-along) * 0.3:
		if state != "strike":
			note_attack()
		go("strike")
		want = (b + ad * 0.6 - me).normalized() * max_in + hover_vec() * 0.5
		if use_dash and rel.length() > DASH_FROM_M:
			dash()
		return
	var goal := b - ad * STRIKE_GAP_M
	if absf(goal.x) > Tuning.SPORT_FIELD_HALF_W - 0.45 and rel.length() < GIVE_SPACE_M:
		# мяч прижат к стене, за него не зайти: отойти в поле и дать ему отскочить (иначе куклы сидят на мяче в углу)
		go("wait")
		want = steer(b + Vector2(-signf(b.x) * GIVE_SPACE_M, 1.4), max_in)
		return
	go("chase")
	if along > -BEHIND_M:
		# бот перед мячом или сбоку: облёт — в сторону, где он уже есть (а с линии удара — поверху)
		var perp := Vector2(-ad.y, ad.x)
		var s := perp.dot(rel)
		if absf(s) < 0.25:
			s = 1.0 if perp.y >= 0.0 else -1.0
		goal = b + perp * signf(s) * AROUND_M - ad * 0.2
	goal.y = maxf(goal.y, 0.9)
	want = steer(goal, max_in)


## Куда должен лететь мяч.
func _aim_point(b: Vector2) -> Vector2:
	var r: Dictionary = sm.rules()
	match sm.sport:
		"basketball":
			var hoop := Vector2(dir * float(r["hoop_x"]), float(r["hoop_y"]))
			if b.y > hoop.y + 0.5 and absf(b.x - hoop.x) < 2.2:
				return hoop + Vector2(0.0, -0.6)
			return hoop + Vector2(0.0, 2.8)
		"volleyball":
			return Vector2(dir * 5.5, float(r["net_h"]) + 4.5)
	return Vector2(dir * (float(r["goal_x"]) + 1.2), float(r["goal_h"]) * 0.45)


## Волейбол: чужая половина — не мой мяч (сетка всё равно не пустит). Остальные виды — мяч общий.
func _ball_is_mine(b: Vector2) -> bool:
	if sm.sport != "volleyball":
		return true
	return b.x * dir < 0.4


func _home_point() -> Vector2:
	return Vector2(-dir * 4.5, 2.4)


func _stuck_allowed() -> bool:
	return true
