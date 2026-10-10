## HUD «Царя горы» (docs/plan-demo/KING.md). Дерево строит сам, шрифты — по скину HUD (HudSkin), смена скина перекрашивает на лету:
##   • сверху по центру — таймер матча «4:12», под ним «ЗОНА ПЕРЕЕДЕТ: 0:17» (последние KING_ZONE_WARN_S — красным), под ним столбики
##     очков пятерых: имя цветом куклы, столбик до KING_SCORE_TO_WIN, число очков; хозяин зоны подсвечен, царь — с короной;
##   • под столбиками — «ЦАРЬ: P3» (золотом) / «ЗОНА: P3» / «ЗОНА СПОРНАЯ» / «ЗОНА СВОБОДНА»;
##   • над куклами — имя цветом куклы, над выбитыми — «ВОЗВРАТ 2»; стрелка к зоне за кадром — KingMarkers (отдельный слой сцены);
##   • диктор (Announcer) — отсчёт, FIGHT!, «ЦАРЬ!», «ЗОНА ПЕРЕЕХАЛА»;
##   • снизу — подсказка клавиш (гаснет через HINT_S), тосты U / K / M / N / H;
##   • конец матча — табличка победителя и таблица бойцов (очки, короны, нокауты, выбит), «R — заново».
## bind(match, playground) — подписка на KingMatch по именам сигналов.
class_name KingHud
extends CanvasLayer

const BAR_W := 118.0
const BAR_H := 120.0
const BAR_GAP := 10.0
const TOP := 12.0
const HINT_S := 14.0
const NAME_LIFT := 0.5           # м над головой
const CROWN := Color(1.0, 0.85, 0.3)

var match_node: KingMatch
var playground: Node
var root: Control
var announcer: Announcer
var clock: Label
var zone_clock: Label
var king_label: Label
var bars_box: HBoxContainer
var bars: Dictionary = {}        # player_index → {panel, name, bar, value}
var marks: Control
var hint: Label
var toast_label: Label
var end_panel: PanelContainer
var end_title: Label
var end_sub: Label
var end_table: GridContainer
var _time := 0.0
var _toast_tw: Tween


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
	clock = _label("Clock", 40, Color.WHITE)
	_top_centre(clock, 200.0, TOP, 48.0)
	root.add_child(clock)
	zone_clock = _label("ZoneClock", 24, Color(1, 1, 1, 0.85))
	_top_centre(zone_clock, 360.0, TOP + 48.0, 30.0)
	root.add_child(zone_clock)
	bars_box = HBoxContainer.new()
	bars_box.name = "Bars"
	bars_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars_box.alignment = BoxContainer.ALIGNMENT_CENTER
	bars_box.add_theme_constant_override("separation", int(BAR_GAP))
	_top_centre(bars_box, 400.0, TOP + 84.0, BAR_H + 70.0)
	root.add_child(bars_box)
	king_label = _label("King", 28, CROWN)
	_top_centre(king_label, 400.0, TOP + 84.0 + BAR_H + 74.0, 36.0)
	root.add_child(king_label)
	announcer = Announcer.new()
	announcer.name = "Announcer"
	announcer.set_anchors_preset(Control.PRESET_CENTER)
	announcer.offset_top = -150.0
	announcer.offset_bottom = -150.0
	announcer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	announcer.grow_vertical = Control.GROW_DIRECTION_BOTH
	announcer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := VBoxContainer.new()
	st.name = "Stack"
	st.set_anchors_preset(Control.PRESET_CENTER)
	st.grow_horizontal = Control.GROW_DIRECTION_BOTH
	st.grow_vertical = Control.GROW_DIRECTION_BOTH
	st.alignment = BoxContainer.ALIGNMENT_CENTER
	st.add_theme_constant_override("separation", -10)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	announcer.add_child(st)
	root.add_child(announcer)
	hint = _label("Hint", 22, Color(1, 1, 1, 0.75))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = 20.0
	hint.offset_right = 1900.0
	hint.offset_top = -96.0
	hint.offset_bottom = -44.0
	root.add_child(hint)
	toast_label = _label("Toast", 26, Color.WHITE)
	toast_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast_label.offset_left = -300.0
	toast_label.offset_right = 300.0
	toast_label.offset_top = -120.0
	toast_label.offset_bottom = -80.0
	toast_label.visible = false
	root.add_child(toast_label)
	_build_end()
	_apply_skin()
	HudSkin.events.changed.connect(func(_id: String) -> void: _apply_skin())


static func _top_centre(c: Control, half_w: float, top: float, h: float) -> void:
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.offset_left = -half_w
	c.offset_right = half_w
	c.offset_top = top
	c.offset_bottom = top + h


func _label(n: String, px: int, c: Color) -> Label:
	var l := Label.new()
	l.name = n
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_meta("px", px)
	l.set_meta("colour", c)
	return l


func _build_end() -> void:
	end_panel = PanelContainer.new()
	end_panel.name = "End"
	end_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_panel.set_anchors_preset(Control.PRESET_CENTER)
	end_panel.offset_left = -420.0
	end_panel.offset_right = 420.0
	end_panel.offset_top = -200.0
	end_panel.offset_bottom = 260.0
	end_panel.visible = false
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 10)
	end_panel.add_child(v)
	end_title = _label("Title", 56, Color.WHITE)
	end_sub = _label("Sub", 26, Color(1, 1, 1, 0.8))
	end_table = GridContainer.new()
	end_table.name = "Table"
	end_table.columns = 5
	end_table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_table.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	end_table.add_theme_constant_override("h_separation", 30)
	end_table.add_theme_constant_override("v_separation", 2)
	var again := _label("Again", 22, Color(1, 1, 1, 0.7))
	again.text = tr("R — заново · Esc — пауза и выход в гараж")
	for l in [end_title, end_sub, end_table, again]:
		v.add_child(l)
	root.add_child(end_panel)


func _apply_skin() -> void:
	for l in root.find_children("*", "Label", true, false):
		if (l as Node).has_meta("px"):
			HudSkin.style_label(l, "display", int(l.get_meta("px")), l.get_meta("colour"))
			(l as Label).add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			(l as Label).add_theme_constant_override("outline_size", 6)
	for pi in bars:
		_style_bar(int(pi), false)
	if end_panel != null:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.035, 0.05, 0.92)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 30.0
		sb.content_margin_right = 30.0
		sb.content_margin_top = 18.0
		sb.content_margin_bottom = 18.0
		end_panel.add_theme_stylebox_override("panel", sb)


func _style_bar(pi: int, lit: bool) -> void:
	var c: Dictionary = bars[pi]
	var col := KingMatch.colour_of(pi).lightened(0.25)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.09, 0.03, 0.92) if lit else Color(0.03, 0.035, 0.05, 0.86)
	sb.border_color = CROWN if lit else col
	sb.border_width_bottom = 6
	if lit:
		sb.border_width_top = 2
		sb.border_width_left = 2
		sb.border_width_right = 2
	sb.set_corner_radius_all(4)
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 6.0
	(c["panel"] as PanelContainer).add_theme_stylebox_override("panel", sb)
	c["lit"] = lit


func bind(m: KingMatch, pg: Node = null) -> void:
	match_node = m
	playground = pg
	var pairs := [["announce", _on_announce], ["phase_changed", _on_phase], ["match_over", _on_over], ["zone_moved", _on_zone_moved]]
	for p in pairs:
		if m.has_signal(p[0]) and not m.is_connected(p[0], p[1]):
			m.connect(p[0], p[1])
	refresh_hint()


func refresh_hint() -> void:
	if hint == null:
		return
	var p2b := true
	if playground != null and playground.get("p2_bot") != null:
		p2b = bool(playground.get("p2_bot"))
	var who := tr("U — P2 на стрелках") if p2b else tr("P2: стрелки + правый Ctrl + Enter (U — бот)")
	hint.text = "%s    %s    %s" % [tr("P1: WASD + Shift — будь в светящемся круге один: очко в секунду"), who,
		tr("K: уровень ботов    R: заново    Esc: пауза")]
	hint.visible = true
	hint.modulate.a = 1.0
	_time = 0.0


func toast(text: String) -> void:
	toast_label.text = text
	toast_label.visible = true
	toast_label.modulate.a = 1.0
	if _toast_tw != null and _toast_tw.is_valid():
		_toast_tw.kill()
	_toast_tw = toast_label.create_tween().set_ignore_time_scale(true)
	_toast_tw.tween_interval(1.2)
	_toast_tw.tween_property(toast_label, "modulate:a", 0.0, 0.3)
	_toast_tw.tween_callback(func() -> void: toast_label.visible = false)


## Имя куклы для HUD: P1 человека — ТЫ, остальные — P2…P5.
func name_of(d: Doll) -> String:
	if d != null and is_instance_valid(d) and d.player_index == 0 and not d.external_input:
		return tr("ТЫ")
	return KingMatch.doll_name(d)


static func clock_text(seconds: float) -> String:
	var s := maxi(int(ceil(seconds)), 0)
	return "%d:%02d" % [s / 60, s % 60]


## Строка про хозяина зоны: «ЦАРЬ: P3» / «ЗОНА: P3» / «ЗОНА СПОРНАЯ» / «ЗОНА СВОБОДНА».
func king_text() -> String:
	if match_node == null:
		return ""
	match match_node.zone_state:
		"held":
			if match_node.crowned:
				return tr("ЦАРЬ: %s") % name_of(match_node.holder)
			return tr("ЗОНА: %s") % name_of(match_node.holder)
		"contested":
			return tr("ЗОНА СПОРНАЯ")
	return tr("ЗОНА СВОБОДНА")


# --- сигналы ---

func _on_announce(text: String, color: Color, kind: String) -> void:
	if kind in ["countdown", "fight", "king", "ko"]:
		announcer.announce(text, color, kind)


func _on_phase(p: int) -> void:
	if p == Match.Phase.COUNTDOWN:
		end_panel.visible = false


func _on_zone_moved(_from_i: int, _to_i: int, _pos: Vector3) -> void:
	toast(tr("ЗОНА ПЕРЕЕХАЛА"))


func _on_over(winner: Doll, results: Dictionary) -> void:
	if winner != null:
		var me := winner.player_index == 0 and not winner.external_input
		end_title.text = tr("ТЫ ПОБЕДИЛ!") if me else tr("ПОБЕДИЛ %s") % KingMatch.doll_name(winner)
		end_title.set_meta("colour", KingMatch.colour_of(winner.player_index).lightened(0.35))
	else:
		end_title.text = tr("НИЧЬЯ")
		end_title.set_meta("colour", Color.WHITE)
	end_sub.text = tr("до %d очков · время матча %s · переездов зоны: %d") % [int(results.get("score_to_win", Tuning.KING_SCORE_TO_WIN)),
		clock_text(float(results.get("match_time", 0.0))), (results.get("moves", []) as Array).size()]
	for c in end_table.get_children():
		end_table.remove_child(c)
		c.queue_free()
	var white := Color(1, 1, 1, 0.75)
	var head := [tr("БОЕЦ"), tr("ОЧКИ"), tr("КОРОН"), tr("НОКАУТОВ"), tr("ВЫБИТ")]
	for i in head.size():
		_cell(head[i], white, i == 0)
	var tally: Dictionary = results.get("tally", {})
	var sc: Dictionary = results.get("scores", {})
	for d in results.get("places", []):
		var dd := d as Doll
		if dd == null or not is_instance_valid(dd):
			continue
		var t: Dictionary = tally.get(dd.player_index, {})
		_cell(name_of(dd), KingMatch.colour_of(dd.player_index).lightened(0.4), true)
		_cell(str(int(sc.get(dd.player_index, 0))), Color.WHITE, false)
		_cell(str(int(t.get("crowns", 0))), Color.WHITE, false)
		_cell(str(int(t.get("kos", 0))), Color.WHITE, false)
		_cell(str(int(t.get("kos_taken", 0))), Color.WHITE, false)
	_apply_skin()
	end_panel.visible = true
	end_panel.modulate.a = 0.0
	var tw := end_panel.create_tween().set_ignore_time_scale(true)
	tw.tween_interval(0.6)
	tw.tween_property(end_panel, "modulate:a", 1.0, 0.3)


func _cell(text: String, c: Color, left: bool) -> void:
	var l := _label("Cell", 22, c)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_CENTER
	end_table.add_child(l)


# --- столбики ---

func _ensure_bar(d: Doll) -> Dictionary:
	var pi := d.player_index
	if bars.has(pi):
		return bars[pi]
	var panel := PanelContainer.new()
	panel.name = "Bar%d" % pi
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(BAR_W, 0.0)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 0)
	panel.add_child(v)
	var nm := _label("Name", 24, KingMatch.colour_of(pi).lightened(0.35))
	var bar := Control.new()
	bar.name = "Fill"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size = Vector2(0.0, BAR_H)
	bar.draw.connect(_draw_bar.bind(bar, pi))
	var val := _label("Value", 26, Color.WHITE)
	for n in [nm, bar, val]:
		v.add_child(n)
	var at := bars_box.get_child_count()
	for i in bars_box.get_child_count():
		if int(bars_box.get_child(i).get_meta("pi", 0)) > pi:
			at = i
			break
	panel.set_meta("pi", pi)
	bars_box.add_child(panel)
	bars_box.move_child(panel, at)
	bars[pi] = {"panel": panel, "name": nm, "bar": bar, "value": val, "lit": false}
	_apply_skin()
	return bars[pi]


## Столбик очков снизу вверх до KING_SCORE_TO_WIN; у царя — золотая корона-полоса сверху.
func _draw_bar(c: Control, pi: int) -> void:
	var to_win := match_node.score_to_win if match_node != null else float(Tuning.KING_SCORE_TO_WIN)
	var have := float(match_node.scores.get(pi, 0.0)) if match_node != null else 0.0
	var col := KingMatch.colour_of(pi).lightened(0.2)
	var w := 34.0
	var r := Rect2(Vector2(c.size.x * 0.5 - w * 0.5, 4.0), Vector2(w, c.size.y - 8.0))
	c.draw_rect(r, Color(1, 1, 1, 0.08))
	var k := clampf(have / maxf(to_win, 1.0), 0.0, 1.0)
	var fill := Rect2(Vector2(r.position.x, r.end.y - r.size.y * k), Vector2(w, r.size.y * k))
	c.draw_rect(fill, col)
	c.draw_rect(r, Color(col, 0.6), false, 2.0)
	if match_node != null and match_node.crowned and match_node.holder != null and is_instance_valid(match_node.holder) \
			and match_node.holder.player_index == pi:
		c.draw_rect(Rect2(r.position - Vector2(6.0, 4.0), Vector2(w + 12.0, 6.0)), CROWN)


func _update_bars() -> void:
	if match_node == null:
		return
	for d in match_node.dolls():
		var dd := d as Doll
		var c := _ensure_bar(dd)
		(c["name"] as Label).text = name_of(dd)
		(c["value"] as Label).text = str(int(floor(float(match_node.scores.get(dd.player_index, 0.0)))))
		var lit := match_node.holder == dd
		if lit != bool(c["lit"]):
			_style_bar(dd.player_index, lit)
		(c["panel"] as Control).modulate.a = 1.0 if dd.alive or match_node.play_state == "countdown" else 0.5
		(c["bar"] as Control).queue_redraw()
	clock.text = clock_text(match_node.time_left_s())
	var zl := match_node.zone_left if match_node.play_state == "play" else match_node.zone_period_s
	zone_clock.text = tr("ЗОНА ПЕРЕЕДЕТ: %s") % clock_text(zl)
	var warn := match_node.play_state == "play" and match_node.warning()
	var zc: Color = KingMatch.ZONE_COLOUR_CONTESTED if warn else Color(1, 1, 1, 0.85)
	if zc != zone_clock.get_meta("colour"):
		zone_clock.set_meta("colour", zc)
		HudSkin.style_label(zone_clock, "display", int(zone_clock.get_meta("px")), zc)
	king_label.text = king_text()
	var kc: Color = KingZone.colour_for(match_node)
	if match_node.zone_state == "held" and match_node.crowned:
		kc = CROWN
	if kc != king_label.get_meta("colour"):
		king_label.set_meta("colour", kc)
		HudSkin.style_label(king_label, "display", int(king_label.get_meta("px")), kc)


# --- кадр ---

func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.02)
	_time += real
	if hint.visible and _time > HINT_S:
		hint.modulate.a = maxf(hint.modulate.a - real * 1.5, 0.0)
		hint.visible = hint.modulate.a > 0.0
	_update_bars()
	marks.queue_redraw()


## Имена над куклами; у выбитых — «ВОЗВРАТ N» на месте нокаута.
func _draw_marks() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or match_node == null or end_panel.visible:
		return
	var font := HudSkin.font("display")
	if font == null:
		font = ThemeDB.fallback_font
	var vp := get_viewport().get_visible_rect().size
	var to_canvas := marks.get_global_transform_with_canvas().affine_inverse()
	for n in match_node.dolls():
		var d := n as Doll
		if not is_instance_valid(d) or not d.is_inside_tree():
			continue
		var torso := d.torso()
		if torso == null:
			continue
		var head: Node3D = d.parts.get("Head", torso) as Node3D
		var top := Vector3(head.global_position.x, maxf(head.global_position.y, torso.global_position.y + 0.35) + NAME_LIFT, 0.0)
		if cam.is_position_behind(top):
			continue
		var sp: Vector2 = to_canvas * cam.unproject_position(top)
		if sp.x < 0.0 or sp.y < 0.0 or sp.x > vp.x or sp.y > vp.y:
			continue
		var col := KingMatch.colour_of(d.player_index).lightened(0.3)
		var txt := name_of(d)
		if not d.alive:
			var left := match_node.respawn_left(d)
			if left < 0.0:
				continue
			txt = tr("ВОЗВРАТ %d") % int(ceil(left))
			col = Color(1, 1, 1, 0.8)
		elif match_node.crowned and match_node.holder == d:
			txt = tr("ЦАРЬ %s") % txt
			col = CROWN
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
		marks.draw_string_outline(font, sp + Vector2(-tw.x * 0.5, 0.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color(0, 0, 0, 0.9))
		marks.draw_string(font, sp + Vector2(-tw.x * 0.5, 0.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)
