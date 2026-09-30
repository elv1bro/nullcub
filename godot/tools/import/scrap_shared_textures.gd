## Пост-импорт glb Свалки (assets/models/scrap/**, прописан в import_script/path их .import): текстуры, которые glTF-импорт
## вынул из glb рядом с ним (<Asset>_albedo_4.webp, <Asset>_normal_3.webp …), подменяются в материалах общими копиями из
## assets/models/scrap/shared_tex/ с тем же содержимым (md5 файла). Зачем: Blender-скрипты (scrap_bodies/props/kit/machines)
## вшивают в каждый glb копии одних и тех же PBR-наборов (rust_metal, scrap_wood …) — сотни извлечённых файлов на несколько
## десятков разных картинок, и арена scrap.tscn грузила каждую копию отдельно, lossless (распаковка WebP на CPU, ~25 мс на
## 1024²; в окне ещё RGB→RGBA и 5.6 МБ видеопамяти на копию). Общие копии импортируются VRAM-сжатыми (цвет BC1/BC3, нормали
## BC5, metallic+roughness BC7) и грузятся один раз на всю арену: load() арены 7.3–9 с → ~0.1 с (29.09, M2).
##
## Текстура, которой нет в библиотеке (перепекли PBR-набор, новый ассет), остаётся своей — ассет выглядит так же, только
## грузится медленнее; импорт пишет предупреждение. Пополнить библиотеку: tools/build_scrap_shared_textures.gd.
@tool
extends EditorScenePostImport

const LIB := "res://assets/models/scrap/shared_tex"

static var _lib := {}        # md5 файла → путь в библиотеке
static var _lib_stamp := {}  # путь → время изменения (md5 пересчитывается только у изменённых файлов)


func _post_import(scene: Node) -> Object:
	scan_lib(_lib, _lib_stamp)
	var mats := {}
	collect_materials(scene, mats)
	var shared := 0
	var missed: Array[String] = []
	for m: BaseMaterial3D in mats:
		for i in BaseMaterial3D.TEXTURE_MAX:
			var t := m.get_texture(i)
			if t == null or t.resource_path.is_empty() or t.resource_path.begins_with(LIB):
				continue
			var p: String = _lib.get(FileAccess.get_md5(t.resource_path), "")
			if p.is_empty():
				if not missed.has(t.resource_path):
					missed.append(t.resource_path)
				continue
			m.set_texture(i, load(p))
			shared += 1
	if not missed.is_empty():
		push_warning("%s: %d текстур(ы) нет в %s (%s) — остаются свои; пополнить: tools/build_scrap_shared_textures.gd" % [
			get_source_file(), missed.size(), LIB, ", ".join(missed.map(func(s): return s.get_file()))])
	return scene


## md5 содержимого → путь для всех картинок библиотеки (без .import).
static func scan_lib(lib: Dictionary, stamps: Dictionary) -> void:
	var seen := {}
	for f in DirAccess.get_files_at(LIB):
		if f.get_extension() == "import":
			continue
		var p := LIB.path_join(f)
		seen[p] = true
		var stamp := FileAccess.get_modified_time(p)
		if stamps.get(p, -1) == stamp:
			continue
		stamps[p] = stamp
		lib[FileAccess.get_md5(p)] = p
	for md5 in lib.keys():
		if not seen.has(lib[md5]):
			lib.erase(md5)
	for p in stamps.keys():
		if not seen.has(p):
			stamps.erase(p)


## Все BaseMaterial3D поддерева: материалы поверхностей мешей и override-ы узлов.
static func collect_materials(n: Node, out: Dictionary) -> void:
	var mesh = n.get("mesh")
	if mesh is ArrayMesh:
		for s in mesh.get_surface_count():
			_add(mesh.surface_get_material(s), out)
	elif mesh is ImporterMesh:
		for s in mesh.get_surface_count():
			_add(mesh.get_surface_material(s), out)
	if n is GeometryInstance3D:
		_add(n.material_override, out)
	if n is MeshInstance3D:
		for s in n.get_surface_override_material_count():
			_add(n.get_surface_override_material(s), out)
	for c in n.get_children():
		collect_materials(c, out)


static func _add(m: Material, out: Dictionary) -> void:
	if m is BaseMaterial3D:
		out[m] = true
