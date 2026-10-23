## «Взрослый вид», проход 2 (docs/plan-demo/grownup_art/README.md): деревянный манекен v3 (doll.tscn / doll_dark.tscn и старые детали
## scenes/body/parts/wood_*.tscn — те же glb assets/models/heroes/mannequin_v3/) без замены glb и запечённых карт. glb не трогаем:
## их же берёт заставка-комикс (BODY_KIT.md §0), там манекен остаётся прежним. Только материалы на инстансе (override поверхности):
##   • Wood_<Часть> — запечённое дерево: albedo × тон «старого дерева» (клён светлее ореха — разница P1 / P2 остаётся), шероховатость
##     выше (лак затёрт). Деталь-нормаль (detail / triplanar) НЕ ставим: BodyPaint.inpass_block отдаёт такие материалы в прозрачный
##     проход краски («feature») — paint_probe «краска в проходе поверхности» краснеет;
##   • Joint / Pin — шары и штифты v3 (плоская серая пластмасса) → воронёная сталь кита (assets/materials/kit/Joint.tres, Pin.tres);
##   • Shirt* (цвет игрока), Face* (плашка лица) не трогаются.
## Физика, формы и массы не меняются. Копия на исходный материал — общая у всех кукол (кэш), как материалы кита.
## Зовёт Doll._ready перед _recolor (ModularDoll тоже: старые детали wood_* в его чертежах).
class_name MannequinLook
extends RefCounted

const KIT_DIR := "res://assets/materials/kit/"
const WOOD_PREFIX := "Wood_"
## Тон дерева, ЛИНЕЙНЫЙ множитель запечённого albedo. Клён (~0.36 / 0.25 / 0.14) → ≈ 0.18 / 0.12 / 0.08 — уровень старого дерева кита
## (aged_wood × Wood 1.3), с уходом из рыжего в серо-коричневый; орех (~0.15 / 0.10 / 0.07) темнеет меньше — иначе станет чёрным.
const TINT_LIGHT := Color(0.5, 0.48, 0.54)
const TINT_DARK := Color(0.82, 0.8, 0.86)
const ROUGH := 1.0
## Шары и штифты v3 → материалы кита (по имени материала glb).
const SWAP := {"Joint": "Joint", "Pin": "Pin"}

static var _cache: Dictionary = {}   # исходный материал -> копия «старого дерева» / материал кита


## Поверхности мешей под root. Число заменённых поверхностей (для проб).
static func apply(root: Node) -> int:
	var n := 0
	for mi in _meshes(root):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var cur := m.get_active_material(s)
			var rep := material_for(cur)
			if rep != null and rep != cur:
				m.set_surface_override_material(s, rep)
				n += 1
	return n


## Замена материала cur (null — оставить как есть). Только материалы самих glb манекена (resource_path без .tres): то, что уже
## подменено (кит, лига, краска), не трогается.
static func material_for(cur: Material) -> Material:
	if cur == null or not cur is BaseMaterial3D or cur.resource_path.ends_with(".tres"):
		return null
	if _cache.has(cur):
		return _cache[cur]
	var nm := _clean(String(cur.resource_name))
	var out: Material = null
	if nm.begins_with(WOOD_PREFIX):
		out = _aged(cur as BaseMaterial3D)
	elif SWAP.has(nm):
		var p: String = KIT_DIR + String(SWAP[nm]) + ".tres"
		out = load(p) as Material if ResourceLoader.exists(p) else null
	_cache[cur] = out
	return out


static func _aged(src: BaseMaterial3D) -> BaseMaterial3D:
	var m := src.duplicate() as BaseMaterial3D
	var dark := src.albedo_texture != null and src.albedo_texture.resource_path.contains("/dark/")
	var t := TINT_DARK if dark else TINT_LIGHT
	var a := src.albedo_color.srgb_to_linear()
	m.albedo_color = Color(a.r * t.r, a.g * t.g, a.b * t.b, a.a).linear_to_srgb()
	m.roughness = ROUGH
	return m


## «Wood_Torso.001» → «Wood_Torso».
static func _clean(s: String) -> String:
	var i := s.rfind(".")
	return s.substr(0, i) if i > 0 and s.substr(i + 1).is_valid_int() else s


static func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		if String(c.name).begins_with("Connector_"):
			continue
		out.append_array(_meshes(c))
	return out
