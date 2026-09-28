## Headless-проба модульного кита Свалки (tools/build_scrap_kit_scenes.gd → scenes/props/scrap/kit_*.tscn): инстанцирует
## каждую сцену кита (в ряд через 14 м), проверяет статически, что сцена загрузилась, в ней есть меш, а у ходибельных
## модулей есть коллизия, пересекающая z = 0 с глубиной ≥ 0.6; затем роняет на настилы, скаты, крышки опор и балки
## RigidBody3D 20 кг — куб 0.4 (и шар ⌀0.5 на плоских платформах) в плоскости XY (оси как у кукол: z и повороты X/Y
## заблокированы) с высоты 0.5 м над поверхностью и скоростью −2 м/с, ждёт FRAMES физических кадров (гравитация
## проекта, 2 м/с²) и проверяет, что тело лежит сверху: |y − ожидаемая| ≤ TOL_Y (не провалилось и не подпрыгнуло),
## сдвиг по x ≤ TOL_X (не улетело, не скатилось), скорость ≤ TOL_V. Печатает строку на каждый бросок; код выхода 0 — всё ок.
## Запуск: godot --headless --path godot res://tests/scrap_kit_probe.tscn --fixed-fps 60
extends Node3D

const DIR := "res://scenes/props/scrap/"
const FRAMES := 120
const MASS := 20.0
const BOX := 0.4
const BALL_R := 0.25
const TOL_Y := 0.08
const TOL_X := 0.35
const TOL_V := 0.3
const SPACING := 14.0

## сцена → броски [x, y поверхности в точке x=0 модуля, наклон tan(θ) поверхности, "box"|"ball"] (локальные оси модуля)
const CASES := {
	"kit_platform_s": [[0.0, 0.0, 0.0, "box"], [0.55, 0.0, 0.0, "ball"]],
	"kit_platform_m": [[-1.2, 0.0, 0.0, "box"], [1.3, 0.0, 0.0, "ball"]],
	"kit_platform_l": [[-2.2, 0.0, 0.0, "box"], [0.0, 0.0, 0.0, "box"], [2.4, 0.0, 0.0, "ball"]],
	"kit_platform_end_l": [[0.0, 0.0, 0.0, "box"]],
	"kit_platform_end_r": [[0.0, 0.0, 0.0, "box"]],
	"kit_platform_gap": [[-1.3, 0.0, 0.0, "box"], [1.3, 0.0, 0.0, "box"]],
	"kit_platform_lower": [[0.0, 0.0, 0.0, "box"]],
	"kit_platform_upper": [[0.0, 0.0, 0.0, "box"]],
	"kit_slope_15": [[-0.8, 0.5, 0.25, "box"], [1.0, 0.5, 0.25, "box"]],
	"kit_slope_30": [[-0.8, 1.0, 0.5, "box"], [1.0, 1.0, 0.5, "box"]],
	"kit_support_s": [[0.0, 3.0, 0.0, "box"]],
	"kit_support_m": [[0.0, 4.0, 0.0, "box"]],
	"kit_support_l": [[0.0, 6.0, 0.0, "box"]],
	"kit_support_diagonal": [[0.0, 3.0, 0.0, "box"]],
	"kit_wall_frame": [[0.0, 3.0, 0.0, "box"]],
	"kit_banner_frame": [[0.0, 4.0, 0.0, "box"]],
	"kit_hanging_beam": [[0.0, 0.0, 0.0, "box"], [-1.0, 0.0, 0.0, "box"]],
	"kit_railing": [],
	"kit_ladder": [],
	"kit_chain_hook": [],
}
## декор без коллизии
const NO_COLLISION := ["kit_chain_hook"]

var drops: Array[Dictionary] = []
var frame := 0
var fails := 0


func _ready() -> void:
	var i := 0
	for scene_name: String in CASES:
		var origin := Vector3(i * SPACING, 0.0, 0.0)
		i += 1
		var ps: PackedScene = load(DIR + scene_name + ".tscn")
		if ps == null:
			_fail("%s: сцена не загрузилась" % scene_name)
			continue
		var inst: Node3D = ps.instantiate()
		inst.position = origin
		add_child(inst)
		_check_static(scene_name, inst)
		for c in CASES[scene_name]:
			_drop(scene_name, origin, float(c[0]), float(c[1]), float(c[2]), String(c[3]))


func _check_static(scene_name: String, inst: Node3D) -> void:
	var meshes := inst.find_children("*", "MeshInstance3D", true, false)
	var surfaces := 0
	var tris := 0
	for m: MeshInstance3D in meshes:
		if m.mesh != null:
			surfaces += m.mesh.get_surface_count()
			tris += m.mesh.get_faces().size() / 3      # в headless (dummy-рендер) может быть 0 — тогда смотрим на поверхности
	if meshes.is_empty() or surfaces == 0:
		_fail("%s: нет меша" % scene_name)
	var shapes := inst.find_children("*", "CollisionShape3D", true, false)
	var crossing := 0
	for cs: CollisionShape3D in shapes:
		var box := cs.shape as BoxShape3D
		if box == null:
			continue
		var zc := cs.global_position.z
		var hz := box.size.z * 0.5
		if zc - hz <= 0.0 and zc + hz >= 0.0 and box.size.z >= 0.6 - 1e-4:
			crossing += 1
	var need := not NO_COLLISION.has(scene_name)
	var ok := (crossing > 0) == need and (need or shapes.is_empty())
	print("%-22s mesh surfaces=%d tris=%5d  shapes=%2d crossing z=0 (≥0.6)=%2d  %s" % [scene_name, surfaces, tris, shapes.size(), crossing, "ok" if ok else "FAIL"])
	if not ok:
		_fail("%s: коллизия не соответствует (нужна=%s, пересекающих z=0: %d)" % [scene_name, str(need), crossing])


func _drop(scene_name: String, origin: Vector3, x: float, y0: float, slope: float, kind: String) -> void:
	var b := RigidBody3D.new()
	b.name = "Drop_%s_%d" % [scene_name, drops.size()]
	b.mass = MASS
	b.axis_lock_linear_z = true
	b.axis_lock_angular_x = true
	b.axis_lock_angular_y = true
	b.continuous_cd = true
	var cs := CollisionShape3D.new()
	var half := 0.0
	if kind == "ball":
		var sp := SphereShape3D.new()
		sp.radius = BALL_R
		cs.shape = sp
		half = BALL_R
	else:
		var bx := BoxShape3D.new()
		bx.size = Vector3(BOX, BOX, BOX)
		cs.shape = bx
		half = BOX * 0.5
	b.add_child(cs)
	var surf := y0 + slope * x
	b.position = origin + Vector3(x, surf + half + 0.5, 0.0)
	b.rotation.z = atan(slope)
	add_child(b)
	b.linear_velocity = Vector3(0.0, -2.0, 0.0)
	drops.append({"body": b, "scene": scene_name, "origin": origin, "x": x, "y0": y0, "slope": slope, "half": half, "kind": kind})


func _physics_process(_delta: float) -> void:
	frame += 1
	if frame < FRAMES:
		return
	set_physics_process(false)
	for d in drops:
		var b: RigidBody3D = d["body"]
		var lp: Vector3 = b.global_position - (d["origin"] as Vector3)
		var slope: float = d["slope"]
		var th := atan(slope)
		# центр тела, лежащего на поверхности y = y0 + slope·x: половина размера по нормали (куб повернут вдоль ската)
		var expect: float = float(d["y0"]) + slope * lp.x + float(d["half"]) / cos(th)
		var dy := lp.y - expect
		var dx := lp.x - float(d["x"])
		var v := b.linear_velocity.length()
		var ok: bool = absf(dy) <= TOL_Y and absf(dx) <= TOL_X and v <= TOL_V
		print("%-22s %-4s x0=%5.2f → x=%5.2f y=%6.3f (ожид. %6.3f, Δy=%+.3f)  v=%.3f  %s" % [d["scene"], d["kind"], d["x"], lp.x, lp.y, expect, dy, v, "ok" if ok else "FAIL"])
		if not ok:
			fails += 1
	print("scrap_kit_probe: %d бросков, %d сцен, провалов: %d (кадров %d)" % [drops.size(), CASES.size(), fails, frame])
	get_tree().quit(0 if fails == 0 else 1)


func _fail(msg: String) -> void:
	push_error("scrap_kit_probe: " + msg)
	print("FAIL ", msg)
	fails += 1
