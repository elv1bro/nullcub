## Кадры «камера за игроком, N0 рядом, стрелка к сопернику» (автор 02.10.2026). Нужен рендер (окно; в контейнере — xvfb-run):
##   godot --path godot --resolution 1600x900 res://tests/n0_follow_snapshot.tscn -- "out=/tmp/n0_follow"
## Бой кампании без выхода бойцов, соперник — бот. Кадры: <out>_1.png — отсчёт, реплика N0 облачком; <out>_2.png — бой, P1 летит
## вправо; <out>_3.png — соперник в 14 м: стрелка «P2 · N м». Склейка трёх кадров — <out>_sheet.png.
## clean=1 — без интерфейса (HUD, стрелки, облачко N0, подсказка): подложка для макетов HUD.
## skin=broadcast|neon|led — скин HUD (HudSkin) на время снимка, без записи в настройки.
extends Node

const FIGHT := preload("res://scenes/campaign/campaign_fight.tscn")

var out := "user://n0_follow"
var clean := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var p := String(a).split("=")
		if p.size() == 2 and p[0] == "out":
			out = p[1]
		if p.size() == 2 and p[0] == "clean":
			clean = p[1] == "1"
		if p.size() == 2 and p[0] == "skin":
			HudSkin.set_skin(p[1], false)
	var r: Dictionary = CampaignLeague.rival(CampaignLeague.LOCAL, 1)
	var f := FIGHT.instantiate()
	f.call("setup", CampaignLeague.start_blueprint(), CampaignLeague.rival_blueprint(CampaignLeague.LOCAL, r), r,
		CampaignLeague.rival_title(r), {"entrance": false})
	add_child(f)
	(f.get_node("AudienceVote") as AudienceVote).enabled = false
	var imgs: Array[Image] = []
	await _secs(1.4)
	imgs.append(await _grab(1))
	await _secs(2.2)
	Input.action_press("p1_right")
	await _secs(1.2)
	imgs.append(await _grab(2))
	Input.action_release("p1_right")
	var p1 := f.get_node("P1") as Doll
	var p2 := f.get_node("P2") as Doll
	p2.get_node("Brain").process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().physics_frame   # переставлять тела — в шаге физики (из кадра отрисовки позиция откатывается)
	var x2 := p1.centre_of_mass().x + (14.0 if p1.centre_of_mass().x < 0.0 else -14.0)
	var shift := Vector3(x2, p1.centre_of_mass().y + 3.0, 0.0) - p2.centre_of_mass()
	for b in p2.parts.values():
		(b as RigidBody3D).global_position += shift
		(b as RigidBody3D).freeze = true
	await _secs(1.0)
	imgs.append(await _grab(3))
	var w := imgs[0].get_width()
	var h := imgs[0].get_height()
	var sheet := Image.create(w, h * 3, false, Image.FORMAT_RGB8)
	for i in imgs.size():
		sheet.blit_rect(imgs[i], Rect2i(0, 0, w, h), Vector2i(0, h * i))
	sheet.resize(w / 2, h * 3 / 2, Image.INTERPOLATE_LANCZOS)
	sheet.save_png(out + "_sheet.png")
	print("n0_follow_snapshot: %s_sheet.png" % out)
	get_tree().quit(0)


func _secs(s: float) -> void:
	var t := 0.0
	while t < s:
		await get_tree().process_frame
		t += get_process_delta_time()


func _grab(i: int) -> Image:
	if clean:
		for l in get_tree().root.find_children("*", "CanvasLayer", true, false):
			(l as CanvasLayer).visible = false
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png("%s_%d.png" % [out, i])
	return img
