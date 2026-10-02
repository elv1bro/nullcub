## Языки игры (docs/plan-demo/I18N.md). Автозагрузка «Loc» (project.godot), стоит перед Flow.
## Код написан по-русски: ru — исходный язык, строка в коде и есть ключ перевода (`tr("Начать бой")`). Пока выбран ru, словарь
## не нужен: движок отдаёт ключ как есть (project.godot: internationalization/locale/fallback = "ru").
## Остальные языки — по одному файлу `res://locale/<код>.json`: {"@name": "English", "Начать бой": "Start fight", …}.
## Новый язык = положить файл (tools/i18n.py new de), в настройках он появится сам. Ключи на «@» — служебные (@name — родное название).
## Нет строки в выбранном языке → берём английскую (REFERENCE) → иначе русскую из кода.
## Подпись в коде — через tr() (в статических функциях TranslationServer.translate()); Label/Button с готовым русским text
## в .tscn переводятся движком сами. Смена языка: set_language(); сцены, уже построенные с текстом, перечитывают его заново
## (GarageSettings перезагружает гараж), сигнал language_changed для тех, кто держит текст в полях.
extends Node

signal language_changed(code: String)

const DIR := "res://locale/"
const SOURCE := "ru"
const REFERENCE := "en"
const BUILTIN := ["ru", "en"]     # если файлы языков не попали в экспорт (нужен include_filter="*.json") — меню всё равно живёт

var codes: Array[String] = []    # SOURCE первым, дальше по алфавиту
var names := {}                  # код → родное название («Русский», «English», «Deutsch»)
var current := SOURCE
var _loaded := {}                # код → Translation, уже отданный TranslationServer


func _ready() -> void:
	scan()
	set_language(current)


## Перечитать папку языков (кнопку «обновить» не рисуем: нужна только при старте и в пробах).
func scan() -> void:
	for t in _loaded.values():
		TranslationServer.remove_translation(t)
	_loaded.clear()
	codes.clear()
	names.clear()
	var found: Array[String] = []
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".json"):
			found.append(f.get_basename())
	for c in BUILTIN:
		if not found.has(c):
			found.append(c)
	found.sort()
	if found.has(SOURCE):
		found.erase(SOURCE)
	codes.append(SOURCE)
	codes.append_array(found)
	var base := _read(REFERENCE)
	for c in codes:
		var tbl := _read(c)
		names[c] = String(tbl.get("@name", c))
		if c == SOURCE and tbl.size() <= 1:
			continue
		var t := Translation.new()
		t.locale = c
		if c != REFERENCE:
			for k in base:
				if not String(k).begins_with("@"):
					t.add_message(k, String(base[k]))
		for k in tbl:
			if not String(k).begins_with("@") and String(tbl[k]) != "":
				t.add_message(k, String(tbl[k]))
		TranslationServer.add_translation(t)
		_loaded[c] = t


func set_language(code: String) -> void:
	if not codes.has(code):
		code = SOURCE
	var changed := code != current or TranslationServer.get_locale() != code
	current = code
	TranslationServer.set_locale(code)
	if changed:
		language_changed.emit(code)


## Родное название языка для меню.
func language_name(code: String) -> String:
	return String(names.get(code, code))


## Все ключи-подписи файла языка (без служебных «@»), для проверок и tools/i18n.py.
func table(code: String) -> Dictionary:
	var out := {}
	var tbl := _read(code)
	for k in tbl:
		if not String(k).begins_with("@"):
			out[k] = tbl[k]
	return out


func _read(code: String) -> Dictionary:
	var path := DIR + code + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_warning("Loc: %s — не словарь JSON" % path)
	return {}
