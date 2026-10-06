## Матч «Гонка: 10 точек» (docs/plan-demo/RACE.md; docs/plan-demo/MODES_PACK.md §4; автор 06.10: «гонки — нужно быстрее собрать
## 10 пунктов, кто быстрее соберёт их»; «у всех одни и те же точки: если кто-то взял, то у тебя этой точки уже нет, и надо к следующей»).
## Наследник Match: от него — регистрация кукол (DollCombat), удары с уроном, KO, отсчёт, надписи. Своё:
##   • метки (marks) — точки карты, где может загореться точка: Marker3D площадки (узел RaceMarks, set_marks), 16–20 на карту;
##   • горят сразу visible точек (Tuning.RACE_VISIBLE, работает 1..6; не больше меток − 1) на случайных свободных метках; первые — не
##     ближе RACE_NEW_MIN_M к центру старта;
##   • взятие: любая деталь живой куклы ближе RACE_PICK_M к центру горящей точки (проверка каждый тик физики, как SupplyCrate).
##     Точку взял один — она гаснет у всех (+1 ему), вместо неё загорается новая на случайной свободной метке (не горящей и не ближе
##     RACE_NEW_MIN_M к взявшему; таких нет — на самой дальней свободной). Коснулись двое в одном тике — берёт тот, чья деталь ближе;
##   • первый, кто набрал to_win (RACE_TO_WIN), побеждает — конец гонки. Лимит RACE_TIME_LIMIT_S: вышло — побеждает тот, у кого
##     больше точек (равно — кто раньше их набрал); Sudden Death и «последний живой» базового Match выключены;
##   • KO (удар, пропасть) → возврат через RACE_RESPAWN_S у последней точки, которую взяла эта кукла (не брала — на старте; горит
##     на ней сейчас точка — у ближайшей негорящей метки), первые RACE_SPAWN_SHIELD_S урон не проходит;
##   • удары с уроном, как в бою; эффекты удара (тряска, стоп-кадр, надписи) — только если в ударе участвует человек: удары ботов
##     между собой на другом краю карты дёргали бы кадр (как в стычке, SQUAD.md); крит-кино выключено — гонка не стоит 1.5 с.
## Сигналы для HUD (scenes/race/race_hud.gd), площадки и проб: point_taken, point_lit, score_changed, respawn_queued, doll_respawned
## + унаследованные. takes — журнал взятий для проб: [{t, pi, mark, pos, score, new_mark, new_pos, new_dist}].
class_name RaceMatch
extends Match

signal point_taken(doll: Doll, mark: int, position: Vector3, score: int)
signal point_lit(mark: int, position: Vector3)
signal score_changed(scores: Dictionary)
signal respawn_queued(victim: Doll, seconds: float)
signal doll_respawned(doll: Doll)

const POINTS_NODE := "RacePoints"
const VISIBLE_MAX := 6

@export var to_win: int = Tuning.RACE_TO_WIN
@export var visible_count: int = Tuning.RACE_VISIBLE
@export var respawn_s: float = Tuning.RACE_RESPAWN_S
## Зерно случайного выбора меток (пробы — повторяемость); 0 — каждый раз новое.
@export var seed_value := 0

## Метки карты (мировые точки) и точки старта по player_index — ставит площадка (set_marks / set_starts).
var marks: Array[Vector3] = []
var starts: Array[Vector3] = []
## player_index → взято точек.
var scores: Dictionary = {}
## player_index → индекс метки последней взятой точки (возврат после KO).
var last_mark: Dictionary = {}
## player_index → время (fight_time) последнего взятия: при равном счёте выше тот, кто набрал раньше.
var last_take_t: Dictionary = {}
## player_index → {kos, kos_taken} — для итогов.
var tally: Dictionary = {}
## idle | countdown | play | over
var play_state := "idle"
var takes: Array = []
var winner_index := -1
## Кукла «я» для HUD и камеры, когда людей нет (пробы: за P1 играет бот): player_index или −1.
var focus_index := -1
var _lit: Array = []              # [RacePoint]
var _respawns: Array = []         # [[Doll, осталось с]]
var _respawn_at: Dictionary = {}  # player_index → точка возврата (только на время respawn_doll)
var _rng := RandomNumberGenerator.new()
var _sfx: Node = null
var _nav: RaceNav = null


func _ready() -> void:
	time_limit_s = Tuning.RACE_TIME_LIMIT_S
	hard_timeout_s = Tuning.RACE_TIME_LIMIT_S
	super._ready()
	crit_enabled = false


# --- метки и старт ---

func set_marks(pts: Array) -> void:
	marks.clear()
	for p in pts:
		marks.append(Vector3((p as Vector3).x, (p as Vector3).y, 0.0))


func set_starts(pts: Array) -> void:
	starts.clear()
	for p in pts:
		starts.append(Vector3((p as Vector3).x, (p as Vector3).y, 0.0))


## Сколько точек горит одновременно: visible_count в пределах 1..VISIBLE_MAX и не больше меток − 1 (иначе новой некуда загореться).
func visible_target() -> int:
	return clampi(visible_count, 1, maxi(mini(VISIBLE_MAX, marks.size() - 1), 1))


## Точка старта куклы (по player_index) — или точка возврата, если её сейчас возрождают у взятой точки.
func spawn_point_for(d: Doll) -> Vector3:
	if _respawn_at.has(d.player_index):
		return _respawn_at[d.player_index]
	if d.player_index >= 0 and d.player_index < starts.size():
		return starts[d.player_index]
	return super.spawn_point_for(d)


## Граф видимости по меткам для ботов (RaceNav) — строится при первом запросе (в тике физики: нужна direct_space_state).
func nav() -> RaceNav:
	if _nav == null or _nav.marks.size() != marks.size():
		var a := _arena() as Node3D
		var space := a.get_world_3d().direct_space_state if a != null and a.is_inside_tree() else null
		if space == null:
			return null
		_nav = RaceNav.new()
		_nav.build(space, marks)
	return _nav


func start_centre() -> Vector3:
	if starts.is_empty():
		return Vector3.ZERO
	var c := Vector3.ZERO
	for s in starts:
		c += s
	return c / float(starts.size())


# --- горящие точки ---

## Горящие точки (живые узлы RacePoint).
func lit_points() -> Array:
	var out: Array = []
	for p in _lit:
		if is_instance_valid(p) and not (p as Node).is_queued_for_deletion():
			out.append(p)
	return out


## Индексы меток, на которых сейчас горят точки.
func lit_marks() -> Array:
	return lit_points().map(func(p: Variant) -> int: return (p as RacePoint).mark)


func _points_root() -> Node3D:
	var parent := get_parent()
	var n := parent.get_node_or_null(POINTS_NODE) as Node3D if parent != null else null
	if n == null and parent != null:
		n = Node3D.new()
		n.name = POINTS_NODE
		parent.add_child(n)
	return n


func _clear_points() -> void:
	for p in _lit:
		if is_instance_valid(p):
			(p as Node).queue_free()
	_lit.clear()


## Зажечь точку на метке i.
func _light(i: int) -> RacePoint:
	var root := _points_root()
	var p := RacePoint.make(i, marks[i])
	if root != null:
		root.add_child(p)
	_lit.append(p)
	point_lit.emit(i, marks[i])
	return p


## Свободная метка для новой точки: не горит, не exclude и не ближе min_m к from (from = null — без условия). Подходящих нет —
## самая дальняя от from свободная; свободных нет — −1.
func pick_free_mark(from: Variant, min_m: float, exclude: Array = []) -> int:
	var busy := lit_marks()
	var ok: Array = []
	var best := -1
	var best_d := -1.0
	for i in marks.size():
		if busy.has(i) or exclude.has(i):
			continue
		var d := INF if from == null else Vector2(marks[i].x - (from as Vector3).x, marks[i].y - (from as Vector3).y).length()
		if d >= min_m:
			ok.append(i)
		if d > best_d:
			best_d = d
			best = i
	if not ok.is_empty():
		return int(ok[_rng.randi_range(0, ok.size() - 1)])
	return best


## Начальные точки: visible_target() штук на случайных метках не ближе RACE_NEW_MIN_M к центру старта.
func _light_initial() -> void:
	_clear_points()
	var centre := start_centre()
	for k in visible_target():
		var i := pick_free_mark(centre, Tuning.RACE_NEW_MIN_M)
		if i < 0:
			break
		_light(i)


## Проверка взятий (каждый тик боя): для каждой горящей точки — ближайшая деталь живой куклы; ближе RACE_PICK_M — взята.
func _tick_points() -> void:
	var r2 := Tuning.RACE_PICK_M * Tuning.RACE_PICK_M
	for p in lit_points():
		var pos := (p as RacePoint).home
		var best: Doll = null
		var best_d2 := r2
		for d in alive_dolls():
			var dd := d as Doll
			if not dd.is_inside_tree() or dd.centre_of_mass().distance_squared_to(pos) > 9.0:
				continue
			for part in dd.parts.values():
				if not is_instance_valid(part):
					continue
				var d2 := (part as Node3D).global_position.distance_squared_to(pos)
				if d2 <= best_d2:
					best_d2 = d2
					best = dd
		if best != null:
			take_point(best, p)
			if play_state != "play":
				return


## Кукла d взяла точку p: +1, точка гаснет у всех, новая — на свободной метке не ближе RACE_NEW_MIN_M к взявшему; to_win — победа.
func take_point(d: Doll, p: RacePoint) -> void:
	if play_state != "play" or not is_instance_valid(p) or not _lit.has(p) or not is_instance_valid(d):
		return
	var pi := d.player_index
	var sc := int(scores.get(pi, 0)) + 1
	scores[pi] = sc
	last_mark[pi] = p.mark
	last_take_t[pi] = fight_time
	_lit.erase(p)
	var colour: Color = Tuning.PLAYER_COLORS[pi % Tuning.PLAYER_COLORS.size()] if pi >= 0 else Color.WHITE
	var taken_mark := p.mark
	var taken_pos := p.home
	p.take(colour)
	var from := d.centre_of_mass()
	var rec := {"t": snappedf(fight_time, 0.01), "pi": pi, "mark": taken_mark, "pos": taken_pos, "score": sc, "new_mark": -1,
		"new_pos": Vector3.ZERO, "new_dist": -1.0, "lit_before": _lit.size() + 1}
	if sc < to_win:
		var i := pick_free_mark(from, Tuning.RACE_NEW_MIN_M, [taken_mark])
		if i >= 0:
			_light(i)
			rec["new_mark"] = i
			rec["new_pos"] = marks[i]
			rec["new_dist"] = snappedf(Vector2(marks[i].x - from.x, marks[i].y - from.y).length(), 0.01)
	takes.append(rec)
	point_taken.emit(d, taken_mark, taken_pos, sc)
	score_changed.emit(scores.duplicate())
	_take_sound(d, sc)
	if sc >= to_win:
		winner_index = pi
		_finish("points")


## Звук взятия: своё (человек) — нота выше с каждой точкой, десятая — колокол; чужое — короткий низкий сигнал.
func _take_sound(d: Doll, sc: int) -> void:
	if not feel_enabled:
		return
	if _sfx == null or not is_instance_valid(_sfx):
		_sfx = get_tree().get_first_node_in_group(SfxDirector.GROUP)
		if _sfx == null:
			return
	if _is_human(d):
		_sfx.call("play_layer", "combo", 0.0, clampf(1.0 + 0.06 * float(sc - 1), 1.0, 1.6), SfxDirector.BUS_UI, 0.0)
		_sfx.call("play_layer", "equip", -4.0, 1.15, SfxDirector.BUS_UI, 0.0)
		if sc >= to_win:
			_sfx.call("play_layer", "bell", 0.0, 1.0, SfxDirector.BUS_UI, 0.0)
	else:
		_sfx.call("play_layer", "callout", -3.0, 0.72, SfxDirector.BUS_UI, 0.0)


# --- фазы ---

func begin() -> void:
	scores.clear()
	last_mark.clear()
	last_take_t.clear()
	takes.clear()
	winner_index = -1
	_respawns.clear()
	_respawn_at.clear()
	_rng.seed = seed_value if seed_value != 0 else int(Time.get_ticks_usec())
	for k in tally.keys():
		tally[k] = {"kos": 0, "kos_taken": 0}
	_clear_points()
	play_state = "countdown"
	super.begin()
	for d in dolls():
		scores[(d as Doll).player_index] = 0
	score_changed.emit(scores.duplicate())


func restart() -> void:
	_respawn_at.clear()
	_respawns.clear()
	super.restart()


func _start_fight() -> void:
	super._start_fight()
	play_state = "play"
	_light_initial()


func _finish(reason: String) -> void:
	if phase == Phase.OVER:
		return
	play_state = "over"
	_respawns.clear()
	if winner_index < 0:
		var lead := leader()
		winner_index = lead.player_index if lead != null else -1
	for d in dolls():
		(d as Doll).control_enabled = false
	super._finish(reason)


func stasis_allowed() -> bool:
	return play_state == "play" and super.stasis_allowed()


func knockback_mult() -> float:
	return 1.0


func stability_mult() -> float:
	return 1.0


func time_left_s() -> float:
	match phase:
		Phase.COUNTDOWN:
			return time_limit_s
		Phase.FIGHT:
			return maxf(time_limit_s - fight_time, 0.0)
	return 0.0


func _physics_process(delta: float) -> void:
	_scan_t += delta
	if _scan_t >= SCAN_INTERVAL_S:
		_scan_t = 0.0
		_scan_dolls()
	if not _started:
		return
	match phase:
		Phase.COUNTDOWN:
			var n := int(ceil(_countdown_left))
			if n != _countdown_shown and n > 0:
				_countdown_shown = n
				announce.emit(str(n), ANNOUNCE_COLORS["countdown"], "countdown")
			_countdown_left -= delta
			if _countdown_left <= 0.0:
				_start_fight()
		Phase.FIGHT:
			fight_time += delta
			time_left.emit(time_left_s())
			_tick_respawns(delta)
			_tick_points()
			if play_state == "play" and fight_time >= time_limit_s:
				_finish("timeout")


# --- счёт ---

func score_of(d: Object) -> int:
	if d == null or not is_instance_valid(d):
		return 0
	return int(scores.get(int(d.get("player_index")), 0))


## Ведущий: больше точек; равно — кто раньше набрал; никто не брал — null.
func leader() -> Doll:
	var best: Doll = null
	for d in dolls():
		var dd := d as Doll
		if best == null or _ahead(dd, best):
			best = dd
	if best != null and score_of(best) <= 0:
		return null
	return best


func _ahead(a: Doll, b: Doll) -> bool:
	var sa := score_of(a)
	var sb := score_of(b)
	if sa != sb:
		return sa > sb
	var ta := float(last_take_t.get(a.player_index, INF))
	var tb := float(last_take_t.get(b.player_index, INF))
	if not is_equal_approx(ta, tb):
		return ta < tb
	return a.player_index < b.player_index


## Куклы по месту в гонке (первый — лидер).
func standings() -> Array:
	var all := dolls()
	all.sort_custom(func(a: Doll, b: Doll) -> bool: return _ahead(a, b))
	return all


## Кукла «я»: человек (external_input = false, меньший player_index), иначе focus_index, иначе null.
func me() -> Doll:
	var best: Doll = null
	for d in dolls():
		var dd := d as Doll
		if not dd.external_input and (best == null or dd.player_index < best.player_index):
			best = dd
	if best != null:
		return best
	if focus_index >= 0:
		for d in dolls():
			if (d as Doll).player_index == focus_index:
				return d
	return null


static func _is_human(d: Object) -> bool:
	return d != null and is_instance_valid(d) and d is Doll and not (d as Doll).external_input


# --- удары ---

## Удар телом или оружием (зовёт DollCombat): урон уже снят. С человеком — как в бою (Match.on_hit: тряска, стоп-кадр, надписи);
## боты между собой — только сигнал hit, Заряд за удар и тихий звук (иначе драка ботов на другом краю карты дёргала бы кадр).
func on_hit(victim: Doll, attacker: Node, damage: float, kind: String, position: Vector3, combo_n: int, double_blow: bool, weapon_id: String, speed: float) -> void:
	if _is_human(victim) or _is_human(attacker):
		super.on_hit(victim, attacker, damage, kind, position, combo_n, double_blow, weapon_id, speed)
		return
	hit.emit(victim, attacker, damage, kind, position)
	if victim == null or not is_instance_valid(victim) or damage <= 0.0 or kind == "environment":
		return
	Charge.apply_hit(make_hit_ctx(victim, attacker, damage, kind, position, combo_n, double_blow, weapon_id, speed))
	if feel_enabled:
		_play_at("hit_m" if damage >= 10.0 else "hit_l", -10.0 + minf(damage, 30.0) * 0.2, randf_range(0.95, 1.1), position)


## Удар о стену или пол без урона: эффекты (тряска, наезд камеры) — только у человека.
func _emit_env_slam(ctx: Dictionary) -> void:
	if _is_human(ctx.get("doll")):
		super._emit_env_slam(ctx)


func _play_at(layer: String, db: float, pitch: float, at: Vector3) -> void:
	if _sfx == null or not is_instance_valid(_sfx):
		_sfx = get_tree().get_first_node_in_group(SfxDirector.GROUP)
		if _sfx == null:
			return
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	var dx := at.x - (cam.global_position.x if cam != null else 0.0)
	if absf(dx) > 26.0:
		return
	var near := 1.0 - clampf(absf(dx) / 26.0, 0.0, 1.0)
	_sfx.call("play_layer", layer, db - 10.0 * (1.0 - near), pitch, SfxDirector.BUS_SFX, clampf(dx / 14.0, -1.0, 1.0))


# --- нокаут и возврат ---

func register(d: Doll) -> void:
	super.register(d)
	if not tally.has(d.player_index):
		tally[d.player_index] = {"kos": 0, "kos_taken": 0}


func _check_over() -> void:
	pass


func _on_doll_ko(attacker: Node, record: Dictionary, victim: Doll) -> void:
	if phase == Phase.OVER or play_state != "play":
		return
	var feel := feel_enabled
	var human := _is_human(victim) or _is_human(attacker)
	feel_enabled = feel and human
	super._on_doll_ko(attacker, record, victim)
	feel_enabled = feel
	(tally[victim.player_index] as Dictionary)["kos_taken"] = int(tally[victim.player_index]["kos_taken"]) + 1
	if attacker is Doll and is_instance_valid(attacker) and attacker != victim and tally.has((attacker as Doll).player_index):
		(tally[(attacker as Doll).player_index] as Dictionary)["kos"] = int(tally[(attacker as Doll).player_index]["kos"]) + 1
	_respawns.append([victim, respawn_s])
	respawn_queued.emit(victim, respawn_s)


## Секунды до возврата куклы (−1 — не ждёт).
func respawn_left(d: Doll) -> float:
	for e in _respawns:
		if e[0] == d:
			return float(e[1])
	return -1.0


## Где кукла player_index вернётся после KO (позиция корня куклы): у последней своей взятой точки, на RACE_RESPAWN_DROP_M ниже её
## центра (горит на этой метке точка — у ближайшей негорящей); не брала — на старте.
func respawn_point(pi: int) -> Vector3:
	if not last_mark.has(pi) or marks.is_empty():
		return starts[pi] if pi >= 0 and pi < starts.size() else start_centre()
	var m := int(last_mark[pi])
	var busy := lit_marks()
	var best := m
	if busy.has(m):
		var best_d := INF
		for i in marks.size():
			if busy.has(i):
				continue
			var dd := marks[i].distance_to(marks[m])
			if dd < best_d:
				best_d = dd
				best = i
	return marks[best] - Vector3(0.0, Tuning.RACE_RESPAWN_DROP_M, 0.0)


func _tick_respawns(delta: float) -> void:
	var i := 0
	while i < _respawns.size():
		var e: Array = _respawns[i]
		e[1] = float(e[1]) - delta
		if float(e[1]) > 0.0:
			i += 1
			continue
		_respawns.remove_at(i)
		var d: Variant = e[0]
		if is_instance_valid(d) and (d as Doll).is_inside_tree() and not (d as Doll).alive:
			var pi := (d as Doll).player_index
			_respawn_at[pi] = respawn_point(pi)
			var nd := respawn_doll(d as Doll)
			_respawn_at.erase(pi)
			nd.control_enabled = true
			nd.grace_until = maxf(nd.grace_until, Tuning.RACE_SPAWN_SHIELD_S)   # _time новой куклы ≈ 0
			hp_changed.emit(nd, nd.hp, nd.max_hp)
			doll_respawned.emit(nd)


# --- итоги ---

## Итоги: базовые (статистика, медали) + места по гонке (точки, кто раньше), счёт, победитель, время, журнал взятий.
func build_results(reason: String = "timeout") -> Dictionary:
	var r := super.build_results(reason)
	var order := standings()
	var ranks: Array = []
	for i in order.size():
		ranks.append(i)
	var winner: Doll = null
	for d in order:
		if (d as Doll).player_index == winner_index:
			winner = d
	r["places"] = order
	r["ranks"] = ranks
	r["winner"] = winner
	r["draw"] = winner == null
	var medals: Dictionary = r.get("medals", {})
	medals.erase("Winner")
	if winner != null:
		medals["Winner"] = winner
	r["medals"] = medals
	r["scores"] = scores.duplicate()
	r["tally"] = tally.duplicate(true)
	r["takes"] = takes.duplicate(true)
	r["race_time"] = fight_time
	r["winner_index"] = winner_index
	r["to_win"] = to_win
	return r
