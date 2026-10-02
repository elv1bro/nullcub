## Разборщик (Scrapling, LORE.md: «разбирал сломанных кукол → откручивает у тебя деталь и удирает с ней, от удара роняет»).
## Мелкая лёгкая кукла из хлама (data/enemies/scrapling.tres: бочонок-ядро, испуганная голова, короткие ноги, 22 кг, max_hp 25 — после «агрессии» 29.09 был 40),
## две руки-хваталки — по ArmAssist на каждую кисть (узлы ArmL / ArmR сцены: цель руки — set_target_override, хват — пружина
## ArmAssist.grab, та же, что у игрока). Программа атакует БИЛД игрока, а не HP:
##   choose    — что украсть у ближайшего игрока (victim): 1) деталь (Doll.detach_part, хук сессии куклы) — кисть, стопа, предплечье,
##               голень (DETACH_BASES по порядку); 2) оружие из его кисти (WeaponPickup); 3) оружие, лежащее рядом с ним
##               (loose_weapon_radius); 4) иначе — nibble (щипок: наскок и отход, как бот match_probe);
##   approach  — быстро (approach_input) к точке в 1.1 м от цели кражи со своей стороны, чуть выше; последние 3 м — не быстрее
##               close_speed (не таранить жертву: урон оружия считается и по скорости того, кто в него влетел);
##   telegraph — telegraph_s (0.4 с): обе руки вскинуты вверх, глаза вспыхивают, стрёкот, надпись PARTS! / MINE!;
##   lunge     — ≤ lunge_s, не быстрее lunge_speed: ближняя рука тянется к цели (ArmAssist); кисть в grab_reach_m от детали — хват
##               (unscrew), в steal_reach_m от оружия — оружие выдёргивается (Weapon.drop у игрока → WeaponPickup.attach себе);
##               промах — retreat;
##   unscrew   — unscrew_s (1.0 с) висит на детали, дёргая её (трещотка: звук, вспышка и щепки в точке хвата раз в 0.25 с, надпись
##               UNSCREW!); удержался — detach_part(деталь, себя), деталь в руке → flee. Сорвался (игрок вырвался тягой: пружина
##               ArmAssist рвётся при растяжении > 0.45 м) — retreat;
##   flee      — «ЦАП!»: отскок от жертвы yank_speed (Doll.apply_recoil), YANK_GHOST_S без столкновений с ней, ввод без сглаживания
##               и короткое бегство вбок и вверх flee_s (1.2 с) — потом снова в драку: украденное оружие отбрасывает прочь от
##               игрока (toss_weapon), деталь носит с собой (ударил вора — уронил);
##   nibble    — щипок, если красть нечего или к цели кражи не подобрался за approach_timeout_s: подход на nibble_standoff, телеграф
##               «!», бросок не быстрее dart_speed, короткий отход retreat_s (0.45 с) — и снова;
##   любой удар ≥ drop_min_damage (и стан, и KO) — роняет добычу (ArmAssist.release, WeaponPickup.drop_all) → stagger.
## Лимит разборки (чтобы не разобрать игрока за 5 с): одна деталь за захват; кулдаун detach_cooldown_s (12 с) на жертву — общий
## для всех Разборщиков («арена откручивает одну деталь за раз»); не больше max_detach_per_victim (3) деталей с одной куклы; никогда —
## голова, торс, плечо, бедро и ПОСЛЕДНЯЯ кисть (оружие держать всегда есть чем); не трогается рука, которой игрок водит мышью
## (ArmAssist.part_name жертвы вместе с предплечьем: иначе мышь таскала бы оторванную кисть). Остальное время — кража оружия и щипки.
class_name ScraplingBrain
extends EnemyBrain

const DETACH_BASES := ["Hand", "Foot", "LowerArm", "LowerLeg"]
const ARMS_UP_SHOULDER := 150.0
const ARMS_UP_ELBOW := 30.0
const STAND_MIN_Y := 0.85                 # ЦМ Разборщика, стоящего на полу
const RATCHET_S := 0.25                   # щелчок трещотки при откручивании (вспышка в точке хвата)
const YANK_GHOST_S := 0.4                 # после кражи вор и жертва не сталкиваются столько (см. _ghost_from)

@export var approach_input := 0.95
@export var lunge_input := 1.0
@export var lunge_s := 0.9
## Кисть в стольких метрах от детали / оружия — хват (как ArmAssist.GRAB_RADIUS у игрока).
@export var grab_reach_m := 0.4
@export var steal_reach_m := 0.45
## Бросок и подход вплотную — не быстрее (м/с): врезаться в молот игрока на 4–5 м/с — 10–20 HP себе же.
@export var lunge_speed := 2.6
## Отскок от жертвы в момент кражи (м/с).
@export var yank_speed := 5.0
@export var close_speed := 3.0
@export var unscrew_s := 1.0
@export var detach_cooldown_s := 12.0
@export var max_detach_per_victim := 3
## Бегство с добычей — коротко (отзыв автора 29.09: «пытаются убежать, будто не видят»): flee_s, без рывка, потом снова в драку
## (оружие отброшено — toss_weapon, деталь носит с собой: ударил вора — уронил). Раньше: 5 с с рывком и keepaway в 6 м с
## деталью — вор висел на краю арены до конца волны.
@export var flee_s := 1.2
@export var flee_dash := false
## Украденное оружие после бегства вор отбрасывает прочь от игрока (toss_speed) и возвращается драться голыми руками: молот 6 кг
## в руке Разборщика на щипке 5.5 м/с — 15–20 HP (бот-игрок с ним умирал на волне 1–2); деталь — носит с собой (урона почти нет).
@export var toss_weapon := true
@export var toss_speed := 4.0
## Не вышло за approach_timeout_s подобраться к цели кражи (или она ушла) — щипок вместо вечной погони за деталью.
@export var approach_timeout_s := 3.0
@export var nibble_standoff := 1.5
@export var nibble_dart_s := 0.55
## Щипок — не таран: скорость броска ограничена (м/с). Полной тягой торс-бочонок влетал на 7–8 м/с (≈ 10 HP за щипок, два
## Разборщика снимали боту-игроку 25–50 HP за волну 1 — вор становился бойцом); с 4.5 м/с щипок ≈ 3–6 HP.
@export var dart_speed := 4.8
@export var retreat_s := 0.6
@export var drop_min_damage := 1.0
## Лежащее оружие крадёт, только если оно у самой жертвы (не бегает за ним по арене).
@export var loose_weapon_radius := 2.5

## Что сейчас добывает: "part" | "weapon" | "nibble"; цель кражи (тело детали или оружие) и имя детали у жертвы.
var mode := ""
var goal_body: RigidBody3D = null
var goal_part := ""
var victim: Doll = null
## Добыча в руке (оторванная деталь или оружие) и её вид.
var loot: RigidBody3D = null
var loot_kind := ""
var arms: Array = []                    # ArmAssist по кистям
var arm: ArmAssist = null               # рука текущего броска / хвата
## Для проб: кражи по видам, уронено от ударов, срывы хвата, длительности телеграфов перед броском.
var steals := {"part": 0, "weapon": 0}
var drops := 0
var slips := 0
var telegraph_durations: Array = []
var last_steal_t := -1.0
## Для проб: ближе всего кисть подошла к цели в каждом броске (м).
var lunge_min_dist: Array = []
var _lunge_best := INF
var _telegraph_t0 := -1.0
var _rest: Dictionary = {}
var _hit_seen := false

## Журнал откручивания по жертвам (общий для всех Разборщиков): instance id -> {"t": сим-время, "n": деталей}.
static var victim_log: Dictionary = {}


static func sim_time() -> float:
	return float(Engine.get_physics_frames()) / float(maxi(Engine.physics_ticks_per_second, 1))


func _brain_ready() -> void:
	_rest = doll.get_pose()
	for c in doll.get_children():
		if c is ArmAssist:
			arms.append(c)


func _wp() -> WeaponPickup:
	for c in doll.get_children():
		if c is WeaponPickup:
			return c
	return null


func holding_loot() -> bool:
	if loot == null or not is_instance_valid(loot):
		return false
	if loot_kind == "weapon":
		return (loot as Weapon).is_held() and (loot as Weapon).holder == _wp()
	for a in arms:
		if (a as ArmAssist).held == loot:
			return true
	return false


# --- выбор добычи ---

func _pick_goal() -> void:
	mode = "nibble"
	goal_body = null
	goal_part = ""
	victim = target
	if victim == null:
		return
	var parts := detach_candidates(victim)
	if not parts.is_empty():
		mode = "part"
		goal_part = parts[0]
		goal_body = victim.parts[goal_part]
		return
	var w := _victim_weapon(victim)
	if w == null:
		w = _loose_weapon_near(com2(victim))
	if w != null:
		mode = "weapon"
		goal_body = w
		return


## Детали жертвы, которые можно открутить сейчас (по предпочтению DETACH_BASES, ближние раньше). Пусто — нельзя (кулдаун, лимит,
## хука detach_part нет).
func detach_candidates(v: Doll) -> Array:
	if v == null or not v.alive or not v.has_method("detach_part"):
		return []
	var e: Dictionary = victim_log.get(v.get_instance_id(), {"t": -1e9, "n": 0})
	if int(e["n"]) >= max_detach_per_victim or sim_time() - float(e["t"]) < detach_cooldown_s:
		return []
	var hands := 0
	for pn in v.parts.keys():
		if Doll.part_base_name(String(pn)) == "Hand":
			hands += 1
	var mouse := _mouse_part(v)
	var me := my_pos()
	var scored: Array = []
	for bi in range(DETACH_BASES.size()):
		for pn in v.parts.keys():
			var name_ := String(pn)
			if Doll.part_base_name(name_) != DETACH_BASES[bi]:
				continue
			var sub := _subtree(v, name_)
			if mouse != "" and sub.has(mouse):
				continue   # рука-мышь игрока (и её предплечье)
			var takes_hand := false
			for s in sub:
				if Doll.part_base_name(String(s)) == "Hand":
					takes_hand = true
			if takes_hand and hands <= 1:
				continue   # последняя кисть — не трогаем
			var b := v.parts[name_] as RigidBody3D
			var d := me.distance_to(Vector2(b.global_position.x, b.global_position.y))
			scored.append([float(bi) * 100.0 + d, name_])   # вид детали важнее расстояния: кисть раньше стопы
	scored.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var out: Array = []
	for s in scored:
		out.append(s[1])
	return out


## Имена тел поддерева части (она и всё, что висит на ней по суставам жертвы).
static func _subtree(v: Doll, part_name: String) -> Array:
	var root := v.parts.get(part_name) as Node
	var out: Array = [part_name]
	if root == null:
		return out
	var bodies: Array = [root]
	var i := 0
	while i < bodies.size():
		for j in v.joints.values():
			var jj := j as Generic6DOFJoint3D
			if jj == null or not is_instance_valid(jj):
				continue
			if jj.get_node_or_null(jj.node_a) == bodies[i]:
				var c := jj.get_node_or_null(jj.node_b)
				if c != null and not bodies.has(c):
					bodies.append(c)
					out.append(String(c.name))
		i += 1
	return out


## Деталь, которой жертва водит мышью (ArmAssist.part_name), "" — нет.
static func _mouse_part(v: Doll) -> String:
	for c in v.get_children():
		if c is ArmAssist:
			return String((c as ArmAssist).part_name)
	return ""


static func _victim_weapon(v: Doll) -> Weapon:
	for c in v.get_children():
		if c is WeaponPickup:
			for hn in (c as WeaponPickup).held.keys():
				var w := (c as WeaponPickup).weapon_in(String(hn))
				if w != null and is_instance_valid(w):
					return w
	return null


func _loose_weapon_near(p: Vector2) -> Weapon:
	var best: Weapon = null
	var best_d := loose_weapon_radius
	for n in get_tree().get_nodes_in_group(Weapon.GROUP):
		var w := n as Weapon
		if w == null or w.is_held() or not w.is_inside_tree():
			continue
		if pit_rect().size.x > 0.0 and arena != null and arena.has_method("is_in_pit") and bool(arena.call("is_in_pit", w.global_position)):
			continue
		var d := p.distance_to(Vector2(w.global_position.x, w.global_position.y))
		if d < best_d:
			best_d = d
			best = w
	return best


func _goal_valid() -> bool:
	if goal_body == null or not is_instance_valid(goal_body) or not goal_body.is_inside_tree():
		return false
	match mode:
		"part":
			return victim != null and is_instance_valid(victim) and victim.alive and victim.parts.get(goal_part) == goal_body
		"weapon":
			var w := goal_body as Weapon
			return w != null and (not w.is_held() or w.holder != _wp())
	return true


func _goal_point() -> Vector2:
	if goal_body != null and is_instance_valid(goal_body):
		var g := goal_body.global_position
		if goal_body is Weapon:
			# середина оружия (хват — у кисти игрока; тянуться к древку/головке безопаснее)
			var w := goal_body as Weapon
			g = w.to_global(w.grip_local + Vector3(maxf(w.length, 0.4) * 0.6, 0.0, 0.0))
		# цель движется: чужая часть — с упреждением по её скорости (реакция — как у восприятия цели)
		var v := goal_body.linear_velocity
		return Vector2(g.x, g.y) + Vector2(v.x, v.y) * (lead_s * 0.5)
	return predicted()


# --- позы и руки ---

func _arms_up(on: bool) -> void:
	var pose := {}
	for hn in ["Hand_L", "Hand_R"]:
		var aj := arm_joints(hn)
		var s := 1.0 if hn.ends_with("_L") else -1.0
		if aj.has("Shoulder"):
			var sh := String(aj["Shoulder"])
			pose[sh] = s * ARMS_UP_SHOULDER if on else float(_rest.get(sh, s * 85.0))
		if aj.has("Elbow"):
			var el := String(aj["Elbow"])
			pose[el] = s * ARMS_UP_ELBOW if on else float(_rest.get(el, s * 10.0))
	if not pose.is_empty():
		doll.set_pose(pose, 0.15)


## Рука, чьё плечо ближе к точке p.
func _nearest_arm(p: Vector2) -> ArmAssist:
	var best: ArmAssist = null
	var best_d := INF
	for a in arms:
		var aa := a as ArmAssist
		if aa.part == null or not is_instance_valid(aa.part) or not doll.parts.has(aa.part_name):
			continue
		var r := aa.root_point()
		var d := Vector2(r.x, r.y).distance_to(p)
		if d < best_d:
			best_d = d
			best = aa
	return best


func _arms_clear() -> void:
	for a in arms:
		(a as ArmAssist).clear_target_override()


func _drop_loot(reason: String) -> void:
	var had := holding_loot()
	for a in arms:
		var aa := a as ArmAssist
		if aa.is_holding():
			aa.release(reason)
	var wp := _wp()
	if wp != null:
		wp.drop_all()
	if had:
		drops += 1
		if look != null:
			look.play("drop")
	loot = null
	loot_kind = ""


func _silenced(why: String) -> void:
	_drop_loot(why)
	_arms_clear()
	_arms_up(false)
	_telegraph_t0 = -1.0


func _on_damaged(amount: float, attacker: Node, _part: String, _pos: Vector3, _kind: String) -> void:
	if amount < drop_min_damage or attacker == doll:
		return
	_hit_seen = true
	if holding_loot() or state == "unscrew":
		_drop_loot("hit")
		_arms_clear()
		go("stagger")


# --- поведение ---

func _think(_delta: float) -> void:
	var me := my_pos()
	if loot != null and not holding_loot() and state in ["flee", "approach", "telegraph", "dart", "retreat"] and loot_kind != "":
		loot = null   # добычу отобрали/сорвалась
		loot_kind = ""
		go("choose")
	match state:
		"idle", "stagger":
			set_alert(0.0)
			want = steer(me, 0.35)
			if state_t >= 0.45:
				go("choose")
		"choose":
			set_alert(0.0)
			_arms_clear()
			if target == null:
				want = steer(me, 0.3)
				return
			if holding_loot():
				mode = "nibble"   # с добычей в руке — снова в драку (оружием — по хозяину, деталь — носит, ударят — уронит)
				go("approach")
				return
			_pick_goal()
			go("approach")
		"approach":
			set_alert(0.0)
			if target == null:
				go("choose")
				return
			if mode == "nibble":
				_nibble_approach(me)
				return
			if not _goal_valid():
				go("choose")
				return
			if state_t > approach_timeout_s:
				mode = "nibble"   # не подобрался к детали/оружию — бьёт, а не кружит
				return
			var gp := _goal_point()
			var side := signf(me.x - gp.x) if absf(me.x - gp.x) > 0.1 else 1.0
			var stand := gp + Vector2(side * 1.1, 0.3)
			stand.y = maxf(stand.y, STAND_MIN_Y)   # цель лежит на полу — стоим рядом, а не в полу
			# издалека — полной тягой, последние 3 м — с ограничением скорости (не таранить жертву и её оружие)
			want = steer(stand, approach_input) if me.distance_to(stand) > 3.0 else steer_speed(stand, close_speed, approach_input)
			if (me.distance_to(gp) < 1.9 or me.distance_to(stand) < 0.5) and state_t > 0.25:
				_start_telegraph("PARTS!" if mode == "part" else "MINE!")
		"telegraph":
			set_alert(1.0)
			want = steer(me, 0.5)
			if mode != "nibble" and not _goal_valid():
				_arms_up(false)
				go("choose")
				return
			if state_t >= telegraph_s:
				telegraph_durations.append(snappedf(_time - _telegraph_t0, 0.001))
				_arms_up(false)
				note_attack()
				if mode == "nibble":
					go("dart")
				else:
					arm = _nearest_arm(_goal_point())
					_lunge_best = INF
					go("lunge")
		"lunge":
			set_alert(0.8)
			if not _goal_valid() or arm == null:
				go("retreat")
				return
			var gp := _goal_point()
			arm.set_target_override(Vector3(gp.x, gp.y, 0.0))
			want = steer_speed(gp, lunge_speed, lunge_input)
			var grip := arm.grip_global()
			var cp := arm.closest_point(goal_body, grip)
			var dist := Vector2(grip.x - cp.x, grip.y - cp.y).length()
			_lunge_best = minf(_lunge_best, dist)
			if mode == "part" and dist <= grab_reach_m:
				if arm.grab(goal_body):
					telegraph("UNSCREW!", unscrew_s + 0.2, "ratchet", Color(1.0, 0.35, 0.15))
					go("unscrew")
					return
			elif mode == "weapon" and dist <= steal_reach_m:
				if _steal_weapon(goal_body as Weapon, arm.part_name):
					_start_flee()
					return
			if state_t >= lunge_s:
				lunge_min_dist.append(snappedf(_lunge_best, 0.01))
				_arms_clear()
				go("retreat")
		"unscrew":
			set_alert(0.9)
			if arm == null or not arm.is_holding() or arm.held != goal_body:
				slips += 1
				_arms_clear()
				go("retreat")
				return
			if victim == null or not is_instance_valid(victim) or not victim.alive or victim.parts.get(goal_part) != goal_body:
				_drop_loot("gone")
				go("retreat")
				return
			# висит на детали и выкручивает: держится у неё с отступом от торса жертвы, дёргает поперёк
			var pp := Vector2(goal_body.global_position.x, goal_body.global_position.y)
			var away := (pp - com2(victim))
			away = away.normalized() if away.length() > 0.01 else Vector2(signf(me.x - pp.x), 0.0)
			var perp := Vector2(-away.y, away.x) * (0.35 if fmod(state_t * 4.0, 1.0) < 0.5 else -0.35)
			arm.set_target_override(Vector3(pp.x, pp.y, 0.0))
			want = steer(pp + away * 0.55, 0.55) + perp
			# щелчки трещотки видно: вспышка и щепки в точке хвата раз в RATCHET_S (звук — EnemyLook «ratchet»)
			if int(state_t / RATCHET_S) != int((state_t - get_physics_process_delta_time()) / RATCHET_S):
				var gp3 := arm.grip_global()
				ImpactFx.spawn_impact(doll.get_parent(), Vector3(gp3.x, gp3.y, 0.15), Vector3(away.x, away.y, 0.0), 3.5, "weapon")
			if state_t >= unscrew_s:
				_finish_unscrew()
		"flee":
			set_alert(0.2)
			_arms_clear()
			if not holding_loot():
				go("choose")
				return
			var fg := _flee_goal(me)
			want = steer(fg, 1.0)
			if me.y < 1.6:
				# с пола — сперва вверх (по полу бегство упирается в тележки и ящики Свалки)
				want = Vector2(signf(fg.x - me.x) * 0.55, 0.85)
			if flee_dash and state_t < 1.2:
				dash()   # запрос держится, пока ввод не развернётся от жертвы (EnemyBrain._tick_dash) и рывок не перезарядится
			if state_t >= flee_s:
				if loot_kind == "weapon" and toss_weapon:
					_toss_weapon(me)
				mode = "nibble"
				go("approach")
		"dart":
			set_alert(0.7)
			var tp := predicted()
			var to := tp - me
			want = steer_speed(tp + to.normalized() * 0.8, dart_speed, 1.0)
			var hit := doll.thrust_lock_until > float(doll.get("_time"))
			if state_t >= nibble_dart_s or (hit and state_t > 0.08):
				go("retreat")
		"retreat":
			set_alert(0.0)
			_arms_clear()
			var th := _threat_pos()
			var away := (me - th)
			away = away.normalized() if away.length() > 0.01 else Vector2.RIGHT
			want = steer(me + away * 2.5 + Vector2(0.0, 0.6), 0.9)
			if state_t >= retreat_s:
				go("choose")


func _separation_weight() -> float:
	return 0.3 if state in ["lunge", "unscrew", "dart"] or near_target(3.0) else 1.0


func _nibble_approach(me: Vector2) -> void:
	var tp := predicted()
	var side := signf(me.x - tp.x) if absf(me.x - tp.x) > 0.1 else 1.0
	var stand := tp + Vector2(side * nibble_standoff, 0.2)
	stand.y = maxf(stand.y, STAND_MIN_Y)
	want = steer(stand, approach_input)
	if (me.distance_to(stand) < 0.9 or me.distance_to(tp) < nibble_standoff + 0.6) and state_t > 0.2:
		_start_telegraph("!")


func _start_telegraph(text: String) -> void:
	_telegraph_t0 = _time
	go("telegraph")
	_arms_up(true)
	telegraph(text, telegraph_s + 0.2, "warn_grab", Color(1.0, 0.42, 0.2) if text != "MINE!" else Color(1.0, 0.8, 0.25))


## Отбросить украденное оружие в сторону от ближайшего игрока (вверх-вбок): лежит на арене — его можно забрать обратно.
func _toss_weapon(me: Vector2) -> void:
	var w := loot as Weapon
	var wp := _wp()
	if w == null or not is_instance_valid(w) or wp == null:
		return
	wp.drop_all()
	var away := me - _threat_pos()
	away = away.normalized() if away.length() > 0.01 else Vector2.RIGHT
	w.linear_velocity = Vector3(away.x, 0.0, 0.0) * toss_speed + Vector3(0.0, toss_speed * 0.5, 0.0)
	w.angular_velocity = Vector3(0.0, 0.0, 6.0 * signf(away.x))
	loot = null
	loot_kind = ""
	counters["toss"] = int(counters.get("toss", 0)) + 1


func _steal_weapon(w: Weapon, hand: String) -> bool:
	if w == null or not is_instance_valid(w):
		return false
	var wp := _wp()
	if wp == null or wp.is_holding(hand):
		return false
	if w.is_held():
		w.drop()   # у игрока: WeaponPickup.drop_weapon
	if w.is_held():
		return false
	wp.hold_angle_deg = 90.0
	if not wp.attach(hand, w):
		return false
	loot = w
	loot_kind = "weapon"
	steals["weapon"] = int(steals["weapon"]) + 1
	last_steal_t = _time
	if look != null:
		look.play("yoink")
	return true


func _finish_unscrew() -> void:
	if victim == null or not victim.has_method("detach_part"):
		return
	# правила могли измениться, пока висел (другой Разборщик открутил деталь раньше)
	if not detach_candidates(victim).has(goal_part):
		_drop_loot("rules")
		go("retreat")
		return
	var body: Variant = victim.call("detach_part", goal_part, doll)
	if not body is RigidBody3D:
		_drop_loot("detach_failed")
		go("retreat")
		return
	var e: Dictionary = victim_log.get(victim.get_instance_id(), {"t": -1e9, "n": 0})
	victim_log[victim.get_instance_id()] = {"t": sim_time(), "n": int(e["n"]) + 1}
	loot = body
	loot_kind = "part"
	steals["part"] = int(steals["part"]) + 1
	last_steal_t = _time
	if look != null:
		look.play("yoink")
	_start_flee()


func _start_flee() -> void:
	_arms_clear()
	go("flee")
	# «ЦАП!» — отскок с добычей: скорость ЦМ к жертве сразу −yank_speed (Doll.apply_recoil, как отдача удара, без блокировки тяги).
	# Без него вор, догоняемый инерцией броска, ещё полсекунды тёрся о жертву и ловил отдачу своих же касаний.
	var th := _threat_pos()
	var to := th - my_pos()
	if to.length() > 0.01:
		doll.apply_recoil(Vector3(to.x, to.y, 0.0).normalized(), yank_speed, 0.0)
	snap_input(0.25)
	_ghost_from(victim if victim != null else _nearest_player(), YANK_GHOST_S)
	if flee_dash:
		dash()


## На миг кражи вор и жертва не сталкиваются (исключения коллизий на seconds): в момент «ЦАП!» кисть вора внутри кисти жертвы,
## и Jolt расталкивал их рывком, а касание засчитывалось ударом — отдача (thrust_lock) и стан сбивали бегство в ~половине краж.
func _ghost_from(v: Doll, seconds: float) -> void:
	if v == null or not is_instance_valid(v):
		return
	var mine: Array = doll.parts.values()
	var theirs: Array = v.parts.values()
	for a in mine:
		for b in theirs:
			(a as RigidBody3D).add_collision_exception_with(b)
	var wr_me: WeakRef = weakref(doll)
	var wr_v: WeakRef = weakref(v)
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		var d0: Doll = wr_me.get_ref() as Doll
		var d1: Doll = wr_v.get_ref() as Doll
		if d0 == null or d1 == null:
			return
		for a in d0.parts.values():
			for b in d1.parts.values():
				if is_instance_valid(a) and is_instance_valid(b):
					(a as RigidBody3D).remove_collision_exception_with(b))


func _nearest_player() -> Doll:
	var best: Doll = null
	var best_d := INF
	for p in players():
		var d := my_pos().distance_to(com2(p))
		if d < best_d:
			best_d = d
			best = p
	return best


## Ближайший игрок сейчас (удирая, вор знает, от кого — он его только что касался; воспринятая с задержкой позиция в момент
## кражи «отставала» и уводила бегство сквозь жертву).
func _threat_pos() -> Vector2:
	var me := my_pos()
	var best := predicted()
	var best_d := INF
	for p in players():
		var c := com2(p)
		if me.distance_to(c) < best_d:
			best_d = me.distance_to(c)
			best = c
	return best


## Куда удирать: вбок от угрозы и вверх; прижат к стене — через верх, над головой угрозы.
func _flee_goal(me: Vector2) -> Vector2:
	var th := _threat_pos()
	var b := arena_bounds()
	var sx := signf(me.x - th.x) if absf(me.x - th.x) > 0.2 else 1.0
	var gx := clampf(me.x + sx * 8.0, b.position.x + 2.0, b.end.x - 2.0)
	var gy := clampf(th.y + 1.8, 2.0, b.end.y - 2.5)
	if absf(gx - me.x) < 2.0:
		gx = clampf(me.x - sx * 8.0, b.position.x + 2.0, b.end.x - 2.0)
		gy = clampf(th.y + 4.0, 3.0, b.end.y - 2.0)
	return Vector2(gx, gy)
