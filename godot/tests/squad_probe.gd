## Проба «Стычки 3 на 3» (docs/plan-demo/SQUAD.md) на настоящей площадке scenes/playground_squad.tscn (Полигон, шесть бойцов,
## SquadMatch, SquadGun, SquadHud).
##   aim (боты молчат): рука с оружием своей команды (у синих — кисть Hand_L, у красных — Hand_R) наводит ствол на точку в 8 м в
##     пяти направлениях к стороне соперника (±60°) — угол ствола к цели, медиана и худший; у команд одинаково;
##   rules (P1 — человек без ввода, боты молчат, ящики выключены): шесть бойцов и команды; у каждого одна рука (своей стороны) и
##     пистолет с полным магазином; свои не ранят ни ударом, ни пулей; пуля — урон без Match.on_hit (ни стоп-кадров, ни замедлений,
##     ни эффектов удара); темп не выше interval, магазин тратится, пустой — перезарядка сама за reload_s, клавишей — тоже; патронов
##     нет — спуск молчит; очки за урон и фраг, улучшения: ветка из трёх → второй уровень → усиления, оружие и усиления переживают
##     возврат; броня: урон × 0.5 и снимается с неё; ящики: патроны / жизни / броня берутся касанием, полный запас — не берётся,
##     ящики появляются сами; нокаут — очко и фраг, возврат на базу со щитом; падение — очко сопернику; конец по очкам и по времени,
##     заново — всё сброшено;
##   bots (P1 тоже бот): матч ботов до конца — все стреляют, пули попадают, урона по своим нет, фраги у обеих команд, первый фраг не
##     поздно, перезарядки, улучшения и ящики были, никто не застрял надолго, все в границах карты; пули не дали эффектов удара
##     (hit_fx — от ударов телом); темп и счёт — в info.
## Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/squad_probe.tscn -- "only=aim|rules|bots,max_s=330,level=2,trace=1,out=<json>"
## → JSON между === SQUAD PROBE === и === OK / FAIL ===, exit 0/1. errors_script — SCRIPT ERROR за прогон (Logger).
extends Node

const SCENE := "res://scenes/playground_squad.tscn"
const TICK := 1.0 / 60.0

## Счётчик SCRIPT ERROR за прогон (как stasis_probe): ошибка скрипта обрывает только свою функцию — проба могла бы молча потерять проверки.
class ScriptErrors extends Logger:
	var count := 0
	var first := ""
	var _mx := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mx.lock()
		count += 1
		if first == "":
			first = "%s %s (%s:%d %s)" % [code, rationale, file, line, function]
		_mx.unlock()


var ok := true
var checks: Array = []
var info := {}
var pg: SquadPlayground
var sm: SquadMatch
var over_results: Dictionary = {}
var over_count := 0
var errs := ScriptErrors.new()


func _check(id: String, cond: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": cond, "detail": str(detail)})
	if not cond:
		ok = false
	print("  %-34s %s  %s" % [id, "ok  " if cond else "FAIL", str(detail)])


func _args() -> Dictionary:
	var out := {"only": "", "max_s": "330", "level": "2", "trace": "0", "out": ""}
	for a in OS.get_cmdline_user_args():
		for part in String(a).split(","):
			var kv := part.split("=")
			if kv.size() == 2 and out.has(kv[0]):
				out[kv[0]] = kv[1]
	return out


func _ready() -> void:
	OS.add_logger(errs)
	print("=== SQUAD PROBE ===")
	var a := _args()
	if String(a["only"]) in ["", "aim"]:
		await _aim()
	if String(a["only"]) in ["", "rules"]:
		await _rules()
	if String(a["only"]) in ["", "bots"]:
		await _bots(float(a["max_s"]), int(a["level"]), String(a["trace"]) == "1")
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


# ------------------------------------------------------------------ помощники

func _load(p1_bot: bool, level := 2, countdown := 0.3, supplies := false) -> void:
	await _unload()
	Engine.time_scale = 1.0
	pg = (load(SCENE) as PackedScene).instantiate() as SquadPlayground
	pg.p1_bot = p1_bot
	pg.bot_level = level
	sm = pg.get_node("Match") as SquadMatch
	sm.feel_enabled = false
	sm.countdown_s = countdown
	sm.supplies = supplies
	over_results = {}
	over_count = 0
	sm.match_over.connect(func(_w: Doll, r: Dictionary) -> void:
		over_results = r
		over_count += 1)
	add_child(pg)
	await _until(func() -> bool: return sm.play_state == "play" and sm.dolls().size() == 6, 8.0)


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
	for i in int(s / TICK):
		await get_tree().physics_frame


func _doll(index: int) -> Doll:
	for d in sm.dolls():
		if is_instance_valid(d) and (d as Doll).player_index == index:
			return d
	return null


func _gun(index: int) -> SquadGun:
	return SquadMatch.gun_of(_doll(index))


func _brains_off() -> void:
	for d in sm.dolls():
		var b := (d as Node).get_node_or_null("SquadBrain")
		if b != null:
			b.set_physics_process(false)
			(d as Doll).input_vec = Vector2.ZERO
		var g := SquadMatch.gun_of(d)
		if g != null:
			g.trigger = false


## Держать куклу в воздухе на месте (тяга = вес), руку — на точку tgt, ticks тиков.
func _hold(d: Doll, tgt: Vector3, ticks: int) -> void:
	var arm := SquadMatch.gun_of(d).arm()
	for i in ticks:
		var br := d.get_node_or_null("SquadBrain") as SquadBrain
		if br != null:
			d.input_vec = br.hover_vec()
		arm.set_target_override(tgt)
		await get_tree().physics_frame


# ------------------------------------------------------------------ прицел

## Пять направлений к стороне соперника (у синих — вправо, у красных — влево; ±60° от горизонтали), точка в 8 м; через 0.9 с — угол
## ствола (SquadGun.aim_ray: плечо → кисть) к направлению «дуло → цель». Два круга, мерится второй.
func _aim() -> void:
	print("--- aim")
	await _load(false)
	_brains_off()
	await _wait(0.8)
	var res := {}
	for pi in [2, 3]:
		var d := _doll(pi)
		var side := 1.0 if SquadMatch.team_of(d) == 0 else -1.0
		var by_dir: Array = []
		for k in 10:
			var ang := deg_to_rad(-60.0 + 30.0 * float(k % 5))
			var c := d.centre_of_mass()
			var tgt := Vector3(c.x, maxf(c.y, 3.0), 0.0) + Vector3(cos(ang) * side, sin(ang), 0.0) * 8.0
			await _hold(d, tgt, 54)
			if k < 5:
				continue
			var ray := SquadMatch.gun_of(d).aim_ray()
			var to := tgt - (ray[0] as Vector3)
			to.z = 0.0
			by_dir.append(snappedf(rad_to_deg((ray[1] as Vector3).angle_to(to.normalized())), 0.1))
		var sorted: Array = by_dir.duplicate()
		sorted.sort()
		res[pi] = {"median": float(sorted[2]), "worst": float(sorted[4]), "by_dir_m60_to_p60": by_dir,
			"hand": SquadMatch.gun_of(d).arm().part_name}
		SquadMatch.gun_of(d).arm().clear_target_override()
	info["aim"] = res
	print("  " + JSON.stringify(res))
	var mb := float(res[2]["median"])
	var mr := float(res[3]["median"])
	_check("aim_blue", mb < 8.0 and float(res[2]["worst"]) < 20.0, "синий (%s): медиана %.1f°, худший %.1f°" % [res[2]["hand"], mb, float(res[2]["worst"])])
	_check("aim_red", mr < 8.0 and float(res[3]["worst"]) < 20.0, "красный (%s): медиана %.1f°, худший %.1f°" % [res[3]["hand"], mr, float(res[3]["worst"])])
	_check("aim_fair", absf(mb - mr) < 5.0, "разница медиан %.1f°" % absf(mb - mr))
	await _unload()


# ------------------------------------------------------------------ правила

func _rules() -> void:
	print("--- rules")
	await _load(false)
	_brains_off()
	var ds := sm.dolls()
	var teams := [0, 0]
	var team_ok := true
	for d in ds:
		var t := SquadMatch.team_of(d)
		teams[t] += 1
		team_ok = team_ok and (d as Doll).team == "squad_%d" % t and is_equal_approx((d as Doll).team_damage_mult, 0.0) \
			and (d as Node).is_in_group(SquadMatch.team_group(t)) and not (d as Node).is_in_group(SquadMatch.team_group(1 - t))
	_check("six_fighters", ds.size() == 6 and teams == [3, 3] and team_ok, "бойцов %d, синих / красных %s, команды и группы %s" % [ds.size(), str(teams), str(team_ok)])
	var hands_ok := 0
	var pistols := 0
	for d in ds:
		var want := "Hand_L" if SquadMatch.team_of(d) == 0 else "Hand_R"
		if _arms(d) == [want]:
			hands_ok += 1
		var g := SquadMatch.gun_of(d)
		if g != null and g.weapon == "pistol" and g.mag == 12 and g.reserve == 48:
			pistols += 1
	_check("one_arm_team_side", hands_ok == 6, "одна рука своей стороны (синие — Hand_L, красные — Hand_R) у %d из 6" % hands_ok)
	_check("start_pistol", pistols == 6, "пистолет 12 / 48 у %d из 6" % pistols)
	var p1arm := _doll(0).get_node_or_null("ArmAssist") as ArmAssist
	var botarm := _doll(1).get_node_or_null("ArmAssist") as ArmAssist
	_check("p1_arm_like_normal", p1arm != null and p1arm.show_hints and botarm != null and not botarm.show_hints and not _doll(0).external_input,
		"у игрока — обычная тяга руки с подсказкой (ЛКМ), у ботов без колец")
	var side_ok := true
	for d in ds:
		var x := (d as Doll).centre_of_mass().x
		side_ok = side_ok and ((x < -18.0) if SquadMatch.team_of(d) == 0 else (x > 18.0))
	_check("bases", side_ok, "синие на x < −18, красные на x > 18")
	var outlines := 0
	for d in ds:
		if (d as Node).has_meta(DollOutline.META):
			outlines += 1
	_check("team_outline", outlines == 6, "обводка цвета команды у %d из 6" % outlines)
	await _wait(1.0)   # щит появления (Tuning.SPAWN_GRACE_S) кончился
	var b0 := _doll(0)
	var b2 := _doll(2)
	var r1 := _doll(1)
	var hp0 := b2.hp
	b2.take_damage(20.0, b0, "Torso", b2.centre_of_mass(), Vector3.UP, "body")
	var dealt_friend := sm.bullet_hit(b2, b0, 9.0, "Torso", b2.centre_of_mass(), Vector3.UP, "pistol")
	_check("no_friendly", is_equal_approx(b2.hp, hp0) and dealt_friend == 0.0, "свой: удар и пуля — %.0f → %.0f HP" % [hp0, b2.hp])
	# пуля по чужому: урон есть, а эффектов удара (Match.on_hit → hit_fx, стоп-кадры, замедления) нет
	var fx0 := sm.hit_fx_count
	var hp1 := r1.hp
	var dealt := sm.bullet_hit(r1, b0, 9.0, "Torso", r1.centre_of_mass(), Vector3.UP, "pistol")
	_check("bullet_no_shake", r1.hp < hp1 - 5.0 and sm.hit_fx_count == fx0 and sm._time_effects.is_empty() and is_equal_approx(Engine.time_scale, 1.0),
		"пуля сняла %.1f HP; эффектов удара %d, замедлений %d, масштаб времени %.2f" % [dealt, sm.hit_fx_count - fx0, sm._time_effects.size(), Engine.time_scale])
	await _gun_rules()
	await _upgrade_rules()
	await _armor_supply_rules()
	await _score_rules()


## Оружие: темп, магазин, перезарядка сама и клавишей, без патронов — молчит.
func _gun_rules() -> void:
	var d := _doll(2)
	var g := SquadMatch.gun_of(d)
	var tgt := d.centre_of_mass() + Vector3(8.0, 0.5, 0.0)
	await _hold(d, tgt, 30)
	var frames: Array = []
	var fcb := func(_o: Vector3, _d: Vector3) -> void: frames.append(Engine.get_physics_frames())
	g.fired.connect(fcb)
	g.trigger = true
	await _hold(d, tgt, 60)   # 1 с: пистолет 0.28 с — 4 выстрела
	var in_1s := frames.size()
	var min_gap := 1 << 20
	for i in range(1, frames.size()):
		min_gap = mini(min_gap, int(frames[i]) - int(frames[i - 1]))
	_check("gun_rate", in_1s >= 3 and in_1s <= 5 and min_gap >= int(floor(0.28 * 60.0)), "за 1 с выстрелов %d, наименьший зазор %d тиков (интервал 0.28 с = 16.8)" % [in_1s, min_gap])
	_check("gun_mag_spent", g.mag == 12 - in_1s and g.shots == in_1s, "магазин %d после %d выстрелов" % [g.mag, in_1s])
	await _until(func() -> bool: return g.mag == 0, 5.0)
	var empty_at := Engine.get_physics_frames()
	await _until(func() -> bool: return g.reloading > 0.0, 0.2)   # перезарядка — со следующего тика после последнего патрона
	_check("gun_auto_reload", g.reloading > 0.0 and Engine.get_physics_frames() - empty_at <= 2,
		"магазин пуст — перезарядка началась сама через %d тик(а)" % (Engine.get_physics_frames() - empty_at))
	var r_start := Engine.get_physics_frames()
	g.trigger = false
	await _until(func() -> bool: return g.reloading <= 0.0, 3.0)
	var r_s := float(Engine.get_physics_frames() - r_start) / 60.0
	_check("gun_reload_time", g.mag == 12 and g.reserve == 36 and absf(r_s - 1.1) < 0.1, "перезарядка %.2f с (ждём 1.1), стало %d / %d" % [r_s, g.mag, g.reserve])
	g.trigger = true
	await _hold(d, tgt, 20)
	g.trigger = false
	var m_before := g.mag
	var started := g.reload()
	await _until(func() -> bool: return g.reloading <= 0.0, 3.0)
	_check("gun_manual_reload", started and m_before < 12 and g.mag == 12 and g.reserve == 36 - (12 - m_before),
		"клавишей: %d → 12, запас %d" % [m_before, g.reserve])
	g.mag = 0
	g.reserve = 0
	var s0 := g.shots
	g.trigger = true
	await _hold(d, tgt, 30)
	g.trigger = false
	_check("gun_out_of_ammo", g.out_of_ammo() and g.shots == s0, "патронов нет — спуск молчит, out_of_ammo")
	g.fired.disconnect(fcb)
	g.arm().clear_target_override()
	g.equip("pistol")


## Улучшения: очки за урон, ветка из трёх → второй уровень → усиления; всё переживает возврат.
func _upgrade_rules() -> void:
	var pi := 2
	var r1 := _doll(1)
	var p0 := int(sm.loadout(pi)["points"])
	var bank := 0.0
	while bank < Tuning.SQUAD_POINTS_DAMAGE and r1.alive:
		bank += sm.bullet_hit(r1, _doll(pi), 9.0, "Torso", r1.centre_of_mass(), Vector3.UP, "pistol")
		r1.grace_until = 0.0
	_check("points_for_damage", int(sm.loadout(pi)["points"]) >= p0 + 1, "очков %d → %d за %.0f урона" % [p0, int(sm.loadout(pi)["points"]), bank])
	sm.loadouts[pi]["points"] = 0
	sm.add_points(pi, 1)
	var of := sm.offers(pi)
	var ids := of.map(func(o: Dictionary) -> String: return String(o["id"]))
	_check("offers_branches", ids == ["smg", "sawnoff", "rifle"] and sm.can_upgrade(pi), "предложено %s" % str(ids))
	var chose := sm.choose(pi, 0)
	var g := _gun(pi)
	_check("upgrade_branch", chose and g.weapon == "smg" and g.mag == 30 and int(sm.loadout(pi)["points"]) == 0, "взят %s, магазин %d" % [g.weapon, g.mag])
	_check("upgrade_needs_points", not sm.choose(pi, 0) and _gun(pi).weapon == "smg", "второй уровень без очков — нельзя")
	sm.add_points(pi, int(Tuning.SQUAD_UPGRADE_COST["tier2"]))
	_check("upgrade_tier2", sm.offers(pi).size() == 1 and sm.choose(pi, 0) and _gun(pi).weapon == "mg", "второй уровень ветки: %s" % _gun(pi).weapon)
	sm.add_points(pi, int(Tuning.SQUAD_UPGRADE_COST["perk"]))
	var perk_ids: Array = sm.offers(pi).map(func(o: Dictionary) -> String: return String(o["id"]))
	sm.choose(pi, 0)
	var dmg := float(_gun(pi).def["damage"])
	_check("upgrade_perk", perk_ids == ["damage", "mag", "speed"] and is_equal_approx(dmg, 6.0 * 1.2), "усиления %s; урон пулемёта %.1f (6 × 1.2)" % [str(perk_ids), dmg])
	_doll(pi).knock_out(_doll(1), {"kind": "body"})
	await _wait(Tuning.SQUAD_RESPAWN_S + 0.3)
	var ng := _gun(pi)
	_check("upgrade_survives_respawn", ng != null and ng.weapon == "mg" and is_equal_approx(float(ng.def["damage"]), 6.0 * 1.2) and ng.mag == ng.mag_max,
		"после возврата: %s, урон %.1f, магазин %d / %d" % [ng.weapon if ng != null else "-", float(ng.def["damage"]) if ng != null else 0.0,
		ng.mag if ng != null else 0, ng.mag_max if ng != null else 0])


## Броня и ящики.
func _armor_supply_rules() -> void:
	await _wait(Tuning.SQUAD_SPAWN_SHIELD_S + 0.2)
	var r := _doll(3)
	r.grace_until = 0.0
	sm.add_armor(r, 50.0)
	var hp0 := r.hp
	r.take_damage(20.0, _doll(0), "Torso", r.centre_of_mass(), Vector3.UP, "body")
	_check("armor_halves", is_equal_approx(hp0 - r.hp, 10.0) and is_equal_approx(sm.armor_of(r), 40.0) and is_equal_approx(r.incoming_mult, 0.5),
		"урон 20 при броне 50: HP −%.1f, броня %.1f" % [hp0 - r.hp, sm.armor_of(r)])
	r.take_damage(100.0, _doll(0), "Torso", r.centre_of_mass(), Vector3.UP, "body")
	_check("armor_runs_out", (sm.armor_of(r) <= 0.0 and is_equal_approx(r.incoming_mult, 1.0)) or not r.alive, "броня кончилась — урон снова полный")
	var d := _doll(4)
	d.grace_until = 0.0
	var g := SquadMatch.gun_of(d)
	g.reserve = 0
	var c1 := sm.spawn_supply("ammo", d.centre_of_mass())
	await _wait(0.2)
	_check("supply_ammo", not is_instance_valid(c1) and g.reserve > 0 and int(sm.supplies_taken["ammo"]) == 1, "патроны: запас 0 → %d" % g.reserve)
	var c2 := sm.spawn_supply("ammo", d.centre_of_mass())
	g.reserve = g.reserve_max
	await _wait(0.2)
	_check("supply_not_needed", is_instance_valid(c2) and int(sm.supplies_taken["ammo"]) == 1, "полный запас — ящик остался")
	if is_instance_valid(c2):
		c2.queue_free()
	d.take_damage(50.0, _doll(1), "Torso", d.centre_of_mass(), Vector3.UP, "body")
	var hp1 := d.hp
	sm.spawn_supply("health", d.centre_of_mass())
	await _wait(0.2)
	_check("supply_health", d.hp > hp1 + 30.0, "жизни: %.0f → %.0f" % [hp1, d.hp])
	sm.spawn_supply("armor", d.centre_of_mass())
	await _wait(0.2)
	_check("supply_armor", is_equal_approx(sm.armor_of(d), 50.0), "броня: 0 → %.0f" % sm.armor_of(d))
	sm.supplies = true
	sm._supply_t = 0.0
	var n0 := sm.supplies_spawned
	await _wait(Tuning.SQUAD_SUPPLY_EVERY_S + 0.3)
	_check("supply_spawns", sm.supplies_spawned > n0, "за %.1f с появилось ящиков %d (сразу брать мог кто-то рядом с точкой)" % [Tuning.SQUAD_SUPPLY_EVERY_S + 0.3,
		sm.supplies_spawned - n0])
	sm.supplies = false
	for c in get_tree().get_nodes_in_group(SquadMatch.SUPPLY_GROUP):
		(c as Node).queue_free()


## Счёт, фраг, возврат, конец, заново.
func _score_rules() -> void:
	sm.restart()
	await _until(func() -> bool: return sm.play_state == "play", 6.0)
	_brains_off()
	_check("restart_resets", sm.score == [0, 0] and _gun(2).weapon == "pistol" and int(sm.loadout(2)["points"]) == 0 and sm.alive_dolls().size() == 6,
		"счёт %s, у синего 2 — %s, очков %d" % [str(sm.score), _gun(2).weapon, int(sm.loadout(2)["points"])])
	await _wait(1.0)
	var frag_seen: Array = []
	sm.frag.connect(func(k: Doll, v: Doll, t: int) -> void: frag_seen.append([k, v, t]))
	var b0 := _doll(0)
	var r1 := _doll(1)
	r1.knock_out(b0, {"kind": "body"})
	await get_tree().physics_frame
	_check("ko_scores", sm.score == [1, 0] and int(sm.tally[0]["kills"]) == 1 and int(sm.tally[1]["deaths"]) == 1 and frag_seen.size() == 1
		and frag_seen[0][0] == b0 and int(sm.loadout(0)["points"]) == Tuning.SQUAD_POINTS_PER_FRAG,
		"счёт %s, фраги P0 %d, очков у P0 %d" % [str(sm.score), int(sm.tally[0]["kills"]), int(sm.loadout(0)["points"])])
	await _wait(Tuning.SQUAD_RESPAWN_S + 0.2)
	var nr1 := _doll(1)
	_check("respawn_at_base", nr1 != null and nr1 != r1 and nr1.alive and nr1.centre_of_mass().x > 18.0 and not nr1.can_take_damage(),
		"новая кукла P1 жива на x = %.1f, щит возрождения" % (nr1.centre_of_mass().x if nr1 != null else 0.0))
	_check("respawn_keeps_parts", nr1 != null and nr1.team == "squad_1" and nr1.has_meta(DollOutline.META) and nr1.get_node_or_null("SquadBrain") != null
		and _arms(nr1) == ["Hand_R"] and SquadMatch.gun_of(nr1) != null and SquadMatch.gun_of(nr1).mag == 12
		and nr1.get_children().filter(func(c: Node) -> bool: return c is SquadGun and not c.is_queued_for_deletion()).size() == 1,
		"команда, обводка, мозг, одна рука Hand_R, одно оружие с полным магазином")
	_doll(4).knock_out(null, {"kind": "self"})
	await get_tree().physics_frame
	_check("self_ko_scores", sm.score == [1, 1] and frag_seen.size() == 2 and frag_seen[1][0] == null, "счёт %s" % str(sm.score))
	sm.score_to_win = 3
	_doll(3).knock_out(_doll(0), {"kind": "body"})
	await get_tree().physics_frame
	_doll(5).knock_out(_doll(2), {"kind": "body"})
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("win_by_score", over_count == 1 and int(over_results.get("winner_team", -1)) == 0 and sm.play_state == "over",
		"итогов %d, победила команда %d, счёт %s" % [over_count, int(over_results.get("winner_team", -1)), str(sm.score)])
	sm.score_to_win = Tuning.SQUAD_SCORE_TO_WIN
	sm.restart()
	await _until(func() -> bool: return sm.play_state == "play", 6.0)
	_brains_off()
	await _wait(1.0)
	_doll(0).knock_out(_doll(1), {"kind": "body"})
	sm.time_limit_s = sm.fight_time + 0.5
	await _until(func() -> bool: return over_count == 2, 3.0)
	_check("timeout_leader", over_count == 2 and int(over_results.get("winner_team", -1)) == 1, "0 : 1 к концу времени — победа красных")
	sm.time_limit_s = Tuning.SQUAD_TIME_LIMIT_S
	await _unload()


## Кисти рук куклы (ArmAssist.part_name), по алфавиту.
func _arms(d: Doll) -> Array:
	var parts := []
	for c in d.get_children():
		if c is ArmAssist and not c.is_queued_for_deletion():
			parts.append((c as ArmAssist).part_name)
	parts.sort()
	return parts


# ------------------------------------------------------------------ матч ботов

func _bots(max_s: float, level: int, trace: bool) -> void:
	print("--- bots (level %d)" % level)
	await _load(true, level, 3.0, true)
	var acc := {"friendly": 0.0, "all": 0.0, "bullet": 0.0, "bullet_hits": 0, "reloads": 0, "upgrades": 0}
	sm.hit.connect(func(v: Doll, a: Node, dmg: float, _k: String, _p: Vector3) -> void:
		acc["all"] = float(acc["all"]) + dmg
		if a is Doll and SquadMatch.team_of(a) == SquadMatch.team_of(v) and a != v:
			acc["friendly"] = float(acc["friendly"]) + dmg)
	sm.bullet_landed.connect(func(_v: Doll, _s: Doll, dmg: float, _p: Vector3) -> void:
		acc["bullet"] = float(acc["bullet"]) + dmg
		acc["bullet_hits"] = int(acc["bullet_hits"]) + 1)
	sm.upgraded.connect(func(_pi: int, _o: Dictionary) -> void: acc["upgrades"] = int(acc["upgrades"]) + 1)
	var ff := {"t": -1.0}
	sm.frag.connect(func(_k: Doll, _v: Doll, _t: int) -> void:
		if float(ff["t"]) < 0.0:
			ff["t"] = sm.fight_time)
	var fx0 := sm.hit_fx_count
	var shots: Dictionary = {}
	var last_shots: Dictionary = {}
	var seen_reload: Dictionary = {}
	var melee_no_ammo := 0
	var last_pos: Dictionary = {}
	var stuck_max := 0.0
	var out_of_bounds := 0
	var b: AABB = pg.arena.call("bounds")
	var props0: int = (pg.arena.call("breakables") as Array).size()
	var t0 := Time.get_ticks_usec()
	var frames := 0
	var trace_t := 0.0
	while over_count == 0 and sm.fight_time < max_s:
		await get_tree().physics_frame
		frames += 1
		for d in sm.dolls():
			var dd := d as Doll
			var g := SquadMatch.gun_of(dd)
			if g != null:
				var id := g.get_instance_id()
				shots[dd.player_index] = int(shots.get(dd.player_index, 0)) + maxi(g.shots - int(last_shots.get(id, 0)), 0)
				last_shots[id] = g.shots
				if g.reloading > 0.0 and not seen_reload.get(id, false):
					acc["reloads"] = int(acc["reloads"]) + 1
				seen_reload[id] = g.reloading > 0.0
				var br := dd.get_node_or_null("SquadBrain") as SquadBrain
				if br != null and br.state == "melee" and g.out_of_ammo():
					melee_no_ammo += 1
			if not dd.alive:
				last_pos.erase(dd.player_index)
				continue
			var c := dd.centre_of_mass()
			if c.x < b.position.x - 0.5 or c.x > b.end.x + 0.5 or c.y < b.position.y - 0.5 or c.y > b.end.y + 0.5:
				out_of_bounds += 1
			var lp: Array = last_pos.get(dd.player_index, [])
			if lp.is_empty() or (lp[0] as Vector3).distance_to(c) > 1.5:
				last_pos[dd.player_index] = [c, sm.fight_time]
			else:
				stuck_max = maxf(stuck_max, sm.fight_time - float(lp[1]))
		if trace and sm.fight_time - trace_t >= 10.0:
			trace_t = sm.fight_time
			var row := []
			for d in sm.dolls():
				var br := (d as Node).get_node_or_null("SquadBrain") as SquadBrain
				var g := SquadMatch.gun_of(d)
				row.append("%d:%s/%s %d|%d(%.0f,%.0f)%s" % [(d as Doll).player_index, br.state if br != null else "-", g.weapon if g != null else "-",
					g.mag if g != null else 0, g.reserve if g != null else 0, (d as Doll).centre_of_mass().x, (d as Doll).centre_of_mass().y,
					"" if (d as Doll).alive else "†"])
			print("  t=%5.1f score=%s  %s" % [sm.fight_time, str(sm.score), " ".join(row)])
	var wall_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var weapons := {}
	for pi in sm.loadouts:
		weapons[pi] = {"weapon": sm.loadouts[pi]["weapon"], "perks": sm.loadouts[pi]["perks"]}
	var kills := [0, 0]
	for pi in sm.tally:
		kills[int(pi) % 2] += int(sm.tally[pi]["kills"])
	var shooters := 0
	for pi in shots:
		if int(shots[pi]) > 20:
			shooters += 1
	var tier_max := 0
	for pi in sm.loadouts:
		tier_max = maxi(tier_max, int(Tuning.SQUAD_WEAPONS[String(sm.loadouts[pi]["weapon"])]["tier"]))
	var hitfx := sm.hit_fx_count - fx0
	info["bots"] = {"level": level, "fight_s": snappedf(sm.fight_time, 0.1), "score": sm.score.duplicate(), "frags": sm.frags.size(),
		"first_frag_s": snappedf(float(ff["t"]), 0.1), "kills_by_team": kills, "shots": shots, "bullet_hits": acc["bullet_hits"],
		"bullet_damage_share": snappedf(float(acc["bullet"]) / maxf(float(acc["all"]), 1.0), 0.01), "hit_fx_melee": hitfx,
		"reloads": acc["reloads"], "upgrades": acc["upgrades"], "weapons_end": weapons, "supplies_spawned": sm.supplies_spawned,
		"supplies_taken": sm.supplies_taken.duplicate(), "melee_no_ammo_ticks": melee_no_ammo, "stuck_max_s": snappedf(stuck_max, 0.1),
		"ms_per_physics_frame": snappedf(wall_ms / maxf(frames, 1), 0.01), "tally": sm.tally.duplicate(true),
		"props_broken": props0 - (pg.arena.call("breakables") as Array).size(), "props": props0}
	print("  " + JSON.stringify(info["bots"]))
	var taken := 0
	for k in sm.supplies_taken:
		taken += int(sm.supplies_taken[k])
	_check("bots_match_ends", over_count == 1, "матч кончился: %s за %.0f с, счёт %s" % [str(over_count == 1), sm.fight_time, str(sm.score)])
	_check("bots_all_shoot", shooters == 6, "стреляли (> 20 выстрелов) %d из 6" % shooters)
	_check("bots_bullets_hit", int(acc["bullet_hits"]) > 100, "попаданий пулями %d (%.0f HP)" % [int(acc["bullet_hits"]), float(acc["bullet"])])
	_check("bots_no_friendly", float(acc["friendly"]) <= 0.01, "урон по своим %.1f HP" % float(acc["friendly"]))
	_check("bots_bullets_no_fx", hitfx < int(acc["bullet_hits"]) / 5, "эффектов удара %d на %d попаданий пулями (эффекты — только от ударов телом)" % [hitfx, int(acc["bullet_hits"])])
	_check("bots_both_frag", kills[0] > 0 and kills[1] > 0, "фраги синих / красных %s" % str(kills))
	_check("bots_first_frag", float(ff["t"]) >= 0.0 and float(ff["t"]) < 60.0, "первый фраг на %.1f с" % float(ff["t"]))
	_check("bots_reload", int(acc["reloads"]) >= 6, "перезарядок %d" % int(acc["reloads"]))
	_check("bots_upgrade", int(acc["upgrades"]) >= 3 and tier_max >= 1, "улучшений %d, высший уровень оружия %d" % [int(acc["upgrades"]), tier_max])
	_check("bots_supplies", taken >= 3, "взято ящиков %d из %d появившихся" % [taken, sm.supplies_spawned])
	_check("bots_not_stuck", stuck_max < 25.0, "дольше всего на месте (в радиусе 1.5 м) %.1f с" % stuck_max)
	_check("bots_in_bounds", out_of_bounds == 0, "тиков вне границ карты %d" % out_of_bounds)
	await _unload()
