## Площадка «Гонка: трасса» (docs/plan-demo/RACE_TRACK.md; автор 06.10: «в гонке мы можем сделать длинную сложную карту с разными
## сложностями на ней?» → «делаем»). Сцена scenes/playground_race_track.tscn = карта (инстанс race_track.tscn, TrackArena) + куклы +
## TrackMatch + TrackHud + стрелки к соперникам (OffscreenMarkers) + камера.
## Гонщики — как в «Гонке: 10 точек» (RacePlayground.make_racer: «Человек», рубашка цвета игрока):
##   P1 (player_index 0) — человек: WASD летать, Shift ускорение, Space + A/D раскрутка, ЛКМ — рука к курсору, E — хват;
##   P2 (1) — бот TrackBrain; U — отдать его второму игроку на стрелках (или просто нажать стрелку), U ещё раз — снова бот;
##   P3, P4 — боты. Уровень ботов bot_level, K — 1 → 2 → 3.
## Клавиши: Q — к своей контрольной точке (P1, через 2 с), R — заново, Esc — пауза (Flow), 1–9 — площадки хаба, M / N — музыка / толпа,
## H — скин HUD.
## Камера (DynamicCamera, группа фокуса track_focus) — за людьми: P1; P2-человек — пока ближе Tuning.TRACK_CAM_PAIR_M к P1 (иначе кадр
## разъехался бы на сотню метров — дальше стрелка у края); боты в кадр не тянут (как follow_mode = "humans", но группу собирает
## площадка: людей нет — гонщик focus_index матча, пробы). Плюс точка линии трассы на CAM_LOOK_M впереди главного гонщика (CamAnchor):
## кадр смотрит, куда лететь (в трубах — вдоль трубы, у пропасти — на мосты), а не держит куклу в центре над полом.
## Яма и сетка (body_fell карты) — TrackMatch.drop(«fall»): возврат к контрольной точке.
class_name TrackPlayground
extends Node3D

const FOCUS_GROUP := "track_focus"
const PLAYERS_GROUP := "players"
const BRAIN := "TrackBrain"
const BEST_PATH := "user://race_track_best.cfg"
## Файл рекордов (пробы подменяют, чтобы не трогать рекорды игрока).
static var best_path := BEST_PATH

@export var bot_level := 2
## Пробы: P1 тоже бот (гонка одними ботами).
@export var p1_bot := false
@export var p2_human := false

const CAM_LOOK_M := 6.0

var arena: TrackArena
var _zoom_before := 1.0
var _anchor: CamAnchor


## Точка «куда лететь» для камеры: не кукла (external_input = true — для камеры и стрелок не человек), только centre_of_mass().
class CamAnchor extends Node3D:
	var pos := Vector3.ZERO
	var external_input := true

	func centre_of_mass(_interpolated := false) -> Vector3:
		return pos

@onready var match_node: TrackMatch = $Match
@onready var hud: TrackHud = $HUD
@onready var cam: DynamicCamera = $Camera
@onready var dolls_root: Node3D = $Dolls


func _enter_tree() -> void:
	_zoom_before = DynamicCamera.user_zoom
	DynamicCamera.user_zoom = 1.0


func _exit_tree() -> void:
	DynamicCamera.user_zoom = _zoom_before


func _ready() -> void:
	TrackBrain.default_level = bot_level
	for c in get_children():
		if c is TrackArena:
			arena = c
			break
	if arena != null:
		arena.body_fell.connect(_on_body_fell)
		match_node.bind_arena(arena)
	_anchor = CamAnchor.new()
	_anchor.name = "CamAnchor"
	add_child(_anchor)
	_spawn_racers()
	hud.bind(match_node, self)
	match_node.phase_changed.connect(func(p: int) -> void:
		if p == Match.Phase.COUNTDOWN:
			cam.snap())
	match_node.match_over.connect(_on_over)


func _spawn_racers() -> void:
	var pts: Array = arena.spawn_points() if arena != null else []
	for i in Tuning.TRACK_RACERS:
		var human := (i == 0 and not p1_bot) or (i == 1 and p2_human)
		var d := RacePlayground.make_racer(i, human)
		d.name = "P%d" % (i + 1)
		d.position = pts[i] if i < pts.size() else Vector3(2.5 * i, 0.05, 0.0)
		dolls_root.add_child(d)
		attach_children(d, human)


## Рука мышью — только у P1-человека; мозг TrackBrain — у ботов.
static func attach_children(d: Doll, human: bool) -> void:
	if human and d.player_index == 0:
		ArmAssist.attach_to(d)
	if not human:
		var b := TrackBrain.new()
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
		var b := TrackBrain.new()
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


## Фокус камеры: P1 (или гонщик focus_index, если людей нет); P2-человек — пока рядом с P1.
func _tick_focus() -> void:
	var want := {}
	var main := match_node.me()
	if main != null:
		want[main] = true
		if _tick_anchor(main):
			want[_anchor] = true
		var c := main.centre_of_mass()
		for d in match_node.dolls():
			var dd := d as Doll
			if dd != main and not dd.external_input and dd.alive and dd.centre_of_mass().distance_to(c) < Tuning.TRACK_CAM_PAIR_M:
				want[dd] = true
	else:
		for d in match_node.alive_dolls():
			want[d] = true
	for n in get_tree().get_nodes_in_group(FOCUS_GROUP):
		if not want.has(n):
			n.remove_from_group(FOCUS_GROUP)
	for n in want.keys():
		if is_instance_valid(n) and not (n as Node).is_in_group(FOCUS_GROUP):
			(n as Node).add_to_group(FOCUS_GROUP)


## Точка линии на CAM_LOOK_M впереди главного гонщика (сглажена; живой — иначе кадр ждёт возврата на контрольную точку).
func _tick_anchor(main: Doll) -> bool:
	var rt := match_node.route
	if rt == null or not rt.ready() or not main.alive:
		return false
	var st := match_node.state_of(main)
	var c := main.centre_of_mass()
	var pr := rt.project(Vector2(c.x, c.y), float(st.get("prog", 0.0)), 30.0, int(st.get("seg", -1)))
	if pr.is_empty():
		return false
	var p := rt.point_ahead(int(pr["seg"]), float(pr["s"]), CAM_LOOK_M)
	var t := Vector3(p.x, p.y, 0.0)
	_anchor.pos = t if _anchor.pos.distance_to(t) > 15.0 else _anchor.pos.lerp(t, 0.08)
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = event.physical_keycode
	match k:
		KEY_U:
			set_p2_human(not p2_human)
			hud.toast(tr("P2: человек на стрелках") if p2_human else tr("P2: бот"))
			return
		KEY_Q:
			var me := match_node.me()
			if me != null and not me.external_input:
				match_node.drop(me, "reset")
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


## K: уровень ботов 1 → 2 → 3 — живые мозги перечитывают уровень сразу (ветки развилок — те же), новые берут его из default_level.
func set_bot_level(lv: int) -> void:
	bot_level = clampi(lv, 1, 3)
	TrackBrain.default_level = bot_level
	for d in match_node.dolls():
		var b := (d as Node).get_node_or_null(BRAIN) as TrackBrain
		if b != null:
			b._brain_ready()
	hud.toast(tr("БОТЫ: УРОВЕНЬ %d") % bot_level)


func _on_body_fell(body: Node3D) -> void:
	var d := body.get_parent() as Doll
	if d == null or not d.alive or not d.parts.values().has(body):
		return
	match_node.drop(d, "fall")


# --- рекорд ---

## Лучшее время P1 до финиша (с) или −1.
func best_time() -> float:
	return best_time_from(best_path)


static func best_time_from(path: String) -> float:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return -1.0
	return float(cfg.get_value("track", "best", -1.0))


## Рекорд пишется, только если человек-P1 доехал до финиша и время лучше прежнего. true — новый рекорд.
static func save_best(seconds: float) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(best_path)
	var old := float(cfg.get_value("track", "best", -1.0))
	if old > 0.0 and old <= seconds:
		return false
	cfg.set_value("track", "best", snappedf(seconds, 0.01))
	cfg.save(best_path)
	return true


func _on_over(_winner: Doll, results: Dictionary) -> void:
	var d := _doll(0)
	var fresh := false
	var per: Dictionary = results.get("racers", {})
	var me: Dictionary = per.get(0, {})
	if d != null and not d.external_input and bool(me.get("finished", false)):
		fresh = save_best(float(me.get("finish_t", 0.0)))
	hud.show_best(best_time(), fresh)
