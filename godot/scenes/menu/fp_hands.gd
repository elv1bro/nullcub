## Руки героя от первого лица в гараже (06.10, автор: «человек будет как будто мы — от первого лица + руки», «а можно руки красивее
## сделать?»; лор — LORE_V2 §2а: герой — механик). Модель — assets/models/hands/FP_Hand.glb (tools/blender/fp_hands.py): рукав рабочей
## куртки со светоотражающей полосой, перчатка без пальцев (ткань, кожаная ладонь, оранжевая накладка и липучка), кожа и ногти на
## пальцах. Каждая фаланга — свой узел с началом в суставе: сгиб (curl) — поворот узла вокруг его X к ладони, так позы и жесты
## ставятся числами, без скелета и анимаций. Левая рука — своя модель-зеркало (FP_Hand_L.glb).
##
## Узел — ребёнок камеры гаража. Позы заданы в кадре камеры при опорном FOV (REF_FOV): весь узел масштабируется на
## tan(fov/2) / tan(REF_FOV/2) — проекция от этого не меняется, поэтому руки занимают одно и то же место кадра на любом FOV пункта.
## Свой слой (LAYER) и своя лампа-подсветка (светит только рукам), тени не бросают.
##
## Рука — предплечье и кисть: предплечье (рукав, манжета) всегда смотрит от запястья к плечу (SHOULDER — ниже и чуть позади глаз),
## поэтому руки в кадре всегда «растут» снизу, где бы ни было запястье; поворот rot — сгиб кисти (x — вверх/вниз, y — вбок) и
## разворот предплечья (z: 0 — ладонью вниз, −90 у правой — ладонью внутрь, большим пальцем вверх).
##
## API: set_pose(рука, поза, сек) — готовые позы из POSES; reach(рука, мировая точка, …) — к предмету; grip(рука, curl);
## walk(фаза, сила) — мах при ходьбе (зовёт GarageView); sway(рысканье/с) — запаздывание на повороте головы.
class_name FpHands
extends Node3D

const REF_FOV := 50.0
const LAYER := 1 << 19
## Позы (кадр камеры при REF_FOV, x вправо, y вверх, −z вперёд): pos — запястье, rot — (сгиб кисти вверх, вбок, разворот
## предплечья), градусы; curl 0..1, thumb 0..1. rest — руки у нижних углов кадра, кулаки полусжаты, большие пальцы вверх
## (видны костяшки), down — ниже кадра (на нырке в экран, в эфире).
const POSES := {
	"rest": {"R": [Vector3(0.125, -0.178, -0.33), Vector3(-10.0, 10.0, -58.0), 0.62, 0.5],
		"L": [Vector3(-0.16, -0.19, -0.34), Vector3(-10.0, -10.0, 58.0), 0.68, 0.5]},
	"down": {"R": [Vector3(0.2, -0.46, -0.24), Vector3(-10.0, 0.0, -60.0), 0.6, 0.5],
		"L": [Vector3(-0.22, -0.46, -0.24), Vector3(-10.0, 0.0, 60.0), 0.6, 0.5]},
	"point": {"R": [Vector3(0.11, -0.13, -0.42), Vector3(0.0, 4.0, -35.0), 0.0, 0.6],
		"L": [Vector3(-0.2, -0.22, -0.33), Vector3(-14.0, -8.0, 64.0), 0.74, 0.55]},
	"open": {"R": [Vector3(0.15, -0.16, -0.4), Vector3(-6.0, 0.0, -40.0), 0.1, 0.1],
		"L": [Vector3(-0.15, -0.16, -0.4), Vector3(-6.0, 0.0, 40.0), 0.1, 0.1]},
}
## Плечи в кадре камеры (опорный FOV): предплечье тянется от запястья к ним.
const SHOULDER := {"R": Vector3(0.2, -0.4, 0.1), "L": Vector3(-0.2, -0.4, 0.1)}
const MODELS := {"R": preload("res://assets/models/hands/FP_Hand_R.glb"), "L": preload("res://assets/models/hands/FP_Hand_L.glb")}
## Сгиб фаланг при curl = 1 (градусы, к ладони): основная, средняя, концевая; большой палец — при thumb = 1.
const CURL_DEG := [72.0, 88.0, 55.0]
const THUMB_DEG := [22.0, 30.0, 42.0]

## Скорость, с которой руки догоняют цель (1/с).
@export var follow_rate := 14.0

var hands := {}          # "R" / "L" → {root, wrist, fingers: [[узлы фаланг]], thumb: [узлы], rest: {узел: Basis}, cur: {}, tgt: {}}
var fill: OmniLight3D
var _walk_phase := 0.0
var _walk_amt := 0.0
var _sway := 0.0


func _ready() -> void:
	for side in ["R", "L"]:
		hands[side] = _build_hand(side)
	fill = OmniLight3D.new()
	fill.name = "HandFill"
	fill.light_cull_mask = LAYER
	fill.light_color = Color(1.0, 0.82, 0.66)
	fill.light_energy = 0.55
	fill.omni_range = 0.9
	fill.shadow_enabled = false
	fill.position = Vector3(0.05, 0.12, -0.12)
	add_child(fill)
	set_pose("rest", 0.0)


## Масштаб узла под FOV камеры (зовёт GarageView каждый кадр).
func fit_fov(fov: float) -> void:
	var k := tan(deg_to_rad(fov) * 0.5) / tan(deg_to_rad(REF_FOV) * 0.5)
	scale = Vector3.ONE * k


## Готовая поза для обеих рук (или одной: side = "R" / "L"); dur = 0 — сразу.
func set_pose(pose: String, dur := 0.25, side := "") -> void:
	var p: Dictionary = POSES.get(pose, POSES["rest"])
	for s in hands:
		if side != "" and s != side:
			continue
		var spec: Array = p[s]
		_target(s, spec[0], spec[1], float(spec[2]), float(spec[3]), dur)


## Рука side тянется к мировой точке world_p (ладонью к ней, пальцы раскрыты на curl); отступ back — сколько не доставать (м).
func reach(side: String, world_p: Vector3, curl := 0.15, dur := 0.3, back := 0.06, rot := Vector3.INF) -> void:
	var cam := get_parent() as Node3D
	if cam == null:
		return
	var local := cam.global_transform.affine_inverse() * world_p
	local /= maxf(scale.x, 0.01)
	var dir := local.normalized()
	local -= dir * back
	var r := rot
	if r == Vector3.INF:   # кисть по линии предплечья, ладонью чуть внутрь
		r = Vector3(0.0, 0.0, -55.0 if side == "R" else 55.0)
	_target(side, local, r, curl, 0.2, dur)


## Положение в кадре камеры (опорный FOV) и поворот руки напрямую.
func place(side: String, pos: Vector3, rot_deg: Vector3, curl: float, thumb := 0.3, dur := 0.25) -> void:
	_target(side, pos, rot_deg, curl, thumb, dur)


func grip(side: String, curl: float, dur := 0.15) -> void:
	var h: Dictionary = hands[side]
	var tg: Dictionary = h["tgt"]
	_target(side, tg["pos"], tg["rot"], curl, maxf(float(tg["thumb"]), curl * 0.8), dur)


## Узел кисти (запястье): к нему цепляется то, что рука держит (нейрошлем).
func wrist(side: String) -> Node3D:
	return (hands[side] as Dictionary)["wrist"]


## Мах рук при ходьбе: фаза шага (рад) и сила 0..1.
func walk(phase: float, amount: float) -> void:
	_walk_phase = phase
	_walk_amt = amount


## Скорость поворота головы (рад/с, + влево): руки чуть отстают от взгляда.
func sway(yaw_rate: float) -> void:
	_sway = lerpf(_sway, clampf(-yaw_rate * 0.05, -0.08, 0.08), 0.25)


func current(side: String) -> Dictionary:
	return (hands[side] as Dictionary)["cur"]


func _target(side: String, pos: Vector3, rot: Vector3, curl: float, thumb: float, dur: float) -> void:
	var h: Dictionary = hands[side]
	var tg := {"pos": pos, "rot": rot, "curl": curl, "thumb": thumb}
	h["tgt"] = tg
	h["rate"] = follow_rate if dur > 0.0 else 1000.0
	if dur > 0.0:
		h["rate"] = clampf(3.2 / dur, 4.0, 40.0)   # ~96 % пути за dur
	else:
		h["cur"] = tg.duplicate()
		_apply(side)


func _process(delta: float) -> void:
	for s in hands:
		var h: Dictionary = hands[s]
		var cur: Dictionary = h["cur"]
		var tg: Dictionary = h["tgt"]
		var a := 1.0 - exp(-delta * float(h.get("rate", follow_rate)))
		cur["pos"] = (cur["pos"] as Vector3).lerp(tg["pos"], a)
		cur["rot"] = (cur["rot"] as Vector3).lerp(tg["rot"], a)
		cur["curl"] = lerpf(float(cur["curl"]), float(tg["curl"]), a)
		cur["thumb"] = lerpf(float(cur["thumb"]), float(tg["thumb"]), a)
		_apply(s)


func _apply(side: String) -> void:
	var h: Dictionary = hands[side]
	var cur: Dictionary = h["cur"]
	# мах при ходьбе: руки в противофазе, чуть вверх-вниз и вперёд-назад; на повороте — запаздывание
	var ph := _walk_phase + (0.0 if side == "R" else PI)
	var walk_off := Vector3(0.0, absf(sin(ph)) * 0.012, sin(ph) * 0.018) * _walk_amt
	var root: Node3D = h["root"]
	var wp := (cur["pos"] as Vector3) + walk_off + Vector3(_sway * 0.6, 0.0, 0.0)
	root.position = wp
	var r: Vector3 = cur["rot"]
	root.basis = _arm_basis(wp - (SHOULDER[side] as Vector3)) * Basis(Vector3.BACK, deg_to_rad(r.z))
	var w := h["wrist"] as Node3D
	w.basis = ((h["rest"] as Dictionary)[w] as Basis) * Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), 0.0), EULER_ORDER_YXZ)
	var curl := float(cur["curl"])
	var rest: Dictionary = h["rest"]
	var fingers: Array = h["fingers"]
	for fi in fingers.size():
		var segs: Array = fingers[fi]
		var c := clampf(curl * (1.0 + 0.08 * fi), 0.0, 1.0)   # мизинец сгибается чуть больше
		for k in segs.size():
			var n := segs[k] as Node3D
			n.basis = (rest[n] as Basis) * Basis(Vector3.RIGHT, -deg_to_rad(CURL_DEG[k] * c))
	var th: Array = h["thumb"]
	var t := float(cur["thumb"])
	for k in th.size():
		var n := th[k] as Node3D
		n.basis = (rest[n] as Basis) * Basis(Vector3.RIGHT, -deg_to_rad(THUMB_DEG[k] * t))


## Кадр предплечья: −Z — от плеча к запястью (d), X — по горизонтали вправо, Y — вверх (тыльная сторона ладони при развороте 0).
func _arm_basis(d: Vector3) -> Basis:
	var z := -d.normalized()
	var x := Vector3.UP.cross(z)
	if x.length_squared() < 1e-4:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, z.cross(x), z)


# ---------------------------------------------------------------- модель

## Рука из модели FP_Hand_<R|L>: узел-кадр предплечья (root) → сцена glb (Arm → Hand → F*_1..3, T_1..3).
func _build_hand(side: String) -> Dictionary:
	var root := Node3D.new()
	root.name = "Hand" + side
	add_child(root)
	var inst := (MODELS[side] as PackedScene).instantiate() as Node3D
	root.add_child(inst)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = LAYER
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var wrist := inst.find_child("Hand", true, false) as Node3D
	var rest := {}
	var fingers: Array = []
	for i in range(1, 5):
		var segs: Array = []
		for k in range(1, 4):
			var n := inst.find_child("F%d_%d" % [i, k], true, false) as Node3D
			segs.append(n)
			rest[n] = n.basis
		fingers.append(segs)
	var thumb: Array = []
	for k in range(1, 4):
		var n := inst.find_child("T_%d" % k, true, false) as Node3D
		thumb.append(n)
		rest[n] = n.basis
	rest[wrist] = wrist.basis
	var cur := {"pos": Vector3(0, -0.4, -0.3), "rot": Vector3.ZERO, "curl": 0.4, "thumb": 0.3}
	return {"root": root, "wrist": wrist, "fingers": fingers, "thumb": thumb, "rest": rest, "cur": cur, "tgt": cur.duplicate(), "rate": follow_rate}
