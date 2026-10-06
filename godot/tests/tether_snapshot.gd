## Кадры «детали на связке» (docs/plan-demo/WORKSHOP_V4.md «Деталь на связке и налог на ветвление»): вкладка «Шарниры» с новыми
## шарнирами, стенд, испытание с кистенем.
##   godot/tools/godot_nofocus.sh --path godot --resolution 1920x1080 res://tests/tether_snapshot.tscn -- "out=/abs/dir"
## Нужно окно. Пишет tether-joints.png (вкладка, нога на тросе), tether-stand.png (нога на тросе, кисть на поршне, кисть на пружине),
## tether-flail-1..3.png (испытание: тяга на стопе ноги на тросе, мышь крутит её). Кадров «кукла на ящике в гараже» больше нет
## (06.10: в гараже кукла висит на стенде мастерской).
extends Node3D

const WORKSHOP := "res://scenes/workshop/workshop_build.tscn"
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
	# (06.10: кукла больше не сидит на ящике в гараже — висит на стенде мастерской, её кадры — tether-stand.png)
	get_tree().quit(0)
