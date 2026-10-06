## Площадка «Стычка 3 на 3» (docs/plan-demo/SQUAD.md; автор 05.10: «карта побольше, стычки 3 на 3 как в шутерах»): карта «Полигон»
## (scenes/arena/proving_ground.tscn, ночью — proving_ground_night.tscn) + шесть бойцов + SquadMatch + SquadHud + камера за игроком.
## Бойцы собираются здесь, до регистрации в матче (Match._late_ready — отложенный): «Человек» (kit_human) у обеих команд — вид по
## классу добавляет SquadLook (только меши), цвет команды — рубашка и обводка. Рука с оружием — Tuning.SQUAD_GUN_HAND: со стороны
## соперника на экране (у синих — кисть Hand_L, у красных — Hand_R; кукла смотрит в камеру), она же blueprint.control.
##   P1 (player_index 0) — человек: WASD летать, Shift рывок; рука с оружием всегда тянется к курсору, кольцо — прицел; ЛКМ (или I,
##   X геймпада) — огонь, пока зажата (гаусс — копит заряд, отпустил — выстрел; громила — полёт за оружием к курсору, пока держишь);
##   Q (или Y геймпада) — перезарядка; 1 / 2 / 3 — класс (громила, снайпер, налётчик; на отсчёте — сразу, в бою — с возрождения), а
##   пока ждёт выбор ветки (SquadMatch.branch_pending) — ветка; оружие и усиления открываются сами по опыту (SquadMatch);
##   боты 1–5 — SquadBrain, уровень bot_level (SquadBrain.default_level: мозг после возрождения — новый экземпляр без настроек).
## Клавиши: R — заново, O — настройки, Esc — пауза (Flow), 5–9 — площадки хаба, M / N — музыка / толпа, H — скин HUD, K — уровень
## ботов 1 → 2 → 3.
## Настройки (SquadSettings: режим, до скольких очков, время, боты, суставы, ящики, бонусы) — перед боем: пункт меню ставит
## SquadSettings.ask, и площадка показывает экран SquadSetup (бой не начинается до «В БОЙ»); прямой запуск и пробы начинают сразу.
## Прочность суставов (JointBreak) на время сцены — по настройке (по умолчанию включена), «Запас из деталей» — выключен.
## Камера — DynamicCamera по группе squad_focus; масштаб — класс игрока (снайпер дальше) × бонус «обзор» (min/max_half_height камеры;
## DynamicCamera.user_zoom общий на все арены — на время сцены 1).
class_name SquadPlayground
extends Node3D

const DOLL_SCENE := preload("res://scenes/body/modular_doll.tscn")
const BLUEPRINT := "res://data/body/blueprints/kit_human.tres"
const SCENE_DAY := "res://scenes/playground_squad.tscn"
const SCENE_NIGHT := "res://scenes/playground_squad_night.tscn"
const FOCUS_GROUP := "squad_focus"
const PLAYERS_GROUP := "players"
## Камера: игрок и ближайший соперник ближе этого (м, × зум) — в кадре вместе; дальше — только игрок (стрелка у края экрана).
const FOCUS_ENEMY_M := 10.0
const CAM_MIN_H := 5.5
const CAM_MAX_H := 9.0
const NUM_KEYS := [KEY_1, KEY_2, KEY_3]   # класс по порядку Tuning.SQUAD_CLASS_ORDER, или ветка по branch_order, пока ждёт выбор

@export var bot_level := 2
## Пробы: P1 тоже бот (бой 3 на 3 одними ботами).
@export var p1_bot := false
## Брать настройки из SquadSettings (пробы ставят false и настраивают матч сами).
@export var use_settings := true

var arena: Node3D
var setup: SquadSetup = null
var _zoom_before := 1.0
var _joints_before := false
var _parthp_before := false
var _was_lmb := false
var _view := 1.0

@onready var match_node: SquadMatch = $Match
@onready var hud: SquadHud = $HUD
@onready var cam: DynamicCamera = $Camera
@onready var dolls_root: Node3D = $Dolls


func _enter_tree() -> void:
	_zoom_before = DynamicCamera.user_zoom
	DynamicCamera.user_zoom = 1.0
	_joints_before = JointBreak.on
	_parthp_before = PartHp.on
	PartHp.set_on(false)
	JointBreak.set_on(SquadSettings.joints if use_settings else Tuning.SQUAD_JOINTS_DEFAULT)
	ActiveBlocks.ensure_input_actions()   # экшены pN_act1…3 (огонь — act1, перезарядка — act2)


func _exit_tree() -> void:
	DynamicCamera.user_zoom = _zoom_before
	JointBreak.set_on(_joints_before)
	PartHp.set_on(_parthp_before)


func _ready() -> void:
	if use_settings:
		_apply_settings()
	SquadBrain.default_level = bot_level
	for c in get_children():
		if c is Node3D and c.has_method("spawn_points"):
			arena = c
			break
	if arena != null and arena.has_signal("body_fell"):
		arena.connect("body_fell", _on_body_fell)
	_spawn_squads()
	hud.bind(match_node)
	match_node.phase_changed.connect(func(p: int) -> void:
		if p == Match.Phase.COUNTDOWN:
			cam.snap())
	if use_settings and SquadSettings.ask:
		SquadSettings.ask = false
		match_node.autostart = false   # бой — после «В БОЙ» на экране настроек
		open_setup()


## Настройки → матч: режим, до скольких очков, время, ящики и бонусы, уровень ботов.
func _apply_settings() -> void:
	match_node.mode = SquadSettings.mode
	match_node.score_to_win = SquadSettings.goal()
	match_node.time_limit_s = float(SquadSettings.time_min) * 60.0
	match_node.hard_timeout_s = match_node.time_limit_s
	match_node.supplies = SquadSettings.supplies
	match_node.boosts = SquadSettings.boosts
	bot_level = SquadSettings.bot_level
	JointBreak.set_on(SquadSettings.joints)


## Экран настроек поверх площадки (O, пункт меню).
func open_setup() -> void:
	if setup != null and is_instance_valid(setup):
		return
	setup = SquadSetup.new()
	setup.name = "Setup"
	setup.started.connect(_on_setup_started)
	setup.cancelled.connect(func() -> void: Flow.to_menu())
	add_child(setup)
	hud.visible = false


## «В БОЙ»: другая карта (день / ночь) — сцена заново, сразу в бой; та же — настройки в матч и отсчёт.
func _on_setup_started() -> void:
	var want := SCENE_NIGHT if SquadSettings.night else SCENE_DAY
	if scene_file_path != "" and want != scene_file_path:
		Loading.change_scene(want, "ПОДКЛЮЧЕНИЕ", want.get_file().get_basename())
		return
	_apply_settings()
	SquadBrain.default_level = bot_level
	set_bot_level(bot_level, false)
	if setup != null:
		setup.queue_free()
		setup = null
	hud.visible = true
	hud.bind(match_node)
	var p := human()
	if p != null:
		match_node.set_class(p.player_index, SquadSettings.player_class)
	match_node.begin()


## Шесть бойцов на точках баз (arena.spawn_points()[player_index]): чётные — синие, нечётные — красные.
func _spawn_squads() -> void:
	var pts: Array = arena.call("spawn_points") if arena != null else []
	for i in 6:
		var human_ := i == 0 and not p1_bot
		var d := make_fighter(i, human_)
		d.position = pts[i] if i < pts.size() else Vector3(-20.0 + 8.0 * i, 1.0, 0.0)
		dolls_root.add_child(d)
		attach_children(d, human_)
	if use_settings and not p1_bot:
		match_node.loadout(0)["class"] = SquadSettings.player_class
		match_node.loadout(0)["next_class"] = SquadSettings.player_class


## Боец player_index i: «Человек», рукой управления — кисть с оружием своей команды. human — P1 (клавиатура и мышь), иначе бот.
static func make_fighter(i: int, human_: bool) -> ModularDoll:
	var bp := (load(BLUEPRINT) as BodyBlueprint).duplicate(true) as BodyBlueprint
	bp.control = PackedStringArray([String(Tuning.SQUAD_GUN_HAND[i % 2])])
	bp.control_rmb = PackedStringArray()
	bp.id = "squad_%d" % i
	var d := DOLL_SCENE.instantiate() as ModularDoll
	d.blueprint = bp
	d.name = "P1" if human_ else "Bot%d" % i
	d.player_index = i
	d.input_prefix = "p1" if human_ else "bot%d" % i
	d.external_input = not human_
	d.add_to_group("dolls")
	if human_:
		d.add_to_group(PLAYERS_GROUP)
		d.add_to_group(FOCUS_GROUP)
	return d


## Рука, ствол, рукопашное оружие, мозг — в этом порядке: Match.respawn_doll пересоздаёт детей со скриптом в том же порядке, а
## настройки у них — в _init и из матча (класс и уровень), не из экспортов. Ствол и рукопашное есть у всех — работает то, что даёт класс.
static func attach_children(d: Doll, human_: bool) -> void:
	var r := SquadArm.new()
	r.name = "ArmAssist"
	d.add_child(r)
	var g := SquadGun.new()
	g.name = "SquadGun"
	d.add_child(g)
	var m := SquadMelee.new()
	m.name = "SquadMelee"
	d.add_child(m)
	if not human_:
		var b := SquadBrain.new()
		b.name = "SquadBrain"
		d.add_child(b)


## Кукла игрока (человек) или null.
func human() -> Doll:
	for d in match_node.dolls():
		if not (d as Doll).external_input:
			return d
	return null


func _physics_process(delta: float) -> void:
	_human_gun()
	_tick_focus(delta)


## Игрок: рука с оружием всегда тянется к курсору (цель руки — курсор каждый тик; без мыши — правый стик, как в бою), ствол смотрит
## по руке; огонь — ЛКМ или активная клавиша 1 (I / X геймпада), пока зажата (гаусс — заряд, отпустил — выстрел); громила — полёт:
## нажал — старт к курсору, держишь — летит за курсором, отпустил — конец; перезарядка — Q или активная клавиша 2 (Y геймпада).
func _human_gun() -> void:
	var p := human()
	if p == null or (setup != null and is_instance_valid(setup)):
		return
	var g := SquadMatch.gun_of(p)
	if g == null:
		return
	var a := g.arm()
	var mp: Variant = null
	if a != null and p.alive:
		mp = a.mouse_on_plane() if DisplayServer.mouse_get_mode() != DisplayServer.MOUSE_MODE_HIDDEN else null
		if mp is Vector3:
			a.set_target_override(mp)
		else:
			a.clear_target_override()
	var pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
		or (InputMap.has_action("p1_act1") and Input.is_action_pressed("p1_act1"))
	g.trigger = pressed
	var ml := SquadMatch.melee_of(p)
	if ml != null and ml.weapon_id != "":
		var at: Vector3 = mp if mp is Vector3 else p.centre_of_mass() + Vector3(1.0 if SquadMatch.team_of(p) == 0 else -1.0, 0.0, 0.0)
		if pressed and not _was_lmb:
			ml.start_dash(at)
		elif pressed and ml.dashing:
			ml.steer_dash(at)
		elif not pressed and ml.dashing:
			ml.end_dash()
	_was_lmb = pressed
	if Input.is_physical_key_pressed(KEY_Q) or (InputMap.has_action("p1_act2") and Input.is_action_pressed("p1_act2")):
		if g.mag < g.mag_max:
			g.reload()


## Камера: игрок + ближайший соперник ближе FOCUS_ENEMY_M × зум (иначе на карте 64 м кадр всё время ездил бы туда-сюда); игрок
## выбыл — камера держит его обломки до возрождения. Зум (класс × бонус «обзор») плавно меняет пределы высоты кадра камеры.
func _tick_focus(delta: float) -> void:
	var p := match_node.me()
	var want := {}
	var z := match_node.view_zoom(p) if p != null else 1.0
	_view = move_toward(_view, z, delta * 0.8)
	cam.min_half_height = CAM_MIN_H * _view
	cam.max_half_height = CAM_MAX_H * _view
	if p != null:
		want[p] = true
		if p.alive:
			var best: Doll = null
			var best_d := FOCUS_ENEMY_M * _view
			var c := p.centre_of_mass()
			for d in match_node.team_alive(1 - SquadMatch.team_of(p)):
				var dist := c.distance_to((d as Doll).centre_of_mass())
				if dist < best_d:
					best_d = dist
					best = d
			if best != null:
				want[best] = true
	else:
		for d in match_node.alive_dolls():
			want[d] = true
	for n in get_tree().get_nodes_in_group(FOCUS_GROUP):
		if not want.has(n):
			n.remove_from_group(FOCUS_GROUP)
	for n in want.keys():
		if is_instance_valid(n) and not (n as Node).is_in_group(FOCUS_GROUP):
			(n as Node).add_to_group(FOCUS_GROUP)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if setup != null and is_instance_valid(setup):
		return   # экран настроек ловит клавиши сам
	var k: int = event.physical_keycode
	if NUM_KEYS.has(k):
		var p := human()
		if p != null:
			_number(p, NUM_KEYS.find(k))
			get_viewport().set_input_as_handled()
		return
	match k:
		KEY_R:
			match_node.restart()
		KEY_O:
			open_setup()
		KEY_ESCAPE:
			Flow.toggle_pause(match_node.restart)
		KEY_M:
			hud.announcer.announce(get_node("/root/GameAudio").toggle_music(), Color(0.9, 0.9, 0.95), "")
		KEY_N:
			hud.announcer.announce(get_node("/root/GameAudio").toggle_crowd(), Color(0.9, 0.9, 0.95), "")
		KEY_H:
			hud.announcer.announce(tr("HUD: ") + HudSkin.cycle(), Color(0.9, 0.9, 0.95), "")
		KEY_K:
			set_bot_level(bot_level % 3 + 1)
		_:
			var path: String = preload("res://scenes/playground.gd").scene_for_key(k)
			if path != "" and path != scene_file_path:
				Loading.change_scene(path, "ПОДКЛЮЧЕНИЕ", path.get_file().get_basename())


## Цифра n (0..2): ждёт выбор ветки — ветка по порядку класса; иначе — класс по порядку Tuning.SQUAD_CLASS_ORDER.
func _number(p: Doll, n: int) -> void:
	var pi := p.player_index
	if match_node.branch_left(pi) >= 0.0:
		var lo := match_node.loadout(pi)
		var order: Array = (Tuning.SQUAD_CLASSES[String(lo["class"])] as Dictionary).get("branch_order", [])
		if n < order.size():
			match_node.choose_branch(pi, String(order[n]))
		return
	if n < Tuning.SQUAD_CLASS_ORDER.size():
		match_node.set_class(pi, String(Tuning.SQUAD_CLASS_ORDER[n]))


## K: уровень ботов 1 → 2 → 3 — живые мозги перечитывают уровень сразу, новые (после возрождения) берут его из default_level.
func set_bot_level(lv: int, say := true) -> void:
	bot_level = clampi(lv, 1, 3)
	SquadBrain.default_level = bot_level
	if use_settings:
		SquadSettings.bot_level = bot_level
	for d in match_node.dolls():
		var b := (d as Node).get_node_or_null("SquadBrain") as SquadBrain
		if b != null:
			b._brain_ready()
	if say:
		hud.announcer.announce(tr("БОТЫ: УРОВЕНЬ %d") % bot_level, Color(0.9, 0.9, 0.95), "")


func _on_body_fell(body: Node3D) -> void:
	var d := body.get_parent() as Doll
	if d == null or not d.alive or not d.parts.values().has(body):
		return
	d.knock_out()
