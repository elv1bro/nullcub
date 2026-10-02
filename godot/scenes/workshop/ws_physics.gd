## Physics Overlay мастерской (UI/UX spec v0.3 §20–21): физика сборки видна «как у игрушки на верстаке», а не как в CAD — поверх
## куклы на стенде: где центр масс (маленькая тёплая точка с отвесом до пола, не огромное перекрестие), как разложена масса (мягкие
## пятна по деталям), какие суставы держат через силу (точки зелёный → жёлтый → красный) и куда сборку клонит (изогнутая стрелка).
## Только расчёт и рисование в 2D: лид зовёт draw() из _draw полноэкранного оверлея (Control) каждый кадр, числа для правой панели —
## summary(). Состояния нет (кроме плашки бирки в кэше) — всё считается заново от текущих поз тел: кукла стенда заморожена, дюжина
## тел — дёшево (tests/ws_physics_probe печатает цену: summary ≈ 0.25 мс на human в headless-контейнере, draw — примерно столько же).
##
## Модель (статика, кукла в позе стенда):
##   • центр масс тела — ModularDoll._com_local (CUSTOM после слияния fixed-деталей или центр объёмов форм, как AUTO у Jolt), куклы —
##     среднее по массам;
##   • сустав — пара мышцы Doll._muscle_pairs (родитель, ребёнок, tmax с множителем типа KitJoint, группа), а не пути node_a / node_b:
##     мастерская обнуляет их у замороженного стенда. Точка и ось — кадр сустава на ТЕКУЩЕМ теле-родителе (Doll._joint_xf_a): узел
##     сустава остаётся на месте сборки, когда поза стенда повернула родителя (ModularDoll._snap_pose);
##   • нагрузка сустава = |момент тяжести всей дистальной цепи вокруг оси сустава| / (tmax мышцы + трение шарнира). Приближение:
##     цепь ниже сустава считается жёсткой (её суставы держат сами себя), пол не помогает — «сколько мышце держать конечность на
##     весу»; на стенде так и есть (кукла висит на штанге за торс). Трение в знаменателе, потому что мотор-трение Jolt (v = 0,
##     force_limit) тоже держит статический момент: у лодыжки tmax 0 и стопу держит только оно. > 1 — мышца не удержит позу,
##     конечность провиснет;
##   • свободный шарнир (KitJoint free: k = tmax = 0) с плечом тяжести больше FREE_LEVER просто болтается (кистень, верёвка) —
##     load 1.0 и "free": true; висящий отвесно — load 0, "free": true. Трение (0.3 × группы) такую цепь не держит в бою, поэтому
##     плечо, а не «момент > трения»: иначе верёвка под булавой на 5° от отвеса светилась бы жёлтой «нагрузкой 81 %». Сустав без
##     мышцы по группе (лодыжка, tmax 0) болтается, только когда момент больше трения. Болтание — не перегрузка, а замысел детали:
##     рисуется нейтральным колечком с маятником;
##   • тяжесть — ProjectSettings physics/3d/default_gravity (в проекте 2 м/с²: обычные сборки зелёные, жёлтое и красное — настоящий
##     перебор: тяжёлое навершие на пружине, длинная рука под булавой);
##   • опора и крен — в плоскости куклы 2.5D: X — вбок (горизонталь плоскости, у неповёрнутого стенда = мировой X), вверх — против
##     тяжести. Опора — формы тел в SUPPORT_BAND от самой нижней точки (как «устойчивость» мастерской v0.2), крен — где центр масс
##     над ней.
class_name WsPhysics
extends RefCounted

## Формы в этой полосе над самой нижней точкой куклы считаются опорой (м).
const SUPPORT_BAND := 0.08
## Пороги цвета нагрузки сустава: < LOAD_WARN — зелёный, до LOAD_HIGH — жёлтый, выше — красный с кольцом-пульсом.
const LOAD_WARN := 0.5
const LOAD_HIGH := 0.9
## Стрелка крена рисуется, когда |tip.dir| больше (0 — центр масс над серединой опоры, 1 — над краем или за ним).
const TIP_ARROW_MIN := 0.35
## Минимальная полуширина опоры для dir (м): у точечной опоры (шар ядра) без неё dir прыгал бы ±1 от миллиметров.
const MIN_HALF_SPAN := 0.02
## Плечо тяжести цепи (м, по горизонтали от оси), с которого свободный шарнир считается болтающимся, а не висящим отвесно.
const FREE_LEVER := 0.01

## Цвета по семантике спецификации: бело-голубой — нейтральное (масса, опора, призрак), янтарь — центр масс (энергия / выбранное),
## зелёный / жёлтый / красный — нагрузка и крен. Тень — тёмная тёплая подложка, чтобы тонкие линии читались поверх куклы.
const COL_MASS := Color(0.80, 0.90, 1.0)
const COL_NEUTRAL := Color(0.72, 0.88, 1.0)
const COL_AMBER := Color(1.0, 0.72, 0.28)
const COL_AMBER_HOT := Color(1.0, 0.93, 0.74)
const COL_OK := Color(0.47, 0.90, 0.46)
const COL_WARN := Color(1.0, 0.82, 0.26)
const COL_BAD := Color(1.0, 0.33, 0.25)
const COL_SHADOW := Color(0.05, 0.035, 0.02, 0.55)
const COL_PAPER := Color(0.93, 0.88, 0.76, 0.93)
const COL_INK := Color(0.17, 0.13, 0.09)
const LABEL_SIZE := 13

static var _paper_box: StyleBoxFlat
static var _fade := 1.0   # opts.alpha на время одного draw(): все цвета × на неё (плавное появление слоя)


# --- расчёт ---

## Тяжесть проекта (м/с², вектор): default_gravity × default_gravity_vector.
static func gravity() -> Vector3:
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var v: Variant = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN)
	var d: Vector3 = (v as Vector3).normalized() if v is Vector3 and (v as Vector3).length() > 1e-6 else Vector3.DOWN
	return d * g


## Центр масс тела в мире.
static func body_com(rb: RigidBody3D) -> Vector3:
	return rb.global_transform * ModularDoll._com_local(rb)


## Центр масс куклы (мир), средний по массам тел; тел нет — позиция узла куклы.
static func com(doll: Node) -> Vector3:
	return _com_of(doll, _snapshot(doll))


## Распределение массы: [{pos (центр масс тела, мир), mass (кг), frac (доля всей массы), body (имя тела)}].
static func mass_points(doll: Node) -> Array:
	return _mass_points_of(_snapshot(doll))


## Нагрузка суставов (см. модель в шапке): [{pos (точка сустава, мир), load (0…, 1 = предел мышцы; у болтающегося 1, у свободного
## без плеча 0), joint, group, free (свободный шарнир / болтается), type (тип шарнира KitJoint), torque (Н·м момент тяжести цепи),
## hold (Н·м tmax + трение), child (имя тела ниже сустава)}].
static func joint_stress(doll: Node) -> Array:
	return _stress_of(doll, _snapshot(doll))


## Опора: {min_x, max_x (м вдоль бока куклы — у неповёрнутого стенда мировой X), floor_y (нижняя точка форм, высота против тяжести),
## bodies (имена тел опоры)}. Формы в SUPPORT_BAND от нижней точки; без форм — точка под центром масс.
static func support(doll: Node) -> Dictionary:
	var ax := _axes(doll)
	var lat: Vector3 = ax[0]
	var up: Vector3 = ax[1]
	var shapes: Array = []   # [низ вдоль up, отрезок вдоль бока, имя тела]
	var lo := INF
	for rb: RigidBody3D in _bodies(doll):
		for c in rb.get_children():
			var cs := c as CollisionShape3D
			if cs == null or cs.shape == null or cs.disabled:
				continue
			var xf := rb.global_transform * cs.transform
			var ey := _extent(xf, cs.shape, up)
			shapes.append([ey.x, _extent(xf, cs.shape, lat), String(rb.name)])
			lo = minf(lo, ey.x)
	if shapes.is_empty():
		var c0 := com(doll)
		return {"min_x": c0.dot(lat), "max_x": c0.dot(lat), "floor_y": c0.dot(up), "bodies": PackedStringArray()}
	var mn := INF
	var mx := -INF
	var names := PackedStringArray()
	for s: Array in shapes:
		if float(s[0]) > lo + SUPPORT_BAND:
			continue
		mn = minf(mn, (s[1] as Vector2).x)
		mx = maxf(mx, (s[1] as Vector2).y)
		if not names.has(String(s[2])):
			names.append(String(s[2]))
	return {"min_x": mn, "max_x": mx, "floor_y": lo, "bodies": names}


## Крен: {dir (−1 влево … 0 ровно … +1 вправо: смещение центра масс от середины опоры в долях полуширины; за краем — ±1),
## margin (м: насколько центр масс внутри опоры, < 0 — снаружи, опрокинется), height (м: центр масс над полом)}.
static func tip(doll: Node) -> Dictionary:
	var ax := _axes(doll)
	return _tip_of(com(doll), support(doll), ax[0], ax[1])


## Числа для правой панели: {com, max_load, max_joint, tip} + mass (кг), max_muscle_load / max_muscle_joint (без свободных: у
## болтающихся load всегда 1.0), free_joints (имена свободных и болтающихся суставов).
static func summary(doll: Node) -> Dictionary:
	var snap := _snapshot(doll)
	var ml := 0.0
	var mj := ""
	var mm := 0.0
	var mmj := ""
	var dangling := PackedStringArray()
	for s: Dictionary in _stress_of(doll, snap):
		var l := float(s["load"])
		if l > ml or mj == "":
			ml = l
			mj = String(s["joint"])
		if bool(s["free"]):
			dangling.append(String(s["joint"]))
		elif l > mm or mmj == "":
			mm = l
			mmj = String(s["joint"])
	var mass := 0.0
	for e: Array in snap:
		mass += float(e[2])
	var c := _com_of(doll, snap)
	var ax := _axes(doll)
	return {"com": c, "max_load": ml, "max_joint": mj, "tip": _tip_of(c, support(doll), ax[0], ax[1]), "mass": mass,
		"max_muscle_load": mm, "max_muscle_joint": mmj, "free_joints": dangling}


# --- рисование ---

## Рисует слой на ci (зовётся из _draw полноэкранного Control, координаты — как у cam.unproject_position). opts:
##   t: float — секунды для пульсов и маятников; ghost_com: Vector3 или null — центр масс с тащимой деталью (бело-голубая полая
##   точка и пунктир от текущего); labels: bool — бумажные бирки (ЦМ, проценты нагрузки ≥ LOAD_WARN, «болтается», крен);
##   необязательные: floor_y: float — высота пола стенда (иначе нижняя точка куклы); alpha: float — общая прозрачность слоя;
##   scale: float — размер точек и линий (1 = экран 1920×1080); mass / stress / tip: bool — слои (по умолчанию все).
static func draw(ci: CanvasItem, cam: Camera3D, doll: Node, font: Font, opts := {}) -> void:
	if ci == null or cam == null or doll == null or not is_instance_valid(doll) or _bodies(doll).is_empty():
		return
	_fade = clampf(float(opts.get("alpha", 1.0)), 0.0, 1.0)
	if _fade <= 0.0:
		return
	var t := float(opts.get("t", 0.0))
	var k := clampf(float(opts.get("scale", 1.0)), 0.4, 3.0)
	var labels := bool(opts.get("labels", false)) and font != null
	var ax := _axes(doll)
	var lat: Vector3 = ax[0]
	var up: Vector3 = ax[1]
	var snap := _snapshot(doll)
	var c := _com_of(doll, snap)
	var sup := support(doll)
	if opts.get("floor_y") != null:
		sup["floor_y"] = float(opts["floor_y"])
	var tp := _tip_of(c, sup, lat, up)
	var tags: Array = []   # [точка, текст, цвет метки, приоритет] — бирки рисуются последними, поверх всего, не налезая друг на друга
	# пиксели на метр у центра масс: пятна массы — в метрах (тяжёлое и на экране крупнее), точки и линии — в пикселях
	var ppm := 300.0
	if not cam.is_position_behind(c):
		ppm = maxf(cam.unproject_position(c).distance_to(cam.unproject_position(c + cam.global_basis.x * 0.5)) * 2.0, 1.0)

	if bool(opts.get("mass", true)):
		for m: Dictionary in _mass_points_of(snap):
			var p3: Vector3 = m["pos"]
			if cam.is_position_behind(p3):
				continue
			_soft_disc(ci, cam.unproject_position(p3), clampf(ppm * (0.018 + 0.085 * sqrt(float(m["frac"]))), 3.0 * k, 34.0 * k))

	# опора и отвес: тонкая линия опоры на полу, пунктир от центра масс вниз, засечка — зелёная над опорой, красная за краем
	var fy := float(sup["floor_y"])
	var c_floor := c + up * (fy - c.dot(up))
	var s0 := c_floor + lat * (float(sup["min_x"]) - c.dot(lat))
	var s1 := c_floor + lat * (float(sup["max_x"]) - c.dot(lat))
	var inside := float(tp["margin"]) >= 0.0
	if not (cam.is_position_behind(s0) or cam.is_position_behind(s1) or cam.is_position_behind(c_floor) or cam.is_position_behind(c)):
		var a2 := cam.unproject_position(s0)
		var b2 := cam.unproject_position(s1)
		var sc := COL_NEUTRAL if inside else COL_BAD
		_line(ci, a2, b2, _a(sc, 0.75), 2.0 * k)
		for e2 in [a2, b2]:
			_line(ci, e2, e2 + Vector2(0, -5.0 * k), _a(sc, 0.75), 1.6 * k)
		var cf2 := cam.unproject_position(c_floor)
		var c2 := cam.unproject_position(c)
		_dashed(ci, c2, cf2, _a(COL_AMBER, 0.6), 1.3 * k, 4.0 * k)
		var tick := COL_OK if inside else COL_BAD
		_line(ci, cf2 + Vector2(-5.0 * k, 0), cf2 + Vector2(5.0 * k, 0), _a(tick, 0.95), 2.4 * k)

	if bool(opts.get("stress", true)):
		var free_tagged := false   # бирка у свободного шарнира — одна на куклу: маятник дальше понятен и без слов
		for s: Dictionary in _stress_of(doll, snap):
			var p3: Vector3 = s["pos"]
			if cam.is_position_behind(p3):
				continue
			var p := cam.unproject_position(p3)
			if bool(s["free"]):
				var down := cam.unproject_position(p3 - up * 0.1) - p
				_free_mark(ci, p, down.normalized() if down.length() > 0.5 else Vector2.DOWN, t, k)
				if labels and not free_tagged:
					free_tagged = true
					tags.append([p + Vector2(9.0 * k, 12.0 * k), TranslationServer.translate("болтается") if float(s["load"]) >= 1.0 else TranslationServer.translate("свободно"), COL_NEUTRAL, 4])
				continue
			var ld := float(s["load"])
			_stress_dot(ci, p, ld, t, k)
			if labels and ld >= LOAD_WARN:
				tags.append([p + Vector2(8.0 * k, -6.0 * k), "%d%%" % roundi(ld * 100.0), load_colour(ld), 3])

	if not cam.is_position_behind(c):
		var c2 := cam.unproject_position(c)
		_com_mark(ci, c2, t, k)
		if bool(opts.get("tip", true)) and absf(float(tp["dir"])) > TIP_ARROW_MIN:
			var side := cam.unproject_position(c + lat * 0.1).x - c2.x
			var sgn := signf(float(tp["dir"])) * (1.0 if side >= 0.0 else -1.0)
			var end := _tip_arrow(ci, c2, sgn, absf(float(tp["dir"])), inside, t, k)
			if labels:
				var word := TranslationServer.translate("крен") if inside else TranslationServer.translate("опрокинется")
				var w := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(int(round(LABEL_SIZE * k)), 9)).x + 16.0 * k
				tags.append([end + Vector2(6.0 * k if sgn > 0.0 else -6.0 * k - w, 2.0 * k), word, COL_WARN if inside else COL_BAD, 1])
		if labels:
			tags.append([c2 + Vector2(11.0 * k, 4.0 * k), TranslationServer.translate("ЦМ"), COL_AMBER, 0])

	var gh: Variant = opts.get("ghost_com")
	if gh is Vector3 and not cam.is_position_behind(gh) and not cam.is_position_behind(c):
		var g2 := cam.unproject_position(gh)
		var c2 := cam.unproject_position(c)
		var gin := (gh as Vector3).dot(lat) >= float(sup["min_x"]) and (gh as Vector3).dot(lat) <= float(sup["max_x"])
		_ghost_mark(ci, c2, g2, k)
		var gf3 := (gh as Vector3) + up * (fy - (gh as Vector3).dot(up))
		if not cam.is_position_behind(gf3):
			var gf2 := cam.unproject_position(gf3)
			_line(ci, gf2 + Vector2(-4.0 * k, 0), gf2 + Vector2(4.0 * k, 0), _a(COL_NEUTRAL if gin else COL_BAD, 0.9), 2.0 * k)
		if labels:
			# сдвиг в сантиметрах: вбок (стрелка — как на экране) и, если заметно, вверх / вниз
			var d := (gh as Vector3) - c
			var dx := roundi(absf(d.dot(lat)) * 100.0)
			var dy := roundi(d.dot(up) * 100.0)
			var txt := "%s%d" % ["→" if g2.x >= c2.x else "←", dx]
			if dy != 0:
				txt += " %s%d" % ["↑" if dy > 0 else "↓", absi(dy)]
			tags.append([g2 + Vector2(9.0 * k, 14.0 * k), txt + TranslationServer.translate(" см"), COL_NEUTRAL, 2])

	# бирки по важности (ЦМ, крен, призрак, нагрузка, свободные): следующая, если налезает, съезжает вниз / вверх на строку
	tags.sort_custom(func(x: Array, y: Array) -> bool: return int(x[3]) < int(y[3]))
	var placed: Array = []
	for tg: Array in tags:
		var r := _free_spot(_tag_rect(font, tg[0], String(tg[1]), k), placed, k)
		placed.append(r)
		_tag(ci, font, r, String(tg[1]), tg[2], k)
	_fade = 1.0


## Цвет нагрузки: зелёный < LOAD_WARN, жёлтый до LOAD_HIGH, красный выше (для правой панели — те же пороги).
static func load_colour(v: float) -> Color:
	if v > LOAD_HIGH:
		return COL_BAD
	if v >= LOAD_WARN:
		return COL_WARN
	return COL_OK


# --- внутреннее: данные ---

## Снимок тел на один вызов: [[тело, центр масс (мир), масса]] — центр масс тела (_com_local по формам) считается один раз.
static func _snapshot(doll: Node) -> Array:
	var out: Array = []
	for rb: RigidBody3D in _bodies(doll):
		out.append([rb, body_com(rb), rb.mass])
	return out


static func _com_of(doll: Node, snap: Array) -> Vector3:
	var sm := 0.0
	var acc := Vector3.ZERO
	for e: Array in snap:
		acc += (e[1] as Vector3) * float(e[2])
		sm += float(e[2])
	if sm > 0.0:
		return acc / sm
	return (doll as Node3D).global_position if doll is Node3D else Vector3.ZERO


static func _mass_points_of(snap: Array) -> Array:
	var total := 0.0
	for e: Array in snap:
		total += float(e[2])
	var out: Array = []
	for e: Array in snap:
		out.append({"pos": e[1], "mass": float(e[2]), "frac": float(e[2]) / total if total > 0.0 else 0.0,
			"body": String((e[0] as Node).name)})
	return out


## Момент тяжести цепи: Σ (cᵢ − p) × wᵢ·g = (Σ wᵢcᵢ − p·Σ wᵢ) × g, wᵢ = масса × gravity_scale — на тело-ребёнка хватает суммы по
## поддереву ([Σ wᵢcᵢ, Σ wᵢ], _subtree), без обхода цепи на каждый сустав.
static func _stress_of(doll: Node, snap: Array) -> Array:
	var out: Array = []
	var links := _links(doll)
	if links.is_empty():
		return out
	var g := gravity()
	var own := {}    # тело -> [wᵢcᵢ, wᵢ]
	for e: Array in snap:
		var w := float(e[2]) * (e[0] as RigidBody3D).gravity_scale
		own[e[0]] = [(e[1] as Vector3) * w, w]
	var kids := {}   # тело-родитель -> [тела-дети]
	for l: Dictionary in links:
		if not kids.has(l["a"]):
			kids[l["a"]] = []
		(kids[l["a"]] as Array).append(l["b"])
	var memo := {}
	for l: Dictionary in links:
		var fr := _joint_frame(doll, l)
		var pivot := fr.origin
		var sub := _subtree(l["b"], kids, own, memo)
		var wsum := float(sub[1])
		var tau := absf(((sub[0] as Vector3) - pivot * wsum).cross(g).dot(fr.basis.z.normalized()))
		var tmax := maxf(float(l["tmax"]), 0.0)
		var hold := tmax + maxf(float(l["friction"]), 0.0)
		var lever := tau / (wsum * g.length()) if wsum > 0.0 and g.length() > 0.0 else 0.0
		var jt := String(l["type"])
		var free_type := jt == "free"
		# свободный шарнир болтается при любом заметном плече (так задуман); сустав без мышцы (лодыжка) — когда трение не держит
		var dangles := lever > FREE_LEVER if free_type else (tmax <= 0.0 and tau > hold)
		var ld := 1.0 if dangles else (0.0 if free_type or hold <= 0.0 else tau / hold)
		out.append({"pos": pivot, "load": ld, "joint": String(l["name"]), "group": String(l["group"]), "free": dangles or free_type,
			"type": jt, "torque": tau, "hold": hold, "child": String((l["b"] as Node).name)})
	return out


## [Σ wᵢcᵢ, Σ wᵢ] тела b и всего ниже него по суставам (memo — на один вызов; повторный заход в тело — пусто, защита от цикла).
static func _subtree(b: Variant, kids: Dictionary, own: Dictionary, memo: Dictionary) -> Array:
	if memo.has(b):
		return memo[b]
	memo[b] = [Vector3.ZERO, 0.0]
	var o: Array = own.get(b, [Vector3.ZERO, 0.0])
	var s: Vector3 = o[0]
	var w := float(o[1])
	for c in kids.get(b, []):
		var r := _subtree(c, kids, own, memo)
		s += r[0] as Vector3
		w += float(r[1])
	memo[b] = [s, w]
	return memo[b]


## Тела куклы в дереве (Doll.parts).
static func _bodies(doll: Node) -> Array:
	var out: Array = []
	if doll == null or not is_instance_valid(doll):
		return out
	var p: Variant = doll.get("parts")
	if not p is Dictionary:
		return out
	for b in (p as Dictionary).values():
		if is_instance_valid(b) and b is RigidBody3D and (b as Node).is_inside_tree():   # сначала «жив ли»: освобождённое тело не проверяют на тип
			out.append(b)
	return out


## Суставы с мышцами: [{name, a, b, tmax, group, type, friction, joint}] — из Doll._muscle_pairs (tmax уже × множитель типа шарнира,
## ModularDoll._update_pair_gains), суставы без пары (группы нет в Tuning.MUSCLE_GROUPS) — по node_a / node_b, если пути целы.
static func _links(doll: Node) -> Array:
	var out: Array = []
	if doll == null or not is_instance_valid(doll):
		return out
	var jv: Variant = doll.get("joints")
	var joints: Dictionary = jv if jv is Dictionary else {}
	var fb: Variant = doll.get("_friction_base")
	var seen := {}
	var pairs: Variant = doll.get("_muscle_pairs")
	if pairs is Array:
		for e: Array in pairs:
			if not is_instance_valid(e[0]) or not is_instance_valid(e[1]):
				continue
			var a := e[0] as RigidBody3D
			var b := e[1] as RigidBody3D
			if a == null or b == null or not a.is_inside_tree() or not b.is_inside_tree():
				continue
			var jn := String(e[Doll.MP_NAME])
			seen[jn] = true
			out.append(_link(jn, a, b, float(e[Doll.MP_TMAX]), String(e[Doll.MP_GROUP]), joints.get(jn) as Node, fb))
	for jn in joints:
		var j := joints[jn] as Generic6DOFJoint3D
		if seen.has(String(jn)) or j == null or not is_instance_valid(j):
			continue
		var a: RigidBody3D = null if j.node_a.is_empty() else j.get_node_or_null(j.node_a) as RigidBody3D
		var b: RigidBody3D = null if j.node_b.is_empty() else j.get_node_or_null(j.node_b) as RigidBody3D
		if a == null or b == null:
			continue
		var grp := String(jn).split("_")[0]
		var jt := String(j.get_meta("joint_type", KitJoint.DEFAULT))
		var tmax := float((Tuning.MUSCLE_GROUPS.get(grp, {}) as Dictionary).get("tmax", 0.0)) * float(KitJoint.info(jt).get("tmax", 1.0))
		out.append(_link(String(jn), a, b, tmax, grp, j, fb))
	return out


static func _link(jn: String, a: RigidBody3D, b: RigidBody3D, tmax: float, group: String, j: Node, fb: Variant) -> Dictionary:
	var fr := 0.0
	var jt := KitJoint.DEFAULT
	if j != null and is_instance_valid(j):
		jt = String(j.get_meta("joint_type", KitJoint.DEFAULT))
		if fb is Dictionary and (fb as Dictionary).has(j):
			fr = float((fb as Dictionary)[j])
		else:
			fr = Tuning.JOINT_FRICTION * float(j.get_meta("friction_factor", 1.0))
	return {"name": jn, "a": a, "b": b, "tmax": tmax, "group": group, "type": jt, "friction": fr, "joint": j}


## Кадр сустава в мире сейчас: кадр сборки на теле-родителе (Doll._joint_xf_a) — едет вместе с родителем; иначе точка на родителе
## (_joint_local_a) с осью Z плоскости куклы; иначе узел сустава.
static func _joint_frame(doll: Node, l: Dictionary) -> Transform3D:
	var a := l["a"] as RigidBody3D
	var jn := String(l["name"])
	var xa: Variant = doll.get("_joint_xf_a")
	if xa is Dictionary and (xa as Dictionary).has(jn):
		return a.global_transform * ((xa as Dictionary)[jn] as Transform3D)
	var n := _plane_normal(doll)
	var la: Variant = doll.get("_joint_local_a")
	if la is Dictionary and (la as Dictionary).has(jn):
		return Transform3D(Basis(Vector3.UP.cross(n).normalized(), Vector3.UP, n), a.global_transform * ((la as Dictionary)[jn] as Vector3))
	var j := l.get("joint") as Node3D
	if j != null and is_instance_valid(j):
		return j.global_transform
	return Transform3D(Basis.IDENTITY, a.global_position)


## Нормаль плоскости куклы 2.5D (мир): ось Z узла куклы, повёрнутая так же, как корень повернулся от сборки (ModularDoll.assembly) —
## стенд, повёрнутый на 90° (R в мастерской), крутит тела, а не узел куклы. Поворот в самой плоскости нормаль не меняет.
static func _plane_normal(doll: Node) -> Vector3:
	var d3 := doll as Node3D
	if d3 == null:
		return Vector3.BACK
	var n := d3.global_basis.z.normalized()
	var asm: Variant = doll.get("assembly")
	var root := _root_body(doll)
	if asm is Dictionary and root != null and (asm as Dictionary).has(String(root.name)):
		var b0: Basis = d3.global_basis * ((asm as Dictionary)[String(root.name)] as Transform3D).basis
		n = (root.global_basis * b0.inverse()) * n
	return n.normalized() if n.length() > 1e-6 else Vector3.BACK


## [бок, вверх]: вверх — против тяжести, бок — горизонталь плоскости куклы (у неповёрнутого стенда — мировой +X).
static func _axes(doll: Node) -> Array:
	var up := -gravity().normalized()
	var lat := up.cross(_plane_normal(doll))
	if lat.length() < 1e-3:
		lat = Vector3.RIGHT
	return [lat.normalized(), up]


## Корень куклы: Torso, иначе тело, которое не ребёнок ни одного сустава.
static func _root_body(doll: Node) -> RigidBody3D:
	var p: Variant = doll.get("parts")
	if not p is Dictionary:
		return null
	var t := (p as Dictionary).get("Torso") as RigidBody3D
	if t != null and is_instance_valid(t):
		return t
	var kids := {}
	var pairs: Variant = doll.get("_muscle_pairs")
	if pairs is Array:
		for e: Array in pairs:
			kids[e[1]] = true
	for b in (p as Dictionary).values():
		if b is RigidBody3D and is_instance_valid(b) and not kids.has(b):
			return b
	return null


## Отрезок [min, max] проекции формы s (кадр xf в мире) на единичную ось axis. Шар, капсула, цилиндр и коробка — точно, выпуклая —
## по вершинам, прочее — по габариту ModularDoll._shape_half (как пол в ModularDoll._build).
static func _extent(xf: Transform3D, s: Shape3D, axis: Vector3) -> Vector2:
	var c := axis.dot(xf.origin)
	var e := 0.0
	if s is SphereShape3D:
		e = (s as SphereShape3D).radius
	elif s is CapsuleShape3D:
		var cp := s as CapsuleShape3D
		e = absf(axis.dot(xf.basis.y.normalized())) * maxf(cp.height * 0.5 - cp.radius, 0.0) + cp.radius
	elif s is CylinderShape3D:
		var cy := s as CylinderShape3D
		var u := absf(axis.dot(xf.basis.y.normalized()))
		e = u * cy.height * 0.5 + cy.radius * sqrt(maxf(1.0 - u * u, 0.0))
	elif s is ConvexPolygonShape3D and not (s as ConvexPolygonShape3D).points.is_empty():
		var lo := INF
		var hi := -INF
		for p in (s as ConvexPolygonShape3D).points:
			var d := axis.dot(xf * p)
			lo = minf(lo, d)
			hi = maxf(hi, d)
		return Vector2(lo, hi)
	else:
		var h := ModularDoll._shape_half(s)
		e = absf(axis.dot(xf.basis.x)) * h.x + absf(axis.dot(xf.basis.y)) * h.y + absf(axis.dot(xf.basis.z)) * h.z
	return Vector2(c - e, c + e)


static func _tip_of(c: Vector3, sup: Dictionary, lat: Vector3, up: Vector3) -> Dictionary:
	var mn := float(sup["min_x"])
	var mx := float(sup["max_x"])
	var half := (mx - mn) * 0.5
	var off := c.dot(lat) - (mn + mx) * 0.5
	var margin := half - absf(off)
	var dir := clampf(off / maxf(half, MIN_HALF_SPAN), -1.0, 1.0)
	if margin < 0.0:
		dir = signf(off)
	return {"dir": dir, "margin": margin, "height": c.dot(up) - float(sup["floor_y"])}


# --- внутреннее: рисование (пиксели экрана 1920×1080 × k) ---

static func _a(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * alpha * _fade)


static func _line(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float) -> void:
	ci.draw_line(a, b, _a(COL_SHADOW, 1.0), w + 2.0, true)
	ci.draw_line(a, b, col, w, true)


static func _dashed(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float, dash: float) -> void:
	if a.distance_to(b) < 1.0:
		return
	ci.draw_dashed_line(a, b, _a(COL_SHADOW, 0.7), w + 1.6, dash, true, true)
	ci.draw_dashed_line(a, b, col, w, dash, true, true)


## Мягкое пятно массы: тёмная тень чуть шире (видно на светлом дереве) и бело-голубые вложенные круги — к центру плотнее, край
## растворяется, в центре точка. Без обводки: иначе пятна читаются как мыльные пузыри, а не как «здесь тяжело».
static func _soft_disc(ci: CanvasItem, p: Vector2, r: float) -> void:
	ci.draw_circle(p, r * 1.1, _a(COL_SHADOW, 0.2), true, -1.0, true)
	ci.draw_circle(p, r * 0.85, _a(COL_SHADOW, 0.12), true, -1.0, true)
	for i in 5:
		ci.draw_circle(p, r * (1.0 - 0.17 * i), _a(COL_MASS, 0.085), true, -1.0, true)
	ci.draw_circle(p, maxf(r * 0.1, 1.4), _a(COL_MASS, 0.6), true, -1.0, true)


## Точка нагрузки: маленькая, у лёгких суставов тусклее и мельче (зелёная кукла не рябит), у красных — тонкое расходящееся кольцо.
static func _stress_dot(ci: CanvasItem, p: Vector2, v: float, t: float, k: float) -> void:
	var col := load_colour(v)
	var r := lerpf(2.8, 5.2, clampf(v, 0.0, 1.0)) * k
	var alpha := lerpf(0.55, 1.0, clampf(v / LOAD_WARN, 0.0, 1.0))
	ci.draw_circle(p, r + 1.6 * k, _a(COL_SHADOW, alpha), true, -1.0, true)
	ci.draw_circle(p, r, _a(col, alpha), true, -1.0, true)
	if v > LOAD_HIGH:
		var ph := fposmod(t * 1.1, 1.0)
		ci.draw_arc(p, r + (2.0 + 11.0 * ph) * k, 0.0, TAU, 28, _a(col, 0.85 * (1.0 - ph)), 1.4 * k, true)


## Болтающийся сустав: полое бело-голубое колечко и короткая дуга-маятник под ним (качается со временем) — «так задумано», не ошибка.
static func _free_mark(ci: CanvasItem, p: Vector2, down: Vector2, t: float, k: float) -> void:
	var r := 4.2 * k
	var base := down.angle()
	var sway := 0.35 * sin(t * 2.4)
	var rr := 14.0 * k
	# размах маятника — бледная дуга, нить и грузик — ярче: «висит и качается»
	ci.draw_arc(p, rr, base - 0.55, base + 0.55, 14, _a(COL_SHADOW, 0.6), 2.6 * k, true)
	ci.draw_arc(p, rr, base - 0.55, base + 0.55, 14, _a(COL_NEUTRAL, 0.45), 1.0 * k, true)
	var dir := Vector2.from_angle(base + sway)
	var bob := p + dir * rr
	ci.draw_line(p + dir * r, bob, _a(COL_SHADOW, 0.9), 3.0 * k, true)
	ci.draw_line(p + dir * r, bob, _a(COL_NEUTRAL, 0.9), 1.2 * k, true)
	ci.draw_circle(bob, 3.4 * k, _a(COL_SHADOW, 0.9), true, -1.0, true)
	ci.draw_circle(bob, 2.4 * k, _a(COL_NEUTRAL, 1.0), true, -1.0, true)
	ci.draw_arc(p, r, 0.0, TAU, 20, _a(COL_SHADOW, 1.0), 3.4 * k, true)
	ci.draw_arc(p, r, 0.0, TAU, 20, _a(COL_NEUTRAL, 0.95), 1.5 * k, true)


## Центр масс: маленькая янтарная точка со светлым ядром и мягким ореолом (ореол чуть дышит) — физический маркер, не перекрестие.
static func _com_mark(ci: CanvasItem, p: Vector2, t: float, k: float) -> void:
	var breathe := 1.0 + 0.08 * sin(t * 2.2)
	ci.draw_circle(p, 17.0 * k * breathe, _a(COL_AMBER, 0.06), true, -1.0, true)
	ci.draw_circle(p, 12.0 * k * breathe, _a(COL_AMBER, 0.10), true, -1.0, true)
	ci.draw_circle(p, 8.0 * k, _a(COL_AMBER, 0.20), true, -1.0, true)
	ci.draw_circle(p, 5.6 * k, _a(COL_SHADOW, 0.95), true, -1.0, true)
	ci.draw_circle(p, 4.3 * k, _a(COL_AMBER, 1.0), true, -1.0, true)
	ci.draw_circle(p + Vector2(-0.9, -0.9) * k, 1.7 * k, _a(COL_AMBER_HOT, 1.0), true, -1.0, true)


## Изогнутая стрелка крена у центра масс: дуга сверху в сторону крена (по часовой — вправо), длиннее при сильном крене; жёлтая —
## клонит, красная — центр масс за опорой.
## Возвращает конец стрелки (для бирки).
static func _tip_arrow(ci: CanvasItem, p: Vector2, sgn: float, amount: float, inside: bool, t: float, k: float) -> Vector2:
	var col := COL_WARN if inside else COL_BAD
	var r := 32.0 * k
	var sweep := lerpf(0.6, 1.25, clampf((amount - TIP_ARROW_MIN) / (1.0 - TIP_ARROW_MIN), 0.0, 1.0)) * (0.9 + 0.1 * sin(t * 3.0))
	var a0 := -PI * 0.5 - sgn * 0.3
	var a1 := a0 + sgn * sweep
	ci.draw_arc(p, r, minf(a0, a1), maxf(a0, a1), 24, _a(COL_SHADOW, 1.0), 5.0 * k, true)
	ci.draw_arc(p, r, minf(a0, a1), maxf(a0, a1), 24, _a(col, 0.95), 2.6 * k, true)
	var tip_p := p + Vector2.from_angle(a1) * r
	var tangent := Vector2.from_angle(a1 + sgn * PI * 0.5)
	var nrm := Vector2(-tangent.y, tangent.x)
	var head := PackedVector2Array([tip_p + tangent * 8.0 * k, tip_p - tangent * 2.0 * k + nrm * 5.5 * k,
		tip_p - tangent * 2.0 * k - nrm * 5.5 * k])
	var shadow := PackedVector2Array([tip_p + tangent * 10.5 * k, tip_p - tangent * 3.5 * k + nrm * 7.5 * k,
		tip_p - tangent * 3.5 * k - nrm * 7.5 * k])
	ci.draw_colored_polygon(shadow, _a(COL_SHADOW, 1.0))
	ci.draw_colored_polygon(head, _a(col, 0.95))
	return tip_p + tangent * 8.0 * k


## Призрак центра масс с тащимой деталью: тонкий пунктир от текущего центра, наконечник, полая бело-голубая точка.
static func _ghost_mark(ci: CanvasItem, from: Vector2, to: Vector2, k: float) -> void:
	var r := 5.2 * k
	var d := to - from
	if d.length() > r + 6.0 * k:
		var u := d.normalized()
		var end := to - u * (r + 2.0 * k)
		_dashed(ci, from + u * 6.0 * k, end, _a(COL_NEUTRAL, 0.85), 1.2 * k, 3.0 * k)
		var nrm := Vector2(-u.y, u.x)
		ci.draw_colored_polygon(PackedVector2Array([end, end - u * 5.0 * k + nrm * 3.0 * k, end - u * 5.0 * k - nrm * 3.0 * k]),
			_a(COL_NEUTRAL, 0.9))
	ci.draw_arc(to, r, 0.0, TAU, 24, _a(COL_SHADOW, 1.0), 3.6 * k, true)
	ci.draw_arc(to, r, 0.0, TAU, 24, _a(COL_NEUTRAL, 1.0), 1.6 * k, true)


## Бумажная бирка: кремовая плашка, тёмные чернила, слева полоска цвета смысла (янтарь, жёлтый, красный, бело-голубой).
static func _tag(ci: CanvasItem, font: Font, rect: Rect2, text: String, col: Color, k: float) -> void:
	if font == null or text == "":
		return
	var fs := maxi(int(round(LABEL_SIZE * k)), 9)
	var pad := Vector2(5.0, 2.0) * k
	var stripe := 3.0 * k
	if _paper_box == null:
		_paper_box = StyleBoxFlat.new()
		_paper_box.set_corner_radius_all(3)
		_paper_box.shadow_size = 2
		_paper_box.shadow_offset = Vector2(0, 1)
	_paper_box.bg_color = _a(COL_PAPER, 1.0)
	_paper_box.shadow_color = _a(Color(0, 0, 0, 0.35), 1.0)
	ci.draw_style_box(_paper_box, rect)
	ci.draw_rect(Rect2(rect.position + Vector2(1.0, 1.0) * k, Vector2(stripe, rect.size.y - 2.0 * k)), _a(col.darkened(0.12), 1.0))
	ci.draw_string(font, Vector2(rect.position.x + stripe + pad.x, rect.position.y + pad.y + font.get_ascent(fs)), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _a(COL_INK, 1.0))


## Прямоугольник бирки: pos — левый край, середина по высоте.
static func _tag_rect(font: Font, pos: Vector2, text: String, k: float) -> Rect2:
	var fs := maxi(int(round(LABEL_SIZE * k)), 9)
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs) if font != null else Vector2.ZERO
	var pad := Vector2(5.0, 2.0) * k
	return Rect2(pos - Vector2(0, sz.y * 0.5 + pad.y), Vector2(sz.x + pad.x * 2.0 + 3.0 * k, sz.y + pad.y * 2.0))


## Место бирки без наложения на уже поставленные: сдвиг на строку вниз, вверх, на две…; всё занято — как было.
static func _free_spot(r: Rect2, placed: Array, k: float) -> Rect2:
	var step := r.size.y + 2.0 * k
	for off in [0.0, 1.0, -1.0, 2.0, -2.0, 3.0]:
		var c := Rect2(r.position + Vector2(0.0, step * float(off)), r.size)
		var hit := false
		for q: Rect2 in placed:
			if c.grow(1.0 * k).intersects(q):
				hit = true
				break
		if not hit:
			return c
	return r
