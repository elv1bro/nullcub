## Поле гравитации участка «Гонки: трасса» (docs/plan-demo/RACE_TRACK.md): своё поле NullField (Area3D с заменой гравитации, без
## мембраны, приоритет выше мира) на прямоугольник size с центром в origin узла: сила g (в G, 1 G = Tuning.G_EARTH) и направление dir
## (в плоскости экрана; вниз — (0, −1)). g берётся из Tuning по имени константы g_key (TRACK_SIDE_G, TRACK_UP_G, TRACK_HEAVY_G,
## TRACK_PIT_G), чтобы ручку крутили в одном месте. Вид — сетка и бегущие по полю шевроны на задней стенке (track_zone.gdshader);
## тяжёлое поле — красное, вбок и вверх — синее.
class_name TrackZone
extends Node3D

const SHADER := preload("res://scripts/race_track/track_zone.gdshader")

@export var size := Vector2(10.0, 10.0)
@export var dir := Vector2(0.0, -1.0)
## Имя константы Tuning с силой поля в G; пусто — g_units.
@export var g_key := ""
@export var g_units := 0.2
## Глубина задника с шевронами (z).
@export var panel_z := -1.9
## Где подпись силы поля (от центра зоны, м); по умолчанию — у верхнего края посередине.
@export var label_offset := Vector2(INF, INF)

var field: NullField


func _ready() -> void:
	var g := tuning_g(g_key, g_units)
	g_units = g
	field = NullField.new()
	field.name = "Field"
	field.membrane_enabled = false
	field.field_g = g
	field.field_dir = dir
	field.priority = 10
	field.collision_layer = 0
	field.collision_mask = 0xFFFFFFFF
	field.monitorable = false
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var bs := BoxShape3D.new()
	bs.size = Vector3(size.x, size.y, 6.0)
	cs.shape = bs
	field.add_child(cs)
	add_child(field)
	var panel := MeshInstance3D.new()
	panel.name = "Panel"
	var qm := QuadMesh.new()
	qm.size = size
	panel.mesh = qm
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var heavy := dir.y < -0.5 and g > 0.5
	m.set_shader_parameter("colour", Color(1.0, 0.35, 0.25) if heavy else Color(0.35, 0.62, 1.0))
	m.set_shader_parameter("dir", dir.normalized())
	m.set_shader_parameter("size_m", size)
	m.set_shader_parameter("speed", 0.8 + 1.6 * clampf(g, 0.0, 1.5))
	m.set_shader_parameter("strength", clampf(0.4 + g * 0.5, 0.4, 1.0))
	panel.material_override = m
	panel.position = Vector3(0.0, 0.0, panel_z)
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(panel)
	var l := Label3D.new()
	l.name = "Reading"
	l.text = "%.2fG" % g
	l.font_size = 72
	l.pixel_size = 0.01
	l.outline_size = 16
	l.modulate = Color(1.0, 0.55, 0.45) if heavy else Color(0.6, 0.8, 1.0)
	l.outline_modulate = Color(0.0, 0.0, 0.05, 0.9)
	l.shaded = false
	l.double_sided = true
	var lo := label_offset if label_offset.x != INF else Vector2(0.0, size.y * 0.5 - 0.8)
	l.position = Vector3(lo.x, lo.y, panel_z + 0.05)
	add_child(l)


## Сила поля из константы Tuning по имени (нет такой — fallback).
static func tuning_g(key: String, fallback: float) -> float:
	if key == "":
		return fallback
	var scr := load("res://scripts/tuning.gd") as Script
	var consts: Dictionary = scr.get_script_constant_map() if scr != null else {}
	return float(consts.get(key, fallback))


## Прямоугольник поля (мир, плоскость XY).
func rect() -> Rect2:
	return Rect2(Vector2(global_position.x, global_position.y) - size * 0.5, size)


## Ускорение поля (м/с², плоскость XY).
func gravity_vec() -> Vector2:
	return dir.normalized() * g_units * Tuning.G_EARTH
