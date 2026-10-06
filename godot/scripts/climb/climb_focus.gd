## Точка кадра для куклы в пробе «Подъём» (docs/plan-demo/CLIMB.md): DynamicCamera держит в кадре узлы группы GROUP, а этот узел
## отдаёт ЦМ своей куклы, поднятый на Tuning.CLIMB_CAM_LOOK_UP — над головой видно больше, чем под ногами (куда лезть).
class_name ClimbFocus
extends Node3D

const GROUP := "climb_focus"

var doll: Doll


static func make(d: Doll) -> ClimbFocus:
	var f := ClimbFocus.new()
	f.name = "Focus_%s" % d.name
	f.doll = d
	f.add_to_group(GROUP)
	return f


func centre_of_mass(interpolated := true) -> Vector3:
	if doll == null or not is_instance_valid(doll) or not doll.is_inside_tree():
		return global_position
	return doll.centre_of_mass(interpolated) + Vector3(0.0, Tuning.CLIMB_CAM_LOOK_UP, 0.0)


func torso() -> RigidBody3D:
	return doll.torso() if doll != null and is_instance_valid(doll) and doll.parts.has("Torso") else null


func _process(_delta: float) -> void:
	if doll != null and is_instance_valid(doll) and doll.is_inside_tree():
		global_position = centre_of_mass(true)
