## Проба реестра режимов (docs/plan-demo/MODES_100.md): каталог, запуск карточек через ModeRun на настоящих площадках, возврат статиков.
##   catalog: карточек ≥ 100, id и имена без повторов, у каждой — основа из ModeDef.BASES, существующая сцена, известные модификаторы,
##     теги и описание; у каждого модификатора — name / desc / group.
##   launch (по умолчанию покрывающая выборка: каждая основа · карта и каждый модификатор хотя бы раз; all=1 — все карточки; ids=a+b —
##     только эти): площадка ставится в дерево пробы, ModeRun.launch(no_scene_change) должен привязаться за ≤ 8 с, после FIGHT
##     проверяются следы модификаторов (тяга ×, запас, урон ×, отброс ×, гравитация, суставы, стазис, время, пропсы, мозги ботов), затем
##     play_s секунд боя без ошибок скриптов; после выхода со сцены — статики как до (JointBreak / PartHp / Stasis / зум / гравитация
##     мира / time_scale) и ModeRun не активен.
##   bots: карточки с ботами (все куклы — боты) доигрываются до match_over за ≤ max_s (duel_bot_3 на куполе, bomb_turbo, race_zero_g).
## Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/modes_probe.tscn -- "only=catalog|launch|bots,all=1,ids=duel_zero_g+bomb_turbo,play_s=6,max_s=240,out=<json>"
## → JSON между === MODES PROBE === и === OK / FAIL ===, exit 0/1.
extends Node

const TICK := 1.0 / 60.0

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
var pg: Node = null


func _check(id: String, cond: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": cond, "detail": str(detail)})
	if not cond:
		ok = false
	print("  %-40s %s  %s" % [id, "ok  " if cond else "FAIL", str(detail)])


func _args() -> Dictionary:
	var out := {"only": "", "all": "0", "ids": "", "play_s": "6", "max_s": "240", "out": "", "seed": "7"}
	for a in OS.get_cmdline_user_args():
		for part in String(a).split(","):
			var kv := part.split("=")
			if kv.size() == 2 and out.has(kv[0]):
				out[kv[0]] = kv[1]
	return out


func _want(a: Dictionary, section: String) -> bool:
	return String(a["only"]) == "" or section in String(a["only"]).split("|")


func _ready() -> void:
	OS.add_logger(errs)
	print("=== MODES PROBE ===")
	var a := _args()
	if _want(a, "catalog"):
		_catalog()
	if _want(a, "launch"):
		await _launch_all(a)
	if _want(a, "bots"):
		await _bots(float(a["max_s"]), int(a["seed"]))
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


# ------------------------------------------------------------------ catalog

func _catalog() -> void:
	var all := ModeCatalog.all()
	info["cards"] = all.size()
	_check("catalog_count", all.size() >= 100, "карточек %d" % all.size())
	var ids := {}
	var names := {}
	var bad_base: Array = []
	var bad_scene: Array = []
	var bad_mut: Array = []
	var no_desc: Array = []
	var no_tags: Array = []
	var dup_id: Array = []
	var dup_name: Array = []
	var mut_used := {}
	for d in all:
		var def := d as ModeDef
		if ids.has(def.id):
			dup_id.append(def.id)
		ids[def.id] = true
		if names.has(def.name):
			dup_name.append(def.name)
		names[def.name] = true
		if not ModeDef.BASES.has(def.base):
			bad_base.append(def.id)
		var sp := def.scene_path()
		if sp == "" or not ResourceLoader.exists(sp):
			bad_scene.append(def.id)
		for m in def.mutator_ids():
			mut_used[m] = true
			if not Mutators.has(String(m)):
				bad_mut.append("%s:%s" % [def.id, m])
		if def.desc == "":
			no_desc.append(def.id)
		if def.tags.is_empty():
			no_tags.append(def.id)
	_check("catalog_ids_unique", dup_id.is_empty(), dup_id)
	_check("catalog_names_unique", dup_name.is_empty(), dup_name)
	_check("catalog_bases", bad_base.is_empty(), bad_base)
	_check("catalog_scenes_exist", bad_scene.is_empty(), bad_scene)
	_check("catalog_mutators_known", bad_mut.is_empty(), bad_mut)
	_check("catalog_desc", no_desc.is_empty(), no_desc)
	_check("catalog_tags", no_tags.is_empty(), no_tags)
	var unused: Array = []
	var bad_entry: Array = []
	for id in Mutators.ids():
		var e: Dictionary = Mutators.CATALOG[id]
		if not (e.has("name") and e.has("desc") and e.has("group")):
			bad_entry.append(id)
		if not mut_used.has(id):
			unused.append(id)
	_check("mutators_entries", bad_entry.is_empty(), bad_entry)
	_check("mutators_all_used", unused.is_empty(), "не в карточках: %s" % [unused])
	info["mutators"] = Mutators.ids().size()
	info["tags"] = ModeCatalog.tags()
	_check("catalog_by_id", ModeCatalog.by_id("duel_zero_g") != null and ModeCatalog.by_id("nope") == null)
	_check("catalog_daily", ModeCatalog.daily() != null and ModeCatalog.daily().id == ModeCatalog.daily().id)
	var rt := ModeDef.from_dict(ModeCatalog.by_id("duel_bot_3").to_dict())
	_check("def_roundtrip", rt.id == "duel_bot_3" and rt.mutators.size() == 1 and int(rt.mutators[0]["args"]["level"]) == 3)


# ------------------------------------------------------------------ launch

## Покрывающая выборка: первая карточка на каждую пару основа·карта и первая на каждый модификатор.
func _sample(a: Dictionary) -> Array:
	var all := ModeCatalog.all()
	if String(a["all"]) == "1":
		return all
	if String(a["ids"]) != "":
		var out: Array = []
		for id in String(a["ids"]).split("+"):
			var d := ModeCatalog.by_id(id)
			if d != null:
				out.append(d)
		return out
	var seen_scene := {}
	var seen_mut := {}
	var out: Array = []
	for d in all:
		var def := d as ModeDef
		var take := not seen_scene.has(def.scene_path())
		for m in def.mutator_ids():
			if not seen_mut.has(m):
				take = true
		if take:
			out.append(def)
			seen_scene[def.scene_path()] = true
			for m in def.mutator_ids():
				seen_mut[m] = true
	return out


func _launch_all(a: Dictionary) -> void:
	var sample := _sample(a)
	info["launched"] = []
	var play_s := float(a["play_s"])
	for d in sample:
		await _launch_one(d as ModeDef, play_s, int(a["seed"]))


func _statics() -> Dictionary:
	var space := get_tree().root.get_world_3d().space
	return {
		"jb": JointBreak.on, "ph": PartHp.on, "st": Stasis.on, "zoom": DynamicCamera.user_zoom, "ts": Engine.time_scale,
		"g": PhysicsServer3D.area_get_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY),
		"gv": PhysicsServer3D.area_get_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR),
		"squad_mode": SquadSettings.mode,
	}


func _launch_one(def: ModeDef, play_s: float, seed_: int) -> void:
	var before := _statics()
	await _unload()
	var ps := load(def.scene_path()) as PackedScene
	if ps == null:
		_check("launch_%s" % def.id, false, "сцена не грузится")
		return
	ModeRun._prepare_statics(def)   # статики, которые площадка читает в _ready
	pg = ps.instantiate()
	for prop in ["p1_bot"]:
		if prop in pg:
			pg.set(prop, true)
	if "p2_human" in pg:
		pg.set("p2_human", false)
	add_child(pg)
	var m := _find_match(pg)
	if m == null:
		_check("launch_%s" % def.id, false, "нет Match в сцене")
		return
	m.feel_enabled = false
	ModeRun.launch(def, {"no_scene_change": true, "scene": pg, "p1_bot": true, "seed": seed_})
	var attached := await _until(func() -> bool: return ModeRun.is_active() and ModeRun.mt == m, 8.0)
	_check("attach_%s" % def.id, attached, "привязка за 8 с")
	if not attached:
		return
	await _until(func() -> bool: return m.combat_active(), 12.0)
	var fight := m.combat_active()
	_check("fight_%s" % def.id, fight, "FIGHT за 12 с (фаза %d)" % m.phase)
	if fight:
		await _wait(0.5)
		_check_traces(def, m)
		await _wait(play_s)
	var errs_before := errs.count
	await _unload()
	await _wait(0.2)
	var after := _statics()
	var same := true
	var diff: Array = []
	for k in before:
		var eq: bool = before[k] == after[k] if not (before[k] is float) else is_equal_approx(float(before[k]), float(after[k]))
		if k == "squad_mode":
			eq = true
		if not eq:
			same = false
			diff.append("%s: %s → %s" % [k, before[k], after[k]])
	_check("restore_%s" % def.id, same and not ModeRun.is_active(), diff)
	_check("noerr_%s" % def.id, errs.count == errs_before, "ошибок скриптов за прогон: %d" % (errs.count - errs_before))
	(info["launched"] as Array).append(def.id)


## Следы модификаторов на куклах / Match / мире после FIGHT.
func _check_traces(def: ModeDef, m: Match) -> void:
	var dolls := m.dolls()
	var need := 1 if def.base in ["pve", "stasis"] else 2   # PvE: враги приходят волнами позже
	_check("dolls_%s" % def.id, dolls.size() >= need, "кукол %d" % dolls.size())
	if dolls.is_empty():
		return
	var d0 := dolls[0] as Doll
	for mu in def.mutators:
		var id := String(mu["id"])
		var args := Mutators.merged_args(id, mu["args"])
		var tag := "%s/%s" % [def.id, id]
		match id:
			"fast", "slow":
				_check("trace_" + tag, is_equal_approx(d0.mode_thrust_mult, float(args["mult"])), "mode_thrust_mult %.2f" % d0.mode_thrust_mult)
			"glass", "tank":
				_check("trace_" + tag, is_equal_approx(d0.max_hp, float(args["hp"])) and is_equal_approx(d0.hp, float(args["hp"])), "max_hp %.0f hp %.0f" % [d0.max_hp, d0.hp])
			"double_damage", "half_damage":
				_check("trace_" + tag, is_equal_approx(m.mode_damage_mult, float(args["mult"])), m.mode_damage_mult)
			"feather", "anchor":
				_check("trace_" + tag, is_equal_approx(m.mode_knockback_mult, float(args["mult"])), m.mode_knockback_mult)
			"shove_only":
				_check("trace_" + tag, is_zero_approx(d0.incoming_mult), d0.incoming_mult)
			"spinner":
				_check("trace_" + tag, d0.spin_torque_mult >= 1.9, d0.spin_torque_mult)
			"brittle":
				_check("trace_" + tag, JointBreak.on and not PartHp.on, "jb %s ph %s" % [JointBreak.on, PartHp.on])
			"iron":
				_check("trace_" + tag, not JointBreak.on and not PartHp.on and is_equal_approx(d0.max_hp, Tuning.MAX_HP), "jb %s ph %s max_hp %.0f" % [JointBreak.on, PartHp.on, d0.max_hp])
			"blitz", "marathon", "sudden_start":
				_check("trace_" + tag, is_equal_approx(m.time_limit_s, float(args["limit_s"])), m.time_limit_s)
			"slowmo", "hyper":
				_check("trace_" + tag, is_equal_approx(m.mode_time_scale, float(args["scale"])) and is_equal_approx(Engine.time_scale, float(args["scale"])), "mode %.2f engine %.2f" % [m.mode_time_scale, Engine.time_scale])
			"stasis_on":
				_check("trace_" + tag, Stasis.on, Stasis.on)
			"zoom_in", "zoom_out":
				_check("trace_" + tag, is_equal_approx(DynamicCamera.user_zoom, float(args["zoom"])), DynamicCamera.user_zoom)
			"g_zero", "g_light", "g_heavy", "g_side", "g_up":
				var g := _gravity_at(d0)
				var want := Vector2(args["dir"]).normalized() * Tuning.GRAVITY * float(args["g"])
				var okg := g.distance_to(want) < 0.35
				_check("trace_" + tag, okg, "g=(%.2f, %.2f) ждём (%.2f, %.2f)" % [g.x, g.y, want.x, want.y])
			"barrels":
				_check("trace_" + tag, get_tree().get_nodes_in_group("mode_props").size() >= int(args["n"]), get_tree().get_nodes_in_group("mode_props").size())
			"weapons":
				var wp := 0
				for d in dolls:
					for c in (d as Node).get_children():
						if c is WeaponPickup:
							wp += 1
							break
				_check("trace_" + tag, get_tree().get_nodes_in_group("mode_props").size() >= Mutators.WEAPON_IDS.size() and wp == dolls.size(), "оружия %d, подбор у %d/%d" % [get_tree().get_nodes_in_group("mode_props").size(), wp, dolls.size()])
			"bots":
				var brains := 0
				for d in dolls:
					for c in (d as Node).get_children():
						if c.has_method("steer") or c is RivalBrain:
							brains += 1
							break
				_check("trace_" + tag, brains >= 1, "мозгов %d у %d кукол" % [brains, dolls.size()])
			"champion":
				var league := 0
				for d in m.dolls():
					if (d as Doll).team == "league":
						league += 1
				_check("trace_" + tag, league == 1, "куклы лиги: %d" % league)
			"coop":
				var p2 := _doll(m, 1)
				_check("trace_" + tag, p2 != null and not p2.external_input, "P2 external_input %s" % (str(p2.external_input) if p2 != null else "нет P2"))
			"crates", "barrel_rain", "regen", "one_hit", "vampire", "drunk", "g_swing", "g_random", "g_pulse":
				pass   # тики / удары: проверяется в bots и отсутствием ошибок


static func _doll(m: Match, index: int) -> Doll:
	for d in m.dolls():
		if (d as Doll).player_index == index:
			return d
	return null


## Гравитация в точке торса куклы (м/с², плоскость XY): поле купола или мир.
func _gravity_at(d: Doll) -> Vector2:
	var torso: RigidBody3D = d.parts.get("Torso", null)
	if torso == null:
		for b in d.parts.values():
			torso = b
			break
	if torso == null:
		return Vector2.ZERO
	var g := torso.get_gravity()
	return Vector2(g.x, g.y)


# ------------------------------------------------------------------ bots

func _bots(max_s: float, seed_: int) -> void:
	var limits := {"duel_bot_3": 1.0, "bomb_turbo": 2.0, "race_zero_g": 1.0}   # бомба — до 2 побед, 2.5–5 мин (BOMB.md)
	for id in limits:
		var def := ModeCatalog.by_id(id)
		var lim_s: float = max_s * float(limits[id])
		await _unload()
		var ps := load(def.scene_path()) as PackedScene
		ModeRun._prepare_statics(def)
		pg = ps.instantiate()
		if "p1_bot" in pg:
			pg.set("p1_bot", true)
		if "p2_human" in pg:
			pg.set("p2_human", false)
		add_child(pg)
		var m := _find_match(pg)
		m.feel_enabled = false
		var over := {"n": 0, "winner": null}
		m.match_over.connect(func(w: Doll, _r: Dictionary) -> void:
			over["n"] += 1
			over["winner"] = w)
		ModeRun.launch(def, {"no_scene_change": true, "scene": pg, "p1_bot": true, "seed": seed_})
		var attached := await _until(func() -> bool: return ModeRun.is_active() and ModeRun.mt == m, 8.0)
		_check("bots_attach_%s" % id, attached)
		if not attached:
			continue
		var t0 := Time.get_ticks_msec()
		var done := await _until(func() -> bool: return over["n"] > 0, lim_s)
		_check("bots_over_%s" % id, done, "match_over за %.0f с игры: %s (fight_time %.0f)" % [lim_s, done, m.fight_time])
		info["bots_%s" % id] = {"fight_time": m.fight_time, "real_ms": Time.get_ticks_msec() - t0}
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
	for i in int(round(s / TICK)):
		await get_tree().physics_frame
