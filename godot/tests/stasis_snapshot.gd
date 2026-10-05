## Кадры СТАЗИСА (docs/plan-demo/STASIS.md; нужно окно — только через tools/godot_nofocus.sh):
##   godot/tools/godot_nofocus.sh --path godot --resolution 1600x900 --fixed-fps 60 res://tests/stasis_snapshot.tscn -- "out_dir=/abs/dir"
## Кадры <out_dir>/: stasis_<скин>_frozen.png — купол, P1 стоит, бот почти замер, метка на HUD в трёх скинах (broadcast / neon / led,
## скин на диск не пишется); stasis_running.png — P1 жмёт, время идёт; stasis_mode_enter.png — вход в режим СТАЗИС (ВСЕ РЕЖИМЫ, тост);
## stasis_pve.png, stasis_sport.png — метка на HUD режима СТАЗИС (волны PvE) и спорт-зала;
## clip/frame_NNNN.png (clip=1) — 6 с купола: P1 рывками летит к боту, между рывками всё стоит (кадр каждый 2-й). Числа — в stdout:
## путь ЦМ бота за кадр в окнах «стоит» (ровный — картинка не дёргается: max / медиана) и три худших кадра с тегами замедлений
## (удар в момент замирания: тела расталкивает решатель контактов — за тик, а не за время, как и под стоп-кадром удара без режима).
extends Node

const DOME := "res://scenes/playground_null_hall.tscn"
const PVE := "res://scenes/playground_stasis.tscn"   # режим СТАЗИС отдельным пунктом ВСЕ РЕЖИМЫ (PvE-волны, режим вкл в сцене)
const SPORT := "res://scenes/playground_sport.tscn"

var out_dir := "/tmp"
var clip := true
var pg: Node = null


func _ready() -> void:
	ControlFeel.no_disk = true
	for arg in OS.get_cmdline_user_args():
		for part in String(arg).split(","):
			var kv := part.split("=")
			if kv.size() == 2:
				match kv[0]:
					"out_dir": out_dir = kv[1]
					"clip": clip = kv[1] == "1"
	_run.call_deferred()


func _shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name_]
	img.save_png(path)
	print("shot → ", path)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _load(path: String) -> Match:
	if pg != null and is_instance_valid(pg):
		pg.queue_free()
		await _frames(3)
	Engine.time_scale = 1.0
	pg = (load(path) as PackedScene).instantiate()
	var p2 := pg.get_node_or_null("P2") as Doll
	var p1 := pg.get_node_or_null("P1") as Doll
	if path == DOME and p2 != null:
		p1.add_to_group("players")
		p2.add_to_group("rivals")
		var b := RivalBrain.new()
		b.name = "Brain"
		b.level = 3
		p2.add_child(b)
	add_child(pg)
	var m := pg.get_node_or_null("Match") as Match
	if m == null:
		m = pg.get_node_or_null("WaveDirector") as Match
	return m


func _release() -> void:
	for a in Stasis.actions_of("p1"):
		Input.action_release(a)


func _run() -> void:
	var skin0 := HudSkin.id()
	Stasis.set_on(true)
	var m := await _load(DOME)
	while not m.combat_active():
		await get_tree().process_frame
	Input.action_press("p1_right")
	await _frames(40)
	_release()
	await _frames(40)
	for id in HudSkin.IDS:
		HudSkin.set_skin(id, false)
		await _frames(4)
		await _shot("stasis_%s_frozen" % id)
	HudSkin.set_skin(skin0, false)
	Input.action_press("p1_up")
	await _frames(20)
	await _shot("stasis_running")
	_release()
	if clip:
		await _clip(m)
	m = await _load(PVE)
	await _frames(50)
	await _shot("stasis_mode_enter")   # тост с правилом режима на входе
	var wd := m as WaveDirector
	while wd.wave_state != "spawning" and wd.wave_state != "fight":
		await get_tree().process_frame
	Input.action_press("p1_up", 0.6)
	await _frames(150)
	_release()
	await _frames(40)
	await _shot("stasis_pve")
	m = await _load(SPORT)
	while (m as SportMatch).play_state != "play":
		await get_tree().process_frame
	Input.action_press("p1_right")
	await _frames(30)
	_release()
	await _frames(40)
	await _shot("stasis_sport")
	Stasis.set_on(false)
	print("=== OK ===")
	get_tree().quit(0)


## 6 с: P1 летит к боту рывками (0.5 с жмёт, 0.7 с отпущено). Путь ЦМ бота за кадр в окнах «стоит» — ровность картинки.
func _clip(m: Match) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir + "/clip")
	var p1 := pg.get_node("P1") as Doll
	var p2 := pg.get_node("P2") as Doll
	var steps: Array = []
	var dbg: Array = []
	var prev := p2.centre_of_mass(true)
	var prev_ts := Engine.time_scale   # масштаб, с которым посчитан следующий кадр (стоит на конец прошлого)
	var shot_i := 0
	for f in 360:
		var phase := fmod(float(f) / 60.0, 1.2)
		if phase < 0.5 and is_instance_valid(p1) and is_instance_valid(p2):
			var to := p2.centre_of_mass() - p1.centre_of_mass()
			Input.action_press("p1_right" if to.x > 0.0 else "p1_left")
			Input.action_release("p1_left" if to.x > 0.0 else "p1_right")
			Input.action_press("p1_up" if to.y > 0.0 else "p1_down", clampf(absf(to.y), 0.0, 1.0))
		else:
			_release()
		if f % 2 == 0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/clip/frame_%04d.png" % [out_dir, shot_i])
			shot_i += 1
		else:
			await get_tree().process_frame
		if not is_instance_valid(p2):
			break
		var c := p2.centre_of_mass(true)
		if prev_ts < 0.1:
			steps.append(Vector2(c.x - prev.x, c.y - prev.y).length())
			dbg.append([Vector2(c.x - prev.x, c.y - prev.y).length(), f, prev_ts, Engine.time_scale, m.crit_playing(), m.time_scale_tags()])
		prev = c
		prev_ts = Engine.time_scale
	_release()
	dbg.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) > float(y[0]))
	for e in dbg.slice(0, 3):
		print("clip: frozen step %.4f m at frame %d (scale %.2f → %.2f, crit %s, tags %s)" % [e[0], e[1], e[2], e[3], e[4], e[5]])
	steps.sort()
	var med: float = steps[steps.size() / 2] if not steps.is_empty() else 0.0
	var mx: float = steps[-1] if not steps.is_empty() else 0.0
	print("clip: %d frames, frozen-frame bot step median %.4f m, max %.4f m (видимое положение, интерполяция физики)" % [shot_i, med, mx])
