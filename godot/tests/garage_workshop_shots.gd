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


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout
	await _wait(2)


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
	# испытание: первый старт — лоадер «ПОДГОТОВКА ЗАЛА», потом ворота открываются
	w.ws.start_test()
	await _secs(0.25)
	_save("loader")
	var t_hall := Time.get_ticks_msec()
	while w.ws.mode != WorkshopBuild.Mode.TEST:
		await get_tree().process_frame
	print("MEASURE hall prepare ms=", Time.get_ticks_msec() - t_hall, " inst ms=", w.hall_inst_ms)
	await _secs(0.5)
	_save("test_gate_opening")
	await _secs(1.4)
	_save("test_gate_open")
	# ворота крупным планом (камера гаража на пару кадров)
	menu.cam.global_transform = Transform3D(Basis.looking_at(Vector3(-4.7, 1.5, 1.2) - Vector3(-1.2, 1.6, 4.2), Vector3.UP), Vector3(-1.2, 1.6, 4.2))
	menu.cam.fov = 60.0
	menu.cam.make_current()
	await _secs(0.3)
	_save("gate_close")
	w.ws.test_cam.make_current()
	var doll := w.ws.test_doll
	for bd in doll.parts.values():
		(bd as RigidBody3D).linear_velocity = Vector3(-20.0, 3.0, 0.0)
	await _secs(2.0)
	_save("test_in_hall")
	var dx := -24.0 - (doll.parts["Torso"] as Node3D).global_position.x
	for bd in doll.parts.values():
		(bd as RigidBody3D).global_position += Vector3(dx, 0.9, 0.0)
		(bd as RigidBody3D).linear_velocity = Vector3(-15.0, 0.0, 0.0)
	await _secs(0.9)
	_save("test_bag_hit")
	await _secs(1.5)
	_save("test_bag_after")
	# манекен: подлететь к нему на скорости
	var dx2 := -14.0 - (doll.parts["Torso"] as Node3D).global_position.x
	for bd in doll.parts.values():
		(bd as RigidBody3D).global_position += Vector3(dx2, 0.9, 0.0)
		(bd as RigidBody3D).linear_velocity = Vector3(-14.0, 0.0, 0.0)
	await _secs(0.35)
	_save("test_dummy_hit")
	await _secs(1.2)
	_save("test_dummy_after")
	w.ws.stop_test()
	await get_tree().create_timer(0.6).timeout
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	await get_tree().create_timer(1.6).timeout
	await _wait(3)
	_save("back")
