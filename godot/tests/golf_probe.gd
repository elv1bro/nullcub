## Проба «Гольфа: кукла — мяч» (docs/plan-demo/GOLF.md) на настоящей площадке scenes/playground_golf.tscn (купол, поле лунок, GolfMatch,
## GolfHud). Секции:
##   rules (оба игрока — боты с выключенными мозгами, удары даёт проба): запуск на полной силе не отрывает детали и не тянет суставы
##     (прочность выключена); в полёте кукла обмякшая (стан, мышц нет) и без управления — ввод её не двигает; поправка — ровно одна за
##     удар (Δv = GOLF_NUDGE_DV); конец удара по скорости (кукла легла) и по таймеру (кукла всё время катится); яма → +1 и назад на место
##     удара; лунка засчитывается через GOLF_CUP_HOLD_S в чаше и не засчитывается, если выбили раньше; удары и штрафы считаются верно;
##     прочность суставов: потерял деталь за удар — +1;
##   holes: каждая лунка проходима сценарным ударом с известными углом и силой (SCRIPTED); на лунке 3 поле вбок реально гнёт полёт
##     (тот же удар с полем и без поля);
##   bots: два бота играют матч (3 лунки) с несколькими зёрнами: каждый закрывает каждую лунку в чаше (не по лимиту) не больше чем
##     за пар + 3; никто не стоит вне чаши дольше STUCK_LIMIT_S (бот всегда бьёт), лунка кончается раньше GOLF_HOLE_MAX_S;
##     печатает среднее число ударов по лункам (по нему подобран пар).
## Все секции: ошибок скриптов (Logger) и движка — 0.
## Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/golf_probe.tscn -- "only=rules|holes|bots|rules+holes,seeds=1+2+3,level=2,trace=1,out=<json>"
## → JSON между === GOLF PROBE === и === OK / FAIL ===, exit 0/1.
extends Node

const SCENE := "res://scenes/playground_golf.tscn"
const TICK := 1.0 / 60.0
const STUCK_LIMIT_S := 20.0
## Сценарные удары по лункам: [угол °, сила] подряд из старта (P1, P2 убран с поля); каждый — сразу, как кукла легла. Записаны пробой
## only=holes,record=1 (расчёт бота без разброса) — после правки поля лунки записать заново.
const SCRIPTED := {
	0: [[48.0, 0.991], [30.0, 0.099], [126.0, 0.225]],
	1: [[20.0, 0.661], [36.0, 0.371]],
	2: [[52.0, 0.93], [58.0, 0.169]],
}

## Счётчик SCRIPT ERROR за прогон (как squad_probe / bomb_probe) и ошибок движка.
class ScriptErrors extends Logger:
	var count := 0
	var first := ""
	var engine := 0
	var engine_first := ""
	var _mx := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		_mx.lock()
		if error_type == ERROR_TYPE_SCRIPT:
			count += 1
			if first == "":
				first = "%s %s (%s:%d %s)" % [code, rationale, file, line, function]
		elif error_type == ERROR_TYPE_ERROR:
			engine += 1
			if engine_first == "":
				var where := ""
				if not script_backtraces.is_empty() and script_backtraces[0].get_frame_count() > 0:
					where = " ← %s:%d" % [script_backtraces[0].get_frame_file(0), script_backtraces[0].get_frame_line(0)]
				engine_first = "%s (%s:%d)%s" % [code, file, line, where]
		_mx.unlock()


var ok := true
var checks: Array = []
var info := {}
var pg: GolfPlayground
var gm: GolfMatch
var over_results: Dictionary = {}
var errs := ScriptErrors.new()
var trace := false
var record := false


func _check(id: String, cond: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": cond, "detail": str(detail)})
	if not cond:
		ok = false
	print("  %-30s %s  %s" % [id, "ok  " if cond else "FAIL", str(detail)])


func _args() -> Dictionary:
	var out := {"only": "", "level": "2", "trace": "0", "out": "", "seeds": "11+22+33", "hole": "-1", "deg": "15+85+5", "pw": "0.4+1.0+0.1", "at": "", "record": "0", "joints": "0"}
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
	print("=== GOLF PROBE ===")
	var a := _args()
	trace = String(a["trace"]) == "1"
	record = String(a["record"]) == "1"
	JointBreak.set_on(false)
	if _want(a, "feel") and String(a["only"]) != "":
		await _feel()
	if _want(a, "search") and String(a["only"]) != "":
		var dg := String(a["deg"]).split("+")
		var pw := String(a["pw"]).split("+")
		var at := Vector2(-999.0, 0.0)
		if String(a["at"]) != "":
			var xy := String(a["at"]).split("+")
			at = Vector2(float(xy[0]), float(xy[1]))
		await _search(int(a["hole"]), [float(dg[0]), float(dg[1]), float(dg[2])], [float(pw[0]), float(pw[1]), float(pw[2])], at)
	if _want(a, "rules"):
		await _rules()
	if _want(a, "holes"):
		await _holes()
	if _want(a, "bots"):
		var seeds: Array = []
		for s in String(a["seeds"]).split("+"):
			seeds.append(int(s))
		await _bots(seeds, int(a["level"]), String(a["joints"]) == "1")
	await _unload()
	JointBreak.set_on(false)
	_check("errors_script", errs.count == 0, "ошибок скриптов %d; первая: %s" % [errs.count, errs.first])
	_check("errors_engine", errs.engine == 0, "ошибок движка %d; первая: %s" % [errs.engine, errs.engine_first])
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

## Площадка: оба бота; brains = false — мозги сняты (удары даёт проба). start — номер первой лунки, holes — сколько играть.
func _load(brains := false, start := 0, holes := 3, seed_ := 7, level := 2) -> void:
	await _unload()
	Engine.time_scale = 1.0
	pg = (load(SCENE) as PackedScene).instantiate() as GolfPlayground
	pg.p1_bot = true
	pg.p2_bot = true
	pg.bot_level = level
	gm = pg.get_node("Match") as GolfMatch
	gm.feel_enabled = false
	gm.countdown_s = 0.2
	gm.rng_seed = seed_
	gm.trace_shots = trace
	gm.start_hole = start
	gm.holes_n = holes
	over_results = {}
	gm.match_over.connect(func(_w: Doll, r: Dictionary) -> void: over_results = r)
	add_child(pg)
	await _until(func() -> bool: return gm.play_state == "play" and gm.dolls().size() == Tuning.GOLF_PLAYERS, 6.0)
	if not brains:
		for d in gm.dolls():
			var b := (d as Node).get_node_or_null(GolfMatch.BOT_NAME)
			if b != null:
				(d as Node).remove_child(b)
				b.queue_free()
	await _wait(0.6)


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
	for i in int(round(s / TICK)):
		await get_tree().physics_frame


func _doll(i: int) -> Doll:
	return gm.doll_of_index(i)


func _p(i: int) -> Dictionary:
	return gm.players[i]


func _com2(d: Doll) -> Vector2:
	var c := d.centre_of_mass()
	return Vector2(c.x, c.y)


## Убрать куклу с поля (в «лунку» без счёта): для проб, где мешает второй.
func _bench(i: int) -> void:
	var p := _p(i)
	p["state"] = GolfMatch.S.HOLED
	gm._park(_doll(i))


## Поставить куклу ЦМ в точку p (z = 0), скорости 0; состояние прицела, удар — отсюда.
func _place(d: Doll, p: Vector2) -> void:
	GolfShot.place(d, Vector3(p.x, p.y, 0.0))
	var pl := gm.player_of(d)
	pl["origin"] = d.centre_of_mass()
	gm._snap_prev(pl, d)


static func _dir(deg: float) -> Vector2:
	return Vector2.from_angle(deg_to_rad(deg))


## Наибольший разрыв сустава: расстояние между точкой сустава в детали A и в детали B (м).
func _joint_gap(d: Doll) -> float:
	var worst := 0.0
	for jn in d.joints:
		var j := d.joints[jn] as Generic6DOFJoint3D
		if j == null or not is_instance_valid(j):
			continue
		var a := j.get_node_or_null(j.node_a) as RigidBody3D
		var b := j.get_node_or_null(j.node_b) as RigidBody3D
		if a == null or b == null:
			continue
		var pa: Vector3 = a.global_transform * d._joint_xf_a[String(jn)].origin
		var pb: Vector3 = b.global_transform * d._joint_xf_b[String(jn)].origin
		worst = maxf(worst, pa.distance_to(pb))
	return worst


## Удар и ожидание его конца (AIM / HOLED). → {reason, t, end, strokes, max_gap}
func _shot(d: Doll, deg: float, power: float, max_s := 12.0) -> Dictionary:
	var pl := gm.player_of(d)
	var n0 := gm.shots.size()
	var fired := gm.shoot(d, _dir(deg), power)
	var t := 0.0
	var gap := 0.0
	while t < max_s:
		await get_tree().physics_frame
		t += TICK
		if is_instance_valid(d):
			gap = maxf(gap, _joint_gap(d))
		if int(pl["state"]) != GolfMatch.S.FLIGHT:
			break
	var last: Dictionary = gm.shots[n0] if gm.shots.size() > n0 else {}
	var res := {"fired": fired, "reason": String(last.get("reason", "")), "t": snappedf(t, 0.01), "strokes": int(pl["strokes"]),
		"state": GolfMatch.STATE_NAMES[int(pl["state"])], "max_gap": snappedf(gap, 0.001)}
	if is_instance_valid(d) and d.visible:
		var c := _com2(d)
		res["end"] = [snappedf(c.x, 0.01), snappedf(c.y, 0.01)]
	return res


# ------------------------------------------------------------------ feel (числа полёта, для подбора)

func _feel() -> void:
	print("--- feel")
	await _load(false, 0, 1)
	_bench(1)
	var d := _doll(0)
	for spec in [[45.0, 1.0], [45.0, 0.5], [30.0, 0.8], [70.0, 1.0]]:
		_place(d, Vector2(-12.0, 0.6))
		await _wait(0.5)
		var traj: Array = []
		var pl := _p(0)
		gm.shoot(d, _dir(float(spec[0])), float(spec[1]))
		var t := 0.0
		var apex := -INF
		var gap := 0.0
		while int(pl["state"]) == GolfMatch.S.FLIGHT and t < 12.0:
			await get_tree().physics_frame
			t += TICK
			var c := _com2(d)
			apex = maxf(apex, c.y)
			gap = maxf(gap, _joint_gap(d))
			if int(t / TICK) % 15 == 0:
				traj.append([snappedf(t, 0.01), snappedf(c.x, 0.1), snappedf(c.y, 0.1)])
		var c2 := _com2(d)
		var sp: Array = []
		for k in 24:
			await _wait(0.25)
			sp.append(snappedf(d.com_velocity().length(), 0.01))
		print("    скорость ЦМ после конца удара (каждые 0.25 с): ", sp, " макс. деталь ", snappedf(d.max_part_speed(), 0.01))
		print("  angle %.0f power %.2f → %.2f с, конец (%.1f, %.1f), верх %.1f, разрыв сустава %.3f м, %s" % [spec[0], spec[1], t, c2.x, c2.y, apex, gap,
			String(gm.shots[-1].get("reason", ""))])
		if trace:
			print("    ", traj)
		# вернуть в AIM, если засчиталось что-то
		pl["state"] = GolfMatch.S.AIM


# ------------------------------------------------------------------ search (подбор сценарных ударов)

func _search(hole: int, dg: Array, pw: Array, at: Vector2) -> void:
	print("--- search")
	for h in ([0, 1, 2] if hole < 0 else [hole]):
		var found: Array = []
		await _load(false, h, 1)
		_bench(1)
		var d := _doll(0)
		var start := _com2(d) if at.x < -900.0 else at
		var best := INF
		var degs: Array = []
		var x := float(dg[0])
		while x <= float(dg[1]) + 1e-3:
			degs.append(x)
			x += float(dg[2])
		var pws: Array = []
		x = float(pw[0])
		while x <= float(pw[1]) + 1e-3:
			pws.append(x)
			x += float(pw[2])
		for deg in degs:
			for pwv in pws:
				var pl := _p(0)
				if int(pl["state"]) == GolfMatch.S.HOLED or gm.play_state != "play":
					await _load(false, h, 1)
					_bench(1)
					d = _doll(0)
					pl = _p(0)
				pl["state"] = GolfMatch.S.AIM
				pl["strokes"] = 0
				_place(d, start)
				await _wait(0.3)
				var r := await _shot(d, float(deg), float(pwv))
				var end: Array = r.get("end", [0.0, 0.0])
				var cup := gm.course.cup.aim_point()
				var dist := Vector2(float(end[0]), float(end[1])).distance_to(cup)
				if dist < best:
					best = dist
				if dist < 4.0 or String(r["reason"]) == "holed":
					found.append([deg, snappedf(float(pwv), 0.01), snappedf(dist, 0.1), r["reason"], end])
				if trace:
					print("    %.1f° %.2f → %s %s" % [deg, float(pwv), r["reason"], str(end)])
		print("  лунка %d: близких ударов %d, лучший %.1f м: %s" % [h + 1, found.size(), best, str(found)])


# ------------------------------------------------------------------ правила

func _rules() -> void:
	print("--- rules")
	await _load(false, 0, 1)
	var d := _doll(0)
	var d2 := _doll(1)
	_check("two_players", gm.dolls().size() == Tuning.GOLF_PLAYERS and gm.play_state == "play", "кукол %d, %s" % [gm.dolls().size(), gm.play_state])
	_check("golf_doll", d.incoming_mult == 0.0 and not d.control_enabled and d.is_stunned() and is_equal_approx(d.torso().linear_damp, Tuning.GOLF_DAMP),
		"урон ×%.1f, управление %s, стан %s, дамп %.2f" % [d.incoming_mult, d.control_enabled, d.is_stunned(), d.torso().linear_damp])
	_place(d2, Vector2(-15.0, 0.6))   # второй (без мозга) лежит в углу — лунка не кончится, пока он не в чаше
	# --- запуск на полной силе не рвёт куклу
	_place(d, Vector2(-12.0, 0.6))
	await _wait(0.5)
	var parts0 := d.parts.size()
	var joints0 := d.joints.size()
	var pl := _p(0)
	gm.shoot(d, _dir(50.0), 1.0)
	await get_tree().physics_frame
	var v0 := d.com_velocity().length()
	var gap := 0.0
	var input_dx := 0.0
	var muscles_zero := true
	var ctrl_off := true
	d.input_vec = Vector2(1.0, 0.0)   # «держит вправо» — в полёте не должно действовать
	var x_prev := _com2(d).x
	var vx_prev := d.com_velocity().x
	var accel_x := 0.0
	for i in 40:
		await get_tree().physics_frame
		gap = maxf(gap, _joint_gap(d))
		muscles_zero = muscles_zero and d._muscle_mult == 0.0 and d.is_stunned()
		ctrl_off = ctrl_off and not d.control_enabled
		var vx := d.com_velocity().x
		accel_x = maxf(accel_x, (vx - vx_prev) / TICK)   # без ввода ускорение по x только от дампа (< 0)
		vx_prev = vx
	d.input_vec = Vector2.ZERO
	_check("launch_speed", absf(v0 - Tuning.GOLF_SPEED_MAX) < 0.8, "ЦМ после запуска %.2f м/с (сила 1 → %.1f)" % [v0, Tuning.GOLF_SPEED_MAX])
	_check("launch_no_tear", d.parts.size() == parts0 and d.joints.size() == joints0 and gap < 0.12,
		"деталей %d/%d, суставов %d/%d, наибольший разрыв %.3f м" % [d.parts.size(), parts0, d.joints.size(), joints0, gap])
	_check("limp_no_control", muscles_zero and ctrl_off and accel_x < 0.5,
		"мышцы 0 и стан: %s, управление выключено: %s, ускорение по x при вводе вправо ≤ %.2f м/с²" % [muscles_zero, ctrl_off, accel_x])
	# --- поправка: ровно одна
	var vb := d.com_velocity()
	var n1 := gm.nudge(d, Vector2.RIGHT)
	var va := d.com_velocity()
	var n2 := gm.nudge(d, Vector2.LEFT)
	_check("nudge_once", n1 and not n2 and absf((va - vb).x - Tuning.GOLF_NUDGE_DV) < 0.3,
		"первая %s (Δv %.2f м/с), вторая %s" % [n1, (va - vb).x, n2])
	var end_r := await _until(func() -> bool: return int(pl["state"]) != GolfMatch.S.FLIGHT, 12.0)
	var last: Dictionary = gm.shots[-1]
	_check("shot_end_rest", end_r and String(last.get("reason", "")) in ["rest", "holed"] and float(last.get("dur", 99.0)) < Tuning.GOLF_SHOT_MAX_S,
		"конец: %s через %.2f с, ЦМ %s" % [last.get("reason", "?"), float(last.get("dur", -1.0)), str(last.get("end", []))])
	var nudge_logged := last.has("nudge")
	# --- конец по таймеру: кукла всё время катится (проба толкает её)
	_place(d, Vector2(-8.0, 3.0))
	pl["state"] = GolfMatch.S.AIM
	await _wait(0.4)
	var strokes0 := int(pl["strokes"])
	gm.shoot(d, _dir(90.0), 0.0)
	var t := 0.0
	while int(pl["state"]) == GolfMatch.S.FLIGHT and t < 12.0:
		await get_tree().physics_frame
		t += TICK
		var c := _com2(d)
		if c.y < 3.0:   # держим в воздухе и в движении: подталкиваем вверх-вниз
			GolfShot.add_velocity(d, Vector3(0.0, 1.5, 0.0))
	last = gm.shots[-1]
	_check("shot_end_timer", String(last.get("reason", "")) == "time" and absf(float(last.get("dur", 0.0)) - Tuning.GOLF_SHOT_MAX_S) < 0.05,
		"конец: %s через %.2f с (лимит %.1f)" % [last.get("reason", "?"), float(last.get("dur", -1.0)), Tuning.GOLF_SHOT_MAX_S])
	_check("strokes_count", int(pl["strokes"]) == strokes0 + 1 and nudge_logged, "ударов %d → %d, поправка в журнале: %s" % [strokes0, int(pl["strokes"]), nudge_logged])
	# --- яма: +1 и назад
	var hz: Rect2 = (gm.course.data["hazards"] as Array)[0]
	var origin := Vector2(hz.position.x - 3.0, 0.6)
	_place(d, origin)
	pl["state"] = GolfMatch.S.AIM
	await _wait(0.5)
	var o3 := d.centre_of_mass()
	var s_before := int(pl["strokes"])
	var pens0 := gm.penalties.size()
	var r := await _shot(d, 25.0, 0.12)
	var back := _com2(d).distance_to(Vector2(o3.x, o3.y + 0.35))
	_check("hazard_penalty", r["reason"] == "hazard" and int(pl["strokes"]) == s_before + 2 and gm.penalties.size() == pens0 + 1 and back < 0.6
		and int(pl["state"]) == GolfMatch.S.AIM,
		"%s, ударов %d → %d (удар + штраф), возврат в %.2f м от места удара, состояние %s" % [r["reason"], s_before, int(pl["strokes"]), back, GolfMatch.STATE_NAMES[int(pl["state"])]])
	# --- лунка: выбили раньше — не засчитано; пролежал 1 с — засчитано
	var cup := gm.course.cup
	var cz := cup.zone()
	_place(d, Vector2(cz.get_center().x, cz.position.y + 0.5))
	pl["state"] = GolfMatch.S.AIM
	var held := 0.0
	while held < Tuning.GOLF_CUP_HOLD_S - 0.3:
		await get_tree().physics_frame
		held += TICK
	var not_yet := int(pl["state"]) != GolfMatch.S.HOLED
	_place(d, Vector2(cz.position.x - 3.0, 0.6))   # «выбили»
	await _wait(0.5)
	var reset_cup := float(pl["cup_t"]) == 0.0 and int(pl["state"]) != GolfMatch.S.HOLED
	_check("cup_knocked_out", not_yet and reset_cup, "в чаше %.2f с — не засчитано: %s; выбили — счёт чаши %.2f, не засчитано: %s" % [held, not_yet, float(pl["cup_t"]), reset_cup])
	# падение в чашу сверху на 6 м/с: «сетка» держит, засчитано
	var s_cup := int(pl["strokes"])
	_place(d, Vector2(cz.get_center().x, cz.position.y + 3.5))
	GolfShot.add_velocity(d, Vector3(0.0, -6.0, 0.0))
	var caught := await _until(func() -> bool: return int(pl["state"]) == GolfMatch.S.HOLED, 4.0)
	var card: Array = pl["card"]
	_check("cup_catches_drop", caught and card.size() == 1 and int(card[0]) == s_cup and not d.visible,
		"кукла с 6 м/с сверху осталась в чаше: %s, в карточке %s (ударов было %d), ушла с поля: %s" % [caught, str(card), s_cup, not d.visible])
	# ровно GOLF_CUP_HOLD_S: второй кладётся в чашу
	var p2 := _p(1)
	_place(d2, Vector2(cz.get_center().x, cz.position.y + 0.4))
	var t0 := gm.hole_time
	var holed_ok := await _until(func() -> bool: return int(p2["state"]) == GolfMatch.S.HOLED, 3.0)
	var t_in := gm.hole_time - t0
	_check("cup_counts", holed_ok and absf(t_in - Tuning.GOLF_CUP_HOLD_S) < 0.1, "засчитано через %.2f с (нужно %.1f)" % [t_in, Tuning.GOLF_CUP_HOLD_S])
	gm.hole_over.connect(func(_i: int) -> void: info["hole_over_seen"] = true, CONNECT_ONE_SHOT)
	await _wait(0.2)
	_check("hole_over_when_all_in", gm.play_state in ["hole_end", "over"], "состояние лунки %s" % gm.play_state)
	await _until(func() -> bool: return gm.play_state == "over", Tuning.GOLF_HOLE_PAUSE_S + 2.0)
	var tot: Dictionary = over_results.get("totals", {})
	_check("results", gm.play_state == "over" and not over_results.is_empty() and int(tot.get(0, -1)) == s_cup and over_results.get("card", {}).has(1),
		"итоги: всего %s, карточка %s, победитель %s" % [str(tot), str(over_results.get("card", {})), GolfHud.name_of(over_results.get("winner"))])
	# --- прочность суставов: потерял деталь за удар — +1
	await _load(false, 0, 1)
	_bench(1)
	d = _doll(0)
	pl = _p(0)
	JointBreak.set_on(true)
	_place(d, Vector2(-12.0, 0.6))
	await _wait(0.4)
	var sj := int(pl["strokes"])
	gm.shoot(d, _dir(45.0), 0.6)
	await _wait(0.3)
	d.detach_part("Hand_L")   # как оторвало ударом
	await _until(func() -> bool: return int(pl["state"]) != GolfMatch.S.FLIGHT, 12.0)
	var part_pen := 0
	for pe in gm.penalties:
		if String(pe["reason"]) == "part":
			part_pen += 1
	_check("lost_part_penalty", int(pl["strokes"]) == sj + 2 and part_pen == 1, "ударов %d → %d, штрафов за деталь %d" % [sj, int(pl["strokes"]), part_pen])
	# удар о стену на полной силе: износ от удара (без урона) — сколько деталей отлетит (печать, не проверка)
	_place(d, Vector2(-12.0, 0.6))
	pl["state"] = GolfMatch.S.AIM
	await _wait(0.4)
	var lost0 := d.lost_part_names().size()
	await _shot(d, 10.0, 1.0)
	info["joint_break_full_shot_lost"] = d.lost_part_names().size() - lost0
	info["joint_break_max_dv"] = snappedf(gm.max_impact_dv, 0.1)
	print("  (прочность суставов: удар на полной силе в стенку оторвал деталей: %d, наибольший Δv детали за тик %.1f м/с)" % [int(info["joint_break_full_shot_lost"]), gm.max_impact_dv])
	JointBreak.set_on(false)


# ------------------------------------------------------------------ лунки

func _holes() -> void:
	print("--- holes")
	var recorded := {}
	for h in 3:
		await _load(false, h, 1)
		_bench(1)
		var d := _doll(0)
		var pl := _p(0)
		var seq: Array = [] if record else (SCRIPTED[h] as Array).duplicate(true)
		var log: Array = []
		var brain := GolfBrain.new()   # запись (record=1): следующий удар — расчёт бота без разброса
		brain.level = 3
		var i := 0
		while int(pl["state"]) != GolfMatch.S.HOLED and i < 8:
			await _until(func() -> bool: return int(pl["state"]) != GolfMatch.S.FLIGHT, 2.0)
			if int(pl["state"]) == GolfMatch.S.HOLED:
				break
			if i >= seq.size():
				if not record:
					break
				var plan := brain.plan(gm.course, d)
				var dir: Vector2 = GolfShot.solve(_com2(d), plan["target"], gm.course.gravity_at(_com2(d)), Tuning.GOLF_DAMP, Tuning.GOLF_SPEED_MIN,
					Tuning.GOLF_SPEED_MAX, String(plan["arc"]), float(gm.course.bot_hint(_com2(d)).get("deg", -999.0)))["dir"]
				var hint := gm.course.bot_hint(_com2(d))
				var deg := rad_to_deg(dir.angle()) if not (hint.has("power") and hint.has("deg")) else float(hint["deg"])
				var pw := float(hint["power"]) if hint.has("power") else GolfShot.power_for(float(GolfShot.solve(_com2(d), plan["target"],
					gm.course.gravity_at(_com2(d)), Tuning.GOLF_DAMP, Tuning.GOLF_SPEED_MIN, Tuning.GOLF_SPEED_MAX, String(plan["arc"]),
					float(hint.get("deg", -999.0)))["speed"]))
				seq.append([snappedf(deg, 0.1), snappedf(pw, 0.001)])
			var s: Array = seq[i]
			var r := await _shot(d, float(s[0]), float(s[1]))
			log.append(r)
			i += 1
		var done := await _until(func() -> bool: return int(pl["state"]) == GolfMatch.S.HOLED, 3.0)
		recorded[h] = seq.slice(0, i)
		brain.free()
		_check("hole%d_scripted" % (h + 1), done and not bool(pl["picked"]) and (record or i == (SCRIPTED[h] as Array).size()),
			"%d ударов %s: %s" % [int(pl["strokes"]), str(seq.slice(0, i)), str(log)])
	if record:
		print("  SCRIPTED = ", recorded)
	# поле вбок гнёт полёт: тот же удар на лунке 3 с полем и без — как далеко вправо улетела кукла и где легла
	var far: Array = []
	var ends: Array = []
	for with_field in [true, false]:
		await _load(false, 2, 1)
		_bench(1)
		if not with_field:
			for z in gm.course.zones:
				(z as NullField).set_field(Tuning.GOLF_FIELD_G, Vector2(0.0, -1.0), 0.0)
			gm.course.data["zones"] = []
		var d := _doll(0)
		var pl := _p(0)
		gm.shoot(d, _dir(50.0), 1.0)
		var mx := -INF
		var t := 0.0
		while int(pl["state"]) == GolfMatch.S.FLIGHT and t < 10.0:
			await get_tree().physics_frame
			t += TICK
			mx = maxf(mx, _com2(d).x)
		far.append(mx)
		ends.append(_com2(d) if d.visible else gm.course.cup.aim_point())
	_check("side_field_bends", float(far[1]) - float(far[0]) > 2.0 and (ends[1] as Vector2).x - (ends[0] as Vector2).x > 2.0,
		"удар 50° × 1.0: дальше всего вправо — с полем %.1f м, без поля %.1f м; лёг — с полем x = %.1f, без поля x = %.1f" % [far[0], far[1],
		(ends[0] as Vector2).x, (ends[1] as Vector2).x])


# ------------------------------------------------------------------ боты

func _bots(seeds: Array, level: int, joints := false) -> void:
	print("--- bots%s" % (" (прочность суставов вкл)" if joints else ""))
	JointBreak.set_on(joints)
	var lost_total := 0
	var per_hole := {0: [], 1: [], 2: []}
	for s in seeds:
		await _load(true, 0, 3, int(s), level)
		var stuck := {0: 0.0, 1: 0.0}
		var last_pos := {0: Vector2.ZERO, 1: Vector2.ZERO}
		var worst_stuck := 0.0
		var t := 0.0
		var limit := 3.0 * (Tuning.GOLF_HOLE_MAX_S + Tuning.GOLF_HOLE_PAUSE_S + 4.0)
		while gm.play_state != "over" and t < limit:
			await get_tree().physics_frame
			t += TICK
			if gm.play_state != "play":
				continue
			for i in [0, 1]:
				var d := _doll(i)
				if d == null or int(_p(i)["state"]) == GolfMatch.S.HOLED:
					stuck[i] = 0.0
					continue
				var c := _com2(d)
				if c.distance_to(last_pos[i]) < 0.5:
					stuck[i] = float(stuck[i]) + TICK
				else:
					stuck[i] = 0.0
					last_pos[i] = c
				worst_stuck = maxf(worst_stuck, float(stuck[i]))
		var lines: Array = []
		var all_holed := true
		var all_in_par := true
		for e in gm.holes_log:
			var h := int(e["hole"])
			(per_hole[h] as Array).append(int(e["strokes"]))
			lines.append("Л%d P%d: %d%s" % [h + 1, int(e["pi"]) + 1, int(e["strokes"]), "" if bool(e["holed"]) else " (лимит)"])
			if not bool(e["holed"]):
				all_holed = false
			if int(e["strokes"]) > int(e["par"]) + 3:
				all_in_par = false
		var pens := {}
		lost_total += int(gm.penalties.filter(func(pe: Dictionary) -> bool: return String(pe["reason"]) == "part").size())
		if joints:
			print("    удары деталей по м/с за тик: ", gm.impact_hist)
		for pe in gm.penalties:
			pens[String(pe["reason"])] = int(pens.get(String(pe["reason"]), 0)) + 1
		_check("bots_seed%d%s" % [int(s), "_joints" if joints else ""], gm.play_state == "over" and gm.holes_log.size() == 6 and (all_holed and all_in_par or joints) and worst_stuck < STUCK_LIMIT_S,
			"%.0f с, %s; штрафы %s; дольше всего на месте %.1f с" % [t, ", ".join(lines), str(pens), worst_stuck])
		if trace:
			for sh in gm.shots:
				print("    ", sh)
	var avg := {}
	for h in per_hole:
		var arr: Array = per_hole[h]
		var sum := 0
		for v in arr:
			sum += int(v)
		avg[h + 1] = snappedf(float(sum) / maxf(arr.size(), 1), 0.01)
	info["bot_avg_strokes"] = avg
	if joints:
		info["bot_part_penalties"] = lost_total
		print("  прочность суставов: штрафов за деталь за %d матчей — %d" % [seeds.size(), lost_total])
	JointBreak.set_on(false)
	info["bot_strokes"] = per_hole
	print("  среднее ударов ботов по лункам: %s (пар %s)" % [str(avg), str(Tuning.GOLF_PARS)])
