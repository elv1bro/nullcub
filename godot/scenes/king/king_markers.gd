## Стрелка к зоне за кадром (docs/plan-demo/KING.md): та же стрелка у края экрана, что у соперника в куполе
## (scenes/ui/offscreen_markers.gd, вид по скину HUD), но одна — к зоне «гора» (группа KingZone.GROUP, dolls_group в сцене). Подпись
## «ЗОНА · 12 м» цветом зоны (свободна — голубой, занята — цвет хозяина, спорная — красный); метры — от главной куклы кадра (P1).
extends "res://scenes/ui/offscreen_markers.gd"

var _match: KingMatch


func _process(delta: float) -> void:
	super._process(delta)
	if _match == null or not is_instance_valid(_match):
		_match = get_tree().get_first_node_in_group(Match.GROUP) as KingMatch


func _text(m: Dictionary) -> String:
	return tr("ЗОНА · %d м") % int(round(float(m["dist"])))


func _colour(_m: Dictionary) -> Color:
	return KingZone.colour_for(_match)
