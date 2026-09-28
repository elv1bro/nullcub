## Верёвочный мост — только поведение. Дерево (Post_A/Post_B StaticBody3D, Planks/Plank_i RigidBody3D 4 кг на цепочке
## Joints/Joint_k Generic6DOFJoint3D с угловым лимитом Z ±25°, Ropes/Rope_<L|R>_k — отрезки каната, Handrails —
## статичные поручни) собирает tools/build_props_scenes.gd в rope_bridge_4m.tscn / rope_bridge_6m.tscn.
## Столбы стоят по обе стороны настила (Post_A/Post_B — StaticBody3D с двумя столбами на z=±0.6); здесь каждый кадр
## отрезки Rope_<L|R>_k натягиваются между точками крепления: внутренняя сторона намотки столба A (0, anchor_y_a,
## ±anchor_z), отверстия соседних досок (x=±plank_half_w, y=0 в теле доски, z=±hole_z), столб B.
## break_apart() — Sudden Death (план 06, шаг Tuning.SUDDEN_DEATH_BREAK_PLATFORMS_STEP; зовёт площадка): суставы цепи
## освобождаются, доски падают порознь, канаты прячутся. Сигнал broken.
class_name RopeBridge
extends Node3D

@export var plank_half_w := 0.125
@export var hole_z := 0.38
@export var anchor_z := 0.43        # внутренняя сторона намотки столба (столб на z=±0.6, намотка r≈0.17)
@export var segment_len := 0.3      # длина модели Rope_Segment.glb вдоль +X
@export var anchor_y_a := 0.05      # высота цепи над основанием столба A
@export var anchor_y_b := 0.05      # … столба B

signal broken

var is_broken := false
var _planks: Array = []
var _post_a: Node3D
var _post_b: Node3D
var _ropes: Dictionary = {}


func _ready() -> void:
	var planks := get_node_or_null("Planks")
	if planks:
		for c in planks.get_children():
			if c is RigidBody3D:
				_planks.append(c)
	_post_a = get_node_or_null("Post_A")
	_post_b = get_node_or_null("Post_B")
	var ropes := get_node_or_null("Ropes")
	for side in ["L", "R"]:
		var list: Array = []
		var k := 0
		while ropes != null and ropes.has_node("Rope_%s_%d" % [side, k]):
			list.append(ropes.get_node("Rope_%s_%d" % [side, k]))
			k += 1
		_ropes[side] = list
	_update_ropes()


func planks() -> Array:
	return _planks


## Обрыв моста: все Joints/* освобождаются и удаляются, доски получают лёгкий разлёт, канаты скрываются.
func break_apart() -> void:
	if is_broken:
		return
	is_broken = true
	var joints := get_node_or_null("Joints")
	if joints != null:
		for j in joints.get_children():
			if j is Joint3D:
				(j as Joint3D).node_a = NodePath()
				(j as Joint3D).node_b = NodePath()
				j.queue_free()
	for p in _planks:
		var rb := p as RigidBody3D
		rb.sleeping = false
		rb.apply_central_impulse(Vector3(randf_range(-0.6, 0.6), -0.4, 0.0) * rb.mass)
		rb.apply_torque_impulse(Vector3(0.0, 0.0, randf_range(-0.8, 0.8)) * rb.mass)
	var ropes := get_node_or_null("Ropes")
	if ropes != null:
		(ropes as Node3D).visible = false
	set_process(false)
	broken.emit()


func _process(_delta: float) -> void:
	_update_ropes()


func _update_ropes() -> void:
	if _post_a == null or _post_b == null:
		return
	var n := _planks.size()
	for side in ["L", "R"]:
		var sgn := -1.0 if side == "L" else 1.0
		var zs := hole_z * sgn
		var za := anchor_z * sgn
		var segs: Array = _ropes[side]
		for k in range(segs.size()):
			var a: Vector3
			var b: Vector3
			if k == 0:
				a = _post_a.global_transform * Vector3(0.0, anchor_y_a, za)
			elif k - 1 < n:
				a = (_planks[k - 1] as Node3D).global_transform * Vector3(plank_half_w, 0.0, zs)
			else:
				continue
			if k < n:
				b = (_planks[k] as Node3D).global_transform * Vector3(-plank_half_w, 0.0, zs)
			else:
				b = _post_b.global_transform * Vector3(0.0, anchor_y_b, za)
			_stretch(segs[k], a, b)


func _stretch(seg: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var len := d.length()
	if len < 1e-4:
		return
	var x := d / len
	var up := Vector3.UP if absf(x.dot(Vector3.UP)) < 0.99 else Vector3.BACK
	var z := x.cross(up).normalized()
	var y := z.cross(x)
	seg.global_transform = Transform3D(Basis(x * (len / segment_len), y, z), a)
