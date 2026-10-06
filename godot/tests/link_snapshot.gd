## Кадры мастерской со связками (KitLink, docs/plan-demo/WORKSHOP_V4.md «Связки»): шаблон «Поршневой» и вкладка «Связки» с инструментом.
##   godot/tools/godot_nofocus.sh --path godot --resolution 1920x1080 res://tests/link_snapshot.tscn -- "out=/abs/dir"
## Нужно окно. Пишет links-pistons.png (шаблон), links-tool.png (вкладка «Связки», первый конец стержня выбран), links-rod.png
## (стержень кисть — бедро поставлен), links-frames.png (рама вместо ноги, звезда и развилка на запястьях).
extends Node3D

const WORKSHOP := "res://scenes/workshop/workshop_build.tscn"

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
	var path := out_dir.path_join("links-%s.png" % tag)
	print("saved ", path, " (", get_viewport().get_texture().get_image().save_png(path), ")")


func _run() -> void:
	WorkshopBuild.prefs_path = "user://workshop_prefs_link_snapshot.cfg"
	var ws := (load(WORKSHOP) as PackedScene).instantiate() as WorkshopBuild
	ws.load_autosave = false
	ws.autosave_on_test = false
	ws.probe_input = true
	add_child(ws)
	await _frames(30)
	ws.set_preset("kit_pistons")
	await _frames(60)
	await _shot("pistons")
	ws.set_preset("kit_human")
	await _frames(20)
	ws.ui.get("shelf_tab")["body"] = "link"
	ws.ui.call("_build_left")
	ws.set_link_pick("rod")
	ws._link_click({"target": "body", "uid": "3", "pos": (ws.stand.parts["Hand_L"] as Node3D).global_position})
	await _frames(40)
	await _shot("tool")
	ws._link_click({"target": "body", "uid": "4", "pos": (ws.stand.parts["UpperLeg_L"] as Node3D).global_position})
	ws.set_link_pick("rope")
	ws._link_click({"target": "body", "uid": "9", "pos": (ws.stand.parts["Hand_R"] as Node3D).global_position})
	ws._link_click({"target": "body", "uid": "C", "pos": (ws.stand.parts["Foot_R"] as Node3D).global_position})
	await _frames(40)
	await _shot("rod")
	# рама и разветвители: рама вместо левой ноги (три ноги), звезда с пятью кистями справа, развилка слева
	ws.set_preset("kit_human")
	await _frames(10)
	var nodes: Array[Dictionary] = []
	for n in ws.blueprint.nodes:
		if not ["4", "5", "6", "3", "9"].has(String(n["uid"])):
			nodes.append(n)
	for a in [["4", "kit_limb_frame_s", "T", "Anchor_Hip_L"], ["5", "kit_human_lower_leg", "4", "Anchor_End"], ["6", "kit_human_foot", "5", "Anchor_Ankle"],
			["D", "kit_human_lower_leg", "4", "Anchor_SideB_L"], ["E", "kit_human_lower_leg", "4", "Anchor_SideB_R"],
			["9", "kit_hub_star", "8", "Anchor_Wrist"], ["F", "kit_human_hand", "9", "Anchor_End"], ["G", "kit_human_hand", "9", "Anchor_Side_L"],
			["I", "kit_human_hand", "9", "Anchor_Side_R"], ["J", "kit_human_hand", "9", "Anchor_SideB_L"], ["K", "kit_human_hand", "9", "Anchor_SideB_R"],
			["3", "kit_hub_fork", "2", "Anchor_Wrist"], ["L", "kit_human_hand", "3", "Anchor_Side_L"], ["M", "kit_human_hand", "3", "Anchor_Side_R"]]:
		nodes.append({"uid": a[0], "part": a[1], "parent": a[2], "anchor": a[3]})
	ws.blueprint.nodes = nodes
	ws.blueprint.control = PackedStringArray(["F"])
	ws.blueprint.energy_budget = 1000
	ws.clear_tools()
	ws.call("_rebuild")
	ws.ui.get("shelf_tab")["body"] = "limb"
	ws.ui.call("_build_left")
	await _frames(60)
	await _shot("frames")
	get_tree().quit(0)
