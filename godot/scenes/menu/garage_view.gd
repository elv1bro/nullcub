## Взгляд героя в гараже — от первого лица (06.10, автор: «человек будет как будто мы. Мы должны видеть, как будто не камера идёт
## куда-то при перемещении, а человек наш от первого лица + руки»). Камера гаража — глаза механика (точки CamSpots на высоте глаз,
## tools/build_garage_menu.gd), руки — FpHands.
##
## Переход к точке (move): голова ведёт — поворот догоняет цель быстрее, чем тело доходит; тело идёт шагами: покачивание вверх-вниз
## (по шагу), лёгкий увод вбок и крен. Покачивание и увод — Camera3D.v_offset / h_offset (сдвиг кадра без сдвига узла), крен
## к концу шага сходится к нулю, поэтому в конце перехода камера стоит ровно в точке пункта (пробы сверяют transform). Дальний
## переход идёт дольше (шаг ~2.6 м/с), но не дольше MAX_WALK_S. В покое — дыхание (миллиметры). «Нырок» (ease_in: в экран
## телевизора, к воротам) — без шагов, руки опускаются из кадра.
class_name GarageView
extends Node

const STEP_M := 0.6             # длина шага
const WALK_SPEED := 2.6         # м/с — дальше точка, дольше переход
const MAX_WALK_S := 1.1
const BOB_M := 0.024            # покачивание на шаге
const SWAY_M := 0.011
const ROLL_DEG := 0.55
const HEAD_LEAD := 1.45         # голова доворачивает за 1/HEAD_LEAD времени перехода
const BREATH_M := 0.0035

var cam: Camera3D
var hands: FpHands
## Руки в кадре (false — спрятаны: эфир, мастерская, тёмный экран).
var hands_on := true

var _from := Transform3D()
var _to := Transform3D()
var _fov_from := 50.0
var _fov_to := 50.0
var _t := 1.0
var _dur := 0.75
var _dive := false
var _dist := 0.0
var _steps := 1
var _time := 0.0
var _prev_fwd := Vector3.FORWARD
var _phase := 0.0
var _hands_down := false


func _init(c: Camera3D = null) -> void:
	cam = c


func _ready() -> void:
	hands = FpHands.new()
	hands.name = "Hands"
	cam.add_child(hands)
	_prev_fwd = -cam.global_transform.basis.z


## Перейти к кадру xf (FOV fov) за dur; instant — сразу; ease_in — нырок (разгон к цели, без шагов).
func move(xf: Transform3D, fov: float, dur: float, instant := false, ease_in := false) -> void:
	_from = cam.global_transform
	_to = xf
	_fov_from = cam.fov
	_fov_to = fov
	_dive = ease_in
	var d := Vector2(xf.origin.x - _from.origin.x, xf.origin.z - _from.origin.z).length()
	_dist = d
	_steps = maxi(1, roundi(d / STEP_M))
	_dur = maxf(dur, 0.01)
	if not ease_in and d > 0.05:
		_dur = clampf(maxf(dur, d / WALK_SPEED), dur, maxf(dur, MAX_WALK_S))
	_t = 1.0 if instant else 0.0
	if instant:
		cam.global_transform = _to
		cam.fov = _fov_to
		cam.v_offset = 0.0
		cam.h_offset = 0.0
	if hands != null:
		if ease_in:
			hands.set_pose("down", 0.3)
			_hands_down = true
		elif _hands_down:      # вышли из нырка (эфир, ворота) — руки снова в кадре
			_hands_down = false
			hands.set_pose("rest", 0.45)


func is_moving() -> bool:
	return _t < 1.0


func duration() -> float:
	return _dur


func process(delta: float) -> void:
	_time += delta
	var bob := 0.0
	var side := 0.0
	var walk_amt := 0.0
	if _t < 1.0:
		_t = minf(1.0, _t + delta / _dur)
		var u := _t
		var e_pos := u * u * (3.0 - 2.0 * u)
		var ur := clampf(u * HEAD_LEAD, 0.0, 1.0)
		var e_rot := ur * ur * (3.0 - 2.0 * ur)
		if _dive:
			e_pos = u * u * u
			e_rot = e_pos
		var o := _from.origin.lerp(_to.origin, e_pos)
		var q := _from.basis.get_rotation_quaternion().slerp(_to.basis.get_rotation_quaternion(), e_rot)
		var b := Basis(q)
		if not _dive and _dist > 0.05:
			var env := sin(PI * u)
			var amp := minf(1.0, _dist / 0.5)
			_phase = PI * _steps * u
			bob = absf(sin(_phase)) * BOB_M * amp * env
			side = sin(_phase) * SWAY_M * amp * env
			walk_amt = amp * env
			b = b * Basis(Vector3.BACK, deg_to_rad(sin(_phase) * ROLL_DEG * amp * env))
		cam.global_transform = Transform3D(b, o)
		cam.fov = lerpf(_fov_from, _fov_to, e_pos)
		if _t >= 1.0:
			cam.global_transform = _to
			cam.fov = _fov_to
	# дыхание в покое: кадр чуть дышит, узел камеры стоит
	var breath := sin(_time * 1.55) * BREATH_M * (1.0 - walk_amt)
	cam.v_offset = -bob + breath
	cam.h_offset = side + sin(_time * 0.63) * BREATH_M * 0.4
	if hands != null:
		hands.visible = hands_on and cam.is_current()
		hands.fit_fov(cam.fov)
		hands.walk(_phase, walk_amt)
		var fwd := -cam.global_transform.basis.z
		var yaw_rate := 0.0
		if delta > 0.0:
			yaw_rate = Vector2(_prev_fwd.x, _prev_fwd.z).angle_to(Vector2(fwd.x, fwd.z)) / delta
		_prev_fwd = fwd
		hands.sway(-yaw_rate)


## Руки снова в покое (после нырка, возврата из эфира или мастерской).
func rest_hands(dur := 0.35) -> void:
	hands_on = true
	if hands != null:
		hands.set_pose("rest", dur)
