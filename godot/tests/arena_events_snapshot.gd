## Кадры событий купола (этапы 15–16): выход бойца (ворота, путь к мембране, за мембраной, второй боец) и голосование зрителей
## (проценты, итог с аномалией §14) — лист 3×2.
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path godot --resolution 1920x1080 --fixed-fps 60 res://tests/arena_events_snapshot.tscn \
##     -- "sheet=res://../docs/plan-demo/img/entrance-vote-v1.jpg"
extends Node

const FIGHT := preload("res://scenes/campaign/campaign_fight.tscn")

var sheet := "res://tests/arena_events_snapshot.jpg"
var shots: Array[Image] = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		for kv in a.split(","):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "sheet":
				sheet = p[1]
	await _run()


func _run() -> void:
	var r: Dictionary = {}
	for x in CampaignLeague.ladder():
		if String((x as Dictionary).get("anomaly", "")) == "vote_mismatch":
			r = x
	var f := FIGHT.instantiate()
	f.call("setup", CampaignLeague.start_blueprint(), CampaignLeague.rival_blueprint(CampaignLeague.LOCAL, r), r,
		CampaignLeague.rival_title(r), {"entrance": true, "player_name": "Игрок", "player_build": "Кит «Человек»",
		"player_record": "побед 2 · поражений 1 · трофеев 2", "rival_build": "Местная лига · уровень 3", "rival_record": "соперник 3 из 4"})
	add_child(f)
	(f.get_node("P2/Brain") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	var v: AudienceVote = f.get_node("AudienceVote")
	v.first_s = 2.0
	v.duration_s = 3.0
	var ent: FighterEntrance = f.get_node("Entrance")
	await _step(ent, 0, "gate_open", 0.35)
	await _shot()
	await _secs(1.0)
	await _shot()
	await _step(ent, 0, "membrane", 0.6)
	await _shot()
	await _step(ent, 1, "gate_open", 0.2)
	await _shot()
	while v.state != "voting":
		await get_tree().physics_frame
	await _secs(2.0)
	await _shot()
	while v.state != "effect":
		await get_tree().physics_frame
	await _secs(0.9)
	await _shot()
	_save_sheet()
	get_tree().quit(0)


func _step(ent: FighterEntrance, fighter: int, step: String, after_s: float) -> void:
	while not ent.timeline.any(func(e: Dictionary) -> bool: return int(e["fighter"]) == fighter and String(e["step"]) == step):
		await get_tree().physics_frame
	await _secs(after_s)


func _secs(s: float) -> void:
	for i in int(s * 60.0):
		await get_tree().physics_frame


func _shot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(640, 360, Image.INTERPOLATE_LANCZOS)
	shots.append(img)


func _save_sheet() -> void:
	var out := Image.create(1920, 720, false, Image.FORMAT_RGB8)
	for i in shots.size():
		var im := shots[i]
		im.convert(Image.FORMAT_RGB8)
		out.blit_rect(im, Rect2i(0, 0, 640, 360), Vector2i((i % 3) * 640, (i / 3) * 360))
	var path := ProjectSettings.globalize_path(sheet) if sheet.begins_with("res://") or sheet.begins_with("user://") else sheet
	out.save_jpg(path, 0.88)
	print("arena_events_snapshot: %s (%d кадров)" % [path, shots.size()])
