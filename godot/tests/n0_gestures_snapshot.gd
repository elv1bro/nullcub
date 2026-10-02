## Лист жестов тела N0 (scripts/n0/n0_drone.gd, «Тело», 02.10.2026). Нужен рендер (окно; в контейнере — xvfb-run):
##   godot --path godot --resolution 1600x900 res://tests/n0_gestures_snapshot.tscn -- "out=/tmp/n0_gestures.png"
## Ряд 1: покой, полёт вправо с разгоном (крылья чаще, ножки отстают), говорит (микрофон к экрану), злится (angry).
## Ряд 2: ликует (excited), машет (happy), вздрогнул (shocked), сник (sad), задумался (curious).
## Камера как в бою: с +Z, без наклона. Кадр снимается в середине жестов.
extends Node3D

const N0_SCENE := preload("res://scenes/n0/n0.tscn")
const COLS := 5
const STEP := 1.25

var out := "user://n0_gestures.png"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var p := String(a).split("=")
		if p.size() == 2 and p[0] == "out":
			out = p[1]
	_environment()
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0.0, 0.05, 6.4)
	add_child(cam)
	cam.current = true
	var cells := [
		["покой", ""], ["полёт →", "fly"], ["говорит", "talk"], ["злится", "angry"], ["", ""],
		["ликует", "excited"], ["машет", "happy"], ["вздрогнул", "shocked"], ["сник", "sad"], ["задумался", "curious"],
	]
	var drones: Array = []
	for i in cells.size():
		if String(cells[i][0]) == "":
			continue
		var d := N0_SCENE.instantiate() as N0Drone
		add_child(d)
		var col := i % COLS
		var row := i / COLS
		d.position = Vector3((col - (COLS - 1) * 0.5) * STEP, 0.75 - row * 1.55, 0.0)
		d.scale = Vector3.ONE * 0.75
		var l := Label3D.new()
		l.text = String(cells[i][0])
		l.font_size = 40
		l.pixel_size = 0.004
		l.position = d.position + Vector3(0.0, -0.62, 0.3)
		l.outline_size = 10
		add_child(l)
		drones.append([d, String(cells[i][1])])
	await get_tree().process_frame
	for e in drones:
		var d: N0Drone = e[0]
		match String(e[1]):
			"fly":
				d.set_motion(Vector3(8.0, 0.0, 0.0), Vector3(40.0, 0.0, 0.0))
			"talk":
				d.talking = true
			"":
				pass
			_:
				d.flash_expression(String(e[1]), 30.0)
	await _secs(0.55)
	for e in drones:
		if String(e[1]) == "fly":
			(e[0] as N0Drone).set_motion(Vector3(8.0, 0.0, 0.0), Vector3(40.0, 0.0, 0.0))
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(out)
	print("n0_gestures_snapshot: %s" % out)
	get_tree().quit(0)


func _secs(s: float) -> void:
	var t := 0.0
	while t < s:
		await get_tree().process_frame
		t += get_process_delta_time()


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.04, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.75)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	for spec in [[Vector3(-35.0, -30.0, 0.0), Color(1.0, 0.85, 0.68), 1.6, true],
			[Vector3(-20.0, 160.0, 0.0), Color(0.45, 0.6, 1.0), 1.4, false],
			[Vector3(-60.0, 40.0, 0.0), Color(1.0, 0.95, 0.9), 0.4, false]]:
		var l := DirectionalLight3D.new()
		l.rotation_degrees = spec[0]
		l.light_color = spec[1]
		l.light_energy = spec[2]
		l.shadow_enabled = spec[3]
		add_child(l)
