## HUD «Гонки: трасса» (docs/plan-demo/RACE_TRACK.md). Дерево строит сам (как RaceHud), шрифты — по скину HUD (HudSkin).
##   • сверху — полоска трассы: шесть участков (по прогрессу линии, цвета участков), флажок финиша и метки всех гонщиков цветом
##     игрока (P1…P4; «я» крупнее, выбывший — бледный);
##   • под ней по центру — часы гонки, слева плашка «МЕСТО 2/4», справа — номер и имя участка; ниже — лучшее время P1;
##   • справа — таблица мест сейчас (место, имя, пройденная доля трассы или время финиша);
##   • над гонщиками — имя и полоска HP; контрольная точка — диктор «КОНТРОЛЬНАЯ ТОЧКА · N», кольцо — «+ЗАРЯД», финиш — «ФИНИШ! МЕСТО N»;
##   • выбыл — «ВОЗВРАТ ЧЕРЕЗ N» и причина (KO, яма, застрял, Q); подсказка клавиш первые HINT_S секунд; тосты клавиш — снизу;
##   • «я» в поле гравитации (TrackZone) — строка снизу, что это поле делает и что жать (ZONE_HINTS по ключу силы поля);
##   • конец — табличка: кто победил, время, таблица мест (время финиша или пройденная доля, нокауты, возвраты), лучшее время.
## bind(match, playground) — подписка на TrackMatch по именам сигналов.
class_name TrackHud
extends CanvasLayer

## Имена участков (ключи перевода — tr() в месте показа).
const SECTION_NAMES := ["РАЗГОН И КОЛЬЦА", "ПРЕССЫ И МАГНИТЫ", "ТРУБЫ", "ГРАВИТАЦИЯ", "ТЯЖЁЛАЯ ЗОНА", "ЯМА"]
## Цвета участков на полоске (как материалы карты).
const SECTION_COLOURS := [Color(0.9, 0.75, 0.5), Color(0.75, 0.6, 0.5), Color(0.55, 0.78, 0.9), Color(0.5, 0.62, 1.0),
	Color(0.95, 0.45, 0.38), Color(0.75, 0.72, 0.66)]
## Подсказка, пока «я» в поле (ключ — g_key поля TrackZone; ключи перевода — tr() в месте показа).
const ZONE_HINTS := {
	"TRACK_SIDE_G": "ВСТРЕЧНОЕ ПОЛЕ — сносит назад",
	"TRACK_UP_G": "ПОЛЕ ВВЕРХ — в потолке сетка, держись ниже",
	"TRACK_HEAVY_G": "ТЯЖЁЛАЯ ЗОНА — вверх только с ускорением (Shift, Заряд)",
	"TRACK_PIT_G": "ЯМА ТЯНЕТ ВНИЗ — мосты рвутся, бочки взрываются",
}
const STRIP_W := 1100.0
const STRIP_TOP := 12.0
const STRIP_H := 10.0
const TOP := 62.0
const PLATE_W := 230.0
const PLATE_H := 64.0
const TIMER_W := 190.0
const GAP := 10.0
const HINT_S := 10.0
const BAR_W := 56.0
const BAR_H := 6.0
const BAR_LIFT := 0.62
const TOAST_S := 1.4

var match_node: TrackMatch
var playground: Node
var root: Control
var announcer: Announcer
var strip: Control
var timer_label: Label
var place_label: Label
var section_label: Label
var best_label: Label
var table: VBoxContainer
var marks: Control
var hint: Label
var respawn_label: Label
var respawn_why: Label
var zone_label: Label
var _zones: Array = []           # TrackZone карты
var toast_label: Label
var end_panel: PanelContainer
var end_title: Label
var end_time: Label
var end_table: GridContainer
var end_best: Label
var _plates: Array = []
var _rows: Array = []            # Label по местам
var _clock := 0.0
var _toast_left := 0.0
var _sec_bounds: Array = []      # доли трассы начала участков 2..6


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
	strip = Control.new()
	strip.name = "Strip"
	strip.set_anchors_preset(Control.PRESET_FULL_RECT)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.draw.connect(_draw_strip)
	root.add_child(strip)
	_build_top()
	_build_table()
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


func _plate(n: String, x0: float, w: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = n
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.offset_left = x0
	p.offset_right = x0 + w
	p.offset_top = TOP
	p.offset_bottom = TOP + PLATE_H
	root.add_child(p)
	_plates.append(p)
	return p


## Часы по центру, слева — место, справа — участок; под часами — лучшее время.
func _build_top() -> void:
	var tp := _plate("Timer", -TIMER_W * 0.5, TIMER_W)
	timer_label = _label("Time", 40, Color.WHITE)
	timer_label.text = "0:00.0"
	tp.add_child(timer_label)
	var pp := _plate("Place", -TIMER_W * 0.5 - GAP - PLATE_W, PLATE_W)
	place_label = _label("Place", 30, Color.WHITE)
	pp.add_child(place_label)
	var sp := _plate("Section", TIMER_W * 0.5 + GAP, PLATE_W + 120.0)
	section_label = _label("Section", 24, Color.WHITE)
	section_label.clip_text = true
	section_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sp.add_child(section_label)
	best_label = _label("Best", 20, Color(0.75, 1.0, 0.85, 0.9))
	best_label.anchor_left = 0.5
	best_label.anchor_right = 0.5
	best_label.offset_left = -360.0
	best_label.offset_right = 360.0
	best_label.offset_top = TOP + PLATE_H + 4.0
	best_label.offset_bottom = TOP + PLATE_H + 32.0
	root.add_child(best_label)


func _build_table() -> void:
	table = VBoxContainer.new()
	table.name = "Standings"
	table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	table.anchor_left = 1.0
	table.anchor_right = 1.0
	table.offset_left = -330.0
	table.offset_right = -24.0
	table.offset_top = 150.0
	table.offset_bottom = 330.0
	table.add_theme_constant_override("separation", 2)
	root.add_child(table)
	for i in Tuning.TRACK_RACERS:
		var l := _label("Row%d" % i, 22, Color.WHITE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		table.add_child(l)
		_rows.append(l)


func _build_bottom() -> void:
	hint = _label("Hint", 21, Color(1, 1, 1, 0.8))
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -880.0
	hint.offset_right = 880.0
	hint.offset_top = -84.0
	hint.offset_bottom = -20.0
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(hint)
	toast_label = _label("Toast", 26, Color.WHITE)
	toast_label.anchor_left = 0.5
	toast_label.anchor_right = 0.5
	toast_label.anchor_top = 1.0
	toast_label.anchor_bottom = 1.0
	toast_label.offset_left = -300.0
	toast_label.offset_right = 300.0
	toast_label.offset_top = -130.0
	toast_label.offset_bottom = -90.0
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
	zone_label = _label("ZoneHint", 26, Color(1.0, 0.86, 0.62))
	zone_label.anchor_left = 0.5
	zone_label.anchor_right = 0.5
	zone_label.anchor_top = 1.0
	zone_label.anchor_bottom = 1.0
	zone_label.offset_left = -700.0
	zone_label.offset_right = 700.0
	zone_label.offset_top = -176.0
	zone_label.offset_bottom = -136.0
	zone_label.visible = false
	root.add_child(zone_label)
	respawn_why = _label("RespawnWhy", 26, Color(1.0, 0.85, 0.6))
	respawn_why.set_anchors_preset(Control.PRESET_CENTER)
	respawn_why.offset_left = -500.0
	respawn_why.offset_right = 500.0
	respawn_why.offset_top = 120.0
	respawn_why.offset_bottom = 160.0
	respawn_why.visible = false
	root.add_child(respawn_why)


func _build_end() -> void:
	end_panel = PanelContainer.new()
	end_panel.name = "End"
	end_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_panel.set_anchors_preset(Control.PRESET_CENTER)
	end_panel.offset_left = -440.0
	end_panel.offset_right = 440.0
	end_panel.offset_top = -200.0
	end_panel.offset_bottom = 280.0
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
	for p in _plates:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.035, 0.05, 0.86)
		sb.border_color = TrackCheckpoint.COLOUR
		sb.border_width_bottom = 2
		sb.set_corner_radius_all(4)
		(p as PanelContainer).add_theme_stylebox_override("panel", sb)
	var eb := StyleBoxFlat.new()
	eb.bg_color = Color(0.03, 0.035, 0.05, 0.92)
	eb.set_corner_radius_all(8)
	eb.content_margin_left = 30.0
	eb.content_margin_right = 30.0
	eb.content_margin_top = 18.0
	eb.content_margin_bottom = 18.0
	end_panel.add_theme_stylebox_override("panel", eb)


static func _colour(pi: int) -> Color:
	return Tuning.PLAYER_COLORS[pi % Tuning.PLAYER_COLORS.size()] if pi >= 0 else Color.WHITE


func bind(m: TrackMatch, pg: Node = null) -> void:
	match_node = m
	playground = pg
	var pairs := [["announce", _on_announce], ["match_over", _on_over], ["phase_changed", _on_phase], ["ko", _on_ko],
		["checkpoint_reached", _on_checkpoint], ["ring_taken", _on_ring], ["racer_finished", _on_finished]]
	for p in pairs:
		if m.has_signal(p[0]) and not m.is_connected(p[0], p[1]):
			m.connect(p[0], p[1])
	hint.text = tr("До финиша первым · WASD — лететь · Shift — ускорение (Заряд) · Q — к контрольной точке · U — второй игрок · K — боты · R — заново")
	refresh_names()
	show_best(_best(), false)
	_zones.clear()
	var ar: Node = m.arena_node if m.arena_node != null else m.get_tree().get_first_node_in_group("arena")
	if ar != null:
		_zones = ar.find_children("*", "TrackZone", true, false)


func _best() -> float:
	return float(playground.call("best_time")) if playground != null and playground.has_method("best_time") else -1.0


func refresh_names() -> void:
	pass   # имена берутся каждый кадр (RaceHud.name_of): после U сразу «ИГРОК 2»


## Лучшее время P1 (≤ 0 — нет); fresh — только что поставлен.
func show_best(seconds: float, fresh: bool) -> void:
	best_label.text = tr("ЛУЧШЕЕ ВРЕМЯ: %s") % (RaceHud.fmt_time(seconds) if seconds > 0.0 else "—")
	if end_best != null:
		end_best.text = (tr("НОВЫЙ РЕКОРД! %s") % RaceHud.fmt_time(seconds)) if fresh else best_label.text


func toast(text: String) -> void:
	toast_label.text = text
	toast_label.visible = true
	toast_label.modulate.a = 1.0
	_toast_left = TOAST_S


## Участок n (1..6): «3 · ТРУБЫ».
static func section_title(n: int) -> String:
	var i := clampi(n - 1, 0, SECTION_NAMES.size() - 1)
	return "%d · %s" % [i + 1, TranslationServer.translate(SECTION_NAMES[i])]


# --- сигналы ---

func _on_checkpoint(d: Doll, index: int) -> void:
	if is_instance_valid(d) and not d.external_input:
		announcer.announce(tr("КОНТРОЛЬНАЯ ТОЧКА · %d") % (index + 1), TrackCheckpoint.COLOUR, "event")


func _on_ring(d: Doll, _ring: Node3D) -> void:
	if is_instance_valid(d) and not d.external_input:
		announcer.announce(tr("+ЗАРЯД"), TrackRing.COLOUR, "event")


func _on_finished(d: Doll, place: int, seconds: float) -> void:
	if is_instance_valid(d) and not d.external_input:
		announcer.announce(tr("ФИНИШ! МЕСТО %d") % place, _colour(d.player_index).lightened(0.4), "event")
		toast(RaceHud.fmt_time(seconds))


## KO! — только если в нокауте ударом участвует человек (яма, «застрял», Q — без надписи: там своя строка у возврата).
func _on_ko(victim: Doll, attacker: Node, rec: Dictionary) -> void:
	if String(rec.get("kind", "")) in ["fall", "stuck", "reset"]:
		return
	var human := (is_instance_valid(victim) and not victim.external_input) or (is_instance_valid(attacker) and attacker is Doll and not (attacker as Doll).external_input)
	if human:
		announcer.announce(tr("KO!"), Color(1.0, 0.85, 0.3), "ko")


func _on_announce(text: String, color: Color, kind: String) -> void:
	if kind in ["countdown", "fight", "head", "body", "double", "combo"]:
		announcer.announce(text, color, kind)


func _on_phase(p: int) -> void:
	if p == Match.Phase.COUNTDOWN:
		end_panel.visible = false
		hint.visible = true
		hint.modulate.a = 1.0
		_clock = 0.0
		_sec_bounds.clear()


func _on_over(_winner: Doll, results: Dictionary) -> void:
	var wi := int(results.get("winner_index", -1))
	var w: Doll = results.get("winner") as Doll
	if w == null or not is_instance_valid(w):
		end_title.text = tr("НИКТО НЕ ДОЕХАЛ")
		end_title.set_meta("colour", Color.WHITE)
	elif not w.external_input and wi == 0:
		end_title.text = tr("ПОБЕДА!")
		end_title.set_meta("colour", _colour(wi).lightened(0.4))
	else:
		end_title.text = tr("ПОБЕДИЛ: %s") % RaceHud.name_of(w)
		end_title.set_meta("colour", _colour(wi).lightened(0.4))
	var wt := float(results.get("winner_time", -1.0))
	end_time.text = RaceHud.fmt_time(wt) if wt >= 0.0 else tr("ВРЕМЯ ВЫШЛО · %s") % RaceHud.fmt_time(float(results.get("race_time", 0.0)))
	for c in end_table.get_children():
		end_table.remove_child(c)
		c.queue_free()
	var white := Color(1, 1, 1, 0.75)
	for h in [tr("МЕСТО"), tr("ГОНЩИК"), tr("ВРЕМЯ"), tr("НОКАУТЫ"), tr("ВОЗВРАТЫ")]:
		_cell(h, white, end_table.get_child_count() == 1)
	var per: Dictionary = results.get("racers", {})
	var places: Array = results.get("places", [])
	for i in places.size():
		var d := places[i] as Doll
		if d == null or not is_instance_valid(d):
			continue
		var r: Dictionary = per.get(d.player_index, {})
		var c := _colour(d.player_index).lightened(0.4)
		_cell(str(i + 1), Color.WHITE, false)
		_cell(RaceHud.name_of(d), c, true)
		var t := RaceHud.fmt_time(float(r.get("finish_t", 0.0))) if bool(r.get("finished", false)) else "%d%%" % int(round(float(r.get("fraction", 0.0)) * 100.0))
		_cell(t, Color.WHITE, false)
		_cell(str(int(r.get("kos", 0))), Color.WHITE, false)
		_cell(str(int(r.get("kos_taken", 0)) + int(r.get("falls", 0)) + int(r.get("stucks", 0)) + int(r.get("resets", 0))), Color.WHITE, false)
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
	if match_node != null:
		var ft := match_node.fight_time if match_node.play_state in ["play", "over"] else 0.0
		timer_label.text = RaceHud.fmt_time(ft)
		var me := match_node.me()
		var order := match_node.standings()
		place_label.text = tr("МЕСТО %d/%d") % [maxi(order.find(me) + 1, 1), order.size()] if me != null else ""
		section_label.text = section_title(match_node.section_of(me)) if me != null else ""
		for i in _rows.size():
			var l := _rows[i] as Label
			if i >= order.size():
				l.text = ""
				continue
			var d := order[i] as Doll
			var st := match_node.state_of(d)
			var tail := RaceHud.fmt_time(float(st["finish_t"])) if bool(st["finished"]) else "%d%%" % int(match_node.fraction_of(d) * 100.0)
			l.text = "%d  %s  ·  %s" % [i + 1, RaceHud.name_of(d), tail]
			l.add_theme_color_override("font_color", _colour(d.player_index).lightened(0.45 if d == me else 0.25))
		respawn_label.visible = false
		respawn_why.visible = false
		zone_label.visible = false
		if me != null and me.alive and match_node.play_state == "play":
			var c := me.centre_of_mass()
			for z in _zones:
				var tz := z as TrackZone
				if is_instance_valid(tz) and ZONE_HINTS.has(tz.g_key) and tz.rect().has_point(Vector2(c.x, c.y)):
					zone_label.text = tr(ZONE_HINTS[tz.g_key])
					zone_label.visible = true
					break
		if me != null and not me.alive and match_node.play_state == "play":
			var left := match_node.respawn_left(me)
			if left >= 0.0:
				respawn_label.text = tr("ВОЗВРАТ ЧЕРЕЗ %d") % int(ceil(left))
				respawn_label.visible = true
				respawn_why.text = _why_text(match_node.respawn_why(me))
				respawn_why.visible = respawn_why.text != ""
	marks.queue_redraw()
	strip.queue_redraw()


func _why_text(why: String) -> String:
	match why:
		"fall":
			return tr("ЯМА — к контрольной точке")
		"stuck":
			return tr("ЗАСТРЯЛ — к контрольной точке")
		"reset":
			return tr("К КОНТРОЛЬНОЙ ТОЧКЕ")
	return tr("KO — к контрольной точке")


## Полоска трассы: участки по прогрессу линии, финиш, гонщики.
func _draw_strip() -> void:
	if match_node == null or match_node.route == null or not match_node.route.ready():
		return
	var vp := strip.get_viewport_rect().size
	var w := minf(STRIP_W, vp.x - 120.0)
	var x0 := (vp.x - w) * 0.5
	var y := STRIP_TOP + 22.0
	if _sec_bounds.is_empty():
		var tot := match_node.total_m()
		_sec_bounds.append(0.0)
		for i in range(1, match_node.cp_prog.size()):
			_sec_bounds.append(float(match_node.cp_prog[i]) / maxf(tot, 1.0))
		_sec_bounds.append(1.0)
	strip.draw_rect(Rect2(x0 - 6.0, y - 6.0, w + 12.0, STRIP_H + 12.0), Color(0.02, 0.025, 0.035, 0.8))
	var font := HudSkin.font("display")
	if font == null:
		font = ThemeDB.fallback_font
	for i in _sec_bounds.size() - 1:
		var a := x0 + w * float(_sec_bounds[i])
		var b := x0 + w * float(_sec_bounds[i + 1])
		var c: Color = SECTION_COLOURS[i % SECTION_COLOURS.size()]
		strip.draw_rect(Rect2(a + 1.0, y, b - a - 2.0, STRIP_H), Color(c.r, c.g, c.b, 0.85))
		var num := str(i + 1)
		var tw := font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		strip.draw_string_outline(font, Vector2((a + b) * 0.5 - tw.x * 0.5, y + STRIP_H + 18.0), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.9))
		strip.draw_string(font, Vector2((a + b) * 0.5 - tw.x * 0.5, y + STRIP_H + 18.0), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(c.r, c.g, c.b, 1.0))
	# флажок финиша
	for k in 4:
		for j in 2:
			strip.draw_rect(Rect2(x0 + w + 4.0 + 5.0 * j, y - 6.0 + 5.5 * k, 5.0, 5.5), Color.WHITE if (k + j) % 2 == 0 else Color.BLACK)
	var me := match_node.me()
	var order := match_node.standings()
	for i in range(order.size() - 1, -1, -1):
		var d := order[i] as Doll
		if not is_instance_valid(d):
			continue
		var x := x0 + w * match_node.fraction_of(d)
		var c2 := _colour(d.player_index).lightened(0.3)
		if not d.alive:
			c2.a = 0.45
		var big := d == me
		var s := 11.0 if big else 8.0
		var pts := PackedVector2Array([Vector2(x, y - 1.0), Vector2(x - s, y - 1.0 - s * 1.5), Vector2(x + s, y - 1.0 - s * 1.5)])
		strip.draw_colored_polygon(pts, c2)
		strip.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.85), 2.0)
		var lbl := "P%d" % (d.player_index + 1)
		var fs := 15 if big else 13
		var tw2 := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var tp := Vector2(x - tw2.x * 0.5, y - s * 1.5 - 5.0)
		strip.draw_string_outline(font, tp, lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
		strip.draw_string(font, tp, lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE if big else c2)


## Имена и полоски HP над гонщиками.
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
		var txt := RaceHud.name_of(d)
		var fs := 20 if d != me else 22
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var pos := sp + Vector2(-tw.x * 0.5, -10.0)
		marks.draw_string_outline(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.9))
		marks.draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE if d == me else c)
