## Удар в «Гольфе: кукла — мяч» (docs/plan-demo/GOLF.md): запуск, полоска силы, перенос куклы, баллистика с дампом.
## Только статические помощники — состояние ударов держит GolfMatch.
##   • launch(d, dir, power): скорость GOLF_SPEED_MIN…MAX одинаковая всем деталям (импульс в одну деталь растянул бы её сустав —
##     MODES_PACK §3), плюс жёсткое вращение вокруг ЦМ (кувырок вперёд по ходу, GOLF_SPIN) — суставы не тянет: у всех деталей скорость
##     твёрдого тела v + ω × r;
##   • power_at(t): полоска силы «туда-обратно» за GOLF_POWER_PERIOD_S (0 → 1 → 0);
##   • place(d, com): перенос куклы целиком (ЦМ в точку, скорости 0) — возврат после ямы и старт лунки;
##   • point_at(p0, v0, g, k, t): полёт точки с линейным дампом k (как у деталей: GOLF_DAMP) — закрытая формула, без шагов симуляции:
##     p(t) = p0 + g·t/k + (v0 − g/k)(1 − e^(−k·t))/k. Ею целится бот (solve) и рисуется пунктир прицела (HUD).
class_name GolfShot
extends RefCounted


## Полоска силы через t секунд удержания: 0 → 1 за половину периода, обратно — за вторую.
static func power_at(t: float) -> float:
	var period := maxf(Tuning.GOLF_POWER_PERIOD_S, 0.1)
	var u := fposmod(t, period) / period
	return u * 2.0 if u < 0.5 else (1.0 - u) * 2.0


static func speed_for(power: float) -> float:
	return lerpf(Tuning.GOLF_SPEED_MIN, Tuning.GOLF_SPEED_MAX, clampf(power, 0.0, 1.0))


static func power_for(speed: float) -> float:
	return clampf((speed - Tuning.GOLF_SPEED_MIN) / maxf(Tuning.GOLF_SPEED_MAX - Tuning.GOLF_SPEED_MIN, 0.01), 0.0, 1.0)


## Запустить куклу: dir — направление (плоскость XY), power 0..1. Возвращает скорость запуска (Vector3).
static func launch(d: Doll, dir: Vector2, power: float) -> Vector3:
	var n := dir.normalized() if dir.length_squared() > 1e-6 else Vector2.UP
	var v := Vector3(n.x, n.y, 0.0) * speed_for(power)
	var spin := -signf(n.x) * Tuning.GOLF_SPIN if absf(n.x) > 0.05 else 0.0
	var com := d.centre_of_mass()
	for b in d.parts.values():
		var rb := b as RigidBody3D
		if rb == null or not is_instance_valid(rb):
			continue
		var r := d.part_centre(rb) - com
		rb.linear_velocity = v + Vector3(-spin * r.y, spin * r.x, 0.0)   # ω × r, ω = (0, 0, spin)
		rb.angular_velocity = Vector3(0.0, 0.0, spin)
		if rb.sleeping:
			rb.sleeping = false
	return v


## Добавить всем деталям одну скорость (поправка в полёте).
static func add_velocity(d: Doll, dv: Vector3) -> void:
	for b in d.parts.values():
		var rb := b as RigidBody3D
		if rb != null and is_instance_valid(rb):
			rb.linear_velocity += dv
			if rb.sleeping:
				rb.sleeping = false


## Перенести куклу так, чтобы её ЦМ встал в com (z = 0); скорости — 0. Поза не меняется.
static func place(d: Doll, com: Vector3) -> void:
	var c := d.centre_of_mass()
	var off := Vector3(com.x - c.x, com.y - c.y, -c.z)
	for b in d.parts.values():
		var rb := b as RigidBody3D
		if rb == null or not is_instance_valid(rb):
			continue
		rb.global_position += off
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		rb.reset_physics_interpolation()


## Точка полёта через t с: старт p0, скорость v0, гравитация g (вектор), линейный дамп k (1/с).
static func point_at(p0: Vector2, v0: Vector2, g: Vector2, k: float, t: float) -> Vector2:
	if k < 1e-4:
		return p0 + v0 * t + g * (0.5 * t * t)
	var e := 1.0 - exp(-k * t)
	return p0 + g * (t / k) + (v0 - g / k) * (e / k)


static func velocity_at(v0: Vector2, g: Vector2, k: float, t: float) -> Vector2:
	if k < 1e-4:
		return v0 + g * t
	return g / k + (v0 - g / k) * exp(-k * t)


## Прицел в точку p1 из p0 при гравитации g и дампе k: {ok, dir: Vector2, speed, angle_deg}. Скорость — в [vmin, vmax]; не достать —
## ok = false и выстрел на vmax в сторону цели. Выбор угла:
##   "drop" — полёт проходит цель уже вниз (падает в чашу сверху), угол 30…76°, из таких — наименьшая скорость;
##   "low" — самый пологий, но не по полу: не ниже max(угол на цель + 6°, 8°);
##   "high" — самый крутой до 72°;
##   "min" — наименьшая скорость;
##   deg ≥ −90 — ровно этот угол (подсказки лунок: «настильно под потолком»).
## Как считает: в системе «вниз = g» для каждого угла θ (шаг 2°) делением пополам ищется скорость, при которой полёт проходит через цель
## (высота на нужном удалении растёт со скоростью), и запоминается, идёт ли полёт там уже вниз.
static func solve(p0: Vector2, p1: Vector2, g: Vector2, k: float, vmin: float, vmax: float, arc := "min", deg := -999.0) -> Dictionary:
	var gm := g.length()
	var up := -g / gm if gm > 1e-4 else Vector2.UP
	var r := p1 - p0
	var side := r - up * r.dot(up)
	if side.length() < 1e-3:
		side = Vector2(up.y, -up.x)
	side = side.normalized()
	var dx := maxf(r.dot(side), 0.35)
	var dy := r.dot(up)
	var cands: Array = []   # [θ°, V, вниз у цели]
	if deg > -90.0:
		var v1 := _speed_for_angle(deg_to_rad(deg), dx, dy, gm, k, vmin, vmax)
		if v1 > 0.0:
			cands.append([deg, v1, _descending(deg_to_rad(deg), v1, dx, gm, k)])
	else:
		var th := -40.0
		while th <= 84.0:
			var v := _speed_for_angle(deg_to_rad(th), dx, dy, gm, k, vmin, vmax)
			if v > 0.0:
				cands.append([th, v, _descending(deg_to_rad(th), v, dx, gm, k)])
			th += 2.0
	if cands.is_empty():
		var a0 := deg_to_rad(deg) if deg > -90.0 else atan2(dy, dx) + deg_to_rad(20.0)
		var d0 := side * cos(a0) + up * sin(a0)
		return {"ok": false, "dir": d0.normalized(), "speed": vmax, "angle_deg": rad_to_deg(a0)}
	var pick: Array = cands[0]
	match arc:
		"low":
			var floor_deg := maxf(rad_to_deg(atan2(dy, dx)) + 6.0, 8.0)
			pick = cands[-1]
			for c in cands:
				if float(c[0]) >= floor_deg:
					pick = c
					break
		"high":
			pick = cands[0]
			for c in cands:
				if float(c[0]) <= 72.0:
					pick = c
		"drop":
			var best: Array = []
			for c in cands:
				if bool(c[2]) and float(c[0]) >= 30.0 and float(c[0]) <= 76.0 and (best.is_empty() or float(c[1]) < float(best[1])):
					best = c
			if best.is_empty():
				for c in cands:
					if float(c[1]) < float(pick[1]):
						pick = c
			else:
				pick = best
		_:
			for c in cands:
				if float(c[1]) < float(pick[1]):
					pick = c
	var ang := deg_to_rad(float(pick[0]))
	return {"ok": true, "dir": (side * cos(ang) + up * sin(ang)).normalized(), "speed": float(pick[1]), "angle_deg": float(pick[0])}


## Скорость, при которой полёт под углом θ (в системе «вниз = g») проходит через (dx, dy) с точностью 0.15 м; −1 — нет в [vmin, vmax].
static func _speed_for_angle(th: float, dx: float, dy: float, gm: float, k: float, vmin: float, vmax: float) -> float:
	var c := cos(th)
	var s := sin(th)
	if c < 1e-3:
		return -1.0
	var y_hi := _height_at(vmax, c, s, dx, gm, k)
	if is_nan(y_hi) or y_hi < dy:
		return -1.0
	var y_lo := _height_at(vmin, c, s, dx, gm, k)
	if not is_nan(y_lo) and y_lo >= dy:
		return vmin if y_lo - dy < 0.15 else -1.0   # и самый слабый удар проходит выше цели — этим углом не попасть
	var lo := vmin
	var hi := vmax
	for i in 28:
		var mid := (lo + hi) * 0.5
		var y := _height_at(mid, c, s, dx, gm, k)
		if is_nan(y) or y < dy:
			lo = mid
		else:
			hi = mid
	return hi


## Идёт ли полёт (θ, V) вниз на удалении dx.
static func _descending(th: float, vv: float, dx: float, gm: float, k: float) -> bool:
	var a := vv * cos(th)
	var b := vv * sin(th)
	if k < 1e-4:
		return b - gm * dx / a < 0.0
	var q := 1.0 - k * dx / a
	if q <= 1e-6:
		return true
	var t := -log(q) / k
	return (b + gm / k) * exp(-k * t) - gm / k < 0.0


## Высота (вдоль «вверх») на удалении dx при скорости V под углом (c = cos θ, s = sin θ); NAN — до dx не долетает.
static func _height_at(vv: float, c: float, s: float, dx: float, gm: float, k: float) -> float:
	var a := vv * c
	var b := vv * s
	if k < 1e-4:
		var t0 := dx / a
		return b * t0 - 0.5 * gm * t0 * t0
	var q := 1.0 - k * dx / a
	if q <= 1e-6:
		return NAN
	var t := -log(q) / k
	var e := 1.0 - exp(-k * t)
	return (b + gm / k) * e / k - gm * t / k
