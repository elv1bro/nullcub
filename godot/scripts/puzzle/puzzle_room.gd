## Комната головоломок (docs/plan-demo/PUZZLE.md «Комнаты»): закрытый короб ROOM_W × ROOM_H (стены, пол, потолок — StaticBody3D
## "Static", собирает tools/build_puzzle_demo.gd), выходная дверь в правой стене и за ней тамбур с зоной выхода exit_rect. Дети:
##   Static  — геометрия (стены, полки, уступы), Mech — механизмы (PuzzlePart, кабели, раздатчик), Props — подвижное (ящики, бочки,
##   стена с трещиной), Spawns — Marker3D Spawn0 / Spawn1 (P1, P2).
## Origin комнаты — середина пола (верх пола y = 0), внутренность x −8…8, y 0…9 (локально).
## reset(): всё из Props пересоздаётся из записей, сделанных в _ready (сцена, трансформ, kind/size), механизмы — reset_state().
## Тексты для HUD — ключи перевода (title, hint, solo).
class_name PuzzleRoom
extends Node3D

@export var index := 0
@export var title := ""
@export var hint := ""
@export var solo := ""
## Внутренность комнаты (локально) — границы камеры и проба «не выйти в обход».
@export var inner := Rect2(-8.0, 0.0, 16.0, 9.0)
## Тамбур за выходной дверью (локально): ЦМ куклы здесь — комната пройдена.
@export var exit_rect := Rect2(9.2, 0.0, 2.4, 2.8)
@export var exit_door: NodePath

var _records: Array = []


func _ready() -> void:
	var props := get_node_or_null("Props")
	if props == null:
		return
	for c in props.get_children():
		if c is Node3D and (c as Node).scene_file_path != "":
			var rec := {"scene": (c as Node).scene_file_path, "name": String(c.name), "xf": (c as Node3D).transform, "set": {}}
			for k in ["kind", "size", "hp", "start_on"]:
				if c.get(k) != null:
					rec["set"][k] = c.get(k)
			_records.append(rec)


## Границы для камеры (мир): внутренность и стены вокруг.
func bounds() -> AABB:
	var o := global_position
	return AABB(Vector3(o.x + inner.position.x - 0.6, o.y + inner.position.y - 0.6, -1.0),
		Vector3(inner.size.x + 1.2, inner.size.y + 1.2, 2.0))


## Внутренность (мир, плоскость XY).
func inner_global() -> Rect2:
	return Rect2(inner.position + Vector2(global_position.x, global_position.y), inner.size)


func exit_global() -> Rect2:
	return Rect2(exit_rect.position + Vector2(global_position.x, global_position.y), exit_rect.size)


## Точки появления (мир) в порядке P1, P2.
func spawn_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var holder := get_node_or_null("Spawns")
	if holder != null:
		for m in holder.get_children():
			if m is Node3D:
				out.append((m as Node3D).global_position)
	if out.is_empty():
		out.append(global_position + Vector3(-6.0, 0.45, 0.0))
	return out


func door() -> PuzzleDoor:
	return get_node_or_null(exit_door) as PuzzleDoor


## Выходная дверь открыта (полностью).
func solved() -> bool:
	var d := door()
	return d != null and d.is_on()


## Механизмы комнаты (PuzzlePart во всём поддереве Mech).
func parts() -> Array:
	var out: Array = []
	var m := get_node_or_null("Mech")
	if m != null:
		for n in m.find_children("*", "PuzzlePart", true, false):
			out.append(n)
	return out


## Узел механизма или пропса по имени (пробы): ищет в Mech и Props.
func find(n: String) -> Node:
	for holder in ["Mech", "Props"]:
		var h := get_node_or_null(holder)
		if h != null:
			var c := h.find_child(n, true, false)
			if c != null:
				return c
	return null


## Сброс комнаты: пропсы — заново по записям, механизмы — в начальное состояние.
func reset() -> void:
	var props := get_node_or_null("Props")
	if props != null:
		for c in props.get_children():
			props.remove_child(c)
			c.queue_free()
		for rec in _records:
			var ps := load(String(rec["scene"])) as PackedScene
			if ps == null:
				continue
			var n := ps.instantiate() as Node3D
			n.name = String(rec["name"])
			for k in (rec["set"] as Dictionary):
				n.set(k, rec["set"][k])
			n.transform = rec["xf"]
			props.add_child(n)
	var m := get_node_or_null("Mech")
	if m != null:
		for n in m.find_children("*", "", true, false):
			if n.has_method("reset_state"):
				n.call("reset_state")
