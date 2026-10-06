## Кадры камеры прохода по картинке (docs/plan-demo/look/cam.md, ОКОННАЯ проба, --fixed-fps 60): бой «наскоком» (как look_capture
## fight=1), кадры фоторежима посреди боя (фильтры, рамка-обложка), затем нокаут и серия кадров KO-кино: стоп-кадр, облёт, повтор,
## щелчок назад с карточкой KO. Нокаут программный (как в look_cam_probe): толчок жертве от атакующего + take_damage / Match.on_hit
## (крит выключен — уровень «ko»), когда куклы сошлись ближе near_m или вышло ko_t.
## Аргументы (через запятую после --): scene=<res://…tscn> (купол), tag=<имя>, seed=<n>, warm=<с боя до фото>, ko_t=<крайний срок KO>,
## near_m=<м>, photo=0 (без фоторежима), replay=0 (без повтора), push=<м/с толчка>, dmg=<урон нокаута, 24>, seq=<абс. папка> (кадры клипа
## PNG подряд), quit=1 (выйти после кадров; 0 — дождаться итогов).
## Пишет tests/look_shots/<tag>_*.png. Запуск:
##   GODOT_BIN=/usr/local/bin/godot godot/tools/godot_nofocus.sh --path godot --resolution 1600x900 --fixed-fps 60 \
##     res://tests/look_cam_capture.tscn -- "tag=cam,seed=3"
extends Node

const OUT := "res://tests/look_shots/"

var scene_path := "res://scenes/playground_null_hall.tscn"
var tag := "cam"
var warm := 4.0
var ko_t := 12.0
var near_m := 1.9
var photo := true
var replay := true
var push := 7.0
var dmg := 24.0
## seq=<абс. папка>: кадры клипа PNG подряд (секунда до нокаута из кольца + всё кино + 1.5 с после) — для mp4 через ffmpeg.
## Movie Maker (--write-movie) для этого не годится: в нём кадры кино записывались застывшими (06.10, не разбирался).
var seq_dir := ""
var _seq_ring: Array = []
var _seq_live := false
var _seq_n := 0
var quit_after := true
var _inst: Node
var _m: Match
var _kc: KoCam
var _fight := true
var ok := true
var shots: Array = []


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
				"warm": warm = float(kv[1])
				"ko_t": ko_t = float(kv[1])
				"near_m": near_m = float(kv[1])
				"photo": photo = kv[1] != "0"
				"replay": replay = kv[1] != "0"
				"push": push = float(kv[1])
				"dmg": dmg = float(kv[1])
				"seq": seq_dir = kv[1]
				"quit": quit_after = kv[1] != "0"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var look := get_node("/root/Look")
	var lc := get_node("/root/LookCam")
	lc.call("register_items")
	var saved := [look.master, look.checked(&"cam_ko"), look.checked(&"cam_replay"), look.checked(&"cam_photo")]
	look.set_master(true)
	look.set_on(&"cam_ko", true)
	look.set_on(&"cam_replay", replay)
	look.set_on(&"cam_photo", true)
	lc.force = true
	# авто-масштаб графики (DynRes) под чужой нагрузкой и --fixed-fps снижает разрешение 3D — кадры мылятся; на время съёмки выключен
	# без записи в настройки игрока
	var gfx := get_node("/root/Gfx")
	var gfx_auto: bool = gfx.auto_scale
	gfx.auto_scale = false
	gfx.dyn.reset()
	gfx._refresh_scale()
	_inst = (load(scene_path) as PackedScene).instantiate()
	_inst.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_inst)
	for n in _inst.find_children("*", "Node", true, false):
		if n is Match:
			_m = n
			break
	if _m == null:
		print("no Match in ", scene_path)
		get_tree().quit(1)
		return
	_m.crit_enabled = false
	await _wait_phase_fight()
	_kc = _m.get_node_or_null("KoCam") as KoCam
	print("KoCam: ", _kc != null)
	await _secs(warm)
	if photo:
		await _photo_series(lc)
	# нокаут: ждём сближения
	var t := 0.0
	while t < ko_t:
		if _close():
			break
		await get_tree().process_frame
		t += 1.0 / 60.0
	if seq_dir != "":
		DirAccess.make_dir_recursive_absolute(seq_dir)
		for img in _seq_ring:
			_seq_save(img)
		_seq_ring.clear()
		_seq_live = true
	await _do_ko()
	await _ko_series()
	_seq_live = false
	seq_dir = ""
	look.set_on(&"cam_ko", bool(saved[1]))
	look.set_on(&"cam_replay", bool(saved[2]))
	look.set_on(&"cam_photo", bool(saved[3]))
	look.set_master(bool(saved[0]))
	lc.force = false
	gfx.auto_scale = gfx_auto
	gfx.dyn.reset()
	gfx._refresh_scale()
	print("=== %s === %d shots" % ["OK" if ok else "FAIL", shots.size()])
	if quit_after:
		get_tree().quit(0 if ok else 1)


func _process(_dt: float) -> void:
	if seq_dir == "" or _m == null or _m.phase != Match.Phase.FIGHT and not _seq_live:
		return
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	if _seq_live:
		_seq_save(img)
	else:
		_seq_ring.append(img)
		if _seq_ring.size() > 36:
			_seq_ring.pop_front()


func _seq_save(img: Image) -> void:
	img.save_png(seq_dir.path_join("f_%04d.png" % _seq_n))
	_seq_n += 1


func _wait_phase_fight() -> void:
	var n := 0
	while _m.phase != Match.Phase.FIGHT and n < 900:
		await get_tree().process_frame
		n += 1


func _secs(s: float) -> void:
	for i in int(s * 60.0):
		await get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT + "%s_%s.png" % [tag, name])
	var err := img.save_png(path) if img != null else FAILED
	print("  shot %s %s" % [path, "ok" if err == OK else "FAIL"])
	ok = ok and err == OK
	shots.append(path)


func _dolls() -> Array:
	var out: Array = []
	for d in _m.dolls():
		if is_instance_valid(d) and (d as Doll).alive:
			out.append(d)
	return out


func _close() -> bool:
	var ds := _dolls()
	if ds.size() < 2:
		return false
	var a := (ds[0] as Doll).centre_of_mass()
	var b := (ds[1] as Doll).centre_of_mass()
	return Vector2(a.x - b.x, a.y - b.y).length() < near_m


## Наскок (как look_capture fight=1): обе куклы на external_input, летят друг на друга, у цели — рывок.
func _physics_process(_dt: float) -> void:
	if not _fight or _m == null or get_tree().paused:
		return
	var ds := _dolls()
	if ds.size() < 2:
		return
	for i in 2:
		var d := ds[i] as Doll
		var o := ds[1 - i] as Doll
		d.external_input = true
		var dc := d.centre_of_mass()
		var oc := o.centre_of_mass()
		var dx := oc.x - dc.x
		var dy := oc.y - dc.y
		d.input_vec = Vector2(signf(dx) if absf(dx) > 0.05 else 1.0, clampf(dy / 1.5, -1.0, 1.0) if absf(dy) > 0.8 else 0.0)
		var dist := Vector2(dx, dy).length()
		if dist > 1.6 and dist < 4.0 and randf() < 0.05:
			d.request_dash()


func _photo_series(lc: Node) -> void:
	lc.call("toggle_photo")
	await _frames(3)
	var pm := lc.get("photo") as PhotoMode
	if pm == null or not pm.active:
		print("photo mode did not open")
		ok = false
		return
	pm.hint_on = true
	pm.set_filter(0)
	pm.frame_on = false
	pm._apply_layers()
	await _frames(3)
	await _shot("photo_0_enter")
	pm.orbit_by(deg_to_rad(-32.0), deg_to_rad(-8.0), 1.45)
	pm.hint_on = false
	pm.frame_on = true
	pm._apply_layers()
	for i in 4:
		pm.set_filter(i)
		pm._toast.visible = false
		await _frames(3)
		await _shot("photo_%d_%s" % [i + 1, PhotoMode.FILTERS[i]])
	pm.set_filter(0)
	pm.hint_on = true
	pm._apply_layers()
	var p: String = await pm.snapshot()
	print("  photo snapshot: ", p)
	ok = ok and p != ""
	await _frames(2)
	await _shot("photo_6_toast")
	pm.leave()
	await _frames(2)


func _do_ko() -> void:
	var ds := _dolls()
	if ds.size() < 2:
		ok = false
		return
	var a := ds[0] as Doll
	var v := ds[1] as Doll
	_fight = false
	await get_tree().physics_frame
	var dir := v.centre_of_mass() - a.centre_of_mass()
	dir.z = 0.0
	dir = (dir.normalized() if dir.length() > 0.05 else Vector3.RIGHT) + Vector3(0, 0.35, 0)
	for b in v.parts.values():
		(b as RigidBody3D).linear_velocity += dir.normalized() * push
	var pos := v.head().global_position
	v.hp = minf(v.hp, dmg)
	v.take_damage(dmg, a, "Head", pos, -dir.normalized(), "head")
	_m.on_hit(v, a, dmg, "head", pos, 1, false, "", 9.0)
	await get_tree().process_frame


func _ko_series() -> void:
	if _kc == null or not _kc.playing:
		print("KO cinema did not start (stage=%s)" % (_kc.stage if _kc else "no KoCam"))
		ok = false
		await _shot("ko_none")
		return
	await _shot("ko_0_freeze")
	# облёт: u = 0.2 / 0.45 / 0.7 / 1.0
	var marks := [0.2, 0.45, 0.7, 0.98]
	var mi := 0
	while _kc.playing and _kc.stage in ["hold", "orbit"]:
		var u := clampf((_kc._t - KoCam.HOLD_S) / KoCam.ORBIT_S, 0.0, 1.0) if _kc.stage == "orbit" else 0.0
		if mi < marks.size() and u >= float(marks[mi]):
			await _shot("ko_%d_orbit_%02d" % [mi + 1, int(float(marks[mi]) * 100.0)])
			mi += 1
			continue
		await get_tree().process_frame
	# повтор: прогресс 0.05 / 0.5 / 0.85 / 1
	var rmarks := [0.03, 0.5, 0.85, 1.0]
	var ri := 0
	while _kc.playing and _kc.stage == "replay":
		if ri < rmarks.size() and _kc.replay_progress() >= float(rmarks[ri]):
			await _shot("ko_r%d_replay_%02d" % [ri + 1, int(float(rmarks[ri]) * 100.0)])
			ri += 1
			continue
		await get_tree().process_frame
	await _frames(8)
	await _shot("ko_9_back")
	await _frames(40)
	await _shot("ko_9_back_card")
