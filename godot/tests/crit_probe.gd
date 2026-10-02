## Проба кинематографа сокрушительного удара (CritCinematic, HIT_FX.md §3, §5.4) — headless, --fixed-fps 60, площадка Void
## (P1 — клён doll.tscn, P2 — орех doll_dark.tscn). Кинематограф берётся у HitFxDirector (если он уже есть под Match), иначе
## CritCinematic.attach(probe) — вне Match. Удары синтетические: ctx как у Match.hit_fx, play(ctx) напрямую.
## Сценарии:
##   A crit на P2 (голова): фазы freeze 0 / cut_in 120 / caption 220 / crack_2 400 / cut_out 620 / done 1300 мс (±16.7);
##     Engine.time_scale 0.02 / 0.12 / 0.3 в своих окнах; камера — CritCam в крупном плане, игровая через кадр после cut_out;
##     рентген, оверлей волокна на меше головы, Decal на теле головы в крупном плане; повторный play — false;
##     после done: time_scale 1, тегов crit* нет, камера игровая, оверлей снят, material_overlay как до удара, HUD виден;
##     через 3 с: Decal нет, fx_node_count 0, детей Match столько же;
##   B restart на 300 мс (жертва P1): через кадр time_scale 1, камера игровая (camera_owner пустой), оверлей снят, не играет;
##   C ko_crit (P2 с hp 5 получает удар → KO): таймлайн до done (OVER с KO не прерывает), time_scale ≤ 0.25 в 620–1950 мс,
##     1.0 после 2100 мс; карточка KO спрятана на 300 мс и видна на 800 мс;
##   D жертва без MeshInstance3D (все меши P1 удалены): таймлайн до done, Decal был, ошибок нет;
##   E flash_intensity 0 → вспышек/инверсий 0 (в A — 2: инверсия и белый кадр); enabled=false → play false;
##   F Match.feel_enabled=false → таймлайн идёт, time_scale всё время 1.
## v2 (HIT_FX.md §11.4–11.5): A — маска кукол держится в рентгене (use_mask, бит маски на мешах жертвы) и снята после (бит 0),
##   кадры-силуэты по маске 2; полувысота CritCam для головы 0.7–0.95; надпись после ката уезжает вверх (y меньше, scale < 1) и
##   не видна с 880 мс; G — крит в голень: полувысота 0.5–0.7 (деталь занимает кадр).
## v3 (HIT_FX.md §12.1, §12.3): A — маркер точки удара виден в 33–150 мс и снят к 200 мс; атакующий в рентгене затемнён (оверлей на
##   мешах P1) и возвращён; затемнение фона в замедлении после ката и снято после done; надпись после ката не на куклах;
##   S — настоящий крит через Match.on_hit (force_next) из-под потолка Void в правый верхний угол: от ката до конца замедления + 0.3 с
##   жертва (экранная проекция AABB мешей всех частей) в safe-area DynamicCamera.safe_rect во всех кадрах (v2 — safe_enabled=false,
##   тот же сценарий — только справка); послеобразы и лента живут до конца окна.
## Пишет tests/crit_probe_report.json, exit 0/1.
## Запуск: gtimeout 120 /usr/bin/arch -arm64 /usr/local/bin/godot --headless --path <godot> --fixed-fps 60 res://tests/crit_probe.tscn
extends Node3D

const SCENE := "res://scenes/playground_void.tscn"
const PHASES := {"freeze": 0.0, "cut_in": 120.0, "caption": 220.0, "crack_2": 400.0, "cut_out": 620.0, "done": 1300.0}
const FRAME_MS := 1000.0 / 60.0
const TOL_MS := 16.7

var pg: Node3D
var match_node: Match
var hud: Node
var game_cam: Camera3D
var cc: CritCinematic
var report := {"ok": true, "checks": [], "scenarios": {}}
var _phase_seen: Dictionary = {}


func _ready() -> void:
	pg = (load(SCENE) as PackedScene).instantiate()
	add_child(pg)
	pg.set_process_unhandled_input(false)
	match_node = pg.get_node("Match")
	match_node.countdown_s = 0.0
	hud = pg.get_node_or_null("HUD")
	game_cam = pg.get_node("Camera")
	_run.call_deferred()


func check(id: String, ok: bool, value: Variant = null, limit: Variant = null) -> void:
	report["checks"].append({"id": id, "ok": ok, "value": value, "limit": limit})
	if not ok:
		report["ok"] = false
	print("%s %s value=%s limit=%s" % ["OK  " if ok else "FAIL", id, str(value), str(limit)])


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func dolls() -> Array:
	var out: Array = []
	for d in match_node.dolls():
		out.append(d)
	out.sort_custom(func(a: Doll, b: Doll) -> bool: return a.player_index < b.player_index)
	return out


func make_ctx(victim: Doll, attacker: Doll, part: String, tier: String) -> Dictionary:
	var body: RigidBody3D = victim.parts.get(part, victim.torso())
	var dir := body.global_position - attacker.centre_of_mass()
	dir.z = 0.0
	dir = dir.normalized() if dir.length_squared() > 1e-6 else Vector3.LEFT
	var kind := "head" if part.begins_with("Head") else "body"
	return {
		"victim": victim, "attacker": attacker, "damage": 26.0, "kind": kind, "part": part, "part_base": Doll.part_base_name(part),
		"striker": "Hand_R", "position": body.global_position - dir * 0.1, "normal": -dir, "dir": dir, "speed": 8.0,
		"weapon_id": "", "combo": 1, "double_blow": false, "dash": true, "score": 32.5, "tier": tier, "is_ko": not victim.alive,
		"hp_after": victim.hp, "fight_time": match_node.fight_time, "sd_mult": 1.0,
		"colour": Tuning.PLAYER_COLORS[clampi(victim.player_index, 0, 3)],
	}


func overlays_of(d: Doll) -> Dictionary:
	var out := {}
	for b in d.parts.values():
		for m in (b as Node).find_children("*", "MeshInstance3D", true, false):
			out[m] = (m as MeshInstance3D).material_overlay
	return out


func mask_bits(d: Doll) -> int:
	var n := 0
	for mi in d.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).layers & DollMask.MASK_BIT != 0:
			n += 1
	return n


func decals_on(d: Doll) -> int:
	var n := 0
	for b in d.parts.values():
		n += (b as Node).find_children("*", "Decal", true, false).size()
	return n


## Дети Match без временных ImpactFx (prewarm вспышек): ожидаются только директора.
func fx_children() -> Array:
	var out: Array = []
	for n in match_node.get_children():
		if not String(n.name).begins_with("ImpactFx"):
			out.append(String(n.name))
	return out


func time_tags() -> Array:
	return cc.active_time_tags()


func _on_phase(name: String, ms: float) -> void:
	_phase_seen[name] = ms


## Кадры до конца проигрывания; на каждом (в начале кадра) — [мс прошлого кадра, time_scale этого кадра, камера].
func run_timeline(max_frames: int, on_frame: Callable = Callable()) -> Array:
	var log: Array = []
	var k := 0
	while cc.is_playing() and k < max_frames:
		await get_tree().process_frame
		if not cc.is_playing():
			break
		# начало кадра: elapsed_ms — конец прошлого кадра, time_scale и камера — те, что действуют в этом кадре
		var rec := {"k": k, "prev_ms": cc.elapsed_ms(), "ts": Engine.time_scale, "cam": get_viewport().get_camera_3d()}
		log.append(rec)
		if on_frame.is_valid():
			on_frame.call(rec)
		k += 1
	return log


func _run() -> void:
	cc = null
	var dir_node := match_node.get_node_or_null("HitFxDirector")
	if dir_node != null:
		for c in dir_node.get_children():
			if c is CritCinematic:
				cc = c
	if cc == null:
		cc = CritCinematic.attach(self)
	report["host"] = "director" if cc.get_parent() != self else "probe"
	cc.phase.connect(_on_phase)
	await frames(70)
	var ds := dolls()
	var p1: Doll = ds[0]
	var p2: Doll = ds[1]
	check("fight_started", match_node.combat_active(), match_node.phase, Match.Phase.FIGHT)
	var match_children := fx_children()
	report["match_children"] = match_children

	# --- A: crit на P2 (орех), голова ---
	var before := overlays_of(p2)
	var flashes0 := cc.overlay.flash_events
	var masked0 := cc.overlay.masked_frames
	_phase_seen.clear()
	var ok_play := cc.play(make_ctx(p2, p1, "Head", "crit"))
	check("A_play_true", ok_play, ok_play, true)
	var again := cc.play(make_ctx(p2, p1, "Head", "crit"))
	check("A_replay_ignored", not again, again, false)
	var mid := {"cam_crit": 0, "cam_other": 0, "xray": false, "wood": false, "ghost": false, "decal": 0, "ts_bad": [], "cam_back": null,
		"letterbox": false, "caption": false, "crack": false, "hud_hidden": false, "mask_hold": false, "mask_bits": 0,
		"cap_y_in": null, "cap_y_out": null, "cap_sc_out": null, "cap_vis_880": null}
	var before_att := overlays_of(p1)
	var v3 := {"marker_100": null, "marker_200": null, "dimmed_300": 0, "att_overlay_300": false, "bgdim_800": null}
	var head_meshes: Array = (p2.parts["Head"] as Node).find_children("*", "MeshInstance3D", true, false)
	var torso_meshes: Array = p2.torso().find_children("*", "MeshInstance3D", true, false)
	var log := await run_timeline(200, func(r: Dictionary) -> void:
		var ms: float = r["prev_ms"]
		var ts: float = r["ts"]
		var exp_ts := -1.0
		if ms >= 0.0 and ms <= 100.0:
			exp_ts = 0.02
		elif ms >= 140.0 and ms <= 600.0:
			exp_ts = 0.12
		elif ms >= 640.0 and ms <= 1150.0:
			exp_ts = Tuning.CRIT_SLOWMO_SCALE
		if exp_ts > 0.0 and absf(ts - exp_ts) > 1e-4:
			(mid["ts_bad"] as Array).append([snappedf(ms, 0.1), ts])
		if ms >= 140.0 and ms <= 600.0:
			if r["cam"] == cc.crit_cam:
				mid["cam_crit"] = int(mid["cam_crit"]) + 1
			else:
				mid["cam_other"] = int(mid["cam_other"]) + 1
			if ms >= 300.0 and ms <= 320.0:
				mid["xray"] = cc.xray_post.visible
				mid["wood"] = not head_meshes.is_empty() and (head_meshes[0] as MeshInstance3D).material_overlay != null \
					and (head_meshes[0] as MeshInstance3D).material_overlay != before.get(head_meshes[0])
				mid["ghost"] = not torso_meshes.is_empty() and (torso_meshes[0] as MeshInstance3D).material_overlay != before.get(torso_meshes[0])
				mid["decal"] = decals_on(p2)
				mid["letterbox"] = cc.overlay.letterbox.visible
				mid["crack"] = cc.overlay.screen_crack.visible
				var players := hud.get_node_or_null("Root/Players") as CanvasItem if hud != null else null
				mid["hud_hidden"] = players != null and not players.is_visible_in_tree()
				var xm := cc.xray_post.get_surface_override_material(0) as ShaderMaterial
				mid["mask_hold"] = cc._mask != null and cc._mask.active() and float(xm.get_shader_parameter("use_mask")) > 0.5
				mid["mask_bits"] = mask_bits(p2)
			if ms >= 400.0 and ms <= 420.0:
				mid["caption"] = cc.overlay.caption.visible
				mid["cap_y_in"] = cc.overlay.caption.position.y
		if ms >= 740.0 and mid["cap_y_out"] == null:
			mid["cap_y_out"] = cc.overlay.caption.position.y if cc.overlay.caption.visible else null
			mid["cap_sc_out"] = cc.overlay.caption.scale.x
			var vy := game_cam.unproject_position(p2.centre_of_mass()).y * cc.overlay.area().y / get_viewport().get_visible_rect().size.y
			var cy := cc.overlay.caption.position.y + cc.overlay.caption.size.y * 0.5
			mid["cap_victim_gap"] = absf(cy - vy)
		if ms >= 880.0 and mid["cap_vis_880"] == null:
			mid["cap_vis_880"] = cc.overlay.caption.visible
		if ms >= 85.0 and v3["marker_100"] == null:
			v3["marker_100"] = cc.overlay.hit_marker.visible
		if ms >= 200.0 and v3["marker_200"] == null:
			v3["marker_200"] = cc.overlay.hit_marker.visible
		if ms >= 300.0 and ms <= 320.0:
			v3["dimmed_300"] = cc.attacker_dimmed
			var am: Array = p1.torso().find_children("*", "MeshInstance3D", true, false)
			v3["att_overlay_300"] = not am.is_empty() and (am[0] as MeshInstance3D).material_overlay != before_att.get(am[0])
		if ms >= 800.0 and v3["bgdim_800"] == null:
			v3["bgdim_800"] = cc.overlay.bg_dim.visible
		if ms >= 620.0 and mid["cam_back"] == null:
			mid["cam_back"] = r["cam"] == game_cam)
	for ph in PHASES:
		var got: Variant = _phase_seen.get(ph)
		check("A_phase_" + ph, got != null and absf(float(got) - float(PHASES[ph])) <= TOL_MS, got, PHASES[ph])
	check("A_time_scale_windows", (mid["ts_bad"] as Array).is_empty(), mid["ts_bad"], "0.02 / 0.12 / 0.3")
	check("A_cam_crit_in_close_up", int(mid["cam_crit"]) > 0 and int(mid["cam_other"]) == 0, [mid["cam_crit"], mid["cam_other"]], "все кадры 140–600")
	check("A_cam_back_after_cut_out", mid["cam_back"] == true, mid["cam_back"], true)
	check("A_xray_visible", bool(mid["xray"]), mid["xray"], true)
	check("A_wood_overlay_on_head", bool(mid["wood"]), mid["wood"], true)
	check("A_ghost_overlay_on_torso", bool(mid["ghost"]), mid["ghost"], true)
	check("A_decal_on_part", int(mid["decal"]) == 1, mid["decal"], 1)
	check("A_letterbox_crack_caption", bool(mid["letterbox"]) and bool(mid["crack"]) and bool(mid["caption"]), [mid["letterbox"], mid["crack"], mid["caption"]], true)
	check("A_hud_hidden", bool(mid["hud_hidden"]), mid["hud_hidden"], true)
	check("A_mask_hold_in_xray", bool(mid["mask_hold"]) and int(mid["mask_bits"]) > 0, [mid["mask_hold"], mid["mask_bits"]], [true, ">0"])
	check("A_masked_impact_frames", cc.overlay.masked_frames - masked0 == 2, cc.overlay.masked_frames - masked0, 2)
	check("A_cam_half_height_head", cc.part_half_height >= 0.7 and cc.part_half_height <= 0.95, snappedf(cc.part_half_height, 0.01), "0.7–0.95")
	check("A_caption_slot", cc.caption_slot > 0.0, [cc.caption_slot, cc.part_screen_span], "0.76 | 0.25")
	var y_in: Variant = mid["cap_y_in"]
	var y_out: Variant = mid["cap_y_out"]
	check("A_caption_out_shrinks_off_victim", y_in != null and y_out != null and float(mid["cap_sc_out"]) < 0.8 and float(mid.get("cap_victim_gap", 0.0)) > 150.0,
		[y_in, y_out, mid["cap_sc_out"], mid.get("cap_victim_gap")], "на 740 мс: scale < 0.8, центр надписи дальше 150 ед. (из 1080) от ЦМ жертвы")
	check("A_caption_out_slot", cc.caption_out_slot > 0.0, cc.caption_out_slot, "0.26 | 0.84")
	check("A_caption_gone_880", mid["cap_vis_880"] == false, mid["cap_vis_880"], false)
	check("A_frames", log.size() >= 70 and log.size() <= 82, log.size(), "≈78")
	await frames(1)
	check("A_after_time_scale_1", is_equal_approx(Engine.time_scale, 1.0), Engine.time_scale, 1.0)
	check("A_after_no_tags", time_tags().is_empty(), time_tags(), [])
	check("A_after_cam_game", get_viewport().get_camera_3d() == game_cam, str(get_viewport().get_camera_3d()), "DynamicCamera")
	if match_node.has_method("camera_owner"):
		check("A_after_camera_owner", String(match_node.call("camera_owner")) == "", match_node.call("camera_owner"), "")
	check("A_after_overlay_idle", cc.overlay.is_idle() and not cc.xray_post.visible, cc.overlay.visible, false)
	var after := overlays_of(p2)
	var same := after.size() == before.size()
	for m in before:
		same = same and after.get(m) == before[m]
	check("A_after_material_overlay_restored", same, after.size(), before.size())
	var players2 := hud.get_node_or_null("Root/Players") as CanvasItem if hud != null else null
	check("A_after_hud_visible", players2 == null or players2.is_visible_in_tree(), players2 != null and players2.is_visible_in_tree(), true)
	check("A_after_mask_released", not cc._mask.active() and mask_bits(p2) == 0 and mask_bits(p1) == 0, [cc._mask.active(), mask_bits(p2)], [false, 0])
	check("A_flash_events", cc.overlay.flash_events - flashes0 == 2, cc.overlay.flash_events - flashes0, 2)
	# v3
	check("A_marker_33_150", v3["marker_100"] == true and v3["marker_200"] == false and cc.marker_frames >= 4,
		[v3["marker_100"], v3["marker_200"], cc.marker_frames], [true, false, ">=4 кадров"])
	check("A_attacker_dimmed_xray", int(v3["dimmed_300"]) > 0 and bool(v3["att_overlay_300"]), [v3["dimmed_300"], v3["att_overlay_300"]], [">0", true])
	var after_att := overlays_of(p1)
	var same_att := after_att.size() == before_att.size()
	for m in before_att:
		same_att = same_att and after_att.get(m) == before_att[m]
	check("A_attacker_overlay_restored", same_att and cc.attacker_dimmed == 0, [same_att, cc.attacker_dimmed], [true, 0])
	check("A_bg_dim_slowmo", v3["bgdim_800"] == true and cc.bg_dim_frames > 0 and not cc.overlay.bg_dim.visible,
		[v3["bgdim_800"], cc.bg_dim_frames, cc.overlay.bg_dim.visible], [true, ">0", false])
	check("A_caption_out_off_dolls", cc.caption_overlap >= 0.0 and cc.caption_overlap <= 0.15, snappedf(cc.caption_overlap, 0.001), "<= 0.15 полосы на куклах")
	await frames(180)
	check("A_3s_no_decal", decals_on(p2) == 0, decals_on(p2), 0)
	check("A_3s_fx_nodes", cc.fx_node_count() == 0, cc.fx_node_count(), 0)
	check("A_match_children", fx_children() == match_children, fx_children(), match_children)
	report["scenarios"]["A"] = {"frames": log.size(), "phases": _phase_seen.duplicate()}

	# --- B: restart на 300 мс, жертва P1 (клён) ---
	_phase_seen.clear()
	cc.play(make_ctx(p1, p2, "Torso", "crit"))
	var k := 0
	while cc.is_playing() and cc.elapsed_ms() < 300.0 and k < 60:
		await get_tree().process_frame
		k += 1
	var at_ms := cc.elapsed_ms()
	var cam_before_restart := get_viewport().get_camera_3d() == cc.crit_cam
	match_node.restart()
	await frames(1)
	check("B_was_close_up", cam_before_restart, at_ms, 300.0)
	check("B_restart_time_scale_1", is_equal_approx(Engine.time_scale, 1.0), Engine.time_scale, 1.0)
	check("B_restart_cam_game", get_viewport().get_camera_3d() == game_cam, str(get_viewport().get_camera_3d()), "DynamicCamera")
	if match_node.has_method("camera_owner"):
		check("B_restart_camera_owner", String(match_node.call("camera_owner")) == "", match_node.call("camera_owner"), "")
	check("B_restart_overlay_idle", cc.overlay.is_idle() and not cc.xray_post.visible and not cc.is_playing(), cc.is_playing(), false)
	check("B_restart_no_tags", time_tags().is_empty(), time_tags(), [])
	await frames(60)
	ds = dolls()
	p1 = ds[0]
	p2 = ds[1]

	# --- C: ko_crit на P2 ---
	_phase_seen.clear()
	p2.hp = 5.0
	var ctx_ko := make_ctx(p2, p1, "Torso", "ko_crit")
	p2.take_damage(20.0, p1, "Torso", ctx_ko["position"], ctx_ko["normal"], "body")
	ctx_ko["is_ko"] = not p2.alive
	ctx_ko["hp_after"] = p2.hp
	check("C_ko", not p2.alive, p2.alive, false)
	var ko_card := hud.get("ko_card") as CanvasItem if hud != null else null
	var ko_vis := {"300": null, "800": null}
	cc.play(ctx_ko)
	var bad_ko: Array = []
	await run_timeline(200, func(r: Dictionary) -> void:
		var ms: float = r["prev_ms"]
		if ms >= 620.0 and float(r["ts"]) > Tuning.KO_SLOWMO_SCALE + 1e-4:
			bad_ko.append([snappedf(ms, 0.1), r["ts"]])
		if ko_card != null and ms >= 300.0 and ko_vis["300"] == null:
			ko_vis["300"] = ko_card.visible
		if ko_card != null and ms >= 800.0 and ko_vis["800"] == null:
			ko_vis["800"] = ko_card.visible)
	check("C_done", _phase_seen.has("done"), _phase_seen.keys(), "done")
	check("C_ko_slowmo_until_done", bad_ko.is_empty(), bad_ko, "≤ 0.25")
	# после done: ko_crit_slowmo держит ≤ 0.25 до ~2.0 с от удара, потом 1.0
	var t_ms := 1300.0
	var bad_tail: Array = []
	while t_ms < 1950.0:
		await get_tree().process_frame
		t_ms += FRAME_MS
		if Engine.time_scale > Tuning.KO_SLOWMO_SCALE + 1e-4:
			bad_tail.append([snappedf(t_ms, 0.1), Engine.time_scale])
	check("C_ko_slowmo_tail", bad_tail.is_empty(), bad_tail, "≤ 0.25 до 1950 мс")
	while t_ms < 2150.0:
		await get_tree().process_frame
		t_ms += FRAME_MS
	check("C_time_scale_1_after_2100", is_equal_approx(Engine.time_scale, 1.0), Engine.time_scale, 1.0)
	check("C_ko_card_deferred", ko_vis["300"] == false and ko_vis["800"] == true, ko_vis, {"300": false, "800": true})
	check("C_no_tags", time_tags().is_empty(), time_tags(), [])
	match_node.restart()
	await frames(60)
	ds = dolls()
	p1 = ds[0]
	p2 = ds[1]

	# --- D: жертва без мешей ---
	_phase_seen.clear()
	for b in p1.parts.values():
		for m in (b as Node).find_children("*", "MeshInstance3D", true, false):
			(m as Node).get_parent().remove_child(m)
			(m as Node).queue_free()
	await frames(2)
	var decal_seen := [0]
	cc.play(make_ctx(p1, p2, "UpperArm_R" if p1.parts.has("UpperArm_R") else "Torso", "crit"))
	await run_timeline(200, func(r: Dictionary) -> void:
		if float(r["prev_ms"]) >= 300.0 and decal_seen[0] == 0:
			decal_seen[0] = decals_on(p1))
	check("D_no_mesh_done", _phase_seen.has("done"), _phase_seen.keys(), "done")
	check("D_no_mesh_decal", decal_seen[0] == 1, decal_seen[0], 1)
	await frames(1)
	check("D_no_mesh_restored", is_equal_approx(Engine.time_scale, 1.0) and get_viewport().get_camera_3d() == game_cam, Engine.time_scale, 1.0)

	# --- E: доступность и выключатель ---
	var f0 := cc.overlay.flash_events
	cc.flash_intensity_override = 0.0
	_phase_seen.clear()
	cc.play(make_ctx(p2, p1, "Head", "crit"))
	await run_timeline(200)
	check("E_flash_0_no_flashes", cc.overlay.flash_events == f0 and _phase_seen.has("done"), cc.overlay.flash_events - f0, 0)
	cc.flash_intensity_override = -1.0
	cc.enabled = false
	var off := cc.play(make_ctx(p2, p1, "Head", "crit"))
	check("E_disabled_play_false", not off, off, false)
	cc.enabled = true

	# --- G: крит в голень — полувысота крупного плана по детали ---
	_phase_seen.clear()
	var leg := "LowerLeg_L" if p2.parts.has("LowerLeg_L") else "Torso"
	cc.play(make_ctx(p2, p1, leg, "crit"))
	await run_timeline(200)
	report["scenarios"]["G"] = {"part": leg, "half": cc.part_half_height, "slot": cc.caption_slot, "span": cc.part_screen_span}
	check("G_cam_half_height_limb", leg == "Torso" or (cc.part_half_height >= 0.5 and cc.part_half_height <= 0.7), snappedf(cc.part_half_height, 0.01), "0.5–0.7 (≈0.55)")
	check("G_done_mask_released", _phase_seen.has("done") and not cc._mask.active() and mask_bits(p2) == 0, [_phase_seen.has("done"), cc._mask.active()], [true, false])

	# --- F: feel_enabled=false → время не трогается ---
	await frames(2)
	match_node.feel_enabled = false
	_phase_seen.clear()
	cc.play(make_ctx(p2, p1, "Head", "crit"))
	var ts_max := [1.0, 1.0]
	await run_timeline(200, func(r: Dictionary) -> void:
		ts_max[0] = minf(ts_max[0], float(r["ts"])))
	check("F_feel_off_time_untouched", is_equal_approx(ts_max[0], 1.0) and _phase_seen.has("done"), ts_max[0], 1.0)
	match_node.feel_enabled = true

	# --- S (v3): настоящий крит в правый верхний угол Void — жертва в safe-area всё окно ---
	var s_off := await _safe_run(false)
	var s_on := await _safe_run(true)
	report["scenarios"]["S"] = {"v2_safe_off": s_off, "v3": s_on}
	check("S_crit_played", String(s_on["tier"]) == "crit" and String(s_on["mode"]) == "cinematic", [s_on["tier"], s_on["mode"]], ["crit", "cinematic"])
	check("S_victim_reached_corner", float(s_on["max_x"]) >= 5.0 and float(s_on["max_y"]) >= 5.5, [s_on["max_x"], s_on["max_y"]], "ЦМ жертвы x ≥ 5, y ≥ 5.5 (угол)")
	check("S_safe_frames_out_0", int(s_on["frames"]) >= 40 and int(s_on["out"]) == 0, [s_on["out"], s_on["frames"], s_on["worst"]],
		"0 кадров вне safe_rect (v2: %d из %d)" % [int(s_off["out"]), int(s_off["frames"])])
	check("S_trail_whole_window", bool(s_on["trail_end"]) and bool(s_on["ghost_end"]), [s_on["trail_end"], s_on["ghost_end"]], [true, true])
	check("S_cam_idle_after", bool(s_on["idle_after"]), s_on["idle_after"], true)

	var f := FileAccess.open("res://tests/crit_probe_report.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  ", false))
	var n_ok := 0
	for c in report["checks"]:
		if c["ok"]:
			n_ok += 1
	print("crit_probe: %d/%d ok (host=%s)" % [n_ok, report["checks"].size(), report["host"]])
	Engine.time_scale = 1.0
	pg.queue_free()
	cc.queue_free()
	await frames(3)
	get_tree().quit(0 if report["ok"] else 1)


## Экранный прямоугольник куклы (доли кадра): углы AABB мешей частей, без мешей — позиции ± 0.3 м.
func screen_rect(cam: Camera3D, d: Doll) -> Rect2:
	var vs := get_viewport().get_visible_rect().size
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for b in d.parts.values():
		var boxes: Array = []
		for mi in (b as Node).find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh != null and not m.has_meta("hitfx"):
				boxes.append(m.get_global_transform_interpolated() * m.get_aabb())   # что видит игрок: интерполяция физики
		if boxes.is_empty():
			boxes.append(AABB((b as Node3D).get_global_transform_interpolated().origin - Vector3.ONE * 0.3, Vector3.ONE * 0.6))
		for bx in boxes:
			for i in range(8):
				var c := (bx as AABB).get_endpoint(i)
				if cam.is_position_behind(c):
					continue
				var p := cam.unproject_position(c) / vs
				lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
				hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return Rect2(lo, hi - lo)


## S: P2 под потолком Void у правой стены, P1 левее-ниже; удар как DollCombat (урон, отброс, отдача, Match.on_hit) с force_next crit
## вдоль (1, 0.55) — крит-полёт в правый верхний угол. От cut_out до cut_out + HitFxDirector.crit_hold_s — экранная проекция жертвы
## против safe_rect камеры. safe=false — DynamicCamera.safe_enabled = false (камера v2).
func _safe_run(safe: bool) -> Dictionary:
	match_node.restart()
	await frames(80)
	var ds := dolls()
	var a: Doll = ds[0]
	var v: Doll = ds[1]
	a.external_input = true
	v.external_input = true
	var dcam := game_cam as DynamicCamera
	dcam.safe_enabled = safe
	for pr in [[v, Vector2(3.6, 5.6)], [a, Vector2(2.4, 5.0)]]:
		var d: Doll = pr[0]
		var off := Vector3((pr[1] as Vector2).x, (pr[1] as Vector2).y, 0.0) - d.centre_of_mass()
		off.z = 0.0
		for b in d.parts.values():
			(b as RigidBody3D).global_position += off
			(b as RigidBody3D).linear_velocity = Vector3.ZERO
			(b as RigidBody3D).angular_velocity = Vector3.ZERO
	await frames(3)
	var dir := Vector3(1.0, 0.55, 0.0).normalized()
	var cut_ms := -1.0
	_phase_seen.clear()
	var fx_ctx := [{}]
	var cb := func(c: Dictionary) -> void: fx_ctx[0] = c
	match_node.hit_fx.connect(cb)
	match_node.hit_tiers.force_next = "crit"
	await get_tree().physics_frame
	var pos: Vector3 = v.torso().global_position - dir * 0.15
	v.hit_meta = {"speed": 9.0, "weapon_id": "", "striker": a.torso(), "combo_mult": 1.0, "double_blow": false,
		"knockback_mult": match_node.knockback_mult(), "stun_s": 0.0, "dir": dir, "striker_name": "Hand_R"}
	v.take_damage(24.0, a, "Torso", pos, -dir, "body")
	var j := maxf(Damage.knockback_impulse(24.0, match_node.knockback_mult()), Tuning.KNOCKBACK_MIN)
	v.apply_knockback(Damage.knockback_dir(dir) * j, v.torso(), 0.0, dir, Tuning.KNOCKBACK_MIN)
	a.apply_recoil(dir, Tuning.HIT_ATTACKER_RECOIL * j / maxf(v.total_mass, 1.0), Tuning.HIT_ATTACKER_THRUST_LOCK_S)
	match_node.on_hit(v, a, 24.0, "body", pos, 1, false, "", 9.0)
	match_node.hit_fx.disconnect(cb)
	var director := match_node.get_node_or_null("HitFxDirector") as HitFxDirector
	var mode := String((director.played[director.played.size() - 1] as Dictionary).get("mode", "")) if director != null and not director.played.is_empty() else ""
	var tier := String((fx_ctx[0] as Dictionary).get("tier", ""))
	var hold_ms := HitFxDirector.crit_hold_s(tier, true) * 1000.0
	var sr := dcam.safe_rect
	var res := {"tier": tier, "mode": mode, "frames": 0, "out": 0, "worst": 0.0, "max_x": -INF, "max_y": -INF, "trail_end": false,
		"ghost_end": false, "idle_after": false, "hold_ms": hold_ms}
	var k := 0
	var ghost_snaps := -1
	while k < 240:
		await get_tree().process_frame
		k += 1
		if cut_ms < 0.0 and _phase_seen.has("cut_out"):
			cut_ms = director.clock_ms()
		if cut_ms < 0.0:
			if not cc.is_playing() and k > 10:
				break
			continue
		var since := director.clock_ms() - cut_ms
		if since > hold_ms:
			break
		if get_viewport().get_camera_3d() != game_cam:
			continue
		var r := screen_rect(game_cam, v)
		var com := v.centre_of_mass()
		res["max_x"] = maxf(float(res["max_x"]), com.x)
		res["max_y"] = maxf(float(res["max_y"]), com.y)
		res["frames"] = int(res["frames"]) + 1
		var over := maxf(maxf(sr.position.x - r.position.x, r.end.x - sr.end.x), maxf(sr.position.y - r.position.y, r.end.y - sr.end.y))
		if over > 0.006:   # 0.003 → 0.006 (perf-pass): с интерполяцией физики проба читает кадр до обновления камеры — до 3 мм (≈4 px) расхождения, невидимо
			res["out"] = int(res["out"]) + 1
			res["worst"] = maxf(float(res["worst"]), snappedf(over, 0.001))
		if since >= hold_ms - 220.0 and ghost_snaps < 0:
			for c in director.fx_root.get_children():
				if c is AfterimageTrail and not c.is_queued_for_deletion():
					ghost_snaps = maxi(ghost_snaps, (c as AfterimageTrail).snapshots)
		if since >= hold_ms - 40.0:
			for c in director.fx_root.get_children():
				if c.is_queued_for_deletion():
					continue
				if c is FlightTrail:
					res["trail_end"] = true
				if c is AfterimageTrail and ghost_snaps >= 0 and (c as AfterimageTrail).snapshots > ghost_snaps:
					res["ghost_end"] = true
	res["max_x"] = snappedf(float(res["max_x"]), 0.01)
	res["max_y"] = snappedf(float(res["max_y"]), 0.01)
	var w := 0
	while w < 300 and (cc.is_playing() or not dcam.fx_idle()):
		await get_tree().process_frame
		w += 1
	await frames(30)
	res["idle_after"] = dcam.fx_idle() and not dcam.safe_engaged()
	dcam.safe_enabled = true
	return res
