## Builder деталей крафта (docs/plan-demo/BODY_CRAFT.md §1, §4; ASSET_PIPELINE.md, правило 2). Запуск из godot/:
##   godot --headless --path . -s res://tools/build_craft_parts.gd
## (модели — tools/blender/craft_parts.py → assets/models/body/parts/<Name>.glb, до запуска: godot --headless --path . --import).
## Для каждой детали PARTS пишет:
##   scenes/body/parts/<id>.tscn — RigidBody3D (масса PartDef, оси: linear Z / angular X,Y заблокированы, CCD, PhysicsMaterial) →
##     CollisionShape3D "Shape_<имя>" из пустышек glb Shape_<Тип>_<имя> (Box: масштаб = половины размеров; Sphere: масштаб.x = r;
##     Cyl / Capsule: масштаб = (r, h/2, r), ось Y) + instance glb как "Mesh" + Marker3D "Socket" и "Anchor_<имя>" в точках пустышек
##     glb, у якорей метаданные accepts / joint_group / rest_deg / mirror из таблицы ниже;
##   data/body/parts/<id>.tres — PartDef (kind, mass, energy, attach, body_mult, material, name_prefix, weapon_mult, scene).
## Затем пресеты крафтового оружия data/body/weapons/<id>.tres (WeaponBlueprint, PRESETS) и сцену scenes/body/crafted_weapon.tscn
## (RigidBody3D со скриптом scripts/body/crafted_weapon.gd, экспорт blueprint = молот).
## Деревянные детали куклы (wood_*) и хлам (junk_*) в тех же папках делает другой builder — этот их не трогает.
## Числа деталей (массы, энергия) живут здесь, в данных (PartDef), а не в Tuning: деталь = ресурс; Tuning читается только
## для дампа (autoload в -s режиме недоступен, tuning.gd грузится напрямую, как в build_weapon_scenes.gd).
extends SceneTree

const MODEL_DIR := "res://assets/models/body/parts/"
const SCENE_DIR := "res://scenes/body/parts/"
const PART_DIR := "res://data/body/parts/"
const WEAPON_DIR := "res://data/body/weapons/"
const CRAFTED_SCENE := "res://scenes/body/crafted_weapon.tscn"
const CRAFTED_SCRIPT := "res://scripts/body/crafted_weapon.gd"
const PART_DEF_SCRIPT := "res://scripts/body/part_def.gd"
const WEAPON_BP_SCRIPT := "res://scripts/body/weapon_blueprint.gd"
## Тонкие коллизии не должны проваливаться сквозь куклу (как MIN_THICK build_weapon_scenes.gd).
const MIN_THICK := 0.03
const ALL := ["weapon_head", "chain", "mod"]
const FREE := "Ankle"   # свободный шарнир (цепь): у группы Ankle k = 0, только трение (BODY_CRAFT.md §1)

## Детали. Энергия — CONCEPT_V2.md §6: тяжёлая рука 18, доп. сустав 5, металлическая голова 20, щит 12; оружейные детали
## энергии тела не тратят (0), цепь на теле — 8 за сегмент. body_mult = Tuning.BODY_MULT[name_prefix] (урон пока читает таблицу
## по имени, держим совпадающим). weapon_mult > 1 — у лезвий и шипов; тупая головка бьёт массой, а не множителем (§10).
## Массы: головка молота — железо 3.5, киянка (орех) 1.5, накладка +1.5, гвозди +0.4, рукоять 0.6 / 1.0, шар булавы 3.5,
## сегмент цепи 0.8; тяжёлое предплечье 3.0 (деревянное 1.5), шар-кулак 2.0 (кисть 0.5), ведро 5.0 (голова 4.0).
const PARTS := {
	"handle_short": {"glb": "Handle_Short", "title": "Рукоять короткая (0.55 м)", "kind": "handle", "mass": 0.6, "energy": 0,
		"attach": "fixed", "material": "wood", "prefix": "Handle", "weapon_mult": 1.0,
		"anchors": {"Head": {"accepts": ["weapon_head", "chain", "mod"]}, "Butt": {"accepts": ["mod", "weapon_head"]}}},
	"handle_long": {"glb": "Handle_Long", "title": "Рукоять длинная (1.1 м)", "kind": "handle", "mass": 1.0, "energy": 0,
		"attach": "fixed", "material": "wood", "prefix": "Handle", "weapon_mult": 1.0,
		"anchors": {"Head": {"accepts": ["weapon_head", "chain", "mod"]}, "Butt": {"accepts": ["mod", "weapon_head"]}}},
	"head_mallet": {"glb": "Head_Mallet", "title": "Киянка (дерево)", "kind": "weapon_head", "mass": 1.5, "energy": 0,
		"attach": "fixed", "material": "wood", "prefix": "Hammer", "weapon_mult": 1.0,
		"anchors": {"Face_L": {"accepts": ["mod"]}, "Face_R": {"accepts": ["mod"], "mirror": true}}},
	"head_hammer": {"glb": "Head_Hammer", "title": "Железная головка", "kind": "weapon_head", "mass": 3.5, "energy": 0,
		"attach": "fixed", "material": "iron", "prefix": "Hammer", "weapon_mult": 1.0,
		"anchors": {"Face_L": {"accepts": ["mod"]}, "Face_R": {"accepts": ["mod"], "mirror": true}}},
	"head_mace_ball": {"glb": "Head_Mace_Ball", "title": "Шар булавы", "kind": "weapon_head", "mass": 3.5, "energy": 0,
		"attach": "fixed", "material": "iron", "prefix": "Mace", "weapon_mult": 1.15, "anchors": {}},
	"blade_sword": {"glb": "Blade_Sword", "title": "Клинок", "kind": "weapon_head", "mass": 1.3, "energy": 0,
		"attach": "fixed", "material": "iron", "prefix": "Blade", "weapon_mult": 1.6, "anchors": {}},
	"blade_axe": {"glb": "Blade_Axe", "title": "Топор", "kind": "weapon_head", "mass": 2.2, "energy": 0,
		"attach": "fixed", "material": "iron", "prefix": "Blade", "weapon_mult": 1.3,
		"anchors": {"Back": {"accepts": ["mod"]}}},
	"hook": {"glb": "Hook", "title": "Крюк", "kind": "weapon_head", "mass": 0.7, "energy": 0,
		"attach": "fixed", "material": "iron", "prefix": "Hook", "weapon_mult": 1.2, "anchors": {}},
	"mod_nails": {"glb": "Mod_Nails", "title": "6 гвоздей", "kind": "mod", "mass": 0.4, "energy": 0,
		"attach": "fixed", "material": "iron", "prefix": "Mod", "weapon_mult": 1.25, "anchors": {}},
	"mod_iron_plate": {"glb": "Mod_Iron_Plate", "title": "Железная накладка", "kind": "mod", "mass": 1.5, "energy": 0,
		"attach": "fixed", "material": "iron", "prefix": "Mod", "weapon_mult": 1.0,
		"anchors": {"Out": {"accepts": ["mod"]}}},
	"chain_segment": {"glb": "Chain_Segment", "title": "Цепь (3 звена, 0.35 м)", "kind": "chain", "mass": 0.8, "energy": 8,
		"attach": "joint", "material": "iron", "prefix": "Chain", "weapon_mult": 1.0,
		"anchors": {"End": {"accepts": ["chain", "weapon_head", "hand", "handle"]}}},
	"metal_forearm": {"glb": "Metal_Forearm", "title": "Железное предплечье", "kind": "limb", "mass": 3.0, "energy": 18,
		"attach": "joint", "material": "iron", "prefix": "LowerArm", "weapon_mult": 1.0,
		"anchors": {"Wrist": {"accepts": ["hand", "chain", "handle", "weapon_head"], "joint_group": "Wrist"},
			"Plate": {"accepts": ["plate", "mod"], "joint_group": "Wrist"}}},
	"iron_ball_fist": {"glb": "Iron_Ball_Fist", "title": "Шар-кулак", "kind": "hand", "mass": 2.0, "energy": 8,
		"attach": "joint", "material": "iron", "prefix": "Hand", "weapon_mult": 1.0, "anchors": {}},
	"extra_joint": {"glb": "Extra_Joint", "title": "Доп. сустав", "kind": "joint", "mass": 0.5, "energy": 5,
		"attach": "joint", "material": "wood", "prefix": "Joint", "weapon_mult": 1.0,
		"anchors": {"End": {"accepts": ["limb", "hand", "foot", "joint", "chain", "handle", "weapon_head"], "joint_group": "Elbow"}}},
	"metal_head": {"glb": "Metal_Head", "title": "Голова-ведро", "kind": "head", "mass": 5.0, "energy": 20,
		"attach": "joint", "material": "iron", "prefix": "Head", "weapon_mult": 1.0,
		"anchors": {"Top": {"accepts": ["mod", "weapon_head"], "joint_group": "Neck"}}},
	"shield_plate": {"glb": "Shield_Plate", "title": "Щиток", "kind": "plate", "mass": 2.5, "energy": 12,
		"attach": "fixed", "material": "iron", "prefix": "Plate", "weapon_mult": 1.0, "anchors": {}},
}

## Пресеты крафтового оружия (BODY_CRAFT.md §4): корень — рукоять, uid по одному символу. Моды — на Face_R: при махе по часовой
## стрелке это передний боёк (tests/craft_probe.gd). concept_hammer — пример из CONCEPT_V2.md §9: деревянный молот + накладка +
## гвозди поверх накладки + длинная рукоять.
const PRESETS := {
	"mallet": {"title": "Киянка", "nodes": [["0", "handle_short", "", ""], ["1", "head_mallet", "0", "Anchor_Head"]]},
	"hammer": {"title": "Молот", "nodes": [["0", "handle_short", "", ""], ["1", "head_hammer", "0", "Anchor_Head"]]},
	"spiked_hammer": {"title": "Молот с гвоздями", "nodes": [["0", "handle_short", "", ""], ["1", "head_hammer", "0", "Anchor_Head"],
		["2", "mod_nails", "1", "Anchor_Face_R"]]},
	"heavy_hammer": {"title": "Тяжёлый молот", "nodes": [["0", "handle_short", "", ""], ["1", "head_hammer", "0", "Anchor_Head"],
		["2", "mod_iron_plate", "1", "Anchor_Face_R"]]},
	"long_hammer": {"title": "Длинный молот", "nodes": [["0", "handle_long", "", ""], ["1", "head_hammer", "0", "Anchor_Head"]]},
	"flail": {"title": "Кистень", "nodes": [["0", "handle_short", "", ""], ["1", "chain_segment", "0", "Anchor_Head"],
		["2", "chain_segment", "1", "Anchor_End"], ["3", "chain_segment", "2", "Anchor_End"], ["4", "head_mace_ball", "3", "Anchor_End"]]},
	"sword": {"title": "Меч", "nodes": [["0", "handle_short", "", ""], ["1", "blade_sword", "0", "Anchor_Head"]]},
	"axe": {"title": "Топор", "nodes": [["0", "handle_long", "", ""], ["1", "blade_axe", "0", "Anchor_Head"]]},
	"concept_hammer": {"title": "Молот концепта", "nodes": [["0", "handle_long", "", ""], ["1", "head_mallet", "0", "Anchor_Head"],
		["2", "mod_iron_plate", "1", "Anchor_Face_R"], ["3", "mod_nails", "2", "Anchor_Out"]]},
}

var tuning


func _init() -> void:
	tuning = load("res://scripts/tuning.gd").new()
	for d in [SCENE_DIR, PART_DIR, WEAPON_DIR]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))
	var failed := 0
	for id in PARTS:
		if not _build_part(id):
			failed += 1
	for id in PRESETS:
		if not _save_preset(id):
			failed += 1
	if not _save_crafted_scene():
		failed += 1
	print("=== build_craft_parts: parts %d, presets %d, failed %d ===" % [PARTS.size(), PRESETS.size(), failed])
	tuning.free()
	quit(1 if failed > 0 else 0)


func _pascal(id: String) -> String:
	var out := ""
	for w in id.split("_"):
		out += w.capitalize()
	return out


func _build_part(id: String) -> bool:
	var e: Dictionary = PARTS[id]
	var glb_path: String = MODEL_DIR + String(e["glb"]) + ".glb"
	var model_scene := load(glb_path) as PackedScene
	if model_scene == null:
		push_error("build_craft_parts: model not imported: %s (run `godot --headless --path . --import`)" % glb_path)
		return false
	var probe: Node3D = model_scene.instantiate()
	var root := RigidBody3D.new()
	root.name = _pascal(id)
	root.mass = float(e["mass"])
	root.axis_lock_linear_z = true
	root.axis_lock_angular_x = true
	root.axis_lock_angular_y = true
	root.continuous_cd = true
	root.can_sleep = false
	root.linear_damp = tuning.LINEAR_DAMP
	root.angular_damp = tuning.ANGULAR_DAMP
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	pm.bounce = 0.05 if e["kind"] in ["limb", "hand", "joint", "head", "foot"] else 0.1
	root.physics_material_override = pm
	root.set_meta("part_id", id)
	root.set_meta("kind", String(e["kind"]))

	var shapes := 0
	var socket_found := false
	var anchors_found: Array = []
	for c in probe.get_children():
		var n := String(c.name)
		var t: Transform3D = (c as Node3D).transform
		if n.begins_with("Shape_"):
			var cs := _shape_from(n, t)
			if cs == null:
				push_error("build_craft_parts: %s: bad shape node %s" % [id, n])
				probe.free()
				root.free()
				return false
			root.add_child(cs)
			cs.owner = root
			shapes += 1
		elif n == "Socket" or n.begins_with("Anchor_"):
			var mk := Marker3D.new()
			mk.name = n
			mk.transform = Transform3D(t.basis.orthonormalized(), t.origin)
			if n == "Socket":
				socket_found = true
			else:
				var short := n.substr(7)
				var a: Dictionary = (e["anchors"] as Dictionary).get(short, {})
				if a.is_empty():
					push_error("build_craft_parts: %s: anchor %s has no metadata in PARTS" % [id, n])
					probe.free()
					root.free()
					return false
				mk.set_meta("accepts", PackedStringArray(a.get("accepts", ALL)))
				mk.set_meta("joint_group", String(a.get("joint_group", FREE)))
				mk.set_meta("rest_deg", float(a.get("rest_deg", 0.0)))
				mk.set_meta("mirror", bool(a.get("mirror", false)))
				anchors_found.append(short)
			root.add_child(mk)
			mk.owner = root
	probe.free()
	for short in (e["anchors"] as Dictionary).keys():
		if not anchors_found.has(short):
			push_error("build_craft_parts: %s: anchor Anchor_%s from PARTS not found in %s" % [id, short, glb_path])
			root.free()
			return false
	if not socket_found or shapes == 0:
		push_error("build_craft_parts: %s: socket %s, shapes %d" % [id, str(socket_found), shapes])
		root.free()
		return false

	var mesh: Node3D = model_scene.instantiate()
	mesh.name = "Mesh"
	mesh.set_meta("rig_mesh", true)   # doll.gd прячет меши с этой меткой, если на куклу надет внешний скин
	root.add_child(mesh)
	mesh.owner = root   # instance целиком: внутренние узлы (и пустышки glb) принадлежат glb-сцене

	var packed := PackedScene.new()
	var err := packed.pack(root)
	root.free()
	if err != OK:
		push_error("build_craft_parts: pack failed for %s: %d" % [id, err])
		return false
	var scene_path := SCENE_DIR + id + ".tscn"
	err = ResourceSaver.save(packed, scene_path)
	if err != OK:
		push_error("build_craft_parts: save failed %s: %d" % [scene_path, err])
		return false

	var def: Resource = load(PART_DEF_SCRIPT).new()
	def.set("id", id)
	def.set("title", String(e["title"]))
	def.set("kind", String(e["kind"]))
	def.set("scene", ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE))
	def.set("mass", float(e["mass"]))
	def.set("energy", int(e["energy"]))
	def.set("attach", String(e["attach"]))
	def.set("body_mult", float(tuning.BODY_MULT.get(String(e["prefix"]), 1.0)))
	def.set("material", String(e["material"]))
	def.set("name_prefix", String(e["prefix"]))
	def.set("weapon_mult", float(e["weapon_mult"]))
	var def_path := PART_DIR + id + ".tres"
	err = ResourceSaver.save(def, def_path)
	if err != OK:
		push_error("build_craft_parts: save failed %s: %d" % [def_path, err])
		return false
	print("part %-15s %-11s %4.1f kg  E%-2d %-5s shapes %d anchors %s" % [id, e["kind"], e["mass"], e["energy"], e["attach"], shapes, str(anchors_found)])
	return true


## Пустышка glb Shape_<Тип>_<имя> → CollisionShape3D "Shape_<имя>" (размеры — из масштаба пустышки).
func _shape_from(node_name: String, t: Transform3D) -> CollisionShape3D:
	var bits := node_name.split("_")
	if bits.size() < 3:
		return null
	var kind := bits[1]
	var sc := t.basis.get_scale()
	var cs := CollisionShape3D.new()
	cs.name = "Shape_" + "_".join(bits.slice(2))
	match kind:
		"Box":
			var b := BoxShape3D.new()
			b.size = Vector3(maxf(2.0 * sc.x, MIN_THICK), maxf(2.0 * sc.y, MIN_THICK), maxf(2.0 * sc.z, MIN_THICK))
			cs.shape = b
		"Sphere":
			var s := SphereShape3D.new()
			s.radius = sc.x
			cs.shape = s
		"Cyl":
			var cy := CylinderShape3D.new()
			cy.radius = sc.x
			cy.height = 2.0 * sc.y
			cs.shape = cy
		"Capsule":
			var ca := CapsuleShape3D.new()
			ca.radius = sc.x
			ca.height = maxf(2.0 * sc.y, 2.0 * sc.x)
			cs.shape = ca
		_:
			cs.free()
			return null
	cs.transform = Transform3D(t.basis.orthonormalized(), t.origin)
	return cs


func _save_preset(id: String) -> bool:
	var e: Dictionary = PRESETS[id]
	var bp: Resource = load(WEAPON_BP_SCRIPT).new()
	bp.set("id", id)
	bp.set("title", String(e["title"]))
	var nodes: Array[Dictionary] = []
	for n in e["nodes"]:
		nodes.append({"uid": String(n[0]), "part": String(n[1]), "parent": String(n[2]), "anchor": String(n[3])})
	bp.set("nodes", nodes)
	var errors: PackedStringArray = bp.call("validate")
	if not errors.is_empty():
		push_error("build_craft_parts: preset %s invalid: %s" % [id, str(errors)])
		return false
	var path := WEAPON_DIR + id + ".tres"
	var err := ResourceSaver.save(bp, path)
	if err != OK:
		push_error("build_craft_parts: save failed %s: %d" % [path, err])
		return false
	print("preset %-15s %d parts" % [id, nodes.size()])
	return true


## crafted_weapon.tscn: пустое тело оружия со скриптом CraftedWeapon (детали собираются из blueprint в рантайме —
## исключение из правила 2, CONCEPT_V2.md «Следствия для кода»). Физика — как у сцен weapon_<id>.tscn.
func _save_crafted_scene() -> bool:
	var root := RigidBody3D.new()
	root.name = "CraftedWeapon"
	root.set_script(load(CRAFTED_SCRIPT))
	root.set("weapon_id", "craft_hammer")
	root.set("grip_local", Vector3.ZERO)
	root.set("blueprint", ResourceLoader.load(WEAPON_DIR + "hammer.tres", "", ResourceLoader.CACHE_MODE_REPLACE))
	root.mass = 1.0   # пересчитывается при сборке: сумма масс слитых деталей
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
	var packed := PackedScene.new()
	var err := packed.pack(root)
	root.free()
	if err != OK:
		return false
	err = ResourceSaver.save(packed, CRAFTED_SCENE)
	if err != OK:
		push_error("build_craft_parts: save failed %s: %d" % [CRAFTED_SCENE, err])
		return false
	print("saved %s" % CRAFTED_SCENE)
	return true
