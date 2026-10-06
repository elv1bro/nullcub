## Стена пробы «Подъём» (docs/plan-demo/CLIMB.md, MODES_PACK.md §8) — только поведение; сцену climb_wall.tscn собирает
## tools/build_climb_wall.gd. Вертикальная шахта 30 м между двумя скалами: камень (группа climbable — хватается рукой), гладкие плиты
## (без группы — не хватается, обходить или перелетать), уступы разной ширины, нависающий карниз; внизу площадка старта, наверху
## плато финиша. Для Match и камеры — «арена»: spawn_points(), bounds(). Сила тяжести шахты — Area3D "Gravity" (Tuning.CLIMB_GRAVITY,
## set_gravity — клавиша G пробы). Подписи высоты (Label3D "Marks/…") ставятся здесь через tr(): в сцене текста нет.
class_name ClimbWall
extends Node3D

## Высота плато финиша (верх камня), м; ЦМ куклы выше FINISH_Y + FINISH_COM_M над плато левее FINISH_X — финиш.
const FINISH_Y := 30.0
const FINISH_X := -3.0
const FINISH_COM_M := 0.35
## Границы шахты (камера и страховочные стены сборщика).
const BOUNDS := AABB(Vector3(-8.0, -1.0, -1.0), Vector3(16.0, 35.0, 2.0))
const SPAWNS: Array[Vector3] = [Vector3(-0.8, 0.05, 0.0), Vector3(0.9, 0.05, 0.0)]

var gravity: float = Tuning.CLIMB_GRAVITY


func _ready() -> void:
	set_gravity(gravity)
	var marks := get_node_or_null("Marks")
	if marks != null:
		for l in marks.get_children():
			if l is Label3D and l.has_meta("height"):
				var h := int(l.get_meta("height"))
				(l as Label3D).text = tr("%d м") % h if h < int(FINISH_Y) else tr("%d м — ВЕРХ") % h
	var fin := get_node_or_null("Finish/Label") as Label3D
	if fin != null:
		fin.text = tr("ФИНИШ")


func set_gravity(g: float) -> void:
	gravity = g
	var a := get_node_or_null("Gravity") as Area3D
	if a != null:
		a.gravity_space_override = Area3D.SPACE_OVERRIDE_REPLACE
		a.gravity_direction = Vector3.DOWN
		a.gravity = g


func bounds() -> AABB:
	return BOUNDS


func spawn_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var holder := get_node_or_null("Spawns")
	if holder != null:
		for c in holder.get_children():
			if c is Marker3D:
				out.append((c as Marker3D).global_position)
	return out if not out.is_empty() else SPAWNS.duplicate()


## ЦМ куклы на плато финиша.
static func at_finish(com: Vector3) -> bool:
	return com.y >= FINISH_Y + FINISH_COM_M and com.x <= FINISH_X + 0.3
