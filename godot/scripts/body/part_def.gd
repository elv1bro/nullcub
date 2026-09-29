## Деталь тела или оружия (docs/plan-demo/BODY_CRAFT.md §1). Файлы: data/body/parts/<id>.tres.
## Сцена детали — RigidBody3D с маркерами Socket (куда крепится к родителю, −Y = направление роста)
## и Anchor_<имя> (куда крепятся дети; метаданные accepts / joint_group / rest_deg / mirror).
class_name PartDef
extends Resource

const KINDS := ["core", "head", "limb", "hand", "foot", "joint", "handle", "weapon_head", "mod", "chain", "plate"]

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
## Множитель урона этой частью как бьющей. Пока урон читает таблицу Tuning.BODY_MULT по name_prefix — держим совпадающим.
@export var body_mult := 1.0
@export_enum("wood", "iron", "cloth") var material := "wood"
## Префикс имени тела в собранной кукле: UpperArm, LowerArm, Hand, UpperLeg, LowerLeg, Foot, Head, Torso, Chain, Handle…
@export var name_prefix := "Part"
## Множитель урона оружия от этой детали (головки и моды: лезвие, шипы); у частей тела 1.0.
@export var weapon_mult := 1.0


func is_valid() -> bool:
	return id != "" and scene != null and KINDS.has(kind) and mass > 0.0
