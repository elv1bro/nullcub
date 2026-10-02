## Полоса HP — вид по скину HUD (scripts/ui/hud_skin.gd): трансляция — косая дорожка с заливкой цветом игрока и косыми рисками
## по 25 HP; неон — светящаяся трубка; LED — ряд светодиодных ячеек (fill_from_right — от правого края),
## «призрак» урона (светлая полоса, догоняющая текущее HP с задержкой — читается, сколько сняли одним ударом),
## вспышка белым при ударе, пульс при HP ≤ 20. Анимации идут по реальному времени (Time.get_ticks_msec), поэтому
## hit-stop / slow-mo через Engine.time_scale их не замораживают. Только рисование; значения задаёт PlayerPanel.
class_name HpBar
extends Control

const GHOST_DELAY_S := 0.35
const GHOST_SPEED := 60.0       # HP/с, скорость догоняющего «призрака»
const SHOW_SPEED := 400.0       # HP/с, скорость самой полосы
const LOW_HP := 20.0

@export var colour := Color(0.18, 0.44, 0.87)
@export var max_hp := 100.0
## Заливка от правого края (панели P2/P4 зеркальны).
@export var fill_from_right := false

var hp := 100.0
var _shown := 100.0
var _ghost := 100.0
var _ghost_wait := 0.0
var _flash := 0.0
var _pulse := 0.0
var _last_ms := 0


func _ready() -> void:
	_last_ms = Time.get_ticks_msec()
	hp = max_hp
	_shown = max_hp
	_ghost = max_hp


func set_hp(value: float, animate: bool = true) -> void:
	var v := clampf(value, 0.0, max_hp)
	var dropped := v < hp - 0.01
	hp = v
	if not animate:
		_shown = hp
		_ghost = hp
		_flash = 0.0
	elif dropped:
		_flash = 1.0
		_ghost_wait = GHOST_DELAY_S
	else:
		_ghost = maxf(_ghost, hp)
	queue_redraw()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var dt := clampf(float(now - _last_ms) / 1000.0, 0.0, 0.1)
	_last_ms = now
	var changed := false
	if absf(_shown - hp) > 0.01:
		_shown = move_toward(_shown, hp, SHOW_SPEED * dt)
		changed = true
	if _ghost_wait > 0.0:
		_ghost_wait -= dt
	elif _ghost > hp + 0.01:
		_ghost = move_toward(_ghost, hp, GHOST_SPEED * dt)
		changed = true
	if _flash > 0.0:
		_flash = maxf(_flash - dt * 4.0, 0.0)
		changed = true
	if hp > 0.0 and hp <= LOW_HP:
		_pulse += dt * 6.0
		changed = true
	elif _pulse != 0.0:
		_pulse = 0.0
		changed = true
	if changed:
		queue_redraw()


## Доля полосы value → косая заливка от своего края (от правого — зеркально).
func _fill_poly(value: float) -> PackedVector2Array:
	var h := size.y
	var sk := h * Broadcast.SKEW
	var run := maxf(size.x - sk, 1.0)
	var w := sk + run * clampf(value / max_hp, 0.0, 1.0)
	if fill_from_right:
		return BcStyle.para(Rect2(Vector2(size.x - w, 0.0), Vector2(w, h)), sk, true)
	return BcStyle.para(Rect2(Vector2.ZERO, Vector2(w, h)), sk, false)


func _draw() -> void:
	match HudSkin.id():
		"neon":
			_draw_neon()
		"led":
			_draw_led()
		_:
			_draw_slant()


func _fill_colour() -> Color:
	if _pulse > 0.0:
		return colour.lerp(Color(1.0, 0.25, 0.15), 0.5 + 0.5 * sin(_pulse))
	return colour


## Трансляция: косая дорожка, заливка, блик, косые риски.
func _draw_slant() -> void:
	var h := size.y
	var sk := h * Broadcast.SKEW
	draw_colored_polygon(BcStyle.para(Rect2(Vector2.ZERO, size), sk, fill_from_right), Broadcast.PLATE_LIGHT)
	if _ghost > _shown + 0.01:
		draw_colored_polygon(_fill_poly(_ghost), Color(1.0, 0.9, 0.62, 0.9))
	if _shown > 0.01:
		var fill := _fill_poly(_shown)
		draw_colored_polygon(fill, _fill_colour())
		var k := 0.33
		draw_colored_polygon(PackedVector2Array([fill[0], fill[1], fill[1].lerp(fill[2], k), fill[0].lerp(fill[3], k)]), Color(1, 1, 1, 0.18))
		if _flash > 0.0:
			draw_colored_polygon(fill, Color(1, 1, 1, 0.7 * _flash))
	var run := size.x - sk
	for i in range(1, 4):
		var x := run * float(i) / 4.0
		draw_line(Vector2(x + (0.0 if fill_from_right else sk), 0.0), Vector2(x + (sk if fill_from_right else 0.0), h), Broadcast.PLATE, 3.0)


func _span(value: float, inner: Rect2) -> Rect2:
	var w := inner.size.x * clampf(value / max_hp, 0.0, 1.0)
	if fill_from_right:
		return Rect2(Vector2(inner.end.x - w, inner.position.y), Vector2(w, inner.size.y))
	return Rect2(inner.position, Vector2(w, inner.size.y))


## Неон: тёмная трубка с краем цвета игрока, светящаяся заливка с ореолом, тонкие разрезы по четвертям.
func _draw_neon() -> void:
	var r := Rect2(Vector2.ZERO, size).grow_individual(0, -3, 0, -3)
	var rad := int(r.size.y * 0.5)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.06)
	track.border_color = Color(colour, 0.45)
	track.set_border_width_all(1)
	track.set_corner_radius_all(rad)
	track.anti_aliasing = true
	track.draw(get_canvas_item(), r)
	var inner := r.grow(-3.0)
	if _ghost > _shown + 0.01:
		draw_rect(_span(_ghost, inner), Color(1.0, 0.9, 0.62, 0.55))
	if _shown > 0.01:
		var c := _fill_colour()
		var tube := StyleBoxFlat.new()
		tube.bg_color = c.lerp(Color.WHITE, 0.25)
		tube.set_corner_radius_all(int(inner.size.y * 0.5))
		tube.shadow_color = Color(c, 0.75)
		tube.shadow_size = 10
		tube.anti_aliasing = true
		var f := _span(_shown, inner)
		tube.draw(get_canvas_item(), f)
		draw_rect(Rect2(f.position + Vector2(4, 2), Vector2(maxf(f.size.x - 8.0, 0.0), f.size.y * 0.3)), Color(1, 1, 1, 0.35))
		if _flash > 0.0:
			draw_rect(f, Color(1, 1, 1, 0.7 * _flash))
	for i in range(1, 4):
		var x := inner.position.x + inner.size.x * float(i) / 4.0
		draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), Color(0.02, 0.035, 0.07, 0.9), 2.0)


## LED: ячейки табло; горят — цветом игрока, «призрак» урона — янтарём, погасшие — тускло.
func _draw_led() -> void:
	var cell := 7.0
	var gap := 3.0
	var n := maxi(int((size.x + gap) / (cell + gap)), 1)
	var lit := int(roundf(float(n) * clampf(_shown / max_hp, 0.0, 1.0)))
	var ghost := int(roundf(float(n) * clampf(_ghost / max_hp, 0.0, 1.0)))
	var c := _fill_colour().lerp(Color.WHITE, 0.25)
	var y := 3.0
	var h := size.y - 6.0
	for i in n:
		var k := (n - 1 - i) if fill_from_right else i
		var x := float(k) * (cell + gap)
		var col := Color(colour, 0.13)
		if i < lit:
			col = c if _flash <= 0.0 else c.lerp(Color.WHITE, _flash * 0.7)
			draw_rect(Rect2(x - 2.0, y - 2.0, cell + 4.0, h + 4.0), Color(colour, 0.22))
		elif i < ghost:
			col = Color(HudSkin.LED, 0.85)
		draw_rect(Rect2(x, y, cell, h), col)
