## Проба кампании в эфире телевизора гаража (scenes/menu/garage_campaign.gd, docs/plan-demo/MENU_GARAGE.md) без окна:
##   godot --headless --path godot res://tests/garage_campaign_probe.tscn
## Сценарий через настоящий ввод: гараж → «ИСТОРИЯ» (Enter) → нырок в ТВ → сетка лиги → бой ставится в мир гаража (комната
## спрятана, камера боя) → победа (запись, трофей, сохранение) → итоги → мастерская кампании (полка = кит + трофеи, Esc — к сетке) →
## поражение (лестница стоит) → сдача боя → новая кампания → лига пройдена → выход в меню (камера у пункта, строки обновились).
## Кампания и мастерская пишут в свои probe-файлы (сборка игрока не трогается). В stdout «=== GARAGE CAMPAIGN PROBE ===» и JSON.
extends Node

const MENU := preload("res://scenes/menu/garage_menu.tscn")
const SAVE := "user://_probe_gc.tres"
const BP := "_probe_gc"

var menu: GarageMenu
var checks: Array = []


func _ready() -> void:
	WorkshopBuild.prefs_path = "user://_probe_gc_prefs.cfg"
	menu = MENU.instantiate() as GarageMenu
	menu.dry_run = true
	menu.live_tv = false
	add_child(menu)
	menu.campaign.save_path = SAVE
	menu.campaign.bp_name = BP
	menu.campaign.load_save = false
	menu.campaign.entrance_enabled = false
	menu.workshop.ws_overrides = {"autosave_name": "_probe_gc_free", "load_autosave": false, "start_preset": "kit_human"}
	await get_tree().process_frame
	await _run()
	var ok := true
	for c in checks:
		ok = ok and bool(c["ok"])
	for f in [SAVE, CraftEdit.save_path(BP), CraftEdit.save_path("_probe_gc_free"), "user://_probe_gc_prefs.cfg"]:
		var g := ProjectSettings.globalize_path(f)
		if FileAccess.file_exists(g):
			DirAccess.remove_absolute(g)
	print("=== GARAGE CAMPAIGN PROBE ===")
	print(JSON.stringify({"ok": ok, "checks": checks}))
	print("=== OK ===" if ok else "=== FAIL ===")
	get_tree().quit(0 if ok else 1)


func _check(id: String, ok: bool, value = null, limit = null) -> void:
	checks.append({"id": id, "ok": ok, "value": value, "limit": limit})
	if not ok:
		push_warning("garage_campaign_probe FAIL: %s value=%s limit=%s" % [id, str(value), str(limit)])


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame


## Игрок — тоже бот (RivalBrain уровня 4), бой идёт до конца матча; как real_fight в campaign_probe.
func _real_fight(c: GarageCampaign) -> void:
	var step0 := c.state.step
	var fights0 := c.state.fights.size()
	c.start_fight()
	await _wait(func() -> bool: return c.fight != null and c.fight.is_inside_tree(), 60.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var p1: ModularDoll = c.fight.get_node("P1")
	(c.fight.get_node("Match") as Match).feel_enabled = false
	var pb := RivalBrain.new()
	pb.name = "ProbeBrain"
	pb.level = 4
	p1.add_child(pb)
	await get_tree().physics_frame
	await get_tree().physics_frame
	pb.players_group = "rivals"
	pb.enemies_group = "players"
	var t := 0.0
	while t < 200.0 and c.fight != null:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	var rec: Dictionary = c.state.fights[c.state.fights.size() - 1] if c.state.fights.size() > fights0 else {}
	var advanced := c.state.step == step0 + 1 if bool(rec.get("won", false)) else c.state.step == step0
	_check("real_fight_to_outcome", not rec.is_empty() and advanced and c.screen == GarageCampaign.Screen.OUTCOME and c.ui.screen_id == "outcome",
		[snappedf(t, 0.1), rec, c.screen])
	_check("real_fight_world_restored", menu.get_node("Room").visible and menu.cam.is_current(), null)


func _wait(cond: Callable, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < timeout_s * 1000.0:
		await get_tree().process_frame
	return cond.call()


func _run() -> void:
	var c := menu.campaign
	var gw := menu.workshop
	# 1. вход: «ИСТОРИЯ» → нырок в телевизор → сетка
	menu.enter_menu()
	await _wait(func() -> bool: return not menu.is_moving(), 4.0)
	_check("focus_story", menu.focus == 0, menu.focus, 0)
	await _key(KEY_ENTER)
	_check("state_campaign", menu.state == "campaign", menu.state)
	var in_ladder := await _wait(func() -> bool: return c.screen == GarageCampaign.Screen.LADDER, 4.0)
	_check("ladder_after_dive", in_ladder, c.screen)
	var at_tv := menu.cam.global_position.distance_to(menu.spot_transform("IntoTV").origin)
	_check("camera_at_tv_m", at_tv < 0.05, snappedf(at_tv, 0.001), 0.05)
	_check("garage_ui_hidden", not menu.ui.visible, null)
	_check("tv_ui_ladder", c.ui.screen_id == "ladder" and c.ui.buttons.size() == 4, [c.ui.screen_id, c.ui.buttons.size()])
	_check("fight_button_ready", not (c.ui.buttons[0] as Button).disabled, null)
	_check("new_campaign_state", c.state.step == 0 and c.state.wins == 0, [c.state.step, c.state.wins])
	_check("shared_with_garage", menu._campaign == c.state, null)
	# 2. бой ставится в тот же мир
	_check("start_fight_accepted", c.start_fight(), null)
	_check("connecting_screen", c.ui.screen_id == "connecting", c.ui.screen_id)
	var fought := await _wait(func() -> bool: return c.fight != null and is_instance_valid(c.fight) and c.fight.is_inside_tree(), 60.0)
	_check("fight_in_garage_tree", fought and c.fight.get_parent() == menu, [c.fight_load_ms])
	if fought:
		_check("room_hidden_in_fight", not menu.get_node("Room").visible and not menu.get_node("Props").visible and not menu.get_node("Lights").visible, null)
		for i in 30:
			await get_tree().physics_frame
		var vcam := get_viewport().get_camera_3d()
		_check("fight_camera_current", vcam != null and vcam != menu.cam, str(vcam))
		_check("no_garage_env_in_fight", (menu.get_node("WorldEnvironment") as WorldEnvironment).environment == null, null)
		_check("overlay_on_in_fight", c.ui._overlay_layer.visible and not c.ui._screens.visible, null)
	# 3. победа → итоги, трофей, сохранение
	c.finish_fight(true, {"won": true, "duration_s": 47.0, "reason": "ko"})
	_check("fight_freed", c.fight == null, null)
	_check("room_back_after_fight", menu.get_node("Room").visible and menu.get_node("Props").visible, null)
	_check("garage_cam_current_again", menu.cam.is_current(), null)
	_check("env_back", (menu.get_node("WorldEnvironment") as WorldEnvironment).environment != null, null)
	_check("outcome_screen", c.screen == GarageCampaign.Screen.OUTCOME and c.ui.screen_id == "outcome", c.ui.screen_id)
	_check("step_advanced", c.state.step == 1 and c.state.wins == 1, [c.state.step, c.state.wins])
	_check("trophy_given", c.last_trophy != "" and c.state.trophies.has(c.last_trophy), c.last_trophy)
	_check("saved", FileAccess.file_exists(SAVE), null)
	# 4. мастерская кампании
	c.open_workshop()
	_check("workshop_screen", c.screen == GarageCampaign.Screen.WORKSHOP and menu.state == "workshop", [c.screen, menu.state])
	var ws := gw.ws
	var woke := await _wait(func() -> bool: return ws != null and ws.active and ws.build_cam.is_current(), 6.0)
	_check("workshop_camera_handover", woke, null)
	if ws != null:
		_check("campaign_autosave_name", ws.autosave_name == BP, ws.autosave_name)
		_check("campaign_shelf_set", CraftEdit.campaign_shelf.size() > 0 and CraftEdit.campaign_templates_locked and ws.single_esc_exit,
			[CraftEdit.campaign_shelf.size(), CraftEdit.campaign_templates_locked, ws.single_esc_exit])
		_check("trophy_on_shelf", CraftEdit.campaign_shelf.has(c.last_trophy), c.last_trophy)
		_check("campaign_bar", c.ui.screen_id == "workshop" and c.ui.buttons.size() == 2, [c.ui.screen_id, c.ui.buttons.size()])
		_check("regulation_budget", ws.blueprint.energy_budget == CampaignLeague.energy_budget(c.state.tier), ws.blueprint.energy_budget)
		await _key(KEY_ESCAPE)
		var back := await _wait(func() -> bool: return c.screen == GarageCampaign.Screen.LADDER, 4.0)
		_check("esc_returns_to_ladder", back, c.screen)
		_check("workshop_asleep", not ws.active and menu.state == "campaign", [ws.active, menu.state])
		_check("statics_reset", CraftEdit.campaign_shelf.is_empty() and not CraftEdit.campaign_templates_locked and ws.autosave_name == "_probe_gc_free" and not ws.single_esc_exit,
			[CraftEdit.campaign_shelf.size(), CraftEdit.campaign_templates_locked, ws.autosave_name])
		_check("garage_ui_stays_hidden", not menu.ui.visible, null)
		await _wait(func() -> bool: return not menu.is_moving(), 4.0)
		var at2 := menu.cam.global_position.distance_to(menu.spot_transform("IntoTV").origin)
		_check("camera_back_at_tv_m", at2 < 0.05, snappedf(at2, 0.001), 0.05)
	# 5. поражение: лестница стоит; сдача боя
	c.finish_fight(false, {"won": false, "duration_s": 12.0})
	_check("loss_keeps_step", c.state.step == 1 and c.state.losses == 1, [c.state.step, c.state.losses])
	c.show_ladder()
	c.start_fight()
	await _wait(func() -> bool: return c.fight != null and c.fight.is_inside_tree(), 60.0)
	c.fight.emit_signal("fight_abandoned")
	_check("surrender_to_ladder", c.screen == GarageCampaign.Screen.LADDER and c.fight == null and menu.get_node("Room").visible, c.screen)
	# 5б. настоящий бой двух ботов до конца матча: итоги HUD → fight_finished → экран итогов кампании
	c.show_ladder()
	await _real_fight(c)
	# 6. новая кампания и лига целиком
	c.new_campaign(7)
	_check("new_campaign_reset", c.state.step == 0 and c.state.wins == 0 and c.state.trophies.is_empty(), null)
	for i in c.state.ladder().size():
		c.finish_fight(true, {"won": true, "duration_s": 30.0})
	_check("league_finished", c.state.finished(), c.state.step)
	_check("outcome_without_next", c.ui.screen_id == "outcome" and not (c.ui.buttons[0] as Button).visible, null)
	c.show_ladder()
	_check("fight_disabled_when_finished", (c.ui.buttons[0] as Button).disabled, null)
	# 7. Esc на сетке — в меню гаража
	await _key(KEY_ESCAPE)
	var out := await _wait(func() -> bool: return menu.state == "menu", 4.0)
	_check("esc_from_ladder_exits", out and not c.is_open, menu.state)
	_check("menu_ui_back", menu.ui.visible and menu.menu_box.visible, null)
	await _wait(func() -> bool: return not menu.is_moving(), 4.0)
	var at3 := menu.cam.global_position.distance_to(menu.spot_transform("Story").origin)
	_check("camera_back_at_story_m", at3 < 0.05, snappedf(at3, 0.001), 0.05)
	var d1: String = ((menu.item_nodes[0] as Dictionary)["d1"] as Label).text
	_check("story_lines_refreshed", d1.contains("пройдена"), d1)
	_check("overlay_off", not c.ui._overlay_layer.visible and not c.ui._screens.visible, null)
	# 8. повторный вход работает
	menu.activate()
	var again := await _wait(func() -> bool: return c.screen == GarageCampaign.Screen.LADDER, 4.0)
	_check("reopen_ok", again and c.state.finished(), c.screen)
	c.close()
