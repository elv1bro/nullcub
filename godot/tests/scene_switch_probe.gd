## Проба смены арены (headless): клавиши 1 / 2 / 3 площадки (playground.gd: get_tree().change_scene_to_file). Наблюдатель (Watcher)
## висит прямо под root (переживает смену сцены): грузит playground.tscn как текущую сцену, ждёт WAIT_TICKS, шлёт InputEventKey «2»
## (physical KEY_2) через Input.parse_input_event → ждёт → проверяет, что текущая сцена — playground_workshop (arena_id workshop,
## арена WorkshopArena, Match в COUNTDOWN/FIGHT, HUD с 2 панелями, Engine.time_scale 1), затем «3» → playground_void (VoidArena),
## «1» → обратно в Руины, и «R» (restart) — фаза COUNTDOWN и куклы новые. Exit 0/1, отчёт tests/scene_switch_report.json.
## Запуск: godot --headless --path . --fixed-fps 60 res://tests/scene_switch_probe.tscn
extends Node

const WAIT_TICKS := 90
const RUINS := "res://scenes/playground.tscn"


func _ready() -> void:
	# наблюдатель — отдельный узел под root: сама сцена пробы освобождается при change_scene_to_file
	var w := Watcher.new()
	w.name = "SceneSwitchWatcher"
	get_tree().root.call_deferred("add_child", w)
	get_tree().call_deferred("change_scene_to_file", RUINS)


class Watcher extends Node:
	const MAX_TICKS := 3600   # страховка: 60 с симуляции — выход с ошибкой
	var step := 0
	var ticks := 0
	var total := 0
	var old_doll_ids: Array = []
	var report := {"ok": true, "checks": []}


	func _check(id: String, ok: bool, detail: String) -> void:
		report["checks"].append({"id": id, "ok": ok, "detail": detail})
		if not ok:
			report["ok"] = false
		print("  %s %s: %s" % ["ok  " if ok else "FAIL", id, detail])


	func _press(code: Key) -> void:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = true
		Input.parse_input_event(ev)
		var up := InputEventKey.new()
		up.physical_keycode = code
		up.keycode = code
		up.pressed = false
		Input.parse_input_event(up)


	func _scene_checks(tag: String, arena_id: String, arena_class: String) -> void:
		var cs := get_tree().current_scene
		_check(tag + "_scene", cs != null and cs.get("arena_id") == arena_id, "current scene arena_id == %s (%s)" % [arena_id, str(cs.get("arena_id")) if cs != null else "null"])
		if cs == null:
			return
		var arena: Node = cs.get("arena")
		_check(tag + "_arena", arena != null and arena.is_class("Node3D") and arena.get_script() != null and arena.get_script().get_global_name() == arena_class, "arena is %s" % arena_class)
		var m: Node = cs.get("match_node")
		_check(tag + "_match", m != null and (m.get("phase") == Match.Phase.COUNTDOWN or m.get("phase") == Match.Phase.FIGHT), "Match running (phase=%s)" % (str(m.get("phase")) if m != null else "null"))
		var hud: Node = cs.get("hud")
		_check(tag + "_hud", hud != null and (hud.get("panels") as Dictionary).size() == 2, "HUD has 2 panels")
		_check(tag + "_dolls", get_tree().get_nodes_in_group("dolls").size() == 2, "group dolls has 2 (%d)" % get_tree().get_nodes_in_group("dolls").size())
		_check(tag + "_time_scale", is_equal_approx(Engine.time_scale, 1.0), "Engine.time_scale == 1")
		var combats := 0
		for d in get_tree().get_nodes_in_group("dolls"):
			if Match.combat_of(d) != null:
				combats += 1
		_check(tag + "_combat", combats == 2, "each doll has DollCombat (%d)" % combats)


	func _physics_process(_delta: float) -> void:
		ticks += 1
		total += 1
		if total > MAX_TICKS:
			print("=== SCENE SWITCH PROBE: timeout at step %d ===" % step)
			get_tree().quit(1)
			return
		if Loading.showing:     # смена площадки идёт под лоадером (scripts/menu/loading.gd): ждём, пока он уйдёт
			ticks = 0
			return
		if ticks < WAIT_TICKS:
			return
		ticks = 0
		match step:
			0:
				_scene_checks("ruins", "ruins", "RuinsArena")
				_press(KEY_2)
			1:
				_scene_checks("workshop", "workshop", "WorkshopArena")
				_press(KEY_3)
			2:
				_scene_checks("void", "void", "VoidArena")
				_press(KEY_1)
			3:
				_scene_checks("ruins2", "ruins", "RuinsArena")
				for d in get_tree().get_nodes_in_group("dolls"):
					old_doll_ids.append(d.get_instance_id())
				_press(KEY_R)
			4:
				var fresh := 0
				for d in get_tree().get_nodes_in_group("dolls"):
					if not old_doll_ids.has(d.get_instance_id()):
						fresh += 1
				_check("restart_fresh", fresh == 2, "R respawned both dolls (%d fresh)" % fresh)
				var m: Node = get_tree().current_scene.get("match_node")
				_check("restart_phase", m != null and m.get("phase") == Match.Phase.COUNTDOWN, "phase COUNTDOWN right after R (phase=%s)" % (str(m.get("phase")) if m != null else "null"))
				var js := JSON.stringify(report, "  ")
				print("=== SCENE SWITCH PROBE ===")
				print(js)
				var f := FileAccess.open("res://tests/scene_switch_report.json", FileAccess.WRITE)
				if f:
					f.store_string(js)
					f.close()
				print("=== %s ===" % ("OK" if report["ok"] else "FAIL"))
				get_tree().quit(0 if report["ok"] else 1)
		step += 1
