## Проба «мира звука» (docs/plan-demo/AUDIO.md §6), headless (аудио-драйвер Dummy — звука нет, логика та же): настоящая площадка
## (scene=scrap|void|ruins|workshop, по умолчанию scrap) с Match, у которого дети SfxDirector, CrowdDirector, ImpactAudio,
## ArenaAmbience; GameAudio — autoload. Удары SfxDirector проверяет tests/sfx_probe.
## Проверки (checks[].id):
##   buses — Music / Crowd / Ambience (LowPass выкл.), Crowd — Reverb, SFX — Reverb, UI; world_nodes — по одному CrowdDirector,
##   ImpactAudio, ArenaAmbience под Match; arena — пресет арены угадан, петли фона играют, реверберация и пол — из пресета;
##   music_context — бой включил музыку «fight», трек играет (если музыка не выключена игроком); crowd_loops — 3 петли толпы;
##   music_toggle / crowd_toggle — шины Music / Crowd глушатся и возвращаются (настройки не пишутся);
##   world_muffle — глушение крита SfxDirector доходит до Crowd / Ambience / Music и снимается;
##   crowd_heavy — тяжёлые удары поднимают возбуждение; crowd_ko — KO: рёв ~150 мс и аплодисменты ~1.6 с;
##   crowd_crit — фазы крита: стоп-кадр приглушает толпу, выход из крупного плана — рёв и возбуждение 1;
##   crowd_idle — без ударов IDLE_BOO_S — «бууу»; loop_mix — веса петель: покой → гул, пик → рёв;
##   doll_audio — у кукол DollAudio; wind — быстрый полёт поднимает ветер (громче −20 дБ, играет), стоп — ветер стихает и молчит;
##   dash / flip — рывок и переворот звучат; impact_wood / impact_metal — упавший ящик стучит своим материалом;
##   impact_rest — лежащее тело не стучит; fight_* — бой ботов fight_s секунд: удары и стук есть, стуков ≤ MAX_PER_SEC в секунду,
##   голосов ≤ 24, толпа реагировала (реакция или уровень > 0.4).
## Запуск: godot --headless --path . --fixed-fps 60 res://tests/audio_probe.tscn -- "scene=scrap,fight_s=20"
## Отчёт tests/audio_probe_report.json (out=<абс. путь> — свой), exit 0/1.
extends Node3D

const SCENES := {"scrap": "res://scenes/playground_scrap.tscn", "void": "res://scenes/playground_void.tscn",
	"ruins": "res://scenes/playground.tscn", "workshop": "res://scenes/playground_workshop.tscn"}

var scene := "scrap"
var fight_s := 20.0
var out_path := "res://tests/audio_probe_report.json"
var pg: Node3D
var match_node: Match
var sfx: SfxDirector
var crowd: CrowdDirector
var impact: ImpactAudio
var amb: ArenaAmbience
var ga: Node
var p1: Doll
var p2: Doll
var fight := false
var hold_vel: Dictionary = {}
var report := {"ok": true, "checks": [], "info": {}}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			match p[0]:
				"scene":
					scene = p[1]
				"fight_s":
					fight_s = float(p[1])
				"out":
					out_path = p[1]
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


func _physics_process(_dt: float) -> void:
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
	d.input_vec = Vector2(sgn, clampf(dy / 1.5, -1.0, 1.0) if absf(dy) > 0.8 else 0.0)
	if absf(dx) > 2.0:
		d.request_dash()
	elif randf() < 0.01:
		d.request_flip()


func _reactions_since(t0: float) -> Array:
	var out: Array = []
	for r in crowd.reactions:
		if float(r["ms"]) >= t0 - 0.05:
			out.append(r)
	return out


func _has_reaction(rs: Array, layer: String, t0: float, at_ms: float, tol_ms: float) -> bool:
	for r in rs:
		if r["layer"] == layer and absf(float(r["ms"]) - t0 - at_ms) <= tol_ms:
			return true
	return false


func _ctx(tier: String, victim: Doll, attacker: Doll, damage: float) -> Dictionary:
	return {"victim": victim, "attacker": attacker, "damage": damage, "kind": "body", "part": "Torso", "part_base": "Torso",
		"position": victim.centre_of_mass(), "normal": Vector3.LEFT, "dir": Vector3.RIGHT, "tier": tier, "score": damage,
		"is_ko": tier.begins_with("ko"), "hp_after": victim.hp, "speed": 6.0, "combo": 1, "double_blow": false, "dash": false}


func _run() -> void:
	report["info"]["scene"] = scene
	ga = get_node_or_null("/root/GameAudio")
	var music_on0: bool = ga.music_on if ga != null else true
	var crowd_on0: bool = ga.crowd_on if ga != null else true
	pg = (load(String(SCENES.get(scene, SCENES["scrap"]))) as PackedScene).instantiate() as Node3D
	add_child(pg)
	match_node = pg.get_node("Match") as Match
	p1 = pg.get_node("P1") as Doll
	p2 = pg.get_node("P2") as Doll
	await _frames(6)
	var n := {"sfx": 0, "crowd": 0, "impact": 0, "amb": 0}
	for c in match_node.get_children():
		if c is SfxDirector:
			sfx = c
			n["sfx"] += 1
		elif c is CrowdDirector:
			crowd = c
			n["crowd"] += 1
		elif c is ImpactAudio:
			impact = c
			n["impact"] += 1
		elif c is ArenaAmbience:
			amb = c
			n["amb"] += 1
	_check("world_nodes", n.values() == [1, 1, 1, 1] and ga != null, "под Match %s, GameAudio %s" % [str(n), ga != null])
	if sfx == null or crowd == null or impact == null or amb == null or ga == null:
		_finish()
		return
	_check_buses()
	_check_arena()
	_check("crowd_loops", crowd.loops_playing() == 3, "петель играет %d, громкости %s" % [crowd.loops_playing(), str(crowd.loop_volumes())])
	var guard := 0
	while match_node.phase != Match.Phase.FIGHT and guard < 600:
		await _frames(1)
		guard += 1
	await _wait_ms(300.0)
	_check("music_context", ga.music_context == "fight" and (ga.is_music_playing() or not ga.music_on),
		"контекст «%s», трек %s, играет %s, музыка вкл %s" % [ga.music_context, ga.music_track, ga.is_music_playing(), ga.music_on])
	await _test_toggles()
	await _test_world_muffle()
	await _test_crowd()
	await _test_doll_audio()
	await _test_impacts()
	await _test_fight()
	ga.set_music_on(music_on0, false)
	ga.set_crowd_on(crowd_on0, false)
	report["info"]["impacts_total"] = impact.impacts.size()
	report["info"]["reactions"] = crowd.reactions.size()
	report["info"]["sfx_dropped"] = sfx.dropped
	_finish()


func _check_buses() -> void:
	var errs: Array = []
	for b in ["Music", "Crowd", "Ambience"]:
		var i := AudioServer.get_bus_index(b)
		if i < 0 or AudioServer.get_bus_effect_count(i) == 0 or not AudioServer.get_bus_effect(i, 0) is AudioEffectLowPassFilter:
			errs.append("%s: нет LowPass" % b)
		elif AudioServer.get_bus_send(i) != &"Master":
			errs.append("%s → %s" % [b, AudioServer.get_bus_send(i)])
	if SfxDirector.GameAudioScript.bus_effect("Crowd", "AudioEffectReverb") == null:
		errs.append("Crowd: нет Reverb")
	if SfxDirector.GameAudioScript.bus_effect("SFX", "AudioEffectReverb") == null:
		errs.append("SFX: нет Reverb")
	if AudioServer.get_bus_index("UI") < 0:
		errs.append("нет UI")
	_check("buses", errs.is_empty(), str(errs))


func _check_arena() -> void:
	var want := {"scrap": "scrap", "void": "void", "ruins": "ruins", "workshop": "workshop"}
	var p: Dictionary = ArenaAmbience.PRESETS.get(amb.arena, {})
	var ok: bool = amb.arena == String(want.get(scene, "")) and amb.loops_playing() == (p.get("loops", []) as Array).size() \
		and ga.room == String(p.get("room", "")) and SoundMaterial.ground == String(p.get("ground", ""))
	_check("arena", ok, "арена %s, петель %d, комната %s, пол %s" % [amb.arena, amb.loops_playing(), ga.room, SoundMaterial.ground])


func _bus_muted(b: String) -> bool:
	return AudioServer.is_bus_mute(AudioServer.get_bus_index(b))


func _test_toggles() -> void:
	ga.set_music_on(false, false)
	var m_off := _bus_muted("Music")
	ga.set_music_on(true, false)
	await _frames(2)
	var m_on: bool = not _bus_muted("Music") and ga.is_music_playing()
	_check("music_toggle", m_off and m_on, "выкл → шина заглушена %s; вкл → открыта и играет %s" % [m_off, m_on])
	ga.set_crowd_on(false, false)
	var c_off := _bus_muted("Crowd")
	ga.set_crowd_on(true, false)
	_check("crowd_toggle", c_off and not _bus_muted("Crowd"), "выкл → заглушена %s; вкл → открыта %s" % [c_off, not _bus_muted("Crowd")])


func _test_world_muffle() -> void:
	sfx.set_muffle(true)
	await _frames(6)
	var hz_in := [ga.bus_cutoff_hz("Crowd"), ga.bus_cutoff_hz("Ambience"), ga.bus_cutoff_hz("Music")]
	sfx.set_muffle(false)
	await _frames(10)
	var hz_out := [ga.bus_cutoff_hz("Crowd"), ga.bus_cutoff_hz("Ambience"), ga.bus_cutoff_hz("Music")]
	var ok := float(hz_in[0]) <= 1000.0 and float(hz_in[1]) <= 1000.0 and float(hz_in[2]) <= 1000.0 \
		and float(hz_out[0]) >= 19999.0 and float(hz_out[1]) >= 19999.0 and float(hz_out[2]) > 2000.0
	_check("world_muffle", ok, "крит: Crowd/Ambience/Music %s Гц; после: %s Гц" % [str(hz_in), str(hz_out)])


func _test_crowd() -> void:
	# тяжёлые удары
	var e0 := crowd.excitement
	for i in 3:
		match_node.emit_signal("hit_fx", _ctx("heavy", p2, p1, 14.0))
		await _wait_ms(120.0)
	_check("crowd_heavy", crowd.excitement >= e0 + 0.25, "возбуждение %.2f → %.2f" % [e0, crowd.excitement])
	await _wait_ms(1200.0)
	# KO
	var t0 := sfx.clock_ms()
	match_node.ko.emit(p2, p1, {"position": p2.centre_of_mass()})
	await _wait_ms(1900.0)
	var rs := _reactions_since(t0)
	_check("crowd_ko", _has_reaction(rs, "crowd_roar", t0, 150.0, 40.0) and _has_reaction(rs, "crowd_applause", t0, 1600.0, 40.0)
		and crowd.excitement > 0.7, "реакции %s, возбуждение %.2f" % [str(rs), crowd.excitement])
	await _wait_ms(500.0)
	# крит: стоп-кадр приглушает, выход — рёв
	var vols0 := crowd.loop_volumes()
	t0 = sfx.clock_ms()
	sfx.crit_phase.emit("freeze", 0.0)
	await _wait_ms(300.0)
	var vols_duck := crowd.loop_volumes()
	sfx.crit_phase.emit("caption", 300.0)
	await _wait_ms(200.0)
	sfx.crit_phase.emit("cut_out", 500.0)
	await _wait_ms(150.0)
	sfx.crit_phase.emit("done", 1300.0)
	rs = _reactions_since(t0)
	var ducked := float(vols_duck[1]) < float(vols0[1]) - 6.0 or float(vols_duck[2]) < float(vols0[2]) - 6.0
	var ok := ducked and _has_reaction(rs, "crowd_gasp", t0, 300.0, 40.0) and _has_reaction(rs, "crowd_roar", t0, 500.0, 40.0) \
		and crowd.excitement >= 0.95
	_check("crowd_crit", ok, "петли %s → %s; реакции %s; возбуждение %.2f" % [str(vols0), str(vols_duck), str(rs), crowd.excitement])
	await _wait_ms(400.0)
	# скука: никто не бьёт
	t0 = sfx.clock_ms()
	await _wait_ms(CrowdDirector.IDLE_BOO_S * 1000.0 + 600.0)
	rs = _reactions_since(t0)
	var boo := false
	for r in rs:
		boo = boo or r["layer"] == "crowd_boo"
	_check("crowd_idle", boo, "за %.1f с без ударов: %s, уровень %.2f" % [CrowdDirector.IDLE_BOO_S + 0.6, str(rs), crowd.level])
	var w0 := CrowdDirector.loop_weights(0.0)
	var w1 := CrowdDirector.loop_weights(1.0)
	var wm := CrowdDirector.loop_weights(0.5)
	_check("loop_mix", w0[0] > 0.99 and w0[2] < 0.01 and w1[2] > 0.99 and w1[0] < 0.01 and wm[1] > 0.99,
		"веса 0: %s, 0.5: %s, 1: %s" % [str(w0), str(wm), str(w1)])


func _test_doll_audio() -> void:
	var da1 := p1.get_node_or_null("DollAudio") as DollAudio
	var da2 := p2.get_node_or_null("DollAudio") as DollAudio
	_check("doll_audio", da1 != null and da2 != null and da1.wind != null, "P1 %s, P2 %s" % [da1 != null, da2 != null])
	if da1 == null:
		return
	hold_vel[p1] = Vector3(11.0, 2.0, 0.0)
	await _wait_ms(400.0)
	var db_fast := da1.wind_db
	var playing_fast := da1.wind.playing
	hold_vel.clear()
	for b in p1.parts.values():
		(b as RigidBody3D).linear_velocity = Vector3.ZERO
	await _wait_ms(2500.0)
	var db_rest := da1.wind_db
	_check("wind", db_fast > -20.0 and playing_fast and db_rest < -60.0 and not da1.wind.playing,
		"полёт 11 м/с: %.1f дБ, играет %s; покой: %.1f дБ, играет %s" % [db_fast, playing_fast, db_rest, da1.wind.playing])
	p1.external_input = true
	var ev0 := da1.events.size()
	p1.dash_ready_at = 0.0
	p1.request_dash()
	await _wait_ms(120.0)
	p1.request_flip()
	await _wait_ms(120.0)
	p1.input_vec = Vector2.ZERO
	var evs: Array = []
	for i in range(ev0, da1.events.size()):
		evs.append(da1.events[i]["ev"])
	_check("dash", evs.has("dash"), "события %s" % str(evs))
	_check("flip", evs.has("flip"), "события %s" % str(evs))
	await _wait_ms(600.0)


## Ящик 0.4 м с метой материала падает с 5 м на пол арены (или хлам): ImpactAudio — стук его материала; потом лежит — тишина.
func _drop_box(mat: String, x: float) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.name = "ProbeBox_" + mat
	b.mass = 3.0
	b.set_meta("material", mat)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.4, 0.4, 0.4)
	cs.shape = bs
	b.add_child(cs)
	b.axis_lock_linear_z = true
	pg.add_child(b)
	var floor_y := 0.0
	var bb: Variant = amb.get("_bounds")
	if bb is AABB:
		floor_y = (bb as AABB).position.y
	b.global_position = Vector3(x, maxf(floor_y, 0.0) + 5.0, 0.0)
	return b


## Следит за падением: старт / низ по Y и наибольшая скорость — в деталь проверки.
func _watch_fall(b: RigidBody3D, ms: float) -> String:
	var y0 := b.global_position.y
	var y_min := y0
	var v_max := 0.0
	var until := sfx.clock_ms() + ms
	while sfx.clock_ms() < until:
		await get_tree().physics_frame
		y_min = minf(y_min, b.global_position.y)
		v_max = maxf(v_max, b.linear_velocity.length())
	return "y %.2f → %.2f, макс. %.1f м/с" % [y0, y_min, v_max]


func _impacts_of(mat: String, t0: float) -> Array:
	var out: Array = []
	for e in impact.impacts:
		if float(e["ms"]) >= t0 - 0.05 and e["mat"] == mat:
			out.append(e)
	return out


func _test_impacts() -> void:
	var t0 := sfx.clock_ms()
	var bw := _drop_box("wood", -1.0)
	var fw := await _watch_fall(bw, 2600.0)
	var wood := _impacts_of("wood", t0)
	_check("impact_wood", wood.size() >= 1 and String(wood[0]["layer"]).begins_with("wood"), "стуки %s; падение %s" % [str(wood), fw])
	t0 = sfx.clock_ms()
	var bm := _drop_box("iron", 1.0)
	var fm := await _watch_fall(bm, 2600.0)
	var metal := _impacts_of("metal", t0)
	_check("impact_metal", metal.size() >= 1 and String(metal[0]["layer"]).begins_with("metal"), "стуки %s; падение %s" % [str(metal), fm])
	# лежат — тишина (2.5 с на то, чтобы ящики докатились и легли на грань)
	await _wait_ms(2500.0)
	t0 = sfx.clock_ms()
	var n0 := impact.impacts.size()
	await _wait_ms(2000.0)
	var rest: Array = []
	for i in range(n0, impact.impacts.size()):
		var e: Dictionary = impact.impacts[i]
		if String(e.get("body", "")).begins_with("ProbeBox"):
			rest.append(e)
	var still := bw.linear_velocity.length() < 0.2 and bm.linear_velocity.length() < 0.2
	_check("impact_rest", rest.is_empty() or not still, "за 2 с покоя стуков %d (ящики стоят: %s)" % [rest.size(), still])
	bw.queue_free()
	bm.queue_free()


func _test_fight() -> void:
	p1.external_input = true
	p2.external_input = true
	var st := {"hits": 0}
	match_node.hit.connect(func(_v: Doll, _a: Node, dmg: float, _k: String, _p: Vector3) -> void:
		if dmg > 0.0:
			st["hits"] = int(st["hits"]) + 1)
	var t0 := sfx.clock_ms()
	var imp0 := impact.impacts.size()
	var r0 := crowd.reactions.size()
	fight = true
	var ft0 := match_node.fight_time
	var max_active := 0
	var max_level := 0.0
	var max_rate := 0
	var guard := 0
	while match_node.fight_time - ft0 < fight_s and match_node.phase != Match.Phase.OVER and guard < int(fight_s * 60.0 * 20.0):
		await _frames(1)
		guard += 1
		max_active = maxi(max_active, sfx.active_voices())
		max_level = maxf(max_level, crowd.level)
		var now := sfx.clock_ms()
		var n := 0
		for i in range(impact.impacts.size() - 1, -1, -1):
			if now - float(impact.impacts[i]["ms"]) > 1000.0:
				break
			n += 1
		max_rate = maxi(max_rate, n)
	fight = false
	p1.input_vec = Vector2.ZERO
	p2.input_vec = Vector2.ZERO
	var dur := (sfx.clock_ms() - t0) / 1000.0
	var imps := impact.impacts.size() - imp0
	var by_mat := {}
	var dvs: Array = []
	for i in range(imp0, impact.impacts.size()):
		var k := String(impact.impacts[i]["layer"])
		by_mat[k] = int(by_mat.get(k, 0)) + 1
		dvs.append(float(impact.impacts[i]["dv"]))
	dvs.sort()
	if not dvs.is_empty():
		report["info"]["impact_dv"] = {"p10": dvs[int(dvs.size() * 0.1)], "p50": dvs[int(dvs.size() * 0.5)], "p90": dvs[int(dvs.size() * 0.9)]}
	report["info"]["fight"] = {"s": snappedf(dur, 0.1), "hits": st["hits"], "impacts": imps, "impact_layers": by_mat,
		"max_impacts_per_s": max_rate, "max_voices": max_active, "max_crowd_level": snappedf(max_level, 0.01),
		"reactions": crowd.reactions.size() - r0}
	_check("fight_impacts", imps >= 1 and max_rate <= ImpactAudio.MAX_PER_SEC, "стуков %d за %.1f с (макс. %d/с), слои %s"
		% [imps, dur, max_rate, str(by_mat)])
	_check("fight_voices", max_active <= SfxDirector.VOICES, "макс. голосов %d" % max_active)
	# толпа заводится от больших моментов (heavy, крит, KO); бой из одних лёгких ударов — хотя бы реакция или подъём уровня
	_check("fight_crowd", int(st["hits"]) == 0 or crowd.reactions.size() - r0 >= 1 or max_level > 0.4,
		"ударов %d, макс. уровень толпы %.2f, реакций %d" % [st["hits"], max_level, crowd.reactions.size() - r0])


func _finish() -> void:
	report["info"]["godot"] = Engine.get_version_info()["string"]
	var js := JSON.stringify(report, "  ")
	print("=== AUDIO PROBE ===")
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f:
		f.store_string(js)
		f.close()
	var failed := 0
	for c in report["checks"]:
		if not c["ok"]:
			failed += 1
	print("=== %s (%d/%d) ===" % ["OK" if report["ok"] else "FAIL", report["checks"].size() - failed, report["checks"].size()])
	get_tree().quit(0 if report["ok"] else 1)
