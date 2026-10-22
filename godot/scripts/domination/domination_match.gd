## Матч «Захват точек» (docs/plan-demo/DOMINATION.md, MODES_IDEAS.md Б2): стычка 3 на 3 на Полигоне (SquadMatch — классы, опыт,
## ящики, возрождение), но счёт — не за выбывания, а за удержание трёх зон A, B, C (Tuning.DOM_ZONES, радиус DOM_ZONE_R).
##   • В зоне считаются живые бойцы, чей центр масс ближе DOM_ZONE_R (по x-y). Есть оба цвета — зона спорная, прогресс стоит.
##   • Одна команда (n бойцов) — прогресс идёт со скоростью min(1 + DOM_CAPTURE_EXTRA·(n−1), DOM_CAPTURE_MAX) / DOM_CAPTURE_S в секунду:
##     нейтральную — захватывает (0 → 1, полоска её цвета; чужая начатая полоска сначала стекает), чужую — сначала нейтрализует
##     (1 → 0, событие «neutralized»), потом захватывает (событие «captured»), свою — доливает до полной.
##   • Пусто — начатая полоска нейтральной зоны стекает за DOM_IDLE_S, своя у владельца — доливается.
##   • Каждая своя зона даёт DOM_POINTS_PER_S очков в секунду; score (int) — целые очки. До score_to_win — победа, по времени
##     (time_limit_s = DOM_TIME_S) — у кого больше, равно — ничья. Выбывания очков не дают (SquadMatch.frags_score), возрождение то же.
## Опыт: захват — DOM_XP_CAPTURE каждому своему в зоне, нейтрализация — DOM_XP_NEUTRALIZE; в таблицу итогов — captures за захват.
## Зоны на арене — узлы DominationZone (создаются один раз, читают матч каждый кадр); HUD — DominationHud (zone_event).
class_name DominationMatch
extends SquadMatch

## Событие зоны: what — "captured" (team теперь владеет), "neutralized" (team сбила чужую зону в нейтральную).
signal zone_event(zone: int, what: String, team: int)

## Состояние зон: [{owner: -1/0/1, prog: 0..1 (у владельца — запас, у нейтральной — захват prog_team), prog_team, contested, n: [синие, красные]}].
var zones: Array = []
## Очки с дробью (score — их целая часть).
var points: Array = [0.0, 0.0]
## Журнал событий зон: [{t, zone, what, team}] — в итоги и пробе.
var zone_log: Array = []
## Секунды владения зонами по командам — в итоги и пробе.
var held_s: Array = [0.0, 0.0]
var zone_nodes: Array = []


func _ready() -> void:
	super._ready()
	mode = "dom"
	time_limit_s = Tuning.DOM_TIME_S
	hard_timeout_s = Tuning.DOM_TIME_S
	score_to_win = Tuning.DOM_SCORE_TO_WIN


func zone_count() -> int:
	return Tuning.DOM_ZONES.size()


## Центр зоны i (мир; z = 0).
func zone_centre(i: int) -> Vector3:
	var p: Vector2 = Tuning.DOM_ZONES[i]
	return Vector3(p.x, p.y, 0.0)


func zone_owner(i: int) -> int:
	return int(zones[i]["owner"]) if i >= 0 and i < zones.size() else -1


func zone_progress(i: int) -> float:
	return float(zones[i]["prog"]) if i >= 0 and i < zones.size() else 0.0


func zone_name(i: int) -> String:
	return String(Tuning.DOM_ZONE_NAMES[i])


## Сколько зон у команды t.
func zones_of(t: int) -> int:
	var n := 0
	for z in zones:
		if int(z["owner"]) == t:
			n += 1
	return n


func _fresh_zone() -> Dictionary:
	return {"owner": -1, "prog": 0.0, "prog_team": -1, "contested": false, "n": [0, 0]}


## begin(): флагов нет (super убирает старые), зоны — нейтральные, очки — с нуля; узлы зон — один раз на арену.
func _setup_flags() -> void:
	super._setup_flags()
	zones.clear()
	for i in zone_count():
		zones.append(_fresh_zone())
	points = [0.0, 0.0]
	held_s = [0.0, 0.0]
	zone_log.clear()
	var alive_nodes := zone_nodes.filter(func(z: Variant) -> bool: return is_instance_valid(z))
	if alive_nodes.size() == zone_count():
		return
	for z in zone_nodes:
		if is_instance_valid(z):
			(z as Node).queue_free()
	zone_nodes.clear()
	var a := _arena()
	for i in zone_count():
		var zn := DominationZone.new()
		zn.name = "Zone" + zone_name(i)
		zn.index = i
		zn.bind(self)
		(a if a != null else get_parent()).add_child(zn)
		zn.global_position = zone_centre(i)
		zone_nodes.append(zn)


func _tick_flags(delta: float) -> void:
	super._tick_flags(delta)
	if play_state == "play" and phase == Phase.FIGHT:
		_tick_zones(delta)


## Живые бойцы в зоне i по командам.
func count_in(i: int) -> Array:
	var n := [0, 0]
	var c := zone_centre(i)
	var r2: float = Tuning.DOM_ZONE_R * Tuning.DOM_ZONE_R
	for d in alive_dolls():
		var p := (d as Doll).centre_of_mass()
		var t := team_of(d)
		if t < 0:
			continue
		if Vector2(p.x - c.x, p.y - c.y).length_squared() <= r2:
			n[t] = int(n[t]) + 1
	return n


## Те, кто в зоне i, команды t.
func dolls_in(i: int, t: int) -> Array:
	var c := zone_centre(i)
	var r2: float = Tuning.DOM_ZONE_R * Tuning.DOM_ZONE_R
	return team_alive(t).filter(func(d: Variant) -> bool:
		var p := (d as Doll).centre_of_mass()
		return Vector2(p.x - c.x, p.y - c.y).length_squared() <= r2)


## Скорость захвата (доля в секунду) для n своих в зоне.
static func capture_rate(n: int) -> float:
	if n <= 0:
		return 0.0
	return minf(1.0 + Tuning.DOM_CAPTURE_EXTRA * float(n - 1), Tuning.DOM_CAPTURE_MAX) / Tuning.DOM_CAPTURE_S


func _tick_zones(delta: float) -> void:
	for i in zones.size():
		var z: Dictionary = zones[i]
		var n := count_in(i)
		z["n"] = n
		z["contested"] = int(n[0]) > 0 and int(n[1]) > 0
		if bool(z["contested"]):
			continue
		var owner := int(z["owner"])
		var t := 0 if int(n[0]) > 0 else (1 if int(n[1]) > 0 else -1)
		if t < 0:
			if owner >= 0:
				z["prog"] = minf(1.0, float(z["prog"]) + delta / Tuning.DOM_IDLE_S)
			else:
				z["prog"] = maxf(0.0, float(z["prog"]) - delta / Tuning.DOM_IDLE_S)
				if float(z["prog"]) <= 0.0:
					z["prog_team"] = -1
			continue
		var rate := capture_rate(int(n[t])) * delta
		if owner == t:
			z["prog"] = minf(1.0, float(z["prog"]) + rate)
		elif owner == 1 - t:
			z["prog"] = float(z["prog"]) - rate
			if float(z["prog"]) <= 0.0:
				z["owner"] = -1
				z["prog"] = 0.0
				z["prog_team"] = t
				_zone_happened(i, "neutralized", t, Tuning.DOM_XP_NEUTRALIZE)
		else:
			if int(z["prog_team"]) == t or int(z["prog_team"]) < 0 or float(z["prog"]) <= 0.0:
				z["prog_team"] = t
				z["prog"] = float(z["prog"]) + rate
				if float(z["prog"]) >= 1.0:
					z["owner"] = t
					z["prog"] = 1.0
					for d in dolls_in(i, t):
						_tally((d as Doll).player_index, "captures", 1)
					_zone_happened(i, "captured", t, Tuning.DOM_XP_CAPTURE)
			else:
				z["prog"] = maxf(0.0, float(z["prog"]) - rate)   # чужая начатая полоска сначала стекает
	_tick_points(delta)


func _zone_happened(i: int, what: String, t: int, xp: float) -> void:
	for d in dolls_in(i, t):
		add_xp((d as Doll).player_index, xp)
	zone_log.append({"t": snappedf(fight_time, 0.01), "zone": i, "what": what, "team": t})
	zone_event.emit(i, what, t)
	if feel_enabled and what == "captured":
		_play("equip", -2.0, 0.8, zone_centre(i))


## Очки: каждая своя зона — DOM_POINTS_PER_S в секунду; до score_to_win — конец.
func _tick_points(delta: float) -> void:
	var changed := false
	for z in zones:
		var o := int(z["owner"])
		if o < 0:
			continue
		held_s[o] = float(held_s[o]) + delta
		points[o] = float(points[o]) + Tuning.DOM_POINTS_PER_S * delta
		var whole := mini(int(floor(float(points[o]) + 1e-6)), score_to_win)
		if whole != int(score[o]):
			score[o] = whole
			changed = true
	if not changed:
		return
	score_changed.emit(score.duplicate())
	for t in 2:
		if int(score[t]) >= score_to_win:
			call_deferred("_finish", "score")
			return


# --- план ботов ---

var _plan: Array = [{}, {}]          # команда → {player_index: зона}
var _plan_t: Array = [-INF, -INF]    # fight_time последнего плана


## Зона, куда идти боту d (план команды пересчитывается раз в DOM_BOT_REPLAN_S): -1 — плана нет.
func bot_zone(d: Doll) -> int:
	var t := team_of(d)
	if t < 0 or zones.size() != zone_count():
		return -1
	if fight_time - float(_plan_t[t]) >= Tuning.DOM_BOT_REPLAN_S or not (_plan[t] as Dictionary).has(d.player_index):
		_plan[t] = plan_team(t)
		_plan_t[t] = fight_time
	return int((_plan[t] as Dictionary).get(d.player_index, -1))


## Нужда команды t в зоне i: чужая или нейтральная — 2 (середина B — 2.5: с неё ближе к обеим), своя под угрозой (соперник внутри,
## спорная, запас не полный) — 2, своя спокойная — 0.5 (караул, если бойцов хватает).
func zone_need(t: int, i: int) -> float:
	var z: Dictionary = zones[i]
	var n: Array = z["n"]
	var mid := 0.5 if i == 1 else 0.0
	if int(z["owner"]) != t:
		return 2.0 + mid
	if int(n[1 - t]) > 0 or float(z["prog"]) < 1.0:
		return 2.0 + mid
	return 0.5


## План команды t: {player_index бота: зона}. Сначала каждой нужной зоне (нужда ≥ 1, по убыванию) — ближайший свободный бот; лишние —
## в ближайшую нужную (вдвоём захват быстрее); нужных нет — по одному в караул по местам (A, B, C — от своей базы).
func plan_team(t: int) -> Dictionary:
	var bots: Array = team_alive(t).filter(func(d: Variant) -> bool: return (d as Doll).external_input)
	bots.sort_custom(func(a: Doll, b: Doll) -> bool: return a.player_index < b.player_index)
	var plan := {}
	if bots.is_empty():
		return plan
	var order: Array = range(zone_count())
	order.sort_custom(func(a: int, b: int) -> bool:
		var na := zone_need(t, a)
		var nb := zone_need(t, b)
		if not is_equal_approx(na, nb):
			return na > nb
		return _dist_from_base(t, a) < _dist_from_base(t, b))
	var needed: Array = order.filter(func(i: int) -> bool: return zone_need(t, i) >= 1.0)
	var free: Array = bots.duplicate()
	for i in needed:
		if free.is_empty():
			break
		var best := _nearest_bot(free, i)
		plan[best.player_index] = i
		free.erase(best)
	for b in free:
		var dd := b as Doll
		if not needed.is_empty():
			var bi := -1
			var bd := INF
			for i in needed:
				var dist := _bot_dist(dd, i)
				if dist < bd:
					bd = dist
					bi = i
			plan[dd.player_index] = bi
		else:
			var slot := (dd.player_index / 2) % zone_count()
			plan[dd.player_index] = slot if t == 0 else zone_count() - 1 - slot
	return plan


func _bot_dist(d: Doll, i: int) -> float:
	var p := d.centre_of_mass()
	var c := zone_centre(i)
	return Vector2(p.x - c.x, p.y - c.y).length()


func _nearest_bot(bots: Array, i: int) -> Doll:
	var best: Doll = bots[0]
	var bd := INF
	for b in bots:
		var dist := _bot_dist(b as Doll, i)
		if dist < bd:
			bd = dist
			best = b
	return best


func _dist_from_base(t: int, i: int) -> float:
	var base_x := -28.0 if t == 0 else 28.0
	return absf(zone_centre(i).x - base_x)


func build_results(reason: String = "timeout") -> Dictionary:
	var r := super.build_results(reason)
	r["zones"] = zones.duplicate(true)
	r["points"] = [snappedf(float(points[0]), 0.01), snappedf(float(points[1]), 0.01)]
	r["held_s"] = [snappedf(float(held_s[0]), 0.01), snappedf(float(held_s[1]), 0.01)]
	r["zone_log"] = zone_log.duplicate(true)
	return r
