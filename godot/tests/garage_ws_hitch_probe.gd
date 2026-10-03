## Подвисания мастерской В ГАРАЖЕ — так, как их видит игрок (scenes/menu/garage_workshop.gd): гараж запускается, мастерская грузится в фоне и ставится
## в мир, игрок входит («МАСТЕРСКАЯ»), крутит сборку, жмёт «Испытать» и «назад», выходит. Для каждой фазы — самый долгий кадр (реальные часы) и список кадров > порога.
## ОКНО:  godot/tools/godot_nofocus.sh --path godot --resolution 1280x720 res://tests/garage_ws_hitch_probe.tscn -- "limit_ms=150"
## Фазы: старт гаража (фон + постановка мастерской) → пункт меню → вход (нырок + передача камеры) → сборка (3 с, открутка и Ctrl+Z) → «Испытать» →
## назад → второе «Испытать» → назад → выход в меню. exit 1, если: постановка мастерской в мир дольше INST_MAX_MS (было 720–830 мс, пока 157 PartDef читались
## с диска синхронно; теперь ≈ 90); библиотека не достроена; какая-то фаза хуже limit_ms (150 мс), кроме двух с ПЕРВЫМ показом (PHASE_LIMITS: вход в мастерскую
## и первое «Испытать» — Metal собирает пайплайны мира мастерской и полигона прямо в кадре, ≈ 250–450 мс; не лечится без прогрева в видимом кадре, см. PERF_PASS.md §11).
## Старт гаража (первый кадр процесса) не считается.
## Автосейв — probe-файл (сборка игрока не трогается).
extends Node

const MENU := preload("res://scenes/menu/garage_menu.tscn")
var menu: GarageMenu
var limit_ms := 150.0
const INST_MAX_MS := 300
const PHASE_LIMITS := {"вход в мастерскую": 600.0, "«Испытать»": 600.0}
var last_us := 0
var phase := "старт гаража"
var worst: Dictionary = {}
var slow: Array = []
var order: Array = []
var _library_ok := false
var _inst_bad := false
var frames_after: Array = []   # кадры (мс) после последнего действия, первые 8
var calls: Dictionary = {}     # фаза -> мс самого вызова


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "limit_ms":
				limit_ms = float(p[1])
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	WorkshopBuild.prefs_path = "user://_probe_gwh_prefs.cfg"
	menu = MENU.instantiate() as GarageMenu
	menu.dry_run = true
	add_child(menu)
	menu.workshop.ws_overrides = {"autosave_name": "_probe_gwh", "load_autosave": false, "start_preset": "kit_brawler"}
	(menu.player_doll as GarageDoll).blueprint_path = CraftEdit.save_path("_probe_gwh")
	last_us = Time.get_ticks_usec()
	_run.call_deferred()


func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := float(now - last_us) / 1000.0
	last_us = now
	if not worst.has(phase):
		worst[phase] = 0.0
		order.append(phase)
	worst[phase] = maxf(float(worst[phase]), dt)
	if frames_after.size() < 8:
		frames_after.append(snappedf(dt, 0.1))
		if frames_after.size() == 8:
			print("GWH   %s: первые кадры %s" % [phase, str(frames_after)])
	if dt > 60.0:
		slow.append([phase, snappedf(dt, 0.1)])


func _pipes() -> Array:
	var out: Array = []
	for c in [Performance.PIPELINE_COMPILATIONS_CANVAS, Performance.PIPELINE_COMPILATIONS_MESH, Performance.PIPELINE_COMPILATIONS_SURFACE,
			Performance.PIPELINE_COMPILATIONS_DRAW, Performance.PIPELINE_COMPILATIONS_SPECIALIZATION]:
		out.append(int(Performance.get_monitor(c)))
	return out


var _pipes_at: Array = [0, 0, 0, 0, 0]


func _set_phase(p: String) -> void:
	if phase != "" and not order.is_empty():
		var now := _pipes()
		var d: Array = []
		for i in range(5):
			d.append(int(now[i]) - int(_pipes_at[i]))
		print("GWH   пайплайны за фазу «%s» canvas/mesh/surface/draw/spec: %s" % [phase, str(d)])
	_pipes_at = _pipes()
	phase = p
	frames_after = []


func _timed(label: String, f: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	f.call()
	print("GWH   вызов %s: %.1f мс" % [label, float(Time.get_ticks_usec() - t0) / 1000.0])


func _idle(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _run() -> void:
	var w := menu.workshop
	var t0 := Time.get_ticks_msec()
	while w.ws == null and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	print("GWH фон: загрузка %d мс, постановка в мир %d мс (предел %d)" % [w.load_ms, w.inst_ms, INST_MAX_MS])
	if w.inst_ms < 0 or w.inst_ms > INST_MAX_MS:
		_inst_bad = true
	await _idle(1.0)
	_set_phase("пункт меню")
	menu.enter_menu()
	menu.set_focus(2, true)
	await _idle(1.5)
	_set_phase("вход в мастерскую")
	_timed("activate", menu.activate)
	while menu.state == "workshop" and not w.ws.build_cam.is_current():
		await get_tree().process_frame
	await _idle(1.5)
	var filled: bool = not bool(w.ws.ui.call("cards_pending")) and int(w.ws.ui.get("_cards").size()) >= 100
	print("GWH библиотека: %d карточек, достроена: %s" % [int(w.ws.ui.get("_cards").size()), filled])
	_library_ok = filled
	_set_phase("сборка: открутить, Ctrl+Z")
	w.ws.unscrew("3")
	await _idle(0.5)
	w.ws.undo()
	await _idle(1.0)
	_set_phase("«Испытать»")
	_timed("start_test", w.ws.start_test)
	await _idle(2.5)
	_set_phase("назад к сборке")
	w.ws.stop_test()
	await _idle(1.5)
	_set_phase("«Испытать» (второй раз)")
	w.ws.start_test()
	await _idle(2.0)
	_set_phase("назад (второй раз)")
	w.ws.stop_test()
	await _idle(1.5)
	_set_phase("выход в меню")
	w.close()
	await _idle(2.0)
	var bad := not _library_ok or _inst_bad
	for p in order:
		var ms := float(worst[p])
		var counted: bool = p != "старт гаража"
		var lim: float = float(PHASE_LIMITS.get(p, limit_ms))
		var flag := ""
		if counted and ms > lim:
			bad = true
			flag = "  ← > %.0f" % lim
		print("GWH %-30s худший кадр %7.1f мс%s" % [p, ms, flag])
	for s in slow:
		print("GWH   кадр > 60 мс: %s %.1f мс" % [s[0], s[1]])
	for f in [CraftEdit.save_path("_probe_gwh"), ProjectSettings.globalize_path("user://_probe_gwh_prefs.cfg")]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	print("GARAGE WS HITCH PROBE ", "OK" if not bad else "FAILED")
	get_tree().quit(1 if bad else 0)
