## Стрелка за кадром (docs/plan-demo/INFECTION.md): та же стрелка у края экрана, что у соперника в куполе
## (scenes/ui/offscreen_markers.gd, вид по скину HUD), но одна — к ближайшему к главной кукле кадра (P1, DynamicCamera.primary_doll)
## «противнику»: здоровому — ближайший заражённый, заражённому — ближайший здоровый. Подпись «ЗАРАЖЁН · P3 · 12 м» зелёная или
## «P3 · 12 м» цветом здорового.
extends "res://scenes/ui/offscreen_markers.gd"

var _match: InfectionMatch


func _process(delta: float) -> void:
	super._process(delta)
	if _match == null or not is_instance_valid(_match):
		_match = get_tree().get_first_node_in_group(Match.GROUP) as InfectionMatch
	if _match == null or markers.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	var main: Node = cam.call("primary_doll") if cam != null and cam.has_method("primary_doll") else null
	var want_zombie := not (main is Doll and _match.is_infected(main))
	var best: Dictionary = {}
	for m in markers:
		var d := _doll(int(m["player"]))
		if d == null or not d.alive or _match.is_infected(d) != want_zombie or d == main:
			continue
		if best.is_empty() or float(m["dist"]) < float(best["dist"]):
			best = m
	markers.clear()
	if not best.is_empty():
		markers.append(best)


func _doll(pi: int) -> Doll:
	for d in _match.dolls():
		if (d as Doll).player_index == pi:
			return d
	return null


func _text(m: Dictionary) -> String:
	var d := _doll(int(m["player"])) if _match != null else null
	if d != null and _match.is_infected(d):
		return tr("ЗАРАЖЁН · P%d · %d м") % [int(m["player"]) + 1, int(round(float(m["dist"])))]
	return tr("P%d · %d м") % [int(m["player"]) + 1, int(round(float(m["dist"])))]


func _colour(m: Dictionary) -> Color:
	var d := _doll(int(m["player"])) if _match != null else null
	if d != null and _match.is_infected(d):
		return Tuning.INFECTION_COLOR
	return InfectionMatch.colour_of(int(m["player"]))
