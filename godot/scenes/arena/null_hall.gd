## Арена 01 «Old NULL Hall» (лист автора, docs/plan-demo/ART_NULL.md, лист 5): круглый индустриальный зал, ярусы трибун
## со зрителями, мостки, колонны со световыми полосами, большой экран и табло поля, якоря мембраны по контуру поля.
## Только поведение: сцену null_hall.tscn собирает tools/build_null_hall.gd из кита tools/blender/arena_null_hall.py.
## API как у VoidArena: spawn_points(), bounds(), сигнал body_fell, breakables().
## Поле: гравитация (сила в G и направление) показывается на табло; сама механика поля и упругая мембрана — задача
## «Купольная арена» (docs/ai-memory/CONTINUE.md, задача 3), здесь пока только вид и контур якорей.
class_name NullHallArena
extends Node3D

@warning_ignore("unused_signal")
signal body_fell(body: Node3D)

## Границы для камеры и боя: контур мембраны (эллипс по якорям) с запасом.
@export var arena_bounds := AABB(Vector3(-16.0, -0.6, -1.0), Vector3(32.0, 22.6, 2.0))
## Поле NULL для табло: сила в G и направление (в плоскости экрана; вниз — (0, −1)).
@export var gravity_g := 0.35:
	set(v):
		gravity_g = v
		_update_boards()
@export var gravity_dir := Vector2(0.7, -0.7):
	set(v):
		gravity_dir = v
		_update_boards()
@export var membrane_pct := 98:
	set(v):
		membrane_pct = v
		_update_boards()


func _ready() -> void:
	_update_boards()


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


func breakables() -> Array:
	return []


## Точки якорей мембраны (мировые), по кругу — контур поля для будущей мембраны.
func membrane_anchors() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var holder := get_node_or_null("Membrane")
	if holder:
		for m in holder.get_children():
			if m is Node3D:
				out.append((m as Node3D).global_position)
	return out


## Стрелка направления гравитации: восемь направлений экрана.
static func arrow_for(dir: Vector2) -> String:
	if dir.length() < 0.01:
		return "·"
	var arrows := ["→", "↗", "↑", "↖", "←", "↙", "↓", "↘"]
	var a := fposmod(atan2(dir.y, dir.x), TAU)
	return arrows[int(round(a / (TAU / 8.0))) % 8]


func gravity_text() -> String:
	return "%s %.2fG" % [arrow_for(gravity_dir), gravity_g]


func _update_boards() -> void:
	if not is_inside_tree():
		return
	for lbl in get_tree().get_nodes_in_group("null_hall_gravity"):
		if is_ancestor_of(lbl):
			(lbl as Label3D).text = gravity_text()
	for lbl in get_tree().get_nodes_in_group("null_hall_membrane"):
		if is_ancestor_of(lbl):
			(lbl as Label3D).text = "MEMBRANE %d%%" % membrane_pct
