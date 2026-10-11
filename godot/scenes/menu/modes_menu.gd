## Экран «РЕЖИМЫ» — 100+ режимов из реестра ModeCatalog (docs/plan-demo/MODES_100.md, 08.10). Слева фильтры по тегам и поиск,
## по центру карточки (имя, основа · карта, модификаторы, описание), справа — что выбрано. Enter / клик — играть (ModeRun.launch),
## F — в избранное, R — случайный режим, Esc — назад (в «ВСЕ РЕЖИМЫ» или в гараж). Избранное и последние — ModeRun (user://modes.cfg).
## Из мастерской («Испытать в режиме…») экран открывается с кнопкой «кукла со стенда»: ModeRun.launch получает чертёж.
class_name ModesMenu
extends Control

const MENU_SCENE := "res://scenes/menu/modes_menu.tscn"
const TEST_MENU_SCENE := "res://scenes/menu/test_menu.tscn"
const TAG_ALL := "все"
const TAG_FAV := "избранное"
const TAG_RECENT := "последние"
const CARD_H := 92

## Чертёж из мастерской (ModularDoll для P1) — ставит мастерская перед открытием экрана; null — обычный запуск.
static var player_blueprint: Resource = null
## Куда вернуться по Esc: "" — «ВСЕ РЕЖИМЫ».
static var back_scene := ""

var _defs: Array = []
var _filtered: Array = []
var _tag := TAG_ALL
var _query := ""
var _selected: ModeDef = null
var _cards: Array = []
var _sel_i := 0

@onready var list: VBoxContainer = %List
@onready var tags_box: VBoxContainer = %Tags
@onready var search: LineEdit = %Search
@onready var title_l: Label = %SelTitle
@onready var base_l: Label = %SelBase
@onready var muts_l: Label = %SelMutators
@onready var desc_l: Label = %SelDesc
@onready var count_l: Label = %Count
@onready var play_b: Button = %Play
@onready var fav_b: Button = %Fav
@onready var random_b: Button = %Random
@onready var back_b: Button = %Back
@onready var stand_l: Label = %Stand


func _ready() -> void:
	_defs = ModeCatalog.all()
	%Title.text = tr("РЕЖИМЫ")
	count_l.text = ""
	search.placeholder_text = tr("поиск по имени, тегу, модификатору")
	search.text_changed.connect(func(t: String) -> void:
		_query = t.strip_edges().to_lower()
		_rebuild())
	play_b.text = tr("ИГРАТЬ  (Enter)")
	play_b.pressed.connect(_play)
	fav_b.pressed.connect(_toggle_fav)
	random_b.text = tr("СЛУЧАЙНЫЙ  (R)")
	random_b.pressed.connect(_random)
	back_b.text = tr("← НАЗАД  (Esc)")
	back_b.pressed.connect(_back)
	stand_l.visible = player_blueprint != null
	stand_l.text = tr("Кукла со стенда мастерской — за P1. После боя — обратно в мастерскую.")
	_build_tags()
	_rebuild()
	search.grab_focus()


func _build_tags() -> void:
	for c in tags_box.get_children():
		c.queue_free()
	var tags: Array = [TAG_ALL, TAG_FAV, TAG_RECENT]
	tags.append_array(ModeCatalog.tags())
	for t in tags:
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = t == _tag
		b.text = tr(String(t)).capitalize() if t in [TAG_ALL, TAG_FAV, TAG_RECENT] else tr(String(t))
		b.custom_minimum_size = Vector2(0, 40)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 20)
		b.focus_mode = Control.FOCUS_NONE
		var tag := String(t)
		b.pressed.connect(func() -> void:
			_tag = tag
			for o in tags_box.get_children():
				(o as Button).button_pressed = (o as Button).text == b.text
			_rebuild())
		tags_box.add_child(b)


func _matches(d: ModeDef) -> bool:
	match _tag:
		TAG_ALL:
			pass
		TAG_FAV:
			if not ModeRun.is_favorite(d.id):
				return false
		TAG_RECENT:
			if not ModeRun.recent().has(d.id):
				return false
		_:
			if not d.tags.has(_tag):
				return false
	if _query == "":
		return true
	var hay := (tr(d.name) + " " + d.name + " " + tr(d.desc) + " " + d.base_label() + " " + " ".join(d.tags.map(func(t): return tr(String(t))))
		+ " " + " ".join(d.mutator_ids().map(func(m): return Mutators.label(String(m))))).to_lower()
	for word in _query.split(" ", false):
		if not hay.contains(word):
			return false
	return true


func _rebuild() -> void:
	for c in list.get_children():
		c.queue_free()
	_cards.clear()
	_filtered.clear()
	var src: Array = _defs
	if _tag == TAG_RECENT:
		src = []
		for id in ModeRun.recent():
			var d := ModeCatalog.by_id(String(id))
			if d != null:
				src.append(d)
	for d in src:
		if _matches(d):
			_filtered.append(d)
	count_l.text = tr("режимов: %d из %d") % [_filtered.size(), _defs.size()]
	for i in _filtered.size():
		var d: ModeDef = _filtered[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, CARD_H)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		var star := "★ " if ModeRun.is_favorite(d.id) else ""
		b.text = "%s%s\n%s   %s" % [star, tr(d.name), d.base_label(), Mutators.labels_line(d.mutator_ids())]
		b.add_theme_font_size_override("font_size", 22)
		var idx := i
		b.pressed.connect(func() -> void:
			if _sel_i == idx and _selected == d:
				_play()
			else:
				_select(idx))
		b.mouse_entered.connect(func() -> void: _select(idx))
		list.add_child(b)
		_cards.append(b)
	_select(clampi(_sel_i, 0, maxi(_filtered.size() - 1, 0)))


func _select(i: int) -> void:
	if _filtered.is_empty():
		_selected = null
		title_l.text = tr("Ничего не найдено")
		base_l.text = ""
		muts_l.text = ""
		desc_l.text = ""
		fav_b.text = ""
		return
	_sel_i = clampi(i, 0, _filtered.size() - 1)
	_selected = _filtered[_sel_i]
	for j in _cards.size():
		(_cards[j] as Button).modulate = Color(1, 1, 1, 1) if j == _sel_i else Color(0.82, 0.84, 0.9, 1)
	title_l.text = tr(_selected.name)
	base_l.text = _selected.base_label()
	muts_l.text = Mutators.describe(_selected.mutators)
	desc_l.text = tr(_selected.desc)
	fav_b.text = tr("УБРАТЬ ИЗ ИЗБРАННОГО  (F)") if ModeRun.is_favorite(_selected.id) else tr("В ИЗБРАННОЕ  (F)")
	var card := _cards[_sel_i] as Control
	var sc := list.get_parent() as ScrollContainer
	if sc != null:
		sc.ensure_control_visible(card)


func _play() -> void:
	if _selected == null:
		return
	var opts := {}
	if player_blueprint != null:
		opts["player_blueprint"] = player_blueprint
		opts["return_to"] = "workshop"
	player_blueprint = null
	ModeRun.launch(_selected, opts)


func _toggle_fav() -> void:
	if _selected == null:
		return
	ModeRun.set_favorite(_selected.id, not ModeRun.is_favorite(_selected.id))
	var keep := _sel_i
	_rebuild()
	_select(keep)


func _random() -> void:
	var pool: Array = _filtered if not _filtered.is_empty() else _defs
	if pool.is_empty():
		return
	_selected = pool[randi() % pool.size()]
	_sel_i = _filtered.find(_selected)
	_select(maxi(_sel_i, 0))
	_play()


func _back() -> void:
	if player_blueprint != null:   # пришли из мастерской — туда же (гараж откроет её по Flow.reopen_workshop)
		player_blueprint = null
		var flow := get_tree().root.get_node_or_null("Flow")
		if flow != null:
			flow.set("reopen_workshop", true)
			flow.call("to_menu")
			return
	player_blueprint = null
	if back_scene != "":
		var s := back_scene
		back_scene = ""
		Loading.change_scene(s, "ПОДКЛЮЧЕНИЕ", s.get_file().get_basename())
	else:
		Loading.change_scene(TEST_MENU_SCENE, "ПОДКЛЮЧЕНИЕ", "test_menu")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_back()
		KEY_ENTER, KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			_play()
		KEY_DOWN:
			get_viewport().set_input_as_handled()
			_select(_sel_i + 1)
		KEY_UP:
			get_viewport().set_input_as_handled()
			_select(_sel_i - 1)
		KEY_PAGEDOWN:
			_select(_sel_i + 8)
		KEY_PAGEUP:
			_select(_sel_i - 8)
		KEY_F:
			if not search.has_focus():
				_toggle_fav()
		KEY_R:
			if not search.has_focus():
				_random()
