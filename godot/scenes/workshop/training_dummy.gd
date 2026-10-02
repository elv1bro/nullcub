## Манекен для битья в «проверке в деле» мастерской: обычная кукла (scenes/doll/doll_dark.tscn, орех) с external_input, висит на
## верёвке с потолочной балки. «Верёвка» — мягкая пружина к точке дома (торс) + момент «стоять прямо»: удар отправляет манекен
## в полёт как обычно (Doll.apply_knockback, окно knockback_until — пружина молчит), потом он сам возвращается и выпрямляется.
## Верёвка рисуется цилиндром от крюка до макушки. HP видно (сигналы hit / hp для UI), на KO кукла рассыпается (Doll.break_apart),
## через RESPAWN_S — новый манекен с полным HP. Урон считает DollCombat (ребёнок манекена), Match не нужен. Запас HP — Doll.max_hp
## куклы-манекена (max_hp(); у Doll без этого поля — Tuning.MAX_HP).
extends Node3D

signal hit(amount: float, position: Vector3, part: String, kind: String)
signal hp_changed(hp: float, max_hp: float)
signal knocked_out()
signal respawned(doll: Doll)

const DUMMY_SCENE := "res://scenes/doll/doll_dark.tscn"
static var _scene: PackedScene
const RESPAWN_S := 2.0
## Пружина к дому: 40 кг, ω ≈ √(140/40) ≈ 1.9 рад/с — возвращается за ~1.5 с без перелёта (ζ ≈ 0.8).
const HOME_K := 140.0              # Н/м
const HOME_C := 120.0              # Н·с/м
const HOME_F_MAX := 260.0          # Н (вес манекена 80 Н при g = 2 + запас)
const UPRIGHT_K := 160.0           # Н·м/рад
const UPRIGHT_C := 30.0            # Н·м·с/рад
const UPRIGHT_T_MAX := 120.0       # Н·м
const ROPE_UP := 3.4               # м: крюк над точкой дома торса
const ROPE_RADIUS := 0.018

var doll: Doll
var home := Vector3.ZERO           # точка дома торса (мир)
var total_damage := 0.0
var hits := 0
var last_hit: Dictionary = {}
var kos := 0
var _respawn_at := -1.0
var _max_hp: float = Tuning.MAX_HP   # Doll.max_hp текущего манекена (запоминается при спавне: после KO кукла уже может быть освобождена)
var _time := 0.0
var _rope: MeshInstance3D


func _ready() -> void:
	_rope = MeshInstance3D.new()
	_rope.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # натягивается в _process
	var cyl := CylinderMesh.new()
	cyl.top_radius = ROPE_RADIUS
	cyl.bottom_radius = ROPE_RADIUS
	cyl.height = 1.0
	cyl.radial_segments = 8
	_rope.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.43, 0.28)
	mat.roughness = 0.95
	_rope.material_override = mat
	_rope.name = "Rope"
	add_child(_rope)
	spawn()


## Новый манекен в позиции узла (global_position = место, где стоит).
func spawn() -> void:
	if doll != null and is_instance_valid(doll):
		doll.queue_free()
	if _scene == null:
		_scene = load(DUMMY_SCENE) as PackedScene   # держим: слабый кэш ресурсов иначе перечитывает сцену при каждом испытании
	doll = _scene.instantiate() as Doll
	doll.name = "Dummy"
	doll.external_input = true
	doll.player_index = 1
	doll.input_prefix = "p2"
	add_child(doll)
	doll.global_position = global_position
	var combat := DollCombat.new()
	combat.name = "DollCombat"
	doll.add_child(combat)
	doll.damaged.connect(_on_damaged)
	doll.knocked_out.connect(_on_ko)
	home = doll.torso().global_position
	_respawn_at = -1.0
	var mh: Variant = doll.get("max_hp")
	_max_hp = float(mh) if mh != null and float(mh) > 0.0 else Tuning.MAX_HP
	hp_changed.emit(doll.hp, _max_hp)
	respawned.emit(doll)


func alive() -> bool:
	return doll != null and is_instance_valid(doll) and doll.alive


func _on_damaged(amount: float, _attacker: Node, part: String, position: Vector3, kind: String) -> void:
	total_damage += amount
	hits += 1
	last_hit = {"amount": amount, "part": part, "kind": kind, "position": position, "t": _time}
	hit.emit(amount, position, part, kind)
	hp_changed.emit(doll.hp, _max_hp)


func _on_ko(_attacker: Node, _record: Dictionary) -> void:
	kos += 1
	_respawn_at = _time + RESPAWN_S
	hp_changed.emit(0.0, _max_hp)
	knocked_out.emit()


func _physics_process(delta: float) -> void:
	_time += delta
	if _respawn_at >= 0.0 and _time >= _respawn_at:
		spawn()
		return
	if not alive():
		return
	var t := doll.torso()
	var flying := doll.knockback_until > float(doll.get("_time"))
	if not flying:
		var f := (home - t.global_position) * HOME_K - t.linear_velocity * HOME_C
		f.z = 0.0
		t.apply_central_force(f.limit_length(HOME_F_MAX))
		var ang := wrapf(t.global_rotation.z, -PI, PI)
		var tq := clampf(-UPRIGHT_K * ang - UPRIGHT_C * t.angular_velocity.z, -UPRIGHT_T_MAX, UPRIGHT_T_MAX)
		t.apply_torque(Vector3(0, 0, tq))


func _process(_delta: float) -> void:
	if not alive():
		_rope.visible = false
		return
	var top := doll.head().global_transform * Vector3(0, 0.14, 0)
	var hook := home + Vector3(0, ROPE_UP, 0)
	var d := top - hook
	var len := d.length()
	_rope.visible = len > 0.05
	if not _rope.visible:
		return
	var y := d / len
	var x := y.cross(Vector3.BACK).normalized() if absf(y.z) < 0.99 else Vector3.RIGHT
	var z := x.cross(y)
	_rope.global_transform = Transform3D(Basis(x, y * len, z), (hook + top) * 0.5)


## Верхняя точка манекена (для HP-таблички в UI).
func head_top() -> Vector3:
	if alive():
		return doll.head().global_transform * Vector3(0, 0.3, 0)
	return home + Vector3(0, 1.0, 0)


func hp() -> float:
	return doll.hp if alive() else 0.0


## Полный запас HP манекена (Doll.max_hp; для HP-таблички в UI).
func max_hp() -> float:
	return _max_hp
