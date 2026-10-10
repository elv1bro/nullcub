## Бот «Перетягивания каната» (docs/plan-demo/TUG.md). Каркас — EnemyBrain (тяга с плавным разворотом, стан — молчит, выход из
## застревания), без EnemyLook. Канат хватает кодом через руку ArmAssist куклы (set_target_override + grab). Состояния:
##   • idle — розыгрыш не идёт (отсчёт, очко, итоги): висит на месте, канат отпущен;
##   • reach — к свободному звену своей половины (meta grab_team) у «своего места» (передний / задний, Tuning.TUG_BOT_GRIP_LINKS):
##     ЦМ над звеном на Tuning.TUG_BOT_HOVER_Y и чуть ближе к своей стене, рука тянется к звену; кисть вплотную (GRAB_CLOSE_M) — схватить;
##   • pull — держит: рывок (heave_s, тяга pull к своей стене и TUG_BOT_DOWN вниз — упор в пол) ↔ передышка (rest_s, тяга rest);
##     в начале розыгрыша, пока не взялись все боты (свои и чужие), — без рывков (не дольше Tuning.TUG_BOT_WAIT_S: фора за быстрый
##     хват — не очко);
##     метка на нашей стороне дальше Tuning.TUG_BOT_PRESS_M — дожимает без передышек;
##     задний в команде тянет в такт переднему («раз-два»: рывок всей команды сильнее, канат ходит туда-сюда, а не стоит);
##     звено выпало из руки — перехват через regrip_s;
##   • strike (ур. 3) — метка на нашей стороне, свой держит канат, соперник ближе Tuning.TUG_BOT_STRIKE_M: иногда (STRIKE_CHANCE раз в
##     секунду, не чаще STRIKE_COOLDOWN_S) отпустить канат и ударить, через STRIKE_S — снова к канату.
## Уровень 1..3 — Tuning.TUG_BOT_LEVELS; Match.respawn_doll создаёт мозг заново без настроек — уровень из default_level.
class_name TugBrain
extends EnemyBrain

const STRIKE_S := 1.2            # столько бьёт, потом обратно к канату
const STRIKE_COOLDOWN_S := 6.0
const STRIKE_CHANCE := 0.5       # на проверку раз в секунду
const REACH_GIVE_UP_S := 4.0     # не дотянулся до звена за столько — выбрать другое
## Хватать, когда кисть ближе этого к звену (а не на всём ArmAssist.GRAB_RADIUS 0.4 м): сварка подтягивает звено к кисти скачком —
## издалека он растягивал бы стыки цепи (до 0.5 м на рывке).
const GRAB_CLOSE_M := 0.1
const REACH_SPEED := 6.0         # м/с подлёта к звену

static var default_level := 2
## Счётчики всех мозгов (пробы: мозг пересоздаётся после KO и очка, свои счётчики теряет).
static var total := {"grabs": 0, "drops": 0, "strikes": 0}

@export var level := -1

var tm: TugMatch
var arm: ArmAssist
var pull := 0.85
var rest := 0.45
var heave := Vector2(0.9, 1.4)
var rest_range := Vector2(0.3, 0.7)
var regrip_s := 1.4
var use_dash := true
var can_strike := false
var goal_link: RigidBody3D = null
var grabs := 0
var drops := 0
var strikes := 0
var _heave_on := true
var _heave_left := 0.0
var _regrip_left := 0.0
var _strike_cd := 0.0
var _strike_check := 0.0
var _was_holding := false
var _reach_t := 0.0


func _setup() -> void:
	if _ready_done:
		return
	_ready_done = true
	doll.external_input = true
	arena = get_tree().get_first_node_in_group("arena")
	doll.damaged.connect(_on_damaged)
	doll.knocked_out.connect(func(_a: Node, _r: Dictionary) -> void: _on_ko())
	_rng.seed = hash(String(doll.name)) ^ Engine.get_physics_frames()   # новый мозг (после KO / очка) — новые такты рывков
	_find_refs()   # рука бота без подсветки и подписей (Match.respawn_doll создаёт ArmAssist заново с show_hints = true)
	_brain_ready()


func _brain_ready() -> void:
	players_group = "tug_nobody"
	enemies_group = "tug_nobody"
	var lv := level if level > 0 else default_level
	var p: Dictionary = Tuning.TUG_BOT_LEVELS.get(lv, Tuning.TUG_BOT_LEVELS[2])
	pull = float(p["pull"])
	rest = float(p["rest"])
	heave = p["heave"]
	rest_range = p["rest_s"]
	regrip_s = float(p["regrip_s"])
	use_dash = bool(p["dash"])
	can_strike = bool(p["strike"])
	go("idle")


func _find_refs() -> void:
	if tm == null or not is_instance_valid(tm):
		tm = get_tree().get_first_node_in_group(Match.GROUP) as TugMatch
	if arm == null or not is_instance_valid(arm):
		arm = TugPlayground.arm_of(doll)
		if arm != null:
			arm.show_hints = false


func my_team() -> int:
	return TugMatch.team_of(doll)


func home() -> float:
	return TugMatch.home_dir(my_team())


## Цели EnemyBrain (_pick_target): живые соперники.
func players() -> Array:
	_find_refs()
	if tm == null:
		return []
	var out: Array = []
	for d in tm.team_dolls(1 - my_team(), true):
		if (d as Node).is_inside_tree():
			out.append(d)
	return out


## Ближайшее к точке p звено каната, которое кукла d может схватить (своя половина, не в чужой руке), не дальше r.
static func nearest_link(r_: TugRope, d: Doll, p: Vector3, r: float = INF) -> RigidBody3D:
	if r_ == null or d == null:
		return null
	var best: RigidBody3D = null
	var best_d := r
	for b in r_.links:
		var rb := b as RigidBody3D
		if String(rb.get_meta(&"grab_team", "")) != d.team:
			continue
		var h := ArmAssist.holder_of(rb)
		if h != null and h.doll != d:
			continue
		var dist := rb.global_position.distance_to(p)
		if dist < best_d:
			best_d = dist
			best = rb
	return best


func holding() -> bool:
	return arm != null and arm.is_holding() and tm != null and tm.rope != null and tm.rope.is_link(arm.held)


## Отпустить канат и руку (смена режима, KO, стычка).
func let_go() -> void:
	if arm != null and is_instance_valid(arm):
		arm.clear_target_override()
		if arm.is_holding():
			arm.release("drop")


func _silenced(_why: String) -> void:
	if arm != null and is_instance_valid(arm):
		arm.clear_target_override()


func _think(delta: float) -> void:
	_find_refs()
	_strike_cd = maxf(_strike_cd - delta, 0.0)
	if tm == null or arm == null or tm.rope == null or tm.play_state != "play":
		if state != "idle":
			let_go()
		go("idle")
		want = hover_vec()
		return
	var hold := holding()
	if _was_holding and not hold:
		drops += 1
		total["drops"] = int(total["drops"]) + 1
		_regrip_left = regrip_s
	_was_holding = hold
	# --- ур. 3: отпустить и ударить
	if state == "strike":
		if state_t < STRIKE_S and target != null and is_instance_valid(target) and target.alive:
			_strike()
			return
		_strike_cd = STRIKE_COOLDOWN_S
		go("reach")
	if can_strike and _strike_cd <= 0.0:
		_strike_check -= delta
		if _strike_check <= 0.0:
			_strike_check = 1.0
			var e := _close_enemy()
			if e != null and signf(tm.mark_x()) == home() and _mate_holds() and _rng.randf() < STRIKE_CHANCE:
				let_go()
				target = e
				strikes += 1
				total["strikes"] = int(total["strikes"]) + 1
				go("strike")
				_strike()
				return
	if hold:
		_pull(delta)
		return
	if _regrip_left > 0.0:
		_regrip_left -= delta
		go("regrip")
		arm.clear_target_override()
		want = hover_vec() + Vector2(home() * 0.2, 0.0)
		return
	_reach(delta)


func _close_enemy() -> Doll:
	var me := doll.centre_of_mass()
	for e in players():
		if (e as Doll).centre_of_mass().distance_to(me) < Tuning.TUG_BOT_STRIKE_M:
			return e
	return null


func _strike() -> void:
	var to := com2(target) - my_pos()
	want = (to.normalized() + Vector2(0.0, 0.15)).limit_length(1.0)
	if to.length() < 1.0:
		note_attack()


func _pull(delta: float) -> void:
	if state != "pull":
		go("pull")
		grabs += 1
		total["grabs"] = int(total["grabs"]) + 1
		_heave_on = true
		_heave_left = _rng.randf_range(heave.x, heave.y)
		arm.clear_target_override()
	_heave_left -= delta
	if _heave_left <= 0.0:
		_heave_on = not _heave_on
		_heave_left = _rng.randf_range(heave.x, heave.y) if _heave_on else _rng.randf_range(rest_range.x, rest_range.y)
	# «раз-два» команды: задний тянет в такт переднему, если тот тоже держит канат
	var lead := _leader()
	if lead != null:
		_heave_on = lead._heave_on
	# метка уже на нашей стороне дальше TUG_BOT_PRESS_M — дожимать без передышек
	if tm.mark_x() * home() > Tuning.TUG_BOT_PRESS_M:
		_heave_on = true
	# начало розыгрыша: соперник ещё не взялся за канат — держать без рывков (не дольше TUG_BOT_WAIT_S)
	if tm.round_time < Tuning.TUG_BOT_WAIT_S and not _all_hold():
		_heave_on = false
		_heave_left = 0.0   # соперник взялся — рывок сразу
	var k := pull if _heave_on else rest
	want = Vector2(home(), -Tuning.TUG_BOT_DOWN).normalized() * k
	if _heave_on and use_dash:
		dash()


func _reach(delta: float) -> void:
	if state != "reach":
		go("reach")
		_reach_t = 0.0
		goal_link = null
	_reach_t += delta
	if goal_link == null or not is_instance_valid(goal_link) or _reach_t > REACH_GIVE_UP_S \
			or (ArmAssist.holder_of(goal_link) != null and ArmAssist.holder_of(goal_link) != arm):
		var exclude := goal_link if _reach_t > REACH_GIVE_UP_S else null
		goal_link = _pick_link(exclude)
		_reach_t = 0.0
	if goal_link == null:
		arm.clear_target_override()
		want = hover_vec()
		return
	var lp := goal_link.global_position
	var lv := goal_link.linear_velocity
	var g := Vector2(lp.x + home() * 0.25 + lv.x * 0.25, lp.y + Tuning.TUG_BOT_HOVER_Y)
	want = steer_speed(g, REACH_SPEED, 1.0)
	arm.set_target_override(lp + lv * 0.05)
	var grip := arm.grip_global()
	if grip.distance_to(arm.closest_point(goal_link, grip)) <= GRAB_CLOSE_M and arm.can_grab(goal_link):
		arm.grab(goal_link)
		return
	# по пути кисть задела другое свободное звено своей половины — хватать его (канат едет, за целью не угнаться)
	var near := nearest_link(tm.rope, doll, grip, GRAB_CLOSE_M + Tuning.TUG_LINK_RADIUS)
	if near != null and arm.can_grab(near):
		goal_link = near
		arm.grab(near)


## Держит ли канат живой свой (кроме нас): ударить можно, только если канат не брошен.
func _mate_holds() -> bool:
	for d in tm.team_dolls(my_team(), true):
		if d != doll and tm.is_holding(d):
			return true
	return false


## Все живые соперники-боты и свои держат канат (человек-соперник считается взявшимся — его не ждём).
func _all_hold() -> bool:
	for d in tm.dolls():
		var dd := d as Doll
		if dd.alive and dd.external_input and not tm.is_holding(dd):
			return false
	return true


## Передний своей команды (мозг), если он держит канат и это не мы; иначе null.
func _leader() -> TugBrain:
	if slot() == 0:
		return null
	for d in tm.team_dolls(my_team(), true):
		if d == doll:
			continue
		var b := (d as Doll).get_node_or_null(TugPlayground.BRAIN) as TugBrain
		if b != null and b.state == "pull":
			return b
	return null


## Место в команде: 0 — передний (меньший player_index среди своих на канате), 1 — задний.
func slot() -> int:
	var n := 0
	for d in tm.team_dolls(my_team()):
		if d != doll and (d as Doll).player_index < doll.player_index:
			n += 1
	return n


## Звено для хвата: свободное своей половины (не exclude) ближе всего к «своему месту» — передний держит TUG_BOT_GRIP_LINKS[0]
## звеньев от метки, задний — [1] (не толкаются на одном конце); при равенстве — ближе к кукле.
func _pick_link(exclude: RigidBody3D) -> RigidBody3D:
	var me := doll.centre_of_mass()
	var n := tm.rope.links.size()
	var spots: Array = Tuning.TUG_BOT_GRIP_LINKS
	var off := int(spots[clampi(slot(), 0, spots.size() - 1)])
	var want_i := (n / 2 - 1 - off) if my_team() == 0 else (n / 2 + off)
	var best: RigidBody3D = null
	var best_c := INF
	for b in tm.rope.links:
		var rb := b as RigidBody3D
		if rb == exclude or String(rb.get_meta(&"grab_team", "")) != doll.team:
			continue
		var h := ArmAssist.holder_of(rb)
		if h != null and h != arm:
			continue
		var taken := false
		for d in tm.team_dolls(my_team()):
			if d == doll:
				continue
			var ob := (d as Doll).get_node_or_null(TugPlayground.BRAIN) as TugBrain
			if ob != null and ob.goal_link != null and is_instance_valid(ob.goal_link) \
					and absi(int(ob.goal_link.get_meta(&"tug_link")) - int(rb.get_meta(&"tug_link"))) < 2:
				taken = true
				break
		if taken:
			continue
		var c := absf(float(int(rb.get_meta(&"tug_link")) - want_i)) * 0.5 + rb.global_position.distance_to(me) * 0.25
		if c < best_c:
			best_c = c
			best = rb
	return best


func _stuck_allowed() -> bool:
	return state in ["reach", "idle", "regrip"]
