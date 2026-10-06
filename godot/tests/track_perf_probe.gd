## Скорость «Гонки: трасса» (docs/plan-demo/RACE_TRACK.md; длинная карта 420 м: прессы, магниты, мембраны, поля, семь мостов на цепях,
## бочки; нужно окно): гонка ботов (P1 тоже бот, камера ведёт его, как игрока), seconds секунд; кончилась — сразу заново (R). Камера
## проходит все участки. У каждого кадра — реальное время; в конце — средний fps, перцентили кадра, кадры дольше 33 / 50 / 100 мс, средняя
## физика и процесс (мс), fps по участкам (где был P1), загрузка машины и вердикт ok = fps_avg ≥ min_fps.
##   godot/tools/godot_nofocus.sh --path godot --resolution 1920x1080 res://tests/track_perf_probe.tscn -- "seconds=90,min_fps=55,level=2"
##   (auto=0 — без авто-масштаба 3D; hud=0 — без HUD)
## → JSON между === TRACK PERF === и === OK / FAIL ===, exit 0 / 1. Настройки управления автора (user://control_feel.cfg) не читаются.
extends Node

const SCENE := "res://scenes/playground_race_track.tscn"

var seconds := 90.0
var min_fps := 55.0
var level := 2
var hud := true
var auto_scale := true
var _auto_before := true
var pg: TrackPlayground
var tm: TrackMatch
var frames: Array = []
var by_section: Dictionary = {}   # участок → [кадров, сумма мс]
var phys_ms := 0.0
var proc_ms := 0.0
var races := 0
var _last_us := 0
var _running := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for part in String(arg).split(","):
			var kv := part.split("=")
			if kv.size() != 2:
				continue
			match kv[0]:
				"seconds": seconds = float(kv[1])
				"min_fps": min_fps = float(kv[1])
				"level": level = int(kv[1])
				"hud": hud = kv[1] != "0"
				"auto": auto_scale = kv[1] != "0"
	ControlFeel.no_disk = true
	TrackPlayground.best_path = "user://_perf_track_best.cfg"
	_run.call_deferred()


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
	TrackBrain.seed_salt = 5
	pg = (load(SCENE) as PackedScene).instantiate() as TrackPlayground
	pg.p1_bot = true
	pg.bot_level = level
	tm = pg.get_node("Match") as TrackMatch
	tm.focus_index = 0
	tm.countdown_s = 1.0
	add_child(pg)
	if not hud:
		pg.get_node("HUD").visible = false
		pg.get_node("HUD").process_mode = Node.PROCESS_MODE_DISABLED
	tm.match_over.connect(func(_w: Doll, _r: Dictionary) -> void:
		races += 1
		tm.restart.call_deferred())
	while tm.play_state != "play":
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
	var now := Time.get_ticks_usec()
	var ms := float(now - _last_us) / 1000.0
	frames.append(ms)
	_last_us = now
	phys_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	proc_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var me := tm.me()
	var sec := tm.section_of(me) if me != null else 0
	var e: Array = by_section.get(sec, [0, 0.0])
	e[0] = int(e[0]) + 1
	e[1] = float(e[1]) + ms
	by_section[sec] = e


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
	var secs := {}
	for k in by_section.keys():
		var e: Array = by_section[k]
		secs["S%d" % int(k)] = snappedf(1000.0 * float(e[0]) / maxf(float(e[1]), 1.0), 0.1)
	var fps := float(n) / maxf(seconds, 0.1)
	var ok := fps >= min_fps
	var report := {"ok": ok, "resolution": str(get_window().size), "seconds": seconds, "frames": n, "fps_avg": snappedf(fps, 0.1),
		"min_fps": min_fps, "ms_p50": snappedf(pct.call(0.5), 0.1), "ms_p95": snappedf(pct.call(0.95), 0.1), "ms_p99": snappedf(pct.call(0.99), 0.1),
		"ms_max": snappedf(float(sorted[n - 1]) if n > 0 else 0.0, 0.1), "over_ms": counts, "fps_by_section": secs,
		"physics_ms_avg": snappedf(phys_ms / maxf(float(n), 1.0), 0.01), "process_ms_avg": snappedf(proc_ms / maxf(float(n), 1.0), 0.01),
		"races_finished": races, "render_scale": snappedf(get_window().scaling_3d_scale, 0.01), "hud": hud, "auto_scale": auto_scale,
		"load_avg": _load_avg()}
	if not auto_scale:
		_set_auto(_auto_before)
	TrackBrain.seed_salt = 0
	var g := ProjectSettings.globalize_path(TrackPlayground.best_path)
	if FileAccess.file_exists(g):
		DirAccess.remove_absolute(g)
	print("=== TRACK PERF ===")
	print(JSON.stringify(report, " "))
	print("=== OK ===" if ok else "=== FAIL ===")
	get_tree().quit(0 if ok else 1)
