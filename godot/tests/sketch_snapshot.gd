## Снимки холста «Нарисуй» (docs/plan-demo/SKETCH_FIGHTER.md) на русском и английском — поверх гаража, как в fighter_select_snapshot.
## Нужно окно, только невидимо:
##   GODOT_BIN=/usr/local/bin/godot godot/tools/godot_bg.sh --path godot --resolution 1920x1080 --fixed-fps 60 \
##     res://tests/sketch_snapshot.tscn -- "out_dir=/abs/dir"
## Кадры на язык: human (человечек, превью справа), multi (многорукий), hammer (зигзаг на конце руки — навершие, ЛКМ на нём).
## Глазами проверить: штрихи раскрашены по ролям, портрет в превью есть, строка распознавания и правила влезают.
extends Node

const MENU := "res://scenes/menu/garage_menu.tscn"
const P := preload("res://tests/sketch_probe.gd")

var out_dir := "/tmp/sketch_fighter"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for part in String(arg).split(","):
			var kv := part.split("=")
			if kv.size() == 2 and kv[0] == "out_dir":
				out_dir = kv[1]
	_run.call_deferred()


func _shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name_]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("shot → ", path)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _draw_set(fs: FighterSelect, strokes: Array, name_: String) -> void:
	fs.sketch_strokes = strokes.duplicate()
	fs.sketch_seed = 0
	fs.rebuild_sketch()
	fs._pad.queue_redraw()
	await _frames(150)   # портрет превью рендерится не сразу
	await _shot(name_)


func _run() -> void:
	var menu := (load(MENU) as PackedScene).instantiate() as GarageMenu
	menu.dry_run = true
	add_child(menu)
	await _frames(30)
	menu.enter_menu()
	menu.set_focus(1, true)
	await _frames(60)
	var loc := get_node("/root/Loc")
	var hammer: Array = P.human()
	hammer.append(P.zigzag(P.arm_end(hammer), Vector2(1, -0.5), 70.0, 4, 18.0))
	for lang in ["ru", "en"]:
		loc.set_language(lang)
		FighterPick.last = {}
		FighterPick.sketch = {}
		var fs := FighterSelect.open_over(menu, {"title": tr("БЫСТРЫЙ БОЙ · купол Old NULL Hall")})
		await _frames(5)
		fs.open_sketch()
		await _draw_set(fs, P.human(), "%s_human" % lang)
		await _draw_set(fs, P.multi_arm(), "%s_multi" % lang)
		await _draw_set(fs, hammer, "%s_hammer" % lang)
		fs.close()
		await _frames(5)
	loc.set_language("ru")
	FighterPick.last = {}
	FighterPick.sketch = {}
	get_tree().quit(0)
