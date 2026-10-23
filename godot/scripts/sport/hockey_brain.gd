## Бот хоккея (docs/plan-demo/HOCKEY.md) на базе SportBrain: то же правило «встань за шайбу против точки прицела и пройди сквозь
## неё» (chase / strike / wait), шайба с упреждением lead_s, прицел — середина чужих ворот у льда. Своё:
##   • goalie — шайба на своей половине и соперник к ней ближе бота: держаться на луче «середина своих ворот → шайба» в
##     HOCKEY_GOALIE_OUT_M от линии (и не выше перекладины) — встать между шайбой и воротами; соперник отстал — снова за шайбой;
##     то же, когда шайба летит в мои ворота быстрее HOCKEY_THREAT_SPEED, а я дальше от них, чем она (не догнать — встать в воротах,
##     с ускорением);
##   • правила 23.10 (HOCKEY.md, Tuning.HOCKEY_CREASE_M …): защитник — соперник ближе к шайбе на HOCKEY_DEFEND_MARGIN_M (на любой
##     половине, если шайба едет к моим воротам быстрее HOCKEY_DEFEND_SPEED) — тоже вратарь; шайба на чужой половине дальше
##     HOCKEY_BOT_REACH_X от центра — тоже домой (бот играет на своей половине); вбрасывание у соперника — жду дома, пока шайба не
##     перейдёт центр (не дольше HOCKEY_FACEOFF_HOLD_S, _faceoff_hold); шайба летит в створ ближе HOCKEY_LUNGE_M — бросок на неё (lunge, с ускорением): касание в своей
##     вратарской — сейв (SportMatch._save); вратарь соперника держит шайбу — нападающий ждёт за его вратарской;
##   • в ударе у шайбы ближе HOCKEY_SPIN_NEAR_M — раскрутка (Doll.request_spin): клюшка в кисти описывает дугу и подметает лёд.
## Уровни 1..3 — Tuning.HOCKEY_BOT_LEVELS (тяга, прицел, упреждение, ускорение, раскрутка, вратарь); уровень новых мозгов —
## SportBrain.default_level (Match.respawn_doll пересоздаёт мозг без настроек; K на площадке меняет его).
class_name HockeyBrain
extends SportBrain

var use_spin := true
var use_goalie := true
var goalie_dash := true
var _crossed := false   # после вбрасывания соперника шайба уже была на моей половине
var _faceoff_seen := -1   # sm.faceoff_n, для которого считан _crossed


func _brain_ready() -> void:
	super._brain_ready()
	var p: Dictionary = Tuning.HOCKEY_BOT_LEVELS.get(level, Tuning.HOCKEY_BOT_LEVELS[2])
	max_in = float(p["max_in"])
	aim_error_m = float(p["aim_error_m"])
	lead_s = float(p["lead_s"])
	use_dash = bool(p["dash"])
	use_spin = bool(p["spin"])
	use_goalie = bool(p["goalie"])
	goalie_dash = bool(p.get("goalie_dash", use_dash))


func _think(delta: float) -> void:
	_find_refs()
	if ball == null or sm == null:
		want = hover_vec()
		return
	var b := ball.pos2() + ball.vel2() * lead_s
	if sm.save_hold_s() > 0.0:
		_during_save()
		return
	if use_goalie and (_goalie_needed(b) or _faceoff_hold()):
		if _lunge_ok():
			go("lunge")
			want = steer(ball.pos2() + ball.vel2() * 0.15, 1.0)
			if goalie_dash:
				dash()
			return
		go("goalie")
		var gp := _goalie_route(b)
		want = steer(gp, max_in)
		if goalie_dash and (_threat() or gp != _goalie_point(b)) and my_pos().distance_to(gp) > DASH_FROM_M:
			dash()
		return
	super._think(delta)
	if use_spin and state == "strike" and my_pos().distance_to(ball.pos2()) < Tuning.HOCKEY_SPIN_NEAR_M:
		doll.request_spin()


## Решено 22.10 (BALANCE_2210.md): шайба на льду (y 0.08), а ЦМ куклы в погоне не ниже 0.9 (sport_brain) — расстояние до линии
## удара не меньше 0.8 при допуске ALIGN_M 0.5 + 0.3 × отставание: у лежащей шайбы бот висел в «chase» десятки секунд
## (hockey_probe bots_not_stuck, когда вратарь стал отбивать). Допуск — на разницу высот.
func _align_slack(b: Vector2) -> float:
	return maxf(0.0, 0.9 - b.y)


func _aim_point(_b: Vector2) -> Vector2:
	var r: Dictionary = sm.rules()
	return Vector2(dir * (float(r["goal_x"]) + 1.2), Puck.rest_y())


## Правила 23.10: бот играет на своей половине (до HOCKEY_BOT_REACH_X за центр) — шайба глубже у соперника: домой, на луч
## вратаря (как в аэрохоккее — бросок через всё поле, у вратаря есть время). Иначе: шайба на своей половине и соперник к ней ближе меня — или шайба летит в мои ворота, а я дальше от них, чем она (не догнать —
## встать в воротах).
func _goalie_needed(b: Vector2) -> bool:
	if _threat() or _defender_needed(b) or b.x * dir > Tuning.HOCKEY_BOT_REACH_X:
		return true
	if b.x * dir > 0.0:
		return false
	var opp := _opponent()
	if opp == null:
		return false
	var me := my_pos()
	var o := Vector2(opp.centre_of_mass().x, opp.centre_of_mass().y)
	return o.distance_to(b) + 0.5 < me.distance_to(b)


## Правила 23.10: защитник — соперник ведёт шайбу ко мне (ближе к ней на HOCKEY_DEFEND_MARGIN_M, шайба едет к моим воротам
## быстрее HOCKEY_DEFEND_SPEED) на любой половине: домой, а не наперегонки (вратарь опаздывал: шайба 4.5 м/с, кукла с вбрасывания
## у центра). Шайба стоит или уходит на чужую половину — защитник выходит на неё (иначе вратарь стоял в воротах весь матч).
func _defender_needed(b: Vector2) -> bool:
	var opp := _opponent()
	if opp == null or ball.vel2().x * dir > -Tuning.HOCKEY_DEFEND_SPEED:
		return false
	var o := Vector2(opp.centre_of_mass().x, opp.centre_of_mass().y)
	return o.distance_to(b) + Tuning.HOCKEY_DEFEND_MARGIN_M < my_pos().distance_to(b)


## Правила 23.10: вбрасывание после гола или сейва — у соперника (sm.faceoff_team), на его половине: я жду дома, пока шайба не
## перейдёт центр ко мне (или HOCKEY_FACEOFF_HOLD_S часов), а не бегу отнимать её у его ворот (гол через 6 с после вбрасывания).
func _faceoff_hold() -> bool:
	if _faceoff_seen != sm.faceoff_n:
		_faceoff_seen = sm.faceoff_n
		_crossed = false
	if sm.faceoff_team < 0 or sm.faceoff_team == team:
		return false
	if ball.pos2().x * dir < 0.0:
		_crossed = true
	return not _crossed and sm.fight_time - sm.faceoff_clock < Tuning.HOCKEY_FACEOFF_HOLD_S


## Бросок вратаря: шайба едет к моим воротам и уже близко — на неё, а не на луч (касание во вратарской — сейв).
func _lunge_ok() -> bool:
	var p := ball.pos2()
	var v := ball.vel2()
	if v.x * dir > -1.0 or ball.freeze:
		return false
	var gx := float(sm.rules()["goal_x"])
	return my_pos().distance_to(p) < Tuning.HOCKEY_LUNGE_M and -p.x * dir > gx - Tuning.HOCKEY_CREASE_M - 2.0


## Вратарь держит шайбу (сейв): свой — на луче вратаря; нападающий — ждёт у края чужой вратарской, ниже полёта выброса.
func _during_save() -> void:
	var gx := float(sm.rules()["goal_x"])
	if sm.save_team() == team:
		go("goalie")
		want = steer(_goalie_point(ball.pos2()), max_in)
		return
	go("wait")
	want = steer(Vector2(dir * (gx - Tuning.HOCKEY_CREASE_M - 1.0), 0.9), max_in)


func _threat() -> bool:
	var v := ball.vel2()
	return v.x * dir < -Tuning.HOCKEY_THREAT_SPEED and ball.pos2().x * dir < my_pos().x * dir


func _goalie_point(b: Vector2) -> Vector2:
	var r: Dictionary = sm.rules()
	var mouth := Vector2(-dir * float(r["goal_x"]), float(r["goal_h"]) * 0.5)
	var to_b := b - mouth
	var p := mouth + (to_b.normalized() if to_b.length() > 0.01 else Vector2(dir, 0.0)) * Tuning.HOCKEY_GOALIE_OUT_M
	p.y = clampf(p.y, Tuning.HOCKEY_GOALIE_Y_MIN, float(r["goal_h"]) + 0.3)
	return p


## Путь в ворота (решено 22.10, BALANCE_2210.md): шайба ближе к моим воротам, чем я, — прямая к воротам идёт сквозь шайбу и
## нападающего за ней (вратарь ехал за ними по льду до самой линии); тогда — поверху: точка над шайбой на
## HOCKEY_GOALIE_OVER_M и за ней к воротам, пока не обогнал шайбу, дальше — на луч вратаря.
func _goalie_route(b: Vector2) -> Vector2:
	var gp := _goalie_point(b)
	var me := my_pos()
	if me.x * dir < b.x * dir - Tuning.HOCKEY_GOALIE_PASS_M or b.x * dir < gp.x * dir + Tuning.HOCKEY_GOALIE_PASS_M:
		return gp   # уже между шайбой и воротами — или шайба у самой линии, обгонять некуда
	var x := maxf((b.x - dir * Tuning.HOCKEY_GOALIE_PASS_M * 2.0) * dir, gp.x * dir) * dir
	return Vector2(x, maxf(b.y, 0.0) + Tuning.HOCKEY_GOALIE_OVER_M)


func _opponent() -> Doll:
	for d in sm.dolls():
		var dd := d as Doll
		if dd != doll and dd.alive and SportMatch.team_of(dd) != team:
			return dd
	return null
