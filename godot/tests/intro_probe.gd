## Разведка площадки для заставки-комикса: высота поверхности арены «Свалка» лучом вниз по сетке x × z
## (куда ставить куклу в кадрах tools/build_intro_comic.gd). Запуск: godot --headless --path godot res://tests/intro_probe.tscn
extends Node3D

func _ready() -> void:
	var arena: Node3D = load("res://scenes/arena/scrap.tscn").instantiate()
	add_child(arena)
	for i in 3:
		await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var zs := [-1.2, -0.6, 0.0, 0.6, 1.2]
	var line := "x     " + "  ".join(zs.map(func(z): return "z=%5.1f" % z))
	print(line)
	var x := -20.0
	while x <= 20.0:
		var row := "%5.1f " % x
		for z in zs:
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, 11.5, z), Vector3(x, -8.0, z))
			var hit := space.intersect_ray(q)
			row += "  %7.2f" % (hit.position.y if hit else -99.0) + ("%-14s" % ("(" + String(hit.collider.name).substr(0, 12) + ")") if hit else "")
		print(row)
		x += 0.5
	get_tree().quit(0)
