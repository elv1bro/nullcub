## Площадка: арена + две куклы на клавиатуре (P1 — клён doll.tscn, P2 — орех doll_dark.tscn) + оружие + динамическая камера
## + Match (scripts/core/match.gd: фазы, урон через DollCombat, KO, Sudden Death, итоги) + HUD (scenes/ui/hud.tscn, привязан к Match).
## Дерево (арена, P1/P2 с WeaponPickup, Weapons, Camera, Match, HUD, UI/Hint) живёт в сцене: scenes/playground.tscn — «Руины»,
## scenes/playground_workshop.tscn — «Мастерская», scenes/playground_void.tscn — «Void» (пустое чёрное поле RM, без оружия;
## Weapons там пустой — только молот Sudden Death) (ASSET_PIPELINE.md, правило 2). Здесь только поведение:
##   R — match.restart() (куклы пересоздаются на точках спавна арены), Esc — выход, 1 / 2 / 3 — сменить арену
##   (Руины / Мастерская / Void);
##   пропасть (сигнал body_fell арены): во время боя — Doll.knock_out() (KO kind "self", Match сам заканчивает матч), иначе —
##   респавн через RESPAWN_DELAY_S через Match.respawn_doll (той же породы дерева);
##   Sudden Death (Match.sudden_death_step): шаг SUDDEN_DEATH_HEAVY_WEAPON_STEP — молот падает в центр арены,
##   SUDDEN_DEATH_BREAK_PLATFORMS_STEP — верёвочные мосты арены (RopeBridge.break_apart) обрываются;
##   камера: snap на отсчёте (после рестарта куклы стоят на новых местах); меши оружия → gi_mode DYNAMIC (SDFGI в окружении).
## Щепки/пыль (ImpactFx) и урон считает DollCombat — ребёнок каждой куклы, его добавляет Match.register.
## P1: WASD, Shift рывок, Space переворот. P2: стрелки, правый Ctrl рывок, Enter переворот.
extends Node3D

const SCENES := {"ruins": "res://scenes/playground.tscn", "workshop": "res://scenes/playground_workshop.tscn", "void": "res://scenes/playground_void.tscn"}
const DOLLS_GROUP := "dolls"
const RESPAWN_DELAY_S := 1.0
const SD_HAMMER_DROP_M := 1.5      # молот Sudden Death появляется на столько метров ниже потолка арены и падает

## Идентификатор текущей арены (ключ SCENES) — какую сцену НЕ перезагружать по 1/2/3.
@export var arena_id := "ruins"

var arena: Node3D                  # RuinsArena | WorkshopArena | VoidArena: spawn_points(), bounds(), сигнал body_fell
var hits := 0                      # число ударов с начала (Match.hit) — читают тесты
var sd_hammer: Weapon = null       # молот Sudden Death (один на матч)

@onready var cam: DynamicCamera = $Camera
@onready var match_node: Match = $Match
@onready var hud: Hud = $HUD
@onready var weapons_root: Node3D = $Weapons


func _ready() -> void:
	arena = _find_arena()
	if arena != null and arena.has_signal("body_fell"):
		arena.connect("body_fell", _on_body_fell)
	hud.bind(match_node)
	match_node.phase_changed.connect(_on_phase_changed)
	match_node.sudden_death_step.connect(_on_sudden_death_step)
	match_node.hit.connect(func(_v: Doll, _a: Node, _d: float, _k: String, _p: Vector3) -> void: hits += 1)
	_set_gi_dynamic(weapons_root)


## Арена — первый ребёнок с spawn_points() (Ruins / Workshop / Void).
func _find_arena() -> Node3D:
	for c in get_children():
		if c is Node3D and c.has_method("spawn_points"):
			return c
	return null


func dolls() -> Array:
	var out: Array = []
	for c in get_children():
		if c is Doll and c.is_in_group(DOLLS_GROUP):
			out.append(c)
	return out


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				match_node.restart()
			KEY_ESCAPE:
				get_tree().quit()
			KEY_1:
				switch_arena("ruins")
			KEY_2:
				switch_arena("workshop")
			KEY_3:
				switch_arena("void")


## Смена арены: загрузка другой площадки целиком (Match._exit_tree возвращает Engine.time_scale = 1).
func switch_arena(id: String) -> void:
	if id == arena_id or not SCENES.has(id):
		return
	get_tree().change_scene_to_file(SCENES[id])


func respawn_all() -> void:
	match_node.restart()


## Заменяет куклу новым инстансом её сцены на её точке спавна (делегирует Match.respawn_doll). Возвращает новую.
func respawn(old: Doll) -> Doll:
	return match_node.respawn_doll(old)


func _on_phase_changed(p: int) -> void:
	if p == Match.Phase.COUNTDOWN:
		cam.snap()
		if is_instance_valid(sd_hammer):
			sd_hammer.queue_free()
		sd_hammer = null


func _on_body_fell(body: Node3D) -> void:
	var d := body.get_parent() as Doll
	if d == null or not d.is_in_group(DOLLS_GROUP) or not d.alive:
		return   # оружие и части уже разбитой куклы падают дальше
	d.knock_out()   # KO kind "self"; во время боя Match учитывает его как обычное KO и сам завершает матч
	if match_node.combat_active():
		return
	get_tree().create_timer(RESPAWN_DELAY_S).timeout.connect(func() -> void:
		if is_instance_valid(d) and d.is_inside_tree():
			match_node.respawn_doll(d))


## Sudden Death (CONCEPT.md §12, В8): n = 1 — молот в центре арены, n = 3 — мосты рвутся.
func _on_sudden_death_step(n: int) -> void:
	if n == Tuning.SUDDEN_DEATH_HEAVY_WEAPON_STEP and sd_hammer == null:
		var b: AABB = arena.call("bounds") if arena != null and arena.has_method("bounds") else cam.bounds()
		var pos := Vector3(b.get_center().x, b.end.y - SD_HAMMER_DROP_M, 0.0)
		sd_hammer = Weapon.spawn("hammer", weapons_root, pos, 0.0)
		if sd_hammer != null:
			_set_gi_dynamic(sd_hammer)
	elif n == Tuning.SUDDEN_DEATH_BREAK_PLATFORMS_STEP and arena != null and arena.has_method("rope_bridges"):
		for rb in arena.call("rope_bridges"):
			if rb.has_method("break_apart"):
				rb.call("break_apart")


func _set_gi_dynamic(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	for c in n.get_children():
		_set_gi_dynamic(c)
