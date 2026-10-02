## Лист «сок удара на языке игры» (HIT_FX.md §13): оконная сцена, кадры для глаз автора.
##   A — Void, манекены P1/P2: удары по P2 4 / 9 / 14 / 22 HP (торс, голова, плечо, торс) через Match.on_hit + ImpactFx как DollCombat;
##       кадры игровой камерой: обломки и цифра в полёте (+0.12 с после 14 HP), цифры на полу (+1.6 с), крупный план следов на P2;
##   B — модульные куклы кита (kit_bot, kit_skull, kit_brawler, kit_king) в ряд: по удару 14 HP в деталь каждого класса материала
##       (металл, кость, краска, ржавчина, тёмное дерево) — крупный план +0.07 с (обломки) и +0.8 с (след).
## Кадры → out_dir (по умолчанию tests/juice_shots/), sheet=<путь> — лист PNG; info → juice_snapshot_report.json рядом с кадрами.
## Запуск: godot --path . --resolution 1280x720 --always-on-top --fixed-fps 60 res://tests/juice_snapshot.tscn -- "out_dir=<абс.>"
extends Node3D

const SCENE := "res://scenes/playground_void.tscn"
const MDOLL := "res://scenes/body/modular_doll.tscn"
const KITS := ["kit_bot", "kit_skull", "kit_brawler", "kit_king"]
const CLASSES := ["metal", "bone", "paint", "rust", "wood_dark"]

var out_dir := "res://tests/juice_shots"
var shots: Array = []
var info := {}
var pg: Node3D
var match_node: Match
var close_cam: Camera3D


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "out_dir":
				out_dir = p[1]
	seed(11)
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	pg = (load(SCENE) as PackedScene).instantiate()
	add_child(pg)
	match_node = pg.get_node("Match") as Match
	var n := 0
	while match_node.phase != Match.Phase.FIGHT and n < 900:
		await get_tree().physics_frame
		n += 1
	for i in range(50):
		await get_tree().physics_frame
	var ds := _pair()
	var p1: Doll = ds[0]
	var p2: Doll = ds[1]
	for d in ds:
		(d as Doll).external_input = true
	# --- A: манекены ---
	await _strike(p1, p2, 4.0, "Torso")
	await _wait(0.35)
	await _strike(p1, p2, 9.0, "Head")
	await _wait(0.35)
	await _strike(p1, p2, 14.0, "UpperArm_L" if p2.parts.has("UpperArm_L") else "Torso")
	await _wait(0.12)
	await _shot("a1_heavy_flight")
	await _wait(0.5)
	await _strike(p1, p2, 22.0, "Torso")
	await _wait(0.08)
	await _shot("a2_heavy22_debris")
	await _wait(1.6)
	await _shot("a3_digits_floor")
	await _close_up(p2.torso().global_position, 1.5)
	await _shot("a4_marks_close")
	_release_close()
	info["digits"] = (match_node.get_node("HitJuice") as HitJuice).digits.stats.duplicate()
	# --- B: модульные куклы ---
	var mdolls: Array = []
	var x := -4.5
	for k in KITS:
		var md := (load(MDOLL) as PackedScene).instantiate() as Node3D
		md.set("blueprint", load("res://data/body/blueprints/%s.tres" % k))
		md.name = "M_" + k
		pg.add_child(md)
		md.global_position = Vector3(x, 2.4, -2.5)
		x += 3.0
		mdolls.append(md)
	for i in range(30):
		await get_tree().physics_frame
	# крупный план: куклы замирают на месте, звезда вспышки (пресет FX off) не забивает кадр вблизи — в игре камера дальше
	for md in mdolls:
		for b in (md.get("parts") as Dictionary).values():
			(b as RigidBody3D).freeze = true
	FxPreset.set_preset("off", get_tree())
	var found := {}
	for md in mdolls:
		for b in (md.get("parts") as Dictionary).values():
			var c := FxMaterial.cls(FxMaterial.id_of(md, b))
			if CLASSES.has(c) and not found.has(c):
				found[c] = [md, b]
	info["classes_found"] = found.keys()
	for c in CLASSES:
		if not found.has(c):
			continue
		var md: Node3D = found[c][0]
		var b: Node3D = found[c][1]
		await _close_up(b.global_position, 1.1)
		# точка удара — на поверхности детали со стороны камеры (в бою контакт всегда на поверхности)
		await get_tree().physics_frame
		var pos := _surface_point(b, close_cam.global_position)
		var mat := FxMaterial.id_of(md, b)
		ImpactFx.spawn_impact(match_node, pos, Vector3(-1, 0.3, 0.6).normalized(), 4.0 + 0.4 * 14.0, "body", mat, FxMaterial.tint_of(mat, md), c == "metal")
		HitMarks.add(b, pos, 14.0, c)
		HitMarks.add(b, pos + Vector3(0.0, 0.03, 0.0), 10.0, c)
		await _wait(0.07)
		await _shot("b_%s_debris" % c)
		await _wait(0.75)
		await _shot("b_%s_mark" % c)
		_release_close()
	FxPreset.set_preset("full", get_tree())
	_finish()


## Луч от точки к центру тела: первая точка коллизии именно этого тела (чужие — в исключения); нет — центр.
func _surface_point(b: Node3D, from: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, b.global_position + (b.global_position - from).normalized() * 0.5)
	var ex: Array[RID] = []
	for i in range(8):
		q.exclude = ex
		var r := space.intersect_ray(q)
		if r.is_empty():
			break
		if r["collider"] == b:
			return r["position"]
		ex.append(r["rid"])
	return b.global_position


func _pair() -> Array:
	var ds: Array = []
	for d in get_tree().get_nodes_in_group("dolls"):
		if d is Doll and pg.is_ancestor_of(d):
			ds.append(d)
	ds.sort_custom(func(a: Doll, b: Doll) -> bool: return a.player_index < b.player_index)
	return ds


## Удар как DollCombat: take_damage, обломки ImpactFx по материалу, Match.on_hit (следы, цифры, время). Без отброса — жертва в кадре.
func _strike(att: Doll, vic: Doll, dmg: float, part: String) -> void:
	await get_tree().physics_frame
	match_node.fight_time = 1.0
	vic.hp = vic.max_hp
	var dir := Vector3(signf(vic.torso().global_position.x - att.torso().global_position.x), 0, 0)
	if dir == Vector3.ZERO:
		dir = Vector3.RIGHT
	var body := vic.parts[part] as Node3D
	var pos := _surface_point(body, body.global_position - dir * 1.0 + Vector3(0.0, 0.1, 0.45))
	vic.hit_meta = {"speed": 12.0, "weapon_id": "", "striker": att.torso(), "combo_mult": 1.0, "double_blow": false,
		"knockback_mult": 1.0, "stun_s": 0.0, "dir": dir, "striker_name": "Hand_R"}
	vic.take_damage(dmg, att, part, pos, -dir, "body")
	var mat := FxMaterial.id_of(vic, body)
	ImpactFx.spawn_impact(match_node, pos, -dir, 4.0 + 0.4 * dmg, "body", mat, FxMaterial.tint_of(mat, vic), false)
	match_node.on_hit(vic, att, dmg, "body", pos, 1, false, "", 12.0)


func _wait(real_s: float) -> void:
	var t := 0.0
	while t < real_s:
		await get_tree().process_frame
		t += FxClock.real_delta(get_process_delta_time())


func _close_up(target: Vector3, dist: float) -> void:
	close_cam = Camera3D.new()
	close_cam.fov = 40.0
	add_child(close_cam)
	close_cam.global_position = target + Vector3(0.25, 0.15, dist)
	close_cam.look_at(target, Vector3.UP)
	close_cam.make_current()
	await get_tree().process_frame


func _release_close() -> void:
	if close_cam != null and is_instance_valid(close_cam):
		close_cam.queue_free()
	close_cam = null
	var g := match_node.game_camera()
	if g != null:
		g.make_current()


func _shot(id: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, id]
	img.save_png(ProjectSettings.globalize_path(path))
	shots.append(id)
	print("  shot ", id)


func _finish() -> void:
	info["shots"] = shots
	var f := FileAccess.open(ProjectSettings.globalize_path(out_dir + "/juice_snapshot_report.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(info, "  "))
		f.close()
	print("=== juice_snapshot: %d shots ===" % shots.size())
	Engine.time_scale = 1.0
	get_tree().quit(0)
