## Проба оформления «прямого эфира Лиги» (docs/plan-demo/look/show.md, headless): пункты «ВИД» группы «Эфир», стингер по сигналам
## лоадера, купол (толпа: приглушение, вспышки на ударе и KO, волна на победе; прожекторы ведут P1 / P2; свет финала), плашки бойцов
## на отсчёте, единый HUD (шрифты HudSkin, плашки HUD спорта и гонки). Для каждого пункта: включён — новое, выключен — ровно прежнее.
## Галочки и рубильник Look меняются программно (без записи user://look.cfg) и в конце возвращаются.
## Запуск: godot --headless --path . --fixed-fps 60 res://tests/look_show_probe.tscn   Exit 0/1.
## Аргументы: only=stinger|hall|plates|hud (через «+»).
extends Node

const DOME := "res://scenes/playground_null_hall.tscn"
const SPORT := "res://scenes/playground_sport.tscn"
const RACE := "res://scenes/playground_race.tscn"
const IDS := [&"show_stinger", &"show_plates", &"show_crowd_dim", &"show_crowd_fx", &"show_spots", &"show_final_light", &"show_hud"]

var ok := true
var only: PackedStringArray = []
var look: Node
var _saved := {}
var _master0 := true


func _check(id: String, cond: bool, detail: String) -> void:
	if not cond:
		ok = false
	print("  %s %s: %s" % ["ok  " if cond else "FAIL", id, detail])


func _want(part: String) -> bool:
	return only.is_empty() or only.has(part)


func _ready() -> void:
	print("=== LOOK SHOW PROBE ===")
	for a in OS.get_cmdline_user_args():
		for part in a.split(","):
			var kv := part.split("=", true, 1)
			if kv.size() == 2 and kv[0] == "only":
				only = kv[1].split("+")
	look = get_node_or_null("/root/Look")
	await _frames(2)
	_check("look", look != null, "автозагрузка Look")
	if look == null:
		_finish()
		return
	_master0 = look.master
	look.set_master(true)
	for id in IDS:
		_saved[id] = look.checked(id)
		look.set_on(id, true)
	var group_ok := true
	for id in IDS:
		group_ok = group_ok and look.ids().has(id) and look.group_of(id) == tr("Эфир")
	_check("items", group_ok, "7 пунктов в группе «Эфир»: %s" % str(IDS))
	if _want("stinger"):
		await _stinger()
	if _want("hall") or _want("plates"):
		await _dome()
	if _want("hud"):
		await _hud()
	_finish()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _phys(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


# ---------------------------------------------------------------- стингер

func _stinger() -> void:
	var loading := get_node("/root/Loading")
	var show := loading.get_node_or_null("LeagueShow")
	_check("show_node", show != null and show.get("stinger") != null, "LeagueShow — ребёнок лоадера, стингер есть")
	if show == null:
		return
	var st: LeagueStinger = show.stinger
	st.seek(0.0)
	var c0 := st.cover()
	st.seek(LeagueStinger.IN_S)
	var c1 := st.cover()
	st.seek(0.4)
	var c2 := st.cover()
	st.seek(LeagueStinger.FULL_S)
	var c3 := st.cover()
	_check("stinger_cover", c0 < 0.01 and c1 > 0.99 and c2 > 0.99 and c3 < 0.01,
		"шторка: старт %.2f, %.2f с — %.2f, 0.4 с — %.2f, конец %.2f" % [c0, LeagueStinger.IN_S, c1, c2, c3])
	st.stop()
	var p0 := st.plays
	loading.begin("ПРОБА", "")
	_check("stinger_open", st.plays == p0 + 1 and st.playing and st.t >= LeagueStinger.REVEAL_FROM_S - 0.001,
		"лоадер появился → заставка «с закрытого экрана» (t=%.2f)" % st.t)
	loading.finish()
	var t0 := Time.get_ticks_msec()
	while loading.showing and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
	_check("stinger_close", st.plays == p0 + 2, "лоадер закрылся → полная заставка (сыграла %d раз)" % (st.plays - p0))
	var t1 := Time.get_ticks_msec()
	while st.playing and Time.get_ticks_msec() - t1 < 3000:
		await get_tree().process_frame
	var dur := (Time.get_ticks_msec() - t1) / 1000.0
	_check("stinger_len", not st.playing and not st.visible and dur <= LeagueStinger.FULL_S + 0.3,
		"заставка ушла сама за ≤ %.1f с (%.2f с после начала гашения лоадера)" % [LeagueStinger.FULL_S + 0.3, dur])
	look.set_on(&"show_stinger", false)
	loading.begin("ПРОБА", "")
	var played_off := st.playing
	loading.finish()
	while loading.showing and Time.get_ticks_msec() - t0 < 9000:
		await get_tree().process_frame
	_check("stinger_off", not played_off and not st.playing and st.plays == p0 + 2, "пункт выключен → заставки нет")
	look.set_on(&"show_stinger", true)


# ---------------------------------------------------------------- купол: толпа, прожекторы, свет финала, плашки

func _dome() -> void:
	var pg := (load(DOME) as PackedScene).instantiate()
	add_child(pg)
	await _phys(20)
	var hall := pg.get_node("NullHall")
	var hs := hall.get_node_or_null("HallShow") as HallShow
	var m := pg.get_node("Match") as Match
	_check("hall_attach", hs != null and hs.match_node == m, "HallShow в арене купола, привязан к Match")
	var lt := pg.get_node_or_null("LowerThirds") as LowerThirds
	if _want("plates"):
		_check("plates_attach", lt != null and lt.match_node == m, "LowerThirds рядом с матчем")
		# Плашки «ИГРОК 1 / ИГРОК 2 · СЕРИЯ» — только 1 на 1: у босса (кооп), «Собери себя» (FFA 5) и вышибал (3 на 3) их нет.
		var team_off := true
		for mm: Match in [BossMatch.new(), ScavMatch.new(), DodgeballMatch.new()]:
			team_off = team_off and not LowerThirds.wants(mm)
			mm.free()
		_check("plates_skip_team_modes", team_off and LowerThirds.wants(m), "плашки 1 на 1 не у босса / сборщика / вышибал (VISUAL_PASS_2310)")
	if hs == null:
		pg.queue_free()
		return
	var mat := hs._crowd
	if _want("hall"):
		_check("crowd_mat", mat != null, "материал толпы найден")
		_check("crowd_dim_on", is_equal_approx(float(mat.get_shader_parameter("show_dim")), 1.0)
			and is_equal_approx(float(mat.get_shader_parameter("show_sway")), 1.0), "толпа приглушена и покачивается")
		look.set_on(&"show_crowd_dim", false)
		look.set_on(&"show_crowd_fx", false)
		var dim_off := float(mat.get_shader_parameter("show_dim"))
		var sway_off := float(mat.get_shader_parameter("show_sway"))
		var wave_off := float(mat.get_shader_parameter("show_wave"))
		_check("crowd_off", dim_off == 0.0 and sway_off == 0.0 and wave_off < 0.0 and float(mat.get_shader_parameter("show_flash")) == 0.0,
			"пункты выключены → параметры шейдера по умолчанию (вид прежний)")
		look.set_on(&"show_crowd_dim", true)
		look.set_on(&"show_crowd_fx", true)
		# вспышки: сильный удар и KO
		var p1 := pg.get_node("P1") as Doll
		var p2 := pg.get_node("P2") as Doll
		hs.flash = 0.0
		m.hit.emit(p2, p1, 4.0, "light", Vector3.ZERO)
		var weak := hs.flash
		m.hit.emit(p2, p1, 26.0, "heavy", Vector3.ZERO)
		var strong := hs.flash
		await _frames(2)
		_check("flash_hit", weak == 0.0 and strong > 0.5 and float(mat.get_shader_parameter("show_flash")) > 0.3,
			"слабый удар — без вспышек (%.2f), сильный — вспышки %.2f" % [weak, strong])
		m.ko.emit(p2, p1, {})
		_check("flash_ko", hs.flash >= 0.99, "KO → вспышки 1.0")
		m.match_over.emit(p1, {})
		await _frames(3)
		_check("wave", hs.wave > 0.0 and float(mat.get_shader_parameter("show_wave")) >= 0.0, "победа → волна идёт (%.2f)" % hs.wave)
		# прожекторы
		await _phys(10)
		var aim_ok := true
		var info := []
		for i in 2:
			var s: Dictionary = hs._spots[i]
			var l := s["light"] as SpotLight3D
			var d := [p1, p2][i] as Doll
			var to := (d.centre_of_mass(true) - l.global_position).normalized()
			var fwd := -l.global_transform.basis.z.normalized()
			var ang := rad_to_deg(fwd.angle_to(to))
			info.append("%s→P%d %.1f°" % [l.name, i + 1, ang])
			aim_ok = aim_ok and ang < 6.0 and is_equal_approx(l.spot_angle, HallShow.SPOT_ANGLE) and not l.shadow_enabled \
				and (s["beam"] as MeshInstance3D).visible
		_check("spots_aim", aim_ok, "прожекторы ведут бойцов, узкий конус, без теней, луч виден: %s" % ", ".join(info))
		look.set_on(&"show_spots", false)
		var back_ok := true
		for s in hs._spots:
			var l := s["light"] as SpotLight3D
			back_ok = back_ok and l.transform.is_equal_approx(s["xf"]) and is_equal_approx(l.spot_angle, float(s["angle"])) \
				and l.shadow_enabled == bool(s["shadow"]) and not (s["beam"] as MeshInstance3D).visible
		_check("spots_off", back_ok, "выключены → трансформ, угол, тени как в сцене, лучей нет")
		look.set_on(&"show_spots", true)
		# свет финала: последние 10 с
		var key := hall.get_node("Lights/Key") as Light3D
		var warm := hall.get_node("Lights/Warm_1_2") as Light3D
		var env := (hall.get_node("Environment") as WorldEnvironment).environment
		var key0 := key.light_energy
		var warm0 := warm.light_energy
		var amb0 := env.ambient_light_energy
		m.restart()
		await _phys(5)
		m.countdown_s = 0.0
		m._countdown_left = 0.0
		await _phys(5)
		m.fight_time = m.time_limit_s - 8.0
		await _phys(int(HallShow.FINAL_BLEND_S * 60.0) + 20)
		var kd := key.light_energy / key0
		var wd := warm.light_energy / warm0
		var ad := env.ambient_light_energy / amb0
		var crowd_l := float(mat.get_shader_parameter("show_light"))
		var spot_e := (hs._spots[0]["light"] as Light3D).light_energy
		_check("final_dim", absf(kd - HallShow.FINAL_KEEP) < 0.03 and absf(wd - HallShow.FINAL_KEEP) < 0.03 and absf(ad - HallShow.FINAL_KEEP) < 0.03
			and absf(crowd_l - HallShow.FINAL_KEEP) < 0.03,
			"осталось %.0f с → общий свет ×%.2f (лампа ×%.2f, ambient ×%.2f, толпа ×%.2f), прожектор бойца %.1f" % [m.time_left_s(), kd, wd, ad,
			crowd_l, spot_e])
		look.set_on(&"show_final_light", false)
		_check("final_off", is_equal_approx(key.light_energy, key0) and is_equal_approx(warm.light_energy, warm0)
			and is_equal_approx(env.ambient_light_energy, amb0) and float(mat.get_shader_parameter("show_light")) == 1.0,
			"пункт выключен → энергии и толпа как были сразу")
		look.set_on(&"show_final_light", true)
		await _phys(int(HallShow.FINAL_BLEND_S * 60.0) + 20)
		m.restart()
		await _phys(int(HallShow.FINAL_BLEND_S * 60.0) + 20)
		_check("final_back", is_equal_approx(key.light_energy, key0) and is_equal_approx(env.ambient_light_energy, amb0),
			"новый бой → свет вернулся (%.2f / %.2f)" % [key.light_energy, key0])
	if _want("plates") and lt != null:
		m.restart()
		await _phys(30)
		_check("plates_show", lt.plates.size() == 2 and lt.visible, "на отсчёте две плашки (выезжали %d раз)" % lt.shown)
		var names := []
		for p in lt.plates:
			names.append((p.get_node("MaskName/NamePlate/Name") as Label).text + " / " + (p.get_node("MaskSub/SubPlate/Sub") as Label).text)
		var i1 := lt.info_for(0)
		_check("plates_text", names.size() == 2 and String(i1["name"]) == PlayerPanel.default_name(0).to_upper()
			and String(i1["sub"]).contains(tr("Человек")), "плашки: %s" % " | ".join(names))
		var r := lt.plates[1] as Control
		var vp := Vector2(1920, 1080)
		await _phys(40)
		var rr := r.get_global_rect()
		_check("plates_place", rr.end.x <= vp.x + 1.0 and rr.position.x > vp.x * 0.5 and rr.end.y < 940.0,
			"P2 справа снизу в кадре, выше индикатора поля: %s" % str(rr))
		look.set_on(&"show_plates", false)
		_check("plates_off", not lt.visible, "пункт выключен → слой плашек спрятан сразу")
		look.set_on(&"show_plates", true)
		await _phys(int((LowerThirds.HOLD_S + LowerThirds.OUT_S + 0.6) * 60.0))
		_check("plates_gone", lt.plates.is_empty(), "через %.1f с плашки уехали" % (LowerThirds.HOLD_S + LowerThirds.OUT_S))
	pg.queue_free()
	await _frames(2)


# ---------------------------------------------------------------- единый HUD

func _hud() -> void:
	var skin0 := HudSkin.id()
	HudSkin.set_skin("broadcast", false)
	_check("hud_unified", ShowTokens.unified, "единый HUD включён по умолчанию")
	var f := HudSkin.font("plate")
	var base: Font = (f as FontVariation).base_font if f is FontVariation else null
	_check("hud_font_on", base != null and base.resource_path.ends_with("Oswald.ttf") and HudSkin.font("body") is FontVariation
		and ((HudSkin.font("body") as FontVariation).base_font as Resource).resource_path.ends_with("Rubik.ttf"),
		"шрифты HudSkin — Oswald (имена, цифры, надписи) и Rubik (реплики)")
	_check("hud_theme_on", HudSkin.theme().default_font == HudSkin.font("plate"), "тема HUD со шрифтом токенов")
	look.set_on(&"show_hud", false)
	_check("hud_font_off", not ShowTokens.unified and HudSkin.font("plate") is SystemFont, "пункт выключен → системные шрифты скина")
	look.set_on(&"show_hud", true)
	for path in [SPORT, RACE]:
		var pg := (load(path) as PackedScene).instantiate()
		add_child(pg)
		await _phys(20)
		await _frames(3)
		var layer: CanvasLayer = null
		for c in pg.get_children():
			if c is CanvasLayer and c.get_node_or_null("HudUnify") != null:
				layer = c
		var u := layer.get_node("HudUnify") as HudUnify if layer != null else null
		var tag: String = String(path).get_file().get_basename()
		_check("hud_attach_" + tag, u != null, "HudUnify в HUD режима (%s)" % (layer.name if layer != null else "—"))
		if u == null:
			pg.queue_free()
			continue
		var flats: Array[StyleBoxFlat] = []
		for c in layer.find_children("*", "Control", true, false):
			if (c is PanelContainer or c is Panel) and (c as Control).has_theme_stylebox_override("panel"):
				var sb := (c as Control).get_theme_stylebox("panel") as StyleBoxFlat
				if sb != null:
					flats.append(sb)
		var styled := 0
		for sb in flats:
			if sb.has_meta(ShowTokens.META) and sb.corner_radius_top_left == 0 and sb.skew.x > 0.0:
				styled += 1
		_check("hud_restyle_" + tag, flats.size() > 0 and styled == flats.size(),
			"плашки режима — косые плашки трансляции: %d из %d" % [styled, flats.size()])
		look.set_on(&"show_hud", false)
		await _frames(2)
		var plain := 0
		for c in layer.find_children("*", "Control", true, false):
			if (c is PanelContainer or c is Panel) and (c as Control).has_theme_stylebox_override("panel"):
				var sb := (c as Control).get_theme_stylebox("panel") as StyleBoxFlat
				if sb != null and not sb.has_meta(ShowTokens.META) and sb.skew == Vector2.ZERO and sb.corner_radius_top_left > 0:
					plain += 1
		_check("hud_restore_" + tag, plain > 0 and u.restyled == 0, "пункт выключен → прежние скруглённые плашки (%d)" % plain)
		look.set_on(&"show_hud", true)
		await _frames(2)
		pg.queue_free()
		await _frames(2)
	HudSkin.set_skin(skin0, false)


func _finish() -> void:
	if look != null:
		for id in _saved:
			look.set_on(id, bool(_saved[id]))
		look.set_master(_master0)
	print("=== %s ===" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
