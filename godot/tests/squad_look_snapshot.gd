## Вид бойцов стычки по классам (scripts/squad/squad_look.gd): кадр и проверки «физика та же».
##   godot/tools/godot_nofocus.sh --path godot --resolution 1600x900 res://tests/squad_look_snapshot.tscn -- "out_dir=/abs/dir"
##   headless (--headless) — только проверки, кадров нет.
## Сетка замороженных бойцов SquadPlayground.make_fighter (без мозгов и стволов; скрипт площадки не собрался — та же сборка здесь):
## столбцы — «Человек» без вида, громила, снайпер, налётчик; ряды — синие сверху, красные снизу. Цвет команды — как SquadMatch._dress
## (рубашка + обводка). Кадры: out_dir/squad_look_close.png (крупно) и squad_look_far.png (кадр высотой FAR_FRAME_M — как в бою).
## Печатает «squad_look_snapshot {json}»: ok и разделы
##   physics — у каждого бойца с видом масса куклы, число форм / тел / суставов и каждое тело (масса, центр масс, инерция, слои,
##     физматериал, формы) те же, что до apply и что у «Человека» без вида;
##   reapply — смена класса: хвостов прежнего вида нет (узлы — как у свежего бойца этого класса), обводка на новых мешах (refresh_outline);
##   clear — после clear исходные меши снова видны, добавленных узлов нет, число узлов — как до apply, наклейка торса перепеклась на
##     новый меш и вернулась.
## exit 1 — не ок.
extends Node3D

const PLAYGROUND := "res://scenes/squad/playground_squad.gd"
const DOLL_SCENE := "res://scenes/body/modular_doll.tscn"
const BLUEPRINT := "res://data/body/blueprints/kit_human.tres"
const CLASSES := ["", "brawler", "sniper", "raider"]   # "" — «Человек» без вида
const COL_M := 2.3
const ROW_M := 2.5
const FAR_FRAME_M := 11.0
const STICKER := {"img": "stencil:star", "size": Vector2(0.14, 0.14), "color": Color(1, 1, 1)}

var out_dir := ""
var report := {"ok": true, "fighter": "", "physics": {}, "reapply": {}, "clear": {}, "errors": []}
var dolls: Array = []   # [doll, cls, team]
var cam: Camera3D
var _sp: GDScript


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := String(a).split("=", true, 1)
		if kv.size() == 2 and kv[0] == "out_dir":
			out_dir = kv[1]
	_sp = load(PLAYGROUND) as GDScript
	if _sp != null and not _sp.can_instantiate():
		_sp = null
	report["fighter"] = "SquadPlayground.make_fighter" if _sp != null else "fallback (playground_squad.gd не собрался)"
	_environment()
	var ref := _spawn(0, Vector3(0, -50, 0))   # эталон «Человека» без вида, вне кадра
	var ref_sig := _sig(ref)
	for team in range(2):
		for c in range(CLASSES.size()):
			var cls: String = CLASSES[c]
			var i := team + 2 * c
			var d := _spawn(i, Vector3((c - 1.5) * COL_M, (1 - team) * ROW_M, 0.0))
			var before := _sig(d)
			if cls != "":
				SquadLook.apply(d, cls, team)
			var col := SquadLook.team_colour(team)
			d._recolor(d, Doll.SHIRT_MATERIAL, col)   # как SquadMatch._dress
			DollOutline.ensure(d, col)
			var after := _sig(d)
			var key := "%s_%d" % [cls if cls != "" else "plain", team]
			var same := var_to_str(after) == var_to_str(before) and var_to_str(after) == var_to_str(ref_sig)
			var pal := _palette(d, col)
			report["physics"][key] = {"same": same, "total_mass": d.total_mass, "shapes": after["shapes"],
				"look_nodes": SquadLook.added_nodes(d).size(), "outlines": DollOutline.count(d), "palette": pal}
			_check(same, "physics %s: масса / формы не как у «Человека»" % key)
			_check(int(pal["wrong"]) == 0, "palette %s: поверхности вида не в цвете команды / класса" % key)
			if cls != "":
				_check(SquadLook.added_nodes(d).size() > 0, "%s: вид не поставился" % key)
			dolls.append([d, cls, team])
	_shoot.call_deferred()


## Боец как в стычке: SquadPlayground.make_fighter (скрипт площадки собрался) или та же сборка здесь. Заморожен в позе спавна.
func _spawn(i: int, at: Vector3) -> ModularDoll:
	var d: ModularDoll
	if _sp != null:
		d = _sp.call("make_fighter", i, false) as ModularDoll
	else:
		var bp := (load(BLUEPRINT) as BodyBlueprint).duplicate(true) as BodyBlueprint
		bp.control = PackedStringArray([String(Tuning.SQUAD_GUN_HAND[i % 2])])
		bp.control_rmb = PackedStringArray()
		bp.id = "squad_%d" % i
		d = (load(DOLL_SCENE) as PackedScene).instantiate() as ModularDoll
		d.blueprint = bp
		d.name = "Bot%d" % i
		d.player_index = i
		d.input_prefix = "bot%d" % i
		d.external_input = true
		d.add_to_group("dolls")
	d.position = at
	add_child(d)
	for b in d.parts.values():
		(b as RigidBody3D).freeze = true
	return d


## Физика куклы без поз: масса, число форм / тел / суставов, у каждого тела — масса, центр масс, инерция, слои, физматериал, формы.
func _sig(d: ModularDoll) -> Dictionary:
	var parts := {}
	for bn in d.parts:
		var b := d.parts[bn] as RigidBody3D
		var shapes: Array = []
		for c in b.find_children("*", "CollisionShape3D", true, false):
			var cs := c as CollisionShape3D
			shapes.append([String(cs.name), var_to_str(cs.shape), cs.transform, cs.disabled])
		var pm := b.physics_material_override
		parts[String(bn)] = [b.mass, b.center_of_mass_mode, b.center_of_mass, b.inertia, b.collision_layer, b.collision_mask,
			[pm.friction, pm.bounce] if pm != null else [], b.linear_damp, b.angular_damp, shapes]
	return {"total_mass": d.total_mass, "shapes": d.find_children("*", "CollisionShape3D", true, false).size(),
		"bodies": d.find_children("*", "CollisionObject3D", true, false).size(),
		"joints": d.find_children("*", "Joint3D", true, false).size(), "parts": parts}


## Цвета вида: Shirt_* — цвет команды, свет (SquadLook.GLOW_ROLES) — эмиссия цвета команды, Base_* — краска класса. Счётчики и
## число поверхностей не по правилу (wrong).
func _palette(d: ModularDoll, col: Color) -> Dictionary:
	var out := {"shirt": 0, "glow": 0, "base": 0, "wrong": 0}
	var cls := SquadLook.current(d)
	var paint: MaterialDef = MaterialDef.get_def(String((SquadLook.LOOKS.get(cls, {}) as Dictionary).get("paint", "")))
	for n in SquadLook.added_nodes(d):
		for m in BodyPaint.meshes(n):
			var mi := m as MeshInstance3D
			for s in range(mi.mesh.get_surface_count()):
				var mat := mi.get_active_material(s)
				var rn := mat.resource_name if mat != null else ""
				var ok := true
				if rn.begins_with(Doll.SHIRT_MATERIAL):
					out["shirt"] += 1
					var a := (mat as BaseMaterial3D).albedo_color
					ok = Color(a.r, a.g, a.b).is_equal_approx(Color(col.r, col.g, col.b))
				elif SquadLook.GLOW_ROLES.has(rn):
					out["glow"] += 1
					ok = (mat as BaseMaterial3D).emission_enabled and (mat as BaseMaterial3D).emission.is_equal_approx(col.lightened(0.2))
				elif rn.begins_with("Base_"):
					out["base"] += 1
					ok = paint != null and mat == paint.surface
				out["wrong"] += 0 if ok else 1
	return out


func _shoot() -> void:
	for f in range(40):   # шейдеры собраны, тени и свечение улеглись
		await get_tree().process_frame
	var w := (CLASSES.size() - 1) * COL_M
	_place_cam(Vector3(0, ROW_M * 0.5 + 0.9, 0), (ROW_M + 2.4) * 0.5, w)
	await _save("squad_look_close.png")
	_place_cam(Vector3(0, ROW_M * 0.5 + 0.9, 0), FAR_FRAME_M * 0.5, 0.0)
	await _save("squad_look_far.png")
	_reapply_check()
	_clear_check()
	print("squad_look_snapshot ", JSON.stringify(report))
	get_tree().quit(0 if bool(report["ok"]) else 1)


func _place_cam(target: Vector3, half_h: float, width: float) -> void:
	if cam == null:
		cam = Camera3D.new()
		cam.fov = 30.0
		add_child(cam)
		cam.current = true
	var aspect := float(get_viewport().get_visible_rect().size.x) / maxf(float(get_viewport().get_visible_rect().size.y), 1.0)
	var h := maxf(half_h, (width * 0.5 + 1.3) / maxf(aspect, 0.1))
	var dist := h / tan(deg_to_rad(cam.fov * 0.5))
	cam.position = target + Vector3(0, 0, dist)
	cam.look_at(target)


func _save(file: String) -> void:
	for f in range(4):
		await get_tree().process_frame
	if out_dir == "" or DisplayServer.get_name() == "headless":
		return   # headless: frame_post_draw не приходит, кадра нет
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(out_dir)
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(file)
	var err := img.save_png(path) if img != null else ERR_CANT_CREATE
	_check(err == OK, "кадр %s не сохранён (%d)" % [path, err])
	print("squad_look_snapshot: %s → %s" % ["OK" if err == OK else "FAIL", path])


## Смена класса на отсчёте: громила синих → снайпер, затем налётчик; узлы — как у свежего бойца класса, обводка на всех мешах.
func _reapply_check() -> void:
	var fresh := {}
	for e in dolls:
		if String(e[1]) != "":
			fresh[String(e[1])] = _look_names(e[0])
	var d: ModularDoll = dolls[1][0]   # brawler, синие
	var before := var_to_str(_sig(d))
	for cls in ["sniper", "raider"]:
		SquadLook.apply(d, cls, 0)
		SquadLook.refresh_outline(d, SquadLook.team_colour(0))
		var names := _look_names(d)
		var bare := _meshes_without_outline(d)
		var doubled := _meshes_with_double_outline(d)
		var ok_nodes: bool = names == fresh.get(cls, [])
		var ok_sig := var_to_str(_sig(d)) == before
		report["reapply"][cls] = {"nodes_like_fresh": ok_nodes, "no_outline": bare, "double_outline": doubled,
			"physics_same": ok_sig, "current": SquadLook.current(d)}
		_check(ok_nodes, "reapply %s: узлы вида не как у свежего бойца" % cls)
		_check(bare.is_empty() and doubled.is_empty(), "reapply %s: обводка — без неё %s, двойная %s" % [cls, bare, doubled])
		_check(ok_sig and SquadLook.current(d) == cls, "reapply %s: физика или класс" % cls)


## clear: на свежем бойце каждого класса (с наклейкой на торсе) — до apply и после clear всё то же.
func _clear_check() -> void:
	for cls in ["brawler", "sniper", "raider"]:
		var d := _spawn(0, Vector3(0, -60, 0))
		var torso := d.parts["Torso"] as Node3D
		var root := torso.get_node("Mesh") as Node3D
		var st := STICKER.duplicate()
		st["xf"] = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)),
			Vector3(0, 0.0, BodyPaint.mesh_aabb(root).end.z - 0.01))
		var sticker := d.add_sticker("T", st)
		var tris0 := _tris(sticker)
		var base := _state(d)
		SquadLook.apply(d, cls, 1)
		var mid := _state(d)
		var tris1 := _tris(sticker)
		SquadLook.clear(d)
		var back := _state(d)
		var tris2 := _tris(sticker)
		var ok := back == base and SquadLook.added_nodes(d).is_empty() and SquadLook.current(d) == "" \
			and int(mid["hidden"]) > 0 and int(mid["nodes"]) > int(base["nodes"]) and tris2 == tris0
		report["clear"][cls] = {"ok": ok, "before": base, "applied": mid, "after": back, "sticker_tris": [tris0, tris1, tris2]}
		_check(ok, "clear %s: не вернулось как было" % cls)
		_check(tris0 > 0, "clear %s: наклейка на торсе не легла (проба)" % cls)


## Узлы куклы, число видимых мешей, спрятанные видом, — для clear.
func _state(d: ModularDoll) -> Dictionary:
	var visible: PackedStringArray = []
	var hidden := 0
	for m in d.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.has_meta(SquadLook.HID_META):
			hidden += 1
		if mi.is_visible_in_tree():
			visible.append(String(d.get_path_to(mi)))
	return {"nodes": d.find_children("*", "", true, false).size(), "visible": visible, "hidden": hidden}


func _look_names(d: ModularDoll) -> Array:
	var out: Array = []
	for n in SquadLook.added_nodes(d):
		out.append("%s/%s" % [n.get_parent().name, n.name])
	out.sort()
	return out


## Видимые меши вида (кроме лица и наклеек — их DollOutline не обводит) без ребёнка Outline.
func _meshes_without_outline(d: ModularDoll) -> Array:
	var out: Array = []
	for n in SquadLook.added_nodes(d):
		for m in n.find_children("*", "MeshInstance3D", true, false):
			var nm := String(m.name)
			if nm == DollOutline.NAME or nm.begins_with("Face") or nm.begins_with("Sticker"):
				continue
			if (m as MeshInstance3D).is_visible_in_tree() and m.get_node_or_null(DollOutline.NAME) == null:
				out.append(String(d.get_path_to(m)))
	return out


func _meshes_with_double_outline(d: ModularDoll) -> Array:
	var out: Array = []
	for m in d.find_children("*", "MeshInstance3D", true, false):
		var k := 0
		for c in m.get_children():
			k += 1 if String(c.name).begins_with(DollOutline.NAME) else 0
		if k > 1:
			out.append(String(d.get_path_to(m)))
	return out


func _tris(n: MeshInstance3D) -> int:
	if n == null or n.mesh == null or n.mesh.get_surface_count() == 0:
		return 0
	return (n.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


func _check(cond: bool, msg: String) -> void:
	if not cond:
		report["ok"] = false
		(report["errors"] as Array).append(msg)


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.26, 0.27, 0.29)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	for spec in [[Vector3(-35.0, -30.0, 0.0), Color(1.0, 0.95, 0.88), 1.3], [Vector3(-10.0, 160.0, 0.0), Color(0.7, 0.75, 1.0), 0.6]]:
		var l := DirectionalLight3D.new()
		l.rotation_degrees = spec[0]
		l.light_color = spec[1]
		l.light_energy = spec[2]
		l.shadow_enabled = true
		add_child(l)
