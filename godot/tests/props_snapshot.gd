## Витрина библиотеки пропсов (R17): все компоненты в ряд + разрушение бочки быстрым ящиком.
## Запуск: godot --path . --resolution 1280x720 --position 100,100 res://tests/props_snapshot.tscn -- "mode=scenes,out=res://tests/"
##   mode=scenes (по умолчанию) — сцены scenes/props/*.tscn; mode=glb — сырые модели assets/models/props/*.glb
##   Кадры: tests/props_row.png (весь ряд), tests/props_close.png (ящик/столб/мост крупно), tests/props_gate.png (ворота
##   закрыты и открыты), tests/props_break.png (бочка после двух ударов ящиками: обломки разлетаются).
## Печатает JSON: бочка прошла intact → damaged → destroyed, обломков ≥ 4, сигнал destroyed пришёл, первый удар
## зарегистрирован со скоростью ≥ 10 м/с, ударов два; exit 1 при провале.
extends Node3D

const PROPS := "res://scenes/props/"
const GLB := "res://assets/models/props/"

var mode := "scenes"
var out_dir := "res://tests/"
var cam: Camera3D
var t := 0.0
var stage := 0
var busy := false
var row: Node3D
var arena: Node3D
var barrel: Node = null
var states: Array = []
var destroyed_signal := false
var hits: Array = []
var barrel_x := 0.0
var break_ticks := 0
var launch2_t := 0.0
## Тики физики (60 Гц) от запуска первого ящика до второго: не раньше 1.4 с (и бочка успокоилась), не позже 4 с.
const SECOND_HIT_TICKS := 84
const SECOND_HIT_MAX_TICKS := 240
var report := {"ok": true, "checks": [], "mode": ""}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			if p[0] == "mode":
				mode = p[1]
			elif p[0] == "out":
				out_dir = p[1]
	report["mode"] = mode
	_lighting()
	_floor()
	row = Node3D.new()
	row.name = "Row"
	add_child(row)
	_build_row()
	cam = Camera3D.new()
	add_child(cam)
	_frame_row()


func _lighting() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.36, 0.55, 0.84)
	sm.sky_horizon_color = Color(0.78, 0.82, 0.88)
	sm.ground_bottom_color = Color(0.40, 0.38, 0.36)
	sm.ground_horizon_color = Color(0.66, 0.66, 0.68)
	sm.sun_angle_max = 8.0
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 1.0
	e.ambient_light_energy = 0.6
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 0.8
	e.tonemap_white = 1.0
	e.ssao_enabled = true
	e.ssao_radius = 0.5
	e.ssao_intensity = 2.0
	e.glow_enabled = true
	e.glow_intensity = 0.3
	e.glow_hdr_threshold = 1.2
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 28, 0)
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.96, 0.90)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 40.0
	sun.shadow_bias = 0.02
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -120, 0)
	fill.light_energy = 0.30
	fill.light_color = Color(0.80, 0.86, 1.0)
	add_child(fill)


func _floor() -> void:
	var f := StaticBody3D.new()
	f.name = "Floor"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 1, 20)
	cs.shape = bs
	f.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(60, 1, 20)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.46, 0.44, 0.41)
	mat.roughness = 0.95
	mi.material_override = mat
	f.add_child(mi)
	f.position = Vector3(0, -0.5, 0)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	f.physics_material_override = pm
	add_child(f)


## Элементы ряда: [имя, путь, позиция, свойства].
func _entries() -> Array:
	if mode == "glb":
		return [
			["Barrel", GLB + "Barrel.glb", Vector3(-9.0, 0, 0), {}],
			["Crate", GLB + "Crate.glb", Vector3(-7.6, 0, 0), {}],
			["Post", GLB + "Post.glb", Vector3(-6.4, 0, 0), {}],
			["Plank", GLB + "Plank.glb", Vector3(-5.6, 0, 0), {}],
			["Rope", GLB + "Rope_Segment.glb", Vector3(-5.2, 0.4, 0), {}],
			["Banner", GLB + "Banner.glb", Vector3(-4.4, 0, 0), {}],
			["Gate", GLB + "Gate_Arch.glb", Vector3(0.0, 0, -0.5), {}],
			["DoorL", GLB + "Gate_Door_L.glb", Vector3(-1.5, 0, -0.5), {}],
			["DoorR", GLB + "Gate_Door_R.glb", Vector3(1.5, 0, -0.5), {}],
			["Wall", GLB + "Wall_Segment.glb", Vector3(4.2, 0, -0.5), {}],
			["Platform", GLB + "Stone_Platform_2m.glb", Vector3(6.8, 0, 0), {}],
			["Block", GLB + "Stone_Block.glb", Vector3(6.8, 0.4, 0), {}],
			["Torch", GLB + "Torch.glb", Vector3(8.4, 0.6, 0), {}],
			["Cage", GLB + "Cage.glb", Vector3(9.6, 0, 0), {}],
			["Deck", GLB + "Deck_3m.glb", Vector3(12.0, 0.0, 0), {}],
			["Post2", GLB + "Post_2m.glb", Vector3(13.8, 0, 0), {}],
		]
	return [
		["Barrel", PROPS + "barrel.tscn", Vector3(-9.0, 0.02, 0), {}],
		["Crate", PROPS + "crate.tscn", Vector3(-7.6, 0.02, 0), {}],
		["Bridge", PROPS + "rope_bridge_4m.tscn", Vector3(-6.6, 0.0, 0), {}],
		["Banner", PROPS + "banner.tscn", Vector3(-1.9, 0, 0), {"color": "red"}],
		["Gate", PROPS + "gate.tscn", Vector3(1.6, 0, -0.5), {"open": true}],
		["Wall", PROPS + "wall_segment.tscn", Vector3(5.6, 0, -0.5), {}],
		["Platform", PROPS + "stone_platform_2m.tscn", Vector3(8.2, 0, 0), {}],
		["Torch", PROPS + "torch.tscn", Vector3(9.8, 0.6, 0), {}],
		["Cage", PROPS + "cage.tscn", Vector3(11.2, 3.0, 0), {}],
		["Deck", PROPS + "wooden_deck.tscn", Vector3(14.6, 0.0, 0), {}],
		["BannerB", PROPS + "banner.tscn", Vector3(13.0, 2.25, -0.3), {"color": "blue"}],
	]


func _build_row() -> void:
	for e in _entries():
		var ps: PackedScene = load(e[1])
		if ps == null:
			push_warning("missing " + str(e[1]))
			report["checks"].append({"id": "load_" + e[0], "ok": false})
			report["ok"] = false
			continue
		var n: Node3D = ps.instantiate()
		n.name = e[0]
		for k in e[3].keys():
			n.set(k, e[3][k])
		n.position = e[2]
		row.add_child(n)


func _frame_row() -> void:
	cam.fov = 40
	var ext := 16.0 if mode == "scenes" else 15.0
	cam.position = Vector3(2.4, 2.6, ext)
	cam.look_at(Vector3(2.4, 1.6, 0))


func _frame_close() -> void:
	cam.fov = 32
	cam.position = Vector3(-6.2, 1.4, 5.2)
	cam.look_at(Vector3(-6.0, 0.9, 0))


func _frame_gate() -> void:
	cam.fov = 38
	var g := row.get_node_or_null("Gate")
	if g and mode == "scenes":
		g.set("open", false)
		var g2: Node3D = load(PROPS + "gate.tscn").instantiate()
		g2.name = "GateOpen"
		g2.position = g.position + Vector3(6.0, 0, 0)
		g2.set("open", true)
		row.add_child(g2)
		cam.position = Vector3(g.position.x + 3.0, 2.0, 9.5)
		cam.look_at(Vector3(g.position.x + 3.0, 1.7, -0.5))
	else:
		cam.position = Vector3(0.0, 2.0, 7.5)
		cam.look_at(Vector3(0.0, 1.7, -0.5))


## Арена разрушения: бочка на полу; первый ящик влетает слева (12 м/с, по центру бочки — оба получают по 24 HP:
## ящик рассыпается, бочка → damaged), второй через 1.4 с — справа, в бочку там, где она оказалась → destroyed,
## обруч и клёпки разлетаются. За состоянием следим по сигналам state_changed/destroyed и hit.
func _build_break() -> void:
	row.visible = false
	for c in row.get_children():
		c.queue_free()
	arena = Node3D.new()
	arena.name = "Break"
	arena.position = Vector3(0, 0, 0)
	add_child(arena)
	var ps: PackedScene = load(PROPS + "barrel.tscn")
	if ps == null:
		report["checks"].append({"id": "load_barrel", "ok": false})
		report["ok"] = false
		return
	barrel = ps.instantiate()
	barrel.name = "TargetBarrel"
	barrel.position = Vector3(0, 0.02, 0)
	arena.add_child(barrel)
	if barrel.has_signal("destroyed"):
		barrel.destroyed.connect(func() -> void: destroyed_signal = true)
	if barrel.has_signal("hit"):
		barrel.hit.connect(func(speed: float, dmg: float, _by: Node) -> void: hits.append([snappedf(speed, 0.01), snappedf(dmg, 0.01)]))
	cam.fov = 38
	cam.position = Vector3(1.0, 1.3, 8.0)
	cam.look_at(Vector3(1.0, 0.6, 0))
	_launch_crate(-3.5, 12.0)


func _launch_crate(x: float, vx: float, vy := 0.5) -> void:
	var ps: PackedScene = load(PROPS + "crate.tscn")
	if ps == null:
		return
	var c: RigidBody3D = ps.instantiate()
	c.name = "Projectile%d" % arena.get_child_count()
	c.position = Vector3(x, 0.05, 0)   # низ ящика на полу: центр 0.4 = центр бочки, удар лобовой
	arena.add_child(c)
	c.linear_velocity = Vector3(vx, vy, 0)


func _physics_process(delta: float) -> void:
	t += delta
	if stage >= 3 and barrel != null and is_instance_valid(barrel):
		barrel_x = barrel.position.x
		var s = barrel.get("state")
		if s != null and (states.is_empty() or states[-1] != s):
			states.append(s)
		# Второй ящик запускается по счётчику физических тиков, а не из _process по t: save_png перед фазой
		# стопит кадр на ~0.5 с, и число тиков между запусками плавало — бочка после первого удара ещё едет,
		# и второй ящик прилетал в разные точки (1 из 3 прогонов — удар не засчитан). Jolt детерминирован по тикам.
		# Даже при фиксированном числе тиков второй удар был хаотичным: ящик с vy=0.5 приземлялся за ~0.03 с до
		# удара и кувыркался (в неудачных прогонах стоял целый вплотную к бочке). Поэтому второй ящик летит
		# по воздуху (vy=1.2 → апекс ≈ в момент удара) и стартует, когда бочка после первого удара успокоилась.
		if stage == 3:
			break_ticks += 1
			var v: float = barrel.linear_velocity.length() if barrel is RigidBody3D else 0.0
			if break_ticks >= SECOND_HIT_TICKS and (v < 0.3 or break_ticks >= SECOND_HIT_MAX_TICKS):
				_launch_crate(barrel_x + 3.5, -12.0, 1.2)
				launch2_t = t
				stage = 4


func _process(_delta: float) -> void:
	if busy:
		return
	if stage == 0 and t >= 0.5:
		busy = true
		await _capture("props_row.png")
		_frame_close()
		stage = 1
		busy = false
	elif stage == 1 and t >= 0.8:
		busy = true
		await _capture("props_close.png")
		_frame_gate()
		stage = 2
		busy = false
	elif stage == 2 and t >= 1.1:
		busy = true
		await _capture("props_gate.png")
		if mode == "glb":
			_finish()
			return
		_build_break()
		stage = 3
		t = 0.0
		busy = false
	elif stage == 4 and t >= launch2_t + 1.0:
		busy = true
		await _capture("props_break.png")
		_finish()


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(name)
	var err := img.save_png(path)
	print("saved ", path, " (", err, ") at t=", snappedf(t, 0.01))


func _check(id: String, ok: bool, value := 0.0) -> void:
	report["checks"].append({"id": id, "ok": ok, "value": value})
	if not ok:
		report["ok"] = false


func _finish() -> void:
	if mode == "scenes":
		var debris := 0
		for c in arena.get_children():
			if c is RigidBody3D and c.name.begins_with("TargetBarrel_"):
				debris += 1
		_check("barrel_damaged_seen", states.has(1), states.size())
		_check("barrel_destroyed_seen", states.has(2) or destroyed_signal, states.size())
		_check("destroyed_signal", destroyed_signal)
		_check("debris_spawned", debris >= 4, debris)
		_check("hit_speed_ge_10", not hits.is_empty() and float(hits[0][0]) >= 10.0, float(hits[0][0]) if not hits.is_empty() else 0.0)
		_check("two_hits", hits.size() >= 2, hits.size())
		report["states"] = states
		report["hits"] = hits
	print(JSON.stringify(report))
	get_tree().quit(0 if report["ok"] else 1)
