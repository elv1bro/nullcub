## Проба эффектов удара HitFxDirector (HIT_FX.md §5.4, без крит-кинематографа): headless, --fixed-fps 60, площадка Void
## (или body — ModularDoll). Уровни — синтетическим ctx через HitFxDirector.play / play_slam на настоящих куклах; плюс удар через
## Match.on_hit (ядро: сигнал hit_fx; без ядра — старый Match.hit) и настоящий KO. Директор берётся ребёнком Match
## (Match._ensure_fx_directors), а если ядра ещё нет — пробa ставит scenes/fx/hit_fx_director.tscn сама.
## Проверки: light без hit-stop/punch; heavy — вспышка 1, волна, послеобразы 3, ленты, линии, hit-stop 50 ± 17 мс (без ядра — директор,
## с ядром — Match._emit_hit_fx), камера fx_idle к 600 мс; ko — 2 кадра инверсии, волна, ленты; slam — пыль, тряска, hp 100, без
## вспышки; crit без ката — надпись CRUSHING BLOW!, время вернулось к 1, камера игровая; flash_intensity 0 → 0 вспышек; 10 heavy
## за 1 с → ≤ 3 вспышек; лимиты следов; кукла без мешей → послеобразы из коллизий; material_overlay/override жертвы не менялись;
## restart посреди heavy → всё снято; через 3 с после эффектов fx_node_count() = исходному; в конце time_scale 1, камера игровая.
## v2 (§11.3–11.4): heavy — искра SparkCone, волна до ≥ 1.7 м толщиной ≥ 0.25 цветом атакующего, звезда ImpactFlash у точки удара
## к +100 мс сжата/погашена, упреждение камеры по скорости жертвы; ko — кадры-силуэты по маске кукол, бит маски после снят.
## v3 (§12.2–12.3): тормоз атакующего на heavy (CritLaunch.brake_attacker) — сам по себе (heavy_brake_unit) и в одном сценарии с
## тормозом и без (stand 1.2 м, рывок 1.0–1.3 м; удар как DollCombat, с отдачей): клэмп ≤ HEAVY_ATTACKER_BRAKE_SPEED, отлёт не хуже;
## reduced (flash 0.4) — кольцо heavy меньше по размеру.
## Запуск: godot --headless --path . --fixed-fps 60 res://tests/hitfx_probe.tscn -- "scene=void,victim=p2"
##   scene=void|body, victim=p1|p2, out=res://tests/hitfx_probe_report.json. Exit 0/1.
extends Node3D

const SCENES := {"void": "res://scenes/playground_void.tscn", "body": "res://scenes/playground_body.tscn",
	"ruins": "res://scenes/playground.tscn", "workshop": "res://scenes/playground_workshop.tscn"}
const DIRECTOR_SCENE := "res://scenes/fx/hit_fx_director.tscn"
const FRAME_MS := 1000.0 / 60.0
const UNIT_BRAKE_S := 0.18   # окно тормоза в проверке механизма (HIT_FX §12.2: по умолчанию окна нет)

var scene_id := "void"
var victim_id := "p2"
var out_path := "res://tests/hitfx_probe_report.json"
var pg: Node3D
var match_node: Match
var director: HitFxDirector
var cam: Camera3D
var report := {"ok": true, "checks": [], "info": {}}
var announces: Array = []


func _ready() -> void:
	HitJuice.impact_style = "cartoon"   # проба проверяет стиль «мульт» (звезда, кольца, послеобразы); «серьёзный» — juice_probe (§13)
	HitJuice.outline_on = false   # обводка бойцов (B) — свои узлы на мешах кукол; проба считает узлы и оверлеи частей
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			match p[0]:
				"scene": scene_id = p[1]
				"victim": victim_id = p[1]
				"out": out_path = p[1]
	pg = (load(SCENES.get(scene_id, SCENES["void"])) as PackedScene).instantiate()
	match_node = pg.get_node("Match") as Match
	match_node.countdown_s = 0.0
	add_child(pg)
	_run.call_deferred()


func check(id: String, ok: bool, value: Variant = null, limit: Variant = null) -> void:
	report["checks"].append({"id": id, "ok": ok, "value": value, "limit": limit})
	if not ok:
		report["ok"] = false
	print("%s %s value=%s limit=%s" % ["OK  " if ok else "FAIL", id, str(value), str(limit)])


var _phys_cb: Callable
signal _phys_done


## Вызвать cb в _physics_process (как DollCombat зовёт Match.on_hit) и дождаться.
func physics_call(cb: Callable) -> void:
	_phys_cb = cb
	await _phys_done


func _physics_process(_delta: float) -> void:
	if _phys_cb.is_valid():
		var cb := _phys_cb
		_phys_cb = Callable()
		cb.call()
		_phys_done.emit()


func frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func wait_ms(ms: float) -> void:
	var t0 := director.clock_ms()
	while director.clock_ms() - t0 < ms - 0.5:
		await get_tree().process_frame


## Ждать, пока от последнего эффекта (played: удары и удары о стену — куклы после отлёта ещё бьются о стены) пройдёт ms.
func wait_quiet(ms: float = 3000.0, max_ms: float = 10000.0) -> void:
	var t0 := director.clock_ms()
	while director.clock_ms() - t0 < max_ms:
		var last := 0.0
		if not director.played.is_empty():
			last = float((director.played[director.played.size() - 1] as Dictionary).get("ms", 0.0))
		if director.clock_ms() - last >= ms:
			return
		await get_tree().process_frame


func victim() -> Doll:
	return pg.get_node(victim_id.to_upper()) as Doll


func attacker() -> Doll:
	return pg.get_node("P1" if victim_id == "p2" else "P2") as Doll


func ctx_for(tier: String, damage: float, v: Doll = null, a: Doll = null) -> Dictionary:
	if v == null:
		v = victim()
	if a == null:
		a = attacker()
	var head := v.head()
	var pos := head.global_position if tier == "ko" else v.torso().global_position
	var dir := Vector3(1.0 if a.global_position.x < v.global_position.x else -1.0, 0.15, 0.0).normalized()
	return {"victim": v, "attacker": a, "damage": damage, "kind": "head" if tier == "ko" else "body",
		"part": "Head" if tier == "ko" else "Torso", "part_base": "Head" if tier == "ko" else "Torso", "striker": "Hand_R",
		"position": pos, "normal": -dir, "dir": dir, "speed": 7.0, "weapon_id": "", "combo": 1, "double_blow": false,
		"dash": false, "score": damage, "tier": tier, "is_ko": tier == "ko" or tier == "ko_crit", "hp_after": v.hp,
		"fight_time": match_node.fight_time, "sd_mult": 1.0, "colour": Tuning.PLAYER_COLORS[v.player_index]}


func launch(v: Doll, speed: float, dir: Vector3) -> void:
	for b in v.parts.values():
		(b as RigidBody3D).linear_velocity = dir.normalized() * speed


func overlays(v: Doll) -> Array:
	var out: Array = []
	for mi in v.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		# следы ударов (HitMarks, HIT_FX.md §13) — задуманы постоянными, это не «забытый» оверлей эффекта
		var ov: Material = m.material_overlay
		if ov is ShaderMaterial and (ov as ShaderMaterial).shader == HitMarks.SHADER:
			ov = null
		out.append([m.get_path(), ov, m.material_override])
	return out


## Дети Match без временных узлов ImpactFx (prewarm живёт 3 с): директоры эффектов/звука.
func director_children() -> int:
	var n := 0
	for c in match_node.get_children():
		if not String(c.name).begins_with("ImpactFx") and not c.is_queued_for_deletion():
			n += 1
	return n


## Мешей куклы с битом маски DollMask (вне показа — 0).
func mask_bits(d: Doll) -> int:
	var n := 0
	for mi in d.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).layers & DollMask.MASK_BIT != 0:
			n += 1
	return n


func is_idle_cam() -> bool:
	return not cam.has_method("fx_idle") or bool(cam.call("fx_idle"))


func live_count(cls: String) -> int:
	var n := 0
	for c in director.fx_root.get_children():
		if c.is_queued_for_deletion():
			continue
		if (cls == "trail" and c is FlightTrail) or (cls == "ghost" and c is AfterimageTrail) or (cls == "wave" and c is Shockwave):
			n += 1
	return n


static func com_velocity(d: Doll) -> Vector3:
	return FlightTrail.com_velocity(d)


func place_x(d: Doll, x: float) -> void:
	var off := x - d.centre_of_mass().x
	for b in d.parts.values():
		(b as RigidBody3D).global_position.x += off
		(b as RigidBody3D).linear_velocity = Vector3.ZERO
		(b as RigidBody3D).angular_velocity = Vector3.ZERO


## Тормоз heavy (HIT_FX §12.2): mode stand — как лист hitfx_snapshot (атакующий стоит в 1.2 м, отброс 4.2 м/с, 14 HP);
## dash — атакующий в рывке 6 м/с в упор (1.1 м), 12 HP (score 13.8 — heavy). Удар как DollCombat: take_damage, отброс, on_hit.
## Возвращает tier, макс. скорость ЦМ атакующего вдоль отлёта за окно тормоза и расстояние между ЦМ на +400 мс реального времени.
func _brake_run(mode: String, brake: bool, gap: float) -> Dictionary:
	CritLaunch.heavy_brake_enabled = brake
	match_node.restart()
	await frames(2)
	var a := pg.get_node("P1" if victim_id == "p2" else "P2") as Doll
	var vv := pg.get_node(victim_id.to_upper()) as Doll
	a.external_input = true
	vv.external_input = true
	await frames(90)
	var sx := 1.0 if a.player_index < vv.player_index else -1.0   # атакующий слева от жертвы для P1 → P2
	place_x(a, -0.6 * sx - gap * 0.5 * sx)
	place_x(vv, -0.6 * sx + gap * 0.5 * sx)
	await frames(12)
	var hdir := Vector3(sx, 0.0, 0.0)
	var dmg := 14.0 if mode == "stand" else 12.0
	if mode == "dash":
		for b in a.parts.values():
			(b as RigidBody3D).linear_velocity = hdir * 6.0
		a.dash_until = a._time + Tuning.DASH_DURATION_S
		a.input_vec = Vector2(sx, 0.0)
	var np := director.played.size()
	await physics_call(func() -> void:
		var pos: Vector3 = vv.torso().global_position
		vv.hit_meta = {"speed": 9.0, "weapon_id": "", "striker": a.torso(), "combo_mult": 1.0, "double_blow": false,
			"knockback_mult": match_node.knockback_mult(), "stun_s": 0.0, "dir": hdir, "striker_name": "Hand_R"}
		vv.take_damage(dmg, a, "Torso", pos, -hdir, "body")
		var j := 4.2 * vv.total_mass if mode == "stand" else maxf(Damage.knockback_impulse(dmg, match_node.knockback_mult()), Tuning.KNOCKBACK_MIN)
		if mode == "stand":
			vv.apply_knockback(Damage.knockback_dir(hdir) * j, vv.torso(), 0.3, hdir)
		else:
			vv.apply_knockback(Damage.knockback_dir(hdir) * Damage.knockback_impulse(dmg, match_node.knockback_mult()), vv.torso(), 0.0, hdir, Tuning.KNOCKBACK_MIN)
		# отдача атакующего — как DollCombat._deliver (в игре она есть у каждого засчитанного удара куклой)
		a.apply_recoil(hdir, Tuning.HIT_ATTACKER_RECOIL * j / maxf(vv.total_mass, 1.0), Tuning.HIT_ATTACKER_THRUST_LOCK_S)
		match_node.on_hit(vv, a, dmg, "body", pos, 1, false, "", 9.0))
	var tier := ""
	for i in range(np, director.played.size()):
		var tr := String((director.played[i] as Dictionary).get("tier", ""))
		if tier == "":
			tier = tr
	var kb := Damage.knockback_dir(hdir)
	var t0 := director.clock_ms()
	var pt0 := a._time
	var along_max := com_velocity(a).dot(kb)
	var gap_400 := -1.0
	while director.clock_ms() - t0 < 400.0:
		await get_tree().physics_frame
		if a._time - pt0 <= Tuning.HEAVY_ATTACKER_BRAKE_S:
			along_max = maxf(along_max, com_velocity(a).dot(kb))
		if OS.has_environment("HITFX_DEBUG"):
			print("brake %s %s t=%.0f pt=%.3f va=%.2f vv=%.2f gap=%.2f ts=%.2f" % [mode, brake, director.clock_ms() - t0, a._time - pt0,
				com_velocity(a).dot(kb), com_velocity(vv).dot(kb), (vv.centre_of_mass() - a.centre_of_mass()).length(), Engine.time_scale])
	gap_400 = (vv.centre_of_mass() - a.centre_of_mass()).length()
	a.input_vec = Vector2.ZERO
	a.dash_until = 0.0
	CritLaunch.heavy_brake_enabled = true
	await wait_quiet(1500.0, 4000.0)
	return {"tier": tier, "along_max": along_max, "gap_400": gap_400, "gap_0": gap}


func _run() -> void:
	await frames(3)
	director = match_node.get_node_or_null("HitFxDirector") as HitFxDirector
	report["info"]["director_from_core"] = director != null
	if director == null:
		director = (load(DIRECTOR_SCENE) as PackedScene).instantiate() as HitFxDirector
		match_node.add_child(director)
	report["info"]["core_hit_fx"] = match_node.has_signal("hit_fx")
	report["info"]["core_env_slam"] = match_node.has_signal("env_slam")
	report["info"]["cinematic"] = director.get_node_or_null("CritCinematic") != null
	match_node.announce.connect(func(text: String, _c: Color, kind: String) -> void: announces.append([text, kind]))
	cam = match_node.call("game_camera") if match_node.has_method("game_camera") else pg.get_node("Camera") as Camera3D
	for d in [pg.get_node("P1"), pg.get_node("P2")]:
		(d as Doll).external_input = true
	await frames(60)
	var base := director.fx_node_count()
	var match_children := director_children()
	report["info"]["baseline_nodes"] = base
	report["info"]["victim_scene"] = victim().scene_file_path
	var ov0 := overlays(victim())
	var sfx := director.screen_fx

	# --- light ---
	var st: Dictionary = director.stats.duplicate()
	director.play(ctx_for("light", 5.0))
	await frames(2)
	check("light_no_nodes", director.fx_node_count() == base, director.fx_node_count(), base)
	check("light_no_punch", int(director.stats["punches"]) == int(st["punches"]) and is_idle_cam(), director.stats["punches"], st["punches"])
	check("light_no_hitstop", is_equal_approx(Engine.time_scale, 1.0), Engine.time_scale, 1.0)
	check("light_no_flash", int(director.stats["flashes"]) == int(st["flashes"]), director.stats["flashes"], st["flashes"])

	# --- heavy ---
	st = director.stats.duplicate()
	var ff0 := sfx.flash_frames_shown
	var v := victim()
	var dir := Vector3(1.0 if attacker().global_position.x < v.global_position.x else -1.0, 0.3, 0.0)
	launch(v, 4.2, dir)
	var hctx := ctx_for("heavy", 12.0)
	var star_fx := ImpactFx.spawn_impact(match_node, hctx["position"], hctx["normal"], 4.0 + 12.0 * 0.4, "body")
	director.play(hctx)
	var t0 := director.clock_ms()
	var stop_frames := 0
	var max_snap := 0
	var max_trails := 0
	var wave_seen := false
	var lines_seen := false
	var punch_seen := false
	var idle_at_600 := false
	var wave_r_max := 0.0
	var wave_thick := 0.0
	var wave_col_ok := false
	var spark_seen := false
	var star_at_100 := -1.0      # наибольшая «видимость» звезды у точки удара на +100 мс (1 − transparency) × scale
	var lead_max := 0.0
	var lead_dot := 0.0
	var att_col: Color = Tuning.PLAYER_COLORS[attacker().player_index]
	while director.clock_ms() - t0 < 700.0:
		await get_tree().process_frame
		if Engine.time_scale < 0.99:
			stop_frames += 1
		wave_seen = wave_seen or live_count("wave") > 0
		for c in director.fx_root.get_children():
			if c is Shockwave and not c.is_queued_for_deletion():
				var sw := c as Shockwave
				if sw.thickness() > 0.2:
					wave_r_max = maxf(wave_r_max, sw.scale.x)
					wave_thick = maxf(wave_thick, sw.thickness())
					var col: Color = (sw.material_override as ShaderMaterial).get_shader_parameter("colour")
					wave_col_ok = wave_col_ok or (absf(col.r - att_col.r) < 0.02 and absf(col.g - att_col.g) < 0.02 and absf(col.b - att_col.b) < 0.02)
			if c is SparkCone and not c.is_queued_for_deletion():
				spark_seen = true
		if star_at_100 < 0.0 and director.clock_ms() - t0 >= 100.0:
			star_at_100 = 0.0
			if is_instance_valid(star_fx):
				for fl in star_fx.get_children():
					if fl is ImpactFlash and not fl.is_queued_for_deletion() and (fl as ImpactFlash).visible:
						var q := (fl as ImpactFlash).get_child(0) as MeshInstance3D
						star_at_100 = maxf(star_at_100, (1.0 - q.transparency) * (fl as ImpactFlash).scale.x)
		if cam.has_method("focus_lead"):
			var ld: Vector2 = cam.call("focus_lead")
			if ld.length() > lead_max:
				lead_max = ld.length()
				lead_dot = ld.normalized().dot(Vector2(dir.x, dir.y).normalized())
		max_trails = maxi(max_trails, live_count("trail"))
		for c in director.fx_root.get_children():
			if c is AfterimageTrail:
				max_snap = maxi(max_snap, (c as AfterimageTrail).snapshots)
		lines_seen = lines_seen or (sfx.get_node("SpeedLines") as Control).visible
		punch_seen = punch_seen or not is_idle_cam()
		if director.clock_ms() - t0 >= 600.0 and not idle_at_600:
			idle_at_600 = is_idle_cam()
	var stop_ms := stop_frames * FRAME_MS
	check("heavy_flash_1", int(director.stats["flashes"]) - int(st["flashes"]) == 1 and sfx.flash_frames_shown - ff0 == 1, sfx.flash_frames_shown - ff0, 1)
	check("heavy_wave", wave_seen and int(director.stats["waves"]) > int(st["waves"]), director.stats["waves"], ">%d" % int(st["waves"]))
	check("heavy_afterimages_3", max_snap == HitFxDirector.HEAVY_GHOSTS, max_snap, HitFxDirector.HEAVY_GHOSTS)
	check("heavy_trail", max_trails >= 1, max_trails, ">=1")
	check("heavy_speed_lines", lines_seen, lines_seen, true)
	check("heavy_punch", punch_seen, punch_seen, true)
	check("heavy_cam_idle_600ms", idle_at_600, idle_at_600, true)
	check("heavy_spark", spark_seen and int(director.stats["sparks"]) > int(st["sparks"]), director.stats["sparks"], ">%d" % int(st["sparks"]))
	check("heavy_wave_big_thick", wave_r_max >= 1.7 and wave_thick >= 0.25, [snappedf(wave_r_max, 0.01), snappedf(wave_thick, 0.01)], [">=1.7 (1.8)", ">=0.25"])
	check("heavy_wave_attacker_colour", wave_col_ok, wave_col_ok, str(att_col))
	check("heavy_star_gone_100ms", star_at_100 >= 0.0 and star_at_100 <= 0.15, snappedf(star_at_100, 0.001), "<=0.15 (сжата/погашена)")
	check("heavy_star_collapsed", int(director.stats["flash_collapses"]) > int(st["flash_collapses"]), director.stats["flash_collapses"], ">%d" % int(st["flash_collapses"]))
	check("heavy_focus_lead", lead_max >= 0.3 and lead_dot > 0.7, [snappedf(lead_max, 0.01), snappedf(lead_dot, 0.01)], ["≥0.3 м", "вдоль полёта"])
	if not match_node.has_method("_emit_hit_fx"):
		check("heavy_hitstop_ms", absf(stop_ms - Tuning.HITFX_HEAVY_STOP_S * 1000.0) <= 17.0, snappedf(stop_ms, 0.1), "HITFX_HEAVY_STOP_S±17 (директор без ядра)")
	check("heavy_bursts", int(director.stats["bursts"]) - int(st["bursts"]) >= 2, int(director.stats["bursts"]) - int(st["bursts"]), ">=2")
	if match_node.has_method("_emit_hit_fx"):
		# с ядром hit-stop heavy ставит Match._emit_hit_fx: настоящий удар 12 HP через Match.on_hit
		await wait_ms(800.0)
		var np := director.played.size()
		stop_frames = 0
		launch(v, 4.2, dir)
		var vv := v
		await physics_call(func() -> void: match_node.on_hit(vv, attacker(), 12.0, "body", vv.torso().global_position, 1, false, "", 6.0))
		t0 = director.clock_ms()
		var slow_frames := 0
		while director.clock_ms() - t0 < 300.0:
			await get_tree().process_frame
			# стоп-кадр — только кадры HIT_STOP_TIME_SCALE; за ним замедление heavy_slow сока удара (HIT_FX.md §13)
			if Engine.time_scale <= Tuning.HIT_STOP_TIME_SCALE + 1e-3:
				stop_frames += 1
			elif Engine.time_scale < 0.99:
				slow_frames += 1
			if OS.has_environment("HITFX_DEBUG"):
				print("dbg t=%.1f ts=%.3f eff=%s" % [director.clock_ms() - t0, Engine.time_scale, str(match_node.get("_time_effects"))])
		stop_ms = stop_frames * FRAME_MS
		var tr := String((director.played[director.played.size() - 1] as Dictionary).get("tier", "")) if director.played.size() > np else ""
		check("heavy_core_tier", tr == "heavy", tr, "heavy")
		var want_ms := Tuning.HITFX_HEAVY_STOP_S * 1000.0
		check("heavy_hitstop_ms", absf(stop_ms - want_ms) <= 17.0, snappedf(stop_ms, 0.1), "%.0f±17 (Match._emit_hit_fx, Tuning.HITFX_HEAVY_STOP_S)" % want_ms)
		if Tuning.JUICE_ENABLED and float(HitJuice.variant()["heavy_s"]) > 0.0:
			check("heavy_slow_after_stop", slow_frames >= 6, slow_frames, ">=6 frames of heavy_slow (HIT_FX.md §13)")
	await wait_quiet()
	check("heavy_freed_3s", director.fx_node_count() == base, director.fx_node_count(), base)
	check("heavy_time_scale_1", is_equal_approx(Engine.time_scale, 1.0), Engine.time_scale, 1.0)

	# --- ko (синтетический, жертва жива) ---
	st = director.stats.duplicate()
	var if0 := sfx.impact_frames_shown
	var mf0 := sfx.masked_frames_shown
	launch(v, 3.5, dir)
	director.play(ctx_for("ko", 30.0))
	var ko_wave_max := 0.0
	var ko_trails := 0
	t0 = director.clock_ms()
	while director.clock_ms() - t0 < 1300.0:
		await get_tree().process_frame
		for c in director.fx_root.get_children():
			if c is Shockwave and not c.is_queued_for_deletion():
				ko_wave_max = maxf(ko_wave_max, (c as Shockwave).scale.x)
			if c is FlightTrail:
				ko_trails = maxi(ko_trails, (c as FlightTrail).tracks)
	check("ko_masked_frames", sfx.masked_frames_shown - mf0 == 2, sfx.masked_frames_shown - mf0, 2)
	check("ko_mask_bits_restored", director.doll_mask.marked_count() == 0 and not director.doll_mask.active() and mask_bits(v) == 0,
		[director.doll_mask.marked_count(), director.doll_mask.active(), mask_bits(v)], [0, false, 0])
	check("ko_inversion_2_frames", sfx.impact_frames_shown - if0 == 2 and int(director.stats["impact_frames"]) - int(st["impact_frames"]) == 1, sfx.impact_frames_shown - if0, 2)
	check("ko_big_wave", ko_wave_max >= 1.8, snappedf(ko_wave_max, 0.01), ">=1.8 (2.2)")
	check("ko_trails_head_torso", ko_trails == 2, ko_trails, 2)
	check("ko_trail_gone_1300ms", live_count("trail") == 0, live_count("trail"), 0)
	await wait_quiet()
	check("ko_freed_3s", director.fx_node_count() == base, director.fx_node_count(), base)

	# --- slam (синтетический) ---
	st = director.stats.duplicate()
	var hp0 := v.hp
	var arena_b: AABB = (pg.get("arena") as Node).call("bounds") if pg.get("arena") != null else AABB()
	var wall := Vector3(arena_b.end.x if arena_b.size.x > 0.0 else 8.0, 1.0, 0.0)
	director.play_slam({"doll": v, "part": "Torso", "speed": 8.0, "position": wall, "normal": Vector3.LEFT,
		"flying": true, "crit_flight": false, "fight_time": match_node.fight_time})
	await frames(2)
	var shake_amp := float(cam.get("_shake_amp")) if cam.get("_shake_amp") != null else -1.0
	check("slam_played", int(director.stats["slams"]) == int(st["slams"]) + 1, director.stats["slams"], int(st["slams"]) + 1)
	check("slam_dust_splinters", int(director.stats["bursts"]) - int(st["bursts"]) == 2, int(director.stats["bursts"]) - int(st["bursts"]), 2)
	check("slam_shake", shake_amp > 0.0, snappedf(shake_amp, 0.001), "> 0 (0.048 × intensity)")
	check("slam_no_flash", int(director.stats["flashes"]) == int(st["flashes"]) and int(director.stats["impact_frames"]) == int(st["impact_frames"]), director.stats["flashes"], st["flashes"])
	check("slam_hp_unchanged", is_equal_approx(v.hp, hp0), v.hp, hp0)
	director.play_slam({"doll": v, "part": "Torso", "speed": 9.0, "position": wall, "normal": Vector3.LEFT,
		"flying": true, "crit_flight": true, "fight_time": match_node.fight_time})
	await frames(2)
	check("slam_crit_cooldown", int(director.stats["slams"]) == int(st["slams"]) + 1, director.stats["slams"], "cooldown 120 ms")
	await wait_ms(200.0)
	director.play_slam({"doll": v, "part": "Torso", "speed": 9.0, "position": wall, "normal": Vector3.LEFT,
		"flying": true, "crit_flight": true, "fight_time": match_node.fight_time})
	await frames(2)
	check("slam_crit_flight_wave", int(director.stats["waves"]) > int(st["waves"]), director.stats["waves"], ">%d" % int(st["waves"]))
	# настоящий удар о стену Void — только когда ядро шлёт Match.env_slam
	if match_node.has_signal("env_slam"):
		var n_slam := [0]
		match_node.connect("env_slam", func(_c: Dictionary) -> void: n_slam[0] += 1)
		var slams0 := int(director.stats["slams"])
		await wait_ms(400.0)
		var hp1 := v.hp
		var off := wall.x - 1.3 - v.centre_of_mass().x
		for b in v.parts.values():
			(b as RigidBody3D).global_position.x += off
		launch(v, 8.0, Vector3.RIGHT)
		t0 = director.clock_ms()
		while director.clock_ms() - t0 < 700.0:
			await get_tree().process_frame
		check("wall_env_slam_signal", n_slam[0] >= 1, n_slam[0], ">=1")
		check("wall_env_slam_played", int(director.stats["slams"]) > slams0, int(director.stats["slams"]) - slams0, ">=1")
		check("wall_hp_unchanged", is_equal_approx(v.hp, hp1), v.hp, hp1)
	else:
		report["info"]["wall_slam"] = "skipped: Match.env_slam нет (ядро ещё не подключено)"
	await wait_quiet()
	check("slam_freed_3s", director.fx_node_count() == base, director.fx_node_count(), base)

	# --- crit (без ката, если CritCinematic нет) ---
	st = director.stats.duplicate()
	announces.clear()
	launch(v, 4.0, dir)
	director.play(ctx_for("crit", 24.0))
	var mode := String((director.played[director.played.size() - 1] as Dictionary).get("mode", ""))
	var saw_crit_cam := false
	t0 = director.clock_ms()
	while director.clock_ms() - t0 < 1500.0:
		await get_tree().process_frame
		saw_crit_cam = saw_crit_cam or get_viewport().get_camera_3d() != cam
	await frames(1)
	report["info"]["crit_mode"] = mode
	if mode == "crit_fallback":
		var cap := false
		for a in announces:
			cap = cap or String(a[0]) == HitFxDirector.CRIT_CAPTION or String(a[0]).begins_with("IMPACT ")   # табло §13
		check("crit_fallback_caption", cap, announces, HitFxDirector.CRIT_CAPTION)
		check("crit_fallback_time_requests", int(director.stats["time_requests"]) - int(st["time_requests"]) == 2, int(director.stats["time_requests"]) - int(st["time_requests"]), 2)
		check("crit_fallback_afterimages", int(director.stats["afterimages"]) > int(st["afterimages"]), director.stats["afterimages"], ">%d" % int(st["afterimages"]))
	else:
		check("crit_cinematic_cut", saw_crit_cam, saw_crit_cam, true)
	check("crit_time_scale_restored", is_equal_approx(Engine.time_scale, 1.0), Engine.time_scale, 1.0)
	check("crit_camera_restored", get_viewport().get_camera_3d() == cam, str(get_viewport().get_camera_3d()), str(cam))
	if match_node.has_method("time_scale_tags"):
		var tags: Array = match_node.call("time_scale_tags")
		var bad := tags.filter(func(t: Variant) -> bool: return String(t).begins_with("crit") or String(t) == "heavy_stop")
		check("crit_no_time_tags", bad.is_empty(), tags, [])
	await wait_quiet()
	if director.fx_node_count() != base:
		for c in director.fx_root.get_children():
			print("left: ", c, " ", c.get_class(), " children=", c.get_child_count(), " q=", c.is_queued_for_deletion())
		for c in director.screen_fx.get_children():
			print("screen: ", c)
	check("crit_freed_3s", director.fx_node_count() == base, director.fx_node_count(), base)

	# --- доступность: flash_intensity 0 ---
	st = director.stats.duplicate()
	ff0 = sfx.flash_frames_shown
	if0 = sfx.impact_frames_shown
	director.flash_intensity = 0.0
	director.play(ctx_for("heavy", 12.0))
	director.play(ctx_for("ko", 30.0))
	await frames(6)
	check("a11y_no_flash_at_0", sfx.flash_frames_shown == ff0 and sfx.impact_frames_shown == if0, [sfx.flash_frames_shown - ff0, sfx.impact_frames_shown - if0], [0, 0])
	# v3 (§12.3): reduced (flash 0.4) — кольцо меньше по размеру, не только прозрачнее
	director.flash_intensity = 0.4
	await wait_ms(400.0)
	director.play(ctx_for("heavy", 12.0))
	var red_r := 0.0
	var tr0 := director.clock_ms()
	while director.clock_ms() - tr0 < 260.0:
		await get_tree().process_frame
		for c in director.fx_root.get_children():
			if c is Shockwave and not c.is_queued_for_deletion() and (c as Shockwave).thickness() > 0.2:
				red_r = maxf(red_r, (c as Shockwave).scale.x)
	var want_r := HitFxDirector.HEAVY_WAVE_R.y * lerpf(HitFxDirector.WAVE_SIZE_MIN, 1.0, 0.4)
	check("reduced_wave_smaller", red_r > 0.0 and red_r <= want_r + 0.05 and red_r < HitFxDirector.HEAVY_WAVE_R.y - 0.3,
		snappedf(red_r, 0.01), "≈%.2f (full 1.8)" % want_r)
	director.flash_intensity = 1.0
	await wait_ms(1100.0)
	# 10 heavy за 1 с → не больше 3 полноэкранных вспышек; лимиты следов
	st = director.stats.duplicate()
	var max_live_trails := 0
	var max_live_ghosts := 0
	for i in range(10):
		launch(v, 4.0, dir)
		director.play(ctx_for("heavy", 12.0))
		await frames(6)
		max_live_trails = maxi(max_live_trails, live_count("trail"))
		max_live_ghosts = maxi(max_live_ghosts, live_count("ghost"))
	check("a11y_max_3_flashes_per_s", int(director.stats["flashes"]) - int(st["flashes"]) <= Tuning.HITFX_MAX_FLASHES_PER_S, int(director.stats["flashes"]) - int(st["flashes"]), "<=%d" % Tuning.HITFX_MAX_FLASHES_PER_S)
	check("limit_trails", max_live_trails <= HitFxDirector.MAX_TRAILS, max_live_trails, "<=%d" % HitFxDirector.MAX_TRAILS)
	check("limit_afterimages", max_live_ghosts <= HitFxDirector.MAX_AFTERIMAGES, max_live_ghosts, "<=%d" % HitFxDirector.MAX_AFTERIMAGES)
	await wait_quiet()
	check("spam_freed_3s", director.fx_node_count() == base, director.fx_node_count(), base)
	check("spam_cam_idle", is_idle_cam(), is_idle_cam(), true)

	# --- материалы жертвы не менялись; на частях нет чужих узлов ---
	var ov1 := overlays(v)
	var same := ov0.size() == ov1.size()
	if same:
		for i in range(ov0.size()):
			same = same and ov0[i][0] == ov1[i][0] and ov0[i][1] == ov1[i][1] and ov0[i][2] == ov1[i][2]
	check("victim_materials_unchanged", same, ov1.size(), ov0.size())
	var foreign := 0
	for b in v.parts.values():
		for c in (b as Node).find_children("*", "", true, false):
			if c is Decal or c is AfterimageTrail or c is FlightTrail or c is Shockwave:
				foreign += 1
	check("no_fx_nodes_on_parts", foreign == 0, foreign, 0)

	# --- кукла без мешей: послеобразы из коллизий ---
	for mi in v.find_children("*", "MeshInstance3D", true, false):
		(mi as Node).queue_free()
	await frames(2)
	launch(v, 4.2, dir)
	director.play(ctx_for("heavy", 12.0))
	await wait_ms(200.0)
	var coll := false
	var snaps := 0
	for c in director.fx_root.get_children():
		if c is AfterimageTrail:
			coll = coll or (c as AfterimageTrail).from_collision
			snaps = maxi(snaps, (c as AfterimageTrail).snapshots)
	check("no_meshes_afterimages_from_collision", coll and snaps >= 1, [coll, snaps], [true, ">=1"])

	# --- restart посреди heavy: всё снято ---
	await wait_ms(3000.0)
	launch(v, 4.2, dir)
	director.play(ctx_for("heavy", 12.0))
	await wait_ms(100.0)
	match_node.restart()
	await frames(2)
	check("restart_freed", director.fx_node_count() == base, director.fx_node_count(), base)
	check("restart_time_scale_1", is_equal_approx(Engine.time_scale, 1.0), Engine.time_scale, 1.0)
	check("restart_cam_idle", is_idle_cam(), is_idle_cam(), true)
	check("restart_screen_clear", not sfx.active(), sfx.active(), false)
	if match_node.has_method("camera_owner"):
		check("restart_camera_owner_empty", String(match_node.call("camera_owner")) == "", match_node.call("camera_owner"), "")
	await frames(30)

	# --- v3 (HIT_FX §12.2): тормоз атакующего на heavy — один сценарий с тормозом и без (как v2) ---
	if match_node.has_method("_emit_hit_fx"):
		# один и тот же сценарий с тормозом и без; рывок — 4 дистанции (физика хаотична, одна пара ничего не доказывает)
		var runs := {}
		var gaps := {"stand": [1.2, 1.6], "dash": [1.0, 1.1, 1.2, 1.3]}
		for bm in ["stand", "dash"]:
			for g in gaps[bm]:
				for brake in [false, true]:
					runs["%s_%.1f_%s" % [bm, g, "on" if brake else "off"]] = await _brake_run(bm, brake, g)
		report["info"]["heavy_brake"] = runs
		for bm in ["stand", "dash"]:
			var tiers_ok := true
			var along_max := 0.0
			var g_off := 0.0
			var g_on := 0.0
			for g in gaps[bm]:
				var on: Dictionary = runs["%s_%.1f_on" % [bm, g]]
				var off: Dictionary = runs["%s_%.1f_off" % [bm, g]]
				tiers_ok = tiers_ok and String(on["tier"]) == "heavy" and String(off["tier"]) == "heavy"
				along_max = maxf(along_max, float(on["along_max"]))
				g_off += float(off["gap_400"]) / float(gaps[bm].size())
				g_on += float(on["gap_400"]) / float(gaps[bm].size())
			check("heavy_brake_tier_" + bm, tiers_ok, tiers_ok, "heavy")
			if bm == "stand":
				check("heavy_brake_along_" + bm, along_max <= Tuning.HEAVY_ATTACKER_BRAKE_SPEED + 0.05,
					snappedf(along_max, 0.01), "<= %.1f м/с вдоль отлёта (в ударе; окно %.2f с)" % [Tuning.HEAVY_ATTACKER_BRAKE_SPEED, Tuning.HEAVY_ATTACKER_BRAKE_S])
			else:
				report["info"]["heavy_brake_dash_along_max"] = along_max   # в упоре рывка DollCombat засчитывает и свои удары — только справка
			# HIT_FX §12.2: разлёт на +400 мс — только справка. С отдачей DollCombat атакующий в ударе уже отходит (along < 0, клэмп
			# ничего не снимает), а повтор одного и того же прогона после restart расходится на ±0.3 м (Jolt, клинч конечностей) —
			# разница «с тормозом / без» тут шум, а не свойство тормоза.
			report["info"]["heavy_brake_gap_400_" + bm] = [snappedf(g_off, 0.01), snappedf(g_on, 0.01)]
		# тормоз сам по себе (окно UNIT_BRAKE_S — механизм окна; по умолчанию Tuning.HEAVY_ATTACKER_BRAKE_S = 0 — только клэмп в ударе): атакующий 6 м/с вдоль удара, вдали от жертвы — клэмп в окне, после окна узла нет, исключений столкновений нет
		match_node.restart()
		await frames(60)
		var ua := pg.get_node("P1") as Doll
		var uv := pg.get_node("P2") as Doll
		ua.external_input = true
		uv.external_input = true
		await frames(30)
		var udir := Vector3(1.0, 0.0, 0.0)
		var ukb := Damage.knockback_dir(udir)
		var uexc0 := (ua.torso() as PhysicsBody3D).get_collision_exceptions().size()
		var ucut := [0.0]
		await physics_call(func() -> void:
			for b in ua.parts.values():
				(b as RigidBody3D).linear_velocity = udir * 6.0
			ucut[0] = CritLaunch.brake_attacker({"attacker": ua, "victim": uv, "dir": udir}, Tuning.HEAVY_ATTACKER_BRAKE_SPEED, UNIT_BRAKE_S))
		var ut0 := ua._time
		var u_in := 0.0
		var u_node_after := true
		var u_exc := 0
		while ua._time - ut0 < UNIT_BRAKE_S + 0.1:
			await get_tree().physics_frame
			if ua._time - ut0 < UNIT_BRAKE_S - 0.02:
				u_in = maxf(u_in, com_velocity(ua).dot(ukb))
				for b in ua.parts.values():   # во время тормоза атакующий снова «разгоняется» (как тяга / толчок жертвы)
					(b as RigidBody3D).linear_velocity += udir * 0.5
			u_exc = maxi(u_exc, (ua.torso() as PhysicsBody3D).get_collision_exceptions().size())
		u_node_after = ua.get_node_or_null(CritLaunch.HeavyBrake.NODE_NAME) != null
		check("heavy_brake_unit", ucut[0] > 2.0 and u_in <= Tuning.HEAVY_ATTACKER_BRAKE_SPEED + 0.05 and not u_node_after and u_exc == uexc0,
			[snappedf(ucut[0], 0.01), snappedf(u_in, 0.01), u_node_after, u_exc - uexc0], ["cut > 2", "<= %.1f в окне" % Tuning.HEAVY_ATTACKER_BRAKE_SPEED, false, 0])
		var one := ua.get_node_or_null(CritLaunch.HeavyBrake.NODE_NAME) == null
		await physics_call(func() -> void:
			for b in ua.parts.values():
				(b as RigidBody3D).linear_velocity = udir * 6.0
			ucut[0] = CritLaunch.brake_attacker({"attacker": ua, "victim": uv, "dir": udir}, Tuning.HEAVY_ATTACKER_BRAKE_SPEED, 0.0)
			one = one and ua.get_node_or_null(CritLaunch.HeavyBrake.NODE_NAME) == null)
		check("heavy_brake_one_shot", ucut[0] > 2.0 and one and com_velocity(ua).dot(ukb) <= Tuning.HEAVY_ATTACKER_BRAKE_SPEED + 0.3,
			[snappedf(ucut[0], 0.01), one, snappedf(com_velocity(ua).dot(ukb), 0.01)], ["cut > 2", "без узла", "≈ 2.5"])
		match_node.restart()
		await frames(60)
		for d in [pg.get_node("P1"), pg.get_node("P2")]:
			(d as Doll).external_input = true
		await frames(30)

	# --- настоящий удар через Match.on_hit (ядро → hit_fx, без ядра → Match.hit) ---
	var n_played := director.played.size()
	v = victim()
	match_node.on_hit(v, attacker(), 12.0, "body", v.torso().global_position, 1, false, "", 6.0)
	await frames(2)
	var last_tier := String((director.played[director.played.size() - 1] as Dictionary).get("tier", "")) if director.played.size() > n_played else ""
	check("match_on_hit_reaches_director", director.played.size() > n_played, last_tier, "light|heavy")
	await wait_ms(1500.0)

	# --- настоящий KO: take_damage → Match KO (slow-mo) → on_hit → ko ---
	n_played = director.played.size()
	if0 = sfx.impact_frames_shown
	v.take_damage(500.0, attacker(), "Head", v.head().global_position, Vector3.LEFT, "head")
	match_node.on_hit(v, attacker(), 500.0, "head", v.head().global_position, 1, false, "", 8.0)
	await frames(4)
	var ko_tier := String((director.played[director.played.size() - 1] as Dictionary).get("tier", "")) if director.played.size() > n_played else ""
	check("real_ko_tier", ko_tier == "ko" or ko_tier == "ko_crit", ko_tier, "ko|ko_crit")
	var ko_mode := String((director.played[director.played.size() - 1] as Dictionary).get("mode", ""))
	report["info"]["real_ko_mode"] = ko_mode
	if ko_mode != "cinematic":
		check("real_ko_inversion", sfx.impact_frames_shown - if0 >= 1, sfx.impact_frames_shown - if0, ">=1")
	await wait_ms(2600.0)
	check("real_ko_time_scale_1", is_equal_approx(Engine.time_scale, 1.0), Engine.time_scale, 1.0)
	await wait_ms(1500.0)
	check("real_ko_freed", director.fx_node_count() == base, director.fx_node_count(), base)

	# --- итог ---
	check("final_camera_game", get_viewport().get_camera_3d() == cam, str(get_viewport().get_camera_3d()), str(cam))
	check("final_match_fx_children", director_children() == match_children and match_children >= 1, director_children(), match_children)
	report["info"]["played"] = director.played.size()
	report["info"]["stats"] = director.stats
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  ", false))
	print("HITFX_PROBE %s checks=%d" % ["OK" if report["ok"] else "FAIL", (report["checks"] as Array).size()])
	get_tree().quit(0 if report["ok"] else 1)
