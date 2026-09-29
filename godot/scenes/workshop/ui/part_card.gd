## Карточка детали на полке мастерской: иконка (PartIcons, рендер в рантайме), название, энергия и масса. Нажал ЛКМ — сигнал
## grabbed (WorkshopBuild.begin_drag: протяжка или «деталь в руке» по клику). Не влезает в бюджет — энергия красная, карточка тусклее.
## Подсказка (tooltip) — вид, масса, крепление, множитель удара.
extends PanelContainer

signal grabbed(part_id: String, pos: Vector2)

const ICON := 92

var part_id := ""
var def: PartDef
var _icon: TextureRect
var _kind: Label
var _energy: Label
var _style := StyleBoxFlat.new()
var _style_hover := StyleBoxFlat.new()
var _fits := true


func setup(d: PartDef) -> void:
	def = d
	part_id = d.id
	custom_minimum_size = Vector2(122, 168)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	for s in [_style, _style_hover]:
		s.bg_color = Color(0.11, 0.09, 0.075, 0.95)
		s.set_border_width_all(2)
		s.set_corner_radius_all(8)
		s.content_margin_left = 6
		s.content_margin_right = 6
		s.content_margin_top = 6
		s.content_margin_bottom = 6
	_style.border_color = Color(0.36, 0.26, 0.16)
	_style_hover.border_color = Color(0.95, 0.75, 0.4)
	_style_hover.bg_color = Color(0.17, 0.13, 0.1, 0.97)
	add_theme_stylebox_override("panel", _style)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	add_child(v)
	var icon_box := Control.new()
	icon_box.custom_minimum_size = Vector2(ICON, ICON)
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(icon_box)
	_kind = Label.new()
	_kind.text = String(CraftEdit.KIND_TITLES.get(d.kind, d.kind))
	_kind.add_theme_font_size_override("font_size", 16)
	_kind.add_theme_color_override("font_color", Color(0.75, 0.68, 0.58))
	_kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kind.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_kind.set_anchors_preset(Control.PRESET_FULL_RECT)
	_kind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_child(_kind)
	_icon = TextureRect.new()
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_child(_icon)
	var title := Label.new()
	title.text = _short_title(d.title)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size = Vector2(108, 40)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.96, 0.92, 0.84))
	title.add_theme_constant_override("line_spacing", -4)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(title)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_energy = Label.new()
	_energy.text = "⚡%d" % d.energy
	_energy.add_theme_font_size_override("font_size", 18)
	_energy.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35) if d.energy > 0 else Color(0.7, 0.66, 0.6))
	_energy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_energy)
	var mass := Label.new()
	mass.text = "%.1f кг" % d.mass
	mass.add_theme_font_size_override("font_size", 16)
	mass.add_theme_color_override("font_color", Color(0.8, 0.76, 0.7))
	mass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mass)
	tooltip_text = _tooltip(d)
	mouse_entered.connect(func() -> void: add_theme_stylebox_override("panel", _style_hover))
	mouse_exited.connect(func() -> void: add_theme_stylebox_override("panel", _style))


func set_icon(tex: Texture2D) -> void:
	if _icon != null and tex != null:
		_icon.texture = tex
		_kind.visible = false


## Влезает ли по энергии (хотя бы на свободный якорь): нет — энергия красная, карточка тусклее (но тащить можно — на замену).
func set_fits(fits: bool) -> void:
	if fits == _fits:
		return
	_fits = fits
	modulate = Color(1, 1, 1, 1) if fits else Color(0.72, 0.62, 0.6, 0.85)
	_energy.add_theme_color_override("font_color", (Color(1.0, 0.86, 0.35) if def.energy > 0 else Color(0.7, 0.66, 0.6)) if fits else Color(1.0, 0.35, 0.28))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		grabbed.emit(part_id, get_viewport().get_mouse_position())
		accept_event()


static func _short_title(t: String) -> String:
	return t.replace(" (клён)", "").replace(" (хлам)", " · хлам")


static func _tooltip(d: PartDef) -> String:
	var lines: PackedStringArray = [d.title]
	lines.append("%s · %.1f кг · энергия %d" % [String(CraftEdit.KIND_TITLES.get(d.kind, d.kind)).capitalize(), d.mass, d.energy])
	lines.append("свой сустав — болтается" if d.attach == "joint" else "прикручивается намертво")
	if d.weapon_mult > 1.0:
		lines.append("урон оружия ×%.2f" % d.weapon_mult)
	if d.body_mult >= 1.5:
		lines.append("бьёт сильно (×%.1f)" % d.body_mult)
	var anchors := BodyBlueprint.part_anchors(d)
	if not anchors.is_empty():
		lines.append("якорей: %d" % anchors.size())
	return "\n".join(lines)
