## Портрет игрока — вид по скину HUD (scripts/ui/hud_skin.gd): трансляция — косой блок цвета игрока, неон — тёмный круг
## с неоновым кольцом и свечением, LED — квадрат табло. Инициалы «P1» — заглушка под фото (этап 10: set_photo(texture) рисует
## текстуру, обрезанную по форме). mirror — наклон для правых панелей (трансляция). set_ko() гасит портрет в серый
## и перечёркивает. Дерево узлов — scenes/ui/portrait.tscn (форма рисуется в _draw, инициалы — дочерний Label).
class_name Portrait
extends Control

@export var colour := Color(0.18, 0.44, 0.87)
@export var initials := "P1":
	set(v):
		initials = v
		if is_node_ready():
			_label.text = v

var photo: Texture2D
var knocked_out := false
var mirror := false

@onready var _label: Label = $Initials


func _ready() -> void:
	_label.text = initials
	resized.connect(_on_resized)
	_on_resized()
	HudSkin.events.changed.connect(func(_id: String) -> void: _on_resized())


func _on_resized() -> void:
	if not is_node_ready():   # итоги матча зовут set_player до add_child — стиль подписи поставит _ready
		return
	var sz := int(minf(size.x, size.y) * 0.36)
	match HudSkin.id():
		"neon":
			HudSkin.style_label(_label, "display", int(sz * 0.8), Color.WHITE, colour)
		"led":
			HudSkin.style_label(_label, "digits", sz, colour.lerp(Color.WHITE, 0.35), colour)
		_:
			HudSkin.style_label(_label, "display", sz, Color.WHITE)
	queue_redraw()


func set_player(index: int) -> void:
	colour = Tuning.PLAYER_COLORS[clampi(index, 0, Tuning.PLAYER_COLORS.size() - 1)]
	initials = "P%d" % (index + 1)
	_on_resized()


func set_photo(tex: Texture2D) -> void:
	photo = tex
	_label.visible = tex == null
	queue_redraw()


func set_ko(ko: bool) -> void:
	knocked_out = ko
	modulate = Color(0.55, 0.55, 0.55, 1.0) if ko else Color.WHITE
	queue_redraw()


func _draw() -> void:
	match HudSkin.id():
		"neon":
			_draw_ring()
		"led":
			_draw_board()
		_:
			_draw_block()
	if knocked_out:
		# крест «выбыл»
		var c := size * 0.5
		var kx := size.y * 0.28
		draw_line(c + Vector2(-kx, -kx), c + Vector2(kx, kx), HudSkin.alert(), 7.0, true)
		draw_line(c + Vector2(-kx, kx), c + Vector2(kx, -kx), HudSkin.alert(), 7.0, true)


func _photo(pts: PackedVector2Array) -> void:
	if photo == null:
		return
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	for p in pts:
		uvs.append(Vector2(p.x / maxf(size.x, 1.0), p.y / maxf(size.y, 1.0)))
		cols.append(Color.WHITE)
	draw_polygon(pts, cols, uvs, photo)


## Трансляция: косой блок цвета игрока с тёмным низом.
func _draw_block() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var s := size.y * Broadcast.SKEW
	var pts := BcStyle.para(r, s, mirror)
	draw_colored_polygon(BcStyle.para(Rect2(r.position + Vector2(0, 3), r.size), s, mirror), Color(0, 0, 0, 0.4))
	draw_colored_polygon(pts, colour)
	var k := 0.55
	draw_colored_polygon(PackedVector2Array([pts[0].lerp(pts[3], k), pts[1].lerp(pts[2], k), pts[2], pts[3]]), colour.darkened(0.25))
	_photo(pts)


## Неон: тёмный круг, кольцо цвета игрока и ореол.
func _draw_ring() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 4.0
	for i in range(4, 0, -1):
		draw_arc(c, r, 0.0, TAU, 64, Color(colour, 0.12), 3.0 + i * 4.0, true)
	draw_circle(c, r, Color(0.02, 0.035, 0.07, 0.92))
	var pts := PackedVector2Array()
	for i in 48:
		var a := TAU * float(i) / 48.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r - 4.0))
	_photo(pts)
	draw_arc(c, r, 0.0, TAU, 64, colour.lerp(Color.WHITE, 0.3), 3.5, true)


## LED: квадрат табло с тёмной рамкой.
func _draw_board() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.04, 0.045, 0.05))
	draw_rect(r.grow(-1.0), Color(0.15, 0.16, 0.18), false, 2.0)
	_photo(PackedVector2Array([r.position + Vector2(4, 4), Vector2(r.end.x - 4, r.position.y + 4), r.end - Vector2(4, 4), Vector2(r.position.x + 4, r.end.y - 4)]))
