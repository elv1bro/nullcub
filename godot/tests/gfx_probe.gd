## Проба графики (scripts/gfx/gfx.gd, автозагрузка Gfx): масштаб 3D под физические пиксели и бюджет пикселей пресета, пресеты, возврат
## «как задумала арена» (DOF / glow выключаются и возвращаются), выбор переживает пресет «неизвестное имя». Окно не нужно.
## Запуск: godot --headless --path . res://tests/gfx_probe.tscn → tests/gfx_probe_report.json, exit 0/1.
extends Node

const GfxScript := preload("res://scripts/gfx/gfx.gd")
var report := {"ok": true, "checks": []}


func _check(id: String, ok: bool, what: String, value: Variant = null) -> void:
	report["checks"].append({"id": id, "ok": ok, "what": what, "value": value})
	if not ok:
		report["ok"] = false
	print("  %s %-26s %s  %s" % ["ok  " if ok else "FAIL", id, what, "" if value == null else str(value)])


func _ready() -> void:
	# --- чистая математика масштаба ---
	var s1 := GfxScript.scale_for(Vector2(5120, 2880), 0.5, 3_700_000)
	_check("scale_ext_monitor", is_equal_approx(s1, 0.5), "внешний 1× монитор рядом с Retina: окно 5120×2880 «пикселей Godot» → масштаб 0.5 (рендер 2560×1440)", s1)
	var s2 := GfxScript.scale_for(Vector2(3360, 2100), 1.0, 3_700_000)
	_check("scale_retina_budget", absf(s2 - sqrt(3_700_000.0 / (3360.0 * 2100.0))) < 1e-4 and s2 < 1.0, "Retina 3360×2100 (7 Мп) режется до бюджета «high» 3.7 Мп", s2)
	_check("scale_native", is_equal_approx(GfxScript.scale_for(Vector2(1920, 1080), 1.0, 0), 1.0), "ultra (бюджет 0) на нативном экране — масштаб 1")
	_check("scale_small_window", is_equal_approx(GfxScript.scale_for(Vector2(1280, 720), 1.0, 3_700_000), 1.0), "окно меньше бюджета — без потери")
	var s3 := GfxScript.scale_for(Vector2(1920, 1080), 1.0, 1_000_000)
	_check("scale_low", absf(s3 * s3 * 1920.0 * 1080.0 - 1_000_000.0) < 1.0, "low: площадь 3D = бюджет пресета (1 Мп)", s3)
	_check("scale_floor", GfxScript.scale_for(Vector2(8000, 8000), 0.3, 500_000) >= GfxScript.SCALE_MIN, "масштаб не падает ниже SCALE_MIN")
	# --- пресеты ---
	_check("presets_complete", GfxScript.ORDER.size() == 4 and GfxScript.ORDER.all(func(n: Variant) -> bool: return GfxScript.PRESETS.has(n)), "low / medium / high / ultra есть в таблице")
	var prev := -1
	var mono := true
	for n in GfxScript.ORDER:
		var b := int(GfxScript.PRESETS[n]["budget_px"])
		b = 1 << 40 if b == 0 else b
		mono = mono and b > prev
		prev = b
	_check("presets_monotonic", mono, "бюджет пикселей растёт от low к ultra (0 = без потолка — последний)")
	var g: Node = get_node("/root/Gfx")
	_check("autoload", g != null and g.has_method("cycle"), "автозагрузка Gfx")
	var keep: String = g.preset
	_check("set_unknown", g.set_preset("нет-такого", false) == keep, "неизвестное имя пресет не меняет", g.preset)
	# --- DOF / glow возвращаются как задумала арена ---
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.glow_enabled = true
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_near_enabled = false
	we.environment = env
	we.camera_attributes = attrs
	add_child(we)
	await get_tree().process_frame
	await get_tree().process_frame
	g.set_preset("low", false)
	_check("low_off", not env.glow_enabled and not attrs.dof_blur_far_enabled, "low: glow и DOF выключены", [env.glow_enabled, attrs.dof_blur_far_enabled])
	g.set_preset("high", false)
	_check("high_restored", env.glow_enabled and attrs.dof_blur_far_enabled and not attrs.dof_blur_near_enabled, "high: всё как у арены (ближний DOF так и выключен)", [env.glow_enabled, attrs.dof_blur_far_enabled, attrs.dof_blur_near_enabled])
	var env2 := Environment.new()   # арена, у которой glow выключен сама: пресет её не включает
	env2.glow_enabled = false
	we.environment = env2
	g.set_preset("ultra", false)
	await get_tree().process_frame
	_check("never_forces_on", not env2.glow_enabled, "пресет не включает то, что арена выключила", env2.glow_enabled)
	# --- cycle идёт по кругу ---
	g.set_preset("ultra", false)
	var after: String = g.cycle()
	_check("cycle_wraps", after == "low", "после ultra — снова low", after)
	g.set_preset(keep, false)
	var f := FileAccess.open("res://tests/gfx_probe_report.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  ", false))
		f.close()
	var fails := 0
	for c in report["checks"]:
		fails += 0 if bool(c["ok"]) else 1
	print("GFX PROBE ", "OK (%d checks)" % report["checks"].size() if fails == 0 else "FAILED (%d)" % fails)
	get_tree().quit(0 if fails == 0 else 1)
