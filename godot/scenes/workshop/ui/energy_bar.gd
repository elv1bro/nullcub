## Полоска ENERGY мастерской (CONCEPT_V2 §6): использовано / бюджет Ядра, деления по 10, цвет по заполнению (зелёный → жёлтый →
## оранжевый, перебор — красный с пульсом). preview — сколько станет, если поставить деталь в руке (светлая «тень» поверх).
## Только рисование, значения задаёт workshop_ui.gd.
extends Control

const SEG := 10

var used := 0
var budget := 100
var preview := -1           # < 0 — нет
var _pulse := 0.0
var _bg := StyleBoxFlat.new()


func _ready() -> void:
	_bg.bg_color = Color(0.05, 0.045, 0.04, 0.92)
	_bg.border_color = Color(0.42, 0.28, 0.15, 1.0)
	_bg.set_border_width_all(3)
	_bg.set_corner_radius_all(6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_values(u: int, b: int, p: int = -1) -> void:
	if u == used and b == budget and p == preview:
		return
	used = u
	budget = maxi(b, 1)
	preview = p
	queue_redraw()


static func colour_for(frac: float) -> Color:
	if frac > 1.0:
		return Color(0.95, 0.22, 0.16)
	if frac > 0.9:
		return Color(1.0, 0.55, 0.18)
	if frac > 0.7:
		return Color(0.98, 0.82, 0.25)
	return Color(0.45, 0.85, 0.35)


func _process(delta: float) -> void:
	if used > budget or (preview >= 0 and preview > budget):
		_pulse += delta * 7.0
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	_bg.draw(get_canvas_item(), rect)
	var inner := rect.grow(-5.0)
	var frac := float(used) / float(budget)
	var c := colour_for(frac)
	if used > budget:
		c = c.lerp(Color(1, 1, 1), 0.25 + 0.25 * sin(_pulse))
	var w := inner.size.x * clampf(frac, 0.0, 1.0)
	if preview >= 0 and preview != used:
		var pf := clampf(float(preview) / float(budget), 0.0, 1.0)
		var pc := colour_for(float(preview) / float(budget))
		pc.a = 0.45 + (0.2 * sin(_pulse) if preview > budget else 0.0)
		var x0 := inner.position.x + minf(w, inner.size.x * pf)
		var x1 := inner.position.x + maxf(w, inner.size.x * pf)
		draw_rect(Rect2(Vector2(x0, inner.position.y), Vector2(x1 - x0, inner.size.y)), pc)
	if w > 0.5:
		var fill := Rect2(inner.position, Vector2(w, inner.size.y))
		draw_rect(fill, c.darkened(0.3))
		draw_rect(Rect2(fill.position, Vector2(fill.size.x, fill.size.y * 0.55)), c)
		draw_rect(Rect2(fill.position + Vector2(0, 1), Vector2(fill.size.x, fill.size.y * 0.25)), Color(1, 1, 1, 0.2))
	for i in range(1, SEG):
		var x := inner.position.x + inner.size.x * float(i) / float(SEG)
		draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), Color(0, 0, 0, 0.45), 2.0)
