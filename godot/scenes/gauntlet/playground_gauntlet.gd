## Испытание (Gauntlet, docs/plan-demo/GAUNTLET.md; MODES_IDEAS В3) — поток экранов как у кампании (campaign_flow.gd): старт →
## бой (Stage — сцена gauntlet_fight.tscn, сцена дерева не меняется) → антракт (итог боя, следующий соперник с портретом, одна
## бесплатная починка) → бой … → итог забега «пройдено N из 10» (рекорд — GauntletRun.save_path, user://gauntlet.cfg).
## Состояние забега — GauntletRun (чистая логика). Весь забег включён «Запас из деталей» (PartHp): детали — это и запас, и то, что
## не чинится; на выходе — прежние PartHp / JointBreak.
## Сборка игрока — автосейв мастерской (если цел), иначе кит «Человек»; кнопка на старте переключает.
## Esc: в бою — пауза Flow (ЗАНОВО — сдаться и начать забег сначала), на экранах — пауза без ЗАНОВО.
## Пробы (tests/gauntlet_probe.gd): autopilot — за игрока бот и антракт сам (крупнейшая починка → следующий бой); fight_time_limit_s,
## result_delay_s — короче бой и итоги; start_run(), start_fight(), finish_fight(won, info), apply_repair(i), give_up() — шаги кнопок.
class_name GauntletPlayground
extends Node

enum Screen { START, FIGHT, BREAK, RESULT }

signal screen_changed(screen: int)
## Сцена боя создана и настроена, ещё не в дереве (пробы правят Match: отсчёт, feel).
signal fight_created(fight: Node)

const FIGHT_SCENE := preload("res://scenes/gauntlet/gauntlet_fight.tscn")
const EXIT_SCENE := "res://scenes/menu/garage_menu.tscn"
const COL_DONE := Color(0.55, 0.9, 0.5)
const COL_NEXT := Color(1.0, 0.82, 0.3)
const COL_LATER := Color(0.75, 0.75, 0.78)
const COL_BAD := Color(1.0, 0.45, 0.35)
const COL_TITLE := Color(1, 0.93, 0.8)
const COL_SUB := Color(0.8, 0.85, 0.95)
const COL_N0 := Color(0.45, 0.9, 1)
const COL_BG := Color(0.05, 0.06, 0.08, 1)
const PORTRAIT_SIZE := Vector2(200, 300)

@export var autopilot := false
@export var fight_time_limit_s := -1.0
@export var result_delay_s: float = Tuning.GAUNTLET_RESULT_DELAY_S

var run: GauntletRun = null
var screen := Screen.START
var fight: Node = null
var use_workshop := true
var player_bp: BodyBlueprint
var record: Dictionary = {}
var fights_started := 0
var portraits: DollPortrait
var _portrait_key := ""
var _modes_before: Array = []

@onready var stage: Node = $Stage
@onready var ui: CanvasLayer = $UI

# экраны (строятся в _build_ui)
var start_ui: Control
var break_ui: Control
var result_ui: Control
var _start_ladder: VBoxContainer
var _start_record: Label
var _start_build: Label
var _start_button: Button
var _build_button: Button
var _break_headline: Label
var _break_detail: Label
var _break_body: Label
var _break_repairs: VBoxContainer
var _break_repair_note: Label
var _break_next: Button
var _rival_name: Label
var _rival_stats: Label
var _rival_tex: TextureRect
var _rival_placeholder: Label
var _result_headline: Label
var _result_detail: Label
var _result_again: Button


func _enter_tree() -> void:
	_modes_before = [PartHp.on, JointBreak.on]
	PartHp.set_on(true)


func _exit_tree() -> void:
	if run != null and not run.over and fights_started > 0:
		run.over = true
		run.save_record()   # ушёл посреди забега — забег засчитан с тем, что пройдено
	Engine.time_scale = 1.0
	if _modes_before.size() == 2:
		PartHp.set_on(bool(_modes_before[0]))
		JointBreak.on = bool(_modes_before[1])


func _ready() -> void:
	portraits = DollPortrait.new()
	portraits.name = "Portraits"
	add_child(portraits)
	portraits.portrait_ready.connect(_on_portrait)
	_build_ui()
	record = GauntletRun.load_record()
	_pick_build()
	show_start()


func _input(event: InputEvent) -> void:
	if screen == Screen.FIGHT or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		Flow.toggle_pause()


func _set_screen(s: int) -> void:
	screen = s
	start_ui.visible = s == Screen.START
	break_ui.visible = s == Screen.BREAK
	result_ui.visible = s == Screen.RESULT
	screen_changed.emit(s)


# ------------------------------------------------------------------ сборка игрока

## Автосейв мастерской без структурных ошибок (null — нет или сломан).
static func workshop_blueprint() -> BodyBlueprint:
	var bp := CraftEdit.load_saved(CraftEdit.save_path(CraftEdit.AUTOSAVE))
	if bp != null and not bp.nodes.is_empty() and CraftEdit.structural_errors(bp).is_empty():
		return bp
	return null


## Сборка игрока: мастерская (если цела) или кит «Человек».
static func player_blueprint(workshop: bool) -> BodyBlueprint:
	var bp := workshop_blueprint() if workshop else null
	return bp if bp != null else CampaignLeague.preset(CampaignLeague.START_PRESET)


func _pick_build() -> void:
	if use_workshop and workshop_blueprint() == null:
		use_workshop = false   # автосейва нет или он сломан
	player_bp = player_blueprint(use_workshop)


func toggle_build() -> void:
	use_workshop = not use_workshop
	_pick_build()
	show_start()


# ------------------------------------------------------------------ поток

func show_start() -> void:
	_set_screen(Screen.START)
	for c in _start_ladder.get_children():
		_start_ladder.remove_child(c)
		c.queue_free()
	var best := int(record.get("best", 0))
	for i in GauntletRun.fights():
		var r := GauntletRun.rival(i)
		var l := _label(_start_ladder, 24, COL_DONE if i < best else (COL_NEXT if i == best else COL_LATER))
		l.text = tr("%d.  %s · уровень %d · %s") % [i + 1, GauntletRun.rival_title(i), int(r.get("level", 1)), GauntletRun.arena_title(i)]
	_start_record.text = tr("Рекорд: пройдено %d из %d · забегов %d · полных проходов %d") % [best, GauntletRun.fights(),
		int(record.get("runs", 0)), int(record.get("wins", 0))]
	var title := player_bp.title if player_bp != null else "?"
	_start_build.text = tr("Твоя сборка: %s · запас %d ❤") % [title, player_bp.parts_hp_total() if player_bp != null else 0]
	_build_button.text = tr("СБОРКА: МАСТЕРСКАЯ") if use_workshop else tr("СБОРКА: КИТ")
	_start_button.grab_focus()


## Новый забег с первого боя.
func start_run() -> void:
	if Flow.is_paused():
		Flow.close_pause()
	_free_fight()
	if run != null and not run.over and fights_started > 0:
		run.over = true
		run.save_record()
		record = GauntletRun.load_record()
	run = GauntletRun.new()
	run.best_before = int(record.get("best", 0))
	fights_started = 0
	start_fight()


## Следующий бой забега. Починку, которую не взяли, не копим.
func start_fight() -> bool:
	if run == null or run.over or player_bp == null:
		return false
	_free_fight()
	run.repair_used = true
	fight = FIGHT_SCENE.instantiate()
	fight.set("time_limit_s", fight_time_limit_s)
	fight.set("result_delay_s", result_delay_s)
	fight.call("setup_gauntlet", player_bp, run, run.step, autopilot)
	fight.connect("fight_finished", finish_fight)
	fight.connect("fight_abandoned", give_up)
	fight_created.emit(fight)
	stage.add_child(fight)
	fights_started += 1
	_set_screen(Screen.FIGHT)
	return true


## Итог боя (сигнал сцены боя; проба зовёт напрямую): запись в забег, антракт или итог забега.
func finish_fight(won: bool, info: Dictionary = {}) -> void:
	if run == null or run.over:
		return
	var snap: Dictionary = info.get("snapshot", {})
	if snap.is_empty() and fight != null and is_instance_valid(fight):
		var d := fight.get_node_or_null("P1") as Doll
		if is_instance_valid(d):
			snap = GauntletRun.snapshot(d)
	run.record_result(won, info, snap)
	_free_fight()
	if run.over:
		record = GauntletRun.load_record()
		show_result()
	else:
		show_break()


## Сдаться («ЗАНОВО» в паузе боя): забег кончается поражением, новый — с первого боя.
func give_up() -> void:
	if run != null and not run.over:
		run.record_result(false, {"reason": "give_up"}, {})
		record = GauntletRun.load_record()
	_free_fight()
	start_run()


func _free_fight() -> void:
	if fight != null and is_instance_valid(fight):
		stage.remove_child(fight)
		fight.queue_free()
	fight = null
	Engine.time_scale = 1.0


func exit_to_garage() -> void:
	var flow := get_node_or_null("/root/Flow")
	if flow != null:
		flow.to_menu()
	else:
		Loading.change_scene(EXIT_SCENE, "БОКС 07", "возвращаемся в гараж…")


# ------------------------------------------------------------------ антракт

func show_break() -> void:
	_set_screen(Screen.BREAK)
	var last := run.last
	_break_headline.text = tr("ПОБЕДА · бой %d из %d") % [run.cleared, GauntletRun.fights()]
	_break_headline.add_theme_color_override("font_color", COL_DONE)
	var lines: PackedStringArray = []
	lines.append(tr("%s побеждён за %d с · осталось %d из %d ❤") % [GauntletRun.rival_title(run.step - 1),
		int(roundf(float(last.get("duration_s", 0.0)))), int(roundf(float(last.get("hp", 0.0)))), int(roundf(float(last.get("max_hp", 0.0))))])
	var now: PackedStringArray = []
	for n in PackedStringArray(last.get("lost_now", [])):
		now.append(run.title_of(n))
	lines.append(tr("Оторвано в этом бою: %s") % (", ".join(now) if not now.is_empty() else tr("ничего")))
	_break_detail.text = "\n".join(lines)
	_fill_body()
	_fill_repairs()
	_fill_rival()
	_break_next.text = tr("БОЙ %d ▶") % (run.step + 1)
	_break_next.grab_focus()
	if autopilot:
		_autopilot_break.call_deferred()


func _fill_body() -> void:
	var pool := run.fight_pool()
	var lost: PackedStringArray = []
	for n in run.lost_roots():
		lost.append(run.title_of(n))
	_break_body.text = tr("Запас на старт боя: %d из %d ❤\nНе хватает: %s") % [int(roundf(run.start_hp(pool))), int(roundf(pool)),
		", ".join(lost) if not lost.is_empty() else tr("ничего")]


func _fill_repairs() -> void:
	for c in _break_repairs.get_children():
		_break_repairs.remove_child(c)
		c.queue_free()
	var opts := run.repair_options()
	for i in opts.size():
		var o: Dictionary = opts[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(620, 46)
		b.add_theme_font_size_override("font_size", 22)
		if String(o["kind"]) == "branch":
			b.text = tr("Вернуть: %s · +%d ❤") % [String(o["title"]), int(roundf(float(o["hp"])))]
		else:
			b.text = tr("Подлатать корпус · +%d ❤, износ суставов снят") % int(roundf(float(o["hp"])))
		b.disabled = run.repair_used
		b.pressed.connect(apply_repair.bind(i))
		_break_repairs.add_child(b)
	_break_repair_note.text = tr("Починено: %s. Больше чинить нельзя.") % run.repaired if run.repair_used and run.repaired != "" \
		else tr("Одна бесплатная починка до следующего боя.")


func _fill_rival() -> void:
	var i := run.step
	var r := GauntletRun.rival(i)
	var bp := GauntletRun.rival_blueprint(i)
	_rival_name.text = tr("Соперник %d из %d: %s") % [i + 1, GauntletRun.fights(), GauntletRun.rival_title(i)]
	_rival_stats.text = tr("Уровень %d · тяга ×%.2f · запас %d ❤\nАрена: %s") % [int(r.get("level", 1)), float(r.get("thrust", 1.0)),
		int(GauntletRun.rival_max_hp(i)), GauntletRun.arena_title(i)]
	_portrait_key = "gauntlet:%s:%d" % [String(r.get("preset", "")), bp.nodes.size() if bp != null else 0]
	var tex := portraits.request(_portrait_key, bp) if bp != null else null
	_rival_tex.texture = tex
	_rival_placeholder.visible = tex == null


func _on_portrait(key: String, tex: Texture2D) -> void:
	if key == _portrait_key and is_instance_valid(_rival_tex):
		_rival_tex.texture = tex
		_rival_placeholder.visible = tex == null


## Починка i из GauntletRun.repair_options() (кнопка). Ровно одна за антракт.
func apply_repair(i: int) -> bool:
	if run == null or screen != Screen.BREAK:
		return false
	var ok := run.apply_repair(i)
	if ok:
		_fill_body()
		_fill_repairs()
		_break_next.grab_focus()
	return ok


## Автопилот антракта: крупнейшая починка (первая в списке), потом следующий бой.
func _autopilot_break() -> void:
	if screen != Screen.BREAK or run == null:
		return
	apply_repair(0)
	start_fight()


# ------------------------------------------------------------------ итог забега

func show_result() -> void:
	_set_screen(Screen.RESULT)
	_result_headline.text = tr("ИСПЫТАНИЕ ПРОЙДЕНО") if run.won_all else tr("КОНЕЦ ЗАБЕГА")
	_result_headline.add_theme_color_override("font_color", COL_DONE if run.won_all else COL_BAD)
	var lines: PackedStringArray = [tr("Пройдено %d из %d") % [run.cleared, GauntletRun.fights()]]
	if not run.won_all:
		var reason := String(run.last.get("reason", ""))
		if reason == "give_up":
			lines.append(tr("Сдался в бою %d.") % (run.step + 1))
		elif bool(run.last.get("draw", false)):
			lines.append(tr("Ничья в бою %d с %s — ничья в Испытании не проходит.") % [run.step + 1, GauntletRun.rival_title(run.step)])
		else:
			lines.append(tr("Остановил: %s (бой %d).") % [GauntletRun.rival_title(run.step), run.step + 1])
	if run.cleared > run.best_before:
		lines.append(tr("Новый рекорд!"))
	else:
		lines.append(tr("Рекорд: %d из %d") % [int(record.get("best", 0)), GauntletRun.fights()])
	_result_detail.text = "\n".join(lines)
	_result_again.grab_focus()


# ------------------------------------------------------------------ экраны (стиль кампании: campaign.tscn)

func _build_ui() -> void:
	# старт
	start_ui = _screen("Start")
	var box := _box(start_ui, 600, 470)
	_label(box, 60, COL_TITLE, tr("ИСПЫТАНИЕ"))
	_label(box, 26, COL_SUB, tr("10 боёв подряд против бойцов лиги. Каждый следующий сильнее. Детали между боями не чинятся — одна бесплатная починка в антракте. Поражение — конец забега."), true)
	_start_ladder = VBoxContainer.new()
	_start_ladder.add_theme_constant_override("separation", 4)
	box.add_child(_start_ladder)
	_start_record = _label(box, 24, Color(0.9, 0.9, 0.9), "", true)
	_start_build = _label(box, 24, COL_N0, "", true)
	var row := _row(box)
	_start_button = _button(row, tr("НАЧАТЬ ▶"), 250)
	_start_button.pressed.connect(start_run)
	_build_button = _button(row, tr("СБОРКА: МАСТЕРСКАЯ"), 330)
	_build_button.pressed.connect(toggle_build)
	_button(row, tr("ВЫХОД"), 180).pressed.connect(exit_to_garage)

	# антракт
	break_ui = _screen("Break")
	box = _box(break_ui, 760, 470)
	_break_headline = _label(box, 64, COL_DONE)
	_break_detail = _label(box, 26, COL_TITLE, "", true)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(cols)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(640, 0)
	left.add_theme_constant_override("separation", 10)
	cols.add_child(left)
	_label(left, 28, COL_SUB, tr("ТВОЯ СБОРКА"))
	_break_body = _label(left, 22, Color(0.9, 0.9, 0.9), "", true)
	_break_repair_note = _label(left, 22, COL_NEXT, "", true)
	_break_repairs = VBoxContainer.new()
	_break_repairs.add_theme_constant_override("separation", 6)
	left.add_child(_break_repairs)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(420, 0)
	right.add_theme_constant_override("separation", 10)
	cols.add_child(right)
	_label(right, 28, COL_SUB, tr("СЛЕДУЮЩИЙ СОПЕРНИК"))
	var frame := Panel.new()
	frame.custom_minimum_size = PORTRAIT_SIZE
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	right.add_child(frame)
	_rival_tex = TextureRect.new()
	_rival_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rival_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rival_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.add_child(_rival_tex)
	_rival_placeholder = Label.new()
	_rival_placeholder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rival_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rival_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rival_placeholder.add_theme_font_size_override("font_size", 120)
	_rival_placeholder.add_theme_color_override("font_color", Color(0.75, 0.75, 0.78, 0.5))
	_rival_placeholder.text = "?"
	frame.add_child(_rival_placeholder)
	_rival_name = _label(right, 26, COL_NEXT, "", true)
	_rival_stats = _label(right, 22, Color(0.9, 0.9, 0.9), "", true)
	row = _row(box)
	_break_next = _button(row, tr("БОЙ ▶"), 250)
	_break_next.pressed.connect(func() -> void: start_fight())
	_button(row, tr("СДАТЬСЯ"), 250).pressed.connect(give_up_to_result)

	# итог забега
	result_ui = _screen("Result")
	box = _box(result_ui, 600, 280)
	_result_headline = _label(box, 96, COL_BAD)
	_result_detail = _label(box, 34, COL_TITLE, "", true)
	row = _row(box)
	_result_again = _button(row, tr("ЕЩЁ РАЗ ▶"), 250)
	_result_again.pressed.connect(start_run)
	_button(row, tr("К ЛЕСТНИЦЕ"), 250).pressed.connect(show_start)
	_button(row, tr("ВЫХОД"), 180).pressed.connect(exit_to_garage)


## «СДАТЬСЯ» в антракте: забег кончается, экран итога.
func give_up_to_result() -> void:
	if run == null or run.over:
		return
	run.record_result(false, {"reason": "give_up"}, {})
	record = GauntletRun.load_record()
	show_result()


func _screen(n: String) -> Control:
	var c := Control.new()
	c.name = n
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.visible = false
	ui.add_child(c)
	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = COL_BG
	c.add_child(bg)
	return c


func _box(parent: Control, half_w: float, half_h: float) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.name = "Box"
	b.set_anchors_preset(Control.PRESET_CENTER)
	b.offset_left = -half_w
	b.offset_right = half_w
	b.offset_top = -half_h
	b.offset_bottom = half_h
	b.grow_horizontal = Control.GROW_DIRECTION_BOTH
	b.grow_vertical = Control.GROW_DIRECTION_BOTH
	b.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_theme_constant_override("separation", 18)
	parent.add_child(b)
	return b


func _row(parent: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 18)
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(r)
	return r


func _label(parent: Control, size: int, color: Color, text := "", wrap := false) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = text
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, w: float) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(w, 64)
	b.add_theme_font_size_override("font_size", 26)
	b.text = text
	parent.add_child(b)
	return b
