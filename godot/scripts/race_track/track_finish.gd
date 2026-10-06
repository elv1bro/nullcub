## Финиш «Гонки: трасса» (docs/plan-demo/RACE_TRACK.md): клетчатая полоса поперёк коридора и надпись. Линия финиша — x узла (мета x
## того же узла читает TrackArena.finish_x); кто её пересёк ЦМ — финишировал (TrackMatch). Узел стоит на полу у линии.
class_name TrackFinish
extends Node3D

@export var gate_h := 12.0

var _flash := 0.0
var _glow: StandardMaterial3D


func _ready() -> void:
	set_meta("x", global_position.x)
	var cells := int(gate_h / 0.5)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := BoxMesh.new()
	q.size = Vector3(0.5, 0.5, 0.06)
	mm.mesh = q
	mm.instance_count = cells * 2
	for i in cells:
		for k in 2:
			var c := Color.WHITE if (i + k) % 2 == 0 else Color(0.05, 0.05, 0.06)
			mm.set_instance_transform(i * 2 + k, Transform3D(Basis.IDENTITY, Vector3(-0.25 + 0.5 * float(k), 0.25 + 0.5 * float(i), -1.0)))
			mm.set_instance_color(i * 2 + k, c)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	var mi := MultiMeshInstance3D.new()
	mi.name = "Checker"
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_glow = StandardMaterial3D.new()
	_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow.albedo_color = Color(1.0, 0.95, 0.7, 0.12)
	_glow.disable_fog = true
	_glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var qm := QuadMesh.new()
	qm.size = Vector2(0.4, gate_h)
	beam.mesh = qm
	beam.material_override = _glow
	beam.position = Vector3(0.0, gate_h * 0.5, -0.3)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	var l := Label3D.new()
	l.name = "Title"
	l.text = tr("ФИНИШ")
	l.font_size = 160
	l.pixel_size = 0.01
	l.outline_size = 28
	l.modulate = Color(1.0, 0.95, 0.75)
	l.outline_modulate = Color(0.05, 0.04, 0.02, 0.9)
	l.position = Vector3(0.0, minf(gate_h - 1.5, 6.5), -0.9)
	l.shaded = false
	l.double_sided = true
	add_child(l)
	var o := OmniLight3D.new()
	o.light_color = Color(1.0, 0.92, 0.7)
	o.light_energy = 2.0
	o.omni_range = 9.0
	o.shadow_enabled = false
	o.position = Vector3(0.0, gate_h * 0.5, 1.5)
	add_child(o)


func flash() -> void:
	_flash = 1.0


func _process(delta: float) -> void:
	if _flash <= 0.0:
		return
	_flash = maxf(_flash - delta * 0.8, 0.0)
	_glow.albedo_color.a = 0.12 + 0.6 * _flash
