## Снимки пробы «Подъём: стена» (docs/plan-demo/CLIMB.md; нужно окно):
##   godot/tools/godot_nofocus.sh --path godot --resolution 1600x900 res://tests/climb_snapshot.tscn -- "out_dir=/abs/dir"
## Кадры: start — подножие вдвоём (HUD, памятка); smooth — P1 летит вдоль синей гладкой плиты, полоска запаса тает, P2 висит на правой
## скале; hang — P1 на двух руках под карнизом («отдых», обе метки рук горят), P2 на одной руке («тает»); top — P1 на плато, табличка «ВЕРХ!».
## Глазами проверить: полоска запаса над головой и метки рук, подписи высоты справа, синие плиты отличаются от камня, HUD не налезает.
extends Node

const PLAYGROUND := "res://scenes/playground_climb.tscn"
const TICK := 1.0 / 60.0

var out_dir := "/tmp"
var pg: ClimbPlayground


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for part in String(arg).split(","):
			var kv := part.split("=")
			if kv.size() == 2 and kv[0] == "out_dir":
				out_dir = kv[1]
	_run.call_deferred()


func _shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name_]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("shot → ", path)


func _wait(s: float) -> void:
	for i in int(ceil(s / TICK)):
		await get_tree().physics_frame


func _teleport(d: Doll, to: Vector3) -> void:
	for a in ClimbMatch.wall_arms(d):
		(a as ArmAssist).wall_release("shot")
		(a as ArmAssist).clear_target_override()
	var shift := to - d.centre_of_mass()
	shift.z = 0.0
	for p in d.parts.values():
		var b := p as RigidBody3D
		if b != null and is_instance_valid(b):
			b.global_position += shift
			b.linear_velocity = Vector3.ZERO
			b.angular_velocity = Vector3.ZERO


## Рука(и) к курсору, пока не схватятся (≤ 2 с), потом курсор — где висеть.
func _hang(d: Doll, idx: Array, cursor: Vector3, hang_at: Vector3) -> void:
	var arms := ClimbMatch.wall_arms(d)
	for i in idx:
		(arms[i] as ArmAssist).set_target_override(cursor)
	for k in int(2.0 / TICK):
		var all := true
		for i in idx:
			all = all and (arms[i] as ArmAssist).is_wall_holding()
		if all:
			break
		await get_tree().physics_frame
	for i in idx:
		(arms[i] as ArmAssist).set_target_override(hang_at)


func _run() -> void:
	pg = (load(PLAYGROUND) as PackedScene).instantiate() as ClimbPlayground
	pg.p2_on_start = true
	pg.auto_join = false
	add_child(pg)
	await _wait(0.4)
	for d in pg.players():
		(d as Doll).external_input = true
	var p1 := pg.p1
	var p2 := pg.p2
	await _wait(1.2)
	await _shot("01_start")
	# P2 висит на одной руке на правой скале, P1 летит вверх вдоль синей плиты 6–10.6
	_teleport(p2, Vector3(2.45, 8.6, 0.0))
	_teleport(p1, Vector3(-2.3, 6.2, 0.0))
	await _wait(0.1)
	await _hang(p2, [1], Vector3(3.0, 9.1, 0.0), Vector3(2.4, 8.4, 0.0))
	p1.stamina.refill()
	p1.input_vec = Vector2(0.0, 1.0)
	ClimbMatch.wall_arms(p1)[0].set_target_override(Vector3(-2.9, 8.0, 0.0))
	await _wait(0.7)
	await _shot("02_smooth")
	p1.input_vec = Vector2.ZERO
	# P1 на двух руках под карнизом — отдых; P2 на одной руке на скале 15–19
	_teleport(p1, Vector3(-1.4, 18.45, 0.0))
	_teleport(p2, Vector3(-2.3, 17.6, 0.0))
	await _wait(0.1)
	await _hang(p1, [0, 1], Vector3(-1.4, 19.4, 0.0), Vector3(-1.4, 18.9, 0.0))
	await _hang(p2, [0], Vector3(-3.0, 18.3, 0.0), Vector3(-2.4, 17.6, 0.0))
	p1.stamina.value = 55.0
	p2.stamina.value = 40.0
	await _wait(1.0)
	await _shot("03_hang")
	# финиш: P1 на плато, табличка «ВЕРХ!»
	_teleport(p1, Vector3(-5.0, 31.1, 0.0))
	_teleport(p2, Vector3(-2.4, 28.4, 0.0))
	await _wait(0.1)
	await _hang(p2, [0, 1], Vector3(-3.0, 28.9, 0.0), Vector3(-2.4, 28.5, 0.0))
	await _wait(1.6)
	await _shot("04_top")
	get_tree().quit(0)
