## Иконки деталей для полки мастерской — рендер в рантайме через один SubViewport (свой World3D, прозрачный фон), без
## запечённых PNG (на диске места нет, и деталь поменялась — иконка тоже). Очередь: одна деталь за кадр (UPDATE_ONCE →
## RenderingServer.frame_post_draw → Image → ImageTexture в кэш), готовая иконка — сигнал icon_ready.
## Кадр: меш детали (узел Mesh сцены; Mesh_R спрятан) в ортокамере спереди, лёгкий поворот 3/4 для объёма, тёплый ключевой свет
## и холодная подсветка, как в мастерской. В headless (нет рендера) иконок нет — request() всегда null, карточки остаются с подписью.
class_name PartIcons
extends Node

signal icon_ready(part_id: String, tex: Texture2D)

const SIZE := 160
const YAW_DEG := -18.0      # поворот вокруг Y: видно толщину детали
const PITCH_DEG := 8.0
const MARGIN := 1.18        # запас кадра вокруг габарита

var _vp: SubViewport
var _cam: Camera3D
var _holder: Node3D
var _queue: PackedStringArray = []
var _cache: Dictionary = {}     # part id -> ImageTexture
var _busy := false
var _enabled := true
## Живое превью под курсором (UI v0.3: карточка библиотеки — деталь медленно вращается): второй SubViewport, рисуется, только пока
## карточка под мышью.
var _live_vp: SubViewport
var _live_cam: Camera3D
var _live_holder: Node3D
var _live_id := ""
const LIVE_SIZE := 256
const LIVE_SPEED := 0.9   # рад/с


func _ready() -> void:
	_enabled = DisplayServer.get_name() != "headless"
	if not _enabled:
		return
	_vp = SubViewport.new()
	_vp.name = "IconViewport"
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.7, 0.6)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.environment = env
	_cam.position = Vector3(0, 0, 5)
	_cam.far = 20.0
	_vp.add_child(_cam)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -40, 0)
	key.light_energy = 1.5
	key.light_color = Color(1.0, 0.88, 0.72)
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 150, 0)
	rim.light_energy = 0.55
	rim.light_color = Color(0.62, 0.74, 1.0)
	_vp.add_child(rim)
	_holder = Node3D.new()
	_vp.add_child(_holder)
	_live_vp = SubViewport.new()
	_live_vp.name = "LiveViewport"
	_live_vp.size = Vector2i(LIVE_SIZE, LIVE_SIZE)
	_live_vp.own_world_3d = true
	_live_vp.transparent_bg = true
	_live_vp.msaa_3d = Viewport.MSAA_4X
	_live_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_live_vp)
	_live_cam = _cam.duplicate() as Camera3D
	_live_vp.add_child(_live_cam)
	_live_vp.add_child(key.duplicate())
	_live_vp.add_child(rim.duplicate())
	_live_holder = Node3D.new()
	_live_vp.add_child(_live_holder)


## Иконка детали: из кэша, иначе null и деталь встаёт в очередь (придёт icon_ready).
func request(part_id: String) -> Texture2D:
	if _cache.has(part_id):
		return _cache[part_id]
	if _enabled and not _queue.has(part_id):
		_queue.append(part_id)
	return null


## Включить живое превью детали: текстура вьюпорта (карточка показывает её вместо иконки); null — нет рендера (headless).
func live_start(part_id: String) -> Texture2D:
	if not _enabled:
		return null
	if part_id != _live_id:
		for c in _live_holder.get_children():
			c.free()
		var pivot := _mesh_pivot(part_id)
		if pivot == null:
			_live_id = ""
			_live_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			return null
		_live_holder.add_child(pivot)
		_live_holder.rotation_degrees = Vector3(PITCH_DEG, YAW_DEG, 0)
		var box := _visual_aabb(_live_holder, _live_holder.global_transform.affine_inverse())
		pivot.position = -box.get_center()
		var r := box.size.length() * 0.5   # вращается: кадр — по описанной сфере, чтобы углы не срезало
		_live_cam.size = maxf(r * 2.0 * 1.04, 0.05)
		_live_cam.position = Vector3(0, 0, 5.0)
		_live_id = part_id
	_live_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	return _live_vp.get_texture()


func live_stop() -> void:
	if not _enabled:
		return
	_live_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Меш детали на своём узле-опоре (узел Mesh сцены, Mesh_R — нет); null — у детали нет меша.
func _mesh_pivot(part_id: String) -> Node3D:
	var d := BodyBlueprint.part_def(part_id)
	if d == null or d.scene == null:
		return null
	var inst := d.scene.instantiate()
	var mesh := inst.get_node_or_null("Mesh") as Node3D
	if mesh == null:
		inst.free()
		return null
	var xf := mesh.transform
	inst.remove_child(mesh)
	mesh.owner = null
	inst.free()
	var pivot := Node3D.new()
	pivot.add_child(mesh)
	mesh.transform = xf
	return pivot


func pending() -> int:
	return _queue.size() + (1 if _busy else 0)


func _process(delta: float) -> void:
	if _enabled and _live_id != "" and _live_vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
		_live_holder.rotate_y(LIVE_SPEED * delta)
	if not _enabled or _busy or _queue.is_empty():
		return
	var id := _queue[0]
	_queue.remove_at(0)
	_render(id)


func _render(part_id: String) -> void:
	_busy = true
	for c in _holder.get_children():
		c.free()
	var d := BodyBlueprint.part_def(part_id)
	if d == null or d.scene == null:
		_busy = false
		return
	var inst := d.scene.instantiate()
	var mesh := inst.get_node_or_null("Mesh") as Node3D
	if mesh == null:
		inst.free()
		_busy = false
		return
	var xf := mesh.transform
	inst.remove_child(mesh)
	mesh.owner = null
	inst.free()
	var pivot := Node3D.new()
	_holder.add_child(pivot)
	pivot.add_child(mesh)
	mesh.transform = xf
	_holder.rotation_degrees = Vector3(PITCH_DEG, YAW_DEG, 0)
	# габарит в осях камеры → ортокадр по большей стороне, центр — в центр кадра
	var box := _visual_aabb(_holder, _holder.global_transform.affine_inverse())
	var world_box := _holder.transform * box
	pivot.position = -box.get_center()
	world_box = _holder.transform * AABB(box.position - box.get_center(), box.size)
	_cam.size = maxf(maxf(world_box.size.x, world_box.size.y) * MARGIN, 0.05)
	_cam.position = Vector3(world_box.get_center().x, world_box.get_center().y, 5.0)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	if img != null and not img.is_empty():
		var tex := ImageTexture.create_from_image(img)
		_cache[part_id] = tex
		icon_ready.emit(part_id, tex)
	_busy = false


## Объединённый AABB мешей под n в системе to_local (Transform3D мира → системы).
static func _visual_aabb(n: Node, to_local: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is VisualInstance3D and (cur as Node3D).is_visible_in_tree():
			var b := (to_local * (cur as VisualInstance3D).global_transform) * (cur as VisualInstance3D).get_aabb()
			out = b if first else out.merge(b)
			first = false
		for c in cur.get_children():
			stack.append(c)
	return out
