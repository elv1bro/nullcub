## Матч спорт-зала (docs/plan-demo/SPORT.md; автор 04.10: «режим ФУТБОЛ, где куклам нужно пинать мяч в чужие ворота, до 3 голов»).
## Наследник Match: от него — регистрация кукол, удары и их эффекты, надписи табло, HUD, итоги. Своё — счёт и розыгрыши:
##   • виды спорта (Tuning.SPORTS, set_sport): football — мяч за линию ворот под перекладиной; basketball — мяч прошёл кольцо
##     сверху вниз; volleyball — мяч коснулся пола на чужой половине; hockey (HOCKEY.md) — шайба (Puck вместо мяча) пересекла линию
##     низких ворот, клюшки (HockeySticks), свои часы и срок возврата после нокаута (_apply_hockey). Команда 0 (P1, P3) играет слева и атакует вправо, команда 1 —
##     наоборот; гол в свои ворота идёт сопернику;
##   • розыгрыш: ввод мяча (фаза COUNTDOWN: куклы на своих точках, мяч заморожен на точке ввода арены) → игра (FIGHT) → гол: надпись,
##     замедление, пауза SPORT_GOAL_PAUSE_S (мяч в сетке) → новый ввод. Часы матча идут только в игре;
##   • конец: goals_to_win голов (SPORT_GOALS_TO_WIN = 3) или время SPORT_TIME_LIMIT_S — побеждает ведущий; при равном счёте —
##     «золотой гол» (фаза SUDDEN_DEATH без её усилений: sd_step держится 0) до SPORT_GOLDEN_S, потом ничья;
##   • нокаут матч не кончает: кукла возвращается у своих ворот через SPORT_KO_RESPAWN_S («удаление» — соперник играет в пустые);
##     крит-кино выключено (crit_enabled = false) — розыгрыш не останавливается на полторы секунды;
##   • кукла между розыгрышами не чинится (keeps_damage, автор 06.10): оторванное не отрастает до конца матча; на расстановке после
##     гола запас и износ суставов — как были; после нокаута — полный запас того, что осталось. Новый матч (R, F) — куклы целые;
##   • итоги (build_results): победитель и места — по счёту, плюс score / sport / goals; статистика кукол копится через все
##     розыгрыши (куклы на вводе пересоздаются — Match.respawn_doll).
## Сигналы для HUD (scenes/sport/sport_hud.gd) и арены: score_changed, goal_scored, sport_changed, kickoff + унаследованные.
## goals — журнал для проб: [{t, team, scorer, own_goal, sport, score}].
class_name SportMatch
extends Match

signal score_changed(score: Array)
signal goal_scored(team: int, scorer: Doll, own_goal: bool)
signal sport_changed(id: String)
signal kickoff(serve_team: int)
## ХОККЕЙ (HOCKEY.md, правила 23.10): вратарь команды team накрыл шайбу в своей вратарской.
signal puck_saved(team: int, keeper: Doll)

const GOAL_COLOUR := Color(1.0, 0.85, 0.3)
const SAVE_COLOUR := Color(0.55, 0.85, 1.0)
const KO_SLOWMO_S := 0.45
## Статистика, которая через розыгрыши складывается; остальное (hardest_hit, max_speed, combo_max…) — максимум.
const SUM_STATS := ["damage_dealt", "damage_taken", "weapon_hits", "wall_collisions", "air_time", "rotations", "flight_distance",
	"combo_score", "kos", "kos_taken", "self_damage", "low_hp_survived_s"]

@export var sport := "football"
@export var goals_to_win: int = Tuning.SPORT_GOALS_TO_WIN
@export var ball_path: NodePath
@export var kickoff_s: float = Tuning.SPORT_KICKOFF_S

var score := [0, 0]
var ball: SportBall
var goals: Array = []
## idle | kickoff | play | goal | over
var play_state := "idle"
var golden := false
## Кому вводят мяч (волейбол: падает на эту половину): пропустившая команда; первый ввод — команде 0.
var serve_team := 0
var ball_rescues := 0
var _goal_t := 0.0
var _first_kickoff := true
var _respawns: Array = []          # [[Doll, осталось с]]
var _ball_prev := Vector2.ZERO
var _banked: Dictionary = {}       # player_index → накопленная статистика прошлых розыгрышей
var _corner_s := 0.0
## ХОККЕЙ (HOCKEY.md): все снаряды сцены (мяч, шайба) — активен один по виду (_pick_ball); клюшки — узел HockeySticks.
var _balls: Array = []
var _hockey_on := false
var sticks: HockeySticks
## ХОККЕЙ, правила 23.10 (Tuning.HOCKEY_CREASE_M …): журнал сейвов для проб [{t, team, keeper}]; _save_team — чей вратарь накрыл
## шайбу (пауза play_state "save", потом вбрасывание на его половине); _save_by — кукла, коснувшаяся шайбы в своей вратарской.
var saves: Array = []
## Вбрасывание не первое (после гола или сейва): чья шайба (serve_team, −1 — первое или не хоккей) и часы fight_time в этот миг —
## для роли ботов «соперник вбрасывающего ждёт дома» (HockeyBrain, Tuning.HOCKEY_FACEOFF_HOLD_S).
var faceoff_team := -1
var faceoff_clock := 0.0
var faceoff_n := 0
## Шайба выше HOCKEY_HIGH_Y дольше HOCKEY_HIGH_S — «вне игры» (свисток, вбрасывание): счётчик для проб и сколько уже висит.
var high_whistles := 0
var _high_s := 0.0
var _save_team := -1
var _save_by: Doll = null


func _ready() -> void:
	time_limit_s = Tuning.SPORT_TIME_LIMIT_S
	hard_timeout_s = Tuning.SPORT_TIME_LIMIT_S + Tuning.SPORT_GOLDEN_S
	super._ready()
	crit_enabled = false


func _late_ready() -> void:
	ball = get_node_or_null(ball_path) as SportBall if ball_path != NodePath() else null
	if ball == null:
		ball = get_tree().get_first_node_in_group(SportBall.GROUP) as SportBall
	# ХОККЕЙ (HOCKEY.md): запомнить все снаряды сцены — шайба и мяч меняются по виду
	if ball != null:
		_balls.append(ball)
	for n in get_tree().get_nodes_in_group(SportBall.GROUP):
		if not _balls.has(n):
			_balls.append(n)
	for b in _balls:
		if b is Puck:
			(b as Puck).touched.connect(_on_puck_touched)
	_apply_sport()
	super._late_ready()


# --- команды и вид спорта ---

static func team_of(d: Object) -> int:
	if d == null or not is_instance_valid(d):
		return -1
	var pi: Variant = d.get("player_index")
	return (int(pi) % 2) if pi != null else -1


## Направление атаки команды по x: команда 0 бьёт вправо.
static func attack_dir(team: int) -> float:
	return 1.0 if team == 0 else -1.0


func rules() -> Dictionary:
	return Tuning.SPORTS.get(sport, Tuning.SPORTS["football"])


func register(d: Doll) -> void:
	super.register(d)
	d.team = "sport_%d" % team_of(d)


## Сменить вид спорта: снаряд арены, мяч и матч заново.
func set_sport(id: String) -> void:
	if not Tuning.SPORTS.has(id):
		return
	sport = id
	_apply_sport()
	sport_changed.emit(id)
	if _started:
		restart()


func next_sport() -> String:
	var i: int = Tuning.SPORT_ORDER.find(sport)
	set_sport(String(Tuning.SPORT_ORDER[(i + 1) % Tuning.SPORT_ORDER.size()]))
	return sport


func _apply_sport() -> void:
	var a := _arena()
	if a != null and a.has_method("apply_sport"):
		a.call("apply_sport", sport)
	_apply_hockey()   # ХОККЕЙ (HOCKEY.md)
	if ball != null:
		ball.apply_sport(sport)
		if a != null and a.has_method("ball_passthrough"):
			for b in a.call("ball_passthrough"):
				if b is PhysicsBody3D:
					ball.add_collision_exception_with(b)


## ХОККЕЙ (HOCKEY.md): снаряд по виду (шайба / мяч), клюшки, свои часы и возврат после нокаута. Другие виды не меняются:
## числа трогаются только на переходе в хоккей и обратно.
func _apply_hockey() -> void:
	var hk := sport == "hockey"
	_pick_ball(hk)
	if hk != _hockey_on:
		_hockey_on = hk
		time_limit_s = Tuning.HOCKEY_TIME_S if hk else Tuning.SPORT_TIME_LIMIT_S
		hard_timeout_s = time_limit_s + (Tuning.HOCKEY_GOLDEN_S if hk else Tuning.SPORT_GOLDEN_S)
		goals_to_win = Tuning.HOCKEY_GOALS_TO_WIN if hk else Tuning.SPORT_GOALS_TO_WIN
	if hk and sticks == null:
		sticks = HockeySticks.new()
		sticks.name = "HockeySticks"
		add_child(sticks)
	elif not hk and sticks != null:
		remove_child(sticks)
		sticks.queue_free()
		sticks = null


## ХОККЕЙ: активный снаряд — шайба (Puck) при хоккее, иначе мяч; второй выключен — невидим, вне физики и вне всех своих групп
## (sport_ball, камера площадки: боты и камера его не видят), группы возвращаются при включении.
func _pick_ball(hk: bool) -> void:
	var want: SportBall = null
	for b in _balls:
		if is_instance_valid(b) and ((b is Puck) == hk):
			want = b
			break
	if want == null:
		return
	ball = want
	for b in _balls:
		if not is_instance_valid(b):
			continue
		var on: bool = b == want
		var sb := b as SportBall
		sb.visible = on
		sb.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
		if on and sb.has_meta(&"sport_groups"):
			for g in sb.get_meta(&"sport_groups"):
				sb.add_to_group(g)
			sb.remove_meta(&"sport_groups")
		elif not on and not sb.has_meta(&"sport_groups"):
			sb.freeze = true
			var gs: Array = []
			for g in sb.get_groups():
				if not String(g).begins_with("_"):
					gs.append(g)
			sb.set_meta(&"sport_groups", gs)
			for g in gs:
				sb.remove_from_group(g)


func ko_respawn_s() -> float:
	return Tuning.HOCKEY_KO_RESPAWN_S if sport == "hockey" else Tuning.SPORT_KO_RESPAWN_S


# --- фазы ---

func begin() -> void:
	score = [0, 0]
	goals.clear()
	golden = false
	serve_team = 0
	ball_rescues = 0
	_first_kickoff = true
	_respawns.clear()
	_banked.clear()
	saves.clear()
	high_whistles = 0
	_save_team = -1
	_save_by = null
	_place_ball()
	play_state = "kickoff"
	super.begin()
	score_changed.emit(score.duplicate())
	_show_score()
	kickoff.emit(serve_team)


func _finish(reason: String) -> void:
	play_state = "over"
	super._finish(reason)


## СТАЗИС (STASIS.md §3): время ждёт игрока только в розыгрыше. Ввод мяча (отсчёт), пауза после гола и итоги идут сами — иначе
## пауза после гола тянулась бы, пока игрок стоит.
func stasis_allowed() -> bool:
	return play_state == "play" and super.stasis_allowed()


func _place_ball() -> void:
	if ball == null:
		return
	var a := _arena()
	var pos := Vector3(0.0, float(rules().get("ball_y", 3.0)), 0.0)
	if a != null and a.has_method("ball_spawn"):
		pos = a.call("ball_spawn", serve_team)
	pos = hockey_faceoff_spot(pos)
	faceoff_team = serve_team if _hockey_on and not _first_kickoff else -1
	faceoff_clock = fight_time
	faceoff_n += 1
	ball.place(pos)
	_ball_prev = ball.pos2()


## ХОККЕЙ, правила 23.10: точка вбрасывания. Первое — по центру (арена); после гола — на половине пропустившей команды
## (serve_team) в HOCKEY_FACEOFF_X от центра: забившая начинает в защите и успевает к своим воротам.
func hockey_faceoff_spot(arena_spot: Vector3) -> Vector3:
	if not _hockey_on or _first_kickoff:
		return arena_spot
	return Vector3(-attack_dir(serve_team) * Tuning.HOCKEY_FACEOFF_X, arena_spot.y, 0.0)


## Ввод мяча: первый — вместо FIGHT! базового матча (сброс кукол и часов), следующие — часы и статистика идут дальше.
func _start_fight() -> void:
	for d in dolls():
		var dd := d as Doll
		if _first_kickoff:
			dd.reset_for_match()
		dd.control_enabled = true
		var c := combat_of(dd)
		if c != null:
			c.reset()
	if _first_kickoff:
		fight_time = 0.0
	var first := _first_kickoff
	_first_kickoff = false
	if golden:
		sd_step = 0
	_set_phase(Phase.SUDDEN_DEATH if golden else Phase.FIGHT)
	for d in dolls():
		hp_changed.emit(d, (d as Doll).hp, (d as Doll).max_hp)
	if ball != null:
		ball.release()
		_ball_prev = ball.pos2()
	play_state = "play"
	announce.emit(tr("PLAY!"), ANNOUNCE_COLORS["fight"], "fight" if first else "countdown")


## Хоккей: кто касался шайбы за последние HOCKEY_CARRY_S, летит медленнее — потолок скорости × HOCKEY_CARRY_SPEED_MULT. Защитник
## догоняет ведущего шайбу и встаёт между ним и воротами (решено 22.10, BALANCE_2210.md: без этого боты забивали с вбрасывания за 3–5 с).
func _hockey_carry() -> void:
	if not _hockey_on or ball == null:
		return
	for d in dolls():
		var dd := d as Doll
		var carry := is_instance_valid(ball.last_touch) and ball.last_touch == dd and ball.since_touch() < Tuning.HOCKEY_CARRY_S
		dd.speed_cap_mult = Tuning.HOCKEY_CARRY_SPEED_MULT if carry else 1.0


## Расстановка на новый ввод после гола: куклы — заново на своих точках (keeps_damage — какими были, иначе целые), мяч — на точку
## ввода, короткий отсчёт.
func _kickoff() -> void:
	_respawns.clear()
	_save_team = -1
	_save_by = null
	_high_s = 0.0
	for d in dolls():
		_bank_stats(d as Doll)
		_respawn_as_is(d as Doll)
	for d in dolls():
		(d as Doll).control_enabled = false
	_place_ball()
	play_state = "kickoff"
	_set_phase(Phase.COUNTDOWN)
	_countdown_left = kickoff_s
	_countdown_shown = -1
	for d in dolls():
		hp_changed.emit(d, (d as Doll).hp, (d as Doll).max_hp)
	kickoff.emit(serve_team)
	if kickoff_s <= 0.0:
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
				time_left.emit(time_left_s())
				_check_score()
				_hockey_carry()
				_hockey_saves()
				_hockey_high(delta)
				if play_state == "play":
					_tick_idle_ball()
					if phase == Phase.FIGHT and fight_time >= time_limit_s:
						_time_up()
					elif phase == Phase.SUDDEN_DEATH and fight_time >= hard_timeout_s:
						_finish("timeout")
			elif play_state == "goal":
				_goal_t -= delta
				if _goal_t <= 0.0:
					_after_goal()
			elif play_state == "save":   # ХОККЕЙ: вратарь накрыл шайбу — пауза, потом вбрасывание у него
				_goal_t -= delta
				if _goal_t <= 0.0:
					serve_team = _save_team
					_kickoff()
	if ball != null:
		_ball_prev = ball.pos2()


## Основное время вышло: ведущий победил, при равном счёте — золотой гол.
func _time_up() -> void:
	if int(score[0]) != int(score[1]):
		_finish("timeout")
		return
	golden = true
	sd_step = 0
	_set_phase(Phase.SUDDEN_DEATH)
	announce.emit(tr("GOLDEN GOAL"), ANNOUNCE_COLORS["sudden_death"], "sudden_death")


func knockback_mult() -> float:
	return 1.0


func stability_mult() -> float:
	return 1.0


# --- ХОККЕЙ: вратарская и сейв (правила 23.10, HOCKEY.md) ---

## Точка p во вратарской команды team (у её ворот: команда 0 защищает левые, x < 0).
static func in_crease(p: Vector2, team: int) -> bool:
	var gx := float(Tuning.SPORTS["hockey"]["goal_x"])
	return p.x * -attack_dir(team) > gx - Tuning.HOCKEY_CREASE_M and p.y < Tuning.HOCKEY_CREASE_H


## Касание шайбы куклой (SportBall.touched, тело или клюшка): шайба во вратарской команды этой куклы — сейв в ближайшем тике
## матча (заморозка тела — не из сигнала физики).
func _on_puck_touched(d: Doll) -> void:
	if not _hockey_on or play_state != "play" or ball == null or ball.freeze or not is_instance_valid(d):
		return
	if in_crease(ball.pos2(), team_of(d)):
		_save_by = d


## Сейв: шайба во вратарской команды касается её куклы — новое касание (сигнал) или тело / клюшка, которые уже прижаты к шайбе
## (SportBall.touched не повторяется, пока контакт не прервётся: вратарь, заехавший вместе с шайбой, иначе завозил её в ворота).
func _hockey_saves() -> void:
	if not _hockey_on or play_state != "play" or ball == null or ball.freeze:
		_save_by = null
		return
	var d := _save_by
	_save_by = null
	if d == null or not is_instance_valid(d) or not d.alive:
		d = _crease_contact()
	if d != null and in_crease(ball.pos2(), team_of(d)):
		_save(d)


## Кукла-хозяин вратарской, где шайба, чьё тело или клюшка сейчас касается шайбы; нет — null.
func _crease_contact() -> Doll:
	var p := ball.pos2()
	var team := 0 if in_crease(p, 0) else (1 if in_crease(p, 1) else -1)
	if team < 0:
		return null
	for body in ball.get_colliding_bodies():
		var d := SportBall.doll_of(body)
		var w := body as Weapon
		if d == null and w != null and w.is_held() and is_instance_valid(w.holder):
			var hd: Variant = w.holder.get("doll")
			if is_instance_valid(hd) and hd is Doll:
				d = hd
		if d != null and d.alive and team_of(d) == team:
			return d
	return null


## Сейв: шайба замирает перед вратарём (над льдом, к полю от него), пауза HOCKEY_SAVE_HOLD_S (часы стоят), потом вбрасывание на
## половине вратаря (serve_team = его команда): роли меняются — теперь он в атаке, а нападавший успевает домой.
func _save(keeper: Doll) -> void:
	var team := team_of(keeper)
	var c := keeper.centre_of_mass()
	var gx := float(rules()["goal_x"])
	var x := clampf(c.x + attack_dir(team) * 0.8, -gx + 0.4, gx - 0.4)
	var y := clampf(c.y + 0.5, 0.5, 2.0)
	_whistle(team, Vector3(x, y, 0.0))
	ball.last_touch = keeper
	saves.append({"t": snappedf(fight_time, 0.01), "team": team, "keeper": keeper.player_index, "score": score.duplicate()})
	puck_saved.emit(team, keeper)
	announce.emit(tr("СЕЙВ!"), SAVE_COLOUR, "countdown")


## Свисток (сейв, шайба вне игры): шайба замирает в точке at, часы стоят HOCKEY_SAVE_HOLD_S (play_state "save"), потом вбрасывание
## на половине команды team (serve_team).
func _whistle(team: int, at: Vector3) -> void:
	_save_team = team
	play_state = "save"
	_goal_t = Tuning.HOCKEY_SAVE_HOLD_S
	ball.freeze = true
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.global_transform = Transform3D(Basis.IDENTITY, at)
	ball.reset_physics_interpolation()
	_ball_prev = ball.pos2()


## Шайба вне игры (правила 23.10): выше HOCKEY_HIGH_Y дольше HOCKEY_HIGH_S подряд (кукла катала её по потолку, бот соперника ждал в
## воротах — матч стоял минуту) — свисток, вбрасывание на половине команды, которая её не трогала последней.
func _hockey_high(delta: float) -> void:
	if not _hockey_on or play_state != "play" or ball == null or ball.freeze:
		_high_s = 0.0
		return
	_high_s = _high_s + delta if ball.pos2().y > Tuning.HOCKEY_HIGH_Y else 0.0
	if _high_s < Tuning.HOCKEY_HIGH_S:
		return
	_high_s = 0.0
	var lt := ball.last_touch
	var team := 1 - team_of(lt) if lt != null and is_instance_valid(lt) else serve_team
	high_whistles += 1
	_whistle(team, ball.global_position)
	announce.emit(tr("ШАЙБА ВНЕ ИГРЫ"), SAVE_COLOUR, "countdown")


## Пауза сейва: сколько ещё (0 — не сейв). Для ботов и HUD.
func save_hold_s() -> float:
	return _goal_t if play_state == "save" else 0.0


## Чей вратарь держит шайбу (−1 — никто).
func save_team() -> int:
	return _save_team if play_state == "save" else -1


# --- счёт ---

## Команда, забившая в этом тике, или −1. Мяч — по центру (ball.pos2()), прошлый тик — _ball_prev.
func scoring_team() -> int:
	if ball == null or ball.freeze:
		return -1
	var p := ball.pos2()
	var r: Dictionary = rules()
	var side := 0.0
	match sport:
		"football":
			if absf(p.x) > float(r["goal_x"]) + Tuning.SPORT_BALL_RADIUS * 0.5 and p.y < float(r["goal_h"]):
				side = signf(p.x)
		"basketball":
			var hy := float(r["hoop_y"])
			if _ball_prev.y >= hy and p.y < hy and absf(absf(p.x) - float(r["hoop_x"])) < float(r["hoop_r"]) - 0.08:
				side = signf(p.x)
		"volleyball":
			if p.y <= Tuning.SPORT_BALL_RADIUS + 0.07 and absf(p.x) > 0.2:
				side = signf(p.x)
		"hockey":
			# ХОККЕЙ (HOCKEY.md): шайба целиком пересекла линию ворот в этом тике ниже перекладины
			var line := float(r["goal_x"]) + Tuning.HOCKEY_PUCK_R
			if absf(p.x) > line and absf(_ball_prev.x) <= line and p.y < float(r["goal_h"]):
				side = signf(p.x)
	if side == 0.0:
		return -1
	return 0 if side > 0.0 else 1


func _check_score() -> void:
	var team := scoring_team()
	if team >= 0:
		_on_goal(team)


func _on_goal(team: int) -> void:
	score[team] = int(score[team]) + 1
	var scorer: Doll = ball.last_touch if ball != null and is_instance_valid(ball.last_touch) else null
	var own := scorer != null and team_of(scorer) != team
	goals.append({"t": snappedf(fight_time, 0.01), "team": team, "scorer": scorer.player_index if scorer != null else -1,
		"own_goal": own, "sport": sport, "score": score.duplicate()})
	serve_team = 1 - team
	play_state = "goal"
	_goal_t = Tuning.SPORT_GOAL_PAUSE_S
	score_changed.emit(score.duplicate())
	goal_scored.emit(team, scorer, own)
	announce.emit(goal_word(), GOAL_COLOUR, "fight")
	_show_score()
	if feel_enabled and ball != null:
		_camera_fx(30.0, ball.global_position)
		if FxPreset.time_fx():
			_time_effect(Tuning.SPORT_GOAL_SLOWMO, Tuning.SPORT_GOAL_SLOWMO_S)


func goal_word() -> String:
	match sport:
		"basketball":
			return tr("BASKET!")
		"volleyball":
			return tr("POINT!")
	return tr("GOAL!")


func _show_score() -> void:
	var a := _arena()
	if a != null and a.has_method("set_score"):
		a.call("set_score", int(score[0]), int(score[1]))


func _after_goal() -> void:
	if golden or int(score[0]) >= goals_to_win or int(score[1]) >= goals_to_win:
		_finish("goals")
	else:
		_kickoff()


## Страховки «мяч вне игры»: лежит без касаний дольше SPORT_BALL_IDLE_S (оба отошли) — подброс к центру; зажат в углу у пола
## дольше SPORT_BALL_CORNER_S (куклы сидят на нём, касания идут) — выброс из угла. В футболе угол у пола — это ворота (гол раньше).
func _tick_idle_ball() -> void:
	if ball == null:
		return
	var p := ball.pos2()
	var cornered := absf(p.x) > Tuning.SPORT_FIELD_HALF_W - 1.3 and p.y < 1.3 and sport != "football" and sport != "hockey"
	_corner_s = _corner_s + get_physics_process_delta_time() if cornered else 0.0
	if _corner_s >= Tuning.SPORT_BALL_CORNER_S:
		_corner_s = 0.0
		_rescue_ball(Vector3(-signf(p.x) * 5.0, 7.0, 0.0))
		return
	if ball.untouched_s < Tuning.SPORT_BALL_IDLE_S or ball.linear_velocity.length() > 0.6:
		return
	_rescue_ball(Vector3((-signf(p.x) if absf(p.x) > 0.5 else 0.0) * 2.5, 5.0, 0.0))


func _rescue_ball(velocity: Vector3) -> void:
	ball.untouched_s = 0.0
	ball_rescues += 1
	ball.linear_velocity = velocity


# --- нокаут: «удаление» ---

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
	_respawns.append([victim, ko_respawn_s()])   # ХОККЕЙ: свой срок (ko_respawn_s)


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
			var nd := _respawn_as_is(d as Doll)
			nd.control_enabled = play_state == "play" or play_state == "goal" or play_state == "save"
			hp_changed.emit(nd, nd.hp, nd.max_hp)


## Куклы между розыгрышами не чинятся (автор 06.10: «между матчами не чиним это, а оставляем как есть»): Tuning.SPORT_KEEP_DAMAGE
## и идёт режим, в котором детали отрываются («Запас из деталей» или «Прочность суставов»).
func keeps_damage() -> bool:
	return Tuning.SPORT_KEEP_DAMAGE and (PartHp.on or JointBreak.on)


## Пересоздать куклу на её точке. keeps_damage(): оторванное не отрастает (Match.respawn_doll keep_lost); живая кукла (расстановка
## после гола) сохраняет запас и износ суставов; после нокаута — полный запас того, что осталось, голова на месте (её отрыв и есть KO).
func _respawn_as_is(old: Doll) -> Doll:
	var keep := keeps_damage()
	var was_alive := old.alive
	var hp_left := old.hp
	var wear: Dictionary = old.joint_hp.duplicate()
	var d := respawn_doll(old, keep)
	if keep and was_alive:
		d.hp = clampf(hp_left, 1.0, d.max_hp)
		for n in wear:
			if d.joint_hp.has(n):
				d.joint_hp[n] = minf(float(wear[n]), float(d.joint_hp_max[n]))
	return d


# --- итоги ---

func _bank_stats(d: Doll) -> void:
	if d == null or not is_instance_valid(d):
		return
	_banked[d.player_index] = _merged_stats(d)


## Статистика куклы вместе с прошлыми розыгрышами.
func _merged_stats(d: Doll) -> Dictionary:
	var out: Dictionary = d.stats.duplicate()
	var old: Dictionary = _banked.get(d.player_index, {})
	for k in old:
		if not out.has(k) or not (out[k] is float or out[k] is int):
			continue
		out[k] = out[k] + old[k] if SUM_STATS.has(String(k)) else maxf(float(out[k]), float(old[k]))
	return out


## Сколько голов забила кукла-игрок (без голов в свои ворота).
func goals_of(player_index: int) -> int:
	var n := 0
	for g in goals:
		if int(g["scorer"]) == player_index and not bool(g["own_goal"]):
			n += 1
	return n


## Итоги: победитель и места — по счёту (а не по HP, как в бою); reason: "goals" | "timeout".
func build_results(reason: String = "timeout") -> Dictionary:
	var r := super.build_results(reason)
	var lead := -1
	if int(score[0]) != int(score[1]):
		lead = 0 if int(score[0]) > int(score[1]) else 1
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
	var winner: Doll = null
	for d in all:
		var won := lead >= 0 and team_of(d) == lead
		ranks.append(0 if lead < 0 or won else 1)
		if won and winner == null:
			winner = d
		stats[d] = _merged_stats(d as Doll)
		combo_score[d] = float(stats[d].get("combo_score", 0.0))
	var medals: Dictionary = r.get("medals", {})
	medals.erase("Winner")
	if winner != null:
		medals["Winner"] = winner
	r["places"] = all
	r["ranks"] = ranks
	r["stats"] = stats
	r["combo_score"] = combo_score
	r["medals"] = medals
	r["winner"] = winner
	r["draw"] = lead < 0
	r["ko_records"] = []       # нокаут в спорте — удаление, а не выбывание: в итогах никто не «KO»
	r["score"] = score.duplicate()
	r["sport"] = sport
	r["goals"] = goals.duplicate(true)
	return r
