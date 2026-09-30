## Витрина и проверка арены 01 «Old NULL Hall» (docs/plan-demo/ART_NULL.md, лист 5). Нужен рендер (окно; в контейнере — xvfb-run):
##   godot --path godot --resolution 1600x900 res://tests/null_hall_snapshot.tscn -- "sheet=res://../docs/plan-demo/img/null-hall-v1.png"
## Кадры: 1 — игровая камера по листу камеры (вариант 4: часть арены, боец 8–12 % высоты кадра), 2 — весь зал,
## 3 — удар о мембрану: кукла P2 влетает в правый бок купола (поле ↗ 0.24 G), лента прогибается и светится,
## 4 — трибуна крупно: зрители-спрайты (crowd= — полный кадр отдельно). Две куклы (doll.tscn, заморожены) на спавнах, N0 висит у края поля.
## Проверки (exit 1): модули на месте (33 секции трибун, ≥ 1000 зрителей, ≥ 8 якорей и эмиттеров, 2 ворот, экран и табло),
## материалы ролей пришли из assets/materials/null_hall, табло показывает гравитацию и обновляется при смене поля,
## рост бойца в игровом кадре 8–12 % высоты. Отчёт — tests/null_hall_snapshot_report.json.
extends Node3D

const HALL := preload("res://scenes/arena/null_hall.tscn")
const DOLL := preload("res://scenes/doll/doll.tscn")
const N0 := preload("res://scenes/n0/n0.tscn")

var checks: Array = []
var args := {}
var cam: Camera3D
var hall: NullHallArena
var dolls: Array[Node3D] = []
var _last_crowd: Image


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		for kv in String(a).split(","):
			var p := String(kv).split("=")
			if p.size() == 2:
				args[p[0]] = p[1]
	hall = HALL.instantiate() as NullHallArena
	add_child(hall)
	var spawns := hall.spawn_points()
	for i in range(2):
		var d := DOLL.instantiate() as Node3D
		add_child(d)
		d.global_position = spawns[i] + Vector3(0.0, 2.0 + i * 1.5, 0.0)
		dolls.append(d)
	var n0 := N0.instantiate() as N0Drone
	add_child(n0)
	n0.position = Vector3(-11.5, 13.0, 1.0)
	n0.rotation_degrees.y = 25.0
	n0.expression = "excited"
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.far = 300.0
	add_child(cam)
	cam.current = true
	await _frames(2)
	for d in dolls:   # позу держим: физику кукол выключаем после спавна
		for b in d.find_children("*", "RigidBody3D", true, false):
			(b as RigidBody3D).freeze = true
	await _run()


func _run() -> void:
	_check_structure()
	# кадр 1: игровая камера
	cam.position = Vector3(0.0, 7.5, 24.0)
	cam.look_at(Vector3(0.0, 7.0, 0.0))
	await _frames(8)
	var img1 := _grab()
	var frac := _doll_screen_fraction(dolls[0])
	_check("fighter_8_12_pct", frac >= 0.08 and frac <= 0.12, "%.3f of frame height" % frac)
	# кадр 2: весь зал
	cam.position = Vector3(0.0, 14.0, 52.0)
	cam.look_at(Vector3(0.0, 11.0, -6.0))
	await _frames(6)
	var img2 := _grab()
	# кадр 3: удар о мембрану — кукла P2 влетает в правый бок купола, лента прогибается и светится
	hall.set_field(0.24, Vector2(0.7, 0.7))
	var d2 := dolls[1] as Doll
	for b in d2.parts.values():
		(b as RigidBody3D).freeze = false
	d2.global_position = Vector3(9.0, 6.0, 0.0)
	await _frames(2)
	for b in d2.parts.values():
		(b as RigidBody3D).linear_velocity = Vector3(15.0, 1.0, 0.0)
	cam.position = Vector3(8.0, 8.5, 17.0)
	cam.look_at(Vector3(14.0, 7.0, 0.0))
	var stretch := 0.0
	for i in range(60):
		await get_tree().physics_frame
		stretch = maxf(stretch, hall.field.max_stretch_seen)
		if hall.field.max_stretch_seen > 0.6 and i > 10:
			break
	await _frames(1)
	var img3 := _grab()
	_check("membrane_stretched_in_frame", stretch > 0.4, "stretch %.2f m" % stretch)
	await _frames(int(Tuning.NULL_FIELD_BLEND_S * 60.0) + 5)
	# кадр 4: трибуна крупно — зрители-спрайты (модульные существа из кита), толпа болеет
	hall.excite(1.0)
	cam.position = Vector3(-3.0, 7.5, -10.0)
	cam.look_at(Vector3(-4.5, 6.0, -24.0))
	await _frames(20)
	var img4 := _grab()
	_last_crowd = img4.duplicate()
	var lbl := hall.find_children("*", "Label3D", true, false)
	var grav_texts: Array = []
	for l in lbl:
		if (l as Label3D).is_in_group("null_hall_gravity"):
			grav_texts.append((l as Label3D).text)
	_check("gravity_board_updates", grav_texts.size() >= 2 and grav_texts.all(func(t): return t == "↗ 0.24G"), str(grav_texts))
	# лист: 1 сверху во всю ширину, 2, 3 и 4 снизу по трети
	var w := img1.get_width()
	var h := img1.get_height()
	var sw := w / 3
	var sh := h / 3
	for im in [img2, img3, img4]:
		(im as Image).resize(sw, sh, Image.INTERPOLATE_LANCZOS)
	var sheet := Image.create(w, h + sh, false, Image.FORMAT_RGB8)
	sheet.blit_rect(img1, Rect2i(Vector2i.ZERO, img1.get_size()), Vector2i.ZERO)
	sheet.blit_rect(img2, Rect2i(0, 0, sw, sh), Vector2i(0, h))
	sheet.blit_rect(img3, Rect2i(0, 0, sw, sh), Vector2i(sw, h))
	sheet.blit_rect(img4, Rect2i(0, 0, sw, sh), Vector2i(sw * 2, h))
	img4.resize(w, h, Image.INTERPOLATE_LANCZOS)
	var crowd_out := String(args.get("crowd", ""))
	if crowd_out != "":
		var ci := _last_crowd
		ci.save_png(crowd_out)
	var out := String(args.get("sheet", "res://tests/null_hall_snapshot.png"))
	var err := sheet.save_png(ProjectSettings.globalize_path(out) if out.begins_with("res://") else out)
	_check("sheet_saved", err == OK, out)
	_finish()


func _check_structure() -> void:
	var stands := hall.get_node("Stands").get_child_count()
	_check("stand_segments", stands == 33, "%d" % stands)
	var crowd := 0
	for mmi in hall.get_node("Crowd").get_children():
		var mm := (mmi as MultiMeshInstance3D).multimesh
		crowd += mm.instance_count if mm != null else 0
	_check("crowd_1000", crowd >= 1000, "%d spectators" % crowd)
	var anchors := hall.membrane_anchors().size()
	_check("membrane_anchors", anchors >= 8, "%d" % anchors)
	_check("gates", hall.get_node_or_null("Structure/GateA") != null and hall.get_node_or_null("Structure/GateB") != null, "GateA/GateB")
	_check("boards", hall.get_node_or_null("Boards/BigScreen") != null and hall.get_node_or_null("Boards/Scoreboard") != null,
		"BigScreen/Scoreboard")
	_check("spawns", hall.spawn_points().size() == 4, "%d" % hall.spawn_points().size())
	var flat: Array = []
	var surfaces := 0
	for mi in hall.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null or (mi as MeshInstance3D).material_override != null:
			continue   # лента мембраны — шейдер (material_override), не материал роли
		for i in range(mesh.get_surface_count()):
			surfaces += 1
			var m := mesh.surface_get_material(i)
			if m == null or not String(m.resource_path).begins_with("res://assets/materials/null_hall/"):
				if flat.size() < 6:
					flat.append("%s:%s" % [mi.name, m.resource_name if m != null else "null"])
	_check("role_materials", flat.is_empty(), "%d surfaces, flat: %s" % [surfaces, flat])
	var g := hall.gravity_text()
	_check("gravity_text", g == "↓ 0.20G", g)   # поле по умолчанию = проектная гравитация (Tuning.GRAVITY)


## Доля высоты кадра, которую занимает кукла (по AABB её мешей в экранных координатах).
func _doll_screen_fraction(d: Node3D) -> float:
	var lo := INF
	var hi := -INF
	for vi in d.find_children("*", "VisualInstance3D", true, false):
		var v := vi as VisualInstance3D
		var bb := v.global_transform * v.get_aabb()
		for k in range(8):
			var sp := cam.unproject_position(bb.get_endpoint(k))
			lo = minf(lo, sp.y)
			hi = maxf(hi, sp.y)
	return (hi - lo) / get_viewport().get_visible_rect().size.y


func _grab() -> Image:
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _check(id: String, ok: bool, info: String) -> void:
	checks.append({"id": id, "ok": ok, "info": info})
	print("%s %s — %s" % ["PASS" if ok else "FAIL", id, info])


func _finish() -> void:
	var ok := true
	for c in checks:
		ok = ok and bool(c["ok"])
	var f := FileAccess.open("res://tests/null_hall_snapshot_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"ok": ok, "checks": checks}, "  "))
	f.close()
	print("null_hall_snapshot: %s (%d checks)" % ["OK" if ok else "FAIL", checks.size()])
	get_tree().quit(0 if ok else 1)
