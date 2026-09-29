## Крафтовое оружие (docs/plan-demo/BODY_CRAFT.md §4; CONCEPT_V2.md §9–10: «крафт меняет физику, а не цифры»).
## Собирает WeaponBlueprint (рукоять → головка → моды, цепь) в обычный Weapon, чтобы работали WeaponPickup, урон вида weapon,
## зачёт брошенного оружия и статистика:
##   • fixed-детали (головки, лезвия, моды, накладки, рукоять) сливаются в одно RigidBody3D — это тело: их CollisionShape3D
##     переезжают сюда (составные коллизии), меши — под узел Model; масса = сумма масс PartDef, центр масс и момент инерции —
##     настоящие: масса детали распределена по объёму её коллизий, моменты фигур сложены по Штейнеру (center_of_mass_mode
##     CUSTOM, inertia задана). Поэтому тяжёлая головка сдвигает ЦМ от хвата и растит инерцию, длинная рукоять — рычаг;
##   • joint-детали (цепь) — отдельные тела ChainLink на свободных шарнирах в плоскости XY (Generic6DOFJoint3D: линейные оси и
##     вращение X/Y заперты, Z свободна, только трение группы якоря — у Ankle k = 0); fixed-дети цепи (шар булавы) сливаются
##     с её сегментом — кистень;
##   • хват (grip_local) = Socket корневой рукояти, оружие вытянуто вдоль +X от хвата (конвенция weapon.gd): деталь растёт
##     в −Y от Socket, корень повёрнут на +90° вокруг Z. length = дальняя точка коллизий по +X (цепь — в выпрямленном виде);
##   • damage_mult = произведение weapon_mult деталей тела (лезвие, шипы > 1; тупая головка бьёт массой).
## Сборка — в _ready() ДО Weapon._ready() (тот собирает shapes/Model из детей и читает Tuning.WEAPON[weapon_id]); после
## super._ready() damage_mult и length перезаписываются своими (в Tuning.WEAPON крафтового id нет — там были бы 1.0 и 0.0).
## Сцена scenes/body/crafted_weapon.tscn (tools/build_craft_parts.gd), пресеты data/body/weapons/<id>.tres.
## Урон ∝ масса × скорость. С 29.09 масса оружия MASS_CAP (4 кг) не режется (Damage.weapon_mass, мягкий потолок
## Tuning.WEAPON_MASS_SOFT_CAP 10 кг): тяжелее головка — сильнее удар при той же скорости (BODY_CRAFT.md §6, tests/hitfx_core_probe).
class_name CraftedWeapon
extends Weapon

const SCENE := "res://scenes/body/crafted_weapon.tscn"
const PRESET_DIR := "res://data/body/weapons/"
## Корень: деталь растёт в −Y от Socket, оружие — вдоль +X от хвата (поворот +90° вокруг Z).
const GRIP_FRAME := Transform3D(Basis(Vector3(0, 0, 1), PI / 2.0), Vector3.ZERO)
## Через сколько после отпускания снимаются исключения коллизий звеньев с бывшим владельцем (как WeaponPickup.drop_cooldown_s).
const LINK_RELEASE_S := 0.35


## Звено кистеня: своё тело на свободном шарнире. Это тоже Weapon: DollCombat засчитывает удар звеном/шаром как удар оружием
## (масса звена, его damage_mult, атакующий — владелец всего оружия). Из группы weapons звено убрано, чтобы кисть не хватала
## кистень за шар и никто не перебирал звенья как отдельное оружие; скорость до шага (DollCombat.prev_vel) звено пишет само.
class ChainLink extends Weapon:
	var owner_weapon: Weapon = null

	func _ready() -> void:
		super._ready()
		remove_from_group(Weapon.GROUP)

	func _physics_process(delta: float) -> void:
		super._physics_process(delta)
		DollCombat.prev_vel[self] = [linear_velocity, angular_velocity]

	func is_held() -> bool:
		return owner_weapon != null and is_instance_valid(owner_weapon) and owner_weapon.is_held()

	func attacker(window_s: float = 3.0) -> Node:
		if owner_weapon == null or not is_instance_valid(owner_weapon):
			return null
		return owner_weapon.attacker(window_s)

	func drop() -> void:
		if owner_weapon != null and is_instance_valid(owner_weapon):
			owner_weapon.drop()


@export var blueprint: WeaponBlueprint

## uid → {def, body, rest (Transform3D детали в пространстве оружия, цепь выпрямлена), local (в пространстве своего тела),
## mesh (Node3D), anchors {имя: Transform3D в пространстве детали}, anchor_meta {имя: {accepts, joint_group, rest_deg}},
## parent (uid), link_root (деталь — корень звена), joint_point (шарнир в пространстве оружия), centre (центр масс детали там же)}
var parts_info: Dictionary = {}
var links: Array = []            # ChainLink в порядке сборки
var link_joints: Array = []      # Generic6DOFJoint3D (родитель → звено)
var total_mass := 0.0            # всё оружие вместе с цепью
var inertia_grip := 0.0          # Izz жёсткой части (этого тела) относительно хвата, кг·м²
var build_errors: PackedStringArray = []
## Сколько раз цепь выставлялась заново при телепорте тела (WeaponPickup.attach, spawn) — проба проверяет, что не каждый тик.
var teleports := 0
var _built := false
var _damage_mult := 1.0
var _length := 0.0
var _link_rest: Dictionary = {}   # ChainLink → Transform3D в пространстве оружия
var _body_frame: Dictionary = {}  # тело → его система в пространстве оружия (выпрямленная сборка)
var _excepted: Array = []         # части куклы-владельца, с которыми у звеньев исключения коллизий
var _release_at := -1.0


static func preset(id: String) -> WeaponBlueprint:
	var path := PRESET_DIR + id + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as WeaponBlueprint


## Экземпляр сцены с чертежом (ещё не в дереве: сборка — при add_child).
static func create(bp: WeaponBlueprint) -> CraftedWeapon:
	var w: CraftedWeapon = (load(SCENE) as PackedScene).instantiate()
	w.blueprint = bp
	return w


## Как Weapon.spawn, но по чертежу или id пресета: add_child к parent, поставить в pos с поворотом rot_z_deg в плоскости экрана.
static func spawn_preset(bp_or_id: Variant, parent: Node, pos: Vector3, rot_z_deg: float = 0.0) -> CraftedWeapon:
	var bp: WeaponBlueprint = bp_or_id as WeaponBlueprint if bp_or_id is WeaponBlueprint else preset(String(bp_or_id))
	if bp == null:
		push_error("CraftedWeapon.spawn_preset: no blueprint '%s'" % str(bp_or_id))
		return null
	var w := create(bp)
	parent.add_child(w)
	w.global_transform = Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(rot_z_deg)), pos)
	return w


func _ready() -> void:
	if not _built:
		_build()
	super._ready()
	damage_mult = _damage_mult
	length = _length
	set_notify_transform(true)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _release_at >= 0.0 and _time >= _release_at and not is_held():
		_set_link_exceptions([])
		_release_at = -1.0


## Телепорт тела (WeaponPickup.attach ставит global_transform, Weapon.spawn / spawn_preset) — цепь переставляется выпрямленной
## вслед за рукоятью, иначе шарниры рванули бы звенья через полкарты. Физический шаг двигает тело без этого уведомления.
## Уведомление приходит во время SceneTree.flush_transform_notifications: уведомления звеньев, поставленные в очередь отсюда,
## доходят до физики только после следующего шага (и затираются им) — поэтому состояние звеньев пишется в PhysicsServer3D сразу.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and _built and is_inside_tree() and not links.is_empty():
		teleports += 1
		for l in links:
			var link := l as ChainLink
			if is_instance_valid(link):
				_place_link(link, global_transform * (_link_rest[link] as Transform3D), linear_velocity, angular_velocity)


func _place_link(link: ChainLink, xf: Transform3D, v: Vector3, w: Vector3) -> void:
	link.global_transform = xf
	link.linear_velocity = v
	link.angular_velocity = w
	var rid := link.get_rid()
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, v)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, w)


## Звенья не бьют того, кто держит оружие (WeaponPickup ставит исключения только корню).
func set_holder(pickup: Node, hand: RigidBody3D) -> void:
	super.set_holder(pickup, hand)
	if pickup != null:
		var d: Variant = pickup.get("doll")
		if d is Doll:
			_set_link_exceptions((d as Doll).parts.values())
		_release_at = -1.0
	else:
		_release_at = _time + LINK_RELEASE_S


func _set_link_exceptions(bodies: Array) -> void:
	for l in links:
		if not is_instance_valid(l):
			continue
		for b in _excepted:
			if is_instance_valid(b):
				(l as ChainLink).remove_collision_exception_with(b)
		for b in bodies:
			if is_instance_valid(b):
				(l as ChainLink).add_collision_exception_with(b)
	_excepted = bodies.duplicate()


## Все тела оружия: это (жёсткая часть) и звенья цепи.
func bodies() -> Array:
	var out: Array = [self]
	out.append_array(links)
	return out


## Наибольший разрыв шарниров цепи, м: точка якоря родителя против Socket звена в мире (0 — цепь цела).
func joint_separation() -> float:
	var worst := 0.0
	for uid in parts_info:
		var info: Dictionary = parts_info[uid]
		if not bool(info["link_root"]):
			continue
		var parent_body: RigidBody3D = parts_info[String(info["parent"])]["body"]
		var link: RigidBody3D = info["body"]
		var p: Vector3 = info["joint_point"]
		var a := parent_body.global_transform * ((_body_frame[parent_body] as Transform3D).affine_inverse() * p)
		var b := link.global_transform * ((_body_frame[link] as Transform3D).affine_inverse() * p)
		worst = maxf(worst, a.distance_to(b))
	return worst


func com_from_grip() -> float:
	return (center_of_mass - grip_local).length()


## Сводка для мастерской и проб: масса (всё / жёсткая часть), ЦМ и инерция от хвата, длина, множитель, число тел.
func summary() -> Dictionary:
	return {"id": blueprint.id if blueprint != null else "", "mass": total_mass, "rigid_mass": mass, "com_from_grip": com_from_grip(),
		"com_x": center_of_mass.x - grip_local.x, "inertia_grip": inertia_grip, "length": length, "damage_mult": damage_mult,
		"bodies": 1 + links.size(), "errors": build_errors}


# --- сборка ---

func _build() -> void:
	_built = true
	if blueprint == null:
		build_errors.append("нет чертежа")
		return
	build_errors = blueprint.validate()
	if not build_errors.is_empty():
		push_warning("CraftedWeapon %s: %s" % [blueprint.id, ", ".join(build_errors)])
	if blueprint.id != "":
		weapon_id = "craft_" + blueprint.id
	grip_local = Vector3.ZERO
	var model := Node3D.new()
	model.name = "Model"
	add_child(model)
	var body_frame := {self: Transform3D.IDENTITY}   # тело → его система в пространстве оружия (выпрямленная сборка)
	var body_model := {self: model}
	var body_items := {self: []}                     # тело → [[масса, центр (тело), тензор фигуры (Basis) на массу 1 × m]]
	var body_mult := {self: 1.0}
	var max_x := 0.0
	for n in _ordered_nodes():
		var uid := String(n.get("uid", ""))
		var parent_uid := String(n.get("parent", ""))
		var def := BodyBlueprint.part_def(String(n.get("part", "")))
		if def == null or def.scene == null:
			build_errors.append("деталь «%s» не загружена" % n.get("part", ""))
			continue
		var inst: Node3D = def.scene.instantiate()
		var sock := inst.get_node_or_null("Socket") as Node3D
		var sock_xf: Transform3D = sock.transform if sock != null else Transform3D.IDENTITY
		var rest: Transform3D
		var anchor_meta := {}
		if parent_uid == "":
			rest = GRIP_FRAME * sock_xf.affine_inverse()
		else:
			if not parts_info.has(parent_uid):
				build_errors.append("у «%s» родитель «%s» не собран" % [uid, parent_uid])
				inst.free()
				continue
			var pinfo: Dictionary = parts_info[parent_uid]
			var an := _anchor_name(String(n.get("anchor", "")))
			if not (pinfo["anchors"] as Dictionary).has(an):
				build_errors.append("у «%s» нет якоря %s" % [pinfo["def"].id, an])
				inst.free()
				continue
			anchor_meta = (pinfo["anchor_meta"] as Dictionary)[an]
			var accepts: PackedStringArray = anchor_meta.get("accepts", PackedStringArray())
			if not accepts.is_empty() and not accepts.has(def.kind):
				build_errors.append("%s.%s не принимает вид %s" % [pinfo["def"].id, an, def.kind])
			var rest_deg := float(n.get("rest_deg", anchor_meta.get("rest_deg", 0.0)))
			rest = (pinfo["rest"] as Transform3D) * (pinfo["anchors"][an] as Transform3D) \
				* Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(rest_deg)), Vector3.ZERO) * sock_xf.affine_inverse()
		var body: RigidBody3D = self
		var link_root := false
		if parent_uid != "":
			if def.attach == "joint":
				link_root = true
				body = _make_link(uid, def, rest)
				body_frame[body] = rest
				body_model[body] = body.get_node("Model")
				body_items[body] = []
				body_mult[body] = 1.0
			else:
				body = parts_info[parent_uid]["body"]
		var local: Transform3D = (body_frame[body] as Transform3D).affine_inverse() * rest
		body_mult[body] = float(body_mult[body]) * def.weapon_mult
		# формы и меш переезжают в тело; масса детали — по объёму её форм
		var shapes: Array = []
		var vol_total := 0.0
		var mesh: Node3D = null
		var anchors := {}
		var metas := {}
		for c in inst.get_children():
			if c is CollisionShape3D:
				var cs := c as CollisionShape3D
				inst.remove_child(cs)
				cs.owner = null
				cs.name = "%s_%s" % [uid, cs.name]
				cs.transform = local * cs.transform
				body.add_child(cs)
				var vi := _volume_inertia(cs.shape)
				shapes.append([cs, vi])
				vol_total += float(vi[0])
				for corner in _shape_corners(cs):
					max_x = maxf(max_x, ((body_frame[body] as Transform3D) * corner).x)
			elif c.name == "Mesh" and c is Node3D:
				mesh = c as Node3D
				inst.remove_child(mesh)
				mesh.owner = null
				mesh.name = "%s_%s" % [uid, def.id]
				mesh.transform = local * mesh.transform
				(body_model[body] as Node3D).add_child(mesh)
			elif c is Marker3D and String(c.name).begins_with("Anchor_"):
				anchors[String(c.name)] = (c as Marker3D).transform
				metas[String(c.name)] = {"accepts": c.get_meta("accepts", PackedStringArray()),
					"joint_group": String(c.get_meta("joint_group", "Ankle")), "rest_deg": float(c.get_meta("rest_deg", 0.0))}
		var centre := Vector3.ZERO
		for s in shapes:
			centre += (body_frame[body] as Transform3D) * (s[0] as CollisionShape3D).transform.origin * (float(s[1][0]) / vol_total if vol_total > 0.0 else 1.0 / shapes.size())
		if shapes.is_empty():
			centre = rest.origin
		for s in shapes:
			var cs: CollisionShape3D = s[0]
			var vi: Array = s[1]
			var m := def.mass * (float(vi[0]) / vol_total if vol_total > 0.0 else 1.0 / shapes.size())
			var b := cs.transform.basis.orthonormalized()
			var t_local: Basis = b * Basis.from_scale(vi[1] * m) * b.transposed()
			(body_items[body] as Array).append([m, cs.transform.origin, t_local])
		if shapes.is_empty():
			(body_items[body] as Array).append([def.mass, local.origin, Basis.from_scale(Vector3.ZERO)])
		var joint_point := Vector3.ZERO
		if link_root:
			var pinfo: Dictionary = parts_info[parent_uid]
			joint_point = ((pinfo["rest"] as Transform3D) * (pinfo["anchors"][_anchor_name(String(n.get("anchor", "")))] as Transform3D)).origin
		parts_info[uid] = {"def": def, "body": body, "rest": rest, "local": local, "mesh": mesh, "anchors": anchors,
			"anchor_meta": metas, "joint_group": String(anchor_meta.get("joint_group", "Ankle")), "parent": parent_uid,
			"link_root": link_root, "joint_point": joint_point, "centre": centre}
		inst.free()
	# масса, центр масс, инерция каждого тела
	total_mass = 0.0
	for body in body_items:
		var props := _mass_props(body_items[body])
		var rb := body as RigidBody3D
		rb.mass = maxf(float(props[0]), 0.01)
		rb.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		rb.center_of_mass = props[1]
		rb.inertia = props[2]
		total_mass += rb.mass
		if rb is ChainLink:
			(rb as ChainLink).damage_mult = float(body_mult[body])
			(rb as ChainLink).length = _length
	var d := center_of_mass - grip_local
	inertia_grip = inertia.z + mass * (d.x * d.x + d.y * d.y)
	_damage_mult = float(body_mult[self])
	_length = max_x
	for l in links:
		(l as ChainLink).length = _length
	_body_frame = body_frame
	_make_joints()


## Узлы чертежа в порядке «родитель раньше детей».
func _ordered_nodes() -> Array:
	var out: Array = []
	var done := {}
	var pending: Array = blueprint.nodes.duplicate()
	var guard := 0
	while not pending.is_empty() and guard < 64:
		guard += 1
		var rest: Array = []
		for n in pending:
			var p := String(n.get("parent", ""))
			if p == "" or done.has(p):
				out.append(n)
				done[String(n.get("uid", ""))] = true
			else:
				rest.append(n)
		if rest.size() == pending.size():
			build_errors.append("цикл или потерянный родитель в чертеже")
			break
		pending = rest
	return out


static func _anchor_name(a: String) -> String:
	return a if a.begins_with("Anchor_") else "Anchor_" + a


func _make_link(uid: String, def: PartDef, rest: Transform3D) -> ChainLink:
	var link := ChainLink.new()
	link.name = "%s_%s" % [def.name_prefix, uid]
	link.owner_weapon = self
	link.weapon_id = weapon_id
	link.top_level = true           # физика двигает звено само; телепорт рукояти — _notification
	link.axis_lock_linear_z = true
	link.axis_lock_angular_x = true
	link.axis_lock_angular_y = true
	link.continuous_cd = continuous_cd
	link.can_sleep = can_sleep
	link.collision_layer = collision_layer
	link.collision_mask = collision_mask
	link.physics_material_override = physics_material_override
	var model := Node3D.new()
	model.name = "Model"
	link.add_child(model)
	link.transform = global_transform * rest
	add_child(link)
	links.append(link)
	_link_rest[link] = rest
	return link


func _make_joints() -> void:
	for uid in parts_info:
		var info: Dictionary = parts_info[uid]
		if not bool(info["link_root"]):
			continue   # часть жёсткого тела или fixed-деталь, слитая со звеном
		var link := info["body"] as ChainLink
		var parent_body: RigidBody3D = parts_info[String(info["parent"])]["body"]
		var group := String(info["joint_group"])
		var gdef: Dictionary = Tuning.MUSCLE_GROUPS.get(group, Tuning.MUSCLE_GROUPS["Ankle"])
		var j := Generic6DOFJoint3D.new()
		j.name = "Free_%s" % uid
		j.top_level = true
		j.exclude_nodes_from_collision = true
		add_child(j)
		# точка шарнира — якорь родителя (= Socket звена); ось Z мира
		j.global_transform = Transform3D(Basis.IDENTITY, global_transform * (info["joint_point"] as Vector3))
		for ax in ["x", "y", "z"]:
			j.set("linear_limit_%s/enabled" % ax, true)
			j.set("linear_limit_%s/upper_distance" % ax, 0.0)
			j.set("linear_limit_%s/lower_distance" % ax, 0.0)
		for ax in ["x", "y"]:
			j.set("angular_limit_%s/enabled" % ax, true)
			j.set("angular_limit_%s/upper_angle" % ax, 0.0)
			j.set("angular_limit_%s/lower_angle" % ax, 0.0)
		j.set("angular_limit_z/enabled", false)
		# мышц в оружии нет: только трение шарнира группы якоря (Ankle: k = 0, JOINT_FRICTION × friction_factor)
		var f: float = Tuning.JOINT_FRICTION * float(gdef.get("friction_factor", 1.0))
		j.set("angular_motor_z/enabled", f > 0.0)
		j.set("angular_motor_z/target_velocity", 0.0)
		j.set("angular_motor_z/force_limit", f)
		j.set_meta("friction_factor", float(gdef.get("friction_factor", 1.0)))
		j.node_a = j.get_path_to(parent_body)
		j.node_b = j.get_path_to(link)
		link_joints.append(j)


## [масса, центр масс, главные моменты (диагональ тензора в осях тела)] по фигурам [[m, центр, тензор]].
static func _mass_props(items: Array) -> Array:
	var m := 0.0
	var c := Vector3.ZERO
	for it in items:
		m += float(it[0])
		c += (it[1] as Vector3) * float(it[0])
	if m <= 0.0:
		return [0.0, Vector3.ZERO, Vector3.ONE * 0.001]
	c /= m
	var ixx := 0.0
	var iyy := 0.0
	var izz := 0.0
	for it in items:
		var mi := float(it[0])
		var t: Basis = it[2]
		var d: Vector3 = (it[1] as Vector3) - c
		ixx += t.x.x + mi * (d.y * d.y + d.z * d.z)
		iyy += t.y.y + mi * (d.x * d.x + d.z * d.z)
		izz += t.z.z + mi * (d.x * d.x + d.y * d.y)
	return [m, c, Vector3(maxf(ixx, 1e-4), maxf(iyy, 1e-4), maxf(izz, 1e-4))]


## [объём, моменты на единицу массы в осях фигуры] (ось цилиндра/капсулы — Y; капсула ≈ цилиндр полной высоты).
static func _volume_inertia(sh: Shape3D) -> Array:
	if sh is BoxShape3D:
		var s := (sh as BoxShape3D).size
		return [s.x * s.y * s.z, Vector3(s.y * s.y + s.z * s.z, s.x * s.x + s.z * s.z, s.x * s.x + s.y * s.y) / 12.0]
	if sh is SphereShape3D:
		var r := (sh as SphereShape3D).radius
		return [4.0 / 3.0 * PI * r * r * r, Vector3.ONE * 0.4 * r * r]
	if sh is CylinderShape3D:
		var cy := sh as CylinderShape3D
		var a := (3.0 * cy.radius * cy.radius + cy.height * cy.height) / 12.0
		return [PI * cy.radius * cy.radius * cy.height, Vector3(a, 0.5 * cy.radius * cy.radius, a)]
	if sh is CapsuleShape3D:
		var ca := sh as CapsuleShape3D
		var hc := maxf(ca.height - 2.0 * ca.radius, 0.0)
		var a := (3.0 * ca.radius * ca.radius + ca.height * ca.height) / 12.0
		return [PI * ca.radius * ca.radius * hc + 4.0 / 3.0 * PI * pow(ca.radius, 3.0), Vector3(a, 0.5 * ca.radius * ca.radius, a)]
	return [0.001, Vector3.ONE * 0.001]


## Углы габарита формы в системе тела (для длины оружия).
static func _shape_corners(cs: CollisionShape3D) -> Array:
	var half := Vector3.ZERO
	var sh := cs.shape
	if sh is BoxShape3D:
		half = (sh as BoxShape3D).size / 2.0
	elif sh is SphereShape3D:
		half = Vector3.ONE * (sh as SphereShape3D).radius
	elif sh is CylinderShape3D:
		half = Vector3((sh as CylinderShape3D).radius, (sh as CylinderShape3D).height / 2.0, (sh as CylinderShape3D).radius)
	elif sh is CapsuleShape3D:
		half = Vector3((sh as CapsuleShape3D).radius, (sh as CapsuleShape3D).height / 2.0, (sh as CapsuleShape3D).radius)
	var out: Array = []
	for i in range(8):
		out.append(cs.transform * Vector3(half.x * (1 if i & 1 else -1), half.y * (1 if i & 2 else -1), half.z * (1 if i & 4 else -1)))
	return out
