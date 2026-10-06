## Площадка «Бомба касанием» (docs/plan-demo/BOMB.md; автор 06.10: «передать бомбу касанием»): купол Old NULL Hall
## (scenes/arena/null_hall.tscn, гравитация обычная, поле и чемпион по G / K выключены, голосования зрителей нет) + пять кукол + BombMatch
## + BombHud + стрелка к бомбе за кадром (BombMarkers) + камера.
## Куклы собираются здесь, до регистрации в матче (Match._late_ready — отложенный): чётные — светлый клён doll.tscn, нечётные — тёмный
## орех doll_dark.tscn; цвета — Tuning.BOMB_COLORS.
##   P1 (player_index 0) — человек: WASD летать, Shift ускорение, Space + A/D раскрутка; p1_bot = true (пробы) — тоже бот;
##   P2 (player_index 1) — по умолчанию бот; U — отдать человеку на стрелках (правый Ctrl, Enter) или вернуть бота; второй игрок может
##   просто нажать свою клавишу — бот отдаст управление сам (как в спорт-зале);
##   P3…P5 — боты BombBrain уровня bot_level (K — 1 → 2 → 3).
## Камера: люди + держатель бомбы, если он ближе Tuning.BOMB_FOCUS_M; бомба у человека — он и ближний к нему; людей в игре нет
## (выбыли) — все живые. Клавиши: R — заново, Esc — пауза (Flow), M / N — музыка / толпа, H — скин HUD, 1–9 — площадки хаба.
## Масштаб камеры игрока (DynamicCamera.user_zoom) на время сцены — 1: в куполе пятеро, на ближнем масштабе бомба всё время за кадром.
class_name BombPlayground
extends Node3D

const DOLL_SCENES := ["res://scenes/doll/doll.tscn", "res://scenes/doll/doll_dark.tscn"]
const FOCUS_GROUP := "bomb_focus"
const BOT_NAME := "BombBrain"

@export var bot_level := 2
## Пробы: P1 тоже бот (матч одними ботами).
@export var p1_bot := false
@export var p2_bot := true
@export var dolls_n: int = Tuning.BOMB_DOLLS

var arena: Node3D
var _zoom_before := 1.0

@onready var match_node: BombMatch = $Match
@onready var hud: BombHud = $HUD
@onready var cam: DynamicCamera = $Camera
@onready var dolls_root: Node3D = $Dolls


func _enter_tree() -> void:
	_zoom_before = DynamicCamera.user_zoom
	DynamicCamera.user_zoom = 1.0


func _exit_tree() -> void:
	DynamicCamera.user_zoom = _zoom_before


func _ready() -> void:
	BombBrain.default_level = bot_level
	for c in get_children():
		if c is Node3D and c.has_method("spawn_points"):
			arena = c
			break
	if arena != null:
		if "debug_keys" in arena:
			arena.set("debug_keys", false)   # G — смена поля, K — чемпион лиги: в бомбе не нужны
		if arena.has_signal("body_fell"):
			arena.connect("body_fell", _on_body_fell)
	_spawn()
	hud.bind(match_node, self)
	match_node.phase_changed.connect(func(p: int) -> void:
		if p == Match.Phase.COUNTDOWN:
			cam.snap())


func _spawn() -> void:
	for i in dolls_n:
		var human := (i == 0 and not p1_bot) or (i == 1 and not p2_bot)
		var d := make_doll(i, human)
		var sp: Vector2 = Tuning.BOMB_SPAWN[i % Tuning.BOMB_SPAWN.size()]
		d.position = Vector3(sp.x, sp.y, 0.0)
		dolls_root.add_child(d)
		if not human:
			var b := BombBrain.new()
			b.name = BOT_NAME
			d.add_child(b)


## Кукла player_index i (P1 — p1, P2 — p2, остальные — свои префиксы без клавиш). human — управляет клавиатура, иначе мозг.
static func make_doll(i: int, human: bool) -> Doll:
	var d := (load(String(DOLL_SCENES[i % DOLL_SCENES.size()])) as PackedScene).instantiate() as Doll
	d.name = "P%d" % (i + 1)
	d.player_index = i
	d.input_prefix = "p1" if i == 0 else ("p2" if i == 1 else "bot%d" % i)
	d.external_input = not human
	d.add_to_group("dolls")
	return d


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


## За P2 — бот (BombBrain ребёнком куклы) или человек на стрелках. Match.respawn_doll переносит и external_input, и узел мозга.
func set_p2_bot(on: bool) -> void:
	p2_bot = on
	var d := doll(1)
	if d == null:
		return
	var brain := d.get_node_or_null(BOT_NAME)
	if on and brain == null:
		var b := BombBrain.new()
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
	BombBrain.default_level = bot_level
	for d in match_node.dolls():
		var b := (d as Node).get_node_or_null(BOT_NAME) as BombBrain
		if b != null:
			b._brain_ready()
	hud.toast(tr("БОТЫ: УРОВЕНЬ %d") % bot_level)


func _physics_process(_delta: float) -> void:
	_tick_focus()


## Кого держит кадр (группа FOCUS_GROUP камеры).
func _tick_focus() -> void:
	var want := {}
	var hs: Array = []
	for h in humans():
		if (h as Doll).alive:
			hs.append(h)
	var hold := match_node.holder
	if hs.is_empty():
		for d in match_node.alive_dolls():
			want[d] = true
	else:
		for h in hs:
			want[h] = true
		if hold != null and is_instance_valid(hold) and hold.alive and not want.has(hold):
			if _nearest_dist(hold, hs) < Tuning.BOMB_FOCUS_M:
				want[hold] = true
		elif hold != null and want.has(hold):
			var best: Doll = null
			var bd := Tuning.BOMB_FOCUS_M
			for d in match_node.alive_dolls():
				if want.has(d):
					continue
				var dd := (d as Doll).centre_of_mass().distance_to(hold.centre_of_mass())
				if dd < bd:
					bd = dd
					best = d
			if best != null:
				want[best] = true
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
	var d := BombMatch.doll_of(body)
	if d == null or not d.alive or not d.parts.values().has(body):
		return
	d.knock_out()
