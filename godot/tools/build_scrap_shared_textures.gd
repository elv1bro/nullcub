## Библиотека общих текстур Свалки assets/models/scrap/shared_tex/ (зачем — см. tools/import/scrap_shared_textures.gd):
## проходит все glb в assets/models/scrap/** (как они импортированы сейчас), каждую извлечённую из glb текстуру, содержимого
## которой ещё нет в библиотеке, копирует туда байт в байт (<Материал>_<канал>_<размер>.webp) с .import «VRAM Compressed»
## (цвет — BC1/BC3; нормали — compress/normal_map=1 → BC5; metallic+roughness одной картинкой — high_quality → BC7: BC1 жмёт
## несвязанные каналы G/B блоками 4×4, и блик на ржавчине крупным планом «рябит»), и прописывает пост-импорт в import_script/path у .import каждого glb.
## Существующие файлы библиотеки не переименовывает и не удаляет (на них ссылаются импортированные сцены).
## Запускать после перегенерации ассетов Blender-скриптами (новые glb, перепечённые PBR-наборы), затем импорт ещё раз:
##   godot --headless --path godot --import
##   godot --headless --path godot -s res://tools/build_scrap_shared_textures.gd
##   godot --headless --path godot --import        # импорт библиотеки + переимпорт glb с подменой текстур
## Повторный запуск без новых текстур ничего не меняет (печатает «новых 0»).
extends SceneTree

const PostImport := preload("res://tools/import/scrap_shared_textures.gd")  # тот же файл, что POST_IMPORT
const ROOT := "res://assets/models/scrap"
const LIB := PostImport.LIB
const SCRIPT_KEY := "import_script/path="
const POST_IMPORT := "res://tools/import/scrap_shared_textures.gd"

const CHANNEL := {
	BaseMaterial3D.TEXTURE_ALBEDO: "albedo", BaseMaterial3D.TEXTURE_NORMAL: "normal",
	BaseMaterial3D.TEXTURE_ROUGHNESS: "rough", BaseMaterial3D.TEXTURE_METALLIC: "metal",
	BaseMaterial3D.TEXTURE_EMISSION: "emission", BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION: "ao",
}

# .import библиотечной текстуры: VRAM Compressed без детекта 3D (явно), mipmaps; подстановки — compress/high_quality
# (BC7 для metal_rough) и compress/normal_map (1 — нормаль → BC5)
const IMPORT_TEMPLATE := """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality=%s
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=%d
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(LIB)
	var lib := {}
	PostImport.scan_lib(lib, {})
	var names := {}
	for f in DirAccess.get_files_at(LIB):
		names[f.get_file().get_basename().get_basename()] = true
	var role := {}          # md5 → true, если текстура стоит в слоте нормали (для проверки противоречий)
	var added := 0
	var patched := 0
	var glbs := _glbs(ROOT)
	for glb in glbs:
		var root := (load(glb) as PackedScene).instantiate()
		var mats := {}
		PostImport.collect_materials(root, mats)
		for m: BaseMaterial3D in mats:
			for i in BaseMaterial3D.TEXTURE_MAX:
				var t := m.get_texture(i)
				if t == null or t.resource_path.is_empty():
					continue
				var src := t.resource_path
				var md5 := FileAccess.get_md5(src) if not src.begins_with(LIB) else ""
				var is_normal := i == BaseMaterial3D.TEXTURE_NORMAL
				var key := md5 if md5 != "" else src
				if role.has(key) and role[key] != is_normal:
					push_warning("%s: одна картинка и нормаль, и цвет (%s) — сжатие нормали подберётся по первому" % [glb, src])
				role[key] = is_normal
				if md5 == "" or lib.has(md5):
					continue
				var name := _name(m, i, t, names)
				var dst := LIB.path_join(name + "." + src.get_extension())
				var bytes := FileAccess.get_file_as_bytes(src)
				var fa := FileAccess.open(dst, FileAccess.WRITE)
				fa.store_buffer(bytes)
				fa.close()
				fa = FileAccess.open(dst + ".import", FileAccess.WRITE)
				fa.store_string(IMPORT_TEMPLATE % ["true" if name.contains("_metal_rough_") else "false", 1 if is_normal else 0])
				fa.close()
				lib[md5] = dst
				added += 1
		root.free()
		patched += int(_patch_import(glb))
	print("build_scrap_shared_textures: glb %d, новых текстур %d (всего в библиотеке %d), .import с пост-импортом +%d" % [
		glbs.size(), added, lib.size(), patched])
	print("Дальше: godot --headless --path godot --import")
	quit()


## <Материал>_<канал>_<ширина>: имя материала glTF без суффикса Blender .001; metallic + roughness одной картинкой — metal_rough.
static func _name(m: BaseMaterial3D, slot: int, t: Texture2D, names: Dictionary) -> String:
	var mat := m.resource_name
	var re := RegEx.create_from_string("\\.\\d+$")
	mat = re.sub(mat, "") if mat != "" else "mat"
	var ch: String = CHANNEL.get(slot, "tex%d" % slot)
	if (slot == BaseMaterial3D.TEXTURE_ROUGHNESS and m.metallic_texture == t) or \
			(slot == BaseMaterial3D.TEXTURE_METALLIC and m.roughness_texture == t):
		ch = "metal_rough"
	var base := "%s_%s_%d" % [mat.validate_filename().replace(" ", "_"), ch, t.get_width()]
	var name := base
	var n := 2
	while names.has(name):
		name = "%s_%d" % [base, n]
		n += 1
	names[name] = true
	return name


## Прописывает пост-импорт в .import glb; true — файл изменён. Чужой непустой import_script не трогает.
static func _patch_import(glb: String) -> bool:
	var path := glb + ".import"
	var want := SCRIPT_KEY + "\"%s\"" % POST_IMPORT
	var text := FileAccess.get_file_as_string(path)
	if text.contains(want):
		return false
	if not text.contains(SCRIPT_KEY + "\"\""):
		push_warning("%s: import_script/path уже занят — пропускаю" % path)
		return false
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(text.replace(SCRIPT_KEY + "\"\"", want))
	fa.close()
	return true


static func _glbs(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_glbs(dir.path_join(sub)))
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() == "glb":
			out.append(dir.path_join(f))
	out.sort()
	return out
