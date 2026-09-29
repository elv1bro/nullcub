## Проба руки мышью и захвата (docs/plan-demo/BODY_CRAFT.md §5; scripts/body/arm_assist.gd, thrown_credit.gd). Headless, мышь
## не нужна: кукла с external_input, рука — ArmAssist.set_target_override() / press_grab(). Каждый кейс — свой мир (пол 60 м,
## куклы doll.tscn / doll_dark.tscn с DollCombat, пропсы Свалки из scenes/props/scrap/). Запуск:
##   godot --headless --path . --fixed-fps 60 res://tests/arm_assist_probe.tscn                  — все кейсы, код выхода 0 = ок
##   godot --headless --path . --fixed-fps 60 res://tests/arm_assist_probe.tscn -- "case=throw_hit" — один кейс
##   godot --path . --resolution 1280x720 --fixed-fps 60 res://tests/arm_assist_probe.tscn -- "frames=1"
##       — кадры броска ящика в P2 на площадке scenes/playground_arm.tscn → docs/plan-demo/img/arm-throw-v1_{1..4}.png + лист
##         arm-throw-v1.png (2 × 2); ещё style=run|plant, dir=±1, p2x=…, plant_from=…; с --headless — тот же сценарий без картинок
## Кейсы и пороги:
##   reach     кисть приходит к цели (ошибка < ARRIVE_M) за ≤ ARRIVE_MAX_S; цель за пределами досягаемости клэмпится кругом;
##   zero_sum  мах рукой туда-сюда 5 с без тяги: ЦМ куклы в невесомости (gravity_scale 0) уходит < AIR_DRIFT_MAX_M, на полу —
##             < FLOOR_DRIFT_MAX_M по x и не поднимается > FLOOR_RISE_MAX_M; контраст — та же сила без реакции в торс (сдвиг ≫ порога);
##   throw_*   ящик 10 кг схвачен и держится, поднят, брошен — дальность/скорость (печать); throw_hit — попадание в P2: урон P1,
##             kind weapon, в окне ThrownCredit.WINDOW_S; classes — дальность броска по классам веса (печать);
##   heavy     ящик 80 кг схвачен, но с тягой вверх 2.5 с ЦМ поднимается < HEAVY_RISE_MAX_M (или срывается);
##   toggle    подсветка двумя руками не залипает; повторное нажатие отпускает; свои части не хватаются; KO отпускает; оружие в
##             кисти — клавиша бросает его и WeaponPickup не подбирает обратно REPICK_BLOCK_S.
extends Node3D

const DOLL_SCENE := "res://scenes/doll/doll.tscn"
const DOLL_DARK_SCENE := "res://scenes/doll/doll_dark.tscn"
const CRATE := "res://scenes/props/scrap/prop_wooden_crate.tscn"            # 10 кг, Breakable
const BARREL := "res://scenes/props/scrap/prop_wooden_barrel.tscn"          # 15 кг, Breakable
const METAL_BARREL := "res://scenes/props/scrap/prop_metal_barrel.tscn"     # 40 кг
const SHIP_CRATE := "res://scenes/props/scrap/prop_large_shipping_crate.tscn"   # 80 кг, 2.4 × 1.4
const BIT_HEAD := "res://scenes/props/scrap/bit_doll_head_cracked.tscn"     # 2.6 кг
const BIT_BOLT := "res://scenes/props/scrap/bit_bolt.tscn"                  # 0.3 кг
const PLAYGROUND := "res://scenes/playground_arm.tscn"

const ARRIVE_M := 0.1              # «пришла»: хват ближе к (клэмпнутой) цели
const ARRIVE_MAX_S := 1.0          # разумное время: мах рукой ~0.3–0.6 с, секунда — с запасом на мышцы, тянущие к позе
## Порог «ЦМ почти не смещается» в невесомости (gravity_scale 0, пола нет — внешних сил нет): сила помощи внутренняя, остаться может
## только «гребля» воздушным дампом машущей руки (конечности DOLL_LIMB_LINEAR_DAMP 1.5 против ядра 2.25). 5 см за 5 с = 1 см/с;
## та же сила без реакции в торс уходит в разы дальше (контраст).
const AIR_DRIFT_MAX_M := 0.05
## На полу мах перекатывает куклу за счёт трения стоп — это внешняя сила пола (ходьба), а не гребля: та же поза руки одними мышцами,
## без силы помощи, даёт ~0.19 м за 5 с. Порог — средняя скорость ≤ 0.1 м/с за 5 с (≈ 1 % Tuning.MAX_MOVE_SPEED 9 м/с);
## «взлететь рукой» = подъём ЦМ.
const FLOOR_DRIFT_MAX_M := 0.5
const FLOOR_RISE_MAX_M := 0.15
const HEAVY_RISE_MAX_M := 0.5
const SWING_PERIOD_S := 0.8        # zero_sum: цель меняет сторону каждые 0.4 с
const SWING_S := 5.0
const RELEASE_MIN_V := 1.0         # м/с: бросок одной рукой отпускает после пика скорости предмета вдоль броска выше этой
const SWING_FROM_DEG := -60.0      # бросок одной рукой: угол цели от вертикали «вверх» (< 0 — от броска: правая рука внутрь, к голове)
const SWING_TO_DEG := 120.0        # … до угла в сторону броска (через верх), градусы
const SWING_DEG_S := 360.0         # скорость дуги (рывок мышью: −60° → 15° за 0.2 с)
const SWING_RELEASE_DEG := 15.0    # отпустить, когда цель прошла этот угол: кисть отстаёт и ещё у верха — летит вперёд-вверх
const CARRY_S := 0.5               # бросок с разбегом: подержать предмет над головой без тяги (успокоить мах после подъёма)
const RUN_A_S := 0.35              # бросок с разбегом: тяга с предметом над головой
const RUN_B_S := 0.25              # … и мах вперёд-вверх не прекращая тяги, отпустить в конце
## style "plant": тот же разбег, но с доли PLANT_FROM маха — тяга назад (упереться ногами): кукла тормозит, ящик уходит вперёд
## на руке и бросивший не догоняет его телом
const PLANT_FROM := 0.5
## «Ящик улетает»: с разбегом 10 кг уходит быстрее 3 м/с и падает дальше 2 м (g = 2: кукла на тяге сама несётся до 9 м/с).
const THROW_MIN_M := 2.0
## throw_hit: жертва стоит на пути ящика с разбега (ящик пролетает x −2.3 на высоте ~0.6 м) и опустила руки: Т-руки тянутся на 0.9 м к
## бросившему, и его рука, догоняющая по инерции, била бы их раньше ящика (удар kind body, не зачёт броска)
const P2_X := -2.7
const BRAKE_S := 0.4               # после броска бросивший тормозит тягой назад столько секунд
## кадры: P2 на площадке (P1 на 1.35, ящик Crate на 0 — как в throw_hit, P1 − 1.35). Бросок влево: правая рука куклы живёт на −X
## (вправо — только через голову, ящик отстаёт от бегущего). Левее x −1.5 ящику (1 м в глубину) мешает столб Platforms/Support_2
## (z −2.4…−0.4 заходит в плоскость боя) — P2 стоит перед ним, в 3 м от P1.
const FRAMES_P2_X := -1.65
const THROW_MIN_V := 3.0

var case_filter := ""
var frames_mode := false
var frames_style := "plant"
var frames_dir := -1.0
var plant_from := PLANT_FROM
var frames_p2_x := FRAMES_P2_X
var checks: Array = []
var info: Dictionary = {}
var world: Node3D


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			match p[0]:
				"case": case_filter = p[1]
				"frames": frames_mode = p[1] == "1"
				"style": frames_style = p[1]
				"p2x": frames_p2_x = float(p[1])
				"dir": frames_dir = float(p[1])
				"plant_from": plant_from = float(p[1])
	_run.call_deferred()


func _run() -> void:
	if frames_mode:
		await _frames()
		get_tree().quit(0)
		return
	var cases := ["reach", "zero_sum", "throw_far", "throw_hit", "classes", "heavy", "toggle"]
	for c in cases:
		if case_filter != "" and case_filter != c:
			continue
		print("--- case ", c)
		await call("_case_" + c)
		_clear_world()
		await _ticks(2)
	var ok := true
	print("=== ARM ASSIST PROBE ===")
	for ch in checks:
		print("  %-34s %s  value=%s  limit=%s  %s" % [ch["id"], "ok " if ch["ok"] else "FAIL", str(ch["value"]), str(ch["limit"]), ch.get("note", "")])
		ok = ok and bool(ch["ok"])
	print("info: ", JSON.stringify(info))
	print("RESULT: ", "OK" if ok else "FAIL", " (", checks.size(), " checks)")
	get_tree().quit(0 if ok else 1)


func _check(id: String, ok: bool, value: Variant, limit: Variant, note: String = "") -> void:
	checks.append({"id": id, "ok": ok, "value": value, "limit": limit, "note": note})


func _ticks(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


# ------------------------------------------------------------------ мир

func _new_world() -> Node3D:
	_clear_world()
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 1, 4)
	cs.shape = bs
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	world.add_child(floor_body)
	return world


func _clear_world() -> void:
	if world != null and is_instance_valid(world):
		remove_child(world)
		world.free()
	world = null


func _spawn_doll(scene: String, x: float, prefix: String, idx: int, with_arm: bool) -> Doll:
	var d: Doll = (load(scene) as PackedScene).instantiate()
	d.name = prefix.to_upper()
	d.external_input = true
	d.player_index = idx
	d.input_prefix = prefix
	d.position = Vector3(x, 0.05, 0)
	world.add_child(d)
	var dc := DollCombat.new()
	dc.name = "DollCombat"
	d.add_child(dc)
	if with_arm:
		ArmAssist.attach_to(d)
	return d


func _arm(d: Doll) -> ArmAssist:
	return d.get_node("ArmAssist") as ArmAssist


## Статичная тумба (верх на top_y): мелочь с пола стоящая кукла не достаёт (нижняя точка кисти ≈ 0.8 м, радиус 0.4) — кладём
## её на высоту ящика, как на Свалке кладут на настилы.
func _pedestal(x: float, top_y: float, w: float = 0.5) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, top_y, 1.0)
	cs.shape = bs
	sb.add_child(cs)
	sb.position = Vector3(x, top_y / 2.0, 0)
	world.add_child(sb)


func _spawn_prop(path: String, pos: Vector3) -> RigidBody3D:
	var b: RigidBody3D = (load(path) as PackedScene).instantiate()
	world.add_child(b)
	b.global_position = pos
	return b


static func _com_velocity(d: Doll) -> Vector3:
	var acc := Vector3.ZERO
	var m := 0.0
	for b in d.parts.values():
		acc += (b as RigidBody3D).linear_velocity * (b as RigidBody3D).mass
		m += (b as RigidBody3D).mass
	return acc / maxf(m, 0.001)


## Центр масс предмета в мире.
static func _body_com(b: RigidBody3D) -> Vector3:
	var st := PhysicsServer3D.body_get_direct_state(b.get_rid())
	return b.global_position + (st.center_of_mass if st != null else Vector3.ZERO)


# ------------------------------------------------------------------ reach

func _case_reach() -> void:
	_new_world()
	var p1 := _spawn_doll(DOLL_SCENE, 0.0, "p1", 0, true)
	var arm := _arm(p1)
	await _ticks(50)
	var root := arm.root_point()
	info["reach_m"] = snappedf(arm.reach, 0.001)
	info["root"] = [snappedf(root.x, 0.01), snappedf(root.y, 0.01)]
	_check("reach_chain_len", arm.reach > 0.6 and arm.reach < 0.8, snappedf(arm.reach, 0.001), "0.6–0.8", "плечо→локоть→запястье→хват")
	# цели относительно плеча (правая рука куклы — на −X экрана; поперёк тела её не пускает лимит плеча: внутрь 25°, наружу 170°):
	# вбок-вверх, над головой, вбок-вниз, вниз вдоль тела
	var offs := {"side_up": Vector3(-0.55, 0.25, 0), "overhead": Vector3(-0.05, 0.62, 0), "out_low": Vector3(-0.45, -0.35, 0), "down": Vector3(-0.1, -0.6, 0)}
	var times := {}
	for key in offs:
		var tgt: Vector3 = arm.root_point() + offs[key]
		arm.set_target_override(tgt)
		var t_arrive := -1.0
		var err := INF
		for i in range(int(2.0 * 60)):
			await _ticks(1)
			var ct := arm.clamp_to_reach(tgt)
			err = arm.grip_global().distance_to(ct)
			if err < ARRIVE_M and t_arrive < 0.0:
				t_arrive = (i + 1) / 60.0
			if t_arrive >= 0.0 and (i + 1) / 60.0 > t_arrive + 0.3:
				break
		times[key] = {"arrive_s": snappedf(t_arrive, 0.01), "err_m": snappedf(err, 0.003),
			"grip": [snappedf(arm.grip_global().x, 0.01), snappedf(arm.grip_global().y, 0.01)], "target": [snappedf(tgt.x, 0.01), snappedf(tgt.y, 0.01)]}
		_check("reach_arrive_" + key, t_arrive >= 0.0 and t_arrive <= ARRIVE_MAX_S, snappedf(t_arrive, 0.01), "≤ %.1f s, err < %.2f m" % [ARRIVE_MAX_S, ARRIVE_M], "err %.3f м" % err)
	# цель вне досягаемости: клэмп кругом, кисть у края круга
	var far := arm.root_point() + Vector3(-3.0, 2.0, 0)
	arm.set_target_override(far)
	await _ticks(60)
	var ct2 := arm.clamp_to_reach(far)
	var root_d := arm.root_point().distance_to(arm.target)
	var err2 := arm.grip_global().distance_to(ct2)
	_check("reach_clamped", root_d <= arm.reach * ArmAssist.REACH_FRAC + 0.01 and err2 < ARRIVE_M * 1.5, snappedf(err2, 0.003), "цель ≤ reach, err < 0.15", "|root→target| %.3f м" % root_d)
	times["far"] = {"err_m": snappedf(err2, 0.003), "root_to_target": snappedf(root_d, 0.003)}
	arm.clear_target_override()
	await _ticks(60)
	_check("reach_release_no_force", arm.last_assist_force.length() < 1e-6, arm.last_assist_force.length(), "0", "отпустил — силы нет")
	info["reach"] = times


# ------------------------------------------------------------------ zero_sum

## Мах рукой туда-сюда SWING_S без тяги: ЦМ (и в невесомости, и на полу); reaction=false — контраст.
func _swing_run(air: bool, reaction: bool) -> Dictionary:
	_new_world()
	var p1 := _spawn_doll(DOLL_SCENE, 0.0, "p1", 0, true)
	var arm := _arm(p1)
	arm.reaction_to_torso = reaction
	if air:
		p1.position.y = 4.0
		for b in p1.parts.values():
			(b as RigidBody3D).gravity_scale = 0.0
	await _ticks(50)
	var c0 := p1.centre_of_mass()
	var rot0 := p1.torso().global_rotation.z
	var max_dx := 0.0
	var max_dy := 0.0
	var max_d := 0.0
	var fsum := 0.0
	var n := int(SWING_S * 60)
	for i in range(n):
		# мах туда-сюда по дуге ~120°: над головой ↔ вбок-вниз (правая рука живёт на −X: лимит плеча внутрь 25°)
		var up := int(i / (SWING_PERIOD_S * 30.0)) % 2 == 0
		arm.set_target_override(arm.root_point() + (Vector3(-0.1, 0.62, 0) if up else Vector3(-0.55, -0.3, 0)))
		await _ticks(1)
		var c := p1.centre_of_mass() - c0
		max_dx = maxf(max_dx, absf(c.x))
		max_dy = maxf(max_dy, c.y)
		max_d = maxf(max_d, Vector2(c.x, c.y).length())
		fsum += arm.last_assist_force.length()
	arm.clear_target_override()
	var c_end := p1.centre_of_mass() - c0
	var out := {"max_dx": snappedf(max_dx, 0.001), "max_rise": snappedf(max_dy, 0.001), "max_d": snappedf(max_d, 0.001),
		"end_dx": snappedf(c_end.x, 0.001), "end_dy": snappedf(c_end.y, 0.001), "mean_force_n": snappedf(fsum / n, 0.1),
		"torso_rot_deg": snappedf(rad_to_deg(wrapf(p1.torso().global_rotation.z - rot0, -PI, PI)), 0.1)}
	return out


func _case_zero_sum() -> void:
	var air := await _swing_run(true, true)
	var air_cheat := await _swing_run(true, false)
	var fl := await _swing_run(false, true)
	var fl_cheat := await _swing_run(false, false)
	info["zero_sum"] = {"air": air, "air_no_reaction": air_cheat, "floor": fl, "floor_no_reaction": fl_cheat}
	print("zero_sum: ", JSON.stringify(info["zero_sum"]))
	_check("zero_sum_air_drift", float(air["max_d"]) < AIR_DRIFT_MAX_M, air["max_d"], "< %.2f m" % AIR_DRIFT_MAX_M, "без реакции: %.2f м" % air_cheat["max_d"])
	_check("zero_sum_air_contrast", float(air_cheat["max_d"]) > 5.0 * maxf(float(air["max_d"]), 0.05), air_cheat["max_d"], "> 5× с реакцией", "та же сила без −F в торс гребёт")
	_check("zero_sum_floor_dx", float(fl["max_dx"]) < FLOOR_DRIFT_MAX_M, fl["max_dx"], "< %.2f m" % FLOOR_DRIFT_MAX_M, "без реакции: %.2f м" % fl_cheat["max_dx"])
	_check("zero_sum_floor_rise", float(fl["max_rise"]) < FLOOR_RISE_MAX_M, fl["max_rise"], "< %.2f m" % FLOOR_RISE_MAX_M, "без реакции: %.2f м" % fl_cheat["max_rise"])


# ------------------------------------------------------------------ бросок

## Сценарий броска правой кистью в сторону dir_sign (−1 = влево, куда смотрит правая рука): дотянуться до предмета, схватить,
## поднять над головой, затем
##   style "run"   — разбег (тяга в сторону броска RUN_A_S с предметом над головой), мах вперёд-вверх RUN_B_S не прекращая
##                   тяги и отпустить в конце маха (фиксированное время — детерминированно; так бросает игрок: тело + рука);
##   style "swing" — одной рукой без разбега: кисть к плечу, «толчок ядра» наружу-вверх, отпустить после пика скорости предмета
##                   вдоль броска (> RELEASE_MIN_V и упала ниже 85 % максимума).
## Возвращает телеметрию и credit_hits (удары ThrownCredit по сигналу, since_release_s < 0 — удар ещё в руке); предмет летит дальше —
## за ним следит _track_flight.
func _throw(p1: Doll, arm: ArmAssist, item: RigidBody3D, dir_sign: float, style: String = "run", lift_s: float = 0.8, shots: Variant = null) -> Dictionary:
	var out := {"grabbed": false, "style": style, "credit_hits": []}
	# 1. дотянуться: цель — ближайшая к плечу точка предмета, чуть выше
	var t0 := 0
	while t0 < 90:
		var cp := arm.closest_point(item, arm.root_point())
		arm.set_target_override(cp + Vector3(0, 0.08, 0))
		await _ticks(1)
		t0 += 1
		if arm.candidate == item:
			break
	out["reach_ticks"] = t0
	await _capture(shots)
	arm.press_grab()
	await _ticks(1)
	out["grabbed"] = arm.held == item
	if not out["grabbed"]:
		return out
	var tc := ThrownCredit.of(item)
	if tc != null:
		var ch: Array = out["credit_hits"]
		tc.hit_delivered.connect(func(victim: Doll, damage: float, speed: float) -> void:
			var h: Dictionary = tc.hits[tc.hits.size() - 1]
			ch.append({"victim": String(victim.name), "part": h["part"], "damage": snappedf(damage, 0.01), "speed": snappedf(speed, 0.01),
				"since_release_s": snappedf(float(h["since_release"]), 0.01)}))
	# 2. поднять: цель над плечом
	var y0 := _body_com(item).y
	var hold_max := 0.0
	for i in range(int(lift_s * 60)):
		arm.set_target_override(arm.root_point() + Vector3(-dir_sign * 0.15, arm.reach, 0))
		await _ticks(1)
		hold_max = maxf(hold_max, arm.hold_distance())
	out["lift_m"] = snappedf(_body_com(item).y - y0, 0.01)
	out["held_after_lift"] = arm.held == item
	var swing_ticks := 0
	if style == "run" or style == "plant":
		var run := Vector2(dir_sign, 0.2)
		for i in range(int(CARRY_S * 60)):   # предмет над головой успокаивается (после подъёма он ещё качается)
			arm.set_target_override(arm.root_point() + arm.reach * Vector3(-dir_sign * 0.25, 0.97, 0))
			await _ticks(1)
		for i in range(int(RUN_A_S * 60)):
			arm.set_target_override(arm.root_point() + arm.reach * Vector3(-dir_sign * 0.25, 0.97, 0))
			p1.input_vec = run
			await _ticks(1)
			hold_max = maxf(hold_max, arm.hold_distance())
			if i == int(RUN_A_S * 60) - 1:
				await _capture(shots)
			if OS.get_environment("ARM_TRACE") == "1":
				print("  runA t%02d stretch=%.3f hold_f=%.0f assist_f=%.0f item_v(%.2f,%.2f) torso_v(%.2f,%.2f)" % [i, arm.hold_distance(), arm.last_hold_force.length(), arm.last_assist_force.length(), item.linear_velocity.x, item.linear_velocity.y, p1.torso().linear_velocity.x, p1.torso().linear_velocity.y])
		for i in range(int(RUN_B_S * 60)):
			arm.set_target_override(arm.root_point() + arm.reach * Vector3(dir_sign * cos(deg_to_rad(20.0)), sin(deg_to_rad(20.0)), 0))
			p1.input_vec = run if style == "run" or i < int(RUN_B_S * 60 * plant_from) else Vector2(-dir_sign, 0.2)
			await _ticks(1)
			swing_ticks += 1
			hold_max = maxf(hold_max, arm.hold_distance())
	else:
		# «рывок мышью» по дуге досягаемости: цель по кругу 0.9·reach от SWING_FROM_DEG (над головой, чуть внутрь) против броска через
		# верх к SWING_TO_DEG со скоростью SWING_DEG_S, отпустить, когда цель прошла SWING_RELEASE_DEG (кисть идёт почти горизонтально)
		var ang := SWING_FROM_DEG
		for i in range(20):
			arm.set_target_override(arm.root_point() + _arc(ang, dir_sign) * arm.reach * 0.9)
			await _ticks(1)
		while ang < SWING_TO_DEG + 30.0:
			ang += SWING_DEG_S / 60.0
			arm.set_target_override(arm.root_point() + _arc(minf(ang, SWING_TO_DEG), dir_sign) * arm.reach * 0.9)
			await _ticks(1)
			swing_ticks += 1
			hold_max = maxf(hold_max, arm.hold_distance())
			if ang >= SWING_RELEASE_DEG:
				break
	out["held_before_release"] = arm.held == item
	out["hold_stretch_max_m"] = snappedf(hold_max, 0.003)
	arm.press_grab()
	await _ticks(1)
	p1.input_vec = Vector2.ZERO
	arm.clear_target_override()
	out["released"] = arm.held == null and out["held_before_release"]
	out["swing_ticks"] = swing_ticks
	var v: Vector3 = arm.last_release.get("velocity", item.linear_velocity)
	var pos: Vector3 = arm.last_release.get("position", item.global_position)
	out["release_speed"] = snappedf(v.length(), 0.01)
	out["release_v"] = [snappedf(v.x, 0.01), snappedf(v.y, 0.01)]
	out["release_pos"] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)]
	return out


## Точка на дуге вокруг плеча: угол от вертикали «вверх», положительный — в сторону броска (dir_sign), отрицательный — от него.
static func _arc(deg: float, dir_sign: float) -> Vector3:
	var a := deg_to_rad(deg)
	return Vector3(dir_sign * sin(a), cos(a), 0)


## Полёт предмета после броска: до покоя (скорость < 0.3 м/с 0.3 с) или max_s. Дальность — |Δx| от точки отпускания до места покоя.
func _track_flight(item: RigidBody3D, from: Vector3, max_s: float = 5.0, brake: Doll = null, brake_dir: float = 0.0) -> Dictionary:
	var apex := from.y
	var still := 0
	var t := 0.0
	var first_ground := -1.0
	var x_ground := from.x
	while t < max_s:
		if brake != null:
			brake.input_vec = Vector2(-brake_dir, 0.3) if t < BRAKE_S else Vector2.ZERO   # бросивший тормозит — не таранит жертву телом
		await _ticks(1)
		t += 1.0 / 60.0
		if not is_instance_valid(item):
			break
		apex = maxf(apex, item.global_position.y)
		if first_ground < 0.0 and t > 0.1 and item.contact_monitor and item.get_colliding_bodies().size() > 0:
			first_ground = t
			x_ground = item.global_position.x
		if item.linear_velocity.length() < 0.3:
			still += 1
			if still > 18:
				break
		else:
			still = 0
	var rest := item.global_position if is_instance_valid(item) else from
	return {"distance_rest_m": snappedf(absf(rest.x - from.x), 0.01), "distance_first_contact_m": snappedf(absf(x_ground - from.x), 0.01),
		"first_contact_s": snappedf(first_ground, 0.01), "apex_rise_m": snappedf(apex - from.y, 0.01), "flight_s": snappedf(t, 0.01)}


func _case_throw_far() -> void:
	for style in ["run", "swing", "plant"]:
		_new_world()
		var p1 := _spawn_doll(DOLL_SCENE, 0.0, "p1", 0, true)
		var arm := _arm(p1)
		var crate := _spawn_prop(CRATE, Vector3(-1.35, 0.02, 0))
		await _ticks(50)
		var r := await _throw(p1, arm, crate, -1.0, style)
		if style == "run":
			_check("throw_grab_10kg", bool(r["grabbed"]), r["grabbed"], true, "ящик 10 кг в радиусе %.1f м" % ArmAssist.GRAB_RADIUS)
		if not r["grabbed"]:
			info["throw_far_" + style] = r
			continue
		var from := Vector3(float(r["release_pos"][0]), float(r["release_pos"][1]), 0)
		r.merge(await _track_flight(crate, from, 5.0, p1 if style == "plant" else null, -1.0))
		r["crate_ahead_m"] = snappedf(p1.torso().global_position.x - crate.global_position.x, 0.01)   # > 0 — ящик впереди бросившего
		r.erase("credit_hits")
		info["throw_far_" + style] = r
		print("throw_far ", style, ": ", JSON.stringify(r))
		if style == "run":
			_check("throw_hold_10kg", bool(r["held_before_release"]) and float(r["lift_m"]) > 0.3, r["lift_m"], "держит до броска, подъём > 0.3 м",
				"растяжение хвата ≤ %.3f м" % r["hold_stretch_max_m"])
			_check("throw_released", bool(r["released"]), r["released"], true)
			_check("throw_flies", float(r["distance_first_contact_m"]) > THROW_MIN_M and float(r["release_speed"]) > THROW_MIN_V, r["distance_first_contact_m"],
				"> %.1f m, v > %.1f m/s" % [THROW_MIN_M, THROW_MIN_V], "v = %.2f м/с, до покоя %.2f м" % [r["release_speed"], r["distance_rest_m"]])


func _case_throw_hit() -> void:
	_new_world()
	var p1 := _spawn_doll(DOLL_SCENE, 0.0, "p1", 0, true)
	var p2 := _spawn_doll(DOLL_DARK_SCENE, P2_X, "p2", 1, false)
	p2.set_pose({"Shoulder": 8.0})
	var arm := _arm(p1)
	var crate := _spawn_prop(CRATE, Vector3(-1.35, 0.02, 0))
	var hits: Array = []
	p2.damaged.connect(func(amount: float, attacker: Node, part: String, _pos: Vector3, kind: String) -> void:
		hits.append({"amount": snappedf(amount, 0.01), "attacker": attacker.name if attacker != null else "", "part": part, "kind": kind,
			"t": Time.get_ticks_msec()}))
	await _ticks(50)
	var hp0 := p2.hp
	var r := await _throw(p1, arm, crate, -1.0, "run")
	if not r["grabbed"]:
		_check("hit_grabbed", false, false, true)
		return
	var tc := ThrownCredit.of(crate)
	var credit_hits: Array = r["credit_hits"]
	var from := Vector3(float(r["release_pos"][0]), float(r["release_pos"][1]), 0)
	var fl := await _track_flight(crate, from, 3.0, p1, -1.0)
	r.merge(fl)
	r["credit_alive_after_3s"] = is_instance_valid(tc)
	r["p2_hits"] = hits
	r["p2_hp"] = [hp0, p2.hp]
	r["p1_damage_dealt"] = snappedf(float(p1.stats["damage_dealt"]), 0.01)
	r["p1_weapon_hits"] = int(p1.stats["weapon_hits"])
	info["throw_hit"] = r
	print("throw_hit: ", JSON.stringify(r))
	var weapon_by_p1 := false
	for h in hits:
		if h["kind"] == "weapon" and h["attacker"] == "P1" and float(h["amount"]) > 0.0:
			weapon_by_p1 = true
	_check("hit_damage_p2", p2.hp < hp0, snappedf(hp0 - p2.hp, 0.01), "> 0 HP", "HP %.1f → %.1f" % [hp0, p2.hp])
	_check("hit_credit_p1_weapon", weapon_by_p1 and float(r["p1_damage_dealt"]) > 0.0, weapon_by_p1, "kind weapon, attacker P1", "P1 damage_dealt %.2f, weapon_hits %d" % [r["p1_damage_dealt"], r["p1_weapon_hits"]])
	var in_window := credit_hits.size() > 0
	for h in credit_hits:
		in_window = in_window and float(h["since_release_s"]) >= 0.0 and float(h["since_release_s"]) <= ThrownCredit.WINDOW_S
	_check("hit_in_window", in_window, credit_hits.map(func(h: Dictionary) -> float: return h["since_release_s"]), "0 … %.1f s" % ThrownCredit.WINDOW_S)


## Классы веса: броски с разбегом (run) и одной рукой (swing) для болта 0.3, головы 2.6, ящика 10, бочки 15 и железной бочки 40 кг
## (печать; проверка — лёгкий ящик с разбегом улетает дальше железной бочки).
func _case_classes() -> void:
	var rows := {}
	for e in [["bolt_0.3", BIT_BOLT, Vector3(-1.05, 0.72, 0)], ["head_2.6", BIT_HEAD, Vector3(-1.05, 0.72, 0)], ["crate_10", CRATE, Vector3(-1.35, 0.02, 0)],
			["barrel_15", BARREL, Vector3(-1.2, 0.02, 0)], ["metal_barrel_40", METAL_BARREL, Vector3(-1.15, 0.02, 0)]]:
		for style in ["run", "swing"]:
			_new_world()
			var p1 := _spawn_doll(DOLL_SCENE, 0.0, "p1", 0, true)
			var arm := _arm(p1)
			var pos: Vector3 = e[2]
			if pos.y > 0.1:
				_pedestal(pos.x, pos.y - 0.02)
			var item := _spawn_prop(e[1], pos)
			await _ticks(50)
			var r := await _throw(p1, arm, item, -1.0, style)
			if r["grabbed"]:
				var from := Vector3(float(r["release_pos"][0]), float(r["release_pos"][1]), 0)
				r.merge(await _track_flight(item, from, 5.0))
			var key := "%s_%s" % [e[0], style]
			rows[key] = {"grabbed": r["grabbed"], "held_to_release": r.get("held_before_release", false), "lift_m": r.get("lift_m", 0.0),
				"release_speed": r.get("release_speed", 0.0), "distance_first_contact_m": r.get("distance_first_contact_m", 0.0),
				"distance_rest_m": r.get("distance_rest_m", 0.0), "stretch_m": r.get("hold_stretch_max_m", 0.0)}
			print("classes ", key, ": ", JSON.stringify(rows[key]))
	info["classes"] = rows
	var light: Dictionary = rows["crate_10_run"]
	var medium: Dictionary = rows["metal_barrel_40_run"]
	_check("classes_light_farther", float(light["distance_first_contact_m"]) > float(medium["distance_first_contact_m"]) + 1.0, light["distance_first_contact_m"],
		"> 40 кг + 1 м: %.2f" % medium["distance_first_contact_m"])


# ------------------------------------------------------------------ тяжёлый

func _case_heavy() -> void:
	_new_world()
	var p1 := _spawn_doll(DOLL_SCENE, 0.0, "p1", 0, true)
	var arm := _arm(p1)
	var big := _spawn_prop(SHIP_CRATE, Vector3(-2.05, 0.02, 0))   # 2.4 × 1.4: правый край x = −0.85
	await _ticks(50)
	var t0 := 0
	while t0 < 90:
		arm.set_target_override(arm.closest_point(big, arm.root_point()) + Vector3(0, 0.05, 0))
		await _ticks(1)
		t0 += 1
		if arm.candidate == big:
			break
	arm.press_grab()
	await _ticks(1)
	var grabbed := arm.held == big
	_check("heavy_grab_80kg", grabbed, grabbed, true, "схватить можно")
	var y0 := _body_com(big).y
	var x0 := _body_com(big).x
	var rise := 0.0
	var slip_t := -1.0
	for i in range(150):
		arm.set_target_override(arm.root_point() + Vector3(0.1, arm.reach, 0))
		p1.input_vec = Vector2(0.3, 1.0)   # тяга вверх (и чуть от ящика) изо всех сил
		await _ticks(1)
		if is_instance_valid(big):
			rise = maxf(rise, _body_com(big).y - y0)
		if slip_t < 0.0 and arm.held == null:
			slip_t = (i + 1) / 60.0
	p1.input_vec = Vector2.ZERO
	arm.clear_target_override()
	var r := {"grabbed": grabbed, "rise_max_m": snappedf(rise, 0.01), "slip_s": snappedf(slip_t, 0.01),
		"reason": String(arm.last_release.get("reason", "")), "dx_m": snappedf(_body_com(big).x - x0, 0.01)}
	info["heavy"] = r
	print("heavy: ", JSON.stringify(r))
	_check("heavy_not_lifted", rise < HEAVY_RISE_MAX_M, snappedf(rise, 0.01), "< %.1f m (или срыв)" % HEAVY_RISE_MAX_M, "срыв %s с" % ("нет" if slip_t < 0.0 else "%.2f" % slip_t))


# ------------------------------------------------------------------ переключатель, свои части, KO, оружие

func _case_toggle() -> void:
	_new_world()
	var p1 := _spawn_doll(DOLL_SCENE, 0.0, "p1", 0, true)
	var arm := _arm(p1)
	var crate := _spawn_prop(CRATE, Vector3(-1.35, 0.02, 0))
	var p2h := _spawn_doll(DOLL_DARK_SCENE, 6.0, "p2", 1, true)
	await _ticks(50)
	# подсветка одного предмета двумя руками: при любом порядке ухода рук возвращается исходный overlay (не чужая подсветка)
	var arm2 := _arm(p2h)
	var gis := crate.find_children("*", "GeometryInstance3D", true, false)
	arm._set_highlight(null)   # T-рука P1 достаёт ящик (0.9 м): он уже кандидат и подсвечен — снять, чтобы взять исходный overlay
	var orig: Array = gis.map(func(g: Node) -> Variant: return (g as GeometryInstance3D).material_overlay)
	var hl_ok := gis.size() > 0
	var hl_log: Array = [gis.size()]
	for order in [[arm, arm2], [arm2, arm]]:
		arm._set_highlight(crate)
		arm2._set_highlight(crate)
		var both := (gis[0] as GeometryInstance3D).material_overlay == arm2._hl_material
		(order[0] as ArmAssist)._set_highlight(null)
		var top := (gis[0] as GeometryInstance3D).material_overlay == (order[1] as ArmAssist)._hl_material
		(order[1] as ArmAssist)._set_highlight(null)
		var back := true
		for i in gis.size():
			back = back and (gis[i] as GeometryInstance3D).material_overlay == orig[i]
		hl_log.append([both, top, back])
		hl_ok = hl_ok and both and top and back
	_check("highlight_two_arms", hl_ok, hl_log, "[n, [true, true, true] × 2]", "две руки на одном ящике, оба порядка ухода: overlay как был")
	# свои части: can_grab false, кандидата нет, когда рядом только своё тело (кисть у торса)
	var own_ok := true
	for p in p1.parts.values():
		own_ok = own_ok and not arm.can_grab(p)
	arm.set_target_override(p1.torso().global_position + Vector3(-0.05, 0.0, 0))
	await _ticks(40)
	var near_own := arm.grip_global().distance_to(p1.torso().global_position)
	arm.press_grab()
	await _ticks(1)
	_check("own_parts_not_grabbed", own_ok and arm.held == null and arm.last_grab_action == "none", arm.last_grab_action, "none",
		"кисть в %.2f м от торса" % near_own)
	# захват → повторное нажатие отпускает
	var t0 := 0
	while t0 < 90:
		arm.set_target_override(arm.closest_point(crate, arm.root_point()) + Vector3(0, 0.08, 0))
		await _ticks(1)
		t0 += 1
		if arm.candidate == crate:
			break
	arm.press_grab()
	await _ticks(5)
	var held1 := arm.held == crate
	arm.press_grab()
	await _ticks(1)
	_check("toggle_grab_release", held1 and arm.held == null and arm.last_release.get("reason", "") == "toggle", [held1, arm.held == null], "[true, true]")
	# KO отпускает
	await _ticks(20)
	t0 = 0
	while t0 < 90 and arm.held == null:
		arm.set_target_override(arm.closest_point(crate, arm.root_point()) + Vector3(0, 0.08, 0))
		await _ticks(1)
		t0 += 1
		if arm.candidate == crate:
			arm.press_grab()
			await _ticks(1)
	var held2 := arm.held == crate
	p1.knock_out()
	await _ticks(2)
	var ko_ok: bool = held2 and arm.held == null and arm.last_release.get("reason", "") == "ko"
	await _ticks(130)
	var exc_left := 0
	for p in p1.parts.values():
		if crate.get_collision_exceptions().has(p):
			exc_left += 1
	if OS.get_environment("ARM_TRACE") == "1":
		print("  ko: pending=", arm._pending_release, " t=", arm._time, " exc=", exc_left, " held=", arm.held)
	_check("ko_releases", ko_ok, [held2, arm.held == null, arm.last_release.get("reason", "")], "[true, true, ko]", "исключений коллизий через 2.2 с: %d" % exc_left)
	# после KO — не хватает
	arm.press_grab()
	await _ticks(2)
	_check("ko_no_grab", arm.held == null, arm.held == null, true)
	# оружие в кисти: клавиша захвата бросает оружие, подбор не возвращает его сразу
	_new_world()
	var p3 := _spawn_doll(DOLL_SCENE, 0.0, "p1", 0, false)
	var wp := WeaponPickup.attach_to(p3)
	var arm3 := ArmAssist.attach_to(p3)
	await _ticks(2)
	var hand_pos := wp.hand_grip_global("Hand_R")
	var hammer := Weapon.spawn("hammer", world, hand_pos, 0.0)
	hammer.global_position += hand_pos - hammer.grip_global()
	await _ticks(30)
	var had := wp.weapon_in("Hand_R") == hammer
	# рука мышью водит кисть с молотом
	var tgt := arm3.root_point() + Vector3(-0.2, 0.6, 0)
	arm3.set_target_override(tgt)
	await _ticks(60)
	var err_w := arm3.grip_global().distance_to(arm3.clamp_to_reach(tgt))
	arm3.clear_target_override()
	await _ticks(30)
	arm3.press_grab()
	await _ticks(1)
	var dropped := wp.weapon_in("Hand_R") == null and arm3.last_grab_action == "drop_weapon"
	var repicked_early := false
	for i in range(int(ArmAssist.REPICK_BLOCK_S * 60) - 6):
		await _ticks(1)
		repicked_early = repicked_early or wp.weapon_in("Hand_R") != null
	_check("weapon_arm_moves", had and err_w < 0.15, snappedf(err_w, 0.003), "< 0.15 m", "кисть с молотом 6 кг к цели")
	_check("weapon_grab_key_drops", dropped and not repicked_early, [dropped, repicked_early], "[true, false]", "клавиша захвата бросает оружие; подбор выключен %.1f с" % ArmAssist.REPICK_BLOCK_S)
	await _ticks(40)
	info["weapon_auto_pickup_after"] = wp.auto_pickup


# ------------------------------------------------------------------ кадры (не headless)

## Бросок ящика 10 кг в P2 на площадке scenes/playground_arm.tscn: style "plant" (разбег с ящиком над головой, мах вперёд, со
## второй половины маха — тяга назад, отпустить в конце): бросивший тормозит и не таранит P2 телом (со style "run" он обгоняет
## свой ящик и бьёт P2 первым). P2 ставится на FRAMES_P2_X и опускает руки. Кадры: 1 — кисть у ящика (подсветка кандидата, кольцо
## цели), 2 — ящик над головой на разбеге, 3 — через 0.1 с после броска, 4 — ящик попал в P2 (удар kind weapon от P1; нет — +1.5 с).
func _frames() -> void:
	var pg: Node3D = (load(PLAYGROUND) as PackedScene).instantiate()
	var p1: Doll = pg.get_node("P1")
	var p2: Doll = pg.get_node("P2")
	var m := pg.get_node_or_null("Match")
	if m != null:
		m.set("countdown_s", 0.0)
	p1.external_input = true
	p2.external_input = true
	p2.position.x = frames_p2_x
	add_child(pg)
	p2.set_pose({"Shoulder": 8.0})
	var arm := _arm(p1)
	var crate: RigidBody3D = pg.get_node("Scrap/Props/Crate")
	var kinds: Array = []
	var weapon_hit := [false]
	p2.damaged.connect(func(amount: float, attacker: Node, _part: String, _pos: Vector3, kind: String) -> void:
		kinds.append("%s %.1f от %s" % [kind, amount, attacker.name if attacker != null else "—"])
		if kind == "weapon" and attacker == p1:
			weapon_hit[0] = true)
	world = null
	await _ticks(60)
	var shots: Array = []
	var hp0 := p2.hp
	var r := await _throw(p1, arm, crate, frames_dir, frames_style, 0.8, shots)
	if not r["grabbed"]:
		print("frames: ящик не схвачен ", JSON.stringify(r))
		return
	var t := 0
	var hit_shot := false
	while t < 90:
		p1.input_vec = Vector2(-frames_dir, 0.3) if t < int(BRAKE_S * 60) else Vector2.ZERO
		await _ticks(1)
		t += 1
		if OS.get_environment("ARM_TRACE") == "1" and t % 6 == 0:
			print("  t%02d crate(%.2f,%.2f) v(%.2f,%.2f) p1 %.2f p2 %.2f" % [t, crate.global_position.x, crate.global_position.y,
				crate.linear_velocity.x, crate.linear_velocity.y, p1.torso().global_position.x, p2.torso().global_position.x])
		if t == 6:
			shots.append(await _shot())
		if t > 6 and not hit_shot and weapon_hit[0]:
			await _ticks(3)
			shots.append(await _shot())
			hit_shot = true
			break
	p1.input_vec = Vector2.ZERO
	if not hit_shot:
		shots.append(await _shot())
	print("frames: release v %.2f m/s, p2 hp %.1f -> %.1f, hits %s, p1 damage_dealt %.2f" % [float(r["release_speed"]), hp0, p2.hp, str(kinds),
		float(p1.stats["damage_dealt"])])
	if DisplayServer.get_name() == "headless":
		print("frames: headless — кадры не пишутся (прогон сценария)")
		return
	var dir_abs := ProjectSettings.globalize_path("res://").path_join("../docs/plan-demo/img").simplify_path()
	DirAccess.make_dir_recursive_absolute(dir_abs)
	for i in shots.size():
		shots[i].save_png(dir_abs.path_join("arm-throw-v1_%d.png" % (i + 1)))
	# лист 2 × 2 (половинный размер)
	var w := (shots[0] as Image).get_width() / 2
	var h := (shots[0] as Image).get_height() / 2
	var sheet := Image.create(w * 2, h * 2, false, Image.FORMAT_RGBA8)
	for i in mini(shots.size(), 4):
		var s := (shots[i] as Image).duplicate() as Image
		s.convert(Image.FORMAT_RGBA8)
		s.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(s, Rect2i(0, 0, w, h), Vector2i((i % 2) * w, (i / 2) * h))
	sheet.save_png(dir_abs.path_join("arm-throw-v1.png"))
	print("frames saved to ", dir_abs, " (", shots.size(), ")")


## Кадр в shots (Array) — только в режиме кадров; null — ничего. После кадра — снова на начало физического тика (как после
## _ticks): иначе press_grab сразу после кадра обработается уже после следующего await.
func _capture(shots: Variant) -> void:
	if shots is Array:
		(shots as Array).append(await _shot())
		await get_tree().physics_frame


## Кадр окна. Headless (прогон сценария кадров без картинок): frame_post_draw там не приходит — ждём те же два кадра процесса.
func _shot() -> Image:
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
		await get_tree().process_frame
		return null
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()
