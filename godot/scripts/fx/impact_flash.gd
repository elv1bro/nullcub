## Вспышка-блик удара (INSPIRATION_GAMES.md, Ragdoll Masters): мягкий диск + два скрещённых луча из квадов лицом к камере.
## Создаётся ImpactFx._spawn_flash: материал общий на тип удара (ImpactFx.flash_material), размер по силе удара.
## Живёт по времени сцены, но шаг ограничен MAX_STEP_S: длинный кадр (компиляция шейдера на первом ударе, save_png в тестах)
## не съедает всю вспышку за раз. Хлопок POP_S (0.35 → 1.0), затухание LIFE_S через GeometryInstance3D.transparency
## (материал не трогаем — он общий), затем queue_free. Hit-stop (Engine.time_scale) вспышку держит, как и щепки.
class_name ImpactFlash
extends Node3D

const POP_S := 0.05
const LIFE_S := 0.18
const MAX_STEP_S := 1.0 / 30.0
const START_SCALE := 0.35

var _t := 0.0
var _quads: Array[MeshInstance3D] = []


func setup(mat: Material, size: float) -> void:
	var specs: Array = [
		[Vector2(size, size), 0.0],
		[Vector2(size * 2.2, size * 0.16), deg_to_rad(randf_range(-14.0, 14.0))],
		[Vector2(size * 0.16, size * 2.2), deg_to_rad(randf_range(-14.0, 14.0))],
	]
	for spec in specs:
		var q := QuadMesh.new()
		q.size = spec[0]
		q.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.rotation.z = spec[1]
		add_child(mi)
		_quads.append(mi)
	scale = Vector3.ONE * START_SCALE


func _process(delta: float) -> void:
	_t += minf(delta, MAX_STEP_S)
	var pop := clampf(_t / POP_S, 0.0, 1.0)
	var s := lerpf(START_SCALE, 1.0, 1.0 - pow(1.0 - pop, 3.0))
	scale = Vector3.ONE * s
	var fade := clampf((_t - POP_S) / LIFE_S, 0.0, 1.0)
	for mi in _quads:
		mi.transparency = fade * fade
	if _t >= POP_S + LIFE_S:
		queue_free()
