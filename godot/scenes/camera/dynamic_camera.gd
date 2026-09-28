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
@export var max_shake := 0.3
@export var shake_decay_s := 0.25

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
	if fit_bounds:
		hh = minf(hh, max_h)
	_hh_eff = hh
	_centre_eff = _clamp_centre(centre, hh * aspect, hh, b)
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
	var dist := hh / tan(deg_to_rad(fov) * 0.5)
	global_transform = Transform3D(Basis.IDENTITY, Vector3(_centre_eff.x, _centre_eff.y, plane_z + dist) + off)
