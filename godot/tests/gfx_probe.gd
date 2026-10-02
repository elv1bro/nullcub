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
	# --- DynRes на синтетических потоках кадров ---
	var d := DynRes.new()
	d.target_ms = 1000.0 / 60.0
	for i in range(60 * 30):
		d.feed(16.6, true)
	_check("dyn_steady", is_equal_approx(d.mult, 1.0), "ровные 60 fps 30 с — масштаб не трогается", d.mult)
	for i in range(60 * 10):
		d.feed(16.6 if i != 300 else 400.0, true)
	_check("dyn_spike_ignored", is_equal_approx(d.mult, 1.0), "единичный рывок 400 мс окно не портит", d.mult)
	var d2 := DynRes.new()
	var drops := 0
	for i in range(33 * 12):   # 12 с по 30 мс
		if d2.feed(30.0, true):
			drops += 1
	_check("dyn_drops", d2.mult < 0.8 and d2.mult >= d2.floor_mult and drops >= 3, "устойчивые 33 fps: масштаб снижается шагами (по 2 окна)", [snappedf(d2.mult, 0.001), drops])
	for i in range(33 * 60):
		d2.feed(30.0, true)
	_check("dyn_floor", is_equal_approx(d2.mult, d2.floor_mult), "и не ниже пола", d2.mult)
	var d3 := DynRes.new()
	d3.mult = 0.7
	var up := 0
	for i in range(60 * 25):   # 25 с хороших кадров
		if d3.feed(16.0, true):
			up += 1
	_check("dyn_recovers", d3.mult > 0.7 and up >= 1, "запас появился — масштаб возвращается (раз в 10 хороших окон)", [snappedf(d3.mult, 0.001), up])
	var d4 := DynRes.new()
	d4.mult = 0.7
	for i in range(60 * 11):   # поднялись
		d4.feed(16.0, true)
	var raised := d4.mult
	for i in range(33 * 3):    # и сразу плохо
		d4.feed(30.0, true)
	var after_bad := d4.mult
	for i in range(60 * 40):   # 40 с хороших кадров — подъёмы заблокированы на 60 с
		d4.feed(16.0, true)
	_check("dyn_no_seesaw", raised > 0.7 and after_bad < raised and is_equal_approx(d4.mult, after_bad), "после неудачного возврата подъёмы блокируются (без качелей)", [raised, after_bad, d4.mult])
	var d5 := DynRes.new()
	for i in range(33 * 20):
		d5.feed(30.0, false)
	_check("dyn_inactive", is_equal_approx(d5.mult, 1.0), "загрузка / хит-стоп (active=false) — окно не копится", d5.mult)
	_check("suggest_apple", GfxScript.suggested_preset("Apple M2") == "high" and GfxScript.suggested_preset("") == "high", "Apple и неизвестная — high")
	_check("suggest_intel", GfxScript.suggested_preset("Intel(R) HD Graphics 630") == "low" and GfxScript.suggested_preset("Intel(R) UHD Graphics 630") == "medium"
		and GfxScript.suggested_preset("Intel(R) Iris(TM) Plus Graphics") == "medium", "Intel HD — low, UHD / Iris — medium")
	_check("suggest_discrete", GfxScript.suggested_preset("AMD Radeon Pro 5500M") == "high" and GfxScript.suggested_preset("NVIDIA GeForce RTX 3060") == "high", "дискретные — high")
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
