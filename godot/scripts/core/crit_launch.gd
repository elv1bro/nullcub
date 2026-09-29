## Отлёт сокрушительного удара (docs/plan-demo/HIT_FX.md §2.3). Баланс, а не презентация: работает при Match.feel_enabled = false
## и без HITFX_CRIT_CINEMATIC; выключается Match.crit_enabled / Tuning.CRIT_ENABLED. Зовёт Match._emit_hit_fx сразу после
## классификации — обычный отброс (apply_knockback, клэмп FLIGHT_MAX_SPEED) к этому моменту уже применён.
##
##   crit:    kb_dir = Damage.knockback_dir(dir); v — скорость ЦМ жертвы вдоль kb_dir;
##            target = clamp(v × CRIT_KNOCKBACK_MULT, CRIT_LAUNCH_MIN_SPEED, CRIT_FLIGHT_MAX_SPEED × sd). Всем частям одна добавка
##            Δv = kb_dir × (target − v): вращение и мах конечностей сохраняются. Если с поперечной скоростью |v_ЦМ| > потолка —
##            лишнее вычитается так же, как в Doll._cap_flight_speed. Doll.set_flight_cap(CRIT_FLIGHT_MAX_SPEED × sd, CRIT_FLIGHT_S) —
##            свой клэмп полёта и продление knockback_until; всем частям дамп CRIT_FLIGHT_LINEAR_DAMP до land() (land() и страховка
##            FLIGHT_DAMP_MAX_S куклы сами вернут обычный дамп).
##   ko_crit: кукла уже разорвана (break_apart): каждая часть получает +CRIT_KO_LAUNCH_SPEED вдоль kb_dir сверх KO_BURST_SPEED.
##   атакующий (v2, HIT_FX.md §11.1; crit и ko_crit): скорость его ЦМ вдоль kb_dir режется до CRIT_ATTACKER_STOP_SPEED (не летит
##            следом и не дожимает жертву), рывок заканчивается, тяга выключена CRIT_ATTACKER_LOCK_S (Doll.thrust_lock_until —
##            как у отдачи). Поперечная скорость и мах конечностей не трогаются.
## Модель куклы не важна: только Doll.parts (RigidBody3D).
class_name CritLaunch
extends RefCounted


## Возвращает добавку скорости ЦМ (м/с, вектор) — для проб. ctx: victim, dir (или normal), tier.
static func apply(ctx: Dictionary, sd_mult: float = 1.0) -> Vector3:
	var victim := ctx.get("victim", null) as Doll
	if victim == null or not is_instance_valid(victim) or victim.parts.is_empty():
		return Vector3.ZERO
	var dir: Vector3 = ctx.get("dir", Vector3.ZERO)
	if Vector3(dir.x, dir.y, 0.0).length_squared() < 1e-6:
		dir = -(ctx.get("normal", Vector3.ZERO) as Vector3)
	var kb_dir := Damage.knockback_dir(dir)
	var bodies: Array = []
	for b in victim.parts.values():
		if b is RigidBody3D and is_instance_valid(b):
			bodies.append(b)
	if bodies.is_empty():
		return Vector3.ZERO
	if String(ctx.get("tier", "")) == HitTier.KO_CRIT or victim.is_broken():
		var add := kb_dir * Tuning.CRIT_KO_LAUNCH_SPEED
		for b in bodies:
			(b as RigidBody3D).linear_velocity += add
		stop_attacker(ctx.get("attacker", null), victim, kb_dir)
		return add
	var cap := Tuning.CRIT_FLIGHT_MAX_SPEED * maxf(sd_mult, 0.0)
	var v0 := _com_velocity(bodies)
	var along := v0.dot(kb_dir)
	var target := clampf(along * Tuning.CRIT_KNOCKBACK_MULT, Tuning.CRIT_LAUNCH_MIN_SPEED, maxf(cap, Tuning.CRIT_LAUNCH_MIN_SPEED))
	var dv := kb_dir * maxf(target - along, 0.0)
	for b in bodies:
		(b as RigidBody3D).linear_velocity += dv
	# поперечная скорость (подлёт вбок) не должна вынести ЦМ за потолок крит-полёта
	var v1 := v0 + dv
	var sp := v1.length()
	if sp > cap and cap > 0.0:
		var excess := v1 * (1.0 - cap / sp)
		for b in bodies:
			(b as RigidBody3D).linear_velocity -= excess
		dv -= excess
	if victim.has_method("set_flight_cap"):
		victim.call("set_flight_cap", cap, Tuning.CRIT_FLIGHT_S)
	# дамп крит-полёта — только поверх дампа полёта куклы (его вернёт land() / страховка); без полёта обычный дамп не трогаем
	if bool(victim.get("_flight_damp")):
		for b in bodies:
			(b as RigidBody3D).linear_damp = Tuning.CRIT_FLIGHT_LINEAR_DAMP
	stop_attacker(ctx.get("attacker", null), victim, kb_dir)
	return dv


## Атакующий крита не летит следом за жертвой: ЦМ вдоль kb_dir и вдоль его горизонтали ≤ CRIT_ATTACKER_STOP_SPEED (одна добавка всем
## частям), рывок снят, тяга выключена CRIT_ATTACKER_LOCK_S. На те же CRIT_ATTACKER_LOCK_S (физических, Doll._time) — AttackerHold:
## части атакующего и жертвы не сталкиваются (collision exception; иначе в упоре сцепившиеся конечности тащили атакующего следом
## до 4 м/с и гасили отлёт жертвы 6 → 2.5 м/с), клэмп повторяется каждый тик. Возвращает снятую скорость (м/с, ≥ 0) — для проб.
static func stop_attacker(attacker: Variant, victim: Doll, kb_dir: Vector3) -> float:
	if not (attacker is Doll) or not is_instance_valid(attacker) or attacker == victim:
		return 0.0
	var a := attacker as Doll
	var bodies := _bodies(a)
	if bodies.is_empty():
		return 0.0
	# вдоль kb_dir и вдоль его горизонтали: у kb_dir апбиас, и горизонталь «сверх» клэмпа снова несла бы вслед
	var dirs: Array = [kb_dir]
	if absf(kb_dir.x) > 1e-3:
		dirs.append(Vector3(signf(kb_dir.x), 0.0, 0.0))
	var cut := _clamp_along(bodies, dirs)
	if a.is_dashing():
		a.dash_until = a._time
	a.thrust_lock_until = maxf(a.thrust_lock_until, a._time + Tuning.CRIT_ATTACKER_LOCK_S)
	var old := a.get_node_or_null(AttackerHold.NODE_NAME)
	if old != null:
		(old as AttackerHold).finish()
		a.remove_child(old)
		old.queue_free()
	var hold := AttackerHold.new()
	hold.name = AttackerHold.NODE_NAME
	hold.setup(a, victim, dirs, a._time + Tuning.CRIT_ATTACKER_LOCK_S)
	a.add_child(hold)
	return cut


## Снять с ЦМ bodies скорость сверх CRIT_ATTACKER_STOP_SPEED вдоль каждого из dirs (одна добавка всем телам). Возвращает Σ снятого.
static func _clamp_along(bodies: Array, dirs: Array, limit: float = Tuning.CRIT_ATTACKER_STOP_SPEED) -> float:
	var cut := 0.0
	for d in dirs:
		var n := d as Vector3
		var over := _com_velocity(bodies).dot(n) - limit
		if over > 0.0:
			for b in bodies:
				(b as RigidBody3D).linear_velocity -= n * over
			cut += over
	return cut


static func _bodies(d: Doll) -> Array:
	var out: Array = []
	if d == null or not is_instance_valid(d):
		return out
	for b in d.parts.values():
		if b is RigidBody3D and is_instance_valid(b):
			out.append(b)
	return out


## Окно после крита на атакующем (ребёнок Doll): без столкновений с частями жертвы, клэмп ЦМ каждый тик до until (Doll._time).
class AttackerHold:
	extends Node
	const NODE_NAME := "CritAttackerHold"
	var attacker: Doll
	var victim_bodies: Array = []
	var dirs: Array = []
	var until := 0.0
	var _pairs: Array = []   # [attacker body, victim body] с исключением столкновений
	var _done := false

	func setup(a: Doll, victim: Doll, d: Array, t_until: float) -> void:
		attacker = a
		dirs = d
		until = t_until
		victim_bodies = CritLaunch._bodies(victim)
		for ab in CritLaunch._bodies(a):
			for vb in victim_bodies:
				(ab as PhysicsBody3D).add_collision_exception_with(vb as PhysicsBody3D)
				_pairs.append([ab, vb])

	func _ready() -> void:
		process_physics_priority = 900   # после тяги куклы, до физического шага

	func _physics_process(_delta: float) -> void:
		if _done:
			return
		if attacker == null or not is_instance_valid(attacker) or attacker._time >= until or attacker.is_broken():
			finish()
			queue_free()
			return
		CritLaunch._clamp_along(CritLaunch._bodies(attacker), dirs)

	func _exit_tree() -> void:
		finish()

	## Вернуть столкновения (идемпотентно).
	func finish() -> void:
		if _done:
			return
		_done = true
		for pr in _pairs:
			var ab: Variant = pr[0]
			var vb: Variant = pr[1]
			if is_instance_valid(ab) and is_instance_valid(vb):
				(ab as PhysicsBody3D).remove_collision_exception_with(vb as PhysicsBody3D)
		_pairs.clear()


## v3 (HIT_FX.md §12.2): тормоз атакующего на heavy. ЦМ атакующего вдоль kb_dir и вдоль его горизонтали режется до speed (одна
## добавка всем частям) сразу; seconds > 0 — ещё и каждый физический тик seconds (Doll._time, узел HeavyBrake). Без исключений
## столкновений, рывок и тяга не снимаются. Если на атакующем уже стоит AttackerHold крита — ничего не делает. Возвращает снятую
## скорость (м/с, ≥ 0) — для проб. heavy_brake_enabled = false — выключатель для проб (замер «как в v2» тем же сценарием).
## Замер (§12.2): окно 0.18 с разлёт не увеличивает — после отдачи DollCombat атакующий и так отходит, а в клинче (конечности
## переплетены) заторможенный атакующий держит жертву: −0.28…+0.04 м между ЦМ на +400 мс, 0.5 м/с — −0.55 м. Поэтому по умолчанию
## Tuning.HEAVY_ATTACKER_BRAKE_S = 0: только мгновенный клэмп в момент удара (срез «догона», если отдачи не было).
static var heavy_brake_enabled := true


static func brake_attacker(ctx: Dictionary, speed: float, seconds: float) -> float:
	if not heavy_brake_enabled:
		return 0.0
	var attacker: Variant = ctx.get("attacker", null)
	var victim: Variant = ctx.get("victim", null)
	if not (attacker is Doll) or not is_instance_valid(attacker) or attacker == victim or (attacker as Doll).is_broken():
		return 0.0
	var a := attacker as Doll
	if a.get_node_or_null(AttackerHold.NODE_NAME) != null:
		return 0.0
	var bodies := _bodies(a)
	if bodies.is_empty():
		return 0.0
	var dir: Vector3 = ctx.get("dir", Vector3.ZERO)
	if Vector3(dir.x, dir.y, 0.0).length_squared() < 1e-6:
		dir = -(ctx.get("normal", Vector3.ZERO) as Vector3)
	var kb_dir := Damage.knockback_dir(dir)
	var dirs: Array = [kb_dir]
	if absf(kb_dir.x) > 1e-3:
		dirs.append(Vector3(signf(kb_dir.x), 0.0, 0.0))
	var cut := _clamp_along(bodies, dirs, speed)
	var old := a.get_node_or_null(HeavyBrake.NODE_NAME)
	if old != null:
		a.remove_child(old)
		old.queue_free()
	if seconds <= 0.0:
		return cut
	var br := HeavyBrake.new()
	br.name = HeavyBrake.NODE_NAME
	br.attacker = a
	br.dirs = dirs
	br.speed = speed
	br.until = a._time + seconds
	a.add_child(br)
	return cut


## Окно тормоза heavy на атакующем (ребёнок Doll): клэмп ЦМ каждый тик до until (Doll._time), столкновения не трогаются.
class HeavyBrake:
	extends Node
	const NODE_NAME := "HeavyAttackerBrake"
	var attacker: Doll
	var dirs: Array = []
	var speed := 2.5
	var until := 0.0

	func _ready() -> void:
		process_physics_priority = 900   # после тяги куклы, до физического шага

	func _physics_process(_delta: float) -> void:
		if attacker == null or not is_instance_valid(attacker) or attacker._time >= until or attacker.is_broken():
			queue_free()
			set_physics_process(false)
			return
		CritLaunch._clamp_along(CritLaunch._bodies(attacker), dirs, speed)


static func _com_velocity(bodies: Array) -> Vector3:
	var p := Vector3.ZERO
	var m := 0.0
	for b in bodies:
		var rb := b as RigidBody3D
		p += rb.linear_velocity * rb.mass
		m += rb.mass
	return p / m if m > 0.0 else Vector3.ZERO
