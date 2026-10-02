## Кукла игрока в гараже меню (docs/plan-demo/MENU_GARAGE.md): текущая сборка из мастерской (user://blueprints/_autosave.tres —
## его пишет мастерская, CraftEdit.AUTOSAVE; нет или не собирается — пресет human) сидит на ящике перед телевизором.
## Физики нет — как StandDoll мастерской (workshop_build.gd): тела заморожены (kinematic), суставы отцеплены, 2.5D-замки
## сняты. Суставы куклы гнутся только в плоскости экрана, а сидеть надо «лицом к ТВ», поэтому поза ставится в 3D: от сборочной
## позы (spawn_in_pose = false — все детали вдоль якорей: руки и ноги висят) каждое поддерево деталей поворачивается вокруг
## точки своего сустава (таблица SIT, ось — в кадре куклы, лицо куклы +Z). Вне поля NULL кукла тяжёлая — сидит, а не парит.
## look_toward(точка) — голова (поддерево сустава Neck) плавно поворачивается к месту пункта меню.
class_name GarageDoll
extends Node3D

const MODULAR_DOLL := preload("res://scenes/body/modular_doll.tscn")
const PRESET := "human"
## Группа сустава → [ось, угол°]: Hip — бедро вперёд, Knee — голень обратно вниз, Shoulder/Elbow — руки на колени,
## Neck — голова чуть вниз (на экран). Углы относительные, обход — от корня (торс) к концам.
const SIT := {"Hip": [Vector3.RIGHT, -84.0], "Knee": [Vector3.RIGHT, 86.0], "Ankle": [Vector3.RIGHT, -6.0],
	"Shoulder": [Vector3.RIGHT, -16.0], "Elbow": [Vector3.RIGHT, -46.0], "Neck": [Vector3.RIGHT, 6.0]}
const LOOK_MAX_DEG := 55.0

## Высота сиденья (верх ящика) в координатах этого узла; бёдра кладутся на неё.
@export var seat_height := 0.5
## Чертёж вместо автосейва (пробы); пусто — автосейв мастерской, затем PRESET.
@export var blueprint_path := ""

var doll: ModularDoll
var blueprint_source := ""          # откуда взят чертёж: autosave | preset | path
var _children := {}                 # тело → [{joint, body}]
var _pivot_local := {}              # сустав → точка сустава в кадре тела-родителя
var _neck_bodies: Array = []
var _neck_base := {}                # тело → Transform3D до поворота головы
var _neck_pivot := Vector3.ZERO
var _look_yaw := 0.0
var _look_target := 0.0


func _ready() -> void:
	build()


func build() -> void:
	var bp := _blueprint()
	doll = MODULAR_DOLL.instantiate() as ModularDoll
	doll.name = "Doll"
	doll.blueprint = bp
	doll.external_input = true
	doll.control_enabled = false
	doll.spawn_in_pose = false
	doll.player_index = 0
	add_child(doll)
	for b in doll.parts.values():
		var rb := b as RigidBody3D
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rb.freeze = true
		rb.collision_layer = 0
		rb.collision_mask = 0
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		for ax in ["x", "y", "z"]:
			rb.set("axis_lock_angular_" + ax, false)
			rb.set("axis_lock_linear_" + ax, false)
	var is_child := {}
	for j in doll.joints.values():
		var jt := j as Generic6DOFJoint3D
		var a := jt.get_node_or_null(jt.node_a) as Node3D
		var b := jt.get_node_or_null(jt.node_b) as Node3D
		if a == null or b == null:
			continue
		if not _children.has(a):
			_children[a] = []
		_children[a].append({"joint": jt, "body": b})
		_pivot_local[jt] = a.transform.affine_inverse() * jt.position
		is_child[b] = true
	for j in doll.joints.values():
		(j as Generic6DOFJoint3D).node_a = NodePath()
		(j as Generic6DOFJoint3D).node_b = NodePath()
	doll.set_physics_process(false)
	doll.set_process(false)
	for b in doll.parts.values():
		if not is_child.has(b):
			_pose(b as Node3D)
	_seat()
	_find_neck()


func _blueprint() -> BodyBlueprint:
	var bp: BodyBlueprint = null
	if blueprint_path != "":
		bp = CraftEdit.load_saved(blueprint_path)
		blueprint_source = "path"
	if bp == null:
		bp = CraftEdit.load_saved(CraftEdit.save_path(CraftEdit.AUTOSAVE))
		blueprint_source = "autosave"
		if bp != null and not CraftEdit.structural_errors(bp).is_empty():
			bp = null
	if bp == null:
		bp = CraftEdit.load_body_preset(PRESET)
		blueprint_source = "preset"
	return bp


## Обход от тела вниз: поддерево каждого ребёнка поворачивается вокруг точки его сустава (кадр куклы).
func _pose(body: Node3D) -> void:
	for e in _children.get(body, []):
		var jt: Generic6DOFJoint3D = e["joint"]
		var child: Node3D = e["body"]
		var group := String(jt.name).get_slice("_", 0)
		if SIT.has(group):
			var spec: Array = SIT[group]
			var pivot: Vector3 = body.transform * (_pivot_local[jt] as Vector3)
			_rotate_subtree(child, pivot, Basis(spec[0] as Vector3, deg_to_rad(float(spec[1]))))
		_pose(child)


func _subtree(body: Node3D, out: Array) -> Array:
	out.append(body)
	for e in _children.get(body, []):
		_subtree(e["body"], out)
	return out


func _rotate_subtree(body: Node3D, pivot: Vector3, r: Basis) -> void:
	var xf := Transform3D(r, pivot - r * pivot)
	for d in _subtree(body, []):
		(d as Node3D).transform = xf * (d as Node3D).transform


## Бёдра (дети суставов Hip) — нижней точкой на сиденье, таз над центром узла (чуть назад — бёдра свисают вперёд).
func _seat() -> void:
	var hips: Array = []
	var pivots: Array = []
	for a in _children:
		for e in _children[a]:
			if String((e["joint"] as Node).name).begins_with("Hip"):
				hips.append(e["body"])
				pivots.append((a as Node3D).transform * (_pivot_local[e["joint"]] as Vector3))
	var min_y := INF
	var src: Array = hips if not hips.is_empty() else doll.parts.values()
	for b in src:
		for mi in (b as Node).find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var box := doll.transform.affine_inverse() * m.global_transform * m.get_aabb()
			min_y = minf(min_y, box.position.y)
	var c := Vector3.ZERO
	for p in pivots:
		c += p
	if not pivots.is_empty():
		c /= pivots.size()
	if hips.is_empty():     # без ног (колесо, паук без бёдер) — просто стоит на ящике
		doll.position = Vector3(0, seat_height - minf(min_y, 0.0), 0)
	else:
		doll.position = Vector3(-c.x, seat_height - min_y, -c.z - 0.08)


func _find_neck() -> void:
	for a in _children:
		for e in _children[a]:
			if String((e["joint"] as Node).name).begins_with("Neck"):
				_neck_pivot = (a as Node3D).transform * (_pivot_local[e["joint"]] as Vector3)
				_neck_bodies = _subtree(e["body"], [])
	for b in _neck_bodies:
		_neck_base[b] = (b as Node3D).transform


## Голова поворачивается к точке world_point (по горизонтали, не больше LOOK_MAX_DEG от «прямо»).
func look_toward(world_point: Vector3) -> void:
	if _neck_bodies.is_empty():
		return
	var local := (doll.global_transform).affine_inverse() * world_point - _neck_pivot
	_look_target = clampf(rad_to_deg(atan2(local.x, local.z)), -LOOK_MAX_DEG, LOOK_MAX_DEG)


func _process(delta: float) -> void:
	if _neck_bodies.is_empty() or absf(_look_target - _look_yaw) < 0.05:
		return
	_look_yaw = lerpf(_look_yaw, _look_target, 1.0 - exp(-delta * 4.0))
	var r := Basis(Vector3.UP, deg_to_rad(_look_yaw))
	var xf := Transform3D(r, _neck_pivot - r * _neck_pivot)
	for b in _neck_bodies:
		(b as Node3D).transform = xf * (_neck_base[b] as Transform3D)
