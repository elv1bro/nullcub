## Съёмка кадров заставки-комикса без страницы: IntroStage в SubViewport нужного размера → PNG на каждый кадр.
## Запуск (окно, нативно arm64): godot --path godot --resolution 960x540 res://tests/intro_snapshot.tscn --
##   "shots=1-13,at=0.6,w=1200,out=<абс. папка>"   (at — доля длительности кадра; at=0.2+0.8 — два момента)
## Отчёт <out>/intro_snapshot.json: для каждого PNG средняя яркость и доля почти чёрных пикселей (кадр не пустой).
extends Node

var cfg := {"shots": "1-13", "at": "0.6", "w": "1200", "h": "0", "out": "", "frames": "10"}
# пропорции панелей страницы (ширина/высота) — из intro_comic.tscn
var ASPECT: Array = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and cfg.has(p[0]):
				cfg[p[0]] = p[1]
	var out: String = cfg["out"]
	if out == "":
		out = ProjectSettings.globalize_path("res://tests/intro_shots")
	DirAccess.make_dir_recursive_absolute(out)
	var page: Node = load("res://scenes/intro/intro_comic.tscn").instantiate()
	for c in page.get_node("Page").get_children():
		var b: Rect2 = (c as ComicPanel).bbox()
		ASPECT.append(b.size.x / b.size.y)
	page.free()
	var vp := SubViewport.new()
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_2X
	add_child(vp)
	var stage: IntroStage = load("res://scenes/intro/intro_stage.tscn").instantiate()
	vp.add_child(stage)
	await get_tree().process_frame
	var report := {"ok": true, "shots": []}
	var ids: Array = []
	for part in String(cfg["shots"]).split(" "):
		var r := part.split("-")
		if r.size() == 2:
			for i in range(int(r[0]), int(r[1]) + 1):
				ids.append(i)
		else:
			ids.append(int(part))
	var w := int(cfg["w"])
	for i in ids:
		var asp: float = ASPECT[clampi(i - 1, 0, ASPECT.size() - 1)]
		vp.size = Vector2i(w, int(round(w / asp)))
		stage.set_shot(i - 1)
		for at_s in String(cfg["at"]).split("+"):
			var t := float(at_s) * stage.shot.duration
			# идём к моменту кадра по шагам: частицы и события «вперёд» успевают сработать
			var steps := 12
			for s in steps + 1:
				stage.evaluate(t * float(s) / steps)
				await get_tree().process_frame
			for f in int(cfg["frames"]):
				stage.evaluate(t)
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			var path := out.path_join("shot%02d_%s.png" % [i, at_s])
			img.save_png(path)
			var stats := _stats(img)
			report["shots"].append({"shot": i, "at": at_s, "path": path, "mean": stats[0], "black": stats[1]})
			if stats[0] < 0.04:
				report["ok"] = false
			print("shot %02d at %s → %s  mean %.3f black %.2f" % [i, at_s, path, stats[0], stats[1]])
			var an := ""
			for a in ["Head", "Chest", "Hand_L", "Hand_R", "Elbow_R", "Feet"]:
				var v: Vector3 = stage.hero.anchor_world(a)
				an += "  %s(%.2f,%.2f,%.2f)" % [a, v.x, v.y, v.z]
			var c := stage.camera.global_position
			print("   hero:%s  cam(%.2f,%.2f,%.2f)" % [an, c.x, c.y, c.z])
	var f := FileAccess.open(out.path_join("intro_snapshot.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	get_tree().quit(0 if report["ok"] else 1)


func _stats(img: Image) -> Array:
	var sum := 0.0
	var black := 0
	var n := 0
	for y in range(0, img.get_height(), 8):
		for x in range(0, img.get_width(), 8):
			var c := img.get_pixel(x, y)
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			sum += l
			if l < 0.02:
				black += 1
			n += 1
	return [sum / n, float(black) / n]
