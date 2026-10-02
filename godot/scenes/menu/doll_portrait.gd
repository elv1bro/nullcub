## Портреты бойцов для экранов эфира в гараже (scenes/menu/campaign_tv_ui.gd): рендер сборки (BodyBlueprint) в рантайме через
## один SubViewport со своим World3D и прозрачным фоном — как PartIcons мастерской, очередь по одному кадру на портрет, кэш по
## ключу. Кукла стоит как StandDoll мастерской: тела заморожены, суставы отцеплены, поза покоя. Камера — перспектива спереди,
## чуть снизу, боец по высоте целиком, тёплый ключ и холодный контр. Нет рендера (headless) — request() всегда null,
## экран рисует заглушку-силуэт.
class_name DollPortrait
extends Node

signal portrait_ready(key: String, tex: Texture2D)

const MODULAR_DOLL := preload("res://scenes/body/modular_doll.tscn")
const POSE_GROUPS := ["Neck", "Shoulder", "Elbow", "Hip", "Knee", "Wrist", "Ankle"]
const SIZE := Vector2i(512, 768)
const FOV := 24.0

var _vp: SubViewport
var _cam: Camera3D
var _holder: Node3D
var _queue: Array = []              # [{key, bp}]
var _cache: Dictionary = {}         # ключ → ImageTexture
var _busy := false
var _enabled := true
var _warm := false                  # первый рендер SubViewport за сессию выходит с неустановленной камерой — делаем прогревочный


class _PreviewBlueprint extends BodyBlueprint:
	func validate() -> PackedStringArray:
		return CraftEdit.structural_errors(self)


func _ready() -> void:
	_enabled = DisplayServer.get_name() != "headless"
	if not _enabled:
		return
	_vp = SubViewport.new()
	_vp.name = "PortraitViewport"
	_vp.size = SIZE
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.58, 0.62)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.environment = env
	_cam.far = 40.0
	_vp.add_child(_cam)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-28, -32, 0)
	key.light_energy = 1.55
	key.light_color = Color(1.0, 0.9, 0.76)
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_energy = 0.9
	rim.light_color = Color(0.6, 0.78, 1.0)
	_vp.add_child(rim)
	_holder = Node3D.new()
	_vp.add_child(_holder)


## Портрет под ключом key: готовый — сразу, иначе null и в очередь (потом сигнал portrait_ready). Пустой/сломанный чертёж — null.
func request(key: String, bp: BodyBlueprint) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	if not _enabled or bp == null:
		return null
	for q in _queue:
		if String(q["key"]) == key:
			return null
	_queue.append({"key": key, "bp": CraftEdit.dup_body(bp)})
	if not _busy:
		_pump.call_deferred()
	return null


func forget(key: String) -> void:
	_cache.erase(key)


func has_portrait(key: String) -> bool:
	return _cache.has(key)


func _pump() -> void:
	if _busy:
		return
	_busy = true
	while not _queue.is_empty():
		var job: Dictionary = _queue.pop_front()
		var tex := await _render(job["bp"] as BodyBlueprint)
		if tex != null:
			_cache[String(job["key"])] = tex
			portrait_ready.emit(String(job["key"]), tex)
	_busy = false


func _render(bp: BodyBlueprint) -> Texture2D:
	var view_bp := _PreviewBlueprint.new()
	view_bp.id = bp.id
	view_bp.title = bp.title
	view_bp.energy_budget = 100000
	view_bp.nodes = CraftEdit._dup_nodes(bp.nodes)
	view_bp.control = bp.control.duplicate()
	view_bp.control_rmb = bp.control_rmb.duplicate()
	if CraftEdit.structural_errors(view_bp).size() > 0 or view_bp.nodes.is_empty():
		return null
	var d := MODULAR_DOLL.instantiate() as ModularDoll
	d.blueprint = view_bp
	d.external_input = true
	d.control_enabled = false
	d.player_index = 0
	_holder.add_child(d)
	d._snap_pose(POSE_GROUPS)
	for b in d.parts.values():
		var rb := b as RigidBody3D
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rb.freeze = true
		rb.collision_layer = 0
		rb.collision_mask = 0
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		for ax in ["x", "y", "z"]:
			rb.set("axis_lock_angular_" + ax, false)
			rb.set("axis_lock_linear_" + ax, false)
	for j in d.joints.values():
		(j as Generic6DOFJoint3D).node_a = NodePath()
		(j as Generic6DOFJoint3D).node_b = NodePath()
	d.set_physics_process(false)
	d.set_process(false)
	await get_tree().process_frame
	var box := _visual_aabb(d)
	if box.size.y < 0.05:
		d.queue_free()
		return null
	var c := box.get_center()
	var half_h := maxf(box.size.y * 0.5, box.size.x * 0.5 * float(SIZE.y) / float(SIZE.x)) * 1.1
	var dist := half_h / tan(deg_to_rad(FOV) * 0.5)
	_cam.global_position = Vector3(c.x, c.y - half_h * 0.06, c.z + dist)
	_cam.look_at(Vector3(c.x, c.y, c.z), Vector3.UP)
	for pass_i in (1 if _warm else 2):
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
	_warm = true
	var img := _vp.get_texture().get_image()
	_holder.remove_child(d)
	d.queue_free()
	return ImageTexture.create_from_image(img)


static func _visual_aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is VisualInstance3D and (cur as Node3D).is_visible_in_tree():
			var b := (cur as VisualInstance3D).global_transform * (cur as VisualInstance3D).get_aabb()
			out = b if first else out.merge(b)
			first = false
		for c in cur.get_children():
			stack.append(c)
	return out
