## Превью живого эфира телевизора гаража (scenes/menu/tv_bout.gd) во весь экран — куклы-боты на поле Void и N0 в углу.
##   godot --path godot --write-movie /абс/кадры/f.png --fixed-fps 24 res://tests/tv_bout_preview.tscn -- seconds=8
extends Node


func _ready() -> void:
	var b := TvBout.new()
	add_child(b)
	var secs := 8.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seconds="):
			secs = float(a.get_slice("=", 1))
	await get_tree().create_timer(secs).timeout
	get_tree().quit()
