## Проба «Бомбы касанием» (docs/plan-demo/BOMB.md) на настоящей площадке scenes/playground_bomb.tscn (купол, пятеро, BombMatch,
## BombHud, бомба на кукле).
##   rules (все пятеро — боты с выключенными мозгами, куклы ставит проба): пятеро, урона нет (incoming_mult 0), бомба у одного, он быстрее
##     (×1.2), фитиль 20–30 с (и 300 бросков roll_fuse — в диапазоне); касание передаёт бомбу; вернуть тому, от кого получил, в течение
##     1 с нельзя (касание было — запрет держал), после — можно; фитиль при передаче не сбрасывается; удар куклы о куклу — без урона, с
##     отбросом; писк весь фитиль, темп растёт к концу (средняя пауза по пятым долям фитиля не растёт, конец быстрее начала втрое);
##     взрыв ровно по фитилю выбивает только держателя, соседей рядом раскидывает без урона; через BOMB_NEXT_S новая бомба у живого;
##     партия кончается одним живым (победа ему); следующая партия — все снова живы; матч до BOMB_WINS_TO_WIN побед → итоги (победитель, места, табличка
##     HUD); R (restart) — всё заново;
##   bots (все пятеро — боты): матч до wins побед доигрывается; в каждой партии бомба передавалась ≥ 3 раз, взрывов ровно n − 1 (каждый
##     выбил одного), каждый взрыв — ровно по фитилю 20–30 с, возврата раньше 1 с не было, новая бомба — у живого; ударов много, урона 0;
##     никто не застрял (на месте < STUCK_LIMIT_S, держатель на месте < HOLDER_IDLE_LIMIT_S, жмёт тягу и стоит < PRESS_LIMIT_S), все
##     в границах арены.
## Обе секции: ошибок скриптов и ошибок движка (errors_engine — например, «!is_inside_tree()» мембраны купола при перезапуске) — 0.
## Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/bomb_probe.tscn -- "only=rules|bots|rules+bots,max_s=1500,level=2,wins=3,trace=1,out=<json>"
## → JSON между === BOMB PROBE === и === OK / FAIL ===, exit 0/1. errors_script — SCRIPT ERROR за прогон (Logger).
extends Node

const SCENE := "res://scenes/playground_bomb.tscn"
const TICK := 1.0 / 60.0
const STUCK_M := 1.5
const STUCK_LIMIT_S := 40.0         # не сдвинулся на STUCK_M (дольше фитиля с паузой — уже не «переждал в углу»)
const HOLDER_IDLE_LIMIT_S := 6.0    # держатель не сдвинулся на STUCK_M
const PRESS_LIMIT_S := 4.0          # жмёт тягу, а торс стоит

## Счётчик SCRIPT ERROR за прогон (как squad_probe): ошибка скрипта обрывает только свою функцию — проба могла бы молча потерять проверки.
## Ошибки движка (не скрипта) — отдельно: «!is_inside_tree()» из null_field.gd (мембрана перебирает вынутые детали) ловит перезапуск.
class ScriptErrors extends Logger:
	var count := 0
	var first := ""
	var engine := 0
	var engine_first := ""
	var _mx := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		_mx.lock()
		if error_type == ERROR_TYPE_SCRIPT:
			count += 1
			if first == "":
				first = "%s %s (%s:%d %s)" % [code, rationale, file, line, function]
		elif error_type == ERROR_TYPE_ERROR:
			engine += 1
			if engine_first == "":
				var where := ""
				if not script_backtraces.is_empty() and script_backtraces[0].get_frame_count() > 0:
					where = " ← %s:%d" % [script_backtraces[0].get_frame_file(0), script_backtraces[0].get_frame_line(0)]
				engine_first = "%s (%s:%d)%s" % [code, file, line, where]
		_mx.unlock()


var ok := true
var checks: Array = []
var info := {}
var pg: BombPlayground
var bm: BombMatch
var over_results: Dictionary = {}
var over_count := 0
var errs := ScriptErrors.new()


func _check(id: String, cond: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": cond, "detail": str(detail)})
	if not cond:
		ok = false
	print("  %-30s %s  %s" % [id, "ok  " if cond else "FAIL", str(detail)])


func _args() -> Dictionary:
	var out := {"only": "", "max_s": "1500", "level": "2", "trace": "0", "out": "", "wins": str(Tuning.BOMB_WINS_TO_WIN), "seed": "0"}
	for a in OS.get_cmdline_user_args():
		for part in String(a).split(","):
			var kv := part.split("=")
			if kv.size() == 2 and out.has(kv[0]):
				out[kv[0]] = kv[1]
	return out


func _want(a: Dictionary, section: String) -> bool:
	return String(a["only"]) == "" or section in String(a["only"]).split("+")


func _ready() -> void:
	OS.add_logger(errs)
	print("=== BOMB PROBE ===")
	var a := _args()
	if _want(a, "rules"):
		await _rules()
	if _want(a, "bots"):
		await _bots(float(a["max_s"]), int(a["level"]), int(a["wins"]), String(a["trace"]) == "1", int(a["seed"]))
	await _unload()
	_check("errors_script", errs.count == 0, "ошибок скриптов %d; первая: %s" % [errs.count, errs.first])
	_check("errors_engine", errs.engine == 0, "ошибок движка %d; первая: %s" % [errs.engine, errs.engine_first])
	var report := {"ok": ok, "checks": checks, "info": info}
	print(JSON.stringify(report, " "))
	if String(a["out"]) != "":
		var f := FileAccess.open(String(a["out"]), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(report, " "))
			f.close()
	print("=== OK ===" if ok else "=== FAIL ===")
	OS.remove_logger(errs)
	get_tree().quit(0 if ok else 1)


# ------------------------------------------------------------------ помощники

func _load(level := 2, countdown := 0.3, seed_ := 0) -> void:
	await _unload()
	Engine.time_scale = 1.0
	pg = (load(SCENE) as PackedScene).instantiate() as BombPlayground
	pg.p1_bot = true
	pg.p2_bot = true
	pg.bot_level = level
	bm = pg.get_node("Match") as BombMatch
	bm.feel_enabled = false
	bm.countdown_s = countdown
	bm.rng_seed = seed_
	over_results = {}
	over_count = 0
	bm.match_over.connect(func(_w: Doll, r: Dictionary) -> void:
		over_results = r
		over_count += 1)
	add_child(pg)
	await _until(func() -> bool: return bm.play_state == "play" and bm.dolls().size() == Tuning.BOMB_DOLLS, 8.0)


func _unload() -> void:
	if pg != null and is_instance_valid(pg):
		remove_child(pg)
		pg.queue_free()
		pg = null
		await get_tree().physics_frame


func _until(cond: Callable, max_s: float) -> bool:
	for i in int(max_s / TICK):
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _wait(s: float) -> void:
	for i in int(round(s / TICK)):
		await get_tree().physics_frame


func _doll(index: int) -> Doll:
	for d in bm.dolls():
		if is_instance_valid(d) and (d as Doll).player_index == index:
			return d
	return null


func _brains_off() -> void:
	for d in bm.dolls():
		var b := (d as Node).get_node_or_null("BombBrain")
		if b != null:
			b.set_physics_process(false)
		(d as Doll).input_vec = Vector2.ZERO


## Поставить куклу торсом в точку p (все детали — сдвигом, скорости — 0).
func _place(d: Doll, p: Vector2) -> void:
	var t := d.torso().global_position
	var off := Vector3(p.x - t.x, p.y - t.y, 0.0)
	for b in d.parts.values():
		var rb := b as RigidBody3D
		rb.global_position += off
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		rb.reset_physics_interpolation()


func _launch(d: Doll, v: Vector3) -> void:
	for b in d.parts.values():
		(b as RigidBody3D).linear_velocity = v


func _others(except: Array) -> Array:
	var out: Array = []
	for d in bm.dolls():
		if not except.has(d):
			out.append(d)
	return out


func _speed(d: Doll) -> float:
	return d.torso().linear_velocity.length()


# ------------------------------------------------------------------ правила

func _rules() -> void:
	print("--- rules")
	await _load(2, 0.3, 4242)
	_brains_off()
	_check("five_dolls", bm.dolls().size() == Tuning.BOMB_DOLLS, "кукол %d" % bm.dolls().size())
	var mults := []
	for d in bm.dolls():
		mults.append((d as Doll).incoming_mult)
	_check("no_damage_mult", mults.all(func(m: float) -> bool: return m == 0.0), "incoming_mult %s" % str(mults))
	var h := bm.holder
	_check("holder_start", h != null and h.alive and bm.play_state == "play", "держатель %s, фаза %s" % [BombMatch.doll_name(h), bm.play_state])
	if h == null:
		return
	var fast := h.thrust_mult == Tuning.BOMB_HOLDER_THRUST_MULT and h.speed_mult == Tuning.BOMB_HOLDER_SPEED_MULT
	for d in _others([h]):
		fast = fast and (d as Doll).thrust_mult == 1.0 and (d as Doll).speed_mult == 1.0
	_check("holder_faster", fast, "тяга ×%.2f, скорость ×%.2f, у остальных 1" % [h.thrust_mult, h.speed_mult])
	var fuse0 := bm.fuse_s
	_check("fuse_range", fuse0 >= Tuning.BOMB_FUSE_MIN_S and fuse0 <= Tuning.BOMB_FUSE_MAX_S, "фитиль %.2f с" % fuse0)
	var lo := INF
	var hi := -INF
	for i in 300:
		var f := bm.roll_fuse()
		lo = minf(lo, f)
		hi = maxf(hi, f)
	_check("fuse_roll", lo >= Tuning.BOMB_FUSE_MIN_S and hi <= Tuning.BOMB_FUSE_MAX_S and hi - lo > (Tuning.BOMB_FUSE_MAX_S - Tuning.BOMB_FUSE_MIN_S) * 0.8, "300 бросков: %.2f…%.2f с" % [lo, hi])
	_check("bomb_visual", bm.carry != null and bm.carry.visible and bm.carry.holder == h, "бомба видна на держателе")
	var beeps_seen := {"list": []}
	var grab_beeps := func(_v: Doll, _p: Vector3) -> void:
		beeps_seen["list"] = bm.beeps.duplicate()
	bm.bomb_exploded.connect(grab_beeps, CONNECT_ONE_SHOT)

	# --- касание передаёт бомбу
	var others := _others([h])
	var a := others[0] as Doll
	_place(h, Vector2(0.0, 1.3))
	var far := [Vector2(-12.0, 1.3), Vector2(12.0, 1.3), Vector2(-8.0, 1.3), Vector2(8.0, 1.3)]
	for i in others.size():
		_place(others[i] as Doll, far[i])
	await _wait(0.3)
	_check("no_touch_no_pass", bm.holder == h and bm.passes.is_empty(), "кукла одна — бомба у %s, передач %d" % [BombMatch.doll_name(bm.holder), bm.passes.size()])
	var ft_before := bm.fuse_t
	_place(a, Vector2(1.05, 1.3))
	var passed := await _until(func() -> bool: return bm.holder == a, 1.0)
	_check("touch_passes", passed and bm.got_from == h and bm.passes.size() == 1,
		"%s → %s, передач %d" % [BombMatch.doll_name(h), BombMatch.doll_name(bm.holder), bm.passes.size()])
	_check("receiver_faster", a.thrust_mult == Tuning.BOMB_HOLDER_THRUST_MULT and h.thrust_mult == 1.0, "тяга нового ×%.2f, прежнего ×%.2f" % [a.thrust_mult, h.thrust_mult])
	var t_pass := bm.round_time
	# --- запрет возврата: держим их в касании весь запрет
	var stayed := true
	var blocked0 := bm.blocked_returns
	while bm.round_time - t_pass < Tuning.BOMB_RETURN_LOCK_S - 2.0 * TICK:
		a.torso().linear_velocity.x = -1.2
		h.torso().linear_velocity.x = 1.2
		await get_tree().physics_frame
		if bm.holder != a:
			stayed = false
			break
	_check("return_locked", stayed and bm.blocked_returns > blocked0,
		"%.2f с бомба у %s, касаний с отдавшим под запретом: %d" % [bm.round_time - t_pass, BombMatch.doll_name(bm.holder), bm.blocked_returns - blocked0])
	var push_back := func() -> bool:
		a.torso().linear_velocity.x = -1.2
		h.torso().linear_velocity.x = 1.2
		return bm.holder == h
	var back := await _until(push_back, 1.5)
	var dt_back := float(bm.passes[-1]["t"]) - float(bm.passes[0]["t"]) if bm.passes.size() >= 2 else -1.0
	_check("return_after_lock", back and dt_back >= Tuning.BOMB_RETURN_LOCK_S, "назад к %s через %.2f с" % [BombMatch.doll_name(bm.holder), dt_back])
	_check("fuse_not_reset", bm.fuse_s == fuse0 and bm.fuse_t > ft_before + 1.0,
		"фитиль %.2f → %.2f с, сгорело %.2f → %.2f" % [fuse0, bm.fuse_s, ft_before, bm.fuse_t])
	_place(a, Vector2(-12.0, 1.3))
	_place(h, Vector2(0.0, 1.3))
	await _wait(0.4)

	# --- удар куклы о куклу: без урона, с отбросом
	var c := others[1] as Doll
	var dv := others[2] as Doll
	_place(c, Vector2(5.0, 1.6))
	_place(dv, Vector2(8.2, 1.6))
	await _wait(0.2)
	var hit := {"n": 0, "dmg": 0.0}
	var on_hit := func(v: Doll, att: Node, dmg: float, _k: String, _p: Vector3) -> void:
		if v == dv and att == c:
			hit["n"] = int(hit["n"]) + 1
		hit["dmg"] = float(hit["dmg"]) + dmg
	bm.hit.connect(on_hit)
	var v0 := _speed(dv)
	_launch(c, Vector3(9.0, 0.0, 0.0))
	var peak := 0.0
	for i in 50:
		await get_tree().physics_frame
		peak = maxf(peak, _speed(dv))
	bm.hit.disconnect(on_hit)
	_check("hit_no_damage", int(hit["n"]) > 0 and float(hit["dmg"]) == 0.0 and dv.hp == dv.max_hp and c.hp == c.max_hp and dv.alive,
		"ударов %d, урон %.1f, HP %.0f / %.0f" % [int(hit["n"]), float(hit["dmg"]), dv.hp, dv.max_hp])
	_check("hit_knockback", peak > maxf(v0, 0.5) + 2.0, "скорость жертвы %.2f → пик %.2f м/с" % [v0, peak])
	_check("hit_not_bomb", bm.holder == h, "бомба осталась у %s" % BombMatch.doll_name(bm.holder))

	# --- взрыв ровно по фитилю: соседи рядом
	await _until(func() -> bool: return bm.fuse_s - bm.fuse_t < 1.0, 40.0)
	var n1 := others[1] as Doll
	var n2 := others[2] as Doll
	_place(h, Vector2(0.0, 1.3))
	_place(n1, Vector2(-2.3, 1.3))
	_place(n2, Vector2(2.3, 1.3))
	_place(others[0] as Doll, Vector2(-12.0, 1.3))
	_place(others[3] as Doll, Vector2(12.0, 1.3))
	var boom := {"t": -1.0}
	var grab_victim := func(v: Doll, _p: Vector3) -> void:
		boom["v"] = v
	bm.bomb_exploded.connect(grab_victim, CONNECT_ONE_SHOT)
	var exploded := await _until(func() -> bool: return bm.explosions.size() >= 1, 2.0)
	var e: Dictionary = bm.explosions[0] if exploded else {}
	var late := float(e.get("fuse_t", -1.0)) - float(e.get("fuse_s", 0.0))
	_check("explode_on_fuse", exploded and float(e["fuse_s"]) == snappedf(fuse0, 0.001) and late >= 0.0 and late <= TICK * 1.5,
		"фитиль %.3f с, взорвалась на %.3f (позже на %.1f мс)" % [fuse0, float(e.get("fuse_t", -1.0)), late * 1000.0])
	var alive_after := bm.alive_dolls()
	_check("explode_only_holder", boom.get("v") == h and not h.alive and alive_after.size() == Tuning.BOMB_DOLLS - 1 and n1.alive and n2.alive,
		"выбыл %s, живых %d" % [BombMatch.doll_name(boom.get("v")), alive_after.size()])
	var p1 := 0.0
	var p2 := 0.0
	for i in 24:
		await get_tree().physics_frame
		p1 = maxf(p1, _speed(n1))
		p2 = maxf(p2, _speed(n2))
	_check("blast_pushes_no_damage", p1 > 2.5 and p2 > 2.5 and n1.hp == n1.max_hp and n2.hp == n2.max_hp and n1.alive and n2.alive,
		"соседи: пик %.1f и %.1f м/с, HP %.0f и %.0f" % [p1, p2, n1.hp, n2.hp])
	_check("bomb_hidden_after_blast", bm.holder == null and not bm.carry.visible, "держателя нет, бомбы на кукле не видно")
	# --- темп писка
	var bl: Array = beeps_seen["list"]
	var bins := [[], [], [], [], []]
	for i in range(1, bl.size()):
		var k := clampi(int(float(bl[i - 1]) / fuse0 * 5.0), 0, 4)
		(bins[k] as Array).append(float(bl[i]) - float(bl[i - 1]))
	var means: Array = []
	for b in bins:
		var s := 0.0
		for x in b:
			s += float(x)
		means.append(snappedf(s / maxf((b as Array).size(), 1.0), 0.001))
	var mono := true
	for i in range(1, means.size()):
		mono = mono and float(means[i]) <= float(means[i - 1]) + 0.06
	var first_ok := not bl.is_empty() and float(bl[0]) < 0.05
	var last_gap := fuse0 - float(bl[-1]) if not bl.is_empty() else 99.0
	_check("beep_whole_fuse", bl.size() >= 20 and first_ok and last_gap < 0.4, "писков %d, первый %.2f с, последний за %.2f с до взрыва" % [bl.size(),
		float(bl[0]) if not bl.is_empty() else -1.0, last_gap])
	_check("beep_tempo_rises", mono and float(means[4]) < float(means[0]) / 3.0, "средняя пауза по пятым долям фитиля: %s с" % str(means))
	_check("beep_played", bm.carry.beeps_played >= bl.size(), "бомба пискнула %d раз" % bm.carry.beeps_played)
	info["rules_beeps"] = {"fuse_s": snappedf(fuse0, 0.01), "beeps": bl.size(), "bin_means": means}

	# --- новая бомба у живого
	var serial := bm.bomb_serial
	var renewed := await _until(func() -> bool: return bm.holder != null, Tuning.BOMB_NEXT_S + 0.5)
	var nh := bm.holder
	_check("new_bomb_alive", renewed and nh.alive and nh != h and bm.bomb_serial == serial + 1 and bm.fuse_s >= Tuning.BOMB_FUSE_MIN_S
		and bm.fuse_s <= Tuning.BOMB_FUSE_MAX_S and bm.fuse_t < 0.2,
		"через %.1f с бомба у %s, новый фитиль %.2f с" % [Tuning.BOMB_NEXT_S, BombMatch.doll_name(nh), bm.fuse_s])

	# --- партия кончается одним живым (взрывы — сразу, пробой)
	var rounds0 := bm.rounds.size()
	var burn := func() -> bool:
		if bm.play_state == "play":
			bm.fuse_t = bm.fuse_s
		return bm.rounds.size() > rounds0
	await _until(burn, 20.0)
	var last_alive := bm.alive_dolls()
	var r0: Dictionary = bm.rounds[-1] if not bm.rounds.is_empty() else {}
	var w := last_alive[0] as Doll if last_alive.size() == 1 else null
	var w_i := w.player_index if w != null else 0
	_check("round_one_alive", w != null and int(r0.get("winner", -2)) == w_i and bm.win_count(w) == 1 and bm.play_state == "round_end"
		and int(r0.get("explosions", 0)) == Tuning.BOMB_DOLLS - 1,
		"живых %d, партию взял %s, взрывов %d" % [last_alive.size(), BombMatch.doll_name(w), int(r0.get("explosions", 0))])
	var round2 := func() -> bool: return bm.round_i == 2 and bm.play_state == "play"
	var next_ok := await _until(round2, Tuning.BOMB_ROUND_PAUSE_S + Tuning.BOMB_COUNTDOWN_S + 1.0)
	var w_now := _doll(w_i)
	_check("next_round", next_ok and bm.alive_dolls().size() == Tuning.BOMB_DOLLS and bm.holder != null and bm.win_count(w_now) == 1,
		"партия %d, живых %d, побед у %s: %d" % [bm.round_i, bm.alive_dolls().size(), BombMatch.doll_name(w_now), bm.win_count(w_now)])

	# --- матч до BOMB_WINS_TO_WIN побед: тот же победитель (пробе так быстрее), бомба ему не достаётся
	_brains_off()
	var champ_i := w_i
	var rig := func() -> bool:
		if bm.play_state == "play" and bm.holder != null:
			if bm.holder.player_index == champ_i:
				for d in bm.alive_dolls():
					if (d as Doll).player_index != champ_i:
						bm.pass_to(d)
						break
			bm.fuse_t = bm.fuse_s
		return over_count > 0
	await _until(rig, 90.0)
	var champ := _doll(champ_i)
	var places: Array = over_results.get("places", [])
	_check("match_to_wins", over_count == 1 and over_results.get("winner") == champ and bm.win_count(champ) == Tuning.BOMB_WINS_TO_WIN
		and bm.rounds.size() == Tuning.BOMB_WINS_TO_WIN and bm.phase == Match.Phase.OVER and not places.is_empty() and places[0] == champ,
		"итогов %d, победил %s (%d побед), партий %d" % [over_count, BombMatch.doll_name(over_results.get("winner")), bm.win_count(champ), bm.rounds.size()])
	var others_lt := true
	for d in bm.dolls():
		if d != champ:
			others_lt = others_lt and bm.win_count(d) < Tuning.BOMB_WINS_TO_WIN
	_check("others_below_3", others_lt, "побед: %s" % str(bm.wins))
	await _wait(1.2)
	_check("hud_end_panel", pg.hud.end_panel.visible and pg.hud.end_title.text != "", "табличка: «%s» · %s" % [pg.hud.end_title.text, pg.hud.end_sub.text])
	# --- R: заново
	bm.restart()
	await _until(func() -> bool: return bm.play_state == "play", 6.0)
	_check("restart_resets", bm.wins.is_empty() and bm.round_i == 1 and bm.rounds.is_empty() and bm.holder != null
		and bm.alive_dolls().size() == Tuning.BOMB_DOLLS and not pg.hud.end_panel.visible,
		"партия %d, побед %s, бомба у %s" % [bm.round_i, str(bm.wins), BombMatch.doll_name(bm.holder)])


# ------------------------------------------------------------------ матч ботов

func _bots(max_s: float, level: int, wins_n: int, trace: bool, seed_: int) -> void:
	print("--- bots (уровень %d, до %d побед)" % [level, wins_n])
	await _load(level, 3.0, seed_)
	bm.wins_to_win = wins_n
	var acc := {"hits": 0, "dmg": 0.0, "bad_new": 0}
	bm.hit.connect(func(_v: Doll, a: Node, dmg: float, _k: String, _p: Vector3) -> void:
		if a is Doll:
			acc["hits"] = int(acc["hits"]) + 1
		acc["dmg"] = float(acc["dmg"]) + dmg)
	bm.bomb_passed.connect(func(from: Doll, to: Doll) -> void:
		if from == null and (to == null or not to.alive):
			acc["bad_new"] = int(acc["bad_new"]) + 1)
	# застревание — три меры: на месте (не сдвинулся на STUCK_M; убегающий может висеть в безопасной точке — предел щедрый),
	# держатель на месте (он обязан гнаться; якорь — с получения бомбы) и «упёрся» (жмёт тягу ≥ 0.5, а торс почти стоит)
	var last_pos: Dictionary = {}
	var stuck_max := 0.0
	var stuck_who := ""
	var hold_anchor := {"d": null, "p": Vector3.ZERO, "t": 0.0}
	var hold_idle_max := 0.0
	var hold_idle_who := ""
	var press_t: Dictionary = {}
	var press_max := 0.0
	var press_who := ""
	var out_of_bounds := 0
	var b: AABB = pg.arena.call("bounds")
	var t0 := Time.get_ticks_usec()
	var frames := 0
	var trace_t := 0.0
	var round_seen := bm.round_i
	while over_count == 0 and bm.fight_time < max_s:
		await get_tree().physics_frame
		frames += 1
		if bm.round_i != round_seen:
			round_seen = bm.round_i
			last_pos.clear()
			press_t.clear()
		var playing := bm.play_state == "play" or bm.play_state == "next"
		for d in bm.dolls():
			var dd := d as Doll
			if not dd.alive or not playing:
				last_pos.erase(dd.player_index)
				press_t.erase(dd.player_index)
				continue
			var c := dd.centre_of_mass()
			if c.x < b.position.x - 0.5 or c.x > b.end.x + 0.5 or c.y < b.position.y - 0.5 or c.y > b.end.y + 0.5:
				out_of_bounds += 1
			var br := dd.get_node_or_null("BombBrain") as BombBrain
			var lp: Array = last_pos.get(dd.player_index, [])
			if lp.is_empty() or (lp[0] as Vector3).distance_to(c) > STUCK_M:
				last_pos[dd.player_index] = [c, bm.fight_time]
			elif bm.fight_time - float(lp[1]) > stuck_max:
				stuck_max = bm.fight_time - float(lp[1])
				stuck_who = "%s в (%.1f, %.1f), %s" % [BombMatch.doll_name(dd), c.x, c.y, br.state if br != null else "-"]
			if dd.input_vec.length() >= 0.5 and _speed(dd) < 0.35:
				press_t[dd.player_index] = float(press_t.get(dd.player_index, 0.0)) + TICK
				if float(press_t[dd.player_index]) > press_max:
					press_max = float(press_t[dd.player_index])
					press_who = "%s в (%.1f, %.1f), %s" % [BombMatch.doll_name(dd), c.x, c.y, br.state if br != null else "-"]
			else:
				press_t.erase(dd.player_index)
		var hd := bm.holder
		if hd == null or not playing:
			hold_anchor["d"] = null
		elif hold_anchor["d"] != hd or (hold_anchor["p"] as Vector3).distance_to(hd.centre_of_mass()) > STUCK_M:
			hold_anchor = {"d": hd, "p": hd.centre_of_mass(), "t": bm.fight_time}
		elif bm.fight_time - float(hold_anchor["t"]) > hold_idle_max:
			hold_idle_max = bm.fight_time - float(hold_anchor["t"])
			var hc := hd.centre_of_mass()
			hold_idle_who = "%s в (%.1f, %.1f)" % [BombMatch.doll_name(hd), hc.x, hc.y]
		if trace and bm.fight_time - trace_t >= 10.0:
			trace_t = bm.fight_time
			var row := []
			for d in bm.dolls():
				var br := (d as Node).get_node_or_null("BombBrain") as BombBrain
				var cc := (d as Doll).centre_of_mass()
				row.append("%s:%s(%.0f,%.0f)%s%s" % [BombMatch.doll_name(d), br.state if br != null else "-", cc.x, cc.y,
					"*" if d == bm.holder else "", "" if (d as Doll).alive else "†"])
			print("  t=%6.1f партия %d побед %s передач %d  %s" % [bm.fight_time, bm.round_i, str(bm.wins), bm.passes.size(), " ".join(row)])
	var wall_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var winner: Doll = over_results.get("winner")
	_check("bots_match_done", over_count == 1 and winner != null and bm.win_count(winner) == wins_n,
		"итогов %d, победил %s (%d побед) за %.0f с игры, партий %d" % [over_count, BombMatch.doll_name(winner), bm.win_count(winner), bm.fight_time, bm.rounds.size()])
	var per_round: Array = []
	var expl_ok := true
	for r in bm.rounds:
		per_round.append(int(r["passes"]))
		expl_ok = expl_ok and int(r["explosions"]) == Tuning.BOMB_DOLLS - 1 and int(r["winner"]) >= 0
	_check("bots_passes_per_round", not per_round.is_empty() and per_round.min() >= 3, "передач по партиям: %s" % str(per_round))
	_check("bots_one_out_per_blast", expl_ok and not bm.rounds.is_empty(), "взрывов в каждой партии %d (выбивает одного), у каждой партии победитель" % (Tuning.BOMB_DOLLS - 1))
	var worst_late := 0.0
	var fuse_lo := INF
	var fuse_hi := -INF
	for e in bm.explosions:
		worst_late = maxf(worst_late, absf(float(e["fuse_t"]) - float(e["fuse_s"])))
		fuse_lo = minf(fuse_lo, float(e["fuse_s"]))
		fuse_hi = maxf(fuse_hi, float(e["fuse_s"]))
	_check("bots_fuse_exact", not bm.explosions.is_empty() and worst_late <= TICK * 1.5 and fuse_lo >= Tuning.BOMB_FUSE_MIN_S and fuse_hi <= Tuning.BOMB_FUSE_MAX_S,
		"взрывов %d, фитили %.1f…%.1f с, худшее отклонение %.1f мс" % [bm.explosions.size(), fuse_lo, fuse_hi, worst_late * 1000.0])
	var early_return := 0
	for i in range(1, bm.passes.size()):
		var p0: Dictionary = bm.passes[i - 1]
		var p1: Dictionary = bm.passes[i]
		if int(p1["bomb"]) == int(p0["bomb"]) and int(p1["to"]) == int(p0["from"]) and float(p1["t"]) - float(p0["t"]) < Tuning.BOMB_RETURN_LOCK_S - 1e-3:
			early_return += 1
	_check("bots_no_early_return", early_return == 0, "возвратов раньше %.1f с: %d (касаний под запретом %d тиков)" % [Tuning.BOMB_RETURN_LOCK_S, early_return, bm.blocked_returns])
	_check("bots_new_bomb_alive", int(acc["bad_new"]) == 0, "новая бомба у выбывшего: %d" % int(acc["bad_new"]))
	_check("bots_hits_no_damage", int(acc["hits"]) > 20 and float(acc["dmg"]) == 0.0, "ударов кукла о куклу %d, урон %.1f" % [int(acc["hits"]), float(acc["dmg"])])
	_check("bots_not_stuck", stuck_max < STUCK_LIMIT_S and hold_idle_max < HOLDER_IDLE_LIMIT_S and press_max < PRESS_LIMIT_S,
		"на месте дольше всех %.1f с (%s; предел %.0f); держатель на месте %.1f с (%s; предел %.0f); упёрся %.1f с (%s; предел %.0f)" % [
		stuck_max, stuck_who, STUCK_LIMIT_S, hold_idle_max, hold_idle_who, HOLDER_IDLE_LIMIT_S, press_max, press_who, PRESS_LIMIT_S])
	_check("bots_in_bounds", out_of_bounds == 0, "тиков за границей арены %d" % out_of_bounds)
	var states := {}
	var unstick := 0
	for d in bm.dolls():
		var br := (d as Node).get_node_or_null("BombBrain") as BombBrain
		if br != null:
			unstick += int(br.counters.get("unstick", 0))
			for k in br.counters:
				states[k] = int(states.get(k, 0)) + int(br.counters[k])
	info["bots"] = {"level": level, "wins_to_win": wins_n, "fight_s": snappedf(bm.fight_time, 0.1), "rounds": bm.rounds.duplicate(true),
		"wins": bm.wins.duplicate(), "passes": bm.passes.size(), "explosions": bm.explosions.size(), "blocked_return_ticks": bm.blocked_returns,
		"hits": acc["hits"], "stuck_max_s": snappedf(stuck_max, 0.1), "holder_idle_max_s": snappedf(hold_idle_max, 0.1),
		"press_max_s": snappedf(press_max, 0.1), "unstick_last_round": unstick, "brain_counters_last_round": states,
		"ms_per_physics_frame": snappedf(wall_ms / maxf(frames, 1), 0.01), "tally": over_results.get("tally", {})}
