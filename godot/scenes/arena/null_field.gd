## Поле NULL арены: гравитация и упругая мембрана купола (лор §4–5, docs/plan-demo/ART_NULL.md).
## Area3D с заменой гравитации накрывает весь зал: всё внутри падает по вектору поля (сила в G × Tuning.G_EARTH, направление в
## плоскости экрана). Мембрана — полуэллипс над полом: центр centre (середина пола), полуоси axes (A — полуширина, B — высота).
## Каждый физический тик каждое тело за контуром получает ускорение пружины по нормали к эллипсу (см. Tuning.MEMBRANE_*),
## поэтому граница — упругая ткань, а не стена: растягивается, гасит скорость, выбрасывает обратно.
## Свечение и прогиб рисует шейдер assets/shaders/null_membrane.gdshader: точки hits (до 4) — место на мембране, растяжение и
## яркость — считаются здесь по куклам (группа "dolls") и по растянувшим мембрану телам.
## Только поведение: узел собирает tools/build_null_hall.gd (Field в scenes/arena/null_hall.tscn).
class_name NullField
extends Area3D

signal membrane_hit(point: Vector2, speed: float)

## «Вниз» в плоскости боя (y вверх). Не Vector2.DOWN: в Godot это (0, +1) — экранная ось 2D.
const FALL := Vector2(0.0, -1.0)

## Центр эллипса мембраны (мир, плоскость XY) и полуоси: A — полуширина, B — высота купола.
@export var centre := Vector2(0.0, 0.0)
@export var axes := Vector2(16.0, 19.0)
## Сила поля в G и направление (в плоскости экрана); меняются плавно через set_field().
@export var field_g := 0.0
@export var field_dir := Vector2(0.0, -1.0)
## Мембрана с эффектом (MeshInstance3D с ShaderMaterial null_membrane): сюда пишутся hits.
@export var membrane_path: NodePath
## Считать мембрану для тел (false — только гравитация: пробы гравитации).
@export var membrane_enabled := true

var max_stretch_seen := 0.0          # для проб: максимальное растяжение с начала
var hits: Array[Vector4] = []        # последние точки для шейдера (x, y, растяжение, яркость)

var _g_from := 0.0
var _g_to := 0.0
var _dir_from := FALL
var _dir_to := FALL
var _blend_t := 1.0
var _blend_s := 0.0
var _flash := {}                     # body_id → [точка, яркость] вспышка удара, гаснет
var _was_out := {}                   # body_id → bool: тело было за контуром на прошлом тике
var _mat: ShaderMaterial


func _ready() -> void:
	gravity_space_override = Area3D.SPACE_OVERRIDE_REPLACE
	if field_g <= 0.0:
		field_g = Tuning.GRAVITY / Tuning.G_EARTH
	_g_from = field_g
	_g_to = field_g
	_dir_from = field_dir.normalized()
	_dir_to = _dir_from
	_apply_gravity(field_g, _dir_from)
	var m := get_node_or_null(membrane_path) as MeshInstance3D
	if m != null:
		_mat = m.material_override as ShaderMaterial
		if _mat != null:
			_mat.set_shader_parameter("centre", centre)
			_mat.set_shader_parameter("axes", axes)


## Сменить поле: сила в G, направление в плоскости экрана; blend_s < 0 — Tuning.NULL_FIELD_BLEND_S, 0 — сразу.
func set_field(g_units: float, dir: Vector2, blend_s := -1.0) -> void:
	_g_from = field_g
	_dir_from = field_dir.normalized() if field_dir.length() > 0.001 else FALL
	_g_to = maxf(g_units, 0.0)
	_dir_to = dir.normalized() if dir.length() > 0.001 else _dir_from
	_blend_s = Tuning.NULL_FIELD_BLEND_S if blend_s < 0.0 else blend_s
	_blend_t = 0.0 if _blend_s > 0.0 else 1.0
	if _blend_s <= 0.0:
		field_g = _g_to
		field_dir = _dir_to
		_apply_gravity(field_g, field_dir)


func is_shifting() -> bool:
	return _blend_t < 1.0


## Вектор гравитации поля (м/с², плоскость XY).
func gravity_vec() -> Vector2:
	return field_dir.normalized() * field_g * Tuning.G_EARTH


## Растяжение мембраны в точке p (м; ≤ 0 — внутри, по радиусу к центру) и нормаль наружу.
func stretch_at(p: Vector2) -> Array:
	var d := p - centre
	if d.y < 0.0:
		return [d.y, Vector2(0.0, 1.0)]   # под полом — не мембрана (пол держит коллизия): считаем «внутри»
	var rho := sqrt((d.x / axes.x) * (d.x / axes.x) + (d.y / axes.y) * (d.y / axes.y))
	if rho < 1e-4:
		return [-minf(axes.x, axes.y), Vector2(0.0, 1.0)]
	var b := d / rho   # точка эллипса на том же луче
	var n := Vector2(b.x / (axes.x * axes.x), b.y / (axes.y * axes.y)).normalized()
	var pen := d.length() - b.length()
	return [pen, n]


## Ближайшая к p точка мембраны (по лучу от центра) — туда шейдер рисует вмятину.
func membrane_point(p: Vector2) -> Vector2:
	var d := p - centre
	d.y = maxf(d.y, 0.0)
	var rho := sqrt((d.x / axes.x) * (d.x / axes.x) + (d.y / axes.y) * (d.y / axes.y))
	return centre + (d / rho if rho > 1e-4 else Vector2(0.0, axes.y))


func _physics_process(delta: float) -> void:
	if _blend_t < 1.0:
		_blend_t = minf(1.0, _blend_t + delta / maxf(_blend_s, 0.001))
		var k := smoothstep(0.0, 1.0, _blend_t)
		field_g = lerpf(_g_from, _g_to, k)
		var a := _dir_from.angle()
		var b := _dir_to.angle()
		field_dir = Vector2.from_angle(a + wrapf(b - a, -PI, PI) * k)
		_apply_gravity(field_g, field_dir)
	if membrane_enabled:
		_membrane(delta)


func _apply_gravity(g_units: float, dir: Vector2) -> void:
	gravity = g_units * Tuning.G_EARTH
	var d := dir.normalized() if dir.length() > 0.001 else FALL
	gravity_direction = Vector3(d.x, d.y, 0.0)


func _membrane(delta: float) -> void:
	var cand: Array = []   # [яркость, точка, растяжение]
	for body in get_overlapping_bodies():
		var rb := body as RigidBody3D
		if rb == null or rb.freeze:
			continue
		var p := Vector2(rb.global_position.x, rb.global_position.y)
		var sn := stretch_at(p)
		var pen: float = sn[0]
		var n: Vector2 = sn[1]
		var id := rb.get_instance_id()
		if pen <= 0.0 or p.y < centre.y:
			_was_out.erase(id)
			continue
		var v := Vector2(rb.linear_velocity.x, rb.linear_velocity.y)
		var vn := v.dot(n)
		var k := Tuning.MEMBRANE_K * (Tuning.MEMBRANE_RETURN_GAIN if vn < 0.0 else 1.0)
		var acc := -n * k * minf(pen, Tuning.MEMBRANE_MAX_STRETCH)
		if pen > Tuning.MEMBRANE_MAX_STRETCH:
			acc -= n * Tuning.MEMBRANE_K * Tuning.MEMBRANE_HARD_MULT * (pen - Tuning.MEMBRANE_MAX_STRETCH)
		if vn > 0.0:
			acc -= n * Tuning.MEMBRANE_DAMP_OUT * vn
		rb.apply_central_force(Vector3(acc.x, acc.y, 0.0) * rb.mass)
		max_stretch_seen = maxf(max_stretch_seen, pen)
		if not _was_out.get(id, false):
			_was_out[id] = true
			if vn > 2.0:   # удар о мембрану: вспышка
				var mp := membrane_point(p)
				_flash[id] = [mp, clampf(vn / 10.0, 0.3, 1.0)]
				membrane_hit.emit(mp, vn)
		cand.append([0.35 + minf(pen / 1.5, 0.65), membrane_point(p), pen])
	_update_hits(cand, delta)


## Точки для шейдера: куклы у мембраны (свечение вблизи), растянутые тела, вспышки ударов; 4 самых ярких.
func _update_hits(cand: Array, delta: float) -> void:
	for d in get_tree().get_nodes_in_group("dolls"):
		if not (d is Node3D) or not d.has_method("centre_of_mass"):
			continue
		var com: Vector3 = d.call("centre_of_mass")
		var p := Vector2(com.x, com.y)
		var pen: float = stretch_at(p)[0]
		var near := 1.0 - clampf(-pen / Tuning.MEMBRANE_NEAR_M, 0.0, 1.0)
		if near > 0.0:
			cand.append([0.25 * near, membrane_point(p), 0.0])
	for id in _flash.keys():
		var f: Array = _flash[id]
		f[1] = float(f[1]) - delta * 2.2
		if float(f[1]) <= 0.0:
			_flash.erase(id)
		else:
			cand.append([float(f[1]), f[0], 0.0])
	cand.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	# слить близкие точки (одна кукла — одна вмятина): растяжение — максимум, яркость — максимум
	var merged: Array = []
	for c in cand:
		var put := false
		for m in merged:
			if (m[1] as Vector2).distance_to(c[1]) < 1.5:
				m[0] = maxf(float(m[0]), float(c[0]))
				m[2] = maxf(float(m[2]), float(c[2]))
				put = true
				break
		if not put and merged.size() < 4:
			merged.append(c.duplicate())
	hits.clear()
	for m in merged:
		var mp: Vector2 = m[1]
		hits.append(Vector4(mp.x, mp.y, float(m[2]), clampf(float(m[0]), 0.0, 1.0)))
	while hits.size() < 4:
		hits.append(Vector4(0.0, -1000.0, 0.0, 0.0))
	if _mat != null:
		_mat.set_shader_parameter("hits", PackedVector4Array(hits))
