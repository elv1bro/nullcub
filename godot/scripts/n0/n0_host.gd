## N0 рядом с игроком (автор 02.10.2026: «N0 летает в бою перед нами, а не за нами. Он должен быть всегда рядом и выдавать
## комментарии хотя бы субтитрами»; правила полёта — N0_VOICE.md, «N0 в кадре»). Ребёнок узла N0Drone на площадке купола.
## Полёт: точка на дуге радиуса orbit_r над плечом главной куклы кадра (DynamicCamera.primary_doll(), без камеры — P1) со стороны,
## где нет соперника; соперник перешёл на другую сторону — N0 перелетает дугой над головой. Глубина depth_z < 0 — за плоскостью
## боя: кукла всегда перед ним, он не заслоняет бой. Пружина с запаздыванием (spring_w), крен по скорости, взгляд — на игрока,
## на сильный удар — на точку удара, на KO — на поверженного; крит отбрасывает и крутит его. Соперник ближе dodge_r —
## уворачивается. Точка — внутри bounds() арены. Время игровое: в стоп-кадре удара он замирает вместе с миром.
## Реплики: поводы Match (отсчёт, крит, KO, голова, комбо, Sudden Death, ничья, победа по таймеру), удар о мембрану, голосование
## зрителей (AudienceVote), отлетевшая деталь, долгая тишина → N0Lines (частота по N0_VOICE.md) → облачко N0Speech.
## Выражение экрана — flash_expression на тех же поводах, к нему — жест тела (N0Drone.GESTURE_OF); скорость и ускорение полёта
## уходят в N0Drone.set_motion (крылья, ножки). Где соперник и сколько до него — не его дело: это стрелка HUD (offscreen_markers.gd;
## автор 02.10: «ведущий не может так подсказывать»). В бою не участвует: коллизий нет.
extends Node

## Дуга над плечом: радиус (м) и угол от вертикали (градусы) на своей стороне.
@export var orbit_r := 1.75
@export var orbit_deg := 55.0
## Скорость перелёта по дуге (рад/с) и порог смены стороны (м по X между игроком и соперником).
@export var arc_speed := 3.0
@export var side_switch_m := 1.2
## Плоскость полёта: за плоскостью боя (z = 0), дальше от камеры.
@export var depth_z := -1.4
## Пружина следования (1/с): запаздывание ~1/spring_w; потолок скорости растёт с отставанием.
@export var spring_w := 6.5
@export var max_speed := 20.0
## Дальше этого (м) — догнать сразу (респавн, рестарт).
@export var snap_m := 25.0
## Соперник ближе (м, в плоскости XY) — уворот.
@export var dodge_r := 1.6
@export var dolls_group := "dolls"
@export var hit_shocked_dmg := 12.0
## Мелкий повод «тишина»: без ударов quiet_s.
@export var quiet_s := 10.0
@export var membrane_line_speed := 5.0

var lines := N0Lines.new()
var speech: N0Speech
var target := Vector3.ZERO      # куда тянется сейчас (для проб)
var side := -1.0
var player: Node3D              # за кем летает (для проб)

var _drone: N0Drone
var _match: Node
var _vel := Vector3.ZERO
var _theta := 0.0
var _placed := false
var _quiet := 0.0
var _look_pos := Vector3.ZERO
var _look_t := 0.0
var _spin_t := -1.0
var _spin_dir := 1.0
var _parts_hooked := {}         # instance_id куклы → true


func _ready() -> void:
	_drone = get_parent() as N0Drone
	lines.rng.randomize()
	speech = N0Speech.new()
	speech.name = "Speech"
	add_child(speech)
	speech.drone = _drone
	_theta = side * deg_to_rad(orbit_deg)
	_connect.call_deferred()


func _connect() -> void:
	var root := _drone.get_parent() if _drone != null else null
	if root == null:
		return
	for c in root.get_children():
		if c.has_method("membrane_anchors") and c.get("field") != null:
			(c.get("field") as NullField).membrane_hit.connect(_on_membrane)
	_match = root.get_node_or_null("Match")
	if _match != null and _match.has_signal("hit"):
		_match.connect("phase_changed", _on_phase)
		_match.connect("announce", _on_announce)
		_match.connect("hit", _on_hit)
		_match.connect("hit_fx", _on_hit_fx)
		_match.connect("ko", _on_ko)
		_match.connect("match_over", _on_match_over)
	var vote := root.get_node_or_null("AudienceVote")
	if vote != null and vote.has_signal("vote_started"):
		vote.connect("vote_started", func(_o: Array) -> void: say("vote_start"))
		vote.connect("vote_finished", _on_vote_finished)
	var juice := _match.get_node_or_null("HitJuice") if _match != null else null
	if juice != null and juice.has_signal("juice_event"):
		juice.connect("juice_event", _on_juice_event)


## Повод → реплика (N0Lines решает, говорить ли) → облачко. Возвращает сказанный текст или "".
func say(event: String, args: Array = []) -> String:
	var now := Time.get_ticks_msec() / 1000.0
	var text := lines.pick(event, now, speech.speaking(), args)
	if text != "":
		speech.say(text)
	return text


func _react(expr: String, secs: float) -> void:
	if _drone != null:
		_drone.flash_expression(expr, secs)


# --- поводы ---

func _on_phase(p: int) -> void:
	if p == Match.Phase.COUNTDOWN:
		_quiet = 0.0
		_react("happy", 2.0)
		say("fight")


func _on_announce(text: String, _color: Color, kind: String) -> void:
	match kind:
		"head":
			say("head")
		"combo":
			if text.to_int() >= 4:
				say("combo")
		"sudden_death":
			_react("worried", 2.0)
			say("sudden_death")


func _on_hit(_v: Node, _a: Node, dmg: float, _k: String, _p: Vector3) -> void:
	_quiet = 0.0
	if dmg >= hit_shocked_dmg:
		_react("shocked", 1.2)


func _on_hit_fx(ctx: Dictionary) -> void:
	var tier := String(ctx.get("tier", ""))
	var pos: Vector3 = ctx.get("position", Vector3.ZERO)
	if tier == HitTier.CRIT or tier == HitTier.KO_CRIT:
		_look(pos, 1.4)
		_knock(pos)
		_react("shocked", 1.5)
		if tier == HitTier.CRIT:
			say("crit")
	elif tier == HitTier.HEAVY:
		_look(pos, 0.8)
		if ctx.get("victim") == player:
			say("ouch")


func _on_ko(victim: Node, _a: Node, _r: Dictionary) -> void:
	_react("sad" if victim == player else "excited", 2.5)
	if victim is Node3D and victim.has_method("centre_of_mass"):
		_look(victim.call("centre_of_mass"), 2.0)
	say("ko_player" if victim == player else "ko")


func _on_match_over(w: Node, results: Dictionary) -> void:
	if w == player or bool(results.get("draw", false)):
		_react("happy", 4.0)
	if bool(results.get("draw", false)):
		say("draw")
	elif String(results.get("reason", "")) == "timeout":
		say("decision")


func _on_membrane(_p: Vector2, speed: float) -> void:
	_react("excited", 1.6)
	if speed >= membrane_line_speed:
		say("membrane")


func _on_vote_finished(result: Dictionary) -> void:
	if bool(result.get("anomaly", false)):
		say("vote_anomaly")
	else:
		say("vote_result", [String(result.get("applied_title", "?"))])


func _on_part_detached(_part: String, _by: Node, doll: Node) -> void:
	if is_instance_valid(doll) and doll.get("alive") != false:   # разборка на KO — не повод
		say("part")


# --- полёт ---

func _process(delta: float) -> void:
	if _drone == null:
		return
	player = _main_doll()
	_hook_parts()
	if player == null:
		return
	var com: Vector3 = player.call("centre_of_mass")
	var opp := _nearest_opponent(com)
	if opp != null:
		var dx: float = (opp.call("centre_of_mass") as Vector3).x - com.x
		if absf(dx) > side_switch_m:
			side = -signf(dx)
	_theta = move_toward(_theta, side * deg_to_rad(orbit_deg), arc_speed * delta)
	target = Vector3(com.x + sin(_theta) * orbit_r, com.y + cos(_theta) * orbit_r, depth_z)
	target = _dodge(target)
	target = _clamp_bounds(target)
	var pos := _drone.global_position
	if not _placed or pos.distance_to(target) > snap_m:
		# первый кадр: влетает из-за края своей стороны
		_drone.global_position = target + Vector3(side * 6.0, 2.5, 0.0) if not _placed else target
		_vel = Vector3.ZERO
		_placed = true
		pos = _drone.global_position
	var acc := (target - pos) * spring_w * spring_w - _vel * 2.0 * spring_w
	var prev_vel := _vel
	_vel += acc * delta
	_vel = _vel.limit_length(max_speed * (1.0 + pos.distance_to(target) / 6.0))
	_drone.global_position = pos + _vel * delta
	_orient(delta, com)
	_drone.set_motion(_vel, (_vel - prev_vel) / maxf(delta, 1e-4))
	_drone.talking = speech.typing()
	_tick_lines(delta)


## Главная кукла: DynamicCamera.primary_doll(); без неё — кукла группы с наименьшим player_index.
func _main_doll() -> Node3D:
	var cam := _drone.get_viewport().get_camera_3d()
	if cam != null and cam.has_method("primary_doll"):
		var p: Node3D = cam.call("primary_doll")
		if p != null:
			return p
	var best: Node3D = null
	for d in _drone.get_tree().get_nodes_in_group(dolls_group):
		if d is Node3D and d.has_method("centre_of_mass"):
			if best == null or int(d.get("player_index")) < int(best.get("player_index")):
				best = d
	return best


func _nearest_opponent(com: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for d in _drone.get_tree().get_nodes_in_group(dolls_group):
		if d == player or not (d is Node3D) or not d.has_method("centre_of_mass") or d.get("alive") == false:
			continue
		var dd := com.distance_to(d.call("centre_of_mass") as Vector3)
		if dd < best_d:
			best_d = dd
			best = d
	return best


## Соперник (любая чужая кукла) рядом с точкой — точка отходит от него в плоскости XY.
func _dodge(p: Vector3) -> Vector3:
	for d in _drone.get_tree().get_nodes_in_group(dolls_group):
		if d == player or not (d is Node3D) or not d.has_method("centre_of_mass"):
			continue
		var c: Vector3 = d.call("centre_of_mass")
		var v := Vector2(p.x - c.x, p.y - c.y)
		var l := v.length()
		if l < dodge_r:
			var n := v / l if l > 1e-3 else Vector2(side, 1.0).normalized()
			p += Vector3(n.x, n.y, 0.0) * (dodge_r - l)
	return p


func _clamp_bounds(p: Vector3) -> Vector3:
	var cam := _drone.get_viewport().get_camera_3d()
	if cam == null or not cam.has_method("bounds"):
		return p
	var b: AABB = cam.call("bounds")
	var m := 1.0
	return Vector3(clampf(p.x, b.position.x + m, b.end.x - m), clampf(p.y, b.position.y + m, b.end.y - m), p.z)


func _look(pos: Vector3, secs: float) -> void:
	_look_pos = pos
	_look_t = secs


## Крит: ударная волна отбрасывает N0 от точки удара, он крутится и выравнивается.
func _knock(pos: Vector3) -> void:
	var away := _drone.global_position - pos
	away.z = 0.0
	away = away.normalized() if away.length() > 1e-3 else Vector3(side, 0.5, 0.0).normalized()
	_vel += away * 7.0
	_spin_t = 0.0
	_spin_dir = -signf(away.x) if absf(away.x) > 1e-3 else 1.0


func _orient(delta: float, com: Vector3) -> void:
	var look := com
	if _look_t > 0.0:
		_look_t -= delta
		look = _look_pos
	var to := look - _drone.global_position
	var flat := Vector2(to.x, to.z).length()
	var k := clampf(delta * 5.0, 0.0, 1.0)
	# лицо-экран смотрит в +Z (к камере): поворот к цели вполсилы — экран остаётся читаемым
	var yaw := clampf(atan2(to.x, maxf(to.z, 0.3)) * 0.6, -0.65, 0.65)
	var pitch := clampf(atan2(-to.y, maxf(flat, 0.3)) * 0.4, -0.35, 0.35)
	var roll := clampf(-_vel.x * 0.035, -0.3, 0.3)
	if _spin_t >= 0.0:
		_spin_t += delta
		var u := clampf(_spin_t / 0.7, 0.0, 1.0)
		roll += _spin_dir * TAU * (1.0 - pow(1.0 - u, 3.0))
		if u >= 1.0:
			_spin_t = -1.0
	_drone.rotation = Vector3(lerp_angle(_drone.rotation.x, pitch, k), lerp_angle(_drone.rotation.y, yaw, k),
		roll if _spin_t >= 0.0 else lerp_angle(_drone.rotation.z, roll, k))


# --- мелкие поводы по времени ---

func _tick_lines(delta: float) -> void:
	var fighting := _match != null and (int(_match.get("phase")) == Match.Phase.FIGHT or int(_match.get("phase")) == Match.Phase.SUDDEN_DEATH)
	if not fighting:
		_quiet = 0.0
		return
	_quiet += delta
	if _quiet >= quiet_s:
		_quiet = 0.0
		_react("curious", 1.5)
		say("quiet")


## Отлетевшие детали: подписка на Doll.part_detached у каждой куклы (новые куклы после рестарта — тоже).
func _hook_parts() -> void:
	for d in _drone.get_tree().get_nodes_in_group(dolls_group):
		var id := (d as Object).get_instance_id()
		if _parts_hooked.has(id) or not d.has_signal("part_detached"):
			continue
		_parts_hooked[id] = true
		d.connect("part_detached", _on_part_detached.bind(d))


## Поводы сока удара (HitJuice.juice_event, HIT_FX.md §13): большая цифра-обломок, искры железа, деталь в сколах, гора цифр.
## Все мелкие — частоту решает N0Lines; выражение и жест — на сильные.
func _on_juice_event(event: String, args: Array) -> void:
	match event:
		"digit_big":
			_react("shocked", 1.0)
		"metal":
			_react("excited", 1.0)
		"worn":
			_react("worried", 1.4)
	say(event, args)
