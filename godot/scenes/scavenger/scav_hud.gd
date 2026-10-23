## HUD «Собери себя» (docs/plan-demo/SCAVENGER.md). Дерево строит сам, шрифты — по скину HUD (HudSkin), смена скина перекрашивает
## на лету:
##   • сверху по центру — «СОБЕРИ СЕБЯ», таймер матча; под ним — пять плашек бойцов: имя цветом рубашки и «N/12» деталей
##     (выбитый — «ВЫБИТ», плашка тусклая);
##   • снизу слева — крупно «ДЕТАЛИ N/12» главной куклы (человек P1; нет человека — скрыто);
##   • над куклами — имя, «N/12» и полоска запаса; прикрутил деталь — над куклой всплывает «+1 ДЕТАЛЬ» (у полного набора —
##     «ПОЛНЫЙ НАБОР!»);
##   • детали на карте — пульсирующее кольцо; за кадром — стрелки у края экрана к Tuning.SCAV_HUD_ARROWS ближайшим деталям,
##     которые главная кукла может прикрутить («ДЕТАЛЬ · 7 м»);
##   • диктор (Announcer) — отсчёт, FIGHT!, KO!; снизу — подсказка клавиш (гаснет через HINT_S), тосты U / K / M / N / H;
##   • конец матча — табличка: «ПОБЕДА: P3» / «ТЫ ПОБЕДИЛ» / «НИЧЬЯ», причина, таблица (деталей, подобрал, нокаутов, место), медали.
## bind(match, playground) — подписка на ScavMatch по именам сигналов.
class_name ScavHud
extends CanvasLayer

const TOP := 12.0
const HINT_S := 14.0
const NAME_LIFT := 0.5
const BAR_W := 64.0
const BAR_H := 7.0
const EDGE := 46.0
const ARROW := 16.0
const ARROW_GAP := 56.0   # стрелки к деталям ближе этого на краю экрана сливаются в одну (подписи не налезают)
const PLATE_W := 150.0
const PLATE_GAP := 10.0
const POP_S := 1.2

var match_node: ScavMatch
var playground: Node
var root: Control
var announcer: Announcer
var caption: Label
var timer_label: Label
var plates: Array = []          # [PanelContainer, name Label, count Label] по player_index
var mine_label: Label
var marks: Control
var hint: Label
var toast_label: Label
var end_panel: PanelContainer
var end_title: Label
var end_sub: Label
var end_table: GridContainer
var end_medals: Label
## Для проб: сколько стрелок за кадром и колец на деталях нарисовано в последнем кадре.
var arrows_drawn := 0
var rings_drawn := 0
var popups: Array = []          # [{doll, text, colour, t}]
var _clock := 0.0
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
	caption = _label("Caption", 26, Color(1, 1, 1, 0.85))
	_centre(caption, -400.0, 400.0, TOP, TOP + 34.0)
	root.add_child(caption)
	timer_label = _label("Timer", 24, Color(1, 1, 1, 0.8))
	_centre(timer_label, -200.0, 200.0, TOP + 34.0, TOP + 62.0)
	root.add_child(timer_label)
	var n := Tuning.SCAV_DOLLS
	var total := PLATE_W * n + PLATE_GAP * (n - 1)
	for i in n:
		var panel := PanelContainer.new()
		panel.name = "Plate%d" % i
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var x0 := -total * 0.5 + (PLATE_W + PLATE_GAP) * i
		_centre(panel, x0, x0 + PLATE_W, TOP + 66.0, TOP + 66.0 + 40.0)
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_theme_constant_override("separation", 10)
		panel.add_child(h)
		var col: Color = Tuning.SCAV_COLORS[i % Tuning.SCAV_COLORS.size()]
		var nm := _label("Name", 22, col.lightened(0.35))
		var cnt := _label("Count", 22, Color.WHITE)
		h.add_child(nm)
		h.add_child(cnt)
		root.add_child(panel)
		plates.append([panel, nm, cnt])
	mine_label = _label("Mine", 40, Tuning.SCAV_GLOW_COLOR)
	mine_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	mine_label.anchor_top = 1.0
	mine_label.anchor_bottom = 1.0
	mine_label.offset_left = 24.0
	mine_label.offset_right = 520.0
	mine_label.offset_top = -170.0
	mine_label.offset_bottom = -110.0
	mine_label.visible = false
	root.add_child(mine_label)
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
	hint.offset_bottom = -44.0   # ниже — метка «Tab — управление» (ControlFeelPanel)
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN   # две строки растут вверх, не на метку Tab
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


static func _centre(c: Control, l: float, r: float, t: float, b: float) -> void:
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.offset_left = l
	c.offset_right = r
	c.offset_top = t
	c.offset_bottom = b


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
	end_panel.offset_left = -460.0
	end_panel.offset_right = 460.0
	end_panel.offset_top = -280.0
	end_panel.offset_bottom = 280.0
	end_panel.visible = false
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 8)
	end_panel.add_child(v)
	end_title = _label("Title", 52, Color.WHITE)
	end_sub = _label("Sub", 26, Color(1, 1, 1, 0.8))
	end_table = GridContainer.new()
	end_table.name = "Table"
	end_table.columns = 5
	end_table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_table.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	end_table.add_theme_constant_override("h_separation", 26)
	end_table.add_theme_constant_override("v_separation", 0)
	end_medals = _label("Medals", 20, Color(1.0, 0.85, 0.4))
	end_medals.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var again := _label("Again", 22, Color(1, 1, 1, 0.7))
	again.text = tr("R — заново · Esc — пауза и выход в гараж")
	for l in [end_title, end_sub, end_table, end_medals, again]:
		v.add_child(l)
	root.add_child(end_panel)


func _apply_skin() -> void:
	for l in root.find_children("*", "Label", true, false):
		if (l as Node).has_meta("px"):
			HudSkin.style_label(l, "display", int(l.get_meta("px")), l.get_meta("colour"))
			(l as Label).add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			(l as Label).add_theme_constant_override("outline_size", 6)
	for i in plates.size():
		_style_plate(i, true)
	if end_panel != null:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.035, 0.05, 0.92)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 30.0
		sb.content_margin_right = 30.0
		sb.content_margin_top = 18.0
		sb.content_margin_bottom = 18.0
		end_panel.add_theme_stylebox_override("panel", sb)


func _style_plate(i: int, alive: bool) -> void:
	var panel := plates[i][0] as PanelContainer
	var col: Color = Tuning.SCAV_COLORS[i % Tuning.SCAV_COLORS.size()]
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.035, 0.05, 0.86)
	sb.border_color = col.lightened(0.25) if alive else Color(0.4, 0.4, 0.4, 0.6)
	sb.border_width_bottom = 5
	sb.set_corner_radius_all(4)
	sb.content_margin_top = 2.0
	sb.content_margin_bottom = 4.0
	sb.content_margin_left = 6.0
	sb.content_margin_right = 6.0
	panel.add_theme_stylebox_override("panel", sb)
	panel.modulate.a = 1.0 if alive else 0.55


func bind(m: ScavMatch, pg: Node = null) -> void:
	match_node = m
	playground = pg
	var pairs := [["announce", _on_announce], ["phase_changed", _on_phase], ["match_over", _on_over], ["part_attached", _on_attached]]
	for p in pairs:
		if m.has_signal(p[0]) and not m.is_connected(p[0], p[1]):
			m.connect(p[0], p[1])
	caption.text = tr("СОБЕРИ СЕБЯ")
	refresh_hint()
	_refresh_plates()


func refresh_hint() -> void:
	if hint == null:
		return
	var p2h := false
	if playground != null and playground.get("p2_human") != null:
		p2h = bool(playground.get("p2_human"))
	var who := tr("P2: стрелки + правый Ctrl + Enter (U — бот)") if p2h else tr("U — P2 на стрелках")
	hint.text = "%s\n%s    %s" % [tr("P1: WASD + Shift — коснись светящейся детали, она прикрутится; выбей соперника — его детали твои"), who,
		tr("K: уровень ботов    R: заново    Esc: пауза")]
	hint.visible = true
	hint.modulate.a = 1.0
	_clock = 0.0


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
	return ScavMatch.doll_name(d)


# --- сигналы ---

func _on_announce(text: String, color: Color, kind: String) -> void:
	if kind in ["countdown", "fight", "ko"]:
		announcer.announce(text, color, kind)


func _on_phase(p: int) -> void:
	if p == Match.Phase.COUNTDOWN:
		end_panel.visible = false
		popups.clear()


func _on_attached(d: Doll, _kind: String, count: int) -> void:
	var full := count >= Tuning.SCAV_MAX_PARTS
	popups.append({"doll": d, "text": tr("ПОЛНЫЙ НАБОР!") if full else tr("+1 ДЕТАЛЬ"),
		"colour": ScavMatch.colour_of(d).lightened(0.45), "t": 0.0})
	if popups.size() > 12:
		popups.pop_front()


func _on_over(winner: Doll, results: Dictionary) -> void:
	if winner == null or not is_instance_valid(winner):
		end_title.text = tr("НИЧЬЯ")
		end_title.set_meta("colour", Color.WHITE)
	elif winner.player_index == 0 and not winner.external_input:
		end_title.text = tr("ТЫ ПОБЕДИЛ")
		end_title.set_meta("colour", ScavMatch.colour_of(winner).lightened(0.35))
	else:
		end_title.text = tr("ПОБЕДА: %s") % name_of(winner)
		end_title.set_meta("colour", ScavMatch.colour_of(winner).lightened(0.35))
	var secs := int(match_node.fight_time) if match_node != null else 0
	var why := tr("последний на ногах") if String(results.get("reason", "")) == "last" else tr("время вышло · больше деталей")
	end_sub.text = "%s · %d:%02d" % [why, secs / 60, secs % 60]
	for c in end_table.get_children():
		end_table.remove_child(c)
		c.queue_free()
	var white := Color(1, 1, 1, 0.75)
	for h in [tr("БОЕЦ"), tr("ДЕТАЛЕЙ"), tr("ПОДОБРАЛ"), tr("НОКАУТОВ"), tr("МЕСТО")]:
		_cell(h, white, end_table.get_child_count() == 0)
	var tally: Dictionary = results.get("tally", {})
	var places: Array = results.get("places", [])
	var ranks: Array = results.get("ranks", [])
	for i in places.size():
		var dd := places[i] as Doll
		if dd == null or not is_instance_valid(dd):
			continue
		var t: Dictionary = tally.get(dd.player_index, {})
		_cell(name_of(dd), ScavMatch.colour_of(dd).lightened(0.4), true)
		var parts := "%d/%d" % [int(t.get("parts", 0)), Tuning.SCAV_MAX_PARTS]
		if not dd.alive:
			parts += " · KO"
		_cell(parts, Color.WHITE, false)
		_cell(str(int(t.get("picked", 0))), Color.WHITE, false)
		_cell(str(int(t.get("kos", 0))), Color.WHITE, false)
		_cell(str(int(ranks[i]) + 1 if i < ranks.size() else i + 1), Color.WHITE, false)
	var medals: Dictionary = results.get("medals", {})
	var mparts: Array = []
	for k in medals.keys():
		var md: Object = medals[k]
		if is_instance_valid(md) and md is Doll:
			mparts.append("%s — %s" % [ResultsPanel.medal_title(String(k)), name_of(md as Doll)])
	end_medals.text = (tr("МЕДАЛИ: ") + " · ".join(mparts)) if not mparts.is_empty() else ""
	end_medals.visible = not mparts.is_empty()
	_apply_skin()
	end_panel.visible = true
	end_panel.modulate.a = 0.0
	var tw := end_panel.create_tween().set_ignore_time_scale(true)
	tw.tween_interval(0.6)
	tw.tween_property(end_panel, "modulate:a", 1.0, 0.3)


func _cell(text: String, c: Color, left: bool) -> void:
	var l := _label("Cell", 20, c)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_CENTER
	end_table.add_child(l)


# --- кадр ---

func _refresh_plates() -> void:
	if match_node == null:
		return
	for i in plates.size():
		var d := _doll(i)
		var nm := plates[i][1] as Label
		var cnt := plates[i][2] as Label
		var panel := plates[i][0] as PanelContainer
		panel.visible = d != null
		if d == null:
			continue
		nm.text = name_of(d)
		var alive := d.alive
		cnt.text = ("%d/%d" % [match_node.parts_count(d), Tuning.SCAV_MAX_PARTS]) if alive else tr("ВЫБИТ")
		if bool(panel.get_meta("alive", true)) != alive:
			panel.set_meta("alive", alive)
			_style_plate(i, alive)
	var me := match_node.me()
	mine_label.visible = me != null and me.alive and match_node.play_state != "idle"
	if mine_label.visible:
		mine_label.text = tr("ДЕТАЛИ %d/%d") % [match_node.parts_count(me), Tuning.SCAV_MAX_PARTS]


func _doll(i: int) -> Doll:
	for d in match_node.dolls():
		if (d as Doll).player_index == i:
			return d
	return null


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.02)
	_clock += real
	if hint.visible and _clock > HINT_S:
		hint.modulate.a = maxf(hint.modulate.a - real * 1.5, 0.0)
		hint.visible = hint.modulate.a > 0.0
	for p in popups:
		p["t"] = float(p["t"]) + real
	popups = popups.filter(func(p: Dictionary) -> bool: return float(p["t"]) < POP_S)
	if match_node != null:
		if match_node.play_state == "play" or match_node.play_state == "countdown":
			var left := match_node.time_left_s()
			timer_label.text = "%d:%02d" % [int(left) / 60, int(left) % 60]
		else:
			timer_label.text = ""
		_refresh_plates()
	marks.queue_redraw()


## Главная кукла для стрелок: человек с меньшим player_index, иначе P1.
func _main_doll() -> Doll:
	if match_node == null:
		return null
	var m := match_node.me()
	if m != null:
		return m
	return _doll(0)


func _draw_marks() -> void:
	arrows_drawn = 0
	rings_drawn = 0
	var cam := get_viewport().get_camera_3d()
	if cam == null or match_node == null or end_panel.visible:
		return
	var font := HudSkin.font("display")
	if font == null:
		font = ThemeDB.fallback_font
	var vp := get_viewport().get_visible_rect().size
	var to_canvas := marks.get_global_transform_with_canvas().affine_inverse()
	# куклы: имя, N/12, запас
	for n in match_node.dolls():
		var d := n as Doll
		if not is_instance_valid(d) or not d.is_inside_tree() or not d.alive:
			continue
		var sp := _over_head(cam, to_canvas, d)
		if sp.x < -80.0 or sp.y < -60.0 or sp.x > vp.x + 80.0 or sp.y > vp.y + 40.0:
			continue
		var col := ScavMatch.colour_of(d).lightened(0.3)
		_text_c(font, sp + Vector2(0.0, -6.0), "%s  %d/%d" % [name_of(d), match_node.parts_count(d), Tuning.SCAV_MAX_PARTS], 20, col)
		var frac := clampf(d.hp / maxf(d.max_hp, 1.0), 0.0, 1.0)
		var r := Rect2(sp + Vector2(-BAR_W * 0.5, 0.0), Vector2(BAR_W, BAR_H))
		marks.draw_rect(r.grow(1.0), Color(0, 0, 0, 0.7))
		marks.draw_rect(Rect2(r.position, Vector2(BAR_W * frac, BAR_H)), col.lerp(Color(1.0, 0.3, 0.2), 1.0 - frac))
	# всплывающие «+1 ДЕТАЛЬ»
	for p in popups:
		var pd: Object = p["doll"]
		if not is_instance_valid(pd) or not (pd is Doll) or not (pd as Doll).is_inside_tree():
			continue
		var k := float(p["t"]) / POP_S
		var at := _over_head(cam, to_canvas, pd as Doll) + Vector2(0.0, -34.0 - 40.0 * k)
		var c: Color = p["colour"]
		c.a = 1.0 - k * k
		_text_c(font, at, String(p["text"]), 26, c)
	# детали: кольцо в кадре, стрелки к ближайшим нужным за кадром
	var main := _main_doll()
	var rect := Rect2(Vector2(EDGE, EDGE + 110.0), vp - Vector2(EDGE * 2.0, EDGE * 2.0 + 150.0))
	var from := main.centre_of_mass() if main != null and main.is_inside_tree() and main.alive else Vector3.INF
	var pulse := 0.5 + 0.5 * sin(TAU * Tuning.SCAV_GLOW_HZ * _clock)
	var gc := Tuning.SCAV_GLOW_COLOR
	var off: Array = []
	for t in match_node.tokens():
		var tp := (t as Node3D).global_position
		if cam.is_position_behind(tp):
			continue
		var spt: Vector2 = to_canvas * cam.unproject_position(tp)
		if rect.has_point(spt):
			marks.draw_arc(spt, 20.0 + 5.0 * pulse, 0.0, TAU, 24, Color(gc, 0.5 + 0.4 * pulse), 3.0, true)
			rings_drawn += 1
		elif from != Vector3.INF and match_node.token_wanted_by(t, main):
			off.append([Vector2(tp.x - from.x, tp.y - from.y).length(), spt])
	off.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	# Детали кучей в одной стороне дают стрелки в одну точку края — подписи
	# ложились друг на друга («ДЕТАЛЬ · 13 м» дважды). Ближняя из кучи — одна стрелка.
	var used: Array[Vector2] = []
	for o in off:
		if used.size() >= Tuning.SCAV_HUD_ARROWS:
			break
		var at := _edge_point(rect, o[1])
		var near := false
		for u in used:
			if u.distance_to(at) < ARROW_GAP:
				near = true
				break
		if near:
			continue
		used.append(at)
		_edge_arrow(font, rect, o[1], gc, tr("ДЕТАЛЬ · %d м") % int(round(float(o[0]))))


func _over_head(cam: Camera3D, to_canvas: Transform2D, d: Doll) -> Vector2:
	var torso := d.torso() as Node3D
	var head: Node3D = d.parts.get("Head", torso) as Node3D
	if head == null:
		return Vector2(-1000.0, -1000.0)
	var ty := torso.global_position.y if torso != null else head.global_position.y
	var top := Vector3(head.global_position.x, maxf(head.global_position.y, ty + 0.35) + NAME_LIFT, 0.0)
	if cam.is_position_behind(top):
		return Vector2(-1000.0, -1000.0)
	return to_canvas * cam.unproject_position(top)


func _text_c(font: Font, at: Vector2, txt: String, px: int, col: Color) -> void:
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
	marks.draw_string_outline(font, at + Vector2(-tw.x * 0.5, 0.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 6, Color(0, 0, 0, col.a * 0.9))
	marks.draw_string(font, at + Vector2(-tw.x * 0.5, 0.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


## Стрелка у края rect в сторону точки p (экран), подпись рядом.
## Точка на краю rect по лучу из его центра к p (экран).
func _edge_point(rect: Rect2, p: Vector2) -> Vector2:
	var c := rect.get_center()
	var d := p - c
	var k := INF
	if absf(d.x) > 0.001:
		k = minf(k, (rect.size.x * 0.5) / absf(d.x))
	if absf(d.y) > 0.001:
		k = minf(k, (rect.size.y * 0.5) / absf(d.y))
	return c + d * k if k != INF else c


func _edge_arrow(font: Font, rect: Rect2, p: Vector2, col: Color, txt: String) -> void:
	var d := p - rect.get_center()
	if d.length() < 1.0:
		return
	var at := _edge_point(rect, p)
	var dir := d.normalized()
	var side := Vector2(-dir.y, dir.x)
	var tri := PackedVector2Array([at + dir * ARROW, at - dir * ARROW * 0.6 + side * ARROW * 0.8, at - dir * ARROW * 0.6 - side * ARROW * 0.8])
	marks.draw_colored_polygon(tri, col)
	marks.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(0, 0, 0, 0.8), 2.0, true)
	_text_c(font, at - dir * 34.0 + Vector2(0.0, 6.0), txt, 18, col)
	arrows_drawn += 1
