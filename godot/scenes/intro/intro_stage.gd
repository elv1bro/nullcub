## Съёмочная площадка заставки-комикса: арена «Свалка» (scenes/arena/scrap.tscn), кукла-герой и враг (ComicPuppet),
## одна камера и кадры Shots/ShotNN (ComicShot). Сцену intro_stage.tscn собирает tools/build_intro_comic.gd; здесь поведение.
## Всё, что видно в кадре, — функция времени кадра: evaluate(t) можно звать с любым t (страница комикса играет по порядку,
## тест tests/intro_snapshot.gd прыгает на нужный момент). Исключение — частицы (искры, пыль): они живут своим временем.
class_name IntroStage
extends Node3D

const GRAVITY := Vector3(0.0, -6.0, 0.0)

@onready var camera: Camera3D = $Camera
@onready var hero: ComicPuppet = $Hero
@onready var enemy: ComicPuppet = $Enemy
@onready var shots_root: Node3D = $Shots
@onready var arena: Node3D = $Scrap

var shots: Array[ComicShot] = []
var shot: ComicShot
var shot_index := -1
var _t := 0.0
var _prev_t := -1.0
var _hero_keys: Array = []
var _hero_params: Array = []
var _enemy_keys: Array = []
var _enemy_params: Array = []
var _events: Array = []
var _held: Dictionary = {}          # имя пропса → [кукла, часть]
var _rest: Dictionary = {}          # пропс → Transform3D покоя (как в сцене)
var _shatter_cache: Dictionary = {} # кукла → {part: [T0, v, w]}
var _attrs: CameraAttributesPractical
var _hidden_arena: Array = []


func _ready() -> void:
	for c in shots_root.get_children():
		if c is ComicShot:
			shots.append(c)
			c.visible = false
	_attrs = camera.attributes as CameraAttributesPractical
	if _attrs == null:
		_attrs = CameraAttributesPractical.new()
		camera.attributes = _attrs
	camera.current = true


func shot_count() -> int:
	return shots.size()


func set_shot(i: int) -> void:
	for s in shots:
		s.visible = false
	_restore_props()
	shot_index = clampi(i, 0, shots.size() - 1)
	shot = shots[shot_index]
	shot.visible = true
	_hero_keys = ComicShot.parse_keys(shot.hero_keys)
	_hero_params = ComicShot.parse_keys(shot.hero_params)
	_enemy_keys = ComicShot.parse_keys(shot.enemy_keys)
	_enemy_params = ComicShot.parse_keys(shot.enemy_params)
	_events = ComicShot.parse_keys(shot.events)
	hero.visible = shot.hero_visible
	enemy.visible = shot.enemy_visible
	_held.clear()
	_rest.clear()
	var props := shot.get_node_or_null("Props")
	if props:
		for p in props.get_children():
			if p is Node3D:
				_rest[p] = (p as Node3D).transform
	for pup in [hero, enemy]:
		pup.set_shatter(-1.0, Vector3.ZERO, 0)
	_shatter_cache.clear()
	_prev_t = -1.0
	# DOF и экспозиция кадра
	_attrs.dof_blur_far_enabled = shot.dof_far > 0.0
	_attrs.dof_blur_far_distance = maxf(shot.dof_far, 0.01)
	_attrs.dof_blur_far_transition = shot.dof_far_transition
	_attrs.dof_blur_near_enabled = shot.dof_near > 0.0
	_attrs.dof_blur_near_distance = maxf(shot.dof_near, 0.01)
	_attrs.dof_blur_near_transition = shot.dof_near_transition
	_attrs.dof_blur_amount = shot.dof_amount
	_attrs.exposure_multiplier = shot.exposure
	for n in _hidden_arena:
		if is_instance_valid(n):
			(n as Node3D).visible = true
	_hidden_arena.clear()
	for path in shot.hide_nodes:
		var hn := arena.get_node_or_null(path) as Node3D
		if hn and hn.visible:
			hn.visible = false
			_hidden_arena.append(hn)
	var par := arena.get_node_or_null("Parallax")
	if par:
		var fore := par.get_node_or_null("Layer1Fore") as Node3D
		if fore:
			fore.visible = not shot.hide_fore_layer
	evaluate(0.0)


func evaluate(t: float) -> void:
	if shot == null:
		return
	_t = t
	var d := maxf(shot.duration, 0.01)
	var u := clampf(t / d, 0.0, 1.0)
	# камера
	var ca := shot.get_node_or_null("CamA") as Camera3D
	var cb := shot.get_node_or_null("CamB") as Camera3D
	if ca:
		var k := ease(u, shot.cam_ease)
		var ta := ca.global_transform
		var tb := cb.global_transform if cb else ta
		var q := Quaternion(ta.basis.orthonormalized()).slerp(Quaternion(tb.basis.orthonormalized()), k)
		camera.global_transform = Transform3D(Basis(q), ta.origin.lerp(tb.origin, k))
		camera.fov = lerpf(ca.fov, cb.fov if cb else ca.fov, k)
	# куклы
	_place(hero, "Hero", _window(t, shot.hero_move, d), shot.hero_ease)
	_place(enemy, "Enemy", _window(t, shot.enemy_move, d), shot.enemy_ease)
	hero.set_pose(_pose_at(_hero_keys, t))
	enemy.set_pose(_pose_at(_enemy_keys, t))
	_apply_params(hero, _params_at(_hero_params, t))
	_apply_params(enemy, _params_at(_enemy_params, t))
	# события
	_apply_events(t)
	_update_key()
	_prev_t = t


## Ключевой прожектор арены (CameraKey, 14 единиц) рассчитан на игровую камеру в 14–24 м от кукол; на крупных планах
## он пересвечивает клён — энергия по расстоянию до плоскости кукол, плюс множитель кадра.
func _update_key() -> void:
	var key := arena.get_node_or_null("CameraKey") as SpotLight3D
	if key == null:
		return
	var d := absf(camera.global_position.z) + 0.5
	key.light_energy = clampf(14.0 * pow(d / 18.0, 2.0), 0.15, 14.0) * shot.key_mult


## Точка мира → доля кадра (0..1 по x и y от левого верхнего угла).
func project(world: Vector3) -> Vector2:
	var vp := camera.get_viewport()
	var sz := Vector2(vp.get_visible_rect().size)
	if camera.is_position_behind(world):
		return Vector2(-1, -1)
	return camera.unproject_position(world) / sz


## Именованная точка для 2D-эффектов страницы: "hero:Head", "enemy:Chest", "prop:Barrel", "world:x,y,z".
func anchor(name: String) -> Vector3:
	var p := name.split(":")
	if p.size() < 2:
		return Vector3.ZERO
	match p[0]:
		"hero":
			return hero.anchor_world(p[1])
		"enemy":
			return enemy.anchor_world(p[1])
		"prop":
			var n := shot.get_node_or_null("Props/" + p[1]) as Node3D if shot else null
			return n.global_position if n else Vector3.ZERO
		"world":
			var v := p[1].split(",")
			if v.size() == 3:
				return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO


func _window(t: float, w: Vector2, d: float) -> float:
	if w.x >= w.y:
		return clampf(t / d, 0.0, 1.0)
	return clampf((t - w.x) / (w.y - w.x), 0.0, 1.0)


func _place(pup: ComicPuppet, prefix: String, u: float, curve: float) -> void:
	var a := shot.get_node_or_null(prefix + "A") as Node3D
	if a == null:
		return
	var b := shot.get_node_or_null(prefix + "B") as Node3D
	var k := ease(u, curve)
	var ta := a.global_transform
	var tb := b.global_transform if b else ta
	var q := Quaternion(ta.basis.orthonormalized()).slerp(Quaternion(tb.basis.orthonormalized()), k)
	pup.global_transform = Transform3D(Basis(q), ta.origin.lerp(tb.origin, k))


func _pose_at(keys: Array, t: float) -> Dictionary:
	if keys.is_empty():
		return {}
	if t <= keys[0][0]:
		return ComicPoses.pose(keys[0][1])
	for i in range(keys.size() - 1):
		var k0: Array = keys[i]
		var k1: Array = keys[i + 1]
		if t < k1[0]:
			var w := clampf((t - k0[0]) / maxf(k1[0] - k0[0], 0.001), 0.0, 1.0)
			w = w * w * (3.0 - 2.0 * w)
			return ComicPuppet.blend(ComicPoses.pose(k0[1]), ComicPoses.pose(k1[1]), w)
	return ComicPoses.pose(keys[-1][1])


func _params_at(keys: Array, t: float) -> Dictionary:
	var out := {}
	if keys.is_empty():
		return out
	var parsed: Array = []
	for k in keys:
		parsed.append([k[0], ComicShot.parse_params(k[1])])
	for name in ["eye", "squint", "core", "flicker"]:
		var prev_t := -INF
		var prev_v := NAN
		for k in parsed:
			if not (k[1] as Dictionary).has(name):
				continue
			var kt: float = k[0]
			var kv: float = k[1][name]
			if kt <= t:
				prev_t = kt
				prev_v = kv
			else:
				if is_nan(prev_v):
					prev_v = kv
					prev_t = kt
				var w := clampf((t - prev_t) / maxf(kt - prev_t, 0.001), 0.0, 1.0)
				prev_v = lerpf(prev_v, kv, w)
				break
		if not is_nan(prev_v):
			out[name] = prev_v
	return out


func _apply_params(pup: ComicPuppet, p: Dictionary) -> void:
	pup.eye_glow = p.get("eye", 0.0)
	pup.eye_squint = p.get("squint", 0.0)
	pup.core_glow = p.get("core", 0.0)
	pup.core_flicker = p.get("flicker", 0.0)


func _restore_props() -> void:
	for p in _rest:
		if is_instance_valid(p):
			(p as Node3D).transform = _rest[p]
			(p as Node3D).visible = true


## События кадра (время от начала кадра):
##   hero_hide:Part / hero_show:Part / hero_swap:Part:tone   — состояние меша части героя с момента t
##   enemy_hide:Part / enemy_show:Part
##   drop:Prop[:fall_s[:height]]    — пропс падает сверху и приземляется в свою позицию ровно в t, подпрыгивает и остаётся
##   hold:Prop:Part                 — с t пропс держит кукла-герой (кисть Hand_L|Hand_R), смещение хвата — meta "grip" пропса
##   hide:Prop / show:Prop          — видимость пропса
##   rain:Group[:speed]             — дети Props/Group сыплются сверху по кругу (дождь хлама)
##   shake:amp:dur                  — тряска камеры
##   shatter:enemy|hero:dx,dy[:speed[:slow]] — кукла разлетается на части (KO); slow < 1 — замедленно
##   sparks:hero|enemy:Part / dust:hero|enemy:Part — одноразовые частицы (только при проигрывании вперёд)
##   spin:Prop:deg_per_s            — вращение пропса вокруг своей Y
func _apply_events(t: float) -> void:
	var hero_state := {}
	var enemy_state := {}
	var shake := Vector3.ZERO
	for e in _events:
		var et: float = e[0]
		var a: PackedStringArray = (e[1] as String).split(":")
		var kind := a[0]
		match kind:
			"hero_hide", "hero_show", "hero_swap", "enemy_hide", "enemy_show":
				if t >= et:
					var st: Dictionary = hero_state if kind.begins_with("hero") else enemy_state
					if kind.ends_with("hide"):
						var cur0: Dictionary = st.get(a[1], {})
						cur0["visible"] = false
						st[a[1]] = cur0
					elif kind.ends_with("show"):
						var cur: Dictionary = st.get(a[1], {})
						cur["visible"] = true
						st[a[1]] = cur
					else:
						var cur2: Dictionary = st.get(a[1], {})
						cur2["tone"] = a[2]
						st[a[1]] = cur2
			"drop":
				_drop(a, et, t)
			"hold":
				var n := _prop(a[1])
				if n and t >= et:
					var part := a[2] if a.size() > 2 else "Hand_L"
					var hand := hero.part_node(part)
					if hand:
						var grip: Transform3D = n.get_meta("grip", Transform3D.IDENTITY)
						n.global_transform = hand.global_transform * grip
			"hide", "show":
				var n2 := _prop(a[1])
				if n2 and t >= et:
					n2.visible = kind == "show"
			"rain":
				_rain(a, et, t)
			"spin":
				var n3 := _prop(a[1])
				if n3 and _rest.has(n3):
					var tr: Transform3D = _rest[n3]
					n3.transform = Transform3D(tr.basis.rotated(Vector3.UP, deg_to_rad(float(a[2]) * maxf(t - et, 0.0))), tr.origin)
			"shake":
				var amp := float(a[1]) if a.size() > 1 else 0.2
				var dur := float(a[2]) if a.size() > 2 else 0.4
				var dt := t - et
				if dt >= 0.0 and dt < dur:
					var k := amp * pow(1.0 - dt / dur, 2.0)
					shake += Vector3(sin(dt * 71.0) + 0.5 * sin(dt * 131.0), cos(dt * 83.0) + 0.5 * sin(dt * 117.0), 0.0) * k * 0.5
			"shatter":
				var pup: ComicPuppet = enemy if a[1] == "enemy" else hero
				var dv := a[2].split(",") if a.size() > 2 else PackedStringArray(["1", "0.3"])
				var speed := float(a[3]) if a.size() > 3 else 4.0
				var slow := float(a[4]) if a.size() > 4 else 1.0   # < 1 — замедленная съёмка разлёта
				pup.set_shatter((t - et) * slow if t >= et else -1.0, Vector3(float(dv[0]), float(dv[1]), 0.0).normalized() * speed, 7)
			"sparks", "dust":
				if _prev_t >= 0.0 and _prev_t < et and t >= et:
					var who: ComicPuppet = enemy if a[1] == "enemy" else hero
					_burst(kind, who.anchor_world(a[2] if a.size() > 2 else "Chest"))
	for part in ComicPuppet.PART_JOINT:
		var hs: Dictionary = hero_state.get(part, {})
		hero.set_part_state(part, hs.get("visible", true), hs.get("tone", ""))
		var es: Dictionary = enemy_state.get(part, {})
		enemy.set_part_state(part, es.get("visible", true), es.get("tone", ""))
	if shake != Vector3.ZERO:
		camera.global_position += camera.global_transform.basis * shake


func _prop(n: String) -> Node3D:
	return shot.get_node_or_null("Props/" + n) as Node3D


func _drop(a: PackedStringArray, et: float, t: float) -> void:
	var n := _prop(a[1])
	if n == null or not _rest.has(n):
		return
	var fall := float(a[2]) if a.size() > 2 else 0.35
	var h := float(a[3]) if a.size() > 3 else 3.0
	var rest: Transform3D = _rest[n]
	var t0 := et - fall
	if t < t0:
		n.visible = false
		return
	n.visible = true
	if t < et:
		var w := (t - t0) / fall
		n.transform = Transform3D(rest.basis.rotated(Vector3.FORWARD, 0.5 * (1.0 - w)), rest.origin + Vector3(0.0, h * (1.0 - w * w), 0.0))
	else:
		# приземлился и остался на месте (бочка «надета» на голову): затухающий подскок и покачивание
		var dt := t - et
		var hop := 0.12 * absf(sin(dt * 14.0)) * exp(-dt * 6.0)
		var wob := 0.22 * sin(dt * 11.0) * exp(-dt * 3.5)
		n.transform = Transform3D(rest.basis.rotated(Vector3.FORWARD, wob), rest.origin + Vector3(0.0, hop, 0.0))


func _rain(a: PackedStringArray, et: float, t: float) -> void:
	var g := _prop(a[1])
	if g == null:
		return
	var speed := float(a[2]) if a.size() > 2 else 5.0
	var i := 0
	for c in g.get_children():
		if not (c is Node3D):
			continue
		var n: Node3D = c
		if not n.has_meta("rain_origin"):
			n.set_meta("rain_origin", n.position)
		var o: Vector3 = n.get_meta("rain_origin")
		var span := 16.0
		var phase := fmod(float(i) * 0.618, 1.0) * span
		var y := o.y - fmod(maxf(t - et, 0.0) * speed * (0.8 + 0.4 * fmod(float(i) * 0.37, 1.0)) + phase, span)
		n.position = Vector3(o.x, y, o.z)
		n.rotation = Vector3(t * (1.0 + i % 3), t * 0.7 * (1 + i % 2), t * 0.5)
		i += 1


func _burst(kind: String, at: Vector3) -> void:
	var src := get_node_or_null("Fx/" + ("Sparks" if kind == "sparks" else "Dust")) as GPUParticles3D
	if src == null:
		return
	var p: GPUParticles3D = src.duplicate()
	add_child(p)
	p.global_position = at
	p.emitting = true
	p.one_shot = true
	p.restart()
	get_tree().create_timer(p.lifetime + 0.5).timeout.connect(p.queue_free)
