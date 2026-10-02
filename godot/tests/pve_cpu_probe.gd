## Профайлер скриптов PvE: сколько мкс за физический тик уходит на скрипты узлов playground_pve.tscn, когда дерутся 5 врагов и P1-бот.
## Скрипты не меряются из движка, поэтому проба забирает у каждого скриптового узла авто-вызов _physics_process / _process
## (set_physics_process(false)) и вызывает их сама в своём тике, обернув в Time.get_ticks_usec(): динамика та же (порядок вызовов чуть иной),
## а время разложено по файлам скриптов. Печатает таблицу «скрипт: вызовов, мкс/тик (сумма по узлам), макс мкс», сумму и долю бюджета 16.7 мс.
## Запуск: godot --headless --path . --fixed-fps 60 res://tests/pve_cpu_probe.tscn -- "secs=12,warm=2"
## Отчёт — stdout + tests/pve_cpu_probe_report.json; exit 0 — это замер, не гейт.
## Параметр budget_us=N — если задан, суммарный скриптовый мкс/тик > N → exit 1 (страж от возврата тяжёлого кода).
extends Node3D

const PG_SCENE := "res://scenes/playground_pve.tscn"

var secs := 12.0
var warm := 2.0
var budget_us := 0.0
var pg: Node
var director: Node
var p1: Doll
var _bot: Dictionary = {}
var _t := 0.0
var _taken: Array = []      # [{node, path, kind}]
var _acc_us: Dictionary = {}   # "path|kind" -> суммарные мкс за окно замера
var _max_us: Dictionary = {}
var _calls: Dictionary = {}
var _ticks := 0
var _exit_code := 0
var _spawned := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		for kv in String(a).split(","):
			var p := kv.split("=")
			if p.size() == 2:
				match p[0]:
					"secs": secs = float(p[1])
					"warm": warm = float(p[1])
					"budget_us": budget_us = float(p[1])
	await _run()


func _run() -> void:
	seed(20260929)
	pg = (load(PG_SCENE) as PackedScene).instantiate()
	director = pg.get_node("WaveDirector")
	director.auto_waves = false
	director.feel_enabled = false
	add_child(pg)
	p1 = pg.get_node("P1") as Doll
	p1.external_input = true
	await get_tree().process_frame
	await get_tree().physics_frame
	director.begin_manual()
	_give_hammer()
	var x := p1.centre_of_mass().x
	for i in range(5):
		var kind := "sweeper" if i % 2 == 0 and i < 4 else "scrapling"
		director.spawn_enemy(kind, Vector3(x - 6.0 + i * 3.0, 3.0 + (i % 2), 0.0), Vector3.ZERO, 0.5)
	await get_tree().physics_frame
	_pick_new()
	_bench_com()
	print("PVE_CPU taken over %d script callbacks" % _taken.size())
	var warm_ticks := int(warm * 60.0)
	var total_ticks := int((warm + secs) * 60.0)
	for i in range(total_ticks):
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		_t += dt
		_bot_rush(p1, _nearest_enemy(p1))
		_tick(dt, i >= warm_ticks)
		if i >= warm_ticks:
			_ticks += 1
	_report()
	pg.queue_free()
	await get_tree().process_frame
	get_tree().quit(_exit_code)


func _tick(delta: float, measure: bool) -> void:
	for e in _taken:
		if not is_instance_valid(e["node"]):
			continue
		var n: Node = e["node"]
		if not n.is_inside_tree():
			continue
		var t0 := Time.get_ticks_usec()
		if e["kind"] == "phys":
			n._physics_process(delta)
		else:
			n._process(delta)
		if measure:
			var us := float(Time.get_ticks_usec() - t0)
			var key := "%s|%s" % [e["path"], e["kind"]]
			_acc_us[key] = float(_acc_us.get(key, 0.0)) + us
			_calls[key] = int(_calls.get(key, 0)) + 1
			_max_us[key] = maxf(float(_max_us.get(key, 0.0)), us)
	_refill()
	# узлы, появившиеся позже (обломки, оружие, вспышки), — тоже под колпак
	if Engine.get_physics_frames() % 30 == 0:
		_pick_new()


## Микро-замер Doll.centre_of_mass(): сколько мкс стоит один вызов (сумма по ~12 частям: global_transform из физсервера × масса).
func _bench_com() -> void:
	var n := 2000
	var t0 := Time.get_ticks_usec()
	for i in range(n):
		p1.centre_of_mass()
	var us := float(Time.get_ticks_usec() - t0) / float(n)
	print("COM bench: %.1f us per Doll.centre_of_mass() (%d parts)" % [us, p1.parts.size()])
	COM_US = us


var COM_US := 0.0


## Держит в бою 5 врагов: убитых Уборщик/Разборщик заменяются новыми (иначе бот-молот вычищает всех за пару секунд и профиль пустой).
func _refill() -> void:
	var alive := 0
	for n in get_tree().get_nodes_in_group("enemies"):
		if (n as Doll).alive:
			alive += 1
	if alive >= 5 or not p1.alive:
		return
	var x := p1.centre_of_mass().x
	director.spawn_enemy("sweeper" if _spawned % 3 == 0 else "scrapling", Vector3(x + (-5.0 if _spawned % 2 == 0 else 5.0), 3.0, 0.0), Vector3.ZERO, 0.5)
	_spawned += 1


## Отбирает авто-вызовы у всех скриптовых узлов поддерева, которых ещё нет в _taken.
func _pick_new() -> void:
	var seen := {}
	for e in _taken:
		seen[e["node"]] = true
	_take(pg, seen)


func _take(n: Node, seen: Dictionary) -> void:
	var sc := n.get_script() as Script
	if sc != null and not seen.has(n):
		var path := sc.resource_path.get_file()
		if n.has_method("_physics_process") and n.is_physics_processing():
			n.set_physics_process(false)
			_taken.append({"node": n, "path": path, "kind": "phys"})
		if n.has_method("_process") and n.is_processing():
			n.set_process(false)
			_taken.append({"node": n, "path": path, "kind": "proc"})
	for c in n.get_children():
		_take(c, seen)


func _report() -> void:
	var rows: Array = []
	var total := 0.0
	for k in _acc_us.keys():
		var per_tick := float(_acc_us[k]) / maxf(float(_ticks), 1.0)
		total += per_tick
		rows.append({"key": k, "us_per_tick": per_tick, "calls_per_tick": float(_calls[k]) / maxf(float(_ticks), 1.0), "max_us": _max_us[k]})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["us_per_tick"]) > float(b["us_per_tick"]))
	print("=== PVE CPU PROFILE (%d ticks, 5 врагов + P1) ===" % _ticks)
	print("%-34s %8s %10s %9s" % ["script|kind", "calls/tk", "us/tick", "max us"])
	var json_rows: Array = []
	for r in rows:
		print("%-34s %8.1f %10.1f %9.0f" % [r["key"], r["calls_per_tick"], r["us_per_tick"], r["max_us"]])
		json_rows.append({"key": r["key"], "us_per_tick": snappedf(r["us_per_tick"], 0.1), "calls_per_tick": snappedf(r["calls_per_tick"], 0.1), "max_us": r["max_us"]})
	for e in _taken:
		if is_instance_valid(e["node"]) and e["path"] == "impact_audio.gd":
			var ia: Node = e["node"]
			var asleep := 0
			var frozen := 0
			var inside := 0
			for b in ia.bodies:
				if is_instance_valid(b):
					asleep += 1 if (b as RigidBody3D).sleeping else 0
					frozen += 1 if (b as RigidBody3D).freeze else 0
					inside += 1 if (b as Node).is_inside_tree() else 0
			print("IMPACT bodies=%d inside=%d asleep=%d frozen=%d" % [ia.bodies.size(), inside, asleep, frozen])
	print("TOTAL scripts us/tick = %.0f  (%.1f%% of 16.7 ms tick)" % [total, total / 167.0])
	var f := FileAccess.open("res://tests/pve_cpu_probe_report.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"ticks": _ticks, "total_us_per_tick": total, "rows": json_rows}, "\t"))
	if budget_us > 0.0 and total > budget_us:
		print("FAIL budget %.0f us > %.0f us" % [total, budget_us])
		_exit_code = 1
	else:
		print("=== OK ===")


# ---- бот-игрок (как в pve_probe) ----

func _give_hammer() -> void:
	var h := pg.get_node("Weapons/Hammer") as Weapon
	var wp: WeaponPickup = null
	for c in p1.get_children():
		if c is WeaponPickup:
			wp = c
	if h != null and wp != null:
		if h.is_held():
			h.drop()
		wp.attach("Hand_R", h)


func _bot_rush(d: Doll, target: Doll) -> void:
	if d == null or not d.alive:
		return
	if target == null or not is_instance_valid(target) or not target.alive:
		d.input_vec = Vector2.ZERO
		return
	var st: Dictionary = _bot.get(d, {"retreat_until": -1.0})
	var dc := d.centre_of_mass()
	var oc := target.centre_of_mass()
	var dx := oc.x - dc.x
	var dy := oc.y - dc.y
	var sgn := signf(dx) if absf(dx) > 0.05 else 1.0
	var vy := clampf(dy / 1.2, -1.0, 1.0) if absf(dy) > 0.5 else 0.0
	if _t < float(st["retreat_until"]):
		d.input_vec = Vector2(-sgn, 0.3)
	elif absf(dx) < 1.2 and absf(dy) < 1.2:
		st["retreat_until"] = _t + 0.9
		d.input_vec = Vector2(-sgn, 0.3)
	else:
		d.input_vec = Vector2(sgn, vy)
	_bot[d] = st


func _nearest_enemy(from: Doll) -> Doll:
	var best: Doll = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Doll
		if e == null or not e.alive or not e.is_inside_tree():
			continue
		var dd := e.centre_of_mass().distance_to(from.centre_of_mass())
		if dd < best_d:
			best_d = dd
			best = e
	return best
