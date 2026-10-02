## Проба потока экранов (scripts/menu/flow.gd, гараж — главная сцена) без окна:
##   godot --headless --path godot --fixed-fps 60 res://tests/flow_probe.tscn
## Наблюдатель висит под root и переживает смену сцен. Путь настоящим вводом: гараж (титул) → Space → «2» (Быстрый бой) →
## Enter → playground.tscn → Esc (пауза, дерево на паузе) → Esc (продолжить) → Esc → «В ГАРАЖ» → гараж сразу списком на
## «Быстром бое» → снова в бой → MAIN MENU в итогах (сигнал панели) → гараж → мастерская → двойной Esc → гараж на «Мастерской».
## Плюс настройки: громкость пишется в user://settings.cfg и ставится на шину Master. В stdout «=== FLOW PROBE ===» + JSON.
extends Node

const MENU := "res://scenes/menu/garage_menu.tscn"
const RUINS := "res://scenes/playground.tscn"
const WORKSHOP := "res://scenes/workshop/workshop_build.tscn"


func _ready() -> void:
	var w := Watcher.new()
	w.name = "FlowWatcher"
	get_tree().root.call_deferred("add_child", w)
	get_tree().call_deferred("change_scene_to_file", MENU)


class Watcher extends Node:
	var checks: Array = []

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_run()

	func _check(id: String, ok: bool, value = null) -> void:
		checks.append({"id": id, "ok": ok, "value": value})
		print("flow_probe: ", id, " ", ok, " ", value)

	func _sec(s: float) -> void:
		await get_tree().create_timer(s, true, false, true).timeout

	func _key(code: Key) -> void:
		for p in [true, false]:
			var e := InputEventKey.new()
			e.physical_keycode = code
			e.keycode = code
			e.pressed = p
			Input.parse_input_event(e)
		await get_tree().process_frame
		await get_tree().process_frame

	func _scene() -> String:
		var s := get_tree().current_scene
		return s.scene_file_path if s != null else ""

	func _wait_scene(path: String, timeout := 8.0) -> bool:
		var t := 0.0
		while _scene() != path and t < timeout:
			await _sec(0.1)
			t += 0.1
		await _sec(0.4)
		return _scene() == path

	func _run() -> void:
		var flow := get_node("/root/Flow")
		_check("main_scene_is_garage", ProjectSettings.get_setting("application/run/main_scene") == MENU)
		_check("garage_loaded", await _wait_scene(MENU))
		var menu := get_tree().current_scene
		_check("title_first", String(menu.get("state")) == "title", menu.get("state"))
		await _key(KEY_SPACE)
		await _key(KEY_2)
		await _sec(0.9)
		await _key(KEY_ENTER)
		_check("enter_quick_to_ruins", await _wait_scene(RUINS), _scene())
		await _sec(1.0)
		await _key(KEY_ESCAPE)
		_check("esc_pauses", bool(flow.is_paused()) and get_tree().paused, [flow.is_paused(), get_tree().paused])
		await _key(KEY_ESCAPE)
		_check("esc_resumes", not bool(flow.is_paused()) and not get_tree().paused, [flow.is_paused(), get_tree().paused])
		await _key(KEY_ESCAPE)
		var btn: Button = null
		for b in get_node("/root/Flow").find_children("*", "Button", true, false):
			if (b as Button).text == "В ГАРАЖ":
				btn = b
		_check("pause_has_garage_button", btn != null)
		if btn != null:
			btn.pressed.emit()
		_check("pause_to_garage", await _wait_scene(MENU), _scene())
		menu = get_tree().current_scene
		_check("return_skips_title", menu is GarageMenu and String(menu.get("state")) == "menu" and int(menu.get("focus")) == 1 and not get_tree().paused,
			[menu.get("state"), menu.get("focus"), get_tree().paused])
		# итоги: MAIN MENU
		get_tree().change_scene_to_file(RUINS)
		await _wait_scene(RUINS)
		var hud := get_tree().current_scene.get_node_or_null("HUD")
		var res: Node = hud.get("results") if hud != null else null
		_check("results_menu_enabled", res != null and not (res.get("menu_btn") as Button).disabled)
		if res != null:
			res.emit_signal("main_menu")
		_check("results_to_garage", await _wait_scene(MENU), _scene())
		# мастерская: двойной Esc
		flow.last_item = 2
		get_tree().change_scene_to_file(WORKSHOP)
		await _wait_scene(WORKSHOP, 20.0)
		await _sec(1.0)
		await _key(KEY_ESCAPE)
		await _sec(0.3)
		await _key(KEY_ESCAPE)
		_check("workshop_double_esc_to_garage", await _wait_scene(MENU, 10.0), _scene())
		menu = get_tree().current_scene
		_check("workshop_return_focus", menu is GarageMenu and int(menu.get("focus")) == 2, menu.get("focus"))
		# настройки
		var old: float = float(flow.get_setting("volume"))
		flow.set_setting("volume", 0.5)
		var db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))
		flow.load_settings()
		_check("volume_applied_and_saved", absf(db - linear_to_db(0.5)) < 0.01 and absf(float(flow.get_setting("volume")) - 0.5) < 0.001, [db, flow.get_setting("volume")])
		flow.set_setting("volume", old)
		var ok := true
		for c in checks:
			ok = ok and bool(c["ok"])
		print("=== FLOW PROBE ===")
		print(JSON.stringify({"ok": ok, "checks": checks}))
		print("=== OK ===" if ok else "=== FAIL ===")
		get_tree().quit(0 if ok else 1)
