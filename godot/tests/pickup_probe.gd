## Headless-проба подбора оружия (план 07 / v3): кукла doll.tscn + WeaponPickup, молот хватом в точке хвата правой кисти;
## печатает по тикам расстояние кисть–хват, ближайшее оружие и состояние захвата. Запуск:
##   godot --headless --path . res://tests/pickup_probe.tscn -- "ticks=30"
extends Node3D

var doll: Doll
var pickup: WeaponPickup
var hammer: Weapon
var ticks := 0
var max_ticks := 30


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "ticks":
				max_ticks = int(p[1])
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(40, 1, 40)
	cs.shape = bs
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)
	doll = (load("res://scenes/doll/doll.tscn") as PackedScene).instantiate()
	doll.external_input = true
	add_child(doll)
	pickup = WeaponPickup.new()
	pickup.name = "WeaponPickup"
	doll.add_child(pickup)
	await get_tree().physics_frame
	var hand_pos := pickup.hand_grip_global("Hand_R")
	hammer = Weapon.spawn("hammer", self, hand_pos, 0.0)
	hammer.global_position += hand_pos - hammer.grip_global()
	print("spawn: hand_pos=", hand_pos, " grip=", hammer.grip_global(), " radius=", pickup.pickup_radius, " hand=", pickup.hand("Hand_R"))


func _physics_process(_delta: float) -> void:
	if hammer == null:
		return
	ticks += 1
	var hp := pickup.hand_grip_global("Hand_R")
	var w := pickup.nearest_free_weapon("Hand_R")
	print("t%02d d=%.3f nearest=%s holding=%s held=%s hammer_held=%s cooldown=%s hv=%.2f" % [ticks, hp.distance_to(hammer.grip_global()), str(w), str(pickup.is_holding("Hand_R")), str(pickup.held.keys()), str(hammer.is_held()), str(pickup._cooldown_until), hammer.linear_velocity.length()])
	if ticks >= max_ticks:
		get_tree().quit(0)
