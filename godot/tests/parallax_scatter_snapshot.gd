## Процедурный параллакс Свалки (scenes/arena/parallax_scrap_scatter.tscn: небо и дальний фон — слои v2, средний и
## передний планы — ParallaxScatter3D из элементов; сейчас элементы — грейбокс). Кадры A/B/C как у
## parallax_scrap_snapshot (fov 45) → docs/plan-demo/img/scrap-parallax-scatter-{a,b,c}.png (или out=…); pan=N —
## ещё N кадров проезда камеры x −13 → 13 (z 12, y 4) в out/pan/pan_%03d.png (для GIF).
## Проверки (JSON в stdout, exit 1 при провале):
##   • в каждой полосе есть элементы, все z внутри z_range полосы, раскладка детерминирована (вторая сборка
##     с теми же полосами даёт те же x/z/h/flip);
##   • элементы полосы покрывают x_extent(дальняя z) — первый начинается левее, последний кончается правее;
##   • резкость: экранных пикселей 1080p на тексель в ближайшей точке камеры (z = 10) ≤ MAX_MAG для полос
##     среднего/дальнего плана (передний план — только в отчёт: требование к разрешению арта, см. PARALLAX.md);
##   • передний план не закрывает бой: доля площади зоны боя (x ±18, y 0..10 на z=0), закрытая элементами полос
##     с z > 0 (проекция из камеры × fill элемента), ≤ MAX_FORE_COVER для кадров A, B, C;
##   • в кадрах нет пурпура фона (дыр), кадры A и B различаются.
## Запуск (не headless — нужен рендер): godot --path . --resolution 1920x1080 --position 100,100
##   res://tests/parallax_scatter_snapshot.tscn -- "out=/abs/dir/,dof=0,pan=48"
extends Node3D

const SCENE := "res://scenes/arena/parallax_scrap_scatter.tscn"
const FOV := 45.0
const CAMS := [Vector3(0, 4, 20), Vector3(11, 7, 15), Vector3(-13, 2.5, 10)]
const SUFFIX := ["a", "b", "c"]
const HOLE := Color(1.0, 0.0, 1.0)
const MAX_MAG := 1.6
const MAX_FORE_COVER := 0.08
const FIGHT := Rect2(-18.0, 0.0, 36.0, 10.0)

var root: Node3D
var scatter: ParallaxScatter3D
var cam: Camera3D
var out_dir := ""
var use_dof := true
var pan := 0
var report := {"ok": true, "checks": [], "bands": []}
var frames: Array[Image] = []


func _ready() -> void:
	out_dir = ProjectSettings.globalize_path("res://").path_join("../docs/plan-demo/img").simplify_path()
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			match p[0]:
				"out": out_dir = p[1]
				"dof": use_dof = p[1] != "0"
				"pan": pan = int(p[1])
	_lighting()
	_play_plane()
	root = (load(SCENE) as PackedScene).instantiate()
	add_child(root)
	scatter = root.get_node("Scatter") as ParallaxScatter3D
	cam = Camera3D.new()
	cam.fov = FOV
	cam.position = CAMS[0]
	if use_dof:
		var ca := CameraAttributesPractical.new()  # как у арены Свалки (build_arena_scrap.gd)
		ca.dof_blur_far_enabled = true
		ca.dof_blur_far_distance = 45.0
		ca.dof_blur_far_transition = 70.0
		ca.dof_blur_amount = 0.03
		cam.attributes = ca
	add_child(cam)
	cam.make_current()
	_check_static()
	_run.call_deferred()


func _lighting() -> void:
	var env := WorldEnvironment.new()
	var e: Environment
	if ResourceLoader.exists("res://assets/environments/scrap_env.tres"):
		e = (load("res://assets/environments/scrap_env.tres") as Environment).duplicate()
	else:
		e = Environment.new()
		e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.background_mode = Environment.BG_COLOR  # пурпур = дыра между слоями
	e.background_color = HOLE
	e.fog_enabled = false
	e.volumetric_fog_enabled = false
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28, 62, 0)
	sun.light_color = Color(1.0, 0.78, 0.55)
	add_child(sun)


## Масштаб плоскости боя: пол 40 м (верх y=0), платформы и два манекена 1.8 м.
func _play_plane() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.27, 0.19)
	_box(Vector3(0, -1.5, 0), Vector3(40, 3, 2), wood)
	for p in [Vector3(-10, 3, 0), Vector3(8, 4.5, 0), Vector3(-2, 6.5, 0), Vector3(13, 8, 0)]:
		_box(p - Vector3(0, 0.3, 0), Vector3(5, 0.6, 2), wood)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.68, 0.45)
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


func _check_static() -> void:
	var pl := scatter.placements
	for bi in scatter.bands.size():
		var b := scatter.bands[bi]
		var mine := pl.filter(func(p: Dictionary) -> bool: return p["band"] == bi)
		var info := {"band": bi, "dir": b.dir.get_file(), "anchors": Array(b.anchors), "count": mine.size()}
		_check("band%d_has_elements" % bi, mine.size() > 0, mine.size(), "> 0")
		if mine.is_empty():
			report["bands"].append(info)
			continue
		var z_ok := mine.all(func(p: Dictionary) -> bool:
			return p["z"] >= b.z_range.x - 0.001 and p["z"] <= b.z_range.y + 0.001)
		_check("band%d_z_in_range" % bi, z_ok, z_ok, true)
		# покрытие ширины — только у плотных полос (подвешенные цепи редкие по замыслу)
		if b.gap_m.y < 6.0:
			var ext := scatter.x_extent(b.z_range.x)
			var first: Dictionary = mine[0]
			var lastp: Dictionary = mine[mine.size() - 1]
			var l_edge: float = first["x"] - first["w"] / 2.0
			var r_edge: float = lastp["x"] + lastp["w"] / 2.0
			_check("band%d_covers_width" % bi, l_edge <= ext.x and r_edge >= ext.y,
					[snappedf(l_edge, 0.1), snappedf(r_edge, 0.1)], [snappedf(ext.x, 0.1), snappedf(ext.y, 0.1)])
		# резкость в ближайшей точке камеры (z = 10)
		var worst := 0.0
		for p in mine:
			var d: float = 10.0 - p["z"]
			var px_per_m := 1080.0 / (2.0 * tan(deg_to_rad(FOV / 2.0)) * d)
			var texel_per_m: float = float(p["tex_h"]) / p["h"]
			worst = maxf(worst, px_per_m / texel_per_m)
		info["mag_1080_max"] = snappedf(worst, 0.01)
		if b.z_range.y < 0.0:
			_check("band%d_mag_1080" % bi, worst <= MAX_MAG, snappedf(worst, 0.01), "<= %s" % MAX_MAG)
		else:
			# передний план: какой высоты (пкс) нужен арт, чтобы на ближнем зуме было ×1 — в отчёт и бриф
			info["fore_px_needed_per_m"] = snappedf(1080.0 / (2.0 * tan(deg_to_rad(FOV / 2.0)) * (10.0 - b.z_range.y)), 1)
		report["bands"].append(info)
	# детерминизм: вторая сборка с теми же полосами
	var twin := ParallaxScatter3D.new()
	twin.bands = scatter.bands
	twin.cam_points = scatter.cam_points
	add_child(twin)
	var same := twin.placements.size() == pl.size()
	if same:
		for i in pl.size():
			var a: Dictionary = pl[i]
			var b2: Dictionary = twin.placements[i]
			if not (is_equal_approx(a["x"], b2["x"]) and is_equal_approx(a["z"], b2["z"]) \
					and is_equal_approx(a["h"], b2["h"]) and a["flip"] == b2["flip"] and a["file"] == b2["file"]):
				same = false
				break
	_check("deterministic", same, [pl.size(), twin.placements.size()], "same placements")
	twin.queue_free()
	for i in CAMS.size():
		var cover := _fore_cover(CAMS[i])
		_check("fore_cover_fight_%s" % SUFFIX[i], cover <= MAX_FORE_COVER, snappedf(cover, 0.001), "<= %s" % MAX_FORE_COVER)


## Доля зоны боя (FIGHT на z=0), закрытая элементами перед плоскостью боя (z > 0) из камеры c.
func _fore_cover(c: Vector3) -> float:
	var area := 0.0
	for p in scatter.placements:
		var z: float = p["z"]
		if z <= 0.0:
			continue
		var k := c.z / (c.z - z)  # проекция точки с глубины z на плоскость z=0 лучом из камеры
		var x0: float = c.x + (p["x"] - p["w"] / 2.0 - c.x) * k
		var x1: float = c.x + (p["x"] + p["w"] / 2.0 - c.x) * k
		var y0: float = c.y + (p["y"] - p["h"] / 2.0 - c.y) * k
		var y1: float = c.y + (p["y"] + p["h"] / 2.0 - c.y) * k
		var r := Rect2(x0, y0, x1 - x0, y1 - y0).intersection(FIGHT)
		area += r.get_area() * float(p["fill"])
	return area / FIGHT.get_area()


func _run() -> void:
	await get_tree().process_frame
	for i in CAMS.size():
		cam.position = CAMS[i]
		frames.append(await _capture(out_dir.path_join("scrap-parallax-scatter-%s.png" % SUFFIX[i])))
	if pan > 0:
		DirAccess.make_dir_recursive_absolute(out_dir.path_join("pan"))
		for i in pan:
			var t := float(i) / float(maxi(pan - 1, 1))
			cam.position = Vector3(lerpf(-13.0, 13.0, t), 4.0, 12.0)
			await _capture(out_dir.path_join("pan/pan_%03d.png" % i), false)
	_check_frames()
	print(JSON.stringify(report))
	get_tree().quit(0 if report["ok"] else 1)


func _check_frames() -> void:
	var holes := 0
	var total := 0
	for img in frames:
		for y in range(0, img.get_height(), 2):
			for x in range(0, img.get_width(), 2):
				var c := img.get_pixel(x, y)
				total += 1
				if c.r > 0.6 and c.b > 0.6 and c.g < 0.3:
					holes += 1
	_check("no_holes_px", holes == 0, holes, "0 of %d" % total)
	var diff := 0.0
	var n := 0
	for y in range(8, frames[0].get_height(), 16):
		for x in range(8, frames[0].get_width(), 16):
			var ca := frames[0].get_pixel(x, y)
			var cb := frames[1].get_pixel(x, y)
			diff += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			n += 1
	_check("frames_differ_sum_rgb", diff / maxf(n, 1) > 0.03, snappedf(diff / maxf(n, 1), 0.001), "> 0.03")


func _capture(path: String, log := true) -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	if log:
		print("saved ", path, " cam=", cam.position)
	return img
