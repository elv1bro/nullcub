## Проба режима волн PvE (scenes/playground_pve.tscn: Свалка, P1, WaveDirector, враги scenes/enemies/*): весело ли драться с
## физическими куклами под управлением ИИ — сначала цифрами. Каждый сценарий — свой инстанс площадки (P2 убран, кооп выключен).
## Сценарии (mode=full — все подряд, headless --fixed-fps 60; иначе один по имени):
##   sweep        — P1 стоит без оружия, ввод 0; Уборщик сбоку: за SWEEP_S секунд переносит P1 к пропасти (медиана смещения по x ≥ 3 м;
##                  на пути стопка ящиков x −0.9 и ShippingCrate 80 кг у края x −5 — за край выходит не всегда, это в info); каждый
##                  удар — после телеграфа ≥ 0.35 с; урон по P1;
##   sweep_lane   — то же без ящиков на дорожке к провалу: за SWEEP_MAX_S P1 за краем (или в провале) в большинстве прогонов, медиана
##                  толчка за 15 с ≥ 4.5 м; сколько раз упал ВНИЗ — в info (над провалом балка PitBeam, на неё иногда ложится);
##   steal_weapon — P1 стоит с молотом, откручивать детали нельзя (лимит исчерпан): Разборщик выдёргивает молот из кисти и удирает
##                  (за 2 с после кражи дальше от P1 на ≥ 3 м); потом P1-бот гонится, удар по Разборщику — молот падает;
##   steal_part   — P1 стоит с молотом в правой (рука-мышь): Разборщик хватает ЛЕВУЮ кисть, откручивает (Doll.detach_part), удирает
##                  с ней; сразу после — кулдаун (второму Разборщику откручивать нечего), правая кисть на месте; удар — роняет кисть;
##   clear_wave1  — настоящий забег: intro, волна 1 (2 Разборщика) из желоба; P1-бот с молотом (наскок как tests/match_probe.gd, рывок
##                  request_dash) зачищает волну: время зачистки, урон в обе стороны (волна не беззубая: P1 получил урон; и не
##                  неубиваемая: зачищена за CLEAR_MAX_S), кражи, враги подходили к P1 ближе 1.5 м;
##   pit          — враг над пропастью (мозг молчит) падает: KO, WaveDirector.kills.pit, enemy_down(cause "pit");
##   waves        — полный цикл волн ускоренно (враги KO напрямую): состав волн 2 / 1+2 / 2+3 по видам, HP врагов 40/80, строки Башни,
##                  победа, запоздавшая бочка, restart (враги убраны, P1 новый, team), поражение (все игроки KO);
##   coop         — F2: P2 в забеге, команда players у обоих, две панели HUD, волна идёт;
##   reattach     — возврат оторванной детали: касанием, клавишей захвата, рука-мышь (ArmAssist снова управляет), чужую — нельзя;
##                  в steal_part — после удара по вору P1 долетает до уроненной кисти и прикручивает её;
##   bounds       — во всех сценариях ЦМ каждого живого врага в границах арены (или над пропастью), нарушений 0.
## sweep / sweep_lane / steal_weapon / steal_part / clear_wave1 (и run) идут trials раз (trials=N, по умолчанию 3): физика рэгдоллов от прогона к прогону
## не повторяется точь-в-точь — проверки по большинству прогонов и медиане, в отчёте — каждый прогон.
## mode=perf (НЕ headless, окно 1920×1080): 5 врагов (2 Уборщика + 3 Разборщика) и P1-бот дерутся PERF_S с; avg fps ≥ min_fps (55).
## mode=shots (НЕ headless): кадры docs/plan-demo/img/pve-v1-{wave,sweep,steal,clear}.png.
## Запуск: godot --headless --path . --fixed-fps 60 res://tests/pve_probe.tscn -- "mode=full"
##         godot --path . --resolution 1920x1080 res://tests/pve_probe.tscn -- "mode=perf,min_fps=55"
##         godot --path . --resolution 1920x1080 res://tests/pve_probe.tscn -- "mode=shots"
##         godot --headless --path . --fixed-fps 60 res://tests/pve_probe.tscn -- "mode=run,trials=3"   (весь забег ботом, отдельно)
## full с trials=3 идёт ≈ 3–7 мин (от загрузки машины); trials=1 — быстрый прогон (≈ 1.5–2.5 мин), но проверки по одному прогону.
## Отчёт tests/pve_probe_report.json (full; другие режимы — tests/pve_probe_<mode>_report.json) + stdout, exit 0/1.
extends Node3D

const PG_SCENE := "res://scenes/playground_pve.tscn"
const SWEEP_S := 15.0
const SWEEP_MAX_S := 24.0              # sweep_lane: столько ждём падения в пропасть
const STEAL_WAIT_S := 14.0
const CHASE_S := 8.0
const FETCH_S := 10.0
const CLEAR_MAX_S := 75.0
const PERF_S := 8.0
const PERF_WARM_S := 2.0
const SHOT_DIR := "res://../docs/plan-demo/img/"

const TRIALED := ["sweep", "sweep_lane", "steal_weapon", "steal_part", "clear_wave1", "run"]
const RUN_MAX_S := 240.0
## Ящики между центром Свалки и провалом (стопка у x −0.9, ShippingCrate 80 кг у края x −5) — sweep_lane убирает их из арены.
const LANE_PROPS := ["Props/Crate", "Props/ReinforcedCrate", "Props/ShippingCrate"]

var mode := "full"
var min_fps := 55.0
var trials := 3
var report := {"ok": true, "checks": [], "info": {}}
var pg: Node3D
var director: WaveDirector
var p1: Doll
var t := 0.0
var bounds_bad := 0
var bounds_samples := 0
var bounds_worst := ""
var _bot: Dictionary = {}                # Doll -> {"retreat_until": float}
var _frame := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			match p[0]:
				"mode": mode = p[1]
				"min_fps": min_fps = float(p[1])
				"trials": trials = maxi(int(p[1]), 1)
	report["info"]["mode"] = mode
	report["info"]["trials"] = trials
	await get_tree().process_frame
	match mode:
		"perf":
			await _perf()
		"shots":
			await _shots()
		_:
			var all := ["sweep", "sweep_lane", "steal_weapon", "steal_part", "clear_wave1", "pit", "waves", "coop", "reattach"]
			var list: Array = all if mode == "full" else [mode]   # run (весь забег ботом) — только отдельно: mode=run
			for s in list:
				if TRIALED.has(s):
					var runs: Array = []
					for i in range(trials):
						print("--- %s #%d ---" % [s, i + 1])
						var rr: Variant = await call("_r_" + s, i)
						runs.append(rr if rr is Dictionary else {"crashed": true})   # оборвался ошибкой — прогон не засчитан
					report["info"][s] = runs
					call("_agg_" + s, runs)
				else:
					print("--- %s ---" % s)
					await call("_s_" + s)
			_check("bounds", float(bounds_bad), 0.0, "eq", "enemy CoM inside arena bounds (or over the pit): bad %d of %d samples %s" % [bounds_bad, bounds_samples, bounds_worst])
	_finish()


# ------------------------------------------------------------------ площадка

func _load(auto_waves: bool, feel := false) -> void:
	if pg != null and is_instance_valid(pg):
		pg.free()   # прошлый сценарий оборвался ошибкой, не дойдя до _unload: его куклы и враги не должны жить в этом
	seed(20260929)   # глобальный randf (обломки ящиков, разлёт KO) — одинаковый в каждом сценарии и прогоне
	ScraplingBrain.victim_log.clear()
	Engine.time_scale = 1.0
	pg = (load(PG_SCENE) as PackedScene).instantiate()
	director = pg.get_node("WaveDirector")
	director.auto_waves = auto_waves
	director.feel_enabled = feel
	add_child(pg)
	p1 = pg.get_node("P1")
	p1.external_input = true
	p1.input_vec = Vector2.ZERO
	_bot.clear()
	t = 0.0
	await get_tree().process_frame
	await get_tree().physics_frame


func _unload() -> void:
	if pg != null and is_instance_valid(pg):
		pg.queue_free()
	pg = null
	Engine.time_scale = 1.0
	await get_tree().process_frame
	await get_tree().process_frame


## Шаг физики: время, выборка границ.
func _step() -> void:
	await get_tree().physics_frame
	t += get_physics_process_delta_time()
	_frame += 1
	if _frame % 15 == 0:
		_sample_bounds()


func _steps(seconds: float) -> void:
	var n := int(seconds * 60.0)
	for i in range(n):
		await _step()


func _sample_bounds() -> void:
	if director == null or not is_instance_valid(director):
		return
	var a: Node = pg.get_node_or_null("Scrap")
	if a == null:
		return
	var b: AABB = a.call("bounds")
	var pr: Rect2 = a.get("pit_rect")
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Doll
		if e == null or not e.alive or not e.is_inside_tree():
			continue
		var c := e.centre_of_mass()
		bounds_samples += 1
		var inside := b.grow(0.5).has_point(Vector3(c.x, c.y, 0.0))
		var over_pit := c.x > pr.position.x - 0.5 and c.x < pr.end.x + 0.5 and c.y > -9.5
		if not inside and not over_pit:
			bounds_bad += 1
			bounds_worst = "%s at %s" % [e.name, c]


## Отладочная трасса врага раз в 20 тиков (в отчёт): состояние, ЦМ, скорость, ввод, HP.
func _trace(arr: Array, e: Doll, br: EnemyBrain) -> void:
	if _frame % 20 != 0 or arr.size() >= 80 or not is_instance_valid(e) or not e.alive:
		return
	var c := e.centre_of_mass()
	var pc := p1.centre_of_mass() if is_instance_valid(p1) else Vector3.ZERO
	var extra := ""
	if OS.get_environment("PVE_DEBUG") != "":
		var names: Array = []
		for bd in e.torso().get_colliding_bodies():
			names.append(String(bd.name))
		extra = " lock%.2f dash%s ctrl%s col%s" % [maxf(e.thrust_lock_until - float(e.get("_time")), 0.0), e.is_dashing(), e.control_enabled, names]
	arr.append("%.1f %s (%.2f,%.2f) v%.1f in(%.2f,%.2f) hp%.0f p1(%.2f,%.2f)%s%s" % [t, br.state, c.x, c.y, e.torso().linear_velocity.length(),
		e.input_vec.x, e.input_vec.y, e.hp, pc.x, pc.y, " STUN" if e.is_stunned() else "", extra])


func _wp(d: Doll) -> WeaponPickup:
	for c in d.get_children():
		if c is WeaponPickup:
			return c
	return null


func _give_hammer(d: Doll, hand := "Hand_R") -> Weapon:
	var h := pg.get_node("Weapons/Hammer") as Weapon
	var wp := _wp(d)
	if h != null and wp != null:
		if h.is_held():
			h.drop()
		wp.attach(hand, h)
	return h


## Бот-игрок: наскок как tests/match_probe.gd (разбег → отход RETREAT_S → разбег, рывок с ≥ 2.5 м, если есть request_dash).
func _bot_rush(d: Doll, target: Doll) -> void:
	if d == null or not d.alive:
		return
	if target == null or not is_instance_valid(target) or not target.alive:
		d.input_vec = Vector2.ZERO
		return
	var st: Dictionary = _bot.get(d, {"retreat_until": -1.0})
	var dc := d.centre_of_mass()
	var oc := target.centre_of_mass()
	var dx := oc.x - dc.x
	var dy := oc.y - dc.y
	var sgn := signf(dx) if absf(dx) > 0.05 else 1.0
	var vy := clampf(dy / 1.2, -1.0, 1.0) if absf(dy) > 0.5 else 0.0
	if t < float(st["retreat_until"]):
		d.input_vec = Vector2(-sgn, 0.3)
	elif absf(dx) < 1.2 and absf(dy) < 1.2:
		st["retreat_until"] = t + 0.9
		d.input_vec = Vector2(-sgn, 0.3)
	else:
		if Vector2(dx, dy).length() > 2.5 and d.has_method("request_dash") and float(d.get("_time")) >= d.dash_ready_at:
			d.call("request_dash")
		d.input_vec = Vector2(sgn, vy)
	_bot[d] = st


func _nearest_enemy(from: Doll) -> Doll:
	var best: Doll = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Doll
		if e == null or not e.alive or not e.is_inside_tree():
			continue
		var dd := e.centre_of_mass().distance_to(from.centre_of_mass())
		if dd < best_d:
			best_d = dd
			best = e
	return best


# ------------------------------------------------------------------ сценарии

## Физика кукол (Jolt, контакты рэгдоллов) от прогона к прогону не повторяется точь-в-точь, поэтому поведенческие сценарии идут
## trials раз (по умолчанию 3) и проверяются большинством / медианой; в отчёте — каждый прогон.

func _r_sweep(i: int, lane := false) -> Dictionary:
	await _load(false)
	director.begin_manual()
	if lane:
		for pth in LANE_PROPS:
			var n := pg.get_node_or_null("Scrap/" + pth)
			if n != null:
				n.get_parent().remove_child(n)
				n.queue_free()
	_wp(p1).auto_pickup = false
	var x0 := p1.centre_of_mass().x
	var sw := director.spawn_enemy("sweeper", Vector3(x0 + 4.0, 0.05, 0.0), Vector3.ZERO, 0.3)
	var br := WaveDirector.brain_of(sw) as SweeperBrain
	var hp0 := sw.hp
	var mhp := sw.max_hp
	var pit_x := -6.5
	var min_x := x0
	var fell_t := -1.0
	var edge_t := -1.0
	var disp_at_10 := -1.0
	var disp_at_15 := -1.0
	var trace_: Array = []
	var t_end := SWEEP_MAX_S if lane else SWEEP_S + 0.05   # с ящиками — только 15 с (за край за 30 с выходило 0–1 из 3)
	while t < t_end and fell_t < 0.0:
		await _step()
		if i == 0:
			_trace(trace_, sw, br)
		if p1.alive:
			min_x = minf(min_x, p1.centre_of_mass().x)
			if edge_t < 0.0 and min_x <= pit_x:
				edge_t = t
		elif fell_t < 0.0:
			fell_t = t
		if t >= 10.0 and disp_at_10 < 0.0:
			disp_at_10 = x0 - min_x
		if t >= SWEEP_S and disp_at_15 < 0.0:
			disp_at_15 = x0 - min_x
	var in_pit := not p1.alive and String(p1.last_ko_record.get("kind", "")) == "self"
	if disp_at_15 < 0.0:
		disp_at_15 = 99.0 if in_pit else x0 - min_x   # упал в провал раньше 15 с
	var r := {
		"sweeper_hp": hp0, "sweeper_max_hp": mhp, "displacement_10s_m": snappedf(disp_at_10, 0.01), "displacement_15s_m": snappedf(disp_at_15, 0.01),
		"displacement_max_m": snappedf(x0 - min_x, 0.01), "edge_t": snappedf(edge_t, 0.01), "fell_in_pit": in_pit, "fell_t": snappedf(fell_t, 0.01),
		"reached_pit": in_pit or edge_t >= 0.0, "sweeps": br.sweeps, "scoops": br.scoops, "telegraph_min_s": _min_arr(br.telegraph_durations),
		"p1_damage_taken": snappedf(float(p1.stats["damage_taken"]), 0.1), "sweeper_damage_dealt": snappedf(float(sw.stats["damage_dealt"]), 0.1),
		"sweeper_hp_lost": snappedf(hp0 - sw.hp, 0.1), "states": br.counters.duplicate(), "has_broom": br.has_broom(),
	}
	if i == 0:
		r["trace"] = trace_
	print("  sweep%s #%d: 15 s %.2f m, max %.2f m, edge %.1f s, pit %s at %.1f s, sweeps %d (scoops %d), P1 -%.1f HP" % [" lane" if lane else "", i + 1, disp_at_15, x0 - min_x, edge_t, in_pit, fell_t, br.sweeps, br.scoops, float(r["p1_damage_taken"])])
	await _unload()
	return r


func _agg_sweep(runs: Array) -> void:
	_check("sweeper_hp", float(runs[0].get("sweeper_hp", 0.0)), 80.0, "eq", "Sweeper hp at spawn = Doll.max_hp 80 (%s)" % runs[0].get("sweeper_max_hp", "?"))
	_check("sweep_telegraph", _min_key(runs, "telegraph_min_s"), 0.35, "gte", "every sweep telegraphed >= 0.35 s")
	_check("sweep_pushes_to_pit", _median_key(runs, "displacement_15s_m"), 3.0, "gte", "idle P1 pushed toward the pit, median over %d runs, m in %.0f s: %s" % [runs.size(), SWEEP_S, _col(runs, "displacement_15s_m")])
	var edge_n := _count_true(runs, "reached_pit")
	report["info"]["sweep_reached_pit_runs"] = "%d/%d" % [edge_n, runs.size()]
	print("  info sweep: over the pit edge in %d of %d runs within %.0f s (arena as is: crate stack x −0.9, ShippingCrate 80 kg at the edge x −5, PitBeam y=2 over the pit)" % [edge_n, runs.size(), SWEEP_S])
	_check("sweep_damage", _median_key(runs, "p1_damage_taken"), 5.0, "gte", "Sweeper hurts P1 (HP per run %s)" % [_col(runs, "p1_damage_taken")])


## То же на чистой дорожке: ящики между центром и провалом убраны — сколько Уборщику нужно, чтобы смести стоящего в провал.
func _r_sweep_lane(i: int) -> Dictionary:
	return await _r_sweep(i, true)


func _agg_sweep_lane(runs: Array) -> void:
	# за край провала — задача Уборщика; упадёт ли кукла ВНИЗ, решает балка PitBeam (y 2) над провалом: подброшенная метлой кукла
	# иногда ложится на неё (1 из 3 прогонов) — поэтому «в провал» в info, а проверка — «за край или в провал» + сила толчка
	var fell := _count_true(runs, "fell_in_pit")
	report["info"]["sweep_lane_fell_runs"] = "%d/%d" % [fell, runs.size()]
	print("  info sweep_lane: INTO the pit in %d of %d runs (fell at %s s)" % [fell, runs.size(), _col(runs, "fell_t")])
	_check("sweep_lane_over_edge", float(_count_true(runs, "reached_pit")), _majority(runs), "gte", "no crates on the way: idle P1 swept over the pit edge or into the pit within %.0f s in most runs (edge at %s s, fell at %s s)" % [SWEEP_MAX_S, _col(runs, "edge_t"), _col(runs, "fell_t")])
	_check("sweep_lane_push", _median_key(runs, "displacement_15s_m"), 4.5, "gte", "no crates: median push toward the pit in %.0f s, m %s (99 = уже в провале)" % [SWEEP_S, _col(runs, "displacement_15s_m")])
	_check("sweep_lane_telegraph", _min_key(runs, "telegraph_min_s"), 0.35, "gte", "every sweep telegraphed >= 0.35 s")


func _r_steal_weapon(i: int) -> Dictionary:
	await _load(false)
	director.begin_manual()
	var hammer := _give_hammer(p1)
	ScraplingBrain.victim_log[p1.get_instance_id()] = {"t": 1e9, "n": 99}   # откручивать нельзя — только оружие
	var x0 := p1.centre_of_mass().x
	var sc := director.spawn_enemy("scrapling", Vector3(x0 + 5.0, 1.0, 0.0), Vector3.ZERO, 0.2)
	var br := WaveDirector.brain_of(sc) as ScraplingBrain
	var r := {"scrapling_hp": sc.hp, "scrapling_max_hp": sc.max_hp, "stolen": false}
	var tele: Array = br.telegraph_durations   # по ссылке: вора могут убить и убрать раньше конца сценария
	var counters: Dictionary = br.counters
	var steal_t := -1.0
	var min_d := INF
	var trace_: Array = []
	while t < STEAL_WAIT_S and steal_t < 0.0 and is_instance_valid(sc) and sc.alive:
		await _step()
		_trace(trace_, sc, br)
		if not is_instance_valid(sc) or not sc.alive:
			break
		min_d = minf(min_d, sc.centre_of_mass().distance_to(p1.centre_of_mass()))
		if hammer.is_held() and hammer.holder == _wp(sc):
			steal_t = t
	r["stolen"] = steal_t >= 0.0
	r["steal_t"] = snappedf(steal_t, 0.01)
	r["closest_m"] = snappedf(min_d, 0.01)
	if steal_t >= 0.0:
		r.merge(await _measure_flee(sc, br, trace_))
		r.merge(await _chase_until_drop(sc, br, func() -> bool: return not is_instance_valid(sc) or not (hammer.is_held() and hammer.holder == _wp(sc))))
	r["telegraph_min_s"] = _min_arr(tele)
	r["states"] = counters.duplicate()
	if i == 0 or not bool(r["stolen"]) or float(r.get("flee_gain_m", 0.0)) < 3.0:
		r["trace"] = trace_
	print("  steal_weapon #%d: stolen %s at %.2f s, flee +%.2f m, dropped after hit %s (%s)" % [i + 1, r["stolen"], steal_t, float(r.get("flee_gain_m", 0.0)), r.get("dropped", false), r.get("hit_mode", "")])
	await _unload()
	return r


func _agg_steal_weapon(runs: Array) -> void:
	_check("scrapling_hp", float(runs[0].get("scrapling_hp", 0.0)) if is_equal_approx(float(runs[0].get("scrapling_max_hp", 0.0)), 40.0) else -1.0, 40.0, "eq", "Scrapling hp at spawn = Doll.max_hp 40")
	var stolen := _count_true(runs, "stolen")
	_check("steal_weapon", float(stolen), _majority(runs), "gte", "Scrapling took the hammer out of P1's hand within %.0f s in most runs (t %s)" % [STEAL_WAIT_S, _col(runs, "steal_t")])
	_check("steal_weapon_telegraph", _min_key(runs, "telegraph_min_s"), 0.35, "gte", "grab telegraphed >= 0.35 s")
	var fled := 0
	var dropped := 0
	for r in runs:
		if bool(r.get("stolen", false)) and float(r.get("flee_gain_m", 0.0)) >= 3.0:
			fled += 1
		if bool(r.get("stolen", false)) and bool(r.get("dropped", false)):
			dropped += 1
	_check("steal_weapon_flee", float(fled), ceilf(float(stolen) * 0.5), "gte", "after the theft the thief got >= 3 m further within 2 s (gain m %s)" % [_col(runs, "flee_gain_m")])
	_check("steal_weapon_drop", float(dropped), float(stolen), "eq", "a hit on the thief makes it drop the hammer, every run (%s)" % [_col(runs, "hit_mode")])


func _r_steal_part(i: int) -> Dictionary:
	await _load(false)
	director.begin_manual()
	_give_hammer(p1, "Hand_R")
	var detached: Array = []
	p1.connect("part_detached", func(pn: String, by: Node) -> void: detached.append([pn, by, t]))
	var x0 := p1.centre_of_mass().x
	# со стороны левой кисти (+X куклы): кисть с молотом (−X) вор не задевает по дороге — молот в руке бьёт и того, кто в него влетел
	var sc := director.spawn_enemy("scrapling", Vector3(x0 + 4.5, 1.0, 0.0), Vector3.ZERO, 0.2)
	var br := WaveDirector.brain_of(sc) as ScraplingBrain
	var r := {"candidates_before": br.detach_candidates(p1), "detached": false}
	# массивы и словари мозга — по ссылке: вора могут убить и убрать (corpse_s), а числа нужны после
	var tele: Array = br.telegraph_durations
	var lmd: Array = br.lunge_min_dist
	var counters: Dictionary = br.counters
	var got_t := -1.0
	var trace_: Array = []
	while t < STEAL_WAIT_S + 4.0 and got_t < 0.0:
		await _step()
		if not detached.is_empty():
			got_t = t
		_trace(trace_, sc, br)
		if not is_instance_valid(sc) or not sc.alive:
			break
	r["detached"] = got_t >= 0.0 and is_instance_valid(sc) and is_instance_valid(detached[0][1]) and detached[0][1] == sc
	r["detach_t"] = snappedf(got_t, 0.01)
	r["thief_alive"] = is_instance_valid(sc) and sc.alive
	if bool(r["detached"]) and is_instance_valid(br):
		var pn := String(detached[0][0])
		r["part"] = pn
		r["not_mouse_hand"] = pn != "Hand_R" and p1.parts.has("Hand_R")
		var body := br.loot
		r["loot_part_mass"] = snappedf(body.mass if body != null and is_instance_valid(body) else 0.0, 0.01)
		await _steps(0.1)
		r["held"] = br.holding_loot() and br.loot_kind == "part"
		r["cooldown_ok"] = br.detach_candidates(p1).is_empty()
		r.merge(await _measure_flee(sc, br, trace_))
		r.merge(await _chase_until_drop(sc, br, func() -> bool: return not is_instance_valid(br) or not br.holding_loot()))
		r.merge(await _fetch_part(body, pn))
	r["telegraph_min_s"] = _min_arr(tele)
	r["slips"] = br.slips if is_instance_valid(br) else -1
	r["lunge_min_dist"] = lmd
	r["states"] = counters.duplicate()
	if i == 0 or not bool(r["detached"]) or float(r.get("flee_gain_m", 0.0)) < 3.0:
		r["trace"] = trace_
	print("  steal_part #%d: %s at %.2f s, flee +%.2f m, dropped after hit %s (%s)" % [i + 1, r.get("part", "—"), got_t, float(r.get("flee_gain_m", 0.0)), r.get("dropped", false), r.get("hit_mode", "")])
	await _unload()
	return r


func _agg_steal_part(runs: Array) -> void:
	var n := _count_true(runs, "detached")
	_check("steal_part", float(n), _majority(runs), "gte", "Scrapling unscrewed a part of P1 (Doll.detach_part by it) within %.0f s in most runs (%s at %s s)" % [STEAL_WAIT_S + 4.0, _col(runs, "part"), _col(runs, "detach_t")])
	_check("steal_part_telegraph", _min_key(runs, "telegraph_min_s"), 0.35, "gte", "grab telegraphed >= 0.35 s")
	_check("steal_part_not_mouse_hand", float(_count_true(runs, "not_mouse_hand")), float(n), "eq", "the mouse hand (Hand_R, with the hammer) always stays")
	_check("steal_part_held", float(_count_true(runs, "held")), floorf(float(n) * 0.5) + 1.0, "gte", "the Scrapling holds the detached part 0.1 s later in most runs (%s; иногда кисть, зажатая под жертвой, срывается с пружины хвата)" % [_col(runs, "held")])
	_check("steal_part_cooldown", float(_count_true(runs, "cooldown_ok")), float(n), "eq", "right after a detach nothing more can be unscrewed from P1 (cooldown 12 s, last hand)")
	var fled := 0
	for r in runs:
		if bool(r.get("detached", false)) and float(r.get("flee_gain_m", 0.0)) >= 3.0:
			fled += 1
	_check("steal_part_flee", float(fled), ceilf(float(n) * 0.5), "gte", "after the detach the thief got >= 3 m further within 2 s (gain m %s)" % [_col(runs, "flee_gain_m")])
	_check("steal_part_drop", float(_count_true(runs, "dropped")), float(n), "eq", "a hit on the thief makes it drop the part, every run (%s)" % [_col(runs, "hit_mode")])
	_check("steal_part_returned", float(_count_true(runs, "returned")), ceilf(float(n) * 0.5), "gte", "after the drop P1 flies to its part and gets it back by touch (Doll.reattach_part; s %s, how %s)" % [_col(runs, "return_s"), _col(runs, "return_how")])
	_check("steal_part_muscles_back", float(_count_true(runs, "muscles_back")), float(_count_true(runs, "returned")), "eq", "returned part has its joint, muscle pair and pose again")


## Бегство вора: 2 с после кражи — насколько дальше от P1 он ушёл (максимум), уронил ли добычу по дороге.
func _measure_flee(sc: Doll, br: ScraplingBrain, trace_: Array) -> Dictionary:
	var d0 := sc.centre_of_mass().distance_to(p1.centre_of_mass())
	var dmax := d0
	var dropped := false
	for i in range(120):
		await _step()
		_trace(trace_, sc, br)
		if not is_instance_valid(sc) or not sc.alive:
			break
		dmax = maxf(dmax, sc.centre_of_mass().distance_to(p1.centre_of_mass()))
		dropped = dropped or not is_instance_valid(br) or not br.holding_loot()
	return {"flee_d0_m": snappedf(d0, 0.01), "flee_dmax_m": snappedf(dmax, 0.01), "flee_gain_m": snappedf(dmax - d0, 0.01), "flee_dropped": dropped}


## Вор уронил деталь — P1-бот летит к ней (FETCH_S с) и возвращает касанием (ArmAssist._tick_reattach → Doll.reattach_part).
func _fetch_part(body: RigidBody3D, pn: String) -> Dictionary:
	var t0 := t
	var got := {"v": false}
	var cb := func(name_: String) -> void:
		if name_ == pn:
			got["v"] = true
	p1.part_reattached.connect(cb)
	while t - t0 < FETCH_S and not bool(got["v"]) and is_instance_valid(body) and p1.alive:
		var c := p1.centre_of_mass()
		var to := body.global_position - c
		p1.input_vec = Vector2(to.x, to.y).limit_length(1.0) if to.length() > 0.2 else Vector2.ZERO
		await _step()
	p1.input_vec = Vector2.ZERO
	if p1.part_reattached.is_connected(cb):
		p1.part_reattached.disconnect(cb)
	var arm := _arm(p1)
	var jn := "Wrist_L" if pn == "Hand_L" else ""
	var back: bool = bool(got["v"]) and p1.parts.has(pn) and (jn == "" or (p1.joints.has(jn) and p1.get_pose().has(jn)))
	return {"returned": bool(got["v"]), "return_s": snappedf(t - t0, 0.01), "muscles_back": back,
		"return_how": String(arm.last_reattach.get("how", "")) if arm != null else ""}


func _arm(d: Doll) -> ArmAssist:
	for c in d.get_children():
		if c is ArmAssist:
			return c
	return null


## Возврат детали без врагов (детерминированные кейсы, один прогон):
##   touch   — Hand_L оторвана (detach_part), P1 летит к ней → прирастает касанием, сустав/мышца/поза на месте;
##   control — оторвана рука-мышь Hand_R: ArmAssist перестал управлять (part = null); кисть поднесли к торсу → прикручена, ArmAssist
##             собрал цепь заново и рука снова идёт к цели (set_target_override) — управление восстановилось;
##   grab    — оторванная Hand_L у хвата правой кисти, клавиша захвата (press_grab) → прикручена сразу (how "grab"), до грейса касания;
##   foreign — оторванную кисть Разборщика P1 себе не прикручивает (reattach_own → false).
func _s_reattach() -> void:
	await _load(false)
	director.begin_manual()
	_wp(p1).auto_pickup = false
	var arm := _arm(p1)
	await _steps(0.5)
	# touch
	var hl := p1.detach_part("Hand_L", null)
	var r1 := await _fetch_part(hl, "Hand_L")
	_check("reattach_touch", 1.0 if bool(r1["returned"]) and r1["return_how"] == "touch" else 0.0, 1.0, "eq", "detached Hand_L comes back when P1 touches it (%.2f s, %s)" % [float(r1["return_s"]), r1["return_how"]])
	_check("reattach_muscles", 1.0 if bool(r1["muscles_back"]) else 0.0, 1.0, "eq", "Wrist_L joint + muscle pair + pose restored")
	# control
	await _steps(0.5)
	var hr := p1.detach_part("Hand_R", null)
	await _steps(0.1)
	var lost: bool = arm.part == null
	await _steps(1.2)
	hr.global_position = p1.torso().global_position + Vector3(0.0, -0.1, 0.0)
	hr.linear_velocity = p1.torso().linear_velocity
	await _steps(0.3)
	var rebound: bool = arm.part != null and arm.part_name == "Hand_R" and arm.part == p1.parts.get("Hand_R")
	var tgt := arm.root_point() + Vector3(0.35, 0.45, 0.0)
	arm.set_target_override(tgt)
	var d0 := arm.grip_global().distance_to(tgt)
	var fmax := 0.0
	for i in range(45):
		await _step()
		fmax = maxf(fmax, arm.last_assist_force.length())
	var d1 := arm.grip_global().distance_to(arm.clamp_to_reach(tgt))
	arm.clear_target_override()
	_check("reattach_control_lost", 1.0 if lost else 0.0, 1.0, "eq", "mouse hand detached -> ArmAssist stops (part = null)")
	_check("reattach_control_back", 1.0 if rebound and fmax > 1.0 and d1 < 0.2 else 0.0, 1.0, "eq", "mouse hand back -> ArmAssist rebinds and drives it (grip→target %.2f -> %.2f m, force %.0f N)" % [d0, d1, fmax])
	# grab (клавиша) — до грейса касания
	await _steps(0.5)
	var hl2 := p1.detach_part("Hand_L", null)
	await _steps(0.1)
	hl2.global_position = arm.grip_global() + Vector3(0.1, 0.0, 0.0)
	hl2.linear_velocity = Vector3.ZERO
	arm.press_grab()
	await _steps(0.1)
	_check("reattach_grab", 1.0 if p1.parts.has("Hand_L") and arm.last_grab_action == "reattach" and String(arm.last_reattach.get("how", "")) == "grab" else 0.0, 1.0, "eq", "grab key next to own detached hand -> reattached at once (%s)" % arm.last_grab_action)
	# чужая деталь
	var sc := director.spawn_enemy("scrapling", p1.global_position + Vector3(2.5, 0.0, 0.0), Vector3.ZERO, 30.0)
	await _steps(0.2)
	var foreign := sc.detach_part("Hand_L", null)
	await _steps(1.2)
	foreign.global_position = p1.torso().global_position
	var took: bool = arm.reattach_own(foreign, "grab")
	await _steps(1.2)
	_check("reattach_foreign", 1.0 if not took and not p1.parts.values().has(foreign) else 0.0, 1.0, "eq", "someone else's detached part is not screwed onto P1")
	report["info"]["reattach"] = {"touch": r1, "control": {"lost": lost, "rebound": rebound, "d0": snappedf(d0, 0.01), "d1": snappedf(d1, 0.01), "force": snappedf(fmax, 0.1)}}
	await _unload()


## P1-бот гонится за вором CHASE_S с; условие dropped() — добыча выпала. Если физически не догнал — прямой take_damage от P1
## (проверяется логика «удар → роняет»; в отчёте hit_mode direct).
func _chase_until_drop(sc: Doll, br: ScraplingBrain, dropped: Callable) -> Dictionary:
	var t0 := t
	var hp0 := sc.hp
	var mode_ := "physical"
	while t - t0 < CHASE_S and not dropped.call() and is_instance_valid(sc) and sc.alive:
		_bot_rush(p1, sc)
		await _step()
	p1.input_vec = Vector2.ZERO
	var chase_s := t - t0
	if is_instance_valid(sc) and not dropped.call() and sc.alive:
		mode_ = "direct"
		sc.take_damage(5.0, p1, "Torso", sc.centre_of_mass(), Vector3.UP, "body")
		await _steps(0.1)
	var alive := is_instance_valid(sc) and sc.alive
	return {"dropped": dropped.call() or not alive, "hit_mode": mode_, "chase_s": snappedf(chase_s, 0.01),
		"thief_hp_lost": snappedf(hp0 - (sc.hp if is_instance_valid(sc) else 0.0), 0.1), "drops": br.drops if is_instance_valid(br) else -1}


func _r_clear_wave1(i: int) -> Dictionary:
	await _load(true)
	var hammer := _give_hammer(p1)
	var wave_start := -1.0
	var clear_t := -1.0
	var min_d := {}
	var spawn_y: Array = []
	var acc := {"dmg": 0.0, "to_enemies": 0.0, "enemy_hits": 0}   # лямбды захватывают локальные по значению — счётчики в словаре
	director.hit.connect(func(victim: Doll, _att: Node, dmg: float, _k: String, _pos: Vector3) -> void:
		if victim != null and is_instance_valid(victim) and victim.is_in_group("enemies"):
			acc["to_enemies"] = float(acc["to_enemies"]) + dmg
			acc["enemy_hits"] = int(acc["enemy_hits"]) + 1)
	p1.damaged.connect(func(a: float, att: Node, _p: String, _pos: Vector3, _k: String) -> void:
		if att != null and is_instance_valid(att) and att.is_in_group("enemies"):
			acc["dmg"] = float(acc["dmg"]) + a)
	director.enemy_spawned.connect(func(e: Doll) -> void: spawn_y.append(snappedf(e.centre_of_mass().y, 0.01)))
	var brains: Array = []
	while t < CLEAR_MAX_S + 5.0 and clear_t < 0.0 and p1.alive:
		if director.wave_state in ["spawning", "fight"] and wave_start < 0.0:
			wave_start = t
		for n in get_tree().get_nodes_in_group("enemies"):
			var e := n as Doll
			var b := WaveDirector.brain_of(e)
			if b != null and not brains.has(b):
				brains.append(b)
			if e.alive and b != null and b.is_active():
				min_d[e.name] = minf(float(min_d.get(e.name, INF)), e.centre_of_mass().distance_to(p1.centre_of_mass()))
		if director.wave_state == "pause" or director.wave_index >= 1:
			clear_t = t
			break
		_bot_rush(p1, _nearest_enemy(p1))   # бот бьёт ближайшего; молот отобрали — подберёт, если коснётся, иначе руками
		await _step()
	p1.input_vec = Vector2.ZERO
	var steals := {"part": 0, "weapon": 0}
	var enemy_dealt := 0.0
	for b in brains:
		if not is_instance_valid(b):
			continue
		var sb := b as ScraplingBrain
		if sb != null:
			steals["part"] += int(sb.steals["part"])
			steals["weapon"] += int(sb.steals["weapon"])
		var d := (b as EnemyBrain).doll
		if is_instance_valid(d):
			enemy_dealt += float(d.stats["damage_dealt"])
	var clear_s := clear_t - wave_start if clear_t >= 0.0 and wave_start >= 0.0 else -1.0
	var r := {
		"cleared": clear_s >= 0.0 and clear_s <= CLEAR_MAX_S, "clear_s": snappedf(clear_s, 0.01), "p1_alive": p1.alive, "p1_hp": snappedf(p1.hp, 0.1),
		"p1_damage_dealt": snappedf(float(p1.stats["damage_dealt"]), 0.1), "p1_damage_from_enemies": snappedf(float(acc["dmg"]), 0.1),
		"damage_to_enemies": snappedf(float(acc["to_enemies"]), 0.1), "enemy_hits_taken": acc["enemy_hits"], "enemies_damage_dealt": snappedf(enemy_dealt, 0.1),
		"kills": director.kills.duplicate(), "steals": steals, "approach_max_m": snappedf(_max_dict(min_d), 0.01), "spawn_com_y": spawn_y,
		"p1_parts_left": p1.parts.size(), "hammer_with_p1": hammer.is_held() and hammer.holder == _wp(p1),
	}
	if i == 0:
		r["events"] = director.events.slice(0, 30)
	print("  clear_wave1 #%d: cleared %s in %.1f s, P1 -%.1f HP from enemies, P1 dealt %.1f, steals %s, P1 parts %d" % [i + 1, r["cleared"], clear_s, float(r["p1_damage_from_enemies"]), float(r["p1_damage_dealt"]), steals, p1.parts.size()])
	await _unload()
	return r


func _agg_clear_wave1(runs: Array) -> void:
	var sy: Array = runs[0].get("spawn_com_y", [])
	_check("wave1_spawned_from_chute", float(sy.size()), 2.0, "eq", "wave 1 = 2 enemies dropped from the chute (spawn CoM y %s)" % [sy])
	_check("wave1_spawn_high", _min_arr(sy), 6.0, "gte", "enemies appear high (chute mouth y=11), not on the floor")
	_check("wave1_enemies_approach", _median_key(runs, "approach_max_m"), 1.5, "lte", "every enemy came within 1.5 m of P1 (median of the worst enemy %s)" % [_col(runs, "approach_max_m")])
	_check("wave1_cleared", float(_count_true(runs, "cleared")), _majority(runs), "gte", "P1-bot with a hammer cleared wave 1 within %.0f s in most runs (s %s)" % [CLEAR_MAX_S, _col(runs, "clear_s")])
	_check("wave1_p1_hurt", _median_key(runs, "p1_damage_from_enemies"), 5.0, "gte", "wave 1 is not toothless: enemies hurt P1 (HP per run %s)" % [_col(runs, "p1_damage_from_enemies")])


# --- агрегаты ---

static func _col(runs: Array, key: String) -> Array:
	var out: Array = []
	for r in runs:
		out.append(r.get(key, null))
	return out


static func _median_key(runs: Array, key: String) -> float:
	var a: Array = []
	for r in runs:
		if r.has(key):
			a.append(float(r[key]))
	if a.is_empty():
		return 0.0
	a.sort()
	@warning_ignore("integer_division")
	return float(a[a.size() / 2]) if a.size() % 2 == 1 else (float(a[a.size() / 2 - 1]) + float(a[a.size() / 2])) * 0.5


static func _min_key(runs: Array, key: String) -> float:
	var m := INF
	for r in runs:
		if r.has(key) and float(r[key]) > 0.0:
			m = minf(m, float(r[key]))
	return m if m < INF else 0.0


static func _count_true(runs: Array, key: String) -> int:
	var n := 0
	for r in runs:
		if bool(r.get(key, false)):
			n += 1
	return n


## Большинство прогонов (2 из 3, 3 из 5).
static func _majority(runs: Array) -> float:
	return floorf(float(runs.size()) * 0.5) + 1.0


func _s_pit() -> void:
	await _load(false)
	director.begin_manual()
	var causes: Array = []
	director.enemy_down.connect(func(_e: Doll, c: String) -> void: causes.append(c))
	var sc := director.spawn_enemy("scrapling", Vector3(-8.0, 0.4, 0.0), Vector3(0.0, -1.0, 0.0), 30.0)
	var ko_t := -1.0
	while t < 8.0 and ko_t < 0.0:
		await _step()
		if not sc.alive:
			ko_t = t
	report["info"]["pit"] = {"ko_t": snappedf(ko_t, 0.01), "causes": causes, "kills": director.kills.duplicate(), "left": director.enemies_left()}
	_check("pit_ko", 1.0 if ko_t >= 0.0 else 0.0, 1.0, "eq", "enemy dropped into the pit is KO (%.2f s)" % ko_t)
	_check("pit_counted", float(director.kills["pit"]), 1.0, "eq", "WaveDirector counts it as a pit kill (%s)" % [causes])
	_check("pit_left", float(director.enemies_left()), 0.0, "eq", "enemies_left 0 after the pit")
	await _unload()


func _s_waves() -> void:
	await _load(false)
	director.intro_s = 0.5
	director.wave_pause_s = 1.0
	var lines: Array = []
	var comp: Array = []
	var flags := {"hp_ok": true}
	var overs: Array = []
	director.tower_line.connect(func(s: String) -> void: lines.append(s))
	director.run_over.connect(func(v: bool, _l: String) -> void: overs.append(v))
	director.wave_started.connect(func(i: int, _n: int, _l: String) -> void: comp.append({"wave": i + 1, "kinds": {}}))
	director.enemy_spawned.connect(func(e: Doll) -> void:
		var k := String(e.get_meta("enemy_kind", ""))
		if not comp.is_empty():
			var d: Dictionary = comp[comp.size() - 1]["kinds"]
			d[k] = int(d.get(k, 0)) + 1
		var want_hp := 80.0 if k == "sweeper" else 40.0
		if not is_equal_approx(e.hp, want_hp) or not is_equal_approx(e.max_hp, want_hp) or e.get("team") != "tower":
			flags["hp_ok"] = false)
	director.start_run()
	# волны: как только все враги волны выпали — KO каждому
	while t < 60.0 and overs.is_empty():
		await _step()
		p1.input_vec = Vector2.ZERO
		if director.wave_state == "fight":
			for e in director.alive_enemies():
				(e as Doll).knock_out(p1, {"kind": "body"})
	await _steps(2.5)
	var barrel := false
	for n in get_tree().get_nodes_in_group("pve_spawned"):
		if n is RigidBody3D and not n is Weapon and not n is Doll:
			barrel = true
	var comp_ok := comp.size() == 3 and _kinds(comp[0]) == "scrapling:2" and _kinds(comp[1]) == "scrapling:2,sweeper:1" and _kinds(comp[2]) == "scrapling:3,sweeper:2"
	_check("waves_composition", 1.0 if comp_ok else 0.0, 1.0, "eq", "waves 2 / 1+2 / 2+3: %s" % [comp])
	_check("waves_enemy_hp_team", 1.0 if bool(flags["hp_ok"]) else 0.0, 1.0, "eq", "Scrapling 40 HP, Sweeper 80 HP, team tower")
	_check("waves_victory", 1.0 if overs == [true] else 0.0, 1.0, "eq", "run_over(victory) after wave 3 (%s)" % [overs])
	_check("waves_tower_lines", float(lines.size()), 5.0, "gte", "Tower lines (intro, 3 waves, clears, victory): %s" % [lines])
	_check("waves_caps", 1.0 if _all_caps(lines) else 0.0, 1.0, "eq", "Tower speaks in CAPS")
	_check("waves_late_barrel", 1.0 if barrel else 0.0, 1.0, "eq", "late barrel dropped after FLOOR CLEAN (правило гашения)")
	# restart
	var old_id := p1.get_instance_id()
	director.restart()
	await _steps(0.3)
	var np := pg.get_node("P1") as Doll
	var enemies_left := 0
	for n in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			enemies_left += 1
	_check("restart_clean", float(enemies_left), 0.0, "eq", "restart removes enemies")
	_check("restart_player", 1.0 if np.get_instance_id() != old_id and np.alive and is_equal_approx(np.hp, Tuning.MAX_HP) and np.get("team") == "players" else 0.0, 1.0, "eq", "restart: P1 new, alive, full HP, team players")
	_check("restart_state", 1.0 if director.wave_state == "intro" and director.result == "" else 0.0, 1.0, "eq", "restart: intro again (state %s)" % director.wave_state)
	# поражение
	p1 = np
	p1.external_input = true
	await _steps(1.0)
	p1.knock_out()
	await _steps(0.3)
	_check("defeat", 1.0 if director.result == "defeat" and overs.size() == 2 and overs[1] == false else 0.0, 1.0, "eq", "all players KO -> defeat (%s, %s)" % [director.result, overs])
	report["info"]["waves"] = {"composition": comp, "lines": lines, "overs": overs, "events": director.events.slice(0, 40)}
	await _unload()


## Кооп (F2): P2 остаётся, оба в группе players с командой players, у HUD две панели, волна идёт, враги целятся в ближайшего.
func _s_coop() -> void:
	PvePlayground.coop = true
	await _load(true)
	var p2 := pg.get_node_or_null("P2") as Doll
	if p2 != null:
		p2.external_input = true
	var hud := pg.get_node("HUD") as PveHud
	var targets := {}
	while t < 9.0:
		await _step()
		for n in get_tree().get_nodes_in_group("enemies"):
			var b := WaveDirector.brain_of(n)
			if b != null and b.target != null:
				targets[String(b.target.name)] = true
	var both_team: bool = p2 != null and p1.get("team") == "players" and p2.get("team") == "players"
	report["info"]["coop"] = {"players": director.players().size(), "hud_panels": hud.panels.size(), "enemy_targets": targets.keys(), "wave_state": director.wave_state}
	_check("coop_players", float(director.players().size()), 2.0, "eq", "F2 coop: P1 and P2 in the run, team players both: %s" % both_team)
	_check("coop_hud", float(hud.panels.size()), 2.0, "eq", "HUD has two player panels")
	_check("coop_wave", 1.0 if director.wave_index == 0 and director.wave_state in ["spawning", "fight"] else 0.0, 1.0, "eq", "wave 1 runs in coop (%s)" % director.wave_state)
	PvePlayground.coop = false
	await _unload()


## Весь забег (mode=run, trials=N): P1-бот с молотом против трёх волн — сколько волн проходит, за сколько, с каким HP; кражи,
## откручивания, падения в пропасть. Не входит в full (долго) — это ответ на «не слишком ли сложно/легко».
func _r_run(i: int) -> Dictionary:
	await _load(true)
	_give_hammer(p1)
	var waves: Array = []
	var cur := -1
	var t_wave := 0.0
	var hp_at := 0.0
	var detached: Array = []
	p1.connect("part_detached", func(pn: String, _by: Node) -> void: detached.append(pn))
	while t < RUN_MAX_S and director.result == "":
		await _step()
		if director.wave_index != cur and director.wave_state in ["spawning", "fight"]:
			cur = director.wave_index
			t_wave = t
			hp_at = p1.hp
		if director.wave_state == "pause" and (waves.size() <= cur):
			waves.append({"wave": cur + 1, "s": snappedf(t - t_wave, 0.1), "hp_start": snappedf(hp_at, 0.1), "hp_end": snappedf(p1.hp, 0.1)})
		if p1.alive:
			_bot_rush(p1, _nearest_enemy(p1))
	if director.result == "victory" and waves.size() < 3:
		waves.append({"wave": 3, "s": snappedf(t - t_wave, 0.1), "hp_start": snappedf(hp_at, 0.1), "hp_end": snappedf(p1.hp, 0.1)})
	var steals := {"part": 0, "weapon": 0}
	for e in director.events:
		if String(e.get("what", "")) == "part_detached":
			steals["part"] += 1
	var r := {"result": director.result if director.result != "" else "timeout", "run_s": snappedf(t, 0.1), "waves_cleared": waves.size(),
		"waves": waves, "reached_wave": cur + 1, "p1_hp": snappedf(p1.hp, 0.1), "p1_damage_taken": snappedf(float(p1.stats["damage_taken"]), 0.1),
		"p1_damage_dealt": snappedf(float(p1.stats["damage_dealt"]), 0.1), "kills": director.kills.duplicate(), "parts_lost": detached,
		"p1_ko_kind": String(p1.last_ko_record.get("kind", "")) if not p1.alive else ""}
	print("  run #%d: %s at %.0f s, waves cleared %d (reached %d), P1 hp %.0f, lost parts %s, kills %s, KO kind %s" % [i + 1, r["result"], t, waves.size(), cur + 1, p1.hp, detached, director.kills, r["p1_ko_kind"]])
	await _unload()
	return r


func _agg_run(runs: Array) -> void:
	report["info"]["run_summary"] = {"results": _col(runs, "result"), "waves_cleared": _col(runs, "waves_cleared"), "run_s": _col(runs, "run_s")}
	_check("run_reaches_wave2", float(_count_ge(runs, "reached_wave", 2)), _majority(runs), "gte", "P1-bot reaches wave 2 in most runs (reached %s)" % [_col(runs, "reached_wave")])


static func _count_ge(runs: Array, key: String, v: float) -> int:
	var n := 0
	for r in runs:
		if float(r.get(key, 0.0)) >= v:
			n += 1
	return n


static func _kinds(c: Dictionary) -> String:
	var d: Dictionary = c["kinds"]
	var keys := d.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append("%s:%d" % [k, d[k]])
	return ",".join(parts)


static func _all_caps(lines: Array) -> bool:
	for l in lines:
		if String(l) != String(l).to_upper():
			return false
	return not lines.is_empty()


# ------------------------------------------------------------------ fps (окно)

func _perf() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await _load(false, true)
	director.begin_manual()
	_give_hammer(p1)
	var x := p1.centre_of_mass().x
	for i in range(5):
		var kind := "sweeper" if i % 2 == 0 and i < 4 else "scrapling"
		director.spawn_enemy(kind, Vector3(x - 6.0 + i * 3.0, 3.0 + (i % 2), 0.0), Vector3.ZERO, 0.5)
	var frames := 0
	var real0 := 0
	var sec_frames := 0
	var sec_t0 := 0
	var min_sec := INF
	var t_real0 := Time.get_ticks_msec()
	var tiers := {}
	var spikes: Array = []
	var last_fx: Array = [""]
	director.hit_fx.connect(func(ctx: Dictionary) -> void:
		var tr := String(ctx.get("tier", ""))
		tiers[tr] = int(tiers.get(tr, 0)) + 1
		last_fx[0] = "%s@%.2f" % [tr, float(Time.get_ticks_msec() - t_real0) / 1000.0])
	var prev := Time.get_ticks_msec()
	while true:
		await get_tree().process_frame
		_bot_rush(p1, _nearest_enemy(p1))
		var now := Time.get_ticks_msec()
		if now - prev > 80 and spikes.size() < 20:
			spikes.append({"t": snappedf(float(now - t_real0) / 1000.0, 0.01), "ms": now - prev, "last_fx": last_fx[0], "time_scale": snappedf(Engine.time_scale, 0.01)})
		prev = now
		var el := float(now - t_real0) / 1000.0
		if el < PERF_WARM_S:
			continue
		if real0 == 0:
			real0 = now
			sec_t0 = now
		frames += 1
		sec_frames += 1
		if now - sec_t0 >= 1000:
			min_sec = minf(min_sec, float(sec_frames) * 1000.0 / float(now - sec_t0))
			sec_frames = 0
			sec_t0 = now
		if float(now - real0) / 1000.0 >= PERF_S:
			break
	var avg := float(frames) / (float(Time.get_ticks_msec() - real0) / 1000.0)
	var alive := 0
	for n in get_tree().get_nodes_in_group("enemies"):
		if (n as Doll).alive:
			alive += 1
	report["info"]["perf"] = {"avg_fps": snappedf(avg, 0.1), "min_sec_fps": snappedf(min_sec, 0.1), "enemies_alive_end": alive, "hit_fx_tiers": tiers, "spikes": spikes,
		"load_avg": OS.execute("sysctl", ["-n", "vm.loadavg"], []) if false else "",
		"resolution": get_viewport().get_visible_rect().size, "draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)}
	print("PERF pve avg_fps=%.1f min_sec_fps=%.1f" % [avg, min_sec])
	_check("perf_fps", avg, min_fps, "gte", "avg fps with 5 enemies + P1 (window %s)" % [get_viewport().get_visible_rect().size])
	await _unload()


# ------------------------------------------------------------------ кадры (окно)

func _shots() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("../docs/plan-demo/img")
	# 1) волна: забег сразу с волны 3 — враги сыплются из желоба (строка Башни, табличка ВОЛНА 3/3)
	await _load(true, true)
	_give_hammer(p1)
	director.intro_s = 0.3
	while director.wave_state == "intro":
		await _step()
	director.start_wave(2)
	while director.wave_t < 3.1:
		await _step()
	await _shot(dir.path_join("pve-v1-wave.png"))
	await _unload()
	# 2) Уборщик: волна 2, P1 стоит; кадр — в телеграфе SWEEP! (метла над головой), когда Уборщик рядом с P1
	await _load(true, true)
	_wp(p1).auto_pickup = false
	director.intro_s = 0.3
	while director.wave_state == "intro":
		await _step()
	director.start_wave(1)
	var sb: SweeperBrain = null
	while t < 40.0:
		await _step()
		if sb == null:
			for n in get_tree().get_nodes_in_group("enemies"):
				if WaveDirector.brain_of(n) is SweeperBrain:
					sb = WaveDirector.brain_of(n) as SweeperBrain
		if sb != null and is_instance_valid(sb) and sb.state == "telegraph" and sb.state_t >= 0.34 \
				and sb.doll.centre_of_mass().distance_to(p1.centre_of_mass()) < 4.0:
			break
	await _shot(dir.path_join("pve-v1-sweep.png"))
	await _unload()
	# 3) Разборщик: волна 1, P1 стоит с молотом; кадр — откручивает кисть (UNSCREW!, щелчки трещотки)
	await _load(true, true)
	_give_hammer(p1, "Hand_R")
	director.intro_s = 0.3
	var got := false
	while t < 40.0 and not got:
		await _step()
		for n in get_tree().get_nodes_in_group("enemies"):
			var cb := WaveDirector.brain_of(n) as ScraplingBrain
			if cb != null and cb.state == "unscrew" and cb.state_t >= 0.6:
				got = true
	await _shot(dir.path_join("pve-v1-steal.png"))
	await _unload()
	# 4) зачистка: P1-бот с молотом зачищает волну 1 по-настоящему; кадр через 0.15 с после CLEAR (табличка «ЧИСТО», строка Башни)
	await _load(true, true)
	_give_hammer(p1)
	var clear_t := -1.0
	while t < 70.0:
		await _step()
		if director.wave_state == "pause" or director.wave_index >= 1:
			if clear_t < 0.0:
				clear_t = t
			p1.input_vec = Vector2.ZERO
			if t - clear_t >= 0.15:
				break   # последний KO ещё разлетается (замедление KO), CLEAR! и строка Башни уже есть
		else:
			_bot_rush(p1, _nearest_enemy(p1))
	report["info"]["shot_clear_t"] = snappedf(clear_t, 0.01)
	await _shot(dir.path_join("pve-v1-clear.png"))
	await _unload()


func _shot(path: String) -> void:
	var calls := {}
	for n in get_tree().get_nodes_in_group("enemies"):
		var lk := (n as Node).get_node_or_null("EnemyLook") as EnemyLook
		var br := WaveDirector.brain_of(n)
		if lk != null and (n as Doll).alive:
			calls[String(n.name)] = "%s %s(%.2f) callout '%s' active %s" % [br.state if br else "", "", br.state_t if br else 0.0, lk.callout, lk.callout_active()]
	report["info"]["shot_" + path.get_file().get_basename()] = calls
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("shot ", path, " err=", err)
	report["info"][path.get_file()] = err == OK
	_check("shot_" + path.get_file().get_basename(), 1.0 if err == OK else 0.0, 1.0, "eq", "saved " + path)


# ------------------------------------------------------------------ отчёт

static func _min_arr(a: Array) -> float:
	var m := INF
	for v in a:
		m = minf(m, float(v))
	return m if m < INF else 0.0


static func _max_dict(d: Dictionary) -> float:
	var m := 0.0
	if d.is_empty():
		return INF
	for v in d.values():
		m = maxf(m, float(v))
	return m


static func _snap_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		out[String(k)] = snappedf(float(d[k]), 0.01)
	return out


func _check(id: String, value: float, limit: float, cmp: String, detail: String) -> void:
	var ok := false
	match cmp:
		"lt": ok = value < limit
		"gt": ok = value > limit
		"lte": ok = value <= limit
		"gte": ok = value >= limit
		"eq": ok = is_equal_approx(value, limit)
	report["checks"].append({"id": id, "value": snappedf(value, 0.001), "limit": limit, "cmp": cmp, "ok": ok, "detail": detail})
	if not ok:
		report["ok"] = false
		print("  FAIL %s: %s %s %s (%s)" % [id, snappedf(value, 0.001), cmp, limit, detail])
	else:
		print("  ok   %s: %s %s %s  %s" % [id, snappedf(value, 0.001), cmp, limit, detail])


func _finish() -> void:
	report["info"]["godot"] = Engine.get_version_info()["string"]
	var js := JSON.stringify(report, "  ")
	print("=== PVE PROBE ===")
	print(js)
	var name_ := "res://tests/pve_probe_report.json" if mode in ["full"] else "res://tests/pve_probe_%s_report.json" % mode
	var f := FileAccess.open(name_, FileAccess.WRITE)
	if f:
		f.store_string(js)
		f.close()
	print("=== %s ===" % ("OK" if report["ok"] else "FAIL"))
	get_tree().quit(0 if report["ok"] else 1)
