## Площадка «Стычка 3 на 3» (docs/plan-demo/SQUAD.md; автор 05.10: «карта побольше, стычки 3 на 3 как в шутерах»; второй заход
## 05.10: пистолет у всех и ветка развития, патроны и перезарядка, ящики, одна рука, «слишком трясётся»): карта «Полигон»
## (scenes/arena/proving_ground.tscn) + шесть бойцов + SquadMatch + SquadHud + камера за игроком.
## Бойцы собираются здесь, до регистрации в матче (Match._late_ready — отложенный): «Человек» (kit_human) у обеих команд — команды
## различают рубашка, обводка и имена цветом команды. Рука с оружием — Tuning.SQUAD_GUN_HAND: со стороны соперника на экране (у синих
## — кисть Hand_L, у красных — Hand_R; кукла смотрит в камеру), она же blueprint.control.
##   P1 (player_index 0) — человек: WASD летать, Shift рывок; рука с оружием всегда тянется к курсору (автор 05.10: «рука всегда за
##   мышкой, без ЛКМ, а огонь на ЛКМ»), кольцо тяги — прицел; ЛКМ (или I, X геймпада) — огонь, пока зажата; Q (или Y геймпада) —
##   перезарядка, пустой магазин перезаряжается сам; 1 / 2 / 3 — взять улучшение (SquadHud показывает, какие есть и хватает ли очков);
##   боты 1–5 — SquadBrain, уровень bot_level (SquadBrain.default_level: мозг после возрождения — новый экземпляр без настроек).
## Клавиши: R — заново, Esc — пауза (Flow), 4–9 — площадки хаба, M / N — музыка / толпа, H — скин HUD, K — уровень ботов 1 → 2 → 3.
## Пропасти нет; страховочный низ карты (body_fell) — KO, как в бою. Масштаб камеры игрока (DynamicCamera.user_zoom, общий на все
## арены) на время сцены — 1: карта шире купола, на ближнем масштабе соперники всё время за кадром.
class_name SquadPlayground
extends Node3D

const DOLL_SCENE := preload("res://scenes/body/modular_doll.tscn")
const BLUEPRINT := "res://data/body/blueprints/kit_human.tres"
const FOCUS_GROUP := "squad_focus"
const PLAYERS_GROUP := "players"
## Камера: игрок и ближайший соперник ближе этого (м) — в кадре вместе; дальше — только игрок (стрелка у края экрана).
const FOCUS_ENEMY_M := 10.0
const UPGRADE_KEYS := [KEY_1, KEY_2, KEY_3]

@export var bot_level := 2
## Пробы: P1 тоже бот (бой 3 на 3 одними ботами).
@export var p1_bot := false

var arena: Node3D
var _zoom_before := 1.0

@onready var match_node: SquadMatch = $Match
@onready var hud: SquadHud = $HUD
@onready var cam: DynamicCamera = $Camera
@onready var dolls_root: Node3D = $Dolls


func _enter_tree() -> void:
	_zoom_before = DynamicCamera.user_zoom
	DynamicCamera.user_zoom = 1.0
	ActiveBlocks.ensure_input_actions()   # экшены pN_act1…3 (огонь — act1, перезарядка — act2)


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


## Боец player_index i: «Человек», рукой управления — кисть с оружием своей команды. human — P1 (клавиатура и мышь), иначе бот.
static func make_fighter(i: int, human: bool) -> ModularDoll:
	var bp := (load(BLUEPRINT) as BodyBlueprint).duplicate(true) as BodyBlueprint
	bp.control = PackedStringArray([String(Tuning.SQUAD_GUN_HAND[i % 2])])
	bp.control_rmb = PackedStringArray()
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


## Рука, оружие, мозг — в этом порядке: Match.respawn_doll пересоздаёт детей со скриптом в том же порядке, а настройки у них — в _init
## и из матча, не из экспортов.
static func attach_children(d: Doll, human: bool) -> void:
	var r := SquadArm.new()
	r.name = "ArmAssist"
	d.add_child(r)
	var g := SquadGun.new()
	g.name = "SquadGun"
	d.add_child(g)
	if not human:
		var b := SquadBrain.new()
		b.name = "SquadBrain"
		d.add_child(b)


## Кукла игрока (человек) или null.
func human() -> Doll:
	for d in match_node.dolls():
		if not (d as Doll).external_input:
			return d
	return null


func _physics_process(_delta: float) -> void:
	_human_gun()
	_tick_focus()


## Игрок: рука с оружием всегда тянется к курсору (цель руки — курсор каждый тик; без мыши — правый стик, как в бою), ствол смотрит
## по руке; огонь — ЛКМ или активная клавиша 1 (I / X геймпада), пока зажата; перезарядка — Q или активная клавиша 2 (Y геймпада).
func _human_gun() -> void:
	var p := human()
	if p == null:
		return
	var g := SquadMatch.gun_of(p)
	if g == null:
		return
	var a := g.arm()
	if a != null and p.alive:
		var mp: Variant = a.mouse_on_plane() if DisplayServer.mouse_get_mode() != DisplayServer.MOUSE_MODE_HIDDEN else null
		if mp is Vector3:
			a.set_target_override(mp)
		else:
			a.clear_target_override()
	g.trigger = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
		or (InputMap.has_action("p1_act1") and Input.is_action_pressed("p1_act1"))
	if Input.is_physical_key_pressed(KEY_Q) or (InputMap.has_action("p1_act2") and Input.is_action_pressed("p1_act2")):
		if g.mag < g.mag_max:
			g.reload()


## Камера: игрок + ближайший соперник ближе FOCUS_ENEMY_M (иначе на карте 64 м кадр всё время ездил бы туда-сюда); игрок выбыл —
## камера держит его обломки до возрождения (кадр не прыгает).
func _tick_focus() -> void:
	var p := match_node.me()
	var want := {}
	if p != null:
		want[p] = true
		if p.alive:
			var best: Doll = null
			var best_d := FOCUS_ENEMY_M
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
	var k: int = event.physical_keycode
	if UPGRADE_KEYS.has(k):
		var p := human()
		if p != null and match_node.choose(p.player_index, UPGRADE_KEYS.find(k)):
			get_viewport().set_input_as_handled()
		return
	match k:
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
			var path: String = preload("res://scenes/playground.gd").scene_for_key(k)
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
