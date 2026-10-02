## Экран «Трофеи» в гараже (scenes/menu/garage_menu.gd открывает на пункте ТРОФЕИ): витрина полки над телевизором.
## Кампании и побед пока нет, поэтому полка честная: вещи бокса и пустое место «?», где встанет первая деталь соперника
## (правило трофея, LORE_NULL.md). Когда появится профиль кампании, сюда добавятся настоящие трофеи (EXHIBITS → из профиля).
## Ввод: ←→ / ↑↓ — предмет (камера подъезжает к нему, лампа над ним ярче), Esc / Enter на «Назад» — к списку меню;
## мышь — клик по ◀ ▶. Сигнал selected(i) — garage_menu ставит камеру и свет.
class_name GarageTrophies
extends Control

signal closed
signal selected(index: int)

const EXHIBITS := [
	{"node": "Props/Helmet", "title": "ШЛЕМ НОВИЧКА", "l1": "Выдали в боксе 07 вместе с ключами.", "l2": "Пока ни одной вмятины."},
	{"node": "Props/Boombox", "title": "МАГНИТОЛА", "l1": "Ловит эфир NULL Fighting.", "l2": "Иногда — что-то ещё. Ночью, на краю шкалы."},
	{"node": "Props/QBox", "title": "МЕСТО ДЛЯ ТРОФЕЯ", "l1": "Правило трофея: победитель забирает одну деталь соперника.",
		"l2": "Выиграй бой в Истории — деталь встанет сюда."},
	{"node": "Props/Cup_A", "title": "КУБОК МЕСТНОЙ ЛИГИ", "l1": "Не твой. Остался от прошлого хозяина бокса.", "l2": "На дне нацарапано «07»."},
	{"node": "Props/Cup_B", "title": "МАЛЫЙ КУБОК", "l1": "Тоже не твой.", "l2": "Пока."},
]
const ACCENT := Color(1.0, 0.55, 0.2)

var index := 0
var _x0 := 1920.0 * 0.655
var _title: Label
var _l1: Label
var _l2: Label
var _count: Label
var _names: Array = []


func setup(f_head: Font, f_body: Font, f_mono: Font) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_lbl(tr("ТРОФЕИ"), Vector2(_x0, 296), 50, Color(1, 1, 1), f_head)
	_lbl(tr("полка бокса 07"), Vector2(_x0 + 2, 360), 20, Color(0.7, 0.7, 0.72), f_body)
	var bg := ColorRect.new()
	bg.color = Color(1.0, 0.55, 0.2, 0.13)
	bg.position = Vector2(_x0 - 26, 404)
	bg.size = Vector2(580, 196)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var bar := ColorRect.new()
	bar.color = ACCENT
	bar.position = bg.position
	bar.size = Vector2(6, 196)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	_title = _lbl("", Vector2(_x0, 414), 44, Color(1, 1, 1), f_head)
	_l1 = _lbl("", Vector2(_x0 + 2, 482), 21, Color(0.95, 0.88, 0.78), f_body)
	_l2 = _lbl("", Vector2(_x0 + 2, 516), 19, Color(0.7, 0.7, 0.72), f_body)
	_l1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_l1.size = Vector2(540, 0)
	_count = _lbl("", Vector2(_x0 + 2, 560), 18, ACCENT, f_mono)
	for d in [-1, 1]:
		var a := Button.new()
		a.flat = true
		a.focus_mode = Control.FOCUS_NONE
		a.text = "◀" if d < 0 else "▶"
		a.add_theme_font_override("font", f_mono)
		a.add_theme_font_size_override("font_size", 26)
		a.add_theme_color_override("font_color", ACCENT)
		a.position = Vector2(_x0 + (420 if d < 0 else 480), 552)
		a.pressed.connect(func() -> void: step(d))
		add_child(a)
	for i in EXHIBITS.size():
		_names.append(_lbl(tr(String(EXHIBITS[i]["title"])), Vector2(_x0, 640 + i * 40), 24, Color(0.78, 0.76, 0.72, 0.85), f_head))
	_lbl(tr("←→  ПРЕДМЕТ     ESC  НАЗАД"), Vector2(_x0, 1080 - 76), 17, Color(0.65, 0.65, 0.7), f_mono)
	visible = false


func open() -> void:
	index = 0
	visible = true
	_refresh()
	selected.emit(index)


func close() -> void:
	visible = false
	closed.emit()


func step(dir: int) -> void:
	index = (index + dir + EXHIBITS.size()) % EXHIBITS.size()
	_refresh()
	selected.emit(index)


func handle_input(e: InputEvent) -> bool:
	if not visible:
		return false
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("ui_accept"):
		close()
	elif e.is_action_pressed("ui_right") or e.is_action_pressed("ui_down") or e.is_action_pressed("p1_right") or e.is_action_pressed("p1_down"):
		step(1)
	elif e.is_action_pressed("ui_left") or e.is_action_pressed("ui_up") or e.is_action_pressed("p1_left") or e.is_action_pressed("p1_up"):
		step(-1)
	else:
		return false
	return true


func _refresh() -> void:
	var ex: Dictionary = EXHIBITS[index]
	_title.text = tr(String(ex["title"]))
	_l1.text = tr(String(ex["l1"]))
	_l2.text = tr(String(ex["l2"]))
	_l2.position.y = 516 + (24 if _l1.get_line_count() > 1 else 0)
	_count.text = "%d / %d" % [index + 1, EXHIBITS.size()]
	for i in _names.size():
		(_names[i] as Label).add_theme_color_override("font_color", ACCENT if i == index else Color(0.78, 0.76, 0.72, 0.85))


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
