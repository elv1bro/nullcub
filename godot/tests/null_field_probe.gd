## Гейт поля NULL и мембраны купола (арена 01 «Old NULL Hall», scenes/arena/null_field.gd; docs/plan-demo/ART_NULL.md).
##   godot --headless --path godot --fixed-fps 60 res://tests/null_field_probe.tscn
## Проверки числами (exit 1, если не прошли), отчёт — tests/null_field_probe_report.json:
##   gravity_default   шар без дампа 1 с в поле по умолчанию: скорость ≈ Tuning.GRAVITY вниз (±8 %)
##   gravity_side      поле 0.24 G влево сразу: скорость ≈ 0.24·9.81 влево, по вертикали ≈ 0
##   gravity_blend     смена поля плавная: на середине — между, через NULL_FIELD_BLEND_S — ровно цель, SHIFTING снят, табло пишет её
##   membrane_side     шар 10 м/с в бок купола при 0 G (низко, нормаль ≈ горизонтальна): растяжение 0.8…MAX, скорость отскока
##                     ≥ 0.9 и ≤ 1.4 от входа (мембрана возвращает энергию), через 3 с внутри
##   membrane_top      шар 8 м/с вверх при обычной гравитации: выше верха купола не дальше MAX, возвращается внутрь
##   doll_bounce       кукла 14 м/с в бок купола при 0 G: части растягивают мембрану > 0.3 м, ЦМ выходит за контур и возвращается, ни одна часть не дальше 3 м от ЦМ,
##                     нет NaN; мембрана светится у места удара (hits), сигнал membrane_hit был
##   bot_hover         бот (enemy_scrapling) в поле «влево»: hover_vec() смотрит против гравитации (вправо)
##   offscreen_marker  площадка playground_null_hall: кукла P2 за правым краем кадра → стрелка P2 с расстоянием
##   playground        площадка грузится, матч идёт, камера держит только P1 (P2 клавиш не нажимал) с полувысотой кадра
##                     4.2…5.5 м (боец ~21 % кадра; автор 02.10.2026 — «камера слишком далеко»)
extends Node

const HALL := preload("res://scenes/arena/null_hall.tscn")
const DOLL := preload("res://scenes/doll/doll.tscn")
const ENEMY := preload("res://scenes/enemies/enemy_scrapling.tscn")
const PLAYGROUND := preload("res://scenes/playground_null_hall.tscn")

var checks: Array = []
var info := {}
var hall: NullHallArena
var field: NullField


func _ready() -> void:
	await _run()


func _run() -> void:
	hall = HALL.instantiate() as NullHallArena
	add_child(hall)
	field = hall.field
	await _phys(2)
	await _gravity_default()
	await _gravity_side()
	await _gravity_blend()
	await _membrane_side()
	await _membrane_top()
	await _doll_bounce()
	await _bot_hover()
	hall.queue_free()
	await _phys(2)
	await _playground()
	_finish()


func _ball(pos: Vector3, vel: Vector3) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.mass = 1.0
	rb.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	rb.linear_damp = 0.0
	rb.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	rb.axis_lock_linear_z = true
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.2
	cs.shape = sh
	rb.add_child(cs)
	add_child(rb)
	rb.global_position = pos
	rb.linear_velocity = vel
	return rb


func _gravity_default() -> void:
	field.set_field(Tuning.GRAVITY / Tuning.G_EARTH, NullField.FALL, 0.0)
	var rb := _ball(Vector3(0.0, 12.0, 0.0), Vector3.ZERO)
	await _phys(60)
	var v := rb.linear_velocity
	info["gravity_default_v"] = [snappedf(v.x, 0.001), snappedf(v.y, 0.001)]
	_check("gravity_default", absf(v.y + Tuning.GRAVITY) < Tuning.GRAVITY * 0.08 and absf(v.x) < 0.05, "v = %s" % v)
	rb.queue_free()


func _gravity_side() -> void:
	field.set_field(0.24, Vector2.LEFT, 0.0)
	var rb := _ball(Vector3(0.0, 10.0, 0.0), Vector3.ZERO)
	await _phys(60)
	var v := rb.linear_velocity
	var want := 0.24 * Tuning.G_EARTH
	info["gravity_side_v"] = [snappedf(v.x, 0.001), snappedf(v.y, 0.001)]
	_check("gravity_side", absf(v.x + want) < want * 0.08 and absf(v.y) < 0.05, "v = %s (want x −%.2f)" % [v, want])
	rb.queue_free()


func _gravity_blend() -> void:
	field.set_field(0.0, NullField.FALL, 0.0)
	field.set_field(0.5, NullField.FALL)
	var half := int(Tuning.NULL_FIELD_BLEND_S * 0.5 * 60.0)
	await _phys(half)
	var mid := field.field_g
	var shifting_mid := field.is_shifting()
	await _process_frames(1)
	var board_mid := _board_text("null_hall_membrane")
	await _phys(int(Tuning.NULL_FIELD_BLEND_S * 60.0) - half + 3)
	await _process_frames(1)
	var end := field.field_g
	var board := _board_text("null_hall_gravity")
	info["gravity_blend"] = {"mid": snappedf(mid, 0.001), "end": snappedf(end, 0.001), "board": board, "board_mid": board_mid}
	_check("gravity_blend", mid > 0.1 and mid < 0.4 and shifting_mid and absf(end - 0.5) < 1e-3 and not field.is_shifting()
		and board == "↓ 0.50G" and board_mid == "FIELD: SHIFTING", "mid %.3f end %.3f board «%s» / «%s»" % [mid, end, board, board_mid])


func _membrane_side() -> void:
	field.set_field(0.0, NullField.FALL, 0.0)
	field.max_stretch_seen = 0.0
	var rb := _ball(Vector3(10.0, 2.0, 0.0), Vector3(10.0, 0.0, 0.0))   # низко: нормаль почти горизонтальна
	var v_in := 10.0
	var best_back := 0.0   # модуль скорости на отлёте (движение внутрь по x)
	for i in range(180):
		await _phys(1)
		var v := rb.linear_velocity
		if v.x < 0.0:
			best_back = maxf(best_back, Vector2(v.x, v.y).length())
	var stretch := field.max_stretch_seen
	var pen: float = field.stretch_at(Vector2(rb.global_position.x, rb.global_position.y))[0]
	# после отскока шар мог долететь до другой стороны и отскочить снова — важно только, что он внутри купола или у мембраны
	info["membrane_side"] = {"stretch": snappedf(stretch, 0.01), "back_speed": snappedf(best_back, 0.01), "pen_end": snappedf(pen, 0.01)}
	_check("membrane_side", stretch > 0.8 and stretch <= Tuning.MEMBRANE_MAX_STRETCH and best_back >= 0.9 * v_in
		and best_back <= 1.4 * v_in and pen < 0.5, "stretch %.2f m, back %.2f m/s (in %.1f), pen_end %.2f" % [stretch, best_back, v_in, pen])
	rb.queue_free()


func _membrane_top() -> void:
	field.set_field(Tuning.GRAVITY / Tuning.G_EARTH, NullField.FALL, 0.0)
	field.max_stretch_seen = 0.0
	var rb := _ball(Vector3(0.0, 15.0, 0.0), Vector3(0.0, 8.0, 0.0))
	var top := 0.0
	for i in range(150):
		await _phys(1)
		top = maxf(top, rb.global_position.y)
	var came_back := rb.global_position.y < field.axes.y
	info["membrane_top"] = {"top": snappedf(top, 0.01), "stretch": snappedf(field.max_stretch_seen, 0.01)}
	_check("membrane_top", top <= field.axes.y + Tuning.MEMBRANE_MAX_STRETCH and top > field.axes.y and came_back,
		"top %.2f m (dome %.1f), stretch %.2f" % [top, field.axes.y, field.max_stretch_seen])
	rb.queue_free()


func _doll_bounce() -> void:
	field.set_field(0.0, NullField.FALL, 0.0)
	field.max_stretch_seen = 0.0
	var fired := [0]
	var cb := func(_p: Vector2, _s: float) -> void: fired[0] += 1
	field.membrane_hit.connect(cb)
	var d := DOLL.instantiate() as Doll
	add_child(d)
	d.add_to_group("dolls")
	d.global_position = Vector3(10.0, 7.0, 0.0)
	await _phys(3)
	for b in d.parts.values():   # у куклы дамп ядра 2.25: с 14 м/с долетает ~6 м — до мембраны (x ≈ 14.9 на этой высоте)
		(b as RigidBody3D).linear_velocity = Vector3(14.0, 0.0, 0.0)
	var max_out := -99.0
	var torn := 0.0
	var nan := false
	var hit_w := 0.0
	for i in range(240):
		await _phys(1)
		var com := d.centre_of_mass()
		if is_nan(com.x) or is_nan(com.y):
			nan = true
			break
		var pen: float = field.stretch_at(Vector2(com.x, com.y))[0]
		max_out = maxf(max_out, pen)
		for b in d.parts.values():
			torn = maxf(torn, (b as RigidBody3D).global_position.distance_to(com))
		for h in field.hits:
			hit_w = maxf(hit_w, h.w)
	var com_end := d.centre_of_mass()
	var pen_end: float = field.stretch_at(Vector2(com_end.x, com_end.y))[0]
	info["doll_bounce"] = {"max_out": snappedf(max_out, 0.01), "pen_end": snappedf(pen_end, 0.01), "torn_m": snappedf(torn, 0.01),
		"stretch": snappedf(field.max_stretch_seen, 0.01), "hit_glow": snappedf(hit_w, 0.01), "hits_fired": fired[0]}
	_check("doll_bounce", not nan and field.max_stretch_seen > 0.3 and max_out > 0.0 and pen_end < 0.0 and torn < 3.0 and field.max_stretch_seen <= Tuning.MEMBRANE_MAX_STRETCH + 0.3
		and hit_w > 0.3 and fired[0] > 0, str(info["doll_bounce"]))
	field.membrane_hit.disconnect(cb)
	d.queue_free()
	await _phys(2)


func _bot_hover() -> void:
	field.set_field(0.24, Vector2.LEFT, 0.0)
	var e := ENEMY.instantiate() as Doll
	add_child(e)
	e.global_position = Vector3(0.0, 8.0, 0.0)
	await _phys(4)
	var brain: Node = null
	for c in e.get_children():
		if c.has_method("hover_vec"):
			brain = c
			break
	var hv: Vector2 = brain.call("hover_vec") if brain != null else Vector2.ZERO
	var gv: Vector2 = brain.call("gravity_vec") if brain != null else Vector2.ZERO
	info["bot_hover"] = {"hover": [snappedf(hv.x, 0.001), snappedf(hv.y, 0.001)], "gravity": [snappedf(gv.x, 0.001), snappedf(gv.y, 0.001)]}
	_check("bot_hover", brain != null and hv.x > 0.05 and absf(hv.y) < 0.02 and gv.x < -2.0, str(info["bot_hover"]))
	e.queue_free()
	field.set_field(Tuning.GRAVITY / Tuning.G_EARTH, NullField.FALL, 0.0)
	await _phys(2)


func _playground() -> void:
	var pg := PLAYGROUND.instantiate()
	add_child(pg)
	await _phys(150)
	var cam := pg.get_node("Camera") as DynamicCamera
	var m := pg.get_node("Match")
	var hh := cam.half_height
	var phase := str(m.get("phase"))
	var fd := cam.followed_dolls()
	var only_p1: bool = fd.size() == 1 and fd[0] == pg.get_node("P1")
	info["playground"] = {"half_height": snappedf(hh, 0.01), "phase": phase, "only_p1": only_p1}
	_check("playground", only_p1 and hh >= 4.2 - 0.01 and hh <= 5.5, "half_height %.2f, phase %s, в кадре только P1: %s" % [hh, phase, only_p1])
	# P2 далеко вправо за кадр: стрелка
	var p2 := pg.get_node("P2") as Doll
	var marks := pg.get_node("Offscreen")
	cam.set_process(false)
	cam.set_physics_process(false)
	cam.global_position = Vector3(-10.0, 8.0, 24.0)
	for b in p2.parts.values():
		(b as RigidBody3D).global_position += Vector3(24.0, 0.0, 0.0)
		(b as RigidBody3D).freeze = true
	await _process_frames(3)
	var found := {}
	for mk in marks.get("markers"):
		if int(mk["player"]) == 1:
			found = mk
	info["offscreen"] = found.duplicate() if not found.is_empty() else {}
	if not found.is_empty():
		info["offscreen"]["pos"] = [snappedf(found["pos"].x, 0.1), snappedf(found["pos"].y, 0.1)]
		info["offscreen"]["dir"] = [snappedf(found["dir"].x, 0.01), snappedf(found["dir"].y, 0.01)]
	var vp := get_viewport().get_visible_rect().size
	_check("offscreen_marker", not found.is_empty() and float(found["dist"]) > 15.0 and (found["pos"] as Vector2).x > vp.x * 0.8,
		str(info["offscreen"]))
	pg.queue_free()
	await _phys(2)


func _board_text(group: String) -> String:
	for l in get_tree().get_nodes_in_group(group):
		if hall.is_ancestor_of(l):
			return (l as Label3D).text
	return ""


func _phys(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _process_frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _check(id: String, ok: bool, text: String) -> void:
	checks.append({"id": id, "ok": ok, "info": text})
	print("%s %s — %s" % ["PASS" if ok else "FAIL", id, text])


func _finish() -> void:
	var ok := true
	for c in checks:
		ok = ok and bool(c["ok"])
	var f := FileAccess.open("res://tests/null_field_probe_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"ok": ok, "checks": checks, "info": info}, "  "))
	f.close()
	print("null_field_probe: %s (%d checks)" % ["OK" if ok else "FAIL", checks.size()])
	get_tree().quit(0 if ok else 1)
