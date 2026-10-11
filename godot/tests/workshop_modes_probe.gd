## Проба инструментов испытания мастерской и «Испытать в режиме…» (docs/plan-demo/MODES_100.md §B).
##   tools: мастерская workshop_build.tscn (автосейв выключен, кукла испытания на external_input): T → испытание; B → бот-спарринг
##     (ModularDoll + RivalBrain уровня 1, в группах rivals и workshop_test, игрок в players), B×2 → уровень 2 у того же мозга, B×2 →
##     нет бота; G → гравитация зала ноль (мир), после stop_test — гравитация мира как в проекте; R не теряет бота и гравитацию;
##     нокаут бота → новый через RESPAWN_S; Y из испытания (dry_run) → чертёж у ModesMenu.player_blueprint, Flow.reopen_workshop,
##     мастерская вернулась к сборке; Y с чертежом без головы → false и ничего не выставлено.
##   swap: карточка duel_classic на куполе с player_blueprint (kit_brawler): P1 — ModularDoll с этим чертежом, в группе dolls,
##     Match его знает, у него ArmAssist и WeaponPickup как у старой куклы; бой стартует (FIGHT), ошибок 0; чертёж переживает R.
## Headless: godot --headless --path godot --fixed-fps 60 res://tests/workshop_modes_probe.tscn -- "only=tools|swap,out=<json>"
extends Node

const TICK := 1.0 / 60.0
const WORKSHOP := "res://scenes/workshop/workshop_build.tscn"
const BRAWLER := "res://data/body/blueprints/kit_brawler.tres"

class ScriptErrors extends Logger:
	var count := 0
	var first := ""
	var _mx := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_mx.lock()
		if error_type == ERROR_TYPE_SCRIPT:
			count += 1
			if first == "":
				first = "%s %s (%s:%d %s)" % [code, rationale, file, line, function]
		_mx.unlock()


var ok := true
var checks: Array = []
var info := {}
var errs := ScriptErrors.new()
var ws: WorkshopBuild
var pg: Node


func _check(id: String, cond: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": cond, "detail": str(detail)})
	if not cond:
		ok = false
	print("  %-36s %s  %s" % [id, "ok  " if cond else "FAIL", str(detail)])


func _args() -> Dictionary:
	var out := {"only": "", "out": ""}
	for a in OS.get_cmdline_user_args():
		for part in String(a).split(","):
			var kv := part.split("=")
			if kv.size() == 2 and out.has(kv[0]):
				out[kv[0]] = kv[1]
	return out


func _want(a: Dictionary, s: String) -> bool:
	return String(a["only"]) == "" or s in String(a["only"]).split("|")


func _ready() -> void:
	OS.add_logger(errs)
	print("=== WORKSHOP MODES PROBE ===")
	var a := _args()
	if _want(a, "tools"):
		await _tools()
	if _want(a, "swap"):
		await _swap()
	await _unload()
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


func _world_g() -> float:
	return float(PhysicsServer3D.area_get_param(get_tree().root.get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY))


func _brain_of(d: Node) -> RivalBrain:
	if d == null:
		return null
	for c in d.get_children():
		if c is RivalBrain:
			return c
	return null


# ------------------------------------------------------------------ tools

func _tools() -> void:
	WsTestTools.sparring_level = 0
	WsTestTools.gravity_step = 0
	ws = (load(WORKSHOP) as PackedScene).instantiate() as WorkshopBuild
	ws.autosave_on_test = false
	ws.probe_input = true
	ws.mode_pick_dry_run = true
	add_child(ws)
	await _wait(0.3)
	var g0 := _world_g()
	_check("tools_test_start", ws.start_test() and ws.test_doll != null, "испытание стартовало")
	await _wait(0.2)
	# B — бот уровня 1
	ws.call("_input", _key(KEY_B))
	await _wait(0.3)
	var bot := WsTestTools.sparring(ws)
	var brain := _brain_of(bot)
	_check("tools_bot_spawn", bot != null and brain != null and brain.level == 1, "бот %s, мозг %s" % [bot != null, brain.level if brain != null else -1])
	_check("tools_bot_groups", bot != null and bot.is_in_group("rivals") and bot.is_in_group(WorkshopBuild.TEST_GROUP) and ws.test_doll.is_in_group("players"))
	_check("tools_bot_external", bot != null and bot.external_input and bot.get_node_or_null("DollCombat") != null)
	# B — уровень 2
	ws.call("_input", _key(KEY_B))
	await _wait(0.3)
	bot = WsTestTools.sparring(ws)
	brain = _brain_of(bot)
	_check("tools_bot_level2", brain != null and brain.level == 2 and WsTestTools.sparring_level == 2, brain.level if brain != null else -1)
	# G — ноль
	ws.call("_input", _key(KEY_G))
	await _wait(0.1)
	_check("tools_gravity_zero", is_zero_approx(_world_g()) and WsTestTools.gravity_step == 1, _world_g())
	# R — бот и гравитация остаются
	ws.call("_input", _key(KEY_R))
	await _wait(0.4)
	bot = WsTestTools.sparring(ws)
	brain = _brain_of(bot)
	_check("tools_restart_keeps", bot != null and brain != null and brain.level == 2 and is_zero_approx(_world_g()), "бот %s, g %.2f" % [bot != null, _world_g()])
	# бот в нокауте → новый
	if bot != null:
		bot.knock_out()
		await _wait(WsTestTools.RESPAWN_S + 0.5)
		var bot2 := WsTestTools.sparring(ws)
		_check("tools_bot_respawn", bot2 != null and bot2 != bot and bot2.alive, "новый бот %s" % (bot2 != null))
	# бой идёт: удары с уроном за 10 с (бот уровня 2 бьёт пассивную куклу)
	var hits := 0
	var closest := INF
	ws.test_doll.damaged.connect(func(_a: float, _at: Node, _p: String, _pos: Vector3, _k: String) -> void: hits += 1)
	for i in 100:
		await _wait(0.1)
		var b := WsTestTools.sparring(ws)
		if b != null and b.alive:
			closest = minf(closest, b.centre_of_mass().distance_to(ws.test_doll.centre_of_mass()))
	info["sparring_hits_10s"] = hits
	_check("tools_bot_approaches", closest < 2.5, "ближе всего %.2f м за 10 с, попаданий с уроном %d" % [closest, hits])
	# B, B — нет бота
	ws.call("_input", _key(KEY_B))
	await _wait(0.1)
	ws.call("_input", _key(KEY_B))
	await _wait(0.2)
	_check("tools_bot_off", WsTestTools.sparring(ws) == null and WsTestTools.sparring_level == 0)
	# Y из испытания
	ModesMenu.player_blueprint = null
	var flow := get_tree().root.get_node_or_null("Flow")
	if flow != null:
		flow.set("reopen_workshop", false)
	var picked := ws.open_mode_picker()
	await _wait(0.2)
	_check("tools_pick", picked and ModesMenu.player_blueprint != null and ws.mode == WorkshopBuild.Mode.BUILD, "picked %s, bp %s, mode %d" % [picked, ModesMenu.player_blueprint != null, ws.mode])
	_check("tools_pick_flow", flow == null or bool(flow.get("reopen_workshop")), "Flow.reopen_workshop")
	_check("tools_gravity_restored", is_equal_approx(_world_g(), g0), "g %.2f (было %.2f)" % [_world_g(), g0])
	ModesMenu.player_blueprint = null
	# Y без головы — нельзя
	var head_uid := ""
	for n in ws.blueprint.nodes:
		if String(n.get("part", "")).contains("head"):
			head_uid = String(n["uid"])
	if head_uid != "":
		ws.detach_part(head_uid)
		await _wait(0.1)
		_check("tools_pick_invalid", not ws.open_mode_picker() and ModesMenu.player_blueprint == null, "без головы")
	WsTestTools.sparring_level = 0
	WsTestTools.gravity_step = 0
	await _unload()


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.pressed = true
	e.physical_keycode = code
	e.keycode = code
	return e


# ------------------------------------------------------------------ swap

func _swap() -> void:
	var def := ModeCatalog.by_id("duel_classic")
	var bp := load(BRAWLER) as BodyBlueprint
	_check("swap_blueprint_loads", bp != null)
	if bp == null:
		return
	pg = (load(def.scene_path()) as PackedScene).instantiate()
	add_child(pg)
	var m := _find_match(pg)
	m.feel_enabled = false
	var old_p1: Doll = null
	for d in m.dolls():
		if (d as Doll).player_index == 0:
			old_p1 = d
	await _wait(0.1)
	ModeRun.launch(def, {"no_scene_change": true, "scene": pg, "player_blueprint": bp})
	var attached := await _until(func() -> bool: return ModeRun.is_active() and ModeRun.mt == m, 8.0)
	_check("swap_attach", attached)
	var p1: Doll = null
	for d in m.dolls():
		if (d as Doll).player_index == 0:
			p1 = d
	_check("swap_p1_modular", p1 != null and p1 is ModularDoll and p1 != old_p1, "P1 %s" % (p1.get_class() if p1 != null else "нет"))
	if p1 != null:
		var pbp: Resource = p1.get("blueprint")
		_check("swap_p1_blueprint", pbp is BodyBlueprint and (pbp as BodyBlueprint).nodes.size() == bp.nodes.size(), "узлов %d / %d" % [(pbp as BodyBlueprint).nodes.size() if pbp is BodyBlueprint else -1, bp.nodes.size()])
		_check("swap_p1_groups", p1.is_in_group("dolls") and not p1.external_input and p1.input_prefix == "p1")
		var has_arm := false
		var has_pick := false
		for c in p1.get_children():
			has_arm = has_arm or c is ArmAssist
			has_pick = has_pick or c is WeaponPickup
		_check("swap_p1_children", has_arm, "ArmAssist %s, WeaponPickup %s" % [has_arm, has_pick])
	var fight := await _until(func() -> bool: return m.combat_active(), 12.0)
	_check("swap_fight", fight, "FIGHT (фаза %d)" % m.phase)
	await _wait(1.0)
	_check("swap_p1_alive", p1 != null and is_instance_valid(p1) and p1.alive and p1.hp > 0.0, "hp %.0f" % (p1.hp if p1 != null else -1.0))
	m.restart()
	await _until(func() -> bool: return m.combat_active(), 12.0)
	var p1b: Doll = null
	for d in m.dolls():
		if (d as Doll).player_index == 0:
			p1b = d
	_check("swap_survives_restart", p1b is ModularDoll and p1b.get("blueprint") is BodyBlueprint and (p1b.get("blueprint") as BodyBlueprint).nodes.size() == bp.nodes.size(), "P1 после R: %s" % (p1b.get_class() if p1b != null else "нет"))
	await _unload()


# ------------------------------------------------------------------ помощники

func _find_match(root: Node) -> Match:
	if root is Match:
		return root
	for c in root.get_children():
		var f := _find_match(c)
		if f != null:
			return f
	return null


func _unload() -> void:
	for n in [ws, pg]:
		if n != null and is_instance_valid(n):
			remove_child(n)
			n.queue_free()
	ws = null
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
	for i in int(round(s / TICK)):
		await get_tree().physics_frame
