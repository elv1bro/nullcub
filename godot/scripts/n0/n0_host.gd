## N0 как ведущий у поля (лор §9, ART_NULL.md лист 2: «flies near the arena but remains far enough away»): ребёнок узла N0Drone
## на площадке. Держится у верхнего края кадра со стороны, где нет бойцов (в плоскости перед мембраной, z = plane_z),
## поворачивается к драке и меняет лицо на событиях: удар о мембрану — EXCITED, сильный удар — SHOCKED, KO — EXCITED,
## конец матча — HAPPY, долгая тишина — CURIOUS. В бою не участвует: коллизий нет.
## Позже здесь же — голос N0 вместо диктора (задача 4 в docs/ai-memory/CONTINUE.md).
extends Node

## Плоскость полёта (перед лентой мембраны, ближе к камере — не заслоняет бойцов сзади).
@export var plane_z := 3.2
## Точка в кадре (доли: x от края, y сверху), куда N0 стремится; сторона выбирается по бойцам.
@export var frame_anchor := Vector2(0.1, 0.26)
@export var follow_tau := 0.9
@export var max_speed := 9.0
@export var dolls_group := "dolls"
@export var hit_shocked_dmg := 12.0

var _drone: N0Drone
var _vel := Vector3.ZERO
var _side := -1.0
var _quiet := 0.0


func _ready() -> void:
	_drone = get_parent() as N0Drone
	_connect.call_deferred()


func _connect() -> void:
	var root := _drone.get_parent() if _drone != null else null
	if root == null:
		return
	for c in root.get_children():
		if c.has_method("membrane_anchors") and c.get("field") != null:
			(c.get("field") as NullField).membrane_hit.connect(func(_p: Vector2, _s: float) -> void: _react("excited", 1.6))
	var m := root.get_node_or_null("Match")
	if m != null and m.has_signal("hit"):
		m.connect("hit", func(_v: Node, _a: Node, dmg: float, _k: String, _p: Vector3) -> void:
			if dmg >= hit_shocked_dmg:
				_react("shocked", 1.2))
		m.connect("ko", func(_v: Node, _a: Node, _r: Dictionary) -> void: _react("excited", 2.5))
		m.connect("match_over", func(_w: Node, _r: Dictionary) -> void: _react("happy", 4.0))


func _react(expr: String, secs: float) -> void:
	if _drone != null:
		_drone.flash_expression(expr, secs)
	_quiet = 0.0


func _process(delta: float) -> void:
	if _drone == null:
		return
	var cam := _drone.get_viewport().get_camera_3d()
	if cam == null:
		return
	var size := _drone.get_viewport().get_visible_rect().size
	# бойцы в кадре: N0 уходит на противоположную сторону
	var sum_x := 0.0
	var n := 0
	var mid := Vector3.ZERO
	for d in _drone.get_tree().get_nodes_in_group(dolls_group):
		if d is Node3D and d.has_method("centre_of_mass"):
			var com: Vector3 = d.call("centre_of_mass")
			sum_x += cam.unproject_position(com).x / size.x
			mid += com
			n += 1
	if n > 0:
		mid /= n
		var want_side := 1.0 if sum_x / n < 0.5 else -1.0
		if absf(sum_x / n - 0.5) > 0.12:
			_side = want_side
	var fx := 0.5 + _side * (0.5 - frame_anchor.x)
	var screen := Vector2(fx * size.x, frame_anchor.y * size.y)
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	var target := from + dir * ((plane_z - from.z) / dir.z) if absf(dir.z) > 1e-4 else _drone.global_position
	# сглаженная погоня с ограничением скорости
	var k := 1.0 - exp(-delta / maxf(follow_tau, 0.01))
	var want_v := (target - _drone.global_position) * k / maxf(delta, 1e-4)
	_vel = _vel.lerp(want_v.limit_length(max_speed), clampf(delta * 4.0, 0.0, 1.0))
	_drone.global_position += _vel * delta
	# взгляд на драку: поворот вокруг Y и лёгкий наклон
	if n > 0:
		var to := mid - _drone.global_position
		var yaw := atan2(to.x, to.z)
		_drone.rotation.y = lerp_angle(_drone.rotation.y, clampf(yaw, -1.1, 1.1), clampf(delta * 3.0, 0.0, 1.0))
		_drone.rotation.z = lerpf(_drone.rotation.z, clampf(-_vel.x * 0.03, -0.25, 0.25), clampf(delta * 4.0, 0.0, 1.0))
	_quiet += delta
	if _quiet > 9.0:
		_react("curious", 1.5)
