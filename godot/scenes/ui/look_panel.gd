## Панель «ВИД» (Look, docs/plan-demo/LOOK_PASS.md): галочки проб картинки по группам и общий рубильник «до / после».
## Открывается Э, мышью кликаются галочки; строится заново, когда регистрируется новый пункт. Над HUD и панелями боя, под лоадером.
class_name LookPanel
extends CanvasLayer

const LAYER := 90
const FONT := 17

var look: Node
var open := false

var _root: Control
var _panel: PanelContainer
var _box: VBoxContainer
var _master: CheckBox
var _checks := {}           # id → CheckBox
var _toast: Label
var _toast_t := 0.0


func _init() -> void:
	layer = LAYER
	name = "LookPanel"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.06, 0.86)
	sb.border_color = Color(0.35, 0.8, 1.0, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.position = Vector2(24, 96)
	_root.add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 2)
	_panel.add_child(_box)
	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 30)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 120.0
	_toast.offset_left = -300.0
	_toast.offset_right = 300.0
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_root.add_child(_toast)
	rebuild()
	_apply()


func set_open(v: bool) -> void:
	open = v
	_apply()


func toast(text: String) -> void:
	if _toast == null:
		return
	_toast.text = text
	_toast.visible = true
	_toast_t = Look.TOAST_S


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / 0.4, 0.0, 1.0)
		if _toast_t <= 0.0:
			_toast.visible = false


func _apply() -> void:
	if _panel != null:
		_panel.visible = open


## Дерево строк: заголовок, рубильник, дальше группы в порядке регистрации пунктов.
func rebuild() -> void:
	if _box == null or look == null:
		return
	for ch in _box.get_children():
		ch.queue_free()
	_checks.clear()
	var title := _label(tr("ВИД — проба картинки"), FONT + 3, Color(0.55, 0.88, 1.0))
	_box.add_child(title)
	_box.add_child(_label(tr("Э — закрыть · Shift+Э — всё до / после"), FONT - 3, Color(1, 1, 1, 0.6)))
	_master = CheckBox.new()
	_master.text = tr("НОВЫЙ ВИД (общий рубильник)")
	_master.add_theme_font_size_override("font_size", FONT)
	_master.focus_mode = Control.FOCUS_NONE
	_master.toggled.connect(func(v: bool) -> void: look.set_master(v, true))
	_box.add_child(_master)
	var groups: Array[String] = []
	for id in look.ids():
		var g: String = look.group_of(id)
		if not groups.has(g):
			groups.append(g)
	for g in groups:
		if g != "":
			var gl := _label(g, FONT - 1, Color(1.0, 0.78, 0.35))
			_box.add_child(gl)
		for id in look.ids():
			if look.group_of(id) != g:
				continue
			var cb := CheckBox.new()
			cb.text = look.label_of(id)
			cb.add_theme_font_size_override("font_size", FONT - 1)
			cb.focus_mode = Control.FOCUS_NONE
			cb.toggled.connect(func(v: bool) -> void: look.set_on(id, v, true))
			_box.add_child(cb)
			_checks[id] = cb
	if look.ids().is_empty():
		_box.add_child(_label(tr("пока нет проб в этой сцене"), FONT - 2, Color(1, 1, 1, 0.5)))
	refresh()


## Галочки — по текущему состоянию, без сигналов назад.
func refresh() -> void:
	if _master != null:
		_master.set_pressed_no_signal(look.master)
	for id in _checks:
		var cb := _checks[id] as CheckBox
		cb.set_pressed_no_signal(look.checked(id))
		cb.modulate.a = 1.0 if look.master else 0.45


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
