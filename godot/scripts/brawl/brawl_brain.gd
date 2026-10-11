## Бот «Стенки на стенку 5×5» (docs/plan-demo/BRAWL.md). Каркас — EnemyBrain (тяга с плавным разворотом, восприятие с задержкой и
## упреждением, стан — молчит, выход из застревания, ускорение за Заряд), без EnemyLook (это боец, а не сломанный робот). Поведение —
## наскок RivalBrain (разбег → удар → отход → разбег, рывок с разбега), но цель — ближайший живой враг (другая команда BrawlMatch,
## players() — team_alive), свои — группа своей команды (разнос EnemyBrain.separation: не толпятся и не бьют друг друга в куче).
##   • approach — к цели с упреждением lead_s; дальше DASH_FROM_M — ускорение (уровни 2–3); цель рядом (NEAR_X_M × NEAR_Y_M) —
##     наскок состоялся → retreat на retreat_s, потом снова approach;
##   • держится своих: дальше Tuning.BRAWL_BOT_COHESION_M от центра живых своих — к направлению на цель примешивается тяга к ним (до
##     полной на удвоенной дистанции); один в поле к краю не улетает; у команды врага остался один живой — он ближайший всем, все
##     окружают его сами;
##   • idle — раунд не идёт (отсчёт, пауза, итоги): висит на месте.
## Уровень 1..3 — Tuning.BRAWL_BOT_LEVELS; Match.respawn_doll создаёт мозг заново без настроек — уровень из default_level.
class_name BrawlBrain
extends EnemyBrain

const NEAR_X_M := 1.3        # ближе по x (и по y NEAR_Y_M) — наскок состоялся, отход
const NEAR_Y_M := 1.2
const DASH_FROM_M := 2.0     # рывок с разбега не ближе этого (кулдаун — у куклы, Tuning.DASH_COOLDOWN_S)
const CLIMB_FROM_M := 0.8    # цель выше / ниже больше этого — тяга по вертикали к ней
const CLIMB_SCALE_M := 1.5

static var default_level := 2

## −1 — брать default_level (мозг после пересоздания куклы — новый экземпляр без настроек).
@export var level := -1

var bm: BrawlMatch
var max_in := 0.92
var retreat_s := 1.3
var use_dash := true


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
	players_group = "brawl_nobody"
	enemies_group = BrawlMatch.team_group(BrawlMatch.team_of(doll))
	var lv := level if level > 0 else default_level
	var p: Dictionary = Tuning.BRAWL_BOT_LEVELS.get(lv, Tuning.BRAWL_BOT_LEVELS[2])
	max_in = float(p["max_in"])
	reaction_s = float(p["reaction_s"])
	aim_error_m = float(p["aim_error_m"])
	lead_s = float(p["lead_s"])
	retreat_s = float(p["retreat_s"])
	use_dash = bool(p["dash"])
	go("idle")


func _find_refs() -> void:
	if bm == null or not is_instance_valid(bm):
		bm = get_tree().get_first_node_in_group(Match.GROUP) as BrawlMatch


## Цели для EnemyBrain (_pick_target — ближайшая): живые куклы другой команды.
func players() -> Array:
	_find_refs()
	if bm == null:
		return []
	var out: Array = []
	for d in bm.team_alive(1 - BrawlMatch.team_of(doll)):
		if (d as Node).is_inside_tree():
			out.append(d)
	return out


## Центр живых своих (без меня) или моя позиция, если я один.
func team_centre() -> Vector2:
	var s := Vector2.ZERO
	var n := 0
	for o in get_tree().get_nodes_in_group(enemies_group):
		if o == doll or not (o is Doll) or not (o as Doll).alive or not o.is_inside_tree():
			continue
		s += com2(o)
		n += 1
	return s / float(n) if n > 0 else my_pos()


func _think(_delta: float) -> void:
	_find_refs()
	if bm == null or bm.play_state != "play":
		go("idle")
		want = hover_vec()
		return
	if target == null or not is_instance_valid(target) or not target.alive:
		if state != "idle":
			go("idle")
		want = hover_vec()
		return
	var me := my_pos()
	var to := predicted() - me
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
			# держится своих: далеко от центра живых своих — тяга к ним примешивается, у удвоенной дистанции — целиком
			var c := team_centre()
			var away := me.distance_to(c)
			var coh: float = Tuning.BRAWL_BOT_COHESION_M
			if away > coh:
				var k := clampf((away - coh) / coh, 0.0, 1.0)
				var back := (c - me).normalized() * max_in
				want = want.lerp(back, k)
				counters["cohesion_ticks"] = int(counters.get("cohesion_ticks", 0)) + 1
			if use_dash and absf(to.x) > DASH_FROM_M and want.normalized().dot(to.normalized()) > 0.5:
				dash()


func _stuck_allowed() -> bool:
	return state in ["approach", "retreat", "idle"]
