## Визуальная и численная проверка параллакс-фона (scenes/arena/parallax_background.tscn).
## Кадры: камера fov 45 в (0, 4, 20) → tests/parallax_a.png; затем камера на 8 м правее и 2 м выше → tests/parallax_b.png.
## В сцене: честный свет (солнце с тенями, небо-ambient, SSAO, ACES), линия земли (плита 40 м, верх y=0),
## кукла из scenes/doll/doll.tscn для масштаба.
## Проверки (JSON в stdout, exit 1 при провале): четыре слоя-квада с unshaded-материалом; слой 4 закрывает фрустум
## камеры во всём диапазоне игровой камеры; слой 3 закрывает низ кадра и ширину; кромка слоя 1 в пересчёте на
## плоскость боя не выше 0.4 м над ногами; кадры a и b различаются (слои сдвинулись).
## Запуск: godot --path . --resolution 1280x720 --position 100,100 res://tests/parallax_snapshot.tscn -- "out=res://tests/"
extends Node3D

const BgScene := preload("res://scenes/arena/parallax_background.tscn")
const DollScene := preload("res://scenes/doll/doll.tscn")
const CAM_A := Vector3(0, 4, 20)
const CAM_B := Vector3(8, 6, 20)
const FOV := 45.0
## Диапазон игровой камеры (DynamicCamera: центр y 2.5..10, x ±12, z 10..22) — слой 4 обязан закрывать фрустум везде.
const CAM_RANGE := [Vector3(0, 4, 20), Vector3(8, 6, 20), Vector3(-12, 2.5, 10), Vector3(12, 10, 22), Vector3(12, 2.5, 22)]

var bg: ParallaxBackground3D
var doll: Node3D
var cam: Camera3D
var t := 0.0
var stage := 0
var busy := false
var out_dir := "res://tests/"
var report := {"ok": true, "checks": []}
var img_a: Image


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "out":
				out_dir = p[1]
	_lighting()
	_floor()
	bg = BgScene.instantiate()
	add_child(bg)
	doll = DollScene.instantiate()
	doll.player_index = 0
	doll.external_input = true
	add_child(doll)
	doll.position = Vector3(0, 0, 0)
	cam = Camera3D.new()
	cam.fov = FOV
	cam.position = CAM_A
	add_child(cam)
	cam.make_current()
	_check_static()


func _lighting() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.36, 0.55, 0.84)
	sm.sky_horizon_color = Color(0.78, 0.82, 0.88)
	sm.ground_bottom_color = Color(0.40, 0.38, 0.36)
	sm.ground_horizon_color = Color(0.66, 0.66, 0.68)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 1.0
	e.ambient_light_energy = 0.6
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 0.85
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
	fill.light_energy = 0.3
	fill.light_color = Color(0.80, 0.86, 1.0)
	add_child(fill)


## Линия земли: плита 40×0.5×2 м, верх на y=0 (ноги куклы), как плиты арены.
func _floor() -> void:
	var f := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(40, 0.5, 2)
	cs.shape = bs
	f.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(40, 0.5, 2)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.52, 0.49, 0.44)
	mat.roughness = 0.95
	mi.material_override = mat
	f.add_child(mi)
	f.position = Vector3(0, -0.25, 0)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	f.physics_material_override = pm
	add_child(f)


func _check(id: String, ok: bool, value, limit) -> void:
	report["checks"].append({"id": id, "ok": ok, "value": value, "limit": limit})
	if not ok:
		report["ok"] = false


## Прямоугольник квада-слоя в мире: [x0, y0, x1, y1] и z.
func _quad_rect(l: MeshInstance3D) -> Array:
	var q := l.mesh as QuadMesh
	var p := l.global_position
	return [p.x - q.size.x / 2.0, p.y - q.size.y / 2.0, p.x + q.size.x / 2.0, p.y + q.size.y / 2.0, p.z]


## Видимый прямоугольник камеры c (fov по вертикали, аспект окна) на глубине z.
func _view_rect(c: Vector3, z: float) -> Array:
	var vs := get_viewport().get_visible_rect().size
	var hh := tan(deg_to_rad(FOV / 2.0)) * (c.z - z)
	var hw := hh * vs.x / vs.y
	return [c.x - hw, c.y - hh, c.x + hw, c.y + hh]


func _check_static() -> void:
	var names := ["Layer4Sky", "Layer3Far", "Layer2Mid", "Layer1Fore"]
	var found := 0
	for n in names:
		var l := bg.layer(n)
		if l == null or not (l.mesh is QuadMesh):
			continue
		found += 1
		var m := l.get_active_material(0) as StandardMaterial3D
		_check("unshaded_" + n, m != null and m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, m.shading_mode if m else "null", BaseMaterial3D.SHADING_MODE_UNSHADED)
		_check("no_shadow_" + n, l.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, l.cast_shadow, 0)
	_check("layers_found", found == 4, found, 4)
	if found < 4:
		return
	# слой 4 закрывает фрустум для всех положений игровой камеры (с запасом 1 м)
	var r4 := _quad_rect(bg.layer("Layer4Sky"))
	var worst := INF
	for c in CAM_RANGE:
		var v := _view_rect(c, r4[4])
		worst = minf(worst, minf(minf(v[0] - r4[0], r4[2] - v[2]), minf(v[1] - r4[1], r4[3] - v[3])))
	_check("layer4_covers_frustum_margin_m", worst >= 1.0, snappedf(worst, 0.01), ">= 1.0")
	# слой 3: ширина и низ кадра закрыты (верх у него прозрачный — там горы слоя 4)
	var r3 := _quad_rect(bg.layer("Layer3Far"))
	worst = INF
	for c in CAM_RANGE:
		var v := _view_rect(c, r3[4])
		worst = minf(worst, minf(minf(v[0] - r3[0], r3[2] - v[2]), v[1] - r3[1]))
	_check("layer3_covers_width_bottom_margin_m", worst >= 0.5, snappedf(worst, 0.01), ">= 0.5")
	# кромка слоя 1 (непрозрачный верх, metadata/opaque_top_y) в пересчёте на плоскость боя z=0 от камеры A
	var l1 := bg.layer("Layer1Fore")
	var top: float = float(l1.get_meta("opaque_top_y", l1.global_position.y + (l1.mesh as QuadMesh).size.y / 2.0))
	var top_play := CAM_A.y + (top - CAM_A.y) * CAM_A.z / (CAM_A.z - l1.global_position.z)
	_check("layer1_edge_above_feet_m", top_play <= 0.4, snappedf(top_play, 0.01), "<= 0.4")
	# слой 2: линия земли чуть ниже плит арены (0..0.4) и не глубже 1 м под ними в пересчёте на плоскость боя
	var l2 := bg.layer("Layer2Mid")
	var g2: float = float(l2.get_meta("ground_y", l2.global_position.y - (l2.mesh as QuadMesh).size.y / 2.0))
	var g2_play := CAM_A.y + (g2 - CAM_A.y) * CAM_A.z / (CAM_A.z - l2.global_position.z)
	_check("layer2_ground_below_arena_m", g2_play <= 0.4 and g2_play >= -1.0, snappedf(g2_play, 0.01), "[-1.0, 0.4]")


func _physics_process(delta: float) -> void:
	t += delta
	if doll:
		doll.input_vec = Vector2.ZERO


func _process(_delta: float) -> void:
	if busy:
		return
	if stage == 0 and t >= 0.5:
		busy = true
		img_a = await _capture("parallax_a.png")
		cam.position = CAM_B
		stage = 1
		busy = false
	elif stage == 1 and t >= 0.8:
		busy = true
		var img_b := await _capture("parallax_b.png")
		_check_frames(img_a, img_b)
		print(JSON.stringify(report))
		get_tree().quit(0 if report["ok"] else 1)


## Кадры должны отличаться заметно (слои сдвинулись): средняя по пикселям сумма |Δr|+|Δg|+|Δb|.
func _check_frames(a: Image, b: Image) -> void:
	if a == null or b == null:
		_check("frames_saved", false, "null", "2 images")
		return
	var w := a.get_width()
	var h := a.get_height()
	var diff := 0.0
	var n := 0
	var y := 8
	while y < h:
		var x := 8
		while x < w:
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			diff += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			n += 1
			x += 16
		y += 16
	var mean_diff := diff / maxf(n, 1)
	_check("frames_differ_sum_rgb", mean_diff > 0.03, snappedf(mean_diff, 0.001), "> 0.03")
	# верхняя строка кадра A — небо слоя 4 (голубое), нижняя — слой 1 (не голубое небо)
	var top := a.get_pixel(w / 2, 4)
	var bottom := a.get_pixel(w / 2, h - 4)
	_check("top_is_sky", top.b > top.r + 0.1 and top.b > 0.45, "%.2f %.2f %.2f" % [top.r, top.g, top.b], "b > r+0.1")
	_check("bottom_is_not_sky", not (bottom.b > bottom.r + 0.1 and bottom.b > 0.45), "%.2f %.2f %.2f" % [bottom.r, bottom.g, bottom.b], "not sky")


func _capture(name: String) -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(name)
	var err := img.save_png(path)
	print("saved ", path, " (", err, ") at t=", snappedf(t, 0.01))
	return img
