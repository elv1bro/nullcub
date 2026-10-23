## Проба экрана «ВЫБОР БОЙЦА» и «Быстрого конструктора» (docs/plan-demo/FIGHTER_SELECT.md). Без окна:
##   godot --headless --path godot --fixed-fps 60 res://tests/fighter_select_probe.tscn [-- only=data|builder|ui|spawn,dice_n=50,spawn_s=5]
## Разделы:
##   data    — ростер (FighterPick.roster): группы кит / лига / про-лига / Аоэлюн, все чертежи целые; кубик: dice_n бросков — все валидны
##             (friendly / structural пусты, энергия ≤ потолка, есть ЛКМ), почти все разные;
##   builder — QuickBuild: все 48 сочетаний ответов × 6 вариантов собираются (с запасом из деталей и без); heavy тяжелее balanced
##             тяжелее fast (в каждом из 16 сочетаний «чем бить × особенность»); ответ «чем бить» и «особенность» видны в деталях
##             (head — ЛКМ на голове-таране, weapon — навершие на конце руки, flail — цепь / трос / ядро, piston — поршень и т. д.);
##             смена любого одного ответа меняет чертёж; «ещё вариант» с теми же ответами — другой чертёж;
##   ui      — сам экран (FighterSelect, dry_run): карточки = «Обычный» + ростер + кубик + быстрая сборка; Enter на «Обычном» → chosen(null);
##             выбранный шаблон → chosen(тот же чертёж); R — кубик; Q → конструктор, клавиши ↑↓ / цифры меняют ответы, N — ещё вариант,
##             Enter → chosen(сборка конструктора); Esc — к карточкам, ещё Esc — cancelled; M → workshop_requested(чертёж);
##   spawn   — каждый боец ростера, выбранные на экране (шаблон, конструктор) и 10 бросков кубика уходят в бой путём игрока —
##             ModeRun.launch(opts.player_blueprint) → ModePlayer.swap_p1 — на поле Void против бота 1 уровня (P1 тоже бот): P1 —
##             ModularDoll с тем же чертежом (signature), через spawn_s секунд жив, ЦМ конечен и на поле.
## → строки «  id  ok/FAIL  деталь», JSON, === OK / FAIL ===, exit 0/1.
extends Node

const TICK := 1.0 / 60.0


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
var _ui_ran := false
var _picked: Array = []        # [{tag, bp}] — что экран отдал в chosen (уходит в spawn)


func _check(id: String, cond: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": cond, "detail": str(detail)})
	if not cond:
		ok = false
	print("  %-34s %s  %s" % [id, "ok  " if cond else "FAIL", str(detail)])


func _args() -> Dictionary:
	var out := {"only": "", "out": "", "dice_n": "50", "spawn_s": "5"}
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
	print("=== FIGHTER SELECT PROBE ===")
	var a := _args()
	var recent: Array = ModeRun._recent.duplicate()   # проба не трогает «последние» игрока
	FighterPick.last = {}
	if _want(a, "data"):
		_data(int(a["dice_n"]))
	if _want(a, "builder"):
		_builder()
	if _want(a, "ui"):
		_ui_ran = true
		await _ui()
	if _want(a, "spawn"):
		await _spawn(float(a["spawn_s"]))
	await _unload()
	ModeRun._recent = recent
	ModeRun._save_cfg()
	FighterPick.last = {}
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


# ------------------------------------------------------------------ data

func _data(dice_n: int) -> void:
	var r := FighterPick.roster()
	var groups := {}
	var bad: Array = []
	for e in r:
		groups[String(e["group"])] = int(groups.get(String(e["group"]), 0)) + 1
		var v := _valid(e["bp"])
		if v != "":
			bad.append("%s: %s" % [e["id"], v])
	info["roster"] = r.size()
	info["roster_groups"] = groups
	_check("roster_size", r.size() >= 20, "бойцов %d" % r.size())
	_check("roster_groups", groups.has("Кит") and groups.has("Лига NULL") and groups.has("Про-лига") and groups.has("Аоэлюн") and groups.has("Шаблоны"),
		groups)
	_check("roster_valid", bad.is_empty(), bad if not bad.is_empty() else "все %d целые" % r.size())
	var no_empty := true
	for e in r:
		if String(e["id"]) in FighterPick.SKIP:
			no_empty = false
	_check("roster_no_empty_templates", no_empty)
	# кубик
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261023
	var fails: Array = []
	var sigs := {}
	var combos := {}
	for i in dice_n:
		var d := FighterPick.roll(rng)
		var bp := d.get("bp", null) as BodyBlueprint
		var v := _valid(bp)
		if v != "":
			fails.append("#%d %s: %s" % [i, QuickBuild.answers_line(d.get("answers", {})), v])
			continue
		sigs[_sig(bp)] = true
		combos[QuickBuild.answers_line(d["answers"])] = true
	_check("dice_valid", fails.is_empty(), fails if not fails.is_empty() else "%d бросков — все валидны" % dice_n)
	_check("dice_varied", sigs.size() >= int(dice_n * 0.9), "разных чертежей %d из %d, сочетаний ответов %d" % [sigs.size(), dice_n, combos.size()])


# ------------------------------------------------------------------ builder

static func _pool_all(key: String) -> Array:
	var out: Array = []
	for s in QuickBuild.POOLS:
		for p in (QuickBuild.POOLS[s] as Dictionary).get(key, []):
			if not out.has(p):
				out.append(p)
	return out


## Ответ «чем бить» виден в деталях: "" — да, иначе что не так.
static func _hitter_seen(bp: BodyBlueprint, hitter: String) -> String:
	var lmb := CraftEdit.find(bp, String(bp.control[0])) if bp.control.size() > 0 else {}
	match hitter:
		"fists":
			if not _pool_all("fist").has(String(lmb.get("part", ""))):
				return "ЛКМ на %s, не на кулаке" % lmb.get("part", "—")
		"head":
			if String(lmb.get("anchor", "")) != "Anchor_Neck" or not _pool_all("ram_head").has(String(lmb.get("part", ""))):
				return "ЛКМ на %s (%s), не на голове-таране" % [lmb.get("part", "—"), lmb.get("anchor", "")]
		"weapon":
			var w := _pool_all("weapon")
			for n in bp.nodes:
				if w.has(String(n.get("part", ""))) and String(n.get("anchor", "")) == "Anchor_End":
					return ""
			return "нет навершия на конце руки"
		"flail":
			for n in bp.nodes:
				if String(n.get("part", "")) in ["chain_segment", "kit_limb_rope_s", "iron_ball_fist"]:
					return ""
			return "нет цепи / троса / ядра"
	return ""


static func _special_seen(bp: BodyBlueprint, special: String) -> String:
	match special:
		"piston":
			for n in bp.nodes:
				if String(n.get("joint", "")) == "on_piston":
					return ""
			return "нет поршня"
		"rotor":
			for n in bp.nodes:
				if String(n.get("part", "")) == "kit_mod_flywheel":
					return ""
			return "нет маховика"
		"arms":
			var sides := {}
			for n in bp.nodes:
				if String(n.get("anchor", "")).begins_with("Anchor_Side"):
					sides[String(n.get("anchor", ""))] = true
			return "" if sides.size() >= 1 else "нет рук на боках"
		"armor":
			for n in bp.nodes:
				if String(n.get("anchor", "")) == "Anchor_Deco" and String(n.get("part", "")).begins_with("kit_deco_"):
					return ""
			return "нет брони"
	return ""


func _builder() -> void:
	var ph0 := PartHp.on
	for hp_on in [true, false]:
		PartHp.on = hp_on
		var tag := "hp" if hp_on else "nohp"
		var fails: Array = []
		var hit_bad: Array = []
		var spec_bad: Array = []
		var min_var := 99
		var mass := {}     # "hitter/special" → {style → [массы]}
		var levels := {0: 0, 1: 0, 2: 0}
		for s in QuickBuild.STYLES:
			for h in QuickBuild.HITTERS:
				for sp in QuickBuild.SPECIALS:
					var sigs := {}
					var key := "%s/%s" % [h, sp]
					if not mass.has(key):
						mass[key] = {}
					(mass[key] as Dictionary)[s] = []
					for seed_v in 6:
						var r := QuickBuild.generate({"style": s, "hitter": h, "special": sp}, seed_v)
						var bp := r.get("bp", null) as BodyBlueprint
						var v := _valid(bp)
						if v != "":
							fails.append("%s/%s/%s#%d: %s" % [s, h, sp, seed_v, v])
							continue
						levels[int(r["level"])] = int(levels.get(int(r["level"]), 0)) + 1
						sigs[_sig(bp)] = true
						((mass[key] as Dictionary)[s] as Array).append(bp.total_mass())
						var hs := _hitter_seen(bp, h)
						if hs != "":
							hit_bad.append("%s/%s/%s#%d: %s" % [s, h, sp, seed_v, hs])
						var ss := _special_seen(bp, sp)
						if ss != "":
							spec_bad.append("%s/%s/%s#%d: %s" % [s, h, sp, seed_v, ss])
					min_var = mini(min_var, sigs.size())
		_check("builder_all_valid_" + tag, fails.is_empty(), fails.slice(0, 6) if not fails.is_empty() else "48 сочетаний × 6 вариантов, уступки %s" % levels)
		_check("builder_hitter_seen_" + tag, hit_bad.is_empty(), hit_bad.slice(0, 6) if not hit_bad.is_empty() else "ЛКМ / навершие / цепь — по ответу")
		_check("builder_special_seen_" + tag, spec_bad.is_empty(), spec_bad.slice(0, 6) if not spec_bad.is_empty() else "поршень / маховик / руки / броня — по ответу")
		_check("builder_variants_" + tag, min_var >= 3, "разных вариантов из 6 у самого бедного сочетания: %d" % min_var)
		# heavy > balanced > fast
		var order_bad: Array = []
		var avg := {"fast": 0.0, "balanced": 0.0, "heavy": 0.0}
		for key in mass:
			var m: Dictionary = mass[key]
			var mean := {}
			for s in QuickBuild.STYLES:
				var arr: Array = m.get(s, [])
				var sum := 0.0
				for x in arr:
					sum += float(x)
				mean[s] = sum / maxf(arr.size(), 1)
				avg[s] = float(avg[s]) + float(mean[s]) / mass.size()
			if not (float(mean["heavy"]) > float(mean["balanced"]) and float(mean["balanced"]) > float(mean["fast"])):
				order_bad.append("%s: fast %.1f bal %.1f heavy %.1f" % [key, mean["fast"], mean["balanced"], mean["heavy"]])
		info["builder_mass_" + tag] = {"fast": snappedf(avg["fast"], 0.1), "balanced": snappedf(avg["balanced"], 0.1), "heavy": snappedf(avg["heavy"], 0.1)}
		_check("builder_heavy_heavier_" + tag, order_bad.is_empty(),
			order_bad.slice(0, 6) if not order_bad.is_empty() else "средняя масса fast %.1f < balanced %.1f < heavy %.1f кг (16/16 сочетаний)" % [avg["fast"], avg["balanced"], avg["heavy"]])
	PartHp.on = ph0
	# одна смена ответа — другой чертёж (тот же вариант)
	var same: Array = []
	var tried := 0
	for seed_v in 4:
		var base := QuickBuild.default_answers()
		var b0 := _sig(QuickBuild.generate(base, seed_v)["bp"])
		for q in ["style", "hitter", "special"]:
			var opts: Array = QuickBuild.STYLES if q == "style" else (QuickBuild.HITTERS if q == "hitter" else QuickBuild.SPECIALS)
			for v in opts:
				if String(v) == String(base[q]):
					continue
				var a2 := base.duplicate()
				a2[q] = v
				tried += 1
				if _sig(QuickBuild.generate(a2, seed_v)["bp"]) == b0:
					same.append("%s=%s#%d" % [q, v, seed_v])
	_check("builder_answer_changes_bp", same.is_empty(), same if not same.is_empty() else "%d смен одного ответа — все дают другой чертёж" % tried)


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


func _open() -> FighterSelect:
	var fs := FighterSelect.open_over(self, {"title": "PROBE", "include_saved": false, "dry_run": true})
	await get_tree().process_frame
	await get_tree().process_frame
	return fs


func _ui() -> void:
	var got: Array = []
	var fs := await _open()
	var on_chosen := func(bp: BodyBlueprint) -> void: got.append(bp)
	fs.chosen.connect(on_chosen)
	var roster := FighterPick.roster()
	# экран модальный: корень и затемнение Bg — во весь кадр (иначе гараж просвечивает и ловит клики)
	var vsz := get_viewport().get_visible_rect().size
	var bg := fs.get_node_or_null("Bg") as Control
	var full: bool = fs.size.is_equal_approx(vsz) and bg != null and bg.size.is_equal_approx(vsz)
	_check("ui_full_screen", full, "экран %s, Bg %s, кадр %s" % [fs.size, bg.size if bg != null else Vector2.ZERO, vsz])
	_check("ui_cards", fs.cards.size() == roster.size() + 4 and String(fs.cards[0]["kind"]) == "default" and fs.index_of("dice") >= 0
		and fs.index_of("builder") >= 0 and fs.index_of("sketch") >= 0, "карточек %d (ростер %d + «Обычный», кубик, быстрая сборка, «Нарисуй»)" % [fs.cards.size(), roster.size()])
	_check("ui_starts_on_default", fs.sel == 0 and fs.current_bp() == null, "sel %d" % fs.sel)
	# стрелки: → и ↓ двигают выбор, ↓ из «МОЙ БОЕЦ» уходит в первый раздел ростера
	await _key(KEY_RIGHT)
	var s1 := fs.sel
	await _key(KEY_DOWN)
	var s2 := fs.sel
	_check("ui_arrows", s1 == 1 and s2 > s1 and String(fs.cards[s2]["kind"]) == "preset", "→ %d, ↓ %d (%s)" % [s1, s2, fs.cards[s2]["kind"]])
	await _key(KEY_LEFT)
	await _key(KEY_UP)
	_check("ui_arrows_back", fs.sel == 0, "← ↑ → %d" % fs.sel)
	await _key(KEY_ENTER)
	_check("ui_default_chosen_null", got.size() == 1 and got[0] == null and String(FighterPick.last.get("kind", "")) == "default", "chosen %s" % [got])
	fs.close()
	await get_tree().process_frame
	# шаблон: выбрать «Человек» (или первый ростера), Enter → тот же чертёж
	got.clear()
	fs = await _open()
	fs.chosen.connect(on_chosen)
	var pi := fs.index_of("preset", "kit_human")
	if pi < 0:
		pi = fs.index_of("preset")
	var want_sig := _sig(fs.cards[pi]["bp"])
	fs.select(pi)
	await _key(KEY_ENTER)
	_check("ui_preset_chosen", got.size() == 1 and got[0] != null and _sig(got[0]) == want_sig,
		"%s → %s" % [fs.cards[pi]["id"], (got[0] as BodyBlueprint).title if got.size() == 1 and got[0] != null else "—"])
	if got.size() == 1 and got[0] != null:
		_picked.append({"tag": "ui_preset_" + String(fs.cards[pi]["id"]), "bp": got[0]})
	fs.close()
	await get_tree().process_frame
	# экран открывается на прошлом выборе
	fs = await _open()
	_check("ui_remembers_last", fs.sel == pi, "открылся на %d, прошлый выбор %d" % [fs.sel, pi])
	fs.chosen.connect(on_chosen)
	# кубик
	got.clear()
	await _key(KEY_R)
	var di := fs.index_of("dice")
	var d1 := fs.current_bp()
	var d1s := _sig(d1)
	await _key(KEY_R)
	var d2s := _sig(fs.current_bp())
	_check("ui_dice", fs.sel == di and _valid(d1) == "" and d1s != d2s, "R → карточка %d, чертёж %s, второй бросок другой %s" % [fs.sel, _valid(d1) if _valid(d1) != "" else "валиден", d1s != d2s])
	await _key(KEY_ENTER)
	_check("ui_dice_chosen", got.size() == 1 and got[0] != null and _sig(got[0]) == d2s, "chosen %d" % got.size())
	fs.close()
	await get_tree().process_frame
	# конструктор: Q, ответы клавишами (↓ — вопрос, цифра — ответ), N — ещё вариант, Enter — в бой
	got.clear()
	fs = await _open()
	fs.chosen.connect(on_chosen)
	await _key(KEY_Q)
	_check("ui_builder_opens", fs.builder_open and fs.current_bp() != null and _valid(fs.current_bp()) == "", "Q → конструктор, %s" % QuickBuild.answers_line(fs.answers))
	await _key(KEY_3)                      # СТИЛЬ: 3 — тяжёлый
	await _key(KEY_DOWN)
	await _key(KEY_2)                      # ЧЕМ БИТЬ: 2 — голова
	await _key(KEY_DOWN)
	await _key(KEY_1)                      # ОСОБЕННОСТЬ: 1 — поршень
	var want := {"style": "heavy", "hitter": "head", "special": "piston"}
	var a_ok: bool = fs.answers == want
	var q1 := fs.current_bp()
	_check("ui_builder_keys", a_ok and _hitter_seen(q1, "head") == "" and _special_seen(q1, "piston") == "",
		"ответы %s, ЛКМ %s" % [QuickBuild.answers_line(fs.answers), _hitter_seen(q1, "head") if _hitter_seen(q1, "head") != "" else "на голове-таране"])
	var v0 := fs._variant
	var q1s := _sig(q1)
	var differs: bool = false
	for i in 3:                            # «ещё вариант»: хотя бы один из трёх другой (у одного сочетания вариантов конечно)
		await _key(KEY_N)
		differs = differs or _sig(fs.current_bp()) != q1s
	_check("ui_builder_reroll", fs._variant == v0 + 3 and fs.answers == want and differs, "N ×3: вариант %d → %d, другой чертёж %s" % [v0, fs._variant, differs])
	var fin := _sig(fs.current_bp())
	await _key(KEY_ENTER)
	_check("ui_builder_chosen", got.size() == 1 and got[0] != null and _sig(got[0]) == fin and String(FighterPick.last.get("kind", "")) == "quick",
		"chosen %d, last %s" % [got.size(), FighterPick.last.get("kind", "")])
	if got.size() == 1 and got[0] != null:
		_picked.append({"tag": "ui_quick_heavy_head_piston", "bp": got[0]})
	# Esc: из конструктора к карточкам, ещё Esc — cancelled
	var cancels := [0]
	fs.cancelled.connect(func() -> void: cancels[0] += 1)
	await _key(KEY_ESCAPE)
	var back_to_cards: bool = not fs.builder_open and cancels[0] == 0
	await _key(KEY_ESCAPE)
	_check("ui_esc", back_to_cards and cancels[0] == 1, "Esc → карточки %s, Esc → cancelled %d" % [back_to_cards, cancels[0]])
	fs.close()
	await get_tree().process_frame
	# повторный вход: карточка «Прошлая сборка» с той же сборкой, экран на ней
	fs = await _open()
	var li := fs.index_of("last")
	_check("ui_last_card", li >= 0 and fs.sel == li and _sig(fs.current_bp()) == fin, "карточка %d, выбрана %d" % [li, fs.sel])
	# M — в мастерскую с выбранным чертежом
	var ws_bp: Array = []
	fs.workshop_requested.connect(func(bp: BodyBlueprint) -> void: ws_bp.append(bp))
	await _key(KEY_M)
	_check("ui_workshop", ws_bp.size() == 1 and _sig(ws_bp[0]) == fin, "workshop_requested %d" % ws_bp.size())
	fs.close()
	await get_tree().process_frame
	# мышь: клик выбирает, клик по выбранной — в бой
	got.clear()
	fs = await _open()
	fs.chosen.connect(on_chosen)
	var ci := fs.index_of("preset")
	(fs.cards[ci]["node"] as Button).pressed.emit()
	var after1 := got.size()
	(fs.cards[ci]["node"] as Button).pressed.emit()
	_check("ui_click_select_then_fight", fs.sel == ci and after1 == 0 and got.size() == 1, "1-й клик: выбор %d, chosen %d; 2-й: chosen %d" % [fs.sel, after1, got.size()])
	fs.close()
	await get_tree().process_frame
	FighterPick.last = {}


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


## Один боец путём игрока: ModeRun.launch(opts.player_blueprint) на Void против бота; "" — жив, иначе что не так.
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
	var def := ModeDef.make("fighter_select_probe", "Проба выбора бойца", "duel", [{"id": "bots", "args": {"level": 1}}], "", [], "void")
	var list: Array = []
	for e in FighterPick.roster():
		list.append({"tag": String(e["id"]), "bp": e["bp"]})
	list.append_array(_picked)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 10:
		var d := FighterPick.roll(rng)
		list.append({"tag": "dice_%d_%s" % [i, QuickBuild.answers_line(d["answers"])], "bp": d["bp"]})
	var bad: Array = []
	var t0 := Time.get_ticks_msec()
	for e in list:
		var why := await _fight(def, e["bp"], play_s)
		if why != "":
			bad.append("%s: %s" % [e["tag"], why])
			print("    spawn %s: %s" % [e["tag"], why])
	await _unload()
	info["spawn_n"] = list.size()
	info["spawn_wall_s"] = snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1)
	_check("spawn_reaches_p1_and_lives", bad.is_empty(), bad if not bad.is_empty() else "%d бойцов (ростер %d, с экрана %d, кубик 10): P1 — тот чертёж, жив через %.0f с против бота" % [
		list.size(), list.size() - _picked.size() - 10, _picked.size(), play_s])
	if _ui_ran:   # с экрана бойцов отдаёт только часть ui
		_check("spawn_from_screen", _picked.size() >= 2, "с экрана в бой ушло %d (шаблон, конструктор)" % _picked.size())
