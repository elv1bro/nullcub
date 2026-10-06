## Прочность суставов — пробный режим (JointBreak, docs/plan-demo/JOINT_BREAK.md, 04.10.2026): headless-проба.
##   godot --headless --path godot --fixed-fps 60 res://tests/joint_break_probe.tscn
## Проверки (exit 1):
##   • JointBreak.hp_for_depth — 40 → 28 → 19.6, пол JOINT_HP_MIN; у doll.tscn глубины плечо/бедро 1, локоть/колено 2,
##     запястье/лодыжка 3, ядра и головы в таблице нет, у ребёнка запас меньше, чем у родителя;
##   • режим выключен — урон суставы не изнашивает; включён — урон в предплечье тратит запас локтя, на нуле предплечье отлетает
##     вместе с кистью (сигнал joint_broken с точкой сустава, stats.joints_broken, meta joint_broken), кукла жива;
##   • блок кистью режет HP, но не износ запястья; голова и ядро не отлетают; удар, который кладёт куклу, сустав не ломает;
##   • отлетевшую деталь касанием не вернуть (ArmAssist.reattach_own = false), Doll.reattach_part возвращает её с целым суставом;
##   • ModularDoll: с режимом суставов запас по материалу (part_integrity, PART_BREAK) не тратится, без режима — тратится он,
##     а не сустав (если в сборке есть PART_BREAK; нет — проверяется только сустав); длинная сборка (long_arm, 5 суставов
##     от ядра) — запас упирается в JOINT_HP_MIN и не ниже;
##   • JointBreakFx: повреждённый сустав искрит, отрыв даёт вспышку.
## В stdout — «=== JOINT BREAK PROBE ===» и JSON.
extends Node3D

const DOLL := "res://scenes/doll/doll.tscn"
const MODULAR := "res://scenes/body/presets/kit_skull.tscn"
const DEEP := "res://scenes/body/presets/long_arm.tscn"   # цепочка в 5 суставов от ядра: запас упирается в пол
const EPS := 0.001

var checks: Array = []
var ok := true
var _x := 0.0


func _check(pass_: bool, what: String, detail: Variant = null) -> void:
	checks.append({"ok": pass_, "check": what, "detail": detail})
	ok = ok and pass_


func _spawn(path: String) -> Doll:
	var d := (load(path) as PackedScene).instantiate() as Doll
	d.external_input = true
	d.position = Vector3(_x, 0.0, 0.0)
	_x += 8.0
	add_child(d)
	d.max_hp = 1000.0
	d.hp = 1000.0
	d.grace_until = -1.0
	return d


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _ready() -> void:
	PartHp.set_on(false)   # меряем «Прочность суставов» (C): «Запас из деталей» (стандарт с 06.10) строит таблицу отрыва по своим ❤
	var was := JointBreak.on
	# формула
	var f := [JointBreak.hp_for_depth(1), JointBreak.hp_for_depth(2), JointBreak.hp_for_depth(3), JointBreak.hp_for_depth(12)]
	_check(absf(f[0] - Tuning.JOINT_HP_BASE) < EPS and absf(f[1] - Tuning.JOINT_HP_BASE * Tuning.JOINT_HP_FALLOFF) < EPS
		and absf(f[2] - Tuning.JOINT_HP_BASE * Tuning.JOINT_HP_FALLOFF * Tuning.JOINT_HP_FALLOFF) < EPS and absf(f[3] - Tuning.JOINT_HP_MIN) < EPS,
		"hp_for_depth: BASE × FALLOFF^(глубина − 1), пол JOINT_HP_MIN", f)

	# обычная кукла: таблица запасов
	var d := _spawn(DOLL)
	var depth_ok := true
	for side in ["L", "R"]:
		depth_ok = depth_ok and int(d.joint_depth.get("UpperArm_" + side, 0)) == 1 and int(d.joint_depth.get("LowerArm_" + side, 0)) == 2 \
			and int(d.joint_depth.get("Hand_" + side, 0)) == 3 and int(d.joint_depth.get("UpperLeg_" + side, 0)) == 1 \
			and int(d.joint_depth.get("LowerLeg_" + side, 0)) == 2 and int(d.joint_depth.get("Foot_" + side, 0)) == 3
	_check(depth_ok, "doll.tscn: глубины плечо/бедро 1, локоть/колено 2, запястье/лодыжка 3", d.joint_depth)
	_check(d.joint_hp.size() == 12 and not d.joint_hp.has("Torso") and not d.joint_hp.has("Head"), "ядра и головы в таблице нет, суставов 12", d.joint_hp.keys())
	_check(float(d.joint_hp["UpperArm_L"]) > float(d.joint_hp["LowerArm_L"]) and float(d.joint_hp["LowerArm_L"]) > float(d.joint_hp["Hand_L"])
		and float(d.joint_hp["UpperLeg_R"]) > float(d.joint_hp["LowerLeg_R"]) and float(d.joint_hp["LowerLeg_R"]) > float(d.joint_hp["Foot_R"]),
		"дальше от ядра — запас меньше", d.joint_hp)

	# режим выключен: урон суставы не трогает
	JointBreak.set_on(false)
	var elbow := float(d.joint_hp["LowerArm_L"])
	d.take_damage(elbow + 20.0, null, "LowerArm_L", Vector3.ZERO, Vector3.UP, "body")
	await _frames(2)
	_check(d.parts.has("LowerArm_L") and absf(float(d.joint_hp["LowerArm_L"]) - elbow) < EPS, "режим выключен: сустав цел, деталь на месте", d.joint_hp["LowerArm_L"])

	# режим включён: износ, затем отрыв предплечья вместе с кистью
	JointBreak.set_on(true)
	var broken: Array = []
	d.joint_broken.connect(func(n: String, _by: Node, pos: Vector3) -> void: broken.append([n, pos]))
	var pivot := d.joint_pivot_global("Elbow_L")
	d.take_damage(elbow - 5.0, null, "LowerArm_L", Vector3.ZERO, Vector3.UP, "body")
	await _frames(2)
	_check(d.parts.has("LowerArm_L") and absf(float(d.joint_hp["LowerArm_L"]) - 5.0) < EPS, "урон в предплечье тратит запас локтя, деталь на месте", d.joint_hp.get("LowerArm_L"))
	d.take_damage(10.0, null, "LowerArm_L", Vector3.ZERO, Vector3.UP, "body")
	await _frames(2)
	_check(broken.size() == 1 and broken[0][0] == "LowerArm_L" and not d.parts.has("LowerArm_L") and not d.parts.has("Hand_L")
		and d.parts.has("UpperArm_L") and d.alive, "запас кончился — предплечье отлетело вместе с кистью, кукла жива", {"broken": broken, "parts": d.parts.size()})
	_check(broken.size() == 1 and (broken[0][1] as Vector3).distance_to(pivot) < 0.5, "joint_broken несёт точку сустава (локоть)",
		[broken[0][1] if broken.size() == 1 else null, pivot])
	_check(int(d.stats.get("joints_broken", 0)) == 1 and not d.joint_hp.has("LowerArm_L") and not d.joint_hp.has("Hand_L"),
		"stats.joints_broken = 1, запасы отлетевших деталей сняты", d.stats.get("joints_broken"))
	var lost: Array = d.detached_parts()
	_check(lost.size() == 1 and (lost[0] as Node).has_meta("joint_broken"), "оторванное тело помечено joint_broken", lost.size())

	# касанием не вернуть; Doll.reattach_part возвращает с целым суставом
	var arm := ArmAssist.new()
	d.add_child(arm)
	await _frames(2)
	if lost.size() == 1:
		_check(not arm.reattach_own(lost[0], "touch") and not d.parts.has("LowerArm_L"), "ArmAssist.reattach_own отлетевшую от ударов деталь не возвращает")
		_check(d.reattach_part(lost[0]) and d.parts.has("LowerArm_L") and absf(float(d.joint_hp.get("LowerArm_L", 0.0)) - elbow) < EPS
			and d.joint_hp.has("Hand_L") and not (lost[0] as Node).has_meta("joint_broken"), "Doll.reattach_part: деталь на месте, сустав целый", d.joint_hp.get("LowerArm_L"))

	# блок кистью: HP режется (это делает DollCombat до take_damage), износ запястья — полный
	var wrist := float(d.joint_hp["Hand_R"])
	d.take_damage(2.0, null, "Hand_R", Vector3.ZERO, Vector3.UP, "body")
	await _frames(2)
	_check(absf(float(d.joint_hp["Hand_R"]) - (wrist - 2.0 / Tuning.HAND_HIT_MULT * Tuning.JOINT_WEAR_MULT)) < EPS,
		"блок кистью: 2 HP урона = %.1f износа запястья" % (2.0 / Tuning.HAND_HIT_MULT), d.joint_hp["Hand_R"])

	# голова и ядро
	d.take_damage(60.0, null, "Head", Vector3.ZERO, Vector3.UP, "head")
	d.take_damage(60.0, null, "Torso", Vector3.ZERO, Vector3.UP, "body")
	await _frames(2)
	_check(d.alive and d.parts.has("Head") and d.parts.has("Torso"), "голова и ядро не отлетают", d.hp)

	# удар, который кладёт куклу, сустав не ломает (кукла и так разлетается)
	var k := _spawn(DOLL)
	k.hp = 5.0
	var kb: Array = []
	k.joint_broken.connect(func(n: String, _by: Node, _p: Vector3) -> void: kb.append(n))
	k.take_damage(50.0, null, "UpperArm_R", Vector3.ZERO, Vector3.UP, "body")
	await _frames(2)
	_check(not k.alive and kb.is_empty(), "KO этим ударом: joint_broken не было", kb)

	# ModularDoll: два счёта сразу не ведутся. Запас по материалу (PART_BREAK, ARMOR_BREAK.md) — отдельная работа: читаем его
	# через get(), чтобы проба шла и в сборке без него
	var m := _spawn(MODULAR) as ModularDoll
	_check(m != null and m.build_errors.is_empty() and m.joint_hp.has("LowerArm_L"), "kit_skull собран, у предплечья есть запас сустава", m.joint_hp if m != null else null)
	if m != null and m.joint_hp.has("LowerArm_L"):
		var pi: Variant = m.get("part_integrity")
		var part_break: bool = (load("res://scripts/tuning.gd") as Script).get_script_constant_map().get("PART_BREAK", false) == true
		var has_integ := part_break and pi is Dictionary and (pi as Dictionary).has("LowerArm_L")
		var integ := float((pi as Dictionary)["LowerArm_L"]) if has_integ else 0.0
		var jh := float(m.joint_hp["LowerArm_L"])
		m.take_damage(6.0, null, "LowerArm_L", Vector3.ZERO, Vector3.UP, "body")
		await _frames(2)
		_check(absf(float(m.joint_hp["LowerArm_L"]) - (jh - 6.0 * Tuning.JOINT_WEAR_MULT)) < EPS, "ModularDoll, режим суставов: тратится сустав", m.joint_hp["LowerArm_L"])
		if has_integ:
			_check(absf(float((pi as Dictionary)["LowerArm_L"]) - integ) < EPS, "ModularDoll, режим суставов: запас по материалу (PART_BREAK) цел", (pi as Dictionary)["LowerArm_L"])
		JointBreak.set_on(false)
		m.take_damage(6.0, null, "LowerArm_L", Vector3.ZERO, Vector3.UP, "body")
		await _frames(2)
		_check(absf(float(m.joint_hp["LowerArm_L"]) - (jh - 6.0 * Tuning.JOINT_WEAR_MULT)) < EPS, "ModularDoll, режим выключен: сустав не трогается", m.joint_hp["LowerArm_L"])
		if has_integ:
			_check(absf(float((pi as Dictionary)["LowerArm_L"]) - (integ - 6.0)) < EPS, "ModularDoll, режим выключен: тратится запас по материалу (PART_BREAK)", (pi as Dictionary)["LowerArm_L"])
		else:
			print("joint_break_probe: PART_BREAK в этой сборке нет — совместная проверка с запасом по материалу пропущена")
		JointBreak.set_on(true)

	# длинная сборка: запас упирается в пол и не уходит ниже
	var c := _spawn(DEEP)
	var lo := INF
	var deepest := 0
	for n in c.joint_hp:
		lo = minf(lo, float(c.joint_hp[n]))
		deepest = maxi(deepest, int(c.joint_depth[n]))
	_check(deepest >= 5 and absf(lo - Tuning.JOINT_HP_MIN) < EPS, "long_arm: глубина ≥ 5, самый дальний сустав держит ровно JOINT_HP_MIN",
		{"joints": c.joint_hp.size(), "min_hp": lo, "max_depth": deepest})

	# вид: повреждённый сустав искрит, отрыв — вспышка
	var holder := Node.new()
	add_child(holder)
	var fx := JointBreakFx.new()
	holder.add_child(fx)
	var s := _spawn(DOLL)
	s.add_to_group("dolls")
	await get_tree().create_timer(0.5).timeout
	var knee := float(s.joint_hp["LowerLeg_L"])
	s.take_damage(knee * 0.8, null, "LowerLeg_L", Vector3.ZERO, Vector3.UP, "body")
	await get_tree().create_timer(2.5).timeout
	var sparks := int(fx.stats["sparks"])
	_check(sparks >= 2, "JointBreakFx: сустав с 20 % запаса искрит (≥ 2 искр за 2.5 с)", sparks)
	s.take_damage(knee, null, "LowerLeg_L", Vector3.ZERO, Vector3.UP, "body")
	await get_tree().create_timer(0.3).timeout
	_check(int(fx.stats["breaks"]) == 1 and not s.parts.has("LowerLeg_L") and not s.parts.has("Foot_L") and s.alive,
		"JointBreakFx: отрыв голени со стопой дал вспышку", fx.stats)

	JointBreak.set_on(was)
	_finish()


func _finish() -> void:
	print("=== JOINT BREAK PROBE ===")
	print(JSON.stringify({"ok": ok, "checks": checks}, "\t"))
	print("=== OK ===" if ok else "=== FAIL ===")
	get_tree().quit(0 if ok else 1)
