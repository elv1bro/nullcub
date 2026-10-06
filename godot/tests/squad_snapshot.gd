## Снимки «Стычки 3 на 3» (нужно окно): карта целиком, отсчёт, бой глазами P1 (за него играет бот, камера и HUD ведут его как
## игрока — SquadMatch.focus_index), выбор класса на отсчёте, карточка нового уровня, громила с оружием, ящики снабжения, фраг P1,
## ожидание возврата, итоги, и клип
## clip/frame_NNNN.png (10 кадров/с).
##   godot/tools/godot_nofocus.sh --path godot --resolution 1600x900 res://tests/squad_snapshot.tscn -- "out_dir=/abs/dir,clip_s=8,level=2,night=1"
## (night=1 — ночная карта)
## Глазами проверить: карта читается (базы, укрытия, плиты), команды различимы (цвет, обводка, имена), трассы пуль видны, счёт и лента
## фрагов на HUD, стрелки к соперникам за кадром, табличка итогов.
extends Node

const SCENE := "res://scenes/playground_squad.tscn"
const SCENE_NIGHT := "res://scenes/playground_squad_night.tscn"

var out_dir := "/tmp"
var clip_s := 8.0
var level := 2
var night := false
var pg: SquadPlayground
var sm: SquadMatch


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for part in String(arg).split(","):
			var kv := part.split("=")
			if kv.size() != 2:
				continue
			match kv[0]:
				"out_dir": out_dir = kv[1]
				"clip_s": clip_s = float(kv[1])
				"level": level = int(kv[1])
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


func _until(cond: Callable, max_s: float) -> bool:
	var t := 0.0
	while not cond.call() and t < max_s:
		await get_tree().process_frame
		t += get_process_delta_time() / maxf(Engine.time_scale, 0.05)
	return cond.call()


func _p0() -> Doll:
	for d in sm.dolls():
		if (d as Doll).player_index == 0:
			return d
	return null


func _run() -> void:
	pg = (load(SCENE_NIGHT if night else SCENE) as PackedScene).instantiate() as SquadPlayground
	pg.p1_bot = true
	pg.bot_level = level
	sm = pg.get_node("Match") as SquadMatch
	sm.focus_index = 0
	add_child(pg)
	await _wait(0.6)
	# карта целиком: своя камера на время кадра
	var game_cam := get_viewport().get_camera_3d()
	var wide := Camera3D.new()
	wide.fov = 26.0
	wide.attributes = CameraAttributesPractical.new()   # без глубины резкости окружения Руин: карта целиком резкая
	add_child(wide)
	wide.global_position = Vector3(0.0, 7.5, 150.0)
	wide.make_current()
	await _wait(0.2)
	await _shot("squad_map")
	game_cam.make_current()
	wide.queue_free()
	await _wait(0.3)
	await _shot("squad_countdown")
	await _until(func() -> bool: return sm.play_state == "play", 8.0)
	# темп кадров: 5 с без снимков — кадров в секунду и тиков физики на секунду реального времени
	var f0 := Engine.get_process_frames()
	var p0 := Engine.get_physics_frames()
	var t0 := Time.get_ticks_msec()
	var worst := 0.0
	var tt := 0.0
	while tt < 5.0:
		await get_tree().process_frame
		var dt := get_process_delta_time() / maxf(Engine.time_scale, 0.05)
		worst = maxf(worst, dt)
		tt += dt
	var real := float(Time.get_ticks_msec() - t0) / 1000.0
	print("perf: fps %.1f, physics ticks/s %.1f, worst frame %.1f ms, time_scale %.2f" % [float(Engine.get_process_frames() - f0) / real,
		float(Engine.get_physics_frames() - p0) / real, worst * 1000.0, Engine.time_scale])
	await _wait(2.0)
	await _shot("squad_fight_1")
	# клип
	var frames := int(clip_s * 10.0)
	for i in frames:
		await _shot("clip/frame_%04d" % i)
		await _wait(0.1)
	await _shot("squad_fight_2")
	# новый уровень: опыта P1 до следующего уровня — карточка «что ты теперь можешь»
	var lo := sm.loadout(0)
	var lv := int(lo["level"])
	if lv < Tuning.SQUAD_XP_LEVELS.size():
		sm.add_xp(0, float(Tuning.SQUAD_XP_LEVELS[lv]) - float(lo["xp"]) + 1.0)
		await _wait(0.5)
		await _shot("squad_level")
	# громила крупно: камера на синем громиле (P5 — красный, P4 — синий)
	sm.focus_index = 4
	await _wait(2.5)
	await _shot("squad_brawler")
	sm.focus_index = 0
	await _wait(1.0)
	# ящики рядом с P1
	var me0 := _p0()
	if me0 != null and me0.alive:
		var c := me0.centre_of_mass()
		var k := 0
		for kind in ["ammo", "health", "armor"]:
			sm.spawn_supply(kind, c + Vector3(-3.0 + 3.0 * k, 2.6, 0.0))
			k += 1
		await _wait(0.5)
		await _shot("squad_supply")
	# фраг с участием P1 (он добил или его выбили) — кадр сразу после
	var got := {"k": false}
	sm.frag.connect(func(k: Doll, v: Doll, _t: int) -> void:
		if (k != null and k.player_index == 0) or (v != null and v.player_index == 0):
			got["k"] = true)
	await _until(func() -> bool: return bool(got["k"]), 90.0)
	await _wait(0.25)
	await _shot("squad_frag")
	var p := _p0()
	if p != null and not p.alive:
		await _wait(1.0)
		await _shot("squad_respawn")
	# итоги: матч досрочно до ведущего + 1 (полный матч в окне идёт пару минут)
	sm.score_to_win = maxi(int(sm.score[0]), int(sm.score[1])) + 1
	await _until(func() -> bool: return sm.play_state == "over", 120.0)
	await _wait(1.6)
	await _shot("squad_end")
	print("score ", sm.score, " fight_s ", snappedf(sm.fight_time, 0.1))
	get_tree().quit(0)
