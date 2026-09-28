## Арена «Руины» (референс docs/refs/R15-a-arena-ruins-concept.jpg) — только поведение.
## Сцена ruins.tscn собрана builder-ом tools/build_arena_ruins.gd ИЗ КОМПОНЕНТНЫХ СЦЕН scenes/props/*.tscn
## (ART_DIRECTION.md §2): плиты, стены, ворота, палубы, верёвочный мост, знамёна, факелы, бочки/ящики (Breakable),
## клетка на цепи, параллакс-фон, свет и окружение. Каждый компонент сам качается/мерцает/ломается своим скриптом.
## Здесь: точки спавна (Spawns/Spawn*), границы для камеры, сигнал зоны смерти и доступ к компонентам.
class_name RuinsArena
extends Node3D

signal body_fell(body: Node3D)

## Границы арены (невидимые стены x=±16, потолок y=12, ямы внизу) — для камеры и боя.
@export var arena_bounds := AABB(Vector3(-16.0, -6.0, -1.0), Vector3(32.0, 18.0, 2.0))


func _ready() -> void:
	var dz := get_node_or_null("DeathZone")
	if dz is Area3D:
		dz.body_entered.connect(func(b: Node3D) -> void: body_fell.emit(b))


## Четыре точки спавна (мировые координаты) из маркеров Spawns/Spawn0..3.
func spawn_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var holder := get_node_or_null("Spawns")
	if holder:
		for m in holder.get_children():
			if m is Node3D:
				out.append(m.global_position)
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


func torches() -> Array:
	return find_children("*", "Torch", true, false)


func banners() -> Array:
	return find_children("*", "Banner", true, false)


func rope_bridges() -> Array:
	return find_children("*", "RopeBridge", true, false)


## Фон-параллакс (инстанс scenes/arena/parallax_background.tscn) или пустой узел-заглушка "Parallax".
func parallax() -> Node3D:
	return get_node_or_null("Parallax") as Node3D
