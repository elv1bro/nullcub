## Площадка «Перетягивание каната 2 на 2» (docs/plan-demo/TUG.md): спорт-зал (scenes/arena/sport_hall.tscn, снаряды спорта убраны) +
## канат TugRope (собирается кодом: цепь звеньев на полу, метка посередине, черты ±Tuning.TUG_LINE_M) + четыре куклы с рукой
## ArmAssist + TugMatch + TugHud + камера.
## Куклы — «Человек» (ModularDoll, kit_human), собираются здесь до регистрации в матче: синие (P1, P3) слева, красные (P2, P4) справа.
##   P1 (player_index 0, синие) — человек: WASD летать, Shift ускорение, ЛКМ — рука к курсору, E — схватить звено / отпустить;
##   P2 (1, красные) — бот; U — отдать его второму игроку на стрелках (или второй просто жмёт стрелку), «/» — схватить ближайшее
##       звено своей половины в досягаемости / отпустить; U ещё раз — снова бот;
##   P3, P4 — боты TugBrain уровня bot_level (K — 1 → 2 → 3).
## Клавиши: R — заново, Esc — пауза (Flow), M / N — музыка / толпа, H — скин HUD, 1–9 — площадки хаба.
class_name TugPlayground
extends Node3D

const DOLL_SCENE := preload("res://scenes/body/modular_doll.tscn")
const BLUEPRINT := "res://data/body/blueprints/kit_human.tres"
const CAM_GROUP := "tug_cam"
const BRAIN := "TugBrain"

@export var bot_level := 2
## Пробы: P1 тоже бот (матч одними ботами).
@export var p1_bot := false
@export var p2_human := false

var arena: Node3D
var rope: TugRope
var _zoom_before := 1.0
var _break_modes_before: Array = []

@onready var match_node: TugMatch = $Match
@onready var hud: TugHud = $HUD
@onready var cam: DynamicCamera = $Camera
@onready var dolls_root: Node3D = $Dolls


func _enter_tree() -> void:
	_zoom_before = DynamicCamera.user_zoom
	DynamicCamera.user_zoom = 1.0
	_break_modes_before = [PartHp.on, JointBreak.on]
	if Tuning.SPORT_PARTHP:
		PartHp.set_on(true)
		JointBreak.set_on(false)


func _exit_tree() -> void:
	DynamicCamera.user_zoom = _zoom_before
	if _break_modes_before.size() == 2:
		PartHp.set_on(bool(_break_modes_before[0]))
		JointBreak.set_on(bool(_break_modes_before[1]))


func _ready() -> void:
	TugBrain.default_level = bot_level
	arena = get_node_or_null("SportHall") as Node3D
	_strip_arena()
	rope = $Rope as TugRope
	rope.build()
	_spawn()
	hud.bind(match_node, self)
	match_node.phase_changed.connect(func(p: int) -> void:
		if p == Match.Phase.COUNTDOWN:
			cam.snap())


## Снаряды футбола / баскетбола / волейбола — прочь (невидимы и вне физики), табло — подпись режима.
func _strip_arena() -> void:
	if arena == null:
		return
	var fx := arena.get_node_or_null("Fixtures")
	if fx != null:
		for f in fx.get_children():
			(f as Node3D).visible = false
			f.process_mode = Node.PROCESS_MODE_DISABLED
	var sub := arena.get_node_or_null("Board/Sub") as Label3D
	if sub != null:
		sub.text = "%s · %s" % [tr("ПЕРЕТЯГИВАНИЕ КАНАТА"), tr("ДО %d") % Tuning.TUG_SCORE_TO_WIN]


func _spawn() -> void:
	for i in Tuning.TUG_TEAM * 2:
		var human := (i == 0 and not p1_bot) or (i == 1 and p2_human)
		var d := make_doll(i, human)
		var p: Vector2 = Tuning.TUG_SPAWN[i]
		d.position = Vector3(p.x, p.y, 0.0)
		dolls_root.add_child(d)
		attach_children(d, human)


## Боец player_index i: «Человек» (ModularDoll, kit_human), рубашка — цвет команды (TugMatch._dress). human — человек (P1 — клавиатура
## и мышь, P2 — стрелки), иначе бот.
static func make_doll(i: int, human: bool) -> Doll:
	var bp := (load(BLUEPRINT) as BodyBlueprint).duplicate(true) as BodyBlueprint
	bp.id = "tug_%d" % i
	var d := DOLL_SCENE.instantiate() as ModularDoll
	d.blueprint = bp
	d.name = "P%d" % (i + 1)
	d.player_index = i
	d.input_prefix = "p%d" % (i + 1) if human else "bot%d" % i
	d.external_input = not human
	d.add_to_group("dolls")
	d.add_to_group(CAM_GROUP)
	return d


## Рука — у всех (боты держат канат ею же), мозг — у ботов.
static func attach_children(d: Doll, human: bool) -> void:
	var a := ArmAssist.attach_to(d)
	if not human:
		a.show_hints = false
		var b := TugBrain.new()
		b.name = BRAIN
		d.add_child(b)


func dolls() -> Array:
	return match_node.dolls()


func doll(index: int) -> Doll:
	for d in match_node.dolls():
		if (d as Doll).player_index == index:
			return d
	return null


static func arm_of(d: Doll) -> ArmAssist:
	if d == null or not is_instance_valid(d):
		return null
	for c in d.get_children():
		if c is ArmAssist and (c as ArmAssist).primary:
			return c
	return null


## P2 — человек на стрелках или бот (U). Match.respawn_doll переносит и external_input, и узел мозга.
func set_p2_human(on: bool) -> void:
	p2_human = on
	var d := doll(1)
	if d == null:
		return
	var brain := d.get_node_or_null(BRAIN)
	if not on and brain == null:
		var b := TugBrain.new()
		b.name = BRAIN
		d.add_child(b)
	elif on and brain != null:
		(brain as TugBrain).let_go()
		d.remove_child(brain)
		brain.queue_free()
	d.external_input = not on
	d.input_prefix = "p2" if on else "bot1"
	d.input_vec = Vector2.ZERO
	var a := arm_of(d)
	if a != null:
		a.show_hints = on
	hud.refresh_hint()


func set_bot_level(lv: int) -> void:
	bot_level = clampi(lv, 1, 3)
	TugBrain.default_level = bot_level
	for d in match_node.dolls():
		var b := (d as Node).get_node_or_null(BRAIN) as TugBrain
		if b != null:
			b._brain_ready()
	hud.toast(tr("БОТЫ: УРОВЕНЬ %d") % bot_level)


## «/» у P2-человека: держит — отпустить; нет — схватить ближайшее звено своей половины в досягаемости руки.
func p2_grip_toggle() -> void:
	var d := doll(1)
	var a := arm_of(d)
	if d == null or a == null or not d.alive or not d.control_enabled:
		return
	if a.is_holding():
		a.release("drop")
		return
	var link := TugBrain.nearest_link(rope, d, a.root_point(), a.reach + ArmAssist.GRAB_RADIUS)
	if link != null:
		a.grab(link)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if not p2_human:
		for act in ["p2_left", "p2_right", "p2_up", "p2_down", "p2_dash", "p2_flip"]:
			if InputMap.has_action(act) and event.is_action(act):
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
		KEY_SLASH:
			if p2_human:
				p2_grip_toggle()
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
