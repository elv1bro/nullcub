## Проба тестового меню сборки (docs/plan-demo/RELEASE_0.0.1.md):
##   godot --headless --path godot --fixed-fps 60 res://tests/menu_probe.tscn
##   menu_items    — пункты меню ведут к существующим сценам, есть «В гараж», первый пункт в фокусе
##   menu_version  — строка версии = application/config/version (0.0.1); главная сцена проекта — boot.tscn (лоадер, под ним грузится гараж)
##                   (scenes/menu/garage_menu.tscn), в нём есть пункт, ведущий сюда (ВСЕ РЕЖИМЫ)
##   menu_open     — каждый пункт открывается (сцена грузится и живёт 1 с без ошибок скрипта)
##   menu_back     — Esc на площадке купола ставит паузу Flow, «В ГАРАЖ» в ней — в гараж
##   menu_esc      — Esc в этом меню — тоже в гараж
extends Node

const MENU := "res://scenes/menu/test_menu.tscn"
const GARAGE := "res://scenes/menu/garage_menu.tscn"
var checks: Array = []


func _ready() -> void:
	_detach.call_deferred()


## Проба переключает сцены сама: уходит из текущей сцены в корень дерева (иначе change_scene_to_file выгрузил бы её).
func _detach() -> void:
	var dummy := Node.new()
	get_tree().root.add_child(dummy)
	reparent(get_tree().root)
	get_tree().current_scene = dummy
	await _run()


func _run() -> void:
	var M := load("res://scenes/menu/test_menu.gd")
	var missing: Array = []
	for it in M.ITEMS:
		if not ResourceLoader.exists(String(it[1])):
			missing.append(it[1])
	get_tree().change_scene_to_file(MENU)
	await _frames(5)
	var menu := get_tree().current_scene
	var items: Node = menu.get_node("%Items")
	var first := items.get_child(0) as Button
	_check("menu_items", missing.is_empty() and items.get_child_count() == M.ITEMS.size() + 2 and first.has_focus(),
		"пунктов %d (+ выход), нет сцен %s, фокус на первом %s" % [M.ITEMS.size(), missing, first.has_focus()])
	var v := String(ProjectSettings.get_setting("application/config/version", ""))
	var from_garage := GarageMenu.ITEMS.any(func(it: Dictionary) -> bool: return String(it["go"]) == MENU)
	_check("menu_version", RegEx.create_from_string("^\\d+\\.\\d+\\.\\d+$").search(v) != null and String(menu.get_node("%Version").text).contains(v) and from_garage
		and String(ProjectSettings.get_setting("application/run/main_scene", "")) == "res://scenes/boot.tscn", "версия «%s», главная сцена %s, пункт гаража сюда %s" % [v,
		ProjectSettings.get_setting("application/run/main_scene", ""), from_garage])
	var bad: Array = []
	for it in M.ITEMS:
		get_tree().change_scene_to_file(String(it[1]))
		await _frames(60)
		var cs := get_tree().current_scene
		if cs == null or cs.scene_file_path != String(it[1]):
			bad.append(it[1])
	_check("menu_open", bad.is_empty(), "не открылись %s" % [bad])
	get_tree().change_scene_to_file("res://scenes/playground_null_hall.tscn")
	await _frames(30)
	var e := InputEventKey.new()
	e.physical_keycode = KEY_ESCAPE
	e.keycode = KEY_ESCAPE
	e.pressed = true
	get_viewport().push_input(e)
	await _frames(10)
	var flow := get_node("/root/Flow")
	var paused: bool = flow.is_paused() and get_tree().paused
	var to_garage: Button = null
	for b in flow.find_children("*", "Button", true, false):
		if (b as Button).text == "В ГАРАЖ":
			to_garage = b
	var found := to_garage != null      # до нажатия: кнопка освобождается вместе с паузой
	if found:
		to_garage.pressed.emit()
	await _frames(20)
	var cs2 := get_tree().current_scene
	_check("menu_back", paused and found and cs2 != null and cs2.scene_file_path == GARAGE and not get_tree().paused,
		"пауза %s, кнопка %s, после «В гараж»: %s" % [paused, found, cs2.scene_file_path if cs2 else "null"])
	get_tree().change_scene_to_file(MENU)
	await _frames(10)
	get_viewport().push_input(e)
	await _frames(20)
	var cs3 := get_tree().current_scene
	_check("menu_esc", cs3 != null and cs3.scene_file_path == GARAGE, "после Esc в меню: %s" % (cs3.scene_file_path if cs3 else "null"))
	var ok := true
	for c in checks:
		ok = ok and bool(c["ok"])
	print("menu_probe: %s (%d checks)" % ["OK" if ok else "FAIL", checks.size()])
	get_tree().quit(0 if ok else 1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
	# смена сцены кнопками идёт под лоадером (scripts/menu/loading.gd): ждём, пока он уйдёт
	var t0 := Time.get_ticks_msec()
	while Loading.showing and Time.get_ticks_msec() - t0 < 25000:
		await get_tree().process_frame


func _check(id: String, ok: bool, text: String) -> void:
	checks.append({"id": id, "ok": ok, "info": text})
	print("%s %s — %s" % ["PASS" if ok else "FAIL", id, text])
