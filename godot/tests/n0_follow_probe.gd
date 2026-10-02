## Проба «камера за игроком и N0 рядом» (автор 02.10.2026: N0 летает перед нами, а не за нами; камера слишком далеко; соперника
## не обязательно видеть — стрелка с метрами). Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/n0_follow_probe.tscn
## Сцены — бой кампании (scenes/campaign/campaign_fight.tscn, соперник — бот RivalBrain, без выхода бойцов) и Быстрый бой в куполе
## (scenes/playground_null_hall.tscn, двое людей). Игрок P1 летает по сценарию клавишами (Input.action_press p1_*).
## Проверки (exit 1), отчёт — tests/n0_follow_probe_report.json:
##   camera_on_player   кадр держит только P1 (бот в кадр не тянет), полувысота 3.6…5.5 м, центр кадра у P1 (≤ 2 м по X от точки,
##                      куда его пускают границы арены — у мембраны кадр упирается в bounds())
##   n0_near            N0 рядом с P1: в 95 % кадров ≤ 3.5 м (XY) от ЦМ P1, всегда ≤ 6 м (на быстром полёте отстаёт ~0.3 с)
##   n0_behind          N0 всегда за плоскостью боя (z ≤ −0.8): кукла перед ним
##   n0_side            соперник сбоку дальше 3 м и сторона держится 1 с: N0 выбрал другую сторону (≥ 95 % таких кадров), и когда
##                      игрок почти стоит (< 2 м/с), N0 и правда там (≥ 90 %)
##   n0_in_frame        N0 в кадре (экранная точка внутри окна) в ≥ 98 % кадров
##   n0_keeps_off_rival до ЦМ соперника (XY) ≥ 0.8 м в ≥ 97 % кадров
##   marker_from_player соперник за 22 м: стрелка P2 у правого края, расстояние — от P1 (±0.5 м), камера осталась на P1
##   lines_rules        N0Lines: мелкий повод не чаще 8 с и не поверх реплики, важный — всегда; повода «соперник далеко» нет
##                      (где соперник — только стрелка HUD, автор 02.10)
##   line_countdown     на отсчёте N0 сказал реплику «fight», облачко видно и не залезает на полосу HUD
##   bubble_size        облачко на экране ни в одном кадре не выше 160 px (баг: в первый кадр строки — огромная панель)
##   line_events        KO соперника, Sudden Death и голосование зрителей — реплики N0; субтитра N0 в панели голосования нет
##   hotseat_join       Быстрый бой: P2-человек не в кадре, пока не нажал клавиш; нажал стрелку — кадр держит обоих
## Тело N0 (n0_drone.gd, «Тело»; отдельный дрон без боя):
##   anim_wings         крылья машут в плоскости экрана: размах за 1 с в полёте 8 м/с ≥ 0.4 рад и в 1.5 раза больше, чем в покое
##   anim_legs          разгон вправо 40 м/с² — кончики ножек отстают влево (≥ 0.4 рад) и возвращаются после остановки
##   anim_gestures      каждое выражение с жестом даёт свой жест, поза уходит от покоя ≥ 0.35 рад (рука или крыло)
##   anim_mic           микрофон всё время жестов у кисти правой руки (±1 мм)
extends Node

const FIGHT := preload("res://scenes/campaign/campaign_fight.tscn")
const QUICK := preload("res://scenes/playground_null_hall.tscn")
const DT := 1.0 / 60.0
## Сценарий клавиш P1: [действия, секунды].
const ROUTE := [
	[["p1_right"], 2.5], [["p1_up"], 1.5], [["p1_left"], 3.0], [["p1_left", "p1_up"], 1.5], [[], 1.0],
	[["p1_right", "p1_down"], 2.0], [["p1_right"], 2.5], [["p1_left"], 4.0], [[], 2.0],
]

const EXPECTED_CHECKS := 16

var checks: Array = []
var info := {}


func _ready() -> void:
	await _run()


func _run() -> void:
	DynamicCamera.user_zoom = 1.0   # проба про автокадрирование, не про масштаб игрока (по умолчанию 1.5×)
	_lines_rules()
	await _anim()
	await _campaign()
	await _hotseat()
	_finish()


# ------------------------------------------------------------------ бой кампании

func _fight() -> Node:
	var r: Dictionary = CampaignLeague.rival(CampaignLeague.LOCAL, 0)
	var f := FIGHT.instantiate()
	f.call("setup", CampaignLeague.start_blueprint(), CampaignLeague.rival_blueprint(CampaignLeague.LOCAL, r), r,
		CampaignLeague.rival_title(r), {"entrance": false})
	add_child(f)
	(f.get_node("Match") as Match).feel_enabled = false
	var vote := f.get_node("AudienceVote") as AudienceVote
	vote.enabled = false   # голосование проверяется отдельно (start_vote), поле не меняется посреди замеров
	return f


func _campaign() -> void:
	var f := _fight()
	var host: Node = f.get_node("N0/Host")
	(host.get("lines") as N0Lines).minor_chance = 0.0   # мелкие поводы не перебивают замеры реплик
	var cam := f.get_node("Camera") as DynamicCamera
	var p1 := f.get_node("P1") as Doll
	var p2 := f.get_node("P2") as Doll
	var n0 := f.get_node("N0") as N0Drone
	var speech: N0Speech = host.get("speech")
	# отсчёт: реплика «fight», облачко
	var said_fight := false
	var bubble_max_h := 0.0
	var bubble_ok := false
	var bubble_rect := Rect2()
	for i in int(Tuning.COUNTDOWN_S / DT) + 30:
		await get_tree().physics_frame
		if not said_fight:
			for e in (host.get("lines") as N0Lines).said:
				said_fight = said_fight or String(e["event"]) == "fight"
		if speech.shown():
			bubble_max_h = maxf(bubble_max_h, speech.bubble.size.y)
		if speech.shown() and speech.bubble.size.x > 10.0:
			bubble_rect = Rect2(speech.bubble.position, speech.bubble.size)
			var vs := get_viewport().get_visible_rect().size
			bubble_ok = bubble_rect.position.y >= vs.y * speech.top_band - 0.5 and Rect2(Vector2.ZERO, vs).encloses(bubble_rect)
	info["countdown_bubble"] = {"said": said_fight, "rect": [bubble_rect.position.x, bubble_rect.position.y, bubble_rect.size.x,
		bubble_rect.size.y], "text": speech.text}
	_check("line_countdown", said_fight and bubble_ok, str(info["countdown_bubble"]))
	# полёт по сценарию: замеры каждый кадр
	var near: Array[float] = []
	var opp_d: Array[float] = []
	var z_max := -INF
	var side_n := 0
	var side_ok := 0
	var slow_n := 0
	var slow_ok := 0
	var in_frame := 0
	var frames := 0
	var hh_max := 0.0
	var hh_min := INF
	var cx_err := 0.0
	var follow_only_p1 := true
	var side_since := 0.0
	var last_dx_sign := 0.0
	var vs := get_viewport().get_visible_rect().size
	for leg in ROUTE:
		for a in leg[0]:
			Input.action_press(String(a))
		for i in int(float(leg[1]) / DT):
			await get_tree().physics_frame
			await get_tree().process_frame
			if speech.shown():
				bubble_max_h = maxf(bubble_max_h, speech.bubble.size.y)
			var c1 := p1.centre_of_mass()
			var c2 := p2.centre_of_mass()
			var np := n0.global_position
			frames += 1
			near.append(Vector2(np.x - c1.x, np.y - c1.y).length())
			opp_d.append(Vector2(np.x - c2.x, np.y - c2.y).length())
			z_max = maxf(z_max, np.z)
			var sp := cam.unproject_position(np)
			if not cam.is_position_behind(np) and Rect2(Vector2.ZERO, vs).has_point(sp):
				in_frame += 1
			hh_max = maxf(hh_max, cam.half_height)
			hh_min = minf(hh_min, cam.half_height)
			var b := cam.view_bounds()
			var hw := cam.half_height * get_viewport().get_visible_rect().size.aspect()
			var want_cx := clampf(c1.x, b.position.x + hw, b.end.x - hw)
			cx_err = maxf(cx_err, absf(cam.centre.x - want_cx))
			var fd := cam.followed_dolls()
			follow_only_p1 = follow_only_p1 and fd.size() == 1 and fd[0] == p1 and cam.primary_doll() == p1
			var dx := c2.x - c1.x
			var sgn := signf(dx) if absf(dx) > 3.0 else 0.0
			if sgn != last_dx_sign:
				side_since = 0.0
				last_dx_sign = sgn
			side_since += DT
			if sgn != 0.0 and side_since >= 1.0:
				side_n += 1
				if float(host.get("side")) == -sgn:
					side_ok += 1
				if p1.torso().linear_velocity.length() < 2.0:
					slow_n += 1
					if signf(np.x - c1.x) == -sgn:
						slow_ok += 1
		for a in leg[0]:
			Input.action_release(String(a))
	near.sort()
	opp_d.sort()
	var p95 := near[int(near.size() * 0.95)]
	var opp_p3 := opp_d[int(opp_d.size() * 0.03)]
	info["flight"] = {"frames": frames, "near_p95": snappedf(p95, 0.01), "near_max": snappedf(near[near.size() - 1], 0.01),
		"z_max": snappedf(z_max, 0.01), "side": [side_ok, side_n], "side_slow": [slow_ok, slow_n], "in_frame": [in_frame, frames], "hh": [snappedf(hh_min, 0.01),
		snappedf(hh_max, 0.01)], "cam_cx_err": snappedf(cx_err, 0.01), "opp_p3": snappedf(opp_p3, 0.01),
		"opp_min": snappedf(opp_d[0], 0.01)}
	_check("bubble_size", bubble_max_h > 20.0 and bubble_max_h <= 160.0, "наибольшая высота облачка %.0f px" % bubble_max_h)
	_check("camera_on_player", follow_only_p1 and hh_min >= 3.6 - 0.01 and hh_max <= 5.5 and cx_err <= 2.0,
		"только P1 %s, полувысота %.2f…%.2f, центр от P1 до %.2f м" % [follow_only_p1, hh_min, hh_max, cx_err])
	_check("n0_near", p95 <= 3.5 and near[near.size() - 1] <= 6.0, "p95 %.2f м, max %.2f м" % [p95, near[near.size() - 1]])
	_check("n0_behind", z_max <= -0.8, "z max %.2f" % z_max)
	_check("n0_side", side_n > 30 and float(side_ok) / side_n >= 0.95 and slow_n > 10 and float(slow_ok) / slow_n >= 0.9,
		"сторона выбрана верно %d / %d, игрок почти стоит — N0 там %d / %d" % [side_ok, side_n, slow_ok, slow_n])
	_check("n0_in_frame", float(in_frame) / frames >= 0.98, "%d / %d" % [in_frame, frames])
	_check("n0_keeps_off_rival", opp_p3 >= 0.8, "3-й перцентиль %.2f м, минимум %.2f м" % [opp_p3, opp_d[0]])
	# соперник далеко: стрелка, метры от игрока
	var brain := p2.get_node("Brain")
	brain.process_mode = Node.PROCESS_MODE_DISABLED
	var c1 := p1.centre_of_mass()
	var shift := Vector3(c1.x + 22.0, c1.y, 0.0) - p2.centre_of_mass()
	for b in p2.parts.values():
		(b as RigidBody3D).global_position += shift
		(b as RigidBody3D).freeze = true
	for i in 40:
		await get_tree().physics_frame
		await get_tree().process_frame
	var marks := f.get_node("Offscreen")
	var found := {}
	for mk in marks.get("markers"):
		if int(mk["player"]) == 1:
			found = mk
	var real := Vector2(p2.centre_of_mass().x - p1.centre_of_mass().x, p2.centre_of_mass().y - p1.centre_of_mass().y).length()
	info["marker"] = {"dist": snappedf(float(found.get("dist", -1.0)), 0.01), "real": snappedf(real, 0.01),
		"pos": [snappedf((found.get("pos", Vector2.ZERO) as Vector2).x, 0.1), snappedf((found.get("pos", Vector2.ZERO) as Vector2).y, 0.1)],
		"half_height": snappedf(cam.half_height, 0.01)}
	_check("marker_from_player", not found.is_empty() and absf(float(found["dist"]) - real) <= 0.5
		and (found["pos"] as Vector2).x > vs.x * 0.8 and cam.half_height <= 5.5, str(info["marker"]))
	# поводы: KO соперника, Sudden Death, голосование
	var lines := host.get("lines") as N0Lines
	var m := f.get_node("Match") as Match
	var vote := f.get_node("AudienceVote") as AudienceVote
	var events: Array = []
	m.announce.emit("SUDDEN DEATH", Color.RED, "sudden_death")
	events.append(_last_event(lines))
	vote.enabled = true
	vote.start_vote()
	await get_tree().process_frame
	events.append(_last_event(lines))
	var panel_n0 := vote.get_node("Panel").find_child("N0Line", true, false) as Label
	var panel_quiet := panel_n0 == null or not panel_n0.visible
	m.ko.emit(p2, p1, {})
	events.append(_last_event(lines))
	m.ko.emit(p1, p2, {})
	events.append(_last_event(lines))
	info["events"] = events
	_check("line_events", events == ["sudden_death", "vote_start", "ko", "ko_player"] and speech.text != "" and panel_quiet,
		"%s, облачко «%s», панель без субтитра N0: %s" % [str(events), speech.text, panel_quiet])
	f.queue_free()
	await get_tree().physics_frame


func _last_event(lines: N0Lines) -> String:
	return String(lines.said[lines.said.size() - 1]["event"]) if not lines.said.is_empty() else ""


# ------------------------------------------------------------------ тело N0

func _anim() -> void:
	var d := (load("res://scenes/n0/n0.tscn") as PackedScene).instantiate() as N0Drone
	add_child(d)
	await get_tree().process_frame
	var ear := d.part("N0_Ear_L")
	var arm_r := d.part("N0_Arm_R")
	var mic := d.part("N0_Mic")
	var mic_rel := arm_r.transform.affine_inverse() * mic.transform.origin
	var mic_err := 0.0
	# крылья: размах за секунду в покое и в полёте
	var spans: Array[float] = []
	for v in [Vector3.ZERO, Vector3(8.0, 0.0, 0.0)]:
		var lo := INF
		var hi := -INF
		for i in 60:
			d.set_motion(v, Vector3.ZERO)
			await get_tree().process_frame
			var z := ear.transform.basis.get_euler().z
			lo = minf(lo, z)
			hi = maxf(hi, z)
		spans.append(hi - lo)
	info["anim_wings"] = {"idle": snappedf(spans[0], 0.01), "flight": snappedf(spans[1], 0.01)}
	_check("anim_wings", spans[1] >= 0.4 and spans[1] >= spans[0] * 1.5, str(info["anim_wings"]))
	# ножки: разгон вправо — отстают влево, после остановки — назад
	var legs := d.part("N0_Legs_L")
	var lag := 0.0
	for i in 30:
		d.set_motion(Vector3(4.0, 0.0, 0.0), Vector3(40.0, 0.0, 0.0))
		await get_tree().process_frame
		lag = minf(lag, legs.transform.basis.get_euler().z)
	for i in 120:
		d.set_motion(Vector3.ZERO, Vector3.ZERO)
		await get_tree().process_frame
	var back := legs.transform.basis.get_euler().z
	info["anim_legs"] = {"lag": snappedf(lag, 0.01), "back": snappedf(back, 0.01)}
	_check("anim_legs", lag <= -0.4 and absf(back) <= 0.2, str(info["anim_legs"]))
	# жесты по выражениям: поза уходит от покоя
	var idle_l := d.arm_direction("N0_Arm_L")
	var idle_r := d.arm_direction("N0_Arm_R")
	var idle_ear := ear.transform.basis.get_euler().z
	var gest := {}
	var ok_all := true
	for ex in ["excited", "happy", "shocked", "sad", "curious", "angry"]:
		d.flash_expression(ex, 1.0)
		var dev := 0.0
		for i in 24:
			await get_tree().process_frame
			mic_err = maxf(mic_err, ((arm_r.transform.affine_inverse() * mic.transform.origin) - mic_rel).length())
			dev = maxf(dev, maxf(d.arm_direction("N0_Arm_L").angle_to(idle_l), d.arm_direction("N0_Arm_R").angle_to(idle_r)))
			dev = maxf(dev, absf(ear.transform.basis.get_euler().z - idle_ear))
		gest[ex] = [d.gesture, snappedf(dev, 0.01)]
		ok_all = ok_all and d.gesture == String(N0Drone.GESTURE_OF[ex]) and dev >= 0.35
		for i in 70:
			await get_tree().process_frame
	info["anim_gestures"] = gest
	_check("anim_gestures", ok_all, str(gest))
	info["anim_mic"] = {"mic_err_mm": snappedf(mic_err * 1000.0, 0.01)}
	_check("anim_mic", mic_err <= 0.001, str(info["anim_mic"]))
	d.queue_free()
	await get_tree().process_frame


# ------------------------------------------------------------------ правила частоты

func _lines_rules() -> void:
	var l := N0Lines.new()
	l.minor_chance = 1.0
	var a := l.pick("head", 0.0, false) != ""
	var b := l.pick("head", 3.0, false) == ""           # кулдаун мелких
	var c := l.pick("membrane", 9.0, true) == ""        # N0 говорит — мелкое молчит
	var d := l.pick("membrane", 9.5, false) != ""
	var e := l.pick("crit", 10.0, true) != ""           # важное — всегда
	var g: bool = l.pick("vote_result", 30.0, false, ["ZERO G"]).contains("ZERO G")   # подстановка в строку
	var all_ru := true
	for k in N0Lines.LINES:
		for v in N0Lines.LINES[k]:
			all_ru = all_ru and String(v) != "" and String(Loc.table("en").get(v, "")) != ""   # ru в коде, en в locale/en.json
	var no_hint := not N0Lines.LINES.has("far")
	_check("lines_rules", a and b and c and d and e and g and all_ru and no_hint, "%s" % [[a, b, c, d, e, g, all_ru, no_hint]])


# ------------------------------------------------------------------ Быстрый бой вдвоём

func _hotseat() -> void:
	var pg := QUICK.instantiate()
	add_child(pg)
	(pg.get_node("Match") as Match).feel_enabled = false
	var vote := pg.get_node_or_null("AudienceVote") as AudienceVote
	if vote != null:
		vote.enabled = false
	var cam := pg.get_node("Camera") as DynamicCamera
	for i in 60:
		await get_tree().physics_frame
	var before := cam.followed_dolls().size()
	Input.action_press("p2_left")
	for i in 30:
		await get_tree().physics_frame
		await get_tree().process_frame
	Input.action_release("p2_left")
	var after := cam.followed_dolls().size()
	info["hotseat"] = {"before": before, "after": after, "half_height": snappedf(cam.half_height, 0.01)}
	_check("hotseat_join", before == 1 and after == 2, str(info["hotseat"]))
	pg.queue_free()
	await get_tree().physics_frame


func _check(id: String, ok: bool, text: String) -> void:
	checks.append({"id": id, "ok": ok, "info": text})
	print("%s %s — %s" % ["PASS" if ok else "FAIL", id, text])


func _finish() -> void:
	var ok := checks.size() == EXPECTED_CHECKS   # упавший скрипт сцены пропускает проверки — это провал, а не OK
	if not ok:
		print("FAIL checks_count — %d из %d" % [checks.size(), EXPECTED_CHECKS])
	for c in checks:
		ok = ok and bool(c["ok"])
	var fa := FileAccess.open("res://tests/n0_follow_probe_report.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify({"ok": ok, "checks": checks, "info": info}, "  "))
	fa.close()
	print("n0_follow_probe: %s (%d checks)" % ["OK" if ok else "FAIL", checks.size()])
	get_tree().quit(0 if ok else 1)
