## Поток экранов игры (docs/plan-demo/MENU_GARAGE.md): гараж — главная сцена (scenes/menu/garage_menu.tscn); из боя
## и мастерской — обратно в гараж на тот же пункт; пауза в бою; настройки игрока (user://settings.cfg) применяются при старте.
## Autoload «Flow» (project.godot). Кто зовёт:
##   playground.gd / playground_pve.gd — Esc → toggle_pause(рестарт матча): ПРОДОЛЖИТЬ / ЗАНОВО / В ГАРАЖ;
##   hud.gd — MAIN MENU в итогах → to_menu(); workshop_build.gd — двойной Esc → to_menu();
##   garage_menu.gd — перед уходом в бой пишет last_item; при returning открывается сразу списком, без титула.
extends Node

const MENU := "res://scenes/menu/garage_menu.tscn"
const SETTINGS_PATH := "user://settings.cfg"
## Громкость — линейная доля 0..1 на шину Master (linear_to_db), fx — пресет FxPreset (full / reduced / off),
## subtitles — субтитры реплик N0 в гараже.
const DEFAULTS := {"volume": 0.8, "fullscreen": false, "vsync": true, "fx": "full", "subtitles": true}
const ACCENT := Color(1.0, 0.55, 0.2)

var returning := false
var last_item := 0
var settings := {}
var _pause: CanvasLayer = null
var _restart := Callable()
var _font_head: Font = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply_settings()


# ---------------------------------------------------------------- переходы

## В гараж; item ≥ 0 — на какой пункт встать (иначе тот, с которого ушли).
func to_menu(item := -1) -> void:
	if item >= 0:
		last_item = item
	returning = true
	close_pause()
	get_tree().paused = false
	Engine.time_scale = 1.0
	# отложенно: вызывающий (обработчик ввода мастерской, кнопка итогов) ещё доработает в этом кадре
	get_tree().call_deferred("change_scene_to_file", MENU)


## Пауза поверх боя. restart — что делать на «Заново» (Match.restart / WaveDirector.restart); пустой — пункта нет.
func toggle_pause(restart := Callable()) -> void:
	get_viewport().set_input_as_handled()   # иначе тот же Esc дойдёт до Flow._unhandled_input и сразу закроет паузу
	if _pause != null:
		close_pause()
		return
	_restart = restart
	_build_pause()
	get_tree().paused = true


func close_pause() -> void:
	if _pause != null:
		_pause.queue_free()
		_pause = null
	get_tree().paused = false


func is_paused() -> bool:
	return _pause != null


func _build_pause() -> void:
	_pause = CanvasLayer.new()
	_pause.name = "PauseOverlay"
	_pause.layer = 60
	_pause.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pause)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.01, 0.02, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-220, -170)
	box.custom_minimum_size = Vector2(440, 0)
	box.add_theme_constant_override("separation", 10)
	_pause.add_child(box)
	var title := Label.new()
	title.text = "ПАУЗА"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", head_font())
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", ACCENT)
	box.add_child(title)
	var first: Button = null
	var items := [["ПРОДОЛЖИТЬ", close_pause]]
	if _restart.is_valid():
		items.append(["ЗАНОВО", func() -> void:
			var r := _restart
			close_pause()
			r.call()])
	items.append(["В ГАРАЖ", func() -> void: to_menu()])
	for it in items:
		var b := Button.new()
		b.text = it[0]
		b.flat = true
		b.add_theme_font_override("font", head_font())
		b.add_theme_font_size_override("font_size", 44)
		b.add_theme_color_override("font_color", Color(0.85, 0.83, 0.8))
		b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		b.add_theme_color_override("font_focus_color", Color(1, 1, 1))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1.0, 0.55, 0.2, 0.16)
		sb.border_color = ACCENT
		sb.border_width_left = 6
		b.add_theme_stylebox_override("focus", sb)
		b.pressed.connect(it[1])
		b.mouse_entered.connect(b.grab_focus)
		box.add_child(b)
		if first == null:
			first = b
	var hint := Label.new()
	hint.text = "↑↓  ВЫБОР     ENTER  ОК     ESC  ПРОДОЛЖИТЬ"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	box.add_child(hint)
	first.call_deferred("grab_focus")


func _unhandled_input(e: InputEvent) -> void:
	if _pause != null and e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).physical_keycode == KEY_ESCAPE:
		close_pause()
		get_viewport().set_input_as_handled()


## Шрифт заголовков меню (Oswald, OFL), общий для гаража и паузы.
func head_font() -> Font:
	if _font_head == null:
		_font_head = make_font("res://assets/fonts/Oswald.ttf", 650)
	return _font_head


static func make_font(path: String, weight: int) -> Font:
	var fv := FontVariation.new()
	fv.base_font = load(path)
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return fv


# ---------------------------------------------------------------- настройки

func load_settings() -> void:
	settings = DEFAULTS.duplicate()
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		for k in DEFAULTS:
			settings[k] = cf.get_value("player", k, DEFAULTS[k])


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings:
		cf.set_value("player", k, settings[k])
	cf.save(SETTINGS_PATH)


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	apply_settings()
	save_settings()


func get_setting(key: String) -> Variant:
	return settings.get(key, DEFAULTS.get(key))


func apply_settings() -> void:
	_bus_volume("Master", float(settings["volume"]))
	FxPreset.set_preset(String(settings["fx"]), get_tree())
	if DisplayServer.get_name() != "headless":
		var fs := bool(settings["fullscreen"])
		var mode := DisplayServer.window_get_mode()
		if fs and mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif not fs and mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(settings["vsync"]) else DisplayServer.VSYNC_DISABLED)


func _bus_volume(bus: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(i, linear <= 0.001)
