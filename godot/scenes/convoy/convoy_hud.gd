## HUD пробы «Перегон» (docs/plan-demo/CONVOY.md). Дерево строит сам, шрифты — по скину HUD (HudSkin), как PuzzleHud:
##   • слева сверху — плашка участка: «ПЕРЕГОН · проба машины», где машина («КОЧКИ», «ПОДЪЁМ»…) и сколько проехано «42 / 92 м»;
##   • справа сверху — время, груз «В КУЗОВЕ 4 / 5» (меньше, чем было, — красным) и скорость машины;
##   • по центру — предупреждение «Перевернулась — кран через 3 с»; над памяткой — тосты;
##   • снизу — памятка клавиш P1 и P2 по состоянию (снаружи / за рулём), видна всегда (проба — для рук автора);
##   • у двери кабины — подпись в мире «F — сесть» (P2 — «\ — сесть»), когда кукла снаружи рядом с дверью;
##   • финиш — табличка «ДОЕХАЛИ»: время и сколько груза довезли.
## bind(playground) — подписка на сигналы ConvoyPlayground.
class_name ConvoyHud
extends CanvasLayer

const TOP := 14.0
const PANEL_W := 470.0
const TOAST_S := 2.2

var playground: ConvoyPlayground
var root: Control
var info_panel: PanelContainer
var title: Label
var section: Label
var progress: Label
var stat_panel: PanelContainer
var time_label: Label
var cargo_label: Label
var speed_label: Label
var warn_label: Label
var help_p1: Label
var help_p2: Label
var help_all: Label
var toast_label: Label
var end_panel: PanelContainer
var end_title: Label
var end_time: Label
var end_cargo: Label
var door_hint: Label3D
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
	_build_info()
	_build_stats()
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


func _build_info() -> void:
	info_panel = PanelContainer.new()
	info_panel.name = "Info"
	info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_panel.offset_left = 24.0
	info_panel.offset_top = TOP
	info_panel.offset_right = 24.0 + PANEL_W
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	info_panel.add_child(v)
	title = _label("Title", 17, Color(1.0, 0.8, 0.35), HORIZONTAL_ALIGNMENT_LEFT)
	title.text = tr("ПЕРЕГОН · проба машины")
	section = _label("Section", 30, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	progress = _label("Progress", 18, Color(0.85, 0.92, 1.0), HORIZONTAL_ALIGNMENT_LEFT)
	for l in [title, section, progress]:
		v.add_child(l)
	root.add_child(info_panel)


func _build_stats() -> void:
	stat_panel = PanelContainer.new()
	stat_panel.name = "Stats"
	stat_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stat_panel.anchor_left = 1.0
	stat_panel.anchor_right = 1.0
	stat_panel.offset_left = -300.0
	stat_panel.offset_right = -24.0
	stat_panel.offset_top = TOP
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 0)
	stat_panel.add_child(v)
	time_label = _label("Time", 40, Color.WHITE)
	time_label.text = "0:00.0"
	cargo_label = _label("Cargo", 22, Color(1.0, 0.85, 0.45))
	speed_label = _label("Speed", 18, Color(1, 1, 1, 0.8))
	for l in [time_label, cargo_label, speed_label]:
		v.add_child(l)
	root.add_child(stat_panel)
	warn_label = _label("Warn", 30, Color(1.0, 0.45, 0.35))
	warn_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	warn_label.offset_left = -560.0
	warn_label.offset_right = 560.0
	warn_label.offset_top = 150.0
	warn_label.offset_bottom = 196.0
	warn_label.visible = false
	root.add_child(warn_label)


func _build_bottom() -> void:
	help_p1 = _label("HelpP1", 18, Color(0.75, 0.85, 1.0, 0.92))
	help_p2 = _label("HelpP2", 18, Color(1.0, 0.75, 0.72, 0.92))
	help_all = _label("HelpAll", 16, Color(1, 1, 1, 0.6))
	var rows := [help_p1, help_p2, help_all]
	for i in rows.size():
		var l: Label = rows[i]
		l.anchor_left = 0.5
		l.anchor_right = 0.5
		l.anchor_top = 1.0
		l.anchor_bottom = 1.0
		l.offset_left = -820.0
		l.offset_right = 820.0
		l.offset_top = -92.0 + 28.0 * i
		l.offset_bottom = -66.0 + 28.0 * i
		root.add_child(l)
	help_all.text = tr("R — участок заново · U — второй игрок · Esc — пауза · колесо мыши — масштаб")
	toast_label = _label("Toast", 26, Color.WHITE)
	toast_label.anchor_left = 0.5
	toast_label.anchor_right = 0.5
	toast_label.anchor_top = 1.0
	toast_label.anchor_bottom = 1.0
	toast_label.offset_left = -640.0
	toast_label.offset_right = 640.0
	toast_label.offset_top = -146.0
	toast_label.offset_bottom = -104.0
	toast_label.visible = false
	root.add_child(toast_label)


func _build_end() -> void:
	end_panel = PanelContainer.new()
	end_panel.name = "End"
	end_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_panel.set_anchors_preset(Control.PRESET_CENTER)
	end_panel.offset_left = -380.0
	end_panel.offset_right = 380.0
	end_panel.offset_top = -170.0
	end_panel.offset_bottom = 150.0
	end_panel.visible = false
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 10)
	end_panel.add_child(v)
	end_title = _label("Title", 52, Color(1.0, 0.85, 0.4))
	end_title.text = tr("ДОЕХАЛИ")
	end_time = _label("Time", 36, Color.WHITE)
	end_cargo = _label("Cargo", 30, Color(1.0, 0.85, 0.45))
	var again := _label("Again", 22, Color(1, 1, 1, 0.7))
	again.text = tr("Enter или R — заново · Esc — пауза и выход в гараж")
	for l in [end_title, end_time, end_cargo, again]:
		v.add_child(l)
	root.add_child(end_panel)


func _apply_skin() -> void:
	for l in root.find_children("*", "Label", true, false):
		if (l as Node).has_meta("px"):
			HudSkin.style_label(l, "display", int(l.get_meta("px")), l.get_meta("colour"))
			(l as Label).add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			(l as Label).add_theme_constant_override("outline_size", 6)
	for p in [info_panel, stat_panel]:
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


func bind(pg: ConvoyPlayground) -> void:
	playground = pg
	pg.finished.connect(_on_finished)
	pg.p2_changed.connect(func(_j: bool) -> void: refresh_help())
	door_hint = Label3D.new()
	door_hint.name = "DoorHint"
	door_hint.font_size = 56
	door_hint.pixel_size = 0.0042
	door_hint.outline_size = 12
	door_hint.outline_modulate = Color(0.02, 0.02, 0.03, 0.9)
	door_hint.modulate = Color(1.0, 0.92, 0.55)
	door_hint.shaded = false
	door_hint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	door_hint.no_depth_test = true
	door_hint.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	door_hint.visible = false
	pg.car.chassis.add_child(door_hint)
	door_hint.position = ConvoyCar.DOOR_LOCAL + Vector3(0.0, -0.2, ConvoyCar.DEPTH * 0.5 + 0.05)   # на самой двери кабины
	refresh_help()


## Памятка клавиш по состоянию: снаружи / за рулём; P2 — пока не вошёл: «нажми стрелку или U».
func refresh_help() -> void:
	if playground == null:
		return
	var car := playground.car
	if car != null and car.driver == playground.p1 and playground.p1 != null:
		help_p1.text = tr("P1 за рулём — A / D газ / назад · Space ручник · W / S наклон в воздухе · F выйти")
	else:
		help_p1.text = tr("P1 — WASD летать, толкай машину тягой · F у двери — сесть · ЛКМ рука · E взять / положить · ЛКМ + E бросок")
	var joined := playground.p2 != null and is_instance_valid(playground.p2)
	if not joined:
		help_p2.text = tr("P2 — нажми стрелку или U, чтобы ехать вдвоём")
	elif car != null and car.driver == playground.p2:
		help_p2.text = tr("P2 за рулём — ← / → газ / назад · Enter ручник · ↑ / ↓ наклон в воздухе · «\\» или Num . выйти")
	else:
		help_p2.text = tr("P2 — стрелки летать · «\\» или Num . у двери — сесть · «/» или Num 0 взять / положить, со стрелкой — бросок")


func _on_finished(time_s: float, delivered: int, total: int) -> void:
	end_time.text = tr("Время: %s") % fmt_time(time_s)
	end_cargo.text = tr("Груз довезли: %d из %d") % [delivered, total]
	end_panel.visible = true


func hide_end() -> void:
	end_panel.visible = false


## Время «м:сс.д».
static func fmt_time(s: float) -> String:
	var t := maxf(s, 0.0)
	var m := int(t / 60.0)
	return "%d:%04.1f" % [m, t - m * 60.0]


func toast(text: String) -> void:
	toast_label.text = text
	toast_label.visible = true
	toast_label.modulate.a = 1.0
	_toast_left = TOAST_S


func _process(delta: float) -> void:
	if playground != null and playground.car != null and playground.car.chassis != null:
		var pg := playground
		var car := pg.car
		time_label.text = fmt_time(pg.time_s)
		var n := pg.cargo_in_bed()
		var m := pg.cargo.size()
		cargo_label.text = tr("В КУЗОВЕ %d / %d") % [n, m]
		cargo_label.set_meta("colour", Color(1.0, 0.85, 0.45) if n >= m else Color(1.0, 0.45, 0.35))
		cargo_label.add_theme_color_override("font_color", cargo_label.get_meta("colour"))
		speed_label.text = tr("%d км/ч") % roundi(absf(car.speed()) * 3.6)
		section.text = pg.section_title()
		progress.text = tr("проехано %d из %d м") % [roundi(pg.progress_m()), roundi(pg.finish_x - pg.start_x)]
		if car.crane_t >= 0.0:
			warn_label.text = tr("Кран NULL ставит машину на колёса")
			warn_label.visible = true
		elif car.is_upside() and car.flip_t > 0.4:
			warn_label.text = tr("Перевернулась — кран через %d с") % ceili(maxf(Tuning.CONVOY_UPRIGHT_S - car.flip_t, 0.0))
			warn_label.visible = true
		elif pg.pit_t > 0.0:
			warn_label.text = tr("Провал! Машина возвращается на старт")
			warn_label.visible = true
		else:
			warn_label.visible = false
		_tick_door_hint(pg)
	if _toast_left > 0.0:
		_toast_left -= delta
		toast_label.modulate.a = clampf(_toast_left / 0.4, 0.0, 1.0)
		if _toast_left <= 0.0:
			toast_label.visible = false


## Подпись у двери: кукла игрока снаружи и рядом с дверью — какой клавишей сесть.
func _tick_door_hint(pg: ConvoyPlayground) -> void:
	if door_hint == null:
		return
	var keys: Array[String] = []
	if pg.car.driver == null:
		if pg.p1 != null and is_instance_valid(pg.p1) and pg.car.can_enter(pg.p1):
			keys.append(tr("F — сесть"))
		if pg.p2 != null and is_instance_valid(pg.p2) and pg.car.can_enter(pg.p2):
			keys.append(tr("«\\» — сесть"))
	door_hint.visible = not keys.is_empty()
	if door_hint.visible:
		door_hint.text = " · ".join(keys)
