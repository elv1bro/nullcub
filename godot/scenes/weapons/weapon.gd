## Физическое оружие (CONCEPT.md §11, план 07): RigidBody3D в плоскости XY, как части куклы.
## Сцена res://scenes/weapons/weapon_<id>.tscn генерируется tools/build_weapon_scenes.gd (ASSET_PIPELINE.md, правило 2):
## тело + коллизии (Handle/Head/...) + модель assets/models/weapons/<id>.glb (tools/blender/weapons.py):
## origin модели = точка хвата, оружие вытянуто вдоль +X, лицо в +Z, навершие/торец рукояти в −X.
## Здесь только поведение: id, хват, владелец, drop(). Числа — Tuning.WEAPON (масса пишется билдером в сцену,
## damage_mult/length читаются отсюда при старте).
class_name Weapon
extends RigidBody3D

const GROUP := "weapons"
const SCENE_DIR := "res://scenes/weapons/"
const IDS := ["hammer", "mace", "sword", "axe", "pan", "stick"]   # stick — клюшка (ХОККЕЙ, HOCKEY.md)

@export var weapon_id := "hammer"
## Точка хвата в локальных координатах (по конвенции моделей — начало координат).
@export var grip_local := Vector3.ZERO

var damage_mult := 1.0
var length := 0.0
## Кто держит (WeaponPickup) и какой кистью; null = свободно лежит.
var holder: Node = null
var holder_hand: RigidBody3D = null
## Последний владелец (для зачёта урона брошенным оружием, план 07) и время, когда его отпустили.
var last_holder: Node = null
var released_at := -1.0
var shapes: Array[CollisionShape3D] = []
var model: Node3D
var _time := 0.0


static func scene_path(id: String) -> String:
	return SCENE_DIR + "weapon_" + id + ".tscn"


## Удобный спавн: load сцены по id, добавить к parent в позиции pos (поворот rot_z_deg в плоскости экрана).
static func spawn(id: String, parent: Node, pos: Vector3, rot_z_deg: float = 0.0) -> Weapon:
	var ps := load(scene_path(id)) as PackedScene
	if ps == null:
		push_error("Weapon.spawn: no scene for id '%s'" % id)
		return null
	var w: Weapon = ps.instantiate()
	parent.add_child(w)
	w.global_transform = Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(rot_z_deg)), pos)
	return w


func _ready() -> void:
	add_to_group(GROUP)
	var e: Dictionary = Tuning.WEAPON.get(weapon_id, {})
	damage_mult = float(e.get("damage_mult", 1.0))
	length = float(e.get("length", 0.0))
	linear_damp = Tuning.LINEAR_DAMP
	angular_damp = Tuning.ANGULAR_DAMP
	for c in get_children():
		if c is CollisionShape3D:
			shapes.append(c)
		elif c is Node3D and model == null and c.name == "Model":
			model = c


func _physics_process(delta: float) -> void:
	_time += delta


func grip_global() -> Vector3:
	return to_global(grip_local)


func is_held() -> bool:
	return holder != null and is_instance_valid(holder)


## Отпустить из кисти (если держат). Делегирует WeaponPickup.drop_weapon.
func drop() -> void:
	if is_held() and holder.has_method("drop_weapon"):
		holder.drop_weapon(self)


## Вызывается WeaponPickup при захвате/отпускании.
func set_holder(pickup: Node, hand: RigidBody3D) -> void:
	if pickup == null and holder != null:
		last_holder = holder
		released_at = _time
	holder = pickup
	holder_hand = hand


## Кому засчитать урон от этого оружия: держащему, иначе последнему владельцу в течение window_s.
func attacker(window_s: float = 3.0) -> Node:
	if is_held():
		return holder
	if last_holder != null and is_instance_valid(last_holder) and released_at >= 0.0 and _time - released_at <= window_s:
		return last_holder
	return null


func speed() -> float:
	return linear_velocity.length()


## Объединённый AABB коллизий в локальных координатах (для раскладки на полу и витрин).
func bounds() -> AABB:
	var box := AABB()
	var first := true
	for cs in shapes:
		var half := Vector3.ZERO
		var sh := cs.shape
		if sh is BoxShape3D:
			half = (sh as BoxShape3D).size / 2.0
		elif sh is SphereShape3D:
			half = Vector3.ONE * (sh as SphereShape3D).radius
		elif sh is CylinderShape3D:
			var cy := sh as CylinderShape3D
			half = Vector3(cy.radius, cy.height / 2.0, cy.radius)
		elif sh is CapsuleShape3D:
			var ca := sh as CapsuleShape3D
			half = Vector3(ca.radius, ca.height / 2.0, ca.radius)
		for i in range(8):
			var corner := Vector3(half.x * (1 if i & 1 else -1), half.y * (1 if i & 2 else -1), half.z * (1 if i & 4 else -1))
			var p: Vector3 = cs.transform * corner
			if first:
				box = AABB(p, Vector3.ZERO)
				first = false
			else:
				box = box.expand(p)
	return box
