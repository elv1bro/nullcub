## Снимки «Королевской битвы» (docs/plan-demo/ROYALE.md; нужно окно): бой глазами P1 (за него играет бот, камера и HUD ведут его как
## игрока — RoyaleMatch.focus_index): старт (ящики по карте, табло зоны), сбор (без оружия — стрелка к ящику), бой со стволом, стены
## зоны во время сжатия и пунктир будущих стен, «ты за стеной», выбывание P1 и слежение за тем, кто выбил, итоги с местами.
##   godot/tools/godot_nofocus.sh --path godot --resolution 1920x1080 res://tests/royale_snapshot.tscn -- "out_dir=/abs/dir,night=0"
## Глазами проверить: поле зоны видно и не закрывает бой, табло читается, цвета бойцов различимы, ящики с оружием подписаны, рамка
## «за стеной», табличка итогов.
extends Node

const SCENE := "res://scenes/playground_royale.tscn"
const SCENE_NIGHT := "res://scenes/playground_royale_night.tscn"

var out_dir := "/tmp/royale_shots"
var night := false
var pg: RoyalePlayground
var rm: RoyaleMatch


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for part in String(arg).split(","):
			var kv := part.split("=")
			if kv.size() != 2:
				continue
			match kv[0]:
				"out_dir": out_dir = kv[1]
				"night": night = kv[1] == "1"
	_run.call_deferred()


func _shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name_]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("shot → ", path)


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _p0() -> Doll:
	return pg.doll(0)


func _run() -> void:
	pg = (load(SCENE_NIGHT if night else SCENE) as PackedScene).instantiate() as RoyalePlayground
	pg.p1_bot = true
	rm = pg.get_node("Match") as RoyaleMatch
	rm.focus_index = 0
	rm.rng_seed = 33
	add_child(pg)
	var pre := "night_" if night else ""
	while rm.play_state != "play":
		await get_tree().process_frame
	await _wait(0.6)
	await _shot(pre + "01_start")
	if night:
		await _wait(6.0)
		await _shot(pre + "02_fight")
		get_tree().quit(0)
		return
	await _wait(5.0)
	await _shot("02_loot")
	# со стволом: если P1 ещё без оружия — дать винтовку
	var p := _p0()
	if p != null and p.alive and SquadMatch.gun_of(p).weapon == "":
		rm._weapons[0] = "rifle"
		rm._equip(p)
	await _wait(4.0)
	await _shot("03_armed")
	# зона: перемотать к середине второго сжатия
	rm.zone.tick(30.0 + 20.0 + 30.0 + 10.0)
	await _wait(1.5)
	await _shot("04_zone_shrink")
	# P1 за стеной
	p = _p0()
	if p != null and p.alive:
		var x := p.centre_of_mass().x
		rm.zone.left = x + 2.0
		rm.zone.right = maxf(x + 14.0, rm.zone.left + 4.0)
		await _wait(1.2)
		await _shot("05_outside")
		rm.zone.left = rm.zone.map_l
		rm.zone.right = rm.zone.map_r
	# выбыл P1 — камера на того, кто выбил
	p = _p0()
	var killer: Doll = null
	for d in rm.alive_dolls():
		if d != p:
			killer = d
			break
	if p != null and p.alive and killer != null:
		p.take_damage(1000.0, killer, "Torso", p.centre_of_mass(), Vector3.UP, "weapon")
	await _wait(2.5)
	await _shot("06_spectate")
	# итоги
	var alive := rm.alive_dolls()
	for i in range(1, alive.size()):
		(alive[i] as Doll).take_damage(1000.0, alive[0], "Torso", (alive[i] as Doll).centre_of_mass(), Vector3.UP, "weapon")
		await _wait(0.1)
	await _wait(2.0)
	await _shot("07_end")
	get_tree().quit(0)
