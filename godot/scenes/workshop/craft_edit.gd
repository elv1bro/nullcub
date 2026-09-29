## Правки чертежей в мастерской (docs/plan-demo/BODY_CRAFT.md §1–4, CONCEPT_V2 §12 «взял деталь → поднёс к anchor → CLICK»).
## Только данные, без сцены: этим пользуются мастерская (scenes/workshop/workshop_build.gd) и проба tests/workshop_probe.gd.
## Формат чертежей не меняется: BodyBlueprint / WeaponBlueprint, nodes — {uid, part, parent, anchor, rest_deg?, name?}.
##
## Операции (body — BodyBlueprint, weapon — WeaponBlueprint; обе — «деталь на якорь родителя»):
##   check(bp, part, parent, anchor)  — можно ли прикрутить: {ok, code, reason, replace, energy_after, drops}; code:
##       ""        — можно (якорь свободен);
##       "replace" — можно, якорь занят: деталь заменяется, её дети, которым нет места на новой, снимаются (drops);
##       "kind"    — якорь не принимает этот вид; "energy" — не влезает в бюджет Ядра; "head" — голова только на шею;
##       "core"    — ядро не крепится на якорь (только заменить ядро); "invalid" — сборка не сошлась (текст validate).
##   attach(...) — то же и применить: новый узел получает свободный uid (имя тела и сустава не совпадают с чужими явными
##       именами пресета human: «UpperArm_L» у узла 1 — новый UpperArm не получит uid L); замена оставляет uid (и явное имя, если
##       префикс тела тот же), чтобы не терялись control / weapon_on.
##   set_root(...) — ядро (у тела) / рукоять (у оружия) в корень: пустой чертёж — новый корень, иначе замена.
##   detach(bp, uid) — открутить с поддеревом (корень тела не снимается; корень оружия — верстак пуст).
##   set_control(bp, uid) — рука мышью: не больше MAX_CONTROL (сейчас 1, новая пометка заменяет старую, повторная снимает);
##       fixed-деталь (броня) — управляется тело-хозяин; ядро нельзя.
##   weapon_mount(bp) — куда вешать крафтовое оружие: кисть управляемой цепи, иначе любая кисть, иначе конец управляемой детали
##       (контракт §2: «оружие на указанной детали»), иначе пусто с подсказкой.
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
const BODY_PRESETS := ["human", "spider", "long_arm", "big_arm", "legless", "junk", "flail"]
const WEAPON_PRESETS := ["mallet", "hammer", "spiked_hammer", "heavy_hammer", "long_hammer", "flail", "sword", "axe", "concept_hammer"]
## Полки мастерской: вкладка → виды деталей. Ударные навершия есть и у тела («тело становится частью оружия», CONCEPT_V2 §8).
const BODY_SHELVES := [
	{"id": "core", "title": "Ядро", "kinds": ["core"]},
	{"id": "head", "title": "Головы", "kinds": ["head"]},
	{"id": "limb", "title": "Конечности", "kinds": ["limb"]},
	{"id": "end", "title": "Кисти, стопы", "kinds": ["hand", "foot"]},
	{"id": "joint", "title": "Суставы, цепь", "kinds": ["joint", "chain"]},
	{"id": "plate", "title": "Броня, ударное", "kinds": ["plate", "weapon_head"]},
]
const WEAPON_SHELVES := [
	{"id": "handle", "title": "Рукояти", "kinds": ["handle"]},
	{"id": "weapon_head", "title": "Навершия", "kinds": ["weapon_head"]},
	{"id": "mod", "title": "Моды", "kinds": ["mod"]},
	{"id": "chain", "title": "Цепь", "kinds": ["chain"]},
]
const KIND_ORDER := ["core", "head", "limb", "hand", "foot", "joint", "chain", "plate", "handle", "weapon_head", "mod"]
const KIND_TITLES := {
	"core": "ядро", "head": "голова", "limb": "конечность", "hand": "кисть", "foot": "стопа", "joint": "сустав", "chain": "цепь",
	"plate": "броня", "handle": "рукоять", "weapon_head": "навершие", "mod": "мод",
}
const MAX_CONTROL := 1
const UID_CHARS := BodyBlueprint.UID_CHARS

static var _parts_cache: Array[PartDef] = []
static var _scene_names: Dictionary = {}   # путь сцены детали -> PackedStringArray имён CollisionShape3D


# ------------------------------------------------------------------ детали

## Все PartDef из data/body/parts, по порядку KIND_ORDER, внутри — по энергии и массе.
static func all_parts() -> Array[PartDef]:
	if not _parts_cache.is_empty():
		return _parts_cache
	var out: Array[PartDef] = []
	var dir := DirAccess.open(PARTS_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		var fn := f.trim_suffix(".remap")
		if not fn.ends_with(".tres"):
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
		if kinds.has(d.kind):
			out.append(d)
	return out


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
	var g := (bp as BodyBlueprint).joint_group_of(uid)
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
	out.weapon = dup_weapon(bp.weapon as WeaponBlueprint) if bp.weapon is WeaponBlueprint else null
	out.weapon_on = bp.weapon_on
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
	if not ResourceLoader.exists(path):
		return null
	return dup_body(load(path) as BodyBlueprint)


static func load_weapon_preset(id: String) -> WeaponBlueprint:
	var path := WEAPON_PRESET_DIR + id + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return dup_weapon(load(path) as WeaponBlueprint)


## Сигнатура узлов для сравнения (проба сохранения): отсортированные строки uid|part|parent|anchor|rest|name.
static func signature(bp: Resource) -> PackedStringArray:
	var out: PackedStringArray = []
	for n in nodes_of(bp):
		out.append("%s|%s|%s|%s|%s|%s" % [n.get("uid", ""), n.get("part", ""), n.get("parent", ""), anchor_name(String(n.get("anchor", ""))) if String(n.get("parent", "")) != "" else "",
			str(n.get("rest_deg", "")), n.get("name", "")])
	out.sort()
	return out


# ------------------------------------------------------------------ проверки

## Ошибки сборки, при которых ModularDoll / CraftedWeapon не соберутся (без «голов 0», энергии и управления — это правила игры,
## мастерская показывает их отдельно, а куклу без головы всё равно собирает на стенде).
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
		out.append("Нет детали для руки мышью — нажми «Рука мышью» и кликни по детали")
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
		return "Деталь руки мышью снята — выбери новую"
	if e.begins_with("корн") or e.begins_with("корень"):
		return "В центре должно быть ядро"
	if e.begins_with("голова «"):
		return "Голова крепится только на шею ядра"
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
	var trial: Resource = dup_body(bp as BodyBlueprint) if bp is BodyBlueprint else dup_weapon(bp as WeaponBlueprint)
	var res := _apply_attach(trial, part_id, parent_uid, an)
	r["replace"] = res.get("replace", "")
	r["drops"] = res.get("drops", PackedStringArray())
	if not bool(res.get("ok", false)):
		r["code"] = String(res.get("code", "invalid"))
		r["reason"] = String(res.get("reason", "Не встаёт"))
		return r
	if bp is BodyBlueprint:
		var after := (trial as BodyBlueprint).energy_used()
		r["energy_after"] = after
		if after > (bp as BodyBlueprint).energy_budget and after > energy_used(bp):
			var free_e: int = (bp as BodyBlueprint).energy_budget - energy_used(bp)
			var freed: int = energy_used(bp) + d.energy - after   # энергия снятого при замене
			r["code"] = "energy"
			r["reason"] = "Не хватает энергии: %s стоит %d, свободно %d" % [d.title, d.energy, free_e + freed]
			return r
	var errs := structural_errors(trial)
	if not errs.is_empty():
		r["code"] = "invalid"
		r["reason"] = _friendly(errs[0])
		return r
	r["ok"] = true
	r["code"] = "replace" if String(r["replace"]) != "" else ""
	return r


## Прикрутить (с проверкой): {ok, uid, code, reason, replace, drops}.
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
	(bp.get("nodes") as Array).append(n)
	return {"ok": true, "uid": uid}


## Заменить деталь uid на part_id: uid остаётся (control и weapon_on не теряются), явное имя — только если префикс тела тот же,
## дети, которым нет якоря на новой детали (или вид не принимается), снимаются с поддеревом.
static func _replace(bp: Resource, uid: String, part_id: String) -> Dictionary:
	var n := find(bp, uid)
	var d := part(part_id)
	var old := part(String(n.get("part", "")))
	n["part"] = part_id
	if n.has("name") and (old == null or d.name_prefix != old.name_prefix):
		n.erase("name")
	var new_anchors := BodyBlueprint.part_anchors(d)
	var drops: PackedStringArray = []
	for c in children_of(bp, uid):
		var an := anchor_name(String(c.get("anchor", "")))
		var cd := part(String(c.get("part", "")))
		var ok := new_anchors.has(an)
		if ok:
			var acc: PackedStringArray = new_anchors[an]["accepts"]
			ok = acc.is_empty() or (cd != null and acc.has(cd.kind))
		if not ok:
			drops.append_array(_remove_subtree(bp, String(c.get("uid", ""))))
	return {"ok": true, "uid": uid, "drops": drops}


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
	var own_body := d != null and (d.attach != "fixed" or parent_uid == "")   # fixed-деталь живёт в теле хозяина: своих имён нет
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
		if d == null or (d.attach == "fixed" and String(n.get("parent", "")) != ""):
			continue
		if body.body_name_of(u) == bn:
			return true
		if jn != "" and body.joint_name_of(u) == jn:
			return true
	return false


# ------------------------------------------------------------------ рука мышью и оружие

## Тело, которым управляется деталь: fixed-деталь (броня, навершие на теле) — её хозяин по цепочке.
static func host_uid(bp: Resource, uid: String) -> String:
	var cur := uid
	var guard := 0
	while guard < 64:
		guard += 1
		var n := find(bp, cur)
		var d := part(String(n.get("part", "")))
		if n.is_empty() or d == null or d.attach != "fixed" or String(n.get("parent", "")) == "":
			return cur
		cur = String(n.get("parent", ""))
	return cur


## Пометить деталь рукой мышью: {ok, uid, reason, cleared}. Повторная пометка той же детали снимает её.
static func set_control(bp: BodyBlueprint, uid: String) -> Dictionary:
	if find(bp, uid).is_empty():
		return {"ok": false, "uid": "", "reason": "Нет такой детали"}
	var h := host_uid(bp, uid)
	if h == root_uid(bp):
		return {"ok": false, "uid": "", "reason": "Ядро — это ты сам: выбери конечность, кисть или цепь"}
	if bp.control.has(h):
		var ctrl: PackedStringArray = []
		for c in bp.control:
			if c != h:
				ctrl.append(c)
		bp.control = ctrl
		return {"ok": true, "uid": h, "reason": "", "cleared": true}
	var ctrl2: PackedStringArray = bp.control.duplicate()
	ctrl2.append(h)
	while ctrl2.size() > MAX_CONTROL:
		ctrl2.remove_at(0)
	bp.control = ctrl2
	return {"ok": true, "uid": h, "reason": "", "cleared": false}


## Куда повесить крафтовое оружие: {uid, kind: "hand" | "end", reason}. Порядок: управляемая кисть → кисть ниже управляемой детали →
## любая кисть (правая раньше) → конец управляемой детали (у неё нет кисти: оружие продолжает конечность) → некуда.
static func weapon_mount(bp: BodyBlueprint) -> Dictionary:
	var ctrl := String(bp.control[0]) if not bp.control.is_empty() else ""
	if ctrl != "" and _kind(bp, ctrl) == "hand":
		return {"uid": ctrl, "kind": "hand", "reason": ""}
	if ctrl != "":
		for u in subtree(bp, ctrl):
			if _kind(bp, u) == "hand":
				return {"uid": u, "kind": "hand", "reason": ""}
	var hands: Array = []
	for n in bp.nodes:
		var u := String(n.get("uid", ""))
		if _kind(bp, u) == "hand":
			hands.append(u)
	hands.sort_custom(func(a: String, b: String) -> bool: return int(is_mirrored(bp, a)) > int(is_mirrored(bp, b)))
	if not hands.is_empty():
		return {"uid": hands[0], "kind": "hand", "reason": ""}
	if ctrl != "":
		var d := def_of(bp, ctrl)
		if d != null and d.attach == "joint":
			return {"uid": ctrl, "kind": "end", "reason": ""}
	return {"uid": "", "kind": "", "reason": "Оружие некуда взять: поставь кисть или отметь деталь для руки мышью"}


static func _kind(bp: Resource, uid: String) -> String:
	var d := def_of(bp, uid)
	return d.kind if d != null else ""


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
