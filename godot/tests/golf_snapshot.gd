## Снимки «Гольфа: кукла — мяч» (нужно окно; docs/plan-demo/GOLF.md): прицел и полоска силы, полёт обмякшей куклы, паровой столб
## и бочки, поле «гравитация вбок», карточка итогов. P1 — человек (удары даёт скрипт), P2 — бот.
##   godot/tools/godot_nofocus.sh --path godot --resolution 1600x900 res://tests/golf_snapshot.tscn -- "out_dir=/abs/dir"
## Глазами проверить: чашу и флажок видно через весь купол, стрелка и пунктир прицела понятны, полоска силы рядом с куклой, кукла
## летит кувырком, поле вбок видно (синяя сетка и шевроны), ямы — красные.
extends Node

const SCENE := "res://scenes/playground_golf.tscn"

var out_dir := "/tmp"
var only := ""
var pg: GolfPlayground
var gm: GolfMatch


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for part in String(arg).split(","):
			var kv := part.split("=")
			if kv.size() == 2 and kv[0] == "out_dir":
				out_dir = kv[1]
			if kv.size() == 2 and kv[0] == "only":
				only = kv[1]
	_run.call_deferred()


func _shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name_]
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


func _load(hole: int, holes := 1) -> void:
	if pg != null:
		remove_child(pg)
		pg.queue_free()
		await get_tree().process_frame
	pg = (load(SCENE) as PackedScene).instantiate() as GolfPlayground
	pg.p1_bot = false
	pg.p2_bot = true
	gm = pg.get_node("Match") as GolfMatch
	gm.rng_seed = 5
	gm.start_hole = hole
	gm.holes_n = holes
	add_child(pg)
	pg.set_process(false)   # прицел P1 не от мыши — его ставит скрипт
	await _until(func() -> bool: return gm.play_state == "play", 8.0)


func _aim_and_fire(deg: float, power: float, shot_name: String, after_s: float) -> void:
	gm.set_aim(0, Vector2.from_angle(deg_to_rad(deg)))
	gm.charge_start(0)
	var t := 0.0
	var period := Tuning.GOLF_POWER_PERIOD_S
	await _until(func() -> bool: return GolfShot.power_at(float(gm.players[0]["charge_t"])) >= power - 0.02, period)
	if shot_name != "":
		await _shot(shot_name)
	gm.players[0]["charge_t"] = power * period * 0.5   # ровно нужная сила
	gm.charge_release(0)
	await _wait(after_s)


func _run() -> void:
	if only == "card":
		await _card()
		get_tree().quit(0)
		return
	await _load(0)
	await _wait(0.8)
	await _aim_and_fire(40.0, 0.92, "01_aim", 1.2)
	await _shot("02_flight")
	await _wait(1.6)
	await _shot("03_membrane")
	# лунка 2: настильно в паровой столб
	await _load(1)
	await _wait(0.6)
	await _aim_and_fire(22.0, 0.7, "", 2.6)
	await _shot("04_steam")
	await _wait(3.0)
	await _shot("05_steam_top")
	# лунка 3: поле вбок
	await _load(2)
	await _wait(0.6)
	await _aim_and_fire(60.0, 0.9, "06_side_aim", 2.0)
	await _shot("07_side_curve")
	await _wait(1.6)
	await _shot("08_side_back")
	await _card()
	get_tree().quit(0)


func _card() -> void:
	print("card: load")
	await _load(0, 3)
	print("card: loaded")
	gm.players[0]["card"] = [3, 4, 2]
	gm.players[1]["card"] = [4, 3, 4]
	gm.hole_i = 2
	gm._finish("holes")
	print("card: finished")
	await _wait(1.4)
	await _shot("09_card")
