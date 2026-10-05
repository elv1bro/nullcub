## Карта «Полигон» пробного режима «Стычка 3 на 3» (docs/plan-demo/SQUAD.md) — только поведение; сцену proving_ground.tscn собирает
## tools/build_proving_ground.gd из компонентов Руин. От RuinsArena — точки спавна (Spawns/Spawn0..5 в порядке player_index), границы,
## сигнал body_fell (страховочный низ), пропсы. Своё — точки базы команды для возрождения.
class_name ProvingGround
extends RuinsArena


func _init() -> void:
	arena_bounds = AABB(Vector3(-32.0, -2.0, -1.0), Vector3(64.0, 18.0, 2.0))


## Точки базы команды (0 — синие слева, 1 — красные справа): spawn_points() с индексом той же чётности.
func base_points(team: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var pts := spawn_points()
	for i in range(pts.size()):
		if i % 2 == team:
			out.append(pts[i])
	return out


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
