## Линия «Гонки: трасса» (docs/plan-demo/RACE_TRACK.md): проложенный руками путь от старта до финиша — для ботов (поиска пути в игре
## нет) и для счёта «кто впереди». Строится из узла Route карты (сборщик tools/build_race_track.gd):
##   Route/<отрезок> (Node3D, мета kind = main | easy | hard, fork = "" | "A" | "B" | "C", next = PackedStringArray имён следующих)
##     └── W00, W01, … (Marker3D, точки линии по порядку; мета v — предел скорости бота у точки, м/с; dash — бот держит ускорение;
##         press — путь от карты до пресса, перед которым бот ждёт такта; look — насколько вперёд бот смотрит, м; charge — бот ждёт у
##         точки, пока Заряд не наберётся до стольких).
## Отрезки: main0 → развилка A (easy | hard) → main1 → развилка B → main2 → развилка C → main3 → финиш. Последняя точка отрезка
## совпадает с первой точкой следующего.
## Прогресс (метры от старта): главные отрезки — своей длиной; обе ветки развилки ложатся на один отрезок прогресса длиной короткой
## (трудной) ветки — линейно по доле пройденного, поэтому «кто впереди» сравнимо, кто бы какой путь ни выбрал.
class_name TrackRoute
extends RefCounted


class Seg:
	var name := ""
	var kind := "main"
	var fork := ""
	var next: Array[int] = []
	var pts := PackedVector2Array()
	var meta: Array = []                  # Dictionary на точку
	var cum := PackedFloat64Array()       # длина пути от начала отрезка до точки i
	var length := 0.0
	var p0 := 0.0
	var p1 := 0.0

	## Прогресс трассы в точке «s метров от начала отрезка».
	func prog_at(s: float) -> float:
		if length <= 0.0:
			return p0
		return p0 + clampf(s / length, 0.0, 1.0) * (p1 - p0)


var segs: Array[Seg] = []
## Длина трассы в метрах прогресса (финиш).
var total := 0.0
## Развилки: id → {easy: индекс отрезка, hard: индекс, p0, p1}.
var forks: Dictionary = {}
var _by_name: Dictionary = {}


## Собрать из узла Route (мировые координаты точек; z не нужен).
func build(route: Node) -> void:
	segs.clear()
	forks.clear()
	_by_name.clear()
	if route == null:
		return
	var nexts: Array = []
	for n in route.get_children():
		if not (n is Node3D):
			continue
		var s := Seg.new()
		s.name = String(n.name)
		s.kind = String(n.get_meta("kind", "main"))
		s.fork = String(n.get_meta("fork", ""))
		for w in n.get_children():
			if w is Node3D:
				var p := (w as Node3D).global_position
				s.pts.append(Vector2(p.x, p.y))
				var m := {}
				for k in ["v", "dash", "press", "look", "charge"]:
					if w.has_meta(k):
						m[k] = w.get_meta(k)
				s.meta.append(m)
		_measure(s)
		_by_name[s.name] = segs.size()
		segs.append(s)
		nexts.append(n.get_meta("next", PackedStringArray()))
	for i in segs.size():
		for nm in nexts[i]:
			if _by_name.has(String(nm)):
				segs[i].next.append(int(_by_name[String(nm)]))
	_progress()


static func _measure(s: Seg) -> void:
	s.cum.resize(s.pts.size())
	var acc := 0.0
	for i in s.pts.size():
		if i > 0:
			acc += s.pts[i - 1].distance_to(s.pts[i])
		s.cum[i] = acc
	s.length = acc


## Прогресс по отрезкам: от main0 по цепочке; у развилки обе ветки — один отрезок длиной короткой.
func _progress() -> void:
	var cur := index_of("main0")
	var p := 0.0
	var guard := 0
	while cur >= 0 and guard < 64:
		guard += 1
		var s := segs[cur]
		s.p0 = p
		s.p1 = p + s.length
		p = s.p1
		if s.next.size() == 1:
			cur = s.next[0]
		elif s.next.size() >= 2:
			var a := segs[s.next[0]]
			var b := segs[s.next[1]]
			var l := minf(a.length, b.length)
			for br in [a, b]:
				(br as Seg).p0 = p
				(br as Seg).p1 = p + l
			var easy := s.next[0] if a.kind == "easy" else s.next[1]
			var hard := s.next[1] if easy == s.next[0] else s.next[0]
			forks[a.fork] = {"easy": easy, "hard": hard, "p0": p, "p1": p + l}
			p += l
			cur = a.next[0] if not a.next.is_empty() else -1
		else:
			cur = -1
	total = p


func index_of(name_: String) -> int:
	return int(_by_name.get(name_, -1))


func ready() -> bool:
	return not segs.is_empty() and total > 0.0


## Ближайшая к pos точка линии среди отрезков, чей прогресс пересекает [hint − window, hint + window] (window < 0 — все).
## prefer — отрезок, на котором гонщик был (с ним сравнение мягче на STICK_M: на развилке не прыгает между ветками).
## → {seg, k (номер куска), t, s (м от начала отрезка), prog, dist, point}.
const STICK_M := 1.5

func project(pos: Vector2, hint := 0.0, window := -1.0, prefer := -1) -> Dictionary:
	var best := {}
	var best_score := INF
	for si in segs.size():
		var s := segs[si]
		if window >= 0.0 and (s.p1 < hint - window or s.p0 > hint + window):
			continue
		for k in s.pts.size() - 1:
			var a := s.pts[k]
			var b := s.pts[k + 1]
			var ab := b - a
			var l2 := ab.length_squared()
			var t := clampf((pos - a).dot(ab) / l2, 0.0, 1.0) if l2 > 1e-6 else 0.0
			var c := a + ab * t
			var d := pos.distance_to(c)
			var score := d - (STICK_M if si == prefer else 0.0)
			if score < best_score:
				best_score = score
				var along := s.cum[k] + sqrt(l2) * t
				best = {"seg": si, "k": k, "t": t, "s": along, "prog": s.prog_at(along), "dist": d, "point": c}
	return best


## Точка на линии через ahead метров после (seg, s), по веткам choice (fork → "easy" | "hard"; нет — easy).
func point_ahead(seg: int, s: float, ahead: float, choice: Dictionary = {}) -> Vector2:
	var si := seg
	var along := s + ahead
	var guard := 0
	while si >= 0 and guard < 16:
		guard += 1
		var sg := segs[si]
		if along <= sg.length or sg.next.is_empty():
			return _point_on(sg, minf(along, sg.length))
		along -= sg.length
		si = next_of(si, choice)
	return segs[seg].pts[segs[seg].pts.size() - 1] if seg >= 0 else Vector2.ZERO


## Следующий отрезок после si: развилка — по choice (fork → "easy" | "hard"), иначе единственный; конец — −1.
func next_of(si: int, choice: Dictionary = {}) -> int:
	var sg := segs[si]
	if sg.next.is_empty():
		return -1
	if sg.next.size() == 1:
		return sg.next[0]
	var f := segs[sg.next[0]].fork
	var want := String(choice.get(f, "easy"))
	for n in sg.next:
		if segs[n].kind == want:
			return n
	return sg.next[0]


func _point_on(sg: Seg, s: float) -> Vector2:
	for k in sg.pts.size() - 1:
		if s <= sg.cum[k + 1] or k == sg.pts.size() - 2:
			var l := sg.cum[k + 1] - sg.cum[k]
			var t := clampf((s - sg.cum[k]) / l, 0.0, 1.0) if l > 1e-6 else 0.0
			return sg.pts[k].lerp(sg.pts[k + 1], t)
	return sg.pts[0] if not sg.pts.is_empty() else Vector2.ZERO


## Точки линии впереди (seg, s) в пределах dist метров: [[метров до точки, мета точки, сама точка]] (по веткам choice).
func points_ahead(seg: int, s: float, dist: float, choice: Dictionary = {}) -> Array:
	var out: Array = []
	var si := seg
	var base := -s
	var guard := 0
	while si >= 0 and guard < 16:
		guard += 1
		var sg := segs[si]
		for i in sg.pts.size():
			var d := base + sg.cum[i]
			if d < -0.01:
				continue
			if d > dist:
				return out
			out.append([d, sg.meta[i], sg.pts[i]])
		base += sg.length
		si = next_of(si, choice)
	return out


## Прогресс точки начала развилки id (−1 — нет такой).
func fork_start(id: String) -> float:
	return float((forks.get(id, {}) as Dictionary).get("p0", -1.0))


## Отрезок-ветка развилки: kind = "easy" | "hard".
func branch(id: String, kind: String) -> int:
	return int((forks.get(id, {}) as Dictionary).get(kind, -1))
