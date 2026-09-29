## UI мастерской (стиль HUD: деревянные таблички hud_theme.tres, кисть-леттеринг, лист R20). Дерево — workshop_ui.tscn, здесь
## поведение: bind(WorkshopBuild) → шаблоны, полка (вкладки по видам, карточки part_card.gd с иконками PartIcons), правая панель
## (ENERGY, масса, тела, разгон, рука мышью, оружие, ошибки validate() словами, сохранить / загрузить / отменить; на вкладке ОРУЖИЕ —
## верстак: характеристики словами, «В руку»), подсказка внизу, всплывающие сообщения сверху, иконка детали у курсора при протяжке.
## В испытании — плашка ИСПЫТАНИЕ, счёт урона, табличка HP над манекеном и цифры урона в точке удара.
## Все размеры — в базовом вьюпорте 1920×1080 (project.godot: stretch canvas_items).
extends CanvasLayer

const PartCard := preload("res://scenes/workshop/ui/part_card.gd")
## Короткие подписи шаблонов на кнопках (полные — в подсказке).
const PRESET_SHORT := {
	"human": "Человек", "spider": "Паук", "long_arm": "Длиннорук", "big_arm": "Силач", "legless": "Безногий", "junk": "Хлам",
	"flail": "Кистень", "mallet": "Киянка", "hammer": "Молот", "spiked_hammer": "С гвоздями", "heavy_hammer": "Тяжёлый",
	"long_hammer": "Длинный", "sword": "Меч", "axe": "Топор", "concept_hammer": "Концепт",
}
const TOAST_Y_BUILD := 18.0
const TOAST_Y_TEST := 112.0
const TOAST_HOLD_S := 1.9
const TOAST_FADE_S := 0.35
const FLOAT_S := 1.1
const FLOAT_RISE := 90.0

var ctl: WorkshopBuild
var icons: PartIcons
var shelf_tab := {"body": "limb", "weapon": "weapon_head"}
var _cards: Dictionary = {}          # part id -> карточка
var _hint_t := 0.0
var _toast_tween: Tween
var _dmg_total := 0.0
var _dmg_hits := 0
var _dmg_best := 0.0
var _preset_buttons: Array = []

@onready var root: Control = $Root
@onready var overlay: Control = $Root/Overlay
@onready var floaters: Control = $Root/Floaters
@onready var left: Control = $Root/Left
@onready var right: Control = $Root/Right
@onready var body_tab: Button = $Root/Left/VBox/ViewTabs/BodyTab
@onready var weapon_tab: Button = $Root/Left/VBox/ViewTabs/WeaponTab
@onready var presets_box: GridContainer = $Root/Left/VBox/Presets
@onready var shelf_title: Label = $Root/Left/VBox/ShelfTitle
@onready var shelf_tabs: HFlowContainer = $Root/Left/VBox/ShelfTabs
@onready var shelf: GridContainer = $Root/Left/VBox/ShelfScroll/Shelf
@onready var shelf_scroll: ScrollContainer = $Root/Left/VBox/ShelfScroll
@onready var body_box: Control = $Root/Right/VBox/BodyBox
@onready var build_title: Label = $Root/Right/VBox/BodyBox/BuildTitle
@onready var energy_value: Label = $Root/Right/VBox/BodyBox/EnergyHead/EnergyValue
@onready var energy_bar: Control = $Root/Right/VBox/BodyBox/Energy
@onready var mass_v: Label = $Root/Right/VBox/BodyBox/Stats/MassV
@onready var bodies_v: Label = $Root/Right/VBox/BodyBox/Stats/BodiesV
@onready var accel_v: Label = $Root/Right/VBox/BodyBox/Stats/AccelV
@onready var control_label: Label = $Root/Right/VBox/BodyBox/ControlBox/V/ControlLabel
@onready var control_button: Button = $Root/Right/VBox/BodyBox/ControlBox/V/ControlButton
@onready var weapon_line: Label = $Root/Right/VBox/BodyBox/ControlBox/V/WeaponLine
@onready var problems: Label = $Root/Right/VBox/BodyBox/Problems
@onready var save_button: Button = $Root/Right/VBox/BodyBox/Files/SaveButton
@onready var load_button: Button = $Root/Right/VBox/BodyBox/Files/LoadButton
@onready var undo_button: Button = $Root/Right/VBox/BodyBox/UndoButton
@onready var weapon_box: Control = $Root/Right/VBox/WeaponBox
@onready var weapon_name: Label = $Root/Right/VBox/WeaponBox/WeaponName
@onready var wstats: VBoxContainer = $Root/Right/VBox/WeaponBox/WStats
@onready var wproblems: Label = $Root/Right/VBox/WeaponBox/WProblems
@onready var equip_button: Button = $Root/Right/VBox/WeaponBox/EquipButton
@onready var equip_info: Label = $Root/Right/VBox/WeaponBox/EquipInfo
@onready var clear_button: Button = $Root/Right/VBox/WeaponBox/ClearButton
@onready var test_button: Button = $Root/Right/VBox/TestButton
@onready var hint_bar: Control = $Root/HintBar
@onready var hint: Label = $Root/HintBar/Hint
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
	body_tab.pressed.connect(func() -> void: _set_view(WorkshopBuild.View.BODY))
	weapon_tab.pressed.connect(func() -> void: _set_view(WorkshopBuild.View.WEAPON))
	control_button.pressed.connect(func() -> void: ctl.toggle_control_pick())
	save_button.pressed.connect(_open_save)
	load_button.pressed.connect(_open_load)
	undo_button.pressed.connect(func() -> void: ctl.undo())
	equip_button.pressed.connect(func() -> void: ctl.weapon_to_hand())
	clear_button.pressed.connect(func() -> void: ctl.clear_weapon())
	test_button.pressed.connect(func() -> void: ctl.start_test())
	back_button.pressed.connect(func() -> void: ctl.stop_test())
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
	_build_left()
	_refresh()


## Точка над панелью / всплывающим окном (клик туда не ставит деталь в «липком» режиме протяжки).
func is_over_panel(p: Vector2) -> bool:
	for c in [left, right, save_popup, load_popup, test_bar]:
		if (c as Control).visible and (c as Control).get_global_rect().has_point(p):
			return true
	return false


# ------------------------------------------------------------------ левая панель

func _set_view(v: int) -> void:
	ctl.set_view(v)
	_build_left()
	_refresh()


func _view_key() -> String:
	return "weapon" if ctl.view == WorkshopBuild.View.WEAPON else "body"


func _build_left() -> void:
	if ctl == null:
		return
	var weapon := ctl.view == WorkshopBuild.View.WEAPON
	body_tab.set_pressed_no_signal(not weapon)
	weapon_tab.set_pressed_no_signal(weapon)
	shelf_title.text = "ПОЛКА — ТЯНИ ДЕТАЛЬ НА ВЕРСТАК" if weapon else "ПОЛКА — ТЯНИ ДЕТАЛЬ НА КУКЛУ"
	# шаблоны
	for c in presets_box.get_children():
		c.queue_free()
	_preset_buttons.clear()
	var ids: Array = CraftEdit.WEAPON_PRESETS if weapon else CraftEdit.BODY_PRESETS
	for id in ids:
		var title := _preset_title(String(id), weapon)
		var b := Button.new()
		b.text = String(PRESET_SHORT.get(String(id), title))
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 18)
		b.clip_text = true
		b.tooltip_text = title
		var pid := String(id)
		if weapon:
			b.pressed.connect(func() -> void: ctl.set_weapon_preset(pid))
		else:
			b.pressed.connect(func() -> void: ctl.set_preset(pid))
		presets_box.add_child(b)
		_preset_buttons.append(b)
	# вкладки полки
	for c in shelf_tabs.get_children():
		c.queue_free()
	var shelves: Array = CraftEdit.WEAPON_SHELVES if weapon else CraftEdit.BODY_SHELVES
	for s in shelves:
		var b2 := Button.new()
		b2.text = String(s["title"])
		b2.toggle_mode = true
		b2.focus_mode = Control.FOCUS_NONE
		b2.custom_minimum_size = Vector2(0, 38)
		b2.add_theme_font_size_override("font_size", 17)
		b2.add_theme_stylebox_override("pressed", _gold_style())
		b2.set_pressed_no_signal(String(s["id"]) == String(shelf_tab[_view_key()]))
		var sid := String(s["id"])
		b2.pressed.connect(func() -> void:
			shelf_tab[_view_key()] = sid
			_build_left())
		shelf_tabs.add_child(b2)
	_build_shelf()


func _gold_style() -> StyleBox:
	return control_button.get_theme_stylebox("pressed")


func _preset_title(id: String, weapon: bool) -> String:
	var path := (CraftEdit.WEAPON_PRESET_DIR if weapon else CraftEdit.BODY_PRESET_DIR) + id + ".tres"
	if not ResourceLoader.exists(path):
		return id
	var r := load(path)
	return String(r.get("title")) if r != null else id


func _build_shelf() -> void:
	for c in shelf.get_children():
		c.queue_free()
	_cards.clear()
	var shelves: Array = CraftEdit.WEAPON_SHELVES if ctl.view == WorkshopBuild.View.WEAPON else CraftEdit.BODY_SHELVES
	var kinds: Array = []
	for s in shelves:
		if String(s["id"]) == String(shelf_tab[_view_key()]):
			kinds = s["kinds"]
	for d in CraftEdit.parts_of_kinds(kinds):
		var card := PartCard.new()
		card.setup(d)
		card.grabbed.connect(_on_card_grabbed)
		shelf.add_child(card)
		_cards[d.id] = card
		var tex := icons.request(d.id)
		if tex != null:
			card.set_icon(tex)
	shelf_scroll.scroll_vertical = 0
	_update_card_fits()


func _on_icon(part_id: String, tex: Texture2D) -> void:
	if _cards.has(part_id):
		(_cards[part_id]).set_icon(tex)
	if drag_icon.visible and ctl != null and not ctl.drag.is_empty() and String(ctl.drag["part"]) == part_id:
		drag_icon.texture = tex


func _on_card_grabbed(part_id: String, pos: Vector2) -> void:
	if ctl.mode != WorkshopBuild.Mode.BUILD:
		return
	ctl.begin_drag(part_id, pos)
	drag_icon.texture = icons.request(part_id)


func _update_card_fits() -> void:
	if ctl == null:
		return
	var free_e := ctl.energy_free()
	for id in _cards:
		var d := CraftEdit.part(String(id))
		(_cards[id]).set_fits(d == null or d.energy <= free_e or ctl.view == WorkshopBuild.View.WEAPON)


# ------------------------------------------------------------------ правая панель

func _refresh() -> void:
	if ctl == null:
		return
	var weapon := ctl.view == WorkshopBuild.View.WEAPON
	body_box.visible = not weapon
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
	var wm := float(s["weapon_mass"])
	mass_v.text = "%.1f кг" % float(s["mass"]) if wm <= 0.0 else "%.1f + %.1f кг" % [float(s["mass"]), wm]
	bodies_v.text = "%d  (%d)" % [int(s["bodies"]), int(s["parts"])]
	var acc := float(s["accel"])
	accel_v.text = "×%.2f  %s" % [acc, "быстрый" if acc > 1.15 else ("как кукла" if acc > 0.87 else ("тяжеловат" if acc > 0.65 else "танк"))]
	control_label.text = "Рука мышью: %s" % (String(s["control"]) if String(s["control"]) != "" else "— не выбрана")
	control_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4) if String(s["control"]) != "" else Color(0.9, 0.6, 0.45))
	control_button.set_pressed_no_signal(ctl.control_pick)
	control_button.text = "КЛИКНИ ПО ДЕТАЛИ…" if ctl.control_pick else "РУКА МЫШЬЮ   [Q]"
	weapon_line.text = "Оружие: %s" % (String(s["weapon"]) if String(s["weapon"]) != "" else "нет  (вкладка ОРУЖИЕ → «В руку»)")
	var lines: PackedStringArray = []
	for e in (s["errors"] as PackedStringArray):
		lines.append("✖ " + e)
	for w in (s["warnings"] as PackedStringArray):
		lines.append("• " + w)
	problems.text = "\n".join(lines)
	problems.add_theme_color_override("font_color", Color(1, 0.45, 0.35) if not (s["errors"] as PackedStringArray).is_empty() else Color(1.0, 0.78, 0.4))
	undo_button.disabled = ctl.history.is_empty()
	test_button.disabled = not (s["errors"] as PackedStringArray).is_empty()
	test_button.tooltip_text = "" if not test_button.disabled else "Сначала исправь: %s" % (s["errors"] as PackedStringArray)[0]
	_refresh_weapon()
	_update_card_fits()
	_update_hint()


func _refresh_weapon() -> void:
	var w := ctl.weapon_stats()
	weapon_name.text = String(w["title"]) if not bool(w["empty"]) else "Пусто — положи рукоять"
	for c in wstats.get_children():
		c.queue_free()
	for r in (w["rows"] as Array):
		wstats.add_child(_stat_row(r))
	var errs: PackedStringArray = w["errors"]
	wproblems.text = "✖ " + errs[0] if not errs.is_empty() else ""
	var equipped := bool(w["equipped"])
	equip_button.text = "СНЯТЬ С РУКИ" if equipped else "В РУКУ"
	equip_button.disabled = bool(w["empty"]) and not equipped
	var s := ctl.body_stats()
	equip_info.text = ("В руке: %s" % String(s["weapon"])) if equipped else "Оружие лежит на верстаке"


func _stat_row(r: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var top := HBoxContainer.new()
	box.add_child(top)
	var l := Label.new()
	l.text = String(r["label"])
	l.theme_type_variation = &"StatLabel"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(l)
	var v := Label.new()
	v.text = String(r["value"])
	v.theme_type_variation = &"StatValue"
	top.add_child(v)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	bar.max_value = 1.0
	bar.value = clampf(float(r["frac"]), 0.02, 1.0)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.045, 0.04, 0.9)
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(0.95, 0.72, 0.35)
	fg.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	box.add_child(bar)
	var word := Label.new()
	word.text = String(r["word"])
	word.add_theme_font_size_override("font_size", 18)
	word.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
	box.add_child(word)
	return box


# ------------------------------------------------------------------ подсказки, сообщения

func _update_hint() -> void:
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
	if ctl.mode == WorkshopBuild.Mode.TEST:
		_update_dummy_panel()


# ------------------------------------------------------------------ испытание

func _on_mode(m: int) -> void:
	var test := m == WorkshopBuild.Mode.TEST
	left.visible = not test
	right.visible = not test
	test_bar.visible = test
	test_stats.visible = test
	dummy_panel.visible = test
	save_popup.visible = false
	load_popup.visible = false
	hint_bar.offset_left = -760.0 if test else -490.0   # в испытании панелей нет — подсказка в одну строку
	hint_bar.offset_right = -hint_bar.offset_left
	toast_label.offset_top = TOAST_Y_TEST if test else TOAST_Y_BUILD
	toast_label.offset_bottom = toast_label.offset_top + 92.0
	if test:
		_dmg_total = 0.0
		_dmg_hits = 0
		_dmg_best = 0.0
		_update_test_stats()
		dummy_hp.set_hp(Tuning.MAX_HP, false)
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
	test_stats_text.text = "Урон по манекену: %d\nУдаров: %d   ·   сильнейший: %d" % [roundi(_dmg_total), _dmg_hits, roundi(_dmg_best)]


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
	if not is_equal_approx(hp, dummy_hp.hp):
		dummy_hp.set_hp(hp, true)
	dummy_hp_text.text = "%d / %d" % [roundi(hp), roundi(Tuning.MAX_HP)] if bool(d.call("alive")) else "KO! встаёт…"


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
