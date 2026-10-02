## Проба мастерской внутри гаража меню (scenes/menu/garage_workshop.gd, docs/plan-demo/MENU_GARAGE.md §0) без окна:
##   godot --headless --path godot res://tests/garage_workshop_probe.tscn
## Сценарий: гараж → мастерская грузится в фоне и встаёт в мир спящей → «МАСТЕРСКАЯ» (Enter): состояние workshop, камера у
## мастерской без скачка, кукла игрока встала с ящика → правка сборки → «Испытать»: кукла оживает на полу гаража в плоскости
## z = 0, не проваливается, манекен и камера есть → назад к сборке → двойной Esc: обратно в меню, камера гаража, кукла на ящике
## пересобрана по новой сборке, мастерская уснула. Автосейв и настройки мастерской — свои probe-файлы (сборка игрока не трогается).
## В stdout «=== GARAGE WORKSHOP PROBE ===» и JSON; exit 0 — всё ок.
extends Node

const MENU := preload("res://scenes/menu/garage_menu.tscn")
const PROBE_BP := "_probe_gw"

var menu: GarageMenu
var checks: Array = []


func _ready() -> void:
	WorkshopBuild.prefs_path = "user://_probe_gw_prefs.cfg"
	menu = MENU.instantiate() as GarageMenu
	menu.dry_run = true
	menu.live_tv = false
	add_child(menu)
	menu.workshop.ws_overrides = {"autosave_name": PROBE_BP, "load_autosave": false, "start_preset": "kit_human"}
	(menu.player_doll as GarageDoll).blueprint_path = CraftEdit.save_path(PROBE_BP)
	await get_tree().process_frame
	await _run()
	var ok := true
	for c in checks:
		ok = ok and bool(c["ok"])
	for f in [CraftEdit.save_path(PROBE_BP), ProjectSettings.globalize_path("user://_probe_gw_prefs.cfg")]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	print("=== GARAGE WORKSHOP PROBE ===")
	print(JSON.stringify({"ok": ok, "checks": checks}))
	print("=== OK ===" if ok else "=== FAIL ===")
	get_tree().quit(0 if ok else 1)


func _check(id: String, ok: bool, value = null, limit = null) -> void:
	checks.append({"id": id, "ok": ok, "value": value, "limit": limit})
	if not ok:
		push_warning("garage_workshop_probe FAIL: %s value=%s limit=%s" % [id, str(value), str(limit)])


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame


func _wait(cond: Callable, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < timeout_s * 1000.0:
		await get_tree().process_frame
	return cond.call()


func _run() -> void:
	var w := menu.workshop
	# 1. фоновая загрузка и постановка спящей мастерской
	_check("loads_in_background", await _wait(func() -> bool: return w.ws != null, 60.0), [w.load_ms, w.inst_ms])
	var ws := w.ws
	if ws == null:
		return
	_check("sleeps_in_menu", not ws.active and not ws.visible and ws.process_mode == Node.PROCESS_MODE_DISABLED,
		[ws.active, ws.visible, ws.process_mode])
	_check("embedded_no_arena", ws.embedded and ws.arena == null, [ws.embedded, ws.arena])
	_check("garage_cam_current", menu.cam.is_current() and not ws.build_cam.is_current(), null)
	# 2. вход: Enter на «Мастерской»
	menu.enter_menu()
	await _wait(func() -> bool: return not menu.is_moving(), 4.0)
	await _key(KEY_3)
	_check("focus_workshop", menu.focus == 2, menu.focus, 2)
	await _wait(func() -> bool: return not menu.is_moving(), 4.0)
	await _key(KEY_ENTER)
	_check("state_workshop", menu.state == "workshop", menu.state)
	var opened := await _wait(func() -> bool: return ws.build_cam.is_current(), 4.0)
	_check("camera_handed_over", opened and not menu.cam.is_current(), opened)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("ws_awake", ws.active and ws.visible and ws.process_mode == Node.PROCESS_MODE_INHERIT, [ws.active, ws.visible])
	var d := ws.build_cam.global_position.distance_to(menu.cam.global_position)
	_check("no_camera_jump_m", d < 0.15, snappedf(d, 0.001), 0.15)
	var sp := ws.snap_camera_pose().origin
	var dd := ws.build_cam.global_position.distance_to(sp)
	_check("camera_at_build_frame_m", dd < 0.6, snappedf(dd, 0.001), 0.6)
	_check("stand_doll_built", ws.stand != null and ws.stand.global_position.distance_to(ws.stand_root.global_position) < 0.5, null)
	_check("garage_doll_hidden", not menu.player_doll.visible, null)
	_check("garage_input_idle", menu.state == "workshop", null)
	var ui_layer := ws.get_node("UI") as CanvasLayer
	_check("ui_visible", ui_layer.visible and not menu.ui.visible, [ui_layer.visible, menu.ui.visible])
	# 3. правка сборки
	var title_before := ws.blueprint.title
	_check("set_preset", ws.set_preset("kit_brawler"), null)
	await get_tree().process_frame
	_check("blueprint_changed", ws.blueprint.title != title_before or ws.blueprint.id == "kit_brawler", [ws.blueprint.id, ws.blueprint.title])
	var parts_after := ws.blueprint.nodes.size()
	# 4. испытание: зал за воротами готовится под лоадером (первый старт — false), потом испытание стартует само
	var first := ws.start_test()
	_check("first_test_waits_for_hall", not first and Loading.showing, [first, Loading.showing])
	var started := await _wait(func() -> bool: return ws.mode == WorkshopBuild.Mode.TEST, 60.0)
	_check("start_test", started, null)
	var hall: TrainingHall = w.hall
	_check("hall_in_world", hall != null and hall.get_parent() == menu and hall.awake, [w.hall_inst_ms])
	if started:
		for i in 150:
			await get_tree().physics_frame
		var torso := ws.test_doll.parts["Torso"] as Node3D
		var y := torso.global_position.y
		var z := torso.global_position.z
		_check("test_doll_on_floor", y > 0.25 and y < 2.2, snappedf(y, 0.01), [0.25, 2.2])
		_check("test_doll_on_plane_z0", absf(z) < 0.25, snappedf(z, 0.01), 0.25)
		_check("test_dummy_in_hall", ws.dummy != null and is_instance_valid(ws.dummy) and ws.dummy.global_position.x < -10.0,
			ws.dummy.global_position.x if ws.dummy != null else null)
		_check("test_camera_current", ws.test_cam != null and ws.test_cam.is_current(), null)
		var b := ws.test_cam.bounds()
		_check("test_bounds_from_stage", b.size.x > 40.0 and b.size.y > 8.0, [b.size.x, b.size.y])
		var lit := true
		for l in menu.zone_lights.get("tv", []):
			lit = lit and (l as Light3D).light_energy > 0.0
		_check("test_zone_lights_even", lit, null)
		# ворота в зал: створки открылись, заглушка проёма снята
		var gate := menu.get_node("Room/HallGate") as GarageHallGate
		_check("gate_opened", gate.is_open, null)
		var block := ws.get_node("Stage/Bounds/WallL") as CollisionShape3D
		_check("door_block_off_when_open", block.disabled, null)
		# вылет в зал: сильный толчок влево и вверх через ворота (кукла гасит скорость трением, меряем дальность)
		for bd in ws.test_doll.parts.values():
			(bd as RigidBody3D).linear_velocity = Vector3(-20.0, 3.0, 0.0)
		var x_out := 0.0
		for i in 120:
			await get_tree().physics_frame
			x_out = minf(x_out, (ws.test_doll.parts["Torso"] as Node3D).global_position.x)
		_check("doll_flew_into_hall", x_out < -7.0, snappedf(x_out, 0.1), -7.0)
		_check("speed_screen_got_data", float(hall.screens["speed"]._data.get("vmax", 0.0)) > 2.0, hall.screens["speed"]._data.get("vmax", 0.0))
		# груша: подвести куклу к груше (x = −30) и ударить на скорости
		var dx := -26.5 - (ws.test_doll.parts["Torso"] as Node3D).global_position.x
		for bd in ws.test_doll.parts.values():
			(bd as RigidBody3D).global_position += Vector3(dx, 0.4, 0.0)
			(bd as RigidBody3D).linear_velocity = Vector3(-14.0, 0.0, 0.0)
		var hit := await _wait(func() -> bool: return hall.bag.hits > 0, 6.0)
		_check("bag_registered_hit", hit, [hall.bag.hits, snappedf(hall.bag.best_force_n, 1.0)])
		await get_tree().create_timer(0.5).timeout
		var imp: Dictionary = hall.screens["impact"]._data
		_check("impact_screen_shows_force", float(imp.get("f_n", 0.0)) > 100.0 and int(imp.get("hits", 0)) > 0, imp.get("f_n", 0.0))
		ws.stop_test()
		await get_tree().process_frame
		_check("stop_test_back_to_build", ws.mode == WorkshopBuild.Mode.BUILD and ws.build_cam.is_current(), ws.mode)
		_check("hall_asleep_after_test", not hall.awake and not hall.visible, null)
		await get_tree().create_timer(0.1).timeout
		_check("gate_closed_after_test", not gate.is_open and not block.disabled, [gate.is_open, block.disabled])
	# 5. двойной Esc → обратно в меню
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	var back := await _wait(func() -> bool: return menu.state == "menu", 3.0)
	if not back:   # Esc мог уйти на отмену жеста — повторить как «ещё раз»
		await _key(KEY_ESCAPE)
		await _key(KEY_ESCAPE)
		back = await _wait(func() -> bool: return menu.state == "menu", 3.0)
	_check("double_esc_returns_to_menu", back, menu.state)
	_check("menu_cam_back", menu.cam.is_current() and not ws.build_cam.is_current(), null)
	_check("ws_asleep_again", not ws.active and not ws.visible, [ws.active, ws.visible])
	_check("menu_ui_back", menu.ui.visible and menu.menu_box.visible and is_equal_approx(menu.ui.modulate.a, 1.0), null)
	_check("garage_doll_back", menu.player_doll.visible, null)
	await _wait(func() -> bool: return not menu.is_moving(), 4.0)
	var at := menu.cam.global_position.distance_to(menu.spot_transform("Workshop").origin)
	_check("camera_back_at_menu_spot_m", at < 0.05, snappedf(at, 0.001), 0.05)
	var pd := menu.player_doll
	_check("garage_doll_rebuilt_from_workshop", pd.blueprint_source == "path" and pd.doll.blueprint.nodes.size() == parts_after,
		[pd.blueprint_source, pd.doll.blueprint.nodes.size(), parts_after])
	# 6. повторный вход: мгновенно, без новой загрузки
	var t0 := Time.get_ticks_msec()
	menu.activate()
	var again := await _wait(func() -> bool: return ws.build_cam.is_current(), 4.0)
	_check("reopen_same_instance", again and menu.workshop.ws == ws, snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.01))
	menu.workshop.close()
	_check("close_api", menu.state == "menu" and not ws.active, menu.state)
