## Направленная искра heavy (HIT_FX.md §11.3): конус-вспышка от точки удара вдоль ctx.dir + веер штрихов-искр (±SPREAD_DEG), летящих
## вдоль удара. Квады в плоскости кукол (XY, лицом к камере +Z), шейдер scenes/fx/shaders/spark.gdshader (материал общий, цвет и
## затухание — instance-параметры). Время — нескалированное (FxClock.real_delta): в hit-stop искра доигрывает в реальном темпе и к
## LIFE_MS снимается сама — торсы кукол к +100 мс не закрыты. Ребёнок FxRoot директора (abort_all снимает).
class_name SparkCone
extends Node3D

const SHADER: Shader = preload("res://scenes/fx/shaders/spark.gdshader")
const Z_OFFSET := 0.22
const CONE_LEN := 1.5          # м при k = 1
const CONE_W := 0.75
const CONE_MS := 100.0
const STREAKS := 13
const SPREAD_DEG := 26.0
const STREAK_LEN := Vector2(0.45, 0.95)
const STREAK_W := Vector2(0.05, 0.09)
const STREAK_SPEED := Vector2(7.0, 12.0)   # м/с реального времени
const STREAK_MS := Vector2(120.0, 200.0)
const LIFE_MS := 210.0

static var _mat: ShaderMaterial

var streaks := 0                # пробы
var _t := 0.0
var _cone: MeshInstance3D
var _items: Array = []          # [MeshInstance3D, dir: Vector3, speed, life_ms, len]
var _k := 1.0
var _alpha := 1.0


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
		_mat.render_priority = 9
	return _mat


## pos — точка удара, dir — направление удара (XY), colour — цвет атакующего, k — сила (0.6–1.6).
## alpha — яркость (flash_intensity директора / пресет FX).
func setup(pos: Vector3, dir: Vector3, colour: Color, k: float = 1.0, alpha: float = 1.0) -> void:
	_k = clampf(k, 0.5, 1.8)
	_alpha = clampf(alpha, 0.0, 1.0)
	var d := Vector3(dir.x, dir.y, 0.0)
	d = d.normalized() if d.length_squared() > 1e-6 else Vector3.RIGHT
	global_transform = Transform3D(Basis.IDENTITY, Vector3(pos.x, pos.y, pos.z + Z_OFFSET))
	var hot := colour.lerp(Color(1.0, 0.95, 0.8), 0.2)
	hot.a = 1.0
	_cone = _quad(Vector2(CONE_W * _k, CONE_LEN * _k), d, hot, 1.0)
	_place(_cone, Vector3.ZERO, d, CONE_LEN * _k * 0.3)
	for i in range(STREAKS):
		var ang := deg_to_rad(randf_range(-SPREAD_DEG, SPREAD_DEG))
		var sd := d.rotated(Vector3.BACK, ang)
		var ln := randf_range(STREAK_LEN.x, STREAK_LEN.y) * _k
		var mi := _quad(Vector2(randf_range(STREAK_W.x, STREAK_W.y) * _k, ln), sd, colour.lerp(Color(1.0, 0.95, 0.8), 0.35), 0.0)
		_items.append([mi, sd, randf_range(STREAK_SPEED.x, STREAK_SPEED.y) * _k, randf_range(STREAK_MS.x, STREAK_MS.y), ln])
		_place(mi, sd * 0.05, sd, ln * 0.2)
	streaks = _items.size()


func _quad(size: Vector2, d: Vector3, colour: Color, cone: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("tint", colour)
	mi.set_instance_shader_parameter("cone", cone)
	mi.set_instance_shader_parameter("fade", _alpha)
	add_child(mi)
	return mi


## Квад основанием в base (локально), вытянут вдоль d на длину, видимую как len_vis (масштаб по Y).
func _place(mi: MeshInstance3D, base: Vector3, d: Vector3, len_vis: float) -> void:
	var q := mi.mesh as QuadMesh
	var full := maxf(q.size.y, 1e-3)
	var sy := clampf(len_vis / full, 0.02, 1.0)
	var y := d
	var x := y.cross(Vector3.BACK).normalized()
	mi.transform = Transform3D(Basis(x, y * sy, Vector3.BACK), base + d * full * sy * 0.5)


func _process(delta: float) -> void:
	var dt := FxClock.real_delta(delta)
	_t += dt * 1000.0
	if _cone != null:
		var u := clampf(_t / CONE_MS, 0.0, 1.0)
		var grow := 1.0 - pow(1.0 - clampf(_t / (CONE_MS * 0.35), 0.0, 1.0), 2.0)
		var d: Vector3 = _cone.transform.basis.y.normalized()
		_place(_cone, Vector3.ZERO, d, CONE_LEN * _k * lerpf(0.3, 1.0, grow))
		_cone.set_instance_shader_parameter("fade", (1.0 - u * u) * _alpha)
		_cone.visible = u < 1.0
	for it in _items:
		var mi: MeshInstance3D = it[0]
		var sd: Vector3 = it[1]
		var life: float = it[3]
		var u := clampf(_t / life, 0.0, 1.0)
		var travel: float = float(it[2]) * (_t / 1000.0) * (1.0 - 0.45 * u)
		var ln: float = float(it[4]) * lerpf(1.0, 0.35, u)
		_place(mi, sd * (0.05 + travel), sd, ln)
		mi.set_instance_shader_parameter("fade", (1.0 - u) * _alpha)
		mi.visible = u < 1.0
	if _t >= LIFE_MS:
		queue_free()
