## «Правило кадра» и «дорогой пластик» на самой кукле (docs/plan-demo/look/frame.md, автозагрузка LookFrame): без замены моделей,
## без новых узлов в дереве куклы — только бит слоя на мешах и материалы. Три части, каждая включается и снимается отдельно:
##   • rim  — бит RIM_BIT мешам куклы: контровой свет LookFrame (DirectionalLight3D сзади-сверху) светит ТОЛЬКО на этот слой
##            (light_cull_mask), арену не трогает. Материалы кукол не меняются — работает для манекена, кита, лиги, врагов;
##   • glow — свечение цвета игрока: обмотки, краска цвета игрока и шары суставов кита (поверхности Shirt*, они уже свои у каждой
##            куклы — Doll._recolor / ModularDoll._recolor) получают эмиссию своего цвета ПРЯМО В МАТЕРИАЛЕ (исходные значения —
##            meta META_GLOW на материале; копия материала, сделанная потом чужим _recolor, несёт meta с собой, и снять свечение
##            можно и с неё); окошко ядра кита и полосы про-лиги / лиги (GLOW_SWAP, общие ресурсы кита) — подмена на копию с
##            эмиссией цвета куклы (кэш на исходник и цвет), только если поверхность ещё не перекрашена кем-то (SquadLook);
##   • coat — лак (clearcoat) на краске и пластике кита (COAT_PREFIXES): подмена активного материала поверхности на копию с лаком
##            (кэш на исходник — общий для всех кукол); у Shirt_Kit (своя у каждой куклы) — прямо в материале.
## Подмены (swap) помнят прежний override поверхности в meta меша META_SWAP и возвращают его, только если на поверхности всё ещё
## наша копия (чужая замена за это время остаётся). Уже светящиеся поверхности (лига, SquadLook) и враги (EnemyLook — общий
## перекрашенный материал) не трогаются.
class_name FrameDress
extends RefCounted

## Слой «бойцы» для контрового света (бит видимого слоя; занятые: BodyPaint.PAINT_LAYER_BIT 1 << 11, CritCinematic 1 << 19).
const RIM_BIT := 1 << 16
const SKIP_PREFIXES := ["Outline", "Sticker", "Face"]
const META_GLOW := "lf_glow0"     # на материале: исходные emission_* до свечения
const META_COAT := "lf_coat0"     # на материале: исходные clearcoat_* до лака (Shirt_Kit — прямо в материале)
const META_SWAP := "lf_swap"      # на меше: {"<вид>:<поверхность>": [прежний override, наша копия]}
const META_MINE := "lf_mine"      # на нашей копии: вид подмены ("glow" | "coat")

## Свечение: обмотки манекена — ткань, тише; краска цвета игрока и шары кита — пластик, ярче.
const GLOW_FABRIC := 0.9
const GLOW_KIT := 1.0
const GLOW_SWAP := ["CoreGlow", "Pro_Glow", "League_Glow"]
const GLOW_SWAP_ENERGY := 1.6
## Лак: краска и пластик кита. Дерево, железо, резина, кость — без лака.
const COAT_PREFIXES := ["Base_Paint", "Base_Pink", "Shirt_Kit", "Pro_", "League_", "Gem"]
const COAT := 0.75
const COAT_ROUGHNESS := 0.16

static var _glow_cache: Dictionary = {}   # "id исходника|цвет" → копия с эмиссией
static var _coat_cache: Dictionary = {}   # исходный материал → копия с лаком


## Меши куклы, которые красит проход (без обводки, наклеек, лица).
static func meshes(doll: Node) -> Array:
	var out: Array = []
	if doll == null or not is_instance_valid(doll):
		return out
	for n in doll.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var skip := false
		for pre in SKIP_PREFIXES:
			skip = skip or String(mi.name).begins_with(pre)
		if not skip:
			out.append(mi)
	return out


# --- rim: бит слоя ---

static func set_rim(doll: Node, on: bool) -> int:
	var n := 0
	for mi in meshes(doll):
		var m := mi as MeshInstance3D
		if on:
			m.layers |= RIM_BIT
		else:
			m.layers &= ~RIM_BIT
		n += 1
	return n


# --- glow: свечение цвета игрока ---

static func set_glow(doll: Node, on: bool, colour: Color) -> int:
	if doll == null or not is_instance_valid(doll):
		return 0
	var enemy := doll.get_node_or_null("EnemyLook") != null
	var kit := doll is ModularDoll
	var n := 0
	for mi in meshes(doll):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s) as BaseMaterial3D
			if mat == null:
				continue
			var nm := mat.resource_name
			if nm.begins_with("Shirt"):
				if not on:
					n += int(_restore(mat, META_GLOW))
				elif not enemy and m.get_surface_override_material(s) != null and (not mat.emission_enabled or mat.has_meta(META_GLOW)):
					_remember(mat, META_GLOW, ["emission_enabled", "emission", "emission_energy_multiplier"])
					var c := Color(mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b)
					mat.emission_enabled = true
					mat.emission = c
					mat.emission_energy_multiplier = GLOW_KIT if kit or nm.begins_with("Shirt_Kit") else GLOW_FABRIC
					n += 1
			elif _starts(nm, GLOW_SWAP):   # наша копия носит то же имя (duplicate)
				if not on:
					n += int(_unswap(m, s, "glow"))
				elif not enemy and m.get_surface_override_material(s) == null:
					_swap(m, s, "glow", _glow_copy(mat, colour))
					n += 1
	return n


static func _glow_copy(src: BaseMaterial3D, colour: Color) -> BaseMaterial3D:
	var key := "%d|%s" % [src.get_instance_id(), colour.to_html(false)]
	if _glow_cache.has(key):
		return _glow_cache[key]
	var g := src.duplicate() as BaseMaterial3D
	g.emission_enabled = true
	g.emission = colour.lightened(0.25)
	g.emission_energy_multiplier = GLOW_SWAP_ENERGY
	g.set_meta(META_MINE, "glow")
	_glow_cache[key] = g
	return g


# --- coat: лак ---

static func set_coat(doll: Node, on: bool) -> int:
	if not doll is ModularDoll:
		return 0   # манекен — лакированное дерево уже в его материале; лак — краске и пластику кита
	var n := 0
	for mi in meshes(doll):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s) as BaseMaterial3D
			if mat == null:
				continue
			if not on:
				if str(mat.get_meta(META_MINE, "")) == "coat":
					n += int(_unswap(m, s, "coat"))
				elif mat.has_meta(META_COAT):
					n += int(_restore(mat, META_COAT))
				continue
			if not _starts(mat.resource_name, COAT_PREFIXES) or mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			if str(mat.get_meta(META_MINE, "")) == "coat" or (mat.has_meta(META_COAT) and mat.clearcoat_enabled):
				continue
			if mat.resource_name.begins_with("Shirt") and m.get_surface_override_material(s) != null:
				_remember(mat, META_COAT, ["clearcoat_enabled", "clearcoat", "clearcoat_roughness"])
				_coat(mat)
			else:
				_swap(m, s, "coat", _coat_copy(mat))
			n += 1
	return n


static func _coat_copy(src: BaseMaterial3D) -> BaseMaterial3D:
	if _coat_cache.has(src):
		return _coat_cache[src]
	var c := src.duplicate() as BaseMaterial3D
	_coat(c)
	c.set_meta(META_MINE, "coat")
	_coat_cache[src] = c
	return c


static func _coat(m: BaseMaterial3D) -> void:
	m.clearcoat_enabled = true
	m.clearcoat = COAT
	m.clearcoat_roughness = COAT_ROUGHNESS


## Сброс кэшей копий (смена арены: копии живут, пока на них ссылаются поверхности кукол).
static func clear_caches() -> void:
	_glow_cache.clear()
	_coat_cache.clear()


# --- общие ---

static func _starts(s: String, prefixes: Array) -> bool:
	for p in prefixes:
		if s.begins_with(p):
			return true
	return false


static func _remember(m: Material, key: String, props: Array) -> void:
	if m.has_meta(key):
		return
	var d := {}
	for p in props:
		d[p] = m.get(p)
	m.set_meta(key, d)


static func _restore(m: Material, key: String) -> bool:
	if not m.has_meta(key):
		return false
	var d: Dictionary = m.get_meta(key)
	for p in d:
		m.set(p, d[p])
	m.remove_meta(key)
	return true


static func _swap(mi: MeshInstance3D, s: int, kind: String, mine: Material) -> void:
	var rec: Dictionary = mi.get_meta(META_SWAP, {})
	var k := "%s:%d" % [kind, s]
	if not rec.has(k):
		rec[k] = [mi.get_surface_override_material(s), mine]
	else:
		rec[k][1] = mine
	mi.set_meta(META_SWAP, rec)
	mi.set_surface_override_material(s, mine)


static func _unswap(mi: MeshInstance3D, s: int, kind: String) -> bool:
	var rec: Dictionary = mi.get_meta(META_SWAP, {})
	var k := "%s:%d" % [kind, s]
	if not rec.has(k):
		return false
	var pair: Array = rec[k]
	rec.erase(k)
	if rec.is_empty():
		mi.remove_meta(META_SWAP)
	else:
		mi.set_meta(META_SWAP, rec)
	if mi.get_surface_override_material(s) == pair[1]:
		mi.set_surface_override_material(s, pair[0])
		return true
	return false
