## Дрон-камера трансляции (лор §7: «Cameras/drones follow»): летает дугой снаружи купола туда-обратно, смотрит в центр поля,
## чуть покачивается. Только поведение: узел и модель (Camera_Drone.glb) ставит tools/build_null_hall.gd.
extends Node3D

@export var centre := Vector3(0.0, 8.0, 0.0)     # куда смотрит
@export var radii := Vector2(19.5, 22.0)         # полуоси дуги полёта (за куполом 16 × 19)
@export var sweep_deg := 62.0                    # размах от вертикали туда-обратно
@export var speed := 0.16                        # рад/с фазы качания
@export var phase := 0.0
@export var z_base := 1.5
@export var z_amp := 1.8

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	var a := deg_to_rad(90.0 + sweep_deg * sin(_t * speed + phase))
	var p := Vector3(cos(a) * radii.x, sin(a) * radii.y, z_base + z_amp * sin(_t * speed * 1.7 + phase * 2.0))
	p.y += sin(_t * 2.3 + phase) * 0.15
	global_position = p
	if global_position.distance_to(centre) > 0.5:
		look_at(centre, Vector3.UP, true)
		rotate_object_local(Vector3.FORWARD, sin(_t * 1.3 + phase) * 0.08)
