## Проба Physics Overlay мастерской (scenes/workshop/ws_physics.gd, UI/UX spec v0.3 §20–21): пресеты стоят рядом, как кукла стенда
## (WorkshopBuild._rebuild_stand: поза стенда _snap_pose, тела заморожены, пути суставов обнулены), WsPhysics считает центр масс,
## нагрузку суставов, опору и крен. Headless:
##   godot --headless --path . --fixed-fps 60 res://tests/ws_physics_probe.tscn   → таблица, «WS PHYSICS OK» и код 0 / «FAIL» и 1,
##   tests/ws_physics_probe_report.json ({ok, checks[]}). Куклы замораживаются сразу после посадки, как стенд мастерской; числа —
##   после двух шагов физики.
## Проверки (id):
##   <preset>_finite  — у каждого пресета (все scenes/body/presets + modular_doll.tscn + старая doll.tscn): центр масс, доли массы,
##                      нагрузки, опора, крен конечны, нагрузки ≥ 0, доли массы в сумме 1, summary с ключами {com, max_load, max_joint, tip};
##   pivot_on_socket  — точка сустава (кадр на текущем родителе) совпадает с маркером Socket тела-ребёнка ≤ 1 см у всех пресетов кита:
##                      поза стенда повернула родителей, а узлы суставов остались на месте сборки;
##   human_*          — kit_human: центр масс между стопами, нагрузки есть, плечи (руки в T-позе) тяжелее колен, левое = правое,
##                      крен ≈ 0, запас опоры > 0; то же для деревянной куклы modular_doll.tscn (wood_*);
##   torque_reference — момент сустава (суммы по поддеревьям) = прямой счёт по цепи g·|Σ mᵢ(xᵢ − x_оси)| у шести пресетов;
##   spinner_*        — вертушка: есть болтающийся свободный сустав (free, load 1; у свободных load только 0 или 1), наибольшая
##                      нагрузка выше, чем у human;
##   spider_margin    — паук стоит: запас опоры > 0;
##   empty_*          — ядро + голова: всё считается без ошибок (шея — единственный сустав);
##   turn_invariant   — стенд, повёрнутый на 90° (как R покраски: узел куклы и тела), даёт те же нагрузки и запас опоры;
##   tip_outside      — верх деревянной куклы сдвинут за стопы: запас < 0, крен +1, опора прежняя;
##   draw_*           — WsPhysics.draw из _draw полноэкранного Control отрабатывает во всех ветках (призрак, бирки, свободные,
##                      центр масс за опорой, без шрифта, масштаб, alpha), центр масс human на экране.
extends Node3D

const PRESET_DIR := "res://scenes/body/presets/"
const REPORT := "res://tests/ws_physics_probe_report.json"
const MAIN := {
	"human": "res://scenes/body/presets/kit_human.tscn",
	"spinner": "res://scenes/body/presets/kit_spinner.tscn",
	"spider": "res://scenes/body/presets/kit_spider.tscn",
	"empty": "res://scenes/body/presets/kit_empty.tscn",
	"wood": "res://scenes/body/modular_doll.tscn",
	"doll": "res://scenes/doll/doll.tscn",
}
## Поза стенда — копия WorkshopBuild.POSE_GROUPS (мастерская ставит в позу и кисти, стопы, шею; скрипт мастерской сейчас переписывается).
const POSE_GROUPS := ["Neck", "Shoulder", "Elbow", "Hip", "Knee", "Wrist", "Ankle"]
const SPACING := 3.0
const SOCKET_TOL := 0.01
const SUMMARY_KEYS := ["com", "max_load", "max_joint", "tip"]

var checks: Array = []
var ok := true
var dolls: Dictionary = {}   # имя -> кукла
var _drawn := 0
var _draw_com := Vector2.ZERO


func _check(id: String, cond: bool, detail: String) -> void:
	checks.append({"id": id, "ok": cond, "detail": detail})
	if not cond:
		ok = false
	print("  %-28s %s  %s" % [id, "ok  " if cond else "FAIL", detail])


func _ready() -> void:
	print("=== WS PHYSICS PROBE === g = %.2f м/с²" % WsPhysics.gravity().length())
	var paths := MAIN.duplicate()
	for f in DirAccess.get_files_at(PRESET_DIR):
		if f.ends_with(".tscn"):
			var id := f.get_basename()
			if not paths.values().has(PRESET_DIR + f):
				paths[id] = PRESET_DIR + f
	var i := 0
	for id: String in paths:
		dolls[id] = _stand(load(paths[id]) as PackedScene, Vector3(i * SPACING, 0.0, 0.0))
		i += 1
	await get_tree().physics_frame
	await get_tree().physics_frame
	_table()
	_checks()
	await _draw_check()
	var f := FileAccess.open(REPORT, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"ok": ok, "checks": checks}, "  "))
		f.close()
	print("=== %s ===" % ("WS PHYSICS OK" if ok else "WS PHYSICS FAIL"))
	get_tree().quit(0 if ok else 1)


## Кукла как на стенде мастерской: поза стенда, тела заморожены без коллизий, пути суставов обнулены (Jolt их не решает).
func _stand(ps: PackedScene, at: Vector3) -> Node3D:
	var d := ps.instantiate() as Node3D
	d.set("external_input", true)
	d.set("control_enabled", false)
	d.position = at
	add_child(d)
	if d.has_method("_snap_pose"):
		d.call("_snap_pose", POSE_GROUPS)
	for b in (d.get("parts") as Dictionary).values():
		var rb := b as RigidBody3D
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rb.freeze = true
		rb.collision_layer = 0
		rb.collision_mask = 0
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
	for j in (d.get("joints") as Dictionary).values():
		(j as Generic6DOFJoint3D).node_a = NodePath()
		(j as Generic6DOFJoint3D).node_b = NodePath()
	return d


func _table() -> void:
	print("  %-13s %5s %6s %15s %17s %7s %6s %6s  %-22s %-22s %s" % ["preset", "bodies", "kg", "com x,y (loc)", "support x", "margin",
		"dir", "high", "max load", "max muscle", "free"])
	for id: String in dolls:
		var d: Node3D = dolls[id]
		var s := WsPhysics.summary(d)
		var sup := WsPhysics.support(d)
		var tp: Dictionary = s["tip"]
		var c: Vector3 = (s["com"] as Vector3) - d.global_position
		var ox := d.global_position.x
		print("  %-13s %5d %6.1f %7.3f,%6.3f  [%6.3f, %6.3f] %7.3f %6.2f %6.2f  %-22s %-22s %s" % [id, (d.get("parts") as Dictionary).size(),
			float(s["mass"]), c.x, c.y, float(sup["min_x"]) - ox, float(sup["max_x"]) - ox, float(tp["margin"]), float(tp["dir"]),
			float(tp["height"]), "%.2f %s" % [float(s["max_load"]), s["max_joint"]],
			"%.2f %s" % [float(s["max_muscle_load"]), s["max_muscle_joint"]], ",".join(s["free_joints"])])
	print("  нагрузки (load = момент / (tmax + трение)):")
	for id: String in ["human", "spinner", "spider", "empty", "wood"]:
		var row: PackedStringArray = []
		for e: Dictionary in WsPhysics.joint_stress(dolls[id]):
			row.append("%s %s%.2f" % [e["joint"], "free " if bool(e["free"]) else "", float(e["load"])])
		print("    %-8s %s" % [id, "  ".join(row)])
	var h: Node3D = dolls["human"]
	var fns := {"com": func() -> void: WsPhysics.com(h), "mass_points": func() -> void: WsPhysics.mass_points(h),
		"joint_stress": func() -> void: WsPhysics.joint_stress(h), "support": func() -> void: WsPhysics.support(h),
		"tip": func() -> void: WsPhysics.tip(h), "summary": func() -> void: WsPhysics.summary(h)}
	var cost: PackedStringArray = []
	for fn: String in fns:
		var t0 := Time.get_ticks_usec()
		for n in 20:
			(fns[fn] as Callable).call()
		cost.append("%s %.0f" % [fn, (Time.get_ticks_usec() - t0) / 20.0])
	print("  цена на human, мкс (среднее из 20; draw ≈ summary + mass_points): %s" % ", ".join(cost))


func _checks() -> void:
	for id: String in dolls:
		_finite_check(id, dolls[id])
	_socket_check()
	_human_checks("human", dolls["human"])
	_human_checks("wood", dolls["wood"])

	var hs := WsPhysics.summary(dolls["human"])
	var ss := WsPhysics.summary(dolls["spinner"])
	var dangling := 0
	var free_bad: PackedStringArray = []
	for e: Dictionary in WsPhysics.joint_stress(dolls["spinner"]):
		if not bool(e["free"]):
			continue
		if is_equal_approx(float(e["load"]), 1.0):
			dangling += 1
		elif not is_zero_approx(float(e["load"])):
			free_bad.append("%s %.2f" % [e["joint"], float(e["load"])])   # свободный: 1 (болтается) или 0 (висит отвесно)
	_check("spinner_free_joint", dangling > 0 and free_bad.is_empty(), "болтающихся (load 1): %d из %s%s" % [dangling,
		",".join(ss["free_joints"]), "" if free_bad.is_empty() else "; не 0/1: " + ", ".join(free_bad)])
	_check("spinner_max_above_human", float(ss["max_load"]) > float(hs["max_load"]),
		"%.2f (%s) > %.2f (%s)" % [float(ss["max_load"]), ss["max_joint"], float(hs["max_load"]), hs["max_joint"]])

	var sp := WsPhysics.tip(dolls["spider"])
	_check("spider_margin", float(sp["margin"]) > 0.0, "запас %.3f м, dir %.2f" % [float(sp["margin"]), float(sp["dir"])])

	var em: Node3D = dolls["empty"]
	var es := WsPhysics.joint_stress(em)
	var ec := WsPhysics.com(em)
	_check("empty_works", _fin3(ec) and (em.get("parts") as Dictionary).size() == 2 and es.size() == 1,
		"тел %d, суставов %d (%s), центр масс %s" % [(em.get("parts") as Dictionary).size(), es.size(),
		String(es[0]["joint"]) if not es.is_empty() else "-", ec - em.global_position])

	_torque_reference()
	_turn_check("human")
	_turn_check("spinner")
	_tip_outside_check()


func _finite_check(id: String, d: Node3D) -> void:
	var bad: PackedStringArray = []
	if not _fin3(WsPhysics.com(d)):
		bad.append("com")
	var fs := 0.0
	for m: Dictionary in WsPhysics.mass_points(d):
		fs += float(m["frac"])
		if not _fin3(m["pos"]) or not is_finite(float(m["mass"])):
			bad.append("mass " + String(m["body"]))
	if absf(fs - 1.0) > 1e-4:
		bad.append("frac Σ %.4f" % fs)
	for e: Dictionary in WsPhysics.joint_stress(d):
		if not _fin3(e["pos"]) or not is_finite(float(e["load"])) or float(e["load"]) < 0.0:
			bad.append("load " + String(e["joint"]))
	var sup := WsPhysics.support(d)
	for key in ["min_x", "max_x", "floor_y"]:
		if not is_finite(float(sup[key])):
			bad.append("support " + key)
	if float(sup["max_x"]) < float(sup["min_x"]):
		bad.append("support min > max")
	var tp := WsPhysics.tip(d)
	if not is_finite(float(tp["dir"])) or not is_finite(float(tp["margin"])) or absf(float(tp["dir"])) > 1.0:
		bad.append("tip")
	var s := WsPhysics.summary(d)
	for key: String in SUMMARY_KEYS:
		if not s.has(key):
			bad.append("summary." + key)
	_check(id + "_finite", bad.is_empty(), "всё конечно, summary с ключами" if bad.is_empty() else ", ".join(bad))


## Точка сустава = маркер Socket тела ниже сустава (у деталей кита сокет — точка крепления). Проверяется у всех кукол, где Socket есть.
func _socket_check() -> void:
	var worst := 0.0
	var worst_id := ""
	var n := 0
	for id: String in dolls:
		var d: Node3D = dolls[id]
		var parts: Dictionary = d.get("parts")
		for e: Dictionary in WsPhysics.joint_stress(d):
			var b := parts.get(String(e["child"])) as Node3D
			var sock := b.get_node_or_null("Socket") as Node3D if b != null else null
			if sock == null:
				continue
			n += 1
			var gap := sock.global_position.distance_to(e["pos"])
			if gap > worst:
				worst = gap
				worst_id = "%s/%s" % [id, e["joint"]]
	_check("pivot_on_socket", n > 20 and worst <= SOCKET_TOL, "суставов с Socket %d, хуже всех %.4f м %s" % [n, worst, worst_id])


func _human_checks(id: String, d: Node3D) -> void:
	var parts: Dictionary = d.get("parts")
	var c := WsPhysics.com(d)
	var fl := WsPhysics.body_com(parts["Foot_L"])
	var fr := WsPhysics.body_com(parts["Foot_R"])
	_check(id + "_com_between_feet", _fin3(c) and c.x > minf(fl.x, fr.x) and c.x < maxf(fl.x, fr.x),
		"стопы x %.3f / %.3f, центр масс %.3f (от куклы)" % [fl.x - d.global_position.x, fr.x - d.global_position.x, c.x - d.global_position.x])
	var st := WsPhysics.joint_stress(d)
	var by := {}
	var all_ok := true
	for e: Dictionary in st:
		by[String(e["joint"])] = float(e["load"])
		all_ok = all_ok and is_finite(float(e["load"])) and float(e["load"]) >= 0.0
	_check(id + "_stress", not st.is_empty() and all_ok, "суставов %d, все нагрузки конечны и ≥ 0" % st.size())
	var sh := minf(float(by.get("Shoulder_L", -1.0)), float(by.get("Shoulder_R", -1.0)))
	var kn := maxf(float(by.get("Knee_L", INF)), float(by.get("Knee_R", INF)))
	_check(id + "_shoulders_over_knees", sh > kn, "плечи ≥ %.3f > колени ≤ %.3f" % [sh, kn])
	var l := float(by.get("Shoulder_L", 0.0))
	var r := float(by.get("Shoulder_R", 0.0))
	_check(id + "_symmetric", absf(l - r) <= 0.05 * maxf(l, r) + 1e-4, "плечо L %.3f / R %.3f" % [l, r])
	var tp := WsPhysics.tip(d)
	_check(id + "_margin", float(tp["margin"]) > 0.0 and absf(float(tp["dir"])) < 0.15,
		"запас %.3f м, крен %.3f" % [float(tp["margin"]), float(tp["dir"])])


## Момент сустава против прямого счёта (стенд не повёрнут, ось Z, тяжесть −Y): τ = g·|Σ mᵢ (xᵢ − x_оси)| по цепи Doll._muscle_pairs
## от ребёнка вниз — сверка суммирования по поддеревьям WsPhysics._subtree.
func _torque_reference() -> void:
	var g := WsPhysics.gravity().length()
	var worst := 0.0
	var worst_id := ""
	var n := 0
	for id: String in ["human", "spinner", "spider", "flail", "long_arm", "kit_king"]:
		var d: Node3D = dolls[id]
		var pairs: Array = d.get("_muscle_pairs")
		var parts: Dictionary = d.get("parts")
		for e: Dictionary in WsPhysics.joint_stress(d):
			var chain: Array = [parts[String(e["child"])]]
			var i := 0
			while i < chain.size():
				for p: Array in pairs:
					if p[0] == chain[i] and not chain.has(p[1]):
						chain.append(p[1])
				i += 1
			var acc := 0.0
			for rb: RigidBody3D in chain:
				acc += rb.mass * (WsPhysics.body_com(rb).x - (e["pos"] as Vector3).x)
			var err := absf(g * absf(acc) - float(e["torque"]))
			n += 1
			if err > worst:
				worst = err
				worst_id = "%s/%s" % [id, e["joint"]]
	_check("torque_reference", n > 40 and worst < 1e-4, "суставов %d, расхождение ≤ %.6f Н·м %s" % [n, worst, worst_id])


## Поворот стенда на 90° вокруг вертикали (как WorkshopPaint._apply_turn: узел куклы и каждое тело) не меняет нагрузки и запас опоры.
func _turn_check(id: String) -> void:
	var d: Node3D = dolls[id]
	var before := WsPhysics.joint_stress(d)
	var tip0 := WsPhysics.tip(d)
	var pivot := d.global_position
	var xf := Transform3D(Basis.IDENTITY, pivot) * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -pivot)
	var nodes: Array = [d]
	nodes.append_array((d.get("parts") as Dictionary).values())
	var rest: Array = []
	for n: Node3D in nodes:
		rest.append(n.global_transform)
	for i in nodes.size():
		(nodes[i] as Node3D).global_transform = xf * (rest[i] as Transform3D)
	var after := WsPhysics.joint_stress(d)
	var tip1 := WsPhysics.tip(d)
	var worst := 0.0
	for i in mini(before.size(), after.size()):
		worst = maxf(worst, absf(float(before[i]["load"]) - float(after[i]["load"])))
	var dm := absf(float(tip0["margin"]) - float(tip1["margin"]))
	for i in nodes.size():
		(nodes[i] as Node3D).global_transform = rest[i]
	_check("turn_invariant_" + id, before.size() == after.size() and worst < 1e-3 and dm < 1e-3,
		"Δload %.5f, Δmargin %.5f м" % [worst, dm])


## Центр масс за опорой: деревянной кукле (wood) всё, кроме голеней и стоп, сдвинуто на 0.8 м вправо — запас < 0, крен +1, опора
## та же (стопы). Кукла остаётся сдвинутой: draw_* рисует и её (красная стрелка «опрокинется»).
func _tip_outside_check() -> void:
	var d: Node3D = dolls["wood"]
	var sup0 := WsPhysics.support(d)
	for b in (d.get("parts") as Dictionary).values():
		var base := ModularDoll.base_name(String((b as Node).name))
		if base != "Foot" and base != "LowerLeg":
			(b as Node3D).global_position += Vector3(0.8, 0.0, 0.0)
	var sup1 := WsPhysics.support(d)
	var tp := WsPhysics.tip(d)
	_check("tip_outside", float(tp["margin"]) < 0.0 and is_equal_approx(float(tp["dir"]), 1.0)
		and is_equal_approx(float(sup0["min_x"]), float(sup1["min_x"])) and is_equal_approx(float(sup0["max_x"]), float(sup1["max_x"])),
		"запас %.3f м, крен %.2f (опора [%.3f, %.3f])" % [float(tp["margin"]), float(tp["dir"]), float(sup1["min_x"]) - d.global_position.x,
		float(sup1["max_x"]) - d.global_position.x])


## Рисование: полноэкранный Control, в его _draw — WsPhysics.draw со всеми опциями (как у оверлея мастерской).
func _draw_check() -> void:
	var d: Node3D = dolls["human"]
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = d.global_position + Vector3(0.0, 1.0, 4.0)
	cam.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	var ctl := Control.new()
	ctl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ctl)
	var ghost := WsPhysics.com(d) + Vector3(0.12, 0.05, 0.0)
	ctl.draw.connect(func() -> void:
		WsPhysics.draw(ctl, cam, d, ctl.get_theme_default_font(), {"t": 0.4, "ghost_com": ghost, "labels": true})
		WsPhysics.draw(ctl, cam, dolls["spinner"], ctl.get_theme_default_font(), {"t": 0.4, "labels": true, "alpha": 0.5})
		WsPhysics.draw(ctl, cam, dolls["wood"], ctl.get_theme_default_font(), {"t": 0.4, "labels": true, "floor_y": 0.0,
			"ghost_com": WsPhysics.com(dolls["wood"]) + Vector3(0.5, 0.0, 0.0)})
		WsPhysics.draw(ctl, cam, dolls["flail"], null, {"t": 1.3, "scale": 1.5, "mass": false})
		_drawn += 1
		_draw_com = cam.unproject_position(WsPhysics.com(d)))
	ctl.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	var vr := get_viewport().get_visible_rect()
	_check("draw_runs", _drawn > 0, "кадров _draw: %d" % _drawn)
	_check("draw_com_on_screen", vr.has_point(_draw_com), "ЦМ на экране %s в %s" % [_draw_com, vr.size])


static func _fin3(v: Variant) -> bool:
	return v is Vector3 and (v as Vector3).is_finite()
