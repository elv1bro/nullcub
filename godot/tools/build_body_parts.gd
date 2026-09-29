## Builder системы сборки тела (docs/plan-demo/BODY_CRAFT.md §1–3, ASSET_PIPELINE.md правило 2). Пишет:
##   res://scenes/body/parts/<id>.tscn       — сцены деталей: RigidBody3D (форма Shape, меш Mesh [+ Mesh_R], маркеры Socket / Anchor_*)
##   res://data/body/parts/<id>.tres         — PartDef деталей
##   res://data/body/blueprints/<id>.tres    — пресеты тела (BodyBlueprint): human, spider, long_arm, big_arm, legless, junk [, flail]
##   res://scenes/body/modular_doll.tscn     — ModularDoll с чертежом human (Match.respawn_doll пересоздаёт по scene_file_path)
##   res://scenes/body/presets/<id>.tscn     — та же кукла с другими чертежами (смена пресета = respawn с другим scene_file_path)
## Запуск: cd godot && godot --headless --path . -s res://tools/build_body_parts.gd   (GLB уже импортированы: godot --headless --import)
##
## Детали куклы v3 (wood_*) повторяют тела tools/build_doll_scene.gd один в один: формы, массы из tuning.gd, меши
## assets/models/heroes/mannequin_v3/light/ (правые — Mesh_R из *_R.glb, ModularDoll берёт его на зеркальном якоре), точка сустава =
## origin GLB. Детали Свалки (junk_*) — меши assets/models/scrap/bits/ (tools/blender/scrap_bodies.py, origin = центр габарита),
## коллизии — капсулы/боксы по габариту, свои массы (легче куклы v3).
##
## Соглашения маркеров (BODY_CRAFT.md §1): Socket — точка крепления детали к родителю, −Y = куда деталь растёт; Anchor_<имя> — точка
## сустава ребёнка, −Y = куда он вырастет. Метаданные якоря:
##   accepts        PackedStringArray видов детали;
##   joint_group    группа мышц сустава (Tuning.MUSCLE_GROUPS) или "auto" (универсальная конечность хлама, BodyBlueprint.AUTO_NEXT);
##   rest_deg       угол покоя, градусы наружу для ЛЕВОЙ стороны, от направления якоря (−Y); mirror = true — правая сторона;
##   rest_from_pose true — угол покоя берётся из Tuning.POSE[группа] во время игры (rest_deg — значение на момент сборки);
##   limit_deg      (необяз.) Vector2 лимитов сустава в той же конвенции; иначе — ModularDoll.JOINT_LIMITS[группа] (= doll.tscn).
## Autoload в режиме -s недоступен, поэтому tuning.gd грузится как ресурс (как в build_doll_scene.gd).
extends SceneTree

const PARTS_SCENE_DIR := "res://scenes/body/parts/"
const PARTS_DATA_DIR := "res://data/body/parts/"
const BLUEPRINT_DIR := "res://data/body/blueprints/"
const PRESET_DIR := "res://scenes/body/presets/"
const MODULAR_SCENE := "res://scenes/body/modular_doll.tscn"
const MODULAR_SCRIPT := "res://scripts/body/modular_doll.gd"
const PART_DEF_SCRIPT := "res://scripts/body/part_def.gd"
const BLUEPRINT_SCRIPT := "res://scripts/body/body_blueprint.gd"
const WOOD := "res://assets/models/heroes/mannequin_v3/light/"
const BITS := "res://assets/models/scrap/bits/"

# Размеры и высоты суставов манекена v3 — как в tools/build_doll_scene.gd (D, *_Y): держать совпадающими, tests/body_probe сверяет.
const D := {
	"head_w": 0.24, "head_h": 0.30, "torso_w": 0.36, "torso_h": 0.52, "torso_d": 0.22,
	"ua": 0.30, "la": 0.27, "hand": 0.18, "hand_w": 0.07, "hand_d": 0.07,
	"ul": 0.42, "ll": 0.40, "foot": 0.25, "foot_h": 0.08, "foot_w": 0.10,
	"ua_r": 0.052, "la_r": 0.044, "ul_r": 0.070, "ll_r": 0.056,
	"shoulder_x": 0.22, "hip_x": 0.10,
}
const NECK_Y := 1.47
const SHOULDER_Y := 1.43
const HIP_Y := 0.91
const ANKLE_Y := 0.09
const TORSO_C_Y := 1.17
const HEAD_C_Y := 1.625

# Якоря-«универсалы» (CONCEPT_V2 §5: «здесь находится универсальный физический anchor»): любой вид, кроме головы и ядра.
const ANY_LIMB := ["limb", "hand", "foot", "joint", "chain", "weapon_head", "handle", "mod", "plate"]
# Боковые якоря торса («пауки»): растут наружу-вниз под 30° к горизонту (−Y повёрнут на 60° от «вниз»), своя вилка лимитов.
const SIDE_ROT_DEG := 60.0
const SIDE_LIMITS := Vector2(-60, 80)

# Тяжёлая рука (CONCEPT_V2 §6 «Heavy Arm 18»): меши плеча/предплечья/кисти v3, толще и длиннее.
const BIG_ARM_SCALE := Vector3(1.45, 1.4, 1.45)
const BIG_HAND_SCALE := Vector3(1.6, 1.35, 1.6)

# Массы деталей, которых нет в Tuning.MASS (кг). Хук §6: перенести в tuning.gd (правило 3 ASSET_PIPELINE), tuning.gd сейчас не наш.
const EXTRA_MASS := {
	"wood_big_upper_arm": 4.0, "wood_big_lower_arm": 3.0, "wood_big_hand": 1.2,
	# хлам легче клёна: кукла из хлама 26 кг против 40 — разгон ×1.5 при фиксированной тяге Ядра, отлетает дальше
	"junk_torso": 9.0, "junk_head": 2.5, "junk_upper_limb": 1.8, "junk_lower_limb": 1.2, "junk_hand": 0.35, "junk_foot": 0.7,
}

# Энергия (CONCEPT_V2 §6: рука 10, тяжёлая рука 18, нога 15, доп. сустав 5, металлическая голова 20; остальное — здесь).
const ENERGY := {
	"wood_torso": 0, "wood_head": 8,
	"wood_upper_arm": 4, "wood_lower_arm": 4, "wood_hand": 2,           # рука 10
	"wood_upper_leg": 6, "wood_lower_leg": 6, "wood_foot": 3,           # нога 15
	"wood_big_upper_arm": 7, "wood_big_lower_arm": 7, "wood_big_hand": 4,  # тяжёлая рука 18
	"junk_torso": 0, "junk_head": 5,
	"junk_upper_limb": 3, "junk_lower_limb": 3, "junk_hand": 1, "junk_foot": 2,   # рука хлама 7, нога 8
}

var T: Node
var phys_mat: PhysicsMaterial
var built: Array = []      # id деталей, собранных в этом запуске


func _init() -> void:
	T = load("res://scripts/tuning.gd").new()
	phys_mat = PhysicsMaterial.new()
	phys_mat.friction = 0.6   # как build_doll_scene.gd (FEEL_TARGET §4)
	phys_mat.bounce = 0.05
	for dir in [PARTS_SCENE_DIR, PARTS_DATA_DIR, BLUEPRINT_DIR, PRESET_DIR]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var ok := _build_wood() and _build_junk() and _build_blueprints()
	T.free()
	quit(0 if ok else 1)


# --- детали куклы v3 ---

func _build_wood() -> bool:
	var sx: float = D["shoulder_x"]
	var hx: float = D["hip_x"]
	var ok := true

	var b := _body("Torso", "core")
	_box(b, Vector3(D["torso_w"], D["torso_h"], D["torso_d"]))
	_mesh(b, WOOD + "Torso.glb", Vector3.ZERO)
	_anchor(b, "Anchor_Neck", Vector3(0, NECK_Y - TORSO_C_Y, 0), 180.0, ["head"], "Neck", false, true)
	for s in [["L", 1.0, false], ["R", -1.0, true]]:
		var k: float = s[1]
		_anchor(b, "Anchor_Shoulder_" + s[0], Vector3(sx * k, SHOULDER_Y - TORSO_C_Y, 0), 0.0, ANY_LIMB, "Shoulder", s[2], true)
		_anchor(b, "Anchor_Hip_" + s[0], Vector3(hx * k, HIP_Y - TORSO_C_Y, 0), 0.0, ANY_LIMB, "Hip", s[2], true)
	for s in [["L", 1.0, false], ["R", -1.0, true]]:
		var k: float = s[1]
		_anchor(b, "Anchor_Side_" + s[0], Vector3(D["torso_w"] / 2.0 * k, 0.0, 0), SIDE_ROT_DEG * k, ANY_LIMB, "Hip", s[2], false,
			0.0, SIDE_LIMITS)
	ok = ok and _save_part(b, "wood_torso", "Ядро-торс (клён)", float(T.MASS["Torso"]))

	b = _body("Head", "head")
	_capsule(b, D["head_w"] / 2.0, D["head_h"])
	var neck := Vector3(0, NECK_Y - HEAD_C_Y, 0)
	_mesh(b, WOOD + "Head.glb", neck)
	_socket(b, neck, 180.0)
	ok = ok and _save_part(b, "wood_head", "Голова-яйцо (клён)", float(T.MASS["Head"]))

	# конечности: [id, title, prefix, kind, radius|box, length, mass key, GLB, дистальный якорь, группа якоря, scale]
	var limbs := [
		["wood_upper_arm", "Плечо (клён)", "UpperArm", D["ua_r"], D["ua"], "UpperArm", "Anchor_Elbow", "Elbow", Vector3.ONE],
		["wood_lower_arm", "Предплечье (клён)", "LowerArm", D["la_r"], D["la"], "LowerArm", "Anchor_Wrist", "Wrist", Vector3.ONE],
		["wood_upper_leg", "Бедро (клён)", "UpperLeg", D["ul_r"], D["ul"], "UpperLeg", "Anchor_Knee", "Knee", Vector3.ONE],
		["wood_lower_leg", "Голень (клён)", "LowerLeg", D["ll_r"], D["ll"], "LowerLeg", "Anchor_Ankle", "Ankle", Vector3.ONE],
		["wood_big_upper_arm", "Тяжёлое плечо (клён)", "UpperArm", D["ua_r"] * BIG_ARM_SCALE.x, D["ua"] * BIG_ARM_SCALE.y, "UpperArm",
			"Anchor_Elbow", "Elbow", BIG_ARM_SCALE],
		["wood_big_lower_arm", "Тяжёлое предплечье (клён)", "LowerArm", D["la_r"] * BIG_ARM_SCALE.x, D["la"] * BIG_ARM_SCALE.y, "LowerArm",
			"Anchor_Wrist", "Wrist", BIG_ARM_SCALE],
	]
	for L in limbs:
		var r: float = L[3]
		var length_: float = L[4]
		b = _body(L[2], "limb")
		_capsule(b, r, length_)
		var top := Vector3(0, length_ / 2.0, 0)
		var sc: Vector3 = L[8]
		_mesh(b, WOOD + L[5] + "_L.glb", top, sc)
		_mesh(b, WOOD + L[5] + "_R.glb", top, sc, "Mesh_R")
		_socket(b, top)
		_anchor(b, L[6], Vector3(0, -length_ / 2.0, 0), 0.0, ANY_LIMB, L[7], false, true)
		var mass: float = float(EXTRA_MASS[L[0]]) if EXTRA_MASS.has(L[0]) else float(T.MASS[L[5]])
		ok = ok and _save_part(b, L[0], L[1], mass)

	for H in [["wood_hand", "Кисть (клён)", Vector3.ONE], ["wood_big_hand", "Кулак-колотушка (клён)", BIG_HAND_SCALE]]:
		var sc: Vector3 = H[2]
		var size := Vector3(D["hand_w"] * sc.x, D["hand"] * sc.y, D["hand_d"] * sc.z)
		b = _body("Hand", "hand")
		_box(b, size)
		var top := Vector3(0, size.y / 2.0, 0)
		_mesh(b, WOOD + "Hand_L.glb", top, sc)
		_mesh(b, WOOD + "Hand_R.glb", top, sc, "Mesh_R")
		_socket(b, top)
		var mass: float = float(EXTRA_MASS[H[0]]) if EXTRA_MASS.has(H[0]) else float(T.MASS["Hand"])
		ok = ok and _save_part(b, H[0], H[1], mass)

	# стопа вытянута к камере (+Z): центр (0, foot_h/2, 0.055) от пола, сустав — лодыжка (ANKLE_Y) над центром пятки
	b = _body("Foot", "foot")
	_box(b, Vector3(D["foot_w"], D["foot_h"], D["foot"]))
	var ankle := Vector3(0, ANKLE_Y - D["foot_h"] / 2.0, -0.055)
	_mesh(b, WOOD + "Foot_L.glb", ankle)
	_mesh(b, WOOD + "Foot_R.glb", ankle, Vector3.ONE, "Mesh_R")
	_socket(b, ankle)
	ok = ok and _save_part(b, "wood_foot", "Стопа (клён)", float(T.MASS["Foot"]))
	return ok


# --- детали Свалки (assets/models/scrap/bits, scrap_bodies.py: origin = центр габарита; шар сустава — у верхнего конца) ---

func _build_junk() -> bool:
	var ok := true
	# торс-бочонок 0.48 × 0.50 × 0.27 (с шарами плеч): гнёзда плеч x ±0.19 на y +0.18, горловина y +0.25, низ y −0.25 (радиус 0.13)
	var b := _body("Torso", "core")
	_box(b, Vector3(0.40, 0.50, 0.26))
	_mesh(b, BITS + "Doll_Torso_Shell.glb", Vector3.ZERO)
	_anchor(b, "Anchor_Neck", Vector3(0, 0.25, 0), 180.0, ["head"], "Neck", false, true)
	for s in [["L", 1.0, false], ["R", -1.0, true]]:
		var k: float = s[1]
		_anchor(b, "Anchor_Shoulder_" + s[0], Vector3(0.21 * k, 0.18, 0), 0.0, ANY_LIMB, "Shoulder", s[2], true)
		_anchor(b, "Anchor_Hip_" + s[0], Vector3(0.08 * k, -0.23, 0), 0.0, ANY_LIMB, "Hip", s[2], true)
		_anchor(b, "Anchor_Side_" + s[0], Vector3(0.20 * k, 0.0, 0), SIDE_ROT_DEG * k, ANY_LIMB, "Hip", s[2], false, 0.0, SIDE_LIMITS)
	ok = ok and _save_part(b, "junk_torso", "Ядро-бочонок (хлам)", EXTRA_MASS["junk_torso"], "junk_torso")

	# головы ⌀0.235 × 0.29 с колышком шеи внизу: шар до y −0.105, колышек до −0.146 — сустав в колышке, y −0.13
	for h in [["junk_head_sad", "Doll_Head_Sad", "Грустная голова (хлам)"], ["junk_head_scared", "Doll_Head_Scared", "Испуганная голова (хлам)"],
			["junk_head_cracked", "Doll_Head_Cracked", "Треснувшая голова (хлам)"]]:
		b = _body("Head", "head")
		_capsule(b, 0.117, 0.29)
		_mesh(b, BITS + h[1] + ".glb", Vector3.ZERO)
		_socket(b, Vector3(0, -0.13, 0), 180.0)
		ok = ok and _save_part(b, h[0], h[2], EXTRA_MASS["junk_head"], "junk_head")

	# сегменты конечности (ось вдоль Y, шар сустава сверху): Upper 0.116 × 0.49, центр шара y +0.187; Lower 0.096 × 0.435, шар +0.169.
	# Дистальный якорь чуть выше торца: шар следующего сегмента садится в полый торец. Группа "auto": рука или нога — по месту.
	for L in [["junk_upper_limb", "Doll_Limb_Upper", "Сегмент конечности (хлам)", 0.056, 0.49, 0.187, -0.225],
			["junk_lower_limb", "Doll_Limb_Lower", "Тонкий сегмент (хлам)", 0.047, 0.435, 0.169, -0.205]]:
		b = _body("UpperArm" if L[0] == "junk_upper_limb" else "LowerArm", "limb")
		_capsule(b, L[3], L[4])
		_mesh(b, BITS + L[1] + ".glb", Vector3.ZERO)
		_socket(b, Vector3(0, L[5], 0))
		_anchor(b, "Anchor_End", Vector3(0, L[6], 0), 0.0, ANY_LIMB, "auto", false, true)
		ok = ok and _save_part(b, L[0], L[2], EXTRA_MASS[L[0]])

	# кисть-варежка 0.114 × 0.203 × 0.083: шар запястья (r 0.028) наверху — центр y +0.074
	b = _body("Hand", "hand")
	_box(b, Vector3(0.10, 0.20, 0.08))
	_mesh(b, BITS + "Doll_Hand.glb", Vector3.ZERO)
	_socket(b, Vector3(0, 0.074, 0))
	ok = ok and _save_part(b, "junk_hand", "Кисть-варежка (хлам)", EXTRA_MASS["junk_hand"])

	# стопа-клин 0.09 × 0.127 × 0.243, носок к камере: шар щиколотки y +0.032, z −0.072 (над пяткой)
	b = _body("Foot", "foot")
	_box(b, Vector3(0.09, 0.127, 0.24))
	_mesh(b, BITS + "Doll_Foot.glb", Vector3.ZERO)
	_socket(b, Vector3(0, 0.032, -0.072))
	ok = ok and _save_part(b, "junk_foot", "Стопа-клин (хлам)", EXTRA_MASS["junk_foot"])
	return ok


# --- пресеты тела (BODY_CRAFT.md §2) ---

## Узел чертежа. rest — переопределение угла покоя (NAN — по якорю), name — явное имя тела.
func _n(uid: String, part: String, parent: String = "", anchor: String = "", name: String = "", rest: float = NAN) -> Dictionary:
	var n := {"uid": uid, "part": part, "parent": parent, "anchor": anchor}
	if name != "":
		n["name"] = name
	if not is_nan(rest):
		n["rest_deg"] = rest
	return n


## Рука плечо → предплечье → кисть от якоря anchor ядра T; names — явные имена [плечо, предплечье, кисть] или пусто.
func _arm(out: Array, uids: String, anchor: String, names: Array = [], pre: String = "wood", rest: float = NAN) -> void:
	var parts := ["%s_upper_arm" % pre, "%s_lower_arm" % pre, "%s_hand" % pre]
	var anchors := [anchor, "Anchor_Elbow", "Anchor_Wrist"]
	if pre == "junk":
		parts = ["junk_upper_limb", "junk_lower_limb", "junk_hand"]
		anchors = [anchor, "Anchor_End", "Anchor_End"]
	var parent := "T"
	for i in range(3):
		out.append(_n(uids[i], parts[i], parent, anchors[i], names[i] if names.size() > i else "", rest if i == 0 else NAN))
		parent = uids[i]


## Нога бедро → голень → стопа; rest/knee — углы покоя бедра и колена (NAN — по якорю).
func _leg(out: Array, uids: String, anchor: String, names: Array = [], pre: String = "wood", rest: float = NAN, knee: float = NAN) -> void:
	var parts := ["wood_upper_leg", "wood_lower_leg", "wood_foot"]
	var anchors := [anchor, "Anchor_Knee", "Anchor_Ankle"]
	if pre == "junk":
		parts = ["junk_upper_limb", "junk_lower_limb", "junk_foot"]
		anchors = [anchor, "Anchor_End", "Anchor_End"]
	var parent := "T"
	for i in range(3):
		var r := rest if i == 0 else (knee if i == 1 else NAN)
		out.append(_n(uids[i], parts[i], parent, anchors[i], names[i] if names.size() > i else "", r))
		parent = uids[i]


func _build_blueprints() -> bool:
	var ok := true
	var hum_l := ["UpperArm_L", "LowerArm_L", "Hand_L"]
	var hum_r := ["UpperArm_R", "LowerArm_R", "Hand_R"]
	var leg_l := ["UpperLeg_L", "LowerLeg_L", "Foot_L"]
	var leg_r := ["UpperLeg_R", "LowerLeg_R", "Foot_R"]

	# human — регресс-эталон: имена тел и суставов, порядок узлов и углы как у doll.tscn
	var n: Array = [_n("T", "wood_torso", "", "", "Torso"), _n("H", "wood_head", "T", "Anchor_Neck", "Head")]
	_arm(n, "123", "Anchor_Shoulder_L", hum_l)
	_leg(n, "456", "Anchor_Hip_L", leg_l)
	_arm(n, "789", "Anchor_Shoulder_R", hum_r)
	_leg(n, "ABC", "Anchor_Hip_R", leg_r)
	ok = ok and _save_blueprint("human", "Человек (кукла v3)", n, ["9"])

	# spider — 6 ног: бёдра, бока, плечи (CONCEPT_V2 §5). Рук нет: управляемая деталь — стопа правой «плечевой» ноги.
	n = [_n("T", "wood_torso"), _n("H", "wood_head", "T", "Anchor_Neck")]
	_leg(n, "123", "Anchor_Hip_L", [], "wood", 22.0, 15.0)
	_leg(n, "456", "Anchor_Hip_R", [], "wood", 22.0, 15.0)
	_leg(n, "789", "Anchor_Side_L", [], "wood", NAN, 20.0)
	_leg(n, "ABC", "Anchor_Side_R", [], "wood", NAN, 20.0)
	_leg(n, "DEF", "Anchor_Shoulder_L", [], "wood", 110.0, 10.0)
	_leg(n, "GIJ", "Anchor_Shoulder_R", [], "wood", 110.0, 10.0)
	ok = ok and _save_blueprint("spider", "Паук: шесть ног", n, ["J"])

	# long_arm — рука на руке (CONCEPT_V2 §8 «длинная рука → длинная рука»): плечо → предплечье → плечо → предплечье → кисть справа.
	# Средний сустав — якорь запястья (группа Wrist, k 5): вторая половина руки болтается, как кистень.
	n = [_n("T", "wood_torso", "", "", "Torso"), _n("H", "wood_head", "T", "Anchor_Neck", "Head")]
	_arm(n, "123", "Anchor_Shoulder_L", hum_l)
	_leg(n, "456", "Anchor_Hip_L", leg_l)
	n.append(_n("7", "wood_upper_arm", "T", "Anchor_Shoulder_R", "UpperArm_R"))
	n.append(_n("8", "wood_lower_arm", "7", "Anchor_Elbow", "LowerArm_R"))
	n.append(_n("D", "wood_upper_arm", "8", "Anchor_Wrist"))
	n.append(_n("E", "wood_lower_arm", "D", "Anchor_Elbow"))
	n.append(_n("9", "wood_hand", "E", "Anchor_Wrist", "Hand_R"))
	_leg(n, "ABC", "Anchor_Hip_R", leg_r)
	ok = ok and _save_blueprint("long_arm", "Длинная рука", n, ["9"])

	# big_arm — правая тяжёлая рука (18), левая короткая: предплечье с кистью прямо на плече
	n = [_n("T", "wood_torso", "", "", "Torso"), _n("H", "wood_head", "T", "Anchor_Neck", "Head")]
	n.append(_n("2", "wood_lower_arm", "T", "Anchor_Shoulder_L", "LowerArm_L"))
	n.append(_n("3", "wood_hand", "2", "Anchor_Wrist", "Hand_L"))
	_leg(n, "456", "Anchor_Hip_L", leg_l)
	n.append(_n("7", "wood_big_upper_arm", "T", "Anchor_Shoulder_R", "UpperArm_R"))
	n.append(_n("8", "wood_big_lower_arm", "7", "Anchor_Elbow", "LowerArm_R"))
	n.append(_n("9", "wood_big_hand", "8", "Anchor_Wrist", "Hand_R"))
	_leg(n, "ABC", "Anchor_Hip_R", leg_r)
	ok = ok and _save_blueprint("big_arm", "Большая рука", n, ["9"])

	# legless — без ног, 4 руки: плечи (Hand_L / Hand_R держат оружие) и бёдра
	n = [_n("T", "wood_torso", "", "", "Torso"), _n("H", "wood_head", "T", "Anchor_Neck", "Head")]
	_arm(n, "123", "Anchor_Shoulder_L", hum_l)
	_arm(n, "456", "Anchor_Hip_L", [], "wood", 35.0)
	_arm(n, "789", "Anchor_Shoulder_R", hum_r)
	_arm(n, "ABC", "Anchor_Hip_R", [], "wood", 35.0)
	ok = ok and _save_blueprint("legless", "Безногий: четыре руки", n, ["9"])

	# junk — всё из хлама Свалки: торс-бочонок, грустная голова, универсальные сегменты (суставы "auto" → как у человека)
	n = [_n("T", "junk_torso", "", "", "Torso"), _n("H", "junk_head_sad", "T", "Anchor_Neck", "Head")]
	_arm(n, "123", "Anchor_Shoulder_L", hum_l, "junk")
	_leg(n, "456", "Anchor_Hip_L", leg_l, "junk")
	_arm(n, "789", "Anchor_Shoulder_R", hum_r, "junk")
	_leg(n, "ABC", "Anchor_Hip_R", leg_r, "junk")
	ok = ok and _save_blueprint("junk", "Кукла из хлама", n, ["9"])

	# flail — детали параллельного агента (scenes/body/parts, data/body/parts: цепь chain_segment, шар булавы head_mace_ball — fixed):
	# правое предплечье → цепь (сустав запястья) → цепь (свободный шарнир) → шар, слитый со второй цепью. Кисти справа нет —
	# управляемая деталь (рука мышью) — предплечье: им раскручивается кистень.
	var chain := _find_part(["chain_segment", "chain_link", "chain"])
	var ball := _find_part(["head_mace_ball", "iron_ball_fist"])
	if chain != "" and ball != "":
		var end := _first_anchor(chain)
		n = [_n("T", "wood_torso", "", "", "Torso"), _n("H", "wood_head", "T", "Anchor_Neck", "Head")]
		_arm(n, "123", "Anchor_Shoulder_L", hum_l)
		_leg(n, "456", "Anchor_Hip_L", leg_l)
		n.append(_n("7", "wood_upper_arm", "T", "Anchor_Shoulder_R", "UpperArm_R"))
		n.append(_n("8", "wood_lower_arm", "7", "Anchor_Elbow", "LowerArm_R"))
		n.append(_n("D", chain, "8", "Anchor_Wrist"))
		n.append(_n("E", chain, "D", end))
		n.append(_n("9", ball, "E", end))
		_leg(n, "ABC", "Anchor_Hip_R", leg_r)
		ok = ok and _save_blueprint("flail", "Кистень: рука → цепь → булава", n, ["8"])
	else:
		print("flail: нет деталей цепи/булавы (chain=%s, ball=%s) — пресет пропущен" % [chain, ball])
	return ok


func _find_part(ids: Array) -> String:
	for id in ids:
		if ResourceLoader.exists(PARTS_DATA_DIR + String(id) + ".tres"):
			return String(id)
	return ""


func _first_anchor(part_id: String) -> String:
	var d: Resource = load(PARTS_DATA_DIR + part_id + ".tres")
	var ps: PackedScene = d.get("scene")
	var inst := ps.instantiate()
	var out := ""
	for c in inst.get_children():
		if c is Marker3D and String(c.name).begins_with("Anchor_"):
			out = String(c.name)
			break
	inst.free()
	return out


func _save_blueprint(id: String, title: String, nodes: Array, control: Array) -> bool:
	var bp: Resource = load(BLUEPRINT_SCRIPT).new()
	var typed: Array[Dictionary] = []
	for n in nodes:
		typed.append(n)
	bp.set("id", id)
	bp.set("title", title)
	bp.set("energy_budget", 100)
	bp.set("nodes", typed)
	bp.set("control", PackedStringArray(control))
	var path := BLUEPRINT_DIR + id + ".tres"
	var errors: PackedStringArray = bp.call("validate")
	if not errors.is_empty():
		push_error("blueprint %s: %s" % [id, "; ".join(errors)])
		return false
	var err := ResourceSaver.save(bp, path)
	if err != OK:
		push_error("save %s failed: %d" % [path, err])
		return false
	bp = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	# сцена куклы с этим чертежом: корень ModularDoll (Match.respawn_doll пересоздаёт по scene_file_path)
	var root := Node3D.new()
	root.name = "ModularDoll"
	root.set_script(load(MODULAR_SCRIPT))
	if root.get_script() == null:
		push_error("modular_doll.gd не компилируется в режиме -s")
		root.free()
		return false
	root.set("blueprint", bp)
	var ps := PackedScene.new()
	ps.pack(root)
	var out := MODULAR_SCENE if id == "human" else PRESET_DIR + id + ".tscn"
	err = ResourceSaver.save(ps, out)
	root.free()
	if err != OK:
		push_error("save %s failed: %d" % [out, err])
		return false
	print("blueprint %-9s energy %3d / 100, mass %5.1f kg, %2d parts → %s" % [id, bp.call("energy_used"), bp.call("total_mass"), nodes.size(), out])
	return true


# --- узлы деталей ---

func _body(prefix: String, kind: String) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.name = prefix
	b.axis_lock_linear_z = true
	b.axis_lock_angular_x = true
	b.axis_lock_angular_y = true
	b.continuous_cd = true
	b.can_sleep = false
	var core := kind == "core" or kind == "head"
	# как Tuning.doll_linear_damp / doll_angular_damp (ядро — голова и торс); Doll._ready ставит то же по имени тела
	b.linear_damp = T.DOLL_LINEAR_DAMP if core else T.DOLL_LIMB_LINEAR_DAMP
	b.angular_damp = T.ANGULAR_DAMP if core else T.DOLL_LIMB_ANGULAR_DAMP
	b.physics_material_override = phys_mat
	b.set_meta("kind", kind)
	return b


func _capsule(b: RigidBody3D, r: float, h: float, pos: Vector3 = Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var s := CapsuleShape3D.new()
	s.radius = r
	s.height = max(h, r * 2.0)
	cs.shape = s
	cs.position = pos
	b.add_child(cs)


func _box(b: RigidBody3D, size: Vector3, pos: Vector3 = Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	cs.position = pos
	b.add_child(cs)


## Меш детали — инстанс GLB (meta rig_mesh: Doll прячет, если надет скин). node_name "Mesh_R" — меш правой стороны (скрыт;
## ModularDoll берёт его вместо Mesh на зеркальном якоре, иначе отражает Mesh по X).
func _mesh(b: RigidBody3D, glb: String, pos: Vector3, scale: Vector3 = Vector3.ONE, node_name: String = "Mesh") -> void:
	var ps: PackedScene = load(glb)
	if ps == null:
		push_error("missing mesh " + glb)
		return
	var mi: Node3D = ps.instantiate()
	mi.name = node_name
	mi.position = pos
	mi.scale = scale
	mi.set_meta("rig_mesh", true)
	if node_name == "Mesh_R":
		mi.visible = false
	b.add_child(mi)


func _socket(b: RigidBody3D, pos: Vector3, rot_deg: float = 0.0) -> void:
	var m := Marker3D.new()
	m.name = "Socket"
	m.position = pos
	m.rotation.z = deg_to_rad(rot_deg)
	b.add_child(m)


## Якорь: rot_deg — поворот −Y от «вниз» (180 — ребёнок растёт вверх), rest — угол покоя (rest_from_pose → Tuning.POSE[группа]).
func _anchor(b: RigidBody3D, name: String, pos: Vector3, rot_deg: float, accepts: Array, group: String, mirror: bool,
		rest_from_pose: bool, rest: float = 0.0, limits: Variant = null) -> void:
	var m := Marker3D.new()
	m.name = name
	m.position = pos
	m.rotation.z = deg_to_rad(rot_deg)
	m.set_meta("accepts", PackedStringArray(accepts))
	m.set_meta("joint_group", group)
	var r := rest
	if rest_from_pose and T.POSE.has(group):
		r = float(T.POSE[group])
	m.set_meta("rest_deg", r)
	m.set_meta("mirror", mirror)
	m.set_meta("rest_from_pose", rest_from_pose)
	if limits != null:
		m.set_meta("limit_deg", limits)
	b.add_child(m)


## Упаковать деталь в scenes/body/parts/<id>.tscn и записать PartDef data/body/parts/<id>.tres. energy_key — ключ ENERGY (по умолчанию id).
func _save_part(b: RigidBody3D, id: String, title: String, mass: float, energy_key: String = "") -> bool:
	b.mass = mass
	_set_owner(b, b)
	var ps := PackedScene.new()
	var err := ps.pack(b)
	var scene_path := PARTS_SCENE_DIR + id + ".tscn"
	if err == OK:
		err = ResourceSaver.save(ps, scene_path)
	var prefix := String(b.name)
	var kind := String(b.get_meta("kind"))
	b.free()
	if err != OK:
		push_error("save %s failed: %d" % [scene_path, err])
		return false
	var d: Resource = load(PART_DEF_SCRIPT).new()
	d.set("id", id)
	d.set("title", title)
	d.set("kind", kind)
	d.set("scene", ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_REPLACE))
	d.set("mass", mass)
	d.set("energy", int(ENERGY[energy_key if energy_key != "" else id]))
	d.set("attach", "joint")
	d.set("body_mult", float(T.BODY_MULT.get(prefix, 1.0)))
	d.set("material", "wood")
	d.set("name_prefix", prefix)
	var data_path := PARTS_DATA_DIR + id + ".tres"
	err = ResourceSaver.save(d, data_path)
	if err != OK:
		push_error("save %s failed: %d" % [data_path, err])
		return false
	ResourceLoader.load(data_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	built.append(id)
	print("part %-20s %-6s %-9s %5.2f kg  energy %2d" % [id, kind, prefix, mass, d.get("energy")])
	return true


## owner для всех узлов детали; у инстансов GLB — только корень инстанса.
func _set_owner(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		if c.scene_file_path == "":
			_set_owner(c, root)
