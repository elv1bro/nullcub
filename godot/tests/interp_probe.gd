## Проба дрожи 60 Гц физики на дисплее с другой частотой (docs/plan-demo/PERF_PASS.md §6). ОКНО, vsync включён (иначе проба врёт: без
## него кадры идут чаще дисплея).  godot --path . --resolution 1280x720 res://tests/interp_probe.tscn -- "mode=off|on,secs=7,scene=void"
## mode=on включает SceneTree.physics_interpolation (как project.godot physics/common/physics_interpolation) — A/B на одной сборке.
## Бот-кукла P1 летит туда-сюда на тяге; каждый кадр пишем, где торс ВИДЕН: get_global_transform_interpolated() (при выключенной
## интерполяции равен физическому), и его положение относительно камеры — так видны и шаги кукол, и шаги камеры.
## Метрики: stall — доля кадров, где торс стоит (|Δ| < 15 % среднего шага), пока скорость > 1.5 м/с; double — шаг > 1.7× среднего;
## jerk — RMS второй разности видимого положения относительно камеры в долях среднего шага (ловит и шаги камеры).
## Строка «INTERP mode=… stall=…%» и tests/interp_probe_report.json; exit 1, если mode=on хуже порогов (stall ≤ 1 %, double ≤ 1 %).
extends Node

const SCENES := {"void": "res://scenes/playground_void.tscn", "ruins": "res://scenes/playground.tscn", "scrap": "res://scenes/playground_scrap.tscn"}
var mode := "off"
var secs := 7.0
var scene_id := "void"
var fps := 72   # частота кадров дисплея автора (внешний монитор 72 Гц); 0 — как есть
var pg: Node3D
var p1: Doll
var cam: Camera3D
var t := 0.0
var rows: Array = []   # [dt, x_view, x_rel, speed]
var last_us := 0
var warm := 0
var dir := 1.0
var next_flip := 1.4


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2:
				match p[0]:
					"mode": mode = p[1]
					"secs": secs = float(p[1])
					"scene": scene_id = p[1]
					"fps": fps = int(p[1])
	# каденс кадров задаём сами: vsync выключен, потолок Engine.max_fps — так проба не зависит от экрана, на который попало окно
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = fps
	get_tree().physics_interpolation = mode == "on"
	if mode == "on":
		Engine.physics_jitter_fix = 0.0
	pg = (load(SCENES.get(scene_id, SCENES["void"])) as PackedScene).instantiate()
	var mt := pg.get_node_or_null("Match") as Match
	if mt != null:
		mt.countdown_s = 0.0
	add_child(pg)
	p1 = pg.get_node("P1") as Doll
	p1.external_input = true
	(pg.get_node("P2") as Doll).external_input = true
	last_us = Time.get_ticks_usec()


func _physics_process(_d: float) -> void:
	if warm < 60:
		return
	p1 = pg.get_node_or_null("P1") as Doll   # после KO матч пересоздаёт кукол
	if p1 == null or not is_instance_valid(p1):
		return
	if t >= next_flip:
		dir = -dir
		next_flip += 1.4
	p1.input_vec = Vector2(dir, 0.0)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := float(now - last_us) / 1e6
	last_us = now
	warm += 1
	if warm < 90:
		return
	t += dt
	if cam == null:
		cam = get_viewport().get_camera_3d()
	if p1 == null or not is_instance_valid(p1):
		return
	var torso := p1.torso()
	var x := torso.get_global_transform_interpolated().origin.x
	var cx := cam.global_position.x if cam != null else 0.0
	rows.append([dt, x, x - cx, torso.linear_velocity.length()])
	if t >= secs:
		_report()


func _report() -> void:
	var steps: Array = []
	var rel: Array = []
	for i in range(1, rows.size()):
		if float(rows[i][3]) > 1.5:
			steps.append(absf(float(rows[i][1]) - float(rows[i - 1][1])))
			rel.append(float(rows[i][2]) - float(rows[i - 1][2]))
	if steps.size() < 30:
		print("INTERP mode=%s: мало движущихся кадров (%d) — кукла не летит" % [mode, steps.size()])
		get_tree().quit(1)
		return
	var med := 0.0   # типичный шаг — СРЕДНЕЕ (медиана при кадрах чаще физики = 0)
	for s in steps:
		med += float(s)
	med /= steps.size()
	var stall := 0
	var dbl := 0
	for s in steps:
		stall += 1 if float(s) < med * 0.15 else 0
		dbl += 1 if float(s) > med * 1.7 else 0
	var mean := 0.0
	for r in rel:
		mean += absf(float(r))
	mean /= rel.size()
	var sd := 0.0
	for r in rel:
		sd += pow(absf(float(r)) - mean, 2.0)
	sd = sqrt(sd / rel.size())
	# рывок: RMS второй разности видимого положения относительно камеры, в долях среднего шага (гладкое движение → ~0)
	var jerk2 := 0.0
	var jn := 0
	for i in range(1, rows.size() - 1):
		if float(rows[i][3]) > 1.5:
			var a2 := float(rows[i + 1][2]) - 2.0 * float(rows[i][2]) + float(rows[i - 1][2])
			jerk2 += a2 * a2
			jn += 1
	var jerk := sqrt(jerk2 / maxf(jn, 1)) / maxf(med, 1e-6)
	var hz := float(rows.size()) / maxf(t, 0.001)
	var stall_pct := 100.0 * stall / steps.size()
	var dbl_pct := 100.0 * dbl / steps.size()
	print("INTERP screen=%d refresh=%.0f" % [DisplayServer.window_get_current_screen(), DisplayServer.screen_get_refresh_rate(DisplayServer.window_get_current_screen())])
	print("INTERP mode=%s scene=%s frames=%d hz=%.1f moving=%d stall=%.1f%% double=%.1f%% jerk=%.3f mean_step=%.4f m" % [mode, scene_id, rows.size(), hz, steps.size(), stall_pct, dbl_pct, jerk, med])
	var f := FileAccess.open("res://tests/interp_probe_report.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"mode": mode, "hz": hz, "stall_pct": stall_pct, "double_pct": dbl_pct, "jerk": jerk}, "  "))
		f.close()
	var bad := mode == "on" and (stall_pct > 1.0 or dbl_pct > 1.0)
	get_tree().quit(1 if bad else 0)
