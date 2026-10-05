## Проба «в английском не осталось кириллицы» (headless): под en загружает главные сцены (гараж, кампания, тестовое меню, бой в куполе,
## Руины, Свалка, PvE, мастерская), ждёт несколько кадров и обходит дерево: Label / Button / RichTextLabel / LineEdit / Label3D / подсказки —
## текст, как его покажет движок (atr), не должен содержать русских букв. Заодно открывает экраны гаража НАСТРОЙКИ и ТРОФЕИ.
## Ловит забытые tr() в const-таблицах и строках, собранных заранее. Тексты, нарисованные draw_string, проверяются `tools/i18n.py check`.
## Запуск: godot --headless --path . res://tests/i18n_scenes_probe.tscn   Exit 0/1, отчёт tests/i18n_scenes_report.json.
## Параметры: -- "lang=en" (другой код языка), "only=garage" (одна сцена по подстроке пути).
extends Node

const SCENES := [
	"res://scenes/menu/garage_menu.tscn",
	"res://scenes/menu/test_menu.tscn",
	"res://scenes/campaign/campaign.tscn",
	"res://scenes/playground_null_hall.tscn",
	"res://scenes/playground_sport.tscn",
	"res://scenes/playground.tscn",
	"res://scenes/playground_scrap.tscn",
	"res://scenes/playground_pve.tscn",
	"res://scenes/workshop/workshop_build.tscn",
]
const FRAMES := 40
const MAX_LEFT := 25

var report := {"ok": true, "lang": "en", "scenes": {}}
var lang := "en"
var only := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		for part in a.split(","):
			if part.begins_with("lang="):
				lang = part.substr(5)
			elif part.begins_with("only="):
				only = part.substr(5)
	report["lang"] = lang
	print("=== I18N SCENES PROBE (%s) ===" % lang)
	var loc := get_node_or_null("/root/Loc")
	if loc == null:
		_fail("Loc не в автозагрузке")
		return
	loc.set_language(lang)
	for path in SCENES:
		if only != "" and not String(path).contains(only):
			continue
		await _scene(path)
	_finish()


func _scene(path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		_note(path, ["сцена не загрузилась"])
		return
	var inst := packed.instantiate()
	add_child(inst)
	for i in FRAMES:
		await get_tree().process_frame
	if path.ends_with("garage_menu.tscn"):
		await _garage_screens(inst)
	var left := _scan(inst)
	_note(path, left)
	inst.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


## Экраны гаража строятся при setup, но открываются по пунктам: открываем их, чтобы тексты точно обновились.
func _garage_screens(g: Node) -> void:
	for id in ["_open_settings", "_close_settings", "_open_trophies", "_close_trophies"]:
		if g.has_method(id):
			g.call(id)
			for i in 3:
				await get_tree().process_frame


func _scan(root: Node) -> Array:
	var left: Array = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var texts: Array = []
		if n is Label:
			texts.append((n as Label).text)
		elif n is RichTextLabel:
			texts.append((n as RichTextLabel).text)
		elif n is LineEdit:
			texts.append((n as LineEdit).placeholder_text)
		elif n is Label3D:
			texts.append((n as Label3D).text)
		if n is Button:
			texts.append((n as Button).text)
		if n is Control:
			texts.append((n as Control).tooltip_text)
		for t in texts:
			var s := n.atr(String(t))
			if _has_cyr(s) and not _native_names().has(s):   # «Русский» в строке выбора языка — родное название, так и надо
				left.append("%s [%s]: %s" % [n.get_path(), n.get_class(), s.replace("\n", " ").left(70)])
	return left


func _note(path: String, left: Array) -> void:
	report["scenes"][path] = left
	if left.is_empty():
		print("  ok   %s" % path)
		return
	report["ok"] = false
	print("  FAIL %s: %d строк с кириллицей" % [path, left.size()])
	for i in mini(left.size(), MAX_LEFT):
		print("       ", left[i])


func _native_names() -> Array:
	return get_node("/root/Loc").names.values()


func _has_cyr(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if (c >= 0x410 and c <= 0x44F) or c == 0x401 or c == 0x451:
			return true
	return false


func _fail(msg: String) -> void:
	report["ok"] = false
	print("  FAIL ", msg)
	_finish()


func _finish() -> void:
	var f := FileAccess.open("res://tests/i18n_scenes_report.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "\t"))
	print("=== %s ===" % ("OK" if report["ok"] else "FAIL"))
	get_tree().quit(0 if report["ok"] else 1)
