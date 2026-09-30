## UI мастерской v0.3 (docs/plan-demo/WORKSHOP_V3.md §9, спецификация UI/UX v0.3): боец — в центре и занимает 55–65 % экрана,
## интерфейс только помогает его собрать; ощущение — верстак и конструктор, не RPG-инвентарь и не таблица.
##   верх — одна строка: [⚙ Мастерская] (клавиши) · ‹ имя сборки › (клик — шаблоны Робот / Паук / Длинная рука / Вертушка / Пустой
##     и переименование; стрелки листают все шаблоны) · ⚡ 40 / 100 (при протяжке «40 → 44», красное — не встанет) · ↶ ↷ · [Мои сборки]
##     (список и «Сохранить копию»; обычное сохранение — автосейв);
##   слева библиотека — только найти деталь: поиск (имя, вид, материал, теги — PartNames.search_text), фильтр-всплывашка (влезает,
##     избранное, недавние, масса, материал, сортировка), один ряд значков категорий с подсказками (Все, Ядро, Головы, Конечности,
##     Шарниры, Кисти и стопы, Оружие, Броня, Материал, Декор и покраска); поиск и категории стоят, листается только сетка — две
##     колонки крупных карточек (part_card.gd): картинка, имя для игрока, ⚡ и кг, ☆ избранное;
##   справа — одна маленькая контекстная панель: ничего не выбрано — сводка (имя, масса, детали, разгон, энергия, [Физика]); при
##     протяжке — «было → станет»; выбрана деталь — паспорт (масса, энергия, длина; деталь / ветка; шарнир; тяга — / ЛКМ / ПКМ;
##     Копия D, Зеркало M, Снять Del); вид «Оружие» — верстак;
##   низ: подсказка по ситуации одной строкой (WorkshopBuild.context_help) и «Испытать T» по центру под бойцом.
## В испытании — плашка «Испытание», счёт урона, табличка HP над манекеном и цифры урона в точке удара.
## Размеры — в базовом вьюпорте 1920×1080 (project.godot: stretch canvas_items); стиль — WsStyle, значки — WsIcon.
extends CanvasLayer

const PartCard := preload("res://scenes/workshop/ui/part_card.gd")
const MaterialCard := preload("res://scenes/workshop/ui/material_card.gd")
const JointCard := preload("res://scenes/workshop/ui/joint_card.gd")
const PaintPanel := preload("res://scenes/workshop/ui/paint_panel.gd")

## Имена шаблонов для игрока.
const PRESET_SHORT := {
	"human": "Человек", "spider": "Паук из клёна", "long_arm": "Длинная рука", "big_arm": "Силач", "legless": "Безногий", "junk": "Хлам",
	"flail": "Кистень", "kit_human": "Кукла-кит", "kit_brawler": "Громила", "kit_bot": "Робот", "kit_horned": "Рогатый",
	"kit_king": "Король", "kit_spider": "Паук", "kit_devil": "Чёртик", "kit_skull": "Скелет", "kit_wheels": "Каталка",
	"kit_lantern": "Фонарщик", "kit_graffiti": "Граффити", "kit_camo": "Камуфляж", "kit_spinner": "Вертушка", "kit_empty": "Пустой",
	"mallet": "Киянка", "hammer": "Молот", "spiked_hammer": "С гвоздями", "heavy_hammer": "Тяжёлый молот",
	"long_hammer": "Длинный молот", "sword": "Меч", "axe": "Топор", "concept_hammer": "Концепт",
}
## Шаблоны во всплывашке имени (v0.3 §5): [пресет, деталь-картинка].
const TEMPLATES := [["kit_bot", "kit_head_bot"], ["kit_spider", "kit_limb_basic_l"], ["long_arm", "wood_upper_arm"],
	["kit_spinner", "head_mace_ball"], ["kit_empty", "kit_core_ball"]]
## Категории библиотеки тела (v0.3 §9): один ряд значков. tool — инструмент вкладки над деталями (кисть материала, шарнир),
## alt — вторая вкладка той же категории (Декор | Покраска). Ударные навершия и моды встают и на тело — категория «Оружие».
const CATS := [
	{"id": "all", "title": "Все детали", "icon": "all",
		"kinds": ["core", "head", "limb", "hand", "foot", "joint", "chain", "plate", "armor", "weapon_head", "mod", "deco"]},
	{"id": "core", "title": "Ядро", "icon": "body", "kinds": ["core"]},
	{"id": "head", "title": "Головы", "icon": "head", "kinds": ["head"]},
	{"id": "limb", "title": "Конечности", "icon": "limb", "kinds": ["limb"]},
	{"id": "joint", "title": "Шарниры и цепи", "icon": "joint", "kinds": ["joint", "chain"], "tool": "joint"},
	{"id": "end", "title": "Кисти и стопы", "icon": "hand", "kinds": ["hand", "foot"]},
	{"id": "weapon", "title": "Оружие", "icon": "weapon", "kinds": ["weapon_head", "mod"]},
	{"id": "armor", "title": "Броня", "icon": "armor", "kinds": ["plate", "armor"]},
	# активные блоки (docs/plan-demo/ACTIVE_BLOCKS.md): вид deco с действием на клавише канала — only, CraftEdit.shelf_allows
	{"id": "active", "title": "Активные блоки", "icon": "energy", "kinds": ["deco"], "only": "active"},
	{"id": "mat", "title": "Материал", "icon": "material", "kinds": [], "tool": "material"},
	{"id": "deco", "title": "Декор и покраска", "icon": "decor", "kinds": ["deco"], "alt": "paint", "only": "passive"},
]
## Вкладка «Покраска» — вторая у «Декора» (shelf_tab["body"] == "paint").
const PAINT_TAB := {"id": "paint", "title": "Покраска", "icon": "paint", "kinds": [], "tool": "paint"}
## Верстак оружия: первая — назад к бойцу.
const WCATS := [
	{"id": "w_all", "title": "Все детали оружия", "icon": "all", "kinds": ["handle", "weapon_head", "mod", "chain"]},
	{"id": "handle", "title": "Рукояти", "icon": "limb", "kinds": ["handle"]},
	{"id": "weapon_head", "title": "Навершия", "icon": "weapon", "kinds": ["weapon_head"]},
	{"id": "mod", "title": "Моды", "icon": "gear", "kinds": ["mod"]},
	{"id": "chain", "title": "Цепь", "icon": "joint", "kinds": ["chain"]},
]
## Группы внутри категории: [заголовок, условие по PartDef].
const GROUPS := {
	"limb": [["Руки", "arm"], ["Ноги", "leg"]],
	"end": [["Кисти", "hand"], ["Стопы", "foot"]],
	"weapon": [["Навершия", "weapon_head"], ["Моды", "mod"]],
	"armor": [["Щитки", "plate"], ["Броня", "armor"]],
}
const SORTS := ["Энергия", "Масса", "Имя"]
## Разъёмы словами (кроме групп мышц CraftEdit.GROUP_TITLES).
const ANCHOR_WORDS := {"Face": "боёк", "End": "конец", "Side": "бок", "Top": "макушка", "Back": "спина", "Deco": "накладка",
	"Plate": "щиток", "Head": "навершие", "Mod": "мод", "Tip": "кончик", "Grip": "хват", "Spike": "шип", "Neck": "шея"}
const TOOL_HINTS := {
	"material": "Выбери материал и кликай по деталям бойца",
	"joint": "Выбери шарнир и кликай по детали",
}
const PULL_TITLES := {"": "—", "lmb": "ЛКМ", "rmb": "ПКМ"}
const PREFS := "user://workshop_prefs.cfg"
## Раскладка (база 1920×1080).
const PAD := 16.0
const TOP_Y := 12.0
const TOP_H := 58.0
const LEFT_W := 424.0
const RIGHT_W := 300.0
const TEST_W := 252.0
const TEST_H := 56.0
const TOAST_HOLD_S := 1.7
const TOAST_FADE_S := 0.3
const FLOAT_S := 1.1
const FLOAT_RISE := 90.0
const CHIP := 36.0

var ctl: WorkshopBuild
var icons: PartIcons
var shelf_tab := {"body": "all", "weapon": "w_all"}
var favorites: PackedStringArray = []
var filters := {"fits": false, "fav": false, "recent": false, "sort": 0, "mass": "", "mat": ""}
var _cards: Dictionary = {}          # part id -> карточка
var _tool_cards: Dictionary = {}     # id материала / тип шарнира -> плашка инструмента текущей вкладки
var _tool := ""                      # инструмент вкладки: "material" | "joint" | "paint" | ""
var _cat_buttons: Dictionary = {}    # id категории -> кнопка
var _hint_t := 0.0
var _toast_tween: Tween
var _dmg_total := 0.0
var _dmg_hits := 0
var _last_hit := ""
var _dmg_best := 0.0
var _live_card := ""
var _energy_shown := Vector3i(-1, -1, -2)

@onready var root: Control = $Root
@onready var overlay: Control = $Root/Overlay
@onready var floaters: Control = $Root/Floaters
@onready var toast_label: Label = $Root/Toast
@onready var test_bar: Control = $Root/TestBar
@onready var back_button: Button = $Root/TestBar/BackButton
@onready var test_stats: PanelContainer = $Root/TestStats
@onready var test_stats_text: Label = $Root/TestStats/Text
@onready var dummy_panel: Control = $Root/DummyPanel
@onready var dummy_hp: HpBar = $Root/DummyPanel/Hp
@onready var dummy_hp_text: Label = $Root/DummyPanel/HpText

# верх
var top_bar: PanelContainer
var title_button: Button
var prev_template: Button
var next_template: Button
var name_button: Button
var energy_icon: WsIcon
var energy_value: Label
var energy_bar: Control
var undo_button: Button
var redo_button: Button
var builds_button: Button
# библиотека
var left: PanelContainer
var search: LineEdit
var filter_button: Button
var cats_row: HBoxContainer
var sub_row: HBoxContainer
var shelf_scroll: ScrollContainer
var tool_hint: Label
var tools_box: GridContainer
var shelf: VBoxContainer
var presets_box: Control             # шаблоны — во всплывашке имени (проба покраски: на вкладке покраски не видны)
# справа
var right: PanelContainer
var summary_box: VBoxContainer
var summary_title: Label
var summary_rows: GridContainer
var problems: Label
var physics_button: Button
var physics_info: Label
var part_box: VBoxContainer
var part_icon: TextureRect
var part_title: Label
var part_where: Label
var part_rows: GridContainer
var branch_row: HBoxContainer
var joint_row: HFlowContainer
var pull_row: HBoxContainer
var part_actions: HBoxContainer
var part_desc: Label
var channel_row: HBoxContainer
var weapon_box: VBoxContainer
var weapon_name: Label
var wstats: GridContainer
var wproblems: Label
var equip_button: Button
var clear_button: Button
# низ, всплывашки
var test_button: Button
var help_line: Label
var drag_info: PanelContainer
var drag_info_text: RichTextLabel
var dismiss: Control
var templates_popup: PanelContainer
var rename_edit: LineEdit
var templates_grid: GridContainer
var builds_popup: PanelContainer
var builds_list: VBoxContainer
var builds_empty: Label
var copy_edit: LineEdit
var filter_popup: PanelContainer
var help_popup: PanelContainer


func _ready() -> void:
	icons = PartIcons.new()
	icons.name = "PartIcons"
	add_child(icons)
	icons.icon_ready.connect(_on_icon)
	_load_prefs()
	_build_top()
	_build_library()
	_build_right()
	_build_bottom()
	_build_popups()
	_style_test_nodes()
	back_button.pressed.connect(func() -> void: ctl.stop_test())
	root.resized.connect(_layout)
	_layout()


func bind(c: WorkshopBuild) -> void:
	ctl = c
	overlay.set("ctl", c)
	ctl.changed.connect(_refresh)
	ctl.toast.connect(show_toast)
	ctl.mode_changed.connect(_on_mode)
	ctl.view_changed.connect(func(_v: int) -> void:
		_close_popups()
		_build_left())
	ctl.dummy_hit.connect(_on_dummy_hit)
	ctl.selection_changed.connect(_refresh)
	if ctl.paint != null:
		ctl.paint.open_tab.connect(open_paint_tab)   # файл брошен в окно — полка покраски
	_build_left()
	_refresh()


## Открыть вкладку «Покраска» (категория «Декор и покраска», вид — тело).
func open_paint_tab() -> void:
	if ctl.view != WorkshopBuild.View.BODY:
		ctl.set_view(WorkshopBuild.View.BODY)
	shelf_tab["body"] = "paint"
	_build_left()


## Точка над панелью / всплывашкой (клик туда не ставит деталь в «липком» режиме протяжки).
func is_over_panel(p: Vector2) -> bool:
	for c in [left, right, top_bar, test_button, templates_popup, builds_popup, filter_popup, help_popup, test_bar]:
		if c != null and (c as Control).is_visible_in_tree() and (c as Control).get_global_rect().has_point(p):
			return true
	return false


## Свободная зона для бойца (WorkshopBuild.free_rect: камера держит сборку в её середине) — между библиотекой, правой колонкой,
## верхней строкой и кнопкой «Испытать».
func free_rect() -> Rect2:
	var vp := root.size
	var x0 := PAD + LEFT_W + 12.0
	var x1 := vp.x - PAD - RIGHT_W - 12.0
	var y0 := TOP_Y + TOP_H + 10.0
	var y1 := vp.y - TEST_H - 34.0
	return Rect2(x0, y0, x1 - x0, y1 - y0)


func _layout() -> void:
	if test_button == null:
		return
	var fr := free_rect()
	var vp := root.size
	test_button.position = Vector2(fr.get_center().x - TEST_W * 0.5, vp.y - TEST_H - 20.0)
	test_button.size = Vector2(TEST_W, TEST_H)
	help_line.position = Vector2(fr.position.x, vp.y - TEST_H - 54.0)
	help_line.size = Vector2(fr.size.x, 28.0)


# ------------------------------------------------------------------ сборка узлов: верх

func _build_top() -> void:
	top_bar = PanelContainer.new()
	top_bar.name = "TopBar"
	var st := WsStyle.panel() as StyleBoxFlat
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	st.content_margin_left = 10
	st.content_margin_right = 10
	top_bar.add_theme_stylebox_override("panel", st)
	top_bar.anchor_right = 1.0
	top_bar.offset_left = PAD
	top_bar.offset_right = -PAD
	top_bar.offset_top = TOP_Y
	top_bar.offset_bottom = TOP_Y + TOP_H
	root.add_child(top_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	top_bar.add_child(row)
	# слева: ⚙ Мастерская (клавиши)
	var lft := HBoxContainer.new()
	lft.custom_minimum_size = Vector2(560, 0)
	row.add_child(lft)
	title_button = Button.new()
	title_button.text = "Мастерская"
	title_button.tooltip_text = "Клавиши и мышь"
	title_button.flat = true
	title_button.focus_mode = Control.FOCUS_NONE
	title_button.add_theme_font_size_override("font_size", 28)
	for st_name in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		title_button.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	title_button.add_theme_color_override("font_color", WsStyle.TEXT)
	title_button.add_theme_color_override("font_hover_color", WsStyle.TEXT_SELECTED)
	title_button.add_theme_color_override("font_pressed_color", WsStyle.AMBER)
	title_button.pressed.connect(func() -> void: _toggle_popup(help_popup))
	WsIcon.add_to_button(title_button, "gear", 26.0, WsStyle.BRASS)
	lft.add_child(title_button)
	# середина: ‹ имя ›
	var mid := HBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 2)
	row.add_child(mid)
	prev_template = _icon_button("chevron_left", "Предыдущий шаблон")
	prev_template.pressed.connect(func() -> void: _step_template(-1))
	mid.add_child(prev_template)
	name_button = Button.new()
	name_button.focus_mode = Control.FOCUS_NONE
	name_button.tooltip_text = "Шаблоны и имя"
	name_button.custom_minimum_size = Vector2(300, 0)
	name_button.clip_text = true
	name_button.add_theme_font_size_override("font_size", WsStyle.SIZE_M)
	WsStyle.apply_button(name_button, "tab")
	name_button.add_theme_color_override("font_color", WsStyle.TEXT)
	name_button.pressed.connect(func() -> void: _toggle_popup(templates_popup))
	mid.add_child(name_button)
	next_template = _icon_button("chevron_right", "Следующий шаблон")
	next_template.pressed.connect(func() -> void: _step_template(1))
	mid.add_child(next_template)
	# справа: энергия, ↶ ↷, мои сборки
	var rgt := HBoxContainer.new()
	rgt.custom_minimum_size = Vector2(560, 0)
	rgt.alignment = BoxContainer.ALIGNMENT_END
	rgt.add_theme_constant_override("separation", 8)
	row.add_child(rgt)
	var en := HBoxContainer.new()
	en.tooltip_text = "Энергия ядра: чем дальше от ядра деталь, тем дороже"
	en.mouse_filter = Control.MOUSE_FILTER_PASS
	en.add_theme_constant_override("separation", 6)
	rgt.add_child(en)
	energy_icon = WsIcon.make("energy", 24.0, WsStyle.AMBER)
	energy_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	en.add_child(energy_icon)
	var ev := VBoxContainer.new()
	ev.add_theme_constant_override("separation", 1)
	ev.alignment = BoxContainer.ALIGNMENT_CENTER
	ev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	en.add_child(ev)
	energy_value = Label.new()
	WsStyle.label(energy_value, WsStyle.SIZE_M)
	energy_value.custom_minimum_size = Vector2(150, 0)
	energy_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ev.add_child(energy_value)
	energy_bar = MiniBar.new()
	energy_bar.custom_minimum_size = Vector2(150, 5)
	ev.add_child(energy_bar)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(14, 0)
	rgt.add_child(gap)
	undo_button = _icon_button("undo", "Отменить  Ctrl+Z")
	undo_button.pressed.connect(func() -> void: ctl.undo())
	rgt.add_child(undo_button)
	redo_button = _icon_button("redo", "Вернуть  Ctrl+Y")
	redo_button.pressed.connect(func() -> void: ctl.redo())
	rgt.add_child(redo_button)
	builds_button = Button.new()
	builds_button.text = "Мои сборки"
	builds_button.focus_mode = Control.FOCUS_NONE
	WsStyle.apply_button(builds_button)
	WsIcon.add_to_button(builds_button, "folder", 20.0)
	builds_button.pressed.connect(func() -> void:
		_fill_builds()
		_toggle_popup(builds_popup))
	rgt.add_child(builds_button)


func _icon_button(icon_name: String, tip: String, px := 22.0, kind := "button") -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(40, 40)
	WsStyle.apply_button(b, kind)
	WsIcon.add_to_button(b, icon_name, px)
	return b


# ------------------------------------------------------------------ сборка узлов: библиотека

func _build_library() -> void:
	left = PanelContainer.new()
	left.name = "Left"
	var st := WsStyle.panel() as StyleBoxFlat
	st.content_margin_left = 12
	st.content_margin_right = 8
	st.content_margin_top = 12
	st.content_margin_bottom = 10
	left.add_theme_stylebox_override("panel", st)
	left.anchor_bottom = 1.0
	left.offset_left = PAD
	left.offset_right = PAD + LEFT_W
	left.offset_top = TOP_Y + TOP_H + 10.0
	left.offset_bottom = -PAD
	root.add_child(left)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	left.add_child(v)
	# поиск и фильтр — стоят, листается только сетка
	var sr := HBoxContainer.new()
	sr.add_theme_constant_override("separation", 6)
	v.add_child(sr)
	search = LineEdit.new()
	search.placeholder_text = "Найти деталь"
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.custom_minimum_size = Vector2(0, 40)
	WsStyle.apply_field(search)
	for k in ["normal", "focus", "read_only"]:
		var sb := search.get_theme_stylebox(k).duplicate() as StyleBoxFlat
		if sb != null:
			sb.content_margin_left = 36
			search.add_theme_stylebox_override(k, sb)
	var si := WsIcon.make("search", 20.0, WsStyle.TEXT_DIM)
	si.position = Vector2(10, 10)
	search.add_child(si)
	search.text_changed.connect(func(_t: String) -> void: _build_shelf())
	sr.add_child(search)
	filter_button = _icon_button("filter", "Фильтр и порядок")
	filter_button.toggle_mode = true
	WsStyle.apply_button(filter_button)
	filter_button.pressed.connect(func() -> void:
		filter_button.set_pressed_no_signal(_filters_active())
		_toggle_popup(filter_popup))
	sr.add_child(filter_button)
	cats_row = HBoxContainer.new()
	cats_row.add_theme_constant_override("separation", 3)
	v.add_child(cats_row)
	sub_row = HBoxContainer.new()
	sub_row.add_theme_constant_override("separation", 6)
	v.add_child(sub_row)
	shelf_scroll = ScrollContainer.new()
	shelf_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shelf_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(shelf_scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	shelf_scroll.add_child(box)
	tool_hint = Label.new()
	WsStyle.label(tool_hint, WsStyle.SIZE_XS, true)
	tool_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(tool_hint)
	tools_box = GridContainer.new()
	tools_box.add_theme_constant_override("h_separation", 6)
	tools_box.add_theme_constant_override("v_separation", 6)
	tools_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(tools_box)
	shelf = VBoxContainer.new()
	shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shelf.add_theme_constant_override("separation", 8)
	box.add_child(shelf)


# ------------------------------------------------------------------ сборка узлов: справа

func _build_right() -> void:
	right = PanelContainer.new()
	right.name = "Right"
	WsStyle.apply_panel(right)
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -PAD - RIGHT_W
	right.offset_right = -PAD
	right.offset_top = TOP_Y + TOP_H + 10.0
	right.offset_bottom = TOP_Y + TOP_H + 10.0
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(right)
	var v := VBoxContainer.new()
	right.add_child(v)
	# сводка сборки
	summary_box = VBoxContainer.new()
	summary_box.add_theme_constant_override("separation", 8)
	v.add_child(summary_box)
	summary_title = Label.new()
	WsStyle.label(summary_title, WsStyle.SIZE_M)
	summary_title.clip_text = true
	summary_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	summary_box.add_child(summary_title)
	summary_rows = _rows_grid()
	summary_box.add_child(summary_rows)
	problems = Label.new()
	WsStyle.label(problems, WsStyle.SIZE_XS)
	problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_box.add_child(problems)
	physics_button = Button.new()
	physics_button.text = "Физика"
	physics_button.toggle_mode = true
	physics_button.focus_mode = Control.FOCUS_NONE
	physics_button.tooltip_text = "Центр масс, нагрузка на суставы, куда заваливается"
	WsStyle.apply_button(physics_button)
	WsIcon.add_to_button(physics_button, "physics", 20.0)
	physics_button.toggled.connect(func(on: bool) -> void:
		ctl.show_com = on
		_refresh())
	summary_box.add_child(physics_button)
	physics_info = Label.new()
	WsStyle.label(physics_info, WsStyle.SIZE_XS, true)
	physics_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_box.add_child(physics_info)
	# паспорт детали
	part_box = VBoxContainer.new()
	part_box.add_theme_constant_override("separation", 8)
	v.add_child(part_box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	part_box.add_child(head)
	part_icon = TextureRect.new()
	part_icon.custom_minimum_size = Vector2(56, 56)
	part_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	part_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(part_icon)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_theme_constant_override("separation", 0)
	head.add_child(hv)
	part_title = Label.new()
	WsStyle.label(part_title, WsStyle.SIZE_M)
	part_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(part_title)
	part_where = Label.new()
	WsStyle.label(part_where, WsStyle.SIZE_XS, true)
	part_where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(part_where)
	var close := _icon_button("close", "Снять выбор  Esc", 16.0)
	close.custom_minimum_size = Vector2(30, 30)
	close.flat = true
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(func() -> void: ctl.clear_selection())
	head.add_child(close)
	part_rows = _rows_grid()
	part_box.add_child(part_rows)
	branch_row = HBoxContainer.new()
	branch_row.add_theme_constant_override("separation", 4)
	part_box.add_child(branch_row)
	joint_row = HFlowContainer.new()
	joint_row.add_theme_constant_override("h_separation", 4)
	joint_row.add_theme_constant_override("v_separation", 4)
	part_box.add_child(joint_row)
	pull_row = HBoxContainer.new()
	pull_row.add_theme_constant_override("separation", 4)
	part_box.add_child(pull_row)
	channel_row = HBoxContainer.new()
	channel_row.add_theme_constant_override("separation", 4)
	part_box.add_child(channel_row)
	part_desc = Label.new()
	WsStyle.label(part_desc, WsStyle.SIZE_XS, true)
	part_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	part_box.add_child(part_desc)
	part_actions = HBoxContainer.new()
	part_actions.add_theme_constant_override("separation", 6)
	part_box.add_child(part_actions)
	# верстак оружия
	weapon_box = VBoxContainer.new()
	weapon_box.add_theme_constant_override("separation", 8)
	v.add_child(weapon_box)
	weapon_name = Label.new()
	WsStyle.label(weapon_name, WsStyle.SIZE_M)
	weapon_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	weapon_box.add_child(weapon_name)
	wstats = _rows_grid()
	weapon_box.add_child(wstats)
	wproblems = Label.new()
	WsStyle.label(wproblems, WsStyle.SIZE_XS)
	wproblems.add_theme_color_override("font_color", WsStyle.RED)
	wproblems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	weapon_box.add_child(wproblems)
	var wb := HBoxContainer.new()
	wb.add_theme_constant_override("separation", 6)
	weapon_box.add_child(wb)
	equip_button = Button.new()
	equip_button.focus_mode = Control.FOCUS_NONE
	equip_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	WsStyle.apply_button(equip_button)
	WsIcon.add_to_button(equip_button, "hand", 20.0)
	equip_button.pressed.connect(func() -> void: ctl.weapon_to_hand())
	wb.add_child(equip_button)
	clear_button = Button.new()
	clear_button.text = "Очистить"
	clear_button.focus_mode = Control.FOCUS_NONE
	WsStyle.apply_button(clear_button, "danger")
	WsIcon.add_to_button(clear_button, "delete", 18.0)
	clear_button.pressed.connect(func() -> void: ctl.clear_weapon())
	wb.add_child(clear_button)


func _rows_grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 5)
	return g


## Строка сводки: значок, подпись, значение справа (value_col — цвет значения: «станет» зелёным / красным).
func _row(g: GridContainer, icon_name: String, label: String, value: String, value_col := WsStyle.TEXT) -> void:
	var ic: Control = WsIcon.make(icon_name, 18.0, WsStyle.TEXT_DIM) if icon_name != "" else Control.new()
	ic.custom_minimum_size = Vector2(18, 18)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g.add_child(ic)
	var l := Label.new()
	l.text = label
	WsStyle.label(l, WsStyle.SIZE_S, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(l)
	var v := Label.new()
	v.text = value
	WsStyle.label(v, WsStyle.SIZE_S)
	v.add_theme_color_override("font_color", value_col)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	g.add_child(v)


# ------------------------------------------------------------------ сборка узлов: низ и всплывашки

func _build_bottom() -> void:
	help_line = Label.new()
	help_line.name = "HelpLine"
	WsStyle.label(help_line, WsStyle.SIZE_S, true)
	help_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_line.clip_text = true
	help_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	help_line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	help_line.add_theme_constant_override("outline_size", 5)
	help_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(help_line)
	test_button = Button.new()
	test_button.name = "TestButton"
	test_button.text = "Испытать"
	test_button.focus_mode = Control.FOCUS_NONE
	test_button.tooltip_text = "Испытать сборку на манекене  T"
	WsStyle.apply_button(test_button, "cta")
	WsIcon.add_to_button(test_button, "play", 22.0)
	test_button.set_meta("ws_sfx_kind", "test")
	test_button.pressed.connect(func() -> void: ctl.start_test())
	root.add_child(test_button)
	var key := Label.new()
	key.text = "T"
	WsStyle.label(key, WsStyle.SIZE_XS)
	key.add_theme_color_override("font_color", Color(1, 0.93, 0.85, 0.7))
	key.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	key.offset_left = -26
	key.offset_top = -10
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	test_button.add_child(key)
	# «+1.5 кг ⚡+4 ЦМ →» у детали в руке
	drag_info = PanelContainer.new()
	drag_info.name = "DragInfo"
	var ds := WsStyle.popup() as StyleBoxFlat
	ds.content_margin_left = 10
	ds.content_margin_right = 10
	ds.content_margin_top = 4
	ds.content_margin_bottom = 4
	drag_info.add_theme_stylebox_override("panel", ds)
	drag_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_info.visible = false
	root.add_child(drag_info)
	drag_info_text = RichTextLabel.new()
	drag_info_text.bbcode_enabled = true
	drag_info_text.fit_content = true
	drag_info_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	drag_info_text.scroll_active = false
	drag_info_text.add_theme_font_size_override("normal_font_size", WsStyle.SIZE_S)
	drag_info_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_info.add_child(drag_info_text)


func _build_popups() -> void:
	dismiss = Control.new()
	dismiss.name = "Dismiss"
	dismiss.set_anchors_preset(Control.PRESET_FULL_RECT)
	dismiss.mouse_filter = Control.MOUSE_FILTER_STOP
	dismiss.visible = false
	dismiss.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_close_popups())
	root.add_child(dismiss)
	# шаблоны и имя — под именем сборки
	templates_popup = _popup("TemplatesPopup", Vector2(620, 0))
	templates_popup.anchor_left = 0.5
	templates_popup.anchor_right = 0.5
	templates_popup.offset_left = -310
	templates_popup.offset_right = 310
	templates_popup.offset_top = TOP_Y + TOP_H + 6.0
	var tv := templates_popup.get_child(0) as VBoxContainer
	tv.add_child(_caption("Имя сборки"))
	rename_edit = LineEdit.new()
	rename_edit.custom_minimum_size = Vector2(0, 40)
	WsStyle.apply_field(rename_edit)
	rename_edit.text_submitted.connect(func(t: String) -> void:
		ctl.rename_build(t)
		_close_popups())
	tv.add_child(rename_edit)
	tv.add_child(_caption("Начать с шаблона"))
	templates_grid = GridContainer.new()
	templates_grid.columns = 5
	templates_grid.add_theme_constant_override("h_separation", 6)
	templates_grid.add_theme_constant_override("v_separation", 6)
	tv.add_child(templates_grid)
	presets_box = templates_grid
	# мои сборки
	builds_popup = _popup("BuildsPopup", Vector2(460, 0))
	builds_popup.anchor_left = 1.0
	builds_popup.anchor_right = 1.0
	builds_popup.offset_left = -PAD - 460
	builds_popup.offset_right = -PAD
	builds_popup.offset_top = TOP_Y + TOP_H + 6.0
	var bv := builds_popup.get_child(0) as VBoxContainer
	bv.add_child(_caption("Мои сборки"))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 360)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bv.add_child(sc)
	builds_list = VBoxContainer.new()
	builds_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	builds_list.add_theme_constant_override("separation", 4)
	sc.add_child(builds_list)
	builds_empty = Label.new()
	builds_empty.text = "Пока пусто: сохрани копию ниже"
	WsStyle.label(builds_empty, WsStyle.SIZE_S, true)
	bv.add_child(builds_empty)
	bv.add_child(_caption("Сохранить копию"))
	var cr := HBoxContainer.new()
	cr.add_theme_constant_override("separation", 6)
	bv.add_child(cr)
	copy_edit = LineEdit.new()
	copy_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_edit.custom_minimum_size = Vector2(0, 40)
	WsStyle.apply_field(copy_edit)
	copy_edit.text_submitted.connect(func(_t: String) -> void: _save_copy())
	cr.add_child(copy_edit)
	var sb := Button.new()
	sb.text = "Сохранить"
	sb.focus_mode = Control.FOCUS_NONE
	WsStyle.apply_button(sb)
	WsIcon.add_to_button(sb, "save", 18.0)
	sb.pressed.connect(_save_copy)
	cr.add_child(sb)
	var auto := Label.new()
	auto.text = "Текущая сборка сохраняется сама"
	WsStyle.label(auto, WsStyle.SIZE_XS, true)
	bv.add_child(auto)
	# фильтр библиотеки
	filter_popup = _popup("FilterPopup", Vector2(360, 0))
	filter_popup.offset_left = PAD + LEFT_W + 8.0
	filter_popup.offset_right = PAD + LEFT_W + 8.0 + 360.0
	filter_popup.offset_top = TOP_Y + TOP_H + 10.0
	# клавиши
	help_popup = _popup("HelpPopup", Vector2(520, 0))
	help_popup.offset_left = PAD
	help_popup.offset_right = PAD + 520.0
	help_popup.offset_top = TOP_Y + TOP_H + 6.0
	var hv := help_popup.get_child(0) as VBoxContainer
	hv.add_child(_caption("Мышь"))
	for r in [["ЛКМ по детали", "выбрать; тащи — перенести с тем, что на ней"], ["Shift-клик, двойной клик", "выбрать всю ветку"],
			["ПКМ по детали", "открутить"], ["ПКМ и тащи", "вращать вид"], ["Колесо", "ближе / дальше"]]:
		hv.add_child(_key_line(String(r[0]), String(r[1])))
	hv.add_child(_caption("Клавиши"))
	for r in [["D", "копия в руку"], ["M", "зеркало: Enter — поставить"], ["Del", "снять"], ["Q", "тяги ЛКМ / ПКМ"],
			["R", "вид по умолчанию"], ["Tab", "верстак оружия"], ["Ctrl+Z / Ctrl+Y", "отменить / вернуть"], ["T", "испытать"]]:
		hv.add_child(_key_line(String(r[0]), String(r[1])))


func _popup(n: String, min_size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = n
	WsStyle.apply_panel(p, "popup")
	p.custom_minimum_size = min_size
	p.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	root.add_child(p)
	return p


func _caption(t: String) -> Label:
	var l := Label.new()
	l.text = t
	WsStyle.label(l, WsStyle.SIZE_XS, true)
	return l


func _key_line(k: String, what: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var kl := Label.new()
	kl.text = k
	WsStyle.label(kl, WsStyle.SIZE_S)
	kl.add_theme_color_override("font_color", WsStyle.AMBER)
	kl.custom_minimum_size = Vector2(200, 0)
	h.add_child(kl)
	var wl := Label.new()
	wl.text = what
	WsStyle.label(wl, WsStyle.SIZE_S, true)
	h.add_child(wl)
	return h


func _toggle_popup(p: Control) -> void:
	var was := p.visible
	_close_popups()
	if was:
		return
	if p == templates_popup:
		_fill_templates()
	elif p == filter_popup:
		_fill_filter()
	p.visible = true
	dismiss.visible = true
	root.move_child(dismiss, root.get_child_count() - 1)
	root.move_child(p, root.get_child_count() - 1)
	_wire()


func _close_popups() -> void:
	for p in [templates_popup, builds_popup, filter_popup, help_popup]:
		if p != null:
			(p as Control).visible = false
	if dismiss != null:
		dismiss.visible = false
	if rename_edit != null:
		rename_edit.release_focus()
	if copy_edit != null:
		copy_edit.release_focus()
	if filter_button != null:
		filter_button.set_pressed_no_signal(_filters_active())


func _style_test_nodes() -> void:
	WsStyle.apply_button(back_button)
	WsIcon.add_to_button(back_button, "chevron_left", 20.0)
	WsStyle.apply_panel(test_stats)
	WsStyle.label(test_stats_text, WsStyle.SIZE_S)
	toast_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	toast_label.add_theme_constant_override("outline_size", 8)


# ------------------------------------------------------------------ библиотека

func _view_key() -> String:
	return "weapon" if ctl.view == WorkshopBuild.View.WEAPON else "body"


func _cats() -> Array:
	return WCATS if ctl.view == WorkshopBuild.View.WEAPON else CATS


## Категория текущей вкладки (у «Покраски» — PAINT_TAB).
func _cat() -> Dictionary:
	var id := String(shelf_tab[_view_key()])
	if id == "paint":
		return PAINT_TAB
	for c in _cats():
		if String(c["id"]) == id:
			return c
	# старые id вкладок (проба, сохранённые настройки): полки CraftEdit.BODY_SHELVES
	var sh := CraftEdit.shelf_of(CraftEdit.WEAPON_SHELVES if ctl.view == WorkshopBuild.View.WEAPON else CraftEdit.BODY_SHELVES, id)
	if not sh.is_empty():
		return sh
	return _cats()[0]


func _build_left() -> void:
	if ctl == null:
		return
	var weapon := ctl.view == WorkshopBuild.View.WEAPON
	var tab := String(shelf_tab[_view_key()])
	for c in cats_row.get_children():
		c.queue_free()
	_cat_buttons.clear()
	if weapon:
		var back := _chip("body", "К бойцу  Tab", false)
		back.pressed.connect(func() -> void: _set_view(WorkshopBuild.View.BODY))
		cats_row.add_child(back)
	for c in _cats():
		var cid := String(c["id"])
		var on := cid == tab or (cid == "deco" and tab == "paint")
		var b := _chip(String(c["icon"]), String(c["title"]), on)
		b.pressed.connect(func() -> void: _select_tab(cid))
		cats_row.add_child(b)
		_cat_buttons[cid] = b
	# под рядом категорий: у «Декор и покраска» — Детали | Покраска; у «Оружия» — на верстак
	for c in sub_row.get_children():
		c.queue_free()
	sub_row.visible = false
	if not weapon and (tab == "deco" or tab == "paint"):
		sub_row.visible = true
		for pair in [["deco", "Детали", "decor"], ["paint", "Покраска", "paint"]]:
			var sid := String(pair[0])
			var sb := Button.new()
			sb.text = String(pair[1])
			sb.toggle_mode = true
			sb.focus_mode = Control.FOCUS_NONE
			sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			WsStyle.apply_button(sb, "tab")
			WsIcon.add_to_button(sb, String(pair[2]), 18.0)
			sb.set_pressed_no_signal(sid == tab)
			sb.pressed.connect(func() -> void: _select_tab(sid))
			sub_row.add_child(sb)
	elif not weapon and tab == "weapon":
		sub_row.visible = true
		var wb := Button.new()
		wb.text = "Собрать оружие на верстаке"
		wb.focus_mode = Control.FOCUS_NONE
		wb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		WsStyle.apply_button(wb)
		WsIcon.add_to_button(wb, "weapon", 18.0)
		wb.pressed.connect(func() -> void: _set_view(WorkshopBuild.View.WEAPON))
		sub_row.add_child(wb)
	search.get_parent().visible = tab != "paint"
	_build_shelf()
	_update_name()
	_wire()


func _chip(icon_name: String, tip: String, on: bool) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(CHIP, CHIP)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	WsStyle.apply_button(b, "chip")
	_tight(b, 5.0)   # десять значков в ряд на 400 px: поля чипа поуже, значок по центру
	WsIcon.add_to_button(b, icon_name, 22.0)
	b.set_pressed_no_signal(on)
	return b


## Поля кнопки по горизонтали — m px во всех состояниях (ряд значков, узкие плитки).
static func _tight(b: Button, m: float) -> void:
	for st_name in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := b.get_theme_stylebox(st_name).duplicate() as StyleBoxFlat
		if sb != null:
			sb.content_margin_left = m
			sb.content_margin_right = m
			b.add_theme_stylebox_override(st_name, sb)


func _select_tab(id: String) -> void:
	var was := String(shelf_tab[_view_key()])
	shelf_tab[_view_key()] = id
	var tool := String(_cat().get("tool", ""))
	if ctl.active_tool() in ["material", "joint", "paint"] and ctl.active_tool() != tool:
		ctl.clear_tools()   # ушёл с вкладки инструмента — кисть / шарнир / баллончик кладутся
	if was == "paint" and id != "paint" and ctl.paint != null:
		ctl.paint.reset_turn()   # стенд снова лицом
	if id == "paint" and was != "paint" and ctl.paint != null and ctl.paint.tool == "":
		ctl.paint.set_tool("spray")   # пришёл красить — баллончик сразу в руке
	_build_left()


func _set_view(v: int) -> void:
	ctl.set_view(v)
	_build_left()
	_refresh()


func _build_shelf() -> void:
	for c in shelf.get_children():
		c.queue_free()
	for c in tools_box.get_children():
		c.queue_free()
	_cards.clear()
	_tool_cards.clear()
	var weapon := ctl.view == WorkshopBuild.View.WEAPON
	var cat := _cat()
	var kinds: Array = cat.get("kinds", [])
	_tool = String(cat.get("tool", ""))
	if ctl.paint != null:
		ctl.paint.tab_open = _tool == "paint"
	var query := search.text.strip_edges().to_lower() if _tool != "paint" else ""
	# инструмент вкладки: плашки материалов / шарниров / покраска — над деталями
	if query == "":
		if _tool == "material":
			tools_box.columns = 2
			for mid in MaterialDef.all_ids():
				var mc := MaterialCard.new()
				mc.setup(MaterialDef.get_def(mid))
				mc.picked.connect(func(m: String) -> void: ctl.set_paint_mat(m))
				tools_box.add_child(mc)
				_tool_cards[mid] = mc
		elif _tool == "joint":
			tools_box.columns = 2
			for jt in KitJoint.ORDER:
				var jc := JointCard.new()
				jc.setup(String(jt))
				jc.picked.connect(func(t: String) -> void: ctl.set_joint_pick(t))
				tools_box.add_child(jc)
				_tool_cards[String(jt)] = jc
		elif _tool == "paint":
			tools_box.columns = 1
			var pp := PaintPanel.new()
			tools_box.add_child(pp)
			pp.setup(ctl)
	tools_box.visible = not _tool_cards.is_empty() or (_tool == "paint" and query == "")
	tool_hint.visible = tools_box.visible and TOOL_HINTS.has(_tool)
	tool_hint.text = String(TOOL_HINTS.get(_tool, ""))
	# детали: поиск — по всей библиотеке вида; иначе — категория (группами, где они есть)
	var groups: Array = []   # [[заголовок, [PartDef]]]
	if query != "":
		var found: Array = []
		for d in CraftEdit.parts_of_kinds(_cats()[0]["kinds"]):
			if PartNames.search_text(d).contains(query) or d.id.contains(query):
				found.append(d)
		groups.append(["", found])
	elif String(cat.get("id", "")) == "all" and not weapon:
		# «Все детали» — по категориям с подзаголовками: библиотека читается, как полки верстака
		for c in CATS:
			if String(c["id"]) == "all" or (c["kinds"] as Array).is_empty():
				continue
			groups.append([String(c["title"]), CraftEdit.parts_of_kinds(c["kinds"]).filter(func(d: PartDef) -> bool:
				return CraftEdit.shelf_allows(c, d))])
	else:
		var defs := CraftEdit.parts_of_kinds(kinds).filter(func(d: PartDef) -> bool: return CraftEdit.shelf_allows(cat, d))
		var gdef: Array = GROUPS.get(String(cat.get("id", "")), [])
		if gdef.is_empty():
			groups.append(["", defs])
		else:
			for g in gdef:
				var part: Array = []
				for d in defs:
					if _in_group(d, String(g[1])):
						part.append(d)
				if not part.is_empty():
					groups.append([String(g[0]), part])
	var total := 0
	for g in groups:
		var list: Array = []
		for d in (g[1] as Array):
			if _passes(d as PartDef, weapon):
				list.append(d)
		if bool(filters["recent"]):
			list.sort_custom(func(a: PartDef, b: PartDef) -> bool:
				return ctl.recent_parts.find(a.id) < ctl.recent_parts.find(b.id))
		else:
			list.sort_custom(_sorter())
		if list.is_empty():
			continue
		if String(g[0]) != "":
			shelf.add_child(_group_header(String(g[0]), list.size()))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		shelf.add_child(grid)
		for d in list:
			var card := PartCard.new()
			card.setup(d, not weapon, favorites.has((d as PartDef).id))
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			card.grabbed.connect(_on_card_grabbed)
			card.picked.connect(_on_card_picked)
			card.favorite_toggled.connect(_on_favorite)
			card.hovered.connect(_on_card_hover)
			grid.add_child(card)
			_cards[d.id] = card
			var tex := icons.request(d.id)
			if tex != null:
				card.set_icon(tex)
			total += 1
	if total == 0 and not (_tool != "" and query == ""):
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		WsStyle.label(l, WsStyle.SIZE_S, true)
		l.text = "Ничего не нашлось" if query != "" else ("Под фильтр ничего не подходит" if _filters_active() else "Пусто")
		shelf.add_child(l)
	shelf_scroll.scroll_vertical = 0
	_update_card_state()
	_update_tool_cards()


## Фильтр библиотеки: влезает по энергии, избранное, недавние, масса, материал.
func _passes(d: PartDef, weapon: bool) -> bool:
	if bool(filters["fits"]) and not weapon and d.energy > ctl.energy_free():
		return false
	if bool(filters["fav"]) and not favorites.has(d.id):
		return false
	if bool(filters["recent"]) and not ctl.recent_parts.has(d.id):
		return false
	match String(filters["mass"]):
		"light": if d.mass > 2.0: return false
		"heavy": if d.mass < 4.0: return false
	if String(filters["mat"]) != "" and _mat_group(d) != String(filters["mat"]):
		return false
	return true


## Материал детали словом фильтра: metal / soft / wood.
static func _mat_group(d: PartDef) -> String:
	var m := d.base_mat if d.base_mat != "" else d.material
	if m in ["iron", "brass", "rust", "rust_red", "steel", "metal", "copper"]:
		return "metal"
	if m in ["cloth", "rope", "rubber", "leather"]:
		return "soft"
	return "wood"


func _filters_active() -> bool:
	return bool(filters["fits"]) or bool(filters["fav"]) or bool(filters["recent"]) or String(filters["mass"]) != "" \
		or String(filters["mat"]) != ""


func _in_group(d: PartDef, g: String) -> bool:
	match g:
		"arm": return d.name_prefix.contains("Arm") or d.id.ends_with("_s")
		"leg": return not (d.name_prefix.contains("Arm") or d.id.ends_with("_s"))
		"hand": return d.kind == "hand"
		"foot": return d.kind == "foot"
		"plate": return d.kind == "plate"
		"armor": return d.kind == "armor"
		"weapon_head": return d.kind == "weapon_head"
		"mod": return d.kind == "mod"
	return true


func _sorter() -> Callable:
	match int(filters["sort"]):
		1: return func(a: PartDef, b: PartDef) -> bool: return a.mass < b.mass
		2: return func(a: PartDef, b: PartDef) -> bool: return PartNames.of(a).naturalnocasecmp_to(PartNames.of(b)) < 0
	return func(a: PartDef, b: PartDef) -> bool: return a.energy < b.energy or (a.energy == b.energy and a.mass < b.mass)


func _group_header(text: String, n: int) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = text
	WsStyle.label(l, WsStyle.SIZE_S)
	h.add_child(l)
	var sep := HSeparator.new()
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sep.modulate = Color(1, 1, 1, 0.35)
	h.add_child(sep)
	var c := Label.new()
	c.text = str(n)
	WsStyle.label(c, WsStyle.SIZE_XS, true)
	h.add_child(c)
	return h


## Выбранная плашка инструмента — янтарная (кисть / шарнир в руке у WorkshopBuild).
func _update_tool_cards() -> void:
	if ctl == null or _tool == "paint":
		return
	var sel := ctl.paint_mat if _tool == "material" else (ctl.joint_pick if _tool == "joint" else "")
	for id in _tool_cards:
		(_tool_cards[id]).set_selected(String(id) == sel)


func _on_icon(part_id: String, tex: Texture2D) -> void:
	if _cards.has(part_id):
		(_cards[part_id]).set_icon(tex)
	for b in templates_grid.get_children():
		if b.has_meta("icon_part") and String(b.get_meta("icon_part")) == part_id:
			var tr := b.find_child("Icon", true, false) as TextureRect
			if tr != null:
				tr.texture = tex
	if ctl != null and ctl.selected_def() != null and ctl.selected_def().id == part_id:
		part_icon.texture = tex


## Потянул карточку — деталь в руке (под курсором настоящая 3D-деталь, WorkshopBuild).
func _on_card_grabbed(part_id: String, pos: Vector2) -> void:
	if ctl.mode != WorkshopBuild.Mode.BUILD:
		return
	_close_popups()
	ctl.select_shelf(part_id)
	ctl.begin_drag(part_id, pos)
	ctl.update_drag(get_viewport().get_mouse_position())


## Клик по карточке — выбрать (справа паспорт и «Поставить»); ещё клик по выбранной — снять выбор.
func _on_card_picked(part_id: String) -> void:
	if ctl.mode != WorkshopBuild.Mode.BUILD:
		return
	_sfx("button")
	if String(ctl.selected.get("source", "")) == "shelf" and String(ctl.selected.get("part", "")) == part_id:
		ctl.clear_selection()
	else:
		ctl.select_shelf(part_id)


func _on_favorite(part_id: String, on: bool) -> void:
	if on and not favorites.has(part_id):
		favorites.append(part_id)
	elif not on and favorites.has(part_id):
		favorites.remove_at(favorites.find(part_id))
	_save_prefs()
	if bool(filters["fav"]) and not on:
		_build_shelf()


func _on_card_hover(part_id: String, on: bool) -> void:
	if on:
		if _live_card != "" and _cards.has(_live_card):
			(_cards[_live_card]).set_live(null)
		var tex := icons.live_start(part_id)
		if tex != null and _cards.has(part_id):
			(_cards[part_id]).set_live(tex)
		_live_card = part_id
		_sfx("hover")
	elif part_id == _live_card:
		icons.live_stop()
		if _cards.has(part_id):
			(_cards[part_id]).set_live(null)
		_live_card = ""


func _update_card_state() -> void:
	if ctl == null:
		return
	var free_e := ctl.energy_free()
	var sel := String(ctl.selected.get("part", "")) if String(ctl.selected.get("source", "")) == "shelf" else ""
	for id in _cards:
		var d := CraftEdit.part(String(id))
		(_cards[id]).set_fits(d == null or d.energy <= free_e or ctl.view == WorkshopBuild.View.WEAPON)
		(_cards[id]).set_selected(String(id) == sel)


# ------------------------------------------------------------------ всплывашки: шаблоны, сборки, фильтр

func _fill_templates() -> void:
	var weapon := ctl.view == WorkshopBuild.View.WEAPON
	rename_edit.text = _current_title()
	for c in templates_grid.get_children():
		c.queue_free()
	var tiles: Array = []
	if weapon:
		for id in CraftEdit.WEAPON_PRESETS:
			tiles.append([String(id), _weapon_icon_part(String(id))])
	else:
		tiles = TEMPLATES
	if CraftEdit.campaign_templates_locked:   # кампания: шаблоны тела и оружия закрыты (17-career-trophy.md)
		tiles = []
	for t in tiles:
		var pid := String(t[0])
		var b := _tile(String(PRESET_SHORT.get(pid, _preset_title(pid, weapon))), String(t[1]))
		b.pressed.connect(func() -> void:
			_close_popups()
			if weapon:
				ctl.set_weapon_preset(pid)
			else:
				ctl.set_preset(pid))
		templates_grid.add_child(b)


## Плитка шаблона: картинка детали и имя.
func _tile(text: String, icon_part: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(108, 112)
	b.tooltip_text = text
	WsStyle.apply_button(b)
	_tight(b, 4.0)
	b.set_meta("icon_part", icon_part)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_top = 6
	v.offset_bottom = -6
	v.add_theme_constant_override("separation", 2)
	b.add_child(v)
	var tr := TextureRect.new()
	tr.name = "Icon"
	tr.custom_minimum_size = Vector2(0, 70)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tr)
	if icon_part != "":
		tr.texture = icons.request(icon_part)
	var l := Label.new()
	l.text = text
	WsStyle.label(l, WsStyle.SIZE_XS)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l)
	return b


func _fill_builds() -> void:
	for c in builds_list.get_children():
		c.queue_free()
	var items := CraftEdit.list_saved()
	var shown := 0
	for it in items:
		if bool(it["auto"]):
			continue
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 44)
		b.clip_text = true
		WsStyle.apply_button(b)
		b.text = "%s   ·   ⚡%d   ·   %d дет." % [it["title"], it["energy"], it["parts"]]
		var path := String(it["path"])
		b.pressed.connect(func() -> void:
			_close_popups()
			ctl.load_path(path))
		builds_list.add_child(b)
		shown += 1
	builds_empty.visible = shown == 0
	copy_edit.text = _current_title()


func _save_copy() -> void:
	var t := copy_edit.text.strip_edges()
	_close_popups()
	if ctl.view == WorkshopBuild.View.WEAPON:
		ctl.set_view(WorkshopBuild.View.BODY)
	ctl.save_as(t)


func _fill_filter() -> void:
	var v := filter_popup.get_child(0) as VBoxContainer
	for c in v.get_children():
		c.queue_free()
	v.add_child(_caption("Показывать"))
	for f in [["fits", "Влезает по энергии", "energy"], ["fav", "Только избранное", "star"], ["recent", "Недавние", "clock"]]:
		var key := String(f[0])
		var b := Button.new()
		b.text = String(f[1])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		WsStyle.apply_button(b, "tab")
		WsIcon.add_to_button(b, String(f[2]), 18.0)
		b.set_pressed_no_signal(bool(filters[key]))
		b.toggled.connect(func(on: bool) -> void:
			filters[key] = on
			_after_filter())
		v.add_child(b)
	v.add_child(_caption("Масса"))
	v.add_child(_choice_row("mass", [["", "Любая"], ["light", "Лёгкие"], ["heavy", "Тяжёлые"]]))
	v.add_child(_caption("Материал"))
	v.add_child(_choice_row("mat", [["", "Любой"], ["wood", "Дерево"], ["metal", "Металл"], ["soft", "Мягкий"]]))
	v.add_child(_caption("Порядок"))
	v.add_child(_choice_row("sort", [[0, SORTS[0]], [1, SORTS[1]], [2, SORTS[2]]]))
	var reset := Button.new()
	reset.text = "Сбросить фильтр"
	reset.focus_mode = Control.FOCUS_NONE
	WsStyle.apply_button(reset)
	reset.pressed.connect(func() -> void:
		filters = {"fits": false, "fav": false, "recent": false, "sort": int(filters["sort"]), "mass": "", "mat": ""}
		_after_filter()
		_fill_filter())
	v.add_child(reset)


func _choice_row(key: String, opts: Array) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	for o in opts:
		var val: Variant = o[0]
		var b := Button.new()
		b.text = String(o[1])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		WsStyle.apply_button(b, "chip")
		b.set_pressed_no_signal(filters[key] == val)
		b.pressed.connect(func() -> void:
			filters[key] = val
			_after_filter()
			for s in h.get_children():
				(s as Button).set_pressed_no_signal(s == b))
		h.add_child(b)
	return h


func _after_filter() -> void:
	filter_button.set_pressed_no_signal(_filters_active())
	_save_prefs()
	_build_shelf()


# ------------------------------------------------------------------ шаблоны, имя

func _weapon_icon_part(id: String) -> String:
	var path := CraftEdit.WEAPON_PRESET_DIR + id + ".tres"
	if not ResourceLoader.exists(path):
		return ""
	var w := load(path) as WeaponBlueprint
	if w == null:
		return ""
	var handle := ""
	for n in w.nodes:
		var d := CraftEdit.part(String(n.get("part", "")))
		if d != null and d.kind == "weapon_head":
			return d.id
		if d != null and handle == "":
			handle = d.id
	return handle


func _preset_title(id: String, weapon: bool) -> String:
	var path := (CraftEdit.WEAPON_PRESET_DIR if weapon else CraftEdit.BODY_PRESET_DIR) + id + ".tres"
	if not ResourceLoader.exists(path):
		return id
	var r := load(path)
	return String(r.get("title")) if r != null else id


## ‹ › — листать все шаблоны (тела или оружия).
func _step_template(d: int) -> void:
	_close_popups()
	if ctl.view == WorkshopBuild.View.WEAPON:
		var wi := CraftEdit.WEAPON_PRESETS.find(ctl.weapon_bp.id if ctl.weapon_bp != null else "")
		ctl.set_weapon_preset(String(CraftEdit.WEAPON_PRESETS[wrapi(wi + d, 0, CraftEdit.WEAPON_PRESETS.size())]))
		return
	var ids: Array = CraftEdit.BODY_PRESETS
	var i := ids.find(ctl.blueprint.id)
	ctl.set_preset(String(ids[wrapi((i if i >= 0 else 0) + d, 0, ids.size())]))


## Имя сборки для игрока: без « *» правки и служебного хвоста шаблона в скобках («Человек (кукла v3)» → «Человек»).
func _current_title() -> String:
	var t := ctl.weapon_bp.title if ctl.view == WorkshopBuild.View.WEAPON and ctl.weapon_bp != null else ctl.blueprint.title
	t = t.trim_suffix(" *").strip_edges()
	var br := t.rfind(" (")
	if br > 0 and t.ends_with(")"):
		t = t.substr(0, br)
	return t if t != "" else "Своя сборка"


func _update_name() -> void:
	if ctl == null:
		return
	var t := ctl.weapon_bp.title if ctl.view == WorkshopBuild.View.WEAPON and ctl.weapon_bp != null else ctl.blueprint.title
	var edited := t.ends_with("*")
	name_button.text = _current_title() + ("  •" if edited else "")
	name_button.tooltip_text = "Шаблоны и имя%s" % ("  ·  изменена" if edited else "")


# ------------------------------------------------------------------ правая панель, энергия

func _refresh() -> void:
	if ctl == null:
		return
	prev_template.visible = not CraftEdit.campaign_templates_locked   # кампания: шаблоны закрыты (17-career-trophy.md)
	next_template.visible = not CraftEdit.campaign_templates_locked
	var weapon := ctl.view == WorkshopBuild.View.WEAPON
	var sel := not weapon and ctl.selected_def() != null
	summary_box.visible = not weapon and not sel
	part_box.visible = sel
	weapon_box.visible = weapon
	var s := ctl.body_stats()
	var pv := ctl.drag_preview() if not ctl.drag.is_empty() else {}
	_refresh_energy(s, pv)
	if summary_box.visible:
		_refresh_summary(s, pv)
	if sel:
		_refresh_part()
	if weapon:
		_refresh_weapon()
	undo_button.disabled = ctl.history.is_empty()
	redo_button.disabled = ctl.redo_stack.is_empty()
	test_button.disabled = not (s["errors"] as PackedStringArray).is_empty()
	test_button.tooltip_text = "Испытать сборку на манекене  T" if not test_button.disabled else "Сначала исправь: %s" % (s["errors"] as PackedStringArray)[0]
	_update_card_state()
	_update_tool_cards()
	_update_name()
	_update_hint()
	_wire()


## Энергия в верхней строке: «82 / 100»; при протяжке — «82 → 86», красным, если не встанет.
func _refresh_energy(s: Dictionary, pv: Dictionary) -> void:
	var used := int(s["energy"])
	var budget := int(s["budget"])
	var after := int(pv.get("energy", -1)) if not pv.is_empty() else -1
	var bad := after > budget or (not pv.is_empty() and not bool(pv["ok"]) and String(pv.get("reason", "")).contains("энерги"))
	if after >= 0 and after != used:
		energy_value.text = "%d → %d" % [used, after]
	else:
		energy_value.text = "%d / %d" % [used, budget]
	var col := WsStyle.RED if bad or used > budget else (WsStyle.AMBER if after > used else WsStyle.TEXT)
	energy_value.add_theme_color_override("font_color", col)
	energy_icon.color = WsStyle.RED if bad or used > budget else WsStyle.AMBER
	(energy_bar as MiniBar).set_values(float(used) / maxf(budget, 1), float(after) / maxf(budget, 1) if after >= 0 else -1.0)


## Маленькая сводка: имя, масса, детали, разгон, энергия; при протяжке — «было → станет».
func _refresh_summary(s: Dictionary, pv: Dictionary) -> void:
	summary_title.text = _current_title()
	for c in summary_rows.get_children():
		c.queue_free()
	var mass := float(s["mass"])
	var wm := float(s["weapon_mass"])
	var acc := float(s["accel"])
	if pv.is_empty():
		_row(summary_rows, "mass", "Масса", "%.1f кг" % mass if wm <= 0.0 else "%.1f + %.1f кг" % [mass, wm])
		_row(summary_rows, "all", "Детали", str(int(s["parts"])))
		_row(summary_rows, "play", "Разгон", "×%.2f" % acc)
		_row(summary_rows, "energy", "Энергия", "%d / %d" % [int(s["energy"]), int(s["budget"])])
	else:
		var ok := bool(pv["ok"])
		var m1 := float(pv["mass"])
		var a1 := float(pv["accel"])
		var e1 := int(pv["energy"])
		_row(summary_rows, "mass", "Масса", "%.1f → %.1f" % [mass, m1], WsStyle.TEXT if absf(m1 - mass) < 0.05 else WsStyle.AMBER)
		_row(summary_rows, "all", "Детали", "%d → %d" % [int(s["parts"]), int(pv["parts"])])
		_row(summary_rows, "play", "Разгон", "×%.2f → ×%.2f" % [acc, a1], WsStyle.GREEN if a1 > acc + 0.005 else (WsStyle.AMBER if a1 < acc - 0.005 else WsStyle.TEXT))
		_row(summary_rows, "energy", "Энергия", "%d → %d" % [int(s["energy"]), e1], WsStyle.RED if e1 > int(s["budget"]) or not ok else WsStyle.AMBER)
	var lines: PackedStringArray = []
	for e in (s["errors"] as PackedStringArray):
		lines.append(e)
	for w in (s["warnings"] as PackedStringArray):
		lines.append(w)
	problems.text = "\n".join(lines)
	problems.visible = not lines.is_empty()
	problems.add_theme_color_override("font_color", WsStyle.RED if not (s["errors"] as PackedStringArray).is_empty() else WsStyle.AMBER)
	physics_button.set_pressed_no_signal(ctl.show_com)
	physics_info.text = _physics_text() if ctl.show_com else ""
	physics_info.visible = ctl.show_com and physics_info.text != ""
	if physics_info.visible:
		var sm := WsPhysics.summary(ctl.stand)
		physics_info.add_theme_color_override("font_color", WsPhysics.load_colour(float(sm.get("max_muscle_load", 0.0))).lerp(WsStyle.TEXT, 0.35))


## Физика словами (кнопка «Физика», WsPhysics.summary): устойчивость и самый нагруженный сустав — цветом нагрузки.
func _physics_text() -> String:
	if ctl.stand == null or not is_instance_valid(ctl.stand):
		return ""
	var sm := WsPhysics.summary(ctl.stand)
	var tip: Dictionary = sm.get("tip", {})
	var margin := float(tip.get("margin", 1.0))
	var dir := float(tip.get("dir", 0.0))
	var side := "вправо" if dir > 0.0 else "влево"
	var lines: PackedStringArray = []
	if margin < 0.0:
		lines.append("Заваливается %s" % side)
	elif margin < 0.05:
		lines.append("Еле стоит, клонит %s" % side)
	else:
		lines.append("Стоит устойчиво")
	var j := String(sm.get("max_muscle_joint", sm.get("max_joint", "")))
	if j != "":
		lines.append("Тяжелее всего: %s — %d %%" % [_joint_words(j), roundi(float(sm.get("max_muscle_load", sm.get("max_load", 0.0))) * 100.0)])
	var free: PackedStringArray = sm.get("free_joints", PackedStringArray())
	if not free.is_empty():
		lines.append("Болтается свободно: %d" % free.size())
	return "\n".join(lines)


## «Shoulder_L» → «плечо слева».
static func _joint_words(j: String) -> String:
	var base := j.get_slice("_", 0)
	var w := String(CraftEdit.GROUP_TITLES.get(base, "сустав"))
	if j.ends_with("_L"):
		w += " слева"
	elif j.ends_with("_R"):
		w += " справа"
	return w


## Паспорт выбранной детали: масса, энергия, длина; деталь / ветка; шарнир; тяга; действия.
func _refresh_part() -> void:
	var d := ctl.selected_def()
	if d == null:
		return
	var on_stand := String(ctl.selected.get("source", "")) == "stand"
	var uid := String(ctl.selected.get("uid", ""))
	var branch := bool(ctl.selected.get("branch", false))
	part_title.text = PartNames.of(d)
	part_icon.texture = icons.request(d.id)
	var mat_id := ""
	var energy := d.energy
	var mass := d.mass
	var n := {}
	if on_stand:
		n = CraftEdit.find(ctl.blueprint, uid)
		mat_id = String(n.get("mat", ""))
		energy = ctl.blueprint.node_energy(uid)
		mass = ctl.blueprint.node_mass(uid)
		var par := String(n.get("parent", ""))
		part_where.text = "ядро бойца" if par == "" else "на бойце · %s" % _anchor_title(String(n.get("anchor", "")))
		if branch:
			var sub := CraftEdit.subtree(ctl.blueprint, uid)
			mass = 0.0
			energy = 0
			for u in sub:
				mass += ctl.blueprint.node_mass(u)
				energy += ctl.blueprint.node_energy(u)
	else:
		part_where.text = "в библиотеке"
	for c in part_rows.get_children():
		c.queue_free()
	_row(part_rows, "mass", "Масса", "%.1f кг" % mass)
	_row(part_rows, "energy", "Энергия", str(energy), WsStyle.AMBER)
	_row(part_rows, "limb", "Длина", "%.2f м" % CraftEdit.part_length(d))
	if mat_id != "" or (on_stand and d.base_mat != ""):
		_row(part_rows, "material", "Материал", CraftEdit.mat_title(mat_id if mat_id != "" else d.base_mat))
	# деталь / ветка
	for c in branch_row.get_children():
		c.queue_free()
	var sub_n := CraftEdit.subtree(ctl.blueprint, uid).size() if on_stand else 1
	branch_row.visible = on_stand and sub_n > 1
	if branch_row.visible:
		for pair in [[false, "Деталь"], [true, "Ветка · %d" % sub_n]]:
			var want := bool(pair[0])
			var b := Button.new()
			b.text = String(pair[1])
			b.toggle_mode = true
			b.focus_mode = Control.FOCUS_NONE
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.tooltip_text = "Копия и зеркало — только этой детали" if not want else "Копия и зеркало — с тем, что на ней  (Shift-клик)"
			WsStyle.apply_button(b, "tab")
			b.set_pressed_no_signal(branch == want)
			b.pressed.connect(func() -> void: ctl.select_stand(uid, "body", want))
			branch_row.add_child(b)
	# шарнир (у детали на своём суставе)
	for c in joint_row.get_children():
		c.queue_free()
	var jt := ctl.blueprint.joint_type_of(uid) if on_stand else ""
	joint_row.visible = on_stand and jt != "" and String(n.get("parent", "")) != ""
	if joint_row.visible:
		var cap := _caption("Шарнир")
		cap.custom_minimum_size = Vector2(62, 30)
		cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		joint_row.add_child(cap)
		for t in KitJoint.ORDER:
			var tid := String(t)
			var b := Button.new()
			b.text = CraftEdit.joint_title(tid)
			b.toggle_mode = true
			b.focus_mode = Control.FOCUS_NONE
			WsStyle.apply_button(b, "chip")
			b.set_pressed_no_signal(tid == jt)
			b.pressed.connect(func() -> void:
				ctl.set_joint(uid, tid)
				_refresh())
			joint_row.add_child(b)
	# тяга: — / ЛКМ / ПКМ
	for c in pull_row.get_children():
		c.queue_free()
	var host := CraftEdit.host_uid(ctl.blueprint, uid) if on_stand else ""
	pull_row.visible = on_stand and host != "" and host != CraftEdit.root_uid(ctl.blueprint)
	if pull_row.visible:
		var cap2 := _caption("Тяга")
		cap2.custom_minimum_size = Vector2(62, 0)
		pull_row.add_child(cap2)
		var cur := ctl.blueprint.pull_button(host)
		for p in ["", "lmb", "rmb"]:
			var pid := String(p)
			var b := Button.new()
			b.text = String(PULL_TITLES[pid])
			b.toggle_mode = true
			b.focus_mode = Control.FOCUS_NONE
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.tooltip_text = "Без тяги" if pid == "" else "Тянется за мышью, пока зажата %s" % String(PULL_TITLES[pid])
			WsStyle.apply_button(b, "chip")
			b.set_pressed_no_signal(pid == cur)
			b.pressed.connect(func() -> void:
				ctl.set_pull(uid, pid)
				_refresh())
			pull_row.add_child(b)
	# канал активного блока: — / Q / F / C (docs/plan-demo/ACTIVE_BLOCKS.md; цвет выбранного — цвет канала, как плашка на кукле)
	for c in channel_row.get_children():
		c.queue_free()
	channel_row.visible = on_stand and ActiveBlocks.is_active(d.id)
	if channel_row.visible:
		var cap3 := _caption("Канал")
		cap3.custom_minimum_size = Vector2(62, 0)
		channel_row.add_child(cap3)
		var cur_ch := ActiveBlocks.channel_of(n)
		for ch in range(ActiveBlocks.CHANNELS + 1):
			var c_ch := ch
			var b := Button.new()
			b.text = "—" if ch == 0 else ActiveBlocks.key_label("p1", ch)
			b.toggle_mode = true
			b.focus_mode = Control.FOCUS_NONE
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.tooltip_text = "Без канала: в бою молчит" if ch == 0 else "Канал %d: пока зажата %s (P2 — %s, геймпад — %s)" % [ch,
				ActiveBlocks.key_label("p1", ch), ActiveBlocks.key_label("p2", ch), ActiveBlocks.PAD_LABELS[ch - 1]]
			WsStyle.apply_button(b, "chip")
			b.set_pressed_no_signal(ch == cur_ch)
			if ch > 0 and ch == cur_ch:
				b.add_theme_color_override("font_pressed_color", ActiveRig.COL_CH[ch - 1])
			b.pressed.connect(func() -> void:
				ctl.set_channel(uid, c_ch)
				_refresh())
			channel_row.add_child(b)
	part_desc.text = CraftEdit.part_desc(d) if not on_stand or ActiveBlocks.is_active(d.id) else ""
	part_desc.visible = part_desc.text != ""
	# действия
	for c in part_actions.get_children():
		c.queue_free()
	if on_stand:
		var root_part := String(n.get("parent", "")) == ""
		var dup := _action("duplicate", "Копия", "Копия в руку  D")
		dup.disabled = root_part
		dup.pressed.connect(func() -> void: ctl.duplicate_to_hand(uid, "body", bool(ctl.selected.get("branch", false))))
		part_actions.add_child(dup)
		var mir := _action("mirror", "Зеркало", "Зеркальная копия  M")
		mir.disabled = CraftEdit.mirror_place(ctl.blueprint, uid).is_empty()
		mir.pressed.connect(func() -> void: ctl.start_mirror_preview(uid, bool(ctl.selected.get("branch", false))))
		part_actions.add_child(mir)
		var del := _action("delete", "Снять", "Снять с бойца  Del", "danger")
		del.set_meta("ws_sfx_kind", "delete")
		del.disabled = root_part
		del.pressed.connect(func() -> void: ctl.delete_selected())
		part_actions.add_child(del)
	else:
		var ins := _action("plus", "Поставить", "На свободный подходящий разъём (или тащи на бойца)")
		ins.pressed.connect(_on_install)
		part_actions.add_child(ins)


func _action(icon_name: String, text: String, tip: String, kind := "button") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", WsStyle.SIZE_XS + 1)
	WsStyle.apply_button(b, kind)
	WsIcon.add_to_button(b, icon_name, 18.0)
	return b


func _on_install() -> void:
	var d := ctl.selected_def()
	if d == null or String(ctl.selected.get("source", "")) != "shelf":
		return
	ctl.cancel_drag()
	ctl.install_part(d.id)


func _refresh_weapon() -> void:
	var w := ctl.weapon_stats()
	weapon_name.text = String(w["title"]).trim_suffix(" *") if not bool(w["empty"]) else "Верстак пуст — положи рукоять"
	for c in wstats.get_children():
		c.queue_free()
	for r in (w["rows"] as Array):
		_row(wstats, "", String(r["label"]), String(r["value"]))
	var errs: PackedStringArray = w["errors"]
	wproblems.text = errs[0] if not errs.is_empty() else ""
	wproblems.visible = not errs.is_empty()
	var equipped := bool(w["equipped"])
	equip_button.text = "Снять с руки" if equipped else "В руку"
	equip_button.disabled = bool(w["empty"]) and not equipped


func _anchor_title(an: String) -> String:
	var s := an.trim_prefix("Anchor_")
	var side := ""
	if s.ends_with("_L"):
		side = " слева"
		s = s.trim_suffix("_L")
	elif s.ends_with("_R"):
		side = " справа"
		s = s.trim_suffix("_R")
	return String(CraftEdit.GROUP_TITLES.get(s, ANCHOR_WORDS.get(s, s.to_lower()))) + side


# ------------------------------------------------------------------ подсказка, сообщения

func _update_hint() -> void:
	if ctl == null:
		return
	help_line.text = ctl.context_help()


func show_toast(text: String, colour: Color) -> void:
	toast_label.text = text
	toast_label.add_theme_color_override("font_color", colour)
	if _toast_tween != null:
		_toast_tween.kill()
	toast_label.modulate = Color(1, 1, 1, 1)
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_HOLD_S)
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, TOAST_FADE_S)


func _process(delta: float) -> void:
	if ctl == null:
		return
	_hint_t += delta
	if _hint_t > 0.1:
		_hint_t = 0.0
		_update_hint()
		# мышь ушла на панель — подсветка детали под курсором гаснет (движение над панелью до 3D не доходит)
		if not ctl.hover.is_empty() and is_over_panel(get_viewport().get_mouse_position()):
			ctl.set_hover({})
	_update_drag_info(ctl.mode == WorkshopBuild.Mode.BUILD and not ctl.drag.is_empty())
	if ctl.mode == WorkshopBuild.Mode.TEST:
		_update_dummy_panel()


## «+1.5 кг  ⚡ +4  ЦМ →» у детали в руке (над разъёмом); не встанет — причина коротко, красным.
func _update_drag_info(dragging: bool) -> void:
	var t := ctl.drag_target() if dragging else {}
	drag_info.visible = dragging and ctl.physics_hints and not t.is_empty()
	if not drag_info.visible:
		return
	var d := CraftEdit.part(String(ctl.drag["part"]))
	var txt := ""
	if String(t["target"]) == "weapon":
		txt = "[color=#e9dcc4]%s[/color]  ·  +%.1f кг" % [_anchor_title(String(t["anchor"])), d.mass]
	else:
		var pv := ctl.drag_preview()
		if pv.is_empty() or not bool(pv["ok"]):
			var why := String(pv.get("reason", t.get("reason", ""))) if not pv.is_empty() else String(t.get("reason", ""))
			txt = "[color=#ee5a44]%s[/color]" % ("Не хватает энергии" if why.contains("энерги") else (why if why.length() < 40 else "Сюда не встанет"))
		else:
			var s := ctl.body_stats()
			var dm := float(pv["mass"]) - float(s["mass"])
			var de := int(pv["energy"]) - int(s["energy"])
			var com := ""
			if ctl.show_com:
				var g: Variant = ctl.drag_com()
				if g is Vector3:
					var dx := ((g as Vector3).x - ctl.stand_com().x) * 100.0
					com = "  ·  ЦМ %s" % ("→" if dx > 0.5 else ("←" if dx < -0.5 else "·"))
			var repl := ""
			if String(t["replace"]) != "":
				repl = "  ·  [color=#ffb35a]замена[/color]"
			txt = "%+.1f кг  ·  [color=#ffbd4d]⚡ %+d[/color]%s%s" % [dm, de, com, repl]
	drag_info_text.text = txt
	drag_info.reset_size()
	var p: Vector2 = ctl.drag["pos"]
	var vp := root.size
	drag_info.position = (p + Vector2(28, -52)).clamp(Vector2(8, 8), vp - drag_info.size - Vector2(8, 8))


# ------------------------------------------------------------------ испытание

func _on_mode(m: int) -> void:
	var test := m == WorkshopBuild.Mode.TEST
	_close_popups()
	left.visible = not test
	right.visible = not test
	top_bar.visible = not test
	test_button.visible = not test
	drag_info.visible = false
	test_bar.visible = test
	test_stats.visible = test
	dummy_panel.visible = test
	toast_label.offset_top = 88.0 if test else 84.0
	toast_label.offset_bottom = toast_label.offset_top + 56.0
	if test:
		_dmg_total = 0.0
		_dmg_hits = 0
		_dmg_best = 0.0
		_update_test_stats()
		dummy_hp.max_hp = _dummy_max_hp()
		dummy_hp.set_hp(dummy_hp.max_hp, false)
		_last_hit = ""
		# скорость удара, блок кистью и слабые касания (TrainingFeel — WORKSHOP_V3.md §5)
		if ctl.feel != null:
			ctl.feel.hit_fx.connect(_on_feel_hit)
			ctl.feel.weak_contact.connect(_on_weak_contact)
		help_line.position = Vector2(0, root.size.y - 44.0)
		help_line.size = Vector2(root.size.x, 28.0)
	else:
		_layout()
	for c in floaters.get_children():
		c.queue_free()
	_refresh()


func _on_dummy_hit(amount: float, pos: Vector3, part: String, kind: String) -> void:
	_dmg_total += amount
	_dmg_hits += 1
	_dmg_best = maxf(_dmg_best, amount)
	_update_test_stats()
	var cam := get_viewport().get_camera_3d()
	if not _projectable(cam, pos):
		return
	var p := cam.unproject_position(pos)
	var l := Label.new()
	l.text = "%d" % roundi(amount) if amount >= 1.0 else "%.1f" % amount
	if part.begins_with("Head"):
		l.text += "  в голову!"
	elif part.begins_with("Hand"):
		l.text += "  блок"
	l.theme_type_variation = &"AnnounceLabel"
	var fs := int(clampf(34.0 + amount * 1.6, 34.0, 96.0))
	l.add_theme_font_size_override("font_size", fs)
	var col := Color(1.0, 0.95, 0.7) if amount < 8.0 else (Color(1.0, 0.7, 0.25) if amount < 20.0 else Color(1.0, 0.3, 0.18))
	if kind == "weapon":
		col = col.lerp(Color(1.0, 0.85, 0.3), 0.25)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floaters.add_child(l)
	l.reset_size()
	l.position = p - l.size * 0.5 + Vector2(randf_range(-16, 16), -20)
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2(0.6, 0.6)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - FLOAT_RISE, FLOAT_S).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(FLOAT_S - 0.35)
	tw.chain().tween_callback(l.queue_free)


## Точка перед камерой (DynamicCamera в первый кадр испытания ещё стоит в нуле — unproject там не определён).
static func _projectable(cam: Camera3D, p: Vector3) -> bool:
	return cam != null and (p - cam.global_position).dot(-cam.global_basis.z) > cam.near + 0.05


func _update_test_stats() -> void:
	test_stats_text.text = "Урон по манекену: %d\nУдаров: %d   ·   сильнейший: %d%s" % [roundi(_dmg_total), _dmg_hits, roundi(_dmg_best),
		"\n" + _last_hit if _last_hit != "" else ""]


## Удар по манекену (TrainingFeel.hit_fx): скорость под числом урона и строка «последний» в сводке.
func _on_feel_hit(ctx: Dictionary) -> void:
	var v: Variant = ctx.get("victim")
	if not (v is Doll) or not is_instance_valid(v) or (v as Doll) != ctl.dummy.get("doll"):
		return
	var sp := float(ctx.get("speed", 0.0))
	var part := String(ctx.get("part_base", ""))
	var note := "  ·  в кисть ×%.2f" % Tuning.HAND_HIT_MULT if part == "Hand" else ("  ·  в голову ×%.1f" % Tuning.HEAD_HIT_MULT if part == "Head" else "")
	_last_hit = "Последний: %d HP  ·  %.1f м/с%s" % [roundi(float(ctx.get("damage", 0.0))), sp, note]
	_update_test_stats()
	_float_small(ctx.get("position", Vector3.ZERO), "%.1f м/с" % sp, Color(0.85, 0.9, 1.0), Vector2(0, 26))


## Касание манекена ниже порога урона (Tuning.MIN_IMPACT_SPEED): серое «0 · 1.2 м/с» — видно, почему не бьёт.
func _on_weak_contact(victim: Doll, speed: float, pos: Vector3) -> void:
	if victim == null or not is_instance_valid(victim) or victim != ctl.dummy.get("doll"):
		return
	_float_small(pos, "0 · %.1f м/с" % speed, Color(0.7, 0.7, 0.72), Vector2.ZERO)
	_last_hit = "Слабо: %.1f м/с (урон от %.1f м/с)" % [speed, Tuning.MIN_IMPACT_SPEED]
	_update_test_stats()


func _float_small(pos: Vector3, text: String, col: Color, offset: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if not _projectable(cam, pos):
		return
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floaters.add_child(l)
	l.reset_size()
	l.position = cam.unproject_position(pos) - l.size * 0.5 + offset
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - FLOAT_RISE * 0.6, FLOAT_S).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(FLOAT_S - 0.35)
	tw.chain().tween_callback(l.queue_free)


func _update_dummy_panel() -> void:
	var d: Node3D = ctl.dummy
	var cam := get_viewport().get_camera_3d()
	if d == null or not is_instance_valid(d) or cam == null:
		dummy_panel.visible = false
		return
	var top: Vector3 = d.call("head_top")
	dummy_panel.visible = _projectable(cam, top)
	if not dummy_panel.visible:
		return
	var p := cam.unproject_position(top)
	dummy_panel.position = p - Vector2(dummy_panel.size.x * 0.5, dummy_panel.size.y + 6.0)
	var hp := float(d.call("hp"))
	var mx := _dummy_max_hp()
	if not is_equal_approx(mx, dummy_hp.max_hp):   # другой манекен (запас HP куклы — Doll.max_hp)
		dummy_hp.max_hp = mx
		dummy_hp.set_hp(hp, false)
	if not is_equal_approx(hp, dummy_hp.hp):
		dummy_hp.set_hp(hp, true)
	dummy_hp_text.text = "%d / %d" % [roundi(hp), roundi(mx)] if bool(d.call("alive")) else "Нокаут — встаёт…"


## Полный запас HP манекена: TrainingDummy.max_hp() (= Doll.max_hp его куклы), иначе поле max_hp куклы, иначе Tuning.MAX_HP.
func _dummy_max_hp() -> float:
	var d: Node = ctl.dummy if ctl != null else null
	if d == null or not is_instance_valid(d):
		return Tuning.MAX_HP
	if d.has_method("max_hp"):
		return float(d.call("max_hp"))
	var doll: Variant = d.get("doll")
	if doll is Object and is_instance_valid(doll):
		var mh: Variant = (doll as Object).get("max_hp")
		if mh != null and float(mh) > 0.0:
			return float(mh)
	return Tuning.MAX_HP


# ------------------------------------------------------------------ настройки игрока, звук

func _load_prefs() -> void:
	var cf := ConfigFile.new()
	if cf.load(PREFS) != OK:
		return
	favorites = PackedStringArray(cf.get_value("library", "favorites", PackedStringArray()))
	var f: Variant = cf.get_value("library", "filters", {})
	if f is Dictionary:
		for k in filters:
			if (f as Dictionary).has(k) and typeof(f[k]) == typeof(filters[k]):
				filters[k] = f[k]


func _save_prefs() -> void:
	var cf := ConfigFile.new()
	cf.set_value("library", "favorites", favorites)
	cf.set_value("library", "filters", filters)
	cf.save(PREFS)


func _sfx(kind: String) -> void:
	if ctl != null and ctl.sfx != null and is_instance_valid(ctl.sfx):
		ctl.sfx.play(kind)


## Звук кнопок (WsSfx.wire_buttons): наведение — тихий щелчок, нажатие — кнопка / вкладка, «Снять» — удаление, «Испытать» —
## свой. Уже подключённые пропускаются — зовём после каждой пересборки панелей.
func _wire() -> void:
	if ctl != null and ctl.sfx != null and is_instance_valid(ctl.sfx):
		ctl.sfx.wire_buttons(root)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		for p in [templates_popup, builds_popup, filter_popup, help_popup]:
			if p != null and (p as Control).visible:
				_close_popups()
				get_viewport().set_input_as_handled()
				return


## Тонкая полоска энергии под числом: занято (янтарь), «станет» — светлая тень; перебор — красным.
class MiniBar extends Control:
	var frac := 0.0
	var after := -1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_values(f: float, a: float) -> void:
		if is_equal_approx(f, frac) and is_equal_approx(a, after):
			return
		frac = f
		after = a
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0, 0, 0, 0.45))
		var bad := frac > 1.0 or after > 1.0
		var c := WsStyle.RED if bad else WsStyle.AMBER
		if after >= 0.0 and not is_equal_approx(after, frac):
			var x0 := r.size.x * clampf(minf(frac, after), 0.0, 1.0)
			var x1 := r.size.x * clampf(maxf(frac, after), 0.0, 1.0)
			draw_rect(Rect2(x0, 0, x1 - x0, r.size.y), Color(c, 0.45))
		draw_rect(Rect2(Vector2.ZERO, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), c)
