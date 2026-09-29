## Builder сцен механизмов и лута Свалки (биом 1, лист 04 «Machines & Hazards», kit-02 «Interactive elements»): собирает деревья
## узлов из моделей assets/models/scrap/machines/*.glb (tools/blender/scrap_machines.py) и сохраняет
## res://scenes/props/scrap/machine_<name>.tscn, deco_chain_long.tscn, loot_<id>.tscn. Поведение — скрипты
## scenes/props/scrap/machines/*.gd (цикл OFF → WARNING → ACTIVE → COOLDOWN — scrap_machine.gd) и scenes/props/scrap/loot_item.gd.
## Запуск: godot --headless --path godot --import && godot --headless --path godot -s res://tools/build_scrap_machines_scenes.gd
## Повторный запуск перезаписывает сцены (правки, которые нужно сохранить, вносятся сюда). Проверка — tests/scrap_machines_probe.tscn.
##
## Оси Godot: x вбок, y вверх, +z к камере; куклы и пропсы в плоскости z = 0. Рабочие части механизмов (диск магнита, патрубок,
## ползун, траверса и наковальня пресса) — на плоскости боя, с коллизией; станины, балки, трубы, цепи — без коллизий.
##
##   machine_magnet.tscn       Node3D "Magnet" (magnet_machine.gd), origin — точка подвеса маятника:
##                             ├ Gantry (балка-рельс, декор) └ Pivot (поворот z) ├ Chain_0..3 (4 × 2 м цепи, CHAIN_LEN)
##                                                                                └ Head AnimatableBody3D (y −CHAIN_LEN): Shape цилиндр
##                                                                                  r 0.78 × 0.55 (y −0.87), Model, Pole (y −1.17),
##                                                                                  LampLight, Sparks, Sfx
##   machine_steam_vent.tscn   Node3D "SteamVent" (steam_vent_machine.gd), origin — пол: Body StaticBody3D (цилиндр r 0.42 × 0.38),
##                             Model, Steam / Leak (GPUParticles3D), LampLight (фонарь на стояке), Sfx
##   machine_press.tscn        Node3D "Press" (press_machine.gd), origin — пол: Frame StaticBody3D (Crown 2.6 × 0.7 × 1.1 на y 5.0…5.7,
##                             Cylinder 0.6 × 0.6 × 0.6 на y 4.4…5.0, Anvil 2.5 × 0.12 × 1.24) + Model; Ram AnimatableBody3D
##                             (y rest 3.3; Shape 2.0 × 0.8 × 1.2) + Model; LampLight, Dust, Sparks, Sfx
##   machine_chute.tscn        Node3D "Chute" (chute_machine.gd), origin — центр раструба: Model, Mouth, Dust, LampLight, Sfx
##   deco_chain_long.tscn      Node3D с Model (цепь 2 м вниз от origin) — подвесы островков
##   loot_<id>.tscn            RigidBody3D (loot_item.gd, material_id) в плоскости XY: Shape бокс по силуэту × LOOT_SCALE, Model;
##                             масса — как у детали крафта (data/body/parts: mod_nails 0.4, mod_iron_plate 1.5, chain_segment 0.8,
##                             handle_short 0.6)
extends SceneTree

const DIR := "res://scenes/props/scrap/"
const GLB := "res://assets/models/scrap/machines/%s.glb"
const MOTE_TEX := "res://assets/textures/fx/mote.png"
const CHAIN_LEN := 8.0
const LOOT_SCALE := 1.3
## id → [glb, масса кг, центр бокса (x, y), размер бокса (x, y)] — по габаритам моделей (печать scrap_machines.py)
const LOOT := {
	"nails": ["Loot_Nails", 0.4, Vector2(0.01, -0.015), Vector2(0.42, 0.19)],
	"plate": ["Loot_Plate", 1.5, Vector2(0.0, 0.015), Vector2(0.44, 0.35)],
	"chain": ["Loot_Chain", 0.8, Vector2(0.0, -0.01), Vector2(0.46, 0.16)],
	"handle": ["Loot_Handle", 0.6, Vector2(0.015, 0.0), Vector2(0.53, 0.09)],
}

var _iron: PhysicsMaterial
var _failed := false


func _init() -> void:
	_iron = PhysicsMaterial.new()
	_iron.friction = 0.65
	_iron.bounce = 0.12
	_magnet()
	_steam_vent()
	_press()
	_chute()
	_chain()
	for id in LOOT:
		_loot(id)
	print("scrap machines: scenes saved to ", DIR)
	quit(1 if _failed else 0)


# ---------------------------------------------------------------- helpers
func _glb(name: String, node_name := "Model") -> Node3D:
	var ps: PackedScene = load(GLB % name) if ResourceLoader.exists(GLB % name) else null
	if ps == null:
		push_error("missing " + (GLB % name) + " — run Blender tools/blender/scrap_machines.py and godot --import")
		_failed = true
		return Node3D.new()
	var n: Node3D = ps.instantiate()
	n.name = node_name
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
		_failed = true
		root.free()
		return
	var path := DIR + file + ".tscn"
	err = ResourceSaver.save(ps, path)
	if err != OK:
		push_error("save failed %s: %d" % [path, err])
		_failed = true
		root.free()
		return
	var id := ResourceUID.text_to_id("uid://" + uid)
	if ResourceUID.has_id(id):
		ResourceUID.set_id(id, path)
	else:
		ResourceUID.add_id(id, path)
	ResourceSaver.set_uid(path, id)
	print("saved ", path)
	root.free()


func _shape(parent: Node, name: String, shape: Shape3D, pos: Vector3) -> CollisionShape3D:
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


func _light(parent: Node, pos: Vector3, colour: Color, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = "LampLight"
	l.position = pos
	l.light_color = colour
	l.light_energy = 0.0
	l.light_indirect_energy = 0.0
	l.light_specular = 0.3
	l.omni_range = rng
	l.omni_attenuation = 1.2
	l.shadow_enabled = false
	l.visible = false
	parent.add_child(l)
	return l


func _sfx(parent: Node, pos: Vector3) -> void:
	var s := AudioStreamPlayer3D.new()
	s.name = "Sfx"
	s.position = pos
	s.unit_size = 8.0
	s.max_distance = 60.0
	parent.add_child(s)


func _mote(colour: Color, additive: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = colour
	mat.albedo_texture = load(MOTE_TEX)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.disable_receive_shadows = true
	return mat


func _ramp(offsets: Array, colours: Array) -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array(offsets)
	grad.colors = PackedColorArray(colours)
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	return ramp


func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for p in points:
		c.add_point(p)
	var t := CurveTexture.new()
	t.curve = c
	return t


## Частицы: opts — amount, lifetime, dir, spread, v (Vector2 min/max), gravity, box (Vector3 extents) | sphere (радиус),
## size (квад, м), ramp [[offsets], [colours]], additive, one_shot, explosiveness, damping (Vector2), scale_curve [Vector2…], aabb.
func _particles(parent: Node, name: String, pos: Vector3, o: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = name
	p.position = pos
	p.amount = int(o.get("amount", 24))
	p.lifetime = float(o.get("lifetime", 1.0))
	p.one_shot = bool(o.get("one_shot", false))
	p.explosiveness = float(o.get("explosiveness", 0.0))
	p.randomness = 0.4
	p.emitting = false
	p.visibility_aabb = o.get("aabb", AABB(Vector3(-3, -3, -2), Vector3(6, 8, 4)))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.lifetime_randomness = 0.3
	if o.has("sphere"):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = float(o["sphere"])
	else:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = o.get("box", Vector3(0.2, 0.05, 0.2))
	pm.direction = o.get("dir", Vector3.UP)
	pm.spread = float(o.get("spread", 15.0))
	var v: Vector2 = o.get("v", Vector2(1, 2))
	pm.initial_velocity_min = v.x
	pm.initial_velocity_max = v.y
	pm.gravity = o.get("gravity", Vector3.ZERO)
	var dm: Vector2 = o.get("damping", Vector2(0.2, 0.5))
	pm.damping_min = dm.x
	pm.damping_max = dm.y
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	if o.has("scale_curve"):
		pm.scale_curve = _curve(o["scale_curve"])
	var r: Array = o.get("ramp", [[0.0, 1.0], [Color(1, 1, 1, 1), Color(1, 1, 1, 0)]])
	pm.color_ramp = _ramp(r[0], r[1])
	p.process_material = pm
	var quad := QuadMesh.new()
	var sz := float(o.get("size", 0.2))
	quad.size = Vector2(sz, sz)
	quad.material = _mote(Color(1, 1, 1, 1), bool(o.get("additive", false)))
	p.draw_pass_1 = quad
	parent.add_child(p)
	return p


# ---------------------------------------------------------------- scenes
func _magnet() -> void:
	var root := Node3D.new()
	root.name = "Magnet"
	root.set_script(load("res://scenes/props/scrap/machines/magnet_machine.gd"))
	root.set("lamp_warn_color", Color(1.0, 0.6, 0.15))
	root.set("lamp_active_color", Color(1.0, 0.35, 0.12))
	root.set("coil_color", Color(1.0, 0.52, 0.2))
	root.set("off_s", 4.0)
	root.set("warning_s", 1.0)
	root.set("active_s", 4.0)
	root.set("cooldown_s", 2.0)
	root.add_child(_glb("Gantry_Rail", "Gantry"))
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	root.add_child(pivot)
	var n := int(round(CHAIN_LEN / 2.0))
	for i in n:
		var c := _glb("Chain_Long", "Chain_%d" % i)
		c.position = Vector3(0, -2.0 * i, 0)
		pivot.add_child(c)
	var head := AnimatableBody3D.new()
	head.name = "Head"
	head.position = Vector3(0, -CHAIN_LEN, 0)
	head.sync_to_physics = false
	head.physics_material_override = _iron
	pivot.add_child(head)
	_shape(head, "Shape", _cyl(0.78, 0.55), Vector3(0, -0.87, 0))
	head.add_child(_glb("Magnet_Head"))
	var pole := Marker3D.new()
	pole.name = "Pole"
	pole.position = Vector3(0, -1.17, 0)
	head.add_child(pole)
	_light(head, Vector3(0, -1.7, 0.4), Color(1.0, 0.4, 0.15), 4.0)   # свет снизу — на то, что магнит держит
	var sp := _particles(head, "Sparks", Vector3(0, -1.15, 0), {
		"amount": 28, "lifetime": 0.55, "sphere": 0.7, "dir": Vector3(0, -1, 0), "spread": 70.0, "v": Vector2(0.4, 1.6),
		"gravity": Vector3(0, -3.0, 0), "size": 0.06, "additive": true, "damping": Vector2(0.5, 1.0),
		"ramp": [[0.0, 0.2, 1.0], [Color(2.5, 2.2, 1.6, 1.0), Color(2.4, 1.2, 0.4, 1.0), Color(1.0, 0.3, 0.05, 0.0)]],
		"aabb": AABB(Vector3(-2, -3, -2), Vector3(4, 4, 4))})
	sp.emitting = false
	_sfx(head, Vector3(0, -0.8, 0))
	# свет и звук едут с диском
	root.set("lamp_light_path", NodePath("Pivot/Head/LampLight"))
	root.set("sfx_path", NodePath("Pivot/Head/Sfx"))
	_save(root, "machine_magnet", "scrmachmag01")


func _steam_vent() -> void:
	var root := Node3D.new()
	root.name = "SteamVent"
	root.set_script(load("res://scenes/props/scrap/machines/steam_vent_machine.gd"))
	root.set("lamp_warn_color", Color(1.0, 0.7, 0.2))
	root.set("lamp_active_color", Color(1.0, 0.95, 0.85))
	root.set("off_s", 5.0)
	root.set("warning_s", 1.0)
	root.set("active_s", 1.6)
	root.set("cooldown_s", 1.5)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.physics_material_override = _iron
	root.add_child(body)
	_shape(body, "Shape", _cyl(0.42, 0.38), Vector3(0, 0.19, 0))
	root.add_child(_glb("Steam_Vent"))
	_particles(root, "Steam", Vector3(0, 0.45, 0), {
		"amount": 90, "lifetime": 1.5, "box": Vector3(0.3, 0.05, 0.25), "dir": Vector3.UP, "spread": 7.0,
		"v": Vector2(4.0, 6.0), "gravity": Vector3(0, -0.6, 0), "size": 0.55, "damping": Vector2(0.4, 0.9),
		"scale_curve": [Vector2(0.0, 0.35), Vector2(0.5, 1.0), Vector2(1.0, 1.9)],
		"ramp": [[0.0, 0.12, 0.6, 1.0], [Color(1, 1, 1, 0.0), Color(0.95, 0.95, 0.97, 0.55), Color(0.9, 0.9, 0.95, 0.3), Color(0.9, 0.9, 0.95, 0.0)]],
		"aabb": AABB(Vector3(-2.5, -0.5, -2), Vector3(5, 10, 4))})
	_particles(root, "Leak", Vector3(0, 0.4, 0), {
		"amount": 18, "lifetime": 0.8, "box": Vector3(0.25, 0.02, 0.2), "dir": Vector3.UP, "spread": 20.0,
		"v": Vector2(0.8, 1.6), "size": 0.25, "damping": Vector2(0.5, 1.0),
		"scale_curve": [Vector2(0.0, 0.5), Vector2(1.0, 1.4)],
		"ramp": [[0.0, 0.2, 1.0], [Color(1, 1, 1, 0.0), Color(0.95, 0.95, 0.97, 0.4), Color(0.9, 0.9, 0.95, 0.0)]],
		"aabb": AABB(Vector3(-1, -0.5, -1), Vector3(2, 3, 2))})
	_light(root, Vector3(-0.5, 2.1, -0.7), Color(1.0, 0.7, 0.3), 2.5)
	_sfx(root, Vector3(0, 0.6, 0))
	_save(root, "machine_steam_vent", "scrmachstm01")


func _press() -> void:
	var root := Node3D.new()
	root.name = "Press"
	root.set_script(load("res://scenes/props/scrap/machines/press_machine.gd"))
	root.set("lamp_warn_color", Color(1.0, 0.15, 0.05))
	root.set("lamp_active_color", Color(1.0, 0.3, 0.08))
	root.set("off_s", 3.5)
	root.set("warning_s", 1.0)
	root.set("active_s", 0.6)
	root.set("cooldown_s", 1.8)
	root.set("lamp_light_energy", 2.5)
	var frame := StaticBody3D.new()
	frame.name = "Frame"
	frame.physics_material_override = _iron
	root.add_child(frame)
	_shape(frame, "Crown", _box(Vector3(2.6, 0.7, 1.1)), Vector3(0, 5.35, 0))
	_shape(frame, "Cylinder", _box(Vector3(0.6, 0.6, 0.6)), Vector3(0, 4.7, 0))
	_shape(frame, "Anvil", _box(Vector3(2.5, 0.12, 1.24)), Vector3(0, 0.06, 0))
	frame.add_child(_glb("Press_Frame"))
	var ram := AnimatableBody3D.new()
	ram.name = "Ram"
	ram.position = Vector3(0, 3.3, 0)
	ram.sync_to_physics = false
	ram.physics_material_override = _iron
	root.add_child(ram)
	_shape(ram, "Shape", _box(Vector3(2.0, 0.8, 1.2)), Vector3(0, 0.4, 0))
	ram.add_child(_glb("Press_Ram"))
	_light(root, Vector3(0, 4.2, 0.9), Color(1.0, 0.2, 0.08), 5.0)
	_particles(root, "Dust", Vector3(0, 0.2, 0.1), {
		"amount": 46, "lifetime": 1.3, "one_shot": true, "explosiveness": 0.95, "box": Vector3(1.1, 0.05, 0.4),
		"dir": Vector3.UP, "spread": 80.0, "v": Vector2(1.5, 3.8), "gravity": Vector3(0, -1.2, 0), "size": 0.45,
		"damping": Vector2(1.5, 2.5), "scale_curve": [Vector2(0.0, 0.5), Vector2(1.0, 1.6)],
		"ramp": [[0.0, 0.1, 1.0], [Color(0.55, 0.42, 0.32, 0.0), Color(0.55, 0.42, 0.32, 0.6), Color(0.45, 0.36, 0.3, 0.0)]],
		"aabb": AABB(Vector3(-4, -1, -2), Vector3(8, 5, 4))})
	_particles(root, "Sparks", Vector3(0, 0.15, 0.35), {
		"amount": 34, "lifetime": 0.6, "one_shot": true, "explosiveness": 1.0, "box": Vector3(0.9, 0.02, 0.3),
		"dir": Vector3.UP, "spread": 75.0, "v": Vector2(3.0, 7.0), "gravity": Vector3(0, -6.0, 0), "size": 0.07,
		"additive": true, "damping": Vector2(0.2, 0.6),
		"ramp": [[0.0, 0.3, 1.0], [Color(3.0, 2.2, 1.0, 1.0), Color(2.6, 1.0, 0.25, 1.0), Color(1.0, 0.25, 0.05, 0.0)]],
		"aabb": AABB(Vector3(-4, -1, -2), Vector3(8, 6, 4))})
	_sfx(root, Vector3(0, 1.0, 0))
	_save(root, "machine_press", "scrmachprs01")


func _chute() -> void:
	var root := Node3D.new()
	root.name = "Chute"
	root.set_script(load("res://scenes/props/scrap/machines/chute_machine.gd"))
	root.set("lamp_warn_color", Color(1.0, 0.65, 0.12))
	root.set("lamp_active_color", Color(1.0, 0.5, 0.1))
	root.set("off_s", 11.0)
	root.set("warning_s", 1.2)
	root.set("active_s", 1.2)
	root.set("cooldown_s", 2.0)
	root.add_child(_glb("Garbage_Chute"))
	var mouth := Marker3D.new()
	mouth.name = "Mouth"
	root.add_child(mouth)
	_particles(root, "Dust", Vector3(0.15, -0.2, 0.2), {
		"amount": 30, "lifetime": 1.3, "sphere": 0.45, "dir": Vector3(0.55, -0.83, 0), "spread": 25.0,
		"v": Vector2(0.6, 1.5), "gravity": Vector3(0, -1.0, 0), "size": 0.32, "damping": Vector2(0.3, 0.8),
		"scale_curve": [Vector2(0.0, 0.5), Vector2(1.0, 1.5)],
		"ramp": [[0.0, 0.15, 1.0], [Color(0.5, 0.36, 0.26, 0.0), Color(0.5, 0.36, 0.26, 0.55), Color(0.4, 0.3, 0.24, 0.0)]],
		"aabb": AABB(Vector3(-2, -4, -2), Vector3(5, 5, 4))})
	_light(root, Vector3(-0.1, 0.75, 0.9), Color(1.0, 0.55, 0.15), 3.0)
	_sfx(root, Vector3(0, 0, 0))
	_save(root, "machine_chute", "scrmachcht01")


func _chain() -> void:
	var root := Node3D.new()
	root.name = "ChainLong"
	root.add_child(_glb("Chain_Long"))
	_save(root, "deco_chain_long", "scrdecochn01")


func _loot(id: String) -> void:
	var e: Array = LOOT[id]
	var b := RigidBody3D.new()
	b.name = String(e[0]).replace("_", "")
	b.set_script(load("res://scenes/props/scrap/loot_item.gd"))
	b.set("material_id", id)
	b.mass = float(e[1])
	b.axis_lock_linear_z = true
	b.axis_lock_angular_x = true
	b.axis_lock_angular_y = true
	b.continuous_cd = true
	b.linear_damp = 0.3
	b.angular_damp = 0.8
	b.physics_material_override = _iron
	var c: Vector2 = e[2]
	var s: Vector2 = e[3]
	_shape(b, "Shape", _box(Vector3(s.x * LOOT_SCALE, maxf(s.y * LOOT_SCALE, 0.12), 0.3)), Vector3(c.x, c.y, 0) * LOOT_SCALE)
	var m := _glb(String(e[0]))
	m.scale = Vector3.ONE * LOOT_SCALE
	b.add_child(m)
	_save(b, "loot_" + id, "scrloot%s01" % id.substr(0, 3))
