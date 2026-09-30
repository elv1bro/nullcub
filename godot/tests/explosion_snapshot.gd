## Кадры взрыва бочки (scenes/props/explosion.gd): пол, кукла, ящик, две бочки (цепь), свет; кадры через 0.03 / 0.12 / 0.3 / 0.6 с
## после поджига. Нужно окно (кадры читаются с вьюпорта):
##   godot --path . --resolution 1280x720 --fixed-fps 60 res://tests/explosion_snapshot.tscn -- "out=/путь/к/папке"
extends Node3D

var out_dir := "user://"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var p := arg.split("=")
		if p.size() == 2 and p[0] == "out":
			out_dir = p[1]
	_run.call_deferred()


func _run() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.08, 0.1)
	e.ambient_light_color = Color(0.5, 0.5, 0.55)
	e.ambient_light_energy = 0.6
	e.glow_enabled = true
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 0.6
	add_child(sun)
	var fl := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(30, 1, 4)
	cs.shape = bs
	fl.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	mi.mesh = bm
	fl.add_child(mi)
	fl.position = Vector3(0, -0.5, 0)
	add_child(fl)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.8, 9.0)
	cam.fov = 55
	add_child(cam)
	cam.current = true
	var d: Doll = (load("res://scenes/doll/doll.tscn") as PackedScene).instantiate()
	d.external_input = true
	d.position = Vector3(1.6, 0.05, 0)
	add_child(d)
	d.add_to_group("dolls")
	var crate := (load("res://scenes/props/scrap/prop_wooden_crate.tscn") as PackedScene).instantiate() as RigidBody3D
	add_child(crate)
	crate.global_position = Vector3(-1.5, 0.02, 0)
	var b1 := (load("res://scenes/props/scrap/prop_metal_barrel.tscn") as PackedScene).instantiate() as ExplosiveBarrel
	add_child(b1)
	b1.global_position = Vector3(0, 0.02, 0)
	var b2 := (load("res://scenes/props/scrap/prop_metal_barrel_dented.tscn") as PackedScene).instantiate() as ExplosiveBarrel
	add_child(b2)
	b2.global_position = Vector3(-3.0, 0.02, 0)
	for i in 60:
		await get_tree().physics_frame
	b1.take_damage(11.0)   # DAMAGED → фитиль
	await _wait(1.2)
	await _shot("fuse")
	await _wait(1.0 - 0.0)
	await _shot("t0_03")
	await _wait(0.09)
	await _shot("t0_12")
	await _wait(0.18)
	await _shot("t0_30")
	await _wait(0.3)
	await _shot("t0_60")
	get_tree().quit(0)


func _wait(s: float) -> void:
	var t := 0.0
	while t < s:
		await get_tree().process_frame
		t += get_process_delta_time()


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join("explosion_%s.png" % tag))
