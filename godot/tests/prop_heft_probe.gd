## Проба веса пропсов, жёсткого хвата, броска и взрывов (29.09; scenes/props/prop_heft.gd, scripts/body/arm_assist.gd,
## scenes/props/explosive_barrel.gd, scripts/fx/explosion.gd). Headless, без Match (урон взрыва идёт — Match нет). Запуск:
##   godot --headless --path . --fixed-fps 60 res://tests/prop_heft_probe.tscn                  — все кейсы, код выхода 0 = ок
##   godot --headless --path . --fixed-fps 60 res://tests/prop_heft_probe.tscn -- "case=explode" — один кейс
## Кейсы:
##   push      кукла 2.5 с изо всех сил толкает: ящик 10 кг уезжает, корзина 35 кг — меньше, ящик 80 кг — стоит (< HEAVY_DX_MAX);
##   too_heavy захват у ящика 80 кг — "too_heavy", в руке пусто;
##   weld      ящик 10 кг в руке: приварен за ≤ WELD_S, при махе рукой 1 с точка хвата не отходит (< WELD_GAP_MAX), поворот
##             ограничен (< WELD_TURN_MAX_DEG); контраст — старая пружина (weld_light = false) тянется в разы сильнее;
##   throw     бросок к цели справа-сверху: скорость ≈ √(2E/m), направление — к цели (< THROW_DIR_MAX_DEG);
##   breaks    брошенный в стену ящик разлетается (< 2 с);
##   explode   поджиг бочки 0.1 с: кукла рядом — урон и отлёт, ящик рядом — в щепки, вторая бочка — цепью, ящик 80 кг — сдвинут;
##   fuse      урон бочке до DAMAGED — горит и взрывается через ≈ FUSE_S.
extends Node3D

const DOLL_SCENE := "res://scenes/doll/doll.tscn"
const CRATE := "res://scenes/props/scrap/prop_wooden_crate.tscn"
const BASKET_FULL := "res://scenes/props/scrap/prop_scrap_basket_full.tscn"
const SHIP_CRATE := "res://scenes/props/scrap/prop_large_shipping_crate.tscn"
const BARREL := "res://scenes/props/scrap/prop_metal_barrel.tscn"

const HEAVY_DX_MAX := 0.05
const WELD_S := 0.4
const WELD_GAP_MAX := 0.03
const WELD_TURN_MAX_DEG := 25.0   # поворот ящика относительно кисти: остаток — запястье (см. ArmAssist.WELD_ANG_OMEGA)
const THROW_DIR_MAX_DEG := 12.0

var case_filter := ""
var checks: Array = []
var info: Dictionary = {}
var world: Node3D


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "case":
				case_filter = p[1]
	_run.call_deferred()


func _run() -> void:
	for c in ["push", "too_heavy", "weld", "throw", "breaks", "explode", "fuse"]:
		if case_filter != "" and case_filter != c:
			continue
		print("--- case ", c)
		await call("_case_" + c)
		_clear_world()
		await _ticks(2)
	var ok := true
	print("=== PROP HEFT PROBE ===")
	for ch in checks:
		print("  %-26s %s  value=%s  limit=%s  %s" % [ch["id"], "ok " if ch["ok"] else "FAIL", str(ch["value"]), str(ch["limit"]), ch.get("note", "")])
		ok = ok and bool(ch["ok"])
	print("info: ", JSON.stringify(info))
	print("RESULT: ", "OK" if ok else "FAIL", " (", checks.size(), " checks)")
	get_tree().quit(0 if ok else 1)


func _check(id: String, ok: bool, value: Variant, limit: Variant, note: String = "") -> void:
	checks.append({"id": id, "ok": ok, "value": value, "limit": limit, "note": note})


func _ticks(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _new_world() -> Node3D:
	_clear_world()
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	_static_box(Vector3(0, -0.5, 0), Vector3(60, 1, 4))
	return world


func _static_box(pos: Vector3, size: Vector3) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	sb.position = pos
	world.add_child(sb)


func _clear_world() -> void:
	if world != null and is_instance_valid(world):
		remove_child(world)
		world.free()
	world = null


func _spawn_doll(x: float, name_: String, with_arm: bool) -> Doll:
	var d: Doll = (load(DOLL_SCENE) as PackedScene).instantiate()
	d.name = name_
	d.external_input = true
	d.input_prefix = "p1"
	d.position = Vector3(x, 0.05, 0)
	world.add_child(d)
	d.add_to_group("dolls")
	if with_arm:
		ArmAssist.attach_to(d)
	return d


func _prop(path: String, pos: Vector3) -> RigidBody3D:
	var b: RigidBody3D = (load(path) as PackedScene).instantiate()
	world.add_child(b)
	b.global_position = pos
	PropHeft.equip(b)
	return b


func _grab(arm: ArmAssist, item: RigidBody3D) -> bool:
	for i in 90:
		arm.set_target_override(arm.closest_point(item, arm.root_point()) + Vector3(0, 0.08, 0))
		await _ticks(1)
		if arm.candidate == item or (arm.blocked_candidate == item):
			break
	arm.press_grab()
	await _ticks(1)
	return arm.held == item


static func _angle(b: Node3D) -> float:
	var x := b.global_transform.basis.x
	return atan2(x.y, x.x)


# ------------------------------------------------------------------ кейсы

func _push_dx(path: String) -> float:
	_new_world()
	var d := _spawn_doll(0.0, "P1", false)
	var it := _prop(path, Vector3(1.9, 0.02, 0))
	await _ticks(60)
	var x0 := it.global_position.x
	for i in 150:
		d.input_vec = Vector2(1.0, 0.0)
		await _ticks(1)
	d.input_vec = Vector2.ZERO
	await _ticks(30)
	return snappedf(it.global_position.x - x0, 0.001)


func _case_push() -> void:
	var light := await _push_dx(CRATE)
	var medium := await _push_dx(BASKET_FULL)
	var heavy := await _push_dx(SHIP_CRATE)
	info["push_dx"] = {"crate_10": light, "basket_35": medium, "ship_80": heavy}
	_check("push_heavy_stays", absf(heavy) < HEAVY_DX_MAX, heavy, "< %.2f m" % HEAVY_DX_MAX, "ящик 80 кг, тяга 2.5 с")
	_check("push_light_moves", light > 0.5, light, "> 0.5 m", "ящик 10 кг")
	_check("push_medium_harder", medium < light, medium, "< %.2f (лёгкий)" % light, "корзина 35 кг")


func _case_too_heavy() -> void:
	_new_world()
	var d := _spawn_doll(0.0, "P1", true)
	var arm := d.get_node("ArmAssist") as ArmAssist
	var it := _prop(SHIP_CRATE, Vector3(-1.9, 0.02, 0))
	await _ticks(60)
	var anchored := it.freeze
	await _grab(arm, it)
	_check("too_heavy_action", arm.last_grab_action == "too_heavy" and arm.held == null, [arm.last_grab_action, arm.held == null],
		"[too_heavy, true]", "якорь: %s" % anchored)


## Мах рукой по дуге 1 с с ящиком 10 кг. weld = false — контраст: пружина и свободный шарнир (как до 29.09).
func _weld_swing(weld: bool) -> Dictionary:
	_new_world()
	var d := _spawn_doll(0.0, "P1", true)
	var arm := d.get_node("ArmAssist") as ArmAssist
	arm.weld_light = weld
	var it := _prop(CRATE, Vector3(-1.35, 0.02, 0))
	await _ticks(50)
	var got: bool = await _grab(arm, it)
	var t := 0
	while t < 30 and not arm.is_welded():
		arm.set_target_override(arm.root_point() + Vector3(-0.2, arm.reach * 0.9, 0))
		await _ticks(1)
		t += 1
	var welded := arm.is_welded()
	var rel0 := wrapf(_angle(it) - _angle(arm.part), -PI, PI)
	var gap_max := 0.0
	var turn_max := 0.0
	for i in 60:
		var a := PI * 0.5 + sin(float(i) / 60.0 * TAU) * 1.0
		arm.set_target_override(arm.root_point() + Vector3(cos(a), sin(a), 0) * arm.reach * 0.9)
		await _ticks(1)
		gap_max = maxf(gap_max, arm.grip_global().distance_to(it.to_global(arm.anchor_local)))
		turn_max = maxf(turn_max, absf(rad_to_deg(wrapf(_angle(it) - _angle(arm.part) - rel0, -PI, PI))))
	return {"grabbed": got, "welded": welded, "weld_ticks": t, "gap_max": snappedf(gap_max, 0.001), "turn_max_deg": snappedf(turn_max, 0.1),
		"still_held": arm.held == it}


func _case_weld() -> void:
	var w := await _weld_swing(true)
	var old := await _weld_swing(false)
	info["weld"] = {"weld": w, "spring_old": old}
	_check("weld_made", w["grabbed"] and w["welded"] and float(w["weld_ticks"]) / 60.0 <= WELD_S, w["weld_ticks"], "≤ %.1f s" % WELD_S)
	_check("weld_no_stretch", float(w["gap_max"]) < WELD_GAP_MAX and w["still_held"], w["gap_max"], "< %.2f m" % WELD_GAP_MAX,
		"пружина: %.2f м" % float(old["gap_max"]))
	_check("weld_turn_bounded", float(w["turn_max_deg"]) < WELD_TURN_MAX_DEG, w["turn_max_deg"], "< %.0f°" % WELD_TURN_MAX_DEG,
		"пружина: %.0f°" % float(old["turn_max_deg"]))
	_check("weld_beats_spring", float(w["gap_max"]) * 5.0 < float(old["gap_max"]), [w["gap_max"], old["gap_max"]], "растяжение ×5 меньше")


func _case_throw() -> void:
	_new_world()
	var d := _spawn_doll(0.0, "P1", true)
	var arm := d.get_node("ArmAssist") as ArmAssist
	var it := _prop(CRATE, Vector3(-1.35, 0.02, 0))
	await _ticks(50)
	await _grab(arm, it)
	for i in 40:
		arm.set_target_override(arm.root_point() + Vector3(-0.1, arm.reach, 0))
		await _ticks(1)
	var aim := Vector3(-1.0, 0.6, 0).normalized()
	arm.set_target_override(arm.root_point() + aim * 2.0)
	await _ticks(2)
	arm.press_grab()
	await _ticks(1)
	var v := it.linear_velocity
	var expect := sqrt(2.0 * ArmAssist.THROW_ENERGY / it.mass)
	var ang := rad_to_deg(Vector2(v.x, v.y).angle_to(Vector2(aim.x, aim.y)))
	info["throw"] = {"v": [snappedf(v.x, 0.01), snappedf(v.y, 0.01)], "speed": snappedf(v.length(), 0.01), "expect": snappedf(expect, 0.01),
		"angle_deg": snappedf(ang, 0.1), "last_throw": arm.last_throw.get("speed", -1.0)}
	_check("throw_speed", absf(v.length() - expect) < 1.5, snappedf(v.length(), 0.01), "≈ %.1f ± 1.5 m/s" % expect)
	_check("throw_aimed", absf(ang) < THROW_DIR_MAX_DEG, snappedf(ang, 0.1), "< %.0f°" % THROW_DIR_MAX_DEG)


func _case_breaks() -> void:
	_new_world()
	_static_box(Vector3(-3.6, 2.0, 0), Vector3(0.4, 4.0, 4.0))
	var d := _spawn_doll(0.0, "P1", true)
	var arm := d.get_node("ArmAssist") as ArmAssist
	var it := _prop(CRATE, Vector3(-1.35, 0.02, 0))
	await _ticks(50)
	await _grab(arm, it)
	for i in 40:
		arm.set_target_override(arm.root_point() + Vector3(-0.1, arm.reach, 0))
		await _ticks(1)
	arm.set_target_override(arm.root_point() + Vector3(-2.0, 0.1, 0))
	await _ticks(2)
	var hits: Array = []
	(it as Breakable).hit.connect(func(sp: float, dm: float, by: Node) -> void:
		hits.append([snappedf(sp, 0.01), snappedf(dm, 0.1), String(by.name) if by != null else "?"]))
	arm.press_grab()
	var t := 0
	while t < 120 and is_instance_valid(it) and (it as Breakable).state != Breakable.State.DESTROYED:
		await _ticks(1)
		t += 1
	var broke := not is_instance_valid(it) or (it as Breakable).state == Breakable.State.DESTROYED
	info["breaks"] = {"hits": hits, "throw_v": arm.last_throw.get("speed", -1.0)}
	_check("thrown_crate_breaks", broke, t, "< 120 ticks", "бросок в стену 2.2 м")


func _case_explode() -> void:
	_new_world()
	var victim := _spawn_doll(1.4, "P2", false)
	var crate := _prop(CRATE, Vector3(-1.4, 0.02, 0))
	var b1 := _prop(BARREL, Vector3(0, 0.02, 0)) as ExplosiveBarrel
	var b2 := _prop(BARREL, Vector3(-2.6, 0.02, 0)) as ExplosiveBarrel
	var ship := _prop(SHIP_CRATE, Vector3(3.8, 0.02, 0))
	await _ticks(60)
	var hp0 := victim.hp
	var ship_x0 := ship.global_position.x
	var ship_anchored := ship.freeze
	var boom: Array = []
	b1.ignite(0.1, null)
	b1.tree_exiting.connect(func() -> void: boom.append(["b1", Engine.get_physics_frames()]))
	b2.tree_exiting.connect(func() -> void: boom.append(["b2", Engine.get_physics_frames()]))
	var vmax := 0.0
	for i in 90:
		await _ticks(1)
		var v := Vector3.ZERO
		var m := 0.0
		for p in victim.parts.values():
			v += (p as RigidBody3D).linear_velocity * (p as RigidBody3D).mass
			m += (p as RigidBody3D).mass
		vmax = maxf(vmax, (v / m).length())
	var dmg := hp0 - victim.hp
	var crate_gone := not is_instance_valid(crate) or (crate as Breakable).state == Breakable.State.DESTROYED
	var ship_dx := ship.global_position.x - ship_x0
	info["explode"] = {"damage": snappedf(dmg, 0.1), "vmax": snappedf(vmax, 0.01), "boom": boom, "ship_dx": snappedf(ship_dx, 0.01),
		"ship_anchored_before": ship_anchored}
	_check("explode_hurts", dmg > 10.0, snappedf(dmg, 0.1), "> 10 HP", "кукла в 1.4 м")
	_check("explode_knockback", vmax > 3.0, snappedf(vmax, 0.01), "> 3 m/s ЦМ")
	_check("explode_breaks_crate", crate_gone, crate_gone, true, "ящик в 1.4 м")
	_check("explode_chain", boom.size() == 2, boom, "b1 и b2", "вторая бочка в 2.6 м")
	_check("explode_moves_heavy", ship_anchored and absf(ship_dx) > 0.1, snappedf(ship_dx, 0.01), "> 0.1 m", "ящик 80 кг в 3.8 м, якорь до взрыва: %s" % ship_anchored)


func _case_fuse() -> void:
	_new_world()
	var b := _prop(BARREL, Vector3(0, 0.02, 0)) as ExplosiveBarrel
	await _ticks(30)
	b.take_damage(12.0)
	var lit := b.lit
	var t := 0
	while t < 240 and is_instance_valid(b):
		await _ticks(1)
		t += 1
	var s := float(t) / 60.0
	_check("fuse_lit_on_damage", lit, lit, true)
	_check("fuse_explodes", absf(s - ExplosiveBarrel.FUSE_S) < 0.2, snappedf(s, 0.01), "≈ %.1f s" % ExplosiveBarrel.FUSE_S)
