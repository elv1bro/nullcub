## Диагностика мышц: торс заморожен и повёрнут на 90°, конечности висят под гравитацией.
## Печатает углы суставов через 3 с. Аргументы одной строкой: -- "k=60,c=6,f=6,tmax=80"
extends Node3D

const DollScene := preload("res://scenes/doll/doll.tscn")

func _ready() -> void:
	var user_args := OS.get_cmdline_user_args()
	print("user args: ", user_args)
	var cfg := {"k": 60.0, "c": 6.0, "f": 6.0, "tmax": 80.0}
	for arg in user_args:
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and cfg.has(p[0]):
				cfg[p[0]] = float(p[1])
	var d: Doll = DollScene.instantiate()
	d.external_input = true
	d.muscle_stiffness = cfg["k"]
	d.muscle_damping = cfg["c"]
	d.muscle_max_torque = cfg["tmax"]
	d.joint_friction = cfg["f"]
	d.rotation.z = deg_to_rad(90.0)
	add_child(d)
	var torso: RigidBody3D = d.parts["Torso"]
	torso.freeze = true
	torso.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	print("cfg: ", cfg)
	await get_tree().create_timer(3.0).timeout
	for name in ["Shoulder_L", "Elbow_L", "Hip_L", "Knee_L", "Ankle_L", "Neck"]:
		var jj: Generic6DOFJoint3D = d.joints[name]
		var a: Node3D = jj.get_node(jj.node_a)
		var b: Node3D = jj.get_node(jj.node_b)
		var rel := rad_to_deg(wrapf(b.global_rotation.z - a.global_rotation.z, -PI, PI))
		print("%s: rel angle %.1f°" % [name, rel])
	print("max speed ", snappedf(d.max_part_speed(), 0.01))
	get_tree().quit(0)
