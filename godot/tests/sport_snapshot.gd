## Снимки спорт-зала (нужно окно): по каждому виду спорта — ввод мяча, игра ботов, гол, а в конце футбола — итоги матча.
##   godot/tools/godot_nofocus.sh --path godot --resolution 1600x900 res://tests/sport_snapshot.tscn -- "out_dir=/abs/dir,sports=football,basketball,volleyball"
## Кадры: <out_dir>/sport_<вид>_{kickoff,play,goal}.png, sport_football_results.png. За обеих кукол играет SportBrain.
## Глазами проверить: зал читается, мяч и снаряд видны, счёт на HUD и на табло стены, подпись вида.
extends Node

const SCENES := {
	"football": "res://scenes/playground_sport.tscn",
	"basketball": "res://scenes/playground_sport_basketball.tscn",
	"volleyball": "res://scenes/playground_sport_volleyball.tscn",
}

var out_dir := "/tmp"
var sports: Array = ["football", "basketball", "volleyball"]
var play_s := 6.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var key := ""
		for part in String(arg).split(","):
			var kv := part.split("=")
			if kv.size() == 2:
				key = kv[0]
				match key:
					"out_dir": out_dir = kv[1]
					"sports": sports = [kv[1]]
					"play_s": play_s = float(kv[1])
			elif key == "sports":
				sports.append(part)
	_run.call_deferred()


func _shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name_]
	img.save_png(path)
	print("shot → ", path)


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _run() -> void:
	for id in sports:
		if not SCENES.has(id):
			continue
		var pg := (load(SCENES[id]) as PackedScene).instantiate()
		add_child(pg)
		var sm := pg.get_node("Match") as SportMatch
		await _wait(1.2)
		await _shot("sport_%s_kickoff" % id)
		while sm.play_state != "play":
			await get_tree().process_frame
		var p1: Doll = null
		for d in sm.dolls():
			if (d as Doll).player_index == 0:
				p1 = d
		var b := SportBrain.new()
		b.name = "SportBrain"
		p1.add_child(b)
		p1.external_input = true
		await _wait(play_s)
		await _shot("sport_%s_play" % id)
		var t := 0.0
		while sm.play_state == "play" and t < 60.0:
			await get_tree().process_frame
			t += get_process_delta_time()
		await _wait(0.35)
		await _shot("sport_%s_goal" % id)
		while sm.play_state == "goal":
			await get_tree().process_frame
		if sm.play_state == "kickoff":
			await _wait(0.8)
			await _shot("sport_%s_kickoff2" % id)
		if id == "football":
			while sm.phase != Match.Phase.OVER and t < 240.0:
				await get_tree().process_frame
				t += get_process_delta_time()
			await _wait(1.6)
			await _shot("sport_football_results")
		remove_child(pg)
		pg.queue_free()
		await get_tree().process_frame
	get_tree().quit(0)
