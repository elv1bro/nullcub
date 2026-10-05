## Модульная кукла (docs/plan-demo/BODY_CRAFT.md §3, CONCEPT_V2 §4–8): тело собирается из деталей по чертежу BodyBlueprint
## в _ready() ДО Doll._ready() — Doll дальше сам находит тела и суставы по дереву и навешивает мышцы по префиксу имени сустава.
## Исключение из правила 2 ASSET_PIPELINE (CONCEPT_V2, «Следствия для кода»): детали — .tscn с маркерами (tools/build_body_parts.gd),
## рантайм только расставляет их по чертежу.
##
## Сборка:
##   • деталь = инстанс PartDef.scene (RigidBody3D, маркеры Socket / Anchor_*), имя тела — BodyBlueprint.body_name_of(uid);
##   • посадка: child = anchor × socket⁻¹ (кадр якоря родителя в кукле × обратный кадр Socket ребёнка);
##   • зеркало: правый якорь (meta mirror) отражает деталь по X — маркеры и формы M·T·M, меш — Mesh_R из сцены, если есть, иначе M·T;
##     зеркальность наследуется вниз по цепи (локоть правой руки тоже правый);
##   • сустав — Generic6DOFJoint3D как в doll.tscn (tools/build_doll_scene.gd `_joint`): линейные оси и углы X/Y заперты, Z с лимитами,
##     мотор-трение Tuning.JOINT_FRICTION × friction_factor группы, meta friction_factor; имя — BodyBlueprint.joint_name_of(uid);
##   • fixed-узел (BodyBlueprint.is_fixed: attach fixed, декор/броня, joint "weld") сливается с телом родителя: формы и меш
##     переезжают, масса (BodyBlueprint.node_mass) складывается, центр масс — взвешенный (CUSTOM);
##   • кукла ставится на пол: нижняя точка форм собранного тела — y = 0 локально (у human торс ровно на 1.17, как в doll.tscn).
## Углы (градусы): от направления якоря (−Y), наружу = + для левой стороны, у зеркальной — знак меняется. Jolt считает угол сустава
## от собранной позы, Doll — measured = child.rot.z − parent.rot.z, поэтому поза покоя = a0 + знак × угол (a0 — measured-угол сборки).
## Поза покоя чертежа ставится set_pose({сустав: measured°}) после Doll._ready, спавн сразу в позе — _snap_pose (центр поворота —
## точка сустава на текущем теле-родителе, см. там); reset_pose() возвращает позу чертежа, а не Tuning.POSE.
##
## Поверх Doll (без правки doll.gd, хуки для другой сессии — BODY_CRAFT.md §6):
##   • фиксированная тяга Ядра (CONCEPT_V2 §7, fixed_thrust): сила = MOVE_FORCE_PER_KG × thrust_mass(), а не × total_mass — тяжёлая
##     сборка разгоняется медленнее, лёгкая быстрее, у human (40 кг) тяга та же. Doll зовёт thrust_mass() в обеих строках тяги
##     (хук внесён 29.09), здесь он только переопределён; total_mass остаётся настоящей массой для отброса, отдачи и клэмпа полёта.
##   • демпфирование мышц по настоящей инерции цепи: сустав несёт meta "chain_inertia" (_make_joint), Doll._pair_inertia берёт её
##     вместо I группы Tuning.MUSCLE_GROUPS, если отличие больше Doll.CHAIN_INERTIA_TOLERANCE (= INERTIA_TOLERANCE, у human все цепи
##     в допуске — числа как у doll.tscn). До 29.09 это масштабирование жило здесь в _update_pair_gains (перенесено в Doll по просьбе
##     этой сессии; тяга — Doll.thrust_mass()); теперь _update_pair_gains здесь — только множители типа шарнира (ниже).
##   • DollCombat слушает контакты только частей с именами из DollCombat.MONITORED (Hand_L, Foot_R…) — у деталей «Foot_3», «Hand_C»
##     (по базовому имени, как Damage.body_mult_of) и у бьющих деталей STRIKER_KINDS («Chain_E» с шаром булавы) тот же монитор
##     включается здесь, когда DollCombat появляется ребёнком (Match.register).
##   • цепь (kind chain) — свободный шарнир с лимитами CHAIN_LIMITS; fixed-деталь с началом координат в Socket (детали оружия)
##     сливается с настоящим центром масс (центр объёмов форм, как AUTO у Jolt).
##
## Кит тела v2 (docs/plan-demo/BODY_KIT.md §4, §5.4; у деталей без base_mat и суставов pin — всё как раньше, human = doll.tscn):
##   • материал узла (node_mat ≠ base_mat) — сразу после _mirror_part, до слияния: поверхности Base_* мешей → MaterialDef.surface,
##     своё тело — physics_material_override (friction/bounce); масса узла = PartDef.mass × density / density base_mat;
##   • тип шарнира (KitJoint, node["joint"]): _make_joint — трение × friction типа (force_limit и meta friction_factor), лимиты
##     KitJoint.limits, meta joint_type; _update_pair_gains — k, tmax × множители типа, c × √k-множителя (free — 0, только трение);
##     weld — узел сливается с родителем как fixed, но в позе покоя своего сустава (_weld_rest);
##   • коннектор (PartDef.connector, не weld): Connector_<uid> на теле-ребёнке в точке сустава, шар цвета игрока (_add_connector);
##   • meta тел: "material" — кг железа (float, ScrapMachine.iron_mass) у КАЖДОГО тела; "body_mult" (Damage.body_mult_of_body) —
##     только если ≠ Damage.body_mult_of(имя): × body_mult материала своего узла × PartDef.hit_mult своего узла (форма: шипы, рога,
##     клешня) × body_mult слитого декора/брони (шипы). PartDef.body_mult детали со своим телом не читается (= Tuning.BODY_MULT по
##     префиксу, builder), hit_mult сваренного узла и weapon_mult слитого навершия — тоже (weapon_mult только для CraftedWeapon):
##     навершие на теле добавляет массу и формы;
##     "armor" — доля урона, которую снимают слитые с телом щитки (Tuning.PART_ARMOR; Damage.armor_mult_of_body), если она есть;
##   • цвет игрока — _recolor с одной копией на исходный материал (коннекторы и Shirt_Kit каждой детали).
##
## Покраска (docs/plan-demo/BODY_PAINT.md §5, BodyPaint): после Doll._ready — бит слоя наклеек мешам (кроме коннекторов), узлам с
## ключами paint / stickers / face — слой краски (next_pass поверхностей, кроме Shirt* / Face*), наклейки (меш-декали — MeshInstance3D
## «Sticker» на теле детали), фото на плашку лица. Физика не меняется. Ручки для мастерской: paint_handle(uid), ensure_paint(uid),
## stickers_of(uid), add_sticker(uid, st).
class_name ModularDoll
extends Doll

const DEFAULT_BLUEPRINT := "res://data/body/blueprints/human.tres"
## Лимиты сустава по группе (градусы, левая сторона, наружу = +, от направления якоря) — копия таблицы tools/build_doll_scene.gd
## (там она внутри _build_and_save): держать совпадающими, tests/body_probe сверяет human с doll.tscn. meta limit_deg якоря перекрывает.
const JOINT_LIMITS := {
	"Neck": Vector2(-40, 40), "Shoulder": Vector2(-25, 170), "Elbow": Vector2(0, 140), "Wrist": Vector2(-35, 35),
	"Hip": Vector2(-30, 120), "Knee": Vector2(-5, 120), "Ankle": Vector2(-25, 25),
}
## Допуск |I_цепи / I_группы − 1|, в котором демпфирование мышцы остаётся как у Doll (human: отличия ≤ 4 %).
const INERTIA_TOLERANCE := 0.15
## Сустав, где с любой стороны цепь (kind chain): «свободный шарнир» кистеня (BODY_CRAFT.md §1) — лимиты шире таблицы групп
## (у Ankle ±25°), если якорь не задал свои (meta limit_deg).
const CHAIN_LIMITS := Vector2(-160, 160)
## Виды деталей, которые бьют: их тела получают монитор контактов DollCombat, даже если имени нет в DollCombat.MONITORED
## (цепь, шар булавы, слитый с цепью, кулак на плече).
const STRIKER_KINDS := ["hand", "foot", "chain", "weapon_head", "handle"]
const MIRROR_X := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))

@export var blueprint: BodyBlueprint
## Фиксированная тяга Ядра (CONCEPT_V2 §7): false — как у Doll (сила ∝ массе, разгон у всех одинаковый).
@export var fixed_thrust := true
## Масса, при которой тяга совпадает с обычной куклой; ≤ 0 — масса куклы v3 по Tuning.MASS (40 кг).
@export var thrust_ref_mass := -1.0

## uid детали -> имя тела (fixed-деталь — имя тела-хозяина).
var uid_body: Dictionary = {}
## uid детали -> имя сустава, которым она крепится к родителю.
var uid_joint: Dictionary = {}
## Ошибки validate() чертежа, если он не собрался (тогда собран human).
var build_errors: PackedStringArray = []
## Запас прочности тел (Tuning.PART_BREAK, 04.10): имя тела → сколько урона В НЕГО оно ещё выдержит; кончился — деталь отлетает
## (part_broken, затем Doll.detach_part → part_detached). Ядра и головы здесь нет. part_integrity_max — запас целой детали.
var part_integrity: Dictionary = {}
var part_integrity_max: Dictionary = {}
## Деталь сломалась от урона (запас part_integrity кончился): part_name — имя тела, by — чей удар. Сразу после — part_detached.
signal part_broken(part_name: String, by: Node)
## Имя тела -> Transform3D в кукле сразу после сборки (до позы) — для проб.
var assembly: Dictionary = {}
var _bp_pose: Dictionary = {}          # имя сустава -> measured-градусы (поза покоя чертежа)
var _chain_inertia: Dictionary = {}    # имя сустава -> кг·м², инерция дистальной цепи вокруг оси сустава (сборка, по прямой)
var _striker: Dictionary = {}          # имя тела -> true: бьющая деталь (STRIKER_KINDS), монитор контактов в _hook_combat
var _joint_type: Dictionary = {}       # имя сустава -> тип шарнира KitJoint ("pin", "free", "spring", "motor"), для _update_pair_gains
var _paint: Dictionary = {}            # uid -> ручка слоя краски BodyPaint.attach_layer {layer, tex, materials, mesh_root}
var _stickers: Dictionary = {}         # uid -> Array[MeshInstance3D] наклеек узла (BodyPaint.add_sticker)
## Активные блоки и пассивы деталей (scripts/active/active_rig.gd, docs/plan-demo/ACTIVE_BLOCKS.md): заряд, каналы 1–3; null — нет.
var active_rig: ActiveRig


func _ready() -> void:
	_build()
	var snap := spawn_in_pose
	spawn_in_pose = false   # Doll._ready поставил бы Tuning.POSE с зеркалом по «_R» — у чертежа свои углы (ниже)
	super._ready()
	spawn_in_pose = snap
	_apply_paint()
	active_rig = ActiveRig.attach_if_needed(self)
	set_pose(_bp_pose)
	if snap:
		_snap_pose(SPAWN_POSE_GROUPS)
	child_entered_tree.connect(_on_child_entered)
	part_reattached.connect(_on_part_reattached)
	for c in get_children():
		if c is DollCombat:
			_hook_combat(c)


## Множитель входящего урона и стана (Doll.take_damage, DollCombat._deliver): команда (Doll) × активные блоки — энергощит гасит
## урон, фаза не берёт его совсем (ActiveRig.incoming_mult).
func team_mult_for(attacker: Node) -> float:
	var m := super.team_mult_for(attacker)
	return m * active_rig.incoming_mult() if active_rig != null and is_instance_valid(active_rig) else m


## Урон изнашивает деталь, в которую пришёл (Tuning.PART_BREAK): запас part_integrity тела тратится на урон, реально снятый с HP
## (после брони, блока кистью и множителя команды); кончился — деталь отлетает (_break_part на следующем кадре: удар считается
## внутри шага физики). KO этим ударом детали уже не ломает — кукла и так разлетается.
func take_damage(amount: float, attacker: Node, part: String, position: Vector3, normal: Vector3, kind: String) -> void:
	var before := hp
	super.take_damage(amount, attacker, part, position, normal, kind)
	var dealt := before - hp
	if not Tuning.PART_BREAK or JointBreak.on or PartHp.on or dealt <= 0.0 or not alive or not part_integrity.has(part):
		return   # JointBreak и PartHp (пробные режимы) считают износ сами, в Doll.take_damage — два счёта сразу не ведём
	part_integrity[part] = float(part_integrity[part]) - dealt
	if float(part_integrity[part]) <= 0.0:
		part_integrity.erase(part)
		_break_part.call_deferred(part, attacker)


func _break_part(part: String, by: Node) -> void:
	if not alive or not parts.has(part):
		return
	stats["parts_broken"] = int(stats.get("parts_broken", 0)) + 1
	part_broken.emit(part, by)
	detach_part(part, by)
	for n in part_integrity.keys():   # всё, что висело на отлетевшей детали, ушло вместе с ней
		if not parts.has(n):
			part_integrity.erase(n)


## Прикрученная обратно деталь (Doll.reattach_part) возвращается с полным запасом — и всё, что на ней висит.
func _on_part_reattached(_part: String) -> void:
	for n in part_integrity_max:
		if parts.has(n) and not part_integrity.has(n):
			part_integrity[n] = part_integrity_max[n]


## Поза покоя чертежа (а не Tuning.POSE).
func reset_pose(blend_s: float = 0.0) -> void:
	set_pose(_bp_pose, blend_s)


## Масса, для которой считается фиксированная тяга (Н = MOVE_FORCE_PER_KG × эта масса).
func thrust_mass() -> float:
	if not fixed_thrust:
		return total_mass   # обычная тяга Doll (Doll зовёт thrust_mass() в обеих строках тяги, и в окне полёта тоже)
	if thrust_ref_mass > 0.0:
		return thrust_ref_mass
	if PartHp.on:   # запас из деталей: тягу дают мотор ядра и голова (PartHp.thrust_n), разгон = тяга / настоящая масса сборки
		return PartHp.thrust_n(blueprint.core_def() if blueprint != null else null, parts.has("Head")) / Tuning.MOVE_FORCE_PER_KG
	# = Tuning.total_mass(); методы автолоада не компилируются, когда builder (-s) грузит этот скрипт
	var m: Dictionary = Tuning.MASS
	return float(m["Head"]) + float(m["Torso"]) + 2.0 * (float(m["UpperArm"]) + float(m["LowerArm"]) + float(m["Hand"])
		+ float(m["UpperLeg"]) + float(m["LowerLeg"]) + float(m["Foot"]))


## Имена тел, которыми управляет рука мышью (blueprint.control).
func control_part_names() -> PackedStringArray:
	var out: PackedStringArray = []
	for u in blueprint.control:
		if uid_body.has(u):
			out.append(String(uid_body[u]))
	return out


func energy_used() -> int:
	return blueprint.energy_used() if blueprint != null else 0


# --- покраска (docs/plan-demo/BODY_PAINT.md §5): только вид, физика не трогается ---

## Ручка слоя краски узла uid ({layer: PaintLayer, tex: ImageTexture3D, materials: [ShaderMaterial], mesh_root}); {} — краски нет.
## Мастерская рисует прямо в layer и зовёт layer.update_texture(tex).
func paint_handle(uid: String) -> Dictionary:
	return _paint.get(uid, {})


## Ручка слоя узла uid; слоя не было — пустой слой по габариту меша детали (BodyPaint.mesh_aabb) и next_pass на её поверхностях.
## {} — у узла нет меша.
func ensure_paint(uid: String) -> Dictionary:
	if _paint.has(uid):
		return _paint[uid]
	var root := BodyPaint.mesh_root_of(self, uid)
	if root == null or BodyPaint.meshes(root).is_empty():
		return {}
	var h := BodyPaint.attach_layer(root, PaintLayer.for_aabb(BodyPaint.mesh_aabb(root)))
	if not h.is_empty():
		_paint[uid] = h
	return h


## Наклейки узла uid (MeshInstance3D «Sticker», meta «sticker» — словарь чертежа) — поставленные из чертежа и через add_sticker.
func stickers_of(uid: String) -> Array:
	return (_stickers.get(uid, []) as Array).filter(func(d: Variant) -> bool: return is_instance_valid(d))


## Поставить наклейку на узел uid (st — словарь чертежа, BODY_PAINT.md §4) и запомнить её. null — нет узла / картинки.
func add_sticker(uid: String, st: Dictionary) -> MeshInstance3D:
	var d := BodyPaint.add_sticker(BodyPaint.body_of(self, uid), BodyPaint.mesh_root_of(self, uid), st)
	if d != null:
		if not _stickers.has(uid):
			_stickers[uid] = []
		(_stickers[uid] as Array).append(d)
	return d


## Бит слоя наклеек мешам (кроме коннекторов), потом покраска узлов чертежа с paint / stickers / face. Зовётся после Doll._ready (Shirt уже в цвете
## игрока, BodyPaint его не трогает) — и при респавне Match: новый инстанс собирается из того же чертежа.
func _apply_paint() -> void:
	BodyPaint.tag_layers(self)
	for n in blueprint.nodes:
		if not (n.has("paint") or n.has("stickers") or n.has("face")):
			continue
		var uid := String(n.get("uid", ""))
		if not uid_body.has(uid):
			continue
		var r := BodyPaint.apply_node(self, uid, n)
		if not (r["paint"] as Dictionary).is_empty():
			_paint[uid] = r["paint"]
		if not (r["stickers"] as Array).is_empty():
			_stickers[uid] = r["stickers"]


## Спавн сразу в позе чертежа (как Doll.spawn_in_pose, группы по порядку: проксимальные раньше). Отличие от Doll._snap_to_pose:
## центр поворота — точка сустава на ТЕКУЩЕМ родительском теле (по кадру сборки), а не узел сустава. Узел остаётся на месте сборки,
## и у Doll после поворота плеча на 85° локоть поворачивается вокруг старой точки — предплечье отрывается от плеча на 7 см (у пауков и
## длинной руки до 0.2 м), Jolt стягивает сустав на первых шагах рывком (tests/body_probe: human_vs_doll.doll_spawn_joint_gap_m).
func _snap_pose(groups: Array) -> void:
	var pairs: Variant = get("_muscle_pairs")
	if not pairs is Array:
		return
	for g in groups:
		for e in pairs:
			if e[MP_GROUP] != g:
				continue
			var a: RigidBody3D = e[0]
			var b: RigidBody3D = e[1]
			var cur := wrapf(b.global_rotation.z - a.global_rotation.z, -PI, PI)
			var delta := wrapf(float(e[MP_REST]) - cur, -PI, PI)
			if absf(delta) < 1e-4:
				continue
			var local: Vector3 = (assembly[String(a.name)] as Transform3D).affine_inverse() * (joints[e[MP_NAME]] as Node3D).position
			var pivot := a.global_transform * local
			var rot := Basis(Vector3(0, 0, 1), delta)
			for body in _distal(b, pairs):
				var rb := body as RigidBody3D
				var tr := rb.global_transform
				rb.global_transform = Transform3D(rot * tr.basis, pivot + rot * (tr.origin - pivot))


## Тело b и всё ниже него по суставам.
static func _distal(b: RigidBody3D, pairs: Array) -> Array:
	var out: Array = [b]
	var i := 0
	while i < out.size():
		for e in pairs:
			if e[0] == out[i] and not out.has(e[1]):
				out.append(e[1])
		i += 1
	return out


## Doll пересчитывает k/c/tmax пар из групп (и override сустава) в _ready, set_muscles, set_muscle_group, set_muscle_joint (оружие
## в руке), clear_muscle_joint — поверх каждого раза множители типа шарнира (KitJoint.TYPES, BODY_KIT.md §5.4): k и tmax × k/tmax
## типа, c × √(k-множителя) (c = 2ζ√(k·I)), если не задано единое c (Doll._uniform_c ≥ 0); free — k = c = tmax = 0 (только трение).
## pin (все суставы human) не трогается — числа как у doll.tscn.
func _update_pair_gains() -> void:
	super._update_pair_gains()
	if _joint_type.is_empty():
		return
	var pairs: Variant = get("_muscle_pairs")
	if not pairs is Array:
		return
	var uc: Variant = get("_uniform_c")
	var uniform_c := uc != null and float(uc) >= 0.0
	for e in pairs:
		var jt := String(_joint_type.get(String(e[MP_NAME]), KitJoint.DEFAULT))
		if jt == KitJoint.DEFAULT:
			continue
		var ti := KitJoint.info(jt)
		var km := float(ti.get("k", 1.0))
		e[MP_K] = float(e[MP_K]) * km
		e[MP_TMAX] = float(e[MP_TMAX]) * float(ti.get("tmax", 1.0))
		if km <= 0.0:
			e[MP_K] = 0.0
			e[MP_C] = 0.0
			e[MP_TMAX] = 0.0
		elif not uniform_c:
			e[MP_C] = float(e[MP_C]) * sqrt(km)


# --- сборка ---

func _build() -> void:
	if blueprint == null:
		blueprint = load(DEFAULT_BLUEPRINT) as BodyBlueprint
	build_errors = blueprint.validate()
	if not build_errors.is_empty():
		push_error("ModularDoll «%s»: чертёж «%s» не собирается, собираю human:\n  • %s" % [name, blueprint.id, "\n  • ".join(build_errors)])
		blueprint = load(DEFAULT_BLUEPRINT) as BodyBlueprint
	var info := {}          # uid -> {def, xf (кадр детали в кукле), mirror, anchors, body (хозяин), body_xf}
	var bodies: Array[RigidBody3D] = []
	var todo: Array = []    # суставы: {name, group, type, pos, a, b, limits, mirror}
	var iron := {}          # тело -> кг железа (meta material): свой узел + слитые, чей материал iron (BodyBlueprint.node_iron)
	var mult := {}          # тело -> множитель удара сверх таблицы по имени: материал своего узла
	var shape := {}         # тело -> [бонус формы, профиль]: форма своей детали (hit_mult) или слитого декора/брони — больший (WORKSHOP_V3.md §4)
	var armor := {}         # тело -> доля урона, которую снимают слитые с ним щитки (Tuning.PART_ARMOR, meta armor)
	var integ := {}         # тело -> запас прочности (Tuning.PART_INTEGRITY × прочность детали + щитки); ядра и головы тут нет
	part_integrity.clear()
	part_integrity_max.clear()
	for n in blueprint.sorted_nodes():
		var uid := String(n["uid"])
		var def := BodyBlueprint.part_def(String(n["part"]))
		var inst := def.scene.instantiate() as RigidBody3D
		var parent := String(n.get("parent", ""))
		var mirror := false
		var a: Dictionary = {}
		var a_xf := Transform3D.IDENTITY
		if parent != "":
			var p: Dictionary = info[parent]
			a = (p["anchors"] as Dictionary)[String(n["anchor"])]
			a_xf = (p["xf"] as Transform3D) * (a["xf"] as Transform3D)
			mirror = bool(p["mirror"]) != bool(a["mirror"])
		_mirror_part(inst, mirror)
		# кит v2 (BODY_KIT.md §4): материал узла — до слияния, пока меши ещё под инстансом детали
		var mat_id := blueprint.node_mat(uid)
		var mdef: MaterialDef = null
		if def.base_mat != "":
			mdef = MaterialDef.get_def(mat_id)
		var repaint := mdef != null and mat_id != def.base_mat
		if repaint and mdef.surface != null:
			_swap_base_surfaces(inst, mdef.surface)
		var node_mass := blueprint.node_mass(uid)
		var node_iron := blueprint.node_iron(uid)
		var sock := inst.get_node_or_null("Socket") as Node3D
		var xf := Transform3D.IDENTITY
		if parent != "":
			xf = a_xf * (sock.transform if sock != null else Transform3D.IDENTITY).affine_inverse()
			# сварка — в позе покоя сустава (до entry: дети, слияние, центр масс и пол берут повёрнутый кадр); fixed по PartDef — как был
			if KitJoint.is_weld(String(n.get("joint", ""))) and not BodyBlueprint.is_fixed_part(def):
				xf = _weld_rest(uid, n, a, mirror, a_xf.origin) * xf
		var anchors := {}
		for c in inst.get_children():
			if c is Marker3D and String(c.name).begins_with("Anchor_"):
				anchors[String(c.name)] = BodyBlueprint.anchor_info(c as Marker3D)
		var entry := {"def": def, "xf": xf, "mirror": mirror, "anchors": anchors, "body": inst, "body_xf": xf}
		info[uid] = entry
		if blueprint.is_fixed(uid):   # fixed по PartDef (декор, броня, детали оружия) или joint "weld"
			var host: RigidBody3D = info[parent]["body"]
			entry["body"] = host
			entry["body_xf"] = info[parent]["body_xf"]
			_merge_into(host, entry["body_xf"], inst, xf, node_mass, uid)
			if node_iron:
				iron[host] = float(iron.get(host, 0.0)) + node_mass
			if PartDef.FIXED_KINDS.has(def.kind) and def.body_mult > float((shape.get(host, [1.0, ""]) as Array)[0]):
				shape[host] = [def.body_mult, def.hit_profile]   # шипы / рога / наруч: форма хозяина, не множитель поверх неё
			var part_armor := Damage.part_armor(def.id)
			if part_armor > 0.0:   # щиток бережёт тело, с которым слит (Tuning.PART_ARMOR)
				armor[host] = Damage.armor_stack(float(armor.get(host, 0.0)), part_armor)
				if integ.has(host):
					integ[host] = float(integ[host]) + Tuning.PART_INTEGRITY * Tuning.ARMOR_INTEGRITY_BONUS
			uid_body[uid] = String(host.name)
			if STRIKER_KINDS.has(def.kind):
				_striker[String(host.name)] = true
			continue
		inst.name = blueprint.body_name_of(uid)
		inst.mass = node_mass
		inst.transform = xf
		if repaint:   # по умолчанию у детали кита уже физматериал base_mat (builder), у kit_human — байт в байт как у wood_*
			inst.physics_material_override = mdef.physics_material()
		iron[inst] = node_mass if node_iron else 0.0
		mult[inst] = mdef.body_mult if mdef != null else 1.0
		if not is_equal_approx(def.hit_mult, 1.0):
			shape[inst] = [def.hit_mult, def.hit_profile]   # форма детали (шипы, рога, клешня) × скорость — Damage.shape_mult
		var durability := Damage.part_durability(def, blueprint.node_mat(uid))
		inst.set_meta("durability", durability)   # ❤ детали в запасе из деталей (Doll._init_part_hp, PartHp.hp_of)
		if def.kind != "core" and def.kind != "head":
			integ[inst] = Tuning.PART_INTEGRITY * durability
		var own_armor := Damage.part_armor(def.id)
		if own_armor > 0.0:   # своя броня детали (ядро с толстыми стенками); слитые щитки сложатся с ней
			armor[inst] = own_armor
		bodies.append(inst)
		uid_body[uid] = String(inst.name)
		if STRIKER_KINDS.has(def.kind):
			_striker[String(inst.name)] = true
		if parent == "":
			continue
		var g := blueprint.joint_group_of(uid)
		var rel: float
		if n.has("rest_deg"):
			rel = float(n["rest_deg"])
		elif bool(a["rest_from_pose"]) and Tuning.POSE.has(g):
			rel = float(Tuning.POSE[g])
		else:
			rel = float(a["rest_deg"])
		var host_p: RigidBody3D = info[parent]["body"]
		var a0 := rad_to_deg(_rot_z(xf.basis) - _rot_z((info[parent]["body_xf"] as Transform3D).basis))
		var jn := blueprint.joint_name_of(uid)
		var jt := blueprint.joint_type_of(uid)
		uid_joint[uid] = jn
		_joint_type[jn] = jt
		todo.append({
			"name": jn, "group": g, "type": jt, "pos": a_xf.origin, "a": host_p, "b": inst, "mirror": mirror,
			"limits": KitJoint.limits(jt, _limits_for(a, g, def, info[parent]["def"])),
		})
		_bp_pose[jn] = wrapf(a0 + (-rel if mirror else rel), -180.0, 180.0)
		if def.connector:
			_add_connector(inst, uid, jt, xf.affine_inverse() * a_xf, a, g)

	# на пол: нижняя точка форм — y = 0
	var min_y := INF
	for b in bodies:
		for c in b.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
				var h := _shape_half((c as CollisionShape3D).shape)
				var w: AABB = (b.transform * (c as Node3D).transform) * AABB(-h, h * 2.0)
				min_y = minf(min_y, w.position.y)
	var shift := Vector3(0.0, -min_y if min_y < INF else 0.0, 0.0)
	for b in bodies:
		b.transform.origin += shift
		assembly[String(b.name)] = b.transform
		# магнит Свалки (ScrapMachine.iron_mass: число = кг железа) и удар частью (Damage.body_mult_of_body) — BODY_KIT.md §5.4
		b.set_meta("material", float(iron.get(b, 0.0)))
		var bm0 := Damage.body_mult_of(String(b.name))
		var bm := bm0 * float(mult.get(b, 1.0))
		if not is_equal_approx(bm, bm0):
			b.set_meta("body_mult", bm)
		if shape.has(b):
			b.set_meta("shape_mult", minf(float(shape[b][0]), Tuning.SHAPE_MULT_MAX) if float(shape[b][0]) > 1.0 else float(shape[b][0]))
			b.set_meta("shape_profile", String(shape[b][1]))
		if armor.has(b):
			b.set_meta("armor", float(armor[b]))   # Damage.armor_mult_of_body: урон В это тело × (1 − броня)
		if integ.has(b):
			part_integrity[String(b.name)] = float(integ[b])
			part_integrity_max[String(b.name)] = float(integ[b])
		add_child(b)
	for jd in todo:
		jd["pos"] = (jd["pos"] as Vector3) + shift
		_chain_inertia[jd["name"]] = _inertia_about(jd["b"], jd["pos"], todo)
		add_child(_make_joint(jd))


## Сварка (joint "weld", BODY_KIT.md §5.2, §5.4) замораживает деталь в позе покоя её сустава, а не прямо по якорю: поворот вокруг
## точки сустава pivot (кадр куклы) на угол покоя — rest_deg узла, иначе Tuning.POSE группы якоря (rest_from_pose), иначе rest_deg
## якоря, как у сустава в _build. Группа — BodyBlueprint.anchor_group_of (joint_group_of у сваренного узла пуст: сустава нет),
## у зеркальной стороны знак меняется (как _bp_pose). Плечо, сваренное на Shoulder_*, торчит под 85°, а не висит вниз.
func _weld_rest(uid: String, n: Dictionary, a: Dictionary, mirror: bool, pivot: Vector3) -> Transform3D:
	var g := blueprint.anchor_group_of(uid)
	var rel: float
	if n.has("rest_deg"):
		rel = float(n["rest_deg"])
	elif bool(a.get("rest_from_pose", false)) and Tuning.POSE.has(g):
		rel = float(Tuning.POSE[g])
	else:
		rel = float(a.get("rest_deg", 0.0))
	if is_zero_approx(rel):
		return Transform3D.IDENTITY
	var r := Basis(Vector3(0, 0, 1), deg_to_rad(-rel if mirror else rel))
	return Transform3D(r, pivot - r * pivot)


## Лимиты сустава: meta limit_deg якоря, иначе у цепи — CHAIN_LIMITS, иначе таблица групп (= doll.tscn).
static func _limits_for(a: Dictionary, group: String, child: PartDef, parent: PartDef) -> Vector2:
	if a.has("limit_deg"):
		return a["limit_deg"]
	if child.kind == "chain" or parent.kind == "chain":
		return CHAIN_LIMITS
	return JOINT_LIMITS.get(group, Vector2(-45, 45))


## Generic6DOFJoint3D как tools/build_doll_scene.gd `_joint` (лимиты: намерение [lo, hi] левой стороны → Jolt [−hi, −lo],
## правой → [lo, hi], см. _lim там). Пути к телам ставятся до add_child: кадры сустава считаются один раз при входе в дерево.
## Тип шарнира (KitJoint): трение × friction типа (и в meta friction_factor — Doll.joint_friction ≥ 0 читает её), лимиты уже
## пересчитаны KitJoint.limits в _build, meta joint_type.
func _make_joint(jd: Dictionary) -> Generic6DOFJoint3D:
	var g := String(jd["group"])
	var jt := String(jd.get("type", KitJoint.DEFAULT))
	var ff := float((Tuning.MUSCLE_GROUPS[g] as Dictionary)["friction_factor"]) * float(KitJoint.info(jt).get("friction", 1.0))
	var j := Generic6DOFJoint3D.new()
	j.name = String(jd["name"])
	j.position = jd["pos"]
	j.exclude_nodes_from_collision = true
	for ax in ["x", "y", "z"]:
		j.set("linear_limit_%s/enabled" % ax, true)
		j.set("linear_limit_%s/upper_distance" % ax, 0.0)
		j.set("linear_limit_%s/lower_distance" % ax, 0.0)
	for ax in ["x", "y"]:
		j.set("angular_limit_%s/enabled" % ax, true)
		j.set("angular_limit_%s/upper_angle" % ax, 0.0)
		j.set("angular_limit_%s/lower_angle" % ax, 0.0)
	var lim: Vector2 = jd["limits"]
	var l := Vector2(lim.x, lim.y) if bool(jd["mirror"]) else Vector2(-lim.y, -lim.x)
	j.set("angular_limit_z/enabled", true)
	j.set("angular_limit_z/lower_angle", deg_to_rad(l.x))
	j.set("angular_limit_z/upper_angle", deg_to_rad(l.y))
	var f: float = Tuning.JOINT_FRICTION * ff
	j.set("angular_motor_z/enabled", f > 0.0)
	j.set("angular_motor_z/target_velocity", 0.0)
	j.set("angular_motor_z/force_limit", f)
	j.set_meta("friction_factor", ff)
	j.set_meta("chain_inertia", _chain_inertia.get(j.name, 0.0))
	j.set_meta("joint_type", jt)
	j.node_a = NodePath("../" + String((jd["a"] as Node).name))
	j.node_b = NodePath("../" + String((jd["b"] as Node).name))
	return j


## Отражение детали по X для правой стороны: маркеры и формы — M·T·M (кадр без отражения), меш — Mesh_R (правый GLB) или M·T.
func _mirror_part(inst: RigidBody3D, on: bool) -> void:
	var mesh_r := inst.get_node_or_null("Mesh_R") as Node3D
	if not on:
		if mesh_r != null:
			inst.remove_child(mesh_r)
			mesh_r.free()
		return
	var mesh := inst.get_node_or_null("Mesh") as Node3D
	if mesh_r != null:
		if mesh != null:
			inst.remove_child(mesh)
			mesh.free()
		mesh_r.name = "Mesh"
		mesh_r.visible = true
		mesh_r.transform = _mirrored(mesh_r.transform)
	elif mesh != null:
		mesh.transform = Transform3D(MIRROR_X, Vector3.ZERO) * mesh.transform
	for c in inst.get_children():
		if c is Marker3D or c is CollisionShape3D:
			(c as Node3D).transform = _mirrored((c as Node3D).transform)


static func _mirrored(t: Transform3D) -> Transform3D:
	return Transform3D(MIRROR_X * t.basis * MIRROR_X, MIRROR_X * t.origin)


## Цвет игрока — цикл Doll._recolor (зовётся из Doll._ready, GDScript отдаёт вызов сюда), но одна копия материала на ИСХОДНЫЙ
## материал, а не на каждую поверхность: у куклы кита Shirt_Kit есть на каждой детали и на каждом коннекторе (13–19 шаров), у Doll
## каждая поверхность получала свой дубликат — 25–37 одинаковых материалов на куклу (рендер их не делит), а в headless при
## освобождении dummy-рендер писал «Parameter "material" is null» на каждую куклу кита. Альфа — своя у каждого исходника (Shirt и
## Shirt_Paint остаются разными копиями). BODY_KIT.md §5.4.
func _recolor(body: Node, material_name: String, colour: Color) -> void:
	if body == null:
		return
	var cache := {}   # исходный материал -> его перекрашенная копия
	for m in _find_meshes(body):
		var mi: MeshInstance3D = m
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var mat: Material = mi.get_active_material(s)
			if mat == null or not mat.resource_name.begins_with(material_name):
				continue
			if not cache.has(mat):
				var dup: Material = mat.duplicate()
				if dup is BaseMaterial3D:
					var c := colour
					c.a = dup.albedo_color.a
					dup.albedo_color = c
				cache[mat] = dup
			mi.set_surface_override_material(s, cache[mat])


## Материал узла кита (BODY_KIT.md §4): поверхности Base_* всех мешей детали → surface MaterialDef (override на инстансе, общий
## ресурс меша не трогаем; Shirt_Kit, Face и фурнитура остаются — Doll._recolor потом красит Shirt_*).
func _swap_base_surfaces(n: Node, surface: Material) -> void:
	for m in _find_meshes(n):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var cur := mi.get_active_material(s)
			if cur != null and cur.resource_name.begins_with("Base_"):
				mi.set_surface_override_material(s, surface)


## Коннектор кита (BODY_KIT.md §5.4): шар шарнира на теле-ребёнке Connector_<uid> — инстанс KitJoint.connector_scene(тип) в точке
## сустава (local — кадр якоря родителя в осях тела: у зеркальной детали точка уже зеркальная, сам шар симметричен и не отражается),
## масштаб — meta joint_r якоря, иначе KitJoint.RADIUS группы. Без коллизий, meta rig_mesh; ставится до Doll._ready (_recolor
## красит Shirt_Kit в цвет игрока). Сцены пишет tools/build_body_kit.gd — пока файла нет, шара нет.
static var _connector_scenes: Dictionary = {}   # путь -> PackedScene (null — файла нет): сцену не перечитывать с диска на каждый сустав


func _add_connector(body: RigidBody3D, uid: String, jt: String, local: Transform3D, a: Dictionary, group: String) -> void:
	var path := KitJoint.connector_scene(jt)
	if path == "":
		return
	if not _connector_scenes.has(path):
		_connector_scenes[path] = load(path) as PackedScene if ResourceLoader.exists(path) else null
	var ps: PackedScene = _connector_scenes[path]
	if ps == null:
		return
	var c := ps.instantiate()
	if not c is Node3D:
		c.free()
		return
	var r := float(a.get("joint_r", 0.0))
	if r <= 0.0:
		r = KitJoint.radius_for(group)
	c.name = "Connector_" + uid
	(c as Node3D).transform = Transform3D(local.basis.orthonormalized().scaled(Vector3.ONE * r), local.origin)
	c.set_meta("rig_mesh", true)
	body.add_child(c)


## fixed-деталь: формы, меши и маркеры переезжают в тело-хозяина (host_xf — его кадр в кукле), масса складывается, центр масс —
## взвешенный по массам (CUSTOM: AUTO у Jolt считал бы его по объёму форм).
func _merge_into(host: RigidBody3D, host_xf: Transform3D, part: RigidBody3D, part_xf: Transform3D, mass: float, uid: String) -> void:
	var rel := host_xf.affine_inverse() * part_xf
	var host_com := _com_local(host)   # до переезда форм: центр масс хозяина по его собственным формам
	for c in part.get_children():
		if c is Node3D:
			part.remove_child(c)
			c.owner = null   # владелец — корень сцены детали, она сейчас освобождается
			(c as Node3D).transform = rel * (c as Node3D).transform
			c.name = "%s_%s" % [c.name, uid]
			host.add_child(c)
	var m0 := host.mass
	var c0 := host_com
	var c1 := rel * _com_local(part)
	host.mass = m0 + mass
	host.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	host.center_of_mass = (c0 * m0 + c1 * mass) / maxf(m0 + mass, 1e-6)
	part.free()


## Инерция вокруг оси Z через pivot: тело b и всё дистальное по суставам todo; своя инерция тела — бокс по габариту форм.
func _inertia_about(b: RigidBody3D, pivot: Vector3, todo: Array) -> float:
	var chain: Array = [b]
	var i := 0
	while i < chain.size():
		for jd in todo:
			if jd["a"] == chain[i] and not chain.has(jd["b"]):
				chain.append(jd["b"])
		i += 1
	var total := 0.0
	for body in chain:
		var rb := body as RigidBody3D
		var com := rb.transform * _com_local(rb)
		var d := Vector2(com.x - pivot.x, com.y - pivot.y)
		var ext := _local_extent(rb)
		total += rb.mass * (d.length_squared() + (ext.x * ext.x + ext.y * ext.y) / 12.0)
	return total


## Центр масс тела в его осях: CUSTOM — как задан, AUTO — центр объёмов форм (Jolt считает массу по формам при равной плотности;
## у деталей куклы v3 форма в начале координат → 0, у деталей оружия начало — в Socket, форма ниже).
static func _com_local(rb: RigidBody3D) -> Vector3:
	if rb.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM:
		return rb.center_of_mass
	var acc := Vector3.ZERO
	var vol := 0.0
	for c in rb.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
			var v := _shape_volume((c as CollisionShape3D).shape)
			acc += (c as Node3D).position * v
			vol += v
	return acc / vol if vol > 0.0 else Vector3.ZERO


static func _shape_volume(s: Shape3D) -> float:
	if s is CapsuleShape3D:
		var c := s as CapsuleShape3D
		return PI * c.radius * c.radius * maxf(c.height - 2.0 * c.radius, 0.0) + 4.0 / 3.0 * PI * pow(c.radius, 3.0)
	if s is SphereShape3D:
		return 4.0 / 3.0 * PI * pow((s as SphereShape3D).radius, 3.0)
	if s is CylinderShape3D:
		var cy := s as CylinderShape3D
		return PI * cy.radius * cy.radius * cy.height
	var h := _shape_half(s)
	return 8.0 * h.x * h.y * h.z


## Габарит форм тела в его локальных осях (м).
static func _local_extent(rb: RigidBody3D) -> Vector3:
	var box := AABB()
	var first := true
	for c in rb.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
			var h := _shape_half((c as CollisionShape3D).shape)
			var w: AABB = (c as Node3D).transform * AABB(-h, h * 2.0)
			box = w if first else box.merge(w)
			first = false
	return box.size


static func _shape_half(s: Shape3D) -> Vector3:
	if s is BoxShape3D:
		return (s as BoxShape3D).size * 0.5
	if s is CapsuleShape3D:
		var c := s as CapsuleShape3D
		return Vector3(c.radius, maxf(c.height * 0.5, c.radius), c.radius)
	if s is SphereShape3D:
		return Vector3.ONE * (s as SphereShape3D).radius
	if s is CylinderShape3D:
		var cy := s as CylinderShape3D
		return Vector3(cy.radius, cy.height * 0.5, cy.radius)
	if s is ConvexPolygonShape3D:
		var pts := (s as ConvexPolygonShape3D).points
		var m := Vector3.ZERO
		for p in pts:
			m = Vector3(maxf(m.x, absf(p.x)), maxf(m.y, absf(p.y)), maxf(m.z, absf(p.z)))
		return m
	return Vector3.ONE * 0.05


static func _rot_z(b: Basis) -> float:
	return atan2(b.x.y, b.x.x)


# --- DollCombat: монитор контактов у деталей с «чужими» суффиксами ---

func _on_child_entered(n: Node) -> void:
	if n is DollCombat:
		if n.is_node_ready():
			_hook_combat(n)
		else:
			n.ready.connect(_hook_combat.bind(n), CONNECT_ONE_SHOT)


## Нужен ли части монитор контактов DollCombat: базовое имя (без «_X») есть в DollCombat.MONITORED или деталь бьющая (STRIKER_KINDS).
func combat_monitored(part_name: String) -> bool:
	for pn in DollCombat.MONITORED:
		if base_name(String(pn)) == base_name(part_name):
			return true
	return _striker.has(part_name)


## Части из combat_monitored() получают тот же монитор, что Hand_L / Foot_R у Doll.
func _hook_combat(c: Node) -> void:
	var mon: Variant = c.get("_monitored")
	if not mon is Array or not c.has_method("_on_part_contact"):
		push_warning("ModularDoll: у DollCombat нет _monitored/_on_part_contact — детали вне DollCombat.MONITORED без монитора ударов")
		return
	for b in parts.values():
		var rb := b as RigidBody3D
		if (mon as Array).has(rb) or not combat_monitored(String(rb.name)):
			continue
		rb.contact_monitor = true
		rb.max_contacts_reported = maxi(rb.max_contacts_reported, DollCombat.MAX_CONTACTS)
		rb.body_entered.connect(Callable(c, "_on_part_contact").bind(rb))
		(mon as Array).append(rb)


## «Hand_L» → «Hand», «Foot_3» → «Foot» (как Damage.body_mult_of: режется суффикс длиной ≤ 1 символа).
static func base_name(part_name: String) -> String:
	var us := part_name.rfind("_")
	if us > 0 and part_name.length() - us <= 2:
		return part_name.substr(0, us)
	return part_name
