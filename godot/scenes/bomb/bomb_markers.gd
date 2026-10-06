## Стрелка к бомбе за кадром (docs/plan-demo/BOMB.md): та же стрелка у края экрана, что у соперника в куполе
## (scenes/ui/offscreen_markers.gd, вид по скину HUD), но только для держателя бомбы (группа BombMatch.HOLDER_GROUP — в сцене
## dolls_group), подпись «БОМБА · P3 · 12 м», цвет — цвет держателя в режиме (BombMatch.colour_of: у пятого свой).
extends "res://scenes/ui/offscreen_markers.gd"


func _text(m: Dictionary) -> String:
	return tr("БОМБА · P%d · %d м") % [int(m["player"]) + 1, int(round(float(m["dist"])))]


func _colour(m: Dictionary) -> Color:
	return BombMatch.colour_of(int(m["player"]))
