## Карточка KO (R20 KO CARD; вид по скину HUD — scripts/ui/hud_skin.gd): лёгкое затемнение экрана радиальным градиентом
## (центр 0.1 → край 0.6, чтобы разлёт частей оставался виден), большое «KO!» (трансляция — красная косая плашка, неон —
## красный ореол, LED — красные светодиоды), над ним выбывший («P2», цвет игрока), под ним строка табло «FIGHTER OFFLINE»
## (N0_VOICE.md, п. 4; чернильные брызги assets/ui/splatter.png больше не показываются). show_card(victim, colour): плашки влетают
## scale 2.4 → 1 с отскоком за 0.12 с и трясутся SHAKE_S, подпись проявляется через 0.25 с, вся карточка живёт
## SHOW_S = 1.2 с (последние FADE_S — затухание). Реальное время (Time.get_ticks_msec, Tween.set_ignore_time_scale):
## KO-замедление Engine.time_scale (этап 09) карточку не растягивает. Дерево узлов — scenes/ui/ko_card.tscn.
class_name KoCard
extends Control

const SHOW_S := 1.2
const FADE_S := 0.2
const SHAKE_S := 0.35
const SHAKE_PX := 16.0

@onready var dim: TextureRect = $Dim
@onready var burst: Control = $Burst
@onready var splatter: TextureRect = $Burst/Splatter
@onready var ko_label: Label = $Burst/Ko
@onready var victim_label: Label = $Burst/Victim
@onready var sub: Label = $Sub

var _shake_left := 0.0
var _burst_base := Vector2.ZERO
var _last_ms := 0
var _hide_at_ms := 0
var _tw: Tween
# HIT_FX §3.3 (ko_crit): карточка откладывается на время крупного плана крита и показывается заново
var _defer_until_ms := 0
var _defer_gen := 0
var _last_name := ""
var _last_colour := Color.WHITE


func _ready() -> void:
	dim.texture = dim_texture()
	visible = false
	_last_ms = Time.get_ticks_msec()
	splatter.visible = false
	ko_label.rotation = 0.0
	sub.text = tr("FIGHTER OFFLINE")
	_apply_skin()
	HudSkin.events.changed.connect(func(_id: String) -> void: _apply_skin())


## Затемнение под карточкой — радиальный градиент 256×256. Строится здесь, на главном потоке, а не подресурсом ko_card.tscn: HUD
## грузят в фоне (ResourceLoader с под-потоками — бой кампании при входе в гараж, площадки), а GradientTexture2D, собранный в рабочем
## потоке, достраивает картинку отложенным вызовом на главном, пока поток ещё ставит width / height. Гонка давала «Expected Image data
## size of 256x256x4 … got 65536» (256×64 — высота ещё по умолчанию) и порчу кучи: 05.10 игра падала на первом лоадере (SIGABRT).
static var _dim_tex: GradientTexture2D


static func dim_texture() -> GradientTexture2D:
	if _dim_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		g.colors = PackedColorArray([Color(0, 0, 0, 0.1), Color(0, 0, 0, 0.28), Color(0, 0, 0, 0.6)])
		var t := GradientTexture2D.new()
		t.width = 256
		t.height = 256
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.gradient = g
		_dim_tex = t
	return _dim_tex


func _apply_skin() -> void:
	ko_label.add_theme_stylebox_override("normal", HudSkin.panel("ko"))
	HudSkin.style_label(ko_label, "display", 190, HudSkin.text_for("alert"))
	sub.add_theme_stylebox_override("normal", HudSkin.panel("ko_sub"))
	HudSkin.style_label(sub, "display", 40, HudSkin.text_for("sub"))
	_style_victim()
	_fit(ko_label, 0.0)
	_fit(sub, 190.0)


func _style_victim() -> void:
	victim_label.add_theme_stylebox_override("normal", HudSkin.panel("ko_victim", _last_colour))
	HudSkin.style_label(victim_label, "display", 38, HudSkin.text_colour(), _last_colour)
	_fit(victim_label, -150.0)


## Подогнать прямоугольник подписи под текст (плашка рисуется по всему прямоугольнику) с центром на y от якоря.
func _fit(l: Label, centre_y: float) -> void:
	var m := l.get_minimum_size()
	l.offset_left = -m.x * 0.5
	l.offset_right = m.x * 0.5
	l.offset_top = centre_y - m.y * 0.5
	l.offset_bottom = centre_y + m.y * 0.5
	l.pivot_offset = m * 0.5


## Непрозрачность брызг (0 — без брызг: Void, HUD.ko_splatter_alpha).
func set_splatter_alpha(a: float) -> void:
	splatter.modulate.a = clampf(a, 0.0, 1.0)
	splatter.visible = a > 0.0


## Осталось секунд показа (0, если карточка скрыта) — HUD откладывает панель итогов до конца карточки.
func remaining_s() -> float:
	if _defer_until_ms > 0:   # HIT_FX §3.3: отложенный показ (ko_crit)
		return maxf(float(_defer_until_ms - Time.get_ticks_msec()) / 1000.0, 0.0) + SHOW_S
	if not visible:
		return 0.0
	return maxf(float(_hide_at_ms - Time.get_ticks_msec()) / 1000.0, 0.0)


func show_card(victim_name: String = "", colour: Color = Color.WHITE) -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	visible = true
	_last_name = victim_name
	_last_colour = colour
	modulate = Color.WHITE
	victim_label.visible = victim_name != ""
	victim_label.text = victim_name
	_style_victim()
	dim.modulate = Color(1, 1, 1, 0)
	sub.modulate = Color(1, 1, 1, 0)
	if visible and _shake_left > 0.0:
		burst.position = _burst_base
	_burst_base = burst.position
	burst.scale = Vector2(2.4, 2.4)
	burst.rotation = deg_to_rad(-5.0)
	_shake_left = SHAKE_S
	_hide_at_ms = Time.get_ticks_msec() + int(SHOW_S * 1000.0)
	_tw = create_tween().set_ignore_time_scale(true)
	_tw.set_parallel(true)
	_tw.tween_property(dim, "modulate:a", 1.0, 0.08)
	_tw.tween_property(burst, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_property(burst, "rotation", 0.0, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_property(sub, "modulate:a", 1.0, 0.15).set_delay(0.25)
	_tw.tween_property(self, "modulate:a", 0.0, FADE_S).set_delay(SHOW_S - FADE_S)
	_tw.set_parallel(false)
	_tw.tween_callback(hide)


## HIT_FX §3.3: спрятать карточку сейчас и показать её заново (полные SHOW_S) через real_s реального времени.
## remaining_s() учитывает отложенный показ — итоги матча ждут карточку.
func defer(real_s: float) -> void:
	if not visible and _defer_until_ms == 0:
		return
	if _tw != null and _tw.is_valid():
		_tw.kill()
	visible = false
	_defer_gen += 1
	var gen := _defer_gen
	_defer_until_ms = Time.get_ticks_msec() + int(maxf(real_s, 0.0) * 1000.0)
	get_tree().create_timer(maxf(real_s, 0.0), true, false, true).timeout.connect(func() -> void:
		if gen != _defer_gen or _defer_until_ms == 0:
			return
		_defer_until_ms = 0
		show_card(_last_name, _last_colour))


## Отменить отложенный показ (restart / COUNTDOWN).
func cancel_defer() -> void:
	_defer_gen += 1
	_defer_until_ms = 0


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var dt := clampf(float(now - _last_ms) / 1000.0, 0.0, 0.1)
	_last_ms = now
	if not visible:
		return
	if _shake_left > 0.0:
		_shake_left -= dt
		var k := maxf(_shake_left, 0.0) / SHAKE_S
		burst.position = _burst_base + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * SHAKE_PX * k
	else:
		burst.position = _burst_base
