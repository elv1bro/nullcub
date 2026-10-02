## Проба тестового меню сборки (docs/plan-demo/RELEASE_0.0.1.md):
##   godot --headless --path godot --fixed-fps 60 res://tests/menu_probe.tscn
##   menu_items    — пункты меню ведут к существующим сценам, есть «Выход», первый пункт в фокусе
##   menu_version  — строка версии = application/config/version (0.0.1), главная сцена проекта — меню
##   menu_open     — каждый пункт открывается (сцена грузится и живёт 1 с без ошибок скрипта)
##   menu_back     — Esc на площадке купола возвращает в меню
extends Node

const MENU := "res://scenes/menu/test_menu.tscn"
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
	_check("menu_version", v == "0.0.1" and String(menu.get_node("%Version").text).contains(v)
		and String(ProjectSettings.get_setting("application/run/main_scene", "")) == MENU, "версия «%s», главная сцена %s" % [v,
		ProjectSettings.get_setting("application/run/main_scene", "")])
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
	var cs2 := get_tree().current_scene
	_check("menu_back", cs2 != null and cs2.scene_file_path == MENU, "после Esc: %s" % (cs2.scene_file_path if cs2 else "null"))
	var ok := true
	for c in checks:
		ok = ok and bool(c["ok"])
	print("menu_probe: %s (%d checks)" % ["OK" if ok else "FAIL", checks.size()])
	get_tree().quit(0 if ok else 1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(id: String, ok: bool, text: String) -> void:
	checks.append({"id": id, "ok": ok, "info": text})
	print("%s %s — %s" % ["PASS" if ok else "FAIL", id, text])
