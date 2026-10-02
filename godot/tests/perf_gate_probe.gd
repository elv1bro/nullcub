## Гейт производительности (docs/plan-demo/PERF_PASS.md §5): то, что должно оставаться быстрым, и пределы. Headless, без окна.
##   godot --headless --path . --fixed-fps 60 res://tests/perf_gate_probe.tscn → tests/perf_gate_report.json, exit 0/1
## Время — реальные часы, берём МИНИМУМ из нескольких прогонов (под чужой нагрузкой среднее врёт, минимум — нет). Пределы с запасом ~3–5× к
## измеренному после perf-pass и в 3–50× ниже того, что было до него (см. «до» в строке проверки).
##   part_def_cached  — BodyBlueprint.part_def: 2000 вызовов (было 350 мкс на вызов: слабый кэш ресурсов перечитывал .tres с диска);
##   ws_*             — жесты мастерской на пресете kit_human: body_stats, «открутить» (ПКМ), отмена, захват ветки с куклы, смена цели
##                      при протяжке, отмена протяжки, пересборка стенда;
##   debris_*         — Breakable._spawn_debris ящика и бочки после прогрева (было 40 / 75 мс: выпуклая оболочка на каждый кусок).
extends Node

const WS_SCENE := "res://scenes/workshop/workshop_build.tscn"
const RUNS := 5

var report := {"ok": true, "checks": [], "info": {}}
var ws: WorkshopBuild


func _check(id: String, value: float, limit: float, was: String, what: String) -> void:
	var ok := value <= limit
	report["checks"].append({"id": id, "value": snappedf(value, 0.01), "limit": limit, "ok": ok, "what": what, "was": was})
	if not ok:
		report["ok"] = false
	print("  %s %-22s %8.2f ≤ %-7.1f (было %s)  %s" % ["ok  " if ok else "FAIL", id, value, limit, was, what])


func _t() -> int:
	return Time.get_ticks_usec()


func _ms(t0: int) -> float:
	return float(Time.get_ticks_usec() - t0) / 1000.0


func _ready() -> void:
	WorkshopBuild.prefs_path = "user://workshop_prefs_probe.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WorkshopBuild.prefs_path))
	ws = (load(WS_SCENE) as PackedScene).instantiate() as WorkshopBuild
	ws.load_autosave = false
	ws.autosave_on_test = false
	ws.probe_input = true
	add_child(ws)
	_run.call_deferred()


func _run() -> void:
	for i in range(30):
		await get_tree().process_frame
	# --- part_def ---
	var best := INF
	for r in range(3):
		var t0 := _t()
		for i in range(2000):
			BodyBlueprint.part_def("kit_human_hand")
			BodyBlueprint.part_def("kit_human_torso")
		best = minf(best, _ms(t0))
	_check("part_def_cached", best, 40.0, "~1400 мс", "4000 вызовов part_def")
	# --- мастерская ---
	ws.set_preset("kit_human")
	for i in range(20):
		await get_tree().process_frame
	var m := {"body_stats": INF, "unscrew": INF, "undo": INF, "drag_begin_move": INF, "drag_target_change": INF, "drag_cancel": INF, "rebuild_stand": INF}
	for r in range(RUNS):
		var t0 := _t()
		ws.body_stats()
		m["body_stats"] = minf(m["body_stats"], _ms(t0))
		# захват руки (ветка из трёх деталей) и проход над разъёмами
		var n := CraftEdit.find(ws.blueprint, "1")
		var start := Vector2(600, 360)
		ws.probe_input = false   # как в игре: пробы разъёмов — порциями по кадрам (в пробах они синхронные)
		t0 = _t()
		ws.begin_drag(String(n["part"]), start, {"move": "1", "start": start})
		m["drag_begin_move"] = minf(m["drag_begin_move"], _ms(t0))
		ws.probe_input = true
		ws.flush_trials()   # дальше меряем смену цели на полностью посчитанных пробах (как и было)
		for t in (ws.drag.get("targets", []) as Array):
			if not bool(t["accepts"]):
				continue
			var idx := int(ws.drag.get("index", -1))
			t0 = _t()
			ws.update_drag(ws.target_screen_pos(t))
			if int(ws.drag.get("index", -1)) != idx:
				m["drag_target_change"] = minf(m["drag_target_change"], _ms(t0))
		t0 = _t()
		ws.cancel_drag()
		m["drag_cancel"] = minf(m["drag_cancel"], _ms(t0))
		await get_tree().process_frame
		t0 = _t()
		ws.unscrew("3")
		m["unscrew"] = minf(m["unscrew"], _ms(t0))
		await get_tree().process_frame
		t0 = _t()
		ws._rebuild_stand()
		m["rebuild_stand"] = minf(m["rebuild_stand"], _ms(t0))
		t0 = _t()
		ws.undo()
		m["undo"] = minf(m["undo"], _ms(t0))
		await get_tree().process_frame
	_check("ws_body_stats", m["body_stats"], 8.0, "106–330 мс", "WorkshopBuild.body_stats (вызывается на каждое изменение)")
	_check("ws_unscrew", m["unscrew"], 100.0, "270–600 мс", "ПКМ «открутить» деталь")
	_check("ws_undo", m["undo"], 100.0, "290–690 мс", "Ctrl+Z")
	_check("ws_drag_begin", m["drag_begin_move"], 250.0, "~6000 мс (60–130 мс с кэшем PartDef)", "схватить руку с куклы: кадр захвата (пробы разъёмов — порциями)")
	_check("ws_drag_retarget", m["drag_target_change"], 30.0, "~280 мс", "смена ближайшего разъёма при протяжке")
	_check("ws_drag_cancel", m["drag_cancel"], 30.0, "~170 мс", "отпустить деталь мимо")
	_check("ws_rebuild_stand", m["rebuild_stand"], 120.0, "114–280 мс", "пересборка куклы на стенде")
	# --- обломки ---
	for kind in ["crate", "barrel"]:
		var best_d := INF
		for r in range(3):
			var b := (load("res://scenes/props/%s.tscn" % kind) as PackedScene).instantiate() as Breakable
			add_child(b)
			await get_tree().process_frame
			await get_tree().process_frame
			var t0 := _t()
			b._spawn_debris()
			best_d = minf(best_d, _ms(t0))
			b.queue_free()
			await get_tree().process_frame
		_check("debris_" + kind, best_d, 12.0, "40 мс" if kind == "crate" else "75 мс", "Breakable._spawn_debris: " + kind)
	var f := FileAccess.open("res://tests/perf_gate_report.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  ", false))
		f.close()
	var fails := 0
	for c in report["checks"]:
		fails += 0 if bool(c["ok"]) else 1
	print("PERF GATE PROBE ", "OK (%d checks)" % report["checks"].size() if fails == 0 else "FAILED (%d of %d)" % [fails, report["checks"].size()])
	get_tree().quit(0 if fails == 0 else 1)
