## Каток спорт-зала для хоккея (docs/plan-demo/HOCKEY.md): снаряды вида "hockey" собираются кодом при первом выборе вида —
## зал (scenes/arena/sport_hall.tscn, tools/build_sport_hall.gd) не перестраивается. SportHallArena.apply_sport зовёт:
##   ensure(hall) — Fixtures/hockey: низкие ворота у боковых стен (модель Sport_Goal, сжатая по высоте до HOCKEY_GOAL_H; линия
##     ворот x = ±goal_x — шов пола; крыша ворот — коллайдер от перекладины к стене до HOCKEY_GOAL_BACK_H, шайба сверху скатывается;
##     перекладина — шар). Дальше этот набор включает и выключает сам apply_sport, как три других;
##   apply_ice(hall, on) — лёд: пол зала (Floor/FloorBody) получает материал с трением HOCKEY_ICE_FRICTION, при другом виде —
##     материал снимается (пол как был: без материала).
class_name HockeyRink
extends RefCounted

const KIT := "res://assets/models/arena/null_hall/%s.glb"
const ROOF_T := 0.12
const ICE_META := &"hockey_ice"


static func ensure(hall: Node3D) -> void:
	var fx := hall.get_node_or_null("Fixtures")
	if fx == null or fx.has_node("hockey"):
		return
	var g := Node3D.new()
	g.name = "hockey"
	fx.add_child(g)
	var r: Dictionary = Tuning.SPORTS["hockey"]
	var gx := float(r["goal_x"])
	var gh := float(r["goal_h"])
	var depth := Tuning.SPORT_FIELD_HALF_W - gx
	for sx: float in [-1.0, 1.0]:
		var tag := "L" if sx < 0.0 else "R"
		# модель футбольных ворот (перекладина 3.2 м, спинка 3.7 м) — сжата по высоте; проём смотрит в +X, правые — на 180°
		var goal := _model("Sport_Goal", g, "Goal_" + tag, Vector3(sx * gx, 0.0, 0.0), 0.0 if sx < 0.0 else 180.0,
			Vector3(depth / 1.8, gh / 3.2, 0.8))
		if goal == null:
			push_warning("HockeyRink: no Sport_Goal model")
		_model("Floor_Seam", g, "GoalLine_" + tag, Vector3(sx * gx, 0.0, 0.0), 0.0, Vector3(0.6, 1.0, 0.5))
		var rise := Tuning.HOCKEY_GOAL_BACK_H - gh
		var len := sqrt(depth * depth + rise * rise)
		var ang := rad_to_deg(atan2(rise, depth))
		var box := BoxShape3D.new()
		box.size = Vector3(len, ROOF_T, 3.0)
		_body(g, "GoalRoof_" + tag, box, Vector3(sx * (gx + depth * 0.5), gh + rise * 0.5 + ROOF_T * 0.5, 0.0), ang * sx)
		var bar := SphereShape3D.new()
		bar.radius = 0.07
		_body(g, "Crossbar_" + tag, bar, Vector3(sx * gx, gh + 0.05, 0.0))


static func apply_ice(hall: Node3D, on: bool) -> void:
	var floor_body := hall.get_node_or_null("Floor/FloorBody") as StaticBody3D
	if floor_body == null:
		return
	if on and not floor_body.has_meta(ICE_META):
		floor_body.set_meta(ICE_META, floor_body.physics_material_override)
		var pm := PhysicsMaterial.new()
		pm.friction = Tuning.HOCKEY_ICE_FRICTION
		floor_body.physics_material_override = pm
	elif not on and floor_body.has_meta(ICE_META):
		floor_body.physics_material_override = floor_body.get_meta(ICE_META) as PhysicsMaterial
		floor_body.remove_meta(ICE_META)


static func is_ice(hall: Node3D) -> bool:
	var floor_body := hall.get_node_or_null("Floor/FloorBody")
	return floor_body != null and floor_body.has_meta(ICE_META)


static func _model(module: String, parent: Node3D, node_name: String, pos: Vector3, yaw: float, scl: Vector3) -> Node3D:
	var ps := load(KIT % module) as PackedScene
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	n.name = node_name
	parent.add_child(n)
	n.position = pos
	n.rotation_degrees = Vector3(0.0, yaw, 0.0)
	n.scale = scl
	return n


static func _body(parent: Node3D, n: String, shape: Shape3D, pos: Vector3, roll_deg := 0.0) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = n
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = shape
	b.add_child(cs)
	parent.add_child(b)
	b.position = pos
	b.rotation_degrees = Vector3(0.0, 0.0, roll_deg)
	return b
