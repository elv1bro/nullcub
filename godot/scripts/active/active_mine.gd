## Мина минного лотка (ActiveBlocks "kit_active_mine", docs/plan-demo/ACTIVE_BLOCKS.md): плоский диск-тело, взводится через arm_s,
## рвётся от касания любой куклы (свою тоже — мина не разбирает) или через life секунд. Взрыв — общий Explosion.detonate (урон,
## отброс, стан; только пока Match.combat_active()), автор взрыва — хозяин мины. Глазок мигает: медленно — не взведена, часто — взведена.
class_name ActiveMine
extends RigidBody3D

var owner_doll: Doll
var arm_s := 0.8
var life := 12.0
var armed := false
var _t := 0.0
var _eye: MeshInstance3D
var _eye_mat: StandardMaterial3D
var _done := false


func _ready() -> void:
	mass = 1.0
	contact_monitor = true
	max_contacts_reported = 6
	body_entered.connect(_on_body)
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 0.065
	cy.height = 0.03
	cs.shape = cy
	cs.rotation_degrees = Vector3(90.0, 0.0, 0.0)   # диск лицом к камере: в плоскости боя катится и ложится на ребро
	add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.065
	cm.bottom_radius = 0.065
	cm.height = 0.03
	mi.mesh = cm
	mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.24, 0.23)
	m.metallic = 0.5
	m.roughness = 0.5
	mi.material_override = m
	add_child(mi)
	_eye = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.016
	sm.height = 0.032
	_eye.mesh = sm
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.albedo_color = Color(1.0, 0.15, 0.1)
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color(1.0, 0.1, 0.05)
	_eye_mat.emission_energy_multiplier = 3.0
	_eye.material_override = _eye_mat
	_eye.position = Vector3(0.0, 0.0, 0.02)
	add_child(_eye)


func _physics_process(dt: float) -> void:
	if _done:
		return
	_t += dt
	if not armed and _t >= arm_s:
		armed = true
		for b in get_colliding_bodies():   # взвелась, уже лёжа на кукле
			_on_body(b)
	var period := 0.18 if armed else 0.6
	_eye.visible = fmod(_t, period) < period * 0.5
	if _t >= life:
		boom()


func _on_body(body: Node) -> void:
	if not armed or _done:
		return
	var n := body
	while n != null:
		if n is Doll:
			boom()
			return
		n = n.get_parent()


func boom() -> void:
	if _done:
		return
	_done = true
	var parent := get_parent()
	var pos := global_position
	queue_free()
	if parent != null:
		Explosion.detonate(parent, pos, owner_doll if is_instance_valid(owner_doll) else null)
