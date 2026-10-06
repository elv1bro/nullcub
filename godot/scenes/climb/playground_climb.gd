## Площадка «Подъём: проба стены» (docs/plan-demo/CLIMB.md, MODES_PACK.md §8; автор 06.10: «PEAK тоже»). Стена 30 м (ClimbWall,
## сцена scenes/climb/climb_wall.tscn — сборщик tools/build_climb_wall.gd) + ClimbMatch + ClimbHud + камера. Здесь — игроки и клавиши.
##   • P1 — «Человек» (kit_human): WASD — полёт (тратит запас тяги), Shift — рывок (дороже), ЛКМ — левая рука, ПКМ — правая: держишь
##     кнопку — рука тянется к курсору и хватается за камень, держит, пока зажата; курсор, пока рука держит, — куда тянется грудь
##     (подтягивание). Гладкое (синие плиты) не хватается.
##   • P2 входит первым нажатием своей клавиши (стрелки, правый Ctrl, Enter, [, ], геймпад 2) или клавишей U; U ещё раз — P2 уходит.
##     Руки P2 — [ и ] (ClimbKeyHands): пока клавиша руки зажата, стрелки ведут руки, а не полёт.
##   • Камера — DynamicCamera по точкам ClimbFocus (ЦМ куклы + Tuning.CLIMB_CAM_LOOK_UP), полувысота кадра CLIMB_CAM_MIN…MAX_HALF_H.
##   • Клавиши: R — заново (все к подножию, часы с нуля), G — сила тяжести шахты (Tuning.CLIMB_GRAVITY_STEPS, сравнить руками),
##     U — P2, Esc — пауза (продолжить / заново / в гараж), M / N — музыка / толпа, H — скин HUD.
class_name ClimbPlayground
extends Node3D

signal p2_changed(joined: bool)
signal gravity_changed(g: float)

const DOLL_SCENE := preload("res://scenes/body/modular_doll.tscn")
const BLUEPRINT := "res://data/body/blueprints/kit_human.tres"
const PLAYERS_GROUP := "players"

## P2 сразу в игре (пробы); обычно — с первого нажатия.
@export var p2_on_start := false
## Сам заходит ли P2 по первому нажатию своих клавиш (пробы выключают).
@export var auto_join := true

var p1: Doll
var p2: Doll
var _zoom_before := 1.0
var _focus: Dictionary = {}   # кукла → ClimbFocus

@onready var wall: ClimbWall = $Wall
@onready var match_node: ClimbMatch = $Match
@onready var hud: ClimbHud = $HUD
@onready var cam: DynamicCamera = $Camera
@onready var dolls_root: Node3D = $Dolls


func _enter_tree() -> void:
	_zoom_before = DynamicCamera.user_zoom
	DynamicCamera.user_zoom = 1.0


func _exit_tree() -> void:
	DynamicCamera.user_zoom = _zoom_before


func _ready() -> void:
	ClimbKeyHands.ensure_actions()
	ArmAssist.ensure_input_actions()
	cam.min_half_height = Tuning.CLIMB_CAM_MIN_HALF_H
	cam.max_half_height = Tuning.CLIMB_CAM_MAX_HALF_H
	p1 = _spawn_player(0)
	if p2_on_start:
		join_p2()
	hud.bind(self)
	match_node.doll_replaced.connect(_on_doll_replaced)
	cam.snap()


# --- игроки ---

## Кукла игрока i: «Человек», рубашка — цвет игрока, человек (ввод с клавиатуры / мыши / геймпада).
static func make_player(i: int) -> ModularDoll:
	var bp := (load(BLUEPRINT) as BodyBlueprint).duplicate(true) as BodyBlueprint
	bp.id = "climb_%d" % i
	var d := DOLL_SCENE.instantiate() as ModularDoll
	d.blueprint = bp
	d.name = "P%d" % (i + 1)
	d.player_index = i
	d.input_prefix = "p%d" % (i + 1)
	d.external_input = false
	d.add_to_group("dolls")
	d.add_to_group(PLAYERS_GROUP)
	return d


func _spawn_player(i: int) -> Doll:
	var d := make_player(i)
	var pts := wall.spawn_points()
	d.position = pts[mini(i, pts.size() - 1)]
	dolls_root.add_child(d)
	match_node.register(d)
	_add_focus(d)
	return d


func _add_focus(d: Doll) -> void:
	var f := ClimbFocus.make(d)
	add_child(f)
	_focus[d] = f


func _drop_focus(d: Doll) -> void:
	var f: Variant = _focus.get(d, null)
	_focus.erase(d)
	if f != null and is_instance_valid(f):
		(f as Node).queue_free()


func players() -> Array:
	var out: Array = []
	for d in [p1, p2]:
		if d != null and is_instance_valid(d) and d.is_inside_tree():
			out.append(d)
	return out


func join_p2() -> void:
	if p2 != null and is_instance_valid(p2):
		return
	p2 = _spawn_player(1)
	p2_changed.emit(true)


func leave_p2() -> void:
	if p2 == null or not is_instance_valid(p2):
		p2 = null
		return
	_drop_focus(p2)
	match_node.players.erase(p2.player_index)
	dolls_root.remove_child(p2)
	p2.queue_free()
	p2 = null
	p2_changed.emit(false)


func _on_doll_replaced(old: Doll, new_doll: Doll) -> void:
	if old == p1:
		p1 = new_doll
	elif old == p2:
		p2 = new_doll
	var f: Variant = _focus.get(old, null)
	_focus.erase(old)
	if f != null and is_instance_valid(f):
		(f as ClimbFocus).doll = new_doll
		_focus[new_doll] = f
	else:
		_add_focus(new_doll)


## R: все к подножию, запас полный, часы с нуля.
func restart() -> void:
	match_node.restart()
	cam.snap()


## G: следующая сила тяжести шахты из Tuning.CLIMB_GRAVITY_STEPS.
func cycle_gravity() -> float:
	var steps: Array = Tuning.CLIMB_GRAVITY_STEPS
	var i := 0
	for k in steps.size():
		if is_equal_approx(float(steps[k]), wall.gravity):
			i = k
	var g := float(steps[(i + 1) % steps.size()])
	wall.set_gravity(g)
	gravity_changed.emit(g)
	return g


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_R:
				restart()
				hud.toast(tr("Заново — к подножию"))
				return
			KEY_G:
				var g := cycle_gravity()
				hud.toast(tr("Тяжесть шахты: %.0f м/с²") % g)
				return
			KEY_U:
				if p2 != null and is_instance_valid(p2):
					leave_p2()
					hud.toast(tr("P2 ушёл — лезешь один"))
				else:
					join_p2()
					hud.toast(tr("P2 в игре: стрелки, руки — [ и ]"))
				return
			KEY_ESCAPE:
				Flow.toggle_pause(restart)
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
	if auto_join and (p2 == null or not is_instance_valid(p2)) and event.is_pressed():
		for a in ["p2_left", "p2_right", "p2_up", "p2_down", "p2_dash", "p2_flip"] + ClimbKeyHands.ACTIONS:
			if InputMap.has_action(a) and event.is_action(a):
				join_p2()
				hud.toast(tr("P2 в игре: стрелки, руки — [ и ]"))
				return
