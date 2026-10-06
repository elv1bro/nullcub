## Замер цены «эфира Лиги» в куполе (docs/plan-demo/look/show.md; ОКОННАЯ проба — только через tools/godot_nofocus.sh): Быстрый бой,
## куклы несутся друг на друга (как look_capture fight=1), vsync выключен, авто-масштаб Gfx (DynRes) выключен без записи настроек —
## иначе он съел бы разницу разрешением. Отрезки по SEG_S секунд чередуются: весь «эфир» выключен (Look: только пункты группы «Эфир»)
## / включён, ROUNDS раз (A/B/A/B — чужая нагрузка машины размазывается по обоим), первые SKIP_S каждого отрезка не считаются.
## Время кадра — по часам (Time.get_ticks_usec между кадрами), GPU — viewport_get_measured_render_time_gpu. Печатает медиану, p95, fps.
## final=1 — во включённых отрезках сразу свет финала (худший случай для света). Exit 0, если всё снялось.
##   godot/tools/godot_nofocus.sh --path godot --resolution 1600x900 res://tests/look_show_fps.tscn -- "seg=5,rounds=3"
extends Node

const SCENE := "res://scenes/playground_null_hall.tscn"
const IDS := [&"show_stinger", &"show_plates", &"show_crowd_dim", &"show_crowd_fx", &"show_spots", &"show_final_light", &"show_hud"]

var seg_s := 5.0
var rounds := 3
var skip_s := 1.0
var final := false
var _inst: Node
var _look: Node
var _last := 0
var _samples := {true: [], false: []}
var _gpu := {true: [], false: []}
var _saved := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		for part in a.split(","):
			var kv := part.split("=", true, 1)
			if kv.size() < 2:
				continue
			match kv[0]:
				"seg": seg_s = float(kv[1])
				"rounds": rounds = int(kv[1])
				"final": final = kv[1] == "1"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var gfx := get_node_or_null("/root/Gfx")
	if gfx != null:
		gfx.set("auto_scale", false)
		gfx.get("dyn").call("reset")
		gfx.call("_refresh_scale")
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_look = get_node("/root/Look")
	for id in IDS:
		_saved[id] = _look.checked(id)
	seed(3)
	_inst = (load(SCENE) as PackedScene).instantiate()
	add_child(_inst)
	var match_node := _inst.get_node("Match") as Match
	match_node.time_limit_s = 9999.0       # весь замер — обычный бой, без Sudden Death
	match_node.hard_timeout_s = 99999.0
	match_node.match_over.connect(func(_w: Doll, _r: Dictionary) -> void:
		get_tree().create_timer(0.8).timeout.connect(match_node.restart))   # нокаут — новый бой, куклы снова дерутся
	await _wait(3.0)
	for r in rounds:
		for on in [false, true]:
			_set_show(on)
			await _measure(on)
	_set_show(true)
	for id in _saved:
		_look.set_on(id, bool(_saved[id]))
	var rep := {}
	for on in [false, true]:
		rep[on] = _stats(_samples[on], _gpu[on])
	print("LOOK SHOW FPS (купол, окно %s, vsync off, DynRes off, 3D scale %.2f, load %s)" % [str(get_window().size),
		get_viewport().scaling_3d_scale, _load()])
	for on in [false, true]:
		var s: Dictionary = rep[on]
		print("  %-6s кадров %4d  медиана %.2f мс (%.0f fps)  p95 %.2f мс  GPU медиана %s" % ["эфир" if on else "без", s["n"],
			s["median"], 1000.0 / maxf(s["median"], 0.001), s["p95"], "%.2f мс" % s["gpu"] if float(s["gpu"]) > 0.0 else "н/д (Metal отдаёт 0)"])
	var d := float(rep[true]["median"]) - float(rep[false]["median"])
	print("  разница медиан (эфир − без): %+.2f мс" % d)
	print("=== OK ===")
	get_tree().quit(0)


func _set_show(on: bool) -> void:
	for id in IDS:
		_look.set_on(id, on)
	if on and final:
		var hs := _inst.find_child("HallShow", true, false) as HallShow
		if hs != null:
			hs.force_final(true)


func _wait(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) / 1000.0 < s:
		await get_tree().process_frame


func _measure(on: bool) -> void:
	await _wait(skip_s)
	var t0 := Time.get_ticks_usec()
	_last = t0
	while float(Time.get_ticks_usec() - t0) / 1e6 < seg_s:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		(_samples[on] as Array).append(float(now - _last) / 1000.0)
		(_gpu[on] as Array).append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
		_last = now


func _stats(a: Array, g: Array) -> Dictionary:
	var s := a.duplicate()
	s.sort()
	var gs := g.duplicate()
	gs.sort()
	var n := s.size()
	if n == 0:
		return {"n": 0, "median": 0.0, "p95": 0.0, "gpu": 0.0}
	return {"n": n, "median": float(s[n / 2]), "p95": float(s[mini(n - 1, int(n * 0.95))]), "gpu": float(gs[gs.size() / 2])}


func _load() -> String:
	var out := []
	OS.execute("sysctl", ["-n", "vm.loadavg"], out)
	return String(out[0]).strip_edges() if not out.is_empty() else "?"


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
