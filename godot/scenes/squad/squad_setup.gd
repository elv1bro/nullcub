## Экран настроек «Стычки 3 на 3» перед боем (автор 06.10: «режим настроек перед запуском боя — количество фрагов + ещё что-то»).
## Поверх площадки (карта и бойцы видны за затемнением), бой не начинается, пока не нажато «В БОЙ». Строки — SquadSettings:
## режим, карта, до скольких очков (фраги или флаги — по режиму), время, уровень ботов, прочность суставов, ящики, бонусы, свой класс.
## Клавиши: W / S или ↑ / ↓ — строка, A / D или ← / → — значение, Enter / Space — в бой, Esc — назад в гараж; мышь — ◀ ▶ и кнопки.
## started — «В БОЙ» (значения уже в SquadSettings), cancelled — назад.
class_name SquadSetup
extends CanvasLayer

signal started
signal cancelled

const W := 860.0
const ROW_H := 50.0
const ACCENT := Color(1.0, 0.78, 0.3)

## [ключ, подпись]; значения и подписи значений — _values / _value_text.
const ROWS := [
	["mode", "РЕЖИМ"], ["night", "КАРТА"], ["goal", "ДО ПОБЕДЫ"], ["time", "ВРЕМЯ"], ["bots", "БОТЫ"],
	["class", "ТВОЙ КЛАСС"], ["joints", "ПРОЧНОСТЬ СУСТАВОВ"], ["supplies", "ЯЩИКИ"], ["boosts", "БОНУСЫ В ЯЩИКАХ"],
]

var sel := 0
var _rows: Array = []      # [{panel, value}]
var _desc: Label
var _root: Control


func _init() -> void:
	layer = 20


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = HudSkin.theme()
	add_child(_root)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.025, 0.04, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -W * 0.5
	panel.offset_right = W * 0.5
	panel.offset_top = -380.0
	panel.offset_bottom = 380.0
	panel.add_theme_stylebox_override("panel", _panel_box())
	_root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var title := _label(tr("СТЫЧКА 3 НА 3"), 54, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(title)
	var sub := _label(tr("настройки боя"), 22, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size.y = 10.0
	v.add_child(gap)
	for i in ROWS.size():
		v.add_child(_row(i))
	_desc = _label("", 20, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(W - 80.0, 56.0)
	v.add_child(_desc)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 24)
	v.add_child(buttons)
	var back := _button(tr("← НАЗАД"), false)
	back.pressed.connect(func() -> void: cancelled.emit())
	buttons.add_child(back)
	var go := _button(tr("В БОЙ  ▸"), true)
	go.pressed.connect(_start)
	buttons.add_child(go)
	var keys := _label(tr("W / S — строка · A / D — значение · Enter — в бой · Esc — назад"), 18, Color(1, 1, 1, 0.5),
		HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(keys)
	_refresh()


func _panel_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.045, 0.065, 0.96)
	sb.border_color = ACCENT
	sb.border_width_top = 4
	sb.set_corner_radius_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 18
	sb.content_margin_left = 40.0
	sb.content_margin_right = 40.0
	sb.content_margin_top = 24.0
	sb.content_margin_bottom = 22.0
	return sb


func _label(text: String, px: int, c: Color, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	HudSkin.style_label(l, "display", px, c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, main: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260.0, 58.0)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", HudSkin.font("display"))
	b.add_theme_font_size_override("font_size", 28)
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		var base := ACCENT if main else Color(0.2, 0.22, 0.28)
		sb.bg_color = base.darkened(0.15 if st == "normal" else (0.0 if st == "hover" else 0.3))
		sb.set_corner_radius_all(8)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", Color(0.06, 0.05, 0.03) if main else Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color(0.06, 0.05, 0.03) if main else Color.WHITE)
	return b


## Строка i: подпись слева, «◀ значение ▶» справа; клик по строке — выбрать, по стрелкам — листать.
func _row(i: int) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(W - 80.0, ROW_H)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	var name_l := _label(tr(String(ROWS[i][1])), 26, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name_l)
	var left := _arrow("◀", i, -1)
	h.add_child(left)
	var val := _label("", 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	val.custom_minimum_size = Vector2(300.0, 0.0)
	h.add_child(val)
	h.add_child(_arrow("▶", i, 1))
	p.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			sel = i
			_refresh())
	p.mouse_entered.connect(func() -> void:
		sel = i
		_refresh())
	_rows.append({"panel": p, "value": val})
	return p


func _arrow(t: String, i: int, dir: int) -> Button:
	var b := Button.new()
	b.text = t
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(44.0, 40.0)
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", ACCENT)
	b.pressed.connect(func() -> void:
		sel = i
		change(dir))
	return b


## Варианты строки key.
func _values(key: String) -> Array:
	match key:
		"mode":
			return SquadSettings.MODES
		"night", "joints", "supplies", "boosts":
			return [false, true]
		"goal":
			return Tuning.SQUAD_CAPTURE_CHOICES if SquadSettings.mode == "ctf" else Tuning.SQUAD_SCORE_CHOICES
		"time":
			return Tuning.SQUAD_TIME_CHOICES
		"bots":
			return [1, 2, 3]
		"class":
			return Tuning.SQUAD_CLASS_ORDER
	return []


func value_of(key: String) -> Variant:
	match key:
		"mode": return SquadSettings.mode
		"night": return SquadSettings.night
		"goal": return SquadSettings.goal()
		"time": return SquadSettings.time_min
		"bots": return SquadSettings.bot_level
		"class": return SquadSettings.player_class
		"joints": return SquadSettings.joints
		"supplies": return SquadSettings.supplies
		"boosts": return SquadSettings.boosts
	return null


func _set_value(key: String, v: Variant) -> void:
	match key:
		"mode": SquadSettings.mode = String(v)
		"night": SquadSettings.night = bool(v)
		"goal":
			if SquadSettings.mode == "ctf":
				SquadSettings.captures_to_win = int(v)
			else:
				SquadSettings.score_to_win = int(v)
		"time": SquadSettings.time_min = int(v)
		"bots": SquadSettings.bot_level = int(v)
		"class": SquadSettings.player_class = String(v)
		"joints": SquadSettings.joints = bool(v)
		"supplies": SquadSettings.supplies = bool(v)
		"boosts": SquadSettings.boosts = bool(v)


## Подпись значения (ключ перевода и формат).
func _value_text(key: String, v: Variant) -> String:
	match key:
		"mode":
			return tr("ЗАХВАТ ФЛАГА") if String(v) == "ctf" else tr("ПЕРЕСТРЕЛКА")
		"night":
			return tr("НОЧЬ") if bool(v) else tr("ДЕНЬ")
		"goal":
			return (tr("%d ФЛАГОВ") if SquadSettings.mode == "ctf" else tr("%d ОЧКОВ")) % int(v)
		"time":
			return tr("%d МИН") % int(v)
		"bots":
			return tr("УРОВЕНЬ %d") % int(v)
		"class":
			return tr(String(Tuning.SQUAD_CLASSES[String(v)]["title"]))
		_:
			return tr("ВКЛ") if bool(v) else tr("ВЫКЛ")


## Пояснение строки (что делает настройка).
func _desc_of(key: String) -> String:
	match key:
		"mode":
			return tr("Захват флага: принеси чужой флаг к своему, пока свой — дома. Выбывания очков не дают") if SquadSettings.mode == "ctf" \
				else tr("Перестрелка: каждый выбывший соперник — очко команде")
		"night":
			return tr("Полигон днём или ночью: луна, фонари цвета команд, светящиеся трассеры")
		"goal":
			return tr("До скольких очков идёт матч; кто первый набрал — победил")
		"time":
			return tr("Время кончилось — побеждает ведущая команда, при равном счёте — ничья")
		"bots":
			return tr("Меткость, реакция и скорость ботов. В бою — клавиша K")
		"class":
			return tr(String(Tuning.SQUAD_CLASSES[SquadSettings.player_class]["note"])) + " · " + tr("в бою — клавиши 1–3")
		"joints":
			return tr("Конечности отлетают от ударов и пуль; любой ящик возвращает руку с оружием")
		"supplies":
			return tr("Ящики с патронами, жизнями и бронёй появляются на карте")
		"boosts":
			return tr("Бонусы на время: обзор, ярость, форсаж")
	return ""


## Листать значение выбранной строки на dir.
func change(dir: int) -> void:
	var key := String(ROWS[sel][0])
	var vals := _values(key)
	if vals.is_empty():
		return
	var i := vals.find(value_of(key))
	i = wrapi((i if i >= 0 else 0) + dir, 0, vals.size())
	_set_value(key, vals[i])
	_refresh()


func _refresh() -> void:
	for i in _rows.size():
		var key := String(ROWS[i][0])
		var r: Dictionary = _rows[i]
		(r["value"] as Label).text = _value_text(key, value_of(key))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1.0, 0.78, 0.3, 0.14) if i == sel else Color(1, 1, 1, 0.03)
		sb.border_color = ACCENT
		sb.border_width_left = 5 if i == sel else 0
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 16.0
		sb.content_margin_right = 8.0
		(r["panel"] as PanelContainer).add_theme_stylebox_override("panel", sb)
	_desc.text = _desc_of(String(ROWS[sel][0]))


func _start() -> void:
	started.emit()


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed):
		return
	var k: int = (e as InputEventKey).physical_keycode
	match k:
		KEY_W, KEY_UP:
			sel = wrapi(sel - 1, 0, ROWS.size())
			_refresh()
		KEY_S, KEY_DOWN:
			sel = wrapi(sel + 1, 0, ROWS.size())
			_refresh()
		KEY_A, KEY_LEFT:
			change(-1)
		KEY_D, KEY_RIGHT:
			change(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if not e.echo:
				_start()
		KEY_ESCAPE:
			if not e.echo:
				cancelled.emit()
		_:
			return
	get_viewport().set_input_as_handled()
