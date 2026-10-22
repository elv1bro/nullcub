## Настройки «Стычки 3 на 3» перед боем (автор 06.10: «режим настроек перед запуском боя — количество фрагов + ещё что-то»).
## Живут в статике до выхода из игры: R (заново) и смена карты день / ночь их не теряют. Экран настроек — SquadSetup (поверх площадки);
## пункт меню ставит ask, и площадка показывает экран один раз; прямой запуск сцены и пробы идут сразу, с тем, что здесь записано.
class_name SquadSettings
extends RefCounted

const MODES := ["dm", "ctf", "dom"]     # перестрелка, захват флага, захват точек (DOMINATION.md)

static var mode := "dm"
static var night := false
static var score_to_win: int = Tuning.SQUAD_SCORE_TO_WIN
static var captures_to_win: int = Tuning.SQUAD_CAPTURES_TO_WIN
static var time_min := 20
## Захват точек: свои цель и время (очки там копятся иначе — 1 в секунду за зону, матч короче).
static var dom_score_to_win: int = Tuning.DOM_SCORE_TO_WIN
static var dom_time_min: int = int(Tuning.DOM_TIME_S / 60.0)
static var bot_level := 2
static var joints: bool = Tuning.SQUAD_JOINTS_DEFAULT
static var supplies := true
static var boosts := true
## Класс игрока на старте (меняется и в бою клавишами 1–3).
static var player_class: String = Tuning.SQUAD_SLOT_CLASSES[0]
## Показать экран настроек при следующем входе на площадку (ставит меню).
static var ask := false


## До скольких очков матч: фраги в перестрелке, доставленные флаги в захвате флага, очки удержания в захвате точек.
static func goal() -> int:
	match mode:
		"ctf":
			return captures_to_win
		"dom":
			return dom_score_to_win
	return score_to_win


## Лимит времени матча в минутах для текущего режима.
static func minutes() -> int:
	return dom_time_min if mode == "dom" else time_min


static func reset() -> void:
	mode = "dm"
	night = false
	score_to_win = Tuning.SQUAD_SCORE_TO_WIN
	captures_to_win = Tuning.SQUAD_CAPTURES_TO_WIN
	time_min = 20
	dom_score_to_win = Tuning.DOM_SCORE_TO_WIN
	dom_time_min = int(Tuning.DOM_TIME_S / 60.0)
	bot_level = 2
	joints = Tuning.SQUAD_JOINTS_DEFAULT
	supplies = true
	boosts = true
	player_class = Tuning.SQUAD_SLOT_CLASSES[0]
	ask = false
