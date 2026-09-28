## Builder сцен куклы: собирает дерево узлов рэгдолла и сохраняет ДВЕ сцены с одним скриптом doll.gd:
##   res://scenes/doll/doll.tscn       — светлый клён  (assets/models/heroes/mannequin_v3/light/)
##   res://scenes/doll/doll_dark.tscn  — тёмный орех   (assets/models/heroes/mannequin_v3/dark/)
## Запуск: cd godot && godot --headless --path . -s res://tools/build_doll_scene.gd
## (перед этим GLB частей должны быть импортированы: Blender tools/blender/wooden_doll_v3.py -- tone=light|dark,
##  затем godot --headless --path . --import).
##
## Дерево: Node3D "Doll" (script doll.gd)
##   ├── RigidBody3D <Part> ×14  (масса из tuning.gd, XY-плоскость, CCD, без сна)
##   │     ├── CollisionShape3D "Shape"  (капсула/бокс по лофтам v3)
##   │     └── Node3D "Mesh" = инстанс <Part>.glb (origin GLB = проксимальный сустав → position = joint - centre тела)
##   └── Generic6DOFJoint3D <Joint> ×13 (Neck, Shoulder_*, Elbow_*, Wrist_*, Hip_*, Knee_*, Ankle_*):
##         линейные оси = 0, угловые X/Y заперты, угловой Z с лимитами, мотор Z (трение шарнира)
##         meta "friction_factor" — множитель трения относительно Tuning.JOINT_FRICTION (из Tuning.MUSCLE_GROUPS; doll.gd читает).
##         Лимиты в таблице ниже — НАМЕРЕНИЕ в measured-конвенции (угол = child.rot.z − parent.rot.z, L наружу = +),
##         _lim() переводит их в Jolt (см. комментарий там). Поза покоя (Tuning.POSE) лежит внутри лимитов с запасом ≥ 5°.
## Autoload в режиме -s недоступен, поэтому tuning.gd грузится как ресурс.
extends SceneTree

const DOLL_SCRIPT := "res://scenes/doll/doll.gd"
const TONES := {
	"light": {"out": "res://scenes/doll/doll.tscn", "uid": "uid://doll00000001", "mesh_dir": "res://assets/models/heroes/mannequin_v3/light/"},
	"dark": {"out": "res://scenes/doll/doll_dark.tscn", "uid": "uid://doll00000002", "mesh_dir": "res://assets/models/heroes/mannequin_v3/dark/"},
}

# Художественный манекен v3 (ART_DIRECTION.md «v3», R22): рост 1.80, человеческие пропорции.
# Высоты суставов (м): шея 1.47, плечи 1.43 (x ±0.22), локти 1.13, запястья 0.86, бёдра 0.91 (x ±0.10), колени 0.49, лодыжки 0.09.
const D := {
	"head_w": 0.24, "head_h": 0.30, "head_r": 0.15, "neck": 0.04,
	"torso_w": 0.36, "torso_h": 0.52, "torso_d": 0.22,
	"ua": 0.30, "la": 0.27, "hand": 0.18, "hand_w": 0.07, "hand_d": 0.07,
	"ul": 0.42, "ll": 0.40, "foot": 0.25, "foot_h": 0.08, "foot_w": 0.10,
	# v3.1 (28.09): конечности толще (лофты 0.105/0.088/0.150/0.112 → капсулы ≈ средний радиус лофта)
	"ua_r": 0.052, "la_r": 0.044, "ul_r": 0.070, "ll_r": 0.056,
	"shoulder_x": 0.22, "hip_x": 0.10,
}
const NECK_Y := 1.47
const SHOULDER_Y := 1.43
const ELBOW_Y := 1.13
const WRIST_Y := 0.86
const HIP_Y := 0.91
const KNEE_Y := 0.49
const ANKLE_Y := 0.09
const TORSO_C_Y := 1.17
const HEAD_C_Y := 1.625

var tone := "light"
var mesh_dir := ""
var T: Node
var doll_root: Node3D
var parts: Dictionary = {}
var phys_mat: PhysicsMaterial


func _init() -> void:
	T = load("res://scripts/tuning.gd").new()
	phys_mat = PhysicsMaterial.new()
	phys_mat.friction = 0.6   # FEEL_TARGET §4 (было 0.9): RM — после посадки скользит 0.3–0.5 роста
	phys_mat.bounce = 0.05
	for tn in TONES:
		tone = tn
		mesh_dir = TONES[tn]["mesh_dir"]
		if not _build_and_save(TONES[tn]["out"], TONES[tn]["uid"]):
			T.free()
			quit(1)
			return
	T.free()
	quit(0)


func _build_and_save(out: String, uid: String) -> bool:
	parts.clear()
	doll_root = Node3D.new()
	doll_root.name = "Doll"
	doll_root.set_script(load(DOLL_SCRIPT))

	var sx: float = D["shoulder_x"]
	var hx: float = D["hip_x"]
	var torso_c := Vector3(0, TORSO_C_Y, 0)

	# --- тела: name, centre, shape, size, mass key, proximal joint (origin GLB) ---
	_body("Torso", torso_c, "box", Vector3(D["torso_w"], D["torso_h"], D["torso_d"]), "Torso", torso_c)
	_body("Head", Vector3(0, HEAD_C_Y, 0), "capsule", Vector3(D["head_w"] / 2.0, D["head_h"], 0), "Head", Vector3(0, NECK_Y, 0))
	for side in [["L", 1.0], ["R", -1.0]]:
		var s: String = side[0]
		var k: float = side[1]
		_body("UpperArm_" + s, Vector3(sx * k, (SHOULDER_Y + ELBOW_Y) / 2.0, 0), "capsule", Vector3(D["ua_r"], D["ua"], 0), "UpperArm", Vector3(sx * k, SHOULDER_Y, 0))
		_body("LowerArm_" + s, Vector3(sx * k, (ELBOW_Y + WRIST_Y) / 2.0, 0), "capsule", Vector3(D["la_r"], D["la"], 0), "LowerArm", Vector3(sx * k, ELBOW_Y, 0))
		_body("Hand_" + s, Vector3(sx * k, WRIST_Y - D["hand"] / 2.0, 0), "box", Vector3(D["hand_w"], D["hand"], D["hand_d"]), "Hand", Vector3(sx * k, WRIST_Y, 0))
		_body("UpperLeg_" + s, Vector3(hx * k, (HIP_Y + KNEE_Y) / 2.0, 0), "capsule", Vector3(D["ul_r"], D["ul"], 0), "UpperLeg", Vector3(hx * k, HIP_Y, 0))
		_body("LowerLeg_" + s, Vector3(hx * k, (KNEE_Y + ANKLE_Y) / 2.0, 0), "capsule", Vector3(D["ll_r"], D["ll"], 0), "LowerLeg", Vector3(hx * k, KNEE_Y, 0))
		# стопа вытянута к камере (+Z): пятка z −0.07, носок z +0.18
		_body("Foot_" + s, Vector3(hx * k, D["foot_h"] / 2.0, 0.055), "box", Vector3(D["foot_w"], D["foot_h"], D["foot"]), "Foot", Vector3(hx * k, ANKLE_Y, 0))
		if parts.is_empty():
			return false

	# --- суставы (вращение вокруг Z = в плоскости экрана): name, parent, child, pos, lower°, upper° (Jolt, из _lim) ---
	# Лимиты-намерение (FEEL_TARGET §2, L, measured; R зеркально): поза покоя Tuning.POSE внутри с запасом.
	# Трение = Tuning.JOINT_FRICTION × MUSCLE_GROUPS[группа].friction_factor (группа = имя сустава до "_").
	var l: Vector2 = _lim(1.0, -40, 40)
	_joint("Neck", "Torso", "Head", Vector3(0, NECK_Y, 0), l.x, l.y)
	for side in [["L", 1.0], ["R", -1.0]]:
		var s: String = side[0]
		var k: float = side[1]
		l = _lim(k, -25, 170)   # плечо: покой +90 (Т-поза RM); наружу до «над головой», внутрь 25 (намерение −30, но лимит
		                        # Jolt мягкий ~10°: при −30 пик −39.5° против цели limit_Shoulder_L_min ≥ −40)
		_joint("Shoulder_" + s, "Torso", "UpperArm_" + s, Vector3(sx * k, SHOULDER_Y, 0), l.x, l.y)
		l = _lim(k, 0, 140)     # локоть: покой +10; сгиб наружу/вверх. Намерение FEEL_TARGET −10, но лимит Jolt мягкий (+10–12° под
		                        # ударом кисти 6 Н·с): при −10 пик −19.8°, при −5 — −17.1°; при 0 цель limit_Elbow_L_min ≥ −15
		_joint("Elbow_" + s, "UpperArm_" + s, "LowerArm_" + s, Vector3(sx * k, ELBOW_Y, 0), l.x, l.y)
		l = _lim(k, -35, 35)    # кисть: покой 0
		_joint("Wrist_" + s, "LowerArm_" + s, "Hand_" + s, Vector3(sx * k, WRIST_Y, 0), l.x, l.y)
		l = _lim(k, -30, 120)   # бедро: покой +12; нога в сторону/вверх
		_joint("Hip_" + s, "Torso", "UpperLeg_" + s, Vector3(hx * k, HIP_Y, 0), l.x, l.y)
		l = _lim(k, -5, 120)    # колено: покой +5; сгиб наружу, «не туда» только 5°
		_joint("Knee_" + s, "UpperLeg_" + s, "LowerLeg_" + s, Vector3(hx * k, KNEE_Y, 0), l.x, l.y)
		l = _lim(k, -25, 25)    # лодыжка: покой 0, PD выключен (только трение)
		_joint("Ankle_" + s, "LowerLeg_" + s, "Foot_" + s, Vector3(hx * k, ANKLE_Y, 0), l.x, l.y)

	_set_owner(doll_root)
	var ps := PackedScene.new()
	var err := ps.pack(doll_root)
	if err != OK:
		push_error("pack failed: %d" % err)
		return false
	err = ResourceSaver.save(ps, out)
	if err != OK:
		push_error("save failed: %d" % err)
		return false
	ResourceSaver.set_uid(out, ResourceUID.text_to_id(uid))  # стабильный uid между пересборками
	print("saved ", out, " (", tone, "): ", parts.size(), " bodies, ", _count(doll_root, "Generic6DOFJoint3D"), " joints, total mass ", T.total_mass())
	doll_root.free()
	return true


## Лимиты сустава для стороны. lo/hi — намерение в measured-конвенции ЛЕВОЙ стороны (угол = child.rot.z − parent.rot.z,
## наружу = +); правая сторона зеркальна (measured [−hi, −lo]).
## Факт Jolt/Godot (измерено feel_probe `limit`, FEEL_TARGET §0.1): Generic6DOFJoint3D.angular_limit_z = [lower, upper]
## ограничивает measured угол диапазоном [−upper, −lower]. Поэтому для L пишем [−hi, −lo] (→ measured [lo, hi]),
## для R — [lo, hi] (→ measured [−hi, −lo]). До 28.09 было наоборот: рука уходила внутрь на 170° и наружу только на 30°.
static func _lim(k: float, lo: float, hi: float) -> Vector2:
	return Vector2(-hi, -lo) if k > 0.0 else Vector2(lo, hi)


func _body(name: String, centre: Vector3, shape: String, size: Vector3, mass_key: String, origin: Vector3) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.name = name
	b.position = centre
	b.mass = T.MASS[mass_key]
	b.axis_lock_linear_z = true
	b.axis_lock_angular_x = true
	b.axis_lock_angular_y = true
	b.continuous_cd = true
	b.can_sleep = false
	b.linear_damp = T.doll_linear_damp(name)    # v6.2: ядро (голова, торс) и конечности раздельно — doll.gd ставит то же в _ready
	b.angular_damp = T.doll_angular_damp(name)
	b.physics_material_override = phys_mat
	doll_root.add_child(b)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	match shape:
		"box":
			var bs := BoxShape3D.new()
			bs.size = size
			cs.shape = bs
		"sphere":
			var ss := SphereShape3D.new()
			ss.radius = size.x
			cs.shape = ss
		"capsule":
			var cs3 := CapsuleShape3D.new()
			cs3.radius = size.x
			cs3.height = max(size.y, size.x * 2.0)
			cs.shape = cs3
	b.add_child(cs)
	var mesh_scene: PackedScene = load(mesh_dir + name + ".glb")
	if mesh_scene == null:
		push_error("missing mesh " + mesh_dir + name + ".glb (run Blender wooden_doll_v3.py -- tone=" + tone + " + godot --import)")
		parts.clear()
		return b
	var mi: Node3D = mesh_scene.instantiate()
	mi.name = "Mesh"
	mi.position = origin - centre       # origin GLB (проксимальный сустав) → точка сустава в локале тела
	mi.set_meta("rig_mesh", true)       # doll.gd прячет, если надет внешний скин (DollSkin)
	b.add_child(mi)
	parts[name] = b
	return b


func _joint(name: String, a: String, b: String, pos: Vector3, lower_deg: float, upper_deg: float) -> Generic6DOFJoint3D:
	var group: String = name.split("_")[0]
	var friction_factor: float = float((T.MUSCLE_GROUPS[group] as Dictionary)["friction_factor"])
	var j := Generic6DOFJoint3D.new()
	j.name = name
	j.position = pos
	doll_root.add_child(j)
	j.node_a = j.get_path_to(parts[a])
	j.node_b = j.get_path_to(parts[b])
	j.exclude_nodes_from_collision = true
	for ax in ["x", "y", "z"]:
		j.set("linear_limit_%s/enabled" % ax, true)
		j.set("linear_limit_%s/upper_distance" % ax, 0.0)
		j.set("linear_limit_%s/lower_distance" % ax, 0.0)
	for ax in ["x", "y"]:
		j.set("angular_limit_%s/enabled" % ax, true)
		j.set("angular_limit_%s/upper_angle" % ax, 0.0)
		j.set("angular_limit_%s/lower_angle" % ax, 0.0)
	j.set("angular_limit_z/enabled", true)
	j.set("angular_limit_z/lower_angle", deg_to_rad(lower_deg))
	j.set("angular_limit_z/upper_angle", deg_to_rad(upper_deg))
	# Трение шарнира: мотор с целевой скоростью 0 и ограниченным моментом (JOINT_FRICTION × фактор).
	# Угловые пружины Jolt (angular_spring_*) проверены 27.09 — держат плохо и взрываются, не используем.
	var f: float = T.JOINT_FRICTION * friction_factor
	j.set("angular_motor_z/enabled", f > 0.0)
	j.set("angular_motor_z/target_velocity", 0.0)
	j.set("angular_motor_z/force_limit", f)
	j.set_meta("friction_factor", friction_factor)
	return j


## owner для всех узлов, созданных здесь; у инстансов GLB — только корень инстанса (его внутренности принадлежат GLB-сцене).
func _set_owner(n: Node) -> void:
	for c in n.get_children():
		c.owner = doll_root
		if c.scene_file_path == "":
			_set_owner(c)


func _count(n: Node, cls: String) -> int:
	var k := 0
	for c in n.get_children():
		if c.is_class(cls):
			k += 1
	return k
