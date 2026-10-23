## Зона режима «Захват точек» (docs/plan-demo/DOMINATION.md): светящееся кольцо радиуса Tuning.DOM_ZONE_R лицом к камере, тёмная
## обводка, столб света вверх, точечный свет и большая буква зоны (A / B / C) — как гора «Царя горы» (KingZone).
## Состояние решает DominationMatch, узел только показывает (каждый кадр читает матч):
##   • цвет кольца и столба — владелец (синие / красные), нейтральная — бледно-белая;
##   • прогресс — диск внутри кольца растёт от центра цветом команды, что захватывает (prog_team), у владельца — его запас;
##   • спорная (оба цвета внутри) — кольцо мигает белым.
## Коллизии нет. Для стрелок HUD — centre_of_mass(); external_input = true, player_index = −1 — «не боец».
class_name DominationZone
extends Node3D

const GROUP := "domination_zone"
const RING_W := 0.26
const OUTLINE := Color(0.02, 0.05, 0.07)
const BEAM_H := 7.0
const BEAM_R := 0.55
const BLINK_HZ := 4.0
const PULSE_HZ := 1.1
const NEUTRAL := Color(0.86, 0.9, 0.95)
const OUTLINE_LETTER := Color(0, 0, 0)
const LETTER_H := 1.6               # м: высота буквы (font_size 160 × pixel_size 0.01)

var index := 0
var external_input := true
var player_index := -1
var dm: DominationMatch
var colour := NEUTRAL
## Буква гаснет до этой доли, пока на экране стоит за табло HUD (ставит DominationHud каждый кадр; VISUAL_PASS_2310 D-6).
var letter_alpha_target := 1.0
var _letter_a := 1.0
var _t := 0.0
var _ring: MeshInstance3D
var _rim: MeshInstance3D
var _fill: MeshInstance3D
var _beam: MeshInstance3D
var _light: OmniLight3D
var _letter: Label3D
var _ring_mat: StandardMaterial3D
var _fill_mat: StandardMaterial3D
var _beam_mat: StandardMaterial3D


func bind(m: DominationMatch) -> void:
	dm = m


func _ready() -> void:
	add_to_group(GROUP)
	var r: float = Tuning.DOM_ZONE_R
	_rim = MeshInstance3D.new()
	_rim.name = "Rim"
	var om := TorusMesh.new()
	om.inner_radius = r - RING_W - 0.08
	om.outer_radius = r + 0.08
	om.rings = 56
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
	tm.rings = 56
	tm.ring_segments = 8
	_ring.mesh = tm
	_ring_mat = KingZone._glow(colour, 3.0)
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring.material_override = _ring_mat
	_ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)   # лицом к камере
	_ring.scale = Vector3(1.0, 0.4, 1.0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_fill = MeshInstance3D.new()
	_fill.name = "Fill"
	var fm := CylinderMesh.new()
	fm.top_radius = r - RING_W
	fm.bottom_radius = r - RING_W
	fm.height = 0.02
	fm.radial_segments = 48
	fm.rings = 1
	_fill.mesh = fm
	_fill_mat = KingZone._glow(NEUTRAL, 0.8)
	_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_fill_mat.albedo_color.a = 0.0
	_fill.material_override = _fill_mat
	_fill.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_fill.position = Vector3(0.0, 0.0, -0.6)
	_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fill)
	_beam = MeshInstance3D.new()
	_beam.name = "Beam"
	var cm := CylinderMesh.new()
	cm.top_radius = BEAM_R * 0.6
	cm.bottom_radius = BEAM_R
	cm.height = BEAM_H
	cm.radial_segments = 12
	cm.rings = 1
	_beam.mesh = cm
	_beam_mat = KingZone._glow(colour, 1.6)
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.albedo_color.a = 0.2
	_beam.material_override = _beam_mat
	_beam.position = Vector3(0.0, BEAM_H * 0.5, -0.3)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.omni_range = r * 2.6
	_light.light_energy = 1.2
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 0.6, 1.2)
	add_child(_light)
	_letter = Label3D.new()
	_letter.name = "Letter"
	_letter.text = String(Tuning.DOM_ZONE_NAMES[index]) if index < Tuning.DOM_ZONE_NAMES.size() else "?"
	_letter.font_size = 160
	_letter.pixel_size = 0.01
	_letter.outline_size = 36
	_letter.outline_modulate = Color(OUTLINE_LETTER, 0.85)
	_letter.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_letter.shaded = false
	_letter.no_depth_test = false
	_letter.position = Vector3(0.0, r + 0.9, -0.2)
	add_child(_letter)


## Цвет команды t для зоны (нейтральная — бледно-белая).
static func colour_of(t: int) -> Color:
	return SquadMatch.team_colour(t).lightened(0.25) if t >= 0 else NEUTRAL


func _process(delta: float) -> void:
	_t += delta
	if dm == null or not is_instance_valid(dm) or index >= dm.zones.size():
		return
	var z: Dictionary = dm.zones[index]
	var owner := int(z["owner"])
	var prog := clampf(float(z["prog"]), 0.0, 1.0)
	var contested := bool(z["contested"])
	colour = colour_of(owner)
	var pulse := 0.5 + 0.5 * sin(_t * TAU * PULSE_HZ)
	var ring_c := colour
	if contested and sin(_t * TAU * BLINK_HZ) > 0.0:
		ring_c = Color(1, 1, 1)
	_ring_mat.albedo_color = Color(ring_c, 1.0)
	_ring_mat.emission = ring_c
	_ring_mat.emission_energy_multiplier = (2.2 + 1.2 * pulse) * (1.3 if owner >= 0 else 0.8)
	var fill_t := owner if owner >= 0 else int(z["prog_team"])
	var fc := colour_of(fill_t)
	var s := maxf(prog, 0.001)
	_fill.scale = Vector3(s, 1.0, s)
	_fill_mat.albedo_color = Color(fc, 0.16 + 0.08 * pulse if prog > 0.0 else 0.0)
	_fill_mat.emission = fc
	_beam_mat.albedo_color = Color(colour, (0.14 + 0.1 * pulse) * (1.0 if owner >= 0 else 0.5))
	_beam_mat.emission = colour
	_letter_a = move_toward(_letter_a, letter_alpha_target, delta * 4.0)
	_letter.modulate = Color(ring_c, _letter_a)
	_letter.outline_modulate = Color(OUTLINE_LETTER, 0.85 * _letter_a)
	if _light != null:
		_light.light_color = colour
		_light.light_energy = (0.9 + 0.5 * pulse) * (1.3 if owner >= 0 else 0.7)


## Центр буквы в мире — HUD проверяет, не стоит ли она за табло.
func letter_point() -> Vector3:
	return _letter.global_position if _letter != null else global_position


## Центр зоны — для стрелок HUD.
func centre_of_mass(_interpolated := false) -> Vector3:
	return global_position
