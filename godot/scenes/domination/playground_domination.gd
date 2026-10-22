## Площадка «Захват точек» (docs/plan-demo/DOMINATION.md): та же «Стычка 3 на 3» на Полигоне (SquadPlayground — бойцы, классы, камера,
## клавиши, экран настроек O), но матч — DominationMatch (три зоны A, B, C, очки за удержание), HUD — DominationHud, мозги ботов —
## DominationBrain. Ночная карта — playground_domination_night.tscn. Режим в этой сцене всегда «dom»: настройки (SquadSettings) дают
## цель, время, ботов, ящики; сменили режим на экране настроек — SquadPlayground._scene_for уводит в сцену стычки.
class_name DominationPlayground
extends SquadPlayground

const BRAIN := preload("res://scripts/domination/domination_brain.gd")


## Сцена открыта напрямую (или из гаража) при другом режиме в настройках — режим настроек становится «dom»: цель, время и экран
## настроек — захвата точек.
func _ready() -> void:
	if use_settings:
		SquadSettings.mode = "dom"
	super._ready()


func _mode_from_settings() -> String:
	return "dom"


func _brain_script() -> Script:
	return BRAIN
