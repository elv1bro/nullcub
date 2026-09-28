## Факел — только поведение: мерцание OmniLight3D "Light" и дыхание пламени (Mesh/…/Flame из Torch.glb).
## Дерево: torch.tscn (tools/build_props_scenes.gd).
class_name Torch
extends Node3D

@export var flicker := 0.35
@export var base_energy := 2.0

var _light: OmniLight3D
var _flame: Node3D
var _t := 0.0


func _ready() -> void:
	_t = randf() * 100.0
	_light = get_node_or_null("Light") as OmniLight3D
	var m := get_node_or_null("Mesh")
	if m:
		_flame = m.find_child("Flame", true, false) as Node3D


func _process(delta: float) -> void:
	_t += delta
	var n := 0.5 * sin(_t * 9.0) + 0.3 * sin(_t * 23.0 + 1.7) + 0.2 * sin(_t * 41.0 + 0.6)
	if _light:
		_light.light_energy = base_energy * (1.0 + flicker * n)
	if _flame:
		_flame.scale = Vector3(1.0 + 0.08 * n, 1.0 + 0.2 * n, 1.0 + 0.08 * n)
