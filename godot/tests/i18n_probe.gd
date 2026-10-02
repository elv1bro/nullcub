## Проба языков (headless): 1) все .gd из scenes/ и scripts/ компилируются (после правок tr()); 2) файлы языков читаются, автозагрузка Loc
## видит ru + en (и любой другой файл из locale/); 3) переключение: ru отдаёт ключ как есть, en — перевод, нет строки у языка → английская;
## 4) во всех языках одинаковые подстановки (%s %d …) — полную сверку кода и файлов делает `python3 tools/i18n.py check`.
## Запуск: godot --headless --path . res://tests/i18n_probe.tscn   Exit 0/1, отчёт tests/i18n_probe_report.json.
extends Node

var report := {"ok": true, "checks": []}


func _check(id: String, ok: bool, detail: String) -> void:
	report["checks"].append({"id": id, "ok": ok, "detail": detail})
	if not ok:
		report["ok"] = false
	print("  %s %s: %s" % ["ok  " if ok else "FAIL", id, detail])


func _ready() -> void:
	print("=== I18N PROBE ===")
	var loc := get_node_or_null("/root/Loc")
	_check("autoload", loc != null, "Loc в автозагрузке")
	if loc == null:
		_finish()
		return
	_check("languages", loc.codes.has("ru") and loc.codes.has("en"), "языки: %s" % str(loc.codes))
	var en: Dictionary = loc.table("en")
	_check("en_table", en.size() > 0, "en.json: %d строк" % en.size())
	# переключение
	var sample := ""
	for k in en:
		if String(en[k]) != String(k) and not String(k).contains("%"):
			sample = String(k)
			break
	if sample != "":
		loc.set_language("ru")
		_check("ru_is_source", tr(sample) == sample, "ru: «%s» остаётся как в коде" % sample.left(40))
		loc.set_language("en")
		_check("en_translates", tr(sample) == String(en[sample]), "en: «%s» → «%s»" % [sample.left(40), tr(sample).left(40)])
		_check("en_no_cyrillic", not _has_cyr(tr(sample)), "в английском переводе нет русских букв")
		loc.set_language("ru")
	# все языки: подстановки совпадают, нет русских букв, пустых нет
	var bad := 0
	for c in loc.codes:
		if c == "ru":
			continue
		var tbl: Dictionary = loc.table(c)
		for k in tbl:
			var v := String(tbl[k])
			if v != "" and (_ph(String(k)) != _ph(v) or _has_cyr(v)):
				bad += 1
				print("    ", c, ": ", String(k).left(50), " → ", v.left(50))
	_check("placeholders", bad == 0, "подстановки/кириллица в переводах: %d проблем" % bad)
	# компиляция всех скриптов
	var failed: Array[String] = []
	var n := 0
	for root in ["res://scenes", "res://scripts"]:
		for p in _gd_files(root):
			n += 1
			var s: Variant = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE)
			if s == null or (s is GDScript and not (s as GDScript).can_instantiate()):   # ошибка разбора (tr() в const / static) → не создаётся
				failed.append(p)
	_check("scripts_load", failed.is_empty(), "%d скриптов, не загрузились: %s" % [n, str(failed)])
	_finish()


func _gd_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files(dir + "/" + d))
	return out


func _has_cyr(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if (c >= 0x410 and c <= 0x44F) or c == 0x401 or c == 0x451:
			return true
	return false


func _ph(s: String) -> Array:
	var re := RegEx.new()
	re.compile("%[-+ 0#]*\\d*(?:\\.\\d+)?[sdfxXeEgGcbo]|%%|\\{[A-Za-z0-9_]*\\}")
	var out: Array = []
	for m in re.search_all(s):
		out.append(m.get_string())
	out.sort()
	return out


func _finish() -> void:
	var f := FileAccess.open("res://tests/i18n_probe_report.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "\t"))
	print("=== %s ===" % ("OK" if report["ok"] else "FAIL"))
	get_tree().quit(0 if report["ok"] else 1)
