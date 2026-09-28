## Перф-проба площадки «Свалка» (scenes/playground_scrap.tscn) — вся логика и ключи tests/perf_probe.gd (наследование, без
## копии): vsync off, FPS по секундам, TIME_PROCESS, draw calls, переключатели ssao/ssil/fog/vfog/shadow/… одной строкой.
## perf_probe знает только scene=ruins|workshop|void (константа SCENES, её правит другая сессия), поэтому здесь scene_id =
## "scrap" и, пока ключа "scrap" в SCENES нет, загруженная сцена Свалки подменяет в кэше ресурсов путь SCENES["ruins"]
## (Resource.take_over_path): родитель грузит SCENES.get(scene_id, SCENES["ruins"]) и получает Свалку. Только в этом процессе.
## Свой ключ: wide=1 — камера на полном отъезде (min_half_height 10.5: вся арена в кадре, больше всего объектов), иначе
## как у других арен — куклы стоят на спавнах, камера на ближнем зуме.
## Запуск: godot --path . --resolution 1920x1080 --position 100,100 res://tests/scrap_perf_probe.tscn -- "secs=10,min_fps=55"
extends "res://tests/perf_probe.gd"

const SCRAP_SCENE := "res://scenes/playground_scrap.tscn"

var _scrap_ps: PackedScene          # держим ссылку: иначе ресурс освободится и кэш по пути забудет подмену


func _ready() -> void:
	scene_id = "scrap"
	if not SCENES.has("scrap"):
		_scrap_ps = load(SCRAP_SCENE)
		_scrap_ps.take_over_path(SCENES["ruins"])
	super._ready()
	if not (pg.get("arena") is ScrapArena):
		push_error("scrap_perf_probe: загружена не Свалка")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if "wide=1" in arg.split(","):
			(pg.get_node("Camera") as DynamicCamera).min_half_height = 10.5
			print("wide camera")
