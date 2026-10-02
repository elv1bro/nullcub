## Физический звук столкновений (docs/plan-demo/AUDIO.md §4.5): любое RigidBody3D сцены (части кукол — и живых, и рассыпавшихся
## после KO, оружие, ящики, бочки, хлам Свалки, обломки, оторванные детали) стучит своим материалом (SoundMaterial) с силой удара.
## Ребёнок Match (Match._ensure_fx_directors) рядом с SfxDirector; звуки — через SfxDirector.play_layer (лимиты, журнал).
##
## Детектор без контактов: удар — резкое торможение тела за один тик физики (или за два — мягкая посадка на хлам). Δv = v − v_prev −
## g·gravity_scale·dt; удар, если |Δv| ≥ MIN_DV и Δv направлено против прежней скорости (cos ≤ −OPPOSE_COS): тело остановилось или
## отскочило. Разгон с места
## (тело толкнули) не звучит — звучит то, что ударило. Части кукол сразу после удара по ним (hit_fx) и рядом с «шлепком» о стену
## (env_slam) молчат HIT_QUIET_MS — там свой звук SfxDirector.
## Слой: класс материала × размер (масса и сила): SoundMaterial.hit_layer; громкость — от √силы и массы; удар о пол тяжёлым телом
## снизу — ещё thud. Лимиты: тело не чаще BODY_GAP_MS, всего не больше MAX_PER_SEC в секунду; в крите молчит.
## Breakable.destroyed — crash. impacts — журнал для проб [{ms, layer, dv, mass, mat, db, body}].
class_name ImpactAudio
extends Node

const GROUP := "impact_audio"
const MIN_DV := 1.4                     # м/с за тик
const FULL_DV := 9.0
const OPPOSE_COS := 0.3
const BODY_GAP_MS := 90.0
const HIT_QUIET_MS := 150.0
const MAX_PER_SEC := 16
const MIN_MASS := 0.05
const LIGHT_MASS := 1.2
const HEAVY_MASS := 6.0
const FLOOR_THUD_DV := 4.0
const FLOOR_THUD_MASS := 3.0

var sfx: SfxDirector
var enabled := true
var impacts: Array = []
var bodies: Array = []                  # RigidBody3D

var _prev_v: Dictionary = {}            # instance_id -> Vector3 (прошлый тик)
var _prev2_v: Dictionary = {}           # instance_id -> Vector3 (тик до прошлого)
var _last_ms: Dictionary = {}           # instance_id -> мс последнего звука
var _quiet_doll: Dictionary = {}        # instance_id куклы -> мс, до которой части молчат
var _window: Array = []                 # мс звуков за последнюю секунду
var _gravity := Vector3(0, -2, 0)
var _rng := RandomNumberGenerator.new()
var _match: Node


func _ready() -> void:
	add_to_group(GROUP)
	process_physics_priority = 100      # после DollCombat: удар этого тика уже пришёл в hit_fx (тишина частей)
	_rng.seed = 41
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var gv: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN)
	_gravity = gv * g
	call_deferred("_bind")


func _bind() -> void:
	if sfx == null:
		sfx = get_tree().get_first_node_in_group(SfxDirector.GROUP) as SfxDirector
	_match = get_parent() if get_parent() != null and get_parent().is_in_group("match") else get_tree().get_first_node_in_group("match")
	if _match != null:
		if _match.has_signal("hit_fx") and not _match.is_connected("hit_fx", _on_hit_fx):
			_match.connect("hit_fx", _on_hit_fx)
		if _match.has_signal("env_slam") and not _match.is_connected("env_slam", _on_env_slam):
			_match.connect("env_slam", _on_env_slam)
	var root := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	_collect(root)
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _collect(n: Node) -> void:
	if n is RigidBody3D:
		_track(n as RigidBody3D)
	for c in n.get_children():
		_collect(c)


func _on_node_added(n: Node) -> void:
	if n is RigidBody3D:
		_track(n as RigidBody3D)


func _track(b: RigidBody3D) -> void:
	if bodies.has(b) or b.mass < MIN_MASS:
		return
	bodies.append(b)
	_prev_v[b.get_instance_id()] = b.linear_velocity
	_prev2_v[b.get_instance_id()] = b.linear_velocity
	if b is Breakable and not (b as Breakable).destroyed.is_connected(_on_destroyed):
		(b as Breakable).destroyed.connect(_on_destroyed.bind(b))


func _now() -> float:
	return sfx.clock_ms() if sfx != null and is_instance_valid(sfx) else Time.get_ticks_msec()


func _on_hit_fx(ctx: Dictionary) -> void:
	var t := _now() + HIT_QUIET_MS
	for k in ["victim", "attacker"]:
		var d: Variant = ctx.get(k, null)
		if is_instance_valid(d) and d is Node:
			_quiet_doll[(d as Node).get_instance_id()] = t


func _on_env_slam(ctx: Dictionary) -> void:
	var d: Variant = ctx.get("doll", null)
	if is_instance_valid(d) and d is Node:
		_quiet_doll[(d as Node).get_instance_id()] = _now() + HIT_QUIET_MS


func _on_destroyed(b: RigidBody3D) -> void:
	if not enabled or sfx == null or not is_instance_valid(sfx) or not is_instance_valid(b):
		return
	var pos := b.global_position if b.is_inside_tree() else Vector3.ZERO
	sfx.play_layer("crash", -3.0, _rng.randf_range(0.95, 1.15), SfxDirector.BUS_SFX, sfx.pan_for(pos))
	_log("crash", 0.0, b.mass, SoundMaterial.WOOD, -3.0, String(b.name))


func _log(layer: String, dv: float, mass: float, mat: String, db: float, body: String = "") -> void:
	impacts.append({"ms": snappedf(_now(), 0.1), "layer": layer, "dv": snappedf(dv, 0.01), "mass": snappedf(mass, 0.01), "mat": mat,
		"db": snappedf(db, 0.1), "body": body})
	if impacts.size() > 2048:
		impacts.remove_at(0)


func _physics_process(delta: float) -> void:
	if sfx == null or not is_instance_valid(sfx):
		sfx = get_tree().get_first_node_in_group(SfxDirector.GROUP) as SfxDirector
	var now := _now()
	var quiet := not enabled or sfx == null or sfx.crit_active()
	while not _window.is_empty() and now - float(_window[0]) > 1000.0:
		_window.remove_at(0)
	var i := 0
	while i < bodies.size():
		var b: Variant = bodies[i]
		if not is_instance_valid(b) or not (b as Node).is_inside_tree():
			if not is_instance_valid(b):
				bodies.remove_at(i)
				continue
			i += 1
			continue
		i += 1
		var rb := b as RigidBody3D
		var id := rb.get_instance_id()
		var v := rb.linear_velocity
		var prev: Vector3 = _prev_v.get(id, v)
		var prev2: Vector3 = _prev2_v.get(id, prev)
		_prev2_v[id] = prev
		_prev_v[id] = v
		if quiet or rb.freeze or rb.sleeping:
			continue
		var g := _gravity * rb.gravity_scale * delta
		var dv := v - prev - g
		var mag := dv.length()
		if mag < MIN_DV:
			# мягкая посадка (куча хлама, стопка) гасит скорость за 2 тика — окно в 2 тика
			var dv2 := v - prev2 - g * 2.0
			if dv2.length() < MIN_DV or prev2.length() < MIN_DV * 0.5 or dv2.dot(prev2) > -OPPOSE_COS * dv2.length() * prev2.length():
				continue
			dv = dv2
			mag = dv2.length()
			prev = prev2
		var pl := prev.length()
		if pl < MIN_DV * 0.5 or dv.dot(prev) > -OPPOSE_COS * mag * pl:
			continue
		if now - float(_last_ms.get(id, -1.0e9)) < BODY_GAP_MS or _window.size() >= MAX_PER_SEC:
			continue
		var owner_doll := rb.get_parent() as Doll
		if owner_doll != null and now < float(_quiet_doll.get(owner_doll.get_instance_id(), -1.0)):
			continue
		_play_impact(rb, mag, dv, now)


func _play_impact(rb: RigidBody3D, mag: float, dv: Vector3, now: float) -> void:
	var mat := SoundMaterial.of_body(rb)
	var m := rb.mass
	var k := clampf((mag - MIN_DV) / (FULL_DV - MIN_DV), 0.0, 1.0)
	var size := 0
	if m >= HEAVY_MASS:
		size = 2 if mag >= 3.0 else 1
	elif m >= LIGHT_MASS:
		size = 1 if mag >= 4.0 else 0
	var pitch := _rng.randf_range(0.94, 1.06)
	if m < LIGHT_MASS:
		pitch *= lerpf(1.25, 1.05, clampf(m / LIGHT_MASS, 0.0, 1.0))
	elif m >= HEAVY_MASS:
		pitch *= 0.9
	var db := lerpf(-22.0, -3.0, sqrt(k)) + clampf(log(maxf(m, 0.01)) / log(10.0) * 3.0, -5.0, 3.0)
	var layer := SoundMaterial.hit_layer(mat, size)
	var pan := sfx.pan_for(rb.global_position)
	if sfx.play_layer(layer, db, pitch, SfxDirector.BUS_SFX, pan) < 0:
		return
	_last_ms[rb.get_instance_id()] = now
	_window.append(now)
	_log(layer, mag, m, mat, db, String(rb.name))
	# тяжёлое о пол (отскок вверх) — ещё глухой удар пола
	if mag >= FLOOR_THUD_DV and m >= FLOOR_THUD_MASS and dv.y > 0.6 * mag:
		sfx.play_layer("thud", db - 5.0, _rng.randf_range(0.85, 1.0), SfxDirector.BUS_SFX, pan)
