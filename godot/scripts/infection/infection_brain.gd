## Бот «Заражения» (docs/plan-demo/INFECTION.md). Каркас — EnemyBrain (тяга с плавным разворотом, восприятие с задержкой и
## упреждением, выход из застревания, ускорение за Заряд), без EnemyLook и без разноса со «своими» (как BombBrain). Цели — из матча:
##   • chase — я заражён: к ближайшему живому здоровому, которого не взял другой заражённый (у каждого своя цель; все взяты — ближний),
##     с упреждением lead_s; касание любой деталью заражает. Рывка у заражённых нет (Заряд заперт матчем);
##   • evade — я здоров: к точке бегства на кольце вдоль мембраны купола (эллипс мембраны, ужатый на INFECTION_BOT_FLEE_MARGIN_M;
##     углы у пола в кольцо не входят) — выбор раз в FLEE_EVAL_S: дальше от всех заражённых (ближайший — главный), ближе ко мне, путь
##     не мимо заражённого, не в кучу с другими здоровыми, плюс случайная прибавка раз в WANDER_S; гистерезис FLEE_HYST;
##   • panic — заражённый ближе INFECTION_BOT_PANIC_M: прочь от него и вбок к середине купола, с ускорением;
##   • breakout — зажат: я у мембраны (ближе INFECTION_BOT_CORNER_M) или у пола, заражённый между мной и серединой купола — рывок
##     сквозь него к середине (мимо, с уклоном в сторону);
##   • idle — отсчёт и паузы: висеть.
## Уровень 1..3 — Tuning.INFECTION_BOT_LEVELS; Match.respawn_doll создаёт мозг заново без настроек — уровень из default_level.
class_name InfectionBrain
extends EnemyBrain

const FLEE_EVAL_S := 0.25
const FLEE_HYST := 1.5          # м «очков»: новая точка бегства должна быть лучше текущей хотя бы на столько
const PATH_CLEAR_M := 3.0       # путь к точке ближе этого к заражённому — штраф
const CROWD_M := 3.0            # точка бегства ближе этого к другому здоровому — штраф
const CROWD_GAIN := 1.2
const WANDER_S := 4.0
const WANDER_GAIN := 2.5
const BREAKOUT_S := 0.7         # рывок сквозь — столько держать курс (не передумывать на полпути)
const BREAKOUT_SIDE := 0.5      # уклон вбок при рывке сквозь (не лоб в лоб)

static var default_level := 2

@export var level := -1

var im: InfectionMatch
var max_in := 0.92
var use_dash := true
var flee_goal := Vector2.ZERO
var ring: Array = []            # точки бегства (Vector2)
var centre := Vector2(0.0, 7.0)
var axes := Vector2(16.0, 19.0)
var _flee_eval_t := 0.0
var _zombie := false
var _wander: Array = []
var _wander_at := 0.0
var _breakout_until := -1.0
var _breakout_dir := Vector2.ZERO


func _setup() -> void:
	if _ready_done:
		return
	_ready_done = true
	doll.external_input = true
	arena = get_tree().get_first_node_in_group("arena")
	doll.knocked_out.connect(func(_a: Node, _r: Dictionary) -> void: _on_ko())
	_brain_ready()


func _brain_ready() -> void:
	players_group = "infection_nobody"
	enemies_group = "infection_nobody"
	var lv := level if level > 0 else default_level
	var p: Dictionary = Tuning.INFECTION_BOT_LEVELS.get(lv, Tuning.INFECTION_BOT_LEVELS[2])
	max_in = float(p["max_in"])
	aim_error_m = float(p["aim_error_m"])
	reaction_s = float(p["reaction_s"])
	lead_s = float(p["lead_s"])
	use_dash = bool(p["dash"])
	_build_ring()
	go("idle")


## Кольцо бегства: эллипс мембраны (NullField арены: centre, axes), ужатый на INFECTION_BOT_FLEE_MARGIN_M, от 15° до 165° — без углов
## у пола; плюс несколько точек внутри купола.
func _build_ring() -> void:
	ring.clear()
	var ax := Vector2(16.0, 19.0)
	var c := Vector2.ZERO
	var f: Variant = arena.get("field") if arena != null and is_instance_valid(arena) else null
	if f is NullField:
		ax = (f as NullField).axes
		c = (f as NullField).centre
	axes = ax
	centre = c + Vector2(0.0, ax.y * 0.37)
	var m: Vector2 = Tuning.INFECTION_BOT_FLEE_MARGIN_M
	var a := maxf(ax.x - m.x, 4.0)
	var b := maxf(ax.y - m.y, 4.0)
	for i in range(1, 12):
		var ang := PI * float(i) / 12.0
		ring.append(c + Vector2(cos(ang) * a, maxf(sin(ang) * b, 2.2)))
	for p in [Vector2(0.0, 3.0), Vector2(-7.0, 2.6), Vector2(7.0, 2.6), Vector2(-5.0, 8.0), Vector2(5.0, 8.0), Vector2(0.0, 10.0)]:
		ring.append(c + (p as Vector2))


func _find_refs() -> void:
	if im == null or not is_instance_valid(im):
		im = get_tree().get_first_node_in_group(Match.GROUP) as InfectionMatch


func is_zombie() -> bool:
	return im != null and im.is_infected(doll)


## Цели для EnemyBrain: я заражён — живые здоровые; я здоров — заражённые (от ближайшего бежим).
func players() -> Array:
	var out: Array = []
	_find_refs()
	if im == null:
		return out
	for d in (im.healthy() if is_zombie() else im.zombies()):
		if d != doll and (d as Node).is_inside_tree():
			out.append(d)
	return out


## Заражённый: ближайший здоровый, которого не взял другой заражённый-бот (все взяты — просто ближайший); здоровый — ближайший
## заражённый (как в EnemyBrain, с гистерезисом RETARGET_MARGIN_M).
func _pick_target() -> void:
	if not is_zombie():
		super._pick_target()
		return
	var me := my_pos()
	var taken := {}
	for z in im.zombies():
		if z == doll:
			continue
		var b := (z as Node).get_node_or_null(NodePath(name)) as InfectionBrain
		if b != null and b.target != null and is_instance_valid(b.target):
			taken[b.target] = true
	var best: Doll = null
	var best_d := INF
	var free_best: Doll = null
	var free_d := INF
	for p in players():
		var d := me.distance_to(com2(p))
		if d < best_d:
			best_d = d
			best = p
		if not taken.has(p) and d < free_d:
			free_d = d
			free_best = p
	var pick := free_best if free_best != null else best
	if pick == null:
		target = null
		_hist.clear()
		return
	if target != null and is_instance_valid(target) and target.alive and target != pick and not taken.has(target) and im.healthy().has(target):
		if me.distance_to(com2(target)) <= me.distance_to(com2(pick)) + RETARGET_MARGIN_M:
			return
	if pick != target:
		target = pick
		_hist.clear()
		counters["retarget"] = int(counters.get("retarget", 0)) + 1


func _think(delta: float) -> void:
	_find_refs()
	if im == null or im.play_state != "play":
		go("idle")
		want = hover_vec()
		return
	var z := is_zombie()
	if z != _zombie or (target != null and not players().has(target)) or (target == null and not players().is_empty()):
		_zombie = z
		_pick_target()
		_record_target()
	if z:
		_chase()
	else:
		_evade(delta)


func _chase() -> void:
	if state != "chase":
		note_attack()
	go("chase")
	if target == null or not is_instance_valid(target):
		want = steer(centre, max_in)
		return
	var me := my_pos()
	var to := predicted() - me
	var dist := to.length()
	var dir := to / dist if dist > 0.01 else Vector2.UP
	want = (dir * max_in + hover_vec()).limit_length(1.0)


func _evade(delta: float) -> void:
	var me := my_pos()
	var zs := im.zombies()
	if zs.is_empty() or target == null or not is_instance_valid(target):
		go("spread")
		want = steer(_nearest_ring(me), max_in * 0.7)
		return
	var zp := predicted(0.15)
	var away := me - zp
	var d := away.length()
	if _time < _breakout_until:
		go("breakout")
		want = (_breakout_dir * max_in + hover_vec()).limit_length(1.0)
		if use_dash:
			dash()
		return
	if d < Tuning.INFECTION_BOT_PANIC_M * 1.5 and _cornered(me, zp):
		# зажат у мембраны: рывок сквозь заражённого к середине купола, с уклоном вбок
		var through := (centre - me).normalized()
		var side := Vector2(-through.y, through.x) * (1.0 if _rng.randf() < 0.5 else -1.0)
		_breakout_dir = (through + side * BREAKOUT_SIDE).normalized()
		_breakout_until = _time + BREAKOUT_S
		counters["breakout"] = int(counters.get("breakout", 0)) + 1
		go("breakout")
		want = (_breakout_dir * max_in + hover_vec()).limit_length(1.0)
		snap_input(BREAKOUT_S)
		if use_dash:
			dash()
		return
	if d < Tuning.INFECTION_BOT_PANIC_M:
		go("panic")
		var ad := away / d if d > 0.01 else Vector2.UP
		var perp := Vector2(-ad.y, ad.x)
		if perp.dot(centre - me) < 0.0:
			perp = -perp   # вбок — к середине купола, а не в мембрану
		want = ((ad * 0.75 + perp * 0.55).normalized() * max_in + hover_vec()).limit_length(1.0)
		if use_dash:
			dash()
		return
	go("evade")
	_flee_eval_t -= delta
	if _flee_eval_t <= 0.0 or flee_goal == Vector2.ZERO:
		_flee_eval_t = FLEE_EVAL_S
		flee_goal = _best_flee(me, zp)
	want = steer(flee_goal, max_in)


## Зажат: я у мембраны (нормированный радиус эллипса ≥ 1 − CORNER_M / полуось) или у пола, и заражённый между мной и серединой купола.
func _cornered(me: Vector2, zp: Vector2) -> bool:
	var f: Variant = arena.get("field") if arena != null and is_instance_valid(arena) else null
	var c := Vector2.ZERO
	if f is NullField:
		c = (f as NullField).centre
	var rel := me - c
	var r := Vector2(rel.x / maxf(axes.x, 1.0), rel.y / maxf(axes.y, 1.0)).length()
	var near_edge := r >= 1.0 - Tuning.INFECTION_BOT_CORNER_M / minf(axes.x, axes.y) or me.y - c.y < 1.6
	if not near_edge:
		return false
	var to_c := centre - me
	var to_z := zp - me
	return to_c.length() > 0.5 and to_z.length() > 0.1 and to_c.normalized().dot(to_z.normalized()) > 0.55


func _best_flee(me: Vector2, zp: Vector2) -> Vector2:
	var best := flee_goal
	var best_s := -INF
	var cur_s := -INF
	var crowd: Array = []   # другие здоровые: в одну точку не сбиваться
	var zs: Array = []
	for d in im.healthy():
		if d != doll:
			crowd.append(com2(d))
	for z in im.zombies():
		zs.append(com2(z))
	if _time >= _wander_at:
		_wander_at = _time + WANDER_S
		_wander.clear()
		for i in ring.size():
			_wander.append(_rng.randf_range(0.0, WANDER_GAIN))
	for i in ring.size():
		var c: Vector2 = ring[i]
		var s := flee_score(c, me, zp, zs, crowd) + (float(_wander[i]) if i < _wander.size() else 0.0)
		if c == flee_goal:
			cur_s = s
		if s > best_s:
			best_s = s
			best = c
	if flee_goal != Vector2.ZERO and cur_s > best_s - FLEE_HYST:
		return flee_goal
	return best


## Оценка точки бегства c: дальше от ближайшего заражённого zp (и от остальных zs — слабее) — лучше, далеко от меня — хуже, путь мимо
## любого заражённого — штраф, у точки уже кто-то из здоровых (crowd) — штраф.
static func flee_score(c: Vector2, me: Vector2, zp: Vector2, zs: Array = [], crowd: Array = []) -> float:
	var s := c.distance_to(zp) - 0.35 * me.distance_to(c)
	for z in zs:
		var dz := c.distance_to(z as Vector2)
		s += 0.3 * minf(dz, 12.0)
		var seg := Geometry2D.get_closest_point_to_segment(z as Vector2, me, c).distance_to(z as Vector2)
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
