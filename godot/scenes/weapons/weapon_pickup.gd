## Подбор оружия (план 07): узел-ребёнок Doll. Каждый физический тик свободная кисть (Hand_L / Hand_R)
## ищет Weapon в радиусе pickup_radius от своей точки хвата и «приваривает» его фиксированным
## Generic6DOFJoint3D (все оси заблокированы), поставленным в точку хвата. Оружие не бьёт хозяина:
## exclude_nodes_from_collision + исключения коллизий со всеми частями куклы. drop() отпускает,
## после чего drop_cooldown_s кисть не подбирает снова (и исключения снимаются, чтобы не выталкивало).
## Оружие — сцены scenes/weapons/weapon_<id>.tscn (Weapon), кукла — сцена scenes/doll/doll.tscn (doll.parts["Hand_L"/"Hand_R"]).
## Использование: doll.add_child(WeaponPickup.new())  (или load("res://scenes/weapons/weapon_pickup.gd").new()).
## v7: рука с оружием жёстче пустой — attach ставит суставам плеча/локтя/кисти этой стороны Tuning.WEAPON_ARM_MUSCLES
## (Doll.set_muscle_joint), drop/KO возвращает групповые (Doll.clear_muscle_joint); вторая рука остаётся мягкой.
class_name WeaponPickup
extends Node

const HANDS := ["Hand_L", "Hand_R"]

@export var pickup_radius := 0.45  # ART_DIRECTION.md v3: манекен 1.8 м, риг по высотам как v1 — радиус подбора снова 0.45
@export var drop_cooldown_s := 0.35
@export var auto_pickup := true
## Как оружие лежит в кисти: 0° = продолжение руки (+X оружия вдоль -Y кисти, «вниз»),
## 90° = в сторону от тела (как в R16, голова молота вбок). Для правой кисти зеркалится.
@export var hold_angle_deg := 90.0
## Точка хвата в локальных координатах кисти (центр кисти чуть к пальцам).
@export var hand_grip_offset := Vector3(0, -0.03, 0)

var doll: Doll
## hand name -> {"weapon": Weapon, "joint": Generic6DOFJoint3D}
var held: Dictionary = {}
var _cooldown_until: Dictionary = {}
## [weapon, time] — исключения коллизий снимаются, когда кулдаун прошёл
var _pending_release: Array = []
var _time := 0.0


func _ready() -> void:
	doll = get_parent() as Doll
	if doll == null:
		push_error("WeaponPickup must be a child of Doll")


func _exit_tree() -> void:
	drop_all()


func hand(hand_name: String) -> RigidBody3D:
	return doll.parts.get(hand_name)


func hand_grip_global(hand_name: String) -> Vector3:
	return hand(hand_name).to_global(hand_grip_offset)


func is_holding(hand_name: String) -> bool:
	return held.has(hand_name)


func weapon_in(hand_name: String) -> Weapon:
	if not held.has(hand_name):
		return null
	return held[hand_name]["weapon"]


func joint_of(hand_name: String) -> Generic6DOFJoint3D:
	if not held.has(hand_name):
		return null
	return held[hand_name]["joint"]


## Расстояние кисть–хват для проверки, что сустав держит (0 в идеале).
func hold_distance(hand_name: String) -> float:
	var w := weapon_in(hand_name)
	if w == null or not is_instance_valid(w):
		return INF
	return hand_grip_global(hand_name).distance_to(w.grip_global())


func _physics_process(delta: float) -> void:
	_time += delta
	if doll == null:
		return
	# снятие исключений коллизий после кулдауна
	var i := 0
	while i < _pending_release.size():
		var e: Array = _pending_release[i]
		if _time >= e[1]:
			var w: Weapon = e[0]
			if is_instance_valid(w) and not w.is_held():
				for part in doll.parts.values():
					w.remove_collision_exception_with(part)
			_pending_release.remove_at(i)
		else:
			i += 1
	if not auto_pickup:
		return
	for hand_name in HANDS:
		if held.has(hand_name) or hand(hand_name) == null:
			continue
		if _time < _cooldown_until.get(hand_name, 0.0):
			continue
		var w := nearest_free_weapon(hand_name)
		if w != null and _closest_free_hand(w) == hand_name:
			attach(hand_name, w)


## Какая из свободных кистей (не занята, не в кулдауне) ближе к хвату оружия. У манекена v3 кисти стоят в 0.44 м друг от
## друга (< pickup_radius): без этой проверки молот, лежащий у правой кисти, хватала левая (первая в HANDS).
func _closest_free_hand(w: Weapon) -> String:
	var best := ""
	var best_d := INF
	for hand_name in HANDS:
		if held.has(hand_name) or hand(hand_name) == null or _time < _cooldown_until.get(hand_name, 0.0):
			continue
		var d := hand_grip_global(hand_name).distance_to(w.grip_global())
		if d < best_d:
			best_d = d
			best = hand_name
	return best


## Ближайшее свободное оружие в радиусе pickup_radius от точки хвата кисти (null, если нет).
func nearest_free_weapon(hand_name: String) -> Weapon:
	var p := hand_grip_global(hand_name)
	var best: Weapon = null
	var best_d := pickup_radius
	for n in get_tree().get_nodes_in_group(Weapon.GROUP):
		var w := n as Weapon
		if w == null or w.is_held():
			continue
		var d := p.distance_to(w.grip_global())
		if d < best_d:
			best_d = d
			best = w
	return best


## Приваривает оружие к кисти: хват оружия ставится в точку хвата кисти под углом hold_angle_deg,
## затем создаётся фиксированный сустав. Возвращает false, если кисть занята или оружие уже в руке.
func attach(hand_name: String, weapon: Weapon) -> bool:
	if doll == null or held.has(hand_name) or weapon == null or weapon.is_held():
		return false
	var h := hand(hand_name)
	if h == null:
		return false
	var side := 1.0 if hand_name.ends_with("L") else -1.0
	var basis: Basis = h.global_transform.basis * Basis(Vector3(0, 0, 1), deg_to_rad(-90.0 + hold_angle_deg * side))
	var grip_g := hand_grip_global(hand_name)
	# оружие не должно бить хозяина
	for part in doll.parts.values():
		weapon.add_collision_exception_with(part)
	# снап: хват в кисть, скорость кисти, чтобы сустав не дёрнуло
	weapon.global_transform = Transform3D(basis, grip_g - basis * weapon.grip_local)
	weapon.linear_velocity = h.linear_velocity
	weapon.angular_velocity = h.angular_velocity
	var j := Generic6DOFJoint3D.new()
	j.name = "Grip_" + hand_name
	add_child(j)
	j.global_transform = Transform3D(h.global_transform.basis, grip_g)
	j.exclude_nodes_from_collision = true
	j.node_a = j.get_path_to(h)
	j.node_b = j.get_path_to(weapon)
	for ax in ["x", "y", "z"]:
		j.set("linear_limit_%s/enabled" % ax, true)
		j.set("linear_limit_%s/upper_distance" % ax, 0.0)
		j.set("linear_limit_%s/lower_distance" % ax, 0.0)
		j.set("angular_limit_%s/enabled" % ax, true)
		j.set("angular_limit_%s/upper_angle" % ax, 0.0)
		j.set("angular_limit_%s/lower_angle" % ax, 0.0)
	held[hand_name] = {"weapon": weapon, "joint": j}
	weapon.set_holder(self, h)
	_set_arm_stiff(hand_name, true)
	return true


## Жёсткость руки с оружием: суставы Shoulder/Elbow/Wrist той же стороны, что кисть (Hand_L → *_L), по Tuning.WEAPON_ARM_MUSCLES.
func _set_arm_stiff(hand_name: String, on: bool) -> void:
	if doll == null or not is_instance_valid(doll):
		return
	var side := hand_name.substr(hand_name.length() - 2)   # "_L" / "_R"
	for g in Tuning.WEAPON_ARM_MUSCLES:
		var jn: String = String(g) + side
		if on:
			var e: Dictionary = Tuning.WEAPON_ARM_MUSCLES[g]
			doll.set_muscle_joint(jn, float(e["k"]), float(e.get("tmax", -1.0)), float(e.get("zeta", -1.0)))
		else:
			doll.clear_muscle_joint(jn)


## Отпускает оружие из кисти: сустав освобождается, кулдаун drop_cooldown_s до повторного подбора.
func drop(hand_name: String) -> void:
	if not held.has(hand_name):
		return
	var e: Dictionary = held[hand_name]
	held.erase(hand_name)
	var j: Generic6DOFJoint3D = e["joint"]
	if is_instance_valid(j):
		j.node_a = NodePath()
		j.node_b = NodePath()
		j.queue_free()
	var w: Weapon = e["weapon"]
	if is_instance_valid(w):
		w.set_holder(null, null)
		_pending_release.append([w, _time + drop_cooldown_s])
	_cooldown_until[hand_name] = _time + drop_cooldown_s
	_set_arm_stiff(hand_name, false)


## Отпустить конкретное оружие (Weapon.drop() делегирует сюда).
func drop_weapon(weapon: Weapon) -> void:
	for hand_name in held.keys():
		if held[hand_name]["weapon"] == weapon:
			drop(hand_name)
			return


func drop_all() -> void:
	for hand_name in held.keys():
		drop(hand_name)


## Удобный статический вход: повесить подбор на куклу (возвращает узел).
static func attach_to(target: Doll) -> WeaponPickup:
	var p := WeaponPickup.new()
	p.name = "WeaponPickup"
	target.add_child(p)
	return p
