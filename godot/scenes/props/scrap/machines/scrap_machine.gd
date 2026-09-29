## Механизм Свалки (лист 04 «Machines & Hazards», kit-02 «Interactive elements: off / warning / active / cooldown») — общий цикл
## состояний, телеграф и помощники. Конкретное поведение — наследники: magnet_machine.gd (№079 магнит на цепи), steam_vent_machine.gd
## (№078 паровой клапан), press_machine.gd (№067 пресс), chute_machine.gd (№061 мусорный желоб). Дерево узлов — сцены
## scenes/props/scrap/machine_*.tscn (tools/build_scrap_machines_scenes.gd), модели — tools/blender/scrap_machines.py.
##
## Цикл: OFF (off_s) → WARNING (warning_s ≈ 1 с: лампы мигают BLINK_HZ, гудок, частицы) → ACTIVE (active_s) → COOLDOWN (cooldown_s:
## лампы гаснут) → OFF. Время — физическое (_physics_process), при --fixed-fps детерминировано. auto_cycle = false — стоит в OFF,
## пока не позовут trigger(); phase_offset_s — сколько секунд уже «прошло» в OFF на старте (механизмы арены не срабатывают разом;
## > off_s — первый цикл раньше). force_state() — для проб и кадров.
## Лампы: поверхности мешей с материалом "Lamp" / "Coil" (слоты glb) получают свои StandardMaterial3D — цвет и яркость по
## состоянию (lamp_*_color, *_ENERGY); OmniLight3D lamp_light_path (если есть) повторяет яркость ламп × lamp_light_energy.
## Звук — AudioStreamPlayer3D sfx_path: синтетические AudioStreamWAV (гудок, шипение, удар, гул, грохот) — заглушки до настоящих.
## Помощники для наследников и проб (static): iron_mass(b) — сколько кг железа в теле (тянет магнит), body_width(b) — ширина тела
## по x (парус пара), doll_of(b) — кукла, чья это часть.
class_name ScrapMachine
extends Node3D

signal state_changed(state: int, prev: int)

enum State { OFF, WARNING, ACTIVE, COOLDOWN }
const STATE_NAMES := ["OFF", "WARNING", "ACTIVE", "COOLDOWN"]
const BLINK_HZ := 4.0
const OFF_ENERGY := 0.25
const WARN_ENERGY := 5.0
const ACTIVE_ENERGY := 4.0
const COIL_ACTIVE_ENERGY := 3.0
## Метаданные тела: "material" = "iron" | "wood" (или число — кг железа). Их пишут builder арены (пропсы), желоб (куски), лут.
const META_MATERIAL := &"material"
const META_IRON_CACHE := &"_scrap_iron_kg"
## Доля железа в массе обычного оружия (scenes/weapons: головки/клинки железные, рукояти деревянные).
const WEAPON_IRON := {"hammer": 0.7, "mace": 0.8, "sword": 0.85, "axe": 0.6, "pan": 1.0}
## Железные куски хлама по имени узла (как METAL_BITS в tools/build_scrap_bodies_scenes.gd).
const IRON_BITS := ["Rivet_Plate", "Gear_Small", "Gear_Medium", "Gear_Large", "Chain_Link", "Chain_Segment", "Bolt", "Nut", "Nail",
	"Pipe_Piece", "Sword_Broken", "Helmet", "Shield_Crown", "Hammer_Old", "Axe_Old", "Mace_Old", "Metal_Barrel"]
const SFX_RATE := 22050

@export var auto_cycle := true
@export var off_s := 4.0
@export var warning_s := 1.0
@export var active_s := 2.0
@export var cooldown_s := 2.0
@export var phase_offset_s := 0.0
@export var lamp_warn_color := Color(1.0, 0.55, 0.1)
@export var lamp_active_color := Color(1.0, 0.22, 0.08)
@export var coil_color := Color(1.0, 0.5, 0.2)
@export var lamp_light_energy := 1.5
@export var sfx_volume_db := -8.0
## Свет ламп и звук: у магнита они едут с диском (Pivot/Head/…), у остальных — дети корня.
@export var lamp_light_path: NodePath = ^"LampLight"
@export var sfx_path: NodePath = ^"Sfx"

var state: int = State.OFF
var state_t := 0.0
var time := 0.0
## Завершённые циклы (COOLDOWN → OFF) и журнал смен состояний [{state, t}] — для проб.
var cycles := 0
var history: Array = []

var _lamp_mat: StandardMaterial3D
var _coil_mat: StandardMaterial3D
var _lamp_light: OmniLight3D
var _sfx: AudioStreamPlayer3D
static var _wav_cache: Dictionary = {}


func _ready() -> void:
	state_t = phase_offset_s
	_lamp_light = get_node_or_null(lamp_light_path) as OmniLight3D
	_sfx = get_node_or_null(sfx_path) as AudioStreamPlayer3D
	if _sfx != null:
		_sfx.volume_db = sfx_volume_db
	_bind_lamps(self)
	_update_lamps()
	_machine_ready()


func _physics_process(delta: float) -> void:
	time += delta
	state_t += delta
	match state:
		State.OFF:
			if auto_cycle and state_t >= off_s:
				_enter(State.WARNING)
		State.WARNING:
			if state_t >= warning_s:
				_enter(State.ACTIVE)
		State.ACTIVE:
			if state_t >= active_s:
				_enter(State.COOLDOWN)
		State.COOLDOWN:
			if state_t >= cooldown_s:
				cycles += 1
				_enter(State.OFF)
	_update_lamps()
	_machine_tick(delta)


## Запустить цикл сейчас (из OFF — в WARNING). true — запущен.
func trigger() -> bool:
	if state != State.OFF:
		return false
	_enter(State.WARNING)
	return true


func force_state(s: int) -> void:
	_enter(s)


## Нашлись ли в мешах слоты ламп (телеграф состояний виден).
func has_lamps() -> bool:
	return _lamp_mat != null


func lamp_energy() -> float:
	return _lamp_mat.emission_energy_multiplier if _lamp_mat != null else 0.0


func state_name() -> String:
	return STATE_NAMES[state]


## Секунд до конца текущего состояния.
func state_left() -> float:
	match state:
		State.OFF:
			return maxf(off_s - state_t, 0.0) if auto_cycle else INF
		State.WARNING:
			return maxf(warning_s - state_t, 0.0)
		State.ACTIVE:
			return maxf(active_s - state_t, 0.0)
	return maxf(cooldown_s - state_t, 0.0)


func _enter(s: int) -> void:
	var prev := state
	state = s
	state_t = 0.0
	history.append({"state": STATE_NAMES[s], "t": snappedf(time, 0.001)})
	if history.size() > 64:
		history.pop_front()
	_on_state(s, prev)
	state_changed.emit(s, prev)


# --- для наследников ---

func _machine_ready() -> void:
	pass


func _machine_tick(_delta: float) -> void:
	pass


func _on_state(_s: int, _prev: int) -> void:
	pass


## Сила лампы 0..1 в текущем состоянии (мигание в WARNING, затухание в COOLDOWN).
func lamp_level() -> float:
	match state:
		State.WARNING:
			return 1.0 if fmod(state_t * BLINK_HZ, 1.0) < 0.5 else 0.1
		State.ACTIVE:
			return 1.0
		State.COOLDOWN:
			return clampf(1.0 - state_t / maxf(cooldown_s, 0.01), 0.0, 1.0)
	return 0.0


func _bind_lamps(n: Node) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i)
			if mat == null:
				continue
			var nm := String(mat.resource_name)
			if nm.begins_with("Lamp"):
				if _lamp_mat == null:
					_lamp_mat = _glow_material(Color(0.55, 0.36, 0.22))
				m.set_surface_override_material(i, _lamp_mat)
			elif nm.begins_with("Coil"):
				if _coil_mat == null:
					_coil_mat = _glow_material(Color(0.22, 0.16, 0.12))
				m.set_surface_override_material(i, _coil_mat)


static func _glow_material(albedo: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = 0.35
	m.emission_enabled = true
	m.emission = Color(1, 0.5, 0.2)
	m.emission_energy_multiplier = OFF_ENERGY
	return m


func _update_lamps() -> void:
	var lv := lamp_level()
	var col := lamp_active_color
	if state == State.WARNING:
		col = lamp_warn_color
	if _lamp_mat != null:
		_lamp_mat.emission = col if lv > 0.0 else Color(1.0, 0.45, 0.2)
		_lamp_mat.emission_energy_multiplier = OFF_ENERGY + lv * (WARN_ENERGY if state == State.WARNING else ACTIVE_ENERGY)
	if _coil_mat != null:
		var c := _coil_level()
		_coil_mat.emission = coil_color
		_coil_mat.emission_energy_multiplier = 0.15 + c * COIL_ACTIVE_ENERGY
	if _lamp_light != null:
		_lamp_light.light_color = col
		_lamp_light.light_energy = lv * lamp_light_energy
		_lamp_light.visible = lv > 0.02


## Свечение рабочей поверхности (магнит): по умолчанию — как лампы, но без мигания.
func _coil_level() -> float:
	if state == State.WARNING:
		return 0.25 * clampf(state_t / maxf(warning_s, 0.01), 0.0, 1.0)
	return lamp_level()


# --- звук-заглушка ---

func play_sfx(kind: String, pitch := 1.0) -> void:
	if _sfx == null or not is_inside_tree():
		return
	_sfx.stream = synth(kind)
	_sfx.pitch_scale = pitch
	_sfx.play()


## Короткие синтетические звуки (моно 16 бит): beep — двойной гудок, hiss — шипение, thud — удар, hum — гул, rumble — грохот.
static func synth(kind: String) -> AudioStreamWAV:
	if _wav_cache.has(kind):
		return _wav_cache[kind]
	var dur := {"beep": 0.32, "hiss": 1.4, "thud": 0.45, "hum": 1.0, "rumble": 1.1}.get(kind, 0.3) as float
	var n := int(dur * SFX_RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var lp := 0.0
	for i in n:
		var t := float(i) / SFX_RATE
		var u := t / dur
		var v := 0.0
		match kind:
			"beep":
				var on := fmod(t, 0.16) < 0.11
				v = (0.35 if sin(TAU * 880.0 * t) > 0.0 else -0.35) * (1.0 if on else 0.0)
			"hiss":
				lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.35)
				v = lp * 0.5 * minf(u * 8.0, 1.0) * (1.0 - u)
			"thud":
				lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.08)
				v = (sin(TAU * 52.0 * t) * 0.8 + lp * 0.9) * exp(-t * 9.0)
			"hum":
				v = (fmod(t * 110.0, 1.0) - 0.5) * 0.3 * minf(u * 6.0, 1.0) * minf((1.0 - u) * 6.0, 1.0)
			"rumble":
				lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.04)
				v = lp * 1.6 * minf(u * 5.0, 1.0) * (1.0 - u)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SFX_RATE
	w.stereo = false
	w.data = data
	_wav_cache[kind] = w
	return w


# --- помощники ---

func camera_shake(metres: float) -> void:
	if not is_inside_tree():
		return
	var cam := get_tree().get_first_node_in_group("camera")
	if cam != null and cam.has_method("shake"):
		cam.call("shake", metres)


func match_node() -> Node:
	return get_tree().get_first_node_in_group("match") if is_inside_tree() else null


## Идёт ли бой (урон принимается). Без Match (пробы, песочницы) — да.
func combat_on() -> bool:
	var m := match_node()
	if m != null and m.has_method("combat_active"):
		return bool(m.call("combat_active"))
	return true


## Тела в форме shape с трансформом xf (без статики и выключенных): RigidBody3D, не замороженные. Запрос возвращает по строке
## на каждую форму, статика тоже в счёт (пол, кучи вала из десятков призм) — отсюда запас max_results.
func bodies_in(shape: Shape3D, xf: Transform3D, exclude: Array[RID] = [], max_results := 256) -> Array:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = xf
	q.collide_with_areas = false
	q.collide_with_bodies = true
	q.exclude = exclude
	var out: Array = []
	for r in get_world_3d().direct_space_state.intersect_shape(q, max_results):
		var b := r.get("collider") as RigidBody3D
		if b != null and not b.freeze and not out.has(b):
			out.append(b)
	return out


static func doll_of(b: Node) -> Doll:
	return b.get_parent() as Doll if b != null and is_instance_valid(b) else null


## Центр масс тела в мировых координатах.
static func com_of(b: RigidBody3D) -> Vector3:
	var st := PhysicsServer3D.body_get_direct_state(b.get_rid())
	return b.global_position + st.center_of_mass if st != null else b.global_position


## Кг железа в теле (0 — не железо). Порядок:
##   1) meta material тела ("iron" → вся масса тела, "wood"/"cloth" → 0, число → столько кг) — без кэша: её пишут builder арены
##      (пропсы, куски), желоб, лут и модульная кукла (итоговый материал детали — meta "material" каждого тела; сессия «Модульная
##      система куклы» делает материал осью, PartDef.material остаётся запасным значением);
##   2) иначе (кэш в метаданных тела): группа "iron"; крафтовое оружие — сумма масс деталей PartDef.material "iron" этого тела
##      (звено кистеня — своих); обычное оружие — WEAPON_IRON; часть ModularDoll — сумма масс железных деталей чертежа, слитых в
##      это тело (PartDef.material); кусок хлама — по имени (IRON_BITS).
static func iron_mass(b: RigidBody3D) -> float:
	if b == null or not is_instance_valid(b):
		return 0.0
	if b.has_meta(META_MATERIAL):
		var m: Variant = b.get_meta(META_MATERIAL)
		if m is float or m is int:
			return float(m)
		return b.mass if String(m) == "iron" else 0.0
	if b.has_meta(META_IRON_CACHE):
		return float(b.get_meta(META_IRON_CACHE))
	var v := _iron_mass_uncached(b)
	b.set_meta(META_IRON_CACHE, v)
	return v


static func _iron_mass_uncached(b: RigidBody3D) -> float:
	if b.is_in_group("iron"):
		return b.mass
	var owner_weapon: Variant = b.get("owner_weapon")
	var crafted: Node = owner_weapon if owner_weapon is Node else b
	var pinfo: Variant = crafted.get("parts_info") if crafted != null else null
	if pinfo is Dictionary and not (pinfo as Dictionary).is_empty():
		var s := 0.0
		for uid in pinfo:
			var e: Dictionary = pinfo[uid]
			var def := e.get("def") as PartDef
			if def != null and def.material == "iron" and e.get("body") == b:
				s += def.mass
		return s
	if b is Weapon:
		return b.mass * float(WEAPON_IRON.get((b as Weapon).weapon_id, 0.0))
	var d := b.get_parent()
	if d is Doll:
		var bp: Variant = d.get("blueprint")
		var ub: Variant = d.get("uid_body")
		if bp == null or not (ub is Dictionary):
			return 0.0
		var s2 := 0.0
		for n in (bp as BodyBlueprint).nodes:
			var uid := String(n.get("uid", ""))
			if String((ub as Dictionary).get(uid, "")) != String(b.name):
				continue
			var def2 := BodyBlueprint.part_def(String(n.get("part", "")))
			if def2 != null and def2.material == "iron":
				s2 += def2.mass
		return s2
	var nm := String(b.name)
	for k in IRON_BITS:
		if nm.begins_with(k) or nm.begins_with("Chute_" + k):
			return b.mass
	return 0.0


## Ширина тела по x (м) — по AABB его коллизий в мировых осях (кэш не нужен: 1–3 формы).
static func body_width(b: RigidBody3D) -> float:
	var x0 := INF
	var x1 := -INF
	for c in b.get_children():
		var cs := c as CollisionShape3D
		if cs == null or cs.shape == null or cs.disabled:
			continue
		var bx := cs.global_transform * _shape_aabb(cs.shape)
		x0 = minf(x0, bx.position.x)
		x1 = maxf(x1, bx.end.x)
	return x1 - x0 if x1 > x0 else 0.3


static func _shape_aabb(sh: Shape3D) -> AABB:
	if sh is BoxShape3D:
		var s := (sh as BoxShape3D).size
		return AABB(-s / 2.0, s)
	if sh is SphereShape3D:
		var r := (sh as SphereShape3D).radius
		return AABB(-Vector3.ONE * r, Vector3.ONE * r * 2.0)
	if sh is CylinderShape3D:
		var cy := sh as CylinderShape3D
		return AABB(Vector3(-cy.radius, -cy.height / 2.0, -cy.radius), Vector3(cy.radius * 2.0, cy.height, cy.radius * 2.0))
	if sh is CapsuleShape3D:
		var ca := sh as CapsuleShape3D
		return AABB(Vector3(-ca.radius, -ca.height / 2.0, -ca.radius), Vector3(ca.radius * 2.0, ca.height, ca.radius * 2.0))
	if sh is ConvexPolygonShape3D:
		var pts := (sh as ConvexPolygonShape3D).points
		if pts.size() > 0:
			var bx := AABB(pts[0], Vector3.ZERO)
			for q in pts:
				bx = bx.expand(q)
			return bx
	return AABB(Vector3(-0.15, -0.15, -0.15), Vector3(0.3, 0.3, 0.3))
