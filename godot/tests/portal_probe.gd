## Проба порталов (docs/plan-demo/PORTAL.md; scripts/portal/, scenes/portal/portal_pair.tscn, комнаты 7–8 демо головоломок).
## Помощники (кукла, ящики, рука, площадка, сценарии комнат _solve_7 / _solve_8) — из tests/puzzle_probe.gd (наследник).
## Секции (only=doll|props|rooms, несколько — через «+», пусто — все):
##   doll  — пары пол→стена, стена→стена лицом друг к другу и в одну сторону, стена→потолок: кукла влетает в A и переносится целиком;
##           скорость ЦМ через тик после переноса — ±5 % от скорости до; направление — по нормали выхода (не дальше 5° сверх угла входа)
##           и ровно повёрнутая скорость входа (±5°); суставы не растянуты (разрыв ≤ 0.05 м за 0.5 с); через 1 с ни одна деталь не
##           в статике, ЦМ перед выходом; пинг-понг: в паре лицом друг к другу — не больше 2 переносов за 3 с; выключенная пара не
##           переносит и гаснет, включили — перенесла; «стрелочник»: ток на switch_input ведёт A в B2, B горит тускло; что в руке:
##           лёгкий ящик (приварен) и средний (на пружине) едут с куклой и остаются в руке, ящик «вдвоём», который держит и вторая
##           кукла, — рука отпускает (reason portal), ящик остаётся;
##   props — ящики 10 / 35 / 90 кг и взрывная бочка в тех же парах (скорость, направление, не в стене); ящик, лежащий в кармане, —
##           один перенос; держимый рукой ящик в кармане сам не уходит, отпустили — ушёл; замороженный — нет;
##   rooms — комнаты 7 «Разгон» и 8 «Стрелочник» на настоящей площадке: вдвоём и соло сценарием (дверь закрыта в начале → решено →
##           выход в тамбур), плюс проверки самих комнат.
## Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/portal_probe.tscn -- "only=doll,trace=1,out=<json>"
## → JSON между === PORTAL PROBE === и === OK / FAIL ===, exit 0/1; errors_script — SCRIPT ERROR за прогон (Logger).
extends "res://tests/puzzle_probe.gd"

const PAIR := "res://scenes/portal/portal_pair.tscn"
const SPEED := 6.0
const START_M := 1.3
const SPEED_TOL := 0.05
const DIR_TOL_DEG := 5.0
const JOINT_GAP_MAX := 0.05

## Пары: [имя, A (x, y, угол°), B (x, y, угол°)]. Угол — поворот щели вокруг Z: 0 пол, 180 потолок, −90 стена слева, 90 справа.
const CASES := [
	["floor_wall", Vector3(0, 0, 0), Vector3(-10, 5, -90)],
	["wall_wall_facing", Vector3(6, 4, 90), Vector3(-6, 4, -90)],
	["wall_wall_same", Vector3(-6, 2, -90), Vector3(-14, 6, -90)],
	["wall_ceiling", Vector3(-6, 3, -90), Vector3(4, 10, 180)],
	["floor_wall_fall", Vector3(0, 0, 0), Vector3(-10, 5, -90)],   # подлёт с гравитацией: падает в щель с 2.2 м
]


func _ready() -> void:
	OS.add_logger(errs)
	print("=== PORTAL PROBE ===")
	var a := _args()
	trace = String(a["trace"]) == "1"
	if _want(a, "doll"):
		await _doll_section()
	if _want(a, "props"):
		await _props_section()
	if _want(a, "rooms"):
		await _rooms_section()
	_clear_world()
	await _unload()
	_check("errors_script", errs.count == 0, "ошибок скриптов %d; первая: %s" % [errs.count, errs.first])
	var report := {"ok": ok, "checks": checks, "info": info}
	print(JSON.stringify(report, " "))
	if String(a["out"]) != "":
		var f := FileAccess.open(String(a["out"]), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(report, " "))
			f.close()
	print("=== OK ===" if ok else "=== FAIL ===")
	OS.remove_logger(errs)
	get_tree().quit(0 if ok else 1)


# ------------------------------------------------------------------ мир с парой

## Мир: для каждого прохода — плита-поверхность (по 5 м с обеих сторон щели, толщина 1 м за плоскостью) и пара порталов.
func _pair_world(pa: Vector3, pb: Vector3, set_props := {}, alt := Vector3.INF) -> PortalPair:
	_clear_world()
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	var st := StaticBody3D.new()
	st.name = "Static"
	world.add_child(st)
	var list := [pa, pb]
	if alt != Vector3.INF:
		list.append(alt)
	for p in list:
		_slab(st, p)
	var pair := (load(PAIR) as PackedScene).instantiate() as PortalPair
	pair.name = "Pair"
	pair.a_position = Vector3(pa.x, pa.y, 0)
	pair.a_angle_deg = pa.z
	pair.b_position = Vector3(pb.x, pb.y, 0)
	pair.b_angle_deg = pb.z
	if alt != Vector3.INF:
		pair.alt_enabled = true
		pair.alt_position = Vector3(alt.x, alt.y, 0)
		pair.alt_angle_deg = alt.z
	for k in set_props:
		pair.set(k, set_props[k])
	world.add_child(pair)
	return pair


func _slab(st: StaticBody3D, p: Vector3) -> void:
	var ang := deg_to_rad(p.z)
	var t := Vector3(cos(ang), sin(ang), 0)
	var n := Vector3(-sin(ang), cos(ang), 0)
	var w: float = Tuning.PORTAL_WIDTH
	for s in [-1.0, 1.0]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(5.0, 1.0, 4.0)
		cs.shape = bs
		var c: Vector3 = Vector3(p.x, p.y, 0) + t * float(s) * (w * 0.5 + 2.5) - n * 0.5
		cs.transform = Transform3D(Basis(Vector3(0, 0, 1), ang), c)
		st.add_child(cs)


## Гравитация деталей куклы выкл / вкл (кукла встаёт в позу в невесомости, вдали от всего).
func _zero_g(d: Doll, on: bool, extra: Array = []) -> void:
	for b in d.parts.values():
		(b as RigidBody3D).gravity_scale = 0.0 if on else 1.0
	if not on:
		d._apply_gravity_scale()
	for e in extra:
		var rb := e as RigidBody3D
		rb.gravity_scale = 0.0 if on else float(rb.get_meta("g_saved", 1.0))


## Кукла P(i+1) с рукой, в невесомости в точке at (вдали от плит), встала в позу.
func _ready_doll(i: int, at: Vector3, arm := true) -> Doll:
	var d := _doll(i, at, arm)
	d.brake_off = true
	await _ticks(2)
	_zero_g(d, true)
	await _wait(0.4)
	return d


## Поставить ЦМ куклы (и тела extra — тем же сдвигом) на start_m перед проходом p и пустить в щель со скоростью speed.
func _aim(d: Doll, p: Portal, speed: float, start_m: float, extra: Array = []) -> void:
	var n := p.normal()
	var to := p.global_position + n * start_m
	var shift := to - d.centre_of_mass()
	shift.z = 0.0
	var v := -n * speed
	var bodies: Array = d.parts.values()
	bodies.append_array(extra)
	for b in bodies:
		var rb := b as RigidBody3D
		rb.global_position += shift
		rb.linear_velocity = v
		rb.angular_velocity = Vector3.ZERO
		rb.reset_physics_interpolation()


## Наибольший разрыв суставов куклы (м): точка сустава по родителю и по ребёнку (кадры сборки, как якоря Jolt).
func _joint_gap(d: Doll) -> float:
	var worst := 0.0
	for jn in d.joints.keys():
		var j := d.joints[jn] as Generic6DOFJoint3D
		if j == null or not is_instance_valid(j) or not d._joint_xf_a.has(jn) or not d._joint_xf_b.has(jn):
			continue
		var ba := j.get_node_or_null(j.node_a) as RigidBody3D
		var bb := j.get_node_or_null(j.node_b) as RigidBody3D
		if ba == null or bb == null:
			continue
		var pa: Vector3 = ba.global_transform * (d._joint_xf_a[jn] as Transform3D).origin
		var pb: Vector3 = bb.global_transform * (d._joint_xf_b[jn] as Transform3D).origin
		worst = maxf(worst, pa.distance_to(pb))
	return worst


## Сколько тел из list пересекают статику (застряли в стене).
func _in_static(pair: PortalPair, list: Array) -> int:
	var space := pair.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var excl: Array[RID] = []
	for b in list:
		excl.append((b as RigidBody3D).get_rid())
	q.exclude = excl
	q.collide_with_areas = false
	var n := 0
	for b in list:
		var rb := b as RigidBody3D
		for cs in PortalPair._shapes(rb):
			q.shape = (cs as CollisionShape3D).shape
			q.transform = (cs as CollisionShape3D).global_transform
			q.margin = -0.02   # касание — не застревание
			var hit := false
			for h in space.intersect_shape(q, 4):
				if h.get("collider") is StaticBody3D:
					hit = true
			if hit:
				n += 1
				break
	return n


static func _deg(a: Vector3, b: Vector3) -> float:
	if a.length() < 1e-4 or b.length() < 1e-4:
		return 180.0
	return rad_to_deg(a.angle_to(b))


func _r(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01)]


# ------------------------------------------------------------------ doll

func _doll_section() -> void:
	print("--- doll")
	for c in CASES:
		await _doll_case(String(c[0]), c[1], c[2])
	await _doll_off()
	await _doll_alt()
	await _doll_held_light()
	await _doll_held_medium()
	await _doll_held_duo()
	_clear_world()


## Кукла влетает в A пары case: перенос, скорость, направление, суставы, не в стене; в паре лицом друг к другу — пинг-понг.
## Подлёт к щели — в невесомости (вход строго по нормали, без провиса от g), сразу после переноса гравитация включается.
func _doll_case(name: String, pa: Vector3, pb: Vector3) -> void:
	var pair := _pair_world(pa, pb)
	var d := await _ready_doll(0, Vector3(30, -30, 0), false)
	var gap0 := _joint_gap(d)
	var fall := name.ends_with("_fall")
	_aim(d, pair.a, 1.0 if fall else SPEED, 2.2 if fall else START_M)
	if fall:
		_zero_g(d, false)
	var moved := await _until(func() -> bool: return pair.transfers > 0, 5.0 if fall else 2.0)
	_zero_g(d, false)
	if not moved:
		_check("doll_%s" % name, false, "перенос не случился: ЦМ %s" % str(_r(d.centre_of_mass())))
		if trace:
			for pn in d.parts:
				var body := d.parts[pn] as RigidBody3D
				print("    %s at %s box %s" % [pn, str(_r(body.global_position)), str(PortalPair.local_box(body))])
		d.queue_free()
		return
	var h: Dictionary = pair.history[0]
	var v_in: Vector3 = h["v_in"]
	var v1 := d.com_velocity()
	var nb := pair.b.normal()
	var rot := PortalPair.mapping(pair.a, pair.b).basis
	var ratio := v1.length() / maxf(v_in.length(), 1e-4)
	var dev_in := _deg(v_in, -pair.a.normal())
	var dev_out := _deg(v1, nb)
	var dev_map := _deg(v1, rot * v_in)
	var gap := 0.0
	for k in 30:
		gap = maxf(gap, _joint_gap(d))
		await get_tree().physics_frame
	await _wait(0.5)
	var stuck := _in_static(pair, d.parts.values())
	var ahead := pair.b.height_of(d.centre_of_mass())
	var extra := 0
	if name == "wall_wall_facing":
		var t0 := pair.transfers
		await _wait(2.5)
		extra = pair.transfers - t0
	var rec := {"v_in": snappedf(v_in.length(), 0.01), "v_after_tick": snappedf(v1.length(), 0.01), "ratio": snappedf(ratio, 0.001),
		"dev_in_deg": snappedf(dev_in, 0.1), "dev_out_deg": snappedf(dev_out, 0.1), "dev_map_deg": snappedf(dev_map, 0.1),
		"joint_gap_m": snappedf(gap, 0.001), "joint_gap0_m": snappedf(gap0, 0.001), "shift_m": snappedf(float(h["shift"]), 0.01),
		"stuck_parts": stuck, "com_ahead_m": snappedf(ahead, 0.01), "transfers": pair.transfers}
	info["doll_" + name] = rec
	_check("doll_%s_speed" % name, absf(ratio - 1.0) <= SPEED_TOL, "|v| через тик / до: %.3f (%.2f → %.2f м/с)" % [ratio, v_in.length(), v1.length()])
	_check("doll_%s_dir" % name, dev_out <= dev_in + DIR_TOL_DEG and dev_map <= DIR_TOL_DEG,
		"к нормали выхода %.1f° (вход %.1f° к нормали), к повёрнутой скорости %.1f°" % [dev_out, dev_in, dev_map])
	_check("doll_%s_joints" % name, gap <= JOINT_GAP_MAX, "разрыв суставов %.3f м (до запуска %.3f)" % [gap, gap0])
	_check("doll_%s_not_stuck" % name, stuck == 0 and ahead > 0.3, "деталей в статике %d, ЦМ перед выходом %.2f м" % [stuck, ahead])
	if name == "wall_wall_facing":
		_check("doll_pingpong", extra <= 1 and pair.transfers <= 2, "переносов за 3 с: %d (после первого ещё %d)" % [pair.transfers, extra])
	d.queue_free()
	await _ticks(2)


## Пара без тока: не переносит, проходы погасли; ток дали — кукла из кармана ушла.
func _doll_off() -> void:
	var src := PuzzlePart.new()
	var pair := _pair_world(Vector3(0, 0, 0), Vector3(-10, 5, -90))
	src.name = "Source"
	world.add_child(src)
	pair.input = pair.get_path_to(src)
	var d := await _ready_doll(0, Vector3(30, -30, 0), false)
	_aim(d, pair.a, 4.0, 1.6)
	_zero_g(d, false)
	await _wait(1.5)
	var looks_off := pair.a.lit == Portal.Lit.OFF and pair.b.lit == Portal.Lit.OFF
	var none := pair.transfers == 0
	var in_pocket := pair.a.height_of(d.centre_of_mass()) < 0.0
	src._set_on(true)
	var moved := await _until(func() -> bool: return pair.transfers > 0, 1.0)
	var lit := pair.a.lit == Portal.Lit.ACTIVE
	info["doll_off"] = {"transfers_off": 0 if none else pair.transfers, "com_in_pocket": in_pocket, "looks_off": looks_off,
		"moved_when_on": moved, "lit_when_on": lit}
	_check("portal_off_no_transfer", none and looks_off, "без тока переносов %d, проходы погасли %s (ЦМ в кармане %s)" % [pair.transfers if not none else 0, str(looks_off), str(in_pocket)])
	_check("portal_on_transfers", moved and lit, "ток дали — кукла из кармана ушла %s, горит %s" % [str(moved), str(lit)])
	d.queue_free()
	await _ticks(2)


## «Стрелочник»: switch_input с током — A ведёт в B2; без тока — в B (B2 тускло).
func _doll_alt() -> void:
	var pair := _pair_world(Vector3(0, 0, 0), Vector3(-10, 5, -90), {}, Vector3(10, 5, 90))
	var sw := PuzzlePart.new()
	sw.name = "Switch"
	world.add_child(sw)
	pair.switch_input = pair.get_path_to(sw)
	await _ticks(2)
	var idle_alt := pair.alt.lit == Portal.Lit.IDLE and pair.b.lit == Portal.Lit.ACTIVE
	var d := await _ready_doll(0, Vector3(30, -30, 0), false)
	_aim(d, pair.a, SPEED, 1.6)
	_zero_g(d, false)
	await _until(func() -> bool: return pair.transfers > 0, 2.0)
	var first: String = String(pair.history[0]["to"]) if pair.transfers > 0 else "-"
	sw._set_on(true)
	await _wait(0.5)
	var idle_b := pair.b.lit == Portal.Lit.IDLE and pair.alt.lit == Portal.Lit.ACTIVE
	_zero_g(d, true)
	await _wait(0.3)
	_aim(d, pair.a, SPEED, 1.6)
	_zero_g(d, false)
	await _until(func() -> bool: return pair.transfers > 1, 2.0)
	var second: String = String(pair.history[1]["to"]) if pair.transfers > 1 else "-"
	var vx := d.com_velocity().x
	info["doll_alt"] = {"first_to": first, "second_to": second, "vx_after": snappedf(vx, 0.01), "looks_ok": idle_alt and idle_b}
	_check("portal_switch", first == "B" and second == "B2" and vx < -1.0 and idle_alt and idle_b,
		"без тока — в %s, с током — в %s (vx %.1f), тусклый невыбранный выход %s" % [first, second, vx, str(idle_alt and idle_b)])
	d.queue_free()
	await _ticks(2)


## Подвести ящик к руке куклы в невесомости и схватить; true — держит (и приварен, если лёгкий).
func _hold_crate(d: Doll, kind: String) -> PuzzleCrate:
	var arm := _arm(d)
	var c := _crate(kind, d.centre_of_mass() + Vector3(-1.0, 0.0, 0))
	c.set_meta("g_saved", c.gravity_scale)
	await _ticks(1)
	c.gravity_scale = 0.0
	if not await _grab_with(arm, c):
		return null
	arm.set_target_override(arm.root_point() + Vector3(-arm.reach * 0.8, 0.0, 0))
	await _wait(0.6)
	return c


## Лёгкий ящик 10 кг (приварен) едет с куклой через пол → стена и остаётся в руке.
func _doll_held_light() -> void:
	var pair := _pair_world(Vector3(0, 0, 0), Vector3(-10, 5, -90))
	var d := await _ready_doll(0, Vector3(30, -30, 0), true)
	var c := await _hold_crate(d, "light")
	var arm := _arm(d)
	if c == null:
		_check("held_light_carried", false, "не схватила ящик")
		d.queue_free()
		return
	var welded := arm.is_welded()
	var off0 := c.global_position - arm.grip_global()
	_aim(d, pair.a, 5.0, 2.0, [c])
	_zero_g(d, false, [c])
	var moved := await _until(func() -> bool: return pair.transfers > 0, 2.0)
	await _wait(0.3)
	var held := arm.held == c
	var dist := arm.hold_distance()
	var carried := int(pair.history[0]["carried"]) if moved else 0
	var gap := _joint_gap(d)
	info["held_light"] = {"welded": welded, "moved": moved, "carried": carried, "still_held": held, "hold_dist_m": snappedf(dist, 0.001),
		"crate_ahead_m": snappedf(pair.b.height_of(c.global_position), 0.01), "joint_gap_m": snappedf(gap, 0.001), "offset0": _r(off0)}
	_check("held_light_carried", moved and carried == 1 and held and dist < 0.1 and gap <= JOINT_GAP_MAX,
		"приварен %s; перенесён с куклой %s, всё ещё в руке %s, хват %.3f м, суставы %.3f м" % [str(welded), str(carried == 1), str(held), dist, gap])
	d.queue_free()
	c.queue_free()
	await _ticks(2)


## Средний ящик 35 кг (на пружине) едет с куклой и не срывается.
func _doll_held_medium() -> void:
	var pair := _pair_world(Vector3(0, 0, 0), Vector3(-10, 5, -90))
	var d := await _ready_doll(0, Vector3(30, -30, 0), true)
	var c := await _hold_crate(d, "medium")
	var arm := _arm(d)
	if c == null:
		_check("held_medium_carried", false, "не схватила ящик")
		d.queue_free()
		return
	var s0 := arm.hold_distance()
	_aim(d, pair.a, 4.0, 1.8, [c])
	_zero_g(d, false, [c])
	var moved := await _until(func() -> bool: return pair.transfers > 0, 2.0)
	var s1 := arm.hold_distance()
	await _wait(0.3)
	var held := arm.held == c
	var carried := int(pair.history[0]["carried"]) if moved else 0
	info["held_medium"] = {"moved": moved, "carried": carried, "still_held": held, "stretch_before": snappedf(s0, 0.01),
		"stretch_after": snappedf(s1, 0.01)}
	_check("held_medium_carried", moved and carried == 1 and held, "перенесён с куклой %s, в руке через 0.3 с %s, растяжение %.2f → %.2f м" % [
		str(carried == 1), str(held), s0, s1])
	d.queue_free()
	c.queue_free()
	await _ticks(2)


## Ящик «вдвоём»: держат две куклы (стоят на полу у щели, как в комнате 3), P1 уходит в портал — его рука отпускает («portal»),
## ящик остаётся у P2. Перенос — PortalPair.transfer_doll (тот же путь, что от щели; живой полёт к щели с ящиком 60 кг на пружине
## рвёт хват раньше — slip).
func _doll_held_duo() -> void:
	var pair := _pair_world(Vector3(0, 0, 0), Vector3(-10, 5, -90))
	var c := _crate("duo", Vector3(3.6, 0.52, 0))
	var d1 := _doll(0, Vector3(2.6, 0.05, 0), true)
	var d2 := _doll(1, Vector3(4.6, 0.05, 0), true)
	await _wait(0.6)
	var a1 := _arm(d1)
	var a2 := _arm(d2)
	var g1 := await _grab_with(a1, c)
	var g2 := await _grab_with(a2, c)
	a1.clear_target_override()
	a2.clear_target_override()
	await _wait(0.3)
	if not (g1 and g2):
		_check("held_duo_released", false, "схватили P1 %s, P2 %s" % [str(g1), str(g2)])
		d1.queue_free()
		d2.queue_free()
		c.queue_free()
		return
	var c0 := c.global_position
	pair.transfer_doll(d1, pair.a, pair.b)
	var moved := pair.transfers > 0
	await _ticks(2)
	var rel: Dictionary = a1.last_release
	var reason := String(rel.get("reason", ""))
	var stays := c.global_position.distance_to(c0) < 1.0
	info["held_duo"] = {"moved": moved, "p1_release": reason, "p1_holds": a1.held == c, "p2_holds": a2.held == c, "crate_moved_m": snappedf(c.global_position.distance_to(c0), 0.01)}
	_check("held_duo_released", moved and reason == "portal" and a1.held == null and a2.held == c and stays,
		"P1 ушёл в портал %s, рука P1 отпустила (%s), ящик у P2 %s, ящик на месте %s" % [str(moved), reason, str(a2.held == c), str(stays)])
	d1.queue_free()
	d2.queue_free()
	c.queue_free()
	await _ticks(2)


# ------------------------------------------------------------------ props

func _props_section() -> void:
	print("--- props")
	for c in CASES:
		for kind in ["light", "medium", "iron", "barrel"]:
			await _prop_case(String(c[0]), c[1], c[2], kind)
	await _prop_resting()
	await _prop_held_in_pocket()
	_clear_world()


func _prop(kind: String, at: Vector3) -> RigidBody3D:
	if kind == "barrel":
		var b := (load(BARREL) as PackedScene).instantiate() as RigidBody3D
		b.position = at
		world.add_child(b)
		return b
	return _crate(kind, at)


func _prop_case(name: String, pa: Vector3, pb: Vector3, kind: String) -> void:
	var pair := _pair_world(pa, pb)
	var b := _prop(kind, Vector3(30, -30, 0))
	await _ticks(2)
	var g0 := b.gravity_scale
	var fall := name.ends_with("_fall")
	var n := pair.a.normal()
	var shift := pair.a.global_position + n * (2.2 if fall else START_M) - PortalPair.body_centre(b)
	shift.z = 0.0
	b.global_position += shift
	b.linear_velocity = -n * (1.0 if fall else SPEED)
	b.angular_velocity = Vector3.ZERO
	b.reset_physics_interpolation()
	if not fall:
		b.gravity_scale = 0.0   # подлёт без провиса (как у куклы); после переноса — снова g
	var moved := await _until(func() -> bool: return pair.transfers > 0, 2.0)
	b.gravity_scale = g0
	var id := "%s_%s" % [kind, name]
	if not moved:
		_check("prop_%s" % id, false, "перенос не случился: центр %s" % str(_r(PortalPair.body_centre(b))))
		b.queue_free()
		await _ticks(2)
		return
	var h: Dictionary = pair.history[0]
	var v_in: Vector3 = h["v_in"]
	var v1 := b.linear_velocity
	var rot := PortalPair.mapping(pair.a, pair.b).basis
	var ratio := v1.length() / maxf(v_in.length(), 1e-4)
	var dev_in := _deg(v_in, -n)
	var dev_out := _deg(v1, pair.b.normal())
	var dev_map := _deg(v1, rot * v_in)
	await _wait(0.6)
	var alive := is_instance_valid(b) and not b.is_queued_for_deletion()
	var stuck := _in_static(pair, [b]) if alive else 0
	var ahead := pair.b.height_of(PortalPair.body_centre(b)) if alive else 1.0
	info["prop_" + id] = {"ratio": snappedf(ratio, 0.001), "dev_out_deg": snappedf(dev_out, 0.1), "dev_in_deg": snappedf(dev_in, 0.1),
		"dev_map_deg": snappedf(dev_map, 0.1), "stuck": stuck, "ahead_m": snappedf(ahead, 0.01), "g_scale": g0, "alive": alive,
		"transfers": pair.transfers}
	_check("prop_%s" % id, absf(ratio - 1.0) <= SPEED_TOL and dev_out <= dev_in + DIR_TOL_DEG and dev_map <= DIR_TOL_DEG and stuck == 0 and ahead > 0.2,
		"|v| %.3f, к нормали выхода %.1f° (вход %.1f°), к повёрнутой %.1f°, в статике %d, впереди %.2f м" % [ratio, dev_out, dev_in, dev_map, stuck, ahead])
	if alive:
		b.queue_free()
	await _ticks(2)


## Ящик, положенный в карман пола A (выход — стена), — ровно один перенос; ящик в кармане потолка не мечется.
func _prop_resting() -> void:
	var pair := _pair_world(Vector3(0, 0, 0), Vector3(-6, 4, -90))
	var c := _crate("medium", Vector3(0, -0.6, 0))
	await _wait(3.0)
	_check("prop_resting_one_transfer", pair.transfers == 1, "ящик 35 кг из кармана: переносов за 3 с %d" % pair.transfers)
	# лицом друг к другу, вплотную по высоте: тело вылетает медленно — не мечется
	pair = _pair_world(Vector3(4, 4, 90), Vector3(-4, 4, -90))
	var l := _crate("light", Vector3(4.4, 4, 0))
	l.linear_velocity = Vector3(1.0, 0, 0)
	await _wait(3.0)
	info["prop_resting"] = {"floor_pocket": 1, "facing_slow_transfers": pair.transfers}
	_check("prop_pingpong", pair.transfers <= 2, "лёгкий ящик медленно в паре лицом друг к другу: переносов за 3 с %d" % pair.transfers)
	if is_instance_valid(c):
		c.queue_free()
	if is_instance_valid(l):
		l.queue_free()


## Держимый рукой ящик в кармане сам не уходит (его везёт держащий); отпустили — ушёл. Замороженное тело не переносится.
func _prop_held_in_pocket() -> void:
	# A — щель в стене слева (нормаль +x) на высоте 4 м; всё в невесомости: кукла стоит в 0.75 м перед щелью, рука с ящиком — в кармане
	var pair := _pair_world(Vector3(0, 4, -90), Vector3(-10, 5, 90))
	var d := await _ready_doll(0, Vector3(30, -30, 0), true)
	var c := await _hold_crate(d, "light")
	var arm := _arm(d)
	if c == null:
		_check("prop_held_stays", false, "не схватила ящик")
		d.queue_free()
		return
	var shift := Vector3(0.95, 4.0 - (arm.root_point().y - d.centre_of_mass().y), 0) - d.centre_of_mass()
	shift.z = 0.0
	for b in d.parts.values() + [c]:
		(b as RigidBody3D).global_position += shift
		(b as RigidBody3D).linear_velocity = Vector3.ZERO
		(b as RigidBody3D).reset_physics_interpolation()
	for k in 60:
		arm.set_target_override(Vector3(-1.2, 4.0, 0))
		await get_tree().physics_frame
	var in_pocket := pair.a.behind(PortalPair.body_centre(c))
	var doll_out := not pair.a.behind(d.centre_of_mass())
	var none := pair.transfers == 0
	arm.release("probe")
	arm.clear_target_override()
	var gone := await _until(func() -> bool: return pair.transfers > 0, 1.5)
	var who: Object = pair.history[0]["what"] if pair.transfers > 0 else null
	info["prop_held"] = {"crate_in_pocket": in_pocket, "doll_out": doll_out, "transfers_while_held": 0 if none else pair.transfers,
		"after_release": gone}
	_check("prop_held_stays", in_pocket and doll_out and none and gone and who == c,
		"в руке, центр в кармане %s, ЦМ куклы снаружи %s — не ушёл %s; отпустили — ушёл %s" % [str(in_pocket), str(doll_out), str(none), str(gone and who == c)])
	d.queue_free()
	if is_instance_valid(c):
		c.queue_free()
	# заморожен — не переносится
	var f := _crate("light", Vector3(-0.6, 4.0, 0))
	f.freeze = true
	var t0 := pair.transfers
	await _wait(0.5)
	_check("prop_frozen_stays", pair.transfers == t0, "замороженный ящик в кармане: переносов %d" % (pair.transfers - t0))
	f.queue_free()
	await _ticks(2)


# ------------------------------------------------------------------ rooms

func _rooms_section() -> void:
	print("--- rooms")
	await _load_pg(6, true)
	_check("rooms_count", pg.rooms.size() == 8, "комнат %d" % pg.rooms.size())
	if pg.rooms.size() < 8:
		return
	for coop in [true, false]:
		for i in [6, 7]:
			if coop:
				if pg.p2 == null:
					pg.join_p2()
			else:
				pg.leave_p2()
			await _ticks(3)
			pg.goto_room(i)
			var r := pg.rooms[i]
			pg.reset_room()
			await _wait(0.5)
			_script_players()
			var closed := _door_closed(r)
			var t0 := pg.total_time
			var solved: bool = await call("_solve_%d" % (i + 1), r, coop)
			var opened := r.door().open_frac() > 0.5
			var moved := await _exit_via_door(pg.p1, r, 10.0)
			var tag := "room%d_%s" % [i + 1, "coop" if coop else "solo"]
			info[tag + "_s"] = snappedf(pg.total_time - t0, 0.1)
			_check(tag, closed and solved and opened and moved, "дверь закрыта в начале %s, сценарий %s, дверь открыта %s, вышли %s" % [
				str(closed), str(solved), str(opened), str(moved)])
	await _unload()
