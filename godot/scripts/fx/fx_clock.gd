## Реальное (нескалированное) время кадра для эффектов и Match (HIT_FX.md §2.2).
## Движок считает delta кадра с Engine.time_scale, взятым В НАЧАЛЕ кадра, а удар (DollCombat → Match.on_hit) меняет time_scale
## в физике того же кадра. Поэтому delta / Engine.time_scale в _process первого кадра стопа врёт в 1/scale раз (стоп 0.05 →
## +333 мс вместо 16.7): hit-stop истекал в том же кадре, таймлайны эффектов прыгали. frame_scale — масштаб, с которым посчитан
## delta текущего кадра: узел FxClock (ребёнок root, process_priority максимальный — идёт последним) записывает Engine.time_scale
## в конце каждого кадра. real_delta(delta) = delta / frame_scale. ensure(node) — создать узел (Match._ready, HitFxDirector._ready).
class_name FxClock
extends Node

static var frame_scale := 1.0
static var _node: FxClock = null


static func real_delta(delta: float) -> float:
	return delta / maxf(frame_scale, 1e-4)


static func ensure(from: Node) -> void:
	if _node != null and is_instance_valid(_node):
		return
	if from == null or not from.is_inside_tree():
		return
	var n := FxClock.new()
	n.name = "FxClock"
	n.process_priority = 1 << 30
	n.process_mode = Node.PROCESS_MODE_ALWAYS
	_node = n
	frame_scale = Engine.time_scale
	from.get_tree().root.add_child.call_deferred(n)


func _process(_delta: float) -> void:
	frame_scale = Engine.time_scale


func _exit_tree() -> void:
	if _node == self:
		_node = null
