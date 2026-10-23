## Выбор бойца перед боем (docs/plan-demo/FIGHTER_SELECT.md): данные экрана scenes/menu/fighter_select.gd — без UI, чтобы проба
## (tests/fighter_select_probe) проверяла то же, что видит игрок.
##   roster()    — готовые бойцы: шаблоны мастерской (CraftEdit.BODY_PRESETS — кит, лига, про-лига, Аоэлюн, химера, поршневой)
##                 без пустых заготовок; только те, что собираются в текущем режиме энергии (CraftEdit.friendly_errors пуст);
##   my_builds() — «Мой боец»: автосейв мастерской и сохранённые сборки (CraftEdit.list_saved), тоже только целые;
##   roll(rng)   — кубик: случайные ответы «Быстрого конструктора» (QuickBuild) и случайный вариант.
## Выбор уходит в бой единственным путём — opts.player_blueprint у ModeRun.launch (ModePlayer.swap_p1); null — «Обычный»: кукла
## режима как есть. last — последний выбор за сессию (экран открывается на нём).
class_name FighterPick
extends RefCounted

## Пустые заготовки и заведомо не бойцы — не в ростер.
const SKIP := ["kit_empty", "open_empty"]
## Порядок групп ростера: префикс id → группа (подпись — ключ перевода).
const GROUPS := [["kit_", "Кит"], ["league_", "Лига NULL"], ["pro_", "Про-лига"], ["aoe_", "Аоэлюн"], ["set_", "Наборы"], ["", "Шаблоны"]]

static var last: Dictionary = {}       # {kind, id[, bp, line]} последнего выбора: kind = default | preset | saved | quick | dice | sketch
## Последний эскиз сессии (docs/plan-demo/SKETCH_FIGHTER.md): {bp, line, strokes, sym, seed} — карточка «Прошлый эскиз» и холст с ним.
static var sketch: Dictionary = {}
## «В мастерскую» с экрана выбора не в гараже: чертёж, который гараж положит на стенд, открыв мастерскую (Flow.reopen_workshop).
static var pending_workshop: BodyBlueprint = null


## Из любого экрана — в мастерскую гаража; bp (если есть) окажется на стенде.
static func open_workshop(tree: SceneTree, bp: BodyBlueprint) -> void:
	pending_workshop = bp
	var flow := tree.root.get_node_or_null("Flow")
	if flow == null:
		return
	flow.set("reopen_workshop", true)
	flow.call("to_menu")


## Готовые бойцы: [{id, title, group, bp}] в порядке GROUPS (внутри группы — как в BODY_PRESETS).
static func roster() -> Array:
	var by_group := {}
	for g in GROUPS:
		by_group[g[0]] = []
	for id in CraftEdit.BODY_PRESETS:
		if SKIP.has(id):
			continue
		var bp := preset(String(id))
		if bp == null or not CraftEdit.friendly_errors(bp).is_empty() or not CraftEdit.structural_errors(bp).is_empty():
			continue
		var gk := ""
		for g in GROUPS:
			if String(id).begins_with(String(g[0])) and String(g[0]) != "":
				gk = String(g[0])
				break
		(by_group[gk] as Array).append({"id": String(id), "title": bp.title, "group": _group_title(gk), "bp": bp})
	var out: Array = []
	for g in GROUPS:
		out.append_array(by_group[g[0]])
	return out


## Шаблон мастерской по id (копия; мимо campaign_templates_locked — выбор бойца не кампания).
static func preset(id: String) -> BodyBlueprint:
	var path := CraftEdit.BODY_PRESET_DIR + id + ".tres"
	if not ResourceLoader.exists(path):
		return null
	var src := load(path) as BodyBlueprint
	return CraftEdit.dup_body(src) if src != null else null


## «Мой боец»: [{id (путь), title, auto, bp}] — автосейв первым, потом сохранённые (свежие выше). Только целые чертежи.
static func my_builds() -> Array:
	var out: Array = []
	var auto: Array = []
	for e in CraftEdit.list_saved():
		var bp := CraftEdit.load_saved(String(e["path"]))
		if bp == null or bp.nodes.is_empty() or not CraftEdit.friendly_errors(bp).is_empty() or not CraftEdit.structural_errors(bp).is_empty():
			continue
		var item := {"id": String(e["path"]), "title": String(e["title"]).trim_suffix(" *"), "auto": bool(e["auto"]), "bp": bp}
		if bool(e["auto"]):
			auto.append(item)
		else:
			out.append(item)
	return auto + out


## Кубик: случайные ответы конструктора + случайный вариант. {answers, seed, bp, …} как QuickBuild.generate.
static func roll(rng: RandomNumberGenerator) -> Dictionary:
	var answers := {"style": QuickBuild.STYLES[rng.randi_range(0, QuickBuild.STYLES.size() - 1)],
		"hitter": QuickBuild.HITTERS[rng.randi_range(0, QuickBuild.HITTERS.size() - 1)],
		"special": QuickBuild.SPECIALS[rng.randi_range(0, QuickBuild.SPECIALS.size() - 1)]}
	var seed_v := rng.randi()
	var r := QuickBuild.generate(answers, seed_v)
	r["answers"] = answers
	r["seed"] = seed_v
	if r["bp"] != null:
		(r["bp"] as BodyBlueprint).title = TranslationServer.translate("Случайный боец")
	return r


## Короткая сводка чертежа для карточки: «41.2 кг · ⚡ 92/104 · 14 дет.».
static func summary(bp: BodyBlueprint) -> String:
	if bp == null:
		return TranslationServer.translate("кукла режима")
	return TranslationServer.translate("%.1f кг · энергия %d/%d · деталей %d") % [bp.total_mass(), bp.energy_used(), bp.energy_cap(), bp.nodes.size()]


static func _group_title(prefix: String) -> String:
	for g in GROUPS:
		if String(g[0]) == prefix:
			return String(g[1])
	return "Шаблоны"
