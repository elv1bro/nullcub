## HUD «Бомбы касанием» (docs/plan-demo/BOMB.md). Боевой HUD (scenes/ui/hud.gd) — про HP, а урона в режиме нет; здесь свой. Дерево
## строит сам, шрифты — по скину HUD (HudSkin), смена скина перекрашивает на лету:
##   • сверху по центру — «ПАРТИЯ N · ДО 3 ПОБЕД», под ним плашки пятерых: имя цветом куклы, кто она (ТЫ / ИГРОК / БОТ), у держателя —
##     «БОМБА» (плашка мигает с писком), у выбывшего — «ВЫБЫЛ» (тусклая), точки побед в партиях; под плашками — «ЖИВЫХ: N ИЗ 5»;
##   • над куклами — имя цветом куклы; над держателем — красное кольцо и «БОМБА», вспыхивают на каждый писк (BombMatch.beeped);
##     держатель за кадром — стрелка у края экрана (BombMarkers — отдельный слой сцены);
##   • диктор (Announcer) — отсчёт, FIGHT!, «БОМБА У P3», БУМ!, «P2 БЕРЁТ ПАРТИЮ»;
##   • снизу — подсказка клавиш (гаснет через HINT_S), тосты U / K / M / N / H;
##   • конец матча — табличка победителя и таблица бойцов (победы, отдал бомбу, взорвался), «R — заново».
## bind(match, playground) — подписка на BombMatch по именам сигналов.
class_name BombHud
extends CanvasLayer

const CHIP_W := 150.0
const CHIP_GAP := 12.0
const TOP := 12.0
const HINT_S := 14.0
const NAME_LIFT := 0.5           # м над головой
const RING_R := 46.0             # px: кольцо вокруг бомбы
const PIP_R := 6.0
const COLOUR_OUT := Color(0.6, 0.6, 0.65)

var match_node: BombMatch
var playground: Node
var root: Control
var announcer: Announcer
var caption: Label
var alive_label: Label
var chips_box: HBoxContainer
var chips: Dictionary = {}       # player_index → {panel, name, status, pips}
var marks: Control
var hint: Label
var toast_label: Label
var end_panel: PanelContainer
var end_title: Label
var end_sub: Label
var end_table: GridContainer
var _pulse := 0.0                # 1 на писк, гаснет — вспышка метки и плашки держателя
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
	caption = _label("Caption", 30, Color(1, 1, 1, 0.9))
	caption.anchor_left = 0.5
	caption.anchor_right = 0.5
	caption.offset_left = -400.0
	caption.offset_right = 400.0
	caption.offset_top = TOP
	caption.offset_bottom = TOP + 40.0
	root.add_child(caption)
	chips_box = HBoxContainer.new()
	chips_box.name = "Chips"
	chips_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips_box.alignment = BoxContainer.ALIGNMENT_CENTER
	chips_box.add_theme_constant_override("separation", int(CHIP_GAP))
	chips_box.anchor_left = 0.5
	chips_box.anchor_right = 0.5
	chips_box.offset_left = -480.0
	chips_box.offset_right = 480.0
	chips_box.offset_top = TOP + 44.0
	chips_box.offset_bottom = TOP + 44.0 + 84.0
	root.add_child(chips_box)
	alive_label = _label("Alive", 22, Color(1, 1, 1, 0.75))
	alive_label.anchor_left = 0.5
	alive_label.anchor_right = 0.5
	alive_label.offset_left = -300.0
	alive_label.offset_right = 300.0
	alive_label.offset_top = TOP + 134.0
	alive_label.offset_bottom = TOP + 164.0
	root.add_child(alive_label)
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
	st.grow_horizontal = Control.GROW_DIRECTION_BOTH   # надпись по центру экрана, а не от центра вправо (как в hud.tscn)
	st.grow_vertical = Control.GROW_DIRECTION_BOTH
	st.alignment = BoxContainer.ALIGNMENT_CENTER
	st.add_theme_constant_override("separation", -10)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	announcer.add_child(st)
	root.add_child(announcer)
	hint = _label("Hint", 22, Color(1, 1, 1, 0.75))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # длинный язык — вторая строка, а не за край экрана
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = 20.0
	hint.offset_right = 1900.0
	hint.offset_top = -96.0
	hint.offset_bottom = -44.0   # ниже — метка «Tab — управление» (ControlFeelPanel) в левом нижнем углу
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
	end_panel.offset_left = -400.0
	end_panel.offset_right = 400.0
	end_panel.offset_top = -170.0
	end_panel.offset_bottom = 270.0
	end_panel.visible = false
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 10)
	end_panel.add_child(v)
	end_title = _label("Title", 56, Color.WHITE)
	end_sub = _label("Sub", 26, Color(1, 1, 1, 0.8))
	end_table = GridContainer.new()
	end_table.name = "Table"
	end_table.columns = 4
	end_table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_table.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	end_table.add_theme_constant_override("h_separation", 34)
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
	for pi in chips:
		_style_chip(int(pi), false)
	if end_panel != null:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.035, 0.05, 0.92)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 30.0
		sb.content_margin_right = 30.0
		sb.content_margin_top = 18.0
		sb.content_margin_bottom = 18.0
		end_panel.add_theme_stylebox_override("panel", sb)


func _style_chip(pi: int, hot: bool) -> void:
	var c: Dictionary = chips[pi]
	var col := BombMatch.colour_of(pi).lightened(0.25)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.32, 0.05, 0.03, 0.9) if hot else Color(0.03, 0.035, 0.05, 0.86)
	sb.border_color = BombMatch.COLOUR_BOMB if hot else col
	sb.border_width_bottom = 6
	if hot:
		sb.border_width_top = 3
		sb.border_width_left = 3
		sb.border_width_right = 3
	sb.set_corner_radius_all(4)
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 6.0
	(c["panel"] as PanelContainer).add_theme_stylebox_override("panel", sb)
	c["hot"] = hot


func bind(m: BombMatch, pg: Node = null) -> void:
	match_node = m
	playground = pg
	var pairs := [["announce", _on_announce], ["phase_changed", _on_phase], ["match_over", _on_over], ["beeped", _on_beep],
		["round_started", _on_round]]
	for p in pairs:
		if m.has_signal(p[0]) and not m.is_connected(p[0], p[1]):
			m.connect(p[0], p[1])
	_on_round(maxi(m.round_i, 1))
	refresh_hint()


func refresh_hint() -> void:
	if hint == null:
		return
	var p2b := true
	if playground != null and playground.get("p2_bot") != null:
		p2b = bool(playground.get("p2_bot"))
	var who := tr("U — P2 на стрелках") if p2b else tr("P2: стрелки + правый Ctrl + Enter (U — бот)")
	hint.text = "%s    %s    %s" % [tr("P1: WASD + Shift — коснись другого, и бомба у него"), who,
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
	return BombMatch.doll_name(d)


# --- сигналы ---

func _on_announce(text: String, color: Color, kind: String) -> void:
	if kind in ["countdown", "fight", "bomb", "ko", "round"]:
		announcer.announce(text, color, kind)


func _on_phase(p: int) -> void:
	if p == Match.Phase.COUNTDOWN:
		end_panel.visible = false


func _on_round(r: int) -> void:
	var n := match_node.wins_to_win if match_node != null else Tuning.BOMB_WINS_TO_WIN
	caption.text = tr("ПАРТИЯ %d · ДО %d ПОБЕД") % [r, n]


func _on_beep(_urgency: float) -> void:
	_pulse = 1.0


func _on_over(winner: Doll, results: Dictionary) -> void:
	if winner != null:
		var me := winner.player_index == 0 and not winner.external_input
		end_title.text = tr("ТЫ ПОБЕДИЛ!") if me else tr("ПОБЕДИЛ %s") % BombMatch.doll_name(winner)
		end_title.set_meta("colour", BombMatch.colour_of(winner.player_index).lightened(0.35))
	else:
		end_title.text = tr("НИЧЬЯ")
		end_title.set_meta("colour", Color.WHITE)
	end_sub.text = tr("партий: %d · бомба передавалась %d раз") % [(results.get("rounds", []) as Array).size(), int(results.get("passes", 0))]
	for c in end_table.get_children():
		end_table.remove_child(c)
		c.queue_free()
	var white := Color(1, 1, 1, 0.75)
	for h in [tr("БОЕЦ"), tr("ПОБЕД"), tr("ОТДАЛ"), tr("ВЗОРВАЛСЯ")]:
		_cell(h, white, end_table.get_child_count() == 0)
	var tally: Dictionary = results.get("tally", {})
	for d in results.get("places", []):
		var dd := d as Doll
		if dd == null or not is_instance_valid(dd):
			continue
		var t: Dictionary = tally.get(dd.player_index, {})
		_cell(name_of(dd), BombMatch.colour_of(dd.player_index).lightened(0.4), true)
		_cell(str(int(t.get("wins", 0))), Color.WHITE, false)
		_cell(str(int(t.get("passed", 0))), Color.WHITE, false)
		_cell(str(int(t.get("exploded", 0))), Color.WHITE, false)
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


# --- плашки ---

func _ensure_chip(d: Doll) -> Dictionary:
	var pi := d.player_index
	if chips.has(pi):
		return chips[pi]
	var panel := PanelContainer.new()
	panel.name = "Chip%d" % pi
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(CHIP_W, 0.0)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 0)
	panel.add_child(v)
	var nm := _label("Name", 30, BombMatch.colour_of(pi).lightened(0.35))
	var stl := _label("Status", 18, Color(1, 1, 1, 0.8))
	var pips := Control.new()
	pips.name = "Pips"
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.custom_minimum_size = Vector2(0.0, PIP_R * 2.0 + 6.0)
	pips.draw.connect(_draw_pips.bind(pips, pi))
	for n in [nm, stl, pips]:
		v.add_child(n)
	# по порядку player_index
	var at := chips_box.get_child_count()
	for i in chips_box.get_child_count():
		if int(chips_box.get_child(i).get_meta("pi", 0)) > pi:
			at = i
			break
	panel.set_meta("pi", pi)
	chips_box.add_child(panel)
	chips_box.move_child(panel, at)
	chips[pi] = {"panel": panel, "name": nm, "status": stl, "pips": pips, "hot": false}
	_apply_skin()
	return chips[pi]


func _draw_pips(c: Control, pi: int) -> void:
	var n := match_node.wins_to_win if match_node != null else Tuning.BOMB_WINS_TO_WIN
	var have := int(match_node.wins.get(pi, 0)) if match_node != null else 0
	var col := BombMatch.colour_of(pi).lightened(0.35)
	var step := PIP_R * 2.0 + 8.0
	var x0 := c.size.x * 0.5 - step * float(n - 1) * 0.5
	for i in n:
		var p := Vector2(x0 + step * float(i), c.size.y * 0.5)
		if i < have:
			c.draw_circle(p, PIP_R, col)
		else:
			c.draw_arc(p, PIP_R - 1.0, 0.0, TAU, 20, Color(col, 0.55), 2.0, true)


func _update_chips() -> void:
	if match_node == null:
		return
	var alive := 0
	var total := 0
	for d in match_node.dolls():
		var dd := d as Doll
		total += 1
		if dd.alive:
			alive += 1
		var c := _ensure_chip(dd)
		var hold := dd == match_node.holder
		(c["name"] as Label).text = name_of(dd)
		var st := c["status"] as Label
		if hold:
			st.text = tr("БОМБА")
		elif not dd.alive:
			st.text = tr("ВЫБЫЛ")
		elif dd.player_index == 0 and not dd.external_input:
			st.text = tr("ИГРОК 1")
		elif not dd.external_input:
			st.text = tr("ИГРОК 2")
		else:
			st.text = tr("БОТ")
		var hot := hold and _pulse > 0.35
		if hot != bool(c["hot"]):
			_style_chip(dd.player_index, hot)
		(c["panel"] as Control).modulate.a = 1.0 if dd.alive or match_node.play_state == "countdown" else 0.45
		(c["pips"] as Control).queue_redraw()
	alive_label.text = tr("ЖИВЫХ: %d ИЗ %d") % [alive, total]


# --- кадр ---

func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.02)
	_clock += real
	_pulse = maxf(_pulse - real * 6.0, 0.0)
	if hint.visible and _clock > HINT_S:
		hint.modulate.a = maxf(hint.modulate.a - real * 1.5, 0.0)
		hint.visible = hint.modulate.a > 0.0
	_update_chips()
	marks.queue_redraw()


## Имена над куклами, кольцо и «БОМБА» над держателем.
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
		if not is_instance_valid(d) or not d.is_inside_tree() or not d.alive:
			continue
		var head: Node3D = d.parts.get("Head", d.torso()) as Node3D
		if head == null:
			continue
		# над куклой, даже если она вниз головой: выше головы и торса
		var top := Vector3(head.global_position.x, maxf(head.global_position.y, d.torso().global_position.y + 0.35) + NAME_LIFT, 0.0)
		if cam.is_position_behind(top):
			continue
		var sp: Vector2 = to_canvas * cam.unproject_position(top)
		if sp.x < 0.0 or sp.y < 0.0 or sp.x > vp.x or sp.y > vp.y:
			continue
		var col := BombMatch.colour_of(d.player_index).lightened(0.3)
		var txt := name_of(d)
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
		marks.draw_string_outline(font, sp + Vector2(-tw.x * 0.5, 0.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color(0, 0, 0, 0.9))
		marks.draw_string(font, sp + Vector2(-tw.x * 0.5, 0.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)
		if d != match_node.holder:
			continue
		var bp3: Vector3 = match_node.carry.global_position if match_node.carry != null and match_node.carry.visible else d.torso().global_position
		var bc: Vector2 = to_canvas * cam.unproject_position(bp3)
		var red := BombMatch.COLOUR_BOMB
		var r := RING_R * (1.0 + 0.18 * _pulse)
		marks.draw_arc(bc, r, 0.0, TAU, 40, Color(red, 0.35 + 0.55 * _pulse), 3.0 + 3.0 * _pulse, true)
		var bt := tr("БОМБА")
		var fs := 26 + int(6.0 * _pulse)
		var bw := font.get_string_size(bt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var bp := sp + Vector2(-bw.x * 0.5, -26.0)
		marks.draw_string_outline(font, bp, bt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, Color(0, 0, 0, 0.9))
		marks.draw_string(font, bp, bt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, red.lerp(Color.WHITE, 0.5 * _pulse))
