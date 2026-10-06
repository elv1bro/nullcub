## Раздатчик (docs/plan-demo/PUZZLE.md, комната 6): люк в потолке, из которого падает новая взрывная бочка, если в комнате их не
## осталось, а дело ещё не сделано (трещина цела) — головоломка не становится нерешаемой, если все бочки взорвали мимо.
## Считает целые взрывные бочки среди детей into (Props комнаты — из закрытой комнаты они не уходят), спавнит scene в origin узла
## через Tuning.PUZZLE_BARREL_RESPAWN_S после того, как их стало меньше keep. until — путь к узлу с полем broken (стена): разрушена
## (или уже убрана из дерева) — раздатчик молчит.
class_name PuzzleDispenser
extends Node3D

const BARREL := "res://scenes/props/scrap/prop_metal_barrel.tscn"

@export var scene_path := BARREL
@export var keep := 1
@export var until: NodePath
## Куда класть новые (родитель — обычно Props комнаты); пусто — родитель раздатчика.
@export var into: NodePath

var spawned := 0
var _wait := -1.0


func _ready() -> void:
	PuzzlePart.box_mesh(self, "Hatch", Vector3(1.2, 0.12, 1.6), Vector3(0, 0.1, 0), PuzzlePart.flat_material(Color(0.18, 0.19, 0.2), 0.8, 0.4))
	var hz := PuzzlePart.glow_material(Color(1.0, 0.7, 0.1), 0.4)
	var e := PuzzlePart.box_mesh(self, "HatchEdge", Vector3(1.3, 0.05, 0.05), Vector3(0, 0.03, 0.82), hz)
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func reset_state() -> void:
	_wait = -1.0


func count_in_area() -> int:
	var n := 0
	var parent := get_node_or_null(into) if into != NodePath() else get_parent()
	if parent == null:
		return 0
	for c in parent.get_children():
		if c is ExplosiveBarrel and is_instance_valid(c) and not (c as ExplosiveBarrel)._exploded and not c.is_queued_for_deletion():
			n += 1
	return n


func _physics_process(delta: float) -> void:
	var done := false
	var u := get_node_or_null(until) if until != NodePath() else null
	if u == null and until != NodePath():
		done = true   # стену уже убрали из дерева (разрушена)
	elif u != null and bool(u.get("broken")):
		done = true
	if done or count_in_area() >= keep:
		_wait = -1.0
		return
	if _wait < 0.0:
		_wait = Tuning.PUZZLE_BARREL_RESPAWN_S
		return
	_wait -= delta
	if _wait <= 0.0:
		_wait = -1.0
		_spawn()


func _spawn() -> void:
	if not ResourceLoader.exists(scene_path):
		return
	var parent := get_node_or_null(into) if into != NodePath() else get_parent()
	if parent == null:
		return
	var b := (load(scene_path) as PackedScene).instantiate() as Node3D
	b.name = "Dispensed%d" % spawned
	parent.add_child(b)
	b.global_position = global_position + Vector3(0, -0.8, 0)
	spawned += 1
