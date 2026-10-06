## Бот «Стычки 3 на 3» (docs/plan-demo/SQUAD.md). Каркас — EnemyBrain: восприятие с задержкой, упреждение и ошибка прицела, плавный
## ввод тягой, страховка от застревания, ускорение за Заряд. Без EnemyLook (это боец отряда, а не сломанный робот).
## Команду берёт у своей куклы (SquadMatch.team_of — чётность player_index): Match.respawn_doll пересоздаёт мозг без настроек.
## Цели — живые куклы чужой команды (группа squad_N); свои (squad_своя) — разнос, чтобы отряд не шёл кучей.
##   • advance — целей рядом нет: к ближайшему сопернику на своей «полке» высоты (у каждого бота своя);
##   • engage  — держать дистанцию своего оружия (Tuning.SQUAD_BOT_RANGE: дробовик — вплотную, винтовка — издалека) со своей стороны
##     от цели: рука с оружием на экране со стороны соперника (у синих — справа), поэтому синие держатся левее цели, красные —
##     правее; ход вверх-вниз (уклонение); рука (SquadArm) — на упреждённую цель; спуск (SquadGun.trigger) — когда ствол в конусе
##     fire_cone_deg (+ разброс оружия) от цели, она в дальности и первая кукла на луче от дула — не своя;
##     Дробь (дальность ≤ CLOSE_RANGE_M) сближается рывком;
##   • reload  — идёт перезарядка: отход подальше от цели;
##   • supply  — к ящику (SupplyCrate): патронов нет совсем — к любому ящику с патронами; мало жизней, мало запаса или нет брони — к
##     такому ящику, если он ближе Tuning.SQUAD_BOT_SUPPLY_M; по дороге стреляет, если может; не добрался за CRATE_GIVE_UP_S —
##     ящик брошен на CRATE_SKIP_S (пути бот не ищет — идёт напрямую);
##   • melee   — цель ближе SQUAD_BOT_MELEE_M или патронов нет и ящика с ними нет: наскок тягой с ускорением (кукла бьёт телом);
##   • brawl   — громила (рукопашный класс, SquadMelee): к цели с рывком, рука с оружием — на неё; ближе BRAWL_LUNGE_M — полёт за
##     оружием (держит до BOT_DASH_MAX_S или до цели), мимо — снова;
##   • objective — захват флага (SquadMatch.mode «ctf»): несущий — домой к своему флагу; свой флаг унесли — все гонятся за несущим
##     (он — цель); свой флаг лежит — ближайший идёт вернуть; иначе нападающие (места 0 и 2) — к чужому флагу, защитник (место 1,
##     снайпер) — у своей базы; соперник ближе OBJ_ENGAGE_M — сначала бой.
## Гаусс копит заряд (спуск зажат) до gauss_charge и стреляет, отпустив, когда ствол на цели. Руку с оружием оторвало — к ближайшему
## ящику любого вида (он вернёт руку), по дороге бьёт телом. Класс, ветка и оружие бота — от матча (SquadMatch), сами.
class_name SquadBrain
extends EnemyBrain

const ENGAGE_EXTRA_M := 6.0         # цель ближе дальности боя + столько — уже бой, а не переход
const WOBBLE_M := 1.6               # м: амплитуда хода вверх-вниз в бою
const WOBBLE_S := 2.4               # с: период
const LANE_Y := [1.2, 3.0, 5.2]     # «полки» высоты (по номеру бота в команде)
const LANE_PULL := 0.55             # бой: доля «своей полки» в высоте (остальное — высота цели): иначе обе команды уползали под потолок
const FLOOR_Y := 0.9                # ниже — тяга вверх (не ползти по полу)
const CEIL_MARGIN := 2.0            # м под потолком карты
const MELEE_S := 0.8
const LOW_HP := 0.45                # доля HP: ниже — к ящику жизней
const CLOSE_RANGE_M := 12.0
const BRAWL_LUNGE_M := 9.0           # громила: ближе — полёт к цели (12 м/с: 9 м — за ~0.8 с, под огнём меньше)
const BRAWL_DASH_M := 6.0            # громила: дальше — рывок на сближение
const CRATE_GIVE_UP_S := 6.0         # к ящику не добрался за столько (пути нет: напрямую, а сверху настил) — бросить его …
const CRATE_SKIP_S := 15.0           # … на столько
const STUCK_RADIUS_M := 1.5
const STUCK_AREA_S := 5.0
const UNSTICK_DIRS := [Vector2(0.6, 0.9), Vector2(1.0, -0.15), Vector2(0.5, -0.9), Vector2(-0.6, 0.9), Vector2(-1.0, -0.15)]
const BOT_DASH_MAX_S := 1.2          # громила: полёт бота — не дольше (5 с полёта человек держит сам, бот бы улетал мимо)
const OBJ_ENGAGE_M := 8.0            # захват флага, защитник: соперник ближе — бой, дальше — к своему флагу
const OBJ_RUSH_FIGHT_M := 4.0        # захват флага, нападающий (и кто возвращает свой флаг): к цели, стреляя на ходу; бой — только вплотную
const DEFEND_M := 6.0                # защитник держится у своего флага не дальше

## Уровень 1..3 (Tuning.SQUAD_BOT_LEVELS); 0 — default_level (его ставит площадка: Match.respawn_doll создаёт мозг заново, экспорт теряется).
@export var level := 0
static var default_level := 2

var team := 0
var max_in := 0.88
var fire_cone_deg := 10.0
var firing := false
var shots_blocked := 0
var crate: SupplyCrate = null
var _crate_t := 0.0
var _crate_skip: Dictionary = {}     # instance id ящика → до какого _time его не брать
var _stuck_anchor := Vector2.ZERO
var _stuck_anchor_t := 0.0
var _unstick_n := 0
var _lane := 1.2
var _phase := 0.0
## Гаусс: до какого заряда копить (по уровню бота).
var gauss_charge := 0.75


func _init() -> void:
	reaction_s = 0.3
	aim_error_m = 0.55


## Как EnemyBrain._setup, но без EnemyLook. Рука (SquadArm) и оружие (SquadGun) — дети куклы, их ставит площадка раньше мозга.
func _setup() -> void:
	if _ready_done:
		return
	_ready_done = true
	doll.external_input = true
	arena = get_tree().get_first_node_in_group("arena")
	doll.damaged.connect(_on_damaged)
	doll.knocked_out.connect(func(_a: Node, _r: Dictionary) -> void: _on_ko())
	_brain_ready()


func _brain_ready() -> void:
	team = SquadMatch.team_of(doll)
	players_group = SquadMatch.team_group(1 - team)
	enemies_group = SquadMatch.team_group(team)
	var lv := level if level > 0 else default_level
	var p: Dictionary = Tuning.SQUAD_BOT_LEVELS.get(lv, Tuning.SQUAD_BOT_LEVELS[2])
	max_in = float(p["max_in"])
	aim_error_m = float(p["aim_error_m"])
	reaction_s = float(p["reaction_s"])
	fire_cone_deg = float(p["fire_cone_deg"])
	gauss_charge = 0.55 + 0.15 * float(lv)
	var slot := int(doll.player_index) / 2
	_lane = float(LANE_Y[slot % LANE_Y.size()])
	_phase = float(doll.player_index) * 1.7
	go("advance")


func gun() -> SquadGun:
	return SquadMatch.gun_of(doll)


func arm() -> ArmAssist:
	var g := gun()
	return g.arm() if g != null else null


func sm() -> SquadMatch:
	return get_tree().get_first_node_in_group(Match.GROUP) as SquadMatch


## Оружие есть, а руки с ним нет (прочность суставов оторвала): ствол без луча, рукопашное — не в руке.
func _armless(g: SquadGun, ml: SquadMelee) -> bool:
	if g != null and g.weapon != "":
		return g.aim_ray().is_empty()
	return ml != null and ml.weapon_id != "" and not ml.armed()


func _think(delta: float) -> void:
	var g := gun()
	var ml := SquadMatch.melee_of(doll)
	var m := sm()
	var armless := _armless(g, ml)
	var had := crate
	_pick_crate(g, armless)
	if crate != null and crate == had:
		_crate_t += delta
		if _crate_t > CRATE_GIVE_UP_S:
			_crate_skip[crate.get_instance_id()] = _time + CRATE_SKIP_S
			crate = null
			_crate_t = 0.0
	else:
		_crate_t = 0.0
	var has_target := target != null and is_instance_valid(target) and target.alive
	var obj: Variant = _objective(m)
	var carrying := m != null and m.carried_flag(doll) != null
	var rush := obj is Vector2 and not _defending()
	if crate != null and rush and not armless and not (g != null and g.out_of_ammo()):
		crate = null   # к цели режима — без заходов за ящиками «на всякий случай»
	if crate != null and not carrying:
		go("supply")
		var cp := crate.global_position
		want = steer_speed(_clamp_goal(Vector2(cp.x, cp.y)), 6.0, max_in)
		_fight_on_the_way(g, has_target)
		return
	var t_dist := my_pos().distance_to(com2(target)) if has_target else INF
	if obj is Vector2 and (carrying or rush or not has_target or t_dist > OBJ_ENGAGE_M):
		go("objective")
		var op := obj as Vector2
		want = steer_speed(_clamp_goal(op), 7.0, max_in)
		if carrying or my_pos().distance_to(op) > 10.0:
			dash()
		if ml != null and ml.weapon_id != "" and (g == null or g.weapon == "") and _fly_to(ml, op):
			_aim(op)
			return
		_fight_on_the_way(g, has_target)
		return
	if not has_target:
		_advance()
		_release_arm()
		_trigger(false)
		return
	if ml != null and ml.weapon_id != "" and (g == null or g.weapon == ""):
		_brawl(ml)
		return
	if armless:
		go("melee")   # ствола в руке нет, ящика рядом нет — бьёт телом
		want = steer(predicted(), 1.0)
		if state_t > MELEE_S:
			state_t = 0.0
			note_attack()
			dash()
		_trigger(false)
		return
	var tp := predicted()
	var d := my_pos().distance_to(com2(target))
	var band: Vector2 = Tuning.SQUAD_BOT_RANGE.get(g.weapon if g != null else "pistol", Vector2(6.0, 11.0))
	var no_ammo := g == null or g.out_of_ammo()
	if d > band.y + ENGAGE_EXTRA_M and not no_ammo:
		_advance()
		_aim(tp)
		_trigger(false)
		return
	match state:
		"melee":
			want = steer(tp, 1.0)
			if no_ammo:
				if state_t > MELEE_S:
					state_t = 0.0   # без патронов — новый наскок
					note_attack()
					dash()
			elif state_t > MELEE_S or d > Tuning.SQUAD_BOT_MELEE_M * 2.0:
				go("engage")
		"reload":
			want = _hold_range(tp, band.y + 2.5)
			if g == null or g.reloading <= 0.0:
				go("engage")
		_:
			if state != "engage":
				go("engage")
			want = _hold_range(tp, (band.x + band.y) * 0.5)
			if g != null and float(g.def["range"]) <= CLOSE_RANGE_M and d > band.y:
				dash()   # дробь бьёт только вблизи: сближение рывком, а не шагом под огнём винтовок
			if no_ammo or d < Tuning.SQUAD_BOT_MELEE_M:
				go("melee")
				note_attack()
				dash()
			elif g.reloading > 0.0:
				go("reload")
	want = want.limit_length(max_in)
	_aim(tp)
	_shoot(g, state != "melee" and g != null and _can_hit(g, tp, d))


## По дороге (к ящику, к цели режима): цель есть — рука на неё и огонь, если можно; громила — полёт, если цель рядом.
func _fight_on_the_way(g: SquadGun, has_target: bool) -> void:
	if not has_target:
		_release_arm()
		_trigger(false)
		return
	var tp := predicted()
	_aim(tp)
	var ml := SquadMatch.melee_of(doll)
	if ml != null and ml.weapon_id != "" and (g == null or g.weapon == ""):
		_fly(ml, tp, my_pos().distance_to(com2(target)))
		return
	_shoot(g, g != null and g.weapon != "" and _can_hit(g, tp, my_pos().distance_to(com2(target))))


## Спуск: обычное оружие — зажат, пока можно попасть; гаусс — копит заряд до gauss_charge (зажат), потом держит, пока ствол не на
## цели, и отпускает — выстрел.
func _shoot(g: SquadGun, can_hit: bool) -> void:
	if g == null or not g.charges():
		_trigger(can_hit)
		return
	if g.mag <= 0 or g.reloading > 0.0:
		_trigger(false)
		return
	if g.charge < gauss_charge:
		_trigger(true)
	else:
		_trigger(not can_hit)


## Цель режима захвата флага (точка) или null: несущий — свой флаг дома (доставка); свой флаг лежит — ближайший из своих идёт вернуть;
## нападающие (места 0 и 2) — к чужому флагу (дома или где лежит); защитник (место 1) — у своего флага. Свой флаг унесли — целью
## становится несущий (_pick_target), точки нет.
func _objective(m: SquadMatch) -> Variant:
	if m == null or not m.is_ctf():
		return null
	var mine := m.flag_of(team)
	var theirs := m.flag_of(1 - team)
	if mine == null or theirs == null:
		return null
	if m.carried_flag(doll) != null:
		return Vector2(mine.home.x, mine.home.y)
	if mine.state == "carried":
		return null
	if mine.state == "dropped" and _nearest_to(mine.global_position):
		return Vector2(mine.global_position.x, mine.global_position.y)
	var slot := int(doll.player_index) / 2
	if slot == 1:
		var h := Vector2(mine.home.x, mine.home.y)
		return h if my_pos().distance_to(h) > DEFEND_M else null
	if theirs.state == "carried":
		return Vector2(mine.home.x - _side() * 3.0, mine.home.y)   # свой несёт — прикрыть его у базы
	return Vector2(theirs.point().x, theirs.point().y)


## Защитник (место 1): держит свой флаг, а не бежит к чужому.
func _defending() -> bool:
	return int(doll.player_index) / 2 == 1


## Я ближайший из живых своих к точке at.
func _nearest_to(at: Vector3) -> bool:
	var me := doll.centre_of_mass().distance_to(at)
	for n in get_tree().get_nodes_in_group(SquadMatch.team_group(team)):
		if n != doll and n is Doll and (n as Doll).alive and (n as Doll).centre_of_mass().distance_to(at) < me:
			return false
	return true


## Цель: в захвате флага, если свой флаг несёт соперник, — он; иначе — ближайший (EnemyBrain).
func _pick_target() -> void:
	var m := sm()
	if m != null and m.is_ctf():
		var mine := m.flag_of(team)
		if mine != null and mine.state == "carried" and is_instance_valid(mine.carrier) and mine.carrier.alive:
			if target != mine.carrier:
				target = mine.carrier
				_hist.clear()
			return
	super._pick_target()


## Ящик, за которым стоит идти сейчас (или null): патронов нет — ближайший с патронами, где бы он ни был; жизней мало — жизни; запас
## меньше магазина — патроны; брони нет — броня (эти — если ближе SQUAD_BOT_SUPPLY_M).
func _pick_crate(g: SquadGun, armless := false) -> void:
	if crate != null and (not is_instance_valid(crate) or crate.is_queued_for_deletion()):
		crate = null
	var kinds: Array = []
	var far_ok := false
	if armless:
		kinds = Tuning.SQUAD_SUPPLY.keys()   # любой ящик вернёт руку с оружием
		far_ok = true
	elif g != null and g.out_of_ammo():
		kinds = ["ammo"]
		far_ok = true
	else:
		kinds.append_array(Tuning.SQUAD_BOOSTS)
		if doll.hp < doll.max_hp * LOW_HP:
			kinds.append("health")
		if g != null and g.reserve < g.mag_max:
			kinds.append("ammo")
		var m := get_tree().get_first_node_in_group(Match.GROUP) as SquadMatch
		if m != null and m.armor_of(doll) <= 0.0:
			kinds.append("armor")
	if kinds.is_empty():
		crate = null
		return
	var best: SupplyCrate = null
	var best_d := INF if far_ok else Tuning.SQUAD_BOT_SUPPLY_M
	for n in get_tree().get_nodes_in_group(SquadMatch.SUPPLY_GROUP):
		var c := n as SupplyCrate
		if c == null or not kinds.has(c.kind) or c.is_queued_for_deletion() or float(_crate_skip.get(c.get_instance_id(), -1.0)) > _time:
			continue
		var cp := c.global_position
		var dd := my_pos().distance_to(Vector2(cp.x, cp.y))
		if dd < best_d:
			best_d = dd
			best = c
	crate = best


## Громила: к цели полной тягой (дальше BRAWL_DASH_M — с рывком), рука с оружием на упреждённую цель, ближе BRAWL_LUNGE_M — выпад.
func _brawl(ml: SquadMelee) -> void:
	if state != "brawl":
		go("brawl")
	var tp := predicted()
	var d := my_pos().distance_to(com2(target))
	want = steer(tp, max_in)
	if d > BRAWL_DASH_M and not ml.dashing:
		dash()
	_aim(tp)
	_trigger(false)
	_fly(ml, tp, d)


## Громила к цели режима: дальше 6 м — полёт к ней (оружие тянет, как к сопернику), долетел или 2.5 с — конец. true — летит.
func _fly_to(ml: SquadMelee, op: Vector2) -> bool:
	var d := my_pos().distance_to(op)
	if ml.dashing:
		ml.steer_dash(Vector3(op.x, op.y, 0.0))
		if d < 1.5 or ml.dash_t > 2.5:
			ml.end_dash()
		return true
	if d > 6.0 and ml.can_dash():
		return ml.start_dash(Vector3(op.x, op.y, 0.0))
	return false


## Полёт громилы-бота: цель ближе BRAWL_LUNGE_M — полёт к ней (рука с оружием ведёт), держит до BOT_DASH_MAX_S или пока не долетел.
func _fly(ml: SquadMelee, tp: Vector2, d: float) -> void:
	if ml.dashing:
		ml.steer_dash(Vector3(tp.x, tp.y, 0.0))
		if ml.dash_t > BOT_DASH_MAX_S or d < 0.8:
			ml.end_dash()
	elif d < BRAWL_LUNGE_M and d > 1.2 and ml.can_dash():
		if ml.start_dash(Vector3(tp.x, tp.y, 0.0)):
			note_attack()


## Переход: к ближайшему сопернику (или к середине карты, если их нет), на своей полке высоты.
func _advance() -> void:
	if state != "advance":
		go("advance")
	var goal := Vector2(0.0, _lane)
	if target != null and is_instance_valid(target) and target.alive:
		goal = Vector2(com2(target).x + _side() * 4.0, _lane)
	want = steer_speed(_clamp_goal(goal), 5.0, max_in)


## Сторона, с которой бот держится от цели: синие — левее (рука с оружием смотрит вправо), красные — правее.
func _side() -> float:
	return -1.0 if team == 0 else 1.0


## Держать дистанцию dist до цели по x со своей стороны, по y — между высотой цели и своей полкой + ход вверх-вниз. Только
## «высота цели» поднимала бы обе команды под потолок: каждый держится чуть выше соперника, тот — выше него.
func _hold_range(tp: Vector2, dist: float) -> Vector2:
	var wob := sin((_time + _phase) * TAU / WOBBLE_S) * WOBBLE_M
	var goal := Vector2(tp.x + _side() * dist, lerpf(tp.y, _lane, LANE_PULL) + wob)
	return steer(_clamp_goal(goal), max_in)


func _clamp_goal(g: Vector2) -> Vector2:
	var b := arena_bounds()
	return Vector2(clampf(g.x, b.position.x + 1.5, b.end.x - 1.5), clampf(g.y, FLOOR_Y, b.end.y - CEIL_MARGIN))


func _aim(tp: Vector2) -> void:
	var a := arm()
	if a != null:
		a.set_target_override(Vector3(tp.x, tp.y, 0.0))


func _release_arm() -> void:
	var a := arm()
	if a != null:
		a.clear_target_override()


func _trigger(on: bool) -> void:
	firing = on
	var g := gun()
	if g != null:
		g.trigger = on


## Можно стрелять: есть патрон, цель в дальности, ствол в конусе fire_cone_deg (+ разброс оружия) от направления «дуло → цель»,
## первая кукла на луче от дула — не своя.
func _can_hit(g: SquadGun, tp: Vector2, d: float) -> bool:
	if g.mag <= 0 or g.reloading > 0.0 or d > float(g.def["range"]) * 0.95:
		counters["no_range"] = int(counters.get("no_range", 0)) + 1
		return false
	var ray := g.aim_ray()
	if ray.is_empty():
		return false
	var o := ray[0] as Vector3
	var ax := ray[1] as Vector3
	var to := Vector3(tp.x, tp.y, 0.0) - o
	if to.length() > 0.05 and ax.angle_to(to.normalized()) > deg_to_rad(fire_cone_deg + float(g.def["spread_deg"])):
		counters["no_cone"] = int(counters.get("no_cone", 0)) + 1
		return false
	var q := PhysicsRayQueryParameters3D.create(o, o + ax * float(g.def["range"]))
	var ex: Array[RID] = []
	for p in doll.parts.values():
		if is_instance_valid(p):
			ex.append((p as RigidBody3D).get_rid())
	q.exclude = ex
	var hit := doll.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var who := SquadGun._doll_of(hit["collider"] as Node)
		if who != null and who != doll and SquadMatch.team_of(who) == team:
			shots_blocked += 1
			return false
	counters["fire_ok"] = int(counters.get("fire_ok", 0)) + 1
	return true


func _stuck_allowed() -> bool:
	return state in ["advance", "engage", "reload", "supply", "brawl", "objective"]


## Застревание (поверх EnemyBrain: там только «жмёт, а стоит», и выход всегда вверх-вбок). Ещё и «жмёт, а топчется на месте»: ЦМ
## не вышел из круга STUCK_RADIUS_M за STUCK_AREA_S (бот бьётся о стену и отскакивает — скорость есть, хода нет). Выход — по кругу
## направлений UNSTICK_DIRS: под настилом вверх не выйти, у стены укрытия — вбок не выйти (проба 06.10: громила 58 с у укрытия,
## снайпер — головой в палубу базы снизу).
func _tick_stuck(delta: float) -> void:
	if _time < _unstick_until:
		want = _unstick_dir
		return
	var me := my_pos()
	var pushing := _stuck_allowed() and want.length() >= STUCK_INPUT
	if not pushing or me.distance_to(_stuck_anchor) > STUCK_RADIUS_M:
		_stuck_anchor = me
		_stuck_anchor_t = _time
	_stuck_t = _stuck_t + delta if pushing and my_vel().length() < STUCK_SPEED else 0.0
	if _stuck_t < STUCK_S and _time - _stuck_anchor_t < STUCK_AREA_S:
		return
	_stuck_t = 0.0
	_stuck_anchor = me
	_stuck_anchor_t = _time
	_unstick_until = _time + UNSTICK_S
	var sx := -signf(want.x) if absf(want.x) > 0.2 else 1.0
	var d: Vector2 = UNSTICK_DIRS[_unstick_n % UNSTICK_DIRS.size()]
	_unstick_n += 1
	_unstick_dir = Vector2(d.x * sx, d.y)
	counters["unstick"] = int(counters.get("unstick", 0)) + 1


func _silenced(_why: String) -> void:
	_trigger(false)
	_release_arm()
	var ml := SquadMatch.melee_of(doll)
	if ml != null:
		ml.end_dash()
