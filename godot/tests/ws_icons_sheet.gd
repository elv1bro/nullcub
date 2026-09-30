## Лист значков и стиля мастерской v0.3 (scenes/workshop/ui/ws_icon.gd, ws_style.gd) — на тёмном фоне досок мастерской:
##   слева — все WsIcon.names() по 48 и 24 px с подписью, смысловые цвета, масштабы 16…48, макет верхней панели и чипов;
##   справа — WsStyle: главная панель с заклёпками и шкалой шрифтов (L / M / S / XS), секция-вкладыш, кнопки button / tab / chip /
##   danger во всех состояниях (normal / hover / pressed / selected / disabled), ИСПЫТАТЬ (cta), кнопки-значки, карточки деталей
##   (normal / hover / selected / dim), поля ввода (пусто / фокус / только чтение), всплывашки «встанет» / «не хватает энергии».
## Проверки (выход 1 при провале): каждое имя что-то рисует (WsIcon.drawn_primitives > 0) и не вылезает за сетку 24×24; неизвестное
## имя не рисует ничего (детектор жив); все имена из спеки есть; значок в кнопке с текстом стоит на левом поле, кнопка резервирует
## ширину под значок + текст, после ресайза значок по центру по вертикали; значок без текста — по центру кнопки.
## Запуск (окно, кадр):  xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --path . --resolution 1920x1080
##                       res://tests/ws_icons_sheet.tscn -- "out=/abs/ws_icons_sheet.png"   (по умолчанию user://ws_icons_sheet.png)
## Headless — только проверки, без PNG. Печатает «WS ICONS OK n=<число значков>».
extends Control

const OUT_DEFAULT := "user://ws_icons_sheet.png"
## Имена, которые обещает спека v0.3 (WsIcon может знать больше).
const REQUIRED := [
	"energy", "mass", "search", "filter", "physics", "mirror", "duplicate", "delete", "undo", "redo", "star", "star_filled",
	"clock", "all", "gear", "play", "close", "chevron_left", "chevron_right", "chevron_down", "help", "save", "folder", "pull",
	"body", "head", "limb", "joint", "hand", "weapon", "armor", "material", "paint", "decor",
]
const STATES := ["normal", "hover", "pressed", "selected", "disabled"]
const STATE_TITLES := {"normal": "обычная", "hover": "наведение", "pressed": "нажата", "selected": "выбрана", "disabled": "выключена"}
## [вид, значок, подпись] — строки матрицы кнопок.
const KIND_ROWS := [["button", "save", "Сохранить"], ["tab", "body", "Тело"], ["chip", "star", "Избранное"],
	["danger", "delete", "Удалить"]]
const LEFT_X := 32.0
const RIGHT_X := 1010.0
const RIGHT_W := 878.0
const CELL := Vector2(112, 114)

var out_path := OUT_DEFAULT
var _big: Dictionary = {}          # имя -> WsIcon 48 px
var _small: Dictionary = {}        # имя -> WsIcon 24 px
var _unknown: WsIcon
var _text_btn: Button
var _text_icon: WsIcon
var _icon_btn: Button
var _icon_only: WsIcon
var _fails: PackedStringArray = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=", true, 1)
			if p.size() == 2 and p[0] == "out":
				out_path = p[1]
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_icons()
	_build_kit()
	_run.call_deferred()


## Фон — доски мастерской: тёплый тёмный тон, швы, лёгкий свет лампы сверху (панели полупрозрачные — должны на нём читаться).
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.118, 0.085, 0.062))
	var x := 0.0
	var i := 0
	while x < size.x:
		var w := 150.0 + 40.0 * float(i % 3)
		draw_rect(Rect2(x, 0, w, size.y), Color(1.0, 0.86, 0.66, 0.012 * float(i % 4)))
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0, 0, 0, 0.32), 2.0)
		for g in range(3):
			var gx := x + w * (0.25 + 0.25 * g)
			draw_line(Vector2(gx, 0), Vector2(gx + 6.0 * sin(float(i + g)), size.y), Color(0, 0, 0, 0.06), 1.0)
		x += w
		i += 1
	for b in range(12):
		var t := float(b) / 12.0
		draw_rect(Rect2(0, size.y * t * 0.5, size.x, size.y * 0.5 / 12.0), Color(1.0, 0.72, 0.38, 0.035 * (1.0 - t)))


# ------------------------------------------------------------------ значки

func _build_icons() -> void:
	var title := _label("Значки мастерской", WsStyle.SIZE_M)
	title.position = Vector2(LEFT_X, 18)
	add_child(title)
	var sub := _label("WsIcon · сетка 24, штрих 2, круглые концы · в каждой ячейке 48 px и 24 px", WsStyle.SIZE_XS, true)
	sub.position = Vector2(LEFT_X, 50)
	add_child(sub)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.position = Vector2(LEFT_X, 78)
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	add_child(grid)
	for n in WsIcon.names():
		var cell := PanelContainer.new()
		cell.custom_minimum_size = CELL
		WsStyle.apply_panel(cell, "inset")
		grid.add_child(cell)
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 6)
		cell.add_child(v)
		var h := HBoxContainer.new()
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_theme_constant_override("separation", 10)
		v.add_child(h)
		var big := WsIcon.make(n, 48)
		h.add_child(big)
		var small := WsIcon.make(n, 24)
		small.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(small)
		var l := _label(n, WsStyle.SIZE_XS, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		_big[n] = big
		_small[n] = small
	# проверка самого детектора: неизвестное имя обязано не нарисовать ничего (WARNING «нет значка» ниже — ожидаемый)
	print("ожидаемо: WsIcon предупредит про «no_such_icon» (проверка детектора пустых значков)")
	_unknown = WsIcon.make("no_such_icon", 24)
	_unknown.position = Vector2(-100, -100)
	add_child(_unknown)

	var y := 78.0 + 5.0 * (CELL.y + 8.0) + 10.0
	_caption("Смысловые цвета", Vector2(LEFT_X, y))
	var sem := HBoxContainer.new()
	sem.position = Vector2(LEFT_X, y + 22)
	sem.add_theme_constant_override("separation", 22)
	add_child(sem)
	for s in [["energy", WsStyle.AMBER, "энергия"], ["star_filled", WsStyle.AMBER, "выбрано"], ["check", WsStyle.GREEN, "можно"],
			["warning", WsStyle.RED, "нельзя"], ["delete", WsStyle.RED, "удалить"], ["socket", WsStyle.PALE_BLUE, "разъём"],
			["physics", WsStyle.PALE_BLUE, "центр масс"], ["gear", WsStyle.PURPLE, "NULL-техника"]]:
		var b := HBoxContainer.new()
		b.add_theme_constant_override("separation", 6)
		b.add_child(WsIcon.make(String(s[0]), 32, s[1]))
		var l := _label(String(s[2]), WsStyle.SIZE_XS, true)
		b.add_child(l)
		sem.add_child(b)

	y += 74.0
	_caption("Масштаб: 16 · 20 · 24 · 32 · 48 px", Vector2(LEFT_X, y))
	var sc := HBoxContainer.new()
	sc.position = Vector2(LEFT_X, y + 22)
	sc.add_theme_constant_override("separation", 26)
	add_child(sc)
	for n in ["energy", "mass", "limb", "gear", "mirror"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		for px in [16, 20, 24, 32, 48]:
			var ic := WsIcon.make(n, px)
			ic.size_flags_vertical = Control.SIZE_SHRINK_END
			row.add_child(ic)
		sc.add_child(row)

	# макет верхней панели и строки каталога: значки в кнопках 22 px, как их соберёт workshop_ui
	y += 94.0
	_caption("Верхняя панель и каталог (add_to_button, 22 px)", Vector2(LEFT_X, y))
	var bar := PanelContainer.new()
	bar.position = Vector2(LEFT_X, y + 22 + 46)
	bar.custom_minimum_size = Vector2(952, 0)
	WsStyle.apply_panel(bar, "panel")
	add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	bar.add_child(hb)
	var t := _label("МАСТЕРСКАЯ", WsStyle.SIZE_L)
	hb.add_child(t)
	var help := _button("button", "", "help")
	hb.add_child(help)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(gap)
	_icon_btn = _button("button", "", "undo")
	hb.add_child(_icon_btn)
	_icon_only = _icon_btn.get_meta("ws_icon")
	var redo := _button("button", "", "redo")
	redo.disabled = true
	hb.add_child(redo)
	_text_btn = _button("button", "Сохранить", "save")
	hb.add_child(_text_btn)
	_text_icon = _text_btn.get_meta("ws_icon")
	hb.add_child(_button("button", "Мои сборки", "folder"))

	var chips := HBoxContainer.new()
	chips.position = Vector2(LEFT_X, y + 22)
	chips.add_theme_constant_override("separation", 6)
	add_child(chips)
	var all := _button("chip", "Все", "all", true)
	all.button_pressed = true
	chips.add_child(all)
	chips.add_child(_button("chip", "Избранное", "star", true))
	chips.add_child(_button("chip", "Недавние", "clock", true))
	var fits := _button("chip", "Влезает", "energy", true, WsStyle.AMBER)
	chips.add_child(fits)
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(14, 0)
	chips.add_child(sep)
	for c in [["body", "Тело"], ["limb", "Конечности"], ["hand", "Кисти"]]:
		var tb := _button("tab", String(c[1]), String(c[0]), true)
		tb.button_pressed = c[0] == "limb"
		chips.add_child(tb)


# ------------------------------------------------------------------ стиль

func _build_kit() -> void:
	var y := 18.0
	# главная панель: заклёпки, шкала шрифтов, секция-вкладыш со строками характеристик
	var main := PanelContainer.new()
	main.position = Vector2(RIGHT_X, y)
	main.custom_minimum_size = Vector2(RIGHT_W, 0)
	WsStyle.apply_panel(main, "panel")
	WsStyle.rivets(main)
	add_child(main)
	var mh := HBoxContainer.new()
	mh.add_theme_constant_override("separation", 18)
	main.add_child(mh)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mh.add_child(left)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 10)
	th.add_child(WsIcon.make("gear", 30, WsStyle.BRASS))
	th.add_child(_label("МАСТЕРСКАЯ", WsStyle.SIZE_L))
	left.add_child(th)
	left.add_child(_label("Человек (кукла v3)", WsStyle.SIZE_M))
	left.add_child(_label("panel() · L — табличка, M — имя сборки, S — цифры, XS — клавиши", WsStyle.SIZE_XS, true))
	var keys := HBoxContainer.new()
	keys.add_theme_constant_override("separation", 14)
	for k in ["Ctrl+Z  отменить", "D  дубликат", "M  зеркало", "T  испытать"]:
		keys.add_child(_label(k, WsStyle.SIZE_XS, true))
	left.add_child(keys)
	var inset := PanelContainer.new()
	inset.custom_minimum_size = Vector2(330, 0)
	WsStyle.apply_panel(inset, "inset")
	mh.add_child(inset)
	var st := VBoxContainer.new()
	st.add_theme_constant_override("separation", 4)
	inset.add_child(st)
	for r in [["mass", WsStyle.TEXT_DIM, "Масса", "42.0 кг"], ["energy", WsStyle.AMBER, "Энергия ядра", "87 / 100"],
			["physics", WsStyle.PALE_BLUE, "Центр масс", "виден"], ["limb", WsStyle.TEXT_DIM, "Деталей", "15"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var ic := WsIcon.make(String(r[0]), 20, r[1])
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
		var name_l := _label(String(r[2]), WsStyle.SIZE_S, true)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		row.add_child(_label(String(r[3]), WsStyle.SIZE_S))
		st.add_child(row)

	# матрица кнопок: вид × состояние
	y += 206.0
	var grid := GridContainer.new()
	grid.columns = 6
	grid.position = Vector2(RIGHT_X, y)
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	add_child(grid)
	grid.add_child(_label("", WsStyle.SIZE_XS))
	for s in STATES:
		grid.add_child(_label(String(STATE_TITLES[s]), WsStyle.SIZE_XS, true))
	for kr in KIND_ROWS:
		var kl := _label(String(kr[0]), WsStyle.SIZE_XS, true)
		kl.custom_minimum_size = Vector2(66, 0)
		grid.add_child(kl)
		for s in STATES:
			grid.add_child(_state_button(String(kr[0]), String(s), String(kr[2]), String(kr[1])))

	# ИСПЫТАТЬ — главная кнопка, 4 состояния
	y += 228.0
	_caption("cta — главная кнопка", Vector2(RIGHT_X, y))
	var ctas := HBoxContainer.new()
	ctas.position = Vector2(RIGHT_X, y + 22)
	ctas.add_theme_constant_override("separation", 14)
	add_child(ctas)
	for s in ["normal", "hover", "pressed", "disabled"]:
		var b := _state_button("cta", s, "Испытать  T", "play")
		ctas.add_child(b)

	# кнопки-значки
	y += 92.0
	_caption("Кнопки-значки: обычная · наведение · нажата · выключена", Vector2(RIGHT_X, y))
	var ib := HBoxContainer.new()
	ib.position = Vector2(RIGHT_X, y + 22)
	ib.add_theme_constant_override("separation", 8)
	add_child(ib)
	var ib_states := {"duplicate": "hover", "mirror": "pressed", "redo": "disabled"}
	for n in ["undo", "redo", "duplicate", "mirror", "delete", "physics", "search", "help", "close", "chevron_left",
			"chevron_right", "chevron_down", "gear", "folder"]:
		var st2 := String(ib_states.get(n, "normal"))
		var kind := "danger" if n == "delete" else "button"
		ib.add_child(_state_button(kind, st2, "", n))

	# карточки деталей
	y += 80.0
	_caption("card(): обычная · наведение · выбрана · dim (не влезает по энергии)", Vector2(RIGHT_X, y))
	var cards := HBoxContainer.new()
	cards.position = Vector2(RIGHT_X, y + 24)
	cards.add_theme_constant_override("separation", 18)
	add_child(cards)
	cards.add_child(_card("normal", "limb", "Тонкая рука", 3, 1.1))
	cards.add_child(_card("hover", "head", "Голова-бочка", 5, 2.4))
	cards.add_child(_card("selected", "hand", "Клешня", 4, 0.9))
	cards.add_child(_card("dim", "weapon", "Тяжёлый молот", 14, 6.5))
	var pops := VBoxContainer.new()
	pops.add_theme_constant_override("separation", 10)
	pops.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_child(pops)
	pops.add_child(_popup("socket", WsStyle.PALE_BLUE, "Совместимый разъём", "check", WsStyle.GREEN, "Встанет: плечо на бок, +3 энергии"))
	pops.add_child(_popup("warning", WsStyle.RED, "Не хватает энергии", "energy", WsStyle.RED, "Нужно 14, свободно 13"))

	# поля ввода
	y += 262.0
	_caption("field(): пусто · фокус · только чтение", Vector2(RIGHT_X, y))
	var fields := HBoxContainer.new()
	fields.position = Vector2(RIGHT_X, y + 22)
	fields.add_theme_constant_override("separation", 14)
	add_child(fields)
	var f1 := _field("", "Поиск деталей…")
	fields.add_child(f1)
	var f2 := _field("молот", "")
	fields.add_child(f2)
	var f3 := _field("Человек (кукла v3)", "")
	f3.editable = false
	fields.add_child(f3)
	f2.grab_focus.call_deferred()


# ------------------------------------------------------------------ сборщики

func _label(text: String, font_size: int, dim := false) -> Label:
	var l := Label.new()
	l.text = text
	WsStyle.label(l, font_size, dim)
	return l


func _caption(text: String, pos: Vector2) -> void:
	var l := _label(text, WsStyle.SIZE_XS, true)
	l.position = pos
	add_child(l)


func _button(kind: String, text: String, icon_name: String, toggle := false, col := WsIcon.DEFAULT_COLOR) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	WsStyle.apply_button(b, kind)
	WsIcon.add_to_button(b, icon_name, 22.0, col)
	return b


## Кнопка, застывшая в состоянии: наведение и «нажата» — подменой normal (мыши в тесте нет), выбрана — toggle, выключена — disabled.
func _state_button(kind: String, state: String, text: String, icon_name: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = state == "selected"
	WsStyle.apply_button(b, kind)
	match state:
		"hover", "pressed":
			b.add_theme_stylebox_override("normal", WsStyle.box(kind, state))
			b.add_theme_color_override("font_color", WsStyle.text_color(kind, state))
		"selected":
			b.button_pressed = true
		"disabled":
			b.disabled = true
	WsIcon.add_to_button(b, icon_name, 24.0 if kind == "cta" else 22.0)
	return b


func _card(state: String, icon_name: String, title: String, energy: int, mass: float) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(118, 150)
	p.add_theme_stylebox_override("panel", WsStyle.card(state))
	col.add_child(p)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var dim := state == "dim"
	var ic := WsIcon.make(icon_name, 48, WsStyle.TEXT_FAINT if dim else WsStyle.TEXT)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var t := _label(title, WsStyle.SIZE_S, dim)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(100, 0)
	v.add_child(t)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	v.add_child(row)
	var ec := WsStyle.RED if dim else WsStyle.AMBER
	row.add_child(WsIcon.make("energy", 16, ec))
	var el := _label(str(energy), WsStyle.SIZE_XS)
	el.add_theme_color_override("font_color", ec)
	row.add_child(el)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(6, 0)
	row.add_child(spacer)
	row.add_child(WsIcon.make("mass", 16, WsStyle.TEXT_FAINT if dim else WsStyle.TEXT_DIM))
	row.add_child(_label("%.1f кг" % mass, WsStyle.SIZE_XS, true))
	if dim:
		p.modulate = Color(1, 1, 1, 0.85)
	var cap := _label(state, WsStyle.SIZE_XS, true)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cap)
	return col


func _popup(icon_name: String, icol: Color, title: String, line_icon: String, lcol: Color, line: String) -> Control:
	var p := PanelContainer.new()
	WsStyle.apply_panel(p, "popup")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var ic := WsIcon.make(icon_name, 24, icol)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	h.add_child(_label(title, WsStyle.SIZE_M))
	v.add_child(h)
	var h2 := HBoxContainer.new()
	h2.add_theme_constant_override("separation", 8)
	var ic2 := WsIcon.make(line_icon, 18, lcol)
	ic2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h2.add_child(ic2)
	var l := _label(line, WsStyle.SIZE_S)
	l.add_theme_color_override("font_color", lcol.lerp(WsStyle.TEXT, 0.35))
	h2.add_child(l)
	v.add_child(h2)
	return p


## Поле со значком поиска внутри: значок — ребёнок LineEdit у левого края, текст сдвинут полем стиля.
func _field(text: String, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(280, 40)
	e.focus_mode = Control.FOCUS_ALL
	WsStyle.apply_field(e)
	for sb_name in ["normal", "focus", "read_only"]:
		var sb := e.get_theme_stylebox(sb_name).duplicate() as StyleBox
		sb.content_margin_left = 38
		e.add_theme_stylebox_override(sb_name, sb)
	var ic := WsIcon.make("search", 20, WsStyle.TEXT_DIM)
	ic.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	ic.offset_left = 11
	ic.offset_right = 31
	ic.offset_top = -10
	ic.offset_bottom = 10
	e.add_child(ic)
	return e


# ------------------------------------------------------------------ проверки

func _fail(what: String) -> void:
	_fails.append(what)
	print("  FAIL ", what)


func _run() -> void:
	for i in range(4):
		await get_tree().process_frame
	var grid := Rect2(-0.01, -0.01, WsIcon.GRID + 0.02, WsIcon.GRID + 0.02)
	var names := WsIcon.names()
	for n in REQUIRED:
		if not names.has(n):
			_fail("нет обязательного значка «%s»" % n)
	for n in names:
		var big: WsIcon = _big[n]
		var small: WsIcon = _small[n]
		if big.drawn_primitives <= 0 or small.drawn_primitives <= 0:
			_fail("значок «%s» ничего не рисует" % n)
		elif not grid.encloses(big.drawn_bounds):
			_fail("значок «%s» вылезает за сетку 24: %s" % [n, big.drawn_bounds])
	if _unknown.drawn_primitives != 0:
		_fail("неизвестное имя что-то нарисовало (%d) — детектор пустых значков не работает" % _unknown.drawn_primitives)
	_check_text_button()
	_check_icon_button()
	# ресайз: значок остаётся на левом поле и по центру по вертикали
	_text_btn.custom_minimum_size = Vector2(_text_btn.size.x + 60.0, 64.0)
	for i in range(3):
		await get_tree().process_frame
	_check_text_button("после ресайза ")
	var ok := _fails.is_empty()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(out_path) if img != null else ERR_CANT_CREATE
		print("saved ", ProjectSettings.globalize_path(out_path), " (", err, ")")
		if err != OK:
			_fail("не записался %s" % out_path)
			ok = false
	else:
		print("headless: без PNG, только проверки")
	if ok:
		print("WS ICONS OK n=%d" % names.size())
	else:
		print("WS ICONS FAILED (%d): %s" % [_fails.size(), "; ".join(_fails)])
	get_tree().quit(0 if ok else 1)


func _margins(b: Button) -> Vector4:
	var sb := b.get_theme_stylebox("normal")
	return Vector4(sb.get_margin(SIDE_LEFT), sb.get_margin(SIDE_TOP), sb.get_margin(SIDE_RIGHT), sb.get_margin(SIDE_BOTTOM))


func _check_text_button(prefix := "") -> void:
	var b := _text_btn
	var r := _text_icon.get_rect()
	var m := _margins(b)
	var px := _text_icon.custom_minimum_size.x
	if absf(r.position.x - floorf(m.x)) > 0.5:
		_fail("%sзначок кнопки с текстом не на левом поле: x=%.1f, поле %.1f" % [prefix, r.position.x, m.x])
	var cy := m.y + (b.size.y - m.y - m.w) * 0.5
	if absf(r.get_center().y - cy) > 1.0:
		_fail("%sзначок не по центру по вертикали: %.1f против %.1f" % [prefix, r.get_center().y, cy])
	var font := b.get_theme_font("font")
	var fs := b.get_theme_font_size("font_size")
	var tw := font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var need := m.x + px + float(b.get_theme_constant("h_separation")) + tw + m.z
	if b.get_minimum_size().x + 1.0 < need:
		_fail("%sкнопка не резервирует место под значок и текст: %.1f < %.1f" % [prefix, b.get_minimum_size().x, need])
	if r.size.x != px or r.size.y != px:
		_fail("%sразмер значка в кнопке %s, ждали %d" % [prefix, r.size, px])


func _check_icon_button() -> void:
	var b := _icon_btn
	var r := _icon_only.get_rect()
	var m := _margins(b)
	var c := Vector2(m.x + (b.size.x - m.x - m.z) * 0.5, m.y + (b.size.y - m.y - m.w) * 0.5)
	if r.get_center().distance_to(c) > 1.0:
		_fail("значок кнопки без текста не по центру: %s против %s" % [r.get_center(), c])
