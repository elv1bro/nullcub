## Бот «Захвата точек» (docs/plan-demo/DOMINATION.md): всё от бота стычки (SquadBrain — стрельба, ящики, громила, застревание), но
## цель режима — зона из плана команды (DominationMatch.bot_zone: чужие и нейтральные зоны — по ближайшему боту, лишние — вдвоём в
## ближайшую нужную, все свои спокойны — караул по одному).
##   • Не в своей зоне плана — к ней напрямую, стреляя на ходу (rush), дальше 10 м — с рывком.
##   • В зоне — к своей точке удержания (по месту в команде, в пределах DOM_BOT_HOLD_FRAC радиуса, с покачиванием) и бой оттуда:
##     пока зону берут или она спорная — стоит и стреляет (за ящиками не уходит); своя спокойная — бьётся с соперником ближе
##     DOM_BOT_ENGAGE_M, но держится внутри зоны (_hold_range / _advance зажаты в круг).
class_name DominationBrain
extends SquadBrain

const HOLD_SPREAD := [-0.75, 0.0, 0.75]   # точка удержания по x (доля HOLD_FRAC·R) по месту в команде
const HOLD_WOBBLE := 0.35                  # доля R: покачивание вверх-вниз в зоне

## Зона из плана (−1 — нет) и внутри ли бот её круга.
var zone := -1
var inside := false


func dm() -> DominationMatch:
	return sm() as DominationMatch


func _objective(m: SquadMatch) -> Variant:
	var d := m as DominationMatch
	if d == null or not is_instance_valid(d) or d.play_state != "play":
		zone = -1
		return super._objective(m)
	zone = d.bot_zone(doll)
	if zone < 0:
		return null
	var c := d.zone_centre(zone)
	var r: float = Tuning.DOM_ZONE_R
	var me := my_pos()
	inside = me.distance_to(Vector2(c.x, c.y)) <= r * 0.92
	var slot := (int(doll.player_index) / 2) % HOLD_SPREAD.size()
	var off := Vector2(float(HOLD_SPREAD[slot]) * Tuning.DOM_BOT_HOLD_FRAC * r,
		sin((_time + _phase) * TAU / WOBBLE_S) * HOLD_WOBBLE * r * 0.5)
	return _clamp_goal(Vector2(c.x, c.y) + off)


## Обороняет (может уйти в бой с соперником ближе DOM_BOT_ENGAGE_M) — только в своей спокойной зоне: внутри круга, зона наша и
## полна, не спорная. Иначе — к точке удержания, стреляя на ходу.
func _defending() -> bool:
	var d := dm()
	if d == null or zone < 0 or zone >= d.zones.size() or not inside:
		return false
	var z: Dictionary = d.zones[zone]
	if int(z["owner"]) != team or float(z["prog"]) < 1.0 or bool(z["contested"]):
		return false
	return target != null and is_instance_valid(target) and target.alive \
		and my_pos().distance_to(com2(target)) <= Tuning.DOM_BOT_ENGAGE_M


func _think(delta: float) -> void:
	super._think(delta)
	_keep_in_zone()


## Бой в зоне: цель движения не выходит за круг зоны (иначе _hold_range увёл бы на дистанцию оружия — и зону бы отдали).
func _keep_in_zone() -> void:
	var d := dm()
	if d == null or zone < 0 or not inside or state == "objective" or state == "supply":
		return
	var c := d.zone_centre(zone)
	var cc := Vector2(c.x, c.y)
	var me := my_pos()
	var r: float = Tuning.DOM_ZONE_R * 0.8
	var off := me - cc
	if off.length() > r:
		var back := (cc + off.normalized() * r * 0.6) - me
		want = (want * 0.3 + back.normalized() * max_in).limit_length(max_in)
