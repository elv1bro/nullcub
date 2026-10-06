## Дверь (docs/plan-demo/PUZZLE.md «Механизмы»): сдвижная створка — AnimatableBody3D "Panel" (sync_to_physics: толкает тела, как
## пресс Свалки), уезжает вверх в стену на height + 0.1 м, пока на входе input есть ток, и опускается без тока. Опускается, только если
## проём пуст (Area3D "Gap": свободных тел нет) — не давит кукол и ящики; на полпути с куклой в проёме ждёт. Узел ставится в проём
## стены (origin — низ проёма по центру толщины стены). Лампа над проёмом: красная — закрыта, зелёная — открыта; подпись «ВЫХОД».
## is_on() — дверь открыта полностью (для логики и проб); open_frac() — доля хода.
class_name PuzzleDoor
extends PuzzlePart

@export var input: NodePath
@export var height := 2.8
@export var thickness := 0.6
## Выход из комнаты (подпись «ВЫХОД» и стрелка); false — внутренняя дверь.
@export var is_exit := true
## Принудительно открыта (пробы, отладка, вход в комнату).
@export var force_open := false

var panel: AnimatableBody3D
var _gap: Area3D
var _lift := 0.0
var _lamp_mat: StandardMaterial3D
var _stripe_mat: StandardMaterial3D


func _ready() -> void:
	panel = AnimatableBody3D.new()
	panel.name = "Panel"
	panel.sync_to_physics = true
	add_child(panel)
	box_shape(panel, "Shape", Vector3(thickness - 0.1, height, 1.9), Vector3(0, height * 0.5, 0))
	box_mesh(panel, "Mesh", Vector3(thickness - 0.12, height - 0.02, 1.85), Vector3(0, height * 0.5, 0),
		flat_material(Color(0.32, 0.34, 0.37), 0.75, 0.35))
	_stripe_mat = glow_material(COLOUR_OFF, 0.9)
	for i in 3:
		var s := box_mesh(panel, "Stripe%d" % i, Vector3(thickness - 0.08, 0.08, 0.02), Vector3(0, height * (0.25 + 0.25 * i), 0.94), _stripe_mat)
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gap = Area3D.new()
	_gap.name = "Gap"
	_gap.monitorable = false
	add_child(_gap)
	box_shape(_gap, "Shape", Vector3(thickness + 0.5, height, 1.8), Vector3(0, height * 0.5, 0))
	_lamp_mat = glow_material(COLOUR_OFF, 2.4)
	var lamp := box_mesh(self, "Lamp", Vector3(0.5, 0.14, 0.1), Vector3(-thickness * 0.5 - 0.1, height + 0.3, 1.0), _lamp_mat)
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if is_exit:
		label(self, "Exit", tr("ВЫХОД"), Vector3(-thickness * 0.5 - 1.05, height + 0.3, 1.0), 44, Color(0.95, 0.96, 0.9))
	reset_state()


func reset_state() -> void:
	_lift = height + 0.1 if force_open else 0.0
	if panel != null:
		panel.position = Vector3(0, _lift, 0)
	_on = not force_open
	_set_on(force_open)
	_refresh_visual()


## Ход створки: 0 — закрыта, 1 — открыта.
func open_frac() -> float:
	return clampf(_lift / (height + 0.1), 0.0, 1.0)


func wants_open() -> bool:
	return force_open or power_of(input)


func _physics_process(delta: float) -> void:
	var top := height + 0.1
	var want := wants_open()
	var was := _lift
	if want:
		_lift = move_toward(_lift, top, Tuning.PUZZLE_DOOR_OPEN_SPEED * delta)
	elif _lift > 0.0 and not _gap_busy():
		_lift = move_toward(_lift, 0.0, Tuning.PUZZLE_DOOR_CLOSE_SPEED * delta)
	if not is_equal_approx(was, _lift):
		panel.position = Vector3(0, _lift, 0)
		if is_zero_approx(was) or is_equal_approx(was, top):
			sfx("scrape", -4.0, 0.8)
		if is_zero_approx(_lift):
			sfx("clank", -2.0, 0.7)
	_set_on(open_frac() >= 0.999)
	_refresh_visual()


## В проёме есть свободное тело (кукла, ящик) — створка не опускается.
func _gap_busy() -> bool:
	for b in _gap.get_overlapping_bodies():
		var rb := b as RigidBody3D
		if rb != null and not rb.freeze:
			return true
	return false


func _refresh_visual() -> void:
	if _lamp_mat == null:
		return
	var c := COLOUR_ON if _lift > 0.05 else COLOUR_OFF
	_lamp_mat.albedo_color = c
	_lamp_mat.emission = c
	_stripe_mat.albedo_color = c.darkened(0.2)
	_stripe_mat.emission = c.darkened(0.2)
