## Стрелки за экраном (лист камеры автора, правило 4, docs/plan-demo/ART_NULL.md): если боец вне кадра, у края экрана
## рисуется стрелка его цвета с подписью «P2 · 37 м» — расстояние в плоскости боя от главной куклы кадра (P1,
## DynamicCamera.primary_doll(); автор 02.10: «стрелкой и написать количество метров до него»). Стрелка самой главной куклы
## (её увела кинематография крита) и камера без primary_doll() — от центра кадра.
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


func _draw_markers() -> void:
	var font := ThemeDB.fallback_font
	for m in markers:
		var idx: int = m["player"]
		var col: Color = Tuning.PLAYER_COLORS[idx % Tuning.PLAYER_COLORS.size()]
		var p: Vector2 = m["pos"]
		var d: Vector2 = m["dir"]
		var side := Vector2(-d.y, d.x)
		var tip := p + d * 26.0
		var pts := PackedVector2Array([tip, p - d * 12.0 + side * 18.0, p - d * 4.0, p - d * 12.0 - side * 18.0])
		_canvas.draw_colored_polygon(pts, Color(0, 0, 0, 0.6))
		var inner := PackedVector2Array()
		for q in pts:
			inner.append(p + (q - p) * 0.8)
		_canvas.draw_colored_polygon(inner, col)
		var label := "P%d · %d м" % [idx + 1, int(round(float(m["dist"])))]
		var ls := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var lp := p - d * 40.0 - ls * 0.5 + Vector2(0.0, ls.y * 0.35)
		lp.x = clampf(lp.x, 6.0, _canvas.size.x - ls.x - 6.0)
		_canvas.draw_string_outline(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 7, Color(0, 0, 0, 0.85))
		_canvas.draw_string(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col.lightened(0.35))
