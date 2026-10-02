## Пост-импорт моделей гаража меню (tools/blender/garage_kit.py → assets/models/garage/Garage_*.glb). Материалы в glb
## плоские, имя материала = роль (Wood, Iron, PaintNavy, Hazard, Screen…); здесь каждой поверхности ставится материал роли
## из scripts/menu/garage_materials.gd — модели выглядят правильно и в редакторе, и в игре, без кода в сцене.
## Подключение: import_script/path="res://tools/garage_import.gd" в Garage_*.glb.import (пишет tools/build_garage_menu.gd).
@tool
extends EditorScenePostImport

const MATS := preload("res://scripts/menu/garage_materials.gd")


func _post_import(scene: Node) -> Object:
	var n := _apply(scene)
	print("garage_import: %s — %d surfaces" % [get_source_file().get_file(), n])
	return scene


func _apply(node: Node) -> int:
	var n := 0
	if node is ImporterMeshInstance3D and (node as ImporterMeshInstance3D).mesh != null:
		var im: ImporterMesh = (node as ImporterMeshInstance3D).mesh
		for i in range(im.get_surface_count()):
			var cur := im.get_surface_material(i)
			var m: Material = MATS.get_material(MATS._role(cur.resource_name if cur != null else im.get_surface_name(i)))
			if m != null:
				im.set_surface_material(i, m)
				n += 1
	elif node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for i in range(mesh.get_surface_count()):
			var cur2 := mesh.surface_get_material(i)
			var m2: Material = MATS.get_material(MATS._role(cur2.resource_name if cur2 != null else ""))
			if m2 != null:
				mesh.surface_set_material(i, m2)
				n += 1
	for c in node.get_children():
		n += _apply(c)
	return n
