## Витрина арены «Void» v6 (res://scenes/playground_void.tscn как есть: пустое чёрное поле RM, P1 клён / P2 орех на спавнах
## x=∓3, DynamicCamera fov 24° с fit_bounds, Match + HUD). Отсчёт Match 0, ввод кукол — из теста (external_input).
##   <out>/05-void-<tag>-close.png — t=close_t: камера боя по умолчанию, куклы стоят на спавнах (кадр RM: кукла ≈ 1/3 кадра);
##   <out>/05-void-<tag>-wide.png  — P1 толкают влево, P2 вправо push с; через wide_wait с после толчка камера плавно
##                                   отъехала до всего поля (полосы стен по краям, пол внизу, пустоты за ними нет).
## Числовые проверки (яркость — sRGB-люма 0..1; точки мира проецируются камерой в пиксели кадра):
##   standing / at_rest — ЦМ над корнем > 0.6 м, скорость частей < rest_v (кадр close);
##   close_half_height — полувысота камеры на спавне в [2.6, 3.2] м; close_doll_frac_P1/P2 — рост куклы в кадре (проекция
##   AABB видимых мешей) ≥ min_frac высоты кадра; frame_in_bounds — кадр камеры (плоскость кукол) ни в одном кадре прогона
##   не выходит за bounds() арены; wide_half_height ≥ 3.9 и frame_covers_field (края кадра за x=±6.95 — всё поле);
##   bg_black — фон между линиями сетки < 0.05; grid_visible / grid_faint — линия сетки ярче середины клетки на > 0.008
##   и < 0.12 («едва видна»); doll_p1_reads / doll_p2_reads — торс клёна/ореха ярче фона на > 0.15 / > 0.06;
##   floor_front_grey — передняя грань пола ярче фона на > 0.12; floor_top_darker — верх пола темнее передней грани
##   (нет светлой трапеции); wide_wall_band — передняя грань стены видна полосой (ярче фона на > 0.015), но темнее пола.
## Параметры камеры можно подменить для сравнения «до/после»: cam_fov, cam_min_h, cam_pad, cam_pad_y, cam_fit (0/1).
## Запуск (окно, нативно arm64): godot --path godot --resolution 1280x720 --position 100,100 --always-on-top
##   res://tests/void_snapshot.tscn -- "close_t=3.0,push=1.4,wide_wait=2.2,min_frac=0.28,tag=v6,out=<абс. путь>"
##   (out по умолчанию docs/plan-demo/img). Отчёт tests/void_snapshot_report.json, exit 0/1.
extends Node3D

const SCENE := "res://scenes/playground_void.tscn"
const BACKDROP_Z := -6.0
const FIELD_HALF_W := 7.0
const FLOOR_FRONT_Z := 0.5      # передняя грань плиты пола и стен (видимая глубина моделей 1 м)
const WALL_MID_X := 7.5         # середина стены (внутренняя грань 7, внешняя 8)

var cfg := {"close_t": 3.0, "push": 1.4, "wide_wait": 2.2, "rest_v": 0.8, "min_frac": 0.28,
	"cam_fov": -1.0, "cam_min_h": -1.0, "cam_pad": -1.0, "cam_pad_y": -2.0, "cam_fit": -1.0}
var out_dir := ""
var tag := "v6"
var pg: Node3D
var p1: Doll
var p2: Doll
var cam: DynamicCamera
var arena: Node
var match_node: Match
var t := 0.0
var stage := 0
var busy := false
var push_from := INF
var in_bounds := true
var worst_bounds := 0.0
var hh_track: Array = []       # [t, half_height] во время отъезда
var report := {"ok": true, "checks": [], "shots": [], "info": {}}


func _ready() -> void:
	out_dir = ProjectSettings.globalize_path("res://").path_join("../docs/plan-demo/img").simplify_path()
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			if p[0] == "out":
				out_dir = p[1]
			elif p[0] == "tag":
				tag = p[1]
			elif cfg.has(p[0]):
				cfg[p[0]] = float(p[1])
	pg = load(SCENE).instantiate()
	add_child(pg)
	p1 = pg.get_node("P1")
	p2 = pg.get_node("P2")
	cam = pg.get_node("Camera")
	arena = pg.get_node("Void")
	match_node = pg.get_node("Match")
	match_node.countdown_s = 0.0
	p1.external_input = true
	p2.external_input = true
	if cfg["cam_fov"] > 0.0:
		cam.fov = cfg["cam_fov"]
	if cfg["cam_min_h"] > 0.0:
		cam.min_half_height = cfg["cam_min_h"]
	if cfg["cam_pad"] > 0.0:
		cam.padding = cfg["cam_pad"]
	if cfg["cam_pad_y"] > -1.5:
		cam.padding_y = cfg["cam_pad_y"]
	if cfg["cam_fit"] >= 0.0:
		cam.fit_bounds = cfg["cam_fit"] >= 0.5
	report["resolution"] = var_to_str(get_viewport().get_visible_rect().size)
	report["camera_params"] = {"fov": cam.fov, "min_half_height": cam.min_half_height, "padding": cam.padding,
		"padding_y": cam.padding_y, "fit_bounds": cam.fit_bounds, "zoom_out_tau": cam.zoom_out_tau, "zoom_in_tau": cam.zoom_in_tau}


func _physics_process(delta: float) -> void:
	t += delta
	var pushing := t >= push_from and t < push_from + float(cfg["push"])
	p1.input_vec = Vector2(-1.0, 0.15) if pushing else Vector2.ZERO
	p2.input_vec = Vector2(1.0, 0.15) if pushing else Vector2.ZERO
	if cam.half_height <= 0.0:
		return
	# кадр камеры внутри границ арены (fit_bounds): ни в одном кадре не видно пустоты за стенами и под полом
	var b: AABB = cam.view_bounds()
	var r := cam.frame_rect()
	var over := maxf(maxf(b.position.x - r.position.x, r.end.x - b.end.x), maxf(b.position.y - r.position.y, r.end.y - b.end.y))
	worst_bounds = maxf(worst_bounds, over)
	if over > 0.02:
		in_bounds = false
	if t >= push_from:
		hh_track.append([snappedf(t - push_from, 0.01), snappedf(cam.half_height, 0.001)])


func _process(_delta: float) -> void:
	if busy:
		return
	if stage == 0 and t >= float(cfg["close_t"]):
		busy = true
		_rest_checks("close")
		var hh := cam.half_height
		_check("close_half_height_min", hh, 2.6, "gt", "camera half-height at spawn (m), RM framing 2.6..3.2")
		_check("close_half_height_max", hh, 3.2, "lt", "camera half-height at spawn (m), RM framing 2.6..3.2")
		report["info"]["close_camera"] = {"half_height": snappedf(hh, 0.01), "pos": var_to_str(cam.global_position), "frame": var_to_str(cam.frame_rect())}
		var img := await _capture("05-void-%s-close.png" % tag)
		for d in [p1, p2]:
			var fr := _doll_frac(d)
			report["info"]["close_doll_%s" % d.name] = {"frame_frac": snappedf(fr.x, 0.001), "world_h": snappedf(fr.y, 0.01)}
			_check("close_doll_frac_%s" % d.name, fr.x, float(cfg["min_frac"]), "gt", "doll height / frame height at spawn (projected mesh AABB)")
		_image_checks(img, "close", false)
		push_from = t
		stage = 1
		busy = false
	elif stage == 1 and t >= push_from + float(cfg["push"]) + float(cfg["wide_wait"]):
		busy = true
		var hh := cam.half_height
		var r := cam.frame_rect()
		report["info"]["wide_camera"] = {"half_height": snappedf(hh, 0.01), "pos": var_to_str(cam.global_position), "frame": var_to_str(r),
			"p1_com": var_to_str(p1.centre_of_mass()), "p2_com": var_to_str(p2.centre_of_mass())}
		_check("wide_half_height", hh, 3.9, "gt", "camera zoomed out after the dolls separated (m; max = whole field 4.5)")
		_check("frame_covers_field", minf(-r.position.x, r.end.x), FIELD_HALF_W - 0.05, "gt", "wide frame spans x = -7..7 (min |edge| m; frame %s)" % r)
		var img := await _capture("05-void-%s-wide.png" % tag)
		for d in [p1, p2]:
			var fr := _doll_frac(d)
			report["info"]["wide_doll_%s" % d.name] = {"frame_frac": snappedf(fr.x, 0.001), "world_h": snappedf(fr.y, 0.01)}
		_image_checks(img, "wide", true)
		_zoom_info()
		_check("frame_in_bounds", 1.0 if in_bounds else 0.0, 0.5, "gt", "camera frame never left arena bounds (worst overshoot %.3f m)" % worst_bounds)
		stage = 2
		_finish()


func _rest_checks(tag_: String) -> void:
	for d in [p1, p2]:
		var c: Vector3 = d.centre_of_mass()
		_check("%s_%s_standing" % [tag_, d.name], c.y - d.position.y, 0.6, "gt", "COM above root (m)")
		_check("%s_%s_at_rest" % [tag_, d.name], d.max_part_speed(), float(cfg["rest_v"]), "lt", "max part speed (m/s)")


## Отъезд камеры: за сколько секунд после начала толчка полувысота прошла 90 % пути от кадра спавна к итоговой.
func _zoom_info() -> void:
	if hh_track.is_empty():
		return
	var h0: float = hh_track[0][1]
	var h1: float = hh_track[hh_track.size() - 1][1]
	var t90 := -1.0
	for e in hh_track:
		if float(e[1]) >= h0 + (h1 - h0) * 0.9:
			t90 = float(e[0])
			break
	report["info"]["zoom_out"] = {"from": h0, "to": h1, "t90_s": t90, "samples": hh_track.size()}


## Доля высоты кадра, которую занимает кукла (проекция AABB видимых мешей), и её высота в мире (м).
func _doll_frac(d: Node) -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	var y0 := INF
	var y1 := -INF
	var w0 := INF
	var w1 := -INF
	for mi in _meshes(d):
		var ab: AABB = mi.global_transform * mi.get_aabb()
		w0 = minf(w0, ab.position.y)
		w1 = maxf(w1, ab.end.y)
		for i in 8:
			var p := cam.unproject_position(ab.get_endpoint(i))
			y0 = minf(y0, p.y)
			y1 = maxf(y1, p.y)
	if y1 < y0:
		return Vector2.ZERO
	return Vector2((y1 - y0) / vp.y, w1 - w0)


func _meshes(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).is_visible_in_tree() and (c as MeshInstance3D).mesh != null:
			out.append(c)
		out += _meshes(c)
	return out


## Люма sRGB средняя по квадрату (2r+1)² вокруг пикселя.
func _luma(img: Image, px: Vector2i, r: int) -> float:
	var s := 0.0
	var n := 0
	for y in range(px.y - r, px.y + r + 1):
		for x in range(px.x - r, px.x + r + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var c := img.get_pixel(x, y)
			s += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return s / maxf(float(n), 1.0)


func _to_px(img: Image, world: Vector3) -> Vector2i:
	var vp := get_viewport().get_visible_rect().size
	var p := cam.unproject_position(world)
	return Vector2i(roundi(p.x * img.get_width() / vp.x), roundi(p.y * img.get_height() / vp.y))


func _inside(img: Image, px: Vector2i, margin: int) -> bool:
	return px.x >= margin and px.y >= margin and px.x < img.get_width() - margin and px.y < img.get_height() - margin


## Точка задника (z = BACKDROP_Z), которая видна в доле кадра frac (0..1 от левого верхнего угла).
func _backdrop_at(frac: Vector2) -> Vector3:
	var vp := get_viewport().get_visible_rect().size
	return cam.project_position(Vector2(frac.x * vp.x, frac.y * vp.y), cam.global_position.z - BACKDROP_Z)


## Максимум люмы по столбцу ±1 px вокруг линии сетки (линия 1.6 см — на экране ≈ 1–2 px) и среднее между линиями.
func _grid_contrast(img: Image, x_line: float, y0: float, y1: float) -> Vector2:
	var line := 0.0
	var mid := 0.0
	var n := 0
	var y := y0
	while y <= y1:
		var pl := _to_px(img, Vector3(x_line, y, BACKDROP_Z))
		var best := 0.0
		for dx in [-1, 0, 1]:
			best = maxf(best, _luma(img, pl + Vector2i(dx, 0), 0))
		line += best
		mid += _luma(img, _to_px(img, Vector3(x_line + 0.5, y + 0.5, BACKDROP_Z)), 2)
		n += 1
		y += 0.25
	return Vector2(line, mid) / maxf(float(n), 1.0)


func _image_checks(img: Image, tag_: String, wide: bool) -> void:
	# фон и сетка: на заднике в свободной от кукол и HUD зоне кадра (левее центра, выше голов), середина клетки / линия
	var bp := _backdrop_at(Vector2(0.33, 0.33))
	var cell := Vector3(floorf(bp.x) + 0.5, floorf(bp.y) + 0.5, BACKDROP_Z)
	var bg := _luma(img, _to_px(img, cell), 3)
	var torso1 := _luma(img, _to_px(img, p1.centre_of_mass() + Vector3(0, 0.25, 0.1)), 3)
	var torso2 := _luma(img, _to_px(img, p2.centre_of_mass() + Vector3(0, 0.25, 0.1)), 3)
	var gc := _grid_contrast(img, floorf(bp.x), floorf(bp.y) - 1.0, floorf(bp.y) + 1.0)
	var front := _luma(img, _to_px(img, Vector3(0.0, -0.35, FLOOR_FRONT_Z + 0.001)), 3)
	var top := _luma(img, _to_px(img, Vector3(0.0, 0.001, 0.0)), 2)
	var info := {"bg": snappedf(bg, 0.0001), "torso_p1": snappedf(torso1, 0.001), "torso_p2": snappedf(torso2, 0.001),
		"grid_line": snappedf(gc.x, 0.0001), "grid_mid": snappedf(gc.y, 0.0001), "grid_contrast": snappedf(gc.x - gc.y, 0.0001),
		"floor_front": snappedf(front, 0.001), "floor_top": snappedf(top, 0.001), "grid_x": floorf(bp.x)}
	_check("%s_bg_black" % tag_, bg, 0.05, "lt", "mean luma of the empty field between grid lines")
	_check("%s_grid_visible" % tag_, gc.x - gc.y, 0.008, "gt", "grid line (x=%d on the backdrop) brighter than cell centre" % int(floorf(bp.x)))
	_check("%s_grid_faint" % tag_, gc.x - gc.y, 0.12, "lt", "grid line contrast stays faint")
	_check("%s_floor_front_grey" % tag_, front - bg, 0.12, "gt", "floor front face (x=0, y=-0.35) luma above background")
	_check("%s_floor_top_darker" % tag_, front - top, 0.05, "gt", "floor top (x=0, z=0) darker than the front face: no bright trapezoid")
	if not wide:
		_check("%s_doll_p1_reads" % tag_, torso1 - bg, 0.15, "gt", "maple torso luma above background")
		_check("%s_doll_p2_reads" % tag_, torso2 - bg, 0.06, "gt", "walnut torso luma above background")
	else:
		# куклы после толчка могут лежать/лететь где угодно — их контраст пишется в info, стены проверяются полосой
		var walls: Array = []
		for side in [-1.0, 1.0]:
			var px := _to_px(img, Vector3(side * (WALL_MID_X - 0.1), 3.0, FLOOR_FRONT_Z + 0.001))
			if _inside(img, px, 3):
				walls.append(_luma(img, px, 3))
		info["walls"] = walls
		var wall: float = float(walls.min()) if not walls.is_empty() else 0.0
		_check("%s_wall_band" % tag_, wall - bg, 0.015, "gt", "wall front face reads as a band at the frame edge (luma above background)")
		_check("%s_wall_darker_than_floor" % tag_, front - wall, 0.05, "gt", "wall band darker than the floor band")
	report["info"][tag_] = info


func _check(id: String, value: float, limit: float, cmp: String, detail: String) -> void:
	var ok := (value < limit) if cmp == "lt" else (value > limit)
	report["checks"].append({"id": id, "value": snappedf(value, 0.0001), "limit": limit, "cmp": cmp, "ok": ok, "detail": detail})
	print("  %s %s: %s %s %s (%s)" % ["ok  " if ok else "FAIL", id, snappedf(value, 0.0001), cmp, limit, detail])
	if not ok:
		report["ok"] = false


func _capture(name: String) -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(name)
	var err := img.save_png(path)
	report["shots"].append(path)
	print("saved ", path, " (", err, ") at t=", snappedf(t, 0.01), " half_height=", snappedf(cam.half_height, 0.01))
	return img


func _finish() -> void:
	var js := JSON.stringify(report, "  ")
	print("=== VOID SNAPSHOT ===")
	print(js)
	var f := FileAccess.open("res://tests/void_snapshot_report.json", FileAccess.WRITE)
	if f:
		f.store_string(js)
		f.close()
	print("=== %s ===" % ("OK" if report["ok"] else "FAIL"))
	get_tree().quit(0 if report["ok"] else 1)
