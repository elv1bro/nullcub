## Лифт (docs/plan-demo/PUZZLE.md «Механизмы»): платформа — AnimatableBody3D "Platform" (sync_to_physics, как пресс Свалки: везёт и
## толкает тела) шириной width, ездит по вертикали между низом (origin узла — верх платформы внизу) и travel м выше: вверх, пока на
## входе input есть ток, вниз — без тока, со скоростью Tuning.PUZZLE_LIFT_SPEED. Вниз не едет, если под платформой тело (Area3D
## "Under") — не давит кукол в шахте. Направляющие по краям и лампа: зелёная — едет/наверху, красная — внизу без тока.
## is_on() — платформа наверху (для логики и проб); height_now() — подъём, м.
class_name PuzzleLift
extends PuzzlePart

@export var input: NodePath
@export var width := 3.0
@export var travel := 5.0

var platform: AnimatableBody3D
var _under: Area3D
var _y := 0.0
var _lamp_mat: StandardMaterial3D


func _ready() -> void:
	platform = AnimatableBody3D.new()
	platform.name = "Platform"
	platform.sync_to_physics = true
	add_child(platform)
	box_shape(platform, "Shape", Vector3(width, 0.3, 2.0), Vector3(0, -0.15, 0))
	box_mesh(platform, "Mesh", Vector3(width, 0.3, 1.9), Vector3(0, -0.15, 0), flat_material(Color(0.24, 0.25, 0.27), 0.8, 0.35))
	var hz := glow_material(Color(1.0, 0.7, 0.1), 0.5)
	for s in [-1.0, 1.0]:
		var e := box_mesh(platform, "Edge", Vector3(0.12, 0.31, 1.92), Vector3(s * (width * 0.5 - 0.06), -0.15, 0), hz)
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_under = Area3D.new()
	_under.name = "Under"
	_under.monitorable = false
	platform.add_child(_under)
	box_shape(_under, "Shape", Vector3(width - 0.1, 0.5, 1.8), Vector3(0, -0.55, 0))
	var rail := flat_material(Color(0.2, 0.21, 0.23), 0.8, 0.4)
	for s in [-1.0, 1.0]:
		box_mesh(self, "Rail", Vector3(0.12, travel + 1.2, 0.12), Vector3(s * (width * 0.5 + 0.08), (travel + 1.2) * 0.5 - 0.6, -0.9), rail)
	_lamp_mat = glow_material(COLOUR_OFF, 2.0)
	var lamp := box_mesh(platform, "Lamp", Vector3(0.4, 0.1, 0.05), Vector3(0, -0.15, 0.98), _lamp_mat)
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	reset_state()


func reset_state() -> void:
	_y = 0.0
	if platform != null:
		platform.position = Vector3.ZERO
	super.reset_state()
	_refresh_visual()


func height_now() -> float:
	return _y


func _physics_process(delta: float) -> void:
	var want_up := power_of(input)
	var was := _y
	if want_up:
		_y = move_toward(_y, travel, Tuning.PUZZLE_LIFT_SPEED * delta)
	elif _y > 0.0 and not _under_busy():
		_y = move_toward(_y, 0.0, Tuning.PUZZLE_LIFT_SPEED * delta)
	if not is_equal_approx(was, _y):
		platform.position = Vector3(0, _y, 0)
		if is_zero_approx(was) or is_equal_approx(was, travel):
			sfx("creak", -6.0, 0.8)
	_set_on(_y >= travel - 0.01)
	_refresh_visual()


func _under_busy() -> bool:
	for b in _under.get_overlapping_bodies():
		var rb := b as RigidBody3D
		if rb != null and not rb.freeze:
			return true
	return false


func _refresh_visual() -> void:
	if _lamp_mat == null:
		return
	var c := COLOUR_ON if (power_of(input) or _y > 0.01) else COLOUR_OFF
	_lamp_mat.albedo_color = c
	_lamp_mat.emission = c
