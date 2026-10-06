## N0 в гараже (06.10, автор: «N0 может быть у нас в гараже — помогать нам»; лор — LORE_V2 §2а п. 5: герой с Кешем нашёл старого
## повреждённого N0 и восстановил его). Тот же дрон, что ведёт эфир (scenes/n0/n0.tscn, N0Drone), только уменьшенный: парит рядом
## с тем, на что смотрит герой, — между предметом и камерой, сбоку, чтобы не заслонять его и не залезать под меню справа; поворачивается
## к герою (к камере), реплики субтитров «говорит» (talking + выражение экрана и жест). В мастерской висит у стенда и светит своей
## лампой на куклу («держу свет»), на испытании отлетает к задней стене (за плоскость боя z = 0), на «Выходе» — к рубильнику.
## Полёт — пружина с запаздыванием; скорость и ускорение уходят в N0Drone.set_motion (крылья, ножки).
class_name GarageN0
extends Node3D

const N0_SCENE := preload("res://scenes/n0/n0.tscn")
const SIZE := 0.3                  # модель ~1.2 м → ~0.36 м
const SPRING_W := 3.2              # 1/с
const MAX_SPEED := 3.5
## Подвешенная точка относительно взгляда: доля пути от камеры к предмету, вбок (вправо от линии взгляда), вверх; не ближе
## MIN_FROM_CAM и не дальше MAX_FROM_CAM от глаз (близко — заслоняет кадр, далеко — теряется).
const FRAC := 0.62
const SIDE_M := 0.55
const UP_M := 0.32
const MIN_FROM_CAM := 1.25
const MAX_FROM_CAM := 2.2

var drone: N0Drone
var cam: Camera3D
var target := Vector3.ZERO
var look_point := Vector3.ZERO      # куда смотрит, если не на камеру
var face_camera := true
var lamp: SpotLight3D
var _vel := Vector3.ZERO
var _talk_left := 0.0
var _lamp_on := false
var _bounds := AABB(Vector3(-4.3, 0.6, -2.7), Vector3(8.6, 2.5, 6.0))


func _ready() -> void:
	drone = N0_SCENE.instantiate() as N0Drone
	drone.name = "N0"
	drone.scale = Vector3.ONE * SIZE
	add_child(drone)
	lamp = SpotLight3D.new()
	lamp.name = "WorkLamp"
	lamp.light_color = Color(1.0, 0.86, 0.7)
	lamp.light_energy = 0.0
	lamp.spot_range = 3.2
	lamp.spot_angle = 24.0
	lamp.shadow_enabled = false
	lamp.light_volumetric_fog_energy = 0.6
	add_child(lamp)
	target = global_position


## Повиснуть у предмета subject, на который смотрит камера из cam_pos (side: +1 справа от линии взгляда, −1 слева).
func hover_near(subject: Vector3, cam_pos: Vector3, side := 1.0) -> void:
	var to := subject - cam_pos
	var d := clampf(to.length() * FRAC, minf(MIN_FROM_CAM, to.length() * 0.85), MAX_FROM_CAM)
	var fwd := to.normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var p := cam_pos + fwd * d + right * SIDE_M * side + Vector3.UP * UP_M
	fly_to(p)
	face_camera = true


func fly_to(p: Vector3) -> void:
	target = Vector3(clampf(p.x, _bounds.position.x, _bounds.end.x), clampf(p.y, _bounds.position.y, _bounds.end.y),
		clampf(p.z, _bounds.position.z, _bounds.end.z))


## Сразу в точку (вход в гараж, пробы).
func snap_to(p: Vector3) -> void:
	fly_to(p)
	global_position = target
	_vel = Vector3.ZERO


## Реплика: экран «говорит» (по длине текста), выражение mood с жестом.
func say(text: String, mood := "") -> void:
	if drone == null:
		return
	_talk_left = clampf(text.length() * 0.045, 0.0, 4.0)
	drone.talking = _talk_left > 0.0
	if mood != "" and N0Drone.EXPRESSIONS.has(mood):
		drone.flash_expression(mood, clampf(_talk_left, 1.2, 3.0))


## Лампа «держу свет»: светит на точку at (кукла на стенде); false — гаснет.
func light(on: bool, at := Vector3.ZERO) -> void:
	_lamp_on = on
	if on:
		look_point = at


func _process(delta: float) -> void:
	if drone == null:
		return
	# пружина к цели с ограничением скорости
	var acc := (target - global_position) * SPRING_W * SPRING_W - _vel * 2.0 * SPRING_W
	_vel += acc * delta
	if _vel.length() > MAX_SPEED:
		_vel = _vel.normalized() * MAX_SPEED
	global_position += _vel * delta
	drone.set_motion(_vel, acc)
	# взгляд: на героя (камера) или на точку работы; крен по скорости
	var look := cam.global_position if face_camera and cam != null else look_point
	var to := look - global_position
	var yaw := atan2(to.x, to.z)
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-delta * 5.0))
	rotation.z = lerpf(rotation.z, clampf(-_vel.x * 0.06, -0.3, 0.3), 1.0 - exp(-delta * 4.0))
	if _talk_left > 0.0:
		_talk_left -= delta
		if _talk_left <= 0.0:
			drone.talking = false
	# лампа: из-под корпуса на точку работы
	var want := 1.6 if _lamp_on else 0.0
	lamp.light_energy = lerpf(lamp.light_energy, want, 1.0 - exp(-delta * 4.0))
	lamp.visible = lamp.light_energy > 0.02
	if lamp.visible and look_point.distance_to(global_position) > 0.1:
		lamp.global_position = global_position + Vector3(0, -0.08, 0)
		lamp.look_at(look_point, Vector3.UP if absf((look_point - lamp.global_position).normalized().y) < 0.95 else Vector3.FORWARD)
