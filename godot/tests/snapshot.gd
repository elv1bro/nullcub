## Визуальная проверка: три куклы (idle, толчок вправо, голова вверх), три скриншота.
## Нужно окно: godot --path . --resolution 1280x720 res://tests/snapshot.tscn -- "k=0,c=0,f=6,tmax=0"
extends Node3D

const DollScene := preload("res://scenes/doll/doll.tscn")
var dolls: Array = []
var t := 0.0
var shots := 0
var capturing := false
var cfg := {"k": -1.0, "c": -1.0, "f": -1.0, "tmax": -1.0}
var skin := ""
var mode := ""

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			if cfg.has(p[0]):
				cfg[p[0]] = float(p[1])
			elif p[0] == "skin":
				skin = p[1]
			elif p[0] == "mode":
				mode = p[1]
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.56, 0.76, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.9, 0.85, 0.8)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.4, 9.5)
	cam.fov = 45
	add_child(cam)
	var f := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(40, 1, 10)
	cs.shape = bs
	f.add_child(cs)
	var fm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(40, 1, 10)
	fm.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.67, 0.59)
	fm.material_override = mat
	f.add_child(fm)
	f.position = Vector3(0, -0.5, 0)
	add_child(f)
	for i in range(3):
		var d: Doll = DollScene.instantiate()
		d.player_index = i
		d.external_input = true
		d.muscle_stiffness = cfg["k"]
		d.muscle_damping = cfg["c"]
		d.joint_friction = cfg["f"]
		d.muscle_max_torque = cfg["tmax"]
		d.skin_scene = skin
		d.control_mode = mode
		add_child(d)
		d.position = Vector3(-3.5 + i * 3.5, 0, 0)
		dolls.append(d)

func _physics_process(delta: float) -> void:
	t += delta
	dolls[0].input_vec = Vector2.ZERO
	dolls[1].input_vec = Vector2(1, 0) if t > 0.4 and t < 1.2 else Vector2.ZERO
	dolls[2].input_vec = Vector2(0, 1) if t > 0.4 else Vector2.ZERO

func _process(_delta: float) -> void:
	if capturing:
		return
	var marks := [0.05, 1.0, 2.5]
	if shots < marks.size() and t >= marks[shots]:
		_capture("snap_%d.png" % shots)

func _capture(name: String) -> void:
	capturing = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tests/" + name)
	print("saved ", name, " at t=", snappedf(t, 0.01))
	shots += 1
	capturing = false
	if shots >= 3:
		get_tree().quit(0)
