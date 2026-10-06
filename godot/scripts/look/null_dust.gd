## Пыль и мелкий мусор в объёме боя (поле NULL, docs/plan-demo/look/null.md): слои GPUParticles3D по глубине — немного перед плоскостью
## боя, больше за ней. Движение — assets/shaders/null_dust_process.gdshader (дрейф по гравитации поля, волны ударов, кильватер, толчок),
## вид — null_dust_draw.gdshader (пылинки, осколки-мусор, голубые искры). Узел — top_level в мировых координатах (координаты слоёв — мир).
## Управляет NullLook: set_drift() — вектор дрейфа, set_waves() / set_wakes() / set_push() — каждый кадр, пока что-то идёт.
class_name NullDust
extends Node3D

const PROCESS_SHADER := "res://assets/shaders/null_dust_process.gdshader"
const DRAW_SHADER := "res://assets/shaders/null_dust_draw.gdshader"
## Множитель числа частиц по пресету графики (Gfx).
const QUALITY := {"low": 0.4, "medium": 0.7, "high": 1.0, "ultra": 1.0}

## Слои: z0..z1 — глубина (м, плоскость боя z = 0), density — частиц на м³ коробки, size — диапазон размера пылинки, м, soft — мягкость
## точки (ближний слой — «боке»), alpha — плотность пыли, sparks / chips — доли искр и осколков.
const LAYERS_NULL := [
	{"name": "Front", "z0": 0.9, "z1": 3.4, "density": 0.05, "size": Vector2(0.1, 0.22), "soft": 0.9, "alpha": 0.22, "sparks": 0.06, "chips": 0.1},
	{"name": "Mid", "z0": -1.6, "z1": 0.9, "density": 0.2, "size": Vector2(0.045, 0.09), "soft": 0.3, "alpha": 0.6, "sparks": 0.08, "chips": 0.2},
	{"name": "Back", "z0": -5.5, "z1": -1.6, "density": 0.32, "size": Vector2(0.04, 0.08), "soft": 0.2, "alpha": 0.55, "sparks": 0.08, "chips": 0.2},
]
## Упрощённая пыль обычных арен: два слоя только перед плоскостью боя (у Руин стены и платформы стоят в самой плоскости боя и
## прямо за ней — там пыль была бы внутри камня; камера Руин ближе — 7 м, поэтому слой гуще), тёплая пыль, блики солнца вместо
## голубых искр NULL.
const LAYERS_PLAIN := [
	{"name": "Near", "z0": 1.3, "z1": 3.0, "density": 1.6, "size": Vector2(0.06, 0.11), "soft": 0.35, "alpha": 0.7, "sparks": 0.06, "chips": 0.1},
	{"name": "Front", "z0": 3.0, "z1": 4.6, "density": 0.15, "size": Vector2(0.08, 0.16), "soft": 0.9, "alpha": 0.22, "sparks": 0.04, "chips": 0.05},
]
const LIFE_S := 14.0                 # с: жизнь одной частицы (перерождается сама в шейдере)
const SYSTEM_LIFETIME_S := 3600.0    # с: системная жизнь — все частицы рождаются разом при старте, дальше живут сами
const MAX_PER_LAYER := 1400

var layers: Array[GPUParticles3D] = []
var drift := Vector3(0.0, -0.2, 0.0)
var _proc: Array[ShaderMaterial] = []
var _draw: Array[ShaderMaterial] = []


## Собрать слои в коробке box (мир; z коробки не важен — глубина у каждого слоя своя). ellipsoid.w > 0.5 — частицы видны только в куполе
## поля (полуоси xyz, центр ell_centre). plain — упрощённая пыль обычных арен.
func build(box: AABB, plain: bool, ellipsoid := Vector4(16.0, 19.0, 4.0, 0.0), ell_centre := Vector3.ZERO) -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var q := float(QUALITY.get(_gfx_preset(), 1.0))
	var ps: Shader = load(PROCESS_SHADER)
	var ds: Shader = load(DRAW_SHADER)
	for cfg: Dictionary in (LAYERS_PLAIN if plain else LAYERS_NULL):
		var z0 := float(cfg["z0"])
		var z1 := float(cfg["z1"])
		if ellipsoid.w > 0.5:
			z0 = maxf(z0, -ellipsoid.z)
			z1 = minf(z1, ellipsoid.z)
		var bmin := Vector3(box.position.x, box.position.y, z0)
		var bsize := Vector3(box.size.x, box.size.y, z1 - z0)
		var vol := bsize.x * bsize.y * bsize.z
		var p := GPUParticles3D.new()
		p.name = String(cfg["name"])
		p.amount = clampi(int(vol * float(cfg["density"]) * q), 8, MAX_PER_LAYER)
		p.lifetime = SYSTEM_LIFETIME_S
		p.explosiveness = 1.0
		p.randomness = 0.0
		p.fixed_fps = 30
		p.interpolate = true
		p.local_coords = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		p.visibility_aabb = AABB(bmin - Vector3.ONE * 3.0, bsize + Vector3.ONE * 6.0)
		var pm := ShaderMaterial.new()
		pm.shader = ps
		pm.set_shader_parameter("box_min", bmin)
		pm.set_shader_parameter("box_size", bsize)
		pm.set_shader_parameter("ellipsoid", ellipsoid)
		pm.set_shader_parameter("ell_centre", ell_centre)
		pm.set_shader_parameter("drift", drift)
		pm.set_shader_parameter("size_range", cfg["size"])
		pm.set_shader_parameter("life_s", LIFE_S)
		pm.set_shader_parameter("spark_frac", float(cfg["sparks"]))
		pm.set_shader_parameter("chip_frac", float(cfg["chips"]))
		pm.set_shader_parameter("waves", PackedVector4Array([Vector4(0, 0, 0, -1), Vector4(0, 0, 0, -1), Vector4(0, 0, 0, -1), Vector4(0, 0, 0, -1)]))
		pm.set_shader_parameter("wave_power", Vector4.ZERO)
		pm.set_shader_parameter("wakes", PackedVector4Array([Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]))
		pm.set_shader_parameter("wake_vel", PackedVector4Array([Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]))
		p.process_material = pm
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		var dm := ShaderMaterial.new()
		dm.shader = ds
		dm.set_shader_parameter("soft", float(cfg["soft"]))
		dm.set_shader_parameter("dust_alpha", float(cfg["alpha"]))
		if plain:   # обычные арены: светлая тёплая пыль (на светлом фоне Руин серая не видна), блики солнца вместо искр NULL
			dm.set_shader_parameter("dust_col", Color(1.0, 0.95, 0.86))
			dm.set_shader_parameter("chip_col", Color(0.27, 0.24, 0.2))
			dm.set_shader_parameter("spark_col", Color(1.0, 0.86, 0.6))
			dm.set_shader_parameter("spark_gain", 1.8)
		quad.material = dm
		p.draw_pass_1 = quad
		add_child(p)
		layers.append(p)
		_proc.append(pm)
		_draw.append(dm)


## Дрейф (м/с, мир): вектор гравитации поля, приведённый к медленной скорости.
func set_drift(v: Vector3) -> void:
	drift = v
	for m in _proc:
		m.set_shader_parameter("drift", v)


## Общий толчок (м/с²) — пока идёт смена поля; Vector3.ZERO — нет.
func set_push(v: Vector3) -> void:
	for m in _proc:
		m.set_shader_parameter("push", v)


## Волны ударов: до 4 [центр xyz, возраст w] и силы.
func set_waves(waves: PackedVector4Array, power: Vector4) -> void:
	for m in _proc:
		m.set_shader_parameter("waves", waves)
		m.set_shader_parameter("wave_power", power)


## Кильватер: до 4 точек (xyz — ЦМ, w — радиус) и скоростей (xyz, w — сила 0..1).
func set_wakes(points: PackedVector4Array, vels: PackedVector4Array) -> void:
	for m in _proc:
		m.set_shader_parameter("wakes", points)
		m.set_shader_parameter("wake_vel", vels)


func total_amount() -> int:
	var n := 0
	for p in layers:
		n += p.amount
	return n


func _gfx_preset() -> String:
	var g := get_node_or_null("/root/Gfx")
	return String(g.get("preset")) if g != null else "high"
