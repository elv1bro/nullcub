## HUD «Стычки 3 на 3» (docs/plan-demo/SQUAD.md). Боевой HUD (scenes/ui/hud.gd) рассчитан на 2–4 панели игроков — шесть больших
## панелей закрыли бы карту, поэтому здесь свой, как в командных шутерах. Дерево строит сам, шрифты — по скину HUD (HudSkin):
##   • сверху по центру — счёт команд (синие слева, красные справа, цвет — Tuning.SQUAD_COLORS), между ними часы, под ними «ДО N»;
##   • справа сверху — лента выбываний «кто ▸ кого» цветами команд (FEED_MAX строк, гаснут через FEED_HOLD_S);
##   • над каждым живым бойцом — полоска HP цвета команды (под ней — броня) и имя (ТЫ, СИНИЙ 2, КРАСНЫЙ 1…); соперник за кадром —
##     стрелка у края экрана с метрами (от игрока); у игрока — луч прицела от ствола (куда уйдёт пуля), над попаданиями игрока —
##     цифры урона;
##   • слева снизу — HP, броня, оружие и патроны игрока («12 / 48»: магазин / запас; полоса — магазин, на перезарядке — её ход),
##     очки улучшения; подсказка клавиш первые HINT_S секунд;
##   • снизу по центру — улучшения, пока на них хватает очков: [1] [2] [3] — ветка из трёх, второй уровень, усиления (SquadMatch.offers);
##   • игрок выбыл — по центру «ВОЗВРАТ ЧЕРЕЗ N»; конец — табличка победителя со счётом и таблицей бойцов (фраги / выбывания),
##     «R — заново».
## Диктор (Announcer) — только отсчёт, FIGHT!, KO! игрока (его фраг), новое оружие и взятый ящик игрока; надписи ударов шести бойцов
## были бы шумом. Лента выбываний пишет и оружие добившего.
## bind(match) — подписка на SquadMatch по именам сигналов.
class_name SquadHud
extends CanvasLayer

const PLATE_W := 130.0
const PLATE_H := 86.0
const TIMER_W := 170.0
const TOP := 14.0
const FEED_MAX := 5
const FEED_HOLD_S := 6.0
const HINT_S := 9.0
const BAR_W := 64.0
const BAR_H := 7.0
const BAR_LIFT := 0.62           # м над головой
const ARROW_MARGIN := 46.0
const ARMOR_COLOUR := Color(0.55, 0.82, 1.0)
const DIGIT_S := 0.7              # цифра урона живёт столько реальных секунд и всплывает на DIGIT_RISE px
const DIGIT_RISE := 46.0
const AIM_DASH := 0.35            # м: штрих луча прицела
const SUPPLY_WORDS := {"ammo": "+ПАТРОНЫ", "health": "+ЖИЗНИ", "armor": "+БРОНЯ"}

var match_node: SquadMatch
var root: Control
var announcer: Announcer
var score_labels: Array = []
var timer_label: Label
var caption: Label
var feed: VBoxContainer
var marks: Control
var me_hp: ProgressBar
var me_armor: ProgressBar
var me_ammo: ProgressBar
var me_label: Label
var me_weapon: Label
var me_points: Label
var up_panel: PanelContainer
var up_title: Label
var up_cards: Array = []          # Label × 3
var hint: Label
var respawn_label: Label
var end_panel: PanelContainer
var end_title: Label
var end_score: Label
var end_table: GridContainer
var _plates: Array = []
var _feed_rows: Array = []       # [[Label, осталось с]]
var _digits: Array = []          # [[мировая точка, текст, осталось с]]
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
	_build_score()
	_build_feed()
	_build_me()
	_build_upgrades()
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
	respawn_label = _label("Respawn", 54, Color.WHITE)
	respawn_label.set_anchors_preset(Control.PRESET_CENTER)
	respawn_label.offset_left = -500.0
	respawn_label.offset_right = 500.0
	respawn_label.offset_top = 40.0
	respawn_label.offset_bottom = 120.0
	respawn_label.visible = false
	root.add_child(respawn_label)
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


func _build_score() -> void:
	for i in 2:
		var plate := PanelContainer.new()
		plate.name = "Score%d" % i
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.anchor_left = 0.5
		plate.anchor_right = 0.5
		var x0 := -TIMER_W * 0.5 - 10.0 - PLATE_W if i == 0 else TIMER_W * 0.5 + 10.0
		plate.offset_left = x0
		plate.offset_right = x0 + PLATE_W
		plate.offset_top = TOP
		plate.offset_bottom = TOP + PLATE_H
		plate.pivot_offset = Vector2(PLATE_W, PLATE_H) * 0.5
		var l := _label("Value", 70, Color.WHITE)
		l.text = "0"
		plate.add_child(l)
		root.add_child(plate)
		_plates.append(plate)
		score_labels.append(l)
	var tp := PanelContainer.new()
	tp.name = "Timer"
	tp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tp.anchor_left = 0.5
	tp.anchor_right = 0.5
	tp.offset_left = -TIMER_W * 0.5
	tp.offset_right = TIMER_W * 0.5
	tp.offset_top = TOP + 10.0
	tp.offset_bottom = TOP + PLATE_H - 10.0
	timer_label = _label("Time", 44, Color.WHITE)
	timer_label.text = "5:00"
	tp.add_child(timer_label)
	root.add_child(tp)
	_plates.append(tp)
	caption = _label("Caption", 24, Color(1, 1, 1, 0.85))
	caption.anchor_left = 0.5
	caption.anchor_right = 0.5
	caption.offset_left = -400.0
	caption.offset_right = 400.0
	caption.offset_top = TOP + PLATE_H + 4.0
	caption.offset_bottom = TOP + PLATE_H + 38.0
	root.add_child(caption)


func _build_feed() -> void:
	feed = VBoxContainer.new()
	feed.name = "Feed"
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed.anchor_left = 1.0
	feed.anchor_right = 1.0
	feed.offset_left = -520.0
	feed.offset_right = -24.0
	feed.offset_top = 20.0
	feed.offset_bottom = 320.0
	feed.add_theme_constant_override("separation", 4)
	root.add_child(feed)


func _build_me() -> void:
	var box := VBoxContainer.new()
	box.name = "Me"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 28.0
	box.offset_right = 448.0
	box.offset_top = -236.0
	box.offset_bottom = -24.0
	box.add_theme_constant_override("separation", 5)
	root.add_child(box)
	me_label = _label("Name", 26, Color.WHITE)
	me_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(me_label)
	me_hp = _bar(SquadMatch.team_colour(0).lightened(0.2))
	box.add_child(me_hp)
	me_armor = _bar(ARMOR_COLOUR)
	me_armor.custom_minimum_size.y = 9.0
	me_armor.max_value = Tuning.SQUAD_ARMOR_MAX
	box.add_child(me_armor)
	me_weapon = _label("Weapon", 30, Color(1.0, 0.92, 0.7))
	me_weapon.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(me_weapon)
	me_ammo = _bar(Color(1.0, 0.8, 0.3))
	me_ammo.custom_minimum_size.y = 12.0
	box.add_child(me_ammo)
	me_points = _label("Points", 20, Color(0.75, 1.0, 0.7))
	me_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(me_points)
	hint = _label("Hint", 22, Color(1, 1, 1, 0.8))
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -640.0
	hint.offset_right = 640.0
	hint.offset_top = -64.0
	hint.offset_bottom = -24.0
	hint.text = tr("WASD — лететь · ЛКМ — рука с оружием · I — огонь · O — перезарядка · 1 / 2 / 3 — улучшения · Shift — рывок")
	root.add_child(hint)


## Улучшения: снизу по центру, над подсказкой — заголовок с очками и до трёх карточек «[1] АВТОМАТ — очередь, магазин 30 · 1 очко».
func _build_upgrades() -> void:
	up_panel = PanelContainer.new()
	up_panel.name = "Upgrades"
	up_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	up_panel.anchor_left = 0.5
	up_panel.anchor_right = 0.5
	up_panel.anchor_top = 1.0
	up_panel.anchor_bottom = 1.0
	up_panel.offset_left = -470.0
	up_panel.offset_right = 470.0
	up_panel.offset_top = -78.0
	up_panel.offset_bottom = -78.0
	up_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN   # высота — по числу карточек, растёт вверх от подсказки
	up_panel.visible = false
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	up_panel.add_child(v)
	up_title = _label("Title", 24, Color(0.75, 1.0, 0.7))
	v.add_child(up_title)
	for k in 3:
		var l := _label("Card%d" % k, 24, Color.WHITE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(l)
		up_cards.append(l)
	root.add_child(up_panel)


func _bar(fill: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(380.0, 20.0)
	b.max_value = 100.0
	b.value = 100.0
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.035, 0.05, 0.8)
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(3)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	return b


func _build_end() -> void:
	end_panel = PanelContainer.new()
	end_panel.name = "End"
	end_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_panel.set_anchors_preset(Control.PRESET_CENTER)
	end_panel.offset_left = -380.0
	end_panel.offset_right = 380.0
	end_panel.offset_top = -170.0
	end_panel.offset_bottom = 250.0
	end_panel.visible = false
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 10)
	end_panel.add_child(v)
	end_title = _label("Title", 56, Color.WHITE)
	end_score = _label("Score", 44, Color.WHITE)
	end_table = GridContainer.new()
	end_table.name = "Table"
	end_table.columns = 4
	end_table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_table.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	end_table.add_theme_constant_override("h_separation", 34)
	end_table.add_theme_constant_override("v_separation", 2)
	var again := _label("Again", 22, Color(1, 1, 1, 0.7))
	again.text = tr("R — заново · Esc — пауза и выход в гараж")
	for l in [end_title, end_score, end_table, again]:
		v.add_child(l)
	root.add_child(end_panel)


func _apply_skin() -> void:
	for l in root.find_children("*", "Label", true, false):
		if (l as Node).has_meta("px"):
			HudSkin.style_label(l, "display", int(l.get_meta("px")), l.get_meta("colour"))
			(l as Label).add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			(l as Label).add_theme_constant_override("outline_size", 6)
	for i in _plates.size():
		var c := SquadMatch.team_colour(i).lightened(0.25) if i < 2 else Color(0.85, 0.85, 0.9)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.035, 0.05, 0.86)
		sb.border_color = c
		sb.border_width_bottom = 6 if i < 2 else 2
		sb.set_corner_radius_all(4)
		(_plates[i] as PanelContainer).add_theme_stylebox_override("panel", sb)
	if up_panel != null:
		var ub := StyleBoxFlat.new()
		ub.bg_color = Color(0.03, 0.05, 0.035, 0.82)
		ub.border_color = Color(0.55, 0.95, 0.5, 0.9)
		ub.border_width_top = 3
		ub.set_corner_radius_all(6)
		ub.content_margin_left = 22.0
		ub.content_margin_right = 22.0
		ub.content_margin_top = 8.0
		ub.content_margin_bottom = 8.0
		up_panel.add_theme_stylebox_override("panel", ub)
	if end_panel != null:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.035, 0.05, 0.92)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 30.0
		sb.content_margin_right = 30.0
		sb.content_margin_top = 18.0
		sb.content_margin_bottom = 18.0
		end_panel.add_theme_stylebox_override("panel", sb)


func bind(m: SquadMatch) -> void:
	match_node = m
	var pairs := [["score_changed", _on_score], ["frag", _on_frag], ["announce", _on_announce], ["time_left", _on_time],
		["match_over", _on_over], ["phase_changed", _on_phase], ["bullet_landed", _on_bullet], ["upgraded", _on_upgraded],
		["supply_taken", _on_supply]]
	for p in pairs:
		if m.has_signal(p[0]) and not m.is_connected(p[0], p[1]):
			m.connect(p[0], p[1])
	_on_score(m.score)
	caption.text = tr("СТЫЧКА 3 НА 3 · ДО %d") % m.score_to_win
	_on_time(m.time_left_s())


## Имя бойца для ленты и меток: человек — ТЫ, бот — цвет команды и номер в ней.
static func name_of(d: Object) -> String:
	if d == null or not is_instance_valid(d):
		return TranslationServer.translate("ПОЛИГОН")
	var dd := d as Doll
	if not dd.external_input:
		return TranslationServer.translate("ТЫ")
	var n := dd.player_index / 2 + 1
	return (TranslationServer.translate("СИНИЙ %d") if SquadMatch.team_of(dd) == 0 else TranslationServer.translate("КРАСНЫЙ %d")) % n


# --- сигналы ---

func _on_score(score: Array) -> void:
	for i in mini(score_labels.size(), score.size()):
		(score_labels[i] as Label).text = str(int(score[i]))


func _on_time(seconds: float) -> void:
	var s := int(ceil(maxf(seconds, 0.0)))
	timer_label.text = "%d:%02d" % [s / 60, s % 60]


func _on_frag(killer: Doll, victim: Doll, team: int) -> void:
	if team >= 0 and team < 2:
		var p := _plates[team] as Control
		var tw := p.create_tween().set_ignore_time_scale(true)
		tw.tween_property(p, "scale", Vector2(1.35, 1.35), 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var row := RichTextLabel.new()
	row.bbcode_enabled = true
	row.fit_content = true
	row.scroll_active = false
	row.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(496.0, 0.0)
	row.add_theme_font_size_override("normal_font_size", 24)
	row.add_theme_font_override("normal_font", HudSkin.font("display"))
	row.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	row.add_theme_constant_override("outline_size", 6)
	var vc := SquadMatch.team_colour(SquadMatch.team_of(victim)).lightened(0.35).to_html(false)
	var vname := name_of(victim)
	if killer != null:
		var kc := SquadMatch.team_colour(SquadMatch.team_of(killer)).lightened(0.35).to_html(false)
		var g := SquadMatch.gun_of(killer)
		var wn := tr(String(Tuning.SQUAD_WEAPONS[g.weapon]["title"])) if g != null and g.weapon != "" else "▸"
		row.text = "[right][color=#%s]%s[/color]  [color=#c8c8c8]%s[/color]  [color=#%s]%s[/color][/right]" % [kc, name_of(killer), wn, vc, vname]
	else:
		row.text = "[right][color=#%s]%s[/color]  %s[/right]" % [vc, vname, tr("выбыл")]
	feed.add_child(row)
	_feed_rows.append([row, FEED_HOLD_S])
	while _feed_rows.size() > FEED_MAX:
		var old: Array = _feed_rows.pop_front()
		(old[0] as Node).queue_free()
	if killer != null and not killer.external_input:
		announcer.announce(tr("KO!"), Color(1.0, 0.85, 0.3), "ko")


## Попадание пули: у пуль игрока — цифра урона над точкой попадания.
func _on_bullet(_victim: Doll, shooter: Doll, damage: float, pos: Vector3) -> void:
	if shooter == null or shooter != _human():
		return
	_digits.append([pos, str(int(round(damage))), DIGIT_S])
	if _digits.size() > 24:
		_digits.pop_front()


func _on_upgraded(pi: int, offer: Dictionary) -> void:
	var me := _human()
	if me != null and me.player_index == pi:
		announcer.announce(tr(String(offer.get("title", ""))), Color(0.6, 1.0, 0.55), "event")


func _on_supply(d: Doll, kind: String) -> void:
	if d != null and d == _human():
		announcer.announce(tr(String(SUPPLY_WORDS.get(kind, ""))), SupplyCrate.COLOURS.get(kind, Color.WHITE), "event")


func _on_announce(text: String, color: Color, kind: String) -> void:
	if kind in ["countdown", "fight"]:
		announcer.announce(text, color, kind)


func _on_phase(p: int) -> void:
	if p == Match.Phase.COUNTDOWN:
		end_panel.visible = false
		hint.visible = true
		hint.modulate.a = 1.0
		_clock = 0.0
		for r in _feed_rows:
			(r[0] as Node).queue_free()
		_feed_rows.clear()
		_digits.clear()


func _on_over(_winner: Doll, results: Dictionary) -> void:
	var wt := int(results.get("winner_team", -1))
	if wt < 0:
		end_title.text = tr("НИЧЬЯ")
		end_title.set_meta("colour", Color.WHITE)
	else:
		end_title.text = tr("ПОБЕДА СИНИХ") if wt == 0 else tr("ПОБЕДА КРАСНЫХ")
		end_title.set_meta("colour", SquadMatch.team_colour(wt).lightened(0.35))
	var sc: Array = results.get("score", [0, 0])
	end_score.text = "%d : %d" % [int(sc[0]), int(sc[1])]
	for c in end_table.get_children():
		end_table.remove_child(c)
		c.queue_free()
	var white := Color(1, 1, 1, 0.75)
	for h in [tr("БОЕЦ"), tr("ФРАГИ"), tr("ВЫБЫЛ"), tr("УРОН")]:
		_cell(h, white, end_table.get_child_count() == 0)
	var tally: Dictionary = results.get("tally", {})
	var dolls: Array = match_node.dolls() if match_node != null else []
	dolls.sort_custom(func(a: Doll, b: Doll) -> bool:
		if SquadMatch.team_of(a) != SquadMatch.team_of(b):
			return SquadMatch.team_of(a) < SquadMatch.team_of(b)
		return a.player_index < b.player_index)
	for d in dolls:
		var t: Dictionary = tally.get((d as Doll).player_index, {})
		var c := SquadMatch.team_colour(SquadMatch.team_of(d)).lightened(0.4)
		_cell(name_of(d), c, true)
		_cell(str(int(t.get("kills", 0))), Color.WHITE, false)
		_cell(str(int(t.get("deaths", 0))), Color.WHITE, false)
		_cell(str(int(round(float(t.get("damage", 0.0))))), Color.WHITE, false)
	_apply_skin()
	end_panel.visible = true
	end_panel.modulate.a = 0.0
	var tw := end_panel.create_tween().set_ignore_time_scale(true)
	tw.tween_interval(0.6)
	tw.tween_property(end_panel, "modulate:a", 1.0, 0.3)


## Клетка таблицы итогов: имя — влево, числа — по центру колонки.
func _cell(text: String, c: Color, left: bool) -> void:
	var l := _label("Cell", 22, c)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_CENTER
	end_table.add_child(l)


# --- кадр ---

func _human() -> Doll:
	return match_node.me() if match_node != null else null


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.02)
	_clock += real
	if hint.visible and _clock > HINT_S:
		hint.modulate.a = maxf(hint.modulate.a - real * 1.5, 0.0)
		hint.visible = hint.modulate.a > 0.0
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
	var me := _human()
	respawn_label.visible = false
	if me != null:
		me_label.text = "%s · %s" % [name_of(me), tr("СИНИЕ") if SquadMatch.team_of(me) == 0 else tr("КРАСНЫЕ")]
		me_hp.max_value = me.max_hp
		me_hp.value = me.hp if me.alive else 0.0
		me_armor.value = match_node.armor_of(me) if me.alive else 0.0
		var g := SquadMatch.gun_of(me)
		if g != null and g.weapon != "":
			var wt := tr(String(Tuning.SQUAD_WEAPONS[g.weapon]["title"]))
			var rp := g.reload_progress()
			if g.out_of_ammo():
				me_weapon.text = "%s   %s" % [wt, tr("ПАТРОНОВ НЕТ — РУКОПАШНАЯ")]
			elif rp >= 0.0:
				me_weapon.text = "%s   %s" % [wt, tr("ПЕРЕЗАРЯДКА")]
			else:
				me_weapon.text = "%s   %d / %d" % [wt, g.mag, g.reserve]
			me_ammo.max_value = 1.0
			me_ammo.value = rp if rp >= 0.0 else float(g.mag) / maxf(float(g.mag_max), 1.0)
			me_ammo.modulate = Color(1, 1, 1, 0.55) if rp >= 0.0 else Color.WHITE
		var lo := match_node.loadout(me.player_index)
		me_points.text = tr("ОЧКИ УЛУЧШЕНИЯ: %d") % int(lo["points"])
		_update_upgrades(me)
		if not me.alive and match_node != null and match_node.play_state == "play":
			var left := match_node.respawn_left(me)
			if left >= 0.0:
				respawn_label.text = tr("ВОЗВРАТ ЧЕРЕЗ %d") % int(ceil(left))
				respawn_label.visible = true
	else:
		up_panel.visible = false
	var j := 0
	while j < _digits.size():
		_digits[j][2] = float(_digits[j][2]) - real
		if float(_digits[j][2]) <= 0.0:
			_digits.remove_at(j)
		else:
			j += 1
	marks.queue_redraw()


## Карточки улучшений: видны, пока на что-то хватает очков; карточка, на которую очков мало, — бледная.
func _update_upgrades(me: Doll) -> void:
	var pi := me.player_index
	var show := match_node.play_state != "over" and match_node.can_upgrade(pi)
	up_panel.visible = show
	if not show:
		return
	var pts := int(match_node.loadout(pi)["points"])
	var of := match_node.offers(pi)
	up_title.text = tr("УЛУЧШЕНИЕ · ОЧКОВ: %d · ЖМИ 1 / 2 / 3") % pts
	for k in up_cards.size():
		var l := up_cards[k] as Label
		l.visible = k < of.size()
		if not l.visible:
			continue
		var o: Dictionary = of[k]
		l.text = tr("[%d]  %s — %s · очков: %d") % [k + 1, tr(String(o["title"])), tr(String(o["note"])), int(o["cost"])]
		l.modulate = Color.WHITE if pts >= int(o["cost"]) else Color(1, 1, 1, 0.4)


## Полоски HP и имена над бойцами, стрелки к соперникам за кадром.
func _draw_marks() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or match_node == null or end_panel.visible:
		return   # итоги: метки бойцов просвечивали бы сквозь табличку
	var font := HudSkin.font("display")
	if font == null:
		font = ThemeDB.fallback_font
	var vp := get_viewport().get_visible_rect().size
	var to_canvas := marks.get_global_transform_with_canvas().affine_inverse()
	var me := _human()
	var my_team := SquadMatch.team_of(me) if me != null else 0
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
		var t := SquadMatch.team_of(d)
		var c := SquadMatch.team_colour(t).lightened(0.3)
		var inside := sp.x > 0.0 and sp.y > 0.0 and sp.x < vp.x and sp.y < vp.y
		if not inside:
			if t != my_team and me != null:
				_arrow(sp, vp, c, me, d, font)
			continue
		var r := Rect2(sp - Vector2(BAR_W * 0.5, BAR_H * 0.5), Vector2(BAR_W, BAR_H))
		marks.draw_rect(r.grow(2.0), Color(0.03, 0.03, 0.04, 0.85))
		marks.draw_rect(Rect2(r.position, Vector2(BAR_W * clampf(d.hp / maxf(d.max_hp, 1.0), 0.0, 1.0), BAR_H)), c)
		var ar := match_node.armor_of(d)
		if ar > 0.0:
			var a_r := Rect2(r.position + Vector2(0.0, BAR_H + 3.0), Vector2(BAR_W * clampf(ar / Tuning.SQUAD_ARMOR_MAX, 0.0, 1.0), 3.0))
			marks.draw_rect(a_r.grow(1.0), Color(0.03, 0.03, 0.04, 0.85))
			marks.draw_rect(a_r, ARMOR_COLOUR)
		var txt := name_of(d)
		var fs := 20 if d != me else 22
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var pos := sp + Vector2(-tw.x * 0.5, -10.0)
		marks.draw_string_outline(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.9))
		marks.draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE if d == me else c)
	if me != null and me.alive:
		_draw_aim(cam, to_canvas, me)
	for e in _digits:
		var wp := e[0] as Vector3
		if cam.is_position_behind(wp):
			continue
		var k2 := clampf(float(e[2]) / DIGIT_S, 0.0, 1.0)
		var dp: Vector2 = to_canvas * cam.unproject_position(wp) + Vector2(0.0, -DIGIT_RISE * (1.0 - k2))
		var txt2 := String(e[1])
		var tw2 := font.get_string_size(txt2, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
		var col := Color(1.0, 0.95, 0.6, k2)
		marks.draw_string_outline(font, dp - Vector2(tw2.x * 0.5, 0.0), txt2, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 6, Color(0, 0, 0, 0.9 * k2))
		marks.draw_string(font, dp - Vector2(tw2.x * 0.5, 0.0), txt2, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, col)


## Луч прицела игрока: штрихи от дула по стволу на дальность оружия — куда уйдёт пуля (ствол смотрит по руке).
func _draw_aim(cam: Camera3D, to_canvas: Transform2D, me: Doll) -> void:
	var g := SquadMatch.gun_of(me)
	if g == null or g.def.is_empty():
		return
	var ray := g.aim_ray()
	if ray.is_empty():
		return
	var o := ray[0] as Vector3
	var dir := ray[1] as Vector3
	var reach := float(g.def["range"])
	var n := int(reach / (AIM_DASH * 2.0))
	var col := Color(1.0, 1.0, 1.0, 0.45) if g.mag > 0 and g.reloading <= 0.0 else Color(1.0, 0.4, 0.3, 0.35)
	for k in n:
		var a3 := o + dir * (float(k) * AIM_DASH * 2.0)
		var b3 := a3 + dir * AIM_DASH
		if cam.is_position_behind(a3) or cam.is_position_behind(b3):
			continue
		var fade := 1.0 - float(k) / float(maxi(n, 1))
		marks.draw_line(to_canvas * cam.unproject_position(a3), to_canvas * cam.unproject_position(b3),
			Color(col.r, col.g, col.b, col.a * fade), 2.0)


func _arrow(sp: Vector2, vp: Vector2, c: Color, me: Doll, d: Doll, font: Font) -> void:
	var centre := vp * 0.5
	var dir := (sp - centre)
	if dir.length() < 1.0:
		return
	dir = dir.normalized()
	var half := centre - Vector2(ARROW_MARGIN, ARROW_MARGIN)
	var k := minf(half.x / maxf(absf(dir.x), 1e-4), half.y / maxf(absf(dir.y), 1e-4))
	var p := centre + dir * k
	if p.x > vp.x - 160.0 and absf(p.y - centre.y) < 36.0:
		p.y += 48.0 * (1.0 if p.y >= centre.y else -1.0)   # справа посередине — подсказка «L — клавиши» (HitJuice): стрелка мимо неё
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([p + dir * 18.0, p - dir * 10.0 + side * 12.0, p - dir * 10.0 - side * 12.0])
	marks.draw_colored_polygon(pts, c)
	marks.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.8), 2.0)
	var m := me.centre_of_mass().distance_to(d.centre_of_mass())
	var txt := tr("%d м") % int(round(m))
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	var tp := p - dir * 34.0 + Vector2(-tw.x * 0.5, 6.0)
	marks.draw_string_outline(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0, 0, 0, 0.9))
	marks.draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, c)
