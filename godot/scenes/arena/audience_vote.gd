## Голосование зрителей купола (docs/plan-demo/15-audience-vote.md; лор §8 «AUDIENCE EVENT», §14 «Things begin going wrong»).
## Узел-ребёнок площадки с куполом (Match + NullHallArena). 1–2 раза за бой зрители выбирают, как изменить поле NULL:
##   • первое голосование — через first_s боя (Tuning.VOTE_FIRST_S), второе — на Sudden Death; не больше VOTE_MAX_PER_MATCH;
##   • три варианта из пула OPTIONS §8 (сила и направление гравитации, обломки сверху); голоса симулируются: базовые веса случайны,
##     криты и длинные комбо до голосования сдвигают их к хаосу (Tuning.VOTE_CHAOS_*); проценты растут duration_s, потом «… WINS»;
##   • победивший вариант действует effect_s, потом поле возвращается к регламенту (Tuning.GRAVITY вниз), обломки убираются;
##   • толпа заводится на старте и на итоге (NullHallArena.excite), табло зала пишет AUDIENCE EVENT / «… WINS»;
##   • аномалия (anomaly = "vote_mismatch", кампания, бой 3 — §14): 74 % за LOW GRAVITY, а поле включает GRAVITY INVERSION;
##     табло мигает, у N0 на экране GLITCH; реплику говорит N0 облачком (n0_host.gd), без N0 — субтитр в панели.
## Панель — scenes/arena/audience_vote_panel.tscn (ребёнок Panel). Пробы укорачивают first_s / duration_s / effect_s.
## Журнал history (для проб): {options, pct, winner, applied, anomaly, fight_time}.
class_name AudienceVote
extends Node

signal vote_started(options: Array)
signal vote_finished(result: Dictionary)
signal effect_ended

## Пул вариантов: title — строка табло, g / dir — поле (сила в G, направление экрана), debris — обломки, chaos — насколько вариант
## любит разогретая толпа (0..1). SIDE PULL — сторона случайная.
const OPTIONS := {
	"low_gravity": {"title": "LOW GRAVITY", "g": 0.10, "dir": Vector2(0.0, -1.0), "chaos": 0.1},
	"heavy": {"title": "HEAVY FIELD", "g": 0.50, "dir": Vector2(0.0, -1.0), "chaos": 0.5},
	"flip": {"title": "GRAVITY FLIP", "g": 0.20, "dir": Vector2(0.0, 1.0), "chaos": 0.9},
	"side_pull": {"title": "SIDE PULL", "g": 0.24, "dir": Vector2(1.0, 0.0), "chaos": 0.7},
	"zero_g": {"title": "ZERO G", "g": 0.0, "dir": Vector2(0.0, -1.0), "chaos": 0.6},
	"debris": {"title": "DEBRIS DROP", "debris": true, "chaos": 1.0},
}
## Что включает поле при аномалии «результат не тот» (§14: зрители — LOW GRAVITY 74 %, арена — GRAVITY INVERSION).
const INVERSION := {"id": "inversion", "title": "GRAVITY INVERSION", "g": 0.35, "dir": Vector2(0.0, 1.0)}
const ANOMALY_PCT := [74, 16, 10]
const CRATE_SCENE := "res://scenes/props/crate.tscn"
const N0_LINES := {
	"start": "N0: Зрители, ваш ход! Табло принимает голоса.",
	"anomaly": "N0: Эм… это не то, за что голосовали. Технический сбой! Наверное.",
}

@export var enabled := true
## "" — обычное голосование; "vote_mismatch" — аномалия §14 (первое голосование матча).
@export var anomaly := ""
@export var first_s := Tuning.VOTE_FIRST_S
@export var duration_s := Tuning.VOTE_DURATION_S
@export var effect_s := Tuning.VOTE_EFFECT_S
@export var match_path: NodePath = ^"../Match"
@export var arena_path: NodePath = ^"../NullHall"
@export var panel_path: NodePath = ^"Panel"
@export var rng_seed := 0

var state := "idle"            # idle → voting → effect → idle
var votes_done := 0
var options: Array = []        # [{id, title, g?, dir?, debris?}]
var target_pct: Array = []     # итог, сумма 100
var shown_pct: Array = []
var result: Dictionary = {}
var history: Array = []
var chaos := 0.0
var t := 0.0
var match_node: Match
var arena: Node
var panel: Node
var debris: Array = []
var _rng := RandomNumberGenerator.new()
var _board: Label3D = null
var _board_text := "NULL FIELD"


func _ready() -> void:
	match_node = get_node_or_null(match_path) as Match
	arena = get_node_or_null(arena_path)
	panel = get_node_or_null(panel_path)
	_rng.seed = rng_seed if rng_seed != 0 else int(Time.get_ticks_usec())
	if arena != null:
		_board = arena.find_child("Text_NULL_FIELD", true, false) as Label3D
		if _board != null:
			_board_text = _board.text
	if match_node != null:
		match_node.phase_changed.connect(_on_phase)
		match_node.hit_fx.connect(func(ctx: Dictionary) -> void:
			var tier := String(ctx.get("tier", ""))
			if tier == "crit" or tier == "ko_crit":
				chaos = minf(1.0, chaos + Tuning.VOTE_CHAOS_PER_CRIT))
		match_node.combo_changed.connect(func(_d: Doll, n: int) -> void:
			if n >= 3:
				chaos = minf(1.0, chaos + Tuning.VOTE_CHAOS_PER_COMBO))


func _physics_process(delta: float) -> void:
	if not enabled or match_node == null or arena == null:
		return
	match state:
		"idle":
			if votes_done == 0 and match_node.phase == Match.Phase.FIGHT and match_node.fight_time >= first_s:
				start_vote()
		"voting":
			t += delta
			var k := smoothstep(0.0, 1.0, clampf(t / maxf(duration_s, 0.01), 0.0, 1.0))
			for i in shown_pct.size():
				var wobble := _rng.randf_range(-4.0, 4.0) * (1.0 - k)
				shown_pct[i] = maxf(0.0, lerpf(100.0 / shown_pct.size(), float(target_pct[i]), k) + wobble)
			if panel != null:
				panel.call("set_percents", _normalised(shown_pct))
			if t >= duration_s:
				_finish_vote()
		"effect":
			t += delta
			if t >= effect_s:
				end_effect()


func _on_phase(p: int) -> void:
	match p:
		Match.Phase.COUNTDOWN:
			_abort()
			votes_done = 0
			chaos = 0.0
		Match.Phase.SUDDEN_DEATH:
			if enabled and state == "idle" and votes_done < Tuning.VOTE_MAX_PER_MATCH:
				start_vote()
		Match.Phase.OVER:
			_abort()


## Начать голосование: три варианта, итоговые проценты (решены сразу — детерминированно по зерну), панель, табло, толпа.
func start_vote() -> void:
	if state != "idle":
		return
	var mismatch := anomaly == "vote_mismatch" and votes_done == 0
	var pool: Array = OPTIONS.keys()
	options.clear()
	if mismatch:
		pool.erase("low_gravity")
		options.append(_option("low_gravity"))
	while options.size() < 3:
		var id: String = pool[_rng.randi_range(0, pool.size() - 1)]
		pool.erase(id)
		options.append(_option(id))
	if mismatch:
		target_pct = ANOMALY_PCT.duplicate()
	else:
		var w: Array = []
		for o in options:
			w.append(_rng.randf_range(0.6, 1.4) + chaos * float(o.get("chaos", 0.0)) * 1.5)
		target_pct = _to_percent(w)
	shown_pct = []
	for i in options.size():
		shown_pct.append(100.0 / options.size())
	state = "voting"
	t = 0.0
	if arena.has_method("excite"):
		arena.call("excite", 0.6)
	_set_board("AUDIENCE EVENT")
	if panel != null:
		panel.call("show_vote", options, _panel_n0_line("start"))
	vote_started.emit(options)


func _finish_vote() -> void:
	var wi := 0
	for i in target_pct.size():
		if int(target_pct[i]) > int(target_pct[wi]):
			wi = i
	var winner: Dictionary = options[wi]
	var mismatch := anomaly == "vote_mismatch" and votes_done == 0
	var applied: Dictionary = INVERSION if mismatch else winner
	votes_done += 1
	result = {"options": options.map(func(o: Dictionary) -> String: return String(o["id"])), "pct": target_pct.duplicate(),
		"winner": String(winner["id"]), "winner_title": String(winner["title"]), "applied": String(applied["id"]),
		"applied_title": String(applied["title"]), "anomaly": mismatch, "fight_time": snappedf(match_node.fight_time, 0.01)}
	history.append(result)
	_apply(applied)
	state = "effect"
	t = 0.0
	chaos = 0.0
	if arena.has_method("excite"):
		arena.call("excite", 1.0)
	_set_board("%s WINS" % String(winner["title"]))
	if panel != null:
		panel.call("set_percents", target_pct)
		panel.call("show_result", String(winner["title"]), String(applied["title"]) if mismatch else "",
			_panel_n0_line("anomaly") if mismatch else "")
	if mismatch:
		_glitch_board(String(winner["title"]), String(applied["title"]))
		var n0 := get_parent().get_node_or_null("N0")
		if n0 != null and n0.has_method("flash_expression"):
			n0.call("flash_expression", "glitch", 2.5)
	vote_finished.emit(result)


## Субтитр N0 в панели — только если на площадке нет N0 с облачком (scripts/n0/n0_host.gd сам говорит на vote_started / vote_finished).
func _panel_n0_line(key: String) -> String:
	var host := get_parent().get_node_or_null("N0/Host")
	return "" if host != null and host.has_method("say") else String(N0_LINES[key])


## Конец действия: поле по регламенту, обломки убрать, табло — как было.
func end_effect() -> void:
	if state != "effect":
		return
	state = "idle"
	t = 0.0
	_restore_field()
	_clear_debris()
	_set_board(_board_text)
	effect_ended.emit()


func _abort() -> void:
	if state == "idle":
		return
	state = "idle"
	t = 0.0
	_restore_field()
	_clear_debris()
	_set_board(_board_text)
	if panel != null:
		panel.call("hide_now")


func _apply(o: Dictionary) -> void:
	if bool(o.get("debris", false)):
		_drop_debris()
		return
	arena.call("set_field", float(o.get("g", 0.2)), o.get("dir", Vector2(0.0, -1.0)))


func _restore_field() -> void:
	if arena != null and arena.has_method("set_field"):
		arena.call("set_field", Tuning.GRAVITY / Tuning.G_EARTH, Vector2(0.0, -1.0))


func _option(id: String) -> Dictionary:
	var o: Dictionary = OPTIONS[id].duplicate()
	o["id"] = id
	if id == "side_pull":
		o["dir"] = Vector2(1.0 if _rng.randf() < 0.5 else -1.0, 0.0)
		o["title"] = "SIDE PULL %s" % ("→" if (o["dir"] as Vector2).x > 0.0 else "←")
	return o


## Веса → целые проценты с суммой ровно 100 (остаток — самым большим долям).
static func _to_percent(w: Array) -> Array:
	var sum := 0.0
	for x in w:
		sum += float(x)
	var raw: Array = []
	var out: Array = []
	var total := 0
	for x in w:
		var r := float(x) / maxf(sum, 0.0001) * 100.0
		raw.append(r)
		out.append(int(floor(r)))
		total += int(floor(r))
	var order := range(w.size())
	order.sort_custom(func(a: int, b: int) -> bool: return float(raw[a]) - floor(float(raw[a])) > float(raw[b]) - floor(float(raw[b])))
	var i := 0
	while total < 100:
		out[order[i % order.size()]] += 1
		total += 1
		i += 1
	return out


static func _normalised(v: Array) -> Array:
	var w: Array = []
	for x in v:
		w.append(maxf(float(x), 0.001))
	return _to_percent(w)


func _drop_debris() -> void:
	var ps := load(CRATE_SCENE) as PackedScene
	if ps == null:
		return
	var b: AABB = arena.call("bounds") if arena.has_method("bounds") else AABB(Vector3(-12, 0, -1), Vector3(24, 18, 2))
	for i in Tuning.VOTE_DEBRIS_COUNT:
		var c := ps.instantiate() as Node3D
		c.name = "VoteDebris_%d" % i
		var x := lerpf(b.position.x + 5.0, b.end.x - 5.0, (float(i) + _rng.randf_range(0.2, 0.8)) / Tuning.VOTE_DEBRIS_COUNT)
		c.position = Vector3(x, b.end.y - 5.0 - _rng.randf_range(0.0, 2.0), 0.0)
		get_parent().add_child(c)
		if c is RigidBody3D:
			(c as RigidBody3D).linear_velocity = Vector3(0.0, -4.0, 0.0)
			(c as RigidBody3D).angular_velocity = Vector3(0.0, 0.0, _rng.randf_range(-2.0, 2.0))
		debris.append(c)


func _clear_debris() -> void:
	for c in debris:
		if is_instance_valid(c):
			c.queue_free()
	debris.clear()


func _set_board(text: String) -> void:
	if _board != null and is_instance_valid(_board):
		_board.text = text


## Аномалия на табло: «LOW GRAVITY WINS» мигает с «GRAVITY INVERSION» и остаётся на нём (реальное время).
func _glitch_board(said: String, did: String) -> void:
	for i in 6:
		var txt := ("%s WINS" % said) if i % 2 == 0 else did
		get_tree().create_timer(0.25 * (i + 1), true, false, true).timeout.connect(func() -> void:
			if state == "effect":
				_set_board(txt))
