## Builder сцен оружия (ASSET_PIPELINE.md, правило 2). Запуск из godot/:
##   godot --headless --path . -s res://tools/build_weapon_scenes.gd [-- hammer mace ...]
## Для каждого id пишет res://scenes/weapons/weapon_<id>.tscn:
##   RigidBody3D (script weapon.gd, масса из Tuning.WEAPON, оси: linear Z / angular X,Y заблокированы, CCD,
##   PhysicsMaterial friction 0.6) → CollisionShape3D "Col_Handle" / "Col_Head" (/Guard) + instance модели
##   assets/models/weapons/<id>.glb как "Model" в точке хвата (origin модели = хват).
## Размеры коллизий — из DIMS tools/blender/weapons.py (Blender x→x, z→y, −y→z), продублированы здесь:
## после изменения геометрии в Blender править обе таблицы. Autoload Tuning в -s режиме недоступен,
## поэтому tuning.gd грузится напрямую.
extends SceneTree

const IDS := ["hammer", "mace", "sword", "axe", "pan"]
const SCENE_DIR := "res://scenes/weapons/"
const MODEL_DIR := "res://assets/models/weapons/"
const SCRIPT_PATH := "res://scenes/weapons/weapon.gd"
## Тонкие лезвия не должны проваливаться сквозь куклу: минимальная толщина коробки по каждой оси.
const MIN_THICK := 0.03

## id → список коллизий: {name, type: box|sphere|cylinder, pos, size|radius|height, rot_deg (Vector3, опц.)}.
## Godot-координаты (x вдоль оружия от хвата, y вверх на экране, z к камере).
const SHAPES := {
	"hammer": [
		{"name": "Handle", "type": "box", "pos": Vector3(0.2875, 0, 0), "size": Vector3(0.745, 0.068, 0.068)},
		{"name": "Head", "type": "cylinder", "pos": Vector3(0.80, 0, 0), "radius": 0.16, "height": 0.40},   # ось бочки = Y
	],
	"mace": [
		{"name": "Handle", "type": "box", "pos": Vector3(0.1585, 0, 0), "size": Vector3(0.603, 0.06, 0.06)},
		{"name": "Head", "type": "sphere", "pos": Vector3(0.62, 0, 0), "radius": 0.16},                     # шар 0.12 + полшипа
	],
	"sword": [
		{"name": "Handle", "type": "box", "pos": Vector3(-0.027, 0, 0), "size": Vector3(0.178, 0.056, 0.056)},
		{"name": "Guard", "type": "box", "pos": Vector3(0.077, 0, 0), "size": Vector3(0.03, 0.235, 0.03)},
		{"name": "Head", "type": "box", "pos": Vector3(0.451, 0, 0), "size": Vector3(0.718, 0.076, 0.03)},
	],
	"axe": [
		{"name": "Handle", "type": "box", "pos": Vector3(0.35, 0, 0), "size": Vector3(0.90, 0.054, 0.054)},
		{"name": "Head", "type": "box", "pos": Vector3(0.64, -0.1315, 0), "size": Vector3(0.34, 0.387, 0.05)},   # кромка вниз (−Y)
	],
	"pan": [
		{"name": "Handle", "type": "box", "pos": Vector3(0.134, 0, 0), "size": Vector3(0.452, 0.064, 0.03)},
		{"name": "Head", "type": "cylinder", "pos": Vector3(0.53, 0, -0.003), "radius": 0.18, "height": 0.066, "rot_deg": Vector3(90, 0, 0)},   # диск в плоскости экрана
	],
}


func _init() -> void:
	var tuning = load("res://scripts/tuning.gd").new()
	var script: Script = load(SCRIPT_PATH)
	var ids: Array = []
	for a in OS.get_cmdline_user_args():
		for id in a.split(","):
			if id in IDS:
				ids.append(id)
	if ids.is_empty():
		ids = IDS
	var failed := 0
	for id in ids:
		if not _build(id, tuning, script):
			failed += 1
	print("=== build_weapon_scenes: %d/%d ok ===" % [ids.size() - failed, ids.size()])
	quit(1 if failed > 0 else 0)


func _build(id: String, tuning, script: Script) -> bool:
	var entry: Dictionary = tuning.WEAPON.get(id, {})
	if entry.is_empty():
		push_error("build_weapon_scenes: no Tuning.WEAPON entry for '%s'" % id)
		return false
	var model_scene: PackedScene = load(MODEL_DIR + id + ".glb")
	if model_scene == null:
		push_error("build_weapon_scenes: model not imported: %s%s.glb (run `godot --headless --path . --import` first)" % [MODEL_DIR, id])
		return false

	var root := RigidBody3D.new()
	root.name = "Weapon" + id.capitalize()
	root.set_script(script)
	root.set("weapon_id", id)
	root.set("grip_local", Vector3.ZERO)
	root.mass = float(entry["mass"])
	root.axis_lock_linear_z = true
	root.axis_lock_angular_x = true
	root.axis_lock_angular_y = true
	root.continuous_cd = true
	root.linear_damp = tuning.LINEAR_DAMP
	root.angular_damp = tuning.ANGULAR_DAMP
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	pm.bounce = 0.1
	root.physics_material_override = pm

	for s in SHAPES[id]:
		var cs := CollisionShape3D.new()
		cs.name = "Col_" + s["name"]
		match s["type"]:
			"box":
				var b := BoxShape3D.new()
				b.size = Vector3(maxf(s["size"].x, MIN_THICK), maxf(s["size"].y, MIN_THICK), maxf(s["size"].z, MIN_THICK))
				cs.shape = b
			"sphere":
				var sp := SphereShape3D.new()
				sp.radius = s["radius"]
				cs.shape = sp
			"cylinder":
				var cy := CylinderShape3D.new()
				cy.radius = s["radius"]
				cy.height = s["height"]
				cs.shape = cy
		var rot: Vector3 = s.get("rot_deg", Vector3.ZERO)
		cs.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z))), s["pos"])
		root.add_child(cs)
		cs.owner = root

	var model: Node3D = model_scene.instantiate()
	model.name = "Model"
	root.add_child(model)
	model.owner = root   # instance целиком: внутренние узлы принадлежат glb-сцене

	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("build_weapon_scenes: pack failed for %s: %d" % [id, err])
		return false
	var path := SCENE_DIR + "weapon_" + id + ".tscn"
	err = ResourceSaver.save(packed, path)
	if err != OK:
		push_error("build_weapon_scenes: save failed for %s: %d" % [path, err])
		return false
	print("saved %s (mass %.1f kg, %d shapes)" % [path, root.mass, SHAPES[id].size()])
	root.free()
	return true
