## Бот-игрок против босса (docs/plan-demo/BOSS.md): напарник P2 (пока не нажата U) и оба игрока в пробе. Каркас — EnemyBrain (тяга с
## плавным разворотом, восприятие с задержкой и упреждением, стан — молчит, выход из застревания, ускорение за Заряд), без EnemyLook.
## Цель одна — босс (BossMatch.boss):
##   • attack — наскок в светящуюся деталь (BossMatch.weak_body; нет — в ЦМ босса) с упреждением, в коридоре DASH_M — с ускорением;
##   • back — после касания (вплотную CLOSE_M дольше HIT_S) отскок BACK_S: бить и уходить, а не висеть на боссе;
##   • dodge (уровни 2–3) — босс замахнулся на меня (BossBrain.threat windup/charge) или идёт волна (wave_warning_left ≥ 0 и я ближе
##     BOSS_WAVE_R + 1.5) — прочь от босса, вбок от линии рывка.
## Уровень 1..3 — Tuning.BOSS_BOT_LEVELS; Match.respawn_doll создаёт мозг заново без настроек — уровень из default_level.
class_name BossAllyBrain
extends EnemyBrain

const CLOSE_M := 2.6
const HIT_S := 0.35
const BACK_S := 0.5
const DASH_M := Vector2(2.5, 9.0)
const DODGE_M := 10.0
const DODGE_S := 0.7

static var default_level := 2

@export var level := -1

var bm: BossMatch
var max_in := 0.9
var use_dash := true
var use_dodge := true
var _close_t := 0.0
var _dodge_dir := Vector2.UP


func _setup() -> void:
	if _ready_done:
		return
	_ready_done = true
	doll.external_input = true
	arena = get_tree().get_first_node_in_group("arena")
	doll.knocked_out.connect(func(_a: Node, _r: Dictionary) -> void: _on_ko())
	_brain_ready()


func _brain_ready() -> void:
	players_group = "boss_nobody"
	enemies_group = "boss_nobody"
	var lv := level if level > 0 else default_level
	var p: Dictionary = Tuning.BOSS_BOT_LEVELS.get(lv, Tuning.BOSS_BOT_LEVELS[2])
	max_in = float(p["max_in"])
	aim_error_m = float(p["aim_error_m"])
	reaction_s = float(p["reaction_s"])
	lead_s = float(p["lead_s"])
	use_dash = bool(p["dash"])
	use_dodge = bool(p["dodge"])
	go("attack")


func _find_match() -> void:
	if bm == null or not is_instance_valid(bm):
		bm = get_tree().get_first_node_in_group(Match.GROUP) as BossMatch


func _boss() -> Doll:
	if bm == null or not is_instance_valid(bm.boss) or not bm.boss.alive or not bm.boss.is_inside_tree():
		return null
	return bm.boss


func players() -> Array:
	var b := _boss()
	return [b] if b != null else []


func _boss_threat() -> String:
	var b := _boss()
	if b == null:
		return ""
	for c in b.get_children():
		if is_instance_valid(c) and c is BossBrain:
			var bb := c as BossBrain
			return bb.threat() if bb.target == doll else ""
	return ""


func _think(delta: float) -> void:
	_find_match()
	var b := _boss()
	if bm == null or bm.play_state != "play" or b == null:
		go("idle")
		want = hover_vec()
		return
	if target != b:
		target = b
		_hist.clear()
		_record_target()
	var me := my_pos()
	var bc := com2(b)
	var away := me - bc
	var dist := away.length()
	var adir := away / dist if dist > 0.01 else Vector2.UP
	# уклон: волна или замах на меня
	if use_dodge and state != "dodge":
		var th := _boss_threat()
		var wave := bm.wave_warning_left() >= 0.0 and dist < Tuning.BOSS_WAVE_R + 1.5
		if wave or ((th == "windup" or th == "charge") and dist < DODGE_M):
			var side := Vector2(-adir.y, adir.x)
			if side.y < 0.0:
				side = -side   # вбок — лучше вверх (у пола не развернуться)
			_dodge_dir = (adir * (1.0 if wave else 0.4) + side * (0.3 if wave else 1.0)).normalized()
			go("dodge")
	match state:
		"dodge":
			want = (_dodge_dir * max_in + hover_vec()).limit_length(1.0)
			if use_dash and state_t < 0.1:
				dash()
			if state_t > DODGE_S:
				go("attack")
			return
		"back":
			want = steer(me + adir * 3.0, max_in)
			if state_t > BACK_S:
				go("attack")
			return
	if state != "attack":
		go("attack")
	# прицел: светящаяся деталь + упреждение/ошибка восприятия (сдвиг predicted() от ЦМ)
	var aim := predicted()
	var wb := bm.weak_body()
	if wb != null and is_instance_valid(wb):
		aim += Vector2(wb.global_position.x, wb.global_position.y) - bc
	var to := aim - me
	var dt := to.length()
	var dir := to / dt if dt > 0.01 else Vector2.UP
	want = (dir * max_in + hover_vec()).limit_length(1.0)
	if use_dash and dt > DASH_M.x and dt < DASH_M.y:
		if state_t > 0.2 and doll.charge >= DASH_START_CHARGE:
			note_attack()
		dash()
	if dist < CLOSE_M:
		_close_t += delta
		if _close_t > HIT_S:
			_close_t = 0.0
			go("back")
	else:
		_close_t = 0.0


func _stuck_allowed() -> bool:
	return state == "attack"
