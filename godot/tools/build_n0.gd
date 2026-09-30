## Builder дрона N0 (docs/plan-demo/ART_NULL.md, лист 2): материалы по ролям, пост-импорт glb и сцена.
##   assets/materials/n0/<Роль>.tres     — N0_Livery / N0_Accent (краска paint_marks), N0_Mech, N0_Joint, N0_Screen (эмиссия атласа
##                                          выражений), N0_Lens, N0_Glow, N0_Rubber, N0_Print, N0_Flag
##   assets/models/n0/n0.glb.import      — import_script/path = tools/import/n0_import.gd (роль → .tres при импорте)
##   scenes/n0/n0.tscn                   — Node3D "N0" (scripts/n0/n0_drone.gd) ← Model (n0.glb)
## Порядок: blender -b --python tools/blender/n0_drone.py -- --export
##          godot --headless --path godot --import
##          godot --headless --path godot -s res://tools/build_n0.gd
##          godot --headless --path godot --import        (переимпорт glb с материалами; builder печатает, если нужен)
extends SceneTree

const MAT_DIR := "res://assets/materials/n0/"
const GLB := "res://assets/models/n0/n0.glb"
const ATLAS := "res://assets/models/n0/n0_face_atlas.png"
const IMPORT_SCRIPT := "res://tools/import/n0_import.gd"
const SCRIPT := "res://scripts/n0/n0_drone.gd"
const OUT := "res://scenes/n0/n0.tscn"
const PBR := "res://assets/textures/pbr/%s/%s.png"

const GLOW := Color(0.25, 0.7, 1.0)   # линейный, как GLOW в n0_drone.py

## роль → параметры. pbr — набор assets/textures/pbr; flat — линейный цвет; glow — линейная эмиссия
const MATS := {
	"N0_Livery": {"pbr": "paint_marks", "rough": 0.7},     # цвет ставит N0Drone по ливрее; здесь — default
	"N0_Accent": {"pbr": "paint_marks", "rough": 0.7},
	"N0_Mech": {"flat": [0.075, 0.078, 0.088], "rough": 0.42, "metal": 0.75},
	"N0_Joint": {"flat": [0.04, 0.04, 0.045], "rough": 0.32, "metal": 0.9},
	"N0_Screen": {"flat": [0.006, 0.008, 0.012], "rough": 0.08, "atlas": true, "energy": 2.2},
	"N0_Lens": {"flat": [0.01, 0.03, 0.06], "rough": 0.05, "glow": [0.25, 0.7, 1.0], "energy": 0.6},
	"N0_Glow": {"flat": [0.1, 0.3, 0.5], "rough": 0.3, "glow": [0.25, 0.7, 1.0], "energy": 4.0},
	"N0_Rubber": {"flat": [0.035, 0.034, 0.034], "rough": 0.95},
	"N0_Print": {"flat": [0.025, 0.022, 0.02], "rough": 0.6},
	"N0_Flag": {"flat": [0.80, 0.78, 0.74], "rough": 0.5},
}

var errors := 0


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/n0/"))
	var fresh := _build_materials()
	var patched := _patch_import()
	_build_scene()
	if fresh or patched:
		print("build_n0: материалы или import_script новые — нужен переимпорт: godot --headless --path godot --import")
	print("build_n0: done, errors=%d" % errors)
	quit(1 if errors > 0 else 0)


func _build_materials() -> bool:
	var fresh := false
	var default_pair: Array = load(SCRIPT).LIVERIES["default"]
	for role in MATS:
		var d: Dictionary = MATS[role]
		var path: String = MAT_DIR + role + ".tres"
		if not FileAccess.file_exists(path):
			fresh = true
		var m := StandardMaterial3D.new()
		m.resource_name = role
		m.roughness = float(d.get("rough", 0.7))
		m.metallic = float(d.get("metal", 0.0))
		if d.has("pbr"):
			var folder := String(d["pbr"])
			m.albedo_texture = _tex(folder, "albedo")
			if m.albedo_texture == null:
				_err("%s: нет текстуры %s" % [role, PBR % [folder, "albedo"]])
				continue
			var rough := _tex(folder, "roughness")
			if rough != null:
				m.roughness_texture = rough
			var nrm := _tex(folder, "normal")
			if nrm != null:
				m.normal_enabled = true
				m.normal_texture = nrm
			var c: Color = default_pair[0] if role == "N0_Livery" else default_pair[1]
			m.albedo_color = N0Drone._paint(c)
		else:
			var f: Array = d["flat"]
			m.albedo_color = Color(f[0], f[1], f[2]).linear_to_srgb()
		if d.has("glow"):
			var g: Array = d["glow"]
			m.emission_enabled = true
			m.emission = Color(g[0], g[1], g[2]).linear_to_srgb()
			m.emission_energy_multiplier = float(d.get("energy", 1.0))
		if d.get("atlas", false):
			if not ResourceLoader.exists(ATLAS):
				_err("нет %s — сначала --import" % ATLAS)
				continue
			m.emission_enabled = true
			m.emission = Color.BLACK
			m.emission_texture = load(ATLAS)
			m.emission_operator = BaseMaterial3D.EMISSION_OP_ADD
			m.emission_energy_multiplier = float(d.get("energy", 1.0))
			m.uv1_scale = Vector3(1.0 / N0Drone.ATLAS_COLS, 1.0 / N0Drone.ATLAS_ROWS, 1.0)
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var err := ResourceSaver.save(m, path)
		if err != OK:
			_err("не сохранить %s: %d" % [path, err])
	return fresh


func _tex(folder: String, ch: String) -> Texture2D:
	var p := PBR % [folder, ch]
	return load(p) if ResourceLoader.exists(p) else null


func _patch_import() -> bool:
	var ipath := GLB + ".import"
	var line := "import_script/path=\"%s\"" % IMPORT_SCRIPT
	var text := FileAccess.get_file_as_string(ipath) if FileAccess.file_exists(ipath) else ""
	if text.contains(line):
		return false
	var re := RegEx.create_from_string("(?m)^import_script/path=.*$")
	if text == "":
		text = "[remap]\n\nimporter=\"scene\"\nimporter_version=1\n\n[params]\n\n%s\n" % line
	elif re.search(text) != null:
		text = re.sub(text, line)
	elif text.contains("[params]"):
		text = text.replace("[params]\n", "[params]\n\n%s\n" % line)
	else:
		text += "\n[params]\n\n%s\n" % line
	var f := FileAccess.open(ipath, FileAccess.WRITE)
	if f == null:
		_err("не записать " + ipath)
		return false
	f.store_string(text)
	f.close()
	return true


func _build_scene() -> void:
	if not ResourceLoader.exists(GLB):
		_err("нет %s — сначала экспорт Blender и --import" % GLB)
		return
	var root := Node3D.new()
	root.name = "N0"
	root.set_script(load(SCRIPT))
	var model := (load(GLB) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	root.add_child(model)
	model.owner = root
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err == OK:
		err = ResourceSaver.save(ps, OUT)
	if err != OK:
		_err("сцена %s: %d" % [OUT, err])
	else:
		print("build_n0: %s" % OUT)
	root.free()


func _err(msg: String) -> void:
	errors += 1
	push_error("build_n0: " + msg)
