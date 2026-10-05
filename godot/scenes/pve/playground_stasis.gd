## Режим «СТАЗИС» — отдельный пункт ВСЕ РЕЖИМЫ (docs/plan-demo/STASIS.md; автор 05.10: «сделай отдельный режим»): PvE-волны на
## Свалке, где время идёт, только пока игрок жмёт свои клавиши (Stasis). Сцена — наследник playground_pve.tscn: всё то же (R — заново,
## F2 — кооп, Esc — пауза, 1–9 — площадки), но режим включён, пока площадка в дереве. Уходя (гараж, другая площадка, F2 — перезагрузка
## сцены), возвращает Stasis.on, каким он был до входа: в других боях режим не залипает. X здесь тоже работает — сравнить с обычным
## ходом времени. На входе — тост с правилом режима (HitJuice).
class_name StasisPlayground
extends PvePlayground

const HINT_S := 3.5

var _was_on := false


func _enter_tree() -> void:
	_was_on = Stasis.on
	Stasis.set_on(true)


func _exit_tree() -> void:
	Stasis.set_on(_was_on)


func _ready() -> void:
	super()
	var juice := director.get_node_or_null("HitJuice") as HitJuice
	if juice != null:
		juice.show_toast(tr("СТАЗИС: время идёт, только пока ты двигаешься. Отпусти клавиши — мир замрёт"), HINT_S)
