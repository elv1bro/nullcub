## Подбор оружия (план 07): узел-ребёнок Doll. Каждый физический тик свободная кисть (Hand_L / Hand_R)
## ищет Weapon в радиусе pickup_radius от своей точки хвата и «приваривает» его фиксированным
## Generic6DOFJoint3D (все оси заблокированы), поставленным в точку хвата. Оружие не бьёт хозяина:
## exclude_nodes_from_collision + исключения коллизий со всеми частями куклы. drop() отпускает,
## после чего drop_cooldown_s кисть не подбирает снова (и исключения снимаются, чтобы не выталкивало).
## Оружие — сцены scenes/weapons/weapon_<id>.tscn (Weapon), кукла — сцена scenes/doll/doll.tscn (doll.parts["Hand_L"/"Hand_R"]).
## Использование: doll.add_child(WeaponPickup.new())  (или load("res://scenes/weapons/weapon_pickup.gd").new()).
## v7: рука с оружием жёстче пустой — attach ставит суставам плеча/локтя/кисти этой стороны Tuning.WEAPON_ARM_MUSCLES
## (Doll.set_muscle_joint), drop/KO возвращает групповые (Doll.clear_muscle_joint); вторая рука остаётся мягкой.
## 29.09 (сборка тела, BODY_CRAFT.md): кисти — все части с базовым именем "Hand" (Hand_L / Hand_R у doll.tscn, Hand_<uid> у ModularDoll),
## суставы жёсткой руки ищутся вверх по цепочке от кисти (Wrist → Elbow → Shoulder), блокировка подбора — по кисти (set_hand_blocked),
## общий auto_pickup остаётся.
class_name WeaponPickup
extends Node

const HAND_BASE := "Hand"

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
## hand name -> true: подбор этой кистью выключен (ArmAssist держит ею пропс и т. п.)
var _blocked: Dictionary = {}


func _ready() -> void:
	doll = get_parent() as Doll
	if doll == null:
		push_error("WeaponPickup must be a child of Doll")


func _exit_tree() -> void:
	drop_all()


## Кисти куклы: части с базовым именем HAND_BASE, по имени (порядок стабилен: Hand_L раньше Hand_R).
func hand_names() -> Array:
	var out: Array = []
	if doll == null:
		return out
	for pn in doll.parts.keys():
		if Doll.part_base_name(String(pn)) == HAND_BASE:
			out.append(String(pn))
	out.sort()
	return out


## Выключить / включить подбор одной кистью (оружие в ней не трогается).
func set_hand_blocked(hand_name: String, on: bool) -> void:
	if on:
		_blocked[hand_name] = true
	else:
		_blocked.erase(hand_name)


func is_hand_blocked(hand_name: String) -> bool:
	return _blocked.has(hand_name)


func _hand_free(hand_name: String) -> bool:
	return not held.has(hand_name) and not _blocked.has(hand_name) and hand(hand_name) != null \
		and _time >= float(_cooldown_until.get(hand_name, 0.0))


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
			# оружие могли освободить, пока шёл кулдаун (сломалось, убрали): присваивание освобождённого в типизированную
			# переменную в Godot 4.7 обрывает функцию — сначала is_instance_valid, потом приведение
			var wv: Variant = e[0]
			if is_instance_valid(wv) and not (wv as Weapon).is_held():
				for part in doll.parts.values():
					(wv as Weapon).remove_collision_exception_with(part)
			_pending_release.remove_at(i)
		else:
			i += 1
	if not auto_pickup:
		return
	for hand_name in hand_names():
		if not _hand_free(hand_name):
			continue
		var w := nearest_free_weapon(hand_name)
		if w != null and _closest_free_hand(w) == hand_name:
			attach(hand_name, w)


## Какая из свободных кистей (не занята, не в кулдауне) ближе к хвату оружия. У манекена v3 кисти стоят в 0.44 м друг от
## друга (< pickup_radius): без этой проверки молот, лежащий у правой кисти, хватала левая (первая в hand_names()).
func _closest_free_hand(w: Weapon) -> String:
	var best := ""
	var best_d := INF
	for hand_name in hand_names():
		if not _hand_free(hand_name):
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
	var side := _hand_side(hand_name, h)
	var basis: Basis = h.global_transform.basis * Basis(Vector3(0, 0, 1), deg_to_rad(-90.0 + hold_angle_deg * side))
	var grip_g := hand_grip_global(hand_name)
	# оружие не должно бить хозяина
	for part in doll.parts.values():
		weapon.add_collision_exception_with(part)
	# снап: хват в кисть, скорость кисти, чтобы сустав не дёрнуло
	weapon.global_transform = Transform3D(basis, grip_g - basis * weapon.grip_local)
	weapon.linear_velocity = h.linear_velocity
	weapon.angular_velocity = h.angular_velocity
	weapon.reset_physics_interpolation()   # снап в кисть — телепорт, не полёт за тик
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


## Сторона кисти для угла хвата: +1 левая, −1 правая. Hand_L / Hand_R — по суффиксу (как раньше); у деталей Hand_<uid> — по тому,
## с какой стороны торса кисть в его локальных координатах (кукла смотрит в камеру, левая сторона — +X).
func _hand_side(hand_name: String, h: RigidBody3D) -> float:
	if hand_name.ends_with("_L"):
		return 1.0
	if hand_name.ends_with("_R"):
		return -1.0
	# ModularDoll: кадр детали в сборке (кукла лицом в камеру, левая сторона +X) — не зависит от того, как кукла повёрнута сейчас
	var asm: Variant = doll.get("assembly")
	if asm is Dictionary and (asm as Dictionary).has(hand_name) and (asm as Dictionary)[hand_name] is Transform3D:
		return 1.0 if ((asm as Dictionary)[hand_name] as Transform3D).origin.x >= 0.0 else -1.0
	var t := doll.torso() if doll.parts.has("Torso") else null
	if t == null:
		return 1.0
	return 1.0 if t.to_local(h.global_position).x >= 0.0 else -1.0


## Суставы руки от кисти вверх по цепочке (Wrist → Elbow → Shoulder у doll.tscn), чьи группы есть в Tuning.WEAPON_ARM_MUSCLES:
## идём от тела к родителю по суставу, где тело — node_b, пока группа сустава в таблице.
func _arm_joints(hand_name: String) -> Array:
	var out: Array = []
	var body: Node = hand(hand_name)
	var guard := 0
	while body != null and guard < 6:
		guard += 1
		var up: Generic6DOFJoint3D = null
		for j in doll.joints.values():
			if not is_instance_valid(j):
				continue
			var jj := j as Generic6DOFJoint3D
			if jj != null and jj.get_node_or_null(jj.node_b) == body:
				up = jj
				break
		if up == null or not Tuning.WEAPON_ARM_MUSCLES.has(String(up.name).split("_")[0]):
			break
		out.append(String(up.name))
		body = up.get_node_or_null(up.node_a)
	return out


## Жёсткость руки с оружием: суставы этой руки (_arm_joints) по Tuning.WEAPON_ARM_MUSCLES их группы.
func _set_arm_stiff(hand_name: String, on: bool) -> void:
	if doll == null or not is_instance_valid(doll) or hand(hand_name) == null:
		return
	for jn in _arm_joints(hand_name):
		if on:
			var e: Dictionary = Tuning.WEAPON_ARM_MUSCLES[String(jn).split("_")[0]]
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
	for other in held.keys():   # у сборки две кисти могут делить суставы руки — вторая с оружием остаётся жёсткой
		_set_arm_stiff(String(other), true)


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
