## Лист-каталог моделей гаража меню (tools/blender/garage_kit.py → assets/models/garage/Garage_*.glb) в настоящих
## материалах ролей (scripts/menu/garage_materials.gd). Каждая модель снимается отдельно, камера подгоняется под её AABB.
## Нужно окно (headless не рендерит):
##   godot --path godot --resolution 1600x900 res://tests/garage_kit_sheet.tscn -- out=/абс/sheet.png [only=TV,Crate] [cols=5]
## В stdout — «=== GARAGE KIT ===» и JSON: модели, поверхности, роли без материала. Exit 1, если модель не грузится
## или у поверхности роль без записи в GarageMaterials.SPEC.
extends Node3D

const DIR := "res://assets/models/garage/"
const CELL := Vector2i(400, 300)

var cam: Camera3D
var label: Label


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var only: PackedStringArray = String(args.get("only", "")).split(",", false)
	var cols := int(args.get("cols", "5"))
	var out: String = args.get("out", ProjectSettings.globalize_path("user://garage_kit_sheet.png"))
	_studio()
	var files: Array = []
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".glb") and (only.is_empty() or only.has(f.get_basename().trim_prefix("Garage_"))):
			files.append(f)
	files.sort()
	var report := {"models": {}, "unknown_roles": []}
	var ok := true
	var rows := int(ceil(files.size() / float(cols)))
	var sheet := Image.create(CELL.x * cols, CELL.y * max(rows, 1), false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.1, 0.1, 0.11))
	for i in files.size():
		var f: String = files[i]
		var ps := load(DIR + f) as PackedScene
		if ps == null:
			ok = false
			report["models"][f] = "LOAD FAILED"
			continue
		var inst := ps.instantiate() as Node3D
		add_child(inst)
		var n := GarageMaterials.apply(inst)
		var surf := 0
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			for s in (mi as MeshInstance3D).mesh.get_surface_count():
				surf += 1
				var cur := (mi as MeshInstance3D).mesh.surface_get_material(s)
				var role := GarageMaterials._role(cur.resource_name if cur != null else "")
				if not GarageMaterials.SPEC.has(role) and not report["unknown_roles"].has(role):
					report["unknown_roles"].append(role)
		var box := _aabb(inst)
		report["models"][f] = {"surfaces": surf, "with_role": n, "size": [snappedf(box.size.x, 0.01), snappedf(box.size.y, 0.01), snappedf(box.size.z, 0.01)]}
		_frame(box)
		label.text = "%s   %.2f × %.2f × %.2f м" % [f.get_basename().trim_prefix("Garage_"), box.size.x, box.size.y, box.size.z]
		for k in 4:
			await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(CELL.x, CELL.y, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i((i % cols) * CELL.x, (i / cols) * CELL.y))
		remove_child(inst)
		inst.queue_free()
	if not report["unknown_roles"].is_empty():
		ok = false
	sheet.save_png(out)
	print("=== GARAGE KIT ===")
	print(JSON.stringify(report))
	print("=== OK ===" if ok else "=== FAIL ===")
	get_tree().quit(0 if ok else 1)


func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b := m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _frame(box: AABB) -> void:
	var c := box.get_center()
	var r := box.size.length() * 0.5
	var dir := Vector3(-0.5, 0.32, 1.0).normalized()
	var dist := r / tan(deg_to_rad(cam.fov * 0.5)) * 1.05
	cam.position = c + dir * dist
	cam.look_at(c, Vector3.UP)
	cam.near = max(0.01, dist - r * 2.0)
	cam.far = dist + r * 3.0


func _studio() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.13, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.56, 0.62)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ssao_enabled = true
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -35, 0)
	key.light_energy = 1.6
	key.light_color = Color(1.0, 0.92, 0.8)
	key.shadow_enabled = true
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_energy = 1.0
	rim.light_color = Color(0.6, 0.65, 1.0)
	add_child(rim)
	cam = Camera3D.new()
	cam.fov = 32.0
	add_child(cam)
	cam.current = true
	var cl := CanvasLayer.new()
	add_child(cl)
	label = Label.new()
	label.position = Vector2(24, 16)
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	cl.add_child(label)
