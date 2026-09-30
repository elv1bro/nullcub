## Полка вкладки «Покраска» (docs/plan-demo/BODY_PAINT.md §1, §6): строится кодом (workshop_ui._build_shelf, вкладка с tool "paint"),
## всё состояние — у WorkshopPaint (ctl.paint), refresh() — по paint.changed / ctl.changed.
##   • инструменты — 8 плашек с пиктограммами (краска пиктограмм — текущий цвет);
##   • цвет: большая плашка (клик — ColorPicker), второй цвет (клик — поменять местами, X), палитра 20 (ЛКМ — цвет, ПКМ — второй),
##     последние 8;
##   • настройки инструмента: баллончик — размер / нажим / жёсткость, ластик — размер / сила, заливка — плотность; раскраски — 6 плиток
##     с превью (настоящий PaintLayer.pattern на плоской плашке) и «Своими цветами»; трафарет — сетка масок цветом краски и размер;
##     наклейка — размер, мои картинки (миниатюры user://kit_images, ПКМ — удалить) и «Импорт…» (FileDialog с нативным диалогом,
##     импорт в потоке — окно не замирает); фото — те же картинки и «Снять фото»;
##   • «Симметрия», «Стенд 0°» (поворот на 90°), «Очистить деталь» (последнюю правленную и пару), «Очистить всё».
extends VBoxContainer

## Ширина полки: левая панель 440 − поля 2 × 16 − полоса прокрутки ≈ 380.
const W := 350.0   # левая колонка 400 px (компактный экран, WORKSHOP_V3.md §6)
const GOLD := Color(1.0, 0.8, 0.3)
const INK := Color(0.96, 0.92, 0.84)
const DIM := Color(0.8, 0.76, 0.7)
const BG := Color(0.11, 0.09, 0.075, 0.95)
const BG_HOVER := Color(0.17, 0.13, 0.1, 0.97)
const BG_SEL := Color(0.26, 0.19, 0.08, 0.97)
const EDGE := Color(0.36, 0.26, 0.16)
const TOOL_SHORT := {
	"spray": "Баллончик", "erase": "Ластик", "fill": "Заливка", "pattern": "Раскраски", "pick": "Пипетка", "stencil": "Трафарет",
	"sticker": "Наклейка", "face": "Фото",
}
const TOOL_TIPS := {
	"spray": "Баллончик: зажми ЛКМ на кукле — краска ложится напылением.\nКолесо / [ ] — размер, Alt+клик — пипетка",
	"erase": "Ластик: стирает краску баллончика и раскрасок",
	"fill": "Заливка: клик — вся деталь в цвет (нажим = плотность)",
	"pattern": "Раскраски: полосы, камуфляж, пламя, горошек, градиент, граффити.\nКлик — деталь, Shift+клик — вся кукла",
	"pick": "Пипетка: взять цвет с детали",
	"stencil": "Трафарет: чёткая фигура цветом краски.\nКолесо / [ ] — размер, Q / E — поворот, тащи — переставить, ПКМ — снять",
	"sticker": "Наклейка: любая картинка с диска — «Импорт…» или перетащи файл в окно.\nКолесо / [ ] — размер, Q / E — поворот",
	"face": "Фото на голову: картинка на плашку лица",
}
const PATTERN_PREVIEW_BOX := AABB(Vector3(-0.16, -0.1, -0.012), Vector3(0.32, 0.2, 0.024))

var ctl: WorkshopBuild
var paint: WorkshopPaint
var _tool_buttons: Dictionary = {}       # tool -> ToolTile
var _cur: Swatch
var _sec: Swatch
var _palette: Array = []                 # [Swatch]
var _recent_box: HBoxContainer
var _recent_sig := ""
var _options: VBoxContainer
var _opt_tool := "?"
var _tiles: Dictionary = {}              # ключ плитки (узор / трафарет / id картинки) -> Tile
var _sliders: Dictionary = {}            # ключ -> [HSlider, Label, Callable формат]
var _info: Label
var _own: Button
var _sym: Button
var _turn: Button
var _clear_part: Button
var _clear_all: Button
var _images_sig := ""
var _pattern_key := ""
var _pattern_dirty := false
var _pattern_t := 0.0

static var _pattern_tex: Dictionary = {}  # kind|цвета -> ImageTexture
static var _knob: ImageTexture


func setup(c: WorkshopBuild) -> void:
	ctl = c
	paint = c.paint
	name = "PaintPanel"
	custom_minimum_size = Vector2(W, 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 7)
	add_child(_caption("ИНСТРУМЕНТ"))
	var tools := GridContainer.new()
	tools.columns = 4
	tools.add_theme_constant_override("h_separation", 6)
	tools.add_theme_constant_override("v_separation", 6)
	add_child(tools)
	for t in WorkshopPaint.TOOLS:
		var b := ToolTile.new()
		b.setup(String(t), String(TOOL_SHORT[t]), String(TOOL_TIPS[t]))
		b.chosen.connect(func(id: String) -> void: paint.set_tool(id))
		tools.add_child(b)
		_tool_buttons[t] = b
	# цвет
	add_child(_caption("ЦВЕТ   ·   ЛКМ — цвет, ПКМ — второй"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	_cur = Swatch.new()
	_cur.setup(paint.color, Vector2(84, 44), 8)
	_cur.tooltip_text = "Цвет краски — клик: свой цвет (круг)"
	_cur.chosen.connect(func(_c: Color, _b: int) -> void: _open_picker())
	row.add_child(_cur)
	_sec = Swatch.new()
	_sec.setup(paint.color2, Vector2(46, 30), 6)
	_sec.size_flags_vertical = Control.SIZE_SHRINK_END
	_sec.tooltip_text = "Второй цвет (раскраски «своими цветами») — клик: поменять местами  [X]"
	_sec.chosen.connect(func(_c: Color, _b: int) -> void: paint.swap_colors())
	row.add_child(_sec)
	var own_pick := _button("СВОЙ ЦВЕТ…", 17, 42)
	own_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	own_pick.pressed.connect(_open_picker)
	row.add_child(own_pick)
	var pal := GridContainer.new()
	pal.columns = 10
	pal.add_theme_constant_override("h_separation", 4)
	pal.add_theme_constant_override("v_separation", 4)
	add_child(pal)
	for col in WorkshopPaint.PALETTE:
		var sw := Swatch.new()
		sw.setup(col, Vector2(34, 27), 5)
		sw.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # сетки тянутся на всю ширину полки
		sw.chosen.connect(_on_palette)
		pal.add_child(sw)
		_palette.append(sw)
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 4)
	add_child(rrow)
	var rl := Label.new()
	rl.text = "Недавние"
	rl.custom_minimum_size = Vector2(70, 0)
	rl.add_theme_font_size_override("font_size", 16)
	rl.add_theme_color_override("font_color", DIM)
	rrow.add_child(rl)
	_recent_box = HBoxContainer.new()
	_recent_box.add_theme_constant_override("separation", 4)
	rrow.add_child(_recent_box)
	# настройки инструмента
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	add_child(sep)
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 6)
	add_child(_options)
	var sep2 := HSeparator.new()
	sep2.add_theme_constant_override("separation", 4)
	add_child(sep2)
	# симметрия, поворот, очистка
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 8)
	add_child(trow)
	_sym = _button("СИММЕТРИЯ: ВКЛ", 16, 42)
	_sym.clip_text = true
	_sym.toggle_mode = true
	_sym.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sym.tooltip_text = "Краска и наклейки — сразу на обе стороны куклы"
	_sym.add_theme_stylebox_override("pressed", _gold())
	_sym.toggled.connect(func(on: bool) -> void: paint.set_symmetry(on))
	trow.add_child(_sym)
	_turn = _button("СТЕНД 0°  [R]", 16, 42)
	_turn.clip_text = true
	_turn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_turn.tooltip_text = "Повернуть стенд на 90° — красить бока и спину (R, Shift+R — назад)"
	_turn.pressed.connect(func() -> void: paint.turn_stand(1))
	trow.add_child(_turn)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 8)
	add_child(crow)
	_clear_part = _button("ОЧИСТИТЬ ДЕТАЛЬ", 15, 40)
	_clear_part.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clear_part.clip_text = true
	_clear_part.pressed.connect(func() -> void: paint.clear_part())
	crow.add_child(_clear_part)
	_clear_all = _button("ОЧИСТИТЬ ВСЁ", 15, 40)
	_clear_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clear_all.tooltip_text = "Снять всю краску, наклейки и фото (Ctrl+Z вернёт)"
	_clear_all.pressed.connect(func() -> void: paint.clear_all())
	crow.add_child(_clear_all)
	paint.changed.connect(refresh)
	paint.images_changed.connect(func() -> void:
		_images_sig = ""
		refresh())
	ctl.changed.connect(refresh)
	refresh()


func _process(delta: float) -> void:
	_pattern_t += delta
	if _pattern_dirty and _pattern_t > 0.2 and _opt_tool == "pattern":
		_pattern_dirty = false
		_pattern_t = 0.0
		_update_pattern_previews()


# ------------------------------------------------------------------ обновление

func refresh() -> void:
	if paint == null or not is_inside_tree():
		return
	for t in _tool_buttons:
		(_tool_buttons[t] as ToolTile).set_state(String(t) == paint.tool, paint.color)
	_cur.set_colour(paint.color)
	_sec.set_colour(paint.color2)
	for sw in _palette:
		(sw as Swatch).set_selected((sw as Swatch).c.is_equal_approx(paint.color))
	var rs := ",".join(PackedStringArray(paint.recent.map(func(x: Variant) -> String: return (x as Color).to_html(false))))
	if rs != _recent_sig:
		_recent_sig = rs
		for ch in _recent_box.get_children():
			ch.queue_free()
		for col in paint.recent:
			var sw := Swatch.new()
			sw.setup(col, Vector2(32, 24), 5)
			sw.chosen.connect(_on_palette)
			_recent_box.add_child(sw)
		if paint.recent.is_empty():
			var l := Label.new()
			l.text = "— красишь, и цвет появится тут"
			l.add_theme_font_size_override("font_size", 15)
			l.add_theme_color_override("font_color", Color(0.62, 0.58, 0.52))
			_recent_box.add_child(l)
	for ch in _recent_box.get_children():
		if ch is Swatch:
			(ch as Swatch).set_selected((ch as Swatch).c.is_equal_approx(paint.color))
	if _opt_tool != paint.tool:
		_build_options()
	else:
		_update_options()
	_sym.set_pressed_no_signal(paint.symmetry)
	_sym.text = "СИММЕТРИЯ: ВКЛ" if paint.symmetry else "СИММЕТРИЯ: ВЫКЛ"
	_turn.text = "СТЕНД %d°  [R]" % paint.turn_degrees()
	var fu := paint.focus_uid
	var has_focus := fu != "" and not CraftEdit.find(ctl.blueprint, fu).is_empty() and paint.has_paint(fu)
	_clear_part.disabled = not has_focus
	_clear_part.text = ("ОЧИСТИТЬ: %s" % ctl.uid_title("body", fu).get_slice(" (", 0).to_upper()) if has_focus else "ОЧИСТИТЬ ДЕТАЛЬ"
	_clear_part.tooltip_text = "Снять краску, наклейки и фото с последней детали, которую красил (и с её пары при симметрии)"
	_clear_all.disabled = not paint.has_paint()


func _on_palette(c: Color, button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		paint.set_color2(c)
	else:
		paint.set_color(c)


# ------------------------------------------------------------------ настройки инструмента

func _build_options() -> void:
	_opt_tool = paint.tool
	for ch in _options.get_children():
		ch.queue_free()
	_tiles.clear()
	_sliders.clear()
	_info = null
	_own = null
	match paint.tool:
		"":
			_options.add_child(_note("Выбери инструмент. Краска — только вид: масса и удар — у материала. Цвет игрока (пояса, шары суставов) не закрашивается."))
		"spray":
			_options.add_child(_caption("БАЛЛОНЧИК"))
			_add_size_slider()
			_add_slider("pressure", "Нажим", 5, 100, 5, paint.pressure * 100.0, func(v: float) -> String: return "%d%%" % roundi(v),
				func(v: float) -> void: paint.set_pressure(v / 100.0))
			_add_slider("hardness", "Жёсткость", 0, 100, 5, paint.hardness * 100.0,
				func(v: float) -> String: return "мягкий" if v < 25 else ("%d%%" % roundi(v) if v < 80 else "чёткий"),
				func(v: float) -> void: paint.set_hardness(v / 100.0))
			_options.add_child(_note("Зажми ЛКМ и веди по кукле. Колесо / [ ] — размер, Alt+клик — пипетка, X — второй цвет."))
		"erase":
			_options.add_child(_caption("ЛАСТИК"))
			_add_size_slider()
			_add_slider("pressure", "Сила", 5, 100, 5, paint.pressure * 100.0, func(v: float) -> String: return "%d%%" % roundi(v),
				func(v: float) -> void: paint.set_pressure(v / 100.0))
			_options.add_child(_note("Стирает краску баллончика и раскрасок. Наклейки снимает ПКМ трафаретом или наклейкой."))
		"fill":
			_options.add_child(_caption("ЗАЛИВКА"))
			_add_slider("pressure", "Плотность", 5, 100, 5, paint.pressure * 100.0, func(v: float) -> String: return "%d%%" % roundi(v),
				func(v: float) -> void: paint.set_pressure(v / 100.0))
			_options.add_child(_note("Клик по детали — вся деталь в цвет (с симметрией — и парная). Неполная плотность — тонировка поверх."))
		"pattern":
			_options.add_child(_caption("РАСКРАСКИ   ·   SHIFT+КЛИК — ВСЯ КУКЛА"))
			var g := GridContainer.new()
			g.columns = 3
			g.add_theme_constant_override("h_separation", 6)
			g.add_theme_constant_override("v_separation", 6)
			_options.add_child(g)
			for k in WorkshopPaint.PATTERNS:
				var t := Tile.new()
				t.setup(String(k), null, Vector2(120, 86), String(WorkshopPaint.PATTERN_TITLES[k]))
				t.cover = true
				t.chosen.connect(func(key: String, _b: int) -> void: paint.set_pattern_kind(key))
				g.add_child(t)
				_tiles[String(k)] = t
			_own = _button("СВОИМИ ЦВЕТАМИ", 17, 38)
			_own.toggle_mode = true
			_own.add_theme_stylebox_override("pressed", _gold())
			_own.tooltip_text = "Раскраска цветом и вторым цветом вместо родной палитры узора"
			_own.toggled.connect(func(on: bool) -> void: paint.set_own_colors(on))
			_options.add_child(_own)
			_options.add_child(_note("Клик по детали — узор на неё (и пару). Ещё клик — новый вариант. Раскраска заменяет краску детали; баллончик — поверх."))
			_pattern_key = ""
			_update_pattern_previews()
		"pick":
			_options.add_child(_caption("ПИПЕТКА"))
			_options.add_child(_note("Клик по детали — её цвет в кисть (краска, а где её нет — цвет материала). Потом — снова прежний инструмент. Alt+клик баллончиком — то же самое."))
		"stencil":
			_options.add_child(_caption("ТРАФАРЕТ — ЦВЕТОМ КРАСКИ"))
			_add_sticker_slider()
			var g2 := GridContainer.new()
			g2.columns = 5
			g2.add_theme_constant_override("h_separation", 5)
			g2.add_theme_constant_override("v_separation", 5)
			_options.add_child(g2)
			for nm in KitImages.stencils():
				var t2 := Tile.new()
				t2.setup(String(nm), KitImages.texture(KitImages.STENCIL_PREFIX + String(nm)), Vector2(71, 58), "")
				t2.tooltip_text = String(WorkshopPaint.STENCIL_TITLES.get(nm, String(nm).replace("digit_", "цифра ")))
				t2.chosen.connect(func(key: String, _b: int) -> void: paint.set_stencil(key))
				g2.add_child(t2)
				_tiles[String(nm)] = t2
			_info = _note("")
			_options.add_child(_info)
		"sticker", "face":
			_options.add_child(_caption("МОИ КАРТИНКИ   ·   ПКМ — УДАЛИТЬ" if paint.tool == "sticker" else "ФОТО НА ГОЛОВУ — ВЫБЕРИ КАРТИНКУ"))
			if paint.tool == "sticker":
				_add_sticker_slider()
			var ib := HBoxContainer.new()
			ib.add_theme_constant_override("separation", 8)
			_options.add_child(ib)
			var imp := _button("ИМПОРТ…", 20, 44)
			imp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			imp.tooltip_text = "Картинка с диска: png, jpg, webp, bmp, tga, svg (большие уменьшаются до 512 px; HEIC с iPhone — сохрани как JPG)"
			imp.pressed.connect(open_import)
			ib.add_child(imp)
			if paint.tool == "face":
				var cf := _button("СНЯТЬ ФОТО", 18, 44)
				cf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				cf.pressed.connect(func() -> void: paint.clear_face())
				ib.add_child(cf)
			var g3 := GridContainer.new()
			g3.name = "Images"
			g3.columns = 4
			g3.add_theme_constant_override("h_separation", 6)
			g3.add_theme_constant_override("v_separation", 6)
			_options.add_child(g3)
			_images_sig = ""
			_fill_images(g3)
			_info = _note("")
			_options.add_child(_info)
	_update_options()


func _update_options() -> void:
	# слайдеры — за состоянием (колесо, [ ], жесты трекпада меняют размер мимо полки)
	for key in _sliders:
		var e: Array = _sliders[key]
		var v := _slider_value(String(key))
		(e[0] as HSlider).set_value_no_signal(v)
		(e[1] as Label).text = (e[2] as Callable).call(v)
	match paint.tool:
		"pattern":
			for k in _tiles:
				(_tiles[k] as Tile).set_selected(String(k) == paint.pattern_kind)
			if _own != null:
				_own.set_pressed_no_signal(paint.own_colors)
			var key := _pattern_colors_key()
			if key != _pattern_key:
				_pattern_dirty = true
		"stencil":
			var bg := Color(0.78, 0.74, 0.68, 0.97) if paint.color.get_luminance() < 0.22 else BG
			for k in _tiles:
				var t := _tiles[k] as Tile
				t.tint = paint.color
				t.bg = bg
				t.set_selected(String(k) == paint.stencil)
				t.queue_redraw()
			if _info != null:
				_info.text = "Клик по кукле — поставить (поворот %d°). Колесо / [ ] — размер, Q / E — поворот. Над наклейкой: тащи — переставить, ПКМ — снять. Пояса и шары суставов (цвет игрока) наклейка не закрывает." \
					% roundi(paint.sticker_rot)
		"sticker", "face":
			var g := _options.get_node_or_null("Images") as GridContainer
			if g != null:
				_fill_images(g)
			for k in _tiles:
				(_tiles[k] as Tile).set_selected(String(k) == paint.image)
			if _info != null:
				if paint.tool == "face":
					_info.text = "Клик по картинке — фото на лицо головы (клик по голове — то же). Перетащи файл в окно — тоже."
				elif KitImages.list_images().is_empty():
					_info.text = "Картинок пока нет: «Импорт…» или просто перетащи файл в окно игры."
				else:
					_info.text = "Выбери картинку и кликни по кукле (поворот %d°). Колесо / [ ], Q / E, ПКМ — как у трафарета. Файл можно перетащить в окно; ПКМ по картинке — удалить её." \
						% roundi(paint.sticker_rot)


func _fill_images(g: GridContainer) -> void:
	var ids := KitImages.list_images()
	var sig := ",".join(ids)
	if sig == _images_sig:
		return
	_images_sig = sig
	for ch in g.get_children():
		ch.queue_free()
	for k in _tiles.keys():
		_tiles.erase(k)
	for id in ids:
		var t := Tile.new()
		t.setup(String(id), KitImages.texture(String(id)), Vector2(89, 89), "")
		t.tooltip_text = "ЛКМ — выбрать, ПКМ — удалить из «Моих картинок»"
		t.chosen.connect(func(key: String, b: int) -> void:
			if b == MOUSE_BUTTON_RIGHT:
				_ask_delete(key)
			else:
				paint.set_image(key))
		g.add_child(t)
		_tiles[String(id)] = t


func _add_size_slider() -> void:
	_add_slider("size", "Размер", WorkshopPaint.SIZE_CM.x, WorkshopPaint.SIZE_CM.y, 0.5, paint.size_cm,
		func(v: float) -> String: return "%s см" % String.num(snappedf(v, 0.5)),
		func(v: float) -> void: paint.set_size_cm(v))


## Размер следующей наклейки / трафарета (большая сторона): на трекпаде без колеса — главный способ.
func _add_sticker_slider() -> void:
	_add_slider("sticker", "Размер", WorkshopPaint.STICKER_CM.x, WorkshopPaint.STICKER_CM.y, 1.0, paint.sticker_cm,
		func(v: float) -> String: return "%d см" % roundi(v),
		func(v: float) -> void: paint.set_sticker_cm(v))


func _slider_value(key: String) -> float:
	match key:
		"size":
			return paint.size_cm
		"sticker":
			return paint.sticker_cm
		"hardness":
			return paint.hardness * 100.0
	return paint.pressure * 100.0


## Слайдер одной строкой: подпись · ползунок · значение.
func _add_slider(key: String, title: String, lo: float, hi: float, step: float, value: float, fmt: Callable, apply: Callable) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = title
	l.custom_minimum_size = Vector2(104, 0)
	l.clip_text = true
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", DIM)
	box.add_child(l)
	var v := Label.new()
	v.text = fmt.call(value)
	v.custom_minimum_size = Vector2(70, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_theme_font_size_override("font_size", 17)
	v.add_theme_color_override("font_color", GOLD)
	var s := HSlider.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(0, 26)
	s.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_slider(s)
	s.value_changed.connect(func(x: float) -> void:
		apply.call(x)
		v.text = fmt.call(x))
	box.add_child(s)
	box.add_child(v)
	_options.add_child(box)
	_sliders[key] = [s, v, fmt]


# ------------------------------------------------------------------ раскраски: превью

func _pattern_colors_key() -> String:
	return "%s|%s" % [paint.color.to_html(false), paint.color2.to_html(false)] if paint.own_colors else "palette"


## Превью узоров: настоящий PaintLayer.pattern на плоской плашке 32 × 20 см (передний срез), кэш по виду и цветам.
func _update_pattern_previews() -> void:
	_pattern_key = _pattern_colors_key()
	var cols: Array = [paint.color, paint.color2] if paint.own_colors else []
	for k in _tiles:
		var t := _tiles[k] as Tile
		t.tex = pattern_preview(String(k), cols)
		t.queue_redraw()


static func pattern_preview(kind: String, cols: Array) -> Texture2D:
	var key := kind + "|" + ",".join(PackedStringArray(cols.map(func(c: Variant) -> String: return (c as Color).to_html(false))))
	if _pattern_tex.has(key):
		return _pattern_tex[key]
	var layer := PaintLayer.for_aabb(PATTERN_PREVIEW_BOX)
	layer.pattern(kind, cols, 7, Vector3.UP)
	var img := Image.create(layer.res.x, layer.res.y, false, Image.FORMAT_RGBA8)
	var z := layer.res.z - 1
	var bg := Color(0.36, 0.27, 0.19)
	for y in layer.res.y:
		for x in layer.res.x:
			var c := layer.cell_color(x, layer.res.y - 1 - y, z)
			img.set_pixel(x, y, bg.lerp(Color(c.r, c.g, c.b), c.a))
	var tex := ImageTexture.create_from_image(img)
	_pattern_tex[key] = tex
	return tex


# ------------------------------------------------------------------ импорт, свой цвет

## Нативный диалог выбора картинок (несколько сразу).
func open_import() -> void:
	var fd := FileDialog.new()
	fd.use_native_dialog = true
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	fd.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.jfif, *.jpe, *.webp, *.bmp, *.tga, *.svg ; Картинки"])
	fd.title = "Импорт картинки"
	fd.files_selected.connect(func(paths: PackedStringArray) -> void:
		_imported(paths)
		fd.queue_free())
	fd.file_selected.connect(func(path: String) -> void:
		_imported(PackedStringArray([path]))
		fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered_ratio(0.6)


## Выбранные в диалоге файлы → KitImages (в потоке: окно не замирает на больших фото); последняя картинка — текущая (у фото — сразу
## на голову).
func _imported(paths: PackedStringArray) -> void:
	paint.import_files_async(paths, func(ids: PackedStringArray) -> void:
		if ids.is_empty():
			return
		if paint.tool == "face":
			paint.set_face_image(ids[ids.size() - 1])
		else:
			paint.set_image(ids[ids.size() - 1]))


## ПКМ по картинке: удалить её из «Моих картинок» — с подтверждением (на кукле — нельзя, WorkshopPaint.delete_image).
func _ask_delete(id: String) -> void:
	if paint.image_used(id):
		paint.delete_image(id)   # откажет с подсказкой
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "Удалить картинку"
	dlg.dialog_text = "Удалить картинку из «Моих картинок»?\nВ сохранённых сборках с ней наклейка тоже пропадёт."
	dlg.ok_button_text = "Удалить"
	dlg.cancel_button_text = "Оставить"
	dlg.confirmed.connect(func() -> void:
		paint.delete_image(id)
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


func _open_picker() -> void:
	var pop := PopupPanel.new()
	pop.name = "ColorPopup"
	var cp := ColorPicker.new()
	cp.color = paint.color
	cp.edit_alpha = false
	cp.edit_intensity = false   # ползунок яркости даёт компоненты > 1 (слой краски их зажимает, но цвет на полке врал бы)
	cp.presets_visible = false
	cp.can_add_swatches = false
	cp.custom_minimum_size = Vector2(300, 0)
	cp.color_changed.connect(func(c: Color) -> void: paint.set_color(c, false))
	pop.add_child(cp)
	pop.popup_hide.connect(func() -> void:
		paint.remember_color(paint.color)
		pop.queue_free())
	add_child(pop)
	var r := _cur.get_global_rect()
	pop.popup(Rect2i(Vector2i(int(r.end.x + 16.0), int(maxf(r.position.y - 160.0, 20.0))), Vector2i(320, 0)))


# ------------------------------------------------------------------ мелочи

static func _caption(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.theme_type_variation = &"SmallCaps"
	l.clip_text = true
	return l


static func _note(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(W - 8.0, 0)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", DIM)
	l.add_theme_constant_override("line_spacing", -2)
	return l


static func _button(t: String, fs: int, h: float) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_font_size_override("font_size", fs)
	return b


func _gold() -> StyleBox:
	var ui := ctl.ui
	var cb: Variant = ui.get("control_button") if ui != null else null
	if cb is Button:
		return (cb as Button).get_theme_stylebox("pressed")
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_SEL
	return sb


static func _style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.05, 0.045, 0.04, 0.95)
	track.set_corner_radius_all(4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	track.set_border_width_all(1)
	track.border_color = EDGE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.95, 0.68, 0.28)
	fill.set_corner_radius_all(4)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	var fill_hi := fill.duplicate() as StyleBoxFlat
	fill_hi.bg_color = Color(1.0, 0.8, 0.4)
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill_hi)
	s.add_theme_icon_override("grabber", _knob_tex())
	s.add_theme_icon_override("grabber_highlight", _knob_tex())
	s.add_theme_icon_override("grabber_disabled", _knob_tex())


## Ручка слайдера: светлый кружок с тёмной обводкой (22 px, сглаженный).
static func _knob_tex() -> ImageTexture:
	if _knob != null:
		return _knob
	var n := 22
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n, n) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a := clampf(10.5 - d, 0.0, 1.0)
			var col := Color(0.2, 0.12, 0.05) if d > 8.0 else Color(1.0, 0.93, 0.8)
			col.a = a
			img.set_pixel(x, y, col)
	_knob = ImageTexture.create_from_image(img)
	return _knob


# ================================================================== плашки

## Плашка инструмента: пиктограмма (краска — текущий цвет) и подпись; выбранная — золотая рамка.
class ToolTile extends Control:
	signal chosen(id: String)
	var id := ""
	var title := ""
	var selected := false
	var accent := Color.RED
	var _hover := false

	func setup(tool_id: String, t: String, tip: String) -> void:
		id = tool_id
		title = t
		tooltip_text = tip
		custom_minimum_size = Vector2(89, 68)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func set_state(sel: bool, col: Color) -> void:
		if sel == selected and col.is_equal_approx(accent):
			return
		selected = sel
		accent = col
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER:
			_hover = true
			queue_redraw()
		elif what == NOTIFICATION_MOUSE_EXIT:
			_hover = false
			queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			chosen.emit(id)
			accept_event()

	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = BG_SEL if selected else (BG_HOVER if _hover else BG)
		sb.set_corner_radius_all(9)
		sb.set_border_width_all(4 if selected else 2)
		sb.border_color = GOLD if selected else (Color(0.95, 0.75, 0.4) if _hover else EDGE)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		var s := 38.0
		var o := Vector2((size.x - s) * 0.5, 5.0)
		var ink := Color(0.97, 0.94, 0.87) if selected or _hover else Color(0.86, 0.82, 0.75)
		var acc := accent if accent.get_luminance() > 0.08 else Color(0.35, 0.35, 0.35)
		PaintIcon.draw(self, id, o, s, ink, acc)
		var f := get_theme_font("font", "Label")
		draw_string(f, Vector2(0, size.y - 7.0), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14,
			GOLD if selected else ink)


## Плашка цвета: ЛКМ / ПКМ — chosen(цвет, кнопка); выбранная — золотое кольцо.
class Swatch extends Control:
	signal chosen(c: Color, button: int)
	var c := Color.WHITE
	var selected := false
	var radius := 6
	var _hover := false

	func setup(col: Color, sz: Vector2, r: int) -> void:
		c = col
		radius = r
		custom_minimum_size = sz
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if tooltip_text == "":
			tooltip_text = "#" + col.to_html(false)

	func set_colour(col: Color) -> void:
		if not col.is_equal_approx(c):
			c = col
			queue_redraw()

	func set_selected(on: bool) -> void:
		if on != selected:
			selected = on
			queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER:
			_hover = true
			queue_redraw()
		elif what == NOTIFICATION_MOUSE_EXIT:
			_hover = false
			queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			var b := (e as InputEventMouseButton).button_index
			if b == MOUSE_BUTTON_LEFT or b == MOUSE_BUTTON_RIGHT:
				chosen.emit(c, b)
				accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(radius)
		sb.set_border_width_all(3 if selected else 2)
		sb.border_color = GOLD if selected else (Color(1, 1, 1, 0.85) if _hover else c.darkened(0.6))
		if selected:
			sb.expand_margin_left = 2
			sb.expand_margin_right = 2
			sb.expand_margin_top = 2
			sb.expand_margin_bottom = 2
		draw_style_box(sb, r)


## Плитка сетки (узор, трафарет, картинка): текстура по центру (cover — заполнить, иначе вписать), подпись снизу; выбранная — золото.
class Tile extends Control:
	signal chosen(key: String, button: int)
	var key := ""
	var tex: Texture2D
	var tint := Color.WHITE
	var bg := BG
	var title := ""
	var cover := false
	var selected := false
	var _hover := false

	func setup(k: String, t: Texture2D, sz: Vector2, ttl: String) -> void:
		key = k
		tex = t
		title = ttl
		custom_minimum_size = sz
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func set_selected(on: bool) -> void:
		if on != selected:
			selected = on
			queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER:
			_hover = true
			queue_redraw()
		elif what == NOTIFICATION_MOUSE_EXIT:
			_hover = false
			queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			var b := (e as InputEventMouseButton).button_index
			if b == MOUSE_BUTTON_LEFT or b == MOUSE_BUTTON_RIGHT:
				chosen.emit(key, b)
				accept_event()

	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg if not _hover or selected else bg.lightened(0.08)
		sb.set_corner_radius_all(8)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		var pad := 5.0
		var th := 20.0 if title != "" else 0.0
		var area := Rect2(pad, pad, size.x - pad * 2.0, size.y - pad * 2.0 - th)
		if tex != null and tex.get_height() > 0:
			var a := float(tex.get_width()) / float(tex.get_height())
			var r := area
			if cover:
				draw_texture_rect_region(tex, area, _cover_src(tex, area.size.x / maxf(area.size.y, 1.0)), tint)
			else:
				if a > area.size.x / area.size.y:
					r.size.y = area.size.x / a
				else:
					r.size.x = area.size.y * a
				r.position = area.position + (area.size - r.size) * 0.5
				draw_texture_rect(tex, r, false, tint)
		if title != "":
			var f := get_theme_font("font", "Label")
			draw_string(f, Vector2(0, size.y - 7.0), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, GOLD if selected else INK)
		var fr := StyleBoxFlat.new()
		fr.draw_center = false
		fr.set_corner_radius_all(8)
		fr.set_border_width_all(4 if selected else 2)
		fr.border_color = GOLD if selected else (Color(0.95, 0.75, 0.4) if _hover else EDGE)
		draw_style_box(fr, Rect2(Vector2.ZERO, size))

	static func _cover_src(t: Texture2D, aspect: float) -> Rect2:
		var w := float(t.get_width())
		var h := float(t.get_height())
		if w / h > aspect:
			var nw := h * aspect
			return Rect2((w - nw) * 0.5, 0, nw, h)
		var nh := w / aspect
		return Rect2(0, (h - nh) * 0.5, w, nh)


## Пиктограммы инструментов: рисунок в квадрате o..o+s (координаты 0..1), ink — контур / корпус, acc — краска.
class PaintIcon:
	static func draw(ci: CanvasItem, tool: String, o: Vector2, s: float, ink: Color, acc: Color) -> void:
		var dark := ink.darkened(0.55)
		match tool:
			"spray":
				_rect(ci, o, s, 0.3, 0.36, 0.62, 0.95, ink)
				_rect(ci, o, s, 0.3, 0.52, 0.62, 0.68, acc)
				_rect(ci, o, s, 0.35, 0.24, 0.57, 0.36, dark)
				_rect(ci, o, s, 0.42, 0.14, 0.52, 0.24, ink)
				for d in [[0.7, 0.16, 0.05], [0.8, 0.24, 0.04], [0.68, 0.3, 0.035], [0.88, 0.1, 0.03], [0.9, 0.32, 0.028], [0.78, 0.07, 0.025]]:
					ci.draw_circle(_p(o, s, d[0], d[1]), s * float(d[2]), acc)
			"erase":
				ci.draw_colored_polygon(PackedVector2Array([_p(o, s, 0.16, 0.62), _p(o, s, 0.5, 0.28), _p(o, s, 0.84, 0.62),
					_p(o, s, 0.5, 0.96)]), ink)
				ci.draw_colored_polygon(PackedVector2Array([_p(o, s, 0.16, 0.62), _p(o, s, 0.33, 0.45), _p(o, s, 0.67, 0.79),
					_p(o, s, 0.5, 0.96)]), Color(1.0, 0.55, 0.62))
				ci.draw_line(_p(o, s, 0.06, 0.98), _p(o, s, 0.42, 0.98), acc, s * 0.06, true)
			"fill":
				ci.draw_colored_polygon(PackedVector2Array([_p(o, s, 0.16, 0.38), _p(o, s, 0.62, 0.38), _p(o, s, 0.56, 0.92),
					_p(o, s, 0.22, 0.92)]), ink)
				ci.draw_colored_polygon(PackedVector2Array([_p(o, s, 0.16, 0.38), _p(o, s, 0.62, 0.38), _p(o, s, 0.6, 0.5),
					_p(o, s, 0.18, 0.5)]), acc)
				ci.draw_arc(_p(o, s, 0.39, 0.38), s * 0.2, PI, TAU, 12, dark, s * 0.05, true)
				ci.draw_colored_polygon(PackedVector2Array([_p(o, s, 0.62, 0.4), _p(o, s, 0.8, 0.46), _p(o, s, 0.86, 0.74),
					_p(o, s, 0.78, 0.74)]), acc)
				ci.draw_circle(_p(o, s, 0.82, 0.84), s * 0.07, acc)
			"pattern":
				var cols := [acc, ink, acc, ink, acc]
				for i in 5:
					_rect(ci, o, s, 0.14, 0.14 + i * 0.144, 0.86, 0.14 + (i + 1) * 0.144, cols[i])
				ci.draw_colored_polygon(PackedVector2Array([_p(o, s, 0.14, 0.86), _p(o, s, 0.3, 0.52), _p(o, s, 0.42, 0.74),
					_p(o, s, 0.55, 0.4), _p(o, s, 0.68, 0.7), _p(o, s, 0.86, 0.48), _p(o, s, 0.86, 0.86)]), Color(1.0, 0.55, 0.12))
				_frame(ci, o, s, 0.14, 0.14, 0.86, 0.86, dark)
			"pick":
				ci.draw_line(_p(o, s, 0.18, 0.84), _p(o, s, 0.6, 0.42), ink, s * 0.1, true)
				ci.draw_line(_p(o, s, 0.52, 0.34), _p(o, s, 0.68, 0.5), ink, s * 0.14, true)
				ci.draw_circle(_p(o, s, 0.72, 0.28), s * 0.13, ink)
				ci.draw_circle(_p(o, s, 0.15, 0.88), s * 0.07, acc)
			"stencil":
				var pts := PackedVector2Array()
				for i in 10:
					var a := -PI * 0.5 + i * PI / 5.0
					var rr := 0.36 if i % 2 == 0 else 0.15
					pts.append(_p(o, s, 0.5 + cos(a) * rr, 0.54 + sin(a) * rr))
				ci.draw_colored_polygon(pts, acc)
				for side in [[0.08, 0.1, 0.92, 0.1], [0.92, 0.1, 0.92, 0.96], [0.92, 0.96, 0.08, 0.96], [0.08, 0.96, 0.08, 0.1]]:
					ci.draw_dashed_line(_p(o, s, side[0], side[1]), _p(o, s, side[2], side[3]), ink, s * 0.045, s * 0.1, true)
			"sticker":
				ci.draw_colored_polygon(PackedVector2Array([_p(o, s, 0.16, 0.14), _p(o, s, 0.84, 0.14), _p(o, s, 0.84, 0.64),
					_p(o, s, 0.62, 0.88), _p(o, s, 0.16, 0.88)]), ink)
				ci.draw_circle(_p(o, s, 0.42, 0.44), s * 0.14, acc)
				ci.draw_colored_polygon(PackedVector2Array([_p(o, s, 0.84, 0.64), _p(o, s, 0.62, 0.88), _p(o, s, 0.64, 0.66)]), dark)
			"face":
				ci.draw_circle(_p(o, s, 0.5, 0.44), s * 0.34, ink)
				_rect(ci, o, s, 0.33, 0.28, 0.67, 0.58, acc)
				ci.draw_circle(_p(o, s, 0.42, 0.4), s * 0.035, dark)
				ci.draw_circle(_p(o, s, 0.58, 0.4), s * 0.035, dark)
				ci.draw_arc(_p(o, s, 0.5, 0.46), s * 0.08, 0.3, PI - 0.3, 8, dark, s * 0.03, true)
				_rect(ci, o, s, 0.42, 0.78, 0.58, 0.96, ink)

	static func _p(o: Vector2, s: float, x: float, y: float) -> Vector2:
		return o + Vector2(x, y) * s

	static func _rect(ci: CanvasItem, o: Vector2, s: float, x0: float, y0: float, x1: float, y1: float, c: Color) -> void:
		ci.draw_rect(Rect2(_p(o, s, x0, y0), Vector2(x1 - x0, y1 - y0) * s), c)

	static func _frame(ci: CanvasItem, o: Vector2, s: float, x0: float, y0: float, x1: float, y1: float, c: Color) -> void:
		ci.draw_rect(Rect2(_p(o, s, x0, y0), Vector2(x1 - x0, y1 - y0) * s), c, false, s * 0.04)
