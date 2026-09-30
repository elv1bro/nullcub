## Вес пропсов (29.09, «тяжёлое двигается без проблем»): классы веса по массе тела и то, как они ведут себя в мире.
##
## Почему так. g = 2 (Tuning.GRAVITY, решение 28.09 — кукла парит), трение ∝ m·g, а тяга куклы 12 Н/кг × 40 кг = 480 Н: ящику 80 кг
## (μ 0.8) трения ≈ 128 Н, вагону 140 кг ≈ 154 Н — кукла толкала всё что угодно в 3–4 раза сильнее, чем держит пол. Гравитацию мира
## не трогаем (полёт куклы), а пропсам даём «свой вес»:
##   LIGHT  ≤ LIGHT_MAX_KG   — как было (g = 2): летают, в руке сидят жёстко (ArmAssist приваривает), бросаются далеко;
##   MEDIUM ≤ HEAVY_MIN_KG   — gravity_scale MEDIUM_G_SCALE (g ≈ 5): трение и вес в 2.5 раза больше — толкаются с трудом, рукой
##                             тащатся по полу, но не поднимаются (вес > ArmAssist.HOLD_F_MAX);
##   HEAVY  > HEAVY_MIN_KG   — g как на Земле (HEAVY_G_SCALE) и «якорь»: остановился на SETTLE_S — тело замораживается (FREEZE_MODE_STATIC)
##                             и для кукол становится стеной: не сдвинуть ни тягой, ни тараном, ни рукой (ArmAssist не хватает
##                             замороженные тела, подсказка «слишком тяжело»). Сдвинуть может только взрыв (PropHeft.kick —
##                             размораживает и толкает; успокоился — снова якорь). Опора пропала (под якорем разбили ящик, скрипт
##                             перенёс тело) — лучи вниз из нижних углов каждые SUPPORT_CHECK_S ничего не нашли — якорь снимается, тело падает.
## Класс можно задать явно: meta "heft" = Heft.* на теле.
## Подключение: PropHeft.equip(body) для каждого свободного пропса арены (ScrapArena._ready → loose_bodies()).
class_name PropHeft
extends Node

enum Heft { LIGHT, MEDIUM, HEAVY }

const META := &"heft"
const LIGHT_MAX_KG := 15.0
const HEAVY_MIN_KG := 50.0
const MEDIUM_G_SCALE := 2.5        # g ≈ 5 м/с²: бочка 40 кг весит 200 Н > хвата 150 Н — только тащить
const HEAVY_G_SCALE := 4.9         # g ≈ 9.8 м/с²
const SETTLE_SPEED := 0.12         # м/с: «стоит»
const SETTLE_SPIN := 0.2           # рад/с
const SETTLE_S := 0.35             # столько подряд стоит — якорь
const KICK_AWAKE_S := 0.5          # после взрыва не якорится хотя бы столько
const SUPPORT_CHECK_S := 0.2
const SUPPORT_RAY_M := 0.12        # опора ищется так глубоко под низом коллизии

var body: RigidBody3D
var _time := 0.0
var _rest_t := 0.0
var _awake_until := 0.0
var _support_t := 0.0
var _bottom := AABB()               # локальные границы коллизий (низ и ширина для лучей опоры)


## Класс веса тела (meta "heft" важнее массы).
static func heft_of(b: Node) -> int:
	if b == null:
		return Heft.LIGHT
	if b.has_meta(META):
		return int(b.get_meta(META))
	var rb := b as RigidBody3D
	if rb == null:
		return Heft.LIGHT
	if rb.mass > HEAVY_MIN_KG:
		return Heft.HEAVY
	if rb.mass > LIGHT_MAX_KG:
		return Heft.MEDIUM
	return Heft.LIGHT


static func is_heavy(b: Node) -> bool:
	return heft_of(b) == Heft.HEAVY


## Надпись класса для подсказок.
static func title(h: int) -> String:
	match h:
		Heft.HEAVY:
			return "слишком тяжело"
		Heft.MEDIUM:
			return "тяжёлое — тащить"
	return "лёгкое"


## Выдать телу вес по классу; HEAVY — ещё и якорь (узел-ребёнок PropHeft). Повторный вызов ничего не дублирует.
static func equip(b: RigidBody3D) -> void:
	if b == null or not is_instance_valid(b) or b is Weapon or b.get_parent() is Doll:
		return
	var h := heft_of(b)
	match h:
		Heft.MEDIUM:
			b.gravity_scale = MEDIUM_G_SCALE
		Heft.HEAVY:
			b.gravity_scale = HEAVY_G_SCALE
			if anchor_of(b) == null:
				var n := PropHeft.new()
				n.name = "PropHeft"
				b.add_child(n)


static func anchor_of(b: Node) -> PropHeft:
	if b == null:
		return null
	for c in b.get_children():
		if c is PropHeft:
			return c
	return null


## Толчок извне (взрыв): якорь снимается, импульс прикладывается; тело снова заякорится, когда успокоится.
static func kick(b: RigidBody3D, impulse: Vector3) -> void:
	if b == null or not is_instance_valid(b):
		return
	var a := anchor_of(b)
	if a != null:
		a.wake()
	elif b.freeze:
		return   # чужая заморозка (обломки Breakable, скрипты) — не наша
	b.apply_central_impulse(impulse)


func _ready() -> void:
	body = get_parent() as RigidBody3D
	if body == null:
		queue_free()
		return
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	var first := true
	for c in body.get_children():
		var cs := c as CollisionShape3D
		if cs == null or cs.shape == null or cs.shape.get_debug_mesh() == null:
			continue
		var box := cs.transform * cs.shape.get_debug_mesh().get_aabb()
		_bottom = box if first else _bottom.merge(box)
		first = false


func wake() -> void:
	_awake_until = _time + KICK_AWAKE_S
	_rest_t = 0.0
	if body != null and body.freeze:
		body.freeze = false


## Есть ли под телом опора: луч вниз из левого, центрального и правого нижних углов коллизий (любой попал — есть).
func has_support() -> bool:
	if body == null or not body.is_inside_tree() or _bottom.size == Vector3.ZERO:
		return true
	var space := body.get_world_3d().direct_space_state
	var y := _bottom.position.y
	for fx in [0.1, 0.5, 0.9]:
		var lx: float = _bottom.position.x + _bottom.size.x * fx
		var from := body.to_global(Vector3(lx, y + 0.05, 0.0))
		var to := body.to_global(Vector3(lx, y - SUPPORT_RAY_M, 0.0))
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = [body.get_rid()]
		if not space.intersect_ray(q).is_empty():
			return true
	return false


func anchored() -> bool:
	return body != null and body.freeze


func _physics_process(delta: float) -> void:
	_time += delta
	if body == null:
		return
	if body.freeze:
		_support_t += delta
		if _support_t >= SUPPORT_CHECK_S:
			_support_t = 0.0
			if not has_support():
				wake()
		return
	if _time < _awake_until:
		return
	if body.linear_velocity.length() < SETTLE_SPEED and absf(body.angular_velocity.z) < SETTLE_SPIN:
		_rest_t += delta
		if _rest_t >= SETTLE_S:
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
			body.freeze = true
	else:
		_rest_t = 0.0
