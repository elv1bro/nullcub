## Турнтейбл модели героя без физического рига: фронт, три четверти, профиль → три PNG + общий лист.
## godot --path . --resolution 1280x720 --position 100,100 res://tests/mannequin_turntable.tscn -- "skin=res://assets/models/heroes/mannequin.glb,prefix=mannequin"
## Пишет tests/<prefix>_front.png, <prefix>_34.png, <prefix>_side.png и <prefix>_sheet.png (три ракурса в ряд).
extends Node3D

var skin := "res://assets/models/heroes/mannequin.glb"
var prefix := "mannequin"
var shots := [["front", 0.0], ["34", -45.0], ["side", -90.0]]
var idx := 0
var t := 0.0
var busy := false
var model: Node3D
var cam: Camera3D


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			if p[0] == "skin":
				skin = p[1]
			elif p[0] == "prefix":
				prefix = p[1]
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.20, 0.20, 0.21)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.85, 0.9)
	e.ambient_light_energy = 0.4
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, 35, 0)
	key.light_energy = 0.9
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, -110, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.8, 0.85, 1.0)
	add_child(fill)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	floor.mesh = pm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.17, 0.17, 0.18)
	fmat.roughness = 1.0
	floor.material_override = fmat
	add_child(floor)
	cam = Camera3D.new()
	cam.position = Vector3(0, 0.96, 4.7)
	cam.fov = 28
	add_child(cam)
	model = _spawn(Vector3.ZERO, 0.0)
	if model == null:
		push_error("mannequin_turntable: cannot load " + skin)
		get_tree().quit(1)


func _spawn(pos: Vector3, yaw: float) -> Node3D:
	var ps := load(skin)
	if ps == null:
		return null
	var inst: Node3D = ps.instantiate()
	inst.position = pos
	inst.rotation_degrees.y = yaw
	add_child(inst)
	return inst


func _process(delta: float) -> void:
	t += delta
	if busy or t < 0.3:
		return
	busy = true
	if idx < shots.size():
		model.rotation_degrees.y = shots[idx][1]
		await _capture("%s_%s.png" % [prefix, shots[idx][0]])
		idx += 1
		busy = false
		return
	# лист: три ракурса в ряд
	model.rotation_degrees.y = 0.0
	model.position = Vector3(-1.35, 0, 0)
	_spawn(Vector3(0, 0, 0), -45.0)
	_spawn(Vector3(1.35, 0, 0), -90.0)
	await _capture("%s_sheet.png" % prefix)
	get_tree().quit(0)


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tests/" + name)
	print("saved ", name)
