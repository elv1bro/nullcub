## Мозг босса (docs/plan-demo/BOSS.md): чемпион лиги (LeagueBrain — восприятие с задержкой, управляемая рука тянется к цели), но
## поведение по фазе BossMatch.boss_phase:
##   • фаза 1 — наскоки и раскрутка: подход не быстрее APPROACH[ф]; ближе REACH_M — наскок (lunge: тяга в цель + ускорение) или
##     раскрутка (spin: Space + A/D к цели, request_spin) с вероятностью SPIN_P[ф]; потом отход (recover RECOVER_S[ф]);
##   • фаза 2 — рывки: цель в коридоре DASH_M — замах (windup WINDUP_S: босс замирает, игрок успевает уйти) и рывок (charge
##     CHARGE_S: ускорение в упреждённую точку), вплотную — наскоки как в фазе 1;
##   • фаза 3 — ярость: то же быстрее (тягу и скорость поднимает BossMatch), отход короче, раскрутка чаще.
## Заряд у босса не кончается (BossMatch держит пол BOSS_CHARGE_FLOOR[ф]). Для напарника-бота и HUD: threat() — замах/рывок/наскок/
## раскрутка сейчас (кукла-цель — target).
class_name BossBrain
extends LeagueBrain

const APPROACH := [3.2, 4.0, 5.2]
const REACH_M := 3.2
const LUNGE_S := 0.75
const SPIN_S := 1.1
const SPIN_P := [0.35, 0.25, 0.45]
const RECOVER_S := [1.1, 0.8, 0.45]
const DASH_M := Vector2(4.5, 13.0)
const DASH_COOLDOWN_S := [99.0, 2.8, 2.0]
const WINDUP_S := [0.55, 0.5, 0.35]
const CHARGE_S := 0.9

var bm: BossMatch
var spin_dir := 1.0
var _dash_cd := 1.5
var _charge_goal := Vector2.ZERO


func _brain_ready() -> void:
	reaction_s = 0.22
	aim_error_m = 0.35
	lead_s = 0.2
	go("approach")


func _find_match() -> void:
	if bm == null or not is_instance_valid(bm):
		bm = get_tree().get_first_node_in_group(Match.GROUP) as BossMatch


func phase_i() -> int:
	return clampi(bm.boss_phase - 1, 0, 2) if bm != null and is_instance_valid(bm) else 0


## Опасный приём сейчас: windup | charge | lunge | spin (иначе "").
func threat() -> String:
	return state if state in ["windup", "charge", "lunge", "spin"] else ""


func _think(delta: float) -> void:
	_find_match()
	if bm == null or bm.play_state != "play" or target == null or not is_instance_valid(target):
		go("idle")
		want = hover_vec()
		if arm != null:
			arm.clear_target_override()
		return
	var ph := phase_i()
	_dash_cd -= delta
	var tp := predicted()
	var me := my_pos()
	var d := me.distance_to(com2(target))
	match state:
		"lunge":
			want = steer(tp, 1.0)
			if state_t > LUNGE_S:
				go("recover")
		"spin":
			var to := tp - me
			spin_dir = signf(to.x) if absf(to.x) > 0.3 else spin_dir
			want = (to.normalized() * 0.6 + hover_vec()).limit_length(1.0)
			want.x = spin_dir * maxf(absf(want.x), 0.6)
			doll.request_spin()
			if state_t > SPIN_S:
				go("recover")
		"windup":
			want = hover_vec() + (me - tp).normalized() * 0.15   # замер и чуть назад — телеграф рывка
			_charge_goal = predicted(0.25)
			if state_t > float(WINDUP_S[ph]):
				go("charge")
				note_attack()
				dash()
		"charge":
			var dir := (_charge_goal - me)
			if dir.length() < 1.0 or state_t > CHARGE_S:
				go("recover")
			want = (dir.normalized() + hover_vec() * 0.5).limit_length(1.0)
			dash()
		"recover":
			var away := (me - tp).normalized() if me.distance_to(tp) > 0.01 else Vector2.UP
			want = steer(me + away * 2.0, 0.8)
			if state_t > float(RECOVER_S[ph]):
				go("approach")
		_:
			go("approach")
			want = steer_speed(tp, float(APPROACH[ph]))
			if ph >= 1 and _dash_cd <= 0.0 and d > DASH_M.x and d < DASH_M.y:
				_dash_cd = float(DASH_COOLDOWN_S[ph])
				go("windup")
			elif d < REACH_M:
				note_attack()
				if _rng.randf() < float(SPIN_P[ph]):
					spin_dir = signf(tp.x - me.x) if absf(tp.x - me.x) > 0.1 else 1.0
					go("spin")
				else:
					go("lunge")
					dash()
	if arm != null:
		arm.set_target_override(Vector3(tp.x, tp.y, 0.0))


func _stuck_allowed() -> bool:
	return state == "approach"
