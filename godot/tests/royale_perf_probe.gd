## Скорость «Королевской битвы» (docs/plan-demo/ROYALE.md; MODES_PACK.md §2: «8 кукол с оружием — оконная проба, порог ≥ 55 fps в 1080p»;
## нужно окно): бой ботов (P1 тоже бот, камера ведёт бойца, как игрока) seconds секунд; кончился бой — сразу заново (R), чтобы мерить
## и начало боя, когда живы все восемь. У каждого кадра — реальное время; в конце — средний fps, перцентили кадра, кадры дольше 33 / 50 /
## 100 мс, сколько в среднем было живых, и вердикт ok = fps_avg ≥ min_fps.
##   godot/tools/godot_nofocus.sh --path godot --resolution 1920x1080 res://tests/royale_perf_probe.tscn -- "seconds=60,min_fps=55,night=0,dolls=8"
##   (hud=0 — без HUD; auto=0 — без авто-масштаба 3D, только пресет графики; spike_ms — какие кадры разбирать по событиям)
## → JSON между === ROYALE PERF === и === OK / FAIL ===, exit 0 / 1; в отчёте — загрузка машины (load_avg): пробы других сессий на той же
## машине меняют fps в разы.
extends Node

const SCENE := "res://scenes/playground_royale.tscn"
const SCENE_NIGHT := "res://scenes/playground_royale_night.tscn"

var seconds := 60.0
var min_fps := 55.0
var night := false
var dolls_n: int = Tuning.ROYALE_FIGHTERS
var spike_ms := 40.0
var hud := true
var auto_scale := true
var _auto_before := true
var pg: RoyalePlayground
var rm: RoyaleMatch
var frames: Array = []
var events: Dictionary = {}   # индекс кадра → [строки]
var alive_sum := 0
var matches := 0
var _last_us := 0
var _running := false
var _added := 0
var _scale := -1.0


func _ev(what: String) -> void:
	var i := frames.size()
	if not events.has(i):
		events[i] = []
	(events[i] as Array).append(what)


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for part in String(arg).split(","):
			var kv := part.split("=")
			if kv.size() != 2:
				continue
			match kv[0]:
				"seconds": seconds = float(kv[1])
				"min_fps": min_fps = float(kv[1])
				"night": night = kv[1] == "1"
				"dolls": dolls_n = int(kv[1])
				"spike_ms": spike_ms = float(kv[1])
				"hud": hud = kv[1] != "0"
				"auto": auto_scale = kv[1] != "0"
	_run.call_deferred()


## Авто-масштаб 3D (Gfx + DynRes) на время пробы: auto=0 — масштаб только по пресету (без снижения под нагрузкой); в настройки игрока
## не пишется (set_auto_scale сохранил бы), в конце — как было.
func _set_auto(on: bool) -> void:
	var gfx := get_node_or_null("/root/Gfx")
	if gfx == null:
		return
	gfx.set("auto_scale", on)
	(gfx.get("dyn") as DynRes).reset()
	gfx.call("_refresh_scale")


func _run() -> void:
	var gfx := get_node_or_null("/root/Gfx")
	_auto_before = bool(gfx.get("auto_scale")) if gfx != null else true
	if not auto_scale:
		_set_auto(false)
	pg = (load(SCENE_NIGHT if night else SCENE) as PackedScene).instantiate() as RoyalePlayground
	pg.p1_bot = true
	pg.fighters = dolls_n
	rm = pg.get_node("Match") as RoyaleMatch
	rm.focus_index = 0
	rm.rng_seed = 22
	add_child(pg)
	if not hud:
		pg.get_node("HUD").visible = false
		pg.get_node("HUD").process_mode = Node.PROCESS_MODE_DISABLED
	rm.match_over.connect(func(_w: Doll, _r: Dictionary) -> void:
		_ev("match_over")
		matches += 1
		rm.restart.call_deferred())
	rm.eliminated.connect(func(v: Doll, _k: Doll, _p: int, _l: int, c: String) -> void: _ev("ko:%d:%s" % [v.player_index, c]))
	rm.weapon_taken.connect(func(_d: Doll, id: String, _f: String) -> void: _ev("weapon:%s" % id))
	rm.supply_taken.connect(func(_d: Doll, k: String) -> void: _ev("supply:%s" % k))
	rm.zone_stage.connect(func(st: int, sh: bool) -> void: _ev("zone:%d:%s" % [st, "shrink" if sh else "wait"]))
	rm.hit_fx.connect(func(ctx: Dictionary) -> void: _ev("hit_fx:%s" % String(ctx.get("tier", ""))))
	get_tree().node_added.connect(func(n: Node) -> void:
		if _running:
			_added += 1
			if n is RoyaleCrate:
				_ev("crate")
			elif n is ModularDoll:
				_ev("doll_built"))
	while rm.play_state != "play":
		await get_tree().process_frame
	_last_us = Time.get_ticks_usec()
	_running = true
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < seconds:
		await get_tree().process_frame
	_running = false
	_report()


func _process(_delta: float) -> void:
	if not _running:
		return
	if _added > 25:
		_ev("nodes+%d" % _added)
	_added = 0
	var sc := get_window().scaling_3d_scale
	if _scale >= 0.0 and not is_equal_approx(sc, _scale):
		_ev("render_scale:%.2f" % sc)
	_scale = sc
	if Engine.time_scale < 0.99:
		_ev("slow:%.2f" % Engine.time_scale)
	var now := Time.get_ticks_usec()
	frames.append(float(now - _last_us) / 1000.0)
	_last_us = now
	alive_sum += rm.alive_count()


## Загрузка машины (macOS: sysctl vm.loadavg) — замер fps без неё не сравнить: на общей машине параллельно идут чужие пробы.
func _load_avg() -> String:
	if OS.get_name() != "macOS":
		return ""
	var out: Array = []
	OS.execute("sysctl", ["-n", "vm.loadavg"], out)
	return String(out[0]).strip_edges() if not out.is_empty() else ""


func _report() -> void:
	var sorted := frames.duplicate()
	sorted.sort()
	var n := sorted.size()
	var pct := func(p: float) -> float: return float(sorted[clampi(int(p * float(n - 1)), 0, n - 1)]) if n > 0 else 0.0
	var counts := {"33": 0, "50": 0, "100": 0}
	for m in frames:
		if float(m) > 33.0:
			counts["33"] += 1
		if float(m) > 50.0:
			counts["50"] += 1
		if float(m) > 100.0:
			counts["100"] += 1
	var spikes: Array = []
	for i in range(frames.size()):
		if float(frames[i]) > spike_ms:
			var ev: Array = []
			for k in range(i - 3, i + 1):
				if events.has(k):
					ev.append_array(events[k])
			spikes.append({"frame": i, "ms": snappedf(float(frames[i]), 0.1), "events": ev})
	var ev_count := {}
	for k in events:
		for e in events[k]:
			var key := String(e).split(":")[0]
			ev_count[key] = int(ev_count.get(key, 0)) + 1
	var fps := float(n) / maxf(seconds, 0.1)
	var ok := fps >= min_fps
	var report := {"ok": ok, "night": night, "dolls": dolls_n, "resolution": str(get_window().size), "seconds": seconds, "frames": n,
		"fps_avg": snappedf(fps, 0.1), "min_fps": min_fps, "ms_p50": snappedf(pct.call(0.5), 0.1), "ms_p95": snappedf(pct.call(0.95), 0.1),
		"ms_p99": snappedf(pct.call(0.99), 0.1), "ms_max": snappedf(float(sorted[n - 1]) if n > 0 else 0.0, 0.1), "over_ms": counts,
		"alive_avg": snappedf(float(alive_sum) / maxf(float(n), 1.0), 0.1), "matches_finished": matches,
		"render_scale": snappedf(get_window().scaling_3d_scale, 0.01), "hud": hud, "events": ev_count, "spikes": spikes.slice(0, 30),
		"load_avg": _load_avg(), "auto_scale": auto_scale}
	if not auto_scale:
		_set_auto(_auto_before)
	print("=== ROYALE PERF ===")
	print(JSON.stringify(report, " "))
	print("=== OK ===" if ok else "=== FAIL ===")
	get_tree().quit(0 if ok else 1)
