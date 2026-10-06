## Плита (docs/plan-demo/PUZZLE.md «Механизмы»): считает массу тел на себе и даёт ток, пока масса ≥ threshold_kg.
## Узел ставится так, что его локальный +Y — «вверх» плиты: на полу без поворота, на стене (комната с гравитацией вбок) — повёрнутым.
## Дерево строится в _ready: StaticBody3D "Base" (плита толщиной 0.2 м, ширина width), меш накладки "Pad" (проседает на
## Tuning.PUZZLE_PLATE_SINK_M под током), Area3D "Sensor" (над плитой на Tuning.PUZZLE_PLATE_SENSOR_H — ящики стопкой тоже давят),
## лампа "Lamp", полоска заполнения "Bar" и подпись "Kg" «32 / 30 кг» на лицевой стороне.
## Масса: каждое RigidBody3D в датчике медленнее Tuning.PUZZLE_PLATE_REST_SPEED — его масса; деталь куклы — вся кукла (total_mass,
## ~40 кг) один раз, если count_dolls (грузовые весы count_dolls = false — куклы не в счёт). Включение — масса держится над порогом
## PUZZLE_PLATE_ON_S, выключение — под порогом PUZZLE_PLATE_OFF_S (дребезг ящика не моргает дверью). latch — включилась раз и навсегда
## (до сброса комнаты).
class_name PuzzlePlate
extends PuzzlePart

@export var threshold_kg := 30.0
@export var count_dolls := true
@export var width := 2.0
@export var latch := false
## Цвет накладки (грузовые весы — свой, чтобы отличались от кнопок под кукол).
@export var pad_colour := Color(0.95, 0.72, 0.12)

var mass_now := 0.0
## Кто сейчас давит (для проб и HUD): [{body, kg}].
var pressing: Array = []

var _sensor: Area3D
var _pad: MeshInstance3D
var _lamp_mat: StandardMaterial3D
var _bar: MeshInstance3D
var _bar_mat: StandardMaterial3D
var _label: Label3D
var _over_t := 0.0
var _under_t := 0.0
var _sink := 0.0
var _latched := false
## Лампа, полоска и подпись — перед лицевой гранью пола / уступа (твёрдое комнат — глубиной 2.4 м, грань на z = 1.2).
const FRONT_Z := 1.26


func _ready() -> void:
	var base := StaticBody3D.new()
	base.name = "Base"
	add_child(base)
	box_shape(base, "Shape", Vector3(width, 0.2, 2.0), Vector3(0, -0.1, 0))
	box_mesh(base, "Mesh", Vector3(width + 0.2, 0.22, 1.9), Vector3(0, -0.12, 0), flat_material(Color(0.13, 0.14, 0.16), 0.7, 0.45))
	_pad = box_mesh(self, "Pad", Vector3(width - 0.1, 0.08, 1.6), Vector3(0, 0.03, 0), flat_material(pad_colour, 0.2, 0.55))
	_sensor = Area3D.new()
	_sensor.name = "Sensor"
	_sensor.monitorable = false
	add_child(_sensor)
	box_shape(_sensor, "Shape", Vector3(width - 0.05, Tuning.PUZZLE_PLATE_SENSOR_H, 1.8), Vector3(0, Tuning.PUZZLE_PLATE_SENSOR_H * 0.5 + 0.02, 0))
	_lamp_mat = glow_material(COLOUR_OFF, 2.0)
	var lamp := MeshInstance3D.new()
	lamp.name = "Lamp"
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	sm.material = _lamp_mat
	lamp.mesh = sm
	lamp.position = Vector3(width * 0.5 + 0.05, -0.08, FRONT_Z)
	add_child(lamp)
	var track := box_mesh(self, "BarTrack", Vector3(width - 0.3, 0.06, 0.02), Vector3(0, -0.13, FRONT_Z), flat_material(Color(0.04, 0.04, 0.05), 0.0, 0.9))
	track.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar_mat = glow_material(COLOUR_OFF, 1.4)
	_bar = box_mesh(self, "Bar", Vector3(width - 0.3, 0.06, 0.02), Vector3(0, -0.13, FRONT_Z + 0.012), _bar_mat)
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_label = label(self, "Kg", "", Vector3(0, -0.42, FRONT_Z + 0.02), 40, Color(0.92, 0.94, 0.96))
	_refresh_visual()


func reset_state() -> void:
	_latched = false
	_over_t = 0.0
	_under_t = 0.0
	mass_now = 0.0
	pressing.clear()
	super.reset_state()
	_refresh_visual()


func _physics_process(delta: float) -> void:
	mass_now = measure()
	if mass_now >= threshold_kg:
		_over_t += delta
		_under_t = 0.0
	else:
		_under_t += delta
		_over_t = 0.0
	if not _on and _over_t >= Tuning.PUZZLE_PLATE_ON_S:
		_set_on(true)
		if latch:
			_latched = true
		sfx("clank", -2.0, 1.25)
	elif _on and not _latched and _under_t >= Tuning.PUZZLE_PLATE_OFF_S:
		_set_on(false)
		sfx("clank", -6.0, 0.9)
	var want := Tuning.PUZZLE_PLATE_SINK_M if _on else Tuning.PUZZLE_PLATE_SINK_M * 0.35 * clampf(mass_now / maxf(threshold_kg, 1.0), 0.0, 1.0)
	_sink = move_toward(_sink, want, delta * 0.6)
	_refresh_visual()


## Масса на плите сейчас (кг), заодно — список давящих (pressing).
func measure() -> float:
	pressing.clear()
	if _sensor == null or not _sensor.is_inside_tree():
		return 0.0
	var total := 0.0
	var seen := {}
	for b in _sensor.get_overlapping_bodies():
		var rb := b as RigidBody3D
		if rb == null or not is_instance_valid(rb):
			continue
		var d := doll_of(rb)
		if d != null:
			if not count_dolls or seen.has(d) or not d.alive:
				continue
			seen[d] = true
			var t := d.torso() as RigidBody3D if d.has_method("torso") else null
			if t != null and t.linear_velocity.length() > Tuning.PUZZLE_PLATE_REST_SPEED:
				continue
			total += d.total_mass
			pressing.append({"body": d, "kg": d.total_mass})
			continue
		if not rb.freeze and rb.linear_velocity.length() > Tuning.PUZZLE_PLATE_REST_SPEED:
			continue
		total += rb.mass
		pressing.append({"body": rb, "kg": rb.mass})
	return total


func _refresh_visual() -> void:
	if _pad == null:
		return
	_pad.position.y = 0.03 - _sink
	var c := COLOUR_ON if _on else COLOUR_OFF
	_lamp_mat.albedo_color = c
	_lamp_mat.emission = c
	var k := clampf(mass_now / maxf(threshold_kg, 0.01), 0.0, 1.0)
	_bar.scale.x = maxf(k, 0.001)
	_bar.position.x = -(width - 0.3) * 0.5 * (1.0 - k)
	var bc := COLOUR_ON if _on else Color(1.0, 0.75, 0.2)
	_bar_mat.albedo_color = bc
	_bar_mat.emission = bc
	var fmt := tr("%d / %d кг") if count_dolls else tr("%d / %d кг груза")
	_label.text = fmt % [roundi(mass_now), roundi(threshold_kg)]
	_label.modulate = COLOUR_ON.lightened(0.3) if _on else Color(0.92, 0.94, 0.96)
