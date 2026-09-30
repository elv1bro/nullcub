## UI мастерской v0.2 (docs/plan-demo/WORKSHOP_V3.md §8: «как в играх ААА», стиль — тёплая деревянная мастерская, не sci-fi).
## Дерево — workshop_ui.tscn, здесь поведение: bind(WorkshopBuild) →
##   верх: табличка МАСТЕРСКАЯ + «?» (легенда значков и клавиш), энергия ядра по центру, ↶ / ↷, СОХРАНИТЬ, МОИ СБОРКИ;
##   слева каталог: ШАБЛОН ‹ имя › и плитки избранных шаблонов (FEATURED; стрелки листают все), категории-иконки (CraftEdit.BODY_SHELVES,
##     иконка — рендер детали PartIcons; последняя — ОРУЖИЕ / ← ТЕЛО, вид верстака), поиск по названию (по всем категориям), ⚡ — только
##     то, что влезает по энергии, сортировка; детали группами (руки / ноги, кисти / стопы…) крупными карточками part_card.gd — на карточке
##     только ⚡ и кг; у вкладок с инструментом — плашки материалов / шарниров / покраска (paint_panel.gd) над деталями;
##   справа контекстная панель: ничего не выбрано — ХАРАКТЕРИСТИКИ СБОРКИ (масса, детали, разгон, управляемость, устойчивость, прочность,
##     энергия; переключатели Physics Overlay: центр массы, физические подсказки; тяги ЛКМ / ПКМ; ошибки словами); выбрана деталь (клик
##     по карточке или по кукле) — её паспорт (масса, энергия здесь, длина, прочность, тип, что делает) и УСТАНОВИТЬ / ДУБЛИКАТ / ЗЕРКАЛИТЬ /
##     УДАЛИТЬ; вид ОРУЖИЕ — верстак (характеристики, «В руку»);
##   низ: ▶ ИСПЫТАТЬ СБОРКУ [T], строка клавиш; подсказка — только когда в руке инструмент / деталь (контекстно), при протяжке у разъёма —
##     всплывашка «Совместимый разъём» (что встанет, энергия, масса, сдвиг центра массы).
## В испытании — плашка ИСПЫТАНИЕ, счёт урона, табличка HP над манекеном и цифры урона в точке удара.
## Все размеры — в базовом вьюпорте 1920×1080 (project.godot: stretch canvas_items).
extends CanvasLayer

const PartCard := preload("res://scenes/workshop/ui/part_card.gd")
const MaterialCard := preload("res://scenes/workshop/ui/material_card.gd")
const JointCard := preload("res://scenes/workshop/ui/joint_card.gd")
const PaintPanel := preload("res://scenes/workshop/ui/paint_panel.gd")
## Короткие подписи шаблонов (полные — в подсказке).
const PRESET_SHORT := {
	"human": "Человек", "spider": "Паук", "long_arm": "Длинная рука", "big_arm": "Силач", "legless": "Безногий", "junk": "Хлам",
	"flail": "Кистень", "kit_human": "Кукла-кит", "kit_brawler": "Громила", "kit_bot": "Робот", "kit_horned": "Рогатый",
	"kit_king": "Король", "kit_spider": "Паук", "kit_devil": "Чёртик", "kit_skull": "Скелет", "kit_wheels": "Каталка",
	"kit_lantern": "Фонарщик", "kit_graffiti": "Граффити", "kit_camo": "Камуфляж", "kit_spinner": "Вертушка", "kit_empty": "Пустой",
	"mallet": "Киянка", "hammer": "Молот", "spiked_hammer": "С гвоздями", "heavy_hammer": "Тяжёлый",
	"long_hammer": "Длинный", "sword": "Меч", "axe": "Топор", "concept_hammer": "Концепт",
}
## Плитки шаблонов (UI v0.2): Робот / Паук / Длинная рука / Вертушка / Пустой; иконка плитки — деталь (PartIcons).
const FEATURED := [["kit_bot", "kit_head_bot"], ["kit_spider", "kit_limb_basic_l"], ["long_arm", "wood_upper_arm"],
	["kit_spinner", "head_mace_ball"], ["kit_empty", "kit_core_ball"]]
## Группы деталей внутри категории: [заголовок, условие] — условие по PartDef (вид / префикс имени тела).
const GROUPS := {
	"limb": [["РУКИ", "arm"], ["НОГИ", "leg"]],
	"end": [["КИСТИ", "hand"], ["СТОПЫ", "foot"]],
	"armor": [["БРОНЯ И ЩИТКИ", "armor"], ["НАВЕРШИЯ И МОДЫ", "weapon"]],
}
const SORTS := ["По энергии", "По массе", "По названию"]
## Разъёмы словами во всплывашке (кроме групп мышц CraftEdit.GROUP_TITLES).
const ANCHOR_WORDS := {"Face": "боёк", "End": "конец", "Side": "бок", "Top": "макушка", "Back": "спина", "Deco": "накладка",
	"Plate": "щиток", "Head": "навершие", "Mod": "мод", "Tip": "кончик", "Grip": "хват", "Spike": "шип"}
## Строка над инструментом вкладки (CraftEdit.BODY_SHELVES tool).
const TOOL_HINTS := {
	"material": "Выбери материал и кликай по деталям куклы: масса меняется как новая плотность / прежняя (дерево = 1). Старые детали (не кит) не красятся.",
	"joint": "Выбери тип и кликай по детали — так она держится за родителя. У ядра и декора шарнира нет.",
}
const TOAST_Y_BUILD := 104.0
const TOAST_Y_TEST := 112.0
const TOAST_HOLD_S := 1.9
const TOAST_FADE_S := 0.35
const FLOAT_S := 1.1
const FLOAT_RISE := 90.0
const CAT_W := 104.0

var ctl: WorkshopBuild
var icons: PartIcons
var shelf_tab := {"body": "limb", "weapon": "weapon_head"}
var _cards: Dictionary = {}          # part id -> карточка
var _tool_cards: Dictionary = {}     # id материала / тип шарнира -> плашка инструмента текущей вкладки
var _tool := ""                      # инструмент текущей вкладки: "material" | "joint" | ""
var _cat_icons: Dictionary = {}      # part id иконки -> [TextureRect категорий / плиток шаблонов]
var _hint_t := 0.0
var _toast_tween: Tween
var _dmg_total := 0.0
var _dmg_hits := 0
var _last_hit := ""   # строка сводки: последний удар (скорость, куда) или слабое касание
var _dmg_best := 0.0
var _preset_buttons: Array = []
var _preset_index := 0

@onready var root: Control = $Root
@onready var overlay: Control = $Root/Overlay
@onready var floaters: Control = $Root/Floaters
@onready var top_bar: Control = $Root/TopBar
@onready var help_button: Button = $Root/TopBar/TitlePlate/H/HelpButton
@onready var energy_value: Label = $Root/TopBar/EnergyPlate/V/EnergyHead/EnergyValue
@onready var energy_bar: Control = $Root/TopBar/EnergyPlate/V/Energy
@onready var undo_button: Button = $Root/TopBar/Tools/UndoButton
@onready var redo_button: Button = $Root/TopBar/Tools/RedoButton
@onready var save_button: Button = $Root/TopBar/Tools/SaveButton
@onready var load_button: Button = $Root/TopBar/Tools/LoadButton
@onready var left: Control = $Root/Left
@onready var template_name: Label = $Root/Left/VBox/TemplateRow/TemplateName
@onready var prev_template: Button = $Root/Left/VBox/TemplateRow/PrevTemplate
@onready var next_template: Button = $Root/Left/VBox/TemplateRow/NextTemplate
@onready var presets_box: GridContainer = $Root/Left/VBox/Presets
@onready var presets_title: Label = $Root/Left/VBox/PresetsTitle
@onready var shelf_tabs: GridContainer = $Root/Left/VBox/ShelfTabs
@onready var search: LineEdit = $Root/Left/VBox/SearchRow/Search
@onready var fits_only: Button = $Root/Left/VBox/SearchRow/FitsOnly
@onready var sort_button: OptionButton = $Root/Left/VBox/SearchRow/Sort
@onready var shelf_scroll: ScrollContainer = $Root/Left/VBox/ShelfScroll
@onready var tool_hint: Label = $Root/Left/VBox/ShelfScroll/ShelfBox/ToolHint
@onready var tools_box: GridContainer = $Root/Left/VBox/ShelfScroll/ShelfBox/Tools
@onready var parts_title: Label = $Root/Left/VBox/ShelfScroll/ShelfBox/PartsTitle
@onready var shelf: VBoxContainer = $Root/Left/VBox/ShelfScroll/ShelfBox/Shelf
@onready var right: Control = $Root/Right
@onready var body_box: Control = $Root/Right/VBox/BodyBox
@onready var build_title: Label = $Root/Right/VBox/BodyBox/BuildTitle
@onready var stats_box: VBoxContainer = $Root/Right/VBox/BodyBox/Stats
@onready var com_toggle: CheckButton = $Root/Right/VBox/BodyBox/Toggles/ComToggle
@onready var hints_toggle: CheckButton = $Root/Right/VBox/BodyBox/Toggles/HintsToggle
@onready var control_label: Label = $Root/Right/VBox/BodyBox/ControlBox/V/ControlLabel
@onready var control_button: Button = $Root/Right/VBox/BodyBox/ControlBox/V/ControlButton
@onready var weapon_line: Label = $Root/Right/VBox/BodyBox/ControlBox/V/WeaponLine
@onready var problems: Label = $Root/Right/VBox/BodyBox/Problems
@onready var part_box: Control = $Root/Right/VBox/PartBox
@onready var part_title: Label = $Root/Right/VBox/PartBox/Head/PartTitle
@onready var part_where: Label = $Root/Right/VBox/PartBox/Where
@onready var part_icon: TextureRect = $Root/Right/VBox/PartBox/Info/Icon
@onready var part_grid: GridContainer = $Root/Right/VBox/PartBox/Info/Grid
@onready var part_desc: Label = $Root/Right/VBox/PartBox/Desc
@onready var install_button: Button = $Root/Right/VBox/PartBox/Actions/InstallButton
@onready var duplicate_button: Button = $Root/Right/VBox/PartBox/Actions/DuplicateButton
@onready var mirror_button: Button = $Root/Right/VBox/PartBox/Actions/MirrorButton
@onready var delete_button: Button = $Root/Right/VBox/PartBox/Actions/DeleteButton
@onready var weapon_box: Control = $Root/Right/VBox/WeaponBox
@onready var weapon_name: Label = $Root/Right/VBox/WeaponBox/WeaponName
@onready var wstats: VBoxContainer = $Root/Right/VBox/WeaponBox/WStats
@onready var wproblems: Label = $Root/Right/VBox/WeaponBox/WProblems
@onready var equip_button: Button = $Root/Right/VBox/WeaponBox/EquipButton
@onready var equip_info: Label = $Root/Right/VBox/WeaponBox/EquipInfo
@onready var clear_button: Button = $Root/Right/VBox/WeaponBox/ClearButton
@onready var help_panel: Control = $Root/HelpPanel
@onready var legend: Control = $Root/HelpPanel/Legend
@onready var test_button: Button = $Root/TestButton
@onready var keys_bar: Label = $Root/KeysBar
@onready var hint_bar: Control = $Root/HintBar
@onready var hint: Label = $Root/HintBar/Hint
@onready var drag_info: Control = $Root/DragInfo
@onready var drag_info_text: RichTextLabel = $Root/DragInfo/Text
@onready var toast_label: Label = $Root/Toast
@onready var test_bar: Control = $Root/TestBar
@onready var back_button: Button = $Root/TestBar/BackButton
@onready var test_stats: Control = $Root/TestStats
@onready var test_stats_text: Label = $Root/TestStats/Text
@onready var dummy_panel: Control = $Root/DummyPanel
@onready var dummy_hp: HpBar = $Root/DummyPanel/Hp
@onready var dummy_hp_text: Label = $Root/DummyPanel/HpText
@onready var drag_icon: TextureRect = $Root/DragIcon
@onready var save_popup: Control = $Root/SavePopup
@onready var name_edit: LineEdit = $Root/SavePopup/V/NameEdit
@onready var load_popup: Control = $Root/LoadPopup
@onready var load_list: VBoxContainer = $Root/LoadPopup/V/Scroll/List
@onready var load_empty: Label = $Root/LoadPopup/V/Empty


func _ready() -> void:
	icons = PartIcons.new()
	icons.name = "PartIcons"
	add_child(icons)
	icons.icon_ready.connect(_on_icon)
	control_button.pressed.connect(func() -> void: ctl.toggle_control_pick())
	save_button.pressed.connect(_open_save)
	load_button.pressed.connect(_open_load)
	undo_button.pressed.connect(func() -> void: ctl.undo())
	redo_button.pressed.connect(func() -> void: ctl.redo())
	equip_button.pressed.connect(func() -> void: ctl.weapon_to_hand())
	clear_button.pressed.connect(func() -> void: ctl.clear_weapon())
	test_button.pressed.connect(func() -> void: ctl.start_test())
	back_button.pressed.connect(func() -> void: ctl.stop_test())
	help_button.toggled.connect(func(on: bool) -> void: help_panel.visible = on)
	prev_template.pressed.connect(func() -> void: _step_template(-1))
	next_template.pressed.connect(func() -> void: _step_template(1))
	search.text_changed.connect(func(_t: String) -> void: _build_shelf())
	fits_only.toggled.connect(func(_on: bool) -> void: _build_shelf())
	for s in SORTS:
		sort_button.add_item(s)
	sort_button.item_selected.connect(func(_i: int) -> void: _build_shelf())
	com_toggle.toggled.connect(func(on: bool) -> void: ctl.show_com = on)
	hints_toggle.toggled.connect(func(on: bool) -> void: ctl.physics_hints = on)
	install_button.pressed.connect(_on_install)
	duplicate_button.pressed.connect(func() -> void:
		if String(ctl.selected.get("source", "")) == "stand":
			ctl.duplicate_part(String(ctl.selected["uid"]), String(ctl.selected["target"])))
	mirror_button.pressed.connect(func() -> void:
		if String(ctl.selected.get("source", "")) == "stand":
			ctl.mirror_part(String(ctl.selected["uid"])))
	delete_button.pressed.connect(func() -> void: ctl.delete_selected())
	$Root/Right/VBox/PartBox/Head/CloseButton.pressed.connect(func() -> void: ctl.clear_selection())
	$Root/SavePopup/V/Buttons/OkButton.pressed.connect(_do_save)
	$Root/SavePopup/V/Buttons/CancelButton.pressed.connect(func() -> void: save_popup.visible = false)
	name_edit.text_submitted.connect(func(_t: String) -> void: _do_save())
	$Root/LoadPopup/V/CloseButton.pressed.connect(func() -> void: load_popup.visible = false)


func bind(c: WorkshopBuild) -> void:
	ctl = c
	overlay.set("ctl", c)
	ctl.changed.connect(_refresh)
	ctl.toast.connect(show_toast)
	ctl.mode_changed.connect(_on_mode)
	ctl.view_changed.connect(func(_v: int) -> void: _build_left())
	ctl.dummy_hit.connect(_on_dummy_hit)
	ctl.selection_changed.connect(_refresh)
	if ctl.paint != null:
		ctl.paint.open_tab.connect(open_paint_tab)   # файл брошен в окно — полка покраски
	com_toggle.set_pressed_no_signal(ctl.show_com)
	hints_toggle.set_pressed_no_signal(ctl.physics_hints)
	_build_left()
	_refresh()


## Открыть вкладку «Покраска» (вид — ТЕЛО).
func open_paint_tab() -> void:
	if ctl.view != WorkshopBuild.View.BODY:
		ctl.set_view(WorkshopBuild.View.BODY)
	shelf_tab["body"] = "paint"
	_build_left()


## Точка над панелью / всплывающим окном (клик туда не ставит деталь в «липком» режиме протяжки).
func is_over_panel(p: Vector2) -> bool:
	for c in [left, right, save_popup, load_popup, test_bar, top_bar.get_node("TitlePlate"), top_bar.get_node("Tools"), test_button, help_panel]:
		if (c as Control).visible and (c as Control).get_global_rect().has_point(p):
			return true
	return false


# ------------------------------------------------------------------ каталог

func _view_key() -> String:
	return "weapon" if ctl.view == WorkshopBuild.View.WEAPON else "body"


func _build_left() -> void:
	if ctl == null:
		return
	var weapon := ctl.view == WorkshopBuild.View.WEAPON
	var painting := not weapon and String(shelf_tab["body"]) == "paint"
	presets_title.visible = false
	# шаблоны: ‹ имя › и плитки избранных (у оружия — все пресеты верстака плитками)
	for c in presets_box.get_children():
		c.queue_free()
	_preset_buttons.clear()
	_cat_icons.clear()
	presets_box.visible = not painting
	$Root/Left/VBox/TemplateRow.visible = not painting
	var tiles: Array = []
	if weapon:
		for id in CraftEdit.WEAPON_PRESETS:
			tiles.append([String(id), _weapon_icon_part(String(id))])
	else:
		tiles = FEATURED
	presets_box.columns = 5
	for t in tiles:
		var pid := String(t[0])
		var b := _tile_button(String(PRESET_SHORT.get(pid, _preset_title(pid, weapon))), String(t[1]), 78.0)
		b.tooltip_text = _preset_title(pid, weapon)
		if weapon:
			b.pressed.connect(func() -> void: ctl.set_weapon_preset(pid))
		else:
			b.pressed.connect(func() -> void:
				_preset_index = maxi(CraftEdit.BODY_PRESETS.find(pid), 0)
				ctl.set_preset(pid))
		presets_box.add_child(b)
		_preset_buttons.append(b)
	# категории-иконки (+ ОРУЖИЕ / ← ТЕЛО)
	for c in shelf_tabs.get_children():
		c.queue_free()
	var shelves: Array = CraftEdit.WEAPON_SHELVES if weapon else CraftEdit.BODY_SHELVES
	for s in shelves:
		var sid := String(s["id"])
		var stool := String(s.get("tool", ""))
		var b2 := _cat_button(String(s["title"]).to_upper(), String(s.get("icon", "")), String(s.get("glyph", "")),
			sid == String(shelf_tab[_view_key()]))
		b2.pressed.connect(func() -> void:
			var was := String(shelf_tab[_view_key()])
			shelf_tab[_view_key()] = sid
			if ctl.active_tool() in ["material", "joint", "paint"] and ctl.active_tool() != stool:
				ctl.clear_tools()   # ушёл с вкладки инструмента — кисть / шарнир / баллончик кладутся
			if was == "paint" and sid != "paint" and ctl.paint != null:
				ctl.paint.reset_turn()   # стенд снова лицом
			if sid == "paint" and was != "paint" and ctl.paint != null and ctl.paint.tool == "":
				ctl.paint.set_tool("spray")   # пришёл красить — баллончик сразу в руке
			_build_left())
		shelf_tabs.add_child(b2)
	var vb := _cat_button("← ТЕЛО" if weapon else "ОРУЖИЕ", "" if weapon else "kit_drill_head", "⚙" if weapon else "", false)
	vb.pressed.connect(func() -> void: _set_view(WorkshopBuild.View.BODY if weapon else WorkshopBuild.View.WEAPON))
	shelf_tabs.add_child(vb)
	$Root/Left/VBox/SearchRow.visible = not painting
	_build_shelf()
	_update_template_name()


func _set_view(v: int) -> void:
	ctl.set_view(v)
	_build_left()
	_refresh()


## Кнопка-плитка: иконка детali (PartIcons) и подпись под ней.
func _tile_button(text: String, icon_part: String, h: float) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, h + 26.0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 0)
	b.add_child(v)
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(0, h)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tr)
	_bind_icon(tr, icon_part)
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 14)
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l)
	return b


## Кнопка категории: иконка детали (или значок glyph) и мелкая подпись; выбранная — золотая.
func _cat_button(text: String, icon_part: String, glyph: String, on: bool) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(CAT_W, 62)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.tooltip_text = text.capitalize()
	b.set_pressed_no_signal(on)
	b.add_theme_stylebox_override("pressed", _gold_style())
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 0)
	b.add_child(v)
	if glyph != "":
		var g := Label.new()
		g.text = glyph
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		g.add_theme_font_size_override("font_size", 26)
		g.size_flags_vertical = Control.SIZE_EXPAND_FILL
		g.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(g)
	else:
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(0, 38)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(tr)
		_bind_icon(tr, icon_part)
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 13)
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l)
	return b


func _bind_icon(tr: TextureRect, part_id: String) -> void:
	if part_id == "":
		return
	var tex := icons.request(part_id)
	if tex != null:
		tr.texture = tex
	else:
		if not _cat_icons.has(part_id):
			_cat_icons[part_id] = []
		(_cat_icons[part_id] as Array).append(tr)


func _gold_style() -> StyleBox:
	return control_button.get_theme_stylebox("pressed")


## Иконка плитки оружия — его навершие (иначе рукоять).
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


## ‹ › — листать все шаблоны тела.
func _step_template(d: int) -> void:
	if ctl.view == WorkshopBuild.View.WEAPON:
		return
	var ids: Array = CraftEdit.BODY_PRESETS
	_preset_index = wrapi(_preset_index + d, 0, ids.size())
	ctl.set_preset(String(ids[_preset_index]))


func _update_template_name() -> void:
	if ctl == null:
		return
	if ctl.view == WorkshopBuild.View.WEAPON:
		template_name.text = ctl.weapon_bp.title if ctl.weapon_bp != null else "Оружие"
		prev_template.visible = false
		next_template.visible = false
		return
	prev_template.visible = true
	next_template.visible = true
	template_name.text = ctl.blueprint.title if ctl.blueprint != null else ""


func _build_shelf() -> void:
	for c in shelf.get_children():
		c.queue_free()
	for c in tools_box.get_children():
		c.queue_free()
	_cards.clear()
	_tool_cards.clear()
	var weapon := ctl.view == WorkshopBuild.View.WEAPON
	var shelves: Array = CraftEdit.WEAPON_SHELVES if weapon else CraftEdit.BODY_SHELVES
	var sh := CraftEdit.shelf_of(shelves, String(shelf_tab[_view_key()]))
	var kinds: Array = sh.get("kinds", [])
	_tool = String(sh.get("tool", ""))
	if ctl.paint != null:
		ctl.paint.tab_open = _tool == "paint"
	var query := search.text.strip_edges().to_lower()
	# инструмент вкладки (кит v2, BODY_KIT.md §5.5): плашки материалов (2 колонки) / типов шарнира (строки) над деталями
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
	# детали: поиск — по всем категориям вида; иначе — категория группами
	var groups: Array = []   # [[заголовок, [PartDef]]]
	if query != "":
		for s in shelves:
			var found: Array = []
			for d in CraftEdit.parts_of_kinds(s.get("kinds", [])):
				if d.title.to_lower().contains(query) or d.id.contains(query):
					found.append(d)
			if not found.is_empty():
				groups.append([String(s["title"]).to_upper(), found])
	else:
		var defs := CraftEdit.parts_of_kinds(kinds)
		var gdef: Array = GROUPS.get(String(sh.get("id", "")), [])
		if gdef.is_empty() or weapon:
			groups.append(["", defs])
		else:
			for g in gdef:
				var part: Array = []
				for d in defs:
					if _in_group(d, String(g[1])):
						part.append(d)
				if not part.is_empty():
					groups.append([String(g[0]), part])
	var free_e := ctl.energy_free()
	var total := 0
	for g in groups:
		var list: Array = []
		for d in (g[1] as Array):
			if fits_only.button_pressed and not weapon and (d as PartDef).energy > free_e:
				continue
			list.append(d)
		list.sort_custom(_sorter())
		if list.is_empty():
			continue
		if String(g[0]) != "":
			shelf.add_child(_group_header(String(g[0]), list.size()))
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		shelf.add_child(grid)
		for d in list:
			var card := PartCard.new()
			card.setup(d, not weapon)   # на полке тела навершие — только масса и форма (подсказка)
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			card.grabbed.connect(_on_card_grabbed)
			grid.add_child(card)
			_cards[d.id] = card
			var tex := icons.request(d.id)
			if tex != null:
				card.set_icon(tex)
			total += 1
	parts_title.visible = false
	if total == 0 and not (_tool != "" and query == ""):
		var l := Label.new()
		l.text = "Ничего не найдено" if query != "" else ("Всё дороже свободной энергии (⚡ %d)" % free_e if fits_only.button_pressed else "Пусто")
		l.add_theme_color_override("font_color", Color(0.8, 0.72, 0.62))
		shelf.add_child(l)
	shelf_scroll.scroll_vertical = 0
	_update_card_fits()
	_update_tool_cards()


func _in_group(d: PartDef, g: String) -> bool:
	match g:
		"arm": return d.name_prefix.contains("Arm") or d.id.ends_with("_s")
		"leg": return not (d.name_prefix.contains("Arm") or d.id.ends_with("_s"))
		"hand": return d.kind == "hand"
		"foot": return d.kind == "foot"
		"armor": return d.kind in ["plate", "armor"]
		"weapon": return d.kind in ["mod", "weapon_head"]
	return true


func _sorter() -> Callable:
	match sort_button.selected:
		1: return func(a: PartDef, b: PartDef) -> bool: return a.mass < b.mass
		2: return func(a: PartDef, b: PartDef) -> bool: return a.title.naturalnocasecmp_to(b.title) < 0
	return func(a: PartDef, b: PartDef) -> bool: return a.energy < b.energy or (a.energy == b.energy and a.mass < b.mass)


func _group_header(text: String, n: int) -> Control:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = "▾  %s" % text
	l.theme_type_variation = &"SmallCaps"
	l.add_theme_font_size_override("font_size", 19)
	h.add_child(l)
	var sep := HSeparator.new()
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sep)
	var c := Label.new()
	c.text = str(n)
	c.add_theme_color_override("font_color", Color(0.7, 0.62, 0.52))
	c.add_theme_font_size_override("font_size", 16)
	h.add_child(c)
	return h


## Выбранная плашка инструмента — золотая (кисть / шарнир в руке у WorkshopBuild).
func _update_tool_cards() -> void:
	if ctl == null:
		return
	var sel := ctl.paint_mat if _tool == "material" else (ctl.joint_pick if _tool == "joint" else "")
	if _tool == "paint":
		return
	for id in _tool_cards:
		(_tool_cards[id]).set_selected(String(id) == sel)


func _on_icon(part_id: String, tex: Texture2D) -> void:
	if _cards.has(part_id):
		(_cards[part_id]).set_icon(tex)
	for tr in (_cat_icons.get(part_id, []) as Array):
		if is_instance_valid(tr):
			(tr as TextureRect).texture = tex
	if drag_icon.visible and ctl != null and not ctl.drag.is_empty() and String(ctl.drag["part"]) == part_id:
		drag_icon.texture = tex
	if ctl != null and ctl.selected_def() != null and ctl.selected_def().id == part_id:
		part_icon.texture = tex


func _on_card_grabbed(part_id: String, pos: Vector2) -> void:
	if ctl.mode != WorkshopBuild.Mode.BUILD:
		return
	ctl.select_shelf(part_id)   # справа — паспорт детали и УСТАНОВИТЬ
	ctl.begin_drag(part_id, pos)
	drag_icon.texture = icons.request(part_id)


func _on_install() -> void:
	var d := ctl.selected_def()
	if d == null or String(ctl.selected.get("source", "")) != "shelf":
		return
	ctl.cancel_drag()
	ctl.install_part(d.id)


func _update_card_fits() -> void:
	if ctl == null:
		return
	var free_e := ctl.energy_free()
	for id in _cards:
		var d := CraftEdit.part(String(id))
		(_cards[id]).set_fits(d == null or d.energy <= free_e or ctl.view == WorkshopBuild.View.WEAPON)


# ------------------------------------------------------------------ правая панель, энергия

func _refresh() -> void:
	if ctl == null:
		return
	var weapon := ctl.view == WorkshopBuild.View.WEAPON
	var sel := not weapon and ctl.selected_def() != null
	body_box.visible = not weapon and not sel
	part_box.visible = sel
	weapon_box.visible = weapon
	var s := ctl.body_stats()
	build_title.text = String(s["title"]) if String(s["title"]) != "" else "Своя сборка"
	var used := int(s["energy"])
	var budget := int(s["budget"])
	var preview := -1
	var t := ctl.drag_target()
	if not t.is_empty() and String(t["target"]) == "body":
		var c := CraftEdit.check(ctl.blueprint, String(ctl.drag["part"]), String(t["uid"]), String(t["anchor"])) if not bool(t["root"]) \
			else CraftEdit.check_root(ctl.blueprint, String(ctl.drag["part"]))
		preview = int(c["energy_after"])
	(energy_bar as Object).call("set_values", used, budget, preview)
	energy_value.text = "%d / %d" % [used, budget] if preview < 0 else "%d → %d / %d" % [used, preview, budget]
	energy_value.add_theme_color_override("font_color", (energy_bar as Object).call("colour_for", float(maxi(used, preview)) / float(maxi(budget, 1))))
	_fill_stats(s)
	control_label.text = "Тяги: %s" % (String(s["control"]) if String(s["control"]) != "" else "— нет")
	control_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4) if String(s["control"]) != "" else Color(0.9, 0.6, 0.45))
	control_button.set_pressed_no_signal(ctl.control_pick)
	control_button.text = "КЛИКАЙ ПО ДЕТАЛЯМ…" if ctl.control_pick else "ТЯГИ ЛКМ / ПКМ   [Q]"
	weapon_line.text = "Оружие: %s" % (String(s["weapon"]) if String(s["weapon"]) != "" else "нет  (категория ОРУЖИЕ → «В руку»)")
	var lines: PackedStringArray = []
	for e in (s["errors"] as PackedStringArray):
		lines.append("✖ " + e)
	for w in (s["warnings"] as PackedStringArray):
		lines.append("• " + w)
	problems.text = "\n".join(lines)
	problems.visible = not lines.is_empty()
	problems.add_theme_color_override("font_color", Color(1, 0.45, 0.35) if not (s["errors"] as PackedStringArray).is_empty() else Color(1.0, 0.78, 0.4))
	undo_button.disabled = ctl.history.is_empty()
	redo_button.disabled = ctl.redo_stack.is_empty()
	test_button.disabled = not (s["errors"] as PackedStringArray).is_empty()
	test_button.tooltip_text = "" if not test_button.disabled else "Сначала исправь: %s" % (s["errors"] as PackedStringArray)[0]
	if sel:
		_refresh_part()
	_refresh_weapon()
	_update_card_fits()
	_update_tool_cards()
	_update_template_name()
	_update_hint()


## ХАРАКТЕРИСТИКИ СБОРКИ: строки с полосками (UI v0.2).
func _fill_stats(s: Dictionary) -> void:
	for c in stats_box.get_children():
		c.queue_free()
	var wm := float(s["weapon_mass"])
	var acc := float(s["accel"])
	stats_box.add_child(_bar_row("⚖  Масса", "%.1f кг" % float(s["mass"]) if wm <= 0.0 else "%.1f + %.1f кг" % [float(s["mass"]), wm], -1.0))
	stats_box.add_child(_bar_row("⚙  Деталей", "%d  (%d)" % [int(s["bodies"]), int(s["parts"])], -1.0))
	stats_box.add_child(_bar_row("➚  Разгон", "×%.2f" % acc, clampf(acc / 1.5, 0.0, 1.0)))
	stats_box.add_child(_bar_row("✥  Управляемость", "%d%%" % roundi(float(s["handling"]) * 100.0), float(s["handling"])))
	stats_box.add_child(_bar_row("⚓  Устойчивость", "%d%%" % roundi(float(s["stability"]) * 100.0), float(s["stability"])))
	stats_box.add_child(_bar_row("⛨  Прочность", "%d%%" % roundi(float(s["durability"]) * 100.0), float(s["durability"])))
	stats_box.add_child(_bar_row("⚡  Энергия ядра", "%d / %d" % [int(s["energy"]), int(s["budget"])],
		float(s["energy"]) / maxf(float(s["budget"]), 1.0)))


func _bar_row(label: String, value: String, frac: float) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = label
	l.theme_type_variation = &"StatLabel"
	l.add_theme_font_size_override("font_size", 17)
	l.custom_minimum_size = Vector2(186, 0)
	l.clip_text = true
	h.add_child(l)
	if frac >= 0.0:
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 10)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.max_value = 1.0
		bar.value = clampf(frac, 0.02, 1.0)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.05, 0.045, 0.04, 0.9)
		bg.set_corner_radius_all(3)
		var fg := StyleBoxFlat.new()
		fg.bg_color = Color(0.95, 0.62, 0.25) if frac < 0.95 else Color(1.0, 0.4, 0.25)
		fg.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fg)
		h.add_child(bar)
	else:
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(sp)
	var v := Label.new()
	v.text = value
	v.theme_type_variation = &"StatValue"
	v.add_theme_font_size_override("font_size", 20)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.custom_minimum_size = Vector2(76, 0)
	h.add_child(v)
	return h


## Паспорт выбранной детали и действия.
func _refresh_part() -> void:
	var d := ctl.selected_def()
	if d == null:
		return
	var on_stand := String(ctl.selected.get("source", "")) == "stand"
	var uid := String(ctl.selected.get("uid", ""))
	part_title.text = d.title
	var mat_id := ""
	var energy := d.energy
	if on_stand:
		var n := CraftEdit.find(ctl.blueprint, uid)
		mat_id = String(n.get("mat", ""))
		energy = ctl.blueprint.node_energy(uid)
		part_where.text = "на кукле  ·  %s" % ("вынос %.2f м" % float(ctl.blueprint.node_reach().get(uid, 0.0)))
	else:
		part_where.text = "в каталоге  ·  тяни на куклу или УСТАНОВИТЬ"
	var tex := icons.request(d.id)
	part_icon.texture = tex
	for c in part_grid.get_children():
		c.queue_free()
	var dur := CraftEdit.part_durability(d, mat_id)
	var stars := clampi(1 + roundi(dur * 2.0), 1, 3)
	var mass := ctl.blueprint.node_mass(uid) if on_stand else d.mass
	for row in [["Масса", "%.1f кг" % mass], ["Энергия", ("⚡%d здесь" % energy) if on_stand else "⚡%d+" % energy],
			["Длина", "%.2f м" % CraftEdit.part_length(d)], ["Прочность", "★".repeat(stars) + "☆".repeat(3 - stars)],
			["Тип", String(CraftEdit.KIND_TITLES.get(d.kind, d.kind)).capitalize()]]:
		var l := Label.new()
		l.text = String(row[0])
		l.theme_type_variation = &"StatLabel"
		l.add_theme_font_size_override("font_size", 18)
		part_grid.add_child(l)
		var v := Label.new()
		v.text = String(row[1])
		v.theme_type_variation = &"StatValue"
		v.add_theme_font_size_override("font_size", 19)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		part_grid.add_child(v)
	part_desc.text = CraftEdit.part_desc(d)
	install_button.visible = not on_stand
	duplicate_button.disabled = not on_stand
	mirror_button.disabled = not on_stand or CraftEdit.mirror_place(ctl.blueprint, uid).is_empty()
	delete_button.disabled = not on_stand or String(CraftEdit.find(ctl.blueprint, uid).get("parent", "")) == ""
	install_button.text = "УСТАНОВИТЬ"


func _refresh_weapon() -> void:
	var w := ctl.weapon_stats()
	weapon_name.text = String(w["title"]) if not bool(w["empty"]) else "Пусто — положи рукоять"
	for c in wstats.get_children():
		c.queue_free()
	for r in (w["rows"] as Array):
		wstats.add_child(_bar_row(String(r["label"]), String(r["value"]), float(r["frac"])))
	var errs: PackedStringArray = w["errors"]
	wproblems.text = "✖ " + errs[0] if not errs.is_empty() else ""
	var equipped := bool(w["equipped"])
	equip_button.text = "СНЯТЬ С РУКИ" if equipped else "В РУКУ"
	equip_button.disabled = bool(w["empty"]) and not equipped
	var s := ctl.body_stats()
	equip_info.text = ("В руке: %s" % String(s["weapon"])) if equipped else "Оружие лежит на верстаке"


# ------------------------------------------------------------------ подсказки, сообщения

## Подсказка — только контекстная: инструмент в руке, деталь в протяжке, покраска (UI v0.2: без постоянного обучения).
func _update_hint() -> void:
	var active := ctl.mode == WorkshopBuild.Mode.TEST or ctl.active_tool() != "" or not ctl.drag.is_empty()
	hint_bar.visible = active
	if active:
		hint.text = ctl.hint_text()


func show_toast(text: String, colour: Color) -> void:
	toast_label.text = text
	toast_label.add_theme_color_override("font_color", colour)
	if _toast_tween != null:
		_toast_tween.kill()
	toast_label.modulate = Color(1, 1, 1, 1)
	toast_label.scale = Vector2.ONE
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
	# иконка детали у курсора
	var dragging := ctl.mode == WorkshopBuild.Mode.BUILD and not ctl.drag.is_empty()
	drag_icon.visible = dragging and drag_icon.texture != null and ctl.drag_target().is_empty()
	if dragging:
		drag_icon.position = (ctl.drag["pos"] as Vector2) + Vector2(14, 10)
		if drag_icon.texture == null:
			drag_icon.texture = icons.request(String(ctl.drag["part"]))
	_update_drag_info(dragging)
	if ctl.mode == WorkshopBuild.Mode.TEST:
		_update_dummy_panel()


## Всплывашка у разъёма при протяжке (physics_hints): что встанет, куда, энергия и масса.
func _update_drag_info(dragging: bool) -> void:
	var t := ctl.drag_target() if dragging else {}
	drag_info.visible = dragging and ctl.physics_hints and not t.is_empty()
	if not drag_info.visible:
		return
	var d := CraftEdit.part(String(ctl.drag["part"]))
	var ok := bool(t["ok"])
	var head := "[color=#9ff29a]✔ Совместимый разъём[/color]" if ok else "[color=#ff7a60]✖ Не встаёт[/color]"
	var body := ""
	if ok:
		var tg := String(t["target"])
		var repl := "\n[color=#ffb060]заменит «%s»[/color]" % ctl.uid_title(tg, String(t["replace"])) if String(t["replace"]) != "" else ""
		if tg == "weapon":   # у верстака энергии нет — масса и куда встанет
			body = "%s → %s\n⚖ %.1f кг%s" % [d.title, _anchor_title(String(t["anchor"])), d.mass, repl]
		else:
			var c := CraftEdit.check(ctl.blueprint, d.id, String(t["uid"]), String(t["anchor"])) if not bool(t["root"]) \
				else CraftEdit.check_root(ctl.blueprint, d.id)
			var de := int(c["energy_after"]) - ctl.blueprint.energy_used()
			body = "%s → %s\n⚡ %+d   ·   ⚖ %.1f кг%s" % [d.title, _anchor_title(String(t["anchor"])), de, d.mass, repl]
	else:
		body = String(t.get("reason", ""))
	drag_info_text.text = "%s\n%s" % [head, body]
	var p := ctl.target_screen_pos(t)
	drag_info.position = (p + Vector2(34, -drag_info.size.y * 0.5)).clamp(Vector2(620, 100), Vector2(1500, 900) - drag_info.size)


func _anchor_title(an: String) -> String:
	var s := an.trim_prefix("Anchor_")
	var side := ""
	if s.ends_with("_L"):
		side = ", слева"
		s = s.trim_suffix("_L")
	elif s.ends_with("_R"):
		side = ", справа"
		s = s.trim_suffix("_R")
	var g := String(CraftEdit.GROUP_TITLES.get(s, ANCHOR_WORDS.get(s, s.to_lower())))
	return g + side


# ------------------------------------------------------------------ испытание

func _on_mode(m: int) -> void:
	var test := m == WorkshopBuild.Mode.TEST
	left.visible = not test
	right.visible = not test
	top_bar.visible = not test
	test_button.visible = not test
	keys_bar.visible = not test
	help_panel.visible = false
	help_button.set_pressed_no_signal(false)
	drag_info.visible = false
	test_bar.visible = test
	test_stats.visible = test
	dummy_panel.visible = test
	save_popup.visible = false
	load_popup.visible = false
	hint_bar.offset_left = -760.0 if test else -330.0   # в испытании панелей нет — подсказка в одну строку внизу
	hint_bar.offset_right = -hint_bar.offset_left
	hint_bar.offset_top = -80.0 if test else -206.0
	hint_bar.offset_bottom = -16.0 if test else -144.0
	toast_label.offset_top = TOAST_Y_TEST if test else TOAST_Y_BUILD
	toast_label.offset_bottom = toast_label.offset_top + 92.0
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
		l.text += "  В ГОЛОВУ!"
	elif part.begins_with("Hand"):
		l.text += "  БЛОК"
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
	dummy_hp_text.text = "%d / %d" % [roundi(hp), roundi(mx)] if bool(d.call("alive")) else "KO! встаёт…"


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


# ------------------------------------------------------------------ сохранить / загрузить

func _open_save() -> void:
	load_popup.visible = false
	save_popup.visible = true
	name_edit.text = ctl.blueprint.title.trim_suffix(" *")
	name_edit.grab_focus()
	name_edit.select_all()


func _do_save() -> void:
	save_popup.visible = false
	name_edit.release_focus()
	ctl.save_as(name_edit.text)


func _open_load() -> void:
	save_popup.visible = false
	for c in load_list.get_children():
		c.queue_free()
	var items := CraftEdit.list_saved()
	load_empty.visible = items.is_empty()
	for it in items:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 56)
		b.add_theme_font_size_override("font_size", 22)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var when := Time.get_datetime_string_from_unix_time(int(it["time"]) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60, true)
		b.text = "%s%s   ·   ⚡%d   ·   %d дет.   ·   %s" % ["(авто) " if bool(it["auto"]) else "", it["title"], it["energy"], it["parts"],
			when.substr(5, 11)]
		var path := String(it["path"])
		b.pressed.connect(func() -> void:
			load_popup.visible = false
			ctl.load_path(path))
		load_list.add_child(b)
	load_popup.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		if save_popup.visible or load_popup.visible:
			save_popup.visible = false
			load_popup.visible = false
			get_viewport().set_input_as_handled()
