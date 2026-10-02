## Экранный слой сокрушительного удара (HIT_FX.md §3.1, §4.3): CanvasLayer 30 — выше HUD (10) и ScreenFx директора (5).
## Дерево — scenes/ui/crit_overlay.tscn:
##   Root/SpeedLines  — радиальные линии скорости вокруг жертвы после ката назад (шейдер speed_lines);
##   Root/ScreenCrack — экранные трещины от точки удара (шейдер screen_crack, текстура crack_screen.png);
##   Root/Letterbox   — две чёрные полосы по LETTERBOX_FRAC высоты (въезд/выезд — set_letterbox(k));
##   Root/Caption     — надпись CRUSHING BLOW! в стиле диктора HUD (hud_theme.tres, AnnounceLabel), золото с тёмно-красной обводкой;
##   Root/CutFlash    — кадры-силуэты, белый кадр ката, белая кромка-виньетка (шейдер crit_screen); v2 — силуэты по маске кукол
##                      (set_mask(DollMask), HIT_FX.md §11.4), фон плоский на любой арене.
## Надпись v2 (§11.5): полоса y_frac и множитель масштаба scale_mult задаёт CritCinematic (выбор по детали на экране, уезд после ката).
## v3 (HIT_FX.md §12.3): Root/BgDim (первый ребёнок, под линиями) — затемнение фона в замедлении после ката, вокруг жертвы чисто
## (set_bg_dim, шейдер crit_bg_dim); Root/HitMarker — маркер точки удара 33–150 мс: кольцо и 8 лучей, светлое ядро с тёмной обводкой
## (set_marker, шейдер hit_marker; читается и на белом небе Руин, и на чёрном Void). Узлы создаются в _ready (сцена не менялась).
## Слой пассивный: CritCinematic каждый кадр задаёт состояние сеттерами (всё — функции от мс таймлайна), reset() прячет всё.
## Координаты — в единицах Root (база 1920×1080, stretch canvas_items); to_overlay(px) переводит пиксели вьюпорта.
## flash_events — сколько раз показан кадр инверсии или белый кадр (проба доступности: при flash_intensity 0 — 0).
class_name CritOverlay
extends CanvasLayer

const LETTERBOX_FRAC := 0.11
const CAPTION_TEXT := "CRUSHING BLOW!"
const CAPTION_COLOUR := Color(1.0, 0.8, 0.2)
const CAPTION_OUTLINE := Color(0.32, 0.02, 0.03)
const CAPTION_FONT_SIZE := 150
const CAPTION_OUTLINE_PX := 18
const CAPTION_Y_FRAC := 0.74
const CAPTION_TILT_DEG := -4.0
const CAPTION_START_SCALE := 2.0
const CRACK_TEX_FRAC := 1.35          # размер текстуры экранных трещин × высота экрана
const BG_DIM_SHADER: Shader = preload("res://assets/shaders/fx/crit_bg_dim.gdshader")
const MARKER_SHADER: Shader = preload("res://assets/shaders/fx/hit_marker.gdshader")

@onready var root: Control = $Root
@onready var speed_lines: ColorRect = $Root/SpeedLines
@onready var screen_crack: ColorRect = $Root/ScreenCrack
@onready var letterbox: Control = $Root/Letterbox
@onready var letter_top: ColorRect = $Root/Letterbox/Top
@onready var letter_bottom: ColorRect = $Root/Letterbox/Bottom
@onready var caption: Label = $Root/Caption
@onready var cut_flash: ColorRect = $Root/CutFlash

var flash_events := 0
var _last_invert := 0
var _last_flash := 0.0
var _mask: DollMask
var masked_frames := 0            # пробы: кадров-силуэтов по маске
var bg_dim: ColorRect
var hit_marker: ColorRect


func _ready() -> void:
	bg_dim = _full_rect("BgDim", BG_DIM_SHADER)
	root.move_child(bg_dim, 0)
	hit_marker = _full_rect("HitMarker", MARKER_SHADER)
	root.move_child(hit_marker, caption.get_index())
	caption.text = tr("CRUSHING BLOW!")   # = CAPTION_TEXT; литерал — ключ перевода
	caption.add_theme_color_override("font_color", CAPTION_COLOUR)
	caption.add_theme_color_override("font_outline_color", CAPTION_OUTLINE)
	caption.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	caption.add_theme_constant_override("outline_size", CAPTION_OUTLINE_PX)
	caption.add_theme_constant_override("shadow_offset_x", 6)
	caption.add_theme_constant_override("shadow_offset_y", 8)
	caption.add_theme_font_size_override("font_size", CAPTION_FONT_SIZE)
	reset()


func _full_rect(n: String, sh: Shader) -> ColorRect:
	var r := ColorRect.new()
	r.name = n
	r.visible = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = sh
	r.material = m
	root.add_child(r)
	return r


## Всё спрятано, слой выключен.
func reset() -> void:
	set_bg_dim(Vector2.ZERO, 0.0, 0.0)
	set_marker(Vector2.ZERO, 0.0, 0.0, 0.0)
	set_letterbox(0.0)
	set_crack(Vector2.ZERO, 0.0, 0.0)
	set_caption(-1.0, 0.0, Vector2.ZERO)
	set_screen(0, 0.0, 0.0)
	set_speed_lines(Vector2.ZERO, 0.0, 0.0)
	visible = false
	_last_invert = 0
	_last_flash = 0.0


func begin() -> void:
	_prewarming = false
	visible = true


var _prewarming := false
var _prewarm_left := 0

## Прогрев шейдеров затемнения фона и маркера удара: слой и оба прямоугольника видимы с нулевой силой FRAMES кадров
## (невидимый CanvasLayer не рисуется и не компилирует шейдеры). Если за это время начался крит (begin), прогрев просто кончается.
func prewarm(frames: int = 3) -> void:
	if bg_dim == null or hit_marker == null or not is_inside_tree() or visible:
		return
	_prewarming = true
	_prewarm_left = frames
	visible = true
	var r := area()
	for rect in [bg_dim, hit_marker]:
		var m := (rect as ColorRect).material as ShaderMaterial
		m.set_shader_parameter("rect_size", r)
		m.set_shader_parameter("amount", 0.0)
		m.set_shader_parameter("alpha", 0.0)
		m.set_shader_parameter("radius", 1.0)
		(rect as ColorRect).visible = true
	if not get_tree().process_frame.is_connected(_prewarm_tick):
		get_tree().process_frame.connect(_prewarm_tick)


func _prewarm_tick() -> void:
	_prewarm_left -= 1
	if _prewarm_left > 0:
		return
	get_tree().process_frame.disconnect(_prewarm_tick)
	if _prewarming:
		_prewarming = false
		reset()


func is_idle() -> bool:
	return not visible


func area() -> Vector2:
	var s := root.size if root != null else Vector2.ZERO
	return s if s.x > 1.0 and s.y > 1.0 else Vector2(1920.0, 1080.0)


## Пиксели вьюпорта (Camera3D.unproject_position) → единицы Root.
func to_overlay(px: Vector2) -> Vector2:
	var vp := get_viewport()
	var vs := vp.get_visible_rect().size if vp != null else area()
	if vs.x <= 1.0 or vs.y <= 1.0:
		return px
	return px * area() / vs


## k 0 — полос нет, 1 — полностью въехали.
func set_letterbox(k: float) -> void:
	var s := area()
	var h := s.y * LETTERBOX_FRAC
	k = clampf(k, 0.0, 1.0)
	letterbox.visible = k > 0.0
	letter_top.position = Vector2(0.0, -h + h * k)
	letter_top.size = Vector2(s.x, h)
	letter_bottom.position = Vector2(0.0, s.y - h * k)
	letter_bottom.size = Vector2(s.x, h)


func set_crack(centre: Vector2, progress: float, alpha: float) -> void:
	screen_crack.visible = alpha > 0.0 and progress > 0.0
	if not screen_crack.visible:
		return
	var s := area()
	var m := screen_crack.material as ShaderMaterial
	m.set_shader_parameter("centre", centre)
	m.set_shader_parameter("rect_size", s)
	m.set_shader_parameter("tex_px", s.y * CRACK_TEX_FRAC)
	m.set_shader_parameter("progress", clampf(progress, 0.0, 1.0))
	m.set_shader_parameter("alpha", clampf(alpha, 0.0, 1.0))


func set_mask(mask: DollMask) -> void:
	_mask = mask


## since_ms < 0 — надписи нет; иначе мс от появления: влёт CAPTION_START_SCALE → 1 за in_ms, дрожь shake_px.
## y_frac < 0 — CAPTION_Y_FRAC (доля высоты центра надписи); scale_mult — множитель масштаба (уезд после ката).
func set_caption(since_ms: float, alpha: float, shake: Vector2, in_ms: float = 90.0, y_frac: float = -1.0, scale_mult: float = 1.0) -> void:
	caption.visible = since_ms >= 0.0 and alpha > 0.0
	if not caption.visible:
		return
	var s := area()
	var h := float(CAPTION_FONT_SIZE) * 1.6
	caption.size = Vector2(s.x, h)
	var yf := CAPTION_Y_FRAC if y_frac < 0.0 else y_frac
	caption.position = Vector2(0.0, s.y * yf - h * 0.5) + shake
	caption.pivot_offset = caption.size * 0.5
	var t := clampf(since_ms / maxf(in_ms, 1.0), 0.0, 1.0)
	var e := 1.0 - pow(1.0 - t, 3.0)
	var sc := lerpf(CAPTION_START_SCALE, 1.0, e)
	if t >= 1.0:
		sc = 1.0
	sc *= scale_mult
	caption.scale = Vector2(sc, sc)
	caption.rotation = deg_to_rad(CAPTION_TILT_DEG)
	caption.modulate = Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0))


## invert: 0 нет, 1 — чёрные силуэты на белом, 2 — белые на тёмно-красном; flash — белый кадр; edge — белая кромка.
func set_screen(invert: int, flash: float, edge: float) -> void:
	cut_flash.visible = invert > 0 or flash > 0.0 or edge > 0.0
	var m := cut_flash.material as ShaderMaterial
	var masked := invert > 0 and _mask != null and is_instance_valid(_mask) and _mask.active()
	m.set_shader_parameter("use_mask", masked)
	if masked:
		m.set_shader_parameter("mask_tex", _mask.texture())
		masked_frames += 1
	m.set_shader_parameter("invert", float(invert))
	m.set_shader_parameter("flash", clampf(flash, 0.0, 1.0))
	m.set_shader_parameter("edge", clampf(edge, 0.0, 1.0))
	if (invert > 0 and _last_invert == 0) or (flash > 0.0 and _last_flash <= 0.0):
		flash_events += 1
	_last_invert = invert
	_last_flash = flash


func set_speed_lines(centre: Vector2, amount: float, phase: float) -> void:
	speed_lines.visible = amount > 0.0
	if not speed_lines.visible:
		return
	var m := speed_lines.material as ShaderMaterial
	m.set_shader_parameter("centre", centre)
	m.set_shader_parameter("rect_size", area())
	m.set_shader_parameter("amount", clampf(amount, 0.0, 1.0))
	m.set_shader_parameter("phase", phase)


## v3: затемнение фона amount (0–1) вне круга radius (ед. Root) вокруг centre.
func set_bg_dim(centre: Vector2, amount: float, radius: float) -> void:
	if bg_dim == null:
		return
	bg_dim.visible = amount > 0.0
	if not bg_dim.visible:
		return
	var m := bg_dim.material as ShaderMaterial
	m.set_shader_parameter("centre", centre)
	m.set_shader_parameter("rect_size", area())
	m.set_shader_parameter("amount", clampf(amount, 0.0, 1.0))
	m.set_shader_parameter("radius", maxf(radius, 1.0))


## v3: маркер точки удара — кольцо радиуса radius (ед. Root) с лучами, alpha, phase 0 → 1 (поворот/раскрытие лучей).
func set_marker(centre: Vector2, radius: float, alpha: float, phase: float) -> void:
	if hit_marker == null:
		return
	hit_marker.visible = alpha > 0.0 and radius > 0.0
	if not hit_marker.visible:
		return
	var m := hit_marker.material as ShaderMaterial
	m.set_shader_parameter("centre", centre)
	m.set_shader_parameter("rect_size", area())
	m.set_shader_parameter("radius", radius)
	m.set_shader_parameter("alpha", clampf(alpha, 0.0, 1.0))
	m.set_shader_parameter("phase", clampf(phase, 0.0, 1.0))
