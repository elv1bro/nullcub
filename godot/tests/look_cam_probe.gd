## Проба камеры прохода по картинке (docs/plan-demo/look/cam.md, headless, --fixed-fps 60): KO-камера, мини-повтор, фоторежим.
## Площадка Void (быстрая), LookCam.force — KoCam ставится и в headless. Нокаут — программный (take_damage + Match.on_hit, крит
## выключен — уровень «ko»), время — кадры по 1/60 с (часы FxClock реальные).
##   A  облёт без повтора: на KO кино стартует (камера захвачена «ko_cam», время ≤ 0.05, HUD в кино, карточка KO отложена), камера
##      выходит из боковой плоскости на 40–60°, возвращается в игровую ≤ 3 с, тег времени снят, HUD и карточка KO вернулись;
##   B  облёт + повтор: стадии hold → orbit → replay → back, копии мешей есть, настоящие куклы спрятаны и вернулись, итог ≤ 6.5 с;
##   C  прерывание: R посреди облёта — камера, время и HUD как до кино;
##   D  пункты «ВИД» выключены — на KO ничего: карточка KO сразу, камера игровая;
##   E  KoCam только у обычного Match (наследники — нет), не последний нокаут — без кино;
##   F  фоторежим: клавиша / — пауза, своя камера, HUD спрятан, фильтр; Esc — выход (пауза боя не открылась), всё вернулось.
## Ловит SCRIPT ERROR (Logger). Запуск: godot --headless --path godot --fixed-fps 60 res://tests/look_cam_probe.tscn   Exit 0/1.
extends Node

const SCENE := "res://scenes/playground_void.tscn"
const TICK := 1.0 / 60.0


class ScriptErrors extends Logger:
	var count := 0
	var first := ""
	var _mx := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mx.lock()
		count += 1
		if first == "":
			first = "%s %s (%s:%d %s)" % [code, rationale, file, line, function]
		_mx.unlock()


var ok := true
var errs := ScriptErrors.new()
var look: Node
var lc: Node
var pg: Node
var m: Match
var _phys_cb := Callable()
var _saved := {}


func check(id: String, cond: bool, detail: Variant = "") -> void:
	if not cond:
		ok = false
	print("  %s %s: %s" % ["ok  " if cond else "FAIL", id, str(detail)])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.add_logger(errs)
	print("=== LOOK CAM PROBE ===")
	look = get_node_or_null("/root/Look")
	lc = get_node_or_null("/root/LookCam")
	# без --fixed-fps кадр под нагрузкой длиннее 1/60 с: кино (часы FxClock по delta) кончается раньше ожидаемых кадров — ложные FAIL.
	# Флаг движок забирает себе (в get_cmdline_args его нет) — узнаём по delta: с ним каждый кадр ровно 1/60 с
	var fixed := true
	for i in 3:
		await get_tree().process_frame
		fixed = fixed and absf(get_process_delta_time() - TICK) < 1e-6
	check("fixed_fps", fixed, "запуск с --fixed-fps 60 (иначе тайминги кино плывут под нагрузкой), delta %.4f" % get_process_delta_time())
	check("autoloads", look != null and lc != null, "Look и LookCam в автозагрузке")
	if look == null or lc == null:
		_finish()
		return
	check("look_items_lazy", not look.ids().has(&"cam_ko"), "без боя пунктов «Камера» в панели нет")
	lc.force = true
	pg = (load(SCENE) as PackedScene).instantiate()
	add_child(pg)
	check("look_items", look.ids().has(&"cam_ko") and look.ids().has(&"cam_replay") and look.ids().has(&"cam_photo")
		and look.group_of(&"cam_ko") == tr("Камера"), "бой в дереве — три пункта в группе «Камера»")
	_saved = {"master": look.master, "ko": look.checked(&"cam_ko"), "replay": look.checked(&"cam_replay"), "photo": look.checked(&"cam_photo")}
	look.set_master(true)
	m = pg.get_node_or_null("Match") as Match
	if m == null:
		for n in pg.find_children("*", "Node", true, false):
			if n is Match:
				m = n
				break
	check("match", m != null, SCENE)
	if m == null:
		_finish()
		return
	m.crit_enabled = false   # уровень удара «ko», не ko_crit (у крита своё кино)
	await _frames(3)
	var kc := m.get_node_or_null("KoCam") as KoCam
	check("kocam_attached", kc != null, "KoCam — ребёнок обычного Match")
	if kc == null:
		_finish()
		return
	await _case_a(kc)
	await _case_b(kc)
	await _case_c(kc)
	await _case_d(kc)
	await _case_e()
	await _case_f()
	_finish()


# --- помощники ---

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _physics_process(_dt: float) -> void:
	if _phys_cb.is_valid():
		var cb := _phys_cb
		_phys_cb = Callable()
		cb.call()


## Вызов в физическом тике (как DollCombat зовёт take_damage / on_hit), дождаться конца кадра.
func _in_physics(cb: Callable) -> void:
	_phys_cb = cb
	await get_tree().physics_frame
	await get_tree().process_frame


## Новый раунд: R, ждать FIGHT и набрать запись повтора (game_s игровых секунд боя).
func _fresh_round(game_s: float) -> void:
	m.restart()
	var n := 0
	while m.phase != Match.Phase.FIGHT and n < 600:
		await get_tree().process_frame
		n += 1
	await _frames(int(game_s * 60.0))


func _ko() -> void:
	var ds := m.dolls()
	var v := ds[1] as Doll
	var a := ds[0] as Doll
	await _in_physics(func() -> void:
		var pos := v.head().global_position
		v.take_damage(500.0, a, "Head", pos, Vector3.UP, "head")
		m.on_hit(v, a, 500.0, "head", pos, 1, false, "", 8.0))


func _set_items(ko: bool, replay: bool) -> void:
	look.set_on(&"cam_ko", ko)
	look.set_on(&"cam_replay", replay)


func _hud() -> Node:
	return get_tree().get_first_node_in_group("hud")


func _view_cam() -> Camera3D:
	return get_viewport().get_camera_3d()


# --- A: облёт без повтора ---

func _case_a(kc: KoCam) -> void:
	print("-- A: облёт")
	_set_items(true, false)
	await _fresh_round(1.0)
	var gc := m.game_camera()
	var plays0 := kc.plays
	await _ko()
	var hud := _hud()
	check("A_started", kc.playing and kc.plays == plays0 + 1 and kc.stage == "hold", "playing=%s stage=%s" % [kc.playing, kc.stage])
	check("A_camera_captured", m.camera_owner() == KoCam.TAG and _view_cam() == kc.cam, "owner=%s" % m.camera_owner())
	check("A_time_stopped", m.time_scale_tags().has(KoCam.TAG) and Engine.time_scale <= 0.05, "ts=%.3f tags=%s" % [Engine.time_scale, m.time_scale_tags()])
	check("A_hud_cinematic", hud != null and bool(hud.call("is_cinematic")), "HUD спрятан")
	var card := hud.get("ko_card") as KoCard if hud != null else null
	check("A_ko_card_deferred", card != null and not card.visible and card.remaining_s() > kc.planned_s, "card visible=%s remaining=%.2f planned=%.2f" % [card.visible if card else null, card.remaining_s() if card else -1.0, kc.planned_s])
	var max_angle := 0.0
	var f := 0
	var back_f := -1
	var fov_min := 999.0
	while f < 300:
		await get_tree().process_frame
		f += 1
		if kc.stage == "orbit":
			max_angle = maxf(max_angle, kc.view_angle_deg())
			fov_min = minf(fov_min, kc.cam.fov)
		if not kc.playing:
			back_f = f
			break
	var secs := float(back_f) * TICK
	check("A_orbit_angle", max_angle >= 40.0 and max_angle <= 60.0, "%.1f° (40–60)" % max_angle)
	check("A_fov_tightens", fov_min < gc.fov, "fov %.1f → %.1f" % [gc.fov, fov_min])
	check("A_back_in_3s", back_f > 0 and secs <= 3.0, "%.2f с (≤ 3)" % secs)
	check("A_stage_back", kc.stage == "back" and kc.completed >= 1, kc.stage)
	check("A_camera_released", m.camera_owner() == "" and _view_cam() == gc, "owner=%s" % m.camera_owner())
	check("A_time_tag_gone", not m.time_scale_tags().has(KoCam.TAG), m.time_scale_tags())
	check("A_hud_back", hud != null and not bool(hud.call("is_cinematic")), "HUD вернулся")
	await _frames(3)
	check("A_ko_card_shown", card != null and card.visible, "карточка KO после щелчка назад")
	await _frames(60)
	check("A_time_released", Engine.time_scale > 0.99 and not m.time_scale_tags().has(KoCam.TAG_OUT), "ts=%.2f" % Engine.time_scale)


# --- B: облёт + повтор ---

func _case_b(kc: KoCam) -> void:
	print("-- B: облёт + повтор")
	_set_items(true, true)
	await _fresh_round(2.0)
	check("B_recorded", kc.recorded_frames() >= 60, "кадров записи %d" % kc.recorded_frames())
	var stages: Array = []
	var cb := func(s: String) -> void: stages.append(s)
	kc.stage_changed.connect(cb)
	await _ko()
	var planned := kc.planned_s
	var f := 0
	var dolls_hidden := false
	var ghosts := 0
	var prog_last := -1.0
	var prog_mono := true
	while f < 600 and kc.playing:
		await get_tree().process_frame
		f += 1
		if kc.stage == "replay":
			ghosts = maxi(ghosts, kc.ghost_count)
			var all_hidden := true
			for d in m.dolls():
				all_hidden = all_hidden and not (d as Node3D).visible
			dolls_hidden = dolls_hidden or all_hidden
			var p := kc.replay_progress()
			prog_mono = prog_mono and p >= prog_last - 1e-4
			prog_last = p
	kc.stage_changed.disconnect(cb)
	var secs := float(f) * TICK
	check("B_stages", stages == ["hold", "orbit", "replay", "back"], stages)
	check("B_ghosts", ghosts >= 10, "копий мешей %d" % ghosts)
	check("B_dolls_hidden", dolls_hidden, "в повторе настоящие куклы спрятаны")
	check("B_progress", prog_mono and prog_last >= 0.99, "прогресс повтора монотонный, дошёл до %.2f" % prog_last)
	check("B_duration", not kc.playing and secs <= planned + 0.1 and secs <= 6.5, "%.2f с (план %.2f, ≤ 6.5)" % [secs, planned])
	await _frames(2)
	var vis := true
	for d in m.dolls():
		vis = vis and (d as Node3D).visible
	check("B_dolls_back", vis, "куклы снова видны")
	check("B_ghosts_freed", kc.get_node_or_null("ReplayGhosts") == null, "копии убраны")
	check("B_camera_released", m.camera_owner() == "" and _view_cam() == m.game_camera(), "owner=%s" % m.camera_owner())
	await _frames(60)


# --- C: прерывание ---

func _case_c(kc: KoCam) -> void:
	print("-- C: прерывание R")
	_set_items(true, true)
	await _fresh_round(1.0)
	await _ko()
	await _frames(30)
	check("C_playing", kc.playing, kc.stage)
	m.restart()
	await _frames(2)
	var hud := _hud()
	check("C_aborted", not kc.playing and kc.stage == "abort", kc.stage)
	check("C_camera_released", m.camera_owner() == "" and _view_cam() == m.game_camera(), "owner=%s" % m.camera_owner())
	check("C_time", not m.time_scale_tags().has(KoCam.TAG) and Engine.time_scale > 0.99, "ts=%.2f tags=%s" % [Engine.time_scale, m.time_scale_tags()])
	check("C_hud", hud != null and not bool(hud.call("is_cinematic")), "HUD не в кино")
	var vis := true
	for d in m.dolls():
		vis = vis and (d as Node3D).visible
	check("C_dolls_visible", vis, "куклы видны")


# --- D: пункты выключены ---

func _case_d(kc: KoCam) -> void:
	print("-- D: пункты «ВИД» выключены")
	_set_items(false, false)
	await _fresh_round(1.0)
	var plays0 := kc.plays
	await _ko()
	await _frames(2)
	var card := _hud().get("ko_card") as KoCard
	check("D_no_cinema", not kc.playing and kc.plays == plays0, "plays %d → %d" % [plays0, kc.plays])
	check("D_camera_game", m.camera_owner() == "" and _view_cam() == m.game_camera(), "камера игровая")
	check("D_ko_card_now", card != null and card.visible, "карточка KO сразу")
	look.set_master(false)
	await _fresh_round(1.2)
	_set_items(true, true)
	await _ko()
	await _frames(2)
	check("D_master_off", not kc.playing and kc.plays == plays0, "рубильник «как было» — без кино")
	look.set_master(true)
	await _frames(30)


# --- E: где KoCam работает ---

func _case_e() -> void:
	print("-- E: только обычный бой, только последний нокаут")
	var wd: Node = (load("res://scripts/pve/wave_director.gd") as GDScript).new()
	check("E_plain_match", lc.call("plain_match", m) and not lc.call("plain_match", wd), "Match — да, WaveDirector — нет")
	wd.free()
	# не последний нокаут: третья кукла жива — кино нет
	_set_items(true, false)
	await _fresh_round(1.2)
	var kc := m.get_node("KoCam") as KoCam
	var extra := (load("res://scenes/doll/doll.tscn") as PackedScene).instantiate() as Doll
	extra.player_index = 2
	extra.input_prefix = "p3"
	extra.position = Vector3(0.0, 4.0, 0.0)
	pg.add_child(extra)
	extra.add_to_group("dolls")
	m.register(extra)
	await _frames(3)
	var plays0 := kc.plays
	await _ko()
	await _frames(2)
	check("E_not_last_ko", not kc.playing and kc.plays == plays0 and m.alive_dolls().size() == 2, "живых %d, plays %d → %d" % [m.alive_dolls().size(), plays0, kc.plays])
	extra.queue_free()
	await _frames(2)


# --- F: фоторежим ---

func _case_f() -> void:
	print("-- F: фоторежим")
	await _fresh_round(1.2)
	var gc := m.game_camera()
	var hud := _hud() as CanvasLayer
	look.set_on(&"cam_photo", false)
	_key(KEY_SLASH)
	await _frames(1)
	check("F_off_no_photo", not lc.call("photo_active") and not get_tree().paused, "пункт выключен — клавиша / ничего не делает")
	look.set_on(&"cam_photo", true)
	_key(KEY_SLASH)
	await _frames(2)
	var pm := lc.get("photo") as PhotoMode
	check("F_enter", pm != null and pm.active and get_tree().paused, "фоторежим и пауза")
	if pm == null or not pm.active:
		return
	check("F_camera", _view_cam() == pm.cam, "своя камера")
	check("F_hud_hidden", hud != null and not hud.visible and pm.hidden_count > 0, "HUD спрятан, слоёв %d" % pm.hidden_count)
	var t0 := pm.cam.global_transform
	pm.orbit_by(0.6, 0.2, 1.3)
	await _frames(2)
	check("F_orbit", pm.cam.global_transform.origin.distance_to(t0.origin) > 0.5, "камера сдвинулась на %.2f м" % pm.cam.global_transform.origin.distance_to(t0.origin))
	check("F_focus", pm.focus_distance() > 0.5, "фокус %.2f м" % pm.focus_distance())
	_key(KEY_3)
	await _frames(1)
	check("F_filter", pm.filter == 2 and pm._filter_layer.visible, "фильтр %d" % pm.filter)
	_key(KEY_C)
	await _frames(1)
	check("F_frame_toggle", not pm.frame_on and not pm._frame_layer.visible, "рамка выкл")
	_key(KEY_C)
	_key(KEY_ESCAPE)
	await _frames(2)
	var flow := get_node_or_null("/root/Flow")
	check("F_exit_esc", not pm.active and not get_tree().paused, "Esc — выход, пауза снята")
	check("F_no_pause_menu", flow == null or not bool(flow.call("is_paused")), "пауза боя не открылась")
	check("F_restored", hud != null and hud.visible and _view_cam() == gc, "HUD и игровая камера вернулись")
	_key(KEY_SLASH)
	await _frames(1)
	_key(KEY_SLASH)
	await _frames(1)
	check("F_toggle_slash", not pm.active and not get_tree().paused, "/ — вход и выход той же клавишей")


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	get_viewport().push_input(e)
	var r := e.duplicate() as InputEventKey
	r.pressed = false
	get_viewport().push_input(r)


func _finish() -> void:
	if lc != null:
		lc.force = false
	if look != null and not _saved.is_empty():
		look.set_on(&"cam_ko", bool(_saved["ko"]))
		look.set_on(&"cam_replay", bool(_saved["replay"]))
		look.set_on(&"cam_photo", bool(_saved["photo"]))
		look.set_master(bool(_saved["master"]))
	get_tree().paused = false
	check("no_script_errors", errs.count == 0, "SCRIPT ERROR: %d %s" % [errs.count, errs.first])
	print("=== %s ===" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
