## Бот хоккея (docs/plan-demo/HOCKEY.md) на базе SportBrain: то же правило «встань за шайбу против точки прицела и пройди сквозь
## неё» (chase / strike / wait), шайба с упреждением lead_s, прицел — середина чужих ворот у льда. Своё:
##   • goalie — шайба на своей половине и соперник к ней ближе бота: держаться на луче «середина своих ворот → шайба» в
##     HOCKEY_GOALIE_OUT_M от линии (и не выше перекладины) — встать между шайбой и воротами; соперник отстал — снова за шайбой;
##     то же, когда шайба летит в мои ворота быстрее HOCKEY_THREAT_SPEED, а я дальше от них, чем она (не догнать — встать в воротах,
##     с ускорением);
##   • в ударе у шайбы ближе HOCKEY_SPIN_NEAR_M — раскрутка (Doll.request_spin): клюшка в кисти описывает дугу и подметает лёд.
## Уровни 1..3 — Tuning.HOCKEY_BOT_LEVELS (тяга, прицел, упреждение, ускорение, раскрутка, вратарь); уровень новых мозгов —
## SportBrain.default_level (Match.respawn_doll пересоздаёт мозг без настроек; K на площадке меняет его).
class_name HockeyBrain
extends SportBrain

var use_spin := true
var use_goalie := true


func _brain_ready() -> void:
	super._brain_ready()
	var p: Dictionary = Tuning.HOCKEY_BOT_LEVELS.get(level, Tuning.HOCKEY_BOT_LEVELS[2])
	max_in = float(p["max_in"])
	aim_error_m = float(p["aim_error_m"])
	lead_s = float(p["lead_s"])
	use_dash = bool(p["dash"])
	use_spin = bool(p["spin"])
	use_goalie = bool(p["goalie"])


func _think(delta: float) -> void:
	_find_refs()
	if ball == null or sm == null:
		want = hover_vec()
		return
	var b := ball.pos2() + ball.vel2() * lead_s
	if use_goalie and _goalie_needed(b):
		go("goalie")
		want = steer(_goalie_point(b), max_in)
		if use_dash and _threat() and my_pos().distance_to(_goalie_point(b)) > DASH_FROM_M:
			dash()
		return
	super._think(delta)
	if use_spin and state == "strike" and my_pos().distance_to(ball.pos2()) < Tuning.HOCKEY_SPIN_NEAR_M:
		doll.request_spin()


func _aim_point(_b: Vector2) -> Vector2:
	var r: Dictionary = sm.rules()
	return Vector2(dir * (float(r["goal_x"]) + 1.2), Puck.rest_y())


## Шайба на своей половине и соперник к ней ближе меня — или шайба летит в мои ворота, а я дальше от них, чем она (не догнать —
## встать в воротах).
func _goalie_needed(b: Vector2) -> bool:
	if _threat():
		return true
	if b.x * dir > 0.0:
		return false
	var opp := _opponent()
	if opp == null:
		return false
	var me := my_pos()
	var o := Vector2(opp.centre_of_mass().x, opp.centre_of_mass().y)
	return o.distance_to(b) + 0.5 < me.distance_to(b)


func _threat() -> bool:
	var v := ball.vel2()
	return v.x * dir < -Tuning.HOCKEY_THREAT_SPEED and ball.pos2().x * dir < my_pos().x * dir


func _goalie_point(b: Vector2) -> Vector2:
	var r: Dictionary = sm.rules()
	var mouth := Vector2(-dir * float(r["goal_x"]), float(r["goal_h"]) * 0.5)
	var to_b := b - mouth
	var p := mouth + (to_b.normalized() if to_b.length() > 0.01 else Vector2(dir, 0.0)) * Tuning.HOCKEY_GOALIE_OUT_M
	p.y = clampf(p.y, 0.7, float(r["goal_h"]) + 0.3)
	return p


func _opponent() -> Doll:
	for d in sm.dolls():
		var dd := d as Doll
		if dd != doll and dd.alive and SportMatch.team_of(dd) != team:
			return dd
	return null
