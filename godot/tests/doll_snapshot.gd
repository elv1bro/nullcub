## Визуальная проверка манекена v3 (scenes/doll/doll.tscn — клён, scenes/doll/doll_dark.tscn — орех) со светом
## «как на R22»: тёплый ключевой свет сверху-слева с тенями, холодная подсветка справа, тёплый тёмный фон мастерской,
## пол из половой доски wood_plank (доски вдоль X),
## SSAO + SSIL, лёгкий объёмный туман, тонмаппинг ACES, MSAA 4×. Три кадра за один запуск:
##   tests/doll_front.png   — P1 (клён), P2 (орех), P3 (клён) стоят фронтально в позе покоя «звезда» (кадр на FRONT_T ≥ 1 с
##                            после спавна — поза успевает собраться, ~0.7 с); шаг ряда ROW_STEP ≥ 2.2 м > размаха Т-позы
##                            (≈ 1.94 м): соседние кисти не сталкиваются на спавне;
##   tests/doll_closeup.png — крупно голова, грудь и кисть P1 в три четверти (яйцо, глаза, чашки, штифты, пальцы, обмотки, мазки);
##   tests/doll_action.png  — P4 (орех, на ROW_STEP+ правее P3) после толчка вправо-вверх, конечности отстают.
## Запуск: godot --path . --resolution 1280x720 --position 100,100 res://tests/doll_snapshot.tscn -- "out=res://tests/"
##   out=<папка> для PNG (по умолчанию res://tests/).
extends Node3D

const DollScene := preload("res://scenes/doll/doll.tscn")
const DollDarkScene := preload("res://scenes/doll/doll_dark.tscn")
const ROW_STEP := 2.3          # м между куклами ряда (размах Т-позы ≈ 1.94 м)
const P4_X := 5.2              # толкаемая кукла: 2.9 м правее P3
const FRONT_T := 1.1           # с после спавна: фронтальный кадр
const CLOSEUP_T := 1.25
const PUSH_T0 := 1.3           # толчок P4
const PUSH_T1 := 1.75
const ACTION_T := 1.9

var dolls: Array = []
var cam: Camera3D
var t := 0.0
var stage := 0
var busy := false
var out_dir := "res://tests/"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "out":
				out_dir = p[1]
	get_viewport().msaa_3d = Viewport.MSAA_4X
	_lighting()
	_floor()
	for i in range(4):
		var d: Doll = (DollDarkScene if i % 2 == 1 else DollScene).instantiate()
		d.player_index = i
		d.external_input = true
		add_child(d)
		# P1..P3 в ряд для фронтального кадра, P4 правее — её толкают для кадра action
		d.position = Vector3((i - 1) * ROW_STEP, 0, 0) if i < 3 else Vector3(P4_X, 0, 0)
		dolls.append(d)
	cam = Camera3D.new()
	add_child(cam)
	_frame_front()


func _lighting() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	# тёплый интерьер: верх тёмный, у горизонта — свет из окон
	sm.sky_top_color = Color(0.16, 0.13, 0.11)
	sm.sky_horizon_color = Color(0.62, 0.50, 0.36)
	sm.ground_bottom_color = Color(0.12, 0.09, 0.07)
	sm.ground_horizon_color = Color(0.42, 0.33, 0.24)
	sm.sun_angle_max = 10.0
	sm.sun_curve = 0.2
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 1.0
	e.ambient_light_energy = 0.55
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 0.9
	e.tonemap_white = 1.2
	e.ssao_enabled = true
	e.ssao_radius = 0.35
	e.ssao_intensity = 2.5
	e.ssao_power = 1.6
	e.ssil_enabled = true
	e.ssil_radius = 1.5
	e.ssil_intensity = 1.2
	e.glow_enabled = true
	e.glow_intensity = 0.25
	e.glow_bloom = 0.05
	e.glow_hdr_threshold = 1.1
	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = 0.012
	e.volumetric_fog_albedo = Color(0.95, 0.85, 0.7)
	e.volumetric_fog_emission_energy = 0.0
	e.volumetric_fog_anisotropy = 0.7
	e.volumetric_fog_length = 40.0
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.06
	env.environment = e
	add_child(env)
	# ключевой тёплый свет сверху-слева (падает вправо-вниз)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -42, 0)
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.86, 0.66)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 30.0
	sun.shadow_bias = 0.015
	sun.shadow_normal_bias = 1.0
	sun.light_volumetric_fog_energy = 1.5
	add_child(sun)
	# холодная подсветка справа-сзади
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, 130, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.62, 0.74, 0.95)
	fill.light_volumetric_fog_energy = 0.0
	add_child(fill)
	# контровой тёплый (кромки)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-25, 175, 0)
	rim.light_energy = 0.4
	rim.light_color = Color(1.0, 0.8, 0.6)
	rim.light_volumetric_fog_energy = 0.0
	add_child(rim)


func _floor() -> void:
	var f := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(40, 1, 12)
	cs.shape = bs
	f.add_child(cs)
	# пол — половая доска wood_plank (v3.1): доски идут вдоль X как на R22 (плоскость повёрнута на 90°, U = мировой Z)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(24, 40)   # глубина 24 м: камера кадра action (z=9.5) не видит край пола
	mi.mesh = pm
	mi.position = Vector3(0, 0.5, 0)
	mi.rotation_degrees = Vector3(0, 90, 0)
	var mat := StandardMaterial3D.new()
	var alb: Texture2D = load("res://assets/textures/pbr/wood_plank/albedo.png")
	if alb != null:
		mat.albedo_texture = alb
		mat.albedo_color = Color(0.78, 0.72, 0.66)   # чуть темнее под тёплым ключевым светом, ближе к полу R22
		var nrm: Texture2D = load("res://assets/textures/pbr/wood_plank/normal.png")
		if nrm != null:
			mat.normal_enabled = true
			mat.normal_texture = nrm
		var rgh: Texture2D = load("res://assets/textures/pbr/wood_plank/roughness.png")
		if rgh != null:
			mat.roughness_texture = rgh
		mat.uv1_scale = Vector3(24, 40, 1)
		mat.uv1_triplanar = false
	else:
		mat.albedo_color = Color(0.32, 0.25, 0.19)
	mat.roughness = 0.85
	mi.material_override = mat
	f.add_child(mi)
	f.position = Vector3(0, -0.5, 0)
	var phys := PhysicsMaterial.new()
	phys.friction = 0.9
	f.physics_material_override = phys
	add_child(f)
	# задник: тёмная тёплая стена далеко сзади, чтобы силуэты читались
	var wall := MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = Vector2(60, 20)
	wall.mesh = wm
	wall.rotation_degrees = Vector3(90, 0, 0)
	wall.position = Vector3(0, 6, -9)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.20, 0.15, 0.11)
	wmat.roughness = 1.0
	wall.material_override = wmat
	add_child(wall)


func _frame_front() -> void:
	# ряд −2.3..2.3 м с руками в стороны (кисти до ±3.3 м): полуширина кадра ≈ 3.8 м
	cam.fov = 30
	cam.position = Vector3(0.0, 1.0, 8.0)
	cam.look_at(Vector3(0.0, 0.9, 0))


func _frame_closeup() -> void:
	# голова, грудь и правая кисть P1 в три четверти
	var px: float = dolls[0].position.x
	cam.fov = 30
	cam.position = Vector3(px + 0.95, 1.32, 1.75)
	cam.look_at(Vector3(px - 0.04, 1.16, 0))


func _frame_action() -> void:
	# камера за толкаемой куклой: видно и позу в полёте, и ряд P1..P3 слева
	var c: Vector3 = dolls[3].centre_of_mass()
	# (кадр ставится до толчка, P4 на спавне): ряд P1..P3 с руками (от −3.3 м) и полёт P4 вправо до ≈ 8 м
	var cx: float = clampf(c.x - 2.6, 0.0, 7.0)
	cam.fov = 40
	cam.position = Vector3(cx, 1.4, 9.5)
	cam.look_at(Vector3(cx, 0.95, 0))


func _physics_process(delta: float) -> void:
	t += delta
	for d in dolls:
		d.input_vec = Vector2.ZERO
	# четвёртая кукла: толчок вправо и вверх — конечности отстают, поза «летит»
	if t > PUSH_T0 and t < PUSH_T1:
		dolls[3].input_vec = Vector2(1, 0.4)


func _process(_delta: float) -> void:
	if busy:
		return
	if stage == 0 and t >= FRONT_T:
		busy = true
		await _capture("doll_front.png")
		_frame_closeup()
		stage = 1
		busy = false
	elif stage == 1 and t >= CLOSEUP_T:
		busy = true
		await _capture("doll_closeup.png")
		_frame_action()
		stage = 2
		busy = false
	elif stage == 2 and t >= ACTION_T:
		busy = true
		await _capture("doll_action.png")
		get_tree().quit(0)


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(name)
	var err := img.save_png(path)
	print("saved ", path, " (", err, ") at t=", snappedf(t, 0.01))
