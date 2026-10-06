## Стенки-мембраны узких труб «Гонки: трасса» (docs/plan-demo/RACE_TRACK.md, участок 3): у каждой стенки — слой bands[i] толщиной
## Tuning.TRACK_MEMBRANE_SKIN, внутри него деталь куклы получает ускорение от стенки (пружина TRACK_MEMBRANE_K на метр вдавливания) и
## гашение скорости к стенке (TRACK_MEMBRANE_DAMP) — стенка отбрасывает, как мембрана купола, а не бьёт; за слоем — твёрдая стена
## (коллизия карты), сквозь неё не пролететь. Лёгкие пропсы мембрана не трогает (только куклы группы "dolls").
## bands — Rect2 слоя (мир, плоскость XY), normals — нормаль от стенки в коридор (одна из четырёх осей). Вид — светящаяся полоса у стенки
## (track_membrane.gdshader), вдавились — вспышка.
## Считает один узел на всю трубу: кукла ближе MARGIN к общей рамке — проверяются её детали по слоям (слоёв ~40, деталей ~14).
class_name TrackMembrane
extends Node3D

const SHADER := preload("res://scripts/race_track/track_membrane.gdshader")
const COLOUR := Color(0.5, 0.78, 1.0)
const MARGIN := 1.0

@export var bands: Array[Rect2] = []
@export var normals: PackedVector2Array = PackedVector2Array()

## Для проб: сколько раз за жизнь слой толкнул деталь куклы, максимум вдавливания (м).
var pushes := 0
var max_pen := 0.0
var _box := Rect2()
var _quads: Array = []
var _hit: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	_hit.resize(bands.size())
	for i in bands.size():
		_box = bands[i] if i == 0 else _box.merge(bands[i])
		_quads.append(_band_mesh(bands[i], normals[i] if i < normals.size() else Vector2.UP))


func _band_mesh(r: Rect2, n: Vector2) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Band"
	var qm := QuadMesh.new()
	var along := r.size.x if absf(n.y) > 0.5 else r.size.y
	var across := r.size.y if absf(n.y) > 0.5 else r.size.x
	qm.size = Vector2(along, across)
	mi.mesh = qm
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("colour", COLOUR)
	m.set_shader_parameter("length_m", along)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# локальная +y квада — к стенке (UV.y = 0 у верхнего края квада): поворот так, чтобы +y смотрела против нормали
	var up := -n
	var right := Vector2(up.y, -up.x)
	var c := r.get_center()
	mi.transform = Transform3D(Basis(Vector3(right.x, right.y, 0.0), Vector3(up.x, up.y, 0.0), Vector3(0.0, 0.0, 1.0)), Vector3(c.x, c.y, -0.35))
	add_child(mi)
	return mi


func _physics_process(delta: float) -> void:
	if bands.is_empty():
		return
	var area := _box.grow(MARGIN)
	var skin := Tuning.TRACK_MEMBRANE_SKIN
	for d in get_tree().get_nodes_in_group("dolls"):
		var doll := d as Doll
		if doll == null or not doll.is_inside_tree() or doll.is_broken():
			continue
		var com := doll.centre_of_mass()
		if not area.has_point(Vector2(com.x, com.y)):
			continue
		for p in doll.parts.values():
			var b := p as RigidBody3D
			if b == null or not is_instance_valid(b):
				continue
			var pos := Vector2(b.global_position.x, b.global_position.y)
			for i in bands.size():
				var r := bands[i]
				if not r.has_point(pos):
					continue
				var n := normals[i]
				var wall := _wall_coord(r, n)
				var dist := (pos.x - wall) * n.x if absf(n.x) > 0.5 else (pos.y - wall) * n.y
				var pen := clampf(skin - dist, 0.0, skin)
				if pen <= 0.0:
					continue
				var v := Vector2(b.linear_velocity.x, b.linear_velocity.y)
				var vn := v.dot(n)
				var acc := n * Tuning.TRACK_MEMBRANE_K * pen
				if vn < 0.0:
					acc -= n * Tuning.TRACK_MEMBRANE_DAMP * vn
				b.apply_central_force(Vector3(acc.x, acc.y, 0.0) * b.mass)
				pushes += 1
				max_pen = maxf(max_pen, pen)
				_hit[i] = maxf(_hit[i], clampf(pen / skin, 0.3, 1.0))
	for i in _hit.size():
		if _hit[i] > 0.0:
			_hit[i] = maxf(_hit[i] - delta * 2.5, 0.0)
			(_quads[i] as GeometryInstance3D).set_instance_shader_parameter("hit", _hit[i])


## Координата поверхности стенки слоя: край слоя со стороны, противоположной нормали.
static func _wall_coord(r: Rect2, n: Vector2) -> float:
	if n.x > 0.5:
		return r.position.x
	if n.x < -0.5:
		return r.end.x
	if n.y > 0.5:
		return r.position.y
	return r.end.y
