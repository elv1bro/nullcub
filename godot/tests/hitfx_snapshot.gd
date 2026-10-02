## Кадры уровней удара (HIT_FX.md §5.5): Void 1280×720, по строке на уровень — light / heavy / slam / crit / ko,
## по столбцу на момент — +1 кадр, +100 мс, +400 мс реального времени (часы HitFxDirector); crit — +1 кадр (стоп-кадр, инверсия),
## +250 мс (крупный план, рентген, CRUSHING BLOW!), +700 мс (кат назад, отлёт в замедлении). Крит — настоящий удар через Match.on_hit
## с тестовым переключателем Match.hit_tiers.force_next = "crit" (правило крита само не выпадает на 2-й секунде боя). Удар эмулирует DollCombat._deliver:
## take_damage → apply_knockback → ImpactFx → Match.on_hit (в _physics_process, как в игре); Match.crit_enabled = false (кроме строки crit) —
## ko в листе — обычный KO, ko_crit показывает CritCinematic (crit_snapshot). slam — настоящий удар о правую стену Void 8 м/с (Match.env_slam; без ядра —
## HitFxDirector.play_slam напрямую). Лист → docs/plan-demo/img/hitfx-tiers-v1.png (ячейки cell_w × cell_h), кадры —
## в out_dir. Печатает JSON-отчёт (что показано по уровням: stats директора, размер листа). Exit 0/1.
## Запуск: godot --path . --resolution 1280x720 --position 100,100 --always-on-top --fixed-fps 60 res://tests/hitfx_snapshot.tscn
##   -- "sheet=res://../docs/plan-demo/img/hitfx-tiers-v1.png,cell_w=640,out_dir=<abs dir>"
## v2 (HIT_FX §11.6): presets=1 — лист пресетов FX игрока: строки full / reduced / off (FxPreset.set_preset), в каждой один и
##   тот же heavy (+1 кадр / +100 / +400 мс) → docs/plan-demo/img/fx-presets-v2.png; в конце пресет возвращается в full.
## v3 (HIT_FX §12.2–12.3): scene=ruins — те же уровни на Руинах (light / heavy / slam / ko; крит на Руинах — crit_snapshot) →
##   docs/plan-demo/img/hitfx-tiers-ruins-v3.png; удар эмулирует и отдачу атакующего DollCombat._deliver (apply_recoil: −0.5 Δv, тяга
##   выключена 0.3 с) — как в игре; в v1/v2 её не было, и в листе атакующий летел следом за жертвой.
extends Node3D

const SCENES := {"void": "res://scenes/playground_void.tscn", "ruins": "res://scenes/playground.tscn"}
const VOID_SCENE := "res://scenes/playground_void.tscn"
const DIRECTOR_SCENE := "res://scenes/fx/hit_fx_director.tscn"
const TIERS := ["light", "heavy", "slam", "crit", "ko"]
const SHOTS_MS := [17.0, 100.0, 400.0]
const CRIT_SHOTS_MS := [17.0, 250.0, 700.0]
const MAX_SHEET_BYTES := 2 * 1024 * 1024
const HEAVY_GAP_M := 1.6          # v3: ЦМ атакующего левее жертвы на столько (v1/v2 — 1.2)

var sheet_path := "res://../docs/plan-demo/img/hitfx-tiers-v1.png"
var out_dir := ""
var cell_w := 640
var presets_mode := false           # presets=1: строки — пресеты FX, удар — heavy
var scene_id := "void"
var recoil := true                  # recoil=0 — удар без отдачи атакующего (как листы v1/v2)
var pg: Node3D
var match_node: Match
var director: HitFxDirector
var caption: Label
var report := {"ok": true, "tiers": {}, "checks": []}
var shots: Dictionary = {}          # tier -> [Image]
var _phys_cb: Callable
signal _phys_done


func _ready() -> void:
	HitJuice.impact_style = "cartoon"   # проба проверяет стиль «мульт» (звезда, кольца, послеобразы); «серьёзный» — juice_probe (§13)
	HitJuice.outline_on = false   # обводка бойцов (B) — свои узлы на мешах кукол; проба считает узлы и оверлеи частей
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			match p[0]:
				"sheet": sheet_path = p[1]
				"out_dir": out_dir = p[1]
				"cell_w": cell_w = int(p[1])
				"presets": presets_mode = p[1] != "0"
				"scene": scene_id = p[1]
				"recoil": recoil = p[1] != "0"
	pg = (load(SCENES.get(scene_id, VOID_SCENE)) as PackedScene).instantiate()
	match_node = pg.get_node("Match") as Match
	match_node.countdown_s = 0.0
	add_child(pg)
	var cl := CanvasLayer.new()
	cl.layer = 40
	add_child(cl)
	caption = Label.new()
	caption.position = Vector2(24, 84)
	caption.add_theme_font_size_override("font_size", 44)
	caption.add_theme_color_override("font_color", Color(1, 1, 1))
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	caption.add_theme_constant_override("outline_size", 10)
	cl.add_child(caption)
	_run.call_deferred()


func check(id: String, ok: bool, value: Variant = null) -> void:
	report["checks"].append({"id": id, "ok": ok, "value": value})
	if not ok:
		report["ok"] = false
	print("%s %s %s" % ["OK  " if ok else "FAIL", id, str(value)])


func physics_call(cb: Callable) -> void:
	_phys_cb = cb
	await _phys_done


func _physics_process(_delta: float) -> void:
	if _phys_cb.is_valid():
		var cb := _phys_cb
		_phys_cb = Callable()
		cb.call()
		_phys_done.emit()


func frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func p1() -> Doll:
	return pg.get_node("P1") as Doll


func p2() -> Doll:
	return pg.get_node("P2") as Doll


## x ЦМ куклы; same_y — ещё и высота ЦМ как у этой куклы (Руины: P1 спавнится на верхнем ярусе).
func _place(d: Doll, x: float, same_y: Doll = null) -> void:
	var off := x - d.centre_of_mass().x
	var dy := 0.0 if same_y == null or scene_id == "void" else same_y.centre_of_mass().y - d.centre_of_mass().y
	for b in d.parts.values():
		(b as RigidBody3D).global_position.x += off
		(b as RigidBody3D).global_position.y += dy
		(b as RigidBody3D).linear_velocity = Vector3.ZERO
		(b as RigidBody3D).angular_velocity = Vector3.ZERO


## Удар как DollCombat._deliver: урон, отброс (скорость ЦМ ≈ com_speed вдоль dir), ImpactFx, Match.on_hit.
func _hit(victim: Doll, attacker: Doll, dmg: float, com_speed: float, part_name: String, kind: String) -> void:
	var part := victim.parts[part_name] as RigidBody3D
	var dir := Vector3(1.0, 0.35, 0.0).normalized()
	var pos := part.global_position + Vector3(-0.12, 0.0, 0.0)
	var nrm := -dir
	victim.hit_meta = {"dir": dir, "striker_name": "Hand_R"}
	victim.take_damage(dmg, attacker, part_name, pos, nrm, kind)
	if victim.alive:
		victim.apply_knockback(Damage.knockback_dir(dir) * com_speed * victim.total_mass, victim.torso(), 0.3, dir)
		if recoil and com_speed > 0.0:
			attacker.apply_recoil(dir, Tuning.HIT_ATTACKER_RECOIL * com_speed, Tuning.HIT_ATTACKER_THRUST_LOCK_S)
	ImpactFx.spawn_impact(pg, pos, nrm, 4.0 + dmg * 0.4, kind)
	match_node.on_hit(victim, attacker, dmg, kind, pos, 1, false, "", 7.0)


func _shoot(tier: String, key: String = "", label: String = "") -> void:
	if key == "":
		key = tier
	if label == "":
		label = tier.to_upper()
	var t0 := director.clock_ms()
	var imgs: Array = []
	for ms in (CRIT_SHOTS_MS if tier == "crit" else SHOTS_MS):
		while director.clock_ms() - t0 < float(ms) - 0.5:
			await get_tree().process_frame
		caption.text = "%s  +%d ms" % [label, int(ms) if ms > 20.0 else 0]
		if OS.has_environment("HITFX_DEBUG"):
			for fl in get_tree().root.find_children("*", "ImpactFlash", true, false):
				var f := fl as ImpactFlash
				print("dbg %s %s flash %s vis=%s coll=%s sc=%.2f tr=%.2f" % [tier, ms, f.get_path(), f.visible, f.collapsing(), f.scale.x, (f.get_child(0) as MeshInstance3D).transparency])
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if out_dir != "":
			img.save_png(out_dir.path_join("hitfx_%s_%03d.png" % [key, int(ms)]))
		imgs.append(img)
	shots[key] = imgs


func _run() -> void:
	await frames(3)
	director = match_node.get_node_or_null("HitFxDirector") as HitFxDirector
	if director == null:
		director = (load(DIRECTOR_SCENE) as PackedScene).instantiate() as HitFxDirector
		match_node.add_child(director)
	match_node.crit_enabled = false
	var slam_n := [0]
	if match_node.has_signal("env_slam"):
		match_node.connect("env_slam", func(_c: Dictionary) -> void: slam_n[0] += 1)
	var rows: Array = []                 # [ключ строки, уровень, пресет FX]
	if presets_mode:
		for pr in Tuning.HITFX_PRESET_ORDER:
			rows.append(["heavy_" + String(pr), "heavy", String(pr)])
	else:
		for tr0 in TIERS:
			if scene_id != "void" and tr0 == "crit":
				continue   # крит на Руинах — лист crit_snapshot scene=ruins
			rows.append([tr0, tr0, FxPreset.FULL])
	for row in rows:
		var key := String(row[0])
		var tier := String(row[1])
		FxPreset.set_preset(String(row[2]), get_tree())
		match_node.restart()
		await frames(2)
		p1().external_input = true
		p2().external_input = true
		await frames(150)        # стоят; SPAWN_GRACE прошла
		var st: Dictionary = director.stats.duplicate()
		var np := director.played.size()
		var v := p2()
		var a := p1()
		match_node.crit_enabled = tier == "crit"
		match tier:
			"light":
				_place(v, 0.3)
				_place(a, -0.9, v)
				await frames(20)
				await physics_call(func() -> void: _hit(v, a, 5.0, 1.4, "Torso", "body"))
			"heavy":
				# v3: 1.6 м между ЦМ — руки Т-позы не переплетены (в 1.2 м они вложены друг в друга, и жертва в первом же шаге
				# физики отдаёт скорость атакующему: он летел следом — критик v2); удар — как DollCombat, с отдачей
				_place(v, 0.3)
				_place(a, 0.3 - HEAVY_GAP_M, v)
				await frames(20)
				await physics_call(func() -> void: _hit(v, a, 14.0, 4.2, "Torso", "body"))
			"crit":
				_place(v, 0.3)
				_place(a, -0.9, v)
				await frames(20)
				match_node.hit_tiers.force_next = "crit"
				await physics_call(func() -> void: _hit(v, a, 24.0, 4.2, "Head", "head"))
			"ko":
				_place(v, 0.3)
				_place(a, -0.9, v)
				await frames(20)
				v.hp = 12.0
				await physics_call(func() -> void: _hit(v, a, 30.0, 0.0, "Head", "head"))
			"slam":
				var b: AABB = pg.get("arena").call("bounds")
				_place(v, b.end.x - 2.6 if scene_id == "void" else 0.3)
				await frames(10)
				var n0: int = slam_n[0]
				for rb in v.parts.values():
					if scene_id == "void":
						(rb as RigidBody3D).global_position.y += 0.6
						(rb as RigidBody3D).linear_velocity = Vector3(8.5, 2.0, 0.0)
					else:   # Руины: стены у границ нет — удар о пол сверху
						(rb as RigidBody3D).global_position.y += 1.1
						(rb as RigidBody3D).linear_velocity = Vector3(1.0, -9.0, 0.0)
				var waited := 0
				while slam_n[0] == n0 and waited < 90:
					await get_tree().process_frame
					waited += 1
				if slam_n[0] == n0:
					director.play_slam({"doll": v, "part": "Torso", "speed": 8.0, "position": Vector3(b.end.x, v.centre_of_mass().y, 0.0),
						"normal": Vector3.LEFT, "flying": true, "crit_flight": false, "fight_time": match_node.fight_time})
					report["tiers"]["slam_mode"] = "direct"
				else:
					await frames(1)
					report["tiers"]["slam_mode"] = "env_slam"
		await _shoot(tier, key, tier.to_upper() + ("  ·  FX " + String(row[2]).to_upper() if presets_mode else ""))
		var d := {}
		for k in director.stats.keys():
			var dv := int(director.stats[k]) - int(st.get(k, 0))
			if dv != 0:
				d[k] = dv
		report["tiers"][key] = d
		var seen: Array = []
		for i in range(np, director.played.size()):
			var tr := String((director.played[i] as Dictionary).get("tier", ""))
			if not seen.has(tr):
				seen.append(tr)
		report["tiers"][key + "_played"] = seen
		await frames(90 if tier == "crit" else 30)
		match_node.crit_enabled = false
	caption.text = ""
	FxPreset.set_preset(FxPreset.FULL, get_tree())
	# лист
	var cw := cell_w
	var ch := int(round(cw * 9.0 / 16.0))
	var sheet := Image.create(cw * SHOTS_MS.size(), ch * rows.size(), false, Image.FORMAT_RGB8)
	for r in range(rows.size()):
		var imgs: Array = shots.get(String(rows[r][0]), [])
		for c in range(imgs.size()):
			var img := (imgs[c] as Image).duplicate() as Image
			img.convert(Image.FORMAT_RGB8)
			img.resize(cw, ch, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(img, Rect2i(0, 0, cw, ch), Vector2i(c * cw, r * ch))
	var path := ProjectSettings.globalize_path(sheet_path) if sheet_path.begins_with("res://") else sheet_path
	var err := sheet.save_png(path)
	var size := FileAccess.get_file_as_bytes(path).size() if err == OK else -1
	check("sheet_saved", err == OK, path)
	check("sheet_le_2mb", size > 0 and size <= MAX_SHEET_BYTES, size)
	if presets_mode:
		for row in rows:
			var k := String(row[0])
			check(k + "_played", (report["tiers"].get(k + "_played", []) as Array).has("heavy"), report["tiers"].get(k + "_played", []))
		check("preset_restored_full", FxPreset.current == FxPreset.FULL, FxPreset.current)
		check("time_scale_1", is_equal_approx(Engine.time_scale, 1.0) or match_node.phase == Match.Phase.OVER, Engine.time_scale)
		print(JSON.stringify(report, "  ", false))
		get_tree().quit(0 if report["ok"] else 1)
		return
	check("light_played", (report["tiers"].get("light_played", []) as Array) == ["light"], report["tiers"].get("light_played", []))
	check("heavy_played", (report["tiers"].get("heavy_played", []) as Array).has("heavy"), report["tiers"].get("heavy_played", []))
	if scene_id == "void":
		check("crit_played", (report["tiers"].get("crit_played", []) as Array).has("crit"), report["tiers"].get("crit_played", []))
	check("ko_played", (report["tiers"].get("ko_played", []) as Array).has("ko"), report["tiers"].get("ko_played", []))
	check("slam_played", int((report["tiers"].get("slam", {}) as Dictionary).get("slams", 0)) >= 1, report["tiers"].get("slam", {}))
	check("time_scale_1", is_equal_approx(Engine.time_scale, 1.0) or match_node.phase == Match.Phase.OVER, Engine.time_scale)
	print(JSON.stringify(report, "  ", false))
	get_tree().quit(0 if report["ok"] else 1)
