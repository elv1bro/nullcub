## Пост-импорт glb дрона N0 (tools/blender/n0_drone.py → assets/models/n0/n0.glb; docs/plan-demo/ART_NULL.md, лист 2).
## Материалы в glb плоские, имя материала = роль (N0_Livery, N0_Accent, N0_Mech, N0_Joint, N0_Screen, N0_Lens, N0_Glow,
## N0_Rubber, N0_Print, N0_Flag). Каждой поверхности ставится res://assets/materials/n0/<Роль>.tres, если файл есть.
## Материалы пишет builder tools/build_n0.gd, он же прописывает этот скрипт в n0.glb.import.
@tool
extends EditorScenePostImport

const MAT_DIR := "res://assets/materials/n0/"


func _post_import(scene: Node) -> Object:
	var n := _apply(scene, {})
	print("n0_import: %s — %d surfaces → %s" % [get_source_file().get_file(), n, MAT_DIR])
	return scene


func _apply(node: Node, cache: Dictionary) -> int:
	var n := 0
	if node is ImporterMeshInstance3D and (node as ImporterMeshInstance3D).mesh != null:
		var im: ImporterMesh = (node as ImporterMeshInstance3D).mesh
		for i in range(im.get_surface_count()):
			var m := _role_material(im.get_surface_material(i), im.get_surface_name(i), cache)
			if m != null:
				im.set_surface_material(i, m)
				n += 1
	elif node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for i in range(mesh.get_surface_count()):
			var sname: String = (mesh as ArrayMesh).surface_get_name(i) if mesh is ArrayMesh else ""
			var m := _role_material(mesh.surface_get_material(i), sname, cache)
			if m != null:
				mesh.surface_set_material(i, m)
				n += 1
	for c in node.get_children():
		n += _apply(c, cache)
	return n


func _role_material(cur: Material, surface_name: String, cache: Dictionary) -> Material:
	for raw in [cur.resource_name if cur != null else "", surface_name]:
		var role := RegEx.create_from_string("[._]\\d{3}$").sub(String(raw), "")
		if role == "":
			continue
		if not cache.has(role):
			var path := MAT_DIR + role + ".tres"
			cache[role] = load(path) if ResourceLoader.exists(path) else null
		if cache[role] != null:
			return cache[role]
	return null
