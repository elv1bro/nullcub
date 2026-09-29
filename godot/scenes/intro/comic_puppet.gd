## Кукла-марионетка заставки-комикса (docs/plan-demo/INTRO_COMIC.md): меши манекена v3 без физики, суставы — иерархия
## Node3D (FK), поза — словарь «сустав → углы Эйлера в градусах». Сцены comic_puppet.tscn (клён) и comic_puppet_dark.tscn
## (орех) собирает tools/build_intro_comic.gd; здесь только поведение. Позу можно ставить и руками в редакторе — это
## обычные повороты узлов-суставов.
##
## Дерево: ComicPuppet (ступни на y=0, лицо к +Z)
##   └ Root (таз, y 0.91) — поворот/сдвиг всего тела; ключ позы "Root" (углы) и "Root_pos" (сдвиг, м)
##       ├ TorsoMesh, CoreGlow (свет в груди), Crown (корона на Ядре)
##       ├ Neck → HeadMesh, Eye_L, Eye_R
##       ├ Shoulder_L → UpperArm_L → Elbow_L → LowerArm_L → Wrist_L → Hand_L (так же _R)
##       └ Hip_L → UpperLeg_L → Knee_L → LowerLeg_L → Ankle_L → Foot_L (так же _R)
## Оси сустава (кукла смотрит в +Z): X− — конечность вперёд (к лицу), Z+ — левая наружу / правая внутрь, Y — кручение.
## Локоть сгибается X−, колено X+, бедро вперёд X−.
class_name ComicPuppet
extends Node3D

const JOINTS := ["Root", "Neck", "Shoulder_L", "Elbow_L", "Wrist_L", "Shoulder_R", "Elbow_R", "Wrist_R",
	"Hip_L", "Knee_L", "Ankle_L", "Hip_R", "Knee_R", "Ankle_R"]
## Меш части → сустав, которым она крепится (для hide_part / swap_part).
const PART_JOINT := {"Torso": "Root", "Head": "Neck", "UpperArm_L": "Shoulder_L", "LowerArm_L": "Elbow_L",
	"Hand_L": "Wrist_L", "UpperArm_R": "Shoulder_R", "LowerArm_R": "Elbow_R", "Hand_R": "Wrist_R",
	"UpperLeg_L": "Hip_L", "LowerLeg_L": "Knee_L", "Foot_L": "Ankle_L", "UpperLeg_R": "Hip_R",
	"LowerLeg_R": "Knee_R", "Foot_R": "Ankle_R"}
const MESH_DIR := "res://assets/models/heroes/mannequin_v3/%s/%s.glb"

@export var player_color := Color("2f6fde")
## Цвет свечения глаз и Ядра (герой — золото Короны, враг — красный).
@export var eye_color := Color(1.0, 0.72, 0.28)
## Свечение глаз (0 — тёмные дырочки, 1 — горят); множитель энергии эмиссии.
@export_range(0.0, 1.0, 0.01) var eye_glow := 0.0
## Прищур: глаза-щёлки (1 — злой взгляд).
@export_range(0.0, 1.0, 0.01) var eye_squint := 0.0
## Свет Ядра в груди и корона на нём.
@export_range(0.0, 1.0, 0.01) var core_glow := 0.0
@export var eye_energy := 9.0
@export var core_energy := 0.0
## Родная порода деталей (light — клён, dark — орех); swap_part/set_part_state меняют отдельные части.
@export var base_tone := "light"
## Пол для разлёта частей (мировой y).
@export var ground_y := 0.0

const SHATTER_G := Vector3(0.0, -5.0, 0.0)
var _shatter: Dictionary = {}    # часть → {local, g0, v, w}

var _j: Dictionary = {}          # имя сустава → Node3D
var _rest: Dictionary = {}       # имя сустава → Transform3D покоя (из сцены)
var _eye_mat: StandardMaterial3D
var _crown_mat: StandardMaterial3D
var _flicker_t := 0.0
## Мерцание Ядра (0 — ровно): для кадра «Ядро оживает».
var core_flicker := 0.0


func _ready() -> void:
	for n in JOINTS:
		var node := find_child(n, true, false) as Node3D
		if node == null:
			push_warning("ComicPuppet: нет сустава %s" % n)
			continue
		_j[n] = node
		_rest[n] = node.transform
	_recolor(self, "Shirt", player_color)
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color(0.03, 0.02, 0.015)
	_eye_mat.roughness = 0.3
	_eye_mat.emission_enabled = true
	_eye_mat.emission = eye_color
	for e in ["Eye_L", "Eye_R"]:
		var mi := find_child(e, true, false) as MeshInstance3D
		if mi:
			mi.material_override = _eye_mat
	var crown := find_child("Crown", true, false) as MeshInstance3D
	if crown and crown.material_override is StandardMaterial3D:
		_crown_mat = (crown.material_override as StandardMaterial3D).duplicate()
		crown.material_override = _crown_mat
	_apply_glow()


func _process(delta: float) -> void:
	_flicker_t += delta
	_apply_glow()


func joint(n: String) -> Node3D:
	return _j.get(n)


## Ставит позу: ключи — суставы (Vector3 градусы), "Root_pos" — сдвиг таза (м). Суставы без ключа — в покое.
func set_pose(pose: Dictionary) -> void:
	for n in _j:
		var node: Node3D = _j[n]
		var rest: Transform3D = _rest[n]
		var e: Vector3 = pose.get(n, Vector3.ZERO)
		var off: Vector3 = pose.get("Root_pos", Vector3.ZERO) if n == "Root" else Vector3.ZERO
		node.transform = Transform3D(Basis.from_euler(e * (PI / 180.0)), rest.origin + off)


## Смешивание двух поз (линейно по углам — позы близкие, кватернионы не нужны).
static func blend(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for k in a.keys() + b.keys():
		if out.has(k):
			continue
		out[k] = (a.get(k, Vector3.ZERO) as Vector3).lerp(b.get(k, Vector3.ZERO), t)
	return out


## Прячет меш части (и только его: дистальные части прячутся отдельно).
func hide_part(part: String, hidden := true) -> void:
	var m := _part_mesh(part)
	if m:
		m.visible = not hidden


## Меняет меш части на другую породу дерева (light | dark) — «приделал чужую деталь».
func swap_part(part: String, tone: String) -> void:
	var m := _part_mesh(part)
	if m == null:
		return
	var ps: PackedScene = load(MESH_DIR % [tone, part])
	if ps == null:
		return
	var n: Node3D = ps.instantiate()
	var nm := m.name
	var idx := m.get_index()
	n.transform = m.transform
	n.visible = m.visible
	var parent := m.get_parent()
	# дети старого меша (глаза, корона, снаряжение) переезжают на новый
	for c in m.get_children():
		if c.owner != m:
			m.remove_child(c)
			n.add_child(c)
	parent.remove_child(m)
	m.free()
	n.name = nm
	parent.add_child(n)
	parent.move_child(n, idx)
	if tone == base_tone:
		_recolor(n, "Shirt", player_color)   # чужая деталь сохраняет обмотки прежнего хозяина


func part_node(part: String) -> Node3D:
	return _part_mesh(part)


## Видимость и порода части одним вызовом (tone "" — родная порода куклы); меш меняется только при смене породы.
func set_part_state(part: String, visible_: bool, tone: String = "") -> void:
	var m := _part_mesh(part)
	if m == null:
		return
	var want := tone if tone != "" else base_tone
	if String(m.get_meta("tone", base_tone)) != want:
		swap_part(part, want)
		m = _part_mesh(part)
		m.set_meta("tone", want)
	if m.visible != visible_:
		m.visible = visible_


## Разлёт на части (KO как в игре): dt < 0 — собрать обратно; dt ≥ 0 — части летят от позы момента разлёта по баллистике
## со скоростью vel + разброс (seed — повторяемый разброс), падают до пола ground_y (мировой y) и замирают.
func set_shatter(dt: float, vel: Vector3, seed_: int) -> void:
	if dt < 0.0:
		if _shatter.is_empty():
			return
		for part in _shatter:
			var m := _part_mesh(part)
			if m:
				m.top_level = false
				m.transform = _shatter[part]["local"]
		_shatter.clear()
		return
	if _shatter.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_
		var centre := (_j["Root"] as Node3D).global_position + Vector3(0.0, 0.3, 0.0)
		for part in PART_JOINT:
			var m := _part_mesh(part)
			if m == null or not m.visible:
				continue
			var g := m.global_transform
			var out := (g.origin - centre)
			out.z *= 0.3
			var v := vel + out.normalized() * rng.randf_range(1.2, 3.2) + Vector3(0.0, rng.randf_range(0.5, 2.5), 0.0)
			var w := Vector3(rng.randf_range(-9, 9), rng.randf_range(-9, 9), rng.randf_range(-12, 12))
			_shatter[part] = {"local": m.transform, "g0": g, "v": v, "w": w}
	for part in _shatter:
		var m := _part_mesh(part)
		if m == null:
			continue
		var s: Dictionary = _shatter[part]
		var g0: Transform3D = s["g0"]
		var v: Vector3 = s["v"]
		var w: Vector3 = s["w"]
		# баллистика до пола: время касания — первый корень y(t) = ground_y
		var p := g0.origin + v * dt + 0.5 * SHATTER_G * dt * dt
		var t_rot := dt
		if p.y < ground_y:
			var a := 0.5 * SHATTER_G.y
			var disc := v.y * v.y - 4.0 * a * (g0.origin.y - ground_y)
			var t_hit := (-v.y - sqrt(maxf(disc, 0.0))) / (2.0 * a)
			t_hit = clampf(t_hit, 0.0, dt)
			p = g0.origin + v * t_hit + 0.5 * SHATTER_G * t_hit * t_hit
			var slide := minf(dt - t_hit, 0.25)
			p += Vector3(v.x, 0.0, v.z) * slide * 0.3
			p.y = ground_y
			t_rot = t_hit + slide * 0.3
		m.top_level = true
		var b := g0.basis.rotated(Vector3.RIGHT, w.x * t_rot).rotated(Vector3.UP, w.y * t_rot * 0.3).rotated(Vector3.BACK, w.z * t_rot)
		m.global_transform = Transform3D(b.orthonormalized(), p)


## Мировая точка части (для привязки 2D-эффектов комикса): голова — центр яйца, кисть — середина ладони и т.п.
func anchor_world(part: String) -> Vector3:
	match part:
		"Head":
			return (_j["Neck"] as Node3D).global_transform * Vector3(0.0, 0.16, 0.02)
		"Chest":
			return (_j["Root"] as Node3D).global_transform * Vector3(0.0, 0.40, 0.12)
		"Hand_L":
			return (_j["Wrist_L"] as Node3D).global_transform * Vector3(0.0, -0.08, 0.0)
		"Hand_R":
			return (_j["Wrist_R"] as Node3D).global_transform * Vector3(0.0, -0.08, 0.0)
		"Elbow_R":
			return (_j["Elbow_R"] as Node3D).global_position
		"Feet":
			return ((_j["Ankle_L"] as Node3D).global_position + (_j["Ankle_R"] as Node3D).global_position) * 0.5
	return (_j["Root"] as Node3D).global_position


func _part_mesh(part: String) -> Node3D:
	var jn: Node3D = _j.get(PART_JOINT.get(part, ""))
	if jn == null:
		return null
	return jn.get_node_or_null(part + "Mesh") as Node3D


func _apply_glow() -> void:
	if _eye_mat:
		_eye_mat.emission = eye_color
		_eye_mat.emission_energy_multiplier = eye_energy * eye_glow
		for e in ["Eye_L", "Eye_R"]:
			var mi := find_child(e, true, false) as Node3D
			if mi:
				mi.scale = Vector3(lerpf(1.0, 1.6, eye_squint), lerpf(1.0, 0.32, eye_squint), 1.0)
	var fl := 1.0
	if core_flicker > 0.0:
		fl = lerpf(1.0, 0.15 + 0.85 * absf(sin(_flicker_t * 23.0) * sin(_flicker_t * 7.3)), core_flicker)
	var cg := core_glow * fl
	var light := find_child("CoreGlow", true, false) as OmniLight3D
	if light:
		light.light_energy = core_energy * cg
		light.visible = cg > 0.001
	if _crown_mat:
		var hdr := 1.0 + 2.4 * cg
		_crown_mat.albedo_color = Color(1.0 * hdr, 0.78 * hdr, 0.35 * hdr, clampf(cg * 1.5, 0.0, 1.0))


func _recolor(n: Node, material_name: String, colour: Color) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		if mi.mesh:
			for s in range(mi.mesh.get_surface_count()):
				var mat: Material = mi.get_active_material(s)
				if mat == null or not mat.resource_name.begins_with(material_name):
					continue
				var dup: Material = mat.duplicate()
				if dup is BaseMaterial3D:
					var c := colour
					c.a = (dup as BaseMaterial3D).albedo_color.a
					(dup as BaseMaterial3D).albedo_color = c
				mi.set_surface_override_material(s, dup)
	for c in n.get_children():
		_recolor(c, material_name, colour)
