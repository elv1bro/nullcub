## Полоса HP (R20 IN-GAME HUD): тёмная подложка с рамкой, заливка цветом игрока с бликом и рисками по 25 HP,
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
var _bg := StyleBoxFlat.new()


func _ready() -> void:
	_bg.bg_color = Color(0.05, 0.045, 0.04, 0.9)
	_bg.border_color = Color(0.32, 0.22, 0.13, 1.0)
	_bg.set_border_width_all(2)
	_bg.set_corner_radius_all(5)
	_bg.shadow_color = Color(0, 0, 0, 0.5)
	_bg.shadow_size = 4
	_bg.shadow_offset = Vector2(0, 2)
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


func _fill_rect(inner: Rect2, value: float) -> Rect2:
	var w := inner.size.x * clampf(value / max_hp, 0.0, 1.0)
	if fill_from_right:
		return Rect2(Vector2(inner.end.x - w, inner.position.y), Vector2(w, inner.size.y))
	return Rect2(inner.position, Vector2(w, inner.size.y))


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	_bg.draw(get_canvas_item(), rect)
	var inner := rect.grow(-3.0)
	# призрак урона: светлая полоса под заливкой
	if _ghost > _shown + 0.01:
		draw_rect(_fill_rect(inner, _ghost), Color(1.0, 0.86, 0.55, 0.85))
	var fill := _fill_rect(inner, _shown)
	if fill.size.x > 0.5:
		var c := colour
		if _pulse > 0.0:
			c = c.lerp(Color(1.0, 0.25, 0.15), 0.5 + 0.5 * sin(_pulse))
		var dark := c.darkened(0.35)
		draw_rect(fill, dark)
		var top := Rect2(fill.position, Vector2(fill.size.x, fill.size.y * 0.55))
		draw_rect(top, c)
		var gloss := Rect2(fill.position + Vector2(0, 1), Vector2(fill.size.x, fill.size.y * 0.28))
		draw_rect(gloss, Color(1, 1, 1, 0.22))
		if _flash > 0.0:
			draw_rect(fill, Color(1, 1, 1, 0.7 * _flash))
	# риски по четвертям
	for i in range(1, 4):
		var x := inner.position.x + inner.size.x * float(i) / 4.0
		draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), Color(0, 0, 0, 0.35), 2.0)
	# рамка поверх (перекрывает край заливки)
	draw_rect(rect.grow(-1.0), Color(0.32, 0.22, 0.13, 1.0), false, 2.0)
