## Витрина и проверка дрона N0 (docs/plan-demo/ART_NULL.md, лист 2). Нужен рендер (окно; в контейнере — xvfb-run):
##   godot --path godot --resolution 1600x900 res://tests/n0_snapshot.tscn -- "sheet=res://../docs/plan-demo/img/n0-godot-v1.png"
## Кадр 1: три ливреи (default / event / support) с разными выражениями, в тёмной арене, контровой свет.
## Кадр 2: все 10 выражений экрана крупно (ряд из 5 × 2 дронов в ливрее default).
## Проверки (exit 1, если не прошли): узлы модели на месте, материалы ролей пришли из assets/materials/n0 (не плоские glb),
## 10 выражений дают 10 разных uv1_offset, ливреи дают разные цвета, неизвестное выражение отклоняется, треугольников ≤ 40 000.
## Отчёт — tests/n0_snapshot_report.json.
extends Node3D

const N0_SCENE := preload("res://scenes/n0/n0.tscn")
const PARTS := ["N0_Body", "N0_Screen", "N0_Ear_L", "N0_Ear_R", "N0_Legs_L", "N0_Legs_R", "N0_Arm_L", "N0_Arm_R", "N0_Mic"]
const TRI_BUDGET := 40000

var checks: Array = []
var args := {}
var cam: Camera3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		for kv in String(a).split(","):
			var p := String(kv).split("=")
			if p.size() == 2:
				args[p[0]] = p[1]
	_environment()
	cam = Camera3D.new()
	cam.fov = 30.0
	add_child(cam)
	cam.current = true
	await _run()


func _run() -> void:
	# --- кадр 1: ливреи ---
	var trio: Array[N0Drone] = []
	var setups := [["default", "happy"], ["event", "excited"], ["support", "curious"]]
	for i in range(3):
		var d := N0_SCENE.instantiate() as N0Drone
		add_child(d)
		d.position = Vector3((i - 1) * 1.05, 0.0, 0.0)
		d.rotation.y = deg_to_rad([22.0, 0.0, -22.0][i])
		d.livery = setups[i][0]
		d.expression = setups[i][1]
		trio.append(d)
	cam.position = Vector3(0.0, 0.16, 3.9)
	cam.look_at(Vector3(0.0, 0.14, 0.0))
	await _frames(6)
	var img1 := get_viewport().get_texture().get_image()
	_check_model(trio[0])
	_check("liveries_differ", trio[0].livery_color() != trio[1].livery_color() and trio[1].livery_color() != trio[2].livery_color(),
		"%s / %s / %s" % [trio[0].livery_color(), trio[1].livery_color(), trio[2].livery_color()])
	_check("unknown_expression_rejected", not trio[0].set_expression("nope") and trio[0].expression == "happy", trio[0].expression)
	for d in trio:
		d.queue_free()
	await _frames(2)
	# --- кадр 2: выражения ---
	var offs := {}
	var grid: Array[N0Drone] = []
	for i in range(N0Drone.EXPRESSIONS.size()):
		var d := N0_SCENE.instantiate() as N0Drone
		add_child(d)
		d.idle = false
		d.position = Vector3((i % 5 - 2) * 0.62, 0.55 - (i / 5) * 0.62, 0.0)
		d.scale = Vector3.ONE * 0.5
		d.expression = N0Drone.EXPRESSIONS[i]
		offs[N0Drone.EXPRESSIONS[i]] = d.screen_uv_offset()
		grid.append(d)
	cam.position = Vector3(0.0, 0.3, 3.7)
	cam.look_at(Vector3(0.0, 0.28, 0.0))
	await _frames(6)
	var img2 := get_viewport().get_texture().get_image()
	var uniq := {}
	for k in offs:
		uniq[str(offs[k])] = true
	_check("expressions_10_unique_cells", uniq.size() == 10, "%d unique of %d" % [uniq.size(), offs.size()])
	# --- лист ---
	var sheet := Image.create(img1.get_width(), img1.get_height() * 2, false, Image.FORMAT_RGB8)
	img1.convert(Image.FORMAT_RGB8)
	img2.convert(Image.FORMAT_RGB8)
	sheet.blit_rect(img1, Rect2i(Vector2i.ZERO, img1.get_size()), Vector2i.ZERO)
	sheet.blit_rect(img2, Rect2i(Vector2i.ZERO, img2.get_size()), Vector2i(0, img1.get_height()))
	var out := String(args.get("sheet", "res://tests/n0_snapshot.png"))
	var err := sheet.save_png(ProjectSettings.globalize_path(out) if out.begins_with("res://") else out)
	_check("sheet_saved", err == OK, out)
	_finish()


func _check_model(d: N0Drone) -> void:
	var missing: Array = []
	for n in PARTS:
		if d.get_node_or_null("Model/" + n) == null:
			missing.append(n)
	_check("model_parts", missing.is_empty(), "missing %s" % [missing])
	var tris := 0
	var flat_roles: Array = []
	for mi in d.mesh_nodes():
		for i in range(mi.mesh.get_surface_count()):
			var arr := mi.mesh.surface_get_arrays(i)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			tris += idx.size() / 3
			var m := mi.mesh.surface_get_material(i)
			if m == null or not String(m.resource_path).begins_with("res://assets/materials/n0/"):
				flat_roles.append("%s:%s" % [mi.name, m.resource_name if m != null else "null"])
	_check("tri_budget", tris <= TRI_BUDGET, "%d tris" % tris)
	_check("role_materials", flat_roles.is_empty(), "flat: %s" % [flat_roles])


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.04, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.75)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	for spec in [[Vector3(-35.0, -30.0, 0.0), Color(1.0, 0.85, 0.68), 1.6, true],
			[Vector3(-20.0, 160.0, 0.0), Color(0.45, 0.6, 1.0), 1.4, false],
			[Vector3(-60.0, 40.0, 0.0), Color(1.0, 0.95, 0.9), 0.4, false]]:
		var l := DirectionalLight3D.new()
		l.rotation_degrees = spec[0]
		l.light_color = spec[1]
		l.light_energy = spec[2]
		l.shadow_enabled = spec[3]
		add_child(l)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _check(id: String, ok: bool, info: String) -> void:
	checks.append({"id": id, "ok": ok, "info": info})
	print("%s %s — %s" % ["PASS" if ok else "FAIL", id, info])


func _finish() -> void:
	var ok := true
	for c in checks:
		ok = ok and bool(c["ok"])
	var f := FileAccess.open("res://tests/n0_snapshot_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"ok": ok, "checks": checks}, "  "))
	f.close()
	print("n0_snapshot: %s (%d checks)" % ["OK" if ok else "FAIL", checks.size()])
	get_tree().quit(0 if ok else 1)
