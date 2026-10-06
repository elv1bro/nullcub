## Кадры оформления «эфира Лиги» (docs/plan-demo/look/show.md, ОКОННАЯ проба — только через tools/godot_nofocus.sh): как look_capture
## (сцена, моменты t, на паузе один и тот же кадр «после» / «до» по рубильнику Look), плюс то, что в обычной игре надо ждать:
##   final=1      — свет финала (последние 10 с) включить сразу;     flash=1 — вспышки камер в толпе сейчас;
##   wave=0.4     — «волна» толпы в точке 0..1;                      skin=broadcast|neon|led — скин HUD (без записи настроек);
##   iso=<id>     — «до» = выключен только этот пункт (а не всё);    stinger=0.1;0.2;… — серия кадров заставки поверх сцены в момент t;
##   fight=1      — куклы несутся друг на друга (как look_capture);   hud=0 — без слоёв HUD; only=after.
## Файлы — tests/look_shots/<tag>_<t>_after.png / _before.png, серия заставки — <tag>_sting_<s>.png.
##   godot/tools/godot_nofocus.sh --path godot --resolution 1600x900 res://tests/look_show_snapshot.tscn -- "tag=final,t=6,fight=1,final=1"
extends Node

const OUT := "res://tests/look_shots/"

var scene_path := "res://scenes/playground_null_hall.tscn"
var times: Array[float] = [5.0]
var tag := "show"
var only_after := false
var hud := true
var fight := false
var final := false
var flash := false
var wave := -1.0
var wave_width := -1.0
var iso := ""
var stinger_t: Array[float] = []
var _inst: Node
var _look: Node


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
				"final": final = kv[1] == "1"
				"flash": flash = kv[1] == "1"
				"wave": wave = float(kv[1])
				"wave_w": wave_width = float(kv[1])
				"iso": iso = kv[1]
				"skin": HudSkin.set_skin(kv[1], false)
				"t":
					times.clear()
					for s in kv[1].split(";"):
						times.append(float(s))
				"stinger":
					for s in kv[1].split(";"):
						stinger_t.append(float(s))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_look = get_node("/root/Look")
	var master0: bool = _look.master
	_look.set_master(true)
	_inst = (load(scene_path) as PackedScene).instantiate()
	_inst.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_inst)
	var t0 := Time.get_ticks_msec()
	var ok := true
	for t in times:
		while (Time.get_ticks_msec() - t0) / 1000.0 < t:
			await get_tree().process_frame
		get_tree().paused = true
		if not hud:
			_set_hud(_inst, false)
		_force(true)
		await _frames(4)
		if not stinger_t.is_empty():
			ok = await _stinger_series() and ok
		else:
			ok = _shot("%s_%s_after" % [tag, str(t)]) and ok
			if not only_after:
				if iso != "":
					_look.set_on(StringName(iso), false)
				else:
					_look.set_master(false)
				_redraw(_inst)
				await _frames(4)
				ok = _shot("%s_%s_before" % [tag, str(t)]) and ok
				if iso != "":
					_look.set_on(StringName(iso), true)
				else:
					_look.set_master(true)
				_redraw(_inst)
				_force(true)
				await _frames(2)
		if not hud:
			_set_hud(_inst, true)
		get_tree().paused = false
	_look.set_master(master0)
	print("=== %s ===" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


## Состояния эфира, которых в игре надо ждать (свет финала, вспышки, волна) — включить сразу.
func _force(on: bool) -> void:
	var hs := _inst.find_child("HallShow", true, false) as HallShow
	if hs == null:
		return
	if final:
		hs.force_final(on)
	if flash:
		hs.flash_now(1.0 if on else 0.0)
	if wave >= 0.0:
		hs.wave_at(wave)
	if wave_width > 0.0 and hs._crowd != null:
		hs._crowd.set_shader_parameter("show_wave_width", wave_width)


func _stinger_series() -> bool:
	var st := get_node("/root/Loading/LeagueShow").get("stinger") as LeagueStinger
	st.playing = true
	st.visible = true
	var ok := true
	for s in stinger_t:
		st.seek(s)
		await _frames(3)
		ok = _shot("%s_sting_%s" % [tag, str(s)]) and ok
	st.stop()
	return ok


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


## Холсты HUD (стычка рисует почти всё в _draw, перерисовка — из _process) на паузе сами не перерисуются — попросить.
func _redraw(n: Node) -> void:
	if n is CanvasItem:
		(n as CanvasItem).queue_redraw()
	for ch in n.get_children():
		_redraw(ch)


func _set_hud(n: Node, v: bool) -> void:
	for ch in n.get_children():
		if ch is CanvasLayer:
			(ch as CanvasLayer).visible = v
		_set_hud(ch, v)
