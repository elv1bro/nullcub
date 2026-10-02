## Экран «Настройки» в гараже (scenes/menu/garage_menu.gd открывает его на пункте НАСТРОЙКИ, камера едет к радио и щитку).
## Строки: громкость, качество графики (пресет автозагрузки Gfx — то же, что F9; хранит его сам Gfx в user://gfx.cfg), эффекты
## ударов (FxPreset), интерфейс боя (HudSkin: трансляция / неон / LED — то же, что H в бою), полный экран, вертикальная
## синхронизация, субтитры N0, НАЗАД; ниже — схема управления (только показ).
## Остальные значения живут в Flow (scripts/menu/flow.gd → user://settings.cfg) и применяются сразу.
## Ввод: ↑↓ строка, ←→ / Enter изменить, Esc — назад; мышь: наведение выбирает строку, клик по ◀ ▶ или по строке меняет.
class_name GarageSettings
extends Control

signal closed
signal volume_changed(v: float)

const ROWS := [
	{"key": "volume", "title": "ГРОМКОСТЬ", "kind": "slider"},
	{"key": "gfx", "title": "ГРАФИКА", "kind": "choice", "values": ["low", "medium", "high", "ultra"], "labels": ["НИЗКАЯ", "СРЕДНЯЯ", "ВЫСОКАЯ", "УЛЬТРА"]},
	{"key": "auto_scale", "title": "АВТО-МАСШТАБ", "kind": "bool"},
	{"key": "fx", "title": "ЭФФЕКТЫ УДАРОВ", "kind": "choice", "values": ["full", "reduced", "off"], "labels": ["ПОЛНЫЕ", "СПОКОЙНЕЕ", "ВЫКЛ"]},
	{"key": "hud_skin", "title": "ИНТЕРФЕЙС БОЯ", "kind": "choice", "values": ["broadcast", "neon", "led"], "labels": ["ТРАНСЛЯЦИЯ", "НЕОН", "LED-ТАБЛО"]},
	{"key": "fullscreen", "title": "ПОЛНЫЙ ЭКРАН", "kind": "bool"},
	{"key": "vsync", "title": "V-SYNC", "kind": "bool"},
	{"key": "subtitles", "title": "СУБТИТРЫ N0", "kind": "bool"},
	{"key": "back", "title": "НАЗАД", "kind": "action"},
]
const CONTROLS := [
	"P1   WASD · Shift — ускорение · Space + A/D — раскрутка",
	"P2   стрелки · правый Ctrl — ускорение · Enter — раскрутка",
	"Геймпад   стик · A — ускорение · B — раскрутка",
	"Блоки   P1: I O P · P2: Num 1 2 3 · всё за Заряд",
	"В бою   R — заново · Esc — пауза · F9 — графика · F10 — эффекты",
]
const ACCENT := Color(1.0, 0.55, 0.2)
const ROW_H := 56.0

var row := 0
var _x0 := 1920.0 * 0.655
var _y0 := 318.0
var _rows: Array = []
var _f_head: Font
var _f_body: Font
var _f_mono: Font
var _local := {}           # если Flow нет (пробы сцены без автозагрузки)


func setup(f_head: Font, f_body: Font, f_mono: Font) -> void:
	_f_head = f_head
	_f_body = f_body
	_f_mono = f_mono
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_lbl("НАСТРОЙКИ", Vector2(_x0, _y0 - 22), 50, Color(1, 1, 1), _f_head)
	for i in ROWS.size():
		var y := _y0 + 60 + i * ROW_H
		var bg := ColorRect.new()
		bg.color = Color(1.0, 0.55, 0.2, 0.13)
		bg.position = Vector2(_x0 - 26, y - 8)
		bg.size = Vector2(580, ROW_H - 6)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		var bar := ColorRect.new()
		bar.color = ACCENT
		bar.position = bg.position
		bar.size = Vector2(6, ROW_H - 6)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bar)
		var hit := Button.new()
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.position = bg.position
		hit.size = bg.size
		hit.mouse_entered.connect(func() -> void:
			row = i
			_refresh())
		hit.pressed.connect(func() -> void:
			row = i
			change(1))
		add_child(hit)
		var t := _lbl(ROWS[i]["title"], Vector2(_x0, y - 2), 30, Color(0.85, 0.83, 0.8), _f_head)
		var v := _lbl("", Vector2(_x0 + 300, y + 4), 22, Color(1, 1, 1), _f_mono)
		var arrows: Array = []
		for d in [-1, 1]:
			var a := Button.new()
			a.flat = true
			a.focus_mode = Control.FOCUS_NONE
			a.text = "◀" if d < 0 else "▶"
			a.add_theme_font_override("font", _f_mono)
			a.add_theme_font_size_override("font_size", 22)
			a.add_theme_color_override("font_color", ACCENT)
			a.position = Vector2(_x0 + (262 if d < 0 else 510), y - 2)
			a.pressed.connect(func() -> void:
				row = i
				change(d))
			add_child(a)
			arrows.append(a)
		_rows.append({"bg": bg, "bar": bar, "title": t, "value": v, "arrows": arrows})
	var cy := _y0 + 60 + ROWS.size() * ROW_H + 24
	_lbl("УПРАВЛЕНИЕ", Vector2(_x0, cy), 24, ACCENT, _f_head)
	for k in CONTROLS.size():
		_lbl(CONTROLS[k], Vector2(_x0, cy + 40 + k * 30), 18, Color(0.78, 0.78, 0.8), _f_body)
	visible = false


func open() -> void:
	row = 0
	visible = true
	_refresh()


func close() -> void:
	visible = false
	closed.emit()


## Ввод экрана; true — событие съедено.
func handle_input(e: InputEvent) -> bool:
	if not visible:
		return false
	if e.is_action_pressed("ui_cancel"):
		close()
	elif e.is_action_pressed("ui_down") or e.is_action_pressed("p1_down"):
		row = (row + 1) % ROWS.size()
		_refresh()
	elif e.is_action_pressed("ui_up") or e.is_action_pressed("p1_up"):
		row = (row - 1 + ROWS.size()) % ROWS.size()
		_refresh()
	elif e.is_action_pressed("ui_right") or e.is_action_pressed("p1_right"):
		change(1)
	elif e.is_action_pressed("ui_left") or e.is_action_pressed("p1_left"):
		change(-1)
	elif e.is_action_pressed("ui_accept"):
		change(1)
	else:
		return false
	return true


func get_value(key: String) -> Variant:
	var gfx := get_node_or_null("/root/Gfx")
	if key == "gfx" and gfx != null:
		return gfx.preset
	if key == "auto_scale" and gfx != null:
		return gfx.auto_scale   # Gfx.DynRes: снижает разрешение 3D, когда игра не держит ~60 fps (Shift+F9)
	var flow := get_node_or_null("/root/Flow")
	if flow != null:
		return flow.get_setting(key)
	return _local.get(key, {"volume": 0.8, "gfx": "high", "fx": "full", "fullscreen": false, "vsync": true, "subtitles": true,
		"hud_skin": "broadcast"}.get(key))


func _set_value(key: String, v: Variant) -> void:
	var gfx := get_node_or_null("/root/Gfx")
	if key == "gfx" and gfx != null:
		gfx.set_preset(String(v))
		return
	if key == "auto_scale" and gfx != null:
		gfx.set_auto_scale(bool(v))
		return
	var flow := get_node_or_null("/root/Flow")
	if flow != null:
		flow.set_setting(key, v)
	else:
		_local[key] = v


## Изменить текущую строку: dir = +1 / −1 (громкость шагом 10 %, выбор по кругу, флажок — переключить, НАЗАД — закрыть).
func change(dir: int) -> void:
	var r: Dictionary = ROWS[row]
	var key := String(r["key"])
	match String(r["kind"]):
		"slider":
			var v := clampf(snappedf(float(get_value(key)) + 0.1 * dir, 0.1), 0.0, 1.0)
			_set_value(key, v)
			volume_changed.emit(v)
		"choice":
			var vals: Array = r["values"]
			var k := vals.find(String(get_value(key)))
			_set_value(key, vals[(k + dir + vals.size()) % vals.size()])
		"bool":
			_set_value(key, not bool(get_value(key)))
		"action":
			close()
			return
	_refresh()


func _refresh() -> void:
	for i in _rows.size():
		var n: Dictionary = _rows[i]
		var on := i == row
		(n["bg"] as ColorRect).visible = on
		(n["bar"] as ColorRect).visible = on
		(n["title"] as Label).add_theme_color_override("font_color", Color(1, 1, 1) if on else Color(0.8, 0.78, 0.74, 0.85))
		var r: Dictionary = ROWS[i]
		var key := String(r["key"])
		var txt := ""
		match String(r["kind"]):
			"slider":
				var v := float(get_value(key))
				var cells := int(round(v * 10.0))
				txt = "▮".repeat(cells) + "▯".repeat(10 - cells) + "  %d%%" % int(round(v * 100.0))
			"choice":
				var k: int = (r["values"] as Array).find(String(get_value(key)))
				txt = String(r["labels"][max(k, 0)])
			"bool":
				txt = "ВКЛ" if bool(get_value(key)) else "ВЫКЛ"
		(n["value"] as Label).text = txt
		for a in n["arrows"]:
			(a as Button).visible = String(r["kind"]) != "action"


func _lbl(s: String, pos: Vector2, px: int, c: Color, font: Font) -> Label:
	var l := Label.new()
	l.text = s
	l.position = pos
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l
