## Площадка «Гонка: 10 точек» (docs/plan-demo/RACE.md; автор 06.10: «гонки — нужно быстрее собрать 10 пунктов»; «у всех одни и те же
## точки: если кто-то взял, то у тебя этой точки уже нет, и надо к следующей»). Одна площадка на все карты: сцена playground_race*.tscn
## = арена (инстанс, сцену арены не трогаем) + метки точек RaceMarks (Marker3D, 16–20 штук) + старт RaceStart (Marker3D Start0..3) +
## куклы + RaceMatch + RaceHud + стрелки к соперникам (OffscreenMarkers) + камера.
## Куклы собираются здесь, до регистрации в матче (Match._late_ready — отложенный): «Человек» (kit_human) у всех, рубашка — цвет игрока
## (Tuning.PLAYER_COLORS по player_index).
##   P1 (player_index 0) — человек: WASD летать, Shift ускорение, Space + A/D раскрутка, ЛКМ — рука к курсору, E — хват (как в бою);
##   P2 (1) — бот RaceBrain; U — отдать его второму игроку на стрелках (или просто нажать стрелку), U ещё раз — снова бот;
##   P3, P4 — боты. Уровень ботов bot_level, K — 1 → 2 → 3.
## Клавиши: R — заново, Esc — пауза (Flow), 1–9 — площадки хаба, M / N — музыка / толпа, H — скин HUD.
## Камера (DynamicCamera, группа фокуса race_focus): люди + ближайшая к игроку горящая точка ближе focus_point_m + соперники ближе
## focus_rivals_m; остальное — стрелки у края экрана (точки — RaceHud, соперники — OffscreenMarkers). На узкой карте (Руины, Свалка)
## focus_rivals_m большой — в кадре все. Масштаб игрока (DynamicCamera.user_zoom) на время сцены — 1, как в стычке.
## Пропасть (body_fell арены) — KO, возврат у последней своей точки (RaceMatch).
class_name RacePlayground
extends Node3D

const DOLL_SCENE := preload("res://scenes/body/modular_doll.tscn")
const BLUEPRINT := "res://data/body/blueprints/kit_human.tres"
const FOCUS_GROUP := "race_focus"
const PLAYERS_GROUP := "players"
const BRAIN := "RaceBrain"
const BEST_PATH := "user://race_best.cfg"
## Файл рекордов (пробы подменяют, чтобы не трогать рекорды игрока).
static var best_path := BEST_PATH

## Карта для рекордов и подписи: proving | ruins | scrap.
@export var map_id := "proving"
@export var bot_level := 2
## Пробы: P1 тоже бот (гонка одними ботами).
@export var p1_bot := false
@export var p2_human := false
## Камера: соперник ближе этого (м) к игроку — в кадре вместе с ним; горящая точка ближе focus_point_m — тоже (ближайшая).
@export var focus_rivals_m := 10.0
@export var focus_point_m := 16.0

var arena: Node3D
var _zoom_before := 1.0

@onready var match_node: RaceMatch = $Match
@onready var hud: RaceHud = $HUD
@onready var cam: DynamicCamera = $Camera
@onready var dolls_root: Node3D = $Dolls


func _enter_tree() -> void:
	_zoom_before = DynamicCamera.user_zoom
	DynamicCamera.user_zoom = 1.0


func _exit_tree() -> void:
	DynamicCamera.user_zoom = _zoom_before


func _ready() -> void:
	RaceBrain.default_level = bot_level
	for c in get_children():
		if c is Node3D and c.has_method("spawn_points"):
			arena = c
			break
	if arena != null and arena.has_signal("body_fell"):
		arena.connect("body_fell", _on_body_fell)
	match_node.set_marks(_markers("RaceMarks"))
	match_node.set_starts(_markers("RaceStart"))
	_spawn_racers()
	hud.bind(match_node, self)
	match_node.phase_changed.connect(func(p: int) -> void:
		if p == Match.Phase.COUNTDOWN:
			cam.snap())
	match_node.match_over.connect(_on_over)


## Мировые точки детей-маркеров узла name (в порядке дерева).
func _markers(name_: String) -> Array:
	var out: Array = []
	var holder := get_node_or_null(name_)
	if holder != null:
		for m in holder.get_children():
			if m is Node3D:
				out.append((m as Node3D).global_position)
	return out


func _spawn_racers() -> void:
	var pts := match_node.starts
	for i in Tuning.RACE_RACERS:
		var human := (i == 0 and not p1_bot) or (i == 1 and p2_human)
		var d := make_racer(i, human)
		d.position = pts[i] if i < pts.size() else Vector3(-4.5 + 3.0 * i, 0.5, 0.0)
		dolls_root.add_child(d)
		attach_children(d, human)


## Гонщик player_index i: «Человек», рубашка — цвет игрока. human — человек (P1 — клавиатура и мышь, P2 — стрелки), иначе бот.
static func make_racer(i: int, human: bool) -> ModularDoll:
	var bp := (load(BLUEPRINT) as BodyBlueprint).duplicate(true) as BodyBlueprint
	bp.id = "race_%d" % i
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


## Рука мышью — только у P1-человека (у ботов она не нужна, а хват дорог: ArmAssist.intersect_shape); мозг — у ботов.
static func attach_children(d: Doll, human: bool) -> void:
	if human and d.player_index == 0:
		ArmAssist.attach_to(d)
	if not human:
		var b := RaceBrain.new()
		b.name = BRAIN
		d.add_child(b)


func _doll(pi: int) -> Doll:
	for d in match_node.dolls():
		if (d as Doll).player_index == pi:
			return d
	return null


## P2 — человек на стрелках или бот (U). Match.respawn_doll переносит и external_input, и узел мозга.
func set_p2_human(on: bool) -> void:
	p2_human = on
	var d := _doll(1)
	if d == null:
		return
	var brain := d.get_node_or_null(BRAIN)
	if not on and brain == null:
		var b := RaceBrain.new()
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
	hud.refresh_names()


func _physics_process(_delta: float) -> void:
	_tick_focus()


## Фокус камеры: люди; у главного (P1) — ближайшая горящая точка ближе focus_point_m и соперники ближе focus_rivals_m. Людей нет (пробы)
## — все живые куклы.
func _tick_focus() -> void:
	var want := {}
	var main := match_node.me()
	var humans: Array = match_node.dolls().filter(func(d: Variant) -> bool: return not (d as Doll).external_input)
	if humans.is_empty() and main == null:
		for d in match_node.alive_dolls():
			want[d] = true
	else:
		if main != null:
			want[main] = true
		for h in humans:
			want[h] = true
		if main != null and main.alive:
			var c := main.centre_of_mass()
			var best: RacePoint = null
			var best_d := focus_point_m
			for p in match_node.lit_points():
				var dd := Vector2(c.x - (p as RacePoint).home.x, c.y - (p as RacePoint).home.y).length()
				if dd < best_d:
					best_d = dd
					best = p
			if best != null:
				want[best] = true
			for d in match_node.alive_dolls():
				if d != main and (d as Doll).centre_of_mass().distance_to(c) < focus_rivals_m:
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
	match k:
		KEY_U:
			set_p2_human(not p2_human)
			hud.toast(tr("P2: человек на стрелках") if p2_human else tr("P2: бот"))
			return
		KEY_R:
			match_node.restart()
			return
		KEY_ESCAPE:
			Flow.toggle_pause(match_node.restart)
			return
		KEY_M:
			hud.toast(get_node("/root/GameAudio").toggle_music())
			return
		KEY_N:
			hud.toast(get_node("/root/GameAudio").toggle_crowd())
			return
		KEY_H:
			hud.toast(tr("HUD: ") + HudSkin.cycle())
			return
		KEY_K:
			set_bot_level(bot_level % 3 + 1)
			return
	if not p2_human:
		for a in ["p2_left", "p2_right", "p2_up", "p2_down", "p2_dash", "p2_flip"]:
			if InputMap.has_action(a) and event.is_action(a):
				set_p2_human(true)
				hud.toast(tr("P2: человек на стрелках"))
				return
	var path: String = preload("res://scenes/playground.gd").scene_for_key(k)
	if path != "" and path != scene_file_path:
		Loading.change_scene(path, "ПОДКЛЮЧЕНИЕ", path.get_file().get_basename())


## K: уровень ботов 1 → 2 → 3 — живые мозги перечитывают уровень сразу, новые (после возрождения) берут его из default_level.
func set_bot_level(lv: int) -> void:
	bot_level = clampi(lv, 1, 3)
	RaceBrain.default_level = bot_level
	for d in match_node.dolls():
		var b := (d as Node).get_node_or_null(BRAIN) as RaceBrain
		if b != null:
			b._brain_ready()
	hud.toast(tr("БОТЫ: УРОВЕНЬ %d") % bot_level)


func _on_body_fell(body: Node3D) -> void:
	var d := body.get_parent() as Doll
	if d == null or not d.alive or not d.parts.values().has(body):
		return
	d.knock_out()


# --- рекорд ---

## Лучшее время P1 до победы на этой карте (с) или −1.
func best_time() -> float:
	return best_time_for(map_id, match_node.to_win)


static func best_time_for(map: String, to_win: int) -> float:
	var cfg := ConfigFile.new()
	if cfg.load(best_path) != OK:
		return -1.0
	return float(cfg.get_value(map, "to_%d" % to_win, -1.0))


## Рекорд пишется, только если победил человек-P1 (player_index 0, не бот) и время лучше прежнего. true — новый рекорд.
static func save_best(map: String, to_win: int, seconds: float) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(best_path)
	var key := "to_%d" % to_win
	var old := float(cfg.get_value(map, key, -1.0))
	if old > 0.0 and old <= seconds:
		return false
	cfg.set_value(map, key, snappedf(seconds, 0.01))
	cfg.save(best_path)
	return true


func _on_over(_winner: Doll, results: Dictionary) -> void:
	var w := int(results.get("winner_index", -1))
	var d := _doll(w)
	var fresh := false
	if w == 0 and d != null and not d.external_input and String(results.get("reason", "")) == "points":
		fresh = save_best(map_id, match_node.to_win, float(results.get("race_time", 0.0)))
	hud.show_best(best_time(), fresh)
