## Экран «ВЫБОР БОЙЦА» перед боем (docs/plan-demo/FIGHTER_SELECT.md). Открывается поверх того, кто запускает бой: гараж (БЫСТРЫЙ БОЙ),
## «ВСЕ РЕЖИМЫ» (дуэльные арены), «РЕЖИМЫ» реестра, «Испытание». Данные — FighterPick (ростер, «Мой боец», кубик), сборка по ответам —
## QuickBuild. Экран только выбирает: чертёж уходит в бой через ModeRun.launch(opts.player_blueprint) у хозяина экрана.
##   слева — карточки: МОЙ БОЕЦ («Обычный» — кукла режима, автосейв и сохранённые сборки, прошлая быстрая сборка, КУБИК, БЫСТРАЯ СБОРКА)
##           и готовые бойцы по группам (кит, лига, про-лига, Аоэлюн, наборы, шаблоны); портреты — DollPortrait (без окна — заглушка);
##   справа  — выбранный: портрет, масса, энергия, детали, запас ❤, на чём ЛКМ; кнопки В БОЙ и В МАСТЕРСКУЮ;
##   БЫСТРАЯ СБОРКА — вместо карточек три вопроса (стиль, чем бить, особенность) → сборка сразу в превью; ЕЩЁ ВАРИАНТ — те же ответы,
##           другой вариант.
## Клавиши: стрелки / WASD-геймпад ui_* — выбор, Enter — В БОЙ, R — кубик, Q — быстрая сборка, M — в мастерскую, Esc — назад
## (из конструктора — к карточкам). В конструкторе ↑↓ — вопрос, ←→ или 1–4 — ответ, N — ещё вариант. Мышь: клик — выбрать,
## клик по выбранной — в бой.
## Сигналы: chosen(bp) — null значит «Обычный» (кукла режима без подмены); cancelled; workshop_requested(bp) — открыть мастерскую
## (bp — что положить на стенд, null — как есть).
class_name FighterSelect
extends Control

signal chosen(bp: BodyBlueprint)
signal cancelled
signal workshop_requested(bp: BodyBlueprint)

const W := 1920.0
const H := 1080.0
const COLS := 5
const CARD := Vector2(208, 258)
const GAP := 12.0
const GRID_X := 64.0
const TOP := 168.0
const BOTTOM := 1000.0
const GRID_W := 1120.0
const DETAIL_X := 1236.0
const DETAIL_W := 620.0
const MAX_SAVED := 9
const QUESTIONS := [["style", "СТИЛЬ", "STYLE"], ["hitter", "ЧЕМ БИТЬ", "HITTER"], ["special", "ОСОБЕННОСТЬ", "SPECIAL"]]

## Настройки (до add_child, или через open_over).
var mode_title := ""
var allow_default := true          # карточка «Обычный» (кукла режима); «Испытанию» не нужна — там всегда сборка
var include_saved := true          # «Мой боец» из user://blueprints (проба вёрстки выключает: на каждой машине свой набор)
var dry_run := false               # проба: портреты не рендерить

var cards: Array = []              # [{kind, id, title, sub, bp, key, node, pic, ph, section}]
var sections: Array = []           # [{title, start, count}]
var sel := 0
var builder_open := false
var answers := QuickBuild.default_answers()
var quick: Dictionary = {}         # последний QuickBuild.generate (+ answers, seed)
var q_row := 0
var portraits: DollPortrait

var _rng := RandomNumberGenerator.new()
var _variant := 0
var _seed_base := 0
var _sb := {}
var _scroll: ScrollContainer
var _grid_box: VBoxContainer
var _builder: Control
var _q_buttons: Array = []         # [[Button…] по вопросам]
var _q_labels: Array = []
var _answers_l: Label
var _d_pic: TextureRect
var _d_ph: Label
var _d_title: Label
var _d_group: Label
var _d_stats: VBoxContainer
var _d_note: Label
var _d_key := ""
var _fight_b: Button
var _ws_b: Button
var _dice_b: Button
var _quick_b: Button
var _back_b: Button
var _hint_l: Label
var _closed := false


## Открыть экран поверх host (свой CanvasLayer поверх всего, что у хозяина). opts: title, allow_default, include_saved, dry_run.
static func open_over(host: Node, opts: Dictionary = {}) -> FighterSelect:
	var layer := CanvasLayer.new()
	layer.name = "FighterSelectLayer"
	layer.layer = 60
	var fs := FighterSelect.new()
	fs.name = "FighterSelect"
	fs.mode_title = String(opts.get("title", ""))
	fs.allow_default = bool(opts.get("allow_default", true))
	fs.include_saved = bool(opts.get("include_saved", true))
	fs.dry_run = bool(opts.get("dry_run", false))
	layer.add_child(fs)
	host.add_child(layer)
	return fs


## Убрать экран (вместе со своим CanvasLayer).
func close() -> void:
	if _closed:
		return
	_closed = true
	var p := get_parent()
	if p is CanvasLayer and p.name == "FighterSelectLayer":
		p.queue_free()
	else:
		queue_free()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # не set_anchors_preset: тот сохраняет нулевой размер
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rng.randomize()
	_seed_base = _rng.randi()
	portraits = DollPortrait.new()
	portraits.name = "Portraits"
	add_child(portraits)
	portraits.portrait_ready.connect(_on_portrait)
	_make_styles()
	_build()
	_fill_cards()
	var pre := _preselect()
	select(pre, true)


# ------------------------------------------------------------------ данные

func _fill_cards() -> void:
	cards.clear()
	sections.clear()
	var mine: Array = []
	if allow_default:
		mine.append({"kind": "default", "id": "default", "title": tr("Обычный"), "sub": tr("кукла режима"), "bp": null})
	if include_saved:
		var n := 0
		for e in FighterPick.my_builds():
			if not bool(e["auto"]) and n >= MAX_SAVED:
				continue
			if not bool(e["auto"]):
				n += 1
			mine.append({"kind": "saved", "id": String(e["id"]), "title": String(e["title"]),
				"sub": tr("автосейв мастерской") if bool(e["auto"]) else tr("сохранённая сборка"), "bp": e["bp"]})
	var last_bp: Variant = FighterPick.last.get("bp", null)
	if String(FighterPick.last.get("kind", "")) in ["quick", "dice"] and last_bp is BodyBlueprint:
		mine.append({"kind": "last", "id": "last", "title": tr("Прошлая сборка"), "sub": String(FighterPick.last.get("line", "")), "bp": last_bp})
	mine.append({"kind": "dice", "id": "dice", "title": tr("Кубик"), "sub": tr("случайная сборка"), "bp": null})
	mine.append({"kind": "builder", "id": "builder", "title": tr("Быстрая сборка"), "sub": tr("три вопроса"), "bp": null})
	_add_section(tr("МОЙ БОЕЦ"), mine)
	var groups := {}
	var order: Array = []
	for r in FighterPick.roster():
		var g := String(r["group"])
		if not groups.has(g):
			groups[g] = []
			order.append(g)
		(groups[g] as Array).append({"kind": "preset", "id": String(r["id"]), "title": tr(String(r["title"])), "sub": "", "bp": r["bp"]})
	for g in order:
		_add_section(tr(String(g)), groups[g])


func _add_section(title: String, items: Array) -> void:
	if items.is_empty():
		return
	var sec := {"title": title, "start": cards.size(), "count": items.size()}
	sections.append(sec)
	var head := _label(title, ShowTokens.title(650), 26, ShowTokens.AMBER)
	head.custom_minimum_size = Vector2(GRID_W - 20, 40)
	_grid_box.add_child(head)
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", int(GAP))
	grid.add_theme_constant_override("v_separation", int(GAP))
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	_grid_box.add_child(grid)
	for it in items:
		var c: Dictionary = it
		c["section"] = sections.size() - 1
		var i := cards.size()
		c["key"] = "fs:%s:%s" % [String(c["kind"]), String(c["id"])]
		if c["bp"] != null and String(c["sub"]) == "":
			c["sub"] = "%.0f %s · %d %s" % [(c["bp"] as BodyBlueprint).total_mass(), tr("кг"), (c["bp"] as BodyBlueprint).nodes.size(), tr("дет.")]
		cards.append(c)
		grid.add_child(_make_card(c, i))


func _preselect() -> int:
	var want_kind := String(FighterPick.last.get("kind", ""))
	var want_id := String(FighterPick.last.get("id", ""))
	if want_kind in ["quick", "dice"]:
		want_kind = "last"
		want_id = "last"
	for i in cards.size():
		if String(cards[i]["kind"]) == want_kind and String(cards[i]["id"]) == want_id:
			return i
	return 0


## Чертёж выбранной карточки (null — «Обычный» или служебная карточка без сборки).
func current_bp() -> BodyBlueprint:
	if builder_open:
		return quick.get("bp", null) as BodyBlueprint
	if sel < 0 or sel >= cards.size():
		return null
	return cards[sel]["bp"] as BodyBlueprint


func index_of(kind: String, id := "") -> int:
	for i in cards.size():
		if String(cards[i]["kind"]) == kind and (id == "" or String(cards[i]["id"]) == id):
			return i
	return -1


# ------------------------------------------------------------------ действия

func select(i: int, instant := false) -> void:
	if cards.is_empty():
		return
	sel = clampi(i, 0, cards.size() - 1)
	_style_cards()
	if String(cards[sel]["kind"]) == "dice" and cards[sel]["bp"] == null:
		_roll_into_dice()
	_show_detail(cards[sel]["bp"] as BodyBlueprint, String(cards[sel]["key"]), String(cards[sel]["title"]),
		_card_group(sel), _card_note(sel))
	var node := cards[sel]["node"] as Control
	if node != null and _scroll != null and not instant:
		_scroll.ensure_control_visible(node)
	elif node != null and _scroll != null:
		_scroll.call_deferred("ensure_control_visible", node)


## В БОЙ: выбранная карточка (или сборка конструктора). «Быстрая сборка» — открыть конструктор, не в бой.
func confirm() -> void:
	if _closed:
		return
	if builder_open:
		var bp := quick.get("bp", null) as BodyBlueprint
		if bp == null:
			return
		FighterPick.last = {"kind": "quick", "id": "quick", "bp": bp, "line": QuickBuild.answers_line(answers)}
		chosen.emit(bp)
		return
	var c: Dictionary = cards[sel]
	match String(c["kind"]):
		"builder":
			open_builder()
			return
		"dice":
			if c["bp"] == null:
				_roll_into_dice()
			FighterPick.last = {"kind": "dice", "id": "dice", "bp": c["bp"], "line": String(c["sub"])}
		"last":
			FighterPick.last = {"kind": String(FighterPick.last.get("kind", "quick")), "id": "last", "bp": c["bp"], "line": String(c["sub"])}
		_:
			FighterPick.last = {"kind": String(c["kind"]), "id": String(c["id"])}
	chosen.emit(c["bp"] as BodyBlueprint)


func cancel() -> void:
	if builder_open:
		close_builder()
		return
	cancelled.emit()


func to_workshop() -> void:
	workshop_requested.emit(current_bp())


## Кубик: новая случайная сборка в карточку «Кубик», она же выбрана.
func roll_dice() -> void:
	if builder_open:
		var ans := {}
		for q in QUESTIONS:
			var opts := _options(String(q[0]))
			ans[String(q[0])] = opts[_rng.randi_range(0, opts.size() - 1)]
		answers = ans
		reroll()
		return
	var i := index_of("dice")
	if i < 0:
		return
	cards[i]["bp"] = null
	select(i)


func _roll_into_dice() -> void:
	var i := index_of("dice")
	if i < 0:
		return
	var r := FighterPick.roll(_rng)
	var bp := r.get("bp", null) as BodyBlueprint
	cards[i]["bp"] = bp
	_variant += 1
	cards[i]["key"] = "fs:dice:%d" % _variant
	cards[i]["sub"] = QuickBuild.answers_line(r.get("answers", {}))
	_set_card_text(i)
	_request_card_pic(i)


func open_builder() -> void:
	builder_open = true
	_scroll.visible = false
	_builder.visible = true
	q_row = 0
	if quick.is_empty():
		reroll()
	else:
		_show_quick()
	_style_questions()
	_update_hint()


func close_builder() -> void:
	builder_open = false
	_scroll.visible = true
	_builder.visible = false
	_update_hint()
	select(sel, true)


func set_answer(q: String, v: String) -> void:
	if not _options(q).has(v):
		return
	answers[q] = v
	reroll()


## Ещё вариант: те же ответы, следующий seed.
func reroll() -> void:
	_variant += 1
	var seed_v := _seed_base + _variant
	quick = QuickBuild.generate(answers, seed_v)
	quick["answers"] = answers.duplicate()
	quick["seed"] = seed_v
	_show_quick()
	_style_questions()


func _show_quick() -> void:
	var bp := quick.get("bp", null) as BodyBlueprint
	_answers_l.text = QuickBuild.answers_line(answers)
	_show_detail(bp, "fs:quick:%d" % _variant, tr("Быстрая сборка"), QuickBuild.answers_line(answers),
		tr("Вариант %d. Не то — «Ещё вариант» или другой ответ.") % _variant)


static func _options(q: String) -> Array:
	match q:
		"style":
			return QuickBuild.STYLES
		"hitter":
			return QuickBuild.HITTERS
		_:
			return QuickBuild.SPECIALS


static func _opt_title(q: String, v: String) -> String:
	match q:
		"style":
			return String(QuickBuild.STYLE_TITLES.get(v, v))
		"hitter":
			return String(QuickBuild.HITTER_TITLES.get(v, v))
		_:
			return String(QuickBuild.SPECIAL_TITLES.get(v, v))


static func _opt_hint(q: String, v: String) -> String:
	match q:
		"style":
			return String(QuickBuild.STYLE_HINTS.get(v, ""))
		"hitter":
			return String(QuickBuild.HITTER_HINTS.get(v, ""))
		_:
			return String(QuickBuild.SPECIAL_HINTS.get(v, ""))


# ------------------------------------------------------------------ ввод

func _unhandled_input(e: InputEvent) -> void:
	if _closed or (Loading.showing and not dry_run):
		return
	var k := e as InputEventKey
	var key := k.physical_keycode if k != null and k.pressed and not k.echo else KEY_NONE
	if e.is_action_pressed("ui_cancel") or key == KEY_ESCAPE:
		cancel()
	elif e.is_action_pressed("ui_accept") or key == KEY_ENTER or key == KEY_KP_ENTER:
		confirm()
	elif key == KEY_R:
		roll_dice()
	elif key == KEY_Q and not builder_open:
		open_builder()
	elif key == KEY_M:
		to_workshop()
	elif builder_open:
		if not _builder_input(e, key):
			return
	elif e.is_action_pressed("ui_right", true):
		select(sel + 1)
	elif e.is_action_pressed("ui_left", true):
		select(sel - 1)
	elif e.is_action_pressed("ui_down", true):
		select(_step_row(sel, 1))
	elif e.is_action_pressed("ui_up", true):
		select(_step_row(sel, -1))
	else:
		return
	get_viewport().set_input_as_handled()


func _builder_input(e: InputEvent, key: int) -> bool:
	var q := String(QUESTIONS[q_row][0])
	var opts := _options(q)
	var cur := opts.find(String(answers.get(q, opts[0])))
	if e.is_action_pressed("ui_down", true):
		q_row = (q_row + 1) % QUESTIONS.size()
		_style_questions()
	elif e.is_action_pressed("ui_up", true):
		q_row = (q_row + QUESTIONS.size() - 1) % QUESTIONS.size()
		_style_questions()
	elif e.is_action_pressed("ui_right", true):
		set_answer(q, String(opts[(cur + 1) % opts.size()]))
	elif e.is_action_pressed("ui_left", true):
		set_answer(q, String(opts[(cur + opts.size() - 1) % opts.size()]))
	elif key == KEY_N:
		reroll()
	elif key >= KEY_1 and key < KEY_1 + opts.size():
		set_answer(q, String(opts[key - KEY_1]))
	else:
		return false
	return true


## Шаг по строкам сетки с переходом между разделами (колонка сохраняется, сколько можно).
func _step_row(i: int, d: int) -> int:
	var s := int(cards[i]["section"])
	var sec: Dictionary = sections[s]
	var start := int(sec["start"])
	var count := int(sec["count"])
	var col := (i - start) % COLS
	if d > 0:
		if i + COLS < start + count:
			return i + COLS
		var rows := (count - 1) / COLS
		if (i - start) / COLS < rows:
			return start + count - 1
		if s + 1 < sections.size():
			var nx: Dictionary = sections[s + 1]
			return int(nx["start"]) + mini(col, int(nx["count"]) - 1)
		return i
	if i - COLS >= start:
		return i - COLS
	if s > 0:
		var pv: Dictionary = sections[s - 1]
		var pstart := int(pv["start"])
		var pcount := int(pv["count"])
		var last_row := (pcount - 1) / COLS
		return pstart + mini(last_row * COLS + col, pcount - 1)
	return i


func _on_card_click(i: int) -> void:
	if builder_open:
		return
	if i == sel:
		confirm()
	else:
		select(i, true)


# ------------------------------------------------------------------ портреты

func _request_card_pic(i: int) -> void:
	var c: Dictionary = cards[i]
	if dry_run or c["bp"] == null or c.get("pic", null) == null:
		return
	var tex := portraits.request(String(c["key"]), c["bp"] as BodyBlueprint)
	if tex != null:
		_set_card_pic(i, tex)


func _set_card_pic(i: int, tex: Texture2D) -> void:
	var pic := cards[i]["pic"] as TextureRect
	pic.texture = tex
	(cards[i]["ph"] as Label).visible = tex == null


func _on_portrait(key: String, tex: Texture2D) -> void:
	for i in cards.size():
		if String(cards[i]["key"]) == key:
			_set_card_pic(i, tex)
	if key == _d_key:
		_d_pic.texture = tex
		_d_ph.visible = false


# ------------------------------------------------------------------ вид

func _show_detail(bp: BodyBlueprint, key: String, title: String, group: String, note: String) -> void:
	_d_key = key
	_d_title.text = title
	_d_group.text = group
	_d_note.text = note
	for c in _d_stats.get_children():
		_d_stats.remove_child(c)
		c.queue_free()
	_d_pic.texture = null
	_d_ph.visible = true
	_d_ph.text = _initials(title) if bp != null else "N0"
	if bp != null:
		_stat(tr("МАССА"), tr("%.1f кг") % bp.total_mass())
		_stat(tr("ЭНЕРГИЯ"), "%d / %d" % [bp.energy_used(), bp.energy_cap()])
		_stat(tr("ДЕТАЛЕЙ"), str(bp.nodes.size()))
		if PartHp.on:
			_stat(tr("ЗАПАС ❤"), str(bp.parts_hp_total()))
		_stat(tr("ЛКМ"), _part_title(bp, String(bp.control[0]) if bp.control.size() > 0 else ""))
		if not dry_run:
			var tex := portraits.request(key, bp)
			if tex != null:
				_d_pic.texture = tex
				_d_ph.visible = false
	_fight_b.disabled = builder_open and bp == null
	_fight_b.text = tr("БЫСТРАЯ СБОРКА  ▸") if not builder_open and sel < cards.size() and String(cards[sel]["kind"]) == "builder" else tr("В БОЙ  (Enter)")


func _stat(caption: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	var c := _label(caption, ShowTokens.title(600), 18, ShowTokens.MUTED)
	c.custom_minimum_size = Vector2(110, 0)
	row.add_child(c)
	var v := _label(value, ShowTokens.text(600), 22, ShowTokens.TEXT)
	v.custom_minimum_size = Vector2(150, 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.clip_text = true
	row.add_child(v)
	_d_stats.add_child(row)


func _part_title(bp: BodyBlueprint, uid: String) -> String:
	if uid == "":
		return "—"
	var n := CraftEdit.find(bp, uid)
	var d := BodyBlueprint.part_def(String(n.get("part", "")))
	return tr(d.title) if d != null and d.title != "" else String(n.get("part", "—"))


func _card_group(i: int) -> String:
	return String(sections[int(cards[i]["section"])]["title"])


func _card_note(i: int) -> String:
	match String(cards[i]["kind"]):
		"default":
			return tr("Обычный боец арены — без сборки из мастерской.")
		"saved":
			return tr("Твоя сборка из мастерской.")
		"last":
			return tr("Последняя быстрая сборка этой сессии.")
		"dice":
			return tr("Случайные ответы конструктора. R — бросить ещё.")
		"builder":
			return tr("Три вопроса — и боец готов. Q или Enter — открыть.")
	return ""


static func _initials(s: String) -> String:
	var parts := s.strip_edges().split(" ", false)
	var out := ""
	for p in parts:
		if out.length() >= 2:
			break
		var ch := p.substr(0, 1)
		if ch != "«" and ch != "(" and ch != ":":
			out += ch.to_upper()
	return out if out != "" else "?"


func _style_cards() -> void:
	for i in cards.size():
		var b := cards[i]["node"] as Button
		if b == null:
			continue
		var on := i == sel
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, _sb["on"] if on else (_sb["hover"] if st == "hover" else _sb["off"]))


func _style_questions() -> void:
	for qi in QUESTIONS.size():
		var q := String(QUESTIONS[qi][0])
		var opts := _options(q)
		(_q_labels[qi] as Label).add_theme_color_override("font_color", ShowTokens.AMBER if qi == q_row else ShowTokens.MUTED)
		for oi in opts.size():
			var b := _q_buttons[qi][oi] as Button
			var on := String(answers.get(q, "")) == String(opts[oi])
			for st in ["normal", "hover", "pressed", "focus"]:
				b.add_theme_stylebox_override(st, _sb["on"] if on else (_sb["hover"] if st == "hover" else _sb["off"]))


func _update_hint() -> void:
	_hint_l.text = tr("↑↓ — вопрос · ←→ или 1–4 — ответ · N — ещё вариант · R — кубик · Enter — в бой · Esc — к бойцам") if builder_open \
		else tr("Стрелки — выбор · Enter — в бой · R — кубик · Q — быстрая сборка · M — мастерская · Esc — назад")


func _set_card_text(i: int) -> void:
	var c: Dictionary = cards[i]
	(c["title_l"] as Label).text = String(c["title"])
	(c["sub_l"] as Label).text = String(c["sub"])
	(c["ph"] as Label).text = _initials(String(c["title"])) if c["bp"] != null else _ph_glyph(String(c["kind"]))


static func _ph_glyph(kind: String) -> String:
	match kind:
		"dice":
			return "?"
		"builder":
			return "+"
		"default":
			return "N0"
	return "?"


func _make_card(c: Dictionary, i: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = CARD
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.clip_contents = true
	b.pressed.connect(_on_card_click.bind(i))
	var ph := _label("", ShowTokens.title(700), 64, Color(ShowTokens.MUTED, 0.45))
	ph.position = Vector2(8, 10)
	ph.size = Vector2(CARD.x - 16, 176)
	ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(ph)
	var pic := TextureRect.new()
	pic.position = Vector2(8, 8)
	pic.size = Vector2(CARD.x - 16, 180)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(pic)
	var t := _label("", ShowTokens.title(600), 22, ShowTokens.TEXT)
	t.position = Vector2(12, 192)
	t.size = Vector2(CARD.x - 24, 32)
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_child(t)
	var s := _label("", ShowTokens.text(500), 15, ShowTokens.MUTED)
	s.position = Vector2(12, 224)
	s.size = Vector2(CARD.x - 24, 24)
	s.clip_text = true
	s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_child(s)
	c["node"] = b
	c["pic"] = pic
	c["ph"] = ph
	c["title_l"] = t
	c["sub_l"] = s
	cards_set_text_later(c)
	return b


## Подписи карточки (до того, как она попала в cards — по ссылке на словарь).
func cards_set_text_later(c: Dictionary) -> void:
	(c["title_l"] as Label).text = String(c["title"])
	(c["sub_l"] as Label).text = String(c["sub"])
	(c["ph"] as Label).text = _initials(String(c["title"])) if c["bp"] != null else _ph_glyph(String(c["kind"]))
	if not dry_run and c["bp"] != null:
		var tex := portraits.request(String(c["key"]), c["bp"] as BodyBlueprint)
		if tex != null:
			(c["pic"] as TextureRect).texture = tex
			(c["ph"] as Label).visible = false


func _build() -> void:
	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(ShowTokens.PLATE, 0.97)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# шапка
	var head := _label(tr("ВЫБОР БОЙЦА"), ShowTokens.title(700), 56, ShowTokens.TEXT)
	head.position = Vector2(GRID_X, 28)
	head.size = Vector2(700, 76)
	add_child(head)
	var sub := _label(mode_title, ShowTokens.text(500), 22, ShowTokens.NULL_BLUE)
	sub.position = Vector2(GRID_X + 4, 104)
	sub.size = Vector2(GRID_W - 360, 32)
	sub.clip_text = true
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(sub)
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.alignment = BoxContainer.ALIGNMENT_END
	row.position = Vector2(DETAIL_X - 520, 46)
	row.size = Vector2(W - 64 - (DETAIL_X - 520), 50)
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	_dice_b = _plate_button(tr("КУБИК  (R)"), 22)
	_dice_b.pressed.connect(roll_dice)
	row.add_child(_dice_b)
	_quick_b = _plate_button(tr("БЫСТРАЯ СБОРКА  (Q)"), 22)
	_quick_b.pressed.connect(func() -> void:
		if builder_open:
			close_builder()
		else:
			open_builder())
	row.add_child(_quick_b)
	_back_b = _plate_button(tr("← НАЗАД  (Esc)"), 22)
	_back_b.pressed.connect(cancel)
	row.add_child(_back_b)
	var bar := ColorRect.new()
	bar.position = Vector2(GRID_X, 146)
	bar.size = Vector2(W - GRID_X * 2.0, 3)
	bar.color = Color(ShowTokens.AMBER, 0.85)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	# карточки
	_scroll = ScrollContainer.new()
	_scroll.name = "Cards"
	_scroll.position = Vector2(GRID_X, TOP)
	_scroll.size = Vector2(GRID_W + 24, BOTTOM - TOP)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_grid_box = VBoxContainer.new()
	_grid_box.add_theme_constant_override("separation", 8)
	_grid_box.custom_minimum_size = Vector2(GRID_W, 0)
	_scroll.add_child(_grid_box)
	_build_builder()
	_build_detail()
	_hint_l = _label("", ShowTokens.text(500), 18, ShowTokens.MUTED)
	_hint_l.position = Vector2(GRID_X, BOTTOM + 30)
	_hint_l.size = Vector2(W - GRID_X * 2.0, 30)
	_hint_l.clip_text = true
	_hint_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_hint_l)
	_update_hint()


func _build_builder() -> void:
	_builder = Control.new()
	_builder.name = "Builder"
	_builder.position = Vector2(GRID_X, TOP)
	_builder.size = Vector2(GRID_W, BOTTOM - TOP)
	_builder.visible = false
	add_child(_builder)
	var t := _label(tr("БЫСТРАЯ СБОРКА"), ShowTokens.title(700), 40, ShowTokens.TEXT)
	t.position = Vector2(0, 0)
	t.size = Vector2(GRID_W, 52)
	_builder.add_child(t)
	var st := _label(tr("Три ответа — и боец готов. Каждый ответ меняет детали; тот же ответ ещё раз — другой вариант."),
		ShowTokens.text(500), 19, ShowTokens.MUTED)
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st.position = Vector2(0, 56)
	st.size = Vector2(GRID_W, 54)
	_builder.add_child(st)
	var y := 124.0
	for qi in QUESTIONS.size():
		var q := String(QUESTIONS[qi][0])
		var ql := _label(tr(String(QUESTIONS[qi][1])), ShowTokens.title(650), 24, ShowTokens.MUTED)
		ql.position = Vector2(0, y)
		ql.size = Vector2(GRID_W, 34)
		_builder.add_child(ql)
		_q_labels.append(ql)
		var opts := _options(q)
		var bw := (GRID_W - GAP * 3.0) / 4.0
		var btns: Array = []
		for oi in opts.size():
			var b := Button.new()
			b.position = Vector2(oi * (bw + GAP), y + 38)
			b.size = Vector2(bw, 104)
			b.focus_mode = Control.FOCUS_NONE
			b.clip_contents = true
			b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			var v := String(opts[oi])
			b.pressed.connect(func() -> void:
				q_row = qi
				set_answer(q, v))
			var bt := _label("%d  %s" % [oi + 1, tr(_opt_title(q, v))], ShowTokens.title(650), 26, ShowTokens.TEXT)
			bt.clip_text = true
			bt.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			bt.position = Vector2(14, 8)
			bt.size = Vector2(bw - 28, 36)
			b.add_child(bt)
			var bh := _label(tr(_opt_hint(q, v)), ShowTokens.text(500), 16, ShowTokens.MUTED)
			# перенос и обрезка — до size: без них минимальная ширина Label = вся строка, и size растягивается за кнопку
			bh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			bh.clip_text = true
			bh.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			bh.position = Vector2(14, 46)
			bh.size = Vector2(bw - 28, 50)
			b.add_child(bh)
			_builder.add_child(b)
			btns.append(b)
		_q_buttons.append(btns)
		y += 168.0
	_answers_l = _label("", ShowTokens.title(650), 28, ShowTokens.AMBER)
	_answers_l.position = Vector2(0, y + 10)
	_answers_l.size = Vector2(GRID_W, 40)
	_answers_l.clip_text = true
	_answers_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_builder.add_child(_answers_l)
	var row := HBoxContainer.new()
	row.position = Vector2(0, y + 64)
	row.size = Vector2(GRID_W, 56)
	row.add_theme_constant_override("separation", 14)
	_builder.add_child(row)
	var more := _plate_button(tr("ЕЩЁ ВАРИАНТ  (N)"), 24)
	more.pressed.connect(reroll)
	row.add_child(more)
	var back := _plate_button(tr("← К БОЙЦАМ  (Esc)"), 24)
	back.pressed.connect(close_builder)
	row.add_child(back)


func _build_detail() -> void:
	var panel := ColorRect.new()
	panel.name = "Detail"
	panel.position = Vector2(DETAIL_X, TOP)
	panel.size = Vector2(DETAIL_W, BOTTOM - TOP)
	panel.color = Color(ShowTokens.PLATE_LIGHT, 0.75)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_d_ph = _label("", ShowTokens.title(700), 120, Color(ShowTokens.MUTED, 0.35))
	_d_ph.position = Vector2(20, 20)
	_d_ph.size = Vector2(300, 450)
	_d_ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_d_ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(_d_ph)
	_d_pic = TextureRect.new()
	_d_pic.position = Vector2(20, 20)
	_d_pic.size = Vector2(300, 450)
	_d_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_d_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_d_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_d_pic)
	_d_stats = VBoxContainer.new()
	_d_stats.position = Vector2(336, 40)
	_d_stats.size = Vector2(DETAIL_W - 356, 300)
	_d_stats.add_theme_constant_override("separation", 12)
	_d_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_d_stats)
	_d_title = _label("", ShowTokens.title(700), 38, ShowTokens.TEXT)
	_d_title.position = Vector2(20, 482)
	_d_title.size = Vector2(DETAIL_W - 40, 52)
	_d_title.clip_text = true
	_d_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	panel.add_child(_d_title)
	_d_group = _label("", ShowTokens.title(600), 20, ShowTokens.AMBER)
	_d_group.position = Vector2(22, 534)
	_d_group.size = Vector2(DETAIL_W - 44, 30)
	_d_group.clip_text = true
	_d_group.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	panel.add_child(_d_group)
	_d_note = _label("", ShowTokens.text(500), 19, ShowTokens.MUTED)
	_d_note.position = Vector2(22, 572)
	_d_note.size = Vector2(DETAIL_W - 44, 84)
	_d_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_note.clip_text = true
	_d_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	panel.add_child(_d_note)
	_fight_b = _plate_button(tr("В БОЙ  (Enter)"), 34)
	_fight_b.position = Vector2(20, BOTTOM - TOP - 156)
	_fight_b.size = Vector2(DETAIL_W - 40, 70)
	_fight_b.size_flags_vertical = Control.SIZE_FILL
	_fight_b.pressed.connect(confirm)
	var hot := StyleBoxFlat.new()
	hot.bg_color = ShowTokens.AMBER
	hot.skew = Vector2(ShowTokens.SKEW * 0.5, 0)
	_fight_b.add_theme_stylebox_override("normal", hot)
	_fight_b.add_theme_color_override("font_color", ShowTokens.INK)
	panel.add_child(_fight_b)
	_ws_b = _plate_button(tr("В МАСТЕРСКУЮ  (M)"), 22)
	_ws_b.position = Vector2(20, BOTTOM - TOP - 72)
	_ws_b.size = Vector2(DETAIL_W - 40, 52)
	_ws_b.size_flags_vertical = Control.SIZE_FILL
	_ws_b.pressed.connect(to_workshop)
	panel.add_child(_ws_b)


func _make_styles() -> void:
	var off := StyleBoxFlat.new()
	off.bg_color = Color(1, 1, 1, 0.045)
	off.border_color = Color(1, 1, 1, 0.08)
	off.set_border_width_all(1)
	var hover := off.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1, 1, 1, 0.09)
	hover.border_color = Color(ShowTokens.AMBER, 0.45)
	var on := off.duplicate() as StyleBoxFlat
	on.bg_color = Color(ShowTokens.PLATE_LIGHT, 0.98)
	on.border_color = ShowTokens.AMBER
	on.set_border_width_all(3)
	on.shadow_color = Color(0, 0, 0, 0.35)
	on.shadow_size = 10
	_sb = {"off": off, "hover": hover, "on": on}


func _label(text: String, font: Font, px: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # текст уже переведён tr()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", colour)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _plate_button(text: String, px: int) -> Button:
	var b := Button.new()
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", ShowTokens.title(600))
	b.add_theme_font_size_override("font_size", px)
	b.add_theme_color_override("font_color", ShowTokens.TEXT)
	b.add_theme_color_override("font_hover_color", ShowTokens.INK)
	b.add_theme_color_override("font_pressed_color", ShowTokens.INK)
	for st in [["normal", Color(ShowTokens.PLATE_LIGHT, 0.9), Color(1, 1, 1, 0.14)], ["hover", ShowTokens.AMBER, ShowTokens.AMBER],
			["pressed", ShowTokens.AMBER.darkened(0.15), ShowTokens.AMBER], ["focus", Color(ShowTokens.PLATE_LIGHT, 0.9), Color(1, 1, 1, 0.14)],
			["disabled", Color(ShowTokens.PLATE_LIGHT, 0.5), Color(1, 1, 1, 0.06)]]:
		var s := StyleBoxFlat.new()
		s.bg_color = st[1]
		s.border_color = st[2]
		s.set_border_width_all(1)
		s.skew = Vector2(ShowTokens.SKEW * 0.5, 0)
		s.content_margin_left = 20
		s.content_margin_right = 20
		s.content_margin_top = 8
		s.content_margin_bottom = 8
		b.add_theme_stylebox_override(String(st[0]), s)
	return b
