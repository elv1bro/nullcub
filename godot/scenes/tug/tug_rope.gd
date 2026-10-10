## Канат «Перетягивания» (docs/plan-demo/TUG.md): цепь звеньев RigidBody3D на Generic6DOFJoint3D (как доски rope_bridge.gd), концы
## свободные, лежит на полу зала. Дерево строит сам в build(): Links/Link_i (бокс seg × 2r × 2r, масса TUG_ROPE_MASS_KG / N, материал
## с трением TUG_LINK_FRICTION, в плоскости боя: axis_lock z / angular x, y), Joints/Joint_i между соседями (линейные оси и угловые
## X / Y заперты, угловая Z свободна), Mark — кольцо на стыке половин, Lines — две черты на полу x = ±TUG_LINE_M.
## Половины: звено i < N / 2 — сторона 0 (синие, слева), иначе 1 (красные): meta "side" и meta "grab_team" = "tug_<side>" — ArmAssist
## хватает только звенья со своей Doll.team (чужую половину не схватить). Группа "tug_links".
## reset() — канат снова прямой по центру (скорости 0); shift(dx) — сдвиг целиком (пробы); mark_x() — x метки; max_gap() — наибольший
## зазор на стыках звеньев (проба: цепь не рвётся).
class_name TugRope
extends Node3D

const GROUP := "tug_links"
const MARK_COLOUR := Color(1.0, 0.92, 0.35)

var links: Array = []            # Array[RigidBody3D] по порядку, слева направо
var joints: Array = []
var mark: MeshInstance3D
var seg := 0.5
var radius: float = Tuning.TUG_LINK_RADIUS
var length_m: float = Tuning.TUG_ROPE_M
var line_m: float = Tuning.TUG_LINE_M
var _built := false
var _y0 := 0.0


## Собрать канат: n звеньев общей длиной length на полу (y = 0), метка на стыке половин, черты на ±line.
func build(n: int = Tuning.TUG_ROPE_LINKS, length: float = Tuning.TUG_ROPE_M, mass_kg: float = Tuning.TUG_ROPE_MASS_KG,
		friction: float = Tuning.TUG_LINK_FRICTION, line: float = Tuning.TUG_LINE_M) -> void:
	if _built:
		return
	_built = true
	n = maxi(n, 2)
	if n % 2 == 1:
		n += 1
	length_m = length
	line_m = line
	seg = length / float(n)
	_y0 = radius + 0.01
	var pm := PhysicsMaterial.new()
	pm.friction = friction
	pm.bounce = 0.0
	var holder := Node3D.new()
	holder.name = "Links"
	add_child(holder)
	var jh := Node3D.new()
	jh.name = "Joints"
	add_child(jh)
	var mats := [_link_material(Tuning.TUG_COLORS[0]), _link_material(Tuning.TUG_COLORS[1])]
	for i in n:
		var side := 0 if i < n / 2 else 1
		var b := RigidBody3D.new()
		b.name = "Link_%d" % i
		b.mass = mass_kg / float(n)
		b.axis_lock_linear_z = true
		b.axis_lock_angular_x = true
		b.axis_lock_angular_y = true
		b.continuous_cd = true
		b.linear_damp = 0.1
		b.angular_damp = 0.3
		b.physics_material_override = pm
		b.set_meta("side", side)
		b.set_meta("grab_team", "tug_%d" % side)
		b.set_meta("tug_link", i)
		b.add_to_group(GROUP)
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		var box := BoxShape3D.new()
		box.size = Vector3(seg * 0.96, radius * 2.0, radius * 2.0)
		cs.shape = box
		b.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		var cap := CapsuleMesh.new()
		cap.radius = radius
		cap.height = seg
		cap.radial_segments = 10
		cap.rings = 4
		mi.mesh = cap
		mi.rotation = Vector3(0.0, 0.0, PI * 0.5)   # капсула вдоль Y → вдоль X
		mi.material_override = mats[side]
		b.add_child(mi)
		holder.add_child(b)
		b.global_position = _rest_pos(i)
		links.append(b)
	for i in range(n - 1):
		var j := Generic6DOFJoint3D.new()
		j.name = "Joint_%d" % i
		jh.add_child(j)
		j.global_position = Vector3(-length * 0.5 + seg * float(i + 1), _y0, 0.0)
		j.node_a = j.get_path_to(links[i])
		j.node_b = j.get_path_to(links[i + 1])
		j.exclude_nodes_from_collision = true
		for ax in ["x", "y", "z"]:
			j.set("linear_limit_%s/enabled" % ax, true)
			j.set("linear_limit_%s/upper_distance" % ax, 0.0)
			j.set("linear_limit_%s/lower_distance" % ax, 0.0)
		for ax in ["x", "y"]:
			j.set("angular_limit_%s/enabled" % ax, true)
			j.set("angular_limit_%s/upper_angle" % ax, 0.0)
			j.set("angular_limit_%s/lower_angle" % ax, 0.0)
		j.set("angular_limit_z/enabled", false)
		joints.append(j)
	_build_mark()
	_build_lines()


func _link_material(team: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.48, 0.3).lerp(team, 0.22)
	m.roughness = 0.9
	return m


func _rest_pos(i: int) -> Vector3:
	return Vector3(-length_m * 0.5 + seg * (float(i) + 0.5), _y0, 0.0)


func _build_mark() -> void:
	mark = MeshInstance3D.new()
	mark.name = "Mark"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.16
	ring.outer_radius = 0.24
	ring.rings = 24
	ring.ring_segments = 10
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = MARK_COLOUR
	m.emission_enabled = true
	m.emission = MARK_COLOUR
	m.emission_energy_multiplier = 1.5
	ring.material = m
	mark.mesh = ring
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mark.top_level = true
	add_child(mark)
	_update_mark()


func _build_lines() -> void:
	var holder := Node3D.new()
	holder.name = "Lines"
	add_child(holder)
	for s in 2:
		var mi := MeshInstance3D.new()
		mi.name = "Line_%d" % s
		var box := BoxMesh.new()
		box.size = Vector3(0.1, 0.02, 5.0)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = (Tuning.TUG_COLORS[s] as Color).lightened(0.25)
		m.emission_enabled = true
		m.emission = Tuning.TUG_COLORS[s]
		box.material = m
		mi.mesh = box
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		mi.position = Vector3(line_m * (-1.0 if s == 0 else 1.0), 0.011, 0.0)


func _physics_process(_delta: float) -> void:
	_update_mark()


func _update_mark() -> void:
	if mark == null or links.is_empty():
		return
	var p := mark_pos()
	mark.global_transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), p + Vector3(0.0, 0.0, 0.3))


## Точка метки: стык половин (конец последнего звена левой половины и начало первого правой — среднее).
func mark_pos() -> Vector3:
	var n := links.size()
	if n == 0:
		return global_position
	var a := links[n / 2 - 1] as RigidBody3D
	var b := links[n / 2] as RigidBody3D
	var pa := a.to_global(Vector3(seg * 0.5, 0.0, 0.0))
	var pb := b.to_global(Vector3(-seg * 0.5, 0.0, 0.0))
	var p := (pa + pb) * 0.5
	p.z = 0.0
	return p


func mark_x() -> float:
	return mark_pos().x


func is_link(b: Object) -> bool:
	return b is RigidBody3D and (b as Node).has_meta("tug_link") and links.has(b)


## Сторона звена (0 слева / синие, 1 справа / красные), −1 — не звено.
func side_of(b: Object) -> int:
	if not is_link(b):
		return -1
	return int((b as Node).get_meta("side"))


func side_links(side: int) -> Array:
	var out: Array = []
	for b in links:
		if int((b as Node).get_meta("side")) == side:
			out.append(b)
	return out


## Наибольший зазор между концами соседних звеньев (м): цепь цела, пока он мал.
func max_gap() -> float:
	var worst := 0.0
	for i in range(links.size() - 1):
		var a := links[i] as RigidBody3D
		var b := links[i + 1] as RigidBody3D
		var pa := a.to_global(Vector3(seg * 0.5, 0.0, 0.0))
		var pb := b.to_global(Vector3(-seg * 0.5, 0.0, 0.0))
		worst = maxf(worst, pa.distance_to(pb))
	return worst


func lowest_y() -> float:
	var y := INF
	for b in links:
		y = minf(y, (b as Node3D).global_position.y)
	return y


func highest_y() -> float:
	var y := -INF
	for b in links:
		y = maxf(y, (b as Node3D).global_position.y)
	return y


## Канат снова прямой по центру: звенья на местах сборки, скорости 0.
func reset() -> void:
	for i in links.size():
		_place(links[i] as RigidBody3D, _rest_pos(i))
	_update_mark()


## Сдвиг всего каната на dx (пробы: метка за чертой без кукол).
func shift(dx: float) -> void:
	for b in links:
		var rb := b as RigidBody3D
		_place(rb, rb.global_position + Vector3(dx, 0.0, 0.0), rb.global_transform.basis)
	_update_mark()


func _place(rb: RigidBody3D, p: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	rb.global_transform = Transform3D(basis, p)
	rb.linear_velocity = Vector3.ZERO
	rb.angular_velocity = Vector3.ZERO
	rb.sleeping = false
	rb.reset_physics_interpolation()
