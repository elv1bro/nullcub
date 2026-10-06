## Проба «Подъём: стена» (docs/plan-demo/CLIMB.md; scripts/core/thrust_stamina.gd, ArmAssist.wall_grip, scripts/climb/, scenes/climb/,
## scenes/playground_climb.tscn). Секции (only=stamina|grip|wall|calib, несколько — через «+», пусто — все, кроме calib):
##   stamina — запас тяги на настоящей площадке: полёт тратит, рывок дороже, при 0 тяги нет (кукла падает), полный бак — 4–5 м подъёма;
##             на уступе (пол) восполняется; без узла ThrustStamina (другие режимы) — тяга как раньше, Doll.stamina = null;
##   grip    — хват за стену: рука к камню хватается, висит ≥ 10 с без проскальзывания (кисть и ЦМ ≤ 0.1 м); гладкое не хватается;
##             на двух руках запас копится, на одной — тает, на нуле одна рука срывается; отпустил кнопку — отпустил; подтягивание
##             на уступ сценарным вводом; руки P2 с клавиатуры (ClimbKeyHands) хватают и отпускают;
##   wall    — стена целиком: только полётом без рук до верха не долететь; сценарный подъём (полёт + хваты + отдых) проходит 30 м за T с;
##             падение вниз — кукла цела, у подножия снова лезет (запас восполнен, хватается);
##   calib   — замеры для подбора чисел (печать, без проверок): масса, тяга, подъём на полном баке и падение при каждой тяжести шахты.
## Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/climb_probe.tscn -- "only=stamina+grip,out=<json>"
## → JSON между === CLIMB PROBE === и === OK / FAIL ===, exit 0/1. errors_script — SCRIPT ERROR за прогон (Logger).
extends Node

const PLAYGROUND := "res://scenes/playground_climb.tscn"
const TICK := 1.0 / 60.0

## Счётчик SCRIPT ERROR за прогон (как squad_probe, puzzle_probe).
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
var errs := ScriptErrors.new()
var pg: ClimbPlayground
var trace := false
var sections_done: Array = []


func _check(id: String, cond: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": cond, "detail": str(detail)})
	if not cond:
		ok = false
	print("  %-34s %s  %s" % [id, "ok  " if cond else "FAIL", str(detail)])


func _args() -> Dictionary:
	var out := {"only": "", "out": "", "trace": "0"}
	for a in OS.get_cmdline_user_args():
		for part in String(a).split(","):
			var kv := part.split("=")
			if kv.size() == 2 and out.has(kv[0]):
				out[kv[0]] = kv[1]
	return out


func _want(a: Dictionary, section: String) -> bool:
	if String(a["only"]) == "":
		return section != "calib"
	return section in String(a["only"]).split("+")


func _ready() -> void:
	OS.add_logger(errs)
	print("=== CLIMB PROBE ===")
	var a := _args()
	trace = String(a["trace"]) == "1"
	if _want(a, "calib"):
		await _calib()
	if _want(a, "stamina"):
		await _stamina()
	if _want(a, "grip"):
		await _grip()
	if _want(a, "wall"):
		await _wall()
	await _unload()
	_check("sections_finished", sections_done.size() == _expected_sections(a), "дошли до конца: %s" % str(sections_done))
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


func _expected_sections(a: Dictionary) -> int:
	var n := 0
	for s in ["calib", "stamina", "grip", "wall"]:
		if _want(a, s):
			n += 1
	return n


# ------------------------------------------------------------------ помощники

func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait(s: float) -> void:
	await _ticks(int(ceil(s / TICK)))


func _until(cond: Callable, max_s: float) -> bool:
	for i in int(max_s / TICK):
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _load_pg(p2 := false, gravity := -1.0) -> void:
	await _unload()
	Engine.time_scale = 1.0
	pg = (load(PLAYGROUND) as PackedScene).instantiate() as ClimbPlayground
	pg.p2_on_start = p2
	pg.auto_join = false
	(pg.get_node("Match") as Match).feel_enabled = false
	add_child(pg)
	await _ticks(5)
	if gravity > 0.0:
		pg.wall.set_gravity(gravity)
	for d in pg.players():
		(d as Doll).external_input = true
		(d as Doll).input_vec = Vector2.ZERO
	await _ticks(2)


func _unload() -> void:
	if pg != null and is_instance_valid(pg):
		remove_child(pg)
		pg.queue_free()
		pg = null
		await get_tree().physics_frame


## Перенести куклу целиком: ЦМ в to; скорости — ноль; руки отпускают стену.
func _teleport(d: Doll, to: Vector3) -> void:
	for a in ClimbMatch.wall_arms(d):
		(a as ArmAssist).wall_release("probe")
		(a as ArmAssist).clear_target_override()
	var shift := to - d.centre_of_mass()
	shift.z = 0.0
	for p in d.parts.values():
		var b := p as RigidBody3D
		if b == null or not is_instance_valid(b):
			continue
		b.global_position += shift
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO


func _arms(d: Doll) -> Array:
	return ClimbMatch.wall_arms(d)


## Касания деталей куклы со статикой (детали с contact_monitor): ["Торс:Имя", …].
func _contacts(d: Doll) -> Array:
	var out: Array = []
	for p in d.parts.values():
		var rb := p as RigidBody3D
		if rb == null or not rb.contact_monitor:
			continue
		var s := PhysicsServer3D.body_get_direct_state(rb.get_rid())
		if s == null:
			continue
		for i in s.get_contact_count():
			var o := s.get_contact_collider_object(i)
			if o is StaticBody3D:
				out.append("%s:%s" % [rb.name, (o as Node).name])
	return out


func _vy(d: Doll) -> float:
	return d.com_velocity().y


func _r2(v: float) -> float:
	return snappedf(v, 0.01)


## Держит ли кукла все руки (по списку) на стене.
func _holding(d: Doll, idx: Array) -> bool:
	var a := _arms(d)
	for i in idx:
		if i >= a.size() or not (a[i] as ArmAssist).is_wall_holding():
			return false
	return true


## Рука i тянется к точке p (override) и ждёт хвата до max_s; true — схватилась.
func _reach_grab(d: Doll, i: int, p: Vector3, max_s := 1.5) -> bool:
	var arm := _arms(d)[i] as ArmAssist
	arm.set_target_override(p)
	var got: bool = await _until(func() -> bool: return arm.is_wall_holding(), max_s)
	if not got or trace:
		var g := arm.grip_global()
		print("    reach %s → %s: got %s grip %s root %s reach %.2f dist_root %.2f touch %s smooth %s com %s" % [arm.part_name, str(p), str(got),
			str(g), str(arm.root_point()), arm.reach, arm.root_point().distance_to(p), str(arm.wall_touch().get("dist", -1.0)),
			str(arm.wall_smooth_touch), str(d.centre_of_mass())])
	return got


## Обе руки тянутся к одной цели (как ЛКМ + ПКМ с одним курсором у P1) и ждут хвата обеих; → [левая, правая].
func _reach_both(d: Doll, p: Vector3, max_s := 2.0) -> Array:
	var arms := _arms(d)
	for a in arms:
		(a as ArmAssist).set_target_override(p)
	await _until(func() -> bool: return (arms[0] as ArmAssist).is_wall_holding() and (arms[1] as ArmAssist).is_wall_holding(), max_s)
	var out := [(arms[0] as ArmAssist).is_wall_holding(), (arms[1] as ArmAssist).is_wall_holding()]
	if not (out[0] and out[1]) or trace:
		for a in arms:
			var arm := a as ArmAssist
			print("    both %s → %s: got %s grip %s root %s dist_root %.2f touch %s com %s" % [arm.part_name, str(p), str(arm.is_wall_holding()),
				str(arm.grip_global()), str(arm.root_point()), arm.root_point().distance_to(p), str(arm.wall_touch().get("dist", -1.0)),
				str(d.centre_of_mass())])
	return out


## Подъём на полном баке с пола: ввод вверх держится, пока есть запас; → {rise, t_empty, vy_after, spent_rate}.
func _fly_up(d: Doll, dash: bool, max_s := 6.0) -> Dictionary:
	var st := d.stamina
	var y0 := d.centre_of_mass().y
	var peak := y0
	var t_empty := -1.0
	var t := 0.0
	d.input_vec = Vector2(0.0, 1.0)
	while t < max_s:
		if dash:
			d.request_dash()
		await get_tree().physics_frame
		t += TICK
		peak = maxf(peak, d.centre_of_mass().y)
		if t_empty < 0.0 and st != null and st.value <= 0.0:
			t_empty = t
		if t_empty > 0.0 and t > t_empty + 2.5:
			break
	var vy := _vy(d)
	d.input_vec = Vector2.ZERO
	return {"rise": peak - y0, "t_empty": t_empty, "vy_after": vy}


# ------------------------------------------------------------------ calib

func _calib() -> void:
	print("--- calib")
	var out := {}
	for g in Tuning.CLIMB_GRAVITY_STEPS:
		await _load_pg(false, float(g))
		var d := pg.p1
		await _wait(1.0)
		var row := {"mass": _r2(d.total_mass), "thrust_n": _r2(d.thrust_mass() * Tuning.MOVE_FORCE_PER_KG)}
		d.stamina.refill()
		var fly := await _fly_up(d, false)
		row["rise_full_bar"] = _r2(fly["rise"])
		row["t_empty"] = _r2(fly["t_empty"])
		row["vy_after_empty"] = _r2(fly["vy_after"])
		# падение с 10 м без ввода (x = 1.4 — мимо карниза): скорость и время
		_teleport(d, Vector3(1.4, 17.0, 0.0))
		var t := 0.0
		var vmin := 0.0
		while d.centre_of_mass().y > 7.0 and t < 40.0:
			await get_tree().physics_frame
			t += TICK
			vmin = minf(vmin, _vy(d))
		row["fall_10m_s"] = _r2(t)
		row["fall_vmin"] = _r2(vmin)
		# без запаса: полёт 2 с вверх в воздухе (узел снят)
		out["g%.0f" % float(g)] = row
		print("  g=%.0f %s" % [float(g), str(row)])
	info["calib"] = out
	sections_done.append("calib")


# ------------------------------------------------------------------ stamina

func _stamina() -> void:
	print("--- stamina")
	await _load_pg()
	var d := pg.p1
	var st := d.stamina
	_check("stamina_attached", st != null and d.get_node_or_null(ThrustStamina.NODE_NAME) == st and st.frac() >= 0.999,
		"у куклы Подъёма запас: %s, полный %s" % [str(st != null), str(st != null and st.frac() >= 0.999)])
	if st == null:
		return
	await _wait(1.0)
	# полёт вверх с пола на полном баке
	st.refill()
	var fly := await _fly_up(d, false)
	var rise := float(fly["rise"])
	var t_fly := float(fly["t_empty"])
	info["full_bar_rise_m"] = _r2(rise)
	info["full_bar_fly_s"] = _r2(t_fly)
	_check("stamina_fly_spends", t_fly > 0.0 and absf(t_fly - Tuning.CLIMB_STAMINA_MAX / Tuning.CLIMB_STAMINA_FLY_PER_S) < 0.15,
		"полёт вверх: бак пуст за %.2f с (ждём %.2f)" % [t_fly, Tuning.CLIMB_STAMINA_MAX / Tuning.CLIMB_STAMINA_FLY_PER_S])
	_check("stamina_full_bar_4_5m", rise >= 4.0 and rise <= 5.5, "полного бака хватило на %.2f м подъёма (цель 4–5 м)" % rise)
	# пустой: тяги нет — ввод вверх держится, а кукла падает (vy после 2.5 с с пустым баком)
	_check("stamina_zero_no_thrust", float(fly["vy_after"]) < -0.5 or st.on_ledge,
		"ввод вверх, бак пуст: vy %.2f м/с (падает), на полу %s" % [float(fly["vy_after"]), str(st.on_ledge)])
	# в воздухе без опоры запас не копится
	_teleport(d, Vector3(1.4, 16.0, 0.0))
	st.value = 0.0
	st.locked = true
	await _wait(1.2)
	_check("stamina_air_no_regen", st.value <= 0.01 and st.support == "", "в воздухе 1.2 с: запас %.1f, опора «%s»" % [st.value, st.support])
	# пол / уступ: восполняется
	var landed := await _until(func() -> bool: return st.on_ledge, 12.0)
	var v0 := st.value
	await _wait(2.5)
	var regen := st.value - v0
	info["ledge_regen_2_5s"] = _r2(regen)
	_check("stamina_ledge_regen", landed and regen >= 60.0 and st.support == "ledge",
		"на полу: опора «%s», за 2.5 с +%.1f (ждём ≈ %.0f)" % [st.support, regen, Tuning.CLIMB_STAMINA_LEDGE_PER_S * (2.5 - Tuning.CLIMB_STAMINA_REGEN_PAUSE_S)])
	# рывок дороже полёта
	st.refill()
	await _wait(0.5)
	var dash := await _fly_up(d, true)
	var t_dash := float(dash["t_empty"])
	info["full_bar_dash_s"] = _r2(t_dash)
	info["full_bar_dash_rise_m"] = _r2(float(dash["rise"]))
	_check("stamina_dash_spends_more", t_dash > 0.0 and t_fly / t_dash >= 1.8,
		"рывок: бак пуст за %.2f с, полёт — %.2f с (×%.2f)" % [t_dash, t_fly, t_fly / maxf(t_dash, 0.01)])
	await _until(func() -> bool: return st.on_ledge, 10.0)
	# без узла (все другие режимы): Doll.stamina = null, тяга без предела
	d.remove_child(st)
	st.queue_free()
	await _ticks(2)
	var free_fly := await _fly_free(d, 3.0)
	_check("stamina_off_default", d.stamina == null and free_fly >= 9.0 and Doll.new().stamina == null,
		"без ThrustStamina: Doll.stamina %s, за 3 с тяги вверх +%.1f м (с запасом было %.1f)" % [str(d.stamina), free_fly, rise])
	info["no_stamina_rise_3s"] = _r2(free_fly)
	sections_done.append("stamina")


## Полёт вверх s секунд без запаса (узел снят) → подъём ЦМ, м.
func _fly_free(d: Doll, s: float) -> float:
	var y0 := d.centre_of_mass().y
	var peak := y0
	d.input_vec = Vector2(0.0, 1.0)
	for i in int(s / TICK):
		await get_tree().physics_frame
		peak = maxf(peak, d.centre_of_mass().y)
	d.input_vec = Vector2.ZERO
	return peak - y0


# ------------------------------------------------------------------ grip

func _grip() -> void:
	print("--- grip")
	await _load_pg()
	var d := pg.p1
	var st := d.stamina
	var arms := _arms(d)
	_check("grip_two_arms", arms.size() == 2 and (arms[0] as ArmAssist).button == "lmb" and (arms[1] as ArmAssist).button == "rmb"
		and (arms[0] as ArmAssist).part_name == "Hand_R" and (arms[1] as ArmAssist).part_name == "Hand_L",
		"руки: %s" % str(arms.map(func(a: ArmAssist) -> String: return "%s/%s" % [a.part_name, a.button])))
	if arms.size() < 2:
		return
	var left := arms[0] as ArmAssist
	var right := arms[1] as ArmAssist
	# 1. левая рука к камню левой скалы (лицо x = −3, 15.4–19.4 м, ниже ног уступов нет) — хват и 10 с без проскальзывания
	_teleport(d, Vector3(-2.25, 18.0, 0.0))
	await _ticks(2)
	st.refill()
	var hold_pt := Vector3(-3.0, 18.7, 0.0)
	var got := await _reach_grab(d, 0, hold_pt, 1.5)
	_check("grip_climbable_grab", got, "рука к камню: схватилась %s, %s" % [str(got), str(left.last_wall)])
	if got:
		left.set_target_override(left.wall_anchor_global() + Vector3(0.3, -0.8, 0.0))   # курсор ниже руки — просто висеть
		var anchor := left.wall_anchor_global()
		await _wait(3.0)
		var c0 := d.centre_of_mass()
		var hand_max := 0.0
		var com_max := 0.0
		var v_before := st.value
		for i in int(10.0 / TICK):
			await get_tree().physics_frame
			hand_max = maxf(hand_max, left.grip_global().distance_to(anchor))
			com_max = maxf(com_max, d.centre_of_mass().distance_to(c0))
		var held := left.is_wall_holding()
		info["hold_10s"] = {"hand_max_m": _r2(hand_max), "com_drift_m": _r2(com_max), "support": st.support}
		_check("grip_hold_10s", held and hand_max <= 0.1 and com_max <= 0.1,
			"13 с на одной руке: держит %s, кисть от точки хвата ≤ %.3f м, ЦМ за 10 с ≤ %.3f м" % [str(held), hand_max, com_max])
		var drained := v_before - st.value
		_check("grip_one_hand_drains", st.support == "hand1" and drained >= 0.8 * 10.0 * -Tuning.CLIMB_STAMINA_ONE_HAND_PER_S,
			"одна рука: опора «%s», запас −%.1f за 10 с (ждём ≈ %.0f)" % [st.support, drained, 10.0 * -Tuning.CLIMB_STAMINA_ONE_HAND_PER_S])
		# отпустил кнопку — отпустил стену
		left.clear_target_override()
		await _ticks(2)
		_check("grip_release_button", not left.is_wall_holding() and String(left.last_wall.get("reason", "")) == "button",
			"кнопку отпустили: держит %s, %s" % [str(left.is_wall_holding()), str(left.last_wall.get("reason", ""))])
	# 2. гладкое (синяя плита 6–10.6 м) не хватается
	_teleport(d, Vector3(-2.25, 8.2, 0.0))
	await _ticks(2)
	var smooth_seen := false
	left.set_target_override(Vector3(-2.9, 8.9, 0.0))
	for i in int(1.5 / TICK):
		await get_tree().physics_frame
		smooth_seen = smooth_seen or left.wall_smooth_touch
	_check("grip_smooth_no_grab", not left.is_wall_holding() and smooth_seen,
		"гладкое: схватилась %s, касание гладкого %s" % [str(left.is_wall_holding()), str(smooth_seen)])
	left.clear_target_override()
	# 3. две руки под карнизом (низ y = 19.4): запас копится; одна рука на нуле — срыв
	_teleport(d, Vector3(-1.0, 18.45, 0.0))
	await _ticks(2)
	var gb := await _reach_both(d, Vector3(-1.0, 19.4, 0.0))
	var g1: bool = gb[0]
	var g2: bool = gb[1]
	_check("grip_two_hands_grab", g1 and g2, "под карнизом (одна цель на обе): левая %s, правая %s" % [str(g1), str(g2)])
	if g1 and g2:
		for a in [left, right]:
			(a as ArmAssist).set_target_override((a as ArmAssist).chest_point())   # висеть, не подтягиваться
		st.value = 30.0
		await _wait(1.0)
		var v1 := st.value
		await _wait(4.0)
		var gain := st.value - v1
		info["two_hands_regen_4s"] = _r2(gain)
		_check("grip_two_hands_regen", st.support == "hands2" and gain >= 0.8 * 4.0 * Tuning.CLIMB_STAMINA_TWO_HANDS_PER_S,
			"две руки: опора «%s», запас +%.1f за 4 с (ждём ≈ %.0f)" % [st.support, gain, 4.0 * Tuning.CLIMB_STAMINA_TWO_HANDS_PER_S])
		right.clear_target_override()
		await _ticks(2)
		st.value = 1.0
		var slipped := await _until(func() -> bool: return not left.is_wall_holding(), 1.5)
		_check("grip_slip_at_zero", slipped and String(left.last_wall.get("reason", "")) == "tired" and st.slips >= 1,
			"одна рука, запас 1: сорвалась %s (%s), срывов %d" % [str(slipped), str(left.last_wall.get("reason", "")), st.slips])
		# пока кнопка зажата — снова не хватается
		await _wait(0.6)
		_check("grip_slip_needs_release", not left.is_wall_holding(), "после срыва с зажатой кнопкой: держит %s" % str(left.is_wall_holding()))
		left.clear_target_override()
	# 4. подтягивание на уступ: висим под краем полки (x −3.2…−1.0, верх 11.1), курсор над полкой — грудь поднимается, кукла на полке
	var mantle := await _mantle(d)
	info["mantle"] = mantle
	_check("grip_mantle_onto_ledge", bool(mantle["ok"]), str(mantle))
	# 5. рука без флага (другие режимы) стену не хватает
	var plain := ArmAssist.new()
	plain.name = "PlainArm"
	plain.control_part = "Hand_R"
	await _unload()
	await _load_pg()
	d = pg.p1
	for a in _arms(d):
		d.remove_child(a)
		(a as Node).queue_free()
	d.add_child(plain)
	await _ticks(3)
	_teleport(d, Vector3(-2.25, 4.0, 0.0))
	await _ticks(2)
	plain.set_target_override(Vector3(-3.0, 4.75, 0.0))
	await _wait(1.5)
	var dist := plain.grip_global().distance_to(Vector3(-3.0, 4.75, 0.0))
	_check("grip_off_default", not plain.wall_grip and not plain.is_wall_holding() and plain.wall_body == null,
		"рука без wall_grip: держит стену %s (кисть у цели в %.2f м)" % [str(plain.is_wall_holding()), dist])
	# 6. руки P2 с клавиатуры: [ — левая тянется (стрелка влево-вверх) и хватает, стрелки не тратят запас; отпустил — отпустила
	await _p2_keys()
	sections_done.append("grip")


## Подтягивание на полку: висим двумя руками у края (x −1.0, верх 11.1), цель — над полкой, потом вглубь; отпускаем — кукла стоит на полке.
func _mantle(d: Doll) -> Dictionary:
	var st := d.stamina
	var arms := _arms(d)
	var left := arms[0] as ArmAssist
	var right := arms[1] as ArmAssist
	_teleport(d, Vector3(-0.75, 10.05, 0.0))
	await _ticks(2)
	st.refill()
	# как человек одним курсором: ЛКМ на угол полки — левая схватилась; курсор вверх-наружу — грудь выше края (не под полкой);
	# курсор над полкой, потом вглубь — грудь переваливает через край; отпустить — кукла на полке
	var g1 := await _reach_grab(d, 0, Vector3(-1.0, 11.05, 0.0), 1.5)
	if not g1:
		return {"ok": false, "why": "левая не схватилась за угол полки", "com": str(d.centre_of_mass())}
	var c0 := d.centre_of_mass()
	var peak := c0.y
	for step in [[Vector3(-0.9, 12.8, 0.0), 1.6], [Vector3(-1.4, 12.6, 0.0), 1.2], [Vector3(-2.4, 11.9, 0.0), 1.5], [Vector3(-2.8, 11.5, 0.0), 1.5]]:
		left.set_target_override(step[0])
		var t := 0.0
		while t < float(step[1]):
			await get_tree().physics_frame
			t += TICK
			peak = maxf(peak, d.centre_of_mass().y)
			if trace and int(t / TICK) % 20 == 0:
				var tb := d.torso().global_basis.x
				print("    mantle → %s t=%.1f com=%s v=%s pull=%s sh=%s anchor=%s chest=%s torso_deg=%.0f contacts %s" % [str(step[0]), t,
					str(d.centre_of_mass()), str(d.com_velocity()), str(left.wall_pull_force), str(left.root_point()), str(left.wall_anchor_global()),
					str(left.chest_point()), rad_to_deg(atan2(tb.y, tb.x)), str(_contacts(d))])
	var c1 := d.centre_of_mass()
	for a in arms:
		(a as ArmAssist).clear_target_override()
	var on := await _until(func() -> bool: return st.on_ledge and d.centre_of_mass().y > 11.15, 3.0)
	await _wait(1.0)
	var c2 := d.centre_of_mass()
	var ok2 := on and c2.y > 11.15 and c2.x < -0.9 and st.on_ledge   # ЦМ над верхом полки (11.1) и над ней по x — лежит или стоит на полке
	return {"ok": ok2, "com_start": [_r2(c0.x), _r2(c0.y)], "com_pulled": [_r2(c1.x), _r2(c1.y)], "com_end": [_r2(c2.x), _r2(c2.y)],
		"rise_m": _r2(peak - c0.y), "on_ledge": st.on_ledge, "support": st.support}


func _p2_keys() -> void:
	await _load_pg(true)
	var d2 := pg.p2
	var kh := d2.get_node_or_null(ClimbKeyHands.NODE_NAME) as ClimbKeyHands if d2 != null else null
	var kh1 := pg.p1.get_node_or_null(ClimbKeyHands.NODE_NAME)
	_check("grip_p2_keys_node", kh != null and kh1 == null, "у P2 ClimbKeyHands %s, у P1 нет %s" % [str(kh != null), str(kh1 == null)])
	if kh == null:
		return
	var st := d2.stamina
	var arms := _arms(d2)
	_teleport(d2, Vector3(-2.25, 4.0, 0.0))
	await _ticks(2)
	st.refill()
	var spent0 := st.spent_total
	d2.input_vec = Vector2(0.0, 1.0)   # «стрелка вверх» тяги — пока клавиша руки зажата, она ведёт руку, а запас не тратится
	kh.keys_override = [true, false]
	kh.arrows_override = Vector2(-1.0, 0.6)
	var got := await _until(func() -> bool: return (arms[0] as ArmAssist).is_wall_holding(), 2.0)
	var muted := st.mute and st.spent_total <= spent0 + 0.01
	kh.arrows_override = Vector2.ZERO
	await _wait(1.0)
	var still := (arms[0] as ArmAssist).is_wall_holding()
	kh.keys_override = [false, false]
	d2.input_vec = Vector2.ZERO
	await _ticks(3)
	var let_go := not (arms[0] as ArmAssist).is_wall_holding() and not st.mute
	# без стрелок свободная рука тянется к ближнему камню сама
	_teleport(d2, Vector3(-2.3, 4.0, 0.0))
	await _ticks(2)
	kh.keys_override = [true, false]
	kh.arrows_override = Vector2.ZERO
	var auto := await _until(func() -> bool: return (arms[0] as ArmAssist).is_wall_holding(), 2.0)
	kh.keys_override = [false, false]
	await _ticks(3)
	_check("grip_p2_keys", got and muted and still and let_go and auto,
		"[ со стрелкой: схватилась %s, тяга молчит и запас цел %s, держит без стрелок %s, отпустила %s; без стрелок сама к камню %s" % [
		str(got), str(muted), str(still), str(let_go), str(auto)])


# ------------------------------------------------------------------ wall

## Маршрут сценарного подъёма: [действие, цель ЦМ / курсор]. fly — лететь к точке ЦМ (ПД-удержание, тратит запас); rest_wall — обе
## руки к курсору на камне, висеть, пока запас не ≥ REST_FULL; rest_ledge — стоять, пока запас не полный; land — без ввода до опоры.
## У rest_wall третий элемент — точка ЦМ, где висеть тягой, пока руки тянутся (у камня, чтобы дотянулись обе).
const ROUTE := [
	["rest_ledge", Vector3.ZERO],
	["fly", Vector3(2.45, 3.3, 0.0)], ["rest_wall", Vector3(3.0, 3.7, 0.0), Vector3(2.5, 3.3, 0.0)],      # правая скала, камень 0–4.6
	["fly", Vector3(1.25, 4.1, 0.0)], ["rest_wall", Vector3(1.8, 4.8, 0.0), Vector3(1.25, 4.1, 0.0)],     # висим на конце правого уступа
	["fly", Vector3(1.2, 6.0, 0.0)], ["fly", Vector3(2.35, 6.2, 0.0)], ["land", Vector3.ZERO], ["rest_ledge", Vector3.ZERO],   # мимо низа уступа — на уступ 5.0
	["fly", Vector3(2.45, 8.2, 0.0)], ["rest_wall", Vector3(3.0, 8.6, 0.0), Vector3(2.5, 8.2, 0.0)],      # правая скала 5–13
	["fly", Vector3(2.1, 11.2, 0.0)], ["rest_wall", Vector3(3.0, 11.6, 0.0), Vector3(2.5, 11.2, 0.0)],    # мимо выступа 9.9–10.2
	["fly", Vector3(-1.8, 12.0, 0.0)], ["land", Vector3.ZERO], ["rest_ledge", Vector3.ZERO],              # через шахту на полку 11.1
	["fly", Vector3(-2.65, 14.6, 0.0)], ["rest_wall", Vector3(-3.2, 15.0, 0.0), Vector3(-2.7, 14.6, 0.0)],   # левая скала 11–15.4
	["fly", Vector3(-2.1, 16.6, 0.0)], ["rest_wall", Vector3(-3.0, 17.0, 0.0), Vector3(-2.5, 16.6, 0.0)],   # мимо узкого уступа 15.45
	["fly", Vector3(-1.6, 18.5, 0.0)], ["rest_wall", Vector3(-1.6, 19.4, 0.0), Vector3(-1.6, 18.5, 0.0)],   # под карнизом (низ 19.4)
	["fly", Vector3(1.3, 18.7, 0.0)], ["rest_wall", Vector3(0.6, 19.4, 0.0), Vector3(1.0, 18.8, 0.0)],     # к краю карниза, висим на кромке
	["fly", Vector3(1.3, 21.4, 0.0)], ["fly", Vector3(-0.1, 21.2, 0.0)], ["land", Vector3.ZERO], ["rest_ledge", Vector3.ZERO],   # на карниз
	["fly", Vector3(-1.6, 21.2, 0.0)], ["land", Vector3.ZERO], ["rest_ledge", Vector3.ZERO],                                   # к скале
	["fly", Vector3(-2.5, 24.0, 0.0)], ["rest_wall", Vector3(-3.0, 24.5, 0.0), Vector3(-2.5, 24.0, 0.0)],  # мимо гладкого 20.2–24 на камень
	["fly", Vector3(-2.5, 25.8, 0.0)], ["rest_wall", Vector3(-3.0, 26.2, 0.0), Vector3(-2.5, 25.8, 0.0)],
	["fly", Vector3(-2.4, 28.6, 0.0)], ["rest_wall", Vector3(-3.0, 29.0, 0.0), Vector3(-2.5, 28.6, 0.0)],   # под самым верхом
	["fly", Vector3(-2.4, 30.9, 0.0)], ["fly", Vector3(-3.9, 31.2, 0.0)], ["land", Vector3.ZERO],         # через край на плато
]
const REST_FULL := 95.0


func _wall() -> void:
	print("--- wall")
	await _load_pg()
	var d := pg.p1
	var st := d.stamina
	var m := pg.match_node
	# 1. только полётом без рук: полный бак с пола вверх — до верха (30 м) не долететь
	await _wait(0.5)
	st.refill()
	var fly := await _fly_up(d, false)
	info["no_hands_flight_rise_m"] = _r2(float(fly["rise"]))
	_check("wall_flight_only_short", float(fly["rise"]) < Tuning.CLIMB_WALL_H * 0.3,
		"только полёт с пола на полном баке: подъём %.1f м из %.0f" % [float(fly["rise"]), Tuning.CLIMB_WALL_H])
	# и без отдыха на уступах — сколько ни жми, выше одного бака не набрать (запас без опоры не копится)
	var peak := 0.0
	d.input_vec = Vector2(0.0, 1.0)
	for i in int(6.0 / TICK):
		await get_tree().physics_frame
		peak = maxf(peak, ClimbMatch.height_of(d))
	d.input_vec = Vector2.ZERO
	await _until(func() -> bool: return st.on_ledge, 8.0)
	_check("wall_flight_hold_up_6s", peak < 8.0, "6 с держать «вверх» без рук: высота ног не выше %.1f м" % peak)
	# 2. сценарный подъём: полёт + хваты + отдых на руках и уступах
	pg.restart()
	await _ticks(10)
	d = pg.p1
	d.external_input = true
	st = d.stamina
	var log: Array = []
	var ok_route := true
	for i in ROUTE.size():
		var step: Array = ROUTE[i]
		var r: Dictionary
		if String(step[0]) == "rest_wall":
			r = await _do_rest_wall(d, step[1], REST_FULL, step[2])
		else:
			r = await call("_do_" + String(step[0]), d, step[1])
		r["i"] = i
		r["act"] = step[0]
		r["h"] = _r2(ClimbMatch.height_of(d))
		r["st"] = _r2(st.value)
		log.append(r)
		if trace or not bool(r["ok"]):
			print("    route %d %s %s → %s" % [i, str(step[0]), str(step[1]), str(r)])
		if not bool(r["ok"]):
			ok_route = false
			break
	var p: Dictionary = m.players.get(0, {})
	var climb_t := float(p.get("done_t", 0.0)) if bool(p.get("done", false)) else -1.0
	info["route_log"] = log
	info["route_time_s"] = _r2(climb_t)
	info["route_falls"] = int(p.get("falls", 0))
	info["route_best_h"] = _r2(float(p.get("best_h", 0.0)))
	_check("wall_scripted_ascent", ok_route and bool(p.get("done", false)) and climb_t > 0.0 and climb_t < 240.0,
		"маршрут пройден %s, финиш %s за %.1f с (лимит 240), рекорд высоты %.1f м, шагов %d / %d" % [str(ok_route),
		str(p.get("done", false)), climb_t, float(p.get("best_h", 0.0)), log.size(), ROUTE.size()])
	if bool(p.get("done", false)):
		_check("wall_finish_best_time", ClimbMatch.best_time > 0.0 and absf(ClimbMatch.best_time - climb_t) < 0.05,
			"лучшее время сессии %.1f с, финиш %.1f с" % [ClimbMatch.best_time, climb_t])
	# 3. падение вниз: кукла цела, у подножия запас восполняется, снова хватается за камень
	var parts_n := d.parts.size()
	for a in _arms(d):
		(a as ArmAssist).clear_target_override()
	d.input_vec = Vector2.ZERO
	_teleport(d, Vector3(1.2, 24.0, 0.0))   # над шахтой, мимо края карниза (0.6) и правого уступа (1.8)
	var falls0 := int(m.players[0]["falls"])
	st.value = 0.0
	st.locked = true
	var fall_t := 0.0
	while not (st.on_ledge and ClimbMatch.height_of(d) < 1.0) and fall_t < 25.0:
		await get_tree().physics_frame
		fall_t += TICK
	var landed := fall_t < 25.0
	await _wait(1.0)
	var intact := d.alive and not d.is_broken() and d.parts.size() == parts_n and d.lost_part_names().is_empty()
	var fell_n := int(m.players[0]["falls"]) - falls0
	await _wait(2.5)
	var refilled := st.value
	var again: Dictionary = await _do_fly(d, Vector3(2.45, 3.3, 0.0))
	var regrab: Dictionary = await _do_rest_wall(d, Vector3(3.0, 3.7, 0.0), 30.0, Vector3(2.5, 3.3, 0.0))
	info["fall_24m_s"] = _r2(fall_t)
	_check("wall_fall_retry", landed and intact and fell_n >= 1 and refilled >= 90.0 and bool(again["ok"]) and bool(regrab["ok"]),
		"упал с 24 м за %.1f с: у подножия %s, цела %s (деталей %d → %d), срыв засчитан %d, запас внизу %.0f, снова к камню %s и хват %s" % [
		fall_t, str(landed), str(intact), parts_n, d.parts.size(), fell_n, refilled, str(again["ok"]), str(regrab["ok"])])
	sections_done.append("wall")


## ПД-полёт к точке ЦМ to: желаемая скорость к цели, ввод — разница скоростей + компенсация тяжести; готово ближе 0.5 м.
func _do_fly(d: Doll, to: Vector3, max_s := 6.0) -> Dictionary:
	var st := d.stamina
	for a in _arms(d):
		(a as ArmAssist).clear_target_override()
	var t := 0.0
	var g := pg.wall.gravity
	var thrust_acc := d.thrust_mass() * Tuning.MOVE_FORCE_PER_KG / maxf(d.total_mass, 1.0)
	while t < max_s:
		var c := d.centre_of_mass()
		var e := Vector2(to.x - c.x, to.y - c.y)
		if e.length() < 0.5:
			d.input_vec = Vector2.ZERO
			return {"ok": true, "t": _r2(t)}
		if st.locked:
			d.input_vec = Vector2.ZERO
			return {"ok": false, "why": "запас кончился в полёте", "com": [_r2(c.x), _r2(c.y)], "t": _r2(t)}
		var v := d.com_velocity()
		var want := (e * 2.2).limit_length(4.5)
		var u := (want - Vector2(v.x, v.y)) * 0.45 + Vector2(0.0, g / thrust_acc)
		d.input_vec = u.limit_length(1.0)
		if trace and int(t / TICK) % 15 == 0:
			print("      fly t=%.2f com=%s v=%s u=%s st=%.1f contacts %s holds %s" % [t, str(c), str(v), str(d.input_vec), st.value,
				str(_contacts(d)), str(_arms(d).map(func(a: ArmAssist) -> bool: return a.is_wall_holding()))])
		await get_tree().physics_frame
		t += TICK
	d.input_vec = Vector2.ZERO
	var c2 := d.centre_of_mass()
	return {"ok": false, "why": "не долетел", "com": [_r2(c2.x), _r2(c2.y)], "t": _r2(t)}


## Обе руки к курсору на камне (пока не схватились — висим тягой на месте), висеть до запаса ≥ REST_FULL; отпустить.
func _do_rest_wall(d: Doll, cursor: Vector3, full := REST_FULL, hover: Variant = null) -> Dictionary:
	var st := d.stamina
	var arms := _arms(d)
	var hold: Vector3 = hover if hover is Vector3 else d.centre_of_mass()
	var g := pg.wall.gravity
	var thrust_acc := d.thrust_mass() * Tuning.MOVE_FORCE_PER_KG / maxf(d.total_mass, 1.0)
	for a in arms:
		(a as ArmAssist).set_target_override(cursor)
	var t := 0.0
	var both := false
	while t < 3.0:
		var n := 0
		for a in arms:
			if (a as ArmAssist).is_wall_holding():
				n += 1
		if n >= 2:
			both = true
			break
		if n == 0 and not st.locked:   # ещё ни одной руки — держаться тягой на месте
			var c := d.centre_of_mass()
			var v := d.com_velocity()
			var u := (Vector2(hold.x - c.x, hold.y - c.y) * 2.0 - Vector2(v.x, v.y)) * 0.45 + Vector2(0.0, g / thrust_acc)
			d.input_vec = u.limit_length(1.0)
		else:
			d.input_vec = Vector2.ZERO
		await get_tree().physics_frame
		t += TICK
	d.input_vec = Vector2.ZERO
	if not both:
		var held := arms.filter(func(a: ArmAssist) -> bool: return a.is_wall_holding()).size()
		return {"ok": false, "why": "обе руки не схватились (держит %d)" % held, "com": str(d.centre_of_mass())}
	# обе держат — курсор туда, где висеть (грудь над точкой висения): тело не прижимается к камню над руками
	for a in arms:
		(a as ArmAssist).set_target_override(hold + Vector3(0.0, 0.4, 0.0))
	var t_hang := 0.0
	while st.value < full and t_hang < 14.0:
		await get_tree().physics_frame
		t_hang += TICK
	for a in arms:
		(a as ArmAssist).clear_target_override()
	await get_tree().physics_frame
	return {"ok": st.value >= full, "t_grab": _r2(t), "t_hang": _r2(t_hang)}


## Стоять на уступе (опора «ledge»), пока запас не полный.
func _do_rest_ledge(d: Doll, _v: Vector3) -> Dictionary:
	var st := d.stamina
	d.input_vec = Vector2.ZERO
	var on := await _until(func() -> bool: return st.on_ledge, 3.0)
	var full := await _until(func() -> bool: return st.value >= REST_FULL, 6.0)
	return {"ok": on and full, "on_ledge": on}


## Без ввода до опоры (уступ) — приземлиться.
func _do_land(d: Doll, _v: Vector3) -> Dictionary:
	var st := d.stamina
	d.input_vec = Vector2.ZERO
	var on := await _until(func() -> bool: return st.on_ledge, 4.0)
	var c := d.centre_of_mass()
	return {"ok": on, "com": [_r2(c.x), _r2(c.y)]}
