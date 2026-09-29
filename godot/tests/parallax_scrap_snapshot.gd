## Визуальная и численная проверка параллакс-фона Свалки (scenes/arena/parallax_scrap.tscn, биом 1 THE SCRAP).
## Кадры (камера fov 45, как DynamicCamera): A (0, 4, 20) — по умолчанию; B (11, 7, 15) — панорама вправо-вверх
## с приближением; C (−13, 2.5, 10) — максимальное приближение у левого края. PNG → docs/plan-demo/img/
## scrap-parallax-godot-v1a/b/c.png (или в out=…).
## В сцене: свет и тонмаппинг арены «Руин» (assets/environments/ruins_env.tres + ruins_camera.tres с DoF дали —
## как в игре; dof=0 выключает), но фон окружения — пурпурный: любой пурпур в кадре = дыра между слоями.
## Плоскость боя: пол 40 м (верх y=0), платформы до 8 м и манекены 1.8 м — только для масштаба (без физики).
## Проверки (JSON в stdout, exit 1 при провале): четыре слоя-квада unshaded/без тени/без тумана; небо закрывает
## фрустум для всех точек диапазона игровой камеры (CAM_XZ × CAM_Y: z 10..24, y 2.5..10, x по клэмпу арены 40 м —
## как в tools/parallax_cut_scrap.py); слои 3, 2 и передний план закрывают ширину и низ кадра; кромка переднего плана
## на плоскости боя не выше 0.4 м, линия земли слоя 2 — в [−1.0, 0.4] м (из камеры A); в кадрах нет пурпура;
## кадры A и B различаются.
## v2 (scenes/arena/parallax_scrap_v2.tscn): scene=v2 → кадры scrap-parallax-godot-v2a/b/c.png; дополнительно
## проверка резкости: экранных пикселей на тексель в ближайшей точке диапазона камеры при 1080p ≤ max_mag
## (metadata/max_mag слоя; слои без неё — только в отчёте). Нижняя граница линии земли слоя 2 — metadata/ground_play_min.
## Запуск (не headless — нужен рендер): godot --path . --resolution 1280x720 --position 100,100
##   res://tests/parallax_scrap_snapshot.tscn -- "out=/abs/dir/,dof=0,scene=v2"
extends Node3D

const SCENES := {"v1": "res://scenes/arena/parallax_scrap.tscn", "v2": "res://scenes/arena/parallax_scrap_v2.tscn"}
const FOV := 45.0
const CAMS := [Vector3(0, 4, 20), Vector3(11, 7, 15), Vector3(-13, 2.5, 10)]
const SUFFIX := ["a", "b", "c"]
## Диапазон игровой камеры Свалки (арена ~40 м по x, пол y=0, платформы до 8 м): на каждом зуме z центр по x
## клэмпится так, чтобы кадр не выходил за ±20 м (|x| ≤ 20 − 0.736·z, здесь с запасом ~0.4 м), по y — весь 2.5..10.
const CAM_XZ := [Vector2(13.0, 10.0), Vector2(8.5, 16.0), Vector2(5.5, 20.0), Vector2(2.5, 24.0)]
const CAM_Y := [2.5, 10.0]
const HOLE := Color(1.0, 0.0, 1.0)

var bg: ParallaxBackground3D
var cam: Camera3D
var t := 0.0
var stage := 0
var busy := false
var out_dir := ""
var use_dof := true
var tag := "v1"
var pan := 0  # pan=N — ещё N кадров проезда камеры x −13 → 13 (z 12, y 4) в out/pan_<tag>/ (для GIF)
var dof_override := {}  # dofd/doft/dofa — подбор DOF дали: distance / transition / amount
var report := {"ok": true, "checks": []}
var frames: Array[Image] = []


func _ready() -> void:
	out_dir = ProjectSettings.globalize_path("res://").path_join("../docs/plan-demo/img").simplify_path()
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			if p[0] == "out":
				out_dir = p[1]
			elif p[0] == "dof":
				use_dof = p[1] != "0"
			elif p[0] == "pan":
				pan = int(p[1])
			elif p[0] == "scene" and SCENES.has(p[1]):
				tag = p[1]
			elif p[0] in ["dofd", "doft", "dofa"]:
				dof_override[p[0]] = float(p[1])
	_lighting()
	_play_plane()
	bg = (load(SCENES[tag]) as PackedScene).instantiate()
	add_child(bg)
	cam = Camera3D.new()
	cam.fov = FOV
	cam.position = CAMS[0]
	if use_dof and ResourceLoader.exists("res://assets/environments/ruins_camera.tres"):
		var ca := (load("res://assets/environments/ruins_camera.tres") as CameraAttributesPractical).duplicate()
		ca.dof_blur_far_distance = dof_override.get("dofd", ca.dof_blur_far_distance)
		ca.dof_blur_far_transition = dof_override.get("doft", ca.dof_blur_far_transition)
		ca.dof_blur_amount = dof_override.get("dofa", ca.dof_blur_amount)
		cam.attributes = ca
	add_child(cam)
	cam.make_current()
	_check_static()


func _lighting() -> void:
	var env := WorldEnvironment.new()
	var e: Environment
	if ResourceLoader.exists("res://assets/environments/ruins_env.tres"):
		e = (load("res://assets/environments/ruins_env.tres") as Environment).duplicate()
	else:
		e = Environment.new()
		e.tonemap_mode = Environment.TONE_MAPPER_ACES
	# фон — сигнальный пурпур (дыры); свет окружения берём из неба ruins_env, как в игре
	e.background_mode = Environment.BG_COLOR
	e.background_color = HOLE
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28, 62, 0)  # закатное солнце справа-спереди, как на листе
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.78, 0.55)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -120, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.70, 0.72, 1.0)
	add_child(fill)


## Пол арены 40 × 3 м (верх y=0), платформы на 3 / 4.5 / 6.5 / 8 м и два манекена 1.8 м — масштаб плоскости боя.
func _play_plane() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.27, 0.19)
	wood.roughness = 0.9
	_box(Vector3(0, -1.5, 0), Vector3(40, 3, 2), wood)
	for p in [Vector3(-10, 3, 0), Vector3(8, 4.5, 0), Vector3(-2, 6.5, 0), Vector3(13, 8, 0)]:
		_box(p - Vector3(0, 0.3, 0), Vector3(5, 0.6, 2), wood)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.68, 0.45)
	skin.roughness = 0.7
	for x in [-1.5, 1.5]:
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.28
		cm.height = 1.8
		mi.mesh = cm
		mi.material_override = skin
		mi.position = Vector3(x, 0.9, 0)
		add_child(mi)


func _box(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


func _check(id: String, ok: bool, value, limit) -> void:
	report["checks"].append({"id": id, "ok": ok, "value": value, "limit": limit})
	if not ok:
		report["ok"] = false


## Прямоугольник квада-слоя в мире: [x0, y0, x1, y1, z].
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


func _cam_points() -> Array:
	var out := []
	for xz in CAM_XZ:
		for sx in [-1.0, 1.0]:
			for y in CAM_Y:
				out.append(Vector3(sx * xz.x, y, xz.y))
	return out


## Худший запас (м) покрытия фрустума квадом по сторонам sides = [лево, низ, право, верх].
func _cover_margin(r: Array, sides: Array) -> float:
	var worst := INF
	for c in _cam_points():
		var v := _view_rect(c, r[4])
		var m := [v[0] - r[0], v[1] - r[1], r[2] - v[2], r[3] - v[3]]
		for i in 4:
			if sides[i]:
				worst = minf(worst, m[i])
	return worst


## Высота y на глубине z, пересчитанная на плоскость боя z=0 по лучу из камеры c.
func _to_play(c: Vector3, y: float, z: float) -> float:
	return c.y + (y - c.y) * c.z / (c.z - z)


func _check_static() -> void:
	var names := ["Layer4Sky", "Layer3Far", "Layer2Mid", "Layer1Fore"]
	var found := 0
	for n in names:
		var l := bg.layer(n)
		if l == null or not (l.mesh is QuadMesh):
			continue
		found += 1
		var mat := l.get_active_material(0)
		var m := mat as StandardMaterial3D
		var sm := mat as ShaderMaterial
		if sm != null:  # v2: небо и башни — шейдер parallax_layer_wrap* (продолжение за края картинки)
			var code := sm.shader.code if sm.shader else ""
			_check("unshaded_" + n, code.contains("unshaded"), "shader", "render_mode unshaded")
			_check("no_fog_" + n, code.contains("fog_disabled"), "shader", "render_mode fog_disabled")
		else:
			_check("unshaded_" + n, m != null and m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, m.shading_mode if m else "null", BaseMaterial3D.SHADING_MODE_UNSHADED)
			_check("no_fog_" + n, m != null and m.disable_fog, m.disable_fog if m else "null", true)
		_check("no_shadow_" + n, l.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, l.cast_shadow, 0)
	_check("layers_found", found == 4, found, 4)
	if found < 4:
		return
	var m4 := _cover_margin(_quad_rect(bg.layer("Layer4Sky")), [true, true, true, true])
	_check("sky_covers_frustum_margin_m", m4 >= 1.0, snappedf(m4, 0.01), ">= 1.0")
	var m3 := _cover_margin(_quad_rect(bg.layer("Layer3Far")), [true, true, true, false])
	_check("far_covers_width_bottom_margin_m", m3 >= 0.5, snappedf(m3, 0.01), ">= 0.5")
	# v2: низ среднего плана растворяется сам, низ кадра за ним закрывает квад тумана Layer2Fog
	var fog := bg.get_node_or_null("Layer2Fog") as MeshInstance3D
	var m2 := _cover_margin(_quad_rect(bg.layer("Layer2Mid")), [true, fog == null, true, false])
	_check("mid_covers_width_bottom_margin_m", m2 >= 0.5, snappedf(m2, 0.01), ">= 0.5")
	if fog != null:
		var mf := _cover_margin(_quad_rect(fog), [true, true, true, false])
		_check("fog_covers_width_bottom_margin_m", mf >= 0.5, snappedf(mf, 0.01), ">= 0.5")
	var m1 := _cover_margin(_quad_rect(bg.layer("Layer1Fore")), [true, true, true, false])
	_check("fore_covers_width_bottom_margin_m", m1 >= 0.5, snappedf(m1, 0.01), ">= 0.5")
	var a: Vector3 = CAMS[0]
	var l1 := bg.layer("Layer1Fore")
	var top1 := float(l1.get_meta("opaque_top_y", _quad_rect(l1)[3]))
	var top_play := _to_play(a, top1, l1.global_position.z)
	_check("fore_edge_above_feet_m", top_play <= 0.4, snappedf(top_play, 0.01), "<= 0.4")
	var l2 := bg.layer("Layer2Mid")
	var g2 := float(l2.get_meta("ground_y", _quad_rect(l2)[1]))
	var g2_play := _to_play(a, g2, l2.global_position.z)
	var g2_min := float(l2.get_meta("ground_play_min", -1.0))
	_check("mid_ground_below_floor_m", g2_play <= 0.4 and g2_play >= g2_min, snappedf(g2_play, 0.01),
			"[%s, 0.4]" % g2_min)
	for n in names:
		_check_magnification(bg.layer(n), n)


## Резкость: экранных пикселей 1080p на пиксель ИСТОЧНИКА в ближайшей к слою точке диапазона камеры (min z камеры = 10).
## > 1 — растянуто. Ширина источника — metadata/source_px_w слоя (текстуры v1 апскейлены до 4096 из полос листа
## по ~1363 пкс, по ширине текстуры они выглядели бы резкими); без метаданных — ширина текстуры.
func _check_magnification(l: MeshInstance3D, n: String) -> void:
	var mat := l.get_active_material(0)
	var tex: Texture2D = null
	if mat is StandardMaterial3D:
		tex = (mat as StandardMaterial3D).albedo_texture
	elif mat is ShaderMaterial:
		tex = (mat as ShaderMaterial).get_shader_parameter("tex") as Texture2D
	if tex == null:
		return
	var q := l.mesh as QuadMesh
	var src_w := float(l.get_meta("source_px_w", tex.get_width()))
	var texel_per_m := src_w / float(l.get_meta("tex_span_m", q.size.x))
	var d := 10.0 - l.global_position.z
	var px_per_m := 1080.0 / (2.0 * tan(deg_to_rad(FOV / 2.0)) * d)
	var mag := snappedf(px_per_m / texel_per_m, 0.01)
	if l.has_meta("max_mag"):
		var lim := float(l.get_meta("max_mag"))
		_check("mag_1080_" + n, mag <= lim, mag, "<= %s" % lim)
	else:
		report["checks"].append({"id": "mag_1080_" + n, "ok": true, "value": mag, "limit": "info"})


func _process(delta: float) -> void:
	t += delta
	if busy:
		return
	if stage < CAMS.size() and t >= 0.5 + 0.3 * stage:
		busy = true
		cam.position = CAMS[stage]
		var img := await _capture("scrap-parallax-godot-%s%s.png" % [tag, SUFFIX[stage]])
		frames.append(img)
		stage += 1
		busy = false
	elif stage == CAMS.size():
		stage += 1
		busy = true
		if pan > 0:
			var dir := out_dir.path_join("pan_" + tag)
			DirAccess.make_dir_recursive_absolute(dir)
			for i in pan:
				cam.position = Vector3(lerpf(-13.0, 13.0, float(i) / float(maxi(pan - 1, 1))), 4.0, 12.0)
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(dir.path_join("pan_%03d.png" % i))
		_check_frames()
		print(JSON.stringify(report))
		get_tree().quit(0 if report["ok"] else 1)


## Дыры (пурпур фона окружения) и различие кадров A/B.
func _check_frames() -> void:
	if frames.size() < 2 or frames[0] == null or frames[1] == null:
		_check("frames_saved", false, frames.size(), ">= 2 images")
		return
	var holes := 0
	var total := 0
	for img in frames:
		var w := img.get_width()
		var h := img.get_height()
		for y in range(0, h, 2):
			for x in range(0, w, 2):
				var c := img.get_pixel(x, y)
				total += 1
				if c.r > 0.6 and c.b > 0.6 and c.g < 0.3:
					holes += 1
	_check("no_holes_px", holes == 0, holes, "0 of %d" % total)
	var a := frames[0]
	var b := frames[1]
	var diff := 0.0
	var n := 0
	for y in range(8, a.get_height(), 16):
		for x in range(8, a.get_width(), 16):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			diff += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			n += 1
	var mean_diff := diff / maxf(n, 1)
	_check("frames_differ_sum_rgb", mean_diff > 0.03, snappedf(mean_diff, 0.001), "> 0.03")
	# низ кадра A — тёмный хлам переднего плана, верх — небо (не тёмное)
	var bottom := a.get_pixel(a.get_width() / 2, a.get_height() - 4)
	var top := a.get_pixel(a.get_width() / 2, 4)
	_check("bottom_is_dark_fore", bottom.get_luminance() < 0.25, snappedf(bottom.get_luminance(), 0.01), "< 0.25")
	_check("top_is_sky", top.get_luminance() > 0.1 and top.b > top.r, [snappedf(top.get_luminance(), 0.01),
			snappedf(top.b - top.r, 0.01)], "lum > 0.1, b > r")


func _capture(file: String) -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(file)
	var err := img.save_png(path)
	print("saved ", path, " (", err, ") cam=", cam.position, " t=", snappedf(t, 0.01))
	return img
