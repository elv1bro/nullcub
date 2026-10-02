## Режим волн PvE (CONCEPT_V2 §3, §29, проба 2: «2 типа PvE-врагов на основе бота-наскока, волна 3–5 против одного игрока»; лор —
## LORE_NULL.md: враги — сервисные роботы арены со сбитой программой, выпадают из мусорного желоба вместе с хламом, системы поля
## говорят капсом).
## Наследник Match (scripts/core/match.gd): от него — всё ядро боя без копий: регистрация кукол (DollCombat), удар → hit / hit_fx /
## env_slam (HitFxDirector, SfxDirector, крит, hit stop, тряска камеры), надписи announce, request_time_scale. Своё — фазы и конец:
##   • PvP-логика Match выключена переопределениями: нет отсчёта до FIGHT! и таймера, нет Sudden Death, нет «последний живой
##     победил» (_check_over), reset_for_match не зовётся (он вернул бы врагам HP 100);
##   • забег: intro (COUNTDOWN intro_s — урона нет) → волна i: желоб арены (ScrapArena.chute()) переходит в WARNING, через
##     chute_warn_s из раструба по одному (spawn_interval_s) выпадают враги со скоростью вдоль spit_dir, мозг молчит spawn_drop_s
##     (кувырок из трубы) → бой → волна зачищена (все враги волны KO — ударами или в пропасти) → пауза wave_pause_s → следующая;
##     после WAVES.size() волн — победа, все игроки KO — поражение; restart() — заново (R на площадке);
##   • строка систем поля капсом (сигнал field_line) на старте забега и каждой волны, на зачистке, победе и поражении, когда Разборщик
##     открутил деталь игрока (PART CONFISCATED…) и когда враг сам улетел в провал (CREW MEMBER DISPOSED…); «правило гашения»
##     (LORE.md): после FIELD CLEAR сверху прилетает запоздавшая бочка;
##   • команды (хук Doll.team): игрокам player_team ("players": друг по другу × Tuning.TEAM_DAMAGE_MULT, толчки полные — CONCEPT_V2 §22
##     «дружеский хаос»), врагам enemy_team ("arena", team_damage_mult 0 — свои не ранят); запас HP — Doll.max_hp (враги 25 / 50 — в своих сценах). Match.respawn_doll
##     переносит team и max_hp;
##   • KO врага: как у Match, но замедление и тряска слабее (enemy_ko_slowmo_s); тело лежит corpse_s и убирается (6 кукол по 14 тел);
##     метла Уборщика остаётся — её можно подобрать;
##   • мёртвые игроки в коопе встают на своих спавнах в начале следующей волны (пока нет «Ядра товарища» из CONCEPT_V2);
##   • игрок вернул себе отобранную деталь (Doll.reattach_part — касание / захват, scripts/body/arm_assist.gd) — строка систем поля;
##   • страховка: враг вне границ арены (ниже дна, за стенами) — KO, считается как пропасть.
## Сигналы для HUD (scenes/pve/pve_hud.gd): wave_started, wave_cleared, enemies_changed, field_line, run_over, enemy_spawned,
## enemy_down + унаследованные announce, hp_changed, ko, hit. Пробы: auto_waves = false и begin_manual() — враги только через
## spawn_enemy(); events — журнал забега.
class_name WaveDirector
extends Match

signal wave_started(index: int, total: int, line: String)
signal wave_cleared(index: int, total: int)
signal enemies_changed(left: int, total: int)
signal field_line(text: String)
signal run_over(victory: bool, line: String)
signal enemy_spawned(enemy: Doll)
signal enemy_down(enemy: Doll, cause: String)

const ENEMY_SCENES := {
	"scrapling": "res://scenes/enemies/enemy_scrapling.tscn",
	"sweeper": "res://scenes/enemies/enemy_sweeper.tscn",
}
## Волны: кто выпадает из желоба (по порядку); строка систем поля — wave_line(i).
const WAVES := [
	{"enemies": ["scrapling", "scrapling"]},
	{"enemies": ["sweeper", "scrapling", "scrapling"]},
	{"enemies": ["sweeper", "scrapling", "scrapling", "sweeper", "scrapling"]},
]
const WAVE_COLOUR := Color(1.0, 0.72, 0.25)
const PART_LINE_GAP_S := 6.0
const LATE_BARREL := "res://scenes/props/scrap/prop_wooden_barrel.tscn"
const LATE_BARREL_S := 1.6
const BOUNDS_CHECK_S := 0.25

@export var auto_waves := true
@export var intro_s := 2.0
@export var wave_pause_s := 4.0
@export var spawn_interval_s := 0.75
@export var chute_warn_s := 1.0
@export var spawn_drop_s := 1.1
## Скорость вылета из раструба (м/с) вдоль spit_dir желоба.
@export var spawn_speed := 3.5
@export var corpse_s := 8.0
## Передышка между волнами: живым игрокам +heal_between_waves HP (не больше Tuning.MAX_HP). Без неё (и с прежним щипком Разборщика
## на полной тяге) бот-игрок доходил только до волны 2 — три волны на 100 HP без починки проверяли бы выносливость, а не «весело ли».
@export var heal_between_waves := 30.0
@export var enemy_ko_slowmo_s := 0.45
## Крит-кинематограф в PvE (эффекты v3: удар от CRIT_BYPASS_DAMAGE 25 HP — крит сквозь кулдауны, кино ≈ 1.3 с реального времени,
## атакующий стоит, жертва летит до 7.5 м/с) — только на ПОСЛЕДНЕМ враге волны (добивание как финал) и когда враг бьёт игрока
## последним оставшимся. Иначе: молот (20–30 HP) по Разборщику на 40 HP — крит почти каждым вторым ударом, волна из 5 врагов
## превращалась в череду замедленных роликов. Match.crit_enabled переключается каждый тик (_tick_crit_gate); false — никогда.
## 29.09 (автор: «нет крутых ударов»): крит разрешён и в середине волны, но не чаще раза в pve_crit_gap_s реального времени
## (кино ≈ 1.3 с — раз в 6 с оставляет бою ~80 %), а на последнем враге волны — всегда, как раньше.
@export var pve_crits := true
@export var pve_crit_gap_s := 6.0
var _last_crit_ms := -1000000
@export var enemies_path: NodePath
@export var weapons_path: NodePath
@export var players_group := "players"
@export var enemies_group := "enemies"
@export var player_team := "players"
@export var enemy_team := "arena"
## Урон и стан врага от своих (Doll.team_damage_mult): 0 — Уборщик, сметая Разборщика, толкает его, но не ранит.
@export var enemy_team_damage := 0.0

var wave_index := -1
## idle | intro | spawning | fight | pause | victory | defeat | manual
var wave_state := "idle"
var wave_t := 0.0
var run_t := 0.0
var result := ""
## Враги текущей волны (живые и KO) и сколько из них уже выбыло.
var wave_enemies: Array = []
var wave_total := 0
var wave_down := 0
var spawn_queue: Array = []             # [{t, kind}] от старта волны
var kills := {"ko": 0, "pit": 0}
## Журнал для проб: [{t, what, ...}].
var events: Array = []
var _scenes: Dictionary = {}
var _weapon_home: Dictionary = {}       # Weapon -> Transform3D
var _corpses: Array = []                # [Doll, run_t уборки тела]
var _bounds_t := 0.0
var _spawn_n := 0
var _barrel_at := -1.0
var _part_line_t := -100.0
var _pit_line_t := -100.0


func _ready() -> void:
	for k in ENEMY_SCENES:
		_scenes[k] = load(ENEMY_SCENES[k])   # заранее: сборка сцены посреди волны — рывок кадра
	super._ready()
	pve_crits = pve_crits and crit_enabled   # Tuning.CRIT_ENABLED = false выключает и здесь
	doll_replaced.connect(_on_doll_replaced)


## Match.respawn_doll (R, пропасть, возрождение между волнами) — новая кукла игрока получает подписки забега (team и max_hp
## переносит сам Match).
func _on_doll_replaced(_old: Doll, new_doll: Doll) -> void:
	if new_doll != null and is_instance_valid(new_doll) and new_doll.is_in_group(players_group):
		_setup_player(new_doll)


func _late_ready() -> void:
	if not hit_fx.is_connected(_on_pve_hit_fx):
		hit_fx.connect(_on_pve_hit_fx)
	_scan_dolls()
	_remember_weapons()
	for p in players():
		_setup_player(p, true)
	if auto_waves:
		start_run()


# --- куклы ---

## Игроки забега — каждый раз заново из группы (ссылок не храним: R, кооп F2 и респавн Match пересоздают кукол).
func players() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group(players_group):
		if n is Doll and is_instance_valid(n) and n.is_inside_tree() and not n.is_queued_for_deletion():
			out.append(n)
	return out


func players_alive() -> Array:
	var out: Array = []
	for p in players():
		if (p as Doll).alive:
			out.append(p)
	return out


func alive_enemies() -> Array:
	var out: Array = []
	for e in wave_enemies:
		if is_instance_valid(e) and (e as Doll).alive:
			out.append(e)
	return out


func enemies_left() -> int:
	return maxi(wave_total - wave_down, 0)


func is_enemy(d: Node) -> bool:
	return d != null and d.is_in_group(enemies_group)


## Игрок в забеге: команда (только куклам со сцены — респавн Match переносит её сам), группа, DollCombat, строки систем поля про детали.
func _setup_player(p: Doll, set_team := false) -> void:
	if set_team and player_team != "":
		p.team = player_team
	if not p.is_in_group(dolls_group):
		p.add_to_group(dolls_group)
	register(p)
	if not p.part_detached.is_connected(_on_player_part_detached):
		p.part_detached.connect(_on_player_part_detached.bind(p))
	if not p.part_reattached.is_connected(_on_player_part_reattached):
		p.part_reattached.connect(_on_player_part_reattached.bind(p))


func _on_player_part_reattached(part_name: String, p: Doll) -> void:
	_log("part_reattached", {"player": String(p.name), "part": part_name})
	if wave_state not in ["victory", "defeat"]:
		_say(tr("UNAUTHORIZED REPAIR DETECTED"))


## Разборщик открутил деталь игрока — системы поля комментируют (строка раз в PART_LINE_GAP_S, не спамит в куче).
func _on_player_part_detached(part_name: String, by: Node, p: Doll) -> void:
	_log("part_detached", {"player": String(p.name), "part": part_name, "by": String(by.name) if by != null else ""})
	if run_t - _part_line_t >= PART_LINE_GAP_S and wave_state not in ["victory", "defeat"]:
		_part_line_t = run_t
		_say(tr("PART CONFISCATED. TROPHY RULE APPLIED"))


func _enemies_parent() -> Node:
	var n: Node = get_node_or_null(enemies_path) if enemies_path != NodePath() else null
	return n if n != null else get_parent()


func _remember_weapons() -> void:
	_weapon_home.clear()
	var root: Node = get_node_or_null(weapons_path) if weapons_path != NodePath() else null
	if root == null:
		return
	for w in root.find_children("*", "Weapon", true, false):
		_weapon_home[w] = (w as Node3D).global_transform


func _reset_weapons() -> void:
	for w in _weapon_home.keys():
		if not is_instance_valid(w):
			continue
		var ww := w as Weapon
		if ww.is_held():
			ww.drop()
		ww.global_transform = _weapon_home[w]
		ww.reset_physics_interpolation()   # оружие вернулось домой — телепорт
		ww.linear_velocity = Vector3.ZERO
		ww.angular_velocity = Vector3.ZERO


# --- забег ---

## Новый забег: intro → волна 1.
func start_run() -> void:
	result = ""
	wave_index = -1
	run_t = 0.0
	wave_t = 0.0
	kills = {"ko": 0, "pit": 0}
	events.clear()
	spawn_queue.clear()
	wave_enemies.clear()
	wave_total = 0
	wave_down = 0
	_barrel_at = -1.0
	_part_line_t = -100.0
	_pit_line_t = -100.0
	Engine.time_scale = 1.0
	_time_effects.clear()
	fight_time = 0.0
	sd_step = -1
	_ko_order.clear()
	ko_records.clear()
	for d in dolls():
		var c := combat_of(d)
		if c != null:
			c.reset()
	_started = true
	_set_phase(Phase.COUNTDOWN)
	wave_state = "intro"
	_log("run_start")
	_say(tr("FIGHTER ON FIELD. NO MATCH SCHEDULED"))
	for p in players():
		hp_changed.emit(p, (p as Doll).hp, (p as Doll).max_hp)
	enemies_changed.emit(0, 0)


## Для проб: бой без волн (урон идёт сразу), враги — только spawn_enemy().
func begin_manual() -> void:
	_started = true
	fight_time = 0.0
	_set_phase(Phase.FIGHT)
	wave_state = "manual"
	wave_index = 0


func start_wave(i: int) -> void:
	if i < 0 or i >= WAVES.size():
		return
	wave_index = i
	wave_t = 0.0
	wave_state = "spawning"
	wave_down = 0
	wave_enemies.clear()
	_revive_dead_players()
	var w: Dictionary = WAVES[i]
	var kinds: Array = w["enemies"]
	wave_total = kinds.size()
	spawn_queue.clear()
	for k in range(kinds.size()):
		spawn_queue.append({"t": chute_warn_s + float(k) * spawn_interval_s, "kind": String(kinds[k])})
	var ch := _chute()
	if ch != null:
		ch.force_state(ScrapMachine.State.WARNING)
	var line := wave_line(i)
	_say(line)
	announce.emit(tr("WAVE %d") % (i + 1), WAVE_COLOUR, "fight")
	wave_started.emit(i, WAVES.size(), line)
	enemies_changed.emit(enemies_left(), wave_total)
	_log("wave_start", {"wave": i + 1, "enemies": kinds.duplicate()})


func _wave_done() -> void:
	_log("wave_clear", {"wave": wave_index + 1})
	wave_cleared.emit(wave_index, WAVES.size())
	if wave_index + 1 >= WAVES.size():
		_finish_run(true)
		return
	wave_state = "pause"
	wave_t = 0.0
	if heal_between_waves > 0.0:
		for p in players_alive():
			var d := p as Doll
			d.hp = minf(d.hp + heal_between_waves, d.max_hp)
			hp_changed.emit(d, d.hp, d.max_hp)
	_say(clear_line(wave_index))
	announce.emit(tr("CLEAR!"), Color(0.55, 0.95, 0.45), "body")


func _finish_run(victory: bool) -> void:
	if wave_state == "victory" or wave_state == "defeat":
		return
	wave_state = "victory" if victory else "defeat"
	result = wave_state
	spawn_queue.clear()
	var line := tr("FIELD CLEAR. RETURN TO THE GARAGE") if victory else tr("FIGHTER DOWN. DEBRIS RECOVERED")
	_say(line)
	announce.emit(tr("FIELD CLEAR!") if victory else tr("FIGHTER DOWN"), Color(1.0, 0.85, 0.3) if victory else Color(0.95, 0.2, 0.15), "fight" if victory else "ko")
	_log("run_over", {"victory": victory, "run_t": snappedf(run_t, 0.01)})
	_set_phase(Phase.OVER)
	run_over.emit(victory, line)
	if victory:
		_barrel_at = run_t + LATE_BARREL_S


## Заново: враги, их метлы, оторванные детали и бочки убираются, игроки пересоздаются на спавнах, оружие площадки — на места.
func restart() -> void:
	_set_phase(Phase.OVER)
	Engine.time_scale = 1.0
	_time_effects.clear()
	spawn_queue.clear()
	# из дерева сразу (не только queue_free): иначе новый P1 в этом же кадре подхватил бы метлу, которая освободится в конце кадра
	for g in ["pve_spawned", "detached_parts"]:
		for n in get_tree().get_nodes_in_group(g):
			if not is_instance_valid(n) or n.is_queued_for_deletion():
				continue
			if n is Weapon and (n as Weapon).is_held():
				(n as Weapon).drop()
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.queue_free()
	wave_enemies.clear()
	_corpses.clear()
	ScraplingBrain.victim_log.clear()
	for p in players():
		var nd := respawn_doll(p)
		_setup_player(nd)
	_reset_weapons()
	_log("restart")
	start_run()


func _revive_dead_players() -> void:
	if players_alive().is_empty():
		return
	for p in players():
		if not (p as Doll).alive:
			var nd := respawn_doll(p)
			_setup_player(nd)
			hp_changed.emit(nd, nd.hp, nd.max_hp)


# --- враги ---

## Враг kind ("scrapling" | "sweeper") в точке pos (корень куклы — ступни) со скоростью vel; мозг молчит drop_s.
func spawn_enemy(kind: String, pos: Vector3, vel := Vector3.ZERO, drop_s := -1.0) -> Doll:
	var ps := _scenes.get(kind) as PackedScene
	if ps == null:
		push_error("WaveDirector: нет врага «%s»" % kind)
		return null
	_spawn_n += 1
	var d := ps.instantiate() as Doll
	d.name = "%s_%d" % [kind.capitalize(), _spawn_n]
	if enemy_team != "" and d.get("team") != null:
		d.set("team", enemy_team)
	if "team_damage_mult" in d:
		d.set("team_damage_mult", enemy_team_damage)   # свои не ранят и не оглушают (толчки полные) — отзыв автора 29.09
	d.add_to_group(dolls_group)
	d.add_to_group(enemies_group)
	d.add_to_group("pve_spawned")
	d.set_meta("enemy_kind", kind)   # max_hp (25 / 50) — в сцене врага, hp = max_hp в Doll._ready
	_enemies_parent().add_child(d)
	d.global_position = Vector3(pos.x, pos.y, 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = _spawn_n * 7919
	for b in d.parts.values():
		(b as RigidBody3D).linear_velocity = Vector3(vel.x, vel.y, 0.0)
	d.torso().angular_velocity = Vector3(0.0, 0.0, rng.randf_range(-2.5, 2.5))
	register(d)
	var br := brain_of(d)
	if br != null:
		br.activate(spawn_drop_s if drop_s < 0.0 else drop_s)
	d.knocked_out.connect(_on_enemy_ko.bind(d))
	wave_enemies.append(d)
	if wave_state == "manual":
		wave_total += 1
	hp_changed.emit(d, d.hp, d.max_hp)
	enemy_spawned.emit(d)
	enemies_changed.emit(enemies_left(), wave_total)
	_log("spawn", {"kind": kind, "name": String(d.name)})
	return d


static func brain_of(d: Node) -> EnemyBrain:
	if d == null:
		return null
	for c in d.get_children():
		if c is EnemyBrain:
			return c
	return null


func _chute() -> ScrapMachine:
	var a := _arena()
	if a != null and a.has_method("chute"):
		return a.call("chute") as ScrapMachine
	return null


## Точка и скорость вылета: из раструба желоба (корень куклы ниже раструба на рост — вся кукла под ним), иначе сверху по центру.
func _spawn_from_chute() -> Array:
	var ch := _chute()
	if ch != null and ch.has_method("mouth_global"):
		var m: Vector3 = ch.call("mouth_global")
		var d: Vector3 = ch.get("spit_dir") if ch.get("spit_dir") is Vector3 else Vector3(0.55, -0.83, 0.0)
		d = d.normalized()
		return [m + d * 0.6 + Vector3(0.0, -1.7, 0.0), d * spawn_speed]
	var a := _arena()
	var b: AABB = a.call("bounds") if a != null and a.has_method("bounds") else AABB(Vector3(-16, -6, -1), Vector3(32, 18, 2))
	return [Vector3(b.get_center().x, b.end.y - 3.0, 0.0), Vector3.ZERO]


func _on_enemy_ko(_attacker: Node, record: Dictionary, d: Doll) -> void:
	var cause := "ko"
	var a := _arena()
	var com := d.centre_of_mass()
	if String(record.get("kind", "")) == "self":
		if a != null and a.has_method("is_in_pit") and bool(a.call("is_in_pit", com)):
			cause = "pit"
		elif com.y < -1.0 or String(record.get("reason", "")) == "bounds":
			cause = "pit"
	kills[cause] = int(kills[cause]) + 1
	if cause == "pit" and run_t - _pit_line_t >= PART_LINE_GAP_S and wave_state in ["spawning", "fight"]:
		_pit_line_t = run_t
		_say(tr("CREW MEMBER DISPOSED. CORRECTLY"))   # свой же уборщик в провале — системы довольны: мусор к мусору
	if wave_enemies.has(d):
		wave_down += 1
	_corpses.append([d, run_t + corpse_s])
	_log("enemy_down", {"name": String(d.name), "cause": cause})
	enemy_down.emit(d, cause)
	enemies_changed.emit(enemies_left(), wave_total)


# --- тик ---

func _physics_process(delta: float) -> void:
	_scan_t += delta
	if _scan_t >= SCAN_INTERVAL_S:
		_scan_t = 0.0
		_scan_dolls()
	if not _started:
		return
	run_t += delta
	wave_t += delta
	if phase == Phase.FIGHT:
		fight_time += delta
	_tick_crit_gate()
	_tick_corpses()
	_tick_barrel()
	match wave_state:
		"intro":
			if wave_t >= intro_s:
				_set_phase(Phase.FIGHT)
				start_wave(0)
		"spawning", "fight":
			_tick_spawns()
			_check_bounds(delta)
			if wave_state == "spawning" and spawn_queue.is_empty():
				wave_state = "fight"
			if wave_state == "fight" and alive_enemies().is_empty():
				_wave_done()
		"pause":
			if wave_t >= wave_pause_s:
				start_wave(wave_index + 1)
		"manual":
			_check_bounds(delta)


func _tick_spawns() -> void:
	while not spawn_queue.is_empty() and wave_t >= float(spawn_queue[0]["t"]):
		var e: Dictionary = spawn_queue.pop_front()
		var sp := _spawn_from_chute()
		spawn_enemy(String(e["kind"]), sp[0], sp[1])


func _check_bounds(delta: float) -> void:
	_bounds_t += delta
	if _bounds_t < BOUNDS_CHECK_S:
		return
	_bounds_t = 0.0
	var a := _arena()
	if a == null or not a.has_method("bounds"):
		return
	var b: AABB = a.call("bounds")
	for e in alive_enemies():
		var c := (e as Doll).centre_of_mass()
		if c.y < b.position.y + 1.0 or c.x < b.position.x - 1.5 or c.x > b.end.x + 1.5 or c.y > b.end.y + 3.0:
			(e as Doll).knock_out(null, {"kind": "self", "reason": "bounds"})


func _tick_crit_gate() -> void:
	var last_enemy := spawn_queue.is_empty() and alive_enemies().size() <= 1
	var gap_ok := Time.get_ticks_msec() - _last_crit_ms >= int(pve_crit_gap_s * 1000.0)
	crit_enabled = pve_crits and wave_state == "fight" and (last_enemy or gap_ok)


## Время последнего крита (crit / ko_crit) — для паузы pve_crit_gap_s между роликами.
func _on_pve_hit_fx(ctx: Dictionary) -> void:
	var tier := String(ctx.get("tier", ""))
	if tier == HitTier.CRIT or tier == HitTier.KO_CRIT:
		_last_crit_ms = Time.get_ticks_msec()


func _tick_corpses() -> void:
	var i := 0
	while i < _corpses.size():
		var e: Array = _corpses[i]
		if run_t >= float(e[1]):
			if is_instance_valid(e[0]):
				(e[0] as Node).queue_free()
			_corpses.remove_at(i)
		else:
			i += 1


## «Правило гашения» (LORE.md): после FIELD CLEAR сверху прилетает запоздавшая бочка — на голову первого живого игрока.
func _tick_barrel() -> void:
	if _barrel_at < 0.0 or run_t < _barrel_at:
		return
	_barrel_at = -1.0
	var alive := players_alive()
	if alive.is_empty() or not ResourceLoader.exists(LATE_BARREL):
		return
	var p := (alive[0] as Doll).centre_of_mass()
	var b := (load(LATE_BARREL) as PackedScene).instantiate() as Node3D
	if b == null:
		return
	b.add_to_group("pve_spawned")
	_enemies_parent().add_child(b)
	b.global_position = Vector3(p.x, p.y + 5.5, 0.0)
	if b is RigidBody3D:
		(b as RigidBody3D).linear_velocity = Vector3(0.0, -3.0, 0.0)
		(b as RigidBody3D).angular_velocity = Vector3(0.0, 0.0, 2.0)
	var a := _arena()
	if a != null and a.has_method("watch_breakable") and b is Breakable:
		a.call("watch_breakable", b)
	_log("late_barrel")


# --- переопределения Match ---

## KO: всё — у Match (записи, статистика, KO!, ko, deferred _check_over). У врага своё только «ощущение»: тряска 25 вместо 40 и
## замедление enemy_ko_slowmo_s вместо Tuning.KO_SLOWMO_S (5 KO за волну по 1.2 с — слишком долгое кино). Тонко: Match чинит двойной
## KO в другой сессии — здесь не копия, а вызов super с выключенным feel_enabled на время вызова.
func _on_doll_ko(attacker: Node, record: Dictionary, victim: Doll) -> void:
	if not is_enemy(victim) or not feel_enabled:
		super._on_doll_ko(attacker, record, victim)
		return
	if phase == Phase.OVER:
		return
	feel_enabled = false
	super._on_doll_ko(attacker, record, victim)
	feel_enabled = true
	var pos: Vector3 = record.get("position", victim.centre_of_mass())
	_camera_fx(25.0, pos)
	_time_effect(Tuning.KO_SLOWMO_SCALE, enemy_ko_slowmo_s)


## Поражение — все игроки KO (последний живой ничего не выигрывает: против него волна).
func _check_over() -> void:
	if wave_state in ["victory", "defeat", "idle"]:
		return
	if not players().is_empty() and players_alive().is_empty():
		_finish_run(false)


func begin() -> void:
	start_run()


func time_left_s() -> float:
	return 0.0


# --- строки и журнал ---

## Строка систем поля на старте волны i.
func wave_line(i: int) -> String:
	match i:
		0: return tr("SERVICE CREW DISPATCHED: DEBRIS RECOVERY")
		1: return tr("FIGHTER RECLASSIFIED AS DEBRIS")
	return tr("FIELD CLEARANCE PRIORITY 1. ALL CREWS TO THE FLOOR")


## Строка в паузе после зачищенной волны (по кругу из двух).
func clear_line(i: int) -> String:
	return tr("CREW OFFLINE. SENDING REPLACEMENT") if i % 2 == 0 else tr("DEBRIS STILL FIGHTING. ESCALATING")


func _say(text: String) -> void:
	field_line.emit(text)
	_log("field", {"line": text})


func _log(what: String, extra: Dictionary = {}) -> void:
	var e := {"t": snappedf(run_t, 0.01), "what": what}
	e.merge(extra)
	events.append(e)
	if events.size() > 200:
		events.pop_front()
