## Площадка «Перегон: проба машины» (docs/plan-demo/CONVOY.md; автор 06.10: «RV There Yet — подумай, как добавить интересно похожее»,
## план — MODES_PACK.md §7, шаг 1). Сцена scenes/playground_convoy.tscn собирается tools/build_convoy_probe.gd: участок ~100 м слева
## направо — ровно → поле кочек → крутой подъём → провал (доски на стеллаже над ним) → спуск → финиш-площадка. Здесь — игроки,
## машина, груз, время, клавиши.
##   • Игроки: P1 — «Человек» (kit_human) с рукой мышью (ArmAssist: ЛКМ — рука к курсору, E — взять / отпустить, ЛКМ+E — бросок).
##     P2 входит первым нажатием своей клавиши (стрелки, правый Ctrl, Enter, «\», Num ., «/», Num 0, геймпад 2) или клавишей U;
##     U ещё раз — P2 уходит. Рука P2 — клавиатура (PuzzleKeyArm головоломок: «/» или Num 0) или геймпад.
##   • Машина (ConvoyCar): F у двери кабины (P2 — «\» или Num .; геймпад — Y) — сесть / выйти. В кабине: A / D — газ / назад,
##     пробел (P2 — Enter) — ручник, W / S — наклон в воздухе. Без водителя — на ручнике. Толкать — тягой, телом в борт.
##   • Груз (ConvoyCargo, Tuning.CONVOY_CARGO) лежит в кузове; счёт «в кузове N из M». Вылетевшее — ловить и закидывать рукой.
##   • Провал: колесо машины в провале ниже дороги (или её ЦМ ниже кромки на CONVOY_PIT_DROP_M) дольше CONVOY_PIT_RESET_S — назад на
##     старт участка (что в кузове — с ней). Доски (CONVOY_PLANKS) — на стеллаже за провалом: отпущенная поперёк провала доска
##     «ложится в пазы» (ровно на дорогу, заморожена) — мост до рестарта участка.
##   • Время — от первого движения машины до финиша (её ЦМ за линией финиша); итоги — время и сколько груза довёз.
##   • Клавиши: R — участок заново (машина, груз, доски, игроки — на старт), U — P2, Esc — пауза (продолжить / заново / в гараж),
##     M / N — музыка / толпа, H — скин HUD; после финиша Enter — заново.
## Площадка — «арена» для Match и камеры: spawn_points() (у машины) и bounds() (весь участок).
class_name ConvoyPlayground
extends Node3D

signal finished(time_s: float, delivered: int, total: int)
signal p2_changed(joined: bool)
signal car_reset(reason: String)

const DOLL_SCENE := preload("res://scenes/body/modular_doll.tscn")
const BLUEPRINT := "res://data/body/blueprints/kit_human.tres"
const PLAYERS_GROUP := "players"
## Группа цели камеры: куклы игроков и машина.
const CAM_GROUP := "convoy_cam"
## Сесть / выйти: P1 — F, P2 — «\» и Num . (рядом со стрелками; «/» и Num 0 — рука P2), геймпад — Y.
const CAR_ACTIONS := {"p1_car": [KEY_F], "p2_car": [KEY_BACKSLASH, KEY_KP_PERIOD]}
const COM_LIFT := 1.0
const BRIDGE_SETTLE_S := 0.25
## Названия участков для HUD (ключи перевода; в сцене — коды).
const SECTION_TITLES := {"start": "СТАРТ", "flat": "РОВНО", "bumps": "КОЧКИ", "runup": "РАЗГОН", "hill": "ПОДЪЁМ", "pit": "ПРОВАЛ",
	"descent": "СПУСК", "finish": "ФИНИШ"}

## Начало кузова машины на старте (сборщик), м.
@export var car_start := Vector3(2.5, 0.55, 0.0)
## Линия старта (часы идут, когда ЦМ машины за ней) и финиша, м по x.
@export var start_x := 2.0
@export var finish_x := 99.0
## Провал: x кромок и высота дороги у провала.
@export var pit_x0 := 71.0
@export var pit_x1 := 74.4
@export var pit_top_y := 5.5
## Места досок на стеллаже (центры).
@export var plank_spots := PackedVector3Array()
## Весь участок (камера и спавн): x, y, ширина, высота.
@export var level_rect := Rect2(-11.0, -3.0, 116.0, 26.0)
## Участки для HUD: [x начала, код] (сборщик); название — SECTION_TITLES[код].
@export var sections: Array = []
## P2 сразу в игре (пробы); обычно — с первого нажатия.
@export var p2_on_start := false
## Сам заходит ли P2 по первому нажатию своих клавиш (пробы выключают).
@export var auto_join := true
## Пробы: не спавнить игроков (куклы — свои).
@export var spawn_players := true

var car: ConvoyCar
var p1: Doll
var p2: Doll
var cargo: Array[ConvoyCargo] = []
var planks: Array[ConvoyCargo] = []
var time_s := 0.0
var running := false
var done := false
var delivered := 0
var resets := 0
var pit_t := 0.0
## Последнее действие клавиши машины (пробы): "enter" | "exit" | "busy" | "far" | "".
var last_car_action := ""
var _zoom_before := 1.0
static var _actions_done := false

@onready var match_node: ConvoyMatch = $Match
@onready var hud: ConvoyHud = $HUD
@onready var cam: DynamicCamera = $Camera
@onready var dolls_root: Node3D = $Dolls


func _enter_tree() -> void:
	_zoom_before = DynamicCamera.user_zoom
	DynamicCamera.user_zoom = 1.0


func _exit_tree() -> void:
	DynamicCamera.user_zoom = _zoom_before


func _ready() -> void:
	ensure_actions()
	PuzzleKeyArm.ensure_action()
	car = get_node_or_null("Car") as ConvoyCar
	if car == null:
		car = ConvoyCar.new()
		car.name = "Car"
		car.position = car_start
		add_child(car)
	car.add_to_group(CAM_GROUP)
	_spawn_cargo()
	_spawn_planks()
	if spawn_players:
		p1 = _spawn_player(0)
		if p2_on_start:
			join_p2()
	hud.bind(self)
	match_node.doll_replaced.connect(_on_doll_replaced)
	car.driver_changed.connect(func(_d: Doll) -> void: hud.refresh_help())
	car.uprighted.connect(func(teleported: bool) -> void:
		hud.toast(tr("Кран NULL поставил машину на колёса") if not teleported else tr("Машину переставили на колёса")))
	cam.snap()


static func ensure_actions() -> void:
	if _actions_done and InputMap.has_action("p1_car"):
		return
	_actions_done = true
	var dev := 0
	for a in CAR_ACTIONS:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.5)
			for k in CAR_ACTIONS[a]:
				var e := InputEventKey.new()
				e.physical_keycode = k
				InputMap.action_add_event(a, e)
			var jb := InputEventJoypadButton.new()
			jb.device = dev
			jb.button_index = JOY_BUTTON_Y
			InputMap.action_add_event(a, jb)
		dev += 1


# --- арена для Match и камеры ---

func bounds() -> AABB:
	return AABB(Vector3(level_rect.position.x, level_rect.position.y, -2.0), Vector3(level_rect.size.x, level_rect.size.y, 4.0))


## Точки появления: над машиной сзади (кукла не встаёт в кузов и не цепляет груз).
func spawn_points() -> Array[Vector3]:
	var base := car.chassis.global_position if car != null and car.chassis != null else car_start
	return [base + Vector3(-3.6, 1.6, 0.0), base + Vector3(-5.0, 2.2, 0.0)]


# --- игроки ---

## Кукла игрока i: «Человек», рубашка — цвет игрока, ввод с клавиатуры / мыши / геймпада.
static func make_player(i: int) -> ModularDoll:
	var bp := (load(BLUEPRINT) as BodyBlueprint).duplicate(true) as BodyBlueprint
	bp.id = "convoy_%d" % i
	var d := DOLL_SCENE.instantiate() as ModularDoll
	d.blueprint = bp
	d.name = "P%d" % (i + 1)
	d.player_index = i
	d.input_prefix = "p%d" % (i + 1)
	d.external_input = false
	d.add_to_group("dolls")
	d.add_to_group(PLAYERS_GROUP)
	d.add_to_group(CAM_GROUP)
	return d


func _spawn_player(i: int) -> Doll:
	var d := make_player(i)
	var pts := spawn_points()
	d.position = pts[mini(i, pts.size() - 1)]
	dolls_root.add_child(d)
	ArmAssist.attach_to(d)
	if i == 1:
		PuzzleKeyArm.attach_to(d)
	match_node.register(d)
	return d


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
	hud.refresh_help()


func leave_p2() -> void:
	if p2 == null or not is_instance_valid(p2):
		p2 = null
		return
	if car.driver == p2:
		car.exit_driver()
	var a := _arm(p2)
	if a != null:
		a.release("leave")
	dolls_root.remove_child(p2)
	p2.queue_free()
	p2 = null
	p2_changed.emit(false)
	hud.refresh_help()


func _on_doll_replaced(old: Doll, new_doll: Doll) -> void:
	if old == p1:
		p1 = new_doll
	elif old == p2:
		p2 = new_doll


static func _arm(d: Doll) -> ArmAssist:
	if d == null or not is_instance_valid(d):
		return null
	for c in d.get_children():
		if c is ArmAssist and (c as ArmAssist).primary:
			return c
	return null


## Перенести куклу целиком так, чтобы её ЦМ встал в to + COM_LIFT вверх; скорости — ноль. Что в руке — отпускается.
func teleport(d: Doll, to: Vector3) -> void:
	var a := _arm(d)
	if a != null:
		a.release("reset")
		a.clear_target_override()
	var shift := to + Vector3(0, COM_LIFT, 0) - d.centre_of_mass()
	shift.z = 0.0
	for p in d.parts.values():
		var b := p as RigidBody3D
		if b == null or not is_instance_valid(b):
			continue
		b.global_position += shift
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
		b.reset_physics_interpolation()


# --- машина, груз, доски ---

func _spawn_cargo() -> void:
	for c in cargo:
		if is_instance_valid(c):
			c.queue_free()
	cargo.clear()
	var holder := get_node_or_null("Cargo")
	if holder == null:
		holder = Node3D.new()
		holder.name = "Cargo"
		add_child(holder)
	for i in Tuning.CONVOY_CARGO.size():
		var e: Array = Tuning.CONVOY_CARGO[i]
		var c := ConvoyCargo.new()
		c.name = "Cargo%d" % i
		c.kind = String(e[0])
		c.cargo_mass = float(e[1])
		holder.add_child(c)
		cargo.append(c)
	load_cargo()


## Уложить весь груз в кузов (рестарт участка).
func load_cargo() -> void:
	car.load_cargo(cargo)


func _spawn_planks() -> void:
	for p in planks:
		if is_instance_valid(p):
			p.queue_free()
	planks.clear()
	var holder := get_node_or_null("Planks")
	if holder == null:
		holder = Node3D.new()
		holder.name = "Planks"
		add_child(holder)
	for i in Tuning.CONVOY_PLANKS:
		var p := ConvoyCargo.new()
		p.name = "Plank%d" % i
		p.kind = "plank"
		p.position = plank_spots[i] if i < plank_spots.size() else Vector3(pit_x0 - 4.0, pit_top_y + 3.8 + 0.2 * i, 0.0)
		holder.add_child(p)
		planks.append(p)


## Доска лежит поперёк провала: оба конца над дорогой, почти горизонтально, на уровне дороги.
func plank_across(p: ConvoyCargo) -> bool:
	if p == null or not is_instance_valid(p):
		return false
	var a := absf(wrapf(p.rotation.z, -PI * 0.5, PI * 0.5))
	var half := p.size.x * 0.5 * cos(a)
	var pos := p.global_position
	return pos.x - half < pit_x0 - 0.02 and pos.x + half > pit_x1 + 0.02 and a < deg_to_rad(15.0) \
		and absf(pos.y - (pit_top_y + p.size.y * 0.5)) < 0.4


func bridges() -> int:
	var n := 0
	for p in planks:
		if is_instance_valid(p) and p.bridged:
			n += 1
	return n


## Доска, отпущенная поперёк провала и успокоившаяся на BRIDGE_SETTLE_S, «ложится в пазы»: ровно на дорогу и замораживается — мост.
## Иначе машина, наезжая колесом на торец, сталкивала бы лёгкую доску в провал (проба: с 0.5 м опоры на краю доска уезжала).
## Доска в руке держится ровно (горизонтально в мире): момент к ближнему из 0° / 180°, без реакции в куклу. Удержание угла самой руки
## (ArmAssist, 30 Н·м и относительно кисти) длинную доску за конец не держит: на разгоне куклы доска 4.4 м проворачивалась (проба).
func _level_held(p: ConvoyCargo) -> void:
	var x := p.global_basis.x
	var a := atan2(x.y, x.x)
	var err := wrapf(-a, -PI * 0.5, PI * 0.5)
	var inertia := p.mass * p.size.x * p.size.x / 12.0
	var w := Tuning.CONVOY_PLANK_LEVEL_OMEGA
	var t := inertia * (w * w * err - 2.0 * 0.9 * w * p.angular_velocity.z)
	p.apply_torque(Vector3(0.0, 0.0, clampf(t, -Tuning.CONVOY_PLANK_LEVEL_TORQUE, Tuning.CONVOY_PLANK_LEVEL_TORQUE)))


func _tick_planks(delta: float) -> void:
	for p in planks:
		if not is_instance_valid(p) or p.bridged:
			continue
		var held := ArmAssist.holder_of(p) != null
		if held:
			_level_held(p)
		var t := float(p.get_meta(&"bridge_t", 0.0))
		if not held and plank_across(p) and p.linear_velocity.length() < 0.8:
			t += delta
		else:
			t = 0.0
		p.set_meta(&"bridge_t", t)
		if t >= BRIDGE_SETTLE_S:
			var half := p.size.x * 0.5
			var x := clampf(p.global_position.x, pit_x1 + 0.2 - half, pit_x0 - 0.2 + half)
			p.set_bridged(true, Transform3D(Basis(), Vector3(x, pit_top_y + p.size.y * 0.5, 0.0)))
			hud.toast(tr("Доска легла поперёк — мост готов"))


func cargo_in_bed() -> int:
	var n := 0
	for c in cargo:
		if is_instance_valid(c) and car.in_bed(c):
			n += 1
	return n


## Машину — на старт участка; что лежит в кузове, едет с ней (как лежало). reason — для HUD и проб.
func reset_car(reason: String) -> void:
	var carried: Array = []
	var inv := car.chassis.global_transform.affine_inverse()
	for c in cargo:
		if is_instance_valid(c) and car.in_bed(c):
			carried.append([c, inv * c.global_transform])
	car.reset_state()
	car.place(car_start)
	for e in carried:
		var c: ConvoyCargo = e[0]
		c.global_transform = car.chassis.global_transform * (e[1] as Transform3D)
		c.linear_velocity = Vector3.ZERO
		c.angular_velocity = Vector3.ZERO
		c.reset_physics_interpolation()
		c.sleeping = false
	pit_t = 0.0
	resets += 1
	car_reset.emit(reason)
	if reason == "pit":
		hud.toast(tr("Машина в провале — назад на старт. Положи доску поперёк провала"))
	elif reason == "void":
		hud.toast(tr("Машина улетела с дороги — назад на старт"))


## R: участок заново — машина, весь груз и доски на места, игроки у машины, время с нуля.
func restart() -> void:
	if car.driver != null:
		car.exit_driver()
	car.reset_state()
	car.place(car_start)
	load_cargo()
	for p in planks:
		if is_instance_valid(p):
			var a := ArmAssist.holder_of(p)
			if a != null:
				a.release("reset")
			p.go_home()
	var pts := spawn_points()
	var k := 0
	for d in players():
		teleport(d, pts[mini(k, pts.size() - 1)])
		k += 1
	time_s = 0.0
	running = false
	done = false
	delivered = 0
	resets = 0
	pit_t = 0.0
	hud.hide_end()
	hud.refresh_help()


## Клавиша машины у куклы d: в кабине — выйти; рядом с дверью и место свободно — сесть.
func toggle_car(d: Doll) -> String:
	if d == null or not is_instance_valid(d):
		last_car_action = ""
		return ""
	if car.driver == d:
		car.exit_driver()
		last_car_action = "exit"
	elif car.driver != null:
		last_car_action = "busy"
		hud.toast(tr("За рулём уже другой игрок"))
	elif car.enter(d):
		last_car_action = "enter"
	else:
		last_car_action = "far"
		hud.toast(tr("Подлети к двери кабины (жёлтая кабина спереди)"))
	return last_car_action


func progress_m() -> float:
	return clampf(car.centre_of_mass(false).x - start_x, 0.0, finish_x - start_x)


## Код участка, где сейчас машина ("" — до первого).
func section_code() -> String:
	var x := car.centre_of_mass(false).x
	var out := ""
	for s in sections:
		if x >= float(s[0]):
			out = String(s[1])
	return out


## Название участка для HUD (переведённое).
func section_title() -> String:
	return tr(String(SECTION_TITLES.get(section_code(), "СТАРТ")))


func _physics_process(delta: float) -> void:
	if car == null or car.chassis == null:
		return
	var com := car.centre_of_mass(false)
	if not running and not done and com.x > start_x + 0.5:
		running = true
	if running and not done:
		time_s += delta
	if not done and com.x >= finish_x and car.crane_t < 0.0:
		done = true
		running = false
		delivered = cargo_in_bed()
		finished.emit(time_s, delivered, cargo.size())
		return
	_tick_planks(delta)
	# провал: колесо между кромками ниже дороги (машина клюнула носом и застряла) или ЦМ машины ниже кромки — ждём PIT_RESET_S
	var in_pit := com.x > pit_x0 - 1.0 and com.x < pit_x1 + 1.0 and com.y < pit_top_y - Tuning.CONVOY_PIT_DROP_M
	for w in car.wheels:
		var wp := w.global_position
		if wp.x > pit_x0 + 0.1 and wp.x < pit_x1 - 0.1 and wp.y < pit_top_y - 0.3:
			in_pit = true
	var lost := com.y < level_rect.position.y - 2.0 or com.x < level_rect.position.x - 2.0 or com.x > level_rect.end.x + 2.0
	if in_pit or lost:
		pit_t += delta
		if pit_t >= Tuning.CONVOY_PIT_RESET_S:
			reset_car("pit" if in_pit else "void")
	else:
		pit_t = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	if event.is_action_pressed("p1_car") and not event.is_echo():
		toggle_car(p1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("p2_car") and not event.is_echo():
		if p2 == null or not is_instance_valid(p2):
			join_p2()
			hud.toast(tr("P2 в игре: стрелки, рука — «/» или Num 0, машина — «\\» или Num ."))
		else:
			toggle_car(p2)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_R:
				restart()
				hud.toast(tr("Участок заново"))
				return
			KEY_U:
				if p2 != null and is_instance_valid(p2):
					leave_p2()
					hud.toast(tr("P2 ушёл — играешь один"))
				else:
					join_p2()
					hud.toast(tr("P2 в игре: стрелки, рука — «/» или Num 0, машина — «\\» или Num ."))
				return
			KEY_ENTER, KEY_KP_ENTER:
				if done:
					restart()
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
		for a in ["p2_left", "p2_right", "p2_up", "p2_down", "p2_dash", "p2_flip", "p2_grab", PuzzleKeyArm.ACTION]:
			if InputMap.has_action(a) and event.is_action(a):
				join_p2()
				hud.toast(tr("P2 в игре: стрелки, рука — «/» или Num 0, машина — «\\» или Num ."))
				return
