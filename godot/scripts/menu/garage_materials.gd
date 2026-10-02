## Материалы гаража главного меню (docs/plan-demo/MENU_GARAGE.md) по ролям. Модели гаража (tools/blender/garage_kit.py →
## assets/models/garage/Garage_*.glb) несут ПЛОСКИЕ материалы, имя материала = роль (Wood, Iron, PaintNavy, Hazard, Screen…).
## apply(узел) обходит MeshInstance3D и ставит каждой поверхности материал роли (surface override) — как kit_import.gd у кита,
## только во время выполнения: так glb не тащат копии текстур, а правка таблицы ниже сразу видна во всех моделях.
## Текстуры: kit/tex (дерево, железо, латунь — общие с куклами) и assets/textures/garage (tools/gen_garage_textures.py).
## Развёртка моделей — коробкой в метрах: 1 тайл = 1 м (uv1_scale = 1).
class_name GarageMaterials
extends RefCounted

const KIT := "res://assets/materials/kit/tex/"
const GAR := "res://assets/textures/garage/"

## Роль → параметры: set — папка с albedo/normal/roughness[/metallic], ext — расширение файлов, tint — albedo_color,
## rough/metal — константы (если нет карты), emi — цвет свечения и energy, alpha — прозрачность.
const SPEC := {
	"Wood": {"set": KIT + "wood/", "ext": "webp", "tint": Color(0.72, 0.5, 0.42)},
	"WoodDark": {"set": KIT + "wood_dark/", "ext": "webp", "tint": Color(0.74, 0.58, 0.5)},
	"WoodWall": {"set": KIT + "wood_plank/", "ext": "webp", "tint": Color(0.42, 0.32, 0.26)},
	"Iron": {"set": KIT + "iron/", "ext": "webp", "tint": Color(1.1, 1.1, 1.15), "metal": 0.6},
	"Steel": {"color": Color(0.52, 0.53, 0.55), "rough": 0.38, "metal": 0.85},
	"Brass": {"set": KIT + "brass_worn/", "ext": "webp", "tint": Color(1, 1, 1)},
	"Bronze": {"set": KIT + "brass_worn/", "ext": "webp", "tint": Color(0.95, 0.66, 0.48)},
	"PaintNavy": {"set": GAR + "paint_metal/", "ext": "png", "tint": Color(0.22, 0.31, 0.47)},
	"PaintOlive": {"set": GAR + "paint_metal/", "ext": "png", "tint": Color(0.40, 0.43, 0.26)},
	"PaintRed": {"set": GAR + "paint_metal/", "ext": "png", "tint": Color(0.72, 0.15, 0.11)},
	"PaintCream": {"set": GAR + "paint_metal/", "ext": "png", "tint": Color(0.92, 0.85, 0.7)},
	"PaintGreen": {"set": GAR + "paint_metal/", "ext": "png", "tint": Color(0.2, 0.37, 0.27)},
	"PaintGrey": {"set": GAR + "paint_metal/", "ext": "png", "tint": Color(0.38, 0.4, 0.42)},
	"Hazard": {"set": GAR + "hazard/", "ext": "png", "tint": Color(1, 1, 1)},
	"Tread": {"set": GAR + "tread/", "ext": "png", "tint": Color(1, 1, 1), "metal": 0.7},
	"Floor": {"set": GAR + "floor/", "ext": "png", "tint": Color(1, 1, 1)},
	"Rust": {"set": KIT + "rust_metal/", "ext": "webp", "tint": Color(1, 1, 1)},
	"Rope": {"set": KIT + "rope/", "ext": "webp", "tint": Color(1, 1, 1)},
	"Rubber": {"color": Color(0.05, 0.05, 0.05), "rough": 0.85},
	"Grille": {"color": Color(0.07, 0.07, 0.08), "rough": 0.6, "metal": 0.3},
	"Enamel": {"color": Color(0.92, 0.9, 0.82), "rough": 0.35},
	"Ceramic": {"color": Color(0.9, 0.88, 0.82), "rough": 0.3},
	"Coffee": {"color": Color(0.1, 0.05, 0.02), "rough": 0.1},
	"Pot": {"color": Color(0.6, 0.3, 0.18), "rough": 0.8},
	"ClothRed": {"set": GAR + "paint_metal/", "ext": "png", "tint": Color(0.55, 0.1, 0.09), "rough": 0.9, "metal": 0.0},
	"Paper": {"color": Color(0.88, 0.83, 0.72), "rough": 0.9},
	"Glass": {"color": Color(0.6, 0.7, 0.8, 0.22), "rough": 0.05, "alpha": true},
	"Screen": {"color": Color(0.02, 0.03, 0.04), "rough": 0.15, "emi": [Color(0.15, 0.25, 0.4), 0.3]},
	"NullGlow": {"color": Color(0, 0, 0), "emi": [Color(0.62, 0.40, 1.0), 1.6]},
	"Bulb": {"color": Color(0, 0, 0), "emi": [Color(1.0, 0.78, 0.5), 6.0]},
	"LampRed": {"color": Color(0, 0, 0), "emi": [Color(1.0, 0.12, 0.05), 5.0]},
	"LampAmber": {"color": Color(0, 0, 0), "emi": [Color(1.0, 0.6, 0.2), 1.6]},
	"LampGreen": {"color": Color(0, 0, 0), "emi": [Color(0.25, 1.0, 0.35), 4.0]},
	"Leaves": {"tex": GAR + "leaves.png", "rough": 0.7, "scissor": true},
	"LiveryOrange": {"set": GAR + "paint_metal/", "ext": "png", "tint": Color(0.95, 0.45, 0.1)},
	"LiveryTeal": {"set": GAR + "paint_metal/", "ext": "png", "tint": Color(0.16, 0.6, 0.6)},
	"EyeGlow": {"color": Color(0, 0, 0), "emi": [Color(0.35, 0.9, 1.0), 4.0]},
	# картинки на моделях с UV 0..1 (tools/gen_garage_textures.py)
	"Blueprint": {"tex": GAR + "blueprint.png", "rough": 0.85},
	"BannerCloth": {"tex": GAR + "banner.png", "rough": 0.95},
	"Rug": {"tex": GAR + "rug.png", "normal": GAR + "rug_normal.png", "rough": 0.95},
	"Photo_A": {"tex": GAR + "photo_a.png", "rough": 0.6},
	"Photo_B": {"tex": GAR + "photo_b.png", "rough": 0.6},
	"Photo_C": {"tex": GAR + "photo_c.png", "rough": 0.6},
	"Photo_D": {"tex": GAR + "photo_d.png", "rough": 0.6},
	"Photo_E": {"tex": GAR + "photo_e.png", "rough": 0.6},
	"Photo_F": {"tex": GAR + "photo_f.png", "rough": 0.6},
	"Poster_A": {"tex": GAR + "poster_a.png", "rough": 0.8},
	"Poster_B": {"tex": GAR + "poster_b.png", "rough": 0.8},
	"Poster_C": {"tex": GAR + "poster_c.png", "rough": 0.8},
}

static var _cache := {}


## Материал роли (кэш); null — роль неизвестна (остаётся плоский материал glb).
static func get_material(role: String) -> Material:
	if _cache.has(role):
		return _cache[role]
	var m: Material = _build(role) if SPEC.has(role) else null
	_cache[role] = m
	return m


## Ставит материалы ролей всем поверхностям под node; возвращает число поверхностей, получивших материал.
static func apply(node: Node) -> int:
	var n := 0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var cur := mi.mesh.surface_get_material(i)
			var role := _role(cur.resource_name if cur != null else "")
			var m := get_material(role)
			if m != null:
				mi.set_surface_override_material(i, m)
				n += 1
	for c in node.get_children():
		n += apply(c)
	return n


## Имя материала glb → роль: Blender добавляет суффиксы .001 / _001 — отрезаем.
static func _role(raw: String) -> String:
	var s := raw
	var dot := s.find(".")
	if dot > 0:
		s = s.substr(0, dot)
	var re := RegEx.create_from_string("_\\d{3}$")
	return re.sub(s, "")


static func _tex(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func _build(role: String) -> Material:
	var s: Dictionary = SPEC[role]
	var m := StandardMaterial3D.new()
	m.resource_name = role
	if s.has("set"):
		var d: String = s["set"]
		var ext: String = s["ext"]
		m.albedo_texture = _tex(d + "albedo." + ext)
		m.albedo_color = s.get("tint", Color.WHITE)
		var r := _tex(d + "roughness." + ext)
		if r != null:
			m.roughness_texture = r
			m.roughness = 1.0
		var nm := _tex(d + "normal." + ext)
		if nm != null:
			m.normal_enabled = true
			m.normal_texture = nm
		var mt := _tex(d + "metallic." + ext)
		if mt != null and not s.has("metal"):
			m.metallic_texture = mt
			m.metallic = 1.0
	if s.has("tex"):
		m.albedo_texture = _tex(s["tex"])
	if s.has("normal"):
		m.normal_enabled = true
		m.normal_texture = _tex(s["normal"])
	if s.has("color"):
		m.albedo_color = s["color"]
	if s.has("rough"):
		m.roughness = s["rough"]
		m.roughness_texture = null if not s.has("set") else m.roughness_texture
	if s.has("metal"):
		m.metallic = s["metal"]
		if s.has("set"):
			var mt2 := _tex(String(s["set"]) + "metallic." + String(s["ext"]))
			if mt2 != null:
				m.metallic_texture = mt2
	if s.has("emi"):
		m.emission_enabled = true
		m.emission = s["emi"][0]
		m.emission_energy_multiplier = s["emi"][1]
	if s.get("alpha", false):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if s.get("scissor", false):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.4
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m
