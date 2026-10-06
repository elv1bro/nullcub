## Рамка-обложка фоторежима (PhotoMode, docs/plan-demo/look/cam.md): тёмное паспарту, тонкая кремовая линия, сверху знак N0 и
## название игры NULL GRAVITY (NULL — белый, GRAVITY — оранжевый, Oswald, BRAND.md), под ним строка лиги; снизу слоган заставки и
## дата. Название и слоган — бренд, не переводятся. Координаты — в базе окна 1920×1080 (stretch canvas_items).
class_name PhotoFrame
extends Control

const MATTE := Color("090e16")
const CREAM := Color("f1e0b4")
const ORANGE := Color("ff8c33")
const MATTE_PX := 26.0
const LINE_INSET := 12.0
const LINE_W := 3.0
const BAND_TOP := 250.0
const BAND_BOTTOM := 150.0
const BADGE := preload("res://assets/ui/brand/null_gravity_badge_512.png")
const TAGLINE := "GRAVITY IS OPTIONAL.  WINNING IS NOT."

var title_null: Label
var title_gravity: Label
var league: Label
var tagline: Label
var date_label: Label
var badge: TextureRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # не set_anchors_preset: в дереве он сохранил бы нулевой размер
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band(true)
	_band(false)
	badge = TextureRect.new()
	badge.texture = BADGE
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.position = Vector2(MATTE_PX + 34.0, MATTE_PX + 26.0)
	badge.size = Vector2(150.0, 150.0)
	add_child(badge)
	var head := _font(650)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_CENTER_TOP)
	row.offset_left = -700.0
	row.offset_right = 700.0
	row.offset_top = MATTE_PX + 18.0
	row.offset_bottom = MATTE_PX + 168.0
	add_child(row)
	title_null = _label("NULL", head, 128, Color.WHITE)
	title_gravity = _label("GRAVITY", head, 128, ORANGE)
	row.add_child(title_null)
	row.add_child(title_gravity)
	league = _label(tr("NULL FIGHTING · МЕСТНАЯ ЛИГА"), _font(450), 30, CREAM)
	league.set_anchors_preset(Control.PRESET_CENTER_TOP)
	league.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	league.offset_left = -600.0
	league.offset_right = 600.0
	league.offset_top = MATTE_PX + 168.0
	league.offset_bottom = MATTE_PX + 210.0
	add_child(league)
	var small := _font(500)
	tagline = _label(TAGLINE, small, 28, CREAM)
	tagline.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	tagline.offset_left = MATTE_PX + 40.0
	tagline.offset_right = MATTE_PX + 1000.0
	tagline.offset_top = -MATTE_PX - 78.0
	tagline.offset_bottom = -MATTE_PX - 30.0
	add_child(tagline)
	date_label = _label("", small, 28, CREAM)
	date_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	date_label.offset_left = -MATTE_PX - 600.0
	date_label.offset_right = -MATTE_PX - 40.0
	date_label.offset_top = -MATTE_PX - 78.0
	date_label.offset_bottom = -MATTE_PX - 30.0
	add_child(date_label)
	var lines := Control.new()   # линия и уголки — поверх затемнений
	lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.draw.connect(_draw_lines.bind(lines))
	add_child(lines)
	refresh()


## Дата снимка (ДД.ММ.ГГГГ) — при каждом входе в фоторежим.
func refresh() -> void:
	var d := Time.get_date_dict_from_system()
	date_label.text = "N0 · %02d.%02d.%04d" % [int(d["day"]), int(d["month"]), int(d["year"])]


static func _font(weight: int) -> Font:
	var fv := FontVariation.new()
	fv.base_font = load("res://assets/fonts/Oswald.ttf")
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return fv


func _label(text: String, font: Font, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_constant_override("shadow_outline_size", 8)
	return l


## Затемнение сверху и снизу под надписями (градиент от паспарту к прозрачному).
func _band(top: bool) -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(MATTE, 0.82), Color(MATTE, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 4
	t.height = 64
	t.fill_from = Vector2(0, 0) if top else Vector2(0, 1)
	t.fill_to = Vector2(0, 1) if top else Vector2(0, 0)
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_left = 0.0
	r.anchor_right = 1.0
	r.anchor_top = 0.0 if top else 1.0
	r.anchor_bottom = 0.0 if top else 1.0
	r.offset_top = 0.0 if top else -BAND_BOTTOM
	r.offset_bottom = BAND_TOP if top else 0.0
	add_child(r)


## Паспарту, кремовая линия и оранжевые уголки (слой поверх затемнений и надписей не перекрывает).
func _draw_lines(c: Control) -> void:
	var s := c.size
	c.draw_rect(Rect2(0, 0, s.x, MATTE_PX), MATTE)
	c.draw_rect(Rect2(0, s.y - MATTE_PX, s.x, MATTE_PX), MATTE)
	c.draw_rect(Rect2(0, 0, MATTE_PX, s.y), MATTE)
	c.draw_rect(Rect2(s.x - MATTE_PX, 0, MATTE_PX, s.y), MATTE)
	var o := MATTE_PX + LINE_INSET
	c.draw_rect(Rect2(o, o, s.x - 2.0 * o, s.y - 2.0 * o), CREAM, false, LINE_W)
	var L := 54.0
	for e in [[Vector2(o, o), Vector2(1, 1)], [Vector2(s.x - o, o), Vector2(-1, 1)], [Vector2(o, s.y - o), Vector2(1, -1)], [Vector2(s.x - o, s.y - o), Vector2(-1, -1)]]:
		var p: Vector2 = e[0]
		var d: Vector2 = e[1]
		c.draw_line(p, p + Vector2(d.x * L, 0), ORANGE, 7.0)
		c.draw_line(p, p + Vector2(0, d.y * L), ORANGE, 7.0)

