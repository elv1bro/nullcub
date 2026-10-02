## Витрина площадки как она есть (res://scenes/playground.tscn — Руины, playground_workshop.tscn — Мастерская или
## playground_void.tscn — Void, пустое поле без оружия: арена, P1/P2,
## оружие, DynamicCamera, Match + HUD):
##   tests/playground_wide.png    — t=wide_t, обе куклы стоят на спавнах, камера с полувысотой не меньше wide_h;
##   tests/playground_action.png  — P1 (external_input) толкают вправо-вверх с push_start на push с, кадр в полёте;
##                                  в режиме hit=1 — кадр через 0.12 с (реального времени) после первого удара: HUD, вспышка полосы HP,
##                                  диктор (BODY/HEAD BLOW!), щепки ImpactFx;
##   tests/playground_ko.png      — ko=1: P1 с hp 5 получает удар → KO: карточка KO поверх разлёта частей (0.45 с реального времени после KO);
##                                  под карточкой нет надписей диктора (проверка ko_announcer_clear);
##   tests/playground_results.png — ko=1: панель итогов (P1 WINS!, места, статистика, медали) после карточки.
## Печатает JSON и пишет tests/playground_report.json: куклы стоят, толкаемая улетела/долетела, ЦМ в кадре, кадр в границах арены,
## полувысота в [min, высота/2], взрыва нет, удары/надписи/HUD (hit), KO/карточка/итоги (ko), средний кадр (TIME_PROCESS),
## FPS и время кадра — в стадиях после кадра wide, через 0.3 с после PNG (vsync выключен; на macOS всё равно ≤ 60). Exit 0/1.
## Godot запускать нативно (arm64 → Metal): не через x86_64-обёртки вроде /usr/local/bin/timeout (Rosetta → MoltenVK).
## Запуск: godot --path . --resolution 1920x1080 --position 100,100 --always-on-top res://tests/playground_snapshot.tscn -- "hit=1,ko=1"
##   scene=ruins|workshop|void (площадка), push_start=0.8 push=1.0 wide_t=0.6 wide_h=6.5 shot=0.45 (кадр action через shot с после конца толчка)
##   end=3.0 (конец через end с после толчка) out=res://tests/ vsync=0|1 min_fps=55
##   hit=1 — режим удара: P2 (орех) ставится на 3.8 м правее P1 (в Руинах — на каменный мост) и толкается влево в P1;
##           dash=1 (по умолчанию) — с разбега ≥ DASH_FROM_M P2 делает рывок (как Shift, как match_probe): после отброса RM
##           (FEEL_TARGET §9, v6) простой толчок бьёт сначала кисть в кисть по 1–5 HP и надпись BODY/HEAD BLOW не гарантирована;
##           dash=0 — прежний толчок без рывка;
##   ko=1 — как hit, но у P1 (стоящей жертвы) hp 5: удар P2 даёт KO, снимаются карточка KO и итоги (подразумевает hit=1).
##   pit=1 — режим пропасти (Руины): P1 толкают влево к яме за левым помостом push с → падение = KO kind "self" (Match, карточка, итоги);
##            кадры ko/results как в ko=1, action — в полёте к яме.
##   debug=1 — печатать каждый кадр после первого удара/KO состояние диктора/карточки/итогов (реальное время).
##   pad=<м> / min_h=<м> — переопределить padding / min_half_height DynamicCamera после кадра wide (крупнее кадр action).
## Отсчёт Match (countdown_s) в тесте 0: толчок начинается сразу, FIGHT! уже объявлен к кадру wide.
extends Node3D

const SCENES := {"ruins": "res://scenes/playground.tscn", "workshop": "res://scenes/playground_workshop.tscn", "void": "res://scenes/playground_void.tscn"}
const HIT_SHOT_REAL_MS := 120
const KO_SHOT_REAL_MS := 450
const RESULTS_SHOT_REAL_MS := 350
const P2_HIT_OFFSET := Vector3(3.8, 0.0, 0.0)
const DASH_FROM_M := 2.0   # рывок P2 в режиме удара, если ЦМ дальше от P1 (как tests/match_probe.gd)

var cfg := {"push_start": 0.8, "push": 1.0, "wide_t": 0.6, "wide_h": 6.5, "shot": 0.45, "end": 3.0, "vsync": 0.0, "min_fps": 55.0, "hit": 0.0, "ko": 0.0, "pad": -1.0, "min_h": -1.0, "debug": 0.0, "pit": 0.0, "dash": 1.0}
var scene_id := "ruins"
var out_dir := "res://tests/"
var pg: Node3D
var p1: Doll
var p2: Doll
var cam: DynamicCamera
var match_node: Match
var hud: Hud
var t := 0.0
var stage := 0
var busy := false
var orig_min_h := 4.0
var start_x := 0.0
var p1_in_frame := true
var hit := false            # режим удара (cfg hit=1 или ko=1): толкают P2 в P1
var ko := false             # режим KO (cfg ko=1): P1 с hp 5, или pit=1 — падение P1 в пропасть
var pit := false            # режим пропасти (cfg pit=1)
var dashed := false        # рывок P2 в режиме удара уже сделан
var mover: Doll             # кого толкают: P1 (полёт вправо-вверх) или P2 (удар влево в P1)
var first_hit_ms := -1      # реальное время первого удара (Match.hit)
var announce_kinds: Array = []
var hp_synced := true       # HP панели HUD совпадает с hp куклы после каждого удара
var ko_fired := false
var ko_ms := -1
var ko_card_at_shot := false
var ko_stack_at_shot := -1   # надписей диктора на кадре KO (под карточкой их быть не должно — «призраки» v5)
var over_fired := false
var over_winner: Doll = null
var results_ms := -1
var results_at_shot := false
var frame_in_bounds := true
var hh_ok := true
var max_speed := 0.0
var frames := 0
var measure_from := INF   # замер кадра только в стадиях после wide, через 0.3 с после сохранения PNG (save_png ~0.5 с)
var sum_frame := 0.0
var sum_process := 0.0
var sum_physics := 0.0
var max_process := 0.0
var report := {"ok": true, "checks": [], "shots": []}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			if p[0] == "out":
				out_dir = p[1]
			elif p[0] == "scene":
				scene_id = p[1]
			elif cfg.has(p[0]):
				cfg[p[0]] = float(p[1])
	if cfg["vsync"] < 0.5:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	pit = cfg["pit"] >= 0.5
	ko = cfg["ko"] >= 0.5 and not pit
	hit = (cfg["hit"] >= 0.5 or ko) and not pit
	pg = load(SCENES.get(scene_id, SCENES["ruins"])).instantiate()
	add_child(pg)
	# окно always-on-top: случайные нажатия (R — restart, Enter/Space — REMATCH в фокусе) пересоздали бы кукол посреди теста
	pg.set_process_unhandled_input(false)
	get_viewport().gui_disable_input = true
	p1 = pg.get_node("P1")
	p2 = pg.get_node("P2")
	cam = pg.get_node("Camera")
	match_node = pg.get_node("Match")
	hud = pg.get_node("HUD")
	match_node.countdown_s = 0.0   # _late_ready (deferred) ещё не начал матч
	match_node.hit.connect(_on_hit)
	match_node.announce.connect(func(_text: String, _c: Color, kind: String) -> void: announce_kinds.append(kind))
	match_node.ko.connect(func(_v: Doll, _a: Node, _r: Dictionary) -> void:
		ko_fired = true
		ko_ms = Time.get_ticks_msec())
	match_node.match_over.connect(func(winner: Doll, _r: Dictionary) -> void:
		over_fired = true
		over_winner = winner)
	p1.external_input = true
	p2.external_input = true
	mover = p2 if hit else p1
	if hit:
		p2.position = p1.position + P2_HIT_OFFSET
	if pit:
		cfg["push"] = maxf(float(cfg["push"]), 2.5)
	orig_min_h = cam.min_half_height
	if cfg["pad"] > 0.0:
		cam.padding = cfg["pad"]
	if cfg["min_h"] > 0.0:
		orig_min_h = cfg["min_h"]
	cam.min_half_height = maxf(orig_min_h, float(cfg["wide_h"]))
	start_x = mover.centre_of_mass().x
	report["scene"] = scene_id
	report["resolution"] = var_to_str(get_viewport().get_visible_rect().size)
	report["window"] = var_to_str(DisplayServer.window_get_size())
	report["msaa_3d"] = get_viewport().msaa_3d
	report["screen_space_aa"] = get_viewport().screen_space_aa
	report["taa"] = get_viewport().use_taa


func _on_hit(victim: Doll, _attacker: Node, _damage: float, _kind: String, _position: Vector3) -> void:
	if first_hit_ms < 0:
		first_hit_ms = Time.get_ticks_msec()
	# HUD: панель жертвы получила тот же hp (hp_changed идёт из Doll.damaged до Match.on_hit)
	var panel: PlayerPanel = hud.panels.get(victim.player_index, null)
	if panel == null or not is_equal_approx(panel.hp_bar.hp, victim.hp):
		hp_synced = false


func _physics_process(delta: float) -> void:
	t += delta
	var ps: float = cfg["push_start"]
	var pushing := t >= ps and t < ps + float(cfg["push"])
	p1.input_vec = Vector2.ZERO
	p2.input_vec = Vector2.ZERO
	if is_instance_valid(mover) and mover.alive:
		var dir_v := Vector2(-1.0, 0.25) if hit else (Vector2(-1.0, 0.15) if pit else Vector2(1.0, 0.55))
		mover.input_vec = dir_v if pushing else Vector2.ZERO
		if hit and pushing and not dashed and cfg["dash"] >= 0.5 and is_instance_valid(p1) \
				and absf(mover.centre_of_mass().x - p1.centre_of_mass().x) > DASH_FROM_M and mover._time >= mover.dash_ready_at:
			mover.dash_until = mover._time + Tuning.DASH_DURATION_S
			mover.dash_ready_at = mover._time + Tuning.DASH_COOLDOWN_S
			dashed = true
	if ko and t >= ps and p1.alive and p1.hp > 5.0:
		p1.hp = 5.0
		match_node.hp_changed.emit(p1, p1.hp, Tuning.MAX_HP)
	for d in [p1, p2]:
		if d.alive:
			max_speed = maxf(max_speed, d.max_part_speed())
	if cam.half_height <= 0.0:
		return   # камера ещё не сделала первый кадр
	if stage >= 1 and mover.alive and (not hit or first_hit_ms < 0):   # в режиме удара — до удара (дальше жертву/бьющего уносит куда угодно)
		var c: Vector3 = mover.centre_of_mass()
		# ниже границ вида (яма, floor_inset) камера по правилам §7 не смотрит — там кадр не проверяем
		if c.y >= cam.view_bounds().position.y and not cam.frame_rect().grow(0.3).has_point(Vector2(c.x, c.y)):
			p1_in_frame = false
	var b := cam.view_bounds()
	var r := cam.frame_rect()
	# кадр внутри границ; если кадр больше границ по оси — он центрирован на них
	if r.size.x <= b.size.x + 0.05:
		if r.position.x < b.position.x - 0.05 or r.end.x > b.end.x + 0.05:
			frame_in_bounds = false
	elif absf(r.get_center().x - (b.position.x + b.end.x) * 0.5) > 0.05:
		frame_in_bounds = false
	if r.size.y <= b.size.y + 0.05:
		if r.position.y < b.position.y - 0.05 or r.end.y > b.end.y + 0.05:
			frame_in_bounds = false
	elif absf(r.get_center().y - (b.position.y + b.end.y) * 0.5) > 0.05:
		frame_in_bounds = false
	# верхняя граница — правило камеры max(высота арены / 2, min_half_height); тест сам поднимал min_half_height до wide_h,
	# и после кадра wide камера сходит с него плавно (zoom_in_tau), поэтому потолок здесь — wide_h на весь прогон
	if cam.half_height < orig_min_h - 0.01 or cam.half_height > maxf(cam.bounds().size.y * 0.5, maxf(orig_min_h, float(cfg["wide_h"]))) + 0.01:
		hh_ok = false


func _process(delta: float) -> void:
	if stage >= 1 and t >= measure_from and not busy:
		frames += 1
		sum_frame += delta / maxf(Engine.time_scale, 1e-3)   # реальное время кадра (hit stop / slow-mo масштабируют delta)
		var tp := Performance.get_monitor(Performance.TIME_PROCESS)
		sum_process += tp
		max_process = maxf(max_process, tp)
		sum_physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	var now := Time.get_ticks_msec()
	if cfg["debug"] >= 0.5 and (first_hit_ms >= 0 or ko_ms >= 0):
		var st: Node = hud.announcer.stack
		var l0: Control = st.get_child(0) as Control if st.get_child_count() > 0 else null
		print("dbg real+%d ms t=%.2f ts=%.2f stack=%d %s ko_card=%s a=%.2f rem=%.2f results=%s busy=%s" % [now - (first_hit_ms if first_hit_ms >= 0 else ko_ms), t, Engine.time_scale, st.get_child_count(),
			("'%s' s=%.2f a=%.2f pos=%s size=%s" % [String(l0.get_meta("text", "")), l0.scale.x, l0.modulate.a, l0.global_position, l0.size]) if l0 != null else "-",
			hud.ko_card.visible, hud.ko_card.modulate.a, hud.ko_card.remaining_s(), hud.results.visible, busy])
	if busy:
		return
	var ps: float = cfg["push_start"]
	if hud.results.visible and results_ms < 0:
		results_ms = now
	if stage == 0 and t >= float(cfg["wide_t"]):
		busy = true
		for i in [p1, p2]:
			var c: Vector3 = i.centre_of_mass()
			_check("%s_standing" % i.name, c.y - i.position.y, 0.6, "gt", "COM above root at wide shot (m)")
		await _capture("playground_wide.png")
		cam.min_half_height = orig_min_h
		stage = 1
		measure_from = t + 0.3
		busy = false
	elif stage == 1 and ((hit and first_hit_ms >= 0 and now >= first_hit_ms + HIT_SHOT_REAL_MS) or (not hit and t >= ps + float(cfg["push"]) + float(cfg["shot"])) or t >= ps + float(cfg["push"]) + float(cfg["end"])):
		busy = true
		await _capture("playground_action.png")
		stage = 2 if (ko or pit) else 4
		measure_from = t + 0.3
		busy = false
	elif stage == 2 and ((ko_fired and now >= ko_ms + KO_SHOT_REAL_MS) or t >= ps + float(cfg["push"]) + float(cfg["end"]) + 3.0):
		busy = true
		ko_card_at_shot = hud.ko_card.visible
		ko_stack_at_shot = hud.announcer.stack.get_child_count()
		await _capture("playground_ko.png")
		stage = 3
		measure_from = INF
		busy = false
	elif stage == 3 and ((results_ms >= 0 and now >= results_ms + RESULTS_SHOT_REAL_MS) or (ko_ms >= 0 and now >= ko_ms + 6000) or t >= ps + float(cfg["push"]) + float(cfg["end"]) + 8.0):
		busy = true
		results_at_shot = hud.results.visible
		await _capture("playground_results.png")
		stage = 4
		busy = false
		_finish()
	elif stage == 4 and t >= ps + float(cfg["push"]) + float(cfg["end"]):
		busy = true
		_finish()


## soft=true: информационная проверка (производительность зависит от машины) — печатает WARN, ok отчёта не меняет.
func _check(id: String, value: float, limit: float, cmp: String, detail: String, soft := false) -> void:
	var ok := (value < limit) if cmp == "lt" else (value > limit)
	report["checks"].append({"id": id, "value": snappedf(value, 0.001), "limit": limit, "cmp": cmp, "ok": ok, "soft": soft, "detail": detail})
	if not ok:
		if soft:
			print("WARN %s: %s %s %s (%s)" % [id, snappedf(value, 0.001), cmp, limit, detail])
		else:
			report["ok"] = false


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(name)
	var err := img.save_png(path)
	report["shots"].append(path)
	print("saved ", path, " (", err, ") at t=", snappedf(t, 0.01), " half_height=", snappedf(cam.half_height, 0.01))
	# save_png блокирует кадр (~0.5–1 с на 1080p): пропускаем длинный кадр, чтобы он не съел таймеры/твины HUD
	await get_tree().process_frame
	await get_tree().process_frame


func _has_hit_announce() -> bool:
	for k in announce_kinds:
		if k == "head" or k == "body" or k == "double":
			return true
	return false


func _finish() -> void:
	var c: Vector3 = mover.centre_of_mass()
	report["hits"] = int(pg.get("hits"))
	report["announces"] = announce_kinds
	if hit:
		_check("p2_hit_dx", start_x - c.x, 1.0, "gt", "P2 COM moved left towards P1 (m)")
		_check("hits", float(pg.get("hits")), 0.5, "gt", "Match.hit fired (DollCombat registered a doll-vs-doll hit)")
		_check("announce_fight", 1.0 if announce_kinds.has("fight") else 0.0, 0.5, "gt", "FIGHT! announced")
		_check("announce_hit", 1.0 if _has_hit_announce() else 0.0, 0.5, "gt", "HEAD/BODY/DOUBLE BLOW! announced (damage >= ANNOUNCE_MIN_DAMAGE)")
		_check("hud_panels", float(hud.panels.size()), 1.5, "gt", "HUD has a panel per player")
		_check("hud_hp_synced", 1.0 if hp_synced else 0.0, 0.5, "gt", "HUD panel hp == doll hp after every hit")
	elif pit:
		_check("p1_flew_dx", start_x - c.x, 2.0, "gt", "P1 COM moved left towards the pit (m)")
	else:
		_check("p1_flew_dx", c.x - start_x, 2.0, "gt", "P1 COM dx after push (m)")
	if pit:
		_check("ko_fired", 1.0 if ko_fired else 0.0, 0.5, "gt", "Match.ko emitted (P1 fell into the pit: kind self)")
		_check("ko_kind_self", 1.0 if String(p1.last_ko_record.get("kind", "")) == "self" else 0.0, 0.5, "gt", "KoRecord.kind == self")
		_check("ko_broken", 1.0 if (ko_fired and p1.is_broken()) else 0.0, 0.5, "gt", "fallen doll broke apart")
		_check("ko_no_respawn", 1.0 if p1.is_broken() and is_instance_valid(p1) and p1.is_inside_tree() else 0.0, 0.5, "gt", "no respawn during the match (old P1 still in tree, broken)")
		_check("ko_card_at_shot", 1.0 if ko_card_at_shot else 0.0, 0.5, "gt", "KO card visible on the KO shot")
		_check("announce_ko", 1.0 if announce_kinds.has("ko") else 0.0, 0.5, "gt", "KO! announced")
		_check("match_over", 1.0 if over_fired else 0.0, 0.5, "gt", "match_over emitted")
		_check("winner_p2", 1.0 if over_winner == p2 else 0.0, 0.5, "gt", "winner is P2")
		_check("results_at_shot", 1.0 if results_at_shot else 0.0, 0.5, "gt", "results panel visible on the results shot")
	if ko:
		_check("ko_fired", 1.0 if ko_fired else 0.0, 0.5, "gt", "Match.ko emitted (P1 at hp 5 was hit)")
		_check("ko_broken", 1.0 if (ko_fired and p1.is_broken() and p1.joints.is_empty()) else 0.0, 0.5, "gt", "victim broke apart (joints freed)")
		_check("ko_card_at_shot", 1.0 if ko_card_at_shot else 0.0, 0.5, "gt", "KO card visible on the KO shot")
		_check("ko_announcer_clear", float(ko_stack_at_shot), 0.5, "lt", "no announcer labels under the KO card (the card itself says KO!)")
		_check("announce_ko", 1.0 if announce_kinds.has("ko") else 0.0, 0.5, "gt", "KO! announced")
		_check("match_over", 1.0 if over_fired else 0.0, 0.5, "gt", "match_over emitted")
		_check("winner_p2", 1.0 if over_winner == p2 else 0.0, 0.5, "gt", "winner is P2 (the striker)")
		_check("results_at_shot", 1.0 if results_at_shot else 0.0, 0.5, "gt", "results panel visible on the results shot")
		_check("phase_over", 1.0 if match_node.phase == Match.Phase.OVER else 0.0, 0.5, "gt", "Match phase OVER at the end")
	_check("p1_in_frame", 1.0 if p1_in_frame else 0.0, 0.5, "gt", "pushed doll COM inside camera frame (+0.3 m) for the whole flight")
	_check("frame_in_bounds", 1.0 if frame_in_bounds else 0.0, 0.5, "gt", "camera frame never leaves arena bounds")
	_check("half_height_range", 1.0 if hh_ok else 0.0, 0.5, "gt", "half_height within [min_half_height, max(arena_h/2, wide_h)]")
	_check("no_explosion", max_speed, 20.0, "lt", "max part speed of alive dolls (m/s)")
	var n := maxf(float(frames), 1.0)
	var fps := float(frames) / maxf(sum_frame, 0.001)
	report["perf"] = {
		"frames": frames,
		"window_s": snappedf(sum_frame, 0.01),
		"avg_frame_ms": snappedf(sum_frame / n * 1000.0, 0.01),
		"avg_process_ms": snappedf(sum_process / n * 1000.0, 0.01),
		"max_process_ms": snappedf(max_process * 1000.0, 0.01),
		"avg_physics_ms": snappedf(sum_physics / n * 1000.0, 0.01),
		"arch": Engine.get_architecture_name(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"fps": snappedf(fps, 0.1),
		"vsync_disabled": cfg["vsync"] < 0.5,
	}
	_check("fps", fps, float(cfg["min_fps"]), "gt", "average FPS in the measured windows (soft: machine-dependent)", true)
	_check("frame_time_ms", sum_frame / n * 1000.0, 16.7, "lt", "average frame time (ms; TIME_PROCESS is in perf; soft)", true)
	report["mover"] = [mover.name, snappedf(c.x, 0.01), snappedf(c.y, 0.01)]
	report["camera"] = {"half_height": snappedf(cam.half_height, 0.01), "pos": var_to_str(cam.global_position)}
	report["hp"] = {"p1": snappedf(p1.hp, 0.1), "p2": snappedf(p2.hp, 0.1)}
	var js := JSON.stringify(report, "  ")
	print("=== PLAYGROUND SNAPSHOT ===")
	print(js)
	var f := FileAccess.open("res://tests/playground_report.json", FileAccess.WRITE)
	if f:
		f.store_string(js)
		f.close()
	print("=== %s ===" % ("OK" if report["ok"] else "FAIL"))
	get_tree().quit(0 if report["ok"] else 1)
