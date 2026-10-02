## Косая плашка эфира NULL League (scripts/ui/broadcast.gd): параллелограмм с наклоном skew (сдвиг верхнего края — доля высоты),
## mirror — наклон в другую сторону (правые панели), полоса edge_color шириной edge_w по левому (edge_side = −1) или правому (+1)
## краю, полоса underline_color высотой underline_h по низу, мягкая тень снизу. StyleBox — годится для PanelContainer, Label
## (стиль normal), Button и для рисования вручную (draw_in).
class_name BcStyle
extends StyleBox

@export var bg := Color(0.04, 0.063, 0.118, 0.93)
@export var skew := 0.21
@export var mirror := false
@export var edge_color := Color(0, 0, 0, 0)
@export var edge_w := 0.0
@export var edge_side := -1
@export var underline_color := Color(0, 0, 0, 0)
@export var underline_h := 0.0
@export var shadow_alpha := 0.35


## Параллелограмм в прямоугольнике: наклон вправо (верх сдвинут вправо) или зеркально.
static func para(r: Rect2, skew_px: float, mirrored: bool) -> PackedVector2Array:
	var s := clampf(skew_px, 0.0, r.size.x * 0.5)
	if mirrored:
		return PackedVector2Array([r.position, Vector2(r.end.x - s, r.position.y), r.end, Vector2(r.position.x + s, r.end.y)])
	return PackedVector2Array([Vector2(r.position.x + s, r.position.y), Vector2(r.end.x, r.position.y),
		Vector2(r.end.x - s, r.end.y), Vector2(r.position.x, r.end.y)])


func _draw(to: RID, rect: Rect2) -> void:
	draw_in(to, rect)


## Нарисовать плашку в canvas item (для Control._draw: get_canvas_item()).
func draw_in(to: RID, rect: Rect2) -> void:
	var s := rect.size.y * skew
	if shadow_alpha > 0.0:
		RenderingServer.canvas_item_add_polygon(to, para(Rect2(rect.position + Vector2(0, 4), rect.size), s, mirror),
			PackedColorArray([Color(0, 0, 0, shadow_alpha * bg.a)]))
	var p := para(rect, s, mirror)
	RenderingServer.canvas_item_add_polygon(to, p, PackedColorArray([bg]))
	if edge_w > 0.0 and edge_color.a > 0.0:
		var w := minf(edge_w, rect.size.x * 0.5)
		var e: PackedVector2Array
		if edge_side < 0:
			e = PackedVector2Array([p[0], p[0] + Vector2(w, 0), p[3] + Vector2(w, 0), p[3]])
		else:
			e = PackedVector2Array([p[1] - Vector2(w, 0), p[1], p[2], p[2] - Vector2(w, 0)])
		RenderingServer.canvas_item_add_polygon(to, e, PackedColorArray([edge_color]))
	if underline_h > 0.0 and underline_color.a > 0.0:
		var k := clampf(1.0 - underline_h / maxf(rect.size.y, 1.0), 0.0, 1.0)
		var u := PackedVector2Array([p[0].lerp(p[3], k), p[1].lerp(p[2], k), p[2], p[3]])
		RenderingServer.canvas_item_add_polygon(to, u, PackedColorArray([underline_color]))
