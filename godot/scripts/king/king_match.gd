## Матч «Царь горы» (docs/plan-demo/KING.md; MODES_IDEAS.md Б10: «светящаяся зона переезжает каждые 30 с; очко в секунду тому, кто в
## ней один; все против всех, до 60»). Наследник Match: от него — регистрация кукол, DollCombat (удары с уроном, как в бою), KO, отсчёт,
## надписи. Своё:
##   • зона («гора»): круг радиуса KING_ZONE_R вокруг одной из точек Tuning.KING_ZONE_SPOTS (zone_i); раз в zone_period_s переезжает
##     на другую точку не ближе KING_ZONE_MIN_MOVE_M (zone_moved); за KING_ZONE_WARN_S до переезда следующая точка уже выбрана
##     (next_i, zone_warning: кольцо мигает, новая зона подсвечена призраком — KingZone);
##   • очки: каждый тик боя считается, чьи центры масс (Doll.centre_of_mass) в радиусе зоны (только живые) — occupants. Ровно один
##     (holder) — ему KING_POINT_PER_S × delta (×KING_STREAK_MULT с короной); двое и больше — никому (zone_state "contested"); никого —
##     никому ("free");
##   • корона (стрик): один и тот же holder KING_STREAK_S подряд — «ЦАРЬ!» (crowned, king_crowned), очки ×2, пока его не выбили (зона
##     спорная / пустая / переехала / KO) — king_lost;
##   • KO (удар, пропасть, голова) → возврат через respawn_s на случайной точке Tuning.KING_SPAWN вне зоны (respawn_queued →
##     doll_respawned); в нокауте очков нет (считаются только живые);
##   • конец: первый до score_to_win (reason "score") или лимит time_limit_s = KING_TIME_S (reason "timeout": больше очков; равно —
##     ничья). Sudden Death и «последний живой» базового Match выключены; эффекты удара (тряска, стоп-кадр) — только с человеком.
## play_state: idle | countdown | play | over. Журналы для проб: moves [{t, from, to, dist}], crowns [{t, pi}], ko_log [{t, victim,
## attacker}], visited (индекс точки → сколько раз зона там стояла).
class_name KingMatch
extends Match

signal zone_moved(from_i: int, to_i: int, position: Vector3)
signal zone_warning(next_i: int, position: Vector3)
signal score_changed(scores: Dictionary)
signal king_crowned(doll: Doll)
signal king_lost(doll: Doll)
signal respawn_queued(victim: Doll, seconds: float)
signal doll_respawned(doll: Doll)

const ZONE_COLOUR_FREE := Color(0.35, 0.9, 1.0)
const ZONE_COLOUR_CONTESTED := Color(1.0, 0.25, 0.2)
const ZONE_COLOUR_CROWN := Color(1.0, 0.85, 0.3)

@export var score_to_win: float = float(Tuning.KING_SCORE_TO_WIN)
@export var zone_period_s: float = Tuning.KING_ZONE_S
@export var respawn_s: float = Tuning.KING_RESPAWN_S
## Сид случайностей (первая точка зоны, переезды, точки возврата); 0 — каждый раз новый.
@export var rng_seed := 0

var play_state := "idle"
## player_index → очки (дробные: по delta тика; HUD показывает целые).
var scores: Dictionary = {}
var zone_i := -1
var zone_pos := Vector2.ZERO
## До переезда зоны, с.
var zone_left := 0.0
## Следующая точка (выбрана за KING_ZONE_WARN_S до переезда), −1 — ещё нет.
var next_i := -1
var occupants: Array = []       # живые куклы, чей ЦМ в зоне на этом тике
var holder: Doll = null         # единственный в зоне (null — пусто или спорно)
var sole_t := 0.0               # сколько подряд holder один в зоне, с
var crowned := false
var zone_state := "free"        # free | held | contested
var tally: Dictionary = {}      # player_index → {kos, kos_taken, crowns}
var moves: Array = []
var crowns: Array = []
var ko_log: Array = []
var visited: Dictionary = {}
var winner_index := -1
## Кукла «я» для HUD и камеры, когда людей нет (пробы): player_index или −1.
var focus_index := -1
var _respawns: Array = []        # [[Doll, осталось с]]
var _respawn_at: Dictionary = {} # player_index → точка возврата (только на время respawn_doll)
var _rng := RandomNumberGenerator.new()
var _shown: Dictionary = {}      # player_index → последнее целое очков (score_changed)
var _restart_pending := false
var _in_tick := false


func _ready() -> void:
	time_limit_s = Tuning.KING_TIME_S
	hard_timeout_s = 1.0e9      # Sudden Death не нужен: лимит решает по очкам
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	super._ready()
	crit_enabled = false        # крит-кино на 1.5 с в толпе из пятерых — лишнее


# --- куклы ---

func register(d: Doll) -> void:
	super.register(d)
	var c := colour_of(d.player_index)
	if c != Tuning.PLAYER_COLORS[clampi(d.player_index, 0, 3)]:
		d._recolor(d, Doll.SHIRT_MATERIAL, c)   # пятый и дальше: у куклы цветов четыре (PLAYER_COLORS)
	if not tally.has(d.player_index):
		tally[d.player_index] = {"kos": 0, "kos_taken": 0, "crowns": 0}
	if not scores.has(d.player_index):
		scores[d.player_index] = 0.0


## Точка появления: в начале — Tuning.KING_SPAWN по player_index; после KO — точка возврата (_respawn_at).
func spawn_point_for(d: Doll) -> Vector3:
	if _respawn_at.has(d.player_index):
		return _respawn_at[d.player_index]
	var pts: Array = Tuning.KING_SPAWN
	if d.player_index >= 0 and d.player_index < pts.size():
		var p: Vector2 = pts[d.player_index]
		return Vector3(p.x, p.y, 0.0)
	return super.spawn_point_for(d)


static func colour_of(i: int) -> Color:
	return Tuning.BOMB_COLORS[posmod(i, Tuning.BOMB_COLORS.size())]


static func doll_name(d: Object) -> String:
	if d == null or not is_instance_valid(d):
		return "—"
	return "P%d" % (int(d.get("player_index")) + 1)


## Кукла, которой принадлежит тело (деталь — ребёнок Doll; у сборок — глубже).
static func doll_of(body: Node) -> Doll:
	var n := body
	for _i in 4:
		if n == null:
			return null
		if n is Doll:
			return n
		n = n.get_parent()
	return null


static func _is_human(d: Object) -> bool:
	return d != null and is_instance_valid(d) and d is Doll and not (d as Doll).external_input


func score_of(d: Object) -> float:
	if d == null or not is_instance_valid(d):
		return 0.0
	return float(scores.get(int(d.get("player_index")), 0.0))


## Кукла «я»: человек (меньший player_index), иначе focus_index, иначе null.
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


# --- зона ---

func zone_centre() -> Vector3:
	return Vector3(zone_pos.x, zone_pos.y, 0.0)


func next_centre() -> Vector3:
	if next_i < 0:
		return zone_centre()
	var p: Vector2 = Tuning.KING_ZONE_SPOTS[next_i]
	return Vector3(p.x, p.y, 0.0)


## Скоро переезд: следующая точка уже выбрана (кольцо мигает).
func warning() -> bool:
	return next_i >= 0


func in_zone(p: Vector3) -> bool:
	return Vector2(p.x, p.y).distance_to(zone_pos) <= Tuning.KING_ZONE_R


## Следующая точка зоны: случайная из KING_ZONE_SPOTS не ближе KING_ZONE_MIN_MOVE_M к текущей (таких нет — самая дальняя).
func pick_next(from_i: int) -> int:
	var spots: Array = Tuning.KING_ZONE_SPOTS
	var from: Vector2 = spots[from_i] if from_i >= 0 and from_i < spots.size() else zone_pos
	var cand: Array = []
	var far_i := -1
	var far_d := -1.0
	for i in spots.size():
		if i == from_i:
			continue
		var dd := (spots[i] as Vector2).distance_to(from)
		if dd >= Tuning.KING_ZONE_MIN_MOVE_M:
			cand.append(i)
		if dd > far_d:
			far_d = dd
			far_i = i
	if cand.is_empty():
		return far_i
	return cand[_rng.randi() % cand.size()]


func _set_zone(i: int) -> void:
	var from := zone_i
	zone_i = i
	zone_pos = Tuning.KING_ZONE_SPOTS[i]
	zone_left = zone_period_s
	next_i = -1
	visited[i] = int(visited.get(i, 0)) + 1
	if from >= 0:
		moves.append({"t": snappedf(fight_time, 0.01), "from": from, "to": i,
			"dist": snappedf((Tuning.KING_ZONE_SPOTS[from] as Vector2).distance_to(zone_pos), 0.01)})
		zone_moved.emit(from, i, zone_centre())


func _tick_zone(delta: float) -> void:
	zone_left -= delta
	if next_i < 0 and zone_left <= Tuning.KING_ZONE_WARN_S:
		next_i = pick_next(zone_i)
		zone_warning.emit(next_i, next_centre())
	if zone_left <= 0.0:
		_set_zone(next_i if next_i >= 0 else pick_next(zone_i))
	# кто в зоне (ЦМ живой куклы в радиусе)
	occupants.clear()
	for d in alive_dolls():
		if in_zone((d as Doll).centre_of_mass()):
			occupants.append(d)
	var one: Doll = occupants[0] if occupants.size() == 1 else null
	if one != holder:
		_set_holder(one)
	zone_state = "held" if one != null else ("contested" if occupants.size() > 1 else "free")
	if one == null:
		return
	sole_t += delta
	if not crowned and sole_t >= Tuning.KING_STREAK_S:
		crowned = true
		crowns.append({"t": snappedf(fight_time, 0.01), "pi": one.player_index})
		(tally[one.player_index] as Dictionary)["crowns"] = int(tally[one.player_index]["crowns"]) + 1
		king_crowned.emit(one)
		announce.emit(tr("ЦАРЬ!"), ZONE_COLOUR_CROWN, "king")
	var gain := Tuning.KING_POINT_PER_S * delta * (Tuning.KING_STREAK_MULT if crowned else 1.0)
	scores[one.player_index] = float(scores.get(one.player_index, 0.0)) + gain
	if int(floor(float(scores[one.player_index]))) != int(_shown.get(one.player_index, -1)):
		_shown[one.player_index] = int(floor(float(scores[one.player_index])))
		score_changed.emit(scores.duplicate())
	if float(scores[one.player_index]) >= score_to_win:
		winner_index = one.player_index
		_finish("score")


func _set_holder(d: Doll) -> void:
	var was := holder
	var was_crowned := crowned
	holder = d
	sole_t = 0.0
	crowned = false
	if was_crowned and was != null and is_instance_valid(was):
		king_lost.emit(was)


# --- фазы ---

func begin() -> void:
	scores.clear()
	_shown.clear()
	moves.clear()
	crowns.clear()
	ko_log.clear()
	visited.clear()
	winner_index = -1
	_respawns.clear()
	_respawn_at.clear()
	for k in tally.keys():
		tally[k] = {"kos": 0, "kos_taken": 0, "crowns": 0}
	holder = null
	sole_t = 0.0
	crowned = false
	occupants.clear()
	zone_state = "free"
	zone_i = -1
	next_i = -1
	_set_zone(_rng.randi() % Tuning.KING_ZONE_SPOTS.size())
	play_state = "countdown"
	super.begin()
	for d in dolls():
		scores[(d as Doll).player_index] = 0.0
	score_changed.emit(scores.duplicate())


## R / «Заново»: куклы пересоздаются только в своём тике (как BombMatch: вызов внутри физического кадра до тика поля купола оставляет
## мембране вынутые из дерева детали — ошибки «!is_inside_tree()» в null_field.gd).
func restart() -> void:
	if not _in_tick:
		_restart_pending = true
		return
	_restart_pending = false
	_respawn_at.clear()
	_respawns.clear()
	super.restart()


func _start_fight() -> void:
	super._start_fight()
	play_state = "play"


func _finish(reason: String) -> void:
	if phase == Phase.OVER:
		return
	play_state = "over"
	_respawns.clear()
	if winner_index < 0:
		var order := standings()
		if order.size() >= 2 and absf(score_of(order[0]) - score_of(order[1])) < 1e-4:
			winner_index = -1
		elif not order.is_empty():
			winner_index = (order[0] as Doll).player_index
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
	if _restart_pending:
		_in_tick = true
		restart()
		_in_tick = false
		return
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
			if play_state == "play":
				_tick_zone(delta)
			if play_state == "play" and fight_time >= time_limit_s:
				_finish("timeout")


# --- удары ---

## Удар телом или оружием: с человеком — как в бою (тряска, стоп-кадр, надписи); боты между собой — только сигнал hit и Заряд
## (драка ботов на другом краю купола не дёргает кадр, как в гонке).
func on_hit(victim: Doll, attacker: Node, damage: float, kind: String, position: Vector3, combo_n: int, double_blow: bool, weapon_id: String, speed: float) -> void:
	if _is_human(victim) or _is_human(attacker):
		super.on_hit(victim, attacker, damage, kind, position, combo_n, double_blow, weapon_id, speed)
		return
	hit.emit(victim, attacker, damage, kind, position)
	if victim == null or not is_instance_valid(victim) or damage <= 0.0 or kind == "environment":
		return
	Charge.apply_hit(make_hit_ctx(victim, attacker, damage, kind, position, combo_n, double_blow, weapon_id, speed))


func _emit_env_slam(ctx: Dictionary) -> void:
	if _is_human(ctx.get("doll")):
		super._emit_env_slam(ctx)


# --- нокаут и возврат ---

func _check_over() -> void:
	pass   # конец — очки или время (_tick_zone / _physics_process)


func _on_doll_ko(attacker: Node, record: Dictionary, victim: Doll) -> void:
	if phase == Phase.OVER or play_state != "play":
		return
	var feel := feel_enabled
	feel_enabled = feel and (_is_human(victim) or _is_human(attacker))
	super._on_doll_ko(attacker, record, victim)
	feel_enabled = feel
	(tally[victim.player_index] as Dictionary)["kos_taken"] = int(tally[victim.player_index]["kos_taken"]) + 1
	var att_i := -1
	if attacker is Doll and is_instance_valid(attacker) and attacker != victim and tally.has((attacker as Doll).player_index):
		att_i = (attacker as Doll).player_index
		(tally[att_i] as Dictionary)["kos"] = int(tally[att_i]["kos"]) + 1
	ko_log.append({"t": snappedf(fight_time, 0.01), "victim": victim.player_index, "attacker": att_i})
	if victim == holder:
		_set_holder(null)
	_respawns.append([victim, respawn_s])
	respawn_queued.emit(victim, respawn_s)


## Секунды до возврата куклы (−1 — не ждёт).
func respawn_left(d: Doll) -> float:
	for e in _respawns:
		if e[0] == d:
			return float(e[1])
	return -1.0


## Точка возврата: случайная из KING_SPAWN не ближе KING_ZONE_R + KING_SPAWN_CLEAR_M к центру зоны (и к следующей, если она уже
## выбрана); подходящих нет — самая дальняя от зоны.
func respawn_point() -> Vector3:
	var pts: Array = Tuning.KING_SPAWN
	var clear := Tuning.KING_ZONE_R + Tuning.KING_SPAWN_CLEAR_M
	var nxt := Vector2(next_centre().x, next_centre().y)
	var cand: Array = []
	var far: Vector2 = pts[0]
	var far_d := -1.0
	for p in pts:
		var v := p as Vector2
		var dd := v.distance_to(zone_pos)
		if dd > clear and (next_i < 0 or v.distance_to(nxt) > clear):
			cand.append(v)
		if dd > far_d:
			far_d = dd
			far = v
	var c: Vector2 = cand[_rng.randi() % cand.size()] if not cand.is_empty() else far
	return Vector3(c.x, c.y, 0.0)


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
			_respawn_at[pi] = respawn_point()
			var nd := respawn_doll(d as Doll)
			_respawn_at.erase(pi)
			nd.control_enabled = true
			hp_changed.emit(nd, nd.hp, nd.max_hp)
			doll_respawned.emit(nd)


# --- места и итоги ---

func _ahead(a: Doll, b: Doll) -> bool:
	var sa := score_of(a)
	var sb := score_of(b)
	if absf(sa - sb) > 1e-4:
		return sa > sb
	return a.player_index < b.player_index


## Куклы по месту (первый — лидер).
func standings() -> Array:
	var all := dolls()
	all.sort_custom(func(a: Doll, b: Doll) -> bool: return _ahead(a, b))
	return all


## Лидер по очкам (никто не набрал — null).
func leader() -> Doll:
	var order := standings()
	if order.is_empty() or score_of(order[0]) <= 0.0:
		return null
	return order[0]


## Итоги: базовые (статистика, медали) + места по очкам (равные — делят место), победитель (winner_index; при равенстве — ничья),
## очки, сводка (нокауты, выбывания, короны), журналы.
func build_results(reason: String = "timeout") -> Dictionary:
	var r := super.build_results(reason)
	var order := standings()
	var ranks: Array = []
	for i in order.size():
		var tied := i > 0 and absf(score_of(order[i]) - score_of(order[i - 1])) < 1e-4
		ranks.append(ranks[i - 1] if tied else i)
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
	medals.erase("Survivor")
	if winner != null:
		medals["Winner"] = winner
	r["medals"] = medals
	var sc := {}
	for k in scores:
		sc[k] = int(floor(float(scores[k])))
	r["scores"] = sc
	r["tally"] = tally.duplicate(true)
	r["moves"] = moves.duplicate(true)
	r["crowns"] = crowns.duplicate(true)
	r["ko_log"] = ko_log.duplicate(true)
	r["winner_index"] = winner_index
	r["score_to_win"] = int(score_to_win)
	r["match_time"] = fight_time
	return r
