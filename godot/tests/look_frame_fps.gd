## Цена «правила кадра» в кадре (docs/plan-demo/look/frame.md, ОКОННАЯ проба): арена с боем-«наскоком» (как look_capture fight=1),
## vsync выключен, авто-масштаб Gfx выключен (без записи в user://gfx.cfg), после прогрева — блоки по block_s секунд попеременно
## «новый вид» (рубильник Look вкл) и «как было» (выкл); первые кадры после переключения не считаются. Время кадра — по реальным
## часам, медиана и 90-й перцентиль по каждому состоянию за все его блоки (чередование гасит дрейф чужой нагрузки).
## Аргументы: scene=<res://…tscn> (купол), warm=3, block_s=2.5, blocks=8, skip=12, max_ratio=1.1 (медиана «вкл» / «выкл» выше — exit 1),
## item=<id пункта Look> — переключать только этот пункт (остальные пункты LookFrame выключены): цена одного пункта.
## Запуск: godot/tools/godot_nofocus.sh --path godot --resolution 1600x900 res://tests/look_frame_fps.tscn -- "blocks=8"
extends Node

var scene_path := "res://scenes/playground_null_hall.tscn"
var warm := 3.0
var block_s := 2.5
var blocks := 8
var skip := 12
var max_ratio := 1.1
var item := &""
var _inst: Node
var _times := {true: [], false: []}
var _state := true
var _t_block := 0.0
var _block := -1
var _skip_left := 0
var _last_us := 0
var _t0 := 0.0
var _done := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		for part in a.split(","):
			var kv := part.split("=", true, 1)
			if kv.size() < 2:
				continue
			match kv[0]:
				"scene": scene_path = kv[1]
				"warm": warm = float(kv[1])
				"block_s": block_s = float(kv[1])
				"blocks": blocks = int(kv[1])
				"skip": skip = int(kv[1])
				"max_ratio": max_ratio = float(kv[1])
				"item": item = StringName(kv[1])
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var gfx := get_node_or_null("/root/Gfx")
	if gfx != null:
		gfx.auto_scale = false
		gfx.set_preset(String(gfx.preset), false)
	seed(3)
	_look().set_master(true)
	if item != &"":
		for it in _ids():
			_look().set_on(it, it == item)
	_inst = (load(scene_path) as PackedScene).instantiate()
	add_child(_inst)
	_t0 = Time.get_ticks_msec() / 1000.0
	print("=== LOOK FRAME FPS: %s, %s, render %s ===" % [scene_path.get_file(), RenderingServer.get_current_rendering_method(),
		str(gfx.call("info")["render_size"]) if gfx != null else "?"])


func _look() -> Node:
	return get_node("/root/Look")


func _ids() -> Array:
	return (get_node("/root/LookFrame").get("ITEMS") as Array).map(func(it: Array) -> StringName: return it[0])


func _process(_dt: float) -> void:
	if _done:
		return
	var now_us := Time.get_ticks_usec()
	var ms := float(now_us - _last_us) / 1000.0 if _last_us != 0 else 0.0
	_last_us = now_us
	var t := now_us / 1e6 - _t0
	if t < warm:
		return
	if _block < 0 or t - _t_block >= block_s:
		_block += 1
		if _block >= blocks:
			_finish()
			return
		_state = _block % 2 == 0
		if item != &"":
			_look().set_on(item, _state)
		else:
			_look().set_master(_state)
		_t_block = t
		_skip_left = skip
		return
	if _skip_left > 0:
		_skip_left -= 1
		return
	(_times[_state] as Array).append(ms)


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
		if Vector2(dx, dy).length() > 1.6 and Vector2(dx, dy).length() < 4.0 and randf() < 0.05:
			d.request_dash()


static func _stats(a: Array) -> Dictionary:
	if a.is_empty():
		return {"n": 0, "med": 0.0, "p90": 0.0}
	var s := a.duplicate()
	s.sort()
	return {"n": s.size(), "med": float(s[s.size() / 2]), "p90": float(s[int(s.size() * 0.9)])}


func _finish() -> void:
	_done = true
	_look().set_master(true)
	if item != &"":
		for it in _ids():
			_look().set_on(it, true)
	var on := _stats(_times[true])
	var off := _stats(_times[false])
	var ratio := float(on["med"]) / maxf(float(off["med"]), 0.001)
	print("  new look (on):  n=%d  median %.2f ms (%.1f fps)  p90 %.2f ms" % [on["n"], on["med"], 1000.0 / maxf(on["med"], 0.001), on["p90"]])
	print("  as before (off): n=%d  median %.2f ms (%.1f fps)  p90 %.2f ms" % [off["n"], off["med"], 1000.0 / maxf(off["med"], 0.001), off["p90"]])
	print("  ratio on/off %.3f (limit %.2f)  item %s  load %s" % [ratio, max_ratio, item if item != &"" else "all", _load()])
	var ok: bool = ratio <= max_ratio and int(on["n"]) > 30 and int(off["n"]) > 30
	print("=== %s ===" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


static func _load() -> String:
	var out: Array = []
	if OS.execute("sysctl", ["-n", "vm.loadavg"], out) == 0 and not out.is_empty():
		return String(out[0]).strip_edges()
	return "?"
