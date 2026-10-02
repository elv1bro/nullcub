## Следы отлёта (HIT_FX.md §2.2, §4.2): ленты за ЦМ куклы и за выбранными частями (по именам Doll.parts: Head, Hand_*,
## Foot_*, Torso — без привязки к мешам) + дымный след (клубы dust_puff за ЦМ, пока кукла летит быстрее SMOKE_MIN_SPEED).
## Лента — ImmediateMesh (triangle strip) в мировых координатах в плоскости XY (камера смотрит вдоль −Z): последние
## POINTS точек не старше POINT_LIFE_MS, ширина width → 0 к хвосту, альфа по длине, аддитивно, цвет игрока.
## Время — нескалированное. Живёт life_ms, последние FADE_MS гаснет; клубы дыма — дети FxRoot директора (переживают ленту).
class_name FlightTrail
extends Node3D

const POINTS := 12
const POINT_LIFE_MS := 240.0
const MIN_STEP_M := 0.025
const FADE_MS := 200.0
const COM_WIDTH := 0.3
const COM_ALPHA := 0.45
const PART_WIDTH := 0.14
const PART_ALPHA := 0.9
const SMOKE_INTERVAL_MS := 60.0
const SMOKE_MIN_SPEED := 3.0
const SMOKE_MAX := 8

static var _mat: StandardMaterial3D

var smoke_puffs := 0        # пробы
## Клубов дыма не больше (v3: крит-полёт — на всё окно, HitFxDirector.CRIT_SMOKE_MAX).
var smoke_max := SMOKE_MAX
var tracks := 0             # число лент

var _doll: WeakRef
var _director: Node
var _life_ms := 400.0
var _smoke_ms := 0.0
var _colour := Color.WHITE
var _t := 0.0
var _next_smoke := 0.0
var _tracks: Array = []     # [{body: WeakRef|null, width, alpha, pts: Array[Vector3], ages: Array[float], im: ImmediateMesh}]


static func ribbon_material() -> StandardMaterial3D:
	if _mat == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.vertex_color_use_as_albedo = true
		m.disable_receive_shadows = true
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.render_priority = 5
		_mat = m
	return _mat


static func clear_cache() -> void:
	_mat = null


## part_bases: базовые имена частей (Doll.part_base_name) для узких лент; with_com — широкая лента за ЦМ.
## smoke_ms > 0 — дымный след столько мс (director должен иметь метод puff(pos, normal, k)).
func setup(doll: Doll, part_bases: Array, with_com: bool, life_ms: float, colour: Color, smoke_ms: float = 0.0, director: Node = null) -> void:
	_doll = weakref(doll)
	_director = director
	_life_ms = maxf(life_ms, FADE_MS)
	_smoke_ms = smoke_ms
	_colour = colour
	top_level = true
	global_transform = Transform3D.IDENTITY
	if with_com:
		_add_track(null, COM_WIDTH, COM_ALPHA)
	if doll != null:
		for pn in doll.parts.keys():
			if part_bases.has(Doll.part_base_name(String(pn))):
				_add_track(doll.parts[pn], PART_WIDTH, PART_ALPHA)
	tracks = _tracks.size()


func _add_track(body: Node3D, width: float, alpha: float) -> void:
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.extra_cull_margin = 16.0
	add_child(mi)
	_tracks.append({"body": weakref(body) if body != null else null, "width": width, "alpha": alpha,
		"pts": [], "ages": [], "im": im})


func _doll_ref() -> Doll:
	if _doll == null:
		return null
	var d := _doll.get_ref() as Doll
	if d == null or not is_instance_valid(d) or not d.is_inside_tree():
		return null
	return d


static func com_velocity(d: Doll) -> Vector3:
	var p := Vector3.ZERO
	var m := 0.0
	for b in d.parts.values():
		var rb := b as RigidBody3D
		if rb == null or not is_instance_valid(rb):
			continue
		p += rb.linear_velocity * rb.mass
		m += rb.mass
	return p / m if m > 0.0 else Vector3.ZERO


func _process(delta: float) -> void:
	var real_ms := FxClock.real_delta(delta) * 1000.0
	_t += real_ms
	var d := _doll_ref()
	var fade := clampf((_life_ms - _t) / FADE_MS, 0.0, 1.0)
	for tr in _tracks:
		var pts: Array = tr["pts"]
		var ages: Array = tr["ages"]
		for i in range(ages.size()):
			ages[i] = float(ages[i]) + real_ms
		while not ages.is_empty() and (float(ages[0]) > POINT_LIFE_MS or ages.size() > POINTS):
			ages.remove_at(0)
			pts.remove_at(0)
		if d != null and _t < _life_ms:
			var pos := Vector3.ZERO
			var wr = tr["body"]
			if wr == null:
				pos = d.centre_of_mass()
			else:
				var b := (wr as WeakRef).get_ref() as Node3D
				if b == null or not is_instance_valid(b):
					continue
				pos = d.part_centre(b as RigidBody3D) if b is RigidBody3D and d.has_method("part_centre") else b.global_position
			if pts.is_empty() or (pts[pts.size() - 1] as Vector3).distance_to(pos) >= MIN_STEP_M:
				pts.append(pos)
				ages.append(0.0)
		_rebuild(tr, fade)
	if d != null and _smoke_ms > 0.0 and _t < _smoke_ms and _t >= _next_smoke and smoke_puffs < smoke_max:
		var v := com_velocity(d)
		if v.length() > SMOKE_MIN_SPEED and _director != null and is_instance_valid(_director):
			var com := d.centre_of_mass()
			_director.call("puff", com - v.normalized() * 0.25, -v.normalized(), clampf(v.length() / 6.0, 0.4, 1.2))
			smoke_puffs += 1
			_next_smoke = _t + SMOKE_INTERVAL_MS
	if _t >= _life_ms or (d == null and _all_empty()):
		queue_free()


func _all_empty() -> bool:
	for tr in _tracks:
		if not (tr["pts"] as Array).is_empty():
			return false
	return true


func _rebuild(tr: Dictionary, fade: float) -> void:
	var im: ImmediateMesh = tr["im"]
	im.clear_surfaces()
	var pts: Array = tr["pts"]
	var n := pts.size()
	if n < 2 or fade <= 0.0:
		return
	var width: float = tr["width"]
	var alpha: float = tr["alpha"]
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, ribbon_material())
	for i in range(n):
		var p: Vector3 = pts[i]
		var a: Vector3 = pts[maxi(i - 1, 0)]
		var b: Vector3 = pts[mini(i + 1, n - 1)]
		var dd := Vector2(b.x - a.x, b.y - a.y)
		if dd.length_squared() < 1e-8:
			dd = Vector2.RIGHT
		dd = dd.normalized()
		var perp := Vector3(-dd.y, dd.x, 0.0)
		var u := float(i) / float(n - 1)            # 0 хвост → 1 голова
		var w := width * u * 0.5
		var c := Color(_colour.r, _colour.g, _colour.b, alpha * u * fade)
		im.surface_set_color(c)
		im.surface_add_vertex(p + perp * w)
		im.surface_set_color(c)
		im.surface_add_vertex(p - perp * w)
	im.surface_end()


## Мягкий конец (BoostFx: ускорение кончилось): новые точки не добавляются, ленты гаснут за FADE_MS и узел уходит сам.
func finish() -> void:
	_life_ms = minf(_life_ms, _t + FADE_MS)


func stop() -> void:
	queue_free()
