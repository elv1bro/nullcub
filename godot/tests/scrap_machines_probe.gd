## Проба механизмов и лута арены «Свалка» v3 (headless, scenes/playground_scrap.tscn как есть: арена, P1 / P2, Match без отсчёта).
## Запуск: godot --headless --path . --fixed-fps 60 res://tests/scrap_machines_probe.tscn
## Отчёт tests/scrap_machines_probe_report.json и stdout, exit 0/1. Стадии (checks[].id):
##   supports_behind          — коллизии опор, рам, перил, лестниц, башен и заднего плана (Back/*) не заходят в |z| < Z_CLEAR
##                              (ящик глубиной 1 м их не касается); в info — сколько форм проверено;
##   props_start_clear        — в позах builder-а (до первого шага физики) ни одно свободное тело (Props/Junk/Loot) не вставлено
##                              в другое тело или в статику (intersect_shape): иначе на первом пробуждении его выталкивает рывком;
##   machines_found / lamps_* — четыре механизма ScrapMachine, у каждого есть слоты ламп (телеграф);
##   cycle_<name>             — авто-цикл: за CYCLE_TIMEOUT_S каждый прошёл OFF → WARNING → ACTIVE → COOLDOWN → OFF;
##   warning_s_<name>         — WARNING длится ≈ 1 с (0.8…1.3);
##   blink_<name>             — в WARNING лампа мигает (min/max яркости различаются);
##   magnet_pulls_iron        — маятник остановлен, вокруг полюса убраны свободные тела и обломки; «железная 40 кг» (связка труб,
##                              meta material = "iron", класс PropHeft.MEDIUM — gravity_scale 2.5) на полу в ~3.5 м от полюса: за
##                              MAGNET_S ACTIVE приблизилась к полюсу ≥ MAGNET_IRON_MIN_M. info.magnet_barrel_touching — кто касается
##                              её перед включением (кроме пола);
##   magnet_ignores_wood      — деревянный ящик на том же расстоянии сдвинулся < MAGNET_WOOD_MAX_M;
##   magnet_releases          — через MAGNET_RELEASE_S после начала COOLDOWN бочка отпущена (сила 0) и лежит на полу;
##   magnet_iron_part         — ModularDoll с железным предплечьем и кулаком (metal_forearm, iron_ball_fist): магнит тянет её
##                              железные части (сила > 0), деревянные — нет; сумма сил ≤ doll_force_max;
##   steam_light_high / steam_light_over_heavy — пар: ящик 10 кг взлетает ≥ STEAM_LIGHT_MIN_M над полом и выше железной
##                              бочки 40 кг на ≥ STEAM_GAP_M (каждый — отдельный цикл с патрубка);
##   press_damage             — кукла под ползуном получила урон (Doll.take_damage, вид environment) и HP упало;
##   press_breaks_crate / press_loot — ящик под ползуном сломан, из него выпал лут;
##   chute_count / chute_in_bounds — желоб высыпал 3–6 кусков, все в границах арены;
##   loot_touch / loot_counter — лут, упавший на куклу, подобран касанием: RunInventory +1, счётчик на экране показывает;
##   loot_grab                — лут, схваченный рукой (ThrownCredit held — как ArmAssist.grab), подобран;
##   bodies_in_bounds         — все свободные тела (пропсы, куски, лут) весь прогон в границах: |x| ≤ HALF_W + 0.5,
##                              y ∈ [−9.7, CEIL_Y + 0.5].
extends Node3D

const SCENE := "res://scenes/playground_scrap.tscn"
const REPORT := "res://tests/scrap_machines_probe_report.json"
const CRATE := "res://scenes/props/scrap/prop_wooden_crate.tscn"
## 29.09: железная бочка Свалки стала взрывной (12 кг, scenes/props/explosive_barrel.gd) — роняемая магнитом, она взрывается.
## Магнит и пар проверяются на прежней «железной 40 кг»: связка труб 40 кг с meta material = "iron".
const IRON_40 := "res://scenes/props/scrap/prop_pipe_bundle.tscn"
const MODULAR := "res://scenes/body/modular_doll.tscn"
const HUMAN_BP := "res://data/body/blueprints/human.tres"
const HALF_W := 18.0
const CEIL_Y := 14.0
const Z_CLEAR := 0.6
const CYCLE_TIMEOUT_S := 20.0
const MAGNET_S := 2.5
const MAGNET_IRON_MIN_M := 0.5
const MAGNET_WOOD_MAX_M := 0.05
const MAGNET_RELEASE_S := 3.0       # после COOLDOWN бочка по инерции ещё поднимается, потом падает на пол (ЦМ < 0.7 м)
const STEAM_LIGHT_MIN_M := 2.0
const STEAM_GAP_M := 1.0
const BEHIND_PATTERNS := ["Support", "Frame", "Railing", "Ladder", "Banner", "Tower", "Gantry", "Bridge"]

var pg: Node3D
var arena: ScrapArena
var match_node: Node
var p1: Doll
var p2: Doll
var report := {"checks": [], "info": {}, "ok": true}
var out_of_bounds: Array = []
var start_overlaps: Array = []
var start_checked := false
var t := 0.0


func _ready() -> void:
	RunInventory.shared().reset()
	pg = (load(SCENE) as PackedScene).instantiate()
	var m := pg.get_node_or_null("Match")
	if m != null:
		m.set("countdown_s", 0.0)
	add_child(pg)
	arena = pg.get("arena") as ScrapArena
	match_node = m
	p1 = pg.get_node("P1") as Doll
	p2 = pg.get_node("P2") as Doll
	for d in [p1, p2]:
		d.external_input = true
	_run.call_deferred()


func _physics_process(delta: float) -> void:
	t += delta
	if arena == null:
		return
	if not start_checked:
		start_checked = true
		start_overlaps = _loose_overlaps()   # первый вызов — до первого шага физики: позы builder-а
	for b in arena.loose_bodies():
		var p := (b as Node3D).global_position
		if absf(p.x) > HALF_W + 0.5 or p.y < -9.7 or p.y > CEIL_Y + 0.5:
			var tag := String(arena.get_path_to(b))
			if out_of_bounds.size() < 20 and not out_of_bounds.any(func(e: Dictionary) -> bool: return e["body"] == tag):
				out_of_bounds.append({"body": tag, "pos": var_to_str(p.snapped(Vector3.ONE * 0.01)), "t": snappedf(t, 0.01)})


func _check(id: String, value: Variant, limit: Variant, op: String, note := "") -> bool:
	var ok := false
	match op:
		"eq": ok = value == limit
		"gte": ok = float(value) >= float(limit)
		"lte": ok = float(value) <= float(limit)
		"lt": ok = float(value) < float(limit)
		"gt": ok = float(value) > float(limit)
		"in": ok = float(value) >= float(limit[0]) and float(value) <= float(limit[1])
	report["checks"].append({"id": id, "ok": ok, "value": value, "limit": limit, "op": op, "note": note})
	if not ok:
		report["ok"] = false
	print("  %-26s %s  value=%s  limit=%s  %s" % [id, "ok  " if ok else "FAIL", str(value), str(limit), note])
	return ok


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _secs(s: float) -> void:
	await _ticks(int(ceil(s * 60.0)))


func _run() -> void:
	await _ticks(2)
	if arena == null:
		_check("scrap_arena", 0, 1, "eq", "playground_scrap: нет ScrapArena")
		_finish()
		return
	_supports()
	_check("props_start_clear", start_overlaps.size(), 0, "eq", "свободные тела вставлены друг в друга / в статику: %s" % [start_overlaps])
	await _cycles()
	for mm in arena.machines():
		(mm as ScrapMachine).auto_cycle = false
	await _settle_off()
	await _magnet()
	await _magnet_doll()
	await _steam()
	await _press()
	await _chute()
	await _loot()
	_check("bodies_in_bounds", out_of_bounds.size(), 0, "eq", "вне арены: %s" % [out_of_bounds])
	_finish()


# ------------------------------------------------------------------ стадии

## Свободные тела (Props/Junk/Loot), чьи коллизии в позах builder-а пересекаются с другим телом (свободным или статикой) —
## точный запрос формы (intersect_shape), не AABB. Тело, вставленное в другое, застревает в нём (решатель держит их вдавленными)
## и при ударе выталкивается рывком: до 29.09 доска Junk/Bit_2 (x −3.9) лежала на 0.55 м внутри большого ящика ShippingCrate
## (x −6.2…−3.8), ящик стоял на ней с креном 0.5°.
func _loose_overlaps() -> Array:
	var space := arena.get_world_3d().direct_space_state
	var out: Array = []
	for b in arena.loose_bodies():
		var rb := b as RigidBody3D
		for c in rb.get_children():
			var cs := c as CollisionShape3D
			if cs == null or cs.shape == null or cs.disabled:
				continue
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = cs.shape
			q.transform = cs.global_transform
			q.exclude = [rb.get_rid()]
			q.collide_with_areas = false
			for r in space.intersect_shape(q, 16):
				var other := r.get("collider") as Node
				if other == null or other.get_parent() is Doll:
					continue
				var tag := "%s ↔ %s" % [arena.get_path_to(rb), arena.get_path_to(other) if arena.is_ancestor_of(other) else other.get_path()]
				var rev := "%s ↔ %s" % [arena.get_path_to(other) if arena.is_ancestor_of(other) else other.get_path(), arena.get_path_to(rb)]
				if not out.has(tag) and not out.has(rev):
					out.append(tag)
	return out


func _supports() -> void:
	var n := 0
	var bad: Array = []
	for cs in arena.find_children("*", "CollisionShape3D", true, false):
		var shape_node := cs as CollisionShape3D
		if shape_node.shape == null or shape_node.disabled:
			continue
		var path := String(arena.get_path_to(shape_node))
		if path.begins_with("Machines/"):
			continue   # рабочие части механизмов на плоскости боя (станины без коллизий)
		var behind := path.begins_with("Back/")
		for pat in BEHIND_PATTERNS:
			if path.contains(pat):
				behind = true
		if not behind:
			continue
		n += 1
		var box := shape_node.global_transform * ScrapMachine._shape_aabb(shape_node.shape)
		if box.end.z > -Z_CLEAR and box.position.z < Z_CLEAR:
			bad.append("%s z %.2f…%.2f" % [path, box.position.z, box.end.z])
	report["info"]["supports_shapes_checked"] = n
	_check("supports_behind", bad.size(), 0, "eq", "формы заходят в |z| < %.1f: %s" % [Z_CLEAR, bad.slice(0, 8)])


func _cycles() -> void:
	var ms := arena.machines()
	_check("machines_found", ms.size(), 4, "eq", "Machines/*: %s" % [ms.map(func(x: Node) -> String: return String(x.name))])
	var blink: Dictionary = {}
	for mm in ms:
		_check("lamps_" + String(mm.name), 1 if (mm as ScrapMachine).has_lamps() else 0, 1, "eq", "слоты Lamp в мешах")
		blink[mm] = [INF, -INF]
	var t0 := t
	while t - t0 < CYCLE_TIMEOUT_S:
		await _ticks(1)
		var done := true
		for mm in ms:
			var sm := mm as ScrapMachine
			if sm.state == ScrapMachine.State.WARNING:
				var e := sm.lamp_energy()
				blink[mm] = [minf(blink[mm][0], e), maxf(blink[mm][1], e)]
			if sm.cycles < 1:
				done = false
		if done:
			break
	for mm in ms:
		var sm := mm as ScrapMachine
		var seq: Array = sm.history.map(func(h: Dictionary) -> String: return h["state"])
		var ok := _has_sequence(seq, ["WARNING", "ACTIVE", "COOLDOWN", "OFF"])
		_check("cycle_" + String(mm.name), 1 if ok else 0, 1, "eq", "история %s" % [sm.history])
		var w := _duration(sm.history, "WARNING")
		_check("warning_s_" + String(mm.name), snappedf(w, 0.01), [0.8, 1.3], "in", "WARNING, с")
		var b: Array = blink[mm]
		_check("blink_" + String(mm.name), snappedf(b[1] - b[0], 0.01), 1.0, "gte", "размах яркости лампы в WARNING")
	report["info"]["cycle_time_s"] = snappedf(t - t0, 0.01)


func _has_sequence(seq: Array, want: Array) -> bool:
	var i := 0
	for s in seq:
		if s == want[i]:
			i += 1
			if i == want.size():
				return true
		elif s == want[0]:
			i = 1
		else:
			i = 0
	return false


func _duration(hist: Array, state: String) -> float:
	for i in hist.size() - 1:
		if hist[i]["state"] == state:
			return float(hist[i + 1]["t"]) - float(hist[i]["t"])
	return -1.0


## Все механизмы довести до OFF (auto_cycle уже выключен).
func _settle_off() -> void:
	for i in 600:
		var all_off := true
		for mm in arena.machines():
			if (mm as ScrapMachine).state != ScrapMachine.State.OFF:
				all_off = false
		if all_off:
			return
		await _ticks(1)


## Убрать свободные тела вокруг точки (кроме keep) — чистая сцена для стадии. Обломки Breakable (группа "debris") — тоже:
## до 29.09 они пропускались («удаляют себя сами»), и связка труб в стадии магнита спавнилась в обломки деревянной бочки Barrel
## (x 9.35), разбитой взрывом железной MetalBarrel на авто-цикле (магнит уронил её, пресс смял — фитиль — взрыв за ~2 с до стадии).
## Обломки ещё летели, а через debris_freeze_s после взрыва замерзали (FREEZE_MODE_STATIC) — на связке и у её правого торца:
## статика сверху держала её намертво, сила магнита 160 Н уходила в контакт (magnet_pulls_iron 0.0 м, падала «через раз» —
## куда лягут обломки, решает randf закрутки). Таймеры breakable.gd держат обломок через weakref — ранний queue_free безопасен.
func _clear_around(c: Vector3, r: float, keep: Array) -> void:
	for b in arena.loose_bodies():
		if keep.has(b):
			continue
		var p := (b as Node3D).global_position
		if absf(p.x - c.x) < r and p.y < c.y + 8.0:
			(b as Node).queue_free()
	await _ticks(2)


## Пропс в Props арены — как у пропсов builder-а: лут при разрушении и вес по классу (PropHeft.equip, как ScrapArena._ready:
## связка труб 40 кг — MEDIUM, gravity_scale 2.5; ящик 10 кг — LIGHT, без изменений).
func _spawn_prop(path: String, pos: Vector3) -> RigidBody3D:
	var b := (load(path) as PackedScene).instantiate() as RigidBody3D
	arena.get_node("Props").add_child(b)
	b.global_position = pos
	if b is Breakable:
		arena.watch_breakable(b as Breakable)
	PropHeft.equip(b)
	return b


## Телепорт свободного тела в pos стоя (поворот сцены пропса — Basis.IDENTITY, origin у пропсов — низ) и без скоростей.
## Только global_position (как было до 29.09) сохранял поворот: железная бочка, которую магнит на авто-цикле поднял и уронил,
## лежит в случайной позе, и если она перевёрнута (поворот ≳ 135°), её цилиндр (origin — низ, высота 0.91) с origin на y 0.02
## занимает y −0.89…0.02 — насквозь через пол (плита 0.5 м, y −0.5…0). Выталкивать вниз ближе (0.52 м), чем вверх (0.89),
## и Jolt выталкивает бочку под пол — она падает мимо всего (проба падала ~1 из 5: magnet_pulls_iron −7.7 м, бочка на y −9.7).
## CCD тут ни при чём (он от туннелирования на скорости, не от старта внутри плиты), стыка модулей пола в x 6.5 нет (середина модуля).
func _teleport(b: RigidBody3D, pos: Vector3) -> void:
	b.global_transform = Transform3D(Basis.IDENTITY, pos)
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO


## Тела, чьи коллизии пересекают коллизии b (кроме пола Ground/*), с пометкой frozen — для диагностики стадии.
func _touching(b: RigidBody3D) -> Array:
	var space := arena.get_world_3d().direct_space_state
	var out: Array = []
	for c in b.get_children():
		var cs := c as CollisionShape3D
		if cs == null or cs.shape == null or cs.disabled:
			continue
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cs.shape
		q.transform = cs.global_transform
		q.exclude = [b.get_rid()]
		for r in space.intersect_shape(q, 16):
			var o := r.get("collider") as Node
			if o == null:
				continue
			var tag := String(arena.get_path_to(o)) if arena.is_ancestor_of(o) else String(o.name)
			if tag.begins_with("Ground/"):
				continue
			if o is RigidBody3D and (o as RigidBody3D).freeze:
				tag += " (frozen)"
			if not out.has(tag):
				out.append(tag)
	return out


func _place_doll(d: Doll, pos: Vector3) -> void:
	var low := INF
	for part in d.parts.values():
		low = minf(low, (part as Node3D).global_position.y)
	var com := d.centre_of_mass()
	d.global_position += Vector3(pos.x - com.x, pos.y + 0.12 - low, 0.0)
	for part in d.parts.values():
		(part as RigidBody3D).linear_velocity = Vector3.ZERO
		(part as RigidBody3D).angular_velocity = Vector3.ZERO


func _magnet() -> void:
	var mag := arena.magnet()
	mag.swing_deg = 0.0
	await _ticks(2)
	var pole := mag.pole_global()
	await _clear_around(Vector3(pole.x, 0, 0), 6.0, [])
	var barrel := _spawn_prop(IRON_40, Vector3(pole.x - 0.9, 0.02, 0.0))
	barrel.set_meta(ScrapMachine.META_MATERIAL, "iron")
	report["info"]["magnet_barrel_before"] = "pos %s rot %.0f°" % [barrel.global_position.snapped(Vector3.ONE * 0.01), rad_to_deg(barrel.global_rotation.z)]
	for d in [p1, p2]:
		_place_doll(d, Vector3(-0.3 if d == p1 else 1.8, 0.05, 0))   # куклы между паром и магнитом, вне их зон
	_teleport(barrel, Vector3(pole.x - 0.9, 0.02, 0.0))
	var crate := _spawn_prop(CRATE, Vector3(pole.x + 1.6, 0.02, 0.0))
	await _secs(1.0)
	var b0 := ScrapMachine.com_of(barrel)
	var c0 := crate.global_position
	var d0 := b0.distance_to(pole)
	report["info"]["magnet_barrel_gravity_scale"] = barrel.gravity_scale
	report["info"]["magnet_barrel_touching"] = _touching(barrel)   # не пол: если связка не едет — кто её держит
	report["info"]["magnet_pole"] = var_to_str(pole.snapped(Vector3.ONE * 0.01))
	report["info"]["magnet_barrel_r0"] = snappedf(d0, 0.01)
	report["info"]["magnet_crate_r0"] = snappedf(ScrapMachine.com_of(crate).distance_to(pole), 0.01)
	mag.force_state(ScrapMachine.State.ACTIVE)
	var max_f := 0.0
	var wood_f := 0.0
	for i in int(MAGNET_S * 60.0):
		await _ticks(1)
		max_f = maxf(max_f, (mag.last_forces.get(barrel, Vector3.ZERO) as Vector3).length())
		wood_f = maxf(wood_f, (mag.last_forces.get(crate, Vector3.ZERO) as Vector3).length())
	var d1 := ScrapMachine.com_of(barrel).distance_to(pole)
	report["info"]["magnet_barrel_rise_m"] = snappedf(ScrapMachine.com_of(barrel).y - b0.y, 0.01)
	report["info"]["magnet_barrel_force_max_n"] = snappedf(max_f, 0.1)
	_check("magnet_pulls_iron", snappedf(d0 - d1, 0.01), MAGNET_IRON_MIN_M, "gte", "железная бочка 40 кг ближе к полюсу за %.1f с (м)" % MAGNET_S)
	_check("magnet_ignores_wood", snappedf(crate.global_position.distance_to(c0), 0.001), MAGNET_WOOD_MAX_M, "lt",
		"деревянный ящик сдвинулся (м), сила на него %.1f Н" % wood_f)
	# Ящик своё отработал: связка 2 м длиной, отпущенная у полюса, правым концом падала на него (x 8.5…9.5) и оставалась
	# лежать наискось, ЦМ 0.78 м — magnet_releases проверяет «отпустил и упала на пол», а не раскладку пропсов.
	crate.queue_free()
	mag.force_state(ScrapMachine.State.COOLDOWN)
	var y_hold := ScrapMachine.com_of(barrel).y
	await _secs(MAGNET_RELEASE_S)
	var f_after := (mag.last_forces.get(barrel, Vector3.ZERO) as Vector3).length()
	var y_after := ScrapMachine.com_of(barrel).y
	_check("magnet_releases", 1 if f_after == 0.0 and y_after < 0.7 else 0, 1, "eq",
		"через %.1f с COOLDOWN сила %.1f Н, ЦМ бочки на %.2f м (держалась на %.2f)" % [MAGNET_RELEASE_S, f_after, y_after, y_hold])
	await _settle_off()
	barrel.queue_free()


## ModularDoll с железной рукой под магнитом: сила на железные части, не на деревянные.
func _magnet_doll() -> void:
	var mag := arena.magnet()
	var bp := (load(HUMAN_BP) as BodyBlueprint).duplicate(true) as BodyBlueprint
	var nodes: Array[Dictionary] = []
	for n in bp.nodes:
		var e: Dictionary = (n as Dictionary).duplicate()
		if String(e.get("name", "")) == "LowerArm_R":
			e["part"] = "metal_forearm"
		elif String(e.get("name", "")) == "Hand_R":
			e["part"] = "iron_ball_fist"
		nodes.append(e)
	bp.nodes = nodes
	bp.id = "probe_iron_arm"
	var inst := (load(MODULAR) as PackedScene).instantiate()
	var md := inst as Doll
	if md == null or not md.has_method("energy_used"):
		# 29.09: ModularDoll не компилировался (конфликт имён с Doll) — сцена создалась без скрипта, стадия падала с ошибкой
		# скрипта и проверка просто пропадала, а проба оставалась зелёной. Теперь это явный провал.
		_check("magnet_iron_part", 0, 1, "eq", "ModularDoll не создался из %s (ошибка скрипта modular_doll.gd?)" % MODULAR)
		if inst != null:
			inst.free()
		return
	md.set("blueprint", bp)
	md.external_input = true
	md.name = "IronArm"
	pg.add_child(md)
	var pole := mag.pole_global()
	_place_doll(md, Vector3(pole.x - 0.6, 0.05, 0.0))
	await _secs(0.6)
	var errs: Variant = md.get("build_errors")
	report["info"]["iron_doll_build_errors"] = Array(errs) if errs != null else []
	var iron_parts: Array = []
	for pn in md.parts:
		if ScrapMachine.iron_mass(md.parts[pn]) > 0.0:
			iron_parts.append(String(pn))
	report["info"]["iron_doll_iron_parts"] = iron_parts
	var hand := md.parts.get("Hand_R") as RigidBody3D
	var hy0 := hand.global_position.y if hand != null else 0.0
	mag.force_state(ScrapMachine.State.ACTIVE)
	var iron_f := 0.0
	var wood_f := 0.0
	var doll_sum := 0.0
	for i in 60:
		await _ticks(1)
		var s := 0.0
		for pn in md.parts:
			var f := (mag.last_forces.get(md.parts[pn], Vector3.ZERO) as Vector3).length()
			s += f
			if iron_parts.has(String(pn)):
				iron_f = maxf(iron_f, f)
			else:
				wood_f = maxf(wood_f, f)
		doll_sum = maxf(doll_sum, s)
	report["info"]["iron_doll_hand_rise_m"] = snappedf((hand.global_position.y - hy0) if hand != null else 0.0, 0.01)
	var ok := not iron_parts.is_empty() and iron_f > 0.0 and wood_f == 0.0 and doll_sum <= mag.doll_force_max + 0.5
	_check("magnet_iron_part", 1 if ok else 0, 1, "eq", "железные части %s: сила до %.1f Н, деревянные %.1f Н, сумма %.1f ≤ %.0f Н" %
		[iron_parts, iron_f, wood_f, doll_sum, mag.doll_force_max])
	mag.force_state(ScrapMachine.State.OFF)
	md.queue_free()
	await _ticks(2)


func _steam() -> void:
	var vent := arena.steam_vent()
	var vx := vent.global_position.x
	await _clear_around(Vector3(vx, 0, 0), 3.0, [])
	var results := {}
	for spec in [["crate_10", CRATE], ["metal_barrel_40", IRON_40]]:
		var b := _spawn_prop(spec[1], Vector3(vx, 0.42, 0.0))
		if spec[1] == IRON_40:
			b.set_meta(ScrapMachine.META_MATERIAL, "iron")
		await _secs(0.8)
		var y0 := b.global_position.y
		vent.force_state(ScrapMachine.State.ACTIVE)
		var top := y0
		for i in int((vent.active_s + vent.cooldown_s + 2.5) * 60.0):
			await _ticks(1)
			if not is_instance_valid(b):
				break
			top = maxf(top, b.global_position.y)
		results[spec[0]] = top - y0
		report["info"]["steam_rise_" + String(spec[0])] = snappedf(top - y0, 0.01)
		report["info"]["steam_top_" + String(spec[0])] = snappedf(top, 0.01)
		await _settle_off()
		if is_instance_valid(b):
			b.queue_free()
		await _ticks(2)
	_check("steam_light_high", snappedf(results["crate_10"], 0.01), STEAM_LIGHT_MIN_M, "gte", "ящик 10 кг поднят паром (м)")
	_check("steam_light_over_heavy", snappedf(results["crate_10"] - results["metal_barrel_40"], 0.01), STEAM_GAP_M, "gte",
		"ящик 10 кг выше железной бочки 40 кг (подъём бочки %.2f м)" % results["metal_barrel_40"])


func _press() -> void:
	var press := arena.press()
	var px := press.global_position.x
	await _clear_around(Vector3(px, 0, 0), 2.5, [])
	_place_doll(p1, Vector3(px - 0.55, 0.13, 0.0))
	var crate := _spawn_prop(CRATE, Vector3(px + 0.45, 0.14, 0.0))
	var drops := [0]
	var cb := func(_it: Node3D, from: Node3D) -> void:
		if from == crate:
			drops[0] += 1
	arena.loot_dropped.connect(cb)
	await _secs(0.8)
	var hp0 := p1.hp
	var hits0 := press.hits.size()
	report["info"]["press_combat_on"] = press.combat_on()
	press.trigger()
	await _secs(press.warning_s + press.active_s + 0.3)
	var got: Array = press.hits.slice(hits0).filter(func(h: Dictionary) -> bool: return h["victim"] == p1)
	_check("press_damage", snappedf(hp0 - p1.hp, 0.1), 1.0, "gte", "HP %.1f → %.1f, удары пресса по P1: %d" % [hp0, p1.hp, got.size()])
	var broken := not is_instance_valid(crate) or (crate as Breakable).state == Breakable.State.DESTROYED
	_check("press_breaks_crate", 1 if broken else 0, 1, "eq", "сломаны прессом: %s" % [press.broken])
	await _ticks(3)
	_check("press_loot", drops[0], 1, "gte", "лут из ящика под прессом (1–2)")
	await _settle_off()
	arena.loot_dropped.disconnect(cb)


func _chute() -> void:
	var chute := arena.chute()
	var n0 := chute.spawned_total
	chute.trigger()
	await _secs(chute.warning_s + chute.active_s + 0.1)
	var batch: Array = chute.last_batch.duplicate()
	_check("chute_count", chute.spawned_total - n0, [3, 6], "in", "кусков за цикл")
	await _secs(4.0)
	var bad: Array = []
	for b in batch:
		if not is_instance_valid(b):
			continue
		var p := (b as Node3D).global_position
		if absf(p.x) > HALF_W + 0.5 or p.y < -9.7 or p.y > CEIL_Y + 0.5:
			bad.append("%s %s" % [b.name, p])
	report["info"]["chute_landing"] = batch.filter(func(b: Variant) -> bool: return is_instance_valid(b)).map(
		func(b: Node3D) -> String: return "%s (%.1f, %.1f)" % [b.name, b.global_position.x, b.global_position.y])
	_check("chute_in_bounds", bad.size(), 0, "eq", "вне арены: %s" % [bad])
	await _settle_off()


func _loot() -> void:
	var inv := RunInventory.shared()
	_place_doll(p2, Vector3(5.0, 0.05, 0.0))
	await _secs(1.0)
	var n0 := inv.count("nails")
	var head := p2.parts["Head"] as RigidBody3D
	var it := arena.spawn_loot("nails", head.global_position + Vector3(0.0, 0.55, 0.0))
	var picked := [false]
	if it != null:
		it.picked.connect(func(_by: Node, _id: String) -> void: picked[0] = true)
	for i in 240:
		await _ticks(1)
		if picked[0]:
			break
	_check("loot_touch", inv.count("nails") - n0, 1, "eq", "гвозди упали на голову P2: подобраны=%s" % picked[0])
	await _ticks(2)
	var counter := arena.get_node_or_null("LootCounter") as RunInventoryCounter
	var txt := counter.text() if counter != null else ""
	report["info"]["counter_text"] = txt
	_check("loot_counter", 1 if txt.contains("гвозди") else 0, 1, "eq", "счётчик: «%s»" % txt)
	var p0 := inv.count("plate")
	var it2 := arena.spawn_loot("plate", Vector3(8.5, 0.3, 0.0))
	await _secs(0.7)
	if it2 != null and is_instance_valid(it2):
		ThrownCredit.attach(it2, p2)
	await _ticks(3)
	_check("loot_grab", inv.count("plate") - p0, 1, "eq", "пластина схвачена рукой (ThrownCredit held) → подобрана")
	report["info"]["inventory"] = inv.snapshot()


## Проверки, которые обязаны быть в отчёте: стадия, упавшая с ошибкой скрипта, не пишет свою проверку — без этой сверки проба
## оставалась бы зелёной (так было 29.09 с magnet_iron_part). Префиксы — проверки по каждому механизму.
const REQUIRED_CHECKS := ["machines_found", "supports_behind", "props_start_clear", "magnet_pulls_iron", "magnet_ignores_wood",
	"magnet_releases", "magnet_iron_part", "steam_light_high", "steam_light_over_heavy", "press_damage", "press_breaks_crate",
	"press_loot", "chute_count", "chute_in_bounds", "loot_touch", "loot_grab", "loot_counter", "bodies_in_bounds"]
const REQUIRED_PREFIXES := ["cycle_", "lamps_", "blink_", "warning_s_"]


func _missing_checks() -> Array:
	var ids := {}
	for c in report["checks"]:
		ids[String(c["id"])] = true
	var missing: Array = []
	for id in REQUIRED_CHECKS:
		if not ids.has(id):
			missing.append(id)
	for p in REQUIRED_PREFIXES:
		var found := false
		for id in ids:
			if String(id).begins_with(p):
				found = true
				break
		if not found:
			missing.append(p + "*")
	return missing


func _finish() -> void:
	if arena != null:
		var missing := _missing_checks()
		_check("all_checks_present", missing.size(), 0, "eq", "стадии без своих проверок (упали с ошибкой?): %s" % [missing])
	report["info"]["godot"] = Engine.get_version_info()["string"]
	report["info"]["sim_s"] = snappedf(t, 0.01)
	var js := JSON.stringify(report, "  ")
	var f := FileAccess.open(REPORT, FileAccess.WRITE)
	if f:
		f.store_string(js)
		f.close()
	print("info: ", JSON.stringify(report["info"]))
	print("=== SCRAP MACHINES PROBE: %s (%d checks) ===" % ["OK" if report["ok"] else "FAIL", report["checks"].size()])
	get_tree().quit(0 if report["ok"] else 1)
