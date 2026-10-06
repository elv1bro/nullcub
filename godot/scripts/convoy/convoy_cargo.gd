## Груз и доски «Перегона» (docs/plan-demo/CONVOY.md). Свободное тело в плоскости боя (z зажата, поворот только вокруг z), не ломается
## (в отличие от Breakable-ящиков арен: счёт груза не должен пропадать от удара), класс веса для руки — meta PropHeft (до 15 кг лёгкий:
## ArmAssist приваривает и бросает; тяжелее — средний: только тащить; доска — всегда средний: держится ровно, см. _ready). Вес — свой множитель (Tuning.CONVOY_CARGO_G_SCALE: легче
## машины — на кочках «всплывает» и вылетает из кузова; доски — CONVOY_PLANK_G_SCALE).
## Вид — модели пропсов Свалки: ящик (Wooden_Crate), бочка (Metal_Barrel), большой ящик (Reinforced_Crate), доска (Wooden_Beam,
## вытянутая). Начало тела — в центре формы.
class_name ConvoyCargo
extends RigidBody3D

const GROUP_CARGO := "convoy_cargo"
const GROUP_PLANK := "convoy_plank"
const MODELS := {
	"crate": "res://assets/models/scrap/props/Wooden_Crate.glb",
	"big": "res://assets/models/scrap/props/Reinforced_Crate.glb",
	"barrel": "res://assets/models/scrap/props/Metal_Barrel.glb",
	"plank": "res://assets/models/scrap/props/Wooden_Beam.glb",
}
## Размер модели (м) — во сколько её масштабировать: ящики — куб 1 м, бочка — r 0.3 × 0.91, балка — 3 × 0.336 × 0.32.
const MODEL_SIZE := {"crate": Vector3.ONE, "big": Vector3.ONE, "barrel": Vector3(0.6, 0.91, 0.6), "plank": Vector3(3.0, 0.336, 0.32)}

@export_enum("crate", "big", "barrel", "plank") var kind := "crate"
## 0 — по Tuning (груз — из CONVOY_CARGO, доска — CONVOY_PLANK_MASS).
@export var cargo_mass := 0.0

var size := Vector3(0.6, 0.6, 0.6)
## Где лежал на старте (рестарт участка возвращает сюда).
var home := Transform3D()
## Доска легла поперёк провала и стала мостом (заморожена намертво; рука её не берёт) — до рестарта участка.
var bridged := false


func _init() -> void:
	axis_lock_linear_z = true
	axis_lock_angular_x = true
	axis_lock_angular_y = true
	continuous_cd = true
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.05
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.5
	can_sleep = false   # отпущенное рукой в воздухе тело не должно «уснуть» на месте; тел всего ~8


func _ready() -> void:
	match kind:
		"crate":
			size = Vector3(0.6, 0.6, 0.6)
		"big":
			size = Vector3(0.8, 0.8, 0.8)
		"barrel":
			size = Vector3(0.6, 0.9, 0.6)
		"plank":
			size = Vector3(Tuning.CONVOY_PLANK_LEN, 0.14, 0.5)
	if kind == "plank":
		mass = cargo_mass if cargo_mass > 0.0 else Tuning.CONVOY_PLANK_MASS
		gravity_scale = Tuning.CONVOY_PLANK_G_SCALE
		add_to_group(GROUP_PLANK)
	else:
		mass = cargo_mass if cargo_mass > 0.0 else 10.0
		gravity_scale = Tuning.CONVOY_CARGO_G_SCALE
		add_to_group(GROUP_CARGO)
	# доска — «средний» класс для руки при любой массе: не приваривается к кисти (иначе крутится вместе с ней), а висит на пружине
	# с удержанием угла (ArmAssist: момент к углу при захвате) — несёшь ровно и кладёшь поперёк провала ровно
	var light := mass <= PropHeft.LIGHT_MAX_KG and kind != "plank"
	set_meta(PropHeft.META, PropHeft.Heft.LIGHT if light else PropHeft.Heft.MEDIUM)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.7 if kind != "barrel" else 0.55
	pm.bounce = 0.05
	physics_material_override = pm
	if get_node_or_null("Shape") == null:
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		if kind == "barrel":
			var c := CylinderShape3D.new()
			c.radius = size.x * 0.5
			c.height = size.y
			cs.shape = c
		else:
			var b := BoxShape3D.new()
			b.size = size
			cs.shape = b
		add_child(cs)
	if get_node_or_null("Mesh") == null:
		_build_visual()
	home = global_transform


func _build_visual() -> void:
	var holder := Node3D.new()
	holder.name = "Mesh"
	add_child(holder)
	var path: String = MODELS.get(kind, "")
	var ps := load(path) as PackedScene if path != "" and ResourceLoader.exists(path) else null
	if ps == null:
		ConvoyGeo.box_mesh(holder, "Box", size, Vector3.ZERO, ConvoyGeo.kit("Base_Planks", Color(0.6, 0.45, 0.3)))
		return
	var m := ps.instantiate() as Node3D
	var ms: Vector3 = MODEL_SIZE.get(kind, Vector3.ONE)
	m.scale = Vector3(size.x / ms.x, size.y / ms.y, size.z / ms.z)
	m.position = Vector3(0.0, -size.y * 0.5, 0.0)
	holder.add_child(m)
	for n in ["Damaged", "Destroyed"]:
		var c := m.find_child(n, true, false) as Node3D
		if c != null:
			c.visible = false


## Доска — мостом: ровно в at, заморожена (FREEZE_MODE_STATIC — для машины как дорога); false — снова свободна.
func set_bridged(on: bool, at := Transform3D()) -> void:
	bridged = on
	if on:
		global_transform = at
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		freeze = true
		reset_physics_interpolation()
	else:
		freeze = false


## Вернуть на место старта (рестарт участка).
func go_home() -> void:
	if bridged:
		set_bridged(false)
	global_transform = home
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	reset_physics_interpolation()
	sleeping = false
