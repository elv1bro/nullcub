## Холодный старт мастерской (docs/plan-demo/PERF_PASS.md): первые жесты после запуска — где кадр дольше порога. ОКНО.
##   rm -rf "$(getconf DARWIN_USER_CACHE_DIR)org.godotengine.godot"   # кэш Metal драйвера — холодный запуск
##   tools/godot_nofocus.sh --path . --resolution 1280x720 res://tests/cold_ws_probe.tscn -- "limit_ms=120"
## Выводит самый долгий кадр после каждого жеста (кадры пишем по реальным часам) и PIPELINES по жестам; exit 1, если какой-то > limit_ms.
extends Node

var ws: WorkshopBuild
var limit_ms := 120.0
var wait_s := 5.0
var last_us := 0
var cur_max := 0.0
var cur_pipes := [0, 0, 0, 0, 0]
var results: Array = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "limit_ms":
				limit_ms = float(p[1])
			if p.size() == 2 and p[0] == "wait_s":
				wait_s = float(p[1])
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	WorkshopBuild.prefs_path = "user://workshop_prefs_probe.cfg"
	ws = (load("res://scenes/workshop/workshop_build.tscn") as PackedScene).instantiate() as WorkshopBuild
	ws.load_autosave = false
	ws.autosave_on_test = false
	ws.probe_input = false   # как в игре
	add_child(ws)
	last_us = Time.get_ticks_usec()
	_run.call_deferred()


var _nodes_last := 0


func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := float(now - last_us) / 1000.0
	cur_max = maxf(cur_max, dt)
	last_us = now
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	if dt > 100.0:
		print("COLDWS   медленный кадр %.0f мс: process=%.1f physics=%.1f мс, узлов %d (Δ %+d), физ. тел активных %d, объектов рендера %d" % [dt,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, nodes, nodes - _nodes_last,
			int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)), int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))])
	_nodes_last = nodes


func _pipes() -> Array:
	var out: Array = []
	for c in [Performance.PIPELINE_COMPILATIONS_CANVAS, Performance.PIPELINE_COMPILATIONS_MESH, Performance.PIPELINE_COMPILATIONS_SURFACE,
			Performance.PIPELINE_COMPILATIONS_DRAW, Performance.PIPELINE_COMPILATIONS_SPECIALIZATION]:
		out.append(int(Performance.get_monitor(c)))
	return out


func _step(name: String, frames: int, call_ms := -1.0) -> void:
	var p0 := _pipes()
	cur_max = 0.0
	for i in range(frames):
		await get_tree().process_frame
	var p1 := _pipes()
	var dp: Array = []
	for i in range(5):
		dp.append(int(p1[i]) - int(p0[i]))
	results.append({"name": name, "max_ms": snappedf(cur_max, 0.1), "pipes": dp})
	print("COLDWS %-34s вызов %6.1f мс, худший кадр %7.1f мс   пайплайнов canvas/mesh/surface/draw/spec = %s" % [name, call_ms, cur_max, dp])


func _run() -> void:
	for i in range(60):
		await get_tree().process_frame
	cur_max = 0.0
	ws.set_preset("kit_human")
	await _step("загрузка пресета", 30)
	var t0 := Time.get_ticks_usec()
	ws.unscrew("3")
	var c := float(Time.get_ticks_usec() - t0) / 1000.0
	await _step("ПКМ «открутить» (первый)", 40, c)
	t0 = Time.get_ticks_usec()
	ws.undo()
	c = float(Time.get_ticks_usec() - t0) / 1000.0
	await _step("Ctrl+Z", 30, c)
	var n := CraftEdit.find(ws.blueprint, "1")
	ws.begin_drag(String(n["part"]), Vector2(600, 360), {"move": "1", "start": Vector2(600, 360)})
	await _step("захват руки с куклы", 40)
	ws.cancel_drag()
	await _step("отпустить мимо", 20)
	ws.select_shelf("kit_hand_mitten")
	ws.begin_drag("kit_hand_mitten", Vector2(300, 600))
	await _step("деталь с полки в руку", 40)
	ws.cancel_drag()
	ws.show_com = true
	ws.changed.emit()
	await _step("слой «Физика»", 40)
	await get_tree().create_timer(wait_s).timeout   # игрок какое-то время собирает куклу — мастерская греет ресурсы испытания в фоне
	cur_max = 0.0
	t0 = Time.get_ticks_usec()
	ws.start_test()
	c = float(Time.get_ticks_usec() - t0) / 1000.0
	await _step("«Испытать» (старт теста)", 90, c)
	t0 = Time.get_ticks_usec()
	ws.stop_test()
	c = float(Time.get_ticks_usec() - t0) / 1000.0
	await _step("назад к сборке", 60, c)
	t0 = Time.get_ticks_usec()
	ws.start_test()
	c = float(Time.get_ticks_usec() - t0) / 1000.0
	await _step("«Испытать» (второй раз)", 90, c)
	t0 = Time.get_ticks_usec()
	ws.stop_test()
	c = float(Time.get_ticks_usec() - t0) / 1000.0
	await _step("назад к сборке (второй раз)", 60, c)
	var bad := false
	for r in results:
		bad = bad or float(r["max_ms"]) > limit_ms
	print("COLD WS PROBE ", "OK" if not bad else "FAILED (кадр > %.0f мс)" % limit_ms)
	get_tree().quit(1 if bad else 0)
