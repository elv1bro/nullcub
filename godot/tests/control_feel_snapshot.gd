## Кадры «как выглядит управление» (нужно окно): один вариант ControlFeel — кукла вправо 1.6 с, затем разворот влево 0.8 с,
## кадры каждые 0.4 с (камера следует за ЦМ). Запуск (без кражи фокуса):
##   godot/tools/godot_nofocus.sh --path godot --resolution 960x540 --fixed-fps 60 res://tests/control_feel_snapshot.tscn -- "variant=head,tempo=action,air=0,out=/abs/dir"
##   air=1 — кукла в воздухе (спавн на 3.5 м, лёгкая тяга вверх, висит и летит вбок) — как в бою над полом; dash=1 — с ускорением (Shift).
## Кадры: <out>/<variant>_<tempo>_<air|floor>_<n>.png (n = 0…5). Лист из кадров всех вариантов собирает tools/control_feel_sheet.py.
extends Node3D

const MARKS := [0.4, 0.8, 1.2, 1.6, 2.0, 2.4]   # с после начала движения
const SETTLE_S := 1.0

var variant := "body"
var tempo := "now"
var air := false
var dash := false
var out_dir := "/tmp"
var _doll: Doll
var _cam: Camera3D
var _t := 0.0
var _shot := 0
var _busy := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			match p[0]:
				"variant": variant = p[1]
				"tempo": tempo = p[1]
				"air": air = p[1] != "0"
				"dash": dash = p[1] != "0"
				"out": out_dir = p[1]
	ControlFeel.reset()
	ControlFeel.set_variant(variant)
	ControlFeel.set_tempo(tempo)
	get_viewport().msaa_3d = Viewport.MSAA_4X
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.13, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.85, 0.9)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	add_child(sun)
	var f := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(80, 1, 10)
	cs.shape = bs
	f.add_child(cs)
	var fm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(80, 1, 10)
	fm.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.34, 0.4)
	fm.material_override = mat
	f.add_child(fm)
	f.position = Vector3(0, -0.5, 0)
	add_child(f)
	_doll = (load("res://scenes/doll/doll.tscn") as PackedScene).instantiate()
	_doll.external_input = true
	_doll.position = Vector3(0, 3.5 if air else 0.05, 0)
	add_child(_doll)
	_cam = Camera3D.new()
	_cam.fov = 40
	_cam.position = Vector3(0, 1.6, 9.0)
	add_child(_cam)


func _physics_process(delta: float) -> void:
	_t += delta
	var hover := Vector2(0, 0.2) if air else Vector2.ZERO
	if _t < SETTLE_S:
		_doll.input_vec = hover
		return
	var since := _t - SETTLE_S
	var dir := 1.0 if since < 1.6 else -1.0
	_doll.input_vec = Vector2(dir, hover.y)
	if dash:
		_doll.request_dash()
	var c := _doll.centre_of_mass()
	_cam.position = Vector3(c.x, maxf(c.y, 1.4) + 0.3, 9.0)


func _process(_d: float) -> void:
	if _busy or _shot >= MARKS.size():
		return
	if _t - SETTLE_S >= float(MARKS[_shot]):
		_capture()


func _capture() -> void:
	_busy = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out_dir)
	img.save_png("%s/%s_%s_%s_%d.png" % [out_dir, variant, tempo, "air" if air else "floor", _shot])
	_shot += 1
	_busy = false
	if _shot >= MARKS.size():
		ControlFeel.reset()
		get_tree().quit(0)
