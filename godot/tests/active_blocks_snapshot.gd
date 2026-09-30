## Кадры активных блоков (docs/plan-demo/ACTIVE_BLOCKS.md). Окно (в контейнере — xvfb-run):
##   godot --path godot --resolution 1600x900 --fixed-fps 60 res://tests/active_blocks_snapshot.tscn -- "mode=fight,out=/abs/fight.png"
##   godot --path godot --resolution 1920x1080 res://tests/active_blocks_snapshot.tscn -- "mode=workshop,out=/abs/workshop.png"
## fight — kit_human с огнемётом (правая рука, канал 2, Q/F/C = 1/2/3) и пулемётом (левая, канал 3) жжёт Кристаллида под энергощитом и
##   стреляет по второму бойцу; третий летит на реактивном ранце (канал 1); над каждым — полоска заряда и огоньки каналов.
## workshop — мастерская: kit_human с ранцем, огнемётом и пулемётом, полка «Активные», выбран огнемёт (строка «Канал»), на кукле —
##   плашки клавиш каналов. Проверка одна: кадр сохранён (exit 1 — нет).
extends Node3D

const DOLL := preload("res://scenes/body/modular_doll.tscn")
const HUMAN := "res://data/body/blueprints/kit_human.tres"

var args := {}
var t := 0.0
var done := false
var dolls: Dictionary = {}
var ws: WorkshopBuild


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		for kv in String(a).split(","):
			var p := String(kv).split("=")
			if p.size() == 2:
				args[p[0]] = p[1]
	if String(args.get("mode", "fight")) == "workshop":
		_workshop.call_deferred()
	else:
		_fight()


func _bp(actives: Array) -> BodyBlueprint:
	var bp := (load(HUMAN) as BodyBlueprint).duplicate(true) as BodyBlueprint
	var nodes: Array[Dictionary] = []
	for n in bp.nodes:
		nodes.append((n as Dictionary).duplicate(true))
	var uids := "DEFG"
	for k in range(actives.size()):
		var a: Array = actives[k]
		nodes.append({"uid": uids[k], "part": String(a[0]), "parent": String(a[1]), "anchor": String(a[2]), "channel": int(a[3])})
	bp.nodes = nodes
	bp.energy_budget = 1000
	bp.id = "snapshot_%d" % actives.size()
	return bp


func _spawn(bp: BodyBlueprint, x: float, scene := "") -> ModularDoll:
	var d: ModularDoll
	if scene != "":
		d = (load(scene) as PackedScene).instantiate() as ModularDoll
	else:
		d = DOLL.instantiate() as ModularDoll
		d.blueprint = bp
	d.external_input = true
	d.position = Vector3(x, 0.0, 0.0)
	add_child(d)
	return d


func _fight() -> void:
	_environment()
	_floor()
	dolls["gunner"] = _spawn(_bp([["kit_active_flamer", "8", "Anchor_Deco", 2], ["kit_active_gun", "2", "Anchor_Deco", 3]]), 0.0)
	dolls["crystal"] = _spawn(null, -1.35, "res://scenes/body/presets/league_crystal.tscn")
	dolls["target"] = _spawn(_bp([]), 3.2)
	dolls["jet"] = _spawn(_bp([["kit_active_jetpack", "T", "Anchor_Back", 1], ["kit_active_booster", "2", "Anchor_Deco", 1]]), 4.9)
	var cam := Camera3D.new()
	cam.fov = 34.0
	add_child(cam)
	cam.current = true
	cam.position = Vector3(1.7, 2.0, 10.5)
	cam.look_at(Vector3(1.7, 1.25, 0.0))


func _physics_process(dt: float) -> void:
	if ws != null or done or dolls.is_empty():
		return
	t += dt
	if t > 1.0:
		for k in ["gunner", "crystal", "jet"]:
			var r := (dolls[k] as ModularDoll).active_rig
			if r == null:
				continue
			for ch in range(3):
				r.held[ch] = true
	if t > 1.55:
		done = true
		_save()


func _workshop() -> void:
	ws = (load("res://scenes/workshop/workshop_build.tscn") as PackedScene).instantiate() as WorkshopBuild
	ws.load_autosave = false
	ws.autosave_on_test = false
	ws.probe_input = true
	add_child(ws)
	get_viewport().msaa_3d = Viewport.MSAA_4X
	for i in range(3):
		await get_tree().process_frame
	var icons: PartIcons = ws.ui.get("icons")
	for d in CraftEdit.all_parts():
		icons.request(d.id)
	var tt := 0.0
	while icons.pending() > 0 and tt < 20.0:
		await get_tree().process_frame
		tt += get_process_delta_time()
	ws.set_preset("kit_human")
	ws.attach_part("kit_active_jetpack", "T", "Anchor_Back", "body")
	var fl := ws.attach_part("kit_active_flamer", "8", "Anchor_Deco", "body")
	var gn := ws.attach_part("kit_active_gun", "2", "Anchor_Deco", "body")
	ws.set_channel(String(fl.get("uid", "")), 2)
	ws.set_channel(String(gn.get("uid", "")), 3)
	(ws.ui.get("shelf_tab") as Dictionary)["body"] = "active"
	ws.ui.call("_build_left")
	ws.select_stand(String(fl.get("uid", "")), "body")
	for i in range(70):
		await get_tree().process_frame
	_save()


func _save() -> void:
	await RenderingServer.frame_post_draw
	var out := String(args.get("out", "res://tests/active_blocks_snapshot.png"))
	var err := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(out) if out.begins_with("res://") else out)
	print("active_blocks_snapshot: %s → %s" % ["OK" if err == OK else "FAIL", out])
	get_tree().quit(0 if err == OK else 1)


func _floor() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60.0, 1.0, 40.0)
	cs.shape = bs
	body.add_child(cs)
	body.position = Vector3(0.0, -0.5, 0.0)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.15, 0.18)
	mat.roughness = 0.85
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	add_child(body)


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.045, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.65)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	for spec in [[Vector3(-40.0, -25.0, 0.0), Color(1.0, 0.9, 0.78), 1.4], [Vector3(-15.0, 165.0, 0.0), Color(0.55, 0.6, 1.0), 1.2]]:
		var l := DirectionalLight3D.new()
		l.rotation_degrees = spec[0]
		l.light_color = spec[1]
		l.light_energy = spec[2]
		l.shadow_enabled = true
		add_child(l)
