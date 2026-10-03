## Тренировочный зал за воротами мастерской гаража (docs/plan-demo/MENU_GARAGE.md, «Тренировочный зал»; автор 02.10): большой зал
## вдоль плоскости боя z = 0 влево от гаража (x от −4.7 до −47 м, пол y = 0 — продолжение пола гаража), собран builder-ом
## tools/build_training_hall.gd из кита Old NULL Hall и новых модулей (Heavy_Bag, Chain_Link, Tire_Column, Hang_Beam). В зале: манекен
## на подвесе (его ставит мастерская — WorkshopBuild.start_test, точка DummySpot), груша-шар на цепи (HeavyBag), колонна из покрышек
## (с коллайдером), три экрана на задней стене («HUD как экраны»: скорость, сила удара, манекен — HallScreen) и энергетическая
## сетка по краям стен (energy_grid.gdshader): дальняя стена, края задней стены, полосы по полу и потолку.
## Спит, пока не нужен (set_awake(false): невидим, физика и процессы выключены — коллайдеры выходят из мира, свет не считается).
## bind(кукла, манекен) на время испытания: экраны получают данные (скорость куклы, удары по груше, HP манекена); unbind() — отпустить.
## Только поведение и данные экранов; расстановка — в tscn (builder).
class_name TrainingHall
extends Node3D

signal bag_hit(info: Dictionary)

const SPEED_SAMPLES := 90               # график скорости: ~3 с при обновлении раз в 2 кадра
const HIST_MAX := 12

var bag: HeavyBag
var screens := {}                       # "speed" | "impact" | "dummy" → HallScreen
var awake := false
var doll: Node3D
var dummy: Node
var _grids: Array = []
var _v_hist: Array = []
var _v_max := 0.0
var _f_hist: Array = []
var _impact := {"f_n": 0.0, "speed": 0.0, "impulse": 0.0, "hits": 0, "best_n": 0.0, "hist": []}
var _frame := 0
var _grid_focus := 0.0


func _ready() -> void:
	bag = get_node_or_null("Bag") as HeavyBag
	for k in ["speed", "impact", "dummy"]:
		var s := get_node_or_null("Screens/" + k) as HallScreen
		if s != null:
			screens[k] = s
	var gh := get_node_or_null("Grids")
	if gh != null:
		for g in gh.get_children():
			if g is MeshInstance3D:
				_grids.append(g)
	if bag != null:
		bag.hit.connect(_on_bag_hit)
	set_awake(false)


func bounds() -> AABB:
	return AABB(Vector3(-47.0, 0.0, -1.0), Vector3(42.5, 10.0, 2.0))


## Включить / усыпить зал целиком (свет, экраны, физика груши и коллайдеры пола).
func set_awake(on: bool) -> void:
	awake = on
	visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if on and bag != null:
		bag.reset_stats()


## Привязать испытание: кукла игрока (ModularDoll) и манекен (training_dummy.gd; null — без экрана манекена).
func bind(d: Node3D, dm: Node) -> void:
	unbind()
	doll = d
	dummy = dm
	_v_hist = []
	_v_max = 0.0
	_f_hist = []
	_impact = {"f_n": 0.0, "speed": 0.0, "impulse": 0.0, "hits": 0, "best_n": 0.0, "hist": []}
	if bag != null:
		bag.reset_stats()
	_push_screens()


func unbind() -> void:
	doll = null
	dummy = null


func _on_bag_hit(info: Dictionary) -> void:
	_f_hist.append(float(info["force_n"]))
	if _f_hist.size() > HIST_MAX:
		_f_hist.pop_front()
	_impact = {"f_n": float(info["force_n"]), "speed": float(info["speed_ms"]), "impulse": float(info["impulse_ns"]),
		"hits": bag.hits, "best_n": bag.best_force_n, "hist": _f_hist.duplicate()}
	if screens.has("impact"):
		(screens["impact"] as HallScreen).flash()
	_push_screens()
	bag_hit.emit(info)


func _physics_process(_delta: float) -> void:
	if not awake:
		return
	_frame += 1
	var x := _grid_focus
	if doll != null and is_instance_valid(doll):
		var t := doll.call("torso") as RigidBody3D
		if t != null:
			x = t.global_position.x
			if _frame % 2 == 0:
				var v := t.linear_velocity.length()
				_v_hist.append(v)
				if _v_hist.size() > SPEED_SAMPLES:
					_v_hist.pop_front()
				_v_max = maxf(_v_max, v)
	_grid_focus = lerpf(_grid_focus, x, 0.15)
	for g in _grids:
		var m := (g as MeshInstance3D).material_override as ShaderMaterial
		if m != null:
			m.set_shader_parameter("focus_x", _grid_focus)
			m.set_shader_parameter("focus_amt", 1.0 if doll != null else 0.0)
	if _frame % 4 == 0:
		_push_screens()


func _push_screens() -> void:
	if screens.has("speed"):
		var v := 0.0
		if doll != null and is_instance_valid(doll):
			var t := doll.call("torso") as RigidBody3D
			v = t.linear_velocity.length() if t != null else 0.0
		(screens["speed"] as HallScreen).set_data({"v": snappedf(v, 0.1), "vmax": snappedf(_v_max, 0.1), "hist": _v_hist.duplicate()})
	if screens.has("impact"):
		(screens["impact"] as HallScreen).set_data(_impact)
	if screens.has("dummy") and dummy != null and is_instance_valid(dummy):
		var lh: Dictionary = dummy.get("last_hit") if dummy.get("last_hit") != null else {}
		(screens["dummy"] as HallScreen).set_data({"hp": snappedf(float(dummy.call("hp")), 0.5), "max_hp": float(dummy.call("max_hp")),
			"alive": bool(dummy.call("alive")), "last": snappedf(float(lh.get("amount", 0.0)), 0.1),
			"total": snappedf(float(dummy.get("total_damage")), 0.1), "hits": int(dummy.get("hits")), "kos": int(dummy.get("kos"))})
