## Логотип финала заставки-комикса: чёрная рваная полоса поперёк страницы, корона, RAGDOLL / MASTER и строка темы.
## Рисуется в координатах страницы вокруг своего origin (узел стоит в центре страницы), масштаб «удара» — у IntroComic.
@tool
class_name ComicTitle
extends Node2D

@export var line1 := "RAGDOLL"
@export var line2 := "MASTER"
@export var tagline := "GRAVITY IS OPTIONAL.  WINNING IS NOT."
@export var size1 := 290.0
@export var size2 := 360.0
@export var gold := Color(1.0, 0.76, 0.26)
@export var cream := Color(0.97, 0.91, 0.78)
@export var red := Color(0.86, 0.19, 0.13)
@export var ink := Color(0.04, 0.03, 0.025)

var _t := 0.0


func play() -> void:
	_t = 0.0


func _process(delta: float) -> void:
	if visible:
		_t += delta
		queue_redraw()


func _draw() -> void:
	var f := ComicLetter.impact()
	# рваная полоса-мазок
	var band := PackedVector2Array()
	var w := 2600.0
	var h := 820.0
	var n := 40
	for i in n + 1:
		var x := -w * 0.5 + w * float(i) / n
		band.append(Vector2(x, -h * 0.5 + sin(float(i) * 2.7) * 22.0 + sin(float(i) * 7.1) * 12.0))
	for i in range(n, -1, -1):
		var x := -w * 0.5 + w * float(i) / n
		band.append(Vector2(x, h * 0.5 + sin(float(i) * 3.3) * 24.0 + sin(float(i) * 5.3) * 10.0))
	draw_colored_polygon(band, Color(ink.r, ink.g, ink.b, 0.86))
	# корона
	var c := Vector2(0, -330)
	var cw := 190.0
	var ch := 120.0
	var crown := PackedVector2Array([c + Vector2(-cw * 0.5, ch * 0.5), c + Vector2(-cw * 0.5, -ch * 0.25), c + Vector2(-cw * 0.25, ch * 0.05),
		c + Vector2(0, -ch * 0.5), c + Vector2(cw * 0.25, ch * 0.05), c + Vector2(cw * 0.5, -ch * 0.25), c + Vector2(cw * 0.5, ch * 0.5)])
	var ol := PackedVector2Array()
	for p in crown:
		ol.append(c + (p - c) * 1.14)
	draw_colored_polygon(ol, ink)
	draw_colored_polygon(crown, gold)
	_line(f, line1, int(size1), Vector2(0, -70), cream, red)
	_line(f, line2, int(size2), Vector2(0, 250), red, cream)
	var m := ComicLetter.mono()
	var ts := 44
	var tw := m.get_string_size(tagline, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x
	var a := clampf((_t - 0.6) / 0.5, 0.0, 1.0) if not Engine.is_editor_hint() else 1.0
	draw_string(m, Vector2(-tw * 0.5, 350), tagline, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, Color(gold.r, gold.g, gold.b, a))


func _line(f: Font, s: String, fs: int, at: Vector2, fill: Color, rim: Color) -> void:
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := at + Vector2(-w * 0.5, 0)
	draw_string_outline(f, p + Vector2(fs * 0.05, fs * 0.07), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(fs * 0.3), Color(0, 0, 0, 0.6))
	draw_string_outline(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(fs * 0.26), ink)
	draw_string_outline(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(fs * 0.1), rim)
	draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fill)
