## Проба «Гонки: 10 точек» (docs/plan-demo/RACE.md) на настоящих площадках scenes/playground_race*.tscn (арена, метки точек, четыре
## гонщика, RaceMatch, RaceBrain, RaceHud).
##   rules (Полигон; мозги ботов сняты, куклы висят на старте, проба сама переносит их к точкам): горит ровно RACE_VISIBLE точек на
##     разных метках, первые — не ближе RACE_NEW_MIN_M к центру старта; деталь ближе RACE_PICK_M — точка взята одним (+1 ему, у
##     остальных 0), гаснет у всех, вместо неё загорается новая — не на горящей метке, не на взятой и не ближе RACE_NEW_MIN_M к
##     взявшему; двое у одной точки в одном тике — +1 только одному; 9 — гонка идёт, 10 — победа и конец, после конца точки не
##     берутся; KO → возврат через RACE_RESPAWN_S у последней своей точки (не брал — на старте); при RACE_VISIBLE = 1 и 5 горит
##     ровно столько, после взятий — тоже;
##   bots (P1 тоже бот, на каждой карте map=…): гонка ботов до 10 кончается за ≤ max_s (по умолчанию 180 с), точки берут хотя бы
##     двое, никто не стоит на месте (в круге 1.5 м) дольше stuck_s (10 с), все в границах карты; темп — в info.
## Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/race_probe.tscn -- "only=rules|bots,map=proving|ruins|scrap|all,max_s=180,level=2,seed=7,visible=3,trace=1,out=<json>"
## → JSON между === RACE PROBE === и === OK / FAIL ===, exit 0/1. errors_script — SCRIPT ERROR за прогон (Logger).
extends Node

const SCENES := {
	"proving": "res://scenes/playground_race.tscn",
	"ruins": "res://scenes/playground_race_ruins.tscn",
	"scrap": "res://scenes/playground_race_scrap.tscn",
}
const TICK := 1.0 / 60.0
const STUCK_R := 1.5

## Счётчик SCRIPT ERROR за прогон (как squad_probe): ошибка скрипта обрывает только свою функцию — проба могла бы молча потерять проверки.
class ScriptErrors extends Logger:
	var count := 0
	var first := ""
	var _mx := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mx.lock()
		count += 1
		if first == "":
			first = "%s %s (%s:%d %s)" % [code, rationale, file, line, function]
		_mx.unlock()


var ok := true
var checks: Array = []
var info := {}
var pg: RacePlayground
var rm: RaceMatch
var over_results: Dictionary = {}
var over_count := 0
var errs := ScriptErrors.new()


func _check(id: String, cond: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": cond, "detail": str(detail)})
	if not cond:
		ok = false
	print("  %-34s %s  %s" % [id, "ok  " if cond else "FAIL", str(detail)])


func _args() -> Dictionary:
	var out := {"only": "", "map": "all", "max_s": "180", "stuck_s": "10", "level": "2", "seed": "7", "visible": "", "trace": "0", "out": ""}
	for a in OS.get_cmdline_user_args():
		for part in String(a).split(","):
			var kv := part.split("=")
			if kv.size() == 2 and out.has(kv[0]):
				out[kv[0]] = kv[1]
	return out


func _want(a: Dictionary, section: String) -> bool:
	return String(a["only"]) == "" or section in String(a["only"]).split("+")


func _ready() -> void:
	OS.add_logger(errs)
	print("=== RACE PROBE ===")
	RacePlayground.best_path = "user://_probe_race_best.cfg"
	var a := _args()
	var maps: Array = SCENES.keys() if String(a["map"]) == "all" else String(a["map"]).split("+")
	if "grid" in String(a["only"]).split("+"):   # только по запросу: ASCII-карта статики и меток (расстановка меток)
		for m in maps:
			if SCENES.has(m) and ResourceLoader.exists(String(SCENES[m])):
				await _grid(String(m))
	if _want(a, "marks"):
		for m in maps:
			if SCENES.has(m) and ResourceLoader.exists(String(SCENES[m])):
				await _marks(String(m))
	if _want(a, "rules"):
		await _rules(int(a["seed"]))
	if _want(a, "bots"):
		for m in maps:
			if not SCENES.has(m):
				_check("map_%s" % m, false, "нет такой карты")
				continue
			if not ResourceLoader.exists(String(SCENES[m])):
				_check("map_%s" % m, false, "нет сцены %s" % SCENES[m])
				continue
			var vis := int(a["visible"]) if String(a["visible"]) != "" else Tuning.RACE_VISIBLE
			await _bots(String(m), float(a["max_s"]), float(a["stuck_s"]), int(a["level"]), int(a["seed"]), vis, String(a["trace"]) == "1")
	var g := ProjectSettings.globalize_path(RacePlayground.best_path)
	if FileAccess.file_exists(g):
		DirAccess.remove_absolute(g)
	_check("errors_script", errs.count == 0, "ошибок скриптов %d; первая: %s" % [errs.count, errs.first])
	var report := {"ok": ok, "checks": checks, "info": info}
	print(JSON.stringify(report, " "))
	if String(a["out"]) != "":
		var f := FileAccess.open(String(a["out"]), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(report, " "))
			f.close()
	print("=== OK ===" if ok else "=== FAIL ===")
	OS.remove_logger(errs)
	get_tree().quit(0 if ok else 1)


# ------------------------------------------------------------------ помощники

func _load(scene: String, p1_bot: bool, level := 2, seed_v := 7, visible := Tuning.RACE_VISIBLE, countdown := 0.3) -> void:
	await _unload()
	Engine.time_scale = 1.0
	pg = (load(scene) as PackedScene).instantiate() as RacePlayground
	pg.p1_bot = p1_bot
	pg.bot_level = level
	rm = pg.get_node("Match") as RaceMatch
	rm.feel_enabled = false
	rm.countdown_s = countdown
	rm.seed_value = seed_v
	rm.visible_count = visible
	over_results = {}
	over_count = 0
	rm.match_over.connect(func(_w: Doll, r: Dictionary) -> void:
		over_results = r
		over_count += 1)
	add_child(pg)
	await _until(func() -> bool: return rm.play_state == "play" and rm.dolls().size() == Tuning.RACE_RACERS, 8.0)


func _unload() -> void:
	if pg != null and is_instance_valid(pg):
		remove_child(pg)
		pg.queue_free()
		pg = null
		await get_tree().physics_frame


func _until(cond: Callable, max_s: float) -> bool:
	for i in int(max_s / TICK):
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _wait(s: float) -> void:
	for i in int(s / TICK):
		await get_tree().physics_frame


func _doll(pi: int) -> Doll:
	for d in rm.dolls():
		if (d as Doll).player_index == pi:
			return d
	return null


## Снять мозги: куклы висят (ввод 0). Площадка их не вернёт — мозг пересоздаётся только из детей старой куклы при возрождении.
func _silence() -> void:
	for d in rm.dolls():
		var b := (d as Node).get_node_or_null(RacePlayground.BRAIN)
		if b != null:
			(d as Node).remove_child(b)
			b.queue_free()
		(d as Doll).external_input = true
		(d as Doll).input_vec = Vector2.ZERO


## Перенести куклу целиком (все детали) так, чтобы её ЦМ встал в to; скорости — ноль.
func _teleport(d: Doll, to: Vector3) -> void:
	var shift := to - d.centre_of_mass()
	shift.z = 0.0
	for p in d.parts.values():
		var b := p as RigidBody3D
		if b == null or not is_instance_valid(b):
			continue
		b.global_position += shift
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO


## Парковка кукол-«зрителей» далеко от всех меток (у потолка, по краям), чтобы они не брали точки случайно.
func _park(except: Array) -> void:
	var b: AABB = pg.arena.call("bounds")
	var k := 0
	for d in rm.dolls():
		if except.has(d) or not (d as Doll).alive:
			continue
		var x := b.position.x + 1.5 if k % 2 == 0 else b.end.x - 1.5
		_teleport(d, Vector3(x, b.end.y - 1.5 - 2.0 * float(k / 2), 0.0))
		k += 1


func _dist2(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.y - b.y).length()


## Горящие метки уникальны и их ровно n.
func _lit_ok(n: int) -> Array:
	var ms := rm.lit_marks()
	var uniq := {}
	for m in ms:
		uniq[m] = true
	return [ms.size() == n and uniq.size() == n, ms]


## Взять точку p куклой d: перенести и подождать, пока матч засчитает. → true, если засчитано этой кукле.
func _grab(d: Doll, p: RacePoint) -> bool:
	var before := rm.score_of(d)
	var pos := p.home
	for k in 6:
		if not is_instance_valid(p) or not rm.lit_points().has(p):
			break
		_teleport(d, pos)
		await get_tree().physics_frame
	await get_tree().physics_frame
	return rm.score_of(d) == before + 1


# ------------------------------------------------------------------ marks

## Метки карты: 16–20; шар r = MARK_CLEAR_M вокруг каждой не задевает статику (стены, плиты, настилы), внутри границ; из каждой метки
## по прямой (луч по статике) видно не меньше LOS_MIN других; старт свободен. Точки старта — тоже без статики.
const MARK_CLEAR_M := 0.45
const LOS_MIN := 3

func _marks(map: String) -> void:
	print("--- marks %s" % map)
	await _load(SCENES[map], true, 2, 7, Tuning.RACE_VISIBLE, 30.0)   # длинный отсчёт: куклы стоят на старте, точки не горят
	var space := pg.get_world_3d().direct_space_state
	var b: AABB = pg.arena.call("bounds")
	# коробка в слое кукол (|z| ≤ 0.25): кладка-декор за плоскостью (пилоны ворот z −1.1…−0.3) куклам не мешает
	var sphere := BoxShape3D.new()
	sphere.size = Vector3(MARK_CLEAR_M * 2.0, MARK_CLEAR_M * 2.0, 0.5)
	var blocked: Array = []
	var outside: Array = []
	var names: Array = []
	for m in pg.get_node("RaceMarks").get_children():
		names.append(String(m.name))
	for i in rm.marks.size():
		var p := rm.marks[i]
		if not b.has_point(Vector3(p.x, p.y, 0.0)):
			outside.append(names[i])
		if _static_hit(space, sphere, p):
			blocked.append(names[i])
	var starts_blocked: Array = []
	var cap := BoxShape3D.new()
	cap.size = Vector3(0.6, 1.6, 0.4)
	for i in rm.starts.size():
		if _static_hit(space, cap, rm.starts[i] + Vector3(0.0, 0.95, 0.0)):
			starts_blocked.append(i)
	var nav := RaceNav.new()
	nav.build(space, rm.marks)
	var vis: Array = []
	var lonely: Array = []
	for i in rm.marks.size():
		var n := (nav.edges[i] as Array).size()
		vis.append(n)
		if n < LOS_MIN:
			lonely.append("%s(%d)" % [names[i], n])
	var total := 0
	for v in vis:
		total += int(v)
	info["marks_" + map] = {"marks": rm.marks.size(), "los_per_mark": vis, "los_avg": snappedf(float(total) / maxf(rm.marks.size(), 1), 0.1),
		"graph_connected": snappedf(nav.connected_share(), 0.001)}
	_check("marks_%s_count" % map, rm.marks.size() >= 16 and rm.marks.size() <= 20, "меток %d" % rm.marks.size())
	_check("marks_%s_free" % map, blocked.is_empty() and outside.is_empty(), "в статике (r %.2f м): %s; вне границ: %s" % [MARK_CLEAR_M, str(blocked), str(outside)])
	_check("marks_%s_los" % map, lonely.is_empty(), "из каждой метки видно (толстым лучом RaceNav) ≥ %d других (в среднем %.1f); мало: %s" % [LOS_MIN,
		float(info["marks_" + map]["los_avg"]), str(lonely)])
	_check("marks_%s_graph" % map, is_equal_approx(nav.connected_share(), 1.0), "граф видимости связный: доля пар с путём %.3f" % nav.connected_share())
	_check("marks_%s_starts" % map, starts_blocked.is_empty() and rm.starts.size() == Tuning.RACE_RACERS, "стартов %d, в статике: %s" % [rm.starts.size(), str(starts_blocked)])
	await _unload()


## ASCII-карта слоя кукол (|z| ≤ 0.2) с шагом 0.5 м: # — статика, = — доски моста / замороженное, цифра/буква — метка (индекс в
## RaceMarks, 0–9 и a–k), S — старт. Сверху вниз — от потолка к полу. Для расстановки меток руками.
func _grid(map: String) -> void:
	print("--- grid %s" % map)
	await _load(SCENES[map], true, 2, 7, Tuning.RACE_VISIBLE, 30.0)
	var space := pg.get_world_3d().direct_space_state
	var b: AABB = pg.arena.call("bounds")
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.5, 0.4)
	var y := b.end.y - 0.25
	while y > b.position.y + 3.0:
		var row := "%5.1f " % y
		var x := b.position.x + 0.25
		while x < b.end.x:
			var ch := "."
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = box
			q.transform = Transform3D(Basis.IDENTITY, Vector3(x, y, 0.0))
			for h in space.intersect_shape(q, 8):
				var c: Object = h.get("collider")
				if c is StaticBody3D:
					ch = "#"
					break
				if RaceNav.is_obstacle(c):
					ch = "="
			for i in rm.marks.size():
				if absf(rm.marks[i].x - x) <= 0.25 and absf(rm.marks[i].y - y) <= 0.25:
					ch = "0123456789abcdefghijk"[i]
			for s in rm.starts:
				if absf(s.x - x) <= 0.25 and absf(s.y + 0.9 - y) <= 0.25:
					ch = "S"
			row += ch
			x += 0.5
		print(row)
		y -= 0.5
	await _unload()


func _static_hit(space: PhysicsDirectSpaceState3D, shape: Shape3D, at: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, Vector3(at.x, at.y, 0.0))
	q.collide_with_areas = false
	for h in space.intersect_shape(q, 16):
		if RaceNav.is_obstacle(h.get("collider")):   # статика, тяжёлые пропсы, доски моста
			var c := h.get("collider") as Node3D
			print("    obstacle at (%.1f, %.1f): %s" % [at.x, at.y, str(c.get_path()).replace(str(pg.get_path()) + "/", "")])
			return true
	return false


# ------------------------------------------------------------------ rules

func _rules(seed_v: int) -> void:
	print("--- rules (Полигон)")
	await _load(SCENES["proving"], false, 2, seed_v)
	_silence()
	var vis := rm.visible_target()
	var start := rm.start_centre()
	var lo := _lit_ok(vis)
	var near_start := 99.0
	for m in lo[1]:
		near_start = minf(near_start, _dist2(rm.marks[int(m)], start))
	_check("marks_count", rm.marks.size() >= 16 and rm.marks.size() <= 20, "меток %d" % rm.marks.size())
	_check("lit_visible", bool(lo[0]), "горит %d из %d (метки %s)" % [(lo[1] as Array).size(), vis, str(lo[1])])
	_check("lit_first_far_from_start", near_start >= Tuning.RACE_NEW_MIN_M - 0.01, "ближайшая к старту %.1f м" % near_start)
	# --- взятие одним: точка гаснет у всех, +1 только ему, новая — не на горящей, не на взятой, ≥ 8 м от взявшего
	var a := _doll(0)
	var b := _doll(2)
	_park([a])
	await get_tree().physics_frame
	var p0 := rm.lit_points()[0] as RacePoint
	var m0 := p0.mark
	var lit_before := rm.lit_marks()
	var got := await _grab(a, p0)
	var last: Dictionary = rm.takes[-1] if not rm.takes.is_empty() else {}
	var others := 0
	for d in rm.dolls():
		if d != a:
			others += rm.score_of(d)
	_check("take_scores_one", got and rm.score_of(a) == 1 and others == 0, "у взявшего %d, у остальных %d" % [rm.score_of(a), others])
	_check("take_gone_for_all", not rm.lit_marks().has(m0) and not rm.lit_points().has(p0),
		"метка %d после взятия горит: %s" % [m0, str(rm.lit_marks().has(m0))])
	var lo2 := _lit_ok(vis)
	_check("take_relit_count", bool(lo2[0]), "после взятия горит %d (метки %s)" % [(lo2[1] as Array).size(), str(lo2[1])])
	var nm := int(last.get("new_mark", -1))
	_check("take_new_free", nm >= 0 and nm != m0 and not lit_before.has(nm), "новая метка %d (взята %d, горели %s)" % [nm, m0, str(lit_before)])
	_check("take_new_far", float(last.get("new_dist", -1.0)) >= Tuning.RACE_NEW_MIN_M, "новая в %.1f м от взявшего" % float(last.get("new_dist", -1.0)))
	# --- двое у одной точки в одном тике — +1 только одному
	var p1 := rm.lit_points()[0] as RacePoint
	var sa := rm.score_of(a)
	var sb := rm.score_of(b)
	_teleport(a, p1.home + Vector3(-0.15, 0.0, 0.0))
	_teleport(b, p1.home + Vector3(0.15, 0.0, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var gained := rm.score_of(a) - sa + rm.score_of(b) - sb
	_check("take_two_one_wins", gained == 1, "двое у одной точки: прибавилось %d (P1 %d → %d, P3 %d → %d)" % [gained, sa, rm.score_of(a), sb, rm.score_of(b)])
	# --- новая точка — по всем взятиям: не ближе 8 м к взявшему и не на горящей метке
	var far_ok := true
	var worst := 99.0
	for t in rm.takes:
		if int(t["new_mark"]) >= 0:
			worst = minf(worst, float(t["new_dist"]))
			far_ok = far_ok and float(t["new_dist"]) >= Tuning.RACE_NEW_MIN_M
	# --- KO → возврат у последней своей точки; не брал — на старте
	_park([])
	await get_tree().physics_frame
	var a_mark := int(rm.last_mark.get(a.player_index, -1))
	var c := _doll(3)
	var c_score := rm.score_of(c)
	a.knock_out()
	c.knock_out()
	var dead_ok := not a.alive and rm.respawn_left(a) > 0.0
	await _wait(Tuning.RACE_RESPAWN_S + 0.2)
	var na := _doll(0)
	var nc := _doll(3)
	var want_a := rm.marks[a_mark] - Vector3(0.0, Tuning.RACE_RESPAWN_DROP_M, 0.0) if a_mark >= 0 else Vector3.INF
	var lit_on_a := rm.lit_marks().has(a_mark)
	var da := _dist2(na.global_position, want_a) if a_mark >= 0 else 99.0
	var dc := _dist2(nc.global_position, rm.starts[3])
	_check("ko_respawn_alive", dead_ok and na.alive and nc.alive and na != a, "выбыл и вернулся через %.1f с: %s / %s" % [Tuning.RACE_RESPAWN_S, str(na.alive), str(nc.alive)])
	_check("ko_respawn_last_point", lit_on_a or da < 0.6, "P1 вернулся в %.2f м от своей точки (метка %d)%s" % [da, a_mark, " — на ней горит точка, у соседней" if lit_on_a else ""])
	_check("ko_respawn_start", c_score > 0 or dc < 0.6, "P4 без точек вернулся в %.2f м от старта" % dc)
	_check("ko_keeps_score", rm.score_of(na) >= 1, "счёт после возврата %d" % rm.score_of(na))
	info["respawn_com_above_mark_m"] = snappedf(na.centre_of_mass().y - rm.marks[a_mark].y, 0.01) if a_mark >= 0 else 0.0
	# --- до 10: 9 — идёт, 10 — победа и конец, после конца не берётся
	a = na
	_park([a])
	var guard := 0
	while rm.score_of(a) < rm.to_win - 1 and guard < 40:
		guard += 1
		_park([a])
		var pts := rm.lit_points()
		if pts.is_empty():
			break
		await _grab(a, pts[0] as RacePoint)
	var at9 := rm.score_of(a)
	var going := rm.play_state == "play" and over_count == 0
	_park([a])
	var p_last := rm.lit_points()[0] as RacePoint if not rm.lit_points().is_empty() else null
	if p_last != null:
		await _grab(a, p_last)
	await get_tree().physics_frame
	_check("win_at_ten", at9 == rm.to_win - 1 and going and rm.score_of(a) == rm.to_win and over_count == 1 and rm.phase == Match.Phase.OVER,
		"%d — гонка идёт: %s; %d — конец: %s (итогов %d)" % [at9, str(going), rm.score_of(a), str(rm.phase == Match.Phase.OVER), over_count])
	var w: Doll = over_results.get("winner") as Doll
	_check("win_results", w == a and int(over_results.get("winner_index", -1)) == a.player_index and String(over_results.get("reason", "")) == "points"
		and (over_results.get("places", []) as Array).size() == Tuning.RACE_RACERS and (over_results.get("places", []) as Array)[0] == a,
		"победитель P%d, причина %s, первый в таблице — он" % [int(over_results.get("winner_index", -1)) + 1, String(over_results.get("reason", ""))])
	var total0 := 0
	for d in rm.dolls():
		total0 += rm.score_of(d)
	if not rm.lit_points().is_empty():
		var ps := rm.lit_points()[0] as RacePoint
		_teleport(b, ps.home)
		await _wait(0.1)
	var total1 := 0
	for d in rm.dolls():
		total1 += rm.score_of(d)
	_check("no_takes_after_end", total1 == total0, "очков до %d, после касания в итогах %d" % [total0, total1])
	_check("new_point_far_all", far_ok, "новая точка — не ближе %.0f м к взявшему во всех %d взятиях (ближайшая %.1f м)" % [Tuning.RACE_NEW_MIN_M, rm.takes.size(), worst])
	var dup := false
	for t in rm.takes:
		if int(t["new_mark"]) == int(t["mark"]):
			dup = true
	_check("new_point_not_taken_mark", not dup, "новая точка ни разу не загорелась на только что взятой метке")
	info["rules"] = {"marks": rm.marks.size(), "takes": rm.takes.size(), "race_s": snappedf(rm.fight_time, 0.01)}
	# --- RACE_VISIBLE = 1 и 5
	for v in [1, 5]:
		await _load(SCENES["proving"], false, 2, seed_v + v, v)
		_silence()
		var x := _doll(0)
		_park([x])
		var lv := _lit_ok(v)
		var counts: Array = [(lv[1] as Array).size()]
		var all_ok := bool(lv[0])
		for k in 4:
			_park([x])
			var pts2 := rm.lit_points()
			if pts2.is_empty():
				all_ok = false
				break
			await _grab(x, pts2[0] as RacePoint)
			var l3 := _lit_ok(v)
			counts.append((l3[1] as Array).size())
			all_ok = all_ok and bool(l3[0])
		_check("visible_%d" % v, all_ok and rm.score_of(x) == 4, "горит по взятиям %s, взято %d" % [str(counts), rm.score_of(x)])
	await _unload()


# ------------------------------------------------------------------ bots

## Печать застрявшего бота (trace=1): состояние, цель, обход, ввод, скорость, стан, чего касаются торс, голова и кисти.
func _stuck_trace(dd: Doll) -> void:
	var br := dd.get_node_or_null(RacePlayground.BRAIN) as RaceBrain
	var touching := []
	for pn in dd.parts.keys():
		var pb := dd.parts[pn] as RigidBody3D
		if pb != null and pb.contact_monitor:
			for cb in pb.get_colliding_bodies():
				touching.append("%s>%s" % [pn, str(cb.get_path()).get_file()])
	var gp := br.goal_point.home if br != null and br.goal_point != null and is_instance_valid(br.goal_point) else Vector3.INF
	print("    STUCK P%d t=%.1f: %s, цель %s, обход %s %s, want %s, ввод %s, v %.2f, стан %s, касания %s" % [dd.player_index + 1, rm.fight_time,
		br.state if br != null else "-", str(Vector2(gp.x, gp.y).snapped(Vector2(0.1, 0.1))), str(br.detour if br != null else false),
		str(br.waypoint.snapped(Vector2(0.1, 0.1)) if br != null else Vector2.ZERO), str(br.want.snapped(Vector2(0.01, 0.01)) if br != null else Vector2.ZERO),
		str(dd.input_vec.snapped(Vector2(0.01, 0.01))), dd.torso().linear_velocity.length(), str(dd.is_stunned()), str(touching)])

func _bots(map: String, max_s: float, stuck_s: float, level: int, seed_v: int, vis: int, trace: bool) -> void:
	print("--- bots %s (уровень %d, горит %d)" % [map, level, vis])
	await _load(SCENES[map], true, level, seed_v, vis, 3.0)
	var b: AABB = pg.arena.call("bounds")
	var anchor: Dictionary = {}       # pi → [Vector3, t]
	var stuck_max := 0.0
	var stuck_who := ""
	var out_of_bounds := 0
	var oob_who := ""
	var hits := {"n": 0, "dmg": 0.0}
	rm.hit.connect(func(_v: Doll, a: Node, dmg: float, _k: String, _p: Vector3) -> void:
		if a is Doll and dmg > 0.0:
			hits["n"] = int(hits["n"]) + 1
			hits["dmg"] = float(hits["dmg"]) + dmg)
	var kos := {"n": 0}
	rm.ko.connect(func(_v: Doll, _a: Node, _r: Dictionary) -> void: kos["n"] = int(kos["n"]) + 1)
	var t0 := Time.get_ticks_usec()
	var frames := 0
	var trace_t := 0.0
	while over_count == 0 and rm.fight_time < max_s:
		await get_tree().physics_frame
		frames += 1
		if rm.play_state != "play":
			continue
		for d in rm.dolls():
			var dd := d as Doll
			if not dd.alive:
				anchor.erase(dd.player_index)
				continue
			var c := dd.centre_of_mass()
			if c.x < b.position.x - 0.5 or c.x > b.end.x + 0.5 or c.y < b.position.y - 0.5 or c.y > b.end.y + 0.5:
				out_of_bounds += 1
				oob_who = "P%d в (%.1f, %.1f)" % [dd.player_index + 1, c.x, c.y]
			var an: Array = anchor.get(dd.player_index, [])
			if an.is_empty() or (an[0] as Vector3).distance_to(c) > STUCK_R:
				anchor[dd.player_index] = [c, rm.fight_time]
			elif rm.fight_time - float(an[1]) > stuck_max:
				stuck_max = rm.fight_time - float(an[1])
				var br := dd.get_node_or_null(RacePlayground.BRAIN) as RaceBrain
				stuck_who = "P%d в (%.1f, %.1f), состояние %s" % [dd.player_index + 1, c.x, c.y, br.state if br != null else "-"]
			if trace and not an.is_empty() and rm.fight_time - float(an[1]) > 6.0 and frames % 120 == 0:
				_stuck_trace(dd)
		if trace and rm.fight_time - trace_t >= 10.0:
			trace_t = rm.fight_time
			var row := []
			for d in rm.dolls():
				var br2 := (d as Node).get_node_or_null(RacePlayground.BRAIN) as RaceBrain
				var cm := (d as Doll).centre_of_mass()
				row.append("P%d:%s %d (%.0f,%.0f)%s" % [(d as Doll).player_index + 1, br2.state if br2 != null else "-", rm.score_of(d), cm.x, cm.y,
					"" if (d as Doll).alive else "†"])
			print("  t=%5.1f lit=%s  %s" % [rm.fight_time, str(rm.lit_marks()), " ".join(row)])
	var wall_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var per := {}
	var takers := 0
	var brains := {}
	for d in rm.dolls():
		var pi := (d as Doll).player_index
		per["P%d" % (pi + 1)] = rm.score_of(d)
		if rm.score_of(d) > 0:
			takers += 1
		var br := (d as Node).get_node_or_null(RacePlayground.BRAIN) as RaceBrain
		if br != null:
			brains["P%d" % (pi + 1)] = {"retargets": br.retargets, "detours": br.detours, "shoves": br.shoves, "unstick": int(br.counters.get("unstick", 0))}
	var gaps: Array = []
	var prev := 0.0
	for t in rm.takes:
		gaps.append(snappedf(float(t["t"]) - prev, 0.1))
		prev = float(t["t"])
	var max_gap := 0.0
	for g in gaps:
		max_gap = maxf(max_gap, float(g))
	var wi := int(over_results.get("winner_index", -1))
	info["bots_" + map] = {"level": level, "visible": vis, "race_s": snappedf(rm.fight_time, 0.1), "winner": "P%d" % (wi + 1), "scores": per,
		"takes": rm.takes.size(), "max_gap_s": snappedf(max_gap, 0.1), "hits": int(hits["n"]), "damage": snappedf(float(hits["dmg"]), 0.1),
		"kos": int(kos["n"]), "stuck_max_s": snappedf(stuck_max, 0.1), "brains": brains,
		"ms_per_physics_frame": snappedf(wall_ms / maxf(frames, 1), 0.01)}
	print("  " + JSON.stringify(info["bots_" + map]))
	_check("bots_%s_ends" % map, over_count == 1 and String(over_results.get("reason", "")) == "points" and rm.fight_time <= max_s,
		"гонка кончилась за %.1f с (лимит %.0f), победил P%d, причина %s" % [rm.fight_time, max_s, wi + 1, String(over_results.get("reason", "—"))])
	_check("bots_%s_winner_ten" % map, wi >= 0 and rm.score_of(_doll(wi)) == rm.to_win, "у победителя %d из %d; счёт %s" % [
		rm.score_of(_doll(wi)) if wi >= 0 else 0, rm.to_win, str(per)])
	_check("bots_%s_takers" % map, takers >= 2, "точки брали %d гонщиков" % takers)
	_check("bots_%s_not_stuck" % map, stuck_max <= stuck_s, "дольше всего на месте (в круге %.1f м) %.1f с — %s" % [STUCK_R, stuck_max, stuck_who])
	_check("bots_%s_in_bounds" % map, out_of_bounds == 0, "тиков вне границ %d %s" % [out_of_bounds, oob_who])
	await _unload()
