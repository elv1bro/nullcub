## Проба «сока удара на языке игры» (docs/plan-demo/HIT_FX.md §13, 02.10). Headless, --fixed-fps 60, площадка Void (манекены
## doll.tscn / doll_dark.tscn) + модульные куклы кита для материалов. Удары — как DollCombat (take_damage + Match.on_hit), точка удара —
## на поверхности детали (луч), fight_time < CRIT_MIN_FIGHT_S: крита нет, кроме проверки табло.
##
## Проверки (checks[].id):
##   mat_*     — FxMaterial: клён у doll.tscn, орех у doll_dark.tscn, материал узла у ModularDoll (кость, краска, металл), классы,
##               хлопья цвета игрока у манекена, плашка у краски, без хлопьев у железа;
##   debris_*  — ImpactFx по классу: дерево с мазками — серые осколки (градиент с цветом игрока) + пыль; металл — искры + пыль, без
##               осколков; резина — только пыль; ржавчина — осколки + искры + пыль; кость — осколки цвета кости;
##   marks_*   — HitMarks: след на всех мешах ударенной детали (overlay ShaderMaterial), повтор в то же место — глубже, не новый; в другое
##               место — новый; не больше JUICE_MARKS_PER_MESH; слабее JUICE_MARK_MIN_DAMAGE — без следа; повод worn один раз;
##   digits_*  — DamageDigits: < JUICE_DIGIT_MIN_DAMAGE — без цифры; 12 HP — «12», ложится на пол Void у жертвы, лежит и уходит; пул
##               ≤ JUICE_DIGIT_MAX (старые переиспользуются); «−» (digits_on = false) — без цифр; большая — повод digit_big;
##   time_*    — варианты (клавиша 0: stop / cinema / web / off): теги и масштаб на light 7 HP и heavy 12 HP, длина «кино», порядок цикла;
##               пресет FX off — без тегов сока;
##   caption_* — табло: HitJuice.impact_caption, настоящий крит — подпись CritOverlay «IMPACT …G»;
##   n0_*      — N0Lines: строки поводов digit_big / metal / worn / digits_pile (ru и en), подстановка %d;
##   restart_* — COUNTDOWN убирает цифры.
## Отчёт: tests/juice_probe_report.json (out=<путь>). Exit 1 при провале.
extends Node3D

const SCENE := "res://scenes/playground_void.tscn"
const MDOLL := "res://scenes/body/modular_doll.tscn"
const KITS := ["kit_bot", "kit_skull", "kit_brawler", "kit_king"]
const FRAME_S := 1.0 / 60.0

var cfg := {"out": "res://tests/juice_probe_report.json", "seed": 7}
var report := {"ok": true, "checks": [], "info": {}}
var pg: Node3D = null
var match_node: Match = null
var juice: HitJuice = null
var mdolls: Array = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and cfg.has(p[0]):
				cfg[p[0]] = p[1] if p[0] == "out" else int(p[1])
	seed(int(cfg["seed"]))
	call_deferred("_run")


func _run() -> void:
	print("=== JUICE PROBE ===")
	_n0_checks()
	pg = (load(SCENE) as PackedScene).instantiate()
	add_child(pg)
	match_node = pg.get_node("Match") as Match
	await _ticks(2)
	juice = match_node.get_node_or_null("HitJuice") as HitJuice
	_check("setup_juice", juice != null and juice.digits != null and juice.get_index() < _index_of("HitFxDirector"),
		[juice != null, juice.get_index() if juice != null else -1, _index_of("HitFxDirector")], "HitJuice before HitFxDirector")
	if juice == null:
		_finish()
		return
	HitJuice.time_variant = Tuning.JUICE_TIME_DEFAULT
	HitJuice.digits_on = true
	for d in _pair():
		(d as Doll).external_input = true
	await _await_fight()
	var ds := _pair()
	var p1: Doll = ds[0]
	var p2: Doll = ds[1]
	await _spawn_mdolls()
	_material_checks(p1, p2)
	await _debris_checks(p1)
	await _style_checks(p1, p2)
	await _mark_checks(p1, p2)
	await _digit_checks(p1, p2)
	await _time_checks(p1, p2)
	await _caption_checks(p1, p2)
	await _restart_checks()
	_finish()


# ------------------------------------------------------------------ утилиты

func _check(id: String, ok: bool, value: Variant, expect: Variant, detail: String = "") -> void:
	report["checks"].append({"id": id, "ok": ok, "value": _js(value), "expect": _js(expect), "detail": detail})
	if not ok:
		report["ok"] = false
	print("  %s %s: %s (expect %s) %s" % ["ok  " if ok else "FAIL", id, str(_js(value)), str(_js(expect)), detail])


func _js(v: Variant) -> Variant:
	if v is float:
		return snappedf(v, 0.001)
	if v is Vector3 or v is Vector2 or v is Color:
		return str(v)
	if v is Array:
		return (v as Array).map(func(x: Variant) -> Variant: return _js(x))
	return v


func _ticks(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _wait_real(s: float) -> void:
	var t := 0.0
	var guard := 0
	while t < s and guard < 4000:
		await get_tree().process_frame
		t += FxClock.real_delta(get_process_delta_time())
		guard += 1


func _index_of(n: String) -> int:
	var c := match_node.get_node_or_null(n)
	return c.get_index() if c != null else 999


func _pair() -> Array:
	var ds: Array = []
	for d in get_tree().get_nodes_in_group("dolls"):
		if d is Doll and pg.is_ancestor_of(d) and not (d as Node).is_queued_for_deletion() and not mdolls.has(d):
			ds.append(d)
	ds.sort_custom(func(x: Doll, y: Doll) -> bool: return x.player_index < y.player_index)
	return ds


func _await_fight() -> void:
	var n := 0
	while match_node.phase != Match.Phase.FIGHT and n < 900:
		await _ticks(1)
		n += 1
	await _ticks(50)


func _wait_time_clear() -> void:
	var guard := 0
	while (not match_node.time_scale_tags().is_empty() or Engine.time_scale < 1.0) and guard < 300:
		await _frames(1)
		guard += 1


func _heal(ds: Array) -> void:
	for d in ds:
		(d as Doll).hp = (d as Doll).max_hp


## Точка на поверхности тела b со стороны from (луч; чужие тела — в исключения).
func _surface_point(b: Node3D, from: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, b.global_position + (b.global_position - from).normalized() * 0.5)
	var ex: Array[RID] = []
	for i in range(8):
		q.exclude = ex
		var r := space.intersect_ray(q)
		if r.is_empty():
			break
		if r["collider"] == b:
			return r["position"]
		ex.append(r["rid"])
	return b.global_position


## Удар как DollCombat: take_damage + Match.on_hit; точка — на поверхности детали со стороны атакующего и камеры.
func _strike(att: Doll, vic: Doll, dmg: float, part: String = "Torso", at: Variant = null) -> Vector3:
	await get_tree().physics_frame
	if match_node.fight_time > Tuning.CRIT_MIN_FIGHT_S - 1.0:
		match_node.fight_time = 1.0
	var dir := Vector3(signf(vic.torso().global_position.x - att.torso().global_position.x), 0, 0)
	if dir == Vector3.ZERO:
		dir = Vector3.RIGHT
	var body := vic.parts[part] as Node3D
	var pos: Vector3 = at if at is Vector3 else _surface_point(body, body.global_position - dir * 1.0 + Vector3(0.0, 0.1, 0.45))
	vic.hit_meta = {"speed": 12.0, "weapon_id": "", "striker": att.torso(), "combo_mult": 1.0, "double_blow": false,
		"knockback_mult": 1.0, "stun_s": 0.0, "dir": dir, "striker_name": "Hand_R"}
	vic.take_damage(dmg, att, part, pos, -dir, "body")
	match_node.on_hit(vic, att, dmg, "body", pos, 1, false, "", 12.0)
	return pos


func _spawn_mdolls() -> void:
	var x := -4.5
	for k in KITS:
		var md := (load(MDOLL) as PackedScene).instantiate() as Node3D
		md.set("blueprint", load("res://data/body/blueprints/%s.tres" % k))
		md.name = "M_" + k
		pg.add_child(md)
		md.global_position = Vector3(x, 3.0, -3.0)
		x += 3.0
		mdolls.append(md)
	await _ticks(4)
	for md in mdolls:
		for b in (md.get("parts") as Dictionary).values():
			(b as RigidBody3D).freeze = true


## Первое тело модульной куклы с классом материала c: [кукла, тело] или [].
func _body_of_class(c: String) -> Array:
	for md in mdolls:
		for b in (md.get("parts") as Dictionary).values():
			if FxMaterial.cls(FxMaterial.id_of(md, b)) == c:
				return [md, b]
	return []


# ------------------------------------------------------------------ материалы

func _material_checks(p1: Doll, p2: Doll) -> void:
	var m1 := FxMaterial.id_of(p1, p1.torso())
	var m2 := FxMaterial.id_of(p2, p2.torso())
	_check("mat_mannequin", m1 == "maple" and m2 == "wood_dark", [m1, m2], ["maple", "wood_dark"], "doll.tscn / doll_dark.tscn")
	var found := {}
	for c in ["bone", "paint", "metal", "rust"]:
		found[c] = not _body_of_class(c).is_empty()
	_check("mat_modular", found.values().all(func(v: bool) -> bool: return v), found, "bone, paint, metal, rust among kit_bot/skull/brawler/king")
	var t1 := FxMaterial.tint_of(m1, p1)
	var pb := _body_of_class("paint")
	var tp := FxMaterial.tint_of(FxMaterial.id_of(pb[0], pb[1]), pb[0]) if not pb.is_empty() else Color(0, 0, 0, 0)
	var ti := FxMaterial.tint_of("iron", null)
	_check("mat_tint", t1.is_equal_approx(Tuning.PLAYER_COLORS[p1.player_index]) and tp.a > 0.0 and is_zero_approx(ti.a), [t1, tp, ti],
		["player colour", "paint swatch", "none"])


# ------------------------------------------------------------------ обломки

func _debris_checks(p1: Doll) -> void:
	var host := match_node
	var at := Vector3(0.0, -50.0, 0.0)
	var kinds := {}
	for m in ["maple", "iron", "rubber", "rust", "bone"]:
		var tint := FxMaterial.tint_of(m, p1) if m == "maple" else Color(0, 0, 0, 0)
		var root := ImpactFx.spawn_impact(host, at, Vector3.UP, 8.0, "body", m, tint, false)
		var names: Array = []
		for c in root.get_children():
			if c is GPUParticles3D:
				names.append(String(c.name))
		names.sort()
		kinds[m] = names
		if m == "bone":
			var chips := root.get_node_or_null("Chips") as GPUParticles3D
			var g: Gradient = ((chips.process_material as ParticleProcessMaterial).color_initial_ramp as GradientTexture1D).gradient if chips != null else null
			var c0: Color = g.colors[0] if g != null else Color.BLACK
			_check("debris_bone_colour", c0.is_equal_approx(FxMaterial.CHIP_COLOURS[FxMaterial.BONE][0]), c0, FxMaterial.CHIP_COLOURS[FxMaterial.BONE][0])
		if m == "maple":
			var chips := root.get_node_or_null("Chips") as GPUParticles3D
			var g: Gradient = ((chips.process_material as ParticleProcessMaterial).color_initial_ramp as GradientTexture1D).gradient if chips != null else null
			var has_tint := g != null and (g.colors[0] as Color).lightened(0.0).is_equal_approx(Color(tint.r, tint.g, tint.b).lightened(0.12))
			_check("debris_stroke_flakes", has_tint, g.colors[0] if g != null else "-", "player colour flakes in the ramp (STROKE_SHARE)")
		root.queue_free()
	_check("debris_by_class", kinds["maple"] == ["Chips", "DustPuff"] and kinds["iron"] == ["DustPuff", "Sparks"] and kinds["rubber"] == ["DustPuff"]
		and kinds["rust"] == ["Chips", "DustPuff", "Sparks"] and kinds["bone"] == ["Chips", "DustPuff"], kinds,
		{"maple": ["Chips", "DustPuff"], "iron": ["DustPuff", "Sparks"], "rubber": ["DustPuff"], "rust": ["Chips", "DustPuff", "Sparks"]})
	await _frames(1)


# ------------------------------------------------------------------ стиль удара

## «Серьёзный» (по умолчанию): у ImpactFx — горячее пятно без лучей и свет ImpactLight; heavy директора — свет и волна воздуха, без колец,
## послеобразов, лент, линий и белого кадра; клавиша «=» — «мульт» (прежние звезда и кольца) и обратно.
func _style_checks(p1: Doll, p2: Doll) -> void:
	HitJuice.impact_style = Tuning.JUICE_IMPACT_STYLE_DEFAULT
	var root := ImpactFx.spawn_impact(match_node, Vector3(0.0, -40.0, 0.0), Vector3.UP, 8.0, "body", "maple")
	var flash := root.get_node_or_null("Flash")
	var quads := flash.get_child_count() if flash != null else -1
	var light := root.find_children("*", "ImpactLight", true, false).size()
	_check("style_serious_light_hit", Tuning.JUICE_IMPACT_STYLE_DEFAULT == "serious" and quads == 1 and light == 1, [Tuning.JUICE_IMPACT_STYLE_DEFAULT, quads, light],
		["serious", 1, 1], "hot core without rays + ImpactLight")
	root.queue_free()
	var dir := match_node.get_node("HitFxDirector") as HitFxDirector
	var st0: Dictionary = dir.stats.duplicate()
	var ctx := match_node.make_hit_ctx(p2, p1, 12.0, "body", p2.torso().global_position, 1, false, "", 8.0)
	ctx["tier"] = "heavy"
	ctx["score"] = 12.0
	dir.play(ctx)
	await _frames(2)
	var d := func(k: String) -> int: return int(dir.stats.get(k, 0)) - int(st0.get(k, 0))
	_check("style_serious_heavy", d.call("lights") == 1 and d.call("air_shocks") == 1 and d.call("waves") == 0 and d.call("afterimages") == 0
		and d.call("trails") == 0 and d.call("lines") == 0 and d.call("flashes") == 0 and d.call("sparks") == 0,
		[d.call("lights"), d.call("air_shocks"), d.call("waves"), d.call("afterimages"), d.call("trails"), d.call("lines"), d.call("flashes"), d.call("sparks")],
		"lights 1, air_shocks 1, waves/afterimages/trails/lines/flashes/sparks 0")
	await _wait_time_clear()
	var ke := InputEventKey.new()
	ke.physical_keycode = KEY_EQUAL
	ke.pressed = true
	juice._unhandled_input(ke)
	var s1 := HitJuice.impact_style
	var st1: Dictionary = dir.stats.duplicate()
	dir.play(ctx)
	await _frames(2)
	var waves := int(dir.stats.get("waves", 0)) - int(st1.get("waves", 0))
	juice._unhandled_input(ke)
	_check("style_key_cartoon", s1 == "cartoon" and waves >= 1 and HitJuice.impact_style == "serious", [s1, waves, HitJuice.impact_style],
		["cartoon", ">= 1 ring", "serious"], "key = toggles; cartoon keeps the old rings")
	await _wait_time_clear()
	await _wait_real(0.6)
	_heal([p1, p2])


# ------------------------------------------------------------------ следы

func _mark_checks(p1: Doll, p2: Doll) -> void:
	var torso := p2.torso()
	var meshes := HitMarks.meshes_of(torso)
	var pos := await _strike(p1, p2, 8.0)
	var with_overlay := 0
	var counts: Array = []
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.material_overlay is ShaderMaterial and (mi.material_overlay as ShaderMaterial).shader == HitMarks.SHADER:
			with_overlay += 1
		counts.append(HitMarks.marks_of(mi).size())
	_check("marks_on_hit_part", meshes.size() > 0 and with_overlay == meshes.size() and counts.all(func(n: int) -> bool: return n == 1),
		[meshes.size(), with_overlay, counts], "every mesh of the hit part: overlay + 1 mark")
	var mi0 := meshes[0] as MeshInstance3D
	var p_before := float(HitMarks.marks_of(mi0)[0]["power"])
	await _strike(p1, p2, 8.0, "Torso", pos + Vector3(0.0, 0.01, 0.0))
	var n_same := HitMarks.marks_of(mi0).size()
	var p_after := float(HitMarks.marks_of(mi0)[0]["power"])
	_check("marks_merge", n_same == 1 and p_after > p_before, [n_same, p_before, p_after], "same spot → deeper, not a new mark")
	await _strike(p1, p2, 1.5, "Torso", pos + Vector3(0.0, -0.2, 0.0))
	_check("marks_min_damage", HitMarks.marks_of(mi0).size() == 1, HitMarks.marks_of(mi0).size(), 1, "%.1f HP < JUICE_MARK_MIN_DAMAGE" % 1.5)
	await _strike(p1, p2, 6.0, "Torso", pos + Vector3(0.0, -0.22, 0.0))
	_check("marks_new_spot", HitMarks.marks_of(mi0).size() == 2, HitMarks.marks_of(mi0).size(), 2)
	for i in range(10):
		await _strike(p1, p2, 4.0, "Torso", pos + Vector3(0.0, 0.3 - 0.06 * i, 0.0 if i % 2 == 0 else 0.05))
		_heal([p1, p2])
	var cap := 0
	for m in meshes:
		cap = maxi(cap, HitMarks.marks_of(m as MeshInstance3D).size())
	_check("marks_cap", cap <= Tuning.JUICE_MARKS_PER_MESH, cap, "<= %d" % Tuning.JUICE_MARKS_PER_MESH)
	var worn := juice.events.filter(func(e: Dictionary) -> bool: return e["event"] == "worn").size()
	_check("marks_worn_event", worn == 1 and HitMarks.wear(torso) >= Tuning.JUICE_WORN_POWER, [worn, HitMarks.wear(torso)], [1, ">= %.1f" % Tuning.JUICE_WORN_POWER])
	_heal([p1, p2])
	await _wait_time_clear()


# ------------------------------------------------------------------ цифры

func _digit_checks(p1: Doll, p2: Doll) -> void:
	var dg := juice.digits
	dg.clear()
	await _wait_real(0.3)
	var n0 := int(dg.stats["spawned"])
	await _strike(p1, p2, 2.0)
	_check("digits_min_damage", int(dg.stats["spawned"]) == n0, int(dg.stats["spawned"]) - n0, 0, "2 HP < JUICE_DIGIT_MIN_DAMAGE")
	var vic_x := p2.centre_of_mass().x
	await _strike(p1, p2, 12.0)
	var c: Dictionary = {}
	for ch in dg.chunks:
		if String(ch["state"]) == "fly":
			c = ch
	_check("digits_spawn", not c.is_empty() and String(c.get("text", "")) == "12", c.get("text", "-"), "12")
	var landed_t := -1.0
	var t := 0.0
	while t < 3.0 and not c.is_empty():
		await get_tree().physics_frame
		t += FRAME_S
		if String(c["state"]) == "rest":
			landed_t = t
			break
	var b: AABB = (get_tree().get_first_node_in_group("arena")).call("bounds")
	var pos: Vector3 = c.get("pos", Vector3.ZERO)
	# пол Void — y 0 (bounds начинаются ниже, с −1): цифра лежит ниже торса жертвы и выше низа bounds
	_check("digits_land", landed_t > 0.0 and pos.y >= b.position.y - 0.05 and pos.y < p2.torso().global_position.y and absf(pos.x - vic_x) < 3.0,
		[landed_t, pos, vic_x], ["< 3 s", "on the floor (below the torso)", "|dx| < 3 m"])
	await _wait_real(Tuning.JUICE_DIGIT_REST_S + DamageDigits.SINK_S + 0.3)
	_check("digits_sink", String(c["state"]) == "free", c["state"], "free", "after REST_S + SINK_S")
	_heal([p1, p2])
	await _wait_time_clear()
	# пул: 20 цифр подряд — кусков не больше MAX, старые переиспользуются
	var r0 := int(dg.stats["reused"])
	for i in range(20):
		dg.spawn(5.0 + i, p2.centre_of_mass(), 1.0, Color.RED, false)
	_check("digits_pool", dg.chunks.size() <= Tuning.JUICE_DIGIT_MAX and dg.live_count() <= Tuning.JUICE_DIGIT_MAX and int(dg.stats["reused"]) > r0,
		[dg.chunks.size(), dg.live_count(), int(dg.stats["reused"]) - r0], ["<= %d" % Tuning.JUICE_DIGIT_MAX, "<= max", "> 0"])
	dg.clear()
	# F8: цифры выключены
	HitJuice.digits_on = false
	var s0 := int(dg.stats["spawned"])
	await _strike(p1, p2, 12.0)
	HitJuice.digits_on = true
	_check("digits_toggle", int(dg.stats["spawned"]) == s0, int(dg.stats["spawned"]) - s0, 0, "key minus: HitJuice.digits_on = false")
	_heal([p1, p2])
	await _wait_time_clear()
	# большая цифра — повод N0
	var e0 := juice.events.filter(func(e: Dictionary) -> bool: return e["event"] == "digit_big").size()
	await _strike(p1, p2, 16.0)
	var e1 := juice.events.filter(func(e: Dictionary) -> bool: return e["event"] == "digit_big").size()
	_check("digits_big_event", e1 == e0 + 1, e1 - e0, 1, "16 HP ≥ JUICE_DIGIT_BIG")
	_heal([p1, p2])
	await _wait_time_clear()


# ------------------------------------------------------------------ время

func _time_checks(p1: Doll, p2: Doll) -> void:
	# клавиши (автор 02.10: без F1–F12): физические 0 — следующий вариант, «−» — цифры
	HitJuice.time_variant = Tuning.JUICE_TIME_DEFAULT
	var k0 := InputEventKey.new()
	k0.physical_keycode = KEY_0
	k0.pressed = true
	juice._unhandled_input(k0)
	var v_after := HitJuice.time_variant
	var km := InputEventKey.new()
	km.physical_keycode = KEY_MINUS
	km.pressed = true
	var d0 := HitJuice.digits_on
	juice._unhandled_input(km)
	var d1 := HitJuice.digits_on
	juice._unhandled_input(km)
	_check("keys_digits", v_after == "cinema" and d1 == not d0 and HitJuice.digits_on == d0, [v_after, d0, d1, HitJuice.digits_on],
		["cinema", "toggled", "back"], "key 0 → next variant, key minus → digits on/off")
	HitJuice.time_variant = Tuning.JUICE_TIME_DEFAULT
	var order: Array = []
	HitJuice.time_variant = Tuning.JUICE_TIME_DEFAULT
	for i in range(Tuning.JUICE_TIME_ORDER.size()):
		order.append(HitJuice.cycle_time_variant())
	_check("time_cycle", order == ["cinema", "web", "off", "stop"], order, ["cinema", "web", "off", "stop"], "key 0 order from stop")
	var want := {
		"stop": {"light": ["light_stop", "light_slow"], "heavy": ["heavy_slow"], "heavy_scale": 0.4},
		"cinema": {"light": [], "heavy": ["heavy_slow"], "heavy_scale": 0.25},
		"web": {"light": ["light_slow"], "heavy": ["heavy_stop2", "heavy_slow"], "heavy_scale": 0.38},
		"off": {"light": [], "heavy": [], "heavy_scale": 1.0},
	}
	for vname in ["stop", "cinema", "web", "off"]:
		HitJuice.time_variant = vname
		await _wait_time_clear()
		await _wait_real(0.3)
		await _strike(p1, p2, 7.0)
		var lt := _juice_tags()
		await _wait_time_clear()
		_heal([p1, p2])
		await _ticks(20)
		await _strike(p1, p2, 12.0)
		var ht := _juice_tags()
		var slow_scale := 1.0
		for e in match_node.get("_time_effects"):
			if String((e as Dictionary).get("tag", "")) == "heavy_slow":
				slow_scale = float(e["scale"])
		var w: Dictionary = want[vname]
		var ok := _same(lt, w["light"]) and _same(ht, w["heavy"]) and absf(slow_scale - float(w["heavy_scale"])) < 0.01
		_check("time_variant_" + vname, ok, [lt, ht, slow_scale], [w["light"], w["heavy"], w["heavy_scale"]])
		if vname == "cinema":
			var t0 := Time.get_ticks_usec()
			var real := 0.0
			var frames := 0
			while (Engine.time_scale < 1.0 or not match_node.time_scale_tags().is_empty()) and frames < 200:
				await _frames(1)
				real += FxClock.real_delta(get_process_delta_time())
				frames += 1
			var want_s := Tuning.HITFX_HEAVY_STOP_S + float(Tuning.JUICE_TIME_VARIANTS["cinema"]["heavy_s"])
			_check("time_cinema_length", absf(real - want_s) <= 3.0 * FRAME_S, real * 1000.0, "%.0f ± 50 ms" % (want_s * 1000.0))
		await _wait_time_clear()
		_heal([p1, p2])
		await _ticks(20)
	HitJuice.time_variant = Tuning.JUICE_TIME_DEFAULT
	FxPreset.set_preset("off", get_tree())
	await _wait_real(0.3)
	await _strike(p1, p2, 7.0)
	var a := _juice_tags()
	await _ticks(20)
	await _strike(p1, p2, 12.0)
	var b := _juice_tags()
	FxPreset.set_preset("full", get_tree())
	_check("time_preset_off", a.is_empty() and b.is_empty(), [a, b], [[], []])
	await _wait_time_clear()
	_heal([p1, p2])


func _juice_tags() -> Array:
	var out: Array = []
	for t in match_node.time_scale_tags():
		if String(t) in ["light_stop", "light_slow", "heavy_slow", "heavy_stop2"]:
			out.append(t)
	out.sort()
	return out


static func _same(a: Array, b: Array) -> bool:
	var x := a.duplicate()
	var y := b.duplicate()
	x.sort()
	y.sort()
	return x == y


# ------------------------------------------------------------------ табло

func _caption_checks(p1: Doll, p2: Doll) -> void:
	var c1 := HitJuice.impact_caption({"score": 18.44, "damage": 16.0}, "X")
	_check("caption_format", c1 == "IMPACT 18.4G", c1, "IMPACT 18.4G")
	await _wait_time_clear()
	match_node.fight_time = 30.0
	match_node.hit_tiers.force_next = "crit"
	await get_tree().physics_frame
	var dir := Vector3(signf(p2.torso().global_position.x - p1.torso().global_position.x), 0, 0)
	var pos := p2.torso().global_position
	p2.hit_meta = {"speed": 12.0, "weapon_id": "", "striker": p1.torso(), "combo_mult": 1.0, "double_blow": false,
		"knockback_mult": 1.0, "stun_s": 0.0, "dir": dir, "striker_name": "Hand_R"}
	p2.take_damage(24.0, p1, "Torso", pos, -dir, "body")
	match_node.on_hit(p2, p1, 24.0, "body", pos, 1, false, "", 12.0)
	await _frames(3)
	var cc := match_node.get_node_or_null("HitFxDirector/CritCinematic")
	var cap := ""
	if cc != null:
		var ov: Variant = cc.get("overlay")
		if ov is CritOverlay:
			cap = (ov as CritOverlay).caption.text
	_check("caption_crit", cap.begins_with("IMPACT ") and cap.ends_with("G"), cap, "IMPACT …G (CritOverlay)")
	var guard := 0
	while (match_node.camera_owner() != "" or not match_node.time_scale_tags().is_empty()) and guard < 400:
		await _frames(1)
		guard += 1
	_heal([p1, p2])


# ------------------------------------------------------------------ N0

func _n0_checks() -> void:
	var missing: Array = []
	for ev in ["digit_big", "metal", "worn", "digits_pile"]:
		var vs: Array = N0Lines.LINES.get(ev, [])
		if vs.is_empty():
			missing.append(ev)
		for v in vs:
			if not (v as Dictionary).has("ru") or not (v as Dictionary).has("en"):
				missing.append(ev + ":lang")
	_check("n0_lines", missing.is_empty() and not N0Lines.is_major("digit_big"), missing, [], "ru + en, minor")
	var l := N0Lines.new()
	l.minor_chance = 1.0
	var txt := l.pick("digit_big", 100.0, false, [17])
	_check("n0_digit_text", txt.contains("17"), txt, "contains 17")


# ------------------------------------------------------------------ restart

func _restart_checks() -> void:
	juice.digits.spawn(9.0, Vector3(0, 3, 0), 1.0, Color.RED, false)
	match_node.restart()
	await _frames(2)
	_check("restart_clears", juice.digits.live_count() == 0, juice.digits.live_count(), 0, "COUNTDOWN")


func _finish() -> void:
	Engine.time_scale = 1.0
	var fails := 0
	for c in report["checks"]:
		if not bool(c["ok"]):
			fails += 1
	report["info"]["events"] = juice.events.duplicate() if juice != null else []
	report["info"]["digits"] = juice.digits.stats.duplicate() if juice != null else {}
	report["info"]["godot"] = Engine.get_version_info()["string"]
	var f := FileAccess.open(ProjectSettings.globalize_path(String(cfg["out"])), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  ", false))
		f.close()
	print("=== juice_probe: %d checks, %d failed → %s ===" % [report["checks"].size(), fails, "OK" if report["ok"] else "FAIL"])
	get_tree().quit(0 if report["ok"] else 1)
