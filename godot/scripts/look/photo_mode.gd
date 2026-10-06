## Фоторежим (проход по картинке, docs/plan-demo/look/cam.md). Ребёнок автозагрузки LookCam, работает в паузе (PROCESS_MODE_ALWAYS).
## Вход — клавиша / (LookCam) в любой 3D-сцене: дерево на паузу (мир, бой, кино KO — всё стоит), HUD и все слои экрана прячутся,
## своя камера с позы текущей:
##   мышь (зажатая левая или правая кнопка) — вращение вокруг точки, колесо — зум, WASD / стрелки — сдвиг (Shift — быстрее),
##   R — к исходному кадру, F или 1–4 — фильтр (как есть / тёплый / холодный / ч/б плакат), C — рамка-обложка NULL GRAVITY,
##   B — размытие фона (DOF с фокусом на ближайшем к центру кадра бойце; пресет графики «низко» его не даёт), H — подсказка,
##   Enter / пробел — снимок в user://photos/ (без подсказки; тост с путём), Esc или / — выход: всё как было до входа.
## Пока режим открыт, клавиши и мышь не доходят до игры (Esc не открывает паузу боя): ловит _input — раньше всех _unhandled_input.
class_name PhotoMode
extends Node

const KEY_PHOTO := KEY_SLASH       # вход и выход (LookCam)
const LAYER_FILTER := 70
const LAYER_FRAME := 71
const LAYER_UI := 72
const FILTERS := ["none", "warm", "cold", "poster"]
const FILTER_SHADER: Shader = preload("res://assets/shaders/look/photo_filter.gdshader")
const DIR := "user://photos/"
const ORBIT_SENS := 0.006
const ZOOM_STEP := 1.12
const PAN_SPEED := 0.6           # доля дистанции до точки вращения в секунду
const DIST := Vector2(0.8, 90.0)
const PITCH_LIMIT_DEG := 85.0
const DOF_AMOUNT := 0.06
const DOF_BEHIND_M := 1.5
const TOAST_S := 3.0

var active := false
var cam: Camera3D
var filter := 0
var frame_on := true
var dof_on := true
var hint_on := true
## Пробы: сколько снимков, путь последнего, сколько слоёв экрана спрятано.
var shots := 0
var last_path := ""
var hidden_count := 0

var _src_cam: Camera3D
var _was_paused := false
var _mouse_mode := Input.MOUSE_MODE_VISIBLE
var _hidden: Array = []          # [CanvasLayer | CanvasItem, был виден]
var _start := {}                 # исходная поза для R
var _pivot := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0
var _dist := 10.0
var _drag := false
var _attr: CameraAttributesPractical
var _dof_ok := false
var _focus_m := 10.0
var _filter_layer: CanvasLayer
var _filter_rect: ColorRect
var _filter_mat: ShaderMaterial
var _frame_layer: CanvasLayer
var _frame: PhotoFrame
var _ui_layer: CanvasLayer
var _hint: Label
var _toast: Label
var _toast_t := 0.0
var _saving := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _build() -> void:
	if cam != null:
		return
	cam = Camera3D.new()
	cam.name = "PhotoCamera"
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cam)
	_filter_layer = _layer("PhotoFilter", LAYER_FILTER)
	_filter_rect = ColorRect.new()
	_filter_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_filter_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_filter_mat = ShaderMaterial.new()
	_filter_mat.shader = FILTER_SHADER
	_filter_rect.material = _filter_mat
	_filter_layer.add_child(_filter_rect)
	_frame_layer = _layer("PhotoFrameLayer", LAYER_FRAME)
	_frame = PhotoFrame.new()
	_frame.name = "PhotoFrame"
	_frame_layer.add_child(_frame)
	_ui_layer = _layer("PhotoUi", LAYER_UI)
	_hint = Label.new()
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 21)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.offset_left = -900.0
	_hint.offset_right = 900.0
	_hint.offset_top = -330.0
	_hint.offset_bottom = -250.0
	_ui_layer.add_child(_hint)
	_toast = Label.new()
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_theme_font_size_override("font_size", 24)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.offset_left = -820.0
	_toast.offset_right = 820.0
	_toast.offset_top = 250.0
	_toast.offset_bottom = 330.0
	_toast.visible = false
	_ui_layer.add_child(_toast)
	for l in [_filter_layer, _frame_layer, _ui_layer]:
		(l as CanvasLayer).visible = false


func _layer(nm: String, lay: int) -> CanvasLayer:
	var l := CanvasLayer.new()
	l.name = nm
	l.layer = lay
	add_child(l)
	return l


# --- вход и выход ---

## Войти: false — нельзя (нет 3D-камеры, открыта пауза боя, идёт загрузка).
func enter() -> bool:
	if active:
		return true
	var flow := get_node_or_null("/root/Flow")
	if flow != null and flow.has_method("is_paused") and bool(flow.call("is_paused")):
		return false
	var loading := get_node_or_null("/root/Loading")
	if loading != null and bool(loading.get("showing")):
		return false
	var src := get_viewport().get_camera_3d()
	if src == null or not is_instance_valid(src):
		return false
	_build()
	_src_cam = src
	_was_paused = get_tree().paused
	cam.fov = src.fov
	cam.near = src.near
	cam.far = src.far
	cam.cull_mask = src.cull_mask
	cam.environment = src.environment
	cam.keep_aspect = src.keep_aspect
	_attr = KoCam.make_dof_attributes(src)
	_dof_ok = KoCam.dof_allowed() and _attr != null
	if _attr != null:
		_attr.dof_blur_near_enabled = false
		_attr.dof_blur_far_enabled = _dof_ok and dof_on
		_attr.set_meta(Gfx.META_DOF, [_dof_ok, false])
	cam.attributes = _attr
	_init_orbit(src.global_transform)
	_start = {"pivot": _pivot, "yaw": _yaw, "pitch": _pitch, "dist": _dist}
	_apply_cam()
	_hide_screen()
	get_tree().paused = true
	cam.make_current()
	_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	active = true
	_frame.refresh()
	_apply_layers()
	_update_dof()
	_toast_show(tr("ФОТОРЕЖИМ: игра на паузе"), 1.6)
	return true


func leave() -> void:
	if not active:
		return
	active = false
	_drag = false
	for l in [_filter_layer, _frame_layer, _ui_layer]:
		(l as CanvasLayer).visible = false
	_show_screen()
	var back := _return_camera()
	if back != null:
		back.make_current()
	_src_cam = null
	Input.mouse_mode = _mouse_mode
	get_tree().paused = _was_paused


## Куда вернуть кадр: камера, с которой вошли; но если она была чужой захваченной (крит-кино идёт и в паузе и могло кончиться),
## а камеру боя уже никто не держит, — камера боя.
func _return_camera() -> Camera3D:
	var m := get_tree().get_first_node_in_group("match")
	var src_ok := _src_cam != null and is_instance_valid(_src_cam) and _src_cam.is_inside_tree()
	if m != null and m.has_method("camera_owner") and m.has_method("game_camera") and String(m.call("camera_owner")) == "":
		var gc := m.call("game_camera") as Camera3D
		if gc != null and is_instance_valid(gc) and gc.is_inside_tree() and (not src_ok or _src_cam != gc):
			var owned_src := src_ok and _src_cam.get_parent() != null and (_src_cam.get_parent() is KoCam or _src_cam.get_parent() is CritCinematic)
			if not src_ok or owned_src:
				return gc
	return _src_cam if src_ok else null


func _exit_tree() -> void:
	if active:
		leave()


## Все слои экрана корневого окна (CanvasLayer и верхние CanvasItem вне слоёв), кроме своих, — спрятать; вид запоминается.
## Экраны внутри SubViewport (телевизор гаража) — часть 3D-кадра, их не трогаем.
func _hide_screen() -> void:
	_hidden.clear()
	var root := get_tree().root
	for n in root.find_children("*", "CanvasLayer", true, false):
		var cl := n as CanvasLayer
		if cl.get_viewport() != root or is_ancestor_of(cl) or not cl.visible:
			continue
		_hidden.append([cl, true])
		cl.visible = false
	for n in root.find_children("*", "CanvasItem", true, false):
		var ci := n as CanvasItem
		if ci.get_viewport() != root or is_ancestor_of(ci) or ci.get_parent() is CanvasItem or ci.get_canvas_layer_node() != null:
			continue
		if ci.visible:
			_hidden.append([ci, true])
			ci.visible = false
	hidden_count = _hidden.size()


func _show_screen() -> void:
	for e in _hidden:
		if is_instance_valid(e[0]):   # раньше типизации: освобождённый узел в типизированную переменную — SCRIPT ERROR
			(e[0] as Object).set("visible", bool(e[1]))
	_hidden.clear()


func _apply_layers() -> void:
	_filter_layer.visible = active and filter > 0
	_filter_mat.set_shader_parameter("mode", filter)
	_filter_mat.set_shader_parameter("grain_seed", float(shots % 97))
	_frame_layer.visible = active and frame_on
	_ui_layer.visible = active
	_hint.visible = hint_on
	_hint.text = hint_text()


func filter_title() -> String:
	match FILTERS[filter]:
		"warm":
			return tr("тёплый")
		"cold":
			return tr("холодный")
		"poster":
			return tr("ч/б плакат")
	return tr("как есть")


func hint_text() -> String:
	return tr("ФОТО   мышь — вращение   колесо — зум   WASD / стрелки — сдвиг   R — сброс") + "\n" + \
		tr("F / 1–4 — фильтр: %s   C — рамка   B — размытие фона   H — подсказка   Enter / пробел — снимок   Esc или / — выход") % filter_title()


# --- камера ---

func _init_orbit(xf: Transform3D) -> void:
	var fwd := -xf.basis.z
	var depth := 0.0
	var best := INF
	for d in get_tree().get_nodes_in_group("dolls"):
		if not (d is Node3D) or not d.has_method("centre_of_mass"):
			continue
		var p: Vector3 = d.centre_of_mass(true) if d is Doll else d.call("centre_of_mass")
		var along := (p - xf.origin).dot(fwd)
		if along <= 0.5:
			continue
		var off := ((p - xf.origin) - fwd * along).length() / along   # отклонение от центра кадра (тангенс)
		if off < best:
			best = off
			depth = along
	if depth <= 0.0:
		depth = (0.0 - xf.origin.z) / fwd.z if absf(fwd.z) > 0.1 and (0.0 - xf.origin.z) / fwd.z > 0.5 else 10.0
	_pivot = xf.origin + fwd * depth
	_dist = depth
	var back := -fwd
	_yaw = atan2(back.x, back.z)
	_pitch = asin(clampf(back.y, -1.0, 1.0))


func _apply_cam() -> void:
	_pitch = clampf(_pitch, -deg_to_rad(PITCH_LIMIT_DEG), deg_to_rad(PITCH_LIMIT_DEG))
	_dist = clampf(_dist, DIST.x, DIST.y)
	var off := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
	var pos := _pivot + off
	cam.global_transform = Transform3D(Basis.looking_at(-off, Vector3.UP), pos)


## Фокус DOF — ближайший к центру кадра боец (его ЦМ), иначе точка вращения.
func _update_dof() -> void:
	var xf := cam.global_transform
	var fwd := -xf.basis.z
	_focus_m = _dist
	var best := 0.35   # не дальше этого отклонения от центра (тангенс)
	for d in get_tree().get_nodes_in_group("dolls"):
		if not (d is Node3D) or not d.has_method("centre_of_mass") or not (d as Node3D).visible:
			continue
		var p: Vector3 = d.centre_of_mass(true) if d is Doll else d.call("centre_of_mass")
		var along := (p - xf.origin).dot(fwd)
		if along <= 0.3:
			continue
		var off := ((p - xf.origin) - fwd * along).length() / along
		if off < best:
			best = off
			_focus_m = along
	if _attr == null:
		return
	_attr.dof_blur_far_enabled = _dof_ok and dof_on
	_attr.dof_blur_far_distance = _focus_m + DOF_BEHIND_M
	_attr.dof_blur_far_transition = maxf(_focus_m * 0.6, 2.0)
	_attr.dof_blur_amount = DOF_AMOUNT


func focus_distance() -> float:
	return _focus_m


func _process(delta: float) -> void:
	if not active:
		return
	var real := FxClock.real_delta(delta)
	if get_viewport().get_camera_3d() != cam:
		cam.make_current()   # кто-то в паузе переключил камеру (крит-кино живёт и в паузе) — кадр фоторежима главнее
	var mv := Vector2(_key(KEY_D, KEY_RIGHT) - _key(KEY_A, KEY_LEFT), _key(KEY_W, KEY_UP) - _key(KEY_S, KEY_DOWN))
	if mv != Vector2.ZERO:
		var b := cam.global_transform.basis
		var fast := 2.5 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
		_pivot += (b.x * mv.x + b.y * mv.y) * _dist * PAN_SPEED * fast * real
	_apply_cam()
	_update_dof()
	if _toast_t > 0.0:
		_toast_t -= real
		_toast.modulate.a = clampf(_toast_t / 0.4, 0.0, 1.0)
		if _toast_t <= 0.0:
			_toast.visible = false


static func _key(a: Key, b: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(a) or Input.is_physical_key_pressed(b) else 0.0


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				_drag = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_dist /= ZOOM_STEP
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_dist *= ZOOM_STEP
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		if _drag:
			var mm := event as InputEventMouseMotion
			_yaw -= mm.relative.x * ORBIT_SENS
			_pitch += mm.relative.y * ORBIT_SENS
		get_viewport().set_input_as_handled()
		return
	var k := event as InputEventKey
	if k == null:
		return
	get_viewport().set_input_as_handled()   # всё с клавиатуры — фоторежиму: игра, пауза боя и переключатели площадки не слышат
	if not k.pressed or k.echo:
		return
	match k.physical_keycode:
		KEY_ESCAPE, KEY_PHOTO:
			leave()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			snapshot()
		KEY_F:
			set_filter((filter + 1) % FILTERS.size())
		KEY_1, KEY_2, KEY_3, KEY_4:
			set_filter(int(k.physical_keycode - KEY_1))
		KEY_C:
			frame_on = not frame_on
			_apply_layers()
		KEY_B:
			dof_on = not dof_on
			_update_dof()
			_toast_show(tr("Размытие фона: %s") % (tr("вкл") if dof_on and _dof_ok else tr("выкл")), 1.4)
		KEY_H:
			hint_on = not hint_on
			_apply_layers()
		KEY_R:
			_pivot = _start.get("pivot", _pivot)
			_yaw = float(_start.get("yaw", _yaw))
			_pitch = float(_start.get("pitch", _pitch))
			_dist = float(_start.get("dist", _dist))


func set_filter(i: int) -> void:
	filter = clampi(i, 0, FILTERS.size() - 1)
	_apply_layers()
	_toast_show(tr("Фильтр: %s") % filter_title(), 1.2)


## Повернуть камеру вокруг точки на углы (рад) и приблизить (×) — для проб и съёмки.
func orbit_by(dyaw: float, dpitch: float, zoom: float = 1.0) -> void:
	_yaw += dyaw
	_pitch += dpitch
	_dist /= maxf(zoom, 0.01)
	if active:
		_apply_cam()
		_update_dof()


# --- снимок ---

## Снимок кадра (с фильтром и рамкой, без подсказки и тоста) в user://photos/; путь — в тосте и last_path. "" — не вышло.
func snapshot() -> String:
	if _saving or not active:
		return ""
	_saving = true
	_ui_layer.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_ui_layer.visible = active
	var path := ""
	if img != null and not img.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
		var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
		path = ProjectSettings.globalize_path(DIR + "null_gravity_%s_%03d.png" % [stamp, Time.get_ticks_msec() % 1000])
		if img.save_png(path) != OK:
			path = ""
	if path != "":
		shots += 1
		last_path = path
		_filter_mat.set_shader_parameter("grain_seed", float(shots % 97))
		_toast_show(tr("Снимок сохранён: %s") % path, TOAST_S)
	else:
		_toast_show(tr("Снимок не сохранился"), TOAST_S)
	_saving = false
	return path


func _toast_show(text: String, secs: float) -> void:
	if _toast == null:
		return
	_toast.text = text
	_toast.visible = true
	_toast.modulate.a = 1.0
	_toast_t = secs
