## Один проход пары порталов (docs/plan-demo/PORTAL.md): щель в поверхности. Создаёт и расставляет PortalPair (сам по себе не ставится).
## Узел — середина щели на поверхности; локальная +Y — нормаль наружу (туда, где тела), +X — вдоль щели, +Z — к камере. Поворот узла —
## только вокруг Z: 0° — пол (нормаль вверх), 180° — потолок, −90° — стена слева (нормаль вправо), 90° — стена справа, любой угол — наклон.
## Строит в _ready:
##   Pocket (StaticBody3D) — карман за щелью: дно на глубине depth и две щеки по краям (заходят в поверхность карты: сборщик вырезает
##     в поверхности проём шириной width, а форму кармана даёт портал); pocket = false — карман у карты свой;
##   Sensor (Area3D) — карман + полоса перед щелью: кого проверять на перенос (PortalPair читает get_overlapping_bodies);
##   вид — скоба рамки на лицевой грани поверхности (контур кармана), кромки по краям щели, «плёнка» поперёк щели, свечение кармана
##     (полосы бегут внутрь), буква прохода, лампа-вспышка. Цвет — цвет пары; погасший — тёмная скоба, без плёнки и свечения.
## Вид сквозь портал не рисуется (решение 06.10): только светящаяся щель и вспышка на переходе.
class_name Portal
extends Node3D

enum Lit { ACTIVE, IDLE, OFF }

## Лицевая грань поверхностей комнат (визуальная глубина твёрдого 2.4 м — грань на z = 1.2), подписи и скоба — чуть впереди.
const FRONT_Z := 1.22
const VIS_DEPTH := 2.4
const SHAPE_DEPTH := 4.0
## Полоса датчика перед щелью, м (кого держать на заметке; переносит всё равно только ЦМ за плоскостью).
const SENSOR_AHEAD := 0.6
const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 colour = vec3(1.0);
uniform float power = 1.0;
uniform float flash = 0.0;
uniform float flow = 1.0;
void fragment() {
	float d = UV.y;
	float fall = pow(1.0 - d, 1.6);
	float bands = 0.5 + 0.5 * sin((d * 7.0 - TIME * 1.8 * flow) * 6.2831);
	float side = smoothstep(0.0, 0.06, UV.x) * smoothstep(0.0, 0.06, 1.0 - UV.x);
	float a = (0.28 * fall + 0.22 * fall * bands) * side * power + flash * (1.0 - 0.6 * d);
	ALBEDO = colour * a;
}
"""

var width := 2.2
var depth := 1.3
var colour := Color(0.72, 0.38, 1.0)
var label_text := "A"
var pocket := true
## Только выход (PortalPair.one_way): не переносит сам, вид — стрелки наружу, полосы бегут к щели, без плёнки, кромка тусклее.
var exit_only := false

var sensor: Area3D
var lit := Lit.ACTIVE
var _glow_mat: ShaderMaterial
var _film: MeshInstance3D
var _film_mat: StandardMaterial3D
var _rim_mat: StandardMaterial3D
var _label: Label3D
var _light: OmniLight3D
var _arrows: Array[Label3D] = []
var _flash := 0.0
var _built := false


func _ready() -> void:
	_build()
	set_lit(lit, true)


func _build() -> void:
	if _built:
		return
	_built = true
	var hw := width * 0.5
	var jamb: float = Tuning.PORTAL_JAMB
	var dark := PuzzlePart.flat_material(Color(0.07, 0.075, 0.09), 0.7, 0.45)
	if pocket:
		var st := StaticBody3D.new()
		st.name = "Pocket"
		add_child(st)
		PuzzlePart.box_shape(st, "Back", Vector3(width + 2.0 * jamb, jamb, SHAPE_DEPTH), Vector3(0, -depth - jamb * 0.5, 0))
		PuzzlePart.box_shape(st, "JambL", Vector3(jamb, depth + jamb, SHAPE_DEPTH), Vector3(-hw - jamb * 0.5, -(depth + jamb) * 0.5, 0))
		PuzzlePart.box_shape(st, "JambR", Vector3(jamb, depth + jamb, SHAPE_DEPTH), Vector3(hw + jamb * 0.5, -(depth + jamb) * 0.5, 0))
		PuzzlePart.box_mesh(st, "BackMesh", Vector3(width + 2.0 * jamb, jamb, VIS_DEPTH), Vector3(0, -depth - jamb * 0.5, 0), dark)
		PuzzlePart.box_mesh(st, "JambLMesh", Vector3(jamb, depth + jamb, VIS_DEPTH), Vector3(-hw - jamb * 0.5, -(depth + jamb) * 0.5, 0), dark)
		PuzzlePart.box_mesh(st, "JambRMesh", Vector3(jamb, depth + jamb, VIS_DEPTH), Vector3(hw + jamb * 0.5, -(depth + jamb) * 0.5, 0), dark)
		# задняя стенка кармана (вид): тёмная, чтобы свечение читалось на любом фоне
		PuzzlePart.box_mesh(self, "PocketBack", Vector3(width, depth, 0.05), Vector3(0, -depth * 0.5, -VIS_DEPTH * 0.5 + 0.03),
			PuzzlePart.flat_material(Color(0.02, 0.02, 0.03), 0.0, 0.9))
	sensor = Area3D.new()
	sensor.name = "Sensor"
	sensor.monitorable = false
	add_child(sensor)
	PuzzlePart.box_shape(sensor, "Shape", Vector3(width + 0.6, depth + 0.6 + SENSOR_AHEAD, 2.0),
		Vector3(0, (SENSOR_AHEAD - depth - 0.6) * 0.5, 0))
	# свечение кармана: квад на лицевой грани, верх — у щели (UV.y = 0), низ — у дна
	var q := MeshInstance3D.new()
	q.name = "Glow"
	var qm := QuadMesh.new()
	qm.size = Vector2(width, depth)
	q.mesh = qm
	q.position = Vector3(0, -depth * 0.5, FRONT_Z - 0.01)
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := Shader.new()
	sh.code = GLOW_SHADER
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = sh
	q.material_override = _glow_mat
	add_child(q)
	# плёнка поперёк щели (видна сверху и сбоку тонкой яркой линией)
	_film_mat = PuzzlePart.glow_material(colour, 2.2)
	_film_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_film_mat.albedo_color = Color(colour, 0.55)
	_film = PuzzlePart.box_mesh(self, "Film", Vector3(width, 0.05, VIS_DEPTH - 0.1), Vector3(0, -0.04, 0), _film_mat)
	_film.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# рамка: кромки по краям щели (поперёк, на всю глубину) и скоба-контур кармана на лицевой грани
	_rim_mat = PuzzlePart.glow_material(colour, 2.0)
	for s in [-1.0, 1.0]:
		var e := PuzzlePart.box_mesh(self, "Edge%s" % ("L" if s < 0 else "R"), Vector3(0.12, 0.1, VIS_DEPTH + 0.06), Vector3(s * (hw + 0.06), 0.0, 0), _rim_mat)
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var bar := PuzzlePart.box_mesh(self, "Bar%s" % ("L" if s < 0 else "R"), Vector3(0.07, depth + 0.07, 0.03),
			Vector3(s * (hw + 0.035), -depth * 0.5 - 0.035, FRONT_Z + 0.02), _rim_mat)
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bottom := PuzzlePart.box_mesh(self, "BarB", Vector3(width + 0.14, 0.07, 0.03), Vector3(0, -depth - 0.035, FRONT_Z + 0.02), _rim_mat)
	bottom.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# буква прохода — на лицевой грани рядом со щелью, всегда прямо (не поворачивается со щелью)
	_label = PuzzlePart.label(self, "Letter", label_text, Vector3(hw + 0.5, -0.5, FRONT_Z + 0.04), 72, colour)
	_label.outline_size = 10
	if exit_only:
		# стрелки «выход»: ▲ в системе щели смотрит по нормали наружу
		for i in 3:
			var ar := PuzzlePart.label(self, "Arrow%d" % i, "▲", Vector3((float(i) - 1.0) * width * 0.28, -depth * 0.45, FRONT_Z + 0.03), 72, colour)
			ar.outline_size = 8
			_arrows.append(ar)
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.position = Vector3(0, 0.5, 0.9)
	_light.light_color = colour
	_light.light_energy = 0.0
	_light.omni_range = 4.0
	_light.shadow_enabled = false
	add_child(_light)
	if _label.is_inside_tree():
		_label.global_rotation = Vector3.ZERO


## Нормаль наружу (мир).
func normal() -> Vector3:
	return global_transform.basis.y.normalized()


## Вдоль щели (мир).
func tangent() -> Vector3:
	return global_transform.basis.x.normalized()


## Точка в системе щели: x — вдоль, y — от плоскости наружу (< 0 — в кармане).
func to_mouth(p: Vector3) -> Vector3:
	return global_transform.affine_inverse() * p


## Точка ушла за плоскость щели в пределах ширины (+ кромка) и не глубже кармана (+ запас): переносить.
func behind(p: Vector3) -> bool:
	var l := to_mouth(p)
	return l.y < 0.0 and l.y > -(depth + 0.6) and absf(l.x) <= width * 0.5 + Tuning.PORTAL_EDGE_SLACK


## Знаковое расстояние до плоскости щели (м; > 0 — перед щелью).
func height_of(p: Vector3) -> float:
	return (p - global_position).dot(normal())


## Карман и щель в плоскости XY (мир): AABB контура — для проб «не вылетел за стены» и камеры.
func pocket_rect() -> Rect2:
	var pts := [Vector3(-width * 0.5, 0, 0), Vector3(width * 0.5, 0, 0), Vector3(-width * 0.5, -depth, 0), Vector3(width * 0.5, -depth, 0)]
	var r := Rect2()
	for i in pts.size():
		var g: Vector3 = global_transform * (pts[i] as Vector3)
		if i == 0:
			r = Rect2(Vector2(g.x, g.y), Vector2.ZERO)
		else:
			r = r.expand(Vector2(g.x, g.y))
	return r


## Тела в датчике (кандидаты на перенос).
func bodies() -> Array:
	if sensor == null or not sensor.is_inside_tree():
		return []
	return sensor.get_overlapping_bodies()


## Вид: ACTIVE — горит (переносит), IDLE — пара под током, но этот выход не выбран (рамка тусклая), OFF — погас.
func set_lit(l: Lit, force := false) -> void:
	if l == lit and not force:
		return
	lit = l
	if _rim_mat == null:
		return
	var k := 1.0
	match l:
		Lit.IDLE:
			k = Tuning.PORTAL_IDLE_GLOW
		Lit.OFF:
			k = 0.0
	if exit_only and k > 0.0:
		k = maxf(Tuning.PORTAL_IDLE_GLOW, k * 0.45)   # выход: кромка тусклее входа
	var rim := colour * k if k > 0.0 else PuzzlePart.COLOUR_IDLE
	_rim_mat.albedo_color = rim
	_rim_mat.emission = rim
	_rim_mat.emission_energy_multiplier = 2.0 if k > 0.0 else 0.0
	_film.visible = l == Lit.ACTIVE and not exit_only
	_glow_mat.set_shader_parameter("flow", -1.0 if exit_only else 1.0)
	for ar in _arrows:
		ar.modulate = colour if l == Lit.ACTIVE else (colour.darkened(0.6) if l == Lit.IDLE else Color(0.4, 0.42, 0.45))
	_glow_mat.set_shader_parameter("colour", Vector3(colour.r, colour.g, colour.b))
	_glow_mat.set_shader_parameter("power", 1.0 if l == Lit.ACTIVE else 0.0)
	_label.modulate = colour if l != Lit.OFF else Color(0.45, 0.47, 0.5)
	_light.light_energy = 0.6 if l == Lit.ACTIVE else 0.0


## Вспышка на переходе (свечение кармана, плёнка, лампа) — гаснет за Tuning.PORTAL_FLASH_S.
func flash() -> void:
	_flash = 1.0
	set_process(true)


func _process(delta: float) -> void:
	if _flash <= 0.0:
		set_process(false)
		return
	_flash = maxf(_flash - delta / maxf(Tuning.PORTAL_FLASH_S, 0.01), 0.0)
	if _glow_mat != null:
		_glow_mat.set_shader_parameter("flash", _flash * 1.4)
	if _light != null:
		_light.light_energy = (0.6 if lit == Lit.ACTIVE else 0.0) + 3.0 * _flash
	if _film_mat != null:
		_film_mat.emission_energy_multiplier = 2.2 + 6.0 * _flash
