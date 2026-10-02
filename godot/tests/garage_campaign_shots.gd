## Кадры кампании в эфире телевизора гаража (scenes/menu/garage_campaign.gd). Нужно окно:
##   godot/tools/godot_nofocus.sh --path godot --resolution 1920x1080 res://tests/garage_campaign_shots.tscn -- out=/абс/папка
##       → gc-menu, gc-dive, gc-ladder0, gc-connecting, gc-fight, gc-outcome_win, gc-ladder1, gc-workshop, gc-outcome_loss, gc-champion .png
## Кампания и мастерская — probe-файлы (сборка игрока не трогается).
extends Node

const MENU := preload("res://scenes/menu/garage_menu.tscn")
var menu: GarageMenu
var out := ""


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	out = String(args.get("out", ProjectSettings.globalize_path("user://gc_shots")))
	DirAccess.make_dir_recursive_absolute(out)
	WorkshopBuild.prefs_path = "user://_probe_gc_prefs.cfg"
	menu = MENU.instantiate() as GarageMenu
	menu.dry_run = true
	add_child(menu)
	menu.campaign.save_path = "user://_probe_gcs.tres"
	menu.campaign.bp_name = "_probe_gcs"
	menu.campaign.load_save = false
	menu.campaign.entrance_enabled = args.has("entrance")
	menu.workshop.ws_overrides = {"autosave_name": "_probe_gcs_free", "load_autosave": false, "start_preset": "kit_brawler"}
	if args.has("entrance"):
		await _entrance()
	else:
		await _run()
	for f in ["user://_probe_gcs.tres", CraftEdit.save_path("_probe_gcs"), CraftEdit.save_path("_probe_gcs_free"), "user://_probe_gc_prefs.cfg"]:
		var g := ProjectSettings.globalize_path(f)
		if FileAccess.file_exists(g):
			DirAccess.remove_absolute(g)
	get_tree().quit()


func _wait(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw


func _secs(s: float) -> void:
	await get_tree().create_timer(s).timeout
	await _wait(2)


func _save(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(out.path_join("gc-%s.png" % name))
	print("shot ", name)


func _run() -> void:
	var c := menu.campaign
	await _wait(20)
	menu.enter_menu()
	menu.set_focus(0, true)
	await _wait(25)
	_save("menu")
	var t0 := Time.get_ticks_msec()
	menu.activate()
	await _secs(0.6)
	_save("dive")
	while c.screen != GarageCampaign.Screen.LADDER:
		await get_tree().process_frame
	print("MEASURE enter -> ladder ms=", Time.get_ticks_msec() - t0)
	await _secs(1.6)
	_save("ladder0")
	c.start_fight()
	await _secs(0.3)
	_save("connecting")
	while c.fight == null:
		await get_tree().process_frame
	print("MEASURE fight load ms=", c.fight_load_ms, " connect->fight ms=", Time.get_ticks_msec() - t0)
	await _secs(4.0)
	_save("fight")
	c.finish_fight(true, {"won": true, "duration_s": 47.0})
	await _secs(1.6)
	_save("outcome_win")
	c.show_ladder()
	await _secs(1.6)
	_save("ladder1")
	c.open_workshop()
	await _secs(2.4)
	_save("workshop")
	c.close_workshop()
	await _secs(1.4)
	c.finish_fight(false, {"won": false, "duration_s": 12.0})
	await _secs(1.6)
	_save("outcome_loss")
	c.new_campaign(3)
	for i in 4:
		c.finish_fight(true, {"won": true, "duration_s": 30.0})
	c.show_ladder()
	await _secs(1.6)
	_save("champion")
	c.close()
	await _secs(1.6)
	_save("back")


## Выход бойцов внутри мира гаража (камеры FighterEntrance), потом отсчёт и бой: кадры через 1.5 / 3.5 / 6 / 9 / 12 с после «В БОЙ».
func _entrance() -> void:
	var c := menu.campaign
	await _wait(20)
	menu.enter_menu()
	menu.set_focus(0, true)
	await _wait(10)
	menu.activate()
	while c.screen != GarageCampaign.Screen.LADDER:
		await get_tree().process_frame
	await _secs(1.0)
	c.start_fight()
	while c.fight == null:
		await get_tree().process_frame
	var t := 0.0
	for k in [1.5, 2.0, 2.5, 3.0, 3.0]:
		await _secs(k)
		t += k
		_save("ent_%02d" % int(t))
