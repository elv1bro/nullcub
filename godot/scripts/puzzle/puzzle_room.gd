## Комната головоломок (docs/plan-demo/PUZZLE.md «Комнаты»): закрытый короб ROOM_W × ROOM_H (стены, пол, потолок — StaticBody3D
## "Static", собирает tools/build_puzzle_demo.gd), выходная дверь в правой стене и за ней тамбур с зоной выхода exit_rect. Дети:
##   Static  — геометрия (стены, полки, уступы), Mech — механизмы (PuzzlePart, кабели, раздатчик), Props — подвижное (ящики, бочки,
##   стена с трещиной), Spawns — Marker3D Spawn0 / Spawn1 (P1, P2).
## Origin комнаты — середина пола (верх пола y = 0), внутренность x −8…8, y 0…9 (локально).
## reset(): всё из Props пересоздаётся из записей, сделанных в _ready (сцена, трансформ, kind/size), механизмы — reset_state().
## Тексты для HUD — ключи перевода в TEXTS по index (в коде, а не в сцене: инструмент языков берёт из .tscn только text / title).
class_name PuzzleRoom
extends Node3D

## [название, как решить, как решить одному («» — так же, как вдвоём)] по номеру комнаты.
const TEXTS := [
	["Ящик на плиту",
		"Дверь открыта, пока на плите груз. Слетай за ящиком на полку, возьми его (E, у P2 — «/»), положи на плиту — и к выходу.", ""],
	["Две плиты сразу",
		"Обе плиты по 30 кг сразу — и таймер держит дверь 4 с. Вдвоём: встаньте каждый на свою плиту и летите к выходу.",
		"Один: ящик 35 кг не поднять — дотащи его волоком на одну плиту, сам встань на другую."],
	["Тяжёлый ящик вдвоём",
		"Весы на уступе ждут 55 кг груза — куклы не в счёт. Ящик 60 кг одной рукой не поднять: возьмитесь вдвоём и несите наверх.",
		"Один: отнеси на весы четыре ящика по 15 кг, по одному."],
	["Рычаг гравитации",
		"Рычаг поворачивает «низ» комнаты. Чугунный ящик 90 кг не поднять — пусть упадёт на плиту на стене сам. Рычаг: схвати рукоять и перекинь или толкни телом.", ""],
	["Лифт",
		"Лифт едет вверх, пока горит таймер от плиты. Закатите чугунный ящик на лифт; один держит плиту, другой наверху сталкивает ящик на весы.",
		"Один: положи на плиту ящик 35 кг с полки — лифт будет ждать. Или встань на плиту и успей наверх за 8 с."],
	["Финал: трещина",
		"Брось взрывную бочку в трещину (P1: ЛКМ + E, P2: стрелка + «/»). За стеной плита: дверь наверху откроется на 6 с — успейте.", ""],
	["Разгон с высоты",
		"Порталы: что ушло в щель A, вылетает из щели B с той же скоростью. Чугунный ящик не поднять — столкни его с полки в A: разгон с высоты донесёт его до весов.", ""],
	["Стрелочник",
		"Плита включает порталы (таймер 5 с), рычаг выбирает выход A: B1 или B2 в камеру с трещиной. Один стоит на плите, другой ставит рычаг на B2 и бросает бочку в A. Потом — сами через A к двери.",
		"Один: встань на плиту — 5 с, чтобы бросить бочку в A; потом снова на плиту и сам в A."],
]

@export var index := 0
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


## Границы для камеры (мир): внутренность, стены вокруг и полоса под полом (там — нижние строки HUD, а не пол с плитами).
const CAM_BELOW_M := 1.4


func bounds() -> AABB:
	var o := global_position
	return AABB(Vector3(o.x + inner.position.x - 0.6, o.y + inner.position.y - CAM_BELOW_M, -1.0),
		Vector3(inner.size.x + 1.2, inner.size.y + 0.6 + CAM_BELOW_M, 2.0))


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


## Тексты комнаты (ключи перевода; tr — у HUD).
func title_key() -> String:
	return String(TEXTS[index][0]) if index >= 0 and index < TEXTS.size() else ""


func hint_key() -> String:
	return String(TEXTS[index][1]) if index >= 0 and index < TEXTS.size() else ""


func solo_key() -> String:
	return String(TEXTS[index][2]) if index >= 0 and index < TEXTS.size() else ""


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
