## Арена «Свалка» (биом 1 THE SCRAP, первый уровень: Core игрока просыпается в куче хлама на дне Башни; референс —
## docs/refs/biomes/01-scrap/scenes.png, docs/plan-demo/BIOMES.md §1, LORE.md) — только поведение.
## Сцена scrap.tscn собрана builder-ом tools/build_arena_scrap.gd ИЗ КОМПОНЕНТНЫХ СЦЕН scenes/props/scrap/*.tscn: пол из
## модулей кита (kit_platform_lower), платформы на опорах, балка на цепях над пропастью, скат, флаги-короны на рамах, кучи
## хлама и кукол листа 01 (bodies_*), свободные куски (bit_*), физпропсы листа 02 (prop_*), параллакс-фон, свет, пыль и искры.
## API как у RuinsArena / WorkshopArena / VoidArena: spawn_points(), bounds(), breakables(), parallax(), сигнал body_fell —
## пропасть («провал в недра», Area3D "DeathZone"): площадка (scenes/playground.gd) делает Doll.knock_out() → KO kind "self".
## Под пропастью — твёрдое дно Bounds/PitBottom: оружие, пропсы и части KO-нутой куклы там лежат, а не падают бесконечно.
class_name ScrapArena
extends Node3D

signal body_fell(body: Node3D)

## Границы для камеры и боя: невидимые стены x=±18, потолок y=12; снизу −6 — у DynamicCamera floor_inset 4.5 (по умолчанию),
## значит клэмп центра идёт от y=−1.5 (полоса переднего хлама под полом), а максимум зума — половина полной высоты 20 м:
## кадр 16:9 на полном отъезде ≈ 35.6 × 20 м — вся арена (камера z ≈ 24, центр y ≈ 6 — диапазон, под который резан фон
## parallax_scrap.tscn: |x| ≤ 20, y камеры 2.5–10).
@export var arena_bounds := AABB(Vector3(-18.0, -6.0, -1.0), Vector3(36.0, 20.0, 2.0))
## Пропасть на плоскости боя (x0, y0, ширина, глубина до зоны KO): край пола — y=0, зона KO начинается на y=−3.
@export var pit_rect := Rect2(-9.5, -3.0, 3.0, 3.0)
## «Ключ камеры» (SpotLight3D CameraKey): смещение от активной камеры (выше и левее) — светит в плоскость кукол z=0.
@export var key_offset := Vector3(-2.0, 2.5, 0.0)

var _key: SpotLight3D


func _ready() -> void:
	var dz := get_node_or_null("DeathZone")
	if dz is Area3D:
		(dz as Area3D).body_entered.connect(func(b: Node3D) -> void: body_fell.emit(b))
	_key = get_node_or_null("CameraKey") as SpotLight3D


## Ключевой свет едет за камерой: точка на плоскости кукол под центром кадра освещена сильнее, чем задний план за ней.
func _process(_delta: float) -> void:
	if _key == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := cam.global_position
	_key.global_position = c + key_offset
	_key.look_at(Vector3(c.x, c.y, 0.0), Vector3.UP)


## Четыре точки спавна (мировые координаты) из маркеров Spawns/Spawn0..3: P1/P2 — пол центра, P3 — настил над полом
## левее центра, P4 — нижний ярус вертикали (все дальше 3 м от пропасти).
func spawn_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var holder := get_node_or_null("Spawns")
	if holder:
		for m in holder.get_children():
			if m is Node3D:
				out.append((m as Node3D).global_position)
	return out


func bounds() -> AABB:
	return arena_bounds


## Разрушаемые пропсы (Props/*, Breakable) — живые, не обломки.
func breakables() -> Array:
	var out: Array = []
	var holder := get_node_or_null("Props")
	if holder:
		for c in holder.get_children():
			if c is Breakable:
				out.append(c)
	return out


## Все свободные тела плоскости боя: пропсы листа 02 (Props/*, вместе с Breakable и их обломками) и куски хлама (Junk/*).
func loose_bodies() -> Array:
	var out: Array = []
	for g in ["Props", "Junk"]:
		var holder := get_node_or_null(g)
		if holder:
			for c in holder.get_children():
				if c is RigidBody3D:
					out.append(c)
	return out


## Кучи листа 01 (Start/*, Back/* и т. п. — StaticBody3D или Node3D с Heap): для кода, которому нужен рельеф.
func heaps() -> Array:
	return find_children("Heap*", "Node3D", true, false)


## true, если точка плоскости боя над пропастью (по x) и ниже пола.
func is_in_pit(p: Vector3) -> bool:
	return p.x > pit_rect.position.x and p.x < pit_rect.end.x and p.y < 0.0


## Тёплый свет из пропасти (OmniLight3D Pit/Glow).
func pit_light() -> Light3D:
	return get_node_or_null("Pit/Glow") as Light3D


## Фон-параллакс (инстанс scenes/arena/parallax_scrap.tscn).
func parallax() -> Node3D:
	return get_node_or_null("Parallax") as Node3D
