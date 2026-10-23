## Площадка «Вышибалы 3 на 3» (docs/plan-demo/DODGEBALL.md): спорт-зал (scenes/arena/sport_hall.tscn, снаряды спорта убраны) +
## стенка по черте x = 0 (StaticBody3D от пола до потолка: куклы не проходят, мячи её не замечают — исключение коллизий) + четыре мяча
## SportBall + шесть кукол с рукой ArmAssist + DodgeballMatch + DodgeballHud + камера. Стенка и мячи собираются кодом.
## Куклы — «Человек» (ModularDoll, kit_human): синие (P1, P3, P5) слева, красные (P2, P4, P6) справа.
##   P1 (player_index 0, синие) — человек: WASD летать, Shift ускорение, ЛКМ — рука к курсору, E — схватить мяч; с зажатой ЛКМ E —
##       бросок к курсору; рука (ЛКМ) на пути чужого мяча — поймать;
##   P2 (1, красные) — бот; U — отдать его второму игроку на стрелках (или второй просто жмёт стрелку), «/» — схватить ближайший
##       мяч своей половины в досягаемости / бросить в ближайшего соперника; U ещё раз — снова бот;
##   P3…P6 — боты DodgeballBrain уровня bot_level (K — 1 → 2 → 3).
## Клавиши: R — заново, Esc — пауза (Flow), M / N — музыка / толпа, H — скин HUD, 1–9 — площадки хаба.
class_name DodgeballPlayground
extends Node3D

const DOLL_SCENE := preload("res://scenes/body/modular_doll.tscn")
const BALL_SCENE := preload("res://scenes/sport/sport_ball.tscn")
const GRID_SHADER := preload("res://assets/shaders/energy_grid.gdshader")
const BLUEPRINT := "res://data/body/blueprints/kit_human.tres"
const BRAIN := "DodgeballBrain"
const HALL_H := 10.0
const P2_THROW_FRAMES := 4        # «/» с мячом: рука на соперника, бросок через столько физических кадров

@export var bot_level := 2
## Пробы: P1 тоже бот (матч одними ботами).
@export var p1_bot := false
@export var p2_human := false

var arena: Node3D
var line: StaticBody3D
var _zoom_before := 1.0
var _break_modes_before: Array = []
var _p2_throw_left := -1

@onready var match_node: DodgeballMatch = $Match
@onready var hud: DodgeballHud = $HUD
@onready var cam: DynamicCamera = $Camera
@onready var dolls_root: Node3D = $Dolls
@onready var balls_root: Node3D = $Balls


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
	DodgeballBrain.default_level = bot_level
	arena = get_node_or_null("SportHall") as Node3D
	_strip_arena()
	_build_line()
	_spawn_balls()
	_spawn()
	_claim_photo_key()
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
		sub.text = "%s · %s" % [tr("ВЫШИБАЛЫ"), tr("ДО %d ПОБЕД") % Tuning.DODGEBALL_ROUNDS_TO_WIN]


## Стенка по черте: от пола до потолка, полутолщина DODGEBALL_LINE_HALF; видна полупрозрачной сеткой (energy_grid, как сетка
## волейбола) лицом к камере + полоса на полу.
func _build_line() -> void:
	line = StaticBody3D.new()
	line.name = "CentreLine"
	line.add_to_group(DodgeballMatch.LINE_GROUP)
	var sh := CollisionShape3D.new()
	sh.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(Tuning.DODGEBALL_LINE_HALF * 2.0, HALL_H, 3.0)
	sh.shape = box
	sh.position = Vector3(0.0, HALL_H * 0.5, 0.0)
	line.add_child(sh)
	var glow := MeshInstance3D.new()
	glow.name = "Glow"
	var q := QuadMesh.new()
	q.size = Vector2(0.5, HALL_H)
	glow.mesh = q
	glow.position = Vector3(0.0, HALL_H * 0.5, 0.05)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = GRID_SHADER
	mat.set_shader_parameter("color", Color(1.0, 0.92, 0.55, 1.0))
	mat.set_shader_parameter("cells", Vector2(1, 16))
	mat.set_shader_parameter("glow", 0.9)
	mat.set_shader_parameter("base_alpha", 0.08)
	glow.material_override = mat
	line.add_child(glow)
	var strip := MeshInstance3D.new()
	strip.name = "FloorStrip"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.14, 0.02, 3.0)
	strip.mesh = bm
	strip.position = Vector3(0.0, 0.012, 0.0)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(1.0, 0.92, 0.55)
	sm.emission_enabled = true
	sm.emission = Color(1.0, 0.85, 0.4)
	sm.emission_energy_multiplier = 0.8
	strip.material_override = sm
	line.add_child(strip)
	add_child(line)


func _spawn_balls() -> void:
	var spots: Array = Tuning.DODGEBALL_BALL_SPOTS
	for i in Tuning.DODGEBALL_BALLS:
		var b := BALL_SCENE.instantiate() as SportBall
		b.name = "Ball%d" % (i + 1)
		b.add_to_group(DodgeballMatch.BALL_GROUP)
		b.add_to_group(DodgeballMatch.CAM_GROUP)
		var p: Vector2 = spots[i % spots.size()]
		b.position = Vector3(p.x, p.y, 0.0)
		balls_root.add_child(b)
		b.freeze = true


func _spawn() -> void:
	for i in Tuning.DODGEBALL_TEAM * 2:
		var human := (i == 0 and not p1_bot) or (i == 1 and p2_human)
		var d := make_doll(i, human)
		var p: Vector2 = Tuning.DODGEBALL_SPAWN[i]
		d.position = Vector3(p.x, p.y, 0.0)
		dolls_root.add_child(d)
		attach_children(d, human)


## Боец player_index i: «Человек» (ModularDoll, kit_human), рубашка — цвет команды (DodgeballMatch._dress). human — человек (P1 —
## клавиатура и мышь, P2 — стрелки), иначе бот.
static func make_doll(i: int, human: bool) -> Doll:
	var bp := (load(BLUEPRINT) as BodyBlueprint).duplicate(true) as BodyBlueprint
	bp.id = "dodgeball_%d" % i
	var d := DOLL_SCENE.instantiate() as ModularDoll
	d.blueprint = bp
	d.name = "P%d" % (i + 1)
	d.player_index = i
	d.input_prefix = "p%d" % (i + 1) if human else "bot%d" % i
	d.external_input = not human
	d.add_to_group("dolls")
	d.add_to_group(DodgeballMatch.CAM_GROUP)
	return d


## Рука — у всех (боты берут и бросают мяч ею же), мозг — у ботов.
static func attach_children(d: Doll, human: bool) -> void:
	var a := ArmAssist.attach_to(d)
	if not human:
		a.show_hints = false
		var b := DodgeballBrain.new()
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
	return DodgeballMatch.arm_of(d)


## «/» — мяч P2-человека: пока P2 человек, фоторежим клавишу не берёт (PhotoMode.KEY_TAKEN_GROUP).
func _claim_photo_key() -> void:
	if p2_human:
		add_to_group(PhotoMode.KEY_TAKEN_GROUP)
	elif is_in_group(PhotoMode.KEY_TAKEN_GROUP):
		remove_from_group(PhotoMode.KEY_TAKEN_GROUP)


## P2 — человек на стрелках или бот (U). Match.respawn_doll переносит и external_input, и узел мозга.
func set_p2_human(on: bool) -> void:
	p2_human = on
	_claim_photo_key()
	var d := doll(1)
	if d == null:
		return
	var brain := d.get_node_or_null(BRAIN)
	if not on and brain == null:
		var b := DodgeballBrain.new()
		b.name = BRAIN
		d.add_child(b)
	elif on and brain != null:
		(brain as DodgeballBrain).let_go()
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
	DodgeballBrain.default_level = bot_level
	for d in match_node.dolls():
		var b := (d as Node).get_node_or_null(BRAIN) as DodgeballBrain
		if b != null:
			b._brain_ready()
	hud.toast(tr("БОТЫ: УРОВЕНЬ %d") % bot_level)


## «/» у P2-человека: нет мяча — схватить ближайший мяч своей половины в досягаемости руки; держит — бросить в ближайшего
## соперника на поле (рука на него, бросок через P2_THROW_FRAMES кадров: ArmAssist включает руку с ближайшего тика).
func p2_ball_key() -> void:
	var d := doll(1)
	var a := arm_of(d)
	if d == null or a == null or not match_node.in_play(d) or not d.control_enabled:
		return
	if a.is_holding():
		var best: Doll = null
		var best_d := INF
		for e in match_node.team_dolls(0, true):
			var dist := (e as Doll).centre_of_mass().distance_to(d.centre_of_mass())
			if dist < best_d:
				best_d = dist
				best = e
		var aim := best.centre_of_mass() if best != null else d.centre_of_mass() + Vector3(-3.0, 0.3, 0.0)
		a.set_target_override(aim)
		_p2_throw_left = P2_THROW_FRAMES
		return
	var root := a.root_point()
	var pick: SportBall = null
	var pick_d := a.reach + ArmAssist.GRAB_RADIUS + Tuning.SPORT_BALL_RADIUS
	for b in match_node.balls():
		var sb := b as SportBall
		if not a.can_grab(sb):
			continue
		var dist := sb.global_position.distance_to(root)
		if dist < pick_d:
			pick_d = dist
			pick = sb
	if pick != null:
		a.grab(pick)


func _physics_process(_delta: float) -> void:
	if _p2_throw_left < 0:
		return
	_p2_throw_left -= 1
	if _p2_throw_left > 0:
		return
	_p2_throw_left = -1
	var a := arm_of(doll(1))
	if a == null:
		return
	if a.is_holding() and a.arm_active:
		a.release("toggle")
	a.clear_target_override()


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
				p2_ball_key()
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
