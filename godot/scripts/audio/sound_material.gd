## Звуковой материал тела (docs/plan-demo/AUDIO.md §4.3): по нему SfxDirector и ImpactAudio выбирают слой удара.
## Классы: wood, metal, bone, rubber, pan (сковорода), blade (меч, топор) и ground (статика арены — пол, стены).
## Источники: meta "snd_mat" (кэш, можно задать руками) → Weapon.weapon_id → деталь ModularDoll (материал узла чертежа:
## MaterialDef id, иначе PartDef.base_mat / material) → часть Doll v3 (дерево) → meta "material" пропсов Свалки ("wood"/"iron"
## или кг железа) → meta "mat" (крафт) → Breakable — дерево, ExplosiveBarrel — металл → по умолчанию дерево.
class_name SoundMaterial
extends RefCounted

const WOOD := "wood"
const METAL := "metal"
const BONE := "bone"
const RUBBER := "rubber"
const PAN := "pan"
const BLADE := "blade"
const GROUND := "ground"
const METAL_IDS := ["iron", "rust", "rust_red", "brass", "steel", "metal", "tin", "chrome"]
const WEAPON_CLASS := {"pan": PAN, "sword": BLADE, "axe": BLADE, "hammer": METAL, "mace": METAL}
## Слои удара по классу и силе (l / m / h); голова деревянной куклы — свой гулкий «бонк» (SfxDirector).
const HIT_LAYERS := {
	WOOD: ["wood_l", "wood_m", "wood_h"], METAL: ["metal_l", "metal_m", "metal_h"], BONE: ["bone", "bone", "wood_h"],
	RUBBER: ["rubber", "rubber", "rubber"], PAN: ["metal_l", "pan", "pan"], BLADE: ["metal_l", "blade", "blade"],
	GROUND: ["wood_l", "thud", "thud"],
}

## Пол и стены текущей арены (ArenaAmbience ставит по арене): stone | dirt | wood | metal. Сейчас влияет на слой «пола».
static var ground := "stone"


## Класс материала по id MaterialDef / строке meta.
static func from_id(mid: String) -> String:
	var m := mid.to_lower()
	if m == "":
		return WOOD
	if METAL_IDS.has(m) or m.contains("iron") or m.contains("metal") or m.contains("steel"):
		return METAL
	if m.contains("bone"):
		return BONE
	if m.contains("rubber"):
		return RUBBER
	return WOOD


## Класс оружия по weapon_id.
static func weapon_class(id: String) -> String:
	return String(WEAPON_CLASS.get(id, METAL))


static func of_body(b: Object) -> String:
	if b == null or not is_instance_valid(b):
		return GROUND
	if b.has_meta("snd_mat"):
		return String(b.get_meta("snd_mat"))
	var m := _resolve(b)
	b.set_meta("snd_mat", m)
	return m


static func _resolve(b: Object) -> String:
	if b is Weapon:
		return weapon_class((b as Weapon).weapon_id)
	if b is StaticBody3D or b is CSGShape3D or b is GridMap:
		return GROUND
	var n := b as Node
	if n == null:
		return WOOD
	var p := n.get_parent()
	if p is ModularDoll:
		return _modular_part(p as ModularDoll, n.name)
	if p is Doll:
		return WOOD
	var mm: Variant = n.get_meta("material") if n.has_meta("material") else null   # get_meta(k, null) ругается без ключа
	if mm is String:
		return from_id(String(mm))
	if (mm is float or mm is int) and float(mm) > 0.0:
		return METAL
	var mat: Variant = n.get_meta("mat") if n.has_meta("mat") else null
	if mat is String and String(mat) != "":
		return from_id(String(mat))
	var sc := n.get_script() as Script
	if sc != null:
		var path := sc.resource_path
		if path.contains("explosive_barrel"):
			return METAL
		if path.contains("breakable"):
			return WOOD
	return WOOD


static func _modular_part(md: ModularDoll, body_name: String) -> String:
	if md.blueprint == null:
		return WOOD
	for uid in md.uid_body.keys():
		if String(md.uid_body[uid]) != body_name:
			continue
		var mid := md.blueprint.node_mat(String(uid))
		if mid == "":
			var pd := BodyBlueprint.part_def(String(md.blueprint.find_node(String(uid)).get("part", "")))
			mid = pd.material if pd != null else ""
		return from_id(mid)
	return WOOD


## Материал части куклы по имени (ctx.part); нет части — дерево.
static func of_doll_part(doll: Node, part: String) -> String:
	if doll == null or not is_instance_valid(doll) or not doll is Doll or part == "":
		return WOOD
	var b: Variant = (doll as Doll).parts.get(part, null)
	return of_body(b) if b != null else WOOD


## Слой удара: size 0 — лёгкий, 1 — средний, 2 — тяжёлый.
static func hit_layer(mat: String, size: int) -> String:
	var row: Array = HIT_LAYERS.get(mat, HIT_LAYERS[WOOD])
	return String(row[clampi(size, 0, 2)])
