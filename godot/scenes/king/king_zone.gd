## Зона «гора» режима «Царь горы» (docs/plan-demo/KING.md): светящееся кольцо радиуса Tuning.KING_ZONE_R лицом к камере (как точка
## гонки RacePoint, только большое), тёмная обводка, столб света вверх от центра и точечный свет. Коллизии нет — сквозь неё летают.
## Кто в ней и очки решает KingMatch, узел только показывает (каждый кадр читает матч: bind(match)):
##   • цвет — свободна: голубой; один внутри: его цвет; двое и больше («спорная»): красный; с короной — золотая обводка ярче;
##   • за KING_ZONE_WARN_S до переезда (KingMatch.warning) кольцо мигает;
##   • призрак (ghost = true): второй такой же узел — виден только при предупреждении, стоит на следующей точке, тусклый и пульсирует.
## Для камеры площадки (группа фокуса) и стрелки за кадром (offscreen_markers) умеет centre_of_mass(); external_input = true — для
## DynamicCamera это «не человек»; player_index = −1 — подпись стрелки своя (KingMarkers).
class_name KingZone
extends Node3D

const GROUP := "king_zone"
const RING_W := 0.26
const OUTLINE := Color(0.02, 0.05, 0.07)
const BEAM_H := 6.0
const BEAM_R := 0.5
const BLINK_HZ := 4.0
const PULSE_HZ := 1.1

var ghost := false
var external_input := true
var player_index := -1
var km: KingMatch
var colour := KingMatch.ZONE_COLOUR_FREE
var _t := 0.0
var _ring: MeshInstance3D
var _rim: MeshInstance3D
var _beam: MeshInstance3D
var _light: OmniLight3D
var _ring_mat: StandardMaterial3D
var _beam_mat: StandardMaterial3D


func bind(m: KingMatch) -> void:
	km = m


func _ready() -> void:
	if not ghost:
		add_to_group(GROUP)
	var r: float = Tuning.KING_ZONE_R
	_rim = MeshInstance3D.new()
	_rim.name = "Rim"
	var om := TorusMesh.new()
	om.inner_radius = r - RING_W - 0.08
	om.outer_radius = r + 0.08
	om.rings = 48
	om.ring_segments = 6
	_rim.mesh = om
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = OUTLINE
	rm.disable_fog = true
	_rim.material_override = rm
	_rim.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_rim.position = Vector3(0.0, 0.0, -0.02)
	_rim.scale = Vector3(1.0, 0.15, 1.0)
	_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rim)
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	var tm := TorusMesh.new()
	tm.inner_radius = r - RING_W
	tm.outer_radius = r
	tm.rings = 48
	tm.ring_segments = 8
	_ring.mesh = tm
	_ring_mat = _glow(colour, 3.0)
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring.material_override = _ring_mat
	_ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)   # лицом к камере
	_ring.scale = Vector3(1.0, 0.4, 1.0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_beam = MeshInstance3D.new()
	_beam.name = "Beam"
	var cm := CylinderMesh.new()
	cm.top_radius = BEAM_R * 0.6
	cm.bottom_radius = BEAM_R
	cm.height = BEAM_H
	cm.radial_segments = 12
	cm.rings = 1
	_beam.mesh = cm
	_beam_mat = _glow(colour, 1.6)
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.albedo_color.a = 0.22
	_beam.material_override = _beam_mat
	_beam.position = Vector3(0.0, BEAM_H * 0.5, -0.3)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	if not ghost:
		_light = OmniLight3D.new()
		_light.name = "Light"
		_light.omni_range = r * 2.6
		_light.light_energy = 1.4
		_light.shadow_enabled = false
		_light.position = Vector3(0.0, 0.6, 1.2)
		add_child(_light)
	else:
		_ring_mat.albedo_color.a = 0.35
		_beam_mat.albedo_color.a = 0.08
		visible = false


static func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.disable_fog = true
	return m


## Цвет зоны по состоянию матча.
static func colour_for(m: KingMatch) -> Color:
	if m == null:
		return KingMatch.ZONE_COLOUR_FREE
	match m.zone_state:
		"held":
			var c := KingMatch.colour_of(m.holder.player_index) if m.holder != null and is_instance_valid(m.holder) else KingMatch.ZONE_COLOUR_FREE
			return c.lerp(KingMatch.ZONE_COLOUR_CROWN, 0.6) if m.crowned else c.lightened(0.2)
		"contested":
			return KingMatch.ZONE_COLOUR_CONTESTED
	return KingMatch.ZONE_COLOUR_FREE


func _process(delta: float) -> void:
	_t += delta
	if km == null or not is_instance_valid(km):
		return
	if ghost:
		visible = km.warning() and km.play_state == "play"
		if not visible:
			return
		global_position = km.next_centre()
		var k := 0.5 + 0.5 * sin(_t * TAU * PULSE_HZ * 2.0)
		_ring_mat.albedo_color = Color(KingMatch.ZONE_COLOUR_FREE, 0.25 + 0.3 * k)
		_ring_mat.emission = KingMatch.ZONE_COLOUR_FREE
		_ring_mat.emission_energy_multiplier = 1.5 + 1.0 * k
		return
	global_position = km.zone_centre()
	colour = colour_for(km)
	var pulse := 0.5 + 0.5 * sin(_t * TAU * PULSE_HZ)
	var a := 1.0
	if km.warning():
		a = 1.0 if sin(_t * TAU * BLINK_HZ) > 0.0 else 0.25   # мигает перед переездом
	_ring_mat.albedo_color = Color(colour, a)
	_ring_mat.emission = colour
	_ring_mat.emission_energy_multiplier = (2.4 + 1.4 * pulse) * (1.6 if km.crowned else 1.0)
	_beam_mat.albedo_color = Color(colour, 0.14 + 0.1 * pulse)
	_beam_mat.emission = colour
	if _light != null:
		_light.light_color = colour
		_light.light_energy = (1.2 + 0.5 * pulse) * a


## Центр зоны — для камеры и стрелок HUD.
func centre_of_mass(_interpolated := false) -> Vector3:
	return global_position
