## Площадка «Гольф: кукла — мяч» (docs/plan-demo/GOLF.md): купол Old NULL Hall (scenes/arena/null_hall.tscn — мембрана; поле на время
## гольфа Tuning.GOLF_FIELD_G, отладка поля и чемпион по G / K выключены) + поле лунок GolfCourse + GolfMatch + GolfHud + камера.
## Куклы собираются здесь до регистрации в матче: P1 — светлый клён doll.tscn, P2 — тёмный орех doll_dark.tscn.
##   P1 (player_index 0) — человек: мышь — прицел, ЛКМ держать — сила, отпустить — удар; Shift в полёте — рывок в сторону WASD (без
##   WASD — к курсору). p1_bot = true (пробы, снимки) — тоже бот;
##   P2 (player_index 1) — по умолчанию бот GolfBrain; U — отдать человеку на стрелках (← → — прицел, Enter держать — сила, Ctrl в
##   полёте — рывок в сторону стрелок, без стрелок — вверх); второй игрок может просто нажать свою клавишу — бот отдаст управление.
## Камера (группа golf_focus): лунка + люди, которые ещё не в лунке + все, кто сейчас летит; людей на поле нет — все на поле.
## Клавиши: R — заново, Esc — пауза (Flow), K — уровень ботов, M / N — музыка / толпа, H — скин HUD, C — прочность суставов (HitJuice),
## 1–9 — площадки хаба.
class_name GolfPlayground
extends Node3D

const DOLL_SCENES := ["res://scenes/doll/doll.tscn", "res://scenes/doll/doll_dark.tscn"]
const FOCUS_GROUP := "golf_focus"

@export var bot_level := 2
## Пробы и снимки: P1 тоже бот.
@export var p1_bot := false
@export var p2_bot := true
@export var players_n: int = Tuning.GOLF_PLAYERS

var arena: Node3D
var mouse_world := Vector2.ZERO
var _zoom_before := 1.0

@onready var match_node: GolfMatch = $Match
@onready var hud: GolfHud = $HUD
@onready var cam: DynamicCamera = $Camera
@onready var dolls_root: Node3D = $Dolls
@onready var course: GolfCourse = $Course


func _enter_tree() -> void:
	_zoom_before = DynamicCamera.user_zoom
	DynamicCamera.user_zoom = 1.0


func _exit_tree() -> void:
	DynamicCamera.user_zoom = _zoom_before


func _ready() -> void:
	GolfBrain.default_level = bot_level
	for c in get_children():
		if c is Node3D and c.has_method("spawn_points"):
			arena = c
			break
	if arena != null:
		if "debug_keys" in arena:
			arena.set("debug_keys", false)
		var f := arena.get_node_or_null("Field") as NullField
		if f != null:
			f.set_field(Tuning.GOLF_FIELD_G, Vector2(0.0, -1.0), 0.0)
		# мембрана в гольфе — борт поля: видна всегда (в бою — «только вблизи»); материал — копия, у купола других режимов свой
		var mem := arena.get_node_or_null("Membrane") as MeshInstance3D
		if mem != null and mem.material_override is ShaderMaterial:
			var mm := (mem.material_override as ShaderMaterial).duplicate() as ShaderMaterial
			mm.set_shader_parameter("idle", 0.07)
			mem.material_override = mm
			if f != null:
				f.set("_mat", mm)
	course.hall_g = Vector2(0.0, -Tuning.GOLF_FIELD_G * Tuning.G_EARTH)
	match_node.course = course
	course.build_hole(match_node.start_hole)
	_spawn()
	hud.bind(match_node, self)
	match_node.phase_changed.connect(func(p: int) -> void:
		if p == Match.Phase.COUNTDOWN:
			cam.snap())


func _spawn() -> void:
	var slots := course.tee_slots(players_n)
	for i in players_n:
		var human := (i == 0 and not p1_bot) or (i == 1 and not p2_bot)
		var d := make_doll(i, human)
		d.position = slots[i]
		dolls_root.add_child(d)
		if not human:
			var b := GolfBrain.new()
			b.name = GolfMatch.BOT_NAME
			d.add_child(b)


static func make_doll(i: int, human: bool) -> Doll:
	var d := (load(String(DOLL_SCENES[i % DOLL_SCENES.size()])) as PackedScene).instantiate() as Doll
	d.name = "P%d" % (i + 1)
	d.player_index = i
	d.input_prefix = "p1" if i == 0 else ("p2" if i == 1 else "bot%d" % i)
	d.external_input = not human
	d.control_enabled = false
	d.add_to_group("dolls")
	return d


func doll(index: int) -> Doll:
	return match_node.doll_of_index(index)


## За P2 — бот (GolfBrain ребёнком куклы) или человек на стрелках.
func set_p2_bot(on: bool) -> void:
	p2_bot = on
	var d := doll(1)
	if d == null:
		return
	var brain := d.get_node_or_null(GolfMatch.BOT_NAME)
	if on and brain == null:
		var b := GolfBrain.new()
		b.name = GolfMatch.BOT_NAME
		d.add_child(b)
		var p := match_node.player_of(d)
		if not p.is_empty():
			p["think"] = b.think_s()
			p["charging"] = false
	elif not on and brain != null:
		d.remove_child(brain)
		brain.queue_free()
	d.external_input = on
	d.input_vec = Vector2.ZERO
	hud.refresh_hint()


func set_bot_level(lv: int) -> void:
	bot_level = clampi(lv, 1, 3)
	GolfBrain.default_level = bot_level
	for d in match_node.dolls():
		var b := (d as Node).get_node_or_null(GolfMatch.BOT_NAME) as GolfBrain
		if b != null:
			b.level = bot_level
	hud.toast(tr("БОТЫ: УРОВЕНЬ %d") % bot_level)


func _process(_delta: float) -> void:
	var vp := get_viewport()
	var c := vp.get_camera_3d()
	if c == null:
		return
	var mp := vp.get_mouse_position()
	var o := c.project_ray_origin(mp)
	var n := c.project_ray_normal(mp)
	if absf(n.z) > 1e-4:
		var t := -o.z / n.z
		mouse_world = Vector2(o.x + n.x * t, o.y + n.y * t)
	var d := doll(0)
	if d != null and not d.external_input and match_node.players.has(0) and int(match_node.players[0]["state"]) == GolfMatch.S.AIM:
		var com := d.centre_of_mass(true)
		match_node.set_aim(0, mouse_world - Vector2(com.x, com.y))


func _physics_process(delta: float) -> void:
	_tick_focus()
	var d2 := doll(1)
	if d2 != null and not d2.external_input and match_node.players.has(1) and int(match_node.players[1]["state"]) == GolfMatch.S.AIM:
		var turn := Input.get_axis("p2_right", "p2_left")
		if absf(turn) > 0.01:
			match_node.turn_aim(1, turn * deg_to_rad(Tuning.GOLF_AIM_TURN_DEG_S) * delta)


## Кого держит кадр: лунка; люди, которые ещё играют лунку; все летящие. Людей на поле нет — все на поле.
func _tick_focus() -> void:
	var want := {}
	if course.cup != null:
		want[course.cup] = true
	var any_human := false
	for pi in match_node.players:
		var d := match_node.doll_of_index(pi)
		if d == null or not d.visible:
			continue
		var st := int(match_node.players[pi]["state"])
		if st == GolfMatch.S.HOLED:
			continue
		if not d.external_input:
			any_human = true
			want[d] = true
		elif st == GolfMatch.S.FLIGHT:
			want[d] = true
	if not any_human:
		for pi in match_node.players:
			var d := match_node.doll_of_index(pi)
			if d != null and d.visible and int(match_node.players[pi]["state"]) != GolfMatch.S.HOLED:
				want[d] = true
	for n in get_tree().get_nodes_in_group(FOCUS_GROUP):
		if not want.has(n):
			n.remove_from_group(FOCUS_GROUP)
	for n in want.keys():
		if is_instance_valid(n) and not (n as Node).is_in_group(FOCUS_GROUP):
			(n as Node).add_to_group(FOCUS_GROUP)


func _unhandled_input(event: InputEvent) -> void:
	var d1 := doll(0)
	var p1_human := d1 != null and not d1.external_input
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and p1_human:
		if event.pressed:
			match_node.charge_start(0)
		else:
			match_node.charge_release(0)
		return
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if p1_human and k.pressed and not k.echo and event.is_action("p1_dash"):
		var v := Input.get_vector("p1_left", "p1_right", "p1_down", "p1_up")
		if v.length() < 0.1:
			var com := d1.centre_of_mass()
			v = mouse_world - Vector2(com.x, com.y)
		match_node.nudge_input(0, v)
		return
	if p2_bot:
		if k.pressed and not k.echo:
			for a in ["p2_left", "p2_right", "p2_up", "p2_down", "p2_dash", "p2_flip"]:
				if InputMap.has_action(a) and event.is_action(a):
					set_p2_bot(false)
					hud.toast(tr("P2: человек"))
					return
	else:
		if event.is_action("p2_flip") and not k.echo:
			if k.pressed:
				match_node.charge_start(1)
			else:
				match_node.charge_release(1)
			return
		if event.is_action("p2_dash") and k.pressed and not k.echo:
			var v2 := Input.get_vector("p2_left", "p2_right", "p2_down", "p2_up")
			match_node.nudge_input(1, v2 if v2.length() > 0.1 else Vector2.UP)
			return
	if not k.pressed or k.echo:
		return
	match k.physical_keycode:
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
			var path: String = preload("res://scenes/playground.gd").scene_for_key(k.physical_keycode)
			if path != "" and path != scene_file_path:
				Loading.change_scene(path, "ПОДКЛЮЧЕНИЕ", path.get_file().get_basename())
