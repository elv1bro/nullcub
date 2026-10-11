## Шайба хоккея (docs/plan-demo/HOCKEY.md): снаряд спорт-зала вместо мяча — тот же SportBall (касания, last_touch, потолок
## скорости, place / release, камера), но плоский диск: лежит на льду плашмя (CylinderShape3D осью по y, в плоскости боя —
## полоса 2 × HOCKEY_PUCK_R на HOCKEY_PUCK_THICK), вращение заперто (и ang_damp 6 из Tuning.SPORTS["hockey"]) — не катится и не
## встаёт на ребро, скользит. Лёд — трение шайбы 0.02 и пол зала HOCKEY_ICE_FRICTION при хоккее (HockeyRink.apply_ice).
## Не подпрыгивает: после касания пола скорость вверх ниже HOCKEY_PUCK_HOP_KILL гасится (отскок 0.55 нужен бортам).
## Рукой не берётся (meta no_grab от SportBall — ArmAssist.can_grab), группа puck. Сцена — scenes/sport/puck.tscn (Model_hockey);
## площадка спорт-зала добавляет её сама (playground_sport.gd), SportMatch выбирает снаряд по виду (_pick_ball).
class_name Puck
extends SportBall

const PUCK_GROUP := "puck"

var hops_killed := 0
## Наибольшая высота центра с момента последнего place() (пробы: шайба не подскакивает после удара).
var max_y_seen := 0.0


func _ready() -> void:
	sport = "hockey"
	super._ready()
	add_to_group(PUCK_GROUP)
	axis_lock_angular_z = true


## Высота центра лежащей шайбы.
static func rest_y() -> float:
	return Tuning.HOCKEY_PUCK_THICK * 0.5


func place(pos: Vector3) -> void:
	super.place(pos)
	max_y_seen = pos.y
	hops_killed = 0


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not freeze:
		max_y_seen = maxf(max_y_seen, global_position.y)


## Касание клюшкой — касание её хозяина (автор гола, last_touch): клюшка лежит в узле Weapons площадки, а не в кукле.
func _on_body_entered(body: Node) -> void:
	var w := body as Weapon
	if w != null and w.is_held() and is_instance_valid(w.holder):
		var d: Variant = w.holder.get("doll")
		if d is Doll and is_instance_valid(d) and (d as Doll).torso() != null:
			body = (d as Doll).torso()
	super._on_body_entered(body)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	super._integrate_forces(state)
	var v := state.linear_velocity
	if v.y <= 0.0 or v.y >= Tuning.HOCKEY_PUCK_HOP_KILL:
		return
	var y := state.transform.origin.y
	for i in state.get_contact_count():
		# лёд: статика под шайбой — подскок гасится (борта и перекладина выше низа шайбы — не трогаем)
		if state.get_contact_collider_object(i) is StaticBody3D and state.get_contact_collider_position(i).y < y - Tuning.HOCKEY_PUCK_THICK * 0.3:
			v.y = 0.0
			state.linear_velocity = v
			hops_killed += 1
			return
