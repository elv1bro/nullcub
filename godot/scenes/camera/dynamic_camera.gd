## Динамическая камера боя (CONCEPT.md §7; числа — docs/plan-demo/05-arena.md, раздел «Камера»).
## Стоит на +Z и смотрит в −Z без наклона, fov фиксирован (задаётся в сцене). Каждый кадр:
##   цель   = AABB центров масс живых кукол из группы target_group; для летящих (knockback_until > now,
##            а пока боя нет — скорость ЦМ выше lead_speed) добавляется точка ЦМ + скорость × lead_time;
##            отступ padding со всех сторон;
##   зум    = полувысота кадра на плоскости plane_z: clamp(нужная, min_half_height, высота арены / 2);
##            нужная = max(высота AABB / 2 + padding_y, (ширина AABB / 2 + padding) / аспект);
##            отдаление быстро (постоянная времени zoom_out_tau), приближение медленно (zoom_in_tau);
##            fit_bounds = true (Void, как RM): максимум — наибольший кадр, целиком лежащий в view_bounds() (за стенами
##            и под полом пустоты не видно), max_half_height > 0 — дополнительный потолок;
##   центр  = центр AABB, сглажен (follow_tau) и клэмпнут границами арены (bounds() узла arena_path)
##            с учётом половины кадра; по Z камера отъезжает так, чтобы полувысота соответствовала fov
##            (узкий fov в сцене — почти плоский вид: Void 24°, Руины/Мастерская 45°).
## Новые параметры по умолчанию (padding_y < 0, max_half_height 0, fit_bounds false) поведения не меняют.
## FX для этапа 06/09: shake(m) — тряска с затуханием shake_decay_s, zoom_impulse(frac, s) — короткий зум.
## FX удара (HIT_FX.md §4.2, HitFxDirector), время нескалированное (delta / Engine.time_scale), клэмп fit_bounds действует:
## punch(pos, frac, pull, s) — наезд с подтяжкой центра к точке, roll_kick(deg, s) — крен, focus(target, w, s) — центр кадра
## тянется к ЦМ цели, kick(dir, m, s) — толчок кадра по направлению удара; clear_fx(), fx_idle(). Без вызовов — как раньше.
## v2 (HIT_FX.md §11.3): focus с упреждением — точка фокуса = ЦМ + lead по скорости ЦМ цели (до focus_lead_frac ширины кадра при
## focus_lead_full_speed м/с, сглажено focus_lead_tau): полёт после удара идёт в кадр, а не прижимается к краю. Только внутри focus.
## v3 (HIT_FX.md §12.1): keep_safe(target, s, avoid) — на время крит-полёта цель (AABB мешей её частей на плоскости XY) целиком
## в safe-area кадра safe_rect (вне верхней полосы HUD и нижней полосы подсказки/леттербокса): сначала отъезд (не больше safe_max_zoom_out),
## потом сдвиг центра — поверх клэмпа границ арены (за стеной Void — чёрная пустота). avoid (доли кадра) — ещё одна зона, из которой
## убирается «корпус» цели (голова + торс): карточка KO в ko_crit. После окна сдвиг и отъезд плавно уходят (safe_release_tau).
## Без вызова keep_safe камера прежняя.
## Только поведение: узел Camera3D живёт в scenes/playground.tscn.
class_name DynamicCamera
extends Camera3D

## Узел с методом bounds() -> AABB (RuinsArena). Пусто/нет метода — fallback_bounds.
@export var arena_path: NodePath
@export var fallback_bounds := AABB(Vector3(-16.0, -6.0, -1.0), Vector3(32.0, 18.0, 2.0))
## Сколько метров снизу границ арены не показывать (ямы глубже, чем нужно видеть; ниже — только обрыв фундамента).
## Клэмп центра идёт по урезанным границам, максимум зума — по полной высоте арены (§7: «до всей арены»).
@export var floor_inset := 4.5
@export var target_group := "dolls"
@export var padding := 2.5
## Вертикальный отступ (м) вокруг цели; < 0 — как padding.
@export var padding_y := -1.0
@export var min_half_height := 4.0
## Потолок зума (полувысота, м); 0 — только правило «высота арены / 2» (или fit_bounds).
@export var max_half_height := 0.0
## true: кадр никогда не выходит за view_bounds() — максимум зума = min(высота / 2, ширина / 2 / аспект) границ,
## min_half_height не больше максимума; FX-зум и тряска клэмпятся теми же границами. false: максимум =
## max(высота арены / 2, min_half_height), кадр шире арены центрируется на ней.
@export var fit_bounds := false
@export var zoom_out_tau := 0.15
@export var zoom_in_tau := 0.8
@export var follow_tau := 0.2
@export var lead_time := 0.4
## Порог «летит» (м/с) для упреждения, пока у куклы нет knockback_until.
@export var lead_speed := 4.0
## Плоскость кукол (физика в XY при z=0).
@export var plane_z := 0.0
## Упреждение focus (только FX удара): доля ширины кадра при скорости цели ≥ focus_lead_full_speed; 0 — без упреждения.
@export var focus_lead_frac := 0.18
@export var focus_lead_full_speed := 6.0
@export var focus_lead_tau := 0.08
@export var max_shake := 0.3
@export var shake_decay_s := 0.25
## false — keep_safe ничего не делает (пробы: замер «как в v2» тем же сценарием).
@export var safe_enabled := true
## Safe-area крит-полёта (доли кадра, y — сверху вниз): верх 19 % — панели HUD и леттербокс 11 %, низ 12 % — леттербокс и подсказка.
@export var safe_rect := Rect2(0.03, 0.19, 0.94, 0.69)
## Внутренний запас safe-area для самой камеры (доли кадра): крен кадра до 2–3° и перспектива мешей вне плоскости.
@export var safe_inset := 0.02
@export var safe_max_zoom_out := 0.6
@export var safe_release_tau := 0.25
## Запас (м) вокруг позиции части, если у неё нет мешей.
@export var safe_part_pad := 0.3

## Текущая полувысота кадра (м) и центр на плоскости plane_z — без FX.
var half_height := 0.0
var centre := Vector2.ZERO
var _snapped := false
var _shake_amp := 0.0
var _shake_t := 0.0
var _zoom_frac := 0.0
var _zoom_t := 0.0
var _hh_eff := 0.0
var _centre_eff := Vector2.ZERO
var _time := 0.0
# FX удара (реальные секунды)
var _fx_zoom := 1.0
var _fx_roll := 0.0
var _punch_pos := Vector2.ZERO
var _punch_frac := 0.0
var _punch_pull := 0.0
var _punch_t := 0.0
var _punch_s := 0.0
var _roll_deg := 0.0
var _roll_t := 0.0
var _roll_s := 0.0
var _focus_ref: WeakRef = null
var _focus_w := 0.0
var _focus_t := 0.0
var _focus_s := 0.0
var _focus_lead := Vector2.ZERO
var _kick_dir := Vector2.ZERO
var _kick_m := 0.0
var _kick_t := 0.0
var _kick_s := 0.0
var _safe_ref: WeakRef = null
var _safe_t := 0.0
var _safe_s := 0.0
var _safe_avoid := Rect2()
var _safe_shift := Vector2.ZERO
var _safe_zoom := 1.0


func _ready() -> void:
	current = true


## Сброс сглаживания: следующий кадр камера встаёт точно на цель (после респавна/рестарта).
func snap() -> void:
	_snapped = false


func shake(metres: float) -> void:
	_shake_amp = minf(_shake_amp + metres, max_shake)
	_shake_t = shake_decay_s


func zoom_impulse(frac: float = -0.05, seconds: float = 0.2) -> void:
	_zoom_frac = frac
	_zoom_t = seconds


func bounds() -> AABB:
	var n := get_node_or_null(arena_path)
	if n != null and n.has_method("bounds"):
		return n.bounds()
	return fallback_bounds


## Границы для клэмпа центра: bounds() без floor_inset снизу.
func view_bounds() -> AABB:
	var b := bounds()
	var cut := clampf(floor_inset, 0.0, b.size.y * 0.5)
	return AABB(b.position + Vector3(0, cut, 0), b.size - Vector3(0, cut, 0))


## Видимый прямоугольник на плоскости plane_z (для тестов и HUD).
func frame_rect() -> Rect2:
	var hw := _hh_eff * _aspect()
	return Rect2(_centre_eff - Vector2(hw, _hh_eff), Vector2(hw, _hh_eff) * 2.0)


func _aspect() -> float:
	var s := get_viewport().get_visible_rect().size
	return s.x / s.y if s.y > 0.0 else 16.0 / 9.0


func _flying(n: Node, v: Vector3) -> bool:
	var ku = n.get("knockback_until")
	if ku != null and float(ku) > _time:
		return true
	return v.length() > lead_speed


## Точки цели: ЦМ живых кукол (+ упреждение для летящих). Если живых нет — все.
func _targets() -> Array:
	var alive_pts: Array = []
	var all_pts: Array = []
	for n in get_tree().get_nodes_in_group(target_group):
		if not n.has_method("centre_of_mass"):
			continue
		var com: Vector3 = n.centre_of_mass()
		var v := Vector3.ZERO
		if n.has_method("torso"):
			var t = n.torso()
			if t is RigidBody3D:
				v = t.linear_velocity
		var pts: Array = [Vector2(com.x, com.y)]
		if _flying(n, v):
			pts.append(Vector2(com.x + v.x * lead_time, com.y + v.y * lead_time))
		all_pts += pts
		if n.get("alive") != false:
			alive_pts += pts
	return alive_pts if not alive_pts.is_empty() else all_pts


func _clamp_centre(c: Vector2, hw: float, hh: float, b: AABB) -> Vector2:
	var x0 := b.position.x + hw
	var x1 := b.end.x - hw
	var y0 := b.position.y + hh
	var y1 := b.end.y - hh
	return Vector2(
		(x0 + x1) * 0.5 if x0 > x1 else clampf(c.x, x0, x1),
		(y0 + y1) * 0.5 if y0 > y1 else clampf(c.y, y0, y1))


func _process(delta: float) -> void:
	_time += delta
	var pts := _targets()
	if pts.is_empty():
		return
	var box := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		box = box.expand(p)
	var full := bounds()
	var b := view_bounds()
	var aspect := _aspect()
	var max_h := maxf(full.size.y * 0.5, min_half_height)
	if fit_bounds:
		max_h = minf(b.size.y * 0.5, b.size.x * 0.5 / aspect)
	if max_half_height > 0.0:
		max_h = minf(max_h, max_half_height)
	var min_h := minf(min_half_height, max_h)
	var pad_y := padding if padding_y < 0.0 else padding_y
	var need := maxf(box.size.y * 0.5 + pad_y, (box.size.x * 0.5 + padding) / aspect)
	var target_h := clampf(need, min_h, max_h)
	var target_c := _clamp_centre(box.get_center(), target_h * aspect, target_h, b)
	if not _snapped:
		half_height = target_h
		centre = target_c
		_snapped = true
	else:
		var tau := zoom_out_tau if target_h > half_height else zoom_in_tau
		half_height = lerpf(half_height, target_h, 1.0 - exp(-delta / tau))
		centre = centre.lerp(target_c, 1.0 - exp(-delta / follow_tau))
	var hh := half_height
	if _zoom_t > 0.0:
		_zoom_t -= delta
		hh *= 1.0 + _zoom_frac
	_apply_fx(delta)
	hh *= _fx_zoom
	if fit_bounds:
		hh = minf(hh, max_h)
	_hh_eff = hh
	_centre_eff = _clamp_centre(_fx_centre(centre), hh * aspect, hh, b)
	var off := Vector3.ZERO
	if _shake_t > 0.0:
		_shake_t -= delta
		var k := maxf(_shake_t, 0.0) / shake_decay_s
		off = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * _shake_amp * k
		if _shake_t <= 0.0:
			_shake_amp = 0.0
		if fit_bounds:
			var sc := _clamp_centre(_centre_eff + Vector2(off.x, off.y), hh * aspect, hh, b)
			off = Vector3(sc.x - _centre_eff.x, sc.y - _centre_eff.y, 0.0)
	hh = _apply_safe(FxClock.real_delta(delta), hh, aspect, Vector2(off.x, off.y))
	var dist := hh / tan(deg_to_rad(fov) * 0.5)
	global_transform = Transform3D(_fx_basis(), Vector3(_centre_eff.x, _centre_eff.y, plane_z + dist) + off)


# --- FX удара (HIT_FX.md §4.2) ---

const PUNCH_ATTACK_S := 0.06      # вход наезда (выход — остаток real_s)
const FOCUS_IN_S := 0.12
const FOCUS_OUT_FRAC := 0.35      # последняя доля focus — плавный возврат
const ROLL_ATTACK_S := 0.03


## Наезд: полувысота × (1 + zoom_frac) (−0.08 — ближе на 8 %), центр на pull к world_pos; вход PUNCH_ATTACK_S, выход до real_s.
func punch(world_pos: Vector3, zoom_frac: float, pull: float, real_s: float) -> void:
	if real_s <= 0.0:
		return
	_punch_pos = Vector2(world_pos.x, world_pos.y)
	_punch_frac = zoom_frac if _punch_s <= 0.0 else minf(zoom_frac, _punch_frac * _punch_env())
	_punch_pull = clampf(pull, 0.0, 1.0)
	_punch_t = 0.0
	_punch_s = real_s


## Крен кадра на deg (± — в сторону), быстро входит и затухает за real_s.
func roll_kick(deg: float, real_s: float) -> void:
	if real_s <= 0.0:
		return
	_roll_deg = deg
	_roll_t = 0.0
	_roll_s = real_s


## Центр кадра тянется к цели (centre_of_mass() или global_position) с весом weight на real_s; цель остаётся в кадре.
func focus(target: Node3D, weight: float, real_s: float) -> void:
	if target == null or real_s <= 0.0:
		return
	_focus_ref = weakref(target)
	_focus_w = clampf(weight, 0.0, 1.0)
	_focus_t = 0.0
	_focus_s = real_s


## Толчок кадра на metres вдоль dir (XY), затухает за real_s.
func kick(dir: Vector2, metres: float, real_s: float) -> void:
	if real_s <= 0.0 or dir.length_squared() < 1e-8:
		return
	_kick_dir = dir.normalized()
	_kick_m = metres
	_kick_t = 0.0
	_kick_s = real_s


func clear_fx() -> void:
	_safe_s = 0.0
	_safe_ref = null
	_safe_shift = Vector2.ZERO
	_safe_zoom = 1.0
	_punch_s = 0.0
	_roll_s = 0.0
	_focus_s = 0.0
	_focus_ref = null
	_focus_lead = Vector2.ZERO
	_kick_s = 0.0
	_fx_zoom = 1.0
	_fx_roll = 0.0


func fx_idle() -> bool:
	return _punch_s <= 0.0 and _roll_s <= 0.0 and _focus_s <= 0.0 and _kick_s <= 0.0 and not safe_engaged()


# --- safe-area крит-полёта (HIT_FX.md §12.1) ---

## Держать цель (Doll: меши Doll.parts; иначе Node3D) в safe_rect real_s реальных секунд. avoid — доли кадра (Rect2(), нет зоны).
func keep_safe(target: Node3D, real_s: float, avoid: Rect2 = Rect2()) -> void:
	if target == null or real_s <= 0.0 or not safe_enabled:
		return
	_safe_ref = weakref(target)
	_safe_t = 0.0
	_safe_s = real_s
	_safe_avoid = avoid


## Окно safe идёт (пробы).
func safe_active() -> bool:
	return _safe_s > 0.0 and _safe_target() != null


## Safe ещё влияет на кадр (окно или плавный возврат).
func safe_engaged() -> bool:
	return safe_active() or _safe_shift.length_squared() > 1e-6 or _safe_zoom > 1.0001


## Сдвиг центра (м) и множитель полувысоты от safe сейчас (пробы).
func safe_offset() -> Vector2:
	return _safe_shift


func safe_zoom() -> float:
	return _safe_zoom


func _safe_target() -> Node3D:
	if _safe_ref == null:
		return null
	var n := _safe_ref.get_ref() as Node3D
	if n == null or not is_instance_valid(n) or not n.is_inside_tree():
		return null
	return n


## Прямоугольник цели на плоскости XY (м): AABB мешей частей (Doll.parts), без мешей — позиция части ± safe_part_pad.
## only — базовые имена частей (Doll.part_base_name), пусто — все.
func target_rect(n: Node3D, only: Array = []) -> Rect2:
	var r := Rect2()
	var have := false
	var parts: Variant = n.get("parts")
	var bodies: Array = []
	if parts is Dictionary:
		for k in (parts as Dictionary).keys():
			var b: Variant = (parts as Dictionary)[k]
			if not (b is Node3D) or not is_instance_valid(b):
				continue
			if not only.is_empty() and not only.has(Doll.part_base_name(String(k))):
				continue
			bodies.append(b)
	else:
		bodies.append(n)
	for b in bodies:
		var body := b as Node3D
		var got := false
		for mi in body.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null or not m.visible or m.has_meta("hitfx"):
				continue
			var ab := m.global_transform * m.get_aabb()
			var rr := Rect2(Vector2(ab.position.x, ab.position.y), Vector2(ab.size.x, ab.size.y))
			r = rr if not have else r.merge(rr)
			have = true
			got = true
		if not got:
			var p := body.global_position
			var rr := Rect2(Vector2(p.x, p.y) - Vector2.ONE * safe_part_pad, Vector2.ONE * safe_part_pad * 2.0)
			r = rr if not have else r.merge(rr)
			have = true
	return r


## Safe-area: отъезд и сдвиг центра, чтобы цель легла в safe_rect (минус safe_inset). Возвращает полувысоту кадра.
func _apply_safe(real: float, hh: float, aspect: float, shake: Vector2) -> float:
	if _safe_s <= 0.0 and not safe_engaged():
		return hh
	var tgt := _safe_target()
	if _safe_s > 0.0:
		_safe_t += real
		if _safe_t >= _safe_s or tgt == null:
			_safe_s = 0.0
			_safe_ref = null
			tgt = null
	if tgt == null:
		var k := 1.0 - exp(-real / maxf(safe_release_tau, 1e-3))
		_safe_shift = _safe_shift.lerp(Vector2.ZERO, k)
		_safe_zoom = lerpf(_safe_zoom, 1.0, k)
		if _safe_shift.length() < 0.005 and _safe_zoom < 1.002:
			_safe_shift = Vector2.ZERO
			_safe_zoom = 1.0
		_centre_eff += _safe_shift
		_hh_eff = hh * _safe_zoom
		return _hh_eff
	var box := target_rect(tgt)
	var sr := safe_rect.grow(-safe_inset)
	var zoom := 1.0
	if sr.size.x > 0.01 and sr.size.y > 0.01:
		zoom = maxf(zoom, box.size.y / (2.0 * hh * sr.size.y))
		zoom = maxf(zoom, box.size.x / (2.0 * hh * aspect * sr.size.x))
	zoom = minf(zoom * 1.02 if zoom > 1.0 else 1.0, 1.0 + safe_max_zoom_out)
	var h := hh * zoom
	var hw := h * aspect
	var c := _centre_eff + shake
	var shift := Vector2(_axis_shift(box.position.x, box.end.x, c.x - hw + sr.position.x * 2.0 * hw, c.x - hw + sr.end.x * 2.0 * hw),
		_axis_shift(box.position.y, box.end.y, c.y + h - sr.end.y * 2.0 * h, c.y + h - sr.position.y * 2.0 * h))
	if _safe_avoid.size.x > 0.0 and _safe_avoid.size.y > 0.0:
		shift.x += _avoid_shift(tgt, c + shift, h, hw, sr, box)
	_safe_shift = shift
	_safe_zoom = zoom
	_centre_eff += shift
	_hh_eff = h
	return h


## Сдвиг центра по оси, чтобы [a0, a1] лёг в [s0, s1] (шире — по центру).
static func _axis_shift(a0: float, a1: float, s0: float, s1: float) -> float:
	if a1 - a0 >= s1 - s0:
		return (a0 + a1) * 0.5 - (s0 + s1) * 0.5
	if a0 < s0:
		return a0 - s0
	if a1 > s1:
		return a1 - s1
	return 0.0


## Доп. сдвиг по X: корпус цели (голова + торс) уходит из зоны avoid вбок, если вся цель остаётся в safe-area.
func _avoid_shift(tgt: Node3D, c: Vector2, h: float, hw: float, sr: Rect2, box: Rect2) -> float:
	var core := target_rect(tgt, ["Head", "Torso", "Pelvis"])
	var ax0 := c.x - hw + _safe_avoid.position.x * 2.0 * hw
	var ax1 := c.x - hw + _safe_avoid.end.x * 2.0 * hw
	var ay_top := c.y + h - _safe_avoid.position.y * 2.0 * h
	var ay_bot := c.y + h - _safe_avoid.end.y * 2.0 * h
	if core.end.x <= ax0 or core.position.x >= ax1 or core.end.y <= ay_bot or core.position.y >= ay_top:
		return 0.0
	var sx0 := c.x - hw + sr.position.x * 2.0 * hw
	var sx1 := c.x - hw + sr.end.x * 2.0 * hw
	var best := 0.0
	var best_abs := INF
	# кадр сдвигается на d: зона avoid едет вместе с кадром; корпус левее зоны — d = core.end − ax0 (> 0 — кадр вправо)
	for d in [core.end.x - ax0, core.position.x - ax1]:
		var dd: float = d
		if box.position.x < sx0 + dd - 1e-3 or box.end.x > sx1 + dd + 1e-3:
			continue
		if absf(dd) < best_abs:
			best_abs = absf(dd)
			best = dd
	return best


func _punch_env() -> float:
	if _punch_s <= 0.0:
		return 0.0
	var a := minf(PUNCH_ATTACK_S, _punch_s * 0.4)
	if _punch_t < a:
		var u := _punch_t / a
		return 1.0 - (1.0 - u) * (1.0 - u)
	return 1.0 - smoothstep(0.0, 1.0, (_punch_t - a) / maxf(_punch_s - a, 1e-4))


func _apply_fx(delta: float) -> void:
	if fx_idle():
		_fx_zoom = 1.0
		_fx_roll = 0.0
		return
	var real := FxClock.real_delta(delta)
	_fx_zoom = 1.0
	if _punch_s > 0.0:
		_punch_t += real
		_fx_zoom = 1.0 + _punch_frac * _punch_env()
		if _punch_t >= _punch_s:
			_punch_s = 0.0
	_fx_roll = 0.0
	if _roll_s > 0.0:
		_roll_t += real
		var a := minf(ROLL_ATTACK_S, _roll_s * 0.3)
		var env := _roll_t / a if _roll_t < a else pow(1.0 - clampf((_roll_t - a) / maxf(_roll_s - a, 1e-4), 0.0, 1.0), 2.0)
		_fx_roll = deg_to_rad(_roll_deg) * env
		if _roll_t >= _roll_s:
			_roll_s = 0.0
	if _focus_s > 0.0:
		_focus_t += real
		var ft := _focus_target()
		if _focus_t >= _focus_s or ft == null:
			_focus_s = 0.0
			_focus_ref = null
			_focus_lead = Vector2.ZERO
		else:
			var want := _lead_for(ft)
			_focus_lead = _focus_lead.lerp(want, 1.0 - exp(-real / maxf(focus_lead_tau, 1e-3)))
	if _kick_s > 0.0:
		_kick_t += real
		if _kick_t >= _kick_s:
			_kick_s = 0.0


## Упреждение фокуса (м, XY) сейчас — пробы.
func focus_lead() -> Vector2:
	return _focus_lead if _focus_s > 0.0 else Vector2.ZERO


## Скорость ЦМ цели: Doll/ModularDoll — масса-взвешенная по parts, RigidBody3D — linear_velocity.
static func _target_velocity(n: Node3D) -> Vector3:
	var parts: Variant = n.get("parts")
	if parts is Dictionary:
		var p := Vector3.ZERO
		var m := 0.0
		for b in (parts as Dictionary).values():
			if b is RigidBody3D and is_instance_valid(b):
				p += (b as RigidBody3D).linear_velocity * (b as RigidBody3D).mass
				m += (b as RigidBody3D).mass
		return p / m if m > 0.0 else Vector3.ZERO
	if n is RigidBody3D:
		return (n as RigidBody3D).linear_velocity
	return Vector3.ZERO


func _lead_for(n: Node3D) -> Vector2:
	if focus_lead_frac <= 0.0:
		return Vector2.ZERO
	var v3 := _target_velocity(n)
	var v := Vector2(v3.x, v3.y)
	var sp := v.length()
	if sp < 0.5:
		return Vector2.ZERO
	var width := 2.0 * maxf(half_height, 0.1) * _aspect()
	return v / sp * width * focus_lead_frac * clampf(sp / maxf(focus_lead_full_speed, 0.1), 0.0, 1.0)


func _focus_target() -> Node3D:
	if _focus_ref == null:
		return null
	var n := _focus_ref.get_ref() as Node3D
	if n == null or not is_instance_valid(n) or not n.is_inside_tree():
		return null
	return n


func _focus_env() -> float:
	if _focus_s <= 0.0:
		return 0.0
	var u_in := clampf(_focus_t / FOCUS_IN_S, 0.0, 1.0)
	var out0 := _focus_s * (1.0 - FOCUS_OUT_FRAC)
	var u_out := clampf((_focus_t - out0) / maxf(_focus_s - out0, 1e-4), 0.0, 1.0)
	return smoothstep(0.0, 1.0, u_in) * (1.0 - smoothstep(0.0, 1.0, u_out))


## Центр кадра с FX удара (до клэмпа границами).
func _fx_centre(c: Vector2) -> Vector2:
	if fx_idle():
		return c
	var out := c
	if _punch_s > 0.0:
		out = out.lerp(_punch_pos, _punch_pull * _punch_env())
	var ft := _focus_target()
	if _focus_s > 0.0 and ft != null:
		var p: Vector3 = ft.call("centre_of_mass") if ft.has_method("centre_of_mass") else ft.global_position
		out = out.lerp(Vector2(p.x, p.y) + _focus_lead, _focus_w * _focus_env())
	if _kick_s > 0.0:
		var k := 1.0 - clampf(_kick_t / _kick_s, 0.0, 1.0)
		out += _kick_dir * _kick_m * k * k
	return out


func _fx_basis() -> Basis:
	if absf(_fx_roll) < 1e-6:
		return Basis.IDENTITY
	return Basis(Vector3.BACK, _fx_roll)
