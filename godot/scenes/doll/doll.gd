## Рэгдолл на настоящих суставах (Jolt, Generic6DOFJoint3D), 3D на плоскости XY.
## Кукла СМОТРИТ В КАМЕРУ (+Z): плечи и бёдра разнесены по X, руки висят по бокам,
## лицо игрока всегда видно. Движение по X (влево/вправо) и Y (вверх/вниз), Z заблокирована.
## 14 частей (как в CONCEPT.md §4): голова, торс, плечо/предплечье/кисть ×2, бедро/голень/стопа ×2.
## Управление: сила на центр тела (торс), конечности отстают по инерции (CONCEPT.md §3–4).
## Мышцы: явный PD каждого сустава к позе покоя Tuning.POSE (Т-поза Ragdoll Masters: руки ⟂ торсу, ноги слегка врозь),
## жёсткость/клэмп по группам Tuning.MUSCLE_GROUPS, демпфирование c = 2·ζ·√(k·I), ζ группы — MUSCLE_GROUPS[g].zeta или MUSCLE_ZETA
## (docs/plan-demo/FEEL_TARGET.md; §9 v6 — запаздывание конечностей и полёт после удара).
## Позы на лету: set_pose() / reset_pose() / get_pose(); прокачка групп: set_muscle_group(); один сустав — set_muscle_joint() /
## clear_muscle_joint() (v7: рука с оружием, WeaponPickup). v7 (FEEL_TARGET §9.4): спавн сразу в позе (spawn_in_pose), на удар
## расслабляются мышцы И трение групп Tuning.HIT_MUSCLE_SOFT_GROUPS (колено — нет).
##
## Дерево узлов (тела, формы, меши, суставы) живёт в scenes/doll/doll.tscn (светлый клён) и
## scenes/doll/doll_dark.tscn (тёмный орех) — обе генерирует tools/build_doll_scene.gd (ASSET_PIPELINE.md, правило 2)
## с этим скриптом. Здесь — только поведение: в _ready() части (RigidBody3D) и суставы (Generic6DOFJoint3D)
## находятся по дереву. Цвет игрока = все материалы с именем, начинающимся на "Shirt" (обмотки Shirt, мазки Shirt_Paint).
##
## Бой (план 06, scripts/core/): hp / stats / take_damage() / knock_out() → break_apart() (суставы рвутся, части летят — В3) /
## stun() (мышцы 0, трение STUN_JOINT_FRICTION, возврат за STUN_RECOVER_S) / apply_knockback() (KNOCKBACK_FREE_S вместо клэмпа
## MAX_MOVE_SPEED торса — клэмп ЦМ FLIGHT_MAX_SPEED, дамп частей FLIGHT_LINEAR_DAMP до land()) / set_stability() (Sudden Death ×(1−0.15n)).
## v6.2 (FEEL_TARGET §9.2): apply_knockback гасит подлёт жертвы и добирает KNOCKBACK_MIN в торс, soften_muscles() — мышцы жертвы
## × HIT_MUSCLE_SOFT на удар; apply_recoil() — отдача атакующего (DollCombat) и thrust_lock_until; дамп ядра (голова, торс) и
## конечностей раздельно (_apply_base_damp, Tuning.DOLL_LINEAR_DAMP / DOLL_LIMB_*), торможение без ввода IDLE_BRAKE_DAMP.
## Урон считает DollCombat (ребёнок), фазы — Match. Сломанная кукла не восстанавливается: Match.respawn_doll() инстанцирует сцену заново.
class_name Doll
extends Node3D

## Удар получен: amount HP, attacker (Doll | null = окружение/self), part — имя ударенной части, kind ∈ head|body|weapon|environment|self.
signal damaged(amount: float, attacker: Node, part: String, position: Vector3, kind: String)
## HP кончилось (или knock_out() извне): record — KoRecord {victim, attacker, part, kind, damage, speed, weapon_id, position, time, ...}.
signal knocked_out(attacker: Node, record: Dictionary)
signal stunned(seconds: float)
## Часть оторвана detach_part (PvE: Разборщик, пресс, Садовник): part_name — имя оторванного тела, by — кто оторвал (или null).
signal part_detached(part_name: String, by: Node)
## Оторванная часть прикручена обратно reattach_part.
signal part_reattached(part_name: String)

enum StunPhase { NONE, STUNNED, RECOVER }

@export var player_index := 0
@export var input_prefix := "p1"
@export var control_enabled := true
## Внешний ввод (боты, тесты): если true, читается input_vec вместо InputMap.
@export var external_input := false
@export var input_vec := Vector2.ZERO  # x: вправо (+X), y: вверх
## «Мышцы»: PD-контроллер на торках к позе покоя (0 = только трение). -1 = по группам из Tuning.MUSCLE_GROUPS;
## ≥ 0 = единое значение для ВСЕХ суставов (uniform override: тесты, гейты, отладка).
@export var muscle_stiffness := -1.0   # Н·м/рад
@export var muscle_damping := -1.0     # Н·м·с/рад; -1 = 2·ζ·√(k·I) по группе
@export var muscle_max_torque := -1.0  # Н·м, клэмп
@export var muscle_zeta := -1.0        # ≥ 0: единое ζ всех групп; -1 = Tuning.MUSCLE_GROUPS[g].zeta (иначе Tuning.MUSCLE_ZETA)
## Трение шарнира деревянной куклы: мотор с нулевой целевой скоростью, force_limit = Н·м. -1 = как в сцене
## (Tuning.JOINT_FRICTION × per-joint meta "friction_factor" из builder-а).
@export var joint_friction := -1.0
@export var self_collision := false
## v7: при спавне конечности сразу ставятся в позу Tuning.POSE (SPAWN_POSE_GROUPS): doll.tscn собран «палкой» (руки вниз, ноги
## сведены), а мягкое бедро (MUSCLE_GROUPS Hip k 50) не разводит стопы, стоящие на полу (трение 0.9 × 40 Н × 0.9 м ≈ 32 Н·м > k·12°) —
## кукла стояла бы «солдатиком»; мягкое плечо поднимает руки 0.8 с, и оружие, подобранное в эти 0.8 с, смотрит не туда
## (combat_gate band_hammer: хват считается от кисти в момент подбора). false — старый спавн палкой (feel_probe pose_air, limit).
@export var spawn_in_pose := true
const SPAWN_POSE_GROUPS := ["Shoulder", "Elbow", "Hip", "Knee"]   # проксимальные раньше дистальных
## Внешняя модель (см. docs/plan-demo/MODEL_IMPORT.md). Пусто = меши манекена из сцены.
@export var skin_scene := ""
@export var skin_mode := "parts"       # parts | skeleton
@export var skin_bone_map := ""        # "Head=head,Torso=spine,..." для skeleton
## Режим управления: "thrust4" (сила по 4 направлениям) или "rotate" (←→ момент, ↑↓ тяга).
@export var control_mode := ""         # пусто = Tuning.CONTROL_MODE
## Куда прикладывать тягу: "torso" (центр тела, концепт) или "head" (порт Ragdoll Masters).
@export var control_target := ""       # пусто = Tuning.CONTROL_TARGET
## Команда (PvE-волны): урон от куклы той же непустой команды × Tuning.TEAM_DAMAGE_MULT (take_damage); толчки полные.
@export var team := ""
## Запас HP этой куклы (PvE-враги 40 / 80); hp в _ready и reset_for_match = max_hp; Match.hp_changed и HUD берут его отсюда.
@export var max_hp: float = Tuning.MAX_HP

## Подбор дампа без правки Tuning (tests/feel_probe: ldc/ldl/adl/fdc/fdl/brake): ключи "core", "limb", "limb_ang", "flight_core",
## "flight_limb", "brake", "core_ang" перекрывают Tuning.DOLL_LINEAR_DAMP / DOLL_LIMB_LINEAR_DAMP / DOLL_LIMB_ANGULAR_DAMP / FLIGHT_LINEAR_DAMP /
## FLIGHT_LIMB_LINEAR_DAMP / IDLE_BRAKE_DAMP. Задавать до add_child. Пусто — как в Tuning (игра).
var damp_override: Dictionary = {}
## То же для ослабления мышц на удар (tests/feel_probe: hms/hmh/hmr): ключи "mult", "hold", "recover" перекрывают Tuning.HIT_MUSCLE_SOFT /
## HIT_MUSCLE_SOFT_S / HIT_MUSCLE_RECOVER_S. Пусто — как в Tuning (игра).
var soft_override: Dictionary = {}

var parts: Dictionary = {}    # name -> RigidBody3D
var joints: Dictionary = {}   # name -> Generic6DOFJoint3D
## Пара мышцы на сустав: [body_a, body_b, rest (рад, measured), k, c, tmax, group, joint_name]. k/c/tmax — база (без стана/SD).
var _muscle_pairs: Array = []
var _req_dash := false   # request_dash(): рывок на ближайшем тике управления (боты, external_input)
var _req_flip := false   # request_flip(): переворот на ближайшем тике управления
const MP_REST := 2
const MP_K := 3
const MP_C := 4
const MP_TMAX := 5
const MP_GROUP := 6
const MP_NAME := 7
## Допуск |I_цепи / I_группы − 1|, в котором демпфирование мышцы берётся по инерции группы (см. _pair_inertia).
const CHAIN_INERTIA_TOLERANCE := 0.15
var _muscle_mult := 1.0       # stability_mult × стан-рампа (0 в стане, 0 после break_apart)
var _k := 0.0                 # справочно (отчёты гейтов): эффективная k группы Shoulder = база × _muscle_mult
var _c := 0.0
var _tmax := 0.0
var _group_k: Dictionary = {}     # группа -> k (база), из Tuning.MUSCLE_GROUPS или override
var _group_tmax: Dictionary = {}
var _group_zeta: Dictionary = {}  # группа -> ζ (Tuning.MUSCLE_GROUPS[g].zeta, иначе MUSCLE_ZETA; muscle_zeta ≥ 0 — единое)
## v7: override одного сустава поверх группы (рука с оружием — WeaponPickup): имя сустава -> {"k", "tmax", "zeta"}; инерция — группы.
var _joint_override: Dictionary = {}
var _uniform_c := -1.0            # ≥ 0: единое c (muscle_damping / set_muscles)
var _zeta := 0.2
var _pose_blend: Dictionary = {}  # joint_name -> [rest_from, rest_to, t0, dur]
var _friction_base: Dictionary = {}   # joint -> Н·м из сцены (или joint_friction × friction_factor)
var _friction_uniform := -1.0         # set_muscles(..., friction) перекрывает per-joint базу
var alive := true
var stunned_until := 0.0
var _stun_phase := StunPhase.NONE
var _stun_recover_t0 := 0.0
var total_mass := 0.0
## Точка сустава в локальных координатах тела-родителя (node_a), снятая в _ready до спавна в позе: узел сустава после поворота
## родителя остаётся на месте сборки, а якорь Jolt едет вместе с родителем (_snap_to_pose поворачивает вокруг якоря).
var _joint_local_a: Dictionary = {}
## Кадр сустава в системе родителя / ребёнка на момент _ready (сборка): reattach_part совмещает их, как было при сборке.
var _joint_xf_a: Dictionary = {}
var _joint_xf_b: Dictionary = {}
## Оторванные корни (RigidBody3D) -> запись для reattach_part: сустав подвеса (отключён, остаётся ребёнком куклы), родитель,
## поддерево, внутренние суставы с трением, снятые пары мышц, тела под монитором DollCombat.
var _detached: Dictionary = {}
var dash_until := 0.0
var dash_ready_at := 0.0
var _time := 0.0

# --- бой (06) ---
var hp: float = Tuning.MAX_HP
var stats: Dictionary = fresh_stats()
## До этого момента (_time) урон не принимается: spawn grace после спавна и после reset_for_match().
var grace_until: float = Tuning.SPAWN_GRACE_S
## После удара до этого момента клэмп MAX_MOVE_SPEED не действует (полёт); читает DynamicCamera для упреждения.
var knockback_until := 0.0
## Крит-полёт (HIT_FX.md §2.3, CritLaunch): свой клэмп ЦМ вместо Tuning.FLIGHT_MAX_SPEED до _flight_cap_until (_time).
var _flight_cap := 0.0
var _flight_cap_until := -1.0
## Множитель Sudden Death к мышцам и трению (Match.set_stability).
var stability_mult := 1.0
## DollCombat кладёт сюда {speed, weapon_id, striker, ...} перед take_damage — попадает в damaged/KoRecord.
var hit_meta: Dictionary = {}
var last_hit: Dictionary = {}
var last_ko_record: Dictionary = {}
var _broken := false
var _self_exceptions := false
var _flight_damp := false
var _flight_damp_until := 0.0
var _brake_on := false                ## торс с +Tuning.IDLE_BRAKE_DAMP (ввод 0, не в полёте)
## Ослабление мышц на удар (Tuning.HIT_MUSCLE_SOFT): множитель k/tmax держится до _soft_hold_until, затем линейно к 1 за _soft_recover_s.
var _soft_mult := 1.0
var _soft_hold_until := -1.0
var _soft_recover_s := 0.0
var _soft_applied := 1.0              ## множитель ослабления, уже применённый к трению шарниров (_refresh_friction)
## Отдача атакующего (DollCombat._deliver → apply_recoil): до этого момента тяга выключена.
var thrust_lock_until := 0.0
const FLIGHT_DAMP_MAX_S := 4.0        # страховка: дамп полёта возвращается и без land()
const LOW_HP := 10.0                  # stats.low_hp_survived_s (Survivor)

## Размеры рига (метры) — справочно и для DollSkin.auto_scale; сами тела заданы в doll.tscn / doll_dark.tscn (builder).
## Художественный манекен v3 (ART_DIRECTION.md «v3», R22): рост 1.80, голова-яйцо 0.24×0.30, плечи x=±0.22, бёдра x=±0.10.
const D := {
	"head_r": 0.15, "head_w": 0.24, "torso_h": 0.52, "torso_w": 0.36, "torso_d": 0.22,
	"ua": 0.30, "la": 0.27, "hand": 0.18, "hand_w": 0.07, "hand_d": 0.07,
	"ul": 0.42, "ll": 0.40, "foot": 0.25, "foot_h": 0.08, "foot_w": 0.10,
	"ua_r": 0.052, "la_r": 0.044, "ul_r": 0.070, "ll_r": 0.056, "neck": 0.04, "shoulder_x": 0.22, "hip_x": 0.10,
}

const HIP_Y := 0.91                         # бёдра; колени 0.49, лодыжки 0.09
const SHOULDER_Y := 1.43                    # плечи; шея 1.47, центр головы 1.625, макушка 1.775
const SHIRT_MATERIAL := "Shirt"             # префикс имени материалов в GLB, перекрашиваемых в цвет игрока (Shirt, Shirt_Paint)


func _ready() -> void:
	hp = max_hp
	_zeta = muscle_zeta if muscle_zeta >= 0.0 else Tuning.MUSCLE_ZETA
	_uniform_c = muscle_damping
	for g in Tuning.MUSCLE_GROUPS:
		var G: Dictionary = Tuning.MUSCLE_GROUPS[g]
		_group_k[g] = muscle_stiffness if muscle_stiffness >= 0.0 else float(G["k"])
		_group_tmax[g] = muscle_max_torque if muscle_max_torque >= 0.0 else float(G["tmax"])
		_group_zeta[g] = muscle_zeta if muscle_zeta >= 0.0 else float(G.get("zeta", Tuning.MUSCLE_ZETA))

	# части и суставы — из дерева сцены
	for c in get_children():
		if c is RigidBody3D:
			parts[c.name] = c
		elif c is Generic6DOFJoint3D:
			joints[c.name] = c
	for j in joints.values():
		var a := j.get_node_or_null(j.node_a) as RigidBody3D
		var b := j.get_node_or_null(j.node_b) as RigidBody3D
		if a == null or b == null:
			push_error("Doll: joint %s has no bodies (%s / %s)" % [j.name, j.node_a, j.node_b])
			continue
		_joint_local_a[String(j.name)] = a.to_local(j.global_position)
		_joint_xf_a[String(j.name)] = a.global_transform.affine_inverse() * j.global_transform
		_joint_xf_b[String(j.name)] = b.global_transform.affine_inverse() * j.global_transform
		var group: String = String(j.name).split("_")[0]
		if not Tuning.MUSCLE_GROUPS.has(group):
			push_error("Doll: joint %s has no muscle group %s in Tuning.MUSCLE_GROUPS" % [j.name, group])
			continue
		_muscle_pairs.append([a, b, _pose_rest_rad(String(j.name), float(Tuning.POSE.get(group, 0.0)), true), 0.0, 0.0, 0.0, group, String(j.name)])
		if joint_friction >= 0.0:
			var f: float = joint_friction * float(j.get_meta("friction_factor", 1.0))
			j.set("angular_motor_z/enabled", f > 0.0)
			j.set("angular_motor_z/target_velocity", 0.0)
			j.set("angular_motor_z/force_limit", f)
		var enabled: bool = j.get("angular_motor_z/enabled")
		_friction_base[j] = float(j.get("angular_motor_z/force_limit")) if enabled else 0.0

	if spawn_in_pose:
		_snap_to_pose(SPAWN_POSE_GROUPS)
	_update_pair_gains()
	_refresh_muscles()

	if not self_collision:
		_self_exceptions = true
		var list: Array = parts.values()
		for i in range(list.size()):
			for j in range(i + 1, list.size()):
				list[i].add_collision_exception_with(list[j])

	total_mass = 0.0
	for b in parts.values():
		total_mass += b.mass
	_apply_base_damp(false)

	# SDFGI (assets/environments/*_env.tres): движущиеся части не должны запекаться в статичный GI (иначе «шлейфы» за куклой)
	for m in _find_meshes(self):
		(m as GeometryInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC

	_recolor(self, SHIRT_MATERIAL, Tuning.PLAYER_COLORS[clampi(player_index, 0, 3)])  # self: обмотки, ремень и мазки краски на всех частях

	if skin_scene != "":
		var skin := DollSkin.new()
		add_child(skin)
		if skin.apply(self, skin_scene, skin_mode, skin_bone_map):
			_set_rig_visible(false)


## Ставит суставы групп groups (по порядку: проксимальные раньше) в позу покоя до первого шага физики: дистальная цепь сустава
## поворачивается вокруг его оси (точка сустава на оси — якоря Jolt совпадают, лимиты считаются от собранной сцены, как раньше).
## Центр поворота — точка сустава на ТЕКУЩЕМ родителе (_joint_local_a), а не узел сустава: после поворота плеча узел локтя остаётся
## на месте сборки, и поворот вокруг него отрывал предплечье от плеча на 5–7 см (Jolt стягивал сустав рывком на первых шагах;
## tests/body_probe doll_spawn_joint_gap_m).
func _snap_to_pose(groups: Array) -> void:
	for g in groups:
		for e in _muscle_pairs:
			if e[MP_GROUP] != g:
				continue
			var a: RigidBody3D = e[0]
			var b: RigidBody3D = e[1]
			var cur := wrapf(b.global_rotation.z - a.global_rotation.z, -PI, PI)
			var delta := wrapf(float(e[MP_REST]) - cur, -PI, PI)
			if absf(delta) < 1e-4:
				continue
			var pivot: Vector3 = joint_pivot_global(String(e[MP_NAME]))
			var rot := Basis(Vector3(0, 0, 1), delta)
			for body in _distal_bodies(b):
				var rb := body as RigidBody3D
				var tr := rb.global_transform
				rb.global_transform = Transform3D(rot * tr.basis, pivot + rot * (tr.origin - pivot))


## Точка сустава в мире сейчас: якорь на теле-родителе (node_a), как его держит Jolt. Узел сустава для этого не годится — он остаётся
## на месте сборки, когда родитель повернулся (спавн в позе, _snap тестов). Для сустава без записи — позиция узла.
func joint_pivot_global(joint_name: String) -> Vector3:
	var j := joints.get(joint_name) as Generic6DOFJoint3D
	if j == null:
		return Vector3.ZERO
	var a := j.get_node_or_null(j.node_a) as RigidBody3D
	if a == null or not _joint_local_a.has(joint_name):
		return j.global_position
	return a.global_transform * (_joint_local_a[joint_name] as Vector3)


## Тело b и все тела ниже него по цепочке суставов (плечо → предплечье → кисть).
func _distal_bodies(b: RigidBody3D) -> Array:
	var out: Array = [b]
	var i := 0
	while i < out.size():
		for e in _muscle_pairs:
			if e[0] == out[i] and not out.has(e[1]):
				out.append(e[1])
		i += 1
	return out


## Перекрашивает поверхности с материалом, имя которого начинается на material_name, под телом body
## (override, общий ресурс не трогаем; alpha материала сохраняется — мазки краски остаются полупрозрачными).
func _recolor(body: Node, material_name: String, colour: Color) -> void:
	if body == null:
		return
	for m in _find_meshes(body):
		var mi: MeshInstance3D = m
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var mat: Material = mi.get_active_material(s)
			if mat == null or not mat.resource_name.begins_with(material_name):
				continue
			var dup: Material = mat.duplicate()
			if dup is BaseMaterial3D:
				var c := colour
				c.a = dup.albedo_color.a
				dup.albedo_color = c
			mi.set_surface_override_material(s, dup)


func _find_meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out += _find_meshes(c)
	return out


## Меши манекена из сцены (meta rig_mesh) — прячутся, когда надет внешний скин.
func _set_rig_visible(v: bool) -> void:
	for body in parts.values():
		for c in body.get_children():
			if c is Node3D and c.get_meta("rig_mesh", false):
				c.visible = v


## Uniform override мышц: stiff ≥ 0 — единая k всех суставов (< 0 — вернуть группы из Tuning.MUSCLE_GROUPS),
## damp ≥ 0 — единое c (< 0 — c = 2·ζ·√(k·I) по группе), friction ≥ 0 — единое трение всех шарниров (Н·м).
## Эффективные значения = база × stability_mult × стан-рампа (см. _refresh_muscles).
func set_muscles(stiff: float, damp: float, friction: float = -1.0) -> void:
	for g in Tuning.MUSCLE_GROUPS:
		var G: Dictionary = Tuning.MUSCLE_GROUPS[g]
		_group_k[g] = stiff if stiff >= 0.0 else float(G["k"])
	_uniform_c = damp
	if friction >= 0.0:
		_friction_uniform = friction
	_update_pair_gains()
	_refresh_muscles()


## Прокачка группы мышц (апгрейды «сильные ноги»): group — ключ Tuning.MUSCLE_GROUPS ("Shoulder", "Hip", ...),
## k Н·м/рад, tmax Н·м, zeta (< 0 — не менять). c пересчитывается из ζ и инерции группы.
func set_muscle_group(group: String, k: float, tmax: float = -1.0, zeta: float = -1.0) -> void:
	if not Tuning.MUSCLE_GROUPS.has(group):
		push_warning("Doll.set_muscle_group: unknown group %s" % group)
		return
	_group_k[group] = maxf(k, 0.0)
	if tmax >= 0.0:
		_group_tmax[group] = tmax
	if zeta >= 0.0:
		_group_zeta[group] = zeta
	_update_pair_gains()
	_refresh_muscles()


## v7: жёсткость ОДНОГО сустава поверх группы (set_muscle_group меняет обе стороны): рука с оружием держит его
## (WeaponPickup.attach → Tuning.WEAPON_ARM_MUSCLES), а пустая рука остаётся мягкой. k Н·м/рад, tmax/zeta < 0 — как у группы.
## Стан, Sudden Death и ослабление на удар умножают и эти значения (они — база пары, как у группы).
func set_muscle_joint(joint_name: String, k: float, tmax: float = -1.0, zeta: float = -1.0) -> void:
	if not joints.has(joint_name):
		return   # сломанная кукла (break_apart) или неизвестный сустав
	_joint_override[joint_name] = {"k": maxf(k, 0.0), "tmax": tmax, "zeta": zeta}
	_update_pair_gains()
	_refresh_muscles()


## Снять override сустава: вернуть групповые k/tmax/ζ (сброс оружия, KO).
func clear_muscle_joint(joint_name: String) -> void:
	if not _joint_override.has(joint_name):
		return
	_joint_override.erase(joint_name)
	_update_pair_gains()
	_refresh_muscles()


func has_muscle_joint_override(joint_name: String) -> bool:
	return _joint_override.has(joint_name)


## k/c/tmax каждой пары из групп (или uniform override), поверх — override сустава. c = 2·ζ·√(k·I_группы), если не задано единое c.
func _update_pair_gains() -> void:
	for e in _muscle_pairs:
		var g: String = e[MP_GROUP]
		var k: float = float(_group_k.get(g, 0.0))
		var tmax: float = float(_group_tmax.get(g, 0.0))
		var zeta: float = float(_group_zeta.get(g, _zeta))
		var ov: Dictionary = _joint_override.get(String(e[MP_NAME]), {})
		if not ov.is_empty():
			k = float(ov["k"])
			if float(ov["tmax"]) >= 0.0:
				tmax = float(ov["tmax"])
			if float(ov["zeta"]) >= 0.0:
				zeta = float(ov["zeta"])
		var inertia: float = _pair_inertia(String(e[MP_NAME]), float((Tuning.MUSCLE_GROUPS[g] as Dictionary)["inertia"]))
		e[MP_K] = k
		e[MP_C] = _uniform_c if _uniform_c >= 0.0 else 2.0 * zeta * sqrt(maxf(k, 0.0) * inertia)
		e[MP_TMAX] = tmax


## Инерция цепи для демпфирования c = 2ζ√(k·I): инерция группы из Tuning.MUSCLE_GROUPS (цепь куклы v3), а если сустав несёт
## meta "chain_inertia" (ModularDoll: настоящая дистальная цепь сборки) и она отличается от группы больше CHAIN_INERTIA_TOLERANCE — она.
## В допуске остаётся групповая (human-сборка даёт числа doll.tscn; у кисти прямо на локте или ноги на плече I в 0.05–4 раза другая —
## с групповой явный PD дрожит или болтается).
func _pair_inertia(joint_name: String, group_inertia: float) -> float:
	var j := joints.get(joint_name) as Node
	if j == null or group_inertia <= 0.0:
		return group_inertia
	var ci := float(j.get_meta("chain_inertia", 0.0))
	if ci > 0.0 and absf(ci / group_inertia - 1.0) > CHAIN_INERTIA_TOLERANCE:
		return ci
	return group_inertia


## Угол покоя сустава (рад, measured). deg — градусы; mirror=true — deg задан для ЛЕВОЙ стороны и у *_R меняет знак.
static func _pose_rest_rad(joint_name: String, deg: float, mirror: bool) -> float:
	var sgn := -1.0 if mirror and joint_name.ends_with("_R") else 1.0
	return deg_to_rad(deg * sgn)


## Новая поза покоя. Ключи — группа из Tuning.POSE ("Shoulder": градусы ЛЕВОЙ стороны, у *_R знак меняется сам)
## или имя сустава ("Shoulder_R": measured-градусы как есть, наружу у R = −). Не упомянутые суставы не меняются.
## blend_s > 0 — линейный переход за blend_s секунд (без рывка PD).
func set_pose(pose: Dictionary, blend_s: float = 0.0) -> void:
	for e in _muscle_pairs:
		var jn: String = e[MP_NAME]
		var target: float
		if pose.has(jn):
			target = _pose_rest_rad(jn, float(pose[jn]), false)
		elif pose.has(e[MP_GROUP]):
			target = _pose_rest_rad(jn, float(pose[e[MP_GROUP]]), true)
		else:
			continue
		if blend_s > 0.0:
			_pose_blend[jn] = [float(e[MP_REST]), target, _time, blend_s]
		else:
			_pose_blend.erase(jn)
			e[MP_REST] = target


## Вернуть позу покоя из Tuning.POSE.
func reset_pose(blend_s: float = 0.0) -> void:
	set_pose(Tuning.POSE, blend_s)


## Текущая поза покоя: имя сустава -> measured-градусы (цель после blend, если он идёт).
func get_pose() -> Dictionary:
	var out := {}
	for e in _muscle_pairs:
		var jn: String = e[MP_NAME]
		var r: float = float((_pose_blend[jn] as Array)[1]) if _pose_blend.has(jn) else float(e[MP_REST])
		out[jn] = rad_to_deg(r)
	return out


func _tick_pose_blend() -> void:
	if _pose_blend.is_empty():
		return
	for e in _muscle_pairs:
		var jn: String = e[MP_NAME]
		if not _pose_blend.has(jn):
			continue
		var bl: Array = _pose_blend[jn]
		var u := clampf((_time - float(bl[2])) / maxf(float(bl[3]), 0.001), 0.0, 1.0)
		e[MP_REST] = lerpf(float(bl[0]), float(bl[1]), u)
		if u >= 1.0:
			_pose_blend.erase(jn)


## Sudden Death: мышцы и трение × mult (Match.sd step). 1.0 — обычный бой.
func set_stability(mult: float) -> void:
	stability_mult = maxf(mult, 0.0)
	_refresh_muscles()


## 0 в стане, 0→1 за STUN_RECOVER_S после, иначе 1.
func _stun_ramp() -> float:
	match _stun_phase:
		StunPhase.STUNNED:
			return 0.0
		StunPhase.RECOVER:
			return clampf((_time - _stun_recover_t0) / maxf(Tuning.STUN_RECOVER_S, 0.001), 0.0, 1.0)
	return 1.0


func _refresh_muscles() -> void:
	if _broken:
		_muscle_mult = 0.0
		_k = 0.0
		_c = 0.0
		return
	var ramp := _stun_ramp()
	# в стане k → Tuning.STUN_MUSCLE_STIFFNESS (0: пассивный рэгдолл), c → 0; SD — × stability_mult
	_muscle_mult = lerpf(0.0, stability_mult, ramp)
	var ks: float = float(_group_k.get("Shoulder", 0.0))
	_k = lerpf(Tuning.STUN_MUSCLE_STIFFNESS, ks * stability_mult, ramp)
	_c = _uniform_c * _muscle_mult if _uniform_c >= 0.0 else 2.0 * float(_group_zeta.get("Shoulder", _zeta)) * sqrt(maxf(ks, 0.0) * float((Tuning.MUSCLE_GROUPS["Shoulder"] as Dictionary)["inertia"])) * _muscle_mult
	_tmax = float(_group_tmax.get("Shoulder", 0.0))
	_refresh_friction(ramp)


## Трение шарниров: база (сцена / set_muscles) × stability_mult, в стане → STUN_JOINT_FRICTION; на удар × ослабление (v7:
## Tuning.HIT_FRICTION_SOFT — расслабленный сустав не держит сложенную конечность трением, см. soften_muscles).
func _refresh_friction(ramp: float) -> void:
	var soft := _soft_applied if _hit_friction_soft() else 1.0
	var soft_groups := _soft_groups()
	for j in joints.values():
		var base: float = _friction_uniform if _friction_uniform >= 0.0 else float(_friction_base.get(j, 0.0))
		var sf := soft if soft_groups.is_empty() or soft_groups.has(String(j.name).split("_")[0]) else 1.0
		var f := lerpf(Tuning.STUN_JOINT_FRICTION, base * stability_mult, ramp) * sf
		j.set("angular_motor_z/enabled", f > 0.0)
		j.set("angular_motor_z/target_velocity", 0.0)
		j.set("angular_motor_z/force_limit", f)


## Группы суставов, которые слабеют на удар (Tuning.HIT_MUSCLE_SOFT_GROUPS; пусто — все).
func _soft_groups() -> Array:
	return soft_override.get("groups", Tuning.HIT_MUSCLE_SOFT_GROUPS)


func _hit_friction_soft() -> bool:
	return float(soft_override.get("friction", 1.0 if Tuning.HIT_FRICTION_SOFT else 0.0)) > 0.5


## Начальная статистика бойца (CONCEPT.md §19; ключи читает scenes/ui/results_panel.gd).
static func fresh_stats() -> Dictionary:
	return {
		"damage_dealt": 0.0, "damage_taken": 0.0, "hardest_hit": 0.0, "kos": 0, "kos_taken": 0,
		"air_time": 0.0, "wall_collisions": 0, "collisions": 0, "weapon_hits": 0, "rotations": 0,
		"max_speed": 0.0, "flight_distance": 0.0, "combo_max": 0, "combo_score": 0.0,
		"self_damage": 0.0, "low_hp_survived_s": 0.0,
	}


## Принимает ли кукла урон сейчас (жива и не в spawn grace).
func can_take_damage() -> bool:
	return alive and not _broken and _time >= grace_until


## Урон: amount HP от attacker (Doll | null) в часть part (имя узла) в точке position с нормалью normal; kind ∈ head|body|weapon|environment|self.
## Игнорируется, если кукла мертва или в spawn grace. hp ≤ 0 → knock_out(attacker, record).
func take_damage(amount: float, attacker: Node, part: String, position: Vector3, normal: Vector3, kind: String) -> void:
	if team != "" and attacker is Doll and attacker != self and (attacker as Doll).team == team:
		amount *= Tuning.TEAM_DAMAGE_MULT
	if amount <= 0.0 or not can_take_damage():
		hit_meta = {}
		return
	hp = maxf(hp - amount, 0.0)
	stats["damage_taken"] = float(stats["damage_taken"]) + amount
	stats["collisions"] = int(stats["collisions"]) + 1
	if kind == "self":
		stats["self_damage"] = float(stats["self_damage"]) + amount
	var record := {
		"victim": self, "attacker": attacker, "part": part, "kind": kind, "damage": amount,
		"position": position, "normal": normal, "time": _time, "hp_after": hp,
		"speed": 0.0, "weapon_id": "",
	}
	record.merge(hit_meta, true)
	hit_meta = {}
	last_hit = record
	damaged.emit(amount, attacker, part, position, kind)
	if hp <= 0.0:
		knock_out(attacker, record)


## Рывок на ближайшем тике управления — для ботов (external_input): Input они не читают. Те же правила, что у кнопки
## (перезарядка DASH_COOLDOWN_S, не в стане, не во время отдачи после удара).
func request_dash() -> void:
	_req_dash = true


## Переворот (FLIP_IMPULSE) на ближайшем тике управления — для ботов; направление — по input_vec.x, как у кнопки.
func request_flip() -> void:
	_req_flip = true


## Оторвать часть вместе с поддеревом (PvE, CONCEPT_V2: Разборщик откручивает деталь, позже пресс и Садовник).
## Снимается один сустав, которым часть висит на родителе; внутренние суставы поддерева остаются (оторванная рука гнётся), но без
## мышц и трения; пары мышц поддерева, переопределения и смешивание позы удаляются; DollCombat перестаёт слушать эти тела; оружие
## в оторванной кисти выпадает; тела получают мировой дамп и через 0.2 с сталкиваются с куклой (сразу нельзя — они перекрываются
## в точке сустава, Jolt растолкнул бы их). Кукла живёт дальше. Голова или торс — KO (kind "detach"). Возвращает оторванное тело.
func detach_part(part_name: String, by: Node = null) -> RigidBody3D:
	var b := parts.get(part_name) as RigidBody3D
	if b == null or _broken:
		return null
	var base := part_base_name(part_name)
	if base == "Head" or base == "Torso" or b == parts.get("Torso"):
		if alive:
			knock_out(by, {"kind": "detach", "part": part_name})
		part_detached.emit(part_name, by)
		return b
	var hang: Generic6DOFJoint3D = null
	var hang_name := ""
	for jn in joints.keys():
		var j := joints[jn] as Generic6DOFJoint3D
		if j != null and is_instance_valid(j) and j.get_node_or_null(j.node_b) == b:
			hang = j
			hang_name = String(jn)
			break
	if hang == null:
		return null
	# поддерево: b и всё, что висит на нём по суставам
	var sub: Array = [b]
	var sub_joints: Array = []
	var i := 0
	while i < sub.size():
		for jn in joints.keys():
			var j := joints[jn] as Generic6DOFJoint3D
			if j == null or not is_instance_valid(j) or j == hang:
				continue
			if j.get_node_or_null(j.node_a) == sub[i]:
				var child := j.get_node_or_null(j.node_b) as RigidBody3D
				if child != null and not sub.has(child):
					sub.append(child)
					sub_joints.append(String(jn))
		i += 1
	var sub_names: Array = []
	for s in sub:
		sub_names.append(String((s as Node).name))
	# оружие в оторванной кисти выпадает (WeaponPickup и похожие: is_holding / drop)
	for c in get_children():
		if c.has_method("is_holding") and c.has_method("drop"):
			for hn in sub_names:
				if bool(c.call("is_holding", hn)):
					c.call("drop", hn)
	var rec := {"hang": hang, "hang_name": hang_name, "parent": hang.get_node_or_null(hang.node_a), "sub": sub,
		"hang_friction": float(_friction_base.get(hang, 0.0)), "sub_joints": [], "pairs": [], "monitored": []}
	# сустав подвеса не удаляется: без тел он инертен и остаётся ребёнком куклы (reattach_part подключит его снова)
	hang.set("angular_motor_z/enabled", false)
	hang.node_a = NodePath()
	hang.node_b = NodePath()
	joints.erase(hang_name)
	_friction_base.erase(hang)
	_joint_override.erase(hang_name)
	_pose_blend.erase(hang_name)
	for jn in sub_joints:
		var j := joints[jn] as Generic6DOFJoint3D
		(rec["sub_joints"] as Array).append([String(jn), j, float(_friction_base.get(j, 0.0))])
		j.set("angular_motor_z/enabled", false)
		_friction_base.erase(j)
		joints.erase(jn)
		_joint_override.erase(jn)
		_pose_blend.erase(jn)
	var keep: Array = []
	for e in _muscle_pairs:
		if not (sub.has(e[0]) or sub.has(e[1])):
			keep.append(e)
		else:
			(rec["pairs"] as Array).append(e)
	_muscle_pairs = keep
	for c in get_children():
		var mon0: Variant = c.get("_monitored")
		if mon0 is Array:
			for s in sub:
				if (mon0 as Array).has(s) and not (rec["monitored"] as Array).has(s):
					(rec["monitored"] as Array).append(s)
	_detached[b] = rec
	for s in sub:
		var rb := s as RigidBody3D
		for con in rb.body_entered.get_connections():
			var cal: Callable = con["callable"]
			var o: Object = cal.get_object()
			if o != null and o.has_method("_on_part_contact"):
				rb.body_entered.disconnect(cal)
		for c in get_children():
			var mon: Variant = c.get("_monitored")
			if mon is Array:
				(mon as Array).erase(rb)
		parts.erase(rb.name)
		rb.linear_damp = Tuning.LINEAR_DAMP
		rb.angular_damp = Tuning.ANGULAR_DAMP
		rb.set_meta("detached_from", self)
		rb.add_to_group("detached_parts")
	total_mass = 0.0
	for p in parts.values():
		total_mass += (p as RigidBody3D).mass
	if _self_exceptions and is_inside_tree():
		var rest: Array = parts.values()
		get_tree().create_timer(0.2).timeout.connect(func() -> void:
			if not _detached.has(b):
				return   # уже прикручена обратно — исключения нужны
			for s in sub:
				for p in rest:
					if is_instance_valid(s) and is_instance_valid(p):
						(s as RigidBody3D).remove_collision_exception_with(p))
	part_detached.emit(part_name, by)
	return b


## Прикрутить обратно часть, оторванную detach_part (PvE: отобранную у Разборщика кисть игрок возвращает себе). body — корень
## оторванного поддерева (то, что вернул detach_part). Поддерево ставится так, чтобы кадр сустава на нём совпал с кадром на
## родителе (поза сборки), скорости — как у родителя; сустав подвеса подключается снова, внутренние суставы получают трение, пары
## мышц, мониторы DollCombat и исключения коллизий возвращаются, масса пересчитывается. false — не наша часть, кукла сломана/мертва,
## родитель тоже оторван, тела освобождены.
func reattach_part(body: RigidBody3D) -> bool:
	if body == null or not is_instance_valid(body) or _broken or not alive or not _detached.has(body):
		return false
	var rec: Dictionary = _detached[body]
	var a := rec["parent"] as RigidBody3D
	var hang := rec["hang"] as Generic6DOFJoint3D
	var hn: String = rec["hang_name"]
	if a == null or not is_instance_valid(a) or not parts.values().has(a) or hang == null or not is_instance_valid(hang):
		return false
	for s in rec["sub"]:
		if not is_instance_valid(s):
			return false
	var target: Transform3D = a.global_transform * (_joint_xf_a[hn] as Transform3D) * (_joint_xf_b[hn] as Transform3D).affine_inverse()
	var delta: Transform3D = target * body.global_transform.affine_inverse()
	for s in rec["sub"]:
		var rb := s as RigidBody3D
		rb.global_transform = delta * rb.global_transform
		rb.linear_velocity = a.linear_velocity
		rb.angular_velocity = a.angular_velocity
		rb.remove_meta("detached_from")
		rb.remove_from_group("detached_parts")
		parts[rb.name] = rb
	if _self_exceptions:
		for s in rec["sub"]:
			for p in parts.values():
				if p != s and not (rec["sub"] as Array).has(p):
					(s as RigidBody3D).add_collision_exception_with(p)
	hang.global_transform = a.global_transform * (_joint_xf_a[hn] as Transform3D)
	hang.node_a = hang.get_path_to(a)
	hang.node_b = hang.get_path_to(body)
	var hf: float = rec["hang_friction"]
	hang.set("angular_motor_z/enabled", hf > 0.0)
	hang.set("angular_motor_z/target_velocity", 0.0)
	hang.set("angular_motor_z/force_limit", hf)
	joints[hn] = hang
	_friction_base[hang] = hf
	for sj in rec["sub_joints"]:
		var j := sj[1] as Generic6DOFJoint3D
		var f: float = sj[2]
		j.set("angular_motor_z/enabled", f > 0.0)
		j.set("angular_motor_z/force_limit", f)
		joints[String(sj[0])] = j
		_friction_base[j] = f
	for e in rec["pairs"]:
		_muscle_pairs.append(e)
	_update_pair_gains()
	_refresh_muscles()
	for c in get_children():
		if c.has_method("_monitor"):
			for rb in rec["monitored"]:
				c.call("_monitor", rb)
	total_mass = 0.0
	for p in parts.values():
		total_mass += (p as RigidBody3D).mass
	_apply_base_damp(_flight_damp)
	_detached.erase(body)
	part_reattached.emit(String(body.name))
	return true


## Оторванные этой куклой и ещё не прикрученные корни (для UI «вернуть деталь»).
func detached_parts() -> Array:
	var out: Array = []
	for k in _detached.keys():
		if is_instance_valid(k):
			out.append(k)
	return out


## KO (CONCEPT.md §10, В3): кукла мертва, суставы рвутся (break_apart), сигнал knocked_out с KoRecord.
## Без аргументов — внешний KO (пропасть): attacker null, kind "self".
func knock_out(attacker: Node = null, record: Dictionary = {}) -> void:
	if not alive:
		return
	alive = false
	hp = 0.0
	stats["kos_taken"] = int(stats["kos_taken"]) + 1
	var rec := record.duplicate()
	rec["victim"] = self
	if not rec.has("attacker"):
		rec["attacker"] = attacker
	if not rec.has("kind"):
		rec["kind"] = "self"
	if not rec.has("time"):
		rec["time"] = _time
	if not rec.has("position"):
		rec["position"] = centre_of_mass()
	last_ko_record = rec
	break_apart()
	knocked_out.emit(attacker, rec)


## Разрыв куклы (как в Ragdoll Masters): все суставы освобождаются, мышцы и трение выключены, части получают текущую скорость
## плюс радиальный разлёт KO_BURST_SPEED; через мгновение снимаются исключения коллизий между своими частями, чтобы куски лежали кучей.
func break_apart() -> void:
	if _broken:
		return
	_broken = true
	alive = false
	var com := centre_of_mass()
	for j in joints.values():
		var jj := j as Generic6DOFJoint3D
		jj.set("angular_motor_z/enabled", false)
		jj.node_a = NodePath()
		jj.node_b = NodePath()
		jj.queue_free()
	joints.clear()
	_muscle_pairs.clear()
	_joint_override.clear()
	_muscle_mult = 0.0
	_k = 0.0
	_c = 0.0
	for b in parts.values():
		var body := b as RigidBody3D
		var dir := body.global_position - com
		dir.z = 0.0
		if dir.length() < 0.02:
			dir = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0)
		dir = dir.normalized()
		body.linear_velocity += dir * randf_range(Tuning.KO_BURST_SPEED.x, Tuning.KO_BURST_SPEED.y)
		body.angular_velocity += Vector3(0.0, 0.0, randf_range(-4.0, 4.0))
	_flight_damp = false
	_brake_on = false
	_apply_base_damp(false)
	# оружие выпадает, мёртвые кисти больше не хватают
	for c in get_children():
		if c.has_method("drop_all"):
			c.call("drop_all")
		if c.get("auto_pickup") != null:
			c.set("auto_pickup", false)
	if _self_exceptions and is_inside_tree():
		get_tree().create_timer(0.2).timeout.connect(_enable_self_collision)


func _enable_self_collision() -> void:
	if not _self_exceptions:
		return
	_self_exceptions = false
	var list: Array = parts.values()
	for i in range(list.size()):
		for j in range(i + 1, list.size()):
			if is_instance_valid(list[i]) and is_instance_valid(list[j]):
				(list[i] as RigidBody3D).remove_collision_exception_with(list[j])


func is_broken() -> bool:
	return _broken


## Сброс к началу матча: HP, статистика, стан, grace. Сломанную куклу (после KO) не чинит — Match.respawn_doll() инстанцирует
## сцену заново (doll.tscn / doll_dark.tscn) и переносит player_index / input_prefix / external_input / skin_*.
func reset_for_match() -> void:
	hp = max_hp
	stats = fresh_stats()
	hit_meta = {}
	last_hit = {}
	last_ko_record = {}
	grace_until = _time + Tuning.SPAWN_GRACE_S
	stunned_until = 0.0
	_stun_phase = StunPhase.NONE
	knockback_until = 0.0
	_flight_cap_until = -1.0
	stability_mult = 1.0
	dash_until = 0.0
	dash_ready_at = 0.0
	if _broken:
		push_warning("Doll.reset_for_match on a broken doll (%s): respawn it via Match.respawn_doll()" % name)
		return
	alive = true
	_refresh_muscles()


## Отброс (CONCEPT.md §5): импульс impulse (Н·с, уже с направлением и апбиасом) — KNOCKBACK_TORSO_SHARE в торс, остальное в ударенную
## часть (закрутка), но не больше KNOCKBACK_PART_MAX_DV м/с части (излишек — в торс). На max(KNOCKBACK_FREE_S, stun_s) снимается клэмп
## MAX_MOVE_SPEED, дамп частей — FLIGHT_LINEAR_DAMP до land(). approach_dir — направление удара без апбиаса: подлёт жертвы к бьющему
## вдоль него гасится до импульса. min_impulse (Н·с, Tuning.KNOCKBACK_MIN) — добор до минимума идёт ТОЛЬКО в торс: через ударенную часть
## он раскручивал бы конечность до KNOCKBACK_PART_MAX_DV (плечо 20 м/с после касания в 1.5 HP било в ответ на 29.7 HP — combat_gate
## rush_damage). Мышцы жертвы слабеют на удар (soften_muscles, Tuning.HIT_MUSCLE_SOFT).
func apply_knockback(impulse: Vector3, part: RigidBody3D = null, stun_s: float = 0.0, approach_dir: Vector3 = Vector3.ZERO, min_impulse: float = 0.0) -> void:
	if _broken or parts.is_empty():
		return
	# v6.2: встречный удар сначала гасит подлёт жертвы к бьющему — компонента скорости ЦМ против approach_dir (направление удара без
	# апбиаса, DollCombat) → 0 одинаково во всех частях: иначе лобовой наскок (жертва −3 м/с, отброс +1.9) оставлял её лететь на
	# атакующего и куклы висели сцепившись (клип v6, 1-й удар). Без approach_dir (ZERO) — не трогаем (оседание −1 м/с не в счёт).
	var n := Vector3(approach_dir.x, approach_dir.y, 0.0)
	if n.length_squared() > 1e-6:
		n = n.normalized()
		var p := Vector3.ZERO
		for b in parts.values():
			p += (b as RigidBody3D).linear_velocity * (b as RigidBody3D).mass
		var toward := (p / total_mass).dot(n)
		if toward < 0.0:
			for b in parts.values():
				(b as RigidBody3D).linear_velocity -= n * toward
	# импульс = Δv = J/m прямо в linear_velocity (как apply_central_impulse, но видно сразу — клэмп полёта ниже режет в этом же тике)
	var t := torso()
	var jl := impulse.length()
	if min_impulse > jl and jl > 1e-6:
		t.linear_velocity += impulse / jl * (min_impulse - jl) / t.mass
	if part == null or part == t or not is_instance_valid(part) or part.get_parent() != self:
		t.linear_velocity += impulse / t.mass
	else:
		var to_part := impulse * (1.0 - Tuning.KNOCKBACK_TORSO_SHARE)
		var extra := Vector3.ZERO
		var max_j := part.mass * Tuning.KNOCKBACK_PART_MAX_DV
		if to_part.length() > max_j:
			var capped := to_part.normalized() * max_j
			extra = to_part - capped
			to_part = capped
		part.linear_velocity += to_part / part.mass
		t.linear_velocity += (impulse * Tuning.KNOCKBACK_TORSO_SHARE + extra) / t.mass
	knockback_until = _time + maxf(Tuning.KNOCKBACK_FREE_S, stun_s)
	soften_muscles(float(soft_override.get("mult", Tuning.HIT_MUSCLE_SOFT)), float(soft_override.get("hold", Tuning.HIT_MUSCLE_SOFT_S)),
		float(soft_override.get("recover", Tuning.HIT_MUSCLE_RECOVER_S)))
	_set_flight_damp(true)
	_cap_flight_speed()   # серия ударов в клинче складывает импульсы — клэмп сразу, а не со следующего тика


func _set_flight_damp(on: bool) -> void:
	if on == _flight_damp:
		if on:
			_flight_damp_until = _time + FLIGHT_DAMP_MAX_S
		return
	_flight_damp = on
	_flight_damp_until = _time + FLIGHT_DAMP_MAX_S
	_brake_on = false
	_apply_base_damp(on)


## Дамп частей по Tuning.doll_linear_damp / doll_angular_damp: ядро (голова, торс) и конечности раздельно; flight — полёт после удара.
func _apply_base_damp(flight: bool) -> void:
	for b in parts.values():
		var rb := b as RigidBody3D
		rb.linear_damp = _part_linear_damp(String(rb.name), flight)
		rb.angular_damp = _part_angular_damp(String(rb.name))


## Та же логика, что Tuning.doll_linear_damp / doll_angular_damp (их зовёт builder), но на константах: методы автолоада недоступны,
## когда builder (-s) грузит этот скрипт — вызов Tuning.func() там не компилируется и сцена сохраняется без скрипта.
func _part_linear_damp(part: String, flight: bool) -> float:
	var core := Tuning.DOLL_CORE_PARTS.has(part)
	var key := ("flight_" if flight else "") + ("core" if core else "limb")
	if damp_override.has(key):
		return float(damp_override[key])
	if core:
		return Tuning.FLIGHT_LINEAR_DAMP if flight else Tuning.DOLL_LINEAR_DAMP
	return Tuning.FLIGHT_LIMB_LINEAR_DAMP if flight else Tuning.DOLL_LIMB_LINEAR_DAMP


func _part_angular_damp(part: String) -> float:
	if Tuning.DOLL_CORE_PARTS.has(part):
		return float(damp_override.get("core_ang", Tuning.ANGULAR_DAMP))
	return float(damp_override.get("limb_ang", Tuning.DOLL_LIMB_ANGULAR_DAMP))


func _brake_damp() -> float:
	return float(damp_override.get("brake", Tuning.IDLE_BRAKE_DAMP))


## Торможение без ввода: торс +Tuning.IDLE_BRAKE_DAMP, пока ввод 0, кукла жива и не в полёте (RM: скорость гаснет за ~1 с).
func _set_idle_brake(on: bool) -> void:
	if on == _brake_on or _brake_damp() <= 0.0:
		return
	_brake_on = on
	var t := torso()
	t.linear_damp = _part_linear_damp(String(t.name), false) + (_brake_damp() if on else 0.0)


## Ослабить мышцы на удар: k и tmax × mult (c × √mult — ζ тот же) на hold_s, затем линейный возврат за recover_s.
## Повторный удар не складывает, а продлевает (берётся меньший множитель). Без анимации: только ниже жёсткость пружин.
func soften_muscles(mult: float, hold_s: float, recover_s: float) -> void:
	if mult >= 1.0 or hold_s + recover_s <= 0.0 or _broken:
		return
	_soft_mult = minf(clampf(mult, 0.0, 1.0), _soft_factor())
	_soft_hold_until = _time + hold_s
	_soft_recover_s = recover_s


func _soft_factor() -> float:
	if _soft_hold_until < 0.0:
		return 1.0
	if _time <= _soft_hold_until:
		return _soft_mult
	var u := (_time - _soft_hold_until) / maxf(_soft_recover_s, 0.001)
	if u >= 1.0:
		_soft_hold_until = -1.0
		return 1.0
	return lerpf(_soft_mult, 1.0, u)


## Отдача атакующего после засчитанного удара (DollCombat._deliver): dir — направление удара (от атакующего к жертве, XY).
## Сближающая компонента скорости ЦМ вдоль dir гасится до −recoil_speed (только уменьшается: отходящий не ускоряется) одинаково
## во всех частях — мах конечностей не трогается; тяга выключена lock_s (не «дожимает» жертву телом, RM: бьющий зависает поодаль).
func apply_recoil(dir: Vector3, recoil_speed: float, lock_s: float) -> void:
	if _broken or parts.is_empty():
		return
	if _time < _flight_cap_until:
		return   # HIT_FX §2.3: крит-полёт не гасится отдачей встречного удара (клинч: оба тела бьют в одном тике)
	var n := Vector3(dir.x, dir.y, 0.0)
	if n.length_squared() < 1e-6:
		return
	n = n.normalized()
	var p := Vector3.ZERO
	for b in parts.values():
		p += (b as RigidBody3D).linear_velocity * (b as RigidBody3D).mass
	var along := (p / total_mass).dot(n)
	var target := -maxf(recoil_speed, 0.0)
	if along > target:
		var dv := n * (target - along)
		for b in parts.values():
			(b as RigidBody3D).linear_velocity += dv
	if lock_s > 0.0:
		thrust_lock_until = maxf(thrust_lock_until, _time + lock_s)


## Полёт после удара не быстрее Tuning.FLIGHT_MAX_SPEED по ЦМ (RM: тяжёлый удар ≤ ~3 H/с): лишнее вычитается одинаково из всех
## частей — вращение и мах конечностей не трогаются. Нужен для рывка: атакующий 40 кг × 14 м/с продавливает жертву телом до 6–7 м/с
## сверх отброса (feel_probe hit_dash; клип v5 — 7.3 м/с). Вне окна knockback_until действует обычный клэмп MAX_MOVE_SPEED торса.
func _cap_flight_speed() -> void:
	var p := Vector3.ZERO
	for b in parts.values():
		p += (b as RigidBody3D).linear_velocity * (b as RigidBody3D).mass
	var v := p / total_mass
	var sp := v.length()
	var cap := _flight_cap if _time < _flight_cap_until else Tuning.FLIGHT_MAX_SPEED
	if sp <= cap:
		return
	var excess := v * (1.0 - cap / sp)
	for b in parts.values():
		(b as RigidBody3D).linear_velocity -= excess


## Первое касание статики после полёта (зовёт DollCombat): дамп частей обратно.
func land() -> void:
	_set_flight_damp(false)


func is_flying() -> bool:
	return _time < knockback_until


## Крит-полёт (CritLaunch): клэмп ЦМ speed вместо FLIGHT_MAX_SPEED на seconds (физических), knockback_until продлевается.
func set_flight_cap(speed: float, seconds: float) -> void:
	_flight_cap = speed
	_flight_cap_until = _time + seconds
	knockback_until = maxf(knockback_until, _time + seconds)


func flight_cap_active() -> bool:
	return _time < _flight_cap_until


func is_dashing() -> bool:
	return _time < dash_until


## Стан (CONCEPT.md §9, В7): контроль ×(1 − STUN_CONTROL_LOSS), мышцы STUN_MUSCLE_STIFFNESS, трение STUN_JOINT_FRICTION —
## кукла пассивный рэгдолл; повторный стан продлевает, не складывает; после — возврат мышц за STUN_RECOVER_S.
func stun(seconds: float) -> void:
	if seconds <= 0.0 or not alive:
		return
	stunned_until = max(stunned_until, _time + seconds)
	if _stun_phase != StunPhase.STUNNED:
		_stun_phase = StunPhase.STUNNED
		_refresh_muscles()
	stunned.emit(seconds)


func is_stunned() -> bool:
	return _time < stunned_until


## PD-мышцы: момент к позе покоя на каждом суставе, приложен к обоим телам (равный и противоположный).
## k/c пары × _muscle_mult (SD × стан-рампа); в стане k = STUN_MUSCLE_STIFFNESS (0). Пары с k = c = 0 (лодыжки) пропускаются.
func _apply_muscles() -> void:
	var stun_k: float = Tuning.STUN_MUSCLE_STIFFNESS
	var ramp := _stun_ramp()
	if _muscle_mult <= 0.0 and stun_k <= 0.0:
		return
	var soft := _soft_factor()
	var soft_c := sqrt(soft)
	if absf(soft - _soft_applied) > 1e-4:
		_soft_applied = soft
		if _hit_friction_soft() and not _broken:
			_refresh_friction(ramp)
	var soft_groups := _soft_groups()
	for e in _muscle_pairs:
		var sf := soft if soft_groups.is_empty() or soft_groups.has(e[MP_GROUP]) else 1.0
		var k: float = lerpf(stun_k, float(e[MP_K]) * stability_mult, ramp) * sf if not _broken else 0.0
		var c: float = float(e[MP_C]) * _muscle_mult * (soft_c if sf < 1.0 else 1.0)
		if k <= 0.0 and c <= 0.0:
			continue
		var tmax: float = float(e[MP_TMAX]) * sf
		var a: RigidBody3D = e[0]
		var b: RigidBody3D = e[1]
		var ang := wrapf(b.global_rotation.z - a.global_rotation.z - float(e[MP_REST]), -PI, PI)
		var w := b.angular_velocity.z - a.angular_velocity.z
		var torque := clampf(-k * ang - c * w, -tmax, tmax)
		b.apply_torque(Vector3(0, 0, torque))
		a.apply_torque(Vector3(0, 0, -torque))


## Масса, под которую считается сила тяги (Н = MOVE_FORCE_PER_KG × эта масса). У Doll — вся масса куклы (разгон одинаков);
## ModularDoll переопределяет под фиксированную тягу Ядра (тяжёлая сборка разгоняется медленнее, BODY_CRAFT.md).
func thrust_mass() -> float:
	return total_mass


## Базовое имя части/сустава без короткого суффикса стороны или детали: «Hand_L» → «Hand», «Foot_3» → «Foot»
## (как Damage.body_mult_of и ModularDoll.base_name: режется суффикс длиной ≤ 1 символа).
static func part_base_name(part_name: String) -> String:
	var us := part_name.rfind("_")
	if us > 0 and part_name.length() - us <= 2:
		return part_name.substr(0, us)
	return part_name


func centre_of_mass() -> Vector3:
	var acc := Vector3.ZERO
	for b in parts.values():
		acc += part_centre(b as RigidBody3D) * (b as RigidBody3D).mass
	return acc / total_mass


## Центр масс части в мире. У частей doll.tscn origin в центре формы (совпадает), у деталей кита ModularDoll origin = Socket
## (точка сустава) — там центр масс смещён: CUSTOM — RigidBody3D.center_of_mass, AUTO — центр форм, посчитанный физикой
## (PhysicsDirectBodyState3D.center_of_mass_local). Локальная точка постоянна для твёрдого тела — кэш по телу.
func part_centre(b: RigidBody3D) -> Vector3:
	return b.global_transform * _part_com_local(b)


var _part_com_cache: Dictionary = {}   # RigidBody3D -> Vector3 (локальный центр масс; имя не _com_local — в ModularDoll есть static func _com_local)

func _part_com_local(b: RigidBody3D) -> Vector3:
	if _part_com_cache.has(b):
		return _part_com_cache[b]
	var v := Vector3.ZERO
	if b.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM:
		v = b.center_of_mass
	elif b.is_inside_tree():
		var st := PhysicsServer3D.body_get_direct_state(b.get_rid())
		if st == null:
			return v   # тело ещё не в физике — не кэшируем
		v = st.center_of_mass_local
	_part_com_cache[b] = v
	return v


func max_part_speed() -> float:
	var m := 0.0
	for b in parts.values():
		m = max(m, b.linear_velocity.length())
	return m


func head() -> RigidBody3D:
	return parts["Head"]


func torso() -> RigidBody3D:
	return parts["Torso"]


func _control_body() -> RigidBody3D:
	var t: String = control_target if control_target != "" else Tuning.CONTROL_TARGET
	return head() if t == "head" else torso()


func _physics_process(delta: float) -> void:
	_time += delta
	var req_dash := _req_dash   # одноразовые запросы ботов: живут один тик (стан/нет управления — пропадают)
	var req_flip := _req_flip
	_req_dash = false
	_req_flip = false
	if _stun_phase == StunPhase.STUNNED and not is_stunned():
		_stun_phase = StunPhase.RECOVER
		_stun_recover_t0 = _time
	if _stun_phase == StunPhase.RECOVER:
		_refresh_muscles()
		if _stun_ramp() >= 1.0:
			_stun_phase = StunPhase.NONE
	if _flight_damp and _time >= _flight_damp_until:
		_set_flight_damp(false)
	_tick_pose_blend()
	_apply_muscles()
	if _time < knockback_until and not _broken:
		_cap_flight_speed()
	if not alive:
		return
	if hp <= LOW_HP:
		stats["low_hp_survived_s"] = float(stats["low_hp_survived_s"]) + delta
	if not control_enabled:
		return
	var v := input_vec
	var dash_pressed := false
	var flip_pressed := false
	if not external_input:
		v = Input.get_vector(input_prefix + "_left", input_prefix + "_right", input_prefix + "_down", input_prefix + "_up")
		dash_pressed = Input.is_action_just_pressed(input_prefix + "_dash")
		flip_pressed = Input.is_action_just_pressed(input_prefix + "_flip")
	dash_pressed = dash_pressed or req_dash
	flip_pressed = flip_pressed or req_flip
	var locked := _time < thrust_lock_until
	if locked:
		v = Vector2.ZERO   # отдача после удара: тяги нет (RM: бьющий не дожимает жертву)
	_set_idle_brake(v.length_squared() <= 0.0001 and _time >= knockback_until)
	var control := 1.0 - Tuning.STUN_CONTROL_LOSS if is_stunned() else 1.0
	if dash_pressed and _time >= dash_ready_at and not is_stunned() and not locked:
		dash_until = _time + Tuning.DASH_DURATION_S
		dash_ready_at = _time + Tuning.DASH_COOLDOWN_S
	var body := _control_body()
	var mode: String = control_mode if control_mode != "" else Tuning.CONTROL_MODE
	var mult: float = (Tuning.DASH_MULT if _time < dash_until else 1.0) * control
	if mode == "rotate":
		if abs(v.x) > 0.01:
			torso().apply_torque(Vector3(0, 0, -v.x * Tuning.ROTATE_TORQUE * mult))
		if abs(v.y) > 0.01:
			body.apply_central_force(Vector3(0, v.y, 0) * Tuning.MOVE_FORCE_PER_KG * thrust_mass() * mult)
	var max_speed: float = Tuning.MAX_MOVE_SPEED * (Tuning.DASH_MULT if _time < dash_until else 1.0)
	if mode != "rotate" and v.length_squared() > 0.0001:
		var f := Vector3(v.x, v.y, 0.0).limit_length(1.0) * Tuning.MOVE_FORCE_PER_KG * thrust_mass() * mult
		if _time < knockback_until and body.linear_velocity.length() > max_speed:
			# в полёте после удара тяга не разгоняет дальше, только рулит/тормозит
			var vdir := body.linear_velocity.normalized()
			var along := f.dot(vdir)
			if along > 0.0:
				f -= vdir * along
		body.apply_central_force(f)
	if _time >= knockback_until and body.linear_velocity.length() > max_speed:   # после удара клэмп не режет полёт (§5)
		body.linear_velocity = body.linear_velocity.normalized() * max_speed
	if flip_pressed and not is_stunned():
		torso().apply_torque_impulse(Vector3(0, 0, Tuning.FLIP_IMPULSE * (1.0 if v.x >= 0.0 else -1.0)))
