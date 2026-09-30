## Проба покраски куклы (docs/plan-demo/BODY_PAINT.md §7, рантайм; мастерская — в workshop_probe).
## Headless: godot --headless --path . --fixed-fps 60 res://tests/paint_probe.tscn [-- "report=<путь.json>"]
##   → tests/paint_probe_report.json, печатает PAINT PROBE OK / PAINT PROBE FAIL, код выхода 0/1.
##
## Проверки (счётчик checks, в отчёте — числа по разделам и провалы):
##   • PaintLayer: размеры сетки (≤ 40 ячеек по длинной оси, ≥ 4 по каждой, ячейка ≥ 8 мм, ≤ 64 000 ячеек, габарит слоя покрывает
##     меш, cell_for_aabb = ячейка for_aabb); stamp / spray меняют альфу только в радиусе, цвет «поверх» (центр штампа — цвет,
##     половинный штамп — смесь), нажим spray — потолок альфы, spray детерминирован rng; цвет > 1 (ColorPicker с яркостью) —
##     зажат: stamp / fill не переполняют байт, rgb ≤ a; erase обнуляет, частичный — половина, слабый ластик (нажим 0.1) доводит
##     слой до пустого; fill / clear; выборка — не предумноженный цвет; to_dict / from_dict — те же байты, пустой слой после zstd
##     < 1 КБ, битые словари → null (и размеры, которых for_aabb не даёт: 4000 × 4 × 4, 2³, габарит 1 мкм); pattern всех видов
##     детерминирован seed (другой seed — другие байты, кроме gradient), не пустой; частями (pattern_begin / pattern_run по 1 мкс) —
##     байт в байт как целиком; mirror_x — ровно отражение по X рисунка слоя с отражённым габаритом; текстура (размеры, грязные
##     срезы, set_data / mark_dirty — отмена в живом слое);
##     скорость: spray радиусом 5 см на детали в 40 ячеек (ячейка 8 мм) — среднее < SPRAY_MS_MAX;
##   • KitImages: импорт фикстуры tests/fixtures/paint/sticker_fixture.png — id 16 hex, стабилен, файл в user://kit_images,
##     texture(id) не null; большая картинка → ≤ 512 с теми же пропорциями; jpg / webp, jpg под именем .png и .jfif; нет файла /
##     не картинка / чужое расширение → "" (с причиной ERR_*); HEIC → ERR_HEIC; заголовок png 20000² → ERR_TOO_BIG_PIXELS без
##     декодирования; delete_image; texture битых id → null; все трафареты грузятся, с мипмапами (если папки ещё нет — пропуск);
##   • шейдер paint_overlay: грузится, ShaderMaterial с ним создаётся, uniform-ы на месте (если headless их отдаёт);
##   • сборка ModularDoll с paint / stickers / face — kit_human (+ рога kit_deco_horns на Anchor_Top головы: слитая деталь,
##     корень меша Mesh_<uid>), старая human (wood_*, Mesh_R, FacePlate внутри меша головы), kit_brawler (коннекторы): чертёж
##     validate() без ошибок, сохраняется в .tres и читается обратно без потерь; ручки paint_handle с теми же байтами; у всех
##     не-Shirt/Face поверхностей окрашенных узлов next_pass с paint_tex этой ручки, у Shirt* / Face* и неокрашенного узла — нет;
##     коннекторы не красятся; Shirt — в цвете игрока; общие ресурсы материалов не тронуты; наклейки — меш-декали (MeshInstance3D
##     ребёнком тела узла, кадр = корень меша × xf, размер, материал: картинка, цвет, альфа, поверх краски), с треугольниками; бит у
##     всех мешей куклы, кроме коннекторов (у них — нет); FacePlate получил картинку; битые paint / stickers / face — кукла собирается
##     без них; наклейка через пояс kit_human: ни одного треугольника на Shirt*, треугольники пояса в коробке пропущены; размер из
##     чертежа — не больше 40 см;
##   • ensure_paint / paint_handle / add_sticker на живой кукле; «респавн» (новый инстанс из того же чертежа, как
##     Match.respawn_doll) — та же краска, наклейки, фото;
##   • физика с краской и без: массы, центры масс, физматериалы, формы, суставы одинаковы; толчок в воздухе (без контактов,
##     прогоны по очереди в одной точке) — смещение каждой части через 60 кадров совпадает до PHYS_TOL.
extends Node3D

const MODULAR_SCENE := "res://scenes/body/modular_doll.tscn"
const KIT_HUMAN_BP := "res://data/body/blueprints/kit_human.tres"
const HUMAN_BP := "res://data/body/blueprints/human.tres"
const BRAWLER_BP := "res://data/body/blueprints/kit_brawler.tres"
const FIXTURE := "res://tests/fixtures/paint/sticker_fixture.png"
const SPRAY_MS_MAX := 2.0
const PHYS_TOL := 1e-4
const PHYS_FRAMES := 60
const AIR_POS := Vector3(0, 6, 0)
const PUSH := Vector3(40, 25, 0)
## Узел, который в проверке остаётся без краски (предплечье L у всех трёх кукол).
const UNPAINTED_UID := "2"

var report_path := "res://tests/paint_probe_report.json"
var checks := 0
var failures: PackedStringArray = []
var notes: PackedStringArray = []
var report := {"layer": {}, "images": {}, "shader": {}, "dolls": {}, "garbage": {}, "live": {}, "respawn": {}, "physics": {}, "perf": {}, "sticker_guard": {}}

var fixture_id := ""
var stencil_id := ""
var phys_runs: Array = []      # [имя, BodyBlueprint]
var phys_idx := 0
var phys_frame := -1
var phys_doll: ModularDoll
var phys_p0: Dictionary = {}
var phys_disp: Dictionary = {}  # имя прогона -> {часть: смещение}
var warmup := 5                 # кадров до прогонов физики: куклы проверок успевают освободиться
var done := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "report":
				report_path = p[1]
	_floor()
	_check_layer()
	_check_patterns()
	_check_perf()
	_check_images()
	_check_shader()
	var bp_kit := _dup_bp(load(KIT_HUMAN_BP))
	bp_kit.nodes.append({"uid": "D", "part": "kit_deco_horns", "parent": "H", "anchor": "Anchor_Top"})
	var kit := _check_doll("kit_human_horns", bp_kit, Vector3(-30, 0, 0), 1)
	var human := _check_doll("human", _dup_bp(load(HUMAN_BP)), Vector3(-40, 0, 0), 2)
	_check_doll("kit_brawler", _dup_bp(load(BRAWLER_BP)), Vector3(-50, 0, 0), 3)
	_check_garbage(Vector3(-60, 0, 0))
	_check_sticker_guard(Vector3(-70, 0, 0))
	if not kit.is_empty():
		phys_runs.append(["kit_plain", kit["plain_bp"]])
		phys_runs.append(["kit_paint", kit["paint_bp"]])
	if not human.is_empty():
		phys_runs.append(["human_plain", human["plain_bp"]])
		phys_runs.append(["human_paint", human["paint_bp"]])


func _physics_process(_dt: float) -> void:
	if done:
		return
	if warmup > 0:
		warmup -= 1
		return
	if phys_idx >= phys_runs.size():
		_phys_verdict()
		_finish()
		done = true
		return
	phys_frame += 1
	var run: Array = phys_runs[phys_idx]
	if phys_frame == 0:
		phys_doll = _spawn(run[1], AIR_POS, 0)
		return
	if phys_frame == 1:
		phys_p0 = _part_positions(phys_doll)
		var torso := phys_doll.torso()
		if torso != null:
			torso.apply_central_impulse(PUSH)
		var hd := phys_doll.head()
		if hd != null:
			hd.apply_impulse(Vector3(-3, 2, 0), Vector3(0.05, 0.05, 0))
		return
	if phys_frame == PHYS_FRAMES + 1:
		var p1 := _part_positions(phys_doll)
		var disp := {}
		for k in phys_p0:
			if p1.has(k):
				disp[k] = (p1[k] as Vector3) - (phys_p0[k] as Vector3)
		phys_disp[String(run[0])] = disp
		phys_doll.queue_free()
		phys_doll = null
		phys_idx += 1
		phys_frame = -1


# --- PaintLayer ---

func _check_layer() -> void:
	var r := {}
	# размеры сетки
	var cases := {
		"limb_40": AABB(Vector3(-0.16, -0.08, -0.08), Vector3(0.32, 0.16, 0.16)),
		"big": AABB(Vector3(-0.5, -0.25, -0.125), Vector3(1.0, 0.5, 0.25)),
		"tiny_flat": AABB(Vector3(0, 0, 0), Vector3(0.05, 0.02, 0.0)),
		"kit_core": AABB(Vector3(-0.2275, -0.275, -0.202725), Vector3(0.455, 0.555, 0.437629)),
		"cube_max": AABB(Vector3(-0.2, -0.2, -0.2), Vector3(0.4, 0.4, 0.4)),
	}
	var dims := {}
	for k in cases:
		var box: AABB = cases[k]
		var l := PaintLayer.for_aabb(box)
		dims[k] = [l.res, snappedf(l.cell_size(), 0.0001)]
		var mx := maxi(l.res.x, maxi(l.res.y, l.res.z))
		var mn := mini(l.res.x, mini(l.res.y, l.res.z))
		_check(mx <= PaintLayer.MAX_CELLS and mn >= PaintLayer.MIN_CELLS, "PaintLayer.for_aabb(%s): ячеек по осям 4..40" % k, l.res)
		_check(l.cell_count() <= PaintLayer.MAX_TOTAL and l.data.size() == l.cell_count() * 4, "for_aabb(%s): ≤ 64000 ячеек, data = ×4" % k, [l.cell_count(), l.data.size()])
		_check(l.cell_size() >= PaintLayer.MIN_CELL - 1e-7, "for_aabb(%s): ячейка ≥ 8 мм" % k, l.cell_size())
		_check(l.aabb.grow(1e-5).encloses(box.abs()), "for_aabb(%s): габарит слоя покрывает меш" % k, [l.aabb, box])
		_check(l.is_empty(), "for_aabb(%s): новый слой пуст" % k)
		_check(is_equal_approx(PaintLayer.cell_for_aabb(box), l.cell_size()), "cell_for_aabb(%s) = ячейка for_aabb" % k, [PaintLayer.cell_for_aabb(box), l.cell_size()])
	_check(dims["limb_40"][0] == Vector3i(40, 20, 20), "for_aabb 0.32×0.16×0.16 → 40×20×20 (ячейка 8 мм)", dims["limb_40"])
	_check(dims["big"][0] == Vector3i(40, 20, 10), "for_aabb 1×0.5×0.25 → 40×20×10", dims["big"])
	_check(dims["tiny_flat"][0] == Vector3i(7, 4, 4), "for_aabb 5×2×0 см → 7×4×4 (ячейка 8 мм, минимум 4)", dims["tiny_flat"])
	_check(dims["cube_max"][0] == Vector3i(40, 40, 40), "for_aabb куб 0.4 → 40³ = 64000", dims["cube_max"])
	r["dims"] = dims

	# stamp: альфа только в радиусе, цвет «поверх»
	var l := PaintLayer.for_aabb(cases["limb_40"])
	var p := Vector3(0.01, 0.003, -0.002)
	var before := l.data.duplicate()
	l.stamp(p, 0.03, Color(1, 0, 0), 1.0, 0.5)
	var ch := _changed(l, before, p)
	_check(ch["n"] > 0 and ch["max_d"] <= 0.03 + 1e-6, "stamp: альфа меняется только в радиусе 3 см", ch)
	var c0 := l.sample(p)
	_check(_col_close(c0, Color(1, 0, 0, 1), 0.02), "stamp strength 1: в центре — сплошной красный", c0)
	l.stamp(p, 0.02, Color(0, 0, 1), 0.5, 1.0)
	var c1 := l.sample(p)
	_check(_col_close(c1, Color(0.5, 0, 0.5, 1), 0.03), "stamp синим 0.5 поверх красного — смесь 50/50, альфа 1", c1)
	var lh := PaintLayer.for_aabb(cases["limb_40"])
	lh.stamp(p, 0.03, Color(0.2, 0.8, 0.4), 0.5, 1.0)
	var c2 := lh.sample(p)
	_check(_col_close(c2, Color(0.2, 0.8, 0.4, 0.5), 0.02), "выборка: цвет не предумножен (половинная альфа — тот же цвет)", c2)
	_check(_col_close(lh.cell_color(20, 10, 10), c2, 0.03), "cell_color = выборка в центре ячейки", [lh.cell_color(20, 10, 10), c2])
	r["stamp_center"] = [c0, c1, c2]

	# erase
	var le := PaintLayer.for_aabb(cases["limb_40"])
	le.stamp(p, 0.03, Color(1, 1, 0), 1.0, 0.5)
	le.erase(p, 0.06, 1.0)
	_check(le.is_empty(), "erase strength 1 радиусом 2× штампа — слой пуст (обнуляет)")
	le.stamp(p, 0.03, Color(1, 1, 0), 1.0, 1.0)
	le.erase(p, 0.03, 0.5)
	var ce := le.sample(p)
	_check(absf(ce.a - 0.5) < 0.02 and _col_close(Color(ce.r, ce.g, ce.b), Color(1, 1, 0), 0.03), "erase 0.5 — альфа половина, цвет тот же", ce)
	# слабый ластик (мастерская: нажим 0.1 × 0.45) и обычный доводят слой до пустого (округление не застревает на 1–11 / 255);
	# ластик вдвое шире мазка: край мягкого ластика (сила → 0) и не должен стирать до конца
	var weak := {}
	for w in [0.045, 0.3825, 0.45]:
		var lw := PaintLayer.for_aabb(cases["limb_40"])
		lw.stamp(p, 0.03, Color(0.3, 0.9, 0.2), 1.0, 1.0)
		for i in 400:
			lw.erase(p, 0.06, w)
		var mx := 0
		for i in range(3, lw.data.size(), 4):
			mx = maxi(mx, lw.data[i])
		weak[str(w)] = mx
		_check(lw.is_empty(), "erase %.3f × 400 — слой пуст (альфа не застревает)" % w, mx)
	r["erase_weak_max_alpha"] = weak
	# цвет > 1 (ColorPicker с ползунком яркости): зажат — байт не переполняется, rgb ≤ a, красный не слабее красного 1.0
	var lc1 := PaintLayer.for_aabb(cases["limb_40"])
	var lc2 := PaintLayer.for_aabb(cases["limb_40"])
	lc1.stamp(p, 0.03, Color(1.5, 0.2, 0.2), 0.7, 1.0)
	lc2.stamp(p, 0.03, Color(1.0, 0.2, 0.2), 0.7, 1.0)
	var i0 := ((10 * 20 + 10) * 40 + 21) * 4
	_check(lc1.data == lc2.data, "stamp цветом r = 1.5 — как r = 1.0 (зажат, байт не переполнен)", [lc1.data.slice(i0, i0 + 4), lc2.data.slice(i0, i0 + 4)])
	var lcf1 := PaintLayer.for_aabb(cases["limb_40"])
	lcf1.fill(Color(1.5, 0.2, 0.2), 0.7)
	_check(lcf1.data[0] <= lcf1.data[3] and lcf1.data[1] <= lcf1.data[3] and lcf1.data[0] >= 170, "fill цветом r = 1.5, 0.7 — rgb ≤ a (предумножение цело)", lcf1.data.slice(0, 4))
	var lcf2 := PaintLayer.for_aabb(cases["limb_40"])
	lcf2.fill(Color(0.4, 0.2, 0.2), 1.0)
	lcf2.fill(Color(2.0, -1.0, 0.2), 0.5)
	var ok_rgb := true
	for q in range(0, lcf2.data.size(), 4):
		if lcf2.data[q] > lcf2.data[q + 3] or lcf2.data[q + 1] > lcf2.data[q + 3] or lcf2.data[q + 2] > lcf2.data[q + 3]:
			ok_rgb = false
			break
	_check(ok_rgb, "fill поверх цветом (2, −1, 0.2), 0.5 — rgb ≤ a везде", lcf2.data.slice(0, 4))

	# spray: только в радиусе, потолок нажима, детерминизм
	var ls := PaintLayer.for_aabb(cases["limb_40"])
	var before_s := ls.data.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 12:
		ls.spray(p, 0.05, Color(0.1, 0.6, 1.0), 0.5, 0.4, rng)
	var chs := _changed(ls, before_s, p)
	_check(chs["n"] > 0 and chs["max_d"] <= 0.05 + 1e-6, "spray: альфа меняется только в радиусе 5 см", chs)
	_check(chs["max_a"] <= 128, "spray opacity 0.5: альфа ≤ 0.5 (нажим — потолок)", chs["max_a"])
	var ls2 := PaintLayer.for_aabb(cases["limb_40"])
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 7
	for i in 12:
		ls2.spray(p, 0.05, Color(0.1, 0.6, 1.0), 0.5, 0.4, rng2)
	_check(ls2.data == ls.data, "spray детерминирован состоянием rng (тот же seed — те же байты)")
	var cs := ls.sample(p)
	_check(cs.a > 0.3 and _col_close(Color(cs.r, cs.g, cs.b), Color(0.1, 0.6, 1.0), 0.03), "spray: в центре цвет баллончика", cs)
	r["spray"] = chs

	# fill / clear
	var lf := PaintLayer.for_aabb(cases["kit_core"])
	lf.fill(Color(0.2, 0.7, 0.3))
	_check(_col_close(lf.sample(Vector3(0.1, -0.2, 0.15)), Color(0.2, 0.7, 0.3, 1), 0.01), "fill: вся деталь в цвет", lf.sample(Vector3(0.1, -0.2, 0.15)))
	lf.fill(Color(1, 1, 1), 0.5)
	_check(_col_close(lf.sample(Vector3.ZERO), Color(0.6, 0.85, 0.65, 1), 0.02), "fill 0.5 белым поверх — смесь", lf.sample(Vector3.ZERO))
	lf.clear()
	_check(lf.is_empty(), "clear — пусто")
	var lf2 := PaintLayer.for_aabb(cases["kit_core"])
	lf2.fill(Color(1, 0, 0), 0.5)
	_check(_col_close(lf2.sample(Vector3.ZERO), Color(1, 0, 0, 0.5), 0.01), "fill 0.5 по пустому — полупрозрачный цвет", lf2.sample(Vector3.ZERO))

	# сейв
	var d := ls.to_dict()
	var back := PaintLayer.from_dict(d)
	_check(back != null and back.data == ls.data and back.res == ls.res and back.aabb.is_equal_approx(ls.aabb), "to_dict → from_dict: те же байты, res, aabb")
	var empty_max := PaintLayer.for_aabb(cases["cube_max"]).to_dict()
	var empty_limb := PaintLayer.for_aabb(cases["limb_40"]).to_dict()
	var zsz := (empty_max["data"] as PackedByteArray).size()
	_check(zsz < 1024 and (empty_limb["data"] as PackedByteArray).size() < 1024, "пустой слой после zstd < 1 КБ (64000 ячеек: %d байт)" % zsz)
	r["zstd_bytes"] = {"empty_64000": zsz, "empty_16000": (empty_limb["data"] as PackedByteArray).size(), "spray_16000": (d["data"] as PackedByteArray).size()}
	for k in ["v", "res", "aabb", "data", "size"]:
		_check(d.has(k), "to_dict: ключ %s" % k)
	var bad := {
		"not_dict": 42,
		"empty": {},
		"version": _with(d, "v", 2),
		"res_mismatch": _with(d, "res", Vector3i(40, 20, 21)),
		"size_mismatch": _with(d, "size", 12),
		"res_too_big": _with(_with(d, "res", Vector3i(100, 100, 100)), "size", 4000000),
		"aabb_zero": _with(d, "aabb", AABB(Vector3.ZERO, Vector3(0.1, 0.0, 0.1))),
		"aabb_type": _with(d, "aabb", "x"),
		"data_type": _with(d, "data", [1, 2, 3]),
		"data_no_magic": _with(d, "data", PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])),
		"raw_not_zstd": _with(d, "data", ls.data),
		"res_axis_4000": _bad_layer(Vector3i(4000, 4, 4), AABB(Vector3.ZERO, Vector3(40.0, 0.04, 0.04))),
		"res_axis_2": _bad_layer(Vector3i(2, 2, 2), AABB(Vector3.ZERO, Vector3(0.02, 0.02, 0.02))),
		"aabb_micro": _bad_layer(Vector3i(4, 4, 4), AABB(Vector3.ZERO, Vector3.ONE * 1e-6)),
	}
	var bad_ok := []
	for k in bad:
		if PaintLayer.from_dict(bad[k]) != null:
			bad_ok.append(k)
	_check(bad_ok.is_empty(), "from_dict битых данных → null", bad_ok)
	var junk := (d["data"] as PackedByteArray).duplicate()
	var tail := junk.slice(0, 4)   # магия zstd, дальше мусор (движок пишет ошибку распаковки — ожидаемо)
	tail.append_array(PackedByteArray([7, 7, 7, 7, 7, 7, 7, 7, 7, 7]))
	_check(PaintLayer.from_dict(_with(d, "data", tail)) == null, "from_dict: магия zstd + мусор → null")

	# текстура
	var tex := ls.make_texture()
	_check(tex != null and tex.get_width() == ls.res.x and tex.get_height() == ls.res.y and tex.get_depth() == ls.res.z, "make_texture: 3D-текстура res", [tex.get_width(), tex.get_height(), tex.get_depth()] if tex != null else null)
	var dr0 := ls.dirty_range()
	ls.stamp(Vector3(0.1, 0, 0), 0.01, Color(1, 1, 1), 1.0, 1.0)
	var dr1 := ls.dirty_range()
	ls.update_texture(tex)
	var dr2 := ls.dirty_range()
	_check(dr0.y < dr0.x and dr1.y >= dr1.x and dr1.y - dr1.x < ls.res.z - 1 and dr2.y < dr2.x, "грязные срезы: после make_texture чисто, штамп — только его срезы, update_texture — снова чисто", [dr0, dr1, dr2])
	r["dirty_after_stamp"] = dr1
	var snap := ls.data.duplicate()
	ls.stamp(Vector3(-0.1, 0, 0), 0.02, Color(0, 1, 0), 1.0, 1.0)
	ls.update_texture(tex)
	_check(ls.set_data(snap) and ls.data == snap and ls.dirty_range() == Vector2i(0, ls.res.z - 1), "set_data (отмена в живом слое): те же байты, все срезы грязные")
	_check(not ls.set_data(PackedByteArray([1, 2, 3])) and ls.data == snap, "set_data чужого размера — отказ, слой не тронут")
	ls.update_texture(tex)
	ls.mark_dirty()
	_check(ls.dirty_range() == Vector2i(0, ls.res.z - 1), "mark_dirty — все срезы")
	report["layer"] = r


func _check_patterns() -> void:
	var r := {}
	var box := AABB(Vector3(-0.064, -0.277, -0.063), Vector3(0.128, 0.249, 0.126))   # kit_limb_basic_s
	for kind in PaintLayer.KINDS:
		var a := PaintLayer.for_aabb(box)
		var t0 := Time.get_ticks_usec()
		a.pattern(kind, [], 42)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var b := PaintLayer.for_aabb(box)
		b.pattern(kind, [], 42)
		var c := PaintLayer.for_aabb(box)
		c.pattern(kind, [], 43)
		_check(not a.is_empty(), "pattern %s: слой не пуст" % kind)
		_check(a.data == b.data, "pattern %s: тот же seed — те же байты" % kind)
		if kind != "gradient":
			_check(a.data != c.data, "pattern %s: другой seed — другой рисунок" % kind)
		var one := PaintLayer.for_aabb(box)
		one.pattern(kind, [Color(0.9, 0.2, 0.1)], 5, Vector3.RIGHT)
		var three := PaintLayer.for_aabb(box)
		three.pattern(kind, [Color(0.9, 0.2, 0.1), "#2255ff", Color(1, 1, 0)], 5)
		_check(not one.is_empty() and not three.is_empty(), "pattern %s: 1 цвет (ось X) и 3 цвета (строка html) — рисует" % kind)
		var alpha_cells := 0
		for i in range(3, a.data.size(), 4):
			if a.data[i] > 0:
				alpha_cells += 1
		r[kind] = {"ms": snappedf(ms, 0.1), "cells": a.cell_count(), "painted_cells": alpha_cells}
	# частями (срез за вызов) — байт в байт как целиком; mirror_x — ровно отражение рисунка слоя с отражённым по X габаритом
	var box_l := AABB(Vector3(-0.08, -0.277, -0.063), Vector3(0.12, 0.249, 0.126))   # не по центру x: как кисти старой куклы
	var box_r := AABB(Vector3(-(box_l.position.x + box_l.size.x), box_l.position.y, box_l.position.z), box_l.size)
	var slab_bad := []
	var mirror_bad := []
	for kind in PaintLayer.KINDS:
		var one := PaintLayer.for_aabb(box)
		one.pattern(kind, [], 9)
		var part := PaintLayer.for_aabb(box)
		var job := part.pattern_begin(kind, [], 9)
		var calls := 1
		while not part.pattern_run(job, 1):
			calls += 1
		if part.data != one.data or calls < 2:
			slab_bad.append([kind, calls])
		var ll := PaintLayer.for_aabb(box_l)
		ll.pattern(kind, [], 21)
		var lr := PaintLayer.for_aabb(box_r)
		lr.fill(Color(0.2, 0.3, 0.4), 0.3)   # старая краска под рисунком — остаётся на месте (не отражается)
		var base := lr.data.duplicate()
		lr.clear()
		lr.pattern(kind, [], 21, Vector3.UP, true)
		var mism := 0
		for z in ll.res.z:
			for y in ll.res.y:
				for x in ll.res.x:
					var a := ((z * ll.res.y + y) * ll.res.x + x) * 4
					var b := ((z * ll.res.y + y) * ll.res.x + (ll.res.x - 1 - x)) * 4
					if lr.data.slice(b, b + 4) != ll.data.slice(a, a + 4):
						mism += 1
		# старая краска (только слева) под отражённым рисунком — на месте: где рисунок прозрачен, ячейки как были
		var lo := PaintLayer.for_aabb(box_r)
		lo.stamp(lo.cell_center(1, lo.res.y / 2, lo.res.z - 2), 0.03, Color(0.9, 0.1, 0.8), 1.0, 1.0)
		var old := lo.data.duplicate()
		lo.pattern(kind, [], 21, Vector3.UP, true)
		var moved := 0
		for q in range(0, lo.data.size(), 4):
			if lr.data[q + 3] == 0 and lo.data.slice(q, q + 4) != old.slice(q, q + 4):
				moved += 1
		if mism > 0 or ll.res != lr.res or moved > 0:
			mirror_bad.append([kind, mism, moved])
	_check(slab_bad.is_empty(), "pattern_begin / pattern_run по срезу — байт в байт как pattern целиком", slab_bad)
	_check(mirror_bad.is_empty(), "pattern mirror_x — точное отражение по X рисунка на отражённом габарите (все виды)", mirror_bad)
	var over := PaintLayer.for_aabb(box)
	over.fill(Color(0, 0, 1))
	over.pattern("dots", [Color(1, 1, 1)], 3)
	_check(not _has_alpha_below(over, 255), "pattern поверх заливки: прозрачные места раскраски оставляют старую краску")
	var unk := PaintLayer.for_aabb(box)
	unk.pattern("nope", [], 1)
	_check(unk.is_empty(), "pattern неизвестного вида — ничего не рисует (предупреждение)")
	report["layer"]["patterns"] = r


func _check_perf() -> void:
	var r := {}
	for k in ["limb_40x20x20_8mm", "kit_core_14mm"]:
		var box := AABB(Vector3(-0.16, -0.08, -0.08), Vector3(0.32, 0.16, 0.16)) if k.begins_with("limb") \
			else AABB(Vector3(-0.2275, -0.275, -0.202725), Vector3(0.455, 0.555, 0.437629))
		var l := PaintLayer.for_aabb(box)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var pts: Array = []
		for i in 240:
			pts.append(box.get_center() + Vector3(rng.randf_range(-0.4, 0.4) * box.size.x, rng.randf_range(-0.4, 0.4) * box.size.y, rng.randf_range(-0.4, 0.4) * box.size.z))
		var t0 := Time.get_ticks_usec()
		for p in pts:
			l.spray(p, 0.05, Color(1, 0.3, 0.1), 0.8, 0.5, rng)
		var spray_ms := (Time.get_ticks_usec() - t0) / 1000.0 / pts.size()
		var tex := l.make_texture()
		var t1 := Time.get_ticks_usec()
		var upd := 0
		for i in 60:
			l.spray(pts[i], 0.05, Color(0.1, 0.3, 1.0), 0.8, 0.5, rng)
			l.update_texture(tex)
			upd += 1
		var frame_ms := (Time.get_ticks_usec() - t1) / 1000.0 / upd
		var t2 := Time.get_ticks_usec()
		for i in 60:
			l.erase(pts[i], 0.05, 0.8)
		var erase_ms := (Time.get_ticks_usec() - t2) / 1000.0 / 60.0
		var t3 := Time.get_ticks_usec()
		var dd := l.to_dict()
		var t4 := Time.get_ticks_usec()
		PaintLayer.from_dict(dd)
		var t5 := Time.get_ticks_usec()
		r[k] = {"res": l.res, "cell_mm": snappedf(l.cell_size() * 1000.0, 0.1), "spray_ms": snappedf(spray_ms, 0.001),
			"spray_plus_update_ms": snappedf(frame_ms, 0.001), "erase_ms": snappedf(erase_ms, 0.001),
			"to_dict_ms": snappedf((t4 - t3) / 1000.0, 0.01), "from_dict_ms": snappedf((t5 - t4) / 1000.0, 0.01),
			"zstd_bytes": (dd["data"] as PackedByteArray).size()}
		_check(spray_ms < SPRAY_MS_MAX, "spray радиусом 5 см (%s): среднее < %.1f мс" % [k, SPRAY_MS_MAX], snappedf(spray_ms, 0.001))
	report["perf"] = r


# --- KitImages ---

func _check_images() -> void:
	var r := {}
	KitImages.clear_cache()
	var src := ProjectSettings.globalize_path(FIXTURE)
	if not FileAccess.file_exists(FIXTURE):
		var img := Image.create_empty(300, 200, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.2, 0.6, 1.0))
		src = ProjectSettings.globalize_path("user://paint_probe_fixture.png")
		img.save_png(src)
		notes.append("нет %s — фикстура сгенерирована в user://" % FIXTURE)
	var id1 := KitImages.import_file(src)
	var id2 := KitImages.import_file(src)
	_check(KitImages.is_image_id(id1), "import_file фикстуры → id из 16 hex", id1)
	_check(id1 == id2, "import_file: повторный импорт — тот же id", [id1, id2])
	_check(FileAccess.file_exists(KitImages.image_path(id1)), "файл картинки в user://kit_images", KitImages.image_path(id1))
	var tex := KitImages.texture(id1)
	_check(tex != null, "texture(id фикстуры) не null")
	if tex != null:
		_check(maxi(tex.get_width(), tex.get_height()) <= KitImages.MAX_SIDE, "фикстура ≤ 512", [tex.get_width(), tex.get_height()])
		r["fixture_size"] = [tex.get_width(), tex.get_height()]
	KitImages.clear_cache()
	_check(KitImages.texture(id1) != null, "texture(id) после сброса кэша — снова с диска")
	_check(KitImages.list_images().has(id1), "list_images содержит импортированную картинку")
	fixture_id = id1
	r["fixture_id"] = id1
	# большая картинка → ≤ 512, пропорции те же
	var big := Image.create_empty(900, 300, false, Image.FORMAT_RGB8)
	big.fill(Color(0.9, 0.4, 0.1))
	big.fill_rect(Rect2i(100, 50, 300, 100), Color(0.1, 0.2, 0.9))
	var big_path := ProjectSettings.globalize_path("user://paint_probe_big.png")
	big.save_png(big_path)
	var idb := KitImages.import_file(big_path)
	var tb := KitImages.texture(idb)
	_check(tb != null and tb.get_width() == 512 and tb.get_height() == 171, "картинка 900×300 → 512×171", [tb.get_width(), tb.get_height()] if tb != null else idb)
	var jpg_path := ProjectSettings.globalize_path("user://paint_probe.jpg")
	big.save_jpg(jpg_path)
	_check(KitImages.is_image_id(KitImages.import_file(jpg_path)), "import_file jpg")
	var webp_path := ProjectSettings.globalize_path("user://paint_probe.webp")
	big.save_webp(webp_path)
	_check(KitImages.is_image_id(KitImages.import_file(webp_path)), "import_file webp")
	_check(KitImages.import_file("user://paint_probe_nope.png") == "", "import_file несуществующего файла → \"\"")
	_check(KitImages.import_file(ProjectSettings.globalize_path("user://paint_probe.txt")) == "", "import_file чужого расширения → \"\"")
	var g := FileAccess.open("user://paint_probe_garbage.png", FileAccess.WRITE)
	g.store_string("не картинка")
	g.close()
	_check(KitImages.import_file(ProjectSettings.globalize_path("user://paint_probe_garbage.png")) == "", "import_file не-картинки с расширением .png → \"\" (по сигнатуре, без ошибок движка)")
	var jpg_as_png := ProjectSettings.globalize_path("user://paint_probe_jpg_named.png")
	big.save_jpg(jpg_as_png)
	_check(KitImages.is_image_id(KitImages.import_file(jpg_as_png)), "import_file jpg с расширением .png — грузится (формат по сигнатуре)")
	var jfif := ProjectSettings.globalize_path("user://paint_probe_photo.jfif")
	big.save_jpg(jfif)
	_check(KitImages.is_image_id(KitImages.import_file(jfif)), "import_file .jfif (jpg) — грузится")
	_check(KitImages.import_file(ProjectSettings.globalize_path("user://paint_probe_garbage.png")) == "" and KitImages.last_error == KitImages.ERR_UNSUPPORTED,
		"не картинка — причина unsupported", KitImages.last_error)
	_check(KitImages.import_file("user://paint_probe_nope.png") == "" and KitImages.last_error == KitImages.ERR_NOT_FOUND, "нет файла — причина not_found", KitImages.last_error)
	var heic := FileAccess.open("user://paint_probe.heic", FileAccess.WRITE)
	heic.store_buffer(PackedByteArray([0, 0, 0, 24]) + "ftypheic".to_ascii_buffer() + PackedByteArray([0, 0, 0, 0]) + "mif1heic".to_ascii_buffer())
	heic.close()
	var rh := KitImages.import_file_ex(ProjectSettings.globalize_path("user://paint_probe.heic"))
	_check(String(rh["id"]) == "" and String(rh["error"]) == KitImages.ERR_HEIC, "HEIC с iPhone — причина heic («сохрани как JPG»)", rh)
	# заголовок png 20000 × 20000 (400 Мп): отказ по размеру из заголовка, до декодирования
	var hdr := PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13]) + "IHDR".to_ascii_buffer()
	hdr += PackedByteArray([0, 0, 0x4E, 0x20, 0, 0, 0x4E, 0x20, 8, 6, 0, 0, 0, 0, 0, 0, 0])
	var hf := FileAccess.open("user://paint_probe_huge.png", FileAccess.WRITE)
	hf.store_buffer(hdr)
	hf.close()
	var rb := KitImages.import_file_ex(ProjectSettings.globalize_path("user://paint_probe_huge.png"))
	_check(String(rb["id"]) == "" and String(rb["error"]) == KitImages.ERR_TOO_BIG_PIXELS and int(rb["pixels"]) == 400000000,
		"png 20000² — отказ по заголовку (too_big_pixels), без декодирования", rb)
	var jpg_dim := KitImages._header_size(FileAccess.get_file_as_bytes(jpg_path), "jpg")
	var webp_dim := KitImages._header_size(FileAccess.get_file_as_bytes(webp_path), "webp")
	_check(jpg_dim == Vector2i(900, 300) and webp_dim == Vector2i(900, 300), "размер из заголовка jpg / webp", [jpg_dim, webp_dim])
	# удалить картинку
	var tmp := Image.create_empty(33, 17, false, Image.FORMAT_RGBA8)
	tmp.fill(Color(0.8, 0.1, 0.9))
	var tid := KitImages.import_image(tmp)
	KitImages.texture(tid)
	_check(KitImages.delete_image(tid) and not KitImages.list_images().has(tid) and KitImages.texture(tid) == null and not KitImages.delete_image(tid),
		"delete_image: файла и кэша нет, повторно — false", tid)
	_check(not KitImages.delete_image("stencil:star") and not KitImages.delete_image("../x"), "delete_image не-id → false")
	for bad_id in ["", "../project", "0123456789abcdeg", "stencil:", "stencil:../icon", "stencil:nope_nope", "res://nope.png"]:
		_check(KitImages.texture(bad_id) == null, "texture(%s) → null" % bad_id)
	var names := KitImages.stencils()
	r["stencils"] = Array(names)
	if names.is_empty():
		notes.append("трафаретов нет (%s) — проверка трафаретов пропущена" % KitImages.STENCIL_DIR)
	else:
		var missing := []
		for nm in names:
			var st := KitImages.texture(KitImages.STENCIL_PREFIX + nm)
			if st == null or st.get_width() <= 0:
				missing.append(nm)
		_check(missing.is_empty(), "все трафареты грузятся (%d)" % names.size(), missing)
		var no_mip := []
		for nm in names:
			var st2 := KitImages.texture(KitImages.STENCIL_PREFIX + nm)
			if st2 != null and not st2.get_image().has_mipmaps():
				no_mip.append(nm)
		_check(no_mip.is_empty(), "трафареты с мипмапами (наклейка в матче — 10–17 px)", no_mip)
		if names.has("star"):
			_check(names[0] == "star", "трафареты по порядку STENCIL_ORDER (первый — star)", names[0])
		stencil_id = KitImages.STENCIL_PREFIX + (names[0] as String)
	report["images"] = r


func _check_shader() -> void:
	var r := {}
	var sh := BodyPaint.shader()
	_check(sh != null, "шейдер %s грузится" % BodyPaint.SHADER_PATH)
	if sh == null:
		report["shader"] = r
		return
	var code := sh.code
	for s in ["sampler3D paint_tex", "filter_linear", "repeat_disable", "blend_mix", "depth_draw_never", "mat4 to_layer", "roughness_paint"]:
		_check(code.contains(s), "шейдер: %s" % s)
	_check(not code.contains("unshaded"), "шейдер освещён (не unshaded)")
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("paint_tex", PaintLayer.for_aabb(AABB(Vector3.ZERO, Vector3.ONE * 0.1)).make_texture())
	sm.set_shader_parameter("to_layer", Projection(Transform3D.IDENTITY))
	_check(sm.get_shader_parameter("paint_tex") is ImageTexture3D, "ShaderMaterial краски: paint_tex ставится")
	var names := []
	for u in sh.get_shader_uniform_list():
		names.append(String(u["name"]))
	r["uniforms"] = names
	if names.is_empty():
		notes.append("headless не отдаёт uniform-ы шейдера — компиляция проверяется только в окне")
	else:
		for u in ["paint_tex", "to_layer", "aabb_pos", "aabb_size", "roughness_paint"]:
			_check(names.has(u), "шейдер: uniform %s" % u, names)
	report["shader"] = r


# --- куклы ---

## Неокрашенная кукла bp → по её мешам слои краски (все виды раскрасок, штрих баллончика) на все узлы, кроме UNPAINTED_UID,
## наклейки (картинка + трафарет) на ядро и одну деталь, фото на голову → окрашенная кукла; проверки обеих. Возвращает
## {plain_bp, paint_bp} для физики.
func _check_doll(id: String, bp: BodyBlueprint, pos: Vector3, player: int) -> Dictionary:
	var r := {}
	_check(bp.validate().is_empty(), "%s: чертёж без краски собирается" % id, bp.validate())
	var t0 := Time.get_ticks_usec()
	var plain := _spawn(bp, pos, player)
	r["build_plain_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	if not _check(plain.build_errors.is_empty(), "%s: без ошибок сборки" % id, plain.build_errors):
		return {}
	_check(_meshes_without_bit(plain).is_empty(), "%s без краски: бит слоя наклеек у всех MeshInstance3D" % id, _meshes_without_bit(plain))
	var pbp := _dup_bp(bp)
	var expected := {}      # uid -> PackedByteArray
	var stickers := {}      # uid -> Array[Dictionary]
	var head_uid := ""
	var root_uid := ""
	var k := 0
	for n in pbp.nodes:
		var uid := String(n["uid"])
		var d := BlueprintHelper.part(n)
		if d != null and d.kind == "head":
			head_uid = uid
		if String(n.get("parent", "")) == "":
			root_uid = uid
		if uid == UNPAINTED_UID:
			continue
		var root := BodyPaint.mesh_root_of(plain, uid)
		if not _check(root != null, "%s: у узла %s есть корень меша" % [id, uid]):
			continue
		var layer := PaintLayer.for_aabb(BodyPaint.mesh_aabb(root))
		layer.pattern(PaintLayer.KINDS[k % PaintLayer.KINDS.size()], [], 100 + k)
		var rng := RandomNumberGenerator.new()
		rng.seed = k
		layer.spray(BodyPaint.mesh_aabb(root).get_center(), 0.04, Color(0.1, 0.9, 0.2), 1.0, 0.5, rng)
		k += 1
		n["paint"] = layer.to_dict()
		expected[uid] = layer.data
	for uid in [root_uid, "1"]:
		var root := BodyPaint.mesh_root_of(plain, uid)
		if root == null or fixture_id == "":
			continue
		var box := BodyPaint.mesh_aabb(root)
		var st: Array = [{"img": fixture_id, "xf": _surface_xf(root, box, Vector2(0.0, 0.0)), "size": Vector2(0.08, 0.055), "color": Color.WHITE}]
		if stencil_id != "":
			st.append({"img": stencil_id, "xf": _surface_xf(root, box, Vector2(0.0, 0.25)).rotated_local(Vector3.UP, deg_to_rad(30)), "size": Vector2(0.05, 0.05), "color": Color(1, 0.2, 0.2)})
		pbp.find_node(uid)["stickers"] = st
		stickers[uid] = st
	if head_uid != "" and fixture_id != "":
		pbp.find_node(head_uid)["face"] = fixture_id
	if bp.find_node("D").has("part"):
		r["merged_mesh_root"] = String(BodyPaint.mesh_root_of(plain, "D").name) if BodyPaint.mesh_root_of(plain, "D") != null else ""
		_check(r["merged_mesh_root"] == "Mesh_D", "%s: у слитой детали D корень меша Mesh_D на теле-хозяине" % id, r["merged_mesh_root"])
	_check(pbp.validate().is_empty(), "%s: чертёж с paint / stickers / face — validate() без ошибок" % id, pbp.validate())
	# сейв чертежа (как CraftEdit.save — ResourceSaver .tres): краска, наклейки и фото переживают запись и чтение
	var tres := "user://paint_probe_%s.tres" % id
	if _check(ResourceSaver.save(pbp, tres) == OK, "%s: чертёж с краской сохраняется в .tres" % id):
		var back := ResourceLoader.load(tres, "", ResourceLoader.CACHE_MODE_IGNORE) as BodyBlueprint
		var same_paint := 0
		var same_st := 0
		for uid in expected:
			var l2 := PaintLayer.from_dict(back.find_node(uid).get("paint")) if back != null else null
			if l2 != null and l2.data == expected[uid]:
				same_paint += 1
		for uid in stickers:
			var a: Variant = back.find_node(uid).get("stickers") if back != null else null
			if a is Array and (a as Array).size() == (stickers[uid] as Array).size():
				var b0: Dictionary = (a as Array)[0]
				var s0: Dictionary = (stickers[uid] as Array)[0]
				if String(b0["img"]) == String(s0["img"]) and (b0["xf"] as Transform3D).is_equal_approx(s0["xf"]) and (b0["size"] as Vector2).is_equal_approx(s0["size"]) and (b0["color"] as Color).is_equal_approx(s0["color"]):
					same_st += 1
		_check(same_paint == expected.size() and same_st == stickers.size(), "%s: .tres → краска (байты), наклейки (img, xf, size, color) те же" % id, [same_paint, expected.size(), same_st, stickers.size()])
		if head_uid != "" and back != null:
			_check(String(back.find_node(head_uid).get("face", "")) == fixture_id, "%s: .tres → фото головы то же" % id)
		r["tres_bytes"] = FileAccess.get_file_as_bytes(tres).size()
	var t1 := Time.get_ticks_usec()
	var painted := _spawn(pbp, pos + Vector3(0, 0, -4), player)
	r["build_painted_ms"] = snappedf((Time.get_ticks_usec() - t1) / 1000.0, 0.1)
	_check(painted.build_errors.is_empty(), "%s с краской: без ошибок сборки" % id, painted.build_errors)
	r["painted"] = _check_painted(id, painted, expected, stickers, head_uid, player)
	_check_same_physics(id, plain, painted)
	_check_shared_untouched(id)
	# ensure_paint / add_sticker на живой кукле (неокрашенный узел)
	if id == "kit_human_horns":
		_check_live(plain)
		_check_respawn(painted, expected, stickers, head_uid)
	plain.queue_free()
	painted.queue_free()
	report["dolls"][id] = r
	return {"plain_bp": bp, "paint_bp": pbp}


func _check_painted(id: String, d: ModularDoll, expected: Dictionary, stickers: Dictionary, head_uid: String, player: int) -> Dictionary:
	var r := {"paint_surfaces": 0, "protected_surfaces": 0, "paint_materials": 0, "decals": 0, "inpass": 0, "overlay": 0, "overlay_why": {}}
	for uid in expected:
		var h := d.paint_handle(uid)
		if not _check(not h.is_empty(), "%s: paint_handle(%s) есть" % [id, uid]):
			continue
		_check((h["layer"] as PaintLayer).data == expected[uid], "%s: слой %s — те же байты, что в чертеже" % [id, uid])
		_check(h["tex"] is ImageTexture3D, "%s: ручка %s — ImageTexture3D" % [id, uid])
		r["paint_materials"] += (h["materials"] as Array).size()
		var root := BodyPaint.mesh_root_of(d, uid)
		_check(h["mesh_root"] == root, "%s: ручка %s — корень меша узла" % [id, uid])
		var n_paint := 0
		for mi in BodyPaint.meshes(root):
			var m := mi as MeshInstance3D
			for s in m.mesh.get_surface_count():
				var mat := m.get_active_material(s)
				var pp := BodyPaint.paint_pass(mat)
				if BodyPaint.is_protected(mat):
					r["protected_surfaces"] += 1
					_check(pp == null, "%s: %s/%s поверхность %d (%s) — без краски" % [id, uid, m.name, s, mat.resource_name if mat != null else "null"])
				else:
					n_paint += 1
					_check(pp != null and pp.get_shader_parameter("paint_tex") == h["tex"], "%s: %s/%s поверхность %d (%s) — краска с paint_tex узла" % [id, uid, m.name, s, mat.resource_name])
					if mat.has_meta(BodyPaint.INPASS_META):
						r["inpass"] += 1
						var src: Material = mat.get_meta(BodyPaint.INPASS_META)
						_check(pp == mat and mat.resource_name == src.resource_name and mat.next_pass == src.next_pass,
							"%s: %s/%s поверхность %d — двойник: имя и next_pass исходника" % [id, uid, m.name, s])
					else:
						r["overlay"] += 1
						var why := BodyPaint.inpass_block(mat)
						r["overlay_why"][why] = int(r["overlay_why"].get(why, 0)) + 1
		_check(n_paint > 0, "%s: у узла %s окрашенные поверхности есть" % [id, uid])
		r["paint_surfaces"] += n_paint
	# кит и старая кукла: все красимые поверхности — краска в том же проходе (без второго освещённого прохода, BODY_PAINT §8)
	_check(r["inpass"] > 0 and r["overlay"] == 0, "%s: краска в проходе поверхности на всех красимых поверхностях" % id, [r["inpass"], r["overlay"], r["overlay_why"]])
	# неокрашенный узел
	_check(d.paint_handle(UNPAINTED_UID).is_empty(), "%s: у неокрашенного узла %s ручки нет" % [id, UNPAINTED_UID])
	var r2 := BodyPaint.mesh_root_of(d, UNPAINTED_UID)
	if r2 != null:
		var leaked := 0
		for mi in BodyPaint.meshes(r2):
			for s in (mi as MeshInstance3D).mesh.get_surface_count():
				if BodyPaint.paint_pass((mi as MeshInstance3D).get_active_material(s)) != null:
					leaked += 1
		_check(leaked == 0, "%s: неокрашенный узел %s — ни одного next_pass краски" % [id, UNPAINTED_UID], leaked)
	# коннекторы и Shirt
	var cons := 0
	var shirt_bad := []
	var pc: Color = Tuning.PLAYER_COLORS[clampi(player, 0, 3)]
	for b in d.parts.values():
		for c in (b as Node).get_children():
			if String(c.name).begins_with(BodyPaint.CONNECTOR_PREFIX):
				cons += 1
				for mi in _all_meshes(c):
					_check(((mi as MeshInstance3D).layers & BodyPaint.PAINT_LAYER_BIT) == 0, "%s: коннектор %s — без бита слоя кукол (шар и пояс не ловят декали)" % [id, c.name])
					for s in (mi as MeshInstance3D).mesh.get_surface_count():
						_check(BodyPaint.paint_pass((mi as MeshInstance3D).get_active_material(s)) == null, "%s: коннектор %s не красится" % [id, c.name])
	for mi in _all_meshes(d):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s)
			if mat is BaseMaterial3D and mat.resource_name.begins_with("Shirt"):
				var ac := (mat as BaseMaterial3D).albedo_color
				if not Color(ac.r, ac.g, ac.b).is_equal_approx(Color(pc.r, pc.g, pc.b)):
					shirt_bad.append("%s/%d" % [m.name, s])
	r["connectors"] = cons
	_check(shirt_bad.is_empty(), "%s: Shirt* в цвете игрока %d после покраски" % [id, player], shirt_bad)
	# наклейки — меш-декали
	for uid in stickers:
		var decs := d.stickers_of(uid)
		var st: Array = stickers[uid]
		_check(decs.size() == st.size(), "%s: у узла %s наклеек %d" % [id, uid, st.size()], decs.size())
		var body := BodyPaint.body_of(d, uid)
		var root := BodyPaint.mesh_root_of(d, uid)
		for i in mini(decs.size(), st.size()):
			var dec := decs[i] as MeshInstance3D
			if not _check(dec != null, "%s: наклейка %s#%d — MeshInstance3D (не Decal)" % [id, uid, i]):
				continue
			var want: Transform3D = root.global_transform * (st[i]["xf"] as Transform3D)
			r["decals"] += 1
			_check(dec.get_parent() == body, "%s: наклейка %s#%d — ребёнок тела узла" % [id, uid, i])
			var tris := dec.mesh.get_faces().size() / 3 if dec.mesh != null and dec.mesh.get_surface_count() > 0 else 0
			r["sticker_tris"] = int(r.get("sticker_tris", 0)) + tris
			_check(tris > 0, "%s: наклейка %s#%d — есть треугольники детали" % [id, uid, i], tris)
			var sm := dec.mesh.surface_get_material(0) as StandardMaterial3D if tris > 0 else null
			_check(sm != null and sm.albedo_texture == KitImages.texture(st[i]["img"]), "%s: наклейка %s#%d — картинка" % [id, uid, i])
			if sm != null:
				var sc: Color = st[i]["color"]
				_check(Color(sm.albedo_color.r, sm.albedo_color.g, sm.albedo_color.b).is_equal_approx(Color(sc.r, sc.g, sc.b)), "%s: наклейка %s#%d — цвет" % [id, uid, i], sm.albedo_color)
				_check(sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and sm.render_priority == BodyPaint.STICKER_PRIORITY and sm.vertex_color_use_as_albedo,
					"%s: наклейка %s#%d — прозрачная, поверх краски, спад по вершинам" % [id, uid, i])
			_check(dec.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: наклейка %s#%d — без тени" % [id, uid, i])
			_check(dec.global_transform.origin.distance_to(want.origin) < 1e-4 and _basis_close(dec.global_transform.basis, want.basis),
				"%s: наклейка %s#%d — кадр = корень меша × xf" % [id, uid, i], [dec.global_transform, want])
			_check(BodyPaint.sticker_dims(dec).is_equal_approx(st[i]["size"]), "%s: наклейка %s#%d — размер" % [id, uid, i], BodyPaint.sticker_dims(dec))
			_check(not dec.find_children("*", "Decal", true, false).size() and not body.find_children("*", "Decal", true, false).size(),
				"%s: наклейка %s#%d — ни одного Decal на теле" % [id, uid, i])
	# бит у всех мешей
	_check(_meshes_without_bit(d).is_empty(), "%s: бит слоя наклеек у всех MeshInstance3D" % id, _meshes_without_bit(d))
	# фото
	if head_uid != "":
		var root := BodyPaint.mesh_root_of(d, head_uid)
		var want := KitImages.texture(fixture_id)
		var faces := 0
		var ok := 0
		for mi in BodyPaint.meshes(root):
			for s in (mi as MeshInstance3D).mesh.get_surface_count():
				var mat := (mi as MeshInstance3D).get_active_material(s)
				if mat != null and mat.resource_name.begins_with("Face"):
					faces += 1
					if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture == want:
						ok += 1
		r["face_surfaces"] = faces
		_check(faces > 0 and ok == faces, "%s: FacePlate головы получил картинку" % id, [ok, faces])
	return r


## Массы, центры масс, физматериалы, формы, суставы тел — одинаковые у куклы с краской и без.
func _check_same_physics(id: String, a: ModularDoll, b: ModularDoll) -> void:
	_check(a.parts.size() == b.parts.size() and a.joints.size() == b.joints.size(), "%s: тел и суставов столько же с краской" % id, [a.parts.size(), b.parts.size(), a.joints.size(), b.joints.size()])
	var diff := []
	for nm in a.parts:
		var pa := a.parts[nm] as RigidBody3D
		var pb := b.parts.get(nm) as RigidBody3D
		if pb == null:
			diff.append("%s: нет" % nm)
			continue
		if not is_equal_approx(pa.mass, pb.mass) or pa.center_of_mass_mode != pb.center_of_mass_mode or not pa.center_of_mass.is_equal_approx(pb.center_of_mass):
			diff.append("%s: масса/ЦМ" % nm)
		var fa := pa.physics_material_override
		var fb := pb.physics_material_override
		if (fa == null) != (fb == null) or (fa != null and (not is_equal_approx(fa.friction, fb.friction) or not is_equal_approx(fa.bounce, fb.bounce))):
			diff.append("%s: физматериал" % nm)
		if _shape_sig(pa) != _shape_sig(pb):
			diff.append("%s: формы" % nm)
		if pa.collision_layer != pb.collision_layer or pa.collision_mask != pb.collision_mask:
			diff.append("%s: слои коллизий" % nm)
		if not pa.transform.is_equal_approx(pb.transform):
			diff.append("%s: кадр тела в кукле" % nm)
	_check(diff.is_empty(), "%s: массы, центры масс, физматериалы, формы — как без краски" % id, diff)
	_check(is_equal_approx(a.total_mass, b.total_mass), "%s: total_mass как без краски" % id, [a.total_mass, b.total_mass])


## Общие ресурсы материалов (Base_*, glb) краской не тронуты: next_pass у них нет.
func _check_shared_untouched(id: String) -> void:
	var bad := []
	for path in ["res://assets/materials/kit/Base_Wood.tres", "res://assets/materials/kit/Iron.tres", "res://assets/materials/kit/Shirt_Kit.tres"]:
		var m := load(path) as Material
		if m != null and m.next_pass != null:
			bad.append(path)
	_check(bad.is_empty(), "%s: общие материалы без next_pass (краска — только в дублях)" % id, bad)


## Живая кукла: ensure_paint создаёт пустой слой и next_pass, второй вызов — та же ручка; штрих + update_texture; add_sticker.
func _check_live(d: ModularDoll) -> void:
	var r := {}
	_check(d.paint_handle("1").is_empty(), "живая: до ensure_paint ручки нет")
	var h := d.ensure_paint("1")
	_check(not h.is_empty() and (h["layer"] as PaintLayer).is_empty(), "ensure_paint(1): пустой слой")
	_check(d.ensure_paint("1")["layer"] == h["layer"] and d.paint_handle("1")["layer"] == h["layer"], "ensure_paint повторно / paint_handle — та же ручка")
	var root := BodyPaint.mesh_root_of(d, "1")
	var box := BodyPaint.mesh_aabb(root)
	var layer: PaintLayer = h["layer"]
	_check(layer.aabb.grow(1e-5).encloses(box), "ensure_paint: слой покрывает меш детали", [layer.aabb, box])
	var painted := 0
	for mi in BodyPaint.meshes(root):
		for s in (mi as MeshInstance3D).mesh.get_surface_count():
			if BodyPaint.paint_pass((mi as MeshInstance3D).get_active_material(s)) != null:
				painted += 1
	_check(painted > 0, "ensure_paint: next_pass краски на поверхностях", painted)
	var rng := RandomNumberGenerator.new()
	layer.spray(box.get_center(), 0.05, Color(1, 0, 0), 1.0, 0.5, rng)
	layer.update_texture(h["tex"])
	_check(not layer.is_empty() and layer.dirty_range().y < layer.dirty_range().x, "штрих в живой слой + update_texture")
	_check(d.ensure_paint("Z").is_empty() and d.paint_handle("Z").is_empty(), "ensure_paint / paint_handle чужого uid → {}")
	if fixture_id != "":
		var dec := d.add_sticker("1", {"img": fixture_id, "xf": _front_xf(box, Vector2.ZERO), "size": Vector2(0.05, 0.05)})
		_check(dec != null and d.stickers_of("1").has(dec) and dec is MeshInstance3D, "add_sticker на живой кукле — меш-наклейка")
		_check(d.add_sticker("1", {"img": "ffffffffffffffff", "xf": Transform3D.IDENTITY}) == null, "add_sticker без картинки → null")
		dec.queue_free()
		r["sticker"] = true
	report["live"] = r


## «Респавн» как Match.respawn_doll: новый инстанс сцены ModularDoll, чертёж в памяти ставится до add_child.
func _check_respawn(old: ModularDoll, expected: Dictionary, stickers: Dictionary, head_uid: String) -> void:
	var d := (load(MODULAR_SCENE) as PackedScene).instantiate() as ModularDoll
	d.set("blueprint", old.get("blueprint"))
	d.external_input = true
	d.position = old.position + Vector3(0, 0, -4)
	add_child(d)
	var same := 0
	for uid in expected:
		var h := d.paint_handle(uid)
		if not h.is_empty() and (h["layer"] as PaintLayer).data == expected[uid]:
			same += 1
	_check(same == expected.size(), "респавн: краска всех узлов та же", [same, expected.size()])
	var n_st := 0
	var n_want := 0
	for uid in stickers:
		n_st += d.stickers_of(uid).size()
		n_want += (stickers[uid] as Array).size()
	_check(n_st == n_want, "респавн: наклейки те же", [n_st, n_want])
	var face_ok := false
	for mi in BodyPaint.meshes(BodyPaint.mesh_root_of(d, head_uid)):
		for s in (mi as MeshInstance3D).mesh.get_surface_count():
			var mat := (mi as MeshInstance3D).get_active_material(s)
			if mat is BaseMaterial3D and mat.resource_name.begins_with("Face") and (mat as BaseMaterial3D).albedo_texture == KitImages.texture(fixture_id):
				face_ok = true
	_check(face_ok, "респавн: фото на голове")
	report["respawn"] = {"paint_nodes": same, "stickers": n_st, "face": face_ok}
	d.queue_free()


## Битые ключи — кукла собирается без них, validate() молчит.
func _check_garbage(pos: Vector3) -> void:
	var bp := _dup_bp(load(KIT_HUMAN_BP))
	var junk := PaintLayer.for_aabb(AABB(Vector3.ZERO, Vector3.ONE * 0.1)).to_dict()
	junk["size"] = 999
	bp.find_node("1")["paint"] = junk
	bp.find_node("5")["paint"] = 42
	bp.find_node("3")["stickers"] = [{"img": "deadbeefdeadbeef", "xf": Transform3D.IDENTITY, "size": Vector2(0.05, 0.05)}, {"img": 5}, "x"]
	bp.find_node("4")["stickers"] = "не массив"
	bp.find_node("H")["face"] = "0000000000000000"
	bp.find_node("T")["face"] = 17
	_check(bp.validate().is_empty(), "битые paint / stickers / face: validate() без ошибок (мягкая валидация)", bp.validate())
	var d := _spawn(bp, pos, 0)
	_check(d.build_errors.is_empty() and d.parts.size() == 14, "битые paint / stickers / face: кукла собирается целиком", [d.build_errors, d.parts.size()])
	var hs := 0
	var ds := 0
	for uid in ["1", "3", "4", "5", "H", "T"]:
		if not d.paint_handle(uid).is_empty():
			hs += 1
		ds += d.stickers_of(uid).size()
	_check(hs == 0 and ds == 0, "битые данные: ни ручек, ни наклеек", [hs, ds])
	_check(_meshes_without_bit(d).is_empty(), "битые данные: бит слоя у всех мешей")
	report["garbage"] = {"handles": hs, "decals": ds}
	d.queue_free()


## Наклейка через пояс kit_human (Shirt_Kit — цвет игрока): треугольники пояса в коробке пропущены, ни один треугольник меша наклейки
## не лежит на Shirt* (центр треугольника → луч назад по −Y наклейки → поверхность меша детали); размер из чертежа больше 40 см —
## зажат (STICKER_SIZE_RANGE).
func _check_sticker_guard(pos: Vector3) -> void:
	var r := {}
	var d := _spawn(_dup_bp(load(KIT_HUMAN_BP)), pos, 1)
	var root := BodyPaint.mesh_root_of(d, "T")
	var body := BodyPaint.body_of(d, "T")
	var box := BodyPaint.mesh_aabb(root)
	# точка пояса: луч спереди (−Z корня меша) сверху вниз по оси детали, первое попадание в поверхность Shirt*
	var gx := root.global_transform
	var fwd := (gx.basis * Vector3.FORWARD).normalized()
	var belt_y := INF
	var steps := 60
	for k in steps:
		var y := box.position.y + box.size.y * (float(k) + 0.5) / steps
		var h := _ray_root(root, gx * Vector3(box.get_center().x, y, box.end.z + 0.1), fwd)
		if not h.is_empty() and BodyPaint.is_player_colour(h["mat"]):
			belt_y = y
			break
	if not _check(belt_y != INF, "kit_human: у торса есть пояс Shirt* спереди"):
		d.queue_free()
		return
	var hb := _ray_root(root, gx * Vector3(box.get_center().x, belt_y, box.end.z + 0.1), fwd)
	var p: Vector3 = gx.affine_inverse() * (hb["point"] as Vector3)
	var st := {"img": "stencil:star", "xf": Transform3D(Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN), p), "size": Vector2(0.2, 0.2), "color": Color(1, 0.8, 0.1)}
	var n := BodyPaint.add_sticker(body, root, st)
	var tris := n.mesh.get_faces().size() / 3 if n.mesh.get_surface_count() > 0 else 0
	var guarded := int(n.get_meta("sticker_guarded", 0))
	var on_shirt := 0
	var checked := 0
	if tris > 0:
		var fs := n.mesh.get_faces()
		var xf := n.global_transform
		var down := -xf.basis.y.normalized()
		for i in range(0, fs.size(), 3):
			# центр треугольника наклейки — на STICKER_LIFT над своей поверхностью: первая поверхность под ним (≤ 2 мм) — его
			# исходная; пояс, приподнятый над стенкой, лежит ВЫШЕ наклейки и её закрывает (её не видно) — это не «наклейка на поясе»;
			# пояс МЕЖДУ наклейкой и её стенкой — наклейка поверх пояса (плохо)
			var c := xf * ((fs[i] + fs[i + 1] + fs[i + 2]) / 3.0)
			var from := c - down * 0.00002
			var h2 := _ray_root(root, from, down, true)
			if h2.is_empty() or ((h2["point"] as Vector3) - from).dot(down) > 0.002:
				continue
			checked += 1
			if BodyPaint.is_player_colour(h2["mat"]):
				on_shirt += 1
	r = {"tris": tris, "guarded": guarded, "checked": checked, "on_shirt": on_shirt}
	_check(tris > 0 and guarded > 0, "наклейка 20 см через пояс: треугольники детали есть, треугольники пояса в коробке пропущены", r)
	_check(checked >= tris * 0.8 and on_shirt == 0, "наклейка через пояс: ни одного треугольника на Shirt* (цвет игрока не закрыт)", r)
	var big := BodyPaint.add_sticker(body, root, {"img": "stencil:star", "xf": st["xf"], "size": Vector2(1.0, 0.5)})
	_check(big != null and BodyPaint.sticker_dims(big).is_equal_approx(Vector2(0.4, 0.4)), "размер наклейки из чертежа — не больше 40 см", BodyPaint.sticker_dims(big) if big != null else null)
	report["sticker_guard"] = r
	d.queue_free()


## Ближайшее попадание луча (кадр мира) по мешам корня: {point, mat}; any — первое по лучу без учёта стороны.
func _ray_root(root: Node3D, from: Vector3, dir: Vector3, _any := false) -> Dictionary:
	var best := {}
	var bd := INF
	for mi in BodyPaint.meshes(root):
		var m := mi as MeshInstance3D
		var xf := m.global_transform
		var inv := xf.affine_inverse()
		var tm := m.mesh.generate_triangle_mesh()
		var hit := tm.intersect_ray(inv * from, inv.basis * dir)
		if hit.is_empty():
			continue
		var pw: Vector3 = xf * (hit["position"] as Vector3)
		var dd := (pw - from).dot(dir)
		if dd > 0.0 and dd < bd:
			bd = dd
			best = {"point": pw, "mat": BodyPaint.surface_material(m, WorkshopPaint._surface_of_face(m.mesh, int(hit.get("face_index", -1))))}
	return best


# --- физика ---

func _phys_verdict() -> void:
	var r := {}
	for pair in [["kit_plain", "kit_paint"], ["human_plain", "human_paint"]]:
		var a: Dictionary = phys_disp.get(pair[0], {})
		var b: Dictionary = phys_disp.get(pair[1], {})
		if not _check(not a.is_empty() and a.size() == b.size(), "физика %s / %s: прогоны прошли, частей поровну" % pair, [a.size(), b.size()]):
			continue
		var worst := 0.0
		var moved := 0.0
		for k in a:
			if not b.has(k):
				worst = INF
				continue
			worst = maxf(worst, ((a[k] as Vector3) - (b[k] as Vector3)).length())
			moved = maxf(moved, (a[k] as Vector3).length())
		r[pair[1]] = {"max_disp_diff_m": worst, "max_disp_m": snappedf(moved, 0.001)}
		_check(moved > 0.05, "физика %s: толчок сдвинул куклу" % pair[0], moved)
		_check(worst <= PHYS_TOL, "физика: смещение частей через %d кадров с краской = без (%s)" % [PHYS_FRAMES, pair[1]], worst)
	report["physics"] = r


# --- хелперы ---

func _spawn(bp: BodyBlueprint, pos: Vector3, player: int) -> ModularDoll:
	var d := (load(MODULAR_SCENE) as PackedScene).instantiate() as ModularDoll
	d.blueprint = bp
	d.external_input = true
	d.player_index = player
	d.position = pos
	add_child(d)
	return d


## Копия чертежа в памяти (как CraftEdit.dup_body: resource_path "" — Match.respawn_doll переносит её в новый инстанс).
func _dup_bp(src: BodyBlueprint) -> BodyBlueprint:
	var bp := BodyBlueprint.new()
	bp.id = src.id
	bp.title = src.title
	bp.energy_budget = src.energy_budget
	var nodes: Array[Dictionary] = []
	for n in src.nodes:
		nodes.append(n.duplicate(true))
	bp.nodes = nodes
	bp.control = src.control.duplicate()
	bp.weapon = src.weapon
	bp.weapon_on = src.weapon_on
	return bp


## Кадр наклейки на поверхности детали спереди (луч по −Z корня меша в точку at габарита), иначе — на лицевой грани габарита.
func _surface_xf(root: Node3D, box: AABB, at: Vector2) -> Transform3D:
	var xf := _front_xf(box, at)
	var gx := root.global_transform
	var h := _ray_root(root, gx * (xf.origin + Vector3(0, 0, 0.1)), (gx.basis * Vector3.FORWARD).normalized())
	if not h.is_empty():
		xf.origin = gx.affine_inverse() * (h["point"] as Vector3)
	return xf


## Кадр наклейки на лицевой (+Z) грани габарита: −Y декали — в поверхность (−Z), at — доли габарита по X / Y от центра.
func _front_xf(box: AABB, at: Vector2) -> Transform3D:
	var c := box.get_center()
	var p := Vector3(c.x + at.x * box.size.x, c.y + at.y * box.size.y, box.end.z)
	return Transform3D(Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN), p)


func _part_positions(d: ModularDoll) -> Dictionary:
	var out := {}
	for nm in d.parts:
		out[String(nm)] = (d.parts[nm] as Node3D).global_position
	return out


func _changed(l: PaintLayer, before: PackedByteArray, p: Vector3) -> Dictionary:
	var n := 0
	var max_d := 0.0
	var max_a := 0
	var i := 0
	for z in l.res.z:
		for y in l.res.y:
			for x in l.res.x:
				if l.data[i + 3] != before[i + 3]:
					n += 1
					max_d = maxf(max_d, l.cell_center(x, y, z).distance_to(p))
				max_a = maxi(max_a, l.data[i + 3])
				i += 4
	return {"n": n, "max_d": snappedf(max_d, 0.0001), "max_a": max_a}


func _has_alpha_below(l: PaintLayer, a: int) -> bool:
	for i in range(3, l.data.size(), 4):
		if l.data[i] < a:
			return true
	return false


## Меши куклы без бита слоя кукол — кроме коннекторов шарниров (у них бита нет нарочно: шар и пояс — цвет игрока).
func _meshes_without_bit(d: Node) -> Array:
	var out := []
	for mi in _all_meshes(d, true):
		if ((mi as MeshInstance3D).layers & BodyPaint.PAINT_LAYER_BIT) == 0:
			out.append(String((mi as Node).get_path()).get_file())
	return out


## Слой краски с res / aabb и правильным zstd-содержимым (для битых размеров from_dict).
static func _bad_layer(r: Vector3i, box: AABB) -> Dictionary:
	var raw := PackedByteArray()
	raw.resize(r.x * r.y * r.z * 4)
	raw.fill(0)
	return {"v": PaintLayer.VERSION, "res": r, "aabb": box, "data": raw.compress(FileAccess.COMPRESSION_ZSTD), "size": raw.size()}


func _all_meshes(n: Node, skip_connectors := false) -> Array:
	var out: Array = []
	if skip_connectors and String(n.name).begins_with(BodyPaint.CONNECTOR_PREFIX):
		return out
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out += _all_meshes(c, skip_connectors)
	return out


func _shape_sig(b: RigidBody3D) -> Array:
	var out := []
	for c in b.get_children():
		if c is CollisionShape3D:
			out.append([String(c.name), (c as CollisionShape3D).transform, (c as CollisionShape3D).shape])
	return out


static func _with(d: Dictionary, k: String, v: Variant) -> Dictionary:
	var o := d.duplicate()
	o[k] = v
	return o


static func _col_close(a: Color, b: Color, tol: float) -> bool:
	return absf(a.r - b.r) <= tol and absf(a.g - b.g) <= tol and absf(a.b - b.b) <= tol and absf(a.a - b.a) <= tol


static func _basis_close(a: Basis, b: Basis) -> bool:
	return a.x.distance_to(b.x) < 1e-4 and a.y.distance_to(b.y) < 1e-4 and a.z.distance_to(b.z) < 1e-4


func _check(ok: bool, what: String, detail: Variant = null) -> bool:
	checks += 1
	if not ok:
		var msg := what if detail == null else "%s — %s" % [what, str(detail)]
		failures.append(msg)
		push_warning("FAIL: " + msg)
	return ok


func _floor() -> void:
	var f := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(200, 0.2, 20)
	cs.shape = bs
	f.add_child(cs)
	f.position = Vector3(-40, -0.1, 0)
	add_child(f)


func _finish() -> void:
	report["checks"] = checks
	report["failed"] = failures.size()
	report["ok"] = failures.is_empty()
	report["failures"] = Array(failures)
	report["notes"] = Array(notes)
	var f := FileAccess.open(report_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  ", false))
		f.close()
	print("=== PAINT PROBE ===")
	print("  perf: ", report["perf"])
	print("  patterns: ", report["layer"].get("patterns", {}))
	print("  zstd: ", report["layer"].get("zstd_bytes", {}))
	for id in report["dolls"]:
		print("  doll %s: %s" % [id, report["dolls"][id]])
	print("  physics: ", report["physics"])
	print("  stencils: ", report["images"].get("stencils", []))
	for n in notes:
		print("  NOTE ", n)
	for fl in failures:
		print("  FAIL ", fl)
	if failures.is_empty():
		print("PAINT PROBE OK (%d checks)" % checks)
	else:
		print("PAINT PROBE FAIL (%d of %d checks failed)" % [failures.size(), checks])
	get_tree().quit(0 if failures.is_empty() else 1)


class BlueprintHelper:
	static func part(n: Dictionary) -> PartDef:
		return BodyBlueprint.part_def(String(n.get("part", "")))
