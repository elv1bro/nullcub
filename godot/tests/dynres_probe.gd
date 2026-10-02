## Авто-масштаб Gfx вживую (docs/plan-demo/PERF_PASS.md §7). ОКНО.
##   tools/godot_nofocus.sh --path . --screen 0 --resolution 5120x2880 --rendering-method forward_plus res://tests/dynres_probe.tscn -- "scene=ruins,preset=ultra,secs=40,expect=down"
## Каждую секунду печатает fps, множитель DynRes и размер 3D. expect=down — тяжёлый случай: к концу масштаб ниже 1 и fps выше, чем был;
## expect=steady — лёгкий: масштаб не тронут. exit 1, если ожидание не выполнено.
extends Node

const SCENES := {"ruins": "res://scenes/playground.tscn", "scrap": "res://scenes/playground_scrap.tscn", "void": "res://scenes/playground_void.tscn"}
var scene_id := "ruins"
var preset := "high"
var secs := 40.0
var expect := "steady"
var t := 0.0
var sec_n := 0
var sec_t := 0.0
var fps_log: Array = []
var last_us := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2:
				match p[0]:
					"scene": scene_id = p[1]
					"preset": preset = p[1]
					"secs": secs = float(p[1])
					"expect": expect = p[1]
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	var gfx := get_node("/root/Gfx")
	gfx.set_preset(preset, false)
	gfx.set_auto_scale(true)
	var pg := (load(SCENES.get(scene_id, SCENES["ruins"])) as PackedScene).instantiate()
	add_child(pg)
	for pn in ["P1", "P2"]:
		var d := pg.get_node_or_null(pn)
		if d != null and "external_input" in d:
			d.external_input = true
	last_us = Time.get_ticks_usec()


func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := float(now - last_us) / 1e6
	last_us = now
	t += dt
	sec_n += 1
	sec_t += dt
	if sec_t >= 1.0:
		var gfx := get_node("/root/Gfx")
		var info: Dictionary = gfx.info()
		var fps := sec_n / sec_t
		fps_log.append(fps)
		print("DYNRES t=%2.0f fps=%5.1f dyn_mult=%.3f render=%s scale=%.3f" % [t, fps, float(info["dyn_mult"]), str(info["render_size"]), float(info["render_scale"])])
		sec_n = 0
		sec_t = 0.0
	if t >= secs:
		_finish()


func _finish() -> void:
	var gfx := get_node("/root/Gfx")
	var info: Dictionary = gfx.info()
	var n := fps_log.size()
	var early := 0.0
	var late := 0.0
	for i in range(mini(5, n)):
		early += float(fps_log[i])
	for i in range(maxi(0, n - 5), n):
		late += float(fps_log[i])
	early /= maxf(mini(5, n), 1)
	late /= maxf(mini(5, n), 1)
	var mult := float(info["dyn_mult"])
	var ok := true
	if expect == "down":
		ok = mult < 0.99 and late > early * 1.1
	elif expect == "steady":
		ok = mult > 0.99
	print("DYNRES итог: expect=%s fps %.1f → %.1f, dyn_mult %.3f — %s" % [expect, early, late, mult, "OK" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)
