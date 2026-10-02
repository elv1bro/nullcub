## Кадры сокрушительного удара (оконно, 1280×720, --fixed-fps 60 — часы кинематографа детерминированы, захват кадра их не сбивает).
## Площадка Void (чёрное поле): P1 — клён doll.tscn, P2 — орех doll_dark.tscn, стоят вплотную; на t = hit_t с жертве (victim=p1|p2)
## засчитывается удар в голову 26 HP (take_damage), CritLaunch.apply (если ядро есть) и HitFxDirector.play(ctx tier crit)
## (или CritCinematic.play без директора). Снимаются кадры на 0, 33, 120, 250, 450, 640, 900, 1250 мс таймлайна
## (подпись «t = … мс» в углу), лист 4 × 2 по 640×360 → sheet (по умолчанию docs/plan-demo/img/crit-sequence-v1.png, ≤ 2 МБ),
## полные кадры — в out (по умолчанию scratchpad hitfx/). ko=1 — жертва с hp 5 (ko_crit). Печатает JSON, exit 0/1.
## Запуск: gtimeout 120 /usr/bin/arch -arm64 /usr/local/bin/godot --path <godot> --fixed-fps 60 --resolution 1280x720 --position 100,100
##   --always-on-top res://tests/crit_snapshot.tscn -- "victim=p1,sheet=res://../docs/plan-demo/img/crit-sequence-v1.png"
## v2: scene=void|ruins|workshop (площадка), part=Head|LowerLeg_L|… (ударенная деталь; нет у куклы — голова).
## v3 (HIT_FX §12.1, §12.3): кадры 0 / 70 / 130 / 250 / 450 / 640 / 900 / 1250 мс (70 и 130 — маркер точки удара до и после ката);
##   corner=1 — перед ударом жертва под потолком у правой стены Void (ЦМ 3.6, 5.6), атакующий левее-ниже (2.4, 5.0), удар вдоль (1, 0.55):
##   крит-отлёт в правый верхний угол, как в клипе боя v2 (там жертва висела под полосой HP P2) — видно safe-area камеры.
extends Node3D

const SCENES := {"void": "res://scenes/playground_void.tscn", "ruins": "res://scenes/playground.tscn",
	"workshop": "res://scenes/playground_workshop.tscn"}
const SHOTS_MS := [0.0, 70.0, 130.0, 250.0, 450.0, 640.0, 900.0, 1250.0]
const CELL := Vector2i(640, 360)
const COLS := 4
const MAX_SHEET_BYTES := 2 * 1024 * 1024

var cfg := {"victim": "p1", "hit_t": 1.6, "ko": "0", "scene": "void", "part": "Head", "corner": "0",
	"out": "/private/tmp/claude-501/-Users-eliseyvrublevskiy-Projects-ragdoll-faces/e01d6aa4-0c2f-4ed8-9133-35a39f9ccd48/scratchpad/hitfx",
	"sheet": "res://../docs/plan-demo/img/crit-sequence-v1.png"}
var pg: Node3D
var match_node: Match
var cc: CritCinematic
var director: Node
var victim: Doll
var attacker: Doll
var label: Label
var t := 0.0
var fired := false
var shot_i := 0
var shots: Array = []          # [{ms, img}]
var phases: Dictionary = {}
var busy := false
var report := {"ok": true, "checks": []}


func _ready() -> void:
	HitJuice.impact_style = "cartoon"   # проба проверяет стиль «мульт» (звезда, кольца, послеобразы); «серьёзный» — juice_probe (§13)
	HitJuice.outline_on = false   # обводка бойцов (B) — свои узлы на мешах кукол; проба считает узлы и оверлеи частей
	process_priority = 2000   # после CritCinematic (1000): кадр снимается с уже применённым состоянием таймлайна
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and cfg.has(p[0]):
				cfg[p[0]] = p[1]
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	pg = (load(String(SCENES.get(String(cfg["scene"]), SCENES["void"]))) as PackedScene).instantiate()
	add_child(pg)
	pg.set_process_unhandled_input(false)
	get_viewport().gui_disable_input = true
	match_node = pg.get_node("Match")
	match_node.countdown_s = 0.0
	var ui := pg.get_node_or_null("UI") as CanvasLayer
	if ui != null:
		ui.visible = false
	var p1: Doll = pg.get_node("P1")
	var p2: Doll = pg.get_node("P2")
	p1.external_input = true
	p2.external_input = true
	p2.position = p1.position + Vector3(1.05, 0.0, 0.0)
	victim = p1 if cfg["victim"] == "p1" else p2
	attacker = p2 if victim == p1 else p1
	var cl := CanvasLayer.new()
	cl.layer = 100
	add_child(cl)
	label = Label.new()
	label.position = Vector2(28, 24)
	label.add_theme_font_size_override("font_size", 40)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 8)
	label.visible = false
	cl.add_child(label)


func check(id: String, ok: bool, value: Variant = null, limit: Variant = null) -> void:
	report["checks"].append({"id": id, "ok": ok, "value": value, "limit": limit})
	if not ok:
		report["ok"] = false


func _find_cinematic() -> void:
	director = match_node.get_node_or_null("HitFxDirector")
	if director != null and director.has_method("_ensure_cinematic"):
		var n: Variant = director.call("_ensure_cinematic")
		if n is CritCinematic:
			cc = n
	if cc == null and director != null:
		for c in director.get_children():
			if c is CritCinematic:
				cc = c
	if cc == null:
		cc = CritCinematic.attach(self)
		director = null
	cc.phase.connect(func(n: String, ms: float) -> void: phases[n] = ms)


func _hit() -> void:
	_find_cinematic()
	var pn := String(cfg["part"]) if victim.parts.has(String(cfg["part"])) else "Head"
	if cfg["corner"] == "1":
		for pr in [[victim, Vector3(3.6, 5.6, 0.0)], [attacker, Vector3(2.4, 5.0, 0.0)]]:
			var d: Doll = pr[0]
			var off: Vector3 = (pr[1] as Vector3) - d.centre_of_mass()
			off.z = 0.0
			for b in d.parts.values():
				(b as RigidBody3D).global_position += off
				(b as RigidBody3D).linear_velocity = Vector3.ZERO
				(b as RigidBody3D).angular_velocity = Vector3.ZERO
	var head := victim.parts[pn] as RigidBody3D
	var dir := Vector3(-1.0 if attacker.global_position.x > victim.global_position.x else 1.0, 0.3, 0.0).normalized()
	if cfg["corner"] == "1":
		dir = Vector3(1.0, 0.55, 0.0).normalized()
	var pos := head.global_position - dir * 0.11
	if cfg["ko"] == "1":
		victim.hp = 5.0
	var kind := "head" if pn == "Head" else "body"
	victim.take_damage(26.0, attacker, pn, pos, -dir, kind)
	var ctx := {
		"victim": victim, "attacker": attacker, "damage": 26.0, "kind": kind, "part": pn, "part_base": Doll.part_base_name(pn),
		"striker": "Hand_R", "position": pos, "normal": -dir, "dir": dir, "speed": 9.0, "weapon_id": "", "combo": 1,
		"double_blow": false, "dash": true, "score": 37.4, "tier": "ko_crit" if not victim.alive else "crit",
		"is_ko": not victim.alive, "hp_after": victim.hp, "fight_time": match_node.fight_time, "sd_mult": 1.0,
		"colour": Tuning.PLAYER_COLORS[clampi(victim.player_index, 0, 3)],
	}
	if ResourceLoader.exists("res://scripts/core/crit_launch.gd"):
		var cl: Script = load("res://scripts/core/crit_launch.gd")
		cl.call("apply", ctx, 1.0)
	else:
		for b in victim.parts.values():
			(b as RigidBody3D).linear_velocity += dir * 6.0
	var ok := false
	if director != null and director.has_method("play"):
		director.call("play", ctx)
		ok = cc.is_playing()
	else:
		ok = cc.play(ctx)
	check("play_started", ok, ok, true)
	report["host"] = "director" if director != null else "probe"


func _process(delta: float) -> void:
	if busy:
		return
	t += delta / maxf(Engine.time_scale, 1e-4)
	if not fired:
		if t >= float(cfg["hit_t"]):
			fired = true
			_hit()
		return
	if shot_i >= SHOTS_MS.size():
		return
	if not cc.is_playing() and not phases.has("freeze"):
		return   # таймлайн стартует в следующем кадре
	var ms := cc.elapsed_ms() if cc.is_playing() else 1300.0
	if ms + 8.4 >= float(SHOTS_MS[shot_i]):
		busy = true
		label.text = "t = %d ms" % int(round(ms))
		label.visible = true
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		shots.append({"ms": ms, "target": SHOTS_MS[shot_i], "img": img})
		DirAccess.make_dir_recursive_absolute(String(cfg["out"]))
		img.save_png(String(cfg["out"]).path_join("crit_%s_%04d.png" % [cfg["victim"], int(SHOTS_MS[shot_i])]))
		shot_i += 1
		label.visible = false
		busy = false
		if shot_i >= SHOTS_MS.size():
			_finish_sheet()


func _finish_sheet() -> void:
	var rows := int(ceil(float(shots.size()) / COLS))
	var sheet := Image.create(CELL.x * COLS, CELL.y * rows, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.05, 0.05, 0.05))
	for i in shots.size():
		var img: Image = (shots[i]["img"] as Image).duplicate()
		img.convert(Image.FORMAT_RGB8)
		img.resize(CELL.x, CELL.y, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i((i % COLS) * CELL.x, (i / COLS) * CELL.y))
	var path := String(cfg["sheet"])
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	sheet.save_png(abs_path)
	var size := FileAccess.get_file_as_bytes(abs_path).size()
	check("sheet_size", size > 0 and size <= MAX_SHEET_BYTES, size, MAX_SHEET_BYTES)
	var got: Array = []
	for s in shots:
		got.append([s["target"], snappedf(float(s["ms"]), 0.1)])
		check("shot_%d" % int(s["target"]), absf(float(s["ms"]) - float(s["target"])) <= 16.7 or float(s["target"]) >= 1250.0, s["ms"], s["target"])
	report["shots"] = got
	report["phases"] = phases
	report["sheet"] = abs_path
	print(JSON.stringify(report))
	get_tree().quit(0 if report["ok"] else 1)
