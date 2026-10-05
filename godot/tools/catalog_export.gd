## Каталог элементов игры (docs/catalog/index.html): характеристики всех деталей, материалов, шарниров, активных блоков, оружия,
## бойцов и врагов → <out>/catalog.json, сырые кадры каждого элемента (детали кита — в каждом материале) → <out>/raw/**.png.
## Страницу и сжатые картинки из этого собирает tools/build_catalog.py. Нужно окно (headless не рендерит), из корня репозитория:
##   godot/tools/godot_nofocus.sh --path godot --resolution 640x360 res://tools/catalog_export.tscn -- lang=ru out=/абс/папка
##   python3 godot/tools/build_catalog.py /абс/папка
## Аргументы: out — папка вывода (обязательно); only=parts,materials,joints,weapons,fighters,enemies — только эти разделы кадров
## (данные пишутся все); mats=0 — без кадров деталей в чужих материалах.
## Кадр — как иконки мастерской (scenes/workshop/part_icons.gd): ортокамера спереди с поворотом 3/4, тёплый ключевой свет и холодная
## подсветка, прозрачный фон; цвета в PNG умножены на альфу (так рисует вьюпорт) — build_catalog.py делит обратно.
## В stdout — «=== CATALOG EXPORT === {json}» (счётчики, ошибки); код выхода 1 при ошибках.
extends Node

const PARTS_DIR := "res://data/body/parts/"
const BP_DIR := "res://data/body/blueprints/"
const PRESET_DIR := "res://scenes/body/presets/"
const MODULAR_SCENE := "res://scenes/body/modular_doll.tscn"
const ENEMY_DIR := "res://scenes/enemies/"
const ENEMIES := ["enemy_scrapling", "enemy_sweeper"]
## Готовое оружие арены (scenes/weapons/weapon_<id>.tscn, числа — Tuning.WEAPON): подписи для каталога.
const WEAPON_TITLES := {"hammer": "Молот", "mace": "Булава", "sword": "Меч", "axe": "Топор", "pan": "Сковорода"}
const YAW := -18.0
const PITCH := 8.0
const MARGIN := 1.12
const PART_PX := 512        # сырой кадр детали (страница показывает вдвое меньше)
const BIG_PX := 900         # бойцы, враги, оружие

var _vp: SubViewport
var _rig: Node3D
var _cam: Camera3D
var _stage: Node3D
var _out := ""
var _only: PackedStringArray = []
var _mat_shots := true
var _shots := 0
var _errors: PackedStringArray = []


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		for kv in String(a).split(" ", false):
			var p := kv.split("=", true, 1)
			args[p[0]] = p[1] if p.size() > 1 else "1"
	_out = String(args.get("out", "")).trim_suffix("/")
	if _out == "":
		push_error("catalog_export: нужен аргумент out=/абс/папка")
		get_tree().quit(1)
		return
	_only = String(args.get("only", "")).split(",", false)
	_mat_shots = String(args.get("mats", "1")) != "0"
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_studio()
	var data := {
		"tuning": {
			"BODY_MULT": Tuning.BODY_MULT, "HEAD_HIT_MULT": Tuning.HEAD_HIT_MULT, "HAND_HIT_MULT": Tuning.HAND_HIT_MULT,
			"SHAPE_MULT_MAX": Tuning.SHAPE_MULT_MAX, "SHAPE_SLOW_V": Tuning.SHAPE_SLOW_V, "SHAPE_FAST_V": Tuning.SHAPE_FAST_V,
			"MAX_HP": Tuning.MAX_HP, "ENERGY_BUDGET": BodyBlueprint.new().energy_budget,
			"ENERGY_REACH_FREE_M": BodyBlueprint.ENERGY_REACH_FREE_M, "ENERGY_REACH_PER_M": BodyBlueprint.ENERGY_REACH_PER_M,
			"PULL_ENERGY": BodyBlueprint.PULL_ENERGY, "MAX_PULLS": BodyBlueprint.MAX_PULLS,
			"CHARGE_MAX": ActiveBlocks.CHARGE_MAX, "CHARGE_REGEN": ActiveBlocks.CHARGE_REGEN,
			"CHARGE_PER_DEALT": ActiveBlocks.CHARGE_PER_DEALT, "CHARGE_PER_TAKEN": ActiveBlocks.CHARGE_PER_TAKEN,
			"CHANNEL_KEYS": ActiveBlocks.KEY_LABELS,
			"ARMOR_MAX": Tuning.ARMOR_MAX, "PART_BREAK": Tuning.PART_BREAK, "PART_INTEGRITY": Tuning.PART_INTEGRITY,
			"ARMOR_INTEGRITY_BONUS": Tuning.ARMOR_INTEGRITY_BONUS,
		},
	}
	data["materials"] = await _materials()
	data["joints"] = await _joints()
	data["parts"] = await _parts()
	data["weapons"] = await _weapons()
	data["fighters"] = await _fighters()
	data["enemies"] = await _enemies()
	var f := FileAccess.open(_out + "/catalog.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	print("=== CATALOG EXPORT === ", JSON.stringify({"parts": data["parts"].size(), "materials": data["materials"].size(),
		"joints": data["joints"].size(), "weapons": data["weapons"].size(), "fighters": data["fighters"].size(),
		"enemies": data["enemies"].size(), "shots": _shots, "errors": _errors}))
	get_tree().quit(1 if not _errors.is_empty() else 0)


func _wants(section: String) -> bool:
	return _only.is_empty() or _only.has(section)


# ------------------------------------------------------------------ студия

func _studio() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(PART_PX, PART_PX)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.7, 0.6)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_rig = Node3D.new()
	_vp.add_child(_rig)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.environment = env
	_rig.add_child(_cam)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -40, 0)
	key.light_energy = 1.5
	key.light_color = Color(1.0, 0.88, 0.72)
	_rig.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 150, 0)
	rim.light_energy = 0.55
	rim.light_color = Color(0.62, 0.74, 1.0)
	_rig.add_child(rim)
	_stage = Node3D.new()
	_vp.add_child(_stage)


func _clear_stage() -> void:
	for c in _stage.get_children():
		_stage.remove_child(c)
		c.queue_free()


## Кадр того, что стоит на сцене: камера обходит объект (yaw / pitch — как поворот детали в PartIcons), рамка — по габариту.
func _snap(rel: String, px: int, yaw: float = YAW, pitch: float = PITCH, frames: int = 2) -> void:
	_vp.size = Vector2i(px, px)
	_rig.basis = Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0)).inverse()
	var box := PartIcons._visual_aabb(_stage, _rig.global_transform.affine_inverse())
	var c := box.get_center()
	_cam.size = maxf(maxf(box.size.x, box.size.y) * MARGIN, 0.05)
	_cam.position = Vector3(c.x, c.y, box.end.z + 2.0)
	_cam.near = 0.05
	_cam.far = box.size.z + 6.0
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for i in range(frames):
		await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var path := _out + "/raw/" + rel
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if img == null or img.is_empty() or img.save_png(path) != OK:
		_errors.append("кадр не записан: " + rel)
		return
	_shots += 1


static func _meshes(n: Node) -> Array:
	var out: Array = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		out.append(n)
	return out


## Поверхности Base_* → surface (как ModularDoll._swap_base_surfaces; null — вернуть материал детали). Сколько поверхностей сменили.
static func _swap_base(n: Node, surface: Material) -> int:
	var cnt := 0
	for m in _meshes(n):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var cur := mi.mesh.surface_get_material(s)
			if cur != null and cur.resource_name.begins_with("Base_"):
				mi.set_surface_override_material(s, surface)
				cnt += 1
	return cnt


static func _r(v: float, step: float = 0.001) -> float:
	return snappedf(v, step)


# ------------------------------------------------------------------ материалы и шарниры

func _materials() -> Array:
	var out: Array = []
	for id in MaterialDef.all_ids():
		var m := MaterialDef.get_def(id)
		out.append({"id": id, "title": m.title, "density": _r(m.density), "friction": _r(m.friction), "bounce": _r(m.bounce),
			"body_mult": _r(m.body_mult), "iron": m.iron, "swatch": "#" + m.swatch.to_html(false),
			"durability": float(Tuning.MAT_DURABILITY.get(id, 0.5))})
		if not _wants("materials"):
			continue
		_clear_stage()
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.25
		sm.height = 0.5
		sm.radial_segments = 96
		sm.rings = 48
		ball.mesh = sm
		var mat := m.surface.duplicate() as Material
		if mat is BaseMaterial3D:
			(mat as BaseMaterial3D).uv1_scale = Vector3(3.0, 1.5, 1.0)   # текстуры кита — 2 тайла на метр
		ball.material_override = mat
		_stage.add_child(ball)
		await _snap("materials/%s.png" % id, PART_PX, -30.0, 10.0, 3)
	return out


func _joints() -> Array:
	var out: Array = []
	for t in KitJoint.ORDER:
		var info := KitJoint.info(t)
		var lim: Variant = info.get("limits", "")
		var e := {"id": t, "title": KitJoint.title_of(t), "hint": KitJoint.hint_of(t), "energy": KitJoint.energy_of(t),
			"weld": KitJoint.is_weld(t), "k": info.get("k", null), "tmax": info.get("tmax", null), "friction": info.get("friction", null),
			"limits": [lim.x, lim.y] if lim is Vector2 else String(lim), "image": false}
		var path := KitJoint.connector_scene(t)
		if path != "" and ResourceLoader.exists(path):
			e["image"] = true
			if _wants("joints"):
				_clear_stage()
				_stage.add_child((load(path) as PackedScene).instantiate())
				await _snap("joints/%s.png" % t, PART_PX, -24.0, 14.0, 3)
		out.append(e)
	return out


# ------------------------------------------------------------------ детали

## Меш детали на своём узле-опоре (узел Mesh сцены, Mesh_R — нет); нет узла Mesh — вся сцена детали с выключенной физикой.
func _part_visual(d: PartDef) -> Node3D:
	var inst := d.scene.instantiate() as Node3D
	var mesh := inst.get_node_or_null("Mesh") as Node3D
	if mesh == null:
		inst.process_mode = Node.PROCESS_MODE_DISABLED
		return inst
	var xf := mesh.transform
	inst.remove_child(mesh)
	mesh.owner = null
	inst.free()
	var pivot := Node3D.new()
	pivot.add_child(mesh)
	mesh.transform = xf
	return pivot


func _parts() -> Array:
	var out: Array = []
	var files := Array(DirAccess.get_files_at(PARTS_DIR))
	files.sort()
	var mats := MaterialDef.all_ids()
	for f in files:
		var fn := String(f).trim_suffix(".remap")
		if not fn.ends_with(".tres"):
			continue
		var d := load(PARTS_DIR + fn) as PartDef
		if d == null or not d.is_valid():
			_errors.append("деталь не грузится: " + fn)
			continue
		var fixed := BodyBlueprint.is_fixed_part(d)
		var anchors: Array = []
		var info := BodyBlueprint.part_anchors(d)
		var names := info.keys()
		names.sort()
		for a in names:
			var ai: Dictionary = info[a]
			anchors.append({"name": String(a).trim_prefix("Anchor_"), "accepts": ai.get("accepts", []), "group": String(ai.get("joint_group", ""))})
		var e := {
			"id": d.id, "name": PartNames.of(d), "title": d.title, "kind": d.kind, "kind_title": CraftEdit.kind_title(d.kind),
			"mass": _r(d.mass), "energy": d.energy, "attach": d.attach, "fixed": fixed, "body_mult": _r(d.body_mult),
			"hit_mult": _r(d.hit_mult), "hit_profile": d.hit_profile, "material": d.material, "name_prefix": d.name_prefix,
			"weapon_mult": _r(d.weapon_mult), "base_mat": d.base_mat, "connector": d.connector,
			"length": _r(CraftEdit.part_length(d)), "desc": CraftEdit.part_desc(d), "anchors": anchors,
			"hidden": CraftEdit.SHELF_HIDDEN_PREFIXES.any(func(p: String) -> bool: return d.id.begins_with(p)),
			"durability": _r(CraftEdit.part_durability(d), 0.01), "armor": _r(Damage.part_armor(d.id), 0.01), "variants": [],
		}
		if ActiveBlocks.is_active(d.id):
			var ad := ActiveBlocks.def_of(d.id).duplicate()
			for k in ["nozzles", "muzzle"]:
				ad.erase(k)
			ad["title"] = ActiveBlocks.title_of(d.id)
			ad["hint"] = ActiveBlocks.hint_of(d.id)
			e["active"] = ad
		if ActiveBlocks.PASSIVE.has(d.id):
			var pd: Dictionary = (ActiveBlocks.PASSIVE[d.id] as Dictionary).duplicate()
			pd["hint"] = ActiveBlocks.passive_hint(d.id)
			e["passive"] = pd
		_clear_stage()
		var vis := _part_visual(d)
		_stage.add_child(vis)
		var box := PartIcons._visual_aabb(vis, Transform3D.IDENTITY)
		e["size"] = [_r(box.size.x, 0.01), _r(box.size.y, 0.01), _r(box.size.z, 0.01)]
		if _wants("parts"):
			await _snap("parts/%s.png" % d.id, PART_PX)
		# деталь кита в каждом материале оси материалов (BODY_KIT.md §4); кадр в своём материале уже есть
		if d.base_mat != "":
			for m in mats:
				if m == d.base_mat:
					continue
				if _swap_base(vis, MaterialDef.get_def(m).surface) == 0:
					break
				e["variants"].append(m)
				if _wants("parts") and _mat_shots:
					await _snap("parts/%s__%s.png" % [d.id, m], PART_PX, YAW, PITCH, 1)
		out.append(e)
	return out


# ------------------------------------------------------------------ оружие

func _weapons() -> Array:
	var out: Array = []
	for id in Weapon.IDS:
		var ps := load(Weapon.scene_path(id)) as PackedScene
		if ps == null:
			_errors.append("нет сцены оружия: " + id)
			continue
		var w := ps.instantiate() as Weapon
		w.process_mode = Node.PROCESS_MODE_DISABLED
		_clear_stage()
		_stage.add_child(w)
		w.rotation_degrees = Vector3(0, 0, 55)
		var t: Dictionary = Tuning.WEAPON.get(id, {})
		out.append({"id": "weapon_" + id, "group": "arena", "title": tr(String(WEAPON_TITLES.get(id, id))), "mass": _r(w.mass),
			"damage_mult": _r(float(t.get("damage_mult", 1.0))), "length": _r(float(t.get("length", 0.0))), "parts": []})
		if _wants("weapons"):
			await _snap("weapons/weapon_%s.png" % id, BIG_PX, -14.0, 6.0, 3)
	for id in CraftEdit.WEAPON_PRESETS:
		var bp := CraftedWeapon.preset(id)
		if bp == null:
			_errors.append("нет чертежа оружия: " + id)
			continue
		var w := CraftedWeapon.create(bp)
		_clear_stage()
		_stage.add_child(w)
		w.process_mode = Node.PROCESS_MODE_DISABLED
		w.rotation_degrees = Vector3(0, 0, 55)
		var s := w.summary()
		var parts: Array = []
		for n in bp.nodes:
			parts.append(String(n.get("part", "")))
		out.append({"id": "craft_" + id, "group": "craft", "title": bp.title, "mass": _r(float(s["mass"])),
			"damage_mult": _r(float(s["damage_mult"])), "length": _r(float(s["length"])), "bodies": int(s["bodies"]), "parts": parts,
			"errors": s["errors"]})
		if _wants("weapons"):
			await _snap("weapons/craft_%s.png" % id, BIG_PX, -14.0, 6.0, 3)
	return out


# ------------------------------------------------------------------ бойцы и враги

func _doll_entry(d: ModularDoll, id: String) -> Dictionary:
	var bp := d.blueprint
	var nodes: Array = []
	for n in bp.sorted_nodes():
		var uid := String(n.get("uid", ""))
		nodes.append({"part": String(n.get("part", "")), "mat": bp.node_mat(uid), "joint": bp.joint_type_of(uid) if String(n.get("parent", "")) != "" else "",
			"channel": ActiveBlocks.channel_of(n), "pull": bp.pull_button(uid), "body": bp.body_name_of(uid) if not bp.is_fixed(uid) else ""})
	var e := {"id": id, "title": bp.title, "energy": bp.energy_used(), "budget": bp.energy_budget, "mass": _r(bp.total_mass(), 0.1),
		"max_hp": _r(d.max_hp, 0.1), "nodes": nodes, "pulls": bp.control.size(), "errors": Array(d.build_errors)}
	if bp.weapon is WeaponBlueprint:
		e["weapon"] = (bp.weapon as WeaponBlueprint).title
		e["weapon_mass"] = _r(bp.weapon_mass(), 0.1)
	return e


func _spawn_doll(scene_path: String, bp_path: String, player: int) -> ModularDoll:
	var ps := load(scene_path if ResourceLoader.exists(scene_path) else MODULAR_SCENE) as PackedScene
	var d := ps.instantiate() as ModularDoll
	if d == null:
		return null
	if d.blueprint == null and ResourceLoader.exists(bp_path):
		d.blueprint = load(bp_path) as BodyBlueprint
	if d.blueprint == null:
		d.free()
		return null
	d.external_input = true
	if player >= 0:
		d.player_index = player
	_clear_stage()
	_stage.add_child(d)
	d.process_mode = Node.PROCESS_MODE_DISABLED   # поза спавна: физика куклу не трогает
	for bar in d.find_children("ChargeBar", "", true, false):   # полоска заряда ActiveRig — интерфейс боя, не тело
		(bar as Node3D).visible = false
	return d


func _fighters() -> Array:
	var out: Array = []
	for id in CraftEdit.BODY_PRESETS:
		var d := _spawn_doll(PRESET_DIR + id + ".tscn", BP_DIR + id + ".tres", 0)
		if d == null:
			_errors.append("боец не собран: " + id)
			continue
		var e := _doll_entry(d, id)
		e["league"] = String(id).begins_with("league_")
		out.append(e)
		if _wants("fighters"):
			await _snap("fighters/%s.png" % id, BIG_PX, -14.0, 5.0, 4)
	return out


func _enemies() -> Array:
	var out: Array = []
	for id in ENEMIES:
		var d := _spawn_doll(ENEMY_DIR + id + ".tscn", "", -1)
		if d == null:
			_errors.append("враг не собран: " + id)
			continue
		out.append(_doll_entry(d, id))
		if _wants("enemies"):
			await _snap("enemies/%s.png" % id, BIG_PX, -14.0, 5.0, 4)
	return out
