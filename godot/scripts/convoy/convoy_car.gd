## Машина «Перегона» (docs/plan-demo/CONVOY.md, MODES_PACK.md §7). Своя физика на наших телах, не VehicleBody3D:
##   • кузов (Chassis) — RigidBody3D Tuning.CONVOY_CHASSIS_MASS, составная форма: рама с полом кузова, задний борт, кабина, бамперы;
##     центр масс опущен (CENTER_OF_MASS_MODE_CUSTOM) — не кувыркается на каждой кочке;
##   • три колеса (Wheel0..2: зад, середина, перёд) — RigidBody3D-сферы на Generic6DOFJoint3D к кузову: по x и z колесо зажато, по y
##     кузова ходит в пределах подвески (лимит сустава), вокруг z крутится свободно; пружина-демпфер подвески — скриптом (сила к колесу
##     и обратная к кузову в точке крепления), мотор — угловой мотор сустава (цель — скорость вращения, предел — момент);
##   • всё в плоскости боя, как куклы: z зажата, повороты только вокруг z. Машине и колёсам — свой вес (× Tuning.CONVOY_CAR_G_SCALE).
## Управление (водитель — кукла в кабине, ввод по её input_prefix): A / D — газ вперёд / назад (мотор держит предел скорости
## CONVOY_MAX_SPEED / REVERSE_SPEED с моментом DRIVE_TORQUE на колесо); W / S — наклон в воздухе (момент на кузов, только когда ни
## одно колесо не касается земли); пробел (у P2 — Enter, действие *_flip) — ручник (мотор держит ноль моментом BRAKE_TORQUE). Без
## водителя машина всегда на ручнике. Пробы ставят external_control и пишут throttle / tilt / handbrake сами.
## Сесть / выйти — enter(doll) / exit_driver(): кукла в кабине — все детали заморожены (кинематика), без коллизий, видна только голова
## за стеклом; каждый тик детали переносятся за кабиной (с упреждением на тик — без отставания от кузова). Масса куклы машине не
## добавляется, толчков нет. Вышла — над кабиной (CONVOY_EXIT_UP_M), со скоростью машины, управление ей возвращается.
## Переворот: «верх» кузова вбок или вниз и машина почти стоит UPRIGHT_S секунд — «кран» (кузов без веса поднимается и
## поворачивается колёсами вниз); не вышло за CRANE_MAX_S — перенос на колёса.
## Камера: centre_of_mass() и torso() — как у куклы, машина входит в кадр через группу цели DynamicCamera.
class_name ConvoyCar
extends Node3D

signal driver_changed(doll: Doll)
signal uprighted(teleported: bool)

const GROUP := "convoy_car"
const NO_GRAB := &"no_grab"
## Знак цели мотора. Качение вправо (+x) — колесо крутится по часовой (ω_z < 0), но мотор Generic6DOFJoint3D на Jolt считает цель
## как вращение кузова (A) относительно колеса (B): цель «вперёд» положительная. Проверено пробой (only=car, «drive_forward»).
const MOTOR_SIGN := 1.0

# --- геометрия кузова (система кузова: x — вперёд, y — вверх; начало — на линии креплений колёс) ---
const FRAME_Y0 := 0.12
const BED_Y := 0.42           ## верх пола кузова
const BED_X0 := -2.3          ## задний край кузова (внешняя сторона борта)
const BED_X1 := 0.7           ## передняя стенка кузова = задняя стенка кабины
const TAIL_T := 0.12
const TAIL_H := 0.56          ## задний борт над полом
const CAB_X1 := 2.25
const CAB_Y1 := 1.95
const DEPTH := 1.2            ## толщина коллизий кузова по z
const DOOR_LOCAL := Vector3(1.45, 1.05, 0.0)
const SEAT_HEAD_LOCAL := Vector3(1.55, 1.5, 0.0)
const EXIT_FROM_LOCAL := Vector3(1.45, 1.2, 0.0)
const BED_TOP := 2.3          ## до этой высоты над осью груз считается «в кузове»
const COM_LOCAL := Vector3(-0.1, 0.35, 0.0)

var chassis: RigidBody3D
var wheels: Array[RigidBody3D] = []
var joints: Array[Generic6DOFJoint3D] = []
## Точки крепления колёс в системе кузова (подвеска на полном ходе вниз — на TRAVEL_DOWN ниже).
var anchors: Array[Vector3] = []

## Ввод: газ −1…1 (вправо +), наклон −1…1 (W +, нос вверх), ручник.
var throttle := 0.0
var tilt := 0.0
var handbrake := true
## Пробы: ввод пишется снаружи, водителя не читаем.
var external_control := false
var driver: Doll = null

## Для проб и HUD: колёс на земле в этом тике, сколько раз поднимал кран / ставил переносом, сила пружин.
var grounded := 0
var flip_t := 0.0
var crane_t := -1.0
var crane_count := 0
var teleport_upright_count := 0
var spring_f: Array = [0.0, 0.0, 0.0]
## Наибольшее отклонение колеса от своей оси (м, по x кузова) за жизнь — «колесо отваливается».
var max_axle_error := 0.0

var _static_off := 0.0        ## колесо под весом машины: смещение от точки крепления (м, по y кузова)
var _seat: Dictionary = {}    ## деталь водителя -> её место относительно головы (без наклона торса)
var _saved: Dictionary = {}   ## деталь -> [collision_layer, collision_mask, freeze, freeze_mode, visible]
var _crane_y := 0.0
var _motor_target := INF
var _motor_limit := INF
var _gravity_off := false


func _ready() -> void:
	add_to_group(GROUP)
	_build()


# ------------------------------------------------------------------ сборка

func _build() -> void:
	var r: float = Tuning.CONVOY_WHEEL_RADIUS
	var load_n: float = Tuning.CONVOY_CHASSIS_MASS * _g() * Tuning.CONVOY_CAR_G_SCALE / float(Tuning.CONVOY_WHEEL_X.size())
	_static_off = clampf(-Tuning.CONVOY_TRAVEL_DOWN + load_n / Tuning.CONVOY_SPRING_K, -Tuning.CONVOY_TRAVEL_DOWN, Tuning.CONVOY_TRAVEL_UP)
	chassis = RigidBody3D.new()
	chassis.name = "Chassis"
	chassis.mass = Tuning.CONVOY_CHASSIS_MASS
	chassis.gravity_scale = Tuning.CONVOY_CAR_G_SCALE
	chassis.axis_lock_linear_z = true
	chassis.axis_lock_angular_x = true
	chassis.axis_lock_angular_y = true
	chassis.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	chassis.center_of_mass = COM_LOCAL
	chassis.continuous_cd = true
	# своё сопротивление вместо общего мира (0.1 — у куклы-«парашюта»): машина 300 кг на 8 м/с теряла бы 0.8 м/с²
	chassis.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	chassis.linear_damp = 0.03
	chassis.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	chassis.angular_damp = 0.3
	chassis.contact_monitor = true
	chassis.max_contacts_reported = 8
	chassis.set_meta(NO_GRAB, true)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	pm.bounce = 0.05
	chassis.physics_material_override = pm
	add_child(chassis)
	_chassis_shapes()
	_chassis_look()
	for i in Tuning.CONVOY_WHEEL_X.size():
		var wx: float = float(Tuning.CONVOY_WHEEL_X[i])
		var anchor := Vector3(wx, 0.0, 0.0)
		anchors.append(anchor)
		var w := _make_wheel(i, r)
		w.position = anchor + Vector3(0.0, _static_off, 0.0)
		add_child(w)
		wheels.append(w)
		var j := Generic6DOFJoint3D.new()
		j.name = "Joint%d" % i
		j.position = w.position
		# по x и z колесо стоит; по y — от полного хода вниз до полного вверх (сустав создан в положении «под весом»)
		j.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		j.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
		j.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
		j.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		j.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -Tuning.CONVOY_TRAVEL_DOWN - _static_off)
		j.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, Tuning.CONVOY_TRAVEL_UP - _static_off)
		j.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		j.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
		j.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
		for ax in ["x", "y"]:
			j.call("set_flag_" + ax, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
			j.call("set_param_" + ax, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
			j.call("set_param_" + ax, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)
		j.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, false)
		j.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, true)
		j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, 0.0)
		j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, Tuning.CONVOY_BRAKE_TORQUE)
		j.exclude_nodes_from_collision = true
		j.node_a = NodePath("../Chassis")
		j.node_b = NodePath("../" + w.name)
		add_child(j)
		joints.append(j)
	for i in wheels.size():
		wheels[i].add_collision_exception_with(chassis)
		for k in range(i + 1, wheels.size()):
			wheels[i].add_collision_exception_with(wheels[k])


static func _g() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity", 2.0))


func _chassis_shapes() -> void:
	var c := chassis
	ConvoyGeo.shape_xy(c, "Frame", BED_X0, CAB_X1, FRAME_Y0, BED_Y, DEPTH)
	ConvoyGeo.shape_xy(c, "Tailgate", BED_X0, BED_X0 + TAIL_T, BED_Y, BED_Y + TAIL_H, DEPTH)
	ConvoyGeo.shape_xy(c, "Cabin", BED_X1, CAB_X1, BED_Y, CAB_Y1, DEPTH)
	ConvoyGeo.shape_xy(c, "BumperF", CAB_X1, CAB_X1 + 0.15, 0.02, 0.55, DEPTH)
	ConvoyGeo.shape_xy(c, "BumperR", BED_X0 - 0.12, BED_X0, 0.02, BED_Y, DEPTH)


func _chassis_look() -> void:
	var v := Node3D.new()
	v.name = "Look"
	chassis.add_child(v)
	var paint := ConvoyGeo.kit("Base_PaintYellow", Color(0.95, 0.75, 0.2))
	var iron := ConvoyGeo.kit("Iron", Color(0.55, 0.56, 0.58))
	var rust := ConvoyGeo.kit("Rust", Color(0.5, 0.3, 0.2))
	var planks := ConvoyGeo.kit("Base_Planks", Color(0.6, 0.45, 0.3))
	var dark := ConvoyGeo.flat(Color(0.08, 0.085, 0.1), 0.5, 0.5)
	ConvoyGeo.box_xy(v, "Frame", BED_X0, CAB_X1, FRAME_Y0, 0.3, 1.0, iron)
	ConvoyGeo.box_xy(v, "Bed", BED_X0, BED_X1, 0.3, BED_Y, 1.1, planks)
	ConvoyGeo.box_xy(v, "Tailgate", BED_X0, BED_X0 + TAIL_T, BED_Y, BED_Y + TAIL_H, 1.1, rust)
	# борта кузова: дальний — во всю высоту (фон для груза), ближний к камере — низкий, чтобы груз был виден
	ConvoyGeo.box_xy(v, "SideBack", BED_X0, BED_X1, BED_Y, BED_Y + TAIL_H, 0.06, rust, -0.52)
	ConvoyGeo.box_xy(v, "SideFront", BED_X0, BED_X1, BED_Y, BED_Y + 0.16, 0.06, rust, 0.52)
	for k in 4:
		var x := lerpf(BED_X0 + 0.4, BED_X1 - 0.25, k / 3.0)
		ConvoyGeo.box_xy(v, "Stake%d" % k, x - 0.04, x + 0.04, BED_Y, BED_Y + TAIL_H, 0.08, iron, 0.52)
	# кабина: низ (дверь), стойки, крыша, стекло
	ConvoyGeo.box_xy(v, "CabLow", BED_X1, CAB_X1, BED_Y, 1.2, DEPTH, paint)
	ConvoyGeo.box_xy(v, "PillarR", BED_X1, BED_X1 + 0.14, 1.2, CAB_Y1, DEPTH, paint)
	ConvoyGeo.box_xy(v, "PillarF", CAB_X1 - 0.16, CAB_X1, 1.2, CAB_Y1, DEPTH, paint)
	ConvoyGeo.box_xy(v, "Roof", BED_X1 - 0.04, CAB_X1 + 0.04, CAB_Y1 - 0.1, CAB_Y1 + 0.02, DEPTH + 0.06, paint)
	ConvoyGeo.box_xy(v, "Glass", BED_X1 + 0.14, CAB_X1 - 0.16, 1.2, CAB_Y1 - 0.1, DEPTH - 0.04, ConvoyGeo.glass())
	ConvoyGeo.box_xy(v, "BackGlass", BED_X1 + 0.14, CAB_X1 - 0.16, 1.2, CAB_Y1 - 0.1, 0.04, dark, -DEPTH * 0.5 + 0.04)
	# дверь (контур и ручка) — сюда подлетать, чтобы сесть
	ConvoyGeo.box_xy(v, "DoorSeamR", 0.98, 1.0, 0.5, 1.75, 0.02, dark, DEPTH * 0.5 + 0.01)
	ConvoyGeo.box_xy(v, "DoorSeamF", 1.94, 1.96, 0.5, 1.75, 0.02, dark, DEPTH * 0.5 + 0.01)
	ConvoyGeo.box_xy(v, "DoorHandle", 1.1, 1.3, 1.02, 1.07, 0.04, iron, DEPTH * 0.5 + 0.02)
	ConvoyGeo.box_xy(v, "BumperF", CAB_X1, CAB_X1 + 0.15, 0.02, 0.55, DEPTH, iron)
	ConvoyGeo.box_xy(v, "BumperR", BED_X0 - 0.12, BED_X0, 0.02, BED_Y, DEPTH, iron)
	ConvoyGeo.box_xy(v, "Lamp", CAB_X1 + 0.0, CAB_X1 + 0.05, 0.78, 0.96, 0.3, ConvoyGeo.glow(Color(1.0, 0.92, 0.6), 2.2), 0.3)
	ConvoyGeo.box_xy(v, "LampR", BED_X0 - 0.14, BED_X0 - 0.1, 0.25, 0.38, 0.25, ConvoyGeo.glow(Color(1.0, 0.2, 0.15), 1.6), 0.3)
	# арки колёс — тёмные полукруги не нужны: колёса и так видны под рамой


func _make_wheel(i: int, r: float) -> RigidBody3D:
	var w := RigidBody3D.new()
	w.name = "Wheel%d" % i
	w.mass = Tuning.CONVOY_WHEEL_MASS
	w.gravity_scale = Tuning.CONVOY_CAR_G_SCALE
	w.axis_lock_linear_z = true
	w.axis_lock_angular_x = true
	w.axis_lock_angular_y = true
	w.continuous_cd = true
	w.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	w.linear_damp = 0.03
	w.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	w.angular_damp = 0.05
	w.contact_monitor = true
	w.max_contacts_reported = 4
	w.set_meta(NO_GRAB, true)
	var pm := PhysicsMaterial.new()
	pm.friction = Tuning.CONVOY_WHEEL_FRICTION
	pm.bounce = 0.0
	w.physics_material_override = pm
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var s := SphereShape3D.new()
	s.radius = r
	cs.shape = s
	w.add_child(cs)
	var tire := ConvoyGeo.kit("Rubber", Color(0.08, 0.08, 0.09))
	var iron := ConvoyGeo.kit("Iron", Color(0.55, 0.56, 0.58))
	var rust := ConvoyGeo.kit("Rust", Color(0.5, 0.3, 0.2))
	ConvoyGeo.disc_mesh(w, "Tire", r, 0.42, Vector3.ZERO, tire)
	ConvoyGeo.disc_mesh(w, "Hub", r * 0.58, 0.46, Vector3.ZERO, iron)
	for k in 3:   # спицы: видно, что колесо крутится
		var sp := ConvoyGeo.box_mesh(w, "Spoke%d" % k, Vector3(r * 1.1, 0.07, 0.05), Vector3(0, 0, 0.24), rust)
		sp.rotation.z = k * PI / 3.0
	ConvoyGeo.disc_mesh(w, "Cap", r * 0.16, 0.5, Vector3.ZERO, rust, 12)
	return w


# ------------------------------------------------------------------ API

func bodies() -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = [chassis]
	out.append_array(wheels)
	return out


## Для камеры (DynamicCamera): видимое положение машины (центр масс кузова).
func centre_of_mass(interpolated := true) -> Vector3:
	if chassis == null:
		return global_position
	var xf := chassis.get_global_transform_interpolated() if interpolated else chassis.global_transform
	return xf * COM_LOCAL


## Для камеры: тело, по скорости которого кадр берёт упреждение.
func torso() -> RigidBody3D:
	return chassis


## Скорость вдоль дороги (+x — вперёд по участку), м/с.
func speed() -> float:
	return chassis.linear_velocity.x if chassis != null else 0.0


func door_global() -> Vector3:
	return chassis.global_transform * DOOR_LOCAL


## Угол кузова вокруг z (0 — колёсами вниз, + — нос вверх), рад.
func angle() -> float:
	var x := chassis.global_basis.x
	return atan2(x.y, x.x)


func is_upside() -> bool:
	return chassis.global_basis.y.y < Tuning.CONVOY_FLIP_UP_Y


## Тело (его центр) — в кузове: между задним бортом и кабиной, от пола до BED_TOP над осью.
func in_bed(b: Node3D) -> bool:
	if b == null or not is_instance_valid(b) or chassis == null:
		return false
	var l := chassis.global_transform.affine_inverse() * b.global_position
	return l.x >= BED_X0 and l.x <= BED_X1 + 0.05 and l.y >= BED_Y - 0.2 and l.y <= BED_TOP


## Колёса на своих осях: отклонение по x кузова < 0.15 м, по y — в ходе подвески (+ запас), нет NaN.
func axles_ok() -> bool:
	for i in wheels.size():
		var w := wheels[i]
		if not is_instance_valid(w) or not w.is_inside_tree():
			return false
		var l := chassis.global_transform.affine_inverse() * w.global_position
		if is_nan(l.x) or is_nan(l.y):
			return false
		var dx := absf(l.x - anchors[i].x)
		if dx > 0.15 or l.y < -Tuning.CONVOY_TRAVEL_DOWN - 0.12 or l.y > Tuning.CONVOY_TRAVEL_UP + 0.12:
			return false
	return true


## Уложить груз в кузов: нижний ряд от заднего борта к кабине, что не влезло — вторым рядом сверху. Скорость — как у машины.
func load_cargo(items: Array) -> void:
	var xf := chassis.global_transform
	var x0 := BED_X0 + TAIL_T + 0.04
	var x := x0
	var top_x := x0
	var low: Array = []   # нижний ряд: [x от, x до, верх]
	for it in items:
		var c := it as ConvoyCargo
		if c == null or not is_instance_valid(c):
			continue
		var w := c.size.x
		var cx := 0.0
		var bottom := BED_Y
		if x + w <= BED_X1 - 0.03:
			cx = x + w * 0.5
			x += w + 0.04
			low.append([cx - w * 0.5, cx + w * 0.5, BED_Y + c.size.y])
		else:
			cx = top_x + w * 0.5
			top_x += w + 0.04
			for u in low:   # второй ряд: на верх того, что под ним
				if float(u[1]) > cx - w * 0.5 and float(u[0]) < cx + w * 0.5:
					bottom = maxf(bottom, float(u[2]))
		var l := Vector3(cx, bottom + c.size.y * 0.5 + 0.01, 0.0)
		var a := ArmAssist.holder_of(c)
		if a != null:
			a.release("reset")
		c.global_transform = Transform3D(xf.basis, xf * l)
		c.linear_velocity = chassis.linear_velocity
		c.angular_velocity = Vector3.ZERO
		c.reset_physics_interpolation()
		c.sleeping = false


func can_enter(d: Doll) -> bool:
	if driver != null or d == null or not is_instance_valid(d) or not d.alive or chassis == null:
		return false
	if crane_t >= 0.0:
		return false
	return d.centre_of_mass().distance_to(door_global()) <= Tuning.CONVOY_ENTER_RADIUS


## Посадить куклу: рука отпускает, управление куклы выключено, детали заморожены без коллизий, видна только голова за стеклом.
func enter(d: Doll) -> bool:
	if not can_enter(d):
		return false
	driver = d
	for c in d.get_children():
		if c is ArmAssist:
			(c as ArmAssist).release("car")
			(c as ArmAssist).clear_target_override()
	d.control_enabled = false
	d.input_vec = Vector2.ZERO
	var head := d.head()
	var t := d.torso()
	var a := atan2(t.global_basis.x.y, t.global_basis.x.x)
	var unrot := Basis(Vector3.BACK, -a)
	_seat.clear()
	_saved.clear()
	for p in d.parts.values():
		var b := p as RigidBody3D
		if b == null or not is_instance_valid(b):
			continue
		_saved[b] = [b.collision_layer, b.collision_mask, b.freeze, b.freeze_mode, b.visible]
		_seat[b] = Transform3D(unrot * b.global_basis, unrot * (b.global_position - head.global_position))
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
		b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		b.freeze = true
		b.collision_layer = 0
		b.collision_mask = 0
		b.visible = b == head
	_place_seat(false)
	for b in _seat:
		(b as RigidBody3D).reset_physics_interpolation()
	throttle = 0.0
	tilt = 0.0
	_wake()
	driver_changed.emit(d)
	return true


## Высадить водителя над кабиной (по «верху» мира — и у перевёрнутой машины), со скоростью машины. Возвращает куклу.
func exit_driver() -> Doll:
	var d := driver
	if d == null:
		return null
	driver = null
	if is_instance_valid(d):
		var head_pos := chassis.global_transform * EXIT_FROM_LOCAL + Vector3(0.0, Tuning.CONVOY_EXIT_UP_M, 0.0)
		var xf := Transform3D(Basis(), head_pos)
		var v := chassis.linear_velocity
		v.z = 0.0
		for b in _seat:
			var rb := b as RigidBody3D
			if not is_instance_valid(rb):
				continue
			var s: Array = _saved[rb]
			rb.global_transform = xf * (_seat[rb] as Transform3D)
			rb.collision_layer = int(s[0])
			rb.collision_mask = int(s[1])
			rb.freeze_mode = s[3]
			rb.freeze = bool(s[2])
			rb.visible = bool(s[4])
			rb.linear_velocity = v
			rb.angular_velocity = Vector3.ZERO
			rb.reset_physics_interpolation()
		d.control_enabled = true
	_seat.clear()
	_saved.clear()
	throttle = 0.0
	tilt = 0.0
	handbrake = true
	driver_changed.emit(null)
	return d


## Перенести машину: кузов в pos (начало кузова, колёсами вниз под углом angle_rad), колёса — на оси под весом, скорости — ноль.
func place(pos: Vector3, angle_rad := 0.0) -> void:
	var xf := Transform3D(Basis(Vector3.BACK, angle_rad), Vector3(pos.x, pos.y, 0.0))
	chassis.global_transform = xf
	chassis.linear_velocity = Vector3.ZERO
	chassis.angular_velocity = Vector3.ZERO
	for i in wheels.size():
		wheels[i].global_transform = xf * Transform3D(Basis(), anchors[i] + Vector3(0.0, _static_off, 0.0))
		wheels[i].linear_velocity = Vector3.ZERO
		wheels[i].angular_velocity = Vector3.ZERO
	for b in bodies():
		b.reset_physics_interpolation()
	if driver != null:
		_place_seat(false)
		for b in _seat:
			(b as RigidBody3D).reset_physics_interpolation()
	flip_t = 0.0
	_wake()


## Высота опоры (статика) под точкой x, ищется лучом сверху вниз от y_from; нет опоры — y_from − 20.
func ground_y(x: float, y_from: float) -> float:
	var space := chassis.get_world_3d().direct_space_state
	var ex: Array[RID] = []
	for b in bodies():
		ex.append(b.get_rid())
	for _k in 8:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, y_from, 0.0), Vector3(x, y_from - 40.0, 0.0))
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		if hit["collider"] is StaticBody3D or hit["collider"] is AnimatableBody3D:
			return float((hit["position"] as Vector3).y)
		ex.append(hit["rid"])
	return y_from - 20.0


func _wake() -> void:
	for b in bodies():
		b.sleeping = false


# ------------------------------------------------------------------ тик

func _physics_process(delta: float) -> void:
	if chassis == null:
		return
	_read_input()
	_tick_seat()
	_tick_springs()
	_tick_motor()
	grounded = 0
	for w in wheels:
		if w.get_contact_count() > 0:
			grounded += 1
	_tick_air()
	_tick_flip(delta)
	for i in wheels.size():
		var l := chassis.global_transform.affine_inverse() * wheels[i].global_position
		max_axle_error = maxf(max_axle_error, absf(l.x - anchors[i].x))


func _read_input() -> void:
	if external_control:
		return
	if driver == null or not is_instance_valid(driver):
		if driver != null:
			driver = null
			_seat.clear()
			_saved.clear()
			driver_changed.emit(null)
		throttle = 0.0
		tilt = 0.0
		handbrake = true
		return
	if driver.external_input:
		return
	var p := driver.input_prefix
	throttle = Input.get_axis(p + "_left", p + "_right")
	tilt = Input.get_axis(p + "_down", p + "_up")
	handbrake = Input.is_action_pressed(p + "_flip")


func _tick_seat() -> void:
	if driver == null or not is_instance_valid(driver):
		return
	if driver.control_enabled:
		driver.control_enabled = false   # Match.begin / рестарт включают управление всем куклам — водитель остаётся в кабине
	_place_seat(true)


## Детали водителя — за кабиной. predict: положение кузова после этого шага физики (скорость × dt), иначе голова отставала бы на тик.
func _place_seat(predict: bool) -> void:
	var xf := chassis.global_transform
	if predict:
		var dt := 1.0 / float(Engine.physics_ticks_per_second)
		var com := xf * COM_LOCAL
		var rot := Basis(Vector3.BACK, chassis.angular_velocity.z * dt)
		var com2 := com + chassis.linear_velocity * dt
		xf = Transform3D(rot * xf.basis, com2 + rot * (xf.origin - com))
	var seat := xf * Transform3D(Basis(), SEAT_HEAD_LOCAL)
	for b in _seat:
		var rb := b as RigidBody3D
		if is_instance_valid(rb):
			rb.global_transform = seat * (_seat[rb] as Transform3D)


## Подвеска: пружина-демпфер по оси y кузова между точкой крепления и колесом (только толкает).
func _tick_springs() -> void:
	var xf := chassis.global_transform
	var up := xf.basis.y
	var com := xf * chassis.center_of_mass
	for i in wheels.size():
		var w := wheels[i]
		var a := xf * anchors[i]
		var off := (w.global_position - a).dot(up)
		var comp := off + Tuning.CONVOY_TRAVEL_DOWN
		var va := chassis.linear_velocity + chassis.angular_velocity.cross(a - com)
		var rel := (w.linear_velocity - va).dot(up)
		var f := clampf(Tuning.CONVOY_SPRING_K * comp + Tuning.CONVOY_SPRING_C * rel, 0.0, Tuning.CONVOY_SPRING_F_MAX)
		spring_f[i] = f
		if f <= 0.0:
			continue
		w.apply_central_force(-up * f)
		chassis.apply_force(up * f, a - xf.origin)


func _tick_motor() -> void:
	var target := 0.0
	var limit: float = Tuning.CONVOY_ROLL_TORQUE
	if handbrake or crane_t >= 0.0:
		limit = Tuning.CONVOY_BRAKE_TORQUE
	elif absf(throttle) > 0.05:
		var vmax: float = Tuning.CONVOY_MAX_SPEED if throttle > 0.0 else Tuning.CONVOY_REVERSE_SPEED
		target = MOTOR_SIGN * signf(throttle) * vmax / Tuning.CONVOY_WHEEL_RADIUS
		limit = Tuning.CONVOY_DRIVE_TORQUE * minf(absf(throttle), 1.0)
	if is_equal_approx(target, _motor_target) and is_equal_approx(limit, _motor_limit):
		return
	_motor_target = target
	_motor_limit = limit
	for j in joints:
		j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, target)
		j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, limit)
	_wake()


## W / S в воздухе: ни одно колесо и кузов не касаются опоры — момент на кузов (нос вверх / вниз).
func _tick_air() -> void:
	if absf(tilt) < 0.05 or grounded > 0 or crane_t >= 0.0:
		return
	if chassis.get_contact_count() > 0:
		return
	var s := signf(tilt)
	if chassis.angular_velocity.z * s < Tuning.CONVOY_AIR_TILT_MAX_W:
		chassis.apply_torque(Vector3(0.0, 0.0, tilt * Tuning.CONVOY_AIR_TILT_TORQUE))


func _tick_flip(delta: float) -> void:
	if crane_t >= 0.0:
		_tick_crane(delta)
		return
	if is_upside() and chassis.linear_velocity.length() < Tuning.CONVOY_FLIP_SPEED:
		flip_t += delta
		if flip_t >= Tuning.CONVOY_UPRIGHT_S:
			start_crane()
	else:
		flip_t = 0.0


## «Кран»: кузов без веса поднимается над землёй на CRANE_LIFT_M, потом поворачивается колёсами вниз и отпускается.
func start_crane() -> void:
	if crane_t >= 0.0:
		return
	crane_t = 0.0
	crane_count += 1
	var p := chassis.global_position
	_crane_y = ground_y(p.x, p.y + 6.0) + Tuning.CONVOY_CRANE_LIFT_M
	_set_gravity(false)
	_wake()


func _tick_crane(delta: float) -> void:
	crane_t += delta
	var p := chassis.global_transform * COM_LOCAL
	var a := angle()
	var lifted := p.y >= _crane_y - 0.3
	var vy := clampf((_crane_y - p.y) * 3.0, -2.0, 3.0)
	chassis.linear_velocity = Vector3(0.0, vy, 0.0)
	var wz := 0.0
	if lifted or crane_t > 1.2:
		wz = clampf(-wrapf(a, -PI, PI) * 4.0, -3.0, 3.0)
	chassis.angular_velocity = Vector3(0.0, 0.0, wz)
	if lifted and absf(wrapf(a, -PI, PI)) < 0.08:
		_end_crane(false)
	elif crane_t > Tuning.CONVOY_CRANE_MAX_S:
		place(Vector3(p.x, _crane_y, 0.0))
		teleport_upright_count += 1
		_end_crane(true)


func _end_crane(teleported: bool) -> void:
	crane_t = -1.0
	flip_t = 0.0
	_set_gravity(true)
	uprighted.emit(teleported)


func _set_gravity(on: bool) -> void:
	_gravity_off = not on
	for b in bodies():
		b.gravity_scale = Tuning.CONVOY_CAR_G_SCALE if on else 0.0


## Сбросить состояние крана и переворота (рестарт участка).
func reset_state() -> void:
	if crane_t >= 0.0:
		crane_t = -1.0
		_set_gravity(true)
	flip_t = 0.0
	throttle = 0.0
	tilt = 0.0
	handbrake = true
