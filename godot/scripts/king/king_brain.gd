## Бот «Царя горы» (docs/plan-demo/KING.md). Каркас — EnemyBrain (тяга с плавным разворотом, восприятие с задержкой и упреждением,
## стан — молчит, выход из застревания, ускорение за Заряд), без EnemyLook (это игрок, а не сломанный робот) и без разноса со «своими».
## Цели — не группа players, а KingMatch (зона и кто в ней):
##   • seek — я не в зоне, в ней никого: лететь к центру зоны (далеко — с ускорением);
##   • attack — в зоне один враг (или я в зоне и там ещё кто-то): наскок на ближнего из тех, кто в зоне, с упреждением и ускорением
##     в коридоре KING_BOT_DASH_M; удар с уроном и отбросом — как в бою;
##   • hold — я в зоне один: держаться центра (мягкая тяга);
##   • guard — я в зоне один, чужой подлетает ближе KING_BOT_GUARD_M: наскок на него, но из зоны не выходить (вылетел за 0.9 R —
##     обратно к центру);
##   • ahead (уровень 3, foresee) — зона мигает (скоро переедет): лететь к новой заранее.
## Уровень 1..3 — Tuning.KING_BOT_LEVELS; Match.respawn_doll создаёт мозг заново без настроек — уровень из default_level.
class_name KingBrain
extends EnemyBrain

const HOLD_IN := 0.75           # «я в зоне» для решений — ближе этой доли радиуса к центру
const GUARD_BACK := 0.9         # защитник вылетел за эту долю радиуса — назад к центру
const SEEK_DASH_M := 6.0        # к зоне дальше этого — с ускорением
const EVAL_S := 0.2

static var default_level := 2

@export var level := -1

var km: KingMatch
var max_in := 0.92
var use_dash := true
var foresee := false
var attack_target: Doll = null
var _eval_t := 0.0


func _setup() -> void:
	if _ready_done:
		return
	_ready_done = true
	doll.external_input = true
	arena = get_tree().get_first_node_in_group("arena")
	doll.knocked_out.connect(func(_a: Node, _r: Dictionary) -> void: _on_ko())
	_brain_ready()


func _brain_ready() -> void:
	players_group = "king_nobody"
	enemies_group = "king_nobody"
	var lv := level if level > 0 else default_level
	var p: Dictionary = Tuning.KING_BOT_LEVELS.get(lv, Tuning.KING_BOT_LEVELS[2])
	max_in = float(p["max_in"])
	aim_error_m = float(p["aim_error_m"])
	reaction_s = float(p["reaction_s"])
	lead_s = float(p["lead_s"])
	use_dash = bool(p["dash"])
	foresee = bool(p["foresee"])
	go("seek")


func _find_match() -> void:
	if km == null or not is_instance_valid(km):
		km = get_tree().get_first_node_in_group(Match.GROUP) as KingMatch


## Цель для EnemyBrain (_pick_target / predicted): тот, на кого наскакиваем сейчас.
func players() -> Array:
	if attack_target != null and is_instance_valid(attack_target) and attack_target.alive and attack_target.is_inside_tree():
		return [attack_target]
	return []


static func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.y)


func _nearest(list: Array, from: Vector2) -> Doll:
	var best: Doll = null
	var bd := INF
	for d in list:
		if d == doll or d == null or not is_instance_valid(d) or not (d as Doll).alive:
			continue
		var dd := from.distance_to(com2(d))
		if dd < bd:
			bd = dd
			best = d
	return best


func _think(delta: float) -> void:
	_find_match()
	if km == null or km.play_state != "play":
		go("idle")
		want = hover_vec()
		return
	var me := my_pos()
	var zc := _flat(km.zone_centre())
	var r: float = Tuning.KING_ZONE_R
	var me_in := me.distance_to(zc) <= r * HOLD_IN or km.occupants.has(doll)
	var others: Array = []
	for d in km.occupants:
		if d != doll:
			others.append(d)
	_eval_t -= delta
	if _eval_t <= 0.0 or attack_target == null or not players().has(attack_target):
		_eval_t = EVAL_S
		var want_t: Doll = null
		if not others.is_empty():
			want_t = _nearest(others, me)
		elif me_in:
			var near: Array = []
			for d in km.alive_dolls():
				if d != doll and com2(d).distance_to(me) < Tuning.KING_BOT_GUARD_M:
					near.append(d)
			want_t = _nearest(near, me)
		attack_target = want_t
	if target != attack_target:   # EnemyBrain._pick_target держит старую цель «в пределах запаса» — здесь цель одна и точная
		target = attack_target
		_hist.clear()
		_record_target()
	# зона мигает — умный летит к новой заранее
	if foresee and km.warning():
		var nz := _flat(km.next_centre())
		go("ahead")
		want = steer(nz, max_in)
		if use_dash and me.distance_to(nz) > SEEK_DASH_M:
			dash()
		return
	if target != null and is_instance_valid(target) and target.alive:
		var guarding := me_in and others.is_empty()
		if state != "attack" and state != "guard":
			note_attack()
		go("guard" if guarding else "attack")
		if guarding and me.distance_to(zc) > r * GUARD_BACK:
			want = steer(zc, max_in)
			return
		var to := predicted() - me
		var dist := to.length()
		var dir := to / dist if dist > 0.01 else Vector2.UP
		want = (dir * max_in + hover_vec()).limit_length(1.0)
		var dm: Vector2 = Tuning.KING_BOT_DASH_M
		if use_dash and dist > dm.x and dist < dm.y:
			dash()
		return
	if me_in:
		go("hold")
		want = steer(zc, max_in * 0.8)
		return
	go("seek")
	want = steer(zc, max_in)
	if use_dash and me.distance_to(zc) > SEEK_DASH_M:
		dash()


func _stuck_allowed() -> bool:
	return state != "hold"
