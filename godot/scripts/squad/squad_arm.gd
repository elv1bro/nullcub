## Рука с оружием бойца «Стычки 3 на 3» (docs/plan-demo/SQUAD.md): обычная тяга руки (ArmAssist) — деталь blueprint.control[0], у
## команды своя кисть (Tuning.SQUAD_GUN_HAND). Колец-подсказок нет ни у кого: у игрока на курсоре свой прицел (SquadHud — магазин,
## пауза, перезарядка, заряд), у бота цель руки — шум на экране. Настройки — в _ready: Match.respawn_doll пересоздаёт детей куклы через
## script.new() и экспорты теряет.
class_name SquadArm
extends ArmAssist


func _ready() -> void:
	show_hints = false
	super._ready()
