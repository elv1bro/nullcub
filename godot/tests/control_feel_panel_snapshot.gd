## Снимок боя с открытой панелью управления (нужно окно): Быстрый бой (купол), Tab, V, кадр → <out>/control_panel.png.
##   godot/tools/godot_nofocus.sh --path godot --resolution 1600x900 res://tests/control_feel_panel_snapshot.tscn -- "out=/abs/control_panel.png,secs=3"
## Заодно проверка: Tab открывает панель, V меняет вариант на следующий, ползунок меняет ControlFeel, J включает ДРАЙВ (Drive),
## сброс возвращает как было. Файл настроек автора не трогает (ControlFeel.no_disk).
extends Node

var out := "/tmp/control_panel.png"
var secs := 3.0
var _t := 0.0
var _stage := 0
var _fails := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2:
				if p[0] == "out": out = p[1]
				elif p[0] == "secs": secs = float(p[1])
	ControlFeel.no_disk = true   # не читать и не затирать user://control_feel.cfg автора
	ControlFeel.reset()
	var scene := (load("res://scenes/playground_null_hall.tscn") as PackedScene).instantiate()
	add_child(scene)


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _process(delta: float) -> void:
	_t += delta
	if _stage == 0 and _t > secs:
		_stage = 1
		_key(KEY_TAB)
	elif _stage == 1 and _t > secs + 0.3:
		_stage = 2
		var panel := get_tree().root.find_child("ControlFeelPanel", true, false) as ControlFeelPanel
		_check(panel != null and panel.open, "Tab открыл панель")
		_check(ControlFeel.variant == "body", "стартовый вариант ТЕЛО")
		_key(KEY_V)
	elif _stage == 2 and _t > secs + 0.6:
		_stage = 3
		_check(ControlFeel.variant == "head", "V → ГОЛОВА")
		var panel2 := get_tree().root.find_child("ControlFeelPanel", true, false) as ControlFeelPanel
		(panel2._sliders["thrust"] as HSlider).value = 20.0
		_check(is_equal_approx(ControlFeel.thrust(), 20.0), "ползунок разгона меняет ControlFeel")
		_check(ControlFeel.tempo == "custom", "ручка разгона → темп «СВОЙ»")
		_key(KEY_J)
	elif _stage == 3 and _t > secs + 0.9:
		_stage = 4
		_check(Drive.on, "J → ДРАЙВ вкл")
		_check(ControlFeel.variant == "head", "ДРАЙВ при ГОЛОВЕ вариант не меняет")
		_check(ControlFeel.label().contains(tr("ДРАЙВ")), "подпись панели говорит про ДРАЙВ")
	elif _stage == 4 and _t > secs + 1.4:
		_stage = 5
		_capture()


func _capture() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	ControlFeel.reset()
	print("fails: ", _fails)
	get_tree().quit(1 if _fails > 0 else 0)
