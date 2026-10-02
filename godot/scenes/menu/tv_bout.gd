## Живой эфир на телевизоре гаража (scenes/menu/garage_menu.gd): отдельный 3D-мир внутри SubViewport телевизора
## (own_world_3d) — арена Void (scenes/arena/void.tscn, самая дешёвая по кадру), две куклы кита дерутся наскоками, камера
## трансляции держит обеих. Без Match, урона, звука и HUD: просто показательный спарринг, бесконечный (упали за край,
## разлетелись — возвращаются на точки спавна). Графику эфира (LIVE, счёт, бегущая строка) рисует garage_menu поверх.
## Боты — та же логика наскоков, что в tests/match_probe.gd (_rush): разбег → у соперника отход → снова разбег, с рывком
## с дистанции (ускорение за Заряд, Doll.request_dash) и вертикальной тягой к сопернику. Ведущий в углу кадра — N0 (scenes/n0/n0.tscn, N0Drone: модель v1 по листу
## автора, ART_NULL.md): парит, по очереди «говорит» и меняет выражение экрана с жестом.
class_name TvBout
extends Node3D

const ARENA := preload("res://scenes/arena/void.tscn")
const MODULAR_DOLL := preload("res://scenes/body/modular_doll.tscn")
const N0_SCENE := preload("res://scenes/n0/n0.tscn")
## N0 висит в углу кадра трансляции (ребёнок камеры): ведущий рядом с полем, в бою не участвует (§9 документа автора).
const N0_OFFSET := Vector3(1.0, 0.42, -2.6)
const N0_SCALE := 0.4
const N0_MOODS := ["excited", "happy", "shocked", "curious", "excited", "confused"]
const N0_BEAT_S := 2.6        # смена «говорит / молчит» и выражения
const FIGHTERS := ["kit_brawler", "kit_horned"]      # «Громила» против «Рогатого» (первый соперник местной лиги)
const RUSH_NEAR := 1.3
const RETREAT_S := 1.2
const DASH_FROM_M := 2.0
const RESET_FAR_M := 9.0

var arena: Node3D
var dolls: Array = []
var cam: Camera3D
var n0: N0Drone
var _beat := 0
var _retreat := {}
var _t := 0.0
var _cam_mid := Vector3.ZERO
var _cam_dist := 8.0


func _ready() -> void:
	arena = ARENA.instantiate() as Node3D
	add_child(arena)
	var spawns: Array = arena.call("spawn_points")
	for i in 2:
		var d := MODULAR_DOLL.instantiate() as ModularDoll
		d.name = "Fighter%d" % i
		d.blueprint = CraftEdit.load_body_preset(FIGHTERS[i])
		d.player_index = i
		d.external_input = true
		d.position = spawns[i]
		add_child(d)
		dolls.append(d)
	cam = Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true
	n0 = N0_SCENE.instantiate() as N0Drone
	n0.name = "N0"
	n0.position = N0_OFFSET
	n0.scale = Vector3.ONE * N0_SCALE
	cam.add_child(n0)
	var key := OmniLight3D.new()          # свой мягкий свет ведущему, чтобы читался на чёрном поле
	key.position = N0_OFFSET + Vector3(-0.4, 0.3, 0.6)
	key.omni_range = 1.6
	key.light_energy = 0.8
	cam.add_child(key)
	_cam_mid = (spawns[0] + spawns[1]) * 0.5 + Vector3(0, 1.4, 0)
	_place_cam(1.0)


func _physics_process(delta: float) -> void:
	_t += delta
	if dolls.size() < 2:
		return
	var a := dolls[0] as Doll
	var b := dolls[1] as Doll
	var ca := a.centre_of_mass()
	var cb := b.centre_of_mass()
	if ca.distance_to(cb) > RESET_FAR_M or ca.y < -2.0 or cb.y < -2.0:
		_reset()
		return
	_rush(a, ca, cb)
	_rush(b, cb, ca)


func _rush(d: Doll, dc: Vector3, oc: Vector3) -> void:
	var dx := oc.x - dc.x
	var dy := oc.y - dc.y
	var sgn := signf(dx) if absf(dx) > 0.05 else 1.0
	var vy := clampf(dy / 1.5, -1.0, 1.0) if absf(dy) > 0.8 else 0.0
	var until := float(_retreat.get(d, -1.0))
	if _t < until:
		d.input_vec = Vector2(-sgn, 0.25)
	elif absf(dx) < RUSH_NEAR and absf(dy) < 1.2:
		_retreat[d] = _t + RETREAT_S
		d.input_vec = Vector2(-sgn, 0.0)
	else:
		if absf(dx) > DASH_FROM_M and d.can_spend_charge():   # ускорение за Заряд (COMBAT_CHARGE.md): держится, пока просят
			d.request_dash()
		d.input_vec = Vector2(sgn, vy)


func _reset() -> void:
	var spawns: Array = arena.call("spawn_points")
	for i in dolls.size():
		var old := dolls[i] as ModularDoll
		var d := MODULAR_DOLL.instantiate() as ModularDoll
		d.name = old.name
		d.blueprint = old.blueprint
		d.player_index = i
		d.external_input = true
		d.position = spawns[i]
		remove_child(old)
		old.queue_free()
		add_child(d)
		dolls[i] = d
	_retreat.clear()


func _process(delta: float) -> void:
	_place_cam(1.0 - exp(-delta * 3.0))
	if n0 != null:     # парит (покачивание, уши и ножки — сам N0Drone); взгляд то на бой, то в камеру; реплики по тактам
		n0.rotation = Vector3(0.0, deg_to_rad(-24.0) + sin(_t * 0.45) * 0.3, 0.0)
		var beat := int(_t / N0_BEAT_S)
		if beat != _beat:
			_beat = beat
			n0.talking = beat % 2 == 0
			if beat % 2 == 1:
				n0.flash_expression(String(N0_MOODS[(beat / 2) % N0_MOODS.size()]), N0_BEAT_S * 0.9)


## Камера трансляции: середина между бойцами, отъезд по их разлёту.
func _place_cam(k: float) -> void:
	if dolls.size() < 2:
		return
	var ca := (dolls[0] as Doll).centre_of_mass()
	var cb := (dolls[1] as Doll).centre_of_mass()
	var mid := (ca + cb) * 0.5 + Vector3(0, 0.3, 0)
	var dist := clampf(absf(ca.x - cb.x) * 1.15 + absf(ca.y - cb.y) * 0.8 + 4.5, 5.5, 11.0)
	_cam_mid = _cam_mid.lerp(mid, k)
	_cam_dist = lerpf(_cam_dist, dist, k)
	cam.position = _cam_mid + Vector3(0, 0.7, _cam_dist)
	cam.look_at(_cam_mid, Vector3.UP)
