## Экраны кампании «История» в стиле эфира телевизора гаража (docs/plan-demo/MENU_GARAGE.md, «Кампания в телевизоре»):
## красная плашка «● LIVE», тёмная полоса заголовка, бордовый градиент карточки «Следующий бой», крупное жёлтое имя, бегущая
## строка внизу. Рисуется на весь экран (1920×1080 базовых, stretch canvas_items), поверх — слой tv_overlay.gdshader (развёртка,
## виньетка, закруглённые углы, помехи при смене экрана). Экраны:
##   лестница лиги — слева карточка «Следующий бой» (портрет игрока против соперника, имена, рекорд, ставка), справа турнирная
##     сетка (4 соперника с миниатюрами, статусы, трофеи), реплика N0, кнопки В БОЙ / МАСТЕРСКАЯ / НОВАЯ КАМПАНИЯ / ВЫХОД;
##   итоги боя — ПОБЕДА / ПОРАЖЕНИЕ / НИЧЬЯ, плашка TROPHY RIGHTS с иконкой детали, портреты, кнопки;
##   подключение — настроечная таблица и подпись, пока ставится бой (купол грузится);
##   панель мастерской — узкая плашка «КАМПАНИЯ · следующий: …» с кнопками В БОЙ / К СЕТКЕ поверх 3D-мастерской.
## Только вид и сигналы: правила и сохранение — у GarageCampaign (scenes/menu/garage_campaign.gd). Портреты бойцов — DollPortrait
## (рендер сборки в рантайме), иконка трофея — PartIcons; в headless их нет — рисуется силуэт-заглушка.
class_name CampaignTvUi
extends Node

signal fight_pressed
signal workshop_pressed
signal new_pressed
signal exit_pressed
signal ladder_pressed

const W := 1920.0
const H := 1080.0
const N0_LINES_SRC := preload("res://scenes/campaign/campaign_flow.gd")
const OVERLAY := preload("res://scenes/menu/tv_overlay.gdshader")

const RED := Color(0.8, 0.1, 0.1)
const CREAM := Color(1.0, 0.9, 0.55)
const AMBER := Color(0.95, 0.75, 0.2)
const CYAN := Color(0.6, 1.0, 0.95)
const INK := Color(0.08, 0.06, 0.04)
const PLATE := Color(0.05, 0.05, 0.07, 0.88)
const GREEN := Color(0.45, 0.9, 0.5)
const BAD := Color(1.0, 0.45, 0.35)
const MUTED := Color(0.78, 0.76, 0.8)
const NEW_CONFIRM_S := 3.0

var f_head: Font
var f_body: Font
var f_mono: Font
var portraits: DollPortrait
var icons: PartIcons
var screen_id := "none"               # none | ladder | outcome | connecting | workshop
var buttons: Array = []               # кнопки текущего экрана (для проб)

var _screens: CanvasLayer
var _overlay_layer: CanvasLayer
var _root: Control
var _overlay: ColorRect
var _mat: ShaderMaterial
var _ticker: Label
var _ticker_w := 1.0
var _ticker_x := 0.0
var _dot: Label
var _vs: Label
var _pics: Dictionary = {}            # ключ портрета → [TextureRect]
var _icon_rects: Dictionary = {}      # id детали → TextureRect
var _tw_noise: Tween
var _tw_in: Tween
var _new_armed_until := -1.0
var _time := 0.0
var _stripes: ImageTexture


func _init(head: Font = null, body: Font = null, mono: Font = null) -> void:
	f_head = head
	f_body = body
	f_mono = mono


func _ready() -> void:
	_screens = CanvasLayer.new()
	_screens.name = "Screens"
	_screens.layer = 40
	_screens.visible = false
	add_child(_screens)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screens.add_child(_root)
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.name = "Overlay"
	_overlay_layer.layer = 50
	_overlay_layer.visible = false
	add_child(_overlay_layer)
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = OVERLAY
	_overlay.material = _mat
	_overlay_layer.add_child(_overlay)
	portraits = DollPortrait.new()
	portraits.name = "Portraits"
	add_child(portraits)
	portraits.portrait_ready.connect(_on_portrait)
	icons = PartIcons.new()
	icons.name = "TrophyIcons"
	add_child(icons)
	icons.icon_ready.connect(_on_icon)
	_stripes = _make_stripes()


func _process(delta: float) -> void:
	_time += delta
	if not _screens.visible:
		return
	if _ticker != null and is_instance_valid(_ticker):
		_ticker_x -= 150.0 * delta
		if _ticker_x < -_ticker_w:
			_ticker_x += _ticker_w
		_ticker.position.x = _ticker_x
	if _dot != null and is_instance_valid(_dot):
		_dot.modulate.a = 0.55 + 0.45 * sin(_time * 5.0) if screen_id != "outcome" else 1.0
	if _vs != null and is_instance_valid(_vs):
		_vs.scale = Vector2.ONE * (1.0 + 0.035 * sin(_time * 3.0))


# ---------------------------------------------------------------- слой, помехи

## Показать / спрятать экраны и слой кинескопа (strength — сила эффекта: в бою ниже).
func set_visible_all(screens: bool, overlay: bool, strength := 1.0) -> void:
	_screens.visible = screens
	_overlay_layer.visible = overlay
	_mat.set_shader_parameter("strength", strength)
	if not screens:
		screen_id = "none"


func set_strength(v: float) -> void:
	_mat.set_shader_parameter("strength", v)


## Помехи: всплеск снега noise → 0 за dur секунд (смена экрана — «переключили канал»).
func burst(noise := 1.0, dur := 0.35) -> void:
	if _tw_noise != null and _tw_noise.is_valid():
		_tw_noise.kill()
	_mat.set_shader_parameter("noise_amt", noise)
	_tw_noise = create_tween()
	_tw_noise.tween_method(func(v: float) -> void: _mat.set_shader_parameter("noise_amt", v), noise, 0.0, dur)


## Выключение: схлопывание в полоску (power 1 → 0) и обратно.
func power_off(dur := 0.5) -> Tween:
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter("power", v), 1.0, 0.0, dur)
	return tw


func power_on(dur := 0.3) -> Tween:
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter("power", v), 0.0, 1.0, dur)
	return tw


func reset_power() -> void:
	_mat.set_shader_parameter("power", 1.0)


# ---------------------------------------------------------------- портреты и иконки

static func blueprint_key(prefix: String, bp: BodyBlueprint) -> String:
	if bp == null:
		return prefix
	return "%s:%s:%d:%d" % [prefix, bp.id, bp.nodes.size(), hash(var_to_str(bp.nodes))]


func _portrait(parent: Control, key: String, bp: BodyBlueprint, rect: Rect2, shade := false) -> TextureRect:
	var tr := TextureRect.new()
	tr.position = rect.position
	tr.size = rect.size
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if shade:
		tr.modulate = Color(0.55, 0.55, 0.6)
	var tex := portraits.request(key, bp)
	if tex != null:
		tr.texture = tex
	else:
		var ph := _text(tr, "?", Vector2(0, rect.size.y * 0.18), int(rect.size.y * 0.5), Color(1, 1, 1, 0.12), f_head)
		ph.size = Vector2(rect.size.x, rect.size.y * 0.7)
		ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if not _pics.has(key):
			_pics[key] = []
		(_pics[key] as Array).append(tr)
	parent.add_child(tr)
	return tr


func _on_portrait(key: String, tex: Texture2D) -> void:
	for tr in _pics.get(key, []):
		if is_instance_valid(tr):
			(tr as TextureRect).texture = tex
			for c in (tr as TextureRect).get_children():
				c.queue_free()
	_pics.erase(key)


func _on_icon(id: String, tex: Texture2D) -> void:
	var tr: TextureRect = _icon_rects.get(id)
	if tr != null and is_instance_valid(tr):
		tr.texture = tex


# ---------------------------------------------------------------- кирпичики

func _clear() -> void:
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()
	buttons = []
	_pics.clear()
	_icon_rects.clear()
	_ticker = null
	_dot = null
	_vs = null


func _text(parent: Control, s: String, pos: Vector2, px: int, c: Color, font: Font, outline := false) -> Label:
	var l := Label.new()
	l.text = s
	l.position = pos
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", c)
	if outline:
		l.add_theme_constant_override("outline_size", 8)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _rect(parent: Control, pos: Vector2, size: Vector2, c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.position = pos
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


## Косая плашка эфира (Broadcast.plate): фон, наклон, цветная кромка слева.
func _plate(parent: Control, r: Rect2, bg: Color, edge: Color = Color(0, 0, 0, 0), skew := 0.0, edge_w := 8.0) -> Panel:
	var p := Panel.new()
	p.position = r.position
	p.size = r.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := BcStyle.new()
	s.bg = bg
	s.skew = skew
	s.edge_color = edge
	s.edge_w = edge_w if edge.a > 0.0 else 0.0
	p.add_theme_stylebox_override("panel", s)
	parent.add_child(p)
	return p


func _gradient(parent: Control, a: Color, b: Color, horizontal := true) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0) if horizontal else Vector2(0, 1)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.position = Vector2.ZERO
	tr.size = Vector2(W, H)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(tr)
	return tr


func _make_stripes() -> ImageTexture:
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	for y in 48:
		for x in 48:
			img.set_pixel(x, y, Color(1, 1, 1, 0.045) if (x + y) % 48 < 8 else Color(1, 1, 1, 0.0))
	return ImageTexture.create_from_image(img)


## Фон эфира: градиент, косые полосы, тёмный низ.
func _backdrop(a: Color, b: Color) -> void:
	_gradient(_root, a, b, true)
	var st := TextureRect.new()
	st.texture = _stripes
	st.stretch_mode = TextureRect.STRETCH_TILE
	st.position = Vector2.ZERO
	st.size = Vector2(W, H)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(st)
	var wm := _text(_root, "NULL", Vector2(W - 760, 120), 520, Color(1, 1, 1, 0.035), f_head)
	wm.rotation_degrees = 0.0
	var dark := _gradient(_root, Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.55), false)
	dark.position = Vector2(0, H - 360)
	dark.size = Vector2(W, 360)


func _header(tag: String, title: String, right: String) -> void:
	_rect(_root, Vector2(48, 36), Vector2(250, 66), RED)
	_dot = _text(_root, tag, Vector2(66, 36), 44, Color.WHITE, f_head)
	_rect(_root, Vector2(298, 36), Vector2(W - 346, 66), Color(0.05, 0.05, 0.07, 0.88))
	_text(_root, title, Vector2(324, 40), 42, Color.WHITE, f_head)
	var r := _text(_root, right, Vector2(W - 70 - 560, 56), 26, Color(0.75, 0.85, 1.0), f_mono)
	r.size = Vector2(560, 36)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _ticker_bar(s: String) -> void:
	_rect(_root, Vector2(0, H - 72), Vector2(W, 72), AMBER)
	var clip := Control.new()
	clip.position = Vector2(0, H - 72)
	clip.size = Vector2(W, 72)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(clip)
	var one := s + "      ●      "
	_ticker = _text(clip, one + one + one + one, Vector2(0, 8), 40, INK, f_head)
	_ticker_w = maxf(f_head.get_string_size(one, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x, 200.0)
	_ticker_x = 0.0


func _button(text: String, rect: Rect2, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", f_head)
	b.add_theme_font_size_override("font_size", 40 if primary else 34)
	var fg := INK if primary else Color(0.95, 0.93, 0.9)
	for k in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(k, fg)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.3))
	var mk := func(bg: Color, edge: Color) -> BcStyle:
		var s := BcStyle.new()
		s.bg = bg
		s.skew = 0.18
		s.edge_color = edge
		s.edge_w = 8.0 if edge.a > 0.0 else 0.0
		s.content_margin_left = 30
		s.content_margin_right = 30
		return s
	var normal: BcStyle = mk.call(AMBER if primary else Color(0.05, 0.05, 0.07, 0.9), Color(1, 1, 1, 0.0))
	var hover: BcStyle = mk.call(Color(1.0, 0.85, 0.35) if primary else Color(0.16, 0.14, 0.2, 0.96), AMBER)
	var focus: BcStyle = mk.call(Color(1.0, 0.85, 0.35) if primary else Color(0.16, 0.14, 0.2, 0.96), RED if primary else AMBER)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", mk.call(Color(0.1, 0.1, 0.12, 0.7), Color(0, 0, 0, 0)))
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			b.grab_focus())
	_root.add_child(b)
	buttons.append(b)
	return b


func _enter(noise := 0.8) -> void:
	_screens.visible = true
	_overlay_layer.visible = true
	_root.modulate.a = 0.0
	if _tw_in != null and _tw_in.is_valid():
		_tw_in.kill()
	_tw_in = create_tween()
	_tw_in.tween_property(_root, "modulate:a", 1.0, 0.22)
	burst(noise, 0.4)


func _n0_plate(text: String, y: float) -> void:
	_plate(_root, Rect2(48, y, 1008, 58), Color(0.04, 0.04, 0.06, 0.82), Color(0.4, 0.9, 1.0), 0.0, 6.0)
	_text(_root, "N0", Vector2(72, y + 6), 36, Color(0.4, 0.9, 1.0), f_mono)
	var l := _text(_root, text.trim_prefix("N0: "), Vector2(140, y + 10), 28, Color(0.95, 0.95, 0.97), f_body)
	l.size = Vector2(900, 40)
	l.clip_text = true


# ---------------------------------------------------------------- экран: лестница

## Лестница лиги. state — CampaignState; message — причина, почему «В БОЙ» не пускает (пусто — нет). Кнопки: fight / workshop / new / exit.
func show_ladder(state: CampaignState, message := "") -> void:
	_clear()
	screen_id = "ladder"
	_backdrop(Color(0.12, 0.04, 0.07), Color(0.34, 0.08, 0.13))
	var tier := CampaignLeague.tier_title(state.tier)
	_header("● LIVE", "%s  ·  ТУРНИРНАЯ СЕТКА" % tier.to_upper(),
		"РЕГЛАМЕНТ · ЭНЕРГИЯ %d" % CampaignLeague.energy_budget(state.tier))
	var rival := state.current_rival()
	# --- карточка «Следующий бой»
	_text(_root, "МЕСТНАЯ ЛИГА ПРОЙДЕНА" if state.finished() else "СЛЕДУЮЩИЙ БОЙ", Vector2(60, 122), 38, CYAN, f_head)
	_plate(_root, Rect2(48, 176, 1010, 614), Color(0.03, 0.03, 0.05, 0.55), Color(0.8, 0.1, 0.1), 0.0, 8.0)
	var pl_bp := state.blueprint
	var pk := blueprint_key("player", pl_bp)
	_plate(_root, Rect2(92, 200, 340, 520), Color(0.16, 0.3, 0.55, 0.28), Color(0.3, 0.6, 1.0), 0.0, 5.0)
	_portrait(_root, pk, pl_bp, Rect2(96, 204, 332, 512))
	_text(_root, "ТЫ", Vector2(112, 206), 34, Color(0.6, 0.8, 1.0), f_mono)
	_text(_root, pl_bp.title.to_upper() if pl_bp != null else "", Vector2(92, 724), 40, Color.WHITE, f_head)
	if state.finished():
		var champ := _text(_root, "ЧЕМПИОН", Vector2(480, 330), 92, CREAM, f_head)
		champ.size = Vector2(540, 120)
		champ.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_text(_root, "%d – %d" % [state.wins, state.losses], Vector2(520, 460), 72, Color.WHITE, f_head).size = Vector2(460, 90)
		_text(_root, "Трофеев на полке: %d" % state.trophies.size(), Vector2(500, 560), 30, MUTED, f_body)
	else:
		_vs = _text(_root, "VS", Vector2(486, 380), 96, CREAM, f_head, true)
		_vs.pivot_offset = Vector2(60, 60)
		var rbp := CampaignLeague.rival_blueprint(state.tier, rival)
		var rk := blueprint_key("rival", rbp)
		_plate(_root, Rect2(660, 200, 340, 520), Color(0.55, 0.12, 0.14, 0.3), Color(1.0, 0.35, 0.3), 0.0, 5.0)
		_portrait(_root, rk, rbp, Rect2(664, 204, 332, 512))
		_text(_root, "УРОВЕНЬ %d" % int(rival.get("level", 1)), Vector2(680, 206), 30, Color(1.0, 0.7, 0.6), f_mono)
		_text(_root, CampaignLeague.rival_title(rival).to_upper(), Vector2(660, 724), 48, CREAM, f_head)
		if bool(rival.get("final", false)):
			_plate(_root, Rect2(850, 214, 140, 44), AMBER, Color(0, 0, 0, 0), 0.2)
			_text(_root, "ФИНАЛ", Vector2(868, 214), 34, INK, f_head)
	# --- турнирная сетка
	_text(_root, "СЕТКА ЛИГИ", Vector2(1110, 122), 38, CYAN, f_head)
	var ladder := state.ladder()
	for i in ladder.size():
		var r: Dictionary = ladder[i]
		var y := 176.0 + i * 132.0
		var done := i < state.step
		var cur := i == state.step
		var edge := GREEN if done else (AMBER if cur else Color(0.5, 0.5, 0.56))
		_plate(_root, Rect2(1100, y, 770, 118), Color(0.05, 0.05, 0.07, 0.9 if cur else 0.72), edge, 0.0, 8.0)
		_text(_root, "%d" % (i + 1), Vector2(1128, y + 18), 76, edge, f_head)
		var rbp2 := CampaignLeague.rival_blueprint(state.tier, r)
		var thumb := _portrait(_root, blueprint_key("rival", rbp2), rbp2, Rect2(1196, y + 6, 76, 106), not done and not cur)
		thumb.clip_contents = true
		var nm := CampaignLeague.rival_title(r).to_upper()
		_text(_root, nm, Vector2(1290, y + 10), 52, Color.WHITE if (cur or done) else Color(0.8, 0.8, 0.86), f_head)
		var status := ""
		var scol := MUTED
		if done:
			var tr := _trophy_of_step(state, i)
			status = "✓ ПОБЕЖДЁН" + ((" · ТРОФЕЙ: %s" % CampaignLeague.part_title(tr).to_upper()) if tr != "" else "")
			scol = GREEN
		elif cur:
			status = "▶ СЛЕДУЮЩИЙ СОПЕРНИК"
			scol = AMBER
		else:
			status = "ЕЩЁ ВПЕРЕДИ"
		var sl := _text(_root, status, Vector2(1292, y + 70), 24, scol, f_mono)
		sl.size = Vector2(560, 32)
		sl.clip_text = true
		sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if bool(r.get("final", false)):
			_plate(_root, Rect2(1730, y + 14, 120, 40), AMBER, Color(0, 0, 0, 0), 0.2)
			_text(_root, "ФИНАЛ", Vector2(1746, y + 14), 30, INK, f_head)
	var trophies: PackedStringArray = []
	for id in state.trophies:
		trophies.append(CampaignLeague.part_title(id))
	_plate(_root, Rect2(1100, 712, 770, 78), Color(0.03, 0.03, 0.05, 0.55), Color(1, 1, 1, 0.25), 0.0, 4.0)
	_text(_root, "ПОБЕД %d  ·  ПОРАЖЕНИЙ %d" % [state.wins, state.losses], Vector2(1124, 716), 34, Color.WHITE, f_head)
	var tl := _text(_root, "ТРОФЕИ: " + (", ".join(trophies).to_upper() if not trophies.is_empty() else "ПОКА НЕТ"), Vector2(1124, 756), 22, MUTED, f_mono)
	tl.size = Vector2(730, 30)
	tl.clip_text = true
	# --- N0 и кнопки
	var n0 := String(N0_LINES_SRC.N0_LINES[mini(state.step, N0_LINES_SRC.N0_LINES.size() - 1)])
	var errs := CraftEdit.friendly_errors(state.blueprint)
	var msg := message
	if msg == "" and not errs.is_empty():
		msg = "Сборка не готова к бою: %s — открой мастерскую." % errs[0]
	if msg != "":
		_plate(_root, Rect2(48, 806, 1822, 58), Color(0.35, 0.06, 0.05, 0.9), BAD, 0.0, 6.0)
		_text(_root, "!", Vector2(72, 806), 40, BAD, f_head)
		_text(_root, msg, Vector2(120, 816), 28, Color.WHITE, f_body)
	else:
		_n0_plate(n0, 806)
	var fb := _button("ЛИГА ПРОЙДЕНА" if state.finished() else "В БОЙ  ▶", Rect2(48, 890, 420, 84), true)
	fb.disabled = state.finished()
	fb.pressed.connect(func() -> void: fight_pressed.emit())
	var wb := _button("МАСТЕРСКАЯ", Rect2(496, 890, 400, 84))
	wb.pressed.connect(func() -> void: workshop_pressed.emit())
	var nb := _button("НОВАЯ КАМПАНИЯ", Rect2(924, 890, 470, 84))
	nb.pressed.connect(func() -> void:
		var now := Time.get_ticks_msec() / 1000.0
		if now > _new_armed_until:
			_new_armed_until = now + NEW_CONFIRM_S
			nb.text = "ЕЩЁ РАЗ — СТЁРТСЯ"
		else:
			_new_armed_until = -1.0
			new_pressed.emit())
	var xb := _button("ВЫХОД", Rect2(1422, 890, 448, 84))
	xb.pressed.connect(func() -> void: exit_pressed.emit())
	_new_armed_until = -1.0
	(fb if not fb.disabled else wb).grab_focus()
	_ticker_bar("СЕГОДНЯ В 21:00 · %s · ПОБЕДИТЕЛЬ ЗАБИРАЕТ ДЕТАЛЬ СОПЕРНИКА" % (
		"ЛИГА ПРОЙДЕНА" if state.finished() else "%s ПРОТИВ НОВИЧКА ИЗ БОКСА 07" % CampaignLeague.rival_title(rival).to_upper()))
	_enter()


func _trophy_of_step(state: CampaignState, i: int) -> String:
	for f in state.fights:
		if bool(f.get("won", false)) and int(f.get("step", -1)) == i:
			return String(f.get("trophy", ""))
	return ""


# ---------------------------------------------------------------- экран: итоги

## Итоги боя: info — {won, draw, duration_s, reason}; trophy — id детали ("" — нет); rival_bp / player_bp — для портретов.
func show_outcome(state: CampaignState, info: Dictionary, trophy: String, rival: Dictionary) -> void:
	_clear()
	screen_id = "outcome"
	var won := bool(info.get("won", false))
	var draw := bool(info.get("draw", false))
	if won:
		_backdrop(Color(0.04, 0.12, 0.08), Color(0.1, 0.3, 0.18))
	else:
		_backdrop(Color(0.14, 0.04, 0.05), Color(0.32, 0.07, 0.08))
	_header("ИТОГ", "МЕСТНАЯ ЛИГА  ·  ИТОГИ БОЯ", "БОЙ %d ИЗ %d" % [mini(state.step + (0 if won else 1), state.ladder().size()), state.ladder().size()])
	var col := GREEN if won else (AMBER if draw else BAD)
	var head := _text(_root, "ПОБЕДА" if won else ("НИЧЬЯ" if draw else "ПОРАЖЕНИЕ"), Vector2(70, 150), 190, col, f_head, true)
	head.rotation_degrees = -2.0
	var secs := int(float(info.get("duration_s", 0.0)))
	var sub := "%s  ·  %d:%02d" % [CampaignLeague.rival_title(rival).to_upper(), secs / 60, secs % 60]
	_text(_root, sub, Vector2(84, 372), 42, Color.WHITE, f_head)
	if won:
		_plate(_root, Rect2(70, 450, 1060, 250), Color(0.03, 0.03, 0.05, 0.7), AMBER, 0.0, 8.0)
		_text(_root, "TROPHY RIGHTS", Vector2(110, 466), 30, AMBER, f_mono)
		if trophy != "":
			_plate(_root, Rect2(110, 520, 150, 150), Color(0.1, 0.1, 0.14, 0.9), Color(1, 1, 1, 0.2), 0.0, 3.0)
			var ir := TextureRect.new()
			ir.position = Vector2(114, 524)
			ir.size = Vector2(142, 142)
			ir.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ir.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ir.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var tex := icons.request(trophy)
			if tex != null:
				ir.texture = tex
			else:
				_icon_rects[trophy] = ir
			_root.add_child(ir)
			_text(_root, CampaignLeague.part_title(trophy).to_upper(), Vector2(290, 530), 76, CREAM, f_head)
			_text(_root, "Деталь соперника теперь на полке мастерской.", Vector2(292, 622), 28, Color(0.9, 0.9, 0.95), f_body)
		else:
			_text(_root, "ТРОФЕЯ НЕТ", Vector2(110, 540), 76, CREAM, f_head)
			_text(_root, "У соперника не нашлось детали, которая может выпасть.", Vector2(112, 632), 28, Color(0.9, 0.9, 0.95), f_body)
		if state.finished():
			_text(_root, "%s ПРОЙДЕНА. ПРОДОЛЖЕНИЕ СЛЕДУЕТ." % CampaignLeague.tier_title(state.tier).to_upper(), Vector2(84, 726), 34, CYAN, f_head)
	else:
		_plate(_root, Rect2(70, 450, 1060, 160), Color(0.03, 0.03, 0.05, 0.7), BAD, 0.0, 8.0)
		_text(_root, "БОЙ ПЕРЕИГРЫВАЕТСЯ", Vector2(110, 470), 60, Color.WHITE, f_head)
		_text(_root, "Лестница стоит, штрафа нет. Загляни в мастерскую — или просто ещё раз.", Vector2(112, 548), 28, Color(0.9, 0.9, 0.95), f_body)
	# портреты справа
	var rbp := CampaignLeague.rival_blueprint(state.tier, rival)
	_plate(_root, Rect2(1200, 150, 300, 480), Color(0.16, 0.3, 0.55, 0.25), Color(0.3, 0.6, 1.0), 0.0, 5.0)
	_portrait(_root, blueprint_key("player", state.blueprint), state.blueprint, Rect2(1204, 154, 292, 450), not won and not draw)
	_plate(_root, Rect2(1560, 150, 300, 480), Color(0.55, 0.12, 0.14, 0.25), Color(1.0, 0.35, 0.3), 0.0, 5.0)
	_portrait(_root, blueprint_key("rival", rbp), rbp, Rect2(1564, 154, 292, 450), won)
	_text(_root, "ТЫ", Vector2(1220, 156), 30, Color(0.6, 0.8, 1.0), f_mono)
	_text(_root, "%d – %d" % [state.wins, state.losses], Vector2(1200, 636), 56, Color.WHITE, f_head)
	_league_strip(state, 70.0, 740.0)
	var nb := _button(("СЛЕДУЮЩИЙ БОЙ  ▶" if won else "ЕЩЁ РАЗ  ▶"), Rect2(48, 890, 560, 84), true)
	nb.visible = not state.finished()
	nb.pressed.connect(func() -> void: fight_pressed.emit())
	var wb := _button("МАСТЕРСКАЯ", Rect2(636, 890, 460, 84))
	wb.pressed.connect(func() -> void: workshop_pressed.emit())
	var lb := _button("К СЕТКЕ ЛИГИ", Rect2(1124, 890, 746, 84))
	lb.pressed.connect(func() -> void: ladder_pressed.emit())
	(nb if nb.visible else lb).grab_focus()
	_ticker_bar("ИТОГИ БОЯ · %s · %s" % [CampaignLeague.rival_title(rival).to_upper(),
		"ПОБЕДА ЗАЧТЕНА, ДЕТАЛЬ ВЫДАНА" if won else "БОЙ НЕ ЗАЧТЁН, ПЕРЕИГРОВКА БЕЗ ШТРАФА"])
	_enter(1.0)


## Полоска прогресса лиги: по плашке на соперника — пройден (✓), следующий (▶), впереди.
func _league_strip(state: CampaignState, x: float, y: float) -> void:
	_text(_root, "ПРОГРЕСС ЛИГИ", Vector2(x + 4, y - 38), 26, CYAN, f_mono)
	var ladder := state.ladder()
	var w := (1060.0 - 12.0 * (ladder.size() - 1)) / ladder.size()
	for i in ladder.size():
		var done := i < state.step
		var cur := i == state.step
		var edge := GREEN if done else (AMBER if cur else Color(0.5, 0.5, 0.56))
		var px := x + i * (w + 12.0)
		_plate(_root, Rect2(px, y, w, 86), Color(0.05, 0.05, 0.07, 0.85 if (done or cur) else 0.55), edge, 0.0, 6.0)
		_text(_root, ("✓ " if done else ("▶ " if cur else "")) + CampaignLeague.rival_title(ladder[i]).to_upper(), Vector2(px + 20, y + 14), 36,
			Color.WHITE if (done or cur) else Color(0.7, 0.7, 0.76), f_head)


# ---------------------------------------------------------------- экран: подключение

## Настроечная таблица и подпись, пока ставится бой (купол грузится). Без кнопок.
func show_connecting(title: String, sub: String) -> void:
	_clear()
	screen_id = "connecting"
	var cols := [Color(0.75, 0.75, 0.75), Color(0.75, 0.75, 0), Color(0, 0.75, 0.75), Color(0, 0.75, 0), Color(0.75, 0, 0.75), Color(0.75, 0, 0), Color(0, 0, 0.75)]
	for i in cols.size():
		_rect(_root, Vector2(i * W / 7.0, 0), Vector2(W / 7.0 + 1, H), cols[i])
	_rect(_root, Vector2(0, 700), Vector2(W, 220), Color(0.05, 0.05, 0.05))
	for i in 6:
		_rect(_root, Vector2(180 + i * 260, 740), Vector2(260, 140), Color(i / 5.0, i / 5.0, i / 5.0))
	_plate(_root, Rect2(380, 250, 1160, 250), Color(0.03, 0.03, 0.05, 0.92), RED, 0.0, 10.0)
	_text(_root, title, Vector2(430, 270), 96, Color.WHITE, f_head)
	_text(_root, sub, Vector2(434, 396), 36, CREAM, f_mono)
	_dot = _text(_root, "● LIVE", Vector2(430, 452), 36, RED, f_head)
	_enter(0.7)


# ---------------------------------------------------------------- панель мастерской кампании

## Узкая плашка сверху по центру поверх 3D-мастерской: что за регламент, кого ждём, кнопки В БОЙ и К СЕТКЕ.
func show_workshop_bar(state: CampaignState) -> void:
	_clear()
	screen_id = "workshop"
	_screens.visible = true
	_overlay_layer.visible = false
	_root.modulate.a = 1.0
	var r := state.current_rival()
	# между библиотекой слева (до x≈460) и панелью справа (с x≈1600): плашка с подписью слева и кнопками справа
	_plate(_root, Rect2(488, 86, 1090, 106), Color(0.04, 0.04, 0.06, 0.92), RED, 0.0, 8.0)
	_text(_root, "● КАМПАНИЯ" + ("  ·  ПРОТИВ: %s" % CampaignLeague.rival_title(r).to_upper() if not r.is_empty() else ""), Vector2(524, 88), 36, CREAM, f_head)
	_text(_root, "ЭНЕРГИЯ %d  ·  ОРУЖИЕ %d/КГ  ·  ТРОФЕЕВ %d" % [CampaignLeague.energy_budget(state.tier),
		int(CampaignLeague.weapon_energy_per_kg(state.tier)), state.trophies.size()], Vector2(526, 140), 22, MUTED, f_mono)
	var fb := _button("В БОЙ ▶", Rect2(1170, 98, 190, 80), true)
	fb.visible = not state.finished()
	fb.pressed.connect(func() -> void: fight_pressed.emit())
	var lb := _button("К СЕТКЕ", Rect2(1376, 98, 190, 80))
	lb.pressed.connect(func() -> void: ladder_pressed.emit())
	for b in buttons:
		(b as Button).focus_mode = Control.FOCUS_NONE
		(b as Button).add_theme_font_size_override("font_size", 28)


func clear_screens() -> void:
	_clear()
	screen_id = "none"
	_screens.visible = false
