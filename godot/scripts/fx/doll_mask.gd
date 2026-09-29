## Маска кукол для кадров удара и рентгена крита (HIT_FX.md §11.4). SubViewport «MaskViewport» с камерой-копией текущей камеры
## вьюпорта рисует только визуальный слой MASK_BIT (бит 1 << 18): на время показа бит добавляется MeshInstance3D кукол (Doll.parts
## кукол группы «dolls» и Match.dolls(), найденные в рантайме) и снимается сразу после. Альфа текстуры: 1 — кукла, 0 — фон.
## Сцены кукол не трогаются: меняется только свойство layers инстансов, и только добавленный бит.
## Рендер по требованию, вне показа — UPDATE_DISABLED и ноль затрат:
##   pulse(frames) — на N кадров (impact frame ScreenFx / CritOverlay);
##   hold(key) / release(key) — пока держат (рентген крупного плана CritCinematic).
## Камера маски синхронизируется в _process с process_priority 2000 (после DynamicCamera и CritCinematic 1000) и сразу в pulse/hold.
## Живёт ребёнком HitFxDirector (или CritCinematic без директора), группа doll_mask.
class_name DollMask
extends Node

const GROUP := "doll_mask"
const MASK_BIT := 1 << 18
const RES_SCALE := 0.5
const MAX_W := 1280
const DOLL_GROUP := "dolls"

## Кадров с отрисованной маской (пробы).
var frames_rendered := 0

var _vp: SubViewport
var _cam: Camera3D
var _pulse := 0
var _holds: Dictionary = {}
var _marked: Array = []        # MeshInstance3D, которым добавлен MASK_BIT
var _extra: Array = []         # GeometryInstance3D эффектов, которые всегда в маске (щепки крита)
var _active := false


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 2000
	_vp = SubViewport.new()
	_vp.name = "MaskViewport"
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_vp.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	_vp.positional_shadow_atlas_size = 0
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_vp.use_taa = false
	_vp.audio_listener_enable_3d = false
	_vp.size = Vector2i(4, 4)
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.name = "MaskCam"
	_cam.cull_mask = MASK_BIT
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0, 0, 0, 0)
	_cam.environment = env
	_vp.add_child(_cam)
	_cam.current = true


func _exit_tree() -> void:
	_deactivate()


## Текстура маски (альфа — куклы). Действительна, пока active().
func texture() -> Texture2D:
	return _vp.get_texture() if _vp != null else null


func active() -> bool:
	return _active


## Бит маски стоит у стольких мешей (пробы: вне показа 0).
func marked_count() -> int:
	var n := 0
	for m in _marked:
		if is_instance_valid(m):
			n += 1
	return n


## Маска на ближайшие frames кадров (включая текущий).
func pulse(frames: int) -> void:
	if frames <= 0 or not is_inside_tree():
		return
	_pulse = maxi(_pulse, frames)
	_activate()


func hold(key: String) -> void:
	if not is_inside_tree():
		return
	_holds[key] = true
	_activate()


func release(key: String) -> void:
	_holds.erase(key)
	if _holds.is_empty() and _pulse <= 0:
		_deactivate()


## Узел эффекта (GeometryInstance3D) всегда рисуется в маску (свой бит на нём навсегда): щепки крита видны в рентгене.
func include(g: GeometryInstance3D) -> void:
	if g == null:
		return
	g.layers |= MASK_BIT
	if not _extra.has(g):
		_extra.append(g)


func _activate() -> void:
	_mark()
	_sync()
	if not _active:
		_active = true
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _deactivate() -> void:
	_pulse = 0
	_holds.clear()
	for m in _marked:
		if is_instance_valid(m):
			(m as MeshInstance3D).layers &= ~MASK_BIT
	_marked.clear()
	if _active and _vp != null:
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_active = false


func _process(_delta: float) -> void:
	if not _active:
		return
	if _pulse <= 0 and _holds.is_empty():
		_deactivate()
		return
	if _pulse > 0:
		_pulse -= 1
	_mark()
	_sync()
	frames_rendered += 1


func _dolls() -> Array:
	var out: Array = []
	if not is_inside_tree():
		return out
	for n in get_tree().get_nodes_in_group(DOLL_GROUP):
		if not out.has(n):
			out.append(n)
	var m := get_tree().get_first_node_in_group("match")
	if m != null and m.has_method("dolls"):
		for d in m.call("dolls"):
			if d is Node and not out.has(d):
				out.append(d)
	return out


func _mark() -> void:
	for d in _dolls():
		var parts: Variant = (d as Node).get("parts")
		if not (parts is Dictionary):
			continue
		for b in (parts as Dictionary).values():
			if b is Node and is_instance_valid(b):
				_mark_meshes(b as Node)


func _mark_meshes(n: Node) -> void:
	for c in n.get_children():
		if c.has_meta("hitfx"):
			continue
		if c is MeshInstance3D:
			var m := c as MeshInstance3D
			if m.layers & MASK_BIT == 0:
				m.layers |= MASK_BIT
				_marked.append(m)
		_mark_meshes(c)


func _sync() -> void:
	var vp := get_viewport()
	if vp == null or _cam == null:
		return
	var src := vp.get_camera_3d()
	if src == null or src == _cam:
		return
	var s := vp.get_visible_rect().size
	if s.x >= 2.0 and s.y >= 2.0:
		var w := minf(s.x * RES_SCALE, float(MAX_W))
		var sz := Vector2i(maxi(int(w), 2), maxi(int(round(w * s.y / s.x)), 2))
		if _vp.size != sz:
			_vp.size = sz
	_cam.projection = src.projection
	_cam.keep_aspect = src.keep_aspect
	_cam.fov = src.fov
	_cam.size = src.size
	_cam.near = src.near
	_cam.far = src.far
	_cam.h_offset = src.h_offset
	_cam.v_offset = src.v_offset
	_cam.frustum_offset = src.frustum_offset
	_cam.global_transform = src.global_transform


## Маска у директора (его ребёнок) или любая в дереве; нет — null.
static func find(from: Node) -> DollMask:
	if from == null or not from.is_inside_tree():
		return null
	return from.get_tree().get_first_node_in_group(GROUP) as DollMask
