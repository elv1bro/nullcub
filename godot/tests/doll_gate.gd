## Гейт этапа 04: 4 проверки поведения куклы (перенос из eval:behavior старого проекта).
## Запуск: tests/run_gate.sh  →  печатает JSON и пишет tests/doll_gate_report.json, exit 0/1.
extends Node3D

const DollScene := preload("res://scenes/doll/doll.tscn")

const IDLE_S := 30.0
const MOVE_SETTLE_S := 1.0
const MOVE_S := 1.5

var scenarios := ["idle", "move_right", "move_left"]
var idx := -1
var doll: Doll
var t := 0.0
var ticks := 0
var report := {"ok": true, "checks": [], "info": {}}
var start_com := Vector3.ZERO
var start_head_y := 0.0
var max_speed := 0.0
var min_head_y := 99.0
var move_ref := Vector3.ZERO
var dx := {"move_right": 0.0, "move_left": 0.0}
var phys_time_acc := 0.0
var phys_samples := 0
var settled_com := Vector3.ZERO
var wall_start_usec := 0
var total_ticks := 0
const SETTLE_SAMPLE_S := 10.0
## Переопределения одной строкой после "--": "k=60,c=6,f=6,tmax=80" (-1 = из Tuning).
var cfg := {"k": -1.0, "c": -1.0, "f": -1.0, "tmax": -1.0}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and cfg.has(p[0]):
				cfg[p[0]] = float(p[1])
	_make_floor()
	wall_start_usec = Time.get_ticks_usec()
	_next()


func _make_floor() -> void:
	var f := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 1, 10)
	cs.shape = bs
	f.add_child(cs)
	f.position = Vector3(0, -0.5, 0)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	f.physics_material_override = pm
	add_child(f)


func _spawn() -> void:
	if doll:
		doll.queue_free()
	doll = DollScene.instantiate()
	doll.external_input = true
	doll.muscle_stiffness = cfg["k"]
	doll.muscle_damping = cfg["c"]
	doll.joint_friction = cfg["f"]
	doll.muscle_max_torque = cfg["tmax"]
	add_child(doll)
	# idle: спавн в воздухе на 0.5 м — проверяем, что гравитация (пусть и слабая) действует и кукла оседает.
	doll.position = Vector3(0, 0.5, 0) if scenarios[idx] == "idle" else Vector3.ZERO


func _next() -> void:
	idx += 1
	if idx >= scenarios.size():
		_finish()
		return
	_spawn()
	t = 0.0
	ticks = 0
	max_speed = 0.0
	min_head_y = 99.0
	start_com = doll.centre_of_mass()
	start_head_y = doll.head().global_position.y


func _check(id: String, value: float, limit: float, cmp: String, detail: String) -> void:
	var ok := false
	match cmp:
		"lt": ok = value < limit
		"gt": ok = value > limit
		"lte": ok = value <= limit
		"gte": ok = value >= limit
	report["checks"].append({"id": id, "value": snappedf(value, 0.001), "limit": limit, "cmp": cmp, "ok": ok, "detail": detail})
	if not ok:
		report["ok"] = false


func _physics_process(delta: float) -> void:
	if doll == null or idx >= scenarios.size():
		return
	t += delta
	ticks += 1
	total_ticks += 1
	max_speed = max(max_speed, doll.max_part_speed())
	min_head_y = min(min_head_y, doll.head().global_position.y)
	var s: String = scenarios[idx]
	match s:
		"idle":
			doll.input_vec = Vector2.ZERO
			if t >= SETTLE_SAMPLE_S and settled_com == Vector3.ZERO:
				settled_com = doll.centre_of_mass()
			if t >= IDLE_S:
				var com := doll.centre_of_mass()
				_check("idle_creep_com", abs(com.x - settled_com.x), 0.3, "lt", "Idle 10→30 s: |COM.x drift| after settling (m)")
				report["info"]["idle_total_drift_x"] = snappedf(com.x - start_com.x, 0.001)
				_check("idle_settles", start_head_y - doll.head().global_position.y, 0.3, "gt", "Idle 30 s from 0.5 m in the air: head descends (m), gravity acts")
				_check("no_fall_through", min_head_y, 0.1, "gt", "Idle: min head y above floor (m)")
				_check("no_explosion", max_speed, 15.0, "lt", "Idle 30 s: max part speed (m/s)")
				report["info"]["idle_head_y_end"] = snappedf(doll.head().global_position.y, 0.001)
				report["info"]["idle_com_y_end"] = snappedf(com.y, 0.001)
				_next()
		"move_right", "move_left":
			var dir := 1.0 if s == "move_right" else -1.0
			if t < MOVE_SETTLE_S:
				doll.input_vec = Vector2.ZERO
				move_ref = doll.centre_of_mass()
			elif t < MOVE_SETTLE_S + MOVE_S:
				doll.input_vec = Vector2(dir, 0.0)
			else:
				doll.input_vec = Vector2.ZERO
				dx[s] = doll.centre_of_mass().x - move_ref.x
				if s == "move_right":
					_check("move_right", dx[s], 0.6, "gt", "Force +X for 1.5 s: COM dx (m)")
				else:
					_check("move_left", dx[s], -0.6, "lt", "Force -X for 1.5 s: COM dx (m)")
					var a: float = abs(dx["move_right"])
					var b: float = abs(dx["move_left"])
					var bal: float = abs(a - b) / max(max(a, b), 0.001)
					_check("move_lr_balance", bal, 0.10, "lte", "||dxR|-|dxL|| / max (fraction)")
				_check("no_explosion_" + s, max_speed, 15.0, "lt", "max part speed during move (m/s)")
				_next()


func _finish() -> void:
	var wall_ms := (Time.get_ticks_usec() - wall_start_usec) / 1000.0
	report["info"]["wall_ms_per_tick_avg"] = snappedf(wall_ms / max(total_ticks, 1), 0.001)
	report["info"]["ticks"] = total_ticks
	report["info"]["muscles"] = {"k": doll._k, "c": doll._c, "tmax": doll._tmax, "friction": cfg["f"] if cfg["f"] >= 0 else Tuning.JOINT_FRICTION}
	report["info"]["godot"] = Engine.get_version_info()["string"]
	report["info"]["physics_engine"] = ProjectSettings.get_setting("physics/3d/physics_engine")
	var js := JSON.stringify(report, "  ")
	print("=== DOLL GATE ===")
	print(js)
	var f := FileAccess.open("res://tests/doll_gate_report.json", FileAccess.WRITE)
	if f:
		f.store_string(js)
		f.close()
	print("=== %s ===" % ("OK" if report["ok"] else "FAIL"))
	get_tree().quit(0 if report["ok"] else 1)
