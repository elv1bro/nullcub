## Чертёж тела (docs/plan-demo/BODY_CRAFT.md §2). Пресеты: data/body/blueprints/<id>.tres.
## nodes — массив словарей {uid, part, parent, anchor, rest_deg?, name?}:
##   uid      — ОДИН символ 0-9A-Z (Damage.body_mult_of режет только суффикс имени длиной ≤ 1: "UpperArm_3");
##   part     — id PartDef (data/body/parts/<id>.tres);
##   parent   — uid родителя ("" у ядра);
##   anchor   — имя Anchor_* у родителя;
##   rest_deg — переопределение угла покоя сустава (иначе meta rest_deg якоря);
##   name     — явное имя тела (пресет human повторяет имена doll.tscn: UpperArm_L, Hand_R…).
## Корень — ядро (kind core, имя Torso), ровно одна голова (kind head) на Anchor_Neck ядра.
class_name BodyBlueprint
extends Resource

const PARTS_DIR := "res://data/body/parts/"

@export var id := ""
@export var title := ""
@export var energy_budget := 100
@export var nodes: Array[Dictionary] = []
## uid деталей, которыми управляет рука мышью / правым стиком (сейчас ≤ 1, позже ≤ 2).
@export var control: PackedStringArray = []
## Необязательное крафтовое оружие: вешается на деталь weapon_on (uid).
@export var weapon: Resource
@export var weapon_on := ""


static func part_def(part_id: String) -> PartDef:
	var path := PARTS_DIR + part_id + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as PartDef


func energy_used() -> int:
	var total := 0
	for n in nodes:
		var d := part_def(String(n.get("part", "")))
		if d != null:
			total += d.energy
	return total


## Пустой массив = чертёж корректен; иначе — список ошибок по-русски.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	var uids := {}
	var roots := 0
	var heads := 0
	for n in nodes:
		var uid := String(n.get("uid", ""))
		if uid.length() != 1:
			errors.append("uid «%s»: нужен ровно один символ" % uid)
		if uids.has(uid):
			errors.append("uid «%s» повторяется" % uid)
		uids[uid] = n
		var d := part_def(String(n.get("part", "")))
		if d == null:
			errors.append("нет детали «%s»" % n.get("part", ""))
			continue
		if String(n.get("parent", "")) == "":
			roots += 1
			if d.kind != "core":
				errors.append("корень должен быть ядром, а не «%s»" % d.id)
		if d.kind == "head":
			heads += 1
	for n in nodes:
		var p := String(n.get("parent", ""))
		if p != "" and not uids.has(p):
			errors.append("у «%s» нет родителя «%s»" % [n.get("uid", ""), p])
	if roots != 1:
		errors.append("корней %d, нужен один (ядро)" % roots)
	if heads != 1:
		errors.append("голов %d, нужна ровно одна" % heads)
	if energy_used() > energy_budget:
		errors.append("энергия %d > бюджета %d" % [energy_used(), energy_budget])
	for c in control:
		if not uids.has(c):
			errors.append("управляемая деталь «%s» не найдена" % c)
	if errors.is_empty():
		errors.append_array(_validate_assembly())
	return errors


# --- хелперы сборки (ModularDoll, мастерская, tests/body_probe). Формат чертежа тот же, это только чтение. ---

const UID_CHARS := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
## Якорь с joint_group "auto" (универсальные детали хлама: одна и та же конечность — рука или нога): группа сустава берётся
## по группе проксимального сустава самой детали — плечо → локоть → кисть, бедро → колено → лодыжка.
const AUTO_NEXT := {"Shoulder": "Elbow", "Elbow": "Wrist", "Wrist": "Wrist", "Hip": "Knee", "Knee": "Ankle", "Ankle": "Ankle", "Neck": "Neck"}
## Кэш якорей сцен деталей: путь сцены -> {имя якоря: {xf, accepts, joint_group, rest_deg, mirror, rest_from_pose, limit_deg?}}.
static var _anchor_cache: Dictionary = {}


func find_node(uid: String) -> Dictionary:
	for n in nodes:
		if String(n.get("uid", "")) == uid:
			return n
	return {}


## Узлы «родитель раньше детей», порядок чертежа сохраняется (у пресета human — порядок тел и суставов doll.tscn).
## Узлы с несуществующим родителем или в цикле сюда не попадают (validate() их называет).
func sorted_nodes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var placed := {}
	var progress := true
	while progress:
		progress = false
		for n in nodes:
			var uid := String(n.get("uid", ""))
			if placed.has(uid):
				continue
			var p := String(n.get("parent", ""))
			if p == "" or placed.has(p):
				out.append(n)
				placed[uid] = true
				progress = true
	return out


## Якоря сцены детали (маркеры Anchor_* и их метаданные, BODY_CRAFT.md §1). Сцена инстанцируется один раз и кэшируется.
static func part_anchors(d: PartDef) -> Dictionary:
	if d == null or d.scene == null:
		return {}
	var key := d.scene.resource_path
	if _anchor_cache.has(key):
		return _anchor_cache[key]
	var out := {}
	var inst := d.scene.instantiate()
	for c in inst.get_children():
		if c is Marker3D and String(c.name).begins_with("Anchor_"):
			out[String(c.name)] = anchor_info(c as Marker3D)
	inst.free()
	_anchor_cache[key] = out
	return out


## Метаданные одного якоря в словарь (xf — локальный Transform3D маркера в детали).
static func anchor_info(m: Marker3D) -> Dictionary:
	var info := {
		"xf": m.transform,
		"accepts": PackedStringArray(m.get_meta("accepts", PackedStringArray())),
		"joint_group": String(m.get_meta("joint_group", "")),
		"rest_deg": float(m.get_meta("rest_deg", 0.0)),
		"mirror": bool(m.get_meta("mirror", false)),
		"rest_from_pose": bool(m.get_meta("rest_from_pose", false)),
	}
	if m.has_meta("limit_deg"):
		info["limit_deg"] = Vector2(m.get_meta("limit_deg"))
	return info


## Группа мышц сустава, которым деталь uid крепится к родителю ("" у ядра и fixed-деталей): joint_group якоря родителя,
## "auto" — AUTO_NEXT по группе сустава самого родителя.
func joint_group_of(uid: String) -> String:
	var n := find_node(uid)
	var p := String(n.get("parent", ""))
	if n.is_empty() or p == "":
		return ""
	var d := part_def(String(n.get("part", "")))
	if d != null and d.attach == "fixed":
		return ""
	var pn := find_node(p)
	var a: Dictionary = part_anchors(part_def(String(pn.get("part", "")))).get(String(n.get("anchor", "")), {})
	var g := String(a.get("joint_group", ""))
	if g == "auto":
		var pg := _host_group(p)
		g = String(AUTO_NEXT.get(pg, "Wrist"))
	return g


## Группа сустава тела, в которое входит деталь uid (fixed-детали — группа тела-хозяина).
func _host_group(uid: String) -> String:
	var n := find_node(uid)
	var d := part_def(String(n.get("part", "")))
	if d != null and d.attach == "fixed" and String(n.get("parent", "")) != "":
		return _host_group(String(n.get("parent", "")))
	return joint_group_of(uid)


## Имя тела (BODY_CRAFT.md §2): явное name узла; ядро и голова — просто name_prefix («Torso», «Head»: Doll.torso()/head() и
## Tuning.DOLL_CORE_PARTS ищут по имени); остальные — <name_prefix>_<uid>. У fixed-детали своего тела нет — имя тела-хозяина.
func body_name_of(uid: String) -> String:
	var n := find_node(uid)
	var d := part_def(String(n.get("part", "")))
	if n.is_empty() or d == null:
		return ""
	if d.attach == "fixed" and String(n.get("parent", "")) != "":
		return body_name_of(String(n.get("parent", "")))
	if String(n.get("name", "")) != "":
		return String(n.get("name", ""))
	if d.kind == "core" or d.kind == "head":
		return d.name_prefix
	return "%s_%s" % [d.name_prefix, uid]


## Суффикс имени тела после последнего «_» («UpperArm_L» → «L», «Foot_3» → «3», «Head» → «»).
static func name_suffix(body_name: String) -> String:
	var us := body_name.rfind("_")
	return body_name.substr(us + 1) if us > 0 else ""


## Имя сустава детали: <группа>_<суффикс тела> (Shoulder_L, Knee_7); тело без суффикса — просто группа (Head → Neck).
## Doll берёт группу мышц из префикса имени сустава до «_».
func joint_name_of(uid: String) -> String:
	var g := joint_group_of(uid)
	if g == "":
		return ""
	var s := name_suffix(body_name_of(uid))
	return g if s == "" else "%s_%s" % [g, s]


## Имена тел, которыми управляет рука мышью (control → body_name_of).
func control_body_names() -> PackedStringArray:
	var out: PackedStringArray = []
	for c in control:
		out.append(body_name_of(c))
	return out


func total_mass() -> float:
	var m := 0.0
	for n in nodes:
		var d := part_def(String(n.get("part", "")))
		if d != null:
			m += d.mass
	return m


## Проверки сборки поверх базовых: uid из 0-9A-Z, цепочки без циклов, якорь есть у родителя и принимает вид детали, один ребёнок
## на якорь, голова на Anchor_Neck ядра, имена тел и суставов не повторяются, группа сустава известна, управляемых ≤ 2.
func _validate_assembly() -> PackedStringArray:
	var errors: PackedStringArray = []
	var sorted := sorted_nodes()
	if sorted.size() != nodes.size():
		errors.append("цикл или обрыв в цепочке родителей (собрать можно %d из %d деталей)" % [sorted.size(), nodes.size()])
		return errors
	var used_anchor := {}
	var body_names := {}
	var joint_names := {}
	var root_uid := ""
	for n in sorted:
		var uid := String(n.get("uid", ""))
		if not UID_CHARS.contains(uid):
			errors.append("uid «%s»: только 0-9A-Z" % uid)
		var d := part_def(String(n.get("part", "")))
		var p := String(n.get("parent", ""))
		if p == "":
			root_uid = uid
		else:
			var pd := part_def(String(find_node(p).get("part", "")))
			var an := String(n.get("anchor", ""))
			var anchors := part_anchors(pd)
			if not anchors.has(an):
				errors.append("у «%s» (%s) нет якоря «%s» для «%s»" % [p, pd.id, an, uid])
			else:
				var acc: PackedStringArray = anchors[an]["accepts"]
				if not acc.is_empty() and not acc.has(d.kind):
					errors.append("якорь «%s» у «%s» не принимает вид «%s» (%s)" % [an, p, d.kind, d.id])
			var key := p + "/" + an
			if used_anchor.has(key):
				errors.append("на якорь «%s» у «%s» повешены две детали: «%s» и «%s»" % [an, p, used_anchor[key], uid])
			used_anchor[key] = uid
			if d.kind == "head" and (p != root_uid or an != "Anchor_Neck"):
				errors.append("голова «%s» должна висеть на Anchor_Neck ядра" % uid)
		if d.attach == "fixed" and p != "":
			continue
		var bn := body_name_of(uid)
		if body_names.has(bn):
			errors.append("имя тела «%s» повторяется (%s и %s)" % [bn, body_names[bn], uid])
		body_names[bn] = uid
		if p != "":
			var g := joint_group_of(uid)
			if g == "" or not AUTO_NEXT.has(g):
				errors.append("у сустава «%s» неизвестная группа мышц «%s»" % [uid, g])
			var jn := joint_name_of(uid)
			if joint_names.has(jn):
				errors.append("имя сустава «%s» повторяется (%s и %s)" % [jn, joint_names[jn], uid])
			joint_names[jn] = uid
	if control.size() > 2:
		errors.append("управляемых деталей %d, можно не больше 2" % control.size())
	return errors
