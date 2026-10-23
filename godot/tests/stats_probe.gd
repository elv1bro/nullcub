## Перепись сцены и кадра: godot --path godot --resolution 1280x720 [--rendering-method mobile|gl_compatibility] res://tests/stats_probe.tscn -- "scene=res://scenes/playground.tscn,frames=240"
extends Node
var scene_path := "res://scenes/playground.tscn"
var frames := 240
var shot := ""
var native := false
var textop := 0   # textop=N — N самых крупных текстур из материалов сцены и SubViewport (оценка: ш×в×байт/пиксель×4/3 на мипы)
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
					"textop": textop = int(p[1])
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
	if textop > 0:
		_tex_top(mb)
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

func _tex_top(mb: float) -> void:
	var seen := {}
	_tex_walk(get_tree().root, seen)
	var rows: Array = []
	for t in seen.values():
		rows.append(t)
	rows.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
	var total := 0.0
	for r in rows:
		total += float(r[0])
	print("  textures seen: %d, ≈ %.0f MB" % [rows.size(), total * mb])
	for r in rows.slice(0, textop):
		print("  tex %6.1f MB %s" % [float(r[0]) * mb, r[1]])
func _tex_add(t: Texture, seen: Dictionary, where: String) -> void:
	if t == null or seen.has(t.get_rid()):
		return
	var t2 := t as Texture2D
	if t2 == null:
		seen[t.get_rid()] = [0.0, "%s %s" % [t.get_class(), where]]
		return
	var bpp := 4.0
	var fmt := "?"
	if t2 is CompressedTexture2D:
		var f := (t2 as CompressedTexture2D).get_format()
		fmt = str(f)
		bpp = 1.0 if f >= Image.FORMAT_DXT1 and f != Image.FORMAT_DXT1 and f != Image.FORMAT_RGTC_R and f != Image.FORMAT_ETC2_RGB8 else (0.5 if f >= Image.FORMAT_DXT1 else (4.0 if f == Image.FORMAT_RGBA8 or f == Image.FORMAT_RGB8 else 4.0))
	var b := t2.get_width() * t2.get_height() * bpp * (4.0 / 3.0 if t2.has_mipmaps() else 1.0) if t2.has_method("has_mipmaps") else t2.get_width() * t2.get_height() * bpp
	seen[t.get_rid()] = [b, "%dx%d fmt=%s %s %s" % [t2.get_width(), t2.get_height(), fmt, t.resource_path if t.resource_path != "" else t.get_class(), where]]
func _tex_mat(m: Material, seen: Dictionary, where: String) -> void:
	if m == null:
		return
	for pr in m.get_property_list():
		var v: Variant = m.get(pr["name"])
		if v is Texture:
			_tex_add(v, seen, where)
	if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
		for u in (m as ShaderMaterial).shader.get_shader_uniform_list():
			var v2: Variant = (m as ShaderMaterial).get_shader_parameter(u["name"])
			if v2 is Texture:
				_tex_add(v2, seen, where)
	if m.next_pass != null:
		_tex_mat(m.next_pass, seen, where)
func _tex_walk(n: Node, seen: Dictionary) -> void:
	var where := String(n.name)
	if n is SubViewport:
		var sv := n as SubViewport
		seen[sv.get_texture().get_rid()] = [float(sv.size.x * sv.size.y * 4 * 2), "SubViewport %dx%d %s" % [sv.size.x, sv.size.y, n.get_path()]]
	if n is GeometryInstance3D:
		_tex_mat((n as GeometryInstance3D).material_override, seen, where)
		_tex_mat((n as GeometryInstance3D).material_overlay, seen, where)
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			_tex_mat(mi.get_surface_override_material(i), seen, where)
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				_tex_mat(mi.mesh.surface_get_material(i), seen, where)
	if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null and (n as MultiMeshInstance3D).multimesh.mesh != null:
		var mm := (n as MultiMeshInstance3D).multimesh.mesh
		for i in mm.get_surface_count():
			_tex_mat(mm.surface_get_material(i), seen, where)
	if n is SpriteBase3D:
		_tex_add((n as SpriteBase3D).get("texture"), seen, where)
	if n is Decal:
		for k in ["texture_albedo", "texture_normal", "texture_emission"]:
			_tex_add(n.get(k), seen, where)
	if n is WorldEnvironment and (n as WorldEnvironment).environment != null and (n as WorldEnvironment).environment.sky != null:
		_tex_mat((n as WorldEnvironment).environment.sky.sky_material, seen, where)
	if n is CanvasItem:
		for k in ["texture"]:
			if k in n and n.get(k) is Texture:
				_tex_add(n.get(k), seen, where)
		_tex_mat((n as CanvasItem).material, seen, where)
	if n is GPUParticles3D:
		var gp := n as GPUParticles3D
		for i in gp.draw_passes:
			var dm := gp.get_draw_pass_mesh(i)
			if dm != null:
				for j in dm.get_surface_count():
					_tex_mat(dm.surface_get_material(j), seen, where)
	for ch in n.get_children():
		_tex_walk(ch, seen)
