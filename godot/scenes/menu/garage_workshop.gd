## Мастерская внутри гаража меню (решение автора 02.10: «не менять даже локацию, всё делать прямо в гараже»).
## Сцена мастерской (scenes/workshop/workshop_embed.tscn — тот же workshop_build.gd, но без своей комнаты) грузится в фоне, пока игрок
## в меню, и ставится в мир гаража спящей. «МАСТЕРСКАЯ»: кукла встаёт с ящика, камера гаража ныряет к стенду и отдаёт кадр
## мастерской (без скачка), поверх ложится интерфейс сборки. Двойной Esc — обратно: камера возвращается к пункту меню, кукла на ящике
## пересобирается по новому чертежу. «Испытать» — бой 2.5D в плоскости z = 0 прямо на полу гаража (невидимые пол и стены — Stage).
## Устройство и числа — docs/plan-demo/MENU_GARAGE.md §0.
class_name GarageWorkshop
extends Node

signal opened
signal closed
signal instantiated      # мастерская поставлена в мир (спящая): гараж готов к вводу
signal hall_ready        # тренировочный зал поставлен в мир (спящий)

const SCENE := "res://scenes/workshop/workshop_embed.tscn"
const HALL_SCENE := "res://scenes/arena/training_hall.tscn"
const DIVE_S := 0.95

var garage: Node3D                  # GarageMenu
var ws: WorkshopBuild
## Тренировочный зал за воротами (scenes/arena/training_hall.tscn): грузится под лоадером при первом испытании, дальше живёт спящим.
var hall: TrainingHall
var hall_inst_ms := -1
var _hall_prep := false
var _hall_prefetched := false
var _want_test := false
var loading := false
var load_ms := -1                   # сколько мастерская грузилась в фоне (проба / замер), мс
var inst_ms := -1                   # сколько ставилась в мир (instantiate + _ready), мс
## Свойства мастерской, выставляемые до её _ready (проба: свой файл автосейва, чтобы не трогать сборку игрока).
var ws_overrides := {}
## Режим кампании (open_campaign): состояние кампании и что вызвать вместо «в меню» (двойной Esc / кнопки мастерской).
var campaign: CampaignState = null
var on_exit := Callable()
var _free_autosave := ""            # имя автосейва свободной мастерской (пока она в режиме кампании)
var _t_load := 0
var _tw: Tween


func _init(g: Node3D = null) -> void:
	garage = g


## Начать фоновую загрузку (треды движка): ни кадра, ни пауз не отнимает.
func preload_scene() -> void:
	if ws != null or loading:
		return
	if ResourceLoader.load_threaded_request(SCENE, "", true) == OK:
		loading = true
		_t_load = Time.get_ticks_msec()


func _poll_load() -> void:
	var st := ResourceLoader.load_threaded_get_status(SCENE)
	if st == ResourceLoader.THREAD_LOAD_LOADED:
		load_ms = Time.get_ticks_msec() - _t_load
		# ставим, когда камера стоит (титул / пункт меню): подвисание кадра при сборке мастерской не видно на переезде
		if not bool(garage.call("is_moving")):
			_instantiate()
	elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		loading = false
		push_error("GarageWorkshop: мастерская не загрузилась (%s)" % SCENE)


func _instantiate() -> void:
	if ws != null:
		return
	var ps := ResourceLoader.load_threaded_get(SCENE) as PackedScene
	loading = false
	var t0 := Time.get_ticks_msec()
	ws = ps.instantiate() as WorkshopBuild
	ws.name = "Workshop"
	ws.visible = false
	ws.process_mode = Node.PROCESS_MODE_DISABLED
	ws.active = false      # до _ready: set_active(true) потом действительно включит
	for k in ws_overrides:
		ws.set(k, ws_overrides[k])
	garage.add_child(ws)
	ws.set_process_unhandled_input(false)
	ws.set_process_input(false)
	var layer := ws.get_node_or_null("UI") as CanvasLayer
	if layer != null:
		layer.visible = false
	ws.exit_requested.connect(close)
	ws.mode_changed.connect(_on_mode)
	ws.test_ready_check = hall_is_ready
	inst_ms = Time.get_ticks_msec() - t0
	instantiated.emit()


func is_open() -> bool:
	return ws != null and ws.active


## Войти в мастерскую. Камера гаража плавно доезжает до кадра мастерской и отдаёт управление.
func open() -> void:
	_ensure()
	if campaign != null:
		_leave_campaign_mode()
	_dive()


## Мастерская кампании «История» (garage_campaign.gd): та же встроенная сцена, но полка — стартовый кит и трофеи, шаблоны закрыты,
## сборка — из чертежа кампании, автосейв — в него же, выход одним Esc. exit — что вызвать вместо возврата в меню гаража.
func open_campaign(st: CampaignState, exit: Callable) -> void:
	_ensure()
	campaign = st
	on_exit = exit
	if _free_autosave == "":
		_free_autosave = ws.autosave_name
	CraftEdit.campaign_shelf = st.shelf_parts()
	CraftEdit.campaign_templates_locked = false   # загрузка чертежа — до блокировки шаблонов
	ws.autosave_name = st.bp_name
	ws.start_preset = CampaignLeague.START_PRESET
	CraftEdit.campaign_templates_locked = true
	ws.load_path(CraftEdit.save_path(st.bp_name))
	if ws.blueprint.weapon == null:
		ws.clear_weapon()   # верстак стартует с молотом-шаблоном — в кампании оружие собирается только из деталей полки
	ws.history.clear()
	ws.redo_stack.clear()
	ws.single_esc_exit = true
	ws.view_changed.emit(ws.view)   # UI перестраивает левую панель — плитки шаблонов прячутся
	_dive()


func _ensure() -> void:
	if ws == null:
		if not loading:
			preload_scene()
		ResourceLoader.load_threaded_get_status(SCENE)   # дождаться, если ещё грузится
		_instantiate_blocking()


## Вернуть свободной мастерской её полку, шаблоны и автосейв игрока (после кампании).
func _leave_campaign_mode() -> void:
	CraftEdit.campaign_shelf = PackedStringArray()
	CraftEdit.campaign_templates_locked = false
	ws.single_esc_exit = false
	if _free_autosave != "":
		ws.autosave_name = _free_autosave
		_free_autosave = ""
	campaign = null
	on_exit = Callable()
	var free_path := CraftEdit.save_path(ws.autosave_name)
	if FileAccess.file_exists(free_path):
		ws.load_path(free_path)
	ws.history.clear()
	ws.redo_stack.clear()
	ws.view_changed.emit(ws.view)


func _dive() -> void:
	prefetch_hall()
	garage.set("state", "workshop")
	var cam := garage.get("cam") as Camera3D
	var ui_root := garage.get("ui") as Control
	_set_props(false)
	ws.set_active(true, false)
	var target := ws.snap_camera_pose()
	var fov := WorkshopBuild.CAM_FOV
	var layer_root := _ui_root()
	if layer_root != null:
		layer_root.modulate.a = 0.0
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(ui_root, "modulate:a", 0.0, 0.3)
	garage.call("_move_xf", target, fov, DIVE_S, 0.12)
	_tw.tween_interval(DIVE_S - 0.3)
	_tw.tween_callback(_handover)
	garage.call("_set_zone_mult", "bench", DIVE_S)


func _instantiate_blocking() -> void:
	var st := ResourceLoader.load_threaded_get_status(SCENE)
	while st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		OS.delay_msec(5)
		st = ResourceLoader.load_threaded_get_status(SCENE)
	_instantiate()


func _handover() -> void:
	var cam := garage.get("cam") as Camera3D
	ws.take_camera_from(cam)
	(garage.get("ui") as Control).visible = false
	var layer_root := _ui_root()
	if layer_root != null:
		create_tween().tween_property(layer_root, "modulate:a", 1.0, 0.35)
	opened.emit()


func _ui_root() -> Control:
	var layer := ws.get_node_or_null("UI") as CanvasLayer
	return layer.get_node_or_null("Root") as Control if layer != null else null


## Выйти из мастерской в меню гаража (двойной Esc или код): кадр камеры — как был, дальше обычный переезд к пункту.
func close() -> void:
	if not is_open():
		return
	if on_exit.is_valid():      # кампания: она заберёт сборку и сама закроет нас (on_exit очищается перед вторым вызовом)
		on_exit.call()
		return
	var in_campaign := campaign != null
	var cam := garage.get("cam") as Camera3D
	cam.global_transform = ws.build_cam.global_transform
	cam.fov = ws.build_cam.fov
	cam.make_current()
	ws.set_active(false)
	var layer_root := _ui_root()
	if layer_root != null:
		layer_root.modulate.a = 1.0
	_set_props(true)
	if in_campaign:         # возвращает управление кампании (она ведёт камеру к телевизору и показывает сетку)
		_leave_campaign_mode()
		closed.emit()
		return
	var ui_root := garage.get("ui") as Control
	ui_root.visible = true
	ui_root.modulate.a = 1.0
	var pd = garage.get("player_doll")
	if pd != null:
		pd.call("rebuild")
	garage.set("state", "menu")
	(garage.get("menu_box") as Control).visible = true
	garage.call("set_focus", int(garage.get("focus")))
	closed.emit()


## Кукла игрока встала с ящика (она теперь на стенде), стенд гаража заменён приборной стойкой мастерской.
func _set_props(menu_view: bool) -> void:
	var pd := garage.get("player_doll") as Node3D
	if pd != null:
		pd.visible = menu_view
	var stand := garage.get_node_or_null("Props/Stand") as Node3D
	if stand != null:
		stand.visible = menu_view


## Испытание — весь гараж светится ровно (как комната испытаний), сборка — свет у верстака; на испытании открываются ворота в зал.
func _on_mode(m: int) -> void:
	var testing := m == WorkshopBuild.Mode.TEST
	if not testing:
		_leave_test()
	if not is_open():
		return
	garage.call("_set_zone_mult", "" if testing else "bench", 0.4)
	if testing:
		_enter_test()


# ---------------------------------------------------------------- тренировочный зал

func _gate() -> GarageHallGate:
	return garage.get_node_or_null("Room/HallGate") as GarageHallGate


## Зал можно догружать в фоне, пока игрок собирает бойца (кадр не страдает); ставится в мир при первом «Испытать».
func prefetch_hall() -> void:
	if hall != null or _hall_prefetched:
		return
	_hall_prefetched = true
	ResourceLoader.load_threaded_request(HALL_SCENE, "", true)


## Хук WorkshopBuild.start_test: зал уже есть — можно; иначе запускаем загрузку под лоадером, а испытание стартует само, когда зал готов.
func hall_is_ready() -> bool:
	if hall != null:
		return true
	_want_test = true
	prepare_hall()
	return false


## Поставить зал в мир (спящим). Под лоадером: фоновая загрузка с прогрессом → постановка (главный поток) → готово.
## Для проб: await prepare_hall().
func prepare_hall() -> void:
	if hall != null or _hall_prep:
		return
	_hall_prep = true
	var t0 := Time.get_ticks_msec()
	Loading.begin("ПОДГОТОВКА ЗАЛА", "тренировочный зал за воротами")
	var ps := await Loading.load_async(HALL_SCENE, "ПОДГОТОВКА ЗАЛА", "тренировочный зал за воротами") as PackedScene
	await Loading.present()
	if ps == null:
		ps = load(HALL_SCENE) as PackedScene
	hall = ps.instantiate() as TrainingHall
	hall.name = "TrainingHall"
	garage.add_child(hall)
	hall_inst_ms = Time.get_ticks_msec() - t0
	_hall_prep = false
	Loading.finish()
	hall_ready.emit()
	if _want_test and ws != null and ws.active and ws.mode == WorkshopBuild.Mode.BUILD:
		_want_test = false
		ws.start_test()
	_want_test = false


## Камера испытания: в гараже кадр тесный (потолок 3.4 м), в зале — шире, чтобы были видны груша, манекен и экраны: min_half_height
## плавно растёт от гаражного к залу по мере вылета куклы через ворота (x от −3 к −9).
const CAM_HALF_GARAGE := 1.55
const CAM_HALF_HALL := 3.7


func _process(_delta: float) -> void:
	if ws != null and ws.mode == WorkshopBuild.Mode.TEST and ws.test_cam != null and ws.test_doll != null and is_instance_valid(ws.test_doll):
		var t := ws.test_doll.call("torso") as RigidBody3D
		if t != null:
			var k := smoothstep(-3.0, -9.0, t.global_position.x)
			ws.test_cam.min_half_height = lerpf(CAM_HALF_GARAGE, CAM_HALF_HALL, k)
	if not loading:
		return
	_poll_load()


func _enter_test() -> void:
	if hall == null or ws == null:
		return
	hall.set_awake(true)
	hall.bind(ws.test_doll, ws.dummy)
	var g := _gate()
	if g != null:
		if not g.opened.is_connected(_on_gate_opened):
			g.opened.connect(_on_gate_opened)
		g.open()
	else:
		_set_door_block(false)


func _on_gate_opened() -> void:
	_set_door_block(false)


func _leave_test() -> void:
	if hall != null and hall.awake:
		hall.unbind()
		hall.set_awake(false)
	var g := _gate()
	if g != null and g.is_open:
		g.close(0.01)
	_set_door_block(true)


## Заглушка проёма на время закрытых ворот (Stage/Bounds/WallL во встроенной сцене).
func _set_door_block(on: bool) -> void:
	if ws == null:
		return
	var cs := ws.get_node_or_null("Stage/Bounds/WallL") as CollisionShape3D
	if cs != null:
		cs.set_deferred("disabled", not on)
