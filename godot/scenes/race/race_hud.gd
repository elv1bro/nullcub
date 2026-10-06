## HUD «Гонки: 10 точек» (docs/plan-demo/RACE.md). Боевой HUD (scenes/ui/hud.gd) — панели HP на двоих-четверых без счёта гонки, поэтому
## здесь свой (как SquadHud): дерево строит сам, шрифты — по скину HUD (HudSkin).
##   • сверху по центру — часы гонки (идут вверх, «0:42.3»), под ними «ГОНКА · ДО 10 ТОЧЕК» и лучшее время P1 на этой карте;
##   • по бокам от часов — плашки четырёх гонщиков: имя и «7/10» цветом игрока (Tuning.PLAYER_COLORS), у лидера — яркая рамка;
##   • над каждым живым гонщиком — имя и полоска HP его цветом; горящие точки за краем кадра — стрелки цвета точки с метрами от
##     игрока (соперников за кадром показывает OffscreenMarkers площадки);
##   • своя точка — диктор «+1 · 7/10» цветом игрока; чужая — строка в ленте справа «БОТ 3 ▸ 6/10»;
##   • игрок выбыл — «ВОЗВРАТ ЧЕРЕЗ N»; подсказка клавиш первые HINT_S секунд; тосты клавиш (U, K, M, N, H) — снизу;
##   • конец — табличка: кто победил, время, таблица мест (точки, нокауты, выбывания), лучшее время и «НОВЫЙ РЕКОРД!».
## bind(match, playground) — подписка на RaceMatch по именам сигналов.
class_name RaceHud
extends CanvasLayer

const PLATE_W := 150.0
const PLATE_H := 78.0
const TIMER_W := 190.0
const TOP := 14.0
const GAP := 8.0
const FEED_MAX := 4
const FEED_HOLD_S := 4.0
const HINT_S := 9.0
const BAR_W := 56.0
const BAR_H := 6.0
const BAR_LIFT := 0.62
const ARROW_MARGIN := 46.0
const TOAST_S := 1.4

var match_node: RaceMatch
var playground: Node
var root: Control
var announcer: Announcer
var timer_label: Label
var caption: Label
var best_label: Label
var feed: VBoxContainer
var marks: Control
var hint: Label
var respawn_label: Label
var toast_label: Label
var end_panel: PanelContainer
var end_title: Label
var end_time: Label
var end_table: GridContainer
var end_best: Label
var plates: Array = []           # PanelContainer × 4 (по player_index)
var plate_names: Array = []
var plate_scores: Array = []
var _timer_plate: PanelContainer
var _feed_rows: Array = []       # [[Label, осталось с]]
var _clock := 0.0
var _toast_left := 0.0
var _leader := -1
var _placed: Array = []          # стрелки к точкам, уже нарисованные в этом кадре (раздвинуть соседние)


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
	_build_feed()
	_build_bottom()
	_build_end()
	announcer = Announcer.new()
	announcer.name = "Announcer"
	announcer.set_anchors_preset(Control.PRESET_CENTER)
	announcer.offset_top = -170.0
	announcer.offset_bottom = -170.0
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


## Часы по центру, плашки гонщиков по бокам (P1, P2 — слева, P3, P4 — справа), под часами — подпись и лучшее время.
func _build_top() -> void:
	_timer_plate = PanelContainer.new()
	_timer_plate.name = "Timer"
	_timer_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer_plate.anchor_left = 0.5
	_timer_plate.anchor_right = 0.5
	_timer_plate.offset_left = -TIMER_W * 0.5
	_timer_plate.offset_right = TIMER_W * 0.5
	_timer_plate.offset_top = TOP + 6.0
	_timer_plate.offset_bottom = TOP + PLATE_H - 6.0
	timer_label = _label("Time", 42, Color.WHITE)
	timer_label.text = "0:00.0"
	_timer_plate.add_child(timer_label)
	root.add_child(_timer_plate)
	var xs := [-TIMER_W * 0.5 - GAP * 2.0 - PLATE_W * 2.0, -TIMER_W * 0.5 - GAP - PLATE_W, TIMER_W * 0.5 + GAP, TIMER_W * 0.5 + GAP * 2.0 + PLATE_W]
	for i in Tuning.RACE_RACERS:
		var plate := PanelContainer.new()
		plate.name = "Racer%d" % i
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.anchor_left = 0.5
		plate.anchor_right = 0.5
		var x0: float = xs[i] if i < xs.size() else 0.0
		plate.offset_left = x0
		plate.offset_right = x0 + PLATE_W
		plate.offset_top = TOP
		plate.offset_bottom = TOP + PLATE_H
		plate.pivot_offset = Vector2(PLATE_W, PLATE_H) * 0.5
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", -4)
		plate.add_child(v)
		var c := _colour(i)
		var nl := _label("Name", 18, c.lightened(0.35))
		var sl := _label("Score", 40, Color.WHITE)
		sl.text = "0/%d" % Tuning.RACE_TO_WIN
		v.add_child(nl)
		v.add_child(sl)
		root.add_child(plate)
		plates.append(plate)
		plate_names.append(nl)
		plate_scores.append(sl)
	caption = _label("Caption", 22, Color(1, 1, 1, 0.85))
	caption.anchor_left = 0.5
	caption.anchor_right = 0.5
	caption.offset_left = -360.0
	caption.offset_right = 360.0
	caption.offset_top = TOP + PLATE_H + 4.0
	caption.offset_bottom = TOP + PLATE_H + 34.0
	root.add_child(caption)
	best_label = _label("Best", 20, Color(0.75, 1.0, 0.85, 0.9))
	best_label.anchor_left = 0.5
	best_label.anchor_right = 0.5
	best_label.offset_left = -360.0
	best_label.offset_right = 360.0
	best_label.offset_top = TOP + PLATE_H + 32.0
	best_label.offset_bottom = TOP + PLATE_H + 60.0
	root.add_child(best_label)


func _build_feed() -> void:
	feed = VBoxContainer.new()
	feed.name = "Feed"
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed.anchor_left = 1.0
	feed.anchor_right = 1.0
	feed.offset_left = -420.0
	feed.offset_right = -24.0
	feed.offset_top = 120.0
	feed.offset_bottom = 320.0
	feed.add_theme_constant_override("separation", 4)
	root.add_child(feed)


func _build_bottom() -> void:
	hint = _label("Hint", 22, Color(1, 1, 1, 0.8))
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -700.0
	hint.offset_right = 700.0
	hint.offset_top = -64.0
	hint.offset_bottom = -24.0
	root.add_child(hint)
	toast_label = _label("Toast", 26, Color.WHITE)
	toast_label.anchor_left = 0.5
	toast_label.anchor_right = 0.5
	toast_label.anchor_top = 1.0
	toast_label.anchor_bottom = 1.0
	toast_label.offset_left = -300.0
	toast_label.offset_right = 300.0
	toast_label.offset_top = -120.0
	toast_label.offset_bottom = -80.0
	toast_label.visible = false
	root.add_child(toast_label)
	respawn_label = _label("Respawn", 54, Color.WHITE)
	respawn_label.set_anchors_preset(Control.PRESET_CENTER)
	respawn_label.offset_left = -500.0
	respawn_label.offset_right = 500.0
	respawn_label.offset_top = 40.0
	respawn_label.offset_bottom = 120.0
	respawn_label.visible = false
	root.add_child(respawn_label)


func _build_end() -> void:
	end_panel = PanelContainer.new()
	end_panel.name = "End"
	end_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_panel.set_anchors_preset(Control.PRESET_CENTER)
	end_panel.offset_left = -400.0
	end_panel.offset_right = 400.0
	end_panel.offset_top = -190.0
	end_panel.offset_bottom = 270.0
	end_panel.visible = false
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 10)
	end_panel.add_child(v)
	end_title = _label("Title", 52, Color.WHITE)
	end_time = _label("Time", 40, Color.WHITE)
	end_table = GridContainer.new()
	end_table.name = "Table"
	end_table.columns = 5
	end_table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_table.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	end_table.add_theme_constant_override("h_separation", 30)
	end_table.add_theme_constant_override("v_separation", 2)
	end_best = _label("Best", 24, Color(0.75, 1.0, 0.85))
	var again := _label("Again", 22, Color(1, 1, 1, 0.7))
	again.text = tr("R — заново · Esc — пауза и выход в гараж")
	for l in [end_title, end_time, end_table, end_best, again]:
		v.add_child(l)
	root.add_child(end_panel)


func _apply_skin() -> void:
	for l in root.find_children("*", "Label", true, false):
		if (l as Node).has_meta("px"):
			HudSkin.style_label(l, "display", int(l.get_meta("px")), l.get_meta("colour"))
			(l as Label).add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			(l as Label).add_theme_constant_override("outline_size", 6)
	_style_plates()
	var tb := StyleBoxFlat.new()
	tb.bg_color = Color(0.03, 0.035, 0.05, 0.86)
	tb.border_color = RacePoint.COLOUR
	tb.border_width_bottom = 2
	tb.set_corner_radius_all(4)
	_timer_plate.add_theme_stylebox_override("panel", tb)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.035, 0.05, 0.92)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 30.0
	sb.content_margin_right = 30.0
	sb.content_margin_top = 18.0
	sb.content_margin_bottom = 18.0
	end_panel.add_theme_stylebox_override("panel", sb)


## Плашки гонщиков: полоса снизу цветом игрока, у лидера — рамка целиком и толще.
func _style_plates() -> void:
	for i in plates.size():
		var c := _colour(i).lightened(0.25)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.035, 0.05, 0.86)
		sb.border_color = c
		sb.border_width_bottom = 6
		if i == _leader:
			sb.border_width_top = 3
			sb.border_width_left = 3
			sb.border_width_right = 3
			sb.bg_color = Color(c.r * 0.25, c.g * 0.25, c.b * 0.25, 0.9)
		sb.set_corner_radius_all(4)
		(plates[i] as PanelContainer).add_theme_stylebox_override("panel", sb)


static func _colour(pi: int) -> Color:
	return Tuning.PLAYER_COLORS[pi % Tuning.PLAYER_COLORS.size()] if pi >= 0 else Color.WHITE


func bind(m: RaceMatch, pg: Node = null) -> void:
	match_node = m
	playground = pg
	var pairs := [["score_changed", _on_score], ["point_taken", _on_taken], ["announce", _on_announce], ["time_left", _on_time],
		["match_over", _on_over], ["phase_changed", _on_phase], ["ko", _on_ko]]
	for p in pairs:
		if m.has_signal(p[0]) and not m.is_connected(p[0], p[1]):
			m.connect(p[0], p[1])
	caption.text = tr("ГОНКА · ДО %d ТОЧЕК") % m.to_win
	hint.text = tr("Собери %d точек раньше всех · WASD — лететь · Shift — ускорение · U — второй игрок · K — уровень ботов · R — заново") % m.to_win
	refresh_names()
	_on_score(m.scores)
	show_best(_best(), false)


func _best() -> float:
	return float(playground.call("best_time")) if playground != null and playground.has_method("best_time") else -1.0


## Имя гонщика: человек P1 — ТЫ, человек P2 — ИГРОК 2, бот — БОТ N (N = player_index + 1, как стрелки OffscreenMarkers «P N»).
static func name_of(d: Object) -> String:
	if d == null or not is_instance_valid(d):
		return ""
	var dd := d as Doll
	if not dd.external_input:
		return TranslationServer.translate("ТЫ") if dd.player_index == 0 else TranslationServer.translate("ИГРОК %d") % (dd.player_index + 1)
	return TranslationServer.translate("БОТ %d") % (dd.player_index + 1)


func refresh_names() -> void:
	if match_node == null:
		return
	for d in match_node.dolls():
		var pi := (d as Doll).player_index
		if pi >= 0 and pi < plate_names.size():
			(plate_names[pi] as Label).text = name_of(d)


## Лучшее время P1 на карте (≤ 0 — нет); fresh — только что поставлен.
func show_best(seconds: float, fresh: bool) -> void:
	best_label.text = tr("ЛУЧШЕЕ ВРЕМЯ: %s") % (fmt_time(seconds) if seconds > 0.0 else "—")
	if end_best != null:
		end_best.text = (tr("НОВЫЙ РЕКОРД! %s") % fmt_time(seconds)) if fresh else best_label.text


## Время «м:сс.д».
static func fmt_time(s: float) -> String:
	var t := maxf(s, 0.0)
	var m := int(t) / 60
	var rest := t - float(m * 60)
	return "%d:%02d.%d" % [m, int(rest), int(fmod(rest, 1.0) * 10.0)]


func toast(text: String) -> void:
	toast_label.text = text
	toast_label.visible = true
	toast_label.modulate.a = 1.0
	_toast_left = TOAST_S


# --- сигналы ---

func _on_score(scores: Dictionary) -> void:
	for i in plate_scores.size():
		(plate_scores[i] as Label).text = "%d/%d" % [int(scores.get(i, 0)), match_node.to_win if match_node != null else Tuning.RACE_TO_WIN]
	var lead := match_node.leader() if match_node != null else null
	var li := lead.player_index if lead != null else -1
	if li != _leader:
		_leader = li
		_style_plates()


func _on_taken(d: Doll, _mark: int, _pos: Vector3, score: int) -> void:
	var pi := d.player_index if is_instance_valid(d) else -1
	if pi >= 0 and pi < plates.size():
		var p := plates[pi] as Control
		var tw := p.create_tween().set_ignore_time_scale(true)
		tw.tween_property(p, "scale", Vector2(1.25, 1.25), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var to_win := match_node.to_win if match_node != null else Tuning.RACE_TO_WIN
	if is_instance_valid(d) and not d.external_input:
		announcer.announce("+1 · %d/%d" % [score, to_win], _colour(pi).lightened(0.3), "event")
		return
	var row := _label("Row", 24, _colour(pi).lightened(0.35))
	row.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.text = "%s ▸ %d/%d" % [name_of(d), score, to_win]
	feed.add_child(row)
	HudSkin.style_label(row, "display", 24, _colour(pi).lightened(0.35))
	row.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	row.add_theme_constant_override("outline_size", 6)
	_feed_rows.append([row, FEED_HOLD_S])
	while _feed_rows.size() > FEED_MAX:
		var old: Array = _feed_rows.pop_front()
		(old[0] as Node).queue_free()


## KO! на табло — только если в нокауте участвует человек (KO ботов между собой на другом краю карты — шум).
func _on_ko(victim: Doll, attacker: Node, _rec: Dictionary) -> void:
	var human := (is_instance_valid(victim) and not victim.external_input) or (attacker is Doll and is_instance_valid(attacker) and not (attacker as Doll).external_input)
	if human:
		announcer.announce(tr("KO!"), Color(1.0, 0.85, 0.3), "ko")


func _on_announce(text: String, color: Color, kind: String) -> void:
	if kind in ["countdown", "fight"]:
		announcer.announce(text, color, kind)
	elif kind in ["head", "body", "double", "combo"]:
		announcer.announce(text, color, kind)   # Match.on_hit шлёт их только для ударов с человеком (RaceMatch.on_hit)


func _on_time(_seconds: float) -> void:
	pass


func _on_phase(p: int) -> void:
	if p == Match.Phase.COUNTDOWN:
		end_panel.visible = false
		hint.visible = true
		hint.modulate.a = 1.0
		_clock = 0.0
		for r in _feed_rows:
			(r[0] as Node).queue_free()
		_feed_rows.clear()
		refresh_names()


func _on_over(_winner: Doll, results: Dictionary) -> void:
	var wi := int(results.get("winner_index", -1))
	var w: Doll = results.get("winner") as Doll
	if w == null or not is_instance_valid(w):
		end_title.text = tr("НИЧЬЯ")
		end_title.set_meta("colour", Color.WHITE)
	elif not w.external_input and wi == 0:
		end_title.text = tr("ПОБЕДА!")
		end_title.set_meta("colour", _colour(wi).lightened(0.4))
	else:
		end_title.text = tr("ПОБЕДИЛ: %s") % name_of(w)
		end_title.set_meta("colour", _colour(wi).lightened(0.4))
	var t := float(results.get("race_time", 0.0))
	end_time.text = fmt_time(t) if String(results.get("reason", "")) == "points" else tr("ВРЕМЯ ВЫШЛО · %s") % fmt_time(t)
	for c in end_table.get_children():
		end_table.remove_child(c)
		c.queue_free()
	var white := Color(1, 1, 1, 0.75)
	for h in [tr("МЕСТО"), tr("ГОНЩИК"), tr("ТОЧКИ"), tr("НОКАУТЫ"), tr("ВЫБЫЛ")]:
		_cell(h, white, end_table.get_child_count() == 1)
	var scores: Dictionary = results.get("scores", {})
	var tally: Dictionary = results.get("tally", {})
	var places: Array = results.get("places", [])
	for i in places.size():
		var d := places[i] as Doll
		if d == null or not is_instance_valid(d):
			continue
		var tl: Dictionary = tally.get(d.player_index, {})
		var c := _colour(d.player_index).lightened(0.4)
		_cell(str(i + 1), Color.WHITE, false)
		_cell(name_of(d), c, true)
		_cell("%d/%d" % [int(scores.get(d.player_index, 0)), int(results.get("to_win", Tuning.RACE_TO_WIN))], Color.WHITE, false)
		_cell(str(int(tl.get("kos", 0))), Color.WHITE, false)
		_cell(str(int(tl.get("kos_taken", 0))), Color.WHITE, false)
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


# --- кадр ---

func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.02)
	_clock += real
	if hint.visible and _clock > HINT_S:
		hint.modulate.a = maxf(hint.modulate.a - real * 1.5, 0.0)
		hint.visible = hint.modulate.a > 0.0
	if _toast_left > 0.0:
		_toast_left -= real
		toast_label.modulate.a = clampf(_toast_left / 0.3, 0.0, 1.0)
		toast_label.visible = _toast_left > 0.0
	var i := 0
	while i < _feed_rows.size():
		var r: Array = _feed_rows[i]
		r[1] = float(r[1]) - real
		var l := r[0] as CanvasItem
		l.modulate.a = clampf(float(r[1]) / 0.6, 0.0, 1.0)
		if float(r[1]) <= 0.0:
			l.queue_free()
			_feed_rows.remove_at(i)
		else:
			i += 1
	if match_node != null:
		var ft := match_node.fight_time if match_node.play_state in ["play", "over"] else 0.0
		timer_label.text = fmt_time(ft)
		var me := match_node.me()
		respawn_label.visible = false
		if me != null and not me.alive and match_node.play_state == "play":
			var left := match_node.respawn_left(me)
			if left >= 0.0:
				respawn_label.text = tr("ВОЗВРАТ ЧЕРЕЗ %d") % int(ceil(left))
				respawn_label.visible = true
	marks.queue_redraw()


## Имена и полоски HP над гонщиками, стрелки к горящим точкам за кадром.
func _draw_marks() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or match_node == null or end_panel.visible:
		return
	var font := HudSkin.font("display")
	if font == null:
		font = ThemeDB.fallback_font
	var vp := get_viewport().get_visible_rect().size
	var to_canvas := marks.get_global_transform_with_canvas().affine_inverse()
	var me := match_node.me()
	for n in match_node.dolls():
		var d := n as Doll
		if not is_instance_valid(d) or not d.is_inside_tree() or not d.alive:
			continue
		var head: Node3D = d.parts.get("Head", d.torso()) as Node3D
		if head == null:
			continue
		var top := head.global_position + Vector3(0.0, BAR_LIFT, 0.0)
		if cam.is_position_behind(top):
			continue
		var sp: Vector2 = to_canvas * cam.unproject_position(top)
		if sp.x < 0.0 or sp.y < 0.0 or sp.x > vp.x or sp.y > vp.y:
			continue
		var c := _colour(d.player_index).lightened(0.3)
		var r := Rect2(sp - Vector2(BAR_W * 0.5, BAR_H * 0.5), Vector2(BAR_W, BAR_H))
		marks.draw_rect(r.grow(2.0), Color(0.03, 0.03, 0.04, 0.85))
		marks.draw_rect(Rect2(r.position, Vector2(BAR_W * clampf(d.hp / maxf(d.max_hp, 1.0), 0.0, 1.0), BAR_H)), c)
		var txt := "%s · %d" % [name_of(d), match_node.score_of(d)]
		var fs := 20 if d != me else 22
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var pos := sp + Vector2(-tw.x * 0.5, -10.0)
		marks.draw_string_outline(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.9))
		marks.draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE if d == me else c)
	var from := me.centre_of_mass() if me != null else Vector3.ZERO
	_placed.clear()
	for p in match_node.lit_points():
		var hp := (p as RacePoint).home
		var behind := cam.is_position_behind(hp)
		var sp2: Vector2 = to_canvas * cam.unproject_position(hp)
		if not behind and sp2.x > 0.0 and sp2.y > 0.0 and sp2.x < vp.x and sp2.y < vp.y:
			continue
		_arrow(sp2, vp, RacePoint.COLOUR, Vector2(hp.x - from.x, hp.y - from.y).length() if me != null else -1.0, font)


## Стрелка к точке за краем кадра: треугольник цвета точки, внутри кружок (знак «точка»), рядом — метры от игрока.
func _arrow(sp: Vector2, vp: Vector2, c: Color, metres: float, font: Font) -> void:
	var centre := vp * 0.5
	var dir := sp - centre
	if dir.length() < 1.0:
		return
	dir = dir.normalized()
	var half := centre - Vector2(ARROW_MARGIN, ARROW_MARGIN)
	var k := minf(half.x / maxf(absf(dir.x), 1e-4), half.y / maxf(absf(dir.y), 1e-4))
	var p := centre + dir * k
	# у бокового края — вдоль края по вертикали, у верхнего/нижнего — по горизонтали: две точки в одной стороне не слипаются,
	# справа посередине — подсказка «L — клавиши» (HitJuice), стрелка мимо неё
	var vertical_edge := absf(p.x - centre.x) >= half.x - 1.0
	var step := Vector2(0.0, 52.0) if vertical_edge else Vector2(70.0, 0.0)
	if vertical_edge and p.x > centre.x and absf(p.y - centre.y) < 36.0:
		p.y += 48.0 * (1.0 if p.y >= centre.y else -1.0)
	for guard in 6:
		var clash := false
		for q in _placed:
			if (q as Vector2).distance_to(p) < 46.0:
				clash = true
				break
		if not clash:
			break
		p += step
		if p.y > vp.y - ARROW_MARGIN or p.x > vp.x - ARROW_MARGIN:
			step = -step
			p += step * 2.0
	p = p.clamp(Vector2(ARROW_MARGIN, ARROW_MARGIN), vp - Vector2(ARROW_MARGIN, ARROW_MARGIN))
	_placed.append(p)
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([p + dir * 20.0, p - dir * 10.0 + side * 14.0, p - dir * 10.0 - side * 14.0])
	marks.draw_colored_polygon(pts, c)
	marks.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.8), 2.0)
	marks.draw_circle(p - dir * 26.0, 8.0, Color(0, 0, 0, 0.6))
	marks.draw_arc(p - dir * 26.0, 7.0, 0.0, TAU, 20, c, 3.0, true)
	if metres < 0.0:
		return
	var txt := tr("%d м") % int(round(metres))
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	var tp := p - dir * 50.0 + Vector2(-tw.x * 0.5, 6.0)
	marks.draw_string_outline(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0, 0, 0, 0.9))
	marks.draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, c)
