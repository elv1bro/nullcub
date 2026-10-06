## Экранный слой KO-камеры (KoCam, docs/plan-demo/look/cam.md): леттербокс, табло нокаута «KO! · P2 · IMPACT 18.4G» (плашки по скину
## HUD — HudSkin, как карточка KO), плашка повтора «● ПОВТОР» с уголками видоискателя и подсказкой пропуска, вспышка щелчка назад.
## Слой 15: над HUD (10) — леттербокс закрывает нижнюю строку подсказок, под тостами (20), паузой (60) и панелью «ВИД» (90).
## Всё в реальном времени (твины с ignore_time_scale): мир в это время стоит на ×0.03.
class_name KoCamOverlay
extends CanvasLayer

const LAYER := 15
const BAR_FRAC := 0.1
const BAR_IN_S := 0.12
const BASE := Vector2(1920.0, 1080.0)
const CUT_FLASH_ALPHA := 0.35
const CORNER_LEN := 64.0
const CORNER_W := 5.0
const CORNER_PAD := Vector2(60.0, 130.0)
const PLATE_LEFT := 110.0

var root: Control
var bar_top: ColorRect
var bar_bottom: ColorRect
var plate: HBoxContainer
var ko_label: Label
var tag_label: Label
var impact_label: Label
var replay_box: Control
var replay_label: Label
var replay_dot: Label
var skip_label: Label
var corners: Control
var flash: ColorRect
var _tw: Tween
var _blink := 0.0


func _init() -> void:
	layer = LAYER


func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	bar_top = _bar(true)
	bar_bottom = _bar(false)
	plate = HBoxContainer.new()
	plate.add_theme_constant_override("separation", 18)
	plate.alignment = BoxContainer.ALIGNMENT_BEGIN
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	root.add_child(plate)
	ko_label = _label()
	tag_label = _label()
	impact_label = _label()
	for l in [ko_label, tag_label, impact_label]:
		plate.add_child(l)
	corners = Control.new()
	corners.set_anchors_preset(Control.PRESET_FULL_RECT)
	corners.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corners.draw.connect(_draw_corners)
	root.add_child(corners)
	replay_box = PanelContainer.new()
	replay_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	replay_box.position = Vector2(CORNER_PAD.x + 24.0, CORNER_PAD.y + 18.0)
	root.add_child(replay_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	replay_box.add_child(row)
	replay_dot = _label()
	replay_dot.text = "●"
	row.add_child(replay_dot)
	replay_label = _label()
	row.add_child(replay_label)
	skip_label = _label()
	skip_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	skip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(skip_label)
	flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)
	hide_all()


func _bar(top: bool) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.0, 0.0, 0.0, 1.0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_left = 0.0
	r.anchor_right = 1.0
	r.anchor_top = 0.0 if top else 1.0
	r.anchor_bottom = 0.0 if top else 1.0
	root.add_child(r)
	return r


func _label() -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _set_bars(k: float) -> void:
	var h := BASE.y * BAR_FRAC * clampf(k, 0.0, 1.0)
	bar_top.offset_top = 0.0
	bar_top.offset_bottom = h
	bar_bottom.offset_top = -h
	bar_bottom.offset_bottom = 0.0


func _new_tween() -> Tween:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = create_tween().set_ignore_time_scale(true)
	return _tw


## Табло нокаута в облёте: «KO!» на плашке тревоги, тег побеждённого цветом игрока, «IMPACT 18.4G» (пусто — без третьей плашки).
func show_ko(ko_text: String, tag: String, colour: Color, impact: String) -> void:
	visible = true
	replay_box.visible = false
	skip_label.visible = false
	corners.visible = false
	ko_label.text = ko_text
	ko_label.add_theme_stylebox_override("normal", HudSkin.panel("ko"))
	HudSkin.style_label(ko_label, "display", 96, HudSkin.text_for("alert"))
	tag_label.visible = tag != ""
	tag_label.text = tag
	tag_label.add_theme_stylebox_override("normal", HudSkin.panel("ko_victim", colour))
	HudSkin.style_label(tag_label, "display", 44, HudSkin.text_colour(), colour)
	impact_label.visible = impact != ""
	impact_label.text = impact
	impact_label.add_theme_stylebox_override("normal", HudSkin.panel("ko_sub"))
	HudSkin.style_label(impact_label, "display", 52, HudSkin.text_for("sub"))
	_place_plate()
	plate.modulate = Color(1, 1, 1, 0)
	plate.scale = Vector2(1.5, 1.5)
	_set_bars(0.0)
	var tw := _new_tween()
	tw.set_parallel(true)
	tw.tween_method(_set_bars, 0.0, 1.0, BAR_IN_S)
	tw.tween_property(plate, "modulate:a", 1.0, 0.1).set_delay(0.08)
	tw.tween_property(plate, "scale", Vector2.ONE, 0.18).set_delay(0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Табло — нижняя треть слева, как плашки трансляции (центр кадра — побеждённый).
func _place_plate() -> void:
	var m := plate.get_combined_minimum_size()
	plate.size = m
	var bottom := BASE.y * BAR_FRAC + 30.0
	plate.offset_left = PLATE_LEFT
	plate.offset_right = PLATE_LEFT + m.x
	plate.offset_top = -bottom - m.y
	plate.offset_bottom = -bottom
	plate.pivot_offset = Vector2(0.0, m.y * 0.5)


## Повтор: плашка «● ПОВТОР», уголки кадра, подсказка пропуска; табло нокаута уходит, леттербокс остаётся.
func show_replay() -> void:
	visible = true
	_set_bars(1.0)
	plate.modulate.a = 0.0
	replay_box.visible = true
	replay_box.add_theme_stylebox_override("panel", HudSkin.panel("ko_sub"))
	replay_label.text = tr("ПОВТОР")
	HudSkin.style_label(replay_label, "display", 40, HudSkin.text_for("sub"))
	HudSkin.style_label(replay_dot, "display", 34, HudSkin.alert())
	skip_label.visible = true
	skip_label.text = tr("Enter / пробел — пропустить")
	skip_label.add_theme_font_size_override("font_size", 22)
	skip_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	var m := skip_label.get_combined_minimum_size()
	skip_label.offset_left = -m.x * 0.5 - 20.0
	skip_label.offset_right = m.x * 0.5 + 20.0
	skip_label.offset_top = -BASE.y * BAR_FRAC * 0.5 - m.y * 0.5
	skip_label.offset_bottom = skip_label.offset_top + m.y
	corners.visible = true
	corners.queue_redraw()
	replay_box.modulate = Color(1, 1, 1, 0)
	_blink = 0.0
	var tw := _new_tween()
	flash.color.a = 0.5 * FxPreset.flash()
	tw.set_parallel(true)
	tw.tween_property(flash, "color:a", 0.0, 0.14)
	tw.tween_property(replay_box, "modulate:a", 1.0, 0.12)


func _draw_corners() -> void:
	var s := corners.size
	var c := Color(1, 1, 1, 0.75)
	var p0 := CORNER_PAD
	var p1 := s - CORNER_PAD
	for corner in [[p0, Vector2(1, 1)], [Vector2(p1.x, p0.y), Vector2(-1, 1)], [Vector2(p0.x, p1.y), Vector2(1, -1)], [p1, Vector2(-1, -1)]]:
		var o: Vector2 = corner[0]
		var d: Vector2 = corner[1]
		corners.draw_rect(Rect2(o + Vector2(minf(d.x, 0.0) * CORNER_LEN, minf(d.y, 0.0) * CORNER_W), Vector2(CORNER_LEN, CORNER_W)), c)
		corners.draw_rect(Rect2(o + Vector2(minf(d.x, 0.0) * CORNER_W, minf(d.y, 0.0) * CORNER_LEN), Vector2(CORNER_W, CORNER_LEN)), c)


func _process(delta: float) -> void:
	if not visible or not replay_box.visible:
		return
	_blink += FxClock.real_delta(delta)
	replay_dot.modulate.a = 1.0 if fmod(_blink, 0.8) < 0.5 else 0.15


## Щелчок назад: короткая вспышка (с учётом пресета FX), всё остальное сразу прячется.
func cut() -> void:
	plate.modulate.a = 0.0
	replay_box.visible = false
	skip_label.visible = false
	corners.visible = false
	_set_bars(0.0)
	flash.color.a = CUT_FLASH_ALPHA * FxPreset.flash()
	var tw := _new_tween()
	tw.tween_property(flash, "color:a", 0.0, 0.1)
	tw.tween_callback(_hide_layer)


## Довести появление до конца (пробы вёрстки): леттербокс, табло и плашка повтора — в конечном виде.
func settle() -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_set_bars(1.0)
	flash.color.a = 0.0
	plate.scale = Vector2.ONE
	plate.modulate.a = 0.0 if replay_box.visible else 1.0
	replay_box.modulate.a = 1.0


## Сразу всё спрятать (прерывание кино).
func hide_all() -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_hide_layer()


func _hide_layer() -> void:
	visible = false
	if flash != null:
		flash.color.a = 0.0
	if plate != null:
		plate.modulate.a = 0.0
	if replay_box != null:
		replay_box.visible = false
