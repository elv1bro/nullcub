## Визуальная проверка glb-моделей этапа 02: кукла, шляпы, оружие, пропсы в ряд.
## godot --path . --resolution 1600x900 res://tests/models_snapshot.tscn
extends Node3D

var t := 0.0
var done := false

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.93, 0.9, 0.85)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.9, 0.85, 0.8)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.6, 8.5)
	cam.rotation_degrees = Vector3(-8, 0, 0)
	cam.fov = 50
	add_child(cam)
	var rows := [
		[["doll", Vector3(-5.5, 0, 0)], ["hat_crown", Vector3(-3.4, 2.0, 0)], ["hat_cowboy", Vector3(-2.4, 2.0, 0)], ["hat_helmet", Vector3(-1.4, 2.0, 0)], ["hat_viking", Vector3(-0.4, 2.0, 0)],
		 ["hat_chicken", Vector3(0.6, 2.0, 0)], ["hat_pot", Vector3(1.6, 2.0, 0)], ["hat_cap", Vector3(2.6, 2.0, 0)], ["hat_bucket", Vector3(3.6, 2.0, 0)]],
		[["weapon_hammer", Vector3(-3.6, 1.0, 0)], ["weapon_mace", Vector3(-2.0, 1.0, 0)], ["weapon_plank", Vector3(-0.4, 1.0, 0)], ["weapon_pan", Vector3(1.0, 1.0, 0)], ["weapon_torch", Vector3(2.2, 1.0, 0)]],
		[["prop_barrel", Vector3(-3.6, -0.5, 0)], ["prop_crate", Vector3(-1.6, -0.5, 0)], ["prop_bridge", Vector3(0.2, 0.0, 0)], ["prop_banner", Vector3(3.2, -1.5, 0)], ["prop_winch", Vector3(4.6, 0.4, 0)]],
	]
	for row in rows:
		for item in row:
			var path: String = "res://assets/models/%s.glb" % item[0]
			var ps := load(path)
			if ps == null:
				push_error("missing " + path)
				continue
			var inst: Node3D = ps.instantiate()
			inst.position = item[1]
			if item[0].begins_with("hat_"):
				inst.rotation_degrees.y = -35
			add_child(inst)
			var lbl := Label3D.new()
			lbl.text = item[0]
			lbl.font_size = 40
			lbl.pixel_size = 0.004
			lbl.position = item[1] + Vector3(0, -0.35, 0.3)
			lbl.modulate = Color(0.2, 0.15, 0.1)
			add_child(lbl)

func _process(delta: float) -> void:
	t += delta
	if t > 0.5 and not done:
		done = true
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/models_snap.png")
		print("saved models_snap.png")
		get_tree().quit(0)
