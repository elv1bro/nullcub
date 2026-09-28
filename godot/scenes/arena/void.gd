## Арена «Void» — пустое чёрное поле как в Ragdoll Masters (2005) для проверки механики: серый пол во всю ширину,
## тёмные стены (внутренние грани x=±7), невидимый потолок на высоте стен, чёрный задник с едва заметной сеткой, ровный свет.
## Никаких пропсов, тумана, DOF и параллакс-слоёв. Только поведение: сцена void.tscn собрана builder-ом
## tools/build_arena_void.gd из моделей tools/blender/arena_void.py (assets/models/arena/void/*.glb).
## API как у RuinsArena / WorkshopArena: spawn_points(), bounds(), сигнал body_fell. Пропасти нет — сигнал оставлен
## для паритета и никогда не испускается.
class_name VoidArena
extends Node3D

@warning_ignore("unused_signal")
signal body_fell(body: Node3D)

## Границы для камеры и боя (v6): поле 14 м (внутренние грани стен x=±7) + стены толщиной 1 м → x = −8..8, снизу — низ
## плиты пола (y=−1: камера с floor_inset = 0 показывает переднюю грань пола полосой внизу кадра), сверху — невидимый
## потолок y=8 (верх стен). 16 × 9 м = аспект 16:9: камера с fit_bounds во весь зум видит ровно эту коробку.
@export var arena_bounds := AABB(Vector3(-8.0, -1.0, -1.0), Vector3(16.0, 9.0, 2.0))


## Точки спавна (мировые координаты) из маркеров Spawns/Spawn0..3: P1/P2 на x=∓3, P3/P4 на x=∓5.5.
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


## Разрушаемых пропсов нет (паритет с другими аренами для кода, который их перебирает).
func breakables() -> Array:
	return []
