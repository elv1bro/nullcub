## Визуальная проверка PBR-текстур (tools/blender/textures.py) в Godot: тестовый glb assets/models/_texture_test.glb
## (куб stone, цилиндр wood, шар iron, крашеный ящик + тёмная балка, ткань с декалью-короной, верёвка, свотчи)
## плюс пол, собранный из PNG напрямую (StandardMaterial3D, uv 6×6 — виден тайлинг) под «честным» светом
## (солнце с тенями, небо как ambient, SSAO, ACES) → tests/materials_snap.png (общий) и tests/materials_macro.png (крупно).
## Собрать glb: /Applications/Blender.app/Contents/MacOS/Blender -b --python godot/tools/blender/textures.py -- --test-glb
## Запуск: godot --path godot --resolution 1280x720 --position 100,100 res://tests/materials_snapshot.tscn -- "out=res://tests/"
extends Node3D

const GLB := "res://assets/models/_texture_test.glb"
const PBR := "res://assets/textures/pbr/"

var out_dir := "res://tests/"
var cam: Camera3D
var t := 0.0
var stage := 0
var busy := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "out":
				out_dir = p[1]
	if not ResourceLoader.exists(GLB):
		push_error("нет %s — собери: Blender -b --python tools/blender/textures.py -- --test-glb" % GLB)
		get_tree().quit(1)
		return
	var ps: PackedScene = load(GLB)
	var inst := ps.instantiate()
	add_child(inst)
	_lighting()
	_floor()
	cam = Camera3D.new()
	add_child(cam)
	_frame_wide()


func _lighting() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.36, 0.55, 0.84)
	sm.sky_horizon_color = Color(0.78, 0.82, 0.88)
	sm.ground_bottom_color = Color(0.40, 0.38, 0.36)
	sm.ground_horizon_color = Color(0.66, 0.66, 0.68)
	sm.sun_angle_max = 8.0
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 1.0
	e.ambient_light_energy = 0.6
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 0.78
	e.tonemap_white = 1.0
	e.ssao_enabled = true
	e.ssao_radius = 0.5
	e.ssao_intensity = 2.0
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 28, 0)
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.96, 0.90)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 30.0
	sun.shadow_bias = 0.02
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -120, 0)
	fill.light_energy = 0.30
	fill.light_color = Color(0.80, 0.86, 1.0)
	add_child(fill)


func _floor() -> void:
	# пол из PNG напрямую (мимо glTF): тайлинг stone 6×6 м
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(PBR + "stone/albedo.png")
	mat.roughness_texture = load(PBR + "stone/roughness.png")
	mat.normal_enabled = true
	mat.normal_texture = load(PBR + "stone/normal.png")
	mat.normal_scale = 1.0
	mat.uv1_scale = Vector3(12, 12, 1)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mi.material_override = mat
	add_child(mi)


func _frame_wide() -> void:
	cam.fov = 38
	cam.position = Vector3(0.1, 1.35, 4.6)
	cam.look_at(Vector3(0.1, 0.55, 0))


func _frame_macro() -> void:
	cam.fov = 28
	cam.position = Vector3(-0.55, 0.95, 1.9)
	cam.look_at(Vector3(-0.45, 0.55, 0))


func _process(delta: float) -> void:
	t += delta
	if busy:
		return
	if stage == 0 and t >= 0.4:
		busy = true
		await _capture("materials_snap.png")
		_frame_macro()
		stage = 1
		busy = false
	elif stage == 1 and t >= 0.9:
		busy = true
		await _capture("materials_macro.png")
		get_tree().quit(0)


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(name)
	var err := img.save_png(path)
	print("saved ", path, " (", err, ") at t=", snappedf(t, 0.01))
