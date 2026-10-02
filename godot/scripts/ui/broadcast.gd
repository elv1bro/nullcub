## Эфирный графпакет NULL League — HUD боя в стиле «Трансляция Лиги» (вариант B, выбран автором 02.10.2026; макет и
## сравнение с неоном и LED — docs/plan-demo/HUD_SKINS.md). Тёмные косые плашки (BcStyle), плотные цвета игроков,
## узкий жирный шрифт (курсив — у крупных надписей), янтарная полоса зала. Здесь цвета, шрифты, фабрика плашек и тема
## HUD боя (theme() — Root в scenes/ui/hud.tscn; старая деревянная тема hud_theme.tres остаётся мастерской и меню).
## Шрифты — системные (SystemFont): на Mac — DIN Condensed Bold (подписи, имена, цифры; есть кириллица), Avenir Next Condensed
## Heavy Italic (крупные латинские надписи; кириллицы нет — буквы берутся из DIN через fallbacks), Avenir Next (реплики N0),
## иначе узкий Arial. PT Sans Narrow не подходит: Godot открывает вместо него обычный PT Sans. Для релиза положить в проект
## свободный шрифт с кириллицей (вопрос автору в HUD_SKINS.md).
class_name Broadcast
extends RefCounted

const PLATE := Color(0.04, 0.063, 0.118, 0.93)        # тёмно-синяя плашка
const PLATE_LIGHT := Color(0.11, 0.153, 0.259, 1.0)   # дорожка полосы здоровья, выключенные метки
const AMBER := Color(0.941, 0.667, 0.145)              # янтарь зала (свет ферм, полоса эфира)
const INK := Color(0.06, 0.06, 0.07)                   # тёмный текст на янтаре
const TEXT := Color(0.97, 0.97, 0.98)
const MUTED := Color(0.64, 0.69, 0.78)
const FIELD := Color(0.27, 0.89, 1.0)                  # цвет поля NULL (индикатор гравитации)
const ALERT := Color(0.86, 0.13, 0.11)                 # KO, Sudden Death
const SKEW := 0.21                                     # tan 12°: наклон плашек

static var _fonts := {}
static var _theme: Theme


## Шрифт по роли: plate — имена и подписи, display — крупные надписи (курсив), digits — цифры табло, body — реплики N0.
static func font(role: String) -> Font:
	if _fonts.has(role):
		return _fonts[role]
	var f := SystemFont.new()
	match role:
		"display":
			f.font_names = PackedStringArray(["Avenir Next Condensed", "Arial Narrow", "Roboto Condensed", "DejaVu Sans Condensed", "Arial"])
			f.font_weight = 800
			f.font_italic = true
		"digits":
			f.font_names = PackedStringArray(["DIN Condensed", "Avenir Next Condensed", "Arial Narrow", "Roboto Condensed", "Arial"])
			f.font_weight = 700
		"body":
			f.font_names = PackedStringArray(["Avenir Next", "Helvetica Neue", "Segoe UI", "Roboto", "Arial"])
			f.font_weight = 500
		_:
			f.font_names = PackedStringArray(["DIN Condensed", "Arial Narrow", "Roboto Condensed", "DejaVu Sans Condensed", "Arial"])
			f.font_weight = 700
	_fonts[role] = f
	if role != "plate":
		f.fallbacks = [font("plate")]   # нет кириллицы (Avenir Next Condensed) — буквы из DIN Condensed, а не тонкие системные
	return f


## Плашка: фон, наклон, поля под содержимое (по горизонтали — с запасом на наклон).
static func plate(bg: Color = PLATE, skew: float = SKEW, pad_x: float = 26.0, pad_y: float = 6.0) -> BcStyle:
	var s := BcStyle.new()
	s.bg = bg
	s.skew = skew
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	return s


## Тема HUD боя: те же имена типов, что в hud_theme.tres (AnnounceLabel, DisplayLabel, WoodFrame, …) — сцены HUD не меняются.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font("plate")
	t.default_font_size = 22
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0.02, 0.03, 0.06, 0.85))
	t.set_constant("outline_size", "Label", 4)
	t.set_stylebox("panel", "PanelContainer", plate())
	t.set_type_variation("WoodFrame", "PanelContainer")
	var frame := plate(PLATE, 0.04, 40.0, 26.0)
	frame.underline_color = AMBER
	frame.underline_h = 6.0
	t.set_stylebox("panel", "WoodFrame", frame)
	# кнопки: тёмная плашка с янтарным краем; наведение — край шире, нажатие — янтарь
	var normal := plate(PLATE, SKEW, 34.0, 10.0)
	normal.edge_color = AMBER
	normal.edge_w = 8.0
	var hover := plate(PLATE_LIGHT, SKEW, 34.0, 10.0)
	hover.edge_color = AMBER
	hover.edge_w = 16.0
	var pressed := plate(AMBER, SKEW, 34.0, 10.0)
	var disabled := plate(Color(PLATE, 0.6), SKEW, 34.0, 10.0)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_font("font", "Button", font("display"))
	t.set_font_size("font_size", "Button", 30)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(TEXT, 0.5))
	t.set_constant("outline_size", "Button", 0)
	for v in ["AnnounceLabel", "BrushLabel", "DisplayLabel", "SmallCaps", "StatLabel", "StatValue", "TimerLabel"]:
		t.set_type_variation(v, "Label")
	for v in ["AnnounceLabel", "BrushLabel"]:
		t.set_font("font", v, font("display"))
		t.set_constant("outline_size", v, 10)
		t.set_color("font_outline_color", v, Color(0.02, 0.03, 0.06, 0.95))
	t.set_font_size("font_size", "AnnounceLabel", 84)
	t.set_font_size("font_size", "BrushLabel", 84)
	t.set_font("font", "DisplayLabel", font("display"))
	t.set_font_size("font_size", "DisplayLabel", 40)
	t.set_constant("outline_size", "DisplayLabel", 5)
	t.set_font("font", "SmallCaps", font("plate"))
	t.set_font_size("font_size", "SmallCaps", 18)
	t.set_color("font_color", "SmallCaps", MUTED)
	t.set_constant("outline_size", "SmallCaps", 2)
	t.set_font("font", "StatLabel", font("plate"))
	t.set_font_size("font_size", "StatLabel", 22)
	t.set_color("font_color", "StatLabel", Color(0.86, 0.88, 0.93))
	t.set_constant("outline_size", "StatLabel", 2)
	t.set_font("font", "StatValue", font("digits"))
	t.set_font_size("font_size", "StatValue", 28)
	t.set_color("font_color", "StatValue", TEXT)
	t.set_constant("outline_size", "StatValue", 2)
	t.set_font("font", "TimerLabel", font("digits"))
	t.set_font_size("font_size", "TimerLabel", 58)
	t.set_color("font_color", "TimerLabel", INK)
	t.set_constant("outline_size", "TimerLabel", 0)
	_theme = t
	return t
