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
## Стабильный API для подклассов (scripts/pve/wave_director.gd, WaveDirector extends Match — 29.09): члены _late_ready, _physics_process,
## _on_doll_ko, _on_doll_damaged, _check_over, _set_phase, _camera_fx, _time_effect, _ko_order, _scan_t, _started не переименовывать и
## не менять сигнатуры без согласования с сессией PvE (или сначала дать виртуальный хук «конец матча / выбор победителя»).
## hit_feel(strength, position): тряска и zoom impulse DynamicCamera (camera_path | группа "camera" | текущая камера) и hit stop
## через Engine.time_scale (80 мс от 20 HP, 120 мс от 35 HP), KO — slow-mo 0.25× на 1.2 с; таймеры в реальном времени.
## Сок удара (HIT_FX.md §13, 02.10): ребёнок HitJuice (сколы на деталях, цифры-обломки, поводы N0), _juice_time — замедление
## варианта HitJuice.time_variant (клавиша 0), плавный выход (request_time_scale ramp_s); ctx.mat — материал ударенной детали.
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
## Эффекты удара (docs/plan-demo/HIT_FX.md §4.1): каждый удар с уроном > 0 (kind != environment) после hit_feel — ctx с уровнем
## (HitTier); удар о статику ≥ HITFX_SLAM_SPEED без урона (DollCombat._notify_env_slam → on_env_slam).
signal hit_fx(ctx: Dictionary)
signal env_slam(ctx: Dictionary)

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
var _ko_order: Array = []       # жертвы по порядку KO (API подклассов и камеры; места — по ko_records, _ko_groups)
var _scan_t := 0.0
var _started := false
var _time_effects: Array = []   # [{"scale": float, "left": float, "ramp"?: float}] — hit stop / slow-mo в реальных секундах
var _real_clock := 0.0          # реальные с жизни Match (FxClock): зазор микростопов сока удара
var _light_stop_at := -INF

# --- эффекты удара и крит (HIT_FX.md §4.1; вся логика — в конце файла) ---
const HIT_FX_DIRECTOR_SCENE := "res://scenes/fx/hit_fx_director.tscn"
const SFX_DIRECTOR_SCENE := "res://scenes/audio/sfx_director.tscn"
## false — уровни не выше heavy/ko и без крит-отлёта (тесты, гейты с чужими числами).
var crit_enabled: bool = Tuning.CRIT_ENABLED
## Правило уровней и кулдауны крита; reset() — на COUNTDOWN (_on_phase_hitfx).
var hit_tiers := HitTier.new()
## Счётчики для проб: hit_fx / env_slam за жизнь Match.
var hit_fx_count := 0
var env_slam_count := 0
var _camera_owner := ""
var _captured_from: Camera3D = null


func _ready() -> void:
	ImpactFx.prewarm(self)  # шейдеры вспышек/частиц до первого удара
	FxClock.ensure(self)    # масштаб времени, с которым посчитан delta кадра (hit stop из физики, HIT_FX.md §2.2)
	add_to_group(GROUP)
	_ensure_fx_directors()
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
	BoostFx.attach(d)   # эффекты ускорения / раскрутки (COMBAT_CHARGE.md), пресет — F11
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
	d.muscle_zeta = old.muscle_zeta
	d.team = old.team
	d.team_damage_mult = old.team_damage_mult
	d.max_hp = old.max_hp
	# ModularDoll (BODY_CRAFT.md): чертёж из мастерской переживает KO / R — ставится до add_child, сборка идёт в _ready.
	# Только чертёж в памяти (CraftEdit.dup_body → BodyBlueprint.new(), resource_path ""): пресет .tres приходит со сценой, а
	# playground_body.set_preset меняет scene_file_path и зовёт respawn — копия старого чертежа затёрла бы новый пресет.
	var bp: Variant = old.get("blueprint")
	if bp is Resource and (bp as Resource).resource_path == "":
		d.set("blueprint", bp)
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
	_ko_order.clear()
	ko_records.clear()
	for d in dolls():
		if (d as Doll).is_broken():
			respawn_doll(d)
	for d in dolls():
		_drive_hp(d as Doll)
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
		hp_changed.emit(d, (d as Doll).hp, (d as Doll).max_hp)
	time_left.emit(time_limit_s)
	if countdown_s <= 0.0:
		_start_fight()


## ДРАЙВ (Drive): удары сильнее и чаще (бой ботов 24 → 15 с), поэтому запас HP обычной куклы Tuning.DRIVE_MAX_HP — длина боя прежняя.
## Особый запас (враги PvE 25 / 50) не трогается; выключили ДРАЙВ — со следующего begin() снова Tuning.MAX_HP.
func _drive_hp(d: Doll) -> void:
	var want := Tuning.DRIVE_MAX_HP if Drive.on else Tuning.MAX_HP
	if is_equal_approx(d.max_hp, want) or not (is_equal_approx(d.max_hp, Tuning.MAX_HP) or is_equal_approx(d.max_hp, Tuning.DRIVE_MAX_HP)):
		return
	d.max_hp = want
	d.hp = want


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
		hp_changed.emit(d, (d as Doll).hp, (d as Doll).max_hp)
	announce.emit(tr("FIGHT!"), ANNOUNCE_COLORS["fight"], "fight")


func _enter_sudden_death() -> void:
	_set_phase(Phase.SUDDEN_DEATH)
	announce.emit(tr("SUDDEN DEATH"), ANNOUNCE_COLORS["sudden_death"], "sudden_death")
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
	var real := FxClock.real_delta(delta)  # не delta / Engine.time_scale: стоп, поставленный в физике этого кадра, истекал сразу
	_real_clock += real
	if _time_effects.is_empty():
		return
	var scale := 1.0
	var i := 0
	while i < _time_effects.size():
		var e: Dictionary = _time_effects[i]
		e["left"] = float(e["left"]) - real
		if float(e["left"]) <= 0.0:
			_time_effects.remove_at(i)
		else:
			scale = minf(scale, _effect_scale(e))
			i += 1
	Engine.time_scale = scale


## Масштаб записи времени: последние ramp реальных с (если есть) — линейно от scale к 1, без ступеньки на выходе.
static func _effect_scale(e: Dictionary) -> float:
	var s := float(e["scale"])
	var ramp := float(e.get("ramp", 0.0))
	var left := float(e["left"])
	if ramp > 0.0 and left < ramp:
		return lerpf(1.0, s, left / ramp)
	return s


# --- удары и KO (зовёт DollCombat) ---

func on_hit(victim: Doll, attacker: Node, damage: float, kind: String, position: Vector3, combo_n: int, double_blow: bool, _weapon_id: String, _speed: float) -> void:
	hit.emit(victim, attacker, damage, kind, position)
	if damage >= Tuning.ANNOUNCE_MIN_DAMAGE and kind != "environment":
		var part: String = String(victim.last_hit.get("part", ""))
		if double_blow:
			announce.emit(tr("DOUBLE BLOW!"), ANNOUNCE_COLORS["double"], "double")
		elif part.begins_with("Head"):
			announce.emit(tr("HEAD BLOW!"), ANNOUNCE_COLORS["head"], "head")
		else:
			announce.emit(tr("BODY BLOW!"), ANNOUNCE_COLORS["body"], "body")
		if combo_n >= 2:
			announce.emit(tr("%d HIT COMBO!") % combo_n, COMBO_COLORS[clampi(combo_n - 2, 0, COMBO_COLORS.size() - 1)], "combo")
	hit_feel(damage, position)
	_emit_hit_fx(victim, attacker, damage, kind, position, combo_n, double_blow, _weapon_id, _speed)


func on_combo(doll: Doll, n: int) -> void:
	combo_changed.emit(doll, n)


func _on_doll_damaged(_amount: float, _attacker: Node, _part: String, _position: Vector3, _kind: String, doll: Doll) -> void:
	hp_changed.emit(doll, doll.hp, doll.max_hp)


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
	_ko_order.append(victim)
	if attacker is Doll and attacker != victim:
		var s: Dictionary = (attacker as Doll).stats
		s["kos"] = int(s["kos"]) + 1
	victim.stats["kos_taken"] = maxi(int(victim.stats["kos_taken"]), 1)
	hp_changed.emit(victim, 0.0, victim.max_hp)
	combo_changed.emit(victim, 0)
	announce.emit(tr("KO!"), ANNOUNCE_COLORS["ko"], "ko")
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
	var k := FxPreset.shake()   # пресет FX (HIT_FX.md §11.2): full 1, reduced 0.5, off 0
	if cam.has_method("shake") and k > 0.0:
		cam.call("shake", Tuning.HIT_SHAKE_PER_10HP * strength / 10.0 * k * Drive.shake_mult())
	if strength >= Tuning.HIT_ZOOM_DAMAGE and cam.has_method("zoom_impulse") and k > 0.0:
		cam.call("zoom_impulse", Tuning.HIT_ZOOM_FRAC * k, Tuning.HIT_ZOOM_S)


func _time_effect(scale: float, real_seconds: float) -> void:
	_time_effects.append({"scale": scale, "left": real_seconds})
	Engine.time_scale = minf(Engine.time_scale, scale)


## Тряска + zoom impulse камеры и hit stop по силе удара (HP).
func hit_feel(strength: float, position: Vector3) -> void:
	if not feel_enabled:
		return
	_camera_fx(strength, position)
	if not FxPreset.time_fx():
		return   # пресет FX off: без hit stop
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


# --- эффекты удара и крит (docs/plan-demo/HIT_FX.md §4.1): ctx удара, уровень, крит-отлёт, время и камера для эффектов ---

## Директоры эффектов и звука детьми Match (если их нет, есть сцена и Tuning.HITFX_ENABLED) — эффекты работают на всех площадках
## с Match без правки их сцен. Сброс кулдаунов крита — свой обработчик phase_changed.
func _ensure_fx_directors() -> void:
	if not phase_changed.is_connected(_on_phase_hitfx):
		phase_changed.connect(_on_phase_hitfx)
	if Tuning.JUICE_ENABLED and get_node_or_null("HitJuice") == null:
		var j := HitJuice.new()   # сколы на деталях, цифры-обломки, поводы N0 (HIT_FX.md §13) — до директоров: его hit_fx идёт первым
		j.name = "HitJuice"
		add_child(j)
	if not Tuning.HITFX_ENABLED:
		return
	for e in [[HIT_FX_DIRECTOR_SCENE, "HitFxDirector"], [SFX_DIRECTOR_SCENE, "SfxDirector"]]:
		if get_node_or_null(String(e[1])) != null or not ResourceLoader.exists(String(e[0])):
			continue
		var ps := load(String(e[0])) as PackedScene
		if ps == null:
			continue
		var n := ps.instantiate()
		n.name = String(e[1])
		add_child(n)
		if n.is_in_group(FxPreset.DIRECTOR_GROUP):
			FxPreset.apply(n)   # пресет FX игрока (F10, HIT_FX.md §11.2)
	# мир звука (docs/plan-demo/AUDIO.md §4): толпа, стук столкновений, фон арены и музыка боя
	if Tuning.AUDIO_WORLD_ENABLED:
		for e in [["CrowdDirector", CrowdDirector], ["ImpactAudio", ImpactAudio], ["ArenaAmbience", ArenaAmbience]]:
			if get_node_or_null(String(e[0])) == null:
				var a: Node = (e[1] as GDScript).new()
				a.name = String(e[0])
				add_child(a)


## COUNTDOWN (begin / restart): кулдауны крита заново; захваченная камера возвращается. OVER без KO (таймаут) — тоже;
## OVER после KO камеру не трогает — крупный план ko_crit ещё идёт, его закончит сам кинематограф.
func _on_phase_hitfx(p: int) -> void:
	if p == Phase.COUNTDOWN:
		hit_tiers.reset()
	if _camera_owner != "" and (p == Phase.COUNTDOWN or (p == Phase.OVER and _ko_order.is_empty())):
		release_camera(_camera_owner)


## ctx удара → уровень (HitTier) → крит-отлёт (CritLaunch) → hit stop heavy → сигнал hit_fx. Зовёт on_hit последней строкой.
func _emit_hit_fx(victim: Doll, attacker: Node, damage: float, kind: String, position: Vector3, combo_n: int, double_blow: bool, weapon_id: String, speed: float) -> void:
	if victim == null or not is_instance_valid(victim) or damage <= 0.0 or kind == "environment":
		return
	var ctx := make_hit_ctx(victim, attacker, damage, kind, position, combo_n, double_blow, weapon_id, speed)
	var tier := hit_tiers.classify(ctx, fight_time, crit_enabled)
	ctx["tier"] = tier
	ctx["launch_dv"] = Vector3.ZERO
	if tier == HitTier.CRIT or tier == HitTier.KO_CRIT:
		ctx["launch_dv"] = CritLaunch.apply(ctx, knockback_mult())
	if tier == HitTier.HEAVY: ctx["brake_cut"] = CritLaunch.brake_attacker(ctx, Tuning.HEAVY_ATTACKER_BRAKE_SPEED, Tuning.HEAVY_ATTACKER_BRAKE_S)   # HIT_FX §12.2
	if tier == HitTier.HEAVY and damage < Tuning.HIT_STOP_DAMAGE_1:
		request_time_scale(Tuning.HIT_STOP_TIME_SCALE, Tuning.HITFX_HEAVY_STOP_S, "heavy_stop")
	_juice_time(tier, damage)
	Drive.camera_kick(_camera(), ctx, FxPreset.shake())   # ДРАЙВ: толчок кадра в сторону удара на каждом light (Drive)
	hit_fx_count += 1
	var charge_got := Charge.apply_hit(ctx)   # Заряд (COMBAT_CHARGE.md): атакующему за удар, жертве — доля урона
	ctx["charge_attacker"] = float(charge_got[0])
	ctx["charge_victim"] = float(charge_got[1])
	hit_fx.emit(ctx)


## Замедление сока удара (HIT_FX.md §13): вариант HitJuice.variant() (клавиша 0: А микростоп / Б кино на сильных / В как в вебе / выкл).
## light с light_dmg — стоп «light_stop» (если есть) и замедление «light_slow» (не чаще light_gap реального времени); heavy — свой стоп
## «heavy_stop2» (вариант В) и замедление «heavy_slow» сразу за стоп-кадром (heavy_stop 83 мс или hit stop 80 / 120 мс). Выход плавный
## (ramp). Пресет FX off и feel_enabled = false их не пускают (request_time_scale).
func _juice_time(tier: String, damage: float) -> void:
	if not Tuning.JUICE_ENABLED:
		return
	var v := HitJuice.variant()
	if tier == HitTier.LIGHT:
		if damage < float(v["light_dmg"]) or float(v["light_s"]) <= 0.0 or _real_clock - _light_stop_at < float(v["light_gap"]):
			return
		var stop := float(v["light_stop"])
		if stop > 0.0 and not request_time_scale(Tuning.HIT_STOP_TIME_SCALE, stop, "light_stop"):
			return
		if request_time_scale(float(v["light_scale"]), stop + float(v["light_s"]), "light_slow", float(v["light_ramp"])):
			_light_stop_at = _real_clock
	elif tier == HitTier.HEAVY and float(v["heavy_s"]) > 0.0:
		var stop := Tuning.HITFX_HEAVY_STOP_S
		if damage >= Tuning.HIT_STOP_DAMAGE_2:
			stop = Tuning.HIT_STOP_S_2
		elif damage >= Tuning.HIT_STOP_DAMAGE_1:
			stop = Tuning.HIT_STOP_S_1
		if float(v["heavy_stop"]) > 0.0:
			request_time_scale(Tuning.HIT_STOP_TIME_SCALE, float(v["heavy_stop"]), "heavy_stop2")
		request_time_scale(float(v["heavy_scale"]), stop + float(v["heavy_s"]), "heavy_slow", float(v["heavy_ramp"]))


## Поля ctx (HIT_FX.md §4.1): victim, attacker, damage, kind, part, part_base, striker, position, normal, dir, speed, weapon_id, combo,
## double_blow, dash, score, tier, is_ko, hp_after, fight_time, sd_mult, colour (score/tier дописывает classify / _emit_hit_fx).
func make_hit_ctx(victim: Doll, attacker: Node, damage: float, kind: String, position: Vector3, combo_n: int, double_blow: bool, weapon_id: String, speed: float) -> Dictionary:
	var lh: Dictionary = victim.last_hit
	var part := String(lh.get("part", ""))
	var normal: Vector3 = lh.get("normal", Vector3.ZERO)
	var dir: Vector3 = lh.get("dir", Vector3.ZERO)
	dir.z = 0.0
	if dir.length_squared() < 1e-6:
		dir = Vector3(-normal.x, -normal.y, 0.0)
	dir = dir.normalized() if dir.length_squared() > 1e-6 else Vector3.RIGHT
	var striker := weapon_id if weapon_id != "" else String(lh.get("striker_name", ""))
	var dash := false
	if attacker != null and is_instance_valid(attacker) and attacker.has_method("is_dashing"):
		dash = bool(attacker.call("is_dashing"))
	var pi := victim.player_index
	var colour: Color = Tuning.PLAYER_COLORS[pi % Tuning.PLAYER_COLORS.size()] if pi >= 0 else Color.WHITE
	return {
		"victim": victim, "attacker": attacker if attacker != null and is_instance_valid(attacker) else null, "damage": damage, "kind": kind,
		"part": part, "part_base": Doll.part_base_name(part), "striker": striker, "position": position, "normal": normal, "dir": dir,
		"speed": speed, "weapon_id": weapon_id, "combo": combo_n, "double_blow": double_blow, "dash": dash, "score": 0.0, "tier": "",
		"is_ko": not victim.alive, "hp_after": victim.hp, "fight_time": fight_time, "sd_mult": knockback_mult(), "colour": colour,
		"mat": FxMaterial.id_of(victim, victim.parts.get(part) as Node),   # материал ударенной детали (HIT_FX.md §13)
	}


## Удар о статику ≥ HITFX_SLAM_SPEED (DollCombat, без урона) → сигнал env_slam(ctx) в конце кадра физики (не в коллбэке контакта).
func on_env_slam(doll: Doll, part: String, speed: float, position: Vector3, normal: Vector3) -> void:
	if doll == null or not is_instance_valid(doll):
		return
	var ctx := {
		"doll": doll, "part": part, "speed": speed, "position": position, "normal": normal, "flying": doll.is_flying(),
		"crit_flight": bool(doll.call("flight_cap_active")) if doll.has_method("flight_cap_active") else false, "fight_time": fight_time,
	}
	env_slam_count += 1
	call_deferred("_emit_env_slam", ctx)


func _emit_env_slam(ctx: Dictionary) -> void:
	env_slam.emit(ctx)


## Замедление/стоп-кадр для эффектов поверх _time_effects (hit stop и KO slow-mo не меняются: действует минимум). scale ≥
## HITFX_TIME_SCALE_MIN, real_s — реальные секунды; тот же tag заменяет прежнюю запись. false и ничего — при feel_enabled = false.
## ramp_s > 0 — последние ramp_s секунд масштаб линейно идёт к 1 (плавный выход замедления, HIT_FX.md §13).
func request_time_scale(scale: float, real_s: float, tag: String = "", ramp_s: float = 0.0) -> bool:
	if not feel_enabled or real_s <= 0.0:
		return false
	if not FxPreset.time_tag_allowed(tag):
		return false   # пресет FX off (HIT_FX.md §11.2): без стоп-кадров и замедлений, кроме KO
	if tag != "":
		_drop_time_tag(tag)
	var s := clampf(scale, Tuning.HITFX_TIME_SCALE_MIN, 1.0)
	# −1 мкс: сумма кадров 3 × 1/60 не добирает до 0.05 на ошибку округления, и стоп держался бы лишний кадр
	_time_effects.append({"scale": s, "left": real_s - 1e-6, "tag": tag, "ramp": clampf(ramp_s, 0.0, real_s)})
	Engine.time_scale = minf(Engine.time_scale, s)
	return true


## Снять записи с тегом: Engine.time_scale = min(оставшиеся, 1).
func cancel_time_scale(tag: String) -> void:
	if tag == "":
		return
	_drop_time_tag(tag)
	var scale := 1.0
	for e in _time_effects:
		scale = minf(scale, _effect_scale(e))
	Engine.time_scale = scale


func time_scale_tags() -> Array:
	var out: Array = []
	for e in _time_effects:
		var tg := String((e as Dictionary).get("tag", ""))
		if tg != "" and not out.has(tg):
			out.append(tg)
	return out


func _drop_time_tag(tag: String) -> void:
	var i := 0
	while i < _time_effects.size():
		if String((_time_effects[i] as Dictionary).get("tag", "")) == tag:
			_time_effects.remove_at(i)
		else:
			i += 1


## Игровая камера площадки (DynamicCamera: camera_path | группа "camera"); пока камера захвачена — та, что была до захвата.
func game_camera() -> Camera3D:
	var c: Node = get_node_or_null(camera_path) if camera_path != NodePath() else null
	if c == null:
		c = get_tree().get_first_node_in_group("camera")
	if c == null and _captured_from != null and is_instance_valid(_captured_from):
		c = _captured_from
	if c == null:
		c = get_viewport().get_camera_3d()
	return c as Camera3D


## Захват камеры эффектом (крупный план крита): cam.make_current(), владелец tag. Повторный захват тем же владельцем — смена камеры.
func capture_camera(cam: Camera3D, tag: String) -> void:
	if cam == null or not is_instance_valid(cam) or tag == "":
		return
	if _camera_owner != "" and _camera_owner != tag:
		return
	if _camera_owner == "":
		_captured_from = game_camera()
	_camera_owner = tag
	cam.make_current()


## Вернуть игровую камеру, если владелец — tag.
func release_camera(tag: String) -> void:
	if tag == "" or _camera_owner != tag:
		return
	_camera_owner = ""
	var g := game_camera()
	_captured_from = null
	if g != null and is_instance_valid(g) and g.is_inside_tree():
		g.make_current()


func camera_owner() -> String:
	return _camera_owner
