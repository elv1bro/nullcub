## Корзина команды в «Охоте за головами» (docs/plan-demo/HEADHUNT.md). Только вид и точка: правила (кто и что сдаёт) — HeadhuntMatch
## и HeadCarry (касание любой деталью носителя ближе Tuning.HEADHUNT_BASKET_M к point()). Физики нет: стоит на палубе базы Полигона.
## Вид: чугунный котёл (усечённый конус) с ободом цвета команды, светящееся кольцо на палубе, надпись над корзиной — сколько голов
## сдано (count). Пробы и HUD читают team, point(), count.
class_name HeadBasket
extends Node3D

const GROUP := "head_basket"
const R_TOP := 0.62
const R_BOTTOM := 0.46
const H := 0.78

var team := 0
var home := Vector3.ZERO
## Голов сдано в эту корзину за матч (чужих и своих), для надписи.
var count := 0
var _label: Label3D
var _ring: MeshInstance3D
var _t := 0.0
var _flash := 0.0


static func make(t: int, at: Vector3) -> HeadBasket:
	var b := HeadBasket.new()
	b.name = "Basket%d" % t
	b.team = t
	b.home = Vector3(at.x, at.y, 0.0)
	b.position = b.home
	return b


static func colour_of(t: int) -> Color:
	return Tuning.HEADHUNT_COLORS[clampi(t, 0, Tuning.HEADHUNT_COLORS.size() - 1)]


func _ready() -> void:
	add_to_group(GROUP)
	var c := colour_of(team)
	var pot := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = R_TOP
	cm.bottom_radius = R_BOTTOM
	cm.height = H
	pot.mesh = cm
	pot.position = Vector3(0.0, H * 0.5 - 0.45, 0.0)
	pot.material_override = _mat(Color(0.12, 0.12, 0.13), 0.0, 0.7, 0.45)
	add_child(pot)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = R_TOP - 0.05
	tm.outer_radius = R_TOP + 0.06
	rim.mesh = tm
	rim.position = Vector3(0.0, H - 0.45, 0.0)
	rim.material_override = _mat(c, 1.6, 0.5, 0.2)
	add_child(rim)
	var inner := MeshInstance3D.new()
	var im := CylinderMesh.new()
	im.top_radius = R_TOP - 0.08
	im.bottom_radius = R_TOP - 0.08
	im.height = 0.02
	inner.mesh = im
	inner.position = Vector3(0.0, H - 0.46, 0.0)
	inner.material_override = _mat(Color(0.03, 0.03, 0.035), 0.0, 1.0, 0.0)
	add_child(inner)
	_ring = MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 1.05
	rm.outer_radius = 1.18
	_ring.mesh = rm
	_ring.position = Vector3(0.0, -0.42, 0.0)
	_ring.material_override = _mat(c.lightened(0.2), 2.2, 0.4, 0.0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 52
	_label.pixel_size = 0.006
	_label.outline_size = 12
	_label.modulate = c.lightened(0.35)
	_label.outline_modulate = Color(0.05, 0.04, 0.03)
	_label.position = Vector3(0.0, H + 0.35, 0.2)
	_label.no_depth_test = true
	add_child(_label)
	_refresh()


func _mat(c: Color, emission: float, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	return m


## Точка корзины для касаний и ботов: обод котла.
func point() -> Vector3:
	return global_position + Vector3(0.0, H * 0.5 - 0.2, 0.0)


## Для камеры (DynamicCamera держит узлы с centre_of_mass()).
func centre_of_mass(_interpolated := false) -> Vector3:
	return point()


## Сдали n голов (любых): надпись и вспышка кольца.
func add(n: int) -> void:
	count += n
	_flash = 1.0
	_refresh()


func reset() -> void:
	count = 0
	_flash = 0.0
	_refresh()


func _refresh() -> void:
	if _label != null:
		_label.text = tr("КОРЗИНА · %d") % count


func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(_flash - delta * 2.0, 0.0)
	if _ring != null:
		_ring.scale = Vector3.ONE * (1.0 + 0.05 * sin(_t * 3.0) + 0.25 * _flash)
