## HUD «Босса» (docs/plan-demo/BOSS.md). Дерево строит сам, шрифты — по скину HUD (HudSkin), смена скина перекрашивает на лету:
##   • сверху по центру, крупно, — полоса запаса босса в стиле эфира Лиги: имя «ТИТАН» и «ЧЕМПИОН КОНТИНЕНТА · NULL LEAGUE», фаза
##     «ФАЗА 2/3», полоса (цвет фазы, засечки порогов BOSS_PHASE_AT, белый «хвост» недавнего урона), число запаса; под ней —
##     «СЛАБОЕ МЕСТО: ЛЕВОЕ ПЛЕЧО» (золотом, мигает);
##   • слева сверху — игроки: имя, жизни (кружки), полоса запаса; справа сверху — таймер (до BOSS_TIME_S);
##   • над куклами — имена, над выбитыми — «ВОЗВРАТ 2»; вокруг слабой детали — пульсирующее кольцо; телеграф волны (фаза 3) —
##     сжимающееся красное кольцо радиуса BOSS_WAVE_R вокруг босса;
##   • смена фазы — вспышка экрана цветом фазы, диктор («ФАЗА 2: РЫВКИ») и тост-подсказка; оторванная деталь — тост;
##   • диктор (Announcer) — отсчёт, FIGHT!, KO!, фазы, «ВОЛНА!», «БОСС ПОВЕРЖЕН!»;
##   • снизу — подсказка клавиш (гаснет через HINT_S), тосты U / K / M / N / H;
##   • конец матча — «ТИТАН ПОВЕРЖЕН!» / «ТИТАН ВЫСТОЯЛ», время боя, фаза, детали; таблица игроков (урон, в слабое место, деталей,
##     выбит), «R — заново».
## bind(match, playground) — подписка на BossMatch по именам сигналов.
class_name BossHud
extends CanvasLayer

const TOP := 14.0
const BOSS_BAR_W := 1040.0
const BOSS_BAR_H := 30.0
const HINT_S := 14.0
const NAME_LIFT := 0.5           # м над головой
const GOLD := Color(1.0, 0.85, 0.3)
const PLAYER_COLOURS := [Color(0.35, 0.75, 1.0), Color(0.45, 1.0, 0.55)]
const PART_NAMES := {
	"Head": "ГОЛОВА", "UpperArm_L": "ЛЕВОЕ ПЛЕЧО", "UpperArm_R": "ПРАВОЕ ПЛЕЧО", "LowerArm_L": "ЛЕВОЕ ПРЕДПЛЕЧЬЕ",
	"LowerArm_R": "ПРАВОЕ ПРЕДПЛЕЧЬЕ", "Hand_L": "ЛЕВАЯ КИСТЬ", "Hand_R": "ПРАВАЯ КИСТЬ", "UpperLeg_L": "ЛЕВОЕ БЕДРО",
	"UpperLeg_R": "ПРАВОЕ БЕДРО", "LowerLeg_L": "ЛЕВАЯ ГОЛЕНЬ", "LowerLeg_R": "ПРАВАЯ ГОЛЕНЬ", "Foot_L": "ЛЕВАЯ СТОПА",
	"Foot_R": "ПРАВАЯ СТОПА",
}

var match_node: BossMatch
var playground: Node
var root: Control
var announcer: Announcer
var boss_name: Label
var boss_title: Label
var phase_label: Label
var boss_bar: Control
var boss_value: Label
var weak_label: Label
var clock: Label
var players_box: VBoxContainer
var rows: Dictionary = {}        # player_index → {box, name, bar}
var marks: Control
var flash: ColorRect
var hint: Label
var toast_label: Label
var end_panel: PanelContainer
var end_title: Label
var end_sub: Label
var end_table: GridContainer
var _time := 0.0
var _lag := 1.0                  # «хвост» полосы босса (доля), догоняет запас
var _toast_tw: Tween
var _flash_tw: Tween


func _init() -> void:
	layer = 10


func _ready() -> void:
	root = Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = HudSkin.theme()
	add_child(root)
	flash = ColorRect.new()
	flash.name = "Flash"
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.color = Color(1, 1, 1, 0)
	root.add_child(flash)
	marks = Control.new()
	marks.name = "Marks"
	marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marks.draw.connect(_draw_marks)
	root.add_child(marks)
	_build_boss_bar()
	clock = _label("Clock", 36, Color.WHITE)
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clock.anchor_left = 1.0
	clock.anchor_right = 1.0
	clock.offset_left = -220.0
	clock.offset_right = -24.0
	clock.offset_top = TOP
	clock.offset_bottom = TOP + 46.0
	root.add_child(clock)
	players_box = VBoxContainer.new()
	players_box.name = "Players"
	players_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	players_box.add_theme_constant_override("separation", 6)
	players_box.offset_left = 24.0
	players_box.offset_top = TOP
	players_box.offset_right = 300.0
	players_box.offset_bottom = TOP + 140.0
	root.add_child(players_box)
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
	toast_label.offset_left = -420.0
	toast_label.offset_right = 420.0
	toast_label.offset_top = -120.0
	toast_label.offset_bottom = -80.0
	toast_label.visible = false
	root.add_child(toast_label)
	_build_end()
	_apply_skin()
	HudSkin.events.changed.connect(func(_id: String) -> void: _apply_skin())


func _build_boss_bar() -> void:
	var half := BOSS_BAR_W * 0.5
	boss_name = _label("BossName", 34, Color.WHITE)
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	boss_name.text = tr("ТИТАН")
	_top_centre(boss_name, half, TOP, 40.0)
	root.add_child(boss_name)
	boss_title = _label("BossTitle", 18, Color(1, 1, 1, 0.7))
	boss_title.text = tr("ЧЕМПИОН КОНТИНЕНТА · NULL LEAGUE")
	_top_centre(boss_title, half * 0.62, TOP + 8.0, 28.0)
	root.add_child(boss_title)
	phase_label = _label("Phase", 26, GOLD)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_top_centre(phase_label, half, TOP, 40.0)
	root.add_child(phase_label)
	boss_bar = Control.new()
	boss_bar.name = "BossBar"
	boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_bar.draw.connect(_draw_boss_bar)
	_top_centre(boss_bar, half, TOP + 44.0, BOSS_BAR_H)
	root.add_child(boss_bar)
	boss_value = _label("BossValue", 22, Color.WHITE)
	_top_centre(boss_value, 120.0, TOP + 44.0, BOSS_BAR_H)
	root.add_child(boss_value)
	weak_label = _label("Weak", 24, GOLD)
	_top_centre(weak_label, half, TOP + 80.0, 32.0)
	root.add_child(weak_label)


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
	end_panel.offset_left = -440.0
	end_panel.offset_right = 440.0
	end_panel.offset_top = -200.0
	end_panel.offset_bottom = 220.0
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
	if end_panel != null:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.035, 0.05, 0.92)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 30.0
		sb.content_margin_right = 30.0
		sb.content_margin_top = 18.0
		sb.content_margin_bottom = 18.0
		end_panel.add_theme_stylebox_override("panel", sb)


func _set_colour(l: Label, c: Color) -> void:
	if c != l.get_meta("colour"):
		l.set_meta("colour", c)
		HudSkin.style_label(l, "display", int(l.get_meta("px")), c)


func bind(m: BossMatch, pg: Node = null) -> void:
	match_node = m
	playground = pg
	var pairs := [["announce", _on_announce], ["phase_changed", _on_phase], ["match_over", _on_over],
		["boss_phase_changed", _on_boss_phase], ["boss_part_lost", _on_part_lost], ["wave", _on_wave]]
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
	hint.text = "%s\n%s    %s" % [tr("P1: WASD + Shift — бей в светящуюся деталь, уходи от рывков"), who,
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
	_toast_tw.tween_interval(1.8)
	_toast_tw.tween_property(toast_label, "modulate:a", 0.0, 0.3)
	_toast_tw.tween_callback(func() -> void: toast_label.visible = false)


## Имя куклы для HUD: P1 человека — ТЫ, босс — ТИТАН, остальные — P2.
func name_of(d: Doll) -> String:
	if d == null or not is_instance_valid(d):
		return "—"
	if d.is_in_group(BossMatch.BOSS_GROUP):
		return tr("ТИТАН")
	if d.player_index == 0 and not d.external_input:
		return tr("ТЫ")
	return BossMatch.doll_name(d)


static func colour_of(i: int) -> Color:
	return PLAYER_COLOURS[posmod(i, PLAYER_COLOURS.size())]


## Имя детали босса для игрока («ЛЕВОЕ ПЛЕЧО»); незнакомая — «ДЕТАЛЬ».
static func part_title(n: String) -> String:
	return TranslationServer.translate(String(PART_NAMES.get(n, "ДЕТАЛЬ")))


static func clock_text(seconds: float) -> String:
	var s := maxi(int(ceil(seconds)), 0)
	return "%d:%02d" % [s / 60, s % 60]


# --- сигналы ---

func _on_announce(text: String, color: Color, kind: String) -> void:
	if kind in ["countdown", "fight", "ko", "boss_phase", "boss_wave", "boss_down"]:
		announcer.announce(text, color, kind)


func _on_phase(p: int) -> void:
	if p == Match.Phase.COUNTDOWN:
		end_panel.visible = false
		_lag = 1.0


func _on_boss_phase(n: int) -> void:
	var col: Color = BossMatch.PHASE_COLOURS[clampi(n - 1, 0, 2)]
	flash.color = Color(col, 0.0)
	if _flash_tw != null and _flash_tw.is_valid():
		_flash_tw.kill()
	_flash_tw = flash.create_tween().set_ignore_time_scale(true)
	_flash_tw.tween_property(flash, "color:a", 0.45, 0.06)
	_flash_tw.tween_property(flash, "color:a", 0.0, 0.7)
	toast(tr("Титан рвётся рывками — уходи вбок от замаха") if n == 2 else tr("Ярость: быстрее, тяжелее поле, волна-толчок"))


func _on_part_lost(part_name: String, _by: Node) -> void:
	if part_name.begins_with("Head"):
		return
	toast(tr("ОТОРВАНО: %s") % part_title(part_name))


func _on_wave(hits: int) -> void:
	if hits > 0:
		flash.color = Color(BossMatch.PHASE_COLOURS[2], 0.25)
		var tw := flash.create_tween().set_ignore_time_scale(true)
		tw.tween_property(flash, "color:a", 0.0, 0.4)


func _on_over(_winner: Doll, results: Dictionary) -> void:
	var won := bool(results.get("players_won", false))
	if won:
		end_title.text = tr("ТИТАН ПОВЕРЖЕН!")
		end_title.set_meta("colour", GOLD)
	else:
		end_title.text = tr("ТИТАН ВЫСТОЯЛ")
		end_title.set_meta("colour", BossMatch.PHASE_COLOURS[2])
	var how := ""
	if won:
		how = tr("голова оторвана") if String(results.get("kill_kind", "")) == "head" else tr("запас 0")
	elif String(results.get("reason", "")) == "timeout":
		how = tr("время вышло")
	else:
		how = tr("все игроки выбиты")
	end_sub.text = tr("%s · время боя %s · фаза %d · деталей оторвано: %d") % [how, clock_text(float(results.get("match_time", 0.0))),
		int(results.get("boss_phase", 1)), (results.get("parts_lost", []) as Array).size()]
	for c in end_table.get_children():
		end_table.remove_child(c)
		c.queue_free()
	var white := Color(1, 1, 1, 0.75)
	var head := [tr("БОЕЦ"), tr("УРОН"), tr("В СЛАБОЕ"), tr("ДЕТАЛЕЙ"), tr("ВЫБИТ")]
	for i in head.size():
		_cell(head[i], white, i == 0)
	var tally: Dictionary = results.get("tally", {})
	for d in results.get("places", []):
		var dd := d as Doll
		if dd == null or not is_instance_valid(dd):
			continue
		var t: Dictionary = tally.get(dd.player_index, {})
		_cell(name_of(dd), colour_of(dd.player_index).lightened(0.3), true)
		_cell(str(int(round(float(t.get("dmg", 0.0))))), Color.WHITE, false)
		_cell(str(int(t.get("weak_hits", 0))), Color.WHITE, false)
		_cell(str(int(t.get("parts", 0))), Color.WHITE, false)
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


# --- полосы ---

## Полоса запаса босса: подложка, «хвост» недавнего урона, запас цветом фазы, засечки порогов фаз.
func _draw_boss_bar() -> void:
	var c := boss_bar
	var r := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(r, Color(0.03, 0.035, 0.05, 0.86))
	var k := match_node.boss_frac() if match_node != null else 1.0
	var ph := match_node.boss_phase if match_node != null else 1
	var col: Color = BossMatch.PHASE_COLOURS[clampi(ph - 1, 0, 2)]
	var inner := r.grow(-3.0)
	if _lag > k:
		c.draw_rect(Rect2(inner.position, Vector2(inner.size.x * _lag, inner.size.y)), Color(1, 1, 1, 0.75))
	c.draw_rect(Rect2(inner.position, Vector2(inner.size.x * k, inner.size.y)), col)
	for at in Tuning.BOSS_PHASE_AT:
		var x := inner.position.x + inner.size.x * float(at)
		c.draw_line(Vector2(x, r.position.y - 4.0), Vector2(x, r.end.y + 4.0), Color(1, 1, 1, 0.85), 3.0)
	c.draw_rect(r, Color(col, 0.9), false, 2.0)


func _ensure_row(d: Doll) -> Dictionary:
	var pi := d.player_index
	if rows.has(pi):
		return rows[pi]
	var box := VBoxContainer.new()
	box.name = "Row%d" % pi
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	var nm := _label("Name", 24, colour_of(pi).lightened(0.3))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var bar := Control.new()
	bar.name = "Bar"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size = Vector2(240.0, 12.0)
	bar.draw.connect(_draw_row_bar.bind(bar, pi))
	box.add_child(nm)
	box.add_child(bar)
	box.set_meta("pi", pi)
	var at := players_box.get_child_count()
	for i in players_box.get_child_count():
		if int(players_box.get_child(i).get_meta("pi", 0)) > pi:
			at = i
			break
	players_box.add_child(box)
	players_box.move_child(box, at)
	rows[pi] = {"box": box, "name": nm, "bar": bar}
	_apply_skin()
	return rows[pi]


func _player(pi: int) -> Doll:
	if match_node == null:
		return null
	for d in match_node.players():
		if (d as Doll).player_index == pi:
			return d
	return null


## Запас игрока и его жизни: полоса и кружки справа (полный — жизнь осталась).
func _draw_row_bar(c: Control, pi: int) -> void:
	var d := _player(pi)
	var k := 0.0
	if d != null and d.alive:
		k = clampf(d.hp / maxf(d.max_hp, 1.0), 0.0, 1.0)
	var col := colour_of(pi)
	var w := c.size.x - 70.0
	var r := Rect2(Vector2.ZERO, Vector2(w, c.size.y))
	c.draw_rect(r, Color(0.03, 0.035, 0.05, 0.86))
	c.draw_rect(Rect2(r.position + Vector2(2, 2), Vector2((w - 4.0) * k, c.size.y - 4.0)), col)
	var lives := int(match_node.lives.get(pi, 0)) if match_node != null else 0
	for i in Tuning.BOSS_LIVES:
		var cc := Vector2(w + 16.0 + i * 22.0, c.size.y * 0.5)
		if i < lives:
			c.draw_circle(cc, 7.0, col)
		else:
			c.draw_arc(cc, 7.0, 0.0, TAU, 20, Color(1, 1, 1, 0.5), 2.0)


func _update() -> void:
	if match_node == null:
		return
	for d in match_node.players():
		var dd := d as Doll
		var c := _ensure_row(dd)
		var out := not dd.alive and match_node.respawn_left(dd) < 0.0 and match_node.play_state == "play"
		(c["name"] as Label).text = (name_of(dd) + "  " + tr("ВЫБЫЛ")) if out else name_of(dd)
		(c["box"] as Control).modulate.a = 0.5 if out else 1.0
		(c["bar"] as Control).queue_redraw()
	var k := match_node.boss_frac()
	_lag = maxf(k, move_toward(_lag, k, 0.25 * get_process_delta_time() / maxf(Engine.time_scale, 0.02)))
	boss_bar.queue_redraw()
	var hp := match_node.boss.hp if is_instance_valid(match_node.boss) and match_node.boss.alive else 0.0
	boss_value.text = "%d / %d" % [int(ceil(hp)), int(Tuning.BOSS_HP)]
	phase_label.text = tr("ФАЗА %d/3") % match_node.boss_phase
	_set_colour(phase_label, BossMatch.PHASE_COLOURS[clampi(match_node.boss_phase - 1, 0, 2)])
	clock.text = clock_text(match_node.time_left_s())
	if match_node.play_state == "play" and match_node.weak_part != "":
		weak_label.text = tr("СЛАБОЕ МЕСТО: %s") % part_title(match_node.weak_part)
		weak_label.modulate.a = 0.65 + 0.35 * sin(_time * TAU * 1.6)
	else:
		weak_label.text = ""


# --- кадр ---

func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.02)
	_time += real
	if hint.visible and _time > HINT_S:
		hint.modulate.a = maxf(hint.modulate.a - real * 1.5, 0.0)
		hint.visible = hint.modulate.a > 0.0
	_update()
	marks.queue_redraw()


## Имена над игроками («ВОЗВРАТ N» у выбитых), кольцо вокруг слабой детали, телеграф волны.
func _draw_marks() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or match_node == null or end_panel.visible:
		return
	var font := HudSkin.font("display")
	if font == null:
		font = ThemeDB.fallback_font
	var vp := get_viewport().get_visible_rect().size
	var to_canvas := marks.get_global_transform_with_canvas().affine_inverse()
	for n in match_node.players():
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
		var col := colour_of(d.player_index).lightened(0.3)
		var txt := name_of(d)
		if not d.alive:
			var left := match_node.respawn_left(d)
			if left < 0.0:
				continue
			txt = tr("ВОЗВРАТ %d") % int(ceil(left))
			col = Color(1, 1, 1, 0.8)
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
		marks.draw_string_outline(font, sp + Vector2(-tw.x * 0.5, 0.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color(0, 0, 0, 0.9))
		marks.draw_string(font, sp + Vector2(-tw.x * 0.5, 0.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)
	if match_node.play_state != "play":
		return
	var wb := match_node.weak_body()
	if wb != null and is_instance_valid(wb) and not cam.is_position_behind(wb.global_position):
		var p := wb.global_position
		var c: Vector2 = to_canvas * cam.unproject_position(p)
		var e: Vector2 = to_canvas * cam.unproject_position(p + Vector3(0.7, 0.0, 0.0))
		var rad := maxf(c.distance_to(e), 14.0) * (1.0 + 0.12 * sin(_time * TAU * 1.6))
		marks.draw_arc(c, rad, 0.0, TAU, 40, Color(GOLD, 0.9), 4.0)
	var b := match_node.boss
	var wl := match_node.wave_warning_left()
	if wl >= 0.0 and is_instance_valid(b) and b.alive:
		var bc := b.centre_of_mass()
		if not cam.is_position_behind(bc):
			var c2: Vector2 = to_canvas * cam.unproject_position(bc)
			var e2: Vector2 = to_canvas * cam.unproject_position(bc + Vector3(Tuning.BOSS_WAVE_R, 0.0, 0.0))
			var full := c2.distance_to(e2)
			var k := clampf(wl / maxf(Tuning.BOSS_WAVE_WARN_S, 0.01), 0.0, 1.0)
			var red: Color = BossMatch.PHASE_COLOURS[2]
			marks.draw_arc(c2, full, 0.0, TAU, 64, Color(red, 0.5), 3.0)
			marks.draw_arc(c2, full * (1.0 - k), 0.0, TAU, 64, Color(red, 0.95), 6.0)
