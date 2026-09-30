## Матч (план 06 + 09, CONCEPT.md §1, §10, §12, §19–§20): фазы COUNTDOWN → FIGHT → SUDDEN_DEATH → OVER, таймеры, KO, итоги.
## Узел кладётся в площадку (интегратор); куклы — группа dolls_group ("dolls"), каждой добавляется ребёнок DollCombat
## (если его нет) и подписка на damaged/knocked_out. Новые куклы в группе (респавн площадкой) подхватываются на лету.
##
## Сигналы для HUD (scenes/ui/hud.gd подписывается по именам): phase_changed, time_left, announce (FIGHT!, HEAD BLOW!, BODY BLOW!,
## DOUBLE BLOW!, «N HIT COMBO!», KO!, SUDDEN DEATH; цвет по виду), hp_changed, combo_changed, ko, match_over.
## Sudden Death (В8): с time_limit_s шаг n = floor((t − time_limit_s) / SUDDEN_DEATH_STEP_S): knockback ×(1 + 0.25n), мышцы/трение
## ×max(0.3, 1 − 0.15n) через Doll.set_stability; урон не растёт. Молот на n=1 и мост на n=3 — сигнал sudden_death_step(n) для арены.
## Hard timeout: места по ключу HP → нанесённый урон → меньше полученного → сильнейший удар → ничья. KO: последний живой побеждает;
## все оставшиеся выбыли в одном тике физики (голова о голову) — ничья, победитель только живой (build_results).
## Итоги: {places, ranks, stats: {doll: stats}, medals: {name: doll}, winner, draw, reason, duration_s, ko_records, combo_score: {doll: float}}.
## Медали (09): Winner, Hardest Hit, Frequent Flyer, Wall Inspector, Weapon Master, Self Destruction, Acrobat, Survivor
## (одна медаль — один игрок, при нулевом показателе не выдаётся; Showman — только с вебкой, этап 10).
## hit_feel(strength, position): тряска и zoom impulse DynamicCamera (camera_path | группа "camera" | текущая камера) и hit stop
## через Engine.time_scale (80 мс от 20 HP, 120 мс от 35 HP), KO — slow-mo 0.25× на 1.2 с; таймеры в реальном времени.
## restart(): все куклы инстанцируются заново на точках спавна арены (arena_path | группа "arena" | сосед с spawn_points()),
## respawn_doll(old) доступен площадке (пропасть и R).
class_name Match
extends Node

enum Phase { COUNTDOWN, FIGHT, SUDDEN_DEATH, OVER }

signal phase_changed(phase: int)
signal time_left(seconds: float)
signal announce(text: String, color: Color, kind: String)
signal hp_changed(doll: Doll, hp: float, max_hp: float)
signal combo_changed(doll: Doll, n: int)
signal ko(victim: Doll, attacker: Node, record: Dictionary)
signal match_over(winner: Doll, results: Dictionary)
## Дополнительно: каждый удар (для FX/звука/highlight 09), шаг Sudden Death (арена: молот, мост), замена куклы (камера, площадка).
signal hit(victim: Doll, attacker: Node, damage: float, kind: String, position: Vector3)
signal sudden_death_step(n: int)
signal doll_replaced(old_doll: Doll, new_doll: Doll)

const GROUP := "match"
const DollCombatScript := preload("res://scripts/core/doll_combat.gd")
const DEFAULT_DOLL_SCENE := "res://scenes/doll/doll.tscn"
const ANNOUNCE_COLORS := {
	"fight": Color(1.0, 0.85, 0.3), "countdown": Color(0.95, 0.95, 0.95), "head": Color(0.95, 0.2, 0.15),
	"body": Color(0.35, 0.9, 0.35), "double": Color(1.0, 1.0, 1.0), "ko": Color(1.0, 0.25, 0.2), "sudden_death": Color(1.0, 0.3, 0.2),
}
const COMBO_COLORS := [Color(1.0, 0.9, 0.3), Color(1.0, 0.6, 0.2), Color(1.0, 0.35, 0.6), Color(0.7, 0.4, 1.0)]
const SCAN_INTERVAL_S := 0.5

@export var time_limit_s: float = Tuning.BATTLE_TIME_LIMIT_S
@export var hard_timeout_s: float = Tuning.BATTLE_HARD_TIMEOUT_S
@export var countdown_s: float = Tuning.COUNTDOWN_S
@export var autostart := true
## Тряска/зум/hit stop/slow-mo (выключается в headless-тестах для детерминизма).
@export var feel_enabled := true
@export var camera_path: NodePath
@export var arena_path: NodePath
@export var dolls_group := "dolls"

var phase: int = Phase.OVER
var sd_step := -1
## Время боя (с FIGHT!, физическое).
var fight_time := 0.0
var ko_records: Array = []

var _countdown_left := 0.0
var _countdown_shown := -1
var _order: Array = []          # куклы в порядке регистрации (Array[Doll])
var _spawn: Dictionary = {}     # doll -> Vector3 (позиция при регистрации; fallback, если у арены нет spawn_points)
var _scan_t := 0.0
var _started := false
var _time_effects: Array = []   # [{"scale": float, "left": float}] — hit stop / slow-mo в реальных секундах


func _ready() -> void:
	ImpactFx.prewarm(self)  # шейдеры вспышек/частиц до первого удара
	add_to_group(GROUP)
	call_deferred("_late_ready")


func _late_ready() -> void:
	_scan_dolls()
	if autostart:
		begin()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


# --- куклы ---

func dolls() -> Array:
	var out: Array = []
	for d in _order:
		if is_instance_valid(d):
			out.append(d)
	return out


func alive_dolls() -> Array:
	var out: Array = []
	for d in dolls():
		if (d as Doll).alive:
			out.append(d)
	return out


func _scan_dolls() -> void:
	for n in get_tree().get_nodes_in_group(dolls_group):
		if n is Doll and not _order.has(n):
			register(n)


## Регистрирует куклу: DollCombat-ребёнок, подписки, точка спавна по умолчанию.
func register(d: Doll) -> void:
	if _order.has(d):
		return
	_order.append(d)
	if not _spawn.has(d):
		_spawn[d] = d.global_position
	var c := combat_of(d)
	if c == null:
		c = DollCombatScript.new()
		c.name = "DollCombat"
		c.match_ref = self
		d.add_child(c)
	else:
		c.match_ref = self
	d.knocked_out.connect(_on_doll_ko.bind(d))
	d.damaged.connect(_on_doll_damaged.bind(d))
	d.tree_exiting.connect(_unregister.bind(d))
	if phase == Phase.SUDDEN_DEATH and sd_step >= 0:
		d.set_stability(Damage.sd_stability_mult(sd_step))


func _unregister(d: Doll) -> void:
	_order.erase(d)
	_spawn.erase(d)


static func combat_of(d: Doll) -> DollCombat:
	for c in d.get_children():
		if c is DollCombat:
			return c
	return null


func _arena() -> Node:
	var a: Node = get_node_or_null(arena_path) if arena_path != NodePath() else null
	if a == null:
		a = get_tree().get_first_node_in_group("arena")
	if a == null and get_parent() != null:
		for s in get_parent().get_children():
			if s != self and s.has_method("spawn_points"):
				a = s
				break
	return a


## Точка спавна куклы: spawn_points()[player_index] арены, иначе позиция при регистрации.
func spawn_point_for(d: Doll) -> Vector3:
	var a := _arena()
	if a != null and a.has_method("spawn_points"):
		var pts: Array = a.call("spawn_points")
		if d.player_index >= 0 and d.player_index < pts.size():
			return pts[d.player_index]
	if _spawn.has(d):
		return _spawn[d]
	return d.global_position


## Заменяет куклу новым инстансом её сцены (doll.tscn / doll_dark.tscn) с теми же настройками на точке спавна, переносит
## скриптовые узлы-дети (WeaponPickup и т. п.), регистрирует, шлёт doll_replaced. Возвращает новую куклу.
func respawn_doll(old: Doll) -> Doll:
	var parent := old.get_parent()
	if parent == null:
		return old
	var ps: PackedScene = null
	if old.scene_file_path != "":
		ps = load(old.scene_file_path) as PackedScene
	if ps == null:
		ps = load(DEFAULT_DOLL_SCENE) as PackedScene
	var d: Doll = ps.instantiate()
	d.player_index = old.player_index
	d.input_prefix = old.input_prefix
	d.external_input = old.external_input
	d.control_enabled = old.control_enabled
	d.muscle_stiffness = old.muscle_stiffness
	d.muscle_damping = old.muscle_damping
	d.muscle_max_torque = old.muscle_max_torque
	d.joint_friction = old.joint_friction
	d.self_collision = old.self_collision
	d.skin_scene = old.skin_scene
	d.skin_mode = old.skin_mode
	d.skin_bone_map = old.skin_bone_map
	d.control_mode = old.control_mode
	d.control_target = old.control_target
	for g in old.get_groups():
		d.add_to_group(g)
	if not d.is_in_group(dolls_group):
		d.add_to_group(dolls_group)
	var extra: Array = []
	for c in old.get_children():
		if c is DollCombat or c is RigidBody3D or c is Joint3D or c.get_script() == null:
			continue
		var scr: Script = c.get_script()
		var n: Object = scr.new()
		if n is Node:
			(n as Node).name = c.name
			extra.append(n)
	var pos := spawn_point_for(old)
	var name_ := old.name
	var idx := old.get_index()
	var spawn_saved: Variant = _spawn.get(old, null)
	_order.erase(old)
	_spawn.erase(old)
	parent.remove_child(old)
	old.queue_free()
	d.name = name_
	parent.add_child(d)
	parent.move_child(d, idx)
	d.global_position = pos
	if spawn_saved != null:
		_spawn[d] = spawn_saved
	for n in extra:
		d.add_child(n)
	register(d)
	doll_replaced.emit(old, d)
	return d


# --- фазы ---

## Старт матча: отсчёт countdown_s → FIGHT!. Сломанные куклы пересоздаются.
func begin() -> void:
	_started = true
	Engine.time_scale = 1.0
	_time_effects.clear()
	fight_time = 0.0
	sd_step = -1
	ko_records.clear()
	for d in dolls():
		if (d as Doll).is_broken():
			respawn_doll(d)
	for d in dolls():
		var dd := d as Doll
		dd.control_enabled = false
		var c := combat_of(dd)
		if c != null:
			c.reset()
	_set_phase(Phase.COUNTDOWN)
	_countdown_left = countdown_s
	_countdown_shown = -1
	for d in dolls():
		hp_changed.emit(d, (d as Doll).hp, Tuning.MAX_HP)
	time_left.emit(time_limit_s)
	if countdown_s <= 0.0:
		_start_fight()


## Заново: все куклы инстанцируются на точках спавна, потом begin().
func restart() -> void:
	_set_phase(Phase.OVER)
	Engine.time_scale = 1.0
	_time_effects.clear()
	for d in dolls():
		respawn_doll(d)
	begin()


func _set_phase(p: int) -> void:
	if phase == p:
		return
	phase = p
	phase_changed.emit(p)


func _start_fight() -> void:
	for d in dolls():
		var dd := d as Doll
		dd.reset_for_match()
		dd.control_enabled = true
		var c := combat_of(dd)
		if c != null:
			c.reset()
	fight_time = 0.0
	_set_phase(Phase.FIGHT)
	for d in dolls():
		hp_changed.emit(d, (d as Doll).hp, Tuning.MAX_HP)
	announce.emit("FIGHT!", ANNOUNCE_COLORS["fight"], "fight")


func _enter_sudden_death() -> void:
	_set_phase(Phase.SUDDEN_DEATH)
	announce.emit("SUDDEN DEATH", ANNOUNCE_COLORS["sudden_death"], "sudden_death")
	_apply_sd_step(0)


func _apply_sd_step(n: int) -> void:
	if n == sd_step:
		return
	sd_step = n
	var stab := Damage.sd_stability_mult(n)
	for d in dolls():
		if (d as Doll).alive:
			(d as Doll).set_stability(stab)
	sudden_death_step.emit(n)


## Бой идёт (урон принимается): FIGHT или SUDDEN_DEATH.
func combat_active() -> bool:
	return phase == Phase.FIGHT or phase == Phase.SUDDEN_DEATH


func knockback_mult() -> float:
	return Damage.sd_knockback_mult(sd_step) if phase == Phase.SUDDEN_DEATH else 1.0


func stability_mult() -> float:
	return Damage.sd_stability_mult(sd_step) if phase == Phase.SUDDEN_DEATH else 1.0


func time_left_s() -> float:
	match phase:
		Phase.COUNTDOWN:
			return time_limit_s
		Phase.FIGHT:
			return maxf(time_limit_s - fight_time, 0.0)
		Phase.SUDDEN_DEATH:
			return maxf(hard_timeout_s - fight_time, 0.0)
	return 0.0


func _physics_process(delta: float) -> void:
	_scan_t += delta
	if _scan_t >= SCAN_INTERVAL_S:
		_scan_t = 0.0
		_scan_dolls()
	if not _started:
		return
	match phase:
		Phase.COUNTDOWN:
			var n := int(ceil(_countdown_left))
			if n != _countdown_shown and n > 0:
				_countdown_shown = n
				announce.emit(str(n), ANNOUNCE_COLORS["countdown"], "countdown")
			_countdown_left -= delta
			if _countdown_left <= 0.0:
				_start_fight()
		Phase.FIGHT:
			fight_time += delta
			time_left.emit(time_left_s())
			if fight_time >= time_limit_s:
				_enter_sudden_death()
		Phase.SUDDEN_DEATH:
			fight_time += delta
			time_left.emit(time_left_s())
			var n := int(floor((fight_time - time_limit_s) / maxf(Tuning.SUDDEN_DEATH_STEP_S, 0.1)))
			if n != sd_step:
				_apply_sd_step(n)
			if fight_time >= hard_timeout_s:
				_finish("timeout")


func _process(delta: float) -> void:
	if _time_effects.is_empty():
		return
	var real := delta / maxf(Engine.time_scale, 1e-4)
	var scale := 1.0
	var i := 0
	while i < _time_effects.size():
		var e: Dictionary = _time_effects[i]
		e["left"] = float(e["left"]) - real
		if float(e["left"]) <= 0.0:
			_time_effects.remove_at(i)
		else:
			scale = minf(scale, float(e["scale"]))
			i += 1
	Engine.time_scale = scale


# --- удары и KO (зовёт DollCombat) ---

func on_hit(victim: Doll, attacker: Node, damage: float, kind: String, position: Vector3, combo_n: int, double_blow: bool, _weapon_id: String, _speed: float) -> void:
	hit.emit(victim, attacker, damage, kind, position)
	if damage >= Tuning.ANNOUNCE_MIN_DAMAGE and kind != "environment":
		var part: String = String(victim.last_hit.get("part", ""))
		if double_blow:
			announce.emit("DOUBLE BLOW!", ANNOUNCE_COLORS["double"], "double")
		elif part.begins_with("Head"):
			announce.emit("HEAD BLOW!", ANNOUNCE_COLORS["head"], "head")
		else:
			announce.emit("BODY BLOW!", ANNOUNCE_COLORS["body"], "body")
		if combo_n >= 2:
			announce.emit("%d HIT COMBO!" % combo_n, COMBO_COLORS[clampi(combo_n - 2, 0, COMBO_COLORS.size() - 1)], "combo")
	hit_feel(damage, position)


func on_combo(doll: Doll, n: int) -> void:
	combo_changed.emit(doll, n)


func _on_doll_damaged(_amount: float, _attacker: Node, _part: String, _position: Vector3, _kind: String, doll: Doll) -> void:
	hp_changed.emit(doll, doll.hp, Tuning.MAX_HP)


func _on_doll_ko(attacker: Node, record: Dictionary, victim: Doll) -> void:
	if phase == Phase.OVER:
		return
	var rec := record.duplicate()
	rec["victim"] = victim
	rec["attacker"] = attacker
	rec["match_time"] = fight_time
	rec["sd_step"] = sd_step
	# тик физики: KO в одном тике (голова о голову бьёт обоих) делят место, живых не осталось — ничья (build_results).
	# fight_time для этого не годится — Match может стоять в дереве между куклами и прибавить delta между их KO
	rec["physics_frame"] = Engine.get_physics_frames()
	ko_records.append(rec)
	if attacker is Doll and attacker != victim:
		var s: Dictionary = (attacker as Doll).stats
		s["kos"] = int(s["kos"]) + 1
	victim.stats["kos_taken"] = maxi(int(victim.stats["kos_taken"]), 1)
	hp_changed.emit(victim, 0.0, Tuning.MAX_HP)
	combo_changed.emit(victim, 0)
	announce.emit("KO!", ANNOUNCE_COLORS["ko"], "ko")
	ko.emit(victim, attacker, rec)
	if feel_enabled:
		var pos: Vector3 = rec.get("position", victim.centre_of_mass())
		_camera_fx(40.0, pos)
		_time_effect(Tuning.KO_SLOWMO_SCALE, Tuning.KO_SLOWMO_S)
	# конец матча — deferred: цепочка take_damage → knocked_out ещё не дописала статистику/комбо этого удара
	call_deferred("_check_over")


func _check_over() -> void:
	if combat_active() and alive_dolls().size() <= 1:
		_finish("ko")


# --- подача удара ---

func _camera() -> Node:
	var c: Node = get_node_or_null(camera_path) if camera_path != NodePath() else null
	if c == null:
		c = get_tree().get_first_node_in_group("camera")
	if c == null:
		c = get_viewport().get_camera_3d()
	return c


func _camera_fx(strength: float, _position: Vector3) -> void:
	var cam := _camera()
	if cam == null:
		return
	if cam.has_method("shake"):
		cam.call("shake", Tuning.HIT_SHAKE_PER_10HP * strength / 10.0)
	if strength >= Tuning.HIT_ZOOM_DAMAGE and cam.has_method("zoom_impulse"):
		cam.call("zoom_impulse", Tuning.HIT_ZOOM_FRAC, Tuning.HIT_ZOOM_S)


func _time_effect(scale: float, real_seconds: float) -> void:
	_time_effects.append({"scale": scale, "left": real_seconds})
	Engine.time_scale = minf(Engine.time_scale, scale)


## Тряска + zoom impulse камеры и hit stop по силе удара (HP).
func hit_feel(strength: float, position: Vector3) -> void:
	if not feel_enabled:
		return
	_camera_fx(strength, position)
	if strength >= Tuning.HIT_STOP_DAMAGE_2:
		_time_effect(Tuning.HIT_STOP_TIME_SCALE, Tuning.HIT_STOP_S_2)
	elif strength >= Tuning.HIT_STOP_DAMAGE_1:
		_time_effect(Tuning.HIT_STOP_TIME_SCALE, Tuning.HIT_STOP_S_1)


# --- итоги ---

## Ключ tie-break (больше — лучше): HP, нанесённый урон, −полученный, сильнейший удар.
static func rank_key(d: Doll) -> Array:
	return [d.hp, float(d.stats["damage_dealt"]), -float(d.stats["damage_taken"]), float(d.stats["hardest_hit"])]


static func _key_gt(a: Array, b: Array) -> bool:
	for i in range(a.size()):
		if not is_equal_approx(float(a[i]), float(b[i])):
			return float(a[i]) > float(b[i])
	return false


static func _key_eq(a: Array, b: Array) -> bool:
	for i in range(a.size()):
		if not is_equal_approx(float(a[i]), float(b[i])):
			return false
	return true


func _finish(reason: String) -> void:
	if phase == Phase.OVER:
		return
	var results := build_results(reason)
	var winner: Doll = results["winner"]
	_set_phase(Phase.OVER)
	match_over.emit(winner, results)


## Выбывшие группами по тику физики KO — от последнего тика к первому (Array[Array[Doll]]), внутри группы по player_index.
func _ko_groups() -> Array:
	var groups: Array = []
	var frame := 0
	for i in range(ko_records.size() - 1, -1, -1):
		var r: Dictionary = ko_records[i]
		var v: Variant = r.get("victim")
		if not is_instance_valid(v):
			continue
		var f := int(r.get("physics_frame", -1 - i))
		if groups.is_empty() or f != frame:
			groups.append([])
			frame = f
		(groups[-1] as Array).append(v)
	for g in groups:
		(g as Array).sort_custom(func(a: Doll, b: Doll) -> bool: return a.player_index < b.player_index)
	return groups


## Места, статистика, медали, combo_score. reason: "ko" | "timeout".
## Победитель — только живая кукла. ranks[i] — место places[i] (0 = первое): живые с равным ключом и выбывшие в одном тике
## делят место (1, 1, 3). Живых нет (все оставшиеся выбыли в одном тике — клинч голова-о-голову бьёт обоих) — ничья:
## winner null, draw, медали Winner нет, у HUD нет короны (06-combat-hud.md «Одновременный KO»).
func build_results(reason: String = "timeout") -> Dictionary:
	var alive := alive_dolls()
	alive.sort_custom(func(a: Doll, b: Doll) -> bool:
		var ka := rank_key(a)
		var kb := rank_key(b)
		if _key_eq(ka, kb):
			return a.player_index < b.player_index
		return _key_gt(ka, kb))
	var places: Array = []
	var ranks: Array = []
	for i in range(alive.size()):
		var tied := i > 0 and _key_eq(rank_key(alive[i]), rank_key(alive[i - 1]))
		ranks.append(ranks[i - 1] if tied else i)
		places.append(alive[i])
	for g in _ko_groups():
		var rank := places.size()
		for v in g:
			if not places.has(v):
				places.append(v)
				ranks.append(rank)
	for d in dolls():
		if not places.has(d):
			ranks.append(places.size())
			places.append(d)
	var draw := false
	var winner: Doll = null
	if not alive.is_empty():
		winner = alive[0]
		if alive.size() >= 2 and int(ranks[1]) == 0:
			draw = true   # hard timeout: равный ключ HP → урон → полученный → сильнейший удар
			winner = null
	elif not places.is_empty():
		draw = true   # живых нет: одновременный KO
	var stats: Dictionary = {}
	var combo_score: Dictionary = {}
	for d in places:
		stats[d] = (d as Doll).stats.duplicate()
		combo_score[d] = float((d as Doll).stats["combo_score"])
	var medals: Dictionary = {}
	if winner != null:
		medals["Winner"] = winner
	_medal_max(medals, "Hardest Hit", places, "hardest_hit", 0.0)
	_medal_max(medals, "Frequent Flyer", places, "air_time", 0.0)
	_medal_max(medals, "Wall Inspector", places, "wall_collisions", 0.0)
	_medal_max(medals, "Weapon Master", places, "weapon_hits", 0.0)
	var self_ko: Doll = null
	for r in ko_records:
		var k: String = String(r.get("kind", ""))
		if (k == "self" or k == "environment") and is_instance_valid(r.get("victim")):
			self_ko = r["victim"]
			break
	if self_ko != null:
		medals["Self Destruction"] = self_ko
	else:
		_medal_max(medals, "Self Destruction", places, "self_damage", 20.0 - 1e-6)
	_medal_max(medals, "Acrobat", places, "rotations", 0.0)
	var survivor: Doll = null
	var best_low := 10.0 - 1e-6
	for d in alive:
		var v := float((d as Doll).stats["low_hp_survived_s"])
		if v > best_low:
			best_low = v
			survivor = d
	if survivor != null:
		medals["Survivor"] = survivor
	return {
		"places": places, "ranks": ranks, "stats": stats, "medals": medals, "winner": winner, "draw": draw, "reason": reason,
		"duration_s": fight_time, "ko_records": ko_records.duplicate(), "combo_score": combo_score,
	}


## Медаль игроку с максимальным stats[key] > min_value (равенство — меньший player_index).
static func _medal_max(medals: Dictionary, medal: String, places: Array, key: String, min_value: float) -> void:
	var best: Doll = null
	var best_v := min_value
	for d in places:
		var v := float((d as Doll).stats.get(key, 0.0))
		if v > best_v or (best != null and is_equal_approx(v, best_v) and (d as Doll).player_index < best.player_index):
			best_v = v
			best = d
	if best != null:
		medals[medal] = best
