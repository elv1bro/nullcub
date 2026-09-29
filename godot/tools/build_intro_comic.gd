## Builder заставки-комикса (docs/plan-demo/INTRO_COMIC.md, ASSET_PIPELINE.md правило 2):
##   res://scenes/intro/comic_puppet.tscn       — марионетка, клён (герой)
##   res://scenes/intro/comic_puppet_dark.tscn  — марионетка, орех (враг-Разборщик)
##   res://scenes/intro/intro_stage.tscn        — съёмочная площадка: арена «Свалка», герой, враг, камера с чернильным
##                                                контуром, частицы, кадры Shots/Shot01…Shot13 (ComicShot)
## Запуск: godot --headless --path godot -s res://tools/build_intro_comic.gd  (аргумент "only=puppets|stage" — часть)
## Кадры ниже — черновик постановки; после сборки камеры, метки и свет правятся в редакторе (пересборка их перезапишет).
extends SceneTree

const PUPPET_SCRIPT := "res://scenes/intro/comic_puppet.gd"
const STAGE_SCRIPT := "res://scenes/intro/intro_stage.gd"
const SHOT_SCRIPT := "res://scenes/intro/comic_shot.gd"
const INK_SHADER := "res://scenes/intro/shaders/comic_ink.gdshader"
const MESH_DIR := "res://assets/models/heroes/mannequin_v3/%s/%s.glb"
const BITS := "res://assets/models/scrap/bits/%s.glb"
const PROPS := "res://assets/models/scrap/props/%s.glb"
const BODIES := "res://assets/models/scrap/bodies/%s.glb"
const CROWN_TEX := "res://assets/ui/crown.png"
const MOTE_TEX := "res://assets/textures/fx/mote.png"

const PUPPETS := {
	"light": {"out": "res://scenes/intro/comic_puppet.tscn", "uid": "uid://comicpuppet01"},
	"dark": {"out": "res://scenes/intro/comic_puppet_dark.tscn", "uid": "uid://comicpuppet02"},
}
const STAGE_OUT := "res://scenes/intro/intro_stage.tscn"
const STAGE_UID := "uid://introstage001"
const PAGE_OUT := "res://scenes/intro/intro_comic.tscn"
const PAGE_UID := "uid://introcomic001"
const COMIC_SCRIPT := "res://scenes/intro/intro_comic.gd"
const PANEL_SCRIPT := "res://scenes/intro/comic_panel.gd"
const LETTER_SCRIPT := "res://scenes/intro/comic_letter.gd"
const TITLE_SCRIPT := "res://scenes/intro/comic_title.gd"
const NEXT_SCENE := "res://scenes/playground_scrap.tscn"
const PAGE := Vector2(3840.0, 2160.0)
const MARGIN := 64.0
const GUTTER := 26.0
const TOWER := Color(1.0, 0.7, 0.28)
const ALARM := Color(1.0, 0.36, 0.2)

const HERO_COLOR := Color("2f6fde")
const ENEMY_COLOR := Color("b8342a")
const GOLD := Color(1.0, 0.72, 0.28)
const ENEMY_EYE := Color(1.0, 0.22, 0.12)

# Позиция героя на вершине кучи пробуждения (Heap_Awakening, x −17; коллизия сверху y ≈ 1.0).
const HEAP := Vector3(-17.0, 1.0, 0.3)
const HEAP2 := Vector3(-15.1, 0.97, 0.2)
# Ровный пол левее кучи (Floor_4, y = 0): кадры 06–08 — находка и сборка руки.
const FLOOR_A := Vector3(-19.3, 0.0, 0.3)
# Хват оторванного предплечья левой кистью: поперёк ладони, середина детали у пальцев.
var GRIP := Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)), Vector3(0.0, -0.09, 0.14))
const ARENA_X := 1.2
const ENEMY_X := 3.7
# Правого предплечья и кисти у героя нет до кадра 08 (приделывает чужое, из ореха).
const NO_ARM := ["0:hero_hide:LowerArm_R", "0:hero_hide:Hand_R"]
const DARK_ARM := ["0:hero_swap:LowerArm_R:dark", "0:hero_swap:Hand_R:dark"]

var scene_root: Node


func _init() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5)
	if only in ["", "puppets"]:
		for tone in PUPPETS:
			if not _save(_build_puppet(tone), PUPPETS[tone]["out"], PUPPETS[tone]["uid"]):
				return
	if only in ["", "stage"]:
		if not _save(_build_stage(), STAGE_OUT, STAGE_UID):
			return
	if only in ["", "page"]:
		if not _save(_build_page(), PAGE_OUT, PAGE_UID):
			return
	quit(0)


func _save(n: Node, path: String, uid: String) -> bool:
	scene_root = n
	_set_owner(n, n)
	var ps := PackedScene.new()
	var err := ps.pack(n)
	if err != OK:
		push_error("pack failed %s: %d" % [path, err])
		quit(1)
		return false
	err = ResourceSaver.save(ps, path)
	if err != OK:
		push_error("save failed %s: %d" % [path, err])
		quit(1)
		return false
	ResourceSaver.set_uid(path, ResourceUID.text_to_id(uid))
	print("saved ", path, ": nodes=", _count(n))
	n.free()
	return true


func _set_owner(n: Node, owner_: Node) -> void:
	for c in n.get_children():
		if c.owner == null:
			c.owner = owner_
		# внутри инстансов сцен у своих узлов owner уже есть (корень инстанса) — ставим только добавленным нами
		_set_owner(c, owner_)


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


# ------------------------------------------------------------------------------------------------
# марионетка
# ------------------------------------------------------------------------------------------------
func _build_puppet(tone: String) -> Node3D:
	var p := Node3D.new()
	p.name = "ComicPuppet"
	p.set_script(load(PUPPET_SCRIPT))
	p.set("base_tone", tone)
	var r := _node(p, "Root", Vector3(0.0, 0.91, 0.0))
	var torso := _part(r, tone, "Torso", Vector3(0.0, 0.26, 0.0))
	# свет Ядра, корона и глаза — дети мешей, чтобы при разлёте на части летели вместе с торсом и головой
	var glow := OmniLight3D.new()
	glow.name = "CoreGlow"
	glow.position = Vector3(0.0, 0.16, 0.2)
	glow.light_color = Color(1.0, 0.7, 0.3)
	glow.light_energy = 0.0
	glow.omni_range = 0.45
	glow.omni_attenuation = 2.0
	glow.shadow_enabled = false
	glow.visible = false
	torso.add_child(glow)
	var crown := MeshInstance3D.new()
	crown.name = "Crown"
	var q := QuadMesh.new()
	q.size = Vector2(0.075, 0.075)
	crown.mesh = q
	crown.position = Vector3(0.0, 0.17, 0.118)
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.albedo_texture = load(CROWN_TEX)
	cm.albedo_color = Color(1.0, 0.78, 0.35, 0.0)
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	crown.material_override = cm
	crown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	torso.add_child(crown)
	var neck := _node(r, "Neck", Vector3(0.0, 0.56, 0.0))
	var head := _part(neck, tone, "Head", Vector3.ZERO)
	for side in [["Eye_L", 0.036], ["Eye_R", -0.036]]:
		var e := MeshInstance3D.new()
		e.name = side[0]
		var s := SphereMesh.new()
		s.radius = 0.0125
		s.height = 0.025
		s.radial_segments = 12
		s.rings = 6
		e.mesh = s
		e.position = Vector3(side[1], 0.195, 0.109)
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		head.add_child(e)
	for sd in [["_L", 1.0], ["_R", -1.0]]:
		var suf: String = sd[0]
		var sx: float = sd[1]
		var sh := _node(r, "Shoulder" + suf, Vector3(0.22 * sx, 0.52, 0.0))
		_part(sh, tone, "UpperArm" + suf, Vector3.ZERO)
		var el := _node(sh, "Elbow" + suf, Vector3(0.0, -0.30, 0.0))
		_part(el, tone, "LowerArm" + suf, Vector3.ZERO)
		var wr := _node(el, "Wrist" + suf, Vector3(0.0, -0.27, 0.0))
		_part(wr, tone, "Hand" + suf, Vector3.ZERO)
		var hip := _node(r, "Hip" + suf, Vector3(0.10 * sx, 0.0, 0.0))
		_part(hip, tone, "UpperLeg" + suf, Vector3.ZERO)
		var kn := _node(hip, "Knee" + suf, Vector3(0.0, -0.42, 0.0))
		_part(kn, tone, "LowerLeg" + suf, Vector3.ZERO)
		var an := _node(kn, "Ankle" + suf, Vector3(0.0, -0.40, 0.0))
		_part(an, tone, "Foot" + suf, Vector3.ZERO)
	return p


func _node(parent: Node, n: String, pos: Vector3) -> Node3D:
	var x := Node3D.new()
	x.name = n
	x.position = pos
	parent.add_child(x)
	return x


func _part(parent: Node, tone: String, part: String, pos: Vector3) -> Node3D:
	var n := _inst(MESH_DIR % [tone, part], parent)
	n.name = part + "Mesh"
	n.position = pos
	return n


func _inst(path: String, parent: Node) -> Node3D:
	var ps: PackedScene = load(path)
	if ps == null:
		push_error("missing " + path)
		return _node(parent, "Missing", Vector3.ZERO)
	var n: Node3D = ps.instantiate()
	parent.add_child(n)
	return n


# ------------------------------------------------------------------------------------------------
# площадка
# ------------------------------------------------------------------------------------------------
func _build_stage() -> Node3D:
	var st := Node3D.new()
	st.name = "IntroStage"
	st.set_script(load(STAGE_SCRIPT))
	var arena := _inst("res://scenes/arena/scrap.tscn", st)
	arena.name = "Scrap"
	var hero := _inst(PUPPETS["light"]["out"], st)
	hero.name = "Hero"
	hero.set("player_color", HERO_COLOR)
	hero.set("eye_color", GOLD)
	var enemy := _inst(PUPPETS["dark"]["out"], st)
	enemy.name = "Enemy"
	enemy.set("player_color", ENEMY_COLOR)
	enemy.set("eye_color", ENEMY_EYE)
	enemy.set("core_energy", 1.2)
	_enemy_gear(enemy, st)
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.position = Vector3(0.0, 2.0, 8.0)
	cam.fov = 40.0
	cam.near = 0.03
	cam.far = 400.0
	cam.attributes = CameraAttributesPractical.new()
	st.add_child(cam)
	var ink := MeshInstance3D.new()
	ink.name = "Ink"
	var qm := QuadMesh.new()
	qm.size = Vector2(2.0, 2.0)
	ink.mesh = qm
	ink.position = Vector3(0.0, 0.0, -0.1)
	var sm := ShaderMaterial.new()
	sm.shader = load(INK_SHADER)
	ink.material_override = sm
	ink.extra_cull_margin = 16384.0
	ink.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ink.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	cam.add_child(ink)
	var fx := _node(st, "Fx", Vector3.ZERO)
	fx.add_child(_sparks())
	var dust := _inst("res://scenes/fx/dust_puff.tscn", fx)
	dust.name = "Dust"
	(dust as GPUParticles3D).emitting = false
	var shots := _node(st, "Shots", Vector3.ZERO)
	for s in _shot_table():
		shots.add_child(_shot(s, st))
	return st


func _enemy_gear(enemy: Node3D, owner_: Node) -> void:
	var head := enemy.get_node("Root/Neck/HeadMesh")
	var helmet := _inst(BITS % "Helmet", head)
	helmet.name = "Helmet"
	helmet.position = Vector3(0.0, 0.25, -0.01)
	helmet.rotation_degrees = Vector3(-8.0, 0.0, 0.0)
	helmet.scale = Vector3.ONE * 1.25
	helmet.owner = owner_
	var hand := enemy.get_node("Root/Shoulder_R/Elbow_R/Wrist_R/Hand_RMesh")
	var axe := _inst(BITS % "Axe_Old", hand)
	axe.name = "Axe"
	axe.position = Vector3(0.0, -0.09, 0.02)
	axe.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	axe.owner = owner_


func _sparks() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Sparks"
	p.emitting = false
	p.one_shot = true
	p.amount = 48
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0.0, 1.0, 0.4)
	m.spread = 80.0
	m.initial_velocity_min = 1.8
	m.initial_velocity_max = 4.5
	m.gravity = Vector3(0.0, -6.0, 0.0)
	m.damping_min = 1.0
	m.damping_max = 2.0
	m.scale_min = 0.6
	m.scale_max = 1.2
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.9, 0.6, 1.0))
	g.set_color(1, Color(1.0, 0.35, 0.05, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.07)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(4.0, 2.6, 1.2)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = mat
	p.draw_pass_1 = q
	return p


func _embers(n: String, extents: Vector3, amount: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = n
	p.amount = amount
	p.lifetime = 3.5
	p.preprocess = 3.5
	p.visibility_aabb = AABB(Vector3(-8, -2, -4), Vector3(16, 10, 8))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = extents
	m.direction = Vector3(0.2, 1.0, 0.0)
	m.spread = 25.0
	m.initial_velocity_min = 0.3
	m.initial_velocity_max = 1.1
	m.gravity = Vector3(0.0, 0.15, 0.0)
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 0.6
	m.turbulence_noise_scale = 2.0
	m.scale_min = 0.5
	m.scale_max = 1.3
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.75, 0.35, 0.0))
	g.add_point(0.15, Color(1.0, 0.6, 0.2, 1.0))
	g.set_color(g.get_point_count() - 1, Color(1.0, 0.3, 0.05, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.035)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = load(MOTE_TEX)
	mat.albedo_color = Color(3.0, 2.0, 1.0)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = mat
	p.draw_pass_1 = q
	return p


## Карта неба для кадров снизу вверх: слой неба параллакса (layer4_sky) крупно, поверх края квада Layer4Sky.
func _skycard(n: String, width: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var q := QuadMesh.new()
	q.size = Vector2(width, width / 2.28)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = load("res://assets/textures/parallax/scrap/layer4_sky.png")
	m.disable_fog = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _sun_disk(n: String, pos: Vector3, size: float, colour: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	mi.position = pos
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.12, Color(1, 1, 1, 1))
	g.add_point(0.2, Color(1, 1, 1, 0.35))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = gt
	m.albedo_color = colour
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = false
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ------------------------------------------------------------------------------------------------
# кадры
# ------------------------------------------------------------------------------------------------
func _shot(s: Dictionary, owner_: Node) -> Node3D:
	var n := Node3D.new()
	n.name = s["name"]
	n.set_script(load(SHOT_SCRIPT))
	for k in ["duration", "cam_ease", "hero_ease", "hero_move", "enemy_move", "enemy_ease", "hero_visible", "enemy_visible",
			"dof_far", "dof_far_transition", "dof_near", "dof_near_transition", "dof_amount", "exposure", "hide_fore_layer", "key_mult"]:
		if s.has(k):
			n.set(k, s[k])
	for k in ["hero_keys", "hero_params", "enemy_keys", "enemy_params", "events", "hide_nodes"]:
		if s.has(k):
			n.set(k, PackedStringArray(s[k]))
	_cam_node(n, "CamA", s["cam_a"])
	_cam_node(n, "CamB", s.get("cam_b", s["cam_a"]))
	for m in ["hero_a", "hero_b", "enemy_a", "enemy_b"]:
		if s.has(m):
			var v: Array = s[m]
			var mk := Marker3D.new()
			mk.name = ("Hero" if m.begins_with("hero") else "Enemy") + ("A" if m.ends_with("a") else "B")
			mk.position = v[0]
			mk.rotation_degrees = Vector3(0.0, v[1], v[2] if v.size() > 2 else 0.0)
			n.add_child(mk)
	var props := _node(n, "Props", Vector3.ZERO)
	for pr in s.get("props", []):
		var node: Node3D
		match pr.get("kind", "glb"):
			"glb":
				node = _inst(pr["path"], props)
			"sun":
				node = _sun_disk(pr["name"], pr["pos"], pr.get("size", 3.0), pr.get("color", Color(3, 2.2, 1.4)))
				props.add_child(node)
			"embers":
				node = _embers(pr["name"], pr.get("extents", Vector3(3, 0.3, 1)), pr.get("amount", 80))
				props.add_child(node)
			"skycard":
				node = _skycard(pr["name"], pr.get("size", 150.0))
				props.add_child(node)
				node.look_at_from_position(pr["pos"], pr["look_from"], Vector3.UP)
				node.rotate_object_local(Vector3.UP, PI)
			"group":
				node = _node(props, pr["name"], pr.get("pos", Vector3.ZERO))
				for c in pr["children"]:
					var cn := _inst(c[0], node)
					cn.position = c[1]
					cn.rotation_degrees = c[2] if c.size() > 2 else Vector3.ZERO
					cn.scale = Vector3.ONE * (c[3] if c.size() > 3 else 1.0)
			"arm":
				node = _node(props, pr["name"], Vector3.ZERO)
				var la := _inst(MESH_DIR % ["dark", "LowerArm_R"], node)
				la.name = "LowerArm"
				var hd := _inst(MESH_DIR % ["dark", "Hand_R"], node)
				hd.name = "Hand"
				hd.position = Vector3(0.0, -0.27, 0.0)
		node.name = pr["name"]
		if pr.has("pos"):
			node.position = pr["pos"]
		if pr.has("rot"):
			node.rotation_degrees = pr["rot"]
		if pr.has("scale"):
			node.scale = Vector3.ONE * float(pr["scale"])
		if pr.has("grip"):
			node.set_meta("grip", pr["grip"])
	var lights := _node(n, "Lights", Vector3.ZERO)
	for l in s.get("lights", []):
		var ln: Light3D
		if l.get("type", "spot") == "spot":
			var sp := SpotLight3D.new()
			sp.spot_range = l.get("range", 8.0)
			sp.spot_angle = l.get("angle", 30.0)
			sp.spot_attenuation = 0.8
			ln = sp
		else:
			var om := OmniLight3D.new()
			om.omni_range = l.get("range", 4.0)
			ln = om
		ln.name = l["name"]
		ln.light_color = l.get("color", Color(1, 0.85, 0.7))
		ln.light_energy = l.get("energy", 2.0)
		ln.shadow_enabled = l.get("shadow", false)
		lights.add_child(ln)
		ln.position = l["pos"]
		if l.has("look"):
			ln.look_at_from_position(l["pos"], l["look"], Vector3.UP)
	return n


## Точка за объектом на луче «камера → объект» (солнце позади поднятой руки).
func _behind(cam: Vector3, target: Vector3, dist: float) -> Vector3:
	return cam + (target - cam).normalized() * dist


func _cam_node(parent: Node3D, n: String, c: Array) -> void:
	var cam := Camera3D.new()
	cam.name = n
	cam.fov = c[2]
	cam.current = false
	parent.add_child(cam)
	cam.look_at_from_position(c[0], c[1], Vector3.UP)
	if c.size() > 3:
		cam.rotate_object_local(Vector3.BACK, deg_to_rad(c[3]))  # крен (голландский угол)


## Раскадровка (docs/plan-demo/INTRO_COMIC.md). cam_*: [позиция, точка взгляда, fov, крен°]; hero_*/enemy_*: [позиция, рыск°].
func _shot_table() -> Array:
	var shots: Array = []
	# --- 01 Свалка на закате, сверху сыплется хлам -------------------------------------------------------------
	var rain := []
	var bits := ["Gear_Medium", "Scrap_Board", "Doll_Head_Sad", "Doll_Limb_Upper", "Gear_Small", "Chain_Segment",
		"Doll_Hand", "Pipe_Piece", "Doll_Head_Scared", "Gear_Large", "Scrap_Board", "Doll_Limb_Lower", "Rivet_Plate",
		"Doll_Foot", "Gear_Medium", "Doll_Head_Cracked"]
	for i in bits.size():
		var fx := -21.0 + fmod(float(i) * 3.7, 16.0)
		var fz := -4.0 + fmod(float(i) * 1.9, 5.0)
		rain.append([BITS % bits[i], Vector3(fx, 14.0 + fmod(float(i) * 2.3, 6.0), fz), Vector3(i * 20, i * 33, i * 47), 1.4])
	shots.append({"name": "Shot01", "duration": 3.6, "hero_visible": false,
		"cam_a": [Vector3(-11.0, 9.0, 15.0), Vector3(-10.0, 4.5, -20.0), 52.0],
		"cam_b": [Vector3(-12.5, 5.5, 12.5), Vector3(-11.0, 3.0, -20.0), 50.0],
		"events": ["0:rain:Rain:5.5"],
		"props": [{"kind": "group", "name": "Rain", "children": rain}]})
	# --- 02 Лежит в куче, Ядро мерцает: UNKNOWN CORE -----------------------------------------------------------
	shots.append({"name": "Shot02", "duration": 3.0, "hide_fore_layer": true,
		"cam_a": [Vector3(-17.15, 2.35, 1.8), Vector3(-17.45, 1.22, 0.42), 40.0, -8.0],
		"cam_b": [Vector3(-17.25, 2.1, 1.5), Vector3(-17.48, 1.22, 0.44), 40.0, -8.0],
		"hero_a": [HEAP + Vector3(0.1, -0.06, 0.0), 0.0],
		"hero_keys": ["0:lying", "2.2:lying", "2.55:lying_twitch"],
		"hero_params": ["0:core=0.15,flicker=1", "1.6:core=0.5,flicker=1", "2.4:core=1,flicker=0"],
		"events": NO_ARM,
		"dof_far": 2.2, "dof_far_transition": 2.0, "dof_amount": 0.14,
		"props": [
			{"path": BITS % "Doll_Head_Sad", "name": "HeadA", "pos": HEAP + Vector3(0.25, 0.05, 0.75), "rot": Vector3(0, 30, 10)},
			{"path": BITS % "Gear_Medium", "name": "GearA", "pos": HEAP + Vector3(-1.0, 0.12, 0.6), "rot": Vector3(70, 0, 20)},
			{"path": BITS % "Doll_Limb_Upper", "name": "LimbA", "pos": HEAP + Vector3(-0.2, 0.1, 0.85), "rot": Vector3(80, 40, 0)},
			{"path": BITS % "Doll_Head_Cracked", "name": "HeadB", "pos": HEAP + Vector3(-1.1, 0.1, -0.1), "rot": Vector3(-20, -40, 0)},
			{"path": BITS % "Gear_Small", "name": "GearB", "pos": HEAP + Vector3(-0.35, 0.2, 0.75), "rot": Vector3(60, 0, 0)},
		]})
	# --- 03 Резко села: глаза загорелись, «!» ---------------------------------------------------------------------
	shots.append({"name": "Shot03", "duration": 2.4, "hide_fore_layer": true,
		"cam_a": [HEAP + Vector3(0.1, 0.45, 2.45), HEAP + Vector3(0.0, 0.62, 0.0), 36.0],
		"cam_b": [HEAP + Vector3(0.08, 0.45, 2.05), HEAP + Vector3(0.0, 0.64, 0.0), 36.0],
		"cam_ease": 0.4,
		"hero_a": [HEAP + Vector3(0.0, 0.05, 0.0), 0.0],
		"hero_keys": ["0:lying_twitch", "0.28:sit_up"],
		"hero_params": ["0:core=1,eye=0", "0.3:eye=0", "0.45:eye=1"],
		"events": NO_ARM + ["0.3:shake:0.05:0.3", "0.3:dust:hero:Feet"],
		"dof_far": 3.5, "dof_far_transition": 3.0, "dof_amount": 0.12,
		"props": [
			{"path": BITS % "Doll_Head_Sad", "name": "HeadA", "pos": HEAP + Vector3(0.6, -0.05, 0.3), "rot": Vector3(0, 30, 10)},
			{"path": BITS % "Gear_Medium", "name": "GearA", "pos": HEAP + Vector3(-0.5, -0.02, 0.45), "rot": Vector3(70, 0, 20)},
		]})
	# --- 04 Спиной к камере, смотрит на Башню: RETURN TO THE WORKSHOP -------------------------------------------
	shots.append({"name": "Shot04", "duration": 3.2,
		"cam_a": [Vector3(-19.2, 1.05, 2.5), Vector3(-8.0, 7.6, -9.6), 50.0],
		"cam_b": [Vector3(-18.9, 1.0, 2.1), Vector3(-8.0, 8.2, -9.6), 50.0],
		"hero_a": [HEAP, 132.0],
		"hero_keys": ["0:stand_look"],
		"hero_params": ["0:core=1,eye=1"],
		"events": NO_ARM,
		"hide_nodes": ["Back/BannerFrame_1"],
		"props": [{"kind": "skycard", "name": "SkyCard", "pos": _behind(Vector3(-19.0, 1.0, 2.3), Vector3(-8.0, 7.9, -9.6), 95.0), "size": 250.0, "look_from": Vector3(-19.0, 1.0, 2.3)},
			{"kind": "sun", "name": "SunGlow", "pos": _behind(Vector3(-19.0, 1.0, 2.3), Vector3(-6.0, 12.5, -9.6), 90.0), "size": 40.0, "color": Color(1.9, 1.3, 0.8)}],
		"lights": [{"name": "Rim", "pos": HEAP + Vector3(3.0, 4.0, -3.0), "look": HEAP + Vector3(0, 1.4, 0), "color": Color(1.0, 0.72, 0.42), "energy": 6.0, "range": 8.0, "angle": 25.0}]})
	# --- 05 BONK: запоздавшая бочка надевается на голову ---------------------------------------------------------
	shots.append({"name": "Shot05", "duration": 2.2, "hide_fore_layer": true,
		"cam_a": [HEAP + Vector3(0.3, 1.25, 2.9), HEAP + Vector3(0.0, 1.15, 0.2), 40.0],
		"cam_b": [HEAP + Vector3(0.25, 1.2, 2.6), HEAP + Vector3(0.0, 1.1, 0.2), 40.0],
		"hero_a": [HEAP, 0.0],
		"hero_keys": ["0:stand_look", "0.55:stand_look", "0.68:bonk"],
		"hero_params": ["0:core=1,eye=1"],
		"events": NO_ARM + ["0.6:drop:Barrel:0.45:4.0", "0.6:shake:0.12:0.35", "0.6:dust:hero:Head"],
		"props": [{"path": PROPS % "Wooden_Barrel", "name": "Barrel", "pos": Vector3(-17.03, 2.14, 0.47), "rot": Vector3(0, 0, 10), "scale": 0.72}]})
	# --- 06 Тянется в кучу рук-ног (ровный пол левее кучи) ------------------------------------------------------------
	shots.append({"name": "Shot06", "duration": 2.3, "hide_fore_layer": true,
		"cam_a": [FLOOR_A + Vector3(0.95, 0.85, 1.45), FLOOR_A + Vector3(0.4, 0.55, 0.55), 40.0],
		"cam_b": [FLOOR_A + Vector3(1.15, 1.3, 2.35), FLOOR_A + Vector3(0.25, 1.1, 0.4), 42.0],
		"hero_a": [FLOOR_A, 30.0],
		"hero_keys": ["0:reach", "1.3:reach", "2.0:pull"],
		"hero_params": ["0:core=1,eye=1"],
		"events": NO_ARM + ["1.3:hold:LooseArm:Hand_L"],
		"dof_far": 2.6, "dof_far_transition": 2.5, "dof_amount": 0.14,
		"props": [
			{"path": BODIES % "Puppet_Limb_Pile", "name": "LimbPile", "pos": FLOOR_A + Vector3(0.55, 0.0, 0.55), "rot": Vector3(0, -20, 0), "scale": 0.7},
			{"path": BITS % "Doll_Head_Scared", "name": "HeadA", "pos": FLOOR_A + Vector3(1.0, 0.1, 0.9), "rot": Vector3(0, -30, 0)},
			{"path": BITS % "Gear_Large", "name": "GearA", "pos": FLOOR_A + Vector3(-0.4, 0.05, 0.9), "rot": Vector3(80, 0, 10)},
			{"path": BITS % "Doll_Foot", "name": "FootA", "pos": FLOOR_A + Vector3(0.9, 0.05, 0.2), "rot": Vector3(0, 60, 0)},
			{"kind": "arm", "name": "LooseArm", "pos": FLOOR_A + Vector3(0.3, 0.55, 0.75), "rot": Vector3(80, 60, 0), "grip": GRIP},
		]})
	# --- 07 Подняла деталь к солнцу -------------------------------------------------------------------------------
	shots.append({"name": "Shot07", "duration": 2.4, "hide_fore_layer": true,
		"cam_a": [FLOOR_A + Vector3(0.75, 0.3, 2.4), FLOOR_A + Vector3(0.1, 1.75, -0.3), 48.0, 6.0],
		"cam_b": [FLOOR_A + Vector3(0.7, 0.25, 2.1), FLOOR_A + Vector3(0.1, 1.85, -0.3), 48.0, 6.0],
		"hero_a": [FLOOR_A, 15.0],
		"hero_keys": ["0:pull", "0.35:hold_up"],
		"hero_params": ["0:core=1,eye=1"],
		"events": NO_ARM + ["0:hold:LooseArm:Hand_L"],
		"props": [
			{"kind": "arm", "name": "LooseArm", "pos": FLOOR_A, "grip": GRIP},
			{"kind": "skycard", "name": "SkyCard", "pos": _behind(FLOOR_A + Vector3(0.7, 0.25, 2.1), FLOOR_A + Vector3(0.1, 1.85, -0.3), 95.0), "size": 190.0, "look_from": FLOOR_A + Vector3(0.7, 0.25, 2.1)},
			{"kind": "sun", "name": "SunGlow", "pos": _behind(FLOOR_A + Vector3(0.7, 0.25, 2.1), FLOOR_A + Vector3(0.38, 2.15, 0.25), 40.0), "size": 12.0, "color": Color(2.6, 1.8, 1.0)},
		],
		"lights": [{"name": "Rim", "pos": FLOOR_A + Vector3(-1.2, 3.5, -2.5), "look": FLOOR_A + Vector3(0, 1.4, 0), "color": Color(1.0, 0.72, 0.42), "energy": 7.0, "range": 7.0, "angle": 28.0}]})
	# --- 08 CLICK: прикрутила чужое предплечье ----------------------------------------------------------------------
	shots.append({"name": "Shot08", "duration": 2.3, "hide_fore_layer": true,
		"cam_a": [FLOOR_A + Vector3(-0.45, 1.5, 1.85), FLOOR_A + Vector3(-0.2, 1.42, 0.3), 38.0, -5.0],
		"cam_b": [FLOOR_A + Vector3(-0.4, 1.5, 1.6), FLOOR_A + Vector3(-0.22, 1.45, 0.3), 38.0, -5.0],
		"hero_a": [FLOOR_A, 0.0],
		"hero_keys": ["0:attach", "0.85:attach", "1.25:attach_done"],
		"hero_params": ["0:core=0.7,eye=1", "0.8:core=0.7", "0.95:core=1.0"],
		"events": DARK_ARM + ["0:hero_hide:LowerArm_R", "0:hero_hide:Hand_R", "0:hold:LooseArm:Hand_L",
			"0.85:hide:LooseArm", "0.85:hero_show:LowerArm_R", "0.85:hero_show:Hand_R",
			"0.85:sparks:hero:Elbow_R", "0.85:shake:0.05:0.25"],
		"dof_far": 2.2, "dof_far_transition": 2.0, "dof_amount": 0.14,
		"props": [{"kind": "arm", "name": "LooseArm", "pos": FLOOR_A, "grip": GRIP}]})
	# --- 09 Летит над настилами к флагам короны ---------------------------------------------------------------------
	shots.append({"name": "Shot09", "duration": 2.8,
		"cam_a": [Vector3(-6.6, 6.1, 4.2), Vector3(-4.6, 5.6, -2.0), 44.0],
		"cam_b": [Vector3(-5.0, 6.0, 3.8), Vector3(-3.4, 5.7, -2.0), 44.0],
		"hero_a": [Vector3(-7.2, 5.1, 0.4), 0.0], "hero_b": [Vector3(-3.4, 5.6, 0.4), 0.0],
		"hero_ease": 1.0,
		"hero_keys": ["0:hover"],
		"hero_params": ["0:core=1,eye=1"],
		"events": DARK_ARM})
	# --- 10 Арена: сверху падает Разборщик -----------------------------------------------------------------------
	shots.append({"name": "Shot10", "duration": 2.8, "enemy_visible": true,
		"cam_a": [Vector3(2.45, 1.15, 5.9), Vector3(2.45, 1.05, 0.0), 40.0],
		"cam_b": [Vector3(2.45, 1.1, 5.4), Vector3(2.5, 1.05, 0.0), 40.0],
		"hero_a": [Vector3(ARENA_X, 0.0, 0.0), 0.0],
		"enemy_a": [Vector3(ENEMY_X, 3.5, 0.0), -10.0], "enemy_b": [Vector3(ENEMY_X, 0.0, 0.0), -10.0],
		"enemy_move": Vector2(0.15, 0.55), "enemy_ease": 2.2,
		"hero_keys": ["0:stance"],
		"hero_params": ["0:core=1,eye=1"],
		"enemy_keys": ["0:scrapling_swing", "0.55:scrapling_swing", "0.9:scrapling_idle"],
		"enemy_params": ["0:eye=1,core=0.6"],
		"events": DARK_ARM + ["0.55:shake:0.12:0.35", "0.55:dust:enemy:Feet"],
		"props": [{"kind": "embers", "name": "Embers", "pos": Vector3(2.5, 0.2, -0.5), "extents": Vector3(4.0, 0.2, 1.5), "amount": 60}]})
	# --- 11 Крупно: глаза-щёлки, кулаки ----------------------------------------------------------------------------
	shots.append({"name": "Shot11", "duration": 2.0, "enemy_visible": true, "hide_fore_layer": true,
		"cam_a": [Vector3(ARENA_X + 0.75, 1.36, 1.05), Vector3(ARENA_X + 0.12, 1.52, 0.15), 34.0, -6.0],
		"cam_b": [Vector3(ARENA_X + 0.65, 1.38, 0.9), Vector3(ARENA_X + 0.12, 1.53, 0.15), 32.0, -6.0],
		"hero_a": [Vector3(ARENA_X, 0.0, 0.0), 0.0],
		"enemy_a": [Vector3(ENEMY_X, 0.0, 0.0), -10.0],
		"hero_keys": ["0:stance"],
		"hero_params": ["0:core=1,eye=1,squint=0", "0.5:squint=0", "0.8:squint=1"],
		"enemy_keys": ["0:scrapling_idle"],
		"enemy_params": ["0:eye=1,core=0.6"],
		"events": DARK_ARM,
		"dof_far": 1.4, "dof_far_transition": 2.5, "dof_amount": 0.16})
	# --- 12 BAM: рывок и удар, враг разлетается (замедленно — застывает в воздухе) ----------------------------------
	shots.append({"name": "Shot12", "duration": 1.7, "enemy_visible": true,
		"cam_a": [Vector3(2.95, 1.5, 2.7), Vector3(3.2, 1.35, 0.0), 50.0, 10.0],
		"cam_b": [Vector3(3.1, 1.5, 2.35), Vector3(3.3, 1.38, 0.0), 50.0, 10.0],
		"hero_a": [Vector3(ARENA_X, 0.0, 0.0), 0.0], "hero_b": [Vector3(ENEMY_X - 1.0, -0.12, 0.0), 0.0],
		"hero_move": Vector2(0.0, 0.45), "hero_ease": 0.5,
		"enemy_a": [Vector3(ENEMY_X, 0.0, 0.0), -10.0],
		"hero_keys": ["0:stance", "0.22:punch"],
		"hero_params": ["0:core=1,eye=1,squint=1"],
		"enemy_keys": ["0:scrapling_swing"],
		"enemy_params": ["0:eye=1,core=0.6"],
		"events": DARK_ARM + ["0.45:shatter:enemy:1,0.5:4.5:0.3", "0.45:shake:0.25:0.5", "0.45:sparks:enemy:Chest"],
		"props": [{"kind": "embers", "name": "Embers", "pos": Vector3(3.0, 0.2, -0.5), "extents": Vector3(3.0, 0.2, 1.5), "amount": 50}]})
	# --- 13 После боя: парит над обломками, угли -----------------------------------------------------------------
	shots.append({"name": "Shot13", "duration": 3.2, "enemy_visible": true,
		"cam_a": [Vector3(2.0, 0.32, 2.6), Vector3(2.55, 1.4, 0.0), 56.0, -4.0],
		"cam_b": [Vector3(1.95, 0.4, 3.1), Vector3(2.55, 1.5, 0.0), 56.0, -4.0],
		"hero_a": [Vector3(2.4, 0.35, 0.0), 0.0], "hero_b": [Vector3(2.4, 0.5, 0.0), 0.0],
		"enemy_a": [Vector3(ENEMY_X, 0.0, 0.0), -10.0],
		"hero_keys": ["0:victory"],
		"hero_params": ["0:core=1,eye=1,squint=0.4"],
		"enemy_keys": ["0:scrapling_swing"],
		"events": DARK_ARM + ["-3.0:shatter:enemy:0.3,1:1.6"],
		"props": [{"kind": "embers", "name": "Embers", "pos": Vector3(2.5, 0.2, -0.5), "extents": Vector3(5.0, 0.2, 2.0), "amount": 90},
			{"kind": "skycard", "name": "SkyCard", "pos": _behind(Vector3(2.0, 0.35, 2.8), Vector3(2.55, 1.45, 0.0), 95.0), "size": 250.0, "look_from": Vector3(2.0, 0.35, 2.8)}]})
	return shots


# ------------------------------------------------------------------------------------------------
# страница комикса
# ------------------------------------------------------------------------------------------------
## Раскладка: три строки как в референсе (4 / 5 / 4 панели), межпанельные просветы — центры (x сверху, x снизу);
## наклонные просветы во второй строке и «падающая» панель удара в третьей.
func _rows() -> Array:
	return [
		{"y0": 64.0, "y1": 744.0, "seps": [[1157.0, 1157.0], [1943.0, 1943.0], [2769.0, 2769.0]]},
		{"y0": 770.0, "y1": 1390.0, "seps": [[927.0, 867.0], [1533.0, 1593.0], [2259.0, 2199.0], [2925.0, 2985.0]]},
		{"y0": 1416.0, "y1": 2096.0, "seps": [[1017.0, 1017.0], [1753.0, 1853.0], [2839.0, 2939.0]]},
	]


## Надписи панелей: kind, at (время кадра), anchor/frac, offset, text, size, angle и цвета (см. ComicLetter).
func _panel_letters() -> Dictionary:
	return {
		1: [{"kind": "caption", "at": 0.5, "frac": Vector2(0.24, 0.1), "text": "SECTOR 0 // THE SCRAP", "size": 34.0, "fill": TOWER},
			{"kind": "caption", "at": 1.9, "frac": Vector2(0.72, 0.9), "text": "DISPOSAL CYCLE: COMPLETE", "size": 34.0, "fill": TOWER}],
		2: [{"kind": "small", "at": 0.7, "anchor": "hero:Chest", "offset": Vector2(120, -70), "text": "tk... tk...", "size": 58.0, "angle_deg": -10.0,
				"fill": Color(1.0, 0.85, 0.5)},
			{"kind": "caption", "at": 1.1, "frac": Vector2(0.5, 0.1), "text": "CORE SIGNAL DETECTED", "size": 32.0, "fill": TOWER},
			{"kind": "caption", "at": 2.2, "frac": Vector2(0.5, 0.9), "text": "UNKNOWN CORE.", "size": 38.0, "fill": ALARM}],
		3: [{"kind": "emanata", "at": 0.3, "anchor": "hero:Head", "radius": 105.0, "count": 11},
			{"kind": "sfx", "at": 0.32, "anchor": "hero:Head", "offset": Vector2(175, -105), "text": "!", "size": 190.0, "angle_deg": 8.0}],
		4: [{"kind": "caption", "at": 0.9, "frac": Vector2(0.5, 0.11), "text": "RETURN TO THE WORKSHOP.", "size": 36.0, "fill": TOWER}],
		5: [{"kind": "burst", "at": 0.6, "anchor": "prop:Barrel", "offset": Vector2(-200, -50), "radius": 150.0, "count": 9, "fill": Color(1.0, 0.95, 0.75)},
			{"kind": "sfx", "at": 0.6, "anchor": "prop:Barrel", "offset": Vector2(-200, -50), "text": "BONK!", "size": 150.0, "angle_deg": -14.0},
			{"kind": "stars", "at": 0.8, "anchor": "prop:Barrel", "offset": Vector2(0, -40), "radius": 120.0, "count": 4, "fill": Color(1.0, 0.86, 0.2)}],
		6: [{"kind": "small", "at": 1.3, "anchor": "hero:Hand_L", "offset": Vector2(110, -90), "text": "shhk!", "size": 64.0, "angle_deg": -8.0,
				"fill": Color(1.0, 0.9, 0.7)}],
		8: [{"kind": "burst", "at": 0.85, "anchor": "hero:Elbow_R", "radius": 85.0, "count": 8, "fill": Color(1.0, 0.9, 0.5)},
			{"kind": "sfx", "at": 0.85, "anchor": "hero:Elbow_R", "offset": Vector2(-60, -170), "text": "CLICK!", "size": 120.0, "angle_deg": -10.0,
				"fill": Color(0.86, 0.97, 1.0), "outline2": Color(0.15, 0.45, 0.85)},
			{"kind": "caption", "at": 1.45, "frac": Vector2(0.5, 0.9), "text": "COMPONENT ACCEPTED.", "size": 30.0, "fill": TOWER}],
		9: [{"kind": "caption", "at": 0.8, "frac": Vector2(0.4, 0.1), "text": "NEW CONTESTANT DETECTED", "size": 32.0, "fill": TOWER}],
		10: [{"kind": "sfx", "at": 0.55, "anchor": "enemy:Feet", "offset": Vector2(80, -30), "text": "CLANK!", "size": 120.0, "angle_deg": 10.0,
				"fill": Color(0.92, 0.9, 0.84), "outline2": Color(0.5, 0.42, 0.34)},
			{"kind": "caption", "at": 1.3, "frac": Vector2(0.5, 0.1), "text": "BOUT 001 :: FIGHT!", "size": 34.0, "fill": TOWER}],
		11: [{"kind": "focus", "clip": true, "at": 0.0, "anchor": "hero:Head", "radius": 250.0, "count": 70}],
		12: [{"kind": "speed", "clip": true, "at": 0.0, "until": 0.45, "frac": Vector2(0.5, 0.5), "count": 42, "fill": Color(1, 1, 1)},
			{"kind": "focus", "clip": true, "at": 0.45, "anchor": "hero:Hand_R", "radius": 190.0, "count": 80},
			{"kind": "burst", "at": 0.45, "anchor": "hero:Hand_R", "offset": Vector2(40, -10), "radius": 120.0, "count": 10, "fill": Color(1.0, 0.95, 0.7)},
			{"kind": "sfx", "at": 0.45, "frac": Vector2(0.64, 0.2), "text": "BAM!", "size": 210.0, "angle_deg": -8.0}],
		13: [{"kind": "caption", "at": 0.9, "frac": Vector2(0.5, 0.1), "text": "WINNER: UNKNOWN CORE", "size": 34.0, "fill": TOWER}],
	}


func _build_page() -> Node2D:
	var root_ := Node2D.new()
	root_.name = "IntroComic"
	root_.set_script(load(COMIC_SCRIPT))
	root_.set("next_scene", NEXT_SCENE)
	root_.set("page_size", PAGE)
	var bg := Polygon2D.new()
	bg.name = "Bg"
	bg.polygon = PackedVector2Array([Vector2(-3000, -3000), Vector2(PAGE.x + 3000, -3000), Vector2(PAGE.x + 3000, PAGE.y + 3000), Vector2(-3000, PAGE.y + 3000)])
	bg.color = Color(0.045, 0.037, 0.033)
	root_.add_child(bg)
	var pg := Node2D.new()
	pg.name = "Page"
	root_.add_child(pg)
	var letters := _panel_letters()
	var idx := 0
	var holds := {1: 0.6, 2: 0.7, 4: 0.8, 8: 0.6, 9: 0.5, 10: 0.6, 13: 0.9}
	var fx := {5: {"impact_at": 0.6, "impact_strength": 22.0}, 8: {"impact_at": 0.85, "impact_strength": 12.0},
		10: {"impact_at": 0.55, "impact_strength": 20.0}, 12: {"flash_at": 0.45, "impact_at": 0.45, "impact_strength": 42.0},
		3: {"impact_at": 0.3, "impact_strength": 10.0}}
	var sounds := {1: ["0.0:rain"], 2: ["0.7:tk"], 3: ["0.3:stab"], 5: ["0.6:bonk"], 6: ["1.3:scrape"], 8: ["0.85:click"],
		9: ["0.05:whoosh"], 10: ["0.55:clank"], 12: ["0.45:bam:-8", "0.5:shatter:-6"]}
	var rows := _rows()
	for r in rows.size():
		var row: Dictionary = rows[r]
		var seps: Array = row["seps"]
		var y0: float = row["y0"]
		var y1: float = row["y1"]
		for k in seps.size() + 1:
			idx += 1
			var lt: float = MARGIN if k == 0 else seps[k - 1][0] + GUTTER * 0.5
			var lb: float = MARGIN if k == 0 else seps[k - 1][1] + GUTTER * 0.5
			var rt: float = PAGE.x - MARGIN if k == seps.size() else seps[k][0] - GUTTER * 0.5
			var rb: float = PAGE.x - MARGIN if k == seps.size() else seps[k][1] - GUTTER * 0.5
			var poly := PackedVector2Array([Vector2(lt, y0), Vector2(rt, y0), Vector2(rb, y1), Vector2(lb, y1)])
			var pn := Node2D.new()
			pn.name = "Panel%02d" % idx
			pn.set_script(load(PANEL_SCRIPT))
			pn.set("polygon", poly)
			pn.set("shot", idx)
			pn.set("row", r)
			pn.set("hold", holds.get(idx, 0.4))
			for key in fx.get(idx, {}):
				pn.set(key, fx[idx][key])
			pn.set("sounds", PackedStringArray(sounds.get(idx, [])))
			pg.add_child(pn)
			var art := Polygon2D.new()
			art.name = "Art"
			art.polygon = poly
			art.color = Color(0.22, 0.19, 0.17)
			pn.add_child(art)
			var clip := Node2D.new()
			clip.name = "Clip"
			art.add_child(clip)
			var fr := Line2D.new()
			fr.name = "Frame"
			fr.points = poly
			fr.closed = true
			fr.width = 7.0
			fr.default_color = Color(0.03, 0.025, 0.02)
			pn.add_child(fr)
			var lt_node := Node2D.new()
			lt_node.name = "Letters"
			pn.add_child(lt_node)
			var b := Rect2(poly[0], Vector2.ZERO)
			for pt in poly:
				b = b.expand(pt)
			print("panel %02d bbox %s aspect %.2f" % [idx, b, b.size.x / b.size.y])
			var li := 0
			for L in letters.get(idx, []):
				li += 1
				var ln := Node2D.new()
				ln.name = "%s%d" % [String(L["kind"]).capitalize(), li]
				ln.set_script(load(LETTER_SCRIPT))
				for key in L:
					if key != "clip":
						ln.set(key, L[key])
				# положение для редактора: по доле bbox (якорные уточнятся при проигрывании)
				ln.position = b.position + (L.get("frac", Vector2(0.5, 0.5)) as Vector2) * b.size + (L.get("offset", Vector2.ZERO) as Vector2)
				(clip if L.get("clip", false) else lt_node).add_child(ln)
	var title_n := Node2D.new()
	title_n.name = "Title"
	title_n.set_script(load(TITLE_SCRIPT))
	title_n.position = PAGE * 0.5
	title_n.visible = false
	root_.add_child(title_n)
	var cam := Camera2D.new()
	cam.name = "Camera"
	cam.position = PAGE * 0.5
	cam.zoom = Vector2.ONE * 0.5
	root_.add_child(cam)
	var svp := SubViewport.new()
	svp.name = "StageViewport"
	svp.size = Vector2i(1280, 720)
	svp.own_world_3d = true
	svp.msaa_3d = Viewport.MSAA_2X
	svp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	svp.audio_listener_enable_3d = false
	root_.add_child(svp)
	var hud := CanvasLayer.new()
	hud.name = "Hud"
	hud.layer = 10
	root_.add_child(hud)
	var flash := ColorRect.new()
	flash.name = "Flash"
	flash.color = Color(1.0, 0.97, 0.9, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(flash)
	var fade := ColorRect.new()
	fade.name = "Fade"
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(fade)
	var cold := Label.new()
	cold.name = "ColdOpen"
	cold.set_anchors_preset(Control.PRESET_FULL_RECT)
	cold.offset_left = 200.0
	cold.offset_top = 330.0
	cold.offset_right = -160.0
	cold.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var cf := SystemFont.new()
	cf.font_names = PackedStringArray(["Menlo", "SF Mono", "Consolas", "Courier New"])
	cf.font_weight = 700
	cold.add_theme_font_override("font", cf)
	cold.add_theme_font_size_override("font_size", 38)
	cold.add_theme_color_override("font_color", TOWER)
	cold.add_theme_constant_override("line_spacing", 14)
	cold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(cold)
	var skip := Control.new()
	skip.name = "Skip"
	skip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skip.offset_left = -640.0
	skip.offset_top = -86.0
	skip.offset_right = -36.0
	skip.offset_bottom = -30.0
	skip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(skip)
	var lbl := Label.new()
	lbl.name = "Label"
	lbl.text = "HOLD SPACE / CLICK TO SKIP   ·   TAP — NEXT"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl.offset_bottom = 30.0
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Menlo", "Consolas", "Courier New"])
	sf.font_weight = 700
	lbl.add_theme_font_override("font", sf)
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.5, 0.75))
	skip.add_child(lbl)
	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.show_percentage = false
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -8.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.72, 0.28)
	bar.add_theme_stylebox_override("fill", sb)
	var sbb := StyleBoxFlat.new()
	sbb.bg_color = Color(1, 1, 1, 0.08)
	bar.add_theme_stylebox_override("background", sbb)
	skip.add_child(bar)
	return root_
