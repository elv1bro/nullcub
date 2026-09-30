## Проба имён деталей для игрока (PartNames, мастерская UI/UX v0.3 §12) — headless, без физики:
##   godot --headless --path . res://tests/part_names_probe.tscn
## Печатает таблицу «id | title → имя» и PART NAMES OK / PART NAMES FAIL, код выхода 0/1.
## Проверки (по каждой детали data/body/parts/*.tres, включая скрытые с полок kit_human_*):
##   • у id есть запись в PartNames.NAMES, в NAMES нет записей без детали на диске;
##   • имена уникальны (без учёта регистра) и не совпадают с подписями материалов (MaterialDef) и шарниров (KitJoint) — в инспекторе
##     они стоят рядом;
##   • имя ≤ MAX_LEN символов, с заглавной, без двойных / краевых пробелов, без «(», «)», «·», «_», «v3», латиницы (id и хвосты
##     пайплайна не должны доехать до игрока), не равно id;
##   • of(d) и of_id(id) отдают NAMES; search_text(d) в нижнем регистре и содержит имя, исходный title, вид (CraftEdit.KIND_TITLES),
##     материал, теги рука / нога у конечностей кита S / L, «оружие», «колющая» / «дробящая», «шипы», «хлам»;
##   • запасной путь: деталь без записи — title без скобок и « · …», пустой title — id, неизвестный id — сам id, null — "".
extends Node

const PARTS_DIR := "res://data/body/parts/"
const MAX_LEN := 22
const SOFT_LEN := 18   # длиннее — печатаем, но не валим (спецификация: «в идеале ≤ 18»)

var _fails: PackedStringArray = []
var _checks := 0


func _ready() -> void:
	var defs := _load_defs()
	_check(defs.size() >= 100, "catalog_size", "деталей %d (ждём ≥ 100)" % defs.size())
	_check_names(defs)
	_check_search(defs)
	_check_fallback()
	_print_table(defs)
	var ok := _fails.is_empty()
	print("=== %d проверок, провалов %d ===" % [_checks, _fails.size()])
	for f in _fails:
		print("FAIL ", f)
	print("PART NAMES OK" if ok else "PART NAMES FAIL")
	get_tree().quit(0 if ok else 1)


func _load_defs() -> Array[PartDef]:
	var out: Array[PartDef] = []
	var dir := DirAccess.open(PARTS_DIR)
	if dir == null:
		_check(false, "parts_dir", "нет %s" % PARTS_DIR)
		return out
	for f in dir.get_files():
		var fn := f.trim_suffix(".remap")
		if not fn.ends_with(".tres"):
			continue
		var d := load(PARTS_DIR + fn) as PartDef
		_check(d != null and d.id == fn.get_basename(), "load_" + fn, "PartDef не грузится или id ≠ имени файла")
		if d != null:
			out.append(d)
	out.sort_custom(func(a: PartDef, b: PartDef) -> bool: return a.id < b.id)
	return out


func _check_names(defs: Array[PartDef]) -> void:
	var latin := RegEx.create_from_string("[A-Za-z]")
	var cyr := RegEx.create_from_string("[А-Яа-яЁё]")
	var on_disk := {}
	var seen := {}   # имя (нижний регистр) → id
	var taken := {}  # подписи рядом в инспекторе: материалы и шарниры
	for m in MaterialDef.ORDER:
		var md := MaterialDef.get_def(m)
		if md != null:
			taken[md.title.to_lower()] = "материал " + String(m)
	for jt in KitJoint.ORDER:
		taken[String(KitJoint.info(jt).get("title", jt)).to_lower()] = "шарнир " + String(jt)
	for d in defs:
		on_disk[d.id] = true
		if not _check(PartNames.NAMES.has(d.id), "name_" + d.id, "нет записи в PartNames.NAMES (title «%s»)" % d.title):
			continue
		var n := String(PartNames.NAMES[d.id])
		var low := n.to_lower()
		_check(not seen.has(low), "unique_" + d.id, "«%s» уже у %s" % [n, seen.get(low, "")])
		seen[low] = d.id
		_check(not taken.has(low), "clash_" + d.id, "«%s» совпадает с подписью: %s" % [n, taken.get(low, "")])
		_check(n.length() <= MAX_LEN, "len_" + d.id, "«%s» — %d символов > %d" % [n, n.length(), MAX_LEN])
		_check(n != "" and n.left(1) == n.left(1).to_upper(), "cap_" + d.id, "«%s» не с заглавной" % n)
		_check(n == n.strip_edges() and not n.contains("  "), "spaces_" + d.id, "«%s» — лишние пробелы" % n)
		for bad in ["(", ")", "·", "_"]:
			_check(not n.contains(bad), "bad_%s_%s" % [d.id, bad], "«%s» содержит «%s»" % [n, bad])
		_check(not low.contains("v3"), "v3_" + d.id, "«%s» содержит v3" % n)
		_check(latin.search(n) == null, "latin_" + d.id, "«%s» — латиница (похоже на id)" % n)
		_check(cyr.search(n) != null, "cyr_" + d.id, "«%s» без кириллицы" % n)
		_check(low != d.id.to_lower(), "not_id_" + d.id, "имя = id")
		_check(PartNames.of(d) == n, "of_" + d.id, "of() = «%s», ждём «%s»" % [PartNames.of(d), n])
		_check(PartNames.of_id(d.id) == n, "of_id_" + d.id, "of_id() = «%s», ждём «%s»" % [PartNames.of_id(d.id), n])
	for id in PartNames.NAMES:
		_check(on_disk.has(id), "stale_" + String(id), "в NAMES есть «%s», а детали на диске нет" % id)
	for p in CraftEdit.SHELF_HIDDEN_PREFIXES:
		var hidden := defs.filter(func(d: PartDef) -> bool: return d.id.begins_with(String(p)))
		_check(not hidden.is_empty(), "hidden_" + String(p), "скрытые с полок %s* не найдены — стенд их всё равно покажет" % p)


func _check_search(defs: Array[PartDef]) -> void:
	for d in defs:
		var s := PartNames.search_text(d)
		var id := d.id
		_check(s == s.to_lower(), "search_lower_" + id, "не в нижнем регистре: %s" % s)
		_check(s.contains(PartNames.of(d).to_lower()), "search_name_" + id, "нет имени: %s" % s)
		_check(d.title == "" or s.contains(d.title.to_lower()), "search_title_" + id, "нет исходного title: %s" % s)
		_check(s.contains(String(CraftEdit.KIND_TITLES.get(d.kind, "?"))), "search_kind_" + id, "нет вида «%s»: %s"
			% [CraftEdit.KIND_TITLES.get(d.kind, d.kind), s])
		var md := MaterialDef.get_def(d.base_mat) if d.base_mat != "" else null
		var mat := md.title.to_lower() if md != null else String(PartNames.MATERIAL_WORDS.get(d.material, "?"))
		_check(s.contains(mat), "search_mat_" + id, "нет материала «%s»: %s" % [mat, s])
		if d.material == "iron":
			_check(s.contains("железо"), "search_iron_" + id, "железная деталь без «железо»: %s" % s)
		if id.begins_with("kit_limb_"):
			var want := "рука" if id.ends_with("_s") or id.ends_with("_la") else "нога"
			_check(s.contains(want), "search_size_" + id, "конечность без «%s»: %s" % [want, s])
		if PartNames.WEAPON_KINDS.has(d.kind):
			_check(s.contains("оружие"), "search_weapon_" + id, "нет «оружие»: %s" % s)
		if d.hit_profile == "sharp":
			_check(s.contains("колющая"), "search_sharp_" + id, "нет «колющая»: %s" % s)
		if d.hit_profile == "blunt":
			_check(s.contains("дробящая"), "search_blunt_" + id, "нет «дробящая»: %s" % s)
		if id.contains("spike"):
			_check(s.contains("шипы"), "search_spikes_" + id, "нет «шипы»: %s" % s)
		if id.begins_with("junk_"):
			_check(s.contains("хлам"), "search_junk_" + id, "нет «хлам»: %s" % s)
	_check(PartNames.search_text(null) == "", "search_null", "search_text(null) должен быть пустым")


func _check_fallback() -> void:
	var d := PartDef.new()
	d.id = "probe_unnamed_part"
	d.kind = "limb"
	d.title = "Тестовая деталь (предплечье v3) · хлам"
	_check(PartNames.of(d) == "Тестовая деталь", "fallback_clean", "of() = «%s»" % PartNames.of(d))
	d.title = "Скоба (рука) длинная (клён)"
	_check(PartNames.of(d) == "Скоба длинная", "fallback_inner", "of() = «%s»" % PartNames.of(d))
	d.title = "Обрыв (без закрывающей"
	_check(PartNames.of(d) == "Обрыв", "fallback_open", "of() = «%s»" % PartNames.of(d))
	d.title = ""
	_check(PartNames.of(d) == d.id, "fallback_empty", "пустой title → id, of() = «%s»" % PartNames.of(d))
	_check(PartNames.search_text(d).contains(d.id), "fallback_search", "search_text без имени-id")
	_check(PartNames.of(null) == "", "fallback_null", "of(null) должен быть пустым")
	_check(PartNames.of_id("no_such_part_xyz") == "no_such_part_xyz", "fallback_unknown_id", "of_id(неизвестный)")
	_check(PartNames.of_id("") == "", "fallback_empty_id", "of_id(\"\") должен быть пустым")


func _print_table(defs: Array[PartDef]) -> void:
	print("=== PART NAMES (%d) ===" % defs.size())
	var long := 0
	for d in defs:
		var n := PartNames.of(d)
		if n.length() > SOFT_LEN:
			long += 1
		print("%-22s | %-32s → %s%s" % [d.id, d.title, n, "  [%d]" % n.length() if n.length() > SOFT_LEN else ""])
	print("длиннее %d символов: %d" % [SOFT_LEN, long])


func _check(ok: bool, id: String, detail: String) -> bool:
	_checks += 1
	if not ok:
		_fails.append("%s: %s" % [id, detail])
	return ok
