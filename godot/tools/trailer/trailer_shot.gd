## Съёмочный павильон трейлера (docs/plan-demo/STEAM_TRAILER.md): один план = один запуск Godot в окне под Movie Maker.
## Спецификацию плана (JSON) пишет godot/tools/trailer/trailer.py из последовательности (teaser.json): сцена боя как в игре,
## боты RivalBrain на обе стороны, режимы (суставы, ДРАЙВ), скин HUD, язык, камера, принудительные уровни ударов, запас HP.
## Пишет события в кадрах Movie Maker (fight, light/heavy/crit/ko_crit, hit, ko, slam, break, detach, over) в out=<json> —
## монтаж режет от событий («за 1.2 с до крита»), а не от секунд, поэтому смена сида не ломает склейку.
## Кадр события = Engine.get_frames_drawn() в момент сигнала = номер кадра в ролике (Movie Maker пишет кадр на итерацию,
## время в ролике = кадр / fps). «Реальные» часы сока удара (FxClock) считаются от delta — при --fixed-fps они тоже ровные.
## Поля спецификации (все необязательные; полный список и значения по умолчанию — godot/tools/trailer/README.md):
##   scene (null_hall | scrap | ruins | void | workshop | res://…), seed, lang, hud (true/false), hud_skin, gfx, ssaa, msaa,
##   bots {p1: уровень, p2: уровень}, modes {joint_break, drive}, music, crowd, countdown, hp {p1, p2}, spawn {p1: [x, y], p2: …},
##   camera {свойство DynamicCamera: значение}, brain {свойство RivalBrain: значение} (обоим ботам, напр. retreat_s),
##   force [{at: с от начала боя, tier}], length / until + tail / max_s, require [события].
## Служебные подсказки (клавиши внизу, «L — клавиши», «Tab — управление», тосты HitJuice) и счётчик материалов забега Свалки
## (RunInventoryCounter, правый нижний угол) прячутся всегда — в ролике они читаются как отладка.
## Выход: exit 0 — всё из require случилось; 1 — нет (trailer.py пробует следующий сид); 2 — бой не начался.
## Запуск (обычно делает trailer.py):
##   godot/tools/godot_nofocus.sh --path godot --resolution 1920x1080 --fixed-fps 60 --write-movie /abs/shot.avi \
##     res://tools/trailer/trailer_shot.tscn -- shot=/abs/shot.json out=/abs/events.json
extends Node

const SCENES := {
	"null_hall": "res://scenes/playground_null_hall.tscn",   # Быстрый бой: купол Old NULL Hall
	"scrap": "res://scenes/playground_scrap.tscn",           # Свалка
	"ruins": "res://scenes/playground.tscn",                 # Руины
	"void": "res://scenes/playground_void.tscn",
	"workshop": "res://scenes/playground_workshop.tscn",
}
## hud=false: эти узлы площадки прячутся целиком (HUD, стрелки за экраном, подсказка, панель голосования зрителей).
## Слои эффектов (вспышки, рентген крита) остаются — они часть удара, а не интерфейс.
const HIDE_NO_HUD := ["HUD", "Offscreen", "AudienceVote"]
## Служебное, прячется в любом плане: строка клавиш площадки (UI/Hint) и тосты HitJuice (подсказка клавиш на старте сессии).
const HIDE_DEV_NAMES := ["UI", "JuiceToast"]
const DEV_SCAN_EVERY := 10           # кадров: панели клавиш / управления создаются на лету — ищем их заново
const MAX_WAIT_FIGHT_S := 20.0      # бой так и не начался — выход 2


## Бот за P1: тот же RivalBrain, но цель — сторона "rivals", свои — "players" (у P2 наоборот).
class MirrorBrain extends RivalBrain:
	func _brain_ready() -> void:
		super()
		players_group = "rivals"
		enemies_group = "players"


var spec: Dictionary = {}
var out_path := ""
var fps := 60
var pg: Node = null
var m: Match = null
var cam: Camera3D = null
var dolls: Array = []
var events: Array = []
var counts: Dictionary = {}
var fight_frame := -1
var stop_frame := -1
var max_frame := -1
var forces: Array = []
var ssaa := 1.0
var hide_nodes: Array = []
var dev_nodes: Array = []
var finished := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var eq := String(arg).find("=")
		if eq <= 0:
			continue
		var k := String(arg).substr(0, eq)
		var v := String(arg).substr(eq + 1)
		if k == "shot":
			var txt := FileAccess.get_file_as_string(v)
			var parsed: Variant = JSON.parse_string(txt)
			if parsed is Dictionary:
				spec = parsed
			else:
				push_error("trailer_shot: не разобран JSON плана %s" % v)
		elif k == "out":
			out_path = v
	fps = Engine.max_fps if Engine.max_fps > 0 else 60
	var ffps := _fixed_fps()
	if ffps > 0:
		fps = ffps
	_apply_globals()
	_build()


## --fixed-fps N из командной строки (Movie Maker пишет ролик с этой частотой).
func _fixed_fps() -> int:
	var args := OS.get_cmdline_args()
	for i in args.size():
		if args[i] == "--fixed-fps" and i + 1 < args.size():
			return int(args[i + 1])
	return 0


## Настройки игры на время съёмки — только в памяти: файлы настроек автора (user://*.cfg) не трогаем.
func _apply_globals() -> void:
	seed(int(spec.get("seed", 1)))
	ControlFeel.no_disk = true
	Loc.set_language(String(spec.get("lang", "ru")))
	HudSkin.set_skin(String(spec.get("hud_skin", "neon")), false)
	var modes: Dictionary = spec.get("modes", {})
	JointBreak.set_on(bool(modes.get("joint_break", false)))
	Drive.set_on(bool(modes.get("drive", false)))
	GameAudio.set_music_on(bool(spec.get("music", false)), false)
	GameAudio.set_crowd_on(bool(spec.get("crowd", true)), false)
	# качество: без авто-масштаба (при записи кадр рисуется дольше 16 мс — DynRes иначе снизил бы разрешение), пресет ultra
	Gfx.auto_scale = false
	Gfx.dyn.reset()
	Gfx.set_preset(String(spec.get("gfx", "ultra")), false)
	ssaa = clampf(float(spec.get("ssaa", 1.5)), 0.5, 2.0)
	var msaa := int(spec.get("msaa", 0))
	get_window().msaa_3d = {2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X, 8: Viewport.MSAA_8X}.get(msaa, Viewport.MSAA_DISABLED)
	_enforce_scale()


func _build() -> void:
	var sid := String(spec.get("scene", "null_hall"))
	var path: String = SCENES.get(sid, sid)
	pg = (load(path) as PackedScene).instantiate()
	var p1 := pg.get_node("P1") as Doll
	var p2 := pg.get_node("P2") as Doll
	dolls = [p1, p2]
	p1.add_to_group("players")
	p2.add_to_group("rivals")
	var spawn: Dictionary = spec.get("spawn", {})
	for key in ["p1", "p2"]:
		if spawn.has(key):
			var xy: Array = spawn[key]
			var d := p1 if key == "p1" else p2
			d.position = Vector3(float(xy[0]), float(xy[1]), d.position.z)   # до add_child: Match запоминает спавн при регистрации
	var bots: Dictionary = spec.get("bots", {"p1": 3, "p2": 3})
	var brains: Array = []
	for key in ["p1", "p2"]:
		if not bots.has(key):
			continue
		var b: RivalBrain = MirrorBrain.new() if key == "p1" else RivalBrain.new()
		b.name = "Brain"
		b.level = int(bots[key])
		(p1 if key == "p1" else p2).add_child(b)
		brains.append(b)
	m = pg.get_node("Match") as Match
	if spec.has("countdown"):
		m.countdown_s = float(spec["countdown"])
	add_child(pg)
	# мозги сеют свой RNG от имени куклы — сид плана меняет и их (разные дубли одного плана)
	var sd := int(spec.get("seed", 1))
	for i in brains.size():
		var rng: Variant = brains[i].get("_rng")
		if rng is RandomNumberGenerator:
			(rng as RandomNumberGenerator).seed = hash(sd * 7919 + i * 104729)
	var brain_over: Dictionary = spec.get("brain", {})
	for b in brains:
		for k in brain_over:
			(b as Node).set(String(k), brain_over[k])
	cam = pg.get_node_or_null("Camera") as Camera3D
	var cam_over: Dictionary = spec.get("camera", {})
	if cam != null:
		for k in cam_over:
			cam.set(String(k), cam_over[k])
	if not bool(spec.get("hud", true)):
		for n in HIDE_NO_HUD:
			var node := pg.get_node_or_null(String(n))
			if node != null:
				hide_nodes.append(node)
	for f in spec.get("force", []):
		forces.append({"at": float((f as Dictionary).get("at", 0.0)), "tier": String((f as Dictionary).get("tier", "crit")), "done": false})
	m.phase_changed.connect(_on_phase)
	m.hit_fx.connect(func(ctx: Dictionary) -> void:
		var tier := String(ctx.get("tier", ""))
		var v: Variant = ctx.get("victim")
		var who := String((v as Node).name) if is_instance_valid(v) and v is Node else ""
		_event("hit", {"tier": tier, "damage": snappedf(float(ctx.get("damage", 0.0)), 0.1), "victim": who})
		if tier != "":
			_event(tier, {"victim": who}))
	m.ko.connect(func(victim: Doll, _a: Node, _r: Dictionary) -> void: _event("ko", {"victim": String(victim.name) if is_instance_valid(victim) else ""}))
	m.env_slam.connect(func(_ctx: Dictionary) -> void: _event("slam", {}))
	m.match_over.connect(func(_w: Doll, _r: Dictionary) -> void: _event("over", {}))
	for d in dolls:
		_connect_doll(d as Doll)
	m.doll_replaced.connect(func(_old: Doll, new_doll: Doll) -> void: _connect_doll(new_doll))
	max_frame = int(MAX_WAIT_FIGHT_S * fps)


func _connect_doll(d: Doll) -> void:
	if d == null or not is_instance_valid(d):
		return
	d.joint_broken.connect(func(part: String, _by: Node, _p: Vector3) -> void: _event("break", {"doll": String(d.name), "part": part}))
	d.part_detached.connect(func(part: String, _by: Node) -> void: _event("detach", {"doll": String(d.name), "part": part}))


func _on_phase(p: int) -> void:
	if p == Match.Phase.FIGHT and fight_frame < 0:
		fight_frame = Engine.get_frames_drawn()
		_event("fight", {})
		var hp: Dictionary = spec.get("hp", {})
		for i in dolls.size():
			var key := "p%d" % (i + 1)
			var d := dolls[i] as Doll
			if hp.has(key) and is_instance_valid(d):
				d.hp = minf(float(hp[key]), d.max_hp)
				m.hp_changed.emit(d, d.hp, d.max_hp)
		if spec.has("length"):
			stop_frame = fight_frame + int(float(spec["length"]) * fps)
		max_frame = fight_frame + int(float(spec.get("max_s", 40.0)) * fps)


func _event(type: String, extra: Dictionary) -> void:
	var e := {"type": type, "frame": Engine.get_frames_drawn(), "fight_t": snappedf(m.fight_time, 0.01) if m != null else 0.0}
	e.merge(extra)
	events.append(e)
	counts[type] = int(counts.get(type, 0)) + 1
	var until := String(spec.get("until", ""))
	if until != "" and type == until and stop_frame < 0:
		stop_frame = Engine.get_frames_drawn() + int(float(spec.get("tail", 2.0)) * fps)


## SSAA: 3D рисуется в ssaa× от окна и сводится билинейно (Gfx при смене окна/экрана выставил бы свой масштаб — держим свой).
func _enforce_scale() -> void:
	var w := get_window()
	if not is_equal_approx(w.scaling_3d_scale, ssaa):
		w.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		w.scaling_3d_scale = ssaa


func _process(_delta: float) -> void:
	if finished:
		return
	_enforce_scale()
	var f := Engine.get_frames_drawn()
	if f % DEV_SCAN_EVERY == 0:
		dev_nodes = []
		_scan_dev(pg)
	for n in hide_nodes + dev_nodes:
		if is_instance_valid(n):
			_hide(n)
	if fight_frame >= 0:
		var since := float(f - fight_frame) / float(fps)
		for fc in forces:
			if not bool(fc["done"]) and since >= float(fc["at"]):
				fc["done"] = true
				m.hit_tiers.force_next = String(fc["tier"])
	if (stop_frame >= 0 and f >= stop_frame) or f >= max_frame:
		_finish()


func _scan_dev(n: Node) -> void:
	if n == null:
		return
	for c in n.get_children():
		if c is KeysPanel or c is ControlFeelPanel or c is RunInventoryCounter or HIDE_DEV_NAMES.has(String(c.name)):
			dev_nodes.append(c)
		else:
			_scan_dev(c)


func _hide(n: Node) -> void:
	if n is CanvasLayer:
		(n as CanvasLayer).visible = false
	elif n is CanvasItem:
		(n as CanvasItem).visible = false
	else:
		for c in n.get_children():
			_hide(c)


func _finish() -> void:
	finished = true
	var missing: Array = []
	for r in spec.get("require", []):
		if int(counts.get(String(r), 0)) == 0:
			missing.append(r)
	var code := 0
	if fight_frame < 0:
		code = 2
	elif not missing.is_empty():
		code = 1
	var w := get_window()
	var report := {"ok": code == 0, "code": code, "missing": missing, "fps": fps, "frames": Engine.get_frames_drawn(), "fight_frame": fight_frame,
		"events": events, "counts": counts, "seed": int(spec.get("seed", 1)), "scene": String(spec.get("scene", "null_hall")),
		"window_px": [w.size.x, w.size.y], "scaling_3d_scale": w.scaling_3d_scale, "gfx": Gfx.preset, "hud_skin": HudSkin.id(), "lang": Loc.current}
	if out_path != "":
		var fa := FileAccess.open(out_path, FileAccess.WRITE)
		if fa != null:
			fa.store_string(JSON.stringify(report, "  "))
			fa.close()
	print("TRAILER_SHOT code=%d frames=%d fight_frame=%d counts=%s missing=%s" % [code, report["frames"], fight_frame, JSON.stringify(counts), str(missing)])
	get_tree().quit(code)
