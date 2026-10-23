## «Эскиз → боец» (docs/plan-demo/SKETCH_FIGHTER.md): каракуля мышью → валидный чертёж тела. Без UI: на вход — штрихи
## (PackedVector2Array в координатах холста, y вниз), на выход — словарь того же вида, что у QuickBuild.generate, плюс info с разбором.
## Сборка — только через API мастерской (CraftEdit.set_root / check + _apply_attach / set_joint / set_control) и помощники QuickBuild,
## поэтому чертёж проходит те же проверки: якоря, вид детали, энергия (BodyBlueprint.energy_cap — и с «запасом из деталей», и без).
##
## Как читается рисунок (все размеры — относительно ядра, поэтому масштаб рисунка не важен):
##   ядро       — самый крупный замкнутый штрих; размер → стиль (маленькое — fast, среднее — balanced, большое — heavy), вытянутость →
##                высокое ядро (бочка, котёл, игрушка) или круглое (барабан, реактор, ящик);
##   голова     — меньший замкнутый штрих над ядром (крупная, от половины ядра, — голова-таран); нет — голова по умолчанию;
##   конечности — открытые штрихи от края ядра: старт сверху-сбоку — плечо, посередине бока — бок, снизу — бедро (штрих вниз — нога);
##                правая половина экрана — якоря *_L (камера портрета смотрит в −z). Длина в диаметрах ядра → 1 или 2 звена, S или L;
##                волнистая линия от ядра — щупальце; лишние руки встают на свободные якоря (бок, бедро), не влезло — отброшено;
##   конец      — зигзаг на конце штриха или отдельный зигзаг у конца руки — навершие-оружие; клякса (петля, кружок) — булава;
##                волна от конца руки — кистень (цепь + булава); короткий прямой штрих — кулак; длинный прямой — ещё звено (до 3);
##   сверху     — штрих от верха ядра или от головы — рога / антенна на Top головы.
## Не влезло в энергию — уступки, как у QuickBuild: лёгкие пулы и цепь в одно звено → тонкие звенья и простые кисти → по одному звену
## и не больше 4 конечностей; последний запас — QuickBuild по умолчанию (info.fallback). Пустой рисунок — человечек «Средний».
class_name SketchBuild
extends RefCounted

const CANVAS := Vector2(760, 640)
const TRIES := 24
## Стиль по радиусу ядра (доля меньшей стороны холста).
const R_FAST := 0.105
const R_HEAVY := 0.165
const CORE_TALL := {"fast": ["kit_core_toy"], "balanced": ["kit_core_barrel", "kit_human_torso"], "heavy": ["kit_core_boiler"]}
const CORE_ROUND := {"fast": ["kit_core_crate"], "balanced": ["kit_core_drum", "kit_core_cage"],
	"heavy": ["kit_core_pro_reactor", "kit_core_league_gyro"]}
const TENTACLES := ["kit_limb_tentacle_s", "kit_limb_league_tentacle_s", "kit_limb_aoe_sinew_s", "kit_limb_aoe_whip_s"]
const ANTENNA := ["kit_deco_antenna", "kit_deco_plume"]
## Порядок сборки якорей (первые — главные, лишние в конце снимаются первыми ради энергии).
const ANCHOR_ORDER := ["Anchor_Shoulder_L", "Anchor_Shoulder_R", "Anchor_Hip_L", "Anchor_Hip_R", "Anchor_Side_L", "Anchor_Side_R", "Anchor_Back"]
## Подписи (ключи перевода, tr в месте показа).
const TIP_TITLES := {"weapon": "навершие", "blob": "булава", "flail": "кистень", "fist": "кулак", "tentacle": "щупальце"}


# ------------------------------------------------------------------ вход

## Чертёж по рисунку. strokes — Array[PackedVector2Array]; seed — вариант деталей (тот же рисунок и seed → тот же чертёж).
## {bp, strike, pull, notes, tries, level, style, info: {roles: PackedStringArray на каждый штрих (core / head / limb / segment /
## tip / deco / ignored), limbs: [{anchor, role, segs, tip, uids}], arms, legs, head_drawn, fallback, line}}.
static func generate(strokes: Array, seed_v: int, canvas: Vector2 = CANVAS) -> Dictionary:
	var plan := read(strokes, canvas)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_v, JSON.stringify(_plan_key(plan))])
	var r := {}
	for t in TRIES:
		var lvl := 0 if t < 8 else (1 if t < 14 else (2 if t < 20 else 3))
		r = _try(plan, rng, lvl)
		if not r.is_empty():
			r["tries"] = t + 1
			r["level"] = lvl
			break
	var fallback := r.is_empty()
	if fallback:
		r = QuickBuild.generate(QuickBuild.default_answers(), seed_v)
		r["limbs"] = []
	var info := {"roles": plan["roles"], "limbs": r.get("limbs", []), "head_drawn": plan["head_drawn"], "fallback": fallback,
		"default_limbs": plan["default_limbs"], "style": String(r.get("style", plan["style"]))}
	var arms := 0
	var legs := 0
	var tips: PackedStringArray = []
	for l in info["limbs"]:
		if String(l["role"]) == "leg":
			legs += 1
		else:
			arms += 1
		var tp := String(l["tip"])
		if TIP_TITLES.has(tp) and not tips.has(tp):
			tips.append(tp)
	info["arms"] = arms
	info["legs"] = legs
	info["tips"] = tips
	info["line"] = summary_line(info)
	r["info"] = info
	r.erase("limbs")
	if not r.has("style"):
		r["style"] = plan["style"]
	return r


## Строка разбора на языке игрока: «Средний · рук 2 · ног 2 · навершие».
static func summary_line(info: Dictionary) -> String:
	var s := TranslationServer.translate("%s · рук %d · ног %d") % [
		TranslationServer.translate(String(QuickBuild.STYLE_TITLES.get(String(info.get("style", "balanced")), ""))),
		int(info.get("arms", 0)), int(info.get("legs", 0))]
	for tp in info.get("tips", PackedStringArray()):
		s += " · " + TranslationServer.translate(String(TIP_TITLES.get(String(tp), "")))
	if bool(info.get("fallback", false)):
		s += " · " + TranslationServer.translate("рисунок не прочитан — боец по умолчанию")
	elif bool(info.get("default_limbs", false)):
		s += " · " + TranslationServer.translate("конечностей нет — поставлены обычные")
	return s


## Зеркальная симметрия: штрих целиком по одну сторону оси x = axis_x повторяется отражённым (штрих через ось — нет; копия, которая
## совпадает с уже нарисованным штрихом, — нет). {strokes: исходные + копии в конце, mirror_of: индекс источника или −1}.
static func with_mirror(strokes: Array, axis_x: float, tol: float = 24.0) -> Dictionary:
	var out: Array = []
	var src: PackedInt32Array = []
	for i in strokes.size():
		out.append(strokes[i])
		src.append(-1)
	for i in strokes.size():
		var s: PackedVector2Array = strokes[i]
		if s.size() < 2:
			continue
		var b := _bbox(s)
		if not (b.position.x > axis_x + 2.0 or b.end.x < axis_x - 2.0):
			continue
		var m := PackedVector2Array()
		for p in s:
			m.append(Vector2(2.0 * axis_x - p.x, p.y))
		var dup := false
		for o in strokes:
			if _same_stroke(m, o, tol):
				dup = true
				break
		if not dup:
			out.append(m)
			src.append(i)
	return {"strokes": out, "mirror_of": src}


# ------------------------------------------------------------------ разбор рисунка

## Разбор без деталей: {style, tall, round, head_drawn, head_ram, limbs: [{anchor, role, segs: ["s"|"l"], tip, stroke}], deco: [kind],
## roles, default_limbs}.
static func read(strokes: Array, canvas: Vector2 = CANVAS) -> Dictionary:
	var md := minf(canvas.x, canvas.y)
	var n := strokes.size()
	var roles: PackedStringArray = []
	roles.resize(n)
	roles.fill("ignored")
	var F: Array = []
	for i in n:
		F.append(_feat(strokes[i] as PackedVector2Array))
	# ядро
	var core_i := -1
	for i in n:
		var f: Dictionary = F[i]
		if bool(f["closed"]) and float(f["eq_d"]) >= 0.07 * md and (core_i < 0 or float(f["area"]) > float(F[core_i]["area"])):
			core_i = i
	var cc := canvas * 0.5
	var crect := Rect2(cc - Vector2.ONE * 0.13 * md, Vector2.ONE * 0.26 * md)
	var cpoly := PackedVector2Array()
	var D := 0.26 * md
	var style := "balanced"
	var tall := false
	var round_ := false
	if core_i >= 0:
		roles[core_i] = "core"
		var f: Dictionary = F[core_i]
		crect = f["bbox"]
		cc = crect.get_center()
		cpoly = strokes[core_i]
		D = float(f["eq_d"])
		var rr := D * 0.5 / md
		style = "fast" if rr < R_FAST else ("balanced" if rr < R_HEAVY else "heavy")
		var asp := crect.size.y / maxf(crect.size.x, 1.0)
		tall = asp > 1.2
		round_ = asp < 0.95
	elif n > 0:
		# ядра нет: середина рисунка
		var all := Rect2()
		var first := true
		for i in n:
			if (strokes[i] as PackedVector2Array).size() == 0:
				continue
			all = F[i]["bbox"] if first else all.merge(F[i]["bbox"])
			first = false
		if not first:
			cc = all.get_center()
			crect = Rect2(cc - Vector2.ONE * D * 0.5, Vector2.ONE * D)
	var half := Vector2(maxf(crect.size.x, 8.0), maxf(crect.size.y, 8.0)) * 0.5
	var tol := maxf(0.2 * D, 0.03 * md)
	# конечности от ядра
	var cand: Array = []   # {i, start, end, a, side, pts}
	for i in n:
		if roles[i] != "ignored":
			continue
		var s: PackedVector2Array = strokes[i]
		if s.size() < 2 or bool(F[i]["closed"]) or float(F[i]["len"]) < 0.12 * D:
			continue
		var d0 := _dist_core(s[0], cpoly, cc, D)
		var d1 := _dist_core(s[s.size() - 1], cpoly, cc, D)
		if minf(d0, d1) > tol:
			continue
		var pts := s if d0 <= d1 else _reversed(s)
		var p := pts[0]
		var v := Vector2((p.x - cc.x) / half.x, (cc.y - p.y) / half.y)
		var a := rad_to_deg(atan2(v.y, absf(v.x)))
		var side := "L" if p.x >= cc.x else "R"
		cand.append({"i": i, "a": a, "side": side, "pts": pts})
	var limbs: Array = []
	var deco: Array = []
	var by_side := {"L": {"arms": [], "legs": []}, "R": {"arms": [], "legs": []}}
	for c in cand:
		if float(c["a"]) > 65.0:
			deco.append({"stroke": int(c["i"]), "kind": _shape(c["pts"], D)})
			roles[int(c["i"])] = "deco"
			continue
		var bucket := "legs" if float(c["a"]) <= -35.0 else "arms"
		(by_side[c["side"]][bucket] as Array).append(c)
	for side in ["L", "R"]:
		var arms: Array = by_side[side]["arms"]
		var legs: Array = by_side[side]["legs"]
		arms.sort_custom(func(x, y): return float(x["a"]) > float(y["a"]))
		legs.sort_custom(func(x, y): return float(x["a"]) < float(y["a"]))
		var free := {"Shoulder": true, "Side": true, "Hip": true}
		var assign: Array = []   # [c, slot]
		if not legs.is_empty():
			assign.append([legs[0], "Hip"])
			free["Hip"] = false
		for c in arms:
			for slot in ["Shoulder", "Side", "Hip"]:
				if free[slot]:
					free[slot] = false
					assign.append([c, slot])
					break
		for k in range(1, legs.size()):
			if free["Side"]:
				free["Side"] = false
				assign.append([legs[k], "Side"])
		for pr in assign:
			var c: Dictionary = pr[0]
			var pts: PackedVector2Array = c["pts"]
			var anchor := "Anchor_%s_%s" % [pr[1], side]
			var chord := pts[pts.size() - 1] - pts[0]
			var role := "leg" if pr[1] == "Hip" and chord.y > 0.35 * chord.length() else "arm"
			var lb := _limb_plan(pts, D, role)
			lb["anchor"] = anchor
			lb["stroke"] = int(c["i"])
			limbs.append(lb)
			roles[int(c["i"])] = "limb"
	# продолжения: штрих у конца конечности → ещё звено / навершие / кистень / кулак
	var cont_tol := maxf(0.25 * D, 0.03 * md)
	var changed := true
	while changed:
		changed = false
		for lb in limbs:
			if String(lb["tip"]) != "" or String(lb["role"]) == "tentacle":
				continue
			var ep: Vector2 = lb["end"]
			for i in n:
				if roles[i] != "ignored":
					continue
				var s: PackedVector2Array = strokes[i]
				if s.size() < 2:
					continue
				var pts := PackedVector2Array()
				if bool(F[i]["closed"]):
					if _dist_poly(ep, s) > cont_tol and ep.distance_to((F[i]["bbox"] as Rect2).get_center()) > cont_tol + float(F[i]["eq_d"]) * 0.5:
						continue
					pts = s
				else:
					var d0 := s[0].distance_to(ep)
					var d1 := s[s.size() - 1].distance_to(ep)
					if minf(d0, d1) > cont_tol:
						continue
					pts = s if d0 <= d1 else _reversed(s)
				var sh := "blob" if bool(F[i]["closed"]) and float(F[i]["eq_d"]) < 0.8 * D else _shape(pts, D)
				var L := _path_len(pts)
				match sh:
					"zigzag":
						lb["tip"] = "weapon"
						roles[i] = "tip"
					"blob":
						lb["tip"] = "blob"
						roles[i] = "tip"
					"wave":
						lb["tip"] = "flail" if String(lb["role"]) == "arm" else "blob"
						roles[i] = "tip"
					_:
						if L < 0.4 * D:
							lb["tip"] = "fist" if String(lb["role"]) == "arm" else ""
							roles[i] = "tip"
						elif (lb["segs"] as Array).size() < 3:
							(lb["segs"] as Array).append("l" if L > 0.9 * D else "s")
							lb["end"] = pts[pts.size() - 1]
							roles[i] = "segment"
						else:
							continue
				changed = true
				break
	# голова: меньший замкнутый штрих над ядром
	var head_i := -1
	var best := INF
	for i in n:
		if roles[i] != "ignored" or not bool(F[i]["closed"]):
			continue
		var hc: Vector2 = (F[i]["bbox"] as Rect2).get_center()
		if hc.y >= cc.y - 0.25 * half.y or absf(hc.x - cc.x) > maxf(half.x * 1.6, D * 0.8):
			continue
		if core_i >= 0 and float(F[i]["area"]) >= float(F[core_i]["area"]):
			continue
		var dd := hc.distance_to(Vector2(cc.x, crect.position.y))
		if dd < best:
			best = dd
			head_i = i
	var head_ram := false
	if head_i >= 0:
		roles[head_i] = "head"
		head_ram = core_i >= 0 and float(F[head_i]["area"]) >= 0.5 * float(F[core_i]["area"])
		# штрихи от головы — рога / антенна
		for i in n:
			if roles[i] != "ignored" or bool(F[i]["closed"]):
				continue
			var s: PackedVector2Array = strokes[i]
			if s.size() < 2:
				continue
			if minf(_dist_poly(s[0], strokes[head_i]), _dist_poly(s[s.size() - 1], strokes[head_i])) <= tol:
				deco.append({"stroke": i, "kind": _shape(s, D)})
				roles[i] = "deco"
	var default_limbs := limbs.is_empty()
	if default_limbs:
		for an in ["Anchor_Shoulder_L", "Anchor_Shoulder_R"]:
			limbs.append({"anchor": an, "role": "arm", "segs": ["s", "s"], "tip": "", "stroke": -1, "end": Vector2.ZERO})
		for an in ["Anchor_Hip_L", "Anchor_Hip_R"]:
			limbs.append({"anchor": an, "role": "leg", "segs": ["l", "s"], "tip": "", "stroke": -1, "end": Vector2.ZERO})
	limbs.sort_custom(func(x, y): return ANCHOR_ORDER.find(String(x["anchor"])) < ANCHOR_ORDER.find(String(y["anchor"])))
	return {"style": style, "tall": tall, "round": round_, "head_drawn": head_i >= 0, "head_ram": head_ram, "limbs": limbs, "deco": deco,
		"roles": roles, "default_limbs": default_limbs and n > 0, "core_drawn": core_i >= 0}


## Конечность по штриху от ядра: звенья по длине, наконечник по хвосту, волна — щупальце.
static func _limb_plan(pts: PackedVector2Array, D: float, role: String) -> Dictionary:
	var r := _resample(pts, maxf(D * 0.05, 2.0))
	var tail := _tail(r, D)
	var body := r
	var tip := ""
	if tail["tip"] != "":
		tip = tail["tip"]
		body = r.slice(0, int(tail["from"]) + 1)
	var L := _path_len(body) / D
	if _shape(body, D) == "wave" and L > 0.5:
		var tsegs: Array = ["s"] if L < 1.0 else ["s", "s"]
		return {"role": "tentacle", "segs": tsegs, "tip": "", "end": r[r.size() - 1]}
	var segs: Array
	if role == "leg":
		segs = ["s"] if L < 0.55 else (["l"] if L < 0.9 else ["l", "s"])
	else:
		segs = ["s"] if L < 0.55 else (["l"] if L < 0.9 else (["s", "s"] if L < 1.5 else ["l", "s"]))
	return {"role": role, "segs": segs, "tip": tip, "end": r[r.size() - 1]}


## Хвост штриха: компактное окно с конца (диагональ до 0.55 D) с большим поворотом — наконечник. {tip: "" | weapon | blob, from}.
static func _tail(r: PackedVector2Array, D: float) -> Dictionary:
	var n := r.size()
	if n < 6:
		return {"tip": "", "from": n - 1}
	var i := n - 1
	var b := Rect2(r[n - 1], Vector2.ZERO)
	while i > 0:
		var nb := b.expand(r[i - 1])
		if nb.size.length() > 0.55 * D:
			break
		b = nb
		i -= 1
	if i <= 0 and n > 0:
		i = 0
	var w := r.slice(i)
	if w.size() < 5:
		return {"tip": "", "from": n - 1}
	var t := _turning(w)
	var diag := maxf(_bbox(w).size.length(), 1.0)
	if float(t["total"]) >= 270.0 and _path_len(w) >= 1.8 * diag:
		return {"tip": "weapon" if int(t["flips"]) >= 2 else "blob", "from": maxi(i, 1)}
	return {"tip": "", "from": n - 1}


## Вид штриха: zigzag (компактный, поворот туда-сюда), blob (петля, поворот в одну сторону), wave (волна), line.
static func _shape(pts: PackedVector2Array, D: float) -> String:
	if pts.size() < 3:
		return "line"
	var r := _resample(pts, maxf(D * 0.05, 2.0))
	var t := _turning(r)
	var L := _path_len(r)
	var diag := maxf(_bbox(r).size.length(), 1.0)
	var chord := maxf(r[0].distance_to(r[r.size() - 1]), 1.0)
	var total := float(t["total"])
	var flips := int(t["flips"])
	if total >= 300.0 and L >= 1.8 * diag:
		return "zigzag" if flips >= 2 else "blob"
	if flips >= 3 and L / chord > 1.12:
		return "wave"
	if total >= 300.0:
		return "blob"
	return "line"


## Повороты по ломаной: total — сумма |угла| (градусы), flips — сколько раз знак поворота сменился (пороги против дрожи руки).
static func _turning(r: PackedVector2Array) -> Dictionary:
	var total := 0.0
	var flips := 0
	var sign_ := 0
	var acc := 0.0   # накопленный поворот в новую сторону, пока не засчитан
	for k in range(1, r.size() - 1):
		var a := r[k] - r[k - 1]
		var b := r[k + 1] - r[k]
		if a.length() < 0.001 or b.length() < 0.001:
			continue
		var d := rad_to_deg(a.angle_to(b))
		if absf(d) < 3.0:
			continue
		total += absf(d)
		var s := 1 if d > 0.0 else -1
		if sign_ == 0:
			sign_ = s
		elif s != sign_:
			acc += absf(d)
			if acc >= 25.0:
				flips += 1
				sign_ = s
				acc = 0.0
		else:
			acc = 0.0
	return {"total": total, "flips": flips}


# ------------------------------------------------------------------ сборка

static func _plan_key(plan: Dictionary) -> Array:
	var out: Array = [plan["style"], plan["tall"], plan["round"], plan["head_ram"]]
	for l in plan["limbs"]:
		out.append([l["anchor"], l["role"], l["segs"], l["tip"]])
	for d in plan["deco"]:
		out.append(d["kind"])
	return out


static func _sized(part_id: String, size: String) -> String:
	if size == "l" and part_id.ends_with("_s") and CraftEdit.part(part_id.trim_suffix("_s") + "_l") != null:
		return part_id.trim_suffix("_s") + "_l"
	if size == "s" and part_id.ends_with("_l") and CraftEdit.part(part_id.trim_suffix("_l") + "_s") != null:
		return part_id.trim_suffix("_l") + "_s"
	return part_id


## Деталь по ключу роли (пары слева и справа — одинаковые: кэш на одну попытку).
static func _cached(cache: Dictionary, key: String, rng: RandomNumberGenerator, pool: Array) -> String:
	if not cache.has(key):
		cache[key] = QuickBuild._pick(rng, pool)
	return String(cache[key])


static func _try(plan: Dictionary, rng: RandomNumberGenerator, lvl: int) -> Dictionary:
	var style := String(plan["style"])
	var P: Dictionary = QuickBuild.POOLS[style]
	var PL: Dictionary = QuickBuild.POOLS["fast"] if lvl >= 1 else P   # звенья конечностей на уступках — лёгкие
	var bp := BodyBlueprint.new()
	bp.id = "sketch_%s" % style
	bp.title = TranslationServer.translate("Эскиз")
	var cores: Array = P["core"]
	if bool(plan["tall"]):
		cores = CORE_TALL[style]
	elif bool(plan["round"]):
		cores = CORE_ROUND[style]
	if not bool(CraftEdit.set_root(bp, QuickBuild._pick(rng, cores)).get("ok", false)):
		return {}
	var core := CraftEdit.root_uid(bp)
	var head_part := QuickBuild._pick(rng, P["ram_head"] if bool(plan["head_ram"]) else P["head"])
	var head := QuickBuild._put(bp, head_part, core, "Anchor_Neck")
	if head == "":
		head = QuickBuild._put(bp, QuickBuild._pick(rng, QuickBuild.POOLS["balanced"]["head"]), core, "Anchor_Neck")
	if head == "":
		return {}
	var cache := {}
	var optional: Array = []
	var notes: PackedStringArray = []
	var built: Array = []
	var plan_limbs: Array = plan["limbs"]
	var count := 0
	# ударная рука — первая рука с наконечником, иначе первая рука (ей — кулак)
	var strike_i := -1
	for k in plan_limbs.size():
		if String(plan_limbs[k]["role"]) == "arm" and String(plan_limbs[k]["tip"]) != "":
			strike_i = k
			break
	if strike_i < 0:
		for k in plan_limbs.size():
			if String(plan_limbs[k]["role"]) == "arm":
				strike_i = k
				break
	for k in plan_limbs.size():
		var pl: Dictionary = plan_limbs[k]
		if lvl >= 3 and count >= 4:
			break
		var role := String(pl["role"])
		if role == "tentacle" and lvl >= 1:
			role = "arm"
		var segs: Array = (pl["segs"] as Array).duplicate()
		var max_segs := 3 if lvl == 0 else (2 if lvl < 3 else 1)
		if segs.size() > max_segs:
			segs.resize(max_segs)
		var uids: Array = []
		var parent := core
		var anchor := String(pl["anchor"])
		for j in segs.size():
			var pid := ""
			if role == "tentacle":
				pid = _cached(cache, "tent", rng, TENTACLES)
			elif lvl >= 2:
				pid = QuickBuild.CHEAP_LEG
			else:
				var pool_key := ("leg_up" if j == 0 else "leg_lo") if role == "leg" else ("arm_up" if j == 0 else "arm_lo")
				pid = _sized(_cached(cache, "%s|%d" % [pool_key, j], rng, PL[pool_key]), String(segs[j]))
			var u := QuickBuild._put(bp, pid, parent, anchor)
			if u == "" and pid != QuickBuild.CHEAP_LEG:
				u = QuickBuild._put(bp, QuickBuild.CHEAP_LEG, parent, anchor)
			if u == "":
				break
			uids.append(u)
			parent = u
			anchor = "Anchor_End"
		if uids.is_empty():
			continue
		count += 1
		if count > 4 or String(pl["anchor"]) == "Anchor_Back":
			optional.append(uids[0])
		var last := String(uids[uids.size() - 1])
		var tip := String(pl["tip"])
		var end_uid := ""
		var tip_uid := ""
		match tip:
			"weapon":
				tip_uid = QuickBuild._put(bp, _cached(cache, "weapon", rng, P["weapon"]), last, "Anchor_End")
			"blob":
				tip_uid = QuickBuild._put(bp, _cached(cache, "blob", rng, P["flail_head"]), last, "Anchor_End")
			"flail":
				var link := last
				for c in (int(P["chain"]) if lvl == 0 else 1):
					link = QuickBuild._put(bp, "chain_segment", link, "Anchor_End")
					if link == "":
						break
				if link != "":
					tip_uid = QuickBuild._put(bp, _cached(cache, "blob", rng, P["flail_head"]), link, "Anchor_End")
				if tip_uid == "":
					for u in CraftEdit.children_of(bp, last):
						CraftEdit.detach(bp, String(u.get("uid", "")))
		if tip_uid != "":
			end_uid = tip_uid
		elif role != "tentacle":
			if tip in ["weapon", "blob", "flail"]:
				tip = "fist"   # навершие не встало — кулак
			var end_part := ""
			if role == "leg":
				end_part = QuickBuild.CHEAP_FOOT if lvl >= 2 else _cached(cache, "foot", rng, P["foot"])
			elif tip == "fist" or k == strike_i:
				end_part = "kit_hand_mitten" if lvl >= 2 else _cached(cache, "fist", rng, P["fist"])
				if tip == "":
					tip = "fist" if k == strike_i else ""
			else:
				end_part = "kit_hand_mitten" if lvl >= 2 else _cached(cache, "hand", rng, P["hand"])
			end_uid = QuickBuild._put(bp, end_part, last, "Anchor_End")
		else:
			tip = "tentacle"
		built.append({"anchor": String(pl["anchor"]), "role": "leg" if role == "leg" else "arm", "segs": uids.size(), "tip": tip,
			"uids": uids, "end": end_uid, "plan": k})
	# рога / антенна на голову (необязательно)
	for d in plan["deco"]:
		var pool: Array = QuickBuild.RAM_DECO if String(d["kind"]) in ["zigzag", "blob"] else ANTENNA
		var u := QuickBuild._put(bp, _cached(cache, "deco|" + String(d["kind"]), rng, pool), head, "Anchor_Top")
		if u == "":
			u = QuickBuild._put(bp, "kit_deco_horns", head, "Anchor_Top")
		if u != "":
			optional.append(u)
			notes.append("deco")
			break
	# тяга (ЛКМ) — на ударной детали
	var strike := ""
	var pull := ""
	for b in built:
		if int(b["plan"]) == strike_i and String(b["end"]) != "":
			strike = String(b["end"])
			pull = String(b["uids"][b["uids"].size() - 1]) if String(b["tip"]) == "flail" else strike
	if strike == "":
		for want in ["arm", "leg"]:
			for b in built:
				if strike == "" and String(b["role"]) == want and String(b["end"]) != "":
					strike = String(b["end"])
					pull = strike
	if strike == "":
		for b in built:
			if strike == "":
				strike = String(b["uids"][b["uids"].size() - 1])
				pull = strike
	if strike == "":
		strike = head
		pull = head
	bp.control = PackedStringArray()
	bp.control_rmb = PackedStringArray()
	if not bool(CraftEdit.set_control(bp, pull).get("ok", false)):
		return {}
	while not QuickBuild._ok(bp) and not optional.is_empty():
		var u := String(optional.pop_back())
		if not CraftEdit.find(bp, u).is_empty():
			CraftEdit.detach(bp, u)
	if not QuickBuild._ok(bp):
		return {}
	# что осталось после снятия необязательного
	var limbs: Array = []
	for b in built:
		if not CraftEdit.find(bp, String(b["uids"][0])).is_empty():
			limbs.append(b)
	return {"bp": bp, "strike": strike, "pull": pull, "notes": notes, "style": style, "limbs": limbs}


# ------------------------------------------------------------------ геометрия

static func _feat(s: PackedVector2Array) -> Dictionary:
	var f := {"len": 0.0, "bbox": Rect2(), "area": 0.0, "eq_d": 0.0, "closed": false}
	if s.size() == 0:
		return f
	var b := _bbox(s)
	var L := _path_len(s)
	f["bbox"] = b
	f["len"] = L
	if s.size() < 6 or L <= 0.0:
		return f
	var area := absf(_signed_area(s))
	var diag := maxf(b.size.length(), 1.0)
	var gap := s[0].distance_to(s[s.size() - 1])
	f["area"] = area
	f["eq_d"] = 2.0 * sqrt(area / PI)
	f["closed"] = gap <= 0.25 * diag and area >= 0.2 * b.size.x * b.size.y and L >= 2.0 * diag
	return f


static func _bbox(s: PackedVector2Array) -> Rect2:
	if s.is_empty():
		return Rect2()
	var b := Rect2(s[0], Vector2.ZERO)
	for p in s:
		b = b.expand(p)
	return b


static func _path_len(s: PackedVector2Array) -> float:
	var L := 0.0
	for k in range(1, s.size()):
		L += s[k].distance_to(s[k - 1])
	return L


static func _signed_area(s: PackedVector2Array) -> float:
	var a := 0.0
	for k in s.size():
		var p := s[k]
		var q := s[(k + 1) % s.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


static func _reversed(s: PackedVector2Array) -> PackedVector2Array:
	var out := s.duplicate()
	out.reverse()
	return out


## Ломаная с шагом h (сглаживает дрожь и выравнивает плотность точек мыши).
static func _resample(s: PackedVector2Array, h: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if s.is_empty():
		return out
	out.append(s[0])
	var carry := 0.0
	for k in range(1, s.size()):
		var a := s[k - 1]
		var b := s[k]
		var seg := a.distance_to(b)
		if seg <= 0.0:
			continue
		var t := h - carry
		while t <= seg:
			out.append(a.lerp(b, t / seg))
			t += h
		carry = seg - (t - h)
	if out[out.size() - 1].distance_to(s[s.size() - 1]) > h * 0.3:
		out.append(s[s.size() - 1])
	return out


## Расстояние до замкнутого контура (0 — внутри).
static func _dist_poly(p: Vector2, poly: PackedVector2Array) -> float:
	if poly.size() < 2:
		return INF if poly.is_empty() else p.distance_to(poly[0])
	if poly.size() >= 3 and Geometry2D.is_point_in_polygon(p, poly):
		return 0.0
	var best := INF
	for k in poly.size():
		var a := poly[k]
		var b := poly[(k + 1) % poly.size()]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best


## Расстояние до ядра: до нарисованного контура, а без него — до круга диаметра D вокруг середины рисунка.
static func _dist_core(p: Vector2, poly: PackedVector2Array, c: Vector2, D: float) -> float:
	if poly.size() >= 3:
		return _dist_poly(p, poly)
	return maxf(p.distance_to(c) - D * 0.5, 0.0)


static func _same_stroke(a: PackedVector2Array, b: PackedVector2Array, tol: float) -> bool:
	if a.size() < 2 or b.size() < 2:
		return false
	var ra := _sample_n(a, 16)
	var rb := _sample_n(b, 16)
	var d1 := 0.0
	var d2 := 0.0
	for k in 16:
		d1 += ra[k].distance_to(rb[k])
		d2 += ra[k].distance_to(rb[15 - k])
	return minf(d1, d2) / 16.0 < tol


static func _sample_n(s: PackedVector2Array, n: int) -> PackedVector2Array:
	var L := _path_len(s)
	var r := _resample(s, maxf(L / float(n - 1), 0.001))
	var out := PackedVector2Array()
	for k in n:
		out.append(r[mini(int(round(float(k) * float(r.size() - 1) / float(n - 1))), r.size() - 1)])
	return out
