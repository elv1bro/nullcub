## Генератор снимков экрана «ВСЕ РЕЖИМЫ» (docs/plan-demo/MODES_SCREEN.md). Нужно окно — только через tools/godot_nofocus.sh:
##   GODOT_BIN=/usr/local/bin/godot godot/tools/godot_nofocus.sh --path godot --resolution 1600x900 res://tests/modes_shots.tscn \
##     -- "only=quick+bomb,out_dir=/abs/dir,w=960,q=0.82,max_kb=150,seed=7"
## По очереди ставит сцену каждого режима из test_menu.gd (MODES), даёт бою разыграться (за людей играют боты), прячет HUD (все
## CanvasLayer с layer ≥ 0, кроме фона-параллакса) и пишет кадр <out_dir>/<id>.jpg: w × w·9/16, JPEG q, не больше max_kb
## (иначе качество ниже). По умолчанию out_dir = res://assets/ui/modes. После — импорт:
##   gtimeout 600 /usr/bin/arch -arm64 /usr/local/bin/godot --headless --path godot --import
## (у снимков в *.jpg.import — mipmaps/generate=true: миниатюры и размытый фон экрана читают мипы).
## Чужие сохранения не трогает: кампания — своя (user://_modes_shots.tres), мастерская без автосейва, стычка без экрана настроек.
## Рецепт кадра на режим — RECIPES (id → вид); режим без рецепта — «generic»: подождать и снять. На время съёмки: крит-кино выключено
## (иначе в кадр попадает «рентген»), масштаб камеры боя — × zoom рецепта (DynamicCamera.user_zoom), 3D-надписи с буквами (табло зала,
## подписи весов, имена над бойцами) спрятаны — снимок один на все языки; цифры (счёт, номера лунок) остаются.
extends Node

const MENU := "res://scenes/menu/test_menu.gd"
const CAMPAIGN_SAVE := "user://_modes_shots.tres"
const CAMPAIGN_BP := "_modes_shots"
## id → [вид, секунд боя до кадра, масштаб камеры (× DEFAULT_USER_ZOOM; < 1 — ближе), rng_seed матча (необязательно; аргумент seed= сильнее)]
const RECIPES := {
	"campaign": ["campaign", 6.0, 1.0],
	"quick": ["duel", 5.0, 0.9], "ruins": ["duel", 5.0, 1.0], "workshop_arena": ["duel", 5.0, 1.0], "void": ["duel", 4.0, 0.8],
	"scrap": ["duel", 5.0, 1.0], "body": ["duel", 5.0, 1.0],
	"squad": ["p1_bot", 9.0, 0.6], "royale": ["p1_bot", 9.0, 0.6], "bomb": ["bomb", 4.0, 1.0, 3], "golf": ["p1_bot", 7.0, 0.7],
	"race_proving": ["p1_bot", 6.0, 0.7], "race_ruins": ["p1_bot", 6.0, 1.0], "race_scrap": ["p1_bot", 6.0, 0.6],
	"race_track": ["p1_bot", 12.0, 0.8],
	"football": ["sport", 5.0, 0.75], "basketball": ["sport", 5.0, 0.75], "volleyball": ["sport", 5.0, 0.75],
	"puzzle": ["puzzle", 5.0, 1.0],
	"pve": ["pve", 9.0, 0.75], "stasis": ["pve", 9.0, 0.75],
	"workshop": ["workshop", 2.5, 1.0],
	"domination": ["p1_bot", 10.0, 0.6, 5], "boss": ["p1_bot", 8.0, 0.8, 3], "scavenger": ["p1_bot", 7.0, 0.7, 11],
	"dodgeball": ["p1_bot", 9.0, 0.8],
	"gauntlet": ["gauntlet", 6.0, 0.9],
}
const LETTERS := "[A-Za-zА-Яа-яЁё]"

var out_dir := "res://assets/ui/modes"
var only: Array = []
var width := 960
var quality := 0.82
var max_kb := 150
var seed_ := -1                 # rng_seed матча режимов с жребием (бомба: у кого бомба); -1 — как есть
var report: Array = []
var _seed := -1


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for part in String(arg).split(","):
			var kv := part.split("=")
			if kv.size() != 2:
				continue
			match kv[0]:
				"out_dir": out_dir = kv[1]
				"only": only = Array(kv[1].split("+"))
				"w": width = int(kv[1])
				"q": quality = float(kv[1])
				"max_kb": max_kb = int(kv[1])
				"seed": seed_ = int(kv[1])
	_run.call_deferred()


func _run() -> void:
	var dir := ProjectSettings.globalize_path(out_dir) if out_dir.begins_with("res://") or out_dir.begins_with("user://") else out_dir
	DirAccess.make_dir_recursive_absolute(dir)
	var list: Array = (load(MENU) as GDScript).call("modes")
	print("=== MODES SHOTS → %s ===" % dir)
	for m in list:
		var id := String(m["id"])
		if not only.is_empty() and not only.has(id):
			continue
		var r: Array = RECIPES.get(id, ["generic", 4.0, 1.0])
		var t0 := Time.get_ticks_msec()
		DynamicCamera.user_zoom = DynamicCamera.DEFAULT_USER_ZOOM * float(r[2])
		_seed = seed_ if seed_ >= 0 else (int(r[3]) if r.size() > 3 else -1)
		var root := await _stage(String(m["scene"]), String(r[0]), float(r[1]))
		if root == null:
			report.append({"id": id, "ok": false, "why": "сцена не встала"})
			print("  FAIL %s — сцена не встала" % id)
			continue
		var res := await _capture("%s/%s.jpg" % [dir, id])
		res["id"] = id
		res["s"] = snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1)
		report.append(res)
		print("  %s %s — %d КБ, q %.2f, %.1f с" % ["ok  " if res["ok"] else "FAIL", id, res["kb"], res["q"], res["s"]])
		await _unstage(root)
	CampaignState.erase(CAMPAIGN_SAVE, CAMPAIGN_BP)
	DynamicCamera.user_zoom = DynamicCamera.DEFAULT_USER_ZOOM
	var ok := report.all(func(x: Dictionary) -> bool: return bool(x["ok"]))
	print(JSON.stringify({"ok": ok, "shots": report}))
	print("=== %s ===" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


# ------------------------------------------------------------------ постановка

func _stage(path: String, kind: String, fight_s: float) -> Node:
	Engine.time_scale = 1.0
	SquadSettings.reset()       # стычка — сразу в бой, без экрана настроек
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var root := ps.instantiate()
	match kind:
		"p1_bot", "bomb":
			if "p1_bot" in root:
				root.set("p1_bot", true)
			var mt := root.get_node_or_null("Match")
			if mt != null and "rng_seed" in mt and _seed >= 0:
				mt.set("rng_seed", _seed)
			if mt != null and "focus_index" in mt:   # камера ведёт бота P1, как игрока (squad/race/royale_snapshot)
				mt.set("focus_index", 0)
		"campaign":
			CampaignState.erase(CAMPAIGN_SAVE, CAMPAIGN_BP)
			root.set("save_path", CAMPAIGN_SAVE)
			root.set("bp_name", CAMPAIGN_BP)
			root.set("load_save", false)
			root.set("entrance_enabled", false)
		"puzzle":
			root.set("p2_on_start", true)
			root.set("auto_join", false)
		"gauntlet":   # «Испытание»: кит «Человек» (не автосейв этой машины), рекорд — не в рекорды игрока
			GauntletRun.save_path = "user://_modes_shots_gauntlet.cfg"
			root.set("use_workshop", false)
		"workshop":
			WorkshopBuild.prefs_path = "user://_modes_shots_prefs.cfg"
			root.set("load_autosave", false)
			root.set("autosave_on_test", false)
			root.set("autosave_name", "_modes_shots")
	add_child(root)
	await _sec(0.5)
	_no_crits(root)
	match kind:
		"campaign":
			root.call("start_fight")
			await _frames(3)
			_no_crits(root)
			var fight: Node = root.get("fight")
			if fight != null:
				_duel(fight.get_node_or_null("P1") as Doll, fight.get_node_or_null("P2") as Doll, false)
			await _sec(Tuning.COUNTDOWN_S)
			await _close_fight(root, fight_s)
		"gauntlet":   # бой 1 забега: как «История» — P1 против соперника лестницы
			root.call("start_run")
			await _frames(3)
			_no_crits(root)
			var gf: Node = root.get("fight")
			if gf != null:
				_duel(gf.find_child("P1", true, false) as Doll, gf.find_child("P2", true, false) as Doll, false)
			await _sec(Tuning.COUNTDOWN_S)
			await _close_fight(root, fight_s)
		"duel", "generic":
			var p1 := root.get_node_or_null("P1") as Doll
			var p2 := root.get_node_or_null("P2") as Doll
			if p1 != null and p2 != null:
				_duel(p1, p2, true)
				await _sec(Tuning.COUNTDOWN_S)
				await _close_fight(root, fight_s)
			else:
				await _sec(fight_s)
		"sport":
			var sm := root.get_node_or_null("Match")
			var t := 0.0
			while sm != null and String(sm.get("play_state")) != "play" and t < 8.0:
				await _sec(0.1)
				t += 0.1
			var p1 := root.get_node_or_null("P1") as Doll
			if p1 != null:
				var b := SportBrain.new()
				b.name = "SportBrain"
				p1.add_child(b)
				p1.external_input = true
			await _sec(fight_s)
			var ball := sm.get("ball") as Node3D if sm != null else null
			if ball != null and is_instance_valid(ball):   # камера зала держит весь зал — для кадра ближе: мяч и ближайший боец
				var bp := ball.global_position
				var near: Doll = null
				for d in sm.call("dolls"):
					if near == null or (d as Doll).centre_of_mass().distance_to(bp) < near.centre_of_mass().distance_to(bp):
						near = d
				var mid := bp if near == null else bp.lerp(near.centre_of_mass(), 0.5)
				var cam := Camera3D.new()
				cam.name = "ShotCam"
				cam.fov = 40.0
				root.add_child(cam)
				# в кадре только зал: центр не ближе полукадра к краям его границ (за стенами зала — пустота)
				var dc := root.find_children("*", "DynamicCamera", true, false)
				var dist := 11.0
				var hh := dist * tan(deg_to_rad(cam.fov * 0.5))
				var hw := hh * 16.0 / 9.0
				if not dc.is_empty():
					var vb: AABB = (dc[0] as DynamicCamera).bounds()
					if vb.size.x > hw * 2.0:
						mid.x = clampf(mid.x, vb.position.x + hw, vb.end.x - hw)
					if vb.size.y > hh * 2.0:
						mid.y = clampf(mid.y, vb.position.y + hh, vb.end.y - hh)
				cam.global_position = Vector3(mid.x, mid.y, dist)
				cam.look_at(Vector3(mid.x, mid.y, 0.0))
				cam.make_current()
		"puzzle":
			await _puzzle_carry(root as PuzzlePlayground, fight_s)
		"bomb":
			var bm := root.get_node_or_null("Match") as BombMatch
			var t := 0.0
			while bm != null and bm.play_state != "play" and t < 8.0:
				await _sec(0.1)
				t += 0.1
			await _sec(fight_s)
			if bm != null and bm.holder != null:   # держатель крупно: бомба на груди, вокруг купол (как bomb_snapshot)
				var cam := Camera3D.new()
				cam.name = "ShotCam"
				cam.fov = 34.0
				root.add_child(cam)
				var c := bm.holder.centre_of_mass(true)
				var near: Doll = null
				for d in bm.dolls():
					if d != bm.holder and (d as Doll).alive and (near == null or (d as Doll).centre_of_mass().distance_to(c) < near.centre_of_mass().distance_to(c)):
						near = d
				var sep := INF if near == null else near.centre_of_mass().distance_to(c)
				var mid := c if sep > 7.0 else (c + near.centre_of_mass()) * 0.5
				var dist := 6.5 if sep > 7.0 else clampf(5.5 + sep * 0.9, 6.5, 11.0)
				cam.global_position = Vector3(mid.x + 0.6, mid.y + 0.7, dist)
				cam.look_at(Vector3(mid.x, mid.y + 0.1, 0.0))
				cam.make_current()
		"pve":
			var p1 := root.get_node_or_null("P1") as Doll
			if p1 != null:
				var b := RivalBrain.new()
				b.name = "ShotBrain"
				b.level = 3
				p1.add_child(b)
				await _frames(3)
				b.players_group = "enemies"
				b.enemies_group = "players"
			await _sec(fight_s)
		_:
			await _sec(fight_s)
	return root


## Двое бьются друг с другом: RivalBrain на обоих, цели — друг друга (своя группа у каждого).
func _duel(p1: Doll, p2: Doll, both: bool) -> void:
	if p1 == null or p2 == null:
		return
	p1.add_to_group("_shot_a")
	p2.add_to_group("_shot_b")
	var pairs := [[p1, "_shot_b", "_shot_a"]]
	if both:
		pairs.append([p2, "_shot_a", "_shot_b"])
	for pr in pairs:
		var b := RivalBrain.new()
		b.name = "ShotBrain"
		b.level = 3
		(pr[0] as Doll).add_child(b)
		_retarget.call_deferred(b, String(pr[1]), String(pr[2]))


func _retarget(b: RivalBrain, target_group: String, own_group: String) -> void:
	await _frames(3)
	if is_instance_valid(b):
		b.players_group = target_group
		b.enemies_group = own_group


## Бой идёт fight_s; кадр — когда двое сошлись (≤ 2.4 м) после половины этого времени, иначе по таймеру.
func _close_fight(root: Node, fight_s: float) -> void:
	var dolls: Array = []
	for d in root.find_children("*", "Doll", true, false):
		if (d as Doll).is_in_group("_shot_a") or (d as Doll).is_in_group("_shot_b"):
			dolls.append(d)
	var t := 0.0
	while t < fight_s + 3.0:
		await _sec(0.1)
		t += 0.1
		if t < fight_s * 0.6 or dolls.size() < 2:
			continue
		var a := dolls[0] as Doll
		var b := dolls[1] as Doll
		if not is_instance_valid(a) or not is_instance_valid(b):
			break
		if a.centre_of_mass().distance_to(b.centre_of_mass()) < 2.4 or t >= fight_s:
			break


## Крит-кино («рентген») не должно попасть в кадр: у матча крит выключен, у режиссёра эффектов — кино.
func _no_crits(root: Node) -> void:
	for n in root.find_children("*", "", true, false):
		if "crit_enabled" in n:
			n.set("crit_enabled", false)
		if "crit_cinematic" in n and typeof(n.get("crit_cinematic")) == TYPE_BOOL:
			n.set("crit_cinematic", false)


## Головоломки, комната 3: двое берут ящик 60 кг и несут наверх (как puzzle_snapshot, кадр carry).
func _puzzle_carry(pg: PuzzlePlayground, max_s: float) -> void:
	for d in pg.players():
		(d as Doll).external_input = true
	pg.goto_room(2)
	pg.reset_room()
	await _sec(2.4)
	var r := pg.rooms[2]
	var duo := r.find("Duo") as RigidBody3D
	if duo == null or pg.p2 == null:
		return
	var c0 := duo.global_position
	_teleport(pg.p1, Vector3(c0.x - 0.8, 1.0, 0))
	_teleport(pg.p2, Vector3(c0.x + 0.9, 1.0, 0))
	await _sec(0.6)
	var a1 := PuzzlePlayground._arm(pg.p1)
	var a2 := PuzzlePlayground._arm(pg.p2)
	for a in [a1, a2]:
		var arm := a as ArmAssist
		for i in 90:
			arm.set_target_override(arm.closest_point(duo, arm.grip_global()))
			await get_tree().physics_frame
			if arm.find_candidate() == duo:
				break
		arm.press_grab()
		await _frames(2)
	a1.clear_target_override()
	a2.clear_target_override()
	var t := 0.0
	while t < max_s and duo.global_position.y < 2.6:
		pg.p1.input_vec = Vector2(-0.1, 1).normalized()
		pg.p2.input_vec = Vector2(0.1, 1).normalized()
		await get_tree().physics_frame
		t += 1.0 / 60.0


func _teleport(d: Doll, to: Vector3) -> void:
	var shift := to - d.centre_of_mass()
	shift.z = 0.0
	for p in d.parts.values():
		var b := p as RigidBody3D
		if b != null and is_instance_valid(b):
			b.global_position += shift
			b.linear_velocity = Vector3.ZERO
			b.angular_velocity = Vector3.ZERO


func _unstage(root: Node) -> void:
	root.queue_free()
	await _frames(6)
	Engine.time_scale = 1.0
	Stasis.set_on(false)
	SquadSettings.reset()
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = true


# ------------------------------------------------------------------ кадр

func _capture(path: String) -> Dictionary:
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var layer := cl as CanvasLayer
		if layer is ParallaxBackground or layer.layer < 0:
			continue
		layer.visible = false
	var letters := RegEx.create_from_string(LETTERS)
	for l in get_tree().root.find_children("*", "Label3D", true, false):
		if letters.search((l as Label3D).text) != null:
			(l as Label3D).visible = false
	await _frames(2)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var h := int(round(width * 9.0 / 16.0))
	if absf(float(img.get_width()) / img.get_height() - 16.0 / 9.0) > 0.01:   # окно не 16:9 — срез по центру
		var cw := mini(img.get_width(), int(img.get_height() * 16.0 / 9.0))
		var ch := int(cw * 9.0 / 16.0)
		img = img.get_region(Rect2i((img.get_width() - cw) / 2, (img.get_height() - ch) / 2, cw, ch))
	img.resize(width, h, Image.INTERPOLATE_LANCZOS)
	var q := quality
	var buf := img.save_jpg_to_buffer(q)
	while buf.size() > max_kb * 1024 and q > 0.5:
		q -= 0.05
		buf = img.save_jpg_to_buffer(q)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "kb": 0, "q": q, "why": "не записать %s" % path}
	f.store_buffer(buf)
	f.close()
	var lum := _luma(img)
	return {"ok": buf.size() <= max_kb * 1024 and lum > 0.03, "kb": buf.size() / 1024, "q": snappedf(q, 0.01), "luma": snappedf(lum, 0.001),
		"path": path}


## Средняя яркость кадра (0..1): чёрный кадр = сцена не отрисовалась.
func _luma(img: Image) -> float:
	var s := 0.0
	var n := 0
	for y in range(0, img.get_height(), 9):
		for x in range(0, img.get_width(), 9):
			var c := img.get_pixel(x, y)
			s += c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			n += 1
	return s / maxf(n, 1)


func _sec(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
