## Волна воздуха сильного удара (HIT_FX.md §13, стиль «серьёзный»): квад с шейдером-искажением (assets/shaders/air_shock.gdshader)
## в точке удара, кольцо расходится до radius за life_s реального времени и гаснет. Цвета нет — только сдвиг картинки за кольцом.
##   AirShock.spawn(parent, pos, radius, life_s, strength) -> AirShock
class_name AirShock
extends MeshInstance3D

const SHADER: Shader = preload("res://assets/shaders/air_shock.gdshader")

var _life := 0.16
var _t := 0.0
var _mat: ShaderMaterial


static func spawn(parent: Node, pos: Vector3, radius: float, life_s: float, strength: float = 0.025) -> AirShock:
	if parent == null or not parent.is_inside_tree():
		return null
	var a := AirShock.new()
	a.name = "AirShock"
	var q := QuadMesh.new()
	q.size = Vector2.ONE * radius * 2.0
	a.mesh = q
	a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	a._mat = ShaderMaterial.new()
	a._mat.shader = SHADER
	a._mat.set_shader_parameter("strength", strength)
	a._mat.set_shader_parameter("progress", 0.05)
	a.material_override = a._mat
	a._life = maxf(life_s, 0.03)
	parent.add_child(a, true)
	a.global_transform = Transform3D(Basis.IDENTITY, pos + Vector3(0.0, 0.0, 0.3))
	return a


func _process(delta: float) -> void:
	_t += minf(FxClock.real_delta(delta), 1.0 / 30.0)
	var u := clampf(_t / _life, 0.0, 1.0)
	_mat.set_shader_parameter("progress", 0.05 + 0.95 * (1.0 - (1.0 - u) * (1.0 - u)))
	if u >= 1.0:
		queue_free()
