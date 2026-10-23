extends Node
## Невидимый запуск оконной пробы (по образцу fgame/tools/godot_bg): окно — 1×1 прозрачный пиксель за краем экрана, без фокуса
## и без мыши; сцена пробы рисуется во внутренний SubViewport нужного размера, поэтому снимки через get_viewport().get_texture()
## работают как в обычном окне. Запускает godot/tools/godot_bg.sh (он же подменяет главную сцену через override.cfg).
## Аргументы после «--»: --scene=res://… (сцена пробы), --size=WxH (размер кадра, по умолчанию 1920×1080), остальное — пробе.

var _view: SubViewport


func _ready() -> void:
	# Фоновые прогоны молчат: человек рядом работает.
	AudioServer.set_bus_mute(0, true)
	var window := get_window()
	window.mouse_passthrough = true
	window.unfocusable = true
	window.size = Vector2i(1, 1)
	window.position = Vector2i(-20000, -20000)
	var size := Vector2i(1920, 1080)
	var scene := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--size="):
			var parts := arg.trim_prefix("--size=").split("x")
			size = Vector2i(int(parts[0]), int(parts[1]))
		elif arg.begins_with("--scene="):
			scene = arg.trim_prefix("--scene=")
	if scene == "":
		push_error("godot_bg: нет --scene=res://…")
		get_tree().quit(2)
		return
	_view = SubViewport.new()
	_view.size = size
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view.msaa_3d = ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d")
	_view.audio_listener_enable_3d = true
	add_child(_view)
	_view.add_child(load(scene).instantiate())


func _process(_delta: float) -> void:
	# macOS считает крошечное окно за краем экрана закрытым, и Godot перестаёт рисовать — тогда рисуем кадр сами.
	if not DisplayServer.window_can_draw():
		RenderingServer.force_draw(true, 0.0)
