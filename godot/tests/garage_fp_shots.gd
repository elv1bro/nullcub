## Кадры гаража от первого лица (06.10, MENU_GARAGE.md «Мир людей»): пункты с руками и N0, шаг посреди перехода, стена экранов
## вблизи и её атлас, ритуал нейрошлема по кадрам (шаги к верстаку → руки берут шлем → подъём → визор закрывается → «NULL LINK» →
## мастерская) и обратно (связь закрыта → шлем снимают → кладут на подставку). Нужно окно:
##   godot/tools/godot_nofocus.sh --path godot --resolution 1920x1080 res://tests/garage_fp_shots.tscn -- out=/абс/папка
## → fp-<имя>.png. Автосейв мастерской — свой probe-файл (сборка игрока не трогается).
extends Node

const MENU := preload("res://scenes/menu/garage_menu.tscn")
const BP := "_probe_gfp"

var menu: GarageMenu
var out := ""


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	out = String(args.get("out", ProjectSettings.globalize_path("user://garage_fp_shots")))
	DirAccess.make_dir_recursive_absolute(out)
	WorkshopBuild.prefs_path = "user://_probe_gfp_prefs.cfg"
	menu = MENU.instantiate() as GarageMenu
	menu.dry_run = true
	add_child(menu)
	menu.workshop.ws_overrides = {"autosave_name": BP, "load_autosave": false, "start_preset": String(args.get("preset", "kit_human"))}
	await _run()
	for f in [CraftEdit.save_path(BP), ProjectSettings.globalize_path("user://_probe_gfp_prefs.cfg")]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	get_tree().quit()


func _wait(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw


func _sec(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("fp-%s.png" % name))
	print("shot ", name)


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while menu.workshop.ws == null and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	await _wait(30)
	await _save("title")
	menu.enter_menu()
	for i in GarageMenu.ITEMS.size():
		menu.set_focus(i, true)
		await _sec(0.6)
		await _save(String(GarageMenu.ITEMS[i]["id"]))
	# шаг посреди перехода: от «Мастерской» к «Быстрому бою»
	menu.set_focus(2, true)
	await _sec(0.5)
	menu.set_focus(1)
	await _sec(0.32)
	await _save("walk_mid")
	await _sec(1.0)
	# стена экранов вблизи
	menu.set_focus(3, true)
	await _sec(0.3)
	menu.activate()
	await _sec(1.6)
	await _save("fighter_close")
	menu.stats_wall.vp.get_texture().get_image().save_png(out.path_join("fp-stats_atlas.png"))
	menu._close_fighter()
	await _sec(1.0)
	# ритуал шлема: вход в мастерскую
	menu.set_focus(2, true)
	await _sec(0.6)
	menu.activate()
	var hs := menu.headset
	var marks := [["hs_walk", 0.45], ["hs_reach", 1.0], ["hs_lift", 1.38], ["hs_visor", 1.62], ["hs_boot", 1.95], ["hs_workshop", 3.2]]
	var t := 0.0
	for m in marks:
		await _sec(float(m[1]) - t)
		t = float(m[1])
		await _save(String(m[0]))
	print("headset worn=", hs.worn, " ws.active=", menu.workshop.ws.active)
	# снять шлем
	menu.workshop.close()
	marks = [["off_black", 0.15], ["off_lower", 0.55], ["off_place", 0.95], ["off_menu", 2.4]]
	t = 0.0
	for m in marks:
		await _sec(float(m[1]) - t)
		t = float(m[1])
		await _save(String(m[0]))
	print("state=", menu.state, " headset on rest=", menu.get_node("Props/Headset").global_position)
