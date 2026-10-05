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
