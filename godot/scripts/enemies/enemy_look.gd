## Внешность и телеграф врага PvE (LORE.md «Враги: профессия → сломанная программа → физика»). Узел-ребёнок куклы врага; его
## создаёт EnemyBrain (setup). Враг собран из ТЕХ ЖЕ деталей, что игрок, поэтому отличие — только краской и светом:
##   • тон: все материалы куклы и её оружия перекрашиваются (override поверхности, общий ресурс не трогаем) — дерево тёмное и
##     ржавое (× WOOD_TINT), железо ржавее (× IRON_TINT), обмотки и краска «Shirt*/Paint*» — тёмно-ржавые (цвета игрока нет:
##     Doll._recolor красит их в PLAYER_COLORS[0] — здесь перекрашивается обратно). Копии материалов общие для всех врагов
##     (кэш по исходному материалу): 5 врагов не множат уникальные материалы;
##   • глаза — две светящиеся точки на лице (эмиссия, красный), Ядро — светящаяся точка на груди: «сломанная программа» видна
##     в любом зуме, даже когда враг летит кувырком. Позиции считаются по коллизиям головы и торса при сборке (кукла стоит прямо);
##   • телеграф: alert 0…1 (ставит мозг) — глаза и Ядро разгораются от тускло-красного до бело-оранжевого, включается OmniLight
##     на голове (только пока alert > 0: 5 врагов без лишних источников света); telegraph(text, s) — надпись капсом над головой
##     (рисует HUD: scenes/pve/pve_hud.gd читает callout / callout_until) и звук-заглушка;
##   • KO — глаза и Ядро гаснут («Ядро остановилось»).
## Звук — AudioStreamPlayer3D на торсе, синтетические AudioStreamWAV (как ScrapMachine): warn_sweep (нарастающий гул), warn_grab
## (стрёкот), ratchet (трещотка откручивания), yoink (свист кражи), drop (глухой щелчок) — заглушки до настоящих.
class_name EnemyLook
extends Node

const WOOD_TINT := Color(0.40, 0.27, 0.21)
const IRON_TINT := Color(0.62, 0.44, 0.36)
const CLOTH_COLOR := Color(0.30, 0.10, 0.07)
const FACE_TINT := Color(0.55, 0.45, 0.40)
const EYE_COLOR := Color(1.0, 0.16, 0.05)
const EYE_HOT := Color(1.0, 0.72, 0.35)
const EYE_IDLE_ENERGY := 2.2
const EYE_ALERT_ENERGY := 9.0
const EYE_RADIUS := 0.03
const CORE_RADIUS := 0.045
const LIGHT_ENERGY := 2.6
const LIGHT_RANGE := 2.4
const ALERT_RISE := 14.0              # 1/с — глаза вспыхивают почти сразу (телеграф читается с первого кадра)
const ALERT_FALL := 4.0
const SFX_RATE := 22050
const IRON_NAMES := ["Rust", "Iron", "Steel", "Brass", "Joint", "Pin", "Metal", "Chain"]
const CLOTH_NAMES := ["Shirt", "Paint", "Rope", "Cloth"]

## Надпись над головой (HUD) и до какого времени (сек, clock()).
var callout := ""
var callout_until := -1.0
var callout_colour := Color(1.0, 0.55, 0.2)
## Текущий уровень тревоги (сглаженный) и цель.
var alert := 0.0
var alert_target := 0.0
var doll: Doll
var eyes: Array[MeshInstance3D] = []
var core_dot: MeshInstance3D
var light: OmniLight3D
var sfx: AudioStreamPlayer3D
var _eye_mat: StandardMaterial3D
var _dead := false
var _clock := 0.0

static var _tint_cache: Dictionary = {}     # instance id исходного материала -> перекрашенная копия
static var _wav_cache: Dictionary = {}


## Время телеграфа/надписей (физическое, детерминировано при --fixed-fps).
func clock() -> float:
	return _clock


## Внешность куклы: тон, глаза, Ядро, свет, звук. Зовётся после сборки куклы (Doll._ready уже прошёл).
func setup(d: Doll) -> void:
	doll = d
	tint_node(doll)
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color(0.05, 0.02, 0.02)
	_eye_mat.emission_enabled = true
	_eye_mat.emission = EYE_COLOR
	_eye_mat.emission_energy_multiplier = EYE_IDLE_ENERGY
	_eye_mat.roughness = 0.3
	var head := doll.parts.get("Head") as RigidBody3D
	var torso := doll.parts.get("Torso") as RigidBody3D
	if head != null:
		var hb := _world_bounds(head)
		var c := hb.get_center()
		var s := hb.size
		for sx in [-1.0, 1.0]:
			var p := c + Vector3(sx * maxf(s.x * 0.2, 0.04), s.y * 0.1, s.z * 0.5 + 0.012)
			eyes.append(_dot(head, head.to_local(p), EYE_RADIUS))
		light = OmniLight3D.new()
		light.name = "AlertLight"
		light.light_color = EYE_COLOR
		light.omni_range = LIGHT_RANGE
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.visible = false
		head.add_child(light)
		light.position = head.to_local(c + Vector3(0.0, 0.0, s.z * 0.5 + 0.25))
	if torso != null:
		var tb := _world_bounds(torso)
		core_dot = _dot(torso, torso.to_local(tb.get_center() + Vector3(0.0, tb.size.y * 0.12, tb.size.z * 0.5 + 0.015)), CORE_RADIUS)
		sfx = AudioStreamPlayer3D.new()
		sfx.name = "EnemySfx"
		sfx.volume_db = -6.0
		sfx.max_distance = 40.0
		torso.add_child(sfx)
	doll.knocked_out.connect(func(_a: Node, _r: Dictionary) -> void: _die())


func _dot(body: Node3D, local: Vector3, r: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 5
	mi.mesh = sm
	mi.material_override = _eye_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	body.add_child(mi)
	mi.position = local
	return mi


## Перекрасить все меши под узлом n (кукла, её оружие) в «ржавчину арены».
func tint_node(n: Node) -> void:
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null or mi.material_override != null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var mat := mi.get_active_material(s)
			if mat == null or not mat is BaseMaterial3D:
				continue
			mi.set_surface_override_material(s, _tinted(mat as BaseMaterial3D))


static func _tinted(src: BaseMaterial3D) -> BaseMaterial3D:
	var id := src.get_instance_id()
	if _tint_cache.has(id):
		return _tint_cache[id]
	var dup := src.duplicate() as BaseMaterial3D
	var nm := src.resource_name
	var a := dup.albedo_color.a
	if _name_has(nm, CLOTH_NAMES):
		dup.albedo_color = Color(CLOTH_COLOR.r, CLOTH_COLOR.g, CLOTH_COLOR.b, a)
	elif nm.begins_with("Face"):
		dup.albedo_color = dup.albedo_color * FACE_TINT
	elif nm == "Char":
		pass
	elif _name_has(nm, IRON_NAMES):
		dup.albedo_color = dup.albedo_color * IRON_TINT
	else:
		dup.albedo_color = dup.albedo_color * WOOD_TINT
	dup.albedo_color.a = a
	dup.roughness = clampf(dup.roughness + 0.1, 0.0, 1.0)
	_tint_cache[id] = dup
	return dup


static func _name_has(nm: String, keys: Array) -> bool:
	for k in keys:
		if nm.begins_with(String(k)):
			return true
	return false


## Габарит коллизий тела в мире (по полуразмерам форм, как ModularDoll._shape_half).
static func _world_bounds(b: RigidBody3D) -> AABB:
	var box := AABB()
	var first := true
	for cs in b.find_children("*", "CollisionShape3D", true, false):
		var sh := (cs as CollisionShape3D).shape
		if sh == null:
			continue
		var h := Vector3.ONE * 0.05
		if sh is BoxShape3D:
			h = (sh as BoxShape3D).size * 0.5
		elif sh is CapsuleShape3D:
			h = Vector3((sh as CapsuleShape3D).radius, maxf((sh as CapsuleShape3D).height * 0.5, (sh as CapsuleShape3D).radius), (sh as CapsuleShape3D).radius)
		elif sh is SphereShape3D:
			h = Vector3.ONE * (sh as SphereShape3D).radius
		elif sh is CylinderShape3D:
			h = Vector3((sh as CylinderShape3D).radius, (sh as CylinderShape3D).height * 0.5, (sh as CylinderShape3D).radius)
		var w: AABB = (cs as Node3D).global_transform * AABB(-h, h * 2.0)
		box = w if first else box.merge(w)
		first = false
	if first:
		return AABB(b.global_position - Vector3.ONE * 0.1, Vector3.ONE * 0.2)
	return box


## Телеграф: надпись над головой на seconds (HUD) и звук. Свет — alert (ставит мозг каждый тик).
func telegraph(text: String, seconds: float, sound: String = "", colour := Color(1.0, 0.55, 0.2)) -> void:
	callout = text
	callout_until = _clock + seconds
	callout_colour = colour
	if sound != "":
		play(sound)


func callout_active() -> bool:
	return callout != "" and _clock < callout_until and not _dead


func play(kind: String) -> void:
	if sfx == null or not is_instance_valid(sfx) or _dead:
		return
	sfx.stream = _wav(kind)
	sfx.play()


func _physics_process(delta: float) -> void:
	_clock += delta
	if doll == null or _dead:
		return
	var rate := ALERT_RISE if alert_target > alert else ALERT_FALL
	alert = move_toward(alert, alert_target, rate * delta)
	if _eye_mat != null:
		_eye_mat.emission = EYE_COLOR.lerp(EYE_HOT, alert)
		_eye_mat.emission_energy_multiplier = lerpf(EYE_IDLE_ENERGY, EYE_ALERT_ENERGY, alert)
	if light != null:
		light.visible = alert > 0.02
		light.light_energy = LIGHT_ENERGY * alert
		light.light_color = EYE_COLOR.lerp(EYE_HOT, alert * 0.6)


func _die() -> void:
	_dead = true
	alert = 0.0
	callout = ""
	if _eye_mat != null:   # свой у каждой куклы (глаза и Ядро) — гасим его
		_eye_mat.emission_energy_multiplier = 0.0
		_eye_mat.albedo_color = Color(0.12, 0.1, 0.09)
	if light != null and is_instance_valid(light):
		light.visible = false


# --- звук-заглушка ---

static func _wav(kind: String) -> AudioStreamWAV:
	if _wav_cache.has(kind):
		return _wav_cache[kind]
	var dur := 0.4
	match kind:
		"warn_sweep": dur = 0.45
		"warn_grab": dur = 0.35
		"ratchet": dur = 0.9
		"yoink": dur = 0.25
		"drop": dur = 0.12
	var n := int(dur * SFX_RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var ph := 0.0
	for i in range(n):
		var t := float(i) / SFX_RATE
		var u := t / dur
		var v := 0.0
		match kind:
			"warn_sweep":   # гул снизу вверх 110 → 330 Гц, квадрат с мягким краем
				ph += TAU * lerpf(110.0, 330.0, u) / SFX_RATE
				v = clampf(sin(ph) * 3.0, -1.0, 1.0) * 0.35 * minf(u * 8.0, 1.0)
			"warn_grab":    # стрёкот: пачки щелчков 28 Гц
				var click := fmod(t * 28.0, 1.0) < 0.18
				v = (rng.randf_range(-1.0, 1.0) * 0.5 + sin(TAU * 1400.0 * t) * 0.3) * (1.0 if click else 0.0)
			"ratchet":      # трещотка: щелчки 12 Гц с затуханием каждого
				var k := fmod(t * 12.0, 1.0)
				v = rng.randf_range(-1.0, 1.0) * exp(-k * 30.0) * 0.7
			"yoink":        # свист вверх
				ph += TAU * lerpf(500.0, 1800.0, u * u) / SFX_RATE
				v = sin(ph) * 0.35 * (1.0 - u)
			"drop":
				v = rng.randf_range(-1.0, 1.0) * exp(-u * 8.0) * 0.6
		var s := int(clampf(v, -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, s)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SFX_RATE
	w.stereo = false
	w.data = data
	_wav_cache[kind] = w
	return w
