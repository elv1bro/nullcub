## Бойцы NULL League в игре (tools/build_league.gd → scenes/body/presets/league_*.tscn; docs/plan-demo/ART_NULL.md, «Детали лиги v2»).
## Headless: godot --headless --path godot --fixed-fps 60 res://tests/league_fighters_snapshot.tscn → отчёт, код выхода 0/1
## Кадр (окно; в контейнере — xvfb-run): godot --path godot --resolution 1600x900 --fixed-fps 60 res://tests/league_fighters_snapshot.tscn
##   -- "sheet=/abs/league-fighters.png"  (кадр в позе спавна; рядом <имя>-idle.png — после IDLE_S покоя)
## Проверки (exit 1): четыре пресета собираются без ошибок чертежа; LeagueLook применился — шары суставов ужаты до JOINT_SCALE,
## все Shirt_* — свечение лиги (цвета игрока нет), у головы визор league_face.png; IDLE_S покоя на полу без взрыва — точки суставов на
## обоих телах расходятся ≤ MAX_JOINT_GAP, скорость частей ≤ MAX_IDLE_SPEED, нет NaN, торс над полом.
## Отчёт — tests/league_fighters_snapshot_report.json.
extends Node3D

const PRESETS := ["league_reaper", "league_crystal", "league_deep", "league_portal"]
const PRESET_DIR := "res://scenes/body/presets/"
const SPACING := 3.1
const IDLE_S := 4.0
const MAX_JOINT_GAP := 0.05
const MAX_IDLE_SPEED := 8.0
const MIN_TORSO_Y := 0.15

var checks: Array = []
var args := {}
var dolls: Array[ModularDoll] = []
var track: Array = []      # по кукле: [[joint, a, b, pa (локально в a), pb (локально в b)], …]
var max_gap := {}
var max_speed := {}
var nan := {}
var t := 0.0
var stage := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		for kv in String(a).split(","):
			var p := String(kv).split("=")
			if p.size() == 2:
				args[p[0]] = p[1]
	_environment()
	_floor()
	for i in range(PRESETS.size()):
		var ps := load(PRESET_DIR + PRESETS[i] + ".tscn") as PackedScene
		if ps == null:
			_check("preset_" + PRESETS[i], false, "нет сцены")
			continue
		var d := ps.instantiate() as ModularDoll
		d.external_input = true
		d.player_index = 1
		d.position = Vector3((i - (PRESETS.size() - 1) * 0.5) * SPACING, 0.0, 0.0)
		add_child(d)
		dolls.append(d)
	var cam := Camera3D.new()
	cam.fov = 30.0
	add_child(cam)
	cam.current = true
	cam.position = Vector3(0.0, 1.9, 14.5)
	cam.look_at(Vector3(0.0, 0.8, 0.0))


func _physics_process(dt: float) -> void:
	if stage == 0:
		stage = 1
		_static_checks()
		for d in dolls:
			track.append(_joints_of(d))
		if args.has("sheet"):
			await _shot(String(args["sheet"]))
		return
	if stage != 1:
		return
	t += dt
	for i in range(dolls.size()):
		_tick(i)
	if t >= IDLE_S:
		stage = 2
		_idle_checks()
		if args.has("sheet"):
			await _shot(String(args["sheet"]).get_basename() + "-idle.png")
		_finish()


func _static_checks() -> void:
	_check("presets_4", dolls.size() == PRESETS.size(), "%d / %d" % [dolls.size(), PRESETS.size()])
	var glow := LeagueLook.glow_material()
	var face_tex := load(LeagueLook.FACE_TEX) as Texture2D
	for d in dolls:
		var id := String(d.blueprint.id)
		_check(id + ".build", d.build_errors.is_empty() and id.begins_with("league_"), "; ".join(d.build_errors))
		var look := d.get_node_or_null("LeagueLook") as LeagueLook
		_check(id + ".look", look != null and look.applied and look.connectors > 0 and look.shirt_surfaces > 0 and look.faces >= 1,
			"connectors %d, shirt %d, faces %d" % [look.connectors, look.shirt_surfaces, look.faces] if look != null else "нет LeagueLook")
		var bad_scale: Array = []
		var not_glow: Array = []
		var face_ok := false
		for n in d.find_children("*", "", true, false):
			if n is Node3D and String(n.name).begins_with(LeagueLook.CONNECTOR_PREFIX):
				# масштаб шара = joint_r якоря (0.044…0.076 м): ужатый — не больше самого крупного × JOINT_SCALE
				var s := (n as Node3D).scale.x
				if s > 0.076 * LeagueLook.JOINT_SCALE + 0.001 or s <= 0.0:
					bad_scale.append("%s %.3f" % [n.name, s])
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				var mi := n as MeshInstance3D
				for s in range(mi.mesh.get_surface_count()):
					var m := mi.get_active_material(s)
					if m == null:
						continue
					if String(m.resource_name).begins_with("Shirt") and m != glow:
						not_glow.append("%s:%s" % [mi.name, m.resource_name])
					elif String(m.resource_name).begins_with("Face") and m is BaseMaterial3D:
						var bm := m as BaseMaterial3D
						face_ok = face_ok or (bm.albedo_texture == face_tex and bm.emission_enabled)
		_check(id + ".joints_shrunk", bad_scale.is_empty(), str(bad_scale.slice(0, 4)))
		_check(id + ".league_colour", not_glow.is_empty(), str(not_glow.slice(0, 4)))
		_check(id + ".face_visor", face_ok, LeagueLook.FACE_TEX)


## Суставы куклы: точка сустава в локальных кадрах обоих тел — по кадрам СБОРКИ (d.assembly), как tests/body_probe: spawn_in_pose
## поворачивает дистальные тела, а узел сустава остаётся на месте сборки (его global_position — не точка сустава).
func _joints_of(d: ModularDoll) -> Array:
	var out: Array = []
	for j in d.joints.values():
		var jj := j as Generic6DOFJoint3D
		var a := jj.get_node_or_null(jj.node_a) as RigidBody3D
		var b := jj.get_node_or_null(jj.node_b) as RigidBody3D
		if a == null or b == null:
			continue
		var pa: Vector3 = (d.assembly[String(a.name)] as Transform3D).affine_inverse() * jj.position
		var pb: Vector3 = (d.assembly[String(b.name)] as Transform3D).affine_inverse() * jj.position
		out.append([jj, a, b, pa, pb])
	return out


func _tick(i: int) -> void:
	var id := String(dolls[i].blueprint.id)
	for e in track[i]:
		var a := e[1] as RigidBody3D
		var b := e[2] as RigidBody3D
		if not is_instance_valid(a) or not is_instance_valid(b):
			continue
		var pa := a.to_global(e[3] as Vector3)
		var pb := b.to_global(e[4] as Vector3)
		if not (pa.is_finite() and pb.is_finite()):
			nan[id] = true
			continue
		max_gap[id] = maxf(float(max_gap.get(id, 0.0)), pa.distance_to(pb))
	for rb in dolls[i].find_children("*", "RigidBody3D", true, false):
		var v := (rb as RigidBody3D).linear_velocity
		if not v.is_finite():
			nan[id] = true
		else:
			max_speed[id] = maxf(float(max_speed.get(id, 0.0)), v.length())


func _idle_checks() -> void:
	for d in dolls:
		var id := String(d.blueprint.id)
		var torso := d.get_node_or_null(String(d.uid_body.get("T", "Torso"))) as RigidBody3D
		var ty := torso.global_position.y if torso != null else -1.0
		_check(id + ".idle", not nan.has(id) and float(max_gap.get(id, 0.0)) <= MAX_JOINT_GAP and float(max_speed.get(id, 0.0))
			<= MAX_IDLE_SPEED and ty >= MIN_TORSO_Y, "gap %.3f м, speed %.2f м/с, torso y %.2f м%s" % [max_gap.get(id, 0.0),
			max_speed.get(id, 0.0), ty, ", NaN" if nan.has(id) else ""])


func _shot(path: String) -> void:
	for i in range(3):
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	_check("sheet:" + path.get_file(), err == OK, path)


func _finish() -> void:
	var ok := true
	for c in checks:
		ok = ok and bool(c["ok"])
	var f := FileAccess.open("res://tests/league_fighters_snapshot_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"ok": ok, "checks": checks}, "  "))
	f.close()
	print("league_fighters_snapshot: %s (%d checks)" % ["OK" if ok else "FAIL", checks.size()])
	get_tree().quit(0 if ok else 1)


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
	mat.albedo_color = Color(0.13, 0.12, 0.15)
	mat.roughness = 0.8
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	add_child(body)


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.045, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.52, 0.65)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	for spec in [[Vector3(-40.0, -25.0, 0.0), Color(1.0, 0.88, 0.75), 1.4], [Vector3(-15.0, 165.0, 0.0), Color(0.55, 0.6, 1.0), 1.4]]:
		var l := DirectionalLight3D.new()
		l.rotation_degrees = spec[0]
		l.light_color = spec[1]
		l.light_energy = spec[2]
		l.shadow_enabled = true
		add_child(l)


func _check(id: String, ok: bool, info: String) -> void:
	checks.append({"id": id, "ok": ok, "info": info})
	print("%s %s — %s" % ["PASS" if ok else "FAIL", id, info])
