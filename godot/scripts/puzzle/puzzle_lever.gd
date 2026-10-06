## Рычаг (docs/plan-demo/PUZZLE.md «Механизмы»): рукоять — RigidBody3D "Handle", её хватает рука (ArmAssist, класс MEDIUM — тянется
## пружиной, не приваривается) или толкает кукла телом. Ось — в основании рукояти: у тела зажаты все линейные оси, а центр масс
## перенесён в ось (center_of_mass_mode CUSTOM) — рукоять только поворачивается вокруг оси Z, суставов нет. Ход ±PUZZLE_LEVER_MAX_DEG
## (упор — в _integrate_forces), фиксатор тянет к ближнему краю моментом до PUZZLE_LEVER_TORQUE (щелчок: рычаг остаётся, где его
## перекинули). Угол angle_deg() > 0 — рукоять наклонена вправо. Включён за +PUZZLE_LEVER_ON_DEG, выключен за −PUZZLE_LEVER_ON_DEG,
## между — прежнее (гистерезис). Гравитация на рукоять не действует (gravity_scale 0): в комнате с «низом» вбок рычаг не падает сам.
## Узел ставится основанием на пол (origin — низ основания).
class_name PuzzleLever
extends PuzzlePart

## Начальное положение: true — вправо (включён).
@export var start_on := false

var handle: RigidBody3D
var _knob_mat: StandardMaterial3D
var _lamp_mat: StandardMaterial3D
const PIVOT_Y := 0.35


func _ready() -> void:
	var base := StaticBody3D.new()
	base.name = "Base"
	add_child(base)
	box_shape(base, "Shape", Vector3(0.7, 0.3, 1.2), Vector3(0, 0.15, 0))
	box_mesh(base, "Mesh", Vector3(0.8, 0.32, 1.2), Vector3(0, 0.16, 0), flat_material(Color(0.16, 0.17, 0.19), 0.7, 0.4))
	var arc := box_mesh(self, "Arc", Vector3(1.3, 0.05, 0.05), Vector3(0, PIVOT_Y + 0.02, 0.62), flat_material(Color(0.25, 0.26, 0.28), 0.6, 0.5))
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lamp_mat = glow_material(COLOUR_OFF, 2.0)
	var lamp := MeshInstance3D.new()
	lamp.name = "Lamp"
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.16
	sm.material = _lamp_mat
	lamp.mesh = sm
	lamp.position = Vector3(0.0, 0.16, 0.66)
	add_child(lamp)
	label(self, "Off", "◀", Vector3(-0.62, PIVOT_Y + 0.25, 0.62), 36, COLOUR_OFF.lightened(0.2))
	label(self, "On", "▶", Vector3(0.62, PIVOT_Y + 0.25, 0.62), 36, COLOUR_ON.lightened(0.2))
	var h := LeverHandle.new()
	h.lever = self
	handle = h
	handle.name = "Handle"
	handle.mass = Tuning.PUZZLE_LEVER_MASS
	handle.gravity_scale = 0.0
	handle.axis_lock_linear_x = true
	handle.axis_lock_linear_y = true
	handle.axis_lock_linear_z = true
	handle.axis_lock_angular_x = true
	handle.axis_lock_angular_y = true
	handle.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	handle.center_of_mass = Vector3.ZERO
	var L := Tuning.PUZZLE_LEVER_LEN
	handle.inertia = Vector3.ONE * Tuning.PUZZLE_LEVER_MASS * L * L / 3.0
	handle.angular_damp = 2.0
	handle.can_sleep = false
	handle.set_meta(PropHeft.META, PropHeft.Heft.MEDIUM)
	handle.position = Vector3(0, PIVOT_Y, 0)
	add_child(handle)
	box_shape(handle, "Shape", Vector3(0.14, L, 0.4), Vector3(0, L * 0.5, 0))
	box_mesh(handle, "Rod", Vector3(0.1, L, 0.1), Vector3(0, L * 0.5, 0), flat_material(Color(0.55, 0.57, 0.6), 0.8, 0.3))
	_knob_mat = glow_material(COLOUR_OFF, 1.2)
	var knob := MeshInstance3D.new()
	knob.name = "Knob"
	var ks := SphereMesh.new()
	ks.radius = 0.13
	ks.height = 0.26
	ks.material = _knob_mat
	knob.mesh = ks
	knob.position = Vector3(0, L, 0)
	handle.add_child(knob)
	reset_state()


## Сброс: рукоять в начальное положение, состояние — по нему.
func reset_state() -> void:
	if handle == null:
		return
	var a := deg_to_rad(Tuning.PUZZLE_LEVER_MAX_DEG) * (1.0 if start_on else -1.0)
	handle.transform = Transform3D(Basis(Vector3.BACK, -a), Vector3(0, PIVOT_Y, 0))
	handle.angular_velocity = Vector3.ZERO
	handle.linear_velocity = Vector3.ZERO
	_on = not start_on
	_set_on(start_on)
	_refresh_visual()


## Наклон рукояти в градусах относительно основания: > 0 — вправо.
func angle_deg() -> float:
	if handle == null:
		return 0.0
	return rad_to_deg(_angle_of(handle.global_transform.basis))


func _angle_of(b: Basis) -> float:
	var up := (global_transform.basis.inverse() * b).y
	return atan2(up.x, up.y)


## Перекинуть рычаг скриптом (пробы, отладка): рукоять встаёт к краю.
func set_state(on: bool) -> void:
	start_on = on
	reset_state()


## Рукоять: _integrate_forces отдаёт рычагу (фиксатор и упор).
class LeverHandle extends RigidBody3D:
	var lever: PuzzleLever

	func _integrate_forces(st: PhysicsDirectBodyState3D) -> void:
		if lever != null and is_instance_valid(lever):
			lever._integrate(st)


func _integrate(st: PhysicsDirectBodyState3D) -> void:
	var a := _angle_of(st.transform.basis)
	var lim := deg_to_rad(Tuning.PUZZLE_LEVER_MAX_DEG)
	var w := st.angular_velocity.z
	# фиксатор: к ближнему краю (вправо — по часовой, w < 0)
	var target := -lim if a >= 0.0 else lim   # в углах поворота вокруг Z (вправо = отрицательный поворот)
	var rot := -a
	var I := Tuning.PUZZLE_LEVER_MASS * Tuning.PUZZLE_LEVER_LEN * Tuning.PUZZLE_LEVER_LEN / 3.0
	var tq := clampf(I * (36.0 * (target - rot) - 8.0 * w), -Tuning.PUZZLE_LEVER_TORQUE, Tuning.PUZZLE_LEVER_TORQUE)
	st.apply_torque(Vector3(0, 0, tq))
	# упор: за край не уходит
	if absf(rot) > lim:
		var clamped := clampf(rot, -lim, lim)
		var base_basis := global_transform.basis
		st.transform = Transform3D(base_basis * Basis(Vector3.BACK, clamped), st.transform.origin)
		if signf(w) == signf(rot):
			st.angular_velocity = Vector3.ZERO


func _physics_process(_delta: float) -> void:
	var a := angle_deg()
	if not _on and a >= Tuning.PUZZLE_LEVER_ON_DEG:
		_set_on(true)
		sfx("clank", 0.0, 1.4)
	elif _on and a <= -Tuning.PUZZLE_LEVER_ON_DEG:
		_set_on(false)
		sfx("clank", 0.0, 1.1)
	_refresh_visual()


func _refresh_visual() -> void:
	if _knob_mat == null:
		return
	var c := COLOUR_ON if _on else COLOUR_OFF
	_knob_mat.albedo_color = c
	_knob_mat.emission = c
	_lamp_mat.albedo_color = c
	_lamp_mat.emission = c
