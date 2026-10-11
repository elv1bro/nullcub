## Инструменты испытания мастерской (docs/plan-demo/MODES_100.md §B; автор 08.10: «облегчить работу в мастерской… на тестирование
## разные режимы, сейчас это утомляет»). Всё — без выхода из зала: клавиши в режиме TEST (WorkshopBuild._input):
##   B — бот-спарринг: кукла-кит «Человек» с мозгом RivalBrain, уровень 1 → 2 → 3 → нет; бьёт по кукле игрока и получает сдачи,
##       после нокаута любого — тот встаёт через RESPAWN_S на своей точке (бой не кончается, как с манекеном);
##   G — гравитация зала: обычная → ноль → половина → ×2.5 → вбок (гравитация мира: PhysicsServer3D; stop_test возвращает);
##   C — прочность суставов, ; — запас из деталей (те же статики, что в бою);
##   Y — «Испытать в режиме…»: чертёж со стенда → экран РЕЖИМЫ (ModesMenu.player_blueprint), после боя — обратно в мастерскую
##       (Flow.reopen_workshop; гараж открывает её сам).
## Состояние (уровень бота, гравитация) живёт в статиках — R (заново) и следующее испытание его не теряют.
class_name WsTestTools
extends RefCounted

const KIT_HUMAN := "res://data/body/blueprints/kit_human.tres"
const MODULAR_DOLL := "res://scenes/body/modular_doll.tscn"
const SPARRING_NAME := "Sparring"
const RESPAWN_S := 2.0
const SPARRING_OFFSET := Vector3(3.0, 0.02, 0.0)   # от куклы игрока, если нет точки манекена
## Гравитация зала: подпись и (множитель, направление).
const GRAVITY_STEPS := [
	["обычная", 1.0, Vector2(0, -1)], ["ноль", 0.0, Vector2(0, -1)], ["половина", 0.5, Vector2(0, -1)],
	["×2.5", 2.5, Vector2(0, -1)], ["вбок", 1.0, Vector2(1, 0)],
]

static var sparring_level := 0      # 0 — нет бота
static var gravity_step := 0


## Бот-спарринг в зал: ModularDoll kit_human + RivalBrain(level); кукла игрока — в группу players, бот — rivals + группа камеры.
static func spawn_sparring(ws: Node, level: int) -> Doll:
	var player: Doll = ws.get("test_doll")
	var root: Node = ws.get("test_root")
	if player == null or root == null:
		return null
	clear_sparring(ws)
	var bp := load(KIT_HUMAN) as BodyBlueprint
	var ps := load(MODULAR_DOLL) as PackedScene
	if bp == null or ps == null:
		return null
	var d := ps.instantiate() as Doll
	d.set("blueprint", CraftEdit.dup_body(bp))
	d.name = SPARRING_NAME
	d.player_index = 1
	d.input_prefix = "bot1"
	d.external_input = true
	d.add_to_group("rivals")
	d.add_to_group(String(ws.get("TEST_GROUP")))
	player.add_to_group("players")
	var pos := _sparring_pos(ws, player)
	root.add_child(d)
	d.global_position = pos
	var combat := DollCombat.new()
	combat.name = "DollCombat"
	d.add_child(combat)
	var b := RivalBrain.new()
	b.name = "Brain"
	b.level = clampi(level, 1, 3)
	d.add_child(b)
	d.knocked_out.connect(func(_a: Node, _r: Dictionary) -> void: _respawn_later(ws, d, level))
	if not player.knocked_out.is_connected(_on_player_ko):
		player.knocked_out.connect(_on_player_ko.bind(ws))
	return d


static func _sparring_pos(ws: Node, player: Doll) -> Vector3:
	var spot: Node3D = ws.get("dummy_spot")
	if spot != null:
		var p := spot.global_position
		return Vector3(p.x, maxf(p.y, player.global_position.y), 0.0)
	return player.global_position + SPARRING_OFFSET


static func _respawn_later(ws: Node, d: Doll, level: int) -> void:
	var tree := ws.get_tree() if ws is Node else null
	if tree == null:
		return
	await tree.create_timer(RESPAWN_S).timeout
	if not is_instance_valid(ws) or sparring_level <= 0 or ws.get("test_doll") == null:
		return
	if is_instance_valid(d) and d.get_parent() != null:
		spawn_sparring(ws, level)


## Кукла игрока в нокауте: через RESPAWN_S — испытание заново (бот остаётся, уровень в статике).
static func _on_player_ko(_a: Node, _r: Dictionary, ws: Node) -> void:
	var tree := ws.get_tree() if ws is Node else null
	if tree == null:
		return
	await tree.create_timer(RESPAWN_S).timeout
	if is_instance_valid(ws) and ws.has_method("restart_test") and ws.get("test_doll") != null:
		ws.call("restart_test")


static func clear_sparring(ws: Node) -> void:
	var root: Node = ws.get("test_root")
	if root == null:
		return
	var old := root.get_node_or_null(SPARRING_NAME)
	if old != null:
		root.remove_child(old)
		old.queue_free()


static func sparring(ws: Node) -> Doll:
	var root: Node = ws.get("test_root")
	return root.get_node_or_null(SPARRING_NAME) as Doll if root != null else null


## B: уровень 0 → 1 → 2 → 3 → 0. Возвращает подпись для _say.
static func cycle_sparring(ws: Node) -> String:
	return set_sparring(ws, (sparring_level + 1) % 4)


static func set_sparring(ws: Node, level: int) -> String:
	sparring_level = clampi(level, 0, 3)
	if sparring_level == 0:
		clear_sparring(ws)
		return TranslationServer.translate("Спарринг: нет бота   (B — бот)")
	spawn_sparring(ws, sparring_level)
	return TranslationServer.translate("Спарринг: бот уровня %d   (B — следующий)") % sparring_level


# --- гравитация зала ---

static func cycle_gravity(ws: Node) -> String:
	return set_gravity(ws, (gravity_step + 1) % GRAVITY_STEPS.size())


static func set_gravity(ws: Node, step: int) -> String:
	gravity_step = clampi(step, 0, GRAVITY_STEPS.size() - 1)
	var s: Array = GRAVITY_STEPS[gravity_step]
	apply_gravity(ws)
	return TranslationServer.translate("Гравитация зала: %s   (G — следующая)") % TranslationServer.translate(String(s[0]))


static func apply_gravity(ws: Node) -> void:
	var space := _space(ws)
	if not space.is_valid():
		return
	var s: Array = GRAVITY_STEPS[gravity_step]
	var dir := (s[2] as Vector2).normalized()
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, Tuning.GRAVITY * float(s[1]))
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, Vector3(dir.x, dir.y, 0.0))


static func restore_gravity(ws: Node) -> void:
	if ws is Node and (ws as Node).is_inside_tree():
		ModeCtx.restore_world_gravity((ws as Node).get_tree())


static func _space(ws: Node) -> RID:
	if ws is Node3D and (ws as Node3D).is_inside_tree():
		return (ws as Node3D).get_world_3d().space
	return RID()


static func gravity_label() -> String:
	return TranslationServer.translate(String((GRAVITY_STEPS[gravity_step] as Array)[0]))


## Подсказка испытания (строка под кадром).
static func hint() -> String:
	return TranslationServer.translate("Испытание! Esc / Tab — к сборке   ·   R — заново   ·   B — бот   ·   G — гравитация   ·   C — суставы   ·   ; — запас   ·   Y — в режиме…")
