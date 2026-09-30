## Активные блоки бойца в бою (docs/plan-demo/ACTIVE_BLOCKS.md; данные — ActiveBlocks). Узел-ребёнок ModularDoll «ActiveRig»:
## его ставит ModularDoll._ready (attach_if_needed — только если в чертеже есть активный блок или деталь с пассивом).
##   • заряд: один на бойца, копится сам и от ударов (дельта Doll.stats damage_dealt / damage_taken; урон самих блоков заряд не
##     даёт), пассивы ядер лиги меняют запас, скорость и отдачу заряда;
##   • каналы 1–3: игрок — экшены pN_act1…3 (ActiveBlocks.ensure_input_actions), бот / проба — held[] при doll.external_input.
##     Пока канал зажат и заряда хватает, все блоки канала работают и платят cost × dt (пулемёт — за выстрел); не хватает — канал
##     гаснет. Каналы молчат, пока кукла не жива, разбита, без управления (стенд мастерской, отсчёт) или в стане;
##   • действия: thrust (сила вдоль оси блока в точке сопла), flame (конус: урон всем чужим частям + толчок), gun (луч-очередь,
##     импульс, отдача), magnet (тянет чужое железо, отдача на себя), gravity (стягивает чужие тела и оружие), shield (входящий
##     урон × mult — ModularDoll.team_mult_for), phase (исключения столкновений с чужими куклами, урон 0), repair (заряд → HP);
##   • урон блоков — как у взрыва (scenes/props/explosion.gd): Doll.take_damage с hit_meta, stats damage_dealt, Match.on_hit; только
##     пока Match.combat_active() (или матча нет);
##   • полоска заряда над бойцом (в плоскости кадра) и три огонька каналов.
class_name ActiveRig
extends Node

const FLAME_CHUNK := 5.0         # HP: огонь наносит урон порциями (не 60 ударов в секунду в HUD и звук)
const BAR_W := 0.7
const BAR_H := 0.05
const BAR_UP := 0.42             # м над головой (нет головы — над торсом + 0.9)
const COL_CHARGE := Color(0.55, 0.3, 1.0)
const COL_LOW := Color(1.0, 0.35, 0.2)
const COL_CH := [Color(1.0, 0.75, 0.2), Color(0.3, 0.9, 1.0), Color(1.0, 0.35, 0.55)]

signal channel_changed(ch: int, on: bool)

var doll: ModularDoll
## [{uid, part, def, action, channel, host: RigidBody3D, xf: Transform3D — кадр блока в теле-хозяине, t: таймер, fx: Node3D}]
var blocks: Array = []
var charge := 0.0
var charge_max := ActiveBlocks.CHARGE_MAX
var regen := ActiveBlocks.CHARGE_REGEN
var dealt_mult := 1.0
var hp_regen := 0.0
## Внешний ввод каналов (боты, пробы) — читается при doll.external_input.
var held: Array[bool] = [false, false, false]
## Каналы, которые работали на последнем тике.
var running: Array[bool] = [false, false, false]
## Для проб и HUD: всего потрачено, получено от ударов, урон блоками, выстрелов.
var spent := 0.0
var gained_hits := 0.0
var block_damage := 0.0
var shots := 0
var ready_ok := false

var _dealt_seen := 0.0
var _taken_seen := 0.0
var _own_dealt := 0.0
var _incoming := 1.0
var _phase_on := false
var _phase_pairs: Array = []
var _phase_meshes: Array = []
var _flame_acc: Dictionary = {}   # Doll → накопленный урон огня
var _bar_root: Node3D
var _bar_fill: MeshInstance3D
var _pips: Array[MeshInstance3D] = []
var _bubble: MeshInstance3D
var _rng := RandomNumberGenerator.new()


## Поставить узел на куклу, если в чертеже есть активный блок или пассив (зовёт ModularDoll._ready). Уже есть — вернуть его
## (Match.respawn_doll пересоздаёт детей со скриптом: второй экземпляр освобождается в своём _ready).
static func attach_if_needed(d: ModularDoll) -> ActiveRig:
	if d == null or not ActiveBlocks.has_any(d.blueprint):
		return null
	for c in d.get_children():
		if c is ActiveRig and not c.is_queued_for_deletion():
			return c
	var r := ActiveRig.new()
	r.name = "ActiveRig"
	r.doll = d
	d.add_child(r)
	return r


func _ready() -> void:
	if doll == null:
		doll = get_parent() as ModularDoll
	if doll == null:
		queue_free()
		return
	for c in doll.get_children():
		if c is ActiveRig:
			if c != self:
				queue_free()
				return
			break
	if not doll.is_node_ready():
		await doll.ready
	_rng.seed = hash(String(doll.name))
	ActiveBlocks.ensure_input_actions()
	_collect()
	charge = charge_max * ActiveBlocks.CHARGE_START
	_dealt_seen = float(doll.stats.get("damage_dealt", 0.0))
	_taken_seen = float(doll.stats.get("damage_taken", 0.0))
	if not blocks.is_empty():
		_make_bar()
	ready_ok = true


func _exit_tree() -> void:
	_set_phase(false)


func _collect() -> void:
	blocks.clear()
	for n in doll.blueprint.nodes:
		var pid := String(n.get("part", ""))
		var uid := String(n.get("uid", ""))
		if ActiveBlocks.PASSIVE.has(pid):
			var p: Dictionary = ActiveBlocks.PASSIVE[pid]
			charge_max += float(p.get("charge_max", 0.0))
			regen += float(p.get("charge_regen", 0.0))
			dealt_mult *= float(p.get("dealt_mult", 1.0))
			hp_regen += float(p.get("hp_regen", 0.0))
		if not ActiveBlocks.is_active(pid):
			continue
		var host := doll.get_node_or_null(String(doll.uid_body.get(uid, ""))) as RigidBody3D
		if host == null:
			push_warning("ActiveRig: блок %s (%s) без тела-хозяина" % [uid, pid])
			continue
		var mesh := host.get_node_or_null("Mesh_" + uid) as Node3D
		var xf := mesh.transform if mesh != null else Transform3D.IDENTITY
		var d: Dictionary = ActiveBlocks.def_of(pid)
		blocks.append({"uid": uid, "part": pid, "def": d, "action": String(d["action"]), "channel": ActiveBlocks.channel_of(n),
			"host": host, "xf": xf, "t": 0.0, "fx": null})


# --- тик ---

func _physics_process(dt: float) -> void:
	if not ready_ok or not is_instance_valid(doll):
		return
	_charge_from_hits()
	charge = minf(charge + regen * dt, charge_max)
	if hp_regen > 0.0:
		_heal(hp_regen * dt)
	var ok := doll.alive and not doll.is_broken() and doll.control_enabled \
		and not (ActiveBlocks.STUN_BLOCKS and doll.is_stunned())
	_incoming = 1.0
	var phase := false
	for ch in range(1, ActiveBlocks.CHANNELS + 1):
		var want := ok and _want(ch)
		var chan: Array = blocks.filter(func(b: Dictionary) -> bool: return int(b["channel"]) == ch)
		var need := 0.0
		for b in chan:
			if String(b["action"]) != "gun":
				need += float(b["def"]["cost"]) * dt
		var on := want and not chan.is_empty() and charge > 0.0 and charge >= need
		if on:
			charge -= need
			spent += need
		if on != running[ch - 1]:
			running[ch - 1] = on
			channel_changed.emit(ch, on)
		for b in chan:
			if on:
				_run(b, dt)
				if String(b["action"]) == "phase":
					phase = true
			else:
				_fx(b, false)
	for b in blocks:
		if int(b["channel"]) == 0:
			_fx(b, false)
	_set_phase(phase)
	_update_bar()


func _want(ch: int) -> bool:
	if doll.external_input:
		return held[ch - 1]
	var a := ActiveBlocks.action_name(doll.input_prefix, ch)
	return InputMap.has_action(a) and Input.is_action_pressed(a)


## Множитель входящего урона (ModularDoll.team_mult_for): энергощит × mult, фаза — 0.
func incoming_mult() -> float:
	return _incoming


func _charge_from_hits() -> void:
	var dealt := float(doll.stats.get("damage_dealt", 0.0))
	var taken := float(doll.stats.get("damage_taken", 0.0))
	var dd := dealt - _dealt_seen
	var dtk := taken - _taken_seen
	if dd < 0.0 or dtk < 0.0:   # статистика сброшена (новый матч)
		dd = maxf(dd, 0.0)
		dtk = maxf(dtk, 0.0)
	var g := maxf(dd - _own_dealt, 0.0) * ActiveBlocks.CHARGE_PER_DEALT * dealt_mult + dtk * ActiveBlocks.CHARGE_PER_TAKEN
	_own_dealt = 0.0
	_dealt_seen = dealt
	_taken_seen = taken
	if g > 0.0:
		gained_hits += g
		charge = minf(charge + g, charge_max)


# --- действия ---

func _run(b: Dictionary, dt: float) -> void:
	var d: Dictionary = b["def"]
	match String(b["action"]):
		"thrust":
			var host := b["host"] as RigidBody3D
			var ax := _axis(b)
			var nz: Array = d["nozzles"]
			for p in nz:
				var pos := _point(b, p)
				host.apply_force(ax * float(d["force"]) / nz.size(), pos - host.global_position)
			_fx(b, true)
		"flame":
			_flame(b, dt)
			_fx(b, true)
		"gun":
			b["t"] = float(b["t"]) + dt
			var period := 1.0 / float(d["rate"])
			while float(b["t"]) >= period and charge >= float(d["cost"]):
				b["t"] = float(b["t"]) - period
				charge -= float(d["cost"])
				spent += float(d["cost"])
				_shoot(b)
			_fx(b, true)
		"magnet":
			_magnet(b)
			_fx(b, true)
		"gravity":
			_gravity(b)
			_fx(b, true)
		"shield":
			_incoming = minf(_incoming, float(d["mult"]))
			_fx(b, true)
		"phase":
			_incoming = 0.0
			_fx(b, true)
		"repair":
			_heal(float(d["hps"]) * dt)
			_fx(b, true)


## Точка кадра блока p (кадр детали) в мире.
func _point(b: Dictionary, p: Vector3) -> Vector3:
	return (b["host"] as RigidBody3D).global_transform * ((b["xf"] as Transform3D) * p)


## Ось действия блока (+Y детали) в мире, в плоскости боя (z = 0).
func _axis(b: Dictionary) -> Vector3:
	var a := (b["host"] as RigidBody3D).global_basis * (b["xf"] as Transform3D).basis.y
	a.z = 0.0
	return a.normalized() if a.length_squared() > 1e-6 else Vector3.UP


func _own(body: Node) -> bool:
	return body != null and (body == doll or doll.is_ancestor_of(body))


func _doll_of(body: Node) -> Doll:
	var n := body
	while n != null:
		if n is Doll:
			return n as Doll
		n = n.get_parent()
	return null


## Чужие тела (RigidBody3D) в сфере radius вокруг c.
func _bodies_near(c: Vector3, radius: float) -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	var space := doll.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = radius
	q.shape = sh
	q.transform = Transform3D(Basis(), c)
	q.collide_with_areas = false
	for r in space.intersect_shape(q, 48):
		var body := r["collider"] as RigidBody3D
		if body != null and not _own(body) and not out.has(body) and not body.freeze:
			out.append(body)
	return out


func _flame(b: Dictionary, dt: float) -> void:
	var d: Dictionary = b["def"]
	var o := _point(b, d["muzzle"])
	var ax := _axis(b)
	var rng := float(d["range"])
	var cosc := cos(deg_to_rad(float(d["cone_deg"])))
	var hit_dolls := {}
	for body in _bodies_near(o + ax * rng * 0.5, rng * 0.6):
		var v := body.global_position - o
		v.z = 0.0
		var dist := v.length()
		if dist > rng or dist < 1e-3 or v.normalized().dot(ax) < cosc:
			continue
		var f := 1.0 - dist / rng
		body.apply_central_force(ax * float(d["push"]) * f)
		var victim := _doll_of(body)
		if victim != null and victim != doll:
			var best: Array = hit_dolls.get(victim, [])
			if best.is_empty() or f > float(best[1]):
				hit_dolls[victim] = [body, f]
	for victim in hit_dolls:
		var e: Array = hit_dolls[victim]
		var acc := float(_flame_acc.get(victim, 0.0)) + float(d["dps"]) * dt * (0.5 + 0.5 * float(e[1]))
		if acc >= FLAME_CHUNK:
			var body := e[0] as RigidBody3D
			_deal(victim, acc, String(body.name), body.global_position, -ax, "active_flamer")
			acc = 0.0
		_flame_acc[victim] = acc


func _shoot(b: Dictionary) -> void:
	var d: Dictionary = b["def"]
	var host := b["host"] as RigidBody3D
	var o := _point(b, d["muzzle"])
	var ax := _axis(b).rotated(Vector3.BACK, deg_to_rad(_rng.randf_range(-1.0, 1.0) * float(d["spread_deg"])))
	var to := o + ax * float(d["range"])
	var q := PhysicsRayQueryParameters3D.create(o, to)
	var ex: Array[RID] = []
	for p in doll.parts.values():
		if is_instance_valid(p):
			ex.append((p as RigidBody3D).get_rid())
	q.exclude = ex
	var hit := doll.get_world_3d().direct_space_state.intersect_ray(q)
	var end := to
	if not hit.is_empty():
		end = hit["position"]
		var body := hit["collider"] as RigidBody3D
		if body != null and not body.freeze:
			body.apply_impulse(ax * float(d["impulse"]), end - body.global_position)
			var victim := _doll_of(body)
			if victim != null and victim != doll:
				_deal(victim, float(d["damage"]), String(body.name), end, hit["normal"], "active_gun")
	host.apply_impulse(-ax * float(d["recoil"]), o - host.global_position)
	shots += 1
	_tracer(o, end)


func _magnet(b: Dictionary) -> void:
	var d: Dictionary = b["def"]
	var host := b["host"] as RigidBody3D
	var c := _point(b, d["muzzle"])
	var r := float(d["radius"])
	for body in _bodies_near(c, r):
		var iron := float(body.get_meta("material", 0.0)) if body.get_meta("material", 0.0) is float else 0.0
		if iron <= 0.0:
			continue
		var v := c - body.global_position
		v.z = 0.0
		var dist := v.length()
		if dist < 0.05 or dist > r:
			continue
		var f := v / dist * float(d["force"]) * iron * (1.0 - dist / r)
		body.apply_central_force(f)
		host.apply_force(-f, c - host.global_position)


func _gravity(b: Dictionary) -> void:
	var d: Dictionary = b["def"]
	var c := _point(b, d["muzzle"])
	var r := float(d["radius"])
	for body in _bodies_near(c, r):
		var v := c - body.global_position
		v.z = 0.0
		var dist := v.length()
		if dist < 0.1 or dist > r:
			continue
		body.apply_central_force(v / dist * float(d["accel"]) * body.mass * sqrt(1.0 - dist / r))


func _heal(amount: float) -> void:
	if amount <= 0.0 or not doll.alive or doll.hp >= doll.max_hp:
		return
	doll.hp = minf(doll.hp + amount, doll.max_hp)
	var m := get_tree().get_first_node_in_group("match")
	if m != null and m.has_signal("hp_changed"):
		m.emit_signal("hp_changed", doll, doll.hp, doll.max_hp)


## Урон блоком (огонь, пуля) — как взрыв (explosion.gd): hit_meta, take_damage, stats, Match.on_hit; только в бою.
func _deal(victim: Doll, amount: float, part: String, pos: Vector3, normal: Vector3, weapon_id: String) -> void:
	var m := get_tree().get_first_node_in_group("match")
	if m != null and m.has_method("combat_active") and not bool(m.call("combat_active")):
		return
	if not victim.alive or not victim.can_take_damage():
		return
	victim.hit_meta = {"speed": 0.0, "weapon_id": weapon_id, "striker": doll, "combo_mult": 1.0, "double_blow": false,
		"knockback_mult": 1.0, "stun_s": 0.0, "active_block": true}
	var hp0 := victim.hp
	victim.take_damage(amount, doll, part, pos, normal, "weapon")
	var dealt := hp0 - victim.hp
	if dealt <= 0.0:
		return
	doll.stats["damage_dealt"] = float(doll.stats.get("damage_dealt", 0.0)) + dealt
	_own_dealt += dealt
	block_damage += dealt
	if m != null and m.has_method("on_hit"):
		m.call("on_hit", victim, doll, dealt, "weapon", pos, 0, false, weapon_id, 0.0)


func _set_phase(on: bool) -> void:
	if on == _phase_on or not is_instance_valid(doll):
		return
	_phase_on = on
	if on:
		var mine: Array = doll.parts.values().filter(func(p: Variant) -> bool: return is_instance_valid(p))
		for other in _other_dolls():
			for ob in (other as Doll).parts.values():
				if not is_instance_valid(ob):
					continue
				for mb in mine:
					(mb as PhysicsBody3D).add_collision_exception_with(ob as PhysicsBody3D)
					_phase_pairs.append([mb, ob])
		for mi in doll.find_children("*", "GeometryInstance3D", true, false):
			if (mi as GeometryInstance3D).transparency < 0.5:
				(mi as GeometryInstance3D).transparency = 0.55
				_phase_meshes.append(mi)
	else:
		for pr in _phase_pairs:
			if is_instance_valid(pr[0]) and is_instance_valid(pr[1]):
				(pr[0] as PhysicsBody3D).remove_collision_exception_with(pr[1] as PhysicsBody3D)
		_phase_pairs.clear()
		for mi in _phase_meshes:
			if is_instance_valid(mi):
				(mi as GeometryInstance3D).transparency = 0.0
		_phase_meshes.clear()


func _other_dolls() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("dolls"):
		if n is Doll and n != doll:
			out.append(n)
	var p := doll.get_parent()
	if p != null:
		for n in p.get_children():
			if n is Doll and n != doll and not out.has(n):
				out.append(n)
	return out


# --- эффекты ---

## Свечение / частицы блока: создаются при первом включении, дальше только emitting / visible.
func _fx(b: Dictionary, on: bool) -> void:
	var fx := b["fx"] as Node3D
	if fx == null:
		if not on:
			return
		fx = _make_fx(b)
		b["fx"] = fx
	if fx is CPUParticles3D:
		(fx as CPUParticles3D).emitting = on
	else:
		fx.visible = on
	if on and String(b["action"]) == "shield":
		_bubble_follow()


func _make_fx(b: Dictionary) -> Node3D:
	var d: Dictionary = b["def"]
	var host := b["host"] as RigidBody3D
	var xf := b["xf"] as Transform3D
	match String(b["action"]):
		"thrust":
			var root := Node3D.new()
			host.add_child(root)
			root.transform = xf
			for p in d["nozzles"]:
				root.add_child(_particles(p, Vector3.DOWN, Color(1.0, 0.6, 0.15), 0.9, 40, 0.035))
			return _group_fx(root)
		"flame":
			var p := _particles(d["muzzle"], Vector3.UP, Color(1.0, 0.45, 0.08), float(d["range"]) * 1.6, 90, 0.07)
			p.spread = float(d["cone_deg"])
			host.add_child(p)
			p.transform = xf * p.transform
			return p
		"gun":
			var flash := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.035
			sm.height = 0.07
			flash.mesh = sm
			flash.material_override = _glow_mat(Color(1.0, 0.85, 0.4), 4.0)
			host.add_child(flash)
			flash.transform = xf * Transform3D(Basis(), d["muzzle"])
			return flash
		"magnet", "gravity":
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			var rr := 0.25 if String(b["action"]) == "magnet" else 0.45
			tm.inner_radius = rr - 0.012
			tm.outer_radius = rr
			ring.mesh = tm
			ring.material_override = _glow_mat(Color(0.9, 0.2, 0.2) if String(b["action"]) == "magnet" else Color(0.55, 0.2, 1.0), 2.0)
			host.add_child(ring)
			ring.transform = xf * Transform3D(Basis.from_euler(Vector3(PI / 2.0, 0.0, 0.0)), d["muzzle"])
			return ring
		"shield":
			_bubble = MeshInstance3D.new()
			var s := SphereMesh.new()
			s.radius = 0.95
			s.height = 1.9
			_bubble.mesh = s
			var m := StandardMaterial3D.new()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.45, 0.25, 1.0, 0.07)
			m.emission_enabled = true
			m.emission = Color(0.45, 0.2, 1.0)
			m.emission_energy_multiplier = 0.35
			m.rim_enabled = true
			m.rim = 1.0
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_bubble.material_override = m
			_bubble.top_level = true
			add_child(_bubble)
			return _bubble
		_:
			var glow := MeshInstance3D.new()
			var sp := SphereMesh.new()
			sp.radius = 0.06
			sp.height = 0.12
			glow.mesh = sp
			glow.material_override = _glow_mat(Color(0.3, 0.9, 1.0) if String(b["action"]) == "repair" else Color(0.6, 0.3, 1.0), 3.0)
			host.add_child(glow)
			glow.transform = xf * Transform3D(Basis(), d["muzzle"])
			return glow


## Узел-группа частиц: visible / emitting переключаются у всех детей (ActiveRig._fx зовёт visible у не-частиц).
func _group_fx(root: Node3D) -> Node3D:
	root.visibility_changed.connect(func() -> void:
		for c in root.get_children():
			if c is CPUParticles3D:
				(c as CPUParticles3D).emitting = root.visible)
	root.visible = false
	return root


func _particles(at: Vector3, dir: Vector3, col: Color, speed: float, amount: int, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = at
	p.amount = amount
	p.lifetime = 0.35
	p.local_coords = false
	p.direction = dir
	p.spread = 12.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = speed * 0.7
	p.initial_velocity_max = speed
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var m := SphereMesh.new()
	m.radius = size
	m.height = size * 2.0
	m.radial_segments = 6
	m.rings = 3
	p.mesh = m
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.7))
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = g
	p.material_override = _glow_mat(col, 3.0, true)
	p.emitting = false
	return p


func _glow_mat(col: Color, energy: float, vertex_colour := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.vertex_color_use_as_albedo = vertex_colour
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if vertex_colour else BaseMaterial3D.TRANSPARENCY_DISABLED
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


func _tracer(a: Vector3, b: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var len := a.distance_to(b)
	bm.size = Vector3(0.012, len, 0.012)
	mi.mesh = bm
	mi.material_override = _glow_mat(Color(1.0, 0.85, 0.35), 3.0)
	mi.top_level = true
	add_child(mi)
	var dir := (b - a).normalized()
	mi.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), (a + b) * 0.5)
	get_tree().create_timer(0.05, true, true).timeout.connect(mi.queue_free)


func _bubble_follow() -> void:
	if _bubble != null and is_instance_valid(doll):
		_bubble.global_position = doll.centre_of_mass()


func _make_bar() -> void:
	_bar_root = Node3D.new()
	_bar_root.name = "ChargeBar"
	_bar_root.top_level = true
	add_child(_bar_root)
	var bg := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(BAR_W + 0.02, BAR_H + 0.02)
	bg.mesh = q
	bg.material_override = _glow_mat(Color(0.05, 0.04, 0.08), 0.0)
	_bar_root.add_child(bg)
	_bar_fill = MeshInstance3D.new()
	var qf := QuadMesh.new()
	qf.size = Vector2(BAR_W, BAR_H)
	_bar_fill.mesh = qf
	_bar_fill.material_override = _glow_mat(COL_CHARGE, 1.5)
	_bar_fill.position = Vector3(0.0, 0.0, 0.002)
	_bar_root.add_child(_bar_fill)
	for ch in range(ActiveBlocks.CHANNELS):
		var pip := MeshInstance3D.new()
		var qp := QuadMesh.new()
		qp.size = Vector2(0.06, 0.06)
		pip.mesh = qp
		pip.material_override = _glow_mat(COL_CH[ch], 2.0)
		pip.position = Vector3(-0.1 + ch * 0.1, 0.075, 0.002)
		_bar_root.add_child(pip)
		_pips.append(pip)


func _update_bar() -> void:
	if _bar_root == null:
		return
	var t := doll.torso()
	if t == null or not doll.alive or not doll.control_enabled:   # стенд мастерской, KO — полоски нет
		_bar_root.visible = false
		return
	_bar_root.visible = true
	var head := doll.get_node_or_null(String(doll.uid_body.get("H", ""))) as Node3D
	var top := head.global_position + Vector3(0.0, BAR_UP, 0.0) if head != null else t.global_position + Vector3(0.0, 0.9, 0.0)
	_bar_root.global_transform = Transform3D(Basis(), top + Vector3(0.0, 0.0, 0.3))
	var k := clampf(charge / maxf(charge_max, 1.0), 0.0, 1.0)
	_bar_fill.scale = Vector3(maxf(k, 0.001), 1.0, 1.0)
	_bar_fill.position.x = -BAR_W * 0.5 * (1.0 - k)
	(_bar_fill.material_override as StandardMaterial3D).albedo_color = COL_CHARGE if k > 0.2 else COL_LOW
	(_bar_fill.material_override as StandardMaterial3D).emission = COL_CHARGE if k > 0.2 else COL_LOW
	for ch in range(_pips.size()):
		var has := blocks.any(func(b: Dictionary) -> bool: return int(b["channel"]) == ch + 1)
		_pips[ch].visible = has
		_pips[ch].scale = Vector3.ONE * (1.6 if running[ch] else 1.0)
