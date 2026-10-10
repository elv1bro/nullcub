## Шайба хоккея (docs/plan-demo/HOCKEY.md): снаряд спорт-зала вместо мяча — тот же SportBall (касания, last_touch, потолок
## скорости, place / release, камера), но диск: стоит ребром к камере (CylinderShape3D осью по z, в плоскости боя она — круг),
## катится как монета и почти не крутится (ang_damp из Tuning.SPORTS["hockey"]). Лёд — малое трение шайбы (пол зала материала
## не имеет, у пары берётся меньшее); не подпрыгивает: после касания пола скорость вверх ниже HOCKEY_PUCK_HOP_KILL гасится
## (отскок 0.55 нужен бортам). Рукой не берётся (meta no_grab — ArmAssist.can_grab), группа puck. Сцена — scenes/sport/puck.tscn
## (Model_hockey — диск), площадка подменяет узел Ball на неё при виде "hockey" (playground_sport.gd).
class_name Puck
extends SportBall

const PUCK_GROUP := "puck"

var hops_killed := 0
## Наибольшая высота центра с момента последнего place()/release() (пробы: шайба не подскакивает после удара).
var max_y_seen := 0.0


func _ready() -> void:
	sport = "hockey"
	super._ready()
	add_to_group(PUCK_GROUP)
	set_meta(&"snd_mat", SoundMaterial.RUBBER)


func radius() -> float:
	return Tuning.HOCKEY_PUCK_R


func place(pos: Vector3) -> void:
	super.place(pos)
	max_y_seen = pos.y
	hops_killed = 0


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not freeze:
		max_y_seen = maxf(max_y_seen, global_position.y)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	super._integrate_forces(state)
	var v := state.linear_velocity
	if v.y <= 0.0 or v.y >= Tuning.HOCKEY_PUCK_HOP_KILL:
		return
	var y := state.transform.origin.y
	for i in state.get_contact_count():
		# лёд: статика под шайбой — подскок гасится (борта и перекладина выше центра — не трогаем)
		if state.get_contact_collider_object(i) is StaticBody3D and state.get_contact_collider_position(i).y < y - radius() * 0.6:
			v.y = 0.0
			state.linear_velocity = v
			hops_killed += 1
			return
