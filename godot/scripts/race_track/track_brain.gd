## Бот «Гонки: трасса» (docs/plan-demo/RACE_TRACK.md). Каркас — EnemyBrain (плавный ввод, ускорение за Заряд), без EnemyLook. Поиска пути
## в игре нет: бот летит по линии трассы (TrackRoute карты — точки проложены руками в сборщике):
##   • ветки развилок выбираются один раз на гонку: уровень бота (Tuning.TRACK_BOT_LEVELS hard — вероятность трудной) и зерно
##     (имя куклы ^ seed_salt — после возврата тот же выбор); пробы задают ветки сами (force_choices по player_index);
##   • «морковка» — точка линии на look м впереди (мета look у точек: в трубах ближе, на просторе дальше); желаемая скорость — cruise,
##     у точек с метой v — не быстрее (тормозит заранее с BRAKE_A); ввод = (нужное ускорение + против вязкости + против поля) / тяга —
##     поле зоны (вбок, вверх, тяжёлое) бот компенсирует сам;
##   • ускорение (Заряд): нужное больше, чем даёт обычная тяга, — на прямой (уровни 2–3) или где без него не подняться (мета dash,
##     поле тяжелее тяги) — тогда держит, пока есть Заряд;
##   • пресс (мета press у точки перед ним): такта нет (до удара меньше PRESS_NEED_S) — висит у точки и ждёт;
##   • портал (мета jump у точки в кармане щели A): «морковка» продолжает прямую входа — бот влетает в щель по нормали со скоростью
##     меты v, пара переносит его к выходу B, дальше — линия за выходом;
##   • подъём за Заряд (мета charge у точки перед тяжёлой зоной): за SAVE_CHARGE_M до неё ускорение на прямой не включает, у точки ждёт,
##     пока Заряд не наберётся до значения меты (полный бак — на весь подъём);
##   • застрял (жмёт, а стоит): рывок в самую открытую сторону с уклоном вперёд по линии; далеко от линии (сбили) — линия заново;
##   • толчок (уровни 2–3): сосед рядом и чуть впереди на просторе — наскок с ускорением (как в «Гонке: 10 точек»).
class_name TrackBrain
extends EnemyBrain

const LOOK_M := 3.5
const BRAKE_A := 5.0
const KV := 2.6                      # 1/с: догон желаемой скорости
const DAMP_FF := 1.8                 # 1/с: вязкость куклы (ядро 2.25, конечности 1.5) — тяга на её преодоление
const AHEAD_M := 14.0
const OFF_ROUTE_M := 6.0
const PRESS_NEED_S := 1.35
const PRESS_LOOK_M := 4.5
const PRESS_RAM_SAFE := 2.9
const SHOVE_M := 2.6
const SHOVE_S := 0.55
const SHOVE_EVERY_S := 1.6
const HEAVY_FRAC := 0.8              # поле тяжелее этой доли тяги — без ускорения не подняться
const CHARGE_LOOK_M := 1.5           # точка с метой charge ближе — ждать Заряда
const SAVE_CHARGE_M := 40.0          # точка с метой charge ближе — на прямой не тратить Заряд

@export var level := 0
static var default_level := 2
## Пробы: player_index → {fork → "easy" | "hard"} — ветки принудительно.
static var force_choices: Dictionary = {}
## Пробы и площадка: соль зерна выбора веток (разные гонки — разный выбор).
static var seed_salt := 0

var tm: TrackMatch
var route: TrackRoute
var choice: Dictionary = {}
var seg := -1
var s_along := 0.0
var goal := Vector2.ZERO
var max_in := 0.95
var cruise := 8.0
var dash_straight := true
var hard_p := 0.5
var shove_k := 0.3
var holding := false
## Для проб: сколько секунд ждал такта прессов, сколько толкнул, сколько раз возвращался на линию, тиков ускорения «по нужде».
var hold_s := 0.0
var shoves := 0
var relines := 0
var forced_dash_ticks := 0
var _shove_target: Doll = null
var _shove_until := -1.0
var _shove_check := 0.0
var _force_dash := false
var _charging_done := false
## Впереди подъём за Заряд (мета charge ближе SAVE_CHARGE_M): ускорение на прямой не включать.
var saving := false


## Как EnemyBrain._setup, но без EnemyLook: гонщик, а не робот-враг.
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
	players_group = "track_nobody"
	enemies_group = "track_nobody"
	input_slew = 9.0
	var lv := level if level > 0 else default_level
	var p: Dictionary = Tuning.TRACK_BOT_LEVELS.get(lv, Tuning.TRACK_BOT_LEVELS[2])
	max_in = float(p["max_in"])
	cruise = float(p["cruise"])
	dash_straight = bool(p["dash"])
	hard_p = float(p["hard"])
	shove_k = float(p["shove"])
	_rng.seed = hash(String(doll.name)) ^ 0x7ac4 ^ (seed_salt * 7919)
	choice.clear()
	var forced: Dictionary = force_choices.get(doll.player_index, {})
	for f in ["A", "B", "C"]:
		var r := _rng.randf()
		choice[f] = String(forced[f]) if forced.has(f) else ("hard" if r < hard_p else "easy")
	seg = -1
	go("race")


func _find_match() -> void:
	if tm == null or not is_instance_valid(tm):
		tm = get_tree().get_first_node_in_group(Match.GROUP) as TrackMatch
	if tm != null and (route == null or not route.ready()):
		route = tm.route


func _think(delta: float) -> void:
	_find_match()
	holding = false
	_force_dash = false
	if tm == null or route == null or not route.ready() or tm.play_state != "play":
		want = hover_vec()
		return
	var st := tm.state_of(doll)
	if bool(st.get("finished", false)):
		go("done")
		want = _drive(Vector2(tm.arena_node.finish_x() + 8.0, 2.5) if tm.arena_node != null else my_pos(), 2.0)
		return
	var me := my_pos()
	_locate(me, float(st.get("prog", 0.0)))
	if seg < 0:
		want = hover_vec()
		return
	# толчок
	if _time < _shove_until and _shove_target != null and is_instance_valid(_shove_target) and _shove_target.alive:
		go("shove")
		want = _drive(com2(_shove_target), cruise, true)
		return
	_shove_target = null
	_shove_check -= delta
	if shove_k > 0.0 and _shove_check <= 0.0:
		_shove_check = SHOVE_EVERY_S
		if _try_shove(me):
			return
	# морковка и скорость
	var ahead := route.points_ahead(seg, s_along, SAVE_CHARGE_M, choice)
	var look := LOOK_M
	var v_lim := cruise
	var dash_meta := false
	saving = false
	for e in ahead:
		var d := float(e[0])
		var m: Dictionary = e[1]
		if d <= 2.5 and m.has("look"):
			look = float(m["look"])
		if m.has("v") and d <= AHEAD_M:
			v_lim = minf(v_lim, sqrt(float(m["v"]) * float(m["v"]) + 2.0 * BRAKE_A * d))
		if d <= 3.0 and bool(m.get("dash", false)):
			dash_meta = true
		if m.has("press") and d <= PRESS_LOOK_M and not _press_clear(String(m["press"])):
			holding = true
			goal = e[2]
		if m.has("charge"):
			if d <= CHARGE_LOOK_M and doll.charge < float(m["charge"]) and not _charging_done:
				holding = true
				goal = e[2]
			elif d > CHARGE_LOOK_M:
				_charging_done = false
			if d <= SAVE_CHARGE_M:
				saving = true   # впереди подъём за Заряд — на прямой не тратить
	if holding:
		go("hold")
		hold_s += delta
		want = _drive(goal, 3.0, false, true)
		if doll.charge >= doll.charge_cap() - 1.0:
			_charging_done = true
		return
	goal = route.point_ahead(seg, s_along, look, choice)
	go("race")
	_force_dash = dash_meta
	want = _drive(goal, v_lim)


## Где я на линии: на своём отрезке или следующем по выбору; далеко от линии (сбили, вернулся на точку) — по всей линии.
func _locate(me: Vector2, prog_hint: float) -> void:
	if seg >= 0:
		var best := _on_seg(seg, me)
		var nx := route.next_of(seg, choice)
		if nx >= 0:
			var b2 := _on_seg(nx, me)
			if float(b2["dist"]) < float(best["dist"]) - 0.3 or float(best["s"]) >= route.segs[seg].length - 0.05:
				if float(b2["dist"]) <= float(best["dist"]) + 1.0:
					seg = nx
					best = b2
		if float(best["dist"]) <= OFF_ROUTE_M:
			s_along = float(best["s"])
			return
	var pr := route.project(me, prog_hint, 30.0, -1)
	if pr.is_empty():
		seg = -1
		return
	seg = int(pr["seg"])
	# чужая ветка (сбили на другой путь) — летим по ней же
	var sg := route.segs[seg]
	if sg.kind != "main":
		choice[sg.fork] = sg.kind
	s_along = float(pr["s"])
	relines += 1


func _on_seg(si: int, me: Vector2) -> Dictionary:
	var sg := route.segs[si]
	var best := {"dist": INF, "s": 0.0}
	for k in sg.pts.size() - 1:
		if TrackRoute.is_jump(sg, k):
			continue
		var a := sg.pts[k]
		var b := sg.pts[k + 1]
		var ab := b - a
		var l2 := ab.length_squared()
		var t := clampf((me - a).dot(ab) / l2, 0.0, 1.0) if l2 > 1e-6 else 0.0
		var d := me.distance_to(a + ab * t)
		if d < float(best["dist"]):
			best = {"dist": d, "s": TrackRoute.past_jump(sg, k, sg.cum[k] + sqrt(l2) * t)}
	return best


## Ввод к цели: желаемая скорость по направлению на цель (не больше v_max; arrive — тормозит у цели), ускорение против вязкости и
## поля, делённое на тягу. Не хватает обычной тяги — ускорение (если можно: на прямой по уровню, мета dash, тяжёлое поле, толчок).
func _drive(target: Vector2, v_max: float, shove := false, arrive := false) -> Vector2:
	var me := my_pos()
	var v := my_vel()
	var to := target - me
	var dist := to.length()
	var speed := v_max
	if arrive:
		speed = minf(v_max, dist * 1.8)
	var v_des := to / dist * speed if dist > 0.05 else Vector2.ZERO
	var g := gravity_vec()
	var a_steer := (v_des - v) * KV + v_des * DAMP_FF
	var a_thr := maxf(_thrust_acc(false), 0.1)
	var full := (a_steer - g) / a_thr
	var heavy := g.length() > a_thr * HEAVY_FRAC
	var need_dash := full.length() > max_in and (shove or _force_dash or heavy or (dash_straight and not saving and speed >= cruise - 0.1 and not arrive))
	var a_use := a_thr
	var cap := max_in
	if need_dash and doll.can_spend_charge():
		a_use = maxf(_thrust_acc(true), 0.1)
		cap = 1.0
		if _force_dash or heavy:
			doll.request_dash()   # держать, пока есть Заряд (без порогов EnemyBrain.dash: подъём в тяжёлом поле не ждёт)
			forced_dash_ticks += 1
		else:
			dash()
	return fit_input(-g / a_use, a_steer / a_use, cap)


## Ввод не длиннее cap: сначала — держать вес (base, против поля), остаток — на руление (steer), насколько влезает. Иначе при упоре
## в предел ввода руление «съедало» долю против поля и бот тонул (яма, тяжёлое поле).
static func fit_input(base: Vector2, steer: Vector2, cap: float) -> Vector2:
	if base.length() >= cap:
		return base.limit_length(cap)
	var both := base + steer
	if both.length() <= cap:
		return both
	var ss := steer.length_squared()
	if ss < 1e-8:
		return base
	var gs := base.dot(steer)
	var k := (-gs + sqrt(maxf(gs * gs - ss * (base.length_squared() - cap * cap), 0.0))) / ss
	return base + steer * clampf(k, 0.0, 1.0)


## Ускорение тяги куклы, м/с² (с ускорением — × dash_mult).
func _thrust_acc(dashing: bool) -> float:
	if doll.total_mass <= 0.0:
		return Tuning.MOVE_FORCE_PER_KG
	var a := ControlFeel.thrust() * doll.thrust_mass() * doll.thrust_mult / doll.total_mass
	return a * (ControlFeel.dash_mult() if dashing else 1.0)


## Пресс пролетать можно: до следующего удара не меньше PRESS_NEED_S (или ползун уже поднялся выше PRESS_RAM_SAFE).
func _press_clear(path: String) -> bool:
	if tm == null or tm.arena_node == null:
		return true
	var p := tm.arena_node.get_node_or_null(path) as PressMachine
	if p == null:
		return true
	return time_to_slam(p) >= PRESS_NEED_S or (p.state == ScrapMachine.State.COOLDOWN and p.ram_y >= PRESS_RAM_SAFE
		and p.state_left() + p.off_s + p.warning_s >= PRESS_NEED_S)


## Секунд до начала удара пресса (ACTIVE).
static func time_to_slam(p: PressMachine) -> float:
	match p.state:
		ScrapMachine.State.OFF:
			return p.state_left() + p.warning_s
		ScrapMachine.State.WARNING:
			return p.state_left()
		ScrapMachine.State.ACTIVE:
			return 0.0
	return p.state_left() + p.off_s + p.warning_s


## Толчок: сосед рядом и чуть впереди по прогрессу, на просторе (не в трубе) — наскок.
func _try_shove(me: Vector2) -> bool:
	var my_prog := tm.progress_of(doll)
	for d in tm.alive_dolls():
		if d == doll:
			continue
		var dd := d as Doll
		var c := com2(dd)
		var dp := tm.progress_of(dd) - my_prog
		if c.distance_to(me) <= SHOVE_M and dp > 0.0 and dp < 4.0 and dd.grace_until <= dd._time and not _narrow_here():
			if _rng.randf() < shove_k:
				_shove_target = dd
				_shove_until = _time + SHOVE_S
				shoves += 1
				note_attack()
				return true
			return false
	return false


## В узком месте (точки рядом с метой look ≤ 2.5 — трубы, щель, короб): толкаться нельзя.
func _narrow_here() -> bool:
	for e in route.points_ahead(seg, maxf(s_along - 3.0, 0.0), 6.0, choice):
		if (e[1] as Dictionary).has("look") and float(e[1]["look"]) <= 2.5:
			return true
	return false


func _stuck_allowed() -> bool:
	return state in ["race", "shove"]


## Застрял (жмёт, а стоит STUCK_S): рывок в самую открытую сторону с уклоном вперёд по линии.
func _tick_stuck(delta: float) -> void:
	if _time < _unstick_until:
		want = _unstick_dir
		return
	if _stuck_allowed() and want.length() >= STUCK_INPUT and my_vel().length() < STUCK_SPEED:
		_stuck_t += delta
	else:
		_stuck_t = 0.0
	if _stuck_t < STUCK_S:
		return
	_stuck_t = 0.0
	_unstick_until = _time + UNSTICK_S
	_unstick_dir = _open_dir(my_pos())
	counters["unstick"] = int(counters.get("unstick", 0)) + 1


func _open_dir(me: Vector2) -> Vector2:
	var space := doll.get_world_3d().direct_space_state if doll.is_inside_tree() else null
	var ex: Array[RID] = []
	for p in doll.parts.values():
		if is_instance_valid(p):
			ex.append((p as RigidBody3D).get_rid())
	var fwd := (goal - me).normalized() if goal.distance_to(me) > 0.1 else Vector2.RIGHT
	var best := fwd
	var best_s := -INF
	for k in 8:
		var d := Vector2.RIGHT.rotated(TAU * float(k) / 8.0)
		var hit := RaceNav.ray(space, me, me + d * 4.0, ex)
		var l := 4.0 if hit.is_empty() else me.distance_to(hit["pos"] as Vector2)
		var s := l + 1.5 * d.dot(fwd)
		if s > best_s:
			best_s = s
			best = d
	return best


func _silenced(_why: String) -> void:
	_shove_target = null
	_shove_until = -1.0
