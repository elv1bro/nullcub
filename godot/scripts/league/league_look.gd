## Вид бойца NULL League (docs/plan-demo/ART_NULL.md, «Детали лиги v2»; кадр стиля — tools/blender/league_fighters.py).
## Узел-ребёнок куклы (ModularDoll) в пресетах scenes/body/presets/league_*.tscn — их пишет tools/build_league.gd.
## Детали лиги сами по себе — детали кита (трофей встаёт на любого бойца и там выглядит как у хозяина), а боец лиги отличается
## только этим узлом, после Doll._ready (цвет игрока уже покрашен):
##   • шары суставов (Connector_*) ужаты до JOINT_SCALE — между шаром и сегментом зазор, светящееся кольцо детали вокруг шара
##     («парящий» сустав с листов автора);
##   • всё Shirt_* (шары суставов, кольцо на ядре, манжеты) — светящийся фиолетовый вместо цвета игрока: у лиги свой цвет;
##   • плашка лица (Face*) — визор с глазом (FACE_TEX, ключ face узла головы в чертеже) и светится.
class_name LeagueLook
extends Node

const JOINT_SCALE := 0.55
const FACE_TEX := "res://assets/textures/league/league_face.png"
const GLOW_ALBEDO := Color(0.09, 0.025, 0.2)   # проход «взрослого вида» 23.10: темнее и глуше (было 0.16, 0.03, 0.4 и энергия 1.6)
const GLOW_EMISSION := Color(0.3, 0.07, 0.62)
const GLOW_ENERGY := 0.6
const FACE_ENERGY := 1.0
## Аоэлюн (ядро kit_core_aoe_*) — проход 2 «взрослого вида» (C LEAGUE PRO: керамика, графит, латунь): свет суставов и пояса — тусклый
## янтарь, как AOE_MATS League_Glow (tools/build_league.gd), а не фиолет Лиги.
const AOE_TAG := "_aoe_"
const AOE_ALBEDO := Color(0.12, 0.05, 0.015)
const AOE_EMISSION := Color(0.9, 0.42, 0.12)
const AOE_ENERGY := 0.4
const CONNECTOR_PREFIX := "Connector_"

static var _glow: StandardMaterial3D
static var _glow_aoe: StandardMaterial3D
static var _face_cache: Dictionary = {}   # исходный материал Face (с фото) -> копия со свечением

## Сколько поверхностей перекрашено / шаров ужато / лиц засвечено последним apply() — для проб.
var shirt_surfaces := 0
var connectors := 0
var faces := 0
var applied := false
var _aoe := false


func _ready() -> void:
	var d := get_parent()
	if d == null:
		return
	# Match.respawn_doll пересоздаёт у новой куклы детей со скриптом (новый экземпляр), а сцена пресета уже несёт свой LeagueLook:
	# второй ужал бы шары ещё раз — работает только первый по порядку
	for c in d.get_children():
		if c is LeagueLook:
			if c != self:
				queue_free()
				return
			break
	if d.is_node_ready():
		apply()
	else:
		d.ready.connect(apply, CONNECT_ONE_SHOT)


static func glow_material(aoe := false) -> StandardMaterial3D:
	if aoe:
		if _glow_aoe == null:
			_glow_aoe = _make_glow(AOE_ALBEDO, AOE_EMISSION, AOE_ENERGY)
		return _glow_aoe
	if _glow == null:
		_glow = _make_glow(GLOW_ALBEDO, GLOW_EMISSION, GLOW_ENERGY)
	return _glow


static func _make_glow(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var g := StandardMaterial3D.new()
	g.resource_name = "Shirt_League"   # Shirt* — BodyPaint и дальше считает поверхность «цветом игрока» (без краски)
	g.albedo_color = albedo
	g.roughness = 0.35
	g.emission_enabled = true
	g.emission = emission
	g.emission_energy_multiplier = energy
	return g


## Боец Аоэлюн: ядро чертежа — деталь набора Аоэлюн.
static func is_aoe(doll: Node) -> bool:
	var bp: Variant = doll.get("blueprint") if doll != null else null
	if not bp is BodyBlueprint:
		return false
	var core: PartDef = (bp as BodyBlueprint).core_def()
	return core != null and String(core.id).contains(AOE_TAG)


func apply() -> void:
	var d := get_parent()
	shirt_surfaces = 0
	connectors = 0
	faces = 0
	_aoe = is_aoe(d)
	_walk(d)
	applied = true


func _walk(n: Node) -> void:
	if n is Node3D and String(n.name).begins_with(CONNECTOR_PREFIX):
		(n as Node3D).scale *= JOINT_SCALE
		connectors += 1
	if n is MeshInstance3D:
		_surfaces(n as MeshInstance3D)
	for c in n.get_children():
		if c != self:
			_walk(c)


func _surfaces(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	for s in range(mi.mesh.get_surface_count()):
		var m := mi.get_active_material(s)
		if m == null:
			continue
		var nm := String(m.resource_name)
		if nm.begins_with("Shirt"):
			mi.set_surface_override_material(s, glow_material(_aoe))
			shirt_surfaces += 1
		elif nm.begins_with("Face") and m is BaseMaterial3D:
			mi.set_surface_override_material(s, _face_glow(m as BaseMaterial3D))
			faces += 1


func _face_glow(src: BaseMaterial3D) -> BaseMaterial3D:
	if _face_cache.has(src):
		return _face_cache[src]
	var dup := src.duplicate() as BaseMaterial3D
	if dup.albedo_texture == null:
		dup.albedo_texture = load(FACE_TEX) as Texture2D
	dup.emission_enabled = true
	dup.emission = Color.BLACK     # оператор ADD: (emission + карта) × энергия — с белым светилось всё стекло, а не глаз
	dup.emission_texture = dup.albedo_texture
	dup.emission_energy_multiplier = FACE_ENERGY
	dup.roughness = 0.6            # матовое стекло: глянец отражал свет зала, и тёмный визор выходил серым
	dup.metallic_specular = 0.1
	_face_cache[src] = dup
	return dup
