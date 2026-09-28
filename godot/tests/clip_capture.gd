## Клип «эталон vs мы» (задача I, 28.09): оконная сцена на playground_void (Void, Match + HUD + DynamicCamera как в игре),
## скриптованный бой ~9.5 с сим-времени, каждый EVERY-й кадр → tests/clip/frame_%04d.png (при --fixed-fps 60 и EVERY 4 → 15 fps
## клипа, сим-время кадра детерминировано: Match считает hit stop / slow-mo от delta, не от часов).
## Сценарий (обе куклы external_input):
##   rest    0 … REST_S            — стоят на спавнах в позе покоя (Т-поза);
##   rush    наскок друг на друга (тяга к сопернику, как _rush в match_probe, и вверх к AIR_Y) до первого удара;
##   pause   PAUSE_S: P1 без ввода (возврат конечностей в позу, оседание-парение), P2 держит высоту;
##   charge  P1 с рывком (dash) несётся на P2, P2 без ввода; после удара P1 отпускает ввод;
##   wall    P2 летит к правой стене (x = +7), прилипает/скользит; до END_S. v7: обе куклы стартуют на SHIFT_X правее спавна Void
##           (иначе с отбросом RM ~2.4 м/с жертва до стены не долетала) — key_frames.wall = касание + 0.5 с (без касания — удар + 0.8 с).
##           shift=<м> — другой сдвиг. info.p2_wall: since_charge_s, v_in, part_vx_in, v_back_x, ratio (отскок), stick_s, slide_dy,
##           wall_collisions_after (stats считает касания частей ≥ Tuning.ENV_WALL_COLLISION_SPEED = 4 м/с).
## Пишет tests/clip/clip_report.json: по кадру t, фаза, ЦМ/скорость/угол торса обеих кукол (cvx/cvy — скорость ЦМ, w — ω торса °/с,
## flying, lag — отклонение плеч/бёдер от позы, °), удары, контакт со стеной, info.p2_flight_after_charge (v0, время до < 0.4 м/с, vy);
## key_frames — номера кадров моментов для листа сравнения (rest / hit / return / wall).
## v6.2: info.separation_first_hit / separation_charge_hit (|Δx ЦМ| в момент удара, +0.6, +1.0 с; скорость атакующего к жертве) и
## info.p2_wall (скорость до касания стены, отскок, отношение; contact=false — жертва до стены не долетела).
## Запуск: godot --path . --resolution 960x540 --position 100,100 --fixed-fps 60 res://tests/clip_capture.tscn -- "every=4,end=9.5"
## Сборка: ffmpeg -framerate 15 -i tests/clip/frame_%04d.png … (см. godot/README.md).
extends Node3D

const SCENE := "res://scenes/playground_void.tscn"
const OUT_DIR := "res://tests/clip"
const REST_S := 1.0
const PAUSE_S := 1.8
const RUSH_NEAR := 1.2
const AIR_Y := 2.8                  # высота ЦМ, на которой встречаются (в RM дерутся в воздухе)
const HOLD_Y := 3.8                 # P2 в паузе держит эту высоту: P1 после удара всплывает ~4.5 м, рывок идёт почти горизонтально
const AFTER_WALL_S := 2.6           # после контакта P2 со стеной снимаем ещё столько (прилипание/сползание, возврат в позу)
const WALL_X := 7.0
# v7: обе куклы сдвинуты к правой стене Void (спавн −3/+3 → −3+SHIFT_X/+3+SHIFT_X): с отбросом RM (2.4 м/с, гаснет за ~1.1 с) жертва
# после рывка пролетает ~1.5–2 м, и со спавна ±3 до стены x = 7 не долетала (v6.2: x ≈ 4.5, p2_wall.contact=false)
const SHIFT_X := 2.8                # 2.6 / 2.8 / 3.0 — касание через 0.5 / 0.37 / 0.22 с после рывка; 3.1–3.2 — удар рывком вскользь, до стены нет
const LAG_JOINTS := ["Shoulder_L", "Shoulder_R", "Hip_L", "Hip_R"]

var every := 4
var end_s := 9.5
var shift_x := SHIFT_X
var pg: Node3D
var p1: Doll
var p2: Doll
var match_node: Match
var t := 0.0
var frame := 0
var saved := 0
var phase := "rest"
var phase_t0 := 0.0
var first_hit_t := -1.0
var charge_hit_t := -1.0
var wall_t := -1.0
var wall_stats0 := 0                ## p2.stats.wall_collisions в момент касания (до него — спавн/наскок)
var hits: Array = []
var rows: Array = []
var done := false
var report := {"ok": true, "frames": 0, "rows": [], "key_frames": {}, "hits": [], "info": {}}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			match p[0]:
				"every": every = maxi(1, int(p[1]))
				"end": end_s = float(p[1])
				"shift": shift_x = float(p[1])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var d := DirAccess.open(OUT_DIR)
	if d != null:
		for f in d.get_files():
			if f.begins_with("frame_") and f.ends_with(".png"):
				d.remove(f)
	pg = load(SCENE).instantiate()
	for n in ["P1", "P2"]:
		(pg.get_node(n) as Node3D).position.x += shift_x   # до add_child: Match запоминает спавн при регистрации
	add_child(pg)
	p1 = pg.get_node("P1")
	p2 = pg.get_node("P2")
	match_node = pg.get_node("Match")
	match_node.countdown_s = 0.0   # _late_ready (deferred) ещё не начал матч: FIGHT! сразу
	p1.external_input = true
	p2.external_input = true
	match_node.hit.connect(func(victim: Doll, attacker: Node, damage: float, kind: String, _pos: Vector3) -> void:
		hits.append({"t": snappedf(t, 0.01), "frame": saved, "victim": victim.name, "attacker": attacker.name if attacker != null else "", "damage": snappedf(damage, 0.01), "kind": kind})
		if first_hit_t < 0.0:
			first_hit_t = t
		if phase == "charge" and charge_hit_t < 0.0:
			charge_hit_t = t)
	report["info"]["resolution"] = var_to_str(get_viewport().get_visible_rect().size)
	report["info"]["every"] = every


func _set_phase(p: String) -> void:
	phase = p
	phase_t0 = t


## Тяга к сопернику по X; по Y — к высоте target_y (или к сопернику, если target_y < 0).
func _toward(d: Doll, other: Doll, target_y: float) -> Vector2:
	var dc := d.centre_of_mass()
	var oc := other.centre_of_mass()
	var dx := oc.x - dc.x
	var sgn := signf(dx) if absf(dx) > 0.05 else 1.0
	var ty := target_y if target_y >= 0.0 else oc.y
	var vy := clampf((ty - dc.y) / 0.8, -1.0, 1.0)
	return Vector2(sgn, vy)


## Удержание высоты без движения по X (P2 «висит» в паузе, как idle-враг RM).
func _hold(d: Doll, y: float) -> Vector2:
	var c := d.centre_of_mass()
	var vy := d.torso().linear_velocity.y
	return Vector2(0.0, clampf((y - c.y) * 0.9 - vy * 0.6 + Tuning.GRAVITY / Tuning.MOVE_FORCE_PER_KG, -1.0, 1.0))


func _physics_process(delta: float) -> void:
	if done:
		return
	t += delta
	var dist := absf(p1.centre_of_mass().x - p2.centre_of_mass().x)
	match phase:
		"rest":
			p1.input_vec = Vector2.ZERO
			p2.input_vec = Vector2.ZERO
			if t >= REST_S:
				_set_phase("rush")
		"rush":
			# наскок: оба к сопернику и чуть вверх (в RM дерутся в воздухе)
			p1.input_vec = _toward(p1, p2, AIR_Y)
			p2.input_vec = _toward(p2, p1, AIR_Y)
			if first_hit_t >= 0.0 or dist < RUSH_NEAR * 0.5 or t - phase_t0 > 3.0:
				_set_phase("pause")
		"pause":
			p1.input_vec = Vector2.ZERO          # P1 без ввода: возврат в позу и оседание (парение)
			p2.input_vec = _hold(p2, HOLD_Y)     # P2 держит высоту
			if t - phase_t0 >= PAUSE_S:
				_set_phase("charge")
				p1.dash_until = p1._time + Tuning.DASH_DURATION_S   # как Shift: рывок
		"charge":
			p2.input_vec = Vector2.ZERO
			p1.input_vec = _toward(p1, p2, -1.0)
			if charge_hit_t >= 0.0 and t - charge_hit_t > 0.15 or t - phase_t0 > 3.0:
				p1.dash_until = 0.0
				_set_phase("wall")
		"wall":
			p1.input_vec = Vector2.ZERO
			p2.input_vec = Vector2.ZERO
	if wall_t < 0.0 and phase == "wall" and _max_x(p2) > WALL_X - 0.25:
		wall_t = t
		wall_stats0 = int(p2.stats.get("wall_collisions", 0))
	if t >= end_s or (wall_t >= 0.0 and t >= wall_t + AFTER_WALL_S and t >= 8.0):
		done = true
		_finish()


## v7: max скорость части по +X (к правой стене) — для телеметрии стены: stats.wall_collisions считает касания ≥ ENV_WALL_COLLISION_SPEED.
func _max_part_vx(d: Doll) -> float:
	var mx := -INF
	for b in d.parts.values():
		if is_instance_valid(b):
			mx = maxf(mx, (b as RigidBody3D).linear_velocity.x)
	return mx


func _max_x(d: Doll) -> float:
	var mx := -INF
	for b in d.parts.values():
		if is_instance_valid(b):
			mx = maxf(mx, (b as RigidBody3D).global_position.x)
	return mx


func _doll_row(d: Doll) -> Dictionary:
	var c := d.centre_of_mass()
	var tr := d.torso()
	var v := tr.linear_velocity if is_instance_valid(tr) else Vector3.ZERO
	var ang := rad_to_deg(tr.global_rotation.z) if is_instance_valid(tr) else 0.0
	var cv := _com_velocity(d)
	var row := {"x": snappedf(c.x, 0.001), "y": snappedf(c.y, 0.001), "vx": snappedf(v.x, 0.01), "vy": snappedf(v.y, 0.01), "rot": snappedf(ang, 0.1), "hp": snappedf(d.hp, 0.1), "max_x": snappedf(_max_x(d), 0.01),
		"cvx": snappedf(cv.x, 0.01), "cvy": snappedf(cv.y, 0.01), "w": snappedf(rad_to_deg(tr.angular_velocity.z) if is_instance_valid(tr) else 0.0, 1.0), "flying": d.is_flying(),
		"pvx_max": snappedf(_max_part_vx(d), 0.01)}
	# запаздывание конечностей (FEEL_TARGET §9): отклонение плеч/бёдер от позы покоя, градусы (пока суставы целы)
	var pose := d.get_pose()
	var lag := {}
	for jn in LAG_JOINTS:
		if d.joints.has(jn):
			var j: Generic6DOFJoint3D = d.joints[jn]
			var a := j.get_node_or_null(j.node_a) as RigidBody3D
			var b := j.get_node_or_null(j.node_b) as RigidBody3D
			if a != null and b != null:
				lag[jn] = snappedf(rad_to_deg(wrapf(b.global_rotation.z - a.global_rotation.z - deg_to_rad(float(pose.get(jn, 0.0))), -PI, PI)), 0.1)
	row["lag"] = lag
	return row


static func _com_velocity(d: Doll) -> Vector3:
	var acc := Vector3.ZERO
	var m := 0.0
	for b in d.parts.values():
		if is_instance_valid(b):
			acc += (b as RigidBody3D).linear_velocity * (b as RigidBody3D).mass
			m += (b as RigidBody3D).mass
	return acc / maxf(m, 0.001)


## Телеметрия полёта жертвы после удара рывком (FEEL_TARGET §9, RM: ≤ 3 H/с, гаснет до < 0.4 м/с за ~1–1.5 с, оседание ≤ 1.4 м/с).
func _flight_summary(victim: String, t_hit: float) -> Dictionary:
	if t_hit < 0.0:
		return {}
	var v0 := 0.0
	var stop := -1.0
	var vy1 := 0.0
	var vy2 := 0.0
	var vy_min := 0.0
	for r in rows:
		var since := float(r["t"]) - t_hit
		if since < 0.0:
			continue
		var d: Dictionary = r[victim]
		var cvx := absf(float(d["cvx"]))
		if since <= 0.5:
			v0 = maxf(v0, cvx)
		elif stop < 0.0 and cvx < 0.4:
			stop = since
		if since >= 0.5:
			vy_min = minf(vy_min, float(d["cvy"]))
		if since <= 1.0:
			vy1 = float(d["cvy"])
		if since <= 2.0:
			vy2 = float(d["cvy"])
	return {"v0_com_x": snappedf(v0, 0.01), "stop_s": snappedf(stop, 0.01), "vy_1s": snappedf(vy1, 0.01), "vy_2s": snappedf(vy2, 0.01), "vy_min": snappedf(vy_min, 0.01)}


## Разлёт после удара (v6.2, критик круга 2: у RM жертва уходит ~1 H/с, бьющий зависает поодаль): |Δx ЦМ| кукол в момент удара,
## через 0.6 и 1.0 с, скорость ЦМ атакующего по x через 0.3 с (со знаком: > 0 — к жертве, если жертва справа).
func _separation_summary(t_hit: float, attacker: String) -> Dictionary:
	if t_hit < 0.0:
		return {}
	var out := {}
	var marks := {"sep_at_hit_m": 0.0, "sep_0p6s_m": 0.6, "sep_1s_m": 1.0}
	for key in marks:
		var best: Dictionary = {}
		var bd := INF
		for r in rows:
			var dd := absf(float(r["t"]) - (t_hit + float(marks[key])))
			if dd < bd:
				bd = dd
				best = r
		if not best.is_empty():
			out[key] = snappedf(absf(float((best["p1"] as Dictionary)["x"]) - float((best["p2"] as Dictionary)["x"])), 0.01)
			if key == "sep_0p6s_m":
				var a: Dictionary = best[attacker]
				var v: Dictionary = best["p2" if attacker == "p1" else "p1"]
				out["attacker_cvx_toward_victim_0p6s"] = snappedf(float(a["cvx"]) * signf(float(v["x"]) - float(a["x"])), 0.01)
	return out


## Стена (FEEL_TARGET §7, RM ≤ 0.1): |v ЦМ| P2 в последнем кадре до касания и max за 0.5 с после; -1, если стены не было.
## v7: since_charge_s — касание через столько после удара рывком; part_vx_in — max скорость части к стене в кадре до касания
## (stats.wall_collisions считает только ≥ Tuning.ENV_WALL_COLLISION_SPEED); stick_s — сколько P2 держится у стены (max_x ≥ WALL_X − 0.4)
## после касания; slide_dy — на сколько сполз ЦМ за это время; wall_collisions_after — прирост статистики после касания.
func _wall_summary() -> Dictionary:
	if wall_t < 0.0:
		return {"contact": false}
	var v_in := 0.0
	var v_out := 0.0
	var pv_in := 0.0
	var stick := 0.0
	var y0 := -INF
	var y1 := 0.0
	var stuck := true
	for r in rows:
		var d: Dictionary = r["p2"]
		var since := float(r["t"]) - wall_t
		var sp := Vector2(float(d["cvx"]), float(d["cvy"])).length()
		if since < 0.0:
			v_in = sp
			pv_in = float(d.get("pvx_max", 0.0))
		else:
			if since >= 0.1 and since <= 0.5:
				v_out = maxf(v_out, float(d["cvx"]) * -1.0)   # отскок от правой стены — vx < 0
			if stuck and float(d["max_x"]) >= WALL_X - 0.4:
				stick = since
				if y0 == -INF:
					y0 = float(d["y"])
				y1 = float(d["y"])
			elif since > 0.1:
				stuck = false
	return {"contact": true, "since_charge_s": snappedf(wall_t - charge_hit_t, 0.01) if charge_hit_t >= 0.0 else -1.0,
		"v_in": snappedf(v_in, 0.01), "part_vx_in": snappedf(pv_in, 0.01), "v_back_x": snappedf(maxf(v_out, 0.0), 0.01),
		"ratio": snappedf(maxf(v_out, 0.0) / v_in if v_in > 0.01 else 0.0, 0.01), "stick_s": snappedf(stick, 0.01),
		"slide_dy": snappedf(y1 - y0 if y0 > -INF else 0.0, 0.01),
		"wall_collisions_after": int(p2.stats.get("wall_collisions", 0)) - wall_stats0, "stat_speed": Tuning.ENV_WALL_COLLISION_SPEED}


func _process(_delta: float) -> void:
	if done:
		return
	frame += 1
	if frame % every != 0:
		return
	var idx := saved
	saved += 1
	var row := {"frame": idx, "t": snappedf(t, 0.001), "phase": phase, "p1": _doll_row(p1), "p2": _doll_row(p2), "ts": snappedf(Engine.time_scale, 0.01)}
	rows.append(row)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT_DIR).path_join("frame_%04d.png" % idx))


func _first_attacker() -> String:
	for h in hits:
		if String((h as Dictionary)["attacker"]) == "P2":
			return "p2"
		if String((h as Dictionary)["attacker"]) == "P1":
			return "p1"
	return "p1"


func _frame_at(time_s: float) -> int:
	var best := 0
	var bd := INF
	for r in rows:
		var dd := absf(float(r["t"]) - time_s)
		if dd < bd:
			bd = dd
			best = int(r["frame"])
	return best


func _finish() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	report["frames"] = saved
	report["rows"] = rows
	report["hits"] = hits
	var kf := {"rest": _frame_at(REST_S * 0.8)}
	if first_hit_t >= 0.0:
		kf["hit"] = _frame_at(first_hit_t + 0.07)
		kf["return"] = _frame_at(first_hit_t + 0.9)
	if wall_t >= 0.0:
		kf["wall"] = _frame_at(wall_t + 0.5)   # прилип и сползает, вспышка контакта уже погасла
	elif charge_hit_t >= 0.0:
		kf["wall"] = _frame_at(charge_hit_t + 0.8)
	report["key_frames"] = kf
	report["info"]["first_hit_t"] = snappedf(first_hit_t, 0.01)
	report["info"]["charge_hit_t"] = snappedf(charge_hit_t, 0.01)
	report["info"]["wall_t"] = snappedf(wall_t, 0.01)
	report["info"]["p2_wall_collisions"] = p2.stats.get("wall_collisions", 0)
	report["info"]["p2_flight_after_charge"] = _flight_summary("p2", charge_hit_t)
	report["info"]["separation_first_hit"] = _separation_summary(first_hit_t, _first_attacker())
	report["info"]["separation_charge_hit"] = _separation_summary(charge_hit_t, "p1")
	report["info"]["p2_wall"] = _wall_summary()
	report["info"]["sim_s"] = snappedf(t, 0.01)
	var ok := saved > 0 and first_hit_t >= 0.0 and charge_hit_t >= 0.0
	report["ok"] = ok
	var f := FileAccess.open(OUT_DIR.path_join("clip_report.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
	print("CLIP frames=%d first_hit=%.2f charge_hit=%.2f wall=%.2f key=%s %s" % [saved, first_hit_t, charge_hit_t, wall_t, str(kf), "OK" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)
