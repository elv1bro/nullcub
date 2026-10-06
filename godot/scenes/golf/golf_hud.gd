## HUD «Гольфа: кукла — мяч» (docs/plan-demo/GOLF.md). Дерево строит сам, шрифты — по скину HUD (HudSkin):
##   • сверху по центру — «ЛУНКА 1/3 · ПАР 3» и имя лунки; под ним на несколько секунд — совет лунки;
##   • по бокам — плашки игроков: имя цветом куклы, удары на этой лунке крупно, сумма к пару («+1», «−1», «0») и что делает
##     (ПРИЦЕЛ / ЛЕТИТ / В ЛУНКЕ);
##   • над куклами — имя и удары; у человека в прицеле — стрелка из ЦМ (длина — сила) и пунктир начала полёта (GolfShot.point_at — та
##     же формула, что у бота), во время замаха — полоска силы рядом с куклой; у бота, пока он думает, — его стрелка бледнее;
##     в полёте у человека, пока поправка не потрачена, — значок «»» (Shift / Ctrl);
##   • диктор (Announcer) — отсчёт, «ЛУНКА N», «В ЛУНКЕ!» с итогом к пару (БЁРДИ, ПАР, БОГИ…), «ЯМА +1», «ДЕТАЛЬ +1»;
##   • снизу — подсказка клавиш (пока идёт лунка), тосты U / K / M / N / H;
##   • между лунками и в конце — карточка: удары по лункам, пар, сумма; в конце — кто победил и «R — заново».
## bind(match, playground) — подписка на GolfMatch по именам сигналов.
class_name GolfHud
extends CanvasLayer

const PLATE_W := 190.0
const PLATE_H := 92.0
const TOP := 12.0
const TITLE_W := 420.0
const TIP_S := 9.0
const NAME_LIFT := 0.55
const ARROW_MIN := 40.0          # px стрелки при силе 0
const ARROW_MAX := 190.0         # px при силе 1
const DOTS_T := 0.9              # с пунктира прицела
const BAR_W := 12.0
const BAR_H := 90.0

var match_node: GolfMatch
var playground: Node
var root: Control
var announcer: Announcer
var title: Label
var sub: Label
var tip: Label
var marks: Control
var hint: Label
var toast_label: Label
var card_panel: PanelContainer
var card_title: Label
var card_sub: Label
var card_table: GridContainer
var card_again: Label
var plates: Dictionary = {}      # player_index → {panel, name, strokes, total, status}
var _title_plate: PanelContainer
var _tip_left := 0.0
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
	marks = Control.new()
	marks.name = "Marks"
	marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marks.draw.connect(_draw_marks)
	root.add_child(marks)
	_build_top()
	_build_bottom()
	_build_card()
	announcer = Announcer.new()
	announcer.name = "Announcer"
	announcer.set_anchors_preset(Control.PRESET_CENTER)
	announcer.offset_top = -150.0
	announcer.offset_bottom = -150.0
	announcer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := VBoxContainer.new()
	st.name = "Stack"
	st.set_anchors_preset(Control.PRESET_CENTER)
	st.alignment = BoxContainer.ALIGNMENT_CENTER
	st.add_theme_constant_override("separation", -10)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	announcer.add_child(st)
	root.add_child(announcer)
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


func _build_top() -> void:
	_title_plate = PanelContainer.new()
	_title_plate.name = "Title"
	_title_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_plate.anchor_left = 0.5
	_title_plate.anchor_right = 0.5
	_title_plate.offset_left = -TITLE_W * 0.5
	_title_plate.offset_right = TITLE_W * 0.5
	_title_plate.offset_top = TOP
	_title_plate.offset_bottom = TOP + PLATE_H
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", -4)
	_title_plate.add_child(v)
	title = _label("Hole", 34, Color.WHITE)
	sub = _label("Name", 20, GolfCup.COLOUR.lightened(0.3))
	v.add_child(title)
	v.add_child(sub)
	root.add_child(_title_plate)
	tip = _label("Tip", 20, Color(1, 1, 1, 0.85))
	tip.anchor_left = 0.5
	tip.anchor_right = 0.5
	tip.offset_left = -560.0
	tip.offset_right = 560.0
	tip.offset_top = TOP + PLATE_H + 6.0
	tip.offset_bottom = TOP + PLATE_H + 36.0
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(tip)


func _make_plate(pi: int) -> void:
	var plate := PanelContainer.new()
	plate.name = "Player%d" % pi
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.anchor_left = 0.5
	plate.anchor_right = 0.5
	var slot := pi / 2
	var left := pi % 2 == 0
	var x0 := -TITLE_W * 0.5 - 12.0 - PLATE_W - slot * (PLATE_W + 10.0) if left else TITLE_W * 0.5 + 12.0 + slot * (PLATE_W + 10.0)
	plate.offset_left = x0
	plate.offset_right = x0 + PLATE_W
	plate.offset_top = TOP
	plate.offset_bottom = TOP + PLATE_H
	plate.pivot_offset = Vector2(PLATE_W, PLATE_H) * 0.5
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", -6)
	plate.add_child(v)
	var c := GolfMatch.colour_of(pi).lightened(0.35)
	var nl := _label("Name", 18, c)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	var sl := _label("Strokes", 36, Color.WHITE)
	var tl := _label("Total", 20, Color(1, 1, 1, 0.8))
	row.add_child(sl)
	row.add_child(tl)
	var stl := _label("Status", 15, Color(1, 1, 1, 0.7))
	v.add_child(nl)
	v.add_child(row)
	v.add_child(stl)
	root.add_child(plate)
	plates[pi] = {"panel": plate, "name": nl, "strokes": sl, "total": tl, "status": stl}


func _build_bottom() -> void:
	hint = _label("Hint", 20, Color(1, 1, 1, 0.8))
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -760.0
	hint.offset_right = 760.0
	hint.offset_top = -84.0
	hint.offset_bottom = -20.0
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # длинный язык — в две строки, а не за экран
	hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	root.add_child(hint)
	toast_label = _label("Toast", 26, Color.WHITE)
	toast_label.anchor_left = 0.5
	toast_label.anchor_right = 0.5
	toast_label.anchor_top = 1.0
	toast_label.anchor_bottom = 1.0
	toast_label.offset_left = -300.0
	toast_label.offset_right = 300.0
	toast_label.offset_top = -118.0
	toast_label.offset_bottom = -78.0
	toast_label.visible = false
	root.add_child(toast_label)


func _build_card() -> void:
	card_panel = PanelContainer.new()
	card_panel.name = "Card"
	card_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_panel.set_anchors_preset(Control.PRESET_CENTER)
	card_panel.offset_left = -420.0
	card_panel.offset_right = 420.0
	card_panel.offset_top = -170.0
	card_panel.offset_bottom = 230.0
	card_panel.visible = false
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 10)
	card_panel.add_child(v)
	card_title = _label("Title", 48, Color.WHITE)
	card_sub = _label("Sub", 24, Color(1, 1, 1, 0.85))
	card_table = GridContainer.new()
	card_table.name = "Table"
	card_table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_table.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card_table.add_theme_constant_override("h_separation", 34)
	card_table.add_theme_constant_override("v_separation", 4)
	card_again = _label("Again", 22, Color(1, 1, 1, 0.7))
	card_again.text = tr("R — заново · Esc — пауза и выход в гараж")
	for l in [card_title, card_sub, card_table, card_again]:
		v.add_child(l)
	root.add_child(card_panel)


func _apply_skin() -> void:
	for l in root.find_children("*", "Label", true, false):
		if (l as Node).has_meta("px"):
			HudSkin.style_label(l, "display", int(l.get_meta("px")), l.get_meta("colour"))
			(l as Label).add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			(l as Label).add_theme_constant_override("outline_size", 6)
	var tb := StyleBoxFlat.new()
	tb.bg_color = Color(0.03, 0.035, 0.05, 0.86)
	tb.border_color = GolfCup.COLOUR
	tb.border_width_bottom = 3
	tb.set_corner_radius_all(4)
	_title_plate.add_theme_stylebox_override("panel", tb)
	for pi in plates:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.035, 0.05, 0.86)
		sb.border_color = GolfMatch.colour_of(pi).lightened(0.25)
		sb.border_width_bottom = 6
		sb.set_corner_radius_all(4)
		(plates[pi]["panel"] as PanelContainer).add_theme_stylebox_override("panel", sb)
	var cb := StyleBoxFlat.new()
	cb.bg_color = Color(0.03, 0.035, 0.05, 0.93)
	cb.set_corner_radius_all(8)
	cb.content_margin_left = 30.0
	cb.content_margin_right = 30.0
	cb.content_margin_top = 18.0
	cb.content_margin_bottom = 18.0
	card_panel.add_theme_stylebox_override("panel", cb)


func bind(m: GolfMatch, pg: Node = null) -> void:
	match_node = m
	playground = pg
	var pairs := [["announce", _on_announce], ["hole_started", _on_hole_started], ["hole_over", _on_hole_over], ["holed", _on_holed],
		["penalized", _on_penalized], ["match_over", _on_over], ["phase_changed", _on_phase], ["nudged", _on_nudged]]
	for p in pairs:
		if m.has_signal(p[0]) and not m.is_connected(p[0], p[1]):
			m.connect(p[0], p[1])
	refresh_hint()


## Имя игрока: человек P1 — ТЫ, человек P2 — ИГРОК 2, бот — БОТ N.
static func name_of(d: Object) -> String:
	if d == null or not is_instance_valid(d):
		return ""
	var dd := d as Doll
	if not dd.external_input:
		return TranslationServer.translate("ТЫ") if dd.player_index == 0 else TranslationServer.translate("ИГРОК %d") % (dd.player_index + 1)
	return TranslationServer.translate("БОТ %d") % (dd.player_index + 1)


## Счёт к пару: «0», «+2», «−1».
static func to_par_text(n: int) -> String:
	if n == 0:
		return "0"
	return ("+%d" % n) if n > 0 else ("−%d" % -n)


## Итог лунки словами гольфа.
static func score_word(strokes: int, par_: int) -> String:
	if strokes == 1:
		return TranslationServer.translate("С ОДНОГО УДАРА!")
	match strokes - par_:
		-3:
			return TranslationServer.translate("АЛЬБАТРОС")
		-2:
			return TranslationServer.translate("ИГЛ")
		-1:
			return TranslationServer.translate("БЁРДИ")
		0:
			return TranslationServer.translate("ПАР")
		1:
			return TranslationServer.translate("БОГИ")
		2:
			return TranslationServer.translate("ДАБЛ-БОГИ")
	return to_par_text(strokes - par_)


func refresh_hint() -> void:
	var p2_human := playground != null and not bool(playground.get("p2_bot"))
	if p2_human:
		hint.text = tr("P1: мышь — прицел, зажми ЛКМ — сила, отпусти — удар, Shift в полёте — рывок · P2: ← → прицел, Enter — сила, Ctrl — рывок · R — заново")
	else:
		hint.text = tr("Мышь — прицел · зажми ЛКМ — сила, отпусти — удар · Shift в полёте — один рывок (WASD) · U — второй игрок · K — боты · R — заново")


func toast(text: String) -> void:
	toast_label.text = text
	toast_label.visible = true
	toast_label.modulate.a = 1.0
	_toast_left = 1.4


# --- сигналы ---

func _on_announce(text: String, color: Color, kind: String) -> void:
	if kind in ["countdown", "fight"]:
		announcer.announce(text, color, kind)


func _on_hole_started(hole_i: int, par_: int) -> void:
	card_panel.visible = false
	title.text = tr("ЛУНКА %d/%d · ПАР %d") % [hole_i + 1, GolfCourse.hole_count(), par_]
	if match_node != null and match_node.course != null:
		sub.text = tr(match_node.course.hole_name())
		tip.text = tr(match_node.course.tip())
	tip.visible = true
	tip.modulate.a = 1.0
	_tip_left = TIP_S
	hint.visible = true


func _on_holed(d: Doll, strokes: int, par_: int) -> void:
	if not is_instance_valid(d):
		return
	var c := GolfMatch.colour_of(d.player_index).lightened(0.3)
	var who := name_of(d)
	announcer.announce(tr("%s В ЛУНКЕ · %s") % [who, score_word(strokes, par_)], c, "event")
	_bump(d.player_index)


func _on_penalized(d: Doll, reason: String, _strokes: int) -> void:
	if not is_instance_valid(d):
		return
	var c := Color(1.0, 0.45, 0.3)
	var txt := tr("ЯМА · +1") if reason == "hazard" else (tr("ДЕТАЛЬ ПОТЕРЯНА · +1") if reason == "part" else tr("ВЫБЫЛ · +1"))
	if d.external_input:
		txt = "%s: %s" % [name_of(d), txt]
	announcer.announce(txt, c, "event")
	_bump(d.player_index)


func _on_nudged(d: Doll) -> void:
	if is_instance_valid(d) and not d.external_input:
		_bump(d.player_index)


func _bump(pi: int) -> void:
	if not plates.has(pi):
		return
	var p := plates[pi]["panel"] as Control
	var tw := p.create_tween().set_ignore_time_scale(true)
	tw.tween_property(p, "scale", Vector2(1.15, 1.15), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "scale", Vector2.ONE, 0.25)


func _on_hole_over(hole_i: int) -> void:
	hint.visible = false
	_fill_card(tr("ЛУНКА %d СЫГРАНА") % (hole_i + 1), "", false)


func _on_phase(p: int) -> void:
	if p == Match.Phase.COUNTDOWN:
		card_panel.visible = false


func _on_over(_winner: Doll, results: Dictionary) -> void:
	hint.visible = false
	var w: Doll = results.get("winner") as Doll
	var head := ""
	if w == null or not is_instance_valid(w):
		head = tr("НИЧЬЯ")
	elif not w.external_input and w.player_index == 0:
		head = tr("ПОБЕДА!")
	else:
		head = tr("ПОБЕДИЛ: %s") % name_of(w)
	var line := ""
	if w != null and is_instance_valid(w):
		var t := int((results.get("totals", {}) as Dictionary).get(w.player_index, 0))
		line = tr("ударов: %d · к пару: %s") % [t, to_par_text(t - int(results.get("par_total", 0)))]
	_fill_card(head, line, true)


## Карточка: строка «ЛУНКА» с номерами, «ПАР», затем по игроку; в конце — сумма и к пару.
func _fill_card(head: String, line: String, final: bool) -> void:
	if match_node == null:
		return
	card_title.text = head
	card_sub.text = line
	card_sub.visible = line != ""
	card_again.visible = final
	for c in card_table.get_children():
		card_table.remove_child(c)
		c.queue_free()
	var n := match_node.holes_n
	card_table.columns = n + 3
	var white := Color(1, 1, 1, 0.75)
	_cell(tr("ЛУНКА"), white, true)
	for i in n:
		_cell(str(match_node.start_hole + i + 1), white, false)
	_cell(tr("ВСЕГО"), white, false)
	_cell(tr("К ПАРУ"), white, false)
	_cell(tr("ПАР"), white, true)
	var pt := 0
	for i in n:
		var pr := int(Tuning.GOLF_PARS[clampi(match_node.start_hole + i, 0, Tuning.GOLF_PARS.size() - 1)])
		pt += pr
		_cell(str(pr), white, false)
	_cell(str(pt), white, false)
	_cell("", white, false)
	var keys := match_node.players.keys()
	keys.sort()
	for pi in keys:
		var d := match_node.doll_of_index(pi)
		var card: Array = match_node.players[pi]["card"]
		_cell(name_of(d), GolfMatch.colour_of(pi).lightened(0.4), true)
		var tot := 0
		var par_sum := 0
		for i in n:
			if i < card.size():
				var s := int(card[i])
				var pr := int(Tuning.GOLF_PARS[clampi(match_node.start_hole + i, 0, Tuning.GOLF_PARS.size() - 1)])
				tot += s
				par_sum += pr
				_cell(str(s), Color(0.55, 1.0, 0.6) if s < pr else (Color.WHITE if s == pr else Color(1.0, 0.7, 0.55)), false)
			else:
				_cell("·", white, false)
		_cell(str(tot), Color.WHITE, false)
		_cell(to_par_text(tot - par_sum), Color.WHITE, false)
	_apply_skin()
	card_panel.visible = true
	card_panel.modulate.a = 0.0
	var tw := card_panel.create_tween().set_ignore_time_scale(true)
	tw.tween_interval(0.5 if final else 0.9)
	tw.tween_property(card_panel, "modulate:a", 1.0, 0.3)


func _cell(text: String, c: Color, left: bool) -> void:
	var l := _label("Cell", 24, c)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_CENTER
	card_table.add_child(l)


# --- кадр ---

func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.02)
	if _tip_left > 0.0:
		_tip_left -= real
		if _tip_left < 1.0:
			tip.modulate.a = maxf(_tip_left, 0.0)
		tip.visible = _tip_left > 0.0
	if _toast_left > 0.0:
		_toast_left -= real
		toast_label.modulate.a = clampf(_toast_left / 0.3, 0.0, 1.0)
		toast_label.visible = _toast_left > 0.0
	if match_node != null:
		_update_plates()
	marks.queue_redraw()


func _update_plates() -> void:
	for pi in match_node.players:
		if not plates.has(pi):
			_make_plate(pi)
			_apply_skin()
		var pl: Dictionary = plates[pi]
		var d := match_node.doll_of_index(pi)
		(pl["name"] as Label).text = name_of(d)
		var p: Dictionary = match_node.players[pi]
		(pl["strokes"] as Label).text = str(int(p["strokes"]))
		var done: Array = p["card"]
		var played := 0
		var par_sum := 0
		for i in done.size():
			played += int(done[i])
			par_sum += int(Tuning.GOLF_PARS[clampi(match_node.start_hole + i, 0, Tuning.GOLF_PARS.size() - 1)])
		(pl["total"] as Label).text = to_par_text(played - par_sum) if not done.is_empty() else ""
		var st := ""
		match int(p["state"]):
			GolfMatch.S.AIM:
				st = tr("ПРИЦЕЛ")
			GolfMatch.S.FLIGHT:
				st = tr("ЛЕТИТ")
			GolfMatch.S.HOLED:
				st = tr("ЗАКРЫЛ ЛУНКУ") if bool(p["picked"]) else tr("В ЛУНКЕ")
		if match_node.play_state != "play":
			st = ""
		(pl["status"] as Label).text = st


## Имена над куклами, стрелки прицела с пунктиром, полоска силы, значок поправки.
func _draw_marks() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or match_node == null or card_panel.visible:
		return
	var font := HudSkin.font("display")
	if font == null:
		font = ThemeDB.fallback_font
	var to_canvas := marks.get_global_transform_with_canvas().affine_inverse()
	var playing := match_node.play_state == "play"
	for pi in match_node.players:
		var p: Dictionary = match_node.players[pi]
		var d := match_node.doll_of_index(pi)
		if d == null or not d.visible or not d.is_inside_tree() or int(p["state"]) == GolfMatch.S.HOLED:
			continue
		var com := d.centre_of_mass(true)
		if cam.is_position_behind(com):
			continue
		var c := GolfMatch.colour_of(pi).lightened(0.3)
		var sc: Vector2 = to_canvas * cam.unproject_position(com)
		var human := not d.external_input
		# имя и удары
		var head: Node3D = d.parts.get("Head", d.torso()) as Node3D
		var top := com + Vector3(0.0, 1.2, 0.0)
		if head != null:
			top = Vector3(com.x, maxf(com.y, head.global_position.y) + NAME_LIFT, com.z)
		var tp: Vector2 = to_canvas * cam.unproject_position(top)
		var txt := "%s · %d" % [name_of(d), int(p["strokes"])]
		var fs := 22 if human else 19
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		marks.draw_string_outline(font, tp + Vector2(-tw.x * 0.5, 0.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.9))
		marks.draw_string(font, tp + Vector2(-tw.x * 0.5, 0.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE if human else c)
		if not playing:
			continue
		var st := int(p["state"])
		if st == GolfMatch.S.AIM and (human or float(p["think"]) < 0.6):
			var aim: Vector2 = p["aim"]
			var pw := match_node.power_of(pi) if human else 0.55
			_draw_aim(sc, com, aim, pw, c, human, bool(p["charging"]), cam, to_canvas)
		elif st == GolfMatch.S.FLIGHT and human and not bool(p["nudge_used"]):
			var ip := tp + Vector2(tw.x * 0.5 + 16.0, -8.0)
			marks.draw_string_outline(font, ip, "»", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 6, Color(0, 0, 0, 0.9))
			marks.draw_string(font, ip, "»", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1.0, 0.85, 0.3))


## Стрелка прицела из ЦМ (длина — сила), пунктир начала полёта (та же формула, что у бота), полоска силы при замахе.
func _draw_aim(sc: Vector2, com: Vector3, aim: Vector2, pw: float, c: Color, human: bool, charging: bool, cam: Camera3D, to_canvas: Transform2D) -> void:
	var a := Color(c.r, c.g, c.b, 0.95 if human else 0.45)
	# направление на экране (камера смотрит вдоль −Z без наклона: экранный y вниз)
	var sd := Vector2(aim.x, -aim.y).normalized()
	var length := lerpf(ARROW_MIN, ARROW_MAX, pw if charging or not human else 0.35)
	var tip_p := sc + sd * length
	marks.draw_line(sc, tip_p, Color(0, 0, 0, 0.6), 8.0, true)
	marks.draw_line(sc, tip_p, a, 4.5, true)
	var side := Vector2(-sd.y, sd.x)
	var head := PackedVector2Array([tip_p + sd * 16.0, tip_p - sd * 4.0 + side * 11.0, tip_p - sd * 4.0 - side * 11.0])
	marks.draw_colored_polygon(head, a)
	if not human:
		return
	# пунктир: начало полёта при текущей силе (или средней, пока не замахнулся)
	var g := match_node.course.gravity_at(Vector2(com.x, com.y)) if match_node.course != null else Vector2(0.0, -4.4)
	var v0 := aim.normalized() * GolfShot.speed_for(pw if charging else 0.5)
	var p0 := Vector2(com.x, com.y)
	for i in 9:
		var t := DOTS_T * float(i + 1) / 9.0
		var q := GolfShot.point_at(p0, v0, g, Tuning.GOLF_DAMP, t)
		var qs: Vector2 = to_canvas * cam.unproject_position(Vector3(q.x, q.y, 0.0))
		var rr := 5.0 - float(i) * 0.3
		marks.draw_circle(qs, rr + 1.5, Color(0, 0, 0, 0.5))
		marks.draw_circle(qs, rr, Color(1, 1, 1, 0.9 - float(i) * 0.06))
	if charging:
		var bx := sc + Vector2(-60.0, -BAR_H * 0.5)
		var r := Rect2(bx, Vector2(BAR_W, BAR_H))
		marks.draw_rect(r.grow(3.0), Color(0.02, 0.02, 0.03, 0.85))
		var fill := BAR_H * clampf(pw, 0.0, 1.0)
		var fc := Color(0.4, 1.0, 0.5).lerp(Color(1.0, 0.35, 0.2), pw)
		marks.draw_rect(Rect2(bx + Vector2(0.0, BAR_H - fill), Vector2(BAR_W, fill)), fc)
