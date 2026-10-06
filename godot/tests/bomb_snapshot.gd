## Снимки «Бомбы касанием» (нужно окно; docs/plan-demo/BOMB.md): отсчёт, бомба на кукле и HUD (плашки, метка над держателем), крупно
## держатель с бомбой (искра, лампа на писке), взрыв (БУМ!), конец партии, итоги матча. Все пятеро — боты (p1_bot), камера держит живых.
##   godot/tools/godot_nofocus.sh --path godot --resolution 1600x900 res://tests/bomb_snapshot.tscn -- "out_dir=/abs/dir"
## Глазами проверить: бомба на груди держателя видна и мигает, метка «БОМБА» над ним, плашки пятерых сверху (у держателя «БОМБА»), у
## выбывших «ВЫБЫЛ», взрыв раскидывает соседей, табличка итогов.
extends Node

const SCENE := "res://scenes/playground_bomb.tscn"

var out_dir := "/tmp"
var pg: BombPlayground
var bm: BombMatch


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for part in String(arg).split(","):
			var kv := part.split("=")
			if kv.size() == 2 and kv[0] == "out_dir":
				out_dir = kv[1]
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


func _run() -> void:
	pg = (load(SCENE) as PackedScene).instantiate() as BombPlayground
	pg.p1_bot = true
	bm = pg.get_node("Match") as BombMatch
	bm.rng_seed = 99
	add_child(pg)
	await _wait(1.2)
	await _shot("01_countdown")
	await _until(func() -> bool: return bm.play_state == "play", 6.0)
	await _wait(4.0)
	await _shot("02_play")
	# крупно держатель: камера только на нём
	var h := bm.holder
	if h != null:
		var cam := Camera3D.new()
		cam.fov = 30.0
		add_child(cam)
		cam.make_current()
		var follow := func() -> bool:
			if bm.holder != null:
				var c := bm.holder.centre_of_mass(true)
				cam.global_position = Vector3(c.x, c.y + 0.2, 4.2)
			return bm.carry._flash > 0.0 and bm.fuse_t > 1.0
		await _until(follow, 4.0)
		await _shot("03_holder_close")
		cam.queue_free()
		pg.cam.make_current()
	# взрыв
	var n0 := bm.explosions.size()
	bm.fuse_t = maxf(bm.fuse_t, bm.fuse_s - 0.05)
	await _until(func() -> bool: return bm.explosions.size() > n0, 3.0)
	await _wait(0.12)
	await _shot("04_boom")
	await _wait(1.0)
	await _shot("05_after_boom")
	# конец партии
	var r0 := bm.rounds.size()
	var burn := func() -> bool:
		if bm.play_state == "play":
			bm.fuse_t = bm.fuse_s
		return bm.rounds.size() > r0
	await _until(burn, 20.0)
	await _wait(0.4)
	await _shot("06_round_won")
	# итоги
	bm.wins = {0: 3, 2: 1, 4: 2}
	bm._finish("wins")
	await _wait(1.4)
	await _shot("07_end")
	get_tree().quit(0)
