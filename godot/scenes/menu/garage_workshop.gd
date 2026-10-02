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

const SCENE := "res://scenes/workshop/workshop_embed.tscn"
const DIVE_S := 0.95

var garage: Node3D                  # GarageMenu
var ws: WorkshopBuild
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


func _process(_delta: float) -> void:
	# мастерская спит (process_mode = DISABLED) и её панель сама карточки не достроит — доделываем библиотеку по кадрам, пока игрок в меню
	if ws != null and not is_open() and ws.ui != null and ws.ui.has_method("pump_cards"):
		ws.ui.call("pump_cards", 3.0)
	if not loading:
		return
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
	inst_ms = Time.get_ticks_msec() - t0


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


## Испытание — весь гараж светится ровно (как комната испытаний), сборка — свет у верстака.
func _on_mode(m: int) -> void:
	if not is_open():
		return
	garage.call("_set_zone_mult", "" if m == WorkshopBuild.Mode.TEST else "bench", 0.4)
