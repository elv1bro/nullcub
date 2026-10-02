## Параллакс-фон арены из четырёх слоёв листа R18 (docs/refs/R18-a-parallax-layers.jpg, ART_DIRECTION.md §4).
## Текстуры режет tools/parallax_cut.py → assets/textures/parallax/; он же печатает размеры и позиции квадов,
## которые лежат в parallax_background.tscn: Layer4Sky (z −90, непрозрачный, закрывает весь кадр камеры fov 45),
## Layer3Far (z −45), Layer2Mid (z −18, за 3D-постройками арены, линия земли чуть ниже плит), Layer1Fore (z +2.5,
## перед плоскостью боя вдоль нижнего края). Перспективная камера даёт параллакс сама.
##
## Здесь только поведение:
##   • y-смещения слоёв (экспорт) — интегратор совмещает линию земли слоя 2 с плитами арены, не трогая сцену;
##   • необязательный множитель параллакса на слой: 1.0 = чистая перспектива (квад неподвижен в мире),
##     < 1 — слой частично едет за активной камерой и уплывает медленнее, 0 — приклеен к камере.
##     Смещение считается от camera_origin (по умолчанию — позиция камеры в первый кадр).
class_name ParallaxBackground3D
extends Node3D

const LAYER_NAMES := ["Layer4Sky", "Layer3Far", "Layer2Mid", "Layer1Fore"]

@export_group("Смещение слоёв по y, м")
@export var layer4_y_offset := 0.0
@export var layer3_y_offset := 0.0
@export var layer2_y_offset := 0.0
@export var layer1_y_offset := 0.0

@export_group("Множитель параллакса (1 = перспектива)")
@export_range(0.0, 1.5, 0.01) var layer4_scroll := 1.0
@export_range(0.0, 1.5, 0.01) var layer3_scroll := 1.0
@export_range(0.0, 1.5, 0.01) var layer2_scroll := 1.0
@export_range(0.0, 1.5, 0.01) var layer1_scroll := 1.0
## Применять множитель и по вертикали (иначе — только по x).
@export var scroll_vertical := true
## Точка отсчёта камеры для множителей; при нулевом значении берётся позиция камеры в первый кадр.
@export var camera_origin := Vector3.ZERO

var _base: Dictionary = {}   # имя слоя → базовая позиция (из сцены + y-смещение)
var _origin_set := false


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # двигается в _process (не в физическом тике) — своя интерполяция физики дала бы запаздывание / дрожь
	for n in LAYER_NAMES:
		var l := get_node_or_null(n) as MeshInstance3D
		if l == null:
			push_warning("ParallaxBackground3D: нет слоя %s" % n)
			continue
		_base[n] = l.position + Vector3(0.0, _y_offset(n), 0.0)
		l.position = _base[n]
	_origin_set = camera_origin != Vector3.ZERO


## Слой по имени (Layer4Sky … Layer1Fore) или null.
func layer(n: String) -> MeshInstance3D:
	return get_node_or_null(n) as MeshInstance3D


## Мировая позиция слоя без учёта множителя параллакса.
func base_position(n: String) -> Vector3:
	return _base.get(n, Vector3.ZERO)


func _process(_delta: float) -> void:
	if is_equal_approx(layer4_scroll, 1.0) and is_equal_approx(layer3_scroll, 1.0) \
			and is_equal_approx(layer2_scroll, 1.0) and is_equal_approx(layer1_scroll, 1.0):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if not _origin_set:
		camera_origin = cam.global_position
		_origin_set = true
	var d := cam.global_position - camera_origin
	if not scroll_vertical:
		d.y = 0.0
	d.z = 0.0
	for n in LAYER_NAMES:
		var l := get_node_or_null(n) as MeshInstance3D
		if l == null or not _base.has(n):
			continue
		l.position = _base[n] + d * (1.0 - _scroll(n))


func _y_offset(n: String) -> float:
	match n:
		"Layer4Sky": return layer4_y_offset
		"Layer3Far": return layer3_y_offset
		"Layer2Mid": return layer2_y_offset
		_: return layer1_y_offset


func _scroll(n: String) -> float:
	match n:
		"Layer4Sky": return layer4_scroll
		"Layer3Far": return layer3_scroll
		"Layer2Mid": return layer2_scroll
		_: return layer1_scroll
