## Матч «Гонка: трасса» (docs/plan-demo/RACE_TRACK.md; автор 06.10: «в гонке мы можем сделать длинную сложную карту с разными сложностями
## на ней?» → «делаем»). Наследник Match: от него — регистрация кукол (DollCombat), удары с уроном, KO, отсчёт. Своё:
##   • прогресс каждого гонщика — проекция его ЦМ на линию трассы (TrackRoute карты, метры от старта; обе ветки развилки — один отрезок
##     прогресса), отсюда места «кто впереди», полоска трассы в HUD и контрольные точки;
##   • контрольная точка (TrackCheckpoint, в начале каждого участка) — взята, когда прогресс до неё дошёл; KO, яма (drop «fall»),
##     «застрял» (прогресс вырос меньше Tuning.TRACK_STUCK_M за TRACK_STUCK_S) или Q (drop «reset») → через TRACK_RESPAWN_S гонщик у своей
##     последней точки (место по player_index), первые TRACK_SPAWN_SHIELD_S урон не проходит;
##   • кольца (TrackRing): ЦМ ближе TRACK_RING_R — +TRACK_RING_CHARGE Заряда, раз на гонщика (после возврата на точку — кольца за ней снова);
##   • финиш: ЦМ за линией финиша карты (и прогресс у конца) — место по порядку; первый — победитель. После первого финиша остальным
##     TRACK_FINISH_WAIT_S, потом итоги; все доехали — сразу; лимит TRACK_TIME_LIMIT_S. Кто не доехал — места по прогрессу;
##   • удары — как в «Гонке: 10 точек» (RaceMatch): эффекты удара (тряска, стоп-кадр, надписи) только если в ударе человек, крит-кино
##     выключено; Sudden Death и «последний живой» выключены.
## Сигналы для HUD, площадки и проб: checkpoint_reached, ring_taken, racer_finished, respawn_queued, doll_respawned + унаследованные.
class_name TrackMatch
extends Match

signal checkpoint_reached(doll: Doll, index: int)
signal ring_taken(doll: Doll, ring: Node3D)
signal racer_finished(doll: Doll, place: int, seconds: float)
signal respawn_queued(victim: Doll, seconds: float, why: String)
signal doll_respawned(doll: Doll)

## Окно поиска на линии вокруг прошлого прогресса (м): гонщик не «прыгает» на соседний коридор за стеной.
const PROJECT_WINDOW_M := 40.0
const FINISH_PROG_GAP_M := 25.0
const BRANCH_MARK_FRAC := 0.2

@export var respawn_s: float = Tuning.TRACK_RESPAWN_S
@export var finish_wait_s: float = Tuning.TRACK_FINISH_WAIT_S

var arena_node: TrackArena
var route: TrackRoute
## Контрольные точки (TrackCheckpoint) и их прогресс на линии.
var cps: Array = []
var cp_prog: Array = []
var rings: Array = []
## player_index → состояние гонщика: prog, seg, cp, finished, finish_t, place, rings {ring → true}, stuck_anchor, stuck_t, branches
## {fork → kind}, kos, kos_taken, falls, stucks, resets, last_cp_t.
var racers: Dictionary = {}
## idle | countdown | play | over
var play_state := "idle"
var finish_order: Array = []
var first_finish_t := -1.0
var winner_index := -1
var end_reason := ""
## Кукла «я» для HUD и камеры, когда людей нет (пробы: за P1 играет бот): player_index или −1.
var focus_index := -1
## Журнал для проб (journal): [{t, pi, what, …}] — контрольные точки, возвраты, финиши, кольца.
var journal: Array = []
var _respawns: Array = []         # [[Doll, осталось с, why]]
var _respawn_at: Dictionary = {}  # player_index → корень куклы при возврате
var _why: Dictionary = {}         # player_index → причина ближайшего KO (fall | stuck | reset)
var _sfx: Node = null


func _ready() -> void:
	time_limit_s = Tuning.TRACK_TIME_LIMIT_S
	hard_timeout_s = Tuning.TRACK_TIME_LIMIT_S
	super._ready()
	crit_enabled = false


## Карта трассы: линия, контрольные точки, кольца (зовёт площадка до старта).
func bind_arena(a: TrackArena) -> void:
	arena_node = a


func _ensure_route() -> void:
	if route != null and route.ready():
		return
	if arena_node == null:
		arena_node = _arena() as TrackArena
	if arena_node == null or not arena_node.is_inside_tree():
		return
	route = arena_node.route()
	cps = arena_node.checkpoints()
	rings = arena_node.rings()
	cp_prog.clear()
	for i in cps.size():
		if i == 0:
			cp_prog.append(0.0)
			continue
		var c := cps[i] as TrackCheckpoint
		var gp := c.global_position
		var pr := route.project(Vector2(gp.x, gp.y + 2.0))
		cp_prog.append(float(pr.get("prog", 0.0)))


func total_m() -> float:
	return route.total if route != null else 1.0


# --- фазы ---

func begin() -> void:
	_ensure_route()
	finish_order.clear()
	first_finish_t = -1.0
	winner_index = -1
	end_reason = ""
	journal.clear()
	_respawns.clear()
	_respawn_at.clear()
	_why.clear()
	for k in racers.keys():
		racers[k] = _fresh()
	play_state = "countdown"
	super.begin()


static func _fresh() -> Dictionary:
	return {"prog": 0.0, "seg": -1, "cp": 0, "finished": false, "finish_t": -1.0, "place": 0, "rings": {}, "stuck_anchor": 0.0,
		"stuck_t": 0.0, "branches": {}, "kos": 0, "kos_taken": 0, "falls": 0, "stucks": 0, "resets": 0, "last_cp_t": 0.0}


func restart() -> void:
	_respawn_at.clear()
	_respawns.clear()
	super.restart()


func _start_fight() -> void:
	super._start_fight()
	play_state = "play"
	for d in dolls():
		var st := state_of(d as Doll)
		_project(d as Doll, st, -1.0)
		st["stuck_anchor"] = float(st["prog"])


func _finish(reason: String) -> void:
	if phase == Phase.OVER:
		return
	play_state = "over"
	end_reason = reason
	_respawns.clear()
	if winner_index < 0 and not finish_order.is_empty():
		winner_index = int(finish_order[0])
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
			_tick_racers(delta)
			if play_state != "play":
				return
			if finish_order.size() >= dolls().size() and not dolls().is_empty():
				_finish("all")
			elif first_finish_t >= 0.0 and fight_time - first_finish_t >= finish_wait_s:
				_finish("wait")
			elif fight_time >= time_limit_s:
				_finish("timeout")


# --- гонщики ---

func register(d: Doll) -> void:
	super.register(d)
	if not racers.has(d.player_index):
		racers[d.player_index] = _fresh()


func state_of(d: Doll) -> Dictionary:
	if d == null or not is_instance_valid(d):
		return {}
	if not racers.has(d.player_index):
		racers[d.player_index] = _fresh()
	return racers[d.player_index]


func progress_of(d: Doll) -> float:
	return float(state_of(d).get("prog", 0.0))


## Доля пройденной трассы 0..1 (финишировал — 1).
func fraction_of(d: Doll) -> float:
	var st := state_of(d)
	if bool(st.get("finished", false)):
		return 1.0
	return clampf(float(st.get("prog", 0.0)) / maxf(total_m(), 1.0), 0.0, 1.0)


## Номер участка (1..6), где гонщик сейчас (по x ЦМ).
func section_of(d: Doll) -> int:
	if arena_node == null or d == null or not is_instance_valid(d):
		return 1
	return arena_node.section_at(d.centre_of_mass().x)


func _project(d: Doll, st: Dictionary, window: float) -> void:
	if route == null or not route.ready():
		return
	var c := d.centre_of_mass()
	var pr := route.project(Vector2(c.x, c.y), float(st["prog"]), window, int(st["seg"]))
	if pr.is_empty():
		return
	st["seg"] = int(pr["seg"])
	st["prog"] = float(pr["prog"])
	var sg := route.segs[int(pr["seg"])]
	var frac := float(pr["s"]) / maxf(sg.length, 0.01)
	if sg.kind != "main" and frac > BRANCH_MARK_FRAC and frac < 1.0 - BRANCH_MARK_FRAC:
		st["branches"][sg.fork] = sg.kind   # ветка засчитана, когда гонщик в её середине (у концов ветки сходятся)


func _tick_racers(delta: float) -> void:
	_ensure_route()
	if route == null or not route.ready():
		return
	var fx := arena_node.finish_x() if arena_node != null else INF
	for d in dolls():
		var dd := d as Doll
		var st := state_of(dd)
		if not dd.alive or not dd.is_inside_tree() or bool(st["finished"]):
			continue
		_project(dd, st, PROJECT_WINDOW_M)
		var prog := float(st["prog"])
		# контрольные точки
		while int(st["cp"]) + 1 < cp_prog.size() and prog >= float(cp_prog[int(st["cp"]) + 1]) - 0.5:
			st["cp"] = int(st["cp"]) + 1
			st["last_cp_t"] = fight_time
			journal.append({"t": snappedf(fight_time, 0.01), "pi": dd.player_index, "what": "cp", "cp": int(st["cp"])})
			checkpoint_reached.emit(dd, int(st["cp"]))
			if _is_human(dd) and int(st["cp"]) < cps.size():
				(cps[int(st["cp"])] as TrackCheckpoint).flash()
				_play_ui("equip", -2.0, 1.25)
		# кольца
		var c := dd.centre_of_mass()
		var r2 := Tuning.TRACK_RING_R * Tuning.TRACK_RING_R
		for r in rings:
			var rn := r as Node3D
			if (st["rings"] as Dictionary).has(rn) or Vector2(c.x - rn.global_position.x, c.y - rn.global_position.y).length_squared() > r2:
				continue
			st["rings"][rn] = true
			var got := dd.add_charge(Tuning.TRACK_RING_CHARGE)
			if rn.has_method("flash"):
				rn.call("flash", _colour(dd.player_index))
			journal.append({"t": snappedf(fight_time, 0.01), "pi": dd.player_index, "what": "ring", "ring": String(rn.name), "charge": snappedf(got, 0.1)})
			ring_taken.emit(dd, rn)
			if _is_human(dd):
				_play_ui("combo", -3.0, 1.4)
		# финиш
		if c.x >= fx and prog >= total_m() - FINISH_PROG_GAP_M:
			_cross_finish(dd, st)
			continue
		# застрял
		if prog >= float(st["stuck_anchor"]) + Tuning.TRACK_STUCK_M:
			st["stuck_anchor"] = prog
			st["stuck_t"] = 0.0
		elif dd.control_enabled:
			st["stuck_t"] = float(st["stuck_t"]) + delta
			if float(st["stuck_t"]) >= Tuning.TRACK_STUCK_S:
				drop(dd, "stuck")


func _cross_finish(d: Doll, st: Dictionary) -> void:
	st["finished"] = true
	st["finish_t"] = fight_time
	st["prog"] = total_m()
	finish_order.append(d.player_index)
	st["place"] = finish_order.size()
	if first_finish_t < 0.0:
		first_finish_t = fight_time
		winner_index = d.player_index
	d.grace_until = INF   # доехал — его больше не бьют
	journal.append({"t": snappedf(fight_time, 0.01), "pi": d.player_index, "what": "finish", "place": int(st["place"])})
	racer_finished.emit(d, int(st["place"]), fight_time)
	if arena_node != null:
		var f := arena_node.get_node_or_null("Finish")
		if f != null and f.has_method("flash"):
			f.call("flash")
	if _is_human(d):
		_play_ui("bell", 0.0, 1.0)


## Выбить гонщика с возвратом к его контрольной точке: why = fall (яма, сетка) | stuck (застрял) | reset (Q).
func drop(d: Doll, why: String) -> void:
	if d == null or not is_instance_valid(d) or not d.alive or play_state != "play" or bool(state_of(d).get("finished", false)):
		return
	_why[d.player_index] = why
	d.knock_out(null, {"kind": why})


## Ведущий сейчас (первое место) или null.
func leader() -> Doll:
	var s := standings()
	return s[0] if not s.is_empty() else null


## Куклы по месту: доехавшие — по порядку финиша; остальные — по прогрессу (равно — меньший player_index).
func standings() -> Array:
	var all := dolls()
	all.sort_custom(func(a: Doll, b: Doll) -> bool: return _ahead(a, b))
	return all


func _ahead(a: Doll, b: Doll) -> bool:
	var sa := state_of(a)
	var sb := state_of(b)
	var fa := bool(sa.get("finished", false))
	var fb := bool(sb.get("finished", false))
	if fa != fb:
		return fa
	if fa:
		return int(sa["place"]) < int(sb["place"])
	var pa := float(sa.get("prog", 0.0))
	var pb := float(sb.get("prog", 0.0))
	if not is_equal_approx(pa, pb):
		return pa > pb
	return a.player_index < b.player_index


## Место гонщика (1..N).
func place_of(d: Doll) -> int:
	return standings().find(d) + 1


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


static func _colour(pi: int) -> Color:
	return Tuning.PLAYER_COLORS[pi % Tuning.PLAYER_COLORS.size()] if pi >= 0 else Color.WHITE


# --- удары (как RaceMatch: эффекты — только если в ударе человек) ---

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


func _emit_env_slam(ctx: Dictionary) -> void:
	if _is_human(ctx.get("doll")):
		super._emit_env_slam(ctx)


func _sfx_node() -> Node:
	if _sfx == null or not is_instance_valid(_sfx):
		_sfx = get_tree().get_first_node_in_group(SfxDirector.GROUP)
	return _sfx


func _play_ui(layer: String, db: float, pitch: float) -> void:
	if not feel_enabled or _sfx_node() == null:
		return
	_sfx.call("play_layer", layer, db, pitch, SfxDirector.BUS_UI, 0.0)


func _play_at(layer: String, db: float, pitch: float, at: Vector3) -> void:
	if _sfx_node() == null:
		return
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	var dx := at.x - (cam.global_position.x if cam != null else 0.0)
	if absf(dx) > 26.0:
		return
	var near := 1.0 - clampf(absf(dx) / 26.0, 0.0, 1.0)
	_sfx.call("play_layer", layer, db - 10.0 * (1.0 - near), pitch, SfxDirector.BUS_SFX, clampf(dx / 14.0, -1.0, 1.0))


# --- нокаут и возврат ---

func _check_over() -> void:
	pass


func _on_doll_ko(attacker: Node, record: Dictionary, victim: Doll) -> void:
	if phase == Phase.OVER or play_state != "play":
		return
	var why := String(_why.get(victim.player_index, "ko"))
	_why.erase(victim.player_index)
	var feel := feel_enabled
	feel_enabled = feel and why == "ko" and (_is_human(victim) or _is_human(attacker))
	super._on_doll_ko(attacker, record, victim)
	feel_enabled = feel
	var st := state_of(victim)
	match why:
		"fall":
			st["falls"] = int(st["falls"]) + 1
		"stuck":
			st["stucks"] = int(st["stucks"]) + 1
		"reset":
			st["resets"] = int(st["resets"]) + 1
		_:
			st["kos_taken"] = int(st["kos_taken"]) + 1
			if is_instance_valid(attacker) and attacker is Doll and attacker != victim:
				var sa := state_of(attacker as Doll)
				sa["kos"] = int(sa["kos"]) + 1
	journal.append({"t": snappedf(fight_time, 0.01), "pi": victim.player_index, "what": why, "cp": int(st["cp"]),
		"at": Vector2(victim.centre_of_mass().x, victim.centre_of_mass().y).snapped(Vector2(0.1, 0.1))})
	_respawns.append([victim, respawn_s, why])
	respawn_queued.emit(victim, respawn_s, why)


## Секунды до возврата куклы (−1 — не ждёт).
func respawn_left(d: Doll) -> float:
	for e in _respawns:
		if e[0] == d:
			return float(e[1])
	return -1.0


## Почему кукла ждёт возврата (ko | fall | stuck | reset) или "".
func respawn_why(d: Doll) -> String:
	for e in _respawns:
		if e[0] == d:
			return String(e[2])
	return ""


## Где гонщик вернётся (корень куклы): место у его последней контрольной точки; старт — на своей стартовой точке.
func respawn_point(pi: int) -> Vector3:
	var st: Dictionary = racers.get(pi, {})
	var ci := int(st.get("cp", 0))
	if ci <= 0 or ci >= cps.size():
		var a := _arena()
		if a != null and a.has_method("spawn_points"):
			var pts: Array = a.call("spawn_points")
			if pi >= 0 and pi < pts.size():
				return pts[pi]
		return Vector3.ZERO
	return (cps[ci] as TrackCheckpoint).spawn_for(pi)


func spawn_point_for(d: Doll) -> Vector3:
	if _respawn_at.has(d.player_index):
		return _respawn_at[d.player_index]
	return super.spawn_point_for(d)


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
			nd.grace_until = maxf(nd.grace_until, Tuning.TRACK_SPAWN_SHIELD_S)   # _time новой куклы ≈ 0
			var st := state_of(nd)
			var ci := int(st["cp"])
			st["prog"] = float(cp_prog[ci]) if ci < cp_prog.size() else 0.0
			st["seg"] = -1
			st["stuck_anchor"] = float(st["prog"])
			st["stuck_t"] = 0.0
			var cx := (cps[ci] as Node3D).global_position.x if ci < cps.size() and ci > 0 else -INF
			for r in (st["rings"] as Dictionary).keys():
				if not is_instance_valid(r) or (r as Node3D).global_position.x >= cx:
					(st["rings"] as Dictionary).erase(r)
			hp_changed.emit(nd, nd.hp, nd.max_hp)
			journal.append({"t": snappedf(fight_time, 0.01), "pi": pi, "what": "respawn", "cp": ci,
				"at": Vector2(nd.global_position.x, nd.global_position.y).snapped(Vector2(0.01, 0.01))})
			doll_respawned.emit(nd)


# --- итоги ---

## Итоги: базовые + места по гонке, время финиша и прогресс каждого, счётчики (KO, ямы, застревания, Q), причина конца.
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
	var per := {}
	for d in order:
		var st := state_of(d as Doll)
		per[(d as Doll).player_index] = {"finished": bool(st["finished"]), "finish_t": float(st["finish_t"]), "place": order.find(d) + 1,
			"prog": float(st["prog"]), "fraction": fraction_of(d as Doll), "kos": int(st["kos"]), "kos_taken": int(st["kos_taken"]),
			"falls": int(st["falls"]), "stucks": int(st["stucks"]), "resets": int(st["resets"]), "branches": (st["branches"] as Dictionary).duplicate()}
	r["racers"] = per
	r["finish_order"] = finish_order.duplicate()
	r["race_time"] = fight_time
	r["winner_index"] = winner_index
	r["winner_time"] = first_finish_t
	r["total_m"] = total_m()
	r["end_reason"] = reason
	return r
