## Проба хуков Doll для PvE (29.09, сессия «Определение игры и планы»): request_dash / request_flip, team + TEAM_DAMAGE_MULT,
## detach_part (+ сигнал part_detached, выпадение оружия, KO при голове), reattach_part (сустав на месте, мышцы, масса),
## max_hp. Headless:
##   godot --headless --path . --fixed-fps 60 res://tests/doll_hooks_probe.tscn   → код выхода 0/1
extends Node3D

const DollScene := preload("res://scenes/doll/doll.tscn")
const PickupScript := preload("res://scenes/weapons/weapon_pickup.gd")

var checks: Array = []
var ok := true
var t := 0.0
var stage := 0
var a: Doll
var b: Doll
var c: Doll
var detached: RigidBody3D
var detached_sig: Array = []
var pickup: WeaponPickup
var max_speed := 0.0
var pairs_before := 0
var mass_before := 0.0
var torso_w_before := 0.0
var reattached_sig: Array = []


func _check(id: String, cond: bool, detail: String) -> void:
	checks.append({"id": id, "ok": cond, "detail": detail})
	if not cond:
		ok = false
	print("  %-26s %s  %s" % [id, "ok  " if cond else "FAIL", detail])


func _spawn(x: float) -> Doll:
	var d := DollScene.instantiate() as Doll
	d.external_input = true
	add_child(d)
	d.global_position = Vector3(x, 0, 0)
	return d


func _ready() -> void:
	print("=== DOLL HOOKS PROBE ===")
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 4)
	cs.shape = box
	floor_body.add_child(cs)
	add_child(floor_body)
	floor_body.global_position = Vector3(0, -0.5, 0)
	a = _spawn(-3.0)
	b = _spawn(0.0)
	c = _spawn(3.0)

	b.part_detached.connect(func(pn: String, by: Node) -> void: detached_sig.append([pn, by]))
	b.part_reattached.connect(func(pn: String) -> void: reattached_sig.append(pn))


func _physics_process(delta: float) -> void:
	t += delta
	match stage:
		0:
			if t >= 1.0:
				# команды
				a.team = "enemy"
				b.team = "enemy"
				var hp0 := b.hp
				b.take_damage(10.0, a, "Torso", b.torso().global_position, Vector3.UP, "body")
				_check("team_same", is_equal_approx(hp0 - b.hp, 10.0 * Tuning.TEAM_DAMAGE_MULT), "урон своему %.2f (ожидалось %.2f)" % [hp0 - b.hp, 10.0 * Tuning.TEAM_DAMAGE_MULT])
				hp0 = b.hp
				b.take_damage(10.0, c, "Torso", b.torso().global_position, Vector3.UP, "body")
				_check("team_other", is_equal_approx(hp0 - b.hp, 10.0), "урон от чужого %.2f" % (hp0 - b.hp))
				b.team_damage_mult = 0.0
				hp0 = b.hp
				b.take_damage(10.0, a, "Torso", b.torso().global_position, Vector3.UP, "body")
				_check("team_mult_zero", is_equal_approx(hp0 - b.hp, 0.0) and is_equal_approx(b.team_mult_for(a), 0.0), "team_damage_mult 0: урон своему %.2f" % (hp0 - b.hp))
				_check("team_mult_other", is_equal_approx(b.team_mult_for(c), 1.0), "чужой при team_damage_mult 0 — полный")
				b.team_damage_mult = -1.0
				var chp := c.hp
				c.take_damage(10.0, a, "Torso", c.torso().global_position, Vector3.UP, "body")
				_check("team_empty", is_equal_approx(chp - c.hp, 10.0), "без команды полный урон %.2f" % (chp - c.hp))
				# рывок и кувырок по запросу
				a.input_vec = Vector2(1, 0)
				a.request_dash()
				torso_w_before = c.torso().angular_velocity.z
				c.input_vec = Vector2(1, 0)
				c.request_flip()
				stage = 1
		1:
			_check("request_dash", a.is_dashing(), "is_dashing после request_dash")
			_check("request_flip", absf(c.torso().angular_velocity.z - torso_w_before) > 1.0, "ω торса %.2f → %.2f" % [torso_w_before, c.torso().angular_velocity.z])
			a.input_vec = Vector2.ZERO
			c.input_vec = Vector2.ZERO
			# оружие в левую кисть b, затем отрыв предплечья
			pickup = PickupScript.new()
			pickup.name = "WeaponPickup"
			pickup.auto_pickup = false
			b.add_child(pickup)
			var hammer := Weapon.spawn("hammer", self, pickup.hand_grip_global("Hand_L"), 0.0)
			hammer.global_position += pickup.hand_grip_global("Hand_L") - hammer.grip_global()
			_check("attach", pickup.attach("Hand_L", hammer), "молот в Hand_L")
			pairs_before = b._muscle_pairs.size()
			mass_before = b.total_mass
			detached = b.detach_part("LowerArm_L", a)
			_check("detach_returns", detached != null and detached.name == "LowerArm_L", "вернул %s" % (detached.name if detached else "null"))
			_check("detach_parts", not b.parts.has("LowerArm_L") and not b.parts.has("Hand_L") and b.parts.has("UpperArm_L"), "части: %d" % b.parts.size())
			_check("detach_joints", not b.joints.has("Elbow_L") and not b.joints.has("Wrist_L") and b.joints.has("Shoulder_L"), "суставы: %d" % b.joints.size())
			_check("detach_pairs", b._muscle_pairs.size() == pairs_before - 2, "пары мышц %d → %d" % [pairs_before, b._muscle_pairs.size()])
			_check("detach_mass", b.total_mass < mass_before - 0.5, "масса %.1f → %.1f" % [mass_before, b.total_mass])
			_check("detach_weapon_drop", not pickup.is_holding("Hand_L"), "молот выпал")
			_check("detach_signal", detached_sig.size() == 1 and detached_sig[0][0] == "LowerArm_L" and detached_sig[0][1] == a, "сигнал %s" % [detached_sig])
			_check("detach_alive", b.alive, "кукла жива")
			stage = 2
			t = 0.0
		2:
			for d in [a, b, c]:
				max_speed = maxf(max_speed, (d as Doll).max_part_speed())
			if is_instance_valid(detached):
				max_speed = maxf(max_speed, detached.linear_velocity.length())
			if t >= 2.5:
				_check("no_explosion", max_speed < 15.0, "макс. скорость частей %.2f м/с" % max_speed)
				var gap := detached.global_position.distance_to(b.parts["UpperArm_L"].global_position)
				_check("detached_free", gap > 0.35, "оторванное предплечье в %.2f м от плеча" % gap)
				_check("detached_on_floor", detached.global_position.y < 0.6, "лежит: y %.2f" % detached.global_position.y)
				_check("doll_ok", b.alive and b.head().global_position.y > 0.3, "голова y %.2f" % b.head().global_position.y)
				_check("reattach_ok", b.reattach_part(detached), "reattach_part(LowerArm_L)")
				_check("reattach_again_false", not b.reattach_part(detached), "повторно — false")
				_check("reattach_parts", b.parts.has("LowerArm_L") and b.parts.has("Hand_L"), "части: %d" % b.parts.size())
				_check("reattach_joints", b.joints.has("Elbow_L") and b.joints.has("Wrist_L"), "суставы: %d" % b.joints.size())
				_check("reattach_pairs", b._muscle_pairs.size() == pairs_before, "пары мышц %d (было %d)" % [b._muscle_pairs.size(), pairs_before])
				_check("reattach_mass", is_equal_approx(b.total_mass, mass_before), "масса %.1f" % b.total_mass)
				_check("reattach_signal", reattached_sig == ["LowerArm_L"], "сигнал %s" % [reattached_sig])
				max_speed = 0.0
				stage = 3
				t = 0.0
		3:
			max_speed = maxf(max_speed, b.max_part_speed())
			if t >= 2.0:
				var ua := b.parts["UpperArm_L"] as RigidBody3D
				var la := b.parts["LowerArm_L"] as RigidBody3D
				var gap: float = (ua.global_transform * (b._joint_xf_a["Elbow_L"] as Transform3D).origin).distance_to(la.global_transform * (b._joint_xf_b["Elbow_L"] as Transform3D).origin)
				_check("reattach_gap", gap < 0.02, "разрыв локтя %.4f м" % gap)
				_check("reattach_no_explosion", max_speed < 15.0, "макс. скорость частей %.2f м/с" % max_speed)
				var dev := absf(rad_to_deg(wrapf(la.global_rotation.z - ua.global_rotation.z - float(b._muscle_pairs.filter(func(e: Array) -> bool: return e[7] == "Elbow_L")[0][2]), -PI, PI)))
				_check("reattach_pose", dev < 25.0, "локоть от позы покоя %.1f°" % dev)
				# max_hp
				var e := DollScene.instantiate() as Doll
				e.max_hp = 40.0
				e.external_input = true
				add_child(e)
				e.global_position = Vector3(6.0, 0, 0)
				_check("max_hp_spawn", is_equal_approx(e.hp, 40.0), "hp %.1f при max_hp 40" % e.hp)
				e.take_damage(15.0, null, "Torso", e.torso().global_position, Vector3.UP, "body")
				e.reset_for_match()
				_check("max_hp_reset", is_equal_approx(e.hp, 40.0), "reset_for_match → hp %.1f" % e.hp)
				detached_sig.clear()
				var h := b.detach_part("Head", c)
				_check("detach_head_ko", h != null and not b.alive and b.is_broken(), "голова → KO (alive %s)" % b.alive)
				_check("detach_head_signal", detached_sig.size() == 1 and b.last_ko_record.get("kind", "") == "detach", "kind %s" % b.last_ko_record.get("kind", ""))
				print("=== %s ===" % ("OK" if ok else "FAIL"))
				get_tree().quit(0 if ok else 1)
