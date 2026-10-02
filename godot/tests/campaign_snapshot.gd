## Кадры кампании «История» (этап 17): лестница, бой в куполе, исход с трофеем, мастерская из кампании — лист 2×2.
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path godot --resolution 1920x1080 --fixed-fps 60 res://tests/campaign_snapshot.tscn \
##     -- "sheet=res://../docs/plan-demo/img/campaign-v1.jpg"
## Своя кампания (user://campaign_snapshot.tres), чужое сохранение не трогает.
extends Node

const CAMPAIGN := preload("res://scenes/campaign/campaign.tscn")
const SAVE := "user://campaign_snapshot.tres"
const BP := "_campaign_snapshot"
const FIGHT_S := 7.0

var sheet := "res://tests/campaign_snapshot.jpg"
var shots: Array[Image] = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		for kv in a.split(","):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "sheet":
				sheet = p[1]
	await _run()


func _run() -> void:
	CampaignState.erase(SAVE, BP)
	var c := CAMPAIGN.instantiate()
	c.set("save_path", SAVE)
	c.set("bp_name", BP)
	c.set("load_save", false)
	c.set("entrance_enabled", false)   # выход бойцов — своя проба (arena_events_probe)
	add_child(c)
	var st: CampaignState = c.get("state")
	st.record_result(true, {"reason": "ko"})   # первый соперник побеждён — на лестнице видно отметку и трофей
	c.call("show_ladder")
	await _frames(20)
	await _shot()
	c.call("start_fight")
	await _frames(2)
	var fight: Node = c.get("fight")
	var p1: Doll = fight.get_node("P1")
	var pb := RivalBrain.new()
	pb.name = "SnapBrain"
	pb.level = 3
	p1.add_child(pb)
	await _frames(2)
	pb.players_group = "rivals"
	pb.enemies_group = "players"
	var t := 0.0
	while t < Tuning.COUNTDOWN_S + FIGHT_S:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	await _shot()
	c.call("finish_fight", true, {"reason": "ko", "duration_s": FIGHT_S})
	await _frames(20)
	await _shot()
	c.call("open_workshop")
	await _frames(40)
	await _shot()
	c.call("close_workshop")
	_save_sheet()
	CampaignState.erase(SAVE, BP)
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(960, 540, Image.INTERPOLATE_LANCZOS)
	shots.append(img)


func _save_sheet() -> void:
	var out := Image.create(1920, 1080, false, Image.FORMAT_RGB8)
	for i in shots.size():
		var im := shots[i]
		im.convert(Image.FORMAT_RGB8)
		out.blit_rect(im, Rect2i(0, 0, 960, 540), Vector2i((i % 2) * 960, (i / 2) * 540))
	var path := ProjectSettings.globalize_path(sheet) if sheet.begins_with("res://") or sheet.begins_with("user://") else sheet
	out.save_jpg(path, 0.88)
	print("campaign_snapshot: %s (%d кадров)" % [path, shots.size()])
