## Скриншоты look-dev «Мастерская» (scenes/lookdev/workshop_lookdev.tscn) для сравнения с R22.
## Запуск: godot --path . --resolution 1280x720 --position 100,100 res://tests/lookdev_snapshot.tscn -- "out=res://tests/"
##   Аргументы (через запятую в первом аргументе): out=<папка>, a=<с> (кадр A, по умолчанию 1.45), b=<с> (кадр B, 1.95),
##   env.<свойство>=<число> (перекрыть Environment, напр. env.volumetric_fog_density=0.03), sun.<свойство>=<число>,
##   cam.fov=<град>, cam.y=<м>, cam.z=<м>, fx=0 (без ручного спавна щепок в кадре B).
## Кадры (по умолчанию A при t=1.4 с — кукла 2 в полёте после толчка 0.9..1.3 с, B при 1.62 с): tests/lookdev_a.png — общий план в компоновке R22 (верстак слева, станок справа, окна сзади, куклы в лучах);
##        tests/lookdev_b.png — крупно толкаемая кукла в лучах + щепки/пыль (ImpactFx) в момент удара.
## Печатает JSON: куклы загрузились (2), средний fps ≥ 20, эффект спавнился ≥ 1 раз, контактные удары ≥ 1 к until=2.8 с,
## значения Environment и трансформ солнца (для переноса в арену); exit 1 при провале проверок.
extends Node3D

const LookdevScene := preload("res://scenes/lookdev/workshop_lookdev.tscn")

var look: WorkshopLookdev
var cam: Camera3D
var t := 0.0
var shots := 0
var busy := false
var out_dir := "res://tests/"
var shot_a_t := 1.4
var shot_b_t := 1.62
var run_until := 2.8   # после кадра B физика идёт дальше: толкнутая кукла долетает до первой — считаем контактные удары
var manual_fx := true
var fx_done := false
var cam_over: Dictionary = {}
var scene_mode := "workshop"
var fps_samples: Array[float] = []
var warm := 0.0
const WARMUP_S := 1.2   # пауза дерева: компиляция шейдеров, сходимость SDFGI и temporal-тумана до старта физики
var report := {"ok": true, "checks": []}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "scene":
				scene_mode = p[1]
	if scene_mode == "ruins":
		_ruins_mode()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	look = LookdevScene.instantiate() as WorkshopLookdev
	look.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(look)
	get_tree().paused = true
	cam = look.cam
	cam.current = true
	var env: Environment = look.env.environment.duplicate()
	look.env.environment = env
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			var key := p[0]
			var val := p[1]
			if key == "out":
				out_dir = val
			elif key == "scene":
				scene_mode = val
			elif key == "a":
				shot_a_t = float(val)
			elif key == "b":
				shot_b_t = float(val)
			elif key == "until":
				run_until = float(val)
			elif key == "fx":
				manual_fx = val != "0"
			elif key.begins_with("env."):
				_set_num(env, key.substr(4), val)
			elif key.begins_with("sun."):
				_set_num(look.sun, key.substr(4), val)
			elif key.begins_with("cam."):
				cam_over[key.substr(4)] = float(val)
	_frame_a()


## Режим scene=ruins: арена «Руины» с ruins_env.tres / ruins_camera.tres вместо её собственного окружения —
## проверка, что пресет для улицы грузится и выглядит вменяемо (tests/lookdev_ruins.png), без проверок JSON.
func _ruins_mode() -> void:
	var ps := load("res://scenes/arena/ruins.tscn") as PackedScene
	if ps == null:
		push_error("ruins.tscn не загрузилась")
		get_tree().quit(1)
		return
	var arena := ps.instantiate() as Node3D
	add_child(arena)
	var we := arena.get_node_or_null("Environment") as WorldEnvironment
	var renv := load("res://assets/environments/ruins_env.tres") as Environment
	var rcam := load("res://assets/environments/ruins_camera.tres") as CameraAttributes
	if we != null and renv != null:
		we.environment = renv
		we.camera_attributes = rcam
	var c := Camera3D.new()
	c.fov = 40.0
	c.position = Vector3(0, 5.5, 22)
	add_child(c)
	c.current = true
	var dps := load("res://scenes/doll/doll.tscn") as PackedScene
	if dps != null and arena.has_method("spawn_points"):
		var spawns: Array = arena.call("spawn_points")
		for i in mini(2, spawns.size()):
			var d := dps.instantiate() as Node3D
			d.set("player_index", i)
			d.set("external_input", true)
			d.position = spawns[i]
			add_child(d)
	await get_tree().create_timer(1.5).timeout
	await _capture("lookdev_ruins.png")
	get_tree().quit(0)


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
		TYPE_VECTOR3:
			var v := val.split(":")
			if v.size() >= 3:
				obj.set(prop, Vector3(float(v[0]), float(v[1]), float(v[2])))
		_:
			obj.set(prop, float(val))


## Общий план, компоновка R22: камера на высоте груди кукол, лёгкий наклон вниз, окна слева сзади в кадре.
func _frame_a() -> void:
	cam.fov = float(cam_over.get("fov", 42.0))
	var y := float(cam_over.get("y", 1.5))
	var z := float(cam_over.get("z", 6.2))
	var x := float(cam_over.get("x", 0.4))
	cam.position = Vector3(x, y, z)
	cam.look_at(Vector3(float(cam_over.get("tx", x)), float(cam_over.get("ty", 1.2)), float(cam_over.get("tz", 0.0))))


## Крупно: толкаемая кукла (Doll2) в лучах, чуть сбоку, чтобы читались объём и пыль.
func _frame_b() -> void:
	var c := look.doll_com(1)
	cam.fov = 32.0
	cam.position = c + Vector3(1.1, 0.45, 3.1)
	cam.look_at(c + Vector3(0.0, 0.05, 0.0))


func _physics_process(delta: float) -> void:
	if look != null and not get_tree().paused:
		t += delta


func _process(delta: float) -> void:
	if look == null:
		return
	if get_tree().paused:
		warm += delta
		if warm >= WARMUP_S:
			get_tree().paused = false
		return
	if t > 0.5:
		fps_samples.append(Engine.get_frames_per_second())
	if busy:
		return
	if shots == 0 and t >= shot_a_t:
		busy = true
		await _capture("lookdev_a.png")
		shots = 1
		busy = false
	elif shots == 1 and manual_fx and not fx_done and t >= shot_b_t - 0.12:
		fx_done = true
		_frame_b()
		var hand := look.doll_part(1, "Hand_L")
		var pos := hand.global_position if hand != null else look.doll_com(1) + Vector3(-0.3, 0.3, 0.0)
		look.spawn_fx(pos, Vector3(-0.8, 0.5, 0.35), 9.0)
	elif shots == 1 and t >= shot_b_t:
		busy = true
		_frame_b()
		await _capture("lookdev_b.png")
		shots = 2
		busy = false
	elif shots == 2 and t >= run_until:
		busy = true
		_finish()


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(name)
	var err := img.save_png(path)
	print("saved ", path, " (", err, ") at t=", snappedf(t, 0.01))


func _check(id: String, ok: bool, value: float, limit: float) -> void:
	report["checks"].append({"id": id, "ok": ok, "value": snappedf(value, 0.01), "limit": limit})
	if not ok:
		report["ok"] = false


func _finish() -> void:
	var fps := 0.0
	for f in fps_samples:
		fps += f
	fps = fps / maxf(1.0, float(fps_samples.size()))
	_check("dolls_loaded", look.dolls.size() == 2, look.dolls.size(), 2)
	_check("fps_avg", fps >= 20.0, fps, 20)
	report["frame_ms"] = snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.1)
	report["fps_min"] = fps_samples.min() if not fps_samples.is_empty() else 0.0
	_check("fx_spawned", look.fx_spawned >= 1, look.fx_spawned, 1)
	_check("contact_impacts", look.contact_impacts >= 1, look.contact_impacts, 1)
	if look.dolls.size() >= 2:
		var c0 := look.doll_com(0)
		var c1 := look.doll_com(1)
		report["doll1_com"] = [snappedf(c0.x, 0.01), snappedf(c0.y, 0.01)]
		report["doll2_com"] = [snappedf(c1.x, 0.01), snappedf(c1.y, 0.01)]
	var e: Environment = look.env.environment
	var envd := {}
	for prop in ["tonemap_exposure", "ambient_light_energy", "ssao_intensity", "ssil_intensity", "sdfgi_enabled", "sdfgi_energy",
			"volumetric_fog_density", "volumetric_fog_anisotropy", "volumetric_fog_gi_inject", "glow_intensity", "glow_hdr_threshold",
			"adjustment_contrast", "adjustment_saturation"]:
		envd[prop] = e.get(prop)
	report["env"] = envd
	report["sun"] = {"energy": look.sun.light_energy, "color": look.sun.light_color.to_html(false),
		"volumetric_fog_energy": look.sun.light_volumetric_fog_energy,
		"rotation_degrees": [snappedf(look.sun.rotation_degrees.x, 0.1), snappedf(look.sun.rotation_degrees.y, 0.1), snappedf(look.sun.rotation_degrees.z, 0.1)],
		"direction": look.sun.global_basis.z * -1.0}
	print(JSON.stringify(report))
	get_tree().quit(0 if report["ok"] else 1)
