## Карта «Полигон» пробного режима «Стычка 3 на 3» (docs/plan-demo/SQUAD.md) — только поведение; сцену proving_ground.tscn собирает
## tools/build_proving_ground.gd из компонентов Руин. От RuinsArena — точки спавна (Spawns/Spawn0..5 в порядке player_index), границы,
## сигнал body_fell (страховочный низ), пропсы. Своё — точки базы команды для возрождения.
class_name ProvingGround
extends RuinsArena

## Ночная карта (proving_ground_night.tscn, автор 05.10: «сделай ещё карту ночью»): окружение, луна и фонари — в сцене (сборщик), а
## дневной нарисованный фон Руин скрипт затемняет в лунный синий (множитель цвета слоёв) и добавляет на небо звёзды и луну.
## Днём и ночью ближний слой фона (размытая полоса травы перед плоскостью боя) спрятан.
@export var night := false
## Ночь ли на карте, что загружена сейчас (трассеры пуль SquadGun ночью ярче — светятся).
static var night_now := false

## Множитель цвета слоёв фона ночью: небо, дальний, средний, ближний.
const NIGHT_TINT := {"Layer4Sky": Color(0.1, 0.13, 0.27), "Layer3Far": Color(0.14, 0.17, 0.3), "Layer2Mid": Color(0.17, 0.2, 0.32),
	"Layer1Fore": Color(0.2, 0.22, 0.3)}
const STARS := 260
const MOON_AT := Vector3(-58.0, 30.0, 1.0)   # в кадре слоя неба (квад 220 × 109 м, центр — середина)


func _init() -> void:
	arena_bounds = AABB(Vector3(-32.0, -2.0, -1.0), Vector3(64.0, 18.0, 2.0))


func _ready() -> void:
	super._ready()
	night_now = night
	var fore := get_node_or_null("Parallax/Layer1Fore") as Node3D
	if fore != null:
		fore.visible = false   # ближний слой фона — размытая полоса травы перед бойцами (автор 05.10: «как-то размыто всё»)
	if night:
		_night_sky()


## Ночь: слои фона — свои копии материалов с тёмно-синим множителем; на квад неба (он приклеен к камере) — звёзды и луна.
func _night_sky() -> void:
	var par := get_node_or_null("Parallax")
	if par == null:
		return
	for n in NIGHT_TINT:
		var layer := par.get_node_or_null(n) as MeshInstance3D
		if layer == null or not (layer.material_override is StandardMaterial3D):
			continue
		var m := (layer.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		m.albedo_color = NIGHT_TINT[n]
		layer.material_override = m
	var sky := par.get_node_or_null("Layer4Sky") as MeshInstance3D
	if sky == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x57a2
	var star := QuadMesh.new()
	star.size = Vector2.ONE
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(0.85, 0.9, 1.0)
	smat.disable_fog = true
	star.material = smat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = star
	mm.instance_count = STARS
	for i in STARS:
		var sz := rng.randf_range(0.18, 0.55)
		var pos := Vector3(rng.randf_range(-108.0, 108.0), rng.randf_range(-4.0, 52.0), 0.5)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(sz, sz, 1.0)), pos))
		mm.set_instance_color(i, Color(1.0, 1.0, 1.0, 1.0) * rng.randf_range(0.5, 1.0))
	smat.vertex_color_use_as_albedo = true
	var stars := MultiMeshInstance3D.new()
	stars.name = "Stars"
	stars.multimesh = mm
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sky.add_child(stars)
	var moon := MeshInstance3D.new()
	moon.name = "Moon"
	var disc := SphereMesh.new()
	disc.radius = 4.5
	disc.height = 9.0
	moon.mesh = disc
	var mmat := StandardMaterial3D.new()
	mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmat.albedo_color = Color(0.85, 0.9, 1.0)
	mmat.emission_enabled = true
	mmat.emission = Color(0.7, 0.8, 1.0)
	mmat.emission_energy_multiplier = 1.6
	mmat.disable_fog = true
	moon.material_override = mmat
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	moon.position = MOON_AT
	sky.add_child(moon)


## Точки базы команды (0 — синие слева, 1 — красные справа): spawn_points() с индексом той же чётности.
func base_points(team: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var pts := spawn_points()
	for i in range(pts.size()):
		if i % 2 == team:
			out.append(pts[i])
	return out


## Флаг команды в «Захвате флага» (SquadFlag): над палубой своей базы, у дальнего края (палуба — tools/build_proving_ground.gd:
## BASE_X 28, верх DECK_Y 2.65), чтобы возрождённые защитники стояли рядом.
const FLAG_AT := Vector2(30.0, 3.7)


func flag_point(team: int) -> Vector3:
	return Vector3(FLAG_AT.x * (-1.0 if team == 0 else 1.0), FLAG_AT.y, 0.0)


## Точки появления ящиков снабжения (SquadMatch, SupplyCrate): над укрытиями и плитами, у середины и у баз — зеркально. Ящик висит
## в воздухе (поле NULL), поэтому точки — над поверхностями (числа — из tools/build_proving_ground.gd: верх укрытий 1.8 / 2.2,
## парящих плит 4.8, верхней площадки 6.65, высоких плит 9.0).
const SUPPLY_POINTS := [Vector2(6.0, 1.2), Vector2(11.0, 2.6), Vector2(16.0, 5.6), Vector2(21.0, 3.0), Vector2(8.0, 9.8),
	Vector2(24.5, 1.2)]


func supply_points() -> Array[Vector3]:
	var out: Array[Vector3] = [Vector3(0.0, 7.4, 0.0)]
	for p in SUPPLY_POINTS:
		for s in [-1.0, 1.0]:
			out.append(Vector3((p as Vector2).x * s, (p as Vector2).y, 0.0))
	return out
