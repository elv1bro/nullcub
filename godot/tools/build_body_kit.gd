## Builder кита тела v2 (docs/plan-demo/BODY_KIT.md §2–§4, §3.5; ASSET_PIPELINE.md правило 2). Запуск из корня репозитория:
##   python3 godot/tools/gen_kit_face.py                        (один раз / при смене PBR: лицо и копии текстур 512²)
##   <GL> --headless --path godot --import                      (glb кита: Blender body_kit.py -- --export)
##   <GL> --headless --path godot -s res://tools/build_body_kit.gd
##   <GL> --headless --path godot --import                      (пост-импорт tools/kit_import.gd ставит материалы кита в glb)
## Вход — таблица assets/models/body/kit/kit_catalog.json (пишет экспорт Blender: id, kind, title, mass, energy, attach, body_mult
## (только у fixed-видов; у деталей со своим телом PartDef.body_mult = Tuning.BODY_MULT по name_prefix, §3.3), hit_mult (только у
## видов со своим телом, если задан; нет — 1.0), weapon_mult, name_prefix, base_mat, material, connector, empties, materials;
## kind "connector" — визуал шарнира, connector_type).
## Сцены деталей — начало тела в Socket (§1), кроме кисти: у неё начало — центр форм, Socket выше (как wood_hand: хват
## WeaponPickup / ArmAssist (0, −0.03, 0) — в ладони). У конечностей — маркер Grip в точке Anchor_End (хват ArmAssist).
## Builder целиком табличный и перезапускаемый: перезаписывает только свои файлы (id "kit_*"), чужие не трогает. Пишет:
##   assets/materials/kit/<Роль>.tres      StandardMaterial3D, resource_name = роль (таблица MATS = KIT_MATS / MAT_DEFS / FLAT);
##   data/body/materials/<id>.tres          MaterialDef (таблица MATERIALS = BODY_KIT.md §4), surface = Base_<Mat>.tres;
##   assets/models/body/kit/*.glb.import    import_script/path = tools/kit_import.gd (материалы по ролям при импорте);
##   scenes/body/kit/<id>.tscn + data/body/parts/<id>.tres       детали из glb (§3.1) и PartDef (поля каталога);
##   scenes/body/kit/connectors/<type>.tscn                       коннекторы шарниров (§3.4): Node3D + glb, без физики;
##   scenes/body/kit/kit_human_*.tscn + data/body/parts/kit_human_*.tres   кит «Человек» на риге v3 (§3.2) + самосверка с wood_*;
##   data/body/blueprints/kit_*.tres + scenes/body/presets/kit_*.tscn     пресеты (§3.5); id "human" не пишется никогда;
##     витрина покраски (BODY_PAINT.md §4): kit_graffiti, kit_camo — узлы kit_human / kit_brawler + paint (PaintLayer.pattern с
##     постоянным seed) и stickers (трафареты «stencil:<имя>», кадр — луч по треугольникам меша детали).
## В конце — строка «=== BODY KIT BUILD === {json}» (счётчики, самосверка, предупреждения); код выхода 1, если есть ошибки.
##
## Текстуры: копии 512² с мип-мапами assets/materials/kit/tex/<папка>/*.webp (gen_kit_face.py), как CRAFT_TEX_SIZE деталей крафта.
## Исходники assets/textures/pbr/<папка>/*.png — 2048² без мип-мапов и без сжатия (~16 МБ видеопамяти на карту) — только запасной путь,
## если копии ещё не импортированы (предупреждение в сводке).
## Autoload в режиме -s недоступен: tuning.gd грузится как ресурс (константы), скрипты PartDef / MaterialDef / BodyBlueprint — по пути.
extends SceneTree

const KIT_DIR := "res://assets/models/body/kit/"
const CATALOG := KIT_DIR + "kit_catalog.json"
const IMPORT_SCRIPT := "res://tools/kit_import.gd"
const MAT_DIR := "res://assets/materials/kit/"
const TEX_DIR := MAT_DIR + "tex/"
const PBR_DIR := "res://assets/textures/pbr/"
const FACE_TEX := MAT_DIR + "face_default.png"
const MATDEF_DIR := "res://data/body/materials/"
const SCENE_DIR := "res://scenes/body/kit/"
const CONNECTOR_DIR := "res://scenes/body/kit/connectors/"
const PART_DIR := "res://data/body/parts/"
const WOOD_SCENE_DIR := "res://scenes/body/parts/"
const BLUEPRINT_DIR := "res://data/body/blueprints/"
const PRESET_DIR := "res://scenes/body/presets/"
const MODULAR_SCRIPT := "res://scripts/body/modular_doll.gd"
const PART_DEF_SCRIPT := "res://scripts/body/part_def.gd"
const MATERIAL_DEF_SCRIPT := "res://scripts/body/material_def.gd"
const BLUEPRINT_SCRIPT := "res://scripts/body/body_blueprint.gd"
## Покраска витринных пресетов (docs/plan-demo/BODY_PAINT.md §2, §4): слой краски и габарит меша детали — по пути, как прочие скрипты.
const PAINT_LAYER_SCRIPT := "res://scripts/body/paint_layer.gd"
const BODY_PAINT_SCRIPT := "res://scripts/body/body_paint.gd"

## Роль материала → StandardMaterial3D. Роли и папки — как KIT_MATS / KIT_FLAT (tools/blender/kit_common.py) и MAT_DEFS / FLAT
## (tools/blender/craft_parts.py); числа не везде те же (albedo железа, металличность ржавчины, Joint / Pin) — список расхождений
## Blender ↔ Godot в BODY_KIT.md §2. pbr — папка текстур (albedo, roughness, normal, metallic — какие есть); tint — множитель albedo,
## ЛИНЕЙНЫЙ, как в Blender (MULTIPLY) и baseColorFactor glTF → albedo_color = tint.linear_to_srgb() (может быть > 1: тёмную карту
## iron (~0.06 линейно) поднимает до ~0.3); rough — roughness_scale (roughness × карта); metal — металличность (у набора с картой
## metallic — множитель карты, по умолчанию 1.0; у flat — сама металличность); flat — плоский цвет (линейный) без текстур; alpha —
## прозрачность (TRANSPARENCY_ALPHA, стекло); glow — эмиссия (цвет, energy); swatch — плоский запасной цвет Blender (плашка MaterialDef в
## мастерской). uv1_scale = 1: в glb UV уже в тайлах (2 на метр).
## Металл (29.09, визуальная проверка): на тёмном фоне без неба (tests/body_probe, Свалка ночью) металличность 1.0 отражает пустоту —
## железо выходило чёрным. Железо и ржавчина — тёмный крашеный / кованый металл: metal 0.55, albedo поднят, читается диффузом.
const MATS := {
	"Base_Wood": {"pbr": "wood", "tint": [1.0, 0.92, 0.82], "swatch": [0.62, 0.40, 0.20]},
	"Base_Maple": {"pbr": "maple_light", "swatch": [0.60, 0.42, 0.24]},
	"Base_WoodDark": {"pbr": "wood_dark", "swatch": [0.25, 0.14, 0.07]},
	"Base_Planks": {"pbr": "wood_plank", "swatch": [0.45, 0.28, 0.14]},
	# краски — не цвета игроков (29.09, QA на Свалке; BODY_KIT.md §4): бордовая / бирюзовая / горчичная / оливковая, ΔE2000 ≥ 23
	# от каждого из Tuning.PLAYER_COLORS (прежние красная / синяя / жёлтая / зелёная совпадали с ними: ΔE 3–6)
	"Base_PaintRed": {"pbr": "paint_marks", "tint": [0.19, 0.014, 0.057], "rough": 0.75, "swatch": [0.19, 0.014, 0.057]},
	"Base_PaintBlue": {"pbr": "paint_marks", "tint": [0.016, 0.19, 0.206], "rough": 0.75, "swatch": [0.016, 0.19, 0.206]},
	"Base_PaintYellow": {"pbr": "paint_marks", "tint": [0.30, 0.176, 0.018], "rough": 0.75, "swatch": [0.30, 0.176, 0.018]},
	"Base_PaintWhite": {"pbr": "paint_marks", "tint": [0.80, 0.78, 0.72], "rough": 0.75, "swatch": [0.80, 0.78, 0.72]},
	"Base_PaintGreen": {"pbr": "paint_marks", "tint": [0.121, 0.125, 0.025], "rough": 0.75, "swatch": [0.121, 0.125, 0.025]},
	"Base_RustRed": {"pbr": "rust_painted_red", "metal": 0.6, "swatch": [0.30, 0.05, 0.03]},
	"Base_Iron": {"pbr": "iron", "tint": [3.4, 4.3, 4.3], "metal": 0.6, "swatch": [0.20, 0.20, 0.21]},
	"Base_Rust": {"pbr": "rust_metal", "tint": [1.35, 1.5, 1.6], "metal": 0.55, "swatch": [0.20, 0.11, 0.06]},
	"Base_Brass": {"pbr": "brass_worn", "metal": 0.7, "swatch": [0.50, 0.36, 0.14]},
	"Base_Bone": {"pbr": "paint_marks", "tint": [0.86, 0.76, 0.56], "swatch": [0.86, 0.76, 0.56]},
	"Base_Pink": {"pbr": "paint_marks", "tint": [0.85, 0.30, 0.42], "rough": 0.6, "swatch": [0.85, 0.30, 0.42]},
	# фурнитура: не перекрашивается (KIT_MATS, MAT_DEFS craft_parts, FLAT, KIT_FLAT)
	"Iron": {"pbr": "iron", "tint": [3.4, 4.3, 4.3], "metal": 0.6},
	"Steel": {"pbr": "iron", "tint": [4.8, 6.2, 6.2], "metal": 0.65, "rough": 0.9},
	"Brass": {"pbr": "brass_worn", "metal": 0.7},
	"Bone": {"pbr": "paint_marks", "tint": [0.86, 0.76, 0.56]},
	"Wood": {"pbr": "maple_light", "tint": [1.0, 0.97, 0.92]},
	"WoodDark": {"pbr": "walnut_dark", "tint": [1.0, 0.98, 0.96]},
	"Rust": {"pbr": "rust_metal", "tint": [1.35, 1.5, 1.6], "metal": 0.55},
	"RustDark": {"pbr": "rust_metal", "tint": [0.8, 0.8, 0.85], "metal": 0.55},
	"RustRed": {"pbr": "rust_painted_red", "metal": 0.6},
	"Rope": {"pbr": "rope"},
	"Rubber": {"flat": [0.03, 0.028, 0.027], "rough": 0.85},
	"Screen": {"flat": [0.01, 0.012, 0.014], "rough": 0.2},
	# закопчённое стекло (фонарь): янтарное, полупрозрачное — сквозь него виден огарок (KIT_FLAT Glass + GLASS_ALPHA kit_common.py)
	"Glass": {"flat": [0.50, 0.30, 0.10], "rough": 0.08, "alpha": 0.38, "glow": [1.0, 0.55, 0.2], "energy": 0.2},
	"Gem": {"flat": [0.55, 0.02, 0.03], "rough": 0.12},
	"Joint": {"flat": [0.25, 0.24, 0.25], "rough": 0.5, "metal": 0.5},
	"Pin": {"flat": [0.62, 0.62, 0.64], "rough": 0.45, "metal": 0.6},
	# окошко Ядра: тёплый оранжевый с горячей серединой (блик и ACES); при energy 3 купол выгорал в белый диск (клетка, дымоход).
	# В Blender — CORE_GLOW_STRENGTH kit_common.py (AgX)
	"CoreGlow": {"flat": [0.30, 0.10, 0.02], "rough": 0.3, "glow": [1.0, 0.25, 0.03], "energy": 0.9},
	# плашка лица: нарисованное лицо «фотокарточка» (gen_kit_face.py), потом — фото игрока (этап 10)
	"Face": {"face": true, "rough": 0.55},
	# цвет игрока: светлая краска, Doll._recolor("Shirt") заменяет albedo_color цветом игрока; по умолчанию — P1 (2f6fde)
	"Shirt_Kit": {"pbr": "paint_marks", "tint": [0.028, 0.16, 0.73], "rough": 0.7},
}

## MaterialDef (BODY_KIT.md §4), порядок = MaterialDef.ORDER: [id, Base_, title, density, friction, bounce, body_mult, iron].
const MATERIALS := [
	["wood", "Wood", "Дерево", 1.0, 0.6, 0.05, 1.0, false],
	["maple", "Maple", "Клён", 1.0, 0.6, 0.05, 1.0, false],
	["wood_dark", "WoodDark", "Орех", 1.15, 0.6, 0.05, 1.05, false],
	["planks", "Planks", "Доски", 0.9, 0.65, 0.05, 1.0, false],
	# id красок прежние (чертежи, пробы), названия — по новому цвету (MATS: не цвета игроков)
	["paint_red", "PaintRed", "Бордовая краска", 1.0, 0.5, 0.05, 1.0, false],
	["paint_blue", "PaintBlue", "Бирюзовая краска", 1.0, 0.5, 0.05, 1.0, false],
	["paint_yellow", "PaintYellow", "Горчичная краска", 1.0, 0.5, 0.05, 1.0, false],
	["paint_white", "PaintWhite", "Белая краска", 1.0, 0.5, 0.05, 1.0, false],
	["paint_green", "PaintGreen", "Оливковая краска", 1.0, 0.5, 0.05, 1.0, false],
	["rust_red", "RustRed", "Крашеный лист", 1.6, 0.55, 0.1, 1.1, true],
	["iron", "Iron", "Железо", 2.2, 0.5, 0.1, 1.2, true],
	["rust", "Rust", "Ржавчина", 2.0, 0.7, 0.08, 1.15, true],
	["brass", "Brass", "Латунь", 2.4, 0.45, 0.15, 1.2, false],   # латунь не магнитится
	["bone", "Bone", "Кость", 0.9, 0.55, 0.1, 1.05, false],
	["rubber", "Pink", "Резина", 0.8, 0.9, 0.6, 0.8, false],
]

## Якоря (§3.1): метаданные выводятся из имени. ANY_LIMB = BodyBlueprint.ANY_LIMB (= build_body_parts.gd ANY_LIMB).
const ANY_LIMB := ["limb", "hand", "foot", "joint", "chain", "weapon_head", "handle", "mod", "plate"]
const OTHER_ACCEPTS := ["weapon_head", "chain", "mod"]   # прочие якоря — как build_craft_parts.gd ALL / FREE
const OTHER_GROUP := "Ankle"
const SIDE_LIMITS := Vector2(-60, 80)                     # = build_body_parts.gd SIDE_LIMITS
## Радиус шара коннектора по имени якоря (JOINT_R kit_common.py, кадр стиля) → meta joint_r; 0 — у якоря декора шара нет.
const JOINT_R := {"Neck": 0.05, "Shoulder": 0.064, "Hip": 0.076, "Side": 0.062, "End": 0.052}
## Тонкие коллизии не должны проваливаться сквозь куклу (= build_craft_parts.gd MIN_THICK).
const MIN_THICK := 0.03
## Fixed-виды (PartDef.FIXED_KINDS + детали оружия): форм может не быть — масса всё равно слита с хозяином (предупреждение).
const SHAPELESS_OK := ["deco", "armor", "weapon_head", "handle", "mod", "plate"]
## Концевые детали: якоря End у них нет (§3.1).
const END_KINDS := ["hand", "foot"]
## Якоря декора, которые кит «Человек» добавляет сверх якорей wood_* (§3.2).
const DECO_ANCHORS := ["Anchor_Deco", "Anchor_Top", "Anchor_Back"]

## Кит «Человек» под риг v3 (§3.2): [id, wood-деталь, glb, подпись].
const HUMAN := [
	["kit_human_torso", "wood_torso", "Kit_Core_Barrel", "Ядро-бочка (кит «Человек»)"],
	["kit_human_head", "wood_head", "Kit_Head_Round", "Голова-игрушка (кит «Человек»)"],
	["kit_human_upper_arm", "wood_upper_arm", "Kit_Limb_Basic_S", "Плечо (кит «Человек»)"],
	["kit_human_lower_arm", "wood_lower_arm", "Kit_Limb_Basic_LA", "Предплечье (кит «Человек»)"],
	["kit_human_hand", "wood_hand", "Kit_Hand_Mitten", "Варежка (кит «Человек»)"],
	["kit_human_upper_leg", "wood_upper_leg", "Kit_Limb_Basic_L", "Бедро (кит «Человек»)"],
	["kit_human_lower_leg", "wood_lower_leg", "Kit_Limb_Basic_LL", "Голень (кит «Человек»)"],
	["kit_human_foot", "wood_foot", "Kit_Foot_Boot", "Ботинок (кит «Человек»)"],
]

## Имена тел пресетов «человеческой» раскладки (как human / doll.tscn: DollCombat.MONITORED, Damage.body_mult_of по имени).
const ARM_L := ["UpperArm_L", "LowerArm_L", "Hand_L"]
const ARM_R := ["UpperArm_R", "LowerArm_R", "Hand_R"]
const LEG_L := ["UpperLeg_L", "LowerLeg_L", "Foot_L"]
const LEG_R := ["UpperLeg_R", "LowerLeg_R", "Foot_R"]
## Углы покоя дистальных суставов: у якорей End кита rest_deg = 0 (§3.1), поэтому локоть / колено пресетов ставятся явно,
## как Tuning.POSE у human (Elbow 10, Knee 5): кукла стоит, как человек.
const ELBOW_REST := 10.0
const KNEE_REST := 5.0

var T: Node
var catalog: Dictionary = {}
var summary := {
	"materials": 0, "material_defs": 0, "import_patched": 0, "parts": 0, "connectors": 0, "human_parts": 0, "presets": {},
	"self_check": {}, "shapeless": [], "stale": [], "warnings": [], "errors": [],
}
var _written: Dictionary = {}   # пути, записанные в этом запуске (поиск устаревших kit-файлов)


func _init() -> void:
	T = load("res://scripts/tuning.gd").new()
	for d in [MAT_DIR, MATDEF_DIR, SCENE_DIR, CONNECTOR_DIR, PART_DIR, BLUEPRINT_DIR, PRESET_DIR]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))
	if _load_catalog():
		_build_materials()
		_build_material_defs()
		_patch_imports()
		for key in catalog:
			var e: Dictionary = catalog[key]
			if String(e.get("kind", "")) == "connector":
				_build_connector(e)
			else:
				_build_part(e)
		# типы шарниров KitJoint без сцены коннектора: сустав работает, шара нет (ModularDoll._add_connector молча пропускает)
		var types: Dictionary = load("res://scripts/body/kit_joint.gd").get("TYPES")
		for t in types:
			var c := String((types[t] as Dictionary).get("connector", ""))
			if c != "" and not ResourceLoader.exists(CONNECTOR_DIR + c + ".tscn"):
				_warn("нет коннектора «%s» (KitJoint %s): в каталоге нет Kit_Joint_%s.glb" % [c, t, c.capitalize()])
		for h in HUMAN:
			_build_human_part(h)
		_build_presets()
		_find_stale()
	T.free()
	var errs: Array = summary["errors"]
	print("=== BODY KIT BUILD === " + JSON.stringify(summary))
	quit(1 if not errs.is_empty() else 0)


func _err(msg: String) -> void:
	push_error("build_body_kit: " + msg)
	(summary["errors"] as Array).append(msg)


func _warn(msg: String) -> void:
	print("build_body_kit: WARN " + msg)
	(summary["warnings"] as Array).append(msg)


func _load_catalog() -> bool:
	var f := FileAccess.open(CATALOG, FileAccess.READ)
	if f == null:
		_err("нет %s — сначала Blender body_kit.py -- --export" % CATALOG)
		return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not data is Dictionary:
		_err("%s: не JSON-объект" % CATALOG)
		return false
	var keys: Array = (data as Dictionary).keys()
	keys.sort()
	for k in keys:
		catalog[k] = data[k]
	return true


# --- материалы (§2) ---

func _build_materials() -> void:
	var fresh: Array = []   # роли, чей .tres создан этим запуском: glb, импортированные раньше, остались с плоским материалом роли
	for role in MATS:
		var d: Dictionary = MATS[role]
		if not FileAccess.file_exists(MAT_DIR + role + ".tres"):
			fresh.append(role)
		var m := StandardMaterial3D.new()
		m.resource_name = role
		m.uv1_scale = Vector3.ONE
		if d.has("pbr"):
			var folder := String(d["pbr"])
			var alb := _tex(folder, "albedo")
			if alb == null:
				_err("материал %s: нет albedo текстур «%s»" % [role, folder])
				continue
			m.albedo_texture = alb
			m.albedo_color = _srgb(d.get("tint", [1.0, 1.0, 1.0]))
			var rough := _tex(folder, "roughness")
			m.roughness = float(d.get("rough", 1.0))
			if rough != null:
				m.roughness_texture = rough
			else:
				m.roughness = 0.8 * m.roughness   # как textured_material без roughness.png
			var metal := _tex(folder, "metallic")
			if metal != null:
				m.metallic_texture = metal
				m.metallic = float(d.get("metal", 1.0))   # множитель карты
			elif d.has("metal"):
				m.metallic = float(d["metal"])
			var nrm := _tex(folder, "normal")
			if nrm != null:
				m.normal_enabled = true
				m.normal_texture = nrm
		elif d.has("face"):
			if not ResourceLoader.exists(FACE_TEX):
				_err("нет %s — python3 godot/tools/gen_kit_face.py, затем --import" % FACE_TEX)
				continue
			m.albedo_texture = load(FACE_TEX)
			m.roughness = float(d["rough"])
		else:
			m.albedo_color = _srgb(d["flat"])
			m.roughness = float(d.get("rough", 0.7))
			m.metallic = float(d.get("metal", 0.0))
		if d.has("alpha"):
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color.a = float(d["alpha"])
		if d.has("glow"):
			m.emission_enabled = true
			m.emission = _srgb(d["glow"])
			m.emission_energy_multiplier = float(d.get("energy", 1.0))
		if _save(m, MAT_DIR + role + ".tres"):
			summary["materials"] = int(summary["materials"]) + 1
	# роли из каталога, для которых нет материала: останутся плоскими материалами glb
	var missing := {}
	for key in catalog:
		for r in catalog[key].get("materials", []):
			var role := _clean(String(r))
			if not MATS.has(role):
				missing[role] = true
	for role in missing:
		_warn("роль материала «%s» из каталога без assets/materials/kit/%s.tres — останется плоской из glb" % [role, role])
	# новая роль: kit_import.gd ставит .tres только при импорте glb — уже импортированные glb с этой ролью надо переимпортировать
	for role in fresh:
		var users: Array = []
		for key in catalog:
			if (catalog[key].get("materials", []) as Array).has(role):
				users.append(String(catalog[key].get("glb", key)) + ".glb")
		if not users.is_empty():
			_warn("новая роль «%s»: touch %s, затем --import (иначе у них плоский материал glb)" % [role, ", ".join(users)])


## Карта текстуры: копия 512² (tex/<папка>/<карта>.webp), иначе исходник pbr/<папка>/<карта>.png (предупреждение), иначе null.
func _tex(folder: String, map: String) -> Texture2D:
	var p := TEX_DIR + folder + "/" + map + ".webp"
	if ResourceLoader.exists(p):
		return load(p)
	var src := PBR_DIR + folder + "/" + map + ".png"
	if ResourceLoader.exists(src):
		_warn("%s не импортирована — взят исходник %s (2048², без мип-мапов): python3 godot/tools/gen_kit_face.py, --import" % [p, src])
		return load(src)
	return null


static func _srgb(c: Array) -> Color:
	return Color(float(c[0]), float(c[1]), float(c[2])).linear_to_srgb()


func _build_material_defs() -> void:
	var script: Script = load(MATERIAL_DEF_SCRIPT)
	for row in MATERIALS:
		var id := String(row[0])
		var surf_path := MAT_DIR + "Base_" + String(row[1]) + ".tres"
		if not ResourceLoader.exists(surf_path):
			_err("MaterialDef %s: нет %s" % [id, surf_path])
			continue
		var d: Resource = script.new()
		d.set("id", id)
		d.set("title", String(row[2]))
		d.set("surface", ResourceLoader.load(surf_path, "", ResourceLoader.CACHE_MODE_REPLACE))
		d.set("swatch", _srgb(MATS["Base_" + String(row[1])]["swatch"]))
		d.set("density", float(row[3]))
		d.set("friction", float(row[4]))
		d.set("bounce", float(row[5]))
		d.set("body_mult", float(row[6]))
		d.set("iron", bool(row[7]))
		var path := MATDEF_DIR + id + ".tres"
		if _save(d, path):
			ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
			summary["material_defs"] = int(summary["material_defs"]) + 1


func _mat_row(mat_id: String) -> Array:
	for row in MATERIALS:
		if String(row[0]) == mat_id:
			return row
	return []


# --- пост-импорт: import_script/path во все glb кита (§2) ---

func _patch_imports() -> void:
	var dir := DirAccess.open(KIT_DIR)
	if dir == null:
		_err("нет папки " + KIT_DIR)
		return
	var line := "import_script/path=\"%s\"" % IMPORT_SCRIPT
	var re := RegEx.create_from_string("(?m)^import_script/path=.*$")
	for fn in dir.get_files():
		if not fn.ends_with(".glb"):
			continue
		var ipath := KIT_DIR + fn + ".import"
		var text := ""
		if FileAccess.file_exists(ipath):
			text = FileAccess.get_file_as_string(ipath)
		if text.contains(line):
			continue
		if text == "":
			text = "[remap]\n\nimporter=\"scene\"\nimporter_version=1\n\n[params]\n\n%s\n" % line   # glb ещё не импортирован
		elif re.search(text) != null:
			text = re.sub(text, line)
		elif text.contains("[params]"):
			text = text.replace("[params]\n", "[params]\n\n%s\n" % line)
		else:
			text += "\n[params]\n\n%s\n" % line
		var f := FileAccess.open(ipath, FileAccess.WRITE)
		if f == null:
			_err("не записать " + ipath)
			continue
		f.store_string(text)
		f.close()
		summary["import_patched"] = int(summary["import_patched"]) + 1


# --- детали из glb (§3.1, §3.3) ---

func _build_part(e: Dictionary) -> void:
	var id := String(e.get("id", ""))
	var kind := String(e.get("kind", ""))
	if not id.begins_with("kit_") or id == "human":
		_err("каталог: id «%s» (%s) — builder пишет только kit_*" % [id, e.get("glb", "")])
		return
	if not PackedStringArray(load(PART_DEF_SCRIPT).get("KINDS")).has(kind):
		_err("%s: неизвестный вид «%s» (PartDef.KINDS)" % [id, kind])
		return
	var glb_path := KIT_DIR + String(e["glb"]) + ".glb"
	var model := load(glb_path) as PackedScene
	if model == null:
		_err("%s: glb не импортирован: %s (--import)" % [id, glb_path])
		return
	var base_mat := String(e.get("base_mat", ""))
	if base_mat != "" and _mat_row(base_mat).is_empty():
		_err("%s: base_mat «%s» нет в MATERIALS" % [id, base_mat])
		return
	var root := RigidBody3D.new()
	root.name = _pascal(id)
	root.mass = float(e["mass"])
	_physics(root, kind, base_mat)
	root.set_meta("kind", kind)
	root.set_meta("part_id", id)

	var probe: Node = model.instantiate()
	var shapes := 0
	var socket := false
	var anchors: PackedStringArray = []
	var used := {}
	for c in probe.get_children():
		if not c is Node3D or c is MeshInstance3D:
			continue
		var n := _clean(String(c.name))
		var t: Transform3D = (c as Node3D).transform
		if n.begins_with("Shape_"):
			var cs := _shape_from(n, t)
			if cs == null:
				_err("%s: плохая пустышка формы %s" % [id, c.name])
				probe.free()
				root.free()
				return
			cs.name = _unique(String(cs.name), used)
			root.add_child(cs)
			cs.owner = root
			shapes += 1
		elif n == "Socket" or n == "Grip" or n.begins_with("Anchor_"):
			if n == "Socket" and kind == "core":
				_warn("%s: у ядра Socket не нужен (корень чертежа) — пропущен" % id)
				continue
			if n == "Anchor_End" and END_KINDS.has(kind):
				_warn("%s: у концевой детали (%s) Anchor_End не нужен — пропущен" % [id, kind])
				continue
			if used.has(n):
				_warn("%s: пустышка %s повторяется — взята первая" % [id, n])
				continue
			used[n] = true
			var mk := Marker3D.new()
			mk.name = n
			mk.transform = Transform3D(t.basis.orthonormalized(), t.origin)
			if n == "Socket":
				socket = true
			elif n.begins_with("Anchor_"):
				_anchor_meta(mk, n.substr(7))
				anchors.append(n)
			root.add_child(mk)
			mk.owner = root
	probe.free()
	if not socket and kind != "core":
		_err("%s: нет Socket в %s" % [id, glb_path])
		root.free()
		return
	if shapes == 0:
		if SHAPELESS_OK.has(kind):
			(summary["shapeless"] as Array).append(id)
			_warn("%s: в glb нет пустышек Shape_* — деталь без коллизий (масса сливается с хозяином); нужен реэкспорт Blender" % id)
		else:
			_err("%s: в glb нет пустышек Shape_*" % id)
			root.free()
			return
	for want in e.get("empties", []):
		var w := _clean(String(want))
		if (w.begins_with("Anchor_") or w == "Socket") and not used.has(w) and not (w == "Socket" and kind == "core") \
				and not (w == "Anchor_End" and END_KINDS.has(kind)):
			_warn("%s: пустышка %s есть в каталоге, но не в glb (каталог и glb разошлись — реэкспорт)" % [id, w])
	# конечность: маркер Grip в точке Anchor_End — хват ArmAssist, когда рука мышью ведёт саму конечность (предплечье с навершием
	# вместо кисти: kit_lantern, kit_king). Без него хват — начало тела = проксимальный сустав (локоть), досягаемость — одно звено
	if kind == "limb" and not used.has("Grip"):
		var end := root.get_node_or_null("Anchor_End") as Marker3D
		if end != null:
			var grip := Marker3D.new()
			grip.name = "Grip"
			grip.position = end.position
			root.add_child(grip)
			grip.owner = root
	# кисть: начало тела — центр форм, Socket выше (раскладка wood_hand, §3.1). WeaponPickup, ArmAssist и мастерская держат хват в
	# (0, −0.03, 0) тела кисти: при Socket в начале координат хват попадал в запястье — над коробкой кисти, внутри шара коннектора
	var origin_shift := Vector3.ZERO
	if kind == "hand":
		origin_shift = Vector3(0.0, -_shapes_centre_y(root), 0.0)
		for c in root.get_children():
			if c is Node3D:
				(c as Node3D).position += origin_shift

	_add_mesh(root, model, Transform3D(Basis(), origin_shift))
	var scene_path := SCENE_DIR + id + ".tscn"
	if not _pack(root, scene_path):
		return
	var def: Resource = load(PART_DEF_SCRIPT).new()
	def.set("id", id)
	def.set("title", String(e.get("title", id)))
	def.set("kind", kind)
	def.set("scene", ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE))
	def.set("mass", float(e["mass"]))
	def.set("energy", int(e.get("energy", 0)))
	def.set("attach", String(e.get("attach", "joint")))
	def.set("body_mult", _body_mult(id, kind, e))
	def.set("hit_mult", _hit_mult(id, kind, e))
	def.set("hit_profile", _hit_profile(id))
	def.set("material", String(e.get("material", "wood")))
	def.set("name_prefix", String(e.get("name_prefix", "Part")))
	def.set("weapon_mult", float(e.get("weapon_mult", 1.0)))
	def.set("base_mat", base_mat)
	def.set("connector", bool(e.get("connector", false)))
	if _save_def(def, id):
		summary["parts"] = int(summary["parts"]) + 1
		print("part %-22s %-11s %4.1f kg  E%-2d %-5s %-12s shapes %d anchors %s" % [id, kind, float(e["mass"]), int(e.get("energy", 0)),
			e.get("attach", "joint"), base_mat, shapes, ",".join(anchors)])


## PartDef.body_mult (§3.3): у детали со своим телом — Tuning.BODY_MULT по name_prefix (удар в бою — таблица по имени тела ×
## материал узла, ModularDoll meta body_mult; своё число детали не читается), у fixed-видов (декор / броня: бонус телу-хозяину,
## навершия) — из каталога. body_mult каталога у детали со своим телом, отличный от таблицы, — предупреждение (мёртвые данные).
func _body_mult(id: String, kind: String, e: Dictionary) -> float:
	var bm := float(e.get("body_mult", 1.0))
	var fixed_kinds := PackedStringArray(load(PART_DEF_SCRIPT).get("FIXED_KINDS"))
	if String(e.get("attach", "joint")) == "fixed" or fixed_kinds.has(kind):
		return bm
	var prefix := String(e.get("name_prefix", "Part"))
	var table := float((T.BODY_MULT as Dictionary).get(prefix, 1.0))
	if e.has("body_mult") and not is_equal_approx(bm, table):
		_warn("%s: body_mult %.2f из каталога не используется — у детали со своим телом Tuning.BODY_MULT[%s] = %.2f (× материал, §3.3)"
			% [id, bm, prefix, table])
	return table


## Профиль скорости формы (WORKSHOP_V3.md §4, Damage.shape_mult) по префиксу id: колющие — бонус на медленном тычке, дробящие —
## на размахе; мягкие (верёвка, щупальце) — штраф на любой скорости. Нет в таблице — "" (множитель постоянный; у формы 1.0 не важен).
const HIT_PROFILE := {
	"kit_limb_spiked_": "sharp", "kit_head_horned": "sharp", "kit_head_devil": "sharp", "kit_hand_claw": "sharp", "kit_foot_peg": "sharp",
	"kit_deco_spikes_": "sharp", "kit_deco_horns": "sharp",
	"kit_hand_fist": "blunt", "kit_hand_clamp": "blunt", "kit_head_cow": "blunt", "kit_deco_gauntlet_": "blunt",
	"kit_limb_rope_": "soft", "kit_limb_tentacle_": "soft",
	# детали лиги (tools/blender/kit_league.py): коса, когти, ходуля, рога — колющие; клешня и кристалл — дробящие; щупальце — мягкое
	"kit_limb_league_scythe_": "sharp", "kit_hand_league_talon": "sharp", "kit_foot_league_spike": "sharp", "kit_head_league_eye": "sharp",
	"kit_head_league_crystal": "sharp", "kit_hand_league_pincer": "blunt", "kit_limb_league_crystal_": "blunt",
	"kit_limb_league_tentacle_": "soft",
	# наборы 04.10: про-лига Земли (tools/blender/kit_pro.py) и живые детали Аоэлюн (kit_aoe.py)
	"kit_hand_pro_claw": "sharp", "kit_foot_pro_spike": "sharp", "kit_hand_pro_crusher": "blunt",
	"kit_limb_aoe_blade_": "sharp", "kit_limb_aoe_whip_": "sharp", "kit_hand_aoe_claw": "sharp", "kit_foot_aoe_stilt": "sharp",
	"kit_head_aoe_watcher": "sharp", "kit_head_aoe_hunter": "sharp", "kit_deco_aoe_spines": "sharp", "kit_hand_aoe_hook": "blunt",
}


func _hit_profile(id: String) -> String:
	for k in HIT_PROFILE:
		if id.begins_with(String(k)):
			return String(HIT_PROFILE[k])
	return ""


## PartDef.hit_mult (§3.3): множитель удара ЭТОЙ формой (шипы, рога, клешня) — из каталога (META hit_mult Blender-модуля), только у
## детали со своим телом; у fixed-видов (декор / броня: их бонус — body_mult, навершия) — 1.0, hit_mult в каталоге — предупреждение.
func _hit_mult(id: String, kind: String, e: Dictionary) -> float:
	var hm := float(e.get("hit_mult", 1.0))
	var fixed_kinds := PackedStringArray(load(PART_DEF_SCRIPT).get("FIXED_KINDS"))
	if String(e.get("attach", "joint")) == "fixed" or fixed_kinds.has(kind):
		if e.has("hit_mult"):
			_warn("%s: hit_mult %.2f у fixed-детали не используется (её бонус хозяину — body_mult, §6)" % [id, hm])
		return 1.0
	if hm <= 0.0:
		_err("%s: hit_mult %.2f ≤ 0" % [id, hm])
		return 1.0
	return hm


## Центр форм по Y, взвешенный по объёму (как ModularDoll._com_local: центр масс AUTO у Jolt) — у кисти он станет началом тела.
static func _shapes_centre_y(root: Node) -> float:
	var acc := 0.0
	var vol := 0.0
	for c in root.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
			var v := _shape_volume((c as CollisionShape3D).shape)
			acc += (c as Node3D).position.y * v
			vol += v
	return acc / vol if vol > 0.0 else 0.0


## Объём формы (= ModularDoll._shape_volume; ModularDoll в режиме -s не грузим ради одной функции).
static func _shape_volume(sh: Shape3D) -> float:
	if sh is CapsuleShape3D:
		var c := sh as CapsuleShape3D
		return PI * c.radius * c.radius * maxf(c.height - 2.0 * c.radius, 0.0) + 4.0 / 3.0 * PI * pow(c.radius, 3.0)
	if sh is SphereShape3D:
		return 4.0 / 3.0 * PI * pow((sh as SphereShape3D).radius, 3.0)
	if sh is CylinderShape3D:
		var cy := sh as CylinderShape3D
		return PI * cy.radius * cy.radius * cy.height
	if sh is BoxShape3D:
		var b := (sh as BoxShape3D).size
		return b.x * b.y * b.z
	return 0.0


## Физика тела детали (§3.1): оси как у куклы, CCD, демпфирование куклы по виду, PhysicsMaterial материала по умолчанию.
func _physics(root: RigidBody3D, kind: String, base_mat: String) -> void:
	root.axis_lock_linear_z = true
	root.axis_lock_angular_x = true
	root.axis_lock_angular_y = true
	root.continuous_cd = true
	root.can_sleep = false
	var core := kind == "core" or kind == "head"
	# как Tuning.doll_linear_damp / doll_angular_damp (ядро — торс и голова); Doll._ready ставит то же по имени тела
	root.linear_damp = T.DOLL_LINEAR_DAMP if core else T.DOLL_LIMB_LINEAR_DAMP
	root.angular_damp = T.ANGULAR_DAMP if core else T.DOLL_LIMB_ANGULAR_DAMP
	var pm := PhysicsMaterial.new()
	var row := _mat_row(base_mat)
	pm.friction = float(row[4]) if not row.is_empty() else 0.6
	pm.bounce = float(row[5]) if not row.is_empty() else 0.05
	root.physics_material_override = pm


## Метаданные якоря по имени (§3.1). short — имя без «Anchor_».
func _anchor_meta(mk: Marker3D, short: String) -> void:
	var base := short
	var mirror := false
	if short.ends_with("_L") or short.ends_with("_R"):
		base = short.substr(0, short.length() - 2)
		mirror = short.ends_with("_R")
	var accepts: Array = OTHER_ACCEPTS
	var group := OTHER_GROUP
	var from_pose := false
	match base:
		"Neck":
			accepts = ["head"]
			group = "Neck"
			from_pose = true
		"Shoulder", "Hip":
			accepts = ANY_LIMB
			group = base
			from_pose = true
		"Side":
			accepts = ANY_LIMB
			group = "Hip"
			mk.set_meta("limit_deg", SIDE_LIMITS)
		"End":
			accepts = ANY_LIMB
			group = "auto"   # BodyBlueprint.AUTO_NEXT: плечо → локоть → кисть, бедро → колено → лодыжка
		"Deco":
			accepts = ["armor", "deco"]
			group = ""
		"Top", "Back":
			accepts = ["deco"]
			group = ""
	mk.set_meta("accepts", PackedStringArray(accepts))
	mk.set_meta("joint_group", group)
	mk.set_meta("rest_deg", float(T.POSE[group]) if from_pose and T.POSE.has(group) else 0.0)
	mk.set_meta("mirror", mirror)
	mk.set_meta("rest_from_pose", from_pose)
	if float(JOINT_R.get(base, 0.0)) > 0.0:
		mk.set_meta("joint_r", float(JOINT_R[base]))


## Mesh = инстанс glb (meta rig_mesh: Doll прячет его под внешним скином). Пустышки и FacePlate остаются внутри Mesh.
func _add_mesh(root: Node3D, model: PackedScene, xf: Transform3D) -> void:
	var mesh: Node3D = model.instantiate()
	mesh.name = "Mesh"
	mesh.transform = xf
	mesh.set_meta("rig_mesh", true)
	root.add_child(mesh)
	mesh.owner = root   # инстанс целиком: внутренние узлы принадлежат glb-сцене


## Пустышка glb Shape_<Тип>_<имя> → CollisionShape3D "Shape_<имя>" (= build_craft_parts.gd _shape_from).
func _shape_from(node_name: String, t: Transform3D) -> CollisionShape3D:
	var bits := node_name.split("_")
	if bits.size() < 3:
		return null
	var sc := t.basis.get_scale()
	var cs := CollisionShape3D.new()
	cs.name = "Shape_" + "_".join(bits.slice(2))
	match bits[1]:
		"Box":
			var b := BoxShape3D.new()
			b.size = Vector3(maxf(2.0 * sc.x, MIN_THICK), maxf(2.0 * sc.y, MIN_THICK), maxf(2.0 * sc.z, MIN_THICK))
			cs.shape = b
		"Sphere":
			var s := SphereShape3D.new()
			s.radius = sc.x
			cs.shape = s
		"Cyl":
			var cy := CylinderShape3D.new()
			cy.radius = sc.x
			cy.height = 2.0 * sc.y
			cs.shape = cy
		"Capsule":
			var ca := CapsuleShape3D.new()
			ca.radius = sc.x
			ca.height = maxf(2.0 * sc.y, 2.0 * sc.x)
			cs.shape = ca
		_:
			cs.free()
			return null
	cs.transform = Transform3D(t.basis.orthonormalized(), t.origin)
	return cs


# --- коннекторы шарниров (§3.4) ---

func _build_connector(e: Dictionary) -> void:
	var type := String(e.get("connector_type", ""))
	var glb_path := KIT_DIR + String(e.get("glb", "")) + ".glb"
	var model := load(glb_path) as PackedScene
	if type == "" or model == null:
		_err("коннектор %s: тип «%s», glb %s" % [e.get("glb", ""), type, "есть" if model != null else "не импортирован"])
		return
	# центр шара = Socket glb (у Kit_Joint_* он в начале координат); радиус 1 — ModularDoll масштабирует по joint_r / RADIUS
	var sock := Transform3D.IDENTITY
	var probe: Node = model.instantiate()
	for c in probe.get_children():
		if c is Node3D and _clean(String(c.name)) == "Socket":
			sock = (c as Node3D).transform
	probe.free()
	var root := Node3D.new()
	root.name = _pascal("connector_" + type)
	root.set_meta("rig_mesh", true)
	root.set_meta("connector_type", type)
	_add_mesh(root, model, sock.affine_inverse())
	if _pack(root, CONNECTOR_DIR + type + ".tscn"):
		summary["connectors"] = int(summary["connectors"]) + 1
		print("connector %-8s %s" % [type, glb_path])


# --- кит «Человек» под риг v3 (§3.2) ---

func _build_human_part(h: Array) -> void:
	var id := String(h[0])
	var wood_id := String(h[1])
	var glb := String(h[2])
	var wood_scene := ResourceLoader.load(WOOD_SCENE_DIR + wood_id + ".tscn", "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var wood_def := ResourceLoader.load(PART_DIR + wood_id + ".tres", "", ResourceLoader.CACHE_MODE_REPLACE)
	var model := load(KIT_DIR + glb + ".glb") as PackedScene
	if wood_scene == null or wood_def == null or model == null:
		_err("%s: нет %s (сцена/PartDef) или %s.glb" % [id, wood_id, glb])
		return
	var e: Dictionary = catalog.get(glb, {})
	if e.is_empty():
		_warn("%s: %s нет в каталоге — base_mat пустой" % [id, glb])
	var root := wood_scene.instantiate() as RigidBody3D
	root.scene_file_path = ""
	for mn in ["Mesh", "Mesh_R"]:
		var old := root.get_node_or_null(mn)
		if old != null:
			root.remove_child(old)
			old.free()
	# свои копии под-ресурсов wood_* (иначе сохранение новой сцены тянет ресурсы чужого файла); значения те же
	if root.physics_material_override != null:
		root.physics_material_override = root.physics_material_override.duplicate()
	for c in root.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
			(c as CollisionShape3D).shape = (c as CollisionShape3D).shape.duplicate()
	var wood_sock := Transform3D.IDENTITY
	var ws := root.get_node_or_null("Socket") as Node3D
	if ws != null:
		wood_sock = ws.transform
	var glb_sock := Transform3D.IDENTITY
	var glb_anchors := {}
	var probe: Node = model.instantiate()
	for c in probe.get_children():
		if not c is Node3D or c is MeshInstance3D:
			continue
		var n := _clean(String(c.name))
		if n == "Socket":
			glb_sock = (c as Node3D).transform
		elif DECO_ANCHORS.has(n):
			glb_anchors[n] = (c as Node3D).transform
	probe.free()
	var mesh_xf := wood_sock * glb_sock.affine_inverse()
	_add_mesh(root, model, mesh_xf)
	var added: PackedStringArray = []
	for n in glb_anchors:
		if root.get_node_or_null(String(n)) != null:
			continue
		var t: Transform3D = mesh_xf * (glb_anchors[n] as Transform3D)
		var mk := Marker3D.new()
		mk.name = String(n)
		mk.transform = Transform3D(t.basis.orthonormalized(), t.origin)
		_anchor_meta(mk, String(n).substr(7))
		root.add_child(mk)
		mk.owner = root
		added.append(String(n))
	root.set_meta("part_id", id)
	var scene_path := SCENE_DIR + id + ".tscn"
	if not _pack(root, scene_path):
		return
	# самосверка: формы, масса, демпфирование, физматериал и якоря wood_* — байт в байт
	var kit_scene := ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var a := kit_scene.instantiate()
	var b := wood_scene.instantiate()
	var diffs := _diff_vs_wood(a, b)
	var has_mesh := a.get_node_or_null("Mesh") != null and a.get_node_or_null("Mesh_R") == null
	a.free()
	b.free()
	if not has_mesh:
		diffs.append("Mesh/Mesh_R")
	summary["self_check"][id] = {"ok": diffs.is_empty(), "diffs": diffs, "added_anchors": added, "mesh_xf": var_to_str(mesh_xf.origin)}
	if not diffs.is_empty():
		_err("%s: расходится с %s: %s" % [id, wood_id, "; ".join(diffs)])
	var def: Resource = load(PART_DEF_SCRIPT).new()
	for p in ["kind", "mass", "energy", "attach", "body_mult", "material", "name_prefix", "weapon_mult"]:
		def.set(p, wood_def.get(p))
	def.set("id", id)
	def.set("title", String(h[3]))
	def.set("scene", kit_scene)
	def.set("base_mat", String(e.get("base_mat", "")))
	def.set("connector", String(wood_def.get("kind")) != "core")   # у ядра сустава к родителю нет
	if _save_def(def, id):
		summary["human_parts"] = int(summary["human_parts"]) + 1
		print("human %-20s ← %-15s + %-18s mesh %s  anchors +%s  self-check %s" % [id, wood_id, glb, mesh_xf.origin, ",".join(added),
			"ok" if diffs.is_empty() else "FAIL"])


## Отличия детали кита «Человек» от wood_* (пусто = совпадает): тело, физматериал, формы, маркеры (кроме добавленных якорей декора).
func _diff_vs_wood(kit: Node, wood: Node) -> PackedStringArray:
	var out: PackedStringArray = []
	for p in ["mass", "linear_damp", "angular_damp", "axis_lock_linear_z", "axis_lock_angular_x", "axis_lock_angular_y", "continuous_cd",
			"can_sleep", "gravity_scale", "center_of_mass_mode", "collision_layer", "collision_mask", "name"]:
		if kit.get(p) != wood.get(p):
			out.append("%s %s ≠ %s" % [p, kit.get(p), wood.get(p)])
	if kit.get_meta("kind", "") != wood.get_meta("kind", ""):
		out.append("meta kind")
	var pa: PhysicsMaterial = (kit as RigidBody3D).physics_material_override
	var pb: PhysicsMaterial = (wood as RigidBody3D).physics_material_override
	if (pa == null) != (pb == null) or (pa != null and _props(pa) != _props(pb)):
		out.append("physics_material")
	var sa := _children_of(kit, "CollisionShape3D")
	var sb := _children_of(wood, "CollisionShape3D")
	if sa.keys() != sb.keys():
		out.append("формы %s ≠ %s" % [sa.keys(), sb.keys()])
	for k in sb:
		if not sa.has(k):
			continue
		var x: CollisionShape3D = sa[k]
		var y: CollisionShape3D = sb[k]
		if x.transform != y.transform or x.shape.get_class() != y.shape.get_class() or _props(x.shape) != _props(y.shape):
			out.append("форма " + String(k))
	var ma := _children_of(kit, "Marker3D")
	var mb := _children_of(wood, "Marker3D")
	for k in mb:
		if not ma.has(k):
			out.append("нет маркера " + String(k))
			continue
		var x: Marker3D = ma[k]
		var y: Marker3D = mb[k]
		if x.transform != y.transform:
			out.append("кадр " + String(k))
		for mk in y.get_meta_list():
			if not x.has_meta(mk) or var_to_str(x.get_meta(mk)) != var_to_str(y.get_meta(mk)):
				out.append("meta %s.%s" % [k, mk])
	for k in ma:
		if not mb.has(k) and not DECO_ANCHORS.has(String(k)):
			out.append("лишний маркер " + String(k))
	return out


static func _children_of(n: Node, cls: String) -> Dictionary:
	var out := {}
	for c in n.get_children():
		if c.is_class(cls):
			out[String(c.name)] = c
	return out


## Сохраняемые свойства ресурса строкой (сравнение «байт в байт» без resource_path / имени).
static func _props(r: Resource) -> String:
	var s := ""
	for p in r.get_property_list():
		var pn := String(p["name"])
		if int(p["usage"]) & PROPERTY_USAGE_STORAGE and not pn.begins_with("resource_") and pn != "script":
			s += "%s=%s;" % [pn, var_to_str(r.get(pn))]
	return s


# --- пресеты (§3.5) ---

## Узел чертежа. extra — rest_deg / mat / joint.
static func _n(uid: String, part: String, parent: String = "", anchor: String = "", name: String = "", extra: Dictionary = {}) -> Dictionary:
	var n := {"uid": uid, "part": part, "parent": parent, "anchor": anchor}
	if name != "":
		n["name"] = name
	for k in extra:
		n[k] = extra[k]
	return n


## Цепь из трёх деталей от якоря ядра T: parts — [верхняя, нижняя, конец], names — имена тел ([] — авто), extras — по узлу.
static func _chain(out: Array, uids: String, anchor: String, parts: Array, names: Array = [], extras: Array = [{}, {}, {}]) -> void:
	var parent := "T"
	var anchors := [anchor, "Anchor_End", "Anchor_End"]
	for i in range(3):
		out.append(_n(uids[i], String(parts[i]), parent, anchors[i], String(names[i]) if names.size() > i else "",
			extras[i] if extras.size() > i else {}))
		parent = uids[i]


func _build_presets() -> void:
	# kit_human — human.tres узел в узел (те же uid, имена тел, углы, control), детали kit_human_*
	var human := ResourceLoader.load(BLUEPRINT_DIR + "human.tres", "", ResourceLoader.CACHE_MODE_REPLACE)
	var kit_human_nodes: Array = []
	if human == null:
		_err("нет %shuman.tres" % BLUEPRINT_DIR)
	else:
		var swap := {}
		for h in HUMAN:
			swap[String(h[1])] = String(h[0])
		var nodes: Array = []
		var ok := true
		for src in human.get("nodes"):
			var n: Dictionary = (src as Dictionary).duplicate(true)
			if not swap.has(String(n["part"])):
				_err("kit_human: деталь «%s» human.tres без пары kit_human_*" % n["part"])
				ok = false
			n["part"] = swap.get(String(n["part"]), n["part"])
			nodes.append(n)
		if ok:
			_save_blueprint("kit_human", "Кит «Человек»", nodes, Array(human.get("control")), int(human.get("energy_budget")))
			kit_human_nodes = nodes

	# brawler — ящик, голова-ящик, толстые руки (варежки — крашеный лист), поршень + базовая голень, ботинки. Энергия по расстоянию
	# (WORKSHOP_V3.md §2, 30.09): без мотора плеча и железных наплечников, нижняя голень базовая — 119 → ≤ 100
	var n: Array = [_n("T", "kit_core_crate", "", "", "Torso"), _n("H", "kit_head_crate", "T", "Anchor_Neck", "Head")]
	var arm := ["kit_limb_thick_s", "kit_limb_thick_s", "kit_hand_mitten"]
	var leg := ["kit_limb_piston_l", "kit_limb_basic_l", "kit_foot_boot"]
	_chain(n, "123", "Anchor_Shoulder_L", arm, ARM_L, [{}, {"rest_deg": ELBOW_REST}, {"mat": "rust_red"}])
	_chain(n, "456", "Anchor_Hip_L", leg, LEG_L, [{}, {"rest_deg": KNEE_REST}, {}])
	_chain(n, "789", "Anchor_Shoulder_R", arm, ARM_R, [{}, {"rest_deg": ELBOW_REST}, {"mat": "rust_red"}])
	_chain(n, "ABC", "Anchor_Hip_R", leg, LEG_R, [{}, {"rest_deg": KNEE_REST}, {}])
	_save_blueprint("kit_brawler", "Громила", n, ["9"])
	var brawler_nodes: Array = n.duplicate(true)

	# bot — ядро-хаб синей краской, голова-экран, пружинные руки с локтями-пружинами (согнуты), клешни, белые поршни, колышки, флажок
	n = [_n("T", "kit_core_ball", "", "", "Torso", {"mat": "paint_blue"}), _n("H", "kit_head_bot", "T", "Anchor_Neck", "Head")]
	arm = ["kit_limb_spring_s", "kit_limb_spring_s", "kit_hand_claw"]
	leg = ["kit_limb_piston_l", "kit_limb_piston_l", "kit_foot_peg"]
	var white := {"mat": "paint_white"}
	_chain(n, "123", "Anchor_Shoulder_L", arm, ARM_L, [{}, {"joint": "spring", "rest_deg": 25.0}, {}])
	_chain(n, "456", "Anchor_Hip_L", leg, LEG_L, [white, {"mat": "paint_white", "rest_deg": 8.0}, {}])
	_chain(n, "789", "Anchor_Shoulder_R", arm, ARM_R, [{}, {"joint": "spring", "rest_deg": 25.0}, {}])
	_chain(n, "ABC", "Anchor_Hip_R", leg, LEG_R, [white, {"mat": "paint_white", "rest_deg": 8.0}, {}])
	n.append(_n("D", "kit_deco_banner", "T", "Anchor_Back"))
	_save_blueprint("kit_bot", "Робот", n, ["9"])

	# horned — железная бочка, рогатый шлем, кости, бронеплиты, клешни, железные ботинки. Энергия по расстоянию (WORKSHOP_V3.md §2,
	# 30.09): колени без моторов и без шипастых ошейников на бёдрах — 124 → ≤ 100
	n = [_n("T", "kit_core_barrel", "", "", "Torso", {"mat": "iron"}), _n("H", "kit_head_horned", "T", "Anchor_Neck", "Head")]
	arm = ["kit_limb_bone_s", "kit_limb_bone_s", "kit_hand_claw"]
	leg = ["kit_limb_plate_l", "kit_limb_plate_l", "kit_foot_boot"]
	var iron := {"mat": "iron"}
	_chain(n, "123", "Anchor_Shoulder_L", arm, ARM_L, [{}, {"rest_deg": ELBOW_REST}, {}])
	_chain(n, "456", "Anchor_Hip_L", leg, LEG_L, [{}, {"rest_deg": KNEE_REST}, iron])
	_chain(n, "789", "Anchor_Shoulder_R", arm, ARM_R, [{}, {"rest_deg": ELBOW_REST}, {}])
	_chain(n, "ABC", "Anchor_Hip_R", leg, LEG_R, [{}, {"rest_deg": KNEE_REST}, iron])
	_save_blueprint("kit_horned", "Рогатый", n, ["9"])

	# king — ржавый хаб, белая голова с короной, оливковые толстые плечи, щупальца с шаром булавы вместо кисти, ноги из ореха. Кисти нет
	# — рука мышью ведёт правое щупальце с булавой (как кистень: control — деталь, несущая груз; хват — маркер Grip на её конце).
	# Левое щупальце на свободном шарнире, правое — на пружине: свободный локоть управляемой руки сила хвата вверх не поднимает
	# (ArmAssist без IK двух звеньев — цель вверху не достаётся, ошибка ~0.6 м), пружина держит
	n = [_n("T", "kit_core_ball", "", "", "Torso", {"mat": "rust"}),
		_n("H", "kit_head_round", "T", "Anchor_Neck", "Head", {"mat": "paint_white"}), _n("D", "kit_deco_crown", "H", "Anchor_Top")]
	arm = ["kit_limb_thick_s", "kit_limb_tentacle_s", "head_mace_ball"]
	leg = ["kit_limb_basic_l", "kit_limb_basic_l", "kit_foot_boot"]
	var dark := {"mat": "wood_dark"}
	_chain(n, "123", "Anchor_Shoulder_L", arm, ["UpperArm_L", "LowerArm_L"], [{"mat": "paint_green"}, {"joint": "free"}, {}])
	_chain(n, "456", "Anchor_Hip_L", leg, LEG_L, [dark, {"mat": "wood_dark", "rest_deg": KNEE_REST}, {}])
	_chain(n, "789", "Anchor_Shoulder_R", arm, ["UpperArm_R", "LowerArm_R"], [{"mat": "paint_green"}, {"joint": "spring"}, {}])
	_chain(n, "ABC", "Anchor_Hip_R", leg, LEG_R, [dark, {"mat": "wood_dark", "rest_deg": KNEE_REST}, {}])
	_save_blueprint("kit_king", "Король-булава", n, ["8"])

	# spider — хаб, круглая голова, четыре базовые ноги L на бёдрах и плечах, ботинки (углы — как пресет spider). Энергия по
	# расстоянию (WORKSHOP_V3.md §2, 30.09): шесть ног стоили 134 — боковые пары сняты
	n = [_n("T", "kit_core_ball"), _n("H", "kit_head_round", "T", "Anchor_Neck")]
	leg = ["kit_limb_basic_l", "kit_limb_basic_l", "kit_foot_boot"]
	for s in [["123", "Anchor_Hip_L", 22.0, 15.0], ["456", "Anchor_Hip_R", 22.0, 15.0],
			["DEF", "Anchor_Shoulder_L", 110.0, 10.0], ["GIJ", "Anchor_Shoulder_R", 110.0, 10.0]]:
		var u := String(s[0])
		var up: Dictionary = {} if is_nan(float(s[2])) else {"rest_deg": float(s[2])}
		_chain(n, u, String(s[1]), leg, ["", "LowerLeg_" + u[1]], [up, {"rest_deg": float(s[3])}, {}])
	_save_blueprint("kit_spider", "Паук из кита", n, ["J"])

	# --- пресеты второй волны деталей: показывают новые головы, ядра, конечности, кисти / стопы, декор и навершия ---

	# devil — ядро-игрушка бордовой краской (paint_red), голова-чёртик, шипастые руки (левая — клешня, правая — кулак: ею и бьёт), тонкие
	# железные ноги с коленями-пружинами (пружинит на ходу), бордовые ласты, жестяные крылья на спине
	n = [_n("T", "kit_core_toy", "", "", "Torso", {"mat": "paint_red"}), _n("H", "kit_head_devil", "T", "Anchor_Neck", "Head")]
	leg = ["kit_limb_thin_l", "kit_limb_thin_l", "kit_foot_flipper"]
	var red := {"mat": "paint_red"}
	var knee_spring := {"joint": "spring", "rest_deg": KNEE_REST}
	_chain(n, "123", "Anchor_Shoulder_L", ["kit_limb_spiked_s", "kit_limb_spiked_s", "kit_hand_claw"], ARM_L, [{}, {"rest_deg": ELBOW_REST}, {}])
	_chain(n, "456", "Anchor_Hip_L", leg, LEG_L, [{}, knee_spring, red])
	_chain(n, "789", "Anchor_Shoulder_R", ["kit_limb_spiked_s", "kit_limb_spiked_s", "kit_hand_fist"], ARM_R, [{}, {"rest_deg": ELBOW_REST}, {}])
	_chain(n, "ABC", "Anchor_Hip_R", leg, LEG_R, [{}, knee_spring, red])
	n.append(_n("D", "kit_deco_wings", "T", "Anchor_Back"))
	_save_blueprint("kit_devil", "Чёртик", n, ["9"])

	# skull — ядро-клетка, череп с карточкой и султаном, кости, тиски, колышки из кости; левое предплечье на свободном шарнире
	# (болтается, как у скелета), на правом — наруч; рука мышью — правые тиски
	n = [_n("T", "kit_core_cage", "", "", "Torso"), _n("H", "kit_head_skull", "T", "Anchor_Neck", "Head"),
		_n("D", "kit_deco_plume", "H", "Anchor_Top")]
	arm = ["kit_limb_bone_s", "kit_limb_bone_s", "kit_hand_clamp"]
	leg = ["kit_limb_bone_l", "kit_limb_bone_l", "kit_foot_peg"]
	var bone := {"mat": "bone"}
	_chain(n, "123", "Anchor_Shoulder_L", arm, ARM_L, [{}, {"joint": "free"}, {}])
	_chain(n, "456", "Anchor_Hip_L", leg, LEG_L, [{}, {"rest_deg": KNEE_REST}, bone])
	_chain(n, "789", "Anchor_Shoulder_R", arm, ARM_R, [{}, {"rest_deg": ELBOW_REST}, {}])
	_chain(n, "ABC", "Anchor_Hip_R", leg, LEG_R, [{}, {"rest_deg": KNEE_REST}, bone])
	n.append(_n("E", "kit_deco_gauntlet_s", "8", "Anchor_Deco"))
	_save_blueprint("kit_skull", "Скелет", n, ["9"])

	# wheels — каталка: бочка из-под масла, голова-банка с антенной, робо-плечи и тонкие предплечья с лопастями, робо-ноги, вместо
	# стоп колёса. Энергия по расстоянию (WORKSHOP_V3.md §2, 30.09): колени без пружин, предплечья тонкие — 116 → ≤ 100
	n = [_n("T", "kit_core_drum", "", "", "Torso"), _n("H", "kit_head_can", "T", "Anchor_Neck", "Head"),
		_n("D", "kit_deco_antenna", "H", "Anchor_Top")]
	arm = ["kit_limb_robotic_s", "kit_limb_thin_s", "kit_hand_paddle"]
	leg = ["kit_limb_robotic_l", "kit_limb_robotic_l", "kit_foot_wheel"]
	_chain(n, "123", "Anchor_Shoulder_L", arm, ARM_L, [{}, {"rest_deg": ELBOW_REST}, {}])
	_chain(n, "456", "Anchor_Hip_L", leg, LEG_L, [{}, {"rest_deg": KNEE_REST}, {}])
	_chain(n, "789", "Anchor_Shoulder_R", arm, ARM_R, [{}, {"rest_deg": ELBOW_REST}, {}])
	_chain(n, "ABC", "Anchor_Hip_R", leg, LEG_R, [{}, {"rest_deg": KNEE_REST}, {}])
	_save_blueprint("kit_wheels", "Каталка", n, ["9"])

	# lantern — фонарщик: ядро-котёл, голова-фонарь, дымоход на спине, руки — гнутая труба + тонкое предплечье; на правом вместо
	# кисти бур (навершие кита, слито с предплечьем) на локте-моторе, на левом — тиски; поршневые ноги, железные ботинки.
	# Рука мышью ведёт предплечье с буром (как у kit_king: control — деталь, несущая навершие). Энергия по расстоянию
	# (WORKSHOP_V3.md §2, 30.09): нижняя голень базовая — 104 → ≤ 100
	n = [_n("T", "kit_core_boiler", "", "", "Torso"), _n("H", "kit_head_lantern", "T", "Anchor_Neck", "Head")]
	leg = ["kit_limb_piston_l", "kit_limb_basic_l", "kit_foot_boot"]
	_chain(n, "123", "Anchor_Shoulder_L", ["kit_limb_curved_s", "kit_limb_thin_s", "kit_hand_clamp"], ARM_L, [{}, {"rest_deg": ELBOW_REST}, {}])
	_chain(n, "456", "Anchor_Hip_L", leg, LEG_L, [{}, {"rest_deg": KNEE_REST}, iron])
	_chain(n, "789", "Anchor_Shoulder_R", ["kit_limb_curved_s", "kit_limb_thin_s", "kit_drill_head"], ["UpperArm_R", "LowerArm_R"],
		[{}, {"joint": "motor", "rest_deg": ELBOW_REST}, {}])
	_chain(n, "ABC", "Anchor_Hip_R", leg, LEG_R, [{}, {"rest_deg": KNEE_REST}, iron])
	n.append(_n("D", "kit_deco_chimney", "T", "Anchor_Back"))
	_save_blueprint("kit_lantern", "Фонарщик", n, ["8"])

	# spinner — вертушка (UI v0.2, шаблоны мастерской): хаб, круглая голова, ног нет — четыре руки на плечах и бёдрах, у каждой на
	# свободном шарнире верёвка с шаром булавы: раскручивается и молотит. Рука мышью — правая верхняя верёвка (как у kit_king: деталь,
	# несущая груз). Странная несимметричная по смыслу сборка — чтобы шаблоны не были только «человечками»
	n = [_n("T", "kit_core_ball", "", "", "Torso", {"mat": "rust"}), _n("H", "kit_head_round", "T", "Anchor_Neck", "Head")]
	arm = ["kit_limb_basic_s", "kit_limb_rope_s", "head_mace_ball"]
	_chain(n, "123", "Anchor_Shoulder_L", arm, ["UpperArm_L", "LowerArm_L"], [{}, {"joint": "free"}, {}])
	_chain(n, "789", "Anchor_Shoulder_R", arm, ["UpperArm_R", "LowerArm_R"], [{}, {"joint": "free"}, {}])
	_chain(n, "456", "Anchor_Hip_L", arm, ["", ""], [{}, {"joint": "free"}, {}])
	_chain(n, "ABC", "Anchor_Hip_R", arm, ["", ""], [{}, {"joint": "free"}, {}])
	_save_blueprint("kit_spinner", "Вертушка", n, ["8"])

	# empty — «пустой» шаблон (UI v0.2): ядро и голова, дальше всё — из каталога
	n = [_n("T", "kit_core_ball", "", "", "Torso"), _n("H", "kit_head_round", "T", "Anchor_Neck", "Head")]
	_save_blueprint("kit_empty", "Пустой", n, [])

	# --- витрина покраски (docs/plan-demo/BODY_PAINT.md §1, §4): тело то же, сверху краска и трафареты ---
	if not kit_human_nodes.is_empty():
		_build_graffiti(kit_human_nodes.duplicate(true), Array(human.get("control")), int(human.get("energy_budget")))
	_build_camo(brawler_nodes)


## kit_graffiti — kit_human узел в узел: ноги в пламени, руки в полоску, на груди тег граффити и две золотые звезды по бокам окошка
## ядра (между обручами и окошком), золотая корона на лбу — по верхнему краю плашки лица (глаза открыты).
## Парные детали (L / R) — один seed: корень меша правой детали зеркальный, раскраска выходит симметричной.
func _build_graffiti(nodes: Array, control: Array, budget: int) -> void:
	var seeds := {"4": 11, "A": 11, "5": 12, "B": 12, "6": 13, "C": 13, "1": 21, "7": 21, "2": 22, "8": 22, "3": 23, "9": 23}
	var stripes := [Color(0.97, 0.96, 0.9), Color(0.12, 0.42, 0.86)]
	var ok := true
	for nd in nodes:
		var uid := String(nd["uid"])
		if uid in ["4", "5", "6", "A", "B", "C"]:
			ok = _paint_pattern(nd, "flames", [], int(seeds[uid])) and ok
		elif uid in ["1", "2", "3", "7", "8", "9"]:
			ok = _paint_pattern(nd, "stripes", stripes, int(seeds[uid])) and ok
		elif uid == "T":
			ok = _paint_pattern(nd, "graffiti", [Color(1.0, 0.36, 0.72), Color(0.08, 0.07, 0.07)], 31) and ok
			for sx in [-0.55, 0.55]:
				ok = _add_stencil(nd, "star", Vector3(sx, 0.35, 1.0), Vector3(0, 0, -1), 0.09, Color(1.0, 0.8, 0.12)) and ok
		elif uid == "H":
			ok = _add_stencil(nd, "crown", Vector3(0.0, 0.62, 1.0), Vector3(0, 0, -1), 0.085, Color(1.0, 0.8, 0.12)) and ok
	if ok:
		_save_blueprint("kit_graffiti", "Граффити", nodes, control, budget)


## kit_camo — громила (kit_brawler узел в узел) в светлом лесном камуфляже целиком (олива, песок, тёмная зелень — палитра по
## умолчанию в полутёмной мастерской сливается), на груди над окошком — оранжевая мишень.
func _build_camo(nodes: Array) -> void:
	var ok := true
	var woodland := [Color(0.5, 0.56, 0.3), Color(0.74, 0.64, 0.44), Color(0.16, 0.2, 0.12)]
	for nd in nodes:
		var uid := String(nd["uid"])
		# пары L / R и пара наплечников — один seed (см. _build_graffiti)
		var key := {"7": "1", "8": "2", "9": "3", "A": "4", "B": "5", "C": "6", "E": "D"}.get(uid, uid) as String
		ok = _paint_pattern(nd, "camo", woodland, 500 + key.unicode_at(0)) and ok
		if uid == "T":
			ok = _add_stencil(nd, "target", Vector3(0.0, 0.5, 1.0), Vector3(0, 0, -1), 0.13, Color(0.97, 0.45, 0.1)) and ok
	if ok:
		_save_blueprint("kit_camo", "Камуфляж", nodes, ["9"])


## Корень меша детали part_id в её сцене (узел «Mesh», как BodyPaint.mesh_root_of у детали со своим телом и у слитой): [инстанс, корень];
## [] — нет сцены / меша. Инстанс освобождает вызывающий.
func _part_mesh_root(part_id: String) -> Array:
	var def := ResourceLoader.load(PART_DIR + part_id + ".tres")
	var ps: PackedScene = def.get("scene") if def != null else null
	if ps == null:
		return []
	var inst := ps.instantiate()
	var root := inst.get_node_or_null("Mesh") as Node3D
	if root == null:
		inst.free()
		return []
	return [inst, root]


## Раскраска узла nd (ключ paint, BODY_PAINT.md §4): слой по габариту мешей корня (BodyPaint.mesh_aabb — как ModularDoll.ensure_paint),
## PaintLayer.pattern(kind, colors, seed) вдоль +Y корня (у конечностей — к суставу родителя: пламя от стопы вверх).
func _paint_pattern(nd: Dictionary, kind: String, colors: Array, pattern_seed: int) -> bool:
	var mr := _part_mesh_root(String(nd["part"]))
	if mr.is_empty():
		_err("покраска: у детали «%s» нет Mesh" % nd["part"])
		return false
	var box: AABB = load(BODY_PAINT_SCRIPT).mesh_aabb(mr[1])
	(mr[0] as Node).free()
	var layer: RefCounted = load(PAINT_LAYER_SCRIPT).for_aabb(box)
	layer.call("pattern", kind, colors, pattern_seed, Vector3.UP)
	if bool(layer.call("is_empty")):
		_err("покраска: раскраска «%s» детали «%s» пустая" % [kind, nd["part"]])
		return false
	nd["paint"] = layer.call("to_dict")
	return true


## Трафарет name на деталь узла nd (ключ stickers): луч в кадре корня меша из точки центр габарита + at × (полгабарита) по dir, по
## треугольникам мешей (без Connector_*); кадр — Y по нормали наружу, «верх» картинки — +Y корня (как мастерская: X = Y × Z).
func _add_stencil(nd: Dictionary, stencil: String, at: Vector3, dir: Vector3, side: float, colour: Color) -> bool:
	var mr := _part_mesh_root(String(nd["part"]))
	if mr.is_empty():
		_err("трафарет: у детали «%s» нет Mesh" % nd["part"])
		return false
	var root: Node3D = mr[1]
	var bp_script: GDScript = load(BODY_PAINT_SCRIPT)
	var box: AABB = bp_script.mesh_aabb(root)
	var from := box.get_center() + at * box.size * 0.5 - dir * 0.05
	var best := {}
	for mi in bp_script.meshes(root):
		var m := mi as MeshInstance3D
		var rel := Transform3D.IDENTITY
		var cur: Node = m
		while cur != null and cur != root:
			rel = (cur as Node3D).transform * rel
			cur = cur.get_parent()
		var inv := rel.affine_inverse()
		var tm := m.mesh.generate_triangle_mesh()
		if tm == null:
			continue
		var r := tm.intersect_ray(inv * from, inv.basis * dir)
		if r.is_empty():
			continue
		var p: Vector3 = rel * (r["position"] as Vector3)
		var d := (p - from).dot(dir)
		if d > 0.0 and (best.is_empty() or d < float(best["d"])):
			var nrm := (rel.basis.inverse().transposed() * (r["normal"] as Vector3)).normalized()
			best = {"d": d, "p": p, "n": -nrm if nrm.dot(dir) > 0.0 else nrm}
	(mr[0] as Node).free()
	if best.is_empty():
		_err("трафарет «%s»: луч мимо детали «%s»" % [stencil, nd["part"]])
		return false
	var y: Vector3 = best["n"]
	var z := -(Vector3.UP - y * Vector3.UP.dot(y)).normalized()
	var xf := Transform3D(Basis(y.cross(z).normalized(), y, z), best["p"])
	var sts: Array = nd.get("stickers", [])
	sts.append({"img": "stencil:" + stencil, "xf": xf, "size": Vector2(side, side), "color": colour})
	nd["stickers"] = sts
	return true


func _save_blueprint(id: String, title: String, nodes: Array, control: Array, budget: int = 100) -> void:
	if not id.begins_with("kit_") or id == "human":
		_err("пресет «%s»: builder кита пишет только kit_*" % id)
		return
	var bp: Resource = load(BLUEPRINT_SCRIPT).new()
	var typed: Array[Dictionary] = []
	for n in nodes:
		typed.append(n)
	bp.set("id", id)
	bp.set("title", title)
	bp.set("energy_budget", budget)
	bp.set("nodes", typed)
	bp.set("control", PackedStringArray(control))
	var errors: PackedStringArray = bp.call("validate")
	if not errors.is_empty():
		_err("пресет %s: %s" % [id, "; ".join(errors)])
		return
	var path := BLUEPRINT_DIR + id + ".tres"
	if not _save(bp, path):
		return
	bp = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	# сцена куклы с этим чертежом: корень ModularDoll (Match.respawn_doll пересоздаёт по scene_file_path), как presets/junk.tscn
	var root := Node3D.new()
	root.name = "ModularDoll"
	root.set_script(load(MODULAR_SCRIPT))
	if root.get_script() == null:
		root.free()
		_err("modular_doll.gd не компилируется в режиме -s — пресет %s без сцены" % id)
		return
	root.set("blueprint", bp)
	var out := PRESET_DIR + id + ".tscn"
	if not _pack(root, out):
		return
	var energy := int(bp.call("energy_used"))
	var mass := float(bp.call("total_mass"))
	summary["presets"][id] = {"energy": energy, "budget": budget, "mass": snappedf(mass, 0.1), "nodes": nodes.size(), "control": control}
	print("preset %-12s energy %3d / %d, mass %5.1f kg, %2d nodes → %s" % [id, energy, budget, mass, nodes.size(), out])


# --- общее ---

## Упаковать узел в сцену и сохранить (узел освобождается).
func _pack(root: Node, path: String) -> bool:
	_set_owner(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	root.free()
	if err != OK:
		_err("pack %s: %d" % [path, err])
		return false
	return _save(ps, path)


## Сохранить ресурс. Godot при каждом сохранении .tscn выдаёт новые случайные id ресурсов и unique_id узлов: если по сути файл
## не изменился (_norm совпал), прежний текст возвращается на место — повторный прогон не шумит в git.
func _save(r: Resource, path: String) -> bool:
	var old := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var err := ResourceSaver.save(r, path)
	if err != OK:
		_err("save %s: %d" % [path, err])
		return false
	_written[path] = true
	if old != "":
		var cur := FileAccess.get_file_as_string(path)
		if cur != old and _norm(cur) == _norm(old):
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f != null:
				f.store_string(old)
				f.close()
	return true


## Текст ресурса без случайного: unique_id узлов убраны, id ext_/sub_resource заменены порядковыми.
static func _norm(text: String) -> String:
	var s := RegEx.create_from_string(" unique_id=\\d+").sub(text, "", true)
	var i := 0
	for m in RegEx.create_from_string("\\[(?:ext|sub)_resource [^\\]]*? id=\"([^\"]+)\"").search_all(s):
		s = s.replace("\"%s\"" % m.get_string(1), "\"#%d\"" % i)
		i += 1
	return s


func _save_def(def: Resource, id: String) -> bool:
	var path := PART_DIR + id + ".tres"
	if not _save(def, path):
		return false
	ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	return true


## owner для всех узлов; у инстансов (glb) — только корень инстанса.
func _set_owner(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		if c.scene_file_path == "":
			_set_owner(c, root)


## kit-файлы на диске, которые этот запуск не писал (деталь ушла из каталога): только список, не удаляются.
func _find_stale() -> void:
	for d in [[SCENE_DIR, ".tscn"], [CONNECTOR_DIR, ".tscn"], [PART_DIR, ".tres"], [BLUEPRINT_DIR, ".tres"], [PRESET_DIR, ".tscn"],
			[MATDEF_DIR, ".tres"]]:
		var dir := DirAccess.open(String(d[0]))
		if dir == null:
			continue
		for fn in dir.get_files():
			var kit := fn.begins_with("kit_") or String(d[0]) in [SCENE_DIR, CONNECTOR_DIR, MATDEF_DIR]
			var path := String(d[0]) + fn
			if kit and fn.ends_with(String(d[1])) and not _written.has(path):
				(summary["stale"] as Array).append(path)


func _pascal(id: String) -> String:
	var out := ""
	for w in id.split("_"):
		out += w.capitalize()
	return out


## Суффиксы Blender «.001» / «_001» (Godot превращает точку в «_») отрезаются.
static func _clean(s: String) -> String:
	return RegEx.create_from_string("[._]\\d{3}$").sub(s, "")


static func _unique(name: String, used: Dictionary) -> String:
	var n := name
	var i := 2
	while used.has(n):
		n = "%s_%d" % [name, i]
		i += 1
	used[n] = true
	return n
