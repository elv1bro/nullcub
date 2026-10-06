## Проба экрана «ВСЕ РЕЖИМЫ» (scenes/menu/test_menu.tscn, docs/plan-demo/MODES_SCREEN.md), без окна:
##   godot --headless --path godot --fixed-fps 60 res://tests/modes_screen_probe.tscn
## Экран ставится с dry_run: запуск режима и «назад» — только сигналы (сцены не грузятся, Loading не трогается). Ввод — настоящими
## событиями через Viewport.push_input (клавиши, мышь, колесо).
##   modes_scenes   — у каждого режима есть сцена на диске, id и сцены не повторяются, группы известны, ни одна сцена прежнего
##                    списка (до 06.10, 21 строка) не потерялась; старый формат строки [подпись, сцена, пояснение] понимается
##   modes_cards    — карточек столько же, сколько режимов; у каждой название, тег, описание, клавиши; снимок или заглушка N0
##   modes_select   — ↓ / S / ↑ / W меняют выбор, панель справа показывает название и описание выбранного
##   modes_scroll   — проход ↓ до конца и ↑ до начала: выбранная карточка каждый раз целиком в видимой области списка; End / Home
##   modes_wheel    — колесо мыши над списком прокручивает его, выбор не меняется
##   modes_click    — клик по другой карточке выбирает её (без запуска), клик по выбранной — запуск
##   modes_launch   — Enter на стычке → сигнал со сценой стычки и SquadSettings.ask = true; кнопка ИГРАТЬ на футболе → сцена футбола,
##                    ask не ставится
##   modes_photo    — кроссфейд: сразу после смены снимок ещё проявляется, через ≈ 0.5 с — снимок выбранного (или заглушка)
##   modes_memo     — L открывает памятку клавиш, Esc сначала закрывает её, второй Esc — «назад»
##   modes_last     — новый экран открывается на последнем выбранном режиме
##   modes_layout   — ru и en: на каждом режиме снимок полной высоты (PHOTO_H), текст под ним не ниже низа панели, всё в кадре 1920×1080;
##                    qps (+35 %) — только печать (стресс-тест)
## В stdout «=== MODES SCREEN PROBE ===» + JSON, exit 0/1.
extends Node

const SCENE := "res://scenes/menu/test_menu.tscn"
## Сцены прежнего «голого» списка ITEMS (до экрана 06.10) — все должны остаться доступны.
const OLD_SCENES := ["res://scenes/campaign/campaign.tscn", "res://scenes/playground_null_hall.tscn", "res://scenes/playground_sport.tscn",
	"res://scenes/playground_sport_basketball.tscn", "res://scenes/playground_sport_volleyball.tscn", "res://scenes/workshop/workshop_build.tscn",
	"res://scenes/playground_pve.tscn", "res://scenes/playground_squad.tscn", "res://scenes/playground_stasis.tscn", "res://scenes/playground_bomb.tscn",
	"res://scenes/playground_race.tscn", "res://scenes/playground_race_ruins.tscn", "res://scenes/playground_race_scrap.tscn",
	"res://scenes/playground_royale.tscn", "res://scenes/playground_golf.tscn", "res://scenes/playground_puzzle.tscn", "res://scenes/playground.tscn",
	"res://scenes/playground_workshop.tscn", "res://scenes/playground_void.tscn", "res://scenes/playground_scrap.tscn",
	"res://scenes/playground_body.tscn"]
const VIEW := Rect2(0, 0, 1920, 1080)

var checks: Array = []
var M: GDScript
var menu: Control
var launched: Array = []
var backs := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== MODES SCREEN PROBE ===")
	M = load("res://scenes/menu/test_menu.gd")
	var loc := get_node("/root/Loc")
	loc.set_language("ru")
	M.set("last_id", "")
	_check_data()
	await _open()
	_check_cards()
	await _check_select()
	await _check_scroll()
	await _check_wheel()
	await _check_click()
	await _check_launch()
	await _check_photo()
	await _check_memo()
	await _check_last()
	await _check_layout(loc)
	loc.set_language("ru")
	SquadSettings.reset()
	var ok := true
	for c in checks:
		ok = ok and bool(c["ok"])
	print(JSON.stringify({"ok": ok, "checks": checks.map(func(c: Dictionary) -> Dictionary: return {"id": c["id"], "ok": c["ok"]})}))
	print("=== %s ===" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


# ------------------------------------------------------------------ шаги

func _check_data() -> void:
	var list: Array = M.call("modes")
	var bad: Array = []
	var ids := {}
	var scenes := {}
	var known := {}
	for g in M.get("GROUPS"):
		known[String(g[0])] = true
	for m in list:
		var p := String(m["scene"])
		if not ResourceLoader.exists(p):
			bad.append("нет сцены " + p)
		if ids.has(m["id"]):
			bad.append("повтор id " + String(m["id"]))
		if scenes.has(p):
			bad.append("повтор сцены " + p)
		if not known.has(String(m["group"])):
			bad.append("неизвестная группа " + String(m["group"]))
		ids[m["id"]] = true
		scenes[p] = true
	var lost: Array = OLD_SCENES.filter(func(p: String) -> bool: return not scenes.has(p))
	var legacy: Dictionary = M.call("norm_entry", ["Т", "res://scenes/x_mode.tscn", "п"])
	var legacy_ok: bool = legacy["group"] == "other" and legacy["id"] == "x_mode" and legacy["desc"] == "п"
	_check("modes_scenes", bad.is_empty() and lost.is_empty() and legacy_ok and list.size() == (M.get("MODES") as Array).size(),
		"режимов %d, беды %s, потеряно из прежнего списка %s, старый формат строки %s" % [list.size(), bad, lost, legacy_ok])


func _open() -> void:
	if menu != null and is_instance_valid(menu):
		menu.queue_free()
		await _frames(2)
	menu = (load(SCENE) as PackedScene).instantiate() as Control
	menu.set("dry_run", true)
	menu.connect("launched", func(p: String) -> void: launched.append(p))
	menu.connect("went_back", func() -> void: backs += 1)
	add_child(menu)
	await _frames(20)


func _check_cards() -> void:
	var list: Array = menu.get("list")
	var cards: Array = menu.get("cards")
	var bad: Array = []
	var shots := 0
	for i in list.size():
		var m: Dictionary = list[i]
		var c: Dictionary = cards[i]
		if String((c["title"] as Label).text).strip_edges() == "" or String(m["tag"]) == "" or String(m["desc"]).length() < 60 \
				or (m["keys"] as Array).is_empty():
			bad.append(m["id"])
		var has_shot: bool = menu.call("shot", String(m["id"])) != null
		var frame := c["frame"] as Control
		var thumb := frame.get_child(0)
		if has_shot:
			shots += 1
			if not (thumb is TextureRect) or (thumb as TextureRect).texture == null:
				bad.append(String(m["id"]) + ": нет миниатюры")
		elif thumb.name != "Stub":
			bad.append(String(m["id"]) + ": нет заглушки")
	_check("modes_cards", cards.size() == list.size() and bad.is_empty() and int(menu.get("sel")) == 0,
		"карточек %d из %d, со снимком %d, без снимка — заглушка N0 %d, беды %s, выбрана %d" % [cards.size(), list.size(), shots,
			list.size() - shots, bad, menu.get("sel")])


func _check_select() -> void:
	var seq := [[KEY_DOWN, 1], [KEY_S, 2], [KEY_UP, 1], [KEY_W, 0]]
	var bad: Array = []
	for st in seq:
		await _key(st[0])
		await _frames(30)
		var i := int(menu.get("sel"))
		var m: Dictionary = (menu.get("list") as Array)[i]
		var title := String((menu.get("detail_title") as Label).text)
		var desc := String((menu.get("detail_desc") as Label).text)
		if i != int(st[1]) or title != tr(String(m["title"])) or desc != tr(String(m["desc"])):
			bad.append("%s → выбран %d (ждали %d), «%s»" % [OS.get_keycode_string(st[0]), i, st[1], title])
	_check("modes_select", bad.is_empty(), "↓ S ↑ W: %s" % ("панель следует за выбором" if bad.is_empty() else str(bad)))


func _check_scroll() -> void:
	var n := (menu.get("list") as Array).size()
	var hidden: Array = []
	var max_scroll := 0
	for i in range(1, n):
		await _key(KEY_DOWN)
		await _frames(16)
		max_scroll = maxi(max_scroll, (menu.get("scroll") as ScrollContainer).scroll_vertical)
		if not menu.call("card_visible", i):
			hidden.append(i)
	var at_end := int(menu.get("sel")) == n - 1
	for i in range(n - 2, -1, -1):
		await _key(KEY_UP)
		await _frames(16)
		if not menu.call("card_visible", i):
			hidden.append(-i)
	var top := (menu.get("scroll") as ScrollContainer).scroll_vertical
	await _key(KEY_END)
	await _frames(20)
	var end_ok := int(menu.get("sel")) == n - 1 and bool(menu.call("card_visible", n - 1))
	await _key(KEY_HOME)
	await _frames(20)
	var home_ok := int(menu.get("sel")) == 0 and bool(menu.call("card_visible", 0))
	_check("modes_scroll", hidden.is_empty() and at_end and max_scroll > 200 and top == 0 and end_ok and home_ok,
		"вниз до %d и обратно: не видно %s, прокрутка до %d px, наверху %d, End %s, Home %s" % [n - 1, hidden, max_scroll, top, end_ok, home_ok])


func _check_wheel() -> void:
	var sc := menu.get("scroll") as ScrollContainer
	sc.scroll_vertical = 0
	await _frames(2)
	var card := ((menu.get("cards") as Array)[2] as Dictionary)["panel"] as Control
	var pos := card.get_global_rect().get_center()
	for i in 4:
		_mouse(MOUSE_BUTTON_WHEEL_DOWN, pos, true)
		_mouse(MOUSE_BUTTON_WHEEL_DOWN, pos, false)
		await _frames(2)
	await _frames(10)
	var moved := sc.scroll_vertical
	_check("modes_wheel", moved > 40 and int(menu.get("sel")) == 0, "колесо над карточкой: прокрутка %d px, выбор %d" % [moved, menu.get("sel")])
	sc.scroll_vertical = 0
	await _frames(4)


func _check_click() -> void:
	launched.clear()
	var card := ((menu.get("cards") as Array)[1] as Dictionary)["panel"] as Control
	var pos := card.get_global_rect().get_center()
	_mouse(MOUSE_BUTTON_LEFT, pos, true)
	_mouse(MOUSE_BUTTON_LEFT, pos, false)
	await _frames(20)
	var sel1 := int(menu.get("sel"))
	var none := launched.is_empty()
	_mouse(MOUSE_BUTTON_LEFT, pos, true)
	_mouse(MOUSE_BUTTON_LEFT, pos, false)
	await _frames(5)
	var want := String(((menu.get("list") as Array)[1] as Dictionary)["scene"])
	_check("modes_click", sel1 == 1 and none and launched == [want],
		"первый клик: выбрана %d, запусков %d; второй клик: %s" % [sel1, 0 if none else launched.size(), launched])


func _check_launch() -> void:
	launched.clear()
	SquadSettings.reset()
	var list: Array = menu.get("list")
	var si := _index_of("squad")
	menu.call("select", si, true)
	await _frames(5)
	await _key(KEY_ENTER)
	await _frames(5)
	var squad_ok := launched == [String(list[si]["scene"])] and SquadSettings.ask
	SquadSettings.reset()
	launched.clear()
	var fi := _index_of("football")
	menu.call("select", fi, true)
	await _frames(5)
	(menu.get("play_btn") as Button).pressed.emit()
	await _frames(5)
	var foot_ok := launched == [String(list[fi]["scene"])] and not SquadSettings.ask
	_check("modes_launch", squad_ok and foot_ok, "Enter на стычке → %s; ИГРАТЬ на футболе → %s, ask %s" % [squad_ok, launched,
		SquadSettings.ask])
	launched.clear()


func _check_photo() -> void:
	var list: Array = menu.get("list")
	var bad: Array = []
	var fading := false
	for i in [_index_of("quick"), _index_of("bomb"), _index_of("golf")]:
		menu.call("select", i)
		await _frames(2)
		var front := menu.get("photo_front") as TextureRect
		var want: Texture2D = menu.call("shot", String(list[i]["id"]))
		if want != null and front.modulate.a < 0.99:
			fading = true
		await _frames(40)
		var back := menu.get("photo_back") as TextureRect
		var stub := menu.get("photo_stub") as Control
		if back.texture != want or stub.visible != (want == null) or front.modulate.a > 0.01:
			bad.append(list[i]["id"])
	var any_shot := list.any(func(m: Dictionary) -> bool: return menu.call("shot", String(m["id"])) != null)
	_check("modes_photo", bad.is_empty() and (fading or not any_shot), "кроссфейд %s, после смены — снимок выбранного (или заглушка): беды %s" % [
		fading, bad])


func _check_memo() -> void:
	backs = 0
	var memo := menu.get("memo") as Control
	var was := memo.visible
	await _key(KEY_L)
	await _frames(3)
	var opened := memo.visible
	await _key(KEY_ESCAPE)
	await _frames(3)
	var closed := not memo.visible and backs == 0
	await _key(KEY_ESCAPE)
	await _frames(3)
	_check("modes_memo", not was and opened and closed and backs == 1, "L открыл %s, Esc закрыл (без «назад») %s, второй Esc — «назад» %d" % [
		opened, closed, backs])


func _check_last() -> void:
	var gi := _index_of("golf")
	menu.call("select", gi, true)
	await _frames(3)
	await _open()
	var now := int(menu.get("sel"))
	_check("modes_last", now == gi and bool(menu.call("card_visible", now)), "после повторного открытия выбран %d (ждали %d, «Гольф»), карточка видна %s" % [
		now, gi, menu.call("card_visible", now)])
	M.set("last_id", "")


func _check_layout(loc: Node) -> void:
	var res := {}
	var ok := true
	for code in ["ru", "en", loc.PSEUDO]:
		loc.set_language(code)
		await _open()
		var list: Array = menu.get("list")
		var bad: Array = []
		var min_h := 9999.0
		for i in list.size():
			menu.call("select", i, true)
			await _frames(4)
			var photo := menu.find_child("Photo", true, false) as Control
			var info := menu.find_child("Info", true, false) as Control
			min_h = minf(min_h, photo.size.y)
			if photo.size.y < float(M.get("PHOTO_H")) - 1.0:
				bad.append("%s: снимок %d px" % [list[i]["id"], photo.size.y])
			if info.get_global_rect().end.y > float(M.get("BOTTOM")) + 1.0:
				bad.append("%s: текст до y %d" % [list[i]["id"], info.get_global_rect().end.y])
			var out := _outside_view(menu)
			if not out.is_empty():
				bad.append("%s: за кадром %s" % [list[i]["id"], out])
		var cyr := 0
		if code != "ru":
			for l in menu.find_children("*", "Label", true, false):
				if (l as Label).is_visible_in_tree() and RegEx.create_from_string("[А-Яа-яЁё]").search((l as Label).text) != null:
					cyr += 1
					bad.append("кириллица: «%s»" % (l as Label).text.left(40))
		res[code] = {"min_photo_h": min_h, "issues": bad.size()}
		print("  %s: снимок не меньше %d px, бед %d %s" % [code, min_h, bad.size(), bad.slice(0, 6)])
		if code != loc.PSEUDO and not bad.is_empty():
			ok = false
	_check("modes_layout", ok, "ru / en: снимок полной высоты, текст в панели, всё в кадре; %s" % [res])


# ------------------------------------------------------------------ помощники

## Тексты экрана вне кадра 1920×1080 (кроме карточек, прокрученных за край списка: их режет ScrollContainer).
func _outside_view(root: Control) -> Array:
	var out: Array = []
	var sc := root.get("scroll") as ScrollContainer
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree() or sc.is_ancestor_of(c) or not (c is Label or c is Button):
			continue
		var r := c.get_global_rect()
		if r.size.x < 1.0 or (c is Label and (c as Label).text.strip_edges() == ""):
			continue
		if not VIEW.grow(2.0).encloses(r):
			out.append("%s %s" % [c.name, r])
	return out


func _index_of(id: String) -> int:
	var list: Array = menu.get("list")
	for i in list.size():
		if String(list[i]["id"]) == id:
			return i
	return -1


func _key(code: Key) -> void:
	for p in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = p
		get_viewport().push_input(e)
	await get_tree().process_frame


func _mouse(button: MouseButton, pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.position = pos
	e.global_position = pos
	e.pressed = pressed
	e.factor = 1.0
	get_viewport().push_input(e, true)   # координаты кадра 1920×1080 (окно headless может быть другим)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(id: String, ok: bool, text: String) -> void:
	checks.append({"id": id, "ok": ok, "info": text})
	print("%s %s — %s" % ["PASS" if ok else "FAIL", id, text])
