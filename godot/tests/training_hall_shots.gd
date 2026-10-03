## Кадры тренировочного зала (scenes/arena/training_hall.tscn) в окружении гаража. Нужно окно:
##   godot/tools/godot_nofocus.sh --path godot --resolution 1920x1080 res://tests/training_hall_shots.tscn -- out=/абс/папка
##       → hall-a (вход), hall-b (манекен и экраны), hall-c (груша), hall-d (дальний конец), hall-e (общий вид сзади).
extends Node

const MENU := preload("res://scenes/menu/garage_menu.tscn")
const HALL := preload("res://scenes/arena/training_hall.tscn")
var out := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out)
	var menu := MENU.instantiate() as GarageMenu
	menu.dry_run = true
	menu.live_tv = false
	add_child(menu)
	var hall := HALL.instantiate() as TrainingHall
	menu.add_child(hall)
	hall.set_awake(true)
	menu.set_world_visible(true)
	menu.ui.visible = false
	menu.sub_panel.visible = false
	var cam := menu.cam
	cam.make_current()
	cam.fov = 45.0
	var views := {"a": [Vector3(-3.0, 1.8, 6.5), Vector3(-14.0, 2.4, 0.0)], "b": [Vector3(-15.0, 2.0, 7.5), Vector3(-19.0, 2.6, -2.0)],
		"c": [Vector3(-27.0, 2.2, 7.0), Vector3(-30.0, 2.6, -1.0)], "d": [Vector3(-36.0, 2.5, 6.0), Vector3(-44.0, 3.5, -1.0)],
		"e": [Vector3(-6.0, 6.5, 9.0), Vector3(-30.0, 3.0, -2.0)]}
	await get_tree().create_timer(0.5).timeout
	for k in views:
		cam.global_position = views[k][0]
		cam.look_at(views[k][1], Vector3.UP)
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("hall-%s.png" % k))
		print("shot ", k)
	get_tree().quit()
