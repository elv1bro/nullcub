## Площадка «Босс» (docs/plan-demo/BOSS.md; MODES_IDEAS.md В1): купол Old NULL Hall (scenes/arena/null_hall.tscn, поле и чемпион по
## G / K выключены) + двое игроков + босс (scenes/boss/boss_doll.tscn: модульная кукла кита ×2, масса ×3, мозг BossBrain) + BossMatch +
## BossHud + камера.
##   P1 (player_index 0) — человек: WASD летать, Shift ускорение, Space + A/D раскрутка, рука мышью (ArmAssist); p1_bot = true (пробы) —
##     бот BossAllyBrain;
##   P2 (player_index 1) — по умолчанию бот-напарник BossAllyBrain уровня bot_level (K — 1 → 2 → 3); U — отдать человеку на стрелках
##     (правый Ctrl, Enter) или вернуть бота; второй игрок может просто нажать свою клавишу — бот отдаст управление сам;
##   Босс (player_index 2, команда "league", группы dolls + boss).
## «Запас из деталей» (PartHp) на время площадки включён (детали босса отлетают по ❤), при выходе — как было.
## Камера: живые игроки-люди и босс; людей нет — все живые. Клавиши: R — заново, Esc — пауза (Flow), M / N — музыка / толпа,
## H — скин HUD, 1–9 — площадки хаба. Масштаб камеры игрока (DynamicCamera.user_zoom) на время сцены — 1.
class_name BossPlayground
extends Node3D

const DOLL_SCENES := ["res://scenes/doll/doll.tscn", "res://scenes/doll/doll_dark.tscn"]
const BOSS_SCENE := "res://scenes/boss/boss_doll.tscn"
const FOCUS_GROUP := "boss_focus"
const BOT_NAME := "BossAllyBrain"
const BOSS_BRAIN := "BossBrain"
const BOSS_INDEX := 2

@export var bot_level := 2
## Пробы: P1 тоже бот (матч одними ботами).
@export var p1_bot := false
@export var p2_bot := true
## Пробы: без второго игрока (один на один с боссом).
@export var players_n := 2

var arena: Node3D
var boss: Doll
var _zoom_before := 1.0
var _break_modes_before: Array = []

@onready var match_node: BossMatch = $Match
@onready var hud: BossHud = $HUD
@onready var cam: DynamicCamera = $Camera
@onready var dolls_root: Node3D = $Dolls


func _enter_tree() -> void:
	_zoom_before = DynamicCamera.user_zoom
	DynamicCamera.user_zoom = 1.0
	_break_modes_before = [PartHp.on, JointBreak.on]
	PartHp.set_on(true)


func _exit_tree() -> void:
	DynamicCamera.user_zoom = _zoom_before
	if _break_modes_before.size() == 2:
		PartHp.set_on(bool(_break_modes_before[0]))
		JointBreak.set_on(bool(_break_modes_before[1]))


func _ready() -> void:
	BossAllyBrain.default_level = bot_level
	for c in get_children():
		if c is Node3D and c.has_method("spawn_points"):
			arena = c
			break
	if arena != null and "debug_keys" in arena:
		arena.set("debug_keys", false)   # G — смена поля, K — чемпион лиги: у босса своё
	_spawn()
	hud.bind(match_node, self)
	match_node.phase_changed.connect(func(p: int) -> void:
		if p == Match.Phase.COUNTDOWN:
			cam.snap())
	match_node.doll_replaced.connect(_on_doll_replaced)


func _spawn() -> void:
	for i in players_n:
		var human := (i == 0 and not p1_bot) or (i == 1 and not p2_bot)
		var d := make_doll(i, human)
		var sp: Vector2 = Tuning.BOSS_SPAWN[i]
		d.position = Vector3(sp.x, sp.y, 0.0)
		dolls_root.add_child(d)
		attach_children(d, human)
	boss = make_boss()
	var bp: Vector2 = Tuning.BOSS_SPAWN[2]
	boss.position = Vector3(bp.x, bp.y, 0.0)
	dolls_root.add_child(boss)


## Кукла player_index i (P1 — p1, P2 — p2). human — управляет клавиатура, иначе мозг.
static func make_doll(i: int, human: bool) -> Doll:
	var d := (load(String(DOLL_SCENES[i % DOLL_SCENES.size()])) as PackedScene).instantiate() as Doll
	d.name = "P%d" % (i + 1)
	d.player_index = i
	d.input_prefix = "p1" if i == 0 else "p2"
	d.external_input = not human
	d.add_to_group("dolls")
	return d


## Босс: модульная кукла boss_doll.tscn с мозгом BossBrain (команда лиги, группы dolls и boss).
static func make_boss() -> Doll:
	var d := (load(BOSS_SCENE) as PackedScene).instantiate() as Doll
	d.name = "Boss"
	d.player_index = BOSS_INDEX
	d.input_prefix = "bot%d" % BOSS_INDEX
	d.external_input = true
	d.team = LeagueBrain.TEAM
	d.add_to_group("dolls")
	d.add_to_group(BossMatch.BOSS_GROUP)
	var b := BossBrain.new()
	b.name = BOSS_BRAIN
	d.add_child(b)
	return d


## Рука мышью — только у P1-человека; мозг — у ботов-игроков.
static func attach_children(d: Doll, human: bool) -> void:
	if d.is_in_group(BossMatch.BOSS_GROUP):
		return
	if human and d.player_index == 0 and d.get_node_or_null("ArmAssist") == null:
		ArmAssist.attach_to(d)
	if not human and d.get_node_or_null(BOT_NAME) == null:
		var b := BossAllyBrain.new()
		b.name = BOT_NAME
		d.add_child(b)


## Match.respawn_doll переносит узлы-скрипты (мозг, руку); на всякий случай — довесить недостающее.
func _on_doll_replaced(_old: Doll, new_doll: Doll) -> void:
	if new_doll.is_in_group(BossMatch.BOSS_GROUP):
		boss = new_doll
		return
	attach_children(new_doll, not new_doll.external_input)


func doll(index: int) -> Doll:
	for d in match_node.dolls():
		if (d as Doll).player_index == index:
			return d
	return null


## Люди (куклы без мозга), живые и нет.
func humans() -> Array:
	var out: Array = []
	for d in match_node.players():
		if not (d as Doll).external_input:
			out.append(d)
	return out


## За P2 — бот (BossAllyBrain ребёнком куклы) или человек на стрелках. Match.respawn_doll переносит и external_input, и узел мозга.
func set_p2_bot(on: bool) -> void:
	p2_bot = on
	var d := doll(1)
	if d == null:
		return
	var brain := d.get_node_or_null(BOT_NAME)
	if on and brain == null:
		var b := BossAllyBrain.new()
		b.name = BOT_NAME
		d.add_child(b)
	elif not on and brain != null:
		d.remove_child(brain)
		brain.queue_free()
	d.external_input = on
	if not on:
		d.input_vec = Vector2.ZERO
	hud.refresh_hint()


func set_bot_level(lv: int) -> void:
	bot_level = clampi(lv, 1, 3)
	BossAllyBrain.default_level = bot_level
	for d in match_node.players():
		var b := (d as Node).get_node_or_null(BOT_NAME) as BossAllyBrain
		if b != null:
			b.level = bot_level
			b._brain_ready()
	hud.toast(tr("БОТЫ: УРОВЕНЬ %d") % bot_level)


func _physics_process(_delta: float) -> void:
	_tick_focus()


## Кого держит кадр (группа FOCUS_GROUP камеры): живые люди и босс; людей нет — все живые.
func _tick_focus() -> void:
	var want := {}
	var hs: Array = []
	for h in humans():
		if (h as Doll).alive:
			hs.append(h)
	if hs.is_empty():
		for d in match_node.alive_dolls():
			want[d] = true
	else:
		for h in hs:
			want[h] = true
		var b := match_node.boss
		if is_instance_valid(b) and b.alive:
			var bc := b.centre_of_mass()
			for h in hs:
				var hc := (h as Doll).centre_of_mass()
				if Vector2(bc.x, bc.y).distance_to(Vector2(hc.x, hc.y)) < Tuning.BOSS_FOCUS_M:
					want[b] = true
	for n in get_tree().get_nodes_in_group(FOCUS_GROUP):
		if not want.has(n):
			n.remove_from_group(FOCUS_GROUP)
	for n in want.keys():
		if is_instance_valid(n) and not (n as Node).is_in_group(FOCUS_GROUP):
			(n as Node).add_to_group(FOCUS_GROUP)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if p2_bot and players_n >= 2:
		for a in ["p2_left", "p2_right", "p2_up", "p2_down", "p2_dash", "p2_flip"]:
			if InputMap.has_action(a) and event.is_action(a):
				set_p2_bot(false)
				hud.toast(tr("P2: человек"))
				return
	match event.physical_keycode:
		KEY_R:
			match_node.restart()
		KEY_ESCAPE:
			Flow.toggle_pause(match_node.restart)
		KEY_U:
			if players_n >= 2:
				set_p2_bot(not p2_bot)
				hud.toast(tr("P2: бот") if p2_bot else tr("P2: человек"))
		KEY_K:
			set_bot_level(bot_level % 3 + 1)
		KEY_M:
			hud.toast(get_node("/root/GameAudio").toggle_music())
		KEY_N:
			hud.toast(get_node("/root/GameAudio").toggle_crowd())
		KEY_H:
			hud.toast(tr("HUD: ") + HudSkin.cycle())
		_:
			var path: String = preload("res://scenes/playground.gd").scene_for_key(event.physical_keycode)
			if path != "" and path != scene_file_path:
				Loading.change_scene(path, "ПОДКЛЮЧЕНИЕ", path.get_file().get_basename())
