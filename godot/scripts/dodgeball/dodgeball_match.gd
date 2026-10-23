## Матч «Вышибалы» 3 на 3 (docs/plan-demo/DODGEBALL.md, MODES_IDEAS.md A3). Наследник Match: от него — регистрация кукол, DollCombat
## (удары кулаком через черту почти невозможны — стенка), отсчёт, HUD-сигналы. Своё:
##   • команды: player_index % 2 — 0 синие (левая половина), 1 красные (правая); Doll.team = "dodge_<команда>", группа team_group;
##   • мячи (SportBall, группа BALL_GROUP) — состояния: dead (лежит / катится: хватает команда своей половины, meta grab_team),
##     held (в руке ArmAssist), live (ушёл из руки броском быстрее DODGEBALL_THROW_MIN — летит; хватать может любой);
##   • живой мяч: попал в чужую куклу не медленнее DODGEBALL_HIT_SPEED — она выбита; чужая кисть с активной рукой рядом (CATCH_R) или
##     касание этой кистью — поймал: выбит бросивший, к ловцу возвращается первый выбитый свой; касание статики (пол, стена, потолок),
##     своей куклы, мяча в руке или DODGEBALL_LIVE_MAX_S — мёртвый;
##   • выбитый: ещё DODGEBALL_OUT_FADE_S виден (летит от удара), потом «на скамейке» (невидим, вне физики) до возврата или раунда;
##     нокаут по запасу тоже выбивает;
##   • раунд: команда без кукол на поле проиграла; время раунда вышло — у кого больше на поле; поровну — «до первого» DODGEBALL_SUDDEN_S,
##     потом раунд ничей. До DODGEBALL_ROUNDS_TO_WIN побед; матч не дольше DODGEBALL_TIME_S (ведущий по раундам, поровну — у кого больше на поле, иначе ничья).
## play_state: idle | countdown | play | round_over | over. Журналы для проб: events [{t, kind, ...}], tally {player_index: {team,
## throws, hits, catches, outs}}, rounds [{n, winner, t}]. Сигналы: score_changed(score), round_won(team), knocked(doll, by, how),
## caught(catcher, thrower, back) + унаследованные.
class_name DodgeballMatch
extends Match

signal score_changed(score: Array)
signal round_won(team: int)
signal knocked(doll: Doll, by: Node, how: String)
signal caught(catcher: Doll, thrower: Node, back: Doll)

const TEAM_PREFIX := "dodge_"
const CAM_GROUP := "dodgeball_cam"
const BALL_GROUP := "dodgeball_ball"
const LINE_GROUP := "dodgeball_line"
const POINT_COLOUR := Color(1.0, 0.92, 0.35)
const CATCH_COLOUR := Color(0.55, 1.0, 0.6)
const KO_SLOWMO_S := 0.3
const FLOOR_TICK_Y := 0.45        # центр живого мяча ниже — лежит на полу (касание могло не прийти отдельным контактом)
const DEAD_SLOW := 1.2            # живой мяч медленнее этого после LIVE_MIN_S — мёртвый (застрял, катится)
const LIVE_MIN_S := 0.25
const STUCK_LINE_M := 0.8         # мёртвый мяч у черты (|x| меньше) и почти стоит столько — толчок к половине, где мячей меньше
const STUCK_LINE_S := 1.5

@export var rounds_to_win: int = Tuning.DODGEBALL_ROUNDS_TO_WIN
@export var round_s: float = Tuning.DODGEBALL_ROUND_S
@export var time_s: float = Tuning.DODGEBALL_TIME_S
## Пробы: false — раунд не кончается, когда команда пуста (проверка правил по одному броску).
var round_rules := true

var score := [0, 0]
var play_state := "idle"
var round_n := 0
var round_time := 0.0
var sudden := false
var events: Array = []
var tally: Dictionary = {}
var rounds: Array = []
## Выбитые: Doll → {"t": fight_time, "bench": осталось с до скамейки (-1 — уже на скамейке)}. Порядок — out_order.
var out: Dictionary = {}
var out_order: Array = []
## Состояние мячей: SportBall → {state, team, thrower, arm, holder, live_t, prev_speed, stuck_t, why}.
var ball_state: Dictionary = {}
var _contacts: Array = []          # [ball, Node, speed] из body_entered (физику в коллбэке не трогаем)
var _round_pause := 0.0
var _first_fight := true
var _banked: Dictionary = {}


func _ready() -> void:
	time_limit_s = time_s
	hard_timeout_s = time_s
	super._ready()
	crit_enabled = false


# --- команды ---

static func team_of(d: Object) -> int:
	if d == null or not is_instance_valid(d):
		return -1
	var pi: Variant = d.get("player_index")
	return (int(pi) % 2) if pi != null else -1


static func team_name(team: int) -> String:
	return TranslationServer.translate("СИНИЕ") if team == 0 else TranslationServer.translate("КРАСНЫЕ")


static func colour_of(team: int) -> Color:
	return Tuning.DODGEBALL_COLORS[clampi(team, 0, 1)]


static func doll_name(d: Object) -> String:
	if d == null or not is_instance_valid(d):
		return "—"
	return "P%d" % (int(d.get("player_index")) + 1)


## Сторона своей половины по x: синие — слева (−1).
static func home_dir(team: int) -> float:
	return -1.0 if team == 0 else 1.0


static func team_group(team: int) -> String:
	return "dodge_team_%d" % team


func register(d: Doll) -> void:
	var fresh := not _order.has(d)
	super.register(d)
	if not fresh:
		return
	d.team = TEAM_PREFIX + str(team_of(d))
	_enlist(d)
	if d.is_node_ready():
		_dress(d)
	else:
		d.ready.connect(_dress.bind(d), CONNECT_ONE_SHOT)
	if not tally.has(d.player_index):
		tally[d.player_index] = _fresh_tally(team_of(d))


static func _fresh_tally(team: int) -> Dictionary:
	return {"team": team, "throws": 0, "hits": 0, "catches": 0, "outs": 0}


## На поле: группы камеры и команды, видима и в физике.
func _enlist(d: Doll) -> void:
	d.add_to_group(CAM_GROUP)
	d.add_to_group(team_group(team_of(d)))
	d.visible = true
	d.process_mode = Node.PROCESS_MODE_INHERIT


func _dress(d: Doll) -> void:
	if is_instance_valid(d):
		d._recolor(d, Doll.SHIRT_MATERIAL, colour_of(team_of(d)))


func spawn_point_for(d: Doll) -> Vector3:
	var pts: Array = Tuning.DODGEBALL_SPAWN
	if d.player_index >= 0 and d.player_index < pts.size():
		var p: Vector2 = pts[d.player_index]
		return Vector3(p.x, p.y, 0.0)
	return super.spawn_point_for(d)


## Пересоздание (раунд, возврат, R): новая кукла — снова на поле (группы камеры и команды старой могли быть сняты скамейкой).
func respawn_doll(old: Doll, keep_lost := false) -> Doll:
	out.erase(old)
	out_order.erase(old)
	var d := super.respawn_doll(old, keep_lost)
	if d != old:
		_enlist(d)
	return d


## Кукла в игре: на поле и не выбита.
func in_play(d: Object) -> bool:
	return d != null and is_instance_valid(d) and d is Doll and not out.has(d) and (d as Doll).is_inside_tree() and (d as Doll).alive


func team_dolls(team: int, playing_only := false) -> Array:
	var res: Array = []
	for d in dolls():
		if team_of(d) == team and (not playing_only or in_play(d)):
			res.append(d)
	return res


func on_court(team: int) -> int:
	return team_dolls(team, true).size()


static func arm_of(d: Doll) -> ArmAssist:
	if d == null or not is_instance_valid(d):
		return null
	for c in d.get_children():
		if c is ArmAssist and (c as ArmAssist).primary:
			return c
	return null


# --- мячи ---

func balls() -> Array:
	var res: Array = []
	for n in get_tree().get_nodes_in_group(BALL_GROUP):
		if is_instance_valid(n) and n is SportBall:
			res.append(n)
	return res


## Мяч вышибал: лёгкий, руками берётся (у SportBall по умолчанию no_grab), стенку по черте не замечает. Один раз на мяч.
func _adopt(b: SportBall) -> void:
	if ball_state.has(b):
		return
	if b.has_meta(&"no_grab"):
		b.remove_meta(&"no_grab")
	b.apply_sport("volleyball")
	b.floor_kick = 0.0
	b.mass = Tuning.DODGEBALL_BALL_MASS
	b.gravity_scale = Tuning.DODGEBALL_BALL_GRAVITY
	b.linear_damp = Tuning.DODGEBALL_BALL_DAMP
	b.angular_damp = 0.6
	var pm := PhysicsMaterial.new()
	pm.bounce = Tuning.DODGEBALL_BALL_BOUNCE
	pm.friction = 0.5
	b.physics_material_override = pm
	for l in get_tree().get_nodes_in_group(LINE_GROUP):
		if l is PhysicsBody3D and not b.get_collision_exceptions().has(l):
			b.add_collision_exception_with(l)
	b.body_entered.connect(_on_ball_contact.bind(b))
	ball_state[b] = _dead_state(b, "spawn")
	_side_meta(b)


func _ensure_balls() -> void:
	for b in balls():
		_adopt(b as SportBall)


static func _dead_state(_b: SportBall, why: String) -> Dictionary:
	return {"state": "dead", "team": -1, "thrower": null, "arm": null, "holder": null, "live_t": 0.0, "prev_speed": 0.0,
		"stuck_t": 0.0, "why": why}


func ball_info(b: Object) -> Dictionary:
	return ball_state.get(b, {})


func ball_is(b: Object, st: String) -> bool:
	return String(ball_state.get(b, {}).get("state", "")) == st


## Мёртвый мяч хватает команда той половины, где он лежит (на черте — по стороне центра).
func _side_meta(b: SportBall) -> void:
	var st: Dictionary = ball_state.get(b, {})
	if String(st.get("state", "dead")) == "dead":
		b.set_meta(&"grab_team", TEAM_PREFIX + ("0" if b.global_position.x < 0.0 else "1"))
	elif b.has_meta(&"grab_team"):
		b.remove_meta(&"grab_team")


func _place_balls() -> void:
	_ensure_balls()
	var spots: Array = Tuning.DODGEBALL_BALL_SPOTS
	var i := 0
	for b in balls():
		var sb := b as SportBall
		var h := ArmAssist.holder_of(sb)
		if h != null:
			h.release("drop")
		var p: Vector2 = spots[i % spots.size()]
		sb.place(Vector3(p.x, p.y, 0.0))
		ball_state[sb] = _dead_state(sb, "spawn")
		_side_meta(sb)
		i += 1
	_contacts.clear()


func _release_balls() -> void:
	for b in balls():
		(b as SportBall).release()


func _set_dead(b: SportBall, why: String) -> void:
	var st: Dictionary = ball_state.get(b, {})
	if st.is_empty():
		return
	if String(st["state"]) == "live":
		events.append({"t": snappedf(fight_time, 0.01), "kind": "dead", "why": why, "x": snappedf(b.global_position.x, 0.01),
			"y": snappedf(b.global_position.y, 0.01)})
	st["state"] = "dead"
	st["why"] = why
	st["thrower"] = null
	st["team"] = -1
	st["live_t"] = 0.0
	_side_meta(b)


func _on_ball_contact(body: Node, b: SportBall) -> void:
	if String(ball_state.get(b, {}).get("state", "")) != "live":
		return
	_contacts.append([b, body, maxf(float(ball_state[b]["prev_speed"]), b.linear_velocity.length())])


# --- фазы ---

func begin() -> void:
	score = [0, 0]
	round_n = 1
	rounds.clear()
	events.clear()
	tally.clear()
	for d in dolls():
		tally[(d as Doll).player_index] = _fresh_tally(team_of(d))
	out.clear()
	out_order.clear()
	sudden = false
	_first_fight = true
	_banked.clear()
	play_state = "countdown"
	_place_balls()
	super.begin()
	score_changed.emit(score.duplicate())
	_show_score()


func restart() -> void:
	play_state = "idle"
	super.restart()


func _finish(reason: String) -> void:
	play_state = "over"
	super._finish(reason)


func stasis_allowed() -> bool:
	return play_state == "play" and super.stasis_allowed()


func _start_fight() -> void:
	for d in dolls():
		var dd := d as Doll
		if _first_fight:
			dd.reset_for_match()
		dd.control_enabled = in_play(dd)
		var c := combat_of(dd)
		if c != null:
			c.reset()
	if _first_fight:
		fight_time = 0.0
	var first := _first_fight
	_first_fight = false
	sudden = false
	_set_phase(Phase.FIGHT)
	for d in dolls():
		hp_changed.emit(d, (d as Doll).hp, (d as Doll).max_hp)
	play_state = "play"
	round_time = 0.0
	_release_balls()
	announce.emit(tr("ВЫШИБАЙ!"), ANNOUNCE_COLORS["fight"], "fight" if first else "countdown")


## Новый раунд: все шестеро снова на поле, мячи на вводе, короткий отсчёт.
func _reset_round() -> void:
	for d in dolls():
		_bank_stats(d as Doll)
		respawn_doll(d)
	out.clear()
	out_order.clear()
	for d in dolls():
		(d as Doll).control_enabled = false
	_place_balls()
	round_n += 1
	play_state = "countdown"
	_set_phase(Phase.COUNTDOWN)
	_countdown_left = Tuning.DODGEBALL_RESET_COUNTDOWN_S
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
	_tick_bench(delta)
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
				_tick_balls(delta)
				if play_state == "play":
					_tick_round_clock()
				if play_state == "play" and fight_time >= time_limit_s:
					_finish("timeout")
			elif play_state == "round_over":
				_round_pause -= delta
				if _round_pause <= 0.0:
					_after_round()


func knockback_mult() -> float:
	return 1.0


func stability_mult() -> float:
	return 1.0


## Секунд до конца раунда (или «до первого»).
func time_left_s() -> float:
	if sudden:
		return maxf(round_s + Tuning.DODGEBALL_SUDDEN_S - round_time, 0.0)
	return maxf(round_s - round_time, 0.0)


func _tick_round_clock() -> void:
	if not round_rules:
		return
	if not sudden and round_time >= round_s:
		var a := on_court(0)
		var b := on_court(1)
		if a != b:
			_round_to(0 if a > b else 1, "time")
			return
		sudden = true
		_set_phase(Phase.SUDDEN_DEATH)
		announce.emit(tr("ДО ПЕРВОГО ВЫБИТОГО!"), ANNOUNCE_COLORS["ko"], "countdown")
	elif sudden and round_time >= round_s + Tuning.DODGEBALL_SUDDEN_S:
		_round_to(-1, "time")


# --- мячи: тик ---

func _tick_balls(delta: float) -> void:
	_resolve_contacts()
	for b in balls():
		var sb := b as SportBall
		var st: Dictionary = ball_state.get(sb, {})
		if st.is_empty():
			_adopt(sb)
			st = ball_state[sb]
		var h := ArmAssist.holder_of(sb)
		var s := String(st["state"])
		if h != null and is_instance_valid(h.doll):
			var hd := h.doll
			if not in_play(hd):
				h.release("drop")
			elif s == "live" and st["team"] != team_of(hd):
				_on_catch(hd, sb, h)
			else:
				st["state"] = "held"
				st["arm"] = h
				st["holder"] = hd
				st["team"] = team_of(hd)
				st["thrower"] = null
				_side_meta(sb)
		elif s == "held":
			_after_release(sb, st)
		elif s == "live":
			st["live_t"] = float(st["live_t"]) + delta
			var sp := sb.linear_velocity.length()
			if float(st["live_t"]) > Tuning.DODGEBALL_LIVE_MAX_S:
				_set_dead(sb, "long")
			elif sb.global_position.y <= FLOOR_TICK_Y:
				_set_dead(sb, "floor")
			elif float(st["live_t"]) > LIVE_MIN_S and sp < DEAD_SLOW:
				_set_dead(sb, "slow")
			else:
				_try_air_catch(sb, st)
		if String(st["state"]) == "dead":
			_side_meta(sb)
			_tick_stuck(sb, st, delta)
		st["prev_speed"] = sb.linear_velocity.length()


## Мяч ушёл из руки: бросок (ArmAssist._throw в том же тике отпускания, скорость не меньше THROW_MIN) — живой; иначе выронил — мёртвый.
func _after_release(b: SportBall, st: Dictionary) -> void:
	var arm: ArmAssist = st.get("arm") if is_instance_valid(st.get("arm")) else null
	var holder: Variant = st.get("holder")
	var thrown := false
	if arm != null and arm.last_release.get("body") == b and arm.last_throw.get("body") == b \
			and is_equal_approx(float(arm.last_throw.get("t", -1.0)), float(arm.last_release.get("t", -2.0))):
		thrown = b.linear_velocity.length() >= Tuning.DODGEBALL_THROW_MIN
	if not thrown or not is_instance_valid(holder):
		_set_dead(b, "drop")
		return
	# бросок бота — со скоростью его уровня (DODGEBALL_BOT_LEVELS.throw), направление руки сохраняется
	var br := (holder as Doll).get_node_or_null("DodgeballBrain") as DodgeballBrain
	if br != null and br.is_physics_processing() and br.throw_speed > 0.0:
		b.linear_velocity = b.linear_velocity.normalized() * minf(b.linear_velocity.length(), br.throw_speed)
	st["state"] = "live"
	st["thrower"] = holder
	st["team"] = team_of(holder)
	st["live_t"] = 0.0
	st["why"] = ""
	_side_meta(b)
	var t: Dictionary = tally.get((holder as Doll).player_index, {})
	if not t.is_empty():
		t["throws"] = int(t["throws"]) + 1
	events.append({"t": snappedf(fight_time, 0.01), "kind": "throw", "by": (holder as Doll).player_index,
		"speed": snappedf(b.linear_velocity.length(), 0.01)})


## Ловля в воздухе: чужая кисть с активной рукой (ЛКМ у человека, цель у бота) и пустой рукой рядом с живым мячом — схватила.
func _try_air_catch(b: SportBall, st: Dictionary) -> void:
	var bp := b.global_position
	for d in dolls():
		var dd := d as Doll
		if not in_play(dd) or team_of(dd) == int(st["team"]) or not dd.control_enabled or dd.is_stunned():
			continue
		var a := arm_of(dd)
		if a == null or not a.arm_active or a.is_holding() or a.part == null or not is_instance_valid(a.part):
			continue
		if a.grip_global().distance_to(bp) - Tuning.SPORT_BALL_RADIUS > Tuning.DODGEBALL_CATCH_R:
			continue
		if a.grab(b):
			_on_catch(dd, b, a)
			return


## Мёртвый мяч застыл у черты (под стенкой, обеим командам неудобно) — толчок к половине, где мячей меньше.
func _tick_stuck(b: SportBall, st: Dictionary, delta: float) -> void:
	if absf(b.global_position.x) > STUCK_LINE_M or b.linear_velocity.length() > 0.6 or ArmAssist.holder_of(b) != null or b.freeze:
		st["stuck_t"] = 0.0
		return
	st["stuck_t"] = float(st["stuck_t"]) + delta
	if float(st["stuck_t"]) < STUCK_LINE_S:
		return
	st["stuck_t"] = 0.0
	var left := 0
	for o in balls():
		if (o as Node3D).global_position.x < 0.0:
			left += 1
	var dir := -1.0 if left * 2 < balls().size() else 1.0
	b.linear_velocity = Vector3(dir * 3.0, 2.0, 0.0)
	events.append({"t": snappedf(fight_time, 0.01), "kind": "nudge", "dir": dir})


func _resolve_contacts() -> void:
	if _contacts.is_empty():
		return
	var list := _contacts.duplicate()
	_contacts.clear()
	for c in list:
		var b := c[0] as SportBall
		var body: Variant = c[1]
		var speed := float(c[2])
		if not is_instance_valid(b) or not is_instance_valid(body) or not ball_is(b, "live"):
			continue
		var st: Dictionary = ball_state[b]
		if body is SportBall:
			if ArmAssist.holder_of(body as SportBall) != null:
				_set_dead(b, "blocked")
			continue
		var d := SportBall.doll_of(body as Node)
		if d == null:
			if body is StaticBody3D or body is CSGShape3D:
				_set_dead(b, "floor" if b.global_position.y <= Tuning.DODGEBALL_FLOOR_Y else "wall")
			continue
		if not in_play(d):
			continue
		if team_of(d) == int(st["team"]):
			if d != st.get("thrower"):
				_set_dead(b, "friend")
			continue
		if speed < Tuning.DODGEBALL_HIT_SPEED:
			_set_dead(b, "slow")
			continue
		var a := arm_of(d)
		if a != null and a.arm_active and not a.is_holding() and body == a.part and d.control_enabled and not d.is_stunned() \
				and a.grab(b):
			_on_catch(d, b, a)
			continue
		var by: Variant = st.get("thrower")
		_set_dead(b, "hit")
		knock_out(d, by as Node if is_instance_valid(by) else null, "hit", speed)


# --- выбивание, ловля, возврат ---

## Выбить куклу: how — "hit" (мячом), "caught" (её мяч поймали), "ko" (запас кончился), "probe".
func knock_out(d: Doll, by: Node, how: String, speed := 0.0) -> void:
	if not in_play(d) and not (how == "ko" and is_instance_valid(d) and not out.has(d)):
		return
	if play_state != "play":
		return
	out[d] = {"t": fight_time, "bench": Tuning.DODGEBALL_OUT_FADE_S, "how": how}
	out_order.append(d)
	var a := arm_of(d)
	if a != null:
		a.clear_target_override()
		if a.is_holding():
			a.release("drop")
	d.control_enabled = false
	d.input_vec = Vector2.ZERO
	if d.is_in_group(CAM_GROUP):
		d.remove_from_group(CAM_GROUP)
	if d.is_in_group(team_group(team_of(d))):
		d.remove_from_group(team_group(team_of(d)))
	var t: Dictionary = tally.get(d.player_index, {})
	if not t.is_empty():
		t["outs"] = int(t["outs"]) + 1
	if how == "hit" and by is Doll and is_instance_valid(by):
		var tb: Dictionary = tally.get((by as Doll).player_index, {})
		if not tb.is_empty():
			tb["hits"] = int(tb["hits"]) + 1
	events.append({"t": snappedf(fight_time, 0.01), "kind": "out", "who": d.player_index, "how": how,
		"by": (by as Doll).player_index if by is Doll and is_instance_valid(by) else -1, "speed": snappedf(speed, 0.01)})
	knocked.emit(d, by, how)
	announce.emit(tr("ВЫБИТ %s") % doll_name(d), colour_of(team_of(d)).lightened(0.35), "ko")
	if feel_enabled:
		_camera_fx(18.0, d.centre_of_mass())
		if how == "hit":
			_time_effect(Tuning.KO_SLOWMO_SCALE, KO_SLOWMO_S)
	_check_round()


## Поймал: бросивший выбит (если ещё на поле), к ловцу возвращается первый выбитый из его команды.
func _on_catch(catcher: Doll, b: SportBall, a: ArmAssist) -> void:
	var st: Dictionary = ball_state[b]
	var thrower: Variant = st.get("thrower")
	st["state"] = "held"
	st["arm"] = a
	st["holder"] = catcher
	st["team"] = team_of(catcher)
	st["thrower"] = null
	_side_meta(b)
	var t: Dictionary = tally.get(catcher.player_index, {})
	if not t.is_empty():
		t["catches"] = int(t["catches"]) + 1
	events.append({"t": snappedf(fight_time, 0.01), "kind": "catch", "who": catcher.player_index,
		"thrower": (thrower as Doll).player_index if thrower is Doll and is_instance_valid(thrower) else -1})
	announce.emit(tr("ПОЙМАЛ!"), CATCH_COLOUR, "ko")
	var back := _bring_back(team_of(catcher))
	caught.emit(catcher, thrower as Node if is_instance_valid(thrower) else null, back)
	if is_instance_valid(thrower) and thrower is Doll and in_play(thrower as Doll):
		knock_out(thrower as Doll, catcher, "caught")
	elif round_rules:
		_check_round()


## Вернуть на поле первого выбитого команды team (null — некого). Кукла создаётся заново у своей точки появления.
func _bring_back(team: int) -> Doll:
	for d in out_order:
		if not is_instance_valid(d) or team_of(d) != team:
			continue
		var nd := respawn_doll(d as Doll)
		nd.control_enabled = play_state == "play"
		hp_changed.emit(nd, nd.hp, nd.max_hp)
		events.append({"t": snappedf(fight_time, 0.01), "kind": "back", "who": nd.player_index})
		announce.emit(tr("%s СНОВА В ИГРЕ") % doll_name(nd), colour_of(team).lightened(0.35), "countdown")
		return nd
	return null


## Выбитый уходит со сцены через OUT_FADE_S: невидим и вне физики до возврата (respawn_doll) или раунда.
func _tick_bench(delta: float) -> void:
	for d in out.keys():
		var e: Dictionary = out[d]
		if float(e["bench"]) < 0.0:
			continue
		e["bench"] = float(e["bench"]) - delta
		if float(e["bench"]) > 0.0:
			continue
		e["bench"] = -1.0
		if is_instance_valid(d) and (d as Doll).is_inside_tree():
			_bench(d as Doll)


func _bench(d: Doll) -> void:
	var a := arm_of(d)
	if a != null and a.is_holding():
		a.release("drop")
	d.visible = false
	d.process_mode = Node.PROCESS_MODE_DISABLED


func _check_round() -> void:
	if not round_rules or play_state != "play":
		return
	var a := on_court(0)
	var b := on_court(1)
	if a == 0 or b == 0:
		_round_to(-1 if a == b else (0 if a > 0 else 1), "out")
	elif sudden and a != b:
		_round_to(0 if a > b else 1, "sudden")


func _round_to(team: int, why: String) -> void:
	if play_state != "play":
		return
	if team >= 0:
		score[team] = int(score[team]) + 1
	rounds.append({"n": round_n, "winner": team, "why": why, "t": snappedf(round_time, 0.01), "score": score.duplicate()})
	events.append({"t": snappedf(fight_time, 0.01), "kind": "round", "winner": team, "why": why})
	play_state = "round_over"
	_round_pause = Tuning.DODGEBALL_ROUND_PAUSE_S
	for d in dolls():
		(d as Doll).control_enabled = false
	score_changed.emit(score.duplicate())
	if team >= 0:
		round_won.emit(team)
		announce.emit(tr("РАУНД: %s") % team_name(team), colour_of(team).lightened(0.35), "point")
	else:
		announce.emit(tr("РАУНД НИЧЕЙ"), Color.WHITE, "point")
	_show_score()
	if feel_enabled and FxPreset.time_fx():
		_time_effect(Tuning.SPORT_GOAL_SLOWMO, Tuning.SPORT_GOAL_SLOWMO_S)


func _after_round() -> void:
	if int(score[0]) >= rounds_to_win or int(score[1]) >= rounds_to_win:
		_finish("score")
	else:
		_reset_round()


func _show_score() -> void:
	var ar := _arena()
	if ar != null and ar.has_method("set_score"):
		ar.call("set_score", int(score[0]), int(score[1]))


# --- нокаут по запасу ---

func _check_over() -> void:
	pass


## Нокаут (запас кончился — кулаки через стенку, брошенный мяч бьёт и уроном) — тоже выбит, без крит-кино.
func _on_doll_ko(attacker: Node, record: Dictionary, victim: Doll) -> void:
	if phase == Phase.OVER:
		return
	ko_records.append(record.duplicate())
	if attacker is Doll and attacker != victim:
		var s: Dictionary = (attacker as Doll).stats
		s["kos"] = int(s.get("kos", 0)) + 1
	victim.stats["kos_taken"] = maxi(int(victim.stats.get("kos_taken", 0)), 1)
	hp_changed.emit(victim, 0.0, victim.max_hp)
	if play_state == "play" and not out.has(victim):
		knock_out(victim, attacker, "ko")


# --- итоги ---

func _bank_stats(d: Doll) -> void:
	if d == null or not is_instance_valid(d):
		return
	_banked[d.player_index] = _merged_stats(d)


func _merged_stats(d: Doll) -> Dictionary:
	var res: Dictionary = d.stats.duplicate()
	var old: Dictionary = _banked.get(d.player_index, {})
	for k in old:
		if not res.has(k) or not (res[k] is float or res[k] is int):
			continue
		res[k] = res[k] + old[k] if SportMatch.SUM_STATS.has(String(k)) else maxf(float(res[k]), float(old[k]))
	return res


## Ведущий по раундам; поровну — у кого сейчас больше на поле (матч кончился по времени посреди раунда); и так поровну — -1.
func leader() -> int:
	if int(score[0]) == int(score[1]):
		var a := on_court(0)
		var b := on_court(1)
		if a == b:
			return -1
		return 0 if a > b else 1
	return 0 if int(score[0]) > int(score[1]) else 1


## Итоги: победитель и места — по раундам команд; reason: "score" | "timeout". tally[player_index] = {team, throws, hits, catches, outs}.
func build_results(reason: String = "timeout") -> Dictionary:
	var r := super.build_results(reason)
	var lead := leader()
	var all := dolls()
	all.sort_custom(func(a: Doll, b: Doll) -> bool:
		var la := team_of(a) == lead
		var lb := team_of(b) == lead
		if la != lb:
			return la
		var ha := int(tally.get(a.player_index, {}).get("hits", 0))
		var hb := int(tally.get(b.player_index, {}).get("hits", 0))
		if ha != hb:
			return ha > hb
		return a.player_index < b.player_index)
	var ranks: Array = []
	var stats: Dictionary = {}
	var combo_score: Dictionary = {}
	var winner: Doll = null
	for d in all:
		var dd := d as Doll
		var won := lead >= 0 and team_of(dd) == lead
		ranks.append(0 if lead < 0 or won else 1)
		if won and winner == null:
			winner = dd
		stats[dd] = _merged_stats(dd)
		combo_score[dd] = float(stats[dd].get("combo_score", 0.0))
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
	r["rounds"] = rounds.duplicate(true)
	r["tally"] = tally.duplicate(true)
	return r
