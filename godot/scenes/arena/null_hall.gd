## Арена 01 «Old NULL Hall» (лист автора, docs/plan-demo/ART_NULL.md, лист 5): круглый индустриальный зал, ярусы трибун
## со зрителями, мостки, колонны со световыми полосами, большой экран и табло поля, купол поля NULL с упругой мембраной.
## Только поведение: сцену null_hall.tscn собирает tools/build_null_hall.gd из кита tools/blender/arena_null_hall.py.
## API как у VoidArena: spawn_points(), bounds(), сигнал body_fell, breakables(). Поле и мембрана — узел Field (NullField):
## гравитация (сила в G и направление) и упругая граница-полуэллипс; табло показывают текущее поле, пока оно меняется —
## «FIELD: SHIFTING». Отладка: клавиша G (debug_keys) — следующее поле из FIELD_PRESETS (позже поле сменит голосование зрителей).
class_name NullHallArena
extends Node3D

@warning_ignore("unused_signal")
signal body_fell(body: Node3D)

## Поля для отладочной клавиши G: [сила в G, направление в плоскости экрана]. Первое — проектная гравитация (0.20 G вниз).
const FIELD_PRESETS := [[0.204, Vector2(0.0, -1.0)], [0.35, Vector2(0.7, -0.7)], [0.24, Vector2(-1.0, 0.0)],
	[0.1, Vector2(0.0, 1.0)], [0.0, Vector2(0.0, -1.0)], [0.5, Vector2(0.0, -1.0)]]

## Границы для камеры и боя: купол (полуширина 16, высота 19) с запасом, снизу — плита пола.
@export var arena_bounds := AABB(Vector3(-18.0, -0.6, -1.0), Vector3(36.0, 21.6, 2.0))
@export var membrane_pct := 98
@export var debug_keys := true

var _preset := 0

@onready var field: NullField = get_node_or_null("Field")


func _ready() -> void:
	_update_boards()


func _process(_delta: float) -> void:
	_update_boards()


func _unhandled_input(event: InputEvent) -> void:
	if debug_keys and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_G:
		_preset = (_preset + 1) % FIELD_PRESETS.size()
		var p: Array = FIELD_PRESETS[_preset]
		set_field(float(p[0]), p[1])


## Сменить поле: сила в G и направление (плавно, Tuning.NULL_FIELD_BLEND_S).
func set_field(g_units: float, dir: Vector2) -> void:
	if field != null:
		field.set_field(g_units, dir)


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


## Точки якорей мембраны и эмиттеров (мировые) — контур купола.
func membrane_anchors() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var holder := get_node_or_null("Anchors")
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
	if field == null:
		return "↓ 0.20G"
	if field.field_g < 0.005:
		return "0G"
	return "%s %.2fG" % [arrow_for(field.field_dir), field.field_g]


func _update_boards() -> void:
	if not is_inside_tree():
		return
	var g := gravity_text()
	var shifting := field != null and field.is_shifting()
	for lbl in get_tree().get_nodes_in_group("null_hall_gravity"):
		if is_ancestor_of(lbl):
			(lbl as Label3D).text = g
	for lbl in get_tree().get_nodes_in_group("null_hall_membrane"):
		if is_ancestor_of(lbl):
			(lbl as Label3D).text = "FIELD: SHIFTING" if shifting else "MEMBRANE %d%%" % membrane_pct
