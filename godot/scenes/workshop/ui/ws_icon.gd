## Значки мастерской v0.3 (UI/UX spec v0.3): одно семейство линейных иконок вместо эмодзи и символов шрифта (⚡ ↶ ☰ ✎ рисовались
## разными шрифтами, разной толщины и не везде есть в шрифте). Всё рисуется в _draw() в сетке 24×24, масштаб — по меньшей стороне
## узла: одна толщина штриха (stroke в единицах сетки), круглые концы и скругления в изломах, лёгкая заливка — только там, где она
## помогает прочитать форму (молния, гиря, щит, половинки зеркала). Цвет — смысловой (WsStyle: янтарь = энергия / выбрано, зелёный =
## можно, красный = нельзя / удалить, бледно-голубой = разъём), не декоративный.
## Кнопки: add_to_button кладёт значок внутрь Button и резервирует под него место прозрачной иконкой того же размера — текст сдвигает
## сама кнопка (раскладка Godot), значок едет вместе с «нажатой» подложкой. Цвет по умолчанию — значок берёт цвет текста кнопки в
## каждом состоянии (наведение, выбрано — янтарь, выключено — тускло: как у WsStyle.apply_button); свой цвет (янтарная молния,
## красная корзина) держится, у выключенной кнопки тускнеет.
## Полупрозрачный color даёт тёмные точки в изломах (штрих — ломаные + кружки), поэтому «тусклое» — непрозрачным тусклым цветом.
class_name WsIcon
extends Control

const GRID := 24.0
## Излом круче — кружок-скругление и новый кусок ломаной; мельче (дуги по 8°) — одна ломаная без швов.
const SHARP_DEG := 20.0
const ARC_STEP_DEG := 8.0
## Круглые концы и скругления рисуются кружками, а сглаживание Godot 4.7 у линии и у круга разное: перо круга прибавляет к
## радиусу ≈ 0.345 px (от r ≥ 0.875 px; меньше — круг «проваливается»), а линия шириной w выглядит шириной w + AA_LINE_EX(w)
## (замер площади покрытия, w = 1.0, 1.25 … 5.0 px; дальше +0.625). Без поправки концы и изломы — бусины толще штриха.
const AA_LINE_EX := [0.12, 0.155, 0.18, 0.215, 0.256, 0.125, 0.0, -0.047, -0.081, -0.075, -0.044, -0.006, 0.072, 0.175, 0.3,
	0.45, 0.625]
const AA_CIRCLE_EX := 0.345
const AA_CIRCLE_MIN := 0.875
## Порядок — как в листе проверки (tests/ws_icons_sheet.tscn): действия, навигация, категории деталей, служебные.
const NAMES := [
	"energy", "mass", "search", "filter", "physics", "mirror", "duplicate", "delete", "undo", "redo",
	"star", "star_filled", "clock", "all", "gear", "play", "close", "chevron_left", "chevron_right", "chevron_down",
	"help", "save", "folder", "pull", "body", "head", "limb", "joint", "hand", "weapon",
	"armor", "material", "paint", "decor", "check", "warning", "plus", "minus", "socket", "heart",
]
## Выключенная кнопка: значок уходит к цвету тёмного дерева (непрозрачно — см. шапку).
const DIM_TO := Color(0.3, 0.26, 0.22)
const DIM_MIX := 0.6
const DEFAULT_COLOR := Color(0.96, 0.9, 0.78)

static var _spacers: Dictionary = {}      # px -> прозрачная ImageTexture (резерв места под значок в Button)
static var _warned: Dictionary = {}

@export var icon := "energy":
	set(v):
		if icon == v:
			return
		icon = v
		queue_redraw()
@export var color := DEFAULT_COLOR:
	set(v):
		if color == v:
			return
		color = v
		_sync_color()
		queue_redraw()
## Толщина штриха в единицах сетки 24 (2.0 → 2 px при 24 px, 4 px при 48 px).
@export var stroke := 2.0:
	set(v):
		if is_equal_approx(stroke, v):
			return
		stroke = v
		queue_redraw()

## В кнопке: брать цвет текста кнопки по её состоянию (add_to_button ставит, если цвет не задан).
var follow_text := false
## Сколько примитивов нарисовал последний _draw (0 — неизвестное имя: лист проверки валит тест) и их габарит в единицах сетки.
var drawn_primitives := 0
var drawn_bounds := Rect2()

var _btn: Button
var _cur := DEFAULT_COLOR     # цвет с учётом состояния кнопки
var _k := 1.0                 # px на единицу сетки
var _o := Vector2.ZERO        # левый верхний угол сетки в px
var _w := 2.0                 # штрих в px
var _flip := false            # зеркало по X (redo = undo, chevron_right = chevron_left)
var _has_bounds := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cur = color


## Значок px×px (custom_minimum_size — для контейнеров).
static func make(icon_name: String, px := 24.0, col := DEFAULT_COLOR) -> WsIcon:
	var i := WsIcon.new()
	i.icon = icon_name
	i.color = col
	i.custom_minimum_size = Vector2(px, px)
	i.size = Vector2(px, px)
	return i


static func names() -> PackedStringArray:
	return PackedStringArray(NAMES)


## Значок внутрь кнопки. Место под него резервирует прозрачная иконка Button того же размера: текст пустой — значок по центру,
## иначе слева, текст сдвигает сама кнопка (h_separation). Положение пересчитывается на каждой перерисовке кнопки (ресайз,
## наведение, нажатие: «нажатая» подложка опускает содержимое на 2 px — значок вместе с текстом). Повторный вызов меняет значок.
## col по умолчанию (DEFAULT_COLOR) — значок в цвет текста кнопки по состоянию (follow_text); другой — постоянный смысловой цвет.
static func add_to_button(b: Button, icon_name: String, px := 22.0, col := DEFAULT_COLOR) -> WsIcon:
	var n := roundi(px)
	var i: WsIcon = null
	var old: Variant = b.get_meta("ws_icon") if b.has_meta("ws_icon") else null
	if is_instance_valid(old):
		i = old as WsIcon
	if i == null:
		i = WsIcon.new()
		i.name = "WsIcon"
		b.add_child(i, false, Node.INTERNAL_MODE_FRONT)
		b.set_meta("ws_icon", i)
		b.draw.connect(i._sync_button)
	i._btn = b
	i.follow_text = col == DEFAULT_COLOR
	i.icon = icon_name
	i.color = col
	i.custom_minimum_size = Vector2(n, n)
	if not _spacers.has(n):
		_spacers[n] = ImageTexture.create_from_image(Image.create_empty(n, n, false, Image.FORMAT_RGBA8))
	b.icon = _spacers[n]
	b.expand_icon = false
	b.add_theme_constant_override("h_separation", roundi(px * 0.36))
	b.add_theme_constant_override("icon_max_width", 0)
	i._sync_button()
	b.queue_redraw()
	return i


## Подгонка под текущую подложку кнопки — формула раскладки Button (поля стиля состояния, иконка слева / по центру, floor).
func _sync_button() -> void:
	var b := _btn
	if b == null or not is_instance_valid(b):
		return
	var mode := b.get_draw_mode()
	var sb_name := "normal"
	match mode:
		BaseButton.DRAW_PRESSED:
			sb_name = "pressed"
		BaseButton.DRAW_HOVER:
			sb_name = "hover"
		BaseButton.DRAW_DISABLED:
			sb_name = "disabled"
		BaseButton.DRAW_HOVER_PRESSED:
			sb_name = "hover_pressed"
	var sb := b.get_theme_stylebox(sb_name)
	var ml := sb.get_margin(SIDE_LEFT) if sb != null else 0.0
	var mr := sb.get_margin(SIDE_RIGHT) if sb != null else 0.0
	var mt := sb.get_margin(SIDE_TOP) if sb != null else 0.0
	var mb := sb.get_margin(SIDE_BOTTOM) if sb != null else 0.0
	var px := custom_minimum_size.x
	var with_text := b.text != ""
	var want := HORIZONTAL_ALIGNMENT_LEFT if with_text else HORIZONTAL_ALIGNMENT_CENTER
	if b.icon_alignment != want:
		b.icon_alignment = want
	var inner := b.size - Vector2(ml + mr, mt + mb)
	var x := floorf(ml if with_text else ml + (inner.x - px) * 0.5)
	var y := floorf(mt + (inner.y - px) * 0.5)
	# якоря: по вертикали центр, по горизонтали левый край (с текстом) или центр — значок держится и без перерисовки кнопки
	var ax := 0.0 if with_text else 0.5
	anchor_left = ax
	anchor_right = ax
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = x - b.size.x * ax
	offset_right = offset_left + px
	offset_top = y - b.size.y * 0.5
	offset_bottom = offset_top + px
	_sync_color()


func _sync_color() -> void:
	var c := color
	if _btn != null and is_instance_valid(_btn):
		var mode := _btn.get_draw_mode()
		if follow_text:
			var key := "font_color"
			match mode:
				BaseButton.DRAW_NORMAL:
					key = "font_focus_color" if _btn.has_focus() else "font_color"
				BaseButton.DRAW_PRESSED:
					key = "font_pressed_color"
				BaseButton.DRAW_HOVER:
					key = "font_hover_color"
				BaseButton.DRAW_DISABLED:
					key = "font_disabled_color"
				BaseButton.DRAW_HOVER_PRESSED:
					key = "font_hover_pressed_color"
			c = _btn.get_theme_color(key)
		elif mode == BaseButton.DRAW_DISABLED:
			c = Color(color.lerp(DIM_TO, DIM_MIX), color.a)
	if c != _cur:
		_cur = c
		queue_redraw()


# ------------------------------------------------------------------ рисование

func _draw() -> void:
	drawn_primitives = 0
	drawn_bounds = Rect2()
	_has_bounds = false
	_flip = false
	var s := minf(size.x, size.y)
	if s <= 0.0:
		return
	_k = s / GRID
	_o = ((size - Vector2(s, s)) * 0.5).floor()
	_w = maxf(stroke * _k, 1.0)
	match icon:
		"energy":
			_i_energy()
		"mass":
			_i_mass()
		"search":
			_i_search()
		"filter":
			_i_filter()
		"physics":
			_i_physics()
		"mirror":
			_i_mirror()
		"duplicate":
			_i_duplicate()
		"delete":
			_i_delete()
		"undo":
			_i_undo()
		"redo":
			_flip = true
			_i_undo()
		"star":
			_i_star(false)
		"star_filled":
			_i_star(true)
		"clock":
			_i_clock()
		"all":
			_i_all()
		"gear":
			_i_gear()
		"play":
			_i_play()
		"close":
			_i_close()
		"chevron_left":
			_i_chevron_left()
		"chevron_right":
			_flip = true
			_i_chevron_left()
		"chevron_down":
			_path([Vector2(5.5, 9.0), Vector2(12, 15.5), Vector2(18.5, 9.0)])
		"help":
			_i_help()
		"save":
			_i_save()
		"folder":
			_i_folder()
		"pull":
			_i_pull()
		"body":
			_i_body()
		"head":
			_i_head()
		"limb":
			_i_limb()
		"joint":
			_i_joint()
		"hand":
			_i_hand()
		"weapon":
			_i_weapon()
		"armor":
			_i_armor()
		"material":
			_i_material()
		"paint":
			_i_paint()
		"decor":
			_i_decor()
		"check":
			_path([Vector2(4.5, 12.5), Vector2(9.5, 17.5), Vector2(19.5, 6.5)])
		"warning":
			_i_warning()
		"plus":
			_path([Vector2(12, 5), Vector2(12, 19)])
			_path([Vector2(5, 12), Vector2(19, 12)])
		"minus":
			_path([Vector2(5, 12), Vector2(19, 12)])
		"socket":
			_ring(Vector2(12, 12), 7.5)
			_dot(Vector2(12, 12), 3.0)
		"heart":
			_i_heart()
		_:
			if not _warned.has(icon):
				_warned[icon] = true
				push_warning("WsIcon: нет значка «%s»" % icon)


## Запас из деталей (PartHp): сердце из двух дуг и острия — тем же штрихом, с заливкой, как «энергия».
func _i_heart() -> void:
	var p := _arc(Vector2(8.25, 9.5), 4.25, 140.0, 360.0)
	p.append_array(_arc(Vector2(15.75, 9.5), 4.25, 180.0, 400.0))
	p.append(Vector2(12, 20))
	_fill(p, 0.3)
	_path(p, true)


func _i_energy() -> void:
	var p := PackedVector2Array([Vector2(13.5, 2.5), Vector2(4.5, 13.5), Vector2(11.5, 13.5), Vector2(10.5, 21.5),
		Vector2(19.5, 10.5), Vector2(12.5, 10.5)])
	_fill(p, 0.3)
	_path(p, true)


## Масса — гиря-трапеция с кольцом: шире книзу, поэтому не путается с замком (гиря-«кеттлбелл» с дужкой над шаром на 16–20 px
## читалась замком).
func _i_mass() -> void:
	_ring(Vector2(12, 5.3), 2.5)
	var body := _round([Vector2(7.4, 8.8), Vector2(16.6, 8.8), Vector2(21.0, 20.6), Vector2(3.0, 20.6)], 1.8, true)
	_fill(body, 0.45)
	_path(body, true)


func _i_search() -> void:
	_ring(Vector2(10.5, 10.5), 6.5)
	_path([Vector2(15.4, 15.4), Vector2(20.5, 20.5)])


func _i_filter() -> void:
	_path([Vector2(3.5, 4.0), Vector2(20.5, 4.0), Vector2(14.0, 11.8), Vector2(14.0, 20.5), Vector2(10.0, 18.5),
		Vector2(10.0, 11.8)], true)


## Центр масс: круг с залитыми противоположными четвертями и засечки прицела снаружи.
func _i_physics() -> void:
	var c := Vector2(12, 12)
	_pie(c, 7.0, 180.0, 270.0)
	_pie(c, 7.0, 0.0, 90.0)
	_ring(c, 7.0)
	_path([Vector2(12, 2.0), Vector2(12, 4.2)])
	_path([Vector2(12, 19.8), Vector2(12, 22.0)])
	_path([Vector2(2.0, 12), Vector2(4.2, 12)])
	_path([Vector2(19.8, 12), Vector2(22.0, 12)])


## Две половинки к оси: левая — контур (оригинал), правая — с заливкой (копия); ось пунктиром.
func _i_mirror() -> void:
	for y in [[2.5, 4.5], [8.0, 10.0], [14.0, 16.0], [19.5, 21.5]]:
		_path([Vector2(12, y[0]), Vector2(12, y[1])])
	_path([Vector2(3.0, 6.5), Vector2(8.8, 12.0), Vector2(3.0, 17.5)], true)
	var r := PackedVector2Array([Vector2(21.0, 6.5), Vector2(15.2, 12.0), Vector2(21.0, 17.5)])
	_fill(r, 0.4)
	_path(r, true)


func _i_duplicate() -> void:
	_path(_round([Vector2(5.5, 16.0), Vector2(3.0, 16.0), Vector2(3.0, 3.0), Vector2(16.0, 3.0), Vector2(16.0, 5.5)], 2.2))
	_rrect(Rect2(8.0, 8.0, 13.0, 13.0), 2.2)


func _i_delete() -> void:
	_path([Vector2(3.0, 6.0), Vector2(21.0, 6.0)])
	_path(_round([Vector2(8.5, 6.0), Vector2(8.5, 3.0), Vector2(15.5, 3.0), Vector2(15.5, 6.0)], 1.5))
	_path(_round([Vector2(5.5, 6.0), Vector2(6.5, 21.0), Vector2(17.5, 21.0), Vector2(18.5, 6.0)], 2.0))
	_path([Vector2(10.0, 10.5), Vector2(10.0, 16.5)])
	_path([Vector2(14.0, 10.5), Vector2(14.0, 16.5)])


## Стрелка назад по дуге (redo — то же в зеркале).
func _i_undo() -> void:
	_path([Vector2(9.0, 14.0), Vector2(4.0, 9.0), Vector2(9.0, 4.0)])
	var p := PackedVector2Array([Vector2(4.0, 9.0)])
	p.append_array(_arc(Vector2(14.5, 14.5), 5.5, 270.0, 450.0))
	p.append(Vector2(11.0, 20.0))
	_path(p)


func _i_star(filled: bool) -> void:
	var p := PackedVector2Array()
	for i in range(10):
		var a := deg_to_rad(-90.0 + 36.0 * i)
		var r := 9.8 if i % 2 == 0 else 4.9
		p.append(Vector2(12, 12.6) + Vector2(cos(a), sin(a)) * r)
	if filled:
		_fill(p, 1.0)
	_path(p, true)


func _i_clock() -> void:
	_ring(Vector2(12, 12), 9.0)
	_path([Vector2(12, 6.8), Vector2(12, 12), Vector2(15.8, 14.2)])


func _i_all() -> void:
	for o in [Vector2(3.5, 3.5), Vector2(13.5, 3.5), Vector2(3.5, 13.5), Vector2(13.5, 13.5)]:
		_rrect(Rect2(o, Vector2(7, 7)), 1.5)


func _i_gear() -> void:
	var p := PackedVector2Array()
	var c := Vector2(12, 12)
	for i in range(8):
		var a := -90.0 + 45.0 * i
		for q in [[7.3, -15.0], [10.0, -9.0], [10.0, 9.0], [7.3, 15.0], [7.3, 22.5]]:
			var ang := deg_to_rad(a + float(q[1]))
			p.append(c + Vector2(cos(ang), sin(ang)) * float(q[0]))
	_path(p, true)
	_ring(c, 3.0)


func _i_play() -> void:
	var p := PackedVector2Array([Vector2(7.8, 4.5), Vector2(20.0, 12.0), Vector2(7.8, 19.5)])
	_fill(p, 1.0)
	_path(p, true)


func _i_close() -> void:
	_path([Vector2(6, 6), Vector2(18, 18)])
	_path([Vector2(18, 6), Vector2(6, 18)])


func _i_chevron_left() -> void:
	_path([Vector2(14.5, 5.5), Vector2(8.0, 12.0), Vector2(14.5, 18.5)])


func _i_help() -> void:
	_ring(Vector2(12, 12), 9.5)
	var p := _arc(Vector2(12, 9.6), 2.9, 195.0, 380.0)
	p.append_array(_cubic(p[p.size() - 1], Vector2(14.2, 12.2), Vector2(12.1, 12.4), Vector2(12.0, 13.9)).slice(1))
	_path(p)
	_dot(Vector2(12, 17.4), stroke * 0.62)


func _i_save() -> void:
	_path(_round([Vector2(3.0, 3.0), Vector2(15.5, 3.0), Vector2(21.0, 8.5), Vector2(21.0, 21.0), Vector2(3.0, 21.0)], 2.0, true),
		true)
	_path(_round([Vector2(7.0, 21.0), Vector2(7.0, 14.0), Vector2(17.0, 14.0), Vector2(17.0, 21.0)], 1.2))
	_path(_round([Vector2(7.5, 3.0), Vector2(7.5, 7.5), Vector2(14.0, 7.5)], 1.2))


func _i_folder() -> void:
	_path(_round([Vector2(3.0, 4.5), Vector2(9.2, 4.5), Vector2(11.4, 7.5), Vector2(21.0, 7.5), Vector2(21.0, 19.5),
		Vector2(3.0, 19.5)], 2.0, true), true)


## Тяга: курсор тянет за узел детали (линия — «резинка» тяги).
func _i_pull() -> void:
	_ring(Vector2(5.5, 5.5), 2.6)
	_path([Vector2(7.6, 7.4), Vector2(10.4, 9.4)])
	var t := Vector2(11.5, 10.0)
	var cur := PackedVector2Array()
	for q in [Vector2(0, 0), Vector2(0, 10.6), Vector2(2.55, 8.2), Vector2(4.4, 11.9), Vector2(6.1, 11.1), Vector2(4.25, 7.5),
			Vector2(7.65, 7.5)]:
		cur.append(t + q)
	_fill(cur, 0.3)
	_path(cur, true)


## Корпус-бочка с обручами и точкой ядра.
func _i_body() -> void:
	var p := PackedVector2Array([Vector2(7.5, 3.5), Vector2(16.5, 3.5)])
	p.append_array(_quad(Vector2(16.5, 3.5), Vector2(21.5, 12.0), Vector2(16.5, 20.5)).slice(1))
	p.append(Vector2(7.5, 20.5))
	p.append_array(_quad(Vector2(7.5, 20.5), Vector2(2.5, 12.0), Vector2(7.5, 3.5)).slice(1, -1))
	_path(p, true)
	_path(_quad(Vector2(5.4, 8.5), Vector2(12, 9.9), Vector2(18.6, 8.5)))
	_path(_quad(Vector2(5.4, 15.5), Vector2(12, 16.9), Vector2(18.6, 15.5)))
	_dot(Vector2(12, 12.6), 1.5)


## Голова — лицо куклы: овал чуть выше ширины, глаза и ровный рот (без шеи: с ней читалась лампочка).
func _i_head() -> void:
	var p := PackedVector2Array()
	for i in range(48):
		var a := TAU * float(i) / 48.0
		p.append(Vector2(12, 12) + Vector2(cos(a) * 8.0, sin(a) * 9.3))
	_path(p, true)
	_dot(Vector2(9.0, 10.8), 1.35)
	_dot(Vector2(15.0, 10.8), 1.35)
	_path(_quad(Vector2(9.2, 15.6), Vector2(12, 17.0), Vector2(14.8, 15.6)))


## Сегмент конечности: шары-суставы на концах и стержень между ними (двойная линия — объём), как деталь куклы.
func _i_limb() -> void:
	var a := Vector2(6.3, 17.7)
	var b := Vector2(17.7, 6.3)
	var r := 3.3
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	var hw := 1.9
	var t := sqrt(r * r - hw * hw)
	_ring(a, r)
	_ring(b, r)
	_path([a + d * t + n * hw, b - d * t + n * hw])
	_path([a + d * t - n * hw, b - d * t - n * hw])


## Шарнир — петля: ось-втулка с коленами посередине, две створки с винтами.
func _i_joint() -> void:
	_rrect(Rect2(10.0, 2.5, 4.0, 19.0), 2.0)
	_path([Vector2(10.0, 9.5), Vector2(14.0, 9.5)])
	_path([Vector2(10.0, 14.5), Vector2(14.0, 14.5)])
	_path(_round([Vector2(10.0, 5.0), Vector2(3.0, 5.0), Vector2(3.0, 19.0), Vector2(10.0, 19.0)], 1.8))
	_path(_round([Vector2(14.0, 5.0), Vector2(21.0, 5.0), Vector2(21.0, 19.0), Vector2(14.0, 19.0)], 1.8))
	for q in [Vector2(6.6, 9.0), Vector2(6.6, 15.0), Vector2(17.4, 9.0), Vector2(17.4, 15.0)]:
		_dot(q, 1.1)


## Кисть-клешня: шток, ступица и две губки с зацепом внутрь.
func _i_hand() -> void:
	_path([Vector2(12, 2.5), Vector2(12, 5.8)])
	_rrect(Rect2(8.5, 5.8, 7.0, 3.8), 1.4)
	for sx in [1.0, -1.0]:
		var o := Vector2(12, 0)
		var jaw := _cubic(o + Vector2(-2.4 * sx, 9.6), o + Vector2(-7.8 * sx, 11.2), o + Vector2(-9.0 * sx, 17.2),
			o + Vector2(-5.2 * sx, 21.0))
		jaw.append(o + Vector2(-2.4 * sx, 18.6))
		_path(jaw)


## Молот: боёк поперёк рукояти, рукоять по диагонали.
func _i_weapon() -> void:
	var c := Vector2(15.0, 9.0)
	var u := Vector2(0.70710678, 0.70710678)
	var v := Vector2(0.70710678, -0.70710678)
	var head := PackedVector2Array([c - u * 5.5 + v * 2.6, c + u * 5.5 + v * 2.6, c + u * 5.5 - v * 2.6, c - u * 5.5 - v * 2.6])
	_fill(head, 0.3)
	_path(_round(head, 1.0, true), true)
	_path([c - v * 2.6, c - v * 14.2])


## Щит: левая половина чуть залита — объём пластины.
func _i_armor() -> void:
	var p := PackedVector2Array([Vector2(12, 2.8), Vector2(19.5, 5.6), Vector2(19.5, 12.0)])
	p.append_array(_cubic(Vector2(19.5, 12.0), Vector2(19.5, 17.0), Vector2(15.5, 19.8), Vector2(12, 21.4)).slice(1))
	p.append_array(_cubic(Vector2(12, 21.4), Vector2(8.5, 19.8), Vector2(4.5, 17.0), Vector2(4.5, 12.0)).slice(1))
	p.append(Vector2(4.5, 5.6))
	var half := PackedVector2Array([Vector2(12, 2.8), Vector2(12, 21.4)])
	half.append_array(_cubic(Vector2(12, 21.4), Vector2(8.5, 19.8), Vector2(4.5, 17.0), Vector2(4.5, 12.0)).slice(1))
	half.append(Vector2(4.5, 5.6))
	_fill(half, 0.35)
	_path(p, true)


## Материал: кладка из кирпичей (три ряда со сдвигом швов).
func _i_material() -> void:
	_rrect(Rect2(3.0, 4.0, 18.0, 16.0), 1.6)
	_path([Vector2(3.0, 9.33), Vector2(21.0, 9.33)])
	_path([Vector2(3.0, 14.67), Vector2(21.0, 14.67)])
	_path([Vector2(12.0, 4.0), Vector2(12.0, 9.33)])
	_path([Vector2(7.5, 9.33), Vector2(7.5, 14.67)])
	_path([Vector2(16.5, 9.33), Vector2(16.5, 14.67)])
	_path([Vector2(12.0, 14.67), Vector2(12.0, 20.0)])


## Покраска: баллончик с колпачком и облачко брызг.
func _i_paint() -> void:
	_rrect(Rect2(5.0, 10.0, 9.0, 11.0), 2.0)
	_rrect(Rect2(7.5, 6.0, 4.0, 4.0), 1.0)
	_path([Vector2(5.0, 14.5), Vector2(14.0, 14.5)])
	for d in [Vector2(16.8, 7.8), Vector2(19.3, 5.3), Vector2(19.3, 10.3), Vector2(21.3, 7.8)]:
		_dot(d, 1.05)


## Декор: корона.
func _i_decor() -> void:
	var p := PackedVector2Array([Vector2(12, 4.2), Vector2(15.8, 10.2), Vector2(21.0, 6.2), Vector2(18.6, 17.0),
		Vector2(5.4, 17.0), Vector2(3.0, 6.2), Vector2(8.2, 10.2)])
	_fill(p, 0.3)
	_path(p, true)
	_path([Vector2(5.6, 20.6), Vector2(18.4, 20.6)])


func _i_warning() -> void:
	_path(_round([Vector2(12, 3.0), Vector2(21.5, 20.0), Vector2(2.5, 20.0)], 1.8, true), true)
	_path([Vector2(12, 9.0), Vector2(12, 13.2)])
	_dot(Vector2(12, 16.6), stroke * 0.62)


# ------------------------------------------------------------------ примитивы (всё в единицах сетки 24)

func _pt(v: Vector2) -> Vector2:
	if _flip:
		v.x = GRID - v.x
	return _o + v * _k


func _mark(v: Vector2, pad: float) -> void:
	var r := Rect2(v - Vector2(pad, pad), Vector2(pad, pad) * 2.0)
	drawn_bounds = drawn_bounds.merge(r) if _has_bounds else r
	_has_bounds = true


## Штрих по ломаной: куски без резких изломов — одной draw_polyline (без швов сглаживания), в изломах и на концах — кружок
## диаметром в штрих: так все значки получают одинаковые круглые концы и скругления, как у векторной иконки со stroke-linejoin.
func _path(src: PackedVector2Array, closed := false) -> void:
	var pts := src.duplicate()
	if pts.size() < 2:
		return
	if closed and pts[0].distance_to(pts[pts.size() - 1]) > 0.001:
		pts.append(pts[0])
	var m := pts.size()
	var run := PackedVector2Array([pts[0]])
	var joints := PackedVector2Array()
	for i in range(1, m):
		run.append(pts[i])
		var nxt := pts[i + 1] if i < m - 1 else (pts[1] if closed else pts[i])
		var sharp := i < m - 1 and _turn(pts[i - 1], pts[i], nxt) > SHARP_DEG
		if sharp:
			joints.append(pts[i])
		if sharp or i == m - 1:
			_stroke_run(run)
			run = PackedVector2Array([pts[i]])
	joints.append(pts[0])
	if not closed:
		joints.append(pts[m - 1])
	for j in joints:
		_disc(_pt(j), _w * 0.5)


func _stroke_run(run: PackedVector2Array) -> void:
	var px := PackedVector2Array()
	for p in run:
		px.append(_pt(p))
		_mark(p, stroke * 0.5)
	if px.size() == 2:
		draw_line(px[0], px[1], _cur, _w, true)
	else:
		draw_polyline(px, _cur, _w, true)
	drawn_primitives += 1


static func _turn(a: Vector2, b: Vector2, c: Vector2) -> float:
	var d1 := b - a
	var d2 := c - b
	if d1.length_squared() < 1e-8 or d2.length_squared() < 1e-8:
		return 0.0
	return rad_to_deg(absf(d1.angle_to(d2)))


func _ring(c: Vector2, r: float) -> void:
	var p := _arc(c, r, 0.0, 360.0)
	p.remove_at(p.size() - 1)
	_path(p, true)


func _rrect(r: Rect2, radius: float) -> void:
	_path(_round([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)], radius, true), true)


func _fill(src: PackedVector2Array, alpha: float) -> void:
	var px := PackedVector2Array()
	for p in src:
		px.append(_pt(p))
		_mark(p, 0.0)
	draw_colored_polygon(px, Color(_cur, _cur.a * alpha))
	drawn_primitives += 1


func _pie(c: Vector2, r: float, a0: float, a1: float) -> void:
	var p := PackedVector2Array([c])
	p.append_array(_arc(c, r, a0, a1))
	_fill(p, 1.0)


func _dot(c: Vector2, r: float) -> void:
	_disc(_pt(c), r * _k)
	_mark(c, r)


## Круг радиусом r px, видимый как половина штриха шириной 2r (см. AA_LINE_EX): крупный — draw_circle с поправкой на перо,
## мелкий (штрих до ~2.4 px: значки до ~28 px) — кольцо draw_arc шириной r вокруг r/2: сглаживание как у линий, та же толщина.
func _disc(c: Vector2, r: float) -> void:
	var t := (2.0 * r + _aa_line_ex(2.0 * r)) * 0.5 - AA_CIRCLE_EX
	if t >= AA_CIRCLE_MIN:
		draw_circle(c, t, _cur, true, -1.0, true)
	else:
		draw_arc(c, r * 0.5, 0.0, TAU, 16, _cur, r, true)
	drawn_primitives += 1


static func _aa_line_ex(w: float) -> float:
	var f := clampf((w - 1.0) / 0.25, 0.0, float(AA_LINE_EX.size() - 1))
	var i := mini(int(f), AA_LINE_EX.size() - 2)
	return lerpf(float(AA_LINE_EX[i]), float(AA_LINE_EX[i + 1]), f - float(i))


## Точки дуги (углы в градусах, 0 — вправо, по часовой — экранная Y вниз); a1 < a0 — против часовой.
static func _arc(c: Vector2, r: float, a0: float, a1: float) -> PackedVector2Array:
	var n := maxi(2, ceili(absf(a1 - a0) / ARC_STEP_DEG))
	var out := PackedVector2Array()
	for i in range(n + 1):
		var a := deg_to_rad(lerpf(a0, a1, float(i) / float(n)))
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


static func _quad(a: Vector2, c: Vector2, b: Vector2, n := 12) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(n + 1):
		var t := float(i) / float(n)
		out.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
	return out


static func _cubic(a: Vector2, c1: Vector2, c2: Vector2, b: Vector2, n := 14) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(n + 1):
		out.append(a.bezier_interpolate(c1, c2, b, float(i) / float(n)))
	return out


## Скругление углов ломаной радиусом r (у коротких сторон — меньше, чтобы дуги не наезжали): как stroke-linejoin у рамок.
static func _round(src: PackedVector2Array, r: float, closed := false) -> PackedVector2Array:
	var n := src.size()
	var out := PackedVector2Array()
	for i in range(n):
		var p := src[i]
		if not closed and (i == 0 or i == n - 1):
			out.append(p)
			continue
		var prev := src[(i - 1 + n) % n]
		var next := src[(i + 1) % n]
		var d1 := (p - prev).normalized()
		var d2 := (next - p).normalized()
		var turn := absf(d1.angle_to(d2))
		if turn < 0.01:
			out.append(p)
			continue
		var t := minf(r * tan(turn * 0.5), minf(p.distance_to(prev), p.distance_to(next)) * 0.5)
		var rr := t / tan(turn * 0.5)
		var a := p - d1 * t
		var b := p + d2 * t
		var c := p + (d2 - d1).normalized() * (rr / cos(turn * 0.5))
		var a0 := (a - c).angle()
		var da := wrapf((b - c).angle() - a0, -PI, PI)
		var steps := maxi(2, ceili(absf(rad_to_deg(da)) / ARC_STEP_DEG))
		for s in range(steps + 1):
			var ang := a0 + da * float(s) / float(steps)
			out.append(c + Vector2(cos(ang), sin(ang)) * rr)
	return out
