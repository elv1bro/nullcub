## Вид бойца стычки по классу (docs/plan-demo/SQUAD.md; автор 06.10: «было бы классно разделить модели — разные по классам и по
## сторонам»). Все бойцы — «Человек» (kit_human), и физика у них та же: здесь только меши кита поверх куклы — без форм, масс,
## RigidBody и правки чертежа (tests/squad_look_snapshot сверяет массы и формы с куклой без вида):
##   • swap — меш детали заменяется мешем кита: исходный «<Тело>/Mesh» прячется (visible его мешей, meta HID_META), новый glb встаёт
##     ребёнком того же тела по Socket исходного меша — как сам кит «Человек» (кадр Socket тела × Socket glb⁻¹, tools/build_body_kit.gd
##     _build_human_part); у правой стороны исходный меш уже отражён по X (ModularDoll._mirror_part) — новый наследует отражение;
##     масштаб — подгонка звена кита S / L к звену рига (предплечье 0.27 м против 0.30, голень 0.40 против 0.42);
##   • deco — меш декора кита на якоре тела (Anchor_Deco конечности, Anchor_Top головы, Anchor_Back торса), посадка как у fixed-детали
##     (якорь × Socket⁻¹, у правой стороны — × отражение, ModularDoll._merge_into), но без форм и массы; масштаб — крупнее для
##     силуэта (наплечники громилы, ранец налётчика: формы у них нет — пуля сквозь декор проходит, как сквозь обводку);
##   • краска класса: Base_* всех добавленных мешей — один материал класса (paint, MaterialDef), класс читается цветом тела издалека
##     (громила — железо, снайпер — белый, налётчик — жёлтый; цветов команд среди них нет). Варежки и ботинки меняются на те же
##     меши кита — только ради краски;
##   • цвет команды (Tuning.SQUAD_COLORS): Shirt_* — ModularDoll._recolor всей куклы; свет (GLOW_ROLES) — копия материала с
##     эмиссией цвета команды;
##   • наклейки тела с заменённым мешем перепекаются на новый меш (BodyPaint.bake_sticker), clear — обратно на исходный.
## Добавленные узлы — meta LOOK_META (по ней их находит clear). Обводка (DollOutline) ставится один раз на куклу: при первой
## регистрации apply зовут ДО DollOutline.ensure, при смене класса — apply, затем refresh_outline. Возрождение (Match.respawn_doll)
## собирает новую куклу — вид ставится заново.
##   SquadLook.apply(doll, cls, team), clear(doll), refresh_outline(doll, colour), current(doll), model_paths() — для прогрева.
class_name SquadLook
extends RefCounted

const LOOK_META := "squad_look"
const HID_META := "squad_look_hid"
const CLASS_META := "squad_look_class"
const KIT_DIR := "res://assets/models/body/kit/"
## Светящиеся роли кита (окошко Ядра, полосы про-лиги, свет Лиги) — горят цветом команды.
const GLOW_ROLES := ["Pro_Glow", "CoreGlow", "League_Glow"]
const GLOW_ENERGY := 1.8
## Вид класса (Tuning.SQUAD_CLASSES):
##   swap — базовое имя тела (обе стороны) → [glb кита, масштаб в кадре Socket (необязательно)];
##   deco — [базовое имя тела, якорь, glb кита, масштаб?, сдвиг в кадре тела?]; paint — id MaterialDef для Base_* добавленных мешей.
## Громила — тяжёлый: ящик, рогатый шлем, толстые плечи и бёдра, большие наплечники, кулаки, бронированные голени, наручи.
## Снайпер — лёгкий «про»: белые панели со светом команды, визор, антенна. Налётчик — жёлтый робот: бочка, банка, поршни, ранец
## и реактивные сапоги (рывки); ранец поднят над плечами — спереди он иначе весь за торсом.
const LOOKS := {
	"brawler": {
		"swap": {
			"Torso": ["Kit_Core_Crate"], "Head": ["Kit_Head_Horned"], "UpperArm": ["Kit_Limb_Thick_S"],
			"LowerArm": ["Kit_Limb_Basic_LA"], "Hand": ["Kit_Hand_Fist"], "UpperLeg": ["Kit_Limb_Thick_L"],
			"LowerLeg": ["Kit_Limb_Plate_L", Vector3(0.85, 0.95, 0.85)], "Foot": ["Kit_Foot_Boot"],
		},
		"deco": [
			["UpperArm", "Anchor_Deco", "Kit_Deco_Pauldron", Vector3.ONE * 1.45],
			["LowerArm", "Anchor_Deco", "Kit_Deco_Gauntlet_S"],
		],
		"paint": "iron",
	},
	"sniper": {
		"swap": {
			"Torso": ["Kit_Core_Toy"], "Head": ["Kit_Head_ProVisor"], "UpperArm": ["Kit_Limb_ProPanel_S"],
			"LowerArm": ["Kit_Limb_ProPanel_S", Vector3(0.85, 0.9, 0.85)], "Hand": ["Kit_Hand_Mitten"],
			"UpperLeg": ["Kit_Limb_ProPanel_L"], "LowerLeg": ["Kit_Limb_ProPanel_L", Vector3(0.8, 0.95, 0.8)],
			"Foot": ["Kit_Foot_Boot"],
		},
		"deco": [["Head", "Anchor_Top", "Kit_Deco_Antenna"]],
		"paint": "paint_white",
	},
	"raider": {
		"swap": {
			"Torso": ["Kit_Core_Drum"], "Head": ["Kit_Head_Can"], "UpperArm": ["Kit_Limb_Robotic_S"],
			"LowerArm": ["Kit_Limb_Robotic_S", Vector3(0.9, 0.9, 0.9)], "Hand": ["Kit_Hand_Mitten"],
			"UpperLeg": ["Kit_Limb_Piston_L"], "LowerLeg": ["Kit_Limb_Piston_L", Vector3(0.8, 0.95, 0.8)],
			"Foot": ["Kit_Foot_Boot"],
		},
		"deco": [
			["Torso", "Anchor_Back", "Kit_Active_Jetpack", Vector3.ONE * 1.3, Vector3(0.0, 0.14, 0.0)],
			["LowerLeg", "Anchor_Deco", "Kit_Active_JetBoots"],
		],
		"paint": "paint_yellow",
	},
}

static var _glow_cache: Dictionary = {}   # «id исходного материала|цвет» -> копия с эмиссией цвета команды


static func team_colour(team: int) -> Color:
	return Tuning.SQUAD_COLORS[clampi(team, 0, 1)]


## Класс, чей вид сейчас на кукле ("" — вида нет).
static func current(d: Node) -> String:
	return String(d.get_meta(CLASS_META, "")) if d != null and is_instance_valid(d) else ""


## Вид класса cls команды team на куклу d (прежний вид снимается); рубашка всей куклы — цвет команды (как SquadMatch._dress).
## Класса нет в LOOKS — кукла остаётся «Человеком».
static func apply(d: ModularDoll, cls: String, team: int) -> void:
	if d == null or not is_instance_valid(d):
		return
	clear(d)
	var look: Dictionary = LOOKS.get(cls, {})
	if look.is_empty():
		return
	var swaps: Dictionary = look.get("swap", {})
	for bn in d.parts:
		var body := d.parts[bn] as RigidBody3D
		if body == null or not is_instance_valid(body):
			continue
		var base := ModularDoll.base_name(String(bn))
		if swaps.has(base):
			_swap(body, swaps[base])
		for dc in look.get("deco", []):
			if String(dc[0]) == base:
				_deco(body, dc)
	var paint := MaterialDef.get_def(String(look.get("paint", "")))
	for n in added_nodes(d):
		_dress(n, team_colour(team), paint.surface if paint != null else null)
	d._recolor(d, Doll.SHIRT_MATERIAL, team_colour(team))   # всей кукле разом: одна копия Shirt_Kit на куклу, а не на каждый glb
	d.set_meta(CLASS_META, cls)


## Снять вид: добавленные узлы — из дерева, спрятанные меши — снова видны, наклейки — обратно на исходный меш.
static func clear(d: ModularDoll) -> void:
	if d == null or not is_instance_valid(d):
		return
	for n in added_nodes(d):
		var body := n.get_parent()
		body.remove_child(n)
		n.queue_free()
		var orig := body.get_node_or_null("Mesh") as Node3D
		if String(n.get_meta(LOOK_META)) == "swap" and orig != null:
			_rebake_stickers(body, orig)
	for n in d.find_children("*", "MeshInstance3D", true, false):
		if n.has_meta(HID_META):
			(n as MeshInstance3D).visible = true
			n.remove_meta(HID_META)
	if d.has_meta(CLASS_META):
		d.remove_meta(CLASS_META)


## Обводка после смены вида (DollOutline.ensure ставится один раз и видит только меши того времени): старые узлы обводки снимаются,
## обводка ставится заново на все видимые меши, вкл/выкл — как была. Обводки ещё не было — просто ensure.
static func refresh_outline(d: ModularDoll, colour: Color) -> void:
	if d == null or not is_instance_valid(d):
		return
	if not d.has_meta(DollOutline.META):
		DollOutline.ensure(d, colour)
		return
	var on := true
	for o in d.find_children(DollOutline.NAME, "MeshInstance3D", true, false):
		on = (o as MeshInstance3D).visible
		o.get_parent().remove_child(o)
		o.queue_free()
	d.remove_meta(DollOutline.META)
	DollOutline.ensure(d, colour)
	DollOutline.set_visible(d, on)


## Корни добавленных мешей (meta LOOK_META: "swap" / "deco") под куклой.
static func added_nodes(d: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if d == null or not is_instance_valid(d):
		return out
	for n in d.find_children("*", "Node3D", true, false):
		if n.has_meta(LOOK_META):
			out.append(n as Node3D)
	return out


## Пути всех glb видов — матч может загрузить их заранее (SquadMatch._prewarm): смена класса на отсчёте не читает диск.
static func model_paths() -> Array[String]:
	var out: Array[String] = []
	for cls in LOOKS:
		var look: Dictionary = LOOKS[cls]
		var glbs: Array = []
		for k in look.get("swap", {}):
			glbs.append(look["swap"][k][0])
		for dc in look.get("deco", []):
			glbs.append(dc[2])
		for g in glbs:
			var p := KIT_DIR + String(g) + ".glb"
			if not out.has(p):
				out.append(p)
	return out


# --- сборка вида ---

## Меш тела → glb spec[0] в кадре Socket исходного меша (× масштаб spec[1]).
static func _swap(body: RigidBody3D, spec: Array) -> void:
	var orig := body.get_node_or_null("Mesh") as Node3D
	var n := _instance(String(spec[0]))
	if n == null:
		return
	if orig == null:
		n.free()
		return
	var k: Vector3 = spec[1] if spec.size() > 1 else Vector3.ONE
	n.transform = orig.transform * _socket(orig) * Transform3D(Basis.from_scale(k), Vector3.ZERO) * _socket(n).affine_inverse()
	_hide(orig)
	_add(body, n, "swap")
	_rebake_stickers(body, n)


## Декор spec = [тело, якорь, glb, масштаб?, сдвиг?] на якоре тела: якорь × масштаб × Socket⁻¹ (+ сдвиг в кадре тела); у правой
## стороны маркер якоря — M·A·M (ModularDoll._mirror_part), меш — × M.
static func _deco(body: RigidBody3D, spec: Array) -> void:
	var mk := body.get_node_or_null(String(spec[1])) as Node3D
	if mk == null:
		return
	var n := _instance(String(spec[2]))
	if n == null:
		return
	var k: Vector3 = spec[3] if spec.size() > 3 else Vector3.ONE
	var frame := mk.transform
	if spec.size() > 4:
		frame.origin += spec[4] as Vector3
	if _mirrored(body):
		frame = frame * Transform3D(ModularDoll.MIRROR_X, Vector3.ZERO)
	n.transform = frame * Transform3D(Basis.from_scale(k), Vector3.ZERO) * _socket(n).affine_inverse()
	_add(body, n, "deco")


## Цвет на добавленном узле: свет — цвет команды, Base_* — краска класса (Shirt_* красит apply всей кукле).
static func _dress(root: Node3D, colour: Color, paint: Material) -> void:
	for m in BodyPaint.meshes(root):
		var mi := m as MeshInstance3D
		for s in range(mi.mesh.get_surface_count()):
			var mat := mi.get_active_material(s)
			if mat == null:
				continue
			if GLOW_ROLES.has(mat.resource_name):
				mi.set_surface_override_material(s, _glow(mat, colour))
			elif paint != null and mat.resource_name.begins_with("Base_"):
				mi.set_surface_override_material(s, paint)
	BodyPaint.tag_layers(root)


## Копия светящегося материала: тело — тёмный цвет команды, свет — цвет команды (общая на материал и цвет).
static func _glow(mat: Material, colour: Color) -> Material:
	var key := "%d|%s" % [mat.get_instance_id(), colour.to_html(false)]
	if _glow_cache.has(key):
		return _glow_cache[key]
	var g := mat.duplicate() as Material
	if g is BaseMaterial3D:
		var b := g as BaseMaterial3D
		var a := b.albedo_color.a
		b.albedo_color = colour.darkened(0.45)
		b.albedo_color.a = a
		b.emission_enabled = true
		b.emission = colour.lightened(0.2)
		b.emission_energy_multiplier = GLOW_ENERGY
	_glow_cache[key] = g
	return g


static func _instance(glb: String) -> Node3D:
	var path := KIT_DIR + glb + ".glb"
	var ps := load(path) as PackedScene if ResourceLoader.exists(path) else null
	if ps == null:
		push_warning("SquadLook: нет %s — деталь вида пропущена" % path)
		return null
	var n := ps.instantiate() as Node3D
	n.name = "Look_" + glb.trim_prefix("Kit_")
	return n


## kind — "swap" (замена меша тела) или "deco": meta LOOK_META.
static func _add(body: Node3D, n: Node3D, kind: String) -> void:
	n.set_meta(LOOK_META, kind)
	n.set_meta("rig_mesh", true)   # как «Mesh» детали: Doll._set_rig_visible прячет его вместе с ригом
	body.add_child(n, true)


## Кадр пустышки Socket glb (у голов и декора сверху — поворот на 180°), нет — единичный (ядра).
static func _socket(n: Node) -> Transform3D:
	for c in n.get_children():
		if c is Node3D and String(c.name).begins_with("Socket"):
			return (c as Node3D).transform
	return Transform3D.IDENTITY


## Видимые меши под исходным мешем — спрятать (обводка — их дети, прячется вместе с ними).
static func _hide(orig: Node3D) -> void:
	for m in orig.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.visible and String(mi.name) != DollOutline.NAME:
			mi.visible = false
			mi.set_meta(HID_META, true)


## Правая сторона: исходный меш отражён по X (определитель < 0); меша нет — по имени.
static func _mirrored(body: Node3D) -> bool:
	var orig := body.get_node_or_null("Mesh") as Node3D
	if orig != null:
		return orig.transform.basis.determinant() < 0.0
	return String(body.name).ends_with("_R")


## Наклейки тела (meta BodyPaint.STICKER_META) — заново на треугольники мешей root.
static func _rebake_stickers(body: Node, root: Node3D) -> void:
	for c in body.get_children():
		if c is MeshInstance3D and c.has_meta(BodyPaint.STICKER_META):
			BodyPaint.bake_sticker(c as MeshInstance3D, root)
