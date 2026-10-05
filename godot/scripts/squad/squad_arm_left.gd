## Левая рука бойца «Стычки 3 на 3» (docs/plan-demo/SQUAD.md): второй ArmAssist — кисть Hand_L, не главная (захват — у правой), мышь
## не читает. Пулемёт стоит на обоих предплечьях: правая рука почти не достаёт целей справа от куклы (по кадру), левая — слева
## (проба aim), стреляет ствол, который смотрит на цель. Настройки — в _init (Match.respawn_doll теряет экспорты детей куклы).
class_name SquadArmLeft
extends ArmAssist


func _init() -> void:
	control_part = "Hand_L"
	primary = false
	use_mouse = 0
	show_hints = false
