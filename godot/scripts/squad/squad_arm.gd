## Рука бойца «Стычки 3 на 3» (docs/plan-demo/SQUAD.md): ArmAssist правой кисти (деталь — blueprint.control[0]) без колец-подсказок —
## цель руки ставит прицел (GunAim), кольцо легло бы не на курсор, а на повёрнутую точку; у ботов кольца — шум. Настройки — в _init:
## Match.respawn_doll пересоздаёт детей куклы через script.new() и экспорты теряет.
class_name SquadArm
extends ArmAssist


func _init() -> void:
	show_hints = false
