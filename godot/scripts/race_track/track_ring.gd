## Кольцо разгона «Гонки: трасса» (docs/plan-demo/RACE_TRACK.md): ориентир линии и бонус — пролетел сквозь (ЦМ ближе Tuning.TRACK_RING_R
## к центру, засчитывает TrackMatch) — +Tuning.TRACK_RING_CHARGE Заряда, каждое кольцо раз на гонщика (до возврата на контрольную точку).
## Вид: светящееся кольцо лицом к камере, в нём — знак Заряда (стрелка-молния); взяли — вспышка цвета взявшего.
class_name TrackRing
extends Node3D

const COLOUR := Color(1.0, 0.78, 0.25)

var _ring_mat: StandardMaterial3D
var _t := 0.0
var _flash := 0.0
var _flash_col := Color.WHITE


func _ready() -> void:
	var r := Tuning.TRACK_RING_R
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = COLOUR
	_ring_mat.emission_enabled = true
	_ring_mat.emission = COLOUR
	_ring_mat.emission_energy_multiplier = 2.4
	_ring_mat.disable_fog = true
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	var om := TorusMesh.new()
	om.inner_radius = r - 0.24
	om.outer_radius = r + 0.06
	om.rings = 32
	om.ring_segments = 6
	rim.mesh = om
	var dark := StandardMaterial3D.new()
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.albedo_color = Color(0.08, 0.05, 0.01)
	rim.material_override = dark
	rim.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	rim.position = Vector3(0.0, 0.0, -0.03)
	rim.scale = Vector3(1.0, 0.2, 1.0)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rim)
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	var tm := TorusMesh.new()
	tm.inner_radius = r - 0.18
	tm.outer_radius = r
	tm.rings = 32
	tm.ring_segments = 8
	ring.mesh = tm
	ring.material_override = _ring_mat
	ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	# внутри — бледный диск: кольцо читается «окном», сквозь которое лететь
	var disc := MeshInstance3D.new()
	disc.name = "Disc"
	var cm := CylinderMesh.new()
	cm.top_radius = r - 0.18
	cm.bottom_radius = r - 0.18
	cm.height = 0.02
	cm.radial_segments = 32
	disc.mesh = cm
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.albedo_color = Color(COLOUR.r, COLOUR.g, COLOUR.b, 0.08)
	dm.disable_fog = true
	disc.material_override = dm
	disc.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	disc.position = Vector3(0.0, 0.0, -0.05)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)


## Кольцо взяли: вспышка цвета взявшего.
func flash(colour: Color) -> void:
	_flash = 1.0
	_flash_col = colour


func _process(delta: float) -> void:
	_t += delta
	var pulse := 0.5 + 0.5 * sin(_t * TAU * 0.9)
	_flash = maxf(_flash - delta * 2.0, 0.0)
	var c := COLOUR.lerp(_flash_col, _flash)
	_ring_mat.albedo_color = c
	_ring_mat.emission = c
	_ring_mat.emission_energy_multiplier = 1.8 + 1.2 * pulse + 4.0 * _flash
