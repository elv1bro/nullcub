## Проба «Стычки 3 на 3» (docs/plan-demo/SQUAD.md) на настоящей площадке scenes/playground_squad.tscn (Полигон, шесть бойцов,
## SquadMatch, SquadGun, SquadHud).
##   aim (боты молчат): рука с оружием своей команды (у синих — кисть Hand_L, у красных — Hand_R) наводит ствол на точку в 8 м в
##     пяти направлениях к стороне соперника (±60°) — угол ствола к цели, медиана и худший; у команд одинаково;
##   rules (P1 — человек без ввода, боты молчат, ящики выключены): шесть бойцов и команды; классы (P1 — штурмовик, боты — по
##     SQUAD_BOT_CLASSES), у стрелков одна рука своей стороны и пистолет 12 / 48, у громилы — сковорода в той же руке, запас HP и броня
##     класса; свои не ранят ни ударом, ни пулей; пуля и удар телом — без эффектов удара, стоп-кадров и замедлений (камеру трясёт
##     только сильный удар с человеком); пули — трассеры; темп, магазин, перезарядка сама и клавишей, без патронов — молчит; опыт за
##     урон и фраг, уровни открывают оружие класса (автомат, пулемёт, меч…) и усиления, переживают возврат; смена класса — на отсчёте
##     сразу, в бою — с возрождения; выпад громилы и пауза; броня; ящики; нокаут — очко и фраг, возврат; конец; заново — сброс;
##   night: ночная карта (playground_squad_night.tscn) — окружение тёмное, луна слабая, фонари есть, фон затемнён, звёзды и луна на небе,
##     у обеих карт нет глубины резкости; 20 с боя ботов ночью — пули летят и попадают;
##   bots (P1 тоже бот): матч ботов до score очков — все стреляют (громилы — бьют), пули попадают, урона по своим нет, фраги у обеих
##     команд, первый фраг не поздно, перезарядки, новые уровни, рукопашная и ящики были, ни одного тика замедления времени и ни
##     одной тряски от ударов (людей нет), никто не застрял надолго, все в границах карты; темп и счёт — в info.
## Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/squad_probe.tscn -- "only=aim|rules|night|bots|aim+rules…,max_s=900,level=2,score=20,trace=1,out=<json>"
##   (score — до скольких очков матч ботов: по умолчанию 20 — быстрее; в игре 100)
## → JSON между === SQUAD PROBE === и === OK / FAIL ===, exit 0/1. errors_script — SCRIPT ERROR за прогон (Logger).
extends Node

const SCENE := "res://scenes/playground_squad.tscn"
const SCENE_NIGHT := "res://scenes/playground_squad_night.tscn"
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
	var out := {"only": "", "max_s": "900", "level": "2", "trace": "0", "out": "", "score": "20"}
	for a in OS.get_cmdline_user_args():
		for part in String(a).split(","):
			var kv := part.split("=")
			if kv.size() == 2 and out.has(kv[0]):
				out[kv[0]] = kv[1]
	return out


## only — раздел или несколько через «+» (only=aim+rules); пусто — все.
func _want(a: Dictionary, section: String) -> bool:
	return String(a["only"]) == "" or section in String(a["only"]).split("+")


func _ready() -> void:
	OS.add_logger(errs)
	print("=== SQUAD PROBE ===")
	var a := _args()
	if _want(a, "aim"):
		await _aim()
	if _want(a, "rules"):
		await _rules()
	if _want(a, "night"):
		await _night()
	if _want(a, "bots"):
		await _bots(float(a["max_s"]), int(a["level"]), String(a["trace"]) == "1", int(a["score"]))
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

func _load(p1_bot: bool, level := 2, countdown := 0.3, supplies := false, scene := SCENE) -> void:
	await _unload()
	Engine.time_scale = 1.0
	pg = (load(scene) as PackedScene).instantiate() as SquadPlayground
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
	var armed_ok := 0
	var classes := []
	for d in ds:
		var want := "Hand_L" if SquadMatch.team_of(d) == 0 else "Hand_R"
		if _arms(d) == [want]:
			hands_ok += 1
		var cls := String(sm.loadout((d as Doll).player_index)["class"])
		classes.append("%d:%s" % [(d as Doll).player_index, cls])
		var g := SquadMatch.gun_of(d)
		var ml := SquadMatch.melee_of(d)
		if cls == "brawler":
			if g.weapon == "" and ml.weapon_id == "pan" and is_instance_valid(ml.weapon) and ml.weapon.is_held():
				armed_ok += 1
		elif g != null and g.weapon == "pistol" and g.mag == 12 and g.reserve == 48 and ml.weapon_id == "":
			armed_ok += 1
	classes.sort()
	_check("classes", String(sm.loadout(0)["class"]) == "assault" and String(sm.loadout(5)["class"]) == "brawler"
		and String(sm.loadout(2)["class"]) == "sniper" and String(sm.loadout(3)["class"]) == "sniper", "классы %s" % str(classes))
	_check("one_arm_team_side", hands_ok == 6, "одна рука своей стороны (синие — Hand_L, красные — Hand_R) у %d из 6" % hands_ok)
	_check("start_kit", armed_ok == 6, "стрелки — пистолет 12 / 48, громилы — сковорода в руке: %d из 6" % armed_ok)
	var br := _doll(5)
	var hp_k := Tuning.DRIVE_MAX_HP / Tuning.MAX_HP if Drive.on else 1.0
	_check("class_stats", is_equal_approx(br.max_hp, 140.0 * hp_k) and is_equal_approx(sm.armor_of(br), 30.0) and is_equal_approx(_doll(2).max_hp, 90.0 * hp_k),
		"громила %.0f HP и броня %.0f, снайпер %.0f HP" % [br.max_hp, sm.armor_of(br), _doll(2).max_hp])
	var p1arm := _doll(0).get_node_or_null("ArmAssist") as ArmAssist
	var botarm := _doll(1).get_node_or_null("ArmAssist") as ArmAssist
	_check("p1_arm_follows_mouse", p1arm != null and p1arm.show_hints and p1arm.arm_active and botarm != null and not botarm.show_hints
		and not _doll(0).external_input, "рука игрока тянется к курсору без кнопок (кольцо-прицел), у ботов без колец")
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
	# удар телом / оружием: как пуля — без эффектов удара и замедлений; камеру трясёт только сильный удар с человеком
	sm.feel_enabled = true
	var sh0 := sm.melee_shakes
	sm.on_hit(r1, _doll(2), 25.0, "body", r1.centre_of_mass(), 0, false, "", 6.0)
	var bot_shake := sm.melee_shakes - sh0
	sm.on_hit(r1, b0, 6.0, "body", r1.centre_of_mass(), 0, false, "", 3.0)
	var weak_shake := sm.melee_shakes - sh0
	sm.on_hit(r1, b0, 25.0, "body", r1.centre_of_mass(), 0, false, "", 6.0)
	var human_shake := sm.melee_shakes - sh0
	_check("melee_no_shake", sm.hit_fx_count == fx0 and sm._time_effects.is_empty() and is_equal_approx(Engine.time_scale, 1.0)
		and bot_shake == 0 and weak_shake == 0 and human_shake == 1,
		"удары телом: эффектов удара %d, замедлений %d; тряска — бот×бот %d, слабый с игроком %d, сильный с игроком %d" % [sm.hit_fx_count - fx0,
		sm._time_effects.size(), bot_shake, weak_shake, human_shake])
	sm.feel_enabled = false
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
	# пули — шарики в полёте: есть сразу после выстрела, за тик проходят speed / 60 м, дальше range гаснут
	var shot0 := g.shots
	await _until(func() -> bool: return g.shots > shot0, 1.0)
	var flying := g.balls_in_flight()
	var p0: Vector3 = (g.balls[0]["pos"] as Vector3) if flying > 0 else Vector3.ZERO
	await get_tree().physics_frame
	var step := ((g.balls[0]["pos"] as Vector3).distance_to(p0)) if g.balls_in_flight() > 0 else 0.0
	var node: MeshInstance3D = g.balls[0]["node"] if g.balls_in_flight() > 0 else null
	_check("bullets_are_tracers", flying >= 1 and absf(step - 40.0 / 60.0) < 0.05 and node != null and node.mesh is QuadMesh
		and node.material_override is ShaderMaterial, "в полёте %d, трассер за тик прошёл %.2f м (ждём %.2f — 40 м/с), квад с шейдером трассера" % [flying,
		step, 40.0 / 60.0])
	await _until(func() -> bool: return g.mag == 0, 5.0)
	var empty_at := Engine.get_physics_frames()
	await _until(func() -> bool: return g.reloading > 0.0, 0.2)   # перезарядка — со следующего тика после последнего патрона
	_check("gun_auto_reload", g.reloading > 0.0 and Engine.get_physics_frames() - empty_at <= 2,
		"магазин пуст — перезарядка началась сама через %d тик(а)" % (Engine.get_physics_frames() - empty_at))
	var r_start := Engine.get_physics_frames()
	g.trigger = false
	await _until(func() -> bool: return g.reloading <= 0.0, 3.0)
	var r_s := float(Engine.get_physics_frames() - r_start) / 60.0
	_check("bullets_fade", g.balls_in_flight() == 0, "через %.1f с после последнего выстрела шариков в полёте нет (18 м / 40 м/с = 0.45 с)" % r_s)
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


## Опыт и классы: опыт за урон и фраг, уровни открывают оружие и усиления класса, всё переживает возврат; смена класса; выпад громилы.
func _upgrade_rules() -> void:
	var pi := 0   # штурмовик
	var lv_seen: Array = []
	sm.leveled.connect(func(p: int, lv: int, u: Dictionary) -> void:
		if p == pi:
			lv_seen.append([lv, u]))
	var r1 := _doll(1)
	r1.grace_until = 0.0
	var xp0 := float(sm.loadout(pi)["xp"])
	var dealt := sm.bullet_hit(r1, _doll(pi), 9.0, "Torso", r1.centre_of_mass(), Vector3.UP, "pistol")
	_check("xp_for_damage", is_equal_approx(float(sm.loadout(pi)["xp"]) - xp0, dealt * Tuning.SQUAD_XP_PER_DAMAGE), "опыт +%.1f за %.1f урона" % [
		float(sm.loadout(pi)["xp"]) - xp0, dealt])
	sm.add_xp(pi, float(Tuning.SQUAD_XP_LEVELS[1]))
	var g := _gun(pi)
	_check("level2_smg", int(sm.loadout(pi)["level"]) == 2 and g.weapon == "smg" and g.mag == 30 and lv_seen.size() == 1
		and String((lv_seen[0][1] as Dictionary).get("weapon", "")) == "smg", "уровень 2: %s, магазин %d, сигнал leveled %s" % [g.weapon, g.mag, str(lv_seen)])
	sm.add_xp(pi, float(Tuning.SQUAD_XP_LEVELS[4]))
	g = _gun(pi)
	_check("level5_mg_perks", int(sm.loadout(pi)["level"]) == 5 and g.weapon == "mg" and g.mag_max == int(round(70 * 1.5)) and lv_seen.size() == 4,
		"уровень 5: %s, магазин %d (70 × 1.5 — усиление «магазин»), уровней открыто %d" % [g.weapon, g.mag_max, lv_seen.size()])
	# громила: меч на 2-м уровне, броня на 3-м
	var b := 5
	var br := _doll(b)
	var a0 := sm.armor_of(br)
	sm.add_xp(b, float(Tuning.SQUAD_XP_LEVELS[2]))
	var ml := SquadMatch.melee_of(br)
	_check("brawler_levels", ml.weapon_id == "sword" and is_instance_valid(ml.weapon) and ml.weapon.is_held() and sm.armor_of(br) > a0 + 25.0,
		"громила уровень %d: %s в руке, броня %.0f → %.0f" % [int(sm.loadout(b)["level"]), ml.weapon_id, a0, sm.armor_of(br)])
	# выпад: торс разгоняется к точке, вторым — нельзя до паузы
	br.grace_until = 0.0
	var v0 := br.torso().linear_velocity
	var target := br.centre_of_mass() + Vector3(-5.0, 0.0, 0.0)
	var l1 := ml.lunge(target)
	var dv := (br.torso().linear_velocity - v0).x
	var l2 := ml.lunge(target)
	_check("brawler_lunge", l1 and not l2 and dv < -Tuning.SQUAD_LUNGE_DV * 0.9, "выпад: торс Δv %.1f м/с к цели, второй сразу — %s" % [dv, str(l2)])
	# опыт и оружие переживают возврат
	_doll(pi).knock_out(_doll(1), {"kind": "body"})
	await _wait(Tuning.SQUAD_RESPAWN_S + 0.3)
	var ng := _gun(pi)
	_check("level_survives_respawn", ng != null and ng.weapon == "mg" and ng.mag == ng.mag_max and int(sm.loadout(pi)["level"]) == 5,
		"после возврата: уровень %d, %s %d / %d" % [int(sm.loadout(pi)["level"]), ng.weapon if ng != null else "-", ng.mag if ng != null else 0,
		ng.mag_max if ng != null else 0])
	# смена класса в бою — с возрождения: штурмовик → громила
	sm.set_class(pi, "brawler")
	_check("class_pending", String(sm.loadout(pi)["class"]) == "assault" and String(sm.loadout(pi)["next_class"]) == "brawler" and _gun(pi).weapon == "mg",
		"в бою: класс пока штурмовик, следующий — громила")
	await _wait(Tuning.SQUAD_SPAWN_SHIELD_S + 0.2)
	_doll(pi).knock_out(_doll(1), {"kind": "body"})
	await _wait(Tuning.SQUAD_RESPAWN_S + 0.4)
	var nd := _doll(pi)
	var nml := SquadMatch.melee_of(nd)
	var want_melee := String(SquadMatch.kit_of("brawler", int(sm.loadout(pi)["level"]))["melee"])
	_check("class_on_respawn", String(sm.loadout(pi)["class"]) == "brawler" and _gun(pi).weapon == "" and nml.weapon_id == want_melee
		and is_instance_valid(nml.weapon) and nml.weapon.is_held(), "после возврата — громила %d уровня: %s в руке" % [int(sm.loadout(pi)["level"]), nml.weapon_id])
	sm.set_class(pi, "assault")


## Броня и ящики.
func _armor_supply_rules() -> void:
	await _wait(Tuning.SQUAD_SPAWN_SHIELD_S + 0.2)
	var r := _doll(1)   # штурмовик: своей брони у класса нет
	r.grace_until = 0.0
	sm.add_armor(r, -1000.0)
	sm.add_armor(r, 50.0)
	var hp0 := r.hp
	r.take_damage(20.0, _doll(0), "Torso", r.centre_of_mass(), Vector3.UP, "body")
	_check("armor_halves", is_equal_approx(hp0 - r.hp, 10.0) and is_equal_approx(sm.armor_of(r), 40.0) and is_equal_approx(r.incoming_mult, 0.5),
		"урон 20 при броне 50: HP −%.1f, броня %.1f" % [hp0 - r.hp, sm.armor_of(r)])
	r.take_damage(100.0, _doll(0), "Torso", r.centre_of_mass(), Vector3.UP, "body")
	_check("armor_runs_out", (sm.armor_of(r) <= 0.0 and is_equal_approx(r.incoming_mult, 1.0)) or not r.alive, "броня кончилась — урон снова полный")
	if r.alive:   # раненый сосед по базе (P2 стоит рядом с P4) взял бы ящики ниже раньше P4 — снова полный запас
		r.hp = r.max_hp
		sm.add_armor(r, Tuning.SQUAD_ARMOR_MAX)
	var d := _doll(3)   # красный снайпер: ствол есть; броню (на всякий случай) — в ноль
	d.grace_until = 0.0
	sm.add_armor(d, -1000.0)
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
	d.take_damage(50.0, _doll(0), "Torso", d.centre_of_mass(), Vector3.UP, "body")   # синий по красному (свои не ранят)
	var hp1 := d.hp
	var ch := sm.spawn_supply("health", d.centre_of_mass())
	var taker := [-1]
	ch.taken.connect(func(_c: SupplyCrate, who: Doll) -> void: taker[0] = who.player_index)
	await _wait(0.2)
	_check("supply_health", d.hp > hp1 + 30.0, "жизни: %.0f → %.0f (ящик взял P%d)" % [hp1, d.hp, taker[0] + 1])
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
	_check("restart_resets", sm.score == [0, 0] and _gun(0).weapon == "pistol" and int(sm.loadout(0)["level"]) == 1
		and float(sm.loadout(0)["xp"]) == 0.0 and String(sm.loadout(0)["class"]) == "assault" and sm.alive_dolls().size() == 6,
		"счёт %s, P1: %s, уровень %d, опыт %.0f" % [str(sm.score), _gun(0).weapon, int(sm.loadout(0)["level"]), float(sm.loadout(0)["xp"])])
	sm.set_class(0, "sniper")
	_check("class_now_on_countdown_or_play", String(sm.loadout(0)["next_class"]) == "sniper", "выбор класса записан")
	sm.set_class(0, "assault")
	await _wait(1.0)
	var frag_seen: Array = []
	sm.frag.connect(func(k: Doll, v: Doll, t: int) -> void: frag_seen.append([k, v, t]))
	var b0 := _doll(0)
	var r1 := _doll(1)
	r1.knock_out(b0, {"kind": "body"})
	await get_tree().physics_frame
	_check("ko_scores", sm.score == [1, 0] and int(sm.tally[0]["kills"]) == 1 and int(sm.tally[1]["deaths"]) == 1 and frag_seen.size() == 1
		and frag_seen[0][0] == b0 and is_equal_approx(float(sm.loadout(0)["xp"]), Tuning.SQUAD_XP_PER_FRAG),
		"счёт %s, фраги P0 %d, опыт P0 %.0f" % [str(sm.score), int(sm.tally[0]["kills"]), float(sm.loadout(0)["xp"])])
	await _wait(Tuning.SQUAD_RESPAWN_S + 0.2)
	var nr1 := _doll(1)
	_check("respawn_at_base", nr1 != null and nr1 != r1 and nr1.alive and nr1.centre_of_mass().x > 18.0 and not nr1.can_take_damage(),
		"новая кукла P1 жива на x = %.1f, щит возрождения" % (nr1.centre_of_mass().x if nr1 != null else 0.0))
	_check("respawn_keeps_parts", nr1 != null and nr1.team == "squad_1" and nr1.has_meta(DollOutline.META) and nr1.get_node_or_null("SquadBrain") != null
		and _arms(nr1) == ["Hand_R"] and SquadMatch.gun_of(nr1) != null and SquadMatch.gun_of(nr1).mag == 12
		and nr1.get_children().filter(func(c: Node) -> bool: return c is SquadGun and not c.is_queued_for_deletion()).size() == 1
		and nr1.get_children().filter(func(c: Node) -> bool: return c is SquadMelee and not c.is_queued_for_deletion()).size() == 1,
		"команда, обводка, мозг, одна рука Hand_R, одно оружие с полным магазином, один узел рукопашной")
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


# ------------------------------------------------------------------ ночь

func _night() -> void:
	print("--- night")
	await _load(true, 2, 0.3, true, SCENE_NIGHT)
	var arena := pg.arena
	var we := arena.get_node("Environment") as WorldEnvironment
	var env := we.environment
	var sun := arena.get_node("Sun") as DirectionalLight3D
	var lamps := arena.get_node_or_null("Lamps")
	var lamp_n := lamps.get_child_count() if lamps != null else 0
	_check("night_dark", bool(arena.get("night")) and env.ambient_light_energy < 1.0 and sun.light_energy < 1.0 and sun.light_color.b > sun.light_color.r
		and env.glow_enabled, "ночь: окружающий свет %.2f, луна %.2f (голубая), свечение вкл" % [env.ambient_light_energy, sun.light_energy])
	_check("night_lamps", lamp_n >= 10, "фонарей %d (цвета команд у баз, тёплые у башни)" % lamp_n)
	var sky := arena.get_node("Parallax/Layer4Sky") as MeshInstance3D
	var tint := (sky.material_override as StandardMaterial3D).albedo_color
	_check("night_sky", tint.v < 0.35 and sky.get_node_or_null("Stars") != null and sky.get_node_or_null("Moon") != null,
		"фон затемнён (яркость множителя %.2f), звёзды и луна на небе" % tint.v)
	var cam_night := (we.camera_attributes as CameraAttributesPractical)
	var day := (load("res://scenes/arena/proving_ground.tscn") as PackedScene).instantiate()
	var cam_day := ((day.get_node("Environment") as WorldEnvironment).camera_attributes as CameraAttributesPractical)
	var day_fog := (day.get_node("Environment") as WorldEnvironment).environment.fog_density
	day.free()
	_check("no_dof", cam_night != null and not cam_night.dof_blur_far_enabled and cam_day != null and not cam_day.dof_blur_far_enabled
		and day_fog < 0.004, "у обеих карт нет глубины резкости, дымка днём %.4f (у Руин 0.004)" % day_fog)
	var hits := {"n": 0}
	sm.bullet_landed.connect(func(_v: Doll, _s: Doll, _d: float, _p: Vector3) -> void: hits["n"] = int(hits["n"]) + 1)
	var shots0 := 0
	for d in sm.dolls():
		shots0 += SquadMatch.gun_of(d).shots
	await _wait(20.0)   # стреляют 4 из 6 (громилы — без ствола), на пистолетах: 25–80 выстрелов за прогон
	var shots := 0
	for d in sm.dolls():
		var g := SquadMatch.gun_of(d)
		if g != null:
			shots += g.shots
	_check("night_fight", shots - shots0 > 12 and int(hits["n"]) > 5, "20 с ночью: выстрелов %d, попаданий %d" % [shots - shots0, int(hits["n"])])
	await _unload()


# ------------------------------------------------------------------ матч ботов

func _bots(max_s: float, level: int, trace: bool, score_to_win: int = 20) -> void:
	print("--- bots (level %d, до %d)" % [level, score_to_win])
	await _load(true, level, 3.0, true)
	sm.score_to_win = score_to_win
	var slow_ticks := {"n": 0}
	var acc := {"friendly": 0.0, "all": 0.0, "bullet": 0.0, "bullet_hits": 0, "reloads": 0, "upgrades": 0}
	sm.hit.connect(func(v: Doll, a: Node, dmg: float, _k: String, _p: Vector3) -> void:
		acc["all"] = float(acc["all"]) + dmg
		if a is Doll and SquadMatch.team_of(a) == SquadMatch.team_of(v) and a != v:
			acc["friendly"] = float(acc["friendly"]) + dmg)
	sm.bullet_landed.connect(func(_v: Doll, _s: Doll, dmg: float, _p: Vector3) -> void:
		acc["bullet"] = float(acc["bullet"]) + dmg
		acc["bullet_hits"] = int(acc["bullet_hits"]) + 1)
	sm.leveled.connect(func(_pi: int, _lv: int, _u: Dictionary) -> void: acc["upgrades"] = int(acc["upgrades"]) + 1)
	var lunges0 := 0
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
	var stuck_who := ""
	var out_of_bounds := 0
	var b: AABB = pg.arena.call("bounds")
	var props0: int = (pg.arena.call("breakables") as Array).size()
	var t0 := Time.get_ticks_usec()
	var frames := 0
	var trace_t := 0.0
	while over_count == 0 and sm.fight_time < max_s:
		await get_tree().physics_frame
		frames += 1
		if Engine.time_scale < 0.99:
			slow_ticks["n"] = int(slow_ticks["n"]) + 1
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
			elif trace and sm.fight_time - float(lp[1]) > 10.0 and int(sm.fight_time * 60.0) % 120 == 0:
				var sb2 := dd.get_node_or_null("SquadBrain") as SquadBrain
				var ml2 := SquadMatch.melee_of(dd)
				var touching := []
				for pn in ["Torso", "Head", "Hand_L", "Hand_R"]:
					var pb := dd.parts.get(pn) as RigidBody3D
					if pb != null and pb.contact_monitor:
						for cb in pb.get_colliding_bodies():
							touching.append("%s>%s" % [pn, cb.name])
				var wpos := ml2.weapon.global_position if ml2 != null and is_instance_valid(ml2.weapon) else Vector3.ZERO
				print("    STUCK P%d %.0f с: %s, стан %s, ввод %s, v %.2f, оружие %s в %s, касания %s, цель %s" % [dd.player_index,
					sm.fight_time - float(lp[1]), sb2.state if sb2 != null else "-", str(dd.is_stunned()), str(dd.input_vec.snapped(Vector2(0.01, 0.01))),
					dd.torso().linear_velocity.length(), ml2.weapon_id if ml2 != null else "-", str(wpos.snapped(Vector3(0.1, 0.1, 0.1))), str(touching),
					(sb2.target.name if sb2 != null and sb2.target != null and is_instance_valid(sb2.target) else "-")])
			if not lp.is_empty() and sm.fight_time - float(lp[1]) > stuck_max:
				stuck_max = sm.fight_time - float(lp[1])
				var sb := dd.get_node_or_null("SquadBrain") as SquadBrain
				stuck_who = "P%d %s в (%.1f, %.1f), состояние %s" % [dd.player_index, String(sm.loadout(dd.player_index)["class"]), c.x, c.y,
					sb.state if sb != null else "-"]
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
		weapons[pi] = {"class": sm.loadouts[pi]["class"], "level": sm.loadouts[pi]["level"], "kit": sm.kit(int(pi))}
	var kills := [0, 0]
	for pi in sm.tally:
		kills[int(pi) % 2] += int(sm.tally[pi]["kills"])
	var shooters := 0
	var gunners := 0
	for pi in sm.loadouts:
		if String(sm.loadouts[pi]["class"]) == "brawler":
			continue
		gunners += 1
		if int(shots.get(pi, 0)) > 10:
			shooters += 1
	var level_max := 0
	var lunges := 0
	for pi in sm.loadouts:
		level_max = maxi(level_max, int(sm.loadouts[pi]["level"]))
	for d in sm.dolls():
		var mm := SquadMatch.melee_of(d)
		if mm != null:
			lunges += mm.lunges
	var hitfx := sm.hit_fx_count - fx0
	info["bots"] = {"level": level, "fight_s": snappedf(sm.fight_time, 0.1), "score": sm.score.duplicate(), "frags": sm.frags.size(),
		"first_frag_s": snappedf(float(ff["t"]), 0.1), "kills_by_team": kills, "shots": shots, "bullet_hits": acc["bullet_hits"],
		"bullet_damage_share": snappedf(float(acc["bullet"]) / maxf(float(acc["all"]), 1.0), 0.01), "hit_fx_melee": hitfx,
		"reloads": acc["reloads"], "level_ups": acc["upgrades"], "weapons_end": weapons, "melee_hits": sm.melee_hits,
		"melee_shakes": sm.melee_shakes, "slow_ticks": int(slow_ticks["n"]), "lunges_alive_dolls": lunges, "supplies_spawned": sm.supplies_spawned,
		"supplies_taken": sm.supplies_taken.duplicate(), "melee_no_ammo_ticks": melee_no_ammo, "stuck_max_s": snappedf(stuck_max, 0.1),
		"ms_per_physics_frame": snappedf(wall_ms / maxf(frames, 1), 0.01), "tally": sm.tally.duplicate(true),
		"props_broken": props0 - (pg.arena.call("breakables") as Array).size(), "props": props0}
	print("  " + JSON.stringify(info["bots"]))
	var taken := 0
	for k in sm.supplies_taken:
		taken += int(sm.supplies_taken[k])
	_check("bots_match_ends", over_count == 1, "матч кончился: %s за %.0f с, счёт %s" % [str(over_count == 1), sm.fight_time, str(sm.score)])
	_check("bots_all_shoot", shooters == gunners and gunners >= 3, "стреляли (> 10 выстрелов) %d из %d стрелков; выстрелов %s" % [shooters, gunners, str(shots)])
	_check("bots_bullets_hit", int(acc["bullet_hits"]) > 100, "попаданий пулями %d (%.0f HP)" % [int(acc["bullet_hits"]), float(acc["bullet"])])
	_check("bots_no_friendly", float(acc["friendly"]) <= 0.01, "урон по своим %.1f HP" % float(acc["friendly"]))
	_check("bots_bullets_no_fx", hitfx < int(acc["bullet_hits"]) / 5, "эффектов удара %d на %d попаданий пулями (эффекты — только от ударов телом)" % [hitfx, int(acc["bullet_hits"])])
	_check("bots_both_frag", kills[0] > 0 and kills[1] > 0, "фраги синих / красных %s" % str(kills))
	_check("bots_first_frag", float(ff["t"]) >= 0.0 and float(ff["t"]) < 60.0, "первый фраг на %.1f с" % float(ff["t"]))
	_check("bots_reload", int(acc["reloads"]) >= 6, "перезарядок %d" % int(acc["reloads"]))
	_check("bots_level_up", int(acc["upgrades"]) >= 6 and level_max >= 3, "новых уровней %d, высший уровень %d" % [int(acc["upgrades"]), level_max])
	_check("bots_brawl", sm.melee_hits > 10, "ударов телом и оружием %d (громилы и наскоки)" % sm.melee_hits)
	_check("bots_no_slowdown", int(slow_ticks["n"]) == 0 and sm.melee_shakes == 0, "тиков с замедлением времени %d, тряски от ударов %d (людей нет)" % [
		int(slow_ticks["n"]), sm.melee_shakes])
	_check("bots_supplies", taken >= 3, "взято ящиков %d из %d появившихся" % [taken, sm.supplies_spawned])
	_check("bots_not_stuck", stuck_max < 25.0, "дольше всего на месте (в радиусе 1.5 м) %.1f с — %s" % [stuck_max, stuck_who])
	_check("bots_in_bounds", out_of_bounds == 0, "тиков вне границ карты %d" % out_of_bounds)
	await _unload()

