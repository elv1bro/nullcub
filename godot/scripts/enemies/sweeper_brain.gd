## Уборщик (Sweeper, LORE.md: «мёл этажи → сметает мусор, то есть тебя, с платформ в пропасть»). Тяжёлая кукла с ведром на голове
## и толкающей метлой (scenes/enemies/sweeper_broom.tscn: Weapon 2.6 кг, модель tools/blender/enemy_parts.py; запасной вариант —
## крафтовая из чертежа data/enemies/sweeper_broom.tres, рукоять + киянка), метла в кисти через WeaponPickup.
## Программа: «мусор» (ближайший игрок) надо смести к пропасти. Поэтому Уборщик НЕ бьёт в лоб, а заходит с дальней от пропасти
## стороны цели (пролетая над ней, если оказался между целью и провалом) и толкает её метлой по полу в сторону провала:
##   approach  — к точке «за спиной» цели: (цель.x − dir·sweep_standoff, цель.y + sweep_dy), dir — к пропасти от цели
##               (EnemyBrain.pit_dir_from, с гистерезисом); неспешно (approach_input): тяжёлый, его видно издалека;
##               метла в руке со стороны dir (правая кисть метёт влево, левая — вправо; сменить руку — перехват, пока далеко);
##   telegraph — telegraph_s (0.45 с): метла вскинута над головой (поза плеча), глаза разгораются, гул, надпись SWEEP!,
##               лёгкий откат назад — видно, куда сейчас понесёт;
##   sweep     — sweep_s: метла опускается вперёд-вниз (у лежащей цели — круто в пол), тяга sweep_input вдоль dir на высоте цели:
##               колодка идёт по ногам, удар оружием (урон × масса метлы) толкает цель вдоль удара с апбиасом (Damage.knockback_dir)
##               — к провалу; после удара (отдача 0.3 с) метла дожимает цель по полу, пока та едет перед ней (до sweep_max_s);
##               у края провала (dash_edge_m) заход с рывком — добивающий;
##   recover   — recover_s: торможение, метла в «походной» позе; дальше снова approach. Заход почти не сдвинул цель (упёрлась в ящик
##               у края провала — на Свалке там стоит ShippingCrate 80 кг) — следующий заход «подцеп»: колодка снизу и взмах вверх.
## Числа (кукла 44 кг + метла 2.6 кг, max_hp 80; tests/pve_probe sweep / sweep_lane, 29.09): заход ≈ 2.5–3 с, телеграф 0.467 с;
## стоящую без ввода куклу из центра Свалки за 15 с сдвигает к провалу на 1.6–6.1 м (медиана ≈ 4 м; на пути стопка ящиков и
## ShippingCrate 80 кг у края), урон 12–54 HP за 15 с (≈ 4–5 HP за заход); без ящиков на дорожке — сталкивает В провал за 14–21 с
## в 2 из 3 прогонов (третий — ложится на балку PitBeam над провалом).
class_name SweeperBrain
extends EnemyBrain

## С какого расстояния (м по x от ЦМ цели) начинается заход.
@export var sweep_standoff := 2.5
## Высота ЦМ Уборщика относительно ЦМ цели во время заметания (колодка метлы — у колен цели).
@export var sweep_dy := 0.05
@export var approach_input := 0.6
@export var sweep_input := 0.8
@export var sweep_s := 1.1
## Пока цель едет перед метлой к пропасти, заметание продлевается до sweep_max_s (толкающая метла, а не один удар).
@export var sweep_max_s := 2.2
## Цель ниже low_y (лежит на полу после удара): Уборщик встаёт в рост (ЦМ не ниже stand_y) и метёт колодкой по полу — плечо
## floor_shoulder (метла круто вниз); иначе колодка шла бы над лежащей куклой или втыкалась в пол перед ней.
@export var low_y := 0.75
@export var stand_y := 0.95
@export var floor_shoulder := 40.0
## Подцеп (совок): прошлый заход сдвинул цель меньше scoop_after_m (упёрлась в ящик у края, лежит в куче) — следующий начинается
## снизу (колодка под целью, floor_shoulder) и через scoop_lift_at_s метла взмывает до scoop_shoulder: удар снизу с апбиасом
## перекидывает цель через препятствие (сам Уборщик вверх не тянет — со взлётом он бился с целью головами и ловил стан).
@export var scoop_after_m := 0.5
@export var scoop_lift_at_s := 0.3
@export var scoop_shoulder := 118.0
@export var recover_s := 0.9
## Добивающий заход с рывком (Doll.request_dash, кулдаун Tuning.DASH_COOLDOWN_S): только когда цель ближе dash_edge_m к краю
## пропасти — последний мах сбрасывает её вниз (рывок на каждом заходе давал 10 HP за мах, 97 HP за 15 с — Уборщик становился
## убийцей, а не дворником).
@export var sweep_dash := true
@export var dash_edge_m := 3.5
## Перелёт над целью, если Уборщик оказался между целью и пропастью (м над ЦМ цели).
@export var over_dy := 2.3
## Поза руки с метлой (measured-градусы левой стороны; у правой знак меняется): походная, замах, удар.
@export var carry_shoulder := 62.0
@export var windup_shoulder := 158.0
@export var sweep_shoulder := 72.0
@export var wrist_k := 25.0
@export var wrist_tmax := 8.0
## Плечо и локоть руки с метлой: рабочая рука Уборщика (железное предплечье) сильнее обычной руки с оружием
## (Tuning.WEAPON_ARM_MUSCLES: плечо k 38, tmax 22) — иначе метла 2.6 кг на рычаге 1.3 м (инерция ≈ 4.5 кг·м²) поднималась к
## замаху ≈ 0.7 с и за телеграф 0.45 с поза «метла над головой» не успевала читаться.
@export var arm_shoulder_k := 140.0
@export var arm_shoulder_tmax := 70.0
@export var arm_elbow_k := 60.0
@export var arm_elbow_tmax := 30.0
@export var arm_zeta := 0.8
## Метла (сцена оружия; модель — tools/blender/enemy_parts.py). Пусто — крафтовая из blueprint.weapon (handle_long + киянка).
@export var broom_scene: PackedScene

var broom: Weapon = null
var broom_hand := ""
var dir := -1.0
## Для проб: время начала последнего телеграфа и длительности телеграфов перед ударом (с).
var telegraph_durations: Array = []
var sweeps := 0
var _telegraph_t0 := -1.0
var _rest: Dictionary = {}
var _swap_block_until := 0.0
var _dir_set := false
var _scoop := false
var _sweep_x0 := 0.0
## Для проб: сколько заходов были подцепом.
var scoops := 0


func _brain_ready() -> void:
	_rest = doll.get_pose()
	call_deferred("_equip")


## Метла из чертежа (blueprint.weapon) в кисть weapon_on. Родитель метлы — родитель куклы (узел Enemies площадки): после KO
## метла остаётся лежать — лут, её можно подобрать.
func _equip() -> void:
	var bp: Variant = doll.get("blueprint")
	var wbp: Variant = (bp as Resource).get("weapon") if bp is Resource else null
	var hand := "Hand_R"
	var on := String((bp as Resource).get("weapon_on")) if bp is Resource else ""
	if on != "" and (bp as Resource).has_method("body_name_of"):
		hand = String((bp as Resource).call("body_name_of", on))
	var w: Weapon = null
	if broom_scene != null:
		w = broom_scene.instantiate() as Weapon
	elif wbp is WeaponBlueprint:
		w = CraftedWeapon.create(wbp as WeaponBlueprint)
	if w == null:
		return
	w.name = "%s_Broom" % doll.name
	w.add_to_group("pve_spawned")
	var parent := doll.get_parent() if doll.get_parent() != null else doll
	parent.add_child(w)
	var h := doll.parts.get(hand) as RigidBody3D
	w.global_transform = Transform3D(Basis.IDENTITY, h.global_position if h != null else doll.global_position)
	broom = w
	if look != null:
		look.tint_node(w)
	_attach_to(hand)


func _wp() -> WeaponPickup:
	for c in doll.get_children():
		if c is WeaponPickup:
			return c
	return null


func _attach_to(hand: String) -> void:
	var wp := _wp()
	if wp == null or broom == null or not is_instance_valid(broom) or not doll.parts.has(hand):
		return
	if broom_hand != "" and wp.is_holding(broom_hand):
		wp.drop(broom_hand)
		_pose_arm(broom_hand, "rest", 0.3)
	if broom.is_held():
		return   # метлу держит кто-то другой (её отобрали) — не телепортируем
	wp.hold_angle_deg = 0.0   # метла — продолжение руки
	if wp.attach(hand, broom):
		broom_hand = hand
		var aj := arm_joints(hand)
		if aj.has("Wrist"):
			doll.set_muscle_joint(String(aj["Wrist"]), wrist_k, wrist_tmax)
		if aj.has("Shoulder"):
			doll.set_muscle_joint(String(aj["Shoulder"]), arm_shoulder_k, arm_shoulder_tmax, arm_zeta)
		if aj.has("Elbow"):
			doll.set_muscle_joint(String(aj["Elbow"]), arm_elbow_k, arm_elbow_tmax, arm_zeta)
		_pose_arm(hand, "carry", 0.2)


func has_broom() -> bool:
	var wp := _wp()
	return wp != null and broom_hand != "" and wp.is_holding(broom_hand) and wp.weapon_in(broom_hand) == broom


## Сторона кисти: +1 — левая (она со стороны +X куклы, метёт вправо), −1 — правая.
func _side(hand: String) -> float:
	return 1.0 if hand.ends_with("_L") else -1.0


func _pose_arm(hand: String, kind: String, blend: float) -> void:
	var aj := arm_joints(hand)
	if not aj.has("Shoulder"):
		return
	var s := _side(hand)
	var sh := String(aj["Shoulder"])
	var el := String(aj.get("Elbow", ""))
	var pose := {}
	match kind:
		"carry":
			pose[sh] = s * carry_shoulder
			if el != "":
				pose[el] = s * 8.0
		"windup":
			pose[sh] = s * windup_shoulder
			if el != "":
				pose[el] = s * 25.0
		"sweep":
			pose[sh] = s * sweep_shoulder
			if el != "":
				pose[el] = s * 4.0
		"floor":
			pose[sh] = s * floor_shoulder
			if el != "":
				pose[el] = s * 4.0
		"lift":
			pose[sh] = s * scoop_shoulder
			if el != "":
				pose[el] = s * 4.0
		_:
			pose[sh] = float(_rest.get(sh, s * 85.0))
			if el != "":
				pose[el] = float(_rest.get(el, s * 10.0))
	doll.set_pose(pose, blend)


func _silenced(why: String) -> void:
	if why == "stun" and broom_hand != "":
		_pose_arm(broom_hand, "carry", 0.3)
	_telegraph_t0 = -1.0


func _think(delta: float) -> void:
	if target == null:
		want = steer(my_pos(), 0.3)   # висит на месте
		set_alert(0.0)
		return
	var tp := predicted()
	var me := my_pos()
	# куда мести: к пропасти от цели; меняем только с запасом (цель у края не должна дёргать Уборщика туда-сюда)
	var pr := pit_rect()
	var nd := pit_dir_from(tp)
	if not _dir_set or (nd != dir and (pr.size.x <= 0.0 or absf(tp.x - pr.get_center().x) > pr.size.x * 0.5 + 0.6)):
		dir = nd
		_dir_set = true
	var hand := "Hand_L" if dir > 0.0 else "Hand_R"
	match state:
		"idle", "stagger":
			if state_t >= 0.3:
				go("approach")
			want = steer(me, 0.3)
			set_alert(0.0)
		"approach":
			set_alert(0.0)
			if broom != null and is_instance_valid(broom) and broom_hand != hand and _time >= _swap_block_until \
					and me.distance_to(tp) > 3.0 and has_broom():
				_swap_block_until = _time + 2.0
				_attach_to(hand)
			var behind := Vector2(tp.x - dir * sweep_standoff, _sweep_y(tp))
			var wrong_side := (me.x - tp.x) * dir > -0.8
			var goal := behind
			if wrong_side:
				# перелёт над целью: сначала вверх, потом вбок
				goal = Vector2(behind.x, tp.y + over_dy)
				if me.y < tp.y + over_dy * 0.7 and absf(me.x - tp.x) < 2.5:
					goal.x = me.x
			want = steer(goal, approach_input if not wrong_side else 0.85)
			if not wrong_side and me.distance_to(behind) < 0.9 and my_vel().length() < 3.0 and state_t > 0.3:
				_start_telegraph()
			elif not wrong_side and absf(me.x - tp.x) < sweep_standoff * 0.75 and absf(me.y - tp.y) < 1.0 and state_t > 0.4:
				_start_telegraph()   # цель сама подлетела вплотную с нужной стороны
		"telegraph":
			var hold := Vector2(tp.x - dir * sweep_standoff, _sweep_y(tp))
			want = steer(hold, 0.5) + Vector2(-dir * 0.25, 0.0)
			set_alert(1.0)
			if state_t >= telegraph_s:
				telegraph_durations.append(snappedf(_time - _telegraph_t0, 0.001))
				sweeps += 1
				_pose_arm(broom_hand if broom_hand != "" else hand, "floor" if tp.y < low_y or _scoop else "sweep", 0.12)
				_sweep_x0 = tp.x
				if _scoop:
					scoops += 1
				go("sweep")
				if sweep_dash and _near_edge(tp):
					dash()
		"sweep":
			set_alert(0.6)
			var dy := _sweep_y(tp) - me.y
			want = Vector2(dir * sweep_input, clampf(dy * STEER_KP, -0.6, 0.6) + hover_input())
			if _scoop and state_t >= scoop_lift_at_s and state_t - get_physics_process_delta_time() < scoop_lift_at_s:
				_pose_arm(broom_hand if broom_hand != "" else hand, "lift", 0.18)
			# толкающая метла: после удара (отдача — thrust_lock 0.3 с) не останавливается, а дожимает цель по полу; цель едет к
			# пропасти прямо перед метлой — заметание продлевается до sweep_max_s
			var passed := (me.x - tp.x) * dir > 0.6
			var s := seen()
			var riding := (s[1] as Vector2).x * dir > 0.5 and absf(tp.x - me.x) < sweep_standoff
			if passed or state_t >= sweep_max_s or (state_t >= sweep_s and not riding):
				_scoop = (tp.x - _sweep_x0) * dir < scoop_after_m
				go("recover")
		"recover":
			set_alert(0.0)
			var v := my_vel()
			want = Vector2(-v.x * 0.25, -v.y * 0.25 + hover_input())
			if state_t < 0.05 and broom_hand != "":
				_pose_arm(broom_hand, "carry", 0.35)
			if state_t >= recover_s:
				go("approach")


func _separation_weight() -> float:
	return 0.3 if state == "sweep" else 1.0


## Высота ЦМ Уборщика при заходе: у стоящей/летящей цели — её уровень, у лежащей — в рост.
func _sweep_y(tp: Vector2) -> float:
	if _scoop:
		return maxf(tp.y - 0.15, 0.7)
	return maxf(tp.y + 0.45, stand_y) if tp.y < low_y else tp.y + sweep_dy


## Цель у края пропасти со стороны, откуда её метут (x до края ≤ dash_edge_m).
func _near_edge(tp: Vector2) -> bool:
	var pr := pit_rect()
	if pr.size.x <= 0.0:
		return false
	var edge := pr.end.x if dir < 0.0 else pr.position.x
	var gap := (tp.x - edge) * -dir
	return gap >= -0.5 and gap <= dash_edge_m


func _start_telegraph() -> void:
	_telegraph_t0 = _time
	go("telegraph")
	telegraph("SWEEP!", telegraph_s + 0.25, "warn_sweep", Color(1.0, 0.62, 0.18))
	if broom_hand != "":
		_pose_arm(broom_hand, "windup", 0.2)
