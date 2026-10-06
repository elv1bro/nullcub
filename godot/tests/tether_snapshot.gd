## Кадры «детали на связке» (docs/plan-demo/WORKSHOP_V4.md «Деталь на связке и налог на ветвление»): вкладка «Шарниры» с новыми
## шарнирами, стенд, испытание с кистенем и кукла в гараже.
##   godot/tools/godot_nofocus.sh --path godot --resolution 1920x1080 res://tests/tether_snapshot.tscn -- "out=/abs/dir"
## Нужно окно. Пишет tether-joints.png (вкладка, нога на тросе), tether-stand.png (нога на тросе, кисть на поршне, кисть на пружине),
## tether-flail-1..3.png (испытание: тяга на стопе ноги на тросе, мышь крутит её), tether-garage.png и tether-garage-side.png
## (та же сборка сидит на ящике, как в гараже меню).
extends Node3D

const WORKSHOP := "res://scenes/workshop/workshop_build.tscn"
const GARAGE_DOLL := "res://scenes/menu/garage_doll.gd"
const BP_PATH := "user://tether_snapshot_bp.tres"

var out_dir := "user://"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "out":
				out_dir = p[1]
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join("tether-%s.png" % tag)
	print("saved ", path, " (", get_viewport().get_texture().get_image().save_png(path), ")")


func _run() -> void:
	WorkshopBuild.prefs_path = "user://workshop_prefs_tether_snapshot.cfg"
	var ws := (load(WORKSHOP) as PackedScene).instantiate() as WorkshopBuild
	ws.load_autosave = false
	ws.autosave_on_test = false
	ws.probe_input = true
	add_child(ws)
	await _frames(30)
	ws.set_preset("kit_human")
	await _frames(10)
	ws.blueprint.energy_budget = 300
	ws.ui.get("shelf_tab")["body"] = "joint"
	ws.ui.call("_build_left")
	ws.set_joint_pick("on_rope")
	ws.set_joint("A")
	await _frames(60)
	await _shot("joints")
	ws.set_joint_pick("on_piston")
	ws.set_joint("3")
	ws.set_joint_pick("on_spring")
	ws.set_joint("9")
	await _frames(60)
	await _shot("stand")
	ResourceSaver.save(ws.blueprint.duplicate(true), BP_PATH)
	# испытание: тяга — стопа ноги на тросе, мышь водит её по кругу вокруг крепления
	ws.blueprint.control = PackedStringArray(["C"])
	ws.call("_rebuild")
	await _frames(10)
	ws.start_test()
	await _frames(30)
	var aa := ws.test_doll.get_node_or_null("ArmAssist") as ArmAssist
	for i in range(150):
		if aa != null:
			var ang := -PI * 0.5 + i * 0.1
			aa.set_target_override(aa.root_point() + Vector3(cos(ang), sin(ang), 0.0) * 1.6)
		await get_tree().physics_frame
		if i % 10 == 0 and ws.test_doll.parts.has("Foot_R"):
			print("flail i=%d foot=%s torso=%s" % [i, (ws.test_doll.parts["Foot_R"] as Node3D).global_position, ws.test_doll.torso().global_position])
		if i == 70 or i == 100 or i == 130:
			await _shot("flail-%d" % [1 + (i - 70) / 30])
	ws.queue_free()
	await _frames(5)
	# гараж: та же сборка сидит на ящике
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.1, 3.4)
	add_child(cam)
	cam.look_at(Vector3(0.0, 0.7, 0.0))
	cam.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.13, 0.11)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	add_child(env)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8.0, 8.0)
	floor.mesh = pm
	add_child(floor)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 0.5, 0.5)
	box.mesh = bm
	box.position = Vector3(0.0, 0.25, 0.0)
	add_child(box)
	var gd := Node3D.new()
	gd.set_script(load(GARAGE_DOLL))
	gd.set("blueprint_path", BP_PATH)
	add_child(gd)
	await _frames(20)
	await _shot("garage")
	cam.position = Vector3(3.4, 1.1, 0.4)
	cam.look_at(Vector3(0.0, 0.7, 0.0))
	await _frames(5)
	await _shot("garage-side")
	get_tree().quit(0)
