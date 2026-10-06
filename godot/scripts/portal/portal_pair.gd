## Пара порталов (docs/plan-demo/PORTAL.md; автор 06.10: «если мы добавим порталы, как было в Portal…» → механика свободна, вид свой).
## Сцена scenes/portal/portal_pair.tscn — корень + этот скрипт; проходы (Portal) пара строит сама в _ready по своим полям, так что
## сборщик карты пишет только поля (как у механизмов головоломок):
##   a_position / a_angle_deg — проход A (середина щели на поверхности, в системе пары; угол — поворот вокруг Z: 0° пол, 180° потолок,
##     −90° стена слева (нормаль вправо), 90° стена справа, любой — наклон); b_… — проход B; alt_enabled + alt_… — второй выход A
##     (B2), его выбирает switch_input («стрелочник»: ток — A↔B2, нет тока — A↔B);
##   input — ток пары (NodePath на что угодно с is_on(): плита, рычаг, логика); пусто — пара включена всегда;
##   width / depth (−1 — Tuning.PORTAL_WIDTH / PORTAL_DEPTH), colour_index (Tuning.PORTAL_COLOURS), label_a / _b / _alt — буквы;
##   pocket = false — карман у карты свой (портал не ставит дно и щёки).
## Поверхность карты в щели вырезает сборщик: проём шириной width по центру прохода (щёки кармана заходят в поверхность на PORTAL_JAMB).
##
## Перенос (каждый физический тик, пока пара под током; оба направления: A → выход и выход → A):
##   • кукла — когда её ЦМ ушёл за плоскость щели в пределах ширины (Portal.behind): ВСЕ детали разом (и связки — они тоже в parts),
##     положения из системы входа в систему выхода с разворотом (отображение T = выход · поворот 180° вокруг Z · вход⁻¹ — вошёл «в
##     стену» по −n входа, вышел по +n выхода), линейные и угловые скорости поворачиваются так же: модуль сохраняется. Суставы не
##     тянутся — кукла переносится как твёрдое целое. Что в руке (ArmAssist: приваренное и на пружине, WeaponPickup: оружие) едет
##     вместе с куклой; если тот же предмет держит и другая кукла (ящик «вдвоём») или это деталь чужой куклы — рука отпускает
##     (release("portal")), предмет остаётся;
##   • пропс (RigidBody3D, не часть живой куклы, не заморожен, не держится рукой — его везёт держащий) — по своему центру масс;
##     тело, которому нельзя вращаться (axis_lock_angular_z: тяжёлые ящики), переносит место и скорость, ориентацию — нет;
##   • выход: всё перенесённое целиком перед плоскостью выхода (ближайшая точка коллизий ≥ PORTAL_EXIT_AHEAD), место занято статикой —
##     ещё вперёд шагами PORTAL_UNSTICK_STEP; дальше тело (кукла — целиком) PORTAL_COOLDOWN_S не переносится ни одной парой (пинг-понг);
##   • вспышка на обоих проходах, звук (слои SfxDirector: whoosh на входе, sub на выходе), сигнал transferred, запись в history (пробы).
## Выключенная пара не переносит и гаснет (Portal.Lit.OFF); невыбранный выход «стрелочника» горит тускло (IDLE) и не переносит.
class_name PortalPair
extends PuzzlePart

signal transferred(what: Node3D, from: Portal, to: Portal)

@export var a_position := Vector3(-3.0, 0.0, 0.0)
@export var a_angle_deg := 0.0
@export var b_position := Vector3(3.0, 0.0, 0.0)
@export var b_angle_deg := 0.0
@export var alt_enabled := false
@export var alt_position := Vector3.ZERO
@export var alt_angle_deg := 0.0
@export var width := -1.0
@export var depth := -1.0
@export var colour_index := 0
@export var label_a := "A"
@export var label_b := "B"
@export var label_alt := "B2"
## Ток пары (путь к узлу с is_on()); пусто — включена всегда.
@export var input: NodePath
## Ток — выход A второй (B2); пусто или нет тока — B.
@export var switch_input: NodePath
@export var pocket := true
@export var sound := true

const HISTORY_MAX := 64
const QUIET_FRAMES := 12   # звук включения не играет на загрузке
const BOX_META := &"portal_local_box"

var a: Portal
var b: Portal
var alt: Portal
## Сколько переносов с последнего сброса и последние записи: {what, kind, from, to, frame, c_in, v_in, v_out, shift}.
var transfers := 0
var history: Array = []

static var _cool: Dictionary = {}       # instance id тела / куклы -> физкадр, до которого не переносить
static var _purge_at := 0
var _born_frame := 0


func _ready() -> void:
	_born_frame = Engine.get_physics_frames()
	var w := width if width > 0.0 else float(Tuning.PORTAL_WIDTH)
	var dp := depth if depth > 0.0 else float(Tuning.PORTAL_DEPTH)
	var col := pair_colour()
	a = _make("A", a_position, a_angle_deg, label_a, w, dp, col)
	b = _make("B", b_position, b_angle_deg, label_b, w, dp, col)
	if alt_enabled:
		alt = _make("B2", alt_position, alt_angle_deg, label_alt, w, dp, col)
	power_changed.connect(_on_power)
	reset_state()


func _make(n: String, pos: Vector3, angle_deg: float, letter: String, w: float, dp: float, col: Color) -> Portal:
	var p := get_node_or_null(n) as Portal
	if p != null:
		return p
	p = Portal.new()
	p.name = n
	p.width = w
	p.depth = dp
	p.colour = col
	p.label_text = letter
	p.pocket = pocket
	p.position = pos
	p.rotation = Vector3(0.0, 0.0, deg_to_rad(angle_deg))
	add_child(p)
	return p


func pair_colour() -> Color:
	var list: Array = Tuning.PORTAL_COLOURS
	return list[posmod(colour_index, list.size())]


## Проходы пары: [A, B] или [A, B, B2].
func portals() -> Array:
	var out: Array = [a, b]
	if alt != null:
		out.append(alt)
	return out


## Пара под током (вход пуст — всегда).
func is_powered() -> bool:
	return input == NodePath() or power_of(input)


## Куда ведёт A сейчас: B2, если есть и на switch_input ток, иначе B.
func exit_of_a() -> Portal:
	if alt != null and switch_input != NodePath() and power_of(switch_input):
		return alt
	return b


func reset_state() -> void:
	transfers = 0
	history.clear()
	super.reset_state()


func _on_power(on: bool) -> void:
	if not sound or Engine.get_physics_frames() - _born_frame < QUIET_FRAMES:
		return
	_sfx_at(a, "sub" if on else "creak", -8.0 if on else -10.0, 1.4 if on else 0.8)


func _physics_process(_delta: float) -> void:
	if a == null or b == null:
		return
	var powered := is_powered()
	_set_on(powered)
	var ex := exit_of_a()
	for p in portals():
		var pp := p as Portal
		var lk := Portal.Lit.OFF
		if powered:
			lk = Portal.Lit.ACTIVE if (pp == a or pp == ex) else Portal.Lit.IDLE
		pp.set_lit(lk)
	var frame := Engine.get_physics_frames()
	if frame >= _purge_at:
		_purge_at = frame + 600
		for k in _cool.keys():
			if int(_cool[k]) <= frame:
				_cool.erase(k)
	if not powered:
		return
	_scan(a, ex, frame)
	_scan(ex, a, frame)


## Кандидаты в датчике входа from: куклы — по ЦМ (вся кукла раз), пропсы — по центру масс.
func _scan(from: Portal, to: Portal, frame: int) -> void:
	var seen := {}
	for n in from.bodies():
		var rb := n as RigidBody3D
		if rb == null or not is_instance_valid(rb) or rb.is_queued_for_deletion() or rb.freeze:
			continue
		if rb.axis_lock_linear_x and rb.axis_lock_linear_y:
			continue   # на оси (рукоять рычага) — не переносится
		var d := doll_owner(rb)
		var key := d.get_instance_id() if d != null else rb.get_instance_id()
		if seen.has(key):
			continue
		seen[key] = true
		if cooling(key, frame):
			continue
		if d != null:
			if from.behind(d.centre_of_mass()):
				transfer_doll(d, from, to)
		elif not is_held(rb) and from.behind(body_centre(rb)):
			transfer_body(rb, from, to)


## Кукла, чья живая деталь — это тело (не оторванная и не после break_apart), или null.
static func doll_owner(rb: RigidBody3D) -> Doll:
	var d := PuzzlePart.doll_of(rb)
	if d == null or d.is_broken():
		return null
	if d.parts.get(rb.name) != rb:
		return null
	return d


## Предмет в руке (ArmAssist) или оружие в кисти — его переносит держащий, а не портал сам.
static func is_held(rb: RigidBody3D) -> bool:
	if ArmAssist.holder_of(rb) != null:
		return true
	var w := rb as Weapon
	return w != null and w.is_held()


## Центр масс тела (мир).
static func body_centre(rb: RigidBody3D) -> Vector3:
	var st := PhysicsServer3D.body_get_direct_state(rb.get_rid())
	if st == null:
		return rb.global_position
	return rb.global_transform * st.center_of_mass_local


static func cooling(key: int, frame: int) -> bool:
	return int(_cool.get(key, -1)) > frame


static func _cool_until() -> int:
	return Engine.get_physics_frames() + int(ceil(Tuning.PORTAL_COOLDOWN_S * Engine.physics_ticks_per_second))


## Отображение «вход → выход»: точка в системе входа (x вдоль щели, y от плоскости) → в системе выхода, повёрнутая на 180° вокруг Z
## (глубина за входом → высота перед выходом; вдоль щели — зеркально, это поворот, не отражение: кукла остаётся лицом к камере).
static func mapping(from: Node3D, to: Node3D) -> Transform3D:
	return to.global_transform * Transform3D(Basis(Vector3(0, 0, 1), PI), Vector3.ZERO) * from.global_transform.affine_inverse()


## Перенести куклу целиком (и что у неё в руках). Публично — для проб и режимов, которым нужно «втолкнуть» куклу без касания.
func transfer_doll(d: Doll, from: Portal, to: Portal) -> void:
	var list: Array[RigidBody3D] = []
	for p in d.parts.values():
		var rb := p as RigidBody3D
		if rb != null and is_instance_valid(rb) and not list.has(rb):
			list.append(rb)
	for c in d.get_children():
		if c is ArmAssist:
			var arm := c as ArmAssist
			if arm.is_holding() and not list.has(arm.held):
				if _can_carry(arm.held, d, arm):
					list.append(arm.held)
				else:
					arm.release("portal")
		elif c is WeaponPickup:
			var wp := c as WeaponPickup
			for hn in wp.held:
				var w := (wp.held[hn] as Dictionary).get("weapon") as RigidBody3D
				if w != null and is_instance_valid(w) and not list.has(w):
					list.append(w)
	var c_in := d.centre_of_mass()
	var v_in := d.com_velocity()
	var shift := _move(list, from, to)
	var until := _cool_until()
	_cool[d.get_instance_id()] = until
	for rb in list:
		_cool[rb.get_instance_id()] = until
	_after(d, "doll", from, to, c_in, v_in, d.com_velocity(), shift, list.size() - d.parts.size())


## Перенести одно тело (пропс).
func transfer_body(rb: RigidBody3D, from: Portal, to: Portal) -> void:
	var c_in := body_centre(rb)
	var v_in := rb.linear_velocity
	var one: Array[RigidBody3D] = [rb]
	var shift := _move(one, from, to)
	_cool[rb.get_instance_id()] = _cool_until()
	_after(rb, "body", from, to, c_in, v_in, rb.linear_velocity, shift, 0)


## Можно ли везти предмет в руке куклы d через портал: не деталь чужой куклы и не держится рукой другой куклы.
func _can_carry(h: RigidBody3D, d: Doll, own: ArmAssist) -> bool:
	var od := PuzzlePart.doll_of(h)
	if od != null and od != d:
		return false
	if not is_inside_tree():
		return true
	for n in get_tree().get_nodes_in_group("dolls"):
		var other := n as Doll
		if other == null or other == d or not is_instance_valid(other):
			continue
		for c in other.get_children():
			if c is ArmAssist and c != own and (c as ArmAssist).held == h:
				return false
	return true


## Поставить тела list на выход: отображение входа в выход, сдвиг вперёд (целиком перед щелью, не в стене), скорости повёрнуты.
## Возвращает сдвиг вдоль нормали выхода сверх отображения.
func _move(list: Array[RigidBody3D], from: Portal, to: Portal) -> Vector3:
	var xf := mapping(from, to)
	var n := to.normal()
	n.z = 0.0
	n = n.normalized()
	var o := to.global_position
	var targets: Array[Transform3D] = []
	var lo := INF
	for rb in list:
		var t := xf * rb.global_transform
		if rb.axis_lock_angular_z:
			t.basis = rb.global_transform.basis   # не вращается — ориентация прежняя
		t.origin.z = rb.global_position.z
		targets.append(t)
		lo = minf(lo, _lowest(rb, t, n, o))
	var shift := n * maxf(0.0, float(Tuning.PORTAL_EXIT_AHEAD) - lo)
	var excl: Array[RID] = []
	for rb in list:
		excl.append(rb.get_rid())
	for i in int(Tuning.PORTAL_UNSTICK_TRIES):
		if not _blocked(list, targets, shift, excl):
			break
		shift += n * float(Tuning.PORTAL_UNSTICK_STEP)
	var rot := xf.basis
	for i in list.size():
		var rb := list[i]
		var t := targets[i]
		t.origin += shift
		var lv := rot * rb.linear_velocity
		var av := rot * rb.angular_velocity
		lv.z = 0.0
		rb.global_transform = t
		rb.linear_velocity = lv
		rb.angular_velocity = av
		rb.reset_physics_interpolation()
		if DollCombat.prev_vel.has(rb):
			DollCombat.prev_vel[rb] = [lv, av]   # скорость «до шага» для детектора ударов — уже новая
	return shift


## Ближайшая к плоскости выхода точка коллизий тела в положении t (знаковое расстояние вдоль n от o).
static func _lowest(rb: RigidBody3D, t: Transform3D, n: Vector3, o: Vector3) -> float:
	var box := local_box(rb)
	var lo := INF
	for i in 8:
		lo = minf(lo, (t * box.get_endpoint(i) - o).dot(n))
	return lo


## Формы тел в положениях targets + shift пересекают статику (стены, пол, двери, замороженное)?
func _blocked(list: Array[RigidBody3D], targets: Array[Transform3D], shift: Vector3, excl: Array[RID]) -> bool:
	if not is_inside_tree():
		return false
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	q.exclude = excl
	q.collide_with_areas = false
	q.collide_with_bodies = true
	for i in list.size():
		var rb := list[i]
		var t := targets[i]
		t.origin += shift
		var inv := rb.global_transform.affine_inverse()
		for cs in _shapes(rb):
			q.shape = cs.shape
			q.transform = t * (inv * cs.global_transform)
			for hit in space.intersect_shape(q, 4):
				var col: Object = hit.get("collider")
				if col is StaticBody3D or col is AnimatableBody3D or (col is RigidBody3D and (col as RigidBody3D).freeze):
					return true
	return false


## Формы коллизий самого тела (не вложенных тел).
static func _shapes(rb: RigidBody3D) -> Array:
	var out: Array = []
	for c in rb.find_children("*", "CollisionShape3D", true, false):
		var cs := c as CollisionShape3D
		if cs.shape == null or cs.disabled:
			continue
		var p := cs.get_parent()
		while p != null and p != rb and not (p is CollisionObject3D):
			p = p.get_parent()
		if p == rb:
			out.append(cs)
	return out


## Объединённый AABB коллизий тела в его локальных координатах (кэш — meta тела: формы тел не меняются).
static func local_box(rb: RigidBody3D) -> AABB:
	if rb.has_meta(BOX_META):
		return rb.get_meta(BOX_META)
	var box := AABB()
	var first := true
	var inv := rb.global_transform.affine_inverse()
	for cs in _shapes(rb):
		var sb := _shape_box((cs as CollisionShape3D).shape)
		var tb := (inv * (cs as CollisionShape3D).global_transform) * sb
		box = tb if first else box.merge(tb)
		first = false
	if first:
		box = AABB(Vector3(-0.1, -0.1, -0.1), Vector3(0.2, 0.2, 0.2))
	rb.set_meta(BOX_META, box)
	return box


static func _shape_box(sh: Shape3D) -> AABB:
	if sh is BoxShape3D:
		var s := (sh as BoxShape3D).size
		return AABB(-s * 0.5, s)
	if sh is SphereShape3D:
		var r := (sh as SphereShape3D).radius
		return AABB(-Vector3.ONE * r, Vector3.ONE * r * 2.0)
	if sh is CapsuleShape3D:
		var ca := sh as CapsuleShape3D
		return AABB(Vector3(-ca.radius, -ca.height * 0.5, -ca.radius), Vector3(ca.radius * 2.0, ca.height, ca.radius * 2.0))
	if sh is CylinderShape3D:
		var cy := sh as CylinderShape3D
		return AABB(Vector3(-cy.radius, -cy.height * 0.5, -cy.radius), Vector3(cy.radius * 2.0, cy.height, cy.radius * 2.0))
	var m := sh.get_debug_mesh()
	return m.get_aabb() if m != null else AABB(Vector3(-0.1, -0.1, -0.1), Vector3(0.2, 0.2, 0.2))


func _after(what: Node3D, kind: String, from: Portal, to: Portal, c_in: Vector3, v_in: Vector3, v_out: Vector3, shift: Vector3, carried: int) -> void:
	transfers += 1
	history.append({"what": what, "kind": kind, "from": String(from.name), "to": String(to.name), "frame": Engine.get_physics_frames(),
		"c_in": c_in, "v_in": v_in, "v_out": v_out, "shift": shift.length(), "carried": carried})
	if history.size() > HISTORY_MAX:
		history.pop_front()
	from.flash()
	to.flash()
	if sound:
		_sfx_at(from, "whoosh", -5.0, 1.35)
		_sfx_at(to, "sub", -12.0, 1.8)
	transferred.emit(what, from, to)


func _sfx_at(p: Node3D, layer: String, db: float, pitch: float) -> void:
	if not is_inside_tree():
		return
	var s := get_tree().get_first_node_in_group(SfxDirector.GROUP) as SfxDirector
	if s != null:
		s.play_layer(layer, db, pitch, SfxDirector.BUS_SFX, s.pan_for(p.global_position))
