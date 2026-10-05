## Полоса Заряда под HP (docs/plan-demo/COMBAT_CHARGE.md): голубая заливка 0–100, перезаряд (выше 100) — белый «второй круг» поверх
## голубого, его длина — доля перезаряда (100…150: на 150 вся полоса белая), выдохся — красная заливка с рамкой, мигающей до порога
## возврата (метка на 25). Только рисование; значения задаёт PlayerPanel (из Doll.charge / charge_locked). Анимации идут по
## реальному времени (Time.get_ticks_msec): hit-stop через Engine.time_scale их не замораживает.
class_name ChargeBar
extends Control

const FILL := Color(0.30, 0.82, 0.96)
const OVER := Color(1.0, 1.0, 1.0, 0.95)
const FILL_LOCKED := Color(0.78, 0.24, 0.20)
const FOLLOW_SPEED := 14.0              # 1/с: заливка догоняет значение (плавно, но не отстаёт заметно)

## Заливка от правого края (панели P2/P4 зеркальны).
@export var fill_from_right := false

var charge := 100.0
## Полный запас бойца (set_charge): Tuning.CHARGE_MAX + батареи; заливка 0…cap, выше — перезаряд.
var cap := Tuning.CHARGE_MAX
var locked := false
var _shown := 100.0
var _flash := 0.0
var _pulse := 0.0
var _last_ms := 0
var _bg := StyleBoxFlat.new()


func _ready() -> void:
	_bg.bg_color = Color(0.04, 0.05, 0.06, 0.88)
	_bg.border_color = Color(0.20, 0.30, 0.36, 1.0)
	_bg.set_border_width_all(2)
	_bg.set_corner_radius_all(4)
	_last_ms = Time.get_ticks_msec()
	charge = Tuning.CHARGE_MAX
	_shown = charge


## cap_v — полный запас бойца (Doll.charge_cap: CHARGE_MAX + батареи-модули PartMods); выше него — перезаряд.
func set_charge(value: float, is_locked: bool, cap_v: float = Tuning.CHARGE_MAX) -> void:
	if is_locked and not locked:
		_flash = 1.0   # только что выдохся
	cap = maxf(cap_v, 1.0)
	charge = clampf(value, 0.0, Tuning.CHARGE_OVER_MAX + cap - Tuning.CHARGE_MAX)
	locked = is_locked
	queue_redraw()


## Сразу на значение, без догоняния (сброс матча).
func snap(value: float) -> void:
	charge = value
	_shown = value
	_flash = 0.0
	locked = false
	queue_redraw()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var dt := clampf(float(now - _last_ms) / 1000.0, 0.0, 0.1)
	_last_ms = now
	if absf(_shown - charge) > 0.05:
		_shown = move_toward(_shown, charge, maxf(absf(charge - _shown) * FOLLOW_SPEED, 20.0) * dt)
		queue_redraw()
	if _flash > 0.0:
		_flash = maxf(_flash - dt * 3.0, 0.0)
		queue_redraw()
	if locked:
		_pulse += dt * 7.0
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_style_box(_bg, r)
	var inner := r.grow(-3.0)
	var base := clampf(_shown, 0.0, cap) / cap
	var over := clampf((_shown - cap) / (Tuning.CHARGE_OVER_MAX - Tuning.CHARGE_MAX), 0.0, 1.0)
	var col := FILL
	if locked:
		col = FILL_LOCKED.lerp(Color(1.0, 0.5, 0.4), 0.5 + 0.5 * sin(_pulse))
	_fill(inner, base, col)
	if _shown > cap:
		_fill(inner, over, OVER)
	# метка порога возврата после запора
	var mark_x := inner.position.x + inner.size.x * (Tuning.CHARGE_RESTART / cap if not fill_from_right else 1.0 - Tuning.CHARGE_RESTART / cap)
	draw_line(Vector2(mark_x, inner.position.y), Vector2(mark_x, inner.end.y), Color(0, 0, 0, 0.45), 1.0)
	if _flash > 0.0:
		draw_rect(inner, Color(1.0, 0.35, 0.3, 0.6 * _flash))
	if locked:
		var a := 0.45 + 0.4 * sin(_pulse)
		draw_rect(r, Color(1.0, 0.3, 0.25, a), false, 2.0)


func _fill(area: Rect2, frac: float, col: Color) -> void:
	var w := area.size.x * clampf(frac, 0.0, 1.0)
	if w <= 0.0:
		return
	var x := area.end.x - w if fill_from_right else area.position.x
	draw_rect(Rect2(Vector2(x, area.position.y), Vector2(w, area.size.y)), col)
