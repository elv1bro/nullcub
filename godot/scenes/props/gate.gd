## Ворота-арка — только поведение: экспорт open поворачивает створки Door_L / Door_R (StaticBody3D с петлёй в origin)
## внутрь (от камеры) на open_angle_deg и выключает их коллизию; doors=false прячет створки совсем (руина-арка).
## Коллизия арки — только пилоны (Arch/Shape_*). Дерево: gate.tscn (tools/build_props_scenes.gd).
class_name Gate
extends Node3D

@export var open := false: set = _set_open
@export var doors := true: set = _set_doors
@export var open_angle_deg := 105.0


func _ready() -> void:
	_apply()


func _set_open(v: bool) -> void:
	open = v
	if is_inside_tree():
		_apply()


func _set_doors(v: bool) -> void:
	doors = v
	if is_inside_tree():
		_apply()


func _apply() -> void:
	var a := deg_to_rad(open_angle_deg) if open else 0.0
	var l := get_node_or_null("Door_L") as Node3D
	var r := get_node_or_null("Door_R") as Node3D
	if l:
		l.rotation.y = a
		l.visible = doors
		_shapes(l, doors and not open)
	if r:
		r.rotation.y = -a
		r.visible = doors
		_shapes(r, doors and not open)


func _shapes(n: Node, enabled: bool) -> void:
	for c in n.get_children():
		if c is CollisionShape3D:
			c.disabled = not enabled
