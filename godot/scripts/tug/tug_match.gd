## Матч «Перетягивание каната» 2 на 2 (docs/plan-demo/TUG.md, MODES_IDEAS.md A4). Наследник Match: от него — регистрация кукол,
## DollCombat (удары, урон обычный), эффекты, отсчёт, HUD-сигналы. Своё:
##   • команды: player_index % 2 — 0 синие (слева, тянут к левой стене), 1 красные (справа); Doll.team = "tug_<команда>"; свои бьют
##     друг друга слабее (Tuning.TEAM_DAMAGE_MULT);
##   • канат TugRope (rope_path): звено своей половины хватает рука ArmAssist (meta grab_team); держащий звено и тянущий «от центра»
##     (ввод x к своей стене) получает тягу × TUG_PULL_MULT (Doll.thrust_mult);
##   • очко: метка середины каната за чертой (|x| ≥ TUG_LINE_M) на стороне команды TUG_HOLD_S подряд → счёт команде (point_scored),
##     пауза TUG_POINT_PAUSE_S, куклы и канат заново, отсчёт TUG_RESET_COUNTDOWN_S; до score_to_win (TUG_SCORE_TO_WIN) или TUG_TIME_S —
##     побеждает ведущий, равный счёт — ничья;
##   • KO матч не кончает: кукла возвращается у своей стены через TUG_RESPAWN_S (как в спорт-зале), крит-кино выключено.
## play_state: idle | countdown | play | point | over. Журналы для проб: points [{t, team, mark_x, score}], hold_s {player_index: с
## держания каната}, max_mark_abs. Сигналы: score_changed(score), point_scored(team), countdown_to_reset + унаследованные.
class_name TugMatch
extends Match

signal score_changed(score: Array)
signal point_scored(team: int)

const POINT_COLOUR := Color(1.0, 0.92, 0.35)
const KO_SLOWMO_S := 0.45
const TEAM_PREFIX := "tug_"

@export var rope_path: NodePath
@export var score_to_win: int = Tuning.TUG_SCORE_TO_WIN
@export var time_s: float = Tuning.TUG_TIME_S
## Пробы: false — метка за чертой очков не даёт (проверка каната под рывком).
var scoring := true
## Секунд с начала текущего розыгрыша (после отсчёта).
var round_time := 0.0

var rope: TugRope
var score := [0, 0]
var play_state := "idle"
var points: Array = []
var hold_s: Dictionary = {}        # player_index → секунд с канатом в руке
var max_mark_abs := 0.0
## Сторона, на которой метка сейчас за чертой (−1 — в середине), и сколько подряд.
var over_side := -1
var over_t := 0.0
var _point_t := 0.0
var _first_fight := true
var _respawns: Array = []          # [[Doll, осталось с]]
var _banked: Dictionary = {}       # player_index → статистика прошлых жизней


func _ready() -> void:
	time_limit_s = time_s
	hard_timeout_s = time_s
	super._ready()
	crit_enabled = false


func _late_ready() -> void:
	rope = get_node_or_null(rope_path) as TugRope if rope_path != NodePath() else null
	if rope == null:
		rope = get_tree().get_first_node_in_group("tug_rope") as TugRope
	super._late_ready()


# --- команды ---

static func team_of(d: Object) -> int:
	if d == null or not is_instance_valid(d):
		return -1
	var pi: Variant = d.get("player_index")
	return (int(pi) % 2) if pi != null else -1


static func team_name(team: int) -> String:
	return TranslationServer.translate("СИНИЕ") if team == 0 else TranslationServer.translate("КРАСНЫЕ")


static func colour_of(team: int) -> Color:
	return Tuning.TUG_COLORS[clampi(team, 0, 1)]


static func doll_name(d: Object) -> String:
	if d == null or not is_instance_valid(d):
		return "—"
	return "P%d" % (int(d.get("player_index")) + 1)


## Направление «к своей стене» по x: синие — влево.
static func home_dir(team: int) -> float:
	return -1.0 if team == 0 else 1.0


func register(d: Doll) -> void:
	var fresh := not _order.has(d)
	super.register(d)
	if not fresh:
		return
	d.team = TEAM_PREFIX + str(team_of(d))
	if d.is_node_ready():
		_dress(d)
	else:
		d.ready.connect(_dress.bind(d), CONNECT_ONE_SHOT)
	if not hold_s.has(d.player_index):
		hold_s[d.player_index] = 0.0


## Рубашка — цвет команды (P3 / P4 — синий / красный, а не зелёный / жёлтый).
func _dress(d: Doll) -> void:
	if is_instance_valid(d):
		d._recolor(d, Doll.SHIRT_MATERIAL, colour_of(team_of(d)))


func spawn_point_for(d: Doll) -> Vector3:
	var pts: Array = Tuning.TUG_SPAWN
	if d.player_index >= 0 and d.player_index < pts.size():
		var p: Vector2 = pts[d.player_index]
		return Vector3(p.x, p.y, 0.0)
	return super.spawn_point_for(d)


## Звено каната в руке куклы (ArmAssist.held) или null.
func held_link(d: Doll) -> RigidBody3D:
	if d == null or not is_instance_valid(d) or rope == null:
		return null
	for c in d.get_children():
		if c is ArmAssist and (c as ArmAssist).is_holding() and rope.is_link((c as ArmAssist).held):
			return (c as ArmAssist).held
	return null


func is_holding(d: Doll) -> bool:
	return held_link(d) != null


func team_dolls(team: int, alive_only := false) -> Array:
	var out: Array = []
	for d in dolls():
		if team_of(d) == team and (not alive_only or (d as Doll).alive):
			out.append(d)
	return out


func mark_x() -> float:
	return rope.mark_x() if rope != null else 0.0


# --- фазы ---

func begin() -> void:
	score = [0, 0]
	points.clear()
	hold_s.clear()
	for d in dolls():
		hold_s[(d as Doll).player_index] = 0.0
	max_mark_abs = 0.0
	over_side = -1
	over_t = 0.0
	_first_fight = true
	_respawns.clear()
	_banked.clear()
	if rope != null:
		rope.reset()
	play_state = "countdown"
	super.begin()
	score_changed.emit(score.duplicate())
	_show_score()


func restart() -> void:
	if rope != null:
		rope.reset()
	super.restart()


func _finish(reason: String) -> void:
	play_state = "over"
	super._finish(reason)


## СТАЗИС: только в розыгрыше.
func stasis_allowed() -> bool:
	return play_state == "play" and super.stasis_allowed()


func _start_fight() -> void:
	for d in dolls():
		var dd := d as Doll
		if _first_fight:
			dd.reset_for_match()
		dd.control_enabled = true
		var c := combat_of(dd)
		if c != null:
			c.reset()
	if _first_fight:
		fight_time = 0.0
	var first := _first_fight
	_first_fight = false
	over_side = -1
	over_t = 0.0
	_set_phase(Phase.FIGHT)
	for d in dolls():
		hp_changed.emit(d, (d as Doll).hp, (d as Doll).max_hp)
	play_state = "play"
	round_time = 0.0
	announce.emit(tr("ТЯНИ!"), ANNOUNCE_COLORS["fight"], "fight" if first else "countdown")


## Расстановка после очка: куклы заново у своих стен, канат по центру, короткий отсчёт.
func _reset_round() -> void:
	_respawns.clear()
	for d in dolls():
		_bank_stats(d as Doll)
		respawn_doll(d)
	for d in dolls():
		(d as Doll).control_enabled = false
		(d as Doll).thrust_mult = 1.0
	if rope != null:
		rope.reset()
	play_state = "countdown"
	_set_phase(Phase.COUNTDOWN)
	_countdown_left = Tuning.TUG_RESET_COUNTDOWN_S
	_countdown_shown = -1
	for d in dolls():
		hp_changed.emit(d, (d as Doll).hp, (d as Doll).max_hp)
	if _countdown_left <= 0.0:
		_start_fight()


func _physics_process(delta: float) -> void:
	_scan_t += delta
	if _scan_t >= SCAN_INTERVAL_S:
		_scan_t = 0.0
		_scan_dolls()
	if not _started:
		return
	_tick_respawns(delta)
	match phase:
		Phase.COUNTDOWN:
			var n := int(ceil(_countdown_left))
			if n != _countdown_shown and n > 0:
				_countdown_shown = n
				announce.emit(str(n), ANNOUNCE_COLORS["countdown"], "countdown")
			_countdown_left -= delta
			if _countdown_left <= 0.0:
				_start_fight()
		Phase.FIGHT, Phase.SUDDEN_DEATH:
			if play_state == "play":
				fight_time += delta
				round_time += delta
				time_left.emit(time_left_s())
				_tick_pull(delta)
				_tick_mark(delta)
				if play_state == "play" and fight_time >= time_limit_s:
					_finish("timeout")
			elif play_state == "point":
				_point_t -= delta
				if _point_t <= 0.0:
					_after_point()


func knockback_mult() -> float:
	return 1.0


func stability_mult() -> float:
	return 1.0


# --- тяга и метка ---

## Держащий звено и тянущий от центра (ввод x одного знака с x куклы) — тяга × TUG_PULL_MULT; остальным 1.
func _tick_pull(delta: float) -> void:
	for d in dolls():
		var dd := d as Doll
		if not dd.alive:
			dd.thrust_mult = 1.0
			continue
		var link := held_link(dd)
		if link == null:
			dd.thrust_mult = 1.0
			continue
		hold_s[dd.player_index] = float(hold_s.get(dd.player_index, 0.0)) + delta
		var away := dd.input_vec.x * home_dir(team_of(dd)) > 0.2
		dd.thrust_mult = Tuning.TUG_PULL_MULT if away else 1.0


func _tick_mark(delta: float) -> void:
	if rope == null:
		return
	var mx := rope.mark_x()
	max_mark_abs = maxf(max_mark_abs, absf(mx))
	if not scoring:
		return
	var side := -1
	if mx <= -Tuning.TUG_LINE_M:
		side = 0
	elif mx >= Tuning.TUG_LINE_M:
		side = 1
	if side != over_side:
		over_side = side
		over_t = 0.0
	if side < 0:
		return
	over_t += delta
	if over_t >= Tuning.TUG_HOLD_S:
		_on_point(side)


func _on_point(team: int) -> void:
	score[team] = int(score[team]) + 1
	points.append({"t": snappedf(fight_time, 0.01), "team": team, "mark_x": snappedf(mark_x(), 0.01), "score": score.duplicate()})
	play_state = "point"
	_point_t = Tuning.TUG_POINT_PAUSE_S
	over_side = -1
	over_t = 0.0
	for d in dolls():
		(d as Doll).thrust_mult = 1.0
	score_changed.emit(score.duplicate())
	point_scored.emit(team)
	announce.emit(tr("ОЧКО: %s") % team_name(team), colour_of(team).lightened(0.35), "point")
	_show_score()
	if feel_enabled and rope != null:
		_camera_fx(30.0, rope.mark_pos())
		if FxPreset.time_fx():
			_time_effect(Tuning.SPORT_GOAL_SLOWMO, Tuning.SPORT_GOAL_SLOWMO_S)


func _after_point() -> void:
	if int(score[0]) >= score_to_win or int(score[1]) >= score_to_win:
		_finish("score")
	else:
		_reset_round()


func _show_score() -> void:
	var a := _arena()
	if a != null and a.has_method("set_score"):
		a.call("set_score", int(score[0]), int(score[1]))


# --- нокаут: возврат у своей стены ---

func _check_over() -> void:
	pass


func _on_doll_ko(attacker: Node, record: Dictionary, victim: Doll) -> void:
	if phase == Phase.OVER:
		return
	var feel := feel_enabled
	feel_enabled = false
	super._on_doll_ko(attacker, record, victim)
	feel_enabled = feel
	if feel:
		_camera_fx(25.0, record.get("position", victim.centre_of_mass()))
		_time_effect(Tuning.KO_SLOWMO_SCALE, KO_SLOWMO_S)
	victim.thrust_mult = 1.0
	_respawns.append([victim, Tuning.TUG_RESPAWN_S])


func _tick_respawns(delta: float) -> void:
	if _respawns.is_empty() or play_state == "over":
		return
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
			_bank_stats(d as Doll)
			var nd := respawn_doll(d as Doll)
			nd.control_enabled = play_state == "play" or play_state == "point"
			hp_changed.emit(nd, nd.hp, nd.max_hp)


## Секунд до возврата куклы (0 — жива или не ждёт).
func respawn_left(d: Doll) -> float:
	for e in _respawns:
		if e[0] == d:
			return maxf(float(e[1]), 0.0)
	return 0.0


# --- итоги ---

func _bank_stats(d: Doll) -> void:
	if d == null or not is_instance_valid(d):
		return
	_banked[d.player_index] = _merged_stats(d)


func _merged_stats(d: Doll) -> Dictionary:
	var out: Dictionary = d.stats.duplicate()
	var old: Dictionary = _banked.get(d.player_index, {})
	for k in old:
		if not out.has(k) or not (out[k] is float or out[k] is int):
			continue
		out[k] = out[k] + old[k] if SportMatch.SUM_STATS.has(String(k)) else maxf(float(out[k]), float(old[k]))
	return out


func leader() -> int:
	if int(score[0]) == int(score[1]):
		return -1
	return 0 if int(score[0]) > int(score[1]) else 1


## Итоги: победитель и места — по счёту команд; reason: "score" | "timeout". tally[player_index] = {team, hold_s, kos, kos_taken}.
func build_results(reason: String = "timeout") -> Dictionary:
	var r := super.build_results(reason)
	var lead := leader()
	var all := dolls()
	all.sort_custom(func(a: Doll, b: Doll) -> bool:
		var la := team_of(a) == lead
		var lb := team_of(b) == lead
		if la != lb:
			return la
		return a.player_index < b.player_index)
	var ranks: Array = []
	var stats: Dictionary = {}
	var combo_score: Dictionary = {}
	var tally := {}
	var winner: Doll = null
	for d in all:
		var dd := d as Doll
		var won := lead >= 0 and team_of(dd) == lead
		ranks.append(0 if lead < 0 or won else 1)
		if won and winner == null:
			winner = dd
		stats[dd] = _merged_stats(dd)
		combo_score[dd] = float(stats[dd].get("combo_score", 0.0))
		tally[dd.player_index] = {"team": team_of(dd), "hold_s": snappedf(float(hold_s.get(dd.player_index, 0.0)), 0.1),
			"kos": int(stats[dd].get("kos", 0)), "kos_taken": int(stats[dd].get("kos_taken", 0))}
	var medals: Dictionary = r.get("medals", {})
	medals.erase("Winner")
	medals.erase("Survivor")
	if winner != null:
		medals["Winner"] = winner
	r["places"] = all
	r["ranks"] = ranks
	r["stats"] = stats
	r["combo_score"] = combo_score
	r["medals"] = medals
	r["winner"] = winner
	r["winner_team"] = lead
	r["draw"] = lead < 0
	r["ko_records"] = []
	r["score"] = score.duplicate()
	r["points"] = points.duplicate(true)
	r["tally"] = tally
	return r
