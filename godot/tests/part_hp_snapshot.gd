## Кадры мастерской в режиме «Запас из деталей» (PartHp, docs/plan-demo/WORKSHOP_V4.md): сводка, полка с ❤, паспорт головы.
##   godot/tools/godot_nofocus.sh --path godot --resolution 1920x1080 res://tests/part_hp_snapshot.tscn -- "out=/abs/dir"
## Нужно окно (кадры). Пишет part-hp-summary.png, part-hp-head.png, part-hp-arm.png.
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
	var path := out_dir.path_join("part-hp-%s.png" % tag)
	print("saved ", path, " (", get_viewport().get_texture().get_image().save_png(path), ")")


func _run() -> void:
	var was := PartHp.on
	WorkshopBuild.prefs_path = "user://workshop_prefs_part_hp_snapshot.cfg"
	var ws := (load(WORKSHOP) as PackedScene).instantiate() as WorkshopBuild
	ws.load_autosave = false
	ws.autosave_on_test = false
	ws.probe_input = true
	add_child(ws)
	await _frames(30)
	ws.set_preset("kit_human")
	PartHp.set_on(false)
	ws.toggle_parts_hp()
	await _frames(60)
	await _shot("summary")
	var head := ""
	for n in ws.blueprint.nodes:
		var pd := BodyBlueprint.part_def(String(n["part"]))
		if pd != null and pd.kind == "head":
			head = String(n["uid"])
	ws.select_stand(head, "body")
	await _frames(30)
	await _shot("head")
	ws.select_stand(ws.blueprint.nodes[3]["uid"], "body")
	await _frames(30)
	await _shot("arm")
	PartHp.set_on(was)
	get_tree().quit(0)
