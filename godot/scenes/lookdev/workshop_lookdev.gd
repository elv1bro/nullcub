## Look-dev «Мастерская» (docs/refs/R22-a-hero-workshop-fight.jpg, ART_DIRECTION.md v3 §5): пропсы, свет, туман и
## две куклы. Дерево (окружение, солнце, камера, пропсы, пыль) живёт в workshop_lookdev.tscn; здесь только поведение:
##   - куклы грузятся через load() с проверкой на null (doll.tscn может пересобираться другим агентом — сцена не падает);
##     первая — клён (doll.tscn), вторая — орех (doll_dark.tscn, как на R22), если тёмная сцена есть;
##   - стекло окон (MeshInstance3D «Glass») и декали не отбрасывают тень, иначе перекрывают лучи в объёмном тумане;
##   - меши кукол → gi_mode DYNAMIC (иначе SDFGI «запекает» двигающиеся тела);
##   - вторая кукла получает толчок push_vec в окне [PUSH_START, PUSH_END] с (внешний ввод), конечности отстают;
##   - тест VFX: на частях толкаемой куклы включён contact_monitor; body_entered при скорости > IMPACT_SPEED м/с
##     → ImpactFx.spawn_impact в точке контакта (позиция/нормаль из PhysicsDirectBodyState3D).
class_name WorkshopLookdev
extends Node3D

const DOLL_SCENE_PATH := "res://scenes/doll/doll.tscn"
const DOLL_DARK_SCENE_PATH := "res://scenes/doll/doll_dark.tscn"   # R22: чётные куклы (P2) — тёмный орех, если сцена есть
const IMPACT_SPEED := 4.0
const FX_COOLDOWN_S := 0.25
const PUSH_START := 0.9
const PUSH_END := 1.45

@export var spawn_dolls := true
@export var push_vec := Vector2(-1.0, 0.5)
@export var doll_positions: Array[Vector3] = [Vector3(-1.3, 0.0, 0.0), Vector3(1.8, 0.0, 0.0)]

var dolls: Array[Node3D] = []
var contact_impacts := 0
var fx_spawned := 0
var time := 0.0
var _prev_speed: Dictionary = {}   # RigidBody3D → скорость до шага физики (body_entered приходит после отклика, когда скорость уже погашена)

@onready var sun: DirectionalLight3D = $Sun
@onready var cam: Camera3D = $Camera
@onready var env: WorldEnvironment = $Env


func _ready() -> void:
	_fix_shadows(self)
	if spawn_dolls:
		_spawn_dolls()


func _spawn_dolls() -> void:
	var ps := load(DOLL_SCENE_PATH) as PackedScene
	if ps == null:
		push_warning("WorkshopLookdev: %s не загрузилась (кукла пересобирается?) — сцена без кукол" % DOLL_SCENE_PATH)
		return
	var ps_dark: PackedScene = null
	if ResourceLoader.exists(DOLL_DARK_SCENE_PATH):
		ps_dark = load(DOLL_DARK_SCENE_PATH) as PackedScene
	for i in doll_positions.size():
		var d := (ps_dark if (i % 2 == 1 and ps_dark != null) else ps).instantiate() as Node3D
		if d == null:
			push_warning("WorkshopLookdev: instantiate() вернул null для куклы %d" % i)
			continue
		d.name = "Doll%d" % (i + 1)
		d.set("player_index", i)
		d.set("external_input", true)
		d.position = doll_positions[i]
		$Dolls.add_child(d)
		_set_gi_dynamic(d)
		dolls.append(d)
	if dolls.size() >= 2:
		_setup_contacts(dolls[1])


## Стекло/декали: без тени (иначе shadow map перекрывает лучи солнца в volumetric fog).
func _fix_shadows(n: Node) -> void:
	if n is MeshInstance3D:
		var nm := String(n.name)
		if nm.begins_with("Glass") or nm.contains("Decal"):
			(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_fix_shadows(c)


func _set_gi_dynamic(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	for c in n.get_children():
		_set_gi_dynamic(c)


func _setup_contacts(doll: Node3D) -> void:
	for c in doll.get_children():
		if c is RigidBody3D:
			var b := c as RigidBody3D
			b.contact_monitor = true
			b.max_contacts_reported = 4
			b.body_entered.connect(_on_part_contact.bind(b))


func _on_part_contact(_other: Node, part: RigidBody3D) -> void:
	var vel := part.linear_velocity
	var speed := maxf(vel.length(), float(_prev_speed.get(part, 0.0)))
	if vel.length_squared() < 1e-4:
		vel = Vector3.DOWN
	if speed < IMPACT_SPEED:
		return
	if time - float(part.get_meta("fx_t", -10.0)) < FX_COOLDOWN_S:
		return
	part.set_meta("fx_t", time)
	var pos := part.global_position
	var nrm := -vel.normalized()
	var st := PhysicsServer3D.body_get_direct_state(part.get_rid())
	if st != null and st.get_contact_count() > 0:
		pos = st.get_contact_local_position(0)
		nrm = st.get_contact_local_normal(0)
		if nrm.dot(vel) > 0.0:
			nrm = -nrm
	spawn_fx(pos, nrm, speed)
	contact_impacts += 1


func spawn_fx(pos: Vector3, nrm: Vector3, strength: float) -> void:
	ImpactFx.spawn_impact(self, pos, nrm, strength)
	fx_spawned += 1


func doll_com(i: int) -> Vector3:
	if i >= dolls.size():
		return Vector3.ZERO
	var d := dolls[i]
	if d.has_method("centre_of_mass"):
		return d.call("centre_of_mass") as Vector3
	return d.global_position + Vector3(0.0, 0.9, 0.0)


func doll_part(i: int, part_name: String) -> Node3D:
	if i >= dolls.size():
		return null
	return dolls[i].get_node_or_null(part_name) as Node3D


func _physics_process(delta: float) -> void:
	time += delta
	if dolls.size() < 2:
		return
	for d in dolls:
		d.set("input_vec", Vector2.ZERO)
	if time > PUSH_START and time < PUSH_END:
		dolls[1].set("input_vec", push_vec)
	for c in dolls[1].get_children():
		if c is RigidBody3D:
			_prev_speed[c] = (c as RigidBody3D).linear_velocity.length()
