## Проба «Эскиз → боец» (docs/plan-demo/SKETCH_FIGHTER.md). Без окна:
##   godot --headless --path godot --fixed-fps 60 res://tests/sketch_probe.tscn [-- only=data|ui|spawn,spawn_s=5]
## Разделы:
##   data  — SketchBuild на синтетических штрихах (холст 760×640): человечек (круг-тело, круг-голова, 2 руки, 2 ноги), многорукий
##           (круг и 6 линий по бокам), молот (зигзаг у конца руки — отдельным штрихом и хвостом того же штриха → навершие, ЛКМ на
##           его теле-хозяине), кистень (волна от конца руки → цепь + булава), маленький круг против большого (масса меньше),
##           пустой рисунок и каракуля (всё равно боец), симметрия (одна рука справа + S → две руки); каждый случай — валиден с
##           «запасом из деталей» и без (friendly / structural пусты, энергия ≤ потолка, есть ЛКМ); тот же seed — тот же чертёж;
##   ui    — экран ВЫБОР БОЙЦА (dry_run): карточка «Нарисуй», D → холст; штрихи синтетической мышью (InputEventMouse); после паузы
##           превью собрано; Backspace / ПКМ — отмена штриха, C — очистить, S — симметрия; Enter → chosen(чертёж эскиза);
##           снова открыть экран — карточка «Прошлый эскиз»; Esc — к карточкам;
##   spawn — бойцы из data и с экрана уходят в бой путём игрока (ModeRun.launch(opts.player_blueprint)) на Void против бота 1 уровня:
##           P1 — ModularDoll с тем же чертежом, жив через spawn_s секунд.
## → строки «  id  ok/FAIL  деталь», JSON, === OK / FAIL ===, exit 0/1.
extends Node

const TICK := 1.0 / 60.0
const C := Vector2(380, 330)


class ScriptErrors extends Logger:
	var count := 0
	var first := ""
	var _mx := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_mx.lock()
		if error_type == ERROR_TYPE_SCRIPT:
			count += 1
			if first == "":
				first = "%s %s (%s:%d %s)" % [code, rationale, file, line, function]
		_mx.unlock()


var ok := true
var checks: Array = []
var info := {}
var errs := ScriptErrors.new()
var pg: Node
var _fighters: Array = []   # [{tag, bp}] — уходят в spawn


func _check(id: String, cond: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": cond, "detail": str(detail)})
	if not cond:
		ok = false
	print("  %-34s %s  %s" % [id, "ok  " if cond else "FAIL", str(detail)])


func _args() -> Dictionary:
	var out := {"only": "", "out": "", "spawn_s": "5"}
	for a in OS.get_cmdline_user_args():
		for part in String(a).split(","):
			var kv := part.split("=")
			if kv.size() == 2 and out.has(kv[0]):
				out[kv[0]] = kv[1]
	return out


func _want(a: Dictionary, s: String) -> bool:
	return String(a["only"]) == "" or s in String(a["only"]).split("|")


func _ready() -> void:
	OS.add_logger(errs)
	print("=== SKETCH PROBE ===")
	var a := _args()
	var recent: Array = ModeRun._recent.duplicate()
	var hp0 := PartHp.on
	FighterPick.last = {}
	FighterPick.sketch = {}
	if _want(a, "data"):
		_data()
	PartHp.on = hp0
	if _want(a, "ui"):
		await _ui()
	if _want(a, "spawn"):
		await _spawn(float(a["spawn_s"]))
	await _unload()
	ModeRun._recent = recent
	ModeRun._save_cfg()
	FighterPick.last = {}
	FighterPick.sketch = {}
	PartHp.on = hp0
	_check("errors_script", errs.count == 0, "ошибок скриптов %d; первая: %s" % [errs.count, errs.first])
	var report := {"ok": ok, "checks": checks, "info": info}
	print(JSON.stringify(report, " "))
	if String(a["out"]) != "":
		var f := FileAccess.open(String(a["out"]), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(report, " "))
			f.close()
	print("=== OK ===" if ok else "=== FAIL ===")
	OS.remove_logger(errs)
	get_tree().quit(0 if ok else 1)


static func _valid(bp: BodyBlueprint) -> String:
	if bp == null:
		return "null"
	if bp.nodes.is_empty():
		return "пусто"
	var fe: Array = CraftEdit.friendly_errors(bp)
	if not fe.is_empty():
		return String(fe[0])
	var se: Array = CraftEdit.structural_errors(bp)
	if not se.is_empty():
		return str(se[0])
	if bp.energy_used() > bp.energy_cap():
		return "энергия %d > %d" % [bp.energy_used(), bp.energy_cap()]
	if bp.control.is_empty():
		return "нет ЛКМ"
	return ""


static func _sig(bp: BodyBlueprint) -> String:
	return "|".join(CraftEdit.signature(bp)) if bp != null else ""


# ------------------------------------------------------------------ синтетические штрихи

static func circle(c: Vector2, r: float, n: int = 40, ry: float = -1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in n + 1:
		var t := TAU * float(k) / float(n) - PI * 0.5
		out.append(c + Vector2(cos(t) * r, sin(t) * (r if ry < 0.0 else ry)))
	return out


static func line(a: Vector2, b: Vector2, n: int = 14) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in n + 1:
		out.append(a.lerp(b, float(k) / float(n)))
	return out


## Зигзаг от a по направлению dir: teeth зубцов амплитудой amp на длине len.
static func zigzag(a: Vector2, dir: Vector2, len_: float, teeth: int, amp: float) -> PackedVector2Array:
	var out := PackedVector2Array([a])
	var d := dir.normalized()
	var nrm := Vector2(-d.y, d.x)
	for k in range(1, teeth * 2 + 1):
		var t := float(k) / float(teeth * 2)
		out.append(a + d * len_ * t + nrm * amp * (1.0 if k % 2 == 1 else -1.0))
	return out


static func wave(a: Vector2, b: Vector2, periods: float, amp: float, n: int = 60) -> PackedVector2Array:
	var out := PackedVector2Array()
	var d := (b - a)
	var nrm := Vector2(-d.y, d.x).normalized()
	for k in n + 1:
		var t := float(k) / float(n)
		out.append(a + d * t + nrm * sin(t * periods * TAU) * amp)
	return out


static func _on_core(c: Vector2, r: float, deg: float) -> Vector2:
	return c + Vector2(cos(deg_to_rad(deg)), -sin(deg_to_rad(deg))) * r


## Человечек с ядром радиуса r: тело, голова, руки и ноги (обе стороны нарисованы).
static func human(r: float = 85.0) -> Array:
	var k := r / 85.0
	var s: Array = [circle(C, r), circle(C + Vector2(0, -r - 38.0 * k), 34.0 * k)]
	for sx in [1.0, -1.0]:
		var a0 := _on_core(C, r, 28.0)
		a0.x = C.x + (a0.x - C.x) * sx
		s.append(line(a0, a0 + Vector2(145.0 * k * sx, -70.0 * k)))
	for sx in [1.0, -1.0]:
		var l0 := _on_core(C, r, -62.0)
		l0.x = C.x + (l0.x - C.x) * sx
		s.append(line(l0, l0 + Vector2(20.0 * k * sx, 175.0 * k)))
	return s


static func arm_end(sk: Array) -> Vector2:
	var arm: PackedVector2Array = sk[2]
	return arm[arm.size() - 1]


static func multi_arm() -> Array:
	var s: Array = [circle(C, 85.0), circle(C + Vector2(0, -123), 34.0)]
	for sx in [1.0, -1.0]:
		for deg in [40.0, 5.0, -25.0]:
			var p := _on_core(C, 85.0, deg)
			p.x = C.x + (p.x - C.x) * sx
			s.append(line(p, p + Vector2(110.0 * sx, -20.0)))
	return s


static func scribble(seed_v: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var out: Array = []
	for i in 4:
		var p := Vector2(rng.randf_range(100, 660), rng.randf_range(100, 540))
		var s := PackedVector2Array([p])
		for k in 50:
			p += Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
			p = p.clamp(Vector2(5, 5), Vector2(755, 635))
			s.append(p)
		out.append(s)
	return out


# ------------------------------------------------------------------ data

static func _parts(bp: BodyBlueprint) -> Array:
	var out: Array = []
	for n in bp.nodes:
		out.append(String(n.get("part", "")))
	return out


static func _kind_count(bp: BodyBlueprint, kind: String) -> int:
	var c := 0
	for n in bp.nodes:
		var d := CraftEdit.part(String(n.get("part", "")))
		if d != null and d.kind == kind:
			c += 1
	return c


static func _core_limbs(bp: BodyBlueprint) -> PackedStringArray:
	var core := CraftEdit.root_uid(bp)
	var out: PackedStringArray = []
	for n in bp.nodes:
		if String(n.get("parent", "")) == core and String(n.get("anchor", "")) != "Anchor_Neck":
			var d := CraftEdit.part(String(n.get("part", "")))
			if d != null and d.kind in ["limb", ""]:
				out.append(String(n.get("anchor", "")))
	return out


func _gen(tag: String, strokes: Array, seed_v: int = 0) -> Dictionary:
	var r := SketchBuild.generate(strokes, seed_v)
	var bp: BodyBlueprint = r.get("bp")
	var inf: Dictionary = r.get("info", {})
	info[tag] = {"line": String(inf.get("line", "")), "level": r.get("level", -1), "tries": r.get("tries", -1),
		"mass": snappedf(bp.total_mass(), 0.1) if bp != null else 0.0, "energy": "%d/%d" % [bp.energy_used(), bp.energy_cap()] if bp != null else "",
		"parts": bp.nodes.size() if bp != null else 0, "roles": inf.get("roles", PackedStringArray())}
	return r


func _data() -> void:
	var cases := {
		"human": human(),
		"multi": multi_arm(),
		"small": human(52.0),
		"large": human(128.0),
		"empty": [],
		"scribble": scribble(5),
		"scribble2": scribble(11),
	}
	var hm := human()
	hm.append(zigzag(arm_end(hm), Vector2(1, -0.5), 70.0, 4, 18.0))
	cases["hammer"] = hm
	# молот одним штрихом: зигзаг — хвост самой руки
	var hm2 := human()
	var arm: PackedVector2Array = hm2[2]
	var zz := zigzag(arm[arm.size() - 1], Vector2(1, -0.5), 60.0, 4, 16.0)
	arm.append_array(zz.slice(1))
	hm2[2] = arm
	cases["hammer_tail"] = hm2
	var fl := human()
	fl.append(wave(arm_end(fl), arm_end(fl) + Vector2(120, 110), 2.5, 16.0))
	cases["flail"] = fl
	# симметрия: тело, голова и одна рука справа
	var half: Array = [circle(C, 85.0), circle(C + Vector2(0, -123), 34.0), line(_on_core(C, 85.0, 28.0), _on_core(C, 85.0, 28.0) + Vector2(145, -70))]
	cases["sym_off"] = half
	cases["sym_on"] = SketchBuild.with_mirror(half, C.x)["strokes"]
	# валидность с запасом из деталей и без
	var bad: Array = []
	for hp in [false, true]:
		PartHp.on = hp
		for tag in cases:
			for sd in [0, 1, 2]:
				var r := SketchBuild.generate(cases[tag], sd)
				var why := _valid(r.get("bp"))
				if why != "":
					bad.append("%s hp=%s seed=%d: %s" % [tag, hp, sd, why])
	_check("data_all_valid", bad.is_empty(), bad if not bad.is_empty() else "%d рисунков × 3 seed × (с запасом и без): все валидны" % cases.size())
	PartHp.on = false
	var R := {}
	for tag in cases:
		R[tag] = _gen(tag, cases[tag])
		print("    %-12s %s  · масса %.1f · энергия %s · уровень %s" % [tag, info[tag]["line"], info[tag]["mass"], info[tag]["energy"], info[tag]["level"]])
	# человечек
	var hb: BodyBlueprint = R["human"]["bp"]
	var hi: Dictionary = R["human"]["info"]
	var anchors := _core_limbs(hb)
	_check("human_parts", int(hi["arms"]) == 2 and int(hi["legs"]) == 2 and bool(hi["head_drawn"]) and _kind_count(hb, "foot") == 2
		and _kind_count(hb, "hand") == 2 and anchors.has("Anchor_Shoulder_L") and anchors.has("Anchor_Hip_R"),
		"рук %d, ног %d, голова %s, стоп %d, кистей %d, якоря %s" % [hi["arms"], hi["legs"], hi["head_drawn"], _kind_count(hb, "foot"),
		_kind_count(hb, "hand"), anchors])
	var roles: PackedStringArray = hi["roles"]
	_check("human_roles", roles == PackedStringArray(["core", "head", "limb", "limb", "limb", "limb"]), roles)
	# многорукий
	var mi: Dictionary = R["multi"]["info"]
	var mb: BodyBlueprint = R["multi"]["bp"]
	_check("multi_arms", int(mi["arms"]) >= 5 and _core_limbs(mb).size() >= 5, "рук %d, конечностей на ядре %d (%s)" % [mi["arms"], _core_limbs(mb).size(), _core_limbs(mb)])
	# молот
	for tag in ["hammer", "hammer_tail"]:
		var b: BodyBlueprint = R[tag]["bp"]
		var strike := String(R[tag]["strike"])
		var sd := CraftEdit.part(String(CraftEdit.find(b, strike).get("part", "")))
		var host := CraftEdit.host_uid(b, strike)
		_check("%s_weapon_control" % tag, sd != null and sd.kind == "weapon_head" and "weapon" in (R[tag]["info"]["tips"] as PackedStringArray)
			and b.control.size() > 0 and b.control[0] == host,
			"ударная %s (%s), ЛКМ %s, хозяин %s" % [strike, sd.id if sd != null else "?", b.control, host])
	# кистень
	var fb: BodyBlueprint = R["flail"]["bp"]
	_check("flail_chain", _parts(fb).has("chain_segment") and _kind_count(fb, "weapon_head") >= 1 and "flail" in (R["flail"]["info"]["tips"] as PackedStringArray),
		"детали: цепь %s, наверший %d, %s" % [_parts(fb).has("chain_segment"), _kind_count(fb, "weapon_head"), R["flail"]["info"]["line"]])
	# маленький против большого
	var ms: float = (R["small"]["bp"] as BodyBlueprint).total_mass()
	var mh: float = (R["human"]["bp"] as BodyBlueprint).total_mass()
	var ml: float = (R["large"]["bp"] as BodyBlueprint).total_mass()
	_check("mass_small_lt_large", ms < ml and ms <= mh and mh <= ml, "масса: маленький %.1f, средний %.1f, большой %.1f (стили %s / %s / %s)" % [ms, mh, ml,
		R["small"]["style"], R["human"]["style"], R["large"]["style"]])
	# пустой и каракуля
	_check("empty_is_fighter", _valid(R["empty"]["bp"]) == "" and int(R["empty"]["info"]["arms"]) == 2 and int(R["empty"]["info"]["legs"]) == 2,
		R["empty"]["info"]["line"])
	_check("scribble_is_fighter", _valid(R["scribble"]["bp"]) == "" and _valid(R["scribble2"]["bp"]) == "",
		"%s | %s" % [R["scribble"]["info"]["line"], R["scribble2"]["info"]["line"]])
	# симметрия
	var so: Dictionary = R["sym_off"]["info"]
	var sn: Dictionary = R["sym_on"]["info"]
	var sa := _core_limbs(R["sym_on"]["bp"])
	_check("symmetry_two_arms", int(so["arms"]) == 1 and int(sn["arms"]) == 2 and sa.has("Anchor_Shoulder_L") and sa.has("Anchor_Shoulder_R")
		and (SketchBuild.with_mirror(cases["human"], C.x)["strokes"] as Array).size() == (cases["human"] as Array).size(),
		"без S рук %d, с S — %d (%s); у человечка с двумя руками копий нет" % [so["arms"], sn["arms"], sa])
	# детерминизм и варианты
	var same := true
	var differ := false
	for tag in cases:
		var a := _sig(SketchBuild.generate(cases[tag], 3)["bp"])
		if a != _sig(SketchBuild.generate(cases[tag], 3)["bp"]):
			same = false
	var h0 := _sig(hb)
	for sd in range(1, 6):
		if _sig(SketchBuild.generate(cases["human"], sd)["bp"]) != h0:
			differ = true
	_check("deterministic_by_seed", same and differ, "тот же seed → тот же чертёж: %s; другой seed → другой вариант: %s" % [same, differ])
	for tag in ["human", "multi", "hammer", "flail", "small", "large", "empty", "scribble"]:
		_fighters.append({"tag": tag, "bp": R[tag]["bp"]})


# ------------------------------------------------------------------ ui

func _key(code: int) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.pressed = pressed
		e.physical_keycode = code
		e.keycode = code
		get_viewport().push_input(e)
	await get_tree().process_frame
	await get_tree().process_frame


func _mouse_stroke(pad: Control, pts: PackedVector2Array, button: int = MOUSE_BUTTON_LEFT) -> void:
	var xf := pad.get_global_transform_with_canvas()
	var b := InputEventMouseButton.new()
	b.button_index = button
	b.pressed = true
	b.position = xf * pts[0]
	b.global_position = b.position
	get_viewport().push_input(b, true)
	for k in range(1, pts.size()):
		var m := InputEventMouseMotion.new()
		m.position = xf * pts[k]
		m.global_position = m.position
		m.relative = pts[k] - pts[k - 1]
		m.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
		get_viewport().push_input(m, true)
	var u := InputEventMouseButton.new()
	u.button_index = button
	u.pressed = false
	u.position = xf * pts[pts.size() - 1]
	u.global_position = u.position
	get_viewport().push_input(u, true)
	await get_tree().process_frame


func _settle() -> void:
	for i in 40:
		await get_tree().process_frame


func _open() -> FighterSelect:
	var fs := FighterSelect.open_over(self, {"title": "PROBE", "include_saved": false, "dry_run": true})
	await get_tree().process_frame
	await get_tree().process_frame
	return fs


static func _scale_to_pad(pad: Control, s: PackedVector2Array) -> PackedVector2Array:
	var k := pad.size / SketchBuild.CANVAS
	var out := PackedVector2Array()
	for p in s:
		out.append(p * k)
	return out


func _ui() -> void:
	var got: Array = []
	var fs := await _open()
	fs.chosen.connect(func(bp: BodyBlueprint) -> void: got.append(bp))
	var si := fs.index_of("sketch")
	var qi := fs.index_of("builder")
	_check("ui_sketch_card", si >= 0 and qi >= 0 and absi(si - qi) == 1, "карточка «Нарисуй» %d рядом с быстрой сборкой %d" % [si, qi])
	await _key(KEY_D)
	var pad := fs.get("_pad") as Control
	_check("ui_d_opens_canvas", fs.sketch_open and pad != null and pad.is_visible_in_tree() and not fs.builder_open, "холст %s, видим %s" % [fs.sketch_open,
		pad != null and pad.is_visible_in_tree()])
	if pad == null:
		fs.close()
		return
	# тело, голова и правая рука; симметрия по умолчанию включена → две руки
	var body := _scale_to_pad(pad, circle(C, 85.0))
	await _mouse_stroke(pad, body)
	await _mouse_stroke(pad, _scale_to_pad(pad, circle(C + Vector2(0, -123), 34.0)))
	var a0 := _on_core(C, 85.0, 28.0)
	await _mouse_stroke(pad, _scale_to_pad(pad, line(a0, a0 + Vector2(145, -70))))
	await _settle()
	var r: Dictionary = fs.sketch_res
	var sinfo: Dictionary = r.get("info", {})
	_check("ui_strokes_and_preview", fs.sketch_strokes.size() == 3 and fs.sketch_sym and _valid(r.get("bp")) == "" and int(sinfo.get("arms", 0)) == 2,
		"штрихов %d, симметрия %s, превью: %s" % [fs.sketch_strokes.size(), fs.sketch_sym, sinfo.get("line", "—")])
	# S — без симметрии одна рука
	await _key(KEY_S)
	await _settle()
	var one: int = int((fs.sketch_res.get("info", {}) as Dictionary).get("arms", 0))
	await _key(KEY_S)
	await _settle()
	# отмена: Backspace и ПКМ
	await _key(KEY_BACKSPACE)
	var after_bs: int = fs.sketch_strokes.size()
	await _mouse_stroke(pad, PackedVector2Array([Vector2(10, 10), Vector2(12, 12)]), MOUSE_BUTTON_RIGHT)
	var after_rmb: int = fs.sketch_strokes.size()
	_check("ui_sym_undo", one == 1 and after_bs == 2 and after_rmb == 1, "без S рук %d; Backspace → %d штрихов, ПКМ → %d" % [one, after_bs, after_rmb])
	await _key(KEY_C)
	var after_c: int = fs.sketch_strokes.size()
	# заново: человечек мышью → Enter
	for s in human():
		await _mouse_stroke(pad, _scale_to_pad(pad, s))
	await _settle()
	var want := _sig(fs.sketch_res.get("bp"))
	await _key(KEY_N)
	await _settle()
	var n_sig := _sig(fs.sketch_res.get("bp"))
	await _key(KEY_ENTER)
	_check("ui_enter_chosen", after_c == 0 and got.size() == 1 and _valid(got[0]) == "" and _sig(got[0]) == n_sig and String(FighterPick.last.get("kind", "")) == "sketch",
		"C → %d штрихов; chosen %d, N сменил вариант: %s, last %s" % [after_c, got.size(), want != n_sig, FighterPick.last.get("kind", "")])
	if got.size() == 1:
		_fighters.append({"tag": "ui_sketch", "bp": got[0]})
	fs.close()
	await get_tree().process_frame
	# снова: карточка прошлого эскиза, Esc с холста — к карточкам
	fs = await _open()
	var li := fs.index_of("sketch_last")
	_check("ui_last_sketch_card", li >= 0 and fs.sel == li and _sig(fs.current_bp()) == n_sig, "карточка %d, выбрана %d" % [li, fs.sel])
	await _key(KEY_D)
	var opened: bool = fs.sketch_open and fs.sketch_strokes.size() > 0
	await _key(KEY_ESCAPE)
	_check("ui_esc_back", opened and not fs.sketch_open and is_instance_valid(fs) and fs.is_inside_tree(), "холст с прошлым рисунком %s; после Esc открыт %s" % [opened, fs.sketch_open])
	fs.close()
	await get_tree().process_frame


# ------------------------------------------------------------------ spawn

func _find_match(root: Node) -> Match:
	if root is Match:
		return root
	for c in root.get_children():
		var f := _find_match(c)
		if f != null:
			return f
	return null


func _unload() -> void:
	if pg != null and is_instance_valid(pg):
		remove_child(pg)
		pg.queue_free()
	pg = null
	await get_tree().physics_frame
	await get_tree().physics_frame


func _until(cond: Callable, max_s: float) -> bool:
	for i in int(max_s / TICK):
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _wait(s: float) -> void:
	for i in int(round(s / TICK)):
		await get_tree().physics_frame


static func _com(d: Doll) -> Vector3:
	var m := 0.0
	var s := Vector3.ZERO
	for n in d.parts:
		var b := d.parts[n] as RigidBody3D
		if b == null or not is_instance_valid(b):
			continue
		s += (b.global_transform * b.center_of_mass) * b.mass
		m += b.mass
	return s / maxf(m, 1e-6)


func _p1(m: Match) -> Doll:
	for d in m.dolls():
		if (d as Doll).player_index == 0:
			return d
	return null


func _fight(def: ModeDef, bp: BodyBlueprint, play_s: float) -> String:
	await _unload()
	pg = (load(def.scene_path()) as PackedScene).instantiate()
	var m := _find_match(pg)
	if m == null:
		return "нет Match"
	m.countdown_s = 0.0
	m.feel_enabled = false
	add_child(pg)
	ModeRun.launch(def, {"no_scene_change": true, "scene": pg, "p1_bot": true, "player_blueprint": bp, "seed": 7})
	if not await _until(func() -> bool: return ModeRun.is_active() and ModeRun.mt == m, 8.0):
		return "ModeRun не привязался"
	var p1 := _p1(m)
	if not (p1 is ModularDoll) or _sig(p1.get("blueprint")) != _sig(bp):
		return "P1 не тот: %s" % (p1.get_class() if p1 != null else "нет")
	if not await _until(func() -> bool: return m.combat_active(), 6.0):
		return "нет FIGHT (фаза %d)" % m.phase
	var c0 := _com(p1)
	await _wait(play_s)
	if not is_instance_valid(p1):
		return "P1 удалён"
	var c1 := _com(p1)
	if not c1.is_finite():
		return "ЦМ не число"
	if c1.distance_to(c0) > 40.0:
		return "улетел на %.1f м" % c1.distance_to(c0)
	if not p1.alive or p1.hp <= 0.0:
		return "нокаут за %.0f с (hp %.0f)" % [play_s, p1.hp]
	return ""


func _spawn(play_s: float) -> void:
	var def := ModeDef.make("sketch_probe", "Проба эскиза", "duel", [{"id": "bots", "args": {"level": 1}}], "", [], "void")
	if _fighters.is_empty():
		_fighters.append({"tag": "human", "bp": SketchBuild.generate(human(), 0)["bp"]})
	var bad: Array = []
	for e in _fighters:
		var why := await _fight(def, e["bp"], play_s)
		if why != "":
			bad.append("%s: %s" % [e["tag"], why])
			print("    spawn %s: %s" % [e["tag"], why])
	await _unload()
	_check("spawn_lives", bad.is_empty(), bad if not bad.is_empty() else "%d бойцов из эскиза: P1 — тот чертёж, жив через %.0f с против бота" % [_fighters.size(), play_s])
