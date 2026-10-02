## Кампания «История» — поток экранов (docs/plan-demo/17-career-trophy.md): лестница → бой в куполе → исход (трофей или «ещё раз»)
## → мастерская → следующий бой. Сцена scenes/campaign/campaign.tscn: Stage — текущая сцена-ребёнок (бой или мастерская; сцена
## дерева не меняется, состояние кампании живёт всё время), UI — экраны лестницы и исхода, полоска кампании поверх мастерской.
## Правила (автор 30.09): все бои в куполе; поражение — бой переигрывается без штрафа; победа — случайная деталь соперника
## (CampaignState.record_result); энергия — регламент лиги (CampaignLeague.energy_budget). Сохранение — после каждого боя и выхода
## из мастерской (user://campaign.tres + чертёж user://blueprints/_campaign.tres; тот же файл мастерская пишет автосейвом).
## Мастерская из кампании: на полке только стартовый кит и трофеи (CraftEdit.campaign_shelf), шаблоны тела и оружия закрыты
## и спрятаны (CraftEdit.campaign_templates_locked), верстак пуст, если в руке ничего нет; оружие в руке ест энергию ядра по
## регламенту лиги (BodyBlueprint.weapon_energy). Esc в мастерской без инструмента и выбора — к лестнице.
## Реплики N0 на лестнице — заглушки до этапа 14 (N0_VOICE.md).
## Пробы (tests/campaign_probe.gd): save_path / bp_name — свои файлы, load_save = false — новая кампания; start_fight(),
## finish_fight(won, info), open_workshop(), close_workshop() — те же шаги, что кнопки.
extends Node

enum Screen { LADDER, FIGHT, OUTCOME, WORKSHOP }

signal screen_changed(screen: int)

const FIGHT_SCENE := preload("res://scenes/campaign/campaign_fight.tscn")
const WORKSHOP_SCENE := "res://scenes/workshop/workshop_build.tscn"
const EXIT_SCENE := "res://scenes/menu/garage_menu.tscn"   # «Выход» — в гараж (Flow.to_menu: на пункт ИСТОРИЯ, без титула)
const COL_DONE := Color(0.55, 0.9, 0.5)
const COL_NEXT := Color(1.0, 0.82, 0.3)
const COL_LATER := Color(0.75, 0.75, 0.78)
const COL_BAD := Color(1.0, 0.45, 0.35)
## Заглушки реплик N0 по шагу лестницы (последняя — лига пройдена). Настоящие — этап 14.
const N0_LINES := [
	"N0: Местная лига! Четыре соперника, один купол — и я вне зоны брызг.",
	"N0: Первая победа — и чужая деталь уже в гараже. Правило трофея.",
	"N0: Дальше Чёртик. Табло сегодня капризничает — не обращай внимания.",
	"N0: Финал местной лиги. Мембрана держит, трибуны полные. Что может пойти не так?",
	"N0: Чемпион местной лиги! …Табло пишет что-то ещё. Наверное, сбой.",
]
const NEW_CONFIRM_S := 3.0

@export var save_path := CampaignState.SAVE_PATH
@export var bp_name := CampaignState.BP_NAME
@export var load_save := true
## Выход бойцов перед каждым боем (этап 16); пробы выключают.
@export var entrance_enabled := true

var state: CampaignState
var screen := Screen.LADDER
var fight: Node = null
var workshop: WorkshopBuild = null
var last_trophy := ""
var last_outcome: Dictionary = {}
var ladder_message := ""
var _new_armed_until := -1.0

@onready var stage: Node = $Stage
@onready var ladder_ui: Control = %Ladder
@onready var outcome_ui: Control = %Outcome
@onready var workshop_bar: Control = %WorkshopBar


func _ready() -> void:
	state = CampaignState.load_from(save_path) if load_save else null
	if state == null:
		state = CampaignState.new_game(-1, bp_name)
	%FightButton.pressed.connect(func() -> void: start_fight())
	%WorkshopButton.pressed.connect(func() -> void: open_workshop())
	%NewButton.pressed.connect(_on_new_pressed)
	%ExitButton.pressed.connect(func() -> void:
		var flow := get_node_or_null("/root/Flow")
		if flow != null:
			flow.to_menu()
		else:
			Loading.change_scene(EXIT_SCENE, "БОКС 07", "возвращаемся в гараж…"))
	%OutcomeNext.pressed.connect(func() -> void: start_fight())
	%OutcomeWorkshop.pressed.connect(func() -> void: open_workshop())
	%OutcomeLadder.pressed.connect(func() -> void: show_ladder())
	%BarFight.pressed.connect(func() -> void:
		close_workshop()
		start_fight())
	%BarLadder.pressed.connect(func() -> void:
		close_workshop()
		show_ladder())
	show_ladder()


func _exit_tree() -> void:
	CraftEdit.campaign_shelf = PackedStringArray()
	CraftEdit.campaign_templates_locked = false


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if (event as InputEventKey).physical_keycode != KEY_ESCAPE:
		return
	if screen == Screen.WORKSHOP and workshop != null and workshop.mode == WorkshopBuild.Mode.BUILD \
			and workshop.active_tool() == "" and workshop.selected.is_empty() and not workshop.dragging():
		close_workshop()
		show_ladder()
		get_viewport().set_input_as_handled()
	elif screen == Screen.OUTCOME:
		show_ladder()
		get_viewport().set_input_as_handled()


func _set_screen(s: int) -> void:
	screen = s
	ladder_ui.visible = s == Screen.LADDER
	outcome_ui.visible = s == Screen.OUTCOME
	workshop_bar.visible = s == Screen.WORKSHOP
	screen_changed.emit(s)


# ------------------------------------------------------------------ лестница

func show_ladder() -> void:
	_set_screen(Screen.LADDER)
	%Tier.text = tr("%s · регламент: энергия %d") % [CampaignLeague.tier_title(state.tier), CampaignLeague.energy_budget(state.tier)]
	%N0Line.text = tr(String(N0_LINES[mini(state.step, N0_LINES.size() - 1)]))
	var rows: Node = %Rivals
	for c in rows.get_children():
		rows.remove_child(c)
		c.queue_free()
	var ladder := state.ladder()
	for i in ladder.size():
		var r: Dictionary = ladder[i]
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 28)
		var mark := tr("▶ СЛЕДУЮЩИЙ") if i == state.step else (tr("✓ побеждён") if i < state.step else "")
		var tail := ""
		if i < state.step:
			var trophy := _trophy_of_step(i)
			tail = tr(" · трофей: %s") % CampaignLeague.part_title(trophy) if trophy != "" else ""
		var final := tr(" · ФИНАЛ") if bool(r.get("final", false)) else ""
		l.text = "%d.  %s%s   %s%s" % [i + 1, CampaignLeague.rival_title(r), final, mark, tail]
		l.add_theme_color_override("font_color", COL_DONE if i < state.step else (COL_NEXT if i == state.step else COL_LATER))
		rows.add_child(l)
	var trophies: PackedStringArray = []
	for id in state.trophies:
		trophies.append(CampaignLeague.part_title(id))
	%Record.text = tr("Побед: %d · поражений: %d · трофеи: %s") % [state.wins, state.losses,
		", ".join(trophies) if not trophies.is_empty() else tr("пока нет")]
	var errs := CraftEdit.friendly_errors(state.blueprint)
	var msg := ladder_message
	if msg == "" and not errs.is_empty():
		msg = tr("Сборка не готова к бою: %s — открой мастерскую.") % errs[0]
	%Message.text = msg
	%Message.visible = msg != ""
	ladder_message = ""
	var fb: Button = %FightButton
	fb.disabled = state.finished()
	fb.text = tr("ЛИГА ПРОЙДЕНА") if state.finished() else tr("В БОЙ ▶")
	%NewButton.text = tr("НОВАЯ КАМПАНИЯ")
	_new_armed_until = -1.0
	(fb if not fb.disabled else %WorkshopButton as Button).grab_focus()


func _trophy_of_step(i: int) -> String:
	for f in state.fights:
		if bool(f.get("won", false)) and int(f.get("step", -1)) == i:
			return String(f.get("trophy", ""))
	return ""


func _on_new_pressed() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now > _new_armed_until:
		_new_armed_until = now + NEW_CONFIRM_S
		%NewButton.text = tr("ЕЩЁ РАЗ — ПРОГРЕСС СОТРЁТСЯ")
		return
	new_campaign()


func new_campaign(seed_value: int = -1) -> void:
	CampaignState.erase(save_path, bp_name)
	state = CampaignState.new_game(seed_value, bp_name)
	state.save(save_path)
	show_ladder()


# ------------------------------------------------------------------ бой

## Бой с текущим соперником лестницы. false — не начался (лига пройдена или сборка не готова — причина на лестнице).
func start_fight() -> bool:
	close_workshop()
	if state.finished():
		show_ladder()
		return false
	var errs := CraftEdit.friendly_errors(state.blueprint)
	if not errs.is_empty():
		ladder_message = tr("Сборка не готова к бою: %s — открой мастерскую.") % errs[0]
		show_ladder()
		return false
	_free_fight()
	var r := state.current_rival()
	fight = FIGHT_SCENE.instantiate()
	var tier_title := CampaignLeague.tier_title(state.tier)
	fight.call("setup", state.blueprint, CampaignLeague.rival_blueprint(state.tier, r), r, CampaignLeague.rival_title(r), {
		"entrance": entrance_enabled, "player_name": tr("Игрок"), "player_build": state.blueprint.title,
		"player_record": tr("побед %d · поражений %d · трофеев %d") % [state.wins, state.losses, state.trophies.size()],
		"rival_build": tr("%s · уровень %d") % [tier_title, int(r.get("level", 1))],
		"rival_record": tr("ФИНАЛ ЛИГИ") if bool(r.get("final", false)) else tr("соперник %d из %d") % [state.step + 1, state.ladder().size()]})
	fight.connect("fight_finished", finish_fight)
	fight.connect("fight_abandoned", func() -> void:
		_free_fight()
		show_ladder())
	stage.add_child(fight)
	_set_screen(Screen.FIGHT)
	return true


## Итог боя (сигнал сцены боя; проба зовёт напрямую): запись в кампанию, сохранение, экран исхода.
func finish_fight(won: bool, info: Dictionary = {}) -> void:
	last_outcome = info.duplicate()
	last_outcome["won"] = won
	last_trophy = state.record_result(won, info)
	state.save(save_path)
	_free_fight()
	show_outcome()


func _free_fight() -> void:
	if fight != null and is_instance_valid(fight):
		stage.remove_child(fight)
		fight.queue_free()
	fight = null
	Engine.time_scale = 1.0


func show_outcome() -> void:
	_set_screen(Screen.OUTCOME)
	var won := bool(last_outcome.get("won", false))
	var draw := bool(last_outcome.get("draw", false))
	%Headline.text = tr("ПОБЕДА") if won else (tr("НИЧЬЯ") if draw else tr("ПОРАЖЕНИЕ"))
	%Headline.add_theme_color_override("font_color", COL_DONE if won else COL_BAD)
	var lines: PackedStringArray = []
	if won:
		if last_trophy != "":
			lines.append(tr("TROPHY RIGHTS: %s") % CampaignLeague.part_title(last_trophy).to_upper())
			lines.append(tr("Деталь соперника теперь на полке мастерской."))
		else:
			lines.append(tr("Трофея нет: у соперника не нашлось детали, которая может выпасть."))
		if state.finished():
			lines.append(tr("%s пройдена. Продолжение следует.") % CampaignLeague.tier_title(state.tier))
	else:
		lines.append(tr("Бой переигрывается: лестница стоит, штрафа нет."))
	%Detail.text = "\n".join(lines)
	var nb: Button = %OutcomeNext
	nb.visible = not state.finished()
	nb.text = tr("СЛЕДУЮЩИЙ БОЙ ▶") if won else tr("ЕЩЁ РАЗ ▶")
	(nb if nb.visible else %OutcomeLadder as Button).grab_focus()


# ------------------------------------------------------------------ мастерская

func open_workshop() -> void:
	_free_fight()
	if workshop != null:
		return
	state.save(save_path)
	CraftEdit.campaign_shelf = state.shelf_parts()
	CraftEdit.campaign_templates_locked = false   # старт мастерской грузит start_preset — до блокировки шаблонов
	var ws := (load(WORKSHOP_SCENE) as PackedScene).instantiate() as WorkshopBuild
	ws.load_autosave = false
	ws.autosave_name = state.bp_name
	ws.start_preset = CampaignLeague.START_PRESET
	stage.add_child(ws)
	CraftEdit.campaign_templates_locked = true
	ws.load_path(CraftEdit.save_path(state.bp_name))
	if ws.blueprint.weapon == null:
		ws.clear_weapon()   # верстак стартует с молотом-шаблоном — в кампании оружие собирается только из деталей полки
	ws.history.clear()
	ws.redo_stack.clear()
	ws.view_changed.emit(ws.view)   # UI перестраивает левую панель — плитки шаблонов прячутся (campaign_templates_locked)
	workshop = ws
	var r := state.current_rival()
	%BarLabel.text = tr("КАМПАНИЯ%s · трофеев %d\nэнергия %d — тело и оружие (%d/кг) · шаблоны закрыты") % [
		tr(" · следующий: %s") % CampaignLeague.rival_title(r) if not r.is_empty() else "", state.trophies.size(),
		CampaignLeague.energy_budget(state.tier), int(CampaignLeague.weapon_energy_per_kg(state.tier))]
	%BarFight.visible = not state.finished()
	_set_screen(Screen.WORKSHOP)


## Выйти из мастерской: сборка — в кампанию (как есть, даже неготовая: лестница покажет причину), сохранение.
func close_workshop() -> void:
	if workshop == null or not is_instance_valid(workshop):
		workshop = null
		return
	if workshop.mode == WorkshopBuild.Mode.TEST:
		workshop.stop_test()
	state.blueprint = CraftEdit.dup_body(workshop.blueprint)
	state.apply_regulation()
	stage.remove_child(workshop)
	workshop.queue_free()
	workshop = null
	CraftEdit.campaign_shelf = PackedStringArray()
	CraftEdit.campaign_templates_locked = false
	Engine.time_scale = 1.0
	state.save(save_path)
