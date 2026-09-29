## Модульная кукла (docs/plan-demo/BODY_CRAFT.md §3, CONCEPT_V2 §4–8): тело собирается из деталей по чертежу BodyBlueprint
## в _ready() ДО Doll._ready() — Doll дальше сам находит тела и суставы по дереву и навешивает мышцы по префиксу имени сустава.
## Исключение из правила 2 ASSET_PIPELINE (CONCEPT_V2, «Следствия для кода»): детали — .tscn с маркерами (tools/build_body_parts.gd),
## рантайм только расставляет их по чертежу.
##
## Сборка:
##   • деталь = инстанс PartDef.scene (RigidBody3D, маркеры Socket / Anchor_*), имя тела — BodyBlueprint.body_name_of(uid);
##   • посадка: child = anchor × socket⁻¹ (кадр якоря родителя в кукле × обратный кадр Socket ребёнка);
##   • зеркало: правый якорь (meta mirror) отражает деталь по X — маркеры и формы M·T·M, меш — Mesh_R из сцены, если есть, иначе M·T;
##     зеркальность наследуется вниз по цепи (локоть правой руки тоже правый);
##   • сустав — Generic6DOFJoint3D как в doll.tscn (tools/build_doll_scene.gd `_joint`): линейные оси и углы X/Y заперты, Z с лимитами,
##     мотор-трение Tuning.JOINT_FRICTION × friction_factor группы, meta friction_factor; имя — BodyBlueprint.joint_name_of(uid);
##   • fixed-деталь сливается с телом родителя: формы и меш переезжают, масса складывается, центр масс — взвешенный (CUSTOM);
##   • кукла ставится на пол: нижняя точка форм собранного тела — y = 0 локально (у human торс ровно на 1.17, как в doll.tscn).
## Углы (градусы): от направления якоря (−Y), наружу = + для левой стороны, у зеркальной — знак меняется. Jolt считает угол сустава
## от собранной позы, Doll — measured = child.rot.z − parent.rot.z, поэтому поза покоя = a0 + знак × угол (a0 — measured-угол сборки).
## Поза покоя чертежа ставится set_pose({сустав: measured°}) после Doll._ready, спавн сразу в позе — _snap_pose (центр поворота —
## точка сустава на текущем теле-родителе, см. там); reset_pose() возвращает позу чертежа, а не Tuning.POSE.
##
## Поверх Doll (без правки doll.gd, хуки для другой сессии — BODY_CRAFT.md §6):
##   • фиксированная тяга Ядра (CONCEPT_V2 §7, fixed_thrust): сила = MOVE_FORCE_PER_KG × thrust_mass(), а не × total_mass — тяжёлая
##     сборка разгоняется медленнее, лёгкая быстрее, у human (40 кг) тяга та же. Doll читает total_mass в _physics_process только в тяге
##     и в клэмпе полёта (_cap_flight_speed, окно knockback_until) — на время тика вне полёта total_mass подменяется на thrust_mass();
##     в окне полёта тяга прежняя (там она только рулит). Правильный хук — метод Doll.thrust_mass() в строках тяги.
##   • демпфирование мышц по настоящей инерции цепи: Doll берёт c = 2ζ√(k·I) с I группы Tuning.MUSCLE_GROUPS (цепь куклы v3); у кисти
##     прямо на локте или ноги на плече инерция в 0.05–4 раза другая — явный PD дрожит или болтается. Если I цепи отличается от I группы
##     больше INERTIA_TOLERANCE, c масштабируется на √(I_цепи/I_группы) (у human все цепи в допуске — числа как у doll.tscn);
##   • DollCombat слушает контакты только частей с именами из DollCombat.MONITORED (Hand_L, Foot_R…) — у деталей «Foot_3», «Hand_C»
##     (по базовому имени, как Damage.body_mult_of) и у бьющих деталей STRIKER_KINDS («Chain_E» с шаром булавы) тот же монитор
##     включается здесь, когда DollCombat появляется ребёнком (Match.register).
##   • цепь (kind chain) — свободный шарнир с лимитами CHAIN_LIMITS; fixed-деталь с началом координат в Socket (детали оружия)
##     сливается с настоящим центром масс (центр объёмов форм, как AUTO у Jolt).
class_name ModularDoll
extends Doll

const DEFAULT_BLUEPRINT := "res://data/body/blueprints/human.tres"
## Лимиты сустава по группе (градусы, левая сторона, наружу = +, от направления якоря) — копия таблицы tools/build_doll_scene.gd
## (там она внутри _build_and_save): держать совпадающими, tests/body_probe сверяет human с doll.tscn. meta limit_deg якоря перекрывает.
const JOINT_LIMITS := {
	"Neck": Vector2(-40, 40), "Shoulder": Vector2(-25, 170), "Elbow": Vector2(0, 140), "Wrist": Vector2(-35, 35),
	"Hip": Vector2(-30, 120), "Knee": Vector2(-5, 120), "Ankle": Vector2(-25, 25),
}
## Допуск |I_цепи / I_группы − 1|, в котором демпфирование мышцы остаётся как у Doll (human: отличия ≤ 4 %).
const INERTIA_TOLERANCE := 0.15
## Сустав, где с любой стороны цепь (kind chain): «свободный шарнир» кистеня (BODY_CRAFT.md §1) — лимиты шире таблицы групп
## (у Ankle ±25°), если якорь не задал свои (meta limit_deg).
const CHAIN_LIMITS := Vector2(-160, 160)
## Виды деталей, которые бьют: их тела получают монитор контактов DollCombat, даже если имени нет в DollCombat.MONITORED
## (цепь, шар булавы, слитый с цепью, кулак на плече).
const STRIKER_KINDS := ["hand", "foot", "chain", "weapon_head", "handle"]
const MIRROR_X := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))

@export var blueprint: BodyBlueprint
## Фиксированная тяга Ядра (CONCEPT_V2 §7): false — как у Doll (сила ∝ массе, разгон у всех одинаковый).
@export var fixed_thrust := true
## Масса, при которой тяга совпадает с обычной куклой; ≤ 0 — масса куклы v3 по Tuning.MASS (40 кг).
@export var thrust_ref_mass := -1.0

## uid детали -> имя тела (fixed-деталь — имя тела-хозяина).
var uid_body: Dictionary = {}
## uid детали -> имя сустава, которым она крепится к родителю.
var uid_joint: Dictionary = {}
## Ошибки validate() чертежа, если он не собрался (тогда собран human).
var build_errors: PackedStringArray = []
## Имя тела -> Transform3D в кукле сразу после сборки (до позы) — для проб.
var assembly: Dictionary = {}
var _bp_pose: Dictionary = {}          # имя сустава -> measured-градусы (поза покоя чертежа)
var _chain_inertia: Dictionary = {}    # имя сустава -> кг·м², инерция дистальной цепи вокруг оси сустава (сборка, по прямой)
var _striker: Dictionary = {}          # имя тела -> true: бьющая деталь (STRIKER_KINDS), монитор контактов в _hook_combat


func _ready() -> void:
	_build()
	var snap := spawn_in_pose
	spawn_in_pose = false   # Doll._ready поставил бы Tuning.POSE с зеркалом по «_R» — у чертежа свои углы (ниже)
	super._ready()
	spawn_in_pose = snap
	set_pose(_bp_pose)
	if snap:
		_snap_pose(SPAWN_POSE_GROUPS)
	child_entered_tree.connect(_on_child_entered)
	for c in get_children():
		if c is DollCombat:
			_hook_combat(c)


## Поза покоя чертежа (а не Tuning.POSE).
func reset_pose(blend_s: float = 0.0) -> void:
	set_pose(_bp_pose, blend_s)


## Масса, для которой считается фиксированная тяга (Н = MOVE_FORCE_PER_KG × эта масса).
func thrust_mass() -> float:
	if thrust_ref_mass > 0.0:
		return thrust_ref_mass
	# = Tuning.total_mass(); методы автолоада не компилируются, когда builder (-s) грузит этот скрипт
	var m: Dictionary = Tuning.MASS
	return float(m["Head"]) + float(m["Torso"]) + 2.0 * (float(m["UpperArm"]) + float(m["LowerArm"]) + float(m["Hand"])
		+ float(m["UpperLeg"]) + float(m["LowerLeg"]) + float(m["Foot"]))


## Имена тел, которыми управляет рука мышью (blueprint.control).
func control_part_names() -> PackedStringArray:
	var out: PackedStringArray = []
	for u in blueprint.control:
		if uid_body.has(u):
			out.append(String(uid_body[u]))
	return out


func energy_used() -> int:
	return blueprint.energy_used() if blueprint != null else 0


func _physics_process(delta: float) -> void:
	var t: Variant = get("_time")
	if not fixed_thrust or is_broken() or t == null or float(t) + delta < knockback_until:
		super._physics_process(delta)   # в окне полёта Doll._cap_flight_speed читает total_mass как настоящую массу
		return
	var real := total_mass
	total_mass = thrust_mass()
	super._physics_process(delta)
	total_mass = real


## Спавн сразу в позе чертежа (как Doll.spawn_in_pose, группы по порядку: проксимальные раньше). Отличие от Doll._snap_to_pose:
## центр поворота — точка сустава на ТЕКУЩЕМ родительском теле (по кадру сборки), а не узел сустава. Узел остаётся на месте сборки,
## и у Doll после поворота плеча на 85° локоть поворачивается вокруг старой точки — предплечье отрывается от плеча на 7 см (у пауков и
## длинной руки до 0.2 м), Jolt стягивает сустав на первых шагах рывком (tests/body_probe: human_vs_doll.doll_spawn_joint_gap_m).
func _snap_pose(groups: Array) -> void:
	var pairs: Variant = get("_muscle_pairs")
	if not pairs is Array:
		return
	for g in groups:
		for e in pairs:
			if e[MP_GROUP] != g:
				continue
			var a: RigidBody3D = e[0]
			var b: RigidBody3D = e[1]
			var cur := wrapf(b.global_rotation.z - a.global_rotation.z, -PI, PI)
			var delta := wrapf(float(e[MP_REST]) - cur, -PI, PI)
			if absf(delta) < 1e-4:
				continue
			var local: Vector3 = (assembly[String(a.name)] as Transform3D).affine_inverse() * (joints[e[MP_NAME]] as Node3D).position
			var pivot := a.global_transform * local
			var rot := Basis(Vector3(0, 0, 1), delta)
			for body in _distal(b, pairs):
				var rb := body as RigidBody3D
				var tr := rb.global_transform
				rb.global_transform = Transform3D(rot * tr.basis, pivot + rot * (tr.origin - pivot))


## Тело b и всё ниже него по суставам.
static func _distal(b: RigidBody3D, pairs: Array) -> Array:
	var out: Array = [b]
	var i := 0
	while i < out.size():
		for e in pairs:
			if e[0] == out[i] and not out.has(e[1]):
				out.append(e[1])
		i += 1
	return out


## Doll: c = 2ζ√(k·I_группы). Здесь — по инерции настоящей цепи, если она вне допуска (см. шапку).
func _update_pair_gains() -> void:
	super._update_pair_gains()
	var uc: Variant = get("_uniform_c")
	if uc != null and float(uc) >= 0.0:
		return
	var pairs: Variant = get("_muscle_pairs")
	if not pairs is Array:
		return
	for e in pairs:
		var g := String(e[MP_GROUP])
		var ig := float((Tuning.MUSCLE_GROUPS[g] as Dictionary)["inertia"])
		var ic := float(_chain_inertia.get(String(e[MP_NAME]), ig))
		if ig > 0.0 and absf(ic / ig - 1.0) > INERTIA_TOLERANCE:
			e[MP_C] = float(e[MP_C]) * sqrt(ic / ig)


# --- сборка ---

func _build() -> void:
	if blueprint == null:
		blueprint = load(DEFAULT_BLUEPRINT) as BodyBlueprint
	build_errors = blueprint.validate()
	if not build_errors.is_empty():
		push_error("ModularDoll «%s»: чертёж «%s» не собирается, собираю human:\n  • %s" % [name, blueprint.id, "\n  • ".join(build_errors)])
		blueprint = load(DEFAULT_BLUEPRINT) as BodyBlueprint
	var info := {}          # uid -> {def, xf (кадр детали в кукле), mirror, anchors, body (хозяин), body_xf}
	var bodies: Array[RigidBody3D] = []
	var todo: Array = []    # суставы: {name, group, pos, a, b, limits, mirror, rest}
	for n in blueprint.sorted_nodes():
		var uid := String(n["uid"])
		var def := BodyBlueprint.part_def(String(n["part"]))
		var inst := def.scene.instantiate() as RigidBody3D
		var parent := String(n.get("parent", ""))
		var mirror := false
		var a: Dictionary = {}
		var a_xf := Transform3D.IDENTITY
		if parent != "":
			var p: Dictionary = info[parent]
			a = (p["anchors"] as Dictionary)[String(n["anchor"])]
			a_xf = (p["xf"] as Transform3D) * (a["xf"] as Transform3D)
			mirror = bool(p["mirror"]) != bool(a["mirror"])
		_mirror_part(inst, mirror)
		var sock := inst.get_node_or_null("Socket") as Node3D
		var xf := Transform3D.IDENTITY
		if parent != "":
			xf = a_xf * (sock.transform if sock != null else Transform3D.IDENTITY).affine_inverse()
		var anchors := {}
		for c in inst.get_children():
			if c is Marker3D and String(c.name).begins_with("Anchor_"):
				anchors[String(c.name)] = BodyBlueprint.anchor_info(c as Marker3D)
		var entry := {"def": def, "xf": xf, "mirror": mirror, "anchors": anchors, "body": inst, "body_xf": xf}
		info[uid] = entry
		if def.attach == "fixed" and parent != "":
			var host: RigidBody3D = info[parent]["body"]
			entry["body"] = host
			entry["body_xf"] = info[parent]["body_xf"]
			_merge_into(host, entry["body_xf"], inst, xf, def.mass, uid)
			uid_body[uid] = String(host.name)
			if STRIKER_KINDS.has(def.kind):
				_striker[String(host.name)] = true
			continue
		inst.name = blueprint.body_name_of(uid)
		inst.mass = def.mass
		inst.transform = xf
		bodies.append(inst)
		uid_body[uid] = String(inst.name)
		if STRIKER_KINDS.has(def.kind):
			_striker[String(inst.name)] = true
		if parent == "":
			continue
		var g := blueprint.joint_group_of(uid)
		var rel: float
		if n.has("rest_deg"):
			rel = float(n["rest_deg"])
		elif bool(a["rest_from_pose"]) and Tuning.POSE.has(g):
			rel = float(Tuning.POSE[g])
		else:
			rel = float(a["rest_deg"])
		var host_p: RigidBody3D = info[parent]["body"]
		var a0 := rad_to_deg(_rot_z(xf.basis) - _rot_z((info[parent]["body_xf"] as Transform3D).basis))
		var jn := blueprint.joint_name_of(uid)
		uid_joint[uid] = jn
		todo.append({
			"name": jn, "group": g, "pos": a_xf.origin, "a": host_p, "b": inst, "mirror": mirror,
			"limits": _limits_for(a, g, def, info[parent]["def"]),
		})
		_bp_pose[jn] = wrapf(a0 + (-rel if mirror else rel), -180.0, 180.0)

	# на пол: нижняя точка форм — y = 0
	var min_y := INF
	for b in bodies:
		for c in b.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
				var h := _shape_half((c as CollisionShape3D).shape)
				var w: AABB = (b.transform * (c as Node3D).transform) * AABB(-h, h * 2.0)
				min_y = minf(min_y, w.position.y)
	var shift := Vector3(0.0, -min_y if min_y < INF else 0.0, 0.0)
	for b in bodies:
		b.transform.origin += shift
		assembly[String(b.name)] = b.transform
		add_child(b)
	for jd in todo:
		jd["pos"] = (jd["pos"] as Vector3) + shift
		_chain_inertia[jd["name"]] = _inertia_about(jd["b"], jd["pos"], todo)
		add_child(_make_joint(jd))


## Лимиты сустава: meta limit_deg якоря, иначе у цепи — CHAIN_LIMITS, иначе таблица групп (= doll.tscn).
static func _limits_for(a: Dictionary, group: String, child: PartDef, parent: PartDef) -> Vector2:
	if a.has("limit_deg"):
		return a["limit_deg"]
	if child.kind == "chain" or parent.kind == "chain":
		return CHAIN_LIMITS
	return JOINT_LIMITS.get(group, Vector2(-45, 45))


## Generic6DOFJoint3D как tools/build_doll_scene.gd `_joint` (лимиты: намерение [lo, hi] левой стороны → Jolt [−hi, −lo],
## правой → [lo, hi], см. _lim там). Пути к телам ставятся до add_child: кадры сустава считаются один раз при входе в дерево.
func _make_joint(jd: Dictionary) -> Generic6DOFJoint3D:
	var g := String(jd["group"])
	var ff := float((Tuning.MUSCLE_GROUPS[g] as Dictionary)["friction_factor"])
	var j := Generic6DOFJoint3D.new()
	j.name = String(jd["name"])
	j.position = jd["pos"]
	j.exclude_nodes_from_collision = true
	for ax in ["x", "y", "z"]:
		j.set("linear_limit_%s/enabled" % ax, true)
		j.set("linear_limit_%s/upper_distance" % ax, 0.0)
		j.set("linear_limit_%s/lower_distance" % ax, 0.0)
	for ax in ["x", "y"]:
		j.set("angular_limit_%s/enabled" % ax, true)
		j.set("angular_limit_%s/upper_angle" % ax, 0.0)
		j.set("angular_limit_%s/lower_angle" % ax, 0.0)
	var lim: Vector2 = jd["limits"]
	var l := Vector2(lim.x, lim.y) if bool(jd["mirror"]) else Vector2(-lim.y, -lim.x)
	j.set("angular_limit_z/enabled", true)
	j.set("angular_limit_z/lower_angle", deg_to_rad(l.x))
	j.set("angular_limit_z/upper_angle", deg_to_rad(l.y))
	var f: float = Tuning.JOINT_FRICTION * ff
	j.set("angular_motor_z/enabled", f > 0.0)
	j.set("angular_motor_z/target_velocity", 0.0)
	j.set("angular_motor_z/force_limit", f)
	j.set_meta("friction_factor", ff)
	j.set_meta("chain_inertia", _chain_inertia.get(j.name, 0.0))
	j.node_a = NodePath("../" + String((jd["a"] as Node).name))
	j.node_b = NodePath("../" + String((jd["b"] as Node).name))
	return j


## Отражение детали по X для правой стороны: маркеры и формы — M·T·M (кадр без отражения), меш — Mesh_R (правый GLB) или M·T.
func _mirror_part(inst: RigidBody3D, on: bool) -> void:
	var mesh_r := inst.get_node_or_null("Mesh_R") as Node3D
	if not on:
		if mesh_r != null:
			inst.remove_child(mesh_r)
			mesh_r.free()
		return
	var mesh := inst.get_node_or_null("Mesh") as Node3D
	if mesh_r != null:
		if mesh != null:
			inst.remove_child(mesh)
			mesh.free()
		mesh_r.name = "Mesh"
		mesh_r.visible = true
		mesh_r.transform = _mirrored(mesh_r.transform)
	elif mesh != null:
		mesh.transform = Transform3D(MIRROR_X, Vector3.ZERO) * mesh.transform
	for c in inst.get_children():
		if c is Marker3D or c is CollisionShape3D:
			(c as Node3D).transform = _mirrored((c as Node3D).transform)


static func _mirrored(t: Transform3D) -> Transform3D:
	return Transform3D(MIRROR_X * t.basis * MIRROR_X, MIRROR_X * t.origin)


## fixed-деталь: формы, меши и маркеры переезжают в тело-хозяина (host_xf — его кадр в кукле), масса складывается, центр масс —
## взвешенный по массам (CUSTOM: AUTO у Jolt считал бы его по объёму форм).
func _merge_into(host: RigidBody3D, host_xf: Transform3D, part: RigidBody3D, part_xf: Transform3D, mass: float, uid: String) -> void:
	var rel := host_xf.affine_inverse() * part_xf
	var host_com := _com_local(host)   # до переезда форм: центр масс хозяина по его собственным формам
	for c in part.get_children():
		if c is Node3D:
			part.remove_child(c)
			c.owner = null   # владелец — корень сцены детали, она сейчас освобождается
			(c as Node3D).transform = rel * (c as Node3D).transform
			c.name = "%s_%s" % [c.name, uid]
			host.add_child(c)
	var m0 := host.mass
	var c0 := host_com
	var c1 := rel * _com_local(part)
	host.mass = m0 + mass
	host.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	host.center_of_mass = (c0 * m0 + c1 * mass) / maxf(m0 + mass, 1e-6)
	part.free()


## Инерция вокруг оси Z через pivot: тело b и всё дистальное по суставам todo; своя инерция тела — бокс по габариту форм.
func _inertia_about(b: RigidBody3D, pivot: Vector3, todo: Array) -> float:
	var chain: Array = [b]
	var i := 0
	while i < chain.size():
		for jd in todo:
			if jd["a"] == chain[i] and not chain.has(jd["b"]):
				chain.append(jd["b"])
		i += 1
	var total := 0.0
	for body in chain:
		var rb := body as RigidBody3D
		var com := rb.transform * _com_local(rb)
		var d := Vector2(com.x - pivot.x, com.y - pivot.y)
		var ext := _local_extent(rb)
		total += rb.mass * (d.length_squared() + (ext.x * ext.x + ext.y * ext.y) / 12.0)
	return total


## Центр масс тела в его осях: CUSTOM — как задан, AUTO — центр объёмов форм (Jolt считает массу по формам при равной плотности;
## у деталей куклы v3 форма в начале координат → 0, у деталей оружия начало — в Socket, форма ниже).
static func _com_local(rb: RigidBody3D) -> Vector3:
	if rb.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM:
		return rb.center_of_mass
	var acc := Vector3.ZERO
	var vol := 0.0
	for c in rb.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
			var v := _shape_volume((c as CollisionShape3D).shape)
			acc += (c as Node3D).position * v
			vol += v
	return acc / vol if vol > 0.0 else Vector3.ZERO


static func _shape_volume(s: Shape3D) -> float:
	if s is CapsuleShape3D:
		var c := s as CapsuleShape3D
		return PI * c.radius * c.radius * maxf(c.height - 2.0 * c.radius, 0.0) + 4.0 / 3.0 * PI * pow(c.radius, 3.0)
	if s is SphereShape3D:
		return 4.0 / 3.0 * PI * pow((s as SphereShape3D).radius, 3.0)
	if s is CylinderShape3D:
		var cy := s as CylinderShape3D
		return PI * cy.radius * cy.radius * cy.height
	var h := _shape_half(s)
	return 8.0 * h.x * h.y * h.z


## Габарит форм тела в его локальных осях (м).
static func _local_extent(rb: RigidBody3D) -> Vector3:
	var box := AABB()
	var first := true
	for c in rb.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
			var h := _shape_half((c as CollisionShape3D).shape)
			var w: AABB = (c as Node3D).transform * AABB(-h, h * 2.0)
			box = w if first else box.merge(w)
			first = false
	return box.size


static func _shape_half(s: Shape3D) -> Vector3:
	if s is BoxShape3D:
		return (s as BoxShape3D).size * 0.5
	if s is CapsuleShape3D:
		var c := s as CapsuleShape3D
		return Vector3(c.radius, maxf(c.height * 0.5, c.radius), c.radius)
	if s is SphereShape3D:
		return Vector3.ONE * (s as SphereShape3D).radius
	if s is CylinderShape3D:
		var cy := s as CylinderShape3D
		return Vector3(cy.radius, cy.height * 0.5, cy.radius)
	if s is ConvexPolygonShape3D:
		var pts := (s as ConvexPolygonShape3D).points
		var m := Vector3.ZERO
		for p in pts:
			m = Vector3(maxf(m.x, absf(p.x)), maxf(m.y, absf(p.y)), maxf(m.z, absf(p.z)))
		return m
	return Vector3.ONE * 0.05


static func _rot_z(b: Basis) -> float:
	return atan2(b.x.y, b.x.x)


# --- DollCombat: монитор контактов у деталей с «чужими» суффиксами ---

func _on_child_entered(n: Node) -> void:
	if n is DollCombat:
		if n.is_node_ready():
			_hook_combat(n)
		else:
			n.ready.connect(_hook_combat.bind(n), CONNECT_ONE_SHOT)


## Нужен ли части монитор контактов DollCombat: базовое имя (без «_X») есть в DollCombat.MONITORED или деталь бьющая (STRIKER_KINDS).
func combat_monitored(part_name: String) -> bool:
	for pn in DollCombat.MONITORED:
		if base_name(String(pn)) == base_name(part_name):
			return true
	return _striker.has(part_name)


## Части из combat_monitored() получают тот же монитор, что Hand_L / Foot_R у Doll.
func _hook_combat(c: Node) -> void:
	var mon: Variant = c.get("_monitored")
	if not mon is Array or not c.has_method("_on_part_contact"):
		push_warning("ModularDoll: у DollCombat нет _monitored/_on_part_contact — детали вне DollCombat.MONITORED без монитора ударов")
		return
	for b in parts.values():
		var rb := b as RigidBody3D
		if (mon as Array).has(rb) or not combat_monitored(String(rb.name)):
			continue
		rb.contact_monitor = true
		rb.max_contacts_reported = maxi(rb.max_contacts_reported, DollCombat.MAX_CONTACTS)
		rb.body_entered.connect(Callable(c, "_on_part_contact").bind(rb))
		(mon as Array).append(rb)


## «Hand_L» → «Hand», «Foot_3» → «Foot» (как Damage.body_mult_of: режется суффикс длиной ≤ 1 символа).
static func base_name(part_name: String) -> String:
	var us := part_name.rfind("_")
	if us > 0 and part_name.length() - us <= 2:
		return part_name.substr(0, us)
	return part_name
