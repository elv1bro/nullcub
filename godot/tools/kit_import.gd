## Пост-импорт glb кита тела v2 (docs/plan-demo/BODY_KIT.md §2). Материалы в glb плоские, имя материала = роль (Base_<Mat>,
## Shirt_Kit, Face, CoreGlow, Iron, Steel…). Для каждой поверхности MeshInstance3D (и ImporterMeshInstance3D) с материалом <Имя>
## (resource_name, иначе имя поверхности; суффиксы Blender .001 / _001 отрезаются) ставится res://assets/materials/kit/<Имя>.tres,
## если такой файл есть (mesh.surface_set_material). Нет файла — остаётся плоский материал glb.
## Итог: правильные материалы везде без рантайм-кода — в кукле, иконках мастерской, призраке при перетаскивании, крафтовом оружии.
## resource_name материала = роль: по нему Doll._recolor красит Shirt_*, ModularDoll меняет Base_* (ось материалов, §4).
## Подключает builder: tools/build_body_kit.gd пишет import_script/path во все assets/models/body/kit/*.glb.import.
@tool
extends EditorScenePostImport

const MAT_DIR := "res://assets/materials/kit/"


func _post_import(scene: Node) -> Object:
	var cache := {}
	var n := _apply(scene, cache)
	print("kit_import: %s — %d surfaces → assets/materials/kit" % [get_source_file().get_file(), n])
	return scene


func _apply(node: Node, cache: Dictionary) -> int:
	var n := 0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for i in range(mesh.get_surface_count()):
			var sname: String = (mesh as ArrayMesh).surface_get_name(i) if mesh is ArrayMesh else ""
			var m := _kit_material(mesh.surface_get_material(i), sname, cache)
			if m != null:
				mesh.surface_set_material(i, m)
				n += 1
	elif node is ImporterMeshInstance3D and (node as ImporterMeshInstance3D).mesh != null:
		var im: ImporterMesh = (node as ImporterMeshInstance3D).mesh
		for i in range(im.get_surface_count()):
			var m := _kit_material(im.get_surface_material(i), im.get_surface_name(i), cache)
			if m != null:
				im.set_surface_material(i, m)
				n += 1
	for c in node.get_children():
		n += _apply(c, cache)
	return n


## Материал кита по роли текущего материала поверхности (или имени поверхности); null — файла роли нет.
func _kit_material(cur: Material, surface_name: String, cache: Dictionary) -> Material:
	for raw in [cur.resource_name if cur != null else "", surface_name]:
		var role := _clean(String(raw))
		if role == "":
			continue
		if not cache.has(role):
			var path := MAT_DIR + role + ".tres"
			cache[role] = load(path) if ResourceLoader.exists(path) else null
		if cache[role] != null:
			return cache[role]
	return null


## «Iron.001» / «Iron_001» → «Iron».
static func _clean(s: String) -> String:
	var re := RegEx.create_from_string("[._]\\d{3}$")
	return re.sub(s, "")
