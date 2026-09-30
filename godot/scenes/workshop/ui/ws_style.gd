## Стиль мастерской v0.3 (UI/UX spec v0.3): «ручная индустриальная мастерская» — тёмное морёное дерево, старый металл, латунь,
## тёплый янтарный свет. v0.2 обводил каждую плашку толстой доской — экран читался как рама на раме; здесь иерархия материалов
## тонкая: кромки 1–2 px (латунь — панели и кнопки, сталь — вкладки, дерево — карточки деталей), заливки тёмные и полупрозрачные
## (сцена мастерской просвечивает), радиус 4–7, мягкая тень 4–8 px. Свечение — только как информация: янтарная кромка и ореол —
## «выбрано»; нажатие — подложка темнее и содержимое на 2 px ниже (поля стиля), тень короче; выключенное — тусклое.
## Смысловые цвета (не декор): белый / бледно-голубой — разъём, нейтральное; золото / янтарь — энергия, выбор; зелёный — можно;
## красный — нельзя, не хватает энергии, удалить; фиолетовый — будущая экзотика NULL.
## Каждая фабрика отдаёт НОВЫЙ StyleBoxFlat — правка одного (поля, кромка) не задевает другие кнопки.
## Регистр текста не меняем (спека: без КАПСА — заглавными только табличка МАСТЕРСКАЯ, и то текстом сцены).
class_name WsStyle
extends RefCounted

const WOOD_DARK := Color(0.078, 0.06, 0.047)
const WOOD := Color(0.2, 0.145, 0.1)
const BRASS := Color(0.8, 0.62, 0.36)
const STEEL := Color(0.58, 0.63, 0.68)
const AMBER := Color(1.0, 0.74, 0.3)
const GREEN := Color(0.5, 0.84, 0.42)
const RED := Color(0.93, 0.33, 0.26)
const PALE_BLUE := Color(0.72, 0.86, 1.0)
const PURPLE := Color(0.7, 0.52, 0.96)
const TEXT := Color(0.96, 0.9, 0.78)
const TEXT_DIM := Color(0.74, 0.67, 0.57)
const TEXT_FAINT := Color(0.5, 0.45, 0.39)
## Текст «выбрано» — светлый янтарь (чистый AMBER на янтарной подложке теряется).
const TEXT_SELECTED := Color(1.0, 0.86, 0.56)
const TEXT_ON_PLATE := Color(1.0, 0.97, 0.92)
## Типографика: L — только табличка МАСТЕРСКАЯ; M — имя сборки, категория, выбранная деталь; S — цифры и основной мелкий текст;
## XS — клавиши, подписи чипов.
const SIZE_L := 34
const SIZE_M := 22
const SIZE_S := 17
const SIZE_XS := 14
## Насколько «нажатая» подложка опускает содержимое (px).
const PRESS_DROP := 2.0

const STATES := ["normal", "hover", "pressed", "selected", "disabled"]


# ------------------------------------------------------------------ панели

## Основная панель: тёмное морёное дерево на просвет, тонкая латунная кромка, мягкая тень.
static func panel() -> StyleBoxFlat:
	var s := _flat(Color(WOOD_DARK, 0.9), Color(BRASS, 0.42), 1, 7, 16, 14)
	return _shadow(s, Color(0, 0, 0, 0.42), 8, Vector2(0, 4))


## Секция внутри панели: почти невидимая — чуть темнее и волосяная светлая кромка.
static func panel_inset() -> StyleBoxFlat:
	return _flat(Color(0, 0, 0, 0.2), Color(1.0, 0.92, 0.78, 0.07), 1, 5, 12, 8)


## Всплывашка (шаблоны, сохранить, совместимый разъём): плотнее панели, кромка ярче — поверх всего.
static func popup() -> StyleBoxFlat:
	var s := _flat(Color(0.095, 0.074, 0.058, 0.97), Color(BRASS, 0.72), 1, 7, 18, 14)
	return _shadow(s, Color(0, 0, 0, 0.55), 8, Vector2(0, 4))


# ------------------------------------------------------------------ кнопки

## Обычная кнопка (сохранить, отмена, действия с деталью): дерево + латунная кромка.
static func button(state := "normal") -> StyleBoxFlat:
	match _state(state, STATES):
		"hover":
			return _shadow(_flat(Color(0.2, 0.15, 0.105, 0.96), Color(BRASS, 0.8), 1, 5, 12, 6), Color(0, 0, 0, 0.42), 6, Vector2(0, 3))
		"pressed":
			return _lower(_shadow(_flat(Color(0.105, 0.08, 0.06, 0.96), Color(BRASS, 0.5), 1, 5, 12, 6), Color(0, 0, 0, 0.3), 2, Vector2(0, 1)))
		"selected":
			return _shadow(_flat(Color(0.24, 0.16, 0.08, 0.96), AMBER, 1, 5, 12, 6), Color(AMBER, 0.26), 6, Vector2.ZERO)
		"disabled":
			return _flat(Color(0.12, 0.1, 0.085, 0.55), Color(TEXT_FAINT, 0.28), 1, 5, 12, 6)
	return _shadow(_flat(Color(0.155, 0.117, 0.086, 0.94), Color(BRASS, 0.42), 1, 5, 12, 6), Color(0, 0, 0, 0.35), 4, Vector2(0, 2))


## Вкладка: маленькая плашка со стальной кромкой (холодный металл отличает навигацию от действий).
static func tab(state := "normal") -> StyleBoxFlat:
	match _state(state, STATES):
		"hover":
			return _flat(Color(0.17, 0.135, 0.105, 0.94), Color(STEEL, 0.6), 1, 5, 12, 6)
		"pressed":
			return _lower(_flat(Color(0.085, 0.07, 0.058, 0.94), Color(STEEL, 0.4), 1, 5, 12, 6))
		"selected":
			return _shadow(_flat(Color(0.22, 0.15, 0.075, 0.96), AMBER, 1, 5, 12, 6), Color(AMBER, 0.22), 5, Vector2.ZERO)
		"disabled":
			return _flat(Color(0.1, 0.085, 0.075, 0.5), Color(STEEL, 0.12), 1, 5, 12, 6)
	return _flat(Color(0.12, 0.1, 0.085, 0.9), Color(STEEL, 0.28), 1, 5, 12, 6)


## Главная кнопка ИСПЫТАТЬ: тёплая медная пластина с янтарной кромкой (кромка растворяется в заливке — фаска металла),
## важная, но не гигантская; белый текст.
static func cta(state := "normal") -> StyleBoxFlat:
	var s: StyleBoxFlat
	match _state(state, STATES):
		"hover":
			s = _shadow(_flat(Color(0.7, 0.37, 0.15), Color(1.0, 0.8, 0.46), 2, 6, 26, 10), Color(1.0, 0.6, 0.2, 0.3), 8, Vector2(0, 2))
		"pressed":
			s = _lower(_shadow(_flat(Color(0.48, 0.24, 0.1), Color(0.84, 0.54, 0.28), 2, 6, 26, 10), Color(0, 0, 0, 0.4), 2, Vector2(0, 1)))
		"selected":
			s = _shadow(_flat(Color(0.7, 0.37, 0.15), AMBER, 2, 6, 26, 10), Color(AMBER, 0.4), 8, Vector2.ZERO)
		"disabled":
			s = _flat(Color(0.26, 0.19, 0.145, 0.72), Color(0.5, 0.38, 0.28, 0.45), 2, 6, 26, 10)
		_:
			s = _shadow(_flat(Color(0.61, 0.315, 0.13), Color(0.98, 0.68, 0.36), 2, 6, 26, 10), Color(0, 0, 0, 0.5), 6, Vector2(0, 3))
	s.border_blend = true
	return s


## Разрушительное действие (удалить): в покое — тёмное дерево с красной кромкой (не кричит рядом с обычными), наведение — красная
## подложка и ореол.
static func danger(state := "normal") -> StyleBoxFlat:
	match _state(state, STATES):
		"hover":
			return _shadow(_flat(Color(0.37, 0.11, 0.08, 0.96), RED, 1, 5, 12, 6), Color(RED, 0.25), 6, Vector2(0, 2))
		"pressed":
			return _lower(_shadow(_flat(Color(0.2, 0.065, 0.05, 0.96), Color(RED, 0.7), 1, 5, 12, 6), Color(0, 0, 0, 0.3), 2, Vector2(0, 1)))
		"selected":
			return _shadow(_flat(Color(0.37, 0.11, 0.08, 0.96), RED, 2, 5, 12, 6), Color(RED, 0.3), 6, Vector2.ZERO)
		"disabled":
			return _flat(Color(0.15, 0.1, 0.09, 0.5), Color(RED, 0.2), 1, 5, 12, 6)
	return _shadow(_flat(Color(0.165, 0.076, 0.062, 0.94), Color(RED, 0.45), 1, 5, 12, 6), Color(0, 0, 0, 0.35), 4, Vector2(0, 2))


## Чип категории / фильтра: компактная плашка; выбранный — янтарь.
static func chip(state := "normal") -> StyleBoxFlat:
	match _state(state, STATES):
		"hover":
			return _flat(Color(0.17, 0.13, 0.1, 0.92), Color(BRASS, 0.65), 1, 6, 10, 3)
		"pressed":
			return _lower(_flat(Color(0.095, 0.075, 0.06, 0.92), Color(BRASS, 0.45), 1, 6, 10, 3), 1.0)
		"selected":
			return _shadow(_flat(Color(0.3, 0.2, 0.08, 0.95), AMBER, 1, 6, 10, 3), Color(AMBER, 0.2), 3, Vector2.ZERO)
		"disabled":
			return _flat(Color(0.1, 0.085, 0.07, 0.5), Color(BRASS, 0.12), 1, 6, 10, 3)
	return _flat(Color(0.13, 0.1, 0.078, 0.88), Color(BRASS, 0.3), 1, 6, 10, 3)


# ------------------------------------------------------------------ карточки и поля

## Карточка детали: тёмная, деревянная кромка; наведение — кромка светлее и тень «приподнимает»; выбрана — янтарь; dim — не
## влезает по энергии / несовместима (тусклая, без тени).
static func card(state := "normal") -> StyleBoxFlat:
	match _state(state, ["normal", "hover", "selected", "dim"]):
		"hover":
			return _shadow(_flat(Color(0.14, 0.108, 0.082, 0.96), Color(0.68, 0.51, 0.31), 1, 6, 8, 8), Color(0, 0, 0, 0.5), 8, Vector2(0, 4))
		"selected":
			return _shadow(_flat(Color(0.16, 0.115, 0.07, 0.97), AMBER, 2, 6, 8, 8), Color(AMBER, 0.3), 6, Vector2.ZERO)
		"dim":
			return _flat(Color(0.085, 0.07, 0.06, 0.7), Color(0.32, 0.25, 0.19, 0.5), 1, 6, 8, 8)
	return _shadow(_flat(Color(0.105, 0.082, 0.064, 0.94), Color(0.42, 0.3, 0.19, 0.9), 1, 6, 8, 8), Color(0, 0, 0, 0.38), 4, Vector2(0, 2))


## Поле ввода: тёмная утопленная подложка; фокус — янтарная кромка (LineEdit рисует focus ПОВЕРХ normal — без заливки).
static func field(state := "normal") -> StyleBoxFlat:
	match _state(state, ["normal", "hover", "focus", "disabled"]):
		"hover":
			return _flat(Color(0.04, 0.033, 0.028, 0.92), Color(0.56, 0.44, 0.3, 0.8), 1, 5, 10, 6)
		"focus":
			var f := _shadow(_flat(Color(0, 0, 0, 0), AMBER, 1, 5, 10, 6), Color(AMBER, 0.2), 4, Vector2.ZERO)
			f.draw_center = false
			return f
		"disabled":
			return _flat(Color(0.05, 0.042, 0.036, 0.5), Color(TEXT_FAINT, 0.25), 1, 5, 10, 6)
	return _flat(Color(0.04, 0.033, 0.028, 0.92), Color(0.42, 0.33, 0.23, 0.6), 1, 5, 10, 6)


## Подложка по имени: button | tab | cta | danger | chip | card | field | panel | inset | popup.
static func box(kind: String, state := "normal") -> StyleBoxFlat:
	match kind:
		"tab":
			return tab(state)
		"cta":
			return cta(state)
		"danger":
			return danger(state)
		"chip":
			return chip(state)
		"card":
			return card(state)
		"field":
			return field(state)
		"panel":
			return panel()
		"inset":
			return panel_inset()
		"popup":
			return popup()
	return button(state)


## Цвет текста кнопки вида kind в состоянии state (normal | hover | pressed | selected | disabled).
static func text_color(kind: String, state := "normal") -> Color:
	var st := _state(state, STATES)
	match kind:
		"cta":
			return {"hover": Color(1, 1, 1), "pressed": Color(0.95, 0.88, 0.8), "disabled": Color(0.6, 0.53, 0.46)}.get(st, TEXT_ON_PLATE)
		"danger":
			return {"hover": Color(1, 0.93, 0.9), "pressed": Color(0.95, 0.74, 0.68), "selected": Color(1, 0.93, 0.9),
				"disabled": Color(0.55, 0.42, 0.38)}.get(st, Color(1.0, 0.8, 0.74))
		"tab", "chip":
			return {"hover": TEXT, "pressed": TEXT, "selected": TEXT_SELECTED, "disabled": TEXT_FAINT}.get(st, TEXT_DIM)
	return {"hover": Color(1, 0.96, 0.88), "selected": TEXT_SELECTED, "disabled": TEXT_FAINT}.get(st, TEXT)


# ------------------------------------------------------------------ применение

## Все состояния кнопки разом: normal / hover / pressed / hover_pressed / disabled, focus пустой (рамка фокуса Godot чужая стилю),
## цвета текста и иконок. Вкладка, чип и любой toggle_mode: «нажато» = выбрано (янтарь) — toggle_mode ставить ДО вызова.
## Размер шрифта — только если у кнопки его ещё нет (размер из сцены сильнее): cta — M, chip — XS, остальные — S.
static func apply_button(b: Button, kind := "button") -> void:
	var on := "selected" if b.toggle_mode or kind == "tab" or kind == "chip" else "pressed"
	b.add_theme_stylebox_override("normal", box(kind, "normal"))
	b.add_theme_stylebox_override("hover", box(kind, "hover"))
	b.add_theme_stylebox_override("pressed", box(kind, on))
	b.add_theme_stylebox_override("hover_pressed", box(kind, on))
	b.add_theme_stylebox_override("disabled", box(kind, "disabled"))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var cols := {"": "normal", "hover_": "hover", "pressed_": on, "hover_pressed_": on, "focus_": "normal", "disabled_": "disabled"}
	for pre in cols:
		var c := text_color(kind, String(cols[pre]))
		b.add_theme_color_override("font_%scolor" % pre, c)
		b.add_theme_color_override("icon_%scolor" % ("normal_" if pre == "" else pre), c)
	if not b.has_theme_font_size_override("font_size"):
		b.add_theme_font_size_override("font_size", SIZE_M if kind == "cta" else (SIZE_XS if kind == "chip" else SIZE_S))
	if not b.has_theme_constant_override("h_separation"):
		b.add_theme_constant_override("h_separation", 8)


## Подложка PanelContainer / Panel: panel | inset | popup | card (неизвестное — panel).
static func apply_panel(p: Control, kind := "panel") -> void:
	var sb: StyleBoxFlat = panel()
	match kind:
		"inset":
			sb = panel_inset()
		"popup":
			sb = popup()
		"card":
			sb = card()
	p.add_theme_stylebox_override("panel", sb)


static func apply_field(e: LineEdit) -> void:
	e.add_theme_stylebox_override("normal", field("normal"))
	e.add_theme_stylebox_override("focus", field("focus"))
	e.add_theme_stylebox_override("read_only", field("disabled"))
	e.add_theme_color_override("font_color", TEXT)
	e.add_theme_color_override("font_placeholder_color", TEXT_FAINT)
	e.add_theme_color_override("font_uneditable_color", TEXT_FAINT)
	e.add_theme_color_override("font_selected_color", Color(1, 1, 1))
	e.add_theme_color_override("selection_color", Color(AMBER, 0.35))
	e.add_theme_color_override("caret_color", AMBER)
	e.add_theme_color_override("clear_button_color", TEXT_DIM)
	e.add_theme_color_override("clear_button_color_pressed", AMBER)
	if not e.has_theme_font_size_override("font_size"):
		e.add_theme_font_size_override("font_size", SIZE_S)


## Подпись: размер из шкалы (SIZE_L / M / S / XS), тёплый белый или приглушённый; тень 1 px — читается на просвечивающей панели.
static func label(l: Label, size := SIZE_S, dim := false) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", TEXT_DIM if dim else TEXT)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 1)


## Четыре латунные заклёпки по углам (только главные панели — «заклёпки мелкие и не везде»): рисуются поверх подложки узла.
static func rivets(c: Control, inset := 7.0, r := 1.8) -> void:
	c.draw.connect(func() -> void:
		for q in [Vector2(inset, inset), Vector2(c.size.x - inset, inset), Vector2(inset, c.size.y - inset),
				Vector2(c.size.x - inset, c.size.y - inset)]:
			c.draw_circle(q + Vector2(0, 0.7), r, Color(0, 0, 0, 0.5), true, -1.0, true)
			c.draw_circle(q, r, BRASS.darkened(0.25), true, -1.0, true)
			c.draw_circle(q - Vector2(r, r) * 0.3, r * 0.42, Color(1.0, 0.93, 0.78, 0.55), true, -1.0, true))
	c.queue_redraw()


# ------------------------------------------------------------------ внутреннее

static func _flat(bg: Color, edge: Color, edge_w: int, radius: int, mx: float, my: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(edge_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = mx
	s.content_margin_right = mx
	s.content_margin_top = my
	s.content_margin_bottom = my
	s.anti_aliasing = true
	return s


static func _shadow(s: StyleBoxFlat, col: Color, size: int, off: Vector2) -> StyleBoxFlat:
	s.shadow_color = col
	s.shadow_size = size
	s.shadow_offset = off
	return s


## «Нажато»: содержимое ниже на PRESS_DROP (сумма полей та же — кнопка не прыгает по размеру).
static func _lower(s: StyleBoxFlat, drop := PRESS_DROP) -> StyleBoxFlat:
	s.content_margin_top += drop
	s.content_margin_bottom = maxf(s.content_margin_bottom - drop, 0.0)
	return s


static func _state(state: String, allowed: Array) -> String:
	if allowed.has(state):
		return state
	push_warning("WsStyle: нет состояния «%s» (есть: %s)" % [state, ", ".join(PackedStringArray(allowed))])
	return "normal"
