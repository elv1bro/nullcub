## Руки героя от первого лица в гараже (06.10, автор: «человек будет как будто мы — от первого лица + руки»; лор — LORE_V2 §2а:
## герой — механик). Рукава рабочей куртки (тёмно-синие, светоотражающая полоса), перчатки механика (уголь, оранжевая накладка
## на костяшках и липучка). Модель собирается здесь из примитивов: у каждого пальца три фаланги — узлы, которые сгибаются (curl),
## так позы и жесты ставятся числами, без скелета и анимаций.
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
	"rest": {"R": [Vector3(0.17, -0.205, -0.32), Vector3(-14.0, 8.0, -64.0), 0.7, 0.55],
		"L": [Vector3(-0.19, -0.215, -0.33), Vector3(-14.0, -8.0, 64.0), 0.74, 0.55]},
	"down": {"R": [Vector3(0.2, -0.46, -0.24), Vector3(-10.0, 0.0, -60.0), 0.6, 0.5],
		"L": [Vector3(-0.22, -0.46, -0.24), Vector3(-10.0, 0.0, 60.0), 0.6, 0.5]},
	"point": {"R": [Vector3(0.11, -0.13, -0.42), Vector3(0.0, 4.0, -35.0), 0.0, 0.6],
		"L": [Vector3(-0.2, -0.22, -0.33), Vector3(-14.0, -8.0, 64.0), 0.74, 0.55]},
	"open": {"R": [Vector3(0.15, -0.16, -0.4), Vector3(-6.0, 0.0, -40.0), 0.1, 0.1],
		"L": [Vector3(-0.15, -0.16, -0.4), Vector3(-6.0, 0.0, 40.0), 0.1, 0.1]},
}
## Плечи в кадре камеры (опорный FOV): предплечье тянется от запястья к ним.
const SHOULDER := {"R": Vector3(0.2, -0.4, 0.1), "L": Vector3(-0.2, -0.4, 0.1)}
## Кадры пальцев (длина фаланг, м) и места их корней на краю ладони (x поперёк, правая рука; у левой x зеркалится).
const FINGERS := [
	{"x": -0.029, "len": [0.036, 0.024, 0.02], "r": 0.0098, "splay": -5.0},
	{"x": -0.009, "len": [0.04, 0.027, 0.021], "r": 0.0102, "splay": -1.0},
	{"x": 0.011, "len": [0.038, 0.025, 0.02], "r": 0.0098, "splay": 2.5},
	{"x": 0.03, "len": [0.03, 0.02, 0.017], "r": 0.0088, "splay": 6.0},
]
const CURL_DEG := [62.0, 78.0, 52.0]
const PALM_LEN := 0.088

## Скорость, с которой руки догоняют цель (1/с).
@export var follow_rate := 14.0

var hands := {}          # "R" / "L" → {root, wrist, fingers: [[узлы фаланг]], thumb: [узлы], cur: {}, tgt: {}}
var fill: OmniLight3D
var _walk_phase := 0.0
var _walk_amt := 0.0
var _sway := 0.0
var _mats := {}


func _ready() -> void:
	_make_mats()
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
	var sgn := 1.0 if side == "R" else -1.0
	# мах при ходьбе: руки в противофазе, чуть вверх-вниз и вперёд-назад; на повороте — запаздывание
	var ph := _walk_phase + (0.0 if side == "R" else PI)
	var walk_off := Vector3(0.0, absf(sin(ph)) * 0.012, sin(ph) * 0.018) * _walk_amt
	var root: Node3D = h["root"]
	var wp := (cur["pos"] as Vector3) + walk_off + Vector3(_sway * 0.6, 0.0, 0.0)
	root.position = wp
	var r: Vector3 = cur["rot"]
	root.basis = _arm_basis(wp - (SHOULDER[side] as Vector3)) * Basis(Vector3.BACK, deg_to_rad(r.z))
	(h["wrist"] as Node3D).basis = Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), 0.0), EULER_ORDER_YXZ)
	var curl := float(cur["curl"])
	var fingers: Array = h["fingers"]
	for fi in fingers.size():
		var segs: Array = fingers[fi]
		var c := clampf(curl * (1.0 + 0.08 * fi), 0.0, 1.0)   # мизинец сгибается чуть больше
		for k in segs.size():
			(segs[k] as Node3D).rotation.x = deg_to_rad(CURL_DEG[k] * c)
	var th: Array = h["thumb"]
	var t := float(cur["thumb"])
	(th[0] as Node3D).rotation = Vector3(deg_to_rad(-12.0 * t), deg_to_rad(sgn * (38.0 - 30.0 * t)), deg_to_rad(sgn * 20.0 * t))
	(th[1] as Node3D).rotation.x = deg_to_rad(40.0 * t)


## Кадр предплечья: −Z — от плеча к запястью (d), X — по горизонтали вправо, Y — вверх (тыльная сторона ладони при развороте 0).
func _arm_basis(d: Vector3) -> Basis:
	var z := -d.normalized()
	var x := Vector3.UP.cross(z)
	if x.length_squared() < 1e-4:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, z.cross(x), z)


# ---------------------------------------------------------------- модель

func _make_mats() -> void:
	var glove := StandardMaterial3D.new()
	glove.albedo_color = Color(0.11, 0.11, 0.12)
	glove.roughness = 0.82
	var pad := StandardMaterial3D.new()
	pad.albedo_color = Color(0.86, 0.42, 0.13)
	pad.roughness = 0.6
	var palm := StandardMaterial3D.new()
	palm.albedo_color = Color(0.36, 0.27, 0.19)
	palm.roughness = 0.7
	var sleeve := StandardMaterial3D.new()
	sleeve.albedo_color = Color(0.13, 0.17, 0.27)
	sleeve.roughness = 0.92
	var stripe := StandardMaterial3D.new()
	stripe.albedo_color = Color(0.78, 0.78, 0.74)
	stripe.roughness = 0.35
	stripe.metallic = 0.3
	stripe.emission_enabled = true
	stripe.emission = Color(0.6, 0.62, 0.6)
	stripe.emission_energy_multiplier = 0.15
	_mats = {"glove": glove, "pad": pad, "palm": palm, "sleeve": sleeve, "stripe": stripe}


func _mesh(parent: Node3D, mesh: Mesh, mat: String, pos: Vector3, rot_deg := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mats[mat]
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	mi.layers = LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, 2.0 * r + 0.001)
	c.radial_segments = 10
	c.rings = 3
	return c


## Кисть: начало кадра — запястье, пальцы вдоль −Z, тыльная сторона +Y, большой палец со стороны −X (правая) / +X (левая).
func _build_hand(side: String) -> Dictionary:
	var sgn := 1.0 if side == "R" else -1.0
	var root := Node3D.new()
	root.name = "Hand" + side
	add_child(root)
	var wrist := Node3D.new()      # кисть: сгиб относительно предплечья (rot.x / rot.y)
	wrist.name = "Wrist"
	root.add_child(wrist)
	# рукав и манжета: вдоль +Z от запястья (к локтю, за край кадра)
	var sl := CylinderMesh.new()
	sl.top_radius = 0.043
	sl.bottom_radius = 0.052
	sl.height = 0.34
	sl.radial_segments = 14
	_mesh(root, sl, "sleeve", Vector3(0, 0.002, 0.2), Vector3(90, 0, 0))
	var st := CylinderMesh.new()
	st.top_radius = 0.0465
	st.bottom_radius = 0.0475
	st.height = 0.022
	st.radial_segments = 14
	_mesh(root, st, "stripe", Vector3(0, 0.002, 0.1), Vector3(90, 0, 0))
	var cuff := CylinderMesh.new()
	cuff.top_radius = 0.034
	cuff.bottom_radius = 0.04
	cuff.height = 0.06
	cuff.radial_segments = 14
	_mesh(root, cuff, "glove", Vector3(0, 0.0, 0.02), Vector3(90, 0, 0))
	var strap := BoxMesh.new()
	strap.size = Vector3(0.072, 0.012, 0.024)
	_mesh(root, strap, "pad", Vector3(0, 0.034, 0.02))
	# ладонь — приплюснутый эллипсоид, накладка на костяшках, светлая ладонная сторона
	var palm := SphereMesh.new()
	palm.radius = 0.5
	palm.height = 1.0
	palm.radial_segments = 16
	palm.rings = 8
	_mesh(wrist, palm, "glove", Vector3(0, 0, -PALM_LEN * 0.52), Vector3.ZERO, Vector3(0.086, 0.034, PALM_LEN * 1.1))
	_mesh(wrist, palm, "palm", Vector3(0, -0.006, -PALM_LEN * 0.5), Vector3.ZERO, Vector3(0.078, 0.026, PALM_LEN * 0.95))
	var knuckle := BoxMesh.new()
	knuckle.size = Vector3(0.072, 0.012, 0.026)
	_mesh(wrist, knuckle, "pad", Vector3(0, 0.014, -PALM_LEN + 0.012), Vector3(-6, 0, 0))
	# пальцы: три фаланги-узла, у каждого капсула вдоль −Z
	var fingers: Array = []
	for f in FINGERS:
		var segs: Array = []
		var parent: Node3D = wrist
		var base := Node3D.new()
		base.position = Vector3(float(f["x"]) * sgn, 0.0, -PALM_LEN + 0.004)
		base.rotation_degrees = Vector3(0, -float(f["splay"]) * sgn, 0)
		wrist.add_child(base)
		parent = base
		var lens: Array = f["len"]
		var r := float(f["r"])
		for k in lens.size():
			var j := Node3D.new()
			if k > 0:
				j.position = Vector3(0, 0, -float(lens[k - 1]))
			parent.add_child(j)
			var rr := r * (1.0 - 0.1 * k)
			_mesh(j, _capsule(rr, float(lens[k]) + rr * 1.6), "glove", Vector3(0, 0, -float(lens[k]) * 0.5), Vector3(90, 0, 0))
			segs.append(j)
			parent = j
		fingers.append(segs)
	# большой палец: от основания ладони вбок и вперёд, две фаланги
	var tb := Node3D.new()
	tb.position = Vector3(-0.036 * sgn, -0.008, -0.03)
	wrist.add_child(tb)
	var t0 := Node3D.new()
	tb.add_child(t0)
	_mesh(t0, _capsule(0.012, 0.05), "glove", Vector3(0, 0, -0.02), Vector3(90, 0, 0))
	var t1 := Node3D.new()
	t1.position = Vector3(0, 0, -0.038)
	t0.add_child(t1)
	_mesh(t1, _capsule(0.0105, 0.04), "glove", Vector3(0, 0, -0.016), Vector3(90, 0, 0))
	tb.rotation_degrees = Vector3(0, sgn * 42.0, sgn * -25.0)
	var cur := {"pos": Vector3(0, -0.4, -0.3), "rot": Vector3.ZERO, "curl": 0.4, "thumb": 0.3}
	return {"root": root, "wrist": wrist, "fingers": fingers, "thumb": [t0, t1], "cur": cur, "tgt": cur.duplicate(), "rate": follow_rate}
