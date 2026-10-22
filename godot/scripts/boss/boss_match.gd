## Матч «Босс» (docs/plan-demo/BOSS.md; MODES_IDEAS.md В1): один громадный чемпион лиги против одного-двух игроков в куполе Old NULL Hall.
## Наследник Match: от него — регистрация кукол, DollCombat (удары с уроном, как в бою), KO, отсчёт, надписи. Своё:
##   • босс — кукла в группе "boss" (scenes/boss/boss_doll.tscn, BossBrain); его запас — Σ ❤ деталей, приведённая к Tuning.BOSS_HP
##     (_boss_pool); порог отрыва детали — её ❤ × BOSS_BREAK_MULT (голова — BOSS_HEAD_BREAK_MULT), отлетела — запас теряет её ❤;
##   • уязвимая деталь (weak_part) светится BOSS_WEAK_S, потом другая (торс — никогда, голова — только в фазе 3): удар в неё ×
##     BOSS_WEAK_MULT (adjust_hit_damage, weak_hits);
##   • фазы (boss_phase 1..3) по доле запаса BOSS_PHASE_AT: смена — диктор, сигнал boss_phase_changed (HUD: вспышка и тост),
##     журнал phase_log; фаза 3 — ярость (тяга, скорость, поле купола BOSS_RAGE_FIELD_G, волна-толчок раз в BOSS_WAVE_S с
##     телеграфом BOSS_WAVE_WARN_S: wave_warning → wave);
##   • удар босса по игроку × BOSS_HIT_MULT[фаза − 1] (потолок BOSS_HIT_CAP); игроки в одной команде "players" с team_damage_mult 0 —
##     друг друга не бьют (толчки остаются);
##   • у игрока BOSS_LIVES возрождений (через BOSS_RESPAWN_S на точке подальше от босса); KO без жизней — выбыл;
##   • конец: босс выбит (голова оторвана или запас 0) — победа игроков (reason "boss"); все игроки выбыли — "wipe"; лимит
##     time_limit_s = BOSS_TIME_S — "timeout" (босс выстоял). Sudden Death и «последний живой» базового Match выключены.
## play_state: idle | countdown | play | over. Журналы для проб: phase_log [{t, phase, frac}], parts_log [{t, part, by}], ko_log, waves.
class_name BossMatch
extends Match

signal boss_phase_changed(n: int)
signal weak_changed(part_name: String)
signal wave_warning(seconds: float)
signal wave(hits: int)
signal lives_changed(player_index: int, lives: int)
signal respawn_queued(victim: Doll, seconds: float)
signal doll_respawned(doll: Doll)
signal boss_part_lost(part_name: String, by: Node)

const BOSS_GROUP := "boss"
const PLAYERS_TEAM := "players"
const PHASE_COLOURS := [Color(1.0, 0.85, 0.3), Color(1.0, 0.55, 0.15), Color(1.0, 0.2, 0.15)]
const WEAK_COLOUR := Color(1.0, 0.75, 0.15)

@export var respawn_s: float = Tuning.BOSS_RESPAWN_S
@export var lives_per_player: int = Tuning.BOSS_LIVES
## Сид случайностей (порядок уязвимых деталей); 0 — каждый раз новый.
@export var rng_seed := 0

var play_state := "idle"
var boss: Doll = null
var boss_phase := 1
var weak_part := ""
var weak_left := 0.0
## player_index → сколько возрождений осталось.
var lives: Dictionary = {}
## player_index → {dmg, weak_hits, kos_taken, parts}
var tally: Dictionary = {}
var phase_log: Array = []
var parts_log: Array = []
var ko_log: Array = []
var waves: Array = []           # [{t, hits}]
var weak_hits := 0
var wave_left := 0.0            # до следующей волны (фаза 3), с
var wave_warn := -1.0           # ≥ 0 — идёт телеграф волны, осталось с
var players_won := false
var kill_kind := ""             # head (голова оторвана) | pool (запас 0)
var boss_env_dmg := 0.0         # урон боссу от купола и падений (для проб)
var _respawns: Array = []       # [[Doll, осталось с]]
var _respawn_at: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _restart_pending := false
var _in_tick := false
var _field_saved: Array = []    # [g, dir] поля купола до ярости
var _glow_mat: StandardMaterial3D
var _glow_t := 0.0
var _glow_body: Variant = null   # светится сейчас (и после отрыва: деталь улетела — снять свечение с неё)
var _finish_pending := ""


func _ready() -> void:
	time_limit_s = Tuning.BOSS_TIME_S
	hard_timeout_s = 1.0e9
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_mat.albedo_color = Color(WEAK_COLOUR, 0.5)
	_glow_mat.grow = true
	_glow_mat.grow_amount = 0.02
	super._ready()
	crit_enabled = false


func _exit_tree() -> void:
	_restore_field()
	super._exit_tree()


# --- куклы ---

func register(d: Doll) -> void:
	super.register(d)
	if d.is_in_group(BOSS_GROUP):
		boss = d
		if not d.part_detached.is_connected(_on_boss_part_lost):
			d.part_detached.connect(_on_boss_part_lost)
		return
	d.team = PLAYERS_TEAM
	d.team_damage_mult = 0.0
	if not lives.has(d.player_index):
		lives[d.player_index] = lives_per_player
	if not tally.has(d.player_index):
		tally[d.player_index] = _blank_tally()


static func _blank_tally() -> Dictionary:
	return {"dmg": 0.0, "weak_hits": 0, "kos_taken": 0, "parts": 0}


func players() -> Array:
	var out: Array = []
	for d in dolls():
		if d != boss:
			out.append(d)
	return out


func alive_players() -> Array:
	var out: Array = []
	for d in players():
		if (d as Doll).alive:
			out.append(d)
	return out


func is_boss(d: Object) -> bool:
	return d != null and is_instance_valid(d) and d == boss


static func _is_human(d: Object) -> bool:
	return d != null and is_instance_valid(d) and d is Doll and not (d as Doll).external_input


## Точка появления: Tuning.BOSS_SPAWN (P1, P2, босс — третий); после KO — точка возврата (_respawn_at).
func spawn_point_for(d: Doll) -> Vector3:
	if _respawn_at.has(d.player_index):
		return _respawn_at[d.player_index]
	var pts: Array = Tuning.BOSS_SPAWN
	var i := pts.size() - 1 if d.is_in_group(BOSS_GROUP) else clampi(d.player_index, 0, pts.size() - 2)
	var p: Vector2 = pts[i]
	return Vector3(p.x, p.y, 0.0)


## Точка возврата игрока — самая дальняя от босса из BOSS_RESPAWN_POINTS.
func respawn_point() -> Vector3:
	var bp := Vector2.ZERO
	if is_instance_valid(boss) and boss.is_inside_tree():
		var c := boss.centre_of_mass()
		bp = Vector2(c.x, c.y)
	var best: Vector2 = Tuning.BOSS_RESPAWN_POINTS[0]
	var bd := -1.0
	for p in Tuning.BOSS_RESPAWN_POINTS:
		var dd := (p as Vector2).distance_to(bp)
		if dd > bd:
			bd = dd
			best = p
	return Vector3(best.x, best.y, 0.0)


static func doll_name(d: Object) -> String:
	if d == null or not is_instance_valid(d):
		return "—"
	return "P%d" % (int(d.get("player_index")) + 1)


# --- запас босса ---

## Запас: у босса — свой (BOSS_HP из деталей), у игроков — как в базовом Match («Запас из деталей»).
func _parts_hp(d: Doll) -> void:
	if d.is_in_group(BOSS_GROUP):
		_boss_pool(d)
		return
	super._parts_hp(d)


## ❤ деталей босса × BOSS_HP / Σ (Σ ровно BOSS_HP), пороги отрыва — ❤ × BOSS_BREAK_MULT / BOSS_HEAD_BREAK_MULT; стан от ударов ×
## BOSS_STUN_MULT (мета PartMods stun_mult на каждом теле — DollCombat._deliver). Запас ставится один раз на куклу (мета "boss_pool"):
## повторный вызов (HitJuice «;» → Match.refresh_parts_hp) только заново ставит пороги отрыва, запас и оторванное не трогает.
func _boss_pool(d: Doll) -> void:
	if not d.has_meta("boss_pool"):
		d._init_part_hp()
		var k := Tuning.BOSS_HP / maxf(d.parts_hp_total(), 1.0)
		for n in d.part_hp.keys():
			d.part_hp[n] = float(d.part_hp[n]) * k
		for b in d.parts.values():
			var m: Dictionary = ((b as Object).get_meta(PartMods.META, {}) as Dictionary).duplicate()
			m["stun_mult"] = float(m.get("stun_mult", 1.0)) * Tuning.BOSS_STUN_MULT
			(b as Object).set_meta(PartMods.META, m)
		d.max_hp = Tuning.BOSS_HP
		d.hp = Tuning.BOSS_HP
		d.set_meta("boss_pool", true)
	d.refresh_wear()
	for n in d.joint_hp_max.keys():
		var b := d.parts.get(n) as RigidBody3D
		var head := Doll.part_base_name(String(n)) == "Head"
		var mx := float(d.part_hp.get(n, 0.0)) * (Tuning.BOSS_HEAD_BREAK_MULT if head else Tuning.BOSS_BREAK_MULT)
		mx *= PartMods.of(b, "break_mult")
		d.joint_hp_max[n] = mx
		d.joint_hp[n] = mx
	d.set_meta("parts_hp", true)


## Доля запаса босса (0…1) от BOSS_HP.
func boss_frac() -> float:
	if not is_instance_valid(boss):
		return 0.0
	return clampf(boss.hp / Tuning.BOSS_HP, 0.0, 1.0) if boss.alive else 0.0


## Фаза по доле запаса: ≥ BOSS_PHASE_AT[0] — 1, ≥ BOSS_PHASE_AT[1] — 2, ниже — 3.
static func phase_for(frac: float) -> int:
	var at: Array = Tuning.BOSS_PHASE_AT
	if frac >= float(at[0]):
		return 1
	if frac >= float(at[1]):
		return 2
	return 3


func _on_boss_part_lost(part_name: String, by: Node) -> void:
	if play_state != "play":
		return
	var pi := -1
	if is_instance_valid(by) and by is Doll and tally.has((by as Doll).player_index):
		pi = (by as Doll).player_index
		(tally[pi] as Dictionary)["parts"] = int(tally[pi]["parts"]) + 1
	parts_log.append({"t": snappedf(fight_time, 0.01), "part": part_name, "by": pi})
	boss_part_lost.emit(part_name, by)
	if part_name == weak_part:
		_set_weak(_pick_weak())


# --- уязвимая деталь ---

## Кандидаты: детали босса с запасом отрыва (не торс); голова — только в фазе 3.
func weak_candidates() -> Array:
	var out: Array = []
	if not is_instance_valid(boss):
		return out
	for n in boss.joint_hp.keys():
		if not boss.parts.has(n):
			continue
		if Doll.part_base_name(String(n)) == "Head" and boss_phase < 3:
			continue
		out.append(String(n))
	out.sort()
	return out


func _pick_weak() -> String:
	var c := weak_candidates()
	c.erase(weak_part)
	if c.is_empty():
		return ""
	return String(c[_rng.randi() % c.size()])


func weak_body() -> RigidBody3D:
	if weak_part == "" or not is_instance_valid(boss):
		return null
	return boss.parts.get(weak_part) as RigidBody3D


func _set_weak(n: String) -> void:
	_glow(_glow_body, false)
	weak_part = n
	weak_left = Tuning.BOSS_WEAK_S
	_glow_body = weak_body()
	_glow(_glow_body, true)
	weak_changed.emit(weak_part)


## Подсветка уязвимой детали: оверлей (аддитивное свечение) на её сетках; прежний оверлей возвращается.
func _glow(b: Variant, on: bool) -> void:   # Variant: деталь могла быть освобождена (обломок убран)
	if not is_instance_valid(b) or not b is Node:
		return
	for mi in (b as Node).find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if on:
			if not m.has_meta("boss_prev_overlay"):
				m.set_meta("boss_prev_overlay", m.material_overlay)
			m.material_overlay = _glow_mat
		elif m.has_meta("boss_prev_overlay"):
			m.material_overlay = m.get_meta("boss_prev_overlay")
			m.remove_meta("boss_prev_overlay")


func _tick_weak(delta: float) -> void:
	_glow_t += delta
	_glow_mat.albedo_color = Color(WEAK_COLOUR, 0.3 + 0.25 * (0.5 + 0.5 * sin(_glow_t * TAU * 1.6)))
	weak_left -= delta
	if weak_left <= 0.0 or (weak_part != "" and weak_body() == null):
		_set_weak(_pick_weak())


# --- фазы босса ---

func _tick_phase() -> void:
	var want := phase_for(boss_frac())
	if want <= boss_phase:
		return
	boss_phase = want
	phase_log.append({"t": snappedf(fight_time, 0.01), "phase": boss_phase, "frac": snappedf(boss_frac(), 0.001)})
	var col: Color = PHASE_COLOURS[boss_phase - 1]
	if boss_phase == 2:
		announce.emit(tr("ФАЗА 2: РЫВКИ"), col, "boss_phase")
	else:
		announce.emit(tr("ФАЗА 3: ЯРОСТЬ"), col, "boss_phase")
		_enter_rage()
	boss_phase_changed.emit(boss_phase)
	if feel_enabled and _any_human():
		_camera_fx(60.0, boss.centre_of_mass() if is_instance_valid(boss) else Vector3.ZERO)


## Шлем: в фазах 1–2 сустав головы изнашивается не ниже BOSS_HEAD_GUARD её порога — серией ударов голову не сорвать, пока
## босс не в ярости (иначе бой кончался «головой» в фазе 2 и ярость не наступала). Один удар сильнее остатка рвёт и раньше.
func _tick_helmet() -> void:
	if boss_phase >= 3:
		return
	for n in boss.joint_hp.keys():
		if Doll.part_base_name(String(n)) == "Head":
			var guard: float = float(boss.joint_hp_max.get(n, 0.0)) * Tuning.BOSS_HEAD_GUARD
			if float(boss.joint_hp[n]) < guard:
				boss.joint_hp[n] = guard


func _enter_rage() -> void:
	if is_instance_valid(boss):
		boss.thrust_mult = Tuning.BOSS_RAGE_THRUST
		boss.speed_cap_mult = Tuning.BOSS_RAGE_SPEED
	var a := _arena()
	if a != null and a.has_method("set_field"):
		var f: Variant = a.get("field")
		if _field_saved.is_empty() and f is Object and is_instance_valid(f):
			_field_saved = [float((f as Object).get("field_g")), (f as Object).get("field_dir")]
		a.call("set_field", Tuning.BOSS_RAGE_FIELD_G, Vector2(0.0, -1.0))
	wave_left = Tuning.BOSS_WAVE_S * 0.5
	wave_warn = -1.0


func _restore_field() -> void:
	if _field_saved.is_empty():
		return
	var a := _arena()
	if a != null and a.has_method("set_field"):
		a.call("set_field", float(_field_saved[0]), _field_saved[1] as Vector2)
	_field_saved.clear()


## Волна-толчок (фаза 3): телеграф BOSS_WAVE_WARN_S, потом всех игроков ближе BOSS_WAVE_R от ЦМ босса — прочь (Δv от BOSS_WAVE_DV у
## босса до половины у края) с уроном BOSS_WAVE_DMG и коротким станом.
func _tick_wave(delta: float) -> void:
	if boss_phase < 3 or not is_instance_valid(boss) or not boss.alive:
		return
	if wave_warn >= 0.0:
		wave_warn -= delta
		if wave_warn < 0.0:
			_do_wave()
			wave_left = Tuning.BOSS_WAVE_S
		return
	wave_left -= delta
	if wave_left <= 0.0:
		wave_warn = Tuning.BOSS_WAVE_WARN_S
		announce.emit(tr("ВОЛНА!"), PHASE_COLOURS[2], "boss_wave")
		wave_warning.emit(Tuning.BOSS_WAVE_WARN_S)


func _do_wave() -> int:
	var c := boss.centre_of_mass()
	var hits := 0
	for d in alive_players():
		var dd := d as Doll
		var p := dd.centre_of_mass()
		var v := Vector3(p.x - c.x, p.y - c.y, 0.0)
		var dist := v.length()
		if dist > Tuning.BOSS_WAVE_R:
			continue
		var dir := v / dist if dist > 0.05 else Vector3.UP
		var k := 1.0 - 0.5 * clampf(dist / Tuning.BOSS_WAVE_R, 0.0, 1.0)
		var t := dd.torso()
		if t == null:
			continue
		dd.apply_knockback(dir * Tuning.BOSS_WAVE_DV * k * t.mass, null, 0.5)
		dd.stun(0.5)
		dd.take_damage(Tuning.BOSS_WAVE_DMG * k, boss, "Torso", p, -dir, "body")
		hits += 1
	waves.append({"t": snappedf(fight_time, 0.01), "hits": hits})
	wave.emit(hits)
	if feel_enabled and _any_human():
		_camera_fx(50.0, c)
	return hits


## Сейчас идёт телеграф волны (HUD рисует кольцо).
func wave_warning_left() -> float:
	return wave_warn


func _any_human() -> bool:
	for d in players():
		if _is_human(d):
			return true
	return false


# --- фазы матча ---

func begin() -> void:
	_restore_field()
	phase_log.clear()
	parts_log.clear()
	ko_log.clear()
	waves.clear()
	weak_hits = 0
	players_won = false
	kill_kind = ""
	boss_env_dmg = 0.0
	_finish_pending = ""
	_respawns.clear()
	_respawn_at.clear()
	boss_phase = 1
	wave_left = 0.0
	wave_warn = -1.0
	for k in tally.keys():
		tally[k] = _blank_tally()
	for d in players():
		lives[(d as Doll).player_index] = lives_per_player
		lives_changed.emit((d as Doll).player_index, lives_per_player)
	play_state = "countdown"
	super.begin()
	weak_part = ""
	weak_left = 0.0


## R / «Заново»: куклы пересоздаются только в своём тике (как KingMatch: вызов внутри чужого кадра физики до тика поля купола
## оставляет мембране вынутые из дерева детали).
func restart() -> void:
	if not _in_tick:
		_restart_pending = true
		return
	_restart_pending = false
	_respawn_at.clear()
	_respawns.clear()
	_glow(_glow_body, false)
	_glow_body = null
	weak_part = ""
	super.restart()


func _start_fight() -> void:
	super._start_fight()
	play_state = "play"
	_set_weak(_pick_weak())


func _finish(reason: String) -> void:
	if phase == Phase.OVER:
		return
	play_state = "over"
	players_won = reason == "boss"
	_respawns.clear()
	_glow(_glow_body, false)
	_glow_body = null
	for d in dolls():
		(d as Doll).control_enabled = false
	super._finish(reason)


func stasis_allowed() -> bool:
	return play_state == "play" and super.stasis_allowed()


func knockback_mult() -> float:
	return 1.0


func stability_mult() -> float:
	return 1.0


func time_left_s() -> float:
	match phase:
		Phase.COUNTDOWN:
			return time_limit_s
		Phase.FIGHT:
			return maxf(time_limit_s - fight_time, 0.0)
	return 0.0


func _physics_process(delta: float) -> void:
	_scan_t += delta
	if _scan_t >= SCAN_INTERVAL_S:
		_scan_t = 0.0
		_scan_dolls()
	if _restart_pending:
		_in_tick = true
		restart()
		_in_tick = false
		return
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
			if play_state != "play":
				return
			if _finish_pending != "":
				_finish(_finish_pending)
				return
			_tick_respawns(delta)
			if is_instance_valid(boss) and boss.alive:
				var floor_c: float = Tuning.BOSS_CHARGE_FLOOR[boss_phase - 1]
				if boss.charge < floor_c:
					boss.charge = floor_c
				_tick_phase()
				_tick_helmet()
				_tick_weak(delta)
				_tick_wave(delta)
			if alive_players().is_empty() and _respawns.is_empty() and not players().is_empty():
				_finish("wipe")
			elif fight_time >= time_limit_s:
				_finish("timeout")


# --- удары ---

## Урон удара (DollCombat._apply_hit): в босса — × BOSS_PLAYER_DMG_MULT, в светящуюся деталь ещё × BOSS_WEAK_MULT; босс по игроку —
## × BOSS_HIT_MULT[фаза − 1], не больше BOSS_HIT_CAP.
func adjust_hit_damage(victim: Doll, attacker: Node, dmg: float, c: Dictionary) -> float:
	if play_state != "play":
		return dmg
	if is_boss(victim):
		dmg *= Tuning.BOSS_PLAYER_DMG_MULT
		var vp: Variant = c.get("victim_part")
		if weak_part != "" and is_instance_valid(vp) and vp is Node and String((vp as Node).name) == weak_part:
			dmg *= Tuning.BOSS_WEAK_MULT
			weak_hits += 1
			if is_instance_valid(attacker) and attacker is Doll and tally.has((attacker as Doll).player_index):
				var t: Dictionary = tally[(attacker as Doll).player_index]
				t["weak_hits"] = int(t["weak_hits"]) + 1
		return dmg
	if is_boss(attacker):
		return minf(dmg * float(Tuning.BOSS_HIT_MULT[boss_phase - 1]), Tuning.BOSS_HIT_CAP)
	return dmg


## С человеком — как в бою (тряска, стоп-кадр, надписи); боты между собой — только сигнал hit и Заряд. Урон по боссу — в tally.
func on_hit(victim: Doll, attacker: Node, damage: float, kind: String, position: Vector3, combo_n: int, double_blow: bool, weapon_id: String, speed: float) -> void:
	if is_boss(victim) and kind == "environment":
		boss_env_dmg += damage
	if is_boss(victim) and damage > 0.0 and is_instance_valid(attacker) and attacker is Doll and tally.has((attacker as Doll).player_index):
		var t: Dictionary = tally[(attacker as Doll).player_index]
		t["dmg"] = float(t["dmg"]) + damage
	if _is_human(victim) or _is_human(attacker):
		super.on_hit(victim, attacker, damage, kind, position, combo_n, double_blow, weapon_id, speed)
		return
	hit.emit(victim, attacker, damage, kind, position)
	if victim == null or not is_instance_valid(victim) or damage <= 0.0 or kind == "environment":
		return
	Charge.apply_hit(make_hit_ctx(victim, attacker, damage, kind, position, combo_n, double_blow, weapon_id, speed))


func _emit_env_slam(ctx: Dictionary) -> void:
	if _is_human(ctx.get("doll")):
		super._emit_env_slam(ctx)


# --- нокаут и возврат ---

func _check_over() -> void:
	pass   # конец — босс выбит, игроки выбыли или время (_physics_process / _on_doll_ko)


func _on_doll_ko(attacker: Node, record: Dictionary, victim: Doll) -> void:
	if phase == Phase.OVER or play_state != "play":
		return
	var feel := feel_enabled
	feel_enabled = feel and (_is_human(victim) or _is_human(attacker) or (victim == boss and _any_human()))
	super._on_doll_ko(attacker, record, victim)
	feel_enabled = feel
	if victim == boss:
		kill_kind = "head" if String(record.get("kind", "")) == "detach" and String(record.get("part", "")).begins_with("Head") else "pool"
		ko_log.append({"t": snappedf(fight_time, 0.01), "victim": "boss", "attacker": doll_name(attacker), "kind": kill_kind})
		announce.emit(tr("БОСС ПОВЕРЖЕН!"), PHASE_COLOURS[0], "boss_down")
		_finish_pending = "boss"
		return
	var pi := victim.player_index
	if tally.has(pi):
		(tally[pi] as Dictionary)["kos_taken"] = int(tally[pi]["kos_taken"]) + 1
	ko_log.append({"t": snappedf(fight_time, 0.01), "victim": pi, "attacker": "boss" if attacker == boss else doll_name(attacker)})
	var left := int(lives.get(pi, 0))
	if left > 0:
		lives[pi] = left - 1
		lives_changed.emit(pi, left - 1)
		_respawns.append([victim, respawn_s])
		respawn_queued.emit(victim, respawn_s)
	else:
		lives_changed.emit(pi, -1)


## Секунды до возврата куклы (−1 — не ждёт).
func respawn_left(d: Doll) -> float:
	for e in _respawns:
		if e[0] == d:
			return float(e[1])
	return -1.0


func _tick_respawns(delta: float) -> void:
	var i := 0
	while i < _respawns.size():
		var e: Array = _respawns[i]
		e[1] = float(e[1]) - delta
		if float(e[1]) > 0.0:
			i += 1
			continue
		_respawns.remove_at(i)
		var d: Variant = e[0]
		if is_instance_valid(d) and (d as Doll).is_inside_tree() and not (d as Doll).alive:
			var pi := (d as Doll).player_index
			_respawn_at[pi] = respawn_point()
			var nd := respawn_doll(d as Doll)
			_respawn_at.erase(pi)
			nd.control_enabled = true
			hp_changed.emit(nd, nd.hp, nd.max_hp)
			doll_respawned.emit(nd)


# --- итоги ---

## Лучший игрок (больше урона по боссу; равно — меньший номер).
func mvp() -> Doll:
	var best: Doll = null
	var bd := -1.0
	for d in players():
		var dd := d as Doll
		var v := float((tally.get(dd.player_index, {}) as Dictionary).get("dmg", 0.0))
		if best == null or v > bd + 1e-4 or (absf(v - bd) <= 1e-4 and dd.player_index < best.player_index):
			bd = v
			best = dd
	return best


## Итоги: базовые (статистика, медали) + исход (players_won: победитель — лучший по урону игрок, иначе босс), время, фазы, детали
## босса, урон и жизни игроков, волны.
func build_results(reason: String = "timeout") -> Dictionary:
	var r := super.build_results(reason)
	var won := reason == "boss"
	var winner: Doll = mvp() if won else (boss if is_instance_valid(boss) else null)
	var order: Array = players()
	order.sort_custom(func(a: Doll, b: Doll) -> bool:
		var da := float((tally.get(a.player_index, {}) as Dictionary).get("dmg", 0.0))
		var db := float((tally.get(b.player_index, {}) as Dictionary).get("dmg", 0.0))
		return da > db if absf(da - db) > 1e-4 else a.player_index < b.player_index)
	r["places"] = order
	r["ranks"] = range(order.size())
	r["winner"] = winner
	r["draw"] = false
	r["players_won"] = won
	var medals: Dictionary = r.get("medals", {})
	medals.erase("Winner")
	medals.erase("Survivor")
	if won and winner != null:
		medals["Winner"] = winner
	r["medals"] = medals
	r["match_time"] = fight_time
	r["boss_phase"] = boss_phase
	r["boss_hp"] = boss.hp if is_instance_valid(boss) else 0.0
	r["boss_frac"] = boss_frac()
	r["kill_kind"] = kill_kind
	r["parts_lost"] = parts_log.duplicate(true)
	r["phase_log"] = phase_log.duplicate(true)
	r["ko_log"] = ko_log.duplicate(true)
	r["waves"] = waves.duplicate(true)
	r["weak_hits"] = weak_hits
	r["boss_env_dmg"] = boss_env_dmg
	r["tally"] = tally.duplicate(true)
	r["lives"] = lives.duplicate()
	return r
