## Учёт материалов забега (лут Свалки → крафт в Мастерской; docs/plan-demo/BODY_CRAFT.md). Один общий экземпляр на процесс —
## RunInventory.shared() (статическая ссылка: переживает смену сцены, автолоад и project.godot не нужны). Кто кладёт: подбор
## лута (scenes/props/scrap/loot_item.gd — касание куклой или захват E). Кто читает: счётчик на экране
## (scenes/ui/run_inventory_counter.gd) и — позже — мастерская: сколько деталей какого вида можно поставить.
##
## Материал = id из MATERIALS; у каждого подпись (всплывашки и счётчик) и деталь крафта PartDef (data/body/parts/<part>.tres),
## которую он открывает: гвозди → mod_nails, пластина → mod_iron_plate, звено цепи → chain_segment, рукоять → handle_short.
## API:
##   RunInventory.shared()                 — общий экземпляр
##   add(id, n = 1, by = null) -> int      — +n (by — кто подобрал: Doll или null), вернуть новый итог; сигнал changed
##   count(id) -> int, total() -> int, snapshot() -> Dictionary {id: n}
##   can_pay(cost: Dictionary) -> bool, pay(cost) -> bool   — списать {id: n} целиком или ничего (мастерская)
##   reset()                               — новый забег
##   RunInventory.title(id), RunInventory.part_of(id), RunInventory.material_of_part(part_id), RunInventory.is_iron(id)
## Сигнал changed(id, total, delta, by) — после каждого изменения (reset шлёт по каждому ненулевому id с total = 0).
class_name RunInventory
extends RefCounted

signal changed(id: String, total: int, delta: int, by: Node)

## id → подпись (именительный падеж, всплывашка «+1 <title>»), деталь крафта, железо ли (тянет магнит).
const MATERIALS := {
	"nails": {"title": "гвозди", "part": "mod_nails", "iron": true},
	"plate": {"title": "пластина", "part": "mod_iron_plate", "iron": true},
	"chain": {"title": "звено цепи", "part": "chain_segment", "iron": true},
	"handle": {"title": "рукоять", "part": "handle_short", "iron": false},
}
## Порядок показа в счётчике.
const ORDER := ["nails", "plate", "chain", "handle"]

static var _shared: RunInventory = null

var counts: Dictionary = {}


static func shared() -> RunInventory:
	if _shared == null:
		_shared = RunInventory.new()
	return _shared


static func title(id: String) -> String:
	return String((MATERIALS.get(id, {}) as Dictionary).get("title", id))


static func part_of(id: String) -> String:
	return String((MATERIALS.get(id, {}) as Dictionary).get("part", ""))


static func is_iron(id: String) -> bool:
	return bool((MATERIALS.get(id, {}) as Dictionary).get("iron", false))


## Какой материал открывает деталь part_id ("" — ни один).
static func material_of_part(part_id: String) -> String:
	for id in MATERIALS:
		if String(MATERIALS[id]["part"]) == part_id:
			return id
	return ""


func add(id: String, n: int = 1, by: Node = null) -> int:
	if n == 0 or not MATERIALS.has(id):
		return count(id)
	var v := maxi(count(id) + n, 0)
	counts[id] = v
	changed.emit(id, v, n, by)
	return v


func count(id: String) -> int:
	return int(counts.get(id, 0))


func total() -> int:
	var s := 0
	for id in counts:
		s += int(counts[id])
	return s


func snapshot() -> Dictionary:
	return counts.duplicate()


func can_pay(cost: Dictionary) -> bool:
	for id in cost:
		if count(String(id)) < int(cost[id]):
			return false
	return true


func pay(cost: Dictionary) -> bool:
	if not can_pay(cost):
		return false
	for id in cost:
		if int(cost[id]) != 0:
			add(String(id), -int(cost[id]))
	return true


func reset() -> void:
	var old := counts
	counts = {}
	for id in old:
		if int(old[id]) != 0:
			changed.emit(String(id), 0, -int(old[id]), null)
