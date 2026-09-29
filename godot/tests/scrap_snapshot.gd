## Кадры арены «Свалка» (scenes/playground_scrap.tscn как есть: арена, P1 клён / P2 орех, оружие, DynamicCamera, Match + HUD)
## → docs/plan-demo/img/scrap-arena-v1-{wide,start,vertical,fight}.png (или out=…), 1920×1080, камера — настоящая
## DynamicCamera площадки (fov 45), куклы переставляются между кадрами (Doll.global_position + нулевые скорости частей,
## camera.snap()):
##   wide     — куклы на спавнах P1/P2, min_half_height = WIDE_H: полный отъезд, видна вся арена (36 × 20 м);
##   start    — P1 на куче пробуждения, P2 на скате у пропасти: зона старта крупно (HUD скрыт);
##   vertical — правый край (v3): P1 на ярусе R1 4 м, P2 на ярусе R2 7 м у рамы выхода (HUD скрыт);
##   fight    — P1 на Spawn0, P2 в 3.8 м правее делает рывок влево в P1 (как match_probe): кадр через 0.12 с реального
##              времени после первого удара (Match.hit), HUD виден;
##   magnet   — (арена v3) куклы по бокам от магнита, железная бочка под ним, магнит включён (ACTIVE) — кадр через MAGNET_SHOT_S:
##              бочка поднята, рабочее кольцо и лампы светятся, искры (HUD скрыт);
##   press    — (арена v3) P1 левее пресса, P2 на наковальне под ползуном: цикл с WARNING, кадр через PRESS_SHOT_S после удара
##              (пыль, искры, лампы ACTIVE, P2 отброшен) (HUD скрыт).
## Числа по самим кадрам (не «картинка красивая»): контраст куклы с фоном — средняя яркость (Rec.709) пятна 7×7 пкс в центре
## торса и головы минус медиана кольца вокруг куклы (радиус 0.9–1.3 её экранной высоты), для каждой куклы в каждом кадре;
## проверка readability: |контраст торса или головы| ≥ MIN_CONTRAST у обеих кукол в кадре fight. Ещё: камера в границах
## арены, куклы в кадре, в кадре fight был удар. JSON в stdout и tests/scrap_snapshot_report.json, exit 0/1.
## Запуск (не headless — нужен рендер): godot --path . --resolution 1920x1080 --position 100,100 --always-on-top
##   res://tests/scrap_snapshot.tscn -- "shots=wide+start+vertical+fight,out=/abs/dir/"
## Сравнение фонов: parallax=v2 подменяет инстанс Parallax арены на scenes/arena/parallax_scrap_v2.tscn (y-смещения слоёв
## и множители сохраняются), dof=<distance>/<transition>/<amount> — DOF дали камеры арены; name=<шаблон> — имя файлов
## (по умолчанию scrap-arena-v1-%s.png).
extends Node3D

const SCENE := "res://scenes/playground_scrap.tscn"
const WIDE_H := 10.5
const CLOSE_H := 4.5
const HIT_SHOT_REAL_MS := 120
const P2_OFFSET := Vector3(3.8, 0.0, 0.0)
const DASH_FROM_M := 2.0
const MIN_CONTRAST := 0.08
const PARALLAX_V2 := "res://scenes/arena/parallax_scrap_v2.tscn"
const PARALLAX_SCENES := {"v2": PARALLAX_V2, "scatter": "res://scenes/arena/parallax_scrap_scatter.tscn"}
var name_fmt := "scrap-arena-v1-%s.png"
var parallax_tag := ""
var dof_override := PackedFloat32Array()
const FOOT_CLEARANCE := 0.12     # центр самой нижней части (стопа) над опорой
const MACHINE_H := 5.2           # полувысота кадров magnet / press: механизм целиком и куклы
const MAGNET_SHOT_S := 1.8
const PRESS_SHOT_S := 0.12

var out_dir := ""
var shots: Array = ["wide", "start", "vertical", "fight"]
var pg: Node3D
var p1: Doll
var p2: Doll
var cam: DynamicCamera
var match_node: Match
var hud: CanvasLayer
var first_hit_ms := -1
var pushing := false
var dashed := false
var report := {"ok": true, "checks": [], "shots": {}}


func _ready() -> void:
	out_dir = ProjectSettings.globalize_path("res://").path_join("../docs/plan-demo/img").simplify_path()
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			match p[0]:
				"out": out_dir = p[1]
				"shots": shots = Array(p[1].split("+"))
				"parallax": parallax_tag = p[1]
				"name": name_fmt = p[1]
				"dof":
					for v in p[1].split("/"):
						dof_override.append(float(v))
	pg = load(SCENE).instantiate()
	if PARALLAX_SCENES.has(parallax_tag):
		_swap_parallax(pg)
	add_child(pg)
	if dof_override.size() == 3:
		var we := _find_world_env(pg)
		if we and we.camera_attributes is CameraAttributesPractical:
			var ca := (we.camera_attributes as CameraAttributesPractical).duplicate()
			ca.dof_blur_far_distance = dof_override[0]
			ca.dof_blur_far_transition = dof_override[1]
			ca.dof_blur_amount = dof_override[2]
			we.camera_attributes = ca
	report["parallax"] = parallax_tag if parallax_tag != "" else "v1"
	report["dof"] = Array(dof_override)
	pg.set_process_unhandled_input(false)
	get_viewport().gui_disable_input = true
	p1 = pg.get_node("P1")
	p2 = pg.get_node("P2")
	cam = pg.get_node("Camera")
	match_node = pg.get_node("Match")
	hud = pg.get_node("HUD")
	var hint := pg.get_node_or_null("UI/Hint") as CanvasItem
	if hint:
		hint.visible = false
	match_node.countdown_s = 0.0
	p1.external_input = true
	p2.external_input = true
	match_node.hit.connect(func(_v: Doll, _a: Node, _d: float, _k: String, _p: Vector3) -> void:
		if first_hit_ms < 0:
			first_hit_ms = Time.get_ticks_msec())
	report["resolution"] = var_to_str(get_viewport().get_visible_rect().size)
	_run.call_deferred()


## Подмена фона арены на v2 до входа в дерево: новый инстанс с теми же y-смещениями и множителями, на то же место.
func _swap_parallax(root: Node) -> void:
	var old := root.find_child("Parallax", true, false) as Node3D
	if old == null:
		push_warning("scrap_snapshot: нет узла Parallax")
		return
	var nb := (load(PARALLAX_SCENES[parallax_tag]) as PackedScene).instantiate() as Node3D
	for prop in ["layer4_y_offset", "layer3_y_offset", "layer2_y_offset", "layer1_y_offset",
			"layer4_scroll", "layer3_scroll", "layer2_scroll", "layer1_scroll"]:
		nb.set(prop, old.get(prop))
	nb.transform = old.transform
	var parent := old.get_parent()
	var idx := old.get_index()
	parent.remove_child(old)
	old.free()
	nb.name = "Parallax"
	parent.add_child(nb)
	parent.move_child(nb, idx)


func _find_world_env(root: Node) -> WorldEnvironment:
	for n in root.find_children("*", "WorldEnvironment", true, false):
		return n as WorldEnvironment
	return null


func _physics_process(_delta: float) -> void:
	if not pushing or not is_instance_valid(p2) or not p2.alive:
		return
	p2.input_vec = Vector2(-1.0, 0.25)
	if not dashed and absf(p2.centre_of_mass().x - p1.centre_of_mass().x) > DASH_FROM_M and p2._time >= p2.dash_ready_at:
		p2.dash_until = p2._time + Tuning.DASH_DURATION_S
		p2.dash_ready_at = p2._time + Tuning.DASH_COOLDOWN_S
		dashed = true


func _run() -> void:
	await _wait(0.8)
	for s in shots:
		match s:
			"wide":
				hud.visible = false
				cam.min_half_height = WIDE_H
				_place(p1, _spawn(0))
				_place(p2, _spawn(1))
				await _wait(1.5)
				await _capture("wide")
			"start":
				hud.visible = false
				cam.min_half_height = CLOSE_H
				_place(p1, Vector3(-16.6, 1.75, 0.0))
				_place(p2, Vector3(-11.3, 1.45, 0.0))
				await _wait(1.6)
				await _capture("start")
			"vertical":
				hud.visible = false
				cam.min_half_height = CLOSE_H
				_place(p1, Vector3(14.2, 4.05, 0.0))
				_place(p2, Vector3(16.2, 7.05, 0.0))
				await _wait(1.6)
				await _capture("vertical")
			"magnet":
				await _shot_magnet()
			"press":
				await _shot_press()
			"fight":
				hud.visible = true
				cam.min_half_height = 4.0
				_place(p1, _spawn(0))
				_place(p2, _spawn(0) + P2_OFFSET)
				await _wait(0.8)
				pushing = true
				var t0 := Time.get_ticks_msec()
				while first_hit_ms < 0 and Time.get_ticks_msec() - t0 < 4000:
					await get_tree().process_frame
				_check("fight_hit", 1.0 if first_hit_ms >= 0 else 0.0, 1.0, "eq", "Match.hit fired within 4 s of the dash")
				while first_hit_ms >= 0 and Time.get_ticks_msec() - first_hit_ms < HIT_SHOT_REAL_MS:
					await get_tree().process_frame
				pushing = false
				p2.input_vec = Vector2.ZERO
				await _capture("fight")
	_finish()


## Магнит включён над железной бочкой, куклы по бокам (деревянные — магнит их не тянет).
func _shot_magnet() -> void:
	var mag: Node3D = pg.arena.call("magnet") if pg.arena.has_method("magnet") else null
	if mag == null:
		_check("magnet_present", 0.0, 1.0, "eq", "арена без магнита (нужна Свалка v3)")
		return
	hud.visible = false
	cam.min_half_height = MACHINE_H
	var pole: Vector3 = mag.call("pole_global")
	_place(p1, Vector3(pole.x - 2.8, 0.05, 0.0))
	_place(p2, Vector3(pole.x + 2.6, 0.05, 0.0))
	var barrel := pg.arena.get_node_or_null("Props/MetalBarrel") as RigidBody3D
	if barrel != null:
		barrel.global_position = Vector3(pole.x - 0.3, 0.02, 0.0)
		barrel.linear_velocity = Vector3.ZERO
	await _wait(0.6)
	mag.call("force_state", 2)   # ScrapMachine.State.ACTIVE
	await _wait(MAGNET_SHOT_S)
	await _capture("magnet")
	mag.call("force_state", 3)


## Пресс: WARNING → удар по P2 на наковальне, кадр сразу после удара.
func _shot_press() -> void:
	var press: Node3D = pg.arena.call("press") if pg.arena.has_method("press") else null
	if press == null:
		_check("press_present", 0.0, 1.0, "eq", "арена без пресса (нужна Свалка v3)")
		return
	hud.visible = false
	cam.min_half_height = MACHINE_H
	var px := press.global_position.x
	press.call("force_state", 0)
	_place(p1, Vector3(px - 2.6, 0.05, 0.0))
	_place(p2, Vector3(px + 0.2, 0.17, 0.0))
	await _wait(0.8)
	press.call("trigger")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
		if int(press.get("state")) == 2 and float(press.get("state_t")) >= float(press.get("slam_s")) + PRESS_SHOT_S:
			break
	await _capture("press")


func _spawn(i: int) -> Vector3:
	var pts: Array = pg.arena.call("spawn_points")
	return pts[i]


## Перенос куклы целиком: узел Doll двигает свои части-RigidBody (позы сохраняются). Части за время боя уезжают от узла,
## поэтому сдвиг считается от самой нижней части (ЦМ по x): она встаёт на pos.y (+ зазор), иначе ноги оказались бы в настиле.
## Скорости обнуляются, камера — snap.
func _place(d: Doll, pos: Vector3) -> void:
	var low := INF
	for part in d.parts.values():
		low = minf(low, (part as Node3D).global_position.y)
	var com := d.centre_of_mass()
	d.global_position += Vector3(pos.x - com.x, pos.y + FOOT_CLEARANCE - low, 0.0)
	for part in d.parts.values():
		var rb := part as RigidBody3D
		if rb != null:
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO
	cam.snap()


func _wait(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(s * 1000.0):
		await get_tree().process_frame


func _capture(id: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(name_fmt % id)
	var err := img.save_png(path)
	var info := {"path": path, "err": err, "size": var_to_str(img.get_size()), "half_height": snappedf(cam.half_height, 0.01),
		"camera": var_to_str(cam.global_position.snapped(Vector3.ONE * 0.01))}
	var b := cam.view_bounds()
	var r := cam.frame_rect()
	var inside := r.size.x > b.size.x + 0.05 or (r.position.x >= b.position.x - 0.05 and r.end.x <= b.end.x + 0.05)
	_check(id + "_frame_in_bounds", 1.0 if inside else 0.0, 1.0, "eq", "camera frame %s inside view bounds x" % r)
	for d in [p1, p2]:
		var c := _contrast(img, d)
		info[String(d.name)] = c
		if id == "fight":
			_check(id + "_readable_" + String(d.name), maxf(absf(c["torso"]), absf(c["head"])), MIN_CONTRAST, "gte",
				"|luma(torso|head) − median(ring)| (torso %.3f, head %.3f, bg %.3f)" % [c["torso"], c["head"], c["bg"]])
		_check(id + "_in_frame_" + String(d.name), 1.0 if c["in_frame"] else 0.0, 1.0, "eq", "doll torso on screen")
	report["shots"][id] = info
	print("shot ", id, " → ", path, " ", info)
	await get_tree().process_frame
	await get_tree().process_frame


## Контраст куклы с фоном по кадру: пятно 7×7 в центре торса и головы против медианы кольца вокруг куклы.
func _contrast(img: Image, d: Doll) -> Dictionary:
	var vp := Vector2(img.get_size())
	var scale := vp / get_viewport().get_visible_rect().size
	var torso: Vector3 = (d.parts["Torso"] as Node3D).global_position
	var head: Vector3 = (d.parts["Head"] as Node3D).global_position
	var feet: Vector3 = ((d.parts["Foot_L"] as Node3D).global_position + (d.parts["Foot_R"] as Node3D).global_position) * 0.5
	var ts := cam.unproject_position(torso) * scale
	var hs := cam.unproject_position(head) * scale
	var fs := cam.unproject_position(feet) * scale
	var h := maxf(fs.distance_to(hs), 20.0)
	var out := {"in_frame": Rect2(Vector2.ZERO, vp).has_point(ts), "screen_h_px": snappedf(h, 0.1)}
	var t_l := _patch(img, ts, 3)
	var h_l := _patch(img, hs, 3)
	var ring: Array = []
	var centre := (ts + fs) * 0.5
	for k in 48:
		var a := TAU * float(k) / 48.0
		for rr in [0.9, 1.1, 1.3]:
			var p: Vector2 = centre + Vector2(cos(a), sin(a)) * h * float(rr)
			if Rect2(Vector2.ZERO, vp).has_point(p):
				ring.append(_luma(img.get_pixelv(Vector2i(p))))
	ring.sort()
	var bg: float = ring[ring.size() / 2] if not ring.is_empty() else 0.0
	out["torso"] = snappedf(t_l - bg, 0.001)
	out["head"] = snappedf(h_l - bg, 0.001)
	out["bg"] = snappedf(bg, 0.001)
	out["torso_luma"] = snappedf(t_l, 0.001)
	return out


func _patch(img: Image, p: Vector2, r: int) -> float:
	var s := 0.0
	var n := 0
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var q := Vector2i(p) + Vector2i(dx, dy)
			if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height():
				s += _luma(img.get_pixelv(q))
				n += 1
	return s / maxf(n, 1)


func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _check(id: String, value: float, limit: float, cmp: String, detail: String) -> void:
	var ok := false
	match cmp:
		"gte": ok = value >= limit
		"lte": ok = value <= limit
		"eq": ok = is_equal_approx(value, limit)
	report["checks"].append({"id": id, "value": snappedf(value, 0.001), "limit": limit, "cmp": cmp, "ok": ok, "detail": detail})
	if not ok:
		report["ok"] = false
	print("  %s %s: %s %s %s (%s)" % ["ok  " if ok else "FAIL", id, snappedf(value, 0.001), cmp, limit, detail])


func _finish() -> void:
	var js := JSON.stringify(report, "  ")
	print("=== SCRAP SNAPSHOT ===")
	print(js)
	var f := FileAccess.open("res://tests/scrap_snapshot_report.json", FileAccess.WRITE)
	if f:
		f.store_string(js)
		f.close()
	print("=== %s ===" % ("OK" if report["ok"] else "FAIL"))
	get_tree().quit(0 if report["ok"] else 1)
