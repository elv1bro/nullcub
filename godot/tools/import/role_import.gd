## Пост-импорт glb с материалами по ролям (общий): материал поверхности с именем <Роль> заменяется на
## res://assets/materials/<папка glb>/<Роль>.tres, если файл есть. Папка — имя каталога, где лежит glb
## (assets/models/arena/null_hall/*.glb → assets/materials/null_hall/). Суффиксы Blender .001 / _001 отрезаются.
## Так же устроены tools/kit_import.gd (кит тела) и tools/import/n0_import.gd (N0) — у них свой каталог материалов.
@tool
extends EditorScenePostImport


func _post_import(scene: Node) -> Object:
	var dir := "res://assets/materials/%s/" % get_source_file().get_base_dir().get_file()
	var n := _apply(scene, dir, {})
	print("role_import: %s — %d surfaces → %s" % [get_source_file().get_file(), n, dir])
	return scene


func _apply(node: Node, dir: String, cache: Dictionary) -> int:
	var n := 0
	if node is ImporterMeshInstance3D and (node as ImporterMeshInstance3D).mesh != null:
		var im: ImporterMesh = (node as ImporterMeshInstance3D).mesh
		for i in range(im.get_surface_count()):
			var m := _role_material(im.get_surface_material(i), im.get_surface_name(i), dir, cache)
			if m != null:
				im.set_surface_material(i, m)
				n += 1
	elif node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for i in range(mesh.get_surface_count()):
			var sname: String = (mesh as ArrayMesh).surface_get_name(i) if mesh is ArrayMesh else ""
			var m := _role_material(mesh.surface_get_material(i), sname, dir, cache)
			if m != null:
				mesh.surface_set_material(i, m)
				n += 1
	for c in node.get_children():
		n += _apply(c, dir, cache)
	return n


func _role_material(cur: Material, surface_name: String, dir: String, cache: Dictionary) -> Material:
	for raw in [cur.resource_name if cur != null else "", surface_name]:
		var role := RegEx.create_from_string("[._]\\d{3}$").sub(String(raw), "")
		if role == "":
			continue
		if not cache.has(role):
			var path := dir + role + ".tres"
			cache[role] = load(path) if ResourceLoader.exists(path) else null
		if cache[role] != null:
			return cache[role]
	return null
