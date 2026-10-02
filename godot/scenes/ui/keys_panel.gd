## Панель клавиш боя (автор 02.10: «пометку сбоку мелкую, которая включается на L, чтобы все доп. клавиши посмотреть»). CanvasLayer
## над HUD у правого края: строки [клавиша, что делает, текущее значение] — значения живые (вариант замедления, стиль удара, обводка,
## масштаб камеры, пресет FX). Скрыта — у края остаётся мелкая метка «L — клавиши». Строит дерево сам; строки даёт lines_fn (Callable,
## возвращает Array[[key, title, value]]). Создаёт HitJuice.
class_name KeysPanel
extends CanvasLayer

const LAYER := 19
const FONT := 19
const REFRESH_S := 0.2

var lines_fn: Callable
var open := false

var _panel: PanelContainer
var _grid: GridContainer
var _tag: Label
var _t := 0.0


func _init() -> void:
	layer = LAYER
	name = "KeysPanel"


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_tag = Label.new()
	_tag.text = tr("L — клавиши")
	_tag.add_theme_font_size_override("font_size", 16)
	_tag.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_tag.add_theme_constant_override("outline_size", 4)
	_tag.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_tag.offset_left = -130.0
	_tag.offset_right = -14.0
	_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_tag)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.04, 0.72)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(_panel)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 3)
	_panel.add_child(_grid)
	_apply()


func toggle() -> void:
	open = not open
	_apply()


func set_open(on: bool) -> void:
	open = on
	_apply()


func _apply() -> void:
	if _panel == null:
		return
	_panel.visible = open
	_tag.visible = not open
	if open:
		refresh()


## Перестроить строки (вызывается и по таймеру, пока панель открыта).
func refresh() -> void:
	if _grid == null or not lines_fn.is_valid():
		return
	var rows: Array = lines_fn.call()
	var need := rows.size() * 3
	while _grid.get_child_count() < need:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", FONT)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", 3)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grid.add_child(l)
	while _grid.get_child_count() > need:
		var c := _grid.get_child(_grid.get_child_count() - 1)
		_grid.remove_child(c)
		c.queue_free()
	for i in range(rows.size()):
		var r: Array = rows[i]
		var k := _grid.get_child(i * 3) as Label
		var t := _grid.get_child(i * 3 + 1) as Label
		var v := _grid.get_child(i * 3 + 2) as Label
		k.text = String(r[0])
		t.text = String(r[1])
		v.text = String(r[2]) if r.size() > 2 else ""
		var header := String(r[0]) == "" and String(r[1]) != ""
		k.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
		t.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9) if header else Color(0.93, 0.93, 0.93))
		v.add_theme_color_override("font_color", Color(0.55, 0.95, 0.65))
	_layout()


## У правого края по центру высоты: размер — по содержимому (якорь справа, отступы от него влево).
func _layout() -> void:
	var ms := _panel.get_combined_minimum_size()
	_panel.offset_right = -14.0
	_panel.offset_left = -14.0 - ms.x
	_panel.offset_top = -ms.y * 0.5
	_panel.offset_bottom = ms.y * 0.5


## Строки, которые панель знает (для проб).
func row_texts() -> Array:
	var out: Array = []
	if _grid == null:
		return out
	for i in range(0, _grid.get_child_count(), 3):
		out.append([(_grid.get_child(i) as Label).text, (_grid.get_child(i + 1) as Label).text, (_grid.get_child(i + 2) as Label).text])
	return out


func _process(delta: float) -> void:
	if not open:
		return
	_t += FxClock.real_delta(delta)
	if _t >= REFRESH_S:
		_t = 0.0
		refresh()
