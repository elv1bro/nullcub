## Проба звука ударов SfxDirector (docs/plan-demo/HIT_FX.md §2.5, §4.4, §5.4 «Звук»), headless (аудио-драйвер Dummy):
## настоящая площадка Void с Match и HUD; SfxDirector — ребёнок Match (Match._ensure_fx_directors) или подключается вручную.
## Проверки (checks[].id):
##   scene_voices — 12 голосов AudioStreamPlayer; layers_loaded — все слои LAYER_ORDER, каждый звук — OGG длиной > 0.05 с;
##   buses — SFX (→ Master; LowPass выкл., HardLimiter −0.5 dB), SFX_PanL2…R2 (→ SFX, AudioEffectPanner), SFX_Crit (→ Master);
##   attached / bound — один директор под Match, подписки на сигналы Match; countdown_ticks / fight_gong — отсчёт и гонг FIGHT!;
##   light — «ток» (−10…−4 dB, питч 1.15–1.3), light_rate — не чаще раза в 60 мс на жертву; heavy — удар + треск + тумп,
##   heavy_whoosh — «вух» ~70 мс по скорости ЦМ; crit_cine_* — таймлайн крита: freeze 0 (удар, вдох) / cut_in 120 (бум, тумп,
##   удар, zap, треск, скрип) / caption 220 (ох) / crack_2 400 / cut_out 620 (свист, вух) ±17 мс, всё на SFX_Crit, мир заглушён
##   (low-pass ≤ 1 кГц) 70–600 мс и открыт с 720 мс; crit_sync_* — фазы CritCinematic ведут звук (кат на 200 мс → бум на 200,
##   а не 120; нет двойного вдоха); crit_short — крит без крупного плана; ko — KO + треск + рассыпание, аплодисменты 300 мс,
##   ko_dedupe — hit_fx(ko) того же удара не дублирует KO; ko_crit_cheer — аплодисменты после выхода из крупного плана (700 мс);
##   slam / slam_crit — тумп; в крит-полёте ещё треск и crash; sd_gong (2 удара, 260 мс), over_gong (3 удара, 220 мс);
##   slowmo_pitch — питч × 0.3^0.2 в slow-mo 0.3×, гонг без, стоп-кадр 0.02× без; pan_bus — панорамные шины, pan_side — P1
##   левее P2; voice_limit — 16 слоёв разом → голосов ≤ 12, лишние вытеснены/отброшены; layer_cap — не больше 4 голосов слоя;
##   muffle / muffle_watchdog; abort — COUNTDOWN снимает очередь и глушение; signal_path — удар через настоящий сигнал Match;
##   fight_* — бой ботов fight_s секунд: звуки есть, голосов ≤ 12, time_scale вернулся к 1.
## Запуск: godot --headless --path . --fixed-fps 60 res://tests/sfx_probe.tscn -- "fight_s=20"
## Отчёт tests/sfx_probe_report.json, exit 0/1.
extends Node3D

const VOID := "res://scenes/playground_void.tscn"
const SFX_SCENE := "res://scenes/audio/sfx_director.tscn"
const TOL_MS := 17.0
const RUSH_NEAR := 1.3
const RUSH_RETREAT_S := 1.2
const DASH_FROM_M := 2.0


class FakeCine extends Node:
	signal phase(name: String, ms: float)
	var playing := false
	var t0 := 0.0

	func is_playing() -> bool:
		return playing

	func elapsed_ms() -> float:
		return 0.0


var fight_s := 20.0
var pg: Node3D
var match_node: Match
var sfx: SfxDirector
var p1: Doll
var p2: Doll
var hold_vel: Dictionary = {}          # Doll -> Vector3: скорость частей держится каждый физический тик
var rush_retreat: Dictionary = {}
var fight := false
var t := 0.0
var report := {"ok": true, "checks": [], "info": {}}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "fight_s":
				fight_s = float(p[1])
	_run()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _wait_ms(ms: float) -> void:
	var until := sfx.clock_ms() + ms
	while sfx.clock_ms() < until:
		await get_tree().process_frame


func _check(id: String, ok: bool, detail: String) -> void:
	report["checks"].append({"id": id, "ok": ok, "detail": detail})
	if not ok:
		report["ok"] = false
	print("  %s %s: %s" % ["ok  " if ok else "FAIL", id, detail])


func _since(t0: float) -> Array:
	var out: Array = []
	for e in sfx.played:
		if float(e["ms"]) >= t0 - 0.05:
			out.append(e)
	return out


func _layers(entries: Array) -> Array:
	var out: Array = []
	for e in entries:
		out.append(e["layer"])
	return out


func _count(entries: Array, layer: String) -> int:
	var n := 0
	for e in entries:
		if e["layer"] == layer:
			n += 1
	return n


## Слой layer сыгран в t0 + at_ms ± TOL_MS (и на шине bus, если задана).
func _at(entries: Array, t0: float, layer: String, at_ms: float, bus: String = "") -> bool:
	for e in entries:
		if e["layer"] == layer and absf(float(e["ms"]) - t0 - at_ms) <= TOL_MS and (bus == "" or e["bus"] == bus):
			return true
	return false


func _offsets(entries: Array, t0: float) -> Array:
	var out: Array = []
	for e in entries:
		out.append("%s@%d%s" % [e["layer"], roundi(float(e["ms"]) - t0), "" if e["bus"] != SfxDirector.BUS_CRIT else "c"])
	return out


func _ctx(tier: String, victim: Doll, attacker: Doll, damage: float) -> Dictionary:
	return {"victim": victim, "attacker": attacker, "damage": damage, "kind": "body", "part": "Torso", "part_base": "Torso",
		"position": victim.centre_of_mass(), "normal": Vector3.LEFT, "dir": Vector3.RIGHT, "tier": tier, "score": damage,
		"is_ko": tier.begins_with("ko"), "hp_after": victim.hp, "speed": 6.0, "combo": 1, "double_blow": false, "dash": false}


func _physics_process(delta: float) -> void:
	t += delta
	for d in hold_vel.keys():
		if is_instance_valid(d):
			for b in (d as Doll).parts.values():
				(b as RigidBody3D).linear_velocity = hold_vel[d]
	if fight and match_node.combat_active():
		_rush(p1, p2)
		_rush(p2, p1)


func _rush(d: Doll, other: Doll) -> void:
	if d == null or other == null or not is_instance_valid(d) or not is_instance_valid(other) or not d.alive or not other.alive:
		return
	var dx := other.centre_of_mass().x - d.centre_of_mass().x
	var dy := other.centre_of_mass().y - d.centre_of_mass().y
	var sgn := signf(dx) if absf(dx) > 0.05 else 1.0
	var vy := clampf(dy / 1.5, -1.0, 1.0) if absf(dy) > 0.8 else 0.0
	if t < float(rush_retreat.get(d, -1.0)):
		d.input_vec = Vector2(-sgn, 0.0)
	elif absf(dx) < RUSH_NEAR and absf(dy) < 1.2:
		rush_retreat[d] = t + RUSH_RETREAT_S
		d.input_vec = Vector2(-sgn, 0.0)
	else:
		if absf(dx) > DASH_FROM_M and d._time >= d.dash_ready_at and not d.is_stunned():
			d.dash_until = d._time + Tuning.DASH_DURATION_S
			d.dash_ready_at = d._time + Tuning.DASH_COOLDOWN_S
		d.input_vec = Vector2(sgn, vy)


func _run() -> void:
	report["info"]["display"] = DisplayServer.get_name()
	report["info"]["mix_rate"] = AudioServer.get_mix_rate()
	pg = (load(VOID) as PackedScene).instantiate() as Node3D
	add_child(pg)
	match_node = pg.get_node("Match") as Match
	p1 = pg.get_node("P1") as Doll
	p2 = pg.get_node("P2") as Doll
	await _frames(2)
	var found: Array = []
	for c in match_node.get_children():
		if c is SfxDirector:
			found.append(c)
	if found.is_empty():
		sfx = (load(SFX_SCENE) as PackedScene).instantiate() as SfxDirector
		match_node.add_child(sfx)
		report["info"]["attached"] = "manual"
		await _frames(2)
	else:
		sfx = found[0]
		report["info"]["attached"] = "match"
	var n_dir := 0
	for c in match_node.get_children():
		if c is SfxDirector:
			n_dir += 1
	_check("attached", n_dir == 1, "%s, директоров под Match: %d" % [report["info"]["attached"], n_dir])
	_check_resources()
	_check_buses()
	var hit_sig := "hit_fx" if match_node.has_signal("hit_fx") else "hit"
	var need := [hit_sig, "ko", "announce", "phase_changed", "match_over"]
	if match_node.has_signal("env_slam"):
		need.append("env_slam")
	var missing: Array = []
	for s in need:
		if not sfx.bound.has(s):
			missing.append(s)
	_check("bound", missing.is_empty(), "подписки %s (нет: %s)" % [str(sfx.bound), str(missing)])
	report["info"]["core_hit_fx"] = match_node.has_signal("hit_fx")
	# отсчёт и FIGHT!
	var st := {"fight_ms": -1.0}           # лямбды GDScript захватывают локальные по значению — состояние в словаре
	match_node.announce.connect(func(_tx: String, _c: Color, kind: String) -> void:
		if kind == "fight":
			st["fight_ms"] = sfx.clock_ms())
	var guard := 0
	while match_node.phase != Match.Phase.FIGHT and guard < 400:
		await _frames(1)
		guard += 1
	await _frames(2)
	_check("countdown_ticks", _count(sfx.played, "tok") >= 2, "тиков отсчёта: %d" % _count(sfx.played, "tok"))
	var fight_ms := float(st["fight_ms"])
	_check("fight_gong", fight_ms >= 0.0 and _at(sfx.played, fight_ms, "gong", 0.0), "FIGHT! @%.0f мс, звуки %s" % [fight_ms, str(_layers(sfx.played))])
	await _wait_ms(300.0)
	await _test_light()
	await _test_heavy()
	await _test_crit_cine()
	await _test_crit_sync()
	await _test_crit_short()
	await _test_ko()
	await _test_slam()
	await _test_gongs()
	await _test_slowmo_pitch()
	await _test_pan()
	await _test_voice_limit()
	await _test_muffle()
	await _test_abort()
	await _test_signal_path()
	await _test_real_crit()
	await _test_fight()
	report["info"]["dropped"] = sfx.dropped
	report["info"]["stolen"] = sfx.stolen
	report["info"]["played_total"] = sfx.played.size()
	_finish()


func _check_resources() -> void:
	var players := 0
	for c in sfx.get_children():
		if c is AudioStreamPlayer:
			players += 1
	_check("scene_voices", players == SfxDirector.VOICES and sfx.voice_count() == SfxDirector.VOICES, "голосов %d / %d" % [players, sfx.voice_count()])
	var bad: Array = []
	var counts := {}
	for layer in SfxDirector.LAYER_ORDER:
		var rs: AudioStreamRandomizer = sfx.layers.get(layer, null)
		if rs == null or rs.streams_count == 0:
			bad.append(layer)
			continue
		counts[layer] = rs.streams_count
		for i in range(rs.streams_count):
			var s := rs.get_stream(i)
			if not s is AudioStreamOggVorbis or s.get_length() < 0.05:
				bad.append("%s#%d" % [layer, i])
	report["info"]["layers"] = counts
	_check("layers_loaded", bad.is_empty(), "%d слоёв, плохие: %s" % [counts.size(), str(bad)])


func _check_buses() -> void:
	var errs: Array = []
	var sfx_i := AudioServer.get_bus_index(SfxDirector.BUS_SFX)
	var crit_i := AudioServer.get_bus_index(SfxDirector.BUS_CRIT)
	if sfx_i < 0 or crit_i < 0:
		errs.append("нет SFX/SFX_Crit")
	else:
		if AudioServer.get_bus_send(sfx_i) != &"Master":
			errs.append("SFX → %s" % AudioServer.get_bus_send(sfx_i))
		if AudioServer.get_bus_send(crit_i) != &"Master":
			errs.append("SFX_Crit → %s" % AudioServer.get_bus_send(crit_i))
		var n := AudioServer.get_bus_effect_count(sfx_i)
		if n < 2 or not AudioServer.get_bus_effect(sfx_i, 0) is AudioEffectLowPassFilter or AudioServer.is_bus_effect_enabled(sfx_i, 0):
			errs.append("SFX: LowPass первым и выключен")
		var lim := AudioServer.get_bus_effect(sfx_i, n - 1) as AudioEffectHardLimiter
		if lim == null or not is_equal_approx(lim.ceiling_db, SfxDirector.LIMITER_CEILING_DB):
			errs.append("SFX: HardLimiter −0.5 dB последним")
		for k in SfxDirector.PAN_BUSES.keys():
			var j := AudioServer.get_bus_index(SfxDirector.PAN_BUSES[k])
			var pan := AudioServer.get_bus_effect(j, 0) as AudioEffectPanner if j >= 0 and AudioServer.get_bus_effect_count(j) > 0 else null
			if j < 0 or j < sfx_i or AudioServer.get_bus_send(j) != &"SFX" or pan == null or not is_equal_approx(pan.pan, float(k) * SfxDirector.PAN_STEP):
				errs.append("шина %s" % SfxDirector.PAN_BUSES[k])
	var names: Array = []
	for i in range(AudioServer.bus_count):
		names.append(AudioServer.get_bus_name(i))
	report["info"]["buses"] = names
	_check("buses", errs.is_empty(), "%s %s" % [str(names), str(errs)])


func _test_light() -> void:
	var t0 := sfx.clock_ms()
	var rate0 := int(sfx.dropped["rate"])
	sfx.handle_hit_fx(_ctx("light", p2, p1, 4.0))
	sfx.handle_hit_fx(_ctx("light", p2, p1, 4.0))
	var e := _since(t0)
	var ok := _layers(e) == ["tok"] and float(e[0]["db"]) >= -10.01 and float(e[0]["db"]) <= -3.99 \
		and float(e[0]["pitch"]) >= 1.149 and float(e[0]["pitch"]) <= 1.301
	_check("light", ok, "звуки %s" % str(e))
	await _frames(3)                         # 50 мс: слой уже можно (40 мс), жертву P2 ещё нельзя (60 мс)
	sfx.handle_hit_fx(_ctx("light", p2, p1, 4.0))
	sfx.handle_hit_fx(_ctx("light", p1, p2, 4.0))
	e = _since(t0)
	_check("light_rate", _count(e, "tok") == 2 and int(sfx.dropped["rate"]) - rate0 == 2,
		"ток %d (ждём 2), отброшено по жертве %d (ждём 2)" % [_count(e, "tok"), int(sfx.dropped["rate"]) - rate0])
	await _wait_ms(300.0)


func _test_heavy() -> void:
	hold_vel[p2] = Vector3(5.0, 0.0, 0.0)
	await _frames(2)
	var t0 := sfx.clock_ms()
	sfx.handle_hit_fx(_ctx("heavy", p2, p1, 12.0))
	var e0 := _since(t0)
	_check("heavy", _layers(e0) == ["punch", "crack", "thud"], "звуки %s" % str(_offsets(e0, t0)))
	await _wait_ms(150.0)
	hold_vel.clear()
	var e := _since(t0)
	_check("heavy_whoosh", _at(e, t0, "whoosh", SfxDirector.HEAVY_WHOOSH_MS), "звуки %s" % str(_offsets(e, t0)))
	for b in p2.parts.values():
		(b as RigidBody3D).linear_velocity = Vector3.ZERO
	await _wait_ms(800.0)


func _test_crit_cine() -> void:
	sfx.force_crit_mode = "cine"
	var t0 := sfx.clock_ms()
	sfx.handle_hit_fx(_ctx("crit", p2, p1, 24.0))
	var muffled_ok := true
	var open_ok := true
	var samples: Array = []
	while sfx.clock_ms() - t0 < 1450.0:
		await _frames(1)
		var dt := sfx.clock_ms() - t0
		var hz := sfx.muffle_cutoff_hz()
		if int(dt) % 100 < 17:
			samples.append("%d:%d" % [roundi(dt), roundi(hz)])
		if dt >= 70.0 and dt <= 600.0 and hz > 1000.0:
			muffled_ok = false
		if dt >= 720.0 and hz < SfxDirector.OPEN_HZ - 1.0:
			open_ok = false
	sfx.force_crit_mode = ""
	var e := _since(t0)
	var C := SfxDirector.BUS_CRIT
	var want := [["punch", 0.0], ["inhale", 0.0], ["boom", 120.0], ["thud", 120.0], ["punch", 120.0], ["zap_low", 120.0],
		["crack", 120.0], ["creak", 120.0], ["crowd_oof", 220.0], ["crack", 400.0], ["whistle", 620.0], ["whoosh", 620.0]]
	var miss: Array = []
	for w in want:
		if not _at(e, t0, w[0], w[1], C):
			miss.append("%s@%d" % [w[0], w[1]])
	_check("crit_cine_timeline", miss.is_empty() and e.size() == want.size(), "нет %s; звуки %s" % [str(miss), str(_offsets(e, t0))])
	_check("crit_cine_muffle", muffled_ok and open_ok, "срез low-pass (мс:Гц) %s" % str(samples))
	await _wait_ms(700.0)


func _test_crit_sync() -> void:
	var fake := FakeCine.new()
	fake.name = "FakeCritCinematic"
	add_child(fake)
	sfx.bind_cinematic(fake)
	# A: кинематограф (HitFxDirector) получил hit_fx раньше — freeze приходит до крит-ctx; кат на 200 мс вместо 120
	var t0 := sfx.clock_ms()
	fake.playing = true
	fake.phase.emit("freeze", 0.0)
	sfx.handle_hit_fx(_ctx("crit", p2, p1, 24.0))
	var marks := {"cut_in": 200.0, "caption": 300.0, "crack_2": 450.0, "cut_out": 700.0, "done": 1400.0}
	for ph in marks.keys():
		await _wait_ms(float(marks[ph]) - (sfx.clock_ms() - t0))
		fake.phase.emit(ph, sfx.clock_ms() - t0)
	fake.playing = false
	var e := _since(t0)
	var ok := _count(e, "inhale") == 1 and _count(e, "boom") == 1 and _at(e, t0, "boom", 200.0) and not _at(e, t0, "boom", 120.0) \
		and _at(e, t0, "crowd_oof", 300.0) and _at(e, t0, "whistle", 700.0) and _count(e, "crack") == 2
	_check("crit_sync_cine_first", ok, "звуки %s" % str(_offsets(e, t0)))
	await _wait_ms(400.0)
	# B: сначала hit_fx (свой таймлайн), freeze — в том же кадре; кат на 150 мс
	sfx.force_crit_mode = "cine"
	t0 = sfx.clock_ms()
	sfx.handle_hit_fx(_ctx("crit", p2, p1, 24.0))
	fake.playing = true
	fake.phase.emit("freeze", 0.0)
	sfx.force_crit_mode = ""
	marks = {"cut_in": 150.0, "caption": 250.0, "crack_2": 400.0, "cut_out": 620.0, "done": 1300.0}
	for ph in marks.keys():
		await _wait_ms(float(marks[ph]) - (sfx.clock_ms() - t0))
		fake.phase.emit(ph, sfx.clock_ms() - t0)
	fake.playing = false
	e = _since(t0)
	ok = _count(e, "inhale") == 1 and _count(e, "boom") == 1 and _at(e, t0, "boom", 150.0) and _count(e, "whistle") == 1
	_check("crit_sync_hit_first", ok, "звуки %s" % str(_offsets(e, t0)))
	sfx.set("_cine", null)
	fake.queue_free()
	await _wait_ms(500.0)


func _test_crit_short() -> void:
	sfx.force_crit_mode = "short"
	var t0 := sfx.clock_ms()
	sfx.handle_hit_fx(_ctx("crit", p2, p1, 24.0))
	var muffled := false
	while sfx.clock_ms() - t0 < 400.0:
		await _frames(1)
		muffled = muffled or sfx.is_muffled()
	sfx.force_crit_mode = ""
	var e := _since(t0)
	var C := SfxDirector.BUS_CRIT
	var ok := _at(e, t0, "punch", 0.0, C) and _at(e, t0, "thud", 0.0, C) and _at(e, t0, "boom", 0.0, C) and _at(e, t0, "crack", 0.0, C) \
		and _at(e, t0, "zap_low", 0.0, C) and _at(e, t0, "crowd_oof", SfxDirector.CRIT_SHORT_OOF_MS, C) \
		and _at(e, t0, "whoosh", SfxDirector.CRIT_SHORT_WHOOSH_MS, C) and not muffled and _count(e, "inhale") == 0
	_check("crit_short", ok, "звуки %s, глушение %s" % [str(_offsets(e, t0)), muffled])
	await _wait_ms(800.0)


func _test_ko() -> void:
	var t0 := sfx.clock_ms()
	sfx.handle_ko(p2, p1, {"position": p2.centre_of_mass()})
	sfx.handle_hit_fx(_ctx("ko", p2, p1, 30.0))
	await _wait_ms(450.0)
	var e := _since(t0)
	_check("ko", _at(e, t0, "ko", 0.0) and _at(e, t0, "crack", 0.0) and _at(e, t0, "shatter", 0.0) and _at(e, t0, "crowd_cheer", SfxDirector.KO_CHEER_MS),
		"звуки %s" % str(_offsets(e, t0)))
	_check("ko_dedupe", _count(e, "ko") == 1 and _count(e, "shatter") == 1 and _at(e, t0, "thud", 0.0), "KO %d, рассыпание %d" % [_count(e, "ko"), _count(e, "shatter")])
	await _wait_ms(800.0)
	# ko_crit: KO пришёл раньше hit_fx (как в ядре: knocked_out внутри take_damage), аплодисменты — после крупного плана
	sfx.force_crit_mode = "cine"
	t0 = sfx.clock_ms()
	sfx.handle_ko(p1, p2, {"position": p1.centre_of_mass()})
	sfx.handle_hit_fx(_ctx("ko_crit", p1, p2, 30.0))
	sfx.force_crit_mode = ""
	await _wait_ms(1500.0)
	e = _since(t0)
	_check("ko_crit_cheer", _count(e, "crowd_cheer") == 1 and _at(e, t0, "crowd_cheer", SfxDirector.KO_CRIT_CHEER_MS) and _count(e, "ko") == 1
		and _at(e, t0, "boom", 120.0, SfxDirector.BUS_CRIT), "звуки %s" % str(_offsets(e, t0)))
	await _wait_ms(300.0)


func _test_slam() -> void:
	var t0 := sfx.clock_ms()
	sfx.handle_env_slam({"doll": p2, "part": "Torso", "speed": 8.0, "position": p2.centre_of_mass(), "normal": Vector3.LEFT,
		"flying": true, "crit_flight": false, "fight_time": match_node.fight_time})
	var e := _since(t0)
	_check("slam", _layers(e) == ["thud"], "звуки %s" % str(_offsets(e, t0)))
	await _wait_ms(100.0)
	t0 = sfx.clock_ms()
	sfx.handle_env_slam({"doll": p2, "part": "Torso", "speed": 8.0, "position": p2.centre_of_mass(), "normal": Vector3.LEFT,
		"flying": true, "crit_flight": true, "fight_time": match_node.fight_time})
	e = _since(t0)
	_check("slam_crit", _layers(e) == ["thud", "crack", "crash"], "звуки %s" % str(_offsets(e, t0)))
	await _wait_ms(300.0)


func _test_gongs() -> void:
	var t0 := sfx.clock_ms()
	sfx.handle_announce("SUDDEN DEATH", Color.RED, "sudden_death")
	await _wait_ms(400.0)
	var e := _since(t0)
	_check("sd_gong", _count(e, "gong") == 2 and _at(e, t0, "gong", 0.0) and _at(e, t0, "gong", SfxDirector.SD_GONG_GAP_MS), "звуки %s" % str(_offsets(e, t0)))
	await _wait_ms(200.0)
	t0 = sfx.clock_ms()
	sfx.handle_match_over(p1, {})
	await _wait_ms(600.0)
	e = _since(t0)
	_check("over_gong", _count(e, "gong") == 3 and _at(e, t0, "gong", SfxDirector.OVER_GONG_GAP_MS * 2.0), "звуки %s" % str(_offsets(e, t0)))
	await _wait_ms(200.0)


func _test_slowmo_pitch() -> void:
	var ts0 := Engine.time_scale
	Engine.time_scale = 0.3
	var v1 := sfx.play_layer("tok", 0.0, 1.0)
	var v2 := sfx.play_layer("gong", -20.0, 1.0)
	var p_slow := sfx.voice(v1).pitch_scale if v1 >= 0 else -1.0
	var p_gong := sfx.voice(v2).pitch_scale if v2 >= 0 else -1.0
	Engine.time_scale = 0.02
	await _wait_ms(60.0)
	var v3 := sfx.play_layer("tok", 0.0, 1.0)
	var p_freeze := sfx.voice(v3).pitch_scale if v3 >= 0 else -1.0
	Engine.time_scale = ts0
	var want := pow(0.3, SfxDirector.SLOWMO_PITCH_EXP)
	_check("slowmo_pitch", absf(p_slow - want) < 0.002 and is_equal_approx(p_gong, 1.0) and is_equal_approx(p_freeze, 1.0),
		"0.3×: ток %.3f (ждём %.3f), гонг %.3f; 0.02×: ток %.3f" % [p_slow, want, p_gong, p_freeze])
	await _wait_ms(200.0)


func _test_pan() -> void:
	var a := sfx.play_layer("crack", -30.0, 1.0, SfxDirector.BUS_SFX, -0.5)
	var b := sfx.play_layer("thud", -30.0, 1.0, SfxDirector.BUS_SFX, 0.3)
	var c := sfx.play_layer("tok", -30.0, 1.0, SfxDirector.BUS_SFX, 0.05)
	var d := sfx.play_layer("boom", -30.0, 1.0, SfxDirector.BUS_CRIT, 0.5)
	var buses: Array = []
	for v in [a, b, c, d]:
		buses.append(String(sfx.voice(v).bus) if v >= 0 else "-")
	_check("pan_bus", buses == ["SFX_PanL2", "SFX_PanR1", "SFX", "SFX_Crit"], str(buses))
	var pl := sfx.pan_for(p1.centre_of_mass())
	var pr := sfx.pan_for(p2.centre_of_mass())
	_check("pan_side", pl < pr and absf(pl) <= SfxDirector.PAN_WIDTH and absf(pr) <= SfxDirector.PAN_WIDTH, "P1 %.2f, P2 %.2f" % [pl, pr])
	await _wait_ms(1500.0)


func _test_voice_limit() -> void:
	var st0 := sfx.stolen
	var dv0 := int(sfx.dropped["voices"])
	var ok_n := 0
	for layer in SfxDirector.LAYER_ORDER:
		if sfx.play_layer(layer, -30.0, 1.0) >= 0:
			ok_n += 1
	var active := sfx.active_voices()
	var busy := 0
	for c in sfx.get_children():
		if c is AudioStreamPlayer and (c as AudioStreamPlayer).playing:
			busy += 1
	var pushed := sfx.stolen - st0 + int(sfx.dropped["voices"]) - dv0
	_check("voice_limit", active <= SfxDirector.VOICES and busy <= SfxDirector.VOICES and pushed >= SfxDirector.LAYER_ORDER.size() - SfxDirector.VOICES,
		"16 слоёв разом: принято %d, активно %d, играет %d, вытеснено %d, отброшено %d" % [ok_n, active, busy, sfx.stolen - st0, int(sfx.dropped["voices"]) - dv0])
	await _wait_ms(2000.0)
	var cap0 := int(sfx.dropped["layer_cap"])
	var got := 0
	for i in range(6):
		if sfx.play_layer("creak", -30.0, 1.0) >= 0:
			got += 1
		await _wait_ms(50.0)
	_check("layer_cap", got == SfxDirector.MAX_PER_LAYER and int(sfx.dropped["layer_cap"]) - cap0 == 2,
		"скрип ×6 через 50 мс (0.5 с каждый): сыграно %d, отброшено по лимиту слоя %d" % [got, int(sfx.dropped["layer_cap"]) - cap0])
	await _wait_ms(800.0)


func _test_muffle() -> void:
	sfx.set_muffle(true)
	await _frames(5)
	var hz_in := sfx.muffle_cutoff_hz()
	sfx.set_muffle(false)
	await _frames(8)
	var hz_out := sfx.muffle_cutoff_hz()
	_check("muffle", hz_in <= SfxDirector.MUFFLE_HZ + 1.0 and hz_out >= SfxDirector.OPEN_HZ - 1.0, "вкл %.0f Гц, выкл %.0f Гц" % [hz_in, hz_out])
	sfx.set_muffle(true)
	await _wait_ms(SfxDirector.MUFFLE_MAX_MS + 200.0)
	_check("muffle_watchdog", not sfx.is_muffled() and sfx.muffle_cutoff_hz() >= SfxDirector.OPEN_HZ - 1.0, "через %.0f мс: %.0f Гц" % [SfxDirector.MUFFLE_MAX_MS + 200.0, sfx.muffle_cutoff_hz()])


func _test_abort() -> void:
	sfx.force_crit_mode = "cine"
	var t0 := sfx.clock_ms()
	sfx.handle_hit_fx(_ctx("crit", p2, p1, 24.0))
	sfx.force_crit_mode = ""
	await _wait_ms(200.0)
	sfx.handle_phase(Match.Phase.COUNTDOWN)
	var pend := sfx.pending_count()
	var hz := sfx.muffle_cutoff_hz()
	var t_abort := sfx.clock_ms()
	await _wait_ms(700.0)
	var after := _since(t_abort + 1.0)
	_check("abort", pend == 0 and hz >= SfxDirector.OPEN_HZ - 1.0 and after.is_empty(),
		"очередь %d, срез %.0f Гц, звуки после abort %s (крит с %.0f)" % [pend, hz, str(_offsets(after, t0)), t0])
	await _wait_ms(300.0)


## Удар через настоящий сигнал Match (hit_fx у нового ядра, hit у старого).
func _test_signal_path() -> void:
	var t0 := sfx.clock_ms()
	if match_node.has_signal("hit_fx"):
		match_node.emit_signal("hit_fx", _ctx("light", p2, p1, 4.0))
	else:
		match_node.hit.emit(p2, p1, 4.0, "body", p2.centre_of_mass())
	var e := _since(t0)
	_check("signal_path", _count(e, "tok") == 1, "%s → %s" % ["hit_fx" if match_node.has_signal("hit_fx") else "hit", str(_layers(e))])
	await _wait_ms(300.0)


## Настоящий крит через ядро: Match.on_hit → HitTier (crit) → CritLaunch → hit_fx → HitFxDirector → CritCinematic.phase —
## звук идёт по фазам настоящего кинематографа (бум на cut_in, свист на cut_out), мир открыт после done.
func _test_real_crit() -> void:
	var cine := get_tree().get_first_node_in_group("crit_cinematic")
	if not match_node.has_signal("hit_fx") or cine == null or not cine.has_signal("phase"):
		report["info"]["real_crit"] = "пропуск: нет hit_fx / CritCinematic"
		return
	var st := {"tier": "", "phases": {}}
	var t0 := sfx.clock_ms()
	var on_fx := func(ctx: Dictionary) -> void:
		if String(st["tier"]) == "":
			st["tier"] = String(ctx.get("tier", ""))
	var on_phase := func(name_: String, _ms: float) -> void:
		(st["phases"] as Dictionary)[name_] = sfx.clock_ms() - t0
	match_node.connect("hit_fx", on_fx)
	cine.connect("phase", on_phase)
	p2.last_hit = {"part": "Torso", "normal": Vector3.LEFT, "dir": Vector3.RIGHT, "striker_name": "Hand_R", "attacker": p1}
	match_node.on_hit(p2, p1, 26.0, "body", p2.centre_of_mass(), 1, false, "", 8.0)
	await _wait_ms(1700.0)
	match_node.disconnect("hit_fx", on_fx)
	cine.disconnect("phase", on_phase)
	var ph: Dictionary = st["phases"]
	var e := _since(t0)
	var ok := String(st["tier"]) == "crit" and ph.has("cut_in") and ph.has("cut_out") and ph.has("done") \
		and _count(e, "inhale") == 1 and _count(e, "boom") == 1 and _at(e, t0, "inhale", 0.0) \
		and _at(e, t0, "boom", float(ph.get("cut_in", -999.0))) and _at(e, t0, "whistle", float(ph.get("cut_out", -999.0)))
	var rounded := {}
	for k in ph.keys():
		rounded[k] = roundi(float(ph[k]))
	report["info"]["real_crit"] = {"tier": st["tier"], "phases": rounded, "sounds": _offsets(e, t0)}
	_check("real_crit_sync", ok, "уровень %s, фазы %s, звуки %s" % [st["tier"], str(rounded), str(_offsets(e, t0))])
	_check("real_crit_restore", not sfx.is_muffled() and sfx.muffle_cutoff_hz() >= SfxDirector.OPEN_HZ - 1.0 and sfx.pending_count() == 0,
		"глушение %s, срез %.0f Гц, очередь %d, time_scale %.3f" % [sfx.is_muffled(), sfx.muffle_cutoff_hz(), sfx.pending_count(), Engine.time_scale])
	for b in p2.parts.values():
		(b as RigidBody3D).linear_velocity = Vector3.ZERO
	await _wait_ms(500.0)


func _test_fight() -> void:
	var t0 := sfx.clock_ms()
	p1.external_input = true
	p2.external_input = true
	var st := {"hits": 0, "kos": 0, "over": false}
	var tiers := {}
	match_node.hit.connect(func(_v: Doll, _a: Node, dmg: float, _k: String, _p: Vector3) -> void:
		if dmg > 0.0:
			st["hits"] = int(st["hits"]) + 1)
	match_node.ko.connect(func(_v: Doll, _a: Node, _r: Dictionary) -> void: st["kos"] = int(st["kos"]) + 1)
	match_node.match_over.connect(func(_w: Doll, _r: Dictionary) -> void: st["over"] = true)
	if match_node.has_signal("hit_fx"):
		match_node.connect("hit_fx", func(ctx: Dictionary) -> void:
			var k := String(ctx.get("tier", "?"))
			tiers[k] = int(tiers.get(k, 0)) + 1)
	fight = true
	var ft0 := match_node.fight_time
	var max_active := 0
	var guard := 0
	while match_node.fight_time - ft0 < fight_s and not bool(st["over"]) and guard < int(fight_s * 60.0 * 30.0):
		await _frames(1)
		guard += 1
		max_active = maxi(max_active, sfx.active_voices())
	fight = false
	p1.input_vec = Vector2.ZERO
	p2.input_vec = Vector2.ZERO
	await _wait_ms(2600.0)
	var hits := int(st["hits"])
	var kos := int(st["kos"])
	var over := bool(st["over"])
	var e := _since(t0)
	var by_layer := {}
	for x in e:
		by_layer[x["layer"]] = int(by_layer.get(x["layer"], 0)) + 1
	report["info"]["fight"] = {"fight_s": snappedf(match_node.fight_time - ft0, 0.01), "hits": hits, "kos": kos, "over": over,
		"tiers": tiers, "layers": by_layer, "max_active": max_active, "time_scale": Engine.time_scale}
	var hit_sounds := int(by_layer.get("tok", 0)) + int(by_layer.get("punch", 0))
	_check("fight_sounds", hits == 0 or hit_sounds >= 1, "ударов %d, звуков удара %d, слои %s" % [hits, hit_sounds, str(by_layer)])
	_check("fight_voices", max_active <= SfxDirector.VOICES, "макс. голосов %d" % max_active)
	if kos > 0:
		_check("fight_ko", int(by_layer.get("ko", 0)) >= 1 and int(by_layer.get("crowd_cheer", 0)) >= 1, "KO %d: слои %s" % [kos, str(by_layer)])
	if over:
		_check("fight_over_gong", int(by_layer.get("gong", 0)) >= 3, "гонгов %d" % int(by_layer.get("gong", 0)))
	_check("fight_time_scale", is_equal_approx(Engine.time_scale, 1.0) or match_node.phase == Match.Phase.OVER and Engine.time_scale >= 0.25,
		"Engine.time_scale %.3f, фаза %d" % [Engine.time_scale, match_node.phase])
	_check("fight_unmuffled", not sfx.is_muffled() and sfx.pending_count() == 0, "глушение %s, очередь %d" % [sfx.is_muffled(), sfx.pending_count()])


func _finish() -> void:
	report["info"]["godot"] = Engine.get_version_info()["string"]
	var js := JSON.stringify(report, "  ")
	print("=== SFX PROBE ===")
	var f := FileAccess.open("res://tests/sfx_probe_report.json", FileAccess.WRITE)
	if f:
		f.store_string(js)
		f.close()
	var failed := 0
	for c in report["checks"]:
		if not c["ok"]:
			failed += 1
	print("=== %s (%d/%d) ===" % ["OK" if report["ok"] else "FAIL", report["checks"].size() - failed, report["checks"].size()])
	get_tree().quit(0 if report["ok"] else 1)
