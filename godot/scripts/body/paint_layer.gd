## Воксельный слой краски детали (docs/plan-demo/BODY_PAINT.md §2): сетка RGBA8 поверх габарита меша детали — AABB в локальных
## координатах корня меша (узел Mesh, у слитой детали Mesh_<uid>, BodyPaint.mesh_root_of). Рисует его
## assets/materials/kit/paint_overlay.gdshader — next_pass поверхностей детали (BodyPaint.attach_layer): позиция вершины → кадр слоя
## (to_layer) → выборка 3D-текстуры по нормализованной позиции. Покраска косметическая: физику не трогает.
##
## Хранение:
##   • ячейки кубические, ребро = max(самая длинная ось / MAX_CELLS, MIN_CELL) — 8–14 мм у деталей кита; по каждой оси ≥ MIN_CELLS;
##     габарит слоя — габарит меша, округлённый вверх до целых ячеек вокруг его центра; всего ≤ MAX_TOTAL (64 000) ячеек, 256 КБ;
##   • data — RGBA8, порядок x → y → z (срез z — картинка res.x × res.y, как слои ImageTexture3D). RGB ПРЕДУМНОЖЕН на A: линейная
##     фильтрация текстуры на краю мазка не тянет чёрный из пустых ячеек (пустая ячейка — нули), шейдер делит rgb / a;
##     пустой слой — все байты 0;
##   • сейв (to_dict) — data в zstd + исходный размер: пустой слой весит ≈ 30 байт.
##
## Кисти (всё — «поверх»: входящая краска с альфой a_in = поток × спад кладётся на старую, доля нового цвета = a_in / новая альфа):
##   • stamp — мягкий шар, альфа копится к 1; spray — баллончик: мягкое ядро (туман, SPRAY_CORE радиуса) + dots пятнышек со
##     случайным центром (гаусс к середине) — у края «напыление», альфа копится к opacity (нажим), детерминировано rng;
##     кисть меняет только ячейки, чьи центры в радиусе: кисть мельче ячейки может не задеть ни одного центра — мастерская не даёт
##     радиус меньше 0.9 ячейки (WorkshopPaint._dab);
##   • erase — альфа (и предумноженный цвет) × (1 − strength × спад), ячейка с заметной силой стирания теряет хотя бы 1/255 за вызов
##     (округление иначе застревало бы на 1–11/255 — слой никогда не пустел); fill — вся деталь; clear — пусто;
##   • цвет кистей и раскрасок зажат в 0..1 (ColorPicker с «яркостью» даёт компоненты > 1: байт иначе переполнялся бы);
##   • pattern — раскраски stripes, camo, flames, dots, gradient, graffiti, детерминированы seed (координаты — метры в кадре корня
##     меша: полосы и горошек одного размера на всех деталях; для всей куклы мастерская даёт каждой детали свой seed); mirror_x —
##     тот же рисунок, отражённый по X кадра слоя (правая деталь старой куклы: корень меша Mesh_R не зеркальный, BODY_PAINT §6.1);
##     частями — pattern_begin / pattern_run (срезы z до бюджета времени: мастерская не держит кадр на 40–80 мс).
## Живая текстура: make_texture() один раз, update_texture(tex) после штриха — пересобираются только грязные срезы z
## (у ImageTexture3D нет частичной загрузки: сам upload — вся текстура, ≤ 256 КБ).
class_name PaintLayer
extends RefCounted

const VERSION := 1
const MAX_CELLS := 40
const MIN_CELLS := 4
const MAX_TOTAL := 64000
## Ребро ячейки не мельче (м): у маленьких деталей (кисть, стопа) баллончик 10 см иначе красил бы 40³ ячеек за кадр.
const MIN_CELL := 0.008
const KINDS := ["stripes", "camo", "flames", "dots", "gradient", "graffiti"]
## Жёсткость ластика: до половины радиуса стирает полностью, дальше — мягкий край.
const ERASE_HARDNESS := 0.6
## Ластик: сила (после спада), с которой ячейка теряет хотя бы 1/255 за вызов; слабее — мягкий край, округление как есть.
const ERASE_MIN_STEP := 0.02
## Баллончик: туман — мягкий шар SPRAY_CORE × радиуса с потоком SPRAY_MIST за вызов (≈ 20 кадров на месте — почти плотно),
## точки — радиус SPRAY_DOT × радиуса (не меньше ячейки), поток SPRAY_DOT_FLOW, центры — гаусс σ = SPRAY_SIGMA радиуса.
const SPRAY_CORE := 0.7
const SPRAY_MIST := 0.12
const SPRAY_DOT := 0.2
const SPRAY_DOT_FLOW := Vector2(0.3, 0.7)
const SPRAY_SIGMA := 0.45
## Камуфляж: насколько меняется шум за 1 см (полоса смешения цветов у порога ≈ ячейка).
const CAMO_EDGE := 0.06
const ZSTD_MAGIC := [0x28, 0xB5, 0x2F, 0xFD]

var res := Vector3i(MIN_CELLS, MIN_CELLS, MIN_CELLS)
var aabb := AABB(Vector3.ZERO, Vector3.ONE * MIN_CELL * MIN_CELLS)
var data := PackedByteArray()   # res.x × res.y × res.z × 4, x → y → z, RGB предумножен на A

var _cell := Vector3.ONE * MIN_CELL   # ребро ячейки по осям (м)
var _inv := Vector3.ONE / MIN_CELL
var _dz0 := 0                          # грязные срезы z [_dz0, _dz1] для update_texture (_dz1 < _dz0 — чисто)
var _dz1 := -1
var _slices: Array[Image] = []         # срезы для ImageTexture3D (переиспользуются между update_texture)


## Пустой слой поверх габарита box (локальные координаты корня меша детали). max_cells — ячеек по самой длинной оси (≤ MAX_CELLS).
static func for_aabb(box: AABB, max_cells := MAX_CELLS) -> PaintLayer:
	var a := box.abs()
	var size := a.size
	var mc := clampi(max_cells, MIN_CELLS, MAX_CELLS)
	var cell := cell_for_aabb(a, mc)
	var r := Vector3i.ZERO
	for i in 3:
		r[i] = clampi(ceili(size[i] / cell - 1e-4), MIN_CELLS, mc)
	var s := Vector3(r) * cell
	var l := PaintLayer.new()
	l.res = r
	l.aabb = AABB(a.get_center() - s * 0.5, s)
	l.data.resize(r.x * r.y * r.z * 4)
	l.data.fill(0)
	l._setup()
	return l


## Ребро ячейки слоя for_aabb(box) (м) — без самого слоя (кольцо кисти мастерской над деталью, у которой слоя ещё нет).
static func cell_for_aabb(box: AABB, max_cells := MAX_CELLS) -> float:
	var s := box.abs().size
	var mc := clampi(max_cells, MIN_CELLS, MAX_CELLS)
	return maxf(maxf(s.x, maxf(s.y, s.z)) / float(mc), MIN_CELL)


## Пустой слой той же сетки (res, aabb) — черновик раскраски: рисунок готовится частями и ложится в живой слой целиком.
func blank_like() -> PaintLayer:
	var l := PaintLayer.new()
	l.res = res
	l.aabb = aabb
	l.data.resize(res.x * res.y * res.z * 4)
	l.data.fill(0)
	l._setup()
	return l


## Ребро ячейки (м).
func cell_size() -> float:
	return _cell.x


func cell_count() -> int:
	return res.x * res.y * res.z


## Центр ячейки (x, y, z) в кадре слоя.
func cell_center(x: int, y: int, z: int) -> Vector3:
	return aabb.position + (Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5)) * _cell


## Цвет ячейки (не предумноженный; пустая — Color(0, 0, 0, 0)).
func cell_color(x: int, y: int, z: int) -> Color:
	var i := ((z * res.y + y) * res.x + x) * 4
	var a := float(data[i + 3])
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	return Color(data[i] / a, data[i + 1] / a, data[i + 2] / a, a / 255.0)


# --- кисти ---

## Баллончик в точке p (кадр слоя): мягкое ядро + dots пятнышек в круге radius (м). Альфа копится к opacity (нажим 0..1), цвет
## смешивается к color по доле новой краски; hardness 0..1 — жёсткость края ядра и пятнышек; mist — поток ядра за вызов (мастерская
## кладёт один мазок за два: 1 − (1 − SPRAY_MIST)²). Детерминирован состоянием rng.
func spray(p: Vector3, radius: float, color: Color, opacity: float, hardness: float, rng: RandomNumberGenerator, dots := 24,
		mist := SPRAY_MIST) -> void:
	if radius <= 0.0 or opacity <= 0.0:
		return
	var cap := clampf(opacity, 0.0, 1.0)
	_deposit(p, radius * SPRAY_CORE, color, mist, hardness, cap)
	if rng == null or dots <= 0:
		return
	var rd := minf(maxf(radius * SPRAY_DOT, _cell.x * 0.9), radius)
	var reach := maxf(radius - rd, 0.0)   # пятнышко целиком в круге: краска не выходит за radius
	for n in dots:
		var o := Vector3(rng.randfn(0.0, SPRAY_SIGMA), rng.randfn(0.0, SPRAY_SIGMA), rng.randfn(0.0, SPRAY_SIGMA))
		var l := o.length()
		if l > 1.0:
			o *= rng.randf() / l   # хвост гаусса — внутрь круга
		_deposit(p + o * reach, rd, color, rng.randf_range(SPRAY_DOT_FLOW.x, SPRAY_DOT_FLOW.y), hardness, cap)


## Мягкий шар: альфа копится к 1 (strength — поток за вызов 0..1), hardness — доля радиуса без спада.
func stamp(p: Vector3, radius: float, color: Color, strength: float, hardness: float) -> void:
	_deposit(p, radius, color, strength, hardness, 1.0)


## Ластик: альфа и цвет × (1 − strength × спад), спад с жёсткостью ERASE_HARDNESS. strength 1 в центре — ноль. Где сила после спада
## ≥ ERASE_MIN_STEP, альфа падает хотя бы на 1/255 (иначе round(a·(1 − w)) застревал бы: ластик 0.45 держал 1/255, нажим 0.1 —
## 11/255, слой не пустел, ключ paint оставался в чертеже); rgb не выше новой альфы, альфа 0 — вся ячейка 0.
func erase(p: Vector3, radius: float, strength: float) -> void:
	if radius <= 0.0 or strength <= 0.0:
		return
	var b := _ball_box(p, radius)
	if b.is_empty():
		return
	var st := clampf(strength, 0.0, 1.0)
	var h := ERASE_HARDNESS
	var soft := 1.0 - h
	var inv_r := 1.0 / radius
	var r2 := radius * radius
	var sx := _cell.x
	var ox := aabb.position.x + 0.5 * _cell.x
	var oy := aabb.position.y + 0.5 * _cell.y
	var oz := aabb.position.z + 0.5 * _cell.z
	for z in range(b[4], b[5] + 1):
		var dz := oz + z * _cell.z - p.z
		var dz2 := dz * dz
		for y in range(b[2], b[3] + 1):
			var dy := oy + y * _cell.y - p.y
			var dyz := dy * dy + dz2
			if dyz >= r2:
				continue
			var hx := sqrt(r2 - dyz)
			var xa := maxi(ceili((p.x - hx - ox) / sx), b[0])
			var xb := mini(floori((p.x + hx - ox) / sx), b[1])
			var i := ((z * res.y + y) * res.x + xa) * 4
			for x in range(xa, xb + 1):
				var a0 := data[i + 3]
				if a0 != 0:
					var dx := ox + x * sx - p.x
					var d := sqrt(dx * dx + dyz) * inv_r
					var w := st
					if d > h:
						var t := minf((d - h) / soft, 1.0)
						w = st * (1.0 - t * t * (3.0 - 2.0 * t))
					var k := 1.0 - w
					var na := int(a0 * k + 0.5)
					if na == a0 and w >= ERASE_MIN_STEP:
						na = a0 - 1
					if na <= 0:
						data[i] = 0
						data[i + 1] = 0
						data[i + 2] = 0
						data[i + 3] = 0
					else:
						data[i] = mini(int(data[i] * k + 0.5), na)
						data[i + 1] = mini(int(data[i + 1] * k + 0.5), na)
						data[i + 2] = mini(int(data[i + 2] * k + 0.5), na)
						data[i + 3] = na
				i += 4
	_mark(b[4], b[5])


## Вся деталь в цвет: поверх, альфа strength (1 — сплошная заливка, старое закрыто).
func fill(color: Color, strength := 1.0) -> void:
	var s := clampf(strength, 0.0, 1.0)
	if s <= 0.0:
		return
	var c := _clamp01(color)   # r > 1 дал бы rgb > a (предумножение сломано: шейдер делит rgb / a)
	if s >= 1.0 or is_empty():
		# однородный результат — заливка картинкой (натив), без цикла по ячейкам
		var img := Image.create_empty(res.x, res.y * res.z, false, Image.FORMAT_RGBA8)
		img.fill(Color(c.r * s, c.g * s, c.b * s, s))
		data = img.get_data()
	else:
		var cr := c.r * 255.0
		var cg := c.g * 255.0
		var cb := c.b * 255.0
		for i in range(0, data.size(), 4):
			_over(i, cr, cg, cb, s, 255.0)
	_mark(0, res.z - 1)


## Стереть всё.
func clear() -> void:
	data.fill(0)
	_mark(0, res.z - 1)


## Раскраска всей детали поверх старой краски: kind из KINDS, colors — Array[Color] (пустой — палитра вида), pattern_seed — seed
## (одинаковый seed — одинаковый результат), axis — ось полос / пламени / градиента в кадре слоя (снизу вверх).
##   stripes — полосы поперёк оси (1 цвет — через одну прозрачные); camo — 2–3 цвета пятнами шума (1 цвет — он, темнее, светлее);
##   flames — языки пламени от низа по оси, цвет от основания (colors[0]) к кончикам (последний); dots — горошек (1 цвет — только
##   горошины, ≥ 2 — фон colors[0] и горошины остальных); gradient — по оси (1 цвет — от сплошного к прозрачному); graffiti — тег
##   из случайных штрихов на ЛИЦЕВОЙ половине детали (+Z куклы, проекция по Z; colors[0] — заливка, colors[1] — обводка), с потёками.
## mirror_x — рисунок, отражённый по X кадра слоя: то, что тот же seed нарисовал бы на слое с габаритом, отражённым по X, в точке
## (−x, y, z) (ось axis — в кадре этого слоя). Так правая деталь старой куклы (Mesh_R: корень меша не зеркальный, геометрия —
## зеркальная) получает зеркальную пару рисунка левой; у деталей кита корень правой уже зеркальный — им mirror_x не нужен.
func pattern(kind: String, colors: Array, pattern_seed: int, axis := Vector3.UP, mirror_x := false) -> void:
	var job := pattern_begin(kind, colors, pattern_seed, axis, mirror_x)
	if job.is_empty():
		return
	pattern_run(job, 0)
	_mark(0, res.z - 1)


## Раскраска частями: подготовка (все выборки rng и шума — здесь, рисунок байт в байт как у pattern). {} — неизвестный вид
## (предупреждение). Рисует pattern_run.
func pattern_begin(kind: String, colors: Array, pattern_seed: int, axis := Vector3.UP, mirror_x := false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = pattern_seed
	var ax := axis
	if mirror_x:
		ax.x = -ax.x
	var n := ax.normalized() if ax.length() > 1e-6 else Vector3.UP
	var cols := _colors(colors)
	var box := aabb
	if mirror_x:
		aabb = AABB(Vector3(-(box.position.x + box.size.x), box.position.y, box.position.z), box.size)
	var p := {}
	var z0 := 0
	match kind:
		"stripes":
			p = _prep_stripes(cols if not cols.is_empty() else [Color(0.95, 0.94, 0.88), Color(0.82, 0.14, 0.1)], rng, n)
		"camo":
			p = _prep_camo(cols, rng, pattern_seed)
		"flames":
			p = _prep_flames(cols, rng, n, pattern_seed)
		"dots":
			p = _prep_dots(cols if not cols.is_empty() else [Color(0.96, 0.95, 0.9)], rng)
		"gradient":
			p = _prep_gradient(cols if not cols.is_empty() else [Color(1.0, 0.36, 0.1), Color(1.0, 0.86, 0.22)], n)
		"graffiti":
			p = _prep_graffiti(cols if not cols.is_empty() else [Color(1.0, 0.27, 0.62), Color(0.07, 0.07, 0.09)], rng)
			z0 = res.z >> 1
		_:
			aabb = box
			push_warning("PaintLayer.pattern: неизвестный вид «%s» (есть: %s)" % [kind, ", ".join(KINDS)])
			return {}
	p["px"] = _axis_centres(0)
	p["py"] = _axis_centres(1)
	p["pz"] = _axis_centres(2)
	aabb = box
	return {"kind": kind, "p": p, "z": z0, "mirror": mirror_x}


## Рисовать срезы z задачи pattern_begin по порядку, пока не выйдет max_usec (0 — до конца); true — рисунок готов. Срез — целиком:
## результат не зависит от того, на сколько кадров разбит. Грязные срезы помечаются (update_texture).
func pattern_run(job: Dictionary, max_usec := 0) -> bool:
	if job.is_empty():
		return true
	var t0 := Time.get_ticks_usec()
	var p: Dictionary = job["p"]
	var kind := String(job["kind"])
	var mirror := bool(job["mirror"])
	var d := data
	while int(job["z"]) < res.z:
		var z := int(job["z"])
		# отражение: срез переворачивается по x до и после рисунка — старая краска остаётся на месте (перестановка ячеек и
		# «поверх» по ячейке перестановочны), рисунок ложится отражённым
		if mirror:
			_flip_x(d, z)
		match kind:
			"stripes":
				_slab_stripes(d, p, z)
			"camo":
				_slab_camo(d, p, z)
			"flames":
				_slab_flames(d, p, z)
			"dots":
				_slab_dots(d, p, z)
			"gradient":
				_slab_gradient(d, p, z)
			"graffiti":
				_slab_graffiti(d, p, z)
		if mirror:
			_flip_x(d, z)
		job["z"] = z + 1
		_mark(z, z)
		if max_usec > 0 and Time.get_ticks_usec() - t0 >= max_usec:
			break
	data = d
	return int(job["z"]) >= res.z


## Цвет краски в точке p (кадр слоя) — трилинейно, как шейдер (предумноженный rgb и альфа по отдельности, потом rgb / a).
## Пусто — Color(0, 0, 0, 0). Пипетка мастерской.
func sample(p: Vector3) -> Color:
	var g := (p - aabb.position) * _inv - Vector3(0.5, 0.5, 0.5)
	var xs := _lerp_axis(g.x, res.x)
	var ys := _lerp_axis(g.y, res.y)
	var zs := _lerp_axis(g.z, res.z)
	var acc := Vector4.ZERO
	for cz in 2:
		var wz: float = zs[2] if cz == 1 else 1.0 - zs[2]
		if wz <= 0.0:
			continue
		for cy in 2:
			var wy: float = ys[2] if cy == 1 else 1.0 - ys[2]
			if wy <= 0.0:
				continue
			for cx in 2:
				var wx: float = xs[2] if cx == 1 else 1.0 - xs[2]
				if wx <= 0.0:
					continue
				var i := ((int(zs[cz]) * res.y + int(ys[cy])) * res.x + int(xs[cx])) * 4
				var w := wx * wy * wz
				acc += Vector4(data[i], data[i + 1], data[i + 2], data[i + 3]) * w
	if acc.w <= 0.0:
		return Color(0, 0, 0, 0)
	return Color(acc.x / acc.w, acc.y / acc.w, acc.z / acc.w, acc.w / 255.0)


func is_empty() -> bool:
	return data.is_empty() or data.count(0) == data.size()


# --- сейв ---

## {"v": 1, "res": Vector3i, "aabb": AABB, "data": PackedByteArray (zstd), "size": int (байт без сжатия)}.
func to_dict() -> Dictionary:
	return {"v": VERSION, "res": res, "aabb": aabb, "data": data.compress(FileAccess.COMPRESSION_ZSTD), "size": data.size()}


## Слой из to_dict(); null — если данные битые (версия, размеры, сжатие): кукла тогда собирается без этой краски (§4). Размеры —
## те, что даёт for_aabb: MIN_CELLS..MAX_CELLS ячеек по каждой оси, ячейка ≥ MIN_CELL / 2.
static func from_dict(d: Variant) -> PaintLayer:
	if not d is Dictionary:
		return null
	var dd: Dictionary = d
	var vv: Variant = dd.get("v")
	if not (vv is int or vv is float) or int(vv) != VERSION:
		return null
	var rv: Variant = dd.get("res")
	var r: Vector3i
	if rv is Vector3i:
		r = rv
	elif rv is Vector3:
		r = Vector3i(rv)
	else:
		return null
	# по каждой оси — как for_aabb (MIN_CELLS..MAX_CELLS): 3D-текстура 64000 × 1 × 1 не создаётся (предел Metal — 2048 по оси)
	for i in 3:
		if r[i] < MIN_CELLS or r[i] > MAX_CELLS:
			return null
	var cells := r.x * r.y * r.z
	if cells > MAX_TOTAL:
		return null
	var bv: Variant = dd.get("aabb")
	if not bv is AABB:
		return null
	var box: AABB = bv
	if not (box.size.x > 0.0 and box.size.y > 0.0 and box.size.z > 0.0) or not box.position.is_finite() or not box.size.is_finite():
		return null
	# ячейка не мельче половины MIN_CELL (for_aabb даёт ≥ MIN_CELL): вырожденный габарит — кисти молча ничего не красили бы
	for i in 3:
		if box.size[i] / float(r[i]) < MIN_CELL * 0.5:
			return null
	var sv: Variant = dd.get("size")
	if not (sv is int or sv is float) or int(sv) != cells * 4:
		return null
	var zv: Variant = dd.get("data")
	if not zv is PackedByteArray:
		return null
	var z: PackedByteArray = zv
	if z.size() < 4:
		return null
	for k in 4:
		if z[k] != ZSTD_MAGIC[k]:
			return null
	var raw := z.decompress(cells * 4, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != cells * 4:
		return null
	var l := PaintLayer.new()
	l.res = r
	l.aabb = box
	l.data = raw
	l._setup()
	return l


# --- текстура ---

## 3D-текстура слоя (RGBA8, без мипмапов): paint_tex шейдера краски.
func make_texture() -> ImageTexture3D:
	_rebuild_slices(0, res.z - 1)
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGBA8, res.x, res.y, res.z, false, _slices)
	_dz0 = res.z
	_dz1 = -1
	return tex


## Залить изменения в tex (make_texture этого слоя): срезы z пересобираются только грязные; ничего не менялось — ничего не шлёт.
## Текстура другого размера пересоздаётся целиком.
func update_texture(tex: ImageTexture3D) -> void:
	if tex == null:
		return
	var same := tex.get_width() == res.x and tex.get_height() == res.y and tex.get_depth() == res.z \
		and tex.get_format() == Image.FORMAT_RGBA8
	if _slices.size() != res.z:
		_rebuild_slices(0, res.z - 1)
	elif _dz1 >= _dz0:
		_rebuild_slices(_dz0, _dz1)
	elif same:
		return
	if same:
		tex.update(_slices)
	else:
		tex.create(Image.FORMAT_RGBA8, res.x, res.y, res.z, false, _slices)
	_dz0 = res.z
	_dz1 = -1


## Грязные срезы z [от, до] (до < от — чисто) — для проб.
func dirty_range() -> Vector2i:
	return Vector2i(_dz0, _dz1)


## Все срезы — грязные (после прямой записи в data): следующий update_texture зальёт всё.
func mark_dirty() -> void:
	_mark(0, res.z - 1)


## Заменить ячейки целиком (отмена в живом слое: байты из прежнего to_dict / data). false — размер не тот, слой не тронут.
func set_data(bytes: PackedByteArray) -> bool:
	if bytes.size() != cell_count() * 4:
		return false
	data = bytes.duplicate()
	mark_dirty()
	return true


# --- внутреннее ---

func _setup() -> void:
	_cell = aabb.size / Vector3(res)
	_inv = Vector3(1.0 / _cell.x, 1.0 / _cell.y, 1.0 / _cell.z)
	_slices.clear()
	_dz0 = 0
	_dz1 = res.z - 1


func _mark(z0: int, z1: int) -> void:
	_dz0 = mini(_dz0, z0)
	_dz1 = maxi(_dz1, z1)


func _rebuild_slices(z0: int, z1: int) -> void:
	var n := res.x * res.y * 4
	if _slices.size() != res.z:
		_slices.clear()
		for z in res.z:
			_slices.append(Image.create_from_data(res.x, res.y, false, Image.FORMAT_RGBA8, data.slice(z * n, (z + 1) * n)))
		return
	for z in range(maxi(z0, 0), mini(z1, res.z - 1) + 1):
		_slices[z].set_data(res.x, res.y, false, Image.FORMAT_RGBA8, data.slice(z * n, (z + 1) * n))


## Ячейки, чьи центры могут быть в шаре (p, radius): [x0, x1, y0, y1, z0, z1]; пусто — шар мимо слоя.
func _ball_box(p: Vector3, radius: float) -> PackedInt32Array:
	var g := (p - aabb.position) * _inv - Vector3(0.5, 0.5, 0.5)
	var rc := radius * _inv
	var b := PackedInt32Array([
		maxi(ceili(g.x - rc.x), 0), mini(floori(g.x + rc.x), res.x - 1),
		maxi(ceili(g.y - rc.y), 0), mini(floori(g.y + rc.y), res.y - 1),
		maxi(ceili(g.z - rc.z), 0), mini(floori(g.z + rc.z), res.z - 1)])
	if b[0] > b[1] or b[2] > b[3] or b[4] > b[5]:
		return PackedInt32Array()
	return b


## Краска поверх в шар (p, radius): a_in = flow × спад(d / radius) (hardness — доля радиуса без спада, дальше smoothstep к 0);
## альфа растёт не выше max(старой, cap). Цикл — только по ячейкам шара: строка x — от хорды до хорды.
func _deposit(p: Vector3, radius: float, color: Color, flow: float, hardness: float, cap: float) -> void:
	if radius <= 0.0 or flow <= 0.0:
		return
	var b := _ball_box(p, radius)
	if b.is_empty():
		return
	var fl := clampf(flow, 0.0, 1.0)
	var h := clampf(hardness, 0.0, 1.0)
	var soft := 1.0 - h
	var cr := clampf(color.r, 0.0, 1.0) * 255.0   # > 1 переполнил бы байт (int в PackedByteArray берёт младший байт)
	var cg := clampf(color.g, 0.0, 1.0) * 255.0
	var cb := clampf(color.b, 0.0, 1.0) * 255.0
	var cap255 := clampf(cap, 0.0, 1.0) * 255.0
	var inv_r := 1.0 / radius
	var r2 := radius * radius
	var sx := _cell.x
	var ox := aabb.position.x + 0.5 * _cell.x
	var oy := aabb.position.y + 0.5 * _cell.y
	var oz := aabb.position.z + 0.5 * _cell.z
	for z in range(b[4], b[5] + 1):
		var dz := oz + z * _cell.z - p.z
		var dz2 := dz * dz
		for y in range(b[2], b[3] + 1):
			var dy := oy + y * _cell.y - p.y
			var dyz := dy * dy + dz2
			if dyz >= r2:
				continue
			var hx := sqrt(r2 - dyz)
			var xa := maxi(ceili((p.x - hx - ox) / sx), b[0])
			var xb := mini(floori((p.x + hx - ox) / sx), b[1])
			var i := ((z * res.y + y) * res.x + xa) * 4
			for x in range(xa, xb + 1):
				var w := fl
				if soft > 0.0:
					var dx := ox + x * sx - p.x
					var d := sqrt(dx * dx + dyz) * inv_r
					if d > h:
						var t := minf((d - h) / soft, 1.0)
						w = fl * (1.0 - t * t * (3.0 - 2.0 * t))
				if w > 0.0:
					# _over(i, cr, cg, cb, w, cap255), развёрнуто: горячий цикл баллончика
					var a0 := float(data[i + 3])
					var k := 1.0 - w
					var ar := w * 255.0 + a0 * k
					var am := maxf(a0, cap255)
					var s := 1.0
					if ar > am:
						s = am / ar
						ar = am
					data[i] = int((cr * w + data[i] * k) * s + 0.5)
					data[i + 1] = int((cg * w + data[i + 1] * k) * s + 0.5)
					data[i + 2] = int((cb * w + data[i + 2] * k) * s + 0.5)
					data[i + 3] = int(ar + 0.5)
				i += 4
	_mark(b[4], b[5])


## Ячейка i (байт) ← краска (cr, cg, cb в 0..255, не предумножены) с альфой a поверх; альфа не выше max(старой, cap255).
func _over(i: int, cr: float, cg: float, cb: float, a: float, cap255: float) -> void:
	if a <= 0.0:
		return
	var w := minf(a, 1.0)
	var a0 := float(data[i + 3])
	var k := 1.0 - w
	var ar := w * 255.0 + a0 * k
	var am := maxf(a0, cap255)
	var s := 1.0
	if ar > am:
		s = am / ar
		ar = am
	data[i] = int((cr * w + data[i] * k) * s + 0.5)
	data[i + 1] = int((cg * w + data[i + 1] * k) * s + 0.5)
	data[i + 2] = int((cb * w + data[i + 2] * k) * s + 0.5)
	data[i + 3] = int(ar + 0.5)


func _over_c(i: int, c: Color, a: float) -> void:
	_over(i, clampf(c.r, 0.0, 1.0) * 255.0, clampf(c.g, 0.0, 1.0) * 255.0, clampf(c.b, 0.0, 1.0) * 255.0, a, 255.0)


## Цвет с компонентами, зажатыми в 0..1 (альфа 1).
static func _clamp01(c: Color) -> Color:
	return Color(clampf(c.r, 0.0, 1.0), clampf(c.g, 0.0, 1.0), clampf(c.b, 0.0, 1.0), 1.0)


## Для трилинейной выборки: [индекс0, индекс1, доля к индексу1] по одной оси (края — зажаты).
static func _lerp_axis(g: float, n: int) -> Array:
	var i0 := clampi(floori(g), 0, n - 1)
	var i1 := mini(i0 + 1, n - 1)
	var f := clampf(g - float(i0), 0.0, 1.0)
	if g < 0.0 or i1 == i0:
		f = 0.0
	return [i0, i1, f]


static func _colors(colors: Array) -> Array:
	var out: Array = []
	for c in colors:
		if c is Color:
			out.append(c)
		elif c is String and Color.html_is_valid(c):
			out.append(Color.html(c))
	return out


## Проекции углов габарита на ось n: [min, max].
func _axis_span(n: Vector3) -> Vector2:
	var lo := INF
	var hi := -INF
	for k in 8:
		var t := aabb.get_endpoint(k).dot(n)
		lo = minf(lo, t)
		hi = maxf(hi, t)
	return Vector2(lo, maxf(hi, lo + 1e-4))


## Цвет по градиенту стопов cols (равномерно) в точке f 0..1.
static func _ramp(cols: Array, f: float) -> Color:
	if cols.size() == 1:
		return cols[0]
	var x := clampf(f, 0.0, 1.0) * (cols.size() - 1)
	var i := mini(floori(x), cols.size() - 2)
	return (cols[i] as Color).lerp(cols[i + 1], x - i)


## Центры ячеек по оси ax (0 — x, 1 — y, 2 — z) в кадре слоя — ровно как компонента cell_center (float32): Vector3(px[x], py[y],
## pz[z]) == cell_center(x, y, z) байт в байт, без вызова на ячейку.
func _axis_centres(ax: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(res[ax])
	for k in res[ax]:
		var v := Vector3.ZERO
		v[ax] = k
		out[k] = (aabb.position + (v + Vector3(0.5, 0.5, 0.5)) * _cell)[ax]
	return out


## Срез z массива d — строки задом наперёд по x (ячейка x ↔ res.x − 1 − x).
func _flip_x(d: PackedByteArray, z: int) -> void:
	var nx := res.x
	for y in res.y:
		var a := ((z * res.y + y) * nx) * 4
		var b := a + (nx - 1) * 4
		while a < b:
			for k in 4:
				var t := d[a + k]
				d[a + k] = d[b + k]
				d[b + k] = t
			a += 4
			b -= 4


## Ячейка i массива d ← цвет c (зажат в 0..1) с альфой a поверх — как _over с потолком 255 (горячие циклы раскрасок: сплошная
## ячейка пишется прямо, сюда — края и полупрозрачное).
static func _mix_px(d: PackedByteArray, i: int, c: Color, a: float) -> void:
	if a <= 0.0:
		return
	var w := minf(a, 1.0)
	var a0 := float(d[i + 3])
	var k := 1.0 - w
	var ar := w * 255.0 + a0 * k
	var s := 1.0
	if ar > 255.0:
		s = 255.0 / ar
		ar = 255.0
	d[i] = int((clampf(c.r, 0.0, 1.0) * 255.0 * w + d[i] * k) * s + 0.5)
	d[i + 1] = int((clampf(c.g, 0.0, 1.0) * 255.0 * w + d[i + 1] * k) * s + 0.5)
	d[i + 2] = int((clampf(c.b, 0.0, 1.0) * 255.0 * w + d[i + 2] * k) * s + 0.5)
	d[i + 3] = int(ar + 0.5)


func _prep_stripes(cols: Array, rng: RandomNumberGenerator, n: Vector3) -> Dictionary:
	var bw := rng.randf_range(0.022, 0.036)   # ширина полосы, м
	var ph := rng.randf() * bw * 2.0
	var span := _axis_span(n)
	return {"cols": cols, "n": n, "bw": bw, "ph": ph, "s0": span.x, "cell": _cell.x}


func _slab_stripes(d: PackedByteArray, p: Dictionary, z: int) -> void:
	var px: PackedFloat32Array = p["px"]
	var py: PackedFloat32Array = p["py"]
	var zz: float = (p["pz"] as PackedFloat32Array)[z]
	var cols: Array = p["cols"]
	var n: Vector3 = p["n"]
	var bw: float = p["bw"]
	var ph: float = p["ph"]
	var s0: float = p["s0"]
	var cell: float = p["cell"]
	var nc := cols.size()
	var i := z * res.y * res.x * 4
	for y in res.y:
		var yy := py[y]
		for x in res.x:
			var t := Vector3(px[x], yy, zz).dot(n) - s0 + ph
			var k := floori(t / bw)
			var f := t / bw - k
			# край полосы — доля соседней по расстоянию до границы (полячейки по обе стороны), без «лесенки» ячеек
			var w_next := clampf(0.5 - (1.0 - f) * bw / cell, 0.0, 0.5)
			var w_prev := clampf(0.5 - f * bw / cell, 0.0, 0.5)
			if nc == 1:
				var on := 1.0 if posmod(k, 2) == 0 else 0.0
				var a := on * (1.0 - w_next - w_prev) + (1.0 - on) * (w_next + w_prev)
				if a >= 1.0:
					var c1: Color = cols[0]
					d[i] = int(clampf(c1.r, 0.0, 1.0) * 255.0 + 0.5)
					d[i + 1] = int(clampf(c1.g, 0.0, 1.0) * 255.0 + 0.5)
					d[i + 2] = int(clampf(c1.b, 0.0, 1.0) * 255.0 + 0.5)
					d[i + 3] = 255
				elif a > 0.0:
					_mix_px(d, i, cols[0], a)
			else:
				var c: Color = cols[posmod(k, nc)]
				if w_next > 0.0:
					c = c.lerp(cols[posmod(k + 1, nc)], w_next)
				elif w_prev > 0.0:
					c = c.lerp(cols[posmod(k - 1, nc)], w_prev)
				d[i] = int(clampf(c.r, 0.0, 1.0) * 255.0 + 0.5)
				d[i + 1] = int(clampf(c.g, 0.0, 1.0) * 255.0 + 0.5)
				d[i + 2] = int(clampf(c.b, 0.0, 1.0) * 255.0 + 0.5)
				d[i + 3] = 255
			i += 4


func _prep_camo(cols_in: Array, rng: RandomNumberGenerator, pattern_seed: int) -> Dictionary:
	var cols: Array = cols_in.slice(0, 3)
	if cols.is_empty():
		cols = [Color(0.33, 0.37, 0.2), Color(0.42, 0.31, 0.18), Color(0.14, 0.16, 0.11)]
	elif cols.size() == 1:
		var c: Color = cols[0]
		cols = [c, c.darkened(0.4), c.lightened(0.3)]
	var noise := FastNoiseLite.new()
	noise.seed = pattern_seed
	noise.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	noise.frequency = 9.0              # пятна ≈ 10 см
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 2
	noise.fractal_gain = 0.45
	noise.offset = Vector3(rng.randf(), rng.randf(), rng.randf()) * 50.0
	var th: Array = [0.0] if cols.size() == 2 else [-0.12, 0.12]
	# полоса смешения у порога ≈ одна ячейка (шум меняется ≈ на CAMO_EDGE за 1 см)
	return {"cols": cols, "noise": noise, "th": th, "e": CAMO_EDGE * _cell.x / 0.01}


func _slab_camo(d: PackedByteArray, p: Dictionary, z: int) -> void:
	var px: PackedFloat32Array = p["px"]
	var py: PackedFloat32Array = p["py"]
	var zz: float = (p["pz"] as PackedFloat32Array)[z]
	var cols: Array = p["cols"]
	var noise: FastNoiseLite = p["noise"]
	var th: Array = p["th"]
	var nt := th.size()
	var e: float = p["e"]
	var i := z * res.y * res.x * 4
	for y in res.y:
		var yy := py[y]
		for x in res.x:
			var v := noise.get_noise_3dv(Vector3(px[x], yy, zz))
			var k := 0
			while k < nt and v >= float(th[k]):
				k += 1
			var c: Color = cols[k]
			# край пятна — смешение с соседним цветом по расстоянию до порога (без «лесенки» ячеек)
			if k < nt and float(th[k]) - v < e:
				c = c.lerp(cols[k + 1], 0.5 - (float(th[k]) - v) / e * 0.5)
			elif k > 0 and v - float(th[k - 1]) < e:
				c = c.lerp(cols[k - 1], 0.5 - (v - float(th[k - 1])) / e * 0.5)
			d[i] = int(clampf(c.r, 0.0, 1.0) * 255.0 + 0.5)
			d[i + 1] = int(clampf(c.g, 0.0, 1.0) * 255.0 + 0.5)
			d[i + 2] = int(clampf(c.b, 0.0, 1.0) * 255.0 + 0.5)
			d[i + 3] = 255
			i += 4


func _prep_flames(cols_in: Array, rng: RandomNumberGenerator, n: Vector3, pattern_seed: int) -> Dictionary:
	var cols := cols_in.slice(0, 4)
	if cols.is_empty():
		cols = [Color(1.0, 0.86, 0.22), Color(1.0, 0.45, 0.06), Color(0.82, 0.1, 0.05)]
	elif cols.size() == 1:
		var c: Color = cols[0]
		cols = [c.lightened(0.5), c, c.darkened(0.3)]
	var a1 := n.cross(Vector3.BACK)
	if a1.length() < 0.1:
		a1 = n.cross(Vector3.RIGHT)
	a1 = a1.normalized()
	var a2 := n.cross(a1).normalized()
	var span := _axis_span(n)
	var ext := span.y - span.x
	var k := rng.randi_range(5, 8)          # языков по кругу
	var ph := rng.randf()
	var lean := rng.randf_range(-0.7, 0.7)  # языки заворачиваются к верху
	var base_h := rng.randf_range(0.2, 0.32)
	var tips := PackedFloat32Array()
	for j in k:
		tips.append(rng.randf_range(0.55, 0.93))
	var noise := FastNoiseLite.new()
	noise.seed = pattern_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 16.0
	# edge — одна ячейка в долях высоты: мягкий край
	return {"cols": cols, "n": n, "a1": a1, "a2": a2, "centre": aabb.get_center(), "s0": span.x, "ext": ext, "edge": _cell.x / ext,
		"k": k, "ph": ph, "lean": lean, "base_h": base_h, "tips": tips, "noise": noise}


func _slab_flames(d: PackedByteArray, p: Dictionary, z: int) -> void:
	var px: PackedFloat32Array = p["px"]
	var py: PackedFloat32Array = p["py"]
	var zz: float = (p["pz"] as PackedFloat32Array)[z]
	var cols: Array = p["cols"]
	var n: Vector3 = p["n"]
	var a1: Vector3 = p["a1"]
	var a2: Vector3 = p["a2"]
	var centre: Vector3 = p["centre"]
	var s0: float = p["s0"]
	var ext: float = p["ext"]
	var edge: float = p["edge"]
	var k: int = p["k"]
	var ph: float = p["ph"]
	var lean: float = p["lean"]
	var base_h: float = p["base_h"]
	var tips: PackedFloat32Array = p["tips"]
	var noise: FastNoiseLite = p["noise"]
	var i := z * res.y * res.x * 4
	for y in res.y:
		var yy := py[y]
		for x in res.x:
			var q := Vector3(px[x], yy, zz)
			var u := (q.dot(n) - s0) / ext
			if u > 0.99:
				i += 4
				continue
			var dd := q - centre
			var fk := (atan2(dd.dot(a2), dd.dot(a1)) + PI) / TAU * k + ph + lean * u
			var idx := posmod(floori(fk), k)
			var lp := fk - floorf(fk)
			var shape := pow(1.0 - absf(2.0 * lp - 1.0), 1.6)   # язык: острый кончик, широкое основание
			var hgt := base_h + (tips[idx] - base_h) * shape + 0.05 * noise.get_noise_3dv(q)
			var a := clampf((hgt - u) / edge + 0.5, 0.0, 1.0)
			if a > 0.0:
				_mix_px(d, i, _ramp(cols, u / maxf(hgt, 1e-3)), a)
			i += 4


func _prep_dots(cols: Array, rng: RandomNumberGenerator) -> Dictionary:
	var sp := rng.randf_range(0.04, 0.056)             # шаг решётки (объёмно-центрированная), м
	var rad := sp * rng.randf_range(0.2, 0.27)        # радиус горошины
	var off := Vector3(rng.randf(), rng.randf(), rng.randf()) * sp
	return {"cols": cols, "sp": sp, "rad": rad, "off": off, "cell": _cell.x}


func _slab_dots(d: PackedByteArray, p: Dictionary, z: int) -> void:
	var px: PackedFloat32Array = p["px"]
	var py: PackedFloat32Array = p["py"]
	var zz: float = (p["pz"] as PackedFloat32Array)[z]
	var cols: Array = p["cols"]
	var sp: float = p["sp"]
	var rad: float = p["rad"]
	var off: Vector3 = p["off"]
	var cell: float = p["cell"]
	var bg := cols.size() >= 2
	var nd := maxi(cols.size() - 1, 1)
	var c0: Color = cols[0]
	var i := z * res.y * res.x * 4
	for y in res.y:
		var yy := py[y]
		for x in res.x:
			var g := (Vector3(px[x], yy, zz) - off) / sp
			var p1 := g.round()
			var p2 := g.floor() + Vector3(0.5, 0.5, 0.5)
			var d1 := (g - p1).length()
			var d2 := (g - p2).length()
			var a := clampf((rad - minf(d1, d2) * sp) / cell + 0.5, 0.0, 1.0)
			if bg:
				var lp := p1 if d1 <= d2 else p2
				var key := Vector3i((lp * 2.0).round())
				var h := (key.x * 73856093) ^ (key.y * 19349663) ^ (key.z * 83492791)
				var dc: Color = cols[1 + posmod(h, nd)]
				var c := c0.lerp(dc, a)
				d[i] = int(clampf(c.r, 0.0, 1.0) * 255.0 + 0.5)
				d[i + 1] = int(clampf(c.g, 0.0, 1.0) * 255.0 + 0.5)
				d[i + 2] = int(clampf(c.b, 0.0, 1.0) * 255.0 + 0.5)
				d[i + 3] = 255
			elif a > 0.0:
				_mix_px(d, i, c0, a)
			i += 4


func _prep_gradient(cols: Array, n: Vector3) -> Dictionary:
	var span := _axis_span(n)
	return {"cols": cols, "n": n, "s0": span.x, "ext": span.y - span.x}


func _slab_gradient(d: PackedByteArray, p: Dictionary, z: int) -> void:
	var px: PackedFloat32Array = p["px"]
	var py: PackedFloat32Array = p["py"]
	var zz: float = (p["pz"] as PackedFloat32Array)[z]
	var cols: Array = p["cols"]
	var n: Vector3 = p["n"]
	var s0: float = p["s0"]
	var ext: float = p["ext"]
	var one := cols.size() == 1
	var i := z * res.y * res.x * 4
	for y in res.y:
		var yy := py[y]
		for x in res.x:
			var u := clampf((Vector3(px[x], yy, zz).dot(n) - s0) / ext, 0.0, 1.0)
			if one:
				_mix_px(d, i, cols[0], 1.0 - u)
			else:
				var c := _ramp(cols, u)
				d[i] = int(clampf(c.r, 0.0, 1.0) * 255.0 + 0.5)
				d[i + 1] = int(clampf(c.g, 0.0, 1.0) * 255.0 + 0.5)
				d[i + 2] = int(clampf(c.b, 0.0, 1.0) * 255.0 + 0.5)
				d[i + 3] = 255
			i += 4


## Тег: 2D-холст (x, y кадра слоя) — буквы из случайных точек, сглаженные Catmull-Rom, росчерк снизу, потёки вниз; штрихи
## растеризуются дисками в покрытие холста (здесь, один раз), срезы лицевой половины (z ≥ середины) — _slab_graffiti.
func _prep_graffiti(cols: Array, rng: RandomNumberGenerator) -> Dictionary:
	var nx := res.x
	var ny := res.y
	var fill_cov := PackedFloat32Array()
	fill_cov.resize(nx * ny)
	fill_cov.fill(0.0)
	var line_cov := PackedFloat32Array()
	line_cov.resize(nx * ny)
	line_cov.fill(0.0)
	var c2 := Vector2(aabb.get_center().x, aabb.get_center().y)
	var w := aabb.size.x
	var h := aabb.size.y
	var vertical := h > w * 1.3
	var along := Vector2(0, 1) if vertical else Vector2(1, 0)
	var across := Vector2(-along.y, along.x)
	var len_along := (h if vertical else w) * 0.74
	var len_across := (w if vertical else h) * 0.7
	var letters := clampi(int(len_along / 0.05) + rng.randi_range(0, 1), 2, 6)
	var lw := len_along / letters
	var lh := minf(len_across * 0.75, lw * 1.7)
	var th := clampf(lh * 0.16, _cell.x * 1.2, 0.02)                      # толщина штриха: не тоньше 1.2 ячейки
	var outline := maxf(0.004, _cell.x * 0.8) if cols.size() >= 2 else 0.0   # обводка: тоньше ячейки её съел бы край заливки
	# буквы: по 3 точки на букву, связаны в одну строку (курсив тега)
	var pts: Array = []
	var s0 := -len_along * 0.5
	pts.append(Vector2(s0, rng.randf_range(-0.2, 0.2) * lh))
	for j in letters:
		var x0 := s0 + j * lw
		for m in 3:
			var sx := x0 + lw * (0.2 + 0.3 * m) + rng.randf_range(-0.12, 0.12) * lw
			var sy := rng.randf_range(-0.5, 0.5) * lh
			if m == 1:
				sy = (0.5 if j % 2 == 0 else -0.5) * lh * rng.randf_range(0.7, 1.0)
			pts.append(Vector2(sx, sy))
	var tag := _catmull(pts, maxf(_cell.x * 0.4, 0.002))
	var strokes: Array = [[tag, th]]
	if rng.randf() < 0.75:   # росчерк под тегом
		var sw: Array = []
		var y0 := -lh * rng.randf_range(0.65, 0.85)
		var bend := rng.randf_range(-0.25, 0.25) * lh
		for m in 5:
			var f := m / 4.0
			sw.append(Vector2(lerpf(-len_along * 0.52, len_along * 0.5, f), y0 + bend * sin(f * PI) + (0.3 * lh if m == 4 else 0.0)))
		strokes.append([_catmull(sw, maxf(_cell.x * 0.4, 0.002)), th * 0.7])
	# потёки: вниз по кукле (−Y кадра слоя), с каплей на конце
	var drips: Array = []
	for j in rng.randi_range(2, 4):
		var at: Vector2 = tag[rng.randi_range(0, tag.size() - 1)]
		var start := c2 + along * at.x + across * at.y
		var dl := rng.randf_range(0.012, 0.04)
		var dr: Array = []
		for m in 6:
			dr.append(start + Vector2(0.0, -dl * m / 5.0))
		drips.append(dr)
	for stv in strokes:
		var line: Array = stv[0]
		var r := float(stv[1]) * 0.5
		for q in line:
			var pq := c2 + along * (q as Vector2).x + across * (q as Vector2).y
			if outline > 0.0:
				_disc(line_cov, pq, r + outline)
			_disc(fill_cov, pq, r)
	for dr in drips:
		for m in (dr as Array).size():
			var pq: Vector2 = dr[m]
			var r := th * 0.28 * (1.5 if m == (dr as Array).size() - 1 else 1.0)
			if outline > 0.0:
				_disc(line_cov, pq, r + outline * 0.6)
			_disc(fill_cov, pq, r)
	var fc: Color = cols[0]
	return {"fill": fill_cov, "line": line_cov, "fc": fc, "lc": cols[1] if cols.size() >= 2 else fc}


func _slab_graffiti(d: PackedByteArray, p: Dictionary, z: int) -> void:
	var fill_cov: PackedFloat32Array = p["fill"]
	var line_cov: PackedFloat32Array = p["line"]
	var fc: Color = p["fc"]
	var lc: Color = p["lc"]
	var nx := res.x
	var ny := res.y
	for y in ny:
		var i := ((z * ny + y) * nx) * 4
		var row := y * nx
		for x in nx:
			var af := fill_cov[row + x]
			var al := line_cov[row + x]
			var a := maxf(af, al)
			if a > 0.0:
				_mix_px(d, i, lc.lerp(fc, af / a), a)
			i += 4


## Диск радиуса r (м) в покрытие холста (max, мягкий край в одну ячейку).
func _disc(cov: PackedFloat32Array, p: Vector2, r: float) -> void:
	var gx := (p.x - aabb.position.x) * _inv.x - 0.5
	var gy := (p.y - aabb.position.y) * _inv.y - 0.5
	var rc := r * _inv.x + 1.0
	for y in range(maxi(ceili(gy - rc), 0), mini(floori(gy + rc), res.y - 1) + 1):
		for x in range(maxi(ceili(gx - rc), 0), mini(floori(gx + rc), res.x - 1) + 1):
			var d := Vector2(x - gx, y - gy).length() * _cell.x
			var a := clampf((r - d) / _cell.x + 0.5, 0.0, 1.0)
			var k := y * res.x + x
			if a > cov[k]:
				cov[k] = a


## Ломаная через точки pts, сглаженная Catmull-Rom с шагом ≤ step (м).
static func _catmull(pts: Array, step: float) -> Array:
	var out: Array = []
	if pts.size() < 2:
		return pts.duplicate()
	for j in pts.size() - 1:
		var p0: Vector2 = pts[maxi(j - 1, 0)]
		var p1: Vector2 = pts[j]
		var p2: Vector2 = pts[j + 1]
		var p3: Vector2 = pts[mini(j + 2, pts.size() - 1)]
		var n := maxi(ceili(p1.distance_to(p2) / step), 1)
		for m in n:
			var t := float(m) / n
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[pts.size() - 1])
	return out
