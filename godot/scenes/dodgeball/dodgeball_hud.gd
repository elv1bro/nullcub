## HUD «Вышибал» (docs/plan-demo/DODGEBALL.md). Как у «Перетягивания каната»: дерево строит сам, шрифты — по скину HUD (HudSkin),
## смена скина перекрашивает на лету:
##   • сверху по центру — «ВЫШИБАЛЫ · ДО 2 ПОБЕД», счёт раундов «1 : 0», «РАУНД 2 · 0:54» (в «до первого» — «ДО ПЕРВОГО · 0:21»);
##     по бокам счёта — кружки команд: полный — на поле, пустой — выбит (синие слева, красные справа);
##   • над куклами на поле — имя цветом команды (ТЫ — человек), полоска запаса; живой мяч — кольцо цветом бросившей команды;
##   • диктор (Announcer) — отсчёт, ВЫШИБАЙ!, «РАУНД: СИНИЕ»; тосты — «ВЫБИТ P4», «ПОЙМАЛ!», «P3 СНОВА В ИГРЕ», клавиши U / K / M / N / H;
##   • снизу — подсказка клавиш (гаснет через HINT_S);
##   • конец матча — табличка: «ПОБЕДА СИНИХ», счёт и время, таблица бойцов (попаданий, поймал, выбит), медали Match, «R — заново».
## bind(match, playground) — подписка на DodgeballMatch по именам сигналов.
class_name DodgeballHud
extends CanvasLayer

const TOP := 12.0
const HINT_S := 14.0
const NAME_LIFT := 0.5
const BAR_W := 64.0
const BAR_H := 7.0
const DOT_R := 13.0
const DOT_GAP := 36.0

var match_node: DodgeballMatch
var playground: Node
var root: Control
var announcer: Announcer
var caption: Label
var score_label: Label
var timer_label: Label
var teams_box: Control
var marks: Control
var hint: Label
var toast_label: Label
var end_panel: PanelContainer
var end_title: Label
var end_sub: Label
var end_table: GridContainer
var end_medals: Label
## Для проб: тосты по порядку (текст) и сколько кружков «на поле» нарисовано в последнем кадре.
var toasts: Array = []
var dots_on := 0
var _clock := 0.0
var _toast_at := -10.0
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
	score_label = _label("Score", 44, Color.WHITE)
	_centre(score_label, -110.0, 110.0, TOP + 34.0, TOP + 88.0)
	root.add_child(score_label)
	timer_label = _label("Timer", 24, Color(1, 1, 1, 0.8))
	_centre(timer_label, -260.0, 260.0, TOP + 88.0, TOP + 116.0)
	root.add_child(timer_label)
	teams_box = Control.new()
	teams_box.name = "Teams"
	teams_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_centre(teams_box, -330.0, 330.0, TOP + 40.0, TOP + 84.0)
	teams_box.draw.connect(_draw_teams)
	root.add_child(teams_box)
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
	toast_label = _label("Toast", 30, Color.WHITE)
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.offset_left = -360.0
	toast_label.offset_right = 360.0
	toast_label.offset_top = TOP + 124.0
	toast_label.offset_bottom = TOP + 166.0
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
	end_panel.offset_top = -260.0
	end_panel.offset_bottom = 260.0
	end_panel.visible = false
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 8)
	end_panel.add_child(v)
	end_title = _label("Title", 52, Color.WHITE)
	end_sub = _label("Sub", 26, Color(1, 1, 1, 0.8))
	end_table = GridContainer.new()
	end_table.name = "Table"
	end_table.columns = 4
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
	if end_panel != null:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.035, 0.05, 0.92)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 30.0
		sb.content_margin_right = 30.0
		sb.content_margin_top = 18.0
		sb.content_margin_bottom = 18.0
		end_panel.add_theme_stylebox_override("panel", sb)


func bind(m: DodgeballMatch, pg: Node = null) -> void:
	match_node = m
	playground = pg
	var pairs := [["announce", _on_announce], ["phase_changed", _on_phase], ["match_over", _on_over], ["score_changed", _on_score],
		["knocked", _on_knocked], ["caught", _on_caught]]
	for p in pairs:
		if m.has_signal(p[0]) and not m.is_connected(p[0], p[1]):
			m.connect(p[0], p[1])
	caption.text = tr("ВЫШИБАЛЫ · ДО %d ПОБЕД") % m.rounds_to_win
	_on_score(m.score)
	refresh_hint()


func refresh_hint() -> void:
	if hint == null:
		return
	var p2h := false
	if playground != null and playground.get("p2_human") != null:
		p2h = bool(playground.get("p2_human"))
	var who := tr("P2: стрелки, / — схватить мяч / бросить (U — бот)") if p2h else tr("U — P2 на стрелках")
	hint.text = "%s\n%s    %s" % [tr("P1: ЛКМ — рука к курсору, E — схватить мяч, E с зажатой ЛКМ — бросок; рука на пути мяча — поймать"),
		who, tr("K: уровень ботов    R: заново    Esc: пауза")]
	hint.visible = true
	hint.modulate.a = 1.0
	_clock = 0.0


func toast(text: String, colour: Color = Color.WHITE) -> void:
	toasts.append(text)
	# два события в одно мгновение (ПОЙМАЛ! и ВЫБИТ бросившего) — в одну строку, второе не стирает первое
	if toast_label.visible and _clock - _toast_at < 0.6 and toast_label.text != "":
		text = "%s  ·  %s" % [toast_label.text, text]
	_toast_at = _clock
	toast_label.text = text
	toast_label.set_meta("colour", colour)
	HudSkin.style_label(toast_label, "display", int(toast_label.get_meta("px")), colour)
	toast_label.visible = true
	toast_label.modulate.a = 1.0
	if _toast_tw != null and _toast_tw.is_valid():
		_toast_tw.kill()
	_toast_tw = toast_label.create_tween().set_ignore_time_scale(true)
	_toast_tw.tween_interval(1.2)
	_toast_tw.tween_property(toast_label, "modulate:a", 0.0, 0.3)
	_toast_tw.tween_callback(func() -> void: toast_label.visible = false)


## Имя куклы для HUD: человек P1 — ТЫ, остальные — P1…P6.
func name_of(d: Doll) -> String:
	if d != null and is_instance_valid(d) and d.player_index == 0 and not d.external_input:
		return tr("ТЫ")
	return DodgeballMatch.doll_name(d)


# --- сигналы ---

## Отсчёт, «ВЫШИБАЙ!», раунд — диктором; выбит / поймал / снова в игре — тостом (сигналы knocked / caught дают тот же текст,
## но тост берёт текст диктора: он уже переведён и с цветом команды).
func _on_announce(text: String, color: Color, kind: String) -> void:
	if kind == "ko":
		toast(text, color)
	elif kind in ["countdown", "fight", "point"]:
		announcer.announce(text, color, "score" if kind == "point" else kind)


func _on_knocked(_d: Doll, _by: Node, _how: String) -> void:
	teams_box.queue_redraw()


func _on_caught(_catcher: Doll, _thrower: Node, _back: Doll) -> void:
	teams_box.queue_redraw()


func _on_phase(p: int) -> void:
	if p == Match.Phase.COUNTDOWN:
		end_panel.visible = false


func _on_score(s: Array) -> void:
	score_label.text = "%d : %d" % [int(s[0]), int(s[1])]


func _on_over(_winner: Doll, results: Dictionary) -> void:
	var wt := int(results.get("winner_team", -1))
	if wt < 0:
		end_title.text = tr("НИЧЬЯ")
		end_title.set_meta("colour", Color.WHITE)
	else:
		end_title.text = tr("ПОБЕДА СИНИХ") if wt == 0 else tr("ПОБЕДА КРАСНЫХ")
		end_title.set_meta("colour", DodgeballMatch.colour_of(wt).lightened(0.35))
	var s: Array = results.get("score", [0, 0])
	var secs := int(match_node.fight_time) if match_node != null else 0
	end_sub.text = tr("счёт %d : %d · %d:%02d") % [int(s[0]), int(s[1]), secs / 60, secs % 60]
	for c in end_table.get_children():
		end_table.remove_child(c)
		c.queue_free()
	var white := Color(1, 1, 1, 0.75)
	for h in [tr("БОЕЦ"), tr("ПОПАДАНИЙ"), tr("ПОЙМАЛ"), tr("ВЫБИТ")]:
		_cell(h, white, end_table.get_child_count() == 0)
	var tally: Dictionary = results.get("tally", {})
	for d in results.get("places", []):
		var dd := d as Doll
		if dd == null or not is_instance_valid(dd):
			continue
		var t: Dictionary = tally.get(dd.player_index, {})
		_cell(name_of(dd), DodgeballMatch.colour_of(DodgeballMatch.team_of(dd)).lightened(0.4), true)
		_cell(str(int(t.get("hits", 0))), Color.WHITE, false)
		_cell(str(int(t.get("catches", 0))), Color.WHITE, false)
		_cell(str(int(t.get("outs", 0))), Color.WHITE, false)
	var medals: Dictionary = results.get("medals", {})
	var parts: Array = []
	for k in medals.keys():
		var md: Object = medals[k]
		if is_instance_valid(md) and md is Doll:
			parts.append("%s — %s" % [ResultsPanel.medal_title(String(k)), name_of(md as Doll)])
	end_medals.text = (tr("МЕДАЛИ: ") + " · ".join(parts)) if not parts.is_empty() else ""
	end_medals.visible = not parts.is_empty()
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

func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.02)
	_clock += real
	if hint.visible and _clock > HINT_S:
		hint.modulate.a = maxf(hint.modulate.a - real * 1.5, 0.0)
		hint.visible = hint.modulate.a > 0.0
	if match_node != null:
		if match_node.play_state in ["play", "countdown", "round_over"]:
			var left := match_node.time_left_s()
			var head := tr("ДО ПЕРВОГО") if match_node.sudden else tr("РАУНД %d") % match_node.round_n
			timer_label.text = "%s · %d:%02d" % [head, int(left) / 60, int(left) % 60]
		else:
			timer_label.text = ""
	teams_box.queue_redraw()
	marks.queue_redraw()


## Кружки команд по бокам счёта: синие слева (P1 ближе к счёту), красные справа; полный — на поле, пустое кольцо — выбит.
func _draw_teams() -> void:
	dots_on = 0
	if match_node == null:
		return
	var w := teams_box.size.x
	var y := teams_box.size.y * 0.5
	for team in 2:
		var col := DodgeballMatch.colour_of(team).lightened(0.25)
		var list := match_node.team_dolls(team)
		list.sort_custom(func(a: Doll, b: Doll) -> bool: return a.player_index < b.player_index)
		for i in list.size():
			var d := list[i] as Doll
			var x := (w * 0.5 - 140.0 - i * DOT_GAP) if team == 0 else (w * 0.5 + 140.0 + i * DOT_GAP)
			var c := Vector2(x, y)
			teams_box.draw_circle(c, DOT_R + 2.0, Color(0, 0, 0, 0.75))
			if match_node.in_play(d) or match_node.play_state in ["countdown", "idle"]:
				teams_box.draw_circle(c, DOT_R, col)
				dots_on += 1
			else:
				teams_box.draw_arc(c, DOT_R - 2.0, 0.0, TAU, 24, Color(col, 0.6), 3.0, true)
				teams_box.draw_line(c + Vector2(-6, -6), c + Vector2(6, 6), Color(1, 1, 1, 0.55), 2.0, true)
				teams_box.draw_line(c + Vector2(-6, 6), c + Vector2(6, -6), Color(1, 1, 1, 0.55), 2.0, true)


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
		if not is_instance_valid(d) or not d.is_inside_tree() or not match_node.in_play(d):
			continue
		var col := DodgeballMatch.colour_of(DodgeballMatch.team_of(d)).lightened(0.3)
		var head: Node3D = d.parts.get("Head", d.torso()) as Node3D
		if head == null:
			continue
		var top := Vector3(head.global_position.x, maxf(head.global_position.y, d.torso().global_position.y + 0.35) + NAME_LIFT, 0.0)
		if cam.is_position_behind(top):
			continue
		var sp: Vector2 = to_canvas * cam.unproject_position(top)
		if sp.x < -80.0 or sp.y < -60.0 or sp.x > vp.x + 80.0 or sp.y > vp.y + 40.0:
			continue
		_text_c(font, sp + Vector2(0.0, -6.0), name_of(d), 20, col)
		var frac := clampf(d.hp / maxf(d.max_hp, 1.0), 0.0, 1.0)
		var r := Rect2(sp + Vector2(-BAR_W * 0.5, 0.0), Vector2(BAR_W, BAR_H))
		marks.draw_rect(r.grow(1.0), Color(0, 0, 0, 0.7))
		marks.draw_rect(Rect2(r.position, Vector2(BAR_W * frac, BAR_H)), col.lerp(Color(1.0, 0.3, 0.2), 1.0 - frac))
	# живой мяч — кольцо цветом бросившей команды
	for b in match_node.balls():
		var sb := b as SportBall
		var st := match_node.ball_info(sb)
		if String(st.get("state", "")) != "live":
			continue
		var bp := sb.global_position
		if cam.is_position_behind(bp):
			continue
		var c: Vector2 = to_canvas * cam.unproject_position(bp)
		var edge: Vector2 = to_canvas * cam.unproject_position(bp + Vector3(Tuning.SPORT_BALL_RADIUS, 0.0, 0.0))
		var rr := maxf(c.distance_to(edge) + 4.0, 8.0)
		var tc := DodgeballMatch.colour_of(int(st.get("team", 0))).lightened(0.35)
		marks.draw_arc(c, rr, 0.0, TAU, 28, Color(0, 0, 0, 0.6), 5.0, true)
		marks.draw_arc(c, rr, 0.0, TAU, 28, tc, 3.0, true)


func _text_c(font: Font, at: Vector2, txt: String, px: int, col: Color) -> void:
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
	marks.draw_string_outline(font, at + Vector2(-tw.x * 0.5, 0.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 6, Color(0, 0, 0, 0.9))
	marks.draw_string(font, at + Vector2(-tw.x * 0.5, 0.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
