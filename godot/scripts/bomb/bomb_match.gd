## Матч «Бомба касанием» (docs/plan-demo/BOMB.md, MODES_PACK.md §1; автор 06.10: «передать бомбу касанием»; «скрытый таймер, но по
## миганию и звуку чуть-чуть понятно, что и как»). Наследник Match: от него — регистрация кукол, DollCombat (удары и отброс), эффекты
## и звук, отсчёт. Своё:
##   • урона нет: каждой кукле Doll.incoming_mult = 0 (через него идут take_damage, стан и взрыв) — удары и взрыв только толкают
##     (отброс DollCombat считается от сырого удара, он полный); толчок видно — вспышка с пылью (on_hit);
##   • бомба (holder): в начале партии у случайной куклы. Каждый тик — касание любой детали держателя любой детали другой живой куклы
##     (опрос get_colliding_bodies, contact_monitor на всех деталях; ловит и долгое касание, когда кончился запрет) → бомба у неё. Тому,
##     от кого получил, — не раньше BOMB_RETURN_LOCK_S; дальше по цепочке — не раньше BOMB_PASS_MIN_HOLD_S. Держатель быстрее
##     (Doll.thrust_mult / speed_mult = BOMB_HOLDER_*), он в группе bomb_holder (стрелка за кадром — BombMarkers);
##   • фитиль (fuse_s — длина, fuse_t — сгорело): скрытый, случайный BOMB_FUSE_MIN_S…BOMB_FUSE_MAX_S, при передаче не сбрасывается.
##     Писк и мигание (сигнал beeped) — весь фитиль, пауза между писками — от доли сгоревшего с разбросом (beep_interval). Конец —
##     взрыв у держателя: knock_out (kind "bomb") + Explosion.detonate; через BOMB_NEXT_S — новая бомба у случайного живого;
##   • партия: последний живой берёт её (wins[player_index]); пауза BOMB_ROUND_PAUSE_S; до wins_to_win побед — следующая партия (все
##     куклы заново на своих точках, отсчёт BOMB_COUNTDOWN_S), иначе итоги (match_over; build_results — места по победам).
## Фазы Match: COUNTDOWN — отсчёт партии, FIGHT — партия (Sudden Death и часов нет), OVER — итоги.
## play_state: countdown | play (бомба горит) | next (бомбы нет, скоро новая) | round_end | over.
## Журналы для проб: passes, explosions, rounds, blocked_returns, beeps (времена писков текущей бомбы от её начала, с).
class_name BombMatch
extends Match

signal bomb_passed(from: Doll, to: Doll)          # from null — новая бомба
signal bomb_exploded(victim: Doll, position: Vector3)
signal beeped(urgency: float)
signal round_started(round_i: int)
signal round_over(winner: Doll, round_i: int)    # winner null — ничья (живых не осталось)

const HOLDER_GROUP := "bomb_holder"
const COLOUR_BOMB := Color(1.0, 0.42, 0.18)
const SHOVE_FX_MIN_SPEED := 2.5      # м/с: удар куклы о куклу слабее — без вспышки

@export var wins_to_win: int = Tuning.BOMB_WINS_TO_WIN
## Сид случайностей (кто первым с бомбой, фитиль, разброс писка); 0 — каждый раз новый.
@export var rng_seed := 0

var play_state := "idle"
var round_i := 0
## Время текущей партии (с FIGHT!); fight_time — всего матча.
var round_time := 0.0
var wins: Dictionary = {}          # player_index → побед в партиях
var holder: Doll = null
var got_from: Doll = null          # от кого держатель получил бомбу (null — бомба новая)
var got_at := -100.0               # round_time передачи
var fuse_s := 0.0
var fuse_t := 0.0
var bomb_serial := 0
var beeps: Array = []              # fuse_t писков текущей бомбы
var passes: Array = []             # [{t, round, from, to, fuse_t, bomb}]
var explosions: Array = []         # [{t, round, victim, fuse_s, fuse_t, alive_before, bomb}]
var rounds: Array = []             # [{round, winner, t, passes, explosions}]
## Тиков, когда держатель касался того, от кого получил, а запрет возврата не дал отдать.
var blocked_returns := 0
var passes_round := 0
var _explosions_round := 0
var _beep_left := 0.0
var _bias := 0.0
var _next_left := -1.0
var _round_end_left := -1.0
var _rng := RandomNumberGenerator.new()
var _first_round := true
var _restart_pending := false
var _in_tick := false
var carry: BombCarry


func _ready() -> void:
	time_limit_s = 1.0e9      # часов нет: партия кончается взрывами
	hard_timeout_s = 1.0e9
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	super._ready()
	crit_enabled = false      # урона нет — крит-кино не к чему
	carry = BombCarry.new()
	carry.name = "BombCarry"
	add_child(carry)
	carry.bind(self)


# --- куклы ---

func register(d: Doll) -> void:
	super.register(d)
	d.incoming_mult = 0.0
	var c := colour_of(d.player_index)
	if c != Tuning.PLAYER_COLORS[clampi(d.player_index, 0, 3)]:
		d._recolor(d, Doll.SHIRT_MATERIAL, c)   # пятый и дальше: у куклы цветов четыре (PLAYER_COLORS)
	for b in d.parts.values():
		var rb := b as RigidBody3D
		if rb != null:
			rb.contact_monitor = true   # касание любой деталью (DollCombat слушает не все)
			rb.max_contacts_reported = maxi(rb.max_contacts_reported, 4)


## Точки появления: Tuning.BOMB_SPAWN по player_index (у купола их четыре).
func spawn_point_for(d: Doll) -> Vector3:
	var pts: Array = Tuning.BOMB_SPAWN
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


func win_count(d: Object) -> int:
	if d == null or not is_instance_valid(d):
		return 0
	return int(wins.get(int(d.get("player_index")), 0))


## Держатель не может отдать бомбу кукле d прямо сейчас (запрет возврата).
func locked_for(d: Doll) -> bool:
	return d != null and d == got_from and round_time - got_at < Tuning.BOMB_RETURN_LOCK_S


func lock_left() -> float:
	return maxf(Tuning.BOMB_RETURN_LOCK_S - (round_time - got_at), 0.0) if got_from != null else 0.0


# --- фазы ---

func begin() -> void:
	wins.clear()
	rounds.clear()
	passes.clear()
	explosions.clear()
	blocked_returns = 0
	round_i = 1
	round_time = 0.0
	_first_round = true
	_clear_bomb()
	play_state = "countdown"
	super.begin()
	round_started.emit(round_i)


## R / «Заново»: куклы пересоздаются только в своём тике (_physics_process матча — после NullField купола, он раньше в дереве), вызов
## откуда угодно ещё (ввод, пауза, проба) — на ближайшем тике. Иначе вызов внутри физического кадра до тика поля (сигнал physics_frame
## у проб) оставляет мембране вынутые из дерева детали (get_overlapping_bodies обновится только шагом физики) — ошибки
## «!is_inside_tree()» в null_field.gd (проверено 06.10: в куполе Быстрого боя так же; R из ввода их не даёт).
func restart() -> void:
	if not _in_tick:
		_restart_pending = true
		return
	_restart_pending = false
	_clear_bomb()
	super.restart()


## FIGHT! партии: куклы управляемы, бомба — случайному.
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
	passes_round = 0
	_explosions_round = 0
	_set_phase(Phase.FIGHT)
	play_state = "play"
	announce.emit(tr("FIGHT!"), ANNOUNCE_COLORS["fight"], "fight")
	_new_bomb()


## Следующая партия: все куклы заново на своих точках, отсчёт.
func _next_round() -> void:
	round_i += 1
	_clear_bomb()
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
	_countdown_left = Tuning.BOMB_COUNTDOWN_S
	_countdown_shown = -1
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
					_tick_bomb(delta)
				"next":
					_next_left -= delta
					if _next_left <= 0.0:
						_new_bomb()
				"round_end":
					_round_end_left -= delta
					if _round_end_left <= 0.0:
						if _top_wins() >= wins_to_win:
							_finish("wins")
						else:
							_next_round()


## СТАЗИС: время ждёт игрока, только пока горит бомба (отсчёт, пауза между бомбами и после партии идут сами).
func stasis_allowed() -> bool:
	return play_state == "play" and super.stasis_allowed()


func _check_over() -> void:
	pass   # конец партии и матча — _after_out / _round_won


func _finish(reason: String) -> void:
	play_state = "over"
	_clear_bomb()
	super._finish(reason)


# --- бомба ---

func roll_fuse() -> float:
	return _rng.randf_range(Tuning.BOMB_FUSE_MIN_S, Tuning.BOMB_FUSE_MAX_S)


## Пауза до следующего писка при доле сгоревшего фитиля k (0..1), без разброса.
static func beep_interval(k: float) -> float:
	return lerpf(Tuning.BOMB_BEEP_SLOW_S, Tuning.BOMB_BEEP_FAST_S, pow(clampf(k, 0.0, 1.0), Tuning.BOMB_BEEP_CURVE))


## «Сколько осталось» на слух и на глаз: доля сгоревшего с поправкой этой бомбы (0..1). Точного остатка не знает никто, кроме фитиля.
func urgency() -> float:
	if fuse_s <= 0.0:
		return 0.0
	return clampf(fuse_t / fuse_s + _bias, 0.0, 1.0)


func _new_bomb() -> void:
	var alive := alive_dolls()
	if alive.is_empty():
		return
	var d: Doll = alive[_rng.randi() % alive.size()]
	fuse_s = roll_fuse()
	fuse_t = 0.0
	bomb_serial += 1
	beeps.clear()
	_bias = _rng.randf_range(-Tuning.BOMB_BEEP_BIAS, Tuning.BOMB_BEEP_BIAS)
	_beep_left = 0.0
	got_from = null
	got_at = round_time
	_set_holder(d)
	play_state = "play"
	bomb_passed.emit(null, d)
	announce.emit(tr("БОМБА У %s") % doll_name(d), COLOUR_BOMB, "bomb")


func _set_holder(d: Doll) -> void:
	if holder != null and is_instance_valid(holder):
		holder.thrust_mult = 1.0
		holder.speed_mult = 1.0
		if holder.is_in_group(HOLDER_GROUP):
			holder.remove_from_group(HOLDER_GROUP)
	holder = d
	if d != null:
		d.thrust_mult = Tuning.BOMB_HOLDER_THRUST_MULT
		d.speed_mult = Tuning.BOMB_HOLDER_SPEED_MULT
		d.add_to_group(HOLDER_GROUP)


func _clear_bomb() -> void:
	_set_holder(null)
	got_from = null
	fuse_s = 0.0
	fuse_t = 0.0
	_next_left = -1.0


## Передать бомбу кукле d (касание; пробы зовут напрямую). Фитиль не трогается.
func pass_to(d: Doll) -> void:
	if d == null or d == holder or not d.alive:
		return
	var from := holder
	got_from = from
	got_at = round_time
	passes_round += 1
	passes.append({"t": snappedf(round_time, 0.001), "round": round_i, "from": from.player_index if from != null else -1,
		"to": d.player_index, "fuse_t": snappedf(fuse_t, 0.001), "bomb": bomb_serial})
	_set_holder(d)
	bomb_passed.emit(from, d)


func _tick_bomb(delta: float) -> void:
	if holder == null or not is_instance_valid(holder) or not holder.alive:
		# держатель выбыл не от бомбы (страховка: урона в режиме нет) — бомба уходит, скоро новая
		_clear_bomb()
		play_state = "next"
		_next_left = Tuning.BOMB_NEXT_S
		return
	fuse_t += delta
	_beep_left -= delta
	if _beep_left <= 0.0:
		var u := urgency()
		beeps.append(snappedf(fuse_t, 0.001))
		beeped.emit(u)
		_beep_left = beep_interval(u) * (1.0 + _rng.randf_range(-Tuning.BOMB_BEEP_JITTER, Tuning.BOMB_BEEP_JITTER))
	if fuse_t >= fuse_s:
		_explode()
		return
	_check_touch()


## Касание: любая деталь держателя касается детали другой живой куклы матча.
func _check_touch() -> void:
	if round_time - got_at < Tuning.BOMB_PASS_MIN_HOLD_S:
		return
	var to: Doll = null
	var blocked := false
	for b in holder.parts.values():
		var rb := b as RigidBody3D
		if rb == null or not is_instance_valid(rb) or not rb.contact_monitor:
			continue
		for o in rb.get_colliding_bodies():
			var d := doll_of(o)
			if d == null or d == holder or not d.alive or not _order.has(d):
				continue
			if locked_for(d):
				blocked = true
				continue
			to = d
			break
		if to != null:
			break
	if blocked and to == null:
		blocked_returns += 1
	if to != null:
		pass_to(to)


func _explode() -> void:
	var h := holder
	var pos := h.centre_of_mass()
	pos.z = 0.0
	explosions.append({"t": snappedf(round_time, 0.001), "round": round_i, "victim": h.player_index, "fuse_s": snappedf(fuse_s, 0.001),
		"fuse_t": snappedf(fuse_t, 0.001), "alive_before": alive_dolls().size(), "bomb": bomb_serial})
	_explosions_round += 1
	_set_holder(null)
	got_from = null
	bomb_exploded.emit(h, pos)
	h.knock_out(null, {"kind": "bomb", "weapon_id": "bomb", "position": pos})
	var parent := get_parent() if get_parent() != null else self
	Explosion.detonate(parent, pos, null, null, Tuning.BOMB_BLAST_POWER)


## Удар куклы о куклу: урона нет (DollCombat прислал 0 — надписей, тряски и эффектов удара Match не даст), но толчок видно — вспышка и
## пыль ImpactFx (материал «резина»: без щепок), сила — от скорости удара. Стук — ImpactAudio (физика), как везде.
func on_hit(victim: Doll, attacker: Node, damage: float, kind: String, position: Vector3, combo_n: int, double_blow: bool, weapon_id: String, speed: float) -> void:
	super.on_hit(victim, attacker, damage, kind, position, combo_n, double_blow, weapon_id, speed)
	if damage <= 0.0 and kind != "environment" and speed >= SHOVE_FX_MIN_SPEED:
		ImpactFx.spawn_impact(self, position, Vector3.UP, clampf(2.0 + speed * 0.7, 3.0, 10.0), kind, FxMaterial.RUBBER)


# --- выбывание и партия ---

## KO как в Match (записи, статистика, сигнал ko), но надпись — БУМ! и замедление короче; конец партии — _after_out.
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
	announce.emit(tr("БУМ!"), ANNOUNCE_COLORS["ko"], "ko")
	ko.emit(victim, attacker, rec)
	if feel_enabled:
		_camera_fx(40.0, rec.get("position", victim.centre_of_mass()))
		_time_effect(Tuning.KO_SLOWMO_SCALE, Tuning.BOMB_KO_SLOWMO_S)
	if victim == holder:
		_set_holder(null)
	_after_out()


func _after_out() -> void:
	if not combat_active() or play_state == "round_end" or play_state == "over":
		return
	var alive := alive_dolls()
	if alive.size() <= 1:
		_round_won(alive[0] if alive.size() == 1 else null)
	elif holder == null and play_state != "next":
		play_state = "next"
		_next_left = Tuning.BOMB_NEXT_S


func _round_won(w: Doll) -> void:
	_clear_bomb()
	play_state = "round_end"
	_round_end_left = Tuning.BOMB_ROUND_PAUSE_S
	if w != null:
		wins[w.player_index] = int(wins.get(w.player_index, 0)) + 1
	rounds.append({"round": round_i, "winner": w.player_index if w != null else -1, "t": snappedf(round_time, 0.01),
		"passes": passes_round, "explosions": _explosions_round})
	round_over.emit(w, round_i)
	if w != null:
		announce.emit(tr("%s БЕРЁТ ПАРТИЮ") % doll_name(w), colour_of(w.player_index).lightened(0.35), "round")
	else:
		announce.emit(tr("НИЧЬЯ"), Color.WHITE, "round")


func _top_wins() -> int:
	var m := 0
	for k in wins:
		m = maxi(m, int(wins[k]))
	return m


# --- итоги ---

## Итоги по победам в партиях (а не по HP): места, победитель (набрал wins_to_win), сводка бойцов tally.
func build_results(reason: String = "wins") -> Dictionary:
	var r := super.build_results(reason)
	var all := dolls()
	all.sort_custom(func(a: Doll, b: Doll) -> bool:
		var wa := win_count(a)
		var wb := win_count(b)
		if wa != wb:
			return wa > wb
		return a.player_index < b.player_index)
	var ranks: Array = []
	for i in all.size():
		ranks.append(ranks[i - 1] if i > 0 and win_count(all[i]) == win_count(all[i - 1]) else i)
	var winner: Doll = null
	if not all.is_empty() and win_count(all[0]) >= wins_to_win:
		winner = all[0]
	var medals: Dictionary = r.get("medals", {})
	medals.erase("Winner")
	medals.erase("Survivor")
	if winner != null:
		medals["Winner"] = winner
	var tally := {}
	for d in all:
		tally[(d as Doll).player_index] = {"wins": win_count(d), "passed": 0, "got": 0, "exploded": 0}
	for p in passes:
		if tally.has(int(p["from"])):
			tally[int(p["from"])]["passed"] = int(tally[int(p["from"])]["passed"]) + 1
		if tally.has(int(p["to"])):
			tally[int(p["to"])]["got"] = int(tally[int(p["to"])]["got"]) + 1
	for e in explosions:
		if tally.has(int(e["victim"])):
			tally[int(e["victim"])]["exploded"] = int(tally[int(e["victim"])]["exploded"]) + 1
	r["places"] = all
	r["ranks"] = ranks
	r["winner"] = winner
	r["draw"] = winner == null
	r["medals"] = medals
	r["wins"] = wins.duplicate()
	r["rounds"] = rounds.duplicate(true)
	r["passes"] = passes.size()
	r["explosions"] = explosions.size()
	r["tally"] = tally
	return r
