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
var _scale3d := 0.0
var _faces := 0
var _ko_at := -1.0


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
				"look": _look_items(kv[1])
				"scale3d": _scale3d = float(kv[1])
				"faces": _faces = int(kv[1])
				"ko": _ko_at = float(kv[1])
				"t":
					times.clear()
					for s in kv[1].split(";"):
						times.append(float(s))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var look := get_node("/root/Look")
	var master0: bool = look.master
	look.set_master(true)
	if _scale3d > 0.0:
		_apply_scale3d()
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
	if _ko_at >= 0.0 and _inst != null and not get_tree().paused and (Time.get_ticks_msec() - _t0) / 1000.0 >= _ko_at:
		_ko_at = -1.0
		_force_ko()
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
	if _faces > 0:
		_face_crops(img, name)
	return err == OK


func _set_hud(n: Node, v: bool) -> void:
	for ch in n.get_children():
		if ch is CanvasLayer:
			(ch as CanvasLayer).visible = v
		_set_hud(ch, v)


## look=<id>:1;<id>:0 — галочки пунктов «ВИД» до загрузки сцены (пункты, выключенные по умолчанию, — например бойцы-наборы
## look-faces). Не пишет user://look.cfg. Рубильник «до / после» на них действует как на остальные.
func _look_items(spec: String) -> void:
	var look := get_node("/root/Look")
	for it in spec.split(";"):
		var kv := it.split(":")
		if kv.size() == 2:
			look.call("set_on", StringName(kv[0]), kv[1] == "1")


## scale3d=<0..1> — масштаб 3D корневого вьюпорта (Gfx не перебивает выставленный пробой): 1 — снимок без мыла DynRes / Retina.
func _apply_scale3d() -> void:
	var gfx := get_node_or_null("/root/Gfx")
	if gfx != null:
		gfx.set("auto_scale", false)   # DynRes не перебьёт (поле, не set_auto_scale — тот пишет user://gfx.cfg)
	var win := get_window()
	win.scaling_3d_scale = clampf(_scale3d, 0.25, 2.0)
	win.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR


## faces=<px> — ещё и крупные планы голов: квадрат px × px вокруг головы каждой куклы сцены (dolls()), <имя>_face<i>.png (look-faces).
func _face_crops(img: Image, name: String) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _inst == null or not _inst.has_method("dolls"):
		return
	var i := 0
	for d in _inst.dolls():
		var head := (d as Doll).parts.get("Head") as Node3D if is_instance_valid(d) else null
		if head == null or cam.is_position_behind(head.global_position):
			continue
		var p := cam.unproject_position(head.global_position + head.global_basis.y * 0.15)
		var vs := get_viewport().get_visible_rect().size
		var k := Vector2(img.get_width(), img.get_height()) / vs
		var c := Vector2i(p * k)
		var h := _faces / 2
		var r := Rect2i(c - Vector2i(h, h), Vector2i(_faces, _faces)).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
		if r.size.x < 8 or r.size.y < 8:
			continue
		var crop := img.get_region(r)
		var path := ProjectSettings.globalize_path(OUT + "%s_face%d.png" % [name, i])
		crop.save_png(path)
		i += 1


## ko=<t> — в момент t вторая кукла сцены (dolls()) выбита первой (Doll.knock_out с атакующим): кадры KO и победы без долгого боя.
func _force_ko() -> void:
	if not _inst.has_method("dolls"):
		return
	var ds: Array = _inst.dolls()
	if ds.size() < 2 or not is_instance_valid(ds[0]) or not is_instance_valid(ds[1]):
		return
	var v := ds[1] as Doll
	if v.alive:
		v.knock_out(ds[0] as Doll, {"kind": "head", "part": "Head", "damage": 40.0})
