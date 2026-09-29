## Ударная волна (HIT_FX.md §2.2 / §2.4): кольцо на кваде 2×2 (scenes/fx/shockwave.tscn, шейдер scenes/fx/shaders/shockwave.gdshader)
## растёт r0 → r1 с ease-out за ms реального времени и гаснет. Лицом к камере (+Z), чуть перед плоскостью кукол.
## Время — нескалированное (delta / Engine.time_scale): в hit-stop и slow-mo волна идёт в реальном темпе.
## arc_dir ≠ 0 — полукольцо в сторону нормали (удар о стену/пол). Материал уникален на инстанс (resource_local_to_scene).
## thickness > 0 — своя толщина кольца (доля радиуса; в сцене 0.16), heavy v2 — толще (HIT_FX.md §11.3).
class_name Shockwave
extends MeshInstance3D

const Z_OFFSET := 0.25

var _r0 := 0.25
var _r1 := 1.3
var _ms := 180.0
var _t := 0.0
var _mat: ShaderMaterial


func thickness() -> float:
	return float(_mat.get_shader_parameter("thickness")) if _mat != null else 0.0


func setup(pos: Vector3, r0: float, r1: float, ms: float, colour: Color, arc_dir: Vector2 = Vector2.ZERO, thickness: float = -1.0) -> void:
	_r0 = r0
	_r1 = r1
	_ms = maxf(ms, 1.0)
	_t = 0.0
	global_transform = Transform3D(Basis.IDENTITY, Vector3(pos.x, pos.y, pos.z + Z_OFFSET))
	scale = Vector3(r0, r0, 1.0)
	_mat = material_override as ShaderMaterial
	if _mat == null and mesh != null:
		_mat = mesh.surface_get_material(0) as ShaderMaterial
	if _mat != null:
		_mat = _mat.duplicate() as ShaderMaterial
		material_override = _mat
		_mat.set_shader_parameter("colour", colour)
		_mat.set_shader_parameter("arc_dir", arc_dir)
		_mat.set_shader_parameter("progress", 0.0)
		if thickness > 0.0:
			_mat.set_shader_parameter("thickness", thickness)


func progress() -> float:
	return clampf(_t / _ms, 0.0, 1.0)


func _process(delta: float) -> void:
	_t += FxClock.real_delta(delta) * 1000.0
	var u := progress()
	var r := lerpf(_r0, _r1, 1.0 - pow(1.0 - u, 3.0))
	scale = Vector3(r, r, 1.0)
	if _mat != null:
		_mat.set_shader_parameter("progress", u)
	if u >= 1.0:
		queue_free()
