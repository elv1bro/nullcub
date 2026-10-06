## Кадры вида поля NULL по номерам кадров (look-null, docs/plan-demo/look/null.md; ОКОННАЯ проба, запускать с --fixed-fps 60 — тогда
## кадр = 1/60 с игрового времени, сколько бы ни шла съёмка). В отличие от tests/look_capture.tscn (секунды по часам) серия событий
## (смена поля, удар о мембрану) снимается ровно через заданное число кадров. В кадр съёмки дерево на паузе: «после» — как есть,
## before=1 — тот же кадр с рубильником Look выкл («до»).
## Аргументы (через запятую после --): scene=<res://…tscn> (купол), tag=<имя>, out=<абс. папка> (по умолчанию tests/look_shots/),
## frames=F1;F2;… (номера кадров от старта), before=1, fight=1 (куклы несутся друг на друга, как в look_capture), seed=<n>,
## edge=<x> (обе куклы у края купола на старте), slam=<кадр> (P2 — в мембрану 15 м/с), shift=<кадр> (поле ↘ 0.35G; shift_to=g;dx;dy),
## items=<id>:0|1;… (пункты «ВИД» на время пробы, без записи), cam=x;y;z;tx;ty;tz (неподвижная камера), hud=0,
## bubble=<параметр>:<число>;… (параметры шейдера пузыря — подбор вида), halves=back|front (только одна половина пузыря).
## Запуск: GODOT_BIN=… godot/tools/godot_nofocus.sh --path godot --resolution 1600x900 --fixed-fps 60 res://tests/look_null_shots.tscn --
##   "tag=shift,fight=1,shift=300,frames=296;306;318;330;350;380,before=1"
extends Node

var scene_path := "res://scenes/playground_null_hall.tscn"
var out_dir := "res://tests/look_shots/"
var tag := "null"
var frames: Array[int] = [300]
var before := false
var fight := false
var edge_x := NAN
var slam_f := -1
var shift_f := -1
var shift_to := [0.35, Vector2(0.7, -0.7)]
var items := {}
var bubble_params := {}
var halves := "both"
var cam_spec := ""
var hud := true
var _inst: Node
var _f := 0
var _cam: Camera3D


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
				"out": out_dir = kv[1].trim_suffix("/") + "/"
				"seed": seed(int(kv[1]))
				"before": before = kv[1] == "1"
				"fight": fight = kv[1] == "1"
				"edge": edge_x = float(kv[1])
				"slam": slam_f = int(kv[1])
				"shift": shift_f = int(kv[1])
				"shift_to":
					var v := kv[1].split(";")
					shift_to = [float(v[0]), Vector2(float(v[1]), float(v[2]))]
				"cam": cam_spec = kv[1]
				"hud": hud = kv[1] != "0"
				"halves": halves = kv[1]
				"bubble":
					for it in kv[1].split(";"):
						var p := it.split(":")
						if p.size() == 2:
							bubble_params[p[0]] = float(p[1])
				"items":
					for it in kv[1].split(";"):
						var p := it.split(":")
						if p.size() == 2:
							items[StringName(p[0])] = p[1] == "1"
				"frames":
					frames.clear()
					for s in kv[1].split(";"):
						frames.append(int(s))
	frames.sort()
	var dir := ProjectSettings.globalize_path(out_dir) if out_dir.begins_with("res://") else out_dir
	DirAccess.make_dir_recursive_absolute(dir)
	var look := get_node("/root/Look")
	var master0: bool = look.master
	look.set_master(true)
	var saved := {}
	_inst = (load(scene_path) as PackedScene).instantiate()
	_inst.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_inst)
	for id in items:
		saved[id] = look.checked(id)
		look.set_on(id, items[id])
	if cam_spec != "":
		_make_cam()
	if halves != "both":
		var nl0 := _inst.find_child("NullLook", true, false) as NullLook
		if nl0 != null and nl0.bubble.size() == 2:
			nl0.bubble[0].visible = halves == "back"
			nl0.bubble[1].visible = halves == "front"
	if not bubble_params.is_empty():
		var nl := _inst.find_child("NullLook", true, false) as NullLook
		for b in (nl.bubble if nl != null else []):
			for k in bubble_params:
				(b.material_override as ShaderMaterial).set_shader_parameter(k, bubble_params[k])
	var ok := true
	for target in frames:
		while _f < target:
			if _f == 2 and not is_nan(edge_x):
				_place_edge()
			if _f == slam_f:
				_slam()
			if _f == shift_f:
				_shift()
			if _cam != null:
				_cam.make_current()
			await get_tree().process_frame
			_f += 1
		get_tree().paused = true
		var nl := _inst.find_child("NullLook", true, false) as NullLook
		if nl != null:
			print("  frame %d: time_scale %.3f, shift %.2f, waves %d" % [target, Engine.time_scale, nl.shift_progress(), nl.waves.size()])
		if not hud:
			_set_hud(_inst, false)
		await _frames(3)
		ok = _shot(dir, "%s_f%d_after" % [tag, target]) and ok
		if before:
			look.set_master(false)
			await _frames(3)
			ok = _shot(dir, "%s_f%d_before" % [tag, target]) and ok
			look.set_master(true)
			await _frames(2)
		if not hud:
			_set_hud(_inst, true)
		get_tree().paused = false
	for id in saved:
		look.set_on(id, saved[id])
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


func _dolls() -> Array:
	return _inst.call("dolls") if _inst.has_method("dolls") else get_tree().get_nodes_in_group("dolls")


func _place_edge() -> void:
	var ds := _dolls()
	for i in mini(ds.size(), 2):
		(ds[i] as Node3D).global_position = Vector3(edge_x - 3.0 + 3.0 * i, 5.0, 0.0)


func _slam() -> void:
	var ds := _dolls()
	if ds.size() < 2:
		return
	var d := ds[1] as Doll
	var sx := signf(d.centre_of_mass().x) if absf(d.centre_of_mass().x) > 0.5 else 1.0
	for b in d.parts.values():
		(b as RigidBody3D).linear_velocity = Vector3(15.0 * sx, 1.5, 0.0)
	print("  slam at frame %d" % _f)


func _shift() -> void:
	for a in get_tree().get_nodes_in_group("arena"):
		if _inst.is_ancestor_of(a) and a.has_method("set_field"):
			a.call("set_field", float(shift_to[0]), shift_to[1])
			print("  shift at frame %d" % _f)


func _make_cam() -> void:
	var v := cam_spec.split(";")
	if v.size() < 6:
		return
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_cam.far = 400.0
	_inst.add_child(_cam)
	_cam.global_position = Vector3(float(v[0]), float(v[1]), float(v[2]))
	_cam.look_at(Vector3(float(v[3]), float(v[4]), float(v[5])))
	_cam.make_current()


func _frames(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw


func _shot(dir: String, name: String) -> bool:
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join(name + ".png")
	var err := img.save_png(path)
	print("  shot %s %s" % [path, "ok" if err == OK else "FAIL %d" % err])
	return err == OK


func _set_hud(n: Node, v: bool) -> void:
	for ch in n.get_children():
		if ch is CanvasLayer:
			(ch as CanvasLayer).visible = v
		_set_hud(ch, v)
