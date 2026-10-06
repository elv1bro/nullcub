## Навигация ботов «Гонки» (docs/plan-demo/RACE.md): поиска пути в игре нет, поэтому граф видимости по меткам карты. Метки ставятся
## в открытом воздухе так, чтобы из каждой было видно несколько других (race_probe, раздел marks); ребро графа — «толстый» луч между
## метками (центр и два луча по бокам на FAT_M), который не задевает препятствий. Кратчайшие пути — Флойд–Уоршелл (меток ≤ 20).
## Бот, которому прямая к точке закрыта, летит к той видимой метке, от которой путь по графу до цели короче всего (RaceBrain._plan).
## Препятствие для луча — статика (StaticBody3D, в том числе AnimatableBody3D: пресс Свалки), доски верёвочного моста Руин (RopeBridge
## — RigidBody3D на цепи, сквозь них не пролететь), замороженные тела (тяжёлые пропсы-якоря PropHeft) и пропсы тяжелее
## PUSHABLE_KG (тележка 30 кг, железная бочка 40, большой ящик 80 — их не растолкать с ходу). Куклы и лёгкие пропсы — нет.
class_name RaceNav
extends RefCounted

const FAT_M := 0.3
const PUSHABLE_KG := 15.0

var marks: Array[Vector3] = []
## dist[i][j] — длина кратчайшего пути по графу (INF — недостижимо), edges[i] — соседи i.
var dist: Array = []
var edges: Array = []


## Препятствие ли для луча бота.
static func is_obstacle(c: Object) -> bool:
	if c is StaticBody3D:
		return true
	if c is RigidBody3D:
		var b := c as RigidBody3D
		var p := b.get_parent()
		if p is Doll:
			return false   # деталь куклы
		if b.freeze or b.mass > PUSHABLE_KG:
			return true
		return p != null and (p is RopeBridge or p.get_parent() is RopeBridge)   # доска моста: RopeBridge/Planks/Plank_i
	return false


## Первое препятствие на отрезке a → b в плоскости боя: {pos: Vector2, collider} или {}. Прочее (куклы, пропсы, точки) пропускается
## (исключается и луч повторяется, до 6 раз).
static func ray(space: PhysicsDirectSpaceState3D, a: Vector2, b: Vector2, exclude: Array[RID] = []) -> Dictionary:
	if space == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(Vector3(a.x, a.y, 0.0), Vector3(b.x, b.y, 0.0))
	q.collide_with_areas = false
	var ex: Array[RID] = exclude.duplicate()
	for i in 6:
		q.exclude = ex
		var h := space.intersect_ray(q)
		if h.is_empty():
			return {}
		var c: Object = h.get("collider")
		if is_obstacle(c):
			var hp := h["position"] as Vector3
			return {"pos": Vector2(hp.x, hp.y), "collider": c}
		if c is CollisionObject3D:
			ex.append((c as CollisionObject3D).get_rid())
		else:
			return {}
	return {}


## Толстый луч: центр и два параллельных луча на fat по бокам — все чисты (кукла шире точки, тонкий луч задевал бы край плиты).
static func clear(space: PhysicsDirectSpaceState3D, a: Vector2, b: Vector2, exclude: Array[RID] = [], fat: float = FAT_M) -> bool:
	if not ray(space, a, b, exclude).is_empty():
		return false
	var d := b - a
	if d.length() < 0.01 or fat <= 0.0:
		return true
	var n := Vector2(-d.y, d.x).normalized() * fat
	return ray(space, a + n, b + n, exclude).is_empty() and ray(space, a - n, b - n, exclude).is_empty()


## Граф по меткам: рёбра — толстые лучи без препятствий, dist — кратчайшие пути.
func build(space: PhysicsDirectSpaceState3D, pts: Array[Vector3]) -> void:
	marks = pts.duplicate()
	var n := marks.size()
	dist = []
	edges = []
	for i in n:
		var row: Array = []
		row.resize(n)
		row.fill(INF)
		row[i] = 0.0
		dist.append(row)
		edges.append([])
	for i in n:
		for j in range(i + 1, n):
			var a := Vector2(marks[i].x, marks[i].y)
			var b := Vector2(marks[j].x, marks[j].y)
			if clear(space, a, b):
				var l := a.distance_to(b)
				dist[i][j] = l
				dist[j][i] = l
				(edges[i] as Array).append(j)
				(edges[j] as Array).append(i)
	for k in n:
		for i in n:
			var dik: float = dist[i][k]
			if dik == INF:
				continue
			for j in n:
				var v := dik + float(dist[k][j])
				if v < float(dist[i][j]):
					dist[i][j] = v


func ready() -> bool:
	return not dist.is_empty()


func path_len(i: int, j: int) -> float:
	if i < 0 or j < 0 or i >= dist.size() or j >= dist.size():
		return INF
	return float(dist[i][j])


## Сколько пар меток связано (для проб): доля пар с конечным путём.
func connected_share() -> float:
	var n := marks.size()
	if n < 2:
		return 1.0
	var ok := 0
	for i in n:
		for j in n:
			if i != j and float(dist[i][j]) < INF:
				ok += 1
	return float(ok) / float(n * (n - 1))
