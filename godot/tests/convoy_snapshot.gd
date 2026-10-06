## Снимки пробы «Перегон: машина» (docs/plan-demo/CONVOY.md; нужно окно, без кражи фокуса):
##   godot/tools/godot_nofocus.sh --path godot --resolution 1600x900 --fixed-fps 60 res://tests/convoy_snapshot.tscn -- "out_dir=/abs/dir"
## Кадры (shots=1+2+3+4+5, по умолчанию все):
##   1 start  — старт: машина с грузом, P1 у двери (подпись «F — сесть»), P2 рядом, HUD;
##   2 bumps  — P1 за рулём на поле кочек на полном газу, груз подпрыгивает;
##   3 hill   — подъём: P1 жмёт газ, P2 толкает машину в задний борт;
##   4 plank  — машина стоит перед провалом, P2 несёт доску со стеллажа над провалом;
##   5 finish — табличка «ДОЕХАЛИ» (время и груз).
## Глазами проверить: машина и колёса читаются, голова водителя за стеклом, груз в кузове виден (ближний борт низкий), таблички
## участка, стеллаж с досками, HUD (участок, время, «В КУЗОВЕ N / M», скорость, памятка клавиш).
extends Node

const PLAYGROUND := "res://scenes/playground_convoy.tscn"
const BUILDER := preload("res://tools/build_convoy_probe.gd")
const TICK := 1.0 / 60.0

var out_dir := "/tmp"
var shots := "1+2+3+4+5"
var pg: ConvoyPlayground


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for part in String(arg).split(","):
			var kv := part.split("=")
			if kv.size() != 2:
				continue
			match kv[0]:
				"out_dir": out_dir = kv[1]
				"shots": shots = kv[1]
	_run.call_deferred()


func _shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name_]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("shot → ", path)


func _wait(s: float) -> void:
	for i in int(ceil(s / TICK)):
		await get_tree().physics_frame


func _want(n: int) -> bool:
	return str(n) in shots.split("+")


func _hill_x1() -> float:
	return BUILDER.HILL_X0 + BUILDER.HILL_H / tan(deg_to_rad(BUILDER.HILL_DEG))


## Кукла P2 держится за задним бортом и толкает по ходу машины (push) или просто следует.
func _pusher(d: Doll, push: bool) -> void:
	var xf := pg.car.chassis.global_transform
	var slot := xf * Vector3(ConvoyCar.BED_X0 - 0.5, 0.6, 0.0)
	var c := d.centre_of_mass()
	var to := Vector2(slot.x - c.x, slot.y - c.y)
	var fwd := Vector2(xf.basis.x.x, xf.basis.x.y)
	var v := to * 1.5
	if push and to.length() < 1.2:
		v += fwd * 1.2
	d.input_vec = v.limit_length(1.0)


func _car_to(x: float, ground: float) -> void:
	pg.car.reset_state()
	pg.car.place(Vector3(x, ground + Tuning.CONVOY_WHEEL_RADIUS + 0.12, 0.0))
	pg.load_cargo()


func _run() -> void:
	pg = (load(PLAYGROUND) as PackedScene).instantiate() as ConvoyPlayground
	pg.p2_on_start = true
	pg.auto_join = false
	add_child(pg)
	await _wait(0.5)
	for d in pg.players():
		(d as Doll).external_input = true
	var p1 := pg.p1
	var p2 := pg.p2
	if _want(1):
		pg.teleport(p1, pg.car.door_global() + Vector3(0.0, 0.75, 0.0))
		pg.teleport(p2, pg.car.chassis.global_position + Vector3(-4.0, 0.9, 0.0))
		pg.cam.snap()
		await _wait(1.6)
		await _shot("01_start")
	# P1 — за руль
	pg.teleport(p1, pg.car.door_global() + Vector3(0.0, 0.75, 0.0))
	await _wait(0.2)
	pg.car.enter(p1)
	pg.car.external_control = true
	pg.hud.refresh_help()
	if _want(2):
		pg.restart()
		pg.teleport(p1, pg.car.door_global() + Vector3(0.0, 0.75, 0.0))
		await _wait(0.2)
		pg.car.enter(p1)
		pg.car.external_control = true
		pg.hud.refresh_help()
		pg.car.handbrake = false
		pg.car.throttle = 1.0
		for i in int(14.0 / TICK):
			_pusher(p2, false)
			await get_tree().physics_frame
			if pg.car.centre_of_mass(false).x > BUILDER.BUMPS_X0 + 9.5:
				break
		await _shot("02_bumps")
		pg.car.throttle = 0.0
		pg.car.handbrake = true
		await _wait(1.0)
	if _want(3):
		_car_to(BUILDER.HILL_X0 - 3.0, 0.0)
		pg.teleport(p2, pg.car.chassis.global_position + Vector3(-3.5, 0.2, 0.0))
		pg.cam.snap()
		await _wait(1.0)
		pg.car.handbrake = false
		pg.car.throttle = 1.0
		for i in int(14.0 / TICK):
			_pusher(p2, true)
			await get_tree().physics_frame
			if pg.car.centre_of_mass(false).y > 3.4:
				break
		await _shot("03_hill")
		pg.car.throttle = 0.0
		pg.car.handbrake = true
		p2.input_vec = Vector2.ZERO
		await _wait(0.5)
	if _want(4):
		await _plank_shot(p2)
	if _want(5):
		_car_to(BUILDER.FINISH_X + 0.5, 0.0)
		pg.teleport(p2, pg.car.chassis.global_position + Vector3(-3.8, 0.6, 0.0))
		pg.cam.snap()
		await _wait(0.8)
		pg.time_s = 83.4
		pg.done = true
		pg.delivered = 4
		pg.finished.emit(83.4, 4, pg.cargo.size())
		await _wait(0.6)
		await _shot("05_finish")
	get_tree().quit(0)


## Машина перед провалом, P2 вытягивает доску со стеллажа (за правый конец) и несёт над провалом.
func _plank_shot(d: Doll) -> void:
	_car_to(BUILDER.PIT_X0 - 4.2, BUILDER.HILL_H)
	var p: ConvoyCargo = pg.planks[0]
	var end_x := p.global_position.x + p.size.x * 0.5
	pg.teleport(d, Vector3(end_x + 0.55, p.global_position.y - 1.25, 0.0))
	pg.cam.snap()
	await _wait(0.8)
	var arm := ConvoyPlayground._arm(d)
	for i in 90:
		arm.set_target_override(arm.closest_point(p, arm.grip_global()))
		await get_tree().physics_frame
		if arm.find_candidate() == p:
			break
	arm.press_grab()
	await _wait(0.1)
	var cx: float = (BUILDER.PIT_X0 + BUILDER.PIT_X1) * 0.5
	var bracket_r := BUILDER.SHELF_X1 - BUILDER.SHELF_OVERHANG - ((BUILDER.SHELF_X1 - BUILDER.SHELF_X0 - p.size.x) * 0.5)
	var y_carry := p.global_position.y - 0.25
	var y_under := BUILDER.HILL_H + BUILDER.SHELF_UP - 1.3
	var phase := 0
	for i in int(16.0 / TICK):
		var c := d.centre_of_mass()
		var pp := p.global_position
		var off := Vector2(c.x - pp.x, c.y - pp.y)
		arm.set_target_override(arm.root_point() + Vector3(-0.45, 0.05, 0.0))
		var g := Vector2.ZERO
		match phase:
			0:
				g = Vector2(bracket_r + p.size.x * 0.5 + 0.3 + off.x, y_carry)
				if pp.x - p.size.x * 0.5 > bracket_r + 0.1:
					phase = 1
			1:
				g = Vector2(c.x, y_under)
				if c.y < y_under + 0.15:
					phase = 2
			2:
				g = Vector2(cx + off.x, y_under)
				if absf(pp.x - cx) < 0.6:
					break
		var to := Vector2(g.x - c.x, g.y - c.y)
		d.input_vec = Vector2(clampf(to.x * 1.2, -0.4, 0.4), clampf(to.y * 1.2 + 0.17, -0.1, 0.6))
		await get_tree().physics_frame
	await _shot("04_plank")
	d.input_vec = Vector2.ZERO
