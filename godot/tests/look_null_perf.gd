## Цена вида поля NULL в кадре (look-null, docs/plan-demo/look/null.md; ОКОННАЯ проба, запускать через godot_nofocus.sh без --fixed-fps):
## купол с боем (куклы несутся друг на друга, как в look_capture), vsync выключен, авто-масштаб Gfx на время пробы выключен (масштаб
## 3D не плавает). Блоки по block_s секунд по очереди «новый вид» / «как было» (рубильник Look), первые settle_s секунд блока не
## считаются; время кадра — по реальным часам, плюс время кадра на GPU (RenderingServer.viewport_get_measured_render_time_gpu —
## не зависит от потолка частоты окна). Итог: медиана и p95 мс кадра для обоих состояний и разница; шире — tests/look_shots/look_null_perf.json.
## Аргументы: scene=<res://…>, block_s=5, blocks=6, warm_s=3, settle_s=0.6, shifts=1 (в начале каждого блока смена поля — волна по кадру
## в «новом виде»), item=<id> — переключать один пункт «ВИД» вместо рубильника, scale=<0..1> — масштаб 3D вместо выставленного Gfx (1 — полное разрешение окна), max_cost_ms=<n> — exit 1, если
## медиана «нового» дороже «как было» больше чем на n мс.
## Запуск: GODOT_BIN=… godot/tools/godot_nofocus.sh --path godot --resolution 1600x900 res://tests/look_null_perf.tscn -- "block_s=5,blocks=6"
extends Node

var scene_path := "res://scenes/playground_null_hall.tscn"
var block_s := 5.0
var blocks := 6
var warm_s := 3.0
var settle_s := 0.6
var shifts := false
var max_cost_ms := INF
var force_scale := 0.0
var item := &""
var _inst: Node
var _ms := {true: [], false: []}
var _gpu := {true: [], false: []}
var _scale_seen := 0.0
var _last_us := 0
var _record := false
var _state := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		for part in a.split(","):
			var kv := part.split("=", true, 1)
			if kv.size() < 2:
				continue
			match kv[0]:
				"scene": scene_path = kv[1]
				"block_s": block_s = float(kv[1])
				"blocks": blocks = int(kv[1])
				"warm_s": warm_s = float(kv[1])
				"settle_s": settle_s = float(kv[1])
				"shifts": shifts = kv[1] == "1"
				"max_cost_ms": max_cost_ms = float(kv[1])
				"scale": force_scale = float(kv[1])
				"item": item = StringName(kv[1])
	seed(3)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var gfx := get_node("/root/Gfx")
	var auto0: bool = gfx.get("auto_scale")
	gfx.set("auto_scale", false)
	gfx.call("_refresh_scale")
	if force_scale > 0.0:
		get_viewport().scaling_3d_scale = force_scale
	var look := get_node("/root/Look")
	var master0: bool = look.master
	look.set_master(true)
	_inst = (load(scene_path) as PackedScene).instantiate()
	add_child(_inst)
	await _wait(warm_s)
	var presets := [[0.35, Vector2(0.7, -0.7)], [0.204, Vector2(0.0, -1.0)]]
	var item0: bool = look.checked(item) if item != &"" else true
	for b in blocks:
		_state = b % 2 == 0
		if item != &"":
			look.set_on(item, _state)
		else:
			look.set_master(_state)
		if shifts:
			var p: Array = presets[b % 2]
			for a in get_tree().get_nodes_in_group("arena"):
				if _inst.is_ancestor_of(a) and a.has_method("set_field"):
					a.call("set_field", float(p[0]), p[1])
		_record = false
		await _wait(settle_s)
		_last_us = 0
		_record = true
		await _wait(block_s - settle_s)
		_record = false
	look.set_master(master0)
	if item != &"":
		look.set_on(item, item0)
	var on := _stats(_ms[true])
	var off := _stats(_ms[false])
	var cost := float(on["median_ms"]) - float(off["median_ms"])
	var gon := _stats(_gpu[true])
	var goff := _stats(_gpu[false])
	var gcost := float(gon["median_ms"]) - float(goff["median_ms"])
	var rep := {"scene": scene_path, "window": str(get_window().size), "render_scale": _scale_seen, "gpu_on": gon, "gpu_off": goff, "gpu_cost_median_ms": snappedf(gcost, 0.01), "render_size": str(gfx.get("render_size")),
		"preset": gfx.get("preset"), "item": String(item), "load_avg": _load_avg(), "cores": OS.get_processor_count(), "shifts": shifts, "on": on, "off": off,
		"cost_median_ms": snappedf(cost, 0.01)}
	gfx.set("auto_scale", auto0)
	gfx.call("_refresh_scale")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/look_shots/"))
	var f := FileAccess.open("res://tests/look_shots/look_null_perf.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(rep, "  "))
	print("PERF look_null%s on: median %.2f ms (%.0f fps), p95 %.2f ms; off: median %.2f ms (%.0f fps), p95 %.2f ms; cost %+.2f ms; scale %.2f %s, load %s" % [
		"" if item == &"" else " [" + String(item) + "]", on["median_ms"], 1000.0 / maxf(float(on["median_ms"]), 0.001), on["p95_ms"], off["median_ms"], 1000.0 / maxf(float(off["median_ms"]), 0.001),
		off["p95_ms"], cost, _scale_seen, str(get_window().size), str(rep["load_avg"])])
	print("PERF look_null GPU: on median %.2f ms, p95 %.2f; off median %.2f ms, p95 %.2f; cost %+.2f ms" % [gon["median_ms"], gon["p95_ms"],
		goff["median_ms"], goff["p95_ms"], gcost])
	var ok := cost <= max_cost_ms
	print("=== %s ===" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _process(_dt: float) -> void:
	if force_scale > 0.0 and not is_equal_approx(get_viewport().scaling_3d_scale, force_scale):
		get_viewport().scaling_3d_scale = force_scale   # Gfx пересчитывает масштаб на смену сцены / окна — держим свой
	var now := Time.get_ticks_usec()
	if _record and _last_us != 0:
		(_ms[_state] as Array).append(float(now - _last_us) / 1000.0)
		(_gpu[_state] as Array).append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
		_scale_seen = get_viewport().scaling_3d_scale
	_last_us = now


func _physics_process(_dt: float) -> void:
	if _inst == null or not _inst.has_method("dolls"):
		return
	var ds: Array = _inst.dolls()
	if ds.size() < 2:
		return
	for i in 2:
		var d := ds[i] as Doll
		var o := ds[1 - i] as Doll
		if not is_instance_valid(d) or not is_instance_valid(o) or not d.alive or not o.alive:
			continue
		d.external_input = true
		var dc := d.centre_of_mass()
		var oc := o.centre_of_mass()
		var dx := oc.x - dc.x
		var dy := oc.y - dc.y
		d.input_vec = Vector2(signf(dx) if absf(dx) > 0.05 else 1.0, clampf(dy / 1.5, -1.0, 1.0) if absf(dy) > 0.8 else 0.0)
		var dist := Vector2(dx, dy).length()
		if dist > 1.6 and dist < 4.0 and randf() < 0.05:
			d.request_dash()


func _wait(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(s * 1000.0):
		await get_tree().process_frame


func _stats(a: Array) -> Dictionary:
	if a.is_empty():
		return {"n": 0, "median_ms": 0.0, "p95_ms": 0.0, "mean_ms": 0.0}
	var s := a.duplicate()
	s.sort()
	var sum := 0.0
	for v in s:
		sum += float(v)
	return {"n": s.size(), "median_ms": snappedf(float(s[s.size() / 2]), 0.01), "p95_ms": snappedf(float(s[int(s.size() * 0.95)]), 0.01),
		"mean_ms": snappedf(sum / s.size(), 0.01)}


func _load_avg() -> String:
	var out := []
	if OS.execute("/usr/sbin/sysctl", ["-n", "vm.loadavg"], out) == 0 and not out.is_empty():
		return String(out[0]).strip_edges()
	return "?"
