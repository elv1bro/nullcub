## Матч «Стычка 3 на 3» (docs/plan-demo/SQUAD.md; автор 05.10: «карта побольше, стычки 3 на 3 как в шутерах, базовые пулемёты»).
## Наследник Match: от него — регистрация кукол (DollCombat), удары и их эффекты, надписи, отсчёт. Своё — команды и счёт, как в
## командном бою шутеров:
##   • команда — чётность player_index (team_of): 0 — синие (P1 и боты 2, 4), 1 — красные (боты 1, 3, 5). Doll.team "squad_N",
##     team_damage_mult 0 — свои не ранят и не оглушают (ни ударом, ни пулей), толкают полностью; группы squad_0 / squad_1 (цели и
##     разнос ботов, камера); рубашка и обводка — цвет команды (Tuning.SQUAD_COLORS);
##   • пулемёт у каждого (активный блок kit_active_gun на канале 1): числа стычки Tuning.SQUAD_GUN поверх ActiveBlocks.DEFS — своя
##     копия описания блока у каждой куклы, общие DEFS не трогаются; заряд копится быстрее (SQUAD_CHARGE_REGEN) — это патроны; пули
##     ломают ящики и поджигают взрывные бочки (ActiveRig.bullets_break_props);
##   • выбыл (удар, пуля, падение, свой же взрыв) — очко команде соперника; фраг — тому, кто добил (если он из другой команды);
##     кукла возвращается на свою точку базы через SQUAD_RESPAWN_S, первые SQUAD_SPAWN_SHIELD_S урон не проходит;
##   • конец: SQUAD_SCORE_TO_WIN очков, или время SQUAD_TIME_LIMIT_S — ведущий победил, равный счёт — ничья. Last man standing базового
##     Match выключен (_check_over), Sudden Death тоже (часы — до конца времени, без усилений);
##   • KO: замедление короче (SQUAD_KO_SLOWMO_S) и только когда в нокауте участвует человек; крит-кино выключено (бой не встаёт);
##   • корпус бойцов держится вертикально (SQUAD_UPRIGHT, _posture) — иначе рука с пулемётом не достаёт целей над головой.
## Сигналы для HUD (scenes/squad/squad_hud.gd): score_changed, frag, respawn_queued, doll_respawned + унаследованные.
## tally — счёт кукол по player_index: {kills, deaths, damage}; frags — журнал для проб.
class_name SquadMatch
extends Match

signal score_changed(score: Array)
signal frag(killer: Doll, victim: Doll, team: int)
signal respawn_queued(victim: Doll, seconds: float)
signal doll_respawned(doll: Doll)

const GROUP_PREFIX := "squad_"
const GUN_PART := "kit_active_gun"

@export var score_to_win: int = Tuning.SQUAD_SCORE_TO_WIN
@export var respawn_s: float = Tuning.SQUAD_RESPAWN_S

var score := [0, 0]
## idle | countdown | play | over
var play_state := "idle"
var frags: Array = []
var tally: Dictionary = {}          # player_index → {kills, deaths, damage}
var winner_team := -1
## Кукла «я» для HUD и камеры, когда людей нет (пробы и снимки: за P1 играет бот): player_index или −1.
var focus_index := -1
var _respawns: Array = []           # [[Doll, осталось с]]
var _shots_seen: Dictionary = {}    # instance id ActiveRig → shots (звук выстрела)
var _sfx: Node = null


func _ready() -> void:
	time_limit_s = Tuning.SQUAD_TIME_LIMIT_S
	hard_timeout_s = Tuning.SQUAD_TIME_LIMIT_S
	super._ready()
	crit_enabled = false
	hit.connect(_on_hit_tally)


# --- команды ---

static func team_of(d: Object) -> int:
	if d == null or not is_instance_valid(d):
		return -1
	var pi: Variant = d.get("player_index")
	return (int(pi) % 2) if pi != null else -1


static func team_group(team: int) -> String:
	return GROUP_PREFIX + str(team)


static func team_colour(team: int) -> Color:
	return Tuning.SQUAD_COLORS[clampi(team, 0, 1)]


## Живые куклы команды.
func team_alive(team: int) -> Array:
	return alive_dolls().filter(func(d: Variant) -> bool: return team_of(d) == team)


func register(d: Doll) -> void:
	var fresh := not _order.has(d)
	super.register(d)
	if not fresh:
		return
	var t := team_of(d)
	d.team = "squad_%d" % t
	d.team_damage_mult = 0.0
	for g in [team_group(0), team_group(1)]:
		if d.is_in_group(g) and g != team_group(t):
			d.remove_from_group(g)
	d.add_to_group(team_group(t))
	if d.is_node_ready():
		_dress(d)
	else:
		d.ready.connect(_dress.bind(d), CONNECT_ONE_SHOT)
	if not tally.has(d.player_index):
		tally[d.player_index] = {"kills": 0, "deaths": 0, "damage": 0.0}


## Цвет команды: рубашка (Doll._recolor поверх цвета игрока по player_index — их всего 4) и обводка (раньше HitJuice: он красил бы
## обводку цветом игрока, а P5 и P6 — жёлтые).
func _dress(d: Doll) -> void:
	if not is_instance_valid(d):
		return
	var c := team_colour(team_of(d))
	d._recolor(d, Doll.SHIRT_MATERIAL, c)
	DollOutline.ensure(d, c)


## Числа пулемёта стычки: своя копия описания блока поверх ActiveBlocks.DEFS (у ActiveRig блоки ссылаются на общий словарь), заряд
## копится быстрее. ActiveRig собирает блоки после ready куклы, поэтому — когда он готов (зовётся каждый тик, повтор — no-op).
static func tune_gun(d: Doll) -> bool:
	var rig: Variant = d.get("active_rig") if is_instance_valid(d) else null
	if not (rig is ActiveRig) or not is_instance_valid(rig) or not (rig as ActiveRig).ready_ok:
		return false
	var r := rig as ActiveRig
	if r.has_meta("squad_gun"):
		return true
	r.set_meta("squad_gun", true)
	for b in r.blocks:
		if String(b["part"]) == GUN_PART:
			var def: Dictionary = (b["def"] as Dictionary).duplicate()
			def.merge(Tuning.SQUAD_GUN, true)
			b["def"] = def
	r.regen = maxf(r.regen, Tuning.SQUAD_CHARGE_REGEN)
	r.bullets_break_props = true
	return true


## Пулемёты куклы (после tune_gun — с числами стычки): [{def, block, rig, channel, side}] — side "R" / "L" по имени тела-хозяина
## (LowerArm_R → R): по нему мозг и площадка находят руку, которая этот ствол наводит.
static func guns_of(d: Doll) -> Array:
	var out: Array = []
	var rig: Variant = d.get("active_rig") if is_instance_valid(d) else null
	if not (rig is ActiveRig) or not is_instance_valid(rig):
		return out
	for b in (rig as ActiveRig).blocks:
		if String(b["part"]) == GUN_PART:
			var host := b["host"] as Node
			var side := BodyBlueprint.name_suffix(String(host.name)) if host != null and is_instance_valid(host) else ""
			out.append({"def": b["def"], "block": b, "rig": rig, "channel": int(b["channel"]), "side": side})
	return out


## Первый пулемёт куклы или пусто.
static func gun_of(d: Doll) -> Dictionary:
	var g := guns_of(d)
	return g[0] if not g.is_empty() else {}


## Дуло и ось ствола в мире (плоскость боя): [origin: Vector3, axis: Vector3 (z = 0, единичная)] или пусто.
static func muzzle_of(gun: Dictionary) -> Array:
	var b: Dictionary = gun.get("block", {})
	var host := b.get("host") as RigidBody3D
	if host == null or not is_instance_valid(host):
		return []
	var xf := b["xf"] as Transform3D
	var o := host.global_transform * (xf * ((gun["def"] as Dictionary)["muzzle"] as Vector3))
	var ax := host.global_basis * xf.basis.y
	ax.z = 0.0
	if ax.length_squared() < 1e-6:
		return []
	return [Vector3(o.x, o.y, 0.0), ax.normalized()]


## Рука (ArmAssist), которая наводит ствол gun: кисть той же стороны (Hand_R ↔ LowerArm_R).
static func arm_for(d: Doll, gun: Dictionary) -> ArmAssist:
	var side := String(gun.get("side", ""))
	for c in d.get_children():
		if c is ArmAssist and not c.is_queued_for_deletion() and BodyBlueprint.name_suffix((c as ArmAssist).part_name) == side:
			return c
	return null


## Кукла «я»: человек (external_input = false), иначе кукла focus_index, иначе null.
func me() -> Doll:
	for d in dolls():
		if not (d as Doll).external_input:
			return d
	if focus_index >= 0:
		for d in dolls():
			if (d as Doll).player_index == focus_index:
				return d
	return null


# --- фазы ---

func begin() -> void:
	score = [0, 0]
	frags.clear()
	winner_team = -1
	_respawns.clear()
	for k in tally.keys():
		tally[k] = {"kills": 0, "deaths": 0, "damage": 0.0}
	play_state = "countdown"
	super.begin()
	score_changed.emit(score.duplicate())


func _start_fight() -> void:
	super._start_fight()
	play_state = "play"


func _finish(reason: String) -> void:
	if phase == Phase.OVER:
		return
	play_state = "over"
	_respawns.clear()
	winner_team = -1 if int(score[0]) == int(score[1]) else (0 if int(score[0]) > int(score[1]) else 1)
	for d in dolls():
		(d as Doll).control_enabled = false   # итоги: боты и стволы молчат (ActiveRig — только с управлением)
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
	for d in dolls():
		tune_gun(d as Doll)
		_posture(d as Doll)
	_tick_gun_audio()
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
			_tick_respawns(delta)
			if fight_time >= time_limit_s:
				_finish("timeout")


# --- нокаут, счёт, возрождение ---

func _check_over() -> void:
	pass


func _on_doll_ko(attacker: Node, record: Dictionary, victim: Doll) -> void:
	if phase == Phase.OVER or play_state != "play":
		return
	var feel := feel_enabled
	feel_enabled = false
	super._on_doll_ko(attacker, record, victim)
	feel_enabled = feel
	var vt := team_of(victim)
	var other := 1 - vt
	var killer: Doll = attacker as Doll if attacker is Doll and is_instance_valid(attacker) and attacker != victim \
		and team_of(attacker) == other else null
	score[other] = int(score[other]) + 1
	_tally(victim.player_index, "deaths", 1)
	if killer != null:
		_tally(killer.player_index, "kills", 1)
	frags.append({"t": snappedf(fight_time, 0.01), "victim": victim.player_index, "killer": killer.player_index if killer != null else -1,
		"team": other, "kind": String(record.get("kind", "")), "score": score.duplicate()})
	score_changed.emit(score.duplicate())
	frag.emit(killer, victim, other)
	if feel and (_is_human(victim) or _is_human(killer)):
		_camera_fx(25.0, record.get("position", victim.centre_of_mass()))
		if FxPreset.time_fx():
			_time_effect(Tuning.KO_SLOWMO_SCALE, Tuning.SQUAD_KO_SLOWMO_S)
	if int(score[other]) >= score_to_win:
		call_deferred("_finish", "score")
		return
	_respawns.append([victim, respawn_s])
	respawn_queued.emit(victim, respawn_s)


static func _is_human(d: Object) -> bool:
	return d != null and is_instance_valid(d) and d is Doll and not (d as Doll).external_input


func _tally(pi: int, key: String, v: float) -> void:
	if not tally.has(pi):
		tally[pi] = {"kills": 0, "deaths": 0, "damage": 0.0}
	var t: Dictionary = tally[pi]
	t[key] = (t[key] + int(v)) if t[key] is int else (float(t[key]) + v)


func _on_hit_tally(victim: Doll, attacker: Node, damage: float, _kind: String, _pos: Vector3) -> void:
	if attacker is Doll and is_instance_valid(attacker) and attacker != victim and team_of(attacker) != team_of(victim):
		_tally((attacker as Doll).player_index, "damage", damage)


## Секунды до возрождения куклы (−1 — не ждёт).
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
			var nd := respawn_doll(d as Doll)
			nd.control_enabled = true
			nd.grace_until = maxf(nd.grace_until, Tuning.SQUAD_SPAWN_SHIELD_S)   # _time новой куклы ≈ 0
			hp_changed.emit(nd, nd.hp, nd.max_hp)
			doll_respawned.emit(nd)


# --- осанка ---

## Корпус к вертикали (Tuning.SQUAD_UPRIGHT; тот же PD, что Doll._tick_posture с ControlFeel upright): иначе рука с пулемётом не
## достаёт целей выше головы. Молчит у мёртвых, без управления, в стане, раскрутке и полёте после удара. Вариант управления с
## осанкой (панель Tab) добавит свою — две PD к одной цели не спорят.
func _posture(d: Doll) -> void:
	if Tuning.SQUAD_UPRIGHT <= 0.0 or not d.alive or d.is_broken() or not d.control_enabled or d.is_stunned() \
			or d._spinning or d._time < d.knockback_until:
		return
	var t := d.torso()
	if t == null:
		return
	var angle := atan2(t.global_basis.x.y, t.global_basis.x.x)
	var err := clampf(wrapf(angle, -PI, PI), -1.5, 1.5)
	var tau := -Tuning.SQUAD_UPRIGHT * (ControlFeel.UPRIGHT_K * err + ControlFeel.UPRIGHT_D * t.angular_velocity.z) * d.thrust_mass()
	t.apply_torque(Vector3(0, 0, tau))


# --- звук выстрела ---

## У пулемёта своего звука нет (попадание звучит через SfxDirector по материалу). Здесь — сухой щелчок на каждый выстрел: слой
## «snap» с высоким питчем, панорама по x относительно камеры; SfxDirector сам режет повторы чаще LAYER_GAP_MS.
func _tick_gun_audio() -> void:
	if _sfx == null or not is_instance_valid(_sfx):
		_sfx = get_tree().get_first_node_in_group(SfxDirector.GROUP)
		if _sfx == null:
			return
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	for d in dolls():
		var rig: Variant = (d as Doll).get("active_rig")
		if not (rig is ActiveRig) or not is_instance_valid(rig):
			continue
		var id := (rig as Object).get_instance_id()
		var shots := (rig as ActiveRig).shots
		var seen := int(_shots_seen.get(id, shots))
		_shots_seen[id] = shots
		if shots <= seen:
			continue
		var x := (d as Doll).centre_of_mass().x
		var dx := x - (cam.global_position.x if cam != null else 0.0)
		if absf(dx) > 26.0:
			continue
		var near := 1.0 - clampf(absf(dx) / 26.0, 0.0, 1.0)
		var db := -16.0 + 10.0 * near + (4.0 if _is_human(d) else 0.0)
		_sfx.call("play_layer", "snap", db, randf_range(1.7, 2.1), SfxDirector.BUS_SFX, clampf(dx / 14.0, -1.0, 1.0))


# --- итоги ---

## Итоги: базовые (места по HP, медали) + счёт команд, победившая команда, фраги кукол. HUD стычки показывает свою таблицу.
func build_results(reason: String = "timeout") -> Dictionary:
	var r := super.build_results(reason)
	r["score"] = score.duplicate()
	r["winner_team"] = -1 if int(score[0]) == int(score[1]) else (0 if int(score[0]) > int(score[1]) else 1)
	r["draw"] = int(score[0]) == int(score[1])
	r["tally"] = tally.duplicate(true)
	r["frags"] = frags.duplicate(true)
	return r
