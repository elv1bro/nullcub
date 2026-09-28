## Знамя — только поведение: экспорт color выбирает видимое полотнище (Mesh/…/Cloth_Red|Blue|White из Banner.glb),
## полотнище покачивается вокруг перекладины (origin полотнища в GLB — у перекладины). Дерево: banner.tscn.
class_name Banner
extends Node3D

@export_enum("red", "blue", "white") var color := "red": set = _set_color
@export var sway_deg := 5.0

var _cloth: Node3D
var _t := 0.0


func _ready() -> void:
	_t = randf() * 20.0
	_apply()


func _set_color(v: String) -> void:
	color = v
	if is_inside_tree():
		_apply()


func _apply() -> void:
	var mesh := get_node_or_null("Mesh")
	if mesh == null:
		return
	_cloth = null
	for c in ["Red", "Blue", "White"]:
		var n := mesh.find_child("Cloth_" + c, true, false) as Node3D
		if n == null:
			continue
		n.visible = c.to_lower() == color
		if n.visible:
			_cloth = n


func _process(delta: float) -> void:
	_t += delta
	if _cloth == null:
		return
	var amp := deg_to_rad(sway_deg)
	_cloth.rotation.x = amp * (0.6 * sin(_t * 1.3) + 0.4 * sin(_t * 2.9))
	_cloth.rotation.z = amp * 0.5 * sin(_t * 0.9)
