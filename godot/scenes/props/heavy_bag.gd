## Груша-шар для ударов в тренировочном зале (scenes/arena/training_hall.tscn): тяжёлый шар (модель Heavy_Bag.glb кита Old NULL Hall)
## на цепи с потолочной балки. Физика — RigidBody3D в плоскости боя (z-замок) + «цепь» силой: пока ушко шара дальше от проушины, чем
## длина цепи, пружина тянет его обратно и гасит скорость вдоль цепи (цепь тянет, но не толкает); повисшая — шар качается маятником
## с любым поворотом. Цепь рисуется звеньями Chain_Link.glb (MultiMesh) от проушины до ушка.
## Замер удара: пока есть контакты, считаем силу по изменению импульса шара за шаг (Jolt даёт и get_contact_impulse — берём большее),
## запоминаем пик; пауза без касаний (HEAVY_BAG_HIT_GAP_S) — удар закончен → сигнал hit({force_n, impulse_ns, speed_ms, part, t}).
## Числа — Tuning.HEAVY_BAG_*. Урон груша не получает: она меряет, а не ломается.
class_name HeavyBag
extends RigidBody3D

signal hit(info: Dictionary)

const LINK_SCENE := "res://assets/models/arena/null_hall/Chain_Link.glb"
const EAR := 0.62                       # высота ушка над центром шара (Heavy_Bag.glb)

## Точка подвеса (мир) — проушина балки; задаёт зал. Пусто (ZERO) — подвес в центре шара на HEAVY_BAG_CHAIN_LEN + EAR выше старта.
@export var anchor := Vector3.ZERO

var last_hit: Dictionary = {}
var hits := 0
var best_force_n := 0.0
var _chain: MultiMeshInstance3D
var _link_len := 0.2
var _prev_v := Vector3.ZERO
var _in_contact := false
var _gap := 0.0
var _peak_f := 0.0
var _peak_j := 0.0
var _peak_speed := 0.0
var _peak_part := ""
var _time := 0.0
var _contact_dt := 0.0
var _dt := 1.0 / 60.0


func _ready() -> void:
	mass = Tuning.HEAVY_BAG_MASS
	linear_damp = Tuning.HEAVY_BAG_LIN_DAMP
	angular_damp = Tuning.HEAVY_BAG_ANG_DAMP
	axis_lock_linear_z = true
	axis_lock_angular_x = true
	axis_lock_angular_y = true
	contact_monitor = true
	max_contacts_reported = 8
	can_sleep = false
	set_meta(&"no_grab", true)          # ArmAssist.can_grab: груша на цепи не хватается и не таскается
	if anchor == Vector3.ZERO:
		anchor = global_position + Vector3(0, EAR + Tuning.HEAVY_BAG_CHAIN_LEN, 0)
	_build_chain()
	_prev_v = linear_velocity


func _build_chain() -> void:
	var ps := load(LINK_SCENE) as PackedScene
	if ps == null:
		return
	var src: MeshInstance3D = null
	var inst := ps.instantiate()
	for c in inst.find_children("*", "MeshInstance3D", true, false):
		src = c as MeshInstance3D
		break
	if src == null:
		inst.queue_free()
		return
	_chain = MultiMeshInstance3D.new()
	_chain.name = "Chain"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = src.mesh
	mm.instance_count = int(ceil(Tuning.HEAVY_BAG_CHAIN_LEN * 1.6 / _link_len)) + 4
	_chain.multimesh = mm
	_chain.top_level = true
	_chain.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_chain)
	inst.queue_free()


func _physics_process(delta: float) -> void:
	_time += delta
	_dt = delta
	# цепь: ушко шара и проушина
	var ear := global_transform * Vector3(0, EAR, 0)
	var d := ear - anchor
	var dist := d.length()
	if dist > Tuning.HEAVY_BAG_CHAIN_LEN and dist > 0.0001:
		var dir := d / dist
		var stretch := dist - Tuning.HEAVY_BAG_CHAIN_LEN
		var vel_along := linear_velocity.dot(dir)
		var f := -dir * (Tuning.HEAVY_BAG_CHAIN_K * stretch + Tuning.HEAVY_BAG_CHAIN_C * maxf(vel_along, 0.0))
		apply_force(f, ear - global_position)
	# замер удара
	if _in_contact:
		_gap = 0.0
	else:
		_gap += delta
		if _peak_f > 0.0 and _gap >= Tuning.HEAVY_BAG_HIT_GAP_S:
			_finish_hit()
	_in_contact = false
	_prev_v = linear_velocity


func _process(_delta: float) -> void:
	_update_chain()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var n := state.get_contact_count()
	if n == 0:
		return
	var dt := maxf(state.step, 0.0001)
	var dv := state.linear_velocity - _prev_v
	dv.y += Tuning.GRAVITY * dt      # без вклада тяжести
	var f_dv := mass * dv.length() / dt
	var j_sum := 0.0
	var speed := 0.0
	var part := ""
	for i in n:
		j_sum += state.get_contact_impulse(i).length()
		var rel := state.get_contact_collider_velocity_at_position(i) - state.get_contact_local_velocity_at_position(i)
		if rel.length() > speed:
			speed = rel.length()
			var o := state.get_contact_collider_object(i) as Node
			part = String(o.name) if o != null else ""
	var f_j := j_sum / dt
	var f := maxf(f_dv, f_j)
	if f < Tuning.HEAVY_BAG_HIT_MIN_N * 0.25:
		return
	_in_contact = true
	if f > _peak_f:
		_peak_f = f
		_peak_j = maxf(j_sum, mass * dv.length())
		_peak_part = part
	_peak_speed = maxf(_peak_speed, speed)


func _finish_hit() -> void:
	var f := _peak_f
	var info := {"force_n": f, "impulse_ns": _peak_j, "speed_ms": _peak_speed, "part": _peak_part, "t": _time}
	_peak_f = 0.0
	_peak_j = 0.0
	_peak_speed = 0.0
	_peak_part = ""
	if f < Tuning.HEAVY_BAG_HIT_MIN_N:
		return
	hits += 1
	best_force_n = maxf(best_force_n, f)
	last_hit = info
	hit.emit(info)


## Цепь звеньями от проушины до ушка (вдоль цепи, по фазе 90° между парами — звенья Chain_Link уже парные).
func _update_chain() -> void:
	if _chain == null:
		return
	var ear := global_transform * Vector3(0, EAR, 0)
	var d := anchor - ear
	var len := d.length()
	var mm := _chain.multimesh
	if len < 0.05:
		mm.visible_instance_count = 0
		return
	var y := d / len
	var x := y.cross(Vector3.BACK).normalized() if absf(y.z) < 0.99 else Vector3.RIGHT
	var z := x.cross(y)
	var b := Basis(x, y, z)
	var n := mini(int(ceil(len / _link_len)), mm.instance_count)
	mm.visible_instance_count = n
	for i in n:
		mm.set_instance_transform(i, Transform3D(b, ear + y * (i * _link_len)))
	_chain.global_transform = Transform3D.IDENTITY


func reset_stats() -> void:
	hits = 0
	best_force_n = 0.0
	last_hit = {}
