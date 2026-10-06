## Проба «Гонки: трасса» (docs/plan-demo/RACE_TRACK.md) на настоящей площадке scenes/playground_race_track.tscn (карта race_track.tscn,
## четыре гонщика, TrackMatch, TrackBrain, TrackHud).
##   build    — длина трассы и линии ботов, шесть участков подряд, контрольные точки по порядку в начале участков, метки места под порталы
##              (PortalSlotA / B: есть, нормали ±X, щель между ними сквозная), три развилки (лёгкая ветка длиннее трудной), точки линии и
##              отрезки между ними — в воздухе (не в стене), места старта и возврата свободны, кольца на линии;
##   sections — каждый участок по отдельности ботом (остальные гонщики выключены): возврат на контрольную точку участка → до следующей
##              (последний — до финиша), время; на развилках — обе ветки (force_choices); без KO и без «застрял»;
##   checks   — контрольные точки: яма → возврат через TRACK_RESPAWN_S у своей точки; KO ударом — так же; сетка KO короткого пути C;
##              «застрял» — через TRACK_STUCK_S; Q (drop «reset»); прогресс после возврата = прогресс точки; кольцо даёт Заряд один раз;
##   hazards  — тяжёлое поле без ускорения не поднять, с ускорением — да; встречное поле сносит; поле вверх уносит в сетку; мембрана
##              щели отталкивает; магнит тянет; пресс бьёт; мост рвётся и встаёт; бочка поджигается и встаёт новая;
##   bots     — гонка четырёх ботов (зёрна seeds, уровень level): доезжают до финиша (все, за ≤ max_s), никто не стоит на месте (в круге
##              1.5 м) дольше stuck_s, никто не вылетает за границы карты, места на финише по времени финиша; числа — в info.
## Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/track_probe.tscn -- "only=build|sections|checks|hazards|bots|grid,level=2,levels=1+2+3,seeds=1+2+3,max_s=240,stuck_s=10,trace=1,out=<json>"
##   (по умолчанию — все разделы, бот-гонка: зерно 1, уровень 2; only=dump,dump=<json> — геометрия для схемы tools/race_track_map.py)
## → JSON между === TRACK PROBE === и === OK / FAIL ===, exit 0/1. errors_script — SCRIPT ERROR за прогон (Logger).
extends Node

const SCENE := "res://scenes/playground_race_track.tscn"
const TICK := 1.0 / 60.0
const STUCK_R := 1.5

## Счётчик SCRIPT ERROR за прогон (как squad_probe / race_probe).
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
var pg: TrackPlayground
var tm: TrackMatch
var over_results: Dictionary = {}
var over_count := 0
var errs := ScriptErrors.new()


func _check(id: String, cond: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": cond, "detail": str(detail)})
	if not cond:
		ok = false
	print("  %-34s %s  %s" % [id, "ok  " if cond else "FAIL", str(detail)])


func _args() -> Dictionary:
	var out := {"only": "", "max_s": "240", "stuck_s": "10", "level": "2", "seeds": "1", "trace": "0", "out": "", "sec": "", "branch": "",
		"dump": "", "levels": ""}
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
	print("=== TRACK PROBE ===")
	TrackPlayground.best_path = "user://_probe_track_best.cfg"
	var a := _args()
	if "grid" in String(a["only"]).split("+"):
		await _grid()
	if "dump" in String(a["only"]).split("+"):   # только по запросу: геометрия карты в JSON (схема трассы для документа)
		await _dump(String(a["dump"]))
	if _want(a, "build"):
		await _build()
	if _want(a, "sections"):
		await _sections(int(a["level"]), String(a["sec"]), String(a["branch"]), String(a["trace"]) == "1")
	if _want(a, "checks"):
		await _checks()
	if _want(a, "hazards"):
		await _hazards()
	if _want(a, "bots"):
		var lvls: Array = Array(String(a["levels"]).split("+")) if String(a["levels"]) != "" else [a["level"]]
		for lv in lvls:
			for s in String(a["seeds"]).split("+"):
				await _bots(int(s), int(lv), float(a["max_s"]), float(a["stuck_s"]), String(a["trace"]) == "1")
		_bots_summary()
	await _unload()
	var g := ProjectSettings.globalize_path(TrackPlayground.best_path)
	if FileAccess.file_exists(g):
		DirAccess.remove_absolute(g)
	TrackBrain.force_choices = {}
	TrackBrain.seed_salt = 0
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

func _load(p1_bot: bool, level := 2, countdown := 0.3, salt := 0) -> void:
	await _unload()
	Engine.time_scale = 1.0
	TrackBrain.seed_salt = salt
	pg = (load(SCENE) as PackedScene).instantiate() as TrackPlayground
	pg.p1_bot = p1_bot
	pg.bot_level = level
	tm = pg.get_node("Match") as TrackMatch
	tm.feel_enabled = false
	tm.countdown_s = countdown
	tm.focus_index = 0
	over_results = {}
	over_count = 0
	tm.match_over.connect(func(_w: Doll, r: Dictionary) -> void:
		over_results = r
		over_count += 1)
	add_child(pg)
	await _until(func() -> bool: return tm.dolls().size() == Tuning.TRACK_RACERS and (countdown > 5.0 or tm.play_state == "play"), 8.0)


func _unload() -> void:
	if pg != null and is_instance_valid(pg):
		remove_child(pg)
		pg.queue_free()
		pg = null
		await get_tree().physics_frame
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
	for d in tm.dolls():
		if (d as Doll).player_index == pi:
			return d
	return null


## Снять мозг и управление: кукла висит (ввод 0), «застрял» её не считает (control_enabled = false — стоит не по своей вине).
func _silence(d: Doll, keep_control := false) -> void:
	var b := d.get_node_or_null(TrackPlayground.BRAIN)
	if b != null:
		d.remove_child(b)
		b.queue_free()
	d.external_input = true
	d.input_vec = Vector2.ZERO
	d.control_enabled = keep_control


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


## Заморозить куклу целиком (зрители проб): детали не двигаются, управления нет.
func _freeze(d: Doll, at: Vector3) -> void:
	_silence(d)
	_teleport(d, at)
	for p in d.parts.values():
		var b := p as RigidBody3D
		if b != null and is_instance_valid(b):
			b.freeze = true


func _static_hit(space: PhysicsDirectSpaceState3D, size: Vector3, at: Vector2) -> String:
	var q := PhysicsShapeQueryParameters3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	q.shape = bs
	q.transform = Transform3D(Basis.IDENTITY, Vector3(at.x, at.y, 0.0))
	q.collide_with_areas = false
	for h in space.intersect_shape(q, 16):
		var c: Object = h.get("collider")
		if c is StaticBody3D:
			return str((c as Node).name)
	return ""


# ------------------------------------------------------------------ build

func _build() -> void:
	print("--- build")
	await _load(true, 2, 60.0)
	var ar := pg.arena
	var rt := ar.route()
	var space := pg.get_world_3d().direct_space_state
	var span := ar.finish_x() - (ar.spawn_points()[0] as Vector3).x
	info["track"] = {"x_span_m": snappedf(span, 0.1), "route_total_m": snappedf(rt.total, 0.1), "segments": rt.segs.size()}
	_check("track_length", span >= 300.0 and span <= 500.0 and rt.total >= 300.0 and rt.total <= 520.0,
		"старт → финиш %.0f м по x, линия (прогресс) %.0f м" % [span, rt.total])
	var secs := ar.sections()
	var contiguous := secs.size() == 6
	for i in range(1, secs.size()):
		contiguous = contiguous and is_equal_approx(float(secs[i]["x0"]), float(secs[i - 1]["x1"])) and int(secs[i]["index"]) == i + 1
	_check("sections_six", contiguous, "участков %d, подряд: %s" % [secs.size(), str(secs.map(func(s: Dictionary) -> String: return "%d:%.0f–%.0f" % [s["index"], s["x0"], s["x1"]]))])
	var cps := ar.checkpoints()
	tm._ensure_route()
	var cp_ok := cps.size() == 6
	var cp_desc: Array = []
	for i in cps.size():
		var cx := (cps[i] as Node3D).global_position.x
		cp_desc.append("%d:x%.0f p%.0f" % [i, cx, float(tm.cp_prog[i])])
		if i > 0:
			cp_ok = cp_ok and float(tm.cp_prog[i]) > float(tm.cp_prog[i - 1]) and cx >= float(secs[i]["x0"]) - 0.01 and cx <= float(secs[i]["x0"]) + 6.0
	_check("checkpoints_order", cp_ok, "точек %d: %s (в начале участков 2–6, прогресс растёт)" % [cps.size(), str(cp_desc)])
	# места возврата и старта свободны
	var blocked: Array = []
	for i in cps.size():
		for pi in Tuning.TRACK_RACERS:
			var p: Vector3 = (cps[i] as TrackCheckpoint).spawn_for(pi) if i > 0 else ar.spawn_points()[pi]
			var h := _static_hit(space, Vector3(0.6, 1.6, 0.4), Vector2(p.x, p.y + 0.95))
			if h != "":
				blocked.append("CP%d/P%d:%s" % [i, pi + 1, h])
	_check("spawn_slots_free", blocked.is_empty(), "места старта и возврата в стене: %s" % str(blocked))
	# метки портала
	var ps := ar.portal_slots()
	var portal_ok := ps.size() == 2
	var pd := ""
	if portal_ok:
		var a3 := (ps[0] as Node3D)
		var b3 := (ps[1] as Node3D)
		var na: Vector3 = a3.get_meta("normal", Vector3.ZERO)
		var nb: Vector3 = b3.get_meta("normal", Vector3.ZERO)
		# сквозной щели нет: от кармана A до кармана B — стена
		var closed := not RaceNav.ray(space, Vector2(a3.global_position.x + 1.0, a3.global_position.y), Vector2(b3.global_position.x - 1.0, b3.global_position.y)).is_empty()
		var pair := ar.portal_pair()
		var at_slots := pair != null and pair.a != null and pair.b != null \
			and pair.a.global_position.distance_to(a3.global_position) < 0.01 and pair.b.global_position.distance_to(b3.global_position) < 0.01 \
			and Vector3(pair.a.normal()).is_equal_approx(na) and Vector3(pair.b.normal()).is_equal_approx(nb)
		portal_ok = na.is_equal_approx(Vector3(-1, 0, 0)) and nb.is_equal_approx(Vector3(1, 0, 0)) and a3.global_position.x < b3.global_position.x \
			and a3.global_basis.x.is_equal_approx(na) and b3.global_basis.x.is_equal_approx(nb) and closed and at_slots and pair.is_powered()
		pd = "A (%.1f, %.1f) n %s, B (%.1f, %.1f) n %s, между ними %.0f м; пара на метках: %s, под током: %s, щель закрыта: %s" % [
			a3.global_position.x, a3.global_position.y, str(na), b3.global_position.x, b3.global_position.y, str(nb),
			b3.global_position.x - a3.global_position.x, str(at_slots), str(pair != null and pair.is_powered()), str(closed)]
		info["portal_slots"] = pd
	_check("portal_pair", portal_ok, pd if pd != "" else "нет PortalSlotA / PortalSlotB")
	# развилки
	var forks := {}
	var forks_ok := rt.forks.size() == 3
	for f in ["A", "B", "C"]:
		var e := rt.branch(f, "easy")
		var h2 := rt.branch(f, "hard")
		if e < 0 or h2 < 0:
			forks_ok = false
			continue
		forks[f] = {"easy_m": snappedf(rt.segs[e].length, 0.1), "hard_m": snappedf(rt.segs[h2].length, 0.1)}
		forks_ok = forks_ok and rt.segs[e].length > rt.segs[h2].length + 5.0
	info["forks"] = forks
	_check("forks_three", forks_ok, "развилки (лёгкая длиннее трудной): %s" % str(forks))
	# линия в воздухе: точки (коробка 0.5) и отрезки (луч) не задевают статику
	var bad_pts: Array = []
	var bad_legs: Array = []
	for sg in rt.segs:
		for i in sg.pts.size():
			var h3 := _static_hit(space, Vector3(0.5, 0.5, 0.4), sg.pts[i])
			if h3 != "":
				bad_pts.append("%s/W%02d %s:%s" % [sg.name, i, str(sg.pts[i]), h3])
			if i > 0 and not TrackRoute.is_jump(sg, i - 1) and not RaceNav.ray(space, sg.pts[i - 1], sg.pts[i]).is_empty():
				bad_legs.append("%s/W%02d→W%02d" % [sg.name, i - 1, i])
	_check("route_in_air", bad_pts.is_empty() and bad_legs.is_empty(), "точки в стене: %s; отрезки сквозь стену: %s" % [str(bad_pts), str(bad_legs)])
	# кольца на линии
	var far_rings: Array = []
	for r in ar.rings():
		var rp := (r as Node3D).global_position
		var pr := rt.project(Vector2(rp.x, rp.y))
		if float(pr.get("dist", 99.0)) > 1.0:
			far_rings.append("%s %.1f м" % [String((r as Node).name), float(pr.get("dist", 99.0))])
	_check("rings_on_route", ar.rings().size() >= 6 and far_rings.is_empty(), "колец %d, далеко от линии: %s" % [ar.rings().size(), str(far_rings)])
	_check("hazards_present", ar.presses().size() == 3 and ar.magnets().size() == 2 and ar.bridges().size() == 7 and ar.barrels().size() == 6,
		"прессов %d, магнитов %d, мостов %d, бочек %d" % [ar.presses().size(), ar.magnets().size(), ar.bridges().size(), ar.barrels().size()])
	await _unload()


## Геометрия карты в JSON (path): твёрдое (прямоугольники коллизии, sky — невидимое под небом), линия ботов по отрезкам, контрольные
## точки, поля, сетки KO, прессы, магниты, мосты, бочки, кольца, метки порталов, финиш — для схемы трассы (tools: рисует Python).
func _dump(path: String) -> void:
	print("--- dump")
	await _load(true, 2, 60.0)
	var ar := pg.arena
	var out := {"solid": [], "route": [], "cps": [], "zones": [], "grids": [], "presses": [], "magnets": [], "bridges": [], "barrels": [],
		"rings": [], "portals": [], "finish_x": ar.finish_x(), "sections": ar.sections()}
	for body in ar.get_node("Solid").get_children():
		if not (body is StaticBody3D):
			continue
		for cs in body.get_children():
			var sh := (cs as CollisionShape3D).shape as BoxShape3D
			var c := (cs as Node3D).global_position
			out["solid"].append([c.x - sh.size.x * 0.5, c.y - sh.size.y * 0.5, sh.size.x, sh.size.y])
	var rt := ar.route()
	for sg in rt.segs:
		var pts: Array = []
		for i in sg.pts.size():
			pts.append([sg.pts[i].x, sg.pts[i].y])
			if TrackRoute.is_jump(sg, i):   # перенос порталом — линия рвётся
				out["route"].append({"name": sg.name, "kind": sg.kind, "fork": sg.fork, "pts": pts})
				pts = []
		out["route"].append({"name": sg.name, "kind": sg.kind, "fork": sg.fork, "pts": pts})
	for c in ar.checkpoints():
		out["cps"].append([(c as Node3D).global_position.x, (c as TrackCheckpoint).gate_h, (c as TrackCheckpoint).index])
	for z in ar.find_children("*", "TrackZone", true, false):
		var tz := z as TrackZone
		var r := tz.rect()
		out["zones"].append([r.position.x, r.position.y, r.size.x, r.size.y, tz.dir.x, tz.dir.y, TrackZone.tuning_g(tz.g_key, tz.g_units)])
	for g in ar.find_children("*", "TrackGrid", true, false):
		var r2 := (g as TrackGrid).rect()
		out["grids"].append([r2.position.x, r2.position.y, r2.size.x, r2.size.y, (g as TrackGrid).kind])
	for p in ar.presses():
		out["presses"].append((p as Node3D).global_position.x)
	for m in ar.magnets():
		var pole := (m as MagnetMachine).pole_global()
		out["magnets"].append([pole.x, pole.y])
	for b in ar.bridges():
		out["bridges"].append((b as Node3D).global_position.x)
	for b in ar.barrels():
		out["barrels"].append((b as Node3D).global_position.x)
	for r3 in ar.rings():
		out["rings"].append([(r3 as Node3D).global_position.x, (r3 as Node3D).global_position.y])
	for s in ar.portal_slots():
		var n: Vector3 = (s as Node3D).get_meta("normal", Vector3.ZERO)
		out["portals"].append([(s as Node3D).global_position.x, (s as Node3D).global_position.y, n.x, String((s as Node).name)])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out))
		f.close()
	print("dump → ", path)
	await _unload()


## ASCII-карта слоя кукол (|z| ≤ 0.2), шаг 1 м по x и 0.5 м по y: # — статика, ~ — зона KO, R — линия ботов, C — контрольная точка.
func _grid() -> void:
	print("--- grid")
	await _load(true, 2, 60.0)
	var space := pg.get_world_3d().direct_space_state
	var rt := pg.arena.route()
	var route_cells := {}
	for sg in rt.segs:
		for i in sg.pts.size() - 1:
			var a := sg.pts[i]
			var b := sg.pts[i + 1]
			var n := int(a.distance_to(b) / 0.25) + 1
			for k in n + 1:
				var p := a.lerp(b, float(k) / float(n))
				route_cells[Vector2i(int(floor(p.x)), int(floor(p.y * 2.0)))] = true
	var y := 15.0
	while y >= -18.0:
		var row := "%6.1f " % y
		var x := -10.0
		while x < 428.0:
			var ch := "."
			if _static_hit(space, Vector3(0.9, 0.45, 0.4), Vector2(x + 0.5, y + 0.25)) != "":
				ch = "#"
			elif route_cells.has(Vector2i(int(x), int(floor(y * 2.0)))):
				ch = "R"
			row += ch
			x += 1.0
		print(row)
		y -= 0.5
	await _unload()


# ------------------------------------------------------------------ sections

## Один участок ботом P1: остальные заморожены у стенки старта. Возврат на точку участка (cp), гонка до следующей точки (или финиша).
func _section_run(sec: int, branch: String, level: int, max_s: float, trace: bool) -> Dictionary:
	var forks := {2: "A", 3: "B", 4: "C"}
	TrackBrain.force_choices = {}
	if forks.has(sec) and branch != "":
		TrackBrain.force_choices = {0: {forks[sec]: branch}}
	await _load(true, level, 0.3)
	await _until(func() -> bool: return tm.play_state == "play", 5.0)
	for pi in range(1, Tuning.TRACK_RACERS):
		_freeze(_doll(pi), Vector3(-5.5, 3.0 + 2.5 * float(pi), 0.0))
	var d := _doll(0)
	var st := tm.state_of(d)
	var cp := sec - 1
	if cp > 0:
		st["cp"] = cp
		tm.drop(d, "reset")
		await _until(func() -> bool: return _doll(0) != null and _doll(0).alive and _doll(0) != d, Tuning.TRACK_RESPAWN_S + 1.0)
	d = _doll(0)
	var t0 := tm.fight_time
	var goal_prog := float(tm.cp_prog[sec]) if sec < tm.cp_prog.size() else INF
	var drops0 := tm.journal.filter(func(e: Dictionary) -> bool: return int(e["pi"]) == 0 and String(e["what"]) in ["ko", "fall", "stuck", "reset"]).size()
	var pair := pg.arena.portal_pair()
	var hist0 := pair.history.size() if pair != null else 0
	var anchor := Vector3.INF
	var anchor_t := 0.0
	var stuck_max := 0.0
	var trace_t := 0.0
	while tm.fight_time - t0 < max_s:
		await get_tree().physics_frame
		var cur := _doll(0)
		var cst := tm.state_of(cur)
		if bool(cst["finished"]) or (float(cst["prog"]) >= goal_prog and int(cst["cp"]) >= sec):
			break
		if cur.alive:
			var c := cur.centre_of_mass()
			if anchor == Vector3.INF or anchor.distance_to(c) > STUCK_R:
				anchor = c
				anchor_t = tm.fight_time
			stuck_max = maxf(stuck_max, tm.fight_time - anchor_t)
		if trace and tm.fight_time - trace_t >= 2.0:
			trace_t = tm.fight_time
			var br := cur.get_node_or_null(TrackPlayground.BRAIN) as TrackBrain
			var cc := cur.centre_of_mass()
			print("    t=%5.1f (%.1f, %.1f) prog %.1f cp %d %s %s v %.1f charge %.0f" % [tm.fight_time - t0, cc.x, cc.y, float(cst["prog"]),
				int(cst["cp"]), br.state if br != null else "-", (route_seg_name(br) if br != null else ""), cur.torso().linear_velocity.length(), cur.charge])
	var cur2 := _doll(0)
	var cst2 := tm.state_of(cur2)
	var done := bool(cst2["finished"]) or (float(cst2["prog"]) >= goal_prog and int(cst2["cp"]) >= sec)
	var drops := tm.journal.filter(func(e: Dictionary) -> bool: return int(e["pi"]) == 0 and String(e["what"]) in ["ko", "fall", "stuck", "reset"]).size() - drops0
	var whys: Array = tm.journal.filter(func(e: Dictionary) -> bool: return int(e["pi"]) == 0 and String(e["what"]) in ["ko", "fall", "stuck"]).map(
		func(e: Dictionary) -> String: return "%s@%.0f(%s)" % [e["what"], e["t"], str(e.get("at", ""))])
	var br2 := cur2.get_node_or_null(TrackPlayground.BRAIN) as TrackBrain
	var ab := 0
	var ba := 0
	if pair != null:
		for h in pair.history.slice(hist0):
			if (h as Dictionary).get("kind", "") != "doll":
				continue
			if String(h.get("from", "")) == "A":
				ab += 1
			else:
				ba += 1
	return {"done": done, "s": snappedf(tm.fight_time - t0, 0.1), "drops": drops, "whys": whys, "stuck_max": snappedf(stuck_max, 0.1),
		"portal_ab": ab, "portal_ba": ba,
		"branches": (cst2["branches"] as Dictionary).duplicate(), "hold_s": snappedf(br2.hold_s, 0.1) if br2 != null else 0.0,
		"dash_ticks": br2.forced_dash_ticks if br2 != null else 0}


static func route_seg_name(br: TrackBrain) -> String:
	if br == null or br.route == null or br.seg < 0:
		return "-"
	return br.route.segs[br.seg].name


func _sections(level: int, only_sec: String, only_branch: String, trace: bool) -> void:
	var runs := [[1, ""], [2, "easy"], [2, "hard"], [3, "easy"], [3, "hard"], [4, "easy"], [4, "hard"], [5, ""], [6, ""]]
	var res := {}
	for r in runs:
		if only_sec != "" and str(r[0]) != only_sec:
			continue
		if only_branch != "" and String(r[1]) != "" and String(r[1]) != only_branch:
			continue
		var key := "S%d%s" % [int(r[0]), ("_" + String(r[1])) if String(r[1]) != "" else ""]
		print("--- section %s" % key)
		var out := await _section_run(int(r[0]), String(r[1]), level, 90.0, trace)
		res[key] = out
		var fork_ok := String(r[1]) == "" or String((out["branches"] as Dictionary).get({2: "A", 3: "B", 4: "C"}[int(r[0])], "")) == String(r[1])
		var portal_ok := int(out["portal_ba"]) == 0 and (int(out["portal_ab"]) == 1 if key == "S3_hard" else int(out["portal_ab"]) == 0)
		_check("section_%s" % key, bool(out["done"]) and int(out["drops"]) == 0 and fork_ok and portal_ok and float(out["stuck_max"]) <= 10.0,
			"пройден: %s за %.1f с, возвратов %d %s, на месте до %.1f с, ветки %s, ждал прессов %.1f с, порталом A→B %d / B→A %d" % [
			str(out["done"]), float(out["s"]), int(out["drops"]), str(out["whys"]), float(out["stuck_max"]), str(out["branches"]),
			float(out["hold_s"]), int(out["portal_ab"]), int(out["portal_ba"])])
	info["sections_level%d" % level] = res
	TrackBrain.force_choices = {}
	await _unload()


# ------------------------------------------------------------------ checks

func _checks() -> void:
	print("--- checks")
	await _load(true, 2, 0.3)
	await _until(func() -> bool: return tm.play_state == "play", 5.0)
	for pi in Tuning.TRACK_RACERS:
		_silence(_doll(pi), true)
	var ar := pg.arena
	# 0) пара развилки B — односторонняя (PORTAL.md, 06.10): кукла влетает в B (выход) на 6 м/с — не переносится, к A не попадает
	var opair := ar.portal_pair()
	if opair != null:
		var pw := _doll(3)
		var home := pw.centre_of_mass()
		var t_b := opair.transfers
		_teleport(pw, opair.b.global_position + opair.b.normal() * 1.4)
		for b in pw.parts.values():
			(b as RigidBody3D).linear_velocity = -opair.b.normal() * 6.0
		var near_a := false
		for k in int(1.5 / (1.0 / 60.0)):
			near_a = near_a or pw.centre_of_mass().distance_to(opair.a.global_position) < 3.0
			await get_tree().physics_frame
		var moved := opair.transfers - t_b
		var in_b := opair.b.height_of(pw.centre_of_mass()) < 1.2
		info["portal_one_way"] = {"transfers": moved, "near_a": near_a, "doll_at_b": in_b, "one_way": opair.one_way, "b_exit_only": opair.b.exit_only}
		_check("portal_b_one_way", opair.one_way and opair.b.exit_only and moved == 0 and not near_a,
			"влёт в B на 6 м/с: переносов %d, у A %s, кукла у щели B %s (пара односторонняя %s)" % [moved, str(near_a), str(in_b), str(opair.one_way)])
		_teleport(pw, home)
	# 1) яма: P1 с точкой 5 — в дно ямы → возврат у CP5 через TRACK_RESPAWN_S
	var p1 := _doll(0)
	tm.state_of(p1)["cp"] = 5
	var t_fall := tm.fight_time
	_teleport(p1, Vector3(369.0, -14.0, 0.0))
	await _until(func() -> bool: return not _doll(0).alive, 2.0)
	var fell_ok := not _doll(0).alive and tm.respawn_why(_doll(0)) == "fall"
	await _until(func() -> bool: return _doll(0).alive, Tuning.TRACK_RESPAWN_S + 1.0)
	var t_back := tm.fight_time - t_fall
	var np1 := _doll(0)
	var want1 := (ar.checkpoints()[5] as TrackCheckpoint).spawn_for(0)
	var d1 := Vector2(np1.global_position.x - want1.x, np1.global_position.y - want1.y).length()
	_check("fall_respawn", fell_ok and np1.alive and d1 < 0.6 and absf(t_back - Tuning.TRACK_RESPAWN_S) < 0.35,
		"яма → KO (fall): %s; вернулся через %.2f с в %.2f м от места у CP5" % [str(fell_ok), t_back, d1])
	var dp := tm.progress_of(np1) - float(tm.cp_prog[5])
	_check("respawn_progress", dp > -6.0 and dp < 1.0 and int(tm.state_of(np1)["cp"]) == 5,
		"прогресс после возврата %.1f (точка %.1f; места возврата — до 4.5 м позади ворот), точка %d" % [tm.progress_of(np1),
		float(tm.cp_prog[5]), int(tm.state_of(np1)["cp"])])
	# 2) KO ударом: P2 с точкой 2 → knock_out(атакующий P3) → у CP2
	var p2 := _doll(1)
	tm.state_of(p2)["cp"] = 2
	var t_ko := tm.fight_time
	p2.knock_out(_doll(2), {"kind": "hit"})
	await _until(func() -> bool: return _doll(1).alive and _doll(1) != p2, Tuning.TRACK_RESPAWN_S + 1.0)
	var np2 := _doll(1)
	var want2 := (ar.checkpoints()[2] as TrackCheckpoint).spawn_for(1)
	var d2 := Vector2(np2.global_position.x - want2.x, np2.global_position.y - want2.y).length()
	_check("ko_respawn", np2.alive and d2 < 0.6 and absf(tm.fight_time - t_ko - Tuning.TRACK_RESPAWN_S) < 0.35 and int(tm.state_of(_doll(2))["kos"]) == 1,
		"KO ударом → вернулся через %.2f с в %.2f м от места у CP2; нокаутов у P3: %d" % [tm.fight_time - t_ko, d2, int(tm.state_of(_doll(2))["kos"])])
	# 3) сетка в потолке короткого пути C: P4 с точкой 3
	var p4 := _doll(3)
	tm.state_of(p4)["cp"] = 3
	_teleport(p4, Vector3(253.0, 11.6, 0.0))
	await _until(func() -> bool: return not _doll(3).alive, 1.5)
	var grid_ok := not _doll(3).alive and tm.respawn_why(_doll(3)) == "fall"
	await _until(func() -> bool: return _doll(3).alive, Tuning.TRACK_RESPAWN_S + 1.0)
	var want4 := (ar.checkpoints()[3] as TrackCheckpoint).spawn_for(3)
	var d4 := Vector2(_doll(3).global_position.x - want4.x, _doll(3).global_position.y - want4.y).length()
	_check("grid_respawn", grid_ok and _doll(3).alive and d4 < 0.6, "сетка KO → fall: %s; вернулся в %.2f м от места у CP3" % [str(grid_ok), d4])
	# 4) «застрял»: P3 висит без ввода (управление есть) — через TRACK_STUCK_S drop(stuck)
	var p3 := _doll(2)
	tm.state_of(p3)["cp"] = 1
	_teleport(p3, Vector3(70.0, 6.0, 0.0))
	tm.state_of(p3)["stuck_t"] = 0.0
	tm.state_of(p3)["stuck_anchor"] = tm.progress_of(p3)
	var t_st := tm.fight_time
	await _until(func() -> bool: return not _doll(2).alive, Tuning.TRACK_STUCK_S + 2.0)
	var st_after := tm.fight_time - t_st
	var stuck_ok := not _doll(2).alive and tm.respawn_why(_doll(2)) == "stuck"
	await _until(func() -> bool: return _doll(2).alive, Tuning.TRACK_RESPAWN_S + 1.0)
	var want3 := (ar.checkpoints()[1] as TrackCheckpoint).spawn_for(2)
	var d3 := Vector2(_doll(2).global_position.x - want3.x, _doll(2).global_position.y - want3.y).length()
	_check("stuck_respawn", stuck_ok and absf(st_after - Tuning.TRACK_STUCK_S) < 0.6 and _doll(2).alive and d3 < 0.6,
		"висел без продвижения → «застрял» через %.1f с (%s), вернулся в %.2f м от места у CP1" % [st_after, str(stuck_ok), d3])
	# 5) Q (reset): P1 → через TRACK_RESPAWN_S у своей точки (5)
	var q1 := _doll(0)
	var t_q := tm.fight_time
	tm.drop(q1, "reset")
	await _until(func() -> bool: return _doll(0).alive and _doll(0) != q1, Tuning.TRACK_RESPAWN_S + 1.0)
	var dq := Vector2(_doll(0).global_position.x - want1.x, _doll(0).global_position.y - want1.y).length()
	_check("reset_respawn", absf(tm.fight_time - t_q - Tuning.TRACK_RESPAWN_S) < 0.35 and dq < 0.6 and int(tm.state_of(_doll(0))["resets"]) == 1,
		"Q → вернулся через %.2f с в %.2f м от места у CP5" % [tm.fight_time - t_q, dq])
	# 6) кольцо: P2 сквозь кольцо 1 — +Заряд, второй раз — нет
	var p2b := _doll(1)
	var ring := ar.rings()[0] as Node3D
	tm.state_of(p2b)["cp"] = 0
	p2b.charge = 10.0
	_teleport(p2b, ring.global_position)
	await _wait(0.1)
	var c1 := p2b.charge
	_teleport(p2b, ring.global_position + Vector3(3.0, 0.0, 0.0))
	await _wait(0.1)
	_teleport(p2b, ring.global_position)
	await _wait(0.1)
	var c2 := p2b.charge
	_check("ring_charge_once", c1 >= 10.0 + Tuning.TRACK_RING_CHARGE - 1.0 and c2 <= c1 + 1.5,
		"Заряд 10 → %.1f после кольца, повторно → %.1f" % [c1, c2])
	# 7) финиш: P3 за линией — место 1; через TRACK_FINISH_WAIT_S — итоги, остальные — по пройденному пути
	var p3f := _doll(2)
	tm.state_of(p3f)["cp"] = 5
	tm.state_of(p3f)["prog"] = tm.total_m() - 10.0
	_teleport(p3f, Vector3(ar.finish_x() + 2.0, 2.5, 0.0))
	await _until(func() -> bool: return bool(tm.state_of(_doll(2))["finished"]), 1.0)
	var t_fin := tm.fight_time
	var placed := tm.place_of(_doll(2))
	await _until(func() -> bool: return over_count > 0, Tuning.TRACK_FINISH_WAIT_S + 2.0)
	var waited := tm.fight_time - t_fin
	var pl: Array = over_results.get("places", [])
	var rest_ok := true
	for i in range(2, pl.size()):
		rest_ok = rest_ok and tm.progress_of(pl[i - 1] as Doll) >= tm.progress_of(pl[i] as Doll)
	_check("finish_wait_places", placed == 1 and over_count == 1 and String(over_results.get("end_reason", "")) == "wait"
		and absf(waited - Tuning.TRACK_FINISH_WAIT_S) < 0.3 and not pl.is_empty() and (pl[0] as Doll) == _doll(2) and rest_ok
		and int(over_results.get("winner_index", -1)) == 2,
		"P3 за финишем — место %d; итоги через %.1f с (%s), первый — P%d, остальные по пути: %s" % [placed, waited,
		String(over_results.get("end_reason", "")), int(over_results.get("winner_index", -1)) + 1, str(rest_ok)])
	await _unload()


# ------------------------------------------------------------------ hazards

## Препятствия по отдельности (мозги сняты, куклы ставит проба): тяжёлое поле без ускорения не поднять / с ускорением — да; встречное
## поле сносит; поле вверх уносит в сетку KO; мембрана трубы отталкивает; магнит тянет; пресс бьёт; мост рвётся и встаёт; бочка рвётся.
func _hazards() -> void:
	print("--- hazards")
	await _load(true, 2, 0.3)
	await _until(func() -> bool: return tm.play_state == "play", 5.0)
	for pi in Tuning.TRACK_RACERS:
		_freeze(_doll(pi), Vector3(-5.5, 3.0 + 2.5 * float(pi), 0.0))
	var ar := pg.arena
	# 1) тяжёлое поле: вверх обычной тягой — тонет; с ускорением — поднимается
	var d := _unfreeze(_doll(0), Vector3(303.0, 4.0, 0.0))
	d.charge = 100.0
	d.input_vec = Vector2(0.0, 1.0)
	var y0 := d.centre_of_mass().y
	await _wait(1.5)
	var y1 := d.centre_of_mass().y
	_teleport(d, Vector3(303.0, 4.0, 0.0))
	await get_tree().physics_frame
	var y2 := d.centre_of_mass().y
	for i in 60:
		d.request_dash()
		await get_tree().physics_frame
	var y3 := d.centre_of_mass().y
	d.input_vec = Vector2.ZERO
	info["heavy"] = {"up_no_dash_m": snappedf(y1 - y0, 0.01), "up_dash_1s_m": snappedf(y3 - y2, 0.01), "g": Tuning.TRACK_HEAVY_G}
	_check("heavy_needs_dash", y1 - y0 <= 0.3 and y3 - y2 >= 1.5,
		"поле %.2f G: вверх без ускорения за 1.5 с %+.2f м, с ускорением за 1 с %+.2f м" % [Tuning.TRACK_HEAVY_G, y1 - y0, y3 - y2])
	_freeze(d, Vector3(-5.5, 3.0, 0.0))
	# 2) встречное поле участка 4 сносит назад (без ввода)
	var d2 := _unfreeze(_doll(1), Vector3(228.0, 7.0, 0.0))
	var x0 := d2.centre_of_mass().x
	await _wait(2.0)
	var dx := d2.centre_of_mass().x - x0
	_check("side_field_pushes", dx < -1.0, "без ввода во встречном поле за 2 с сдвиг по x %+.2f м" % dx)
	_freeze(d2, Vector3(-5.5, 5.5, 0.0))
	# 3) поле вверх в коробе развилки C уносит в сетку KO
	var d3 := _unfreeze(_doll(2), Vector3(250.0, 10.3, 0.0))
	tm.state_of(d3)["cp"] = 3
	await _until(func() -> bool: return not _doll(2).alive, 4.0)
	var up_ko := not _doll(2).alive and tm.respawn_why(_doll(2)) == "fall"
	_check("up_field_into_grid", up_ko, "без ввода в коробе с полем вверх — в сетку и KO: %s" % str(up_ko))
	await _until(func() -> bool: return _doll(2).alive, Tuning.TRACK_RESPAWN_S + 1.0)
	_freeze(_doll(2), Vector3(-5.5, 8.0, 0.0))
	# 4) мембрана трубы (P1 лёгкого пути B, потолок y 3.4): тяга вверх в стенку — отталкивает, сквозь не пускает
	var mem := ar.get_node("Hazards/Membranes") as TrackMembrane
	var p0 := mem.pushes
	var d4 := _unfreeze(_doll(3), Vector3(151.0, 1.7, 0.0))
	d4.input_vec = Vector2(0.0, 1.0)
	var top := -INF
	for i in 90:
		await get_tree().physics_frame
		var head: Node3D = d4.parts.get("Head", d4.torso())
		top = maxf(top, head.global_position.y)
	d4.input_vec = Vector2.ZERO
	_check("membrane_pushes", mem.pushes > p0 and mem.max_pen > 0.05 and top < 3.4,
		"тяга в потолок трубы: толчков мембраны %d, вдавливание до %.2f м, голова не выше %.2f (стенка 3.4)" % [mem.pushes - p0, mem.max_pen, top])
	_freeze(d4, Vector3(-5.5, 10.5, 0.0))
	# 5) магнит тянет к полюсу
	var mg := ar.get_node("Machines/Magnet1") as MagnetMachine
	var pull := ar.get_node("Machines/MagnetPull1") as TrackMagnetPull
	var d5 := _unfreeze(_doll(0), Vector3(mg.pole_global().x, 17.0, 0.0))
	mg.force_state(ScrapMachine.State.ACTIVE)
	var c0 := d5.centre_of_mass()
	await _wait(0.8)
	var pole := mg.pole_global()
	var closer := c0.distance_to(pole) - d5.centre_of_mass().distance_to(pole)
	_check("magnet_pulls", closer > 0.4 and pull.last_force > 0.0 or pull.pull_ticks > 0 and closer > 0.4,
		"магнит включён: кукла на %.2f м ближе к полюсу за 0.8 с, сила %.0f Н" % [closer, pull.last_force])
	mg.force_state(ScrapMachine.State.OFF)
	_freeze(d5, Vector3(-5.5, 3.0, 0.0))
	# 6) пресс бьёт куклу под ползуном
	var pr := ar.get_node("Machines/Press1") as PressMachine
	var d6 := _unfreeze(_doll(1), Vector3(pr.global_position.x, 1.6, 0.0))
	d6.grace_until = 0.0
	var hp0 := d6.hp
	var hits0 := pr.hits.size()
	pr.force_state(ScrapMachine.State.ACTIVE)
	await _wait(0.4)
	_check("press_hits", pr.hits.size() > hits0 and (d6.hp < hp0 or not d6.alive),
		"удар пресса: попаданий %d, HP %.0f → %.0f" % [pr.hits.size() - hits0, hp0, d6.hp if d6.alive else 0.0])
	await _wait(2.5)
	if _doll(1).alive:
		_freeze(_doll(1), Vector3(-5.5, 5.5, 0.0))
	# 7) мост рвётся под куклой и встаёт заново
	var br := ar.get_node("Hazards/Bridge3") as TrackBridgeSlot
	var d7 := _unfreeze(_doll(3), Vector3(br.global_position.x + 2.0, 1.2, 0.0))
	tm.state_of(d7)["cp"] = 5
	await _until(func() -> bool: return not br.intact(), 3.0)
	var broke := not br.intact() and br.breaks >= 1
	var t_b := tm.fight_time
	await _until(func() -> bool: return br.intact(), Tuning.TRACK_BRIDGE_RESPAWN_S + 2.0)
	_check("bridge_breaks_respawns", broke and br.intact() and absf(tm.fight_time - t_b - Tuning.TRACK_BRIDGE_RESPAWN_S) < 0.5,
		"мост под куклой порвался: %s, встал заново через %.1f с" % [str(broke), tm.fight_time - t_b])
	if _doll(3).alive:
		_freeze(_doll(3), Vector3(-5.5, 10.5, 0.0))
	# 8) бочка: кукла рядом — поджиг, взрыв, новая
	var bs := ar.get_node("Hazards/Barrel2") as TrackBarrelSlot
	var d8 := _unfreeze(_doll(0), bs.global_position + Vector3(-1.2, 1.0, 0.0))
	tm.state_of(d8)["cp"] = 5
	await _until(func() -> bool: return bs.explosions >= 1, 3.0)
	var boom := bs.ignitions >= 1 and bs.explosions >= 1
	await _until(func() -> bool: return bs.alive(), Tuning.TRACK_BARREL_RESPAWN_S + 2.0)
	_check("barrel_fuse_respawn", boom and bs.alive(), "кукла рядом: поджогов %d, взрывов %d, новая бочка: %s" % [bs.ignitions, bs.explosions, str(bs.alive())])
	await _unload()


## Сводка бот-гонок по уровням: время победителя и последнего (мин–макс), возвраты по причинам, дольше всего на месте.
func _bots_summary() -> void:
	var by := {}
	for k in info.keys():
		if not String(k).begins_with("bots_s"):
			continue
		var lv := String(k).get_slice("_l", 1)
		var r: Dictionary = info[k]
		if not by.has(lv):
			by[lv] = {"races": 0, "winner_s": [INF, -INF], "last_s": [INF, -INF], "stuck_max_s": 0.0, "drops": {"ko": 0, "fall": 0, "stuck": 0}}
		var b: Dictionary = by[lv]
		b["races"] = int(b["races"]) + 1
		var w := float(r["winner_s"])
		var l := float(r["race_s"])
		b["winner_s"] = [minf(b["winner_s"][0], w), maxf(b["winner_s"][1], w)]
		b["last_s"] = [minf(b["last_s"][0], l), maxf(b["last_s"][1], l)]
		b["stuck_max_s"] = maxf(float(b["stuck_max_s"]), float(r["stuck_max_s"]))
		for why in ["ko", "fall", "stuck"]:
			b["drops"][why] = int(b["drops"][why]) + int((r["drops"] as Dictionary).get(why, 0))
	info["bots_summary"] = by
	print("  bots summary: " + JSON.stringify(by))


## Разморозить куклу-зрителя и поставить ЦМ в at (управление есть, ввод — у пробы).
func _unfreeze(d: Doll, at: Vector3) -> Doll:
	for p in d.parts.values():
		var b := p as RigidBody3D
		if b != null and is_instance_valid(b):
			b.freeze = false
	_teleport(d, at)
	d.control_enabled = true
	d.external_input = true
	d.input_vec = Vector2.ZERO
	return d


# ------------------------------------------------------------------ bots

func _bots(seed_v: int, level: int, max_s: float, stuck_s: float, trace: bool) -> void:
	print("--- bots seed %d level %d" % [seed_v, level])
	TrackBrain.force_choices = {}
	await _load(true, level, 3.0, seed_v)
	tm.finish_wait_s = max_s   # проба ждёт всех (правило «30 с после первого» проверяет checks)
	var b: AABB = pg.arena.bounds()
	var anchor: Dictionary = {}
	var stuck_max := 0.0
	var stuck_who := ""
	var oob := 0
	var oob_who := ""
	var hits := {"n": 0}
	tm.hit.connect(func(_v: Doll, a: Node, dmg: float, _k: String, _p: Vector3) -> void:
		if a is Doll and dmg > 0.0:
			hits["n"] = int(hits["n"]) + 1)
	var pair := pg.arena.portal_pair()
	var pockets: Array = []
	if pair != null:
		for pt in pair.portals():
			pockets.append((pt as Portal).pocket_rect())
	var moved: Array = []              # [player_index, откуда] — переносы кукол парой (сигнал: кукла после KO уже пересоздана)
	if pair != null:
		pair.transferred.connect(func(what: Node3D, from: Portal, _to: Portal) -> void:
			if what is Doll:
				moved.append([(what as Doll).player_index, String(from.name)]))
	var in_pocket: Dictionary = {}     # pi → с какого времени ЦМ в кармане
	var pocket_max := 0.0
	var t0 := Time.get_ticks_usec()
	var frames := 0
	var trace_t := 0.0
	while over_count == 0 and tm.fight_time < max_s:
		await get_tree().physics_frame
		frames += 1
		if tm.play_state != "play":
			continue
		for d in tm.dolls():
			var dd := d as Doll
			var st := tm.state_of(dd)
			if not dd.alive or bool(st["finished"]):
				anchor.erase(dd.player_index)
				continue
			var c := dd.centre_of_mass()
			var inside := false
			for r in pockets:
				inside = inside or (r as Rect2).has_point(Vector2(c.x, c.y))
			if inside:
				if not in_pocket.has(dd.player_index):
					in_pocket[dd.player_index] = tm.fight_time
				pocket_max = maxf(pocket_max, tm.fight_time - float(in_pocket[dd.player_index]))
			else:
				in_pocket.erase(dd.player_index)
			if c.x < b.position.x or c.x > b.end.x or c.y < b.position.y or c.y > b.end.y:
				oob += 1
				oob_who = "P%d (%.1f, %.1f)" % [dd.player_index + 1, c.x, c.y]
			var an: Array = anchor.get(dd.player_index, [])
			if an.is_empty() or (an[0] as Vector3).distance_to(c) > STUCK_R:
				anchor[dd.player_index] = [c, tm.fight_time]
			elif tm.fight_time - float(an[1]) > stuck_max:
				stuck_max = tm.fight_time - float(an[1])
				var br := dd.get_node_or_null(TrackPlayground.BRAIN) as TrackBrain
				stuck_who = "P%d (%.1f, %.1f) %s %s" % [dd.player_index + 1, c.x, c.y, br.state if br != null else "-", route_seg_name(br)]
		if trace and tm.fight_time - trace_t >= 10.0:
			trace_t = tm.fight_time
			var row := []
			for d in tm.standings():
				var dd2 := d as Doll
				var br2 := dd2.get_node_or_null(TrackPlayground.BRAIN) as TrackBrain
				var cm := dd2.centre_of_mass()
				row.append("P%d:%s %.0f%% (%.0f,%.0f)%s" % [dd2.player_index + 1, route_seg_name(br2), tm.fraction_of(dd2) * 100.0, cm.x, cm.y,
					"" if dd2.alive else "†"])
			print("  t=%5.1f  %s" % [tm.fight_time, " ".join(row)])
	var wall_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var per := {}
	var all_done := true
	var drops := {"ko": 0, "fall": 0, "stuck": 0, "reset": 0}
	var where: Array = []
	for e in tm.journal:
		if drops.has(String(e["what"])):
			drops[String(e["what"])] = int(drops[String(e["what"])]) + 1
			where.append("P%d %s@%.0f с %s" % [int(e["pi"]) + 1, e["what"], float(e["t"]), str(e.get("at", ""))])
	var res: Dictionary = over_results.get("racers", {})
	for d in tm.dolls():
		var pi := (d as Doll).player_index
		var r: Dictionary = res.get(pi, {})
		all_done = all_done and bool(r.get("finished", false))
		per["P%d" % (pi + 1)] = {"place": int(r.get("place", 0)), "t": snappedf(float(r.get("finish_t", -1.0)), 0.1),
			"branches": r.get("branches", {}), "kos_taken": int(r.get("kos_taken", 0)), "falls": int(r.get("falls", 0)),
			"stucks": int(r.get("stucks", 0))}
	# места: по времени финиша
	var order_ok := not over_results.is_empty()
	var fo: Array = over_results.get("finish_order", [])
	var prev_t := -1.0
	for pi in fo:
		var t := float((res.get(pi, {}) as Dictionary).get("finish_t", -1.0))
		order_ok = order_ok and t >= prev_t
		prev_t = t
	var places: Array = over_results.get("places", [])
	if not places.is_empty() and not fo.is_empty():
		order_ok = order_ok and (places[0] as Doll).player_index == int(fo[0]) and int(over_results.get("winner_index", -1)) == int(fo[0])
	for i in mini(places.size(), fo.size()):
		order_ok = order_ok and (places[i] as Doll).player_index == int(fo[i])
	var p_ab := 0
	var p_ba := 0
	var p_per := {}
	for mv in moved:
		var who := "P%d" % (int(mv[0]) + 1)
		if String(mv[1]) == "A":
			p_ab += 1
			p_per[who] = int(p_per.get(who, 0)) + 1
		else:
			p_ba += 1
	var hard_b := 0
	for d in tm.dolls():
		if String((res.get((d as Doll).player_index, {}) as Dictionary).get("branches", {}).get("B", "")) == "hard":
			hard_b += 1
	var key := "bots_s%d_l%d" % [seed_v, level]
	info[key] = {"race_s": snappedf(tm.fight_time, 0.1), "winner_s": snappedf(float(over_results.get("winner_time", -1.0)), 0.1),
		"racers": per, "drops": drops, "drops_at": where, "hits": int(hits["n"]), "portal_ab": p_ab, "portal_ba": p_ba,
		"portal_by": p_per, "b_hard": hard_b, "pocket_max_s": snappedf(pocket_max, 0.1), "stuck_max_s": snappedf(stuck_max, 0.1), "end": String(over_results.get("end_reason", "")),
		"ms_per_physics_frame": snappedf(wall_ms / maxf(frames, 1), 0.01)}
	print("  " + JSON.stringify(info[key]))
	_check(key + "_finish", over_count == 1 and all_done and String(over_results.get("end_reason", "")) == "all",
		"все доехали: %s, гонка %.1f с (лимит %.0f), победитель %.1f с, конец %s" % [str(all_done), tm.fight_time, max_s,
		float(over_results.get("winner_time", -1.0)), String(over_results.get("end_reason", "—"))])
	_check(key + "_not_stuck", stuck_max <= stuck_s, "дольше всего на месте (в круге %.1f м) %.1f с — %s" % [STUCK_R, stuck_max, stuck_who])
	_check(key + "_in_bounds", oob == 0, "тиков вне границ %d %s" % [oob, oob_who])
	_check(key + "_portal", p_ba == 0 and pocket_max <= 1.0 and p_ab >= hard_b,
		"порталом A→B %d (короткую ветку B взяли %d), назад B→A %d, дольше всего в кармане %.1f с" % [p_ab, hard_b, p_ba, pocket_max])
	_check(key + "_places", order_ok, "порядок финиша %s, места %s" % [str(fo), str(places.map(func(d: Doll) -> int: return d.player_index))])
	await _unload()
