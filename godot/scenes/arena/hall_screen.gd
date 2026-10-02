## Экран тренировочного зала (scenes/arena/training_hall.gd): «HUD как экраны на стенах комнаты» (автор 02.10). Рама — табло кита
## Small_Scoreboard, на нём квадрат с кинескопом (crt_screen.gdshader) и картинкой из своего SubViewport 1024×576 (Control-дерево
## строится здесь в _ready). Три вида (kind):
##   speed  — «СКОРОСТЬ»: число м/с крупно, км/ч, шкала из 24 сегментов, максимум, график последних секунд;
##   impact — «СИЛА УДАРА»: кН крупно, слово по порогам (Tuning.HALL_FORCE_WORDS), шкала, скорость удара и импульс, счётчик и рекорд,
##            столбики последних ударов;
##   dummy  — «МАНЕКЕН»: HP-полоса, последний удар, суммарный урон, удары и нокауты.
## set_data(словарь) — единственный вход: ключи по виду (см. update_*); перерисовка только при изменении. flash() — вспышка рамки
## при новом ударе. Числа порогов и шкал — Tuning.HALL_*.
class_name HallScreen
extends Node3D

const CRT := preload("res://scenes/menu/crt_screen.gdshader")
const SIZE := Vector2i(1024, 576)

@export_enum("speed", "impact", "dummy") var kind := "speed"
@export var width := 4.8
@export var height := 2.7

var _vp: SubViewport
var _root: Control
var _mat: ShaderMaterial
var _quad: MeshInstance3D
var _f_head: Font
var _f_body: Font
var _f_mono: Font
var _l := {}                       # имя → Label
var _segs: Array = []              # ColorRect шкалы
var _bars: Control                 # график / столбики истории
var _hist: Array = []
var _flash := 0.0
var _data := {}
var _dirty := true
var _hp_fill: ColorRect

const COL_BG := Color(0.015, 0.02, 0.045)
const COL_TAG := Color(0.85, 0.12, 0.1)
const COL_AMBER := Color(0.97, 0.76, 0.2)
const COL_CYAN := Color(0.45, 0.9, 1.0)
const COL_DIM := Color(0.5, 0.58, 0.72)
const SEGMENTS := 24


func _ready() -> void:
	_f_head = Flow.make_font("res://assets/fonts/Oswald.ttf", 650)
	_f_body = Flow.make_font("res://assets/fonts/Rubik.ttf", 450)
	_f_mono = Flow.make_font("res://assets/fonts/JetBrainsMono.ttf", 600)
	_vp = SubViewport.new()
	_vp.name = "ScreenViewport"
	_vp.size = SIZE
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_root = Control.new()
	_root.size = Vector2(SIZE)
	_root.clip_contents = true
	_vp.add_child(_root)
	_build()
	_mat = ShaderMaterial.new()
	_mat.shader = CRT
	_mat.set_shader_parameter("screen_tex", _vp.get_texture())
	_mat.set_shader_parameter("boost", 2.2)
	_mat.set_shader_parameter("lines", 300.0)
	var qm := QuadMesh.new()
	qm.size = Vector2(width, height)
	_quad = MeshInstance3D.new()
	_quad.name = "Glass"
	_quad.mesh = qm
	_quad.material_override = _mat
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_quad)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 2.5, 0.0)
		if _root != null:
			_root.modulate = Color.WHITE.lerp(Color(1.5, 1.4, 1.2), _flash)
	if _dirty:
		_dirty = false
		_refresh()


func set_data(d: Dictionary) -> void:
	if d.hash() == _data.hash():
		return
	_data = d.duplicate(true)
	_dirty = true


func flash() -> void:
	_flash = 1.0


# ---------------------------------------------------------------- построение

func _text(s: String, pos: Vector2, px: int, c: Color, font: Font, key := "") -> Label:
	var l := Label.new()
	l.text = s
	l.position = pos
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", c)
	_root.add_child(l)
	if key != "":
		_l[key] = l
	return l


func _rect(pos: Vector2, size: Vector2, c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = size
	r.color = c
	_root.add_child(r)
	return r


func _titles() -> Dictionary:
	return {"speed": ["СКОРОСТЬ", "ТВОЙ ПОЛЁТ · М/С"], "impact": ["СИЛА УДАРА", "ГРУША · ПИК ЗА КАСАНИЕ"],
		"dummy": ["МАНЕКЕН", "СТЕНД ИСПЫТАНИЙ · УРОН"]}


func _build() -> void:
	_rect(Vector2.ZERO, Vector2(SIZE), COL_BG)
	var t: Array = _titles()[kind]
	_rect(Vector2(28, 24), Vector2(210, 58), COL_TAG)
	_text("● LIVE", Vector2(44, 22), 42, Color.WHITE, _f_head)
	_rect(Vector2(238, 24), Vector2(758, 58), Color(0.06, 0.07, 0.11))
	_text(t[0], Vector2(262, 22), 44, Color.WHITE, _f_head)
	_text(t[1], Vector2(560, 36), 22, COL_DIM, _f_mono)
	_rect(Vector2(28, 92), Vector2(968, 3), COL_AMBER)
	match kind:
		"speed":
			_build_speed()
		"impact":
			_build_impact()
		_:
			_build_dummy()


func _segment_bar(y: float) -> void:
	_segs = []
	var w := (968.0 - (SEGMENTS - 1) * 4.0) / SEGMENTS
	for i in SEGMENTS:
		var r := _rect(Vector2(28 + i * (w + 4.0), y), Vector2(w, 34), Color(0.1, 0.12, 0.17))
		_segs.append(r)


func _light_segments(frac: float) -> void:
	var on := int(round(clampf(frac, 0.0, 1.0) * SEGMENTS))
	for i in _segs.size():
		var c: Color
		if i >= on:
			c = Color(0.1, 0.12, 0.17)
		elif i < SEGMENTS * 0.5:
			c = Color(0.25, 0.85, 0.5)
		elif i < SEGMENTS * 0.8:
			c = COL_AMBER
		else:
			c = Color(0.95, 0.25, 0.2)
		(_segs[i] as ColorRect).color = c


func _build_speed() -> void:
	_text("0.0", Vector2(40, 96), 230, Color.WHITE, _f_head, "big")
	_text("М/С", Vector2(560, 196), 56, COL_AMBER, _f_head)
	_text("0 КМ/Ч", Vector2(560, 120), 44, COL_CYAN, _f_mono, "kmh")
	_segment_bar(330)
	_text("МАКС 0.0 М/С", Vector2(32, 372), 34, COL_AMBER, _f_mono, "max")
	_bars = Control.new()
	_bars.position = Vector2(28, 420)
	_bars.size = Vector2(968, 130)
	_bars.draw.connect(_draw_graph)
	_root.add_child(_bars)


func _build_impact() -> void:
	_text("—", Vector2(40, 96), 230, Color.WHITE, _f_head, "big")
	_text("кН", Vector2(560, 196), 56, COL_AMBER, _f_head)
	_text("ЖДУ УДАР", Vector2(560, 112), 56, COL_CYAN, _f_head, "word")
	_segment_bar(330)
	_text("СКОРОСТЬ УДАРА —", Vector2(32, 372), 30, COL_CYAN, _f_mono, "spd")
	_text("УДАРОВ 0 · РЕКОРД —", Vector2(32, 412), 30, COL_AMBER, _f_mono, "rec")
	_bars = Control.new()
	_bars.position = Vector2(560, 372)
	_bars.size = Vector2(436, 180)
	_bars.draw.connect(_draw_history)
	_root.add_child(_bars)


func _build_dummy() -> void:
	_text("HP", Vector2(36, 112), 60, COL_DIM, _f_head)
	_rect(Vector2(130, 124), Vector2(866, 52), Color(0.12, 0.13, 0.18))
	_hp_fill = _rect(Vector2(134, 128), Vector2(858, 44), Color(0.25, 0.85, 0.5))
	_text("100 / 100", Vector2(140, 188), 56, Color.WHITE, _f_head, "hp")
	_text("ПОСЛЕДНИЙ УДАР  —", Vector2(40, 300), 46, COL_CYAN, _f_head, "last")
	_text("ВСЕГО УРОНА  0", Vector2(40, 372), 46, COL_AMBER, _f_head, "total")
	_text("УДАРОВ  0", Vector2(40, 444), 46, Color.WHITE, _f_head, "hits")
	_text("НОКАУТОВ  0", Vector2(540, 444), 46, Color(0.95, 0.35, 0.3), _f_head, "kos")


# ---------------------------------------------------------------- данные → экран

func _refresh() -> void:
	match kind:
		"speed":
			update_speed()
		"impact":
			update_impact()
		_:
			update_dummy()
	if _bars != null:
		_bars.queue_redraw()


## speed: {v: м/с сейчас, vmax: макс, hist: [м/с…]}
func update_speed() -> void:
	var v := float(_data.get("v", 0.0))
	(_l["big"] as Label).text = "%.1f" % v
	(_l["kmh"] as Label).text = "%d КМ/Ч" % roundi(v * 3.6)
	(_l["max"] as Label).text = "МАКС %.1f М/С" % float(_data.get("vmax", 0.0))
	_light_segments(v / Tuning.HALL_SPEED_SCALE_MS)
	_hist = _data.get("hist", [])


## impact: {f_n: пик силы последнего удара, speed, impulse, hits, best_n, hist: [Н…]}
func update_impact() -> void:
	var f := float(_data.get("f_n", 0.0)) / 1000.0
	var any := float(_data.get("f_n", 0.0)) > 0.0
	(_l["big"] as Label).text = "%.1f" % f if any else "—"
	var word := "ЖДУ УДАР"
	var col := COL_CYAN
	if any:
		for w in Tuning.HALL_FORCE_WORDS:
			if f < float(w[0]):
				word = String(w[1])
				break
		col = Color(0.35, 0.9, 0.55) if f < 1.5 else (COL_AMBER if f < 4.0 else (Color(1.0, 0.55, 0.2) if f < 8.0 else Color(1.0, 0.25, 0.2)))
	(_l["word"] as Label).text = word
	(_l["word"] as Label).add_theme_color_override("font_color", col)
	_light_segments(f / Tuning.HALL_FORCE_SCALE_KN if any else 0.0)
	(_l["spd"] as Label).text = "СКОРОСТЬ УДАРА %.1f М/С · ИМПУЛЬС %d Н·С" % [float(_data.get("speed", 0.0)), roundi(float(_data.get("impulse", 0.0)))] if any else "СКОРОСТЬ УДАРА —"
	(_l["rec"] as Label).text = "УДАРОВ %d · РЕКОРД %.1f кН" % [int(_data.get("hits", 0)), float(_data.get("best_n", 0.0)) / 1000.0] if int(_data.get("hits", 0)) > 0 else "УДАРОВ 0 · РЕКОРД —"
	_hist = _data.get("hist", [])


## dummy: {hp, max_hp, alive, last, total, hits, kos}
func update_dummy() -> void:
	var hp := float(_data.get("hp", 100.0))
	var mx := maxf(float(_data.get("max_hp", 100.0)), 1.0)
	var k := clampf(hp / mx, 0.0, 1.0)
	_hp_fill.size.x = 858.0 * k
	_hp_fill.color = Color(0.25, 0.85, 0.5).lerp(Color(0.95, 0.25, 0.2), 1.0 - k)
	(_l["hp"] as Label).text = ("%d / %d" % [roundi(hp), roundi(mx)]) if bool(_data.get("alive", true)) else "НОКАУТ — ВСТАЁТ…"
	var last := float(_data.get("last", 0.0))
	(_l["last"] as Label).text = "ПОСЛЕДНИЙ УДАР  %s" % ("%d" % roundi(last) if last > 0.0 else "—")
	(_l["total"] as Label).text = "ВСЕГО УРОНА  %d" % roundi(float(_data.get("total", 0.0)))
	(_l["hits"] as Label).text = "УДАРОВ  %d" % int(_data.get("hits", 0))
	(_l["kos"] as Label).text = "НОКАУТОВ  %d" % int(_data.get("kos", 0))


func _draw_graph() -> void:
	var sz := _bars.size
	_bars.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.04, 0.05, 0.09))
	_bars.draw_line(Vector2(0, sz.y - 1), Vector2(sz.x, sz.y - 1), Color(1, 1, 1, 0.2), 2.0)
	if _hist.size() < 2:
		return
	var pts := PackedVector2Array()
	for i in _hist.size():
		var x := sz.x * float(i) / float(_hist.size() - 1)
		var y := sz.y - 8.0 - (sz.y - 16.0) * clampf(float(_hist[i]) / Tuning.HALL_SPEED_SCALE_MS, 0.0, 1.0)
		pts.append(Vector2(x, y))
	_bars.draw_polyline(pts, COL_CYAN, 3.0, true)


func _draw_history() -> void:
	var sz := _bars.size
	var n := mini(_hist.size(), 8)
	if n == 0:
		return
	var w := (sz.x - (8 - 1) * 8.0) / 8.0
	for i in n:
		var f: float = float(_hist[_hist.size() - n + i]) / 1000.0
		var h := (sz.y - 6.0) * clampf(f / Tuning.HALL_FORCE_SCALE_KN, 0.04, 1.0)
		var c := Color(0.35, 0.9, 0.55) if f < 1.5 else (COL_AMBER if f < 4.0 else (Color(1.0, 0.55, 0.2) if f < 8.0 else Color(1.0, 0.25, 0.2)))
		_bars.draw_rect(Rect2(i * (w + 8.0), sz.y - h, w, h), c)
