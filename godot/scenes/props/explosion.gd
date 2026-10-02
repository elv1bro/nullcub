## Взрыв (29.09: «бочки взрывались, на крутых эффектах»). Explosion.detonate(parent, pos, by) — один вызов делает всё:
##
## Физика и урон (радиус RADIUS, спад f = 1 − d/RADIUS по ближайшей части / центру тела):
##   • куклы (группа Match.dolls_group, иначе "dolls"): урон DOLL_DAMAGE_MAX · f^0.7 в ближайшую часть (kind "weapon", weapon_id
##     "explosion", attacker — by; своя кукла — kind "self" без атакующего), отброс DOLL_IMPULSE_MAX · f от центра с прибавкой вверх,
##     стан Damage.stun_seconds; Match.on_hit — надписи, HUD, звук удара. Урон — только пока Match.combat_active() (или Match нет);
##     отброс — всегда;
##   • свободные тела (RigidBody3D в радиусе, не части кукол): импульс m · PROP_KICK_SPEED · f (не больше PROP_IMPULSE_MAX) +
##     закрутка; тяжёлые снимаются с якоря (PropHeft.kick) — взрыв единственное, что сдвигает вагон;
##   • Breakable: урон PROP_DAMAGE_MAX · f (ящики разлетаются), ExplosiveBarrel — поджиг с короткой задержкой CHAIN_DELAY_S
##     (цепная реакция «бах-бах-бах», а не один кадр);
## Эффекты (всё само освобождается): огненный шар (3 сферы: белое ядро → оранжевый → тёмный дым, рост и гашение), вспышка света
## OmniLight, две ударные волны (оранжевая и белое ядро — HitFxDirector.spawn_wave, иначе своя), искры SparkCone веером, щепки
## и пыль ImpactFx, клубы дыма HitFxDirector.puff, белый кадр, тряска и толчок зума камеры, короткий стоп-кадр Match, звук boom + crash.
class_name Explosion
extends Node3D

const RADIUS := 3.2
const DOLL_DAMAGE_MAX := 42.0        # HP в эпицентре (кукла 100 HP: бочка под ногами — почти половина)
const DOLL_DAMAGE_MIN := 3.0         # меньше — не засчитываем
const DOLL_IMPULSE_MAX := 380.0      # Н·с: кукла 40 кг в эпицентре улетает ~9.5 м/с
const UP_BIAS := 0.45
const PROP_KICK_SPEED := 11.0        # м/с добавки в эпицентре
const PROP_IMPULSE_MAX := 700.0      # Н·с: вагон 140 кг получит 5 м/с
const PROP_SPIN := 6.0               # рад/с закрутки в эпицентре
const PROP_DAMAGE_MAX := 60.0        # Breakable в эпицентре (ящик 20 HP — в щепки до 2.2 м)
const CHAIN_DELAY_S := 0.16
const SHAKE_M := 0.55
const HITSTOP_SCALE := 0.15
const HITSTOP_S := 0.06
const WEAPON_ID := "explosion"
const SHOCKWAVE_SCENE := "res://scenes/fx/shockwave.tscn"

const FIRE_S := 0.55
const SMOKE_S := 1.5
const LIGHT_S := 0.5
const LIGHT_ENERGY := 14.0
const SPARKS := 9

signal detonated(pos: Vector3, hits: Array)

## Для проб: {doll, damage, part} по жертвам и тела, получившие импульс.
var hits: Array = []
var kicked: Array = []
var _t := 0.0
var _balls: Array = []    # [MeshInstance3D, StandardMaterial3D, r0, r1, delay, colour_from, colour_to, life, pos0, drift]
var _light: OmniLight3D


## Взорвать в pos (в игре — плоскость z = 0). by — кому засчитать (Doll | null). ignore — тело, которое взрывается (не толкать себя).
static func detonate(parent: Node, pos: Vector3, by: Node = null, ignore: Node = null) -> Explosion:
	if parent == null or not parent.is_inside_tree():
		return null
	var e := Explosion.new()
	e.name = "Explosion"
	parent.add_child(e)
	e.global_position = pos   # плоскость боя z = 0; пробы раскладывают пропсы по дорожкам z — взрыв остаётся на своей
	e._blast(by, ignore)
	e._effects()
	e.detonated.emit(e.global_position, e.hits)
	return e


static func falloff(d: float) -> float:
	return clampf(1.0 - d / RADIUS, 0.0, 1.0)


func _match() -> Node:
	return get_tree().get_first_node_in_group("match")


# ------------------------------------------------------------------ физика и урон

func _blast(by: Node, ignore: Node) -> void:
	var p := global_position
	var m := _match()
	var combat := m == null or not m.has_method("combat_active") or bool(m.call("combat_active"))
	var group := String(m.get("dolls_group")) if m != null and m.get("dolls_group") != null else "dolls"
	var by_doll := by as Doll if by != null and is_instance_valid(by) else null
	# куклы
	var seen_parts: Dictionary = {}
	for n in get_tree().get_nodes_in_group(group):
		var d := n as Doll
		if d == null or not is_instance_valid(d):
			continue
		var best: RigidBody3D = null
		var best_d := INF
		for part in d.parts.values():
			var rb := part as RigidBody3D
			if rb == null or not is_instance_valid(rb):
				continue
			seen_parts[rb] = true
			var dist := Vector3(rb.global_position.x - p.x, rb.global_position.y - p.y, 0.0).length()
			if dist < best_d:
				best_d = dist
				best = rb
		var f := falloff(best_d)
		if best == null or f <= 0.0:
			continue
		var com: Vector3 = d.centre_of_mass() if d.has_method("centre_of_mass") else best.global_position
		var dir := Vector3(com.x - p.x, com.y - p.y, 0.0)
		dir = dir.normalized() if dir.length_squared() > 1e-4 else Vector3.UP
		dir = (dir + Vector3.UP * UP_BIAS).normalized()
		var dmg := DOLL_DAMAGE_MAX * pow(f, 0.7)
		var stun_s := 0.0
		if combat and dmg >= DOLL_DAMAGE_MIN and d.alive and d.can_take_damage():
			stun_s = Damage.stun_seconds(dmg)
			var self_hit := by_doll == d
			var attacker: Node = null if self_hit else by_doll
			d.hit_meta = {"speed": PROP_KICK_SPEED * f, "weapon_id": WEAPON_ID, "striker": self, "combo_mult": 1.0,
				"double_blow": false, "knockback_mult": 1.0, "stun_s": stun_s, "explosion": true}
			d.take_damage(dmg, attacker, String(best.name), best.global_position, -dir, "self" if self_hit else "weapon")
			if attacker != null:
				var s: Dictionary = (attacker as Doll).stats
				s["damage_dealt"] = float(s.get("damage_dealt", 0.0)) + dmg
				s["hardest_hit"] = maxf(float(s.get("hardest_hit", 0.0)), dmg)
			hits.append({"doll": d, "damage": dmg, "part": String(best.name), "falloff": f})
			if m != null and m.has_method("on_hit"):
				m.call("on_hit", d, attacker, dmg, "weapon", best.global_position, 0, false, WEAPON_ID, PROP_KICK_SPEED * f)
		if not d.is_broken():
			d.apply_knockback(dir * DOLL_IMPULSE_MAX * f, best, stun_s, dir, Tuning.KNOCKBACK_MIN * f)
			if stun_s > 0.0 and d.alive:
				d.stun(stun_s)
		else:
			for part in d.parts.values():
				if is_instance_valid(part):
					(part as RigidBody3D).apply_central_impulse(dir * DOLL_IMPULSE_MAX * f / maxf(d.parts.size(), 1))
	# свободные тела
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = RADIUS
	q.shape = sph
	q.transform = Transform3D(Basis.IDENTITY, p)
	q.collide_with_areas = false
	q.collide_with_bodies = true
	for r in space.intersect_shape(q, 64):
		var b := r.get("collider") as RigidBody3D
		if b == null or b == ignore or seen_parts.has(b) or b.get_parent() is Doll or not is_instance_valid(b):
			continue
		var c := b.global_position
		var st := PhysicsServer3D.body_get_direct_state(b.get_rid())
		if st != null:
			c += st.center_of_mass
		var dv := Vector3(c.x - p.x, c.y - p.y, 0.0)
		var f := falloff(_near_dist(b, p))   # до ближайшей точки коллизий: у вагона 2.4 м центр далеко, а борт рядом
		if f <= 0.0:
			continue
		var dir := dv.normalized() if dv.length_squared() > 1e-4 else Vector3.UP
		dir = (dir + Vector3.UP * UP_BIAS).normalized()
		if b is ExplosiveBarrel:
			(b as ExplosiveBarrel).ignite(CHAIN_DELAY_S * randf_range(0.8, 1.4), by)
		elif b is Breakable:
			(b as Breakable).take_damage(PROP_DAMAGE_MAX * f)
		var imp := dir * minf(b.mass * PROP_KICK_SPEED * f, PROP_IMPULSE_MAX * f)
		PropHeft.kick(b, imp)
		if not b.freeze:
			b.angular_velocity += Vector3(0.0, 0.0, randf_range(-1.0, 1.0) * PROP_SPIN * f)
		kicked.append(b)


## Расстояние в плоскости XY от p до ближайшей точки AABB коллизий тела (по фигурам CollisionShape3D; без фигур — до центра).
static func _near_dist(b: RigidBody3D, p: Vector3) -> float:
	var best := INF
	for c in b.get_children():
		var cs := c as CollisionShape3D
		if cs == null or cs.shape == null or cs.disabled:
			continue
		var dm := cs.shape.get_debug_mesh()
		if dm == null:
			continue
		var box := cs.global_transform * dm.get_aabb()
		var q := Vector3(clampf(p.x, box.position.x, box.end.x), clampf(p.y, box.position.y, box.end.y), 0.0)
		best = minf(best, Vector3(q.x - p.x, q.y - p.y, 0.0).length())
	if best == INF:
		best = Vector3(b.global_position.x - p.x, b.global_position.y - p.y, 0.0).length()
	return best


# ------------------------------------------------------------------ эффекты

func _effects() -> void:
	var p := global_position
	var dir_fx := get_tree().get_first_node_in_group(HitFxDirector.GROUP) as HitFxDirector
	# огненный шар: ядро, пламя, дым
	# дым (позади огня): клубы поднимаются и расползаются
	for i in 6:
		var o := Vector3(randf_range(-0.9, 0.9), randf_range(0.1, 0.9), 0.0)
		_ball(Color(0.2, 0.17, 0.15, 0.0), Color(0.1, 0.09, 0.08, 0.0), 0.5, randf_range(1.4, 2.0), 0.06 + randf() * 0.1,
			SMOKE_S * randf_range(0.8, 1.2), o, Vector3(o.x * 0.6, randf_range(1.2, 2.0), 0.0), false)
	# огонь: клубы вокруг центра, оранжевые → тёмно-красные
	for i in 7:
		var o := Vector3(randf_range(-0.7, 0.7), randf_range(-0.1, 0.8), 0.0)
		_ball(Color(1.0, 0.62, 0.18, 1.0), Color(0.6, 0.1, 0.02, 0.0), 0.3, randf_range(1.0, 1.6), randf() * 0.05,
			FIRE_S * randf_range(0.7, 1.1), o, Vector3(0.0, 0.5, 0.0))
	# белое ядро
	_ball(Color(1.0, 0.97, 0.88, 1.0), Color(1.0, 0.8, 0.4, 0.0), 0.4, 2.0, 0.0, 0.2)
	# свет
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.62, 0.25)
	_light.light_energy = LIGHT_ENERGY
	_light.omni_range = RADIUS * 2.6
	_light.shadow_enabled = false
	add_child(_light)
	_light.position = Vector3(0.0, 0.3, 1.2)
	# волны
	if dir_fx != null:
		dir_fx.spawn_wave(p, 0.4, RADIUS * 1.15, 320.0, Color(1.0, 0.6, 0.2, 0.95))
		dir_fx.spawn_wave(p, 0.2, RADIUS * 0.6, 170.0, Color(1.0, 0.97, 0.9, 1.0))
		dir_fx.white_flash(0.3)
		for i in 5:
			var a := TAU * float(i) / 5.0 + randf() * 0.6
			dir_fx.puff(p + Vector3(cos(a), sin(a) * 0.6 + 0.3, 0.0) * 0.7, Vector3(cos(a), absf(sin(a)) + 0.4, 0.0), 2.4)
	elif ResourceLoader.exists(SHOCKWAVE_SCENE):
		var w := (load(SHOCKWAVE_SCENE) as PackedScene).instantiate() as Shockwave
		if w != null:
			add_child(w)
			w.setup(p, 0.4, RADIUS * 1.15, 320.0, Color(1.0, 0.6, 0.2, 0.95))
	# искры веером
	for i in SPARKS:
		var a := TAU * float(i) / float(SPARKS) + randf_range(-0.2, 0.2)
		var sc := SparkCone.new()
		sc.name = "Spark"
		add_child(sc)
		sc.setup(p, Vector3(cos(a), sin(a), 0.0), Color(1.0, 0.55 + randf() * 0.3, 0.15), 1.6)
	ImpactFx.spawn_impact(get_parent(), p, Vector3.UP, 22.0, "weapon")
	# камера, время, звук
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam != null:
		if cam.has_method("shake"):
			cam.call("shake", SHAKE_M)
		if cam.has_method("zoom_impulse"):
			cam.call("zoom_impulse", -0.07, 0.3)
	var m := _match()
	if m != null and m.has_method("request_time_scale"):
		m.call("request_time_scale", HITSTOP_SCALE, HITSTOP_S, "explosion")
	var sfx := get_tree().get_first_node_in_group(SfxDirector.GROUP) as SfxDirector
	if sfx != null:
		var pan := sfx.pan_for(p)
		sfx.play_layer("explosion", 2.0, randf_range(0.92, 1.05), SfxDirector.BUS_SFX, pan)
		sfx.play_layer("boom", -4.0, 0.8, SfxDirector.BUS_SFX, pan)
		sfx.play_layer("crash", -3.0, 0.85, SfxDirector.BUS_SFX, pan)
		sfx.play_layer("clank", -6.0, 0.8, SfxDirector.BUS_SFX, pan)
	var crowd := get_tree().get_first_node_in_group(CrowdDirector.GROUP) as CrowdDirector
	if crowd != null:
		crowd.bump(0.25)
		crowd.react("crowd_ooh", 0.0, "explosion", true, 250.0)


## Мягкий клуб (billboard-квад с радиальным градиентом, аддитивный — огонь, обычный — дым): растёт r0 → r1 с ease-out за life,
## цвет from → to, сдвиг drift за жизнь (дым поднимается). Поверх пола (no_depth_test), иначе нижняя половина режется полом.
func _ball(from: Color, to: Color, r0: float, r1: float, delay: float, life: float, offset: Vector3 = Vector3.ZERO,
		drift: Vector3 = Vector3.ZERO, additive: bool = true) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = _puff_texture()
	mat.albedo_color = from
	mat.no_depth_test = true
	mat.render_priority = 7 if additive else 6
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * 0.001
	mi.position = offset + Vector3(0.0, 0.0, 0.4)
	add_child(mi)
	_balls.append([mi, mat, r0, r1, delay, from, to, life, offset + Vector3(0.0, 0.0, 0.4), drift])


static var _puff_tex: GradientTexture2D


static func _puff_texture() -> GradientTexture2D:
	if _puff_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 0.8, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.75), Color(1, 1, 1, 0.22), Color(1, 1, 1, 0)])
		_puff_tex = GradientTexture2D.new()
		_puff_tex.gradient = g
		_puff_tex.fill = GradientTexture2D.FILL_RADIAL
		_puff_tex.fill_from = Vector2(0.5, 0.5)
		_puff_tex.fill_to = Vector2(1.0, 0.5)
		_puff_tex.width = 128
		_puff_tex.height = 128
	return _puff_tex


## Время эффектов — реальное (delta / time_scale): стоп-кадр не замораживает огонь.
func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	_t += real
	var alive := false
	for b in _balls:
		var mi: MeshInstance3D = b[0]
		var life: float = b[7]
		if _t < float(b[4]):
			alive = true
			continue
		var k := clampf((_t - float(b[4])) / life, 0.0, 1.0)
		var grow := 1.0 - pow(1.0 - k, 3.0)
		mi.scale = Vector3.ONE * lerpf(float(b[2]), float(b[3]), grow)
		var c := (b[5] as Color).lerp(b[6], k)
		if (b[5] as Color).a <= 0.001:   # дым: проявляется и гаснет
			c.a = 0.62 * sin(PI * minf(k * 1.4, 1.0)) * (1.0 - k)
		(b[1] as StandardMaterial3D).albedo_color = c
		mi.position = (b[8] as Vector3) + (b[9] as Vector3) * grow
		if k < 1.0:
			alive = true
	if _light != null:
		var lk := clampf(_t / LIGHT_S, 0.0, 1.0)
		_light.light_energy = LIGHT_ENERGY * (1.0 - lk) * (1.0 - lk)
		if lk < 1.0:
			alive = true
	if not alive and _t > 2.0:
		queue_free()
