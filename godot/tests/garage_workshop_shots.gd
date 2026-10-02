## Кадры мастерской внутри гаража (scenes/menu/garage_workshop.gd). Нужно окно:
##   godot/tools/godot_nofocus.sh --path godot --resolution 1920x1080 res://tests/garage_workshop_shots.tscn -- out=/абс/папка
##       → gw-menu.png, gw-dive.png (середина нырка), gw-build.png, gw-weapon.png, gw-test.png, gw-back.png; в stdout — замеры мс.
## Автосейв — probe-файл (сборка игрока не трогается).
extends Node

const MENU := preload("res://scenes/menu/garage_menu.tscn")
var menu: GarageMenu
var out := ""


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	out = String(args.get("out", ProjectSettings.globalize_path("user://gw_shots")))
	DirAccess.make_dir_recursive_absolute(out)
	WorkshopBuild.prefs_path = "user://_probe_gw_prefs.cfg"
	menu = MENU.instantiate() as GarageMenu
	menu.dry_run = true
	add_child(menu)
	menu.workshop.ws_overrides = {"autosave_name": "_probe_gw", "load_autosave": false, "start_preset": "kit_brawler"}
	(menu.player_doll as GarageDoll).blueprint_path = CraftEdit.save_path("_probe_gw")
	await _run()
	for f in [CraftEdit.save_path("_probe_gw"), ProjectSettings.globalize_path("user://_probe_gw_prefs.cfg")]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	get_tree().quit()


func _wait(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw


func _save(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(out.path_join("gw-%s.png" % name))
	print("shot ", name)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
	await _wait(2)


func _run() -> void:
	var w := menu.workshop
	await _wait(10)
	var t0 := Time.get_ticks_msec()
	while w.ws == null and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	print("MEASURE background load ms=", w.load_ms, " instantiate ms=", w.inst_ms)
	menu.enter_menu()
	menu.set_focus(2, true)
	await _wait(25)
	_save("menu")
	var t1 := Time.get_ticks_msec()
	menu.activate()
	await get_tree().create_timer(0.5).timeout
	await _wait(2)
	_save("dive")
	while menu.state == "workshop" and not w.ws.build_cam.is_current():
		await get_tree().process_frame
	print("MEASURE enter -> handover ms=", Time.get_ticks_msec() - t1)
	await get_tree().create_timer(1.2).timeout
	await _wait(3)
	_save("build")
	w.ws.set_view(WorkshopBuild.View.WEAPON)
	await get_tree().create_timer(1.2).timeout
	await _wait(3)
	_save("weapon")
	w.ws.set_view(WorkshopBuild.View.BODY)
	await get_tree().create_timer(0.8).timeout
	if w.ws.start_test():
		await get_tree().create_timer(1.5).timeout
		await _wait(3)
		_save("test")
		w.ws.stop_test()
	await get_tree().create_timer(0.6).timeout
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	await get_tree().create_timer(1.6).timeout
	await _wait(3)
	_save("back")
