## Контрольная точка «Гонки: трасса» (docs/plan-demo/RACE_TRACK.md): в начале каждого участка. Пролетел (прогресс по линии трассы
## дошёл до неё — считает TrackMatch) — после KO, ямы или «застрял» возвращаешься сюда через Tuning.TRACK_RESPAWN_S. Вид: световые
## ворота поперёк коридора (столбики у пола и потолка, полупрозрачный луч между ними) и номер участка. Узел стоит на полу у ворот
## (origin — x ворот, y пола); места возврата — SLOTS (сдвиг от origin по player_index: позади ворот, корень куклы над полом).
class_name TrackCheckpoint
extends Node3D

const COLOUR := Color(0.35, 0.95, 1.0)
const SLOTS := [Vector2(-4.5, 0.1), Vector2(-3.0, 0.1), Vector2(-1.5, 0.1), Vector2(0.0, 0.1)]

## Номер точки: 0 — старт, 1..5 — начало участков 2..6.
@export var index := 0
## Высота ворот (м от пола) — до потолка коридора.
@export var gate_h := 12.0

var _beam_mat: StandardMaterial3D
var _flash := 0.0


func _ready() -> void:
	if index <= 0:
		return   # старт: ворот нет (линия старта — сами гонщики)
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.albedo_color = Color(COLOUR.r, COLOUR.g, COLOUR.b, 0.16)
	_beam_mat.disable_fog = true
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var qm := QuadMesh.new()
	qm.size = Vector2(0.5, gate_h)
	beam.mesh = qm
	beam.material_override = _beam_mat
	beam.position = Vector3(0.0, gate_h * 0.5, -0.4)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	var post_mat := StandardMaterial3D.new()
	post_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	post_mat.albedo_color = COLOUR
	post_mat.emission_enabled = true
	post_mat.emission = COLOUR
	post_mat.emission_energy_multiplier = 2.5
	for y in [0.15, gate_h - 0.15]:
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.7, 0.3, 1.4)
		post.mesh = bm
		post.material_override = post_mat
		post.position = Vector3(0.0, y, -0.2)
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(post)
	var l := Label3D.new()
	l.name = "Number"
	l.text = str(index + 1)
	l.font_size = 140
	l.pixel_size = 0.01
	l.outline_size = 24
	l.modulate = COLOUR
	l.outline_modulate = Color(0.0, 0.05, 0.08, 0.9)
	l.position = Vector3(0.0, minf(gate_h - 1.2, 4.0), -0.6)
	l.shaded = false
	l.double_sided = true
	add_child(l)


## Место возврата гонщика player_index (корень куклы).
func spawn_for(pi: int) -> Vector3:
	var o: Vector2 = SLOTS[clampi(pi, 0, SLOTS.size() - 1)]
	return global_position + Vector3(o.x, o.y, 0.0)


## Вспышка ворот (человек пролетел).
func flash() -> void:
	_flash = 1.0


func _process(delta: float) -> void:
	if _beam_mat == null or _flash <= 0.0:
		return
	_flash = maxf(_flash - delta * 1.6, 0.0)
	_beam_mat.albedo_color.a = 0.16 + 0.5 * _flash
