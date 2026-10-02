## Перепись сцены и кадра: godot --path godot --resolution 1280x720 [--rendering-method mobile|gl_compatibility] res://tests/stats_probe.tscn -- "scene=res://scenes/playground.tscn,frames=240"
extends Node
var scene_path := "res://scenes/playground.tscn"
var frames := 240
var shot := ""
var native := false
var warm := 90
var n := 0
var ms: Array = []
var last_us := 0
var inst: Node
var sums := {"draw": 0.0, "prims": 0.0, "objs": 0.0, "gpu": 0.0, "cpu": 0.0, "tproc": 0.0, "tphys": 0.0}
func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2:
				match p[0]:
					"scene": scene_path = p[1]
					"frames": frames = int(p[1])
					"shot": shot = p[1]
					"native": native = p[1] != "0"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var ps := load(scene_path) as PackedScene
	inst = ps.instantiate()
	if "load_autosave" in inst:
		inst.load_autosave = false
		inst.autosave_on_test = false
	add_child(inst)
	for pn in ["P1", "P2"]:
		var d := inst.get_node_or_null(pn)
		if d != null and "external_input" in d:
			d.external_input = true
	last_us = Time.get_ticks_usec()
func _process(_d: float) -> void:
	if native:
		get_window().scaling_3d_scale = 1.0   # без масштаба Gfx: кадры для сравнения рендереров в нативном разрешении окна
		get_window().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	var now := Time.get_ticks_usec()
	var dt := float(now - last_us) / 1000.0
	last_us = now
	n += 1
	if n <= warm:
		return
	ms.append(dt)
	var rid := get_viewport().get_viewport_rid()
	sums["draw"] += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	sums["prims"] += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	sums["objs"] += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	sums["gpu"] += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	sums["cpu"] += RenderingServer.viewport_get_measured_render_time_cpu(rid)
	sums["tproc"] += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	sums["tphys"] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	if ms.size() >= frames:
		_report()
func _census(root: Node, c: Dictionary) -> void:
	var k := root.get_class()
	for cls in ["RigidBody3D", "StaticBody3D", "CharacterBody3D", "Generic6DOFJoint3D", "CollisionShape3D", "MeshInstance3D", "GPUParticles3D", "CPUParticles3D", "Camera3D", "Label3D", "Sprite3D", "Decal", "SubViewport", "AudioStreamPlayer", "AudioStreamPlayer3D"]:
		if root.is_class(cls):
			c[cls] = int(c.get(cls, 0)) + 1
	if root is Light3D:
		var key := "Light:" + root.get_class() + (":shadow" if (root as Light3D).shadow_enabled else "")
		c[key] = int(c.get(key, 0)) + 1
	if root is CollisionShape3D:
		var sh := (root as CollisionShape3D).shape
		if sh != null:
			var key2 := "shape:" + sh.get_class()
			c[key2] = int(c.get(key2, 0)) + 1
	if root is RigidBody3D and (root as RigidBody3D).contact_monitor:
		c["RigidBody3D(contact_monitor)"] = int(c.get("RigidBody3D(contact_monitor)", 0)) + 1
	if root.get_script() != null and root.has_method("_physics_process") and root.is_physics_processing():
		c["physics_process nodes"] = int(c.get("physics_process nodes", 0)) + 1
	if root.get_script() != null and root.is_processing():
		c["process nodes"] = int(c.get("process nodes", 0)) + 1
	for ch in root.get_children():
		_census(ch, c)
func _report() -> void:
	var a: Array = ms.duplicate()
	a.sort()
	var sum := 0.0
	for v in a:
		sum += float(v)
	var c := {}
	_census(get_tree().root, c)
	var mb := 1.0 / 1048576.0
	print("STATS scene=%s driver=%s method=%s win=%s" % [scene_path.get_file(), RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_current_rendering_method(), DisplayServer.window_get_size()])
	var gi: Variant = get_node_or_null("/root/Gfx")
	if gi != null:
		print("  gfx: ", gi.info())
	print("  frame ms: avg=%.2f p50=%.2f p95=%.2f p99=%.2f max=%.2f  fps=%.1f" % [sum / a.size(), a[a.size() / 2], a[int(a.size() * 0.95)], a[int(a.size() * 0.99)], a[a.size() - 1], 1000.0 / (sum / a.size())])
	var k := float(a.size())
	print("  render: draw=%.0f prims=%.0f objs=%.0f gpu=%.2fms rcpu=%.2fms | script: process=%.2fms physics=%.2fms" % [sums["draw"] / k, sums["prims"] / k, sums["objs"] / k, sums["gpu"] / k, sums["cpu"] / k, sums["tproc"] / k, sums["tphys"] / k])
	print("  memory: texture=%.0f MB buffer=%.0f MB video=%.0f MB static=%.0f MB | nodes=%d objects=%d" % [Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) * mb, Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) * mb, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) * mb, Performance.get_monitor(Performance.MEMORY_STATIC) * mb, Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT)])
	print("  physics3d: active=%d pairs=%d islands=%d" % [Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS), Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)])
	var keys: Array = c.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for key in keys:
		parts.append("%s=%d" % [key, c[key]])
	print("  census: ", ", ".join(parts))
	if shot != "":
		get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit(0)
