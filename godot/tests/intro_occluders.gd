## Что арены «Свалка» видно в кадрах заставки: для каждого кадра прячет по одному узлу арены (дети групп верхнего уровня
## и слои параллакса) и меряет, насколько меняется картинка. Нужна после перестройки арены — найти, что влезло в композицию,
## и дописать это в hide_nodes кадра (tools/build_intro_comic.gd).
## Запуск (окно, нативно arm64): godot --path godot --resolution 640x360 -s res://tests/intro_occluders.gd --
##   "shots=4 11 12,at=1.0,top=8"   (at — доля длительности кадра)
extends SceneTree

const GROUPS := ["Start", "Platforms", "Machines", "Props", "Junk", "Back", "Front", "Pit", "Ground", "Parallax", "Loot"]

var cfg := {"shots": "1-13", "at": "1.0", "top": "8", "w": "384"}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and cfg.has(p[0]):
				cfg[p[0]] = p[1]
	_run.call_deferred()


func _run() -> void:
	var vp := SubViewport.new()
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var stage: IntroStage = load("res://scenes/intro/intro_stage.tscn").instantiate()
	vp.add_child(stage)
	await process_frame
	var w := int(cfg["w"])
	vp.size = Vector2i(w, int(w * 9.0 / 16.0))
	var ids: Array = []
	for part in String(cfg["shots"]).split(" "):
		var r := part.split("-")
		if r.size() == 2:
			for i in range(int(r[0]), int(r[1]) + 1):
				ids.append(i)
		else:
			ids.append(int(part))
	for i in ids:
		stage.set_shot(i - 1)
		var t := float(cfg["at"]) * stage.shot.duration
		for s in 13:
			stage.evaluate(t * s / 12.0)
			await process_frame
		var base := await _grab(vp, stage, t)
		var rows: Array = []
		for g in GROUPS:
			var holder := stage.arena.get_node_or_null(g)
			if holder == null:
				continue
			for c in holder.get_children():
				var n := c as Node3D
				if n == null or not n.visible:
					continue
				n.visible = false
				var img := await _grab(vp, stage, t)
				n.visible = true
				var d := _diff(base, img)
				if d[1] > 0.002:
					rows.append([d[1], d[0], "%s/%s" % [g, n.name]])
		rows.sort_custom(func(a, b) -> bool: return a[0] > b[0])
		print("shot %02d (at %.2f s): узлы арены по доле изменённых пикселей" % [i, t])
		for k in mini(int(cfg["top"]), rows.size()):
			print("   %5.1f %%  (Δ %.3f)  %s" % [rows[k][0] * 100.0, rows[k][1], rows[k][2]])
	quit(0)


func _grab(vp: SubViewport, stage: IntroStage, t: float) -> Image:
	for f in 2:
		stage.evaluate(t)
		await process_frame
	await RenderingServer.frame_post_draw
	return vp.get_texture().get_image()


## [средняя |Δ| яркости, доля пикселей с |Δ| > 0.08]
func _diff(a: Image, b: Image) -> Array:
	var sum := 0.0
	var big := 0
	var n := 0
	for y in range(0, a.get_height(), 3):
		for x in range(0, a.get_width(), 3):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var d := absf(ca.get_luminance() - cb.get_luminance()) + absf(ca.r - cb.r) * 0.5 + absf(ca.b - cb.b) * 0.5
			sum += d
			if d > 0.08:
				big += 1
			n += 1
	return [sum / n, float(big) / n]
