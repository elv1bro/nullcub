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
## Служебный «растянутый» язык для проверки вёрстки без носителей: все строки из en.json с удвоенными гласными (≈ +35 % длины), акцентами
## и целыми подстановками (%s, %d, [bbcode]). В меню его нет; включается set_language(PSEUDO) или аргументом пробы/снимка `-- lang=qps`.
const PSEUDO := "qps"
const BUILTIN := ["ru", "en"]     # если файлы языков не попали в экспорт (нужен include_filter="*.json") — меню всё равно живёт

var codes: Array[String] = []    # ru, en, дальше остальные по алфавиту
var names := {}                  # код → родное название («Русский», «English», «Deutsch»)
var current := SOURCE
var _loaded := {}                # код → Translation, уже отданный TranslationServer
var _forced := ""                # язык из аргумента запуска `lang=xx` (пробы и снимки): настройки игрока его не перебивают


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		for part in a.split(","):
			if part.begins_with("lang="):
				_forced = part.substr(5)
	scan()
	if _forced == PSEUDO:
		_ensure_pseudo()
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
	found.erase(SOURCE)
	found.erase(REFERENCE)
	codes.append(SOURCE)
	codes.append(REFERENCE)
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
	if _forced != "":
		code = _forced
	if code == PSEUDO:
		_ensure_pseudo()
	elif not codes.has(code):
		code = SOURCE
	var changed := code != current or TranslationServer.get_locale() != code
	current = code
	TranslationServer.set_locale(code)
	if changed:
		language_changed.emit(code)


func _ensure_pseudo() -> void:
	if _loaded.has(PSEUDO):
		return
	var t := Translation.new()
	t.locale = PSEUDO
	for k in _read(REFERENCE):
		if not String(k).begins_with("@"):
			t.add_message(k, pseudo(String(_read(REFERENCE)[k])))
	TranslationServer.add_translation(t)
	_loaded[PSEUDO] = t
	names[PSEUDO] = "Pseudo (+35%)"


## Растянуть строку: гласные удваиваются и получают акцент; %-подстановки, \n и [bbcode] остаются как есть.
static func pseudo(s: String) -> String:
	const MAP := {"a": "åå", "e": "éé", "i": "ïï", "o": "öö", "u": "üü", "y": "ÿÿ", "A": "ÅÅ", "E": "ÉÉ", "I": "ÏÏ", "O": "ÖÖ", "U": "ÜÜ"}
	var out := ""
	var i := 0
	while i < s.length():
		var c := s[i]
		if c == "[":
			var j := s.find("]", i)
			if j > i:
				out += s.substr(i, j - i + 1)
				i = j + 1
				continue
		if c == "%" and i + 1 < s.length():
			var j := i + 1
			while j < s.length() and "-+ 0#.123456789".contains(s[j]):
				j += 1
			out += s.substr(i, mini(j, s.length() - 1) - i + 1)
			i = j + 1
			continue
		out += MAP.get(c, c)
		i += 1
	return out


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
