## Бот «Охоты за головами» (docs/plan-demo/HEADHUNT.md). Каркас — EnemyBrain (тяга с плавным разворотом, восприятие с задержкой и
## упреждением, стан — молчит, выход из застревания, ускорение за Заряд), без EnemyLook. Цели — живые куклы другой команды
## (HeadhuntMatch.team_alive), разнос — со своими (группа своей команды). Приоритеты каждый тик:
##   • carry — на спине есть головы: к своей корзине (перелёт на высоте Tuning.HEADHUNT_BOT_CRUISE_Y над укрытиями Полигона, у корзины —
##     вниз к ободу); по пути подбирает чужую голову, если она ближе HEAD_DETOUR_M;
##   • fetch — чужая голова лежит ближе Tuning.HEADHUNT_BOT_HEAD_M (и её можно взять) — за ней;
##   • guard — защитник (один на команду: бот с наибольшим player_index) держится у своей корзины; враг ближе
##     Tuning.HEADHUNT_BOT_DEFEND_M к корзине — бьёт его;
##   • approach / retreat — наскок на ближайшего врага, как BrawlBrain (разбег → удар → отход → разбег, рывок с разбега);
##   • idle — раунд не идёт (отсчёт, итоги): висит на месте.
## Уровень 1..3 — Tuning.HEADHUNT_BOT_LEVELS; Match.respawn_doll создаёт мозг заново без настроек — уровень из default_level.
class_name HeadhuntBrain
extends EnemyBrain

const NEAR_X_M := 1.3
const NEAR_Y_M := 1.2
const DASH_FROM_M := 2.5
const CLIMB_FROM_M := 0.8
const CLIMB_SCALE_M := 1.5
const HEAD_DETOUR_M := 3.0       # с головами на спине — заберёт ещё одну чужую, если она так близко
const CRUISE_FROM_M := 4.0       # дальше по x — перелёт на высоте круиза
const GUARD_OFFSET := Vector2(3.0, 1.6)   # точка защитника: от корзины к середине и вверх

static var default_level := 2

@export var level := -1

var hm: HeadhuntMatch
var max_in := 0.92
var retreat_s := 1.3
var use_dash := true
var goal_head: RigidBody3D = null


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
	players_group = "headhunt_nobody"
	enemies_group = HeadhuntMatch.team_group(HeadhuntMatch.team_of(doll))
	var lv := level if level > 0 else default_level
	var p: Dictionary = Tuning.HEADHUNT_BOT_LEVELS.get(lv, Tuning.HEADHUNT_BOT_LEVELS[2])
	max_in = float(p["max_in"])
	reaction_s = float(p["reaction_s"])
	aim_error_m = float(p["aim_error_m"])
	lead_s = float(p["lead_s"])
	retreat_s = float(p["retreat_s"])
	use_dash = bool(p["dash"])
	go("idle")


func _find_refs() -> void:
	if hm == null or not is_instance_valid(hm):
		hm = get_tree().get_first_node_in_group(Match.GROUP) as HeadhuntMatch


func my_team() -> int:
	return HeadhuntMatch.team_of(doll)


## Цели для EnemyBrain (_pick_target — ближайшая): живые куклы другой команды.
func players() -> Array:
	_find_refs()
	if hm == null:
		return []
	var out: Array = []
	for d in hm.team_alive(1 - my_team()):
		if (d as Node).is_inside_tree():
			out.append(d)
	return out


## Защитник команды: бот с наибольшим player_index среди ботов своей команды.
func is_guard() -> bool:
	if hm == null:
		return false
	var best := -1
	for d in hm.dolls():
		var dd := d as Doll
		if HeadhuntMatch.team_of(dd) == my_team() and dd.external_input and dd.player_index > best:
			best = dd.player_index
	return best == doll.player_index


## Ближайшая чужая голова на полу, которую можно взять, ближе r (или null).
func nearest_head(r: float) -> RigidBody3D:
	if hm == null or hm.carry == null:
		return null
	var me := my_pos()
	var best: RigidBody3D = null
	var best_d := r
	for h in hm.carry.loose():
		if HeadCarry.owner_team(h) == my_team() or not hm.carry.pickable(h):
			continue
		var hp := (h as Node3D).global_position
		var d := me.distance_to(Vector2(hp.x, hp.y))
		if d < best_d:
			best_d = d
			best = h
	return best


## Желаемый ввод к точке goal: дальний перелёт — на высоте круиза (над укрытиями), вблизи — прямо.
func fly_to(goal: Vector2, speed_cap: float = 6.0) -> Vector2:
	var me := my_pos()
	var g := goal
	if absf(goal.x - me.x) > CRUISE_FROM_M:
		g = Vector2(goal.x, maxf(goal.y, Tuning.HEADHUNT_BOT_CRUISE_Y))
		if me.y < Tuning.HEADHUNT_BOT_CRUISE_Y - 1.0:
			g.x = me.x + signf(goal.x - me.x) * 2.0   # сначала вверх, потом вбок
	return steer_speed(g, speed_cap, max_in)


func _think(_delta: float) -> void:
	_find_refs()
	if hm == null or hm.play_state != "play":
		go("idle")
		want = hover_vec()
		return
	var carrying := hm.carry.carry_count(doll)
	var basket := hm.basket_of(my_team())
	# --- несёт: к своей корзине
	if carrying > 0 and basket != null:
		var detour := nearest_head(HEAD_DETOUR_M) if carrying < Tuning.HEADHUNT_CARRY_MAX else null
		if detour != null:
			go("fetch")
			goal_head = detour
			var hp := detour.global_position
			want = fly_to(Vector2(hp.x, hp.y), 7.0)
			return
		go("carry")
		var bp := basket.point()
		want = fly_to(Vector2(bp.x, bp.y + 0.3), 7.0)
		if use_dash and absf(bp.x - my_pos().x) > 8.0 and want.length() > 0.5:
			dash()
		return
	# --- чужая голова рядом
	var h := nearest_head(Tuning.HEADHUNT_BOT_HEAD_M)
	if h != null:
		go("fetch")
		goal_head = h
		var hp2 := h.global_position
		want = fly_to(Vector2(hp2.x, hp2.y), 7.0)
		return
	goal_head = null
	# --- защитник у корзины
	if basket != null and is_guard():
		var bp2 := basket.point()
		var threat: Doll = null
		var td := Tuning.HEADHUNT_BOT_DEFEND_M
		for e in players():
			var d := com2(e).distance_to(Vector2(bp2.x, bp2.y))
			if d < td:
				td = d
				threat = e
		if threat == null:
			go("guard")
			var side := 1.0 if bp2.x < 0.0 else -1.0
			want = steer(Vector2(bp2.x + side * GUARD_OFFSET.x, bp2.y + GUARD_OFFSET.y), max_in)
			return
		target = threat
	_attack()


## Наскок на цель (как BrawlBrain): approach → удар → retreat → approach.
func _attack() -> void:
	if target == null or not is_instance_valid(target) or not target.alive:
		if state != "idle":
			go("idle")
		want = hover_vec()
		return
	var me := my_pos()
	var aim := predicted()
	var to := aim - me
	if absf(to.x) > CRUISE_FROM_M * 2.0:
		go("approach")
		want = fly_to(aim, 8.0)
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
	return state in ["approach", "retreat", "idle", "carry", "fetch", "guard"]
