## Круглый портрет игрока (R20): тёмный «деревянный» диск, кольцо цветом игрока, инициалы «P1» — заглушка под фото
## (этап 10: set_photo(texture) рисует текстуру, обрезанную кругом). set_ko() гасит портрет в серый.
## Дерево узлов — scenes/ui/portrait.tscn (диск и кольцо рисуются в _draw, инициалы — дочерний Label).
class_name Portrait
extends Control

const RING_WIDTH := 5.0
const SEGMENTS := 48

@export var colour := Color(0.18, 0.44, 0.87)
@export var initials := "P1":
	set(v):
		initials = v
		if is_node_ready():
			_label.text = v

var photo: Texture2D
var knocked_out := false

@onready var _label: Label = $Initials


func _ready() -> void:
	_label.text = initials
	resized.connect(_on_resized)
	_on_resized()


func _on_resized() -> void:
	_label.add_theme_font_size_override("font_size", int(minf(size.x, size.y) * 0.36))
	queue_redraw()


func set_player(index: int) -> void:
	colour = Tuning.PLAYER_COLORS[clampi(index, 0, Tuning.PLAYER_COLORS.size() - 1)]
	initials = "P%d" % (index + 1)
	queue_redraw()


func set_photo(tex: Texture2D) -> void:
	photo = tex
	_label.visible = tex == null
	queue_redraw()


func set_ko(ko: bool) -> void:
	knocked_out = ko
	modulate = Color(0.55, 0.55, 0.55, 1.0) if ko else Color.WHITE
	queue_redraw()


func _circle(centre: Vector2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(SEGMENTS):
		var a := TAU * float(i) / float(SEGMENTS)
		pts.append(centre + Vector2(cos(a), sin(a)) * radius)
	return pts


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	# тень и тёмная кромка
	draw_circle(c + Vector2(0, 2), r, Color(0, 0, 0, 0.45))
	draw_circle(c, r, Color(0.1, 0.07, 0.05, 1.0))
	# кольцо цветом игрока
	draw_circle(c, r - 2.0, colour)
	var inner_r := r - 2.0 - RING_WIDTH
	# диск: тёплое тёмное дерево с лёгким градиентом (несколько колец)
	draw_circle(c, inner_r, Color(0.16, 0.11, 0.08, 1.0))
	draw_circle(c - Vector2(0, inner_r * 0.25), inner_r * 0.8, Color(0.22, 0.15, 0.1, 0.55))
	draw_circle(c - Vector2(0, inner_r * 0.45), inner_r * 0.45, Color(0.3, 0.21, 0.14, 0.35))
	if photo != null:
		var pts := _circle(c, inner_r)
		var uvs := PackedVector2Array()
		var cols := PackedColorArray()
		for p in pts:
			uvs.append((p - c) / (2.0 * inner_r) + Vector2(0.5, 0.5))
			cols.append(Color.WHITE)
		draw_polygon(pts, cols, uvs, photo)
	# блик сверху и тонкая тёмная кромка внутри кольца
	draw_arc(c, inner_r - 1.5, PI * 1.15, PI * 1.85, 24, Color(1, 1, 1, 0.18), 3.0, true)
	draw_arc(c, inner_r, 0.0, TAU, SEGMENTS, Color(0, 0, 0, 0.5), 1.5, true)
	if knocked_out:
		# крест «выбыл»
		var k := inner_r * 0.45
		draw_line(c + Vector2(-k, -k), c + Vector2(k, k), Color(0.85, 0.15, 0.1, 0.9), 6.0, true)
		draw_line(c + Vector2(-k, k), c + Vector2(k, -k), Color(0.85, 0.15, 0.1, 0.9), 6.0, true)
