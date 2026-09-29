## Надпись или графический эффект панели комикса (ребёнок ComicPanel/Letters или ComicPanel/Art/Clip — там обрезается
## по панели). Всё в координатах страницы, время — время кадра ComicShot.
##   sfx      — звукоподражание (BONK!, BAM!): Impact, три слоя обводки, тень, «выстрел» с перелётом масштаба
##   small    — мелкое звукоподражание (tk… tk…)
##   caption  — голос Башни: тёмная табличка, янтарный моноширинный текст, печатается по буквам, курсор мигает
##   emanata  — штрихи испуга вокруг якоря (кукла очнулась)
##   burst    — рваная звезда удара под sfx
##   stars    — звёздочки вокруг головы (после бочки)
##   speed    — горизонтальные линии скорости (рывок), clip
##   focus    — радиальные линии фокуса к точке, clip
## anchor ("hero:Head", "enemy:Chest", "prop:Barrel") — пока панель живая, эффект следует за точкой 3D-кадра.
@tool
class_name ComicLetter
extends Node2D

@export_enum("sfx", "small", "caption", "emanata", "burst", "stars", "speed", "focus") var kind := "sfx"
@export_multiline var text := ""
@export var at := 0.0
## Время исчезновения (≤ at — остаётся до конца).
@export var until := -1.0
@export var anchor := ""
## Положение без якоря: доля bbox панели (0..1).
@export var frac := Vector2(0.5, 0.5)
## Сдвиг от якоря/доли, пиксели страницы.
@export var offset := Vector2.ZERO
@export var angle_deg := 0.0
@export var size := 120.0
@export var fill := Color(1.0, 0.86, 0.2)
@export var outline := Color(0.05, 0.03, 0.02)
@export var outline2 := Color(0.85, 0.16, 0.08)
@export var radius := 120.0
@export var count := 12
## caption: символов в секунду.
@export var cps := 28.0

static var _impact: SystemFont
static var _mono: SystemFont

var _t := -1.0
var _bbox := Rect2()
var _pos_set := false
var _was_on := false


static func impact() -> Font:
	if _impact == null:
		_impact = SystemFont.new()
		_impact.font_names = PackedStringArray(["Impact", "Haettenschweiler", "Arial Black", "Arial"])
		_impact.font_weight = 900
	return _impact


static func mono() -> Font:
	if _mono == null:
		_mono = SystemFont.new()
		_mono.font_names = PackedStringArray(["Menlo", "SF Mono", "Consolas", "Courier New", "DejaVu Sans Mono"])
		_mono.font_weight = 700
	return _mono


## Возвращает true в кадр, когда надпись появилась (страница играет её звук).
func update(t: float, panel: ComicPanel, stage: IntroStage) -> bool:
	_t = t
	_bbox = panel.bbox()
	var on := t >= at and (until <= at or t < until)
	visible = on
	var appeared := on and not _was_on
	_was_on = on
	if not on:
		return false
	if anchor != "" and stage != null:
		var f := stage.project(stage.anchor(anchor))
		if f.x > -0.5:
			position = panel.to_page(f) + offset
			_pos_set = true
	elif not _pos_set or anchor == "":
		position = panel.to_page(frac) + offset
		_pos_set = true
	var a := t - at
	match kind:
		"sfx", "burst":
			# выстрел: 0 → 1.3 за 0.09 с → 1.0 к 0.22 с, лёгкая дрожь
			var s := 1.0
			if a < 0.09:
				s = lerpf(0.2, 1.3, a / 0.09)
			elif a < 0.22:
				s = lerpf(1.3, 1.0, (a - 0.09) / 0.13)
			scale = Vector2.ONE * s
			rotation = deg_to_rad(angle_deg + (sin(a * 60.0) * 2.0 * exp(-a * 8.0)))
		"small", "emanata", "stars":
			scale = Vector2.ONE * minf(1.0, 0.4 + a / 0.12)
			rotation = deg_to_rad(angle_deg)
		_:
			scale = Vector2.ONE
			rotation = deg_to_rad(angle_deg)
	queue_redraw()
	return appeared


func _draw() -> void:
	if _t < 0.0 and not Engine.is_editor_hint():
		return
	var a := maxf(_t - at, 0.0) if _t >= 0.0 else 1.0
	match kind:
		"sfx":
			_draw_sfx(text, int(size), true)
		"small":
			_draw_sfx(text, int(size), false)
		"caption":
			_draw_caption(a)
		"emanata":
			_draw_emanata(a)
		"burst":
			_draw_burst()
		"stars":
			_draw_stars(a)
		"speed":
			_draw_speed(a)
		"focus":
			_draw_focus(a)


func _draw_sfx(s: String, fs: int, heavy: bool) -> void:
	var f := impact()
	var lines := s.split("\n")
	var lh := fs * 0.92
	var y0 := -lh * (lines.size() - 1) * 0.5
	for i in lines.size():
		var ln: String = lines[i]
		var w := f.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := Vector2(-w * 0.5, y0 + i * lh + fs * 0.35)
		if heavy:
			draw_string_outline(f, p + Vector2(fs * 0.06, fs * 0.08), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(fs * 0.34), Color(0, 0, 0, 0.55))
			draw_string_outline(f, p, ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(fs * 0.30), outline)
			draw_string_outline(f, p, ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(fs * 0.13), outline2)
		else:
			draw_string_outline(f, p, ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(fs * 0.22), outline)
		draw_string(f, p, ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fill)
		# блик сверху буквы — полоса светлее заливки
		if heavy:
			draw_string(f, p + Vector2(0, -fs * 0.03), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.18))


func _draw_caption(a: float) -> void:
	var f := mono()
	var fs := int(size)
	var n := text.length() if Engine.is_editor_hint() else clampi(int(a * cps), 0, text.length())
	var shown := text.substr(0, n)
	var full_w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pad := Vector2(fs * 0.7, fs * 0.55)
	var icon := fs * 1.1
	var rect := Rect2(Vector2.ZERO, Vector2(full_w + pad.x * 2.0 + icon + fs * 0.4, fs + pad.y * 2.0))
	rect.position = -rect.size * 0.5
	var grow := clampf(a / 0.12, 0.0, 1.0)
	var r := Rect2(rect.position + Vector2(0, rect.size.y * 0.5 * (1.0 - grow)), Vector2(rect.size.x, rect.size.y * grow))
	draw_rect(r.grow(fs * 0.12), Color(0, 0, 0, 0.55))
	draw_rect(r, Color(0.07, 0.05, 0.045, 0.94))
	draw_rect(r, fill, false, maxf(2.0, fs * 0.08))
	if grow < 1.0:
		return
	# корона Мастера — знак Башни
	var ic := Vector2(rect.position.x + pad.x * 0.8, 0.0)
	var crown := PackedVector2Array([ic + Vector2(0, icon * 0.28), ic + Vector2(0, -icon * 0.18), ic + Vector2(icon * 0.25, icon * 0.05),
		ic + Vector2(icon * 0.5, -icon * 0.3), ic + Vector2(icon * 0.75, icon * 0.05), ic + Vector2(icon, -icon * 0.18), ic + Vector2(icon, icon * 0.28)])
	draw_colored_polygon(crown, fill)
	var tp := Vector2(ic.x + icon + fs * 0.4, fs * 0.36)
	draw_string(f, tp, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fill)
	# курсор-блок мигает, пока печатает, и ещё полсекунды после
	var typing := n < text.length()
	var blink := fmod(a, 0.5) < 0.28
	if typing or (blink and a < float(text.length()) / cps + 1.2):
		var cw := f.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_rect(Rect2(tp + Vector2(cw + fs * 0.08, -fs * 0.78), Vector2(fs * 0.55, fs * 0.9)), fill)


func _draw_emanata(a: float) -> void:
	var k := clampf(a / 0.12, 0.0, 1.0)
	for i in count:
		var ang := -PI * 0.5 + (float(i) / float(count) - 0.5) * PI * 1.25
		var jit := sin(float(i) * 12.9898) * 0.08
		var r0 := radius * (0.95 + jit)
		var r1 := r0 + radius * 0.55 * k * (0.8 + 0.4 * absf(sin(float(i) * 4.1)))
		var dir := Vector2(cos(ang), sin(ang))
		var nrm := Vector2(-dir.y, dir.x)
		var w := radius * 0.07
		var poly := PackedVector2Array([dir * r0 + nrm * w * 0.2, dir * r1 + nrm * w, dir * r1 - nrm * w, dir * r0 - nrm * w * 0.2])
		var big := PackedVector2Array()
		for p in poly:
			big.append(p + (p - dir * (r0 + r1) * 0.5).normalized() * 5.0)
		draw_colored_polygon(big, Color(1, 1, 1, 0.9))
		draw_colored_polygon(poly, outline)


func _draw_burst() -> void:
	var pts := PackedVector2Array()
	var n := count * 2
	for i in n:
		var ang := float(i) / float(n) * TAU
		var r := radius * (1.0 if i % 2 == 0 else 0.55) * (1.0 + 0.18 * sin(float(i) * 7.7))
		pts.append(Vector2(cos(ang), sin(ang) * 0.72) * r)
	var outer := PackedVector2Array()
	for p in pts:
		outer.append(p * 1.08 + p.normalized() * 8.0)
	draw_colored_polygon(outer, outline)
	draw_colored_polygon(pts, fill)
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(p * 0.62)
	draw_colored_polygon(inner, Color(1, 1, 0.92))


func _draw_stars(a: float) -> void:
	for i in count:
		var ph := a * 3.2 + float(i) / float(count) * TAU
		var c := Vector2(cos(ph) * radius, sin(ph) * radius * 0.32)
		var s := radius * 0.2 * (0.8 + 0.3 * sin(ph))
		var star := PackedVector2Array()
		for k in 10:
			var ang := float(k) / 10.0 * TAU - PI * 0.5 + a * 2.0
			var rr := s if k % 2 == 0 else s * 0.42
			star.append(c + Vector2(cos(ang), sin(ang)) * rr)
		var ol := PackedVector2Array()
		for p in star:
			ol.append(c + (p - c) * 1.35)
		draw_colored_polygon(ol, outline)
		draw_colored_polygon(star, fill)


func _draw_speed(a: float) -> void:
	# линии по всей ширине панели, в локальных координатах (узел в центре bbox, rotation — наклон)
	var b := _bbox
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	for i in count:
		var y := rng.randf_range(-0.5, 0.5) * b.size.y * 1.2
		var len := rng.randf_range(0.25, 0.7) * b.size.x
		var x := fmod(rng.randf() * b.size.x * 2.0 - a * b.size.x * 3.5, b.size.x * 2.0) - b.size.x * 0.5
		var w := rng.randf_range(2.0, 7.0)
		draw_line(Vector2(x, y), Vector2(x + len, y), Color(fill.r, fill.g, fill.b, rng.randf_range(0.35, 0.8)), w, true)


func _draw_focus(a: float) -> void:
	var b := _bbox
	var far := b.size.length()
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for i in count:
		var ang := rng.randf() * TAU
		var dir := Vector2(cos(ang), sin(ang))
		var r0 := radius * rng.randf_range(1.0, 1.6)
		var w := rng.randf_range(0.004, 0.012)
		var nrm := Vector2(-dir.y, dir.x)
		var tri := PackedVector2Array([dir * r0, dir * far + nrm * far * w, dir * far - nrm * far * w])
		draw_colored_polygon(tri, Color(outline.r, outline.g, outline.b, 0.55 * clampf(a / 0.15, 0.0, 1.0)))
