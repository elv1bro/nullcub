## Проход по картинке (docs/plan-demo/LOOK_PASS.md): переключатели «до / после» для каждой пробы вида. Автозагрузка «Look».
##
## Проба регистрирует свой пункт и читает его:  `Look.add(&"null_dust", tr("Пыль и мусор в объёме боя"), tr("Поле NULL"))` → текущее
## состояние; дальше `Look.on(&"null_dust")` или сигнал `changed(id, on)` (переключение на лету, без перезапуска сцены).
## Э (апостроф, physical) — панель с галочками по группам. Shift+Э — общий рубильник: выключенный, все `on()` дают false — кадр «как было»
## без снятия галочек, для сравнения A/B одной клавишей. Галочки и рубильник из панели пишутся в user://look.cfg; программная смена
## (`set_on(..., false)` в пробах) по умолчанию не пишется — пробы не портят настройки игрока.
extends Node

signal changed(id: StringName, on: bool)

const SAVE_PATH := "user://look.cfg"
const KEY_PANEL := KEY_APOSTROPHE
const TOAST_S := 1.6

var master := true
var _items := {}                      # id → {"label": String, "group": String, "on": bool}
var _order: Array[StringName] = []
var _saved := {}                      # id → bool из файла (пункт может зарегистрироваться позже загрузки)
var _panel: LookPanel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	_panel = LookPanel.new()
	_panel.look = self
	add_child(_panel)


## Зарегистрировать пункт (повторный вызов только обновляет подпись и группу). Возвращает текущее `on(id)`.
func add(id: StringName, label: String, group: String = "", default_on := true) -> bool:
	if not _items.has(id):
		_items[id] = {"label": label, "group": group, "on": bool(_saved.get(String(id), default_on))}
		_order.append(id)
		if _panel != null:
			_panel.rebuild()
	else:
		_items[id]["label"] = label
		_items[id]["group"] = group
	return on(id)


## Включён ли пункт с учётом рубильника. Незарегистрированный — как рубильник (проба может спросить раньше add).
func on(id: StringName) -> bool:
	if not master:
		return false
	var it: Dictionary = _items.get(id, {})
	return bool(it.get("on", true))


## Галочка без рубильника (для панели).
func checked(id: StringName) -> bool:
	return bool((_items.get(id, {}) as Dictionary).get("on", true))


func set_on(id: StringName, v: bool, save := false) -> void:
	if not _items.has(id):
		_items[id] = {"label": String(id), "group": "", "on": v}
		_order.append(id)
	if bool(_items[id]["on"]) == v:
		return
	_items[id]["on"] = v
	if save:
		_save()
	changed.emit(id, on(id))
	if _panel != null:
		_panel.refresh()


func toggle(id: StringName, save := true) -> void:
	set_on(id, not checked(id), save)


## Общий рубильник «до / после». Сигнал уходит по всем пунктам, чьё итоговое состояние поменялось.
func set_master(v: bool, save := false) -> void:
	if master == v:
		return
	master = v
	if save:
		_save()
	for id in _order:
		if checked(id):
			changed.emit(id, on(id))
	if _panel != null:
		_panel.refresh()


## Короткая надпись по центру сверху (как у рубильника) — для клавиш проб вида.
func toast(text: String) -> void:
	if _panel != null:
		_panel.toast(text)


func ids() -> Array[StringName]:
	return _order.duplicate()


func label_of(id: StringName) -> String:
	return String((_items.get(id, {}) as Dictionary).get("label", String(id)))


func group_of(id: StringName) -> String:
	return String((_items.get(id, {}) as Dictionary).get("group", ""))


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or k.physical_keycode != KEY_PANEL:
		return
	if k.shift_pressed:
		set_master(not master, true)
		_panel.toast(tr("ВИД: НОВЫЙ") if master else tr("ВИД: КАК БЫЛО"))
	else:
		_panel.set_open(not _panel.open)
	get_viewport().set_input_as_handled()


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	master = bool(cf.get_value("look", "master", true))
	if not cf.has_section("items"):
		return
	for k in cf.get_section_keys("items"):
		_saved[k] = bool(cf.get_value("items", k, true))


func _save() -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	cf.set_value("look", "master", master)
	for id in _order:
		cf.set_value("items", String(id), checked(id))
	cf.save(SAVE_PATH)
