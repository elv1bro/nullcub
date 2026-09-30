## Прогресс кампании «История» (docs/plan-demo/17-career-trophy.md): шаг лестницы, победы и поражения, трофеи, журнал боёв.
## Сохраняется в user://campaign.tres; сборка игрока — отдельным чертежом user://blueprints/<bp_name>.tres (CraftEdit.save), тем же
## файлом, который мастерская в режиме кампании пишет автосейвом (autosave_name = bp_name) — правки в мастерской не теряются.
## Правила (решения автора 30.09): поражение — бой переигрывается, лестница стоит, штрафа нет; победа — случайный трофей
## (CampaignLeague.roll_trophy) и следующий соперник. Случай трофея детерминирован: зерно кампании + шаг + число поражений —
## перезапуск игры не перебрасывает кубик.
class_name CampaignState
extends Resource

const SAVE_PATH := "user://campaign.tres"
const BP_NAME := "_campaign"
const VERSION := 1

@export var version := VERSION
@export var tier := CampaignLeague.LOCAL
## Индекс соперника на лестнице ступени; = размер лестницы — ступень пройдена.
@export var step := 0
@export var wins := 0
@export var losses := 0
## Трофеи — id деталей (PartDef) по порядку получения.
@export var trophies: PackedStringArray = []
## Журнал боёв: {step, rival, won, draw, trophy, reason, duration_s}.
@export var fights: Array[Dictionary] = []
@export var rng_seed := 0
## Имя файла сборки игрока в user://blueprints (без .tres).
@export var bp_name := BP_NAME

## Сборка игрока в памяти (не сохраняется в этот ресурс: лежит отдельным чертежом, см. save / load_from).
var blueprint: BodyBlueprint


## Новая кампания: первый соперник, стартовая сборка, пустые трофеи.
static func new_game(seed_value: int = -1, name: String = BP_NAME) -> CampaignState:
	var s := CampaignState.new()
	s.rng_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system()) & 0x7fffffff
	s.bp_name = name
	s.blueprint = CampaignLeague.start_blueprint(s.tier)
	return s


func ladder() -> Array:
	return CampaignLeague.ladder(tier)


## Соперник текущего шага ({} — ступень пройдена).
func current_rival() -> Dictionary:
	return CampaignLeague.rival(tier, step)


func finished() -> bool:
	return step >= ladder().size()


## Детали на полке мастерской: стартовый кит + трофеи.
func shelf_parts() -> PackedStringArray:
	var out := PackedStringArray(CampaignLeague.STARTER_PARTS)
	for id in trophies:
		if not out.has(id):
			out.append(id)
	return out


## Итог боя текущего шага. won — игрок победил (ничья — не победа, бой переигрывается). Возвращает id трофея ("" — нет).
func record_result(won: bool, info: Dictionary = {}) -> String:
	var r := current_rival()
	if r.is_empty():
		return ""
	var trophy := ""
	if won:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([rng_seed, tier, step, losses])
		trophy = CampaignLeague.roll_trophy(CampaignLeague.rival_blueprint(tier, r), shelf_parts(), rng)
		if trophy != "":
			trophies.append(trophy)
		wins += 1
		step += 1
	else:
		losses += 1
	fights.append({"step": step - 1 if won else step, "rival": String(r.get("id", "")), "won": won,
		"draw": bool(info.get("draw", false)), "trophy": trophy, "reason": String(info.get("reason", "")),
		"duration_s": snappedf(float(info.get("duration_s", 0.0)), 0.1)})
	return trophy


## Бюджет энергии по регламенту текущей ступени — всегда ставится на сборку игрока.
func apply_regulation() -> void:
	if blueprint != null:
		blueprint.energy_budget = CampaignLeague.energy_budget(tier)


# ------------------------------------------------------------------ сохранение

func save(path: String = SAVE_PATH) -> bool:
	apply_regulation()
	if blueprint != null and CraftEdit.save(blueprint, bp_name) == "":
		return false
	return ResourceSaver.save(self, path) == OK


static func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


## Загрузить кампанию (null — нет файла или он не читается). Сборку — из user://blueprints/<bp_name>.tres, если она собирается,
## иначе стартовую (сломанный автосейв не должен запирать кампанию).
static func load_from(path: String = SAVE_PATH) -> CampaignState:
	if not FileAccess.file_exists(path):
		return null
	var r := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not (r is CampaignState):
		return null
	var s := r as CampaignState
	var bp := CraftEdit.load_saved(CraftEdit.save_path(s.bp_name))
	if bp == null or not CraftEdit.structural_errors(bp).is_empty():
		bp = CampaignLeague.start_blueprint(s.tier)
	s.blueprint = bp
	s.apply_regulation()
	return s


static func erase(path: String = SAVE_PATH, name: String = BP_NAME) -> void:
	for p in [path, CraftEdit.save_path(name)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
