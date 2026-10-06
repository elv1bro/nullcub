## Механизм головоломок (docs/plan-demo/PUZZLE.md, MODES_PACK.md §6 «О6»): общий вид «ток есть / нет». Источники (плита, рычаг,
## логика) отвечают is_on(); приёмники (дверь, лифт, зона гравитации, кабель, логика) читают свой вход по NodePath каждый тик —
## опрос, а не сигналы: порядок узлов в дереве не важен, сброс комнаты (PuzzleRoom.reset) ничего не переподключает. Смена
## состояния — сигнал power_changed (звук, HUD, пробы).
## Узлы-механизмы рисуют себя сами (меши, лампы, подписи строятся в _ready): сцены scenes/puzzle/*.tscn — корень + скрипт, расстановку
## и связи пишет сборщик tools/build_puzzle_demo.gd.
class_name PuzzlePart
extends Node3D

signal power_changed(on: bool)

## Цвета ламп и кабелей: ток есть / нет.
const COLOUR_ON := Color(0.35, 1.0, 0.55)
const COLOUR_OFF := Color(0.95, 0.22, 0.16)
const COLOUR_IDLE := Color(0.16, 0.18, 0.2)

var _on := false


## Ток на выходе.
func is_on() -> bool:
	return _on


func _set_on(v: bool) -> void:
	if v == _on:
		return
	_on = v
	power_changed.emit(v)


## Сбросить внутреннее состояние (сброс комнаты): по умолчанию — тока нет.
func reset_state() -> void:
	_set_on(false)


## Ток источника по пути (пусто / нет узла / не механизм — нет тока).
func power_of(path: NodePath) -> bool:
	if path == NodePath():
		return false
	var n := get_node_or_null(path)
	if n == null or not n.has_method("is_on"):
		return false
	return bool(n.call("is_on"))


## Кукла, которой принадлежит тело (деталь — ребёнок Doll; у сборок — глубже), или null.
static func doll_of(body: Node) -> Doll:
	var n := body
	for _i in 4:
		if n == null:
			return null
		if n is Doll:
			return n
		n = n.get_parent()
	return null


## Материал без освещения (лампы, кабели, полоски): цвет и свечение.
static func glow_material(c: Color, energy: float = 1.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.4
	return m


## Обычный материал (цвет, металл, шероховатость).
static func flat_material(c: Color, metallic: float = 0.3, rough: float = 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = rough
	return m


## Меш-коробка (центр — pos) ребёнком parent.
static func box_mesh(parent: Node, n: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	return mi


## Форма-коробка (центр — pos) ребёнком parent.
static func box_shape(parent: Node, n: String, size: Vector3, pos: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.name = n
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	parent.add_child(cs)
	return cs


## Подпись на лицевой стороне (к камере, +Z).
static func label(parent: Node, n: String, text: String, pos: Vector3, px: int = 48, c: Color = Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.name = n
	l.text = text
	l.font_size = px
	l.pixel_size = 0.005
	l.outline_size = 12
	l.outline_modulate = Color(0.02, 0.02, 0.03, 0.9)
	l.modulate = c
	l.shaded = false
	l.double_sided = false
	l.position = pos
	parent.add_child(l)
	return l


## Звук слоя SfxDirector (если есть в сцене).
func sfx(layer: String, db: float = 0.0, pitch: float = 1.0) -> void:
	if not is_inside_tree():
		return
	var s := get_tree().get_first_node_in_group(SfxDirector.GROUP) as SfxDirector
	if s != null:
		s.play_layer(layer, db, pitch, SfxDirector.BUS_SFX, s.pan_for(global_position))
