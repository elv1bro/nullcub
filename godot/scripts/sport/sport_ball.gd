## Мяч спорт-зала (docs/plan-demo/SPORT.md): одно тело на все виды спорта, вид и физика — по виду (Tuning.SPORTS).
## RigidBody3D в плоскости боя (z-замок, вращение только вокруг z), CCD, потолок скорости SPORT_BALL_MAX_SPEED. Куклы бьют его
## телом — отдельной кнопки удара нет: чем быстрее влетел, тем дальше улетел мяч. Руками не берётся (meta no_grab → ArmAssist).
## Модели — дети Model_<вид> (Sport_Ball_Foot / _Basket / _Volley из кита зала), видна одна.
## last_touch — кукла, коснувшаяся мяча последней (автор гола); touched — каждое касание куклой (не чаще TOUCH_GAP_S на куклу).
## Для камеры (DynamicCamera, группа target_group площадки) мяч отвечает как кукла: centre_of_mass(), torso(); external_input — true,
## чтобы камера не сочла его «куклой человека».
## Баскетбол: мяч сам «стучит» об пол — после касания пола летит вверх не медленнее floor_kick (Tuning.SPORTS[вид].floor_kick):
## лежащий мяч куклой не поднять (под него не подлезть), а отскакивающий — бьют в воздухе.
## place(pos) ставит мяч на ввод (заморожен), release() отпускает — этим управляет SportMatch.
class_name SportBall
extends RigidBody3D

signal touched(doll: Doll)

const GROUP := "sport_ball"
const TOUCH_GAP_S := 0.15

var sport := "football"
var last_touch: Doll = null
var last_touch_t := -100.0
var touches := 0
## Секунд с последнего касания куклой, пока мяч отпущен (страховка «мяч застрял» — SportMatch).
var untouched_s := 0.0
## Наибольшая скорость мяча с начала розыгрыша (пробы: потолок скорости держится).
var max_speed_seen := 0.0
var external_input := true
## Наименьшая скорость вверх после касания пола (м/с); 0 — обычный отскок.
var floor_kick := 0.0
var floor_kicks := 0
var _time := 0.0
var _touch_at: Dictionary = {}     # instance_id куклы → _time касания


func _ready() -> void:
	add_to_group(GROUP)
	axis_lock_linear_z = true
	axis_lock_angular_x = true
	axis_lock_angular_y = true
	contact_monitor = true
	max_contacts_reported = 6
	continuous_cd = true
	can_sleep = false
	set_meta(&"no_grab", true)
	set_meta(&"snd_mat", SoundMaterial.RUBBER)
	body_entered.connect(_on_body_entered)
	apply_sport(sport)


## Физика и вид мяча по виду спорта.
func apply_sport(id: String) -> void:
	if not Tuning.SPORTS.has(id):
		return
	sport = id
	var s: Dictionary = Tuning.SPORTS[id]
	mass = float(s["mass"])
	gravity_scale = float(s["gravity_scale"])
	linear_damp = float(s["lin_damp"])
	angular_damp = float(s["ang_damp"])
	floor_kick = float(s.get("floor_kick", 0.0))
	var pm := PhysicsMaterial.new()
	pm.bounce = float(s["bounce"])
	pm.friction = float(s["friction"])
	physics_material_override = pm
	for c in get_children():
		if c is Node3D and String(c.name).begins_with("Model_"):
			(c as Node3D).visible = String(c.name) == "Model_" + id


func centre_of_mass() -> Vector3:
	return global_position


func torso() -> RigidBody3D:
	return self


func pos2() -> Vector2:
	return Vector2(global_position.x, global_position.y)


func vel2() -> Vector2:
	return Vector2(linear_velocity.x, linear_velocity.y)


## Мяч на точку ввода: стоит замороженным, пока SportMatch не отпустит.
func place(pos: Vector3) -> void:
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(Basis.IDENTITY, Vector3(pos.x, pos.y, 0.0))
	reset_physics_interpolation()
	last_touch = null
	last_touch_t = -100.0
	untouched_s = 0.0
	max_speed_seen = 0.0
	_touch_at.clear()


func release() -> void:
	freeze = false
	untouched_s = 0.0


func _physics_process(delta: float) -> void:
	_time += delta
	if not freeze:
		untouched_s += delta
		max_speed_seen = maxf(max_speed_seen, linear_velocity.length())


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var v := state.linear_velocity
	var sp := v.length()
	if sp > Tuning.SPORT_BALL_MAX_SPEED:
		state.linear_velocity = v * (Tuning.SPORT_BALL_MAX_SPEED / sp)
	if floor_kick > 0.0 and state.linear_velocity.y < floor_kick:
		for i in state.get_contact_count():
			# пол зала: статика под мячом на уровне пола (кольцо и крыша ворот мяч не подбрасывают)
			if state.get_contact_local_position(i).y < 0.15 and state.get_contact_collider_object(i) is StaticBody3D:
				var kv := state.linear_velocity
				kv.y = floor_kick
				state.linear_velocity = kv
				floor_kicks += 1
				break


func _on_body_entered(body: Node) -> void:
	var d := doll_of(body)
	if d == null or not d.alive:
		return
	var id := d.get_instance_id()
	if _time - float(_touch_at.get(id, -100.0)) < TOUCH_GAP_S:
		last_touch = d
		return
	_touch_at[id] = _time
	last_touch = d
	last_touch_t = _time
	untouched_s = 0.0
	touches += 1
	touched.emit(d)


## Кукла, которой принадлежит тело (часть тела — ребёнок Doll; у ModularDoll детали могут лежать глубже).
static func doll_of(body: Node) -> Doll:
	var n := body
	for _i in 4:
		if n == null:
			return null
		if n is Doll:
			return n
		n = n.get_parent()
	return null
