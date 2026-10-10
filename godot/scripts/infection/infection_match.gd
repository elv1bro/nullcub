## Матч «Заражение» (docs/plan-demo/INFECTION.md, MODES_IDEAS.md Б5: «один заражённый (зелёный), коснулся — заразил, тот играет за
## заражённых; заражённые быстрее, но без рук»). Наследник Match: от него — регистрация кукол, DollCombat (удары и отброс), эффекты
## и звук, отсчёт. Своё:
##   • урона нет: каждой кукле Doll.incoming_mult = 0 (как в бомбе) — удары только толкают; толчок видно — вспышка с пылью (on_hit);
##   • заражённые (infected: doll → true): в начале партии один случайный (first) — не тот же, что в прошлой партии. Каждый тик —
##     касание любой детали заражённого любой детали живого здорового (опрос get_colliding_bodies, contact_monitor на всех деталях)
##     → тот заражён сразу: infect() — перекраска в INFECTION_COLOR, тяга и предел скорости × INFECTION_ZOMBIE_*, рука мышью
##     (ArmAssist) снимается, Заряд заперт (рывка и раскрутки нет — doll.gd не правится: charge = 0 + charge_locked каждый тик),
##     группа ZOMBIE_GROUP (стрелка за кадром), сигнал infected, диктор «ЗАРАЖЁН: P3». Свежезаражённый сам заражает не раньше
##     INFECTION_TOUCH_GAP_S;
##   • партия INFECTION_ROUND_S: все заражены раньше — партия заражённым, очко первому заражённому; время вышло — партия здоровым,
##     очко каждому живому здоровому. Пауза INFECTION_ROUND_PAUSE_S; до rounds_n партий — следующая (все куклы заново на точках,
##     отсчёт INFECTION_COUNTDOWN_S), иначе итоги (match_over; build_results — места по очкам);
##   • последние INFECTION_PULSE_S партии — сигнал pulsed(urgency) всё чаще (PULSE_SLOW_S → PULSE_FAST_S): мембрана и писк (площадка).
## Фазы Match: COUNTDOWN — отсчёт партии, FIGHT — партия (Sudden Death и часов Match нет), OVER — итоги.
## play_state: countdown | play | round_end | over. Журналы для проб: infections, rounds, pulses (времена пульса текущей партии).
class_name InfectionMatch
extends Match

signal infected(victim: Doll, by: Doll)          # by null — первый заражённый партии
signal pulsed(urgency: float)
signal round_started(round_i: int)
signal round_over(side: String, round_i: int)    # side: "zombies" | "healthy"

const ZOMBIE_GROUP := "infection_zombie"
const HEALTHY_GROUP := "infection_healthy"
const SHOVE_FX_MIN_SPEED := 2.5      # м/с: удар куклы о куклу слабее — без вспышки

@export var rounds_n: int = Tuning.INFECTION_ROUNDS
@export var round_s: float = Tuning.INFECTION_ROUND_S
## Сид случайностей (кто первый заражённый); 0 — каждый раз новый.
@export var rng_seed := 0

var play_state := "idle"
var round_i := 0
## Время текущей партии (с FIGHT!); fight_time — всего матча.
var round_time := 0.0
var scores: Dictionary = {}        # player_index → очков
var infected: Dictionary = {}      # Doll → true
var first: Doll = null             # первый заражённый этой партии
var first_i := -1                  # его player_index (прошлой партии — last_first_i)
var last_first_i := -1
var infections: Array = []         # [{t, round, from, to}] (первый заражённый партии — from -1)
var rounds: Array = []             # [{round, first, side, t, infections, survivors: [player_index]}]
var pulses: Array = []             # round_time пульсов текущей партии
var infections_round := 0
var _survived: Dictionary = {}     # player_index → партий дожил (stats куклы не годятся: respawn_doll делает новую)
var _infected_at: Dictionary = {}  # Doll → round_time заражения
var _pulse_left := 0.0
var _round_end_left := -1.0
var _rng := RandomNumberGenerator.new()
var _first_round := true
var _restart_pending := false
var _in_tick := false


func _ready() -> void:
	time_limit_s = 1.0e9      # часы партии свои (round_time), Sudden Death не нужен
	hard_timeout_s = 1.0e9
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	super._ready()
	crit_enabled = false      # урона нет — крит-кино не к чему


# --- куклы ---

func register(d: Doll) -> void:
	super.register(d)
	d.incoming_mult = 0.0
	_paint_healthy(d)
	d.add_to_group(HEALTHY_GROUP)
	for b in d.parts.values():
		var rb := b as RigidBody3D
		if rb != null:
			rb.contact_monitor = true   # касание любой деталью (DollCombat слушает не все)
			rb.max_contacts_reported = maxi(rb.max_contacts_reported, 4)


## Точки появления: Tuning.INFECTION_SPAWN по player_index (у купола их четыре).
func spawn_point_for(d: Doll) -> Vector3:
	var pts: Array = Tuning.INFECTION_SPAWN
	if d.player_index >= 0 and d.player_index < pts.size():
		var p: Vector2 = pts[d.player_index]
		return Vector3(p.x, p.y, 0.0)
	return super.spawn_point_for(d)


static func colour_of(i: int) -> Color:
	return Tuning.INFECTION_COLORS[posmod(i, Tuning.INFECTION_COLORS.size())]


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


func is_infected(d: Object) -> bool:
	return d != null and infected.has(d)


func score_of(d: Object) -> int:
	if d == null or not is_instance_valid(d):
		return 0
	return int(scores.get(int(d.get("player_index")), 0))


func zombies() -> Array:
	var out: Array = []
	for d in alive_dolls():
		if infected.has(d):
			out.append(d)
	return out


func healthy() -> Array:
	var out: Array = []
	for d in alive_dolls():
		if not infected.has(d):
			out.append(d)
	return out


## Осталось партии, с (в отсчёте — вся партия).
func time_left() -> float:
	return maxf(round_s - round_time, 0.0) if play_state == "play" else (round_s if play_state == "countdown" else 0.0)


## Цвет куклы сейчас: заражённый — зелёный, здоровый — свой.
func doll_colour(d: Doll) -> Color:
	return Tuning.INFECTION_COLOR if is_infected(d) else colour_of(d.player_index)


func _paint_healthy(d: Doll) -> void:
	var c := colour_of(d.player_index)
	if c != Tuning.PLAYER_COLORS[clampi(d.player_index, 0, 3)]:
		d._recolor(d, Doll.SHIRT_MATERIAL, c)   # пятый и дальше: у куклы цветов четыре (PLAYER_COLORS)


# --- фазы ---

func begin() -> void:
	scores.clear()
	_survived.clear()
	rounds.clear()
	infections.clear()
	round_i = 1
	round_time = 0.0
	_first_round = true
	_clear_infection()
	play_state = "countdown"
	super.begin()
	_pick_first()
	round_started.emit(round_i)


## R / «Заново»: куклы пересоздаются только в своём тике (как BombMatch.restart — иначе мембрана купола ловит вынутые детали).
func restart() -> void:
	if not _in_tick:
		_restart_pending = true
		return
	_restart_pending = false
	_clear_infection()
	super.restart()


## FIGHT! партии: куклы управляемы, заражённый уже выбран (в отсчёте).
func _start_fight() -> void:
	for d in dolls():
		var dd := d as Doll
		dd.reset_for_match()
		dd.control_enabled = true
		var c := combat_of(dd)
		if c != null:
			c.reset()
	if _first_round:
		fight_time = 0.0
	_first_round = false
	round_time = 0.0
	pulses.clear()
	_pulse_left = 0.0
	infections_round = 0
	_set_phase(Phase.FIGHT)
	play_state = "play"
	announce.emit(tr("FIGHT!"), ANNOUNCE_COLORS["fight"], "fight")
	if first == null or not is_instance_valid(first):
		_pick_first()


## Следующая партия: все куклы заново на своих точках, новый первый заражённый, отсчёт.
func _next_round() -> void:
	round_i += 1
	_clear_infection()
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
	_set_phase(Phase.COUNTDOWN)
	_countdown_left = Tuning.INFECTION_COUNTDOWN_S
	_countdown_shown = -1
	_pick_first()
	round_started.emit(round_i)
	if _countdown_left <= 0.0:
		_start_fight()


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
	_lock_zombie_charge()
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
			match play_state:
				"play":
					round_time += delta
					_tick_round(delta)
				"round_end":
					_round_end_left -= delta
					if _round_end_left <= 0.0:
						if round_i >= rounds_n:
							_finish("rounds")
						else:
							_next_round()


## СТАЗИС: время ждёт игрока только в партии (отсчёт и пауза после партии идут сами).
func stasis_allowed() -> bool:
	return play_state == "play" and super.stasis_allowed()


func _check_over() -> void:
	pass   # конец партии и матча — _after_out / _round_won


func _finish(reason: String) -> void:
	play_state = "over"
	super._finish(reason)


# --- заражение ---

## Первый заражённый партии: случайный живой, не тот же, что в прошлой партии (если есть выбор).
func _pick_first() -> void:
	var alive := alive_dolls()
	if alive.is_empty():
		return
	var pool: Array = []
	for d in alive:
		if (d as Doll).player_index != last_first_i:
			pool.append(d)
	if pool.is_empty():
		pool = alive
	var d: Doll = pool[_rng.randi() % pool.size()]
	first = d
	first_i = d.player_index
	last_first_i = first_i
	infect(d, null)


## Заразить куклу d (касание заражённого by; первый — by null; пробы зовут напрямую).
func infect(d: Doll, by: Doll) -> void:
	if d == null or not is_instance_valid(d) or infected.has(d):
		return
	infected[d] = true
	_infected_at[d] = round_time
	d.thrust_mult = Tuning.INFECTION_ZOMBIE_THRUST_MULT
	d.speed_cap_mult = Tuning.INFECTION_ZOMBIE_SPEED_MULT
	d._recolor(d, Doll.SHIRT_MATERIAL, Tuning.INFECTION_COLOR)
	for c in d.get_children():
		if c is ArmAssist:   # заражённый — без руки мышью
			(c as ArmAssist).drop_all()
			d.remove_child(c)
			c.queue_free()
	d.charge = 0.0
	d.charge_locked = true
	if d.is_in_group(HEALTHY_GROUP):
		d.remove_from_group(HEALTHY_GROUP)
	d.add_to_group(ZOMBIE_GROUP)
	if by != null:
		infections_round += 1
		infections.append({"t": snappedf(round_time, 0.001), "round": round_i, "from": by.player_index, "to": d.player_index})
		announce.emit(tr("ЗАРАЖЁН: %s") % doll_name(d), Tuning.INFECTION_COLOR, "infect")
	else:
		infections.append({"t": snappedf(round_time, 0.001), "round": round_i, "from": -1, "to": d.player_index})
		announce.emit(tr("ЗАРАЖЁН: %s") % doll_name(d), Tuning.INFECTION_COLOR, "infect")
	infected.emit(d, by)
	if by != null and play_state == "play" and healthy().is_empty():
		_round_won("zombies")


## Заражённые без рывка и раскрутки: Заряд пуст и заперт каждый тик (doll.gd не правится; charge_locked сам снимается только при
## Заряде ≥ CHARGE_RESTART, которого не будет).
func _lock_zombie_charge() -> void:
	for d in infected.keys():
		var dd := d as Doll
		if dd != null and is_instance_valid(dd):
			dd.charge = 0.0
			dd.charge_locked = true


func _clear_infection() -> void:
	infected.clear()
	_infected_at.clear()
	first = null
	first_i = -1
	for d in dolls():
		var dd := d as Doll
		if dd.is_in_group(ZOMBIE_GROUP):
			dd.remove_from_group(ZOMBIE_GROUP)
		if not dd.is_in_group(HEALTHY_GROUP):
			dd.add_to_group(HEALTHY_GROUP)


func _tick_round(delta: float) -> void:
	if round_time >= round_s:
		_round_won("healthy")
		return
	var left := round_s - round_time
	if left <= Tuning.INFECTION_PULSE_S:
		_pulse_left -= delta
		if _pulse_left <= 0.0:
			var u := clampf(1.0 - left / Tuning.INFECTION_PULSE_S, 0.0, 1.0)
			pulses.append(snappedf(round_time, 0.001))
			pulsed.emit(u)
			_pulse_left = pulse_interval(u)
	_check_touch()


## Пауза до следующего пульса при доле прошедших последних секунд k (0..1).
static func pulse_interval(k: float) -> float:
	return lerpf(Tuning.INFECTION_PULSE_SLOW_S, Tuning.INFECTION_PULSE_FAST_S, clampf(k, 0.0, 1.0))


## Касание: любая деталь заражённого (не свежее INFECTION_TOUCH_GAP_S) касается детали живого здорового → заражение.
func _check_touch() -> void:
	var hits: Array = []   # [жертва, заражённый]
	for z in zombies():
		var zd := z as Doll
		if round_time - float(_infected_at.get(zd, -100.0)) < Tuning.INFECTION_TOUCH_GAP_S:
			continue
		for b in zd.parts.values():
			var rb := b as RigidBody3D
			if rb == null or not is_instance_valid(rb) or not rb.contact_monitor:
				continue
			for o in rb.get_colliding_bodies():
				var d := doll_of(o)
				if d == null or d == zd or not d.alive or not _order.has(d) or infected.has(d):
					continue
				var dup := false
				for h in hits:
					if h[0] == d:
						dup = true
						break
				if not dup:
					hits.append([d, zd])
	for h in hits:
		if play_state != "play":
			return
		infect(h[0], h[1])


## Удар куклы о куклу: урона нет, но толчок видно — вспышка и пыль ImpactFx (как в бомбе).
func on_hit(victim: Doll, attacker: Node, damage: float, kind: String, position: Vector3, combo_n: int, double_blow: bool, weapon_id: String, speed: float) -> void:
	super.on_hit(victim, attacker, damage, kind, position, combo_n, double_blow, weapon_id, speed)
	if damage <= 0.0 and kind != "environment" and speed >= SHOVE_FX_MIN_SPEED:
		ImpactFx.spawn_impact(self, position, Vector3.UP, clampf(2.0 + speed * 0.7, 3.0, 10.0), kind, FxMaterial.RUBBER)


# --- выбывание и партия ---

## KO (страховка: урона нет, но кукла может выпасть из арены — body_fell): записи как в Match, без КО-кино; здоровых не осталось —
## партия заражённым.
func _on_doll_ko(attacker: Node, record: Dictionary, victim: Doll) -> void:
	if phase == Phase.OVER:
		return
	var rec := record.duplicate()
	rec["victim"] = victim
	rec["attacker"] = attacker
	rec["match_time"] = fight_time
	rec["sd_step"] = sd_step
	rec["physics_frame"] = Engine.get_physics_frames()
	ko_records.append(rec)
	_ko_order.append(victim)
	victim.stats["kos_taken"] = maxi(int(victim.stats["kos_taken"]), 1)
	hp_changed.emit(victim, 0.0, victim.max_hp)
	announce.emit(tr("ВЫБЫЛ: %s") % doll_name(victim), ANNOUNCE_COLORS["ko"], "ko")
	ko.emit(victim, attacker, rec)
	_after_out()


func _after_out() -> void:
	if play_state != "play":
		return
	if healthy().is_empty():
		_round_won("zombies")


func _round_won(side: String) -> void:
	play_state = "round_end"
	_round_end_left = Tuning.INFECTION_ROUND_PAUSE_S
	var survivors: Array = []
	if side == "zombies":
		if first != null and is_instance_valid(first):
			scores[first_i] = int(scores.get(first_i, 0)) + 1
		announce.emit(tr("ВСЕ ЗАРАЖЕНЫ · ОЧКО %s") % doll_name(first), Tuning.INFECTION_COLOR, "round")
	else:
		for d in healthy():
			var pi := (d as Doll).player_index
			survivors.append(pi)
			scores[pi] = int(scores.get(pi, 0)) + 1
			_survived[pi] = int(_survived.get(pi, 0)) + 1
		var names: Array = []
		for pi in survivors:
			names.append("P%d" % (int(pi) + 1))
		announce.emit(tr("ДОЖИЛИ: %s") % ", ".join(names), Color.WHITE, "round")
	rounds.append({"round": round_i, "first": first_i, "side": side, "t": snappedf(round_time, 0.01), "infections": infections_round,
		"survivors": survivors})
	round_over.emit(side, round_i)


# --- итоги ---

## Итоги по очкам: места (равные очки — одно место), победитель — единственный лидер (иначе ничья), сводка tally.
func build_results(reason: String = "rounds") -> Dictionary:
	var r := super.build_results(reason)
	var all := dolls()
	all.sort_custom(func(a: Doll, b: Doll) -> bool:
		var sa := score_of(a)
		var sb := score_of(b)
		if sa != sb:
			return sa > sb
		return a.player_index < b.player_index)
	var ranks: Array = []
	for i in all.size():
		ranks.append(ranks[i - 1] if i > 0 and score_of(all[i]) == score_of(all[i - 1]) else i)
	var winner: Doll = null
	if not all.is_empty() and (all.size() == 1 or score_of(all[0]) > score_of(all[1])):
		winner = all[0]
	var medals: Dictionary = r.get("medals", {})
	medals.erase("Winner")
	medals.erase("Survivor")
	if winner != null:
		medals["Winner"] = winner
	var tally := {}
	for d in all:
		var dd := d as Doll
		tally[dd.player_index] = {"score": score_of(dd), "spread": 0, "caught": 0, "survived": int(_survived.get(dd.player_index, 0)), "first": 0}
	for e in infections:
		if int(e["from"]) >= 0 and tally.has(int(e["from"])):
			tally[int(e["from"])]["spread"] = int(tally[int(e["from"])]["spread"]) + 1
		if tally.has(int(e["to"])):
			if int(e["from"]) >= 0:
				tally[int(e["to"])]["caught"] = int(tally[int(e["to"])]["caught"]) + 1
			else:
				tally[int(e["to"])]["first"] = int(tally[int(e["to"])]["first"]) + 1
	r["places"] = all
	r["ranks"] = ranks
	r["winner"] = winner
	r["draw"] = winner == null
	r["medals"] = medals
	r["scores"] = scores.duplicate()
	r["rounds"] = rounds.duplicate(true)
	r["infections"] = infections.size()
	r["tally"] = tally
	return r
