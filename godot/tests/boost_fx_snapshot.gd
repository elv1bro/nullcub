## Кадры эффектов ускорения и раскрутки по пресетам BoostFx (COMBAT_CHARGE.md, «лёгкие варианты»): Void 1280×720, на каждый пресет два кадра
## обрезкой вокруг P1 — «ускорение» (разбег по полу, Shift держится ~0.6 с) и «раскрутка» (в воздухе, Space + D ~0.7 с). Нужно окно.
## Пишет PNG (boost_<ряд>_<пресет>.png) и boost_fx_report.json в out_dir. Лист с подписями собирает tests/tools/…не нужен: Python/PIL по именам.
## Запуск: godot --path . --resolution 1280x720 --fixed-fps 60 res://tests/boost_fx_snapshot.tscn -- "out_dir=<абс. папка>"
extends Node3D

const VOID_SCENE := "res://scenes/playground_void.tscn"
const CROP := Vector2i(960, 540)   # вырезка вокруг P1, затем сжатие до 640×360 (линии скорости идут до краёв экрана)
const OUT := Vector2i(640, 360)
const RUN_FRAMES := 38
const SPIN_FRAMES := 44

var out_dir := ""
var pg: Node3D
var match_node: Match
var hold_boost := false
var hold_spin := false
var hold_vec := Vector2.ZERO
var report := {"ok": true, "shots": []}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "out_dir":
				out_dir = p[1]
	pg = (load(VOID_SCENE) as PackedScene).instantiate()
	match_node = pg.get_node("Match") as Match
	match_node.countdown_s = 0.0
	add_child(pg)
	for l in pg.find_children("*", "Label", true, false):
		if (l as Label).text.begins_with("P1:"):
			(l as Label).visible = false   # строка подсказок управления внизу — в кадры не нужна
	_run()


func p1() -> Doll:
	return pg.get_node("P1") as Doll


func p2() -> Doll:
	return pg.get_node("P2") as Doll


func _physics_process(_delta: float) -> void:
	var d := p1()
	if d == null:
		return
	d.external_input = true
	d.input_vec = hold_vec
	if hold_boost:
		d.request_dash()
	if hold_spin:
		d.request_spin()


func frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _place(d: Doll, x: float, dy: float = 0.0) -> void:
	var off := x - d.centre_of_mass().x
	for b in d.parts.values():
		(b as RigidBody3D).global_position.x += off
		(b as RigidBody3D).global_position.y += dy
		(b as RigidBody3D).linear_velocity = Vector3.ZERO
		(b as RigidBody3D).angular_velocity = Vector3.ZERO


func _shot(key: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var cam := get_viewport().get_camera_3d()
	var sp := cam.unproject_position(p1().centre_of_mass()) if cam != null else Vector2(640, 360)
	var c := Vector2i(int(sp.x) - 120, int(sp.y) - 20)   # след остаётся позади бегущего вправо — центр чуть левее
	var r := Rect2i(c.x - CROP.x / 2, c.y - CROP.y / 2, CROP.x, CROP.y)
	r.position.x = clampi(r.position.x, 0, img.get_width() - CROP.x)
	r.position.y = clampi(r.position.y, 0, img.get_height() - CROP.y)
	var crop := img.get_region(r)
	crop.resize(OUT.x, OUT.y, Image.INTERPOLATE_LANCZOS)
	var path := out_dir.path_join("boost_%s.png" % key)
	crop.save_png(path)
	report["shots"].append({"key": key, "label": label, "path": path, "crop": [r.position.x, r.position.y]})
	print("  shot ", key, " ", label)


func _run() -> void:
	await frames(6)
	p2().external_input = true
	p2().input_vec = Vector2.ZERO
	var fi := FxPreset.current
	print("FX preset ", fi, ", BoostFx presets ", BoostFx.PRESET_ORDER)
	for name in BoostFx.PRESET_ORDER:
		BoostFx.set_preset(name, get_tree())
		var label := String(BoostFx.values(name).get("label", name))
		# --- ускорение: рывок в воздухе
		hold_boost = false
		hold_spin = false
		hold_vec = Vector2.ZERO
		_place(p2(), 6.5)
		_place(p1(), -5.0, 1.1)
		p1().reset_charge()
		await frames(40)
		hold_vec = Vector2(1.0, 0.12)
		hold_boost = true
		await frames(RUN_FRAMES)
		await _shot("run_" + name, label)
		hold_boost = false
		hold_vec = Vector2.ZERO
		await frames(60)
		# --- рывок у пола (пыль): только для пресетов, где пыль есть, и для сравнения без эффекта
		if name == "off" or name == "dust" or name == "all":
			_place(p1(), -5.0, 0.0)
			p1().reset_charge()
			await frames(50)
			hold_vec = Vector2(1.0, -0.35)
			hold_boost = true
			await frames(RUN_FRAMES)
			await _shot("floor_" + name, label)
			hold_boost = false
			hold_vec = Vector2.ZERO
			await frames(60)
		# --- раскрутка: в воздухе, катясь вправо
		_place(p1(), -1.5, 1.0)
		p1().reset_charge()
		await frames(8)
		hold_vec = Vector2(1.0, 0.0)
		hold_spin = true
		await frames(SPIN_FRAMES)
		await _shot("spin_" + name, label)
		hold_spin = false
		hold_vec = Vector2.ZERO
		await frames(70)
	BoostFx.set_preset(BoostFx.PRESET_DEFAULT, get_tree())
	var f := FileAccess.open(out_dir.path_join("boost_fx_report.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
	get_tree().quit(0)
