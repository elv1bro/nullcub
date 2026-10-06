## Плашка типа шарнира на вкладке «Шарниры» (кит тела v2, docs/plan-demo/BODY_KIT.md §5.2, §5.5): кружок цвета типа, название,
## как ведёт себя сустав (KitJoint.TYPES.hint), энергия. Клик — сигнал picked (WorkshopBuild.set_joint_pick: инструмент в руке,
## следующий клик по детали на стенде ставит тип её связи с родителем). Выбранная — золотая рамка.
## Подсказка (tooltip) — множители мышцы / силы / трения и ход сустава.
extends PanelContainer

signal picked(joint_type: String)

## Цвет типа: плашка, кружки на суставах стенда (anchor_overlay.gd, инструмент шарнира).
const COLORS := {
	"pin": Color(1.0, 0.93, 0.78), "free": Color(0.55, 0.85, 1.0), "spring": Color(0.55, 0.95, 0.45),
	"motor": Color(1.0, 0.52, 0.25), "weld": Color(0.72, 0.74, 0.8),
}

var joint_type := ""
var _style := StyleBoxFlat.new()
var _style_hover := StyleBoxFlat.new()
var _style_sel := StyleBoxFlat.new()
var _selected := false
var _hovered := false


static func colour(jt: String) -> Color:
	if KitJoint.is_tether(jt):   # деталь на связке — цвет вида связки (KitLink.COLORS)
		return KitLink.colour(KitJoint.tether_link(jt))
	return COLORS.get(jt if jt != "" else KitJoint.DEFAULT, Color.WHITE)


## Плашка вида связки (KitLink, WORKSHOP_V4.md «Связки») на вкладке «Связки»: тот же вид, что у шарнира; picked — вид связки.
func setup_link(t: String) -> void:
	var em := int(float(KitLink.info(t)["energy_m"]))
	_setup_any(t, KitLink.title_of(t), KitLink.hint_of(t), tr("⚡%d/м") % em, KitLink.colour(t), true,
		"\n".join([KitLink.title_of(t), KitLink.hint_of(t), TranslationServer.translate("энергия %d за метр, не меньше %d") % [em, KitLink.ENERGY_MIN],
			TranslationServer.translate("связку можно перебить: урон в неё копится, и она рвётся")]))


func setup(jt: String) -> void:
	var e0 := KitJoint.energy_of(jt)
	_setup_any(jt, tr(String(KitJoint.info(jt).get("title", jt))), tr(String(KitJoint.info(jt).get("hint", ""))), "⚡%d" % e0, colour(jt), e0 > 0, _tooltip(jt))


func _setup_any(jt: String, title_text: String, hint_text: String, energy_text: String, col: Color, energy_lit: bool, tip: String) -> void:
	joint_type = jt
	custom_minimum_size = Vector2(0, 66)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for s in [_style, _style_hover, _style_sel]:
		s.bg_color = Color(0.11, 0.09, 0.075, 0.95)
		s.set_border_width_all(2)
		s.set_corner_radius_all(8)
		s.content_margin_left = 10
		s.content_margin_right = 10
		s.content_margin_top = 5
		s.content_margin_bottom = 6
	_style.border_color = Color(0.36, 0.26, 0.16)
	_style_hover.border_color = Color(0.95, 0.75, 0.4)
	_style_hover.bg_color = Color(0.17, 0.13, 0.1, 0.97)
	_style_sel.border_color = Color(1.0, 0.8, 0.3)
	_style_sel.bg_color = Color(0.24, 0.18, 0.08, 0.97)
	_style_sel.set_border_width_all(4)
	add_theme_stylebox_override("panel", _style)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(26, 26)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ds := StyleBoxFlat.new()
	ds.bg_color = col
	ds.set_corner_radius_all(13)
	ds.set_border_width_all(3)
	ds.border_color = Color(0.05, 0.04, 0.03)
	dot.add_theme_stylebox_override("panel", ds)
	row.add_child(dot)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", -2)
	row.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	var title := Label.new()
	title.text = title_text
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color(0.96, 0.92, 0.84))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(title)
	var energy := Label.new()
	energy.text = energy_text
	energy.add_theme_font_size_override("font_size", 18)
	energy.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35) if energy_lit else Color(0.7, 0.66, 0.6))
	energy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(energy)
	var hint := Label.new()
	hint.text = hint_text
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.8, 0.76, 0.7))
	hint.add_theme_constant_override("line_spacing", -3)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(hint)
	tooltip_text = tip
	mouse_entered.connect(func() -> void:
		_hovered = true
		_restyle())
	mouse_exited.connect(func() -> void:
		_hovered = false
		_restyle())


func set_selected(on: bool) -> void:
	if on == _selected:
		return
	_selected = on
	_restyle()


func _restyle() -> void:
	add_theme_stylebox_override("panel", _style_sel if _selected else (_style_hover if _hovered else _style))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		picked.emit(joint_type)
		accept_event()


static func _tooltip(jt: String) -> String:
	var info := KitJoint.info(jt)
	var lines: PackedStringArray = [TranslationServer.translate(String(info.get("title", jt))), TranslationServer.translate(String(info.get("hint", "")))]
	if KitJoint.is_tether(jt):
		lines.append(TranslationServer.translate("сустава и мышцы нет: деталь со всем, что на ней, висит на связке «%s»") % KitLink.title_of(KitJoint.tether_link(jt)))
		lines.append(TranslationServer.translate("клик ещё раз — длиннее: %s м") % " / ".join(KitJoint.tether_lens(jt).map(func(x: Variant) -> String: return "%.1f" % float(x))))
		lines.append(TranslationServer.translate("энергия — связка по длине и вынос всей ветки дальше от ядра; связку можно перебить"))
		lines.append(TranslationServer.translate("тяга на ней — мышь крутит её вокруг крепления связки"))
	elif KitJoint.is_weld(jt):
		lines.append(TranslationServer.translate("своего тела и сустава нет: масса и формы — у родителя"))
		lines.append(TranslationServer.translate("нельзя: голова, рука мышью, деталь с суставом на конце"))
	else:
		lines.append(TranslationServer.translate("мышца ×%s · сила ×%s · трение ×%s") % [String.num(float(info.get("k", 1.0))), String.num(float(info.get("tmax", 1.0))),
			String.num(float(info.get("friction", 1.0)))])
		var l: Variant = info.get("limits", "group")
		if l is Vector2:
			lines.append(TranslationServer.translate("ход %d…%d°") % [int((l as Vector2).x), int((l as Vector2).y)])
		elif String(l) == "group+20":
			lines.append(TranslationServer.translate("ход шире сустава на 20° в обе стороны"))
		else:
			lines.append(TranslationServer.translate("ход — как у сустава"))
	if KitJoint.energy_of(jt) > 0:
		lines.append(TranslationServer.translate("энергия %d") % KitJoint.energy_of(jt))
	return "\n".join(lines)
