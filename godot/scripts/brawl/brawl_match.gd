## Матч «Стенка на стенку 5×5» (docs/plan-demo/BRAWL.md; автор 08.10: «5×5 это другой режим»). Наследник Match: от него —
## регистрация кукол, DollCombat (удары телом, урон, отброс), эффекты и звук, отсчёт, Sudden Death (knockback_mult / set_stability),
## медали build_results. Своё:
##   • команды — чётность player_index (team_of): 0 — синие (P1 и боты 2, 4, 6, 8), 1 — красные (P2 и боты 3, 5, 7, 9). Doll.team
##     "brawl_N", team_damage_mult BRAWL_TEAM_DAMAGE_MULT (0 — свои не ранят и не оглушают, толкают полностью); группы brawl_0 /
##     brawl_1 (цели и разнос ботов); рубашка и обводка — цвет команды (Tuning.BRAWL_COLORS);
##   • точки появления — Tuning.BRAWL_SPAWN (синие слева, красные зеркально справа), слот = player_index / 2;
##   • раунд: без оружия, классов и возрождений; у команды не осталось живых — раунд другой (обе выбыли в одном тике — ничья, раунд
##     никому). Раунд не дольше BRAWL_ROUND_LIMIT_S: дальше Sudden Death по round_time (шаги SUDDEN_DEATH_STEP_S, как в Match), на
##     BRAWL_ROUND_HARD_S раунд — команде с большим суммарным запасом живых (hp_sum; равно — ничья);
##   • пауза BRAWL_ROUND_PAUSE_S, затем все заново на своих точках, отсчёт BRAWL_COUNTDOWN_S; матч — до wins_to_win побед → итоги
##     (match_over; build_results — winner_team, wins, rounds, tally, медали Match за весь матч: статистика кукол копится по раундам);
##   • эффекты удара и KO (тряска, стоп-кадр, надписи) — только с участием человека: драка ботов на другом краю Полигона не дёргает
##     кадр (как в гонке и стычке); крит-кино выключено.
## Фазы Match: COUNTDOWN — отсчёт раунда, FIGHT / SUDDEN_DEATH — раунд, OVER — итоги.
## play_state: countdown | play | round_end | over. Журналы для проб: rounds [{round, winner, reason, t, alive}], tally, kos.
class_name BrawlMatch
extends Match

signal round_started(round_i: int)
## winner — команда (0 / 1) или −1 (ничья); reason — "ko" (у другой команды никого) | "time" (лимит раунда, по запасу).
signal round_over(winner: int, round_i: int, reason: String)
signal wins_changed(wins: Array)

const GROUP_PREFIX := "brawl_"

@export var wins_to_win: int = Tuning.BRAWL_WINS_TO_WIN
@export var round_limit_s: float = Tuning.BRAWL_ROUND_LIMIT_S
@export var round_hard_s: float = Tuning.BRAWL_ROUND_HARD_S

var play_state := "idle"
var round_i := 0
## Время текущего раунда (с FIGHT!); fight_time — всего матча.
var round_time := 0.0
var wins := [0, 0]
var rounds: Array = []
var winner_team := -1
## player_index → {kos, kos_taken, damage} за матч.
var tally: Dictionary = {}
## Журнал нокаутов для проб: [{t, round, victim, attacker, team}].
var kos: Array = []
## Кукла «я» для HUD и камеры, когда людей нет (пробы: за P1 бот): player_index или −1.
var focus_index := -1
var _round_end_left := -1.0
var _first_round := true
var _stats_acc: Dictionary = {}     # player_index → stats за законченные раунды (медали за весь матч)
var _sfx: Node = null


func _ready() -> void:
	time_limit_s = 1.0e9      # часы Match не нужны: лимит у раунда (round_time)
	hard_timeout_s = 1.0e9
	super._ready()
	crit_enabled = false


# --- команды ---

static func team_of(d: Object) -> int:
	if d == null or not is_instance_valid(d):
		return -1
	var pi: Variant = d.get("player_index")
	return (int(pi) % 2) if pi != null else -1


static func team_group(team: int) -> String:
	return GROUP_PREFIX + str(team)


static func team_colour(team: int) -> Color:
	return Tuning.BRAWL_COLORS[clampi(team, 0, 1)]


static func team_name(team: int) -> String:
	return TranslationServer.translate("СИНИЕ") if team == 0 else TranslationServer.translate("КРАСНЫЕ")


static func doll_name(d: Object) -> String:
	if d == null or not is_instance_valid(d):
		return "—"
	return "P%d" % (int(d.get("player_index")) + 1)


static func _is_human(d: Object) -> bool:
	return d != null and is_instance_valid(d) and d is Doll and not (d as Doll).external_input


## Точка появления куклы player_index i: Tuning.BRAWL_SPAWN[i / 2], красные — зеркально по x.
static func spawn_for(i: int) -> Vector3:
	var pts: Array = Tuning.BRAWL_SPAWN
	var p: Vector2 = pts[(i / 2) % pts.size()]
	return Vector3(p.x * (-1.0 if i % 2 == 1 else 1.0), p.y, 0.0)


func spawn_point_for(d: Doll) -> Vector3:
	if d.player_index >= 0:
		return spawn_for(d.player_index)
	return super.spawn_point_for(d)


func team_dolls(team: int) -> Array:
	return dolls().filter(func(d: Variant) -> bool: return team_of(d) == team)


## Живые куклы команды.
func team_alive(team: int) -> Array:
	return alive_dolls().filter(func(d: Variant) -> bool: return team_of(d) == team)


## Суммарный запас живых команды.
func hp_sum(team: int) -> float:
	var s := 0.0
	for d in team_alive(team):
		s += maxf((d as Doll).hp, 0.0)
	return s


## Кукла «я»: человек (внешнего ввода нет), иначе кукла focus_index, иначе null.
func me() -> Doll:
	for d in dolls():
		if not (d as Doll).external_input:
			return d
	if focus_index >= 0:
		for d in dolls():
			if (d as Doll).player_index == focus_index:
				return d
	return null


func register(d: Doll) -> void:
	var fresh := not _order.has(d)
	super.register(d)
	if not fresh:
		return
	var t := team_of(d)
	d.team = GROUP_PREFIX + str(t)
	d.team_damage_mult = Tuning.BRAWL_TEAM_DAMAGE_MULT
	for g in [team_group(0), team_group(1)]:
		if d.is_in_group(g) and g != team_group(t):
			d.remove_from_group(g)
	if not d.is_in_group(team_group(t)):
		d.add_to_group(team_group(t))
	if d.is_node_ready():
		_dress(d)
	else:
		d.ready.connect(_dress.bind(d), CONNECT_ONE_SHOT)
	if not tally.has(d.player_index):
		tally[d.player_index] = {"kos": 0, "kos_taken": 0, "damage": 0.0}


## Цвет команды: рубашка (поверх цвета игрока по player_index — их всего четыре) и обводка.
func _dress(d: Doll) -> void:
	if not is_instance_valid(d):
		return
	var c := team_colour(team_of(d))
	d._recolor(d, Doll.SHIRT_MATERIAL, c)
	DollOutline.ensure(d, c)


# --- фазы ---

func begin() -> void:
	wins = [0, 0]
	rounds.clear()
	kos.clear()
	winner_team = -1
	_stats_acc.clear()
	for k in tally.keys():
		tally[k] = {"kos": 0, "kos_taken": 0, "damage": 0.0}
	round_i = 1
	round_time = 0.0
	_first_round = true
	_round_end_left = -1.0
	play_state = "countdown"
	super.begin()
	wins_changed.emit(wins.duplicate())
	round_started.emit(round_i)


## FIGHT! раунда: куклы управляемы, время раунда с нуля.
func _start_fight() -> void:
	var ft := fight_time
	super._start_fight()
	if not _first_round:
		fight_time = ft   # fight_time — всего матча; Match._start_fight обнуляет
	_first_round = false
	round_time = 0.0
	sd_step = -1
	play_state = "play"
	time_left.emit(time_left_s())


## Следующий раунд: все куклы заново на своих точках (фаза — COUNTDOWN до пересоздания: register при SUDDEN_DEATH ослабил бы
## новых), отсчёт BRAWL_COUNTDOWN_S.
func _next_round() -> void:
	round_i += 1
	_set_phase(Phase.COUNTDOWN)
	sd_step = -1
	ko_records.clear()
	_ko_order.clear()
	for d in dolls():
		respawn_doll(d)
	for d in dolls():
		(d as Doll).control_enabled = false
		var c := combat_of(d as Doll)
		if c != null:
			c.reset()
	play_state = "countdown"
	_countdown_left = Tuning.BRAWL_COUNTDOWN_S
	_countdown_shown = -1
	for d in dolls():
		hp_changed.emit(d, (d as Doll).hp, (d as Doll).max_hp)
	round_started.emit(round_i)
	if _countdown_left <= 0.0:
		_start_fight()


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
		Phase.FIGHT, Phase.SUDDEN_DEATH:
			fight_time += delta
			round_time += delta
			match play_state:
				"play":
					time_left.emit(time_left_s())
					if phase == Phase.FIGHT and round_time >= round_limit_s:
						_enter_sudden_death()
					if phase == Phase.SUDDEN_DEATH:
						var n := int(floor((round_time - round_limit_s) / maxf(Tuning.SUDDEN_DEATH_STEP_S, 0.1)))
						if n != sd_step:
							_apply_sd_step(n)
						if round_time >= round_hard_s:
							_round_by_hp()
				"round_end":
					_round_end_left -= delta
					if _round_end_left <= 0.0:
						if maxi(int(wins[0]), int(wins[1])) >= wins_to_win:
							_finish("wins")
						else:
							_next_round()


## Остаток раунда: до Sudden Death, в нём — до решения по запасу.
func time_left_s() -> float:
	match phase:
		Phase.COUNTDOWN:
			return round_limit_s
		Phase.FIGHT:
			return maxf(round_limit_s - round_time, 0.0)
		Phase.SUDDEN_DEATH:
			return maxf(round_hard_s - round_time, 0.0)
	return 0.0


## СТАЗИС: время ждёт игрока только в раунде.
func stasis_allowed() -> bool:
	return play_state == "play" and super.stasis_allowed()


func _check_over() -> void:
	pass   # конец раунда — _after_out, конец матча — пауза после раунда


func _finish(reason: String) -> void:
	if phase == Phase.OVER:
		return
	play_state = "over"
	if winner_team < 0:
		winner_team = -1 if int(wins[0]) == int(wins[1]) else (0 if int(wins[0]) > int(wins[1]) else 1)
	for d in dolls():
		var dd := d as Doll
		dd.control_enabled = false
		if _stats_acc.has(dd.player_index):
			dd.stats = (_stats_acc[dd.player_index] as Dictionary).duplicate()   # медали Match — за весь матч
	super._finish(reason)


# --- удары и KO ---

## Удар телом (зовёт DollCombat): с человеком — как в бою (тряска, стоп-кадр, надписи); боты между собой — только сигнал hit,
## Заряд за удар и тихий звук.
func on_hit(victim: Doll, attacker: Node, damage: float, kind: String, position: Vector3, combo_n: int, double_blow: bool, weapon_id: String, speed: float) -> void:
	if attacker is Doll and is_instance_valid(attacker) and damage > 0.0 and tally.has((attacker as Doll).player_index) and attacker != victim:
		(tally[(attacker as Doll).player_index] as Dictionary)["damage"] = float(tally[(attacker as Doll).player_index]["damage"]) + damage
	if _is_human(victim) or _is_human(attacker):
		super.on_hit(victim, attacker, damage, kind, position, combo_n, double_blow, weapon_id, speed)
		return
	hit.emit(victim, attacker, damage, kind, position)
	if victim == null or not is_instance_valid(victim) or damage <= 0.0 or kind == "environment":
		return
	Charge.apply_hit(make_hit_ctx(victim, attacker, damage, kind, position, combo_n, double_blow, weapon_id, speed))
	if feel_enabled:
		_play_at("hit_m" if damage >= 10.0 else "hit_l", -10.0 + minf(damage, 30.0) * 0.2, randf_range(0.95, 1.1), position)


## Удар о стену или пол без урона: эффекты — только у человека.
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


## KO как в Match (записи, статистика, сигнал ko), но замедление — короче и только с участием человека; конец раунда — _after_out.
func _on_doll_ko(attacker: Node, record: Dictionary, victim: Doll) -> void:
	if phase == Phase.OVER or play_state != "play":
		return
	var rec := record.duplicate()
	rec["victim"] = victim
	rec["attacker"] = attacker
	rec["match_time"] = fight_time
	rec["sd_step"] = sd_step
	rec["physics_frame"] = Engine.get_physics_frames()
	ko_records.append(rec)
	_ko_order.append(victim)
	if attacker is Doll and attacker != victim:
		var s: Dictionary = (attacker as Doll).stats
		s["kos"] = int(s["kos"]) + 1
	victim.stats["kos_taken"] = maxi(int(victim.stats["kos_taken"]), 1)
	hp_changed.emit(victim, 0.0, victim.max_hp)
	combo_changed.emit(victim, 0)
	announce.emit(tr("KO!"), ANNOUNCE_COLORS["ko"], "ko")
	ko.emit(victim, attacker, rec)
	(tally[victim.player_index] as Dictionary)["kos_taken"] = int(tally[victim.player_index]["kos_taken"]) + 1
	var ai := -1
	if attacker is Doll and is_instance_valid(attacker) and attacker != victim and tally.has((attacker as Doll).player_index):
		ai = (attacker as Doll).player_index
		(tally[ai] as Dictionary)["kos"] = int(tally[ai]["kos"]) + 1
	kos.append({"t": snappedf(round_time, 0.01), "round": round_i, "victim": victim.player_index, "attacker": ai, "team": team_of(victim)})
	if feel_enabled and (_is_human(victim) or _is_human(attacker)):
		_camera_fx(40.0, rec.get("position", victim.centre_of_mass()))
		_time_effect(Tuning.KO_SLOWMO_SCALE, Tuning.BRAWL_KO_SLOWMO_S)
	call_deferred("_after_out")


func _after_out() -> void:
	if not combat_active() or play_state != "play":
		return
	var a0 := team_alive(0).size()
	var a1 := team_alive(1).size()
	if a0 == 0 and a1 == 0:
		_round_won(-1, "ko")
	elif a0 == 0:
		_round_won(1, "ko")
	elif a1 == 0:
		_round_won(0, "ko")


## Лимит раунда вышел: раунд — команде с большим суммарным запасом живых (равно — ничья).
func _round_by_hp() -> void:
	var h0 := hp_sum(0)
	var h1 := hp_sum(1)
	_round_won(-1 if is_equal_approx(h0, h1) else (0 if h0 > h1 else 1), "time")


func _round_won(t: int, reason: String) -> void:
	play_state = "round_end"
	_round_end_left = Tuning.BRAWL_ROUND_PAUSE_S
	for d in dolls():
		var dd := d as Doll
		_stats_acc[dd.player_index] = _sum_stats(_stats_acc.get(dd.player_index, {}), dd.stats)
	if t >= 0:
		wins[t] = int(wins[t]) + 1
	rounds.append({"round": round_i, "winner": t, "reason": reason, "t": snappedf(round_time, 0.01),
		"alive": [team_alive(0).size(), team_alive(1).size()], "hp": [snappedf(hp_sum(0), 0.1), snappedf(hp_sum(1), 0.1)]})
	wins_changed.emit(wins.duplicate())
	round_over.emit(t, round_i, reason)
	if t >= 0:
		announce.emit(tr("%s БЕРУТ РАУНД") % team_name(t), team_colour(t).lightened(0.35), "round")
	else:
		announce.emit(tr("НИЧЬЯ"), Color.WHITE, "round")


static func _sum_stats(acc: Dictionary, s: Dictionary) -> Dictionary:
	var out := acc.duplicate()
	for k in s:
		var v: Variant = s[k]
		if v is float or v is int:
			if k == "hardest_hit" or k == "max_speed" or k == "combo_max":
				out[k] = maxf(float(out.get(k, 0.0)), float(v)) if v is float else maxi(int(out.get(k, 0)), int(v))
			else:
				out[k] = float(out.get(k, 0.0)) + float(v) if v is float else int(out.get(k, 0)) + int(v)
	return out


# --- итоги ---

## Итоги: базовые (статистика, медали за весь матч) + команда-победитель, счёт раундов, журнал, tally. places — сначала победившая
## команда (внутри — по нокаутам), winner — человек победившей команды, иначе её первая кукла; ничья — winner null.
func build_results(reason: String = "wins") -> Dictionary:
	var r := super.build_results(reason)
	var wt := winner_team
	if wt < 0 and reason == "wins":
		wt = -1 if int(wins[0]) == int(wins[1]) else (0 if int(wins[0]) > int(wins[1]) else 1)
	var all := dolls()
	all.sort_custom(func(a: Doll, b: Doll) -> bool:
		var ta := team_of(a)
		var tb := team_of(b)
		if ta != tb:
			if wt >= 0:
				return ta == wt
			return ta < tb
		var ka := int((tally.get(a.player_index, {}) as Dictionary).get("kos", 0))
		var kb := int((tally.get(b.player_index, {}) as Dictionary).get("kos", 0))
		if ka != kb:
			return ka > kb
		return a.player_index < b.player_index)
	var ranks: Array = []
	for i in all.size():
		ranks.append(0 if wt >= 0 and team_of(all[i]) == wt else (1 if wt >= 0 else 0))
	var winner: Doll = null
	if wt >= 0:
		for d in all:
			if team_of(d) == wt and (winner == null or (_is_human(d) and not _is_human(winner))):
				winner = d
	var medals: Dictionary = r.get("medals", {})
	medals.erase("Winner")
	medals.erase("Survivor")
	if winner != null:
		medals["Winner"] = winner
	r["places"] = all
	r["ranks"] = ranks
	r["winner"] = winner
	r["draw"] = wt < 0
	r["winner_team"] = wt
	r["medals"] = medals
	r["wins"] = wins.duplicate()
	r["rounds"] = rounds.duplicate(true)
	r["tally"] = tally.duplicate(true)
	r["kos"] = kos.duplicate(true)
	return r
