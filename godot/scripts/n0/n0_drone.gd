## N0 — дрон-ведущий NULL Arena (docs/plan-demo/ART_NULL.md, лист 2; лор — LORE_NULL.md §9–10).
## Только поведение: выражение на экране, ливрея, парение. Сцену собирает tools/build_n0.gd, модель — tools/blender/n0_drone.py.
##
## Экран: материал N0_Screen берёт эмиссию из атласа 5 × 2 (assets/models/n0/n0_face_atlas.png); выражение = uv1_offset ячейки.
## Ливрея: основной и акцентный цвет краски (роли N0_Livery / N0_Accent) — свои копии материалов у каждого дрона.
## В бою не участвует: коллизий нет, это Node3D, которую двигает режиссёр/камера (позже — N0 вместо диктора).
class_name N0Drone
extends Node3D

const EXPRESSIONS: Array[String] = ["default", "happy", "excited", "shocked", "curious", "worried", "confused", "angry", "sad", "glitch"]
const ATLAS_COLS := 5
const ATLAS_ROWS := 2
## sRGB: (основной, акцент) — те же числа, что LIVERIES в n0_drone.py
const LIVERIES := {
	"default": [Color8(226, 214, 190), Color8(236, 168, 34)],
	"event": [Color8(196, 38, 34), Color8(236, 214, 190)],
	"support": [Color8(38, 104, 178), Color8(226, 214, 190)],
}
## среднее albedo набора paint_marks: цвет краски = цель / это число (как tint в Blender)
const PAINT_ALBEDO := 0.82

@export var expression: String = "default":
	set(v):
		expression = v
		_apply_expression()
@export var livery: String = "default":
	set(v):
		livery = v
		_apply_livery()
## покачивание, уши, ножки, мерцание двигателя
@export var idle := true
@export var bob_height := 0.035
@export var bob_hz := 0.45

var _t := 0.0
var _screen_mat: StandardMaterial3D
var _livery_mat: StandardMaterial3D
var _accent_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _parts := {}          # имя узла → Node3D
var _rest := {}           # имя узла → исходный Transform3D
var _flash_left := 0.0
var _flash_back := "default"
var _ready_done := false

@onready var model: Node3D = $Model


func _ready() -> void:
	for n in ["N0_Body", "N0_Screen", "N0_Ear_L", "N0_Ear_R", "N0_Legs_L", "N0_Legs_R", "N0_Arm_L", "N0_Arm_R", "N0_Mic"]:
		var node := model.get_node_or_null(n) as Node3D
		if node != null:
			_parts[n] = node
			_rest[n] = node.transform
	_t = randf() * 10.0
	_make_materials()
	_ready_done = true
	_apply_livery()
	_apply_expression()


## Выражение по имени (EXPRESSIONS); неизвестное — false, экран не меняется.
func set_expression(name: String) -> bool:
	if not EXPRESSIONS.has(name):
		return false
	expression = name
	return true


## Показать выражение на secs секунд, затем вернуть прежнее (реакция на удар, голосование).
func flash_expression(name: String, secs: float) -> void:
	if not EXPRESSIONS.has(name):
		return
	if _flash_left <= 0.0:
		_flash_back = expression
	_flash_left = secs
	expression = name


func mesh_nodes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_collect(model, out)
	return out


func screen_uv_offset() -> Vector3:
	return _screen_mat.uv1_offset if _screen_mat != null else Vector3.ZERO


func livery_color() -> Color:
	return _livery_mat.albedo_color if _livery_mat != null else Color.BLACK


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			expression = _flash_back
	if not idle:
		return
	_t += delta
	var w := TAU * bob_hz
	var bob := sin(_t * w) * bob_height
	model.position = Vector3(0.0, bob, 0.0)
	model.rotation = Vector3(sin(_t * w * 0.5) * 0.04, sin(_t * 0.23 * TAU) * 0.06, sin(_t * w + 0.8) * 0.03)
	# уши: плавник отстаёт от корпуса — фаза позже, амплитуда больше
	_swing("N0_Ear_L", Vector3(sin(_t * w - 0.9) * 0.10, 0.0, sin(_t * w * 0.7) * 0.05))
	_swing("N0_Ear_R", Vector3(sin(_t * w - 1.1) * 0.10, 0.0, -sin(_t * w * 0.7 + 0.4) * 0.05))
	_swing("N0_Legs_L", Vector3(-sin(_t * w - 1.4) * 0.12, 0.0, sin(_t * w * 0.5) * 0.04))
	_swing("N0_Legs_R", Vector3(-sin(_t * w - 1.6) * 0.12, 0.0, -sin(_t * w * 0.5) * 0.04))
	_swing("N0_Arm_L", Vector3(sin(_t * w * 0.8 - 0.5) * 0.06, 0.0, 0.0))
	if _glow_mat != null:
		_glow_mat.emission_energy_multiplier = 4.0 + sin(_t * 37.0) * 0.6 + sin(_t * 23.0) * 0.4
	if expression == "glitch" and _screen_mat != null:
		_screen_mat.uv1_offset.x = _cell_offset(expression).x + (randf() - 0.5) * 0.012


func _swing(n: String, euler: Vector3) -> void:
	if not _parts.has(n):
		return
	var rest: Transform3D = _rest[n]
	(_parts[n] as Node3D).transform = Transform3D(rest.basis * Basis.from_euler(euler), rest.origin)


func _make_materials() -> void:
	for mi in mesh_nodes():
		for i in range(mi.mesh.get_surface_count()):
			var m := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if m == null:
				continue
			match m.resource_name:
				"N0_Screen":
					if _screen_mat == null:
						_screen_mat = m.duplicate() as StandardMaterial3D
					mi.set_surface_override_material(i, _screen_mat)
				"N0_Livery":
					if _livery_mat == null:
						_livery_mat = m.duplicate() as StandardMaterial3D
					mi.set_surface_override_material(i, _livery_mat)
				"N0_Accent":
					if _accent_mat == null:
						_accent_mat = m.duplicate() as StandardMaterial3D
					mi.set_surface_override_material(i, _accent_mat)
				"N0_Glow":
					if _glow_mat == null:
						_glow_mat = m.duplicate() as StandardMaterial3D
					mi.set_surface_override_material(i, _glow_mat)


func _apply_expression() -> void:
	if not _ready_done or _screen_mat == null:
		return
	if not EXPRESSIONS.has(expression):
		push_warning("N0: нет выражения «%s»" % expression)
		return
	_screen_mat.uv1_scale = Vector3(1.0 / ATLAS_COLS, 1.0 / ATLAS_ROWS, 1.0)
	_screen_mat.uv1_offset = _cell_offset(expression)


func _cell_offset(name: String) -> Vector3:
	var i := EXPRESSIONS.find(name)
	return Vector3(float(i % ATLAS_COLS) / ATLAS_COLS, float(i / ATLAS_COLS) / ATLAS_ROWS, 0.0)


func _apply_livery() -> void:
	if not _ready_done or not LIVERIES.has(livery):
		return
	var pair: Array = LIVERIES[livery]
	if _livery_mat != null:
		_livery_mat.albedo_color = _paint(pair[0])
	if _accent_mat != null:
		_accent_mat.albedo_color = _paint(pair[1])


static func _paint(c: Color) -> Color:
	var l := c.srgb_to_linear()
	return Color(l.r / PAINT_ALBEDO, l.g / PAINT_ALBEDO, l.b / PAINT_ALBEDO).linear_to_srgb()


func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for c in node.get_children():
		_collect(c, out)
