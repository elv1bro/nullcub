## Материал кита тела v2 — отдельная ось крафта (docs/plan-demo/BODY_KIT.md §4). Файлы: data/body/materials/<id>.tres
## (пишет tools/build_body_kit.gd). Узел чертежа с ключом "mat" заменяет поверхности Base_* детали на surface и меняет физику:
## масса узла = PartDef.mass × density / density материала по умолчанию (PartDef.base_mat), PhysicsMaterial тела — friction/bounce,
## удар частью — × body_mult (meta "body_mult", Damage.body_mult_of_body), магнит Свалки — iron.
class_name MaterialDef
extends Resource

const DIR := "res://data/body/materials/"
## Порядок плашек в мастерской (= таблица BODY_KIT.md §4).
const ORDER := ["wood", "maple", "wood_dark", "planks", "paint_red", "paint_blue", "paint_yellow", "paint_white", "paint_green",
	"rust_red", "iron", "rust", "brass", "bone", "rubber"]

@export var id := ""
@export var title := ""
## Материал поверхностей Base_* (assets/materials/kit/Base_<Mat>.tres, resource_name начинается на "Base_").
@export var surface: Material
## Цвет плашки в мастерской.
@export var swatch := Color.WHITE
## Множитель массы относительно дерева (дерево = 1.0).
@export var density := 1.0
@export var friction := 0.6
@export var bounce := 0.05
## Множитель урона ударом частью из этого материала.
@export var body_mult := 1.0
## Притягивается магнитом Свалки (ScrapMachine.iron_mass).
@export var iron := false

static var _cache: Dictionary = {}


static func get_def(mat_id: String) -> MaterialDef:
	if mat_id == "":
		return null
	if _cache.has(mat_id):
		return _cache[mat_id]
	var path := DIR + mat_id + ".tres"
	var d: MaterialDef = null
	if ResourceLoader.exists(path):
		d = load(path) as MaterialDef
	_cache[mat_id] = d
	return d


## id всех материалов, которые есть на диске, в порядке ORDER.
static func all_ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for m in ORDER:
		if get_def(m) != null:
			out.append(m)
	return out


## PhysicsMaterial по материалу (новый объект: у каждого тела свой).
func physics_material() -> PhysicsMaterial:
	var pm := PhysicsMaterial.new()
	pm.friction = friction
	pm.bounce = bounce
	return pm
