## Чертёж тела (docs/plan-demo/BODY_CRAFT.md §2). Пресеты: data/body/blueprints/<id>.tres.
## nodes — массив словарей {uid, part, parent, anchor, rest_deg?, name?, mat?, joint?}:
##   uid      — ОДИН символ 0-9A-Z (Damage.body_mult_of режет только суффикс имени длиной ≤ 1: "UpperArm_3");
##   part     — id PartDef (data/body/parts/<id>.tres);
##   parent   — uid родителя ("" у ядра);
##   anchor   — имя Anchor_* у родителя;
##   rest_deg — переопределение угла покоя сустава (иначе meta rest_deg якоря);
##   name     — явное имя тела (пресет human повторяет имена doll.tscn: UpperArm_L, Hand_R…);
##   mat      — кит v2 (docs/plan-demo/BODY_KIT.md §4): id MaterialDef вместо PartDef.base_mat (только у деталей с base_mat);
##   joint    — кит v2 (§5.2): тип шарнира связи с родителем, KitJoint.TYPES (нет ключа — "pin"; "weld" — узел сливается с родителем).
## Корень — ядро (kind core, имя Torso), ровно одна голова (kind head) на Anchor_Neck ядра.
## Узел без своего тела (is_fixed): PartDef.attach "fixed", вид из PartDef.FIXED_KINDS (декор, броня) или joint "weld".
class_name BodyBlueprint
extends Resource

const PARTS_DIR := "res://data/body/parts/"

@export var id := ""
@export var title := ""
@export var energy_budget := 100
@export var nodes: Array[Dictionary] = []
## Тяги (WORKSHOP_V3.md §3): uid деталей, которые мышь / стик тянут к цели, ≤ MAX_PULLS. control[0] — главная рука (захват,
## бросок; бесплатная — встроена в ядро), каждая следующая стоит PULL_ENERGY × вынос детали (pull_energy).
@export var control: PackedStringArray = []
## uid тяг из control на ПКМ (стик с LB); остальные — на ЛКМ (стик).
@export var control_rmb: PackedStringArray = []
## Необязательное крафтовое оружие: вешается на деталь weapon_on (uid).
@export var weapon: Resource
@export var weapon_on := ""
## Энергия за кг оружия в руке по регламенту лиги (weapon_energy); 0 — оружие энергию не ест.
@export var weapon_energy_per_kg := 0.0


static var _part_def_cache: Dictionary = {}   # id -> PartDef (null — файла нет)


## PartDef по id. Кэш ресурсов Godot слабый: PartDef без владельца освобождался вместе со сценой детали и перечитывался с диска на
## каждый вызов (≈ 0.3 мс), а validate / energy_used / total_mass / cheapest_cost зовут его сотнями за одну правку в мастерской.
## Файлы деталей пишут только builder-ы (tools/), в игре они не меняются.
static func part_def(part_id: String) -> PartDef:
	if _part_def_cache.has(part_id):
		return _part_def_cache[part_id]
	var path := PARTS_DIR + part_id + ".tres"
	var d: PartDef = load(path) as PartDef if ResourceLoader.exists(path) else null
	_part_def_cache[part_id] = d
	return d


## Энергия по расстоянию (docs/plan-demo/WORKSHOP_V3.md §2): чем дальше деталь от ядра, тем дороже — дефицит без смены бюджета.
## Цена узла = ceil((PartDef.energy + энергия шарнира) × reach_mult(d)), d — вынос детали от ядра по цепочке (node_reach).
const ENERGY_REACH_FREE_M := 0.3      # ближе — без наценки (голова, плечи, бёдра)
const ENERGY_REACH_PER_M := 1.0       # +100 % за каждый метр дальше ENERGY_REACH_FREE_M
const MAX_PULLS := 10                 # тяг на куклу — технический потолок; настоящий предел — энергия
const PULL_ENERGY := 5                # базовая цена тяги (вторая и дальше; первая — в ядре), × вынос детали
const _MIRROR_X := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
static var _socket_cache: Dictionary = {}


## Множитель цены за вынос детали на d метров от центра ядра.
static func reach_mult(d: float) -> float:
	return 1.0 + maxf(0.0, d - ENERGY_REACH_FREE_M) * ENERGY_REACH_PER_M


## Цена по расстоянию: базовая энергия base на расстоянии d.
static func reach_cost(base: int, d: float) -> int:
	return int(ceil(base * reach_mult(d) - 0.001)) if base > 0 else 0


## Σ цен узлов (node_energy) и тяг (pull_energy): детали, шарниры и тяги с наценкой за расстояние от ядра; по регламенту лиги —
## ещё оружие в руке (weapon_energy).
func energy_used() -> int:
	var total := 0
	var reach := node_reach()
	for n in nodes:
		total += _node_energy(n, float(reach.get(String(n.get("uid", "")), 0.0)))
	for i in range(1, control.size()):
		total += reach_cost(PULL_ENERGY, float(reach.get(String(control[i]), 0.0)))
	return total + weapon_energy()


## Регламент лиги (кампания, docs/plan-demo/17-career-trophy.md): оружие в руке ест энергию ядра — ceil(масса оружия ×
## weapon_energy_per_kg). 0 — оружие энергию не ест (Быстрый бой, свободная мастерская — как раньше).
func weapon_energy() -> int:
	if weapon_energy_per_kg <= 0.0 or not (weapon is WeaponBlueprint):
		return 0
	return int(ceil(weapon_mass() * weapon_energy_per_kg - 0.001))


## Масса оружия в руке: Σ масс его деталей (как CraftedWeapon.total_mass, с цепью).
func weapon_mass() -> float:
	var m := 0.0
	if weapon is WeaponBlueprint:
		for n in (weapon as WeaponBlueprint).nodes:
			m += _node_mass(n)
	return m


## Цена тяги на узле uid: 0 у главной (control[0], встроена в ядро) и у узла без тяги; иначе PULL_ENERGY × вынос.
func pull_energy(uid: String) -> int:
	var i := control.find(uid)
	if i <= 0:
		return 0
	return reach_cost(PULL_ENERGY, float(node_reach().get(uid, 0.0)))


## Цена тяги, если поставить её на uid сейчас (первая — бесплатно).
func next_pull_energy(uid: String) -> int:
	if control.is_empty():
		return 0
	return reach_cost(PULL_ENERGY, float(node_reach().get(uid, 0.0)))


## "rmb" — тяга uid на ПКМ, "lmb" — на ЛКМ, "" — у узла тяги нет.
func pull_button(uid: String) -> String:
	if not control.has(uid):
		return ""
	return "rmb" if control_rmb.has(uid) else "lmb"


## Цена узла uid с наценкой за расстояние.
func node_energy(uid: String) -> int:
	var n := find_node(uid)
	return _node_energy(n, float(node_reach().get(uid, 0.0))) if not n.is_empty() else 0


## Базовая цена узла без расстояния: PartDef.energy + шарнир (KitJoint: пружина 2, мотор 8).
static func node_base_energy(n: Dictionary) -> int:
	var d := part_def(String(n.get("part", "")))
	return (d.energy if d != null else 0) + KitJoint.energy_of(String(n.get("joint", "")))


static func _node_energy(n: Dictionary, d: float) -> int:
	return reach_cost(node_base_energy(n), d)


## uid -> вынос детали от ядра (м): путь по цепочке — Σ расстояний между началами деталей от центра ядра до этой детали
## (якоря, Socket и зеркало — как ModularDoll._build). От позы не зависит: кисть на согнутой и на вытянутой руке стоит одинаково.
## Узлы, до которых цепочка не доходит, — 0.
func node_reach() -> Dictionary:
	var out := {}
	var xf := {}       # uid -> Transform3D
	var mir := {}      # uid -> bool
	for n in sorted_nodes():
		var uid := String(n.get("uid", ""))
		var parent := String(n.get("parent", ""))
		if parent == "" or not xf.has(parent):
			xf[uid] = Transform3D.IDENTITY
			mir[uid] = false
			out[uid] = 0.0
			continue
		var pd := part_def(String(find_node(parent).get("part", "")))
		var a: Dictionary = part_anchors(pd).get(String(n.get("anchor", "")), {})
		if a.is_empty():
			xf[uid] = xf[parent]
			mir[uid] = mir[parent]
			out[uid] = out[parent]
			continue
		var pm: bool = mir[parent]
		var a_local: Transform3D = a["xf"]
		if pm:
			a_local = _mirror_xf(a_local)
		var a_xf: Transform3D = (xf[parent] as Transform3D) * a_local
		var m := pm != bool(a["mirror"])
		var sock := _socket_xf(part_def(String(n.get("part", ""))))
		if m:
			sock = _mirror_xf(sock)
		xf[uid] = a_xf * sock.affine_inverse()
		mir[uid] = m
		out[uid] = float(out[parent]) + (xf[uid] as Transform3D).origin.distance_to((xf[parent] as Transform3D).origin)
	return out


static func _mirror_xf(t: Transform3D) -> Transform3D:
	return Transform3D(_MIRROR_X * t.basis * _MIRROR_X, _MIRROR_X * t.origin)


## Локальный кадр маркера Socket сцены детали (кэш по сцене; нет Socket — IDENTITY).
static func _socket_xf(d: PartDef) -> Transform3D:
	if d == null or d.scene == null:
		return Transform3D.IDENTITY
	var key := d.scene.resource_path
	if not _socket_cache.has(key):
		var inst := d.scene.instantiate()
		var s := inst.get_node_or_null("Socket") as Node3D
		_socket_cache[key] = s.transform if s != null else Transform3D.IDENTITY
		inst.free()
	return _socket_cache[key]


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
		var mid := String(n.get("mat", ""))
		if mid != "":
			var me := _mat_error(n, d, mid)
			if me != "":
				errors.append(me)
		var jt := String(n.get("joint", ""))
		if jt != "":
			var je := _joint_error(n, d, jt)
			if je != "":
				errors.append(je)
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
		elif _is_fixed_n(uids[c]):
			# своего тела нет (навершие вместо кисти, декор, сварка): ArmAssist искал бы тело, которого нет, — рука мышью молча пропала бы
			errors.append("рука мышью на «%s» — у детали нет своего тела (fixed), отметь тело-хозяина" % c)
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
	if m.has_meta("joint_r"):
		info["joint_r"] = float(m.get_meta("joint_r"))   # кит v2: радиус шара коннектора (ModularDoll, иначе KitJoint.RADIUS)
	return info


## Группа мышц сустава, которым деталь uid крепится к родителю ("" у ядра и fixed-деталей): joint_group якоря родителя,
## "auto" — AUTO_NEXT по группе сустава самого родителя.
func joint_group_of(uid: String) -> String:
	if is_fixed(uid):
		return ""
	return _anchor_group(uid, 0)


## Группа сустава, которую якорь родителя дал бы узлу uid со своим суставом — и у сваренного узла (joint "weld": угол покоя сварки,
## ModularDoll._build; запрет мотора на суставе без мышцы, _joint_error). "" — корень, нет узла, fixed-деталь по PartDef.
func anchor_group_of(uid: String) -> String:
	return _anchor_group(uid, 0)


## depth — защита от циклов: validate() и CraftEdit.structural_errors зовут группу (через _joint_error) ДО проверки цепочки
## родителей (_validate_assembly); у чертежа с циклом (A → B → A на auto-якорях) рекурсия иначе не кончилась бы. Шаг вверх по цепи —
## +2 (_anchor_group → _host_group → _anchor_group), цепь без цикла короче числа узлов: предел 2 × узлов её не режет.
func _anchor_group(uid: String, depth: int) -> String:
	var n := find_node(uid)
	var p := String(n.get("parent", ""))
	if n.is_empty() or p == "" or depth > 2 * nodes.size():
		return ""
	if is_fixed_part(part_def(String(n.get("part", "")))):
		return ""
	var pn := find_node(p)
	var a: Dictionary = part_anchors(part_def(String(pn.get("part", "")))).get(String(n.get("anchor", "")), {})
	var g := String(a.get("joint_group", ""))
	if g == "auto":
		var pg := _host_group(p, depth + 1)
		g = String(AUTO_NEXT.get(pg, "Wrist"))
	return g


## Группа сустава тела, в которое входит деталь uid (fixed-детали — группа тела-хозяина).
func _host_group(uid: String, depth: int = 0) -> String:
	if depth > 2 * nodes.size():
		return ""
	if is_fixed(uid):
		return _host_group(String(find_node(uid).get("parent", "")), depth + 1)
	return _anchor_group(uid, depth + 1)


## Префикс имени тела узла: PartDef.name_prefix; у конечности кита (префикс по размеру: S — UpperArm, L — UpperLeg) на суставе
## локтя / колена — LowerArm / LowerLeg: имя тела решает Damage.body_mult_of и монитор DollCombat.MONITORED, предплечье из
## мастерской должно бить и слушать контакты как предплечье пресета (BODY_KIT.md §3.5). Плечо / бедро / бок и третий сегмент
## (Wrist / Ankle) — префикс детали, как был (у пресетов пауков — без изменений).
func name_prefix_of(uid: String) -> String:
	var n := find_node(uid)
	var d := part_def(String(n.get("part", "")))
	if n.is_empty() or d == null:
		return ""
	if d.kind == "limb" and d.connector:
		match joint_group_of(uid):
			"Elbow":
				return "LowerArm"
			"Knee":
				return "LowerLeg"
	return d.name_prefix


## Имя тела (BODY_CRAFT.md §2): явное name узла; ядро и голова — просто name_prefix («Torso», «Head»: Doll.torso()/head() и
## Tuning.DOLL_CORE_PARTS ищут по имени); остальные — <name_prefix_of>_<uid>. У fixed-детали своего тела нет — имя тела-хозяина.
func body_name_of(uid: String) -> String:
	var n := find_node(uid)
	var d := part_def(String(n.get("part", "")))
	if n.is_empty() or d == null:
		return ""
	if is_fixed(uid):
		return body_name_of(String(n.get("parent", "")))
	if String(n.get("name", "")) != "":
		return String(n.get("name", ""))
	if d.kind == "core" or d.kind == "head":
		return d.name_prefix
	return "%s_%s" % [name_prefix_of(uid), uid]


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


## Σ node_mass (материал узла меняет массу детали, §4).
func total_mass() -> float:
	var m := 0.0
	for n in nodes:
		m += _node_mass(n)
	return m


# --- кит v2: fixed / материал / тип шарнира узла (docs/plan-demo/BODY_KIT.md §4, §5.2–5.3) ---

## Деталь сама по себе без своего тела: attach "fixed" или вид из PartDef.FIXED_KINDS (декор, броня — даже если attach "joint").
static func is_fixed_part(d: PartDef) -> bool:
	return d != null and (d.attach == "fixed" or PartDef.FIXED_KINDS.has(d.kind))


## Узел uid сливается с телом родителя (своего тела и сустава нет): есть родитель и деталь fixed (is_fixed_part) или joint "weld".
## Все проверки «fixed» сборки, мастерской и проб идут через него.
func is_fixed(uid: String) -> bool:
	return _is_fixed_n(find_node(uid))


func _is_fixed_n(n: Dictionary) -> bool:
	if n.is_empty() or String(n.get("parent", "")) == "":
		return false
	if KitJoint.is_weld(String(n.get("joint", ""))):
		return true
	return is_fixed_part(part_def(String(n.get("part", ""))))


## Тип шарнира, которым узел uid висит на родителе (KitJoint.TYPES): ключ joint, без него — "pin". "" — сустава не бывает
## (корень, fixed-деталь по PartDef, узла нет). Сваренный узел — "weld".
func joint_type_of(uid: String) -> String:
	var n := find_node(uid)
	if n.is_empty() or String(n.get("parent", "")) == "" or is_fixed_part(part_def(String(n.get("part", "")))):
		return ""
	var jt := String(n.get("joint", ""))
	return jt if jt != "" else KitJoint.DEFAULT


## id MaterialDef узла: ключ mat, иначе PartDef.base_mat ("" — деталь не красится: старые wood_*, junk_*, craft).
func node_mat(uid: String) -> String:
	return _node_mat(find_node(uid))


static func _node_mat(n: Dictionary) -> String:
	var mid := String(n.get("mat", ""))
	if mid != "":
		return mid
	var d := part_def(String(n.get("part", "")))
	return d.base_mat if d != null else ""


## Масса узла (кг): PartDef.mass × density материала узла / density base_mat; без base_mat (или без файла материала) — PartDef.mass.
func node_mass(uid: String) -> float:
	return _node_mass(find_node(uid))


static func _node_mass(n: Dictionary) -> float:
	var d := part_def(String(n.get("part", "")))
	if d == null:
		return 0.0
	if d.base_mat == "":
		return d.mass
	var base := MaterialDef.get_def(d.base_mat)
	var m := MaterialDef.get_def(_node_mat(n))
	if base == null or m == null or base.density <= 0.0 or m == base:
		return d.mass
	return d.mass * m.density / base.density


## Железо ли узел для магнита Свалки: у детали кита — MaterialDef.iron материала узла, у старых — PartDef.material == "iron".
func node_iron(uid: String) -> bool:
	return _node_iron(find_node(uid))


static func _node_iron(n: Dictionary) -> bool:
	var d := part_def(String(n.get("part", "")))
	if d == null:
		return false
	var m: MaterialDef = null
	if d.base_mat != "":
		m = MaterialDef.get_def(_node_mat(n))
	return m.iron if m != null else d.material == "iron"


## Почему узлу uid нельзя материал mat_id ("" — можно). Мастерская показывает причину отказа кисти.
func mat_error(uid: String, mat_id: String) -> String:
	var n := find_node(uid)
	var d := part_def(String(n.get("part", "")))
	if n.is_empty() or d == null:
		return "нет детали «%s»" % uid
	return _mat_error(n, d, mat_id)


static func _mat_error(n: Dictionary, d: PartDef, mat_id: String) -> String:
	var uid := String(n.get("uid", ""))
	if MaterialDef.get_def(mat_id) == null:
		return "у «%s» неизвестный материал «%s»" % [uid, mat_id]
	if d.base_mat == "":
		return "«%s» (%s) не красится: материал «%s» — только для деталей кита" % [uid, d.id, mat_id]
	return ""


## Почему узлу uid нельзя тип шарнира jt ("" — можно, BODY_KIT.md §5.2). Мастерская показывает причину отказа.
func joint_error(uid: String, jt: String) -> String:
	var n := find_node(uid)
	var d := part_def(String(n.get("part", "")))
	if n.is_empty() or d == null:
		return "нет детали «%s»" % uid
	return _joint_error(n, d, jt)


func _joint_error(n: Dictionary, d: PartDef, jt: String) -> String:
	var uid := String(n.get("uid", ""))
	if not KitJoint.is_type(jt):
		return "у «%s» неизвестный тип шарнира «%s»" % [uid, jt]
	if String(n.get("parent", "")) == "":
		return "у корня «%s» нет сустава — шарнир «%s» ставить некуда" % [uid, jt]
	if is_fixed_part(d):
		return "«%s» (%s) крепится намертво — шарнир «%s» к ней не ставится" % [uid, d.id, jt]
	if not KitJoint.is_weld(jt):
		# мотор / пружина множат мышцу группы (ModularDoll._update_pair_gains): у группы без мышцы (k = 0 в Tuning.MUSCLE_GROUPS —
		# Ankle: стопы, третий сегмент ноги, «прочие» якоря) они стоили бы энергию и ничего не давали. Группа — по якорю
		# (anchor_group_of): узел может быть сейчас сварен, а спрашивают про мотор.
		var km := float(KitJoint.info(jt).get("k", 1.0))
		if km > 0.0 and jt != KitJoint.DEFAULT:
			var g := _anchor_group(uid, 0)
			var G: Dictionary = Tuning.MUSCLE_GROUPS.get(g, {})
			if not G.is_empty() and float(G["k"]) <= 0.0:
				return "у сустава «%s» (%s) нет мышцы — шарнир «%s» ничего не усилит" % [uid, g, KitJoint.info(jt)["title"]]
		return ""
	if d.kind == "head":
		return "голову «%s» нельзя приварить: она держится на своём суставе Neck" % uid
	if control.has(uid):
		return "управляемую деталь «%s» нельзя приварить: рука мышью тянет её собственное тело" % uid
	var anchors := part_anchors(d)
	for c in nodes:
		if String(c.get("parent", "")) != uid or _is_fixed_n(c):
			continue
		var an := String(c.get("anchor", ""))
		if String((anchors.get(an, {}) as Dictionary).get("joint_group", "")) == "auto":
			return "«%s» нельзя приварить: сустав «%s» на её якоре «%s» берёт группу от неё (auto)" % [uid, c.get("uid", ""), an]
	return ""


## Проверки сборки поверх базовых: uid из 0-9A-Z, цепочки без циклов, якорь есть у родителя и принимает вид детали, один ребёнок
## на якорь, голова на Anchor_Neck ядра, имена тел и суставов не повторяются, группа сустава известна, управляемых ≤ 2.
## mat / joint узлов (кит v2) проверяет validate() в базовом проходе: _mat_error, _joint_error.
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
		if is_fixed(uid):
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
	if control.size() > MAX_PULLS:
		errors.append("тяг %d, можно не больше %d" % [control.size(), MAX_PULLS])
	for u in control_rmb:
		if not control.has(u):
			errors.append("тяга ПКМ «%s» не среди тяг (control)" % u)
	return errors
