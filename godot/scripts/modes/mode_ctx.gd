## Контекст модификатора (Mutators) на площадке: Match, сцена, арена, поле NULL, куклы, случайности, словари state (свой у каждого
## модификатора) и shared (общий на запуск: что вернуть на выходе), opts запуска (ModeRun.launch). Умеет: гравитацию (поле купола
## или гравитация мира), границы арены, узел для пропсов, объявление на HUD.
class_name ModeCtx
extends RefCounted

var mt: Match
var scene: Node
var arena: Node
var field: NullField
var opts: Dictionary = {}
var state: Dictionary = {}
var shared: Dictionary = {}
var rng := RandomNumberGenerator.new()
var _props: Node3D


func dolls() -> Array:
	return mt.dolls() if mt != null and is_instance_valid(mt) else []


func alive_dolls() -> Array:
	return mt.alive_dolls() if mt != null and is_instance_valid(mt) else []


func doll(index: int) -> Doll:
	for d in dolls():
		if (d as Doll).player_index == index:
			return d
	return null


## Кукла по любой её детали / мозгу (как BombMatch.doll_of).
static func doll_of(n: Node) -> Doll:
	var cur := n
	for _i in 4:
		if cur == null:
			return null
		if cur is Doll:
			return cur
		cur = cur.get_parent()
	return null


## Гравитация: множитель к обычной (Tuning.GRAVITY) и направление в плоскости экрана. В куполе — поле NULL (set_field, в G);
## на других аренах — гравитация мира (PhysicsServer3D), ModeRun возвращает её на выходе.
func set_gravity(mult: float, dir: Vector2, blend_s := 0.0) -> void:
	var d := dir.normalized() if dir.length() > 0.001 else Vector2(0, -1)
	if field != null and is_instance_valid(field):
		field.set_field(Tuning.GRAVITY / Tuning.G_EARTH * mult, d, blend_s)
		return
	var space := _space()
	if not space.is_valid():
		return
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, Tuning.GRAVITY * mult)
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, Vector3(d.x, d.y, 0.0))


static func restore_world_gravity(tree: SceneTree) -> void:
	var space := tree.root.get_world_3d().space if tree != null and tree.root != null else RID()
	if not space.is_valid():
		return
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, float(ProjectSettings.get_setting("physics/3d/default_gravity", Tuning.GRAVITY)))
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR,
		ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3(0, -1, 0)))


func _space() -> RID:
	if scene != null and scene is Node3D and (scene as Node3D).is_inside_tree():
		return (scene as Node3D).get_world_3d().space
	if mt != null and mt.is_inside_tree():
		return mt.get_tree().root.get_world_3d().space
	return RID()


## Границы арены (AABB в плоскости XY); нет arena.bounds() — по куклам ± 10 м.
func bounds() -> AABB:
	if arena != null and arena.has_method("bounds"):
		return arena.call("bounds")
	var c := Vector3.ZERO
	var ds := dolls()
	for d in ds:
		c += (d as Doll).centre_of_mass()
	if not ds.is_empty():
		c /= ds.size()
	return AABB(c - Vector3(10.0, 3.0, 1.0), Vector3(20.0, 10.0, 2.0))


## Узел для пропсов режима (бочки, оружие, ящики): ModeProps под сценой; удаляется вместе со сценой.
func props_root() -> Node3D:
	if _props != null and is_instance_valid(_props):
		return _props
	var host: Node = scene if scene != null else (mt.get_parent() if mt != null else null)
	if host == null:
		return null
	_props = host.get_node_or_null("ModeProps") as Node3D
	if _props == null:
		_props = Node3D.new()
		_props.name = "ModeProps"
		host.add_child(_props)
	return _props


func announce(text: String, color := Color(0.9, 0.9, 0.95), kind := "event") -> void:
	if mt != null and is_instance_valid(mt):
		mt.announce.emit(text, color, kind)


## Тост внизу экрана (HitJuice, если он у Match есть).
func toast(text: String, secs := 2.5) -> void:
	if mt == null or not is_instance_valid(mt):
		return
	var j := mt.get_node_or_null("HitJuice")
	if j != null and j.has_method("show_toast"):
		j.call("show_toast", text, secs)
