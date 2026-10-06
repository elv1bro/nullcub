## Бот «Гонки: 10 точек» (docs/plan-demo/RACE.md). Каркас — EnemyBrain: плавный ввод тягой, страховка от застревания и пропасти,
## ускорение за Заряд. Без EnemyLook (это гонщик, а не сломанный робот). Цели-куклы нет: цель — горящая точка (RaceMatch.lit_points()).
##   • выбор точки (раз в RETHINK_S и сразу, когда цель погасла): ближняя горящая, но если соперник к ней заметно ближе (его дистанция
##     < yield × моей и разница больше YIELD_GAP_M) — к ней дорого (+FAR_COST_M), бот берёт другую; новая цель должна быть лучше
##     текущей на SWITCH_MARGIN_M — бот не мечется между двумя точками;
##   • путь (пересчёт раз в PATH_S): поиска пути в игре нет — толстый луч к точке (RaceNav.clear); закрыт — перевалка через метку
##     карты по графу видимости RaceNav (видимая метка с кратчайшим «я → метка → граф → цель»); ни одной не видно — местный обход
##     сбоку от препятствия (перпендикуляр к лучу на DETOUR_STEPS м);
##   • полёт: полная тяга к точке (steer_speed, не быстрее CRUISE_MS), далеко и по прямой — ускорение (уровни 2–3);
##   • толчок (shove, уровни 2–3): соперник ближе к моей точке, чем я, и рядом (≤ SHOVE_M) — наскок на него с ускорением: сбить с
##     подлёта — часть игры (MODES_PACK.md §4);
##   • застрял (EnemyBrain: жмёт, а стоит; или топчется в круге STUCK_RADIUS_M дольше STUCK_AREA_S) — выход в самую открытую сторону
##     (из 8 лучей — самый длинный: из кармана — к выходу; застревает там же снова — выход дольше) и смена цели: текущая точка и
##     метка-перевалка — в чёрный список на SKIP_S.
## Уровень 1..3 — Tuning.RACE_BOT_LEVELS; 0 — default_level (его ставит площадка: Match.respawn_doll создаёт мозг заново, экспорт теряется).
class_name RaceBrain
extends EnemyBrain

const RETHINK_S := 0.4
const PATH_S := 0.25
const SWITCH_MARGIN_M := 2.0
const YIELD_GAP_M := 3.0
const FAR_COST_M := 30.0
const CRUISE_MS := 9.0
const DASH_FROM_M := 7.0
const DETOUR_STEPS := [1.6, 3.0, 4.5, 6.0]
const ARRIVE_M := 1.2
const SHOVE_M := 3.0
const SHOVE_S := 0.8
const FLOOR_Y := 0.9
const CEIL_MARGIN := 1.2
const STUCK_RADIUS_M := 1.2
const STUCK_AREA_S := 3.0
const SKIP_S := 6.0

@export var level := 0
static var default_level := 2

var rm: RaceMatch
var goal_point: RacePoint = null
var waypoint := Vector2.ZERO
var detour := false
## Метка-перевалка графа RaceNav, к которой бот летит сейчас (−1 — прямо или местный обход).
var via := -1
var max_in := 0.92
var use_dash := true
var yield_k := 0.65
var shove_k := 0.5
var shove_target: Doll = null
## Счётчики для проб: смен цели, обходов, толчков, выходов из застревания со сменой цели.
var retargets := 0
var detours := 0
var shoves := 0
var _rethink_t := 0.0
var _path_t := 0.0
var _shove_until := -1.0
var _skip: Dictionary = {}        # instance id точки → до какого _time не выбирать
var _skip_via: Dictionary = {}    # метка-перевалка → до какого _time не лететь через неё
var _last_stuck_at := Vector2.INF
var _stuck_here := 0
var _stuck_anchor := Vector2.ZERO
var _stuck_anchor_t := 0.0
var _unstick_n := 0


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
	players_group = "race_nobody"     # цели-куклы у бота нет (EnemyBrain._pick_target ничего не найдёт)
	enemies_group = "race_nobody"     # и разноса со «своими» нет: каждый сам за себя
	var lv := level if level > 0 else default_level
	var p: Dictionary = Tuning.RACE_BOT_LEVELS.get(lv, Tuning.RACE_BOT_LEVELS[2])
	max_in = float(p["max_in"])
	use_dash = bool(p["dash"])
	yield_k = float(p["yield"])
	shove_k = float(p["shove"])
	_rng.seed = hash(String(doll.name)) ^ 0x7ace
	go("race")


func _find_match() -> void:
	if rm == null or not is_instance_valid(rm):
		rm = get_tree().get_first_node_in_group(Match.GROUP) as RaceMatch


func _think(delta: float) -> void:
	_find_match()
	if rm == null or rm.play_state != "play":
		want = hover_vec()
		return
	_rethink_t -= delta
	var lost := goal_point == null or not is_instance_valid(goal_point) or goal_point.is_queued_for_deletion()
	if lost or _rethink_t <= 0.0:
		_rethink_t = RETHINK_S
		_choose(lost)
	if goal_point == null or not is_instance_valid(goal_point):
		go("hover")
		want = hover_vec()
		return
	var me := my_pos()
	var gp := Vector2(goal_point.home.x, goal_point.home.y)
	if _time < _shove_until and shove_target != null and is_instance_valid(shove_target) and shove_target.alive:
		go("shove")
		want = steer(com2(shove_target), max_in)
		if use_dash:
			dash()
		return
	shove_target = null
	if shove_k > 0.0 and _try_shove(me, gp):
		return
	_path_t -= delta
	if _path_t <= 0.0:
		_path_t = PATH_S
		_plan(me, gp)
	var aim := waypoint if detour else gp
	go("detour" if detour else "race")
	want = steer_speed(_clamp_goal(aim), CRUISE_MS, max_in)
	if use_dash and not detour and me.distance_to(gp) > DASH_FROM_M:
		dash()


## Выбор цели: ближняя горящая точка с поправкой «соперник заметно ближе — дорого»; смена — только если лучше на SWITCH_MARGIN_M.
func _choose(force: bool) -> void:
	var me := my_pos()
	var best: RacePoint = null
	var best_c := INF
	var cur_c := INF
	for p in rm.lit_points():
		var rp := p as RacePoint
		if float(_skip.get(rp.get_instance_id(), -1.0)) > _time:
			continue
		var c := cost_of(rp, me)
		if rp == goal_point:
			cur_c = c
		if c < best_c:
			best_c = c
			best = rp
	if best == null:   # все в чёрном списке — ближайшая, какая есть
		for p in rm.lit_points():
			var c2 := me.distance_to(Vector2((p as RacePoint).home.x, (p as RacePoint).home.y))
			if c2 < best_c:
				best_c = c2
				best = p
	if best == goal_point:
		return
	if not force and goal_point != null and is_instance_valid(goal_point) and cur_c <= best_c + SWITCH_MARGIN_M:
		return
	goal_point = best
	retargets += 1
	_path_t = 0.0


## Цена точки: моя дистанция; соперник (живой) ближе меня в yield_k раз и на YIELD_GAP_M — +FAR_COST_M.
func cost_of(p: RacePoint, me: Vector2) -> float:
	var pp := Vector2(p.home.x, p.home.y)
	var mine := me.distance_to(pp)
	var rival := INF
	for d in rm.alive_dolls():
		if d == doll:
			continue
		rival = minf(rival, com2(d).distance_to(pp))
	if rival < mine * yield_k and mine - rival > YIELD_GAP_M:
		return mine + FAR_COST_M
	return mine


## Толчок: соперник ближе меня к моей точке и рядом со мной — наскок на него (с вероятностью по shove_k, не чаще раза в SHOVE_S·3).
func _try_shove(me: Vector2, gp: Vector2) -> bool:
	if _time < _shove_until + SHOVE_S * 3.0:
		return false
	var mine := me.distance_to(gp)
	for d in rm.alive_dolls():
		if d == doll:
			continue
		var dd := d as Doll
		var c := com2(dd)
		if c.distance_to(me) <= SHOVE_M and c.distance_to(gp) < mine and mine < 9.0 and dd.grace_until <= dd._time:
			if _rng.randf() < shove_k:
				shove_target = dd
				_shove_until = _time + SHOVE_S
				shoves += 1
				note_attack()
				return true
			_shove_until = _time   # не повезло — следующий раз не раньше SHOVE_S·3
			return false
	return false


## Путь: толстый луч к цели чист — прямо. Закрыт — через метку карты (граф видимости RaceNav): из видимых меток та, у которой
## «я → метка + путь по графу до цели» короче всего; долетел до метки (ближе ARRIVE_M) — следующая. Графа нет или ни одна метка
## не видна — местный обход сбоку от препятствия (точка на перпендикуляре к лучу, DETOUR_STEPS м).
func _plan(me: Vector2, gp: Vector2) -> void:
	var space := _space()
	var ex := _own_rids()
	if RaceNav.clear(space, me, gp, ex):
		detour = false
		via = -1
		return
	var nv := rm.nav()
	var gm := goal_point.mark if goal_point != null and is_instance_valid(goal_point) else -1
	if nv != null and nv.ready() and gm >= 0:
		var cands: Array = []
		for i in nv.marks.size():
			if i == gm or float(_skip_via.get(i, -1.0)) > _time:
				continue
			var pl := nv.path_len(i, gm)
			if pl == INF:
				continue
			var m2 := Vector2(nv.marks[i].x, nv.marks[i].y)
			if m2.distance_to(me) < ARRIVE_M:
				continue   # уже у этой метки — дальше по графу
			cands.append([me.distance_to(m2) + pl, i, m2])
		cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		for c in cands:
			if RaceNav.clear(space, me, c[2] as Vector2, ex):
				if via != int(c[1]):
					detours += 1
				via = int(c[1])
				waypoint = c[2] as Vector2
				detour = true
				return
	via = -1
	var hit := RaceNav.ray(space, me, gp, ex)
	if hit.is_empty():
		detour = false   # тонкий луч чист, толстый задел край — прямо
		return
	var hp: Vector2 = hit["pos"]
	var dir := (gp - me).normalized() if me.distance_to(gp) > 0.01 else Vector2.RIGHT
	var perp := Vector2(-dir.y, dir.x)
	for k in DETOUR_STEPS:
		for s in [1.0, -1.0]:
			var wp := _clamp_goal(hp + perp * float(s) * float(k) - dir * 0.6)
			if RaceNav.ray(space, me, wp, ex).is_empty():
				if not detour or waypoint.distance_to(wp) > 0.5:
					detours += 1
				waypoint = wp
				detour = true
				return
	detour = false   # обхода нет — прямо (выручит выход из застревания)


func _space() -> PhysicsDirectSpaceState3D:
	return doll.get_world_3d().direct_space_state if doll.is_inside_tree() else null


func _own_rids() -> Array[RID]:
	var ex: Array[RID] = []
	for p in doll.parts.values():
		if is_instance_valid(p):
			ex.append((p as RigidBody3D).get_rid())
	return ex


func _clamp_goal(g: Vector2) -> Vector2:
	var b := arena_bounds()
	return Vector2(clampf(g.x, b.position.x + 1.2, b.end.x - 1.2), clampf(g.y, FLOOR_Y, b.end.y - CEIL_MARGIN))


func _stuck_allowed() -> bool:
	return state in ["race", "detour", "hover"]


## Застревание (поверх EnemyBrain): «жмёт, а стоит» или «топчется в круге STUCK_RADIUS_M дольше STUCK_AREA_S» — выход в самую
## открытую сторону (_open_dir) и смена цели (точка и перевалка — в чёрный список на SKIP_S).
func _tick_stuck(delta: float) -> void:
	if _time < _unstick_until:
		want = _unstick_dir
		return
	var me := my_pos()
	if rm == null or rm.play_state != "play":
		_stuck_anchor = me   # отсчёт и итоги: кукла стоит не по своей вине
		_stuck_anchor_t = _time
		_stuck_t = 0.0
		return
	var pushing := _stuck_allowed() and want.length() >= STUCK_INPUT
	# круг считается во всех состояниях гонки (и в толчке: «толкнул — вернулся к точке — толкнул» на одном месте — тоже застрял)
	if not (_stuck_allowed() or state == "shove") or me.distance_to(_stuck_anchor) > STUCK_RADIUS_M:
		_stuck_anchor = me
		_stuck_anchor_t = _time
	_stuck_t = _stuck_t + delta if pushing and my_vel().length() < STUCK_SPEED else 0.0
	if _stuck_t < STUCK_S and _time - _stuck_anchor_t < STUCK_AREA_S:
		return
	_stuck_t = 0.0
	_stuck_anchor = me
	_stuck_anchor_t = _time
	_unstick_n += 1
	_unstick_until = _time + UNSTICK_S * (1.0 + 0.5 * float(mini(_unstick_n_here(me), 3)))
	_unstick_dir = _open_dir(me)
	counters["unstick"] = int(counters.get("unstick", 0)) + 1
	if goal_point != null and is_instance_valid(goal_point):
		_skip[goal_point.get_instance_id()] = _time + SKIP_S
	if via >= 0:
		_skip_via[via] = _time + SKIP_S   # перевалка, через которую не пролезть, — тоже в чёрный список
	goal_point = null
	detour = false
	via = -1
	_rethink_t = 0.0


## Сколько раз подряд бот застревал в этом месте (≤ 3 м от прошлого застревания) — выход с каждым разом дольше.
func _unstick_n_here(me: Vector2) -> int:
	if me.distance_to(_last_stuck_at) > 3.0:
		_stuck_here = 0
	_last_stuck_at = me
	_stuck_here += 1
	return _stuck_here - 1


## Куда выбираться: из 8 направлений — то, где луч до препятствия длиннее всего (из кармана — к выходу); поровну — вверх и по кругу.
func _open_dir(me: Vector2) -> Vector2:
	var space := _space()
	var ex := _own_rids()
	var best := Vector2.UP
	var best_l := -1.0
	for k in 8:
		var d := Vector2.UP.rotated(TAU * float(k) / 8.0 + 0.2 * float(_unstick_n % 3))
		var hit := RaceNav.ray(space, me, me + d * 5.0, ex)
		var l := 5.0 if hit.is_empty() else me.distance_to(hit["pos"] as Vector2)
		l += 0.4 * d.y   # при равных — вверх (полёт), а не в пол
		if l > best_l:
			best_l = l
			best = d
	return best


func _silenced(_why: String) -> void:
	shove_target = null
	_shove_until = -1.0
