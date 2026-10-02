## Кампания «История» внутри гаража меню (решение автора 02.10: «перестроить как в телек, когда влетаем; не переключать
## локацию — сразу там всё показывать и красиво»). «ИСТОРИЯ»: камера ныряет в телевизор, картинка переходит в полноэкранный эфир
## (scenes/menu/campaign_tv_ui.gd): турнирная сетка лиги → бой в куполе → итоги с трофеем → мастерская → следующий бой. Сцена не
## меняется ни разу: бой ставится в мир гаража, комната на время боя спрятана (set_world_visible), поверх — слой кинескопа;
## мастерская между боями — встроенная (GarageWorkshop в режиме кампании: полка = кит + трофеи, шаблоны закрыты, регламент энергии).
## Правила — те же, что у отдельной сцены кампании (scenes/campaign/campaign_flow.gd, остаётся для проб и клавиши 9): поражение —
## бой переигрывается без штрафа; победа — случайная деталь соперника (CampaignState.record_result); сохранение — после каждого боя
## и выхода из мастерской (user://campaign.tres + чертёж user://blueprints/_campaign.tres).
## API для проб: open(), close(), show_ladder(), start_fight(), finish_fight(won, info), open_workshop(), close_workshop(),
## new_campaign(); поля state, screen, fight; save_path / bp_name / load_save — свои файлы (до open()).
class_name GarageCampaign
extends Node

enum Screen { NONE, LADDER, FIGHT, OUTCOME, WORKSHOP }

signal screen_changed(screen: int)
signal opened
signal closed

const FIGHT_SCENE := "res://scenes/campaign/campaign_fight.tscn"
const FIGHT_OVERLAY := 0.32       # сила кинескопа поверх боя (на экранах — 1)
const DIVE_S := 1.05
const BACK_S := 0.9

var garage: Node3D                       # GarageMenu
var ui: CampaignTvUi
var state: CampaignState
var screen := Screen.NONE
var fight: Node = null
var last_trophy := ""
var last_outcome: Dictionary = {}
var ladder_message := ""
var is_open := false
var save_path := CampaignState.SAVE_PATH
var bp_name := CampaignState.BP_NAME
var load_save := true
var entrance_enabled := true             # выход бойцов перед боем; пробы выключают
var fight_load_ms := -1
var _fight_requested := false
var _tw: Tween


func _init(g: Node3D = null) -> void:
	garage = g


func _ready() -> void:
	ui = CampaignTvUi.new(garage.get("f_head"), garage.get("f_body"), garage.get("f_mono"))
	ui.name = "TvUi"
	add_child(ui)
	ui.fight_pressed.connect(func() -> void: start_fight())
	ui.workshop_pressed.connect(func() -> void: open_workshop())
	ui.new_pressed.connect(func() -> void: new_campaign())
	ui.exit_pressed.connect(func() -> void: close())
	ui.ladder_pressed.connect(func() -> void:
		if screen == Screen.WORKSHOP:
			close_workshop()
		else:
			show_ladder())


func _ensure_state() -> void:
	if state != null:
		return
	state = CampaignState.load_from(save_path) if load_save else null
	if state == null:
		state = CampaignState.new_game(-1, bp_name)
	_share_state()


## Гараж читает кампанию для строк пункта и карточки на ТВ — отдаём ему живое состояние.
func _share_state() -> void:
	garage.set("_campaign", state)
	garage.set("_campaign_read", true)


func _set_screen(s: int) -> void:
	screen = s
	screen_changed.emit(s)


# ---------------------------------------------------------------- вход и выход

## Нырок в телевизор и переход в эфир. Вызывает гараж по Enter на «ИСТОРИИ».
func open() -> void:
	if is_open:
		return
	is_open = true
	_ensure_state()
	garage.set("state", "campaign")
	_request_fight_scene()
	var ui_root := garage.get("ui") as Control
	if _tw != null and _tw.is_valid():
		_tw.kill()
	garage.call("_move_to", "IntoTV", DIVE_S, 0.0, false, true)
	garage.call("_set_zone_mult", "tv", DIVE_S, 1.6)
	_tw = create_tween()
	_tw.tween_property(ui_root, "modulate:a", 0.0, 0.35)
	_tw.tween_interval(DIVE_S - 0.35 - 0.2)
	_tw.tween_callback(func() -> void:
		ui.set_visible_all(false, true, 1.0)
		ui.reset_power()
		ui.burst(1.0, 0.2))
	_tw.tween_interval(0.2)
	_tw.tween_callback(func() -> void:
		ui_root.visible = false
		show_ladder()
		opened.emit())


## Из эфира обратно в гараж: помехи, камера отъезжает от телевизора к пункту меню.
func close() -> void:
	if not is_open:
		return
	is_open = false
	_free_fight()
	var ws := garage.get("workshop") as GarageWorkshop
	if ws != null and ws.is_open():
		ws.close()
	_set_screen(Screen.NONE)
	ui.burst(1.0, 0.25)
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	_tw.tween_interval(0.2)
	_tw.tween_callback(func() -> void:
		ui.clear_screens()
		ui.set_visible_all(false, false)
		var ui_root := garage.get("ui") as Control
		ui_root.visible = true
		ui_root.modulate.a = 0.0
		create_tween().tween_property(ui_root, "modulate:a", 1.0, 0.4)
		garage.set("state", "menu")
		(garage.get("menu_box") as Control).visible = true
		garage.call("set_focus", int(garage.get("focus")))
		garage.call("refresh_story")
		closed.emit())


# ---------------------------------------------------------------- лестница

func show_ladder() -> void:
	_free_fight()
	_set_screen(Screen.LADDER)
	ui.show_ladder(state, ladder_message)
	ladder_message = ""


func new_campaign(seed_value: int = -1) -> void:
	CampaignState.erase(save_path, bp_name)
	state = CampaignState.new_game(seed_value, bp_name)
	state.save(save_path)
	_share_state()
	show_ladder()


func _input(event: InputEvent) -> void:
	if not is_open or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if (event as InputEventKey).physical_keycode != KEY_ESCAPE:
		return
	if screen == Screen.LADDER:
		close()
	elif screen == Screen.OUTCOME:
		show_ladder()
	else:
		return
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- бой

## Купол грузится в фоне, пока игрок читает сетку (сцена тяжёлая: толпа, трибуны, ~секунды).
func _request_fight_scene() -> void:
	if _fight_requested:
		return
	_fight_requested = true
	ResourceLoader.load_threaded_request(FIGHT_SCENE, "", true)


## Бой с текущим соперником. false — не начался (лига пройдена или сборка не готова — причина на сетке). Сам бой ставится после
## заставки «подключение» (пара кадров), чтобы тяжёлая постановка не повисла на экране сетки.
func start_fight() -> bool:
	close_workshop()
	if state.finished():
		show_ladder()
		return false
	var errs := CraftEdit.friendly_errors(state.blueprint)
	if not errs.is_empty():
		ladder_message = "Сборка не готова к бою: %s — открой мастерскую." % errs[0]
		show_ladder()
		return false
	_free_fight()
	_set_screen(Screen.FIGHT)
	var r := state.current_rival()
	Loading.begin("ПЕРЕКЛЮЧАЕМ НА ПЛОЩАДКУ", "купол Old NULL Hall · %s" % CampaignLeague.rival_title(r).to_upper())
	_launch_fight.call_deferred()
	return true


func _launch_fight() -> void:
	await Loading.present()
	if screen != Screen.FIGHT:
		Loading.finish()
		return     # пока рисовалась заставка, вышли
	var t0 := Time.get_ticks_msec()
	var ps := await Loading.load_async(FIGHT_SCENE, "ПЕРЕКЛЮЧАЕМ НА ПЛОЩАДКУ") as PackedScene
	if ps == null:
		ps = load(FIGHT_SCENE) as PackedScene
	fight_load_ms = Time.get_ticks_msec() - t0
	await Loading.present()
	var r := state.current_rival()
	fight = ps.instantiate()
	fight.call("setup", state.blueprint, CampaignLeague.rival_blueprint(state.tier, r), r, CampaignLeague.rival_title(r), {
		"entrance": entrance_enabled, "player_name": "Игрок", "player_build": state.blueprint.title,
		"player_record": "побед %d · поражений %d · трофеев %d" % [state.wins, state.losses, state.trophies.size()],
		"rival_build": "%s · уровень %d" % [CampaignLeague.tier_title(state.tier), int(r.get("level", 1))],
		"rival_record": "ФИНАЛ ЛИГИ" if bool(r.get("final", false)) else "соперник %d из %d" % [state.step + 1, state.ladder().size()]})
	fight.connect("fight_finished", finish_fight)
	fight.connect("fight_abandoned", func() -> void:
		_free_fight()
		show_ladder())
	garage.call("set_world_visible", false)
	garage.add_child(fight)
	ui.clear_screens()
	ui.set_visible_all(false, true, FIGHT_OVERLAY)
	ui.burst(0.9, 0.5)
	Loading.finish()


## Итог боя (сигнал сцены боя; проба зовёт напрямую): запись в кампанию, сохранение, экран итогов.
func finish_fight(won: bool, info: Dictionary = {}) -> void:
	last_outcome = info.duplicate()
	last_outcome["won"] = won
	last_trophy = state.record_result(won, info)
	state.save(save_path)
	_free_fight()
	show_outcome()


func _free_fight() -> void:
	if fight != null and is_instance_valid(fight):
		garage.remove_child(fight)
		fight.queue_free()
	fight = null
	Engine.time_scale = 1.0
	var gw := garage.get("workshop") as GarageWorkshop
	if screen != Screen.WORKSHOP and (gw == null or not gw.is_open()):
		garage.call("set_world_visible", true)
		(garage.get("cam") as Camera3D).make_current()


func show_outcome() -> void:
	_set_screen(Screen.OUTCOME)
	ui.set_visible_all(true, true, 1.0)
	ui.show_outcome(state, last_outcome, last_trophy, state.ladder()[maxi(mini(state.step - (1 if bool(last_outcome.get("won", false)) else 0), state.ladder().size() - 1), 0)])


# ---------------------------------------------------------------- мастерская

## Встроенная мастерская гаража в режиме кампании. Камера плывёт от телевизора к стенду, поверх — плашка кампании.
func open_workshop() -> void:
	_free_fight()
	var gw := garage.get("workshop") as GarageWorkshop
	if gw == null or screen == Screen.WORKSHOP:
		return
	state.save(save_path)
	_set_screen(Screen.WORKSHOP)
	ui.set_visible_all(true, false)
	ui.show_workshop_bar(state)
	gw.open_campaign(state, close_workshop)


## Выйти из мастерской кампании: сборка — в кампанию (как есть, лестница покажет причину), сохранение, камера — к телевизору.
func close_workshop() -> void:
	var gw := garage.get("workshop") as GarageWorkshop
	if gw == null or screen != Screen.WORKSHOP:
		return
	_set_screen(Screen.NONE)
	gw.on_exit = Callable()
	if gw.ws != null:
		state.blueprint = CraftEdit.dup_body(gw.ws.blueprint)   # до close(): оно вернёт свободной мастерской сборку игрока
		state.apply_regulation()
	state.save(save_path)
	if gw.is_open():
		gw.close()
	garage.set("state", "campaign")
	ui.clear_screens()
	garage.call("_move_to", "IntoTV", 0.95, 0.06)
	garage.call("_set_zone_mult", "tv", 0.6, 1.6)
	show_ladder()
	ui.set_visible_all(true, true, 1.0)
	ui.burst(0.7, 0.4)
