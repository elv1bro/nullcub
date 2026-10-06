## Настройки «Стычки 3 на 3» перед боем (автор 06.10: «режим настроек перед запуском боя — количество фрагов + ещё что-то»).
## Живут в статике до выхода из игры: R (заново) и смена карты день / ночь их не теряют. Экран настроек — SquadSetup (поверх площадки);
## пункт меню ставит ask, и площадка показывает экран один раз; прямой запуск сцены и пробы идут сразу, с тем, что здесь записано.
class_name SquadSettings
extends RefCounted

const MODES := ["dm", "ctf"]     # перестрелка, захват флага

static var mode := "dm"
static var night := false
static var score_to_win: int = Tuning.SQUAD_SCORE_TO_WIN
static var captures_to_win: int = Tuning.SQUAD_CAPTURES_TO_WIN
static var time_min := 20
static var bot_level := 2
static var joints: bool = Tuning.SQUAD_JOINTS_DEFAULT
static var supplies := true
static var boosts := true
## Класс игрока на старте (меняется и в бою клавишами 1–3).
static var player_class: String = Tuning.SQUAD_SLOT_CLASSES[0]
## Показать экран настроек при следующем входе на площадку (ставит меню).
static var ask := false


## До скольких очков матч: фраги в перестрелке, доставленные флаги в захвате.
static func goal() -> int:
	return captures_to_win if mode == "ctf" else score_to_win


static func reset() -> void:
	mode = "dm"
	night = false
	score_to_win = Tuning.SQUAD_SCORE_TO_WIN
	captures_to_win = Tuning.SQUAD_CAPTURES_TO_WIN
	time_min = 20
	bot_level = 2
	joints = Tuning.SQUAD_JOINTS_DEFAULT
	supplies = true
	boosts = true
	player_class = Tuning.SQUAD_SLOT_CLASSES[0]
	ask = false
