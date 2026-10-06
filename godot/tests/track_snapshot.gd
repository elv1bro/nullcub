## Снимки «Гонки: трасса» (docs/plan-demo/RACE_TRACK.md; нужно окно): гонка глазами P1 (за него играет бот, камера и HUD ведут его как
## игрока — TrackMatch.focus_index), ветки P1 заданы (A — трудная под прессами, B — трудная порталом, C — трудная коробом), кадры на
## участках: старт, прессы, вход в портал A, выход из B, короб с полем вверх, подъём в тяжёлой зоне, яма, итоги; и общий вид участков.
##   godot/tools/godot_nofocus.sh --path godot --resolution 1600x900 res://tests/track_snapshot.tscn -- "out_dir=/abs/dir,level=2,overview=1"
## Глазами проверить: участки читаются (цвет, коридор, препятствия), полоска трассы и места в HUD, имена над гонщиками, табличка итогов.
extends Node

const SCENE := "res://scenes/playground_race_track.tscn"
## Кадры гонки: [имя, x ЦМ P1, с которого снимать].
const SHOTS := [["presses", 99.0], ["portal_a", 144.4], ["portal_b", 204.0], ["duct", 252.0], ["heavy", 303.5], ["pit", 362.0]]
## Общий вид: [имя, x0, x1, y центра].
const VIEWS := [["view_s1", -6.0, 64.0, 7.0], ["view_s2", 66.0, 136.0, 9.5], ["view_s3", 136.0, 206.0, 2.5], ["view_s4", 206.0, 288.0, 3.0],
	["view_s5", 286.0, 342.0, 6.0], ["view_s6", 340.0, 420.0, 0.0]]

var out_dir := "/tmp"
var level := 2
var overview := true
var pg: TrackPlayground
var tm: TrackMatch


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for part in String(arg).split(","):
			var kv := part.split("=")
			if kv.size() != 2:
				continue
			match kv[0]:
				"out_dir": out_dir = kv[1]
				"level": level = int(kv[1])
				"overview": overview = kv[1] != "0"
	TrackPlayground.best_path = "user://_snapshot_track_best.cfg"
	ControlFeel.no_disk = true   # не читать сохранённые настройки управления автора (ДРАЙВ, темп): снимки — с настройками по умолчанию
	_run.call_deferred()


func _shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.jpg" % [out_dir, name_]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_jpg(path, 0.86)
	print("shot → ", path)


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _until(cond: Callable, max_s: float) -> bool:
	var t := 0.0
	while not cond.call() and t < max_s:
		await get_tree().process_frame
		t += get_process_delta_time() / maxf(Engine.time_scale, 0.05)
	return cond.call()


func _p1() -> Doll:
	for d in tm.dolls():
		if (d as Doll).player_index == 0:
			return d
	return null


func _run() -> void:
	TrackBrain.force_choices = {0: {"A": "hard", "B": "hard", "C": "hard"}}
	TrackBrain.seed_salt = 3
	pg = (load(SCENE) as PackedScene).instantiate() as TrackPlayground
	pg.p1_bot = true
	pg.bot_level = level
	tm = pg.get_node("Match") as TrackMatch
	tm.focus_index = 0
	tm.countdown_s = 3.0
	add_child(pg)
	await _wait(0.8)
	if overview:
		var game_cam := get_viewport().get_camera_3d()
		var wide := Camera3D.new()
		wide.fov = 30.0
		wide.attributes = CameraAttributesPractical.new()
		pg.add_child(wide)
		var vp := get_viewport().get_visible_rect().size
		for v in VIEWS:
			var hw := (float(v[2]) - float(v[1])) * 0.5 + 1.0
			var hh := maxf(hw / (vp.x / vp.y), 9.0)
			wide.global_position = Vector3((float(v[1]) + float(v[2])) * 0.5, float(v[3]), hh / tan(deg_to_rad(wide.fov * 0.5)))
			wide.make_current()
			await _wait(0.5)
			await _shot(String(v[0]))
		wide.queue_free()
		if game_cam != null:
			game_cam.make_current()
	await _until(func() -> bool: return tm.play_state == "play", 8.0)
	await _wait(0.6)
	await _shot("start")
	for s in SHOTS:
		var ok := await _until(func() -> bool: return _p1() != null and _p1().alive and _p1().centre_of_mass().x >= float(s[1]), 120.0)
		if not ok:
			print("no shot ", s[0], " (P1 x %.1f)" % (_p1().centre_of_mass().x if _p1() != null else -1.0))
			continue
		await _shot(String(s[0]))
	await _until(func() -> bool: return tm.play_state == "over", 200.0)
	await _wait(1.4)
	await _shot("end")
	TrackBrain.force_choices = {}
	TrackBrain.seed_salt = 0
	var g := ProjectSettings.globalize_path(TrackPlayground.best_path)
	if FileAccess.file_exists(g):
		DirAccess.remove_absolute(g)
	get_tree().quit(0)
