## Лига кампании «История» (docs/plan-demo/17-career-trophy.md, LORE_NULL.md: карьера §13, правило трофея).
## Здесь только данные и правила, без сцен:
##   • лестница ступени лиги — соперники по порядку (чертёж пресета data/body/blueprints/<preset>.tres, уровень бота RivalBrain);
##   • регламент (apply_regulation): бюджет энергии сборки по ступени лиги — Tuning.LEAGUE_ENERGY (автор 30.09: энергия растёт
##     с лигой); оружие в руке ест ту же энергию по массе — Tuning.LEAGUE_WEAPON_ENERGY_PER_KG (автор 30.09: «и на оружие
##     ограничение»; BodyBlueprint.weapon_energy);
##   • стартовая полка мастерской — STARTER_PARTS, дальше её пополняют трофеи;
##   • правило трофея: после победы из сборки соперника выпадает СЛУЧАЙНАЯ деталь (решение автора 30.09); голова и ядро не выпадают
##     (предложение: без них соперник не кукла), детали, скрытые с полок мастерской (CraftEdit.SHELF_HIDDEN_PREFIXES), — тоже.
##     Сначала выпадают детали, которых у игрока ещё нет; если есть все — любая.
## Все бои кампании пока в куполе Old NULL Hall (автор 30.09) — сцена боя scenes/campaign/campaign_fight.tscn.
class_name CampaignLeague
extends RefCounted

const LOCAL := "local"
const TIER_TITLES := {LOCAL: "Местная лига"}
## Лестница: id — ключ соперника в журнале боёв, preset — чертёж, level — Tuning.RIVAL_LEVELS, anomaly — сценарий голосования
## (этап 15, пока только пометка), final — финал ступени (этап 18: его прерывает первое вторжение).
const LADDER := {
	LOCAL: [
		{"id": "horned", "preset": "kit_horned", "level": 1},
		{"id": "brawler", "preset": "kit_brawler", "level": 2},
		{"id": "devil", "preset": "kit_devil", "level": 3, "anomaly": "vote_mismatch"},
		{"id": "king", "preset": "kit_king", "level": 4, "final": true},
	],
}
## Сборка игрока в начале кампании.
const START_PRESET := "kit_human"
## Детали на полке мастерской в начале кампании (базовый кит, BODY_KIT.md): ядро, голова, базовые конечности, кисти, стопа, сустав.
## Для верстака — рукоять и киянка (шаблоны оружия в кампании пока не закрыты — открытый вопрос автору).
const STARTER_PARTS := ["kit_core_barrel", "kit_head_round", "kit_limb_basic_s", "kit_limb_basic_l", "kit_limb_basic_la",
	"kit_limb_basic_ll", "kit_hand_fist", "kit_hand_mitten", "kit_foot_boot", "extra_joint", "handle_short", "head_mallet"]
## Виды деталей, которые не выпадают трофеем.
const TROPHY_EXCLUDED_KINDS := ["core", "head"]


static func ladder(tier: String = LOCAL) -> Array:
	return LADDER.get(tier, [])


static func tier_title(tier: String) -> String:
	return TranslationServer.translate(String(TIER_TITLES.get(tier, tier)))


## Соперник шага step ({} — лестница пройдена).
static func rival(tier: String, step: int) -> Dictionary:
	var l := ladder(tier)
	return l[step] if step >= 0 and step < l.size() else {}


## Бюджет энергии сборки по регламенту ступени лиги.
static func energy_budget(tier: String) -> int:
	return int(Tuning.LEAGUE_ENERGY.get(tier, 100))


## Энергия за кг оружия в руке по регламенту ступени лиги.
static func weapon_energy_per_kg(tier: String) -> float:
	return float(Tuning.LEAGUE_WEAPON_ENERGY_PER_KG.get(tier, 0.0))


## Регламент ступени на чертёж: бюджет энергии и цена оружия в руке.
static func apply_regulation(bp: BodyBlueprint, tier: String) -> void:
	if bp != null:
		bp.energy_budget = energy_budget(tier)
		bp.weapon_energy_per_kg = weapon_energy_per_kg(tier)


## Чертёж соперника: копия пресета в памяти (resource_path "" — переживёт респавн Match) с бюджетом лиги.
static func rival_blueprint(tier: String, r: Dictionary) -> BodyBlueprint:
	var bp := preset(String(r.get("preset", "")))
	if bp != null:
		apply_regulation(bp, tier)
	return bp


## Имя соперника на лестнице и в итогах — название его сборки.
static func rival_title(r: Dictionary) -> String:
	var bp := preset(String(r.get("preset", "")))
	return bp.title if bp != null else String(r.get("id", "?"))


## Копия пресета в памяти (resource_path "" — переживёт респавн Match). Напрямую, а не CraftEdit.load_body_preset: тот в режиме
## кампании (CraftEdit.campaign_shelf) шаблоны не отдаёт.
static func preset(id: String) -> BodyBlueprint:
	var path := CraftEdit.BODY_PRESET_DIR + id + ".tres"
	if id == "" or not ResourceLoader.exists(path):
		return null
	return CraftEdit.dup_body(load(path) as BodyBlueprint)


## Стартовая сборка игрока с бюджетом ступени лиги.
static func start_blueprint(tier: String = LOCAL) -> BodyBlueprint:
	var bp := preset(START_PRESET)
	apply_regulation(bp, tier)
	return bp


## Детали чертежа, которые могут выпасть трофеем (уникальные id, в порядке чертежа).
static func trophy_candidates(bp: BodyBlueprint) -> PackedStringArray:
	var out: PackedStringArray = []
	if bp == null:
		return out
	for n in bp.nodes:
		var id := String(n.get("part", ""))
		if id == "" or out.has(id):
			continue
		if CraftEdit.SHELF_HIDDEN_PREFIXES.any(func(p: String) -> bool: return id.begins_with(p)):
			continue
		var d := BodyBlueprint.part_def(id)
		if d == null or TROPHY_EXCLUDED_KINDS.has(d.kind):
			continue
		out.append(id)
	return out


## Правило трофея: случайная деталь соперника, сначала из тех, которых у игрока нет (owned — полка игрока). "" — выпасть нечему.
static func roll_trophy(bp: BodyBlueprint, owned: PackedStringArray, rng: RandomNumberGenerator) -> String:
	var all := trophy_candidates(bp)
	if all.is_empty():
		return ""
	var fresh: PackedStringArray = []
	for id in all:
		if not owned.has(id):
			fresh.append(id)
	var pool := fresh if not fresh.is_empty() else all
	return pool[rng.randi_range(0, pool.size() - 1)]


## Название детали для экрана трофея.
static func part_title(id: String) -> String:
	var d := BodyBlueprint.part_def(id)
	return d.title if d != null and d.title != "" else id
