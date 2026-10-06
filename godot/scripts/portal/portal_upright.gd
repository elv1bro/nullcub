## Выход «как в Portal» (docs/plan-demo/PORTAL.md; автор 06.10: «чтобы как в Portal было примерно»): после переноса кукла сама встаёт
## головой вверх относительно местной гравитации — с полями NullField (гравитация тела из PhysicsDirectBodyState3D.total_gravity).
## Ребёнок куклы, ставит PortalPair после переноса (повторный перенос — заменяет). Не дольше Tuning.PORTAL_UPRIGHT_S каждый тик:
##   ошибка = угол от оси «вверх» торса до «верха» поля; нужная скорость поворота ω = ошибка / PORTAL_UPRIGHT_TAU (не больше
##   PORTAL_UPRIGHT_W_MAX); всем деталям — прибавка Δω к угловой скорости и Δω × (r − ЦМ) к линейной, Δω = ω − ω торса.
## Это поворот всей куклы вокруг её ЦМ: Σ m·(Δω × (r − ЦМ)) = 0 — скорость ЦМ не меняется (полёт из портала тот же), суставы не тянутся.
## Пропсы не доворачиваются (как в Portal). Кукла сломана / выбита / оторвана деталь торса — ничего не делает и уходит.
class_name PortalUpright
extends Node

const NODE_NAME := "PortalUpright"

var doll: Doll
var _left := 0.0


## Включить доворот у куклы d (заново, если уже идёт).
static func start(d: Doll) -> PortalUpright:
	var u := d.get_node_or_null(NODE_NAME) as PortalUpright
	if u == null:
		u = PortalUpright.new()
		u.name = NODE_NAME
		d.add_child(u)
	u.doll = d
	u._left = Tuning.PORTAL_UPRIGHT_S
	return u


## «Верх» в точке тела (мир, плоскость XY): против местной гравитации; гравитации нет — мировой верх.
static func up_at(b: RigidBody3D) -> Vector3:
	var st := PhysicsServer3D.body_get_direct_state(b.get_rid())
	var g := st.total_gravity if st != null else Vector3.ZERO
	g.z = 0.0
	if g.length() < 0.05:
		return Vector3.UP
	return -g.normalized()


## Угол (рад, со знаком: + против часовой) от оси «вверх» торса до «верха» поля.
static func tilt_of(d: Doll) -> float:
	var t := d.parts.get("Torso") as RigidBody3D
	if t == null:
		return 0.0
	var y := t.global_basis.y
	y.z = 0.0
	var up := up_at(t)
	return atan2(y.cross(up).z, y.dot(up))


func _physics_process(delta: float) -> void:
	if doll == null or not is_instance_valid(doll) or not doll.alive or doll.is_broken() or not doll.parts.has("Torso"):
		queue_free()
		return
	_left -= delta
	if _left <= 0.0:
		queue_free()
		return
	var t := doll.parts["Torso"] as RigidBody3D
	var err := tilt_of(doll)
	var w: float = clampf(err / Tuning.PORTAL_UPRIGHT_TAU, -Tuning.PORTAL_UPRIGHT_W_MAX, Tuning.PORTAL_UPRIGHT_W_MAX)
	var dw := w - t.angular_velocity.z
	var c := doll.centre_of_mass()
	for p in doll.parts.values():
		var b := p as RigidBody3D
		if b == null or not is_instance_valid(b):
			continue
		var r := doll.part_centre(b) - c
		r.z = 0.0
		b.angular_velocity += Vector3(0.0, 0.0, dw)
		b.linear_velocity += Vector3(-dw * r.y, dw * r.x, 0.0)
