## Площадка «Стенка на стенку 5×5» (docs/plan-demo/BRAWL.md; автор 08.10: «5×5 это другой режим»): Полигон
## (scenes/arena/proving_ground.tscn, 64 × 16 м) + десять кукол + BrawlMatch + BrawlHud + камера.
## Куклы собираются здесь, до регистрации в матче (Match._late_ready — отложенный): «Человек» (kit_human) у всех, рубашка и обводка —
## цвет команды (BrawlMatch._dress). Синие (чётный player_index) слева, красные (нечётный) справа — точки Tuning.BRAWL_SPAWN.
##   P1 (player_index 0, синие) — человек: WASD летать, Shift ускорение, Space + A/D раскрутка, ЛКМ — рука к курсору (ArmAssist);
##   P2 (1, красные) — бот; U — отдать его второму игроку на стрелках (правый Ctrl, Enter; или второй просто жмёт стрелку — бот отдаёт
##   управление сам), U ещё раз — снова бот; остальные восемь — боты BrawlBrain уровня bot_level (K — 1 → 2 → 3).
## Клавиши: R — заново, Esc — пауза (Flow), M / N — музыка / толпа, H — скин HUD, 1–9 — площадки хаба.
## Камера (DynamicCamera, группа фокуса brawl_focus): живые люди + до BRAWL_FOCUS_N ближайших к ним живых врагов не дальше
## BRAWL_FOCUS_M; людей не осталось — все живые. Масштаб игрока (DynamicCamera.user_zoom) на время сцены — 1, как в стычке.
## Пропасть (body_fell арены) — KO.
class_name BrawlPlayground
extends Node3D

const DOLL_SCENE := preload("res://scenes/body/modular_doll.tscn")
const BLUEPRINT := "res://data/body/blueprints/kit_human.tres"
const FOCUS_GROUP := "brawl_focus"
const PLAYERS_GROUP := "players"
const BRAIN := "BrawlBrain"

@export var bot_level := 2
## Пробы: P1 тоже бот (матч одними ботами).
@export var p1_bot := false
@export var p2_human := false

var arena: Node3D
var _zoom_before := 1.0

@onready var match_node: BrawlMatch = $Match
@onready var hud: BrawlHud = $HUD
@onready var cam: DynamicCamera = $Camera
@onready var dolls_root: Node3D = $Dolls


func _enter_tree() -> void:
	_zoom_before = DynamicCamera.user_zoom
	DynamicCamera.user_zoom = 1.0


func _exit_tree() -> void:
	DynamicCamera.user_zoom = _zoom_before


func _ready() -> void:
	BrawlBrain.default_level = bot_level
	for c in get_children():
		if c is Node3D and c.has_method("spawn_points"):
			arena = c
			break
	if arena != null and arena.has_signal("body_fell"):
		arena.connect("body_fell", _on_body_fell)
	_spawn()
	hud.bind(match_node, self)
	match_node.phase_changed.connect(func(p: int) -> void:
		if p == Match.Phase.COUNTDOWN:
			cam.snap())


func _spawn() -> void:
	for i in Tuning.BRAWL_PER_TEAM * 2:
		var human := (i == 0 and not p1_bot) or (i == 1 and p2_human)
		var d := make_doll(i, human)
		d.position = BrawlMatch.spawn_for(i)
		dolls_root.add_child(d)
		attach_children(d, human)


## Боец player_index i: «Человек». human — человек (P1 — клавиатура и мышь, P2 — стрелки), иначе бот.
static func make_doll(i: int, human: bool) -> ModularDoll:
	var bp := (load(BLUEPRINT) as BodyBlueprint).duplicate(true) as BodyBlueprint
	bp.id = "brawl_%d" % i
	var d := DOLL_SCENE.instantiate() as ModularDoll
	d.blueprint = bp
	d.name = "P%d" % (i + 1)
	d.player_index = i
	d.input_prefix = "p%d" % (i + 1) if human else "bot%d" % i
	d.external_input = not human
	d.add_to_group("dolls")
	if human:
		d.add_to_group(PLAYERS_GROUP)
	return d


## Рука мышью — только у P1-человека (у ботов не нужна, а хват дорог: ArmAssist.intersect_shape); мозг — у ботов.
static func attach_children(d: Doll, human: bool) -> void:
	if human and d.player_index == 0:
		ArmAssist.attach_to(d)
	if not human:
		var b := BrawlBrain.new()
		b.name = BRAIN
		d.add_child(b)


func dolls() -> Array:
	return match_node.dolls()


func doll(index: int) -> Doll:
	for d in match_node.dolls():
		if (d as Doll).player_index == index:
			return d
	return null


## Люди (куклы без мозга), живые и нет.
func humans() -> Array:
	var out: Array = []
	for d in match_node.dolls():
		if not (d as Doll).external_input:
			out.append(d)
	return out


## P2 — человек на стрелках или бот (U). Match.respawn_doll переносит и external_input, и узел мозга.
func set_p2_human(on: bool) -> void:
	p2_human = on
	var d := doll(1)
	if d == null:
		return
	var brain := d.get_node_or_null(BRAIN)
	if not on and brain == null:
		var b := BrawlBrain.new()
		b.name = BRAIN
		d.add_child(b)
	elif on and brain != null:
		d.remove_child(brain)
		brain.queue_free()
	d.external_input = not on
	d.input_prefix = "p2" if on else "bot1"
	d.input_vec = Vector2.ZERO
	if on:
		d.add_to_group(PLAYERS_GROUP)
	elif d.is_in_group(PLAYERS_GROUP):
		d.remove_from_group(PLAYERS_GROUP)
	hud.refresh_hint()


func set_bot_level(lv: int) -> void:
	bot_level = clampi(lv, 1, 3)
	BrawlBrain.default_level = bot_level
	for d in match_node.dolls():
		var b := (d as Node).get_node_or_null(BRAIN) as BrawlBrain
		if b != null:
			b._brain_ready()
	hud.toast(tr("БОТЫ: УРОВЕНЬ %d") % bot_level)


func _physics_process(_delta: float) -> void:
	_tick_focus()


## Кого держит кадр (группа FOCUS_GROUP камеры): живые люди и до BRAWL_FOCUS_N ближайших к ним врагов не дальше BRAWL_FOCUS_M;
## людей в игре нет — все живые.
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
		var near: Array = []   # [[dist, doll]]
		for d in match_node.alive_dolls():
			if want.has(d):
				continue
			var hd := _nearest_dist(d as Doll, hs)
			if hd < Tuning.BRAWL_FOCUS_M and BrawlMatch.team_of(d) != BrawlMatch.team_of(hs[0]):
				near.append([hd, d])
		near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		for i in mini(near.size(), Tuning.BRAWL_FOCUS_N):
			want[near[i][1]] = true
	for n in get_tree().get_nodes_in_group(FOCUS_GROUP):
		if not want.has(n):
			n.remove_from_group(FOCUS_GROUP)
	for n in want.keys():
		if is_instance_valid(n) and not (n as Node).is_in_group(FOCUS_GROUP):
			(n as Node).add_to_group(FOCUS_GROUP)


static func _nearest_dist(d: Doll, others: Array) -> float:
	var best := INF
	for o in others:
		best = minf(best, d.centre_of_mass().distance_to((o as Doll).centre_of_mass()))
	return best


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if not p2_human:
		for a in ["p2_left", "p2_right", "p2_up", "p2_down", "p2_dash", "p2_flip"]:
			if InputMap.has_action(a) and event.is_action(a):
				set_p2_human(true)
				hud.toast(tr("P2: человек на стрелках"))
				return
	match event.physical_keycode:
		KEY_R:
			match_node.restart()
		KEY_ESCAPE:
			Flow.toggle_pause(match_node.restart)
		KEY_U:
			set_p2_human(not p2_human)
			hud.toast(tr("P2: человек на стрелках") if p2_human else tr("P2: бот"))
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


func _on_body_fell(body: Node3D) -> void:
	var d := body.get_parent() as Doll
	if d == null or not d.alive or not d.parts.values().has(body):
		return
	d.knock_out()
