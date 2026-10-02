## Лист «как выглядит удар» в куполе (HIT_FX.md §13): оконная сцена, игровая камера. Удар P1 по P2 как DollCombat (ImpactFx +
## Match.on_hit): light 5 HP в торс и heavy 14 HP в голову, кадры через 1 / 3 / 6 / 12 кадров после каждого удара (реальное время
## идёт и в стоп-кадре — кадры показывают, что видит игрок). style=<имя> — стиль вспышки HitJuice.impact_style (сравнение), out_dir=<абс.>.
## Запуск: godot --path . --resolution 1280x720 --always-on-top --fixed-fps 60 res://tests/impact_look_snapshot.tscn -- "out_dir=<абс.>"
extends Node3D

const SCENE := "res://scenes/playground_null_hall.tscn"
const AT := [1, 3, 6, 12]

var out_dir := "res://tests/impact_shots"
var style := ""
var pg: Node3D
var match_node: Match


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			match p[0]:
				"out_dir": out_dir = p[1]
				"style": style = p[1]
	seed(5)
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	if style != "":
		HitJuice.impact_style = style
	pg = (load(SCENE) as PackedScene).instantiate()
	add_child(pg)
	match_node = pg.get_node("Match") as Match
	var n := 0
	while match_node.phase != Match.Phase.FIGHT and n < 900:
		await get_tree().physics_frame
		n += 1
	var ds := _pair()
	var p1: Doll = ds[0]
	var p2: Doll = ds[1]
	for d in ds:
		(d as Doll).external_input = true
	# сблизить: P2 в 1.2 м справа от P1 на высоте 2 м — удар в кадре игровой камеры
	await get_tree().physics_frame
	var base := p1.torso().global_position
	_place(p1, Vector3(-0.6, 2.0, 0.0) - base + base * Vector3(0, 0, 1))
	_place(p2, Vector3(0.6, 2.0, 0.0) - p2.torso().global_position + p2.torso().global_position * Vector3(0, 0, 1))
	for i in range(70):
		await get_tree().physics_frame
	await _hit(p1, p2, 5.0, "Torso", "light")
	await _wait(1.2)
	await _hit(p1, p2, 14.0, "Head", "heavy")
	await _wait(0.5)
	print("=== impact_look_snapshot: done ===")
	Engine.time_scale = 1.0
	get_tree().quit(0)


func _place(d: Doll, delta: Vector3) -> void:
	for b in d.parts.values():
		(b as RigidBody3D).global_position += delta
		(b as RigidBody3D).linear_velocity = Vector3.ZERO
		(b as RigidBody3D).angular_velocity = Vector3.ZERO


func _pair() -> Array:
	var ds: Array = []
	for d in get_tree().get_nodes_in_group("dolls"):
		if d is Doll and pg.is_ancestor_of(d):
			ds.append(d)
	ds.sort_custom(func(a: Doll, b: Doll) -> bool: return a.player_index < b.player_index)
	return ds


func _hit(att: Doll, vic: Doll, dmg: float, part: String, tag: String) -> void:
	await get_tree().physics_frame
	match_node.fight_time = 1.0
	vic.hp = vic.max_hp
	var dir := Vector3(signf(vic.torso().global_position.x - att.torso().global_position.x), 0, 0)
	var body := vic.parts[part] as Node3D
	var pos := body.global_position - dir * 0.12
	vic.hit_meta = {"speed": 12.0, "weapon_id": "", "striker": att.torso(), "combo_mult": 1.0, "double_blow": false,
		"knockback_mult": 1.0, "stun_s": 0.0, "dir": dir, "striker_name": "Hand_R"}
	vic.take_damage(dmg, att, part, pos, -dir, "head" if part == "Head" else "body")
	var mat := FxMaterial.id_of(vic, body)
	ImpactFx.spawn_impact(match_node, pos, -dir, 4.0 + 0.4 * dmg, "head" if part == "Head" else "body", mat, FxMaterial.tint_of(mat, vic), false)
	vic.apply_knockback(Damage.knockback_dir(dir) * Damage.knockback_impulse(dmg, 1.0), vic.torso(), 0.0, dir, Tuning.KNOCKBACK_MIN)
	match_node.on_hit(vic, att, dmg, "head" if part == "Head" else "body", pos, 1, false, "", 12.0)
	var f := 0
	for at in AT:
		while f < at:
			await get_tree().process_frame
			f += 1
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("%s/%s_f%02d.png" % [out_dir, tag, at]))


func _wait(real_s: float) -> void:
	var t := 0.0
	while t < real_s:
		await get_tree().process_frame
		t += FxClock.real_delta(get_process_delta_time())
