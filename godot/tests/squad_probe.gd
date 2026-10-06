## Проба «Стычки 3 на 3» (docs/plan-demo/SQUAD.md) на настоящей площадке scenes/playground_squad.tscn (Полигон, шесть бойцов,
## SquadMatch, SquadGun, SquadMelee, SquadHud). Площадка — без экрана настроек (use_settings = false), матч настраивает проба.
##   aim (боты молчат): рука с оружием своей команды (у синих — кисть Hand_L, у красных — Hand_R) наводит ствол на точку в 8 м в
##     пяти направлениях к стороне соперника (±60°) — угол ствола к цели, медиана и худший; у команд одинаково;
##   rules (P1 — человек без ввода, боты молчат, ящики выключены): шесть бойцов и команды; классы по местам (налётчик, снайпер,
##     громила), вид класса (SquadLook), стартовое оружие, запас HP и броня класса; свои не ранят; пуля и удар — без эффектов удара и
##     замедлений; пули — трассеры; винтовка: темп, магазин, перезарядка, состояние прицела (пауза — cooldown), луч до стены; гаусс —
##     заряд по удержанию, выстрел на отпускание, сквозь стены с потерей урона; опыт и уровни, на 5-м — ветка (игрок — ждёт выбора и
##     сам через время, бот — сразу, цифрой); полёт громилы и потолок удара, ударная волна молота, топор сквозь броню; суставы ×2 и
##     пуля в кисть — износ предплечья; оторванная рука — ствол молчит, ящик возвращает руку с оружием (и громиле); бонусы (ярость,
##     форсаж, обзор); зум снайпера; броня; ящики; нокаут — очко и фраг, возврат; конец; заново — сброс; настройки (SquadSettings) и
##     экран настроек;
##   ctf: захват флага — флаги дома, касание берёт, доставка — очко, выбыл с флагом — флаг падает (очка нет), свой поднимает — домой,
##     сам домой по времени, победа по флагам;
##   night: ночная карта (playground_squad_night.tscn) — окружение тёмное, луна слабая, фонари есть, фон затемнён, звёзды и луна на небе,
##     у обеих карт нет глубины резкости; 20 с боя ботов ночью — пули летят и попадают;
##   bots (P1 тоже бот): матч ботов до score очков — стрелки стреляют, громилы летают и бьют, пули попадают, урона по своим нет, фраги
##     у обеих команд, перезарядки, уровни и ветки, удар громилы не больше потолка, ни одного тика замедления времени и тряски,
##     никто не застрял надолго, все в границах карты; темп и счёт — в info;
##   ctfbots: матч ботов в захвате флага — флаги берут и доставляют.
## Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/squad_probe.tscn -- "only=aim|rules|ctf|night|bots|ctfbots|aim+rules…,max_s=900,level=2,score=20,trace=1,out=<json>"
##   (score — до скольких очков матч ботов: по умолчанию 20 — быстрее; в игре 100; ctfbots — до 2 флагов)
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
	if _want(a, "ctf"):
		await _ctf()
	if _want(a, "night"):
		await _night()
	if _want(a, "bots"):
		await _bots(float(a["max_s"]), int(a["level"]), String(a["trace"]) == "1", int(a["score"]))
	if _want(a, "ctfbots"):
		await _ctf_bots(float(a["max_s"]), int(a["level"]))
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

func _load(p1_bot: bool, level := 2, countdown := 0.3, supplies := false, scene := SCENE, mode := "dm") -> void:
	await _unload()
	Engine.time_scale = 1.0
	pg = (load(scene) as PackedScene).instantiate() as SquadPlayground
	pg.p1_bot = p1_bot
	pg.bot_level = level
	pg.use_settings = false
	sm = pg.get_node("Match") as SquadMatch
	sm.feel_enabled = false
	sm.countdown_s = countdown
	sm.supplies = supplies
	sm.mode = mode
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
	var looks_ok := 0
	var classes := []
	for d in ds:
		var want := "Hand_L" if SquadMatch.team_of(d) == 0 else "Hand_R"
		if _arms(d) == [want]:
			hands_ok += 1
		var cls := String(sm.loadout((d as Doll).player_index)["class"])
		classes.append("%d:%s" % [(d as Doll).player_index, cls])
		if SquadLook.current(d) == cls and not SquadLook.added_nodes(d).is_empty():
			looks_ok += 1
		var g := SquadMatch.gun_of(d)
		var ml := SquadMatch.melee_of(d)
		match cls:
			"brawler":
				if g.weapon == "" and ml.weapon_id == "pan" and ml.armed():
					armed_ok += 1
			"sniper":
				if g.weapon == "rifle" and g.mag == 5 and g.reserve == 30 and ml.weapon_id == "":
					armed_ok += 1
			"raider":
				if g.weapon == "sawnoff" and g.mag == 2 and g.reserve == 24 and ml.weapon_id == "":
					armed_ok += 1
	classes.sort()
	_check("classes", classes == ["0:raider", "1:raider", "2:sniper", "3:sniper", "4:brawler", "5:brawler"], "классы %s" % str(classes))
	_check("class_looks", looks_ok == 6, "вид класса (SquadLook) у %d из 6" % looks_ok)
	_check("one_arm_team_side", hands_ok == 6, "одна рука своей стороны (синие — Hand_L, красные — Hand_R) у %d из 6" % hands_ok)
	_check("start_kit", armed_ok == 6, "налётчики — обрез 2 / 24, снайперы — винтовка 5 / 30, громилы — сковорода в руке: %d из 6" % armed_ok)
	var hp_k := Tuning.DRIVE_MAX_HP / Tuning.MAX_HP if Drive.on else 1.0
	_check("class_stats", is_equal_approx(_doll(4).max_hp, 140.0 * hp_k) and is_equal_approx(sm.armor_of(_doll(4)), 30.0)
		and is_equal_approx(_doll(2).max_hp, 90.0 * hp_k) and is_equal_approx(_doll(0).max_hp, 110.0 * hp_k) and is_equal_approx(sm.armor_of(_doll(0)), 20.0),
		"громила %.0f HP и броня %.0f, снайпер %.0f HP, налётчик %.0f HP и броня %.0f" % [_doll(4).max_hp, sm.armor_of(_doll(4)), _doll(2).max_hp,
		_doll(0).max_hp, sm.armor_of(_doll(0))])
	var p1arm := _doll(0).get_node_or_null("ArmAssist") as ArmAssist
	var botarm := _doll(1).get_node_or_null("ArmAssist") as ArmAssist
	_check("p1_arm_follows_mouse", p1arm != null and not p1arm.show_hints and p1arm.arm_active and botarm != null and not botarm.show_hints
		and not _doll(0).external_input, "рука игрока тянется к курсору без кнопок; колец нет ни у кого (прицел рисует HUD)")
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
	var fx0 := sm.hit_fx_count
	var hp1 := r1.hp
	var dealt := sm.bullet_hit(r1, b0, 9.0, "Torso", r1.centre_of_mass(), Vector3.UP, "pistol")
	_check("bullet_no_shake", r1.hp < hp1 - 3.0 and sm.hit_fx_count == fx0 and sm._time_effects.is_empty() and is_equal_approx(Engine.time_scale, 1.0),
		"пуля сняла %.1f HP; эффектов удара %d, замедлений %d, масштаб времени %.2f" % [dealt, sm.hit_fx_count - fx0, sm._time_effects.size(), Engine.time_scale])
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
	_heal_all()
	await _gun_rules()
	await _gauss_rules()
	await _level_rules()
	await _brawler_rules()
	await _joint_rules()
	await _boost_rules()
	await _armor_supply_rules()
	await _score_rules()
	await _settings_rules()


## Все живые — полный запас HP, брони, патронов (раненый сосед по базе иначе забирает ящики проверки).
func _heal_all() -> void:
	for d in sm.alive_dolls():
		var dd := d as Doll
		dd.hp = dd.max_hp
		sm.add_armor(dd, Tuning.SQUAD_ARMOR_MAX)
		var g := SquadMatch.gun_of(dd)
		if g != null and g.weapon != "":
			g.reserve = g.reserve_max


## Винтовка снайпера: темп, магазин, трассеры, перезарядка сама и клавишей, состояние прицела, луч до стены, без патронов — молчит.
func _gun_rules() -> void:
	var d := _doll(2)
	var g := SquadMatch.gun_of(d)
	var tgt := d.centre_of_mass() + Vector3(8.0, 0.5, 0.0)
	await _hold(d, tgt, 30)
	var st_ready := g.state()
	var frames: Array = []
	var fcb := func(_o: Vector3, _d: Vector3) -> void: frames.append(Engine.get_physics_frames())
	g.fired.connect(fcb)
	g.trigger = true
	await _hold(d, tgt, 2)
	var st_after := g.state()
	var cd_frac := g.cooldown_frac()
	await _hold(d, tgt, 118)   # 2 с: винтовка 0.8 с — 3 выстрела
	var in_2s := frames.size()
	var min_gap := 1 << 20
	for i in range(1, frames.size()):
		min_gap = mini(min_gap, int(frames[i]) - int(frames[i - 1]))
	_check("gun_rate", in_2s == 3 and min_gap >= int(floor(0.8 * 60.0)), "за 2 с выстрелов %d, наименьший зазор %d тиков (интервал 0.8 с = 48)" % [in_2s, min_gap])
	_check("gun_mag_spent", g.mag == 5 - in_2s and g.shots == in_2s, "магазин %d после %d выстрелов" % [g.mag, in_2s])
	_check("aim_state_cooldown", st_ready == "ready" and st_after == "cooldown" and cd_frac < 0.2,
		"прицел: до выстрела %s, сразу после — %s (пауза пройдена на %.2f — жёлтый)" % [st_ready, st_after, cd_frac])
	var shot0 := g.shots
	await _until(func() -> bool: return g.shots > shot0, 1.5)
	var flying := g.balls_in_flight()
	var p0: Vector3 = (g.balls[0]["pos"] as Vector3) if flying > 0 else Vector3.ZERO
	await get_tree().physics_frame
	var step := ((g.balls[0]["pos"] as Vector3).distance_to(p0)) if g.balls_in_flight() > 0 else 0.0
	var node: MeshInstance3D = g.balls[0]["node"] if g.balls_in_flight() > 0 else null
	_check("bullets_are_tracers", flying >= 1 and absf(step - 85.0 / 60.0) < 0.05 and node != null and node.mesh is QuadMesh
		and node.material_override is ShaderMaterial, "в полёте %d, трассер за тик прошёл %.2f м (ждём %.2f — 85 м/с), квад с шейдером трассера" % [flying,
		step, 85.0 / 60.0])
	await _until(func() -> bool: return g.mag == 0, 5.0)
	var empty_at := Engine.get_physics_frames()
	await _until(func() -> bool: return g.reloading > 0.0, 0.2)
	_check("gun_auto_reload", g.reloading > 0.0 and Engine.get_physics_frames() - empty_at <= 2 and g.state() == "reload",
		"магазин пуст — перезарядка началась сама через %d тик(а), прицел — %s" % [Engine.get_physics_frames() - empty_at, g.state()])
	var r_start := Engine.get_physics_frames()
	g.trigger = false
	await _until(func() -> bool: return g.reloading <= 0.0, 3.0)
	var r_s := float(Engine.get_physics_frames() - r_start) / 60.0
	_check("gun_reload_time", g.mag == 5 and g.reserve == 25 and absf(r_s - 1.8) < 0.1, "перезарядка %.2f с (ждём 1.8), стало %d / %d" % [r_s, g.mag, g.reserve])
	g.trigger = true
	await _hold(d, tgt, 2)
	g.trigger = false
	var m_before := g.mag
	var started := g.reload()
	await _until(func() -> bool: return g.reloading <= 0.0, 3.0)
	_check("gun_manual_reload", started and m_before < 5 and g.mag == 5 and g.reserve == 25 - (5 - m_before),
		"клавишей: %d → 5, запас %d" % [m_before, g.reserve])
	# луч прицела: в пол — упирается (крестик), в небо — на всю дальность
	await _hold(d, d.centre_of_mass() + Vector3(1.0, -8.0, 0.0), 40)
	var e_floor := g.aim_end()
	var o_floor := (g.aim_ray()[0] as Vector3) if not g.aim_ray().is_empty() else Vector3.ZERO
	await _hold(d, d.centre_of_mass() + Vector3(6.0, 6.0, 0.0), 40)
	var e_sky := g.aim_end()
	var o_sky := (g.aim_ray()[0] as Vector3) if not g.aim_ray().is_empty() else Vector3.ZERO
	var sky_d := o_sky.distance_to(e_sky[0]) if not e_sky.is_empty() else -1.0
	_check("aim_reach", not e_floor.is_empty() and bool(e_floor[1]) and o_floor.distance_to(e_floor[0]) < 15.0 and not e_sky.is_empty()
		and sky_d <= 32.05 and (bool(e_sky[1]) or absf(sky_d - 32.0) < 0.05),
		"луч в пол — %.1f м до препятствия (крестик); вверх — %.1f м (%s; дальность 32)" % [o_floor.distance_to(e_floor[0]) if not e_floor.is_empty() else -1.0,
		sky_d, "упёрся" if not e_sky.is_empty() and bool(e_sky[1]) else "вся дальность"])
	g.mag = 0
	g.reserve = 0
	var s0 := g.shots
	g.trigger = true
	await _hold(d, tgt, 30)
	g.trigger = false
	_check("gun_out_of_ammo", g.out_of_ammo() and g.shots == s0 and g.state() == "empty", "патронов нет — спуск молчит, out_of_ammo, прицел — %s" % g.state())
	g.fired.disconnect(fcb)
	g.arm().clear_target_override()
	g.equip("rifle")


## Гаусс: заряд — пока спуск зажат, выстрел — на отпускание, урон по заряду; сквозь стены — × (1 − wall_loss) за каждую, обычная пуля
## в стене гаснет.
func _gauss_rules() -> void:
	var d := _doll(2)
	var lo := sm.loadout(2)
	lo["level"] = 5
	lo["branch"] = "gauss"
	sm._equip(d)
	var g := SquadMatch.gun_of(d)
	var tgt := d.centre_of_mass() + Vector3(8.0, 2.0, 0.0)
	await _hold(d, tgt, 20)
	var s0 := g.shots
	g.trigger = true
	await _hold(d, tgt, 48)   # 0.8 с из 1.6 — половина заряда
	var mid := g.charge
	var shots_held := g.shots - s0
	g.trigger = false
	await _hold(d, tgt, 2)
	var want_dmg := lerpf(float(g.def["damage_min"]), float(g.def["damage"]), g.last_charge)   # с усилением «урон» ствола класса
	var dmg := float(g.balls[0]["damage"]) if g.balls_in_flight() > 0 else -1.0
	_check("gauss_charge", g.weapon == "gauss" and shots_held == 0 and absf(mid - 0.5) < 0.06 and g.shots == s0 + 1 and absf(g.last_charge - mid) < 0.05
		and absf(dmg - want_dmg) < 0.5, "держал 0.8 с: заряд %.2f, выстрелов пока держал %d, на отпускание — 1 (заряд %.2f, урон %.1f из %.0f…%.0f)" % [mid,
		shots_held, g.last_charge, dmg, float(g.def["damage_min"]), float(g.def["damage"])])
	# две стены в пустом небе по ходу пули: гаусс проходит обе (×0.65²), винтовка гаснет в первой
	var walls: Array = []
	for x in [3.0, 6.0]:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.3, 4.0, 2.0)
		cs.shape = bs
		sb.add_child(cs)
		sb.position = Vector3(x, 13.0, 0.0)
		pg.add_child(sb)
		walls.append(sb)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await _until(func() -> bool: return g.balls_in_flight() == 0, 1.0)   # прошлый выстрел гаусса ещё летит сквозь стены карты
	var ex: Array[RID] = []
	var w0 := g.walls_pierced
	g._spawn_ball(Vector3(0.0, 13.0, 0.0), Vector3.RIGHT, ex, 80.0, 1.0)
	var ball: Dictionary = g.balls[g.balls.size() - 1]
	for i in 4:
		await get_tree().physics_frame
	var after := float(ball["damage"])
	var through := int(ball["through"])
	g.equip("rifle")
	g._spawn_ball(Vector3(0.0, 13.0, 0.0), Vector3.RIGHT, ex.duplicate(), 24.0, 1.0)
	var rball: Dictionary = g.balls[g.balls.size() - 1]
	for i in 4:
		await get_tree().physics_frame
	_check("gauss_through_walls", through == 2 and absf(after - 80.0 * 0.65 * 0.65) < 0.5 and g.walls_pierced - w0 == 2 and not g.balls.has(rball)
		and int(rball["through"]) == 0, "гаусс: стен пройдено %d (счётчик +%d), урон 80 → %.1f (ждём %.1f); винтовка — погасла в первой стене: %s" % [through,
		g.walls_pierced - w0, after, 80.0 * 0.65 * 0.65, str(not g.balls.has(rball) and int(rball["through"]) == 0)])
	for w in walls:
		(w as Node).queue_free()
	lo["level"] = 1
	lo["branch"] = ""
	lo["xp"] = 0.0
	sm._equip(d)
	g.arm().clear_target_override()


## Опыт и уровни: опыт за урон; уровень открывает своё; на 5-м у игрока — ждёт выбор ветки (сам — через время), у бота — сразу;
## цифрой — ветка; всё переживает возврат; смена класса в бою — с возрождения и снова выбор ветки.
func _level_rules() -> void:
	var pi := 0   # налётчик, человек
	var lv_seen: Array = []
	var pend: Array = []
	sm.leveled.connect(func(p: int, lv: int, u: Dictionary) -> void:
		if p == pi:
			lv_seen.append([lv, u]))
	sm.branch_pending.connect(func(p: int, c: String) -> void: pend.append([p, c]))
	var r1 := _doll(1)
	r1.grace_until = 0.0
	var xp0 := float(sm.loadout(pi)["xp"])
	var dealt := sm.bullet_hit(r1, _doll(pi), 9.0, "Torso", r1.centre_of_mass(), Vector3.UP, "sawnoff")
	_check("xp_for_damage", dealt > 0.0 and is_equal_approx(float(sm.loadout(pi)["xp"]) - xp0, dealt * Tuning.SQUAD_XP_PER_DAMAGE),
		"опыт +%.1f за %.1f урона" % [float(sm.loadout(pi)["xp"]) - xp0, dealt])
	sm.add_xp(pi, float(Tuning.SQUAD_XP_LEVELS[1]))
	var g := _gun(pi)
	_check("level2_perk", int(sm.loadout(pi)["level"]) == 2 and lv_seen.size() == 1 and String((lv_seen[0][1] as Dictionary).get("perk", "")) == "speed"
		and is_equal_approx(float(g.def["interval"]), 0.45 * 0.8), "уровень 2: %s, пауза обреза %.3f с (0.45 × 0.8)" % [str(lv_seen), float(g.def["interval"])])
	sm.add_xp(pi, float(Tuning.SQUAD_XP_LEVELS[4]))
	g = _gun(pi)
	_check("level5_branch_waits", int(sm.loadout(pi)["level"]) == 5 and String(sm.loadout(pi)["branch"]) == "" and sm.branch_left(pi) > 0.0
		and pend.size() == 1 and g.weapon == "sawnoff", "уровень 5: ветка ждёт выбора (%.0f с), обрез пока в руке" % sm.branch_left(pi))
	sm.branch_wait[pi] = 0.05
	await _wait(0.3)
	g = _gun(pi)
	_check("branch_auto", String(sm.loadout(pi)["branch"]) == "shotgun" and g.weapon == "shotgun" and sm.branch_left(pi) < 0.0,
		"не выбрал — сама первая ветка: %s, в руке %s" % [String(sm.loadout(pi)["branch"]), g.weapon])
	var bpi := 3   # бот-снайпер — ветку выбирает сразу
	sm.add_xp(bpi, float(Tuning.SQUAD_XP_LEVELS[4]))
	var want_b := sm.bot_branch(bpi, "sniper")
	_check("bot_branch_now", String(sm.loadout(bpi)["branch"]) == want_b and _gun(bpi).weapon == ("gauss" if want_b == "gauss" else "marksman"),
		"бот: ветка %s сразу, в руке %s" % [String(sm.loadout(bpi)["branch"]), _gun(bpi).weapon])
	_doll(pi).knock_out(_doll(1), {"kind": "body"})
	await _wait(Tuning.SQUAD_RESPAWN_S + 0.3)
	var ng := _gun(pi)
	_check("level_survives_respawn", ng != null and ng.weapon == "shotgun" and ng.mag == ng.mag_max and int(sm.loadout(pi)["level"]) == 5,
		"после возврата: уровень %d, %s %d / %d" % [int(sm.loadout(pi)["level"]), ng.weapon if ng != null else "-", ng.mag if ng != null else 0,
		ng.mag_max if ng != null else 0])
	sm.set_class(pi, "sniper")
	_check("class_pending", String(sm.loadout(pi)["class"]) == "raider" and String(sm.loadout(pi)["next_class"]) == "sniper" and _gun(pi).weapon == "shotgun",
		"в бою: класс пока налётчик, следующий — снайпер")
	await _wait(Tuning.SQUAD_SPAWN_SHIELD_S + 0.2)
	_doll(pi).knock_out(_doll(1), {"kind": "body"})
	await _wait(Tuning.SQUAD_RESPAWN_S + 0.4)
	var waits := sm.branch_left(pi) > 0.0 and String(sm.loadout(pi)["branch"]) == ""
	pg._number(_doll(pi), 1)   # цифра 2 — вторая ветка снайпера
	_check("class_on_respawn_key_branch", String(sm.loadout(pi)["class"]) == "sniper" and waits and String(sm.loadout(pi)["branch"]) == "marksman"
		and _gun(pi).weapon == "marksman" and SquadLook.current(_doll(pi)) == "sniper",
		"после возврата — снайпер, ветка ждала: %s, клавиша 2 → %s, в руке %s, вид %s" % [str(waits), String(sm.loadout(pi)["branch"]), _gun(pi).weapon,
		SquadLook.current(_doll(pi))])
	sm.set_class(pi, "raider")


## Громила: полёт — разгон к точке, пауза после, не дольше SQUAD_DASH_S; потолок удара и редкость по одному бойцу; ярость; волна молота;
## топор сквозь броню.
func _brawler_rules() -> void:
	var b := _doll(4)
	var ml := SquadMatch.melee_of(b)
	b.grace_until = 0.0
	var arm := ml.arm()
	var far := b.centre_of_mass() + Vector3(2.0, 9.0, 0.0)   # вверх — в открытое небо (вбок у базы — укрытие)
	var started := ml.start_dash(far)
	var again := ml.start_dash(far)
	var v := 0.0
	for i in 30:
		arm.set_target_override(far)
		ml.steer_dash(far)
		await get_tree().physics_frame
		v = maxf(v, b.torso().linear_velocity.length())
	ml.end_dash()
	var cd := ml.cooldown
	_check("dash_flies", started and not again and v > 7.0 and cd > 3.0 and not ml.can_dash() and ml.ready_frac() < 0.1,
		"полёт: старт %s, второй — %s, торс до %.1f м/с за 0.5 с, пауза %.1f с" % [str(started), str(again), v, cd])
	ml.cooldown = 0.0
	ml.start_dash(far)
	await _wait(Tuning.SQUAD_DASH_S + 0.3)
	_check("dash_max_time", not ml.dashing and ml.cooldown > 0.0, "держал дольше %.0f с — полёт кончился сам" % Tuning.SQUAD_DASH_S)
	ml.cooldown = 0.0
	# потолок удара: в полёте — SQUAD_DASH_HIT_MAX и не чаще SQUAD_DASH_HIT_GAP_S по одному бойцу; без полёта — SQUAD_MELEE_HIT_MAX
	var victim := _doll(1)
	var c := {"striker": ml.weapon}
	ml.dashing = true
	var h1 := sm.adjust_hit_damage(victim, b, 60.0, c)
	var h2 := sm.adjust_hit_damage(victim, b, 60.0, c)
	ml.dashing = false
	ml.dash_end_t = -10.0
	var h3 := sm.adjust_hit_damage(victim, b, 60.0, c)
	sm.boosts_active[4] = {"rage": 5.0}
	var h4 := sm.adjust_hit_damage(victim, b, 20.0, c)
	sm.boosts_active.erase(4)
	_check("dash_hit_cap", is_equal_approx(h1, Tuning.SQUAD_DASH_HIT_MAX) and h2 == 0.0 and is_equal_approx(h3, Tuning.SQUAD_MELEE_HIT_MAX)
		and is_equal_approx(h4, 30.0), "удар 60 HP: в полёте %.0f, тот же боец сразу — %.0f, без полёта %.0f; ярость 20 → %.0f" % [h1, h2, h3, h4])
	# молот: удар в полёте — волна раз за полёт
	var lo := sm.loadout(4)
	lo["level"] = 5
	lo["branch"] = "hammer"
	sm._equip(b)
	await _wait(0.2)
	ml = SquadMatch.melee_of(b)
	ml.dashing = true
	ml.wave_done = false
	var w0 := sm.waves
	var near := _doll(1)
	near.grace_until = 0.0
	sm.on_hit(near, b, 20.0, "weapon", near.centre_of_mass(), 0, false, "hammer", 9.0)
	sm.on_hit(near, b, 20.0, "weapon", near.centre_of_mass(), 0, false, "hammer", 9.0)
	_check("hammer_wave", ml.weapon_id == "hammer" and ml.armed() and sm.waves - w0 == 1 and near.is_stunned(),
		"молот в руке %s, волн за полёт %d, задетый в стане %s" % [str(ml.armed()), sm.waves - w0, str(near.is_stunned())])
	ml.dashing = false
	# топор: броня не гасит урон
	lo["branch"] = "axe"
	sm._equip(b)
	await _wait(0.2)
	ml = SquadMatch.melee_of(b)
	ml.dash_end_t = -10.0
	var tgt := _doll(3)
	tgt.grace_until = 0.0
	sm.add_armor(tgt, Tuning.SQUAD_ARMOR_MAX)
	var hpa := tgt.hp
	var raw := sm.adjust_hit_damage(tgt, b, 20.0, {"striker": ml.weapon})
	tgt.take_damage(raw, b, "Torso", tgt.centre_of_mass(), Vector3.UP, "weapon")
	_check("axe_armor_pierce", ml.weapon_id == "axe" and absf((hpa - tgt.hp) - 20.0) < 0.1 and is_equal_approx(float((ml.weapon.get_meta(PartMods.META) as Dictionary)["wear_mult"]), 2.5),
		"топор 20 HP по броне: снято %.1f (броня не гасит), износ суставов × %.1f" % [hpa - tgt.hp, float((ml.weapon.get_meta(PartMods.META, {}) as Dictionary).get("wear_mult", 1.0))])
	lo["level"] = 1
	lo["branch"] = ""
	lo["xp"] = 0.0
	sm._equip(b)
	_heal_all()


## Суставы: прочность включена, запас × SQUAD_JOINT_HP_MULT, пуля в кисть изнашивает предплечье; оторванная рука — ствол молчит,
## любой ящик (даже ненужный) возвращает руку с оружием; громиле — с оружием в кисти.
func _joint_rules() -> void:
	await _wait(0.3)
	var d := _doll(1)   # красный налётчик: оружие в Hand_R
	d.grace_until = 0.0
	var base := JointBreak.hp_for_depth(int(d.joint_depth.get("UpperArm_R", 1)))
	_check("joints_on", JointBreak.on and is_equal_approx(float(d.joint_hp_max.get("UpperArm_R", 0.0)), base * Tuning.SQUAD_JOINT_HP_MULT),
		"прочность суставов вкл: плечо %.1f (база %.1f × %.0f)" % [float(d.joint_hp_max.get("UpperArm_R", 0.0)), base, Tuning.SQUAD_JOINT_HP_MULT])
	var hand0 := float(d.joint_hp.get("Hand_R", 0.0))
	var fore0 := float(d.joint_hp.get("LowerArm_R", 0.0))
	sm.bullet_hit(d, _doll(0), 6.0, "Hand_R", d.centre_of_mass(), Vector3.UP, "sawnoff")
	_check("bullet_hand_to_forearm", is_equal_approx(float(d.joint_hp.get("Hand_R", 0.0)), hand0) and float(d.joint_hp.get("LowerArm_R", 0.0)) < fore0,
		"пуля в кисть: сустав кисти %.1f → %.1f, предплечья %.1f → %.1f" % [hand0, float(d.joint_hp.get("Hand_R", 0.0)), fore0,
		float(d.joint_hp.get("LowerArm_R", 0.0))])
	d.hp = d.max_hp
	d.detach_part("LowerArm_R", _doll(0))
	await _wait(0.2)
	var g := SquadMatch.gun_of(d)
	var lost := g.state() == "none" and not sm.has_weapon_arm(d)
	g.reserve = g.reserve_max   # патроны не нужны — ящик берётся ради руки
	var r0 := sm.limbs_restored
	var c := sm.spawn_supply("ammo", d.centre_of_mass())
	await _wait(0.3)
	_check("arm_restored_by_crate", lost and not is_instance_valid(c) and sm.has_weapon_arm(d) and not g.aim_ray().is_empty() and sm.limbs_restored > r0,
		"рука оторвана — ствол молчит (%s); ящик патронов (не нужных) взят, рука на месте, ствол снова смотрит" % str(lost))
	var br := _doll(5)   # красный громила: сковорода в Hand_R
	br.grace_until = 0.0
	br.detach_part("LowerArm_R", _doll(0))
	await _wait(0.2)
	var ml := SquadMatch.melee_of(br)
	var lost2 := not ml.armed()
	sm.spawn_supply("health", br.centre_of_mass())
	await _wait(0.4)
	_check("brawler_rearmed", lost2 and ml.armed() and ml.weapon_id == "pan", "громила: оружие выпало с рукой (%s), ящик — рука и сковорода снова в кисти" % str(lost2))
	_heal_all()


## Бонусы: ярость — урон × 1.5, форсаж — тяга × 1.35, обзор — зум камеры; проходят по времени.
func _boost_rules() -> void:
	await _wait(0.2)
	var d := _doll(3)
	d.grace_until = 0.0
	var took := 0
	for k in ["rage", "haste", "zoom"]:   # касание ящика проверено ниже (supply_*): здесь — что даёт бонус
		if sm.take_supply(d, k):
			took += 1
	await _wait(0.1)
	var v := _doll(0)
	v.grace_until = 0.0
	sm.add_armor(v, -1000.0)
	var hpv := v.hp
	sm.bullet_hit(v, d, 10.0, "Torso", v.centre_of_mass(), Vector3.UP, "rifle")
	var cls_zoom := float(Tuning.SQUAD_CLASSES["sniper"]["zoom"])
	_check("boosts_taken", took == 3 and sm.boost_left(d, "rage") > 0.0 and sm.boost_left(d, "haste") > 0.0 and sm.boost_left(d, "zoom") > 0.0
		and absf((hpv - v.hp) - 15.0) < 0.1 and is_equal_approx(d.thrust_mult, 1.35) and is_equal_approx(sm.view_zoom(d), cls_zoom * 1.35),
		"ярость: пуля 10 → %.1f; форсаж: тяга × %.2f; обзор: зум %.2f" % [hpv - v.hp, d.thrust_mult, sm.view_zoom(d)])
	for k in sm.boosts_active.get(3, {}).keys():
		sm.boosts_active[3][k] = 0.05
	await _wait(0.2)
	_check("boosts_expire", sm.boost_left(d, "rage") <= 0.0 and is_equal_approx(d.thrust_mult, 1.0) and is_equal_approx(sm.view_zoom(d), cls_zoom),
		"бонусы кончились: тяга × %.2f, зум %.2f" % [d.thrust_mult, sm.view_zoom(d)])
	_heal_all()


## Броня и ящики.
func _armor_supply_rules() -> void:
	await _wait(Tuning.SQUAD_SPAWN_SHIELD_S + 0.2)
	var r := _doll(2)   # синий снайпер: своей брони у класса нет
	r.grace_until = 0.0
	sm.add_armor(r, -1000.0)
	sm.add_armor(r, 50.0)
	var hp0 := r.hp
	r.take_damage(20.0, _doll(1), "Torso", r.centre_of_mass(), Vector3.UP, "body")
	_check("armor_halves", is_equal_approx(hp0 - r.hp, 10.0) and is_equal_approx(sm.armor_of(r), 40.0) and is_equal_approx(r.incoming_mult, 0.5),
		"урон 20 при броне 50: HP −%.1f, броня %.1f" % [hp0 - r.hp, sm.armor_of(r)])
	r.take_damage(100.0, _doll(1), "Torso", r.centre_of_mass(), Vector3.UP, "body")
	_check("armor_runs_out", (sm.armor_of(r) <= 0.0 and is_equal_approx(r.incoming_mult, 1.0)) or not r.alive, "броня кончилась — урон снова полный")
	_heal_all()   # раненый сосед по базе взял бы ящики ниже раньше проверяемого
	var d := _doll(3)   # красный снайпер: ствол есть
	d.grace_until = 0.0
	sm.add_armor(d, -1000.0)
	var g := SquadMatch.gun_of(d)
	g.reserve = 0
	var who := [-1]
	var c1 := sm.spawn_supply("ammo", d.centre_of_mass())
	c1.taken.connect(func(_c: SupplyCrate, by: Doll) -> void: who[0] = by.player_index)
	await _wait(0.2)
	_check("supply_ammo", not is_instance_valid(c1) and g.reserve > 0 and int(who[0]) == 3, "патроны: запас 0 → %d (ящик взял P%d)" % [g.reserve, int(who[0]) + 1])
	g.reserve = g.reserve_max
	var c2 := sm.spawn_supply("ammo", d.centre_of_mass())
	await _wait(0.2)
	_check("supply_not_needed", is_instance_valid(c2), "полный запас — ящик остался")
	if is_instance_valid(c2):
		c2.queue_free()
	d.take_damage(50.0, _doll(0), "Torso", d.centre_of_mass(), Vector3.UP, "body")
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
	_check("supply_spawns", sm.supplies_spawned > n0, "за %.1f с появилось ящиков %d" % [Tuning.SQUAD_SUPPLY_EVERY_S + 0.3, sm.supplies_spawned - n0])
	sm.supplies = false
	for c in get_tree().get_nodes_in_group(SquadMatch.SUPPLY_GROUP):
		(c as Node).queue_free()


## Счёт, фраг, возврат, конец, заново.
func _score_rules() -> void:
	sm.restart()
	await _until(func() -> bool: return sm.play_state == "play", 6.0)
	_brains_off()
	_check("restart_resets", sm.score == [0, 0] and _gun(0).weapon == "sawnoff" and int(sm.loadout(0)["level"]) == 1
		and float(sm.loadout(0)["xp"]) == 0.0 and String(sm.loadout(0)["class"]) == "raider" and String(sm.loadout(0)["branch"]) == ""
		and sm.alive_dolls().size() == 6 and sm.boosts_active.is_empty(),
		"счёт %s, P1: %s, уровень %d, опыт %.0f, ветка «%s»" % [str(sm.score), _gun(0).weapon, int(sm.loadout(0)["level"]), float(sm.loadout(0)["xp"]),
		String(sm.loadout(0)["branch"])])
	sm.set_class(0, "sniper")
	_check("class_now_on_countdown_or_play", String(sm.loadout(0)["next_class"]) == "sniper", "выбор класса записан")
	sm.set_class(0, "raider")
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
		and _arms(nr1) == ["Hand_R"] and SquadMatch.gun_of(nr1) != null and SquadMatch.gun_of(nr1).mag == 2 and SquadLook.current(nr1) == "raider"
		and nr1.get_children().filter(func(c: Node) -> bool: return c is SquadGun and not c.is_queued_for_deletion()).size() == 1
		and nr1.get_children().filter(func(c: Node) -> bool: return c is SquadMelee and not c.is_queued_for_deletion()).size() == 1,
		"команда, обводка, вид налётчика, мозг, одна рука Hand_R, обрез с полным магазином, один узел рукопашной")
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


## Настройки перед боем: SquadSettings → матч (режим, очки, время, боты, суставы, ящики, класс), зум снайпера; экран настроек — бой
## ждёт «В БОЙ», строка листается, бой стартует с новым значением.
func _settings_rules() -> void:
	await _unload()
	SquadSettings.reset()
	SquadSettings.mode = "ctf"
	SquadSettings.captures_to_win = 5
	SquadSettings.time_min = 10
	SquadSettings.bot_level = 3
	SquadSettings.joints = false
	SquadSettings.supplies = false
	SquadSettings.boosts = false
	SquadSettings.player_class = "sniper"
	pg = (load(SCENE) as PackedScene).instantiate() as SquadPlayground
	sm = pg.get_node("Match") as SquadMatch
	sm.feel_enabled = false
	sm.countdown_s = 0.3
	add_child(pg)
	await _until(func() -> bool: return sm.play_state == "play", 6.0)
	_brains_off()
	_check("settings_applied", sm.mode == "ctf" and sm.score_to_win == 5 and is_equal_approx(sm.time_limit_s, 600.0) and not sm.supplies and not sm.boosts
		and pg.bot_level == 3 and not JointBreak.on and String(sm.loadout(0)["class"]) == "sniper" and sm.flags.size() == 2,
		"режим %s до %d, время %.0f с, ящики %s, боты %d, суставы %s, класс %s, флагов %d" % [sm.mode, sm.score_to_win, sm.time_limit_s, str(sm.supplies),
		pg.bot_level, str(JointBreak.on), String(sm.loadout(0)["class"]), sm.flags.size()])
	await _wait(1.5)
	var want_h := SquadPlayground.CAM_MAX_H * float(Tuning.SQUAD_CLASSES["sniper"]["zoom"])
	_check("sniper_zoom", absf(pg.cam.max_half_height - want_h) < 0.2, "снайпер: высота кадра до %.1f м (у других %.1f)" % [pg.cam.max_half_height,
		SquadPlayground.CAM_MAX_H])
	await _unload()
	SquadSettings.reset()
	SquadSettings.ask = true
	pg = (load(SCENE) as PackedScene).instantiate() as SquadPlayground
	sm = pg.get_node("Match") as SquadMatch
	sm.feel_enabled = false
	sm.countdown_s = 0.3
	add_child(pg)
	await _wait(1.0)
	var waiting := pg.setup != null and is_instance_valid(pg.setup) and sm.play_state == "idle" and not pg.hud.visible
	pg.setup.sel = 2   # «до победы»
	pg.setup.change(1)
	pg._on_setup_started()
	await _until(func() -> bool: return sm.play_state == "play", 6.0)
	_check("setup_screen", waiting and SquadSettings.score_to_win == 150 and sm.score_to_win == 150 and sm.play_state == "play" and pg.setup == null
		and pg.hud.visible, "экран настроек: бой ждал (%s), «до победы» 100 → %d, бой начался до %d" % [str(waiting), SquadSettings.score_to_win,
		sm.score_to_win])
	SquadSettings.reset()
	await _unload()


## Кисти рук куклы (ArmAssist.part_name), по алфавиту.
func _arms(d: Doll) -> Array:
	var parts := []
	for c in d.get_children():
		if c is ArmAssist and not c.is_queued_for_deletion():
			parts.append((c as ArmAssist).part_name)
	parts.sort()
	return parts


# ------------------------------------------------------------------ захват флага

func _ctf() -> void:
	print("--- ctf")
	await _load(false, 2, 0.3, false, SCENE, "ctf")
	_brains_off()
	await _wait(1.0)
	var events: Array = []
	sm.flag_event.connect(func(t: int, w: String, d: Doll) -> void: events.append([t, w, d.player_index if d != null else -1]))
	var f0 := sm.flag_of(0)
	var f1 := sm.flag_of(1)
	var a := pg.arena
	_check("ctf_flags_home", f0 != null and f1 != null and f0.state == "home" and f1.state == "home"
		and f0.global_position.distance_to(a.call("flag_point", 0)) < 0.01 and f1.global_position.distance_to(a.call("flag_point", 1)) < 0.01,
		"флаги у баз: синий %s, красный %s" % [str(f0.global_position.snapped(Vector3.ONE * 0.1)) if f0 != null else "-",
		str(f1.global_position.snapped(Vector3.ONE * 0.1)) if f1 != null else "-"])
	var red := _doll(5)   # красный громила: возрождается не у своего флага (налётчик P2 стоит на нём — доставлял бы сразу)
	var home0 := f0.home
	var home1 := f1.home
	f0.home = red.centre_of_mass()
	f0.go_home()
	await get_tree().physics_frame
	await get_tree().physics_frame
	f0.home = home0
	var taken := f0.state == "carried" and f0.carrier == red
	var xp0 := float(sm.loadout(5)["xp"])
	f1.home = red.centre_of_mass()
	f1.go_home()
	await _wait(0.1)
	_check("ctf_take_capture", taken and sm.score == [0, 1] and f0.state == "home" and f0.global_position.distance_to(home0) < 0.01
		and int(sm.tally[5]["captures"]) == 1 and float(sm.loadout(5)["xp"]) - xp0 >= Tuning.SQUAD_XP_PER_CAPTURE
		and events.has([0, "taken", 5]) and events.has([0, "captured", 5]),
		"красный коснулся синего флага — несёт (%s); донёс до своего — счёт %s, флаг синих дома, события %s" % [str(taken), str(sm.score), str(events)])
	f1.home = home1
	f1.go_home()
	await get_tree().physics_frame
	f0.home = red.centre_of_mass()
	f0.go_home()
	await get_tree().physics_frame
	await get_tree().physics_frame
	f0.home = home0
	var carried2 := f0.state == "carried"
	red.knock_out(_doll(0), {"kind": "body"})
	await _wait(0.1)
	_check("ctf_drop_on_ko", carried2 and f0.state == "dropped" and sm.score == [0, 1], "несущий выбыл — флаг упал (%s), за выбывание очков нет: %s" % [f0.state,
		str(sm.score)])
	f0.global_position = _doll(2).centre_of_mass()
	await _wait(0.1)
	var by_blue := events.filter(func(e: Array) -> bool: return e[1] == "returned" and int(e[2]) >= 0 and int(e[2]) % 2 == 0).size() > 0
	_check("ctf_return_by_own", f0.state == "home" and by_blue, "свой коснулся упавшего — флаг %s; события %s" % [f0.state,
		str(events.slice(-3))])
	f0.drop(Vector3(0.0, 12.0, 0.0))
	f0.left = 0.1
	await _wait(0.3)
	_check("ctf_auto_return", f0.state == "home" and events.has([0, "returned", -1]), "упавший флаг вернулся сам по времени")
	sm.score_to_win = 2
	await _wait(Tuning.SQUAD_RESPAWN_S + 0.3)   # громила вернулся на базу — снова далеко от своего флага? берём другого: P4 синих не годится
	var red3 := _doll(5)
	red3.grace_until = 0.0
	f0.home = red3.centre_of_mass()
	f0.go_home()
	await get_tree().physics_frame
	await get_tree().physics_frame
	f0.home = home0
	f1.home = red3.centre_of_mass()
	f1.go_home()
	await _wait(0.2)
	_check("ctf_win", over_count == 1 and int(over_results.get("winner_team", -1)) == 1 and sm.score == [0, 2] and String(over_results.get("mode", "")) == "ctf",
		"второй флаг — победа красных: итогов %d, счёт %s" % [over_count, str(sm.score)])
	await _unload()


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
	await _wait(20.0)   # стреляют 4 из 6 (громилы — без ствола): обрезы вблизи и винтовки
	var shots := 0
	for d in sm.dolls():
		var g := SquadMatch.gun_of(d)
		if g != null:
			shots += g.shots
	_check("night_fight", shots - shots0 > 6 and int(hits["n"]) > 5, "20 с ночью: выстрелов %d, попаданий %d" % [shots - shots0, int(hits["n"])])
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
	var joints := {"n": 0}
	var on_joint := func(_p: String, _by: Node, _pos: Vector3) -> void: joints["n"] = int(joints["n"]) + 1
	for d in sm.dolls():
		(d as Doll).joint_broken.connect(on_joint)
	sm.doll_respawned.connect(func(nd: Doll) -> void: nd.joint_broken.connect(on_joint))
	var dashes := {}
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
			var mm0 := SquadMatch.melee_of(dd)
			if mm0 != null:
				var mid := mm0.get_instance_id()
				dashes[mid] = mm0.dashes
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
	var branch_ok := true
	var branches := {}
	for pi in sm.loadouts:
		var lo: Dictionary = sm.loadouts[pi]
		level_max = maxi(level_max, int(lo["level"]))
		if int(lo["level"]) >= Tuning.SQUAD_BRANCH_LEVEL:
			branch_ok = branch_ok and String(lo["branch"]) != ""
			branches[pi] = String(lo["branch"])
	var dash_n := 0
	for k in dashes:
		dash_n += int(dashes[k])
	var hitfx := sm.hit_fx_count - fx0
	info["bots"] = {"level": level, "fight_s": snappedf(sm.fight_time, 0.1), "score": sm.score.duplicate(), "frags": sm.frags.size(),
		"first_frag_s": snappedf(float(ff["t"]), 0.1), "kills_by_team": kills, "shots": shots, "bullet_hits": acc["bullet_hits"],
		"bullet_damage_share": snappedf(float(acc["bullet"]) / maxf(float(acc["all"]), 1.0), 0.01), "hit_fx_melee": hitfx,
		"reloads": acc["reloads"], "level_ups": acc["upgrades"], "weapons_end": weapons, "melee_hits": sm.melee_hits,
		"melee_shakes": sm.melee_shakes, "slow_ticks": int(slow_ticks["n"]), "dashes": dash_n, "dash_hits": sm.dash_hits_n,
		"melee_max_hit": snappedf(sm.melee_max_hit, 0.1), "waves": sm.waves, "joints_broken": int(joints["n"]), "limbs_restored": sm.limbs_restored,
		"branches": branches, "supplies_spawned": sm.supplies_spawned,
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
	_check("bots_brawl", sm.melee_hits > 10 and dash_n >= 4, "ударов телом и оружием %d, полётов громил %d" % [sm.melee_hits, dash_n])
	_check("bots_melee_cap", sm.melee_max_hit <= Tuning.SQUAD_MELEE_HIT_MAX + 0.01, "сильнейший удар оружием громилы %.1f HP (потолок %.0f, в полёте %.0f)" % [
		sm.melee_max_hit, Tuning.SQUAD_MELEE_HIT_MAX, Tuning.SQUAD_DASH_HIT_MAX])
	_check("bots_branches", branch_ok and not branches.is_empty(), "ветки на 5+ уровне: %s" % str(branches))
	_check("bots_no_slowdown", int(slow_ticks["n"]) == 0 and sm.melee_shakes == 0, "тиков с замедлением времени %d, тряски от ударов %d (людей нет)" % [
		int(slow_ticks["n"]), sm.melee_shakes])
	_check("bots_supplies", taken >= 3, "взято ящиков %d из %d появившихся" % [taken, sm.supplies_spawned])
	_check("bots_not_stuck", stuck_max < 25.0, "дольше всего на месте (в радиусе 1.5 м) %.1f с — %s" % [stuck_max, stuck_who])
	_check("bots_in_bounds", out_of_bounds == 0, "тиков вне границ карты %d" % out_of_bounds)
	await _unload()


# ------------------------------------------------------------------ захват флага ботами

func _ctf_bots(max_s: float, level: int) -> void:
	print("--- ctf bots (level %d, до 2 флагов)" % level)
	await _load(true, level, 3.0, true, SCENE, "ctf")
	sm.score_to_win = 2
	var ev := {}
	sm.flag_event.connect(func(_t: int, w: String, _d: Doll) -> void: ev[w] = int(ev.get(w, 0)) + 1)
	var limit := minf(max_s, 600.0)
	var trace_t := 0.0
	while over_count == 0 and sm.fight_time < limit:
		await get_tree().physics_frame
		if OS.get_environment("SQUAD_DEBUG") != "" and sm.fight_time - trace_t >= 10.0:
			trace_t = sm.fight_time
			var row := []
			for d in sm.dolls():
				var br := (d as Node).get_node_or_null("SquadBrain") as SquadBrain
				var ob: Variant = br._objective(sm) if br != null else null
				row.append("%d:%s(%.0f,%.0f)->%s" % [(d as Doll).player_index, br.state if br != null else "-", (d as Doll).centre_of_mass().x,
					(d as Doll).centre_of_mass().y, str(ob)])
			print("  t=%5.1f flags=%s/%s  %s" % [sm.fight_time, sm.flag_of(0).state, sm.flag_of(1).state, " ".join(row)])
	info["ctf_bots"] = {"level": level, "fight_s": snappedf(sm.fight_time, 0.1), "score": sm.score.duplicate(), "events": ev, "frags": sm.frags.size()}
	print("  " + JSON.stringify(info["ctf_bots"]))
	_check("ctf_bots_take", int(ev.get("taken", 0)) >= 2, "флаги брали %d раз" % int(ev.get("taken", 0)))
	_check("ctf_bots_capture", int(ev.get("captured", 0)) >= 1, "доставлено флагов %d за %.0f с, счёт %s" % [int(ev.get("captured", 0)), sm.fight_time,
		str(sm.score)])
	await _unload()
