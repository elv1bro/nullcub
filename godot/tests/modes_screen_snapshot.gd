## Кадр экрана «ВСЕ РЕЖИМЫ» (нужно окно; только через tools/godot_nofocus.sh, docs/plan-demo/MODES_SCREEN.md):
##   godot/tools/godot_nofocus.sh --path godot --resolution 1600x900 res://tests/modes_screen_snapshot.tscn -- "out=/abs/shot.png,lang=en,sel=squad,memo=0"
## lang — язык (ru, en, qps…), sel — id режима (MODES), memo=1 — открыть памятку клавиш, hover=<id> — карточка под мышью.
## Экран в dry_run: ИГРАТЬ и Esc ничего не грузят. Кадр — PNG; в jpg для документов: sips -s format jpeg -s formatOptions 82.
extends Node

const SCENE := "res://scenes/menu/test_menu.tscn"

var out := "/tmp/modes_screen.png"
var lang := "ru"
var sel := ""
var memo := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for part in String(arg).split(","):
			var kv := part.split("=")
			if kv.size() != 2:
				continue
			match kv[0]:
				"out": out = kv[1]
				"lang": lang = kv[1]
				"sel": sel = kv[1]
				"memo": memo = kv[1] == "1"
	_run.call_deferred()


func _run() -> void:
	get_node("/root/Loc").set_language(lang)
	var menu := (load(SCENE) as PackedScene).instantiate() as Control
	menu.set("dry_run", true)
	add_child(menu)
	await _frames(10)
	if sel != "":
		var list: Array = menu.get("list")
		for i in list.size():
			if String(list[i]["id"]) == sel:
				menu.call("select", i)
	if memo:
		menu.call("set_memo", true)
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	img.save_png(out)
	print("shot → ", out, " ", img.get_size())
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
