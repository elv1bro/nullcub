## Скины HUD боя — три направления с макета (docs/plan-demo/HUD_SKINS.md) живут в игре одновременно, автор сравнивает
## (02.10.2026: «не могу выбрать до конца, хочу посмотреть все 3 варианта в игре, переключать в настройках»):
##   broadcast — «Трансляция Лиги» (B): косые плашки BcStyle, плотные цвета, янтарь зала, узкий жирный шрифт;
##   neon      — «Неон NULL» (A): тёмное стекло с неоновым краем и свечением, светящийся текст, голубой цвет поля;
##   led       — «LED-табло» (C): чёрные панели табло, янтарные надписи, крупные строки — точками светодиодов (led_dots.gdshader).
## Выбор хранится в user://settings.cfg, [player] hud_skin — тот же файл и раздел, что у Flow (scripts/menu/flow.gd в ветке
## меню-гаража; строка экрана настроек — в HUD_SKINS.md). Меняется set_skin() или H в бою (cycle(); F9 занята качеством графики Gfx); элементы HUD слушают
## events.changed и перекрашиваются на лету. Элементы берут у скина font(role), panel(role, …), style_label(…), theme(), цвета;
## рисованные (полоса HP, портрет, стрелки за экраном) смотрят id() сами.
class_name HudSkin
extends RefCounted

class Events:
	extends RefCounted
	signal changed(id: String)

const IDS: Array[String] = ["broadcast", "neon", "led"]
const LABELS := {"broadcast": "ТРАНСЛЯЦИЯ ЛИГИ", "neon": "НЕОН NULL", "led": "LED-ТАБЛО"}
const DEFAULT := "broadcast"
const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "player"
const SETTINGS_KEY := "hud_skin"

const NEON := Color(0.27, 0.89, 1.0)           # голубой цвет поля NULL
const NEON_AMBER := Color(1.0, 0.72, 0.25)
const NEON_RED := Color(1.0, 0.27, 0.33)
const LED := Color(1.0, 0.70, 0.18)            # янтарь светодиодов
const LED_RED := Color(1.0, 0.33, 0.27)
const LED_CYAN := Color(0.62, 0.94, 1.0)       # экран N0
const LED_SHADER := preload("res://scripts/ui/led_dots.gdshader")

static var events := Events.new()
static var _id := ""
static var _fonts := {}
static var _themes := {}
static var _led_mats := {}


# ---------------------------------------------------------------- выбор

static func id() -> String:
	if _id == "":
		_id = DEFAULT
		var cf := ConfigFile.new()
		if cf.load(SETTINGS_PATH) == OK:
			var v := String(cf.get_value(SETTINGS_SECTION, SETTINGS_KEY, DEFAULT))
			if IDS.has(v):
				_id = v
	return _id


static func label() -> String:
	return String(LABELS.get(id(), id()))


## Сменить скин (сразу во всём HUD); save — записать в user://settings.cfg (чужие ключи файла сохраняются).
static func set_skin(new_id: String, save: bool = true) -> void:
	if not IDS.has(new_id):
		return
	var was := id()
	_id = new_id
	if save:
		var cf := ConfigFile.new()
		cf.load(SETTINGS_PATH)
		cf.set_value(SETTINGS_SECTION, SETTINGS_KEY, new_id)
		cf.save(SETTINGS_PATH)
	if was != new_id:
		events.changed.emit(new_id)


## Следующий скин по кругу (H в бою). Возвращает его подпись.
static func cycle() -> String:
	set_skin(IDS[(IDS.find(id()) + 1) % IDS.size()])
	return label()


# ---------------------------------------------------------------- шрифты и цвета

## Шрифт по роли: display — крупные надписи, plate — имена и подписи, digits — цифры табло, body — реплики N0.
static func font(role: String) -> Font:
	var key := id() + "/" + role
	if _fonts.has(key):
		return _fonts[key]
	var f: Font
	match id():
		"neon":
			var sf := SystemFont.new()
			match role:
				"digits":
					sf.font_names = PackedStringArray(["DIN Alternate", "Avenir Next", "Arial"])
					sf.font_weight = 700
				"body":
					sf.font_names = PackedStringArray(["Avenir Next", "Helvetica Neue", "Arial"])
					sf.font_weight = 500
				"plate":
					sf.font_names = PackedStringArray(["Avenir Next", "Helvetica Neue", "Arial"])
					sf.font_weight = 600
				_:
					sf.font_names = PackedStringArray(["Avenir Next", "Helvetica Neue", "Arial Black", "Arial"])
					sf.font_weight = 800
			var fv := FontVariation.new()   # широкая разрядка — «вывеска»
			fv.base_font = sf
			fv.spacing_glyph = 1 if role == "body" else 3
			f = fv
		"led":
			var sf := SystemFont.new()
			if role == "body":
				sf.font_names = PackedStringArray(["Avenir Next", "Helvetica Neue", "Arial"])
				sf.font_weight = 500
			else:
				sf.font_names = PackedStringArray(["DIN Condensed", "Arial Narrow", "Arial"])
				sf.font_weight = 700
			f = sf
		_:
			f = Broadcast.font(role)
	_fonts[key] = f
	return f


static func accent() -> Color:
	match id():
		"neon":
			return NEON
		"led":
			return LED
	return Broadcast.AMBER


static func alert() -> Color:
	match id():
		"neon":
			return NEON_RED
		"led":
			return LED_RED
	return Broadcast.ALERT


## Цвет обычного текста.
static func text_colour() -> Color:
	match id():
		"neon":
			return Color(0.9, 0.98, 1.0)
		"led":
			return LED
	return Broadcast.TEXT


## Цвет текста по группе надписи: gold — на янтарной плашке B (отсчёт, FIGHT!, таймер, ярлык N0, комбо); alert — KO!,
## SUDDEN DEATH; event — удары и комбо в дикторе (цвет события); sub — строки табло под KO; text — подписи.
static func text_for(group: String, event: Color = Color.WHITE) -> Color:
	match id():
		"neon":
			match group:
				"gold", "sub":
					return NEON_AMBER
				"alert":
					return NEON_RED
				"event":
					return event
			return Color(0.9, 0.98, 1.0)
		"led":
			return LED_RED if group == "alert" else LED
	match group:
		"gold":
			return Broadcast.INK
		"text", "sub":
			return Broadcast.TEXT
	return Color.WHITE


# ---------------------------------------------------------------- подписи

## Подпись по роли скина: шрифт, размер, цвет, эффект — B плоско, A свечение (glow, по умолчанию — цвет текста),
## C свечение светодиодов и точки у крупных строк (size ≥ 34).
static func style_label(l: Label, role: String, size: int, colour: Color, glow: Color = Color(0, 0, 0, 0)) -> void:
	l.add_theme_font_override("font", font(role))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.material = null
	match id():
		"neon":
			var g := glow if glow.a > 0.0 else colour
			l.add_theme_color_override("font_color", colour.lerp(Color.WHITE, 0.55))
			l.add_theme_color_override("font_shadow_color", Color(g, 0.7))
			l.add_theme_constant_override("shadow_outline_size", maxi(3, size / 7))
		"led":
			l.add_theme_color_override("font_color", colour)
			l.add_theme_color_override("font_shadow_color", Color(colour, 0.4))
			l.add_theme_constant_override("shadow_outline_size", maxi(2, size / 12))
			if size >= 34:
				l.material = led_material(size)
		_:
			l.add_theme_color_override("font_color", colour)
			l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
			l.add_theme_constant_override("shadow_outline_size", 0)


## Материал точек LED под размер шрифта (шаг сетки ~ size / 15 px).
static func led_material(size: int) -> ShaderMaterial:
	var cell := clampf(roundf(float(size) / 15.0), 3.0, 9.0)
	if _led_mats.has(cell):
		return _led_mats[cell]
	var m := ShaderMaterial.new()
	m.shader = LED_SHADER
	m.set_shader_parameter("cell", cell)
	_led_mats[cell] = m
	return m


# ---------------------------------------------------------------- панели

## Панель по роли. tint — цвет игрока / события, mirror — правая сторона (наклон плашек B), group — для announce
## (gold / alert / event). Роли: player, timer, timer_sd, announce, n0, n0_tag, field, ko, ko_victim, ko_sub, combo,
## pip_on, pip_off, vote_box, vote_title.
static func panel(role: String, tint: Color = Color(0, 0, 0, 0), mirror: bool = false, group: String = "") -> StyleBox:
	match id():
		"neon":
			return _neon_panel(role, tint, group)
		"led":
			return _led_panel(role, tint, group)
	return _bc_panel(role, tint, mirror, group)


static func _bc_panel(role: String, tint: Color, mirror: bool, group: String) -> StyleBox:
	var s: BcStyle
	match role:
		"player":
			s = Broadcast.plate()
			s.mirror = mirror
			s.edge_color = tint
			s.edge_w = 10.0
			s.edge_side = 1 if mirror else -1
			s.underline_color = Broadcast.AMBER
			s.underline_h = 4.0
		"timer", "timer_sd":
			s = Broadcast.plate(Broadcast.AMBER if role == "timer" else Broadcast.ALERT, Broadcast.SKEW, 34.0, 2.0)
			s.underline_color = Broadcast.PLATE
			s.underline_h = 5.0
		"announce":
			var bg := Broadcast.PLATE
			if group == "gold":
				bg = Broadcast.AMBER
			elif group == "alert":
				bg = Broadcast.ALERT
			s = Broadcast.plate(bg, Broadcast.SKEW, 44.0, 0.0)
			if group == "event":
				s.edge_color = tint
				s.edge_w = 16.0
			s.underline_color = Color(0, 0, 0, 0.25)
			s.underline_h = 6.0
		"n0":
			s = Broadcast.plate(Broadcast.PLATE, 0.12, 0.0, 0.0)
			s.content_margin_right = 22.0
			s.underline_color = Broadcast.AMBER
			s.underline_h = 3.0
		"n0_tag":
			s = Broadcast.plate(Broadcast.AMBER, 0.12, 16.0, 0.0)
			s.shadow_alpha = 0.0
		"field":
			s = Broadcast.plate(Broadcast.PLATE, Broadcast.SKEW, 30.0, 6.0)
			s.edge_color = Broadcast.FIELD
			s.edge_w = 8.0
		"ko":
			s = Broadcast.plate(Broadcast.ALERT, Broadcast.SKEW, 70.0, 0.0)
			s.underline_color = Color(0, 0, 0, 0.3)
			s.underline_h = 12.0
		"ko_victim":
			s = Broadcast.plate(Broadcast.PLATE, Broadcast.SKEW, 30.0, 4.0)
			s.edge_color = tint
			s.edge_w = 12.0
		"ko_sub":
			s = Broadcast.plate(Broadcast.PLATE, Broadcast.SKEW, 34.0, 4.0)
			s.underline_color = Broadcast.AMBER
			s.underline_h = 5.0
		"combo":
			s = Broadcast.plate(Broadcast.AMBER, Broadcast.SKEW, 16.0, 2.0)
		"pip_on", "pip_off":
			s = Broadcast.plate(Broadcast.AMBER if role == "pip_on" else Broadcast.PLATE_LIGHT, 0.6, 0.0, 0.0)
			s.shadow_alpha = 0.0
			s.mirror = mirror
		"vote_box":
			s = Broadcast.plate(Broadcast.PLATE, 0.07, 34.0, 14.0)
			s.underline_color = Broadcast.AMBER
			s.underline_h = 5.0
		"vote_title":
			s = Broadcast.plate(Broadcast.AMBER, Broadcast.SKEW, 22.0, 0.0)
		_:
			s = Broadcast.plate()
	return s


## Стекло с неоновым краем и свечением (StyleBoxFlat: рамка + тень цветом рамки).
static func glass(border: Color, pad_x: float = 22.0, pad_y: float = 8.0, radius: int = 8, glow: int = 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.02, 0.035, 0.07, 0.72)
	s.border_color = Color(border, 0.9)
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(border, 0.42)
	s.shadow_size = glow
	s.anti_aliasing = true
	_pad(s, pad_x, pad_y)
	return s


static func _neon_panel(role: String, tint: Color, group: String) -> StyleBox:
	match role:
		"player", "ko_victim":
			return glass(tint, 24.0 if role == "ko_victim" else 22.0, 4.0)
		"timer":
			return glass(NEON, 30.0, 4.0)
		"timer_sd":
			return glass(NEON_RED, 30.0, 4.0)
		"announce":
			var e := StyleBoxEmpty.new()
			_pad(e, 30.0, 0.0)
			return e
		"n0":
			var s := glass(NEON, 0.0, 0.0, 10, 12)
			s.content_margin_right = 22.0
			s.content_margin_left = 6.0
			return s
		"n0_tag", "ko", "ko_sub", "vote_title":
			var e := StyleBoxEmpty.new()
			_pad(e, 14.0, 0.0)
			return e
		"field":
			return glass(NEON, 18.0, 6.0)
		"combo":
			return glass(NEON_AMBER, 12.0, 0.0, 6, 8)
		"pip_on", "pip_off":
			var p := StyleBoxFlat.new()
			p.bg_color = tint if role == "pip_on" else Color(0, 0, 0, 0)
			p.border_color = tint
			p.set_border_width_all(2)
			p.set_corner_radius_all(3)
			p.shadow_color = Color(tint, 0.6)
			p.shadow_size = 5
			return p
		"vote_box":
			return glass(NEON, 26.0, 14.0)
	return glass(NEON)


## Панель табло: почти чёрная, тонкая тёмная рамка, тень.
static func led_box(pad_x: float = 22.0, pad_y: float = 6.0, border: Color = Color(0.15, 0.16, 0.18), radius: int = 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.016, 0.018, 0.022, 0.95)
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = 8
	_pad(s, pad_x, pad_y)
	return s


static func _led_panel(role: String, _tint: Color, _group: String) -> StyleBox:
	match role:
		"player", "field", "ko_victim":
			return led_box(22.0, 4.0)
		"timer":
			return led_box(28.0, 2.0)
		"timer_sd":
			return led_box(28.0, 2.0, Color(0.45, 0.1, 0.08))
		"announce":
			return led_box(36.0, 2.0)
		"n0":
			var s := led_box(6.0, 0.0, Color(0.05, 0.23, 0.28), 14)
			s.bg_color = Color(0.012, 0.075, 0.1, 0.94)
			s.content_margin_right = 22.0
			return s
		"n0_tag", "ko", "ko_sub", "vote_title":
			var e := StyleBoxEmpty.new()
			_pad(e, 14.0, 0.0)
			return e
		"combo":
			return led_box(12.0, 0.0)
		"pip_on", "pip_off":
			var p := StyleBoxFlat.new()
			p.bg_color = LED if role == "pip_on" else Color(0.18, 0.12, 0.04)
			p.set_corner_radius_all(99)
			if role == "pip_on":
				p.shadow_color = Color(LED, 0.6)
				p.shadow_size = 5
			return p
		"vote_box":
			return led_box(26.0, 14.0)
	return led_box()


static func _pad(s: StyleBox, x: float, y: float) -> void:
	s.content_margin_left = x
	s.content_margin_right = x
	s.content_margin_top = y
	s.content_margin_bottom = y


## Цвет фона панели (хвостик облачка N0 и т. п.).
static func panel_bg(role: String) -> Color:
	var p := panel(role)
	if p is BcStyle:
		return (p as BcStyle).bg
	if p is StyleBoxFlat:
		return (p as StyleBoxFlat).bg_color
	return Color(0, 0, 0, 0)


# ---------------------------------------------------------------- тема

## Тема Root HUD боя: те же имена типов, что в hud_theme.tres (AnnounceLabel, DisplayLabel, WoodFrame, …).
static func theme() -> Theme:
	if _themes.has(id()):
		return _themes[id()]
	var t: Theme
	if id() == "broadcast":
		t = Broadcast.theme()
	else:
		t = _skin_theme()
	_themes[id()] = t
	return t


static func _skin_theme() -> Theme:
	var t := Theme.new()
	var neon := id() == "neon"
	var txt := text_colour()
	t.default_font = font("plate")
	t.default_font_size = 22
	t.set_color("font_color", "Label", txt)
	t.set_color("font_outline_color", "Label", Color(0.0, 0.01, 0.03, 0.85))
	t.set_constant("outline_size", "Label", 3)
	var frame: StyleBox = glass(NEON, 40.0, 26.0) if neon else led_box(40.0, 26.0)
	t.set_stylebox("panel", "PanelContainer", frame)
	t.set_type_variation("WoodFrame", "PanelContainer")
	t.set_stylebox("panel", "WoodFrame", frame)
	var normal: StyleBox = glass(NEON, 34.0, 10.0) if neon else led_box(34.0, 10.0, Color(0.35, 0.25, 0.08))
	var hover: StyleBox = glass(Color.WHITE, 34.0, 10.0) if neon else led_box(34.0, 10.0, LED)
	var pressed: StyleBox = glass(NEON_AMBER, 34.0, 10.0) if neon else led_box(34.0, 10.0, LED_RED)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", led_box(34.0, 10.0))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_font("font", "Button", font("display"))
	t.set_font_size("font_size", "Button", 28)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "Button", txt)
	t.set_color("font_disabled_color", "Button", Color(txt, 0.4))
	t.set_constant("outline_size", "Button", 0)
	for v in ["AnnounceLabel", "BrushLabel", "DisplayLabel", "SmallCaps", "StatLabel", "StatValue", "TimerLabel"]:
		t.set_type_variation(v, "Label")
	for v in ["AnnounceLabel", "BrushLabel", "DisplayLabel"]:
		t.set_font("font", v, font("display"))
		t.set_constant("outline_size", v, 0)
		t.set_color("font_shadow_color", v, Color(accent(), 0.6))
		t.set_constant("shadow_outline_size", v, 8 if neon else 4)
		t.set_constant("shadow_offset_x", v, 0)
		t.set_constant("shadow_offset_y", v, 0)
	t.set_font_size("font_size", "AnnounceLabel", 80)
	t.set_font_size("font_size", "BrushLabel", 80)
	t.set_font_size("font_size", "DisplayLabel", 38)
	t.set_font("font", "SmallCaps", font("plate"))
	t.set_font_size("font_size", "SmallCaps", 17)
	t.set_color("font_color", "SmallCaps", Color(txt, 0.7))
	t.set_font("font", "StatLabel", font("plate"))
	t.set_font_size("font_size", "StatLabel", 20)
	t.set_color("font_color", "StatLabel", Color(txt, 0.85))
	t.set_font("font", "StatValue", font("digits"))
	t.set_font_size("font_size", "StatValue", 26)
	t.set_color("font_color", "StatValue", txt)
	t.set_font("font", "TimerLabel", font("digits"))
	t.set_font_size("font_size", "TimerLabel", 54)
	t.set_color("font_color", "TimerLabel", txt)
	t.set_constant("outline_size", "TimerLabel", 0)
	return t
