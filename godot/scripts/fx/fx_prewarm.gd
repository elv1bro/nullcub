## Прогрев шейдеров эффектов (29.09, замечание критика v3: «фриз ~1 с на первом heavy / крите при холодном кэше»).
## Пайплайн шейдера компилируется при первой ОТРИСОВКЕ: объекты вне кадра (старый прогрев ставил волну на y −500) и материалы,
## которые только созданы, не прогревают. Здесь — крошечные квады (2 мм) с нужными материалами прямо перед текущей камерой на
## FRAMES кадров; невидимы, потом освобождаются сами. Headless и без камеры — ничего не делает.
class_name FxPrewarm
extends RefCounted

const FRAMES := 3
const QUAD_M := 0.002


## Точка перед текущей 3D-камерой (для квадов и тестовой ударной волны); null — камеры нет или headless.
static func camera_point(host: Node) -> Variant:
	if host == null or not host.is_inside_tree() or DisplayServer.get_name() == "headless":
		return null
	var cam := host.get_viewport().get_camera_3d()
	if cam == null:
		return null
	return cam.global_position - cam.global_basis.z * (cam.near + 0.5)


## Нарисовать материалы mats (Material) на квадах перед камерой FRAMES кадров.
static func spatial(host: Node, mats: Array) -> void:
	var p: Variant = camera_point(host)
	if p == null:
		return
	var root := _Life.new()
	root.name = "FxPrewarm"
	host.add_child(root)
	root.global_position = p as Vector3
	for m in mats:
		if not m is Material:
			continue
		var q := QuadMesh.new()
		q.size = Vector2(QUAD_M, QUAD_M)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m as Material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


## Узел, который живёт FRAMES кадров отрисовки.
class _Life extends Node3D:
	var left := FxPrewarm.FRAMES

	func _process(_delta: float) -> void:
		left -= 1
		if left <= 0:
			queue_free()
