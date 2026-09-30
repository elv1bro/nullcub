## Деталь тела или оружия (docs/plan-demo/BODY_CRAFT.md §1). Файлы: data/body/parts/<id>.tres.
## Сцена детали — RigidBody3D с маркерами Socket (куда крепится к родителю, −Y = направление роста)
## и Anchor_<имя> (куда крепятся дети; метаданные accepts / joint_group / rest_deg / mirror).
class_name PartDef
extends Resource

const KINDS := ["core", "head", "limb", "hand", "foot", "joint", "handle", "weapon_head", "mod", "chain", "plate", "deco", "armor"]
## Виды, которые всегда сливаются с родителем (attach fixed): декор и броня кита v2 (docs/plan-demo/BODY_KIT.md §5.1).
const FIXED_KINDS := ["deco", "armor"]

@export var id := ""
## Подпись в мастерской.
@export var title := ""
## Вид детали — одно из KINDS; якоря принимают детей по виду (Anchor.meta accepts).
@export var kind := "limb"
@export var scene: PackedScene
## Кг; builder пишет в RigidBody3D, при слиянии (attach = fixed) прибавляется к родителю.
@export var mass := 1.0
## Стоимость в бюджете Ядра (BodyBlueprint.energy_budget).
@export var energy := 10
## "joint" — своё тело и сустав у якоря родителя; "fixed" — формы и меш сливаются с телом родителя.
@export_enum("joint", "fixed") var attach := "joint"
## Множитель урона этой частью как бьющей. У деталей со своим телом урон читает таблицу Tuning.BODY_MULT по имени тела (× материал
## узла × hit_mult, ModularDoll meta body_mult) — здесь то же число по name_prefix (builder-ы пишут таблицу, kit_probe сверяет), сам
## по себе он в бою не читается. У декора / брони (FIXED_KINDS) — бонус к удару телом-хозяином (шипы 1.25), он в бою работает
## (BODY_KIT.md §5.4).
@export var body_mult := 1.0
## Множитель удара ЭТОЙ формой — шипы, рога, клешня (у верёвки, щупальца < 1); на материал и таблицу имени умножается: meta body_mult
## тела = Damage.body_mult_of(имя) × MaterialDef.body_mult × hit_mult × Π body_mult слитого декора / брони (ModularDoll, BODY_KIT.md
## §5.4). Только у деталей со своим телом (у кита — из kit_catalog.json, builder); у старых деталей и у fixed-видов 1.0.
@export var hit_mult := 1.0
## Профиль скорости формы (WORKSHOP_V3.md §4, Damage.shape_mult): "sharp" — колющая (шипы, когти, рога: бонус на медленном тычке),
## "blunt" — дробящая (кулак, тиски, тяжёлые головы, наруч: бонус на размахе), "soft" / "" — постоянный множитель. Бонус с 30.09
## не выше Tuning.SHAPE_MULT_MAX (1.2); у декора / брони — вместе с body_mult (форма хозяина, не множитель поверх).
@export var hit_profile := ""
@export_enum("wood", "iron", "cloth") var material := "wood"
## Префикс имени тела в собранной кукле: UpperArm, LowerArm, Hand, UpperLeg, LowerLeg, Foot, Head, Torso, Chain, Handle…
@export var name_prefix := "Part"
## Множитель урона оружия от этой детали (головки и моды: лезвие, шипы); у частей тела 1.0. Работает только в CraftedWeapon:
## навершие, поставленное на тело, сливается с конечностью массой и формами (удар телом — body_mult тела, BODY_KIT.md §5.4).
@export var weapon_mult := 1.0
## Кит v2 (BODY_KIT.md §4): id MaterialDef поверхностей Base_* по умолчанию; "" — деталь не красится (старые wood_*, junk_*, craft).
@export var base_mat := ""
## Кит v2 (BODY_KIT.md §5.4): на суставе, которым деталь висит на родителе, ModularDoll ставит коннектор (шар цвета игрока).
@export var connector := false


func is_valid() -> bool:
	return id != "" and scene != null and KINDS.has(kind) and mass > 0.0
