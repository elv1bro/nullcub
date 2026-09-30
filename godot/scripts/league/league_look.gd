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
const GLOW_ALBEDO := Color(0.16, 0.03, 0.4)
const GLOW_EMISSION := Color(0.5, 0.12, 1.0)
const GLOW_ENERGY := 1.6
const FACE_ENERGY := 1.0
const CONNECTOR_PREFIX := "Connector_"

static var _glow: StandardMaterial3D
static var _face_cache: Dictionary = {}   # исходный материал Face (с фото) -> копия со свечением

## Сколько поверхностей перекрашено / шаров ужато / лиц засвечено последним apply() — для проб.
var shirt_surfaces := 0
var connectors := 0
var faces := 0
var applied := false


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


static func glow_material() -> StandardMaterial3D:
	if _glow == null:
		_glow = StandardMaterial3D.new()
		_glow.resource_name = "Shirt_League"   # Shirt* — BodyPaint и дальше считает поверхность «цветом игрока» (без краски)
		_glow.albedo_color = GLOW_ALBEDO
		_glow.roughness = 0.35
		_glow.emission_enabled = true
		_glow.emission = GLOW_EMISSION
		_glow.emission_energy_multiplier = GLOW_ENERGY
	return _glow


func apply() -> void:
	var d := get_parent()
	shirt_surfaces = 0
	connectors = 0
	faces = 0
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
			mi.set_surface_override_material(s, glow_material())
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
	dup.emission = Color.WHITE
	dup.emission_texture = dup.albedo_texture
	dup.emission_energy_multiplier = FACE_ENERGY
	dup.roughness = 0.6            # матовое стекло: глянец отражал свет зала, и тёмный визор выходил серым
	dup.metallic_specular = 0.1
	_face_cache[src] = dup
	return dup
