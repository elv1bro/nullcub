## Бот «Стычки 3 на 3» (docs/plan-demo/SQUAD.md). Каркас — EnemyBrain: восприятие с задержкой, упреждение и ошибка прицела, плавный
## ввод тягой, страховка от застревания, ускорение за Заряд. Без EnemyLook (это боец отряда, а не сломанный робот).
## Команду берёт у своей куклы (SquadMatch.team_of — чётность player_index): Match.respawn_doll пересоздаёт мозг без настроек.
## Цели — живые куклы чужой команды (группа squad_N); свои (squad_своя) — разнос, чтобы отряд не шёл кучей.
##   • advance — целей рядом нет: к середине карты / к ближайшему сопернику по прямой, высота — своя «полка» (у каждого бота своя);
##   • engage  — цель ближе SQUAD_BOT_RANGE.y + 6 м: держать дистанцию SQUAD_BOT_RANGE (ближе — отход, дальше — подход), ходить
##     вверх-вниз (уклонение); обе руки (пулемёт на каждом предплечье) смотрят на упреждённую цель (ArmAssist.set_target_override через
##     GunAim — на цель ложится ось ствола, а не кисть); очередь даёт ствол, чья ось в конусе fire_cone_deg от цели, цель в дальности
##     и на линии огня нет своих (луч от дула: первая кукла — чужая) — каждый ствол на своём канале;
##   • reload  — заряд ниже SQUAD_BOT_RELOAD_BELOW: отход от цели, пока не накопится SQUAD_BOT_RELOAD_UNTIL (рука всё равно целится);
##   • melee   — цель ближе SQUAD_BOT_MELEE_M: наскок тягой с ускорением, как в обычном бою (кукла бьёт телом).
## Каналы стволов жмёт сам (ActiveRig.held), автопилот ActiveRig выключен: у него нет проверки своих на линии огня, и он жмёт канал
## целиком, а не тот ствол, что смотрит на цель.
class_name SquadBrain
extends EnemyBrain

const ENGAGE_EXTRA_M := 6.0         # цель ближе дальности боя + столько — уже бой, а не переход
const WOBBLE_M := 1.6               # м: амплитуда хода вверх-вниз в бою
const WOBBLE_S := 2.4               # с: период
const LANE_Y := [1.2, 3.0, 5.2]     # «полки» высоты при переходе (по номеру бота в команде)
const FLOOR_Y := 0.9                # ниже — тяга вверх (не ползти по полу)
const CEIL_MARGIN := 2.0            # м под потолком карты
const MELEE_S := 0.8
const LANE_PULL := 0.55             # бой: доля «своей полки» в высоте (остальное — высота цели)

## Уровень 1..3 (Tuning.SQUAD_BOT_LEVELS); 0 — default_level (его ставит площадка: Match.respawn_doll создаёт мозг заново, экспорт теряется).
@export var level := 0
static var default_level := 2

var team := 0
var rig: ActiveRig
var max_in := 0.88
var fire_cone_deg := 10.0
var firing := false
var shots_blocked := 0
var _aims: Dictionary = {}          # сторона ствола ("R" / "L") → GunAim
var _lane := 1.2
var _phase := 0.0


func _init() -> void:
	reaction_s = 0.3
	aim_error_m = 0.55


## Как EnemyBrain._setup, но без EnemyLook. Руки (SquadArm / SquadArmLeft) ставит площадка раньше мозга; автопилот ActiveRig выключен.
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
	var slot := int(doll.player_index) / 2
	_lane = float(LANE_Y[slot % LANE_Y.size()])
	_phase = float(doll.player_index) * 1.7
	go("advance")


func _rig() -> ActiveRig:
	if rig == null or not is_instance_valid(rig):
		var r: Variant = doll.get("active_rig")
		rig = r as ActiveRig if r is ActiveRig and is_instance_valid(r) else null
	return rig


func _think(_delta: float) -> void:
	var r := _rig()
	if r != null:
		r.auto = false
	var charge := r.charge if r != null else 0.0
	if target == null or not is_instance_valid(target) or not target.alive:
		_advance()
		_release_arms()
		_fire({})
		return
	var tp := predicted()
	var me := my_pos()
	var d := me.distance_to(com2(target))
	if d > Tuning.SQUAD_BOT_RANGE.y + ENGAGE_EXTRA_M:
		_advance()
		_aim(tp)
		_fire({})
		return
	match state:
		"melee":
			want = steer(tp, 1.0)
			if state_t > MELEE_S or d > Tuning.SQUAD_BOT_MELEE_M * 2.0:
				go("engage")
		"reload":
			want = _hold_range(tp, Tuning.SQUAD_BOT_RANGE.y + 3.0)
			if charge >= Tuning.SQUAD_BOT_RELOAD_UNTIL:
				go("engage")
		_:
			if state != "engage":
				go("engage")
			want = _hold_range(tp, (Tuning.SQUAD_BOT_RANGE.x + Tuning.SQUAD_BOT_RANGE.y) * 0.5)
			if charge < Tuning.SQUAD_BOT_RELOAD_BELOW:
				go("reload")
			elif d < Tuning.SQUAD_BOT_MELEE_M:
				go("melee")
				note_attack()
				dash()
	want = want.limit_length(max_in)
	_aim(tp)
	_fire(_aligned(tp, d) if state != "melee" else {})


## Переход: к ближайшему сопернику (или к середине карты, если их нет), на своей полке высоты.
func _advance() -> void:
	if state != "advance":
		go("advance")
	var goal := Vector2(0.0, _lane)
	if target != null and is_instance_valid(target) and target.alive:
		goal = Vector2(com2(target).x, _lane)
	want = steer_speed(_clamp_goal(goal), 5.0, max_in)


## Держать дистанцию dist до цели по x (со своей стороны), по y — между высотой цели и своей полкой + ход вверх-вниз. Только
## «высота цели» поднимала бы обе команды под потолок: каждый держится чуть выше соперника, тот — выше него.
func _hold_range(tp: Vector2, dist: float) -> Vector2:
	var me := my_pos()
	var side := signf(me.x - tp.x)
	if side == 0.0:
		side = -1.0 if team == 0 else 1.0
	var wob := sin((_time + _phase) * TAU / WOBBLE_S) * WOBBLE_M
	var goal := Vector2(tp.x + side * dist, lerpf(tp.y, _lane, LANE_PULL) + wob)
	return steer(_clamp_goal(goal), max_in)


func _clamp_goal(g: Vector2) -> Vector2:
	var b := arena_bounds()
	return Vector2(clampf(g.x, b.position.x + 1.5, b.end.x - 1.5), clampf(g.y, FLOOR_Y, b.end.y - CEIL_MARGIN))


## Обе руки — на цель: каждая наводит свой ствол (GunAim поворачивает цель руки так, чтобы на цель легла ось ствола).
func _aim(tp: Vector2) -> void:
	var want3 := Vector3(tp.x, tp.y, 0.0)
	for g in SquadMatch.guns_of(doll):
		var arm := SquadMatch.arm_for(doll, g)
		if arm == null:
			continue
		var side := String(g["side"])
		if not _aims.has(side):
			_aims[side] = GunAim.new()
		arm.set_target_override((_aims[side] as GunAim).point_for(arm, g, want3))


func _release_arms() -> void:
	for c in doll.get_children():
		if c is ArmAssist:
			(c as ArmAssist).clear_target_override()


## Каналы стволов: channels — {канал: true} тех, что стреляют в этот тик; остальные отпущены.
func _fire(channels: Dictionary) -> void:
	firing = not channels.is_empty()
	var r := _rig()
	if r == null:
		return
	for ch in range(1, ActiveBlocks.CHANNELS + 1):
		r.held[ch - 1] = channels.has(ch)


## Стволы, из которых можно стрелять: цель в дальности, ось ствола в конусе fire_cone_deg от направления «дуло → цель», первая
## кукла на луче от дула — не своя. Возвращает {канал: true}.
func _aligned(tp: Vector2, d: float) -> Dictionary:
	var out := {}
	var want3 := Vector3(tp.x, tp.y, 0.0)
	for g in SquadMatch.guns_of(doll):
		var def: Dictionary = g["def"]
		if d > float(def["range"]) * 0.95:
			counters["no_range"] = int(counters.get("no_range", 0)) + 1
			continue
		if GunAim.error_to(g, want3) > deg_to_rad(fire_cone_deg):
			counters["no_cone"] = int(counters.get("no_cone", 0)) + 1
			continue
		var m := SquadMatch.muzzle_of(g)
		var o := m[0] as Vector3
		var q := PhysicsRayQueryParameters3D.create(o, o + (m[1] as Vector3) * float(def["range"]))
		var ex: Array[RID] = []
		for p in doll.parts.values():
			if is_instance_valid(p):
				ex.append((p as RigidBody3D).get_rid())
		q.exclude = ex
		var hit := doll.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var who := _doll_of(hit["collider"] as Node)
			if who != null and who != doll and SquadMatch.team_of(who) == team:
				shots_blocked += 1
				continue
		counters["fire_ok"] = int(counters.get("fire_ok", 0)) + 1
		out[int(g["channel"])] = true
	return out


static func _doll_of(n: Node) -> Doll:
	while n != null:
		if n is Doll:
			return n as Doll
		n = n.get_parent()
	return null


func _stuck_allowed() -> bool:
	return state in ["advance", "engage", "reload"]


func _silenced(_why: String) -> void:
	_fire({})
	_release_arms()
