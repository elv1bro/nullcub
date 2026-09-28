## Регистрирует действия p1..p4 в InputMap при старте (проще, чем руками в project.godot).
## P1: WASD + Shift (рывок) + Space (переворот). P2: стрелки + правый Ctrl + правый Shift.
## P3/P4: только геймпады (устройства 2 и 3); геймпады 0 и 1 дублируют P1/P2.
extends Node

func _ready() -> void:
	_keys("p1", KEY_A, KEY_D, KEY_W, KEY_S, KEY_SHIFT, KEY_SPACE)
	_keys("p2", KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_CTRL, KEY_ENTER)
	for i in range(4):
		_pad("p%d" % (i + 1), i)

func _add(action: String, ev: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
	InputMap.action_add_event(action, ev)

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e

func _keys(p: String, l: Key, r: Key, u: Key, d: Key, dash: Key, flip: Key) -> void:
	_add(p + "_left", _key(l)); _add(p + "_right", _key(r))
	_add(p + "_up", _key(u)); _add(p + "_down", _key(d))
	_add(p + "_dash", _key(dash)); _add(p + "_flip", _key(flip))

func _pad(p: String, device: int) -> void:
	for pair in [["_left", JOY_AXIS_LEFT_X, -1.0], ["_right", JOY_AXIS_LEFT_X, 1.0], ["_up", JOY_AXIS_LEFT_Y, -1.0], ["_down", JOY_AXIS_LEFT_Y, 1.0]]:
		var m := InputEventJoypadMotion.new()
		m.device = device
		m.axis = pair[1]
		m.axis_value = pair[2]
		_add(p + pair[0], m)
	for pair in [["_dash", JOY_BUTTON_A], ["_flip", JOY_BUTTON_B]]:
		var b := InputEventJoypadButton.new()
		b.device = device
		b.button_index = pair[1]
		_add(p + pair[0], b)
