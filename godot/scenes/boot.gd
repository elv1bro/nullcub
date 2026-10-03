## Загрузочная сцена — главная сцена проекта: лоадер (scripts/menu/loading.gd) встаёт первым, гараж грузится под ним.
## Аргумент `-- boot_scene=res://…` — другая сцена после лоадера (пробы / отладка).
extends Node

const GARAGE := "res://scenes/menu/garage_menu.tscn"


func _ready() -> void:
	var target := GARAGE
	for a in OS.get_cmdline_user_args():
		if a.begins_with("boot_scene="):
			target = a.get_slice("=", 1)
	Loading.begin("NULL FIGHTING", "включаем телевизор…")
	await Loading.present()
	Loading.change_scene.call_deferred(target, "NULL FIGHTING", "прогреваем бокс 07…")
