## Проба feel куклы (headless): числа для приёмки настройки мышц / трения / тяги. Это НЕ гейт: в checks[] только инварианты
## (нет взрыва, нет провала сквозь пол, конечные числа, управление отвечает), сами feel-числа лежат в metrics[<сценарий>],
## а предварительные цели feel — в targets[] (не влияют на exit, пока не передан strict=1).
## Запуск: godot --headless --path . --fixed-fps 60 res://tests/feel_probe.tscn -- "k=45,c=2,f=1,tmax=25,zeta=0.2,g=2,hz=60,only=move|hover_fall,strict=1"
##   k/c/f/tmax — uniform override мышц/трения как в doll_gate (-1 = по группам Tuning.MUSCLE_GROUPS / JOINT_FRICTION × factor);
##   zeta — ζ для c = 2·ζ·√(k·I) по группам (-1 = Tuning.MUSCLE_ZETA); g — гравитация (gravity_scale частей = g / project default);
##   k_<Group>/t_<Group> — k/tmax одной группы через Doll.set_muscle_group (k_Knee=60,t_Hip=45: подбор без правки Tuning);
##   z_<Group>/f_<Group> — ζ группы (Doll.set_muscle_group) и трение шарниров группы, Н·м; ld — linear_damp частей (подбор DOLL_LINEAR_DAMP);
##   ldc/ldl/adl/fdc/fdl/brake — Doll.damp_override (ядро/конечности/угловой конечностей/полёт ядра/полёт конечностей/IDLE_BRAKE_DAMP);
##   hz — physics_ticks_per_second (-1 = как в проекте, 60); only=a|b — подмножество сценариев; strict=1 — targets[] тоже валят exit;
##   report=<путь> — куда писать JSON (по умолчанию tests/feel_probe_report.json).
## Отчёт: tests/feel_probe_report.json, exit 0/1. ≈ 110 с сим-времени, детерминирована (два прогона → одинаковый JSON).
## Цели targets[] — docs/plan-demo/FEEL_TARGET.md §7 (эталон Ragdoll Masters); run_gate.sh гоняет пробу со strict=1.
## Углы суставов: measured = wrapf(child.rot.z − parent.rot.z), L наружу = +; поза покоя — Doll.get_pose() (Tuning.POSE).
## Сценарии (metrics[id]); кукла res://scenes/doll/doll.tscn на плоском StaticBody-полу (верх пола y=0):
##   limit — невесомость, мышцы и трение выключены (k=c=tmax=f=0): импульс ±6 Н·с по X в Hand_L и Foot_L (две фазы, между
##     ними респавн) → min/max measured-углов Shoulder/Elbow/Wrist/Hip/Knee/Ankle_L = фактические лимиты Jolt.
##   pose_api — невесомость: через 2 с Doll.set_pose({"Shoulder": 45, "Elbow_R": -40}, 0.3) → через 1.5 с плечи ±45 (группа
##     зеркалится), Elbow_R −40 (имя сустава — как есть), get_pose() отдаёт цели; reset_pose(0.3) → через 2 с плечи снова ±90.
##   pose_air — невесомость, спавн прямой палкой (плечи в 90° от Т-позы): по суставам t_first_in5_s (первый вход в ±5° позы),
##     settle_s (последний выход), overshoot_pct, crossings; max_dev_end_deg, дрейф COM, скорость частей за последнюю секунду.
##   idle_air / idle_floor — 6 с покоя, спавн 0.5 м над полом / на полу: углы 13 суставов (deg, wrapf(b.rot.z − a.rot.z)),
##     наклон торса от вертикали, высота головы, дрейф COM (всего и за последние 3 с = creep), fall_over_s (торс > 45°).
##   lie_creep — кукла спавнится лёжа на спине (root повёрнут на 90°), 6 с: углы, дрейф COM за последние 3 с (баг «ползёт» при k > 30).
##   spring_hand / spring_foot — невесомость (gravity_scale 0, пола не касается), 1 с покоя, apply_central_impulse по +X
##     3 Н·с в Hand_L / 6 Н·с в Foot_L (≈ 0.75 м/с на конечность) → для локтя+плеча / колена+бедра: peak_deg, overshoot_deg
##     (перелёт на другую сторону), crossings (смены знака отклонения от покоя), settle_s (последний выход из ±5°; −1 = так и
##     не вернулся; 0 = не выходил), final_dev_deg.
##   spring_hand_floor / spring_foot_floor — то же на полу (g как есть, 1.5 с покоя).
##   torso_kick — на полу, 1.5 с покоя, apply_torque_impulse FLIP_IMPULSE торсу: w_first_tick (сколько ω реально получил торс против
##     J/I свободного бокса), spin_stop_s (|ω| < 0.5 рад/с ≥ 0.25 с), turns, max_w, дрейф COM за 9 с и за последние 2 с (creep),
##     settled_end (max скорость частей за последние 2 с < 0.3), наклон торса в конце.
##   hover_fall — спавн 3 м, без ввода: vy торса через 1 с (+ аналитика с демпфированием), время до касания пола, скорость касания.
##   hover_up — спавн 3 м, input (0,1) 2.5 с: dy COM, min/max dy, vy через 1 с и в конце. hover_hold — input (0, g/MOVE_FORCE_PER_KG):
##     удерживает ли высоту неполная тяга (dy за 2.5 с, коснулась ли пола).
##   move — на полу, 1 с покоя, тяга +X 1.5 с: t90 (до 0.9·MAX_MOVE_SPEED), dx COM, max скорость торса, наклон торса, в воздухе ли;
##     отпустить: тормозной путь и время до < 0.2 м/с (−1 = не остановилась за 3 с).
##   wall_bounce — спавн x −2.5, y 1.5, тяга +X до касания стены (StaticBody, грань x=+3): v_in (торс/COM за тик до контакта),
##     v_out (мин. vx за 0.5 с), restitution торса и COM, первая коснувшаяся часть. Стан/урон не смотрим (DollCombat не добавлен).
##   hit_flight_10 / hit_flight_30 — кукла висит на HIT_H, Doll.apply_knockback(Damage.knockback_dir(+X) × Damage.knockback_impulse(10 / 30),
##     торс / голова, стан Damage.stun_seconds) как DollCombat._deliver: v0 (max |vx ЦМ| за 0.5 с), stop_s (|vx| < 0.4), vy через 1 и 2 с.
##   hit_rush / hit_dash — настоящий удар через DollCombat/Damage: вторая кукла влетает в висящую со скоростью 8 (наскок) / 14 м/с (рывок).
##   hit_clash — встречный наскок (атакующий +5, жертва −3 м/с, как первый удар клипа v6). У настоящих ударов v6.2 (критик круга 2):
##     sep_at_hit / sep_0p6s / sep_1s — |Δx ЦМ| кукол (цель ≥ 1.5 H = 2.7 м через 0.6 с), attacker_vx_0p3s (не догоняет, ≤ 0.5 м/с),
##     stop_s ≤ 1.3 с. У всех hit_*: limb_fold_deg — max |отклонение от позы| плеч/бёдер жертвы за 0.8 с (≥ 35°, HIT_MUSCLE_SOFT).
##   lag_thrust_x / lag_thrust_y — невесомость, тяга (1,0) / (0,1) 0.5 с и отпустить: пик отставания бедра / плеча от позы, возврат
##     в ±5°, перелёт; lag_flip — FLIP_IMPULSE торсу в воздухе; lag_spin — режим rotate (ROTATE_TORQUE 0.5 с). Цели — FEEL_TARGET §9 (v6).
##   v7 (FEEL_TARGET §9.4): стойка idle_* по эталону RM (плечо ≤ 25°, бедро ≤ 15°, локоть/колено/шея ≤ 12° вместо ±5°); лаг при разгоне
##     плечо ≥ 30° / бедро ≥ 25°; lag_dash — рывок (тяга × DASH_MULT 0.5 с вверх): плечо ≥ 40°; hit_flight_10 — fold_fast: ведущие плечо
##     и бедро ≥ 60° за 0.4 с, вход в ±10° позы ≤ 1.0 с после удара (settle_s — последний выход, метрика); weapon_arm — молот в Hand_L:
##     суставы этой руки = Tuning.WEAPON_ARM_MUSCLES, вторая рука групповая, drop возвращает группы (checks).
##   Куклы спавнятся в позе (Doll.spawn_in_pose), кроме limit / pose_air / lie_creep (палка, как до v7).
##   Подбор без правки Tuning: hms/hmh/hmr/hmf/hmg — Doll.soft_override (HIT_MUSCLE_SOFT / _S / RECOVER_S / HIT_FRICTION_SOFT /
##     HIT_MUSCLE_SOFT_GROUPS, группы через «|»), p_<Group> — угол позы (Doll.set_pose), adc — угловой дамп ядра; trace=1 — печать рядов.
extends Node3D

const DollScene := preload("res://scenes/doll/doll.tscn")
const PickupScript := preload("res://scenes/weapons/weapon_pickup.gd")
const ALL := ["limit", "pose_air", "pose_api", "idle_air", "idle_floor", "lie_creep", "spring_hand", "spring_foot", "spring_hand_floor", "spring_foot_floor",
	"torso_kick", "hover_fall", "hover_up", "hover_hold", "move", "wall_bounce",
	"hit_flight_10", "hit_flight_30", "hit_rush", "hit_dash", "hit_clash", "lag_thrust_x", "lag_thrust_y", "lag_dash", "lag_spin", "lag_flip", "weapon_arm"]
const JOINT_ORDER := ["Neck", "Shoulder_L", "Elbow_L", "Wrist_L", "Hip_L", "Knee_L", "Ankle_L",
	"Shoulder_R", "Elbow_R", "Wrist_R", "Hip_R", "Knee_R", "Ankle_R"]

const IDLE_S := 6.0
const IDLE_CREEP_FROM_S := 3.0
const FALL_OVER_DEG := 45.0
const SPRING_SETTLE_ZERO_G_S := 2.0      # спавн палкой → Т-поза собирается за ~0.7 с; толкаем уже из покоя
const SPRING_SETTLE_FLOOR_S := 1.5
const SPRING_WINDOW_S := 2.5
const SPRING_IMPULSE_HAND := 3.0       # Н·с по +Y (в Т-позе рука горизонтальна: +X шёл бы вдоль руки); рука 4 кг → ≈ 0.75 м/с
const SPRING_IMPULSE_FOOT := 6.0       # нога 8 кг → тот же ≈ 0.75 м/с, иначе бедро с трением 12.6 Н·м почти не шевелится
const SPRING_BAND_DEG := 5.0
const SPRING_HYST_DEG := 1.0
const KICK_SETTLE_S := 1.5
const KICK_WINDOW_S := 9.0             # при g=2 кукла валится медленно (~7 с до пола): 5–7 с ловили её на полпути
const KICK_CREEP_LAST_S := 2.0
const SETTLED_V := 0.3                 # м/с: max скорость частей за последние 2 с ниже — кукла улеглась
const LIE_S := 6.0
const LIE_CREEP_FROM_S := 3.0
const SPIN_STOP_W := 0.5               # рад/с
const SPIN_STOP_HOLD_S := 0.25
const HOVER_H := 3.0
const HOVER_FALL_MAX_S := 6.0             # при DOLL_LINEAR_DAMP 1.5 оседание терминальное ~1.3 м/с: 3 м ≈ 3 с
const HOVER_AFTER_LAND_S := 0.5
const HOVER_THRUST_S := 2.5
const MOVE_SETTLE_S := 1.0
const MOVE_S := 1.5
const MOVE_BRAKE_S := 3.0
const MOVE_STOP_V := 0.2
const WALL_X := 3.0
const WALL_SPAWN := Vector3(-2.5, 1.5, 0)
const WALL_MAX_S := 3.0
const WALL_AFTER_S := 0.5
const LIMIT_IMPULSE := 6.0             # Н·с, свободный мах без PD/трения
const LIMIT_PHASE_S := 2.5
const POSE_AIR_S := 4.0
const POSE_BAND_DEG := 5.0
# hit_* / lag_* (FEEL_TARGET §9 «v6»): полёт после удара и запаздывание конечностей, эталон RM (H = 1.8 м)
const HIT_H := 6.0                     # в воздухе: пол не мешает полёту 3 с (оседание ≤ 1.4 м/с → −4 м)
const HIT_SETTLE_S := 1.0              # > SPAWN_GRACE_S 0.7 (DollCombat не принимает удар раньше)
const HIT_WINDOW_S := 3.0
const HIT_V0_WINDOW_S := 0.5           # v0 = max |vx ЦМ| жертвы за столько после удара: рывок продолжает толкать жертву 0.2–0.4 с
const HIT_STOP_VX := 0.4               # м/с: «полёт погас» по горизонтали
const HIT_RUSH_V := 8.0                # м/с наскок: терминальная тяги 12/1.5 (FEEL_TARGET §4)
const HIT_DASH_V := 14.0               # м/с рывок: терминальная 12·1.8/1.5 = 14.4
const HIT_GAP := 2.4                   # м между корнями: размах Т-позы 1.94 м, кисти не касаются на спавне
const HIT_CLASH_V := Vector2(5.0, 3.0) # hit_clash: встречный наскок, атакующий +5, жертва −3 м/с (клип v6: 4.7 и 3.2 м/с на первом ударе)
const HIT_SEP_AT_S := 0.6              # расстояние между ЦМ атакующего и жертвы через столько после удара (критик круга 2: ≥ 1.5 H)
const HIT_FOLD_WINDOW_S := 0.8         # складывание конечностей жертвы: max |отклонение от позы| плеч/бёдер за столько после удара
const HIT_FOLD_DEG := 45.0             # конечность «сложилась», если отклонилась хотя бы на столько
const LAG_SETTLE_S := 2.0
const LAG_THRUST_S := 0.5              # RM: разгон 0 → 1.5–2.4 H/с за 0.5 с
const LAG_PEAK_EXTRA_S := 0.25         # пик отставания ищем до отпускания + столько (у переворота — от импульса + 0.6)
const LAG_FLIP_PEAK_S := 0.6
const LAG_AFTER_S := 1.5
const LAG_BAND_DEG := 5.0
const LAG_JOINTS := ["Shoulder_L", "Shoulder_R", "Hip_L", "Hip_R"]
const IDLE_POSE_LIMIT_DEG := {"Shoulder": 25.0, "Hip": 15.0, "Elbow": 12.0, "Knee": 12.0, "Neck": 12.0}   # v7: стойка по эталону RM
const HIT_FOLD_FAST_S := 0.4           # v7: удар 10 HP — ведущие плечо и бедро складываются ≥ HIT_FOLD_FAST_DEG за столько
const HIT_FOLD_FAST_DEG := 60.0
const HIT_RETURN_BAND_DEG := 10.0      # … и возвращаются в ±10° позы за HIT_RETURN_S после удара
const HIT_RETURN_S := 1.0
const EXPLOSION_V := 25.0
const FALL_THROUGH_Y := -0.1

var cfg := {"k": -1.0, "c": -1.0, "f": -1.0, "tmax": -1.0, "zeta": -1.0, "g": -1.0, "hz": -1.0, "ld": -1.0, "gap": -1.0,
	"ldc": -1.0, "ldl": -1.0, "adl": -1.0, "fdc": -1.0, "fdl": -1.0, "brake": -1.0, "adc": -1.0, "hms": -1.0, "hmh": -1.0, "hmr": -1.0, "hmf": -1.0, "trace": -1.0}
const DAMP_KEYS := {"ldc": "core", "ldl": "limb", "adl": "limb_ang", "fdc": "flight_core", "fdl": "flight_limb", "brake": "brake", "adc": "core_ang"}
const SOFT_KEYS := {"hms": "mult", "hmh": "hold", "hmr": "recover", "hmf": "friction"}   # Doll.soft_override (Tuning.HIT_MUSCLE_SOFT / _S / RECOVER_S)
var group_k: Dictionary = {}     # k_<Group>=... → Doll.set_muscle_group
var group_t: Dictionary = {}
var group_z: Dictionary = {}     # z_<Group>=ζ группы
var group_f: Dictionary = {}     # f_<Group>=трение шарниров группы, Н·м (подбор без пересборки doll.tscn)
var group_p: Dictionary = {}     # p_<Group>=угол позы группы, градусы L (Doll.set_pose; подбор Tuning.POSE без правки)
var only: PackedStringArray = []
var soft_groups: Array = []      # hmg=Shoulder|Hip — группы, слабеющие на удар (пусто — как в Tuning)
var strict := false
var report_path := "res://tests/feel_probe_report.json"   # report=<абсолютный путь> — подбор параллельными прогонами
var scenarios: Array = []
var idx := -1
var doll: Doll = null
var floor_body: StaticBody3D = null
var wall_body: StaticBody3D = null
var attacker: Doll = null           # hit_rush / hit_dash: вторая кукла (бьёт), doll — жертва
var hit_log: Array = []             # удары по жертве: {amount, kind, part, t}
var t := 0.0
var S: Dictionary = {}
var report := {"ok": true, "checks": [], "targets": [], "metrics": {}, "info": {}}
var g_eff := 0.0
var g_scale := 1.0
var wall_start_usec := 0
var total_ticks := 0
var sim_total_s := 0.0
var scen_max_speed := 0.0
var scen_min_y := 99.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			if cfg.has(p[0]):
				cfg[p[0]] = float(p[1])
			elif p[0].begins_with("k_"):
				group_k[p[0].substr(2)] = float(p[1])
			elif p[0].begins_with("t_"):
				group_t[p[0].substr(2)] = float(p[1])
			elif p[0].begins_with("z_"):
				group_z[p[0].substr(2)] = float(p[1])
			elif p[0].begins_with("f_"):
				group_f[p[0].substr(2)] = float(p[1])
			elif p[0].begins_with("p_"):
				group_p[p[0].substr(2)] = float(p[1])
			elif p[0] == "hmg":
				soft_groups = Array(p[1].split("|"))   # Doll.soft_override.groups (Tuning.HIT_MUSCLE_SOFT_GROUPS)
			elif p[0] == "only":
				only = p[1].split("|")
			elif p[0] == "report":
				report_path = p[1]
			elif p[0] == "strict":
				strict = p[1] != "0"
	if float(cfg["hz"]) > 0.0:
		Engine.physics_ticks_per_second = int(cfg["hz"])
	var default_g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	g_eff = float(cfg["g"]) if float(cfg["g"]) >= 0.0 else default_g
	g_scale = g_eff / maxf(default_g, 0.001)
	for s in ALL:
		if only.is_empty() or s in only:
			scenarios.append(s)
	_make_floor()
	wall_start_usec = Time.get_ticks_usec()
	_next()


func _make_floor() -> void:
	floor_body = StaticBody3D.new()
	floor_body.name = "Floor"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 1, 10)
	cs.shape = bs
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	floor_body.physics_material_override = pm
	add_child(floor_body)


func _make_wall() -> void:
	wall_body = StaticBody3D.new()
	wall_body.name = "Wall"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.5, 8, 10)
	cs.shape = bs
	wall_body.add_child(cs)
	wall_body.position = Vector3(WALL_X + 0.25, 3.5, 0)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	wall_body.physics_material_override = pm
	add_child(wall_body)


func _spawn(pos: Vector3, zero_g: bool, rot_z: float = 0.0, passive: bool = false) -> void:
	if doll != null:
		remove_child(doll)   # сразу вон из физического мира, иначе старая кукла ещё тик толкает новую
		doll.queue_free()
	doll = DollScene.instantiate()
	_damp_override(doll)
	doll.external_input = true
	doll.muscle_stiffness = 0.0 if passive else float(cfg["k"])
	doll.muscle_damping = 0.0 if passive else float(cfg["c"])
	doll.joint_friction = 0.0 if passive else float(cfg["f"])
	doll.muscle_max_torque = 0.0 if passive else float(cfg["tmax"])
	doll.muscle_zeta = float(cfg["zeta"])
	# limit / pose_air меряют сборку из палки (как до v7); lie_creep — палка на спине (Т-рука ушла бы в пол), руки поднимаются пружинами
	doll.spawn_in_pose = not passive and not (S.get("id", "") in ["pose_air", "lie_creep"])
	doll.position = pos
	doll.rotation = Vector3(0, 0, rot_z)
	add_child(doll)
	if not passive:
		if not group_p.is_empty():
			doll.set_pose(group_p)
		var groups: Array = group_k.keys()
		for g in group_t.keys() + group_z.keys():
			if not groups.has(g):
				groups.append(g)
		for g in groups:
			var G: Dictionary = Tuning.MUSCLE_GROUPS.get(g, {})
			doll.set_muscle_group(g, float(group_k.get(g, G.get("k", 0.0))), float(group_t.get(g, -1.0)), float(group_z.get(g, -1.0)))
		if not group_f.is_empty():
			for j in doll.joints.values():
				var gn: String = String(j.name).split("_")[0]
				if group_f.has(gn):
					doll._friction_base[j] = float(group_f[gn])
			doll._refresh_muscles()
	for b in doll.parts.values():
		var rb := b as RigidBody3D
		rb.gravity_scale = 0.0 if zero_g else g_scale
		rb.contact_monitor = true
		rb.max_contacts_reported = 4
		if float(cfg["ld"]) >= 0.0 and not passive:
			rb.linear_damp = float(cfg["ld"])   # подбор DOLL_LINEAR_DAMP без пересборки doll.tscn (полёт после удара — Tuning.FLIGHT_LINEAR_DAMP)
		if passive:
			# limit меряет геометрию лимитов Jolt, а не feel: без дампа (DOLL_LINEAR_DAMP 1.5 гасит мах ноги раньше лимита)
			rb.linear_damp = 0.0
			rb.angular_damp = 0.0


func _damp_override(d: Doll) -> void:
	for k in DAMP_KEYS:
		if float(cfg[k]) >= 0.0:
			d.damp_override[DAMP_KEYS[k]] = float(cfg[k])
	for k in SOFT_KEYS:
		if float(cfg[k]) >= 0.0:
			d.soft_override[SOFT_KEYS[k]] = float(cfg[k])
	if not soft_groups.is_empty():
		d.soft_override["groups"] = soft_groups


func _next() -> void:
	idx += 1
	if wall_body != null:
		remove_child(wall_body)
		wall_body.queue_free()
		wall_body = null
	if attacker != null:
		remove_child(attacker)
		attacker.queue_free()
		attacker = null
	hit_log = []
	if idx >= scenarios.size():
		_finish()
		return
	var id: String = scenarios[idx]
	S = {"id": id, "m": {}}
	t = 0.0
	scen_max_speed = 0.0
	scen_min_y = 99.0
	match id:
		"limit":
			_spawn(Vector3(0, HOVER_H, 0), true, 0.0, true)
		"pose_air", "pose_api":
			_spawn(Vector3(0, HOVER_H, 0), true)
		"idle_air":
			_spawn(Vector3(0, 0.5, 0), false)
		"idle_floor", "spring_hand_floor", "spring_foot_floor", "torso_kick", "move":
			_spawn(Vector3.ZERO, false)
		"lie_creep":
			_spawn(Vector3(0.9, 0.25, 0), false, PI / 2.0)   # лежит на спине вдоль −X, макушка у x≈−0.9, ступни у x≈+0.9
		"spring_hand", "spring_foot":
			_spawn(Vector3(0, HOVER_H, 0), true)
		"hover_fall", "hover_up", "hover_hold":
			_spawn(Vector3(0, HOVER_H, 0), false)
		"wall_bounce":
			_make_wall()
			_spawn(WALL_SPAWN, false)
		"hit_flight_10", "hit_flight_30":
			_spawn(Vector3(0, HIT_H, 0), false)
		"hit_rush", "hit_dash", "hit_clash":
			_spawn(Vector3(0, HIT_H, 0), false)
			_add_combat(doll)
			doll.damaged.connect(_on_victim_damaged)
			attacker = DollScene.instantiate()
			_damp_override(attacker)
			attacker.name = "Attacker"
			attacker.external_input = true
			attacker.player_index = 1
			attacker.position = Vector3(-(float(cfg["gap"]) if float(cfg["gap"]) > 0.0 else HIT_GAP), HIT_H, 0)
			add_child(attacker)
			for b in attacker.parts.values():
				(b as RigidBody3D).gravity_scale = g_scale
				if float(cfg["ld"]) >= 0.0:
					(b as RigidBody3D).linear_damp = float(cfg["ld"])
			_add_combat(attacker)
		"lag_thrust_x", "lag_thrust_y", "lag_dash", "lag_spin", "lag_flip":
			_spawn(Vector3(0, HOVER_H, 0), true)
			if id == "lag_spin":
				# 29.09: присваивание стояло в ветке weapon_arm — lag_spin шёл в thrust4 и давал метрики lag_thrust_x один в один
				doll.control_mode = "rotate"
		"weapon_arm":
			_spawn(Vector3(0, HIT_H, 0), false)
	S["com0"] = doll.centre_of_mass()
	S["head0"] = doll.head().global_position.y


# --- измерения ---

func _angle(joint_name: String) -> float:
	var j: Generic6DOFJoint3D = doll.joints[joint_name]
	var a := j.get_node(j.node_a) as RigidBody3D
	var b := j.get_node(j.node_b) as RigidBody3D
	return rad_to_deg(wrapf(b.global_rotation.z - a.global_rotation.z, -PI, PI))


func _joint_angles() -> Dictionary:
	var out := {}
	for n in JOINT_ORDER:
		if doll.joints.has(n):
			out[n] = snappedf(_angle(n), 0.01)
	return out


## Поза покоя сустава (measured, градусы) — как её держит Doll (Tuning.POSE, R зеркально).
func _rest_deg(joint_name: String) -> float:
	return float(doll.get_pose().get(joint_name, 0.0))


## Отклонение сустава от позы покоя (градусы, со знаком).
func _pose_dev(joint_name: String) -> float:
	return rad_to_deg(wrapf(deg_to_rad(_angle(joint_name) - _rest_deg(joint_name)), -PI, PI))


## Отклонения всех суставов от позы: {joint: deg}, max по всем и max без Wrist/Ankle (кисть — dead band 8°, лодыжка без PD).
func _pose_devs() -> Dictionary:
	var per := {}
	var mx := 0.0
	var mx_main := 0.0
	for n in JOINT_ORDER:
		if not doll.joints.has(n):
			continue
		var d := _pose_dev(n)
		per[n] = snappedf(d, 0.01)
		mx = maxf(mx, absf(d))
		if not (n.begins_with("Wrist") or n.begins_with("Ankle")):
			mx_main = maxf(mx_main, absf(d))
	return {"per_joint": per, "max": mx, "max_main": mx_main}


func _torso_rot_deg() -> float:
	return rad_to_deg(wrapf(doll.torso().global_rotation.z, -PI, PI))


func _torso_tilt() -> float:
	return absf(_torso_rot_deg())


func _com_velocity() -> Vector3:
	var acc := Vector3.ZERO
	for b in doll.parts.values():
		var rb := b as RigidBody3D
		acc += rb.linear_velocity * rb.mass
	return acc / doll.total_mass


func _touching_part(other: Node) -> RigidBody3D:
	if other == null:
		return null
	for b in doll.parts.values():
		var rb := b as RigidBody3D
		if rb.get_colliding_bodies().has(other):
			return rb
	return null


func _on_floor() -> bool:
	return _touching_part(floor_body) != null


func _check(id: String, value: float, limit: float, cmp: String, detail: String) -> void:
	var ok := _cmp(value, limit, cmp)
	report["checks"].append({"id": id, "value": snappedf(value, 0.001), "limit": limit, "cmp": cmp, "ok": ok, "detail": detail})
	if not ok:
		report["ok"] = false


## Предварительная цель feel: пишется в targets[], валит exit только при strict=1.
func _target(id: String, value: float, limit: float, cmp: String, detail: String) -> void:
	var ok := _cmp(value, limit, cmp)
	report["targets"].append({"id": id, "value": snappedf(value, 0.001), "limit": limit, "cmp": cmp, "ok": ok, "detail": detail})
	if strict and not ok:
		report["ok"] = false


## Цель-полоса lo ≤ value ≤ hi.
func _target_range(id: String, value: float, lo: float, hi: float, detail: String) -> void:
	var ok := value >= lo and value <= hi
	report["targets"].append({"id": id, "value": snappedf(value, 0.001), "limit": [lo, hi], "cmp": "in", "ok": ok, "detail": detail})
	if strict and not ok:
		report["ok"] = false


static func _cmp(value: float, limit: float, cmp: String) -> bool:
	match cmp:
		"lt": return value < limit
		"gt": return value > limit
		"lte": return value <= limit
		"gte": return value >= limit
	return false


static func _finite(v: Variant) -> bool:
	if v is float:
		return is_finite(float(v))
	if v is Dictionary:
		for k in v:
			if not _finite(v[k]):
				return false
	if v is Array:
		for e in v:
			if not _finite(e):
				return false
	return true


func _done(m: Dictionary, has_floor: bool) -> void:
	var id: String = S["id"]
	m["max_part_speed"] = snappedf(scen_max_speed, 0.01)
	m["min_part_y"] = snappedf(scen_min_y, 0.001)
	m["sim_s"] = snappedf(t, 0.01)
	sim_total_s += t
	report["metrics"][id] = m
	_check(id + "_no_explosion", scen_max_speed, EXPLOSION_V, "lt", "max part speed (m/s)")
	if has_floor:
		_check(id + "_no_fall_through", scen_min_y, FALL_THROUGH_Y, "gt", "min part centre y (m), floor top at 0")
	_check(id + "_finite", 1.0 if _finite(m) else 0.0, 0.5, "gt", "all metrics finite (1 = yes)")
	_next()


# --- сценарии ---

func _physics_process(delta: float) -> void:
	if doll == null or idx >= scenarios.size():
		return
	t += delta
	total_ticks += 1
	scen_max_speed = maxf(scen_max_speed, doll.max_part_speed())
	for b in doll.parts.values():
		scen_min_y = minf(scen_min_y, (b as RigidBody3D).global_position.y)
	var id: String = S["id"]
	var m: Dictionary = S["m"]
	match id:
		"limit":
			_tick_limit(m)
		"pose_air":
			_tick_pose_air(m)
		"pose_api":
			_tick_pose_api(m)
		"idle_air", "idle_floor":
			_tick_idle(m)
		"lie_creep":
			_tick_lie(m)
		"spring_hand", "spring_foot", "spring_hand_floor", "spring_foot_floor":
			_tick_spring(m, id)
		"torso_kick":
			_tick_kick(m)
		"hover_fall":
			_tick_hover_fall(m)
		"hover_up", "hover_hold":
			_tick_hover_thrust(m, id)
		"move":
			_tick_move(m)
		"wall_bounce":
			_tick_wall(m)
		"hit_flight_10", "hit_flight_30", "hit_rush", "hit_dash", "hit_clash":
			_tick_hit(m, id)
		"lag_thrust_x", "lag_thrust_y", "lag_dash", "lag_spin", "lag_flip":
			_tick_lag(m, id)
		"weapon_arm":
			_tick_weapon_arm(m)


## Свободный мах без PD и трения: фаза 0 — импульс +X в Hand_L/Foot_L (рука/нога наружу), фаза 1 (респавн) — −X (внутрь).
func _tick_limit(m: Dictionary) -> void:
	doll.input_vec = Vector2.ZERO
	var phase := int(S.get("phase", 0))
	var tp: float = t - float(S.get("phase_t0", 0.0))
	if tp < 0.5:
		return
	if not S.has("kicked%d" % phase):
		S["kicked%d" % phase] = true
		var sgn := 1.0 if phase == 0 else -1.0
		(doll.parts["Hand_L"] as RigidBody3D).apply_central_impulse(Vector3(sgn * LIMIT_IMPULSE, 0, 0))
		(doll.parts["Foot_L"] as RigidBody3D).apply_central_impulse(Vector3(sgn * LIMIT_IMPULSE, 0, 0))
		if not S.has("mx"):
			S["mx"] = {}
		return
	var mx: Dictionary = S["mx"]
	for jn in ["Shoulder_L", "Elbow_L", "Wrist_L", "Hip_L", "Knee_L", "Ankle_L"]:
		var a := _angle(jn)
		mx[jn + "_min"] = minf(float(mx.get(jn + "_min", 0.0)), a)
		mx[jn + "_max"] = maxf(float(mx.get(jn + "_max", 0.0)), a)
	if tp < LIMIT_PHASE_S:
		return
	if phase == 0:
		S["phase"] = 1
		S["phase_t0"] = t
		_spawn(Vector3(0, HOVER_H, 0), true, 0.0, true)
		return
	for k in mx:
		m[k] = snappedf(float(mx[k]), 0.1)
	m["impulse_ns"] = LIMIT_IMPULSE
	var jl := {}
	for jn in ["Shoulder_L", "Elbow_L", "Wrist_L", "Hip_L", "Knee_L", "Ankle_L"]:
		var j: Generic6DOFJoint3D = doll.joints[jn]
		jl[jn] = [snappedf(rad_to_deg(float(j.get("angular_limit_z/lower_angle"))), 0.1), snappedf(rad_to_deg(float(j.get("angular_limit_z/upper_angle"))), 0.1)]
	m["jolt_lower_upper_deg"] = jl
	_target("limit_Shoulder_L_max", float(mx["Shoulder_L_max"]), 150.0, "gte", "free swing: arm reaches over the head (deg); T-pose reachable")
	_target("limit_Shoulder_L_min", float(mx["Shoulder_L_min"]), -40.0, "gte", "free swing: arm inward only ~30° (deg)")
	_target("limit_Elbow_L_min", float(mx["Elbow_L_min"]), -15.0, "gte", "elbow does not bend the wrong way (deg)")
	_target("limit_Knee_L_min", float(mx["Knee_L_min"]), -15.0, "gte", "knee does not bend the wrong way (deg)")
	_target("limit_Hip_L_max", float(mx["Hip_L_max"]), 100.0, "gte", "leg swings out/up to ~120 (deg)")
	_done(m, false)


## API позы: set_pose (группа с автозеркалом + сустав как есть, blend), get_pose, reset_pose.
func _tick_pose_api(m: Dictionary) -> void:
	doll.input_vec = Vector2.ZERO
	if t >= 2.0 and not S.has("set"):
		S["set"] = true
		doll.set_pose({"Shoulder": 45.0, "Elbow_R": -40.0}, 0.3)
		var gp := doll.get_pose()
		m["get_pose_after_set"] = {"Shoulder_L": snappedf(float(gp["Shoulder_L"]), 0.01), "Shoulder_R": snappedf(float(gp["Shoulder_R"]), 0.01), "Elbow_R": snappedf(float(gp["Elbow_R"]), 0.01), "Elbow_L": snappedf(float(gp["Elbow_L"]), 0.01)}
		var ok := absf(float(gp["Shoulder_L"]) - 45.0) < 0.01 and absf(float(gp["Shoulder_R"]) + 45.0) < 0.01 and absf(float(gp["Elbow_R"]) + 40.0) < 0.01 and absf(float(gp["Elbow_L"]) - 10.0) < 0.01
		_check("pose_api_get_pose", 1.0 if ok else 0.0, 0.5, "gt", "get_pose() after set_pose: Shoulder_L 45 / Shoulder_R −45 (group mirrored), Elbow_R −40 (joint as is), Elbow_L untouched 10 (1 = yes)")
	if t >= 3.5 and not S.has("mid"):
		S["mid"] = true
		m["set_angles_deg"] = {"Shoulder_L": snappedf(_angle("Shoulder_L"), 0.01), "Shoulder_R": snappedf(_angle("Shoulder_R"), 0.01), "Elbow_R": snappedf(_angle("Elbow_R"), 0.01)}
		var dev := maxf(absf(_angle("Shoulder_L") - 45.0), maxf(absf(_angle("Shoulder_R") + 45.0), absf(_angle("Elbow_R") + 40.0)))
		m["set_max_dev_deg"] = snappedf(dev, 0.01)
		_check("pose_api_set_reached", dev, 8.0, "lt", "1.5 s after set_pose(…, 0.3): shoulders ±45, Elbow_R −40 within 8° (deg)")
		doll.reset_pose(0.3)
	if t < 5.5:
		return
	var sh_pose := float(Tuning.POSE["Shoulder"])   # v7: 85° (было 90)
	var back := maxf(absf(_angle("Shoulder_L") - sh_pose), absf(_angle("Shoulder_R") + sh_pose))
	m["reset_max_dev_deg"] = snappedf(back, 0.01)
	_check("pose_api_reset", back, 8.0, "lt", "2 s after reset_pose(0.3): shoulders back to ±Tuning.POSE.Shoulder within 8° (deg)")
	_done(m, false)


## Невесомость, спавн прямой палкой: Т-поза собирается пружинами. Отклонения — от Doll.get_pose().
func _tick_pose_air(m: Dictionary) -> void:
	doll.input_vec = Vector2.ZERO
	if not S.has("osc"):
		var osc0 := {}
		for jn in JOINT_ORDER:
			osc0[jn] = {"dev0": _pose_dev(jn), "over": 0.0, "first_in": -1.0, "last_out": 0.0, "cross": 0, "last_sign": 0}
		S["osc"] = osc0
	var osc: Dictionary = S["osc"]
	for jn in JOINT_ORDER:
		var o: Dictionary = osc[jn]
		var dev := _pose_dev(jn)
		var d0 := float(o["dev0"])
		if absf(d0) > 1.0:
			o["over"] = maxf(float(o["over"]), -signf(d0) * dev)
		var sgn := 0
		if dev > SPRING_HYST_DEG:
			sgn = 1
		elif dev < -SPRING_HYST_DEG:
			sgn = -1
		if sgn != 0 and int(o["last_sign"]) != 0 and sgn != int(o["last_sign"]):
			o["cross"] = int(o["cross"]) + 1
		if sgn != 0:
			o["last_sign"] = sgn
		if absf(dev) > POSE_BAND_DEG:
			o["last_out"] = t
		elif float(o["first_in"]) < 0.0:
			o["first_in"] = t
	if t >= POSE_AIR_S - 1.0:
		S["v_last"] = maxf(float(S.get("v_last", 0.0)), doll.max_part_speed())
	if t < POSE_AIR_S:
		return
	var per := {}
	for jn in JOINT_ORDER:
		var o: Dictionary = osc[jn]
		var d0 := absf(float(o["dev0"]))
		per[jn] = {
			"dev0_deg": snappedf(float(o["dev0"]), 0.1),
			"t_first_in5_s": snappedf(float(o["first_in"]), 0.01),
			"settle_s": snappedf(float(o["last_out"]), 0.01),
			"overshoot_deg": snappedf(maxf(float(o["over"]), 0.0), 0.1),
			"overshoot_pct": snappedf(100.0 * maxf(float(o["over"]), 0.0) / d0, 0.1) if d0 > 1.0 else 0.0,
			"crossings": int(o["cross"]),
			"final_dev_deg": snappedf(_pose_dev(jn), 0.1),
		}
	var devs := _pose_devs()
	var drift := (doll.centre_of_mass() - (S["com0"] as Vector3)).length()
	m["joints"] = per
	m["angles_deg"] = _joint_angles()
	m["pose_deg"] = doll.get_pose()
	m["max_dev_end_deg"] = snappedf(float(devs["max"]), 0.01)
	m["com_drift_m"] = snappedf(drift, 0.001)
	m["torso_rot_end_deg"] = snappedf(_torso_rot_deg(), 0.1)
	m["part_speed_max_last1s"] = snappedf(float(S["v_last"]), 0.001)
	var sh: Dictionary = per["Shoulder_L"]
	var hip: Dictionary = per["Hip_L"]
	_target_range("pose_air_Shoulder_L_t_first_in5_s", float(sh["t_first_in5_s"]), 0.2, 0.45, "RM: arm returns from 90° into ±5° of rest in 0.25–0.35 s (s)")
	_target_range("pose_air_Shoulder_L_overshoot_pct", float(sh["overshoot_pct"]), 10.0, 45.0, "RM: visible overshoot 30–40 %; <10 wooden, >45 underdamped (%)")
	_target("pose_air_Shoulder_L_settle_s", float(sh["settle_s"]), 0.9, "lt", "RM: star assembles in 0.5–0.8 s (s)")
	_target_range("pose_air_Hip_L_t_first_in5_s", float(hip["t_first_in5_s"]), 0.0, 0.4, "legs do not lag behind arms (s)")
	_target("pose_air_max_dev_end_deg", float(devs["max"]), 8.0, "lt", "rest pose reached by all 13 joints (wrist dead band 8°) (deg)")
	_target("pose_air_com_drift_m", drift, 0.02, "lt", "PD creates no self-propulsion in zero g (m)")
	_target("pose_air_part_speed_last1s", float(S["v_last"]), 0.05, "lt", "no explicit-PD jitter at rest (m/s)")
	_done(m, false)


func _tick_idle(m: Dictionary) -> void:
	doll.input_vec = Vector2.ZERO
	if float(cfg["trace"]) > 0.0 and total_ticks % 10 == 0:
		print("TRACE %s t=%.2f hipL=%.1f kneeL=%.1f ankleL=%.1f footL=(%.3f,%.3f) footR=(%.3f,%.3f) torso_y=%.3f" % [S["id"], t, _angle("Hip_L"), _angle("Knee_L"), _angle("Ankle_L"),
			doll.parts["Foot_L"].global_position.x, doll.parts["Foot_L"].global_position.y, doll.parts["Foot_R"].global_position.x, doll.parts["Foot_R"].global_position.y, doll.torso().global_position.y])
	var tilt := _torso_tilt()
	if not m.has("fall_over_s") and tilt > FALL_OVER_DEG:
		m["fall_over_s"] = snappedf(t, 0.01)
	if t >= IDLE_CREEP_FROM_S and not S.has("com_mid"):
		S["com_mid"] = doll.centre_of_mass()
	if t >= IDLE_S - 2.0:
		S["v_last"] = maxf(float(S.get("v_last", 0.0)), doll.max_part_speed())
	if t < IDLE_S:
		return
	var com := doll.centre_of_mass()
	var com0: Vector3 = S["com0"]
	var mid: Vector3 = S["com_mid"]
	var devs := _pose_devs()
	m["pose_dev_deg"] = devs["per_joint"]
	m["pose_dev_max_deg"] = snappedf(float(devs["max"]), 0.01)
	m["pose_dev_max_main_deg"] = snappedf(float(devs["max_main"]), 0.01)
	m["part_speed_max_last2s"] = snappedf(float(S["v_last"]), 0.001)
	var angles := _joint_angles()
	var max_abs := 0.0
	for k in angles:
		max_abs = maxf(max_abs, absf(float(angles[k])))
	m["angles_deg"] = angles
	m["max_joint_abs_deg"] = snappedf(max_abs, 0.01)
	m["torso_tilt_deg"] = snappedf(tilt, 0.01)
	m["torso_rot_deg"] = snappedf(_torso_rot_deg(), 0.01)
	m["head_y"] = snappedf(doll.head().global_position.y, 0.001)
	m["head_y_start"] = snappedf(float(S["head0"]), 0.001)
	m["com_y"] = snappedf(com.y, 0.001)
	m["com_drift_x"] = snappedf(com.x - com0.x, 0.001)
	m["com_drift_y"] = snappedf(com.y - com0.y, 0.001)
	m["creep_x_last3s"] = snappedf(com.x - mid.x, 0.001)
	m["creep_xy_last3s"] = snappedf((com - mid).length(), 0.001)
	if not m.has("fall_over_s"):
		m["fall_over_s"] = -1.0
	m["on_floor_end"] = _on_floor()
	var id: String = S["id"]
	_target(id + "_creep_last3s", (com - mid).length(), 0.05, "lt", "Idle 3→6 s: |COM drift| after settling (m), no self-propulsion")
	_target(id + "_part_speed_last2s", float(S["v_last"]), 0.05, "lt", "Idle 4→6 s: max part speed (m/s), no jitter")
	# v7 (FEEL_TARGET §9.4): порог стойки — эталон RM, а не ±5°. RM стоя: руки 50–100° (±40° от Т), ноги раскрыты ±25–35° (§1, разбор
	# RM), руки качаются. ±5° (v6–v6.2) был строже эталона и держал плечо k ≥ 37 / бедро k ≥ 85 — пружины не отставали при разгоне
	# (плечо 26°, бедро 17°, RM 30–60°). Теперь: плечи ≤ 25°, бёдра ≤ 15°, локти/колени/шея ≤ 12°; кисть/лодыжка — только трение.
	# Остальное как было: стоит, не ползёт (creep < 0.05 м), нет дрожи (< 0.05 м/с), лежащая не встаёт, в невесомости ≤ 8° (pose_air).
	var per: Dictionary = devs["per_joint"]
	var gmax := {}
	for jn in per:
		var gn: String = String(jn).split("_")[0]
		if gn == "Wrist" or gn == "Ankle":
			continue
		gmax[gn] = maxf(float(gmax.get(gn, 0.0)), absf(float(per[jn])))
	m["pose_dev_group_max_deg"] = gmax
	for gn in IDLE_POSE_LIMIT_DEG:
		_target(id + "_pose_dev_" + gn + "_deg", float(gmax.get(gn, 0.0)), float(IDLE_POSE_LIMIT_DEG[gn]), "lte",
			"standing: %s within ±%.0f° of Tuning.POSE (RM standing: arms 50–100°, legs ±25–35°) (deg)" % [gn, float(IDLE_POSE_LIMIT_DEG[gn])])
	_done(m, true)


## Кукла спавнится лёжа на спине (root повёрнут на 90° вокруг Z): именно в этой позе PD k ≥ 60 «полз» в гейте 27.09.
func _tick_lie(m: Dictionary) -> void:
	doll.input_vec = Vector2.ZERO
	if t >= LIE_CREEP_FROM_S and not S.has("com_mid"):
		S["com_mid"] = doll.centre_of_mass()
	if t >= LIE_S - 2.0:
		S["v_last"] = maxf(float(S.get("v_last", 0.0)), doll.max_part_speed())
	if t < LIE_S:
		return
	var com := doll.centre_of_mass()
	var com0: Vector3 = S["com0"]
	var mid: Vector3 = S["com_mid"]
	var angles := _joint_angles()
	var max_abs := 0.0
	for k in angles:
		max_abs = maxf(max_abs, absf(float(angles[k])))
	m["angles_deg"] = angles
	m["max_joint_abs_deg"] = snappedf(max_abs, 0.01)
	m["torso_rot_deg"] = snappedf(_torso_rot_deg(), 0.01)
	m["head_y"] = snappedf(doll.head().global_position.y, 0.001)
	m["com_y"] = snappedf(com.y, 0.001)
	m["com_drift_x"] = snappedf(com.x - com0.x, 0.001)
	m["creep_x_last3s"] = snappedf(com.x - mid.x, 0.001)
	m["creep_xy_last3s"] = snappedf((com - mid).length(), 0.001)
	m["part_speed_max_last2s"] = snappedf(float(S["v_last"]), 0.01)
	m["settled_end"] = float(S["v_last"]) < SETTLED_V
	_target("lie_creep_last3s", (com - mid).length(), 0.05, "lt", "Lying on back 3→6 s: |COM drift| (m), the k>30 crawl bug")
	_target_range("lie_torso_rot_deg", absf(_torso_rot_deg()), 70.0, 110.0, "lying doll does not stand up / roll over from its own springs (|torso rot| deg)")
	_target("lie_part_speed_last2s", float(S["v_last"]), 0.6, "lt", "arm pressed into the floor at tmax clamp may twitch slightly (m/s)")
	_done(m, true)


## Момент инерции торса (бокс) вокруг Z — для сравнения с реальной ω после apply_torque_impulse (суставы и пол гасят).
func _torso_inertia_z() -> float:
	var torso := doll.torso()
	var shape := (torso.get_node("Shape") as CollisionShape3D).shape as BoxShape3D
	if shape == null:
		return 1.0
	var sz := shape.size
	return torso.mass / 12.0 * (sz.x * sz.x + sz.y * sz.y)


func _tick_spring(m: Dictionary, id: String) -> void:
	doll.input_vec = Vector2.ZERO
	var is_hand := id.begins_with("spring_hand")
	var zero_g := not id.ends_with("_floor")
	var watch: Array = ["Elbow_L", "Shoulder_L"] if is_hand else ["Knee_L", "Hip_L"]
	var settle := SPRING_SETTLE_ZERO_G_S if zero_g else SPRING_SETTLE_FLOOR_S
	if t < settle:
		return
	if not S.has("kick_t"):
		S["kick_t"] = t
		var rest := {}
		var osc := {}
		for jn in watch:
			rest[jn] = _angle(jn)
			osc[jn] = {"peak": 0.0, "over": 0.0, "cross": 0, "sign0": 0, "last_sign": 0, "last_out": -1.0, "final": 0.0}
		S["rest"] = rest
		S["osc"] = osc
		var part: RigidBody3D = doll.parts["Hand_L" if is_hand else "Foot_L"]
		var imp := SPRING_IMPULSE_HAND if is_hand else SPRING_IMPULSE_FOOT
		# кисть — по +Y (в Т-позе рука горизонтальна), стопа — по +X (нога вниз)
		part.apply_central_impulse(Vector3(0, imp, 0) if is_hand else Vector3(imp, 0, 0))
		S["part"] = part
		m["impulse_ns"] = imp
		m["part"] = part.name
		m["torso_tilt_at_kick_deg"] = snappedf(_torso_tilt(), 0.01)
		return
	var since: float = t - float(S["kick_t"])
	var rest: Dictionary = S["rest"]
	var osc: Dictionary = S["osc"]
	for jn in watch:
		var o: Dictionary = osc[jn]
		var dev := _angle(jn) - float(rest[jn])
		var sgn := 0
		if dev > SPRING_HYST_DEG:
			sgn = 1
		elif dev < -SPRING_HYST_DEG:
			sgn = -1
		if int(o["sign0"]) == 0 and sgn != 0:
			o["sign0"] = sgn
		if sgn != 0 and int(o["last_sign"]) != 0 and sgn != int(o["last_sign"]):
			o["cross"] = int(o["cross"]) + 1
		if sgn != 0:
			o["last_sign"] = sgn
		o["peak"] = maxf(float(o["peak"]), absf(dev))
		if int(o["sign0"]) != 0:
			o["over"] = maxf(float(o["over"]), -float(int(o["sign0"])) * dev)
		if absf(dev) > SPRING_BAND_DEG:
			o["last_out"] = since
		o["final"] = dev
	if since < SPRING_WINDOW_S:
		return
	var part: RigidBody3D = S["part"]
	for jn in watch:
		var o: Dictionary = osc[jn]
		var last_out := float(o["last_out"])
		var settled := last_out < since - 0.05     # последний выход из ±5° не в самом конце окна
		var settle_s := -1.0
		if settled:
			settle_s = maxf(last_out, 0.0)
		m[jn] = {
			"rest_deg": snappedf(float(rest[jn]), 0.01),
			"peak_deg": snappedf(float(o["peak"]), 0.01),
			"overshoot_deg": snappedf(maxf(float(o["over"]), 0.0), 0.01),
			"crossings": int(o["cross"]),
			"settle_s": snappedf(settle_s, 0.01),
			"final_dev_deg": snappedf(float(o["final"]), 0.01),
		}
		# на полу дистальный сустав (локоть / колено) держит опора: кисть/стопа прижата трением пола, возврат зависит от контакта,
		# а не от пружин (FEEL_TARGET §7 целей для них не задаёт) — только метрика; цели — в невесомости и для плеча/бедра
		if zero_g or jn == watch[1]:
			_target(id + "_" + jn + "_settles", settle_s, 0.0, "gte", "joint returns to ±5° of rest within window (s; -1 = never)")
			_target(id + "_" + jn + "_settle_s", settle_s if settle_s >= 0.0 else 99.0, 1.5, "lt", "settle time (s)")
	var prox: String = watch[1]   # проксимальный сустав (плечо / бедро): импульс в кисть/стопу должен реально качнуть конечность
	_target(id + "_" + prox + "_swings", float((osc[prox] as Dictionary)["peak"]), SPRING_BAND_DEG, "gt", "proximal joint peak deviation (deg) > band, i.e. the impulse actually swings the limb")
	if zero_g:
		var ps: float = float((m[prox] as Dictionary)["settle_s"])
		_target(id + "_" + prox + "_settle_s_rm", ps if ps >= 0.0 else 99.0, 0.6, "lt", "RM: proximal joint back within ±5° after the push (s)")
		var cj: String = "Elbow_L" if is_hand else "Hip_L"
		_target(id + "_" + cj + "_crossings", float((m[cj] as Dictionary)["crossings"]), 3.0, "lte", "one or two swings, no ringing")
	m["part_speed_end"] = snappedf(part.linear_velocity.length(), 0.01)
	m["window_s"] = SPRING_WINDOW_S
	_done(m, not zero_g)


func _tick_kick(m: Dictionary) -> void:
	doll.input_vec = Vector2.ZERO
	if t < KICK_SETTLE_S:
		return
	var torso := doll.torso()
	if not S.has("kick_t"):
		S["kick_t"] = t
		S["com_k"] = doll.centre_of_mass()
		S["rot_prev"] = torso.global_rotation.z
		S["turns"] = 0.0
		S["max_w"] = 0.0
		S["stop_t"] = -1.0
		S["slow_since"] = -1.0
		m["impulse_nms"] = Tuning.FLIP_IMPULSE
		m["torso_tilt_before_deg"] = snappedf(_torso_tilt(), 0.01)
		torso.apply_torque_impulse(Vector3(0, 0, Tuning.FLIP_IMPULSE))
		return
	var since: float = t - float(S["kick_t"])
	if not m.has("w_first_tick_rad_s"):
		m["w_first_tick_rad_s"] = snappedf(absf(torso.angular_velocity.z), 0.01)
		m["w_free_torso_analytic"] = snappedf(Tuning.FLIP_IMPULSE / _torso_inertia_z(), 0.01)
	if since >= KICK_WINDOW_S - KICK_CREEP_LAST_S:
		S["v_last"] = maxf(float(S.get("v_last", 0.0)), doll.max_part_speed())
	var rz := torso.global_rotation.z
	S["turns"] = float(S["turns"]) + absf(wrapf(rz - float(S["rot_prev"]), -PI, PI)) / TAU
	S["rot_prev"] = rz
	var w := absf(torso.angular_velocity.z)
	S["max_w"] = maxf(float(S["max_w"]), w)
	if float(S["stop_t"]) < 0.0:
		if w < SPIN_STOP_W:
			if float(S["slow_since"]) < 0.0:
				S["slow_since"] = since
			elif since - float(S["slow_since"]) >= SPIN_STOP_HOLD_S:
				S["stop_t"] = float(S["slow_since"])
		else:
			S["slow_since"] = -1.0
	if since >= KICK_WINDOW_S - KICK_CREEP_LAST_S and not S.has("com_c"):
		S["com_c"] = doll.centre_of_mass()
	if since < KICK_WINDOW_S:
		return
	var com := doll.centre_of_mass()
	var com_k: Vector3 = S["com_k"]
	var com_c: Vector3 = S["com_c"]
	m["spin_stop_s"] = snappedf(float(S["stop_t"]), 0.01)
	m["max_w_rad_s"] = snappedf(float(S["max_w"]), 0.01)
	m["turns"] = snappedf(float(S["turns"]), 0.01)
	m["w_end_rad_s"] = snappedf(w, 0.01)
	m["com_drift_x_9s"] = snappedf(com.x - com_k.x, 0.001)
	m["com_drift_xy_9s"] = snappedf((com - com_k).length(), 0.001)
	m["creep_xy_last2s"] = snappedf((com - com_c).length(), 0.001)
	m["part_speed_max_last2s"] = snappedf(float(S["v_last"]), 0.01)
	m["settled_end"] = float(S["v_last"]) < SETTLED_V
	m["torso_tilt_end_deg"] = snappedf(_torso_tilt(), 0.01)
	m["head_y_end"] = snappedf(doll.head().global_position.y, 0.001)
	_target("torso_kick_settled", 1.0 if float(S["v_last"]) < SETTLED_V else 0.0, 0.5, "gt", "doll at rest in the last 2 s of the 9 s window (1 = yes)")
	_target("torso_kick_creep_last2s", (com - com_c).length(), 0.1, "lt", "after spin: |COM drift| in last 2 s (m), no crawling")
	_target_range("torso_kick_spin_stops", float(S["stop_t"]), 0.0, 0.999, "FLIP spin on the floor dies within 1 s (s; -1 = never)")
	_target("torso_kick_part_speed_last2s", float(S["v_last"]), 0.05, "lt", "no residual jitter after the kick (m/s)")
	_done(m, true)


func _tick_hover_fall(m: Dictionary) -> void:
	doll.input_vec = Vector2.ZERO
	var torso := doll.torso()
	if t >= 1.0 and not m.has("vy_1s"):
		m["vy_1s"] = snappedf(torso.linear_velocity.y, 0.01)
		var d := 0.0   # v6.2: дамп разный у ядра/конечностей (+ IDLE_BRAKE_DAMP торса без ввода) — берём средневзвешенный по массе
		for b in doll.parts.values():
			d += (b as RigidBody3D).linear_damp * (b as RigidBody3D).mass / doll.total_mass
		m["damp_eff"] = snappedf(d, 0.001)
		m["vy_1s_analytic"] = snappedf(-(g_eff / d) * (1.0 - exp(-d * 1.0)) if d > 0.0 else -g_eff, 0.01)
	if not m.has("land_s"):
		var part := _touching_part(floor_body)
		if part != null:
			m["land_s"] = snappedf(t, 0.01)
			m["land_part"] = part.name
			m["land_v"] = snappedf(float(S.get("prev_v", 0.0)), 0.01)
			m["land_s_analytic_no_damp"] = snappedf(sqrt(2.0 * HOVER_H / g_eff) if g_eff > 0.0 else -1.0, 0.01)
		else:
			S["prev_v"] = torso.linear_velocity.length()
			if t >= HOVER_FALL_MAX_S:
				m["land_s"] = -1.0
				m["landed"] = false
				_check("hover_fall_landed", 0.0, 0.5, "gt", "doll reaches the floor from 3 m within 4 s (1 = yes)")
				_done(m, true)
		return
	if t >= float(m["land_s"]) + HOVER_AFTER_LAND_S:
		m["landed"] = true
		_target_range("hover_fall_vy_1s", float(m.get("vy_1s", 0.0)), -1.5, -0.7, "RM: terminal settling 0.4–0.75 H/s reached within 1 s (m/s)")
		_target("hover_fall_land_v", float(m["land_v"]), 1.6, "lt", "landing from 3 m at terminal speed (m/s)")
		m["torso_tilt_end_deg"] = snappedf(_torso_tilt(), 0.01)
		_check("hover_fall_landed", 1.0, 0.5, "gt", "doll reaches the floor from 3 m within 4 s (1 = yes)")
		_done(m, true)


func _tick_hover_thrust(m: Dictionary, id: String) -> void:
	var input_y := 1.0 if id == "hover_up" else g_eff / Tuning.MOVE_FORCE_PER_KG
	doll.input_vec = Vector2(0.0, input_y)
	var torso := doll.torso()
	var com := doll.centre_of_mass()
	var com0: Vector3 = S["com0"]
	S["min_y"] = minf(float(S.get("min_y", com.y)), com.y)
	S["max_y"] = maxf(float(S.get("max_y", com.y)), com.y)
	if t >= 1.0 and not m.has("vy_1s"):
		m["vy_1s"] = snappedf(torso.linear_velocity.y, 0.01)
	if not S.has("floor_t") and _on_floor():
		S["floor_t"] = t
	if t < HOVER_THRUST_S:
		return
	m["input_y"] = snappedf(input_y, 0.001)
	m["dy_com"] = snappedf(com.y - com0.y, 0.001)
	m["min_dy"] = snappedf(float(S["min_y"]) - com0.y, 0.001)
	m["max_dy"] = snappedf(float(S["max_y"]) - com0.y, 0.001)
	m["vy_end"] = snappedf(torso.linear_velocity.y, 0.01)
	m["torso_tilt_end_deg"] = snappedf(_torso_tilt(), 0.01)
	m["floor_touch_s"] = snappedf(float(S.get("floor_t", -1.0)), 0.01)
	if id == "hover_up":
		_check("hover_up_climbs", com.y - com0.y, 0.5, "gt", "full up-thrust for 2.5 s from 3 m: COM dy (m)")
	else:
		_target("hover_hold_altitude", absf(com.y - com0.y), 0.5, "lt", "thrust g/MOVE_FORCE_PER_KG holds altitude: |COM dy| over 2.5 s (m)")
	_done(m, true)


func _tick_move(m: Dictionary) -> void:
	var torso := doll.torso()
	var tv := torso.linear_velocity
	if t < MOVE_SETTLE_S:
		doll.input_vec = Vector2.ZERO
		S["com_ref"] = doll.centre_of_mass()
		return
	if t < MOVE_SETTLE_S + MOVE_S:
		doll.input_vec = Vector2(1.0, 0.0)
		var sp := tv.length()
		S["vmax"] = maxf(float(S.get("vmax", 0.0)), sp)
		S["tilt_max"] = maxf(float(S.get("tilt_max", 0.0)), _torso_tilt())
		if not m.has("t90") and sp >= 0.9 * Tuning.MAX_MOVE_SPEED:
			m["t90"] = snappedf(t - MOVE_SETTLE_S, 0.01)
		if not m.has("v_0p5s") and t >= MOVE_SETTLE_S + 0.5:
			m["v_0p5s"] = snappedf(sp, 0.01)
		return
	var com := doll.centre_of_mass()
	if not S.has("rel"):
		S["rel"] = com
		S["rel_t"] = t
		var ref: Vector3 = S["com_ref"]
		m["thrust_s"] = MOVE_S
		m["dx_thrust"] = snappedf(com.x - ref.x, 0.001)
		m["v_thrust_end"] = snappedf(tv.length(), 0.01)
		m["vmax_torso"] = snappedf(float(S["vmax"]), 0.01)
		m["v90_target"] = snappedf(0.9 * Tuning.MAX_MOVE_SPEED, 0.01)
		if not m.has("t90"):
			m["t90"] = -1.0
		m["torso_tilt_max_deg"] = snappedf(float(S["tilt_max"]), 0.01)
		m["torso_y_thrust_end"] = snappedf(torso.global_position.y, 0.001)
		m["on_floor_thrust_end"] = _on_floor()
		# t90 (0.9·MAX_MOVE_SPEED) — справочно: при DOLL_LINEAR_DAMP 1.5 терминальная тяги 8 м/с < 8.1, клэмп не достигается (FEEL_TARGET §4)
		_check("move_responds", com.x - ref.x, 0.6, "gt", "thrust +X for 1.5 s moves COM (m)")
		_target_range("move_v_0p5s", float(m.get("v_0p5s", 0.0)), 3.6, 5.4, "RM: 0 → 1.5–2.4 H/s in 0.5 s (m/s)")
	doll.input_vec = Vector2.ZERO
	var rel: Vector3 = S["rel"]
	var since: float = t - float(S["rel_t"])
	if not m.has("stop_s") and tv.length() < MOVE_STOP_V:
		m["stop_s"] = snappedf(since, 0.01)
		m["stop_dist"] = snappedf(com.x - rel.x, 0.001)
	if since < MOVE_BRAKE_S:
		return
	if not m.has("stop_s"):
		m["stop_s"] = -1.0
		m["stop_dist"] = snappedf(com.x - rel.x, 0.001)
	m["v_after_brake_3s"] = snappedf(tv.length(), 0.01)
	m["brake_dist_3s"] = snappedf(com.x - rel.x, 0.001)
	_target_range("move_stop_s", float(m["stop_s"]), 0.6, 1.6, "RM: speed dies in ~1 s after release (s; -1 = never in 3 s)")
	_target("move_stop_dist_m", float(m["stop_dist"]), 3.6, "lt", "coast after release <= 2 heights (m)")
	_done(m, true)


func _tick_wall(m: Dictionary) -> void:
	var torso := doll.torso()
	var tv := torso.linear_velocity
	var cv := _com_velocity()
	if not S.has("hit_t"):
		doll.input_vec = Vector2(1.0, 0.0)
		var part := _touching_part(wall_body)
		if part != null:
			S["hit_t"] = t
			S["vout_t"] = tv.x
			S["vout_c"] = cv.x
			m["contact_s"] = snappedf(t, 0.01)
			m["first_part"] = part.name
			m["v_in_torso"] = snappedf(float(S.get("prev_vx", 0.0)), 0.01)
			m["v_in_com"] = snappedf(float(S.get("prev_com_vx", 0.0)), 0.01)
			m["torso_y_at_hit"] = snappedf(torso.global_position.y, 0.001)
			m["on_floor_at_hit"] = _on_floor()
		else:
			S["prev_vx"] = tv.x
			S["prev_com_vx"] = cv.x
			if t >= WALL_MAX_S:
				m["contact_s"] = -1.0
				_check("wall_bounce_contact", 0.0, 0.5, "gt", "doll reaches the wall at x=+3 within 3 s (1 = yes)")
				_done(m, true)
		return
	doll.input_vec = Vector2.ZERO
	S["vout_t"] = minf(float(S["vout_t"]), tv.x)
	S["vout_c"] = minf(float(S["vout_c"]), cv.x)
	if t - float(S["hit_t"]) < WALL_AFTER_S:
		return
	var v_in_t := float(m["v_in_torso"])
	var v_in_c := float(m["v_in_com"])
	var v_out_t := maxf(-float(S["vout_t"]), 0.0)
	var v_out_c := maxf(-float(S["vout_c"]), 0.0)
	m["v_out_torso"] = snappedf(v_out_t, 0.01)
	m["v_out_com"] = snappedf(v_out_c, 0.01)
	m["restitution_torso"] = snappedf(v_out_t / v_in_t if v_in_t > 0.01 else 0.0, 0.001)
	m["restitution_com"] = snappedf(v_out_c / v_in_c if v_in_c > 0.01 else 0.0, 0.001)
	m["torso_x_end"] = snappedf(torso.global_position.x, 0.001)
	m["torso_tilt_end_deg"] = snappedf(_torso_tilt(), 0.01)
	_check("wall_bounce_contact", 1.0, 0.5, "gt", "doll reaches the wall at x=+3 within 3 s (1 = yes)")
	_target("wall_bounce_restitution_com", float(m["restitution_com"]), 0.2, "lt", "RM <= 0.1: doll sticks to the wall, no rubber bounce")
	_done(m, true)

func _add_combat(d: Doll) -> void:
	var c := DollCombat.new()
	c.name = "DollCombat"
	d.add_child(c)


func _on_victim_damaged(amount: float, _attacker: Node, part: String, _position: Vector3, kind: String) -> void:
	hit_log.append({"amount": snappedf(amount, 0.01), "kind": kind, "part": part, "t": snappedf(t, 0.001)})


static func _doll_com_velocity(d: Doll) -> Vector3:
	var acc := Vector3.ZERO
	for b in d.parts.values():
		var rb := b as RigidBody3D
		acc += rb.linear_velocity * rb.mass
	return acc / d.total_mass


## Полёт после удара (FEEL_TARGET §9). hit_flight_10/30 — Doll.apply_knockback как в DollCombat._deliver (Damage.knockback_impulse,
## knockback_dir(+X) с апбиасом, 10 HP в торс / 30 HP в голову + стан Damage.stun_seconds); hit_rush / hit_dash — настоящий удар:
## кукла-атакующий (все части HIT_RUSH_V / HIT_DASH_V по +X, как _inject в combat_gate) влетает в висящую жертву, урон и отброс —
## DollCombat/Damage. Жертва в воздухе на HIT_H: v0 (max |vx ЦМ| за HIT_V0_WINDOW_S), время до |vx| < 0.4, vy ЦМ через 1 и 2 с,
## минимум vy (оседание не разгоняется), путь по X.
func _tick_hit(m: Dictionary, id: String) -> void:
	doll.input_vec = Vector2.ZERO
	var real := id == "hit_rush" or id == "hit_dash" or id == "hit_clash"
	if real:
		attacker.input_vec = Vector2.ZERO
	if t < HIT_SETTLE_S:
		return
	var vc := _com_velocity()
	if not S.has("hit_t"):
		if real:
			if hit_log.is_empty():
				var v := HIT_RUSH_V if id == "hit_rush" else (HIT_CLASH_V.x if id == "hit_clash" else HIT_DASH_V)
				var avy := _doll_com_velocity(attacker).y
				for p in attacker.parts.values():
					(p as RigidBody3D).linear_velocity = Vector3(v, avy, 0.0)
					(p as RigidBody3D).angular_velocity = Vector3.ZERO
				if id == "hit_clash":
					for p in doll.parts.values():
						(p as RigidBody3D).linear_velocity = Vector3(-HIT_CLASH_V.y, vc.y, 0.0)
						(p as RigidBody3D).angular_velocity = Vector3.ZERO
				if t > HIT_SETTLE_S + 2.0:
					_check(id + "_hit", 0.0, 0.5, "gt", "attacker reaches the victim within 2 s (1 = yes)")
					_done(m, true)
				return
			S["hit_t"] = float((hit_log[0] as Dictionary)["t"])
			m["first_hit"] = hit_log[0]
			m["attacker_v_in"] = HIT_RUSH_V if id == "hit_rush" else (HIT_CLASH_V.x if id == "hit_clash" else HIT_DASH_V)
			if id == "hit_clash":
				m["victim_v_in"] = -HIT_CLASH_V.y
			S["sep0"] = absf(attacker.centre_of_mass().x - doll.centre_of_mass().x)
		else:
			var dmg := 10.0 if id == "hit_flight_10" else 30.0
			var part: RigidBody3D = doll.parts["Torso" if dmg < 20.0 else "Head"]
			var j := Damage.knockback_impulse(dmg)
			var stun_s := Damage.stun_seconds(dmg)
			doll.apply_knockback(Damage.knockback_dir(Vector3.RIGHT) * j, part, stun_s, Vector3.RIGHT)
			if stun_s > 0.0:
				doll.stun(stun_s)
			S["hit_t"] = t
			m["damage"] = dmg
			m["impulse_ns"] = snappedf(j, 0.1)
			m["part"] = part.name
			m["stun_s"] = snappedf(stun_s, 0.01)
			m["v_impulse_whole_doll"] = snappedf(j / doll.total_mass, 0.01)
		S["x0"] = doll.centre_of_mass().x
		S["v0"] = 0.0
		S["vy_min"] = 0.0
		return
	var since: float = t - float(S["hit_t"])
	if since <= HIT_FOLD_WINDOW_S:
		var fold: Dictionary = S.get("fold", {})
		for jn in LAG_JOINTS:
			fold[jn] = maxf(float(fold.get(jn, 0.0)), absf(_pose_dev(jn)))
		S["fold"] = fold
	if not S.has("series"):
		S["series"] = {}
	for jn in LAG_JOINTS:
		if not (S["series"] as Dictionary).has(jn):
			S["series"][jn] = []
		(S["series"][jn] as Array).append([since, _pose_dev(jn)])
	if real and since >= HIT_SEP_AT_S and not m.has("sep_0p6s"):
		m["sep_0p6s"] = snappedf(absf(attacker.centre_of_mass().x - doll.centre_of_mass().x), 0.001)
	if real and since >= 1.0 and not m.has("sep_1s"):
		m["sep_1s"] = snappedf(absf(attacker.centre_of_mass().x - doll.centre_of_mass().x), 0.001)
		m["attacker_vx_1s"] = snappedf(_doll_com_velocity(attacker).x, 0.01)
	if since <= HIT_V0_WINDOW_S:
		S["v0"] = maxf(float(S["v0"]), vc.x)   # удар всегда в +X; у hit_clash жертва подлетала с −3 м/с — модуль считал бы подлёт
		if not S.has("trace"):
			S["trace"] = []
		(S["trace"] as Array).append([snappedf(since, 0.001), snappedf(vc.x, 0.01), doll.is_flying()])
		S["v0_total"] = maxf(float(S.get("v0_total", 0.0)), vc.length())
	elif not m.has("stop_s") and absf(vc.x) < HIT_STOP_VX:
		m["stop_s"] = snappedf(since, 0.01)
		m["stop_dx"] = snappedf(doll.centre_of_mass().x - float(S["x0"]), 0.001)
	S["vx_max"] = maxf(float(S.get("vx_max", 0.0)), absf(vc.x))
	if since >= 0.5:
		S["vy_min"] = minf(float(S["vy_min"]), vc.y)
	if since >= 1.0 and not m.has("vy_1s"):
		m["vy_1s"] = snappedf(vc.y, 0.01)
		m["vx_1s"] = snappedf(vc.x, 0.01)
	if since >= 2.0 and not m.has("vy_2s"):
		m["vy_2s"] = snappedf(vc.y, 0.01)
	if real and since >= 0.3 and not m.has("attacker_vx_0p3s"):
		m["attacker_vx_0p3s"] = snappedf(_doll_com_velocity(attacker).x, 0.01)
	if not S.has("floor_t") and _on_floor():
		S["floor_t"] = since
	if since < HIT_WINDOW_S:
		return
	m["v0_x"] = snappedf(float(S["v0"]), 0.01)
	m["v0_total"] = snappedf(float(S.get("v0_total", 0.0)), 0.01)
	m["v0_heights_s"] = snappedf(float(S["v0"]) / 1.8, 0.01)
	m["vx_max_3s"] = snappedf(float(S.get("vx_max", 0.0)), 0.01)
	if not m.has("stop_s"):
		m["stop_s"] = -1.0
	m["dx_3s"] = snappedf(doll.centre_of_mass().x - float(S["x0"]), 0.001)
	m["vy_min_after_0p5s"] = snappedf(float(S["vy_min"]), 0.01)
	m["floor_touch_s"] = snappedf(float(S.get("floor_t", -1.0)), 0.01)
	m["hits"] = hit_log.slice(0, 8)
	m["vx_trace_0p5s"] = S.get("trace", [])
	m["hp_after"] = snappedf(doll.hp, 0.01)
	var fold: Dictionary = S.get("fold", {})
	var folded := 0
	var fold_out := {}
	for jn in LAG_JOINTS:
		fold_out[jn] = snappedf(float(fold.get(jn, 0.0)), 0.1)
		if float(fold.get(jn, 0.0)) >= HIT_FOLD_DEG:
			folded += 1
	m["limb_fold_deg"] = fold_out
	m["limbs_folded"] = folded
	# v7: складывание за HIT_FOLD_FAST_S и возврат в ±HIT_RETURN_BAND_DEG — по ведущему плечу и ведущему бедру
	var fast := _fold_return(S.get("series", {}))
	m["fold_fast"] = fast
	if float(cfg["trace"]) > 0.0:
		var ser: Dictionary = S.get("series", {})
		for jn in LAG_JOINTS:
			var line := "TRACE %s %s:" % [id, jn]
			for smp in ser.get(jn, []):
				if int(round(float(smp[0]) * 60.0)) % 3 == 0 and float(smp[0]) <= 1.5:
					line += " %.2f:%.0f" % [float(smp[0]), float(smp[1])]
			print(line)
	if real:
		m["sep_at_hit"] = snappedf(float(S.get("sep0", 0.0)), 0.001)
	var v0 := float(S["v0"])
	var stop := float(m["stop_s"])
	match id:
		"hit_flight_10":
			_target_range(id + "_v0", v0, 1.8, 3.6, "RM: ordinary hit sends the victim at 1–2 H/s (m/s, COM |vx|)")
		"hit_flight_30":
			_target_range(id + "_v0", v0, 1.8, 5.5, "RM: heavy hit (dash/weapon/head) <= ~3 H/s (m/s, COM |vx|)")
		"hit_dash":
			_target(id + "_v0", v0, 5.5, "lte", "RM: dash hit sends the victim <= ~3 H/s; was 7.3 m/s in the v5 clip (m/s, COM |vx|)")
		"hit_rush":
			_target(id + "_v0", v0, 5.5, "lte", "RM: rush hit into a hovering victim <= ~3 H/s (m/s, COM |vx|)")
		"hit_clash":
			_target_range(id + "_v0", v0, 1.8, 5.5, "RM: head-on bump still sends the victim away at >= 1 H/s (v6 clip: 0.68 m/s) (m/s, COM |vx|)")
	if real:
		# v6.2: отдача атакующего (DollCombat → Doll.apply_recoil) — он больше не дожимает жертву телом (v6: 1.6–1.9 с, клип 1.57 с);
		# критик круга 2: ≤ 1.3 с (RM ~1–1.2 с)
		_target_range(id + "_stop_s", stop if stop >= 0.0 else 99.0, 0.0, 1.3, "RM ~1–1.2 s: flight after a real hit dies to < 0.4 m/s (s; -1 = never)")
		# RM: жертва уходит ~1 H/с, бьющий зависает поодаль. v6: ЦМ 0.7–1.2 м через 0.6–1 с (клип: < 1 H 5 с после рывка)
		_target(id + "_sep_0p6s", float(m.get("sep_0p6s", 0.0)), 2.7, "gte", "RM: attacker and victim COMs >= 1.5 H apart 0.6 s after the hit (m)")
		_target(id + "_attacker_vx_0p3s", float(m.get("attacker_vx_0p3s", 99.0)), 0.5, "lte", "attacker does not follow the victim: COM vx toward it 0.3 s after the hit (m/s)")
	else:
		_target_range(id + "_stop_s", stop if stop >= 0.0 else 99.0, 0.9, 1.5, "RM: flight dies to < 0.4 m/s horizontally in ~1–1.2 s (s; -1 = never)")
	# складывание конечностей жертвы (HIT_MUSCLE_SOFT): RM 00:16.6 — все четыре на ≥ 90°; физически (удар вдоль Т-рук их не качает)
	# ведущая конечность ≥ 35° (v6: 21–30° у 10 HP, у наскока 44° только за счёт дожима телом)
	var fold_max := 0.0
	for jn in LAG_JOINTS:
		fold_max = maxf(fold_max, float(fold.get(jn, 0.0)))
	_target(id + "_limb_fold_deg", fold_max, 35.0, "gte", "victim limbs fold on the hit (max shoulder/hip deviation in %.1f s, deg)" % HIT_FOLD_WINDOW_S)
	if id == "hit_flight_10":
		for gname in ["Shoulder", "Hip"]:
			var e: Dictionary = fast[gname]
			_target(id + "_" + gname + "_fold_0p4s_deg", float(e["fold_deg"]), HIT_FOLD_FAST_DEG, "gte",
				"RM 00:16.6: 10 HP into the torso folds the leading %s >= %.0f° within %.1f s (%s, deg)" % [gname, HIT_FOLD_FAST_DEG, HIT_FOLD_FAST_S, e["joint"]])
			var rt := float(e["return_s"])
			_target(id + "_" + gname + "_return_s", rt if rt >= 0.0 else 99.0, HIT_RETURN_S, "lte",
				"RM: star again ~0.67 s after the hit: leading %s back within ±%.0f° of pose (%s, s after the hit; -1 = never)" % [gname, HIT_RETURN_BAND_DEG, e["joint"]])
	_target(id + "_vy_1s", float(m.get("vy_1s", -99.0)), -1.4, "gte", "RM: settling after a hit is a constant 0.4–0.75 H/s, no free fall (m/s)")
	_target(id + "_vy_2s", float(m.get("vy_2s", -99.0)), -1.4, "gte", "RM: settling does not accelerate 2 s after the hit (m/s)")
	_target(id + "_vy_min", float(S["vy_min"]), -1.4, "gte", "min COM vy 0.5–3 s after the hit (m/s)")
	_done(m, true)


## v7: по ведущему (max |dev| за HIT_FOLD_FAST_S) плечу и бедру: fold_deg — max |dev| за HIT_FOLD_FAST_S, peak_deg/peak_t — за
## HIT_FOLD_WINDOW_S, return_s — первый вход в ±HIT_RETURN_BAND_DEG после пика (с от удара), settle_s — последний выход из этой полосы
## (с от удара), overshoot_deg — max отклонение в другую сторону после возврата.
func _fold_return(series: Dictionary) -> Dictionary:
	var out := {}
	for gname in ["Shoulder", "Hip"]:
		var best := ""
		var best_f := -1.0
		for jn in [gname + "_L", gname + "_R"]:
			var f := 0.0
			for smp in series.get(jn, []):
				if float(smp[0]) <= HIT_FOLD_FAST_S:
					f = maxf(f, absf(float(smp[1])))
			if f > best_f:
				best_f = f
				best = jn
		var peak := 0.0
		var peak_t := 0.0
		var sgn := 0.0
		for smp in series.get(best, []):
			if float(smp[0]) <= HIT_FOLD_WINDOW_S and absf(float(smp[1])) > peak:
				peak = absf(float(smp[1]))
				peak_t = float(smp[0])
				sgn = signf(float(smp[1]))
		var ret := -1.0
		var settle := 0.0
		var over := 0.0
		for smp in series.get(best, []):
			var ts := float(smp[0])
			var dv := float(smp[1])
			if absf(dv) >= HIT_RETURN_BAND_DEG:
				settle = ts
			if ts <= peak_t:
				continue
			if ret < 0.0:
				if absf(dv) < HIT_RETURN_BAND_DEG:
					ret = ts
			else:
				over = maxf(over, -sgn * dv)
		out[gname] = {"joint": best, "fold_deg": snappedf(best_f, 0.1), "peak_deg": snappedf(peak, 0.1), "peak_t": snappedf(peak_t, 0.01),
			"return_s": snappedf(ret, 0.01), "settle_s": snappedf(settle, 0.01), "overshoot_deg": snappedf(over, 0.1)}
	return out


## Запаздывание конечностей (FEEL_TARGET §9): невесомость, 2 с покоя. lag_thrust_x / lag_thrust_y — тяга (1,0) / (0,1) LAG_THRUST_S
## и отпустить (ноги отстают при разгоне вбок, руки — при разгоне вверх: сила инерции поперёк конечности); lag_flip — FLIP_IMPULSE
## торсу (как torso_kick, но в воздухе). По Shoulder_L/R, Hip_L/R: пик отклонения от позы (до отпускания + LAG_PEAK_EXTRA_S; у flip —
## LAG_FLIP_PEAK_S), t_return — от max(пик, отпускание) до первого входа в ±5°, перелёт — max отклонение в другую сторону после
## возврата / пик. Никакой анимации: только PD-пружины, трение, инерция.
func _tick_lag(m: Dictionary, id: String) -> void:
	doll.input_vec = Vector2.ZERO
	if t < LAG_SETTLE_S:
		return
	var flip := id == "lag_flip"
	var torso := doll.torso()
	if not S.has("t0"):
		S["t0"] = t
		var osc := {}
		for jn in LAG_JOINTS:
			osc[jn] = {"peak": 0.0, "sign": 0.0, "peak_t": 0.0, "ret": -1.0, "over": 0.0, "dev0": _pose_dev(jn)}
		S["osc"] = osc
		S["wmax"] = 0.0
		if id == "lag_dash":
			doll.dash_until = doll._time + Tuning.DASH_DURATION_S   # как Shift: тяга × DASH_MULT
		if flip:
			torso.apply_torque_impulse(Vector3(0, 0, Tuning.FLIP_IMPULSE))
			m["impulse_nms"] = Tuning.FLIP_IMPULSE
		return
	var since: float = t - float(S["t0"])
	var release := 0.0 if flip else LAG_THRUST_S
	if not flip and since < LAG_THRUST_S:
		doll.input_vec = Vector2(0.0, 1.0) if id == "lag_thrust_y" or id == "lag_dash" else Vector2(1.0, 0.0)   # lag_spin: rotate, ←→ = момент
	if not flip and since >= LAG_THRUST_S and not m.has("v_release"):
		m["v_release"] = snappedf(_com_velocity().length(), 0.01)
	S["wmax"] = maxf(float(S["wmax"]), absf(torso.angular_velocity.z))
	var peak_until := LAG_FLIP_PEAK_S if flip else LAG_THRUST_S + LAG_PEAK_EXTRA_S
	var osc: Dictionary = S["osc"]
	for jn in LAG_JOINTS:
		var o: Dictionary = osc[jn]
		var dev := _pose_dev(jn)
		if since <= peak_until and absf(dev) > float(o["peak"]):
			o["peak"] = absf(dev)
			o["sign"] = signf(dev)
			o["peak_t"] = since
			o["ret"] = -1.0
			o["over"] = 0.0
			continue
		var from := maxf(float(o["peak_t"]), release)
		if since < from:
			continue
		if float(o["ret"]) < 0.0:
			if absf(dev) < LAG_BAND_DEG:
				o["ret"] = since - from
		else:
			o["over"] = maxf(float(o["over"]), -float(o["sign"]) * dev)
	if since < release + LAG_AFTER_S:
		return
	var per := {}
	for jn in LAG_JOINTS:
		var o: Dictionary = osc[jn]
		var pk := float(o["peak"])
		per[jn] = {
			"peak_deg": snappedf(pk, 0.1), "peak_t": snappedf(float(o["peak_t"]), 0.01), "t_return_s": snappedf(float(o["ret"]), 0.01),
			"overshoot_deg": snappedf(float(o["over"]), 0.1), "overshoot_pct": snappedf(100.0 * float(o["over"]) / pk, 0.1) if pk > 1.0 else 0.0,
			"final_dev_deg": snappedf(_pose_dev(jn), 0.1),
		}
	m["joints"] = per
	m["torso_w_max_deg_s"] = snappedf(rad_to_deg(float(S["wmax"])), 0.1)
	m["part_speed_end"] = snappedf(doll.max_part_speed(), 0.01)
	# ведущая пара: при разгоне вбок отстают ноги, вверх — руки (Т-поза: сила инерции вдоль руки не качает её), при перевороте — обе
	var groups: Array = [["Hip_L", "Hip_R"]] if id == "lag_thrust_x" else ([["Shoulder_L", "Shoulder_R"]] if id == "lag_thrust_y" else [["Shoulder_L", "Shoulder_R"], ["Hip_L", "Hip_R"]])
	if id == "lag_dash":
		# v7: рывок (тяга × DASH_MULT 0.5 с вверх, как Shift): Т-руки поперёк разгона — плечо отстаёт сильнее обычной тяги (RM 30–60°+)
		groups = []
		var lead_d: String = "Shoulder_L" if float((per["Shoulder_L"] as Dictionary)["peak_deg"]) >= float((per["Shoulder_R"] as Dictionary)["peak_deg"]) else "Shoulder_R"
		var ed: Dictionary = per[lead_d]
		_target_range(id + "_Shoulder_lag_deg", float(ed["peak_deg"]), 40.0, 100.0, "dash 0.5 s: shoulder lags the torso >= 40° (%s, deg)" % lead_d)
		var rtd := float(ed["t_return_s"])
		_target_range(id + "_Shoulder_return_s", rtd if rtd >= 0.0 else 99.0, 0.1, 0.6, "limb catches up after the dash (%s, s; -1 = never)" % lead_d)
		var find := 0.0
		for jn in LAG_JOINTS:
			find = maxf(find, absf(float((per[jn] as Dictionary)["final_dev_deg"])))
		_target(id + "_limbs_back_deg", find, LAG_BAND_DEG + 3.0, "lt", "1.5 s after the dash the limbs are back in pose (max |dev| shoulder/hip, deg)")
	if id == "lag_flip" or id == "lag_spin":
		# вращение: торс 12 кг / I ≈ 0.4 кг·м² против четырёх конечностей по 4–8 кг — PD-суставы (Σ tmax ≈ 150 Н·м) гасят
		# относительное вращение за 2–3 тика; при 280 °/с лаг ≤ ~11° при любых k/ζ, 25–60° потребовали бы Σ момент суставов < 10 Н·м
		# (кукла не держит позу). Это метрики расхождения с RM, не цели (FEEL_TARGET §9).
		groups = []
		var lead_sh: Dictionary = per["Shoulder_L"] if float((per["Shoulder_L"] as Dictionary)["peak_deg"]) >= float((per["Shoulder_R"] as Dictionary)["peak_deg"]) else per["Shoulder_R"]
		var lead_hip: Dictionary = per["Hip_L"] if float((per["Hip_L"] as Dictionary)["peak_deg"]) >= float((per["Hip_R"] as Dictionary)["peak_deg"]) else per["Hip_R"]
		m["rm_gap"] = {"shoulder_lag_deg": lead_sh["peak_deg"], "hip_lag_deg": lead_hip["peak_deg"], "rm_lag_deg": [30, 60]}
		var fin := 0.0
		for jn in LAG_JOINTS:
			fin = maxf(fin, absf(float((per[jn] as Dictionary)["final_dev_deg"])))
		_target(id + "_limbs_back_deg", fin, LAG_BAND_DEG + 3.0, "lt", "after the spin the limbs are back in pose (max |dev| shoulder/hip at the end, deg)")
	for g in groups:
		var lead: String = g[0] if float((per[g[0]] as Dictionary)["peak_deg"]) >= float((per[g[1]] as Dictionary)["peak_deg"]) else g[1]
		var e: Dictionary = per[lead]
		var gname: String = String(lead).split("_")[0]
		var rt := float(e["t_return_s"])
		if gname == "Hip":
			# бедро: RM 30–60°, но k_hip держит стойку на полу (idle_floor ±5°, spring_foot_floor): k 60 → лаг 25°, стойка 8–11°,
			# нога на полу не возвращается; tmax < 38 — то же. Торс при разгоне сам кренится (ω 130 °/с), ноги отстают в мире,
			# а не в суставе. Цель — не регрессировать от v6 (FEEL_TARGET §9), расхождение с RM — в rm_gap.
			m["rm_gap"] = {"hip_lag_deg": e["peak_deg"], "rm_lag_deg": [30, 60], "hip_return_s": e["t_return_s"], "hip_overshoot_pct": e["overshoot_pct"]}
			_target_range(id + "_Hip_lag_deg", float(e["peak_deg"]), 25.0, 60.0, "v7 (RM 30–60°; v6.2 floor 15° was held by the ±5° stance): hip lags the torso (%s, deg)" % lead)
			_target_range(id + "_Hip_return_s", rt if rt >= 0.0 else 99.0, 0.12, 0.45, "v6 floor (RM ~0.3 s): hip catches up (%s, s; -1 = never)" % lead)
			_target_range(id + "_Hip_overshoot_pct", float(e["overshoot_pct"]), 12.0, 40.0, "v6 floor (RM 30–40 %%): visible catch-up overshoot (%s, %%)" % lead)
			continue
		_target_range(id + "_" + gname + "_lag_deg", float(e["peak_deg"]), 30.0, 60.0, "RM: limb lags the torso by 30–60° (%s, deg)" % lead)
		# RM ~0.3 с / перелёт 30–40 %. v6: 0.20 с / 23 %; v6.2 (торможение торса без ввода, ядро 2.25): 0.18 с / 31 % — критик круга 2
		# просил перелёт ≥ 28 %, поэтому нижняя граница перелёта 20 → 28 %, а возврата 0.19 → 0.17 с: остановившийся торс пускает руку
		# на тик раньше (11 тиков вместо 12). Четверть периода руки 0.77 с — 0.19 с: ~0.3 с RM дал бы только период ~1.2 с (k ≈ 15,
		# стоя рука проседает > 5°) или tmax 13–15 (рука с молотом провисает, combat_gate band_hammer) — FEEL_TARGET §9.2
		_target_range(id + "_" + gname + "_return_s", rt if rt >= 0.0 else 99.0, 0.17, 0.45, "RM ~0.3 s: limb catches up after release (%s, s; -1 = never)" % lead)
		_target_range(id + "_" + gname + "_overshoot_pct", float(e["overshoot_pct"]), 28.0, 40.0, "RM 30–40 %%: visible catch-up overshoot (%s, %%)" % lead)
	if flip:
		_target_range(id + "_torso_w_deg_s", rad_to_deg(float(S["wmax"])), 200.0, 360.0, "RM: flip/turn spins the torso at 200–360 °/s (deg/s)")
	elif id == "lag_spin" or id == "lag_dash":
		pass   # ROTATE_TORQUE (режим rotate, не по умолчанию): ω торса — метрика; у рывка v_release — метрика
	else:
		_target_range(id + "_v_release", float(m["v_release"]), 3.6, 5.4, "thrust 0.5 s in the air: 0 → 1.5–2.4 H/s (m/s)")
	_done(m, false)


## v7: рука с оружием жёстче пустой (Tuning.WEAPON_ARM_MUSCLES через WeaponPickup.attach → Doll.set_muscle_joint), сброс возвращает
## групповые. Кукла висит на HIT_H (g как в игре), молот 6 кг приваривается к Hand_L на 0.5 с; через 1.5 с — k/tmax суставов обеих рук
## и провис плеча с молотом против пустого; drop → через 0.1 с k снова групповые.
func _tick_weapon_arm(m: Dictionary) -> void:
	doll.input_vec = Vector2.ZERO
	if t >= 0.5 and not S.has("pickup"):
		var pickup: WeaponPickup = PickupScript.new()
		pickup.name = "WeaponPickup"
		pickup.auto_pickup = false
		doll.add_child(pickup)
		var grip := pickup.hand_grip_global("Hand_L")
		var w := Weapon.spawn("hammer", self, grip, 0.0)
		w.global_position += grip - w.grip_global()
		S["pickup"] = pickup
		S["weapon"] = w
		m["attached"] = pickup.attach("Hand_L", w)
		return
	if t >= 2.0 and not S.has("held_k"):
		var ks := {}
		for e in doll._muscle_pairs:
			ks[e[Doll.MP_NAME]] = [snappedf(float(e[Doll.MP_K]), 0.01), snappedf(float(e[Doll.MP_TMAX]), 0.01)]
		S["held_k"] = ks
		m["held_k_tmax"] = {"Shoulder_L": ks["Shoulder_L"], "Shoulder_R": ks["Shoulder_R"], "Elbow_L": ks["Elbow_L"]}
		m["held_sag_deg"] = {"Shoulder_L": snappedf(_pose_dev("Shoulder_L"), 0.1), "Shoulder_R": snappedf(_pose_dev("Shoulder_R"), 0.1)}
		var want: Dictionary = Tuning.WEAPON_ARM_MUSCLES["Shoulder"]
		var group: Dictionary = Tuning.MUSCLE_GROUPS["Shoulder"]
		var ok := absf(float(ks["Shoulder_L"][0]) - float(want["k"])) < 0.01 and absf(float(ks["Shoulder_L"][1]) - float(want["tmax"])) < 0.01 \
			and absf(float(ks["Shoulder_R"][0]) - float(group["k"])) < 0.01
		_check("weapon_arm_stiff", 1.0 if ok else 0.0, 0.5, "gt", "hammer in Hand_L: Shoulder_L k/tmax = WEAPON_ARM_MUSCLES, Shoulder_R keeps the group k (1 = yes)")
		(S["pickup"] as WeaponPickup).drop("Hand_L")
		return
	if t < 2.2:
		return
	var back := true
	for e in doll._muscle_pairs:
		var G: Dictionary = Tuning.MUSCLE_GROUPS[e[Doll.MP_GROUP]]
		if absf(float(e[Doll.MP_K]) - float(G["k"])) > 0.01 or absf(float(e[Doll.MP_TMAX]) - float(G["tmax"])) > 0.01:
			back = false
	m["dropped_group_k"] = back
	_check("weapon_arm_drop", 1.0 if back else 0.0, 0.5, "gt", "after drop all joints are back to Tuning.MUSCLE_GROUPS k/tmax (1 = yes)")
	var w: Weapon = S["weapon"]
	if is_instance_valid(w):
		w.queue_free()
	_done(m, false)


func _finish() -> void:
	var wall_ms := (Time.get_ticks_usec() - wall_start_usec) / 1000.0
	var info: Dictionary = report["info"]
	info["scenarios"] = scenarios
	info["sim_total_s"] = snappedf(sim_total_s, 0.01)
	info["ticks"] = total_ticks
	info["wall_ms_total"] = snappedf(wall_ms, 1.0)
	info["wall_ms_per_tick_avg"] = snappedf(wall_ms / maxf(total_ticks, 1), 0.001)
	info["gravity"] = g_eff
	info["gravity_scale_parts"] = snappedf(g_scale, 0.001)
	if doll == null:
		_spawn(Vector3(0, HOVER_H, 0), true)   # only= не выбрал ни одного сценария: кукла нужна ради info
	var muscles := {}
	var friction := {}
	var deadband := {}
	var rest := {}
	for e in doll._muscle_pairs:
		var jn: String = e[Doll.MP_NAME]
		var k: float = float(e[Doll.MP_K])
		muscles[jn] = {"k": snappedf(k, 0.01), "c": snappedf(float(e[Doll.MP_C]), 0.001), "tmax": snappedf(float(e[Doll.MP_TMAX]), 0.01)}
		rest[jn] = snappedf(rad_to_deg(float(e[Doll.MP_REST])), 0.01)
		var j: Generic6DOFJoint3D = doll.joints[jn]
		var f := float(j.get("angular_motor_z/force_limit")) if bool(j.get("angular_motor_z/enabled")) else 0.0
		friction[jn] = snappedf(f, 0.01)
		# статический dead band PD против трения: |k·ang| ≤ f → мышца не двигает сустав; клэмп tmax тоже режет
		deadband[jn] = snappedf(rad_to_deg(f / k), 0.01) if k > 0.0 else -1.0
	info["muscles"] = muscles
	info["joint_friction_nm"] = friction
	info["pd_deadband_deg"] = deadband
	info["muscle_rest_deg"] = rest
	info["tuning"] = {
		"GRAVITY": Tuning.GRAVITY, "LINEAR_DAMP": Tuning.LINEAR_DAMP, "DOLL_LINEAR_DAMP": Tuning.DOLL_LINEAR_DAMP, "ANGULAR_DAMP": Tuning.ANGULAR_DAMP,
		"MOVE_FORCE_PER_KG": Tuning.MOVE_FORCE_PER_KG, "MAX_MOVE_SPEED": Tuning.MAX_MOVE_SPEED, "FLIP_IMPULSE": Tuning.FLIP_IMPULSE,
		"MUSCLE_ZETA": Tuning.MUSCLE_ZETA, "POSE": Tuning.POSE, "JOINT_FRICTION": Tuning.JOINT_FRICTION, "total_mass": doll.total_mass,
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
	}
	info["cfg"] = cfg
	info["group_k"] = group_k
	info["group_t"] = group_t
	info["strict"] = strict
	info["godot"] = Engine.get_version_info()["string"]
	info["physics_engine"] = ProjectSettings.get_setting("physics/3d/physics_engine")
	var js := JSON.stringify(report, "  ")
	print("=== FEEL PROBE ===")
	print(js)
	var f := FileAccess.open(report_path, FileAccess.WRITE)
	if f:
		f.store_string(js)
		f.close()
	print("=== %s ===" % ("OK" if report["ok"] else "FAIL"))
	get_tree().quit(0 if report["ok"] else 1)
