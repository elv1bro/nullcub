## Вторая половина loading_probe: сцена-цель change_scene. Лоадер должен спрятаться сам после первых кадров.
extends Node


func _ready() -> void:
	LoadingProbe._check("change_scene_switched", true, name)
	var t0 := Time.get_ticks_msec()
	while Loading.showing and Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
	LoadingProbe._check("loader_hidden_after_switch", not Loading.showing, snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.01))
	LoadingProbe.report_and_quit(get_tree())
