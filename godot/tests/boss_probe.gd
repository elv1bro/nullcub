## Проба «Босса» (docs/plan-demo/BOSS.md) на настоящей площадке scenes/playground_boss.tscn (купол, P1 + P2 + босс, BossMatch, BossHud).
##   rules (мозги выключены, куклы ставит проба): босс большой (масштаб ≥ 1.8, масса ≥ ×2.5 игрока); запас ровно BOSS_HP = Σ ❤ деталей,
##     пороги отрыва у всех деталей, кроме торса; светится одна деталь (не торс, не голова в фазах 1–2), оверлей на сетках, HUD её
##     называет; удар в неё × BOSS_WEAK_MULT, в другую — без изменений, босс по игроку × BOSS_HIT_MULT (потолок); через BOSS_WEAK_S —
##     другая; удары в деталь отрывают её (журнал, запас теряет её ❤, счёт игрока, тост HUD); фаза 2 и 3 по запасу (диктор, вспышка,
##     тост, журнал), в ярости — тяга, поле купола, голова в кандидатах, волна с телеграфом толкает и бьёт ближних; жизни: два возврата
##     вдали от босса, третий KO — выбыл; все выбыли — поражение (табличка HUD); R — всё заново (поле купола как было, запас полный);
##     голова оторвана — победа «head»; запас 0 — победа «pool»; время вышло — поражение;
##   bots (оба игрока — боты BossAllyBrain): матч кончается за 60–300 с игры; босс дошёл хотя бы до фазы 2, детали отлетали; босс
##     опасен (выбивал игроков или снял ≥ 40 % их запаса); все в границах арены; физика на кадр (info.phys_ms).
## Обе секции: ошибок скриптов и ошибок движка — 0 (ошибки загрузки ресурсов с диска — отдельно, info.errors_assets; пустышки рендера
## headless — info.errors_dummy_render).
## Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/boss_probe.tscn -- "only=rules|bots|rules+bots,max_s=330,level=2,trace=1,seed=0,out=<json>"
## → JSON между === BOSS PROBE === и === OK / FAIL ===, exit 0/1.
extends Node

const SCENE := "res://scenes/playground_boss.tscn"
const TICK := 1.0 / 60.0
const MIN_MATCH_S := 60.0
const MAX_MATCH_S := 300.0


## Счётчик SCRIPT ERROR за прогон (как king_probe): ошибка скрипта обрывает только свою функцию — проба могла бы молча потерять
## проверки. Ошибки загрузки ресурсов с диска — к режиму не относятся: отдельно, в info.
class ScriptErrors extends Logger:
	var count := 0
	var first := ""
	var engine := 0
	var engine_first := ""
	var assets := 0
	var assets_first := ""
	## Пустышка рендера headless (servers/rendering/dummy): «Parameter "material" is null» — есть в спорт-зале, хоккее, вышибалах,
	## кампании (docs/ai-memory/release-004.md, HIT_FX.md: в окне её нет); к режиму не относится — отдельно (info.errors_dummy_render).
	var dummy := 0
	var dummy_first := ""
	var _mx := Mutex.new()

	static func _is_asset_load(file: String, code: String, rationale: String) -> bool:
		var msg := code + " " + rationale
		return file.begins_with("core/io/resource") or file.begins_with("scene/resources/resource_format_text") \
			or msg.contains("Failed loading resource") or msg.contains("res://.godot/imported/")

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		_mx.lock()
		if error_type == ERROR_TYPE_SCRIPT:
			count += 1
			if first == "":
				first = "%s %s (%s:%d %s)" % [code, rationale, file, line, function]
		elif error_type == ERROR_TYPE_ERROR and file.begins_with("servers/rendering/dummy"):
			dummy += 1
			if dummy_first == "":
				dummy_first = "%s (%s:%d %s)" % [code, file, line, function]
		elif error_type == ERROR_TYPE_ERROR and _is_asset_load(file, code, rationale):
			assets += 1
			if assets_first == "":
				assets_first = "%s %s (%s:%d)" % [code, rationale, file, line]
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
var pg: BossPlayground
var bm: BossMatch
var over_results: Dictionary = {}
var over_count := 0
var announces: Array = []
var errs := ScriptErrors.new()


func _check(id: String, cond: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": cond, "detail": str(detail)})
	if not cond:
		ok = false
	print("  %-30s %s  %s" % [id, "ok  " if cond else "FAIL", str(detail)])


func _args() -> Dictionary:
	var out := {"only": "", "max_s": "330", "level": "2", "trace": "0", "out": "", "seed": "0"}
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
	print("=== BOSS PROBE ===")
	var a := _args()
	if _want(a, "rules"):
		await _rules()
	if _want(a, "bots"):
		await _bots(float(a["max_s"]), int(a["level"]), String(a["trace"]) == "1", int(a["seed"]))
	await _unload()
	_check("errors_script", errs.count == 0, "ошибок скриптов %d; первая: %s" % [errs.count, errs.first])
	_check("errors_engine", errs.engine == 0, "ошибок движка %d; первая: %s" % [errs.engine, errs.engine_first])
	info["errors_assets"] = {"count": errs.assets, "first": errs.assets_first}
	info["errors_dummy_render"] = {"count": errs.dummy, "first": errs.dummy_first}
	if errs.assets > 0:
		print("  (не загрузились ресурсы с диска: %d, первая: %s — не режим, см. info.errors_assets)" % [errs.assets, errs.assets_first])
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

func _load(level := 2, countdown := 0.3, seed_ := 0) -> void:
	await _unload()
	Engine.time_scale = 1.0
	pg = (load(SCENE) as PackedScene).instantiate() as BossPlayground
	pg.p1_bot = true
	pg.p2_bot = true
	pg.bot_level = level
	bm = pg.get_node("Match") as BossMatch
	bm.feel_enabled = false
	bm.countdown_s = countdown
	bm.rng_seed = seed_
	over_results = {}
	over_count = 0
	announces = []
	bm.match_over.connect(func(_w: Doll, r: Dictionary) -> void:
		over_results = r
		over_count += 1)
	bm.announce.connect(func(text: String, _c: Color, kind: String) -> void: announces.append([kind, text]))
	add_child(pg)
	await _until(func() -> bool: return bm.play_state == "play" and bm.dolls().size() == 3 and is_instance_valid(bm.boss), 8.0)


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


func _doll(index: int) -> Doll:
	for d in bm.dolls():
		if is_instance_valid(d) and (d as Doll).player_index == index:
			return d
	return null


func _brains_off() -> void:
	for d in bm.dolls():
		for n in [BossPlayground.BOT_NAME, BossPlayground.BOSS_BRAIN]:
			var b := (d as Node).get_node_or_null(n)
			if b != null:
				b.set_physics_process(false)
		(d as Doll).input_vec = Vector2.ZERO


## Поставить куклу торсом в точку p (все детали — сдвигом, скорости — 0).
func _place(d: Doll, p: Vector2) -> void:
	var t := d.torso().global_position
	var off := Vector3(p.x - t.x, p.y - t.y, 0.0)
	for b in d.parts.values():
		var rb := b as RigidBody3D
		rb.global_position += off
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		rb.reset_physics_interpolation()


static func _mass(d: Doll) -> float:
	var m := 0.0
	for b in d.parts.values():
		m += (b as RigidBody3D).mass
	return m


func _field_g() -> float:
	var f: Variant = pg.arena.get("field")
	return float((f as Object).get("field_g")) if f is Object and is_instance_valid(f) else -1.0


func _announced(kind: String) -> String:
	for a in announces:
		if String(a[0]) == kind:
			return String(a[1])
	return ""


# ------------------------------------------------------------------ правила

func _rules() -> void:
	print("--- rules")
	await _load(2, 0.3, 4242)
	_brains_off()
	var boss := bm.boss
	var p1 := _doll(0)
	var p2 := _doll(1)
	_check("three_dolls", bm.dolls().size() == 3 and bm.players().size() == 2 and boss != null and boss.is_in_group(BossMatch.BOSS_GROUP)
		and bm.play_state == "play", "кукол %d, игроков %d, фаза %s" % [bm.dolls().size(), bm.players().size(), bm.play_state])
	var scale := float(boss.get("body_scale")) if boss.get("body_scale") != null else 1.0
	var mr := _mass(boss) / maxf(_mass(p1), 0.01)
	_check("boss_big", scale >= 1.8 and mr >= 2.5, "масштаб ×%.2f, масса %.0f против %.0f у P1 (×%.1f)" % [scale, _mass(boss), _mass(p1), mr])
	var sum := 0.0
	for n in boss.part_hp:
		sum += float(boss.part_hp[n])
	var no_torso := not boss.joint_hp.has("Torso") and boss.joint_hp.size() >= 8 and boss.joint_hp.has("Head")
	_check("boss_pool", absf(boss.max_hp - Tuning.BOSS_HP) < 0.01 and absf(boss.hp - Tuning.BOSS_HP) < 0.01 and absf(sum - Tuning.BOSS_HP) < 1.0 and no_torso,
		"запас %.0f / %.0f, Σ ❤ деталей %.1f, деталей с порогом отрыва %d (торс %s, голова %s)" % [boss.hp, boss.max_hp, sum,
		boss.joint_hp.size(), boss.joint_hp.has("Torso"), boss.joint_hp.has("Head")])
	_check("players_team", p1.team == BossMatch.PLAYERS_TEAM and p2.team == p1.team and p1.team_damage_mult == 0.0 and boss.team != p1.team
		and int(bm.lives.get(0, -9)) == Tuning.BOSS_LIVES and int(bm.lives.get(1, -9)) == Tuning.BOSS_LIVES,
		"команды %s / %s / босс %s, жизни %s" % [p1.team, p2.team, boss.team, str(bm.lives)])

	# --- светится одна деталь
	await _wait(0.2)
	var wp := bm.weak_part
	var wb := bm.weak_body()
	var glow := false
	if wb != null:
		for mi in wb.find_children("*", "MeshInstance3D", true, false):
			glow = glow or (mi as MeshInstance3D).material_overlay == bm._glow_mat
	_check("weak_glows", wp != "" and wb != null and glow and Doll.part_base_name(wp) != "Head" and wp != "Torso"
		and pg.hud.weak_label.text == tr("СЛАБОЕ МЕСТО: %s") % BossHud.part_title(wp),
		"светится %s (оверлей %s), HUD «%s»" % [wp, glow, pg.hud.weak_label.text])
	var other := ""
	for n in bm.weak_candidates():
		if n != wp:
			other = n
			break
	var d_weak := bm.adjust_hit_damage(boss, p1, 10.0, {"victim_part": wb})
	var d_other := bm.adjust_hit_damage(boss, p1, 10.0, {"victim_part": boss.parts.get(other)})
	var d_boss := bm.adjust_hit_damage(p1, boss, 10.0, {"victim_part": p1.torso()})
	var d_cap := bm.adjust_hit_damage(p1, boss, 500.0, {"victim_part": p1.torso()})
	_check("weak_mult", absf(d_weak - 10.0 * Tuning.BOSS_WEAK_MULT * Tuning.BOSS_PLAYER_DMG_MULT) < 1e-3
		and absf(d_other - 10.0 * Tuning.BOSS_PLAYER_DMG_MULT) < 1e-3 and bm.weak_hits == 1 and int(bm.tally[0]["weak_hits"]) == 1,
		"10 в светящуюся → %.1f, в %s → %.1f; попаданий в слабое %d" % [d_weak, other, d_other, bm.weak_hits])
	_check("boss_hit_mult", absf(d_boss - 10.0 * float(Tuning.BOSS_HIT_MULT[0])) < 1e-3 and absf(d_cap - Tuning.BOSS_HIT_CAP) < 1e-3,
		"босс 10 → %.1f, 500 → %.1f (потолок %.0f)" % [d_boss, d_cap, Tuning.BOSS_HIT_CAP])
	bm.weak_left = 0.02
	await _wait(0.1)
	var wb2 := bm.weak_body()
	var glow_old := false
	if wb != null:
		for mi in wb.find_children("*", "MeshInstance3D", true, false):
			glow_old = glow_old or (mi as MeshInstance3D).material_overlay == bm._glow_mat
	_check("weak_rotates", bm.weak_part != wp and bm.weak_part != "" and wb2 != null and not glow_old and bm.weak_left > Tuning.BOSS_WEAK_S - 0.5,
		"%s → %s, старая погасла %s" % [wp, bm.weak_part, not glow_old])

	# --- отлёт детали
	var part := ""
	for n in ["LowerArm_L", "LowerLeg_R", "LowerArm_R", "LowerLeg_L"]:
		if boss.joint_hp.has(n) and n != bm.weak_part:
			part = n
			break
	await _until(func() -> bool: return boss.can_take_damage(), 2.0)
	var hp0 := boss.hp
	var sub_hp := 0.0
	for n in boss.part_hp:
		if n == part or (part.begins_with("LowerArm") and String(n) == "Hand" + part.substr(8)) or (part.begins_with("LowerLeg") and String(n) == "Foot" + part.substr(8)):
			sub_hp += float(boss.part_hp[n])
	var dealt := 0.0
	var hits := 0
	var body := boss.parts.get(part) as RigidBody3D
	while boss.parts.has(part) and hits < 60:
		var pos := body.global_position
		boss.take_damage(15.0, p1, part, pos, Vector3.UP, "body")
		dealt += 15.0
		hits += 1
		await get_tree().physics_frame
	await get_tree().physics_frame
	var lost: Array = bm.parts_log.filter(func(e: Dictionary) -> bool: return String(e["part"]) == part)
	var drop := hp0 - boss.hp
	_check("part_detaches", part != "" and not boss.parts.has(part) and lost.size() == 1 and int(lost[0]["by"]) == 0
		and int(bm.tally[0]["parts"]) == 1 and drop >= dealt + sub_hp * 0.95 - 1.0 and drop <= dealt + sub_hp * 1.05 + 1.0,
		"%s отлетела за %d ударов по 15 (урон %.0f), запас −%.0f (ветка ❤ %.0f), журнал %s" % [part, hits, dealt, drop, sub_hp, str(lost)])
	await get_tree().process_frame
	_check("hud_part_toast", pg.hud.toast_label.visible and pg.hud.toast_label.text == tr("ОТОРВАНО: %s") % BossHud.part_title(part),
		"тост «%s»" % pg.hud.toast_label.text)

	# --- фазы
	var phases := {"n": []}
	bm.boss_phase_changed.connect(func(n: int) -> void: (phases["n"] as Array).append(n))
	var g0 := _field_g()
	boss.hp = Tuning.BOSS_HP * 0.6
	var p2_ok := await _until(func() -> bool: return bm.boss_phase == 2, 1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var flash_a := pg.hud.flash.color.a
	_check("phase_2", p2_ok and bm.phase_log.size() == 1 and int(bm.phase_log[0]["phase"]) == 2 and _announced("boss_phase") == tr("ФАЗА 2: РЫВКИ")
		and (phases["n"] as Array) == [2] and flash_a > 0.05 and pg.hud.toast_label.text == tr("Титан рвётся рывками — уходи вбок от замаха")
		and pg.hud.phase_label.text == tr("ФАЗА %d/3") % 2 and absf(_field_g() - g0) < 0.01,
		"журнал %s, диктор «%s», вспышка %.2f, тост «%s»" % [str(bm.phase_log), _announced("boss_phase"), flash_a, pg.hud.toast_label.text])
	# шлем: в фазе 2 сустав головы не изнашивается ниже BOSS_HEAD_GUARD порога
	var head_max := float(boss.joint_hp_max.get("Head", 0.0))
	boss.joint_hp["Head"] = head_max * 0.1
	await get_tree().physics_frame
	await get_tree().physics_frame
	var head_left := float(boss.joint_hp.get("Head", -1.0))
	_check("head_guarded", head_max > 0.0 and absf(head_left - head_max * Tuning.BOSS_HEAD_GUARD) < head_max * 0.02 and boss.parts.has("Head"),
		"фаза 2: износ головы 10 %% → %.0f %% порога (шлем %.0f %%)" % [100.0 * head_left / maxf(head_max, 1.0), 100.0 * Tuning.BOSS_HEAD_GUARD])
	boss.joint_hp["Head"] = head_max
	announces.clear()
	boss.hp = Tuning.BOSS_HP * 0.3
	var p3_ok := await _until(func() -> bool: return bm.boss_phase == 3, 1.0)
	var heavy := await _until(func() -> bool: return absf(_field_g() - Tuning.BOSS_RAGE_FIELD_G) < 0.01, Tuning.NULL_FIELD_BLEND_S + 1.0)
	_check("phase_3_rage", p3_ok and bm.phase_log.size() == 2 and _announced("boss_phase") == tr("ФАЗА 3: ЯРОСТЬ") and heavy
		and absf(boss.thrust_mult - Tuning.BOSS_RAGE_THRUST) < 1e-3 and absf(boss.speed_cap_mult - Tuning.BOSS_RAGE_SPEED) < 1e-3
		and "Head" in bm.weak_candidates() and (phases["n"] as Array) == [2, 3],
		"журнал %s, поле %.2f → %.2f G, тяга ×%.2f, голова в кандидатах %s" % [str(bm.phase_log), g0, _field_g(), boss.thrust_mult,
		"Head" in bm.weak_candidates()])
	boss.joint_hp["Head"] = head_max * 0.3
	await get_tree().physics_frame
	await get_tree().physics_frame
	var head_left3 := float(boss.joint_hp.get("Head", -1.0))
	_check("head_unguarded_rage", head_left3 > 0.0 and head_left3 < head_max * Tuning.BOSS_HEAD_GUARD * 0.9,
		"фаза 3: износ головы 30 %% → %.0f %% (шлем снят)" % [100.0 * head_left3 / maxf(head_max, 1.0)])
	boss.joint_hp["Head"] = head_max
	# --- волна
	var bc := boss.centre_of_mass()
	_place(p1, Vector2(bc.x + 3.5, bc.y))
	_place(p2, Vector2(clampf(bc.x - 14.0, -16.0, 16.0) if bc.x > 0.0 else clampf(bc.x + 14.0, -16.0, 16.0), 12.0))
	_brains_off()
	var warned := {"n": 0}
	bm.wave_warning.connect(func(_s: float) -> void: warned["n"] = int(warned["n"]) + 1)
	var hp_p1 := p1.hp
	bm.wave_left = 0.05
	var ring := await _until(func() -> bool: return bm.wave_warning_left() >= 0.0, 0.5)
	var waved := await _until(func() -> bool: return bm.waves.size() > 0, Tuning.BOSS_WAVE_WARN_S + 0.5)
	var v := p1.torso().linear_velocity
	var away := Vector2(v.x, v.y).dot(Vector2(p1.centre_of_mass().x - bc.x, p1.centre_of_mass().y - bc.y).normalized())
	_check("wave", ring and waved and int(warned["n"]) == 1 and _announced("boss_wave") == tr("ВОЛНА!") and int(bm.waves[0]["hits"]) == 1
		and away > 2.0 and p1.hp < hp_p1, "телеграф %s, волн %s, P1 прочь %.1f м/с, запас P1 %.0f → %.0f" % [ring, str(bm.waves), away, hp_p1, p1.hp])

	# --- жизни и возврат
	var back := {"d": null, "t": -1.0}
	bm.doll_respawned.connect(func(d: Doll) -> void:
		back["d"] = d
		back["t"] = bm.fight_time)
	var t_ko := bm.fight_time
	p1.knock_out(boss)
	await get_tree().physics_frame
	var lives1 := int(bm.lives[0])
	var came := await _until(func() -> bool: return back["d"] != null, Tuning.BOSS_RESPAWN_S + 1.0)
	_brains_off()
	var nd: Doll = back["d"]
	var far := -1.0
	if nd != null:
		var c1 := nd.centre_of_mass()
		var cb := boss.centre_of_mass()
		far = Vector2(c1.x, c1.y).distance_to(Vector2(cb.x, cb.y))
	_check("respawn_far", lives1 == Tuning.BOSS_LIVES - 1 and came and nd != null and nd.alive and nd.player_index == 0 and far > 8.0
		and absf(float(back["t"]) - t_ko - Tuning.BOSS_RESPAWN_S) < 0.2 and nd.team == BossMatch.PLAYERS_TEAM,
		"жизней %d, возврат через %.2f с, до босса %.1f м" % [lives1, float(back["t"]) - t_ko, far])
	back["d"] = null
	nd.knock_out(boss)
	await _until(func() -> bool: return back["d"] != null, Tuning.BOSS_RESPAWN_S + 1.0)
	_brains_off()
	var nd2: Doll = back["d"]
	var lives0 := int(bm.lives[0])
	back["d"] = null
	nd2.knock_out(boss)
	await _wait(Tuning.BOSS_RESPAWN_S + 0.5)
	await get_tree().process_frame
	var row: Dictionary = pg.hud.rows.get(0, {})
	var out_txt := (row["name"] as Label).text if not row.is_empty() else ""
	_check("lives_out", lives0 == 0 and int(bm.lives[0]) == 0 and back["d"] == null and not nd2.alive and bm.play_state == "play"
		and int(bm.tally[0]["kos_taken"]) == 3 and out_txt.ends_with(tr("ВЫБЫЛ")),
		"после третьего KO возврата нет, матч идёт (P2 жив), HUD «%s»" % out_txt)
	# --- все выбыли → поражение
	bm.lives[1] = 0
	_doll(1).knock_out(boss)
	var wiped := await _until(func() -> bool: return over_count > 0, 1.0)
	_check("wipe_loses", wiped and over_count == 1 and String(over_results.get("reason", "")) == "wipe" and not bool(over_results.get("players_won", true))
		and over_results.get("winner") == boss and bm.phase == Match.Phase.OVER,
		"итогов %d, причина %s, победил %s" % [over_count, str(over_results.get("reason")), pg.hud.name_of(over_results.get("winner"))])
	await _wait(1.2)
	_check("hud_end_panel", pg.hud.end_panel.visible and pg.hud.end_title.text == tr("ТИТАН ВЫСТОЯЛ") and pg.hud.end_table.get_child_count() == 5 * 3
		and pg.hud.end_sub.text.contains(tr("все игроки выбиты")), "табличка «%s» · %s, ячеек %d" % [pg.hud.end_title.text, pg.hud.end_sub.text,
		pg.hud.end_table.get_child_count()])

	# --- R: заново
	bm.restart()
	await _until(func() -> bool: return bm.play_state == "play", 6.0)
	_brains_off()
	boss = bm.boss
	var restored := await _until(func() -> bool: return absf(_field_g() - g0) < 0.01, Tuning.NULL_FIELD_BLEND_S + 1.0)
	_check("restart_resets", is_instance_valid(boss) and boss.alive and absf(boss.hp - Tuning.BOSS_HP) < 0.01 and boss.parts.has(part)
		and bm.boss_phase == 1 and bm.phase_log.is_empty() and bm.parts_log.is_empty() and bm.waves.is_empty() and restored
		and int(bm.lives[0]) == Tuning.BOSS_LIVES and int(bm.lives[1]) == Tuning.BOSS_LIVES and bm.alive_players().size() == 2
		and not pg.hud.end_panel.visible and absf(boss.thrust_mult - 1.0) < 1e-3 and bm.weak_part != "",
		"запас %.0f, фаза %d, поле %.2f G, жизни %s, деталь %s на месте %s" % [boss.hp, bm.boss_phase, _field_g(), str(bm.lives), part, boss.parts.has(part)])
	# --- голова оторвана → победа
	p1 = _doll(0)
	bm.tally[1]["dmg"] = 50.0
	boss.detach_part("Head", p1)
	var won := await _until(func() -> bool: return over_count > 1, 1.0)
	_check("head_wins", won and String(over_results.get("reason", "")) == "boss" and bool(over_results.get("players_won", false))
		and String(over_results.get("kill_kind", "")) == "head" and over_results.get("winner") == _doll(1),
		"причина %s, как %s, лучший %s" % [str(over_results.get("reason")), str(over_results.get("kill_kind")), BossMatch.doll_name(over_results.get("winner"))])
	await _wait(1.2)
	_check("hud_win_panel", pg.hud.end_panel.visible and pg.hud.end_title.text == tr("ТИТАН ПОВЕРЖЕН!") and pg.hud.end_sub.text.contains(tr("голова оторвана")),
		"табличка «%s» · %s" % [pg.hud.end_title.text, pg.hud.end_sub.text])
	# --- запас 0 → победа
	bm.restart()
	await _until(func() -> bool: return bm.play_state == "play", 6.0)
	_brains_off()
	boss = bm.boss
	p1 = _doll(0)
	await _until(func() -> bool: return boss.can_take_damage(), 2.0)
	boss.take_damage(boss.hp + 5.0, p1, "Torso", boss.torso().global_position, Vector3.UP, "body")
	var won2 := await _until(func() -> bool: return over_count > 2, 1.0)
	_check("pool_wins", won2 and String(over_results.get("reason", "")) == "boss" and String(over_results.get("kill_kind", "")) == "pool"
		and over_results.get("winner") == p1, "причина %s, как %s" % [str(over_results.get("reason")), str(over_results.get("kill_kind"))])
	# --- время вышло → поражение
	bm.restart()
	await _until(func() -> bool: return bm.play_state == "play", 6.0)
	_brains_off()
	bm.fight_time = bm.time_limit_s - 0.3
	var timed := await _until(func() -> bool: return over_count > 3, 2.0)
	_check("timeout_loses", timed and String(over_results.get("reason", "")) == "timeout" and not bool(over_results.get("players_won", true))
		and absf(bm.time_limit_s - Tuning.BOSS_TIME_S) < 0.01, "причина %s, лимит %.0f с" % [str(over_results.get("reason")), bm.time_limit_s])


# ------------------------------------------------------------------ матч ботов

func _bots(max_s: float, level: int, trace: bool, seed_: int) -> void:
	print("--- bots (уровень %d, сид %d)" % [level, seed_])
	await _load(level, 3.0, seed_)
	var acc := {"to_boss": 0.0, "to_players": 0.0, "boss_hits": 0, "player_hits": 0}
	bm.hit.connect(func(v: Doll, att: Node, dmg: float, _k: String, _p: Vector3) -> void:
		if bm.is_boss(v) and is_instance_valid(att) and att is Doll:
			acc["to_boss"] = float(acc["to_boss"]) + dmg
			acc["player_hits"] = int(acc["player_hits"]) + 1
		elif not bm.is_boss(v) and bm.is_boss(att):
			acc["to_players"] = float(acc["to_players"]) + dmg
			acc["boss_hits"] = int(acc["boss_hits"]) + 1)
	var out_of_bounds := 0
	var oob_who := ""
	var b: AABB = pg.arena.call("bounds")
	var t0 := Time.get_ticks_usec()
	var frames := 0
	var trace_t := 0.0
	var phys_us := 0
	while over_count == 0 and bm.fight_time < max_s:
		var f0 := Time.get_ticks_usec()
		await get_tree().physics_frame
		phys_us += Time.get_ticks_usec() - f0
		frames += 1
		if bm.play_state != "play":
			continue
		for d in bm.dolls():
			var dd := d as Doll
			if not dd.alive:
				continue
			var c := dd.centre_of_mass()
			if c.x < b.position.x - 0.5 or c.x > b.end.x + 0.5 or c.y < b.position.y - 0.5 or c.y > b.end.y + 0.5:
				out_of_bounds += 1
				oob_who = "%s (%.1f, %.1f)" % [pg.hud.name_of(dd), c.x, c.y]
		if trace and bm.fight_time - trace_t >= 10.0:
			trace_t = bm.fight_time
			var row := []
			for d in bm.dolls():
				var dd := d as Doll
				var br: Node = dd.get_node_or_null(BossPlayground.BOSS_BRAIN if bm.is_boss(dd) else BossPlayground.BOT_NAME)
				var cc := dd.centre_of_mass()
				row.append("%s:%s(%.0f,%.0f)%.0f%s" % [pg.hud.name_of(dd), String(br.get("state")) if br != null else "-", cc.x, cc.y, dd.hp,
					"" if dd.alive else "†"])
			print("  t=%6.1f фаза %d слабое %s детали %d жизни %s  %s" % [bm.fight_time, bm.boss_phase, bm.weak_part, bm.parts_log.size(),
				str(bm.lives), " ".join(row)])
	var wall_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var reason := String(over_results.get("reason", "?"))
	_check("bots_match_done", over_count == 1 and bm.fight_time >= MIN_MATCH_S and bm.fight_time <= MAX_MATCH_S and reason in ["boss", "wipe"],
		"итог за %.0f с игры (окно %.0f–%.0f), причина %s, игроки победили %s, как %s" % [bm.fight_time, MIN_MATCH_S, MAX_MATCH_S, reason,
		bool(over_results.get("players_won", false)), bm.kill_kind])
	_check("bots_phases", bm.boss_phase >= 2 and bm.phase_log.size() == bm.boss_phase - 1, "фаза %d, журнал %s" % [bm.boss_phase, str(bm.phase_log)])
	_check("bots_parts_fly", bm.parts_log.size() >= 2, "оторвано %d: %s" % [bm.parts_log.size(), str(bm.parts_log.map(func(e: Dictionary) -> String: return String(e["part"])))])
	var kos_players := 0
	for e in bm.ko_log:
		if str(e["victim"]) != "boss":
			kos_players += 1
	_check("bots_boss_dangerous", kos_players >= 1 or float(acc["to_players"]) >= 0.4 * 2.0 * 100.0,
		"игроков выбито %d, урон босса по игрокам %.0f (%d ударов)" % [kos_players, float(acc["to_players"]), int(acc["boss_hits"])])
	_check("bots_weak_used", bm.weak_hits >= 3, "ударов в светящуюся деталь %d из %d" % [bm.weak_hits, int(acc["player_hits"])])
	_check("bots_in_bounds", out_of_bounds == 0, "тиков за границей арены %d (%s)" % [out_of_bounds, oob_who])
	info["bots"] = {"level": level, "seed": seed_, "fight_s": snappedf(bm.fight_time, 0.1), "reason": reason,
		"players_won": over_results.get("players_won", false), "kill_kind": bm.kill_kind, "boss_phase": bm.boss_phase,
		"boss_hp": snappedf(over_results.get("boss_hp", 0.0), 0.1), "phase_log": bm.phase_log.duplicate(true),
		"parts": bm.parts_log.map(func(e: Dictionary) -> String: return "%s@%.0f" % [e["part"], float(e["t"])]),
		"ko_log": bm.ko_log.duplicate(true), "waves": bm.waves.size(), "weak_hits": bm.weak_hits,
		"dmg_to_boss": snappedf(float(acc["to_boss"]), 0.1), "dmg_to_players": snappedf(float(acc["to_players"]), 0.1),
		"boss_env_dmg": snappedf(bm.boss_env_dmg, 0.1), "tally": bm.tally.duplicate(true),
		"ms_per_physics_frame": snappedf(wall_ms / maxf(frames, 1), 0.01),
		"phys_ms": snappedf(float(phys_us) / 1000.0 / maxf(frames, 1), 0.01)}
