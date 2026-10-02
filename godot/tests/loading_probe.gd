## Проба лоадера (scripts/menu/loading.gd, autoload «Loading») без окна:
##   godot --headless --path godot res://tests/loading_probe.tscn
## begin → виден, полоса догоняет цель, finish не раньше MIN_SHOW_S, hold/release, load_async грузит ресурс с прогрессом,
## change_scene меняет сцену (пустая сцена-цель) и прячет лоадер. В stdout «=== LOADING PROBE ===» и JSON; exit 0 — ок.
class_name LoadingProbe
extends Node

## Проверки общие для обеих сцен пробы (смена сцены освобождает эту): вторая половина — tests/loading_probe_target.gd.
static var checks: Array = []


func _ready() -> void:
	checks = []
	await _run()


static func report_and_quit(tree: SceneTree) -> void:
	var ok := true
	for c in checks:
		ok = ok and bool(c["ok"])
	print("=== LOADING PROBE ===")
	print(JSON.stringify({"ok": ok, "checks": checks}))
	print("=== OK ===" if ok else "=== FAIL ===")
	tree.quit(0 if ok else 1)


static func _check(id: String, ok: bool, value = null) -> void:
	checks.append({"id": id, "ok": ok, "value": value})
	if not ok:
		push_warning("loading_probe FAIL: %s value=%s" % [id, str(value)])


func _wait(cond: Callable, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < timeout_s * 1000.0:
		await get_tree().process_frame
	return cond.call()


func _run() -> void:
	_check("hidden_at_start", not Loading.showing)
	Loading.begin("ТЕСТ", "проба")
	_check("shown_after_begin", Loading.showing)
	Loading.set_progress(0.5)
	await _wait(func() -> bool: return Loading.progress > 0.45, 2.0)
	_check("bar_follows_target", Loading.progress > 0.45 and Loading.progress <= 0.5, Loading.progress)
	var t0 := Time.get_ticks_msec()
	Loading.finish()
	var gone := await _wait(func() -> bool: return not Loading.showing, 4.0)
	var dt := (Time.get_ticks_msec() - t0) / 1000.0
	_check("finish_hides", gone, dt)
	# удержание
	Loading.hold("a", "УДЕРЖАНИЕ", "")
	Loading.hold("b")
	Loading.finish()
	await get_tree().create_timer(0.8).timeout
	_check("hold_keeps_it", Loading.showing)
	Loading.release("a")
	await get_tree().create_timer(0.8).timeout
	_check("one_hold_left_keeps_it", Loading.showing)
	Loading.release("b")
	_check("hold_released_hides", await _wait(func() -> bool: return not Loading.showing, 4.0))
	# фоновая загрузка с прогрессом
	var res := await Loading.load_async("res://scenes/workshop/workshop_embed.tscn", "ЗАГРУЗКА", "мастерская")
	_check("load_async_returns_scene", res is PackedScene)
	_check("load_async_showing", Loading.showing)
	Loading.finish()
	await _wait(func() -> bool: return not Loading.showing, 4.0)
	# смена сцены под лоадером: цель — tests/loading_probe_target.tscn, она допроверяет и печатает итог
	Loading.change_scene.call_deferred("res://tests/loading_probe_target.tscn", "СМЕНА", "цель пробы")
