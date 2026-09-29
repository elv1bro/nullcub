## Разрушаемый пропс (бочка, ящик) — только поведение. Дерево (RigidBody3D → Shape + Mesh=GLB с объектами
## Intact / Damaged / Destroyed/Piece_*) живёт в barrel.tscn / crate.tscn (tools/build_props_scenes.gd).
##
## Урон — от столкновений. Контакты читаются в _integrate_forces (нужен max_contacts_reported ≥ MIN_CONTACTS: лежащая
## бочка держит 4–6 точек с полом плюс обломки, и при лимите 6 новый неглубокий контакт вытеснялся): импульс контакта
## Jolt оценивает по скоростям ДО решения, поэтому скорость сближения по нормали восстанавливается точно:
##   v = |J| × (1/m_self + 1/m_other) / (1 + bounce)      (m_other = ∞ для статики; сигнал body_entered для этого
##   не годится — он приходит после решения контакта, когда скорости уже погашены).
## v ≥ min_impact_speed → damage = v × damage_per_speed × mass_factor, mass_factor = масса ударившего / REF_MASS
## в [0.5, 2] (статика — 1.0). hp ≤ 50 % → показывается Damaged; hp ≤ 0 → из Destroyed/Piece_* спавнятся
## RigidBody3D-обломки (выпуклая оболочка меша, скорость родителя + разлёт burst_speed), сигнал destroyed, само тело
## исчезает. Обломки замерзают через debris_freeze_s и удаляются через debris_free_s. Всё, что меняет физику/дерево,
## делается deferred — контакты приходят внутри коллбэка физики.
class_name Breakable
extends RigidBody3D

signal destroyed
signal state_changed(state: int)
## Зарегистрированный удар: скорость сближения (м/с), урон (HP), ударивший узел.
signal hit(speed: float, damage: float, by: Node)

enum State { INTACT, DAMAGED, DESTROYED }

## Массы и HP по виду пропса; builder пишет их в сцену при генерации (одно место — здесь).
const MASS := {"barrel": 15.0, "crate": 10.0}
const HP := {"barrel": 30.0, "crate": 20.0}
const REF_MASS := 4.0          # кг: удар этой массой = множитель 1 (голова/нога куклы)
const HIT_COOLDOWN_S := 0.25
const MIN_CONTACTS := 16

@export_enum("barrel", "crate") var kind := "barrel"
@export var hp := 30.0
@export var state := State.INTACT: set = _set_state
@export var min_impact_speed := 6.0     # м/с (формула 06: ниже порога урона нет)
@export var damage_per_speed := 1.0     # HP на м/с × mass_factor
@export var burst_speed := 2.5          # м/с разлёта обломков от центра
@export var debris_freeze_s := 3.0
@export var debris_free_s := 10.0
@export var mesh_path: NodePath = ^"Mesh"

var max_hp := 30.0
## Последний зарегистрированный удар: {"speed", "damage", "by"} — для тестов и отладки.
var last_hit: Dictionary = {}
var _hit_until: Dictionary = {}   # instance id → время, до которого удары этого тела игнорируются
var _time := 0.0
var _spawned := false


func _ready() -> void:
	max_hp = maxf(hp, 1.0)
	if max_contacts_reported < MIN_CONTACTS:
		max_contacts_reported = MIN_CONTACTS
	_apply_visual()


func _physics_process(delta: float) -> void:
	_time += delta


func _integrate_forces(st: PhysicsDirectBodyState3D) -> void:
	if state == State.DESTROYED:
		return
	# импульсы всех точек манифолда с одним телом суммируются (бокс о цилиндр даёт 2–4 точки)
	var by_id: Dictionary = {}
	for i in st.get_contact_count():
		var id := st.get_contact_collider_id(i)
		if not by_id.has(id):
			by_id[id] = {"other": st.get_contact_collider_object(i), "impulse": Vector3.ZERO}
		by_id[id]["impulse"] += st.get_contact_impulse(i)
	if by_id.is_empty():
		return
	var bounce := physics_material_override.bounce if physics_material_override else 0.0
	for id in by_id.keys():
		if float(_hit_until.get(id, -1.0)) > _time:
			continue
		var other := by_id[id]["other"] as Node
		var inv_m := 1.0 / maxf(mass, 0.01)
		var mf := 1.0
		if other is RigidBody3D and not (other as RigidBody3D).freeze:
			var om: float = maxf((other as RigidBody3D).mass, 0.01)
			inv_m += 1.0 / om
			mf = clampf(om / REF_MASS, 0.5, 2.0)
		var speed: float = (by_id[id]["impulse"] as Vector3).length() * inv_m / (1.0 + bounce)
		if speed < min_impact_speed:
			continue
		_hit_until[id] = _time + HIT_COOLDOWN_S
		var dmg := speed * damage_per_speed * mf
		last_hit = {"speed": speed, "damage": dmg, "by": other}
		hit.emit(speed, dmg, other)
		take_damage.call_deferred(dmg)


## Прямой урон (оружие, скрипты боя). Переходы состояний — через сеттер state.
func take_damage(amount: float) -> void:
	if state == State.DESTROYED or amount <= 0.0:
		return
	hp = maxf(hp - amount, 0.0)
	if hp <= 0.0:
		state = State.DESTROYED
	elif hp <= max_hp * 0.5 and state == State.INTACT:
		state = State.DAMAGED


func _set_state(v: State) -> void:
	if v == state:
		return
	state = v
	if not is_inside_tree():
		return
	_apply_visual()
	state_changed.emit(state)
	if state == State.DESTROYED:
		call_deferred("_destroy")


func _mesh_root() -> Node:
	return get_node_or_null(mesh_path)


func _apply_visual() -> void:
	var m := _mesh_root()
	if m == null:
		return
	var intact := m.find_child("Intact", true, false)
	var dam := m.find_child("Damaged", true, false)
	var des := m.find_child("Destroyed", true, false)
	if intact:
		intact.visible = state == State.INTACT
	if dam:
		dam.visible = state == State.DAMAGED
	if des:
		des.visible = false


func _destroy() -> void:
	if _spawned:
		return
	_spawned = true
	_spawn_debris()
	destroyed.emit()
	visible = false
	freeze = true
	for c in get_children():
		if c is CollisionShape3D:
			c.disabled = true
	queue_free()


## Обломки из шаблонов Destroyed/Piece_* (их трансформы в GLB = положение куска в целом пропсе).
func _spawn_debris() -> void:
	var m := _mesh_root()
	var tpl := m.find_child("Destroyed", true, false) if m else null
	var parent := get_parent()
	if tpl == null or parent == null:
		return
	var pieces: Array = []
	for p in tpl.get_children():
		if p is MeshInstance3D and (p as MeshInstance3D).mesh != null:
			pieces.append(p)
	if pieces.is_empty():
		return
	var tree := get_tree()
	for p in pieces:
		var piece := p as MeshInstance3D
		var body := RigidBody3D.new()
		body.name = "%s_%s" % [name, piece.name]
		body.mass = maxf(mass / pieces.size(), 0.5)
		body.axis_lock_linear_z = true
		body.axis_lock_angular_x = true
		body.axis_lock_angular_y = true
		body.continuous_cd = true
		body.linear_damp = 0.4
		body.angular_damp = 1.0
		body.collision_layer = collision_layer
		body.collision_mask = collision_mask
		body.physics_material_override = physics_material_override
		body.add_to_group("debris")
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		cs.shape = piece.mesh.create_convex_shape(true, true)
		body.add_child(cs)
		var mi := piece.duplicate() as MeshInstance3D
		mi.name = "Mesh"
		mi.visible = true
		mi.transform = Transform3D.IDENTITY
		body.add_child(mi)
		parent.add_child(body)
		body.global_transform = piece.global_transform
		var dir := body.global_position - global_position
		dir.z = 0.0
		dir = dir.normalized() if dir.length() > 0.01 else Vector3.UP
		body.linear_velocity = linear_velocity + dir * burst_speed + Vector3.UP * burst_speed * 0.4
		body.angular_velocity = Vector3(0.0, 0.0, randf_range(-5.0, 5.0))
		# weakref: сцену могут освободить раньше таймеров (смена арены, конец теста) — лямбда не держит мёртвую ссылку
		var wr: WeakRef = weakref(body)
		tree.create_timer(debris_freeze_s).timeout.connect(func() -> void:
			var rb := wr.get_ref() as RigidBody3D
			if rb != null:
				rb.freeze = true)
		tree.create_timer(debris_free_s).timeout.connect(func() -> void:
			var rb := wr.get_ref() as RigidBody3D
			if rb != null:
				rb.queue_free())
