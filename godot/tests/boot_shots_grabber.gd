extends Node

var out := ""
var _t := 0.0
var _next := [0.4, 1.2, 2.5, 4.0, 6.0, 9.0]
var _i := 0
var _gone_at := -1.0


func _process(delta: float) -> void:
	_t += delta
	if _gone_at < 0.0 and _t > 0.6 and not Loading.showing:
		_gone_at = _t
		print("MEASURE loader gone at ", snappedf(_t, 0.01), " s")
	if _i < _next.size() and _t >= float(_next[_i]):
		get_viewport().get_texture().get_image().save_png(out.path_join("boot-%02d.png" % _i))
		print("shot ", _i, " t=", snappedf(_t, 0.01), " loader=", Loading.showing, " prog=", snappedf(Loading.progress, 0.01))
		_i += 1
	if _i >= _next.size():
		get_tree().quit()
