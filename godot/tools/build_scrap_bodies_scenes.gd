## Builder сцен THE SCRAP, лист 01 «Scrap & Bodies» (№001–020, docs/refs/biomes/01-scrap/LIST.md) и библиотеки кусков хлама:
## собирает деревья узлов из моделей assets/models/scrap/{bodies,bits}/*.glb (tools/blender/scrap_bodies.py) и форм коллизии
## из physics.json рядом с ними (их считает тот же Blender-скрипт: выпуклые оболочки R-тел и призмы-срезы по профилю верха
## S-куч), сохраняет res://scenes/props/scrap/bodies_<name>.tscn и res://scenes/props/scrap/bit_<name>.tscn (<name> — имя
## glb в нижнем регистре). Скриптов поведения у сцен нет. Повторный запуск перезаписывает сцены (UID стабильные — из имени).
## Запуск: godot --headless --path godot --import && godot --headless --path godot -s res://tools/build_scrap_bodies_scenes.gd
##
## Оси и origin: как в glb — метры, Y вверх, лицо к камере +Z; у ассетов origin — центр основания (y = 0 — пол; холмы куч
## уходят юбкой на 5 см под пол), у кусков — центр габарита. Куклы живут в плоскости z = 0, поэтому коллизия S-ассетов —
## призмы глубиной z ∈ [−0.6, 0.6] (пересекают z = 0), низ y = −0.05, верх — профиль кучи (медиана лучей на z ∈ [−0.15, 0.15]).
##
## Сцены:
##   bit_<name>.tscn        RigidBody3D <Name> (плоскость XY: axis_lock linear Z / angular X, Y; CCD; damp 0.2 / 0.5)
##                          ├ Shape  CollisionShape3D — ConvexPolygonShape3D (≤ 40 точек оболочки из bits/physics.json)
##                          └ Mesh   bits/<Name>.glb
##   bodies_<name>.tscn  S  StaticBody3D <Name> ├ Shape_0…N (ConvexPolygonShape3D, 8 точек — призма среза) └ Mesh
##                      R  RigidBody3D <Name> (как куски; CCD только если наибольший габарит ≤ CCD_MAX) ├ Shape └ Mesh
##                      SR Node3D <Name> ├ Heap StaticBody3D (как S) └ Loose Node3D — экземпляры bit_*.tscn на верху кучи,
##                         sleeping = true: лежат, пока их не толкнут (кукла, оружие, другой кусок)
##                      SL StaticBody3D (как S) + Glow OmniLight3D (тёплый, слабый, без теней) + LootPoint Marker3D (сундучок)
##
## Массы — константы ниже (tuning.gd правит другая сессия; перенести туда, когда куски получат поведение).
extends SceneTree

const DIR := "res://scenes/props/scrap/"
const BODY_GLB := "res://assets/models/scrap/bodies/%s.glb"
const BIT_GLB := "res://assets/models/scrap/bits/%s.glb"
const BODY_PHYS := "res://assets/models/scrap/bodies/physics.json"
const BIT_PHYS := "res://assets/models/scrap/bits/physics.json"
const CCD_MAX := 0.6            # м: R-ассеты с наибольшим габаритом не больше — с CCD (мелкие); куски bits — всегда

# Массы кусков, кг. Ориентир — части куклы (tuning.gd MASS: голова 4, торс 12, плечо 2, бедро 4, кисть 0.5) и оружие
# (молот 6, меч 1.5): старые куклы легче (пустые, сухое дерево). Самые мелкие (гайка, гвоздь) не легче 0.1 кг — иначе
# отношение масс с куклой > 400:1 и контакт Jolt «дрожит».
const BIT_MASS := {
	"Doll_Head_Sad": 3.0, "Doll_Head_Scared": 3.0, "Doll_Head_Cracked": 2.6,
	"Doll_Limb_Upper": 2.5, "Doll_Limb_Lower": 2.0, "Doll_Hand": 0.5, "Doll_Foot": 1.0, "Doll_Torso_Shell": 8.0,
	"Scrap_Board": 3.0, "Rivet_Plate": 4.0,
	"Gear_Small": 1.0, "Gear_Medium": 4.0, "Gear_Large": 12.0,
	"Chain_Link": 0.4, "Chain_Segment": 3.0,
	"Bolt": 0.3, "Nut": 0.15, "Nail": 0.1, "Pipe_Piece": 2.5,
	"Sword_Broken": 1.2, "Helmet": 2.5, "Shield_Crown": 5.0,
	"Hammer_Old": 5.0, "Axe_Old": 2.5, "Mace_Old": 3.5,
}
# Массы R-ассетов №009–016, кг: пустой торс ×1.3 (торс куклы 12 кг, без Core и с вырванной грудью), железная оболочка Core
# с ядром, связка из 10 конечностей (по ~1.8 кг), ведро гвоздей, ящик болтов (тяжёлый — толкается, но не летает).
const BODY_MASS := {
	"Empty_Torso": 10.0, "Dead_Core_Shell": 14.0, "Wooden_Limb_Bundle": 18.0, "Nail_Bucket": 16.0, "Bolt_Nut_Box": 24.0,
}
const METAL_BITS := ["Rivet_Plate", "Gear_Small", "Gear_Medium", "Gear_Large", "Chain_Link", "Chain_Segment", "Bolt", "Nut",
	"Nail", "Pipe_Piece", "Sword_Broken", "Helmet", "Shield_Crown", "Hammer_Old", "Axe_Old", "Mace_Old"]
const METAL_BODIES := ["Dead_Core_Shell", "Metal_Parts_Heap", "Gear_Heap", "Chain_Heap", "Bolt_Nut_Box", "Broken_Weapons_Pile",
	"Broken_Armor_Heap"]
# свечение Mystery_Scrap_Heap: тёплое, слабое, без теней (эмиссия задней стенки пещеры — в glb)
const GLOW_COLOR := Color(1.0, 0.62, 0.30)
const GLOW_ENERGY := 1.4
const GLOW_RANGE := 2.6

var _wood: PhysicsMaterial
var _iron: PhysicsMaterial
var _heap: PhysicsMaterial
var _bits: Dictionary
var _bodies: Dictionary
var _fail := false


func _init() -> void:
	_wood = _pm(0.9, 0.05)
	_iron = _pm(0.6, 0.15)
	_heap = _pm(0.95, 0.02)
	_bits = _json(BIT_PHYS)
	_bodies = _json(BODY_PHYS)
	if _bits.is_empty() or _bodies.is_empty():
		push_error("нет physics.json — запусти Blender tools/blender/scrap_bodies.py и godot --import")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var names := _bits.keys()
	names.sort()
	for n in names:
		_bit(n)
	names = _bodies.keys()
	names.sort()
	for n in names:
		_body(n)
	print("scrap sheet-01 scenes saved to ", DIR, " (", _bits.size(), " bits, ", _bodies.size(), " bodies)")
	quit(1 if _fail else 0)


# ---------------------------------------------------------------- helpers
func _pm(friction: float, bounce: float) -> PhysicsMaterial:
	var m := PhysicsMaterial.new()
	m.friction = friction
	m.bounce = bounce
	return m


func _json(path: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string(path)
	if txt.is_empty():
		return {}
	var d = JSON.parse_string(txt)
	return d if d is Dictionary else {}


func _glb(path: String) -> Node3D:
	var ps: PackedScene = load(path)
	if ps == null:
		push_error("missing " + path + " — run Blender scrap_bodies.py and godot --import")
		_fail = true
		return Node3D.new()
	var n: Node3D = ps.instantiate()
	n.name = "Mesh"
	return n


func _pts(arr: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in arr:
		out.append(Vector3(p[0], p[1], p[2]))
	return out


func _convex(parent: Node, name: String, points: Array) -> CollisionShape3D:
	var shape := ConvexPolygonShape3D.new()
	shape.points = _pts(points)
	var cs := CollisionShape3D.new()
	cs.name = name
	cs.shape = shape
	parent.add_child(cs)
	return cs


func _rigid(name: String, mass: float, ccd: bool, pm: PhysicsMaterial) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.name = name
	b.mass = mass
	b.axis_lock_linear_z = true
	b.axis_lock_angular_x = true
	b.axis_lock_angular_y = true
	b.continuous_cd = ccd
	b.linear_damp = 0.2
	b.angular_damp = 0.5
	b.physics_material_override = pm
	return b


func _static(name: String, pm: PhysicsMaterial, slices: Array) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = name
	b.physics_material_override = pm
	for i in slices.size():
		_convex(b, "Shape_%d" % i, slices[i])
	return b


func _set_owner(n: Node, root: Node) -> void:
	for c in n.get_children():
		if c.owner == null:
			c.owner = root
		_set_owner(c, root)


func _uid_for(file: String) -> String:
	return "uid://sc" + file.md5_text().substr(0, 10)


func _save(root: Node, file: String) -> void:
	_set_owner(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		push_error("pack failed %s: %d" % [file, err])
		_fail = true
		root.free()
		return
	var path := DIR + file + ".tscn"
	err = ResourceSaver.save(ps, path)
	if err != OK:
		push_error("save failed %s: %d" % [path, err])
		_fail = true
		root.free()
		return
	var id := ResourceUID.text_to_id(_uid_for(file))
	if ResourceUID.has_id(id):
		ResourceUID.set_id(id, path)
	else:
		ResourceUID.add_id(id, path)
	ResourceSaver.set_uid(path, id)
	print("saved ", path, " (", _count(root), " nodes)")
	root.free()


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


# ---------------------------------------------------------------- scenes
func _bit(name: String) -> void:
	var info: Dictionary = _bits[name]
	var pm := _iron if name in METAL_BITS else _wood
	var b := _rigid(name, float(BIT_MASS.get(name, 1.0)), true, pm)
	_convex(b, "Shape", info["hull"])   # тонкие по Z оболочки уже растянуты до 5 см (scrap_bodies.py MIN_HULL_DEPTH)
	b.add_child(_glb(BIT_GLB % name))
	_save(b, "bit_" + name.to_lower())


func _body(name: String) -> void:
	var info: Dictionary = _bodies[name]
	var kind: String = info["kind"]
	var file := "bodies_" + name.to_lower()
	var pm := _iron if name in METAL_BODIES else _heap
	match kind:
		"R":
			var size: Array = info["size"]
			var biggest := maxf(float(size[0]), maxf(float(size[1]), float(size[2])))
			var r := _rigid(name, float(BODY_MASS.get(name, 10.0)), biggest <= CCD_MAX, _iron if name in METAL_BODIES else _wood)
			_convex(r, "Shape", info["hull"])
			r.add_child(_glb(BODY_GLB % name))
			_save(r, file)
		"SR":
			var root := Node3D.new()
			root.name = name
			var heap := _static("Heap", pm, info["slices"])
			heap.add_child(_glb(BODY_GLB % name))
			root.add_child(heap)
			var loose := Node3D.new()
			loose.name = "Loose"
			root.add_child(loose)
			var k := 0
			for l in info.get("loose", []):
				var ps: PackedScene = load(DIR + "bit_" + String(l["bit"]).to_lower() + ".tscn")
				if ps == null:
					push_error("нет сцены куска " + String(l["bit"]))
					_fail = true
					continue
				var inst: RigidBody3D = ps.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)   # в .tscn — только отличия от куска
				inst.name = "%s_%d" % [l["bit"], k]
				inst.position = Vector3(l["pos"][0], l["pos"][1], l["pos"][2])
				inst.quaternion = Quaternion(l["quat"][0], l["quat"][1], l["quat"][2], l["quat"][3]).normalized()
				inst.sleeping = true
				loose.add_child(inst)
				k += 1
			_save(root, file)
		_:
			var s := _static(name, pm, info["slices"])
			s.add_child(_glb(BODY_GLB % name))
			if kind == "SL":
				var lp: Array = info.get("light", [0.0, 0.4, 0.0])
				var light := OmniLight3D.new()
				light.name = "Glow"
				light.position = Vector3(lp[0], lp[1], lp[2])
				light.light_color = GLOW_COLOR
				light.light_energy = GLOW_ENERGY
				light.light_indirect_energy = 0.5
				light.light_volumetric_fog_energy = 0.8
				light.omni_range = GLOW_RANGE
				light.omni_attenuation = 1.6
				light.shadow_enabled = false
				s.add_child(light)
				var tp: Array = info.get("loot", [0.0, 0.15, 0.0])
				var loot := Marker3D.new()
				loot.name = "LootPoint"
				loot.position = Vector3(tp[0], tp[1], tp[2])
				s.add_child(loot)
			_save(s, file)
