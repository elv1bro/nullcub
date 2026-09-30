## Детектор ударов одной куклы (план 06, CONCEPT.md §8–§9, RM-комбо). Узел-ребёнок Doll (добавляет Match.register или интегратор).
##
## Как считается удар. На частях MONITORED (голова, торс, кисти, стопы, предплечья, голени) включён contact_monitor
## (max_contacts_reported 4). Каждый физический тик в общий словарь prev_vel пишутся скорости (линейная + угловая) частей и оружия
## ДО шага физики: body_entered приходит после решения контакта, когда скорости уже погашены. В коллбэке body_entered:
##   • скорость точки контакта каждого тела = v + ω × r (кисть на дуге быстрее торса), нормаль/точка — из PhysicsDirectBodyState3D
##     (get_contact_local_normal/position, координаты мировые), иначе линия центров;
##   • striker = тело с большей скоростью точки, victim — другое; скорость удара v = min(|(v_striker − v_victim) · n|,
##     max собственных скоростей по n) — формула калибрована на удар по стоящей цели, встречные 9 + 9 м/с = удар 9, не 18;
##   • часть другой куклы → kind head|body (в голову ×HEAD_HIT_MULT), масса и BODY_MULT бьющей части; голова о голову бьёт обоих
##     той же v без бонуса «в голову» (RM);
##   • Weapon → kind weapon (масса оружия, damage_mult, атакующий = Weapon.attacker(3 с) → Doll; своё оружие = kind self);
##     оружие без атрибуции (никто не держит и не бросал ≤ 3 с, например толкнутое другой куклой) = kind environment;
##     масса оружия с 29.09 не режется MASS_CAP (Damage.weapon_mass; кап стандартного оружия — в его damage_mult);
##   • статика/пропс → kind environment, если v ≥ ENV_MIN_IMPACT_SPEED (масса = min(кукла или пропс, MASS_CAP), ×ENV_DAMAGE_MULT;
##     без нормали контакта статика не бьёт — скольжение вдоль пола не отличить от удара).
## Урон от окружения выключен (Tuning.ENV_DAMAGE_ENABLED = false, решение автора 28.09): kind environment — и статика/пропс, и
## оружие без атрибуции — в очередь не попадает (_raw_damage тоже даёт 0), значит нет урона, стана, отброса, надписи, hit_feel,
## записи удара. Остаются stats.wall_collisions (Wall Inspector) и KO kind self от пропасти (Doll.knock_out() площадки).
## Кандидаты складываются в очередь жертвы (DollCombat жертвы; если её часть без монитора — сторона бьющего кладёт в чужую очередь)
## и разрешаются в следующем _physics_process по убыванию урона: одна пара (атакующий, жертва) не чаще PAIR_HIT_COOLDOWN_S;
## второе попадание ДРУГИМ телом в DOUBLE_BLOW_WINDOW_S = DOUBLE BLOW с уроном ×DOUBLE_BLOW_MULT; удар о статику в окне
## «дорастает» до максимального из частей (кисть коснулась стены первой — засчитывается голова).
## Применение: комбо атакующего (×combo_mult(n), n сбрасывается, когда его бьют), victim.take_damage, knockback
## (Damage.knockback_impulse × Match.knockback_mult вдоль направления удара с апбиасом; в торс и в ударенную часть),
## стан (Damage.stun_seconds), ImpactFx в точке контакта (сила ∝ урону), Match.on_hit (надписи, hit_feel, hp_changed).
## Статистика (CONCEPT.md §19) в doll.stats: damage_dealt/taken, hardest_hit, weapon_hits, wall_collisions (статика ≥ 4 м/с),
## air_time (ни одна часть не касается статики/пропса), max_speed (торс), rotations (полные обороты торса),
## flight_distance (после удара ≥ FLIGHT_TRACK_DAMAGE до касания статики), combo_max, combo_score = Σ урон × множитель комбо.
class_name DollCombat
extends Node

const MONITORED := ["Head", "Torso", "Hand_L", "Hand_R", "Foot_L", "Foot_R", "LowerArm_L", "LowerArm_R", "LowerLeg_L", "LowerLeg_R"]
const MAX_CONTACTS := 8              # 4 контакта с полом у лежащего торса вытесняли бы удар (см. breakable.gd)
const FX_MIN_DAMAGE := 1.0             # ниже — без щепок
const FX_STRENGTH_BASE := 4.0          # ImpactFx strength = BASE + урон × PER_HP (STRENGTH_REF 8 → «номинальный» удар 10 HP)
const FX_STRENGTH_PER_HP := 0.4
const FLIGHT_LEAVE_GROUND_S := 0.4     # после удара ждём отрыва от земли столько; иначе полёта не было

## Скорости до шага физики, общие для всех кукол: RigidBody3D -> [linear, angular].
static var prev_vel: Dictionary = {}

var doll: Doll
## Match (если есть в сцене): фазы, множители SD, надписи, hit_feel. Ставит Match.register или ищется по группе "match".
var match_ref: Node = null
## Комбо атакующего (RM): число ударов в окне COMBO_WINDOW_S и время последнего.
var combo_n := 0
var combo_last_t := -100.0
## Счётчики для тестов/отладки.
var hits_taken := 0
var hits_dealt := 0
var last_damage_taken := 0.0
var last_damage_dealt := 0.0
var last_kind_taken := ""
## Контакты с окружением, которые при ENV_DAMAGE_ENABLED ударили бы (статика/пропс v ≥ ENV_MIN_IMPACT_SPEED с нормалью, ничьё
## оружие), но проигнорированы, и их максимальная скорость (м/с) — гейт доказывает, что ноль урона не из-за слабого касания.
var env_ignored := 0
var env_ignored_max_speed := 0.0

var _time := 0.0
var _queue: Array = []                 # кандидаты ударов по моей кукле (см. _enqueue)
var _recent: Dictionary = {}           # attacker key -> Array[float] времена применённых ударов (кулдаун пары)
var _env_applied: Dictionary = {}      # static body id -> {"t": float, "damage": float} для дорастания урона о стену
var _wall_t: Dictionary = {}           # static body id -> время последнего учтённого wall_collision
var _grounded := true
var _was_grounded := true
var _prev_torso_rot := 0.0
var _rot_acc := 0.0
var _flight_phase := 0                 # 0 нет, 1 ждём отрыва, 2 летим
var _flight_start := Vector3.ZERO
var _flight_t0 := 0.0
var _monitored: Array = []             # RigidBody3D с включённым монитором
var _setup_done := false
var _purge_ticks := 0
const PURGE_EVERY_TICKS := 300         # чистка prev_vel от освобождённых тел (оружие, чужие куклы)


func _ready() -> void:
	doll = get_parent() as Doll
	if doll == null:
		push_error("DollCombat must be a child of Doll")
		return
	if doll.is_node_ready():
		_setup()
	else:
		doll.ready.connect(_setup)


func _setup() -> void:
	if _setup_done or doll == null:
		return
	_setup_done = true
	for pn in MONITORED:
		var b := doll.parts.get(pn) as RigidBody3D
		if b != null:
			_monitor(b)
	# детали сборки (ModularDoll: «Hand_3», «Foot_C», бьющая цепь кистеня) — по базовому имени или решению самой куклы
	var bases: Dictionary = {}
	for pn in MONITORED:
		bases[Doll.part_base_name(String(pn))] = true
	for pn in doll.parts.keys():
		var b := doll.parts[pn] as RigidBody3D
		if b == null or _monitored.has(b):
			continue
		var want: bool = bool(doll.call("combat_monitored", String(pn))) if doll.has_method("combat_monitored") \
			else bases.has(Doll.part_base_name(String(pn)))
		if want:
			_monitor(b)
	for b in doll.parts.values():
		prev_vel[b] = [(b as RigidBody3D).linear_velocity, (b as RigidBody3D).angular_velocity]
	_prev_torso_rot = doll.torso().global_rotation.z
	if match_ref == null:
		match_ref = get_tree().get_first_node_in_group("match")


func _monitor(b: RigidBody3D) -> void:
	if _monitored.has(b):
		return   # ModularDoll._hook_combat мог подключить деталь раньше _setup
	b.contact_monitor = true
	b.max_contacts_reported = maxi(b.max_contacts_reported, MAX_CONTACTS)
	b.body_entered.connect(_on_part_contact.bind(b))
	_monitored.append(b)
	prev_vel[b] = [b.linear_velocity, b.angular_velocity]


func _exit_tree() -> void:
	if doll == null:
		return
	for b in doll.parts.values():
		prev_vel.erase(b)


## Сброс комбо и очередей (Match.restart / reset_for_match).
func reset() -> void:
	combo_n = 0
	combo_last_t = -100.0
	_queue.clear()
	_recent.clear()
	_env_applied.clear()
	_wall_t.clear()
	_flight_phase = 0
	hits_taken = 0
	hits_dealt = 0
	last_damage_taken = 0.0
	last_damage_dealt = 0.0
	last_kind_taken = ""
	env_ignored = 0
	env_ignored_max_speed = 0.0


func _combat_allowed() -> bool:
	if match_ref != null and is_instance_valid(match_ref) and match_ref.has_method("combat_active"):
		return bool(match_ref.call("combat_active"))
	return true


func _knockback_mult() -> float:
	if match_ref != null and is_instance_valid(match_ref) and match_ref.has_method("knockback_mult"):
		return float(match_ref.call("knockback_mult"))
	return 1.0


static func _part_doll(b: Node) -> Doll:
	if b == null:
		return null
	return b.get_parent() as Doll


static func combat_of(d: Doll) -> DollCombat:
	if d == null:
		return null
	for c in d.get_children():
		if c is DollCombat:
			return c
	return null


## Скорость точки p тела b по скоростям до шага (prev_vel) или текущим.
static func _point_velocity(b: RigidBody3D, p: Vector3) -> Vector3:
	var lv: Vector3 = b.linear_velocity
	var av: Vector3 = b.angular_velocity
	if prev_vel.has(b):
		var e: Array = prev_vel[b]
		lv = e[0]
		av = e[1]
	if b.freeze:
		return Vector3.ZERO
	var com: Vector3 = b.to_global(b.center_of_mass)
	return lv + av.cross(p - com)


# --- контакты ---

func _on_part_contact(other: Node, part: RigidBody3D) -> void:
	if doll == null or not is_instance_valid(part) or not is_instance_valid(other) or not doll.alive:
		return
	if not _combat_allowed():
		return
	var ob := other as PhysicsBody3D
	if ob == null:
		return
	# точка и нормаль контакта из состояния тела (координаты мировые, см. playground.gd/workshop_lookdev.gd)
	var pos := part.global_position
	var nrm := Vector3.ZERO
	var found := false
	var st := PhysicsServer3D.body_get_direct_state(part.get_rid())
	if st != null:
		var oid := ob.get_instance_id()
		for i in st.get_contact_count():
			if st.get_contact_collider_id(i) == oid:
				pos = st.get_contact_local_position(i)
				nrm = st.get_contact_local_normal(i)
				found = true
				break
	if not found:
		var d := ob.global_position - part.global_position
		d.z = 0.0
		if d.length_squared() > 1e-6:
			nrm = d.normalized()
			pos = part.global_position + nrm * 0.1
		else:
			nrm = Vector3.RIGHT
	nrm.z = 0.0
	if nrm.length_squared() < 1e-6:
		nrm = Vector3.RIGHT
	nrm = nrm.normalized()

	var v_part := _point_velocity(part, pos)
	var other_rb := ob as RigidBody3D
	var v_other := Vector3.ZERO
	if other_rb != null:
		v_other = _point_velocity(other_rb, pos)
	var rel := v_part - v_other
	# закрывающая скорость — только по нормали (скольжение вдоль пола не бьёт); без нормали — вся относительная.
	# Формула калибрована на удар по стоящей цели, поэтому v = min(сближение, собственная скорость быстрейшего тела по нормали):
	# встречные 9 + 9 м/с — удар 9, не 18.
	var closing := absf(rel.dot(nrm)) if found else rel.length()
	var own := maxf(absf(v_part.dot(nrm)), absf(v_other.dot(nrm))) if found else maxf(v_part.length(), v_other.length())
	closing = minf(closing, own)

	var other_doll := _part_doll(ob)
	if other_doll != null and other_doll != doll:
		_contact_doll(part, other_rb, other_doll, pos, nrm, v_part, v_other, closing)
	elif ob is Weapon:
		_contact_weapon(part, ob as Weapon, pos, nrm, v_part, v_other, closing)
	elif other_doll == null:
		_contact_env(part, ob, pos, nrm, v_part, v_other, closing, found)


## Часть моей куклы против части чужой. Бьющий — тело с большей скоростью точки контакта; голова о голову бьёт обоих.
func _contact_doll(part: RigidBody3D, other: RigidBody3D, other_doll: Doll, pos: Vector3, nrm: Vector3, v_part: Vector3, v_other: Vector3, closing: float) -> void:
	if other == null or not other_doll.alive:
		return
	var head_head := part.name.begins_with("Head") and other.name.begins_with("Head")
	var i_am_faster := v_part.length_squared() > v_other.length_squared()
	if head_head or not i_am_faster:
		# моя кукла — жертва: бьёт other. Голова о голову бьёт обоих (RM) той же скоростью, без бонуса «в голову».
		var striker_v := v_other - v_part
		var dir := striker_v if striker_v.length_squared() > 1e-4 else (part.global_position - other.global_position)
		_enqueue({
			"victim_part": part, "striker": other, "attacker": other_doll, "kind": "head" if part.name.begins_with("Head") else "body",
			"mass": other.mass, "body_mult": Damage.body_mult_of_body(other) * Damage.shape_mult_of_body(other, closing), "weapon_mult": 1.0, "weapon_id": "",
			"speed": closing, "target_mult": 1.0 if head_head else Damage.target_mult_of(part.name),
			"pos": pos, "nrm": nrm, "dir": dir, "t": _time,
		})
		return
	# чужая кукла — жертва: бьёт моя часть. Если её часть с монитором, она сама получит событие.
	if other.contact_monitor:
		return
	var oc := combat_of(other_doll)
	if oc == null:
		return
	var striker_v := v_part - v_other
	var dir := striker_v if striker_v.length_squared() > 1e-4 else (other.global_position - part.global_position)
	oc._enqueue({
		"victim_part": other, "striker": part, "attacker": doll, "kind": "head" if other.name.begins_with("Head") else "body",
		"mass": part.mass, "body_mult": Damage.body_mult_of_body(part) * Damage.shape_mult_of_body(part, closing), "weapon_mult": 1.0, "weapon_id": "",
		"speed": closing, "pos": pos, "nrm": nrm, "dir": dir, "t": _time,
	})


func _contact_weapon(part: RigidBody3D, w: Weapon, pos: Vector3, nrm: Vector3, v_part: Vector3, v_other: Vector3, closing: float) -> void:
	var attacker: Doll = null
	var holder: Node = w.attacker(Tuning.WEAPON_ATTACKER_WINDOW_S)
	if holder is Doll:
		attacker = holder
	elif holder != null:
		var hd: Variant = holder.get("doll")
		if hd is Doll:
			attacker = hd
		elif holder.get_parent() is Doll:
			attacker = holder.get_parent() as Doll
	var kind := "weapon"
	if attacker == doll:
		kind = "self"
	elif attacker == null:
		if not Tuning.ENV_DAMAGE_ENABLED:
			if closing >= Tuning.MIN_IMPACT_SPEED:
				_note_env_ignored(closing)
			return   # ничьё оружие (лежало, толкнули) — пропс; урон от окружения выключен
		kind = "environment"
	var striker_v := v_other - v_part
	var dir := striker_v if striker_v.length_squared() > 1e-4 else (part.global_position - w.global_position)
	_enqueue({
		"victim_part": part, "striker": w, "attacker": attacker, "kind": kind,
		"mass": w.mass, "body_mult": 1.0, "weapon_mult": w.damage_mult, "weapon_id": w.weapon_id,
		"speed": closing, "pos": pos, "nrm": nrm, "dir": dir, "t": _time,
	})


func _contact_env(part: RigidBody3D, ob: PhysicsBody3D, pos: Vector3, nrm: Vector3, v_part: Vector3, v_other: Vector3, closing: float, found: bool) -> void:
	var key := ob.get_instance_id()
	if closing >= Tuning.ENV_WALL_COLLISION_SPEED and _time - float(_wall_t.get(key, -10.0)) >= Tuning.PAIR_HIT_COOLDOWN_S:
		_wall_t[key] = _time
		doll.stats["wall_collisions"] = int(doll.stats["wall_collisions"]) + 1
		_notify_env_slam(part, pos, nrm, closing)
	if closing < Tuning.ENV_MIN_IMPACT_SPEED:
		return
	var rb := ob as RigidBody3D
	var dynamic := rb != null and not rb.freeze
	if not found and not dynamic:
		return   # без нормали контакта скольжение вдоль статики нельзя отличить от удара — не бьём
	if not Tuning.ENV_DAMAGE_ENABLED:
		_note_env_ignored(closing)
		return   # решение автора 28.09: стены/пол/пропсы урона не наносят (wall_collisions выше уже учтён)
	var mass := doll.total_mass
	if dynamic:
		mass = rb.mass
	# отскок: нормаль, направленная против подлёта части
	var bounce := nrm
	var approach := v_part - v_other
	if bounce.dot(approach) > 0.0:
		bounce = -bounce
	_enqueue({
		"victim_part": part, "striker": ob, "attacker": null, "kind": "environment",
		"mass": mass, "body_mult": 1.0, "weapon_mult": 1.0, "weapon_id": "",
		"speed": closing, "pos": pos, "nrm": nrm, "dir": bounce, "t": _time,
	})


## Удар о статику/пропс без урона (docs/plan-demo/HIT_FX.md §2.4): Match.on_env_slam → сигнал env_slam (пыль, звук, тряска).
## Тот же блок и кулдаун, что stats.wall_collisions; порог Tuning.HITFX_SLAM_SPEED. Очередь урона не трогается.
func _notify_env_slam(part: RigidBody3D, pos: Vector3, nrm: Vector3, closing: float) -> void:
	if closing < Tuning.HITFX_SLAM_SPEED or match_ref == null or not is_instance_valid(match_ref) or not match_ref.has_method("on_env_slam"):
		return
	match_ref.call("on_env_slam", doll, String(part.name), closing, pos, nrm)


func _note_env_ignored(speed: float) -> void:
	env_ignored += 1
	env_ignored_max_speed = maxf(env_ignored_max_speed, speed)


func _enqueue(c: Dictionary) -> void:
	_queue.append(c)


# --- разрешение очереди ---

func _attacker_key(c: Dictionary) -> int:
	var a: Object = c["attacker"]
	if a != null and is_instance_valid(a):
		return a.get_instance_id()
	var s: Object = c["striker"]
	return s.get_instance_id() if s != null and is_instance_valid(s) else 0


func _raw_damage(c: Dictionary, combo_mult: float) -> float:
	var vp: RigidBody3D = c["victim_part"]
	var target := float(c.get("target_mult", Damage.target_mult_of(vp.name)))
	if c["kind"] == "environment" and not Tuning.ENV_DAMAGE_ENABLED:
		return 0.0
	if c["kind"] == "environment" and not (c["striker"] is Weapon):
		return Damage.compute_env(float(c["mass"]), float(c["speed"]), target)
	return Damage.compute(float(c["mass"]), float(c["speed"]), float(c["body_mult"]), float(c["weapon_mult"]), combo_mult, 1.0, target, c["striker"] is Weapon)


func _resolve_queue() -> void:
	if _queue.is_empty():
		return
	var q := _queue
	_queue = []
	if doll == null or not doll.alive or not doll.can_take_damage():
		return
	# оценка урона без комбо — для сортировки
	for c in q:
		c["est"] = _raw_damage(c, 1.0)
	q.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["est"]) > float(b["est"]))
	var seen_pairs: Dictionary = {}
	for c in q:
		var vp: RigidBody3D = c["victim_part"]
		var striker: Object = c["striker"]
		if not is_instance_valid(vp) or striker == null or not is_instance_valid(striker):
			continue
		var pair := "%d:%d" % [striker.get_instance_id(), vp.get_instance_id()]
		if seen_pairs.has(pair):
			continue
		seen_pairs[pair] = true
		if float(c["est"]) <= 0.0:
			continue
		if c["kind"] == "environment" and not (striker is Weapon):
			_apply_env(c)
		else:
			_apply_hit(c)
		if not doll.alive:
			return


## Удар куклой/оружием: кулдаун пары, DOUBLE BLOW, комбо, урон, knockback, стан, FX, Match.
func _apply_hit(c: Dictionary) -> void:
	var key := _attacker_key(c)
	var striker: Object = c["striker"]
	var sid := striker.get_instance_id()
	var times: Array = _recent.get(key, [])
	var fresh: Array = []   # [{"t": float, "striker": int}] в окне кулдауна
	for e in times:
		if _time - float(e["t"]) < Tuning.PAIR_HIT_COOLDOWN_S:
			fresh.append(e)
	var double_blow := false
	if fresh.is_empty():
		pass
	elif fresh.size() == 1 and _time - float(fresh[0]["t"]) <= Tuning.DOUBLE_BLOW_WINDOW_S and int(fresh[0]["striker"]) != sid:
		double_blow = true   # второе тело того же атакующего (кисть + предплечье, молот + кисть) — DOUBLE BLOW
	else:
		_recent[key] = fresh
		return
	fresh.append({"t": _time, "striker": sid})
	_recent[key] = fresh

	var attacker: Doll = c["attacker"]
	if attacker != null and not is_instance_valid(attacker):
		attacker = null
	var ac := combat_of(attacker) if attacker != null and attacker != doll else null
	var n_prev := 0
	if ac != null:
		n_prev = ac.combo_n if _time - ac.combo_last_t <= Tuning.COMBO_WINDOW_S else 0
	var cm := Damage.combo_mult(n_prev)
	var dmg := _raw_damage(c, cm)
	if double_blow:
		dmg *= Tuning.DOUBLE_BLOW_MULT   # второе тело в том же клинче: у рэгдолла из 10 частей это норма, а не редкость
	if dmg <= 0.0:
		return
	_deliver(c, dmg, cm, double_blow, ac, n_prev + 1)


## Удар о статику/пропс: одна запись на тело в PAIR_HIT_COOLDOWN_S; более сильный контакт другой частью в DOUBLE_BLOW_WINDOW_S
## дорастает до максимума (кисть коснулась стены первой — засчитывается голова).
func _apply_env(c: Dictionary) -> void:
	var striker: Object = c["striker"]
	var key := striker.get_instance_id()
	var dmg := _raw_damage(c, 1.0)
	if dmg <= 0.0:
		return
	if _env_applied.has(key):
		var e: Dictionary = _env_applied[key]
		var age := _time - float(e["t"])
		if age < Tuning.PAIR_HIT_COOLDOWN_S:
			var applied: float = e["damage"]
			if age <= Tuning.DOUBLE_BLOW_WINDOW_S and dmg > applied + 0.5:
				e["damage"] = dmg
				_deliver(c, dmg - applied, 1.0, false, null, 0, false)
			return
	_env_applied[key] = {"t": _time, "damage": dmg}
	_deliver(c, dmg, 1.0, false, null, 0)


## Применение удара к моей кукле: зачёт атакующему (до take_damage — KO может закончить матч синхронно), take_damage,
## knockback, стан, статистика, FX, Match.on_hit.
func _deliver(c: Dictionary, dmg: float, combo_mult: float, double_blow: bool, ac: DollCombat, combo_n_new: int, fx: bool = true) -> void:
	if not doll.can_take_damage():
		return
	var vp: RigidBody3D = c["victim_part"]
	var attacker: Doll = c["attacker"]
	if attacker != null and not is_instance_valid(attacker):
		attacker = null
	var kind: String = c["kind"]
	var pos: Vector3 = c["pos"]
	var nrm: Vector3 = c["nrm"]
	var speed: float = c["speed"]
	var stun_s := Damage.stun_seconds(dmg)
	# своя команда (Doll.team, PvE-волны): стан и учтённый урон × TEAM_DAMAGE_MULT, как HP в Doll.take_damage; толчки полные
	var team_mult := doll.team_mult_for(attacker)   # своя команда: как HP в Doll.take_damage (Doll.team_damage_mult)
	stun_s *= team_mult
	# урон, который жертва реально получает: статистика, щепки, Match.on_hit (надписи, уровень удара, крит) — по нему;
	# take_damage режет сам (передаём dmg), отброс — полный (толчки своих остаются)
	var dmg_eff := dmg * team_mult
	# атакующий: статистика и комбо
	if attacker != null and attacker != doll:
		var s: Dictionary = attacker.stats
		s["damage_dealt"] = float(s["damage_dealt"]) + dmg_eff
		s["hardest_hit"] = maxf(float(s["hardest_hit"]), dmg_eff)
		s["combo_score"] = float(s["combo_score"]) + dmg_eff * combo_mult
		if kind == "weapon":
			s["weapon_hits"] = int(s["weapon_hits"]) + 1
		if ac != null:
			ac.combo_n = combo_n_new
			ac.combo_last_t = _time
			ac.hits_dealt += 1
			ac.last_damage_dealt = dmg_eff
			s["combo_max"] = maxi(int(s["combo_max"]), combo_n_new)
			ac._notify_combo()
	# жертва
	hits_taken += 1
	last_damage_taken = dmg_eff
	last_kind_taken = kind
	if combo_n != 0:   # комбо жертвы сбрасывается
		combo_n = 0
		_notify_combo()
	doll.hit_meta = {
		"speed": speed, "weapon_id": c["weapon_id"], "striker": c["striker"], "combo_mult": combo_mult, "double_blow": double_blow,
		"knockback_mult": _knockback_mult(), "stun_s": stun_s,
		"dir": c["dir"], "striker_name": String((c["striker"] as Node).name) if c["striker"] is Node else "",
	}
	doll.take_damage(dmg, attacker, vp.name, pos, nrm, kind)
	# knockback: направление от бьющего к жертве + апбиас; SD множит
	var j := Damage.knockback_impulse(dmg, _knockback_mult())
	var dir_v: Vector3 = c["dir"]
	var env := kind == "environment" and not (c["striker"] is Weapon)
	if env:
		j *= 0.5   # dir — отскок от стены (нормаль против подлёта)
	var by_doll := attacker != null and attacker != doll and not env
	# v6.2: лёгкий удар всё равно разводит кукол (RM: жертва уходит на ~1 H/с); SD множит и минимум. Добор до минимума — в торс.
	var j_min := Tuning.KNOCKBACK_MIN * _knockback_mult() if by_doll and j > 0.0 else 0.0
	var kb_dir := Damage.knockback_dir(dir_v)
	if j > 0.0 and not doll.is_broken():
		doll.apply_knockback(kb_dir * j, vp, stun_s, Vector3(dir_v.x, dir_v.y, 0.0) if by_doll else Vector3.ZERO, j_min)
	j = maxf(j, j_min)
	if by_doll and Tuning.HIT_ATTACKER_RECOIL + Tuning.HIT_ATTACKER_THRUST_LOCK_S > 0.0:
		# отдача атакующего: сближение вдоль удара гасится, он отходит на RECOIL × Δv ЦМ жертвы (и после KO — RM: бьющий
		# отлетает и висит), тяга выключена THRUST_LOCK_S — иначе 40 кг на 4–5 м/с догоняют жертву и куклы летят сцепившись
		var flat := Vector3(dir_v.x, dir_v.y, 0.0)
		attacker.apply_recoil(flat, Tuning.HIT_ATTACKER_RECOIL * j / maxf(doll.total_mass, 1.0), Tuning.HIT_ATTACKER_THRUST_LOCK_S)
	if stun_s > 0.0 and doll.alive:
		doll.stun(stun_s)
	if dmg >= Tuning.FLIGHT_TRACK_DAMAGE:
		_flight_phase = 1
		_flight_start = doll.centre_of_mass()
		_flight_t0 = _time
	# FX
	if fx and dmg_eff >= FX_MIN_DAMAGE:
		var parent: Node = match_ref if match_ref != null and is_instance_valid(match_ref) else doll.get_parent()
		if parent != null:
			# щепки летят от поверхности жертвы к бьющему (для стены — от стены)
			var away := dir_v if env else -dir_v
			var fx_nrm := nrm
			if fx_nrm.dot(away) < 0.0:
				fx_nrm = -fx_nrm
			ImpactFx.spawn_impact(parent, pos, fx_nrm, FX_STRENGTH_BASE + dmg_eff * FX_STRENGTH_PER_HP, kind)
	if match_ref != null and is_instance_valid(match_ref) and match_ref.has_method("on_hit"):
		match_ref.call("on_hit", doll, attacker, dmg_eff, kind, pos, combo_n_new if ac != null else 0, double_blow, c["weapon_id"], speed)


func _notify_combo() -> void:
	if match_ref != null and is_instance_valid(match_ref) and match_ref.has_method("on_combo"):
		match_ref.call("on_combo", doll, combo_n)


# --- тик: скорости, статистика ---

func _is_ground_body(b: Node) -> bool:
	if b is Weapon:
		return false
	if _part_doll(b) != null:
		return false
	return b is PhysicsBody3D


func _physics_process(delta: float) -> void:
	if doll == null or not _setup_done:
		return
	_time += delta
	_resolve_queue()
	# комбо истекло
	if combo_n != 0 and _time - combo_last_t > Tuning.COMBO_WINDOW_S:
		combo_n = 0
		_notify_combo()
	# земля / воздух
	_was_grounded = _grounded
	_grounded = false
	for b in _monitored:
		if not is_instance_valid(b):
			continue
		for o in (b as RigidBody3D).get_colliding_bodies():
			if _is_ground_body(o):
				_grounded = true
				break
		if _grounded:
			break
	if doll.alive:
		if not _grounded:
			doll.stats["air_time"] = float(doll.stats["air_time"]) + delta
		if _grounded and not _was_grounded and doll.is_flying():
			doll.land()
		# полёт после сильного удара
		if _flight_phase == 1:
			if not _grounded:
				_flight_phase = 2
			elif _time - _flight_t0 > FLIGHT_LEAVE_GROUND_S:
				_flight_phase = 0
		elif _flight_phase == 2:
			var dist := doll.centre_of_mass().distance_to(_flight_start)
			doll.stats["flight_distance"] = maxf(float(doll.stats["flight_distance"]), dist)
			if _grounded:
				_flight_phase = 0
		# скорость и обороты торса
		var t := doll.torso()
		doll.stats["max_speed"] = maxf(float(doll.stats["max_speed"]), t.linear_velocity.length())
		var rz := t.global_rotation.z
		_rot_acc += wrapf(rz - _prev_torso_rot, -PI, PI)
		_prev_torso_rot = rz
		if absf(_rot_acc) >= TAU:
			doll.stats["rotations"] = int(doll.stats["rotations"]) + 1
			_rot_acc -= signf(_rot_acc) * TAU
	# скорости до шага — для следующих контактов
	for b in doll.parts.values():
		if is_instance_valid(b):
			prev_vel[b] = [(b as RigidBody3D).linear_velocity, (b as RigidBody3D).angular_velocity]
	for w in get_tree().get_nodes_in_group(Weapon.GROUP):
		if w is RigidBody3D:
			prev_vel[w] = [(w as RigidBody3D).linear_velocity, (w as RigidBody3D).angular_velocity]
	_purge_ticks += 1
	if _purge_ticks >= PURGE_EVERY_TICKS:
		_purge_ticks = 0
		for k in prev_vel.keys():
			if not is_instance_valid(k):
				prev_vel.erase(k)
