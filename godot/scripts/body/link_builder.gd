## Связки в бою (KitLink, docs/plan-demo/WORKSHOP_V4.md «Связки»): тела, суставы и вид одной связки. Зовёт ModularDoll._build_links
## после спавна в позе покоя: концы — точки pa / pb на телах в позе, длина — между ними (у чертежа len та же, она для энергии).
## Суставы — Generic6DOFJoint3D с meta "link" (не мышцы Doll): пин — оси X / Y и все сдвиги заперты, Z свободна (у стержня заперта и
## Z). Телескоп пружины и поршня — сустав между корпусом и штоком: базис X вдоль связки, сдвиг по X в ходу с пружиной, остальное
## заперто. Вид — простые меши кода (цилиндр, шары на концах, кольца пружины, звенья троса) материалами кита.
class_name LinkBuilder
extends RefCounted

const MAT_DIR := "res://assets/materials/kit/"
const MAT := {"rod": "Iron", "bar": "Brass", "spring": "Base_PaintYellow", "rope": "Rope", "piston": "Base_PaintRed", "cap": "Brass",
	"shaft": "Iron"}
const Z_UP := Vector3(0.0, 0.0, 1.0)


## Собрать связку l между телами ba и bb куклы d. {} — слишком короткая или битая. Тела и суставы уже детьми d.
static func build(d: Node3D, l: Dictionary, ba: RigidBody3D, bb: RigidBody3D) -> Dictionary:
	var t := String(l.get("type", "rod"))
	if not KitLink.is_type(t) or ba == null or bb == null or ba == bb:
		return {}
	var info := KitLink.info(t)
	var wa: Vector3 = ba.global_transform * (l.get("pa", Vector3.ZERO) as Vector3)
	var wb: Vector3 = bb.global_transform * (l.get("pb", Vector3.ZERO) as Vector3)
	var length := wa.distance_to(wb)
	if length < KitLink.MIN_LEN * 0.5:
		return {}
	var nm := "Link_" + String(l.get("id", "1"))
	var r := float(info["r"])
	var mass := KitLink.mass_of(t, length)
	var rec := {"id": String(l.get("id", "1")), "name": nm, "type": t, "bodies": [], "joints": [], "a": ba, "b": bb, "len": length,
		"strut": null, "extend": 0.0, "channel": int(l.get(KitLink.CHANNEL_KEY, 1)), "hp": 0.0,
		"pa": l.get("pa", Vector3.ZERO), "pb": l.get("pb", Vector3.ZERO)}
	match t:
		"rod", "bar":
			var body := _body(d, nm, wa, wb, r, mass, t, ba)
			rec["bodies"].append(body)
			rec["joints"].append(_joint(d, nm + "_JA", wa, Basis.IDENTITY, ba, body, t == "rod"))
			rec["joints"].append(_joint(d, nm + "_JB", wb, Basis.IDENTITY, bb, body, t == "rod"))
		"spring", "piston":
			var mid := (wa + wb) * 0.5
			var h1 := _body(d, nm, wa, mid, r, mass * 0.55, t, ba)               # корпус
			var h2 := _body(d, nm + "_R", mid, wb, r * 0.5, mass * 0.45, "shaft", ba)   # шток
			rec["bodies"].append(h1)
			rec["bodies"].append(h2)
			rec["joints"].append(_joint(d, nm + "_JA", wa, Basis.IDENTITY, ba, h1, false))
			rec["joints"].append(_joint(d, nm + "_JB", wb, Basis.IDENTITY, bb, h2, false))
			var ax := (wb - wa).normalized()
			var basis := Basis(ax, Z_UP.cross(ax).normalized(), Z_UP)
			var sl := {"lo": -float(info.get("stroke", 0.0)) * length, "hi": float(info.get("stroke", 0.0)) * length}
			if t == "spring":
				sl["k"] = float(info["k"])
				sl["c"] = float(info["c"])
			else:   # поршень: линейный мотор телескопа (точку покоя пружины Jolt на ходу не меняет) — втянут у нижнего упора
				sl = {"lo": 0.0, "hi": float(info["extend"]) * length, "motor": -float(info["speed"]), "force": float(info["force"])}
				rec["extend"] = float(info["extend"]) * length
			var s := _joint(d, nm + "_JS", mid, basis, h1, h2, true, sl)
			rec["joints"].append(s)
			rec["strut"] = s
			_rings(h2, length * 0.5, r * 1.15, 5 if t == "spring" else 0)
		"rope":
			var n := clampi(ceili(length / float(info["seg"])), 2, 24)
			var prev := ba
			for i in range(n):
				var p0 := wa.lerp(wb, float(i) / n)
				var p1 := wa.lerp(wb, float(i + 1) / n)
				var seg := _body(d, nm if i == 0 else "%s_%d" % [nm, i], p0, p1, r, mass / n, t, ba)
				rec["bodies"].append(seg)
				rec["joints"].append(_joint(d, "%s_J%d" % [nm, i], p0, Basis.IDENTITY, prev, seg, false))
				prev = seg
			rec["joints"].append(_joint(d, "%s_J%d" % [nm, n], wb, Basis.IDENTITY, prev, bb, false))
	return rec


## Тело-стержень от from до to (локальная +Y — вдоль), капсула радиуса r; физические флаги — как у детали-образца like.
static func _body(d: Node3D, nm: String, from: Vector3, to: Vector3, r: float, mass: float, look: String, like: RigidBody3D) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.name = nm
	b.mass = maxf(mass, 0.05)
	b.transform = d.global_transform.affine_inverse() * Transform3D(_basis_along(to - from), (from + to) * 0.5)
	b.collision_layer = like.collision_layer
	b.collision_mask = like.collision_mask
	for ax in ["x", "y", "z"]:
		b.set("axis_lock_linear_" + ax, like.get("axis_lock_linear_" + ax))
		b.set("axis_lock_angular_" + ax, like.get("axis_lock_angular_" + ax))
	b.can_sleep = like.can_sleep
	b.continuous_cd = like.continuous_cd
	var L := from.distance_to(to)
	var cs := CollisionShape3D.new()
	cs.name = "Shape_Link"
	var sh := CapsuleShape3D.new()
	sh.radius = r
	sh.height = maxf(L, 2.0 * r + 0.004)
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = L
	cm.radial_segments = 10
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = _mat(String(MAT.get(look, "Iron")))
	b.add_child(mi)
	if look != "rope" and look != "shaft":   # латунные шары на концах — шарниры связки
		for sy in [-0.5, 0.5]:
			var cap := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = r * 1.45
			sm.height = r * 2.9
			sm.radial_segments = 10
			sm.rings = 5
			cap.mesh = sm
			cap.position = Vector3(0.0, L * float(sy), 0.0)
			cap.material_override = _mat(MAT["cap"])
			b.add_child(cap)
	d.add_child(b)
	b.reset_physics_interpolation()
	return b


## Кольца пружины на штоке (вид): n колец вдоль половины длины.
static func _rings(b: RigidBody3D, half: float, r: float, n: int) -> void:
	for i in range(n):
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r * 0.75
		tm.outer_radius = r * 1.25
		tm.rings = 10
		tm.ring_segments = 4
		ring.mesh = tm
		ring.position = Vector3(0.0, lerpf(-half * 0.45, half * 0.45, float(i) / maxf(n - 1, 1)), 0.0)
		ring.material_override = _mat(MAT["spring"])
		b.add_child(ring)


## Сустав связки в точке at (базис basis — у телескопа X вдоль связки): lock — Z заперта (стержень, телескоп), slider — ход по X с пружиной.
static func _joint(d: Node3D, nm: String, at: Vector3, basis: Basis, a: RigidBody3D, b: RigidBody3D, lock: bool, slider: Dictionary = {}) -> Generic6DOFJoint3D:
	var j := Generic6DOFJoint3D.new()
	j.name = nm
	j.transform = d.global_transform.affine_inverse() * Transform3D(basis, at)
	j.exclude_nodes_from_collision = true
	for ax in ["x", "y", "z"]:
		j.set("linear_limit_%s/enabled" % ax, true)
		j.set("linear_limit_%s/upper_distance" % ax, 0.0)
		j.set("linear_limit_%s/lower_distance" % ax, 0.0)
	if not slider.is_empty():
		j.set("linear_limit_x/lower_distance", float(slider["lo"]))
		j.set("linear_limit_x/upper_distance", float(slider["hi"]))
		if slider.has("k"):
			j.set("linear_spring_x/enabled", true)
			j.set("linear_spring_x/stiffness", float(slider["k"]))
			j.set("linear_spring_x/damping", float(slider["c"]))
			j.set("linear_spring_x/equilibrium_point", 0.0)
		if slider.has("motor"):
			j.set("linear_motor_x/enabled", true)
			j.set("linear_motor_x/target_velocity", float(slider["motor"]))
			j.set("linear_motor_x/force_limit", float(slider["force"]))
	for ax in ["x", "y"]:
		j.set("angular_limit_%s/enabled" % ax, true)
		j.set("angular_limit_%s/upper_angle" % ax, 0.0)
		j.set("angular_limit_%s/lower_angle" % ax, 0.0)
	j.set("angular_limit_z/enabled", lock)
	j.set("angular_limit_z/upper_angle", 0.0)
	j.set("angular_limit_z/lower_angle", 0.0)
	j.set_meta("link", true)
	j.node_a = NodePath("../" + String(a.name))
	j.node_b = NodePath("../" + String(b.name))
	d.add_child(j)
	return j


## Базис, у которого +Y — вдоль dir, +Z — к камере (плоскость боя XY).
static func _basis_along(dir: Vector3) -> Basis:
	var y := dir.normalized() if dir.length_squared() > 1e-8 else Vector3.UP
	var x := y.cross(Z_UP)
	if x.length_squared() < 1e-8:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, y, x.cross(y).normalized())


static var _mats: Dictionary = {}


static func _mat(id: String) -> Material:
	if not _mats.has(id):
		var path := MAT_DIR + id + ".tres"
		_mats[id] = load(path) as Material if ResourceLoader.exists(path) else StandardMaterial3D.new()
	return _mats[id]


## Переставить тела связки rec между текущими точками концов (стенд мастерской, витрина гаража — тела заморожены, позу меняют руками).
static func place(_d: Node3D, rec: Dictionary) -> void:
	var ba: RigidBody3D = rec["a"]
	var bb: RigidBody3D = rec["b"]
	if not is_instance_valid(ba) or not is_instance_valid(bb):
		return
	var wa: Vector3 = ba.global_transform * (rec.get("pa", Vector3.ZERO) as Vector3)
	var wb: Vector3 = bb.global_transform * (rec.get("pb", Vector3.ZERO) as Vector3)
	var bodies: Array = rec["bodies"]
	var n := bodies.size()
	for i in range(n):
		var b := bodies[i] as RigidBody3D
		if not is_instance_valid(b):
			continue
		var p0 := wa.lerp(wb, float(i) / n)
		var p1 := wa.lerp(wb, float(i + 1) / n)
		b.global_transform = Transform3D(_basis_along(p1 - p0), (p0 + p1) * 0.5)
