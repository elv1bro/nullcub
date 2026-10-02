## Панель «Управление» (ControlFeel): кнопки вариантов и темпа, ползунки разгона / скорости / инерции / доли тяги на голову, живая скорость
## бойца. Tab — открыть/скрыть, V / T — следующий вариант / темп без панели (тост). Мышь работает, пока панель открыта; кнопки без фокуса,
## чтобы Space / Enter (раскрутка P1 / P2) не «нажимали» их. Создаёт HitJuice (не в headless). Сохраняет в user://control_feel.cfg.
## Запрос автора 02.10: «управление было больше головой… сделать разные варианты и дать попробовать… общий разгон и скорость настраивать».
class_name ControlFeelPanel
extends CanvasLayer

const LAYER := 21
const KEY_PANEL := KEY_TAB
const KEY_VARIANT := KEY_V
const KEY_TEMPO := KEY_T
const FONT := 15
const SPEED_WINDOW_S := 3.0

var open := false
var toast_fn: Callable                      # HitJuice.show_toast

var _root: Control
var _panel: PanelContainer
var _tag: Label
var _variant_btns: Dictionary = {}
var _tempo_btns: Dictionary = {}
var _variant_note: Label
var _tempo_note: Label
var _sliders: Dictionary = {}
var _slider_vals: Dictionary = {}
var _speed: Label
var _t := 0.0
var _peak := 0.0
var _peak_t := 0.0
var _syncing := false


func _init() -> void:
	layer = LAYER
	name = "ControlFeelPanel"


func _ready() -> void:
	ControlFeel.enable_persistence()
	open = ControlFeel.panel_open
	_build()
	_sync()
	_apply_open()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_tag = Label.new()
	_tag.add_theme_font_size_override("font_size", 16)
	_tag.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_tag.add_theme_constant_override("outline_size", 4)
	_tag.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_tag.offset_left = 14.0
	_tag.offset_top = -34.0
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_tag)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.05, 0.86)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.offset_left = 14.0
	_panel.custom_minimum_size = Vector2(470, 0)
	_root.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	_panel.add_child(box)
	box.add_child(_label("УПРАВЛЕНИЕ    Tab — скрыть    V / T — вариант / темп", Color(1.0, 0.82, 0.4)))
	box.add_child(_label("ВАРИАНТ — куда приложена тяга", Color(0.75, 0.8, 0.9)))
	var vf := HFlowContainer.new()
	box.add_child(vf)
	for id in ControlFeel.VARIANT_ORDER:
		var b := _button(String(ControlFeel.VARIANTS[id]["title"]))
		b.pressed.connect(func() -> void: ControlFeel.set_variant(String(id)); _sync())
		vf.add_child(b)
		_variant_btns[id] = b
	_variant_note = _label("", Color(0.6, 0.95, 0.7))
	box.add_child(_variant_note)
	box.add_child(_label("ТЕМП — разгон и скорость", Color(0.75, 0.8, 0.9)))
	var tf := HFlowContainer.new()
	box.add_child(tf)
	for id in ControlFeel.TEMPO_ORDER:
		var b := _button(String(ControlFeel.TEMPOS[id]["title"]))
		b.pressed.connect(func() -> void: ControlFeel.set_tempo(String(id)); _sync())
		tf.add_child(b)
		_tempo_btns[id] = b
	_tempo_note = _label("", Color(0.6, 0.95, 0.7))
	box.add_child(_tempo_note)
	box.add_child(_label("РУЧКИ (любая меняет бой сразу и запоминается)", Color(0.75, 0.8, 0.9)))
	for s in ControlFeel.SLIDERS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var l := _label(String(s[1]), Color(0.93, 0.93, 0.93), false)
		l.custom_minimum_size = Vector2(250, 0)
		row.add_child(l)
		var sl := HSlider.new()
		sl.min_value = float(s[2])
		sl.max_value = float(s[3])
		sl.step = float(s[4])
		sl.focus_mode = Control.FOCUS_NONE
		sl.custom_minimum_size = Vector2(150, 22)
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var key := String(s[0])
		sl.value_changed.connect(func(v: float) -> void:
			if not _syncing:
				ControlFeel.set_value(key, v)
				_sync())
		row.add_child(sl)
		var vl := _label("", Color(0.55, 0.95, 0.65), false)
		vl.custom_minimum_size = Vector2(46, 0)
		row.add_child(vl)
		_sliders[key] = sl
		_slider_vals[key] = [vl, String(s[5])]
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	box.add_child(foot)
	var reset := _button("Сбросить: ТЕЛО · СЕЙЧАС")
	reset.pressed.connect(func() -> void: ControlFeel.reset(); _sync())
	foot.add_child(reset)
	_speed = _label("", Color(1, 1, 1), false)
	foot.add_child(_speed)


func _label(text: String, col: Color, wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(440, 0)
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	return b


## Подтянуть все кнопки и ползунки к ControlFeel.
func _sync() -> void:
	if _panel == null:
		return
	_syncing = true
	for id in _variant_btns:
		_mark(_variant_btns[id] as Button, ControlFeel.variant == id)
	for id in _tempo_btns:
		_mark(_tempo_btns[id] as Button, ControlFeel.tempo == id)
	_variant_note.text = "%s: %s" % [ControlFeel.variant_title(), ControlFeel.variant_note()]
	_tempo_note.text = "%s: %s" % [ControlFeel.tempo_title(), ControlFeel.tempo_note()]
	for key in _sliders:
		var v := ControlFeel.get_value(String(key))
		(_sliders[key] as HSlider).value = v
		var info: Array = _slider_vals[key]
		(info[0] as Label).text = String(info[1]) % v
	_syncing = false
	_tag.text = "Tab — управление: %s" % ControlFeel.label()


func _mark(b: Button, on: bool) -> void:
	b.set_pressed_no_signal(on)
	b.self_modulate = Color(1.0, 0.8, 0.25) if on else Color(1, 1, 1, 0.7)


func _apply_open() -> void:
	_panel.visible = open
	_tag.visible = not open
	ControlFeel.panel_open = open
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE


func toggle() -> void:
	open = not open
	_apply_open()
	_sync()


func _toast(text: String) -> void:
	if toast_fn.is_valid():
		toast_fn.call(text)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_PANEL:
			toggle()
			get_viewport().set_input_as_handled()
		KEY_VARIANT:
			ControlFeel.cycle_variant(1)
			_sync()
			_toast("Управление: %s   (V — следующий, Tab — ручки)" % ControlFeel.variant_title())
			get_viewport().set_input_as_handled()
		KEY_TEMPO:
			ControlFeel.cycle_tempo(1)
			_sync()
			_toast("Темп: %s   (T — следующий, Tab — ручки)" % ControlFeel.tempo_title())
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_t += delta
	if not open or _t < 0.1:
		return
	_t = 0.0
	var d := _first_doll()
	if d == null:
		_speed.text = ""
		return
	var mv := Vector3.ZERO
	var mt := 0.0
	for b in d.parts.values():
		var rb := b as RigidBody3D
		mv += rb.linear_velocity * rb.mass
		mt += rb.mass
	var sp := (mv / maxf(mt, 0.001)).length()
	_peak_t += 0.1
	if sp >= _peak or _peak_t > SPEED_WINDOW_S:
		_peak = sp
		_peak_t = 0.0
	_speed.text = "скорость %.1f м/с (пик %.1f)" % [sp, _peak]


func _first_doll() -> Doll:
	for n in get_tree().get_nodes_in_group("dolls"):
		var d := n as Doll
		if d != null and d.alive and not d.external_input:
			return d
	return null
