## Матч «Охота за головами» (docs/plan-demo/HEADHUNT.md; MODES_IDEAS.md Б4: «головы выбитых падают и лежат; принеси в свою корзину —
## очко»). Наследник Match: от него — регистрация кукол (DollCombat), удары с уроном, KO, отсчёт, надписи. Своё:
##   • команды: чётность player_index (team_of): 0 — синие (P1 и боты 2, 4), 1 — красные (P2 и боты 3, 5). Doll.team "headhunt_N",
##     team_damage_mult 0 — свои не ранят и не оглушают, толкают полностью; группы headhunt_0 / headhunt_1 (цели ботов, камера);
##     рубашка — цвет команды (Tuning.HEADHUNT_COLORS, Doll._recolor);
##   • KO (удар, пропасть): голова выбитого остаётся лежать (HeadCarry.extract — RigidBody3D в группе heads, meta owner_team), его
##     головы со спины рассыпаются (scatter), он возвращается через respawn_s на своей точке (Match.respawn_doll, arena.spawn_points()
##     по player_index — у Полигона чётные слева, нечётные справа), первые HEADHUNT_SPAWN_SHIELD_S урон не проходит;
##   • подбор — касание любой деталью (HeadCarry.tick), до HEADHUNT_CARRY_MAX на спине, тяга × HEADHUNT_CARRY_THRUST за голову;
##   • корзина (HeadBasket, группа head_basket, по team): носитель коснулся своей — deliver: чужая голова +1 команде, своя — возвращена
##     без очка; корзина после зачёта пуста (обчистить нечего — головы уже засчитаны);
##   • до score_to_win (HEADHUNT_SCORE_TO_WIN) или time_limit_s (HEADHUNT_TIME_S): больше очков побеждает, поровну — ничья.
##     Sudden Death и «последний живой» базового Match выключены;
##   • эффекты удара и KO (тряска, стоп-кадр, надписи) — только если участвует человек (как в гонке и стычке); крит-кино выключено.
## Сигналы для HUD, площадки и проб: score_changed, head_picked, heads_delivered, respawn_queued, doll_respawned + унаследованные.
## Журналы для проб: deliveries [{t, pi, team, scored, returned}], kos [{t, victim, attacker, team}].
class_name HeadhuntMatch
extends Match

signal score_changed(score: Array)
signal head_picked(head: RigidBody3D, doll: Doll)
signal heads_delivered(doll: Doll, team: int, scored: int, returned: int)
signal respawn_queued(victim: Doll, seconds: float)
signal doll_respawned(doll: Doll)

const GROUP_PREFIX := "headhunt_"

@export var score_to_win: int = Tuning.HEADHUNT_SCORE_TO_WIN
@export var respawn_s: float = Tuning.HEADHUNT_RESPAWN_S

var score: Array = [0, 0]
## idle | countdown | play | over
var play_state := "idle"
var winner_team := -1
## player_index → {heads (чужих сдал), returned (своих вернул), kos, kos_taken}
var tally: Dictionary = {}
var deliveries: Array = []
var kos: Array = []
var carry: HeadCarry
var _respawns: Array = []         # [[Doll, осталось с]]
var _sfx: Node = null


func _ready() -> void:
	time_limit_s = Tuning.HEADHUNT_TIME_S
	hard_timeout_s = Tuning.HEADHUNT_TIME_S
	super._ready()
	crit_enabled = false
	carry = HeadCarry.new()
	carry.name = "HeadCarry"
	add_child(carry)
	carry.bind(self)


# --- команды ---

static func team_of(d: Object) -> int:
	if d == null or not is_instance_valid(d):
		return -1
	return posmod(int(d.get("player_index")), 2)


static func team_group(team: int) -> String:
	return GROUP_PREFIX + str(team)


static func team_colour(team: int) -> Color:
	return Tuning.HEADHUNT_COLORS[clampi(team, 0, 1)]


static func team_name(team: int) -> String:
	return TranslationServer.translate("СИНИЕ") if team == 0 else TranslationServer.translate("КРАСНЫЕ")


static func doll_name(d: Object) -> String:
	if d == null or not is_instance_valid(d):
		return "—"
	return "P%d" % (int(d.get("player_index")) + 1)


static func _is_human(d: Object) -> bool:
	return d != null and is_instance_valid(d) and d is Doll and not (d as Doll).external_input


## Кукла, которой принадлежит тело (деталь — ребёнок Doll).
static func doll_of(body: Node) -> Doll:
	var n := body
	for _i in 4:
		if n == null:
			return null
		if n is Doll:
			return n
		n = n.get_parent()
	return null


func team_alive(team: int) -> Array:
	return alive_dolls().filter(func(d: Variant) -> bool: return team_of(d) == team)


func register(d: Doll) -> void:
	var fresh := not _order.has(d)
	super.register(d)
	if not fresh:
		return
	var t := team_of(d)
	d.team = GROUP_PREFIX + str(t)
	d.team_damage_mult = 0.0
	for g in [team_group(0), team_group(1)]:
		if d.is_in_group(g) and g != team_group(t):
			d.remove_from_group(g)
	d.add_to_group(team_group(t))
	if d.is_node_ready():
		_dress(d)
	else:
		d.ready.connect(_dress.bind(d), CONNECT_ONE_SHOT)
	if not tally.has(d.player_index):
		tally[d.player_index] = _fresh_tally()


static func _fresh_tally() -> Dictionary:
	return {"heads": 0, "returned": 0, "kos": 0, "kos_taken": 0}


func _dress(d: Doll) -> void:
	if is_instance_valid(d):
		d._recolor(d, Doll.SHIRT_MATERIAL, team_colour(team_of(d)))


## Корзина команды (HeadBasket в группе head_basket) или null.
func basket_of(team: int) -> HeadBasket:
	for b in get_tree().get_nodes_in_group(HeadBasket.GROUP):
		if b is HeadBasket and (b as HeadBasket).team == team:
			return b
	return null


# --- фазы ---

func begin() -> void:
	score = [0, 0]
	winner_team = -1
	deliveries.clear()
	kos.clear()
	_respawns.clear()
	for k in tally.keys():
		tally[k] = _fresh_tally()
	if carry != null:
		carry.clear()
	for b in get_tree().get_nodes_in_group(HeadBasket.GROUP):
		if b is HeadBasket:
			(b as HeadBasket).reset()
	play_state = "countdown"
	super.begin()
	score_changed.emit(score.duplicate())


func restart() -> void:
	_respawns.clear()
	if carry != null:
		carry.clear()
	super.restart()


func _start_fight() -> void:
	super._start_fight()
	play_state = "play"


func _finish(reason: String) -> void:
	if phase == Phase.OVER:
		return
	play_state = "over"
	_respawns.clear()
	if winner_team < 0 and int(score[0]) != int(score[1]):
		winner_team = 0 if int(score[0]) > int(score[1]) else 1
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
			if play_state == "play":
				carry.tick(delta)
			if play_state == "play" and fight_time >= time_limit_s:
				_finish("timeout")


# --- очки ---

func score_of_team(team: int) -> int:
	return int(score[clampi(team, 0, 1)])


## Носитель d коснулся своей корзины: чужие головы — +1 каждая, свои — возвращены без очка.
func deliver(d: Doll) -> void:
	if play_state != "play" or d == null or not is_instance_valid(d) or not d.alive:
		return
	var t := team_of(d)
	var teams: Array = carry.take_all(d)
	if teams.is_empty():
		return
	var scored := 0
	var returned := 0
	for ot in teams:
		if int(ot) == t:
			returned += 1
		else:
			scored += 1
	score[t] = int(score[t]) + scored
	var tl: Dictionary = tally.get(d.player_index, _fresh_tally())
	tl["heads"] = int(tl["heads"]) + scored
	tl["returned"] = int(tl["returned"]) + returned
	tally[d.player_index] = tl
	deliveries.append({"t": snappedf(fight_time, 0.01), "pi": d.player_index, "team": t, "scored": scored, "returned": returned,
		"score": score.duplicate()})
	var b := basket_of(t)
	if b != null:
		b.add(scored + returned)
	heads_delivered.emit(d, t, scored, returned)
	score_changed.emit(score.duplicate())
	if scored > 0:
		announce.emit(tr("%s +%d") % [team_name(t), scored], team_colour(t).lightened(0.35), "score")
		_deliver_sound(d, scored)
	if int(score[t]) >= score_to_win:
		winner_team = t
		call_deferred("_finish", "score")


func _deliver_sound(d: Doll, n: int) -> void:
	if not feel_enabled:
		return
	if _sfx == null or not is_instance_valid(_sfx):
		_sfx = get_tree().get_first_node_in_group(SfxDirector.GROUP)
		if _sfx == null:
			return
	if _is_human(d):
		_sfx.call("play_layer", "combo", 0.0, clampf(1.0 + 0.08 * float(n), 1.0, 1.5), SfxDirector.BUS_UI, 0.0)
		if int(score[team_of(d)]) >= score_to_win:
			_sfx.call("play_layer", "bell", 0.0, 1.0, SfxDirector.BUS_UI, 0.0)
	else:
		_sfx.call("play_layer", "callout", -3.0, 0.72 if team_of(d) == 1 else 0.9, SfxDirector.BUS_UI, 0.0)


# --- удары ---

## Удар с человеком — как в бою (тряска, стоп-кадр, надписи); боты между собой — только сигнал hit, Заряд и тихий звук.
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

func _check_over() -> void:
	pass


func _on_doll_ko(attacker: Node, record: Dictionary, victim: Doll) -> void:
	if phase == Phase.OVER or play_state != "play":
		return
	var feel := feel_enabled
	var human := _is_human(victim) or _is_human(attacker)
	feel_enabled = false
	super._on_doll_ko(attacker, record, victim)
	feel_enabled = feel
	var vt := team_of(victim)
	var killer: Doll = attacker as Doll if attacker is Doll and is_instance_valid(attacker) and attacker != victim \
		and team_of(attacker) != vt else null
	(tally[victim.player_index] as Dictionary)["kos_taken"] = int(tally[victim.player_index]["kos_taken"]) + 1
	if killer != null and tally.has(killer.player_index):
		(tally[killer.player_index] as Dictionary)["kos"] = int(tally[killer.player_index]["kos"]) + 1
	kos.append({"t": snappedf(fight_time, 0.01), "victim": victim.player_index, "attacker": killer.player_index if killer != null else -1,
		"team": vt, "kind": String(record.get("kind", ""))})
	# головы со спины — на пол, своя — тоже (Doll.knock_out уже порвал суставы; вынос из куклы — после цепочки удара)
	carry.scatter(victim)
	carry.call_deferred("extract", victim, vt)
	if feel and human:
		_camera_fx(30.0, record.get("position", victim.centre_of_mass()))
		if FxPreset.time_fx():
			_time_effect(Tuning.KO_SLOWMO_SCALE, Tuning.HEADHUNT_KO_SLOWMO_S)
	_respawns.append([victim, respawn_s])
	respawn_queued.emit(victim, respawn_s)


## Секунды до возврата куклы (−1 — не ждёт).
func respawn_left(d: Doll) -> float:
	for e in _respawns:
		if e[0] == d:
			return float(e[1])
	return -1.0


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
			var nd := respawn_doll(d as Doll)
			nd.control_enabled = true
			nd.grace_until = maxf(nd.grace_until, Tuning.HEADHUNT_SPAWN_SHIELD_S)   # _time новой куклы ≈ 0
			hp_changed.emit(nd, nd.hp, nd.max_hp)
			doll_respawned.emit(nd)


# --- итоги ---

## Кукла «я» для HUD: человек с меньшим player_index, иначе null.
func me() -> Doll:
	var best: Doll = null
	for d in dolls():
		var dd := d as Doll
		if not dd.external_input and (best == null or dd.player_index < best.player_index):
			best = dd
	return best


func heads_of(d: Object) -> int:
	if d == null or not is_instance_valid(d):
		return 0
	return int((tally.get(int(d.get("player_index")), {}) as Dictionary).get("heads", 0))


## Итоги: базовые (статистика, медали) + места по команде-победителю и сданным головам, счёт, победитель (человек победившей команды,
## иначе её первый), ничья при равном счёте, таблица tally.
func build_results(reason: String = "timeout") -> Dictionary:
	var r := super.build_results(reason)
	var all := dolls()
	var wt := winner_team
	all.sort_custom(func(a: Doll, b: Doll) -> bool:
		var ta := team_of(a)
		var tb := team_of(b)
		if ta != tb and wt >= 0:
			return ta == wt
		var ha := heads_of(a)
		var hb := heads_of(b)
		if ha != hb:
			return ha > hb
		return a.player_index < b.player_index)
	var ranks: Array = []
	for i in all.size():
		ranks.append(i)
	var winner: Doll = null
	if wt >= 0:
		for d in all:
			if team_of(d) == wt and (winner == null or (_is_human(d) and not _is_human(winner))):
				winner = d
	r["places"] = all
	r["ranks"] = ranks
	r["winner"] = winner
	r["draw"] = wt < 0
	var medals: Dictionary = r.get("medals", {})
	medals.erase("Winner")
	medals.erase("Survivor")
	if winner != null:
		medals["Winner"] = winner
	r["medals"] = medals
	r["score"] = score.duplicate()
	r["winner_team"] = wt
	r["tally"] = tally.duplicate(true)
	r["deliveries"] = deliveries.duplicate(true)
	r["kos_log"] = kos.duplicate(true)
	r["score_to_win"] = score_to_win
	return r
