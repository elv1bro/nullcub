## Проба главного меню-гаража (scenes/menu/garage_menu.tscn) без окна:
##   godot --headless --path godot res://tests/garage_menu_probe.tscn
## Сценарий через настоящий ввод (Input.parse_input_event): титул → любая клавиша → ↓ по всем пунктам → цифра 3 → Esc →
## Enter на «Истории» (кампания открывается в эфире ТВ, сцена не меняется; сигнал navigated остаётся для «Быстрого боя» и «Всех режимов»). Проверки: точки камер и цели пунктов существуют,
## камера доезжает до точки пункта за ≤ 1.5 × move_time, телевизор переключается на канал пункта, лампы зоны пункта ярче
## базы, а чужих зон — тусклее, Esc ведёт к «Выходу», до боя ≤ 2 нажатий, выход гасит свет и шлёт navigated("quit").
## 06.10 (гараж от первого лица): точки пунктов на высоте глаз, руки героя в кадре внизу, на переходе кадр покачивается (шаги),
## N0 в кадре у предмета пункта (не под меню), кукла висит на стенде спящей мастерской (витрина), шлем на подставке консоли,
## стена экранов привязана и показывает ту же сводку, что мастерская (масса, детали, энергия), пункт «БОЕЦ» — к стене и обратно.
## В stdout «=== GARAGE MENU PROBE ===» и JSON; exit 0 — всё ок.
extends Node

const MENU := preload("res://scenes/menu/garage_menu.tscn")

var menu: GarageMenu
var checks: Array = []
var nav: Array = []


func _ready() -> void:
	menu = MENU.instantiate() as GarageMenu
	menu.dry_run = true
	add_child(menu)
	menu.navigated.connect(func(t: String) -> void: nav.append({"target": t, "ms": Time.get_ticks_msec()}))
	await get_tree().process_frame
	await _run()
	var ok := true
	for c in checks:
		ok = ok and bool(c["ok"])
	print("=== GARAGE MENU PROBE ===")
	print(JSON.stringify({"ok": ok, "checks": checks}))
	print("=== OK ===" if ok else "=== FAIL ===")
	get_tree().quit(0 if ok else 1)


func _check(id: String, ok: bool, value = null, limit = null) -> void:
	checks.append({"id": id, "ok": ok, "value": value, "limit": limit})
	if not ok:
		push_warning("garage_menu_probe FAIL: %s value=%s limit=%s" % [id, str(value), str(limit)])


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame


func _settle() -> float:
	var t0 := Time.get_ticks_msec()
	while menu.is_moving() and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
	return (Time.get_ticks_msec() - t0) / 1000.0


func _at_spot(spot: String) -> Array:
	var a := menu.cam.global_transform
	var b := menu.spot_transform(spot)
	var d := a.origin.distance_to(b.origin)
	var ang := rad_to_deg(a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion()))
	return [d, ang]


func _zone_ok(zone: String) -> bool:
	if zone == "":
		return true
	for z in menu.zone_lights:
		for l in menu.zone_lights[z]:
			var base := float(l.get_meta("base"))
			var e := (l as Light3D).light_energy
			if z == zone and e < base * 1.2:
				return false
			if z != zone and z != "tv" and z != "room" and e > base * 0.9:
				return false
	return true


func _run() -> void:
	# 1. структура
	var missing: Array = []
	for s in ["Title", "Story", "Quick", "Workshop", "Trophies", "Settings", "SettingsClose", "IntoTV", "IntoGate", "IntoStand"]:
		if not menu.spots.has(s):
			missing.append(s)
	_check("spots_present", missing.is_empty(), missing)
	var bad_go: Array = []
	for it in GarageMenu.ITEMS:
		var go := String(it["go"])
		if go != "" and not ResourceLoader.exists(go):
			bad_go.append(go)
		if String(it["via"]) != "" and not menu.spots.has(String(it["via"])):
			bad_go.append(it["via"])
	_check("targets_exist", bad_go.is_empty(), bad_go)
	_check("tv_screen_bound", _tv_bound(), null)
	_check("title_state", menu.state == "title", menu.state)
	# живой эфир: две куклы в своём мире телевизора двигаются (разлёт меняется), а не стоят
	var bt := menu.bout
	var d0 := -1.0
	var d1 := -1.0
	if bt != null and bt.dolls.size() == 2:
		d0 = (bt.dolls[0] as Doll).centre_of_mass().distance_to((bt.dolls[1] as Doll).centre_of_mass())
		await get_tree().create_timer(2.5).timeout
		d1 = (bt.dolls[0] as Doll).centre_of_mass().distance_to((bt.dolls[1] as Doll).centre_of_mass())
	_check("tv_live_bout", bt != null and absf(d1 - d0) > 0.3 and bt.get_viewport() == menu.tv_vp, [snappedf(d0, 0.01), snappedf(d1, 0.01)])
	# 1б. кукла — на стенде спящей мастерской (витрина): видна, заморожена, интерфейс мастерской спрятан, процесс стоит
	var w := menu.workshop
	var t_ws := Time.get_ticks_msec()
	while w.ws == null and Time.get_ticks_msec() - t_ws < 60000:
		await get_tree().process_frame
	var ws := w.ws
	var frozen := ws != null and ws.stand != null and not ws.stand.parts.is_empty()
	if frozen:
		for b in ws.stand.parts.values():
			frozen = frozen and (b as RigidBody3D).freeze
	var at_stand := ws != null and Vector2(ws.stand_root.global_position.x, ws.stand_root.global_position.z).distance_to(Vector2(-0.75, -1.2)) < 0.05
	_check("doll_hangs_on_stand", frozen and at_stand and ws.visible and ws.stand.visible and ws.stand_root.visible,
		[frozen, at_stand, ws.visible if ws != null else null])
	_check("workshop_sleeps_as_showcase", ws != null and not ws.active and ws.process_mode == Node.PROCESS_MODE_DISABLED
		and not (ws.get_node("UI") as CanvasLayer).visible, [ws.active if ws != null else null])
	_check("no_doll_on_crate", menu.get_node_or_null("Props/PlayerDoll") == null and menu.get_node_or_null("Props/CrateSeat") == null, null)
	# 1в. шлем на подставке консоли, кресло пилота, стена экранов и N0 на месте
	var hs := menu.get_node_or_null("Props/Headset") as Node3D
	var con := menu.get_node_or_null("Props/LinkConsole") as Node3D
	var rest: Vector3 = con.get_meta("headset_rest", Vector3.ZERO) if con != null else Vector3.ZERO
	_check("headset_on_console", hs != null and con != null and hs.global_position.distance_to(rest) < 0.01 and menu.headset.has_headset(),
		snappedf(hs.global_position.distance_to(rest), 0.001) if hs != null else null)
	_check("pilot_chair", menu.get_node_or_null("Props/PilotChair") != null, null)
	var sw := menu.stats_wall
	var bound := sw.screens_bound()
	_check("stats_wall_screens", sw.screens.size() >= 10 and bound >= sw.screens.size(), [sw.screens.size(), bound])
	var bs := ws.body_stats() if ws != null else {}
	var sd := sw.data
	_check("stats_wall_matches_workshop", not sd.is_empty() and int(sd["parts"]) == int(bs.get("parts", -1))
		and int(sd["energy"]) == int(bs.get("energy", -1)) and absf(float(sd["mass"]) - float(bs.get("mass", -1.0))) < 0.01,
		[sd.get("parts"), bs.get("parts"), sd.get("energy"), bs.get("energy")])
	_check("n0_in_garage", menu.n0 != null and menu.n0.drone != null and menu.n0.get_parent().name == "Props", null)
	# 1г. от первого лица: точки пунктов — на высоте глаз (1.5–1.75 м), руки героя видны внизу кадра
	var low: Array = []
	for it in GarageMenu.ITEMS:
		var y := menu.spot_transform(String(it["spot"])).origin.y
		if y < 1.5 or y > 1.75:
			low.append([it["id"], snappedf(y, 0.01)])
	_check("eye_height_spots", low.is_empty(), low)
	_check("hands_in_frame", _hands_in_frame(), _hands_screen())
	# 2. любая клавиша → меню, фокус на «Истории»
	await _key(KEY_SPACE)
	_check("any_key_enters_menu", menu.state == "menu" and menu.focus == 0, [menu.state, menu.focus])
	await _settle()
	# 3. все пункты вниз: камера, канал ТВ, свет зоны
	var limit := menu.move_time * 1.5 + 0.2
	var bob_max := 0.0
	for i in GarageMenu.ITEMS.size():
		if i > 0:
			await _key(KEY_DOWN)
		var it: Dictionary = GarageMenu.ITEMS[i]
		var t0s := Time.get_ticks_msec()
		var bob := 0.0
		while menu.is_moving() and Time.get_ticks_msec() - t0s < 4000:
			bob = maxf(bob, absf(menu.cam.v_offset))
			await get_tree().process_frame
		var t := (Time.get_ticks_msec() - t0s) / 1000.0
		bob_max = maxf(bob_max, bob)
		await get_tree().create_timer(0.3).timeout
		var at := _at_spot(String(it["spot"]))
		var id := String(it["id"])
		_check("focus_%s" % id, menu.focus == i, menu.focus, i)
		_check("camera_%s" % id, at[0] < 0.01 and at[1] < 0.5 and t <= limit, [snappedf(at[0], 0.001), snappedf(at[1], 0.01), snappedf(t, 0.01)], [0.01, 0.5, limit])
		_check("tv_%s" % id, menu.tv_mode == String(it["tv"]), menu.tv_mode, it["tv"])
		_check("zone_%s" % id, _zone_ok(String(it["zone"])), it["zone"])
		await get_tree().create_timer(1.2).timeout     # N0 долетел
		_check("n0_in_frame_%s" % id, _n0_in_frame(), _n0_screen())
	_check("walk_bob", bob_max > 0.006 and bob_max < 0.05, snappedf(bob_max, 0.0001), [0.006, 0.05])
	_check("hands_in_frame_after_walk", _hands_in_frame(), _hands_screen())
	# 3а. «Боец»: Enter — к стене экранов, Esc — к списку
	await _key(KEY_4)
	await _settle()
	await _key(KEY_ENTER)
	await _settle()
	var at_f := _at_spot("FighterClose")
	_check("fighter_open", menu.state == "fighter" and at_f[0] < 0.01, [menu.state, snappedf(at_f[0], 0.001)])
	await _key(KEY_ESCAPE)
	await _settle()
	_check("fighter_back", menu.state == "menu" and menu.focus == 3, [menu.state, menu.focus])
	# 3б. «Настройки»: Enter открывает экран у радио, → громкость +10 % (Flow, сохраняется), ← обратно, ↓ графика, Esc — к списку
	await _key(KEY_6)
	await _settle()
	await _key(KEY_ENTER)
	await _settle()
	var flow := get_node_or_null("/root/Flow")
	var at_s := _at_spot("SettingsClose")
	_check("settings_open", menu.state == "settings" and menu.settings_ui.visible and at_s[0] < 0.01, [menu.state, snappedf(at_s[0], 0.001)])
	await _key(KEY_DOWN)   # строка 0 — «ЯЗЫК» (смена языка перезагружает гараж), громкость — строка 1
	var v0: float = float(flow.get_setting("volume")) if flow != null else 0.8
	await _key(KEY_RIGHT)
	var v1: float = float(flow.get_setting("volume")) if flow != null else 0.0
	await _key(KEY_LEFT)
	var v2: float = float(flow.get_setting("volume")) if flow != null else 0.0
	_check("settings_volume", flow != null and absf(v1 - minf(v0 + 0.1, 1.0)) < 0.051 and absf(v2 - v0) < 0.051, [v0, v1, v2])
	# ↓ «Графика»: → следующий пресет Gfx (как F9), ← обратно
	var gfx := get_node_or_null("/root/Gfx")
	await _key(KEY_DOWN)
	var g0: String = String(gfx.preset) if gfx != null else ""
	await _key(KEY_RIGHT)
	var g1: String = String(gfx.preset) if gfx != null else ""
	await _key(KEY_LEFT)
	var g2: String = String(gfx.preset) if gfx != null else ""
	_check("settings_gfx", gfx != null and menu.settings_ui.row == 2 and g1 != g0 and g2 == g0, [g0, g1, g2])
	await _key(KEY_ESCAPE)
	await _settle()
	_check("settings_back", menu.state == "menu" and menu.focus == 5 and not menu.settings_ui.visible, [menu.state, menu.focus])
	# 3в. «Трофеи»: Enter — витрина, → следующий предмет (камера подъезжает к магнитоле), Esc — к списку
	await _key(KEY_5)
	await _settle()
	await _key(KEY_ENTER)
	await _settle()
	await _key(KEY_RIGHT)
	await _settle()
	# камера стоит в кадре второго предмета (магнитола) и смотрит на него: предмет перед камерой, в поле зрения
	var bx := menu.get_node_or_null("Props/Boombox") as Node3D
	var want := menu.exhibit_transform(1)
	var dpos := menu.cam.global_transform.origin.distance_to(want.origin)
	var seen := bx != null and not menu.cam.is_position_behind(bx.global_position) \
		and Rect2(Vector2.ZERO, menu.get_viewport().get_visible_rect().size).has_point(menu.cam.unproject_position(bx.global_position))
	_check("trophies_browse", menu.state == "trophies" and menu.trophies_ui.index == 1 and dpos < 0.01 and seen,
		[menu.state, menu.trophies_ui.index, snappedf(dpos, 0.001), seen])
	await _key(KEY_ESCAPE)
	await _settle()
	_check("trophies_back", menu.state == "menu" and menu.focus == 4 and not menu.trophies_ui.visible, [menu.state, menu.focus])
	# 4. цифра 3 → «Мастерская», Esc → «Выход»
	await _key(KEY_3)
	_check("digit_jump", menu.focus == 2, menu.focus, 2)
	await _key(KEY_ESCAPE)
	_check("esc_to_exit", menu.focus == GarageMenu.ITEMS.size() - 1, menu.focus)
	# 5. до боя: «1» → Enter (2 нажатия), нырок в телевизор и эфир кампании без смены сцены (garage_campaign.gd)
	await _key(KEY_1)
	await _settle()
	var t0 := Time.get_ticks_msec()
	await _key(KEY_ENTER)
	_check("enter_story_opens_campaign", menu.state == "campaign" and nav.is_empty(), [menu.state, nav.size()])
	while menu.campaign.screen != GarageCampaign.Screen.LADDER and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
	var dt := (Time.get_ticks_msec() - t0) / 1000.0
	_check("enter_to_ladder_s", menu.campaign.screen == GarageCampaign.Screen.LADDER and dt <= 1.8, snappedf(dt, 0.01), 1.8)
	_check("presses_to_fight_from_title", true, 2, 2)


## Руки героя: узел рук видим (камера гаража текущая), кисти — в кадре, в нижней половине.
func _hands_screen() -> Array:
	var out: Array = []
	var h := menu.view.hands
	for side in ["R", "L"]:
		var p := (h.wrist(side) as Node3D).global_transform * Vector3(0, 0, -0.05)
		out.append(menu.cam.unproject_position(p) if not menu.cam.is_position_behind(p) else Vector2(-1, -1))
	return out


func _hands_in_frame() -> bool:
	var h := menu.view.hands
	if h == null or not h.is_visible_in_tree():
		return false
	var vp := menu.get_viewport().get_visible_rect().size
	for p in _hands_screen():
		var v := p as Vector2
		if v.x < 0.0 or v.x > vp.x or v.y < vp.y * 0.5 or v.y > vp.y * 1.08:
			return false
	return true


## N0: перед камерой, ближе 2.6 м, в кадре и левее меню (меню — правые ~38 % кадра).
func _n0_screen() -> Array:
	var p := menu.n0.global_position
	var vp := menu.get_viewport().get_visible_rect().size
	var sp := menu.cam.unproject_position(p) if not menu.cam.is_position_behind(p) else Vector2(-1, -1)
	return [snappedf(sp.x / vp.x, 0.01), snappedf(sp.y / vp.y, 0.01), snappedf(p.distance_to(menu.cam.global_position), 0.01)]


func _n0_in_frame() -> bool:
	var s := _n0_screen()
	return float(s[0]) > 0.02 and float(s[0]) < 0.64 and float(s[1]) > 0.04 and float(s[1]) < 0.9 and float(s[2]) < 2.6


func _tv_bound() -> bool:
	var tv := menu.get_node_or_null("Props/TV")
	if tv == null:
		return false
	for mi in tv.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			if m.get_surface_override_material(i) == menu.tv_mat:
				return true
	return false
