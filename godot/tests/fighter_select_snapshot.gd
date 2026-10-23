## Снимки «ВЫБОР БОЙЦА» и «Быстрой сборки» (нужно окно; docs/plan-demo/FIGHTER_SELECT.md) на русском и английском — поверх гаража,
## как их видит игрок после «Быстрого боя». Экран ставится прямо (FighterSelect.open_over), без смены сцены — годится для godot_bg.sh:
##   GODOT_BIN=/usr/local/bin/godot godot/tools/godot_bg.sh --path godot --resolution 1920x1080 --fixed-fps 60 \
##     res://tests/fighter_select_snapshot.tscn -- "out_dir=/abs/dir"
## Кадры на язык: roster (выбран «Человек», портреты отрисованы), builder_heavy_head_piston, builder_fast_flail_arms.
## Глазами проверить: карточки не налезают, портреты есть, подписи влезают, панель справа — масса / энергия / детали / ЛКМ.
extends Node

const MENU := "res://scenes/menu/garage_menu.tscn"

var out_dir := "/tmp/fighter_select"


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


func _run() -> void:
	var menu := (load(MENU) as PackedScene).instantiate() as GarageMenu
	menu.dry_run = true
	add_child(menu)
	await _frames(30)
	menu.enter_menu()
	menu.set_focus(1, true)
	await _frames(60)
	var loc := get_node("/root/Loc")
	for lang in ["ru", "en"]:
		loc.set_language(lang)
		FighterPick.last = {}
		var fs := FighterSelect.open_over(menu, {"title": tr("БЫСТРЫЙ БОЙ · купол Old NULL Hall")})
		await _frames(5)
		fs.select(maxi(fs.index_of("preset", "kit_human"), 0), true)
		await _frames(240)   # портреты карточек рендерятся по одному
		await _shot("%s_roster" % lang)
		fs._seed_base = 11
		fs._variant = 0
		fs.open_builder()
		fs.answers = {"style": "heavy", "hitter": "head", "special": "piston"}
		fs.reroll()
		await _frames(90)
		await _shot("%s_builder_heavy_head_piston" % lang)
		fs.answers = {"style": "fast", "hitter": "flail", "special": "arms"}
		fs.q_row = 1
		fs.reroll()
		await _frames(90)
		await _shot("%s_builder_fast_flail_arms" % lang)
		fs.close()
		await _frames(5)
	loc.set_language("ru")
	FighterPick.last = {}
	get_tree().quit(0)
