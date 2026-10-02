## Кадры и ролик главного меню-гаража (scenes/menu/garage_menu.tscn). Нужно окно.
##   godot --path godot --resolution 1920x1080 res://tests/garage_menu_shots.tscn -- out=/абс/папка
##       → garage-<title|story|quick|workshop|trophies|settings|exit|settings_screen|into_tv>.png, garage-tv_live_0..2.png
##   godot --path godot --resolution 1280x720 --write-movie /абс/кадры/f.png --fixed-fps 24 res://tests/garage_menu_shots.tscn -- video=1
##       → сценарий: титул → любая клавиша → пункты вниз/вверх → Enter на «Истории» (нырок в телевизор); потом ffmpeg.
extends Node

const MENU := preload("res://scenes/menu/garage_menu.tscn")
const NAMES := ["story", "quick", "workshop", "trophies", "settings", "exit"]

var menu: GarageMenu


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	menu = MENU.instantiate() as GarageMenu
	menu.dry_run = true
	add_child(menu)
	if args.has("video"):
		await _video()
	else:
		await _stills(String(args.get("out", ProjectSettings.globalize_path("user://garage_shots"))), String(args.get("shots", "all")))
	get_tree().quit()


func _wait(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw


func _save(out: String, name: String) -> void:
	get_viewport().get_texture().get_image().save_png(out.path_join("garage-%s.png" % name))
	print("shot ", name)


func _stills(out: String, which: String) -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var want := func(n: String) -> bool: return which == "all" or which.split(",").has(n)
	await _wait(24)
	if want.call("title"):
		_save(out, "title")
	if want.call("tv_live"):     # сам экран эфира (SubViewport телевизора) через 2, 5 и 8 с — живой бой ботов
		for k in 3:
			await get_tree().create_timer(3.0 if k > 0 else 2.0).timeout
			menu.tv_vp.get_texture().get_image().save_png(out.path_join("garage-tv_live_%d.png" % k))
			print("shot tv_live_%d" % k)
	menu.enter_menu()
	for i in NAMES.size():
		if not want.call(NAMES[i]):
			continue
		menu.set_focus(i, true)
		await _wait(20)
		_save(out, NAMES[i])
	if want.call("settings_screen"):
		menu.set_focus(4, true)
		menu.activate()
		menu._move_to("SettingsClose", 0.1, 0.0, true)
		await _wait(20)
		_save(out, "settings_screen")
		menu.settings_ui.close()
	if want.call("into_tv"):
		menu.set_focus(0, true)
		menu.ui.modulate.a = 0.0
		menu.cam.global_transform = menu.spot_transform("IntoTV")
		await _wait(20)
		_save(out, "into_tv")


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	var u := e.duplicate() as InputEventKey
	u.pressed = false
	Input.parse_input_event(u)


func _sec(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _video() -> void:
	await _sec(2.5)
	_key(KEY_ENTER)
	await _sec(1.6)
	for k in [KEY_DOWN, KEY_DOWN, KEY_DOWN, KEY_DOWN, KEY_UP, KEY_UP, KEY_UP, KEY_UP]:
		_key(k)
		await _sec(1.5)
	_key(KEY_ENTER)
	await _sec(1.6)
