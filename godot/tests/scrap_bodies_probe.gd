## Headless-проба сцен THE SCRAP, лист 01 (tools/build_scrap_bodies_scenes.gd → scenes/props/scrap/): все bodies_*.tscn и
## bit_*.tscn инстанцируются в ряд на полу (StaticBody3D 400 × 1 × 20, верх y = 0), R-тела и куски bits падают, свободные
## куски на кучах (Loose, в сцене sleeping) будятся; на каждую S-кучу сверху (над самым высоким срезом коллизии) падает
## бокс 0.4 м 20 кг в плоскости XY. Через N кадров (по умолчанию 180; запускать с --fixed-fps 60) проверяется:
##   R / bits / Loose:  нет NaN; не провалились (y > −0.1 м, а у лежащих на полу самая низкая точка выпуклой оболочки
##                      ≥ −0.03 м — не утонули в полу); не улетели (|Δx| ≤ 2.5 м, y ≤ y0 + 0.5 м; у Loose |Δx| ≤ 1.5 м);
##                      не «взрываются» (|v| < 1.5 м/с, |ω| < 8 рад/с в последнем кадре);
##   бокс на куче:      падает на самый пологий высокий участок профиля (срезы с верхом ≥ 75 % максимума, наименьший
##                      уклон с соседями); у куч (Heap / Pile) и Crushed_Puppet (плита) низ бокса выше пола (≥ 0.08 м),
##                      бокс не съехал за край; у всех — не провалился в коллизию (низ ≥ верх под ним − 0.12 м).
##                      Лежащие куклы (Broken_Puppet, Half_Puppet) — узкий невысокий профиль: бокс с них скатывается, это норма.
## Код выхода 0 — всё прошло, 1 — есть провалы (список в выводе). Запуск (через обёртку блокировки у агентов):
##   godot --headless --path godot --fixed-fps 60 res://tests/scrap_bodies_probe.tscn [-- "frames=180,g=9.8"]
## g — гравитация на время пробы (по умолчанию из project.godot: 3d/default_gravity).
extends Node3D

const DIR := "res://scenes/props/scrap/"
const BOX_MASS := 20.0
const BOX_SIZE := 0.4

var max_frames := 180
var frames := 0
var gravity := -1.0
var tracked: Array = []      # {name, body, start, kind}
var boxes: Array = []        # {name, box, heap, x0, x1}
var heaps: Dictionary = {}   # name → StaticBody3D


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			if p[0] == "frames":
				max_frames = int(p[1])
			elif p[0] == "g":
				gravity = float(p[1])
	if gravity > 0.0:
		PhysicsServer3D.area_set_param(get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, gravity)
	var g: float = gravity if gravity > 0.0 else float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	var fm := PhysicsMaterial.new()
	fm.friction = 0.9
	floor_body.physics_material_override = fm
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(400, 1, 20)
	cs.shape = bs
	floor_body.add_child(cs)
	floor_body.position = Vector3(150, -0.5, 0)
	add_child(floor_body)
	var files := DirAccess.get_files_at(DIR)
	var bodies: Array = []
	var bits: Array = []
	for f in files:
		var fn := String(f).trim_suffix(".remap")
		if not fn.ends_with(".tscn"):
			continue
		if fn.begins_with("bodies_"):
			bodies.append(fn)
		elif fn.begins_with("bit_"):
			bits.append(fn)
	bodies.sort()
	bits.sort()
	print("scrap probe: %d bodies, %d bits, g=%.2f, frames=%d" % [bodies.size(), bits.size(), g, max_frames])
	var x := 0.0
	for fn in bodies:
		var ps: PackedScene = load(DIR + fn)
		if ps == null:
			_fail_now("не загрузилась " + fn)
			continue
		var inst: Node3D = ps.instantiate()
		add_child(inst)
		var aabb := _aabb(inst)
		var w := maxf(aabb.size.x, 0.5)
		inst.position = Vector3(x + w * 0.5 - (aabb.position.x + aabb.size.x * 0.5), 0.0, 0.0)
		if inst is RigidBody3D:
			inst.position.y += 0.3                                   # R-ассеты падают с 0.3 м
		x += w + 2.0
		_collect(inst, fn.trim_suffix(".tscn"))
	x += 2.0
	for fn in bits:
		var ps: PackedScene = load(DIR + fn)
		if ps == null:
			_fail_now("не загрузилась " + fn)
			continue
		var inst: RigidBody3D = ps.instantiate()
		inst.position = Vector3(x, 1.2, 0.0)
		inst.rotation.z = 0.3 * float(bits.find(fn) % 5)
		add_child(inst)
		x += 1.6
		tracked.append({"name": fn.trim_suffix(".tscn"), "body": inst, "start": inst.position, "kind": "bit"})
	await get_tree().physics_frame
	for t in tracked:
		var b: RigidBody3D = t["body"]
		t["start"] = b.global_position
		if t["kind"] == "loose":
			b.sleeping = false
	for name in heaps:
		_drop_box(name, heaps[name])


func _collect(inst: Node, name: String) -> void:
	if inst is RigidBody3D:
		tracked.append({"name": name, "body": inst, "start": Vector3.ZERO, "kind": "R"})
		return
	for n in inst.find_children("*", "RigidBody3D", true, false):
		tracked.append({"name": name + "/" + n.name, "body": n, "start": Vector3.ZERO, "kind": "loose"})
	var st: Array = [inst] if inst is StaticBody3D else inst.find_children("*", "StaticBody3D", true, false)
	if not st.is_empty():
		heaps[name] = st[0]


func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for v in n.find_children("*", "VisualInstance3D", true, false):
		var a: AABB = (v as VisualInstance3D).global_transform * (v as VisualInstance3D).get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out


## Профиль верха S-кучи в мировых координатах: [[x0, x1, h0, h1], …] из призм-срезов (у среза 8 точек: x0/x1 × низ/верх × ±z).
func _slices(heap: StaticBody3D) -> Array:
	var out: Array = []
	for c in heap.get_children():
		if c is CollisionShape3D and c.shape is ConvexPolygonShape3D:
			var pts: PackedVector3Array = c.shape.points
			var xs := {}
			for p in pts:
				var gx: float = snappedf(heap.global_position.x + p.x, 0.0001)
				xs[gx] = maxf(xs.get(gx, -1e9), heap.global_position.y + p.y)
			var ks := xs.keys()
			ks.sort()
			if ks.size() >= 2:
				out.append([ks[0], ks[ks.size() - 1], xs[ks[0]], xs[ks[ks.size() - 1]]])
	return out


## Самая низкая точка выпуклых оболочек тела в мире (по точкам ConvexPolygonShape3D).
func _lowest(b: RigidBody3D) -> float:
	var lo := 1e9
	for c in b.get_children():
		if c is CollisionShape3D and c.shape is ConvexPolygonShape3D:
			var xf: Transform3D = b.global_transform * (c as CollisionShape3D).transform
			for p in (c.shape as ConvexPolygonShape3D).points:
				lo = minf(lo, (xf * p).y)
	return lo


func _top_at(sl: Array, x: float) -> float:
	var best := -1.0
	for s in sl:
		if x >= s[0] - 1e-4 and x <= s[1] + 1e-4:
			var t: float = (x - s[0]) / maxf(1e-6, s[1] - s[0])
			best = maxf(best, lerpf(s[2], s[3], t))
	return best


func _drop_box(name: String, heap: StaticBody3D) -> void:
	var sl := _slices(heap)
	if sl.is_empty():
		_fail_now(name + ": нет срезов коллизии")
		return
	sl.sort_custom(func(a, b): return a[0] < b[0])
	var hmax := 0.0
	for s in sl:
		hmax = maxf(hmax, maxf(s[2], s[3]))
	var best := -1
	var best_slope := 1e9
	for i in sl.size():
		var s: Array = sl[i]
		if minf(s[2], s[3]) < 0.75 * hmax:
			continue
		var slope := 0.0
		for j in [i - 1, i, i + 1]:
			if j < 0 or j >= sl.size():
				slope = maxf(slope, 10.0)                       # край кучи
				continue
			var t: Array = sl[j]
			slope = maxf(slope, absf(t[3] - t[2]) / maxf(1e-4, t[1] - t[0]))
		if slope < best_slope:
			best_slope = slope
			best = i
	if best < 0:
		best = 0
		for i in sl.size():
			if maxf(sl[i][2], sl[i][3]) > maxf(sl[best][2], sl[best][3]):
				best = i
	var bx: float = (sl[best][0] + sl[best][1]) * 0.5
	var top := _top_at(sl, bx)
	var b := RigidBody3D.new()
	b.name = "Box_" + name
	b.mass = BOX_MASS
	b.axis_lock_linear_z = true
	b.axis_lock_angular_x = true
	b.axis_lock_angular_y = true
	b.continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	b.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3.ONE * BOX_SIZE
	cs.shape = bs
	b.add_child(cs)
	add_child(b)
	b.global_position = Vector3(bx, top + BOX_SIZE * 0.5 + 0.6, 0.0)
	var x0: float = sl[0][0]
	var x1: float = sl[0][1]
	for s in sl:
		x0 = minf(x0, s[0])
		x1 = maxf(x1, s[1])
	var stay := name.contains("heap") or name.contains("pile") or name.contains("crushed")
	boxes.append({"name": name, "box": b, "heap": sl, "x0": x0, "x1": x1, "top": top, "stay": stay})


var _early_fail: Array = []


func _fail_now(msg: String) -> void:
	_early_fail.append(msg)
	push_error(msg)


func _physics_process(_delta: float) -> void:
	frames += 1
	if frames < max_frames:
		return
	set_physics_process(false)
	var fails: Array = _early_fail.duplicate()
	print("%-52s %8s %8s %8s %7s %7s %7s" % ["body", "dx", "dy", "y", "|v|", "|w|", "low"])
	for t in tracked:
		var b: RigidBody3D = t["body"]
		var p := b.global_position
		var d: Vector3 = p - t["start"]
		var v := b.linear_velocity.length()
		var w := b.angular_velocity.length()
		var bad := ""
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			bad = "NaN"
		elif p.y < -0.1:
			bad = "провалился под пол"
		elif absf(d.x) > (1.5 if t["kind"] == "loose" else 2.5) or d.y > 0.5:
			bad = "улетел"
		elif v > 1.5 or w > 8.0:
			bad = "не успокоился / взрыв"
		var low := _lowest(b)
		if bad == "" and low < 0.3 and low < -0.03 and t["kind"] != "loose":
			bad = "утонул в полу (низ оболочки %.3f)" % low
		print("%-52s %8.3f %8.3f %8.3f %7.3f %7.3f %7.3f %s" % [t["name"], d.x, d.y, p.y, v, w, _lowest(b), bad])
		if bad != "":
			fails.append("%s: %s" % [t["name"], bad])
	print("%-30s %8s %8s %8s %8s" % ["heap + box 20 kg", "top", "box_bot", "surf", "x"])
	for bx in boxes:
		var b: RigidBody3D = bx["box"]
		var p := b.global_position
		var bot := p.y - BOX_SIZE * 0.5
		var surf := _top_at(bx["heap"], p.x)
		var bad := ""
		if not is_finite(p.y):
			bad = "NaN"
		elif bx["stay"] and bot < 0.08:
			bad = "бокс на полу — не удержался на куче"
		elif bx["stay"] and (p.x < bx["x0"] or p.x > bx["x1"]):
			bad = "бокс съехал с кучи"
		elif surf > 0.0 and bot < surf - 0.12:
			bad = "бокс провалился в кучу"
		elif bot < -0.03:
			bad = "бокс ушёл в пол"
		elif not bx["stay"] and bot < 0.08:
			bad = ""
			print("  (%s: лежащая кукла — бокс скатился на пол, ожидаемо)" % bx["name"])
		print("%-30s %8.3f %8.3f %8.3f %8.3f %s" % [bx["name"], bx["top"], bot, surf, p.x, bad])
		if bad != "":
			fails.append("%s: %s" % [bx["name"], bad])
	if fails.is_empty():
		print("SCRAP PROBE OK: %d тел, %d куч с боксом" % [tracked.size(), boxes.size()])
		get_tree().quit(0)
	else:
		print("SCRAP PROBE FAIL (%d):" % fails.size())
		for f in fails:
			print("  ", f)
		get_tree().quit(1)
