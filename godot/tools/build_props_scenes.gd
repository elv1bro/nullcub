## Builder компонентных сцен пропсов (docs/plan-demo/ART_DIRECTION.md §2, лист R17): собирает деревья узлов из моделей
## assets/models/props/*.glb (tools/blender/props.py) и сохраняет res://scenes/props/*.tscn. Скрипты сцен содержат
## только поведение (breakable.gd, rope_bridge.gd, banner.gd, gate.gd, torch.gd, stone_static.gd).
## Запуск: godot --headless --path godot --import && godot --headless --path godot -s res://tools/build_props_scenes.gd
## Повторный запуск перезаписывает сцены (правки, которые нужно сохранить, вносятся сюда).
##
## Сцены (origin — центр основания, если не сказано иначе):
##   barrel.tscn / crate.tscn   RigidBody3D (breakable.gd: массы/HP из констант скрипта, XY-плоскость, CCD, контакты)
##                              ├ Shape (цилиндр ⌀0.62×0.8 / куб 0.7) └ Mesh = Barrel.glb / Crate.glb (Intact/Damaged/Destroyed)
##   rope_bridge_4m/6m.tscn     Node3D (rope_bridge.gd): Post_A/Post_B StaticBody3D — по два столба Post.glb на z=±0.6
##                              (настил проходит между ними), Planks/Plank_i RigidBody3D 4 кг, Joints/Joint_k (лин. лимиты 0,
##                              угловой Z ±25°), Ropes/Rope_<L|R>_k, Handrails. Столбы стоят на x=0 и x=length;
##                              6-метровый мост поднимается к концу B на 1.35 м (левая палуба 2.65 → каменный мост 4.0)
##   banner.tscn                Node3D (banner.gd, color) + Banner.glb
##   gate.tscn                  Node3D (gate.gd, open): Arch StaticBody3D (коллизия пилонов) + Door_L/Door_R StaticBody3D
##   wall_segment.tscn, stone_platform_2m/4m/5m.tscn, stone_block.tscn   StaticBody3D (stone_static.gd, solid) + Shape + Mesh
##   torch.tscn                 Node3D (torch.gd) + Mesh + OmniLight3D "Light" (тёплый, energy 2, range 6)
##   cage.tscn                  Node3D, origin = точка подвеса: Anchor Marker3D, Link_0/Link_1 (2 кг), Body (30 кг) + Cage.glb,
##                              Joint_0 (мир→Link_0), Joint_1, Joint_2 — Generic6DOFJoint3D, угловой Z ±75°
##   wooden_deck.tscn           StaticBody3D 4 м на 4 столбах Post_2m (верх настила на +2.25); wooden_deck_3m.tscn — 3 м без столбов
##   gallows.tscn               StaticBody3D: столб Post_2m + балка Beam_3m на +2.06, повёрнута на −30° (конец к камере),
##                              Beam/Hook Marker3D — точка подвеса клетки (1.4 м по балке), коллизия только у балки
extends SceneTree

const DIR := "res://scenes/props/"
const GLB := "res://assets/models/props/%s.glb"
const BREAKABLE := preload("res://scenes/props/breakable.gd")

var _phys: PhysicsMaterial
var _root: Node


func _init() -> void:
	_phys = PhysicsMaterial.new()
	_phys.friction = 0.8
	_phys.bounce = 0.1
	_breakable("barrel", "Barrel", "propbarrel01")
	_breakable("crate", "Crate", "propcrate001")
	_rope_bridge(4.0, 0.0, "rope_bridge_4m", "propbridge4m")
	_rope_bridge(6.0, 1.35, "rope_bridge_6m", "propbridge6m")
	_banner()
	_gate()
	_stone("wall_segment", "Wall_Segment", Vector3(2.0, 3.0, 0.8), "propwallseg1")
	_stone("stone_platform_2m", "Stone_Platform_2m", Vector3(2.0, 0.4, 2.0), "propplat2m01")
	_stone("stone_platform_4m", "Stone_Platform_4m", Vector3(4.0, 0.4, 2.0), "propplat4m01")
	_stone("stone_platform_5m", "Stone_Platform_5m", Vector3(5.0, 0.4, 2.0), "propplat5m01")
	_stone("stone_block", "Stone_Block", Vector3(0.5, 0.5, 0.5), "propblock001")
	_torch()
	_cage()
	_deck(4.0, true, "wooden_deck", "propdeck4m01")
	_deck(3.0, false, "wooden_deck_3m", "propdeck3m01")
	_gallows()
	print("props scenes saved to ", DIR)
	quit(0)


# ---------------------------------------------------------------- helpers
func _glb(name: String) -> Node3D:
	var ps: PackedScene = load(GLB % name)
	if ps == null:
		push_error("missing " + (GLB % name) + " — run Blender props.py and godot --import")
		quit(1)
		return Node3D.new()
	var n: Node3D = ps.instantiate()
	n.name = "Mesh"
	return n


func _set_owner(n: Node, root: Node) -> void:
	for c in n.get_children():
		if c.owner == null:
			c.owner = root
		_set_owner(c, root)


func _save(root: Node, file: String, uid: String) -> void:
	_set_owner(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		push_error("pack failed %s: %d" % [file, err])
		quit(1)
		return
	var path := DIR + file + ".tscn"
	err = ResourceSaver.save(ps, path)
	if err != OK:
		push_error("save failed %s: %d" % [path, err])
		quit(1)
		return
	ResourceUID.set_id(ResourceUID.text_to_id("uid://" + uid), path) if ResourceUID.has_id(ResourceUID.text_to_id("uid://" + uid)) else ResourceUID.add_id(ResourceUID.text_to_id("uid://" + uid), path)
	ResourceSaver.set_uid(path, ResourceUID.text_to_id("uid://" + uid))
	print("saved ", path, " (", _count(root), " nodes)")
	root.free()


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


func _shape(parent: Node, name: String, shape: Shape3D, pos := Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.name = name
	cs.shape = shape
	cs.position = pos
	parent.add_child(cs)
	return cs


func _box(size: Vector3) -> BoxShape3D:
	var b := BoxShape3D.new()
	b.size = size
	return b


func _cyl(r: float, h: float) -> CylinderShape3D:
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	return c


func _rigid(name: String, mass: float) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.name = name
	b.mass = mass
	b.axis_lock_linear_z = true
	b.axis_lock_angular_x = true
	b.axis_lock_angular_y = true
	b.continuous_cd = true
	b.linear_damp = 0.2
	b.angular_damp = 0.5
	b.physics_material_override = _phys
	return b


## 6DOF-шарнир: линейные оси заперты, угловые X/Y заперты, угловой Z в [lo, hi] градусов; node_a пустой = мир.
func _joint(parent: Node, name: String, a: Node, b: Node, pos: Vector3, lo: float, hi: float) -> Generic6DOFJoint3D:
	var j := Generic6DOFJoint3D.new()
	j.name = name
	j.position = pos
	parent.add_child(j)
	if a != null:
		j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)
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
	j.set("angular_limit_z/lower_angle", deg_to_rad(lo))
	j.set("angular_limit_z/upper_angle", deg_to_rad(hi))
	return j


## Статичный отрезок каната между a и b (модель 0.3 м вдоль +X).
func _rope_static(parent: Node, name: String, a: Vector3, b: Vector3) -> void:
	var seg := _glb("Rope_Segment")
	seg.name = name
	parent.add_child(seg)
	var d := b - a
	var len := d.length()
	var x := d / len
	var up := Vector3.UP if absf(x.dot(Vector3.UP)) < 0.99 else Vector3.BACK
	var z := x.cross(up).normalized()
	var y := z.cross(x)
	seg.transform = Transform3D(Basis(x * (len / 0.3), y, z), a)


# ---------------------------------------------------------------- scenes
func _breakable(kind: String, glb: String, uid: String) -> void:
	var b := _rigid(glb, BREAKABLE.MASS[kind])
	b.set_script(BREAKABLE)
	b.set("kind", kind)
	b.set("hp", BREAKABLE.HP[kind])
	b.contact_monitor = true
	b.max_contacts_reported = BREAKABLE.MIN_CONTACTS
	if kind == "barrel":
		_shape(b, "Shape", _cyl(0.31, 0.8), Vector3(0, 0.4, 0))
	else:
		_shape(b, "Shape", _box(Vector3(0.7, 0.7, 0.7)), Vector3(0, 0.35, 0))
	b.add_child(_glb(glb))
	_save(b, kind, uid)


func _rope_bridge(length: float, rise: float, file: String, uid: String) -> void:
	var root := Node3D.new()
	root.name = "RopeBridge"
	root.set_script(load(DIR + "rope_bridge.gd"))
	var post_r := 0.15
	var post_h := 1.6
	var post_z := 0.6            # столбы по обе стороны настила (доска 0.9 → ±0.45)
	var ya := 0.06               # нижние канаты выходят у основания столба: первая доска вровень с палубой
	var margin := 0.1            # зазор между осью столбов и первой/последней доской
	root.set("anchor_y_a", ya)
	root.set("anchor_y_b", ya + rise)
	root.set("anchor_z", post_z - 0.17)
	for e in [["Post_A", Vector3.ZERO], ["Post_B", Vector3(length, rise, 0)]]:
		var p := StaticBody3D.new()
		p.name = e[0]
		p.position = e[1]
		p.physics_material_override = _phys
		root.add_child(p)
		for side in [["L", -post_z], ["R", post_z]]:
			_shape(p, "Shape_" + side[0], _cyl(post_r, post_h), Vector3(0, post_h * 0.5, side[1]))
			var m := _glb("Post")
			m.name = "Post_" + side[0]
			m.position = Vector3(0, 0, side[1])
			p.add_child(m)
	var planks := Node3D.new()
	planks.name = "Planks"
	root.add_child(planks)
	var joints := Node3D.new()
	joints.name = "Joints"
	root.add_child(joints)
	var ropes := Node3D.new()
	ropes.name = "Ropes"
	root.add_child(ropes)
	var span := length - 2.0 * margin
	var n := int(round(span / 0.3))
	var pitch := span / n
	var slope := atan2(rise, length)
	var list: Array = []
	for i in n:
		var x := margin + pitch * (i + 0.5)
		var p := _rigid("Plank_%d" % i, 4.0)
		p.position = Vector3(x, ya + rise * x / length, 0)
		p.rotation.z = slope
		p.linear_damp = 0.5
		p.angular_damp = 1.0
		p.can_sleep = false
		planks.add_child(p)
		_shape(p, "Shape", _box(Vector3(0.25, 0.05, 0.9)))
		var m := _glb("Plank")
		m.position = Vector3(0, -0.025, 0)
		p.add_child(m)
		list.append(p)
	for k in n + 1:
		var a: Node = root.get_node("Post_A") if k == 0 else list[k - 1]
		var b: Node = root.get_node("Post_B") if k == n else list[k]
		var xk := margin + pitch * k
		_joint(joints, "Joint_%d" % k, a, b, Vector3(xk, ya + rise * xk / length, 0), -25.0, 25.0)
	for side in ["L", "R"]:
		for k in n + 1:
			var seg := _glb("Rope_Segment")
			seg.name = "Rope_%s_%d" % [side, k]
			ropes.add_child(seg)
	# поручни: статичная цепная линия от верхней намотки столбов A к столбам B (чуть снаружи концов досок)
	var rails := Node3D.new()
	rails.name = "Handrails"
	root.add_child(rails)
	var y_rail := 1.18 + 0.1
	var segs := 14
	for side in ["L", "R"]:
		var zs := 0.5 * (-1.0 if side == "L" else 1.0)
		var prev := Vector3(0.0, y_rail, zs)
		for k in range(1, segs + 1):
			var t := float(k) / segs
			var sag := 0.35 * sin(PI * t)
			var pt := Vector3(length * t, y_rail + rise * t - sag, zs)
			_rope_static(rails, "Rail_%s_%d" % [side, k], prev, pt)
			prev = pt
	_save(root, file, uid)


func _banner() -> void:
	var root := Node3D.new()
	root.name = "Banner"
	root.set_script(load(DIR + "banner.gd"))
	root.add_child(_glb("Banner"))
	_save(root, "banner", "propbanner01")


func _gate() -> void:
	var root := Node3D.new()
	root.name = "Gate"
	root.set_script(load(DIR + "gate.gd"))
	var arch := StaticBody3D.new()
	arch.name = "Arch"
	arch.physics_material_override = _phys
	root.add_child(arch)
	_shape(arch, "Shape_L", _box(Vector3(1.0, 3.2, 0.8)), Vector3(-2.0, 1.6, 0))
	_shape(arch, "Shape_R", _box(Vector3(1.0, 3.2, 0.8)), Vector3(2.0, 1.6, 0))
	arch.add_child(_glb("Gate_Arch"))
	for e in [["Door_L", -1.5, 0.75, "Gate_Door_L"], ["Door_R", 1.5, -0.75, "Gate_Door_R"]]:
		var d := StaticBody3D.new()
		d.name = e[0]
		d.position = Vector3(e[1], 0, 0)
		d.physics_material_override = _phys
		root.add_child(d)
		_shape(d, "Shape", _box(Vector3(1.5, 2.9, 0.08)), Vector3(e[2], 1.45, 0))
		d.add_child(_glb(e[3]))
	_save(root, "gate", "propgate0001")


func _stone(file: String, glb: String, size: Vector3, uid: String) -> void:
	var root := StaticBody3D.new()
	root.name = glb
	root.set_script(load(DIR + "stone_static.gd"))
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.05
	root.physics_material_override = pm
	_shape(root, "Shape", _box(size), Vector3(0, size.y * 0.5, 0))
	root.add_child(_glb(glb))
	_save(root, file, uid)


func _torch() -> void:
	var root := Node3D.new()
	root.name = "Torch"
	root.set_script(load(DIR + "torch.gd"))
	root.add_child(_glb("Torch"))
	var l := OmniLight3D.new()
	l.name = "Light"
	l.light_color = Color(1.0, 0.70, 0.38)
	l.light_energy = 2.0
	l.omni_range = 6.0
	l.omni_attenuation = 1.5
	l.position = Vector3(0, 1.15, 0.2)
	root.add_child(l)
	_save(root, "torch", "proptorch001")


func _cage() -> void:
	var root := Node3D.new()
	root.name = "Cage"
	var anchor := Marker3D.new()
	anchor.name = "Anchor"
	root.add_child(anchor)
	var link_len := 0.5
	var prev: Node = null
	var y := 0.0
	for i in 2:
		var link := _rigid("Link_%d" % i, 2.0)
		link.position = Vector3(0, y - link_len * 0.5, 0)
		root.add_child(link)
		var cap := CapsuleShape3D.new()
		cap.radius = 0.04
		cap.height = link_len
		_shape(link, "Shape", cap)
		for k in 3:
			var m := _glb("Chain_Link")
			m.name = "Link%d" % k
			m.position = Vector3(0, -link_len * 0.5 + 0.17 * k - 0.01, 0)
			m.rotation_degrees.y = 90.0 if k % 2 == 1 else 0.0
			link.add_child(m)
		_joint(root, "Joint_%d" % i, prev, link, Vector3(0, y, 0), -75.0, 75.0)
		prev = link
		y -= link_len
	var body := _rigid("Body", 30.0)
	var hook_h := 1.86
	body.position = Vector3(0, y - hook_h, 0)
	root.add_child(body)
	_shape(body, "Shape", _cyl(0.4, 1.4), Vector3(0, 0.7, 0))
	body.add_child(_glb("Cage"))
	_joint(root, "Joint_2", prev, body, Vector3(0, y, 0), -75.0, 75.0)
	_save(root, "cage", "propcage0001")


## Виселица для клетки: столб 2 м у задней кромки палубы, балка 3 м на +2.06 повёрнута на −30° вокруг Y, чтобы её
## конец вышел вперёд, в плоскость боя; Beam/Hook — точка подвеса (cage.tscn ставится в неё). Коллизия — только балка.
func _gallows() -> void:
	var root := StaticBody3D.new()
	root.name = "Gallows"
	root.physics_material_override = _phys
	var post := _glb("Post_2m")
	post.name = "Post"
	root.add_child(post)
	var beam := Node3D.new()
	beam.name = "Beam"
	beam.position = Vector3(0, 2.06, 0)
	beam.rotation_degrees = Vector3(0, -30.0, 0)
	root.add_child(beam)
	var bm := _glb("Beam_3m")
	bm.position = Vector3(0.4, 0, 0)
	beam.add_child(bm)
	var hook := Marker3D.new()
	hook.name = "Hook"
	hook.position = Vector3(1.4, 0, 0)
	beam.add_child(hook)
	var cs := _shape(root, "Shape", _box(Vector3(3.0, 0.2, 0.2)))
	cs.transform = beam.transform * Transform3D(Basis.IDENTITY, Vector3(0.4, 0.1, 0))
	_save(root, "gallows", "propgallows1")


func _deck(length: float, posts: bool, file: String, uid: String) -> void:
	var root := StaticBody3D.new()
	root.name = "WoodenDeck"
	root.set_script(load(DIR + "stone_static.gd"))
	root.physics_material_override = _phys
	var post_h := 2.0 if posts else 0.0
	_shape(root, "Shape", _box(Vector3(length, 0.25, 1.8)), Vector3(0, post_h + 0.125, 0))
	var m := _glb("Deck_%dm" % int(length))
	m.position = Vector3(0, post_h, 0)
	root.add_child(m)
	if posts:
		var holder := Node3D.new()
		holder.name = "Posts"
		root.add_child(holder)
		var i := 0
		for x in [-(length * 0.5 - 0.3), length * 0.5 - 0.3]:
			for z in [-0.65, 0.65]:
				var p := _glb("Post_2m")
				p.name = "Post_%d" % i
				p.position = Vector3(x, 0, z)
				holder.add_child(p)
				i += 1
	_save(root, file, uid)
