## Проба вёрстки на всех языках (headless): текст другого языка не должен вылезать или налезать там, где русский помещался.
## Эталон — русский (под него рисовался интерфейс). Для каждого экрана (гараж: титул / пункты / настройки / трофеи, кампания в ТВ,
## мастерская, HUD купола с меткой СТАЗИСА, спорт-зал, «Стычка 3 на 3» и её итоги) снимаются прямоугольники всех видимых Label / Button / RichTextLabel / LineEdit на русском, потом то же на каждом
## найденном языке (locale/*.json) и на растянутом qps (+35 % длины, Loc.PSEUDO). Новая беда = её не было на русском:
##   • «вылез за экран»  — текст выходит за окно, а на русском не выходил;
##   • «налез на соседа» — два текста пересеклись (≥ 4 % меньшего), а на русском нет;
##   • «вылез из плашки» — текст был внутри ColorRect/Panel, а теперь торчит за край.
## Узлы сопоставляются по пути из индексов детей, а не по имени (auto-имена @Label@N меняются от прогона к прогону).
## Языки из locale/ дают FAIL (exit 1); qps — стресс-тест: беды печатаются, но exit не валят (+35 % заведомо жёстче реальных языков).
## Запуск: godot --headless --path . res://tests/i18n_layout_probe.tscn [-- "langs=en,de,qps"]   (по умолчанию все + qps)
##   Отчёт: tests/i18n_layout_report.json. Сам кадр беды смотреть так: tools/i18n_shots.sh <код> (снимки главных экранов в окне).
extends Node

const MENU := preload("res://scenes/menu/garage_menu.tscn")
const WORKSHOP := "res://scenes/workshop/workshop_build.tscn"
const HALL := "res://scenes/playground_null_hall.tscn"
const SPORT := "res://scenes/playground_sport.tscn"
const SQUAD := "res://scenes/playground_squad.tscn"
const VIEW := Rect2(0, 0, 1920, 1080)
const OVERLAP := 0.04
const MARGIN := 2.0
const SETTLE := 40

var report := {"ok": true, "langs": {}}
var langs: Array = []
var _base := {}      # экран → {«индексный путь» → {rect, text}}
var _plate_base := {}


func _ready() -> void:
	var loc := get_node("/root/Loc")
	var want := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("langs="):
			want = a.substr(6)
	langs = want.split(",") if want != "" else []
	if langs.is_empty():
		for c in loc.codes:
			langs.append(c)
		langs.append(loc.PSEUDO)
	langs.erase("ru")
	print("=== I18N LAYOUT PROBE: ru (эталон) → %s ===" % ", ".join(langs))
	WorkshopBuild.prefs_path = "user://_probe_layout_prefs.cfg"
	loc.set_language("ru")
	var base := await _pass()
	for code in langs:
		loc.set_language(code)
		var cur := await _pass()
		var issues := _compare(base, cur)
		var real: bool = code != loc.PSEUDO
		report["langs"][code] = {"issues": issues.size(), "stress_only": not real}
		if issues.is_empty():
			print("  ok   %s" % code)
			continue
		if real:
			report["ok"] = false
		print("  %s %s: %d проблем%s" % ["FAIL" if real else "warn", code, issues.size(), "" if real else " (стресс-тест, не валит)"])
		for i in mini(issues.size(), 14):
			print("       ", issues[i])
		report["langs"][code]["list"] = issues
	loc.set_language("ru")
	var f := FileAccess.open("res://tests/i18n_layout_report.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "\t"))
	print("=== %s ===" % ("OK" if report["ok"] else "FAIL"))
	get_tree().quit(0 if report["ok"] else 1)


## Один проход по всем экранам в текущем языке → {экран → {ключ → {rect, text, plates}}}.
func _pass() -> Dictionary:
	var shots := {}
	var menu := MENU.instantiate() as GarageMenu
	menu.dry_run = true
	add_child(menu)
	menu.campaign.save_path = "user://_probe_layout.tres"
	menu.campaign.bp_name = "_probe_layout"
	menu.campaign.load_save = false
	await _wait(SETTLE)
	shots["garage:title"] = _scan(menu)
	menu.enter_menu()
	for i in GarageMenu.ITEMS.size():
		menu.set_focus(i, true)
		await _wait(SETTLE)
		shots["garage:item%d" % i] = _scan(menu)
	menu.set_focus(4, true)
	menu._open_settings()
	await _wait(SETTLE)
	shots["garage:settings"] = _scan(menu)
	menu._close_settings()
	menu._open_trophies()
	await _wait(SETTLE)
	shots["garage:trophies"] = _scan(menu)
	menu._close_trophies()
	menu.set_focus(0, true)
	await _wait(10)
	menu.activate()
	var c := menu.campaign
	var guard := 0
	while c.screen != GarageCampaign.Screen.LADDER and guard < 600:
		guard += 1
		await get_tree().process_frame
	await _wait(SETTLE)
	shots["campaign:ladder"] = _scan(menu)
	c.finish_fight(true, {"won": true, "duration_s": 47.0})
	await _wait(SETTLE)
	shots["campaign:win"] = _scan(menu)
	c.finish_fight(false, {"won": false, "duration_s": 12.0})
	await _wait(SETTLE)
	shots["campaign:loss"] = _scan(menu)
	menu.queue_free()
	await _wait(5)
	for p in [WORKSHOP, HALL, SPORT, SQUAD]:
		Stasis.set_on(p == HALL)   # в куполе — с меткой режима СТАЗИС на HUD (StasisBadge, STASIS.md)
		var inst := (load(p) as PackedScene).instantiate()
		add_child(inst)
		await _wait(SETTLE * 2)
		shots[p.get_file()] = _scan(inst)
		if p == SQUAD:   # «Стычка 3 на 3» (SQUAD.md): ещё табличка итогов с таблицей бойцов
			var sm := inst.get_node("Match") as SquadMatch
			sm.score = [15, 9]
			sm._finish("score")
			await _wait(SETTLE * 3)
			shots["squad:end"] = _scan(inst)
		inst.queue_free()
		await _wait(5)
		if p == SQUAD:   # экран настроек стычки перед боем (SquadSetup): строки, пояснение, кнопки
			SquadSettings.reset()
			SquadSettings.ask = true
			var su := (load(p) as PackedScene).instantiate()
			add_child(su)
			await _wait(SETTLE * 2)
			shots["squad:setup"] = _scan(su)
			su.queue_free()
			SquadSettings.reset()
			await _wait(5)
	Stasis.set_on(false)
	for f in ["user://_probe_layout.tres", CraftEdit.save_path("_probe_layout"), "user://_probe_layout_prefs.cfg"]:
		var g := ProjectSettings.globalize_path(f)
		if FileAccess.file_exists(g):
			DirAccess.remove_absolute(g)
	return shots


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# ------------------------------------------------------------------ снимок экрана

func _scan(root: Node) -> Dictionary:
	var texts := {}
	var plates: Array = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		if not (n is Control) or not (n as Control).is_visible_in_tree() or _alpha(n) < 0.05:
			continue
		var ctl := n as Control
		var r := ctl.get_global_rect()
		if r.size.x < 1.0 or r.size.y < 1.0:
			continue
		if n is ColorRect or n is Panel or n is PanelContainer:
			if r.get_area() < VIEW.get_area() * 0.5:
				plates.append({"key": _key(n), "rect": r})
			continue
		var txt := ""
		if n is Label:
			txt = (n as Label).text
			r = _ink(n as Label, r)
		elif n is Button:
			txt = (n as Button).text
		elif n is RichTextLabel:
			txt = (n as RichTextLabel).get_parsed_text()
		elif n is LineEdit:
			txt = (n as LineEdit).text
		if txt.strip_edges() == "":
			continue
		texts[_key(n)] = {"rect": r, "text": txt.replace("\n", " ").left(48), "node": n}
	for k in texts:
		var tr_ := texts[k]["rect"] as Rect2
		var inside: Array = []
		for p in plates:
			var pr := p["rect"] as Rect2
			if pr.intersects(tr_) and pr.has_point(tr_.get_center()):
				inside.append(p)
		texts[k]["plates"] = inside
		texts[k].erase("node")
	return texts


## Прямоугольник самого текста: у Label с заданным размером без переноса строка может торчать за рамку узла (clip_text выключен).
func _ink(l: Label, r: Rect2) -> Rect2:
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF or l.text.contains("\n") or l.clip_text:
		return r
	var need := l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x
	if need <= r.size.x + 0.5:
		return r
	var extra := need - r.size.x
	match l.horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			return Rect2(r.position.x - extra * 0.5, r.position.y, need, r.size.y)
		HORIZONTAL_ALIGNMENT_RIGHT:
			return Rect2(r.position.x - extra, r.position.y, need, r.size.y)
	return Rect2(r.position.x, r.position.y, need, r.size.y)


func _alpha(n: Node) -> float:
	var a := 1.0
	var cur: Node = n
	while cur != null:
		if cur is CanvasItem:
			a *= (cur as CanvasItem).modulate.a * (cur as CanvasItem).self_modulate.a
		cur = cur.get_parent()
	return a


## Путь из индексов детей: стабилен между прогонами, в отличие от авто-имён @Label@75.
func _key(n: Node) -> String:
	var parts: PackedStringArray = []
	var cur: Node = n
	while cur != null and cur != self:
		parts.append(str(cur.get_index()))
		cur = cur.get_parent()
	parts.reverse()
	return "/".join(parts)


# ------------------------------------------------------------------ сравнение с эталоном

func _compare(base: Dictionary, cur: Dictionary) -> Array:
	var issues: Array = []
	for screen in cur:
		if not base.has(screen):
			continue
		var b: Dictionary = base[screen]
		var c: Dictionary = cur[screen]
		var keys: Array = c.keys().filter(func(k: String) -> bool: return b.has(k))
		for k in keys:
			var rb := b[k]["rect"] as Rect2
			var rc := c[k]["rect"] as Rect2
			if not _outside(rb) and _outside(rc):
				issues.append("%s: вылез за экран «%s» (%s)" % [screen, c[k]["text"], _fmt(rc)])
			# вылез из плашки: на эталоне текст внутри плашки целиком, теперь торчит за её край
			for p in b[k]["plates"]:
				var pr := p["rect"] as Rect2
				var pcur: Variant = null
				for q in c[k]["plates"]:
					if q["key"] == p["key"]:
						pcur = q["rect"]
				if pcur != null and pr.grow(MARGIN).encloses(rb) and not (pcur as Rect2).grow(MARGIN).encloses(rc):
					issues.append("%s: вылез из плашки «%s» (текст %s, плашка %s)" % [screen, c[k]["text"], _fmt(rc), _fmt(pcur)])
					break
		# пересечения пар
		var ks: Array = keys
		for i in ks.size():
			for j in range(i + 1, ks.size()):
				var a := c[ks[i]]["rect"] as Rect2
				var d := c[ks[j]]["rect"] as Rect2
				if _overlap(a, d) < OVERLAP:
					continue
				if _overlap(b[ks[i]]["rect"], b[ks[j]]["rect"]) >= OVERLAP:
					continue   # на русском уже налезали друг на друга — не новая беда
				# виноват текст, ставший ШИРЕ русского; высота рамки зависит от размера шрифта и от письменности, а не от длины фразы
				if a.size.x <= (b[ks[i]]["rect"] as Rect2).size.x + MARGIN and d.size.x <= (b[ks[j]]["rect"] as Rect2).size.x + MARGIN:
					continue
				issues.append("%s: «%s» (%s) налез на «%s» (%s); на русском %s и %s" % [screen, c[ks[i]]["text"], _fmt(a), c[ks[j]]["text"], _fmt(d),
					_fmt(b[ks[i]]["rect"]), _fmt(b[ks[j]]["rect"])])
	return issues


func _outside(r: Rect2) -> bool:
	return r.position.x < -MARGIN or r.position.y < -MARGIN or r.end.x > VIEW.end.x + MARGIN or r.end.y > VIEW.end.y + MARGIN


func _overlap(a: Rect2, b: Rect2) -> float:
	var i := a.intersection(b)
	var m := minf(a.get_area(), b.get_area())
	return 0.0 if m <= 0.0 or i.get_area() <= 0.0 else i.get_area() / m


func _fmt(r: Rect2) -> String:
	return "x %d–%d, y %d–%d" % [r.position.x, r.end.x, r.position.y, r.end.y]
