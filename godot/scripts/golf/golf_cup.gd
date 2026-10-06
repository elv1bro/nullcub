## Лунка «Гольфа: кукла — мяч» (docs/plan-demo/GOLF.md): чаша-корзина на полу или на полке. Узел стоит в середине дна чаши (плоскость
## z = 0). Две стенки (StaticBody3D) высотой Tuning.GOLF_CUP_DEPTH, внутри — ширина GOLF_CUP_W; дно — пол/полка под ней. Светящийся обод,
## флажок с номером лунки, свет и столб света вверх — лунку видно через весь купол.
## Засчитано, если ЦМ куклы пролежал внутри zone() GOLF_CUP_HOLD_S подряд (считает GolfMatch); centre_of_mass() — точка для камеры
## (группа golf_focus: лунка всегда в кадре).
class_name GolfCup
extends Node3D

const WALL_T := 0.25
const DEPTH_Z := 1.6
const COLOUR := Color(0.35, 1.0, 0.55)
const FLAG_H := 3.2

var number := 1
var _rim_mat: StandardMaterial3D
var _light: OmniLight3D
var _flash := 0.0
var _flash_colour := COLOUR


func _init(hole_number := 1) -> void:
	number = hole_number
	name = "Cup"


func _ready() -> void:
	var w := Tuning.GOLF_CUP_W
	var h := Tuning.GOLF_CUP_DEPTH
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.2, 0.22, 0.25)
	steel.metallic = 0.7
	steel.roughness = 0.4
	_rim_mat = StandardMaterial3D.new()
	_rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rim_mat.albedo_color = COLOUR
	for side in [-1.0, 1.0]:
		var x: float = side * (w * 0.5 + WALL_T * 0.5)
		var body := StaticBody3D.new()
		body.name = "WallL" if side < 0.0 else "WallR"
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(WALL_T, h, DEPTH_Z)
		cs.shape = bs
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = bs.size
		mi.mesh = bm
		mi.material_override = steel
		body.add_child(mi)
		body.position = Vector3(x, h * 0.5, 0.0)
		add_child(body)
		var rim := MeshInstance3D.new()   # обод: светящаяся кромка стенки
		var rm := BoxMesh.new()
		rm.size = Vector3(WALL_T + 0.06, 0.1, DEPTH_Z + 0.06)
		rim.mesh = rm
		rim.material_override = _rim_mat
		rim.position = Vector3(x, h + 0.05, 0.0)
		rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(rim)
	# дно: светящаяся полоса (видно, куда попасть)
	var floor_glow := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(w, 0.04, DEPTH_Z)
	floor_glow.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = COLOUR.darkened(0.55)
	floor_glow.material_override = fmat
	floor_glow.position = Vector3(0.0, 0.02, 0.0)
	floor_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_glow)
	# флажок на дальней стенке (за плоскостью кукол — не мешает)
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.04
	pm.bottom_radius = 0.04
	pm.height = FLAG_H
	pole.mesh = pm
	pole.material_override = steel
	pole.position = Vector3(w * 0.5 + WALL_T * 0.5, h + FLAG_H * 0.5, -DEPTH_Z * 0.5 + 0.05)
	add_child(pole)
	var flag := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.1, 0.7)
	flag.mesh = qm
	var flag_mat := StandardMaterial3D.new()
	flag_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flag_mat.albedo_color = Color(1.0, 0.3, 0.2)
	flag_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flag.material_override = flag_mat
	flag.position = pole.position + Vector3(-0.58, FLAG_H * 0.5 - 0.4, 0.0)
	add_child(flag)
	var num := Label3D.new()
	num.text = str(number)
	num.font_size = 96
	num.pixel_size = 0.005
	num.modulate = Color.WHITE
	num.outline_size = 12
	num.position = flag.position + Vector3(0.0, 0.0, 0.02)
	num.no_depth_test = false
	add_child(num)
	_light = OmniLight3D.new()
	_light.light_color = COLOUR
	_light.light_energy = 1.6
	_light.omni_range = 5.0
	_light.position = Vector3(0.0, h * 0.7, 1.0)
	_light.shadow_enabled = false
	add_child(_light)
	# столб света вверх (виден издалека): узкая полоса, гаснет кверху
	var beam := MeshInstance3D.new()
	var qm2 := QuadMesh.new()
	qm2.size = Vector2(w * 0.7, 7.0)
	beam.mesh = qm2
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0))
	grad.set_color(1, Color(1, 1, 1, 1))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	gt.width = 4
	gt.height = 64
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bmat.albedo_color = Color(COLOUR.r, COLOUR.g, COLOUR.b, 0.22)
	bmat.albedo_texture = gt
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = bmat
	beam.position = Vector3(0.0, h + 3.5, -DEPTH_Z * 0.5 - 0.1)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)


## Зона засчитывания (мир, плоскость XY): внутри стенок, от дна до обода + 0.2 м.
func zone() -> Rect2:
	var p := global_position
	return Rect2(p.x - Tuning.GOLF_CUP_W * 0.5, p.y, Tuning.GOLF_CUP_W, Tuning.GOLF_CUP_DEPTH + 0.2)


func contains(p: Vector2) -> bool:
	return zone().has_point(p)


## Точка лунки для камеры (DynamicCamera берёт centre_of_mass у узлов группы цели).
func centre_of_mass(_interpolated := false) -> Vector3:
	return global_position + Vector3(0.0, Tuning.GOLF_CUP_DEPTH * 0.5, 0.0)


## Цель прицела бота: над серединой чаши, выше обода (полёт «drop» проходит её уже вниз и падает в чашу).
func aim_point() -> Vector2:
	return Vector2(global_position.x, global_position.y + Tuning.GOLF_CUP_DEPTH + 0.5)


## Вспышка обода цветом игрока (кукла в лунке).
func flash(c: Color) -> void:
	_flash = 1.0
	_flash_colour = c


func _process(delta: float) -> void:
	if _flash <= 0.0:
		return
	_flash = maxf(_flash - delta * 0.8, 0.0)
	_rim_mat.albedo_color = COLOUR.lerp(_flash_colour.lightened(0.3), _flash)
	_light.light_energy = 1.6 + 6.0 * _flash
	_light.light_color = COLOUR.lerp(_flash_colour, _flash)
