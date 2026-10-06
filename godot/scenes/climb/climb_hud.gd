## HUD пробы «Подъём: стена» (docs/plan-demo/CLIMB.md). Дерево строит сам, шрифты — по скину HUD (HudSkin), как PuzzleHud:
##   • у куклы (над головой) — полоска запаса тяги, по бокам — две метки рук (горит — рука на стене), под ней — слово опоры
##     («отдых» на уступе / на двух руках, «тает» на одной, «пусто» — выдохся);
##   • слева сверху — по строке на игрока: высота ног, рекорд высоты, время (часы с первого отрыва от пола);
##   • справа сверху — лучшее время за сессию и сила тяжести шахты (клавиша G);
##   • снизу — памятка клавиш P1, P2 и общих; над ней — тосты (срыв, «гладко», клавиши);
##   • финиш — табличка «ВЕРХ!» со временем, лучшим временем и срывами.
## bind(playground) — подписка на сигналы ClimbPlayground и ClimbMatch.
class_name ClimbHud
extends CanvasLayer

const TOP := 14.0
const PANEL_W := 470.0
const TOAST_S := 1.8
const SMOOTH_TOAST_GAP_S := 2.5
const BAR_W := 96.0
const BAR_H := 10.0
const BAR_LIFT := 0.55        # м над головой
const HAND_R := 6.0

var playground: ClimbPlayground
var root: Control
var marks: Control
var players_panel: PanelContainer
var player_rows: Array = []   # [{name, height, best, time}] по player_index 0..1
var best_panel: PanelContainer
var best_time: Label
var gravity_label: Label
var help_p1: Label
var help_p2: Label
var help_common: Label
var toast_label: Label
var end_panel: PanelContainer
var end_title: Label
var end_time: Label
var end_best: Label
var end_falls: Label
var _toast_left := 0.0
var _smooth_at := -INF
var _clock := 0.0


func _init() -> void:
	layer = 10


func _ready() -> void:
	root = Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = HudSkin.theme()
	add_child(root)
	marks = Control.new()
	marks.name = "Marks"
	marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marks.draw.connect(_draw_marks)
	root.add_child(marks)
	_build_players()
	_build_best()
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


func _build_players() -> void:
	players_panel = PanelContainer.new()
	players_panel.name = "Players"
	players_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	players_panel.offset_left = 24.0
	players_panel.offset_top = TOP
	players_panel.offset_right = 24.0 + PANEL_W
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 6)
	players_panel.add_child(v)
	for i in 2:
		var row := HBoxContainer.new()
		row.name = "Row%d" % i
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 14)
		var col: Color = Tuning.PLAYER_COLORS[i]
		var nm := _label("Name", 26, col.lightened(0.35), HORIZONTAL_ALIGNMENT_LEFT)
		nm.text = "P%d" % (i + 1)
		nm.custom_minimum_size = Vector2(44, 0)
		var h := _label("Height", 30, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		h.custom_minimum_size = Vector2(120, 0)
		var b := _label("Best", 18, Color(1.0, 0.85, 0.45), HORIZONTAL_ALIGNMENT_LEFT)
		b.custom_minimum_size = Vector2(150, 0)
		var t := _label("Time", 26, Color(0.85, 0.95, 1.0), HORIZONTAL_ALIGNMENT_RIGHT)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for l in [nm, h, b, t]:
			row.add_child(l)
		v.add_child(row)
		player_rows.append({"row": row, "name": nm, "height": h, "best": b, "time": t})
	root.add_child(players_panel)


func _build_best() -> void:
	best_panel = PanelContainer.new()
	best_panel.name = "Best"
	best_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	best_panel.anchor_left = 1.0
	best_panel.anchor_right = 1.0
	best_panel.offset_left = -300.0
	best_panel.offset_right = -24.0
	best_panel.offset_top = TOP
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 0)
	best_panel.add_child(v)
	best_time = _label("BestTime", 22, Color(1.0, 0.85, 0.45))
	gravity_label = _label("Gravity", 17, Color(0.8, 0.9, 1.0, 0.85))
	v.add_child(best_time)
	v.add_child(gravity_label)
	root.add_child(best_panel)


func _build_bottom() -> void:
	help_p1 = _label("HelpP1", 18, Color(0.75, 0.85, 1.0, 0.92))
	help_p2 = _label("HelpP2", 18, Color(1.0, 0.75, 0.72, 0.92))
	help_common = _label("HelpCommon", 16, Color(1, 1, 1, 0.7))
	var lines: Array = [help_p1, help_p2, help_common]
	for i in lines.size():
		var l: Label = lines[i]
		l.anchor_left = 0.5
		l.anchor_right = 0.5
		l.anchor_top = 1.0
		l.anchor_bottom = 1.0
		l.offset_left = -900.0
		l.offset_right = 900.0
		l.offset_top = -128.0 + 28.0 * i   # нижняя строка кончается на −46: ниже — метка «Tab — управление» (ControlFeelPanel)
		l.offset_bottom = -102.0 + 28.0 * i
		root.add_child(l)
	help_p1.text = tr("P1 — WASD полёт (тратит запас) · Shift рывок · ЛКМ / ПКМ держать — левая / правая рука хватается · мышь, пока держишь, — подтянуться")
	help_common.text = tr("Синее гладкое — не ухватиться · отдых: стоять на уступе или висеть на двух руках · R — заново · G — тяжесть · Esc — пауза")
	toast_label = _label("Toast", 26, Color.WHITE)
	toast_label.anchor_left = 0.5
	toast_label.anchor_right = 0.5
	toast_label.anchor_top = 1.0
	toast_label.anchor_bottom = 1.0
	toast_label.offset_left = -500.0
	toast_label.offset_right = 500.0
	toast_label.offset_top = -214.0   # выше тоста сока удара (HitJuice: −170…−130)
	toast_label.offset_bottom = -174.0
	toast_label.visible = false
	root.add_child(toast_label)


func _build_end() -> void:
	end_panel = PanelContainer.new()
	end_panel.name = "End"
	end_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_panel.set_anchors_preset(Control.PRESET_CENTER)
	end_panel.offset_left = -340.0
	end_panel.offset_right = 340.0
	end_panel.offset_top = -170.0
	end_panel.offset_bottom = 150.0
	end_panel.visible = false
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 8)
	end_panel.add_child(v)
	end_title = _label("Title", 60, Color(1.0, 0.85, 0.4))
	end_title.text = tr("ВЕРХ!")
	end_time = _label("Time", 36, Color.WHITE)
	end_best = _label("BestTime", 22, Color(1.0, 0.85, 0.45))
	end_falls = _label("Falls", 20, Color(0.85, 0.92, 1.0))
	var again := _label("Again", 20, Color(1, 1, 1, 0.7))
	again.text = tr("R — ещё раз · Esc — пауза и выход в гараж")
	for l in [end_title, end_time, end_best, end_falls, again]:
		v.add_child(l)
	root.add_child(end_panel)


func _apply_skin() -> void:
	for l in root.find_children("*", "Label", true, false):
		if (l as Node).has_meta("px"):
			HudSkin.style_label(l, "display", int(l.get_meta("px")), l.get_meta("colour"))
			(l as Label).add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			(l as Label).add_theme_constant_override("outline_size", 6)
	for p in [players_panel, best_panel]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.035, 0.05, 0.8)
		sb.border_color = Color(1.0, 0.6, 0.2)
		sb.border_width_left = 4
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 14.0
		sb.content_margin_right = 14.0
		sb.content_margin_top = 6.0
		sb.content_margin_bottom = 8.0
		(p as PanelContainer).add_theme_stylebox_override("panel", sb)
	var eb := StyleBoxFlat.new()
	eb.bg_color = Color(0.03, 0.035, 0.05, 0.92)
	eb.set_corner_radius_all(8)
	eb.content_margin_left = 30.0
	eb.content_margin_right = 30.0
	eb.content_margin_top = 18.0
	eb.content_margin_bottom = 18.0
	end_panel.add_theme_stylebox_override("panel", eb)


func bind(pg: ClimbPlayground) -> void:
	playground = pg
	pg.p2_changed.connect(func(_j: bool) -> void: _refresh_help())
	pg.gravity_changed.connect(func(_g: float) -> void: _refresh_gravity())
	pg.match_node.finished.connect(_on_finished)
	pg.match_node.fell.connect(_on_fell)
	pg.match_node.climb_reset.connect(hide_end)
	_refresh_help()
	_refresh_gravity()


func _refresh_help() -> void:
	var joined := playground != null and playground.p2 != null and is_instance_valid(playground.p2)
	if joined:
		help_p2.text = tr("P2 — стрелки полёт · [ / ] держать — левая / правая рука · пока держишь руку, стрелки ведут руки · U — лезть одному")
	else:
		help_p2.text = tr("P2 — нажми стрелку или U, чтобы лезть вдвоём")


func _refresh_gravity() -> void:
	var g := playground.wall.gravity if playground != null and playground.wall != null else Tuning.CLIMB_GRAVITY
	gravity_label.text = tr("тяжесть %.0f м/с² · G") % g


## Время «м:сс.д».
static func fmt_time(s: float) -> String:
	var t := maxf(s, 0.0)
	var m := int(t) / 60
	return "%d:%04.1f" % [m, t - 60.0 * m]


func toast(text: String) -> void:
	toast_label.text = text
	toast_label.visible = true
	toast_label.modulate.a = 1.0
	_toast_left = TOAST_S


func hide_end() -> void:
	end_panel.visible = false


func _on_finished(d: Doll, seconds: float) -> void:
	var p: Dictionary = playground.match_node.players.get(d.player_index, {})
	end_title.text = tr("ВЕРХ!") if playground.players().size() < 2 else tr("P%d — ВЕРХ!") % (d.player_index + 1)
	end_time.text = tr("Время: %s") % fmt_time(seconds)
	end_best.text = tr("лучшее за сессию: %s") % fmt_time(ClimbMatch.best_time)
	end_falls.text = tr("срывов: %d · самый долгий полёт вниз %.1f м") % [int(p.get("falls", 0)), float(p.get("max_fall", 0.0))]
	_apply_skin()
	end_panel.visible = true


func _on_fell(d: Doll, metres: float) -> void:
	toast(tr("P%d сорвался: %.1f м вниз") % [d.player_index + 1, metres] if playground.players().size() > 1 else tr("Сорвался: %.1f м вниз") % metres)


func _process(delta: float) -> void:
	_clock += delta
	if playground == null:
		return
	var m := playground.match_node
	for i in 2:
		var r: Dictionary = player_rows[i]
		var p: Dictionary = m.players.get(i, {})
		var d := m.doll_of_index(i)
		var show := not p.is_empty() and d != null and d.is_inside_tree()
		(r["row"] as Control).visible = show
		if not show:
			continue
		(r["height"] as Label).text = tr("%.1f м") % float(p["h"])
		(r["best"] as Label).text = tr("рекорд %.1f м") % float(p["best_h"])
		(r["time"] as Label).text = fmt_time(float(p["t"])) if bool(p["started"]) else "0:00.0"
		_check_smooth(d)
	best_time.text = tr("лучшее время %s") % fmt_time(ClimbMatch.best_time) if ClimbMatch.best_time >= 0.0 else tr("лучшее время —")
	if _toast_left > 0.0:
		_toast_left -= delta
		toast_label.modulate.a = clampf(_toast_left / 0.4, 0.0, 1.0)
		if _toast_left <= 0.0:
			toast_label.visible = false
	marks.queue_redraw()


## Рука тянется к гладкому — тост «гладко» (не чаще SMOOTH_TOAST_GAP_S).
func _check_smooth(d: Doll) -> void:
	if _clock - _smooth_at < SMOOTH_TOAST_GAP_S:
		return
	for a in ClimbMatch.wall_arms(d):
		var arm := a as ArmAssist
		if arm.wall_smooth_touch and arm.arm_active and not arm.is_wall_holding():
			_smooth_at = _clock
			toast(tr("Гладко — не ухватиться"))
			return


## Над каждой куклой: полоска запаса, метки рук по бокам, слово опоры.
func _draw_marks() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or playground == null:
		return
	var font := HudSkin.font("display")
	if font == null:
		font = ThemeDB.fallback_font
	var to_canvas := marks.get_global_transform_with_canvas().affine_inverse()
	for d in playground.players():
		var dd := d as Doll
		var st := dd.stamina
		if st == null or not dd.alive:
			continue
		var head: Node3D = dd.parts.get("Head", dd.torso()) as Node3D
		var com := dd.centre_of_mass(true)
		var top := Vector3(com.x, maxf(com.y + 0.9, head.global_position.y if head != null else com.y) + BAR_LIFT, 0.0)
		if cam.is_position_behind(top):
			continue
		var sp: Vector2 = to_canvas * cam.unproject_position(top)
		var r := Rect2(sp - Vector2(BAR_W * 0.5, BAR_H * 0.5), Vector2(BAR_W, BAR_H))
		marks.draw_rect(r.grow(3.0), Color(0.02, 0.02, 0.03, 0.85))
		var f := st.frac()
		var fc := Color(1.0, 0.3, 0.2).lerp(Color(1.0, 0.85, 0.25), clampf(f * 2.0, 0.0, 1.0)).lerp(Color(0.4, 1.0, 0.55), clampf(f * 2.0 - 1.0, 0.0, 1.0))
		if st.locked:
			fc = Color(1.0, 0.25, 0.2, 0.55 + 0.45 * absf(sin(_clock * 8.0)))
		marks.draw_rect(Rect2(r.position, Vector2(BAR_W * f, BAR_H)), fc)
		var restart_x := BAR_W * Tuning.CLIMB_STAMINA_RESTART / maxf(st.max_value, 1.0)
		marks.draw_line(r.position + Vector2(restart_x, 0.0), r.position + Vector2(restart_x, BAR_H), Color(0, 0, 0, 0.6), 1.0)
		var arms := ClimbMatch.wall_arms(dd)
		for i in arms.size():
			var on := (arms[i] as ArmAssist).is_wall_holding()
			var c := sp + Vector2((-1.0 if i == 0 else 1.0) * (BAR_W * 0.5 + 12.0), 0.0)
			marks.draw_circle(c, HAND_R + 2.0, Color(0, 0, 0, 0.8))
			marks.draw_circle(c, HAND_R, Color(1.0, 0.9, 0.5) if on else Color(0.35, 0.35, 0.38))
		var word := ""
		var wc := Color(0.6, 1.0, 0.65)
		if st.locked:
			word = tr("пусто")
			wc = Color(1.0, 0.4, 0.3)
		elif st.support == "ledge" or st.support == "hands2":
			word = tr("отдых")
		elif st.support == "hand1":
			word = tr("тает")
			wc = Color(1.0, 0.75, 0.35)
		if word != "":
			var fs := 17
			var tw := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var tp := sp + Vector2(-tw.x * 0.5, BAR_H + 16.0)
			marks.draw_string_outline(font, tp, word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.9))
			marks.draw_string(font, tp, word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, wc)
