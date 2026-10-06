## Ящик головоломок (docs/plan-demo/PUZZLE.md «Ящики»): куб с ребром, массой, своим множителем гравитации и классом веса для руки
## из Tuning.PUZZLE_CRATES[kind] (light 10 кг, box15 15 кг, medium 35, duo 60 — «вдвоём», iron 90 — «чугунный»). Не ломается (в отличие
## от Breakable-ящиков арен: головоломка не должна стать нерешаемой), не замерзает якорем (PropHeft) — его двигают лифт, гравитация
## вбок и тяга кукол. Класс веса — meta "heft" (ArmAssist: лёгкий приваривается и бросается, средний тянется пружиной, тяжёлый не
## бросается). Вид — модель ящика арен (Crate.glb, целый), чугунный — железом, «вдвоём» — с жёлтыми полосами; на лицевой стороне —
## масса («60 кг ×2» — нужны две руки).
class_name PuzzleCrate
extends RigidBody3D

const MODEL := "res://assets/models/props/Crate.glb"
const MODEL_SIZE := 0.7          # ребро модели, м (origin — середина низа)
const IRON := "res://assets/materials/kit/Iron.tres"
const TINT := {"light": Color(1, 1, 1), "box15": Color(0.92, 0.85, 0.72), "medium": Color(0.8, 0.62, 0.45),
	"duo": Color(1.0, 0.86, 0.45), "iron": Color(0.7, 0.72, 0.75)}

@export_enum("light", "box15", "medium", "duo", "iron") var kind := "light"

var size := 0.6
var heft := 0


func _init() -> void:
	axis_lock_linear_z = true
	axis_lock_angular_x = true
	axis_lock_angular_y = true
	continuous_cd = true
	linear_damp = 0.2
	angular_damp = 0.8
	can_sleep = true


func _ready() -> void:
	var e: Dictionary = Tuning.PUZZLE_CRATES.get(kind, Tuning.PUZZLE_CRATES["light"])
	mass = float(e["mass"])
	size = float(e["size"])
	gravity_scale = float(e["g_scale"])
	heft = int(e["heft"])
	set_meta(PropHeft.META, heft)
	if heft != PropHeft.Heft.LIGHT:
		set_meta(ArmAssist.SLIP_META, Tuning.PUZZLE_CRATE_SLIP_M)   # несут вдвоём: пружины тянутся дальше 0.45 м (PuzzleCarry)
	# тяжёлые («вдвоём», чугунный) не кувыркаются: вдвоём за два угла несут ровно, с полки при гравитации вбок съезжают, а не катятся
	axis_lock_angular_z = bool(e.get("no_spin", false))
	add_to_group("puzzle_crates")
	var pm := PhysicsMaterial.new()
	pm.friction = 0.55 if kind != "iron" else 0.3
	pm.bounce = 0.05
	physics_material_override = pm
	if get_node_or_null("Shape") == null:
		PuzzlePart.box_shape(self, "Shape", Vector3.ONE * size, Vector3.ZERO)
	if get_node_or_null("Mesh") == null:
		_build_visual()


func _build_visual() -> void:
	var holder := Node3D.new()
	holder.name = "Mesh"
	add_child(holder)
	var ps := load(MODEL) as PackedScene if ResourceLoader.exists(MODEL) else null
	if ps != null:
		var m := ps.instantiate() as Node3D
		m.scale = Vector3.ONE * (size / MODEL_SIZE)
		m.position = Vector3(0, -size * 0.5, 0)
		holder.add_child(m)
		for n in ["Damaged", "Destroyed"]:
			var c := m.find_child(n, true, false) as Node3D
			if c != null:
				c.visible = false
		var mat: Material = null
		if kind == "iron" and ResourceLoader.exists(IRON):
			mat = load(IRON) as Material
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if mat != null:
				g.material_override = mat
			elif kind != "light":
				var ov := StandardMaterial3D.new()   # подкраска: умножение цвета модели
				ov.albedo_color = TINT[kind]
				ov.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				ov.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				ov.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
				g.material_overlay = ov
	else:
		PuzzlePart.box_mesh(holder, "Box", Vector3.ONE * size, Vector3.ZERO, PuzzlePart.flat_material(TINT[kind], 0.2, 0.7))
	if kind == "duo":
		var hz := PuzzlePart.glow_material(Color(1.0, 0.75, 0.1), 0.35)
		for s in [-1.0, 1.0]:
			var b := PuzzlePart.box_mesh(holder, "Band", Vector3(size + 0.02, 0.09, size + 0.02), Vector3(0, s * size * 0.3, 0), hz)
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if kind != "light":
		var txt := tr("%d кг") % roundi(mass)
		if kind == "duo":
			txt = tr("%d кг ×2") % roundi(mass)
		var l := PuzzlePart.label(holder, "Kg", txt, Vector3(0, 0, size * 0.5 + 0.03), 34 if size < 0.9 else 44, Color(1.0, 0.97, 0.9))
		l.pixel_size = 0.004
