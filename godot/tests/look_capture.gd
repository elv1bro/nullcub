## Снимки «до / после» прохода по картинке (LOOK_PASS.md, ОКОННАЯ проба): грузит игровую сцену, ждёт моменты t=…, в каждый момент ставит
## дерево на паузу и снимает ОДИН И ТОТ ЖЕ кадр дважды — с рубильником Look вкл (after) и выкл (before). Пробы вида обязаны применять
## выключение сразу в обработчике Look.changed (не в _process), иначе «до» на паузе не отличится от «после».
## Аргументы (через запятую после --): scene=<res://…tscn> (по умолчанию купол), t=4;7.5 (секунды от старта, через «;»), tag=<имя>,
## seed=<n>, only=after (только «после»), hud=0 (спрятать CanvasLayer-ы игры для чистого кадра), fight=1 (обе куклы сцены на
## external_input и несутся друг на друга с рывком — простой «наскок», чтобы в кадре были удары; сцена должна уметь dolls()).
## Пишет tests/look_shots/<tag>_<t>_after.png / _before.png и печатает пути. Запуск:
##   godot/tools/godot_nofocus.sh --path godot --resolution 1600x900 res://tests/look_capture.tscn -- "tag=hall,t=5;9"
extends Node

const OUT := "res://tests/look_shots/"

var scene_path := "res://scenes/playground_null_hall.tscn"
var times: Array[float] = [5.0]
var tag := "shot"
var only_after := false
var hud := true
var fight := false
var _inst: Node
var _t0 := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		for part in a.split(","):
			var kv := part.split("=", true, 1)
			if kv.size() < 2:
				continue
			match kv[0]:
				"scene": scene_path = kv[1]
				"tag": tag = kv[1]
				"seed": seed(int(kv[1]))
				"only": only_after = kv[1] == "after"
				"hud": hud = kv[1] != "0"
				"fight": fight = kv[1] == "1"
				"champ": _lf_champion.call_deferred(float(kv[1]))
				"t":
					times.clear()
					for s in kv[1].split(";"):
						times.append(float(s))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var look := get_node("/root/Look")
	var master0: bool = look.master
	look.set_master(true)
	_inst = (load(scene_path) as PackedScene).instantiate()
	_inst.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_inst)
	_t0 = Time.get_ticks_msec()
	var ok := true
	for t in times:
		while (Time.get_ticks_msec() - _t0) / 1000.0 < t:
			await get_tree().process_frame
		get_tree().paused = true
		if not hud:
			_set_hud(_inst, false)
		await _frames(4)
		ok = _shot("%s_%s_after" % [tag, str(t)]) and ok
		if not only_after:
			look.set_master(false)
			await _frames(4)
			ok = _shot("%s_%s_before" % [tag, str(t)]) and ok
			look.set_master(true)
			await _frames(2)
		if not hud:
			_set_hud(_inst, true)
		get_tree().paused = false
	look.set_master(master0)
	print("=== %s ===" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _physics_process(_dt: float) -> void:
	if not fight or _inst == null or get_tree().paused or not _inst.has_method("dolls"):
		return
	var ds: Array = _inst.dolls()
	if ds.size() < 2:
		return
	for i in 2:
		var d := ds[i] as Doll
		var o := ds[1 - i] as Doll
		if not is_instance_valid(d) or not is_instance_valid(o) or not d.alive or not o.alive:
			continue
		d.external_input = true
		var dc := d.centre_of_mass()
		var oc := o.centre_of_mass()
		var dx := oc.x - dc.x
		var dy := oc.y - dc.y
		d.input_vec = Vector2(signf(dx) if absf(dx) > 0.05 else 1.0, clampf(dy / 1.5, -1.0, 1.0) if absf(dy) > 0.8 else 0.0)
		var dist := Vector2(dx, dy).length()
		if dist > 1.6 and dist < 4.0 and randf() < 0.05:
			d.request_dash()


func _frames(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw


func _shot(name: String) -> bool:
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT + name + ".png")
	var err := img.save_png(path)
	print("  shot %s (%dx%d) %s" % [path, img.get_width(), img.get_height(), "ok" if err == OK else "FAIL %d" % err])
	return err == OK


func _set_hud(n: Node, v: bool) -> void:
	for ch in n.get_children():
		if ch is CanvasLayer:
			(ch as CanvasLayer).visible = v
		_set_hud(ch, v)


## look-frame (docs/plan-demo/look/frame.md): champ=<с> — через столько секунд вызвать чемпиона лиги (купол, как клавиша K): кукла
## кита в кадре (лак, свечение ядра и суставов).
func _lf_champion(at: float) -> void:
	await get_tree().create_timer(maxf(at, 0.1)).timeout
	var arena := get_tree().get_first_node_in_group("arena")
	if arena != null and arena.has_method("call_champion"):
		arena.call("call_champion")
