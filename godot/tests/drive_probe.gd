## Проба ДРАЙВА (docs/plan-demo/DRIVE.md): «сухой» бой против «драйва» в числах. Купол Быстрого боя (playground_null_hall.tscn):
## P1 — «человек» (проба жмёт действия p1_* с силой, как клавиатура: камера считает его человеком, follow_mode "humans"), давит
## соперника с упреждением, зигзагом и ускорением издалека; P2 — настоящий бот кампании RivalBrain (уровень level). Тот же сценарий
## с ДРАЙВОМ выкл и вкл (Drive.set_on — как клавиша J), по сиду на матч; бой до KO или max_s секунд.
## Метрики (info.modes.<off|on>, медианы и доли по всем сидам):
##   air_share — доля времени боя, когда кукла не касается пола/статики (DollCombat._grounded), среднее по двум;
##   mutual_share — доля стычек (удары в окне 0.15 с), где досталось обоим; even_share — из них почти поровну (меньший ≥ ½ большего);
##   respond_share — доля ударов, на которых идёт замедление/стоп-кадр (Engine.time_scale < 1 в момент hit_fx);
##   gap_med_s — медиана паузы между стычками; exchanges_per_min; dmg_med, dmg5_share (доля ударов ≥ 5 HP);
##   fly_v_<полоса> — скорость ЦМ жертвы через 0.1 с после удара: light < 5 HP, mid 5–12, big ≥ 12 (м/с);
##   dist_med_m, close_share (< 3 м), far_share (> 7 м); both_in_frame — доля кадров, где ЦМ соперника в кадре камеры;
##   doll_frac_med — рост куклы (1.8 м) / высота кадра; fight_s, ko / draw / timeout, tiers, crits; Drive.stats (размены).
## Проверки: matches — все матчи дошли до боя; hits — в каждом режиме есть удары; finite — нет NaN в позициях.
## strict=1 — ещё цели ДРАЙВА (DRIVE.md §4): air ≥ 0.5, mutual ≤ 0.3, respond ≥ 0.5, gap_med ≤ 1.5 с, both_in_frame ≥ 0.6.
## Запуск: godot --headless --path godot --fixed-fps 60 res://tests/drive_probe.tscn -- "modes=off,on,seeds=29,7,13,max_s=75,level=3,out=<json>"
extends Node

const SCENE := "res://scenes/playground_null_hall.tscn"
const EXCHANGE_GAP_S := 0.15
const FLY_DELAY_S := 0.1
const CLOSE_M := 3.0
const FAR_M := 7.0
const DOLL_H := 1.8
const SIM_REACT_S := Vector2(0.12, 0.2)
const SIM_ZIG_S := Vector2(0.5, 0.8)
const SIM_ZIG := 0.3
const SIM_DASH_FROM_M := 3.0
const SIM_DASH_STOP_M := 1.6

var modes: Array = ["off", "on"]
var seeds: Array = [29, 7, 13]
var max_s := 75.0
var level := 3
var strict := false
var out_path := "res://tests/drive_probe_report.json"

var checks: Array = []
var ok := true

# состояние текущего матча
var pg: Node = null
var m: Match = null
var p1: Doll = null
var p2: Doll = null
var cam: DynamicCamera = null
var rng := RandomNumberGenerator.new()
var hits: Array = []          # {t, attacker, victim, dmg, tier, responded}
var fly_pending: Array = []   # {due, victim, band}
var fly: Dictionary = {}      # band -> Array[float]
var samples := {"frames": 0, "air": 0, "dist": [], "close": 0, "far": 0, "in_frame": 0, "frame_h": []}
var finite := true
var over := false
var over_info: Dictionary = {}
var sim := {"aim": Vector2.ZERO, "react_t": 0.0, "zig": 1.0, "zig_t": 0.0, "dash": false}


func _ready() -> void:
	ControlFeel.no_disk = true   # в окне панель Tab не читает и не пишет user://control_feel.cfg автора
	_parse_args()
	_run_all.call_deferred()


func _parse_args() -> void:
	var raw := " ".join(OS.get_cmdline_user_args())
	# «seeds=29,7,13» содержит запятые — разбираем по известным ключам
	var keys := ["modes", "seeds", "max_s", "level", "strict", "out"]
	var parts := raw.split(",")
	var cur := ""
	var vals: Dictionary = {}
	for p in parts:
		var s := String(p).strip_edges()
		var eq := s.find("=")
		if eq > 0 and keys.has(s.substr(0, eq)):
			cur = s.substr(0, eq)
			vals[cur] = [s.substr(eq + 1)]
		elif cur != "":
			(vals[cur] as Array).append(s)
	if vals.has("modes"):
		modes = vals["modes"]
	if vals.has("seeds"):
		seeds = []
		for v in vals["seeds"]:
			seeds.append(int(v))
	if vals.has("max_s"):
		max_s = float(vals["max_s"][0])
	if vals.has("level"):
		level = int(vals["level"][0])
	if vals.has("strict"):
		strict = String(vals["strict"][0]) != "0"
	if vals.has("out"):
		out_path = String(vals["out"][0])


func _run_all() -> void:
	var report := {"info": {"scene": SCENE, "seeds": seeds, "max_s": max_s, "level": level, "modes": {}}}
	for mode in modes:
		var runs: Array = []
		for sd in seeds:
			runs.append(await _run_match(String(mode), int(sd)))
		report["info"]["modes"][mode] = _aggregate(runs)
		report["info"]["modes"][mode]["runs"] = runs
	Drive.set_on(false)
	ControlFeel.reset()
	for mode in modes:
		var agg: Dictionary = report["info"]["modes"][mode]
		_check("matches_" + mode, float(agg["matches"]), float(seeds.size()), "eq", "матчи дошли до боя")
		_check("hits_" + mode, float(agg["hits"]), 1.0, "gte", "удары есть")
	_check("finite", 1.0 if finite else 0.0, 1.0, "eq", "позиции без NaN")
	if strict and report["info"]["modes"].has("on"):
		var on: Dictionary = report["info"]["modes"]["on"]
		_check("drive_air", float(on["air_share"]), 0.5, "gte", "ДРАЙВ: доля времени в воздухе")
		_check("drive_mutual", float(on["mutual_share"]), 0.3, "lte", "ДРАЙВ: доля разменов")
		_check("drive_respond", float(on["respond_share"]), 0.5, "gte", "ДРАЙВ: доля ударов с откликом времени")
		_check("drive_gap", float(on["gap_med_s"]), 1.5, "lte", "ДРАЙВ: медиана паузы между стычками, с")
		_check("drive_frame", float(on["both_in_frame"]), 0.6, "gte", "ДРАЙВ: соперник в кадре")
	report["checks"] = checks
	report["ok"] = ok
	var txt := JSON.stringify(report, "  ", false)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(txt)
		f.close()
	print("=== DRIVE PROBE ===")
	for mode in modes:
		var agg: Dictionary = (report["info"]["modes"][mode] as Dictionary).duplicate()
		agg.erase("runs")
		print(mode, " ", JSON.stringify(agg))
	for c in checks:
		print(("OK   " if c["ok"] else "FAIL ") + String(c["id"]) + " = " + str(c["value"]) + " (" + String(c["cmp"]) + " " + str(c["limit"]) + ")")
	print("=== OK ===" if ok else "=== FAIL ===")
	get_tree().quit(0 if ok else 1)


func _check(id: String, value: float, limit: float, cmp: String, detail: String) -> void:
	var good := value >= limit if cmp == "gte" else (value <= limit if cmp == "lte" else is_equal_approx(value, limit))
	checks.append({"id": id, "value": snappedf(value, 0.001), "limit": limit, "cmp": cmp, "ok": good, "detail": detail})
	if not good:
		ok = false


# --- один матч ---

func _run_match(mode: String, sd: int) -> Dictionary:
	Engine.time_scale = 1.0
	ControlFeel.reset()
	Drive.set_on(mode == "on")
	Drive.reset_stats()
	rng.seed = sd
	hits = []
	fly_pending = []
	fly = {"light": [], "mid": [], "big": []}
	samples = {"frames": 0, "air": 0, "dist": [], "close": 0, "far": 0, "in_frame": 0, "frame_h": []}
	over = false
	over_info = {}
	sim = {"aim": Vector2.ZERO, "react_t": 0.0, "zig": 1.0, "zig_t": rng.randf_range(SIM_ZIG_S.x, SIM_ZIG_S.y), "dash": false}
	pg = (load(SCENE) as PackedScene).instantiate()
	p1 = pg.get_node("P1") as Doll
	p2 = pg.get_node("P2") as Doll
	p1.add_to_group("players")
	p2.add_to_group("rivals")
	var brain := RivalBrain.new()
	brain.name = "Brain"
	brain.level = level
	p2.add_child(brain)
	add_child(pg)
	m = pg.get_node("Match") as Match
	cam = pg.get_node("Camera") as DynamicCamera
	m.hit_fx.connect(_on_hit_fx)
	m.match_over.connect(func(winner: Doll, results: Dictionary) -> void:
		over = true
		over_info = {"winner": String(winner.name) if winner != null and is_instance_valid(winner) else "", "reason": String(results.get("reason", "")),
			"draw": winner == null})
	var fought := false
	var guard := 0
	while guard < 60 * 400:
		guard += 1
		await get_tree().physics_frame
		if m.phase == Match.Phase.FIGHT:
			fought = true
			_sim_p1()
			_sample()
		_tick_fly()
		if over or (fought and m.fight_time >= max_s):
			break
	_release_keys()
	var res := _match_result(mode, sd, fought)
	pg.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	pg = null
	Engine.time_scale = 1.0
	return res


func _com(d: Doll) -> Vector3:
	return d.centre_of_mass() if is_instance_valid(d) and not d.parts.is_empty() else Vector3.ZERO


## «Человек»: давит соперника — цель с упреждением (обновляется раз в 0.12–0.2 с, как реакция), зигзаг поперёк хода, ускорение
## издалека, не отступает. Жмёт p1_* с силой (Input.action_press), как клавиатура/стик.
func _sim_p1() -> void:
	if not is_instance_valid(p1) or not p1.alive or not is_instance_valid(p2) or not p2.alive:
		_release_keys()
		return
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var a := _com(p1)
	var b := _com(p2)
	sim["react_t"] = float(sim["react_t"]) - dt
	if float(sim["react_t"]) <= 0.0:
		sim["react_t"] = rng.randf_range(SIM_REACT_S.x, SIM_REACT_S.y)
		var v2 := p2.torso().linear_velocity
		sim["aim"] = Vector2(b.x + v2.x * 0.2 - a.x, b.y + v2.y * 0.2 + 0.2 - a.y)
	sim["zig_t"] = float(sim["zig_t"]) - dt
	if float(sim["zig_t"]) <= 0.0:
		sim["zig_t"] = rng.randf_range(SIM_ZIG_S.x, SIM_ZIG_S.y)
		sim["zig"] = -float(sim["zig"])
	var to: Vector2 = sim["aim"]
	var dist := to.length()
	var dir := to.normalized() if dist > 0.01 else Vector2.RIGHT
	var perp := Vector2(-dir.y, dir.x)
	var w := (dir + perp * SIM_ZIG * float(sim["zig"])).normalized()
	_press("p1_right", maxf(w.x, 0.0))
	_press("p1_left", maxf(-w.x, 0.0))
	_press("p1_up", maxf(w.y, 0.0))
	_press("p1_down", maxf(-w.y, 0.0))
	if bool(sim["dash"]):
		if dist < SIM_DASH_STOP_M or p1.charge < 5.0:
			sim["dash"] = false
	elif dist > SIM_DASH_FROM_M and p1.charge > 40.0 and not p1.charge_locked:
		sim["dash"] = true
	_press("p1_dash", 1.0 if bool(sim["dash"]) else 0.0)


func _press(action: String, strength: float) -> void:
	if strength > 0.02:
		Input.action_press(action, clampf(strength, 0.0, 1.0))
	else:
		Input.action_release(action)


func _release_keys() -> void:
	for s in ["_left", "_right", "_up", "_down", "_dash", "_flip"]:
		Input.action_release("p1" + s)


func _sample() -> void:
	if not is_instance_valid(p1) or not is_instance_valid(p2):
		return
	var a := _com(p1)
	var b := _com(p2)
	if not (is_finite(a.x) and is_finite(a.y) and is_finite(b.x) and is_finite(b.y)):
		finite = false
		return
	samples["frames"] = int(samples["frames"]) + 1
	for d in [p1, p2]:
		var c := DollCombat.combat_of(d)
		if c != null and d.alive and not c._grounded:
			samples["air"] = int(samples["air"]) + 1
	var dist := Vector2(a.x - b.x, a.y - b.y).length()
	(samples["dist"] as Array).append(dist)
	if dist < CLOSE_M:
		samples["close"] = int(samples["close"]) + 1
	if dist > FAR_M:
		samples["far"] = int(samples["far"]) + 1
	if cam != null:
		var r := cam.frame_rect()
		if r.size.y > 0.01:
			(samples["frame_h"] as Array).append(r.size.y)
			if r.grow(-0.2).has_point(Vector2(b.x, b.y)):
				samples["in_frame"] = int(samples["in_frame"]) + 1


func _on_hit_fx(ctx: Dictionary) -> void:
	var v := ctx.get("victim") as Doll
	var at := ctx.get("attacker") as Doll
	var dmg := float(ctx.get("damage", 0.0))
	hits.append({"t": m.fight_time, "attacker": String(at.name) if at != null else "", "victim": String(v.name) if v != null else "",
		"dmg": dmg, "tier": String(ctx.get("tier", "")), "responded": Engine.time_scale < 0.999})
	if v != null and is_instance_valid(v):
		var band := "light" if dmg < 5.0 else ("mid" if dmg < 12.0 else "big")
		fly_pending.append({"due": m.fight_time + FLY_DELAY_S, "victim": v, "band": band})


func _tick_fly() -> void:
	if m == null:
		return
	var keep: Array = []
	for e in fly_pending:
		var v: Doll = e["victim"]
		if not is_instance_valid(v) or v.parts.is_empty():
			continue
		if m.fight_time >= float(e["due"]):
			var p := Vector3.ZERO
			for bb in v.parts.values():
				p += (bb as RigidBody3D).linear_velocity * (bb as RigidBody3D).mass
			(fly[e["band"]] as Array).append((p / maxf(v.total_mass, 0.001)).length())
		else:
			keep.append(e)
	fly_pending = keep


func _match_result(mode: String, sd: int, fought: bool) -> Dictionary:
	var exch: Array = []   # [{t0, dmg: {name: sum}}]
	for h in hits:
		if exch.is_empty() or float(h["t"]) - float(exch[-1]["t1"]) > EXCHANGE_GAP_S:
			exch.append({"t0": h["t"], "t1": h["t"], "dmg": {}})
		var e: Dictionary = exch[-1]
		e["t1"] = h["t"]
		var vn := String(h["victim"])
		e["dmg"][vn] = float(e["dmg"].get(vn, 0.0)) + float(h["dmg"])
	var mutual := 0
	var even := 0
	for e in exch:
		var d: Dictionary = e["dmg"]
		if d.size() >= 2:
			var vs := d.values()
			var lo := minf(float(vs[0]), float(vs[1]))
			var hi := maxf(float(vs[0]), float(vs[1]))
			if lo >= 1.0:
				mutual += 1
				if lo >= 0.5 * hi:
					even += 1
	var gaps: Array = []
	for i in range(1, exch.size()):
		gaps.append(float(exch[i]["t0"]) - float(exch[i - 1]["t1"]))
	var dmgs: Array = []
	var responded := 0
	var tiers := {}
	for h in hits:
		dmgs.append(float(h["dmg"]))
		if bool(h["responded"]):
			responded += 1
		tiers[h["tier"]] = int(tiers.get(h["tier"], 0)) + 1
	var fr := maxi(int(samples["frames"]), 1)
	var fight_s := m.fight_time if m != null else 0.0
	return {
		"mode": mode, "seed": sd, "fought": fought, "fight_s": snappedf(fight_s, 0.01),
		"winner": over_info.get("winner", ""), "reason": over_info.get("reason", "timeout" if not over else ""), "draw": bool(over_info.get("draw", false)),
		"hits": hits.size(), "exchanges": exch.size(), "mutual": mutual, "even": even,
		"mutual_share": snappedf(float(mutual) / maxf(exch.size(), 1), 0.001), "even_share": snappedf(float(even) / maxf(exch.size(), 1), 0.001),
		"respond_share": snappedf(float(responded) / maxf(hits.size(), 1), 0.001),
		"gap_med_s": snappedf(_median(gaps), 0.01), "exchanges_per_min": snappedf(exch.size() / maxf(fight_s, 0.001) * 60.0, 0.1),
		"dmg_med": snappedf(_median(dmgs), 0.01), "dmg5_share": snappedf(_share(dmgs, 5.0), 0.001),
		"fly_v_light": snappedf(_median(fly["light"]), 0.01), "fly_v_mid": snappedf(_median(fly["mid"]), 0.01), "fly_v_big": snappedf(_median(fly["big"]), 0.01),
		"air_share": snappedf(float(samples["air"]) / (2.0 * fr), 0.001),
		"dist_med_m": snappedf(_median(samples["dist"]), 0.01), "close_share": snappedf(float(samples["close"]) / fr, 0.001),
		"far_share": snappedf(float(samples["far"]) / fr, 0.001), "both_in_frame": snappedf(float(samples["in_frame"]) / fr, 0.001),
		"doll_frac_med": snappedf(DOLL_H / maxf(_median(samples["frame_h"]), 0.01), 0.001),
		"tiers": tiers, "crits": int(tiers.get("crit", 0)) + int(tiers.get("ko_crit", 0)), "drive_stats": Drive.stats.duplicate(),
	}


func _aggregate(runs: Array) -> Dictionary:
	var out := {"matches": 0, "hits": 0, "ko": 0, "draw": 0, "timeout": 0}
	var keys := ["fight_s", "mutual_share", "even_share", "respond_share", "gap_med_s", "exchanges_per_min", "dmg_med", "dmg5_share",
		"fly_v_light", "fly_v_mid", "fly_v_big", "air_share", "dist_med_m", "close_share", "far_share", "both_in_frame", "doll_frac_med", "crits"]
	var acc := {}
	for k in keys:
		acc[k] = []
	for r in runs:
		if bool(r["fought"]):
			out["matches"] = int(out["matches"]) + 1
		out["hits"] = int(out["hits"]) + int(r["hits"])
		if bool(r["draw"]):
			out["draw"] = int(out["draw"]) + 1
		elif String(r["reason"]) == "ko":
			out["ko"] = int(out["ko"]) + 1
		else:
			out["timeout"] = int(out["timeout"]) + 1
		for k in keys:
			(acc[k] as Array).append(float(r[k]))
	for k in keys:
		out[k] = snappedf(_median(acc[k]), 0.001)
	return out


static func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	var n := b.size()
	return float(b[n / 2]) if n % 2 == 1 else 0.5 * (float(b[n / 2 - 1]) + float(b[n / 2]))


static func _share(a: Array, lim: float) -> float:
	if a.is_empty():
		return 0.0
	var n := 0
	for x in a:
		if float(x) >= lim:
			n += 1
	return float(n) / a.size()
