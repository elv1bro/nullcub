## Рвущийся мост ямы «Гонки: трасса» (docs/plan-demo/RACE_TRACK.md, участок 6): держит верёвочный мост (RopeBridge, rope_bridge_4m.tscn)
## между столбами. Мост рвётся (RopeBridge.break_apart: доски падают в яму), если у досок кто-то провёл Tuning.TRACK_BRIDGE_BREAK_S
## (деталь куклы в полосе над настилом TOUCH_H), или рядом взорвалась бочка (break_now зовёт TrackBarrelSlot); через
## TRACK_BRIDGE_RESPAWN_S на месте — новый мост (обломки старого убираются). Узел стоит у столба A (origin моста).
class_name TrackBridgeSlot
extends Node3D

const SCENE := "res://scenes/props/rope_bridge_4m.tscn"
const LENGTH := 4.0
const TOUCH_H := 0.9
const TOUCH_BELOW := 0.4

var bridge: RopeBridge
## Для проб: сколько раз рвался, сколько стоит целым сейчас.
var breaks := 0
var touch_t := 0.0
var _broken_left := -1.0
var _old: Array = []


func _ready() -> void:
	_spawn()


func _spawn() -> void:
	var ps := load(SCENE) as PackedScene
	if ps == null:
		return
	bridge = ps.instantiate() as RopeBridge
	bridge.name = "Bridge"
	add_child(bridge)
	touch_t = 0.0
	_broken_left = -1.0


func intact() -> bool:
	return bridge != null and is_instance_valid(bridge) and not bridge.is_broken


## Порвать сейчас (взрыв рядом).
func break_now() -> void:
	if not intact():
		return
	bridge.break_apart()
	breaks += 1
	_broken_left = Tuning.TRACK_BRIDGE_RESPAWN_S
	_old.append(bridge)


## Полоса над настилом (мир, XY).
func touch_rect() -> Rect2:
	var o := global_position
	return Rect2(o.x, o.y - TOUCH_BELOW, LENGTH, TOUCH_H + TOUCH_BELOW)


func _physics_process(delta: float) -> void:
	if not intact():
		if _broken_left >= 0.0:
			_broken_left -= delta
			if _broken_left <= 0.0:
				for b in _old:
					if is_instance_valid(b):
						(b as Node).queue_free()
				_old.clear()
				_spawn()
		return
	var r := touch_rect()
	var touched := false
	for d in get_tree().get_nodes_in_group("dolls"):
		var doll := d as Doll
		if doll == null or not doll.alive or not doll.is_inside_tree():
			continue
		var c := doll.centre_of_mass()
		if c.x < r.position.x - 2.0 or c.x > r.end.x + 2.0 or c.y > r.end.y + 2.0:
			continue
		for p in doll.parts.values():
			var b := p as Node3D
			if b != null and is_instance_valid(b) and r.has_point(Vector2(b.global_position.x, b.global_position.y)):
				touched = true
				break
		if touched:
			break
	if touched:
		touch_t += delta
		if touch_t >= Tuning.TRACK_BRIDGE_BREAK_S:
			break_now()
	else:
		touch_t = maxf(touch_t - delta * 0.5, 0.0)
