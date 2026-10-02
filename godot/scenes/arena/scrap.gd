## Арена «Свалка» v3 (биом 1 THE SCRAP, первый уровень: Core игрока просыпается в куче хлама на дне Башни; референс —
## docs/refs/biomes/01-scrap/scenes.png, docs/plan-demo/BIOMES.md §1, LORE.md) — только поведение.
## Сцена scrap.tscn собрана builder-ом tools/build_arena_scrap.gd ИЗ КОМПОНЕНТНЫХ СЦЕН scenes/props/scrap/*.tscn: пол из
## модулей кита (kit_platform_lower), платформы по краям на опорах за плоскостью боя, балки на цепях (над пропастью и островок
## в центре), скат, кучи хлама и кукол листа 01 (bodies_*), свободные куски (bit_*), физпропсы листа 02 (prop_*), механизмы листа 04
## (machine_*: магнит на цепи, паровой клапан, пресс, мусорный желоб — у каждого свой скрипт и цикл OFF → WARNING → ACTIVE →
## COOLDOWN), параллакс-фон, свет, пыль и искры.
## API как у RuinsArena / WorkshopArena / VoidArena: spawn_points(), bounds(), breakables(), parallax(), сигнал body_fell —
## пропасть («провал в недра», Area3D "DeathZone"): площадка (scenes/playground.gd) делает Doll.knock_out() → KO kind "self".
## Под пропастью — твёрдое дно Bounds/PitBottom: оружие, пропсы и части KO-нутой куклы там лежат, а не падают бесконечно.
## Своё: machines() / magnet() / steam_vent() / press() / chute() — механизмы; лут — разбитый ящик или бочка (Breakable.destroyed)
## роняет LOOT_MIN…LOOT_MAX материалов крафта (LOOT_TABLE → LootItem, scenes/props/scrap/loot_item.gd) в узел "Loot"; подбор
## касанием или захватом E кладёт их в RunInventory.shared() (scripts/body/run_inventory.gd), счётчик — узел LootCounter.
class_name ScrapArena
extends Node3D

signal body_fell(body: Node3D)
## Выпал лут (для проб и HUD).
signal loot_dropped(item: Node3D, from: Node3D)

## Какой материал из чего выпадает: kind Breakable → [[id, вес], …].
const LOOT_TABLE := {
	"crate": [["nails", 3.0], ["handle", 2.0], ["plate", 1.0]],
	"barrel": [["plate", 2.0], ["chain", 2.0], ["nails", 1.0]],
}
const LOOT_MIN := 1
const LOOT_MAX := 2

## Границы для камеры и боя: невидимые стены x=±18, потолок y=14 (= верх границ); снизу −6 — у DynamicCamera floor_inset 4.5
## (по умолчанию), значит клэмп центра идёт от y=−1.5 (полоса переднего хлама под полом), а максимум зума — половина полной
## высоты 20 м: кадр 16:9 на полном отъезде ≈ 35.6 × 20 м — вся арена (камера z ≈ 24, центр y ≈ 6 — диапазон, под который
## резан фон: docs/plan-demo/PARALLAX.md, |x| ≤ 20, y камеры 2.5–10). v3 этот диапазон не меняет.
@export var arena_bounds := AABB(Vector3(-18.0, -6.0, -1.0), Vector3(36.0, 20.0, 2.0))
## Пропасть на плоскости боя (x0, y0, ширина, глубина до зоны KO): край пола — y=0, зона KO начинается на y=−3.
@export var pit_rect := Rect2(-9.5, -3.0, 3.0, 3.0)
## «Ключ камеры» (SpotLight3D CameraKey): смещение от активной камеры (выше и левее) — светит в плоскость кукол z=0.
@export var key_offset := Vector3(-2.0, 2.5, 0.0)
## Детерминированный выбор лута (пробы): seed генератора.
@export var loot_seed := 1

var _key: SpotLight3D
var _loot_rng := RandomNumberGenerator.new()
var _loot_scenes: Array = []       # сцены лута загружены заранее (держим ссылки): первая загрузка glb посреди боя — рывок кадра


func _ready() -> void:
	var dz := get_node_or_null("DeathZone")
	if dz is Area3D:
		(dz as Area3D).body_entered.connect(func(b: Node3D) -> void: body_fell.emit(b))
	_key = get_node_or_null("CameraKey") as SpotLight3D
	if _key != null:
		_key.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # ездит за камерой в _process
	_loot_rng.seed = loot_seed
	for id in RunInventory.MATERIALS:
		if ResourceLoader.exists(LootItem.SCENE % id):
			_loot_scenes.append(load(LootItem.SCENE % id))
	for b in breakables():
		watch_breakable(b)
	for b in loose_bodies():
		PropHeft.equip(b)   # вес по классам (scenes/props/prop_heft.gd): тяжёлое не сдвинуть, среднее — с трудом


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


## Четыре точки спавна (мировые координаты) из маркеров Spawns/Spawn0..3: P1/P2 — пол центра, P3 — висящий островок над ними,
## P4 — правый ярус R1 (все дальше 3 м от пропасти).
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


## Все свободные тела плоскости боя: пропсы листа 02 (Props/*, вместе с Breakable и их обломками), куски хлама (Junk/*, и
## высыпанные желобом) и лут (Loot/*).
func loose_bodies() -> Array:
	var out: Array = []
	for g in ["Props", "Junk", "Loot"]:
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


## Фон-параллакс (инстанс сцены фона, см. PARALLAX в builder-е).
func parallax() -> Node3D:
	return get_node_or_null("Parallax") as Node3D


# --- механизмы ---

## Механизмы (Machines/*, ScrapMachine).
func machines() -> Array:
	var out: Array = []
	var holder := get_node_or_null("Machines")
	if holder:
		for c in holder.get_children():
			if c is ScrapMachine:
				out.append(c)
	return out


func magnet() -> MagnetMachine:
	return get_node_or_null("Machines/Magnet") as MagnetMachine


func steam_vent() -> SteamVentMachine:
	return get_node_or_null("Machines/SteamVent") as SteamVentMachine


func press() -> PressMachine:
	return get_node_or_null("Machines/Press") as PressMachine


func chute() -> ChuteMachine:
	return get_node_or_null("Machines/Chute") as ChuteMachine


# --- лут ---

## Следить за разрушаемым пропсом: когда разобьют — лут. Пропсы, добавленные после _ready (площадки, пробы), — вызвать самим.
func watch_breakable(b: Breakable) -> void:
	if not b.destroyed.is_connected(_on_breakable_destroyed):
		b.destroyed.connect(_on_breakable_destroyed.bind(b))


func _on_breakable_destroyed(b: Breakable) -> void:
	if not is_instance_valid(b):
		return
	var table: Array = LOOT_TABLE.get(b.kind, LOOT_TABLE["crate"])
	var weights := PackedFloat32Array()
	for e in table:
		weights.append(float(e[1]))
	var n := _loot_rng.randi_range(LOOT_MIN, LOOT_MAX)
	var c := b.global_position + Vector3(0.0, 0.5, 0.0)
	for i in n:
		var id := String(table[_loot_rng.rand_weighted(weights)][0])
		var vel := Vector3(_loot_rng.randf_range(-1.5, 1.5), _loot_rng.randf_range(1.5, 3.0), 0.0) + b.linear_velocity * 0.5
		spawn_loot(id, c + Vector3((i - (n - 1) * 0.5) * 0.35, 0.1 * i, 0.0), vel, b)


## Лут id в точке pos (мировые) со скоростью vel в узел "Loot" (from — откуда выпал, для сигнала).
func spawn_loot(id: String, pos: Vector3, vel := Vector3.ZERO, from: Node3D = null) -> LootItem:
	var holder := get_node_or_null("Loot")
	if holder == null:
		holder = self
	var it := LootItem.spawn(id, holder, pos, vel)
	if it != null:
		loot_dropped.emit(it, from)
	return it
