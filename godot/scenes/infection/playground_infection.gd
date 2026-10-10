## Площадка «Заражение» (docs/plan-demo/INFECTION.md; MODES_IDEAS.md Б5): купол Old NULL Hall (scenes/arena/null_hall.tscn,
## гравитация обычная, поле и чемпион по G / K выключены, голосования зрителей нет) + семеро кукол + InfectionMatch + InfectionHud +
## стрелка к ближайшему заражённому за кадром (InfectionMarkers) + камера + пульс мембраны и писк последних секунд партии.
## Куклы собираются здесь, до регистрации в матче (Match._late_ready — отложенный): чётные — светлый клён doll.tscn, нечётные — тёмный
## орех doll_dark.tscn; цвета — Tuning.INFECTION_COLORS, заражённые — INFECTION_COLOR.
##   P1 (player_index 0) — человек: WASD летать, Shift ускорение, Space + A/D раскрутка, рука мышью (ArmAssist — пока здоров);
##     p1_bot = true (пробы) — тоже бот;
##   P2 (player_index 1) — по умолчанию бот; U — отдать человеку на стрелках (правый Ctrl, Enter) или вернуть бота; второй игрок может
##     просто нажать свою клавишу — бот отдаст управление сам (как в спорт-зале);
##   P3…P7 — боты InfectionBrain уровня bot_level (K — 1 → 2 → 3).
## Камера: люди + ближайший к человеку заражённый (здоровому) или здоровый (заражённому), если он ближе Tuning.INFECTION_FOCUS_M;
## людей в игре нет — все живые. Клавиши: R — заново, Esc — пауза (Flow), M / N — музыка / толпа, H — скин HUD, 1–9 — площадки хаба.
## Масштаб камеры игрока (DynamicCamera.user_zoom) на время сцены — 1: в куполе семеро.
class_name InfectionPlayground
extends Node3D

const DOLL_SCENES := ["res://scenes/doll/doll.tscn", "res://scenes/doll/doll_dark.tscn"]
const FOCUS_GROUP := "infection_focus"
const BOT_NAME := "InfectionBrain"
const PULSE_FLASH := 0.35          # яркость контура мембраны на пульс (uniform idle шейдера; покой 0.015)

@export var bot_level := 2
## Пробы: P1 тоже бот (матч одними ботами).
@export var p1_bot := false
@export var p2_bot := true
@export var dolls_n: int = Tuning.INFECTION_DOLLS

var arena: Node3D
## Пробы: сколько пульсов мембраны показано / писков прозвучало.
var pulses_shown := 0
var _zoom_before := 1.0
var _membrane_mat: ShaderMaterial
var _membrane_idle := 0.015
var _membrane_colour := Color(0.35, 0.68, 1.0)
var _pulse := 0.0
var _beep: AudioStreamPlayer

@onready var match_node: InfectionMatch = $Match
@onready var hud: InfectionHud = $HUD
@onready var cam: DynamicCamera = $Camera
@onready var dolls_root: Node3D = $Dolls


func _enter_tree() -> void:
	_zoom_before = DynamicCamera.user_zoom
	DynamicCamera.user_zoom = 1.0


func _exit_tree() -> void:
	DynamicCamera.user_zoom = _zoom_before


func _ready() -> void:
	InfectionBrain.default_level = bot_level
	for c in get_children():
		if c is Node3D and c.has_method("spawn_points"):
			arena = c
			break
	if arena != null:
		if "debug_keys" in arena:
			arena.set("debug_keys", false)   # G — смена поля, K — чемпион лиги: в заражении не нужны
		if arena.has_signal("body_fell"):
			arena.connect("body_fell", _on_body_fell)
		_find_membrane()
	_spawn()
	hud.bind(match_node, self)
	match_node.phase_changed.connect(func(p: int) -> void:
		if p == Match.Phase.COUNTDOWN:
			cam.snap())
	match_node.doll_replaced.connect(_on_doll_replaced)
	match_node.pulsed.connect(_on_pulse)
	match_node.doll_infected.connect(_on_infected)
	_beep = AudioStreamPlayer.new()
	_beep.name = "Beep"
	_beep.stream = BombCarry.beep_stream()
	_beep.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_beep.max_polyphony = 2
	add_child(_beep)


func _find_membrane() -> void:
	var f: Variant = arena.get("field")
	if not (f is NullField):
		return
	var mp: NodePath = (f as NullField).membrane_path
	var m := (f as NullField).get_node_or_null(mp) as MeshInstance3D if mp != NodePath() else null
	if m != null and m.material_override is ShaderMaterial:
		_membrane_mat = m.material_override
		var idle: Variant = _membrane_mat.get_shader_parameter("idle")
		if idle != null:
			_membrane_idle = float(idle)
		var col: Variant = _membrane_mat.get_shader_parameter("colour")
		if col is Color:
			_membrane_colour = col
		elif col is Vector3:
			_membrane_colour = Color((col as Vector3).x, (col as Vector3).y, (col as Vector3).z)


func _spawn() -> void:
	for i in dolls_n:
		var human := (i == 0 and not p1_bot) or (i == 1 and not p2_bot)
		var d := make_doll(i, human)
		var sp: Vector2 = Tuning.INFECTION_SPAWN[i % Tuning.INFECTION_SPAWN.size()]
		d.position = Vector3(sp.x, sp.y, 0.0)
		dolls_root.add_child(d)
		attach_children(d, human)


## Кукла player_index i (P1 — p1, P2 — p2, остальные — свои префиксы без клавиш). human — управляет клавиатура, иначе мозг.
static func make_doll(i: int, human: bool) -> Doll:
	var d := (load(String(DOLL_SCENES[i % DOLL_SCENES.size()])) as PackedScene).instantiate() as Doll
	d.name = "P%d" % (i + 1)
	d.player_index = i
	d.input_prefix = "p1" if i == 0 else ("p2" if i == 1 else "bot%d" % i)
	d.external_input = not human
	d.add_to_group("dolls")
	return d


## Рука мышью — только у P1-человека (заражение её снимает; новая партия — новая кукла, рука снова); мозг — у ботов.
static func attach_children(d: Doll, human: bool) -> void:
	if human and d.player_index == 0 and d.get_node_or_null("ArmAssist") == null:
		ArmAssist.attach_to(d)
	if not human and d.get_node_or_null(BOT_NAME) == null:
		var b := InfectionBrain.new()
		b.name = BOT_NAME
		d.add_child(b)


## Match.respawn_doll переносит узлы-скрипты (мозг, руку — если была); у заражённого руки не было — вернуть здоровому P1.
func _on_doll_replaced(_old: Doll, new_doll: Doll) -> void:
	attach_children(new_doll, not new_doll.external_input)


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


## За P2 — бот (InfectionBrain ребёнком куклы) или человек на стрелках. Match.respawn_doll переносит и external_input, и узел мозга.
func set_p2_bot(on: bool) -> void:
	p2_bot = on
	var d := doll(1)
	if d == null:
		return
	var brain := d.get_node_or_null(BOT_NAME)
	if on and brain == null:
		var b := InfectionBrain.new()
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
	InfectionBrain.default_level = bot_level
	for d in match_node.dolls():
		var b := (d as Node).get_node_or_null(BOT_NAME) as InfectionBrain
		if b != null:
			b._brain_ready()
	hud.toast(tr("БОТЫ: УРОВЕНЬ %d") % bot_level)


func _physics_process(_delta: float) -> void:
	_tick_focus()


func _process(delta: float) -> void:
	if _pulse <= 0.0:
		return
	var real := delta / maxf(Engine.time_scale, 0.02)
	_pulse = maxf(_pulse - real * 3.0, 0.0)
	if _membrane_mat != null:   # на последнем шаге (_pulse 0) контур возвращается к покою
		_membrane_mat.set_shader_parameter("idle", _membrane_idle + PULSE_FLASH * _pulse)
		_membrane_mat.set_shader_parameter("colour", _membrane_colour.lerp(Tuning.INFECTION_COLOR, 0.7 * _pulse))


## Пульс последних секунд партии: вспышка контура мембраны (зеленеет) и писк, к концу выше и громче.
func _on_pulse(urgency: float) -> void:
	pulses_shown += 1
	_pulse = 1.0
	if _beep != null and _beep.is_inside_tree():
		_beep.volume_db = lerpf(-14.0, -5.0, urgency)
		_beep.pitch_scale = lerpf(0.9, 1.2, urgency)
		_beep.play()


## Заражение: зелёная вспышка с пылью на жертве и щелчок; тост «ЗАРАЖЁН: P3» — у HUD (диктор).
func _on_infected(victim: Doll, by: Doll) -> void:
	if by == null or victim == null or not is_instance_valid(victim):
		return
	var pos := victim.centre_of_mass()
	pos.z = 0.0
	ImpactFx.spawn_impact(self, pos, Vector3.UP, 7.0, "infect", FxMaterial.RUBBER, Tuning.INFECTION_COLOR)
	var sfx := get_tree().get_first_node_in_group(SfxDirector.GROUP) as SfxDirector
	if sfx != null:
		sfx.play_layer("stun", -4.0, 0.8, SfxDirector.BUS_SFX, sfx.pan_for(pos))


## Кого держит кадр (группа FOCUS_GROUP камеры): люди + ближайший к ним «противник» (здоровому — заражённый, заражённому — здоровый),
## если он ближе INFECTION_FOCUS_M.
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
		for h in hs:
			var hd := h as Doll
			var others: Array = match_node.healthy() if match_node.is_infected(hd) else match_node.zombies()
			var best: Doll = null
			var bd := Tuning.INFECTION_FOCUS_M
			for d in others:
				if want.has(d):
					continue
				var dd := (d as Doll).centre_of_mass().distance_to(hd.centre_of_mass())
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
	var d := InfectionMatch.doll_of(body)
	if d == null or not d.alive or not d.parts.values().has(body):
		return
	d.knock_out()
