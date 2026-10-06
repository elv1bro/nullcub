## Подвисания «Стычки 3 на 3» (нужно окно; автор 06.10: «иногда подвисает во время битвы»): бой ботов (P1 тоже бот, камера ведёт его как
## игрока) seconds секунд, у каждого кадра — реальное время, у каждого события — кадр, где оно было: нокаут, возврат на базу, ящик,
## новый уровень, эффект удара (hit_fx), стоп-кадр / замедление времени (Engine.time_scale < 1). В конце — перцентили кадра, число кадров
## дольше 33 / 50 / 100 мс и для каждого кадра дольше spike_ms — что случилось в нём и за кадр до него; и сколько реального времени игра
## провела в замедлении (для глаза это тоже «подвисание»).
##   godot/tools/godot_nofocus.sh --path godot --resolution 1600x900 res://tests/squad_perf_probe.tscn -- "seconds=60,spike_ms=40,night=0"
## → JSON между === SQUAD PERF === и === END ===, exit 0 (проба меряет, а не судит).
extends Node

const SCENE := "res://scenes/playground_squad.tscn"
const SCENE_NIGHT := "res://scenes/playground_squad_night.tscn"

var seconds := 60.0
var spike_ms := 40.0
var night := false
var pg: SquadPlayground
var sm: SquadMatch
var frames: Array = []        # [мс кадра, time_scale]
var events: Dictionary = {}   # индекс кадра → [строки]
var _last_us := 0
var _running := false
var _supplies := 0
var _slow_real := 0.0
var _added := 0
var _scale := -1.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for part in String(arg).split(","):
			var kv := part.split("=")
			if kv.size() != 2:
				continue
			match kv[0]:
				"seconds": seconds = float(kv[1])
				"spike_ms": spike_ms = float(kv[1])
				"night": night = kv[1] == "1"
	_run.call_deferred()


func _ev(what: String) -> void:
	var i := frames.size()
	if not events.has(i):
		events[i] = []
	(events[i] as Array).append(what)


func _run() -> void:
	pg = (load(SCENE_NIGHT if night else SCENE) as PackedScene).instantiate() as SquadPlayground
	pg.p1_bot = true
	pg.use_settings = false
	sm = pg.get_node("Match") as SquadMatch
	sm.focus_index = 0
	sm.score_to_win = 1000
	add_child(pg)
	sm.ko.connect(func(v: Doll, _a: Node, _r: Dictionary) -> void: _ev("ko:%d" % v.player_index))
	sm.doll_respawned.connect(func(d: Doll) -> void: _ev("respawn:%d" % d.player_index))
	sm.leveled.connect(func(pi: int, lv: int, _u: Dictionary) -> void: _ev("level:%d:%d" % [pi, lv]))
	sm.hit_fx.connect(func(ctx: Dictionary) -> void: _ev("hit_fx:%s:%.0f" % [String(ctx.get("tier", "")), float(ctx.get("damage", 0.0))]))
	sm.supply_taken.connect(func(d: Doll, k: String) -> void: _ev("supply_taken:%s" % k))
	get_tree().node_added.connect(_on_added)
	while sm.play_state != "play":
		await get_tree().process_frame
	_last_us = Time.get_ticks_usec()
	_running = true
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < seconds:
		await get_tree().process_frame
	_running = false
	_report()
	get_tree().quit(0)


## Новые узлы: заметные типы — событием, остальные — счётом за кадр (большая пачка = сборка куклы, обломки, частицы).
func _on_added(n: Node) -> void:
	if not _running:
		return
	_added += 1
	if n is Explosion:
		_ev("explosion")
	elif n is ModularDoll:
		_ev("doll_built")
	elif n.get_script() != null and String(n.name).begins_with("ImpactFx"):
		pass
	elif n is RigidBody3D and n.is_in_group("debris"):
		_ev("debris")


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
	var now := Time.get_ticks_usec()
	var ms := float(now - _last_us) / 1000.0
	_last_us = now
	var n := get_tree().get_nodes_in_group(SquadMatch.SUPPLY_GROUP).size()
	if n > _supplies:
		_ev("supply_spawn")
	_supplies = n
	if Engine.time_scale < 0.99:
		_slow_real += ms / 1000.0
	frames.append([ms, Engine.time_scale])


func _report() -> void:
	var ms: Array = frames.map(func(f: Array) -> float: return float(f[0]))
	var sorted := ms.duplicate()
	sorted.sort()
	var n := sorted.size()
	var pct := func(p: float) -> float: return float(sorted[clampi(int(p * float(n - 1)), 0, n - 1)]) if n > 0 else 0.0
	var spikes: Array = []
	var counts := {"33": 0, "50": 0, "100": 0}
	for i in range(n):
		var m := float(ms[i])
		if m > 33.0:
			counts["33"] += 1
		if m > 50.0:
			counts["50"] += 1
		if m > 100.0:
			counts["100"] += 1
		if m > spike_ms:
			var ev: Array = []
			for k in range(i - 5, i + 1):
				if events.has(k):
					ev.append_array(events[k])
			spikes.append({"frame": i, "ms": snappedf(m, 0.1), "time_scale": snappedf(float(frames[i][1]), 0.01), "events": ev})
	var ev_count := {}
	for k in events:
		for e in events[k]:
			var key := String(e).split(":")[0]
			ev_count[key] = int(ev_count.get(key, 0)) + 1
	var report := {"night": night, "seconds": seconds, "frames": n, "fps_avg": snappedf(float(n) / maxf(seconds, 0.1), 0.1),
		"ms_p50": snappedf(pct.call(0.5), 0.1), "ms_p95": snappedf(pct.call(0.95), 0.1), "ms_p99": snappedf(pct.call(0.99), 0.1),
		"ms_max": snappedf(float(sorted[n - 1]) if n > 0 else 0.0, 0.1), "over_ms": counts, "slow_time_real_s": snappedf(_slow_real, 0.01),
		"events": ev_count, "spikes": spikes.slice(0, 40), "score": sm.score.duplicate()}
	print("=== SQUAD PERF ===")
	print(JSON.stringify(report, " "))
	print("=== END ===")
