## Мозг врага PvE (LORE.md «Враги: профессия → сломанная программа → физика», CONCEPT_V2 §3, §29) — общий каркас.
## Узел-ребёнок куклы врага (ModularDoll с external_input = true, сцены scenes/enemies/*.tscn): каждый физический тик пишет
## doll.input_vec — та же тяга на торс, что у игрока (управлять врагом «честнее», чем двигать тела напрямую). База — бот-наскок
## tests/match_probe.gd, но бот не идеален:
##   • цель — ближайшая живая кукла группы players_group (пересмотр раз в RETARGET_S, новая цель должна быть ближе на
##     RETARGET_MARGIN_M — не дёргается между двумя игроками);
##   • восприятие с задержкой reaction_s: мозг видит позицию и скорость цели из прошлого (кольцевой буфер по тикам) + упреждение
##     lead_s по этой скорости + ошибка прицела aim_error_m (случайный сдвиг, новый раз в AIM_NOISE_S);
##   • ввод меняется не мгновенно: input_vec догоняет желаемый со скоростью input_slew (1/с) — разворот «на пятке» занимает
##     1/input_slew секунды, как у живого игрока на стике;
##   • стан, KO, падение из желоба (activate(delay)) — мозг молчит (ввод 0, _silenced() сбрасывает поведение);
##   • пропасть арены (pit_rect) — сам в неё не лезет: над провалом ниже PIT_SAFE_Y держит тягу вверх (выбить туда — можно).
## Поведение — наследники (sweeper_brain.gd, scrapling_brain.gd): state + state_t, _think(delta) пишет want (желаемый ввод),
## телеграф через EnemyLook: поза + свет глаз + звук-заглушка + надпись над головой (HUD) не короче telegraph_s.
## Хуки куклы (сессия настройки куклы, 29.09): Doll.request_dash() — через has_method, без него рывка нет (наскок тягой);
## Doll.team — ставит WaveDirector ("tower"): урон по своим × Tuning.TEAM_DAMAGE_MULT, толчки полные.
class_name EnemyBrain
extends Node

const RETARGET_S := 0.5
const RETARGET_MARGIN_M := 1.5
const AIM_NOISE_S := 0.6
const HISTORY_S := 1.0                  # буфер восприятия (не меньше максимального reaction_s)
const PIT_SAFE_Y := 1.4                 # над пропастью ниже этого — тяга вверх
const PIT_MARGIN_X := 0.8
const STEER_KP := 1.1                   # 1/м: ошибка 1 м — почти полная тяга
const STEER_KD := 0.32                  # с/м: гасит подлёт (без него враг проскакивает цель)
## Застрял (жмёт тягу ≥ STUCK_INPUT, а ЦМ почти стоит STUCK_S): прыжок вверх-вбок UNSTICK_S — упёрся в куклу, лежит на ней, в куче.
const STUCK_INPUT := 0.5
const STUCK_SPEED := 0.35
const STUCK_S := 0.8
const UNSTICK_S := 0.6
const DASH_REQ_S := 0.6
const FAR_M := 6.0                      # метрика stat.far_s: дальше этого от цели — «не охотится»
const DASH_ALIGN := 0.8                 # рывок — только когда ввод уже смотрит, куда надо (иначе рывок несёт по старому курсу)
## Разнос врагов (boids-separation): свои ближе SEP_R_M отталкивают с весом до SEP_GAIN — иначе двое, бегущие к одному игроку,
## сталкивались и дрались друг с другом (урон по своим × 0.25, но отброс, стан и отдача полные — волна 1 «зависала»).
const SEP_R_M := 1.7
const SEP_GAIN := 0.9                   # у цели (near_target 3 м) наследники берут 0.3–0.4 от этого
@export var enemies_group := "enemies"

## Задержка восприятия (с): чем больше, тем «тупее» враг — бьёт туда, где цель была.
@export var reaction_s := 0.25
## Упреждение (с) по воспринятой скорости цели.
@export var lead_s := 0.25
## Ошибка прицела (м).
@export var aim_error_m := 0.3
## Скорость изменения ввода (1/с).
@export var input_slew := 6.0
## Длительность телеграфа (с) — игрок должен успеть увидеть, что сейчас будет.
@export var telegraph_s := 0.4
@export var players_group := "players"

var doll: Doll
var look: EnemyLook
var target: Doll = null
var state := "idle"
var state_t := 0.0
## Желаемый ввод этого тика (наследник пишет в _think), до сглаживания и страховки от пропасти.
var want := Vector2.ZERO
## Журнал для проб: [{state, t}] смен состояний (последние 64) и счётчики.
var trace: Array = []
var counters: Dictionary = {}
## Метрики агрессии (пробы, отзыв автора «как будто не видят»): с момента, когда мозг включился (после желоба), пока кукла жива:
## active_s — время работы мозга, target_s — из него с живой целью, far_s — из него дальше FAR_M от цели, dist_int — ∫ дистанции,
## attacks — начатых атак (note_attack: заметание, бросок, щипок), first_attack_s — от включения до первой атаки (−1 — не было),
## silent_s — время в стане.
var stat := {"active_s": 0.0, "target_s": 0.0, "far_s": 0.0, "dist_int": 0.0, "attacks": 0, "first_attack_s": -1.0, "silent_s": 0.0}
var arena: Node = null
var _active_at := 0.0
var _time := 0.0
var _hist: Array = []                   # [t, pos: Vector2, vel: Vector2] цели
var _retarget_t := 0.0
var _noise := Vector2.ZERO
var _noise_t := 0.0
var _rng := RandomNumberGenerator.new()
var _silent := false
var _ready_done := false
var _stuck_t := 0.0
var _unstick_until := -1.0
var _unstick_dir := Vector2.UP
var _dash_want_until := -1.0
var _snap_until := -1.0


func _ready() -> void:
	doll = get_parent() as Doll
	if doll == null:
		push_error("EnemyBrain must be a child of Doll")
		return
	_rng.seed = hash(String(doll.name)) ^ 0x5eed
	if doll.is_node_ready():
		_setup()
	else:
		doll.ready.connect(_setup, CONNECT_ONE_SHOT)


func _setup() -> void:
	if _ready_done:
		return
	_ready_done = true
	doll.external_input = true   # запас HP — Doll.max_hp (ставится в сцене врага до add_child: 25 / 50)
	look = EnemyLook.new()
	look.name = "EnemyLook"
	doll.add_child(look)
	look.setup(doll)
	arena = get_tree().get_first_node_in_group("arena")
	doll.damaged.connect(_on_damaged)
	doll.knocked_out.connect(func(_a: Node, _r: Dictionary) -> void: _on_ko())
	_brain_ready()


## Мозг молчит delay секунд (падение из желоба): ввод 0, потом — поведение с начала.
func activate(delay: float) -> void:
	_active_at = _time + maxf(delay, 0.0)


func is_active() -> bool:
	return _time >= _active_at


# --- виртуальные ---

func _brain_ready() -> void:
	pass


## Поведение: состояние, want, телеграф. target — живая цель (может быть null).
func _think(_delta: float) -> void:
	want = Vector2.ZERO


## Стан / KO / падение: поведение сброшено (отпустить захваты и т. п.).
func _silenced(_why: String) -> void:
	pass


func _on_damaged(_amount: float, _attacker: Node, _part: String, _pos: Vector3, _kind: String) -> void:
	pass


func _on_ko() -> void:
	_silenced("ko")


# --- тик ---

func _physics_process(delta: float) -> void:
	_time += delta
	if doll == null or not _ready_done:
		return
	if not doll.alive:
		doll.input_vec = Vector2.ZERO
		if look != null:
			look.alert_target = 0.0
		return
	state_t += delta
	_retarget_t -= delta
	if _retarget_t <= 0.0:
		_retarget_t = RETARGET_S
		_pick_target()
	_record_target()
	var silent_why := ""
	if not is_active():
		silent_why = "spawn"
	elif doll.is_stunned():
		silent_why = "stun"
	if silent_why == "stun":
		stat["silent_s"] = float(stat["silent_s"]) + delta
	if silent_why != "":
		if not _silent:
			_silent = true
			_silenced(silent_why)
			go("stagger" if silent_why == "stun" else "idle")
		doll.input_vec = doll.input_vec.move_toward(Vector2.ZERO, input_slew * delta)
		if look != null:
			look.alert_target = 0.0
		return
	_silent = false
	_tick_stat(delta)
	_noise_t -= delta
	if _noise_t <= 0.0:
		_noise_t = AIM_NOISE_S
		_noise = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)).limit_length(1.0) * aim_error_m
	want = Vector2.ZERO
	_think(delta)
	want += separation() * _separation_weight()
	_tick_stuck(delta)
	_tick_dash()
	var w := _pit_guard(want).limit_length(1.0)
	if _time < _snap_until:
		doll.input_vec = w   # рефлекс (бегство с добычей): без сглаживания ввода
	else:
		doll.input_vec = doll.input_vec.move_toward(w, input_slew * delta)


## Отталкивание от своих (кроме тех, кто уже KO), м → ввод.
func separation() -> Vector2:
	var me := my_pos()
	var out := Vector2.ZERO
	for n in get_tree().get_nodes_in_group(enemies_group):
		if n == doll or not (n is Doll) or not (n as Doll).alive or not n.is_inside_tree():
			continue
		var d := me - com2(n)
		var l := d.length()
		if l < SEP_R_M and l > 0.01:
			out += d / l * (1.0 - l / SEP_R_M)
	return out.limit_length(1.0) * SEP_GAIN


## Цель ближе m (по ЦМ сейчас): у цели разнос со своими слабее — не расталкиваются прочь от игрока.
func near_target(m: float) -> bool:
	return target != null and is_instance_valid(target) and target.alive and my_pos().distance_to(com2(target)) < m


## Вес разноса в текущем состоянии (наследник: в броске — меньше).
func _separation_weight() -> float:
	return 1.0


## В каких состояниях застревание лечится прыжком (наследник: только перемещения — не в заметании и не в хвате).
## Ввод без сглаживания seconds секунд (рефлекс: рывок прочь с добычей).
func snap_input(seconds: float) -> void:
	_snap_until = _time + seconds


func _stuck_allowed() -> bool:
	return state in ["approach", "flee", "retreat", "choose", "idle"]


func _tick_stuck(delta: float) -> void:
	if _time < _unstick_until:
		want = _unstick_dir
		return
	if _stuck_allowed() and want.length() >= STUCK_INPUT and my_vel().length() < STUCK_SPEED:
		_stuck_t += delta
	else:
		_stuck_t = 0.0
	if _stuck_t >= STUCK_S:
		_stuck_t = 0.0
		_unstick_until = _time + UNSTICK_S
		var sx := -signf(want.x) if absf(want.x) > 0.2 else (1.0 if _rng.randf() < 0.5 else -1.0)
		_unstick_dir = Vector2(sx * 0.6, 0.9)
		counters["unstick"] = int(counters.get("unstick", 0)) + 1


func _tick_stat(delta: float) -> void:
	stat["active_s"] = float(stat["active_s"]) + delta
	if target == null or not is_instance_valid(target) or not target.alive:
		return
	stat["target_s"] = float(stat["target_s"]) + delta
	var d := my_pos().distance_to(com2(target))
	stat["dist_int"] = float(stat["dist_int"]) + d * delta
	if d > FAR_M:
		stat["far_s"] = float(stat["far_s"]) + delta


## Наследник зовёт в начале каждой атаки (метрики агрессии).
func note_attack() -> void:
	stat["attacks"] = int(stat["attacks"]) + 1
	if float(stat["first_attack_s"]) < 0.0:
		stat["first_attack_s"] = snappedf(_time - _active_at, 0.01)


func go(s: String) -> void:
	if s == state:
		return
	state = s
	state_t = 0.0
	counters[s] = int(counters.get(s, 0)) + 1
	trace.append({"state": s, "t": snappedf(_time, 0.01)})
	if trace.size() > 64:
		trace.pop_front()


# --- цель и восприятие ---

func players() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group(players_group):
		if n is Doll and (n as Doll).alive and n.is_inside_tree():
			out.append(n)
	return out


func _pick_target() -> void:
	var me := my_pos()
	var best: Doll = null
	var best_d := INF
	for p in players():
		var d := me.distance_to(com2(p))
		if d < best_d:
			best_d = d
			best = p
	if best == null:
		target = null
		_hist.clear()
		return
	if target != null and is_instance_valid(target) and target.alive and target != best:
		if me.distance_to(com2(target)) <= best_d + RETARGET_MARGIN_M:
			return
	if best != target:
		target = best
		_hist.clear()


func _record_target() -> void:
	if target == null or not is_instance_valid(target) or not target.alive:
		target = null
		return
	var t := target.torso() if target.parts.has("Torso") else null
	var v := Vector2.ZERO
	if t != null:
		v = Vector2(t.linear_velocity.x, t.linear_velocity.y)
	_hist.append([_time, com2(target), v])
	while _hist.size() > 2 and _time - float(_hist[0][0]) > HISTORY_S:
		_hist.pop_front()


## Воспринятое состояние цели: [pos, vel] из прошлого (reaction_s назад).
func seen() -> Array:
	if _hist.is_empty():
		return [my_pos(), Vector2.ZERO]
	var want_t := _time - reaction_s
	for i in range(_hist.size() - 1, -1, -1):
		if float(_hist[i][0]) <= want_t:
			return [_hist[i][1], _hist[i][2]]
	return [_hist[0][1], _hist[0][2]]


## Куда целиться: воспринятая позиция + упреждение по воспринятой скорости + ошибка прицела.
func predicted(extra_lead: float = 0.0) -> Vector2:
	var s := seen()
	return (s[0] as Vector2) + (s[1] as Vector2) * (lead_s + extra_lead) + _noise


# --- движение ---

## Желаемый ввод к точке goal: PD по ЦМ (ошибка − скорость) + компенсация веса, не больше max_in.
func steer(goal: Vector2, max_in: float = 1.0) -> Vector2:
	var e := goal - my_pos()
	var v := my_vel()
	var w := e * STEER_KP - v * STEER_KD
	w += hover_vec()
	return w.limit_length(max_in)


## Желаемый ввод «подойти к goal не быстрее max_speed м/с»: регулятор скорости (а не позиции) — аккуратный подход вплотную,
## без разгона на 5 м/с (Разборщик, влетая в молот игрока, бил сам себя: урон оружия считается и по скорости того, кто в него врезался).
func steer_speed(goal: Vector2, max_speed: float, max_in: float = 1.0) -> Vector2:
	var e := goal - my_pos()
	var l := e.length()
	var v_des := e / l * minf(max_speed, l * 2.5) if l > 0.01 else Vector2.ZERO
	var w := (v_des - my_vel()) * 0.45
	w += hover_vec()
	return w.limit_length(max_in)


## Ввод, при котором тяга держит вес куклы против гравитации у неё (вектор): поле арены NULL (Area3D, NullField) может тянуть
## вбок и вверх, без поля — Tuning.GRAVITY вниз. У тяжёлой сборки ввод больше.
func hover_vec() -> Vector2:
	var thrust := Tuning.MOVE_FORCE_PER_KG * doll.thrust_mass()
	return (-gravity_vec() * doll.total_mass / maxf(thrust, 1.0)).limit_length(0.9)


## Вертикальная часть hover_vec() (старый API: sweeper_brain и прочие, кто складывает только y).
func hover_input() -> float:
	return hover_vec().y


## Гравитация, которая действует на куклу сейчас (м/с², плоскость XY): total_gravity тела торса/ядра — с учётом Area3D.
func gravity_vec() -> Vector2:
	var body: RigidBody3D = doll.parts.get("Torso", null) if doll != null else null
	if body == null and doll != null and not doll.parts.is_empty():
		body = doll.parts.values()[0]
	if body != null:
		var st := PhysicsServer3D.body_get_direct_state(body.get_rid())
		if st != null:
			var g := st.total_gravity
			return Vector2(g.x, g.y)
	return Vector2(0.0, -Tuning.GRAVITY)


## Над пропастью ниже PIT_SAFE_Y — тяга вверх: враг сам в провал не лезет (выбить туда можно — в полёте после удара тяга
## не разгоняет, а только рулит).
func _pit_guard(w: Vector2) -> Vector2:
	var pr := pit_rect()
	if pr.size.x <= 0.0:
		return w
	var me := my_pos()
	if me.x > pr.position.x - PIT_MARGIN_X and me.x < pr.end.x + PIT_MARGIN_X and me.y < PIT_SAFE_Y:
		w.y = maxf(w.y, 0.9)
	return w


func pit_rect() -> Rect2:
	if arena != null and is_instance_valid(arena):
		var r: Variant = arena.get("pit_rect")
		if r is Rect2:
			return r
	return Rect2()


func arena_bounds() -> AABB:
	if arena != null and is_instance_valid(arena) and arena.has_method("bounds"):
		return arena.call("bounds")
	return AABB(Vector3(-18, -6, -1), Vector3(36, 20, 2))


## Направление «к пропасти» от точки p (−1 / +1 по x); без пропасти — к ближнему краю арены.
func pit_dir_from(p: Vector2) -> float:
	var pr := pit_rect()
	if pr.size.x > 0.0:
		return -1.0 if p.x > pr.get_center().x else 1.0
	var b := arena_bounds()
	return -1.0 if p.x - b.position.x < b.end.x - p.x else 1.0


## Рывок (хук Doll.request_dash: флаг на один тик, правила кнопки — кулдаун, не в стане, не в отдаче). Запрос держится DASH_REQ_S:
## в тик отдачи после удара рывок не пропадает. Без хука — false (наскок просто тягой).
func dash() -> bool:
	if not doll.has_method("request_dash"):
		return false
	_dash_want_until = _time + DASH_REQ_S
	counters["dash_req"] = int(counters.get("dash_req", 0)) + 1
	return true


func _tick_dash() -> void:
	if _time >= _dash_want_until:
		return
	if doll.is_dashing():
		_dash_want_until = -1.0
		counters["dash"] = int(counters.get("dash", 0)) + 1
		return
	var iv := doll.input_vec
	if want.length() > 0.3 and iv.length() > 0.5 and iv.normalized().dot(want.normalized()) >= DASH_ALIGN:
		doll.call("request_dash")


# --- помощники ---

static func com2(d: Doll) -> Vector2:
	var c := d.centre_of_mass()
	return Vector2(c.x, c.y)


func my_pos() -> Vector2:
	return com2(doll)


func my_vel() -> Vector2:
	var t := doll.torso()
	return Vector2(t.linear_velocity.x, t.linear_velocity.y)


func target_pos() -> Vector2:
	return com2(target) if target != null and is_instance_valid(target) else my_pos()


## Телеграф: свет глаз (alert держит наследник), надпись и звук.
func telegraph(text: String, seconds: float, sound: String, colour := Color(1.0, 0.55, 0.2)) -> void:
	counters["callout"] = int(counters.get("callout", 0)) + 1
	if look != null:
		look.telegraph(text, seconds, sound, colour)


func set_alert(v: float) -> void:
	if look != null:
		look.alert_target = clampf(v, 0.0, 1.0)


## Имена суставов стороны руки (кисть hand_name → её Wrist/Elbow/Shoulder по doll.joints: node_b — ребёнок).
func arm_joints(hand_name: String) -> Dictionary:
	var out := {}
	var body: Node = doll.parts.get(hand_name)
	var guard := 0
	while body != null and guard < 6:
		guard += 1
		var up: Generic6DOFJoint3D = null
		for j in doll.joints.values():
			var jj := j as Generic6DOFJoint3D
			if jj != null and is_instance_valid(jj) and jj.get_node_or_null(jj.node_b) == body:
				up = jj
				break
		if up == null:
			break
		var g := String(up.name).split("_")[0]
		if g == "Neck" or g == "Hip":
			break
		out[g] = String(up.name)
		body = up.get_node_or_null(up.node_a)
	return out
