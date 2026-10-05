## Площадка «Стычка 3 на 3» (docs/plan-demo/SQUAD.md; автор 05.10: «карта побольше, стычки 3 на 3 как в шутерах, базовые пулемёты»):
## карта «Полигон» (scenes/arena/proving_ground.tscn) + шесть бойцов + SquadMatch + SquadHud + камера за игроком.
## Бойцы собираются здесь, до регистрации в матче (Match._late_ready — отложенный): чертёж кита + пулемёт kit_active_gun на каждом
## предплечье (правое — канал 1, левое — канал 2): одна рука куклы почти не достаёт целей со своей «чужой» стороны (проба aim), стреляет
## ствол, который смотрит на цель. Тело у обеих команд одно — «Человек» (kit_human), команды различают рубашка, обводка и имена над
## головой цветом команды: с «Черепом» у красных (проба 05.10) красные стреляли вдвое чаще и выигрывали 15:9, а поменяв тела
## местами — уже синие 15:12; на одном теле — 13:15 и 14:15.
##   P1 (player_index 0) — человек: WASD летать, Shift рывок; обе руки всегда смотрят на курсор (SquadArm / SquadArmLeft, цель — курсор
##   через GunAim каждый тик), ЛКМ или I — огонь: жмутся каналы стволов, смотрящих на курсор (ActiveRig.manual, held[] пишет площадка);
##   боты 1–5 — SquadBrain, уровень bot_level (SquadBrain.default_level: мозг после возрождения — новый экземпляр без настроек).
## Клавиши: R — заново, Esc — пауза (Flow), 1–9 — площадки хаба, M / N — музыка / толпа, H — скин HUD, K — уровень ботов 1 → 2 → 3
## (сразу, без перезапуска).
## Пропасти нет; страховочный низ карты (body_fell) — KO, как в бою. Масштаб камеры игрока (DynamicCamera.user_zoom, общий на все
## арены) на время сцены — 1: карта шире купола, на ближнем масштабе соперники всё время за кадром.
class_name SquadPlayground
extends Node3D

const DOLL_SCENE := preload("res://scenes/body/modular_doll.tscn")
const BLUEPRINT := "res://data/body/blueprints/kit_human.tres"
## Стволы: [uid узла, предплечье-родитель, канал]. Предплечья kit_human — "8" (правое), "2" (левое); кисти "9", "3".
const GUNS := [["G", "8", 1], ["F", "2", 2]]
const FOCUS_GROUP := "squad_focus"
const PLAYERS_GROUP := "players"
## Огонь игрока: стреляют стволы, чья ось ближе этого угла к курсору; таких нет — самый близкий (кнопка всегда что-то делает).
const P1_FIRE_CONE_DEG := 25.0

@export var bot_level := 2
## Пробы: P1 тоже бот (бой 3 на 3 одними ботами).
@export var p1_bot := false

var arena: Node3D
## Доводка прицела игрока по стволам (сторона "R" / "L" → GunAim); новая кукла после возрождения — заново.
var p1_aims: Dictionary = {}
var p1_firing := false
var _aim_doll: Doll = null
var _zoom_before := 1.0

@onready var match_node: SquadMatch = $Match
@onready var hud: SquadHud = $HUD
@onready var cam: DynamicCamera = $Camera
@onready var dolls_root: Node3D = $Dolls


func _enter_tree() -> void:
	_zoom_before = DynamicCamera.user_zoom
	DynamicCamera.user_zoom = 1.0
	ActiveBlocks.ensure_input_actions()


func _exit_tree() -> void:
	DynamicCamera.user_zoom = _zoom_before


func _ready() -> void:
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


## Шесть бойцов на точках баз (arena.spawn_points()[player_index]): чётные — синие, нечётные — красные.
func _spawn_squads() -> void:
	var pts: Array = arena.call("spawn_points") if arena != null else []
	for i in 6:
		var human := i == 0 and not p1_bot
		var d := make_fighter(i, human)
		d.position = pts[i] if i < pts.size() else Vector3(-20.0 + 8.0 * i, 1.0, 0.0)
		dolls_root.add_child(d)
		attach_children(d, human)


## Боец player_index i: чертёж команды + пулемёт на каждом предплечье. human — P1 (клавиатура и мышь), иначе бот.
static func make_fighter(i: int, human: bool) -> ModularDoll:
	var bp := (load(BLUEPRINT) as BodyBlueprint).duplicate(true) as BodyBlueprint
	# якорь накладки предплечья занят (у других тел кита — наруч): пулемёт встаёт вместо декора, ветка декора уходит
	var arms := {}
	for g in GUNS:
		arms[String(g[1])] = true
	var drop := {}
	for n in bp.nodes:
		if arms.has(String(n.get("parent", ""))) and String(n.get("anchor", "")) == "Anchor_Deco":
			drop[String(n.get("uid", ""))] = true
	var grew := true
	while grew:
		grew = false
		for n in bp.nodes:
			var u := String(n.get("uid", ""))
			if not drop.has(u) and drop.has(String(n.get("parent", ""))):
				drop[u] = true
				grew = true
	var nodes: Array[Dictionary] = []
	for n in bp.nodes:
		if not drop.has(String(n.get("uid", ""))):
			nodes.append((n as Dictionary).duplicate(true))
	for g in GUNS:
		nodes.append({"uid": String(g[0]), "part": SquadMatch.GUN_PART, "parent": String(g[1]), "anchor": "Anchor_Deco", "channel": int(g[2])})
	bp.nodes = nodes
	bp.energy_budget = maxi(bp.energy_budget, 200)
	bp.id = "squad_%d" % i
	var d := DOLL_SCENE.instantiate() as ModularDoll
	d.blueprint = bp
	d.name = "P1" if human else "Bot%d" % i
	d.player_index = i
	d.input_prefix = "p1" if human else "bot%d" % i
	d.external_input = not human
	d.add_to_group("dolls")
	if human:
		d.add_to_group(PLAYERS_GROUP)
		d.add_to_group(FOCUS_GROUP)
	return d


## Руки раньше мозга: Match.respawn_doll пересоздаёт детей со скриптом в том же порядке — мозг найдёт обе руки. Настройки рук — в их
## _init (SquadArm, SquadArmLeft): копии после возрождения такие же.
static func attach_children(d: Doll, human: bool) -> void:
	var r := SquadArm.new()
	r.name = "ArmAssist"
	d.add_child(r)
	var l := SquadArmLeft.new()
	l.name = "ArmAssistL"
	d.add_child(l)
	if not human:
		var b := SquadBrain.new()
		b.name = "SquadBrain"
		d.add_child(b)


## Кукла игрока; для камеры — и кукла «я» снимков (SquadMatch.focus_index), когда за P1 играет бот.
func human() -> Doll:
	for d in match_node.dolls():
		if not (d as Doll).external_input:
			return d
	return null


func _physics_process(_delta: float) -> void:
	_aim_human()
	_tick_focus()


## Обе руки игрока всегда смотрят на курсор (как прицел в шутере; GunAim доводит ось каждого ствола). ЛКМ или I — огонь: каналы стволов,
## смотрящих на курсор (P1_FIRE_CONE_DEG), а если таких нет — самого близкого.
func _aim_human() -> void:
	var p := human()
	if p == null or not p.alive:
		p1_firing = false
		return
	var rig: Variant = p.get("active_rig")
	if p != _aim_doll:
		_aim_doll = p
		p1_aims.clear()
	var guns := SquadMatch.guns_of(p)
	var arm0 := p.get_node_or_null("ArmAssist") as ArmAssist
	var mp: Variant = arm0.mouse_on_plane() if arm0 != null else null
	if mp is Vector3:
		for g in guns:
			var arm := SquadMatch.arm_for(p, g)
			if arm == null:
				continue
			var side := String(g["side"])
			if not p1_aims.has(side):
				p1_aims[side] = GunAim.new()
			arm.set_target_override((p1_aims[side] as GunAim).point_for(arm, g, mp))
	if not (rig is ActiveRig) or not is_instance_valid(rig):
		return
	var r := rig as ActiveRig
	r.manual = true
	p1_firing = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or (InputMap.has_action("p1_act1") and Input.is_action_pressed("p1_act1"))
	var hold := {}
	if p1_firing and mp is Vector3:
		var best := -1
		var best_err := INF
		for g in guns:
			var e := GunAim.error_to(g, mp)
			if e <= deg_to_rad(P1_FIRE_CONE_DEG):
				hold[int(g["channel"])] = true
			if e < best_err:
				best_err = e
				best = int(g["channel"])
		if hold.is_empty() and best > 0:
			hold[best] = true
	for ch in range(1, ActiveBlocks.CHANNELS + 1):
		r.held[ch - 1] = hold.has(ch)


## Камера: игрок + до двух ближайших соперников в 12 м (иначе на карте 64 м кадр уезжал бы на полный отъезд); игрок выбыл —
## камера держит его обломки до возрождения (кадр не прыгает).
func _tick_focus() -> void:
	var p := match_node.me()
	var want := {}
	if p != null:
		want[p] = true
		if p.alive:
			var near: Array = []
			var c := p.centre_of_mass()
			for d in match_node.team_alive(1 - SquadMatch.team_of(p)):
				var dist := c.distance_to((d as Doll).centre_of_mass())
				if dist < 12.0:
					near.append([dist, d])
			near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
			for k in range(mini(near.size(), 2)):
				want[near[k][1]] = true
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
	match event.physical_keycode:
		KEY_R:
			match_node.restart()
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
			var path: String = preload("res://scenes/playground.gd").scene_for_key(event.physical_keycode)
			if path != "" and path != scene_file_path:
				Loading.change_scene(path, "ПОДКЛЮЧЕНИЕ", path.get_file().get_basename())


## K: уровень ботов 1 → 2 → 3 — живые мозги перечитывают уровень сразу, новые (после возрождения) берут его из default_level.
func set_bot_level(lv: int) -> void:
	bot_level = clampi(lv, 1, 3)
	SquadBrain.default_level = bot_level
	for d in match_node.dolls():
		var b := (d as Node).get_node_or_null("SquadBrain") as SquadBrain
		if b != null:
			b._brain_ready()
	hud.announcer.announce(tr("БОТЫ: УРОВЕНЬ %d") % bot_level, Color(0.9, 0.9, 0.95), "")


func _on_body_fell(body: Node3D) -> void:
	var d := body.get_parent() as Doll
	if d == null or not d.alive or not d.parts.values().has(body):
		return
	d.knock_out()
