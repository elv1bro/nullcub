## Флаг команды в «Захвате флага» (SquadMatch.mode «ctf», docs/plan-demo/SQUAD.md; автор 06.10: «CTF режим я не увидел — добавь»).
## Только вид и состояние; правила (кто берёт, возврат, доставка) — SquadMatch._tick_flags.
##   home    — стоит у своей базы (home), под ним кольцо цвета команды;
##   carried — несёт соперник: флаг над его спиной, следует за торсом;
##   dropped — лежит, где выронили; через left секунд сам уходит домой.
## Вид: древко, полотнище цвета команды (колышется), светящееся навершие и кольцо — читается на общем плане 64-метровой карты.
class_name SquadFlag
extends Node3D

const GROUP := "squad_flag"
const POLE_H := 1.7
const CLOTH := Vector2(0.95, 0.6)
const CARRY_LIFT := 0.55         # над торсом несущего

var team := 0
var state := "home"
var home := Vector3.ZERO
var carrier: Doll = null
## Осталось лежать (с), пока state == "dropped".
var left := 0.0
var _cloth: MeshInstance3D
var _ring: MeshInstance3D
var _t := 0.0


static func make(t: int, at: Vector3) -> SquadFlag:
	var f := SquadFlag.new()
	f.name = "Flag%d" % t
	f.team = t
	f.home = at
	f.position = at
	return f


func _ready() -> void:
	add_to_group(GROUP)
	var c := SquadMatch.team_colour(team)
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.035
	cm.bottom_radius = 0.045
	cm.height = POLE_H
	pole.mesh = cm
	pole.position = Vector3(0.0, POLE_H * 0.5 - 0.6, 0.0)
	pole.material_override = _mat(Color(0.75, 0.72, 0.65), 0.0)
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pole)
	var top := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	top.mesh = sm
	top.position = Vector3(0.0, POLE_H - 0.6, 0.0)
	top.material_override = _mat(c.lightened(0.4), 3.0)
	add_child(top)
	_cloth = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = CLOTH
	pm.subdivide_width = 8
	pm.orientation = PlaneMesh.FACE_Z
	_cloth.mesh = pm
	_cloth.position = Vector3(CLOTH.x * 0.5 + 0.04, POLE_H - 0.6 - CLOTH.y * 0.5 - 0.05, 0.0)
	var cmat := _mat(c, 0.6)
	cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cloth.material_override = cmat
	add_child(_cloth)
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.75
	tm.outer_radius = 0.85
	_ring.mesh = tm
	_ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_ring.material_override = _mat(c.lightened(0.2), 2.0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)


func _mat(c: Color, emission: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	return m


## Несёт d (соперник взял).
func carry(d: Doll) -> void:
	state = "carried"
	carrier = d


## Выронили в точке at.
func drop(at: Vector3) -> void:
	state = "dropped"
	carrier = null
	left = Tuning.SQUAD_FLAG_RETURN_S
	global_position = Vector3(at.x, at.y, 0.0)


func go_home() -> void:
	state = "home"
	carrier = null
	left = 0.0
	global_position = home


## Точка флага для касаний и ботов (у несущего — его центр масс).
func point() -> Vector3:
	if state == "carried" and is_instance_valid(carrier):
		return carrier.centre_of_mass()
	return global_position


func _process(delta: float) -> void:
	_t += delta
	if state == "carried" and is_instance_valid(carrier) and carrier.torso() != null:
		var tp := carrier.torso().global_position
		global_position = Vector3(tp.x, tp.y + CARRY_LIFT, 0.15)
	_ring.visible = state != "carried"
	_ring.scale = Vector3.ONE * (1.0 + 0.08 * sin(_t * 4.0)) if state == "dropped" else Vector3.ONE
	# полотнище колышется: наклон и лёгкий сдвиг по времени (без шейдера — квад гнётся целиком)
	_cloth.rotation = Vector3(0.0, sin(_t * 3.1) * 0.35, sin(_t * 2.3) * 0.06)
	visible = state != "dropped" or left > 3.0 or fmod(_t, 0.3) < 0.2
