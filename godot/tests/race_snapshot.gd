## Снимки «Гонки: 10 точек» (нужно окно): карта целиком со всеми метками (все точки зажжены разом — проверить расстановку), гонка
## глазами P1 (за него играет бот, камера и HUD ведут его как игрока — RaceMatch.focus_index), момент взятия точки (вспышка), итоги.
##   godot/tools/godot_nofocus.sh --path godot --resolution 1600x900 res://tests/race_snapshot.tscn -- "out_dir=/abs/dir,map=proving|ruins|scrap,level=2"
## Глазами проверить: точки видны и не прячутся в декоре, стрелки к точкам за кадром, счёт «7/10» на плашках, имена над гонщиками,
## вспышка цвета взявшего, табличка итогов.
extends Node

const SCENES := {
	"proving": "res://scenes/playground_race.tscn",
	"ruins": "res://scenes/playground_race_ruins.tscn",
	"scrap": "res://scenes/playground_race_scrap.tscn",
}

var out_dir := "/tmp"
var map := "proving"
var level := 2
var pg: RacePlayground
var rm: RaceMatch


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for part in String(arg).split(","):
			var kv := part.split("=")
			if kv.size() != 2:
				continue
			match kv[0]:
				"out_dir": out_dir = kv[1]
				"map": map = kv[1]
				"level": level = int(kv[1])
	RacePlayground.best_path = "user://_snapshot_race_best.cfg"
	_run.call_deferred()


func _shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s_%s.png" % [out_dir, map, name_]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("shot → ", path)


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _until(cond: Callable, max_s: float) -> bool:
	var t := 0.0
	while not cond.call() and t < max_s:
		await get_tree().process_frame
		t += get_process_delta_time() / maxf(Engine.time_scale, 0.05)
	return cond.call()


func _run() -> void:
	pg = (load(SCENES.get(map, SCENES["proving"])) as PackedScene).instantiate() as RacePlayground
	pg.p1_bot = true
	pg.bot_level = level
	rm = pg.get_node("Match") as RaceMatch
	rm.focus_index = 0
	rm.countdown_s = 4.0
	rm.seed_value = 7
	add_child(pg)
	await _wait(0.8)
	# карта целиком со всеми метками: свои точки-образцы (не матчевые — их не берут), своя камера на кадр
	var demo := Node3D.new()
	pg.add_child(demo)
	for i in rm.marks.size():
		var dp := RacePoint.make(i, rm.marks[i])
		dp.size_mult = 1.8
		demo.add_child(dp)
	var game_cam := get_viewport().get_camera_3d()
	var wide := Camera3D.new()
	wide.fov = 26.0
	wide.attributes = CameraAttributesPractical.new()   # без глубины резкости окружения: карта целиком резкая
	pg.add_child(wide)
	var b: AABB = pg.arena.call("bounds")
	var vp := get_viewport().get_visible_rect().size
	var hh := maxf((b.size.x * 0.5 + 1.0) / (vp.x / vp.y), (b.size.y - 4.0) * 0.5 + 1.0)
	var c := b.get_center()
	wide.global_position = Vector3(c.x, c.y + 2.0, hh / tan(deg_to_rad(wide.fov * 0.5)))
	wide.make_current()
	await _wait(0.6)
	await _shot("marks")
	demo.queue_free()
	if game_cam != null:
		game_cam.make_current()
	await _until(func() -> bool: return rm.play_state == "play", 8.0)
	await _wait(0.4)
	await _shot("start")
	await _wait(6.0)
	await _shot("race")
	var p1 := rm.me()
	var before := rm.score_of(p1)
	await _until(func() -> bool: return rm.score_of(rm.me()) > before or rm.play_state != "play", 40.0)
	await _wait(0.12)
	await _shot("take")
	await _until(func() -> bool: return rm.play_state == "over", 180.0)
	await _wait(1.4)
	await _shot("end")
	var g := ProjectSettings.globalize_path(RacePlayground.best_path)
	if FileAccess.file_exists(g):
		DirAccess.remove_absolute(g)
	get_tree().quit(0)
