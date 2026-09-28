## Надевает внешнюю модель на физический риг Doll.
## mode "parts": в сцене модели есть меши с именами частей → каждый меш переезжает под свой RigidBody.
## mode "skeleton": в модели Skeleton3D → каждый кадр кости ставятся по трансформам RigidBody.
class_name DollSkin
extends Node3D

const PART_NAMES := ["Head", "Torso", "UpperArm_L", "LowerArm_L", "Hand_L", "UpperArm_R", "LowerArm_R", "Hand_R",
	"UpperLeg_L", "LowerLeg_L", "UpperLeg_R", "LowerLeg_R", "Foot_L", "Foot_R"]

var doll: Doll
var mode := "parts"
var skeleton: Skeleton3D
var bone_map: Dictionary = {}          # part name -> bone index
var bone_offsets: Dictionary = {}      # part name -> Transform3D (body-local → bone rest)
var model_root: Node3D


## Возвращает true, если модель надета.
func apply(target: Doll, scene_path: String, skin_mode: String = "parts", bone_map_str: String = "", auto_scale: bool = true) -> bool:
	doll = target
	mode = skin_mode
	var ps := load(scene_path)
	if ps == null:
		push_error("DollSkin: cannot load " + scene_path)
		return false
	model_root = ps.instantiate()
	add_child(model_root)
	if auto_scale:
		_auto_scale()
	if mode == "skeleton":
		return _apply_skeleton(bone_map_str)
	return _apply_parts()


func _auto_scale() -> void:
	var aabb := _scene_aabb(model_root)
	if aabb.size.y <= 0.001:
		return
	var target_h := Doll.SHOULDER_Y + Doll.D["neck"] + Doll.D["head_r"] * 2.0
	var s := target_h / aabb.size.y
	if abs(s - 1.0) > 0.02:
		model_root.scale = Vector3.ONE * s
		print("DollSkin: auto scale ×%.3f (model height %.2f m)" % [s, aabb.size.y])


func _scene_aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in _find_all(n, "MeshInstance3D"):
		var a: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		if first:
			box = a
			first = false
		else:
			box = box.merge(a)
	return box


func _find_all(n: Node, cls: String) -> Array:
	var out := []
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		out += _find_all(c, cls)
	return out


func _match_part(node_name: String) -> String:
	for p in PART_NAMES:
		if node_name == p or node_name.begins_with(p + "_") or node_name.begins_with(p + ".") or node_name.to_lower() == p.to_lower():
			return p
	return ""


## Части: меш переезжает под RigidBody, сохраняя своё положение относительно тела в позе покоя.
func _apply_parts() -> bool:
	var moved := 0
	for mi in _find_all(model_root, "MeshInstance3D"):
		var part := _match_part(mi.name)
		if part == "":
			# дочерний меш (FacePlate) уедет вместе с родителем, если родитель — часть
			continue
		var body: RigidBody3D = doll.parts.get(part)
		if body == null:
			continue
		var g: Transform3D = mi.global_transform
		var parent: Node = mi.get_parent()
		parent.remove_child(mi)
		body.add_child(mi)
		mi.global_transform = g
		moved += 1
	# спрятать болванки рига
	for body in doll.parts.values():
		for c in body.get_children():
			if c is MeshInstance3D and c.get_meta("rig_mesh", false):
				c.visible = false
	_recolor("Shirt", Tuning.PLAYER_COLORS[clampi(doll.player_index, 0, 3)])
	print("DollSkin: parts attached: ", moved, "/14")
	return moved >= 10  # 14 частей; кисти опциональны


## Перекрашивает все поверхности с материалом данного имени (например Shirt) в цвет игрока.
func _recolor(material_name: String, colour: Color) -> void:
	for body in doll.parts.values():
		for mi in _find_all(body, "MeshInstance3D"):
			var m: MeshInstance3D = mi
			if m.mesh == null:
				continue
			for s in range(m.mesh.get_surface_count()):
				var mat := m.get_active_material(s)
				if mat == null or mat.resource_name != material_name:
					continue
				var dup := mat.duplicate()
				if dup is BaseMaterial3D:
					dup.albedo_color = colour
				m.set_surface_override_material(s, dup)


## Скелет: запоминаем смещение покоя кости относительно тела, потом ведём кости каждый кадр.
func _apply_skeleton(bone_map_str: String) -> bool:
	var sk := _find_all(model_root, "Skeleton3D")
	if sk.is_empty():
		push_error("DollSkin: no Skeleton3D in model")
		return false
	skeleton = sk[0]
	for kv in bone_map_str.split(","):
		var p := kv.strip_edges().split("=")
		if p.size() != 2:
			continue
		var idx := skeleton.find_bone(p[1].strip_edges())
		if idx < 0:
			push_warning("DollSkin: bone not found: " + p[1])
			continue
		bone_map[p[0].strip_edges()] = idx
	for part in bone_map:
		var body: RigidBody3D = doll.parts.get(part)
		if body == null:
			continue
		var bone_global: Transform3D = skeleton.global_transform * skeleton.get_bone_global_rest(bone_map[part])
		bone_offsets[part] = body.global_transform.affine_inverse() * bone_global
	for body in doll.parts.values():
		for c in body.get_children():
			if c is MeshInstance3D and c.get_meta("rig_mesh", false):
				c.visible = false
	print("DollSkin: bones mapped: ", bone_map.size())
	return bone_map.size() >= 6


func _physics_process(_delta: float) -> void:
	if mode != "skeleton" or skeleton == null:
		return
	var inv := skeleton.global_transform.affine_inverse()
	for part in bone_map:
		var body: RigidBody3D = doll.parts.get(part)
		if body == null:
			continue
		var pose: Transform3D = inv * body.global_transform * bone_offsets[part]
		skeleton.set_bone_global_pose(bone_map[part], pose)
