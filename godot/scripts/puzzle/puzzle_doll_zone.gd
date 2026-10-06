## Место для куклы (docs/plan-demo/PORTAL.md, комната 7): ток, пока ЦМ живой куклы в прямоугольнике size (origin узла — середина низа
## прямоугольника, локально +Y вверх). Без плиты и формы — у плиты вровень с уступом Jolt ловил шов (ящик вставал намертво), а здесь
## по уступу едет чугунный ящик. Включается, когда кукла в зоне Tuning.PUZZLE_PLATE_ON_S, гаснет через PUZZLE_PLATE_OFF_S, как плита.
## Вид: светящаяся полоса по низу зоны на лицевой грани уступа (красная / зелёная) и подпись.
class_name PuzzleDollZone
extends PuzzlePart

@export var size := Vector2(4.0, 2.0)

var _area: Area3D
var _strip_mat: StandardMaterial3D
var _over_t := 0.0
var _under_t := 0.0
## Кукла в зоне сейчас (пробы).
var inside := false
const FRONT_Z := 1.26


func _ready() -> void:
	_area = Area3D.new()
	_area.name = "Area"
	_area.monitorable = false
	add_child(_area)
	box_shape(_area, "Shape", Vector3(size.x, size.y, 2.0), Vector3(0, size.y * 0.5, 0))
	_strip_mat = glow_material(COLOUR_OFF, 1.6)
	# по нижнему краю лицевой грани уступа (выше — полоска и подпись весов, если они на том же уступе)
	var strip := box_mesh(self, "Strip", Vector3(size.x, 0.05, 0.03), Vector3(0, -0.37, FRONT_Z), _strip_mat)
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for s in [-1.0, 1.0]:
		var tick := box_mesh(self, "Tick%s" % ("L" if s < 0 else "R"), Vector3(0.06, 0.3, 0.03), Vector3(s * size.x * 0.5, -0.24, FRONT_Z), _strip_mat)
		tick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label(self, "Caption", tr("КУКЛА СЮДА"), Vector3(-size.x * 0.5 + 0.9, -0.22, FRONT_Z + 0.02), 32, Color(0.92, 0.94, 0.96))
	reset_state()


func reset_state() -> void:
	_over_t = 0.0
	_under_t = 0.0
	inside = false
	super.reset_state()
	_refresh_visual()


func _physics_process(delta: float) -> void:
	inside = false
	var seen := {}
	for b in _area.get_overlapping_bodies():
		var d := doll_of(b)
		if d == null or seen.has(d) or not d.alive:
			continue
		seen[d] = true
		var l := to_local(d.centre_of_mass())
		if absf(l.x) <= size.x * 0.5 and l.y >= 0.0 and l.y <= size.y:
			inside = true
			break
	if inside:
		_over_t += delta
		_under_t = 0.0
		if _over_t >= Tuning.PUZZLE_PLATE_ON_S:
			_set_on(true)
	else:
		_under_t += delta
		_over_t = 0.0
		if _under_t >= Tuning.PUZZLE_PLATE_OFF_S:
			_set_on(false)
	_refresh_visual()


func _refresh_visual() -> void:
	if _strip_mat == null:
		return
	var c := COLOUR_ON if _on else COLOUR_OFF
	_strip_mat.albedo_color = c
	_strip_mat.emission = c
