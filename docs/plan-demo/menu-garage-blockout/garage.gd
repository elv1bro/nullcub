extends Node3D
## Болванка главного меню «Гараж + телевизор» (вариант «Эфир NULL Fighting» в тёмном боксе бойца).
## Моделей нет: комната и предметы из примитивов, цвет = роль материала. Слева сцена, справа меню.
## Каждый пункт меню — своя точка камеры в гараже; телевизор показывает эфир под пункт и момент истории.
## Отдельный маленький проект (не часть godot/): docs/plan-demo/menu-garage-blockout. Описание — docs/plan-demo/MENU_GARAGE.md.
## Запуск (из этой папки; нужно окно, headless не рендерит):
##   godot --path . --resolution 1600x900 -- shots=all out=/abs/dir       кадры garage-<имя>.png
##   godot --path . --resolution 1280x720 -- video=1 out=/abs/frames      кадры перелётов f0000.png… → ffmpeg
##   doll=0 — без куклы (ящик остаётся пустым)

const ROOM_W := 9.0
const ROOM_D := 7.0
const ROOM_H := 4.0
const SCREEN_W := 768
const SCREEN_H := 576

## Кадры: pos — камера, subj — что в кадре, frac — где по ширине экрана стоит subj (меню справа → 0.3),
## menu — какой пункт в фокусе, tv — что идёт по телевизору, focus — какая зона светится, sub — субтитр эфира.
const SHOTS := {
	"title": {"pos": Vector3(2.6, 1.75, 3.3), "subj": Vector3(-0.6, 1.2, -2.2), "frac": 0.33, "fov": 50.0,
		"menu": "title", "tv": "live", "focus": "",
		"sub": "N0:  …и Клёпа улетает в мембрану! Мембрана — один, Клёпа — ноль!"},
	"story": {"pos": Vector3(0.0, 1.45, 1.1), "subj": Vector3(-0.33, 1.38, -2.56), "frac": 0.36, "fov": 40.0,
		"menu": "ИСТОРИЯ", "tv": "opponent", "focus": "tv",
		"sub": "N0:  Следующий бой — Гайка. Дерётся грязно. Ну, как грязно — смазкой."},
	"quick": {"pos": Vector3(1.3, 1.65, 1.6), "subj": Vector3(-4.3, 1.45, 0.25), "frac": 0.33, "fov": 50.0,
		"menu": "БЫСТРЫЙ БОЙ", "tv": "quick", "focus": "gate", "sub": ""},
	"workshop": {"pos": Vector3(-0.4, 1.7, 0.9), "subj": Vector3(-3.15, 1.15, -2.55), "frac": 0.33, "fov": 50.0,
		"menu": "МАСТЕРСКАЯ", "tv": "build", "focus": "bench", "sub": ""},
	"trophies": {"pos": Vector3(1.7, 1.6, 0.9), "subj": Vector3(4.35, 1.5, -0.9), "frac": 0.32, "fov": 46.0,
		"menu": "ТРОФЕИ", "tv": "replay", "focus": "shelf",
		"sub": "N0:  Повтор! Следите за головой Полена. Нет, выше. Ещё выше."},
	"settings": {"pos": Vector3(1.0, 1.75, -0.5), "subj": Vector3(3.35, 1.45, -3.3), "frac": 0.33, "fov": 48.0,
		"menu": "НАСТРОЙКИ", "tv": "testcard", "focus": "radio", "sub": ""},
	"into_tv": {"pos": Vector3(-0.33, 1.4, -1.84), "subj": Vector3(-0.33, 1.4, -2.56), "frac": 0.5, "fov": 50.0,
		"menu": "none", "tv": "opponent", "focus": "tv", "sub": ""},
	"plan": {"menu": "none", "tv": "live", "focus": "", "sub": ""},
}
const VIDEO_SEQ := ["title", "story", "quick", "workshop", "story", "trophies", "settings", "story", "into_tv"]

const MENU_ITEMS := [
	["ИСТОРИЯ", "Продолжить · Местная лига, бой 2 из 5", "Соперник: ГАЙКА · 3–1 · на кону предплечье"],
	["БЫСТРЫЙ БОЙ", "Выставочный матч · 1–4 игрока · боты", "Арена: Свалка · 90 с → Sudden Death"],
	["МАСТЕРСКАЯ", "Громила · 57 кг · ENERGY 91 / 100", "2 новые детали на верстаке"],
	["ТРОФЕИ", "3 трофея из 5 боёв", "Последний: голова-ящик Полена"],
	["НАСТРОЙКИ", "Звук · экран · управление · эффекты", "Яркость — по таблице на телевизоре"],
]

var cam: Camera3D
var env: Environment
var tv_vp: SubViewport
var tv_root: Control
var tv_mat: ShaderMaterial
var ui_root: Control
var sub_label: Label
var sub_who: Label
var sub_panel: PanelContainer
var zones := {}              # zone -> Array of Light3D
var zone_base := {}          # Light3D -> base energy
var mats := {}
var tex := {}
var f_head: Font
var f_body: Font
var f_mono: Font
var ceiling_nodes: Array = []
var plan_nodes: Array = []
var show_doll := true         # doll=0 — без куклы (пустой ящик)


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	show_doll = args.get("doll", "1") != "0"
	_load_fonts()
	_build_env()
	_build_room()
	_build_tv()
	_build_doll()
	_build_workshop()
	_build_gate()
	_build_trophies()
	_build_settings()
	_build_plan_marks()
	_build_ui()
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	var out: String = args.get("out", ProjectSettings.globalize_path("res://out"))
	DirAccess.make_dir_recursive_absolute(out)
	if args.has("video"):
		await _render_video(out)
	else:
		var list: Array = SHOTS.keys() if args.get("shots", "all") == "all" else Array(args["shots"].split(","))
		for s in list:
			await _render_still(s, out)
	get_tree().quit()


# ---------------------------------------------------------------- рендер

func _render_still(name: String, out: String) -> void:
	_apply_state(name)
	if name == "plan":
		_plan_mode(true)
	else:
		_plan_mode(false)
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.transform = _shot_xform(name)
		cam.fov = SHOTS[name]["fov"]
	for i in 18:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out.path_join("garage-%s.png" % name))
	print("shot ", name)


func _render_video(out: String) -> void:
	var fps := 24.0
	var move_s := 0.75
	var hold_s := 0.9
	var n := 0
	_plan_mode(false)
	var prev: String = VIDEO_SEQ[0]
	_apply_state(prev)
	cam.transform = _shot_xform(prev)
	cam.fov = SHOTS[prev]["fov"]
	for i in 10:
		await RenderingServer.frame_post_draw
	for idx in VIDEO_SEQ.size():
		var cur: String = VIDEO_SEQ[idx]
		var a := _shot_xform(prev)
		var b := _shot_xform(cur)
		var fa: float = SHOTS[prev]["fov"]
		var fb: float = SHOTS[cur]["fov"]
		var frames := int(move_s * fps) if idx > 0 else 0
		if cur == "into_tv":
			frames = int(1.1 * fps)
		for f in frames:
			var t := float(f + 1) / frames
			var e := t * t * (3.0 - 2.0 * t)
			if cur == "into_tv":
				e = t * t * t
			var o := a.origin.lerp(b.origin, e)
			o.y += sin(PI * t) * 0.06
			var q := a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), e)
			cam.transform = Transform3D(Basis(q), o)
			cam.fov = lerpf(fa, fb, e)
			if f == 0:
				_apply_menu(SHOTS[cur]["menu"])
				_apply_sub(SHOTS[cur]["sub"])
			if f == int(frames * 0.3):
				_apply_tv(SHOTS[cur]["tv"])
			tv_mat.set_shader_parameter("noise_amt", 0.85 if abs(f - int(frames * 0.3)) <= 1 else 0.0)
			_blend_focus(SHOTS[prev]["focus"], SHOTS[cur]["focus"], e)
			if cur == "into_tv":
				ui_root.modulate.a = 1.0 - e
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("f%04d.png" % n))
			n += 1
		_apply_state(cur)
		if cur == "into_tv":
			ui_root.modulate.a = 0.0
		var holds := int(hold_s * fps) if cur != "into_tv" else int(0.6 * fps)
		for f in holds:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("f%04d.png" % n))
			n += 1
		prev = cur
		print("seg ", cur, " frames ", n)


func _apply_state(name: String) -> void:
	var s: Dictionary = SHOTS[name]
	_apply_tv(s["tv"])
	_apply_menu(s["menu"])
	_apply_sub(s["sub"])
	_blend_focus(s["focus"], s["focus"], 1.0)
	ui_root.modulate.a = 1.0
	tv_mat.set_shader_parameter("noise_amt", 0.0)


## Камера в pos, кадр повернут так, чтобы subj оказался на доле frac ширины экрана (меню справа).
func _shot_xform(name: String) -> Transform3D:
	var s: Dictionary = SHOTS[name]
	var pos: Vector3 = s["pos"]
	var subj: Vector3 = s["subj"]
	var xf := Transform3D(Basis(), pos).looking_at(subj, Vector3.UP)
	var aspect := 16.0 / 9.0
	var tan_h := tan(deg_to_rad(float(s["fov"]) * 0.5)) * aspect
	var ndc := (float(s["frac"]) - 0.5) * 2.0
	var yaw := atan(-ndc * tan_h)
	xf.basis = Basis(Vector3.UP, -yaw) * xf.basis
	return xf


func _blend_focus(from_zone: String, to_zone: String, t: float) -> void:
	for z in zones:
		var ma := _zone_mult(z, from_zone)
		var mb := _zone_mult(z, to_zone)
		for l in zones[z]:
			l.light_energy = zone_base[l] * lerpf(ma, mb, t)


func _zone_mult(z: String, focus: String) -> float:
	if focus == "" or z == "room" or z == "tv":
		return 1.0 if z != "tv" or focus == "" or focus == "tv" else 0.85
	return 1.7 if z == focus else 0.45


func _plan_mode(on: bool) -> void:
	for n in ceiling_nodes:
		n.visible = not on
	for n in plan_nodes:
		n.visible = on
	ui_root.visible = not on
	if on:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 8.4
		cam.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 14.0, 0.15))
		env.ambient_light_energy = 1.6
		env.volumetric_fog_enabled = false
	else:
		env.ambient_light_energy = 0.09
		env.volumetric_fog_enabled = true


# ---------------------------------------------------------------- окружение и помощники

func _load_fonts() -> void:
	f_head = _font("res://fonts/Oswald.ttf", 650)
	f_body = _font("res://fonts/Rubik.ttf", 450)
	f_mono = _font("res://fonts/JetBrainsMono.ttf", 600)


func _font(path: String, weight: int) -> Font:
	var ff := FontFile.new()
	ff.load_dynamic_font(path)
	var fv := FontVariation.new()
	fv.base_font = ff
	var ts := TextServerManager.get_primary_interface()
	fv.variation_opentype = {ts.name_to_tag("wght"): weight}
	return fv


func _build_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.008, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.30, 0.31, 0.40)
	env.ambient_light_energy = 0.09
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.ssao_enabled = true
	env.ssao_intensity = 1.6
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.028
	env.volumetric_fog_albedo = Color(0.85, 0.85, 0.9)
	env.volumetric_fog_anisotropy = 0.45
	env.volumetric_fog_length = 22.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func m(c: Color, rough := 0.85, metal := 0.0, emi := Color.BLACK, emi_e := 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%s|%.2f" % [c.to_html(), rough, metal, emi.to_html(), emi_e]
	if mats.has(key):
		return mats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = rough
	mat.metallic = metal
	if emi_e > 0.0:
		mat.emission_enabled = true
		mat.emission = emi
		mat.emission_energy_multiplier = emi_e
	mats[key] = mat
	return mat


func _mi(mesh: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	(parent if parent != null else self).add_child(mi)
	return mi


func box(size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO, parent: Node = null) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _mi(bm, pos, mat, rot, parent)


func cyl(r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, rot := Vector3.ZERO, parent: Node = null, sides := 28) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = sides
	return _mi(cm, pos, mat, rot, parent)


func sph(r: float, pos: Vector3, mat: Material, parent: Node = null) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	return _mi(sm, pos, mat, Vector3.ZERO, parent)


func torus(r_in: float, r_out: float, pos: Vector3, mat: Material, rot := Vector3.ZERO, parent: Node = null) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = r_in
	tm.outer_radius = r_out
	return _mi(tm, pos, mat, rot, parent)


## Цилиндр от точки a до точки b.
func limb(a: Vector3, b: Vector3, r: float, mat: Material, parent: Node = null) -> MeshInstance3D:
	var d := b - a
	var mi := cyl(r, r * 0.9, d.length(), (a + b) * 0.5, mat, Vector3.ZERO, parent)
	var y := d.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	mi.basis = Basis(x, y, z)
	return mi


func quad_tex(size: Vector2, pos: Vector3, rot: Vector3, t: Texture2D, emi_e := 0.0, uv_scale := Vector2.ONE, uv_off := Vector2.ZERO) -> MeshInstance3D:
	var qm := QuadMesh.new()
	qm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = t
	mat.roughness = 0.8
	mat.uv1_scale = Vector3(uv_scale.x, uv_scale.y, 1.0)
	mat.uv1_offset = Vector3(uv_off.x, uv_off.y, 0.0)
	if emi_e > 0.0:
		mat.emission_enabled = true
		mat.emission = Color.WHITE
		mat.emission_texture = t
		mat.emission_energy_multiplier = emi_e
	return _mi(qm, pos, mat, rot)


func lbl(text: String, pos: Vector3, rot: Vector3, px: int, col: Color, font: Font, emissive := true, parent: Node = null) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.rotation_degrees = rot
	l.font = font
	l.font_size = px
	l.pixel_size = 0.0025
	l.modulate = col
	l.outline_size = 0
	l.shaded = not emissive
	l.double_sided = false
	(parent if parent != null else self).add_child(l)
	return l


func omni(pos: Vector3, col: Color, energy: float, rng: float, zone: String, shadow := false, vol := 1.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = shadow
	l.light_volumetric_fog_energy = vol
	add_child(l)
	_zone(zone, l)
	return l


func spot(pos: Vector3, target: Vector3, col: Color, energy: float, rng: float, angle: float, zone: String, shadow := true, vol := 1.0) -> SpotLight3D:
	var l := SpotLight3D.new()
	add_child(l)
	l.position = pos
	l.look_at(target, Vector3.UP if absf((target - pos).normalized().y) < 0.95 else Vector3.FORWARD)
	l.light_color = col
	l.light_energy = energy
	l.spot_range = rng
	l.spot_angle = angle
	l.spot_angle_attenuation = 0.8
	l.shadow_enabled = shadow
	l.light_volumetric_fog_energy = vol
	_zone(zone, l)
	return l


func _zone(zone: String, l: Light3D) -> void:
	if not zones.has(zone):
		zones[zone] = []
	zones[zone].append(l)
	zone_base[l] = l.light_energy


func _img(path: String) -> Texture2D:
	if tex.has(path):
		return tex[path]
	# картинки берём из docs/plan-demo/img (папка рядом с болванкой), а если их скопировали внутрь — из res://img
	var file := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(file):
		file = ProjectSettings.globalize_path("res://").path_join("../img/" + path.get_file()).simplify_path()
	var im := Image.load_from_file(file)
	im.generate_mipmaps()
	var t := ImageTexture.create_from_image(im)
	tex[path] = t
	return t


# ---------------------------------------------------------------- комната

const C_WOOD_DARK := Color(0.29, 0.20, 0.14)
const C_WOOD := Color(0.52, 0.34, 0.19)
const C_WOOD_KIT := Color(0.72, 0.45, 0.22)
const C_METAL := Color(0.30, 0.32, 0.35)
const C_METAL_DARK := Color(0.16, 0.17, 0.19)
const C_CONCRETE := Color(0.22, 0.21, 0.20)
const C_CREAM := Color(0.85, 0.80, 0.68)
const C_TEAL := Color(0.18, 0.60, 0.58)        # цвет игрока P1 (приглушённая бирюза кита)
const C_BORDO := Color(0.50, 0.14, 0.16)
const C_MUSTARD := Color(0.80, 0.60, 0.18)
const C_OLIVE := Color(0.40, 0.44, 0.22)
const C_NULL := Color(0.62, 0.42, 1.0)          # свет поля NULL за воротами


func _build_room() -> void:
	var hw := ROOM_W * 0.5
	var hd := ROOM_D * 0.5
	box(Vector3(ROOM_W, 0.1, ROOM_D), Vector3(0, -0.05, 0), m(C_CONCRETE, 0.92))
	# разметка бокса на полу и коврик перед телевизором
	box(Vector3(2.6, 0.012, 1.8), Vector3(-0.6, 0.006, -1.8), m(Color(0.33, 0.12, 0.12), 0.95))
	box(Vector3(2.4, 0.012, 1.6), Vector3(-0.6, 0.008, -1.8), m(Color(0.42, 0.17, 0.15), 0.95))
	for i in 9:
		box(Vector3(0.28, 0.008, 0.1), Vector3(-3.6 + i * 0.36, 0.005, 2.3), m(C_MUSTARD if i % 2 == 0 else C_METAL_DARK, 0.9))
	lbl("07", Vector3(1.6, 0.012, 1.4), Vector3(-90, 0, 0), 600, Color(0.85, 0.66, 0.2, 0.45), f_head, false)
	# задняя стена — доски
	for i in int(ROOM_W / 0.32) + 1:
		var shade := 0.85 + 0.15 * float((i * 7) % 5) / 4.0
		box(Vector3(0.3, ROOM_H, 0.06), Vector3(-hw + 0.16 + i * 0.32, ROOM_H * 0.5, -hd - 0.03), m(C_WOOD_DARK * shade, 0.9))
	# левая стена — профнастил, правая — доски
	for i in int(ROOM_D / 0.25) + 1:
		box(Vector3(0.06 if i % 2 == 0 else 0.03, ROOM_H, 0.25), Vector3(-hw - 0.03, ROOM_H * 0.5, -hd + 0.125 + i * 0.25), m(C_METAL * (0.9 if i % 2 == 0 else 0.75), 0.6, 0.5))
	for i in int(ROOM_D / 0.32) + 1:
		var shade := 0.8 + 0.2 * float((i * 5) % 4) / 3.0
		box(Vector3(0.06, ROOM_H, 0.3), Vector3(hw + 0.03, ROOM_H * 0.5, -hd + 0.16 + i * 0.32), m(C_WOOD_DARK * shade * 1.1, 0.9))
	# потолок, балки, лампа-груша в центре
	ceiling_nodes.append(box(Vector3(ROOM_W, 0.1, ROOM_D), Vector3(0, ROOM_H + 0.05, 0), m(Color(0.08, 0.08, 0.09))))
	for i in 7:
		ceiling_nodes.append(box(Vector3(ROOM_W, 0.22, 0.16), Vector3(0, ROOM_H - 0.11, -hd + 0.5 + i * 1.0), m(C_WOOD_DARK * 0.8)))
	ceiling_nodes.append(cyl(0.006, 0.006, 1.3, Vector3(1.9, ROOM_H - 0.65, 2.4), m(Color.BLACK)))
	ceiling_nodes.append(sph(0.05, Vector3(1.9, ROOM_H - 1.33, 2.4), m(Color(1, 0.8, 0.5), 0.5, 0.0, Color(1.0, 0.75, 0.45), 3.0)))
	omni(Vector3(1.9, ROOM_H - 1.45, 2.4), Color(1.0, 0.72, 0.42), 0.5, 6.0, "room", true, 0.4)
	# трубы и кабели под потолком
	cyl(0.05, 0.05, ROOM_D, Vector3(hw - 0.3, ROOM_H - 0.35, 0), m(C_METAL, 0.5, 0.6), Vector3(90, 0, 0))
	cyl(0.025, 0.025, ROOM_W, Vector3(0, ROOM_H - 0.45, -hd + 0.2), m(Color(0.1, 0.1, 0.1)), Vector3(0, 0, 90))


# ---------------------------------------------------------------- телевизор (ИСТОРИЯ)

func _build_tv() -> void:
	# тумба
	box(Vector3(1.9, 0.85, 0.62), Vector3(-0.25, 0.425, -3.08), m(C_WOOD, 0.8))
	box(Vector3(1.94, 0.04, 0.66), Vector3(-0.25, 0.87, -3.08), m(C_WOOD * 0.8, 0.7))
	for x in [-0.9, -0.25, 0.4]:
		box(Vector3(0.5, 0.26, 0.02), Vector3(x, 0.55, -2.76), m(C_WOOD * 0.7, 0.8))
		box(Vector3(0.1, 0.02, 0.03), Vector3(x, 0.62, -2.74), m(C_MUSTARD, 0.4, 0.7))
	# корпус: деревянный, кремовая рамка, ручки справа, антенны
	var tvp := Vector3(-0.25, 1.41, -3.02)
	box(Vector3(1.5, 1.04, 0.86), tvp, m(Color(0.55, 0.33, 0.17), 0.55))
	box(Vector3(1.38, 0.92, 0.04), tvp + Vector3(0, 0, 0.43), m(C_CREAM, 0.6))
	box(Vector3(1.14, 0.84, 0.03), tvp + Vector3(-0.08, 0, 0.445), m(Color(0.05, 0.05, 0.06), 0.3))
	for i in 2:
		cyl(0.055, 0.06, 0.05, tvp + Vector3(0.58, 0.22 - i * 0.2, 0.46), m(C_BORDO, 0.5), Vector3(90, 0, 0))
	for i in 6:
		box(Vector3(0.14, 0.012, 0.01), tvp + Vector3(0.58, -0.12 - i * 0.04, 0.455), m(C_METAL_DARK))
	sph(0.016, tvp + Vector3(0.58, -0.4, 0.46), m(Color.RED, 0.4, 0.0, Color(1, 0.1, 0.05), 6.0))
	cyl(0.012, 0.012, 0.7, tvp + Vector3(-0.25, 0.8, -0.05), m(C_METAL, 0.4, 0.8), Vector3(0, 0, 30))
	cyl(0.012, 0.012, 0.7, tvp + Vector3(0.15, 0.8, -0.05), m(C_METAL, 0.4, 0.8), Vector3(0, 0, -25))
	sph(0.06, tvp + Vector3(-0.05, 0.53, -0.05), m(C_METAL_DARK))
	# экран: SubViewport с эфиром → шейдер «кинескоп»
	tv_vp = SubViewport.new()
	tv_vp.size = Vector2i(SCREEN_W, SCREEN_H)
	tv_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tv_vp.transparent_bg = false
	tv_vp.disable_3d = true
	add_child(tv_vp)
	tv_root = Control.new()
	tv_root.size = Vector2(SCREEN_W, SCREEN_H)
	tv_vp.add_child(tv_root)
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D screen_tex : source_color, filter_linear;
uniform float boost = 1.55;
uniform float noise_amt = 0.0;
void fragment() {
	vec2 c = UV - 0.5;
	vec2 uv = 0.5 + c * (1.0 + 0.08 * dot(c, c));
	vec3 col = texture(screen_tex, uv).rgb;
	float scan = 0.84 + 0.16 * sin(uv.y * 576.0 * 3.14159);
	float vig = smoothstep(0.78, 0.30, length(c * vec2(1.0, 1.15)));
	float n = fract(sin(dot(floor(uv * vec2(256.0, 192.0)) + TIME * 37.0, vec2(12.9898, 78.233))) * 43758.5453);
	col = mix(col, vec3(n) * 1.2, noise_amt);
	col *= scan * (0.4 + 0.6 * vig) * boost;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) col = vec3(0.0);
	ALBEDO = col;
}
"""
	tv_mat = ShaderMaterial.new()
	tv_mat.shader = sh
	tv_mat.set_shader_parameter("screen_tex", tv_vp.get_texture())
	var qm := QuadMesh.new()
	qm.size = Vector2(1.06, 0.795)
	_mi(qm, tvp + Vector3(-0.08, 0.0, 0.462), tv_mat)
	# свет экрана: заливка комнаты холодным и «луч» в туман
	omni(tvp + Vector3(-0.08, 0.0, 0.9), Color(0.55, 0.72, 1.0), 2.4, 6.5, "tv", true, 1.2)
	spot(tvp + Vector3(-0.08, 0.0, 0.5), Vector3(0.2, 0.9, 1.5), Color(0.6, 0.75, 1.0), 3.0, 7.0, 42.0, "tv", true, 2.2)
	# кабель от телевизора к стене
	limb(Vector3(-0.9, 0.95, -3.4), Vector3(-1.3, 0.02, -3.35), 0.012, m(Color(0.05, 0.05, 0.05)))
	limb(Vector3(-1.3, 0.02, -3.35), Vector3(-2.0, 0.02, -3.4), 0.012, m(Color(0.05, 0.05, 0.05)))


# ---------------------------------------------------------------- кукла игрока на ящике (вне поля NULL — тяжёлая, сидит)

func _build_doll() -> void:
	# ящик
	var cp := Vector3(-1.05, 0.21, -1.3)
	box(Vector3(0.7, 0.42, 0.7), cp, m(C_WOOD * 1.1, 0.85))
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			box(Vector3(0.07, 0.43, 0.07), cp + Vector3(sx * 0.33, 0, sz * 0.33), m(C_WOOD_DARK, 0.85))
	box(Vector3(0.72, 0.05, 0.08), cp + Vector3(0, 0.0, 0.355), m(C_WOOD_DARK, 0.85), Vector3(0, 0, 38))
	if not show_doll:
		return
	var d := Node3D.new()
	d.position = Vector3(-1.05, 0.42, -1.3)
	d.rotation_degrees = Vector3(0, -30, 0)
	add_child(d)
	var wood := m(C_WOOD_KIT, 0.7)
	var joint := m(Color(0.13, 0.13, 0.15), 0.4, 0.3)
	var ring := m(C_TEAL, 0.55)
	var iron := m(Color(0.12, 0.12, 0.13), 0.45, 0.6)
	box(Vector3(0.3, 0.16, 0.2), Vector3(0, 0.1, 0.05), wood, Vector3.ZERO, d)
	sph(0.08, Vector3(0, 0.22, 0.04), joint, d)
	var torso := cyl(0.19, 0.17, 0.4, Vector3(0, 0.44, 0.02), wood, Vector3(-8, 0, 0), d)
	for y in [-0.13, 0.13]:
		var hoop := cyl(0.198, 0.198, 0.03, Vector3(0, y, 0), iron, Vector3.ZERO, torso)
		hoop.name = "hoop"
	cyl(0.2, 0.2, 0.05, Vector3(0, 0.02, 0), ring, Vector3.ZERO, torso)
	sph(0.05, Vector3(0, 0.7, -0.05), joint, d)
	var head := box(Vector3(0.34, 0.3, 0.3), Vector3(0, 0.88, -0.09), wood, Vector3(7, 0, -4), d)
	box(Vector3(0.36, 0.035, 0.32), Vector3(0, 0.13, 0), iron, Vector3.ZERO, head)
	box(Vector3(0.24, 0.19, 0.01), Vector3(0, -0.01, -0.155), m(C_CREAM, 0.6), Vector3.ZERO, head)
	for ex in [-0.05, 0.05]:
		sph(0.017, Vector3(ex, 0.01, -0.162), m(Color.BLACK), head)
	for sx in [-1, 1]:
		var sh := Vector3(sx * 0.25, 0.58, -0.02)
		var el := Vector3(sx * 0.27, 0.30, -0.2)
		var wr := Vector3(sx * 0.16, 0.2, -0.42)
		sph(0.06, sh, joint, d)
		cyl(0.064, 0.064, 0.025, sh, ring, Vector3(0, 0, 90), d)
		limb(sh, el, 0.055, wood, d)
		sph(0.05, el, joint, d)
		limb(el, wr, 0.048, wood, d)
		box(Vector3(0.09, 0.07, 0.13), wr + Vector3(0, -0.02, -0.05), m(C_TEAL * 0.9, 0.7), Vector3.ZERO, d)
		var hip := Vector3(sx * 0.11, 0.06, -0.02)
		var kn := Vector3(sx * 0.13, 0.08, -0.43)
		var an := Vector3(sx * 0.15, -0.31, -0.55)
		sph(0.06, hip, joint, d)
		limb(hip, kn, 0.07, wood, d)
		sph(0.06, kn, joint, d)
		cyl(0.064, 0.064, 0.025, kn, ring, Vector3(90, 0, 0), d)
		limb(kn, an, 0.06, wood, d)
		sph(0.045, an, joint, d)
		box(Vector3(0.11, 0.08, 0.22), an + Vector3(0, -0.06, -0.06), m(Color(0.2, 0.14, 0.1), 0.7), Vector3.ZERO, d)


# ---------------------------------------------------------------- верстак и стенд (МАСТЕРСКАЯ)

func _build_workshop() -> void:
	var bz := -3.12
	box(Vector3(2.3, 0.08, 0.7), Vector3(-3.25, 0.9, bz), m(C_WOOD, 0.75))
	for x in [-4.3, -2.2]:
		box(Vector3(0.08, 0.86, 0.6), Vector3(x, 0.43, bz), m(C_WOOD_DARK, 0.85))
	box(Vector3(0.8, 0.5, 0.6), Vector3(-2.75, 0.55, bz), m(C_OLIVE, 0.6, 0.3))
	for i in 3:
		box(Vector3(0.72, 0.13, 0.02), Vector3(-2.75, 0.73 - i * 0.16, bz + 0.31), m(C_OLIVE * 0.8, 0.6, 0.3))
	# тиски, молоток, детали на верстаке
	box(Vector3(0.22, 0.14, 0.14), Vector3(-4.0, 1.01, bz + 0.15), m(C_METAL, 0.5, 0.7))
	limb(Vector3(-3.6, 0.96, bz + 0.1), Vector3(-3.25, 0.96, bz + 0.22), 0.015, m(C_WOOD, 0.7))
	box(Vector3(0.12, 0.05, 0.05), Vector3(-3.62, 0.97, bz + 0.1), m(C_METAL_DARK, 0.4, 0.8))
	cyl(0.07, 0.07, 0.28, Vector3(-2.6, 1.0, bz + 0.05), m(C_BORDO, 0.6), Vector3(0, 0, 90))
	box(Vector3(0.3, 0.28, 0.28), Vector3(-2.35, 1.08, bz - 0.12), m(C_WOOD_KIT, 0.7))
	# перфопанель с инструментом, чертёж
	box(Vector3(2.3, 1.15, 0.04), Vector3(-3.25, 1.75, -3.46), m(Color(0.45, 0.33, 0.22), 0.9))
	for i in 7:
		var x := -4.2 + i * 0.3
		limb(Vector3(x, 2.15, -3.43), Vector3(x + 0.02 * (i % 3), 1.65 - 0.08 * (i % 2), -3.43), 0.018 + 0.006 * (i % 3), m(C_METAL_DARK, 0.5, 0.7))
	limb(Vector3(-2.55, 2.05, -3.42), Vector3(-2.55, 1.45, -3.42), 0.06, m(C_TEAL, 0.7))
	var bp := box(Vector3(0.9, 0.62, 0.01), Vector3(-1.62, 1.95, -3.44), m(Color(0.2, 0.42, 0.65), 0.9, 0.0, Color(0.25, 0.5, 0.8), 0.25))
	for i in 5:
		box(Vector3(0.7 - i * 0.08, 0.008, 0.005), Vector3(0, 0.2 - i * 0.1, 0.008), m(Color(0.8, 0.9, 1.0), 0.9, 0.0, Color(0.8, 0.9, 1.0), 0.4), Vector3.ZERO, bp)
	# стенд-прибор: база, стойка, обод-захват, кольцо разметки на полу
	var sp := Vector3(-3.0, 0.0, -1.95)
	cyl(0.5, 0.55, 0.08, sp + Vector3(0, 0.04, 0), m(C_METAL_DARK, 0.5, 0.6))
	torus(0.6, 0.66, sp + Vector3(0, 0.01, 0), m(C_MUSTARD, 0.6))
	cyl(0.05, 0.06, 1.35, sp + Vector3(0, 0.75, 0), m(C_METAL, 0.4, 0.8))
	torus(0.2, 0.25, sp + Vector3(0, 1.42, 0), m(Color(0.85, 0.42, 0.12), 0.5, 0.3), Vector3(0, 0, 0))
	for sx in [-1, 1]:
		limb(sp + Vector3(0, 1.42, 0) + Vector3(sx * 0.22, 0, 0), sp + Vector3(sx * 0.45, 1.6, 0), 0.025, m(C_METAL, 0.4, 0.8))
	# ящик с запасными конечностями
	box(Vector3(0.6, 0.4, 0.5), Vector3(-4.0, 0.2, -1.2), m(C_WOOD * 0.9, 0.85))
	for i in 4:
		limb(Vector3(-4.15 + i * 0.1, 0.3, -1.25 + 0.05 * (i % 2)), Vector3(-4.2 + i * 0.13, 0.75 - 0.08 * (i % 3), -1.1), 0.05, m([C_WOOD_KIT, C_BORDO, C_TEAL, C_MUSTARD][i], 0.7))
	# лампа над верстаком
	cyl(0.006, 0.006, 1.1, Vector3(-3.1, ROOM_H - 0.55, -2.75), m(Color.BLACK))
	cyl(0.08, 0.3, 0.24, Vector3(-3.1, ROOM_H - 1.2, -2.75), m(Color(0.25, 0.36, 0.3), 0.5, 0.3))
	sph(0.05, Vector3(-3.1, ROOM_H - 1.3, -2.75), m(Color(1, 0.85, 0.6), 0.5, 0.0, Color(1, 0.75, 0.45), 4.0))
	spot(Vector3(-3.1, ROOM_H - 1.32, -2.75), Vector3(-3.0, 0.9, -2.5), Color(1.0, 0.72, 0.42), 4.0, 5.0, 50.0, "bench", true, 1.5)


# ---------------------------------------------------------------- ворота лифта на арену (БЫСТРЫЙ БОЙ)

func _build_gate() -> void:
	var gx := -ROOM_W * 0.5 + 0.02
	var z0 := -1.2
	var z1 := 1.8
	var top := 3.0
	var gap := 0.16
	# проём светится полем NULL
	box(Vector3(0.02, top, z1 - z0), Vector3(gx - 0.04, top * 0.5, (z0 + z1) * 0.5), m(Color.BLACK, 1.0, 0.0, C_NULL, 1.2))
	var slat_h := 0.12
	var n := int((top - gap) / slat_h)
	for i in n:
		box(Vector3(0.05, slat_h - 0.012, z1 - z0), Vector3(gx + 0.05, gap + slat_h * (i + 0.5), (z0 + z1) * 0.5), m(C_METAL * (0.95 if i % 2 == 0 else 0.8), 0.55, 0.6))
	# окно-иллюминатор в шторе: видно свечение купола
	cyl(0.24, 0.24, 0.07, Vector3(gx + 0.08, 1.75, 0.3), m(C_METAL_DARK, 0.4, 0.7), Vector3(0, 0, 90))
	cyl(0.19, 0.19, 0.075, Vector3(gx + 0.085, 1.75, 0.3), m(Color.BLACK, 0.2, 0.0, Color(0.7, 0.55, 1.0), 2.6), Vector3(0, 0, 90))
	# рама с полосами опасности
	for z in [z0 - 0.12, z1 + 0.12]:
		for i in 14:
			box(Vector3(0.16, 0.22, 0.2), Vector3(gx + 0.08, 0.11 + i * 0.22, z), m(C_MUSTARD if i % 2 == 0 else Color(0.08, 0.08, 0.08), 0.7))
	box(Vector3(0.18, 0.24, z1 - z0 + 0.44), Vector3(gx + 0.09, top + 0.12, (z0 + z1) * 0.5), m(C_METAL_DARK, 0.6, 0.5))
	# табличка и лампа над воротами
	box(Vector3(0.04, 0.32, 1.5), Vector3(gx + 0.2, top + 0.45, 0.3), m(Color(0.07, 0.07, 0.08), 0.6))
	lbl("ЛИФТ ▸ АРЕНА", Vector3(gx + 0.23, top + 0.45, 0.3), Vector3(0, 90, 0), 70, Color(1.0, 0.7, 0.3), f_head)
	sph(0.06, Vector3(gx + 0.2, top + 0.45, 1.3), m(Color.RED, 0.4, 0.0, Color(1, 0.15, 0.05), 5.0))
	lbl("07", Vector3(gx + 0.085, 1.0, 0.3), Vector3(0, 90, 0), 300, Color(0.9, 0.7, 0.2), f_head, false)
	# свет поля из щели под воротами и из иллюминатора
	box(Vector3(0.3, 0.01, z1 - z0), Vector3(gx + 0.15, 0.005, (z0 + z1) * 0.5), m(Color.BLACK, 1.0, 0.0, C_NULL, 2.0))
	spot(Vector3(gx + 0.05, 0.08, 0.3), Vector3(gx + 3.5, 0.0, 0.3), C_NULL, 6.0, 5.5, 70.0, "gate", false, 2.5)
	omni(Vector3(gx + 0.6, 0.25, 0.3), C_NULL, 1.4, 3.5, "gate", false, 1.5)
	spot(Vector3(gx + 0.1, 1.75, 0.3), Vector3(1.5, 1.2, 0.0), Color(0.7, 0.55, 1.0), 3.0, 6.0, 18.0, "gate", false, 3.0)
	# афиши арен на стене возле ворот
	_poster(Vector3(gx + 0.02, 1.7, -2.15), "res://img/body-paint-arena.png", "СВАЛКА")
	_poster(Vector3(gx + 0.02, 1.7, 2.65), "res://img/00-playground-v5-fight.png", "РУИНЫ")


func _poster(pos: Vector3, img: String, title: String) -> void:
	box(Vector3(0.03, 1.08, 0.78), pos, m(C_CREAM * 0.8, 0.9))
	quad_tex(Vector2(0.7, 0.86), pos + Vector3(0.02, 0.06, 0), Vector3(0, 90, 0), _img(img), 0.25, Vector2(0.4, 1.0), Vector2(0.3, 0.0))
	lbl(title, pos + Vector3(0.025, -0.44, 0), Vector3(0, 90, 0), 54, Color(0.12, 0.1, 0.08), f_head, false)


# ---------------------------------------------------------------- полка трофеев (ТРОФЕИ)

func _build_trophies() -> void:
	var sx := ROOM_W * 0.5 - 0.2
	var zc := -0.9
	for h in [0.85, 1.45, 2.05]:
		box(Vector3(0.38, 0.05, 2.6), Vector3(sx, h, zc), m(C_WOOD, 0.8))
	for z in [zc - 1.32, zc + 1.32]:
		box(Vector3(0.38, 2.1, 0.06), Vector3(sx, 1.05, z), m(C_WOOD_DARK, 0.85))
	var tag := m(C_CREAM, 0.8)
	# нижняя: предплечье-трофей, пружина, пустое место «?»
	limb(Vector3(sx, 0.95, zc - 0.95), Vector3(sx - 0.05, 0.95, zc - 0.45), 0.06, m(C_BORDO, 0.7))
	for i in 4:
		torus(0.05, 0.07, Vector3(sx, 0.95, zc - 0.88 + i * 0.12), m(C_MUSTARD, 0.6), Vector3(90, 0, 0))
	cyl(0.06, 0.06, 0.35, Vector3(sx, 1.06, zc + 0.15), m(C_METAL, 0.5, 0.7))
	torus(0.12, 0.13, Vector3(sx - 0.15, 0.88, zc + 0.85), m(Color(0.9, 0.9, 0.9, 1), 0.9))
	lbl("?", Vector3(sx - 0.19, 1.1, zc + 0.85), Vector3(0, -90, 0), 120, Color(0.95, 0.9, 0.75), f_head)
	# средняя: голова-ящик Полена, булава
	var hb := box(Vector3(0.3, 0.28, 0.28), Vector3(sx, 1.62, zc - 0.6), m(C_WOOD_KIT * 0.9, 0.7), Vector3(0, -70, 6))
	box(Vector3(0.2, 0.16, 0.01), Vector3(0, 0, -0.145), m(C_CREAM, 0.6), Vector3.ZERO, hb)
	sph(0.14, Vector3(sx, 1.62, zc + 0.35), m(C_BORDO * 1.2, 0.5, 0.2))
	for v in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var tip := cyl(0.0, 0.04, 0.1, Vector3(sx, 1.62, zc + 0.35) + v * 0.17, m(C_METAL, 0.4, 0.8))
		tip.basis = Basis(Quaternion(Vector3.UP, v)) if v != Vector3(0, -1, 0) else Basis()
	# верхняя: шлем с рогами, корона
	sph(0.16, Vector3(sx, 2.16, zc - 0.5), m(Color(0.12, 0.12, 0.13), 0.4, 0.5))
	for s in [-1, 1]:
		limb(Vector3(sx, 2.2, zc - 0.5 + s * 0.14), Vector3(sx - 0.02, 2.45, zc - 0.5 + s * 0.3), 0.03, m(C_CREAM, 0.6))
	cyl(0.12, 0.12, 0.1, Vector3(sx, 2.13, zc + 0.45), m(C_MUSTARD * 1.2, 0.3, 0.9))
	for i in 5:
		var a := TAU * i / 5.0
		cyl(0.0, 0.025, 0.08, Vector3(sx + cos(a) * 0.11, 2.22, zc + 0.45 + sin(a) * 0.11), m(C_MUSTARD * 1.2, 0.3, 0.9))
	# бирки с именами проигравших
	var names := [["ПОЛЕНО", 1.53, -0.6], ["ГРОХ", 1.53, 0.35], ["ВИНТ", 0.88, -0.7], ["ТУМБА", 2.08, -0.5], ["КЛЁПА", 2.08, 0.45]]
	for nm in names:
		box(Vector3(0.005, 0.07, 0.22), Vector3(sx - 0.2, nm[1], zc + nm[2]), tag)
		lbl(nm[0], Vector3(sx - 0.205, nm[1], zc + nm[2]), Vector3(0, -90, 0), 26, Color(0.1, 0.08, 0.06), f_mono, false)
	# вымпел лиги
	var pen := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.9, 0.5, 0.01)
	pen.mesh = pm
	pen.material_override = m(C_TEAL, 0.9)
	pen.position = Vector3(sx + 0.15, 2.75, zc)
	pen.rotation_degrees = Vector3(180, 90, 0)
	add_child(pen)
	lbl("МЕСТНАЯ ЛИГА", Vector3(sx + 0.13, 2.86, zc), Vector3(0, -90, 0), 34, C_CREAM, f_head, false)
	for z in [zc - 0.75, zc, zc + 0.75]:
		spot(Vector3(sx - 0.35, 2.55, z), Vector3(sx - 0.05, 1.2, z), Color(1.0, 0.8, 0.55), 2.2, 3.5, 32.0, "shelf", true, 1.2)


# ---------------------------------------------------------------- радио и рубильник (НАСТРОЙКИ / ВЫХОД)

func _build_settings() -> void:
	var cz := -3.15
	box(Vector3(1.7, 0.9, 0.5), Vector3(3.2, 0.45, cz), m(C_WOOD_DARK * 1.2, 0.85))
	# радио
	var rp := Vector3(2.95, 1.12, cz)
	box(Vector3(0.74, 0.42, 0.3), rp, m(C_CREAM, 0.55))
	box(Vector3(0.3, 0.3, 0.01), rp + Vector3(-0.17, 0, 0.152), m(Color(0.3, 0.22, 0.16), 0.9))
	for i in 6:
		box(Vector3(0.28, 0.01, 0.006), rp + Vector3(-0.17, 0.12 - i * 0.048, 0.157), m(C_WOOD_DARK))
	box(Vector3(0.26, 0.1, 0.01), rp + Vector3(0.18, 0.08, 0.152), m(Color.BLACK, 0.3, 0.0, Color(1.0, 0.65, 0.25), 2.5))
	for i in 2:
		cyl(0.04, 0.045, 0.04, rp + Vector3(0.11 + i * 0.14, -0.1, 0.16), m(C_BORDO, 0.5), Vector3(90, 0, 0))
	limb(rp + Vector3(0.25, 0.21, 0), rp + Vector3(0.45, 0.6, -0.05), 0.008, m(C_METAL, 0.4, 0.8))
	omni(rp + Vector3(0.18, 0.08, 0.35), Color(1.0, 0.65, 0.3), 0.6, 1.6, "radio", false, 0.6)
	# щиток с рубильником
	var fp := Vector3(3.85, 1.7, -3.44)
	box(Vector3(0.55, 0.75, 0.14), fp, m(Color(0.32, 0.4, 0.35), 0.6, 0.4))
	box(Vector3(0.06, 0.3, 0.06), fp + Vector3(0.12, 0.02, 0.1), m(C_METAL, 0.4, 0.8), Vector3(-30, 0, 0))
	box(Vector3(0.16, 0.06, 0.06), fp + Vector3(0.12, 0.15, 0.18), m(Color(0.75, 0.12, 0.08), 0.5))
	for i in 3:
		sph(0.02, fp + Vector3(-0.15, 0.2 - i * 0.1, 0.075), m(Color.BLACK, 0.4, 0.0, [Color(0.2, 1, 0.3), Color(1, 0.7, 0.1), Color(1, 0.2, 0.1)][i], 4.0))
	limb(fp + Vector3(0, 0.37, 0), Vector3(3.85, ROOM_H - 0.45, -3.3), 0.02, m(Color(0.05, 0.05, 0.05)))
	# доска «расписание эфира»
	var bd := box(Vector3(1.1, 0.7, 0.02), Vector3(2.85, 2.15, -3.44), m(Color(0.12, 0.14, 0.13), 0.95))
	lbl("ЭФИР  NULL FIGHTING", Vector3(0, 0.25, 0.012), Vector3.ZERO, 40, Color(0.9, 0.88, 0.8), f_head, false, bd)
	lbl("ПН  местная лига\nСР  выставочный\nПТ  ТВОЙ БОЙ?", Vector3(0, -0.06, 0.012), Vector3.ZERO, 34, Color(0.85, 0.85, 0.8), f_body, false, bd)
	spot(Vector3(3.2, 2.9, -2.6), Vector3(3.2, 1.3, -3.4), Color(1.0, 0.8, 0.6), 1.6, 3.0, 35.0, "radio", true, 0.8)


# ---------------------------------------------------------------- метки для плана сверху

func _build_plan_marks() -> void:
	var marks := [
		["ТЕЛЕВИЗОР\n→ ИСТОРИЯ", Vector3(-0.25, 2.5, -2.2)],
		["КУКЛА НА ЯЩИКЕ", Vector3(-1.05, 2.5, -0.75)],
		["ЛИФТ НА АРЕНУ\n→ БЫСТРЫЙ БОЙ", Vector3(-3.2, 2.5, 0.3)],
		["ВЕРСТАК + СТЕНД\n→ МАСТЕРСКАЯ", Vector3(-3.0, 2.5, -1.0)],
		["ПОЛКА ТРОФЕЕВ\n→ ТРОФЕИ", Vector3(3.3, 2.5, -0.9)],
		["РАДИО, РУБИЛЬНИК\n→ НАСТРОЙКИ / ВЫХОД", Vector3(2.7, 2.5, -2.3)],
	]
	for mk in marks:
		var l := lbl(mk[0], mk[1], Vector3(-90, 0, 0), 64, Color(1, 1, 1), f_head)
		l.outline_size = 18
		l.outline_modulate = Color(0, 0, 0, 0.85)
		l.no_depth_test = true
		plan_nodes.append(l)
	var keys := ["story", "quick", "workshop", "trophies", "settings", "title"]
	for k in keys:
		var xf := _shot_xform(k)
		var p := xf.origin
		var fwd := -xf.basis.z
		var flat := Vector3(fwd.x, 0, fwd.z).normalized()
		var c := sph(0.12, Vector3(p.x, 2.8, p.z), m(Color(1.0, 0.55, 0.15), 0.5, 0.0, Color(1.0, 0.55, 0.15), 1.5))
		plan_nodes.append(c)
		var ln := limb(Vector3(p.x, 2.8, p.z), Vector3(p.x, 2.8, p.z) + flat * 1.1, 0.03, m(Color(1.0, 0.55, 0.15), 0.5, 0.0, Color(1.0, 0.55, 0.15), 1.5))
		plan_nodes.append(ln)
		var l := lbl("cam: " + k, Vector3(p.x + 0.25, 2.85, p.z + 0.25), Vector3(-90, 0, 0), 40, Color(1.0, 0.75, 0.4), f_mono)
		l.outline_size = 12
		l.outline_modulate = Color(0, 0, 0, 0.85)
		l.no_depth_test = true
		plan_nodes.append(l)
	for n in plan_nodes:
		n.visible = false


# ---------------------------------------------------------------- эфир на телевизоре

func _apply_tv(mode: String) -> void:
	for c in tv_root.get_children():
		tv_root.remove_child(c)
		c.queue_free()
	match mode:
		"live":
			_tv_bg("res://img/body-paint-arena.png")
			_tv_live_bar("● LIVE", "NULL FIGHTING · МЕСТНАЯ ЛИГА")
			_tv_score("КЛЁПА", "2 : 1", "ТУМБА", "0.20G ↓")
			_tv_ticker("ОТКРЫТ НАБОР НОВИЧКОВ · БОКСЫ 01–12 · ГРАВИТАЦИЯ ПО ГОЛОСОВАНИЮ ЗРИТЕЛЕЙ · ")
			_tv_n0()
		"opponent":
			_tv_grad(Color(0.10, 0.05, 0.08), Color(0.35, 0.10, 0.12))
			_tv_crop("res://img/body-kit-v1.png", Rect2(1095, 245, 240, 315), Rect2(40, 90, 300, 394))
			_tv_live_bar("● LIVE", "СЛЕДУЮЩИЙ БОЙ")
			_tv_text("ГАЙКА", Vector2(360, 150), 92, Color(1.0, 0.85, 0.4), f_head)
			_tv_text("3 – 1   ·   МЕСТНАЯ ЛИГА", Vector2(364, 265), 30, Color(1, 1, 1), f_body)
			_tv_text("НА КОНУ:", Vector2(364, 330), 26, Color(0.8, 0.8, 0.8), f_mono)
			_tv_text("ПРЕДПЛЕЧЬЕ", Vector2(364, 362), 44, Color(0.6, 1.0, 0.95), f_head)
			_tv_text("VS  БОКС 07", Vector2(364, 440), 34, Color(1, 1, 1), f_head)
			_tv_ticker("СЕГОДНЯ В 21:00 · ГАЙКА ПРОТИВ НОВИЧКА ИЗ БОКСА 07 · СТАВКИ НА ДЕТАЛЬ ПРИНЯТЫ · ")
		"quick":
			_tv_bg("res://img/00-playground-v5-fight.png")
			_tv_live_bar("ВЫСТАВОЧНЫЙ", "АРЕНА: РУИНЫ  ◀ ▶")
			_tv_score("P1", "VS", "БОТ ★★", "1–4 ИГРОКА")
		"build":
			_tv_grad(Color(0.05, 0.12, 0.22), Color(0.10, 0.25, 0.40))
			_tv_grid()
			_tv_crop("res://img/body-kit-v1.png", Rect2(470, 245, 240, 315), Rect2(40, 90, 300, 394))
			_tv_live_bar("КАРТОЧКА БОЙЦА", "БОКС 07")
			_tv_text("ГРОМИЛА", Vector2(360, 150), 84, Color(1, 1, 1), f_head)
			_tv_text("МАССА  57 КГ\nДЕТАЛЕЙ  14\nENERGY  91 / 100", Vector2(364, 270), 30, Color(0.75, 0.9, 1.0), f_mono)
		"replay":
			_tv_bg("res://img/00-void-v7-ko.png")
			_tv_live_bar("▶ ПОВТОР", "ТЫ vs ПОЛЕНО · KO 0:47")
			_tv_text("ТРОФЕЙ: ГОЛОВА-ЯЩИК", Vector2(30, 500), 32, Color(1.0, 0.85, 0.4), f_head)
		"testcard":
			var cols := [Color(0.75, 0.75, 0.75), Color(0.75, 0.75, 0), Color(0, 0.75, 0.75), Color(0, 0.75, 0), Color(0.75, 0, 0.75), Color(0.75, 0, 0), Color(0, 0, 0.75)]
			for i in cols.size():
				var r := ColorRect.new()
				r.color = cols[i]
				r.position = Vector2(i * SCREEN_W / 7.0, 0)
				r.size = Vector2(SCREEN_W / 7.0 + 1, SCREEN_H)
				tv_root.add_child(r)
			var band := ColorRect.new()
			band.color = Color(0.05, 0.05, 0.05)
			band.position = Vector2(0, 380)
			band.size = Vector2(SCREEN_W, 120)
			tv_root.add_child(band)
			for i in 6:
				var g := ColorRect.new()
				g.color = Color(i / 5.0, i / 5.0, i / 5.0)
				g.position = Vector2(84 + i * 100, 400)
				g.size = Vector2(100, 80)
				tv_root.add_child(g)
			_tv_text("НАСТРОЙКА ПРИЁМНИКА", Vector2(150, 150), 52, Color(1, 1, 1), f_head, true)
			_tv_text("ЯРКОСТЬ: ВИДНЫ ВСЕ 6 КЛЕТОК?", Vector2(120, 520), 28, Color(1, 1, 1), f_mono)


func _tv_bg(path: String) -> void:
	var t := TextureRect.new()
	t.texture = _img(path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.size = Vector2(SCREEN_W, SCREEN_H)
	tv_root.add_child(t)


func _tv_grad(a: Color, b: Color) -> void:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 1)
	var t := TextureRect.new()
	t.texture = gt
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.size = Vector2(SCREEN_W, SCREEN_H)
	tv_root.add_child(t)


func _tv_grid() -> void:
	for i in 13:
		var v := ColorRect.new()
		v.color = Color(1, 1, 1, 0.07)
		v.position = Vector2(i * 64, 0)
		v.size = Vector2(1, SCREEN_H)
		tv_root.add_child(v)
	for i in 10:
		var h := ColorRect.new()
		h.color = Color(1, 1, 1, 0.07)
		h.position = Vector2(0, i * 64)
		h.size = Vector2(SCREEN_W, 1)
		tv_root.add_child(h)


func _tv_crop(path: String, region: Rect2, dst: Rect2) -> void:
	var at := AtlasTexture.new()
	at.atlas = _img(path)
	at.region = region
	var t := TextureRect.new()
	t.texture = at
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.position = dst.position
	t.size = dst.size
	tv_root.add_child(t)


func _tv_text(s: String, pos: Vector2, px: int, col: Color, font: Font, shadow := false) -> Label:
	var l := Label.new()
	l.text = s
	l.position = pos
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("line_spacing", 2)
	if shadow:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		l.add_theme_constant_override("outline_size", 10)
	tv_root.add_child(l)
	return l


func _tv_rect(pos: Vector2, size: Vector2, col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.position = pos
	r.size = size
	tv_root.add_child(r)
	return r


func _tv_live_bar(tag: String, title: String) -> void:
	_tv_rect(Vector2(24, 22), Vector2(170, 46), Color(0.8, 0.1, 0.1))
	_tv_text(tag, Vector2(36, 24), 30, Color(1, 1, 1), f_head)
	_tv_rect(Vector2(194, 22), Vector2(SCREEN_W - 218, 46), Color(0.05, 0.05, 0.07, 0.85))
	_tv_text(title, Vector2(210, 26), 28, Color(1, 1, 1), f_head)


func _tv_score(a: String, mid: String, b: String, extra: String) -> void:
	var y := SCREEN_H - 140.0
	_tv_rect(Vector2(24, y), Vector2(SCREEN_W - 48, 56), Color(0.05, 0.05, 0.07, 0.88))
	_tv_rect(Vector2(24, y), Vector2(8, 56), C_TEAL)
	_tv_rect(Vector2(SCREEN_W - 32, y), Vector2(8, 56), Color(0.85, 0.35, 0.15))
	_tv_text(a, Vector2(48, y + 6), 36, Color(1, 1, 1), f_head)
	_tv_text(mid, Vector2(SCREEN_W * 0.5 - 50, y + 4), 40, Color(1.0, 0.85, 0.4), f_head)
	_tv_text(b, Vector2(SCREEN_W - 240, y + 6), 36, Color(1, 1, 1), f_head)
	_tv_text(extra, Vector2(SCREEN_W * 0.5 - 60, y + 60), 22, Color(0.75, 0.85, 1.0), f_mono)


func _tv_ticker(s: String) -> void:
	_tv_rect(Vector2(0, SCREEN_H - 48), Vector2(SCREEN_W, 48), Color(0.95, 0.75, 0.2))
	_tv_text(s + s, Vector2(-40, SCREEN_H - 44), 26, Color(0.08, 0.06, 0.04), f_head)


## Заглушка N0 в углу эфира: круглый дрон с линзой (дизайна N0 ещё нет).
func _tv_n0() -> void:
	var p := Vector2(SCREEN_W - 150, 100)
	var body := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.9, 0.85, 0.72)
	sb.set_corner_radius_all(60)
	sb.border_color = Color(0.3, 0.25, 0.2)
	sb.set_border_width_all(5)
	body.add_theme_stylebox_override("panel", sb)
	body.position = p
	body.size = Vector2(120, 120)
	tv_root.add_child(body)
	var lens := Panel.new()
	var sl := StyleBoxFlat.new()
	sl.bg_color = Color(0.1, 0.15, 0.25)
	sl.set_corner_radius_all(26)
	sl.border_color = Color(0.4, 0.9, 1.0)
	sl.set_border_width_all(6)
	lens.add_theme_stylebox_override("panel", sl)
	lens.position = p + Vector2(34, 34)
	lens.size = Vector2(52, 52)
	tv_root.add_child(lens)
	_tv_text("N0", p + Vector2(40, 124), 30, Color(1, 1, 1), f_head, true)


# ---------------------------------------------------------------- меню справа

func _build_ui() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 10
	add_child(cl)
	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(ui_root)
	# субтитр эфира слева внизу
	sub_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)
	sb.set_content_margin_all(12)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.set_corner_radius_all(4)
	sub_panel.add_theme_stylebox_override("panel", sb)
	sub_panel.position = Vector2(48, 900 - 96)
	ui_root.add_child(sub_panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	sub_panel.add_child(hb)
	sub_who = Label.new()
	sub_who.add_theme_font_override("font", f_mono)
	sub_who.add_theme_font_size_override("font_size", 20)
	sub_who.add_theme_color_override("font_color", Color(1.0, 0.6, 0.25))
	hb.add_child(sub_who)
	sub_label = Label.new()
	sub_label.add_theme_font_override("font", f_body)
	sub_label.add_theme_font_size_override("font_size", 21)
	sub_label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	hb.add_child(sub_label)


func _apply_sub(s: String) -> void:
	sub_panel.visible = s != ""
	var parts := s.split(":", true, 1)
	sub_who.text = parts[0] if parts.size() > 1 else ""
	sub_label.text = parts[1].strip_edges() if parts.size() > 1 else s
	sub_panel.reset_size()


func _apply_menu(focus: String) -> void:
	var old := ui_root.get_node_or_null("Menu")
	if old != null:
		ui_root.remove_child(old)
		old.queue_free()
	if focus == "none":
		return
	var vw := 1600.0
	var vh := 900.0
	var root := Control.new()
	root.name = "Menu"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(root)
	# затемнение правой части: градиент от прозрачного к тёмному
	var g := Gradient.new()
	g.set_color(0, Color(0.01, 0.01, 0.02, 0.0))
	g.set_color(1, Color(0.01, 0.01, 0.02, 0.93))
	g.add_point(0.32, Color(0.01, 0.01, 0.02, 0.78))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	var shade := TextureRect.new()
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.position = Vector2(vw * 0.52, 0)
	shade.size = Vector2(vw * 0.48, vh)
	root.add_child(shade)
	var x0 := vw * 0.655
	var accent := Color(1.0, 0.55, 0.2)
	_ui_text(root, "NULL FIGHTING  ·  BAY 07", Vector2(x0, 66), 15, Color(1.0, 0.7, 0.35, 0.9), f_mono)
	_ui_text(root, "RAGDOLL", Vector2(x0 - 3, 86), 66, Color(1, 1, 1), f_head)
	_ui_text(root, "MASTER", Vector2(x0 - 3, 152), 66, accent, f_head)
	if focus == "title":
		_ui_text(root, "build · fly · smash", Vector2(x0, 236), 24, Color(0.85, 0.85, 0.85), f_body)
		_ui_rect(root, Vector2(x0, 330), Vector2(390, 2), Color(1, 1, 1, 0.15))
		_ui_text(root, "НАЖМИ ЛЮБУЮ КНОПКУ", Vector2(x0, 352), 34, Color(1, 1, 1), f_head)
		_ui_text(root, "клавиатура · геймпад · мышь", Vector2(x0, 398), 18, Color(0.7, 0.7, 0.7), f_body)
		_ui_text(root, "МЕСТНАЯ ЛИГА  ·  NULL FIELD 0.20G  ·  v0.1 demo", Vector2(x0, vh - 64), 14, Color(0.6, 0.6, 0.65), f_mono)
		return
	_ui_rect(root, Vector2(x0, 244), Vector2(420, 2), Color(1, 1, 1, 0.14))
	var y := 272.0
	for it in MENU_ITEMS:
		var name: String = it[0]
		if name == focus:
			_ui_rect(root, Vector2(x0 - 22, y - 6), Vector2(470, 132), Color(1.0, 0.55, 0.2, 0.13))
			_ui_rect(root, Vector2(x0 - 22, y - 6), Vector2(5, 132), accent)
			_ui_text(root, name, Vector2(x0, y - 4), 46, Color(1, 1, 1), f_head)
			_ui_text(root, it[1], Vector2(x0 + 2, y + 60), 19, Color(0.95, 0.88, 0.78), f_body)
			_ui_text(root, it[2], Vector2(x0 + 2, y + 88), 17, Color(0.7, 0.7, 0.72), f_body)
			_ui_text(root, "ENTER ▸", Vector2(x0 + 360, y + 12), 18, accent, f_mono)
			y += 150.0
		else:
			_ui_text(root, name, Vector2(x0, y), 30, Color(0.82, 0.8, 0.76, 0.8), f_head)
			y += 58.0
	_ui_text(root, "ВЫХОД", Vector2(x0, vh - 120), 22, Color(0.6, 0.6, 0.6, 0.8), f_head)
	_ui_rect(root, Vector2(x0, vh - 78), Vector2(420, 1), Color(1, 1, 1, 0.12))
	_ui_text(root, "↑↓  ВЫБОР     ENTER  ВОЙТИ     ESC  НАЗАД", Vector2(x0, vh - 64), 15, Color(0.65, 0.65, 0.7), f_mono)


func _ui_text(parent: Control, s: String, pos: Vector2, px: int, col: Color, font: Font) -> Label:
	var l := Label.new()
	l.text = s
	l.position = pos
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l


func _ui_rect(parent: Control, pos: Vector2, size: Vector2, col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.position = pos
	r.size = size
	parent.add_child(r)
	return r
