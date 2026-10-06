## Нейрошлем механика (06.10, автор: «добавь VR-гарнитуру на мастерской — как бы через неё управляют всем; рядом место отдельное
## для этого»; лор — LORE_V2 §2а п. 2–3: механик подключается к кукле для тестов, «нейро-шлем + очки/визор, быт, не киберпанк»).
## Шлем (Props/Headset, модель Garage_NeuroHeadset) лежит на подставке консоли связи (Props/LinkConsole) на правом краю верстака,
## рядом — кресло пилота. Мастерская — это то, что герой видит через шлем: вход в неё — надеть шлем, выход — снять.
##
## put_on(): шаги к верстаку (точка CamSpots/Pilot) → руки тянутся к шлему → хват → шлем разворачивается визором вперёд и идёт
## к лицу → окно визора сжимается (visor.gdshader) → чернота и загрузка «NULL LINK» — в этот момент зовётся on_sealed (мастерская
## берёт камеру) → окно открывается уже в мастерской → on_done.
## take_off(): чернота «связь закрыта» поверх мастерской → on_sealed (камера гаража у верстака, шлем у лица) → окно открывается,
## руки снимают шлем, разворачивают и кладут на подставку → руки в покой → on_done.
## visor_on(): только окно и загрузка, без шагов и рук (мастерская кампании открывается прямо из эфира).
## Любая клавиша или кнопка во время ритуала — ускорить в SKIP_SPEED раз.
class_name GarageHeadset
extends Node

const PILOT_SPOT := "Pilot"
const SKIP_SPEED := 3.0
## Шлем у лица в кадре камеры — конец подъёма, здесь окно визора уже закрыло кадр: визор вперёд (модель смотрит визором в +Z →
## поворот на 180°), чуть наклонён к лицу. Дальше (на голову) — под чернотой, его не видно.
const FACE := Vector3(0.0, 0.0, -0.3)
const FACE_TILT_DEG := -14.0
const LIFT_MID := Vector3(0.0, -0.1, -0.42)
const REACH_S := 0.32
const GRIP_S := 0.14
const LIFT_S := 0.62
const BOOT_S := 0.55
const REVEAL_S := 0.38
const OFF_BLACK_S := 0.22
const OFF_LOWER_S := 0.42
const OFF_PLACE_S := 0.42

var garage: Node3D                  # GarageMenu
var view: GarageView
var headset: Node3D
var rest_parent: Node
var rest_xf := Transform3D()
var worn := false
var busy := false
var seq := ""                       # "" | on | off | visor
var overlay: CanvasLayer
var shade: ColorRect
var boot: Control
var boot_title: Label
var boot_line: Label
var boot_bar: ColorRect

var _clock := 0.0
var _speed := 1.0
var _marks := {}
var _done_marks := {}
var _on_sealed := Callable()
var _on_done := Callable()
var _walk_s := 0.7
var _lift_from := Transform3D()
var _carry := false


func _init(g: Node3D = null) -> void:
	garage = g


func _ready() -> void:
	view = garage.get("view") as GarageView
	headset = garage.get_node_or_null("Props/Headset") as Node3D
	if headset != null:
		rest_parent = headset.get_parent()
		rest_xf = headset.global_transform
	_build_overlay()


func has_headset() -> bool:
	return headset != null


## Шлем снят без ритуала (мастерская кампании закрылась сразу, в эфир): визор открыт, руки снова в кадре.
func reset() -> void:
	busy = false
	seq = ""
	worn = false
	_carry = false
	overlay.visible = false
	_set_open(1.6)
	_set_black(0.0)
	view.rest_hands(0.0)


## Надеть шлем: on_sealed — когда кадр чёрный (отдать камеру мастерской), on_done — когда окно визора открылось.
func put_on(on_sealed: Callable, on_done: Callable) -> void:
	_start("on", on_sealed, on_done)
	var spots: Dictionary = garage.get("spots")
	var fovs: Dictionary = garage.get("spot_fov")
	if spots.has(PILOT_SPOT):
		view.move(spots[PILOT_SPOT], float(fovs[PILOT_SPOT]), 0.7)
	_walk_s = view.duration() if spots.has(PILOT_SPOT) else 0.0
	view.rest_hands(0.25)
	_marks = {"reach": _walk_s * 0.55, "grip": _walk_s + REACH_S * 0.6, "lift": _walk_s + REACH_S * 0.6 + GRIP_S,
		"sealed": _walk_s + REACH_S * 0.6 + GRIP_S + LIFT_S}
	_marks["reveal"] = float(_marks["sealed"]) + BOOT_S
	_marks["done"] = float(_marks["reveal"]) + REVEAL_S
	_set_open(1.6)


## Снять шлем (выход из мастерской).
func take_off(on_sealed: Callable, on_done: Callable) -> void:
	_start("off", on_sealed, on_done)
	_marks = {"sealed": OFF_BLACK_S, "lower": OFF_BLACK_S + 0.05, "release": OFF_BLACK_S + 0.05 + OFF_LOWER_S + OFF_PLACE_S}
	_marks["done"] = float(_marks["release"]) + 0.12
	_show_boot("СВЯЗЬ ЗАКРЫТА", "кукла на стенде · фильтр NULL сброшен")
	_set_open(1.6)


## Только визор: окно закрывается, загрузка связи, окно открывается (мастерская кампании из эфира, шлем «уже под рукой»).
func visor_on(on_sealed: Callable, on_done: Callable) -> void:
	_start("visor", on_sealed, on_done)
	_marks = {"sealed": 0.3, "reveal": 0.3 + BOOT_S * 0.8}
	_marks["done"] = float(_marks["reveal"]) + REVEAL_S
	_set_open(1.6)


func _start(kind: String, on_sealed: Callable, on_done: Callable) -> void:
	seq = kind
	busy = true
	_clock = 0.0
	_speed = 1.0
	_done_marks = {}
	_on_sealed = on_sealed
	_on_done = on_done
	overlay.visible = true
	_set_black(0.0)
	boot.visible = false


func _unhandled_input(e: InputEvent) -> void:
	if not busy:
		return
	var pressed: bool = (e is InputEventKey and e.pressed and not e.echo) or (e is InputEventJoypadButton and e.pressed) \
		or (e is InputEventMouseButton and e.pressed)
	if pressed:
		_speed = SKIP_SPEED
		get_viewport().set_input_as_handled()


func _hit(mark: String) -> bool:
	if _done_marks.has(mark) or not _marks.has(mark) or _clock < float(_marks[mark]):
		return false
	_done_marks[mark] = true
	return true


func _process(delta: float) -> void:
	if not busy:
		return
	_clock += delta * _speed
	match seq:
		"on":
			_process_on()
		"off":
			_process_off()
		"visor":
			_process_visor()


func _process_on() -> void:
	var hands := view.hands
	_hit("reach")
	if _done_marks.has("reach") and not _carry and headset != null:   # тянутся к шлему, пока герой ещё доходит (цель — каждый кадр)
		var right := view.cam.global_transform.basis.x
		var p := headset.global_position
		hands.reach("R", p + right * 0.13, 0.12, REACH_S, 0.0, Vector3(-10.0, 8.0, -80.0))
		hands.reach("L", p - right * 0.13, 0.12, REACH_S, 0.0, Vector3(-10.0, -8.0, 80.0))
	if _hit("grip"):
		hands.grip("R", 0.62)
		hands.grip("L", 0.62)
	if _hit("lift") and headset != null:
		headset.reparent(view.cam, true)
		_lift_from = headset.transform
		_carry = true
	var lift0 := float(_marks["lift"])
	if _carry and headset != null:
		var u := clampf((_clock - lift0) / LIFT_S, 0.0, 1.0)
		headset.transform = _lift_xf(u)
		_hold_sides()
		_set_open(1.6 - 1.6 * smoothstep(0.62, 1.0, u))
	if _hit("sealed"):
		_carry = false
		if headset != null:
			headset.visible = false
		view.hands_on = false
		worn = true
		_set_open(0.0)
		_set_black(1.0)
		_show_boot("NULL LINK", "нейрошлем · фильтр NULL включён · стенд 1")
		if _on_sealed.is_valid():
			_on_sealed.call()
	_boot_progress(float(_marks["sealed"]), float(_marks["reveal"]))
	if _clock >= float(_marks["reveal"]):
		var r := clampf((_clock - float(_marks["reveal"])) / REVEAL_S, 0.0, 1.0)
		_set_black(0.0)
		boot.visible = false
		_set_open(1.6 * smoothstep(0.0, 1.0, r))
	if _hit("done"):
		_finish()


func _process_off() -> void:
	var hands := view.hands
	_set_black(clampf(_clock / OFF_BLACK_S, 0.0, 1.0) if _clock < OFF_BLACK_S else 1.0)
	boot.visible = _clock < float(_marks["lower"])
	if _hit("sealed"):
		if _on_sealed.is_valid():
			_on_sealed.call()     # камера гаража встала у верстака (точка Pilot) и стала текущей
		worn = false
		if headset != null:
			_lift_from = view.cam.global_transform.affine_inverse() * rest_xf
			headset.reparent(view.cam, false)
			headset.transform = _lift_xf(1.0)
			headset.visible = true
		view.hands_on = true
		_carry = true
		_hold_sides()
	if not _done_marks.has("sealed"):
		return
	var lower0 := float(_marks["lower"])
	if _clock >= lower0:
		_set_black(0.0)
		var u := clampf((_clock - lower0) / (OFF_LOWER_S + OFF_PLACE_S), 0.0, 1.0)
		_set_open(1.6 * smoothstep(0.0, 0.45, u))
		if headset != null and _carry:
			headset.transform = _lift_xf(1.0 - u)
			_hold_sides()
	if _hit("release"):
		_carry = false
		if headset != null:
			headset.reparent(rest_parent, false)
			headset.global_transform = rest_xf
		view.rest_hands(0.35)
	if _hit("done"):
		_finish()


func _process_visor() -> void:
	var s := float(_marks["sealed"])
	if _clock < s:
		_set_open(1.6 * (1.0 - smoothstep(0.0, 1.0, _clock / s)))
	if _hit("sealed"):
		view.hands_on = false
		worn = true
		_set_open(0.0)
		_set_black(1.0)
		_show_boot("NULL LINK", "нейрошлем · фильтр NULL включён · стенд 1")
		if _on_sealed.is_valid():
			_on_sealed.call()
	_boot_progress(s, float(_marks["reveal"]))
	if _clock >= float(_marks["reveal"]):
		_set_black(0.0)
		boot.visible = false
		_set_open(1.6 * smoothstep(0.0, 1.0, (_clock - float(_marks["reveal"])) / REVEAL_S))
	if _hit("done"):
		_finish()


func _finish() -> void:
	busy = false
	var kind := seq
	seq = ""
	overlay.visible = false
	_set_open(1.6)
	_set_black(0.0)
	var cb := _on_done
	_on_done = Callable()
	_on_sealed = Callable()
	if kind == "off":
		worn = false
	if cb.is_valid():
		cb.call()


## Положение шлема в кадре камеры на подъёме u (0 — где взяли, 1 — на голове): кривая через точку перед грудью, разворот визором
## вперёд в первой половине пути.
func _lift_xf(u: float) -> Transform3D:
	var e := u * u * (3.0 - 2.0 * u)
	var a := _lift_from.origin
	var p := a.lerp(LIFT_MID, e).lerp(LIFT_MID.lerp(FACE, e), e)
	var worn_b := Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, deg_to_rad(FACE_TILT_DEG))
	var r := clampf(u / 0.65, 0.0, 1.0)
	var q := _lift_from.basis.get_rotation_quaternion().slerp(worn_b.get_rotation_quaternion(), r * r * (3.0 - 2.0 * r))
	return Transform3D(Basis(q), p)


## Руки держат шлем за бока (у висков): точки обода ±0.13 м по оси X шлема.
func _hold_sides() -> void:
	if headset == null:
		return
	var hands := view.hands
	var bx := headset.global_transform.basis.x.normalized()
	var cam_x := view.cam.global_transform.basis.x
	var sgn := 1.0 if bx.dot(cam_x) >= 0.0 else -1.0
	var c := headset.global_position + Vector3(0, -0.02, 0)
	hands.reach("R", c + bx * 0.13 * sgn, 0.62, 0.05, 0.0, Vector3(-6.0, 6.0, -84.0))
	hands.reach("L", c - bx * 0.13 * sgn, 0.62, 0.05, 0.0, Vector3(-6.0, -6.0, 84.0))


# ---------------------------------------------------------------- визор и загрузка связи

func _build_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.layer = 60
	overlay.visible = false
	add_child(overlay)
	shade = ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scenes/menu/visor.gdshader")
	shade.material = mat
	overlay.add_child(shade)
	boot = Control.new()
	boot.set_anchors_preset(Control.PRESET_FULL_RECT)
	boot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boot.visible = false
	overlay.add_child(boot)
	var f_head: Font = garage.get("f_head")
	var f_mono: Font = garage.get("f_mono")
	boot_title = Label.new()
	boot_title.add_theme_font_override("font", f_head)
	boot_title.add_theme_font_size_override("font_size", 72)
	boot_title.add_theme_color_override("font_color", Color(0.45, 0.92, 1.0))
	boot_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boot_title.set_anchors_preset(Control.PRESET_CENTER)
	boot_title.position = Vector2(-600, -110)
	boot_title.size = Vector2(1200, 100)
	boot.add_child(boot_title)
	boot_line = Label.new()
	boot_line.add_theme_font_override("font", f_mono)
	boot_line.add_theme_font_size_override("font_size", 22)
	boot_line.add_theme_color_override("font_color", Color(0.6, 0.8, 0.88))
	boot_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boot_line.set_anchors_preset(Control.PRESET_CENTER)
	boot_line.position = Vector2(-600, -4)
	boot_line.size = Vector2(1200, 40)
	boot.add_child(boot_line)
	var track := ColorRect.new()
	track.color = Color(0.3, 0.88, 1.0, 0.18)
	track.set_anchors_preset(Control.PRESET_CENTER)
	track.position = Vector2(-220, 56)
	track.size = Vector2(440, 4)
	boot.add_child(track)
	boot_bar = ColorRect.new()
	boot_bar.color = Color(0.4, 0.92, 1.0)
	boot_bar.position = Vector2.ZERO
	boot_bar.size = Vector2(0, 4)
	track.add_child(boot_bar)


func _show_boot(title: String, line: String) -> void:
	boot_title.text = tr(title)
	boot_line.text = tr(line)
	boot_bar.size.x = 0.0
	boot.visible = true


func _boot_progress(t0: float, t1: float) -> void:
	if boot.visible and _clock >= t0:
		boot_bar.size.x = 440.0 * clampf((_clock - t0) / maxf(t1 - t0, 0.01), 0.0, 1.0)


func _set_open(v: float) -> void:
	var vp := shade.get_viewport_rect().size if shade.is_inside_tree() else Vector2(16, 9)
	(shade.material as ShaderMaterial).set_shader_parameter("aspect", vp.x / maxf(vp.y, 1.0))
	(shade.material as ShaderMaterial).set_shader_parameter("open", v)


func _set_black(v: float) -> void:
	(shade.material as ShaderMaterial).set_shader_parameter("black", v)
