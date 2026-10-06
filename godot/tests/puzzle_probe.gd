## Проба демо «Головоломки вдвоём» (docs/plan-demo/PUZZLE.md; scripts/puzzle/, scenes/puzzle/, scenes/playground_puzzle.tscn).
## Секции (only=parts|rooms|controls|bounds, несколько — через «+», пусто — все):
##   parts    — каждый механизм в своём мире (пол 40 м): плита — порог массы (кукла 40 кг / ящик 10 / 35 / 60, грузовые весы без кукол,
##              выключение с задержкой); рычаг — угол → состояние, гистерезис, рука хватает рукоять и перекидывает; дверь — открывается
##              от тока и закрывается, не опускается на ящик в проёме; лифт — едет вверх, везёт 60 и 90 кг, без тока — вниз; зона
##              гравитации — «низ» поворачивается вправо, ящик падает вправо; логика И / ИЛИ / ТАЙМЕР (держит hold_s); кабель светится;
##              ящик «вдвоём» 60 кг — одна рука не поднимает (срыв или < 0.3 м), две — поднимают (> 1 м); телом снизу — для сведения;
##   controls — клавиатурная рука P2 (PuzzleKeyArm): тянется к ящику по стрелке и хватает, держит перед собой, бросает со стрелкой,
##              кладёт без стрелки; кукла P2 без узла (другие режимы) — действие p2_grab_kb ничего не делает, подписи «RB» прежние;
##              геймпад — узел уступает; на площадке гонки у P2 нет PuzzleKeyArm;
##   rooms    — каждая комната решается сценарием на настоящей площадке: ящик/кукла/рычаг/лифт/бочка → дверь открыта → кукла в тамбуре →
##              следующая комната; вдвоём и соло, где они разные; после шестой — итоги;
##   bounds   — из каждой комнаты кукла не вылетает: 8 направлений, полная тяга с ускорением по 3 с — ЦМ внутри комнаты, в тамбур
##              при закрытой двери не попасть.
## Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/puzzle_probe.tscn -- "only=parts,out=<json>"
## → JSON между === PUZZLE PROBE === и === OK / FAIL ===, exit 0/1. errors_script — SCRIPT ERROR за прогон (Logger).
extends Node

const PLAYGROUND := "res://scenes/playground_puzzle.tscn"
const RACE := "res://scenes/playground_race.tscn"
const PZ := "res://scenes/puzzle/%s.tscn"
const BARREL := "res://scenes/props/scrap/prop_metal_barrel.tscn"
const TICK := 1.0 / 60.0

## Счётчик SCRIPT ERROR за прогон (как squad_probe, race_probe).
class ScriptErrors extends Logger:
	var count := 0
	var first := ""
	var _mx := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mx.lock()
		count += 1
		if first == "":
			first = "%s %s (%s:%d %s)" % [code, rationale, file, line, function]
		_mx.unlock()


var ok := true
var checks: Array = []
var info := {}
var errs := ScriptErrors.new()
var world: Node3D
var pg: PuzzlePlayground
var trace := false


func _check(id: String, cond: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": cond, "detail": str(detail)})
	if not cond:
		ok = false
	print("  %-36s %s  %s" % [id, "ok  " if cond else "FAIL", str(detail)])


func _args() -> Dictionary:
	var out := {"only": "", "out": "", "room": "", "trace": "0"}
	for a in OS.get_cmdline_user_args():
		for part in String(a).split(","):
			var kv := part.split("=")
			if kv.size() == 2 and out.has(kv[0]):
				out[kv[0]] = kv[1]
	return out


func _want(a: Dictionary, section: String) -> bool:
	return String(a["only"]) == "" or section in String(a["only"]).split("+")


func _ready() -> void:
	OS.add_logger(errs)
	print("=== PUZZLE PROBE ===")
	var a := _args()
	trace = String(a["trace"]) == "1"
	if _want(a, "parts"):
		await _parts()
	if _want(a, "controls"):
		await _controls()
	if _want(a, "rooms"):
		await _rooms(String(a["room"]))
	if _want(a, "bounds"):
		await _bounds()
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


# ------------------------------------------------------------------ помощники

func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait(s: float) -> void:
	await _ticks(int(ceil(s / TICK)))


func _until(cond: Callable, max_s: float) -> bool:
	for i in int(max_s / TICK):
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


## Мир для механизмов: пол 40 м (верх y = 0), стена справа x = 12.
func _new_world() -> Node3D:
	_clear_world()
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	var st := StaticBody3D.new()
	st.name = "Floor"
	world.add_child(st)
	PuzzlePart.box_shape(st, "Floor", Vector3(40, 1, 4), Vector3(0, -0.5, 0))
	return world


func _clear_world() -> void:
	if world != null and is_instance_valid(world):
		remove_child(world)
		world.free()
	world = null


func _unload() -> void:
	if pg != null and is_instance_valid(pg):
		remove_child(pg)
		pg.queue_free()
		pg = null
		await get_tree().physics_frame


func _part(kind: String, pos: Vector3, props := {}) -> Node3D:
	var n := (load(PZ % kind) as PackedScene).instantiate() as Node3D
	for k in props:
		n.set(k, props[k])
	n.position = pos
	world.add_child(n)
	return n


func _crate(kind: String, pos: Vector3) -> PuzzleCrate:
	var c := (load(PZ % "crate") as PackedScene).instantiate() as PuzzleCrate
	c.kind = kind
	c.position = pos
	world.add_child(c)
	return c


## Источник тока для проб: голый PuzzlePart, ток ставится _set_on.
func _source(pos := Vector3.ZERO) -> PuzzlePart:
	var s := PuzzlePart.new()
	s.name = "Source"
	s.position = pos
	world.add_child(s)
	return s


## Кукла «Человек» (как у игроков), ввод — скриптом.
func _doll(i: int, pos: Vector3, arm := false, parent: Node = null) -> Doll:
	var d := PuzzlePlayground.make_player(i)
	d.external_input = true
	d.position = pos
	(parent if parent != null else world).add_child(d)
	if arm:
		ArmAssist.attach_to(d)
	return d


static func _arm(d: Doll) -> ArmAssist:
	return PuzzlePlayground._arm(d)


## Перенести куклу целиком: ЦМ в to; скорости — ноль.
func _teleport(d: Doll, to: Vector3) -> void:
	var shift := to - d.centre_of_mass()
	shift.z = 0.0
	for p in d.parts.values():
		var b := p as RigidBody3D
		if b == null or not is_instance_valid(b):
			continue
		b.global_position += shift
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO


func _place(b: RigidBody3D, to: Vector3) -> void:
	b.global_position = to
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO
	b.rotation = Vector3.ZERO


static func _com(b: RigidBody3D) -> Vector3:
	var st := PhysicsServer3D.body_get_direct_state(b.get_rid())
	return b.global_position + (st.center_of_mass if st != null else Vector3.ZERO)


## Подвести руку к телу и схватить (рука — override к ближней точке; до 1.5 с); true — держит.
func _grab_with(arm: ArmAssist, b: RigidBody3D) -> bool:
	for i in 90:
		arm.set_target_override(arm.closest_point(b, arm.grip_global()))
		await get_tree().physics_frame
		if arm.find_candidate() == b:
			break
	arm.press_grab()
	await _ticks(2)
	return arm.held == b


## Рулить куклой к точкам по очереди (input_vec, полная тяга); true — дошла до последней за max_s.
func _steer(d: Doll, pts: Array, max_s: float, reach_m := 0.6) -> bool:
	var k := 0
	for i in int(max_s / TICK):
		if not is_instance_valid(d):
			return false
		var c := d.centre_of_mass()
		var p: Vector2 = pts[k]
		var to := Vector2(p.x - c.x, p.y - c.y)
		if to.length() < reach_m:
			k += 1
			if k >= pts.size():
				d.input_vec = Vector2.ZERO
				return true
			continue
		d.input_vec = to.normalized()
		if trace and i % 30 == 0:
			print("    steer %s t=%.1f com=(%.2f, %.2f) → (%.2f, %.2f) [%d/%d]" % [d.name, i * TICK, c.x, c.y, p.x, p.y, k + 1, pts.size()])
		await get_tree().physics_frame
	d.input_vec = Vector2.ZERO
	return false


# ------------------------------------------------------------------ parts

func _parts() -> void:
	print("--- parts")
	await _part_plate()
	await _part_lever()
	await _part_door()
	await _part_lift()
	await _part_gravity()
	await _part_logic()
	await _part_duo()


func _part_plate() -> void:
	_new_world()
	var plate := _part("plate", Vector3(0, 0, 0), {"threshold_kg": 30.0, "width": 2.0}) as PuzzlePlate
	var cargo := _part("plate", Vector3(6, 0, 0), {"threshold_kg": 55.0, "width": 2.6, "count_dolls": false}) as PuzzlePlate
	await _ticks(5)
	var empty_off := not plate.is_on() and plate.mass_now < 0.1
	var light := _crate("light", Vector3(0, 0.4, 0))
	await _wait(1.0)
	var light_kg := plate.mass_now
	var light_off := not plate.is_on()
	light.queue_free()
	var med := _crate("medium", Vector3(0, 0.5, 0))
	await _wait(1.0)
	var med_kg := plate.mass_now
	var med_on := plate.is_on()
	med.queue_free()
	await _wait(0.1)
	var off_soon := plate.is_on()   # выключение — не мгновенно (PUZZLE_PLATE_OFF_S)
	await _wait(0.5)
	var off_after := not plate.is_on()
	var d := _doll(0, Vector3(0, 0.05, 0))
	await _wait(1.5)
	var doll_kg := plate.mass_now
	var doll_on := plate.is_on()
	_teleport(d, Vector3(6, 1.0, 0))
	await _wait(1.0)
	var cargo_doll_kg := cargo.mass_now
	var cargo_doll_off := not cargo.is_on()
	_teleport(d, Vector3(-8, 1.0, 0))
	var duo := _crate("duo", Vector3(6, 0.6, 0))
	await _wait(1.0)
	var cargo_duo_on := cargo.is_on()
	var cargo_duo_kg := cargo.mass_now
	info["plate"] = {"light_kg": light_kg, "medium_kg": med_kg, "doll_kg": snappedf(doll_kg, 0.1), "cargo_doll_kg": cargo_doll_kg,
		"cargo_duo_kg": cargo_duo_kg}
	_check("plate_empty_off", empty_off, "масса %.1f" % plate.mass_now)
	_check("plate_light_10kg_off", light_off and absf(light_kg - 10.0) < 0.5, "ящик 10 кг: %.1f кг, ток %s" % [light_kg, str(not light_off)])
	_check("plate_medium_35kg_on", med_on and absf(med_kg - 35.0) < 0.5, "ящик 35 кг: %.1f кг" % med_kg)
	_check("plate_off_delay", off_soon and off_after, "через 0.1 с ещё ток: %s, через 0.6 с нет: %s" % [str(off_soon), str(off_after)])
	_check("plate_doll_on", doll_on and doll_kg > 30.0, "кукла: %.1f кг" % doll_kg)
	_check("scale_ignores_dolls", cargo_doll_off and cargo_doll_kg < 0.1, "кукла на грузовых весах: %.1f кг" % cargo_doll_kg)
	_check("scale_duo_60kg_on", cargo_duo_on and absf(cargo_duo_kg - 60.0) < 0.5, "ящик 60 кг на весах 55: %.1f кг" % cargo_duo_kg)
	duo.queue_free()


func _part_lever() -> void:
	_new_world()
	var lever := _part("lever", Vector3(0, 0, 0), {"start_on": false}) as PuzzleLever
	await _ticks(10)
	var a0 := lever.angle_deg()
	var off0 := not lever.is_on()
	# толчок рукояти моментом вправо (по часовой): перевалить через середину — фиксатор доводит до края
	for i in 30:
		lever.handle.apply_torque(Vector3(0, 0, -40.0))
		await get_tree().physics_frame
	await _wait(0.8)
	var a1 := lever.angle_deg()
	var on1 := lever.is_on()
	# небольшой толчок назад (не до середины) — остаётся включённым (фиксатор и гистерезис)
	for i in 6:
		lever.handle.apply_torque(Vector3(0, 0, 25.0))
		await get_tree().physics_frame
	await _wait(0.8)
	var on_kept := lever.is_on()
	var a2 := lever.angle_deg()
	lever.set_state(false)
	await _ticks(3)
	# рука: кукла слева, хватает рукоять за верх и летит вправо, рука — вперёд (как игрок: ЛКМ вправо + D)
	var d := _doll(0, Vector3(-1.2, 0.05, 0), true)
	var arm := _arm(d)
	await _wait(0.8)
	var grabbed := await _grab_with(arm, lever.handle)
	var on_arm := false
	for i in 120:
		arm.set_target_override(arm.root_point() + Vector3(arm.reach, 0.1, 0))
		d.input_vec = Vector2(1.0, 0.2)
		await get_tree().physics_frame
		if trace and i % 10 == 0:
			print("    lever t=%.2f ang=%.1f grip=%s tgt=%s held=%s hold=%s assist=%s com=%s" % [i * TICK, lever.angle_deg(), arm.grip_global(), arm.target, arm.held != null, arm.last_hold_force, arm.last_assist_force, d.centre_of_mass()])
		if lever.is_on():
			on_arm = true
			break
	d.input_vec = Vector2.ZERO
	arm.release("probe")
	arm.clear_target_override()
	# телом: кукла влетает в рукоять слева
	lever.set_state(false)
	_teleport(d, Vector3(-2.5, 1.0, 0))
	await _wait(0.5)
	var on_body := false
	for i in 120:
		d.input_vec = Vector2(1.0, 0.0)
		await get_tree().physics_frame
		if lever.is_on():
			on_body = true
			break
	d.input_vec = Vector2.ZERO
	_check("lever_body_flips", on_body, "кукла толкнула рукоять телом: %s" % str(on_body))
	info["lever"] = {"start_deg": snappedf(a0, 0.1), "pushed_deg": snappedf(a1, 0.1), "nudged_back_deg": snappedf(a2, 0.1),
		"arm_grabbed": grabbed}
	_check("lever_start_off", off0 and a0 < -Tuning.PUZZLE_LEVER_ON_DEG, "угол %.1f°" % a0)
	_check("lever_push_on", on1 and a1 > Tuning.PUZZLE_LEVER_MAX_DEG - 5.0, "после толчка %.1f°, ток %s" % [a1, str(on1)])
	_check("lever_hysteresis", on_kept and a2 > Tuning.PUZZLE_LEVER_ON_DEG, "слабый толчок назад: %.1f°, ток %s" % [a2, str(on_kept)])
	_check("lever_arm_flips", grabbed and on_arm, "рука схватила рукоять: %s, перекинула: %s" % [str(grabbed), str(on_arm)])


func _part_door() -> void:
	_new_world()
	var src := _source()
	var door := _part("door", Vector3(3, 0, 0), {"height": 2.8, "thickness": 1.0}) as PuzzleDoor
	door.input = door.get_path_to(src)
	await _ticks(5)
	var closed0 := door.open_frac() < 0.01
	src._set_on(true)
	var t_open := -1.0
	for i in 120:
		await get_tree().physics_frame
		if door.is_on():
			t_open = (i + 1) * TICK
			break
	src._set_on(false)
	var t_close := -1.0
	for i in 120:
		await get_tree().physics_frame
		if door.open_frac() < 0.001:
			t_close = (i + 1) * TICK
			break
	# ящик в проёме: дверь не опускается на него
	src._set_on(true)
	await _wait(1.0)
	var c := _crate("light", Vector3(3, 0.35, 0))
	await _wait(0.3)
	src._set_on(false)
	await _wait(1.5)
	var held_open := door.open_frac() > 0.5
	c.queue_free()
	await _wait(1.5)
	var closed_after := door.open_frac() < 0.01
	info["door"] = {"open_s": snappedf(t_open, 0.01), "close_s": snappedf(t_close, 0.01)}
	_check("door_closed_start", closed0, "ход %.2f" % door.open_frac())
	_check("door_opens", t_open > 0.0 and t_open < 1.5, "открылась за %.2f с" % t_open)
	_check("door_closes", t_close > 0.0 and t_close < 2.0, "закрылась за %.2f с" % t_close)
	_check("door_waits_for_body", held_open and closed_after, "ящик в проёме — не опустилась: %s; убрали — закрылась: %s" % [str(held_open), str(closed_after)])


func _part_lift() -> void:
	_new_world()
	var src := _source()
	var lift := _part("lift", Vector3(0, 0.0, 0), {"width": 3.0, "travel": 5.0}) as PuzzleLift
	lift.input = lift.get_path_to(src)
	await _ticks(5)
	var res := {}
	for kind in ["duo", "iron"]:
		var c := _crate(kind, Vector3(0, 0.7, 0))
		await _wait(1.0)
		var y0 := _com(c).y
		src._set_on(true)
		var t_up := -1.0
		for i in 600:
			await get_tree().physics_frame
			if lift.is_on():
				t_up = (i + 1) * TICK
				break
		await _wait(0.5)
		var rise := _com(c).y - y0
		src._set_on(false)
		await _until(func() -> bool: return lift.height_now() < 0.01, 8.0)
		var down := lift.height_now() < 0.01
		res[kind] = {"up_s": snappedf(t_up, 0.01), "rise_m": snappedf(rise, 0.01), "down": down}
		_check("lift_carries_%s" % kind, t_up > 0.0 and rise > 4.5 and down,
			"%s %.0f кг: наверху за %.2f с, поднялся на %.2f м, без тока вниз: %s" % [kind, c.mass, t_up, rise, str(down)])
		c.queue_free()
		await _ticks(2)
	info["lift"] = res


func _part_gravity() -> void:
	_new_world()
	var src := _source()
	var g := _part("gravity_zone", Vector3(0, 4.5, 0), {"size": Vector2(16, 9), "on_dir": Vector2(1, 0), "off_dir": Vector2(0, -1)}) as PuzzleGravity
	g.input = g.get_path_to(src)
	var c := _crate("light", Vector3(-3, 3.0, 0))
	await _wait(2.5)
	var fell_down := _com(c).y < 1.0
	var x0 := _com(c).x
	src._set_on(true)
	await _wait(Tuning.PUZZLE_GRAVITY_BLEND_S + 0.1)
	var d := g.down()
	var turned := g.is_on() and d.x > 0.99
	await _wait(1.5)
	var dx := _com(c).x - x0
	src._set_on(false)
	await _wait(Tuning.PUZZLE_GRAVITY_BLEND_S + 0.1)
	var back := g.down().y < -0.99 and not g.is_on()
	info["gravity"] = {"down_on": [snappedf(d.x, 0.01), snappedf(d.y, 0.01)], "crate_dx_m": snappedf(dx, 0.01)}
	_check("gravity_default_down", fell_down, "ящик упал на пол: y %.2f" % _com(c).y)
	_check("gravity_turns_right", turned, "«низ» под током: (%.2f, %.2f)" % [d.x, d.y])
	_check("gravity_crate_slides", dx > 1.0, "ящик съехал вправо на %.2f м" % dx)
	_check("gravity_back_down", back, "без тока «низ» снова вниз")


func _part_logic() -> void:
	_new_world()
	var a := _source()
	var b := _source()
	var l_and := _part("logic", Vector3(0, 3, 0), {"mode": PuzzleLogic.Mode.AND}) as PuzzleLogic
	var l_or := _part("logic", Vector3(2, 3, 0), {"mode": PuzzleLogic.Mode.OR}) as PuzzleLogic
	var l_tm := _part("logic", Vector3(4, 3, 0), {"mode": PuzzleLogic.Mode.TIMER, "hold_s": 2.0}) as PuzzleLogic
	for l in [l_and, l_or]:
		l.inputs = [l.get_path_to(a), l.get_path_to(b)] as Array[NodePath]
	l_tm.inputs = [l_tm.get_path_to(a)] as Array[NodePath]
	var cable := _part("cable", Vector3(0, 0, -1), {"points": PackedVector2Array([Vector2(0, 0), Vector2(0, 2)])}) as PuzzleCable
	cable.source = cable.get_path_to(l_and)
	var table := []
	var good := true
	for pair in [[false, false], [true, false], [false, true], [true, true]]:
		a._set_on(pair[0])
		b._set_on(pair[1])
		await _ticks(3)
		var want_and: bool = pair[0] and pair[1]
		var want_or: bool = pair[0] or pair[1]
		table.append("%d%d→И%d ИЛИ%d" % [int(pair[0]), int(pair[1]), int(l_and.is_on()), int(l_or.is_on())])
		good = good and l_and.is_on() == want_and and l_or.is_on() == want_or
	_check("logic_and_or", good, ", ".join(table))
	var lit := cable.is_lit()
	a._set_on(false)
	b._set_on(false)
	await _ticks(3)
	_check("cable_lit", lit and not cable.is_lit(), "под током светится: %s, без — нет: %s" % [str(lit), str(not cable.is_lit())])
	a._set_on(true)
	await _ticks(3)
	var tm_on := l_tm.is_on()
	a._set_on(false)
	await _wait(1.5)
	var held := l_tm.is_on()
	await _wait(0.7)
	var gone := not l_tm.is_on()
	_check("logic_timer_holds", tm_on and held and gone, "вход погас: через 1.5 с ток %s, через 2.2 с нет: %s" % [str(held), str(gone)])


## Ящик «вдвоём» 60 кг (вес 210 Н): одна рука (предел 150 Н) не поднимает, две — да. Кукла держит ящик и летит вверх изо всех сил.
func _part_duo() -> void:
	var res := {}
	for hands in [1, 2]:
		_new_world()
		var c := _crate("duo", Vector3(0, 0.51, 0))
		var d1 := _doll(0, Vector3(-1.0, 0.05, 0), true)
		PuzzleCarry.attach_to(d1)
		var d2: Doll = null
		if hands == 2:
			d2 = _doll(1, Vector3(1.0, 0.05, 0), true)
			PuzzleCarry.attach_to(d2)
		await _wait(1.0)
		var y0 := _com(c).y
		var g1 := await _grab_with(_arm(d1), c)
		var g2 := true
		if d2 != null:
			g2 = await _grab_with(_arm(d2), c)
		for a in [_arm(d1), _arm(d2) if d2 != null else null]:
			if a != null:
				(a as ArmAssist).clear_target_override()
		var rise := 0.0
		var slip := -1.0
		for i in 240:
			d1.input_vec = Vector2(-0.1 if d2 != null else 0.1, 1.0)   # вдвоём — чуть врозь (не толкаются над ящиком)
			if d2 != null:
				d2.input_vec = Vector2(0.1, 1.0)
			await get_tree().physics_frame
			rise = maxf(rise, _com(c).y - y0)
			if trace and i % 10 == 0:
				var a1 := _arm(d1)
				var a2 := _arm(d2) if d2 != null else null
				print("    duo%d t=%.2f crate_y=%.2f d1y=%.2f d2y=%.2f st1=%.2f st2=%.2f f1=%s f2=%s tm=%.2f rot=%.0f" % [hands, i * TICK, _com(c).y, d1.centre_of_mass().y,
					d2.centre_of_mass().y if d2 != null else 0.0, a1.hold_distance(), a2.hold_distance() if a2 != null else 0.0,
					a1.last_hold_force, a2.last_hold_force if a2 != null else Vector3.ZERO, d1.thrust_mult, rad_to_deg(c.rotation.z)])
			if slip < 0.0 and (_arm(d1).held != c or (d2 != null and _arm(d2).held != c)):
				slip = (i + 1) * TICK
		d1.input_vec = Vector2.ZERO
		if d2 != null:
			d2.input_vec = Vector2.ZERO
		res["hands_%d" % hands] = {"grabbed": g1 and g2, "rise_m": snappedf(rise, 0.01), "slip_s": snappedf(slip, 0.01)}
		if hands == 1:
			_check("duo_one_hand_no", g1 and rise < 0.3, "одна рука: схватила %s, подъём %.2f м, срыв %s" % [str(g1), rise, "нет" if slip < 0.0 else "%.2f с" % slip])
		else:
			_check("duo_two_hands_lift", g1 and g2 and rise > 1.0, "две руки: схватили %s, подъём %.2f м" % [str(g1 and g2), rise])
	# телом снизу (для сведения): кукла под ящиком тянет вверх 4 с
	_new_world()
	var c2 := _crate("duo", Vector3(0, 3.0, 0))
	var d3 := _doll(0, Vector3(0, 0.05, 0))
	await _wait(1.5)
	var yb := _com(c2).y
	var rise_body := 0.0
	for i in 240:
		d3.input_vec = Vector2(0, 1)
		await get_tree().physics_frame
		rise_body = maxf(rise_body, _com(c2).y - yb)
	d3.input_vec = Vector2.ZERO
	res["body_push_m"] = snappedf(rise_body, 0.01)
	info["duo"] = res
	print("  duo: ", JSON.stringify(res))


# ------------------------------------------------------------------ controls (заглушки, ниже)

func _controls() -> void:
	print("--- controls")
	PuzzleKeyArm.ensure_action()
	_new_world()
	# тумбы под ящики на высоте кисти (стоящая кукла пол не достаёт)
	var st := StaticBody3D.new()
	world.add_child(st)
	PuzzlePart.box_shape(st, "PedR", Vector3(0.5, 0.7, 1.0), Vector3(0.9, 0.35, 0))
	PuzzlePart.box_shape(st, "PedL", Vector3(0.5, 0.7, 1.0), Vector3(-1.3, 0.35, 0))
	var d := _doll(1, Vector3(0, 0.05, 0), true)
	d.input_prefix = "p2"
	var key := PuzzleKeyArm.attach_to(d)
	var arm := _arm(d)
	var right := _crate("light", Vector3(0.9, 1.02, 0))
	var left := _crate("light", Vector3(-1.3, 1.02, 0))
	await _wait(1.0)
	# 1. стрелка вправо + клавиша — рука тянется к правому и хватает (стрелка ведёт и куклу — как у игрока)
	key.arrows_override = Vector2(1, 0)
	d.input_vec = Vector2(1, 0)
	key.press()
	var t_grab := -1.0
	for i in 60:
		await get_tree().physics_frame
		if i == 9:
			d.input_vec = Vector2.ZERO   # стрелку нажали коротко: шаг к ящику, рука тянется дальше сама
		if trace and i % 3 == 0:
			var rt := key.reach_target
			print("    key t=%.2f act=%s tgt=%s grip=%s root=%s reach=%.2f armtgt=%s active=%s cand=%s" % [i * TICK, key.last_action,
				rt.name if rt != null else "-", arm.grip_global(), arm.root_point(), arm.reach, arm.target, arm.arm_active,
				arm.find_candidate().name if arm.find_candidate() != null else "-"])
		if arm.held != null:
			t_grab = (i + 1) * TICK
			break
	d.input_vec = Vector2.ZERO
	_check("keyarm_grabs_by_arrow", arm.held == right and t_grab > 0.0 and t_grab <= Tuning.PUZZLE_KEY_REACH_S + 0.1,
		"схватила %s за %.2f с" % ["правый" if arm.held == right else ("левый" if arm.held == left else "ничего"), t_grab])
	_check("keyarm_hint_keys", arm.hint_grab_key == "/" and arm.hint_aim != "", "подпись: «%s» / «%s»" % [arm.hint_grab_key, arm.hint_aim])
	# 2. со стрелкой рука держит предмет перед собой в её сторону
	await _wait(0.6)
	var shoulder_x := arm.root_point().x
	var front := arm.arm_active and arm.held != null and _com(arm.held).x > shoulder_x + 0.2
	_check("keyarm_carries_in_front", front, "рука активна %s, ящик правее плеча на %.2f м" % [str(arm.arm_active), (_com(right).x - shoulder_x)])
	# 3. клавиша со стрелкой — бросок в её сторону
	key.arrows_override = Vector2(1, 0.5)
	await _wait(0.3)
	var throws0 := float(arm.last_throw.get("t", -1.0))
	key.press()
	await _ticks(3)
	var thrown := arm.held == null and float(arm.last_throw.get("t", -1.0)) > throws0
	var tdir: Vector3 = arm.last_throw.get("dir", Vector3.ZERO)
	var tv := right.linear_velocity
	_check("keyarm_throws_with_arrow", thrown and tdir.x > 0.5 and tv.x > 2.0, "брошен: %s, направление (%.2f, %.2f), скорость x %.1f м/с" % [str(thrown), tdir.x, tdir.y, tv.x])
	# 4. стрелка влево: схватить левый и положить без стрелки (без броска)
	_teleport(d, Vector3(0, 1.0, 0))
	key.arrows_override = Vector2(-1, 0)
	await _wait(1.0)
	d.input_vec = Vector2(-1, 0)
	key.press()
	await _ticks(9)
	d.input_vec = Vector2.ZERO
	await _until(func() -> bool: return arm.held != null, 1.0)
	var got_left := arm.held == left
	key.arrows_override = Vector2.ZERO
	await _wait(0.5)
	var throws1 := float(arm.last_throw.get("t", -1.0))
	key.press()
	await _ticks(3)
	var dropped := arm.held == null and float(arm.last_throw.get("t", -1.0)) == throws1 and key.last_action == "drop"
	_check("keyarm_picks_by_direction", got_left, "стрелка влево — взяла %s" % ["левый" if got_left else "не тот"])
	_check("keyarm_drops_without_arrow", dropped, "без стрелки — положила без броска: %s (действие %s)" % [str(dropped), key.last_action])
	# 5. геймпад: стик отклонён — клавиатурная рука уступает, подпись снова «RB»
	Input.action_press("p2_arm_right", 1.0)
	await _ticks(3)
	var yields := not key._overriding and arm.hint_grab_key == ""
	Input.action_release("p2_arm_right")
	await _ticks(2)
	_check("keyarm_pad_yields", yields, "стик P2 — своя цель снята: %s, подпись «%s»" % [str(not key._overriding), arm.hint_grab_key])
	# 6. другие режимы: P2 без PuzzleKeyArm — клавиша «/» ничего не делает, подпись прежняя
	var d2 := _doll(1, Vector3(4, 0.05, 0), true)
	d2.input_prefix = "p2"
	d2.external_input = false
	var arm2 := _arm(d2)
	var c3 := _crate("light", Vector3(4.9, 0.31, 0))
	await _wait(0.8)
	Input.action_press(PuzzleKeyArm.ACTION)
	await _ticks(2)
	Input.action_release(PuzzleKeyArm.ACTION)
	await _wait(0.6)
	_check("p2_plain_unchanged", arm2.held == null and arm2.last_grab_action == "" and arm2.hint_grab_key == "" and not arm2.arm_active,
		"без узла: держит %s, действие «%s», подпись «%s»" % [str(arm2.held), arm2.last_grab_action, arm2.hint_grab_key])
	c3.queue_free()
	_clear_world()
	# 7. площадка гонки: у P2-человека нет клавиатурной руки (ставит только площадка головоломок)
	var race := (load(RACE) as PackedScene).instantiate()
	add_child(race)
	await _wait(0.5)
	race.call("set_p2_human", true)
	await _wait(0.3)
	var has_key := false
	for n in get_tree().get_nodes_in_group("dolls"):
		if (n as Node).get_node_or_null(PuzzleKeyArm.NODE_NAME) != null or (n as Node).get_node_or_null(PuzzleCarry.NODE_NAME) != null:
			has_key = true
	_check("race_p2_no_keyarm", not has_key, "PuzzleKeyArm / PuzzleCarry у кукол гонки: %s" % str(has_key))
	remove_child(race)
	race.queue_free()
	await _ticks(2)


## Загрузить площадку (P2 сразу в игре, автоприход выключен, игроки — под скриптом).
func _load_pg(start := 0, p2 := true) -> void:
	await _unload()
	_clear_world()
	Engine.time_scale = 1.0
	pg = (load(PLAYGROUND) as PackedScene).instantiate() as PuzzlePlayground
	pg.start_room = start
	pg.p2_on_start = p2
	pg.auto_join = false
	(pg.get_node("Match") as Match).feel_enabled = false
	add_child(pg)
	await _ticks(5)
	_script_players()


func _script_players() -> void:
	for d in pg.players():
		(d as Doll).external_input = true
		(d as Doll).input_vec = Vector2.ZERO


## Точка комнаты (локальная → мир).
func _at(r: PuzzleRoom, x: float, y: float) -> Vector3:
	return r.global_position + Vector3(x, y, 0)


func _door_y(r: PuzzleRoom) -> float:
	return r.exit_rect.position.y


## Вывести куклу в тамбур через выходную дверь; true — комната сменилась (или демо кончилось). Сначала вверх над полом (рычаг, ящики),
## потом к проёму и в тамбур.
func _exit_via_door(d: Doll, r: PuzzleRoom, max_s := 8.0) -> bool:
	var i0 := pg.current
	var dy := _door_y(r)
	var c0 := d.centre_of_mass()
	var pts := [Vector2(c0.x, maxf(c0.y, 2.2)), Vector2(_at(r, 6.4, dy + 1.4).x, dy + 1.4), Vector2(_at(r, 10.4, dy + 1.4).x, dy + 1.4)]
	var t := 0.0
	var k := 0
	while t < max_s:
		if pg.current != i0 or pg.done:
			d.input_vec = Vector2.ZERO
			return true
		var c := d.centre_of_mass()
		var p: Vector2 = pts[k]
		var to := Vector2(p.x - c.x, p.y - c.y)
		if to.length() < 0.6 and k < pts.size() - 1:
			k += 1
			continue
		d.input_vec = to.normalized()
		if trace and int(t / TICK) % 30 == 0:
			print("    exit %s t=%.1f com=(%.2f, %.2f) → (%.2f, %.2f) door %.2f alive %s ctl %s ext %s tm %.2f stun %s v %s held %s" % [d.name, t, c.x, c.y, p.x, p.y, r.door().open_frac(), d.alive, d.control_enabled, d.external_input, d.thrust_mult, d.is_stunned(), d.com_velocity(), _arm(d).held])
		await get_tree().physics_frame
		t += TICK
	d.input_vec = Vector2.ZERO
	return pg.current != i0 or pg.done


func _door_closed(r: PuzzleRoom) -> bool:
	return r.door() != null and r.door().open_frac() < 0.01


func _rooms(only: String) -> void:
	print("--- rooms")
	await _load_pg(0, true)
	var want := func(i: int) -> bool: return only == "" or str(i + 1) in only.split("+")
	var start_ok := pg.current == 0 and pg.rooms.size() == 6
	_check("rooms_six", start_ok, "комнат %d, старт в %d" % [pg.rooms.size(), pg.current + 1])
	var timings := {}
	for i in 6:
		if not want.call(i):
			continue
		if pg.current != i:
			pg.goto_room(i)
			await _ticks(3)
		var r := pg.rooms[i]
		pg.reset_room()
		_script_players()
		var pressed_at_start: Array = []   # игроки у входа не давят плиты ни в один тик, пока встают (руки в Т-позе ±0.9 м)
		for k in int(1.5 / TICK):
			await get_tree().physics_frame
			for part in r.parts():
				if part is PuzzlePlate and (part as PuzzlePlate).mass_now > 0.1 and not pressed_at_start.has(String((part as Node).name)):
					pressed_at_start.append(String((part as Node).name))
		var closed := _door_closed(r)
		_check("room%d_spawn_clear" % (i + 1), pressed_at_start.is_empty(), "плиты под игроками у входа: %s" % str(pressed_at_start))
		var t0 := pg.total_time
		var solved: bool = await call("_solve_%d" % (i + 1), r, true)
		var opened := r.solved() or r.door().open_frac() > 0.5
		var moved := await _exit_via_door(pg.p1, r)
		timings["room%d" % (i + 1)] = snappedf(pg.total_time - t0, 0.1)
		var next_ok := (pg.current == i + 1) if i < 5 else pg.done
		_check("room%d_coop" % (i + 1), closed and solved and opened and moved and next_ok,
			"дверь закрыта в начале %s, сценарий %s, дверь открыта %s, вышли %s, дальше %s" % [str(closed), str(solved), str(opened), str(moved), str(next_ok)])
		if i < 5 and next_ok:
			var inside := true
			for d in pg.players():
				var c := (d as Doll).centre_of_mass()
				inside = inside and pg.rooms[i + 1].inner_global().grow(0.3).has_point(Vector2(c.x, c.y))
			_check("room%d_players_moved" % (i + 1), inside, "игроки у входа комнаты %d" % (i + 2))
	info["room_times_coop"] = timings
	if only == "":
		_check("demo_finished", pg.done and pg.room_times.size() == 6, "итоги: %s, комнат пройдено %d" % [str(pg.done), pg.room_times.size()])
	# соло: P2 ушёл; комнаты 2, 3, 5 решаются иначе (ящик вместо второго)
	pg.restart_demo()
	pg.leave_p2()
	await _ticks(3)
	_script_players()
	for i in [1, 2, 4]:
		if not want.call(i):
			continue
		pg.goto_room(i)
		var r := pg.rooms[i]
		pg.reset_room()
		await _wait(0.6)
		_script_players()
		var solved: bool = await call("_solve_%d" % (i + 1), r, false)
		var opened := r.door().open_frac() > 0.5
		var moved := await _exit_via_door(pg.p1, r, 10.0)
		_check("room%d_solo" % (i + 1), solved and opened and moved and pg.current == i + 1,
			"сценарий %s, дверь открыта %s, успел выйти %s" % [str(solved), str(opened), str(moved)])


## 1. Ящик с полки на плиту: P1 подлетает, хватает (ArmAssist), несёт к плите, кладёт.
func _solve_1(r: PuzzleRoom, _coop: bool) -> bool:
	var p1 := pg.p1
	var crate := r.find("Crate") as RigidBody3D
	var plate := r.find("Plate") as PuzzlePlate
	_teleport(p1, _at(r, 7.3, 5.6))   # рука-хват у куклы слева (Hand_R смотрит в камеру): встать правее ящика
	await _wait(0.5)
	var arm := _arm(p1)
	if not await _grab_with(arm, crate):
		return false
	arm.clear_target_override()
	await _steer(p1, [Vector2(_at(r, 4.0, 6.5).x, 6.5), Vector2(_at(r, -1.5, 3.0).x, 3.0)], 6.0, 0.5)
	await _wait(0.5)
	arm.release("probe")
	await _until(func() -> bool: return plate.is_on(), 3.0)
	await _until(func() -> bool: return r.door().is_on(), 2.0)
	return plate.is_on() and crate.global_position.distance_to(plate.global_position) < 1.5


## 2. Две плиты: вдвоём — по кукле на плиту; соло — ящик 35 кг на одну, P1 на другую. И → ТАЙМЕР 4 с.
func _solve_2(r: PuzzleRoom, coop: bool) -> bool:
	if coop:
		# R — комната заново: сдвинутый ящик возвращается на место
		var m0 := r.find("Medium") as Node3D
		var home := m0.global_position
		_place(m0 as RigidBody3D, _at(r, 5.0, 4.0))
		await _ticks(5)
		pg.reset_room()
		await _wait(0.3)
		var m1 := r.find("Medium") as Node3D
		var back := m1 != null and m1.global_position.distance_to(home) < 0.15
		_check("room_reset_props", back, "ящик после R: %s" % (str(m1.global_position - home) if m1 != null else "нет"))
		_script_players()
	var a := r.find("PlateA") as PuzzlePlate
	var b := r.find("PlateB") as PuzzlePlate
	if coop:
		_teleport(pg.p2, _at(r, -3.6, 1.0))
	else:
		var med := r.find("Medium") as RigidBody3D
		_place(med, _at(r, -3.6, 0.45))
	_teleport(pg.p1, _at(r, 3.6, 1.0))
	var ok_ := await _until(func() -> bool: return a.is_on() and b.is_on(), 3.0)
	await _until(func() -> bool: return r.door().is_on(), 2.0)
	return ok_


## 3. Весы на уступе: вдвоём несут ящик 60 кг (обе руки ArmAssist); соло — четыре ящика по 15 кг на весы.
func _solve_3(r: PuzzleRoom, coop: bool) -> bool:
	var scale := r.find("Scale") as PuzzlePlate
	if not coop:
		for k in 4:
			var b := r.find("Box%d" % (k + 1)) as RigidBody3D
			_place(b, _at(r, 4.3 + 0.7 * (k % 3), 3.35 + 0.65 * float(k / 3)))
		await _until(func() -> bool: return scale.is_on(), 3.0)
		await _until(func() -> bool: return r.door().is_on(), 2.0)
		return scale.is_on()
	var duo := r.find("Duo") as RigidBody3D
	var c0 := _com(duo)
	_teleport(pg.p1, Vector3(c0.x - 1.0, 1.0, 0))
	_teleport(pg.p2, Vector3(c0.x + 1.0, 1.0, 0))
	await _wait(0.6)
	var a1 := _arm(pg.p1)
	var a2 := _arm(pg.p2)
	var g1 := await _grab_with(a1, duo)
	var g2 := await _grab_with(a2, duo)
	a1.clear_target_override()
	a2.clear_target_override()
	if not (g1 and g2):
		print("    room3: схватили P1 %s, P2 %s" % [str(g1), str(g2)])
		return false
	var lifted := false
	for i in int(14.0 / TICK):
		var c := _com(duo)
		var v := Vector2(0, 1)
		if c.y > 4.3:
			v = Vector2(1, 0.25)
		pg.p1.input_vec = Vector2(v.x - 0.1, v.y).normalized()
		pg.p2.input_vec = Vector2(v.x + 0.1, v.y).normalized()
		await get_tree().physics_frame
		if trace and i % 30 == 0:
			print("    room3 t=%.1f duo=(%.2f, %.2f) held %s %s" % [i * TICK, c.x - r.global_position.x, c.y, str(a1.held == duo), str(a2.held == duo)])
		if c.x - r.global_position.x > 4.6 and c.y > 3.6:
			lifted = true
			break
		if a1.held != duo or a2.held != duo:
			break
	pg.p1.input_vec = Vector2.ZERO
	pg.p2.input_vec = Vector2.ZERO
	a1.release("probe")
	a2.release("probe")
	info["room3_carry"] = {"lifted": lifted, "x": snappedf(_com(duo).x - r.global_position.x, 0.01), "y": snappedf(_com(duo).y, 0.01)}
	await _until(func() -> bool: return scale.is_on(), 3.0)
	await _until(func() -> bool: return r.door().is_on(), 2.0)
	_check("room3_duo_carried_by_two", lifted and scale.is_on(), "ящик 60 кг двумя руками на весах: %s" % JSON.stringify(info["room3_carry"]))
	return scale.is_on()


## 4. Рычаг гравитации: P1 хватает рукоять и перекидывает (рука + тяга), «низ» уходит вправо, чугунный ящик падает на плиту на стене.
func _solve_4(r: PuzzleRoom, _coop: bool) -> bool:
	var lever := r.find("Lever") as PuzzleLever
	var g := r.find("Gravity") as PuzzleGravity
	var wp := r.find("WallPlate") as PuzzlePlate
	var p1 := pg.p1
	_teleport(p1, _at(r, -4.8, 1.0))
	await _wait(0.6)
	var arm := _arm(p1)
	var grabbed := await _grab_with(arm, lever.handle)
	for i in 120:
		if lever.is_on():
			break
		arm.set_target_override(arm.root_point() + Vector3(arm.reach, 0.1, 0))
		p1.input_vec = Vector2(1.0, 0.2)
		await get_tree().physics_frame
	p1.input_vec = Vector2.ZERO
	arm.release("probe")
	arm.clear_target_override()
	var turned := await _until(func() -> bool: return g.is_on(), 3.0)
	var pressed := await _until(func() -> bool: return wp.is_on(), 5.0)
	await _until(func() -> bool: return r.door().is_on(), 2.0)
	info["room4"] = {"grabbed": grabbed, "lever_on": lever.is_on(), "gravity": [snappedf(g.down().x, 0.01), snappedf(g.down().y, 0.01)],
		"wall_plate_kg": snappedf(wp.mass_now, 0.1)}
	return lever.is_on() and turned and pressed


## Толкать чугунный ящик телом вправо, пока его центр не дойдёт до x_to (локально) или не включатся весы; застрял (перелез через ящик,
## упёрся) — заново из-за ящика, до 3 попыток (как сделал бы игрок). floor_y — высота, на которой стоит ящик (низ).
func _push_iron(r: PuzzleRoom, iron: RigidBody3D, x_to: float, floor_y: float, scale: PuzzlePlate, lift: PuzzleLift) -> void:
	for attempt in 3:
		if scale.is_on() or _com(iron).x - r.global_position.x >= x_to:
			break
		var ic0 := _com(iron)
		_teleport(pg.p1, Vector3(ic0.x - 1.15, floor_y + 1.0, 0))
		await _wait(0.3)
		var still := 0.0
		var last_x := ic0.x
		for i in int(5.0 / TICK):
			pg.p1.input_vec = Vector2(1.0, -0.3).normalized()
			await get_tree().physics_frame
			var ic := _com(iron)
			if trace and i % 30 == 0:
				var pc := pg.p1.centre_of_mass()
				print("    room5 push #%d t=%.1f iron=(%.2f, %.2f) p1=(%.2f, %.2f) lift %.2f scale %.0f" % [attempt, i * TICK, ic.x - r.global_position.x, ic.y, pc.x - r.global_position.x, pc.y, lift.height_now(), scale.mass_now])
			if scale.is_on() or ic.x - r.global_position.x >= x_to:
				break
			still = still + TICK if absf(ic.x - last_x) < 0.002 else 0.0
			last_x = ic.x
			if still > 1.0 or pg.p1.centre_of_mass().x > ic.x + 0.3:
				break
	pg.p1.input_vec = Vector2.ZERO


## 5. Лифт: P1 толкает чугунный ящик по полу на платформу; вдвоём — P2 на плите, соло — ящик 35 кг на плите; лифт наверху — P1 толкает
## ящик на весы балкона.
func _solve_5(r: PuzzleRoom, coop: bool) -> bool:
	var lift := r.find("Lift") as PuzzleLift
	var scale := r.find("Scale") as PuzzlePlate
	var iron := r.find("Iron") as RigidBody3D
	await _push_iron(r, iron, 1.3, 0.0, scale, lift)
	var on_lift := absf(_com(iron).x - r.global_position.x - 1.5) < 1.0 and lift.height_now() < 0.1
	_check("room5_iron_pushed_on_lift_%s" % ("coop" if coop else "solo"), on_lift, "чугунный ящик толкнули по полу на платформу: x %.2f" % (_com(iron).x - r.global_position.x))
	_teleport(pg.p1, _at(r, 1.5, 7.5))   # P1 подождёт над ящиком (поедет с ним наверх)
	if coop:
		_teleport(pg.p2, _at(r, 5.6, 1.0))
	else:
		_place(r.find("Medium") as RigidBody3D, _at(r, 5.6, 0.45))
	var up := await _until(func() -> bool: return lift.is_on(), 7.0)
	var rode := _com(iron).y > 5.0
	await _push_iron(r, iron, 99.0, 5.02, scale, lift)
	var on_scale := await _until(func() -> bool: return scale.is_on(), 2.0)
	await _until(func() -> bool: return r.door().is_on(), 2.0)
	var stays := true
	if not coop:
		var hold := float((r.find("Timer") as PuzzleLogic).hold_s)
		await _wait(hold + 2.0)
		stays = lift.height_now() > 4.9   # ящик на плите держит ток: таймер (8 с) не кончается
	info["room5_%s" % ("coop" if coop else "solo")] = {"lift_up": up, "iron_rode": rode, "on_scale": on_scale, "lift_stays": stays}
	return up and rode and on_scale and stays


## 6. Финал: P1 хватает бочку и бросает в трещину (бросок ArmAssist), стена рушится; P1 на плиту в нише, потом к двери за 6 с.
func _solve_6(r: PuzzleRoom, _coop: bool) -> bool:
	var p1 := pg.p1
	# раздатчик: бочек не осталось, стена цела — через PUZZLE_BARREL_RESPAWN_S падает новая; потом комната заново
	for n in ["BarrelA", "BarrelB"]:
		var b0 := r.find(n)
		if b0 != null:
			b0.get_parent().remove_child(b0)
			b0.queue_free()
	var dispensed := await _until(func() -> bool: return r.find("Dispensed0") is ExplosiveBarrel, Tuning.PUZZLE_BARREL_RESPAWN_S + 1.0)
	_check("room6_dispenser", dispensed, "бочек не осталось — новая из люка: %s" % str(dispensed))
	pg.reset_room()
	await _wait(0.5)
	_script_players()
	p1 = pg.p1
	var wall := r.find("CrackWall") as PuzzleCrackWall
	var plate := r.find("Plate") as PuzzlePlate
	var arm := _arm(p1)
	var grabbed := false
	var broke := false
	var throws := 0
	# бросок в трещину; мимо (бочка рванула не у стены) — следующая бочка, как сделал бы игрок
	for bn in ["BarrelB", "BarrelA"]:
		var barrel := r.find(bn) as RigidBody3D
		if barrel == null or not is_instance_valid(barrel):
			continue
		_place(barrel, _at(r, 2.0, 0.02))
		_teleport(p1, _at(r, 1.2, 1.0))
		await _wait(0.6)
		var g := await _grab_with(arm, barrel)
		grabbed = grabbed or g
		if not g:
			continue
		for i in 30:
			arm.set_target_override(arm.root_point() + Vector3(arm.reach, 0.25, 0))
			await get_tree().physics_frame
		arm.press_grab()
		throws += 1
		await _ticks(2)
		arm.clear_target_override()
		if trace:
			for k in 40:
				if not is_instance_valid(barrel) or barrel.is_queued_for_deletion():
					print("    room6 throw %d: бочки нет на тике %d, стена hp %.1f" % [throws, k, wall.hp if is_instance_valid(wall) else -1.0])
					break
				if k % 5 == 0:
					print("    room6 throw %d t=%d barrel=(%.2f, %.2f) v=%s held=%s p1=%s" % [throws, k, barrel.global_position.x - r.global_position.x, barrel.global_position.y, barrel.linear_velocity, arm.held, p1.centre_of_mass() - r.global_position])
				await get_tree().physics_frame
		broke = await _until(func() -> bool: return not is_instance_valid(wall) or wall.broken, 4.0)
		if trace:
			print("    room6 after throw %d: broke %s, бочка %s, стена hp %.1f state %d, P2 %s, тела у стены: %s" % [throws, str(broke),
				str(barrel.global_position - r.global_position) if is_instance_valid(barrel) else "нет", wall.hp if is_instance_valid(wall) else -1.0,
				wall.state if is_instance_valid(wall) else -1, str(pg.p2.centre_of_mass() - r.global_position) if pg.p2 != null else "-",
				str(r.get_node("Props").get_children().map(func(n: Node) -> String: return "%s@%.1f" % [n.name, (n as Node3D).global_position.x - r.global_position.x]))])
		if broke:
			break
	await _wait(1.0)
	_teleport(p1, _at(r, 4.0, 1.2))
	await _wait(0.3)
	var reached := await _steer(p1, [Vector2(_at(r, 6.85, 1.0).x, 1.0)], 3.0, 0.4)
	var pressed := await _until(func() -> bool: return plate.is_on(), 2.0)
	var opened := await _until(func() -> bool: return r.door().is_on(), 2.0)
	# с плиты — к двери наверху (таймер 6 с): из ниши влево, вверх, вправо в проём
	var dy := _door_y(r)
	var t0 := pg.room_time
	await _steer(p1, [Vector2(_at(r, 4.2, 1.4).x, 1.4), Vector2(_at(r, 4.2, dy + 1.4).x, dy + 1.4)], 4.0, 0.6)
	info["room6"] = {"grabbed": grabbed, "throws": throws, "wall_broken": broke, "plate": pressed, "door": opened, "to_door_s": snappedf(pg.room_time - t0, 0.01)}
	return grabbed and broke and reached and pressed and opened


## Границы: в каждой комнате (двери закрыты) кукла 8 раз по 3 с летит в одну сторону изо всех сил, с ускорением — ЦМ не выходит за
## внутренность комнаты (+ BOUNDS_MARGIN_M на толщину куклы у стены), комната не сменяется (в тамбур при закрытой двери не попасть).
const BOUNDS_MARGIN_M := 0.4


func _bounds() -> void:
	print("--- bounds")
	await _load_pg(0, false)
	var worst := {}
	for i in 6:
		pg.goto_room(i)
		var r := pg.rooms[i]
		var inner := r.inner_global().grow(BOUNDS_MARGIN_M)
		var p1 := pg.p1
		var escaped := ""
		var legit := 0
		var max_out := 0.0
		for k in 8:
			var ang := TAU * float(k) / 8.0
			var dir := Vector2(cos(ang), sin(ang))
			if pg.current != i:
				pg.goto_room(i)
			pg.reset_room()   # механизмы и ящики на места: кукла могла задеть рычаг (комната 4) — это не побег
			await _wait(0.3)
			_script_players()
			p1 = pg.p1
			_teleport(p1, _at(r, -4.0, 6.5))
			p1.reset_charge()
			await _ticks(2)
			var door_prev := 0.0
			for t in int(3.0 / TICK):
				p1.input_vec = dir
				p1.request_dash()
				door_prev = r.door().open_frac()
				await get_tree().physics_frame
				var c := p1.centre_of_mass()
				var c2 := Vector2(c.x, c.y)
				if pg.current != i:
					if door_prev > 0.3:
						legit += 1   # дверь была открыта (задел рычаг / плиту) — честный выход
					else:
						escaped = "комната сменилась при закрытой двери (направление %d°)" % roundi(rad_to_deg(ang))
					break
				if not inner.has_point(c2):
					var out := maxf(maxf(inner.position.x - c2.x, c2.x - inner.end.x), maxf(inner.position.y - c2.y, c2.y - inner.end.y))
					max_out = maxf(max_out, out)
					if escaped == "" and r.door().open_frac() < 0.3:
						escaped = "направление %d°: ЦМ (%.2f, %.2f)" % [roundi(rad_to_deg(ang)), c.x - r.global_position.x, c.y]
			p1.input_vec = Vector2.ZERO
		worst["room%d" % (i + 1)] = {"out_m": snappedf(max_out, 0.01), "legit_exits": legit}
		_check("bounds_room%d" % (i + 1), escaped == "", "не вылетела в обход (8 направлений × 3 с с ускорением)%s%s" % [
			"" if legit == 0 else "; честных выходов через открытую дверь %d" % legit, "" if escaped == "" else ": " + escaped])
	info["bounds"] = worst
