## Бот «Бомбы касанием» (docs/plan-demo/BOMB.md). Каркас — EnemyBrain (тяга с плавным разворотом, восприятие с задержкой и упреждением,
## стан — молчит, выход из застревания, ускорение за Заряд), но без EnemyLook (это игрок, а не сломанный робот) и без разноса со «своими».
## Цели — не группа players, а матч (players() по бомбе):
##   • chase — бомба у меня: к ближнему живому, кому её можно отдать (не тому, от кого только что получил), с упреждением lead_s и
##     ускорением, когда цель в коридоре Tuning.BOMB_BOT_DASH_M; касание любой деталью отдаёт бомбу;
##   • evade — бомба у другого: к точке бегства на кольце вдоль мембраны купола (эллипс мембраны, ужатый на BOMB_BOT_FLEE_MARGIN_M; углы
##     у пола в кольцо не входят) — выбор раз в FLEE_EVAL_S: дальше от держателя, ближе ко мне, путь не мимо держателя, не в кучу с
##     другими убегающими, плюс случайная прибавка точкам раз в WANDER_S (не висеть на одном месте); гистерезис FLEE_HYST;
##   • panic — держатель ближе BOMB_BOT_PANIC_M: прочь от него и вбок к середине купола, с ускорением;
##   • shove — я только что отдал бомбу и запрет возврата ещё держит: держателя рядом можно отпихнуть (удар без урона, только отброс);
##   • spread — бомбы нет (пауза после взрыва): к ближней точке кольца, разойтись.
## Уровень 1..3 — Tuning.BOMB_BOT_LEVELS; Match.respawn_doll создаёт мозг заново без настроек — уровень из default_level.
class_name BombBrain
extends EnemyBrain

const FLEE_EVAL_S := 0.25
const FLEE_HYST := 1.5          # м «очков»: новая точка бегства должна быть лучше текущей хотя бы на столько
const PATH_CLEAR_M := 3.0       # путь к точке ближе этого к держателю — штраф
const SHOVE_LOCK_LEFT_S := 0.35
const SHOVE_M := 2.4
const CROWD_M := 3.0            # точка бегства ближе этого к другому убегающему — штраф
const CROWD_GAIN := 1.2
## Держатель далеко — убегающий не висит на одной точке: раз в WANDER_S каждой точке кольца своя случайная прибавка до WANDER_GAIN
## (больше гистерезиса — бот перелетает к другой безопасной точке; живому игроку так труднее предсказать, куда он денется).
const WANDER_S := 4.0
const WANDER_GAIN := 2.5

static var default_level := 2

@export var level := -1

var bm: BombMatch
var max_in := 0.92
var use_dash := true
var flee_goal := Vector2.ZERO
var ring: Array = []            # точки бегства (Vector2)
var _flee_eval_t := 0.0
var _holding := false
var _wander: Array = []
var _wander_at := 0.0


func _setup() -> void:
	if _ready_done:
		return
	_ready_done = true
	doll.external_input = true
	arena = get_tree().get_first_node_in_group("arena")
	doll.knocked_out.connect(func(_a: Node, _r: Dictionary) -> void: _on_ko())
	_brain_ready()


func _brain_ready() -> void:
	players_group = "bomb_nobody"
	enemies_group = "bomb_nobody"
	var lv := level if level > 0 else default_level
	var p: Dictionary = Tuning.BOMB_BOT_LEVELS.get(lv, Tuning.BOMB_BOT_LEVELS[2])
	max_in = float(p["max_in"])
	aim_error_m = float(p["aim_error_m"])
	reaction_s = float(p["reaction_s"])
	lead_s = float(p["lead_s"])
	use_dash = bool(p["dash"])
	_build_ring()
	go("spread")


## Кольцо бегства: эллипс мембраны (NullField арены: centre, axes), ужатый на BOMB_BOT_FLEE_MARGIN_M, от 15° до 165° — без углов у пола;
## плюс несколько точек внутри купола.
func _build_ring() -> void:
	ring.clear()
	var ax := Vector2(16.0, 19.0)
	var c := Vector2.ZERO
	var f: Variant = arena.get("field") if arena != null and is_instance_valid(arena) else null
	if f is NullField:
		ax = (f as NullField).axes
		c = (f as NullField).centre
	var m: Vector2 = Tuning.BOMB_BOT_FLEE_MARGIN_M
	var a := maxf(ax.x - m.x, 4.0)
	var b := maxf(ax.y - m.y, 4.0)
	for i in range(1, 12):
		var ang := PI * float(i) / 12.0
		ring.append(c + Vector2(cos(ang) * a, maxf(sin(ang) * b, 2.2)))
	for p in [Vector2(0.0, 3.0), Vector2(-7.0, 2.6), Vector2(7.0, 2.6), Vector2(-5.0, 8.0), Vector2(5.0, 8.0), Vector2(0.0, 10.0)]:
		ring.append(c + (p as Vector2))


func _find_refs() -> void:
	if bm == null or not is_instance_valid(bm):
		bm = get_tree().get_first_node_in_group(Match.GROUP) as BombMatch


## Цели для EnemyBrain (_pick_target): бомба у меня — живые, кому её можно отдать; у другого — сам держатель (от него бежим).
func players() -> Array:
	var out: Array = []
	_find_refs()
	if bm == null:
		return out
	var h := bm.holder
	if h == doll:
		for d in bm.alive_dolls():
			if d != doll and not bm.locked_for(d) and (d as Node).is_inside_tree():
				out.append(d)
	elif h != null and is_instance_valid(h) and h.alive:
		out.append(h)
	return out


func _think(delta: float) -> void:
	_find_refs()
	if bm == null or not (bm.play_state == "play" or bm.play_state == "next"):
		go("idle")
		want = hover_vec()
		return
	var holding := bm.holder == doll
	if holding != _holding or (target != null and not players().has(target)) or (target == null and not players().is_empty()):
		_holding = holding
		_pick_target()
		_record_target()
	if holding:
		_chase()
	else:
		_evade(delta)


func _chase() -> void:
	if state != "chase":
		note_attack()
	go("chase")
	if target == null or not is_instance_valid(target):
		want = steer(Vector2(0.0, 6.0), max_in)
		return
	var me := my_pos()
	var to := predicted() - me
	var dist := to.length()
	var dir := to / dist if dist > 0.01 else Vector2.UP
	want = (dir * max_in + hover_vec()).limit_length(1.0)
	var dm: Vector2 = Tuning.BOMB_BOT_DASH_M
	if use_dash and dist > dm.x and dist < dm.y:
		dash()


func _evade(delta: float) -> void:
	var h := bm.holder
	var me := my_pos()
	if h == null or not is_instance_valid(h) or not h.alive or target == null:
		go("spread")
		want = steer(_nearest_ring(me), max_in * 0.7)
		return
	var hp := predicted(0.15)
	var away := me - hp
	var d := away.length()
	if bm.got_from == doll and bm.lock_left() > SHOVE_LOCK_LEFT_S and d < SHOVE_M:
		# только что отдал — пока запрет возврата держит, отпихнуть держателя (удар без урона, отброс полный)
		go("shove")
		want = ((-away).normalized() * max_in + hover_vec()).limit_length(1.0)
		return
	if d < Tuning.BOMB_BOT_PANIC_M:
		go("panic")
		var ad := away / d if d > 0.01 else Vector2.UP
		var perp := Vector2(-ad.y, ad.x)
		if perp.dot(Vector2(0.0, 7.0) - me) < 0.0:
			perp = -perp   # вбок — к середине купола, а не в мембрану
		want = ((ad * 0.75 + perp * 0.55).normalized() * max_in + hover_vec()).limit_length(1.0)
		if use_dash:
			dash()
		return
	go("evade")
	_flee_eval_t -= delta
	if _flee_eval_t <= 0.0 or flee_goal == Vector2.ZERO:
		_flee_eval_t = FLEE_EVAL_S
		flee_goal = _best_flee(me, hp)
	want = steer(flee_goal, max_in)


func _best_flee(me: Vector2, hp: Vector2) -> Vector2:
	var best := flee_goal
	var best_s := -INF
	var cur_s := -INF
	var crowd: Array = []   # другие убегающие: в одну точку не сбиваться (кучу держатель берёт разом)
	for d in bm.alive_dolls():
		if d != doll and d != bm.holder:
			crowd.append(com2(d))
	if _time >= _wander_at:
		_wander_at = _time + WANDER_S
		_wander.clear()
		for i in ring.size():
			_wander.append(_rng.randf_range(0.0, WANDER_GAIN))
	for i in ring.size():
		var c: Vector2 = ring[i]
		var s := flee_score(c, me, hp, crowd) + (float(_wander[i]) if i < _wander.size() else 0.0)
		if c == flee_goal:
			cur_s = s
		if s > best_s:
			best_s = s
			best = c
	if flee_goal != Vector2.ZERO and cur_s > best_s - FLEE_HYST:
		return flee_goal
	return best


## Оценка точки бегства c: дальше от держателя hp — лучше, далеко от меня — хуже, путь мимо держателя — штраф, у точки уже кто-то
## из убегающих (crowd) — штраф.
static func flee_score(c: Vector2, me: Vector2, hp: Vector2, crowd: Array = []) -> float:
	var s := c.distance_to(hp) - 0.35 * me.distance_to(c)
	var seg := Geometry2D.get_closest_point_to_segment(hp, me, c).distance_to(hp)
	if seg < PATH_CLEAR_M:
		s -= (PATH_CLEAR_M - seg) * 3.0
	for o in crowd:
		var dd := c.distance_to(o as Vector2)
		if dd < CROWD_M:
			s -= (CROWD_M - dd) * CROWD_GAIN
	return s


func _nearest_ring(me: Vector2) -> Vector2:
	var best := me
	var bd := INF
	for c in ring:
		var dd := me.distance_to(c as Vector2)
		if dd < bd:
			bd = dd
			best = c
	return best


func _stuck_allowed() -> bool:
	return true
