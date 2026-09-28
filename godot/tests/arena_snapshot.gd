## Скриншоты арены «Руины» v2 (res://scenes/arena/ruins.tscn из компонентов scenes/props) с куклами
## (res://scenes/doll/doll.tscn, external_input=true).
## Запуск: godot --path . --resolution 1280x720 --position 100,100 res://tests/arena_snapshot.tscn -- "hold=1.5,push=1.6"
## Кадры: tests/arena_full.png   — вся арена (камера fov 40 в (0, 5.5, 22)) при t=hold, куклы 0/1 на спавнах;
##        tests/arena_bridge.png — кукла 2 со спавна левой палубы идёт по верёвочному мосту (толчок вправо push с),
##                                 кадр в момент, когда её ЦМ над мостом (или по таймауту), камера у моста;
##        tests/arena_close.png  — крупный план (полувысота 4 м) ворот и кукол 0/1.
## Печатает JSON с проверками (куклы стоят, кукла 2 дошла до моста и не упала, ничего не упало в яму, 6 факелов,
## 3 знамени, мост из 19 досок, ≥ 16 разрушаемых пропсов, клетка висит, параллакс на месте); exit 1 при провале.
extends Node3D

const CAM_FOV := 40.0
const CAM_POS := Vector3(0, 5.5, 22)
const CLOSE_HALF_H := 4.0
const BRIDGE_X0 := -8.4       # столбы A моста
const BRIDGE_X1 := -2.4       # столбы B (на каменном мосту)

var arena: RuinsArena
var dolls: Array = []
var cam: Camera3D
var t := 0.0
var shots := 0
var capturing := false
var hold := 1.5
var push := 1.6
var fell: Array = []
var bridge_shot_t := INF
var bridge_best_x := -INF
var report := {"ok": true, "checks": [], "dolls": 0}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			match p[0]:
				"hold": hold = float(p[1])
				"push": push = float(p[1])
	arena = load("res://scenes/arena/ruins.tscn").instantiate()
	add_child(arena)
	arena.body_fell.connect(func(b: Node3D) -> void: fell.append(str(b.get_path())))
	cam = Camera3D.new()
	cam.fov = CAM_FOV
	cam.position = CAM_POS
	add_child(cam)
	cam.make_current()
	var doll_scene: PackedScene = load("res://scenes/doll/doll.tscn")
	var spawns := arena.spawn_points()
	if doll_scene == null:
		push_warning("doll.tscn is not loadable; arena only")
	else:
		for i in 3:
			var d = doll_scene.instantiate()
			d.player_index = i
			d.external_input = true
			d.position = spawns[i]
			add_child(d)
			dolls.append(d)
		report["dolls"] = dolls.size()


func _physics_process(delta: float) -> void:
	t += delta
	if dolls.is_empty():
		return
	for d in dolls:
		d.input_vec = Vector2.ZERO
	# кукла 2: со спавна левой палубы вправо — на верёвочный мост (лёгкий подъём, мост идёт в гору)
	if t > hold and t < hold + push:
		dolls[2].input_vec = Vector2(1.0, 0.12)
	if shots == 1:
		var c: Vector3 = dolls[2].centre_of_mass()
		bridge_best_x = maxf(bridge_best_x, c.x)
		if bridge_shot_t == INF and c.x > (BRIDGE_X0 + BRIDGE_X1) * 0.5 + 0.3:
			bridge_shot_t = t   # ЦМ за серединой моста — снимаем


func _process(_delta: float) -> void:
	if capturing:
		return
	if shots == 0 and t >= hold:
		_capture("arena_full.png")
	elif shots == 1 and (t >= bridge_shot_t or t >= hold + push + 1.6):
		_frame_bridge()
		_capture("arena_bridge.png")
	elif shots == 2 and t >= hold + push + 2.2:
		_close_up()
		_capture("arena_close.png")


func _frame_bridge() -> void:
	var centre := Vector3((BRIDGE_X0 + BRIDGE_X1) * 0.5, 3.6, 0)
	if dolls.size() >= 3:
		centre.x = clampf(dolls[2].centre_of_mass().x, BRIDGE_X0 - 1.0, BRIDGE_X1 + 1.0)
	var d := 3.2 / tan(deg_to_rad(CAM_FOV * 0.5))
	cam.position = Vector3(centre.x, centre.y + 0.3, centre.z + d)


func _close_up() -> void:
	var centre := Vector3(0, 2.0, 0)
	if dolls.size() >= 2:
		var a: Vector3 = dolls[0].centre_of_mass()
		var b: Vector3 = dolls[1].centre_of_mass()
		centre = (a + b) * 0.5 if a.distance_to(b) < 2.0 * CLOSE_HALF_H * 1.7 else a
	var d := CLOSE_HALF_H / tan(deg_to_rad(CAM_FOV * 0.5))
	cam.position = Vector3(centre.x, centre.y + 0.4, centre.z + d)


func _check(id: String, ok: bool, value: float, limit: float) -> void:
	report["checks"].append({"id": id, "ok": ok, "value": snappedf(value, 0.01), "limit": limit})
	if not ok:
		report["ok"] = false


func _capture(name: String) -> void:
	capturing = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tests/" + name)
	print("saved ", name, " at t=", snappedf(t, 0.01))
	shots += 1
	capturing = false
	if shots == 1 and not dolls.is_empty():
		for i in dolls.size():
			var c: Vector3 = dolls[i].centre_of_mass()
			_check("doll%d_standing" % i, c.y > dolls[i].position.y + 0.6, c.y - dolls[i].position.y, 0.6)
	if shots == 2 and dolls.size() >= 3:
		var c2: Vector3 = dolls[2].centre_of_mass()
		_check("doll2_reached_bridge_x", bridge_best_x > BRIDGE_X0 + 0.5, bridge_best_x, BRIDGE_X0 + 0.5)
		_check("doll2_on_bridge_now", c2.x > BRIDGE_X0 and c2.x < BRIDGE_X1 + 1.5 and c2.y > 2.6, c2.x, BRIDGE_X0)
		_check("doll2_not_fallen_y", c2.y > 2.4, c2.y, 2.4)
		report["doll2"] = [snappedf(c2.x, 0.01), snappedf(c2.y, 0.01)]
	if shots >= 3:
		_check("nothing_fell", fell.is_empty(), fell.size(), 0)
		if not fell.is_empty():
			report["fell"] = fell
		_check("torches", arena.torches().size() >= 6, arena.torches().size(), 6)
		_check("banners", arena.banners().size() >= 3, arena.banners().size(), 3)
		_check("breakables", arena.breakables().size() >= 16, arena.breakables().size(), 16)
		var bridges := arena.rope_bridges()
		_check("rope_bridge_planks", bridges.size() == 1 and bridges[0].planks().size() == 19, bridges[0].planks().size() if bridges.size() == 1 else 0, 19)
		var cage_body := arena.get_node_or_null("Right/Cage/Body") as Node3D
		_check("cage_hangs_y", cage_body != null and cage_body.global_position.y > 1.5, cage_body.global_position.y if cage_body else 0.0, 1.5)
		var px := arena.parallax()
		_check("parallax_present", px != null and px.get_child_count() >= 4, px.get_child_count() if px else 0, 4)
		for i in dolls.size():
			var c: Vector3 = dolls[i].centre_of_mass()
			report["doll%d" % i] = [snappedf(c.x, 0.01), snappedf(c.y, 0.01)]
		print(JSON.stringify(report))
		get_tree().quit(0 if report["ok"] else 1)
