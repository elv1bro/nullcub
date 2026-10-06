## Точка гонки «Гонка: 10 точек» (docs/plan-demo/RACE.md; автор 06.10: «у всех одни и те же точки: если кто-то взял, то у тебя этой
## точки уже нет, и надо к следующей»). Горящая точка висит над меткой карты (Marker3D площадки, RaceMatch.marks): светящееся кольцо
## лицом к камере и шар внутри, покачивается и мерцает. Коллизии нет — сквозь неё летают, толкать её нечем. Кто её взял, решает
## RaceMatch (любая деталь куклы ближе Tuning.RACE_PICK_M к центру — каждый тик физики), точка только показывает:
##   • появление — раскрывается из нуля за APPEAR_S;
##   • взятие (take) — гаснет у всех, на её месте вспышка цвета взявшего (RaceFlash): кольцо расходится и тает за FLASH_S.
## Для камеры площадки точка умеет centre_of_mass() (DynamicCamera держит в кадре узлы группы фокуса с этим методом) и
## external_input = true (для камеры это «не человек»: главная кукла кадра — по-прежнему игрок).
class_name RacePoint
extends Node3D

const GROUP := "race_point"
const COLOUR := Color(0.3, 1.0, 0.7)
const OUTLINE := Color(0.02, 0.07, 0.05)
const RING_R := 0.66
const RING_W := 0.17
const BALL_R := 0.27
const BOB_M := 0.1
const BOB_HZ := 0.6
const PULSE_HZ := 1.4
const APPEAR_S := 0.3
const FLASH_S := 0.55

## Индекс метки карты (RaceMatch.marks), на которой горит точка.
var mark := -1
var home := Vector3.ZERO
## Для DynamicCamera.is_human(): точка — не кукла человека.
var external_input := true
## Множитель размера вида (снимок карты целиком — крупнее, иначе на 64 м точки в пиксель).
var size_mult := 1.0
var _t := 0.0
var _ring: MeshInstance3D
var _ball: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _ball_mat: StandardMaterial3D


static func make(mark_index: int, at: Vector3) -> RacePoint:
	var p := RacePoint.new()
	p.mark = mark_index
	p.home = Vector3(at.x, at.y, 0.0)
	p.name = "Point%d" % mark_index
	return p


func _ready() -> void:
	add_to_group(GROUP)
	global_position = home
	_ring_mat = _glow(COLOUR, 3.2)
	_ball_mat = _glow(COLOUR.lightened(0.55), 2.2)
	# тёмная обводка за кольцом: точка читается и на небе, и на светлом камне
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	var om := TorusMesh.new()
	om.inner_radius = RING_R - RING_W - 0.05
	om.outer_radius = RING_R + 0.06
	om.rings = 24
	om.ring_segments = 6
	rim.mesh = om
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = OUTLINE
	rm.disable_fog = true
	rim.material_override = rm
	rim.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	rim.position = Vector3(0.0, 0.0, -0.015)
	rim.scale = Vector3(1.0, 0.15, 1.0)   # плоская по глубине и почти в плоскости кольца — в перспективе не съезжает полумесяцем
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rim)
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	var tm := TorusMesh.new()
	tm.inner_radius = RING_R - RING_W
	tm.outer_radius = RING_R
	tm.rings = 24
	tm.ring_segments = 8
	_ring.mesh = tm
	_ring.material_override = _ring_mat
	_ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)   # лицом к камере
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_ball = MeshInstance3D.new()
	_ball.name = "Ball"
	var sm := SphereMesh.new()
	sm.radius = BALL_R
	sm.height = BALL_R * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	_ball.mesh = sm
	_ball.material_override = _ball_mat
	_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ball)
	scale = Vector3.ONE * 0.01


static func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.disable_fog = true
	return m


func _process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / APPEAR_S, 0.0, 1.0)
	scale = Vector3.ONE * maxf(ease(k, 0.4), 0.01) * size_mult
	global_position = home + Vector3(0.0, sin(_t * TAU * BOB_HZ) * BOB_M, 0.0)
	var pulse := 0.5 + 0.5 * sin(_t * TAU * PULSE_HZ)
	_ring_mat.emission_energy_multiplier = 2.4 + 1.6 * pulse
	_ball.scale = Vector3.ONE * (0.85 + 0.3 * pulse)
	_ring.rotation_degrees.z += 50.0 * delta


## Центр точки (физическая метка, без покачивания) — для камеры и стрелок HUD.
func centre_of_mass(_interpolated := false) -> Vector3:
	return home


## Точку взяли: вспышка цвета взявшего на месте точки, сама точка уходит.
func take(colour: Color) -> void:
	var f := RaceFlash.new()
	f.colour = colour
	f.position = home
	var parent := get_parent()
	if parent != null:
		parent.add_child(f)
	queue_free()


## Вспышка взятия: кольцо цвета взявшего расходится втрое и тает, шар — короткая яркая вспышка. Живёт FLASH_S, сама себя убирает.
class RaceFlash extends Node3D:
	var colour := Color.WHITE
	var _t := 0.0
	var _ring: MeshInstance3D
	var _ball: MeshInstance3D
	var _rm: StandardMaterial3D
	var _bm: StandardMaterial3D

	func _ready() -> void:
		name = "RaceFlash"
		_rm = RacePoint._glow(colour, 4.0)
		_rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_bm = RacePoint._glow(colour.lightened(0.5), 5.0)
		_bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = RacePoint.RING_R - 0.1
		tm.outer_radius = RacePoint.RING_R
		_ring.mesh = tm
		_ring.material_override = _rm
		_ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ring)
		_ball = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		_ball.mesh = sm
		_ball.material_override = _bm
		_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ball)

	func _process(delta: float) -> void:
		_t += delta
		var k := clampf(_t / RacePoint.FLASH_S, 0.0, 1.0)
		_ring.scale = Vector3.ONE * (1.0 + 2.2 * ease(k, 0.3))
		_rm.albedo_color.a = 1.0 - k
		_ball.scale = Vector3.ONE * (0.6 + 0.8 * k)
		_bm.albedo_color.a = maxf(1.0 - k * 2.2, 0.0)
		if k >= 1.0:
			queue_free()
