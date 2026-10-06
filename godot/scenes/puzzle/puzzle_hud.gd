## HUD демо «Головоломки вдвоём» (docs/plan-demo/PUZZLE.md). Дерево строит сам, шрифты — по скину HUD (HudSkin), как RaceHud:
##   • слева сверху — плашка комнаты: «КОМНАТА 2 / 6», название, подсказка «вдвоём» и строка «один: …» (как решить соло);
##   • справа сверху — общее время и время этой комнаты;
##   • по центру при входе в комнату — заставка «КОМНАТА N» с названием (гаснет за BANNER_S);
##   • снизу — памятка клавиш P1 и P2 (P2 — пока не вошёл: «нажми стрелку»), над ней — тосты клавиш;
##   • финиш — табличка «ДЕМО ПРОЙДЕНО»: общее время и время каждой комнаты.
## bind(playground) — подписка на сигналы PuzzlePlayground.
class_name PuzzleHud
extends CanvasLayer

const TOP := 14.0
const PANEL_W := 560.0
const BANNER_S := 2.2
const TOAST_S := 1.6

var playground: PuzzlePlayground
var root: Control
var room_panel: PanelContainer
var room_no: Label
var room_title: Label
var room_hint: Label
var room_solo: Label
var time_panel: PanelContainer
var time_total: Label
var time_room: Label
var banner: VBoxContainer
var banner_no: Label
var banner_title: Label
var help_p1: Label
var help_p2: Label
var toast_label: Label
var end_panel: PanelContainer
var end_title: Label
var end_time: Label
var end_table: GridContainer
var _banner_left := 0.0
var _toast_left := 0.0


func _init() -> void:
	layer = 10


func _ready() -> void:
	root = Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = HudSkin.theme()
	add_child(root)
	_build_room()
	_build_time()
	_build_banner()
	_build_bottom()
	_build_end()
	_apply_skin()
	HudSkin.events.changed.connect(func(_id: String) -> void: _apply_skin())


func _label(n: String, px: int, c: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.name = n
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_meta("px", px)
	l.set_meta("colour", c)
	return l


func _build_room() -> void:
	room_panel = PanelContainer.new()
	room_panel.name = "Room"
	room_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room_panel.offset_left = 24.0
	room_panel.offset_top = TOP
	room_panel.offset_right = 24.0 + PANEL_W
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	room_panel.add_child(v)
	room_no = _label("No", 20, Color(1.0, 0.8, 0.35), HORIZONTAL_ALIGNMENT_LEFT)
	room_title = _label("Title", 34, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	room_hint = _label("Hint", 20, Color(0.92, 0.95, 1.0), HORIZONTAL_ALIGNMENT_LEFT)
	room_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	room_hint.custom_minimum_size = Vector2(PANEL_W - 36.0, 0)
	room_solo = _label("Solo", 18, Color(0.7, 0.85, 1.0, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
	room_solo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	room_solo.custom_minimum_size = Vector2(PANEL_W - 36.0, 0)
	for l in [room_no, room_title, room_hint, room_solo]:
		v.add_child(l)
	root.add_child(room_panel)


func _build_time() -> void:
	time_panel = PanelContainer.new()
	time_panel.name = "Time"
	time_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_panel.anchor_left = 1.0
	time_panel.anchor_right = 1.0
	time_panel.offset_left = -244.0
	time_panel.offset_right = -24.0
	time_panel.offset_top = TOP
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", -2)
	time_panel.add_child(v)
	time_total = _label("Total", 40, Color.WHITE)
	time_total.text = "0:00"
	time_room = _label("Room", 18, Color(1, 1, 1, 0.75))
	v.add_child(time_total)
	v.add_child(time_room)
	root.add_child(time_panel)


func _build_banner() -> void:
	banner = VBoxContainer.new()
	banner.name = "Banner"
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.offset_left = -600.0
	banner.offset_right = 600.0
	banner.offset_top = -220.0
	banner.offset_bottom = -90.0
	banner.alignment = BoxContainer.ALIGNMENT_CENTER
	banner.add_theme_constant_override("separation", -6)
	banner_no = _label("No", 64, Color(1.0, 0.8, 0.35))
	banner_title = _label("Title", 40, Color.WHITE)
	banner.add_child(banner_no)
	banner.add_child(banner_title)
	banner.visible = false
	root.add_child(banner)


func _build_bottom() -> void:
	help_p1 = _label("HelpP1", 19, Color(0.75, 0.85, 1.0, 0.85))
	help_p2 = _label("HelpP2", 19, Color(1.0, 0.75, 0.72, 0.85))
	for i in 2:
		var l: Label = [help_p1, help_p2][i]
		l.anchor_left = 0.5
		l.anchor_right = 0.5
		l.anchor_top = 1.0
		l.anchor_bottom = 1.0
		l.offset_left = -900.0
		l.offset_right = 900.0
		l.offset_top = -64.0 + 28.0 * i
		l.offset_bottom = -38.0 + 28.0 * i
		root.add_child(l)
	help_p1.text = tr("P1 — WASD летать · ЛКМ — рука к курсору · E — взять / положить · ЛКМ + E — бросок · R — комната заново")
	toast_label = _label("Toast", 26, Color.WHITE)
	toast_label.anchor_left = 0.5
	toast_label.anchor_right = 0.5
	toast_label.anchor_top = 1.0
	toast_label.anchor_bottom = 1.0
	toast_label.offset_left = -500.0
	toast_label.offset_right = 500.0
	toast_label.offset_top = -120.0
	toast_label.offset_bottom = -80.0
	toast_label.visible = false
	root.add_child(toast_label)


func _build_end() -> void:
	end_panel = PanelContainer.new()
	end_panel.name = "End"
	end_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_panel.set_anchors_preset(Control.PRESET_CENTER)
	end_panel.offset_left = -380.0
	end_panel.offset_right = 380.0
	end_panel.offset_top = -230.0
	end_panel.offset_bottom = 250.0
	end_panel.visible = false
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 10)
	end_panel.add_child(v)
	end_title = _label("Title", 52, Color(1.0, 0.85, 0.4))
	end_title.text = tr("ДЕМО ПРОЙДЕНО")
	end_time = _label("Time", 36, Color.WHITE)
	end_table = GridContainer.new()
	end_table.name = "Table"
	end_table.columns = 3
	end_table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_table.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	end_table.add_theme_constant_override("h_separation", 26)
	end_table.add_theme_constant_override("v_separation", 2)
	var again := _label("Again", 22, Color(1, 1, 1, 0.7))
	again.text = tr("Enter — с начала · Esc — пауза и выход в гараж")
	for l in [end_title, end_time, end_table, again]:
		v.add_child(l)
	root.add_child(end_panel)


func _apply_skin() -> void:
	for l in root.find_children("*", "Label", true, false):
		if (l as Node).has_meta("px"):
			HudSkin.style_label(l, "display", int(l.get_meta("px")), l.get_meta("colour"))
			(l as Label).add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			(l as Label).add_theme_constant_override("outline_size", 6)
	for p in [room_panel, time_panel]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.035, 0.05, 0.82)
		sb.border_color = Color(1.0, 0.75, 0.25)
		sb.border_width_left = 4
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 16.0
		sb.content_margin_right = 16.0
		sb.content_margin_top = 8.0
		sb.content_margin_bottom = 10.0
		(p as PanelContainer).add_theme_stylebox_override("panel", sb)
	var eb := StyleBoxFlat.new()
	eb.bg_color = Color(0.03, 0.035, 0.05, 0.92)
	eb.set_corner_radius_all(8)
	eb.content_margin_left = 30.0
	eb.content_margin_right = 30.0
	eb.content_margin_top = 18.0
	eb.content_margin_bottom = 18.0
	end_panel.add_theme_stylebox_override("panel", eb)


func bind(pg: PuzzlePlayground) -> void:
	playground = pg
	pg.room_changed.connect(_on_room)
	pg.demo_finished.connect(_on_finished)
	pg.p2_changed.connect(func(_j: bool) -> void: _refresh_help())
	_refresh_help()
	if not pg.rooms.is_empty():
		_on_room(pg.current)


func _refresh_help() -> void:
	var joined := playground != null and playground.p2 != null and is_instance_valid(playground.p2)
	if joined:
		help_p2.text = tr("P2 — стрелки летать · «/» или Num 0 — взять / положить · со стрелкой — бросок · U — играть одному")
	else:
		help_p2.text = tr("P2 — нажми стрелку или U, чтобы войти вдвоём")


func _on_room(i: int) -> void:
	var r := playground.rooms[i]
	var n := playground.rooms.size()
	room_no.text = tr("КОМНАТА %d / %d") % [i + 1, n]
	room_title.text = tr(r.title)
	room_hint.text = tr(r.hint)
	room_solo.text = tr(r.solo)
	room_solo.visible = r.solo != ""
	banner_no.text = tr("КОМНАТА %d") % (i + 1)
	banner_title.text = tr(r.title)
	banner.visible = true
	banner.modulate.a = 1.0
	_banner_left = BANNER_S


func _on_finished(total: float) -> void:
	end_time.text = tr("Время: %s") % fmt_time(total)
	for c in end_table.get_children():
		end_table.remove_child(c)
		c.queue_free()
	for i in playground.room_times.size():
		var r := playground.rooms[mini(i, playground.rooms.size() - 1)]
		var a := _label("N", 22, Color(1.0, 0.8, 0.35))
		a.text = "%d" % (i + 1)
		var b := _label("T", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		b.text = tr(r.title)
		var c := _label("S", 22, Color(0.8, 0.95, 1.0), HORIZONTAL_ALIGNMENT_RIGHT)
		c.text = fmt_time(float(playground.room_times[i]))
		for l in [a, b, c]:
			end_table.add_child(l)
	_apply_skin()
	end_panel.visible = true
	banner.visible = false


func hide_end() -> void:
	end_panel.visible = false


## Время «м:сс».
static func fmt_time(s: float) -> String:
	var t := int(maxf(s, 0.0))
	return "%d:%02d" % [t / 60, t % 60]


func toast(text: String) -> void:
	toast_label.text = text
	toast_label.visible = true
	toast_label.modulate.a = 1.0
	_toast_left = TOAST_S


func _process(delta: float) -> void:
	if playground != null:
		time_total.text = fmt_time(playground.total_time)
		time_room.text = tr("комната %s") % fmt_time(playground.room_time)
	if _banner_left > 0.0:
		_banner_left -= delta
		banner.modulate.a = clampf(_banner_left / 0.5, 0.0, 1.0)
		if _banner_left <= 0.0:
			banner.visible = false
	if _toast_left > 0.0:
		_toast_left -= delta
		toast_label.modulate.a = clampf(_toast_left / 0.4, 0.0, 1.0)
		if _toast_left <= 0.0:
			toast_label.visible = false
