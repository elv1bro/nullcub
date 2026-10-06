## «Перегон» (docs/plan-demo/CONVOY.md): общие помощники вида и форм — коробки, цилиндры, материалы кита. Машина (ConvoyCar), груз
## (ConvoyCargo) и сборщик участка (tools/build_convoy_probe.gd) строят себя из примитивов, без своих моделей.
class_name ConvoyGeo
extends RefCounted

const KIT_MAT := "res://assets/materials/kit/%s.tres"

static var _mats: Dictionary = {}


## Материал кита по имени (Iron, Rust, Rubber, Base_Planks, Base_PaintYellow, Glass…); нет файла — однотонный запасной цвет.
static func kit(name: String, fallback := Color(0.6, 0.6, 0.6)) -> Material:
	if _mats.has(name):
		return _mats[name]
	var path := KIT_MAT % name
	var m: Material = null
	if ResourceLoader.exists(path):
		m = load(path) as Material
	if m == null:
		m = flat(fallback)
	_mats[name] = m
	return m


static func flat(c: Color, metallic: float = 0.2, rough: float = 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = rough
	return m


static func glow(c: Color, energy: float = 1.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


## Полупрозрачное стекло (кабина): сквозь него видна голова водителя.
static func glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.75, 0.85, 0.28)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.1
	m.roughness = 0.05
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func box_mesh(parent: Node, n: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	return mi


## Коробка по углам x0..x1, y0..y1 (глубина depth по z, центр по z — z).
static func box_xy(parent: Node, n: String, x0: float, x1: float, y0: float, y1: float, depth: float, mat: Material, z := 0.0) -> MeshInstance3D:
	return box_mesh(parent, n, Vector3(x1 - x0, y1 - y0, depth), Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, z), mat)


static func box_shape(parent: Node, n: String, size: Vector3, pos: Vector3, rot_z := 0.0) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.name = n
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	cs.rotation.z = rot_z
	parent.add_child(cs)
	return cs


static func shape_xy(parent: Node, n: String, x0: float, x1: float, y0: float, y1: float, depth: float) -> CollisionShape3D:
	return box_shape(parent, n, Vector3(x1 - x0, y1 - y0, depth), Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0.0))


## Цилиндр осью вдоль z (колесо, кочка): radius, толщина по z — width.
static func disc_mesh(parent: Node, n: String, radius: float, width: float, pos: Vector3, mat: Material, segments := 28) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = width
	cm.radial_segments = segments
	cm.rings = 1
	cm.material = mat
	mi.mesh = cm
	mi.position = pos
	mi.rotation.x = PI * 0.5
	parent.add_child(mi)
	return mi


static func disc_shape(parent: Node, n: String, radius: float, width: float, pos: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.name = n
	var c := CylinderShape3D.new()
	c.radius = radius
	c.height = width
	cs.shape = c
	cs.position = pos
	cs.rotation.x = PI * 0.5
	parent.add_child(cs)
	return cs


static func label(parent: Node, n: String, text: String, pos: Vector3, px: int = 48, c: Color = Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.name = n
	l.text = text
	l.font_size = px
	l.pixel_size = 0.005
	l.outline_size = 12
	l.outline_modulate = Color(0.02, 0.02, 0.03, 0.9)
	l.modulate = c
	l.shaded = false
	l.double_sided = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # иначе квадрат подписи бросает тень
	l.position = pos
	parent.add_child(l)
	return l
