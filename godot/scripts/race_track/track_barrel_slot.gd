## Взрывная бочка ямы «Гонки: трасса» (docs/plan-demo/RACE_TRACK.md, участок 6): ставит железную бочку Свалки (ExplosiveBarrel,
## prop_metal_barrel.tscn) на столб. Кукла ближе Tuning.TRACK_BARREL_FUSE_M — поджиг, взрыв через TRACK_BARREL_FUSE_S (Explosion: урон,
## отброс — в яму); взрыв рвёт мосты ближе BRIDGE_BLAST_M. Бочки нет (взорвалась, упала в яму) — новая через TRACK_BARREL_RESPAWN_S.
## Узел стоит там, где у бочки дно.
class_name TrackBarrelSlot
extends Node3D

const SCENE := "res://scenes/props/scrap/prop_metal_barrel.tscn"
const BRIDGE_BLAST_M := 3.6
const LOST_DROP_M := 3.0

var barrel: ExplosiveBarrel
## Для проб: поджогов и взрывов за жизнь.
var ignitions := 0
var explosions := 0
var _left := -1.0


func _ready() -> void:
	_spawn()


func _spawn() -> void:
	var ps := load(SCENE) as PackedScene
	if ps == null:
		return
	barrel = ps.instantiate() as ExplosiveBarrel
	barrel.name = "Barrel"
	add_child(barrel)
	barrel.position = Vector3(0.0, 0.02, 0.0)
	barrel.destroyed.connect(_on_destroyed.bind(barrel))
	_left = -1.0


func alive() -> bool:
	return barrel != null and is_instance_valid(barrel) and barrel.state != Breakable.State.DESTROYED


func _on_destroyed(b: ExplosiveBarrel) -> void:
	explosions += 1
	var at := b.global_position if is_instance_valid(b) else global_position
	var arena := get_tree().get_first_node_in_group("arena")
	if arena != null and arena.has_method("bridges"):
		for s in arena.call("bridges"):
			var br := s as TrackBridgeSlot
			var r := br.touch_rect()
			var c := Vector2(clampf(at.x, r.position.x, r.end.x), clampf(at.y, r.position.y, r.end.y))
			if c.distance_to(Vector2(at.x, at.y)) <= BRIDGE_BLAST_M:
				br.break_now()
	if _left < 0.0:
		_left = Tuning.TRACK_BARREL_RESPAWN_S


func _physics_process(delta: float) -> void:
	if not alive():
		if _left < 0.0:
			_left = Tuning.TRACK_BARREL_RESPAWN_S
		_left -= delta
		if _left <= 0.0:
			if barrel != null and is_instance_valid(barrel):
				barrel.queue_free()
			_spawn()
		return
	if barrel.global_position.y < global_position.y - LOST_DROP_M:
		barrel.queue_free()   # упала в яму — не взрывается внизу, новая встанет на столб
		barrel = null
		return
	if barrel.lit:
		return
	var at := barrel.global_position
	var r2 := Tuning.TRACK_BARREL_FUSE_M * Tuning.TRACK_BARREL_FUSE_M
	for d in get_tree().get_nodes_in_group("dolls"):
		var doll := d as Doll
		if doll == null or not doll.alive or not doll.is_inside_tree():
			continue
		if doll.centre_of_mass().distance_squared_to(at) <= r2:
			barrel.ignite(Tuning.TRACK_BARREL_FUSE_S, doll)
			ignitions += 1
			return
