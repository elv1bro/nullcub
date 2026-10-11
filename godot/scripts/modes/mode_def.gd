## Карточка режима из реестра «100+ режимов» (docs/plan-demo/MODES_100.md, 08.10). Режим = основа (одна из площадок игры) + карта
## + набор модификаторов (Mutators) + свои числа. Карточки пишет руками ModeCatalog, запускает ModeRun (autoload), показывает экран
## «РЕЖИМЫ» (scenes/menu/modes_menu.tscn). Имя и описание — русские строки для tr() (перевод — locale/en.json).
class_name ModeDef
extends RefCounted

## Основы — что за площадка. Сцена берётся из SCENES по основе и карте.
const BASES := ["duel", "bomb", "race", "sport", "squad", "pve", "stasis", "body"]
## Карты каждой основы → сцена. Первая карта — по умолчанию.
const SCENES := {
	"duel": {
		"dome": "res://scenes/playground_null_hall.tscn",
		"ruins": "res://scenes/playground.tscn",
		"workshop": "res://scenes/playground_workshop.tscn",
		"void": "res://scenes/playground_void.tscn",
		"scrap": "res://scenes/playground_scrap.tscn",
	},
	"bomb": {"dome": "res://scenes/playground_bomb.tscn"},
	"race": {
		"proving": "res://scenes/playground_race.tscn",
		"ruins": "res://scenes/playground_race_ruins.tscn",
		"scrap": "res://scenes/playground_race_scrap.tscn",
	},
	"sport": {
		"football": "res://scenes/playground_sport.tscn",
		"basketball": "res://scenes/playground_sport_basketball.tscn",
		"volleyball": "res://scenes/playground_sport_volleyball.tscn",
	},
	"squad": {"day": "res://scenes/playground_squad.tscn", "night": "res://scenes/playground_squad_night.tscn"},
	"pve": {"scrap": "res://scenes/playground_pve.tscn"},
	"stasis": {"scrap": "res://scenes/playground_stasis.tscn"},
	"body": {"presets": "res://scenes/playground_body.tscn"},
}
## Подписи основ и карт (ключи tr()).
const BASE_NAMES := {
	"duel": "Дуэль", "bomb": "Бомба", "race": "Гонка", "sport": "Спорт-зал", "squad": "Стычка 3 на 3", "pve": "PvE: волны",
	"stasis": "Стазис", "body": "Пресеты тела",
}
const MAP_NAMES := {
	"dome": "Купол", "ruins": "Руины", "workshop": "Мастерская", "void": "Void", "scrap": "Свалка", "proving": "Полигон",
	"football": "Футбол", "basketball": "Баскетбол", "volleyball": "Волейбол", "day": "День", "night": "Ночь", "presets": "Пресеты",
}

var id := ""
var name := ""          # ключ tr()
var desc := ""          # ключ tr()
var base := "duel"
var map := ""           # "" — первая карта основы
var tags: Array = []    # ["бой", "безумие", …] — ключи tr()
## Модификаторы: [{"id": String, "args": Dictionary}] — порядок важен (последний побеждает в числах).
var mutators: Array = []
## Числа карточки, которые читает раннер (bots, bot_level, time_s, p2_human …).
var params: Dictionary = {}


static func make(p_id: String, p_name: String, p_base: String, p_mutators: Array, p_desc := "", p_tags: Array = [],
		p_map := "", p_params: Dictionary = {}) -> ModeDef:
	var d := ModeDef.new()
	d.id = p_id
	d.name = p_name
	d.desc = p_desc
	d.base = p_base
	d.map = p_map
	d.tags = p_tags.duplicate()
	d.params = p_params.duplicate()
	for m in p_mutators:
		if m is String:
			d.mutators.append({"id": m, "args": {}})
		elif m is Dictionary:
			d.mutators.append({"id": String(m.get("id", "")), "args": (m.get("args", {}) as Dictionary).duplicate()})
	return d


func scene_path() -> String:
	var maps: Dictionary = SCENES.get(base, {})
	if maps.is_empty():
		return ""
	if map != "" and maps.has(map):
		return String(maps[map])
	return String(maps.values()[0])


func map_id() -> String:
	var maps: Dictionary = SCENES.get(base, {})
	if map != "" and maps.has(map):
		return map
	return String(maps.keys()[0]) if not maps.is_empty() else ""


func mutator_ids() -> Array:
	var out: Array = []
	for m in mutators:
		out.append(String(m["id"]))
	return out


func has_mutator(mid: String) -> bool:
	return mutator_ids().has(mid)


## Подпись основы и карты для экрана: «Дуэль · Купол».
func base_label() -> String:
	var b := TranslationServer.translate(String(BASE_NAMES.get(base, base)))
	var m := map_id()
	if m == "" or SCENES.get(base, {}).size() <= 1:
		return b
	return "%s · %s" % [b, TranslationServer.translate(String(MAP_NAMES.get(m, m)))]


func to_dict() -> Dictionary:
	return {"id": id, "name": name, "desc": desc, "base": base, "map": map, "tags": tags.duplicate(), "mutators": mutators.duplicate(true),
		"params": params.duplicate()}


static func from_dict(d: Dictionary) -> ModeDef:
	return make(String(d.get("id", "")), String(d.get("name", "")), String(d.get("base", "duel")), d.get("mutators", []),
		String(d.get("desc", "")), d.get("tags", []), String(d.get("map", "")), d.get("params", {}))
