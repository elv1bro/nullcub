## Площадка «Королевская битва» (docs/plan-demo/ROYALE.md; MODES_PACK.md §2; автор 06.10: «королевская битва тоже можно»): карта
## «Полигон» (scenes/arena/proving_ground.tscn, ночью — proving_ground_night.tscn) + восемь бойцов + RoyaleMatch (зона — его ребёнок) +
## RoyaleHud + камера. Бойцы — «Человек» (kit_human), собираются здесь до регистрации в матче; цвет — Tuning.ROYALE_COLORS.
##   P1 (player_index 0) — человек: WASD летать, Shift рывок; рука тянется к курсору, ствол в руке со стороны курсора (RoyaleArm); ЛКМ
##   (или I) — огонь, пока зажата (гаусс — заряд, отпустил — выстрел; без оружия — рука бьёт); Q — перезарядка; E — схватить / бросить;
##   P2 (player_index 1) — бот или человек на стрелках (U; или просто нажми свою клавишу): правый Ctrl — рывок, Num 1 — огонь, Num 2 —
##   перезарядка, рука сама наводится на ближнего соперника (правый стик геймпада — вручную);
##   P3…P8 — боты RoyaleBrain уровня bot_level (K — 1 → 2 → 3).
## Камера: живые люди + ближний соперник (ближе ROYALE_FOCUS_M × зум); людей в игре нет — ведёт того, кто выбил последнего человека
## (он выбыл — его убийцу, иначе лидера по фрагам); после боя — победителя. Клавиши: R — заново, G — день / ночь, Esc — пауза (Flow),
## M / N — музыка / толпа, H — скин HUD, 1–9 — площадки хаба.
## Прочность суставов (JointBreak) на время сцены — Tuning.ROYALE_JOINTS, «Запас из деталей» — выключен.
class_name RoyalePlayground
extends Node3D

const DOLL_SCENE := preload("res://scenes/body/modular_doll.tscn")
const BLUEPRINT := "res://data/body/blueprints/kit_human.tres"
const SCENE_DAY := "res://scenes/playground_royale.tscn"
const SCENE_NIGHT := "res://scenes/playground_royale_night.tscn"
const FOCUS_GROUP := "royale_focus"
const PLAYERS_GROUP := "players"
const BOT_NAME := "RoyaleBrain"
const CAM_MIN_H := 5.5
const CAM_MAX_H := 9.0
const HAND_UIDS := {"Hand_L": "3", "Hand_R": "9"}   # кисти kit_human (Tuning.SQUAD_GUN_HAND)

@export var bot_level := 2
## Пробы: P1 тоже бот (бой одними ботами).
@export var p1_bot := false
@export var p2_bot := true
@export var fighters: int = Tuning.ROYALE_FIGHTERS

var arena: Node3D
## Кого ведёт камера, когда людей в игре нет (выбыли).
var spectating: Doll = null
var _zoom_before := 1.0
var _joints_before := false
var _parthp_before := false
var _view := 1.0

@onready var match_node: RoyaleMatch = $Match
@onready var hud: RoyaleHud = $HUD
@onready var cam: DynamicCamera = $Camera
@onready var dolls_root: Node3D = $Dolls


func _enter_tree() -> void:
	_zoom_before = DynamicCamera.user_zoom
	DynamicCamera.user_zoom = 1.0
	_joints_before = JointBreak.on
	_parthp_before = PartHp.on
	PartHp.set_on(false)
	JointBreak.set_on(Tuning.ROYALE_JOINTS)
	ActiveBlocks.ensure_input_actions()   # pN_act1…3: огонь — act1, перезарядка — act2


func _exit_tree() -> void:
	DynamicCamera.user_zoom = _zoom_before
	JointBreak.set_on(_joints_before)
	PartHp.set_on(_parthp_before)


func _ready() -> void:
	SquadBrain.default_level = bot_level
	for c in get_children():
		if c is Node3D and c.has_method("spawn_points"):
			arena = c
			break
	if arena != null and arena.has_signal("body_fell"):
		arena.connect("body_fell", _on_body_fell)
	_spawn()
	hud.playground = self
	hud.bind(match_node)
	hud.refresh_hint()
	match_node.phase_changed.connect(func(p: int) -> void:
		if p == Match.Phase.COUNTDOWN:
			spectating = null
			cam.snap())
	match_node.eliminated.connect(_on_eliminated)


func _spawn() -> void:
	for i in fighters:
		var human := (i == 0 and not p1_bot) or (i == 1 and not p2_bot)
		var d := make_fighter(i, human)
		d.position = match_node.slot_point(i)
		dolls_root.add_child(d)
		attach_children(d, human)


## Боец player_index i: «Человек»; рука с оружием на старте — со стороны середины карты (дальше — RoyaleArm перекладывает сам).
## human — управляет клавиатура (P1 — p1, P2 — p2), иначе мозг.
func make_fighter(i: int, human: bool) -> ModularDoll:
	var bp := (load(BLUEPRINT) as BodyBlueprint).duplicate(true) as BodyBlueprint
	var hand := "Hand_L" if match_node.slot_point(i).x < 0.0 else "Hand_R"
	bp.control = PackedStringArray([String(HAND_UIDS[hand])])
	bp.control_rmb = PackedStringArray()
	bp.id = "royale_%d" % i
	var d := DOLL_SCENE.instantiate() as ModularDoll
	d.blueprint = bp
	d.name = "P%d" % (i + 1)
	d.player_index = i
	d.input_prefix = "p1" if i == 0 else ("p2" if i == 1 else "bot%d" % i)
	d.external_input = not human
	d.add_to_group("dolls")
	if human:
		d.add_to_group(PLAYERS_GROUP)
	return d


## Рука, ствол, мозг — в этом порядке (Match.respawn_doll пересоздаёт детей со скриптом в том же порядке; настройки — из матча).
static func attach_children(d: Doll, human: bool) -> void:
	var r := RoyaleArm.new()
	r.name = "ArmAssist"
	d.add_child(r)
	var g := SquadGun.new()
	g.name = "SquadGun"
	d.add_child(g)
	if not human:
		var b := RoyaleBrain.new()
		b.name = BOT_NAME
		d.add_child(b)


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


## За P2 — бот (RoyaleBrain ребёнком куклы) или человек на стрелках. Match.respawn_doll переносит и external_input, и узел мозга.
func set_p2_bot(on: bool) -> void:
	p2_bot = on
	var d := doll(1)
	if d == null:
		return
	var brain := d.get_node_or_null(BOT_NAME)
	if on and brain == null:
		var b := RoyaleBrain.new()
		b.name = BOT_NAME
		d.add_child(b)
	elif not on and brain != null:
		d.remove_child(brain)
		brain.queue_free()
		var g := SquadMatch.gun_of(d)
		if g != null:
			g.trigger = false
			if g.arm() != null:
				g.arm().clear_target_override()
	d.external_input = on
	if not on:
		d.input_vec = Vector2.ZERO
		d.add_to_group(PLAYERS_GROUP)
	elif d.is_in_group(PLAYERS_GROUP):
		d.remove_from_group(PLAYERS_GROUP)
	hud.refresh_hint()


func set_bot_level(lv: int) -> void:
	bot_level = clampi(lv, 1, 3)
	SquadBrain.default_level = bot_level
	for d in match_node.dolls():
		var b := (d as Node).get_node_or_null(BOT_NAME) as RoyaleBrain
		if b != null:
			b._brain_ready()
	hud.toast(tr("БОТЫ: УРОВЕНЬ %d") % bot_level)


func _physics_process(delta: float) -> void:
	_p1_gun()
	_p2_gun()
	_tick_focus(delta)


## P1: рука всегда тянется к курсору (без мыши — правый стик), ствол — в руке со стороны курсора; огонь — ЛКМ или I (X геймпада), пока
## зажата; перезарядка — Q или O (Y геймпада).
func _p1_gun() -> void:
	var p := doll(0)
	if p == null or p.external_input:
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
	g.trigger = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or (InputMap.has_action("p1_act1") and Input.is_action_pressed("p1_act1"))
	if Input.is_physical_key_pressed(KEY_Q) or (InputMap.has_action("p1_act2") and Input.is_action_pressed("p1_act2")):
		if g.mag < g.mag_max:
			g.reload()


## P2 (человек): рука сама на ближнего соперника в пределах дальности оружия (правый стик — вручную), огонь — Num 1 (X геймпада),
## перезарядка — Num 2 (Y геймпада).
func _p2_gun() -> void:
	var p := doll(1)
	if p == null or p.external_input:
		return
	var g := SquadMatch.gun_of(p)
	if g == null:
		return
	var a := g.arm()
	var stick := Input.get_vector("p2_arm_left", "p2_arm_right", "p2_arm_down", "p2_arm_up") if InputMap.has_action("p2_arm_left") else Vector2.ZERO
	if a != null and p.alive:
		var best: Doll = null
		var reach := float(g.def.get("range", 10.0)) if g.weapon != "" else 4.0
		var bd := reach
		for d in match_node.alive_dolls():
			if d == p:
				continue
			var dist := p.centre_of_mass().distance_to((d as Doll).centre_of_mass())
			if dist < bd:
				bd = dist
				best = d
		if stick.length() > 0.2 or best == null:
			a.clear_target_override()
		else:
			a.set_target_override(best.centre_of_mass())
	g.trigger = InputMap.has_action("p2_act1") and Input.is_action_pressed("p2_act1")
	if InputMap.has_action("p2_act2") and Input.is_action_pressed("p2_act2") and g.mag < g.mag_max:
		g.reload()


## Камера: живые люди + ближний к каждому соперник (ближе ROYALE_FOCUS_M × зум); людей в игре нет — тот, за кем смотрим (+ его ближний);
## конец боя — победитель. Зум — оружие игрока × бонус «обзор».
func _tick_focus(delta: float) -> void:
	var want := {}
	var live_h: Array = []
	for h in humans():
		if (h as Doll).alive:
			live_h.append(h)
	if humans().is_empty() and match_node.focus_index >= 0:   # пробы и снимки: за «я» матча играет бот — камера ведёт его, как игрока
		var f := doll(match_node.focus_index)
		if f != null and f.alive:
			live_h.append(f)
	if match_node.play_state == "over":
		var w := doll(match_node.winner_index) if match_node.winner_index >= 0 else null
		if w != null:
			want[w] = true
	elif not live_h.is_empty():
		for h in live_h:
			want[h] = true
	else:
		if spectating == null or not is_instance_valid(spectating) or not spectating.alive:
			spectating = _pick_spectate(null)
		if spectating != null:
			want[spectating] = true
	var me: Doll = live_h[0] if not live_h.is_empty() else spectating
	var z := match_node.view_zoom(me) if me != null else 1.0
	_view = move_toward(_view, z, delta * 0.8)
	cam.min_half_height = CAM_MIN_H * _view
	cam.max_half_height = CAM_MAX_H * _view
	if match_node.play_state != "over":
		for k in want.keys():
			var c := (k as Doll).centre_of_mass()
			var best: Doll = null
			var bd := Tuning.ROYALE_FOCUS_M * _view
			for d in match_node.alive_dolls():
				if want.has(d):
					continue
				var dist := c.distance_to((d as Doll).centre_of_mass())
				if dist < bd:
					bd = dist
					best = d
			if best != null:
				want[best] = true
	if want.is_empty():
		for d in match_node.alive_dolls():
			want[d] = true
	for n in get_tree().get_nodes_in_group(FOCUS_GROUP):
		if not want.has(n):
			n.remove_from_group(FOCUS_GROUP)
	for n in want.keys():
		if is_instance_valid(n) and not (n as Node).is_in_group(FOCUS_GROUP):
			(n as Node).add_to_group(FOCUS_GROUP)


## За кем смотреть: убийца (если жив), иначе лидер по фрагам среди живых, иначе любой живой.
func _pick_spectate(killer: Doll) -> Doll:
	if killer != null and is_instance_valid(killer) and killer.alive:
		return killer
	var best: Doll = null
	var bk := -1
	for d in match_node.alive_dolls():
		var k := int((match_node.tally.get((d as Doll).player_index, {}) as Dictionary).get("kills", 0))
		if k > bk:
			bk = k
			best = d
	return best


## Выбыл человек — камера на того, кто выбил; выбыл тот, за кем смотрим, — на его убийцу.
func _on_eliminated(victim: Doll, killer: Doll, _place: int, _left: int, _cause: String) -> void:
	var me_out := humans().is_empty() and victim.player_index == match_node.focus_index   # пробы и снимки: «я» — бот
	if not victim.external_input or victim == spectating or me_out:
		spectating = _pick_spectate(killer)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if p2_bot:
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
			set_p2_bot(not p2_bot)
			hud.toast(tr("P2: бот") if p2_bot else tr("P2: человек"))
		KEY_K:
			set_bot_level(bot_level % 3 + 1)
		KEY_G:
			var want := SCENE_DAY if scene_file_path == SCENE_NIGHT else SCENE_NIGHT
			Loading.change_scene(want, "ПОДКЛЮЧЕНИЕ", want.get_file().get_basename())
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
