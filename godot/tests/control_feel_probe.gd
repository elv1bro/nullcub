## Проба «чувства управления» (ControlFeel, headless): как ведёт себя кукла в каждом варианте управления и темпе — числа вместо «вроде норм».
## Запуск: godot --headless --path godot --fixed-fps 60 res://tests/control_feel_probe.tscn -- "variants=body|head,tempos=now|action,out=<путь JSON>"
##   variants / tempos — подмножество (по умолчанию все); strict=1 — инварианты валят exit (кукла не взорвалась, управление отвечает).
## Сценарий на конфиг (кукла doll.tscn на плоском полу, external_input, Doll.input_vec):
##   покой 1 с → вправо 2 с (v 0.25/0.5/1/2 с, макс. скорость ЦМ, макс. наклон торса, макс. скорость частей / ЦМ = «хлёсткость») →
##   разворот влево 2 с (за сколько секунд ЦМ меняет знак, и за сколько доходит до −3 м/с) → отпустить: остановка (до 0.3 м/с, путь) →
##   ускорение (request_dash) вправо 1.2 с: пик → покой 1.5 с: наклон торса в конце (встала ли).
## Отчёт: tests/control_feel_probe_report.json (или out=) + таблица в stdout. Это замер, не гейт: инварианты — нет NaN, не провалилась
## сквозь пол, вправо кукла реально сдвинулась.
extends Node3D

const SETTLE_S := 1.0
const RIGHT_S := 2.0
const LEFT_S := 2.0
const COAST_S := 3.0
const DASH_S := 1.2
const END_S := 1.5

var variants: Array = ControlFeel.VARIANT_ORDER.duplicate()
var tempos: Array = ControlFeel.TEMPO_ORDER.duplicate()
var out_path := "res://tests/control_feel_probe_report.json"
var strict := false

var _queue: Array = []
var _doll: Doll = null
var _t := 0.0
var _m := {}
var _s := {}
var _rows: Array = []
var _checks: Array = []
var _cur := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			match p[0]:
				"variants": variants = Array(p[1].split("|"))
				"tempos": tempos = Array(p[1].split("|"))
				"out": out_path = p[1]
				"strict": strict = p[1] != "0"
	for v in variants:
		for tp in tempos:
			_queue.append([String(v), String(tp)])
	_make_floor()
	_next()


func _make_floor() -> void:
	var f := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(80, 1, 10)
	cs.shape = bs
	f.add_child(cs)
	f.position = Vector3(0, -0.5, 0)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	f.physics_material_override = pm
	add_child(f)


func _next() -> void:
	if _doll != null:
		remove_child(_doll)
		_doll.queue_free()
		_doll = null
	if _queue.is_empty():
		_finish()
		return
	_cur = {"variant": _queue[0][0], "tempo": _queue[0][1]}
	_queue.pop_front()
	ControlFeel.reset()
	ControlFeel.set_variant(String(_cur["variant"]))
	ControlFeel.set_tempo(String(_cur["tempo"]))
	_doll = (load("res://scenes/doll/doll.tscn") as PackedScene).instantiate()
	_doll.external_input = true
	_doll.position = Vector3(0, 0.05, 0)
	add_child(_doll)
	_t = 0.0
	_m = {}
	_s = {}


func _com_v() -> Vector3:
	var mv := Vector3.ZERO
	var mt := 0.0
	for b in _doll.parts.values():
		var rb := b as RigidBody3D
		mv += rb.linear_velocity * rb.mass
		mt += rb.mass
	return mv / maxf(mt, 0.001)


func _tilt_deg() -> float:
	var t := _doll.torso()
	return absf(rad_to_deg(atan2(t.global_basis.x.y, t.global_basis.x.x)))


func _physics_process(delta: float) -> void:
	if _doll == null:
		return
	_t += delta
	var v := _com_v()
	var com := _doll.centre_of_mass()
	if not (is_finite(com.x) and is_finite(com.y)):
		_checks.append({"id": "finite_%s_%s" % [_cur["variant"], _cur["tempo"]], "ok": false})
		_m["exploded"] = true
		_end()
		return
	_s["min_y"] = minf(float(_s.get("min_y", 99.0)), com.y)
	var t0 := SETTLE_S
	var t1 := t0 + RIGHT_S
	var t2 := t1 + LEFT_S
	var t3 := t2 + COAST_S
	var t4 := t3 + DASH_S
	var t5 := t4 + END_S
	_doll.input_vec = Vector2.ZERO
	if _t < t0:
		_s["x0"] = com.x
		return
	if _t < t1:
		_doll.input_vec = Vector2(1, 0)
		var since := _t - t0
		for mark in [0.25, 0.5, 1.0, 2.0]:
			var key := "v_%s" % str(mark).replace(".", "p")
			if not _m.has(key) and since >= mark - 0.001:
				_m[key] = snappedf(v.x, 0.01)
		_s["vmax"] = maxf(float(_s.get("vmax", 0.0)), v.x)
		_s["tilt_max"] = maxf(float(_s.get("tilt_max", 0.0)), _tilt_deg())
		_s["limb_max"] = maxf(float(_s.get("limb_max", 0.0)), _doll.max_part_speed())
		_s["x1"] = com.x
		return
	if _t < t2:
		_doll.input_vec = Vector2(-1, 0)
		var since2 := _t - t1
		if not _m.has("flip_s") and v.x <= 0.0:
			_m["flip_s"] = snappedf(since2, 0.01)
		if not _m.has("rev_to_m3_s") and v.x <= -3.0:
			_m["rev_to_m3_s"] = snappedf(since2, 0.01)
		_s["vmin"] = minf(float(_s.get("vmin", 0.0)), v.x)
		_s["tilt_max"] = maxf(float(_s.get("tilt_max", 0.0)), _tilt_deg())
		_s["limb_max"] = maxf(float(_s.get("limb_max", 0.0)), _doll.max_part_speed())
		_s["x2"] = com.x
		return
	if _t < t3:
		var since3 := _t - t2
		if since3 < delta * 1.5:
			_s["x_rel"] = com.x
		if not _m.has("stop_s") and absf(v.x) < 0.3:
			_m["stop_s"] = snappedf(since3, 0.01)
			_m["stop_dist"] = snappedf(absf(com.x - float(_s["x_rel"])), 0.01)
		return
	if _t < t4:
		_doll.request_dash()
		_doll.input_vec = Vector2(1, 0)
		_s["dash_vmax"] = maxf(float(_s.get("dash_vmax", 0.0)), v.x)
		_s["limb_dash_max"] = maxf(float(_s.get("limb_dash_max", 0.0)), _doll.max_part_speed())
		return
	if _t < t5:
		_s["tilt_end"] = _tilt_deg()
		_s["y_end"] = com.y
		return
	_end()


func _end() -> void:
	var id := "%s/%s" % [_cur["variant"], _cur["tempo"]]
	var row := {
		"variant": _cur["variant"], "tempo": _cur["tempo"],
		"v0.5s": _m.get("v_0p5", -1.0), "v1s": _m.get("v_1p0", -1.0), "v2s": _m.get("v_2p0", -1.0),
		"vmax": snappedf(float(_s.get("vmax", 0.0)), 0.01),
		"flip_s": _m.get("flip_s", -1.0), "rev_to_-3_s": _m.get("rev_to_m3_s", -1.0),
		"stop_s": _m.get("stop_s", -1.0), "stop_dist": _m.get("stop_dist", -1.0),
		"tilt_max_deg": snappedf(float(_s.get("tilt_max", 0.0)), 0.1),
		"limb_max": snappedf(float(_s.get("limb_max", 0.0)), 0.01),
		"whip": snappedf(float(_s.get("limb_max", 0.0)) / maxf(float(_s.get("vmax", 0.1)), 0.1), 0.01),
		"dash_vmax": snappedf(float(_s.get("dash_vmax", 0.0)), 0.01),
		"tilt_end_deg": snappedf(float(_s.get("tilt_end", 0.0)), 0.1),
		"dx_right": snappedf(float(_s.get("x1", 0.0)) - float(_s.get("x0", 0.0)), 0.01),
	}
	_rows.append(row)
	_checks.append({"id": "responds_" + id, "ok": float(row["dx_right"]) > 0.6})
	_checks.append({"id": "on_floor_" + id, "ok": float(_s.get("min_y", 0.0)) > -0.5})
	_next()


func _finish() -> void:
	print("=== CONTROL FEEL ===")
	print("%-10s %-7s %5s %5s %5s %5s | %5s %6s | %5s %5s | %5s %5s %5s | %5s %5s" % [
		"variant", "tempo", "v.5", "v1", "v2", "vmax", "flip", "to-3", "stop", "dist", "tilt", "limb", "whip", "dash", "end"])
	for r in _rows:
		print("%-10s %-7s %5.1f %5.1f %5.1f %5.1f | %5.2f %6.2f | %5.2f %5.2f | %5.1f %5.1f %5.2f | %5.1f %5.1f" % [
			r["variant"], r["tempo"], r["v0.5s"], r["v1s"], r["v2s"], r["vmax"], r["flip_s"], r["rev_to_-3_s"], r["stop_s"], r["stop_dist"],
			r["tilt_max_deg"], r["limb_max"], r["whip"], r["dash_vmax"], r["tilt_end_deg"]])
	var failed := 0
	for c in _checks:
		if not bool(c["ok"]):
			failed += 1
			print("FAIL ", c["id"])
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"rows": _rows, "checks": _checks, "failed": failed}, "  "))
		f.close()
	print("failed checks: ", failed)
	ControlFeel.reset()
	get_tree().quit(1 if (strict and failed > 0) else 0)
