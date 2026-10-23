## Визуальный проход по пяти режимам 0.0.5 (docs/plan-demo/VISUAL_PASS_2310.md): ставит сцену режима, за людей играют боты, и пишет
## ряд кадров С HUD — по таймеру и по событиям режима (захват зоны, фаза/слабое место/волна босса, деталь прикручена и KO, выбит/пойман
## мяч, экраны «Испытания»), до итогов матча. Кадры — PNG в окне как есть (<out_dir>/<mode>/NN_<tag>.png), рядом frames.log: время,
## событие, кто из живых бойцов вне кадра (центр масс за краем экрана или за камерой). Нужно окно — только через tools/godot_nofocus.sh:
##   GODOT_BIN=/usr/local/bin/godot gtimeout 900 godot/tools/godot_nofocus.sh --path godot --resolution 1600x900 \
##     res://tests/mode_visual_pass.tscn -- "only=boss,out_dir=/abs/dir,lang=ru,max_s=420,every=8"
## only — режимы через «+» (domination, boss, scavenger, dodgeball, gauntlet); lang — язык игры (ru/en); max_s — предел секунд на режим
## (дошёл — кадр «timeout» и следующий); every — кадр по таймеру раз в столько секунд; human_cam=1 — камера ведёт P1 как человека
## (у босса и «Собери себя» без людей кадр держит всех живых — игрок такого не видит); g_fights — сколько боёв «Испытания» снять
## (1-й с форой автопилоту, чтобы дойти до антракта; потом — итог). Сохранения: «Испытание» — user://_visual_pass_gauntlet.cfg.
## В конце: строка JSON {"ok", "modes": [{id, frames, over, reason, t, offscreen}]}; ok = каждый режим дошёл до итогов (не завис).
extends Node

const SCENES := {
	"domination": "res://scenes/playground_domination.tscn",
	"boss": "res://scenes/playground_boss.tscn",
	"scavenger": "res://scenes/playground_scavenger.tscn",
	"dodgeball": "res://scenes/playground_dodgeball.tscn",
	"gauntlet": "res://scenes/playground_gauntlet.tscn",
}
const ORDER := ["domination", "boss", "scavenger", "dodgeball", "gauntlet"]
## Сигналы матча → [метка кадра, задержка кадра, сколько кадров на метку]
const EVENTS := {
	"zone_event": ["zone", 0.4, 4],
	"boss_phase_changed": ["phase", 0.6, 3],
	"weak_changed": ["weak", 0.5, 3],
	"wave_warning": ["wave_warn", 0.3, 2],
	"wave": ["wave", 0.2, 2],
	"boss_part_lost": ["boss_part", 0.3, 3],
	"part_attached": ["attach", 0.2, 3],
	"knocked": ["out", 0.25, 4],
	"caught": ["catch", 0.2, 3],
	"round_won": ["round", 0.8, 3],
	"ko": ["ko", 0.5, 4],
}

var out_dir := ""
var only: Array = []
var lang := "ru"
var max_s := 420.0
var every := 8.0
var human_cam := true
var g_fights := 2
var report: Array = []

var _dir := ""
var _n := 0
var _log: FileAccess
var _mode := ""
var _root: Node = null
var _match: Node = null
var _tag_n: Dictionary = {}
var _pending: Array = []        # [[осталось с, метка]]
var _over := false
var _over_reason := ""
var _t := 0.0
var _off_samples := 0
var _off_hits: Dictionary = {}  # имя → сколько раз вне кадра (замер раз в 0.5 с)
var _p1: Doll = null
var _g_seen := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for part in String(arg).split(","):
			var kv := part.split("=")
			if kv.size() != 2:
				continue
			match kv[0]:
				"out_dir": out_dir = kv[1]
				"only": only = Array(kv[1].split("+"))
				"lang": lang = kv[1]
				"max_s": max_s = float(kv[1])
				"every": every = float(kv[1])
				"human_cam": human_cam = kv[1] != "0"
				"g_fights": g_fights = int(kv[1])
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://visual_pass")
	_run.call_deferred()


func _run() -> void:
	var lang_before := String(Loc.current)
	Loc.set_language(lang)
	var gauntlet_save := GauntletRun.save_path
	GauntletRun.save_path = "user://_visual_pass_gauntlet.cfg"
	var vs := get_viewport().get_visible_rect().size
	print("=== MODE VISUAL PASS %dx%d lang=%s → %s ===" % [vs.x, vs.y, lang, out_dir])
	for id in ORDER:
		if not only.is_empty() and not only.has(id):
			continue
		await _mode_pass(String(id))
	GauntletRun.erase_record()
	GauntletRun.save_path = gauntlet_save
	Loc.set_language(lang_before)
	var ok := report.all(func(x: Dictionary) -> bool: return bool(x["over"]))
	print(JSON.stringify({"ok": ok, "modes": report}))
	print("=== %s ===" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


# ------------------------------------------------------------------ режим

func _mode_pass(id: String) -> void:
	_mode = id
	_dir = "%s/%s" % [out_dir, id]
	DirAccess.make_dir_recursive_absolute(_dir)
	_log = FileAccess.open(_dir + "/frames.log", FileAccess.WRITE)
	_n = 0
	_tag_n.clear()
	_pending.clear()
	_over = false
	_over_reason = ""
	_t = 0.0
	_off_samples = 0
	_off_hits.clear()
	Engine.time_scale = 1.0
	SquadSettings.reset()
	var root := (load(SCENES[id]) as PackedScene).instantiate()
	if "p1_bot" in root:
		root.set("p1_bot", true)
	var mt := root.get_node_or_null("Match")
	if mt != null and "focus_index" in mt:
		mt.set("focus_index", 0)
	if id == "gauntlet":
		root.set("use_workshop", false)
		root.set("fight_time_limit_s", 60.0)
	add_child(root)
	_root = root
	await _frames(2)
	if id == "gauntlet":
		await _gauntlet()
	else:
		_bind_match(root.get("match_node") if "match_node" in root else root.get_node_or_null("Match"))
		await _play(max_s)
	var row := {"id": id, "frames": _n, "over": _over, "reason": _over_reason, "t": snappedf(_t, 0.1),
		"offscreen": _off_summary()}
	report.append(row)
	_line("RESULT " + JSON.stringify(row))
	print("  %s %s" % ["ok  " if _over else "FAIL", JSON.stringify(row)])
	_log.close()
	root.queue_free()
	_root = null
	_match = null
	await _frames(6)
	Engine.time_scale = 1.0
	Stasis.set_on(false)
	SquadSettings.reset()


func _bind_match(m: Node) -> void:
	_match = m
	if m == null:
		return
	for s in EVENTS:
		if m.has_signal(s):
			m.connect(s, _on_event.bind(String(s)).unbind(_argc(m, String(s))))
	m.connect("match_over", func(_w: Variant, res: Dictionary) -> void:
		_over = true
		_over_reason = String(res.get("reason", ""))
		_line("match_over reason=%s winner_team=%s" % [_over_reason, str(res.get("winner_team", res.get("winner", "")))]))
	if m.has_signal("phase_changed"):
		m.connect("phase_changed", func(p: int) -> void:
			if p == Match.Phase.FIGHT:
				_shot_later(1.5, "fight_start"))


static func _argc(o: Object, sig: String) -> int:
	for s in o.get_signal_list():
		if String(s["name"]) == sig:
			return (s["args"] as Array).size()
	return 0


func _on_event(what: String) -> void:
	var e: Array = EVENTS[what]
	var tag := String(e[0])
	if int(_tag_n.get(tag, 0)) >= int(e[2]):
		return
	for p in _pending:
		if String(p[1]).begins_with(tag):
			return
	_tag_n[tag] = int(_tag_n.get(tag, 0)) + 1
	var extra := ""
	if what == "boss_phase_changed" and _match != null:
		extra = str(_match.get("boss_phase"))
	if what == "weak_changed" and _match != null:
		extra = String(_match.get("weak_part"))
	_shot_later(float(e[1]), tag + extra)
	if what == "ko" and _mode == "scavenger":
		_shot_later(1.4, "scatter")


func _shot_later(delay: float, tag: String) -> void:
	_pending.append([delay, tag])


## Матч идёт до итогов (и ещё 6 с — экран итогов) или до limit секунд.
func _play(limit: float) -> void:
	var next_periodic := 3.0
	var over_t := -1.0
	_shot_later(0.3, "start")
	while _t < limit:
		await get_tree().physics_frame
		var dt := 1.0 / float(Engine.physics_ticks_per_second)
		_t += dt
		_cam_focus()
		if int(_t / dt) % 30 == 0:
			_sample_offscreen()
		if _t >= next_periodic:
			next_periodic += every
			if over_t < 0.0:
				_shot_later(0.0, "t%03d" % int(_t))
		var due: Array = []
		for p in _pending:
			p[0] = float(p[0]) - dt
			if float(p[0]) <= 0.0:
				due.append(p)
		for p in due:
			_pending.erase(p)
			await _shot(String(p[1]))
		if _over and over_t < 0.0:
			over_t = _t
			for d in [1.0, 3.0, 6.0]:
				_shot_later(d, "end%d" % int(d))
		if over_t >= 0.0 and _t > over_t + 6.5 and _pending.is_empty():
			return
	await _shot("timeout")
	_line("TIMEOUT: матч не кончился за %.0f с" % limit)


## Босс, «Собери себя»: без людей кадр держит всех живых; игрок видит себя и тех, кто рядом — P1 на время выбора фокуса «человек».
func _cam_focus() -> void:
	if not human_cam or _root == null or not _root.has_method("_tick_focus") or _mode == "domination":
		return
	if _root.is_physics_processing():
		_root.set_physics_process(false)
	var p1: Doll = _root.call("doll", 0) if _root.has_method("doll") else null
	if p1 == null or not is_instance_valid(p1):
		_root.call("_tick_focus")
		return
	_p1 = p1
	var was := p1.external_input
	p1.external_input = false
	_root.call("_tick_focus")
	p1.external_input = was


# ------------------------------------------------------------------ «Испытание»

func _gauntlet() -> void:
	var pg := _root as GauntletPlayground
	await _sec(1.2)
	await _shot("start_screen")
	_g_seen = 0
	pg.fight_created.connect(func(f: Node) -> void:   # лямбда ловит локальные по значению — счётчик в поле
		_g_seen += 1
		var d1 := f.get_node("P1") as Doll
		if _g_seen == 1:   # фора бою 1, как gauntlet_probe bots: иначе до антракта не дойти
			d1.thrust_mult *= 2.0
			d1.incoming_mult = 0.15
		_bind_fight.call_deferred(f))
	pg.screen_changed.connect(func(s: int) -> void:
		if s == GauntletPlayground.Screen.BREAK:
			pg.autopilot = false)   # антракт снимаем руками: show_break смотрит autopilot после смены экрана
	pg.autopilot = true
	pg.start_run()
	var t0 := 0.0
	while t0 < max_s:
		_over = false
		await _fight_until_screen(pg, max_s - t0)
		t0 = _t
		if pg.screen == GauntletPlayground.Screen.BREAK:
			await _sec(1.5)   # портрет соперника рисуется не сразу
			await _shot("break")
			pg.apply_repair(0)
			await _sec(0.5)
			await _shot("break_repaired")
			if _g_seen >= g_fights:
				pg.give_up_to_result()
				await _sec(1.0)
				await _shot("result")
				_over = true
				_over_reason = "result_screen"
				return
			pg.autopilot = true
			pg.start_fight()
			continue
		if pg.screen == GauntletPlayground.Screen.RESULT:
			await _sec(1.0)
			await _shot("result")
			_over = true
			_over_reason = "result_screen"
			return
		break
	_over = false


func _bind_fight(f: Node) -> void:
	_bind_match(f.get_node_or_null("Match"))


## Бой идёт, пока площадка не сменила экран (антракт/итог).
func _fight_until_screen(pg: GauntletPlayground, limit: float) -> void:
	var next_periodic := _t + 3.0
	var start := _t
	var over_t := -1.0
	_shot_later(0.4, "fight%d_start" % pg.fights_started)
	while _t - start < limit:
		await get_tree().physics_frame
		var dt := 1.0 / float(Engine.physics_ticks_per_second)
		_t += dt
		if int(_t / dt) % 30 == 0 and _match != null and is_instance_valid(_match):
			_sample_offscreen()
		if _t >= next_periodic and over_t < 0.0:
			next_periodic += every
			_shot_later(0.0, "f%d_t%03d" % [pg.fights_started, int(_t - start)])
		var due: Array = []
		for p in _pending:
			p[0] = float(p[0]) - dt
			if float(p[0]) <= 0.0:
				due.append(p)
		for p in due:
			_pending.erase(p)
			if pg.screen == GauntletPlayground.Screen.FIGHT:
				await _shot(String(p[1]))
		if _over and over_t < 0.0:
			over_t = _t
			_shot_later(1.0, "f%d_end1" % pg.fights_started)
			_shot_later(2.5, "f%d_end2" % pg.fights_started)
		if pg.screen != GauntletPlayground.Screen.FIGHT:
			_pending.clear()
			return
	await _shot("timeout")
	_line("TIMEOUT: бой не кончился")


# ------------------------------------------------------------------ кадр и замеры

func _shot(tag: String) -> void:
	# Окно свёрнуто или закрыто другим окном (macOS occlusion) — Godot не рисует, frame_post_draw не придёт: кадр пропускаем, не виснем.
	if not DisplayServer.window_can_draw():
		_line("%6.1f  %-16s SKIP (окно не рисуется)" % [_t, tag])
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	_n += 1
	var path := "%s/%02d_%s.png" % [_dir, _n, tag]
	img.save_png(path)
	_line("%6.1f  %-16s off=%s  %s" % [_t, tag, ",".join(_offscreen()), _state()])


## Живые бойцы, чей центр масс вне кадра.
func _offscreen() -> PackedStringArray:
	var out: PackedStringArray = []
	var cam := get_viewport().get_camera_3d()
	if cam == null or _match == null or not is_instance_valid(_match) or not _match.has_method("alive_dolls"):
		return out
	var r := get_viewport().get_visible_rect()
	for d in _match.call("alive_dolls"):
		if not is_instance_valid(d):
			continue
		var p := (d as Doll).centre_of_mass()
		if cam.is_position_behind(p) or not r.has_point(cam.unproject_position(p)):
			out.append(String((d as Node).name))
	return out


func _sample_offscreen() -> void:
	_off_samples += 1
	for n in _offscreen():
		_off_hits[n] = int(_off_hits.get(n, 0)) + 1


func _off_summary() -> Dictionary:
	var out := {}
	for n in _off_hits:
		out[n] = snappedf(float(_off_hits[n]) / maxf(_off_samples, 1), 0.01)
	return out


func _state() -> String:
	if _match == null or not is_instance_valid(_match):
		return ""
	var bits: PackedStringArray = []
	for k in ["play_state", "score", "boss_phase", "weak_part", "round_n", "points"]:
		if k in _match:
			bits.append("%s=%s" % [k, str(_match.get(k))])
	if "fight_time" in _match:
		bits.append("ft=%.1f" % float(_match.get("fight_time")))
	return " ".join(bits)


func _line(s: String) -> void:
	if _log != null:
		_log.store_line(s)
		_log.flush()


func _sec(s: float) -> void:
	var left := s
	while left > 0.0:
		await get_tree().physics_frame
		var dt := 1.0 / float(Engine.physics_ticks_per_second)
		left -= dt
		_t += dt


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
