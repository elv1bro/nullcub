## Послеобразы отлетающей куклы (HIT_FX.md §2.2, §4.2): снимки позы — копии MeshInstance3D частей (Doll.parts), найденных
## в рантайме, с общим мешем и материалом ghost (scenes/fx/shaders/ghost.gdshader: аддитивно, френель, цвет игрока),
## замороженный transform. Модель куклы не известна заранее: скинованные меши (skin / Skeleton3D) и части без видимых
## мешей заменяются мешем коллизии (Shape3D.get_debug_mesh), так что послеобразы есть у любой модели.
## Материалы куклы не трогаются; снимки — дети этого узла под FxRoot директора (не частей).
## Таймлайн — нескалированное время: снимок не чаще interval_ms и не раньше, чем ЦМ сдвинется на min_step_m (в hit-stop
## поза стоит — копии не слипаются), только в окне window_ms; каждый снимок гаснет за fade_ms. После последнего — queue_free.
class_name AfterimageTrail
extends Node3D


func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # двигается в _process (не в физическом тике) — своя интерполяция физики дала бы запаздывание / дрожь

const GHOST_SHADER: Shader = preload("res://scenes/fx/shaders/ghost.gdshader")
const MAX_SNAPSHOTS := 40          # v3: крит-полёт — снимки на всё окно (живых одновременно ≤ fade / interval + 1)
const FORCE_AFTER_INTERVALS := 3.0   # снимок и без сдвига ЦМ, если ждали столько интервалов

static var _mats: Dictionary = {}          # Color.to_html() -> ShaderMaterial
static var _debug_meshes: Dictionary = {}  # Shape3D -> Mesh

var snapshots := 0          # сколько снимков сделано (пробы)
var from_collision := false # хотя бы одна часть взята из коллизии
## Без лимита снимков (BoostFx: пока идёт ускорение): окно закрывает finish().
var endless := false

var _doll: WeakRef
var _count := 3
var _interval_ms := 50.0
var _fade_ms := 150.0
var _window_ms := 400.0
var _min_step := 0.1
var _mat: ShaderMaterial
var _t := 0.0
var _last_ms := -1e9
var _last_com := Vector3.ZERO
var _ghosts: Array = []     # [[Node3D, born_ms]]
var _sources: Array = []    # [[Node3D-источник, Mesh, from_collision]] — найдены один раз при setup


static func ghost_material(colour: Color) -> ShaderMaterial:
	var key := colour.to_html(true)
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = GHOST_SHADER
	m.set_shader_parameter("colour", colour)
	m.render_priority = 6
	_mats[key] = m
	return m


## Сброс кэшей (последний директор уходит из дерева — иначе ресурсы живут до выхода и считаются утечкой).
static func clear_cache() -> void:
	_mats.clear()
	_debug_meshes.clear()


func setup(doll: Doll, count: int, interval_ms: float, fade_ms: float, window_ms: float, colour: Color, min_step_m: float = 0.1) -> void:
	_doll = weakref(doll)
	_count = clampi(count, 1, MAX_SNAPSHOTS)
	_interval_ms = maxf(interval_ms, 1.0)
	_fade_ms = maxf(fade_ms, 1.0)
	_window_ms = window_ms
	_min_step = min_step_m
	_mat = ghost_material(colour)
	top_level = true
	global_transform = Transform3D.IDENTITY
	_sources = collect_sources(doll)
	for s in _sources:
		if bool(s[2]):
			from_collision = true


## Источники снимка: для каждой части — видимые нескинованные MeshInstance3D-потомки; если их нет — формы коллизии.
static func collect_sources(doll: Doll) -> Array:
	var out: Array = []
	if doll == null:
		return out
	for b in doll.parts.values():
		var body := b as Node3D
		if body == null or not is_instance_valid(body):
			continue
		var found := false
		for mi in body.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null or not m.is_visible_in_tree() or _skinned(m):
				continue
			out.append([m, m.mesh, false])
			found = true
		if found:
			continue
		for cs in body.find_children("*", "CollisionShape3D", true, false):
			var c := cs as CollisionShape3D
			if c.shape == null or c.disabled:
				continue
			out.append([c, _debug_mesh(c.shape), true])
	return out


static func _skinned(m: MeshInstance3D) -> bool:
	if m.skin != null:
		return true
	return m.get_node_or_null(m.skeleton) is Skeleton3D


static func _debug_mesh(shape: Shape3D) -> Mesh:
	if not _debug_meshes.has(shape):
		_debug_meshes[shape] = shape.get_debug_mesh()
	return _debug_meshes[shape]


func _doll_ref() -> Doll:
	if _doll == null:
		return null
	var d := _doll.get_ref() as Doll
	if d == null or not is_instance_valid(d) or not d.is_inside_tree():
		return null
	return d


func _process(delta: float) -> void:
	_t += FxClock.real_delta(delta) * 1000.0
	var d := _doll_ref()
	if d != null and (endless or snapshots < _count) and _t <= _window_ms and _t - _last_ms >= _interval_ms:
		var com := d.centre_of_mass(true)
		if snapshots == 0 or com.distance_to(_last_com) >= _min_step or _t - _last_ms >= _interval_ms * FORCE_AFTER_INTERVALS:
			_snapshot()
			_last_ms = _t
			_last_com = com
	var i := 0
	while i < _ghosts.size():
		var g: Node3D = _ghosts[i][0]
		var u := (_t - float(_ghosts[i][1])) / _fade_ms
		if u >= 1.0 or not is_instance_valid(g):
			if is_instance_valid(g):
				g.queue_free()
			_ghosts.remove_at(i)
			continue
		for c in g.get_children():
			(c as GeometryInstance3D).transparency = u * u
		i += 1
	var done_spawning := d == null or (snapshots >= _count and not endless) or _t > _window_ms
	if done_spawning and _ghosts.is_empty():
		queue_free()


func _snapshot() -> void:
	var g := Node3D.new()
	g.name = "Ghost%d" % snapshots
	add_child(g)
	for s in _sources:
		var src := s[0] as Node3D
		if src == null or not is_instance_valid(src) or not src.is_inside_tree():
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = s[1]
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		g.add_child(mi)
		mi.global_transform = src.global_transform
	snapshots += 1
	_ghosts.append([g, _t])


## Мягкий конец (BoostFx): новые снимки не снимаются, живые гаснут сами, узел уходит после последнего.
func finish() -> void:
	_window_ms = _t


## Снять всё сразу (abort директора).
func stop() -> void:
	for e in _ghosts:
		if is_instance_valid(e[0]):
			(e[0] as Node).queue_free()
	_ghosts.clear()
	queue_free()
