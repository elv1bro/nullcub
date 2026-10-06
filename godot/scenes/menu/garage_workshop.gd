## Мастерская внутри гаража меню (решение автора 02.10: «не менять даже локацию, всё делать прямо в гараже»).
## 06.10 (мир людей, гараж от первого лица): спящая мастерская — «витрина»: её стенд и кукла видны в гараже всегда (кукла висит на
## стенде, как будто её дорабатывают), интерфейс и свет сборки спрятаны, процесс стоит (_showcase). Вход — герой надевает нейрошлем
## у верстака (GarageHeadset.put_on): в чёрном кадре визора мастерская берёт камеру; выход — снимает шлем (take_off) и кладёт на
## подставку. Мастерская кампании открывается из эфира одним визором (visor_on), выход из неё — как раньше, сразу.
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
		CraftEdit.preload_parts_threaded()   # детали полок — туда же, в потоки: иначе их 157 файлов читаются в кадре постановки (≈ 540 мс)


func _poll_load() -> void:
	var st := ResourceLoader.load_threaded_get_status(SCENE)
	if st == ResourceLoader.THREAD_LOAD_LOADED:
		load_ms = Time.get_ticks_msec() - _t_load
		# ставим, когда камера стоит (титул / пункт меню): подвисание кадра при сборке мастерской не видно на переезде
		if not bool(garage.call("is_moving")) and CraftEdit.parts_preloaded():
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
	if ws.stand_root != null:
		ws.stand_root.process_mode = Node.PROCESS_MODE_ALWAYS   # стенд подгоняет муфту и седло под куклу и у спящей мастерской
	_showcase()
	inst_ms = Time.get_ticks_msec() - t0
	instantiated.emit()


## Спящая мастерская как витрина гаража: виден только стенд с куклой (и разметка гаража под ним); интерфейс, свет сборки, оружие на
## верстаке — спрятаны. Процесс мастерской стоит (кукла заморожена).
func _showcase() -> void:
	if ws == null or ws.active:
		return
	ws.visible = true
	for n in ["UI", "BuildLights", "TestLights"]:
		var c := ws.get_node_or_null(n)
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
		elif c is Node3D:
			(c as Node3D).visible = false
	if ws.bench_weapon != null and is_instance_valid(ws.bench_weapon):
		ws.bench_weapon.visible = false
	if ws.stand_root != null:
		ws.stand_root.visible = true
	if ws.stand != null and is_instance_valid(ws.stand):
		ws.stand.visible = true


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
	var ui_root := garage.get("ui") as Control
	_set_props(false)
	var layer_root := _ui_root()
	if layer_root != null:
		layer_root.modulate.a = 0.0
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(ui_root, "modulate:a", 0.0, 0.3)
	var hs := garage.get("headset") as GarageHeadset
	var n0 := garage.get("n0") as GarageN0
	if n0 != null:   # N0 летит к стенду — подержать свет
		n0.fly_to(ws.stand_root.global_position + Vector3(0.7, 1.75, 0.45))
		n0.face_camera = false
		n0.light(true, ws.stand_root.global_position + Vector3(0, 1.0, 0))
	garage.call("_set_zone_mult", "bench", 0.8)
	if hs == null or not hs.has_headset():
		_link_open()
	elif campaign != null:
		hs.visor_on(_link_open, _handover_done)
	else:
		hs.put_on(_link_open, _handover_done)


## Кадр чёрный (визор закрыт): мастерская просыпается, камера гаража встаёт в кадр сборки и отдаёт его мастерской.
func _link_open() -> void:
	var cam := garage.get("cam") as Camera3D
	ws.set_active(true, false)
	var target := ws.snap_camera_pose()
	(garage.get("view") as GarageView).move(target, WorkshopBuild.CAM_FOV, 0.0, true)
	cam.global_transform = target
	cam.fov = WorkshopBuild.CAM_FOV
	_handover()


func _handover_done() -> void:
	pass


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


## Выйти из мастерской в меню гаража (двойной Esc или код). Свободная мастерская: герой снимает шлем (GarageHeadset.take_off) —
## в чёрном кадре камера гаража встаёт у верстака, мастерская засыпает витриной; руки кладут шлем на подставку, и герой идёт к пункту меню.
## Мастерская кампании (или гараж без шлема) — сразу: камера гаража встаёт на кадр сборки.
func close() -> void:
	if not is_open() or _closing:
		return
	if on_exit.is_valid():      # кампания: она заберёт сборку и сама закроет нас (on_exit очищается перед вторым вызовом)
		on_exit.call()
		return
	var hs := garage.get("headset") as GarageHeadset
	if campaign == null and hs != null and hs.has_headset():
		_closing = true
		ws.set_process_input(false)
		ws.set_process_unhandled_input(false)
		hs.take_off(_unlink, _close_done)
		return
	var cam := garage.get("cam") as Camera3D
	cam.global_transform = ws.build_cam.global_transform
	cam.fov = ws.build_cam.fov
	(garage.get("view") as GarageView).move(cam.global_transform, cam.fov, 0.0, true)
	_unlink()
	if hs != null:
		hs.reset()
	if campaign != null:    # возвращает управление кампании (она ведёт камеру к телевизору и показывает сетку)
		_leave_campaign_mode()
		closed.emit()
		return
	_close_done()


var _closing := false


## Кадр чёрный (визор снят): камера гаража у верстака (точка Pilot), мастерская засыпает витриной.
func _unlink() -> void:
	var cam := garage.get("cam") as Camera3D
	if _closing:
		var spots: Dictionary = garage.get("spots")
		if spots.has(GarageHeadset.PILOT_SPOT):
			var fovs: Dictionary = garage.get("spot_fov")
			(garage.get("view") as GarageView).move(spots[GarageHeadset.PILOT_SPOT], float(fovs[GarageHeadset.PILOT_SPOT]), 0.0, true)
	cam.make_current()
	ws.set_active(false)
	_showcase()
	var layer_root := _ui_root()
	if layer_root != null:
		layer_root.modulate.a = 1.0
	_set_props(true)
	var n0 := garage.get("n0") as GarageN0
	if n0 != null:
		n0.light(false)
		n0.face_camera = true


## Шлем на подставке: меню гаража, герой идёт к пункту; стена экранов показывает новую сборку.
func _close_done() -> void:
	_closing = false
	var ui_root := garage.get("ui") as Control
	ui_root.visible = true
	ui_root.modulate.a = 1.0
	garage.set("state", "menu")
	(garage.get("menu_box") as Control).visible = true
	garage.call("set_focus", int(garage.get("focus")))
	var sw := garage.get("stats_wall") as GarageStatsWall
	if sw != null:
		sw.refresh()
	closed.emit()


## Гаражная разметка под стендом остаётся; прятать больше нечего (кукла с ящика и гаражный стенд убраны 06.10 — стенд и кукла теперь
## мастерской). Оставлено для старых сцен гаража, где эти узлы ещё есть.
func _set_props(menu_view: bool) -> void:
	for path in ["Props/PlayerDoll", "Props/Stand"]:
		var n := garage.get_node_or_null(path) as Node3D
		if n != null:
			n.visible = menu_view


## Испытание — весь гараж светится ровно (как комната испытаний), сборка — свет у верстака; на испытании открываются ворота в зал.
func _on_mode(m: int) -> void:
	var testing := m == WorkshopBuild.Mode.TEST
	if not testing:
		_leave_test()
	if not is_open():
		return
	garage.call("_set_zone_mult", "" if testing else "bench", 0.4)
	var n0 := garage.get("n0") as GarageN0
	if n0 != null and ws.stand_root != null:   # на испытании N0 отлетает к задней стене (за плоскость боя), в сборке — снова у стенда
		var sp := ws.stand_root.global_position
		n0.fly_to(Vector3(0.6, 2.5, -2.3) if testing else sp + Vector3(0.7, 1.75, 0.45))
		n0.light(not testing, sp + Vector3(0, 1.0, 0))
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
	# мастерская спит (process_mode = DISABLED) и её панель сама карточки не достроит — доделываем библиотеку по кадрам, пока игрок в меню
	if ws != null and not is_open() and ws.ui != null and ws.ui.has_method("pump_cards"):
		ws.ui.call("pump_cards", 3.0)
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
