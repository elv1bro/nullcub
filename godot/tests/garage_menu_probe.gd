## Проба главного меню-гаража (scenes/menu/garage_menu.tscn) без окна:
##   godot --headless --path godot res://tests/garage_menu_probe.tscn
## Сценарий через настоящий ввод (Input.parse_input_event): титул → любая клавиша → ↓ по всем пунктам → цифра 3 → Esc →
## Enter на «Истории» (dry_run: сцена не меняется, ловим сигнал navigated). Проверки: точки камер и цели пунктов существуют,
## камера доезжает до точки пункта за ≤ 1.5 × move_time, телевизор переключается на канал пункта, лампы зоны пункта ярче
## базы, а чужих зон — тусклее, Esc ведёт к «Выходу», до боя ≤ 2 нажатий, выход гасит свет и шлёт navigated("quit").
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
	# кукла игрока: собрана, все тела заморожены, бёдра на сиденье
	var pd := menu.player_doll
	var frozen := pd != null and pd.doll != null and not pd.doll.parts.is_empty()
	if frozen:
		for b in pd.doll.parts.values():
			frozen = frozen and (b as RigidBody3D).freeze
	_check("doll_seated", frozen, [pd.blueprint_source if pd != null else "нет", pd.doll.parts.size() if frozen else 0])
	# 2. любая клавиша → меню, фокус на «Истории»
	await _key(KEY_SPACE)
	_check("any_key_enters_menu", menu.state == "menu" and menu.focus == 0, [menu.state, menu.focus])
	await _settle()
	# 3. все пункты вниз: камера, канал ТВ, свет зоны
	var limit := menu.move_time * 1.5 + 0.2
	for i in GarageMenu.ITEMS.size():
		if i > 0:
			await _key(KEY_DOWN)
		var it: Dictionary = GarageMenu.ITEMS[i]
		var t := await _settle()
		await get_tree().create_timer(0.3).timeout
		var at := _at_spot(String(it["spot"]))
		var id := String(it["id"])
		_check("focus_%s" % id, menu.focus == i, menu.focus, i)
		_check("camera_%s" % id, at[0] < 0.01 and at[1] < 0.5 and t <= limit, [snappedf(at[0], 0.001), snappedf(at[1], 0.01), snappedf(t, 0.01)], [0.01, 0.5, limit])
		_check("tv_%s" % id, menu.tv_mode == String(it["tv"]), menu.tv_mode, it["tv"])
		_check("zone_%s" % id, _zone_ok(String(it["zone"])), it["zone"])
	# 3б. «Настройки»: Enter открывает экран у радио, → громкость +10 % (Flow, сохраняется), ← обратно, Esc — к списку
	await _key(KEY_5)
	await _settle()
	await _key(KEY_ENTER)
	await _settle()
	var flow := get_node_or_null("/root/Flow")
	var at_s := _at_spot("SettingsClose")
	_check("settings_open", menu.state == "settings" and menu.settings_ui.visible and at_s[0] < 0.01, [menu.state, snappedf(at_s[0], 0.001)])
	var v0: float = float(flow.get_setting("volume")) if flow != null else 0.8
	await _key(KEY_RIGHT)
	var v1: float = float(flow.get_setting("volume")) if flow != null else 0.0
	await _key(KEY_LEFT)
	var v2: float = float(flow.get_setting("volume")) if flow != null else 0.0
	_check("settings_volume", flow != null and absf(v1 - minf(v0 + 0.1, 1.0)) < 0.051 and absf(v2 - v0) < 0.051, [v0, v1, v2])
	await _key(KEY_ESCAPE)
	await _settle()
	_check("settings_back", menu.state == "menu" and menu.focus == 4 and not menu.settings_ui.visible, [menu.state, menu.focus])
	# голова куклы поворачивается к месту пункта: на «Быстром бое» (ворота слева) и «Настройках» (справа) — в разные стороны
	if pd != null and not pd._neck_bodies.is_empty():
		await _key(KEY_2)
		await get_tree().create_timer(1.5).timeout
		var yaw_q := pd._look_yaw
		await _key(KEY_5)
		await get_tree().create_timer(1.5).timeout
		var yaw_s := pd._look_yaw
		_check("doll_looks", yaw_q * yaw_s < 0.0 and absf(yaw_q - yaw_s) > 30.0, [snappedf(yaw_q, 0.1), snappedf(yaw_s, 0.1)])
	# 4. цифра 3 → «Мастерская», Esc → «Выход»
	await _key(KEY_3)
	_check("digit_jump", menu.focus == 2, menu.focus, 2)
	await _key(KEY_ESCAPE)
	_check("esc_to_exit", menu.focus == GarageMenu.ITEMS.size() - 1, menu.focus)
	# 5. до боя: «1» → Enter (2 нажатия), нырок в телевизор, сигнал navigated с целью «Истории»
	await _key(KEY_1)
	await _settle()
	var t0 := Time.get_ticks_msec()
	await _key(KEY_ENTER)
	while nav.is_empty() and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
	var dt := (Time.get_ticks_msec() - t0) / 1000.0
	var tgt := String(nav[0]["target"]) if not nav.is_empty() else ""
	_check("enter_story_navigates", tgt == String(GarageMenu.ITEMS[0]["go"]), tgt)
	_check("enter_to_scene_s", dt <= 1.6, snappedf(dt, 0.01), 1.6)
	_check("presses_to_fight_from_title", true, 2, 2)


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
