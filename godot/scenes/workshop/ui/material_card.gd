## Плашка материала на вкладке «Материал» (кит тела v2, docs/plan-demo/BODY_KIT.md §4, §5.5): цвет (MaterialDef.swatch), название,
## плотность (относительно дерева = 1: масса детали меняется как новая плотность / прежняя), трение, упругость, «магнит» (iron —
## тянет магнит Свалки). Клик — сигнал picked (WorkshopBuild.set_paint_mat: кисть в руке, клик по детали на стенде красит её).
## Выбранная — золотая рамка.
extends PanelContainer

signal picked(mat_id: String)

var mat_id := ""
var _style := StyleBoxFlat.new()
var _style_hover := StyleBoxFlat.new()
var _style_sel := StyleBoxFlat.new()
var _selected := false
var _hovered := false


func setup(m: MaterialDef) -> void:
	mat_id = m.id
	custom_minimum_size = Vector2(0, 72)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for s in [_style, _style_hover, _style_sel]:
		s.bg_color = Color(0.11, 0.09, 0.075, 0.95)
		s.set_border_width_all(2)
		s.set_corner_radius_all(8)
		s.content_margin_left = 6
		s.content_margin_right = 6
		s.content_margin_top = 5
		s.content_margin_bottom = 5
	_style.border_color = Color(0.36, 0.26, 0.16)
	_style_hover.border_color = Color(0.95, 0.75, 0.4)
	_style_hover.bg_color = Color(0.17, 0.13, 0.1, 0.97)
	_style_sel.border_color = Color(1.0, 0.8, 0.3)
	_style_sel.bg_color = Color(0.24, 0.18, 0.08, 0.97)
	_style_sel.set_border_width_all(4)
	add_theme_stylebox_override("panel", _style)
	# ряд 1: плашка цвета + название; ряд 2: плотность (дерево = 1) и «магнит»; ряд 3: трение и упругость (во всю ширину карточки)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", -2)
	add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 7)
	v.add_child(top)
	var sw := Panel.new()
	sw.custom_minimum_size = Vector2(24, 24)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ss := StyleBoxFlat.new()
	ss.bg_color = m.swatch
	ss.set_corner_radius_all(5)
	ss.set_border_width_all(2)
	ss.border_color = m.swatch.darkened(0.55)
	sw.add_theme_stylebox_override("panel", ss)
	top.add_child(sw)
	var title := Label.new()
	title.text = m.title
	title.clip_text = true
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(0.96, 0.92, 0.84))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(title)
	var dens := HBoxContainer.new()
	dens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(dens)
	var dl := _small(tr("плотность ×%s") % _n(m.density), Color(1.0, 0.8, 0.4) if m.density > 1.05 else (Color(0.65, 0.9, 0.6) if m.density < 0.95 else Color(0.8, 0.76, 0.7)))
	dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dens.add_child(dl)
	if m.iron:
		dens.add_child(_small(tr("магнит"), Color(0.62, 0.78, 1.0), false))
	v.add_child(_small(tr("трение %s · упруг. %s") % [_n(m.friction), _n(m.bounce)], Color(0.74, 0.7, 0.64)))
	tooltip_text = tr("%s\n%s\n(дерево = 1; масса детали меняется как новая плотность / прежняя)") % [m.title, CraftEdit.mat_line(m.id)]
	mouse_entered.connect(func() -> void:
		_hovered = true
		_restyle())
	mouse_exited.connect(func() -> void:
		_hovered = false
		_restyle())


## Мелкая строка; clip — обрезать, если не влезает (в VBox / с EXPAND — ширина карточки; без — по тексту).
static func _small(t: String, c: Color, clip := true) -> Label:
	var l := Label.new()
	l.text = t
	l.clip_text = clip
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _n(x: float) -> String:
	return String.num(snappedf(x, 0.01))


func set_selected(on: bool) -> void:
	if on == _selected:
		return
	_selected = on
	_restyle()


func _restyle() -> void:
	add_theme_stylebox_override("panel", _style_sel if _selected else (_style_hover if _hovered else _style))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		picked.emit(mat_id)
		accept_event()
