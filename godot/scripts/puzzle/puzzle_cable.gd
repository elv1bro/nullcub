## Кабель (docs/plan-demo/PUZZLE.md «Механизмы»): ломаная по задней стене от источника к приёмнику, светится, когда на источнике
## source ток. Точки points — локальные (x, y) узла, z — глубина узла (сборщик ставит кабели на заднюю стену). Каждый отрезок —
## тонкая коробка; на изломах — заклёпка. Без тока — тёмный, под током — цветом COLOUR_ON, яркость пульсирует.
class_name PuzzleCable
extends Node3D

@export var source: NodePath
@export var points: PackedVector2Array = PackedVector2Array()
@export var thickness := 0.07

var _mat: StandardMaterial3D
var _on := false
var _t := 0.0


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = PuzzlePart.COLOUR_IDLE
	_mat.emission_enabled = true
	_mat.emission = Color.BLACK
	_mat.roughness = 0.5
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var len := a.distance_to(b)
		if len < 0.01:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Seg%d" % i
		var bm := BoxMesh.new()
		bm.size = Vector3(len + thickness, thickness, thickness)
		bm.material = _mat
		mi.mesh = bm
		mi.position = Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, 0.0)
		mi.rotation = Vector3(0, 0, atan2(b.y - a.y, b.x - a.x))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	for i in points.size():
		var r := PuzzlePart.box_mesh(self, "Rivet%d" % i, Vector3.ONE * thickness * 1.8, Vector3(points[i].x, points[i].y, 0.0),
			PuzzlePart.flat_material(Color(0.2, 0.21, 0.22), 0.8, 0.4))
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func is_lit() -> bool:
	return _on


func _process(delta: float) -> void:
	_t += delta
	var n := get_node_or_null(source)
	var on := n != null and n.has_method("is_on") and bool(n.call("is_on"))
	_on = on
	if on:
		var k := 1.4 + 0.5 * sin(_t * 6.0)
		_mat.albedo_color = PuzzlePart.COLOUR_ON
		_mat.emission = PuzzlePart.COLOUR_ON
		_mat.emission_energy_multiplier = k
	else:
		_mat.albedo_color = PuzzlePart.COLOUR_IDLE
		_mat.emission = Color.BLACK
		_mat.emission_energy_multiplier = 0.0
