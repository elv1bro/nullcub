## Стрелки за экраном (лист камеры автора, правило 4, docs/plan-demo/ART_NULL.md): если боец вне кадра, у края экрана
## рисуется стрелка его цвета, под ней подпись «P2 · 37 м» — расстояние в плоскости боя от главной куклы кадра (P1,
## DynamicCamera.primary_doll(); автор 02.10: «стрелкой и написать количество метров до него»). Стрелка самой главной куклы
## (её увела кинематография крита) и камера без primary_doll() — от центра кадра. Где соперник — подсказка только этого HUD,
## N0 о направлении и метрах не говорит (автор 02.10).
## Узел — CanvasLayer в сцене площадки; бойцы — группа dolls (Doll: player_index, centre_of_mass()), камера — текущая.
extends CanvasLayer

@export var dolls_group := "dolls"
## Отступ стрелки от края экрана (px) и «мёртвая зона»: боец чуть за краем — ещё не стрелка.
@export var margin := 52.0
@export var inside_pad := 8.0
@export var font_size := 24

var markers: Array[Dictionary] = []   # последние стрелки: {player, pos, dir, dist, from_doll} — для проб
var _canvas: Control


func _ready() -> void:
	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_markers)
	add_child(_canvas)


func _process(_delta: float) -> void:
	markers.clear()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_canvas.queue_redraw()
		return
	var size := get_viewport().get_visible_rect().size
	var centre := size * 0.5
	var inner := Rect2(Vector2(inside_pad, inside_pad), size - Vector2(inside_pad, inside_pad) * 2.0)
	# центр кадра на плоскости боя (z = 0)
	var from := cam.project_ray_origin(centre)
	var dir := cam.project_ray_normal(centre)
	var world_centre := from + dir * (-from.z / dir.z) if absf(dir.z) > 1e-4 else from
	var main: Node3D = null
	if cam.has_method("primary_doll"):
		main = cam.call("primary_doll")
	var main_pos: Vector3 = world_centre
	if main != null:
		main_pos = main.call("centre_of_mass", true)
	for d in get_tree().get_nodes_in_group(dolls_group):
		if not (d is Node3D) or not d.has_method("centre_of_mass"):
			continue
		var com: Vector3 = d.call("centre_of_mass", true)
		var behind := cam.is_position_behind(com)
		var sp := cam.unproject_position(com)
		if not behind and inner.has_point(sp):
			continue
		var v := sp - centre
		if behind:
			v = -v
		if v.length() < 1.0:
			v = Vector2.RIGHT
		# точка на прямоугольнике края
		var half := size * 0.5 - Vector2(margin, margin)
		var k := minf(half.x / maxf(absf(v.x), 1e-4), half.y / maxf(absf(v.y), 1e-4))
		var pos := centre + v * k
		var idx := int(d.get("player_index")) if d.get("player_index") != null else 0
		var origin := main_pos if d != main else world_centre
		markers.append({"player": idx, "pos": pos, "dir": v.normalized(), "from_doll": d != main and main != null,
			"dist": Vector2(com.x - origin.x, com.y - origin.y).length()})
	_canvas.queue_redraw()


## Вид по скину HUD (scripts/ui/hud_skin.gd): трансляция — тёмная косая плашка с полосой цвета игрока со стороны соперника,
## внутри треугольник и метры; неон — светящийся шеврон цвета игрока и метры с ореолом; LED — шеврон из светодиодов и метры
## табло. Метры под стрелкой (у нижнего края экрана — над ней).
func _draw_markers() -> void:
	for m in markers:
		match HudSkin.id():
			"neon":
				_draw_neon(m)
			"led":
				_draw_led(m)
			_:
				_draw_plate(m)


func _text(m: Dictionary) -> String:
	return tr("P%d · %d м") % [int(m["player"]) + 1, int(round(float(m["dist"])))]


func _colour(m: Dictionary) -> Color:
	return Tuning.PLAYER_COLORS[int(m["player"]) % Tuning.PLAYER_COLORS.size()]


## Позиция подписи: под стрелкой, у нижнего края — над ней; x — по центру, в пределах экрана.
func _label_pos(p: Vector2, d: Vector2, ls: Vector2) -> Vector2:
	var below := d.y < 0.6 and p.y + 48.0 < _canvas.size.y
	var lp := Vector2(p.x - ls.x * 0.5, p.y + 44.0 if below else p.y - 26.0)
	lp.x = clampf(lp.x, 6.0, _canvas.size.x - ls.x - 6.0)
	return lp


func _draw_plate(m: Dictionary) -> void:
	var font := HudSkin.font("display")
	var col := _colour(m)
	var p: Vector2 = m["pos"]
	var d: Vector2 = m["dir"]
	var label := _text(m)
	var ls := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var below := d.y < 0.6 and p.y + 48.0 < _canvas.size.y
	var w := maxf(ls.x, 44.0) + 52.0
	var h := 44.0 + ls.y + 10.0
	var top := p.y - 26.0 if below else p.y - (h - 26.0)
	var r := Rect2(Vector2(clampf(p.x - w * 0.5, 4.0, _canvas.size.x - w - 4.0), clampf(top, 4.0, _canvas.size.y - h - 4.0)), Vector2(w, h))
	var st := Broadcast.plate()
	st.edge_color = col
	st.edge_w = 8.0
	st.edge_side = 1 if d.x >= 0.0 else -1
	st.draw_in(_canvas.get_canvas_item(), r)
	var c := Vector2(r.get_center().x, r.position.y + 24.0 if below else r.end.y - 24.0)
	var side := Vector2(-d.y, d.x)
	_canvas.draw_colored_polygon(PackedVector2Array([c + d * 16.0, c - d * 10.0 + side * 13.0, c - d * 10.0 - side * 13.0]), col)
	var ly := r.end.y - 12.0 if below else r.position.y + ls.y * 0.8 + 6.0
	_canvas.draw_string(font, Vector2(r.get_center().x - ls.x * 0.5, ly), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Broadcast.TEXT)


func _chevron(p: Vector2, d: Vector2) -> PackedVector2Array:
	var side := Vector2(-d.y, d.x)
	return PackedVector2Array([p - d * 8.0 + side * 16.0, p + d * 16.0, p - d * 8.0 - side * 16.0])


func _draw_neon(m: Dictionary) -> void:
	var font := HudSkin.font("plate")
	var col := _colour(m)
	var p: Vector2 = m["pos"]
	var d: Vector2 = m["dir"]
	var ch := _chevron(p, d)
	_canvas.draw_polyline(ch, Color(col, 0.16), 14.0, true)
	_canvas.draw_polyline(ch, Color(col, 0.32), 8.0, true)
	_canvas.draw_polyline(ch, col.lerp(Color.WHITE, 0.45), 3.5, true)
	var label := _text(m)
	var ls := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var lp := _label_pos(p, d, ls)
	_canvas.draw_string_outline(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 10, Color(col, 0.4))
	_canvas.draw_string(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col.lerp(Color.WHITE, 0.6))


func _draw_led(m: Dictionary) -> void:
	var font := HudSkin.font("digits")
	var p: Vector2 = m["pos"]
	var d: Vector2 = m["dir"]
	var ch := _chevron(p, d)
	for k in 2:
		var a: Vector2 = ch[k]
		var b: Vector2 = ch[k + 1]
		var n := maxi(int(a.distance_to(b) / 5.5), 1)
		for i in n + 1:
			var q := a.lerp(b, float(i) / float(n))
			_canvas.draw_circle(q, 4.2, Color(HudSkin.LED_RED, 0.25))
			_canvas.draw_circle(q, 2.3, HudSkin.LED_RED)
	var label := _text(m)
	var ls := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size + 2)
	var lp := _label_pos(p, d, ls)
	var bg := Rect2(lp + Vector2(-10.0, -ls.y * 0.85), ls + Vector2(20.0, 8.0))
	HudSkin.led_box(0.0, 0.0).draw(_canvas.get_canvas_item(), bg)
	_canvas.draw_string_outline(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size + 2, 6, Color(HudSkin.LED, 0.35))
	_canvas.draw_string(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size + 2, HudSkin.LED)
