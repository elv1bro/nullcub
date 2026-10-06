## Заставка-стингер Лиги между сценами (docs/plan-demo/look/show.md; пункт «ВИД» show_stinger, группа «Эфир»): короткий «вайп» эфира
## поверх лоадера. Тёмно-синяя шторка с полосами цветов Лиги на косом крае (янтарь, красные, синие, голубой NULL) заезжает слева,
## в центре — знак N0 и NULL GRAVITY, шторка уезжает вправо и открывает кадр. Слой LAYER — над лоадером (Loading, 100).
##   play("full")   — въезд + знак + уход, FULL_S (лоадер закрывается: шторка прячет склейку лоадер → новая сцена);
##   play("reveal") — с закрытого экрана: знак + уход, лоадер открывается за шторкой (REVEAL_FROM_S → FULL_S).
## Вид — чистая функция времени (pose(t)): seek(t) ставит кадр сразу (снимки серии на паузе). Время — без масштаба (лоадер работает и на
## паузе дерева, Engine.time_scale не влияет). Мышь не ловит. Выключенный пункт: не играет, а начатая заставка гаснет сразу.
class_name LeagueStinger
extends CanvasLayer

const ID := &"show_stinger"
const LAYER := 105
const W := 1920.0
const H := 1080.0
const IN_S := 0.28                  # шторка закрыла экран
const HOLD_END_S := 0.5             # знак держится до
const FULL_S := 0.8
const REVEAL_FROM_S := 0.26
const SLANT := 300.0                # px: верх края шторки впереди низа
## полосы на краю шторки: цвет, отступ от края, ширина (px)
const STRIPES := [[ShowTokens.AMBER, 0.0, 54.0], [ShowTokens.TEAM_RED, 66.0, 20.0], [ShowTokens.TEAM_BLUE, 98.0, 14.0],
	[ShowTokens.NULL_BLUE, 124.0, 7.0]]
const NAVY_TOP := Color(0.07, 0.1, 0.19)
const NAVY_BOTTOM := Color(0.016, 0.024, 0.06)
const BADGE := "res://assets/ui/brand/null_gravity_badge_512.png"

var playing := false
var t := 0.0
var plays := 0                      # сколько раз играла (пробы)
var _canvas: Control
var _logo: Control
var _badge: TextureRect
var _word_l: Label
var _word_r: Label
var _live: Label
var _line: ColorRect
var _look: Node


func _init() -> void:
	layer = LAYER
	name = "LeagueStinger"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_look = get_node_or_null("/root/Look")
	_canvas = Control.new()
	_canvas.name = "Wipe"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.position = Vector2.ZERO
	_canvas.size = Vector2(W, H)
	_canvas.draw.connect(_draw_wipe)
	add_child(_canvas)
	_logo = Control.new()
	_logo.name = "Logo"
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.size = Vector2(W, H)
	_logo.pivot_offset = Vector2(W, H) * 0.5
	add_child(_logo)
	_badge = TextureRect.new()
	_badge.texture = load(BADGE)
	_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_badge.size = Vector2(300, 300)
	_badge.position = Vector2(W * 0.5 - 150.0, H * 0.5 - 170.0)
	_badge.pivot_offset = _badge.size * 0.5
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.add_child(_badge)
	# название не переводится (BRAND.md): NULL — белым, GRAVITY — янтарём
	_word_l = _word("NULL", ShowTokens.TEXT, Vector2(W * 0.5 - 150.0 - 620.0, H * 0.5 - 130.0), HORIZONTAL_ALIGNMENT_RIGHT)
	_word_r = _word("GRAVITY", ShowTokens.AMBER, Vector2(W * 0.5 + 150.0 + 10.0, H * 0.5 - 130.0), HORIZONTAL_ALIGNMENT_LEFT)
	_line = ColorRect.new()
	_line.color = ShowTokens.AMBER
	_line.size = Vector2(560, 5)
	_line.position = Vector2(W * 0.5 - 280.0, H * 0.5 + 150.0)
	_line.pivot_offset = _line.size * 0.5
	_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.add_child(_line)
	_live = Label.new()
	_live.text = tr("● ЭФИР ЛИГИ")
	_live.add_theme_font_override("font", ShowTokens.title(600))
	_live.add_theme_font_size_override("font_size", 34)
	_live.add_theme_color_override("font_color", ShowTokens.NULL_BLUE)
	_live.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_live.size = Vector2(800, 50)
	_live.position = Vector2(W * 0.5 - 400.0, H * 0.5 + 166.0)
	_live.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.add_child(_live)
	if _look != null:
		_look.changed.connect(func(id: StringName, on: bool) -> void:
			if id == ID and not on:
				stop())
	stop()


func _word(text: String, colour: Color, pos: Vector2, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", ShowTokens.title(700))
	l.add_theme_font_size_override("font_size", 150)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_y", 6)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = pos
	l.size = Vector2(620, 200)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.add_child(l)
	return l


func enabled() -> bool:
	return _look == null or bool(_look.call("on", ID))


## Сыграть: "full" — въезд, знак, уход; "reveal" — с закрытого экрана (знак, уход). Выключенный пункт — ничего.
func play(kind := "full") -> void:
	if not enabled():
		return
	playing = true
	plays += 1
	visible = true
	seek(REVEAL_FROM_S if kind == "reveal" else 0.0)
	set_process(true)


func stop() -> void:
	playing = false
	visible = false
	set_process(false)


## Поставить кадр заставки на время t (0..FULL_S) сразу.
func seek(time_s: float) -> void:
	t = clampf(time_s, 0.0, FULL_S)
	_pose()


func _process(delta: float) -> void:
	# время без масштаба (хит-стоп / СТАЗИС не тормозят); кадр-рывок загрузки не проматывает заставку
	var dt := clampf(delta / maxf(Engine.time_scale, 0.01), 0.0, 0.05)
	t += dt
	if t >= FULL_S:
		stop()
		return
	_pose()


static func _ease_in_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## Край шторки спереди (front) и сзади (back) по x низа кадра.
func edges() -> Vector2:
	var span := W + SLANT + 140.0
	var front := -SLANT - 140.0 + span * _ease_in_out(t / IN_S)
	var back := -SLANT - 140.0
	if t > HOLD_END_S:
		back += (span + 200.0) * _ease_in_out((t - HOLD_END_S) / (FULL_S - HOLD_END_S))   # +200: полосы позади края тоже уходят
	return Vector2(front, back)


## Насколько экран закрыт шторкой сейчас (0..1, пробы): доля ширины между краями.
func cover() -> float:
	var e := edges()
	return clampf((minf(e.x, W) - maxf(e.y + SLANT, 0.0)) / W, 0.0, 1.0)


func _pose() -> void:
	_canvas.queue_redraw()
	# знак: щелчок с отскоком после того, как шторка закрыла экран, гаснет с уходом шторки
	var k_in := clampf((t - IN_S * 0.7) / 0.16, 0.0, 1.0)
	var k_out := clampf((t - HOLD_END_S) / 0.12, 0.0, 1.0)
	_logo.modulate.a = k_in * (1.0 - k_out)
	var pop := 1.0 + 0.35 * (1.0 - k_in) * (1.0 - k_in) - 0.06 * sin(k_in * PI)
	_badge.scale = Vector2.ONE * pop
	_word_l.position.x = W * 0.5 - 150.0 - 620.0 - 120.0 * (1.0 - k_in) * (1.0 - k_in)
	_word_r.position.x = W * 0.5 + 160.0 + 120.0 * (1.0 - k_in) * (1.0 - k_in)
	_line.scale.x = _ease_in_out((t - IN_S * 0.8) / 0.2)


func _para(x_bottom: float, w: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x_bottom + SLANT, 0.0), Vector2(x_bottom + SLANT + w, 0.0), Vector2(x_bottom + w, H),
		Vector2(x_bottom, H)])


func _draw_wipe() -> void:
	var e := edges()
	var front := e.x
	var back := e.y
	if front <= back:
		return
	# шторка: между задним и передним краем (оба косые), градиент сверху вниз
	var poly := PackedVector2Array([Vector2(back + SLANT, 0.0), Vector2(front + SLANT, 0.0), Vector2(front, H), Vector2(back, H)])
	_canvas.draw_polygon(poly, PackedColorArray([NAVY_TOP, NAVY_TOP, NAVY_BOTTOM, NAVY_BOTTOM]))
	# тонкие косые штрихи по шторке — фактура эфира
	var step := 46.0
	var x := floorf((back - SLANT) / step) * step
	while x < front + SLANT:
		var a := maxf(x, back)
		var b := minf(x + 2.0, front)
		if b > a:
			_canvas.draw_colored_polygon(_para(a, b - a), Color(1, 1, 1, 0.025))
		x += step
	# полосы цветов Лиги: впереди переднего края, пока шторка едет; позади заднего — когда уходит
	for s in STRIPES:
		var c: Color = s[0]
		var off: float = s[1]
		var w: float = s[2]
		if t <= HOLD_END_S + 0.02:
			_canvas.draw_colored_polygon(_para(front + 14.0 + off, w), c)
		if t > HOLD_END_S:
			_canvas.draw_colored_polygon(_para(back - 14.0 - off - w, w), c)
