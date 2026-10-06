## Зона KO «Гонки: трасса» (docs/plan-demo/RACE_TRACK.md): прямоугольник size с центром в origin узла — Area3D в группе
## TrackArena.DEATH_GROUP (карта шлёт body_fell → площадка выбивает куклу → возврат к контрольной точке). kind = "grid" — сетка под током
## в потолке короткого пути развилки C (видна: красные прутья и искрящий свет), "pit" — дно ямы (не видна: темнота внизу).
class_name TrackGrid
extends Node3D

@export var size := Vector2(10.0, 0.4)
@export var kind := "grid"

var area: Area3D
var _mat: StandardMaterial3D
var _t := 0.0


func _ready() -> void:
	area = Area3D.new()
	area.name = "Area"
	area.monitoring = true
	area.monitorable = false
	area.add_to_group(TrackArena.DEATH_GROUP)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size.x, size.y, 4.0)
	cs.shape = bs
	area.add_child(cs)
	add_child(area)
	if kind != "grid":
		return
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(1.0, 0.18, 0.12)
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.2, 0.1)
	_mat.emission_energy_multiplier = 2.5
	var n := int(size.x / 0.6)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bar := BoxMesh.new()
	bar.size = Vector3(0.08, size.y, 1.6)
	mm.mesh = bar
	mm.instance_count = n + 1
	for i in n + 1:
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(-size.x * 0.5 + float(i) * size.x / float(maxi(n, 1)), 0.0, -0.2)))
	var mi := MultiMeshInstance3D.new()
	mi.name = "Bars"
	mi.multimesh = mm
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var rail := MeshInstance3D.new()
	rail.name = "Rail"
	var rm := BoxMesh.new()
	rm.size = Vector3(size.x, 0.06, 1.6)
	rail.mesh = rm
	rail.material_override = _mat
	rail.position = Vector3(0.0, -size.y * 0.5, -0.2)
	rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rail)
	for k in 3:
		var o := OmniLight3D.new()
		o.light_color = Color(1.0, 0.3, 0.2)
		o.light_energy = 1.2
		o.omni_range = 4.0
		o.shadow_enabled = false
		o.position = Vector3(-size.x * 0.5 + size.x * (0.5 + float(k)) / 3.0, -0.6, 0.6)
		add_child(o)


func _process(delta: float) -> void:
	if _mat == null:
		return
	_t += delta
	_mat.emission_energy_multiplier = 2.0 + 1.5 * absf(sin(_t * 9.0)) * (0.6 + 0.4 * sin(_t * 2.3))


## Прямоугольник зоны (мир, XY).
func rect() -> Rect2:
	return Rect2(Vector2(global_position.x, global_position.y) - size * 0.5, size)
