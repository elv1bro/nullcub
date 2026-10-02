## Кадры загрузки: лоадер и запуск игры (boot.tscn → гараж под лоадером). Нужно окно:
##   godot/tools/godot_nofocus.sh --path godot --resolution 1920x1080 res://tests/boot_shots.tscn -- out=/абс/папка
## Снимки делает узел под root (переживает смену сцены): boot-0.3s, 1.0s, 2.0s … ; в stdout — когда лоадер ушёл.
extends Node

var out := ""
var _t0 := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out)
	var g := Node.new()
	g.set_script(load("res://tests/boot_shots_grabber.gd"))
	g.set("out", out)
	get_tree().root.add_child.call_deferred(g)
	var boot := (load("res://scenes/boot.tscn") as PackedScene).instantiate()
	add_child(boot)
