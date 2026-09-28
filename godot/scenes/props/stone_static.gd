## Статический каменный модуль (стена, плита, блок) — только поведение: экспорт solid включает/выключает все
## CollisionShape3D-дети. Декор за плоскостью боя (башни, фундамент) ставится с solid=false, чтобы не делать карманов.
class_name StoneStatic
extends StaticBody3D

@export var solid := true: set = _set_solid


func _ready() -> void:
	_apply()


func _set_solid(v: bool) -> void:
	solid = v
	if is_inside_tree():
		_apply()


func _apply() -> void:
	for c in get_children():
		if c is CollisionShape3D:
			c.disabled = not solid
