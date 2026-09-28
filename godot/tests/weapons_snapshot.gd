## Скриншоты оружия (R16) + проверка подбора сценой куклы.
## row:  пять сцен weapon_<id>.tscn стоят в ряд на полу, вид спереди, близко → tests/weapons_row.png
## closeups: каждое оружие крупно → tests/weapon_<id>_closeup.png (для сверки деталей с R16)
## hand: кукла (scenes/doll/doll.tscn, external_input) + WeaponPickup; молот в радиусе подбора правой кисти;
##       через 1 с толчок вправо на 1 с → tests/weapon_in_hand.png (кадр shot=1.35 с: кукла в наклоне, молот
##       отстаёт по инерции); печатает, держит ли сустав, и max скорость частей. Кукла с k=20 после толчка падает —
##       это поведение куклы, не оружия.
## Запуск (нужно окно):
##   godot --path . --resolution 1920x1080 --position 100,100 res://tests/weapons_snapshot.tscn -- "mode=all"
## Аргументы одной строкой k=v,k=v: mode=all|row|closeups|hand, shot=1.35 (момент кадра руки, с),
## skin=res://... (внешняя модель, если у куклы есть skin_scene), dbg=/abs/dir (кадры фазы hand каждые 0.15 с).
## Печатает JSON-отчёт и выходит с кодом 0/1 (в режимах с hand).
extends Node3D

const IDS := ["hammer", "mace", "sword", "axe", "pan"]
const DOLL_SCENE := "res://scenes/doll/doll.tscn"
const PUSH_START_S := 1.0
const PUSH_S := 1.0
const HAND_END_S := 2.6
const MAX_SPEED := 20.0
const MAX_HOLD_DIST := 0.15
const ROW_SPACING := 0.84

var cfg := {"mode": "all", "shot": 1.35, "skin": "", "dbg": "", "hold": 90.0}
var cam: Camera3D
var sun: DirectionalLight3D
var doll: Node3D
var pickup: WeaponPickup
var hammer: Weapon
var phase := "setup"
var tb := 0.0
var dbg_next := 0.3
var attach_t := -1.0
var hold_dist_max := 0.0
var speed_max := 0.0
var weapon_speed_max := 0.0
var report := {"ok": true, "checks": [], "shots": []}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			if p[0] in ["mode", "skin", "dbg"]:
				cfg[p[0]] = p[1]
			elif cfg.has(p[0]):
				cfg[p[0]] = float(p[1])
	_world()
	_run()


## Освещение для честной оценки: солнце с тенями + заполняющий свет, небо для ambient/отражений,
## SSAO, тонмаппинг ACES, MSAA 4x.
func _world() -> void:
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_4X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.165, 0.18)
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.42, 0.58)
	sm.sky_horizon_color = Color(0.72, 0.74, 0.78)
	sm.ground_horizon_color = Color(0.5, 0.46, 0.42)
	sm.ground_bottom_color = Color(0.14, 0.12, 0.11)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 1.0
	e.ambient_light_energy = 0.7
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.ssao_enabled = true
	e.ssao_radius = 0.4
	e.ssao_intensity = 2.0
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.0
	e.tonemap_white = 6.0
	env.environment = e
	add_child(env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46, 32, 0)
	sun.light_energy = 1.6
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_max_distance = 30.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, -125, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.8, 0.86, 1.0)
	add_child(fill)
	cam = Camera3D.new()
	cam.fov = 30
	add_child(cam)
	var f := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(40, 1, 40)
	cs.shape = bs
	f.add_child(cs)
	var fm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(40, 1, 40)
	fm.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.21, 0.21, 0.22)
	mat.roughness = 0.95
	fm.material_override = mat
	f.add_child(fm)
	f.position = Vector3(0, -0.5, 0)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	f.physics_material_override = pm
	add_child(f)


func _run() -> void:
	var mode := String(cfg["mode"])
	await get_tree().process_frame
	if mode in ["all", "row"]:
		await _row()
	if mode in ["all", "closeups"]:
		await _closeups()
	if mode in ["all", "hand"]:
		await _hand()
	else:
		_finish()


## Оружие сценой, поставленное вертикально (локальная +X → мировая +Y), низ на полу.
func _stand(id: String, x: float) -> Weapon:
	var w := Weapon.spawn(id, self, Vector3(x, 0, 0), 90.0)
	if w == null:
		return null
	w.freeze = true
	var b := w.bounds()
	w.position = Vector3(x + b.position.y + b.size.y / 2.0, -b.position.x + 0.012, 0)
	return w


func _row() -> void:
	var ws: Array = []
	var labels: Array = []
	for i in range(IDS.size()):
		var x := (i - 2) * ROW_SPACING
		var w := _stand(IDS[i], x)
		if w == null:
			report["ok"] = false
			continue
		ws.append(w)
		var sh := []
		for cs in w.shapes:
			sh.append(cs.name.trim_prefix("Col_"))
		print("weapon %s: mass=%.1f mult=%.1f length=%.2f shapes=%s bounds=%s" % [IDS[i], w.mass, w.damage_mult, w.length, sh, var_to_str(w.bounds())])
		var lbl := Label3D.new()
		lbl.text = "%02d %s  %.1f kg  x%.1f" % [i + 1, IDS[i], w.mass, w.damage_mult]
		lbl.font_size = 36
		lbl.pixel_size = 0.0014
		lbl.position = Vector3(x, 1.28, 0)
		lbl.modulate = Color(0.85, 0.85, 0.85)
		lbl.outline_modulate = Color(0, 0, 0, 0.7)
		lbl.outline_size = 8
		add_child(lbl)
		labels.append(lbl)
	cam.fov = 26
	cam.position = Vector3(0, 1.0, 4.9)
	cam.look_at(Vector3(0, 0.58, 0))
	await _capture("weapons_row.png", 3)
	for n in ws + labels:
		n.queue_free()
	await get_tree().process_frame


func _closeups() -> void:
	for id in IDS:
		var w := _stand(id, 0.0)
		if w == null:
			continue
		var b := w.bounds()
		var h := b.size.x
		var cy := w.position.y + b.position.x + h / 2.0
		cam.fov = 30
		cam.position = Vector3(0.0, cy + 0.15, h / (2.0 * tan(deg_to_rad(15.0))) * 1.12)
		cam.look_at(Vector3(0, cy, 0))
		await _capture("weapon_%s_closeup.png" % id, 3)
		w.queue_free()
		await get_tree().process_frame


func _hand() -> void:
	var ps := load(DOLL_SCENE) as PackedScene
	if ps == null:
		push_error("weapons_snapshot: cannot load " + DOLL_SCENE)
		report["ok"] = false
		_finish()
		return
	doll = ps.instantiate()
	if not doll.has_method("max_part_speed") or not ("parts" in doll):
		push_error("weapons_snapshot: doll scene has no Doll script (parts/max_part_speed)")
		report["ok"] = false
		_finish()
		return
	doll.set("player_index", 0)
	doll.set("external_input", true)
	if String(cfg["skin"]) != "" and "skin_scene" in doll:
		doll.set("skin_scene", String(cfg["skin"]))
	add_child(doll)
	doll.position = Vector3.ZERO
	pickup = WeaponPickup.new()
	pickup.name = "WeaponPickup"
	pickup.hold_angle_deg = float(cfg["hold"])
	doll.add_child(pickup)
	await get_tree().physics_frame
	# молот появляется хватом точно в точке хвата правой кисти, головой в сторону от торса, над полом.
	# (Раньше стоял на голове с хватом на y=0.96 под манекен 1.9 м; у деревянной куклы 1.64 м кисть на ~0.54 м —
	# 0.42 м до хвата > радиуса подбора 0.35, подбор не происходил.) Подбор — на первом физическом тике,
	# дальше WeaponPickup сам ставит молот под hold_angle.
	var hand_pos := pickup.hand_grip_global("Hand_R")
	var away := 1.0 if hand_pos.x >= doll.global_position.x else -1.0
	hammer = Weapon.spawn("hammer", self, hand_pos, 0.0 if away > 0.0 else 180.0)
	hammer.global_position += hand_pos - hammer.grip_global()
	var d := hand_pos.distance_to(hammer.grip_global())
	report["spawn_hand_to_grip_m"] = snappedf(d, 0.001)
	cam.fov = 30
	phase = "hand"
	tb = 0.0
	while tb < HAND_END_S:
		await get_tree().process_frame
		if phase == "hand" and doll != null:
			var com: Vector3 = doll.centre_of_mass()
			cam.position = Vector3(clampf(com.x, -3.0, 3.0), 1.5, 6.4)
			cam.look_at(Vector3(clampf(com.x, -3.0, 3.0), 0.95, 0))
		if tb >= float(cfg["shot"]) and not report.has("hand_shot_t"):
			report["hand_shot_t"] = snappedf(tb, 0.01)
			await _capture("weapon_in_hand.png", 1)
		elif String(cfg["dbg"]) != "" and tb >= dbg_next:
			dbg_next += 0.15
			await _capture("%s/dbg_%03d.png" % [cfg["dbg"], int(round(tb * 100.0))], 1)
	_finish()


func _physics_process(delta: float) -> void:
	if phase != "hand" or doll == null:
		return
	tb += delta
	if tb >= PUSH_START_S and tb < PUSH_START_S + PUSH_S:
		doll.set("input_vec", Vector2(1, 0))
	else:
		doll.set("input_vec", Vector2.ZERO)
	speed_max = max(speed_max, float(doll.max_part_speed()))
	if is_instance_valid(hammer):
		weapon_speed_max = max(weapon_speed_max, hammer.speed())
	if pickup.is_holding("Hand_R"):
		if attach_t < 0.0:
			attach_t = tb
		hold_dist_max = max(hold_dist_max, pickup.hold_distance("Hand_R"))


func _capture(name: String, settle_frames: int) -> void:
	for i in range(settle_frames):
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := name if name.begins_with("/") else "res://tests/" + name
	img.save_png(path)
	report["shots"].append(name)
	print("saved ", name)


func _check(id: String, value: float, limit: float, cmp: String, detail: String) -> void:
	var ok := (value < limit) if cmp == "lt" else (value > limit)
	report["checks"].append({"id": id, "value": snappedf(value, 0.001), "limit": limit, "cmp": cmp, "ok": ok, "detail": detail})
	if not ok:
		report["ok"] = false


func _finish() -> void:
	if phase == "hand" and doll != null and pickup != null:
		var holding := pickup.is_holding("Hand_R") and is_instance_valid(pickup.joint_of("Hand_R"))
		_check("pickup_attached", attach_t if attach_t >= 0.0 else 99.0, 0.2, "lt", "hammer attached to Hand_R within 0.2 s of spawn (s; 99 = never)")
		_check("joint_holds", 1.0 if holding else 0.0, 0.5, "gt", "still holding at the end (joint alive)")
		_check("hold_distance", hold_dist_max, MAX_HOLD_DIST, "lt", "max |hand grip - weapon grip| while held (m)")
		_check("no_explosion_parts", speed_max, MAX_SPEED, "lt", "max doll part speed (m/s)")
		_check("no_explosion_weapon", weapon_speed_max, MAX_SPEED, "lt", "max hammer speed (m/s)")
		if attach_t < 0.0:
			report["ok"] = false
		report["joint_held"] = holding
		report["max_part_speed"] = snappedf(speed_max, 0.01)
		report["max_hammer_speed"] = snappedf(weapon_speed_max, 0.01)
		if is_instance_valid(hammer):
			report["hammer_final"] = {"pos": var_to_str(hammer.global_position), "rot_z_deg": snappedf(rad_to_deg(hammer.global_rotation.z), 0.1)}
		print("joint held: %s; max part speed: %.2f m/s; max hammer speed: %.2f m/s" % [str(holding), speed_max, weapon_speed_max])
	phase = "done"
	print("=== WEAPONS SNAPSHOT ===")
	print(JSON.stringify(report, "  "))
	print("=== %s ===" % ("OK" if report["ok"] else "FAIL"))
	get_tree().quit(0 if report["ok"] else 1)
