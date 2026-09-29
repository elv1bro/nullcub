## Экранные эффекты удара (HIT_FX.md §2.2, §4.2): CanvasLayer 5 — ниже HUD (10), поэтому HUD не инвертируется и не
## засвечивается. Дети из scenes/fx/hit_fx_director.tscn:
##   SpeedLines  — ColorRect + speed_lines.gdshader: v2 — радиальные штрихи от цели (гуще позади полёта), пока она быстрее SPEED_MIN;
##   ImpactFrame — ColorRect + impact_frame.gdshader: кадры-силуэты (mode 0 тёмные силуэты на белом, 1 — белые на тёмно-красном);
##                 v2 (HIT_FX.md §11.4): фигура — маска кукол DollMask (set_mask), фон плоский на любой арене; без маски — порог яркости;
##   Flash       — ColorRect белый: вспышка на N кадров.
## Кадры считаются вызовами _process (1 кадр = 1 отрисовка), а не временем: impact frame ровно 1–2 кадра при любом time_scale.
## Лимит вспышек (HITFX_MAX_FLASHES_PER_S) и интенсивность решает HitFxDirector; здесь только показ.
class_name ScreenFx
extends CanvasLayer

const SPEED_MIN := 2.6          # м/с ЦМ: ниже линий нет
const SPEED_FULL := 4.2         # м/с: полная альфа
const LINES_FADE_MS := 150.0
const LINES_K_FLOOR := 0.5     # v3: доля альфы линий уже на пороге SPEED_MIN (дальше — до 1 к SPEED_FULL)

var flash_frames_shown := 0     # пробы: сколько кадров показана вспышка / инверсия за всё время
var impact_frames_shown := 0
var masked_frames_shown := 0    # из них по маске кукол

@onready var _lines: ColorRect = $SpeedLines
@onready var _impact: ColorRect = $ImpactFrame
@onready var _flash: ColorRect = $Flash

var _flash_left := 0
var _flash_alpha := 0.0
var _impact_seq: Array = []     # режимы по кадрам
var _impact_strength := 1.0
var _lines_target: WeakRef
var _lines_ms := 0.0
var _lines_left := 0.0
var _lines_alpha := 0.0
var _lines_t := 0.0
var _prewarm_left := 0
var _mask: DollMask


func _ready() -> void:
	layer = 5
	for r in [_lines, _impact, _flash]:
		(r as Control).visible = false
		(r as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


## Белая вспышка на frames кадров (альфа alpha).
func flash(alpha: float, frames: int = 1) -> void:
	_flash_alpha = clampf(alpha, 0.0, 1.0)
	_flash_left = maxi(_flash_left, frames)


## Кадры инверсии: modes — по кадру (0 — тёмные силуэты на белом, 1 — белые на тёмно-красном).
func impact_frame(modes: Array = [0, 1], strength: float = 1.0) -> void:
	_impact_seq = modes.duplicate()
	_impact_strength = clampf(strength, 0.0, 1.0)


## Маска кукол для кадров-силуэтов (HitFxDirector создаёт и передаёт).
func set_mask(mask: DollMask) -> void:
	_mask = mask


## Линии скорости вокруг target (Doll или Node3D) на real_ms мс реального времени, альфа alpha при полной скорости.
func speed_lines(target: Node3D, real_ms: float, alpha: float) -> void:
	_lines_target = weakref(target)
	_lines_ms = real_ms
	_lines_left = real_ms
	_lines_alpha = alpha


## Прогрев шейдеров: оба прямоугольника видимы с нулевой силой пару кадров.
func prewarm() -> void:
	_prewarm_left = 2


func clear() -> void:
	_flash_left = 0
	_impact_seq.clear()
	_lines_left = 0.0
	_lines_target = null
	if is_node_ready():
		_flash.visible = false
		_impact.visible = false
		_lines.visible = false


func active() -> bool:
	return _flash_left > 0 or not _impact_seq.is_empty() or _lines_left > 0.0 or _flash.visible or _impact.visible or _lines.visible


func _process(delta: float) -> void:
	var real_ms := FxClock.real_delta(delta) * 1000.0
	# вспышка
	if _flash_left > 0:
		_flash_left -= 1
		_flash.color = Color(1.0, 1.0, 1.0, _flash_alpha)
		_flash.visible = true
		flash_frames_shown += 1
	else:
		_flash.visible = false
	# инверсия
	var im := _impact.material as ShaderMaterial
	if not _impact_seq.is_empty():
		var mode: int = int(_impact_seq.pop_front())
		if im != null:
			im.set_shader_parameter("mode", mode)
			im.set_shader_parameter("strength", _impact_strength)
			var masked := _mask != null and is_instance_valid(_mask) and _mask.active()
			im.set_shader_parameter("use_mask", masked)
			if masked:
				im.set_shader_parameter("mask_tex", _mask.texture())
				masked_frames_shown += 1
		_impact.visible = true
		impact_frames_shown += 1
	elif _prewarm_left > 0:
		if im != null:
			im.set_shader_parameter("strength", 0.0)
		_impact.visible = true
	else:
		_impact.visible = false
	# линии скорости
	_update_lines(real_ms)
	if _prewarm_left > 0:
		_prewarm_left -= 1


func _update_lines(real_ms: float) -> void:
	var lm := _lines.material as ShaderMaterial
	if _lines_left <= 0.0:
		if _prewarm_left > 0 and lm != null:
			lm.set_shader_parameter("alpha", 0.0)
			_lines.visible = true
		else:
			_lines.visible = false
		return
	_lines_left -= real_ms
	_lines_t += real_ms / 1000.0
	var target: Node3D = null
	if _lines_target != null:
		target = _lines_target.get_ref() as Node3D
	var cam := get_viewport().get_camera_3d()
	if target == null or not is_instance_valid(target) or not target.is_inside_tree() or cam == null or lm == null:
		_lines.visible = false
		_lines_left = 0.0
		return
	var pos := target.global_position
	var v := Vector3.ZERO
	if target is Doll:
		pos = (target as Doll).centre_of_mass()
		v = FlightTrail.com_velocity(target as Doll)
	elif target is RigidBody3D:
		v = (target as RigidBody3D).linear_velocity
	var size := get_viewport().get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		_lines.visible = false
		return
	var sp := cam.unproject_position(pos)
	var sp2 := cam.unproject_position(pos + v * 0.1)
	var sdir := sp2 - sp
	var k := clampf((v.length() - SPEED_MIN) / (SPEED_FULL - SPEED_MIN), 0.0, 1.0)
	if v.length() > SPEED_MIN:
		k = LINES_K_FLOOR + (1.0 - LINES_K_FLOOR) * k   # v3 (§12.3): heavy 4 м/с давал k ≈ 0.25 — линий не было видно
	var tail := clampf(_lines_left / LINES_FADE_MS, 0.0, 1.0)
	var a := _lines_alpha * k * tail
	if a <= 0.005 or sdir.length_squared() < 1e-6:
		_lines.visible = false
		return
	lm.set_shader_parameter("centre", sp / size)
	lm.set_shader_parameter("dir", sdir.normalized())
	lm.set_shader_parameter("alpha", a)
	lm.set_shader_parameter("t", _lines_t)
	lm.set_shader_parameter("aspect", size.x / size.y)
	_lines.visible = true
