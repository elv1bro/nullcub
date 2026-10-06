## Зона гравитации комнаты (docs/plan-demo/PUZZLE.md «Механизмы»): своё поле NullField (Area3D с заменой гравитации, без мембраны) на
## прямоугольник size с центром в origin узла. Ток на входе input — «низ» поворачивается на on_dir, без тока — off_dir; переход плавный
## (NullField.set_field, Tuning.PUZZLE_GRAVITY_BLEND_S). Сила — g_units (по умолчанию как во всём мире: Tuning.GRAVITY).
## На задней стене — знак: круг со стрелкой, куда сейчас «низ» (поворачивается вместе с полем).
## is_on() — поле повёрнуто на on_dir (переход закончен); down() — «низ» сейчас (Vector2, плоскость XY).
class_name PuzzleGravity
extends PuzzlePart

@export var input: NodePath
@export var size := Vector2(16.0, 9.0)
@export var on_dir := Vector2(1.0, 0.0)
@export var off_dir := Vector2(0.0, -1.0)
## Сила поля в G; ≤ 0 — как в мире (Tuning.GRAVITY / Tuning.G_EARTH).
@export var g_units := 0.0
## Сила при токе в G (тяжёлая шахта комнаты 7, PORTAL.md); ≤ 0 — та же g_units (при токе поворачивается только «низ»).
@export var on_g := 0.0
## Знак на задней стене: смещение от центра (м).
@export var sign_offset := Vector3(0.0, 2.5, -0.9)

var field: NullField
var _want := false
var _arrow: Node3D
var _sign_mat: StandardMaterial3D
var _caption: Label3D


func _ready() -> void:
	if g_units <= 0.0:
		g_units = Tuning.GRAVITY / Tuning.G_EARTH
	field = NullField.new()
	field.name = "Field"
	field.membrane_enabled = false
	field.field_g = g_units
	field.field_dir = off_dir
	field.priority = 1
	add_child(field)
	box_shape(field, "Shape", Vector3(size.x, size.y, 4.0), Vector3.ZERO)
	_build_sign()
	reset_state()


func _build_sign() -> void:
	var holder := Node3D.new()
	holder.name = "Sign"
	holder.position = sign_offset
	add_child(holder)
	var disc := MeshInstance3D.new()
	disc.name = "Disc"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.75
	cm.bottom_radius = 0.75
	cm.height = 0.05
	cm.material = flat_material(Color(0.08, 0.09, 0.11), 0.4, 0.6)
	disc.mesh = cm
	disc.rotation_degrees = Vector3(90, 0, 0)
	holder.add_child(disc)
	_sign_mat = glow_material(Color(0.4, 0.8, 1.0), 1.8)
	_arrow = Node3D.new()
	_arrow.name = "Arrow"
	_arrow.position = Vector3(0, 0, 0.05)
	holder.add_child(_arrow)
	var shaft := box_mesh(_arrow, "Shaft", Vector3(0.14, 0.8, 0.04), Vector3(0, 0.12, 0), _sign_mat)
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var head := MeshInstance3D.new()
	head.name = "Head"
	var pm := PrismMesh.new()
	pm.size = Vector3(0.55, 0.4, 0.04)
	pm.material = _sign_mat
	head.mesh = pm
	head.position = Vector3(0, -0.45, 0)
	head.rotation_degrees = Vector3(0, 0, 180)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arrow.add_child(head)
	_caption = label(holder, "Caption", "G", Vector3(0.0, 0.95, 0.06), 44, Color(0.6, 0.85, 1.0))


func reset_state() -> void:
	_want = false
	if field != null:
		field.set_field(g_units, off_dir, 0.0)
	super.reset_state()
	_refresh_visual()


## «Низ» поля сейчас (единичный вектор в плоскости XY).
func down() -> Vector2:
	return field.field_dir.normalized() if field != null else Vector2(0, -1)


func _physics_process(_delta: float) -> void:
	var w := power_of(input)
	if w != _want:
		_want = w
		field.set_field(on_g if (w and on_g > 0.0) else g_units, on_dir if w else off_dir, Tuning.PUZZLE_GRAVITY_BLEND_S)
		sfx("sub", -2.0, 0.7 if w else 0.9)
	_set_on(w and not field.is_shifting())
	_refresh_visual()


func _refresh_visual() -> void:
	if _arrow == null:
		return
	var d := down()
	# стрелка нарисована «вниз» (−Y): поворот так, чтобы −Y смотрел по d
	_arrow.rotation = Vector3(0, 0, atan2(d.x, -d.y))
	var c := Color(1.0, 0.75, 0.25) if _want else Color(0.4, 0.8, 1.0)
	_sign_mat.albedo_color = c
	_sign_mat.emission = c
	if _caption != null:
		_caption.text = ("G ×%s" % str(snappedf(on_g / maxf(g_units, 0.001), 0.1))) if (_want and on_g > 0.0) else "G"
