## Скриншоты арены «Мастерская» (res://scenes/arena/workshop.tscn из компонентов scenes/props/workshop_*) с двумя куклами
## (res://scenes/doll/doll.tscn — клён, res://scenes/doll/doll_dark.tscn — орех, если грузится; external_input=true).
## Запуск: godot --path . --resolution 1280x720 --position 100,100 --always-on-top res://tests/workshop_snapshot.tscn -- "hold=1.5,push=0.9"
##   Аргументы (через запятую в первом аргументе): hold=<с> (кадр full), push=<с> (длительность толчка куклы 1),
##   out=<папка>, env.<свойство>=<число> (перекрыть Environment арены, напр. env.volumetric_fog_density=0.008),
##   sun.<свойство>=<число>, fps=1 (не завершать до until=<с>; fps меряется с t=2.5 с, после компиляции шейдеров),
##   arena=<res://путь.tscn> (другая арена только для сравнения fps: проверки мастерской тогда пропускаются).
## Кадры: tests/workshop_full.png  — вся арена (fov 40, камера (0, 4.8, 22.5)) при t=hold, куклы на спавнах 0/1;
##        tests/workshop_close.png — крупно (полувысота 3 м) кукла 0 у левого штабеля в лучах из окна;
##        tests/workshop_fly.png   — кукла 1 после толчка влево-вверх летит через центр (камера — полувысота 5.5 м).
## Печатает JSON с проверками (куклы стоят, кукла 1 пролетела ≥ 2.5 м, никто не провалился под пол, 3 лампы висят,
## 2 козел, ≥ 8 разрушаемых, 4 спавна, 6 оконных стен со стеклом без тени, средний fps); exit 1 при провале.
extends Node3D

const CAM_FOV := 40.0
const CAM_POS := Vector3(0, 4.8, 22.5)
const CLOSE_HALF_H := 3.0
const FLY_HALF_H := 5.5
const DOLL_SCENE := "res://scenes/doll/doll.tscn"
const DOLL_DARK_SCENE := "res://scenes/doll/doll_dark.tscn"
const WARMUP_S := 1.0   # пауза до старта физики: шейдеры, SDFGI, temporal-туман

var arena: Node3D
var ws: WorkshopArena
var arena_path := "res://scenes/arena/workshop.tscn"
var dolls: Array = []
var cam: Camera3D
var t := 0.0
var warm := 0.0
var shots := 0
var busy := false
var hold := 1.5
var push := 0.9
var run_until := 0.0
var measure_fps := false
var out_dir := "res://tests/"
var fly_shot_t := INF
var start_x1 := 0.0
var best_dx1 := 0.0
var min_y := INF
var fps_samples: Array[float] = []
var report := {"ok": true, "checks": [], "dolls": 0}


func _ready() -> void:
	var env_over: Dictionary = {}
	var sun_over: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			match p[0]:
				"hold": hold = float(p[1])
				"push": push = float(p[1])
				"out": out_dir = p[1]
				"until": run_until = float(p[1])
				"fps": measure_fps = p[1] != "0"
				"arena": arena_path = p[1]
				_:
					if p[0].begins_with("env."):
						env_over[p[0].substr(4)] = p[1]
					elif p[0].begins_with("sun."):
						sun_over[p[0].substr(4)] = p[1]
	process_mode = Node.PROCESS_MODE_ALWAYS
	arena = load(arena_path).instantiate() as Node3D
	ws = arena as WorkshopArena
	arena.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(arena)
	var we := arena.get_node_or_null("Environment") as WorldEnvironment
	if we != null and not env_over.is_empty():
		var e: Environment = we.environment.duplicate()
		for k in env_over.keys():
			_set_num(e, k, env_over[k])
		we.environment = e
	var sun := arena.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		for k in sun_over.keys():
			_set_num(sun, k, sun_over[k])
	cam = Camera3D.new()
	cam.fov = CAM_FOV
	cam.position = CAM_POS
	add_child(cam)
	cam.make_current()
	var spawns: Array = arena.call("spawn_points")
	var ps := load(DOLL_SCENE) as PackedScene
	var ps_dark: PackedScene = null
	if ResourceLoader.exists(DOLL_DARK_SCENE):
		ps_dark = load(DOLL_DARK_SCENE) as PackedScene
	if ps == null:
		push_warning("doll.tscn is not loadable; arena only")
	else:
		for i in 2:
			var d := (ps_dark if (i == 1 and ps_dark != null) else ps).instantiate() as Node3D
			if d == null:
				continue
			d.name = "Doll%d" % i
			d.set("player_index", i)
			d.set("external_input", true)
			d.position = spawns[i]
			d.process_mode = Node.PROCESS_MODE_PAUSABLE
			add_child(d)
			dolls.append(d)
		report["dolls"] = dolls.size()
	if dolls.size() >= 2:
		start_x1 = _com(1).x
	get_tree().paused = true


func _set_num(obj: Object, prop: String, val: String) -> void:
	var cur: Variant = obj.get(prop)
	if cur == null:
		push_warning("нет свойства %s" % prop)
		return
	match typeof(cur):
		TYPE_BOOL:
			obj.set(prop, val != "0" and val != "false")
		TYPE_INT:
			obj.set(prop, int(val))
		TYPE_COLOR:
			var c := val.split(":")
			if c.size() >= 3:
				obj.set(prop, Color(float(c[0]), float(c[1]), float(c[2])))
		_:
			obj.set(prop, float(val))


func _com(i: int) -> Vector3:
	var d: Node3D = dolls[i]
	if d.has_method("centre_of_mass"):
		return d.call("centre_of_mass") as Vector3
	return d.global_position + Vector3(0, 0.9, 0)


func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	t += delta
	if dolls.is_empty():
		return
	for d in dolls:
		d.set("input_vec", Vector2.ZERO)
	# кукла 1: со спавна справа — влево-вверх через центр (над станком)
	if t > hold + 0.4 and t < hold + 0.4 + push:
		dolls[1].set("input_vec", Vector2(-1.0, 0.45))
	for i in dolls.size():
		min_y = minf(min_y, _com(i).y)
	if shots == 2:
		var c := _com(1)
		best_dx1 = maxf(best_dx1, start_x1 - c.x)
		if fly_shot_t == INF and start_x1 - c.x > 3.0:
			fly_shot_t = t


func _process(delta: float) -> void:
	if get_tree().paused:
		warm += delta
		if warm >= WARMUP_S:
			get_tree().paused = false
		return
	if t > 2.5:
		fps_samples.append(Engine.get_frames_per_second())
	if busy:
		return
	if shots == 0 and t >= hold:
		busy = true
		await _capture("workshop_full.png")
		busy = false
	elif shots == 1 and t >= hold + 0.3:
		busy = true
		_close_up()
		await _capture("workshop_close.png")
		busy = false
	elif shots == 2 and (t >= fly_shot_t or t >= hold + 0.4 + push + 1.4):
		busy = true
		_frame_fly()
		await _capture("workshop_fly.png")
		busy = false
	elif shots >= 3 and t >= maxf(run_until, hold + 0.4 + push + 2.0):
		busy = true
		_finish()


func _close_up() -> void:
	var centre := Vector3(-6.0, 1.4, 0)
	if not dolls.is_empty():
		centre = _com(0) + Vector3(0.9, 0.35, 0)
	var d := CLOSE_HALF_H / tan(deg_to_rad(CAM_FOV * 0.5))
	cam.position = Vector3(centre.x, centre.y, centre.z + d)


func _frame_fly() -> void:
	var centre := Vector3(0, 3.5, 0)
	if dolls.size() >= 2:
		var a := _com(0)
		var b := _com(1)
		centre = (a + b) * 0.5 if a.distance_to(b) < 2.0 * FLY_HALF_H * 1.6 else b
		centre.y = maxf(centre.y, 2.5)
	var d := FLY_HALF_H / tan(deg_to_rad(CAM_FOV * 0.5))
	cam.position = Vector3(centre.x, centre.y + 0.5, centre.z + d)


func _check(id: String, ok: bool, value: float, limit: float) -> void:
	report["checks"].append({"id": id, "ok": ok, "value": snappedf(value, 0.01), "limit": limit})
	if not ok:
		report["ok"] = false


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(name)
	var err := img.save_png(path)
	print("saved ", path, " (", err, ") at t=", snappedf(t, 0.01))
	shots += 1
	if shots == 1 and not dolls.is_empty():
		for i in dolls.size():
			var c := _com(i)
			_check("doll%d_standing" % i, c.y > dolls[i].position.y + 0.6, c.y - dolls[i].position.y, 0.6)


func _finish() -> void:
	var fps := 0.0
	for f in fps_samples:
		fps += f
	fps = fps / maxf(1.0, float(fps_samples.size()))
	_check("dolls_loaded", dolls.size() == 2, dolls.size(), 2)
	if dolls.size() >= 2:
		_check("doll1_flew_x", best_dx1 >= 2.5, best_dx1, 2.5)
		_check("dolls_above_floor", min_y > -0.3, min_y, -0.3)
		for i in dolls.size():
			var c := _com(i)
			report["doll%d" % i] = [snappedf(c.x, 0.01), snappedf(c.y, 0.01)]
	if ws != null:
		_workshop_checks()
	_check("fps_avg", fps >= 25.0, fps, 25)
	report["fps_min"] = fps_samples.min() if not fps_samples.is_empty() else 0.0
	report["frame_ms"] = snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.1)
	report["physics_ms"] = snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.1)
	report["draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	report["primitives"] = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	report["objects"] = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	report["lights"] = _count_lights(arena)
	report["resolution"] = var_to_str(get_viewport().get_visible_rect().size)
	report["window_px"] = var_to_str(DisplayServer.window_get_size())
	report["screen_scale"] = DisplayServer.screen_get_scale()
	report["arena"] = arena_path
	print(JSON.stringify(report))
	get_tree().quit(0 if report["ok"] else 1)


func _workshop_checks() -> void:
	var lamps := ws.lamps()
	_check("lamps", lamps.size() == 3, lamps.size(), 3)
	var lamp_min_y := INF
	for l in lamps:
		var body := (l as Node3D).get_node_or_null("Body") as RigidBody3D
		if body != null:
			lamp_min_y = minf(lamp_min_y, body.global_position.y)
	_check("lamps_hang_y", lamp_min_y > 4.0, lamp_min_y, 4.0)
	var horses := ws.sawhorses()
	_check("sawhorses", horses.size() == 2, horses.size(), 2)
	var horse_min_y := INF
	for h in horses:
		horse_min_y = minf(horse_min_y, (h as Node3D).global_position.y)
	_check("sawhorses_on_floor", horse_min_y > -0.3, horse_min_y, -0.3)
	_check("breakables", ws.breakables().size() >= 8, ws.breakables().size(), 8)
	_check("spawns", ws.spawn_points().size() == 4, ws.spawn_points().size(), 4)
	var walls := ws.window_walls()
	_check("window_walls", walls.size() == 6, walls.size(), 6)
	var glass_ok := 0
	for w in walls:
		var g: MeshInstance3D = (w as WorkshopWindowWall).glass()
		if g != null and g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			glass_ok += 1
	_check("glass_no_shadow", glass_ok == walls.size(), glass_ok, walls.size())
	_check("platforms", ws.platforms().size() >= 8, ws.platforms().size(), 8)
	var b := ws.bounds()
	_check("bounds_width", absf(b.size.x - 26.0) < 0.01, b.size.x, 26.0)


func _count_lights(n: Node) -> int:
	var c := 1 if n is Light3D else 0
	for ch in n.get_children():
		c += _count_lights(ch)
	return c

