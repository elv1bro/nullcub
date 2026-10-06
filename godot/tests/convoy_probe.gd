## Проба «Перегон: машина» (docs/plan-demo/CONVOY.md; scripts/convoy/, scenes/convoy/, scenes/playground_convoy.tscn).
## Секции (only=car|cargo|course, несколько — через «+», пусто — все):
##   car    — своя ровная дорога: на ручнике стоит и не ползёт (на ровном и на склоне 22°); разгон 50 м (время, наибольшая скорость);
##            ручник на скорости; задний ход; колёса на осях (нет NaN, отклонение оси, ход подвески) на скорости, на кочках и при
##            падении с 3.5 м; наклон W / S в воздухе крутит кузов; сесть / выйти (кукла в кабине без коллизий, не дёргает машину,
##            голова за стеклом не отстаёт; вышла — снова летает; далеко от двери — не садится); переворот → кран ставит на колёса;
##   cargo  — груз в кузове: на ровном на полной скорости и при торможении ручником не вылетает; на кочках на полной скорости часть
##            вылетает (на малом газу — для сведения); рука хватает выпавший ящик и кладёт обратно в кузов;
##   course — настоящая площадка: подъём без толкания (с места, с короткого разгона), с толканием одной и двух кукол; доска со
##            стеллажа рукой — поперёк провала; провал без доски — машина падает и возвращается на старт; с доской — проезжает;
##            весь участок сценарным вводом (водитель + две куклы толкают на подъёме, доска рукой) — время и сколько груза довезли.
## Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/convoy_probe.tscn -- "only=car,out=<json>"
## → JSON между === CONVOY PROBE === и === OK / FAIL ===, exit 0/1. errors_script — SCRIPT ERROR за прогон (Logger).
extends Node

const PLAYGROUND := "res://scenes/playground_convoy.tscn"
const BUILDER := preload("res://tools/build_convoy_probe.gd")
const TICK := 1.0 / 60.0
## Весь участок сценарным вводом — не дольше (с).
const COURSE_MAX_S := 150.0
## Тяга вверх, которой кукла «висит» (вес 40 кг × g 2 = 80 Н из 480): добавка к рулению у цели.
const HOVER := Vector2(0.0, 0.17)

## Счётчик SCRIPT ERROR за прогон (как squad_probe, puzzle_probe).
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
var pg: ConvoyPlayground
var trace := false


func _check(id: String, cond: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": cond, "detail": str(detail)})
	if not cond:
		ok = false
	print("  %-38s %s  %s" % [id, "ok  " if cond else "FAIL", str(detail)])


func _args() -> Dictionary:
	var out := {"only": "", "out": "", "trace": "0"}
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
	print("=== CONVOY PROBE ===")
	var a := _args()
	trace = String(a["trace"]) == "1"
	if _want(a, "car"):
		await _sec_car()
	if _want(a, "cargo"):
		await _sec_cargo()
	if _want(a, "course"):
		await _sec_course()
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


## Мир: ровный пол от x0 до x1 (верх y = 0), стена слева; bumps — поле кочек участка (BUILDER.BUMPS), сдвинутое на bump_dx.
func _new_world(x0 := -20.0, x1 := 260.0, bumps := false, bump_dx := 0.0) -> Node3D:
	_clear_world()
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	var st := StaticBody3D.new()
	st.name = "Floor"
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	st.physics_material_override = pm
	world.add_child(st)
	ConvoyGeo.shape_xy(st, "Floor", x0, x1, -1.0, 0.0, 4.0)
	ConvoyGeo.shape_xy(st, "WallL", x0 - 1.0, x0, -1.0, 8.0, 4.0)
	if bumps:
		for i in BUILDER.BUMPS.size():
			var b: Array = BUILDER.BUMPS[i]
			var h: float = b[1]
			var w: float = b[2]
			var r := (w * w + h * h) / (2.0 * h)
			ConvoyGeo.disc_shape(st, "Bump%d" % i, r, 4.0, Vector3(float(b[0]) + bump_dx, h - r, 0.0))
	return world


## Мир со склоном deg от x = 0 (низ) до x = run, дальше — площадка.
func _slope_world(deg: float, run := 30.0) -> Node3D:
	_new_world()
	var st := world.get_node("Floor") as StaticBody3D
	var h := run * tan(deg_to_rad(deg))
	var pts := PackedVector3Array()
	for z in [-2.0, 2.0]:
		pts.append(Vector3(0.0, 0.0, z))
		pts.append(Vector3(run, h, z))
		pts.append(Vector3(run, 0.0, z))
	var cs := CollisionShape3D.new()
	cs.name = "Slope"
	var sh := ConvexPolygonShape3D.new()
	sh.points = pts
	cs.shape = sh
	st.add_child(cs)
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


## Машина на ровной дороге: начало кузова в x, колёса на земле (y земли — ground). Ввод — пробой (external_control).
func _spawn_car(x := 0.0, ground := 0.0) -> ConvoyCar:
	var c := ConvoyCar.new()
	c.name = "Car"
	c.position = Vector3(x, ground + Tuning.CONVOY_WHEEL_RADIUS + 0.1, 0.0)
	world.add_child(c)
	c.external_control = true
	return c


## Груз из Tuning.CONVOY_CARGO — в кузов машины.
func _load(car: ConvoyCar) -> Array:
	var items: Array = []
	for i in Tuning.CONVOY_CARGO.size():
		var e: Array = Tuning.CONVOY_CARGO[i]
		var c := ConvoyCargo.new()
		c.name = "Cargo%d" % i
		c.kind = String(e[0])
		c.cargo_mass = float(e[1])
		world.add_child(c)
		items.append(c)
	car.load_cargo(items)
	return items


func _in_bed(car: ConvoyCar, items: Array) -> int:
	var n := 0
	for c in items:
		if car.in_bed(c):
			n += 1
	return n


## Кукла «Человек» (как у игроков), ввод — скриптом.
func _doll(i: int, pos: Vector3, parent: Node = null, arm := true) -> Doll:
	var d := ConvoyPlayground.make_player(i)
	d.external_input = true
	d.position = pos
	(parent if parent != null else world).add_child(d)
	if arm:
		ArmAssist.attach_to(d)
	return d


static func _arm(d: Doll) -> ArmAssist:
	return ConvoyPlayground._arm(d)


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


## Рулить куклой к точке (input_vec, полная тяга); true — дошла (ближе reach_m) за max_s.
func _steer_to(d: Doll, p: Vector2, max_s: float, reach_m := 0.5) -> bool:
	for i in int(max_s / TICK):
		var c := d.centre_of_mass()
		var to := Vector2(p.x - c.x, p.y - c.y)
		if to.length() < reach_m:
			d.input_vec = Vector2.ZERO
			return true
		d.input_vec = (to * 2.5 + HOVER).limit_length(1.0)
		await get_tree().physics_frame
	d.input_vec = Vector2.ZERO
	return false


## Толкающая кукла: k-е место за задним бортом (на высоте рамы, k = 1 — за первой куклой). push — жать по ходу машины, иначе только
## держаться за ней (следовать).
func _pusher_tick(d: Doll, car: ConvoyCar, k: int, push: bool) -> void:
	var xf := car.chassis.global_transform
	var slot := xf * Vector3(ConvoyCar.BED_X0 - 0.5 - 0.75 * k, 0.6, 0.0)
	var c := d.centre_of_mass()
	var to := Vector2(slot.x - c.x, slot.y - c.y)
	var fwd := Vector2(xf.basis.x.x, xf.basis.x.y)
	var v := to * 1.5
	if push and to.length() < 1.2:
		v += fwd * 1.2
	d.input_vec = v.limit_length(1.0)


func _f(v: float) -> float:
	return snappedf(v, 0.01)


func _hill_x1() -> float:
	return BUILDER.HILL_X0 + BUILDER.HILL_H / tan(deg_to_rad(BUILDER.HILL_DEG))


# ------------------------------------------------------------------ car

func _sec_car() -> void:
	print("--- car")
	_new_world()
	var car := _spawn_car(0.0)
	car.handbrake = true
	await _wait(1.5)
	var x0 := car.chassis.global_position.x
	var y0 := car.chassis.global_position.y
	await _wait(5.0)
	var creep := absf(car.chassis.global_position.x - x0)
	_check("park_flat", creep < 0.02 and car.axles_ok(), "за 5 с на ручнике сдвиг %.3f м; ось кузова на y %.2f; пружины %s Н" % [creep, y0, str(car.spring_f.map(func(f: float) -> float: return roundf(f)))])
	info["chassis_rest_y"] = _f(y0)
	# разгон по ровному: 50 м с места
	car.handbrake = false
	car.throttle = 1.0
	var t := 0.0
	var vmax := 0.0
	var axles := true
	var start := car.chassis.global_position.x
	var t50 := -1.0
	while t < 20.0:
		await get_tree().physics_frame
		t += TICK
		vmax = maxf(vmax, car.speed())
		if not car.axles_ok():
			axles = false
		if t50 < 0.0 and car.chassis.global_position.x - start >= 50.0:
			t50 = t
			break
	info["flat_50m_s"] = _f(t50)
	info["flat_vmax"] = _f(vmax)
	_check("drive_forward", t50 > 0.0 and t50 < 12.0, "50 м с места за %.2f с, наибольшая скорость %.2f м/с" % [t50, vmax])
	_check("axles_flat", axles and car.max_axle_error < 0.05, "колёса на осях: %s, наибольшее отклонение оси %.3f м" % [str(axles), car.max_axle_error])
	# ручник на полной скорости: тормозной путь
	var xb := car.chassis.global_position.x
	var vb := car.speed()
	car.throttle = 0.0
	car.handbrake = true
	await _wait(4.0)
	var brake_m := car.chassis.global_position.x - xb
	info["brake_from_v"] = _f(vb)
	info["brake_m"] = _f(brake_m)
	_check("brake", absf(car.speed()) < 0.1 and brake_m < 12.0 and car.axles_ok(), "с %.1f м/с ручник: путь %.2f м, скорость после %.2f" % [vb, brake_m, car.speed()])
	# задний ход
	car.handbrake = false
	car.throttle = -1.0
	var xr := car.chassis.global_position.x
	await _wait(4.0)
	var vr := car.speed()
	_check("reverse", car.chassis.global_position.x < xr - 3.0 and vr > -Tuning.CONVOY_REVERSE_SPEED - 0.3, "назад за 4 с %.2f м, скорость %.2f м/с" % [car.chassis.global_position.x - xr, vr])
	car.throttle = 0.0
	car.handbrake = true
	await _wait(1.0)
	await _car_slope()
	await _car_bumps()
	await _car_drop_tilt()
	await _car_seat()
	await _car_flip()


## На ручнике на склоне 22° (как подъём участка): не ползёт.
func _car_slope() -> void:
	var deg: float = BUILDER.HILL_DEG
	_slope_world(deg)
	var car := _spawn_car(0.0)
	var a := deg_to_rad(deg)
	var x := 12.0
	var gy := x * tan(a)
	var n := Vector2(-sin(a), cos(a))
	var lift := Tuning.CONVOY_WHEEL_RADIUS + 0.12
	car.place(Vector3(x + n.x * lift, gy + n.y * lift, 0.0), a)
	car.handbrake = true
	await _wait(2.0)
	var p0 := car.chassis.global_position
	await _wait(5.0)
	var d := car.chassis.global_position.distance_to(p0)
	info["park_slope_creep_m"] = _f(d)
	_check("park_slope", d < 0.05 and car.axles_ok(), "склон %.0f°, ручник: за 5 с сдвиг %.3f м" % [deg, d])
	# мотор один на этом склоне с места
	car.handbrake = false
	car.throttle = 1.0
	var px := car.chassis.global_position.x
	await _wait(4.0)
	info["slope_motor_dx_4s"] = _f(car.chassis.global_position.x - px)
	car.throttle = 0.0
	car.handbrake = true


## Поле кочек участка на полной скорости: колёса на осях, нет NaN, колёса не разгоняются в разнос.
func _car_bumps() -> void:
	_new_world(-20.0, 200.0, true, 0.0)
	var car := _spawn_car(2.0)
	await _wait(1.0)
	car.handbrake = false
	car.throttle = 1.0
	var axles := true
	var nan := false
	var wmax := 0.0
	var air := 0
	var vmax_bumps := 0.0
	var tilt_max := 0.0
	for i in int(14.0 / TICK):
		await get_tree().physics_frame
		if not car.axles_ok():
			axles = false
		var p := car.chassis.global_position
		if is_nan(p.x) or is_nan(p.y):
			nan = true
			break
		for w in car.wheels:
			wmax = maxf(wmax, absf(w.angular_velocity.z))
		var cx := car.centre_of_mass(false).x
		if cx > BUILDER.BUMPS_X0 and cx < BUILDER.BUMPS_X1:
			vmax_bumps = maxf(vmax_bumps, car.speed())
			if car.grounded == 0:
				air += 1
			tilt_max = maxf(tilt_max, absf(car.angle()))
		if cx > BUILDER.BUMPS_X1 + 10.0:
			break
	info["bumps_vmax"] = _f(vmax_bumps)
	info["bumps_air_s"] = _f(air * TICK)
	info["bumps_tilt_max_deg"] = _f(rad_to_deg(tilt_max))
	info["bumps_axle_error_max"] = _f(car.max_axle_error)
	var vlim := Tuning.CONVOY_MAX_SPEED / Tuning.CONVOY_WHEEL_RADIUS * 1.6
	_check("axles_bumps", axles and not nan and car.max_axle_error < 0.12 and wmax < vlim,
		"кочки на полной: оси целы %s, NaN %s, отклонение оси %.3f м, колесо до %.1f рад/с (предел %.1f), в воздухе %.2f с, крен до %.0f°" % [
			str(axles), str(nan), car.max_axle_error, wmax, vlim, air * TICK, rad_to_deg(tilt_max)])


## Падение с 3.5 м: колёса на осях, встала на колёса; наклон W / S в воздухе крутит кузов.
func _car_drop_tilt() -> void:
	_new_world()
	var car := _spawn_car(0.0)
	car.place(Vector3(0.0, 4.1, 0.0))
	var axles := true
	for i in int(3.0 / TICK):
		await get_tree().physics_frame
		if not car.axles_ok():
			axles = false
	_check("drop_3m", axles and car.grounded == 3 and car.chassis.global_basis.y.y > 0.95, "упала с 3.5 м: оси целы %s, колёс на земле %d, верх кузова y %.2f" % [str(axles), car.grounded, car.chassis.global_basis.y.y])
	car.place(Vector3(0.0, 12.0, 0.0))
	await _ticks(2)
	car.tilt = 1.0
	await _wait(0.4)
	var w_up := car.chassis.angular_velocity.z
	car.tilt = -1.0
	await _wait(0.8)
	var w_dn := car.chassis.angular_velocity.z
	car.tilt = 0.0
	_check("air_tilt", w_up > 0.5 and w_dn < -0.5, "в воздухе W: ω %.2f рад/с (нос вверх), S: ω %.2f" % [w_up, w_dn])
	await _wait(3.0)


## Сесть / выйти: кукла у двери садится, в кабине без коллизий и не дёргает машину, голова не отстаёт на ходу; вышла — летает.
func _car_seat() -> void:
	_new_world()
	var car := _spawn_car(0.0)
	await _wait(1.0)
	var d := _doll(0, Vector3(-6.0, 1.0, 0.0))
	await _wait(1.0)
	_check("enter_far", not car.can_enter(d) and not car.enter(d), "кукла в %.1f м от двери не садится" % d.centre_of_mass().distance_to(car.door_global()))
	_teleport(d, car.door_global() + Vector3(0.0, 1.85, 0.0))   # над крышей кабины, в круге посадки
	await _wait(1.0)
	var p0 := car.chassis.global_position
	var entered := car.enter(d)
	var frozen := true
	var nocoll := true
	for p in d.parts.values():
		var b := p as RigidBody3D
		if not b.freeze:
			frozen = false
		if b.collision_layer != 0 or b.collision_mask != 0:
			nocoll = false
	var wmax := 0.0
	for i in int(1.0 / TICK):
		await get_tree().physics_frame
		wmax = maxf(wmax, absf(car.chassis.angular_velocity.z))
	var moved := car.chassis.global_position.distance_to(p0)
	_check("enter", entered and car.driver == d and not d.control_enabled and frozen and nocoll and d.head().visible and not d.torso().visible,
		"села: %s, управление куклы выкл %s, детали заморожены %s, без коллизий %s, видна голова %s" % [str(entered), str(not d.control_enabled), str(frozen), str(nocoll), str(d.head().visible)])
	_check("seated_still", moved < 0.01 and wmax < 0.02, "машина на ручнике с водителем: сдвиг %.4f м, |ω| до %.4f рад/с" % [moved, wmax])
	# на ходу голова за стеклом: от места водителя (по кузову, интерполяция не в счёт) — не дальше 0.05 м
	car.handbrake = false
	car.throttle = 1.0
	var lag := 0.0
	for i in int(4.0 / TICK):
		await get_tree().physics_frame
		var seat := car.chassis.global_transform * ConvoyCar.SEAT_HEAD_LOCAL
		lag = maxf(lag, d.head().global_position.distance_to(seat))
	info["seat_head_lag_m"] = _f(lag)
	_check("seat_follow", lag < 0.2, "4 с газа до %.1f м/с: голова от места водителя до %.3f м" % [car.speed(), lag])
	car.throttle = 0.0
	car.handbrake = true
	await _wait(2.5)
	var out := car.exit_driver()
	await _ticks(2)
	var free := true
	for p in d.parts.values():
		var b := p as RigidBody3D
		if b.freeze or b.collision_layer == 0 or not b.visible:
			free = false
	var c0 := d.centre_of_mass()
	d.input_vec = Vector2(0.0, 1.0)
	await _wait(1.0)
	d.input_vec = Vector2.ZERO
	var rise := d.centre_of_mass().y - c0.y
	_check("exit", out == d and car.driver == null and d.control_enabled and free and rise > 0.5 and c0.y > car.chassis.global_position.y + 1.5,
		"вышла над кабиной (ЦМ на %.2f м выше оси), детали свободны %s, за 1 с вверх на %.2f м" % [c0.y - car.chassis.global_position.y, str(free), rise])
	d.queue_free()
	await _ticks(2)


## Переворот: машина вверх колёсами — через UPRIGHT_S кран ставит её на колёса.
func _car_flip() -> void:
	_new_world()
	var car := _spawn_car(0.0)
	car.place(Vector3(0.0, 2.3, 0.0), PI)
	var t := 0.0
	var done_t := -1.0
	var was_crane := false
	while t < 14.0:
		await get_tree().physics_frame
		t += TICK
		if car.crane_t >= 0.0:
			was_crane = true
		if was_crane and car.crane_t < 0.0 and car.chassis.global_basis.y.y > 0.9 and car.grounded >= 2 and car.chassis.linear_velocity.length() < 0.3:
			done_t = t
			break
	info["upright_s"] = _f(done_t)
	_check("flip_upright", done_t > 0.0 and car.axles_ok() and car.teleport_upright_count == 0,
		"вверх колёсами → на колёсах через %.2f с (кран %d раз, перенос %d), оси целы %s" % [done_t, car.crane_count, car.teleport_upright_count, str(car.axles_ok())])


# ------------------------------------------------------------------ cargo

func _sec_cargo() -> void:
	print("--- cargo")
	# ровно: разгон до полной, 60 м, ручник — груз на месте
	_new_world()
	var car := _spawn_car(0.0)
	await _wait(0.5)
	var items := _load(car)
	await _wait(1.5)
	var n0 := _in_bed(car, items)
	car.handbrake = false
	car.throttle = 1.0
	var vmax := 0.0
	var min_n := n0
	for i in int(15.0 / TICK):
		await get_tree().physics_frame
		vmax = maxf(vmax, car.speed())
		min_n = mini(min_n, _in_bed(car, items))
		if car.chassis.global_position.x > 60.0:
			break
	car.throttle = 0.0
	car.handbrake = true
	for i in int(4.0 / TICK):
		await get_tree().physics_frame
		min_n = mini(min_n, _in_bed(car, items))
	info["cargo_flat_vmax"] = _f(vmax)
	_check("cargo_flat", n0 == items.size() and min_n == items.size(), "ровно до %.1f м/с и ручник с полной: в кузове %d из %d (меньше всего %d)" % [vmax, _in_bed(car, items), items.size(), min_n])
	# кочки на полной — часть вылетает; на малом газу — для сведения
	var full := await _cargo_bumps(1.0)
	var soft := await _cargo_bumps(0.3)
	info["cargo_bumps_full"] = full
	info["cargo_bumps_soft"] = soft
	_check("cargo_bumps", int(full["left"]) < Tuning.CONVOY_CARGO.size() and int(full["left"]) >= 1,
		"кочки на полном газу (до %.1f м/с): в кузове осталось %d из %d; на газу 0.3 (до %.1f м/с): %d" % [
			float(full["vmax"]), int(full["left"]), Tuning.CONVOY_CARGO.size(), float(soft["vmax"]), int(soft["left"])])
	await _cargo_arm()


## Через поле кочек с газом throttle (разгон 20 м до первой кочки, как на участке): {left, vmax}.
func _cargo_bumps(throttle: float) -> Dictionary:
	_new_world(-20.0, 200.0, true, 0.0)
	var car := _spawn_car(BUILDER.BUMPS_X0 - 20.0)   # как на участке: 20 м ровного до первой кочки
	await _wait(0.5)
	var items := _load(car)
	await _wait(1.0)
	car.handbrake = false
	car.throttle = throttle
	var vmax := 0.0
	for i in int(25.0 / TICK):
		await get_tree().physics_frame
		vmax = maxf(vmax, car.speed())
		if car.centre_of_mass(false).x > BUILDER.BUMPS_X1 + 4.0:
			break
	car.throttle = 0.0
	car.handbrake = true
	await _wait(2.5)
	return {"left": _in_bed(car, items), "vmax": _f(vmax)}


## Рука: ящик выпал за машиной — кукла хватает его и кладёт обратно в кузов.
func _cargo_arm() -> void:
	_new_world()
	var car := _spawn_car(0.0)
	await _wait(0.5)
	var items := _load(car)
	await _wait(1.0)
	var crate: ConvoyCargo = null
	for c in items:
		if (c as ConvoyCargo).kind == "crate":
			crate = c
			break
	crate.global_transform = Transform3D(Basis(), Vector3(-5.0, crate.size.y * 0.5 + 0.01, 0.0))
	crate.linear_velocity = Vector3.ZERO
	await _wait(1.0)
	var before := _in_bed(car, items)
	var d := _doll(0, Vector3(-4.1, 1.2, 0.0))   # ящик слева от куклы — со стороны руки-хвата (правая рука, на экране слева)
	await _wait(0.8)
	var arm := _arm(d)
	var held := await _grab_with(arm, crate)
	if not held:
		print("    рука: хват %s, до ящика %.2f м, кандидат %s" % [str(arm.grip_global()), arm.grip_global().distance_to(crate.global_position), str(arm.find_candidate())])
	# держим перед собой и летим над кузовом
	var bed := car.chassis.global_transform * Vector3((ConvoyCar.BED_X0 + ConvoyCar.BED_X1) * 0.5 - 0.3, 2.3, 0.0)
	var flew := false
	for i in int(6.0 / TICK):
		arm.set_target_override(arm.root_point() + Vector3(0.0, -0.5, 0.0))
		var c := d.centre_of_mass()
		var to := Vector2(bed.x - c.x, bed.y + 0.6 - c.y)
		if to.length() < 0.35:
			flew = true
			d.input_vec = Vector2.ZERO
			break
		d.input_vec = (to * 0.8).limit_length(1.0)
		await get_tree().physics_frame
	d.input_vec = Vector2.ZERO
	await _wait(0.4)
	arm.clear_target_override()
	await _ticks(1)
	arm.press_grab()   # рука не активна — просто отпустить
	await _wait(2.0)
	var after := _in_bed(car, items)
	var lc := car.chassis.global_transform.affine_inverse() * crate.global_position
	info["cargo_arm_crate_local"] = [_f(lc.x), _f(lc.y)]
	_check("cargo_arm", held and flew and car.in_bed(crate) and after == before + 1,
		"ящик с земли: схватила %s, долетела над кузовом %s, в кузове %d → %d" % [str(held), str(flew), before, after])
	d.queue_free()
	await _ticks(2)


# ------------------------------------------------------------------ course

func _load_playground() -> void:
	_clear_world()
	await _unload()
	pg = (load(PLAYGROUND) as PackedScene).instantiate() as ConvoyPlayground
	pg.spawn_players = false
	pg.auto_join = false
	add_child(pg)
	await _wait(0.5)
	pg.car.external_control = true


## Машина на дороге в точке x (ЦМ по x) с грузом в кузове, на ручнике; ground — высота дороги.
func _car_at(x: float, ground: float) -> void:
	pg.car.reset_state()
	pg.car.place(Vector3(x, ground + Tuning.CONVOY_WHEEL_RADIUS + 0.12, 0.0))
	pg.load_cargo()
	pg.pit_t = 0.0
	pg.car.external_control = true
	pg.car.handbrake = true
	await _wait(1.2)


func _pushers(n: int, near: Vector3) -> Array:
	var out: Array = []
	for i in n:
		var d := _doll(i, near + Vector3(-4.5 - 1.2 * i, 1.3, 0.0), pg.get_node("Dolls"), true)
		pg.match_node.register(d)
		out.append(d)
	await _wait(0.6)
	return out


func _drop_dolls(list: Array) -> void:
	for d in list:
		if is_instance_valid(d):
			(d as Node).queue_free()
	await _ticks(2)


## Подъём: машина у подножья (ЦМ на x0), газ до упора; pushers толкают. → {top: заехала, t, x_max, y_max}.
func _climb(x0: float, n_push: int, max_s: float) -> Dictionary:
	await _car_at(x0, 0.0)
	var car := pg.car
	var dolls: Array = await _pushers(n_push, car.chassis.global_position)
	for i in int(1.5 / TICK):
		for k in dolls.size():
			_pusher_tick(dolls[k], car, k, false)
		await get_tree().physics_frame
	car.handbrake = false
	car.throttle = 1.0
	var top := _hill_x1() + 1.0
	var t := 0.0
	var x_max := -INF
	var y_max := -INF
	var reached := false
	while t < max_s:
		for k in dolls.size():
			_pusher_tick(dolls[k], car, k, true)
		await get_tree().physics_frame
		t += TICK
		var c := car.centre_of_mass(false)
		x_max = maxf(x_max, c.x)
		y_max = maxf(y_max, c.y)
		if c.x > top and c.y > BUILDER.HILL_H:
			reached = true
			break
	car.throttle = 0.0
	car.handbrake = true
	for d in dolls:
		(d as Doll).input_vec = Vector2.ZERO
	await _drop_dolls(dolls)
	return {"top": reached, "t": _f(t), "x_max": _f(x_max), "y_max": _f(y_max)}


func _sec_course() -> void:
	print("--- course")
	await _load_playground()
	var x0: float = BUILDER.HILL_X0 - 3.0
	var none := await _climb(x0, 0, 14.0)
	var runup := await _climb(BUILDER.BUMPS_X1 + 0.6, 0, 14.0)
	var one := await _climb(x0, 1, 30.0)
	var two := await _climb(x0, 2, 30.0)
	info["hill_none"] = none
	info["hill_runup_short"] = runup
	info["hill_push1"] = one
	info["hill_push2"] = two
	_check("hill_no_push", not bool(none["top"]), "подъём %.0f° с места без толкания: заехала %s (ЦМ до x %.1f, y %.1f)" % [BUILDER.HILL_DEG, str(none["top"]), float(none["x_max"]), float(none["y_max"])])
	_check("hill_push1", bool(one["top"]), "одна кукла толкает: заехала %s за %.1f с (ЦМ до x %.1f, y %.1f)" % [str(one["top"]), float(one["t"]), float(one["x_max"]), float(one["y_max"])])
	_check("hill_push2", bool(two["top"]) and float(two["t"]) <= float(one["t"]) + 0.5, "две куклы: заехала %s за %.1f с (одна — %.1f)" % [str(two["top"]), float(two["t"]), float(one["t"])])
	print("    для сведения: с разгона %.1f м без толкания — заехала %s (ЦМ до x %.1f, y %.1f)" % [BUILDER.HILL_X0 - BUILDER.BUMPS_X1 - 0.6, str(runup["top"]), float(runup["x_max"]), float(runup["y_max"])])
	await _pit_tests()
	await _full_run()


## Доска поперёк провала (центр по провалу, на дороге).
func _lay_plank(p: ConvoyCargo) -> void:
	var cx: float = (BUILDER.PIT_X0 + BUILDER.PIT_X1) * 0.5
	p.global_transform = Transform3D(Basis(), Vector3(cx, BUILDER.HILL_H + p.size.y * 0.5 + 0.01, 0.0))
	p.linear_velocity = Vector3.ZERO
	p.angular_velocity = Vector3.ZERO
	p.sleeping = false


## Нижняя свободная доска стеллажа (ярусы — снизу вверх; снизу рука достаёт нижнюю).
func _top_plank() -> ConvoyCargo:
	var best: ConvoyCargo = null
	for p in pg.planks:
		var c := p as ConvoyCargo
		if c.bridged or c.global_position.y < BUILDER.HILL_H + 1.0:
			continue
		if best == null or c.global_position.y < best.global_position.y:
			best = c
	return best


## Доска со стеллажа рукой: кукла справа от стеллажа (рука-хват — на экране слева) берёт свисающий правый конец нижней доски,
## вытягивает её вправо с кронштейнов, опускает ниже стеллажа, несёт горизонтально (средний класс: рука держит угол; доска лёгкая),
## ставит серединой над провалом, опускает и отпускает — доска ложится поперёк, мост.
func _plank_by_hand(p: ConvoyCargo) -> Dictionary:
	var end_x := p.global_position.x + p.size.x * 0.5
	var d := _doll(0, Vector3(end_x + 1.5, p.global_position.y - 0.4, 0.0), pg.get_node("Dolls"), true)
	pg.match_node.register(d)
	await _wait(0.6)
	var arm := _arm(d)
	var r := {"held": false, "flew": false, "across": false}
	await _steer_to(d, Vector2(end_x + 0.55, p.global_position.y - 0.25), 4.0, 0.2)
	await _wait(0.3)
	r["held"] = await _grab_with(arm, p)
	r["grab_from_centre_m"] = _f(p.to_local(arm.grip_global()).x)
	if trace:
		print("    доска: хват %s, кисть (%.2f, %.2f), кукла (%.2f, %.2f), конец доски (%.2f, %.2f), кандидат %s, действие %s" % [str(r["held"]),
			arm.grip_global().x, arm.grip_global().y, d.centre_of_mass().x, d.centre_of_mass().y, end_x, p.global_position.y,
			str(arm.find_candidate()), arm.last_grab_action])
	var cx: float = (BUILDER.PIT_X0 + BUILDER.PIT_X1) * 0.5
	var bracket_r := BUILDER.SHELF_X1 - BUILDER.SHELF_OVERHANG - ((BUILDER.SHELF_X1 - BUILDER.SHELF_X0 - p.size.x) * 0.5)
	var y_carry := p.global_position.y - 0.25
	var y_under := BUILDER.HILL_H + BUILDER.SHELF_UP - 1.3   # ЦМ куклы с доской под нижним ярусом: голова (+0.65) ниже кронштейнов
	var phase := 0
	for i in int(20.0 / TICK):
		var c := d.centre_of_mass()
		var pp := p.global_position
		var off := Vector2(c.x - pp.x, c.y - pp.y)   # кукла относительно середины доски
		arm.set_target_override(arm.root_point() + Vector3(-0.45, 0.05, 0.0))
		var g := Vector2.ZERO
		match phase:
			0:   # вытянуть вправо, пока левый конец не сошёл с правого кронштейна
				g = Vector2(bracket_r + p.size.x * 0.5 + 0.3 + off.x, y_carry)
				if pp.x - p.size.x * 0.5 > bracket_r + 0.1:
					phase = 1
			1:   # опустить куклу ниже стеллажа (голова ниже кронштейнов нижнего яруса)
				g = Vector2(c.x, y_under)
				if c.y < y_under + 0.15:
					phase = 2
			2:   # на этой высоте (куклы, не доски) — влево, пока середина доски не над серединой провала
				g = Vector2(cx + off.x, y_under)
				if absf(pp.x - cx) < 0.2:
					phase = 3
			3:   # опустить медленно: середина доски на 0.45 м над дорогой
				g = Vector2(cx + off.x, BUILDER.HILL_H + 0.45 + off.y)
				if pp.y < BUILDER.HILL_H + 0.9 and absf(pp.x - cx) < 0.3 and absf(p.linear_velocity.x) < 0.3:
					r["flew"] = true
					break
		var to := Vector2(g.x - c.x, g.y - c.y)
		# по x и по y — раздельно (вертикаль не съедается общим пределом), вниз — медленно
		d.input_vec = Vector2(clampf(to.x * 1.2, -0.4, 0.4), clampf(to.y * 1.2 + HOVER.y, -0.1, 0.6))
		if trace and i % 15 == 0:
			print("    доска: фаза %d t=%.2f доска (%.2f, %.2f, %.0f°) кукла (%.2f, %.2f) в руке %s растяжение %.2f" % [phase, i * TICK,
				pp.x, pp.y, rad_to_deg(p.rotation.z), c.x, c.y, str(arm.held == p), arm.hold_distance()])
		await get_tree().physics_frame
	d.input_vec = Vector2.ZERO
	r["held_at_drop"] = arm.held == p
	arm.clear_target_override()
	await _ticks(1)
	arm.press_grab()
	await _wait(0.2)
	var away := d.centre_of_mass() + Vector3(0.6, 2.5, 0.0)   # от доски — вверх (кукла справа от её конца)
	await _steer_to(d, Vector2(away.x, away.y), 2.0)
	for i in int(5.0 / TICK):   # доска лёгкая (g × 0.5) — ложится не сразу
		if p.bridged:
			break
		await get_tree().physics_frame
	r["across"] = p.bridged or pg.plank_across(p)
	r["bridged"] = p.bridged
	r["plank"] = [_f(p.global_position.x), _f(p.global_position.y), _f(rad_to_deg(p.rotation.z))]
	await _drop_dolls([d])
	return r


func _pit_tests() -> void:
	var h1 := _hill_x1()
	var plank: ConvoyCargo = null
	# без доски: падает и возвращается на старт
	for p in pg.planks:
		(p as ConvoyCargo).go_home()
	await _car_at(h1 + 3.0, BUILDER.HILL_H)
	var resets0 := pg.resets
	pg.car.handbrake = false
	pg.car.throttle = 1.0
	var t := 0.0
	var fell := false
	while t < 10.0:
		await get_tree().physics_frame
		t += TICK
		if pg.resets > resets0:
			fell = true
			break
	pg.car.throttle = 0.0
	pg.car.handbrake = true
	await _wait(0.5)
	var back := pg.car.centre_of_mass(false).x < BUILDER.START_X + 3.0
	_check("pit_no_plank", fell and back, "без доски: упала в провал и вернулась на старт %s через %.1f с (ЦМ x %.1f)" % [str(fell), t, pg.car.centre_of_mass(false).x])
	# доска рукой со стеллажа
	await _wait(0.5)
	plank = _top_plank()
	var hand := await _plank_by_hand(plank)
	info["plank_by_hand"] = hand
	_check("plank_by_hand", bool(hand["held"]) and bool(hand["across"]),
		"доска рукой: схватила %s, донесла %s (в руке %s), легла поперёк мостом %s (x, y, угол: %s)" % [str(hand["held"]), str(hand["flew"]), str(hand.get("held_at_drop", false)), str(hand["across"]), str(hand["plank"])])
	# с доской: проезжает
	if not bool(hand["across"]):
		_lay_plank(plank)
		await _wait(1.0)
	await _car_at(h1 + 3.0, BUILDER.HILL_H)
	resets0 = pg.resets
	pg.car.handbrake = false
	pg.car.throttle = 1.0
	t = 0.0
	var crossed := false
	while t < 10.0:
		await get_tree().physics_frame
		t += TICK
		if pg.resets > resets0:
			break
		if pg.car.centre_of_mass(false).x > BUILDER.PIT_X1 + 3.0:
			crossed = true
			break
	pg.car.throttle = 0.0
	pg.car.handbrake = true
	_check("pit_plank", crossed and pg.resets == resets0 and pg.car.axles_ok() and plank.bridged, "с доской: проехала провал %s за %.1f с, сбросов %d, доска мостом %s (x %.1f y %.2f)" % [
		str(crossed), t, pg.resets - resets0, str(plank.bridged), plank.global_position.x, plank.global_position.y])
	await _wait(1.0)


## Весь участок: водитель — проба (газ, ручник у провала), две куклы следуют и толкают на подъёме, третья кукла кладёт доску рукой.
func _full_run() -> void:
	pg.restart()
	for p in pg.planks:
		(p as ConvoyCargo).go_home()
	await _wait(1.0)
	var car := pg.car
	car.external_control = true
	var dolls: Array = await _pushers(2, car.chassis.global_position)
	var h1 := _hill_x1()
	var stage := "drive"
	var t := 0.0
	var plank_r := {}
	var stop_x: float = BUILDER.PIT_X0 - 4.0   # нос машины в ~1.5 м от кромки: доске 5 м нужно 0.8 м дороги перед провалом
	car.handbrake = false
	car.throttle = 1.0
	while t < COURSE_MAX_S and not pg.done:
		var c := car.centre_of_mass(false)
		match stage:
			"drive":
				var push := c.x > BUILDER.HILL_X0 - 4.0
				for k in dolls.size():
					_pusher_tick(dolls[k], car, k, push)
				if c.x > h1 + 0.8 and c.y > BUILDER.HILL_H - 0.3:
					stage = "stop"
			"stop":
				for k in dolls.size():
					_pusher_tick(dolls[k], car, k, false)
				car.throttle = 0.6 if c.x < stop_x else 0.0
				car.handbrake = c.x >= stop_x
				if c.x >= stop_x and absf(car.speed()) < 0.1:
					stage = "plank"
			"plank":
				for d in dolls:
					(d as Doll).input_vec = Vector2.ZERO
				var top := _top_plank()
				plank_r = await _plank_by_hand(top)
				if not bool(plank_r["across"]):
					_lay_plank(top)
					await _wait(1.0)
				car.handbrake = false
				car.throttle = 1.0
				stage = "go"
			"go":
				for k in dolls.size():
					_pusher_tick(dolls[k], car, k, false)
				car.throttle = 0.55 if c.x > BUILDER.DESC_X0 else 1.0
		await get_tree().physics_frame
		t += TICK
	car.throttle = 0.0
	car.handbrake = true
	info["course_time_s"] = _f(pg.time_s)
	info["course_delivered"] = pg.delivered
	info["course_resets"] = pg.resets
	info["course_plank_by_hand"] = plank_r
	_check("course_full", pg.done and pg.time_s < COURSE_MAX_S,
		"весь участок сценарием: финиш %s за %.1f с (часы участка), груз довезли %d из %d, сбросов на старт %d, доска рукой поперёк %s" % [
			str(pg.done), pg.time_s, pg.delivered, pg.cargo.size(), pg.resets, str(plank_r.get("across", false))])
	await _drop_dolls(dolls)
