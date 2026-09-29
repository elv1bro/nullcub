## №078 Steam Vent (лист 04): патрубок в полу периодически бьёт столбом пара вверх. Дерево — scenes/props/scrap/machine_steam_vent.tscn:
## Body (StaticBody3D: патрубок на плоскости боя, по нему ходят), Model (glb), Steam (GPUParticles3D столба, в ACTIVE), Leak (струйки
## в WARNING), LampLight (фонарь на стояке), Sfx.
##
## Цикл (ScrapMachine): WARNING — фонарь мигает, гудок и струйки из решётки; ACTIVE — столб: сила вверх всем телам в столбе
## (x ± column_half_w, от верха патрубка на column_height); COOLDOWN — остаточный выдох RESIDUAL на RESIDUAL_S, фонарь гаснет.
## Сила — «сопротивление потоку»: F = парус · drag · max(0, steam_speed − v_y) · спад(y), спад линейно 1 → falloff_top к верху
## столба, парус = ширина тела по x (clamp SAIL_MIN…SAIL_MAX, м); ускорение ≤ accel_max + g. Масса в силу не входит — лёгкое
## улетает выше тяжёлого (g = 2, steam_speed 4, drag 30): ящик 10 кг — к верху столба (~6 м), бочка 15 кг — ~4–5 м,
## железная бочка 40 кг — не отрывается (72 Н < 80 Н веса), болт 0.3 кг вылетает из столба на ~4 м/с и взлетает выше всех.
## Кукла — целиком: F = doll_drag · max(0, steam_speed − v_y ЦМ) · спад(y ЦМ) · доля массы в столбе, по частям пропорционально
## массе (без закрутки): кукла 40 кг зависает у верха столба. Слабое центрирование к оси столба (center_k).
class_name SteamVentMachine
extends ScrapMachine

const SAIL_MIN := 0.25
const SAIL_MAX := 1.2
const RAMP_S := 0.15
const RESIDUAL := 0.3
const RESIDUAL_S := 0.35
const GRAVITY := 2.0

@export var base_y := 0.38             # верх патрубка (локально)
@export var column_height := 6.0
@export var column_half_w := 0.7
@export var steam_speed := 4.0         # м/с
@export var drag := 30.0               # Н·с/м на метр паруса
@export var doll_drag := 60.0          # Н·с/м на куклу
@export var accel_max := 25.0          # м/с² сверх g
@export var falloff_top := 0.2
@export var center_k := 2.0            # 1/с² к оси

var steam: GPUParticles3D
var leak: GPUParticles3D
## Последний тик: тело → сила (для проб).
var last_forces: Dictionary = {}
var _shape: BoxShape3D
var _exclude: Array[RID] = []
var _power := 0.0


func _machine_ready() -> void:
	steam = get_node_or_null("Steam") as GPUParticles3D
	leak = get_node_or_null("Leak") as GPUParticles3D
	_shape = BoxShape3D.new()
	_shape.size = Vector3(column_half_w * 2.0, column_height, 1.2)
	var body := get_node_or_null("Body") as CollisionObject3D
	if body != null:
		_exclude = [body.get_rid()]


func column_rect() -> Rect2:
	var o := global_position
	return Rect2(o.x - column_half_w, o.y + base_y, column_half_w * 2.0, column_height)


func _on_state(s: int, _prev: int) -> void:
	match s:
		State.WARNING:
			play_sfx("beep", 1.2)
		State.ACTIVE:
			play_sfx("hiss")
	if steam != null:
		steam.emitting = s == State.ACTIVE
	if leak != null:
		leak.emitting = s == State.WARNING


func _machine_tick(_delta: float) -> void:
	match state:
		State.ACTIVE:
			_power = minf(state_t / RAMP_S, 1.0)
		State.COOLDOWN:
			_power = RESIDUAL * maxf(1.0 - state_t / RESIDUAL_S, 0.0)
		_:
			_power = 0.0
	last_forces.clear()
	if _power <= 0.0 or not is_inside_tree():
		return
	var y0 := global_position.y + base_y
	var cx := global_position.x
	var xf := Transform3D(Basis.IDENTITY, Vector3(cx, y0 + column_height * 0.5, global_position.z))
	var per_doll: Dictionary = {}
	for b in bodies_in(_shape, xf, _exclude):
		var rb := b as RigidBody3D
		var dl := doll_of(rb)
		if dl != null:
			if not per_doll.has(dl):
				per_doll[dl] = []
			(per_doll[dl] as Array).append(rb)
			continue
		var c := com_of(rb)
		var fall := _falloff(c.y - y0)
		var sail := clampf(body_width(rb), SAIL_MIN, SAIL_MAX)
		var fy := sail * drag * maxf(steam_speed - rb.linear_velocity.y, 0.0) * fall * _power
		fy = minf(fy, rb.mass * (accel_max + GRAVITY))
		var fx := -rb.mass * center_k * (c.x - cx) * _power
		_push(rb, Vector3(fx, fy, 0.0))
	for dl in per_doll:
		_push_doll(dl as Doll, per_doll[dl], y0, cx)


func _falloff(h: float) -> float:
	var u := clampf(h / maxf(column_height, 0.1), 0.0, 1.0)
	return lerpf(1.0, falloff_top, u)


func _push_doll(d: Doll, inside: Array, y0: float, cx: float) -> void:
	if d.total_mass <= 0.0:
		return
	var m_in := 0.0
	for rb in inside:
		m_in += (rb as RigidBody3D).mass
	var com := d.centre_of_mass()
	var v := Vector3.ZERO
	for p in d.parts.values():
		v += (p as RigidBody3D).linear_velocity * (p as RigidBody3D).mass
	v /= d.total_mass
	var fy := doll_drag * maxf(steam_speed - v.y, 0.0) * _falloff(com.y - y0) * (m_in / d.total_mass) * _power
	fy = minf(fy, d.total_mass * (accel_max + GRAVITY))
	var fx := -d.total_mass * center_k * (com.x - cx) * _power * (m_in / d.total_mass)
	for rb in inside:
		var k := (rb as RigidBody3D).mass / m_in
		_push(rb, Vector3(fx, fy, 0.0) * k)


func _push(rb: RigidBody3D, f: Vector3) -> void:
	if rb.sleeping:
		rb.sleeping = false
	rb.apply_central_force(f)
	last_forces[rb] = f
