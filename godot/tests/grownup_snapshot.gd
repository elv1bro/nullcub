## Кадры «взрослого вида» бойцов (docs/plan-demo/grownup_art/): до/после прохода по материалам кита. Нужен рендер:
##   GODOT_BIN=/usr/local/bin/godot godot/tools/godot_bg.sh --path godot --resolution 1600x900 --fixed-fps 60 \
##     res://tests/grownup_snapshot.tscn -- "out=/abs/dir,tag=after"
## Кадры (в out): fighters_a/b_<tag>.png — манекен и шаблоны кита в студии; sets_a/b_<tag>.png — наборы (про-лига, Аоэлюн, лига);
## close_<tag>.png — головы и торсы крупно; parts_<tag>.png — карточки деталей мастерской (PartIcons); fight_<tag>.png — двое в стычке.
## Проверки (exit 1): все пресеты собрались, кадры сохранены, иконок деталей ≥ 90 % списка. Физику кукол замораживаем — это витрина.
extends Node3D

const HALL := preload("res://scenes/arena/null_hall.tscn")
const PRESET_DIR := "res://scenes/body/presets/"
const FIGHTERS := ["@doll", "kit_human", "kit_brawler", "kit_bot", "kit_horned", "kit_lantern"]
const SETS := ["pro_sprinter", "pro_titan", "aoe_predator", "aoe_ram", "league_reaper", "kit_skull"]
const CLOSE := ["kit_human", "pro_titan", "@doll", "kit_bot"]
const PARTS := [
	"kit_human_head", "kit_head_round", "kit_head_bot", "kit_head_can", "kit_head_skull", "kit_head_horned", "kit_head_pro_visor",
	"kit_head_pro_pilot", "kit_head_aoe_hunter", "kit_head_league_eye", "kit_core_toy", "kit_core_ball", "kit_core_boiler",
	"kit_core_pro_reactor", "kit_core_aoe_heart", "kit_core_league_orb", "kit_human_torso", "kit_limb_basic_l", "kit_limb_thick_l",
	"kit_limb_piston_l", "kit_limb_plate_l", "kit_limb_robotic_l", "kit_limb_pro_panel_l", "kit_limb_aoe_blade_l", "kit_limb_league_float_l",
	"kit_hand_fist", "kit_hand_mitten", "kit_hand_clamp", "kit_hand_pro_crusher", "kit_hand_aoe_claw", "kit_foot_boot", "kit_foot_wheel",
	"kit_foot_pro_spike", "kit_hub_star", "kit_deco_pauldron", "kit_deco_gauntlet_l", "kit_mod_bumper", "kit_mod_battery", "kit_saw_disc",
	"kit_active_jetpack",
]
const SPACING := 2.45

var checks: Array = []
var args := {}
var cam: Camera3D
var hall: Node3D
var studio: Node3D
var floor_y := 0.0
var out_dir := ""
var tag := "shot"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		for kv in String(a).split(","):
			var p := String(kv).split("=")
			if p.size() == 2:
				args[p[0]] = p[1]
	out_dir = String(args.get("out", ProjectSettings.globalize_path("res://tests/grownup_shots")))
	tag = String(args.get("tag", "shot"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	_studio()
	cam = Camera3D.new()
	cam.fov = 30.0
	cam.far = 300.0
	add_child(cam)
	cam.current = true
	await _run()


func _run() -> void:
	# 1–2. Бойцы и наборы: по трое в кадре, чтобы куклы были крупными
	var groups := [["fighters_a", FIGHTERS.slice(0, 3), 0], ["fighters_b", FIGHTERS.slice(3, 6), 1],
			["sets_a", SETS.slice(0, 3), 1], ["sets_b", SETS.slice(3, 6), 0]]
	for g in groups:
		var row := await _lineup(g[1], SPACING, int(g[2]))
		cam.fov = 30.0
		_aim(Vector3(0.0, floor_y + 1.3, 8.4), Vector3(0.0, floor_y + 1.05, 0.0))
		await _save(String(g[0]))
		_clear(row)
	# 3. Крупно: головы и торсы
	var row := await _lineup(CLOSE, 1.25, 0)
	cam.fov = 26.0
	_aim(Vector3(0.0, floor_y + 1.75, 5.2), Vector3(0.0, floor_y + 1.35, 0.0))
	await _save("close")
	_clear(row)
	# 4. Стычка в зале NULL: двое сходятся, физика живая
	studio.queue_free()
	await _frames(1)
	hall = HALL.instantiate() as Node3D
	add_child(hall)
	await _fight()
	# 5. Карточки деталей
	await _parts()
	_finish()


func _lineup(ids: Array, spacing: float, player: int) -> Array:
	var made: Array = []
	for i in range(ids.size()):
		var id := String(ids[i])
		var path := ("res://scenes/doll/%s.tscn" % id.substr(1)) if id.begins_with("@") else PRESET_DIR + id + ".tscn"
		var ps := load(path) as PackedScene
		if ps == null:
			_check("scene_" + id, false, "нет " + path)
			continue
		var d := ps.instantiate() as Node3D
		if "external_input" in d:
			d.set("external_input", true)
		if "player_index" in d:
			d.set("player_index", (player + i) % 2)
		add_child(d)
		d.global_position = Vector3((i - (ids.size() - 1) * 0.5) * spacing, floor_y + (0.05 if not id.begins_with("@") else 0.0), 0.0)
		made.append(d)
	_check("built_%d" % ids.size(), made.size() == ids.size(), "%d / %d" % [made.size(), ids.size()])
	await _frames(2)
	for d in made:
		for b in (d as Node).find_children("*", "RigidBody3D", true, false):
			(b as RigidBody3D).freeze = true
	await _frames(4)
	return made


func _fight() -> void:
	var a := (load(PRESET_DIR + "kit_human.tscn") as PackedScene).instantiate() as Node3D
	var b := (load(PRESET_DIR + "pro_titan.tscn") as PackedScene).instantiate() as Node3D
	for pair in [[a, 0, -1.1], [b, 1, 1.1]]:
		var d := pair[0] as Node3D
		d.set("external_input", true)
		d.set("player_index", pair[1])
		add_child(d)
		d.global_position = Vector3(float(pair[2]), floor_y + 0.05, 0.0)
	await _frames(3)
	for pair in [[a, 1.0], [b, -1.0]]:
		for body in (pair[0] as Node).find_children("*", "RigidBody3D", true, false):
			(body as RigidBody3D).linear_velocity = Vector3(5.0 * float(pair[1]), 1.5, 0.0)
	cam.fov = 34.0
	_aim(Vector3(1.2, floor_y + 2.4, 7.5), Vector3(0.0, floor_y + 1.0, 0.0))
	for i in range(22):
		await get_tree().physics_frame
	await _save("fight")
	_clear([a, b])


func _parts() -> void:
	var icons := PartIcons.new()
	add_child(icons)
	await _frames(2)
	var got := {}
	icons.icon_ready.connect(func(id: String, tex: Texture2D) -> void: got[id] = tex)
	for id in PARTS:
		icons.request(id)
	var waited := 0
	while icons.pending() > 0 and waited < 600:
		await get_tree().process_frame
		waited += 1
	_check("part_icons", got.size() >= int(PARTS.size() * 0.9), "%d / %d" % [got.size(), PARTS.size()])
	var cols := 10
	var cell := 160
	var rows := ceili(PARTS.size() / float(cols))
	var sheet := Image.create(cols * cell, rows * cell, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.11, 0.115, 0.12))
	for i in range(PARTS.size()):
		var tex := got.get(PARTS[i]) as Texture2D
		if tex == null:
			continue
		var img := tex.get_image()
		img.convert(Image.FORMAT_RGBA8)
		var x := (i % cols) * cell
		var y := (i / cols) * cell
		var bg := Image.create(cell, cell, false, Image.FORMAT_RGBA8)
		bg.fill(Color(0.16, 0.165, 0.17) if (i + i / cols) % 2 == 0 else Color(0.13, 0.135, 0.14))
		sheet.blit_rect(bg, Rect2i(0, 0, cell, cell), Vector2i(x, y))
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(x, y))
	var path := out_dir.path_join("parts_%s.png" % tag)
	_check("saved_parts", sheet.save_png(path) == OK, path)


## Нейтральная студия для рядов: тёмный фон и пол, тёплый ключ и холодный контровой — как свет зала, без рекламы за спиной.
func _studio() -> void:
	studio = Node3D.new()
	add_child(studio)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.075, 0.08, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.56, 0.62)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	studio.add_child(we)
	for spec in [[Vector3(-38.0, -30.0, 0.0), Color(1.0, 0.9, 0.78), 1.5, true], [Vector3(-12.0, 160.0, 0.0), Color(0.6, 0.7, 1.0), 1.1, false],
			[Vector3(-70.0, 20.0, 0.0), Color(1.0, 1.0, 1.0), 0.35, false]]:
		var l := DirectionalLight3D.new()
		l.rotation_degrees = spec[0]
		l.light_color = spec[1]
		l.light_energy = spec[2]
		l.shadow_enabled = spec[3]
		studio.add_child(l)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60.0, 30.0)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.16, 0.165, 0.17)
	fm.roughness = 0.85
	fl.material_override = fm
	studio.add_child(fl)


func _aim(pos: Vector3, at: Vector3) -> void:
	cam.position = pos
	cam.look_at(at)


func _save(name: String) -> void:
	await _frames(6)
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var path := out_dir.path_join("%s_%s.png" % [name, tag])
	_check("saved_" + name, img.save_png(path) == OK, path)


func _clear(nodes: Array) -> void:
	for n in nodes:
		(n as Node).queue_free()


func _frames(n: int) -> void:
	for i in range(n):
		await RenderingServer.frame_post_draw


func _finish() -> void:
	var ok := true
	for c in checks:
		ok = ok and bool(c["ok"])
	print("grownup_snapshot: ", "OK" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)


func _check(id: String, ok: bool, info: String) -> void:
	checks.append({"id": id, "ok": ok, "info": info})
	print("%s %s — %s" % ["PASS" if ok else "FAIL", id, info])
