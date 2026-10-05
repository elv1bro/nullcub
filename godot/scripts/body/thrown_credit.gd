## Зачёт удара схваченным / брошенным предметом (docs/plan-demo/BODY_CRAFT.md §5 «Брошенный предмет бьёт»). Узел-ребёнок
## предмета (RigidBody3D), его вешает ArmAssist.grab() и снимает сам себя через WINDOW_S после отпускания.
##
## Зачем отдельно: DollCombat считает пропс «окружением» (kind environment), а урон окружения выключен (Tuning.ENV_DAMAGE_ENABLED =
## false, решение автора 28.09) — брошенный ящик сам по себе никого не бьёт. doll_combat.gd не трогаем: удар засчитывается здесь,
## через публичный Doll.take_damage(..., kind "weapon"), attacker = бросивший. У жертвы DollCombat тот же контакт молча
## игнорирует (env), двойного урона нет.
##
## Как считается (как DollCombat для оружия): на время зачёта у предмета включён contact_monitor (прежние значения возвращаются);
## в body_entered — часть живой чужой куклы → скорость точки контакта предмета (v + ω × r, по скоростям ДО шага физики — они
## пишутся в _physics_process) и части жертвы (DollCombat.prev_vel, иначе текущая); v = min(|v_rel · n|, max собственных по n);
## бьёт, только если предмет быстрее части (жертва, сама налетевшая на ящик, — не удар). Урон Damage.compute(масса предмета, v,
## BodyMult 1, WeaponMult PROP_WEAPON_MULT, TargetMult — в голову ×HEAD_HIT_MULT), масса — как у оружия: с 29.09 без MASS_CAP,
## мягкий потолок Tuning.WEAPON_MASS_SOFT_CAP (Damage.weapon_mass: ящик 10 кг — 10 кг, 30-кг хлам — 17.3 кг).
## Применяется в следующем _physics_process (в коллбэке физики тела не трогаем): статистика атакующего (damage_dealt, hardest_hit,
## weapon_hits), hit_meta, take_damage, отброс Damage.knockback_impulse (+KNOCKBACK_MIN, как удар куклой), стан Damage.stun_seconds,
## щепки ImpactFx, Match.on_hit (надписи, hit_feel, HUD). Пока Match не в бою (combat_active = false) — не бьёт.
## Одна жертва — не чаще VICTIM_COOLDOWN_S; своя кукла не бьётся; пока предмет держат, он тоже засчитывается держащему.
class_name ThrownCredit
extends Node

const WINDOW_S := 2.0              # столько секунд после отпускания предмет засчитывается бросившему (контракт §5: ~2 с)
const VICTIM_COOLDOWN_S := 0.5     # одна жертва от одного броска — не чаще (ящик, лёгший на куклу, не бьёт каждый тик)
const PROP_WEAPON_MULT := 1.0      # WeaponMult пропса: урон только от массы (Damage.weapon_mass) и скорости — ящик 10 кг на 4 м/с ≈ 24 HP
const MAX_CONTACTS := 8            # как DollCombat.MAX_CONTACTS: лежащий на полу ящик держит 4 точки, новый контакт не вытесняется
const FX_STRENGTH_BASE := 4.0      # как DollCombat: щепки ∝ урону
const FX_STRENGTH_PER_HP := 0.4
const WEAPON_ID_PREFIX := "prop:"  # hit_meta / KoRecord weapon_id = "prop:<имя узла предмета>"

signal hit_delivered(victim: Doll, damage: float, speed: float)

var item: RigidBody3D
## Кому засчитывается (Doll). Невалиден — зачёт снимается.
var thrower: Node = null
var held := true
var released_at := -1.0
## Засчитанные удары: {victim, part, damage, speed, t, since_release}.
var hits: Array = []
var _time := 0.0
var _prev_lv := Vector3.ZERO
var _prev_av := Vector3.ZERO
var _saved_monitor := false
var _saved_max_contacts := 0
var _victim_t: Dictionary = {}     # victim instance id -> время последнего удара
var _queue: Array = []
var _done := false


## Повесить зачёт на предмет (или перезарядить уже висящий: подобрал снова — окно заново, держит новый хозяин).
static func attach(target: RigidBody3D, by: Node) -> ThrownCredit:
	for c in target.get_children():
		if c is ThrownCredit and not (c as ThrownCredit)._done:
			var tc := c as ThrownCredit
			tc.thrower = by
			tc.held = true
			tc.released_at = -1.0
			return tc
	var n := ThrownCredit.new()
	n.name = "ThrownCredit"
	n.thrower = by
	target.add_child(n)
	return n


## Зачёт у предмета (null — нет).
static func of(target: Node) -> ThrownCredit:
	if target == null:
		return null
	for c in target.get_children():
		if c is ThrownCredit and not (c as ThrownCredit)._done:
			return c
	return null


func _ready() -> void:
	item = get_parent() as RigidBody3D
	if item == null:
		push_error("ThrownCredit must be a child of RigidBody3D")
		_done = true
		queue_free()
		return
	_saved_monitor = item.contact_monitor
	_saved_max_contacts = item.max_contacts_reported
	item.contact_monitor = true
	item.max_contacts_reported = maxi(item.max_contacts_reported, MAX_CONTACTS)
	item.body_entered.connect(_on_body_entered)
	_prev_lv = item.linear_velocity
	_prev_av = item.angular_velocity


func _exit_tree() -> void:
	_restore()


## Отпустили (бросок): WINDOW_S секунд предмет ещё засчитывается бросившему.
func release() -> void:
	held = false
	released_at = _time


## Кому засчитать удар сейчас (Doll | null): держащему, иначе бросившему в окне WINDOW_S.
func attacker() -> Node:
	if _done or thrower == null or not is_instance_valid(thrower):
		return null
	if held or (released_at >= 0.0 and _time - released_at <= WINDOW_S):
		return thrower
	return null


func _physics_process(delta: float) -> void:
	if _done:
		return
	_time += delta
	_resolve_queue()
	if item == null or not is_instance_valid(item):
		return
	# скорости ДО шага физики — для контактов этого шага (body_entered приходит после решения, скорости уже погашены)
	_prev_lv = item.linear_velocity
	_prev_av = item.angular_velocity
	if thrower == null or not is_instance_valid(thrower) or (not held and released_at >= 0.0 and _time - released_at > WINDOW_S):
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	_restore()
	queue_free()


func _restore() -> void:
	if item == null or not is_instance_valid(item):
		return
	if item.body_entered.is_connected(_on_body_entered):
		item.body_entered.disconnect(_on_body_entered)
	item.contact_monitor = _saved_monitor
	item.max_contacts_reported = _saved_max_contacts


func _match() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("match")


func _on_body_entered(other: Node) -> void:
	if _done or item == null or not is_instance_valid(item):
		return
	var by := attacker() as Doll
	if by == null:
		return
	var part := other as RigidBody3D
	if part == null:
		return
	var victim := part.get_parent() as Doll
	if victim == null or victim == by or not victim.alive:
		return
	var m := _match()
	if m != null and m.has_method("combat_active") and not bool(m.call("combat_active")):
		return
	# точка и нормаль контакта из состояния предмета (координаты мировые, как в DollCombat), иначе — линия центров
	var pos := part.global_position
	var nrm := Vector3.ZERO
	var found := false
	var st := PhysicsServer3D.body_get_direct_state(item.get_rid())
	var com := item.global_position
	if st != null:
		com = item.global_position + st.center_of_mass
		var oid := part.get_instance_id()
		for i in st.get_contact_count():
			if st.get_contact_collider_id(i) == oid:
				pos = st.get_contact_local_position(i)
				nrm = st.get_contact_local_normal(i)
				found = true
				break
	if not found:
		var d := part.global_position - item.global_position
		d.z = 0.0
		nrm = d.normalized() if d.length_squared() > 1e-6 else Vector3.RIGHT
	nrm.z = 0.0
	if nrm.length_squared() < 1e-6:
		nrm = Vector3.RIGHT
	nrm = nrm.normalized()
	var v_item := _prev_lv + _prev_av.cross(pos - com)
	var v_part := part.linear_velocity
	var w_part := part.angular_velocity
	if DollCombat.prev_vel.has(part):
		var e: Array = DollCombat.prev_vel[part]
		v_part = e[0]
		w_part = e[1]
	v_part += w_part.cross(pos - part.global_position)
	if v_item.length_squared() <= v_part.length_squared():
		return   # часть сама налетела на предмет — это не удар предметом
	var rel := v_item - v_part
	var closing := absf(rel.dot(nrm)) if found else rel.length()
	var own := maxf(absf(v_item.dot(nrm)), absf(v_part.dot(nrm))) if found else maxf(v_item.length(), v_part.length())
	closing = minf(closing, own)
	var dmg := Damage.compute(item.mass, closing, 1.0, PROP_WEAPON_MULT, 1.0, 1.0, Damage.target_mult_of_body(part), true)
	if dmg <= 0.0:
		return
	var key := victim.get_instance_id()
	if _time - float(_victim_t.get(key, -100.0)) < VICTIM_COOLDOWN_S:
		return
	_victim_t[key] = _time
	var dir := Vector3(rel.x, rel.y, 0.0)
	if dir.length_squared() < 1e-6:
		dir = part.global_position - item.global_position
	_queue.append({"victim": victim, "part": part, "attacker": by, "damage": dmg, "speed": closing, "pos": pos, "nrm": nrm, "dir": dir})


func _resolve_queue() -> void:
	if _queue.is_empty():
		return
	var q := _queue
	_queue = []
	for c in q:
		_deliver(c)


## Применение удара (вне коллбэка физики): как DollCombat._deliver для kind weapon, без комбо и отдачи атакующего.
func _deliver(c: Dictionary) -> void:
	var victim: Doll = c["victim"]
	var part: RigidBody3D = c["part"]
	var by: Doll = c["attacker"]
	if not is_instance_valid(victim) or not is_instance_valid(part) or not victim.can_take_damage():
		return
	if by != null and not is_instance_valid(by):
		by = null
	var dmg: float = c["damage"]
	var speed: float = c["speed"]
	var pos: Vector3 = c["pos"]
	var nrm: Vector3 = c["nrm"]
	var dir: Vector3 = c["dir"]
	var m := _match()
	var kb_mult := float(m.call("knockback_mult")) if m != null and m.has_method("knockback_mult") else 1.0
	var stun_s := Damage.stun_seconds(dmg)
	var weapon_id := WEAPON_ID_PREFIX + String(item.name) if is_instance_valid(item) else WEAPON_ID_PREFIX
	if by != null:
		var s: Dictionary = by.stats
		s["damage_dealt"] = float(s["damage_dealt"]) + dmg
		s["hardest_hit"] = maxf(float(s["hardest_hit"]), dmg)
		s["combo_score"] = float(s["combo_score"]) + dmg
		s["weapon_hits"] = int(s["weapon_hits"]) + 1
	victim.hit_meta = {"speed": speed, "weapon_id": weapon_id, "striker": item, "combo_mult": 1.0, "double_blow": false,
		"knockback_mult": kb_mult, "stun_s": stun_s, "thrown": not held}
	victim.take_damage(dmg, by, String(part.name), pos, nrm, "weapon")
	hits.append({"victim": victim, "part": String(part.name), "damage": dmg, "speed": speed, "t": _time,
		"since_release": _time - released_at if released_at >= 0.0 else -1.0})
	hit_delivered.emit(victim, dmg, speed)
	var j := Damage.knockback_impulse(dmg, kb_mult)
	var j_min := Tuning.KNOCKBACK_MIN * kb_mult
	if j > 0.0 and not victim.is_broken():
		victim.apply_knockback(Damage.knockback_dir(dir) * j, part, stun_s, dir, j_min)
	if stun_s > 0.0 and victim.alive:
		victim.stun(stun_s)
	if dmg >= 1.0:
		var fx_parent: Node = m if m != null else victim.get_parent()
		if fx_parent != null:
			var fx_nrm := nrm if nrm.dot(-dir) >= 0.0 else -nrm   # щепки — от жертвы навстречу предмету
			ImpactFx.spawn_impact(fx_parent, pos, fx_nrm, FX_STRENGTH_BASE + dmg * FX_STRENGTH_PER_HP, "weapon")
	if m != null and m.has_method("on_hit"):
		m.call("on_hit", victim, by, dmg, "weapon", pos, 0, false, weapon_id, speed)
