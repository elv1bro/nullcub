## Рука с оружием бойца «Стычки 3 на 3» (docs/plan-demo/SQUAD.md): обычная тяга руки (ArmAssist) — деталь blueprint.control[0], у
## команды своя кисть (Tuning.SQUAD_GUN_HAND). Человеку — как в обычном бою: ЛКМ тянет руку к курсору, кольцо-подсказка на месте.
## Боту кольца не нужны (его цель руки — шум на экране). Настройки — в _ready по кукле: Match.respawn_doll пересоздаёт детей куклы
## через script.new() и экспорты теряет.
class_name SquadArm
extends ArmAssist


func _ready() -> void:
	var d := get_parent() as Doll
	show_hints = d != null and not d.external_input
	super._ready()
