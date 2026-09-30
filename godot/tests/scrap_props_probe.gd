## Headless-проба пропсов Свалки (лист 02, №021–040; сцены scenes/props/scrap/prop_*.tscn из tools/build_scrap_props_scenes.gd).
## Запуск: godot --headless --path godot --fixed-fps 60 res://tests/scrap_props_probe.tscn
## Каждая сцена — на своей дорожке z = i × LANE (тела заперты в своей плоскости z и соседей не задевают), пол — общий бокс.
##   Фаза 1 «падение», FRAMES кадров физики (180 при --fixed-fps 60 = 3 с сим-времени, g = 2 м/с² из project.godot):
##     R/B — роняем с DROP м над полом; проверки: не провалился (origin.y > −0.06), не улетел (подъём < 0.35 м над стартом,
##     |Δx| < 0.6 м), в конце покоится (последние 30 кадров |v| < 0.05 м/с, |ω| < 0.25 рад/с), B не разрушился от падения;
##     S — стоит на полу; на него роняем пробный бокс 10 кг с 1 м над верхом коллизии — он должен остаться на пропсе
##     (не провалился сквозь коллизию) и успокоиться.
##   Фаза 2 «удар» (только B — у кого есть скрипт breakable.gd): свежий экземпляр отстаивается SETTLE кадров, затем в него
##     летит тяжёлое тело (40 кг, куб 0.4 м, CCD) со скоростью 30 м/с; до 3 попыток. Проверки: сигнал destroyed пришёл,
##     обломков (группа "debris" на этой дорожке) ≥ 3, через 60 кадров все обломки над полом. Взрывные бочки (ExplosiveBarrel,
##     prop_metal_barrel*, 29.09) обломков не дают — вместо них проверяется взрыв (узел Explosion на дорожке, толкнул снаряд).
## Печатает таблицу и JSON-отчёт (tests/scrap_props_probe_report.json); код выхода 0 — всё ок, 1 — есть провалы.
extends Node3D

const DIR := "res://scenes/props/scrap/"
const FRAMES := 180
const LANE := 6.0
const DROP := 0.3
const SETTLE := 60
const HIT_SPEED := 30.0
const HIT_MASS := 40.0
const REST_WINDOW := 30

var frame := 0
var phase := "drop"
var items: Array = []        # {name, node, kind: "R"|"B"|"S", start, max_y, rest_v, rest_w, probe}
var hits: Array = []         # {name, node, lane_z, stage, t, tries, destroyed, proj, debris}
var report := {"ok": true, "frames": FRAMES, "checks": []}
var _files: PackedStringArray


func _ready() -> void:
	var fl := StaticBody3D.new()
	fl.name = "Floor"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(40.0, 1.0, 400.0)
	cs.shape = bs
	fl.add_child(cs)
	fl.position = Vector3(0, -0.5, 150.0)
	add_child(fl)
	_files = PackedStringArray()
	for f in DirAccess.get_files_at(DIR):
		if f.begins_with("prop_") and f.ends_with(".tscn"):
			_files.append(f)
	_files.sort()
	if _files.is_empty():
		_fail("scenes", "нет сцен в " + DIR)
		_finish()
		return
	for i in _files.size():
		var ps: PackedScene = load(DIR + _files[i])
		var n := ps.instantiate() as Node3D
		var z := i * LANE
		var kind := "S"
		if n is RigidBody3D:
			kind = "B" if n.get_script() != null and n.has_signal("destroyed") else "R"
		n.position = Vector3(0, DROP if kind != "S" else 0.0, z)
		add_child(n)
		var it := {"name": _files[i].get_basename(), "node": n, "kind": kind, "start": n.position, "max_y": n.position.y,
			"rest_v": 0.0, "rest_w": 0.0, "destroyed": false, "probe": null, "top": 0.0}
		if kind == "B":
			n.connect("destroyed", func() -> void: it["destroyed"] = true)
		items.append(it)
	print("scrap_props_probe: %d scenes" % items.size())


func _physics_process(_delta: float) -> void:
	frame += 1
	if frame == 2:
		_spawn_probe_boxes()
	if phase == "drop":
		_tick_drop()
		if frame >= FRAMES:
			_check_drop()
			_start_hits()
	elif phase == "hit":
		_tick_hits()


# ---------------------------------------------------------------- фаза 1
## Статике — пробный бокс: луч сверху в x = 0 находит верх коллизии пропса, бокс 10 кг появляется на 1 м выше.
func _spawn_probe_boxes() -> void:
	var space := get_world_3d().direct_space_state
	for i in items.size():
		var it: Dictionary = items[i]
		if it["kind"] != "S":
			continue
		var z: float = (it["start"] as Vector3).z
		var q := PhysicsRayQueryParameters3D.create(Vector3(0, 6.0, z), Vector3(0, -1.0, z))
		var hit := space.intersect_ray(q)
		var top := 0.0
		if not hit.is_empty() and hit["collider"] == it["node"]:
			top = (hit["position"] as Vector3).y
		else:
			_fail("probe_ray:" + it["name"], "луч в x=0 не попал в коллизию пропса")
		it["top"] = top
		var pb := _box_body("ProbeBox_%d" % i, 10.0, Vector3(0.3, 0.3, 0.3))
		pb.position = Vector3(0, top + 1.0 + 0.15, z)
		add_child(pb)
		it["probe"] = pb


func _tick_drop() -> void:
	for it in items:
		var n: Node3D = it["node"]
		if not is_instance_valid(n):
			continue
		it["max_y"] = maxf(it["max_y"], n.global_position.y)
		if frame > FRAMES - REST_WINDOW:
			if n is RigidBody3D:
				it["rest_v"] = maxf(it["rest_v"], (n as RigidBody3D).linear_velocity.length())
				it["rest_w"] = maxf(it["rest_w"], (n as RigidBody3D).angular_velocity.length())
			elif it["probe"] != null:
				it["rest_v"] = maxf(it["rest_v"], (it["probe"] as RigidBody3D).linear_velocity.length())


func _check_drop() -> void:
	print("\n%-34s %-2s %8s %8s %8s %8s %8s  %s" % ["scene", "k", "y", "dx", "rise", "|v|", "|w|", "result"])
	for it in items:
		var n: Node3D = it["node"]
		var nm: String = it["name"]
		var fails: Array = []
		var y := 0.0
		var dx := 0.0
		var rise := 0.0
		if not is_instance_valid(n) or not n.is_inside_tree():
			fails.append("исчез")
		else:
			y = n.global_position.y
			dx = n.global_position.x - (it["start"] as Vector3).x
			rise = it["max_y"] - (it["start"] as Vector3).y
			if it["kind"] == "S":
				var pb: RigidBody3D = it["probe"]
				var py := pb.global_position.y - 0.15
				if py < it["top"] - 0.08:
					fails.append("пробный бокс провалился: низ %.2f < верх коллизии %.2f" % [py, it["top"]])
				if it["rest_v"] > 0.05:
					fails.append("пробный бокс не успокоился |v|=%.3f" % it["rest_v"])
			else:
				if y < -0.06:
					fails.append("провалился y=%.3f" % y)
				if rise > 0.35:
					fails.append("подлетел на %.2f м" % rise)
				if absf(dx) > 0.6:
					fails.append("уехал |dx|=%.2f" % absf(dx))
				if it["rest_v"] > 0.05 or it["rest_w"] > 0.25:
					fails.append("не успокоился |v|=%.3f |w|=%.3f" % [it["rest_v"], it["rest_w"]])
				if it["kind"] == "B" and it["destroyed"]:
					fails.append("разрушился от падения")
		var ok := fails.is_empty()
		print("%-34s %-2s %8.3f %8.3f %8.3f %8.3f %8.3f  %s" % [nm, it["kind"], y, dx, rise, it["rest_v"], it["rest_w"], "ok" if ok else ", ".join(fails)])
		_check("drop:" + nm, ok, {"kind": it["kind"], "y": y, "dx": dx, "rise": rise, "rest_v": it["rest_v"], "rest_w": it["rest_w"], "fails": fails})


# ---------------------------------------------------------------- фаза 2
func _start_hits() -> void:
	phase = "hit"
	var lane := items.size() + 2
	for it in items:
		if it["kind"] != "B":
			continue
		var ps: PackedScene = load(DIR + it["name"] + ".tscn")
		var n := ps.instantiate() as RigidBody3D
		var z := lane * LANE
		lane += 1
		n.position = Vector3(0, 0.02, z)
		add_child(n)
		var h := {"name": it["name"], "node": n, "lane_z": z, "stage": "settle", "t": 0, "tries": 0, "destroyed": false,
			"proj": null, "debris": 0, "debris_low": 0, "speeds": [], "explosive": n is ExplosiveBarrel, "exploded": false}
		n.connect("destroyed", func() -> void: h["destroyed"] = true)
		if n is ExplosiveBarrel:
			n.tree_exited.connect(func() -> void: h["exploded"] = _explosion_on_lane(z))
		n.connect("hit", func(speed: float, dmg: float, _by: Node) -> void: h["speeds"].append([snappedf(speed, 0.1), snappedf(dmg, 0.1)]))
		hits.append(h)
	if hits.is_empty():
		_finish()


func _tick_hits() -> void:
	var all_done := true
	for h in hits:
		h["t"] += 1
		match h["stage"]:
			"settle":
				all_done = false
				if h["t"] >= SETTLE:
					_launch(h)
			"flight":
				all_done = false
				if h["destroyed"]:
					h["stage"] = "debris"
					h["t"] = 0
				elif h["t"] >= 45:
					if h["tries"] < 3:
						_launch(h)
					else:
						h["stage"] = "done"
			"debris":
				all_done = false
				if h["t"] >= 60:
					_count_debris(h)
					h["stage"] = "done"
	if all_done:
		for h in hits:
			var ok: bool = h["destroyed"] and h["debris"] >= 3 and h["debris_low"] == 0
			var why := "ok" if ok else ("не разрушился" if not h["destroyed"] else "обломков %d, под полом %d" % [h["debris"], h["debris_low"]])
			if h["explosive"]:
				ok = h["destroyed"] and h["exploded"]
				why = "ok (взрыв)" if ok else ("не разрушился" if not h["destroyed"] else "нет взрыва")
			print("hit %-30s tries=%d destroyed=%s debris=%d hits=%s  %s" % [h["name"], h["tries"], str(h["destroyed"]), h["debris"], str(h["speeds"]), why])
			_check("hit:" + h["name"], ok, {"tries": h["tries"], "destroyed": h["destroyed"], "debris": h["debris"], "debris_below_floor": h["debris_low"], "hits": h["speeds"], "exploded": h["exploded"]})
		_finish()


func _launch(h: Dictionary) -> void:
	h["tries"] += 1
	h["t"] = 0
	h["stage"] = "flight"
	if h["proj"] != null and is_instance_valid(h["proj"]):
		(h["proj"] as Node).queue_free()
	var target: Node3D = h["node"]
	var p := _box_body("Hammer_%s_%d" % [h["name"], h["tries"]], HIT_MASS, Vector3(0.4, 0.4, 0.4))
	var at := Vector3(0, 0, h["lane_z"])
	if is_instance_valid(target):
		at = target.global_position
	p.position = Vector3(at.x - 2.2, at.y + 0.45, h["lane_z"])
	add_child(p)
	p.linear_velocity = Vector3(HIT_SPEED, 0, 0)
	h["proj"] = p


func _explosion_on_lane(z: float) -> bool:
	for c in get_children():
		if c is Explosion and absf((c as Node3D).global_position.z - z) < 1.0:
			return true
	return false


func _count_debris(h: Dictionary) -> void:
	var n := 0
	var low := 0
	for d in get_tree().get_nodes_in_group("debris"):
		var b := d as Node3D
		if b == null or absf(b.global_position.z - h["lane_z"]) > 1.0:   # обломки заперты на своей глубине (±0.5 м в пропсе)
			continue
		n += 1
		if b.global_position.y < -0.1:
			low += 1
	h["debris"] = n
	h["debris_low"] = low


# ---------------------------------------------------------------- helpers
func _box_body(nm: String, mass: float, size: Vector3) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.name = nm
	b.mass = mass
	b.axis_lock_linear_z = true
	b.axis_lock_angular_x = true
	b.axis_lock_angular_y = true
	b.continuous_cd = true
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	return b


func _check(id: String, ok: bool, data: Dictionary) -> void:
	data["id"] = id
	data["ok"] = ok
	report["checks"].append(data)
	if not ok:
		report["ok"] = false


func _fail(id: String, msg: String) -> void:
	_check(id, false, {"msg": msg})


func _finish() -> void:
	var n_ok := 0
	for c in report["checks"]:
		if c["ok"]:
			n_ok += 1
	report["passed"] = n_ok
	report["total"] = report["checks"].size()
	var f := FileAccess.open("res://tests/scrap_props_probe_report.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("\nscrap_props_probe: %s (%d/%d checks)" % ["OK" if report["ok"] else "FAIL", n_ok, report["total"]])
	get_tree().quit(0 if report["ok"] else 1)
