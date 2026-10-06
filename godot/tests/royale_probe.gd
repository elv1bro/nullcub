## Проба «Королевской битвы» (docs/plan-demo/ROYALE.md) на настоящей площадке scenes/playground_royale.tscn (Полигон, восемь бойцов,
## RoyaleMatch, RoyaleZone, RoyaleHud).
##   zone (без площадки): расписание стадий — до первого сжатия стены на краях и урона нет; ширины стадий 46 → 30 → 20 → 12 → 0;
##     стены только внутрь (окна вложены); урон снаружи 3 → 6 → 10 → 10 → 10; edges_at предсказывает стены; окно в ±18 м;
##   rules (все — боты, мозги выключены): восемь бойцов, все друг другу враги (урон по любому, и той же чётности, что в стычке была
##     командой), старт без оружия, HP и брони нет; 12 ящиков на старте (оружие — по ширине карты); подбор оружия, то же — как патроны,
##     ниже рангом — не берётся, выше — меняет, а старое остаётся ящиком; жизни, броня, патроны, бонус; без оружия патроны не берутся;
##     рука перекладывает ствол на сторону цели (переклад — пауза выстрела); зона ранит только снаружи, броня её не гасит и не
##     тратится, выбывший от зоны — «zone»; без возрождения; выбыл с оружием — оно ящиком; конец — последний живой, места по порядку
##     выбывания, итоги один раз; R — всё заново;
##   aim: ствол на точку в 8 м в десяти направлениях — с перекладом (обе стороны) и без (рука как в стычке: дальняя сторона мимо);
##     бот с пистолетом попадает по цели слева и по цели справа (переклад сам);
##   bots (P1 тоже бот): бой ботов на нескольких зёрнах — кончается одним живым за ≤ 300 с боя, все в границах карты, никто долго не
##     стоит снаружи зоны и на месте, ящики берут, стреляют и попадают; длина боя и места — в info.
## Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/royale_probe.tscn -- "only=zone|rules|aim|bots|…+…,seeds=11+22+33,level=2,max_s=330,trace=1,out=<json>"
## → JSON между === ROYALE PROBE === и === OK / FAIL ===, exit 0/1. errors_script — SCRIPT ERROR за прогон (Logger).
extends Node

const SCENE := "res://scenes/playground_royale.tscn"
const TICK := 1.0 / 60.0

## Счётчик SCRIPT ERROR за прогон (как squad_probe): ошибка скрипта обрывает только свою функцию — проба могла бы молча потерять проверки.
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
var pg: RoyalePlayground
var rm: RoyaleMatch
var over_results: Dictionary = {}
var over_count := 0
var errs := ScriptErrors.new()


func _check(id: String, cond: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": cond, "detail": str(detail)})
	if not cond:
		ok = false
	print("  %-30s %s  %s" % [id, "ok  " if cond else "FAIL", str(detail)])


func _args() -> Dictionary:
	var out := {"only": "", "seeds": "11+22+33", "level": "2", "max_s": "330", "trace": "0", "out": ""}
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
	print("=== ROYALE PROBE ===")
	var a := _args()
	if _want(a, "zone"):
		await _zone()
	if _want(a, "rules"):
		await _rules()
	if _want(a, "aim"):
		await _aim()
	if _want(a, "bots"):
		var runs: Array = []
		for s in String(a["seeds"]).split("+"):
			runs.append(await _bots(int(s), int(a["level"]), float(a["max_s"]), String(a["trace"]) == "1"))
		info["bots"] = runs
		var lens: Array = runs.map(func(r: Dictionary) -> float: return float(r["fight_s"]))
		print("  длина боёв, с: %s" % str(lens))
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

func _load(seed_: int, level := 2, countdown := 0.3) -> void:
	await _unload()
	Engine.time_scale = 1.0
	pg = (load(SCENE) as PackedScene).instantiate() as RoyalePlayground
	pg.p1_bot = true
	pg.bot_level = level
	rm = pg.get_node("Match") as RoyaleMatch
	rm.feel_enabled = false
	rm.countdown_s = countdown
	rm.rng_seed = seed_
	rm.focus_index = 0
	over_results = {}
	over_count = 0
	rm.match_over.connect(func(_w: Doll, r: Dictionary) -> void:
		over_results = r
		over_count += 1)
	add_child(pg)
	await _until(func() -> bool: return rm.play_state == "play" and rm.dolls().size() == Tuning.ROYALE_FIGHTERS, 8.0)


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
	for d in rm.dolls():
		if is_instance_valid(d) and (d as Doll).player_index == index:
			return d
	return null


func _gun(index: int) -> SquadGun:
	return SquadMatch.gun_of(_doll(index))


func _brains_off() -> void:
	for d in rm.dolls():
		var b := (d as Node).get_node_or_null(RoyalePlayground.BOT_NAME)
		if b != null:
			b.set_physics_process(false)
		(d as Doll).input_vec = Vector2.ZERO
		var g := SquadMatch.gun_of(d)
		if g != null:
			g.trigger = false


## Кукла висит в воздухе (тяга = вес) ticks тиков; рука — на tgt (если задана).
func _hover(dolls: Array, ticks: int, arm_doll: Doll = null, tgt := Vector3.ZERO) -> void:
	for i in ticks:
		for d in dolls:
			var dd := d as Doll
			if not is_instance_valid(dd) or not dd.alive:
				continue
			var br := dd.get_node_or_null(RoyalePlayground.BOT_NAME) as RoyaleBrain
			if br != null and not br.is_physics_processing():
				dd.input_vec = br.hover_vec()
		if arm_doll != null:
			SquadMatch.gun_of(arm_doll).arm().set_target_override(tgt)
		await get_tree().physics_frame


## Перенести куклу целиком (все детали) так, чтобы её ЦМ встал в to; скорости — ноль.
func _teleport(d: Doll, to: Vector3) -> void:
	var shift := to - d.centre_of_mass()
	shift.z = 0.0
	for p in d.parts.values():
		var b := p as RigidBody3D
		if b == null or not is_instance_valid(b):
			continue
		b.global_position += shift
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
		b.reset_physics_interpolation()


func _crates() -> Array:
	var out: Array = []
	for c in get_tree().get_nodes_in_group(SquadMatch.SUPPLY_GROUP):
		if c is RoyaleCrate and not (c as Node).is_queued_for_deletion():
			out.append(c)
	return out


func _clear_crates() -> void:
	for c in _crates():
		(c as Node).queue_free()


## Зона стоит на краях карты (правила и прицел — без её сжатия; урон зоны пробы правил ставят руками).
func _freeze_zone() -> void:
	var z := rm.zone
	z.stop()
	z.idx = 0
	z.shrinking = false
	z.t = 0.0
	z.left = z.map_l
	z.right = z.map_r


func _give(d: Doll, id: String) -> void:
	rm._weapons[d.player_index] = id
	rm._equip(d)


func _heal_all() -> void:
	for d in rm.dolls():
		var dd := d as Doll
		if dd.alive:
			dd.hp = dd.max_hp


# ------------------------------------------------------------------ зона (без площадки)

func _zone() -> void:
	print("--- zone")
	var z := RoyaleZone.new()
	add_child(z)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	z.setup(-32.0, 32.0, rng)
	var shrinks: Array = []
	z.stage_changed.connect(func(st: int, sh: bool) -> void:
		if sh:
			shrinks.append([st, z.dps()]))
	z.start()
	var t := 0.0
	var dt := 0.05
	var early_ok := true
	var mono_ok := true
	var prev := z.edges()
	var widths: Array = []
	var marks: Array = []
	var acc := 0.0
	for st in z.stages:
		acc += float(st["wait"]) + float(st["shrink"])
		marks.append(acc)
	var mi := 0
	var predict_err := 0.0
	var predicted := Vector2.ZERO
	var predict_at := -1.0
	while t < acc + 5.0:
		if absf(t - 25.0) < dt * 0.5:
			predicted = z.edges_at(10.0)
			predict_at = t + 10.0
		z.tick(dt)
		t += dt
		var e := z.edges()
		if t < float(z.stages[0]["wait"]) - 0.01 and (e.x > -32.0 + 0.001 or e.y < 32.0 - 0.001 or z.dps() > 0.0):
			early_ok = false
		if e.x < prev.x - 1e-4 or e.y > prev.y + 1e-4:
			mono_ok = false
		prev = e
		if predict_at > 0.0 and absf(t - predict_at) < dt * 0.5:
			predict_err = maxf(absf(predicted.x - e.x), absf(predicted.y - e.y))
		if mi < marks.size() and t >= float(marks[mi]) - 1e-4:
			widths.append(snappedf(e.y - e.x, 0.01))
			mi += 1
	var want_w: Array = []
	for st in z.stages:
		want_w.append(float(st["width"]))
	var w_ok := widths.size() == want_w.size()
	for i in mini(widths.size(), want_w.size()):
		w_ok = w_ok and absf(float(widths[i]) - float(want_w[i])) < 0.05
	var dps_seq: Array = shrinks.map(func(s: Array) -> float: return float(s[1]))
	var want_dps: Array = []
	for st in z.stages:
		want_dps.append(float(st["dps"]))
	info["zone"] = {"final_c": snappedf(z.final_c, 0.01), "widths": widths, "dps": dps_seq, "predict_err_m": snappedf(predict_err, 0.001)}
	print("  " + JSON.stringify(info["zone"]))
	_check("zone_wait_first", early_ok, "до конца первой паузы стены на краях карты, урона нет")
	_check("zone_stage_widths", w_ok, "ширина в конце стадий %s (ждём %s)" % [str(widths), str(want_w)])
	_check("zone_walls_inward", mono_ok, "стены идут только внутрь")
	_check("zone_dps", dps_seq == want_dps, "урон снаружи по стадиям %s" % str(dps_seq))
	_check("zone_window", absf(z.final_c) <= Tuning.ROYALE_ZONE_CENTER_MAX_X + 0.01, "центр окна %.1f м" % z.final_c)
	_check("zone_predict", predict_err < 0.05, "edges_at(10 с) ошибся на %.3f м" % predict_err)
	# окно случайное: на разных зёрнах — разное
	var cs: Array = []
	for s in [1, 2, 3, 4, 5]:
		rng.seed = s
		z.setup(-32.0, 32.0, rng)
		cs.append(snappedf(z.final_c, 0.1))
	_check("zone_random", cs.size() == 5 and cs.min() != cs.max(), "центры окна на пяти зёрнах %s" % str(cs))
	z.queue_free()
	await get_tree().physics_frame


# ------------------------------------------------------------------ правила

func _rules() -> void:
	print("--- rules")
	await _load(1234)
	_brains_off()
	_freeze_zone()
	var gap := INF
	for d in rm.dolls():
		for c in _crates():
			for p in (d as Doll).parts.values():
				gap = minf(gap, (p as Node3D).global_position.distance_to((c as Node3D).global_position))
	_check("spawn_off_crates", gap > Tuning.SQUAD_SUPPLY_PICK_M + 0.4, "ближайшая деталь к ящику на старте — %.1f м" % gap)
	await _wait(0.3)
	var ds := rm.dolls()
	var teams := {}
	var groups_ok := true
	for d in ds:
		teams[(d as Doll).team] = true
		groups_ok = groups_ok and (d as Node).is_in_group(RoyaleMatch.FIGHTERS_GROUP) and not (d as Node).is_in_group("squad_0") \
			and not (d as Node).is_in_group("squad_1")
	_check("fighters_8", ds.size() == 8 and teams.size() == 8 and groups_ok, "бойцов %d, команд %d, группы %s" % [ds.size(), teams.size(), groups_ok])
	var enemies := true
	for a in ds:
		for b in ds:
			if a != b and not is_equal_approx((a as Doll).team_mult_for(b), 1.0):
				enemies = false
	_check("all_enemies", enemies, "каждый бьёт каждого с множителем 1")
	var unarmed := true
	var hp_ok := true
	for d in ds:
		var g := SquadMatch.gun_of(d)
		unarmed = unarmed and g != null and g.weapon == "" and g.aim_end().is_empty()
		hp_ok = hp_ok and is_equal_approx((d as Doll).max_hp, Tuning.ROYALE_HP * rm._hp_scale()) and rm.armor_of(d) == 0.0
	_check("start_unarmed", unarmed and hp_ok, "оружия нет ни у кого, HP %.0f, брони нет" % (Tuning.ROYALE_HP * rm._hp_scale()))
	var cr := _crates()
	var by_kind := {}
	var b: AABB = pg.arena.call("bounds")
	var in_map := true
	var wx: Array = []
	for c in cr:
		var rc := c as RoyaleCrate
		var k := "weapon" if rc.is_weapon() else ("boost" if Tuning.SQUAD_BOOSTS.has(rc.kind) else rc.kind)
		by_kind[k] = int(by_kind.get(k, 0)) + 1
		in_map = in_map and b.has_point(Vector3(rc.home.x, rc.home.y, 0.0))
		if rc.is_weapon():
			wx.append(snappedf(rc.home.x, 0.1))
	wx.sort()
	var want_total := 0
	for k in Tuning.ROYALE_CRATES:
		want_total += int(Tuning.ROYALE_CRATES[k])
	var kinds_ok := by_kind.size() == Tuning.ROYALE_CRATES.size()
	for k in Tuning.ROYALE_CRATES:
		kinds_ok = kinds_ok and int(by_kind.get(k, 0)) == int(Tuning.ROYALE_CRATES[k])
	_check("crates_start", cr.size() == want_total and kinds_ok and in_map, "ящиков %d (%s), все на карте %s" % [
		cr.size(), str(by_kind), in_map])
	_check("crates_weapons_spread", wx.size() >= 2 and float(wx.front()) < -15.0 and float(wx.back()) > 15.0, "оружие по x: %s" % str(wx))
	var min_d := INF
	for i in ds.size():
		for j in range(i + 1, ds.size()):
			min_d = minf(min_d, (ds[i] as Doll).centre_of_mass().distance_to((ds[j] as Doll).centre_of_mass()))
	_check("spawns_spread", min_d > 4.0, "ближе всех двое на %.1f м" % min_d)
	# урон по любому: пары той же чётности (в стычке — одна команда); сначала — конец защиты после появления (Doll.grace_until)
	await _until(func() -> bool: return _doll(3).can_take_damage() and _doll(4).can_take_damage(), 5.0)
	_heal_all()
	var d1 := rm.bullet_hit(_doll(3), _doll(1), 10.0, "Torso", _doll(3).centre_of_mass(), Vector3.UP, "pistol")
	var d2 := rm.bullet_hit(_doll(4), _doll(2), 10.0, "Torso", _doll(4).centre_of_mass(), Vector3.UP, "pistol")
	var want_d := 10.0 * Tuning.ROYALE_BULLET_MULT   # классов нет: у всех мест пули × 1 (в стычке места 4–5 — громила, × 0.5)
	_check("damage_any", absf(d1 - want_d) < 0.01 and absf(d2 - want_d) < 0.01, "пуля 10 × %.2f: P2 → P4 %.1f, P3 → P5 %.1f" % [
		Tuning.ROYALE_BULLET_MULT, d1, d2])
	_heal_all()
	_clear_crates()
	await get_tree().physics_frame
	await _pickup_rules()
	await _hand_rules()
	await _zone_rules()
	await _ko_rules()
	await _restart_rules()
	await _unload()


## Подбор: оружие, то же — патроны, ниже — нет, выше — замена и старое ящиком; жизни, броня, патроны, бонус; без оружия патроны — нет.
func _pickup_rules() -> void:
	var d := _doll(2)
	var g := SquadMatch.gun_of(d)
	_teleport(d, Vector3(-16.0, 6.5, 0.0))
	var c1 := rm.spawn_weapon_crate("rifle", d.centre_of_mass())
	await _hover([d], 30)
	_check("pick_weapon", not is_instance_valid(c1) and g.weapon == "rifle" and g.mag == g.mag_max and rm.weapon_of(d) == "rifle",
		"взял %s, магазин %d/%d" % [g.weapon, g.mag, g.mag_max])
	g.reserve = 0
	var c2 := rm.spawn_weapon_crate("rifle", d.centre_of_mass())
	await _hover([d], 30)
	_check("pick_same_as_ammo", not is_instance_valid(c2) and g.weapon == "rifle" and g.reserve > 0, "та же винтовка — запас %d" % g.reserve)
	var c3 := rm.spawn_weapon_crate("pistol", d.centre_of_mass())
	await _hover([d], 30)
	_check("pick_lower_no", is_instance_valid(c3) and g.weapon == "rifle", "пистолет (ранг ниже) лежит: %s, в руке %s" % [is_instance_valid(c3), g.weapon])
	if is_instance_valid(c3):
		c3.queue_free()
	g.mag = 2
	g.reserve = 7
	var c4 := rm.spawn_weapon_crate("gauss", d.centre_of_mass(), 3, 9)
	await _hover([d], 30)
	var dropped: RoyaleCrate = null
	for c in _crates():
		if (c as RoyaleCrate).weapon_id == "rifle":
			dropped = c
	_check("pick_higher_swaps", not is_instance_valid(c4) and g.weapon == "gauss" and g.mag == 3 and g.reserve == 9 and dropped != null
		and dropped.mag == 2 and dropped.reserve == 7, "гаусс %d/%d, винтовка осталась ящиком %s" % [g.mag, g.reserve,
		("%d/%d" % [dropped.mag, dropped.reserve]) if dropped != null else "нет"])
	await _hover([d], 30)
	_check("dropped_not_retaken", is_instance_valid(dropped) and g.weapon == "gauss", "старое не берётся обратно")
	if is_instance_valid(dropped):
		dropped.queue_free()
	d.hp = 40.0
	var c5 := rm.spawn_crate("health", d.centre_of_mass())
	await _hover([d], 30)
	_check("pick_health", not is_instance_valid(c5) and d.hp > 40.0, "HP 40 → %.0f" % d.hp)
	var c6 := rm.spawn_crate("armor", d.centre_of_mass())
	await _hover([d], 30)
	_check("pick_armor", not is_instance_valid(c6) and rm.armor_of(d) > 0.0, "броня %.0f" % rm.armor_of(d))
	g.reserve = 0
	var c7 := rm.spawn_crate("ammo", d.centre_of_mass())
	await _hover([d], 30)
	_check("pick_ammo", not is_instance_valid(c7) and g.reserve > 0, "патроны: запас %d" % g.reserve)
	var c8 := rm.spawn_crate("rage", d.centre_of_mass())
	await _hover([d], 30)
	_check("pick_boost", not is_instance_valid(c8) and rm.boost_left(d, "rage") > 0.0, "ярость %.1f с" % rm.boost_left(d, "rage"))
	var u := _doll(5)
	_teleport(u, Vector3(-8.5, 6.5, 0.0))
	var c9 := rm.spawn_crate("ammo", u.centre_of_mass())
	await _hover([u], 30)
	_check("ammo_needs_gun", is_instance_valid(c9), "без оружия ящик патронов лежит")
	if is_instance_valid(c9):
		c9.queue_free()
	await get_tree().physics_frame


## Рука: цель справа — ствол в Hand_L (справа на экране), слева — в Hand_R; переклад — пауза выстрела.
func _hand_rules() -> void:
	var d := _doll(2)
	var g := SquadMatch.gun_of(d)
	_give(d, "pistol")
	var arm := g.arm() as RoyaleArm
	var c := d.centre_of_mass()
	await _hover([d], 50, d, c + Vector3(6.0, 0.5, 0.0))
	var right_hand := arm.part_name
	var s0 := arm.swaps
	var cd_after := 0.0
	for i in 50:
		await _hover([d], 1, d, d.centre_of_mass() + Vector3(-6.0, 0.5, 0.0))
		if arm.swaps > s0 and cd_after <= 0.0:
			cd_after = g.cooldown
	var left_hand := arm.part_name
	_check("hand_follows_target", right_hand == RoyaleArm.HAND_SCREEN_RIGHT and left_hand == RoyaleArm.HAND_SCREEN_LEFT and arm.swaps > s0,
		"цель справа — %s, слева — %s, перекладов %d" % [right_hand, left_hand, arm.swaps])
	_check("hand_swap_pause", cd_after >= Tuning.ROYALE_HAND_SWAP_S - 2.0 * TICK, "после переклада ствол молчит %.2f с" % cd_after)
	arm.clear_target_override()


## Зона ранит только снаружи; броня не гасит и не тратится; выбывший от зоны — «zone».
func _zone_rules() -> void:
	_heal_all()
	var a := _doll(2)
	var o := _doll(6)
	var o2 := _doll(7)
	_teleport(a, Vector3(-16.0, 6.5, 0.0))
	_teleport(o, Vector3(16.0, 6.5, 0.0))
	_teleport(o2, Vector3(24.0, 6.5, 0.0))
	rm.add_armor(o2, 50.0)
	var z := rm.zone
	z.idx = 1
	z.shrinking = false
	z.t = 0.0
	z.left = -20.0
	z.right = -12.0
	var hp_a := a.hp
	var hp_o := o.hp
	var hp_o2 := o2.hp
	await _hover([a, o, o2], int(2.0 / TICK))
	var lost_a := hp_a - a.hp
	var lost_o := hp_o - o.hp
	var lost_o2 := hp_o2 - o2.hp
	var want := z.dps() * 2.0
	_check("zone_inside_safe", lost_a < 0.01, "внутри потерял %.2f HP" % lost_a)
	_check("zone_outside_hurts", absf(lost_o - want) <= want * 0.2 + 0.5, "снаружи %.1f HP за 2 с (ждём %.1f при %.0f HP/с)" % [lost_o, want, z.dps()])
	_check("zone_ignores_armor", absf(lost_o2 - lost_o) < 0.6 and is_equal_approx(rm.armor_of(o2), 50.0), "в броне %.1f HP, броня %.0f" % [
		lost_o2, rm.armor_of(o2)])
	_check("zone_counts_outside", float(rm.outside_s.get(o.player_index, 0.0)) > 1.5 and float(rm.outside_s.get(a.player_index, 0.0)) < 0.01,
		"снаружи: P%d %.1f с, P%d %.1f с" % [o.player_index + 1, float(rm.outside_s.get(o.player_index, 0.0)), a.player_index + 1,
		float(rm.outside_s.get(a.player_index, 0.0))])
	o2.hp = 0.6
	await _hover([a, o, o2], int(0.6 / TICK))
	var last: Dictionary = rm.frags.back() if not rm.frags.is_empty() else {}
	_check("zone_ko_cause", not o2.alive and String(last.get("cause", "")) == "zone" and int(last.get("killer", 0)) == -1,
		"выбыл от зоны: %s, запись %s" % [not o2.alive, str(last)])
	z.left = -32.0
	z.right = 32.0
	_heal_all()


## Без возрождения; выбыл с оружием — ящик с ним; конец — последний живой, места по порядку выбывания, итоги один раз.
func _ko_rules() -> void:
	var killer := _doll(2)
	var v := _doll(6)
	_give(v, "smg")
	var gv := SquadMatch.gun_of(v)
	gv.mag = 5
	gv.reserve = 20
	var at := v.centre_of_mass()
	v.take_damage(500.0, killer, "Torso", at, Vector3.UP, "weapon")
	await _hover(rm.alive_dolls(), 10)
	var drop: RoyaleCrate = null
	for c in _crates():
		if (c as RoyaleCrate).weapon_id == "smg":
			drop = c
	var last: Dictionary = rm.frags.back() if not rm.frags.is_empty() else {}
	_check("ko_drops_weapon", drop != null and drop.mag == 5 and drop.reserve == 20 and drop.home.distance_to(at) < 3.0,
		"автомат ящиком %s" % (("%d/%d в %.1f м" % [drop.mag, drop.reserve, drop.home.distance_to(at)]) if drop != null else "нет"))
	_check("ko_feed", int(last.get("killer", -1)) == killer.player_index and int(last.get("victim", -1)) == v.player_index
		and int(last.get("place", 0)) == rm.alive_count() + 1 and int((rm.tally[killer.player_index] as Dictionary)["kills"]) == 1,
		"лента: %s" % str(last))
	await _hover(rm.alive_dolls(), int(5.0 / TICK))
	_check("no_respawn", not _doll(7).alive and not _doll(6).alive and rm.dolls().size() == 8 and rm.respawn_left(_doll(6)) < 0.0,
		"через 5 с выбывшие не вернулись, бойцов в матче %d" % rm.dolls().size())
	# конец: выбивают по очереди P1, P2, P4, P5, P6 — остаётся P3 (index 2)
	var order := [0, 1, 3, 4, 5]
	for pi in order:
		var dd := _doll(pi)
		dd.take_damage(500.0, killer, "Torso", dd.centre_of_mass(), Vector3.UP, "weapon")
		await _hover(rm.alive_dolls(), 3)
	await _until(func() -> bool: return over_count > 0, 2.0)
	await _wait(0.5)
	var pl: Dictionary = over_results.get("royale_places", {})
	var want := {2: 1, 5: 2, 4: 3, 3: 4, 1: 5, 0: 6, 6: 7, 7: 8}
	var places_ok := true
	for k in want:
		places_ok = places_ok and int(pl.get(k, -1)) == int(want[k])
	_check("end_last_alive", over_count == 1 and over_results.get("winner") == killer and rm.winner_index == 2 and rm.play_state == "over",
		"итогов %d, победитель P%d" % [over_count, rm.winner_index + 1])
	_check("end_places", places_ok, "места %s (ждём %s)" % [str(pl), str(want)])


## R: все снова живы, без оружия, 12 ящиков, зона на краях, места пусты.
func _restart_rules() -> void:
	rm.restart()
	await _until(func() -> bool: return rm.play_state == "play", 5.0)
	await get_tree().physics_frame
	_brains_off()
	var alive := rm.alive_count()
	var armed := 0
	for d in rm.dolls():
		var g := SquadMatch.gun_of(d)
		if g != null and g.weapon != "":
			armed += 1
	var want_total := 0
	for k in Tuning.ROYALE_CRATES:
		want_total += int(Tuning.ROYALE_CRATES[k])
	_check("restart", alive == 8 and armed == 0 and _crates().size() == want_total and rm.places.is_empty() and rm.zone.running
		and is_equal_approx(rm.zone.left, rm.zone.map_l), "живых %d, с оружием %d, ящиков %d, зона %s" % [alive, armed, _crates().size(),
		str(rm.zone.edges())])
	# U: P2 — человек на стрелках (мозга нет, ввод с клавиатуры p2) и снова бот
	pg.set_p2_bot(false)
	var p2 := _doll(1)
	var human_ok := not p2.external_input and p2.get_node_or_null(RoyalePlayground.BOT_NAME) == null and p2.input_prefix == "p2"
	pg.set_p2_bot(true)
	await get_tree().physics_frame
	var bot_ok := p2.external_input and p2.get_node_or_null(RoyalePlayground.BOT_NAME) != null
	_check("p2_toggle", human_ok and bot_ok, "U: P2 человек %s, снова бот %s" % [human_ok, bot_ok])


# ------------------------------------------------------------------ прицел

## Десять направлений (по пять с каждой стороны, ±60° от горизонтали), точка в 8 м; через 0.9 с — угол ствола к цели.
func _aim_dirs(d: Doll, switch_on: bool) -> Dictionary:
	var g := SquadMatch.gun_of(d)
	var arm := g.arm() as RoyaleArm
	arm.auto_switch = switch_on
	if not switch_on:
		arm.switch_to(RoyaleArm.HAND_SCREEN_RIGHT)
	var near: Array = []
	var far: Array = []
	for k in 20:
		var side := 1.0 if (k / 5) % 2 == 0 else -1.0
		var ang := deg_to_rad(-60.0 + 30.0 * float(k % 5))
		var c := d.centre_of_mass()
		var tgt := Vector3(c.x, maxf(c.y, 5.0), 0.0) + Vector3(cos(ang) * side, sin(ang), 0.0) * 8.0
		await _hover([d], 54, d, tgt)
		if k < 10:
			continue   # первый круг — разогрев
		var ray := g.aim_ray()
		if ray.is_empty():
			continue
		var to := tgt - (ray[0] as Vector3)
		to.z = 0.0
		var err := snappedf(rad_to_deg((ray[1] as Vector3).angle_to(to.normalized())), 0.1)
		(near if side > 0.0 else far).append(err)
	arm.auto_switch = true
	near.sort()
	far.sort()
	return {"right_med": near[near.size() / 2] if not near.is_empty() else 180.0, "right_worst": near.back() if not near.is_empty() else 180.0,
		"left_med": far[far.size() / 2] if not far.is_empty() else 180.0, "left_worst": far.back() if not far.is_empty() else 180.0}


func _aim() -> void:
	print("--- aim")
	await _load(4321)
	_brains_off()
	_freeze_zone()
	_clear_crates()
	var d := _doll(2)
	_teleport(d, Vector3(-16.0, 6.5, 0.0))
	_give(d, "pistol")
	await _hover([d], 30)
	var on := await _aim_dirs(d, true)
	var off := await _aim_dirs(d, false)
	info["aim"] = {"switch": on, "one_hand": off}
	print("  " + JSON.stringify(info["aim"]))
	_check("aim_both_sides", float(on["right_med"]) < 8.0 and float(on["left_med"]) < 8.0 and float(on["right_worst"]) < 20.0
		and float(on["left_worst"]) < 20.0, "с перекладом: справа %.1f° (худший %.1f°), слева %.1f° (худший %.1f°)" % [on["right_med"],
		on["right_worst"], on["left_med"], on["left_worst"]])
	_check("aim_one_hand_worse", float(off["left_med"]) > float(on["left_med"]) + 5.0, "одной рукой (как в стычке) слева %.1f° — переклад нужен" % float(off["left_med"]))
	# бот стреляет по цели слева и по цели справа
	var s := _doll(2)
	var l := _doll(3)
	var r := _doll(4)
	for pi in [0, 1, 5, 6, 7]:
		_doll(pi).knock_out()
	await get_tree().physics_frame
	for t in [l, r]:
		(t as Doll).max_hp = 10000.0
		(t as Doll).hp = 10000.0
	_teleport(s, Vector3(-16.0, 6.5, 0.0))
	_teleport(l, Vector3(-23.0, 6.5, 0.0))
	_teleport(r, Vector3(-9.0, 6.5, 0.0))
	var hits := {"l": 0, "r": 0}
	rm.bullet_landed.connect(func(v: Doll, sh: Doll, _dmg: float, _p: Vector3) -> void:
		if sh == s and v == l:
			hits["l"] = int(hits["l"]) + 1
		elif sh == s and v == r:
			hits["r"] = int(hits["r"]) + 1)
	var brain := s.get_node(RoyalePlayground.BOT_NAME) as RoyaleBrain
	var hands := {"l": {}, "r": {}}
	for phase in ["l", "r"]:
		var vis: Doll = l if phase == "l" else r
		var hid: Doll = r if phase == "l" else l
		hid.remove_from_group(RoyaleMatch.FIGHTERS_GROUP)
		if not vis.is_in_group(RoyaleMatch.FIGHTERS_GROUP):
			vis.add_to_group(RoyaleMatch.FIGHTERS_GROUP)
		brain.target = null
		brain.set_physics_process(true)
		SquadMatch.gun_of(s).reserve = 200
		for i in int(6.0 / TICK):
			await _hover([l, r], 1)
			var hn := SquadMatch.gun_of(s).arm().part_name
			(hands[phase] as Dictionary)[hn] = int((hands[phase] as Dictionary).get(hn, 0)) + 1
		brain.set_physics_process(false)
	r.add_to_group(RoyaleMatch.FIGHTERS_GROUP)
	l.add_to_group(RoyaleMatch.FIGHTERS_GROUP)
	info["aim_bot"] = {"hits": hits, "hands": hands, "shots": SquadMatch.gun_of(s).shots}
	print("  " + JSON.stringify(info["aim_bot"]))
	_check("bot_hits_left", int(hits["l"]) >= 3, "бот попал по цели слева %d раз (руки %s)" % [int(hits["l"]), str(hands["l"])])
	_check("bot_hits_right", int(hits["r"]) >= 3, "бот попал по цели справа %d раз (руки %s)" % [int(hits["r"]), str(hands["r"])])
	await _unload()


# ------------------------------------------------------------------ бой ботов

func _bots(seed_: int, level: int, max_s: float, trace: bool) -> Dictionary:
	print("--- bots (зерно %d, уровень %d)" % [seed_, level])
	await _load(seed_, level, 1.0)
	var b: AABB = pg.arena.call("bounds")
	var out_of_bounds := 0
	var last_pos: Dictionary = {}
	var stuck_max := 0.0
	var stuck_who := ""
	var hits := {"n": 0, "dmg": 0.0}
	rm.bullet_landed.connect(func(_v: Doll, _s: Doll, dmg: float, _p: Vector3) -> void:
		hits["n"] = int(hits["n"]) + 1
		hits["dmg"] = float(hits["dmg"]) + dmg)
	var taken := {"w": 0, "s": 0}
	rm.weapon_taken.connect(func(_d: Doll, _id: String, _f: String) -> void: taken["w"] = int(taken["w"]) + 1)
	rm.supply_taken.connect(func(_d: Doll, _k: String) -> void: taken["s"] = int(taken["s"]) + 1)
	var first_armed := {}
	var first_ko := -1.0
	var shots := {}
	var swaps := 0
	var trace_t := 0.0
	var t0 := Time.get_ticks_usec()
	var frames := 0
	while over_count == 0 and rm.fight_time < max_s:
		await get_tree().physics_frame
		frames += 1
		if first_ko < 0.0 and not rm.frags.is_empty():
			first_ko = rm.fight_time
		for d in rm.dolls():
			var dd := d as Doll
			var g := SquadMatch.gun_of(dd)
			if g != null:
				shots[dd.player_index] = g.shots
				if g.weapon != "" and not first_armed.has(dd.player_index):
					first_armed[dd.player_index] = snappedf(rm.fight_time, 0.1)
			if not dd.alive:
				last_pos.erase(dd.player_index)
				continue
			var c := dd.centre_of_mass()
			if c.x < b.position.x - 0.5 or c.x > b.end.x + 0.5 or c.y < b.position.y - 0.5 or c.y > b.end.y + 0.5:
				out_of_bounds += 1
			var lp: Array = last_pos.get(dd.player_index, [])
			if lp.is_empty() or (lp[0] as Vector3).distance_to(c) > 1.5:
				last_pos[dd.player_index] = [c, rm.fight_time]
			elif rm.fight_time - float(lp[1]) > stuck_max:
				stuck_max = rm.fight_time - float(lp[1])
				var br := dd.get_node_or_null(RoyalePlayground.BOT_NAME) as RoyaleBrain
				stuck_who = "P%d в (%.1f, %.1f), состояние %s" % [dd.player_index + 1, c.x, c.y, br.state if br != null else "-"]
		if trace and rm.fight_time - trace_t >= 10.0:
			trace_t = rm.fight_time
			var row := []
			for d in rm.dolls():
				var br := (d as Node).get_node_or_null(RoyalePlayground.BOT_NAME) as RoyaleBrain
				var g := SquadMatch.gun_of(d)
				row.append("%d:%s/%s %d|%d(%.0f,%.0f)%s" % [(d as Doll).player_index + 1, br.state if br != null else "-",
					g.weapon if g != null else "-", g.mag if g != null else 0, g.reserve if g != null else 0, (d as Doll).centre_of_mass().x,
					(d as Doll).centre_of_mass().y, "" if (d as Doll).alive else "†"])
			print("  t=%5.1f зона %s  %s" % [rm.fight_time, str(rm.zone.edges().snapped(Vector2(0.1, 0.1))), " ".join(row)])
			print("         физика %.1f мс, процесс %.1f мс, тел активно %d, пар %d, узлов %d" % [
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)), int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
				int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	for d in rm.dolls():
		var arm := SquadMatch.gun_of(d).arm() as RoyaleArm if SquadMatch.gun_of(d) != null else null
		if arm != null:
			swaps += arm.swaps
	var wall_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var out_max := 0.0
	var out_who := -1
	for pi in rm.outside_max:
		if float(rm.outside_max[pi]) > out_max:
			out_max = float(rm.outside_max[pi])
			out_who = int(pi)
	var shot_total := 0
	for k in shots:
		shot_total += int(shots[k])
	var kills_total := 0
	for pi in rm.tally:
		kills_total += int((rm.tally[pi] as Dictionary).get("kills", 0))
	var causes := {}
	for f in rm.frags:
		causes[String(f.get("cause", ""))] = int(causes.get(String(f.get("cause", "")), 0)) + 1
	var res := {"seed": seed_, "level": level, "over": over_count, "fight_s": snappedf(rm.fight_time, 0.1), "winner": rm.winner_index + 1,
		"places": over_results.get("royale_places", {}), "zone_stage": rm.zone.stage_no(), "first_ko_s": snappedf(first_ko, 0.1),
		"armed_at_s": first_armed, "weapons_taken": int(taken["w"]), "supplies_taken": int(taken["s"]), "weapon_swaps": rm.weapon_swaps,
		"drops": rm.drops, "resupplied": rm.crates_resupplied, "shots": shot_total, "bullet_hits": int(hits["n"]),
		"bullet_dmg": snappedf(float(hits["dmg"]), 1.0), "kills": kills_total, "ko_causes": causes, "hand_swaps": swaps,
		"outside_max_s": snappedf(out_max, 0.1), "outside_who": out_who + 1, "zone_damage": rm.zone_damage.duplicate(),
		"stuck_max_s": snappedf(stuck_max, 0.1), "stuck_who": stuck_who, "out_of_bounds": out_of_bounds,
		"ms_per_physics_frame": snappedf(wall_ms / maxf(frames, 1), 0.01)}
	print("  " + JSON.stringify(res))
	var tag := "s%d" % seed_
	_check("bots_end_%s" % tag, over_count == 1 and rm.alive_count() <= 1 and rm.fight_time <= 300.0,
		"бой кончился: %s за %.0f с, живых %d, победитель P%d" % [over_count == 1, rm.fight_time, rm.alive_count(), rm.winner_index + 1])
	_check("bots_armed_%s" % tag, first_armed.size() >= 6, "взяли оружие %d из 8 (%s)" % [first_armed.size(), str(first_armed)])
	_check("bots_shoot_%s" % tag, shot_total > 60 and int(hits["n"]) > 20, "выстрелов %d, попаданий %d" % [shot_total, int(hits["n"])])
	_check("bots_inside_%s" % tag, out_max < 12.0, "дольше всех снаружи зоны подряд P%d — %.1f с" % [out_who + 1, out_max])
	_check("bots_not_stuck_%s" % tag, stuck_max < 25.0, "дольше всего на месте (в радиусе 1.5 м) %.1f с — %s" % [stuck_max, stuck_who])
	_check("bots_in_bounds_%s" % tag, out_of_bounds == 0, "тиков вне границ карты %d" % out_of_bounds)
	await _unload()
	return res
