## Визуальная проверка боя (план 06): два кадра за один запуск, без HUD.
##   tests/combat_hit.png — P2 (орех) через 0.2 с после удара P1 (клён) на 10 м/с: щепки/пыль ImpactFx в точке контакта, жертва в отбросе;
##   tests/combat_ko.png  — P2 с hp 5 получает удар → KO: суставы порваны, части разлетаются (В3, как в Ragdoll Masters).
## Запуск: godot --path . --resolution 1280x720 --always-on-top res://tests/combat_snapshot.tscn -- "out=res://tests/"
extends Node3D

const DollScene := preload("res://scenes/doll/doll.tscn")
const DollDarkScene := preload("res://scenes/doll/doll_dark.tscn")

var a: Doll
var b: Doll
var cam: Camera3D
var t := 0.0
var stage := 0
var busy := false
var hit_t := -1.0
var ko_t := -1.0
var out_dir := "res://tests/"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "out":
				out_dir = p[1]
	get_viewport().msaa_3d = Viewport.MSAA_4X
	_lighting()
	_floor()
	a = _spawn(DollScene, 0, Vector3(-2.2, 0, 0))
	b = _spawn(DollDarkScene, 1, Vector3(0.6, 0, 0))
	b.damaged.connect(func(_amount: float, _at: Node, _part: String, _pos: Vector3, _kind: String) -> void:
		if hit_t < 0.0:
			hit_t = t)
	b.knocked_out.connect(func(_at: Node, _rec: Dictionary) -> void:
		ko_t = t)
	cam = Camera3D.new()
	add_child(cam)
	cam.fov = 40
	cam.position = Vector3(0.6, 1.3, 7.5)
	cam.look_at(Vector3(0.6, 1.0, 0))


func _spawn(scene: PackedScene, index: int, pos: Vector3) -> Doll:
	var d: Doll = scene.instantiate()
	d.player_index = index
	d.external_input = true
	d.add_to_group("dolls")
	add_child(d)
	d.position = pos
	var c := DollCombat.new()
	c.name = "DollCombat"
	d.add_child(c)
	return d


func _lighting() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.16, 0.13, 0.11)
	sm.sky_horizon_color = Color(0.62, 0.50, 0.36)
	sm.ground_bottom_color = Color(0.12, 0.09, 0.07)
	sm.ground_horizon_color = Color(0.42, 0.33, 0.24)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.ssao_enabled = true
	e.glow_enabled = true
	e.glow_intensity = 0.25
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -42, 0)
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.86, 0.66)
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, 130, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.62, 0.74, 0.95)
	add_child(fill)


func _floor() -> void:
	var f := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(40, 1, 12)
	cs.shape = bs
	f.add_child(cs)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 12)
	mi.mesh = pm
	mi.position = Vector3(0, 0.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.25, 0.19)
	mat.roughness = 0.85
	mi.material_override = mat
	f.add_child(mi)
	f.position = Vector3(0, -0.5, 0)
	var phys := PhysicsMaterial.new()
	phys.friction = 0.9
	f.physics_material_override = phys
	add_child(f)
	var wall := MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = Vector2(60, 20)
	wall.mesh = wm
	wall.rotation_degrees = Vector3(90, 0, 0)
	wall.position = Vector3(0, 6, -9)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.20, 0.15, 0.11)
	wmat.roughness = 1.0
	wall.material_override = wmat
	add_child(wall)


func _inject(d: Doll, v: Vector3) -> void:
	for p in d.parts.values():
		(p as RigidBody3D).linear_velocity = v
		(p as RigidBody3D).angular_velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	t += delta
	if not is_instance_valid(a) or not is_instance_valid(b):
		return
	a.input_vec = Vector2.ZERO
	b.input_vec = Vector2.ZERO
	if stage == 0 and t >= 1.0 and hit_t < 0.0:
		_inject(a, Vector3(10.0, 0, 0))
	elif stage == 1 and ko_t < 0.0 and t >= 3.0:
		if b.hp > 5.0:
			b.hp = 5.0
		_inject(a, Vector3(10.0, 0, 0))


func _process(_delta: float) -> void:
	if busy:
		return
	if stage == 0 and hit_t >= 0.0 and t >= hit_t + 0.2:
		busy = true
		var c := b.centre_of_mass()
		cam.position = Vector3(c.x, 1.3, 7.0)
		cam.look_at(Vector3(c.x, 1.0, 0))
		await _capture("combat_hit.png")
		# вернуть кукол на исходные для второго кадра
		a.queue_free()
		b.queue_free()
		await get_tree().process_frame
		a = _spawn(DollScene, 0, Vector3(-2.2, 0, 0))
		b = _spawn(DollDarkScene, 1, Vector3(0.6, 0, 0))
		b.knocked_out.connect(func(_at: Node, _rec: Dictionary) -> void:
			ko_t = t)
		t = 2.0
		stage = 1
		busy = false
	elif stage == 1 and ko_t >= 0.0 and t >= ko_t + 0.35:
		busy = true
		var c := b.centre_of_mass()
		cam.fov = 45
		cam.position = Vector3(c.x, 1.5, 9.0)
		cam.look_at(Vector3(c.x, 1.0, 0))
		await _capture("combat_ko.png")
		get_tree().quit(0)
	elif t > 12.0:
		print("timeout: hit_t=", hit_t, " ko_t=", ko_t)
		get_tree().quit(1)


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(name)
	var err := img.save_png(path)
	print("saved ", path, " (", err, ") at t=", snappedf(t, 0.01))
