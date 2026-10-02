## Витрина деталей NULL League в Godot (tools/blender/kit_league.py → scenes/body/kit/kit_*league*.tscn; docs/plan-demo/ART_NULL.md).
## Нужен рендер (окно; в контейнере — xvfb-run):
##   godot --path godot --resolution 1600x900 res://tests/league_parts_snapshot.tscn -- "sheet=/abs/league-parts.png"
## Все сцены деталей с «league» в имени — в ряд (заморожены) в тёмном окружении с тёплым ключом и холодным контровым.
## Проверки (exit 1): деталей ≥ 12, у каждой корень RigidBody3D, все поверхности — материалы assets/materials/kit (роли League_*
## — из build_league.gd), у голов есть Face. Отчёт — tests/league_parts_snapshot_report.json.
extends Node3D

const DIR := "res://scenes/body/kit/"

var checks: Array = []
var args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		for kv in String(a).split(","):
			var p := String(kv).split("=")
			if p.size() == 2:
				args[p[0]] = p[1]
	_environment()
	var files: Array[String] = []
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".tscn") and f.contains("league"):
			files.append(f)
	files.sort()
	var parts: Array[Node3D] = []
	var bad_root: Array = []
	var bad_mat: Array = []
	var heads_without_face: Array = []
	var cols := 9
	for i in range(files.size()):
		var n := (load(DIR + files[i]) as PackedScene).instantiate() as Node3D
		add_child(n)
		if n is RigidBody3D:
			(n as RigidBody3D).freeze = true
		else:
			bad_root.append(files[i])
		var col := i % cols
		var row := i / cols
		n.position = Vector3((col - (cols - 1) * 0.5) * 0.62, 0.55 - row * 0.8, 0.0)
		if files[i].contains("_head_") or files[i].contains("_deco_league_halo"):
			n.position.y -= 0.2
		n.rotation_degrees.y = 18.0
		parts.append(n)
		var has_face := false
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var mesh := (mi as MeshInstance3D).mesh
			for s in range(mesh.get_surface_count()):
				var m := mesh.surface_get_material(s)
				if m == null or not String(m.resource_path).begins_with("res://assets/materials/kit/"):
					bad_mat.append("%s:%s" % [files[i], m.resource_name if m != null else "null"])
				elif m.resource_name == "Face":
					has_face = true
		if files[i].contains("_head_") and not has_face:
			heads_without_face.append(files[i])
	_check("parts_20", files.size() >= 25, "%d scenes (20 деталей, у конечностей и щита — S / L)" % files.size())
	_check("rigid_roots", bad_root.is_empty(), str(bad_root))
	_check("kit_materials", bad_mat.is_empty(), str(bad_mat.slice(0, 6)))
	_check("heads_have_face", heads_without_face.is_empty(), str(heads_without_face))
	var cam := Camera3D.new()
	cam.fov = 32.0
	add_child(cam)
	cam.current = true
	cam.position = Vector3(0.0, -0.15, 7.4)
	cam.look_at(Vector3(0.0, -0.15, 0.0))
	for i in range(8):
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var out := String(args.get("sheet", "res://tests/league_parts_snapshot.png"))
	var err := img.save_png(ProjectSettings.globalize_path(out) if out.begins_with("res://") else out)
	_check("sheet_saved", err == OK, out)
	var ok := true
	for c in checks:
		ok = ok and bool(c["ok"])
	var f := FileAccess.open("res://tests/league_parts_snapshot_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"ok": ok, "checks": checks}, "  "))
	f.close()
	print("league_parts_snapshot: %s (%d checks)" % ["OK" if ok else "FAIL", checks.size()])
	get_tree().quit(0 if ok else 1)


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.52, 0.65)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	for spec in [[Vector3(-35.0, -30.0, 0.0), Color(1.0, 0.86, 0.7), 1.5], [Vector3(-20.0, 160.0, 0.0), Color(0.5, 0.62, 1.0), 1.3]]:
		var l := DirectionalLight3D.new()
		l.rotation_degrees = spec[0]
		l.light_color = spec[1]
		l.light_energy = spec[2]
		add_child(l)


func _check(id: String, ok: bool, info: String) -> void:
	checks.append({"id": id, "ok": ok, "info": info})
	print("%s %s — %s" % ["PASS" if ok else "FAIL", id, info])
