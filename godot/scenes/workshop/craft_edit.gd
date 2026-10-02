## Правки чертежей в мастерской (docs/plan-demo/BODY_CRAFT.md §1–4, CONCEPT_V2 §12 «взял деталь → поднёс к anchor → CLICK»).
## Только данные, без сцены: этим пользуются мастерская (scenes/workshop/workshop_build.gd) и проба tests/workshop_probe.gd.
## Формат чертежей не меняется: BodyBlueprint / WeaponBlueprint, nodes — {uid, part, parent, anchor, rest_deg?, name?, mat?, joint?,
## paint?, stickers?, face?} (mat / joint — кит тела v2, только у тела: docs/plan-demo/BODY_KIT.md §4, §5.2, §5.5; paint / stickers /
## face — покраска, docs/plan-demo/BODY_PAINT.md §4: их пишет WorkshopPaint, здесь — только signature и замена детали).
##
## Операции (body — BodyBlueprint, weapon — WeaponBlueprint; обе — «деталь на якорь родителя»):
##   check(bp, part, parent, anchor)  — можно ли прикрутить: {ok, code, reason, replace, energy_after, drops}; code:
##       ""        — можно (якорь свободен);
##       "replace" — можно, якорь занят: деталь заменяется, её дети, которым нет места на новой, снимаются (drops);
##       "kind"    — якорь не принимает этот вид; "energy" — не влезает в бюджет Ядра; "head" — голова только на шею;
##       "core"    — ядро не крепится на якорь (только заменить ядро); "welded" — родитель приварен, а на его auto-конец встаёт
##                   деталь со своим суставом (BODY_KIT.md §5.2); "invalid" — сборка не сошлась (текст validate).
##   attach(...) — то же и применить: новый узел получает свободный uid (имя тела и сустава не совпадают с чужими явными
##       именами пресета human: «UpperArm_L» у узла 1 — новый UpperArm не получит uid L); замена оставляет uid (и явное имя, если
##       префикс тела на этом месте тот же — BodyBlueprint.name_prefix_of), чтобы не терялись control / weapon_on; заменённая деталь
##       стала fixed (навершие вместо управляемой кисти) — рука мышью переезжает на тело-хозяина (у ядра — снимается), оружие —
##       в другую кисть.
##   set_root(...) — ядро (у тела) / рукоять (у оружия) в корень: пустой чертёж — новый корень, иначе замена.
##   detach(bp, uid) — открутить с поддеревом (корень тела не снимается; корень оружия — верстак пуст).
##   set_control(bp, uid) — тяги (WORKSHOP_V3.md §3): клик по детали без тяги — тяга ЛКМ (если хватает энергии; первая бесплатна),
##     по ЛКМ-тяге — переводит на ПКМ, по ПКМ-тяге — снимает; не больше BodyBlueprint.MAX_PULLS;
##       fixed-деталь (броня) — управляется тело-хозяин; ядро нельзя.
##   weapon_mount(bp) — куда вешать крафтовое оружие: кисть управляемой цепи, иначе любая кисть, иначе конец управляемой детали
##       (контракт §2: «оружие на указанной детали»), иначе пусто с подсказкой.
##   check_material / set_material(bp, uid, mat) — кисть материала (кит v2): mat узла, для материала по умолчанию (PartDef.base_mat)
##       ключ стирается; деталь без base_mat не красится (отказ с причиной). {ok, code, reason, changed, mass_before, mass_after}.
##   check_joint / set_joint(bp, uid, type) — тип шарнира связи узла с родителем (KitJoint.ORDER); "pin" = ключ стирается; отказ —
##       корень, fixed-деталь, запреты weld и мотор / пружина на суставе без мышцы (BodyBlueprint.joint_error), энергия (мотор 8,
##       пружина 2). {ok, code, reason, changed}. Причины — словами игрока (_joint_refusal: без uid, имён якорей и «auto»).
## «fixed» (узел без своего тела) — только через is_fixed(): у тела это BodyBlueprint.is_fixed (attach fixed, декор / броня,
## joint "weld"), у оружия — attach fixed.
## Энергия считается только у тела (детали оружия стоят 0, кроме цепи; оружие бюджет Ядра не ест — CONCEPT_V2 §6 про тело).
## Ошибки validate() переводятся в понятные строки (friendly_errors), предупреждения — отдельно (warnings).
## Сохранение — user://blueprints/<имя>.tres (ResourceSaver; оружие — встроенный под-ресурс).
class_name CraftEdit
extends RefCounted

const PARTS_DIR := "res://data/body/parts/"
const BODY_PRESET_DIR := "res://data/body/blueprints/"
const WEAPON_PRESET_DIR := "res://data/body/weapons/"
const SAVE_DIR := "user://blueprints/"
const AUTOSAVE := "_autosave"
const BODY_PRESETS := ["human", "spider", "long_arm", "big_arm", "legless", "junk", "flail",
	"kit_human", "kit_brawler", "kit_bot", "kit_horned", "kit_king", "kit_spider", "kit_devil", "kit_skull", "kit_wheels", "kit_lantern",
	"kit_graffiti", "kit_camo", "kit_spinner", "kit_empty"]
## Детали, которых нет на полках: kit_human_* — дубли wood_* под риг v3 (BODY_KIT.md §3.2) для пресета kit_human; на полке
## их не отличить от kit_limb_basic_* / kit_core_barrel. Чертежи с ними грузятся как обычно (BodyBlueprint.part_def).
const SHELF_HIDDEN_PREFIXES := ["kit_human_"]
const WEAPON_PRESETS := ["mallet", "hammer", "spiked_hammer", "heavy_hammer", "long_hammer", "flail", "sword", "axe", "concept_hammer"]
## Полки мастерской (BODY_KIT.md §5.5): вкладка → виды деталей; tool — инструмент вкладки над деталями: "joint" — плашки типов
## шарнира (ui/joint_card.gd), "material" — кисть материала (ui/material_card.gd), "paint" — покраска (BODY_PAINT.md §1, §6:
## ui/paint_panel.gd, поведение — WorkshopPaint). Ударные навершия есть и у тела («тело становится частью оружия», CONCEPT_V2 §8;
## якоря кита их принимают — ANY_LIMB) — на вкладке брони, после видов из контракта.
## UI v0.2: «Броня» и «Декор» — отдельные категории; icon — деталь, чья иконка (PartIcons) стоит на кнопке категории.
## only — отбор внутри видов (shelf_allows): «Активные» — блоки с действием на клавише канала (вид deco, ActiveBlocks), «Декор» — без.
const BODY_SHELVES := [
	{"id": "core", "title": "Тело", "kinds": ["core"], "icon": "kit_core_barrel"},
	{"id": "head", "title": "Головы", "kinds": ["head"], "icon": "kit_head_round"},
	{"id": "limb", "title": "Конечности", "kinds": ["limb"], "icon": "kit_limb_spring_s"},
	{"id": "end", "title": "Кисти/стопы", "kinds": ["hand", "foot"], "icon": "kit_hand_claw"},
	{"id": "joint", "title": "Шарниры", "kinds": ["joint", "chain"], "tool": "joint", "icon": "chain_segment"},
	{"id": "armor", "title": "Броня", "kinds": ["plate", "armor", "mod", "weapon_head"], "icon": "kit_deco_gauntlet_s"},
	{"id": "deco", "title": "Декор", "kinds": ["deco"], "icon": "kit_deco_crown", "only": "passive"},
	{"id": "active", "title": "Активные", "kinds": ["deco"], "icon": "kit_active_booster", "only": "active"},
	{"id": "mat", "title": "Материал", "kinds": [], "tool": "material", "glyph": "▦"},
	{"id": "paint", "title": "Покраска", "kinds": [], "tool": "paint", "glyph": "✎"},
]
const WEAPON_SHELVES := [
	{"id": "handle", "title": "Рукояти", "kinds": ["handle"]},
	{"id": "weapon_head", "title": "Навершия", "kinds": ["weapon_head"]},
	{"id": "mod", "title": "Моды", "kinds": ["mod"]},
	{"id": "chain", "title": "Цепь", "kinds": ["chain"]},
]
const KIND_ORDER := ["core", "head", "limb", "hand", "foot", "joint", "chain", "plate", "armor", "deco", "handle", "weapon_head", "mod"]
const KIND_TITLES := {
	"core": "ядро", "head": "голова", "limb": "конечность", "hand": "кисть", "foot": "стопа", "joint": "сустав", "chain": "цепь",
	"plate": "щиток", "armor": "броня", "deco": "декор", "handle": "рукоять", "weapon_head": "навершие", "mod": "мод",
}
## Группы мышц словами (отказы шарниров): для «сустав без мышцы (лодыжка)».
const GROUP_TITLES := {
	"Neck": "шея", "Shoulder": "плечо", "Elbow": "локоть", "Wrist": "запястье", "Hip": "бедро", "Knee": "колено", "Ankle": "лодыжка",
}
const MAX_CONTROL := BodyBlueprint.MAX_PULLS   # тяг на куклу (предел — энергия, WORKSHOP_V3.md §3)
const UID_CHARS := BodyBlueprint.UID_CHARS

static var _parts_cache: Array[PartDef] = []
## Кампания «История» (docs/plan-demo/17-career-trophy.md): пока мастерская открыта из кампании, на полках только детали
## campaign_shelf (стартовый кит + трофеи; пусто — все), а при campaign_templates_locked шаблоны тела и оружия не ставятся
## (load_body_preset / load_weapon_preset → null) и не показываются (ui/workshop_ui.gd). Ставит и снимает
## scenes/campaign/campaign_flow.gd.
static var campaign_shelf: PackedStringArray = []
static var campaign_templates_locked := false
static var _scene_names: Dictionary = {}   # путь сцены детали -> PackedStringArray имён CollisionShape3D


# ------------------------------------------------------------------ детали

## Все PartDef полок из data/body/parts (кроме SHELF_HIDDEN_PREFIXES), по порядку KIND_ORDER, внутри — по энергии и массе.
static func all_parts() -> Array[PartDef]:
	if not _parts_cache.is_empty():
		return _parts_cache
	var out: Array[PartDef] = []
	var dir := DirAccess.open(PARTS_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		var fn := f.trim_suffix(".remap")
		if not fn.ends_with(".tres") or SHELF_HIDDEN_PREFIXES.any(func(p: String) -> bool: return fn.begins_with(p)):
			continue
		var d := load(PARTS_DIR + fn) as PartDef
		if d != null and d.is_valid():
			out.append(d)
	out.sort_custom(func(a: PartDef, b: PartDef) -> bool:
		var ka := KIND_ORDER.find(a.kind)
		var kb := KIND_ORDER.find(b.kind)
		if ka != kb:
			return ka < kb
		if a.energy != b.energy:
			return a.energy < b.energy
		if not is_equal_approx(a.mass, b.mass):
			return a.mass < b.mass
		return a.id < b.id)
	_parts_cache = out
	return out


static func parts_of_kinds(kinds: Array) -> Array[PartDef]:
	var out: Array[PartDef] = []
	for d in all_parts():
		if kinds.has(d.kind) and (campaign_shelf.is_empty() or campaign_shelf.has(d.id)):
			out.append(d)
	return out


## Деталь d на полке sh: ключ only — "active" (только активные блоки, ActiveBlocks.DEFS) / "passive" (без них) / нет — все.
static func shelf_allows(sh: Dictionary, d: PartDef) -> bool:
	match String(sh.get("only", "")):
		"active":
			return ActiveBlocks.is_active(d.id)
		"passive":
			return not ActiveBlocks.is_active(d.id)
	return true


## Канал активного блока (docs/plan-demo/ACTIVE_BLOCKS.md): ключ узла "channel" 1…3, 0 — снять (блок молчит).
static func set_channel(bp: BodyBlueprint, uid: String, ch: int) -> void:
	var n := find(bp, uid)
	if n.is_empty():
		return
	if ch >= 1 and ch <= ActiveBlocks.CHANNELS:
		n[ActiveBlocks.NODE_KEY] = ch
	else:
		n.erase(ActiveBlocks.NODE_KEY)


## Вкладка полки по id ({} — нет такой).
static func shelf_of(shelves: Array, id: String) -> Dictionary:
	for s in shelves:
		if String(s["id"]) == id:
			return s
	return {}


static func part(part_id: String) -> PartDef:
	return BodyBlueprint.part_def(part_id)


## Имена CollisionShape3D сцены детали (для сопоставления формы в собранной кукле с uid: fixed-детали переезжают с суффиксом _uid).
static func shape_names(d: PartDef) -> PackedStringArray:
	if d == null or d.scene == null:
		return PackedStringArray()
	var key := d.scene.resource_path
	if _scene_names.has(key):
		return _scene_names[key]
	var out: PackedStringArray = []
	var inst := d.scene.instantiate()
	for c in inst.get_children():
		if c is CollisionShape3D:
			out.append(String(c.name))
	inst.free()
	_scene_names[key] = out
	return out


static func is_weapon(bp: Resource) -> bool:
	return bp is WeaponBlueprint


static func nodes_of(bp: Resource) -> Array:
	return bp.get("nodes") if bp != null else []


static func find(bp: Resource, uid: String) -> Dictionary:
	for n in nodes_of(bp):
		if String(n.get("uid", "")) == uid:
			return n
	return {}


static func root_uid(bp: Resource) -> String:
	for n in nodes_of(bp):
		if String(n.get("parent", "")) == "":
			return String(n.get("uid", ""))
	return ""


static func def_of(bp: Resource, uid: String) -> PartDef:
	var n := find(bp, uid)
	return part(String(n.get("part", ""))) if not n.is_empty() else null


## Узел без своего тела (сливается с родителем): у тела — BodyBlueprint.is_fixed (attach fixed, декор / броня по виду, joint "weld"),
## у оружия — attach fixed. Корень — всегда своё тело.
static func is_fixed(bp: Resource, uid: String) -> bool:
	if bp is BodyBlueprint:
		return (bp as BodyBlueprint).is_fixed(uid)
	var n := find(bp, uid)
	var d := part(String(n.get("part", "")))
	return d != null and d.attach == "fixed" and String(n.get("parent", "")) != ""


## Якоря детали uid: {имя: {xf, accepts, joint_group, rest_deg, mirror, rest_from_pose}} (BodyBlueprint.part_anchors).
static func anchors_of(bp: Resource, uid: String) -> Dictionary:
	return BodyBlueprint.part_anchors(def_of(bp, uid))


static func anchor_name(a: String) -> String:
	return a if a.begins_with("Anchor_") else "Anchor_" + a


## uid детали на якоре anchor родителя parent_uid ("" — свободно).
static func occupant(bp: Resource, parent_uid: String, anchor: String) -> String:
	var an := anchor_name(anchor)
	for n in nodes_of(bp):
		if String(n.get("parent", "")) == parent_uid and anchor_name(String(n.get("anchor", ""))) == an:
			return String(n.get("uid", ""))
	return ""


static func children_of(bp: Resource, uid: String) -> Array:
	var out: Array = []
	for n in nodes_of(bp):
		if String(n.get("parent", "")) == uid:
			out.append(n)
	return out


## uid и все его потомки.
static func subtree(bp: Resource, uid: String) -> PackedStringArray:
	var out: PackedStringArray = [uid]
	var i := 0
	while i < out.size():
		for n in nodes_of(bp):
			if String(n.get("parent", "")) == out[i] and not out.has(String(n.get("uid", ""))):
				out.append(String(n.get("uid", "")))
		i += 1
	return out


## Путь от корня до uid (включительно).
static func path_to(bp: Resource, uid: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var cur := uid
	var guard := 0
	while cur != "" and guard < 64:
		out.insert(0, cur)
		cur = String(find(bp, cur).get("parent", ""))
		guard += 1
	return out


## Правая сторона (зеркало по X) — как ModularDoll._build: mirror(ребёнка) = mirror(родителя) XOR mirror якоря.
static func is_mirrored(bp: Resource, uid: String) -> bool:
	var m := false
	var path := path_to(bp, uid)
	for i in range(1, path.size()):
		var n := find(bp, path[i])
		var a: Dictionary = anchors_of(bp, path[i - 1]).get(anchor_name(String(n.get("anchor", ""))), {})
		m = m != bool(a.get("mirror", false))
	return m


## Угол покоя сустава детали (градусы, «наружу = +» левой стороны), как ModularDoll._build: rest_deg узла, иначе поза Tuning.POSE
## группы (rest_from_pose), иначе rest_deg якоря. У оружия — rest_deg узла или якоря (CraftedWeapon).
static func rest_rel_deg(bp: Resource, uid: String) -> float:
	var n := find(bp, uid)
	if n.has("rest_deg"):
		return float(n["rest_deg"])
	var p := String(n.get("parent", ""))
	if p == "":
		return 0.0
	var a: Dictionary = anchors_of(bp, p).get(anchor_name(String(n.get("anchor", ""))), {})
	if is_weapon(bp):
		return float(a.get("rest_deg", 0.0))
	var g := (bp as BodyBlueprint).anchor_group_of(uid)   # у сваренного узла тоже: сварка держит позу покоя (ModularDoll._weld_rest)
	var pose: Dictionary = Tuning.POSE
	if bool(a.get("rest_from_pose", false)) and pose.has(g):
		return float(pose[g])
	return float(a.get("rest_deg", 0.0))


# ------------------------------------------------------------------ копии, снимки

static func dup_body(bp: BodyBlueprint) -> BodyBlueprint:
	var out := BodyBlueprint.new()
	out.id = bp.id
	out.title = bp.title
	out.energy_budget = bp.energy_budget
	out.nodes = _dup_nodes(bp.nodes)
	out.control = bp.control.duplicate()
	out.control_rmb = bp.control_rmb.duplicate()
	out.weapon = dup_weapon(bp.weapon as WeaponBlueprint) if bp.weapon is WeaponBlueprint else null
	out.weapon_on = bp.weapon_on
	out.weapon_energy_per_kg = bp.weapon_energy_per_kg
	return out


static func dup_weapon(bp: WeaponBlueprint) -> WeaponBlueprint:
	if bp == null:
		return null
	var out := WeaponBlueprint.new()
	out.id = bp.id
	out.title = bp.title
	out.nodes = _dup_nodes(bp.nodes)
	return out


static func _dup_nodes(src: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in src:
		out.append((n as Dictionary).duplicate(true))
	return out


static func load_body_preset(id: String) -> BodyBlueprint:
	var path := BODY_PRESET_DIR + id + ".tres"
	if campaign_templates_locked or not ResourceLoader.exists(path):
		return null
	return dup_body(load(path) as BodyBlueprint)


static func load_weapon_preset(id: String) -> WeaponBlueprint:
	var path := WEAPON_PRESET_DIR + id + ".tres"
	if campaign_templates_locked or not ResourceLoader.exists(path):
		return null
	return dup_weapon(load(path) as WeaponBlueprint)


## Сигнатура узлов для сравнения (проба сохранения): отсортированные строки uid|part|parent|anchor|rest|name|mat|joint|краска, где краска
## (BODY_PAINT.md §4, §6) — «p<байт>:<хэш данных>», «s<число наклеек>:<хэш>», «f<id фото>» (пусто — ключа нет): сохранение ловит потерю.
static func signature(bp: Resource) -> PackedStringArray:
	var out: PackedStringArray = []
	for n in nodes_of(bp):
		out.append("%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [n.get("uid", ""), n.get("part", ""), n.get("parent", ""), anchor_name(String(n.get("anchor", ""))) if String(n.get("parent", "")) != "" else "",
			str(n.get("rest_deg", "")), n.get("name", ""), n.get("mat", ""), n.get("joint", ""), paint_signature(n), str(n.get(ActiveBlocks.NODE_KEY, ""))])
	out.sort()
	return out


## Краска узла одной строкой (для signature): слой — размер и хэш сжатых байт, наклейки — число и хэш картинок / кадров / размеров /
## цветов (str: 6 знаков, как пишет .tres), фото — id.
static func paint_signature(n: Dictionary) -> String:
	var parts: PackedStringArray = []
	var p: Variant = n.get("paint")
	if p is Dictionary:
		var data: Variant = (p as Dictionary).get("data")
		parts.append("p%s:%d" % [str((p as Dictionary).get("size", "")), hash(data) if data is PackedByteArray else 0])
	var sts: Variant = n.get("stickers")
	if sts is Array and not (sts as Array).is_empty():
		var acc := ""
		for st in (sts as Array):
			if st is Dictionary:
				acc += "%s;%s;%s;%s/" % [st.get("img", ""), str(st.get("xf", "")), str(st.get("size", "")), str(st.get("color", ""))]
		parts.append("s%d:%d" % [(sts as Array).size(), acc.hash()])
	if String(n.get("face", "")) != "":
		parts.append("f" + String(n["face"]))
	return ",".join(parts)


# ------------------------------------------------------------------ проверки

## Ошибки сборки, при которых ModularDoll / CraftedWeapon не соберутся (без «голов 0», энергии и управления — это правила игры,
## мастерская показывает их отдельно, а куклу без головы всё равно собирает на стенде). У тела сюда входят и mat / joint узлов
## (BodyBlueprint.mat_error / joint_error): с ними validate() не пропустит чертёж, ModularDoll собрал бы human.
static func structural_errors(bp: Resource) -> PackedStringArray:
	var errors: PackedStringArray = []
	var uids := {}
	var roots := 0
	for n in nodes_of(bp):
		var uid := String(n.get("uid", ""))
		if uid.length() != 1 or not UID_CHARS.contains(uid):
			errors.append("uid «%s»: нужен один символ 0-9A-Z" % uid)
		if uids.has(uid):
			errors.append("uid «%s» повторяется" % uid)
		uids[uid] = true
		if part(String(n.get("part", ""))) == null:
			errors.append("нет детали «%s»" % n.get("part", ""))
		if String(n.get("parent", "")) == "":
			roots += 1
	if not errors.is_empty():
		return errors
	if nodes_of(bp).is_empty():
		return errors
	if roots != 1:
		errors.append("корней %d, нужен один" % roots)
		return errors
	if is_weapon(bp):
		errors.append_array((bp as WeaponBlueprint).validate())
		errors.append_array(_weapon_anchor_errors(bp))
		return errors
	var body := bp as BodyBlueprint
	if part(String(find(bp, root_uid(bp)).get("part", ""))).kind != "core":
		errors.append("корень должен быть ядром")
		return errors
	for n in body.nodes:
		var uid := String(n.get("uid", ""))
		if String(n.get("mat", "")) != "":
			var me := body.mat_error(uid, String(n["mat"]))
			if me != "":
				errors.append(me)
		if String(n.get("joint", "")) != "":
			var je := body.joint_error(uid, String(n["joint"]))
			if je != "":
				errors.append(je)
	if not errors.is_empty():
		return errors
	errors.append_array(body._validate_assembly())
	return errors


## У оружия validate() не смотрит якоря: якорь есть у родителя, принимает вид, одна деталь на якорь.
static func _weapon_anchor_errors(bp: Resource) -> PackedStringArray:
	var errors: PackedStringArray = []
	var used := {}
	for n in nodes_of(bp):
		var p := String(n.get("parent", ""))
		if p == "":
			continue
		var an := anchor_name(String(n.get("anchor", "")))
		var anchors := anchors_of(bp, p)
		if not anchors.has(an):
			errors.append("у «%s» нет якоря %s" % [p, an])
			continue
		var acc: PackedStringArray = anchors[an]["accepts"]
		var d := part(String(n.get("part", "")))
		if not acc.is_empty() and d != null and not acc.has(d.kind):
			errors.append("%s не принимает %s" % [an, d.kind])
		var key := p + "/" + an
		if used.has(key):
			errors.append("на %s две детали" % an)
		used[key] = true
	return errors


## Ошибки правил игры (тело): validate() человеческими словами. Пусто — можно испытывать.
static func friendly_errors(bp: Resource) -> PackedStringArray:
	var out: PackedStringArray = []
	if bp == null:
		return out
	if is_weapon(bp):
		if nodes_of(bp).is_empty():
			return out
		for e in structural_errors(bp):
			out.append(_capital(e))
		return out
	var body := bp as BodyBlueprint
	if body.nodes.is_empty():
		out.append("Пусто: поставь ядро")
		return out
	for e in body.validate():
		out.append(_friendly(e))
	return out


## Не ошибки, но стоит знать: нет руки мышью, оружие некуда взять.
static func warnings(bp: BodyBlueprint) -> PackedStringArray:
	var out: PackedStringArray = []
	if bp == null:
		return out
	if bp.control.is_empty():
		out.append("Нет тяги: выбери деталь → «Настроить» → тяга ЛКМ (или Q)")
	if bp.weapon != null:
		var m := weapon_mount(bp)
		if String(m["uid"]) == "":
			out.append(String(m["reason"]))
	return out


static func _friendly(e: String) -> String:
	if e.begins_with("голов 0"):
		return "Голова обязательна — поставь голову на шею ядра"
	if e.begins_with("голов "):
		return "Голова должна быть одна"
	if e.begins_with("энергия "):
		var nums := _ints(e)
		if nums.size() >= 2:
			return "Перебор энергии: %d из %d" % [nums[0], nums[1]]
	if e.begins_with("управляемая деталь"):
		return "Деталь с тягой снята — выбери новую"
	if e.begins_with("рука мышью на"):
		return "Тяга стоит на детали без своего тела — поставь её на конечность заново"
	if e.begins_with("корн") or e.begins_with("корень"):
		return "В центре должно быть ядро"
	if e.begins_with("голова «"):
		return "Голова крепится только на шею ядра"
	# запасная сетка для строк BodyBlueprint._joint_error (в них uid, имена якорей, «auto»): check / check_joint переводят их сами
	if e.contains("нельзя приварить"):
		return "Эту деталь не приварить — сними сварку или деталь на её конце"
	if e.contains("нет мышцы"):
		return "У этого сустава нет мышцы — мотор и пружина тут ничего не дают"
	if e.contains("крепится намертво"):
		return "Эта деталь крепится намертво — шарнира у неё нет"
	return _capital(e)


static func _capital(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s


static func _ints(s: String) -> Array:
	var out: Array = []
	var cur := ""
	for ch in s + " ":
		if ch >= "0" and ch <= "9":
			cur += ch
		elif cur != "":
			out.append(int(cur))
			cur = ""
	return out


static func energy_used(bp: Resource) -> int:
	if bp is BodyBlueprint:
		return (bp as BodyBlueprint).energy_used()
	return 0


## Отказ по энергии: цена детали зависит от выноса (BodyBlueprint.reach_mult, WORKSHOP_V3.md §2), поэтому — итог после установки.
static func energy_reason(what: String, after: int, budget: int) -> String:
	return "Не хватает энергии на %s: будет %d / %d. Чем дальше от ядра, тем дороже" % [what, after, budget]


static func energy_budget(bp: Resource) -> int:
	return (bp as BodyBlueprint).energy_budget if bp is BodyBlueprint else 0


# ------------------------------------------------------------------ прикрутить / открутить

## Можно ли прикрутить деталь part_id на якорь anchor детали parent_uid (см. шапку: code / reason / replace / drops / energy_after).
static func check(bp: Resource, part_id: String, parent_uid: String, anchor: String) -> Dictionary:
	var r := {"ok": false, "code": "invalid", "reason": "", "replace": "", "drops": PackedStringArray(), "energy_after": energy_used(bp)}
	var d := part(part_id)
	if d == null:
		r["reason"] = "Нет такой детали"
		return r
	if find(bp, parent_uid).is_empty():
		r["reason"] = "Нет детали-родителя"
		return r
	var an := anchor_name(anchor)
	var anchors := anchors_of(bp, parent_uid)
	if not anchors.has(an):
		r["reason"] = "Нет такого якоря"
		return r
	if d.kind == "core":
		r["code"] = "core"
		r["reason"] = "Ядро — центр тела: перетащи его на старое ядро, чтобы заменить"
		return r
	var acc: PackedStringArray = anchors[an]["accepts"]
	if not acc.is_empty() and not acc.has(d.kind):
		r["code"] = "kind"
		r["reason"] = "Сюда %s не встанет" % KIND_TITLES.get(d.kind, d.kind)
		return r
	if not is_weapon(bp) and d.kind == "head" and (parent_uid != root_uid(bp) or an != "Anchor_Neck"):
		r["code"] = "head"
		r["reason"] = "Голова — только на шею ядра"
		return r
	# приваренный родитель: деталь со своим суставом на его auto-конце взяла бы группу от сварки (BODY_KIT.md §5.2) — отказ словами
	# игрока, а не строкой validate() с uid и «auto»; навершие, щиток, мод (fixed) — можно
	if bp is BodyBlueprint and KitJoint.is_weld(String(find(bp, parent_uid).get("joint", ""))) \
			and String((anchors[an] as Dictionary).get("joint_group", "")) == "auto" and not BodyBlueprint.is_fixed_part(d):
		var pd := def_of(bp, parent_uid)
		r["code"] = "welded"
		r["reason"] = "Деталь «%s» приварена: на её конец встанет только навершие, щиток или мод — верни ей шарнир «Ось»" \
			% (PartNames.of(pd) if pd != null else parent_uid)
		return r
	var trial: Resource = dup_body(bp as BodyBlueprint) if bp is BodyBlueprint else dup_weapon(bp as WeaponBlueprint)
	var res := _apply_attach(trial, part_id, parent_uid, an)
	r["replace"] = res.get("replace", "")
	r["drops"] = res.get("drops", PackedStringArray())
	r["face_lost"] = res.get("face_lost", "")
	if not bool(res.get("ok", false)):
		r["code"] = String(res.get("code", "invalid"))
		r["reason"] = String(res.get("reason", "Не встаёт"))
		return r
	if bp is BodyBlueprint:
		var after := (trial as BodyBlueprint).energy_used()
		r["energy_after"] = after
		if after > (bp as BodyBlueprint).energy_budget and after > energy_used(bp):
			r["code"] = "energy"
			r["reason"] = energy_reason("«%s»" % PartNames.of(d), after, (bp as BodyBlueprint).energy_budget)
			return r
	var errs := structural_errors(trial)
	if not errs.is_empty():
		r["code"] = "invalid"
		r["reason"] = _friendly(errs[0])
		return r
	r["ok"] = true
	r["code"] = "replace" if String(r["replace"]) != "" else ""
	return r


## Прикрутить (с проверкой): {ok, uid, code, reason, replace, drops, face_lost (id фото, снятого с заменённой головы, или "")}.
static func attach(bp: Resource, part_id: String, parent_uid: String, anchor: String) -> Dictionary:
	var c := check(bp, part_id, parent_uid, anchor)
	if not bool(c["ok"]):
		return c
	var res := _apply_attach(bp, part_id, parent_uid, anchor_name(anchor))
	c["uid"] = res.get("uid", "")
	return c


## Применить без проверок энергии и сборки (check зовёт это на копии). Свободный якорь — новый узел; занятый — замена на месте.
static func _apply_attach(bp: Resource, part_id: String, parent_uid: String, an: String) -> Dictionary:
	var occ := occupant(bp, parent_uid, an)
	if occ != "":
		var rr := _replace(bp, occ, part_id)
		rr["replace"] = occ
		return rr
	var uid := free_uid(bp, part_id, parent_uid, an)
	if uid == "":
		return {"ok": false, "code": "full", "reason": "Больше деталей не поместится (кончились номера)"}
	var n := {"uid": uid, "part": part_id, "parent": parent_uid, "anchor": an}
	if ActiveBlocks.is_active(part_id):
		n[ActiveBlocks.NODE_KEY] = 1   # новый активный блок сразу на канале 1 (Q)
	(bp.get("nodes") as Array).append(n)
	return {"ok": true, "uid": uid}


## Заменить деталь uid на part_id: uid остаётся (control и weapon_on не теряются), явное имя — только если префикс тела тот же,
## дети, которым нет якоря на новой детали (или вид не принимается), снимаются с поддеревом. Кит v2: mat остаётся, только если
## новая деталь красится (есть base_mat; материал по умолчанию — ключ стирается), joint — если тип допустим и для новой детали
## (у fixed-детали — декор, броня, attach fixed — шарнира нет; запреты weld — BodyBlueprint.joint_error). Покраска: другая деталь —
## paint и stickers стираются (слой и кадры наклеек — в кадре меша прежней), face остаётся только у головы кита
## (BodyPaint.face_plate_ok — то же правило, что у WorkshopPaint.set_face_image: у старых голов плашка утоплена или её нет);
## снятое фото — в результате «face_lost» (мастерская кладёт его наклейкой на лицо новой головы).
static func _replace(bp: Resource, uid: String, part_id: String) -> Dictionary:
	var n := find(bp, uid)
	var d := part(part_id)
	var old := part(String(n.get("part", "")))
	var body0 := bp as BodyBlueprint
	# префикс имени на ЭТОМ месте (у тела — BodyBlueprint.name_prefix_of: конечность кита на локте — LowerArm): «LowerArm_L» переживает
	# замену предплечья на конечность кита размера S (её name_prefix — UpperArm)
	var prefix0 := body0.name_prefix_of(uid) if body0 != null else (old.name_prefix if old != null else "")
	n["part"] = part_id
	if not ActiveBlocks.is_active(part_id):
		n.erase(ActiveBlocks.NODE_KEY)
	elif not n.has(ActiveBlocks.NODE_KEY):
		n[ActiveBlocks.NODE_KEY] = 1
	var prefix1 := body0.name_prefix_of(uid) if body0 != null else d.name_prefix
	if n.has("name") and (old == null or prefix1 != prefix0):
		n.erase("name")
	var new_anchors := BodyBlueprint.part_anchors(d)
	var drops: PackedStringArray = []
	var face_lost := ""
	for c in children_of(bp, uid):
		var an := anchor_name(String(c.get("anchor", "")))
		var cd := part(String(c.get("part", "")))
		var ok := new_anchors.has(an)
		if ok:
			var acc: PackedStringArray = new_anchors[an]["accepts"]
			ok = acc.is_empty() or (cd != null and acc.has(cd.kind))
		if not ok:
			drops.append_array(_remove_subtree(bp, String(c.get("uid", ""))))
	if bp is BodyBlueprint:
		var body := bp as BodyBlueprint
		var mid := String(n.get("mat", ""))
		if n.has("mat") and (mid == "" or d.base_mat == "" or mid == d.base_mat or body.mat_error(uid, mid) != ""):
			n.erase("mat")
		var jt := String(n.get("joint", ""))
		if n.has("joint") and (jt == "" or BodyBlueprint.is_fixed_part(d) or body.joint_error(uid, jt) != ""):
			n.erase("joint")
		# покраска (BODY_PAINT.md §4) — в кадре меша прежней детали: другая деталь — слой и наклейки снимаются; фото остаётся только
		# на голове кита (у неё плашка лица снаружи); со старой головы / не головы — снимается (face_lost)
		if old == null or old.id != d.id:
			n.erase("paint")
			n.erase("stickers")
			if not BodyPaint.face_plate_ok(d) and n.has("face"):
				face_lost = String(n["face"])
				n.erase("face")
		# деталь стала fixed (навершие вместо управляемой кисти): своего тела нет — рука мышью переезжает на тело-хозяина, как у
		# set_control (у ядра — снимается: ядром не управляют, warnings() подскажет), оружие — в другую кисть (weapon_mount)
		if body.is_fixed(uid):
			if body.control.has(uid):
				var h := host_uid(body, uid)
				var ctrl: PackedStringArray = []
				for c in body.control:
					var nc := c if c != uid else ("" if h == root_uid(body) else h)
					if nc != "" and not ctrl.has(nc):
						ctrl.append(nc)
				body.control = ctrl
				_sync_rmb(body, uid, h if h != root_uid(body) else "")
			if body.weapon_on == uid:
				body.weapon_on = String(weapon_mount(body)["uid"])
	return {"ok": true, "uid": uid, "drops": drops, "face_lost": face_lost}


## Корень: ядро тела / рукоять оружия. Пустой чертёж — новый корень, иначе замена корня (дети остаются, где есть якоря).
static func check_root(bp: Resource, part_id: String) -> Dictionary:
	var r := {"ok": false, "code": "invalid", "reason": "", "replace": "", "drops": PackedStringArray(), "energy_after": energy_used(bp)}
	var d := part(part_id)
	if d == null:
		return r
	var need := "handle" if is_weapon(bp) else "core"
	if d.kind != need:
		r["code"] = "kind"
		r["reason"] = "В основу встаёт только %s" % KIND_TITLES[need]
		return r
	var trial: Resource = dup_body(bp as BodyBlueprint) if bp is BodyBlueprint else dup_weapon(bp as WeaponBlueprint)
	var res := _apply_root(trial, part_id)
	r["replace"] = res.get("replace", "")
	r["drops"] = res.get("drops", PackedStringArray())
	if bp is BodyBlueprint:
		var after := (trial as BodyBlueprint).energy_used()
		r["energy_after"] = after
		if after > (bp as BodyBlueprint).energy_budget and after > energy_used(bp):
			r["code"] = "energy"
			r["reason"] = "Не хватает энергии"
			return r
	var errs := structural_errors(trial)
	if not errs.is_empty():
		r["reason"] = _friendly(errs[0])
		return r
	r["ok"] = true
	r["code"] = "replace" if String(r["replace"]) != "" else ""
	return r


static func set_root(bp: Resource, part_id: String) -> Dictionary:
	var c := check_root(bp, part_id)
	if not bool(c["ok"]):
		return c
	var res := _apply_root(bp, part_id)
	c["uid"] = res.get("uid", "")
	return c


static func _apply_root(bp: Resource, part_id: String) -> Dictionary:
	var ru := root_uid(bp)
	if ru != "":
		var rr := _replace(bp, ru, part_id)
		rr["replace"] = ru
		return rr
	var uid := "T" if not is_weapon(bp) else "0"
	var n := {"uid": uid, "part": part_id, "parent": "", "anchor": ""}
	if not is_weapon(bp):
		n["name"] = "Torso"
	(bp.get("nodes") as Array).append(n)
	return {"ok": true, "uid": uid}


## Открутить деталь с поддеревом. Возвращает снятые uid (пусто — нельзя: корень тела).
static func detach(bp: Resource, uid: String) -> PackedStringArray:
	var n := find(bp, uid)
	if n.is_empty():
		return PackedStringArray()
	if String(n.get("parent", "")) == "" and not is_weapon(bp):
		return PackedStringArray()
	return _remove_subtree(bp, uid)


static func _remove_subtree(bp: Resource, uid: String) -> PackedStringArray:
	var gone := subtree(bp, uid)
	var nodes: Array = bp.get("nodes")
	for i in range(nodes.size() - 1, -1, -1):
		if gone.has(String(nodes[i].get("uid", ""))):
			nodes.remove_at(i)
	if bp is BodyBlueprint:
		var body := bp as BodyBlueprint
		var ctrl: PackedStringArray = []
		for c in body.control:
			if not gone.has(c):
				ctrl.append(c)
		body.control = ctrl
		_sync_rmb(body)
		if gone.has(body.weapon_on):
			body.weapon_on = ""
	return gone


## Свободный uid для нового узла: не занят, имя тела и сустава не совпадают с уже существующими (явные имена пресета human).
static func free_uid(bp: Resource, part_id: String, parent_uid: String, an: String) -> String:
	var used := {}
	for n in nodes_of(bp):
		used[String(n.get("uid", ""))] = true
	var prefer := "0123456789ABCDEFGIJKMNOPQSUVWXYZHLRT" if not is_weapon(bp) else UID_CHARS
	var d := part(part_id)
	# fixed-деталь живёт в теле хозяина: своих имён нет (у нового узла ключа joint нет — решает сама деталь)
	var own_body := d != null and (not BodyBlueprint.is_fixed_part(d) or parent_uid == "")
	for ch in prefer:
		if used.has(ch):
			continue
		if not is_weapon(bp) and own_body:
			var body := bp as BodyBlueprint
			body.nodes.append({"uid": ch, "part": part_id, "parent": parent_uid, "anchor": an})
			var bn := body.body_name_of(ch)
			var jn := body.joint_name_of(ch)
			body.nodes.pop_back()
			if _name_taken(body, bn, jn):
				continue
		return ch
	return ""


static func _name_taken(body: BodyBlueprint, bn: String, jn: String) -> bool:
	for n in body.nodes:
		var u := String(n.get("uid", ""))
		var d := part(String(n.get("part", "")))
		if d == null or body.is_fixed(u):
			continue
		if body.body_name_of(u) == bn:
			return true
		if jn != "" and body.joint_name_of(u) == jn:
			return true
	return false


# ------------------------------------------------------------------ рука мышью и оружие

## Тело, которым управляется деталь: fixed-деталь (броня, декор, навершие на теле, сваренная) — её хозяин по цепочке.
static func host_uid(bp: Resource, uid: String) -> String:
	var cur := uid
	var guard := 0
	while guard < 64:
		guard += 1
		var n := find(bp, cur)
		if n.is_empty() or part(String(n.get("part", ""))) == null or not is_fixed(bp, cur):
			return cur
		cur = String(n.get("parent", ""))
	return cur


## Тяга на детали (WORKSHOP_V3.md §3): {ok, uid, reason, cleared, button: "lmb" | "rmb" | "", code}. Клик по детали без тяги —
## тяга ЛКМ (первая бесплатна, дальше BodyBlueprint.PULL_ENERGY × вынос; не хватает энергии — отказ code "energy"), по ЛКМ-тяге —
## переводит на ПКМ, по ПКМ-тяге — снимает.
static func set_control(bp: BodyBlueprint, uid: String) -> Dictionary:
	if find(bp, uid).is_empty():
		return {"ok": false, "uid": "", "reason": "Нет такой детали", "code": "invalid"}
	var h := host_uid(bp, uid)
	if h == root_uid(bp):
		return {"ok": false, "uid": "", "reason": "Ядро — это ты сам: выбери конечность, кисть или цепь", "code": "core"}
	if bp.control.has(h):
		if not bp.control_rmb.has(h):
			var rmb: PackedStringArray = bp.control_rmb.duplicate()
			rmb.append(h)
			bp.control_rmb = rmb
			return {"ok": true, "uid": h, "reason": "", "cleared": false, "button": "rmb", "code": "rmb"}
		var ctrl: PackedStringArray = []
		for c in bp.control:
			if c != h:
				ctrl.append(c)
		bp.control = ctrl
		_sync_rmb(bp, h)
		return {"ok": true, "uid": h, "reason": "", "cleared": true, "button": "", "code": "cleared"}
	if bp.control.size() >= MAX_CONTROL:
		return {"ok": false, "uid": h, "reason": "Тяг уже %d — больше нельзя" % MAX_CONTROL, "code": "max"}
	var trial := dup_body(bp)
	var ctrl2: PackedStringArray = trial.control.duplicate()
	ctrl2.append(h)
	trial.control = ctrl2
	var after := trial.energy_used()
	if after > bp.energy_budget and after > bp.energy_used():
		return {"ok": false, "uid": h, "reason": energy_reason("тягу", after, bp.energy_budget), "code": "energy"}
	bp.control = ctrl2
	return {"ok": true, "uid": h, "reason": "", "cleared": false, "button": "lmb", "code": "lmb"}


## control_rmb — только uid из control; gone — снятый uid, moved — куда переехала его тяга ("" — никуда).
static func _sync_rmb(bp: BodyBlueprint, gone: String = "", moved: String = "") -> void:
	var rmb: PackedStringArray = []
	for u in bp.control_rmb:
		var nu := u if u != gone else moved
		if nu != "" and bp.control.has(nu) and not rmb.has(nu):
			rmb.append(nu)
	bp.control_rmb = rmb


## Куда повесить крафтовое оружие: {uid, kind: "hand" | "end", reason}. Порядок: управляемая кисть → кисть ниже управляемой детали →
## любая кисть (правая раньше) → конец управляемой детали (у неё нет кисти: оружие продолжает конечность) → некуда.
static func weapon_mount(bp: BodyBlueprint) -> Dictionary:
	var ctrl := String(bp.control[0]) if not bp.control.is_empty() else ""
	if ctrl != "" and _is_hand(bp, ctrl):
		return {"uid": ctrl, "kind": "hand", "reason": ""}
	if ctrl != "":
		for u in subtree(bp, ctrl):
			if _is_hand(bp, u):
				return {"uid": u, "kind": "hand", "reason": ""}
	var hands: Array = []
	for n in bp.nodes:
		var u := String(n.get("uid", ""))
		if _is_hand(bp, u):
			hands.append(u)
	hands.sort_custom(func(a: String, b: String) -> bool: return int(is_mirrored(bp, a)) > int(is_mirrored(bp, b)))
	if not hands.is_empty():
		return {"uid": hands[0], "kind": "hand", "reason": ""}
	if ctrl != "":
		var d := def_of(bp, ctrl)
		if d != null and not is_fixed(bp, ctrl):
			return {"uid": ctrl, "kind": "end", "reason": ""}
	return {"uid": "", "kind": "", "reason": "Оружие некуда взять: поставь кисть или дай детали тягу"}


static func _kind(bp: Resource, uid: String) -> String:
	var d := def_of(bp, uid)
	return d.kind if d != null else ""


## Кисть со своим телом: сваренная (joint "weld") — часть предплечья, WeaponPickup держал бы оружие телом-хозяином.
static func _is_hand(bp: Resource, uid: String) -> bool:
	return _kind(bp, uid) == "hand" and not is_fixed(bp, uid)


# ------------------------------------------------------------------ кит v2: материал и тип шарнира (BODY_KIT.md §4, §5.2, §5.5)

## Название материала ("" → «не красится»).
static func mat_title(mat_id: String) -> String:
	var m := MaterialDef.get_def(mat_id)
	return m.title if m != null else ("не красится" if mat_id == "" else mat_id)


## Физика материала одной строкой: «плотность ×2.2 · трение 0.5 · упругость 0.1 · магнит».
static func mat_line(mat_id: String) -> String:
	var m := MaterialDef.get_def(mat_id)
	if m == null:
		return ""
	var s := "плотность ×%s · трение %s · упругость %s" % [_num(m.density), _num(m.friction), _num(m.bounce)]
	if not is_equal_approx(m.body_mult, 1.0):
		s += " · удар ×%s" % _num(m.body_mult)
	if m.iron:
		s += " · магнит"
	return s


static func _num(x: float) -> String:
	return String.num(snappedf(x, 0.01))


static func joint_title(jt: String) -> String:
	return String(KitJoint.info(jt).get("title", jt)) if jt != "" else "намертво"


## Можно ли покрасить деталь uid материалом mat_id: {ok, code, reason, changed, mat_before, mass_before, mass_after}.
## code: "" — можно; "same" — уже этот материал (ok, ничего не меняется); "paint" — деталь без base_mat; "unknown" — нет материала;
## "invalid" — нет детали / не тело.
static func check_material(bp: Resource, uid: String, mat_id: String) -> Dictionary:
	var r := {"ok": false, "code": "invalid", "reason": "Нет такой детали", "changed": false, "mat_before": "", "mass_before": 0.0,
		"mass_after": 0.0}
	if not bp is BodyBlueprint or find(bp, uid).is_empty():
		return r
	var body := bp as BodyBlueprint
	var d := def_of(bp, uid)
	if d == null:
		return r
	r["mat_before"] = body.node_mat(uid)
	r["mass_before"] = body.node_mass(uid)
	r["mass_after"] = r["mass_before"]
	if MaterialDef.get_def(mat_id) == null:
		r["code"] = "unknown"
		r["reason"] = "Нет материала «%s»" % mat_id
		return r
	if d.base_mat == "":
		r["code"] = "paint"
		r["reason"] = "%s не красится: материал меняется только у деталей кита" % PartNames.of(d)
		return r
	var err := body.mat_error(uid, mat_id)
	if err != "":
		r["reason"] = _capital(err)
		return r
	r["ok"] = true
	r["reason"] = ""
	if String(r["mat_before"]) == mat_id:
		r["code"] = "same"
		return r
	var trial := dup_body(body)
	_apply_material(trial, uid, mat_id)
	r["mass_after"] = trial.node_mass(uid)
	r["code"] = ""
	r["changed"] = true
	return r


## Покрасить (с проверкой): материал по умолчанию (PartDef.base_mat) — ключ mat стирается.
static func set_material(bp: Resource, uid: String, mat_id: String) -> Dictionary:
	var r := check_material(bp, uid, mat_id)
	if bool(r["ok"]) and bool(r["changed"]):
		_apply_material(bp as BodyBlueprint, uid, mat_id)
	r["uid"] = uid
	return r


static func _apply_material(bp: BodyBlueprint, uid: String, mat_id: String) -> void:
	var n := find(bp, uid)
	var d := part(String(n.get("part", "")))
	if d != null and mat_id == d.base_mat:
		n.erase("mat")
	else:
		n["mat"] = mat_id


## Можно ли поставить узлу uid тип шарнира jt (связь с родителем): {ok, code, reason, changed, joint_before, energy_after}.
## code: "" — можно; "same" — уже так (ok); "root" — корень; "fixed" — деталь крепится намертво сама (декор, броня, attach fixed);
## "rule" — запрет weld (голова, рука мышью, auto-сустав ребёнка), мотор / пружина на суставе без мышцы (лодыжка) и прочие ошибки
## BodyBlueprint.joint_error (причина — словами игрока, _joint_refusal); "energy" — не влезает
## в бюджет Ядра; "invalid" — нет детали, неизвестный тип, сборка не сходится.
static func check_joint(bp: Resource, uid: String, jt: String) -> Dictionary:
	var r := {"ok": false, "code": "invalid", "reason": "Нет такой детали", "changed": false, "joint_before": "",
		"energy_after": energy_used(bp)}
	if not bp is BodyBlueprint or find(bp, uid).is_empty():
		return r
	var body := bp as BodyBlueprint
	var n := find(bp, uid)
	var d := def_of(bp, uid)
	if d == null:
		return r
	if not KitJoint.is_type(jt):
		r["reason"] = "Нет такого шарнира «%s»" % jt
		return r
	if String(n.get("parent", "")) == "":
		r["code"] = "root"
		r["reason"] = "%s — корень тела, сустава с родителем нет" % PartNames.of(d)
		return r
	if BodyBlueprint.is_fixed_part(d):
		r["code"] = "fixed"
		r["reason"] = "Деталь «%s» крепится намертво — шарнира нет (%s)" % [PartNames.of(d), KIND_TITLES.get(d.kind, d.kind)]
		return r
	var cur := String(n.get("joint", ""))
	r["joint_before"] = cur if cur != "" else KitJoint.DEFAULT
	var err := body.joint_error(uid, jt)
	if err != "":
		r["code"] = "rule"
		r["reason"] = _joint_refusal(body, uid, d, jt, err)
		return r
	if String(r["joint_before"]) == jt:
		r["ok"] = true
		r["code"] = "same"
		r["reason"] = ""
		return r
	var trial := dup_body(body)
	_apply_joint(trial, uid, jt)
	var after := trial.energy_used()
	r["energy_after"] = after
	if after > body.energy_budget and after > body.energy_used():
		r["code"] = "energy"
		r["reason"] = energy_reason("шарнир «%s»" % joint_title(jt), after, body.energy_budget)
		return r
	var errs := structural_errors(trial)
	if not errs.is_empty():
		r["reason"] = _friendly(errs[0])
		return r
	r["ok"] = true
	r["code"] = ""
	r["reason"] = ""
	r["changed"] = true
	return r


## Отказ BodyBlueprint.joint_error словами игрока — названия деталей, без uid, имён якорей и «(auto)». Сами строки joint_error —
## диагностика validate() (их сверяет tests/kit_probe), поэтому перевод здесь, а не там; неизвестный случай — _friendly.
static func _joint_refusal(body: BodyBlueprint, uid: String, d: PartDef, jt: String, err: String) -> String:
	if KitJoint.is_weld(jt):
		if d.kind == "head":
			return "Голову не приварить — она держится на шее"
		if body.control.has(uid):
			return "Деталь «%s» ведёт тяга — сначала сними её (Q), потом приваривай" % PartNames.of(d)
		var anchors := BodyBlueprint.part_anchors(d)
		for c in children_of(body, uid):
			if body.is_fixed(String(c.get("uid", ""))):
				continue
			var a: Dictionary = anchors.get(String(c.get("anchor", "")), {})
			if String(a.get("joint_group", "")) == "auto":
				var cd := part(String(c.get("part", "")))
				return "Деталь «%s» не приварить: на её конце держится «%s» на своём суставе — сначала сними или приварь ту деталь" \
					% [PartNames.of(d), PartNames.of(cd) if cd != null else "деталь"]
	elif err.contains("нет мышцы"):
		var g := body.anchor_group_of(uid)
		return "Деталь «%s» висит на суставе без мышцы (%s): шарнир «%s» ничего не усилит" % [PartNames.of(d), GROUP_TITLES.get(g, g),
			joint_title(jt)]
	return _friendly(err)


## Поставить тип шарнира (с проверкой): "pin" — ключ joint стирается (по умолчанию).
static func set_joint(bp: Resource, uid: String, jt: String) -> Dictionary:
	var r := check_joint(bp, uid, jt)
	if bool(r["ok"]) and bool(r["changed"]):
		_apply_joint(bp as BodyBlueprint, uid, jt)
	r["uid"] = uid
	return r


static func _apply_joint(bp: BodyBlueprint, uid: String, jt: String) -> void:
	var n := find(bp, uid)
	if jt == KitJoint.DEFAULT:
		n.erase("joint")
	else:
		n["joint"] = jt


# ------------------------------------------------------------------ сохранение

## Имя файла из названия: латиница, цифры, «_» (кириллица транслитом).
static func slug(title: String) -> String:
	const TR := {"а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e", "ж": "zh", "з": "z", "и": "i", "й": "y", "к": "k",
		"л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f", "х": "h", "ц": "c",
		"ч": "ch", "ш": "sh", "щ": "sch", "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya"}
	var out := ""
	for ch in title.to_lower():
		if TR.has(ch):
			out += TR[ch]
		elif (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif not out.ends_with("_"):
			out += "_"
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	return out.substr(0, 40) if out != "" else "build"


static func save_path(name: String) -> String:
	return SAVE_DIR + name + ".tres"


## Сохранить копию чертежа (с оружием) в user://blueprints/<name>.tres. Возвращает путь или "" при ошибке.
static func save(bp: BodyBlueprint, name: String) -> String:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var copy := dup_body(bp)
	copy.id = name
	var path := save_path(name)
	var err := ResourceSaver.save(copy, path)
	return path if err == OK else ""


static func load_saved(path: String) -> BodyBlueprint:
	if not FileAccess.file_exists(path):
		return null
	var r := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	return dup_body(r as BodyBlueprint) if r is BodyBlueprint else null


## Сохранённые чертежи: [{path, name, title, energy, parts, time}], свежие сначала; автосохранение — последним.
static func list_saved() -> Array:
	var out: Array = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var path := SAVE_DIR + f
		var bp := load_saved(path)
		if bp == null:
			continue
		out.append({"path": path, "name": f.get_basename(), "title": bp.title if bp.title != "" else f.get_basename(),
			"energy": bp.energy_used(), "parts": bp.nodes.size(), "time": FileAccess.get_modified_time(path),
			"auto": f.get_basename() == AUTOSAVE})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["auto"]) != bool(b["auto"]):
			return not bool(a["auto"])
		return int(a["time"]) > int(b["time"]))
	return out

# ------------------------------------------------------------------ зеркало, паспорт детали (UI v0.2)

## Прочность материала для паспорта детали и сводки «Прочность» (0…1): металл крепче дерева. Пока показатель мастерской — в бою
## не читается (урон и HP от него не зависят); нет в таблице — 0.5.
const MAT_DURABILITY := {
	"iron": 1.0, "brass": 0.9, "rust": 0.8, "rust_red": 0.85, "bone": 0.6, "rubber": 0.7, "wood_dark": 0.6, "wood": 0.5,
	"maple": 0.5, "planks": 0.45, "paint_red": 0.5, "paint_blue": 0.5, "paint_yellow": 0.5, "paint_white": 0.5, "paint_green": 0.5,
	"cloth": 0.3,
}
static var _length_cache: Dictionary = {}


## Зеркальное имя якоря: Anchor_Shoulder_L ↔ Anchor_Shoulder_R; "" — якорь по центру.
static func mirror_anchor(an: String) -> String:
	if an.ends_with("_L"):
		return an.substr(0, an.length() - 2) + "_R"
	if an.ends_with("_R"):
		return an.substr(0, an.length() - 2) + "_L"
	return ""


## Узел на зеркальном месте узла uid ("" — нет / деталь по центру): тот же якорь у зеркального родителя или зеркальный якорь того же.
static func mirror_uid(bp: BodyBlueprint, uid: String) -> String:
	var n := find(bp, uid)
	var p := String(n.get("parent", ""))
	if n.is_empty() or p == "":
		return ""
	var ma := mirror_anchor(String(n.get("anchor", "")))
	if ma != "":
		return occupant(bp, p, ma)
	var mp := mirror_uid(bp, p)
	return occupant(bp, mp, String(n.get("anchor", ""))) if mp != "" else ""


## Куда встанет зеркальная копия узла uid: [родитель, якорь]; [] — детали по центру зеркалить некуда.
static func mirror_place(bp: BodyBlueprint, uid: String) -> Array:
	var n := find(bp, uid)
	var p := String(n.get("parent", ""))
	if n.is_empty() or p == "":
		return []
	var ma := mirror_anchor(String(n.get("anchor", "")))
	if ma != "":
		return [p, ma]
	var mp := mirror_uid(bp, p)
	return [mp, String(n.get("anchor", ""))] if mp != "" and mp != p else []


## Копия поддерева uid на зеркальное место (детали, материалы, шарниры, углы покоя; тяги не копируются). Занятое место — заменяется
## со своим поддеревом. {ok, code, reason, uid (корень копии), count, replaced}.
static func mirror_subtree(bp: BodyBlueprint, uid: String) -> Dictionary:
	var place := mirror_place(bp, uid)
	if place.is_empty():
		return {"ok": false, "code": "center", "reason": "Деталь по центру — зеркалить некуда (выбери деталь сбоку: руку, ногу, наплечник)"}
	var replaced := occupant(bp, String(place[0]), String(place[1]))
	if replaced != "":
		if subtree(bp, uid).has(replaced) or subtree(bp, replaced).has(uid):
			return {"ok": false, "code": "self", "reason": "Зеркальное место занято этой же веткой"}
		detach(bp, replaced)
	var queue: Array = [[uid, String(place[0]), String(place[1])]]
	var first := ""
	var count := 0
	while not queue.is_empty():
		var q: Array = queue.pop_front()
		var src := find(bp, String(q[0]))
		var part_id := String(src.get("part", ""))
		var c := check(bp, part_id, String(q[1]), String(q[2]))
		if not bool(c["ok"]):
			var d := part(part_id)
			return {"ok": false, "code": String(c["code"]), "reason": energy_reason("зеркальную копию", int(c["energy_after"]), bp.energy_budget)
				if String(c["code"]) == "energy" else "Зеркально не встаёт «%s»: %s" % [PartNames.of(d) if d != null else part_id, c["reason"]]}
		var res := _apply_attach(bp, part_id, String(q[1]), String(q[2]))
		var nu := String(res.get("uid", ""))
		var dst := find(bp, nu)
		for k in ["mat", "joint", "rest_deg", ActiveBlocks.NODE_KEY]:
			if src.has(k):
				dst[k] = src[k]
		if first == "":
			first = nu
		count += 1
		for ch in children_of(bp, String(q[0])):
			queue.append([String(ch["uid"]), nu, String(ch.get("anchor", ""))])
	if bp.energy_used() > bp.energy_budget:
		return {"ok": false, "code": "energy", "reason": energy_reason("зеркальную копию", bp.energy_used(), bp.energy_budget)}
	var errs := structural_errors(bp)
	if not errs.is_empty():
		return {"ok": false, "code": "invalid", "reason": _friendly(errs[0])}
	return {"ok": true, "code": "ok", "reason": "", "uid": first, "count": count, "replaced": replaced}


## Копия поддерева src_uid чертежа src (все свойства узлов: деталь, материал, шарнир, угол покоя, покраска, наклейки; кроме uid,
## родителя, якоря и явного имени) в dst на якорь anchor детали parent (v0.3: перенос ветки мышью, дубликат ветки). Занятый якорь —
## замена, как у attach. {ok, code, reason, uid (корень копии), map: {старый uid: новый}, count}.
static func graft_subtree(dst: BodyBlueprint, src: BodyBlueprint, src_uid: String, parent: String, anchor: String) -> Dictionary:
	var queue: Array = [[src_uid, parent, anchor_name(anchor)]]
	var map := {}
	var first := ""
	while not queue.is_empty():
		var q: Array = queue.pop_front()
		var sn := find(src, String(q[0]))
		var part_id := String(sn.get("part", ""))
		var c := check(dst, part_id, String(q[1]), String(q[2]))
		if not bool(c["ok"]):
			var d := part(part_id)
			return {"ok": false, "code": String(c["code"]), "map": map,
				"reason": energy_reason("«%s»" % (PartNames.of(d) if d != null else part_id), int(c["energy_after"]), dst.energy_budget)
				if String(c["code"]) == "energy" else String(c["reason"])}
		var res := _apply_attach(dst, part_id, String(q[1]), String(q[2]))
		var nu := String(res.get("uid", ""))
		var dn := find(dst, nu)
		# на занятом разъёме _apply_attach меняет деталь на месте и оставляет свойства прежней (краска, шарнир, угол покоя) —
		# копия / перенос несут только свои
		for k in dn.keys():
			if not String(k) in ["uid", "parent", "anchor", "name", "part"] and not sn.has(k):
				dn.erase(k)
		for k in sn:
			if not String(k) in ["uid", "parent", "anchor", "name", "part"]:
				var v: Variant = sn[k]
				dn[k] = v.duplicate(true) if v is Dictionary or v is Array else v
		map[String(q[0])] = nu
		if first == "":
			first = nu
		for ch in children_of(src, String(q[0])):
			queue.append([String(ch["uid"]), nu, String(ch.get("anchor", ""))])
	if dst.energy_used() > dst.energy_budget:
		return {"ok": false, "code": "energy", "map": map, "reason": energy_reason("эту ветку", dst.energy_used(), dst.energy_budget)}
	var errs := structural_errors(dst)
	if not errs.is_empty():
		return {"ok": false, "code": "invalid", "map": map, "reason": _friendly(errs[0])}
	return {"ok": true, "code": "ok", "reason": "", "uid": first, "map": map, "count": map.size()}


## Перенос ветки uid на якорь anchor детали parent (v0.3: тащишь деталь с куклы). Возвращает {ok, reason, bp (новый чертёж), uid}.
## Тяги, ПКМ-тяги и держатель оружия переезжают вместе с деталями (uid меняются — по map).
static func move_subtree(bp: BodyBlueprint, uid: String, parent: String, anchor: String) -> Dictionary:
	if String(find(bp, uid).get("parent", "")) == "":
		return {"ok": false, "code": "root", "reason": "Ядро не переносится — перетащи другое ядро поверх"}
	if subtree(bp, uid).has(parent):
		return {"ok": false, "code": "self", "reason": "Ветку нельзя повесить на саму себя"}
	var trial := dup_body(bp)
	detach(trial, uid)
	var r := graft_subtree(trial, bp, uid, parent, anchor)
	if not bool(r["ok"]):
		return r
	# тяги и держатель оружия: переехавшие — по map, остальные — только если пережили пересадку (замена на разъёме снимает
	# несовместимых детей вместе с их тягами; их uid могли уже раздать новым деталям)
	var m: Dictionary = r["map"]
	var ctrl: PackedStringArray = []
	for c in bp.control:
		var nc := String(m[c]) if m.has(c) else (String(c) if trial.control.has(c) else "")
		if nc != "" and not find(trial, nc).is_empty() and not is_fixed(trial, nc) and not ctrl.has(nc):
			ctrl.append(nc)
	for c in trial.control:
		if not ctrl.has(c) and not m.values().has(c):
			ctrl.append(c)
	trial.control = ctrl
	var rmb: PackedStringArray = []
	for c in bp.control_rmb:
		var nc := String(m[c]) if m.has(c) else (String(c) if trial.control_rmb.has(c) else "")
		if ctrl.has(nc) and not rmb.has(nc):
			rmb.append(nc)
	trial.control_rmb = rmb
	if bp.weapon_on != "":
		trial.weapon_on = String(m[bp.weapon_on]) if m.has(bp.weapon_on) else trial.weapon_on
	# энергия — с тягами на новом выносе (graft считал без них: detach снял их вместе с веткой)
	var after := trial.energy_used()
	if after > trial.energy_budget and after > bp.energy_used():
		return {"ok": false, "code": "energy", "map": m, "reason": energy_reason("перенос", after, trial.energy_budget)}
	r["bp"] = trial
	return r


## Длина детали, м: наибольший размер её форм столкновения (кэш по id).
static func part_length(d: PartDef) -> float:
	if d == null or d.scene == null:
		return 0.0
	if _length_cache.has(d.id):
		return _length_cache[d.id]
	var inst := d.scene.instantiate()
	var box := AABB()
	var first := true
	for c in inst.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
			var h := ModularDoll._shape_half((c as CollisionShape3D).shape)
			var w: AABB = (c as Node3D).transform * AABB(-h, h * 2.0)
			box = w if first else box.merge(w)
			first = false
	inst.free()
	var l := 0.0 if first else maxf(box.size.x, maxf(box.size.y, box.size.z))
	_length_cache[d.id] = l
	return l


## Прочность детали 0…1 (материал узла или детали по умолчанию; броня и щитки крепче, ядро — чуть). Показатель мастерской.
static func part_durability(d: PartDef, mat_id := "") -> float:
	if d == null:
		return 0.0
	var m := mat_id if mat_id != "" else (d.base_mat if d.base_mat != "" else d.material)
	var v := float(MAT_DURABILITY.get(m, 0.5))
	if d.kind in ["plate", "armor"]:
		v += 0.25
	elif d.kind == "core":
		v += 0.1
	return clampf(v, 0.0, 1.0)


## Паспорт детали словами (правая панель): что она делает в бою.
static func part_desc(d: PartDef) -> String:
	if d == null:
		return ""
	var lines: PackedStringArray = []
	match d.kind:
		"core": lines.append("Ядро — центр тела: к нему крепится всё остальное, чем дальше от него, тем дороже энергия.")
		"head": lines.append("Голова: удар В неё ×%.1f — береги её." % Tuning.HEAD_HIT_MULT)
		"hand": lines.append("Кисть: хват, бросок и удары. Удар В кисть почти не проходит (блок ×%.2f)." % Tuning.HAND_HIT_MULT)
		"foot": lines.append("Стопа: опора и пинок.")
		"limb": lines.append("Звено конечности: длиннее — дальше достаёт, но дороже по энергии.")
		"joint", "chain": lines.append("Связующее звено: гибкость и размах.")
		"plate", "armor": lines.append("Броня: сливается с деталью-хозяином, добавляет массу и прочность.")
		"deco":
			if ActiveBlocks.is_active(d.id):
				var ad := ActiveBlocks.def_of(d.id)
				var cost := "%.0f заряда за выстрел" % float(ad["cost"]) if String(ad["action"]) == "gun" else "%.0f заряда/с" % float(ad["cost"])
				lines.append("Активный блок: %s. Работает, пока зажата клавиша его канала; тратит %s." % [String(ad["hint"]), cost])
			else:
				lines.append("Декор: сливается с деталью-хозяином.")
		"weapon_head": lines.append("Навершие: на оружии — множитель урона ×%.2f; на теле — масса и форма." % d.weapon_mult)
		_: lines.append(String(KIND_TITLES.get(d.kind, d.kind)).capitalize() + ".")
	if ActiveBlocks.PASSIVE.has(d.id):
		lines.append("Особое свойство: %s." % String(ActiveBlocks.PASSIVE[d.id]["hint"]))
	var sm := minf(d.body_mult if BodyBlueprint.is_fixed_part(d) else d.hit_mult, Tuning.SHAPE_MULT_MAX)
	match d.hit_profile:
		"sharp": lines.append("Колющая форма: до ×%.2f на медленном точном тычке, на быстром ударе ×1." % sm)
		"blunt": lines.append("Дробящая форма: до ×%.2f на размахе и рывке, на медленном ×1." % sm)
		"soft": lines.append("Мягкая: бьёт слабее (×%.2f)." % sm)
	return " ".join(lines)
