## Снимки демо «Головоломки вдвоём» (docs/plan-demo/PUZZLE.md; нужно окно):
##   godot/tools/godot_nofocus.sh --path godot --resolution 1600x900 res://tests/puzzle_snapshot.tscn -- "out_dir=/abs/dir,rooms=1+2+3+4+5+6,action=1"
## rooms — общий вид комнат (куклы у входа; 7–8 — с порталами); action — три кадра в деле: двое несут ящик 60 кг (комната 3), «низ»
## повёрнут вправо и чугунный ящик на плите на стене (комната 4), взрыв бочки у трещины (комната 6); portal=1 — кадры порталов
## (docs/plan-demo/PORTAL.md): чугунный ящик вылетает из B с разгона (комната 7), пара под током, выход B2, бочка у трещины (комната 8).
## Глазами проверить: комната целиком в кадре, плиты с подписью кг, кабели, двери и лампы, знак гравитации, HUD слева сверху.
extends Node

const PLAYGROUND := "res://scenes/playground_puzzle.tscn"
const TICK := 1.0 / 60.0

var out_dir := "/tmp"
var rooms := "1+2+3+4+5+6"
var action := true
var portal := false
var upright := false
var pg: PuzzlePlayground


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # снимок на паузе дерева
	for arg in OS.get_cmdline_user_args():
		for part in String(arg).split(","):
			var kv := part.split("=")
			if kv.size() != 2:
				continue
			match kv[0]:
				"out_dir": out_dir = kv[1]
				"rooms": rooms = kv[1]
				"action": action = kv[1] == "1"
				"portal": portal = kv[1] == "1"
				"upright": upright = kv[1] == "1"
	_run.call_deferred()


func _shot(name_: String) -> void:
	# физика на паузе, пока кадр не нарисован: окно за другими окнами macOS притормаживает, и без паузы между «пора снимать» и
	# отрисовкой проходят десятки физических тиков (летящий ящик успевал долететь)
	get_tree().paused = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	get_tree().paused = false
	var path := "%s/%s.png" % [out_dir, name_]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("shot → ", path)


func _wait(s: float) -> void:
	for i in int(ceil(s / TICK)):
		await get_tree().physics_frame


func _at(r: PuzzleRoom, x: float, y: float) -> Vector3:
	return r.global_position + Vector3(x, y, 0)


func _teleport(d: Doll, to: Vector3) -> void:
	var shift := to - d.centre_of_mass()
	shift.z = 0.0
	for p in d.parts.values():
		var b := p as RigidBody3D
		if b != null and is_instance_valid(b):
			b.global_position += shift
			b.linear_velocity = Vector3.ZERO
			b.angular_velocity = Vector3.ZERO


func _grab(arm: ArmAssist, b: RigidBody3D) -> bool:
	for i in 90:
		arm.set_target_override(arm.closest_point(b, arm.grip_global()))
		await get_tree().physics_frame
		if arm.find_candidate() == b:
			break
	arm.press_grab()
	await get_tree().physics_frame
	await get_tree().physics_frame
	return arm.held == b


func _run() -> void:
	pg = (load(PLAYGROUND) as PackedScene).instantiate() as PuzzlePlayground
	pg.p2_on_start = true
	pg.auto_join = false
	add_child(pg)
	await _wait(0.3)
	for d in pg.players():
		(d as Doll).external_input = true
	for i in pg.rooms.size():
		if not str(i + 1) in rooms.split("+"):
			continue
		pg.goto_room(i)
		await _wait(2.6)   # проезд камеры и заставка «КОМНАТА N» гаснет
		await _shot("room%d" % (i + 1))
	if action:
		await _carry()
		await _gravity()
		await _boom()
	if portal:
		await _fling()
		await _switch()
	if upright:
		await _upright()
	get_tree().quit(0)


## Комната 7: груз на весах — шахта тяжёлая; P1 ныряет в шахту → A → из B боком и за 0.3–0.4 с встаёт головой вверх (выход «как в
## Portal»). Кадры: upright_0 (момент выхода), _1 (0.1 с), _2 (0.2 с), _3 (0.4 с).
func _upright() -> void:
	pg.goto_room(6)
	pg.reset_room()
	await _wait(2.4)
	var r := pg.rooms[6]
	var pair := r.find("Portals") as PortalPair
	var iron := r.find("Iron") as RigidBody3D
	iron.global_position = _at(r, 3.0, 3.6)
	_teleport(pg.p2, _at(r, -4.0, 1.0))
	var shaft := r.find("Shaft") as PuzzleGravity
	for i in 240:
		await get_tree().physics_frame
		if shaft.is_on():
			break
	_teleport(pg.p1, _at(r, 7.0, 5.0))
	var t0 := pair.transfers
	for i in 300:
		pg.p1.input_vec = Vector2(0, -1)
		await get_tree().physics_frame
		if pair.transfers > t0:
			break
	pg.p1.input_vec = Vector2.ZERO
	pg.hud.visible = false   # плашка комнаты закрывает щель B
	var marks := [0, 6, 12, 24]
	var done := 0
	for k in 25:
		if k == marks[done]:
			await _shot("upright_%d" % done)
			done += 1
			if done >= marks.size():
				break
		await get_tree().physics_frame


## Комната 7: чугунный ящик столкнули с полки — через щель A на полу он вылетает из B в левой стене (кадр — в полёте).
func _fling() -> void:
	pg.goto_room(6)
	pg.reset_room()
	await _wait(2.4)
	var r := pg.rooms[6]
	var pair := r.find("Portals") as PortalPair
	var iron := r.find("Iron") as RigidBody3D
	_teleport(pg.p1, _at(r, 5.2, 7.0))
	_teleport(pg.p2, _at(r, -4.0, 1.0))
	iron.global_position = _at(r, 6.7, 6.6)   # уже за краем полки: падает вдоль правой стены в A
	iron.linear_velocity = Vector3(0.5, 0, 0)
	var t0 := pair.transfers
	for i in int(4.0 / TICK):
		await get_tree().physics_frame
		if pair.transfers > t0:
			break
	await _wait(0.42)
	await _shot("portal_fling")


## Комната 8: рычаг на B2, P2 на плите (пара под током: A и B2 горят, B1 тускло), бочку роняют в A — кадр, когда она вылетела из B2.
func _switch() -> void:
	pg.goto_room(7)
	pg.reset_room()
	await _wait(2.4)
	var r := pg.rooms[7]
	await _shot("portal_off")
	var pair := r.find("Portals") as PortalPair
	(r.find("Lever") as PuzzleLever).set_state(true)
	_teleport(pg.p2, _at(r, -3.8, 1.0))
	_teleport(pg.p1, _at(r, 1.0, 3.2))
	var barrel: RigidBody3D = null
	for c in r.get_node("Props").get_children():
		if c is ExplosiveBarrel:
			barrel = c
	await _wait(0.8)
	barrel.global_position = _at(r, 0.2, 1.8)
	barrel.linear_velocity = Vector3(0, -4.0, 0)
	var t0 := pair.transfers
	for i in int(3.0 / TICK):
		await get_tree().physics_frame
		if pair.transfers > t0:
			break
	await _wait(0.25)
	await _shot("portal_switch")


## Комната 3: двое несут ящик 60 кг.
func _carry() -> void:
	pg.goto_room(2)
	pg.reset_room()
	await _wait(0.6)
	var r := pg.rooms[2]
	var duo := r.find("Duo") as RigidBody3D
	var c0 := duo.global_position
	_teleport(pg.p1, Vector3(c0.x - 0.8, 1.0, 0))
	_teleport(pg.p2, Vector3(c0.x + 0.9, 1.0, 0))
	await _wait(0.6)
	var a1 := PuzzlePlayground._arm(pg.p1)
	var a2 := PuzzlePlayground._arm(pg.p2)
	var g1 := await _grab(a1, duo)
	var g2 := await _grab(a2, duo)
	print("carry: grabbed ", g1, " ", g2)
	a1.clear_target_override()
	a2.clear_target_override()
	for i in int(5.0 / TICK):
		pg.p1.input_vec = Vector2(-0.1, 1).normalized()
		pg.p2.input_vec = Vector2(0.1, 1).normalized()
		await get_tree().physics_frame
		if i % 30 == 0:
			print("carry t=%.1f y=%.2f held %s %s st %.2f %.2f tm %.2f %.2f" % [i * TICK, duo.global_position.y, a1.held == duo, a2.held == duo, a1.hold_distance(), a2.hold_distance(), pg.p1.thrust_mult, pg.p2.thrust_mult])
		if duo.global_position.y > 2.8:
			break
	await _shot("carry")
	pg.p1.input_vec = Vector2.ZERO
	pg.p2.input_vec = Vector2.ZERO


## Комната 4: рычаг вправо — «низ» вбок, ящик на плите на стене.
func _gravity() -> void:
	pg.goto_room(3)
	pg.reset_room()
	await _wait(2.4)
	var r := pg.rooms[3]
	_teleport(pg.p1, _at(r, -4.6, 1.0))
	_teleport(pg.p2, _at(r, -6.4, 3.5))
	(r.find("Lever") as PuzzleLever).set_state(true)
	await _wait(3.5)
	await _shot("gravity")


## Комната 6: бочка брошена в трещину — взрыв.
func _boom() -> void:
	pg.goto_room(5)
	pg.reset_room()
	await _wait(2.4)
	var r := pg.rooms[5]
	_teleport(pg.p1, _at(r, 1.2, 1.0))
	_teleport(pg.p2, _at(r, -2.5, 4.0))
	var barrel := r.find("BarrelB") as RigidBody3D
	barrel.global_position = _at(r, 2.0, 0.02)
	await _wait(0.6)
	var arm := PuzzlePlayground._arm(pg.p1)
	await _grab(arm, barrel)
	for i in 30:
		arm.set_target_override(arm.root_point() + Vector3(arm.reach, 0.25, 0))
		await get_tree().physics_frame
	arm.press_grab()
	var wall := r.find("CrackWall") as PuzzleCrackWall
	for i in 120:
		await get_tree().physics_frame
		if not is_instance_valid(wall) or wall.broken:
			break
	await _wait(0.12)
	await _shot("boom")
