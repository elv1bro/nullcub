## Матч «Стычка 3 на 3» (docs/plan-demo/SQUAD.md; автор 05.10: «карта побольше, стычки 3 на 3 как в шутерах»; дальше — заходы
## 05–06.10: оружие из рук, патроны и ящики, классы и опыт, рукопашник, подклассы, захват флага, бонусы, прочность суставов).
## Наследник Match: от него — регистрация кукол (DollCombat), удары телом и их эффекты, надписи, отсчёт. Своё:
##   • команда — чётность player_index (team_of): 0 — синие (P1 и боты 2, 4), 1 — красные (боты 1, 3, 5). Doll.team "squad_N",
##     team_damage_mult 0 — свои не ранят и не оглушают, толкают полностью; группы squad_0 / squad_1 (цели и разнос ботов, камера);
##     рубашка и обводка — цвет команды (Tuning.SQUAD_COLORS), вид — по классу (SquadLook, только меши — физика та же);
##   • режим mode: «dm» (перестрелка) — выбыл соперник — очко команде; «ctf» (захват флага) — очко за доставленный флаг (_tick_flags,
##     SquadFlag), выбывания очков не дают. Конец: score_to_win очков или время (ведущий победил; равный счёт — ничья); выбывший
##     возвращается на свою базу через respawn_s, первые SQUAD_SPAWN_SHIELD_S урон не проходит;
##   • оружие — SquadGun (снайпер, налётчик) или SquadMelee (громила) на кукле; урон пули идёт через bullet_hit, удар телом и оружием —
##     через свой on_hit: без тряски и стоп-кадров (с ДРАЙВОМ каждая пуля и каждое касание дёргали кадр и время); adjust_hit_damage —
##     потолок удара громилы (в полёте — SQUAD_DASH_HIT_MAX и не чаще SQUAD_DASH_HIT_GAP_S по одному бойцу), ярость, топор сквозь броню;
##     удар молота в полёте — ударная волна;
##   • классы и опыт (loadout по player_index: класс, следующий класс, ветка, опыт, уровень; сбрасываются на begin): опыт — за урон и
##     фраг (SQUAD_XP_*), уровень растёт сам и сразу открывает, что записано в классе (SQUAD_CLASSES: levels 1–4, на SQUAD_BRANCH_LEVEL —
##     выбор ветки, её levels — 5–8) — сигнал leveled для HUD; ветку игрок выбирает клавишами (choose_branch; не выбрал за
##     SQUAD_BRANCH_AUTO_S — первая), бот — сразу (по очереди матчей); класс меняется set_class (на отсчёте — сразу, в бою — с возрождения);
##   • броня (armor по player_index): пока она есть, Doll.incoming_mult = SQUAD_ARMOR_MULT, прошедший урон снимается и с брони;
##   • ящики (SupplyCrate) — раз в SQUAD_SUPPLY_EVERY_S на свободной точке карты: патроны, жизни, броня и бонусы на время (обзор,
##     ярость, форсаж — boosts_active); любой ящик возвращает оторванные конечности (прочность суставов, автор 06.10);
##   • суставы бойцов — запас × SQUAD_JOINT_HP_MULT; пуля в кисть изнашивает предплечье (износ кисти × 4 — отрывало с одной пули);
##   • KO: замедление короче (SQUAD_KO_SLOWMO_S) и только когда в нокауте участвует человек; крит-кино выключено;
##   • корпус бойцов держится вертикально (SQUAD_UPRIGHT, _posture) — иначе рука с оружием не достаёт целей над головой.
## Сигналы для HUD (scenes/squad/squad_hud.gd): score_changed, frag, respawn_queued, doll_respawned, xp_changed, leveled,
## branch_pending, class_changed, bullet_landed, melee_landed, supply_taken, flag_event + унаследованные. tally — счёт кукол по
## player_index: {kills, deaths, damage, captures}; frags — журнал проб.
class_name SquadMatch
extends Match

signal score_changed(score: Array)
signal frag(killer: Doll, victim: Doll, team: int)
signal respawn_queued(victim: Doll, seconds: float)
signal doll_respawned(doll: Doll)
signal xp_changed(player_index: int, xp: float, level: int)
signal leveled(player_index: int, level: int, unlock: Dictionary)
## Игрок дошёл до SQUAD_BRANCH_LEVEL: выбрать ветку (подкласс) класса — клавиши 1…N, или первая сама через SQUAD_BRANCH_AUTO_S.
signal branch_pending(player_index: int, class_id: String)
signal class_changed(player_index: int, class_id: String, pending: bool)
signal bullet_landed(victim: Doll, shooter: Doll, damage: float, position: Vector3)
signal melee_landed(victim: Doll, attacker: Doll, damage: float, position: Vector3)
signal supply_taken(doll: Doll, kind: String)
## Захват флага: what — taken | dropped | returned | captured; team — чей флаг; doll — кто (взял, выронил, вернул, доставил) или null.
signal flag_event(team: int, what: String, doll: Doll)

const GROUP_PREFIX := "squad_"
const SUPPLY_GROUP := "squad_supply"

## «dm» — перестрелка (очко за выбывшего), «ctf» — захват флага (очко за доставленный флаг).
@export var mode := "dm"
## До скольких очков: фраги в перестрелке, флаги в захвате.
@export var score_to_win: int = Tuning.SQUAD_SCORE_TO_WIN
@export var respawn_s: float = Tuning.SQUAD_RESPAWN_S
## Ящики снабжения (пробы правил выключают, чтобы не мешали счёту) и бонусы среди них.
@export var supplies := true
@export var boosts := true

var score := [0, 0]
## idle | countdown | play | over
var play_state := "idle"
var frags: Array = []
var tally: Dictionary = {}          # player_index → {kills, deaths, damage}
var winner_team := -1
## Кукла «я» для HUD и камеры, когда людей нет (пробы и снимки: за P1 играет бот): player_index или −1.
var focus_index := -1
## player_index → {class, next_class, branch, xp, level}
var loadouts: Dictionary = {}
## player_index → {вид бонуса: осталось с}
var boosts_active: Dictionary = {}
## player_index → осталось с до выбора ветки за игрока
var branch_wait: Dictionary = {}
## Флаги «Захвата флага» [синих, красных] (пусто в перестрелке).
var flags: Array = []
## Номер матча (begin): боты выбирают ветки по очереди — от матча к матчу разные.
var round_n := 0
## Наибольший урон одного удара оружием громилы и число ударов в полёте (пробы: «не ваншотит»).
var melee_max_hit := 0.0
var dash_hits_n := 0
var waves := 0
var limbs_restored := 0
## Счётчики для проб: ударов телом / оружием (on_hit), из них с тряской камеры.
var melee_hits := 0
var melee_shakes := 0
## player_index → броня (0..SQUAD_ARMOR_MAX)
var armor: Dictionary = {}
var supplies_spawned := 0
var supplies_taken: Dictionary = {"ammo": 0, "health": 0, "armor": 0}
var _respawns: Array = []           # [[Doll, осталось с]]
var _sfx: Node = null
var _supply_t := 0.0
var _rng := RandomNumberGenerator.new()
var _dash_hit_t: Dictionary = {}   # "атакующий:жертва" → fight_time последнего удара в полёте
## Заранее загруженные сцены (оружие громилы всех уровней, ящик): первая сковорода / меч / ящик посреди боя иначе читались бы с
## диска синхронно — заметная заминка (автор 06.10: «иногда подвисает во время битвы»). Ссылки держат ресурсы в кэше.
var _warm: Array[Resource] = []


func _ready() -> void:
	time_limit_s = Tuning.SQUAD_TIME_LIMIT_S
	hard_timeout_s = Tuning.SQUAD_TIME_LIMIT_S
	super._ready()
	crit_enabled = false
	_rng.seed = 0x5a1d
	hit.connect(_on_hit_tally)
	_prewarm()


func _prewarm() -> void:
	var paths: Array[String] = [SupplyCrate.MODEL]
	for id in Tuning.SQUAD_MELEE:
		paths.append(Weapon.scene_path(String(id)))
	paths.append_array(SquadLook.model_paths())   # вид классов (смена класса на отсчёте не читает диск)
	for p in paths:
		if ResourceLoader.exists(p):
			var r := load(p)
			if r != null:
				_warm.append(r)


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


## Оружие куклы (SquadGun) или null.
static func gun_of(d: Object) -> SquadGun:
	if d == null or not is_instance_valid(d) or not (d is Node):
		return null
	for c in (d as Node).get_children():
		if c is SquadGun and not c.is_queued_for_deletion():
			return c
	return null


## Рукопашное оружие куклы (SquadMelee) или null.
static func melee_of(d: Object) -> SquadMelee:
	if d == null or not is_instance_valid(d) or not (d is Node):
		return null
	for c in (d as Node).get_children():
		if c is SquadMelee and not c.is_queued_for_deletion():
			return c
	return null


## Живые куклы команды.
func team_alive(team: int) -> Array:
	return alive_dolls().filter(func(d: Variant) -> bool: return team_of(d) == team)


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
		tally[d.player_index] = _fresh_tally()
	_apply_class_stats(d)
	d.damaged.connect(_on_armor_damaged.bind(d))
	d.thrust_mult = 1.0


## Цвет команды: рубашка (Doll._recolor поверх цвета игрока по player_index — их всего 4) и обводка (раньше HitJuice: он красил бы
## обводку цветом игрока, а P5 и P6 — жёлтые).
func _dress(d: Doll) -> void:
	if not is_instance_valid(d):
		return
	var c := team_colour(team_of(d))
	_look(d)
	d._recolor(d, Doll.SHIRT_MATERIAL, c)
	DollOutline.ensure(d, c)
	_scale_joints(d)


## Вид бойца по классу (SquadLook: только меши, физика та же); fresh — сменил класс на отсчёте (новые меши — в обводку).
func _look(d: Doll, fresh := false) -> void:
	if not (d is ModularDoll):
		return
	var t := team_of(d)
	SquadLook.apply(d as ModularDoll, String(loadout(d.player_index)["class"]), t)
	if fresh:
		d._recolor(d, Doll.SHIRT_MATERIAL, team_colour(t))
		SquadLook.refresh_outline(d as ModularDoll, team_colour(t))


## Запас суставов × SQUAD_JOINT_HP_MULT (JOINT_HP_BASE рассчитан на удары телом, а винтовка в 24 HP отрывала бы предплечье с выстрела).
func _scale_joints(d: Doll) -> void:
	if d.has_meta("squad_joints"):
		return
	d.set_meta("squad_joints", true)
	for n in d.joint_hp_max.keys():
		d.joint_hp_max[n] = float(d.joint_hp_max[n]) * Tuning.SQUAD_JOINT_HP_MULT
		d.joint_hp[n] = float(d.joint_hp_max[n])


# --- фазы ---

func begin() -> void:
	score = [0, 0]
	frags.clear()
	winner_team = -1
	_respawns.clear()
	round_n += 1
	boosts_active.clear()
	branch_wait.clear()
	_dash_hit_t.clear()
	melee_max_hit = 0.0
	dash_hits_n = 0
	waves = 0
	limbs_restored = 0
	for k in tally.keys():
		tally[k] = _fresh_tally()
	for k in loadouts.keys():
		var cls := String(loadouts[k]["next_class"])
		loadouts[k] = _fresh_loadout(cls)
	_clear_supplies()
	supplies_spawned = 0
	supplies_taken = {"ammo": 0, "health": 0, "armor": 0}
	_supply_t = 0.0
	play_state = "countdown"
	super.begin()   # пересоздаёт сломанных — оружие возьмут из свежего loadout
	for d in dolls():
		(d as Doll).thrust_mult = 1.0
		_restore_limbs(d as Doll)
		_apply_class_stats(d as Doll)
		_equip(d as Doll)
		xp_changed.emit((d as Doll).player_index, 0.0, 1)
	_setup_flags()
	score_changed.emit(score.duplicate())


func _fresh_tally() -> Dictionary:
	return {"kills": 0, "deaths": 0, "damage": 0.0, "captures": 0}


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
		(d as Doll).control_enabled = false   # итоги: боты и стволы молчат (SquadGun — только с управлением)
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
		_posture(d as Doll)
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
			_tick_supplies(delta)
			_tick_boosts(delta)
			_tick_branch_wait(delta)
			_tick_flags(delta)
			if fight_time >= time_limit_s:
				_finish("timeout")


# --- урон пулей ---

## Урон пули (SquadGun): как удар оружием (броня тела, команда, броня стычки — через Doll.take_damage / incoming_mult, статистика,
## сигнал hit), но без Match.on_hit — ни тряски, ни толчков кадра, ни стоп-кадров, ни замедлений, ни надписей: шесть стволов бьют
## десятки раз в секунду. Только искры у попадания и короткий звук. Возвращает снятый урон.
func bullet_hit(victim: Doll, shooter: Doll, amount: float, part: String, pos: Vector3, normal: Vector3, weapon_id: String) -> float:
	if not combat_active() or victim == null or not is_instance_valid(victim) or not victim.alive or not victim.can_take_damage():
		return 0.0
	amount *= Damage.armor_mult_of_body(victim.parts.get(part) as Node)
	amount *= float((Tuning.SQUAD_CLASSES[String(loadout(victim.player_index)["class"])] as Dictionary).get("bullet_mult", 1.0))
	amount *= boost_mult(shooter, "rage")
	if part.begins_with("Hand") and victim.parts.has(part.replace("Hand", "LowerArm")):
		part = part.replace("Hand", "LowerArm")   # износ кисти × 4 (Damage.target_mult кисти 0.25): пуля в кисть отрывала её сразу
	victim.hit_meta = {"speed": 0.0, "weapon_id": "squad_" + weapon_id, "striker": shooter, "combo_mult": 1.0, "double_blow": false,
		"knockback_mult": 0.0, "stun_s": 0.0, "bullet": true}
	var hp0 := victim.hp
	victim.take_damage(amount, shooter, part, pos, normal, "weapon")
	var dealt := hp0 - victim.hp
	if dealt <= 0.0:
		return 0.0
	if is_instance_valid(shooter):
		shooter.stats["damage_dealt"] = float(shooter.stats.get("damage_dealt", 0.0)) + dealt
		shooter.stats["hardest_hit"] = maxf(float(shooter.stats.get("hardest_hit", 0.0)), dealt)
	hit.emit(victim, shooter, dealt, "weapon", pos)
	bullet_landed.emit(victim, shooter, dealt, pos)
	if feel_enabled:
		ImpactFx.spawn_impact(victim, pos, normal, clampf(dealt, 4.0, 18.0), "light")
		_play("hit_l", -14.0 + minf(dealt, 30.0) * 0.25, randf_range(1.1, 1.35), pos)
	return dealt


## Урон удара телом или оружием до применения (DollCombat._apply_hit): ярость бьющего; оружие громилы — не больше
## SQUAD_MELEE_HIT_MAX, в полёте — не больше SQUAD_DASH_HIT_MAX и по одному бойцу не чаще SQUAD_DASH_HIT_GAP_S (автор 06.10: «проверь,
## чтобы импульс был нормальный и не ваншотил сразу всех»); топор — сквозь броню стычки (Doll.incoming_mult её снимет обратно).
func adjust_hit_damage(victim: Doll, attacker: Node, dmg: float, c: Dictionary) -> float:
	if not (attacker is Doll) or not is_instance_valid(attacker) or attacker == victim:
		return dmg
	var a := attacker as Doll
	dmg *= boost_mult(a, "rage")
	var ml := melee_of(a)
	if ml == null or ml.weapon == null or not is_instance_valid(ml.weapon) or c.get("striker") != ml.weapon:
		return dmg
	if ml.in_dash():
		var key := "%d:%d" % [a.get_instance_id(), victim.get_instance_id()]
		if _dash_hit_t.has(key) and fight_time - float(_dash_hit_t[key]) < Tuning.SQUAD_DASH_HIT_GAP_S:
			return 0.0
		_dash_hit_t[key] = fight_time
		dmg = minf(dmg, Tuning.SQUAD_DASH_HIT_MAX)
		dash_hits_n += 1
	else:
		dmg = minf(dmg, Tuning.SQUAD_MELEE_HIT_MAX)
	if bool(ml.prop("armor_pierce", false)) and armor_of(victim) > 0.0:
		dmg /= Tuning.SQUAD_ARMOR_MULT
	melee_max_hit = maxf(melee_max_hit, dmg)
	return dmg


## Удар телом или оружием в руке (зовёт DollCombat): в стычке — без Match.on_hit-эффектов. Там на каждый удар — тряска и толчок
## кадра, стоп-кадр и микрозамедление (с ДРАЙВОМ — от 2.5 HP), а шесть бойцов в свалке касаются друг друга непрерывно: автор 06.10
## «в рукопашке всё трясётся, и не прерывается». Здесь: сигнал hit (счёт, опыт, ИИ), Заряд за удар (как в бою — Charge.apply_hit),
## звук (искры в точке удара ставит сам DollCombat); камеру чуть трясёт только удар не слабее SQUAD_MELEE_SHAKE_MIN, если в нём участвует человек.
func on_hit(victim: Doll, attacker: Node, damage: float, kind: String, position: Vector3, combo_n: int, double_blow: bool, weapon_id: String, speed: float) -> void:
	hit.emit(victim, attacker, damage, kind, position)
	if victim == null or not is_instance_valid(victim) or damage <= 0.0 or kind == "environment":
		return
	melee_hits += 1
	Charge.apply_hit(make_hit_ctx(victim, attacker, damage, kind, position, combo_n, double_blow, weapon_id, speed))
	if attacker is Doll and is_instance_valid(attacker):
		melee_landed.emit(victim, attacker as Doll, damage, position)
		var ml := melee_of(attacker)
		if ml != null and ml.in_dash() and not ml.wave_done and float(ml.prop("wave_m", 0.0)) > 0.0 and kind == "weapon":
			ml.wave_done = true
			_shockwave(attacker as Doll, position, ml)
	if not feel_enabled:
		return
	_play("hit_m" if damage >= 10.0 else "hit_l", -8.0 + minf(damage, 30.0) * 0.2, randf_range(0.95, 1.1), position)
	if damage >= Tuning.SQUAD_MELEE_SHAKE_MIN and (_is_human(victim) or _is_human(attacker)):
		melee_shakes += 1
		_camera_fx(minf(damage, 40.0) * Tuning.SQUAD_MELEE_SHAKE_MULT, position)


## Ударная волна молота (удар в полёте): соперники ближе wave_m от точки удара — толчок от неё, стан и немного урона.
func _shockwave(attacker: Doll, at: Vector3, ml: SquadMelee) -> void:
	waves += 1
	var r := float(ml.prop("wave_m", 3.0))
	for d in team_alive(1 - team_of(attacker)):
		var dd := d as Doll
		var c := dd.centre_of_mass()
		var v := Vector3(c.x - at.x, c.y - at.y, 0.0)
		var dist := v.length()
		if dist > r:
			continue
		var k := 1.0 - dist / r * 0.5
		var dir := (v / dist if dist > 0.05 else Vector3.UP)
		var stun := float(ml.prop("wave_stun_s", 0.6)) * k
		dd.apply_knockback((dir + Vector3(0.0, 0.35, 0.0)).normalized() * float(ml.prop("wave_impulse", 26.0)) * k, dd.torso(), stun)
		dd.stun(stun)
		if dd.can_take_damage():
			dd.take_damage(float(ml.prop("wave_damage", 8.0)) * k, attacker, "Torso", c, -dir, "weapon")
	if feel_enabled:
		ImpactFx.spawn_impact(self, at, Vector3.UP, 30.0, "heavy")
		_play("hit_m", -4.0, 0.7, at)


## Удар о стену или пол без урона: эффекты (с тряской и наездом камеры) — только у человека, у ботов — тишина.
func _emit_env_slam(ctx: Dictionary) -> void:
	if _is_human(ctx.get("doll")):
		super._emit_env_slam(ctx)


## Выпад громилы (SquadMelee): свист замаха.
func lunge_sound(d: Doll) -> void:
	if feel_enabled and is_instance_valid(d):
		_play("swing_h", -8.0 + (4.0 if _is_human(d) else 0.0), randf_range(0.9, 1.05), d.centre_of_mass())


## Выстрел (SquadGun): звук оружия (Tuning.SQUAD_WEAPONS[…].sound — [слой, питч]) с панорамой по x; дальше 26 м от камеры — тишина.
func gun_sound(d: Doll, def: Dictionary) -> void:
	if not feel_enabled or not is_instance_valid(d):
		return
	var snd: Array = def.get("sound", ["snap", 1.6])
	_play(String(snd[0]), -9.0 + (4.0 if _is_human(d) else 0.0), float(snd[1]) * randf_range(0.95, 1.05), d.centre_of_mass())


func _play(layer: String, db: float, pitch: float, at: Vector3) -> void:
	if _sfx == null or not is_instance_valid(_sfx):
		_sfx = get_tree().get_first_node_in_group(SfxDirector.GROUP)
		if _sfx == null:
			return
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	var dx := at.x - (cam.global_position.x if cam != null else 0.0)
	if absf(dx) > 26.0:
		return
	var near := 1.0 - clampf(absf(dx) / 26.0, 0.0, 1.0)
	_sfx.call("play_layer", layer, db - 10.0 * (1.0 - near), pitch, SfxDirector.BUS_SFX, clampf(dx / 14.0, -1.0, 1.0))


# --- броня ---

## Броня куклы d (0..SQUAD_ARMOR_MAX).
func armor_of(d: Doll) -> float:
	return float(armor.get(d.player_index, 0.0)) if is_instance_valid(d) else 0.0


func add_armor(d: Doll, amount: float) -> void:
	armor[d.player_index] = clampf(armor_of(d) + amount, 0.0, Tuning.SQUAD_ARMOR_MAX)
	d.incoming_mult = Tuning.SQUAD_ARMOR_MULT if armor_of(d) > 0.0 else 1.0


## Прошедший урон снимается и с брони (броня гасила вторую половину — Doll.incoming_mult); кончилась — урон снова полный.
func _on_armor_damaged(amount: float, _attacker: Node, _part: String, _pos: Vector3, _kind: String, d: Doll) -> void:
	if not is_instance_valid(d) or armor_of(d) <= 0.0:
		return
	add_armor(d, -amount * (1.0 - Tuning.SQUAD_ARMOR_MULT) / Tuning.SQUAD_ARMOR_MULT)


# --- классы и опыт ---

func _fresh_loadout(cls: String = "") -> Dictionary:
	var c := cls if Tuning.SQUAD_CLASSES.has(cls) else String(Tuning.SQUAD_SLOT_CLASSES[0])
	return {"class": c, "next_class": c, "branch": "", "xp": 0.0, "level": 1}


## Класс по месту в команде (player_index / 2): Tuning.SQUAD_SLOT_CLASSES — составы зеркальные.
static func slot_class(pi: int) -> String:
	return String(Tuning.SQUAD_SLOT_CLASSES[(pi / 2) % Tuning.SQUAD_SLOT_CLASSES.size()])


## Класс, ветка, опыт и уровень куклы player_index (новой — класс её места в команде).
func loadout(pi: int) -> Dictionary:
	if not loadouts.has(pi):
		loadouts[pi] = _fresh_loadout(slot_class(pi))
	return loadouts[pi]


## Открытия класса cls по порядку до уровня level: уровни 1–4 — общий ствол (levels), 5–8 — ветка branch (её levels; ветки нет — их нет).
static func unlocks_of(cls: String, level: int, branch: String = "") -> Array:
	var c: Dictionary = Tuning.SQUAD_CLASSES.get(cls, Tuning.SQUAD_CLASSES[Tuning.SQUAD_CLASS_ORDER[0]])
	var out: Array = []
	var trunk: Array = c["levels"]
	for i in range(mini(level, trunk.size())):
		out.append(trunk[i])
	var br: Dictionary = (c.get("branches", {}) as Dictionary).get(branch, {})
	if not br.is_empty():
		var bl: Array = br["levels"]
		for i in range(clampi(level - trunk.size(), 0, bl.size())):
			out.append(bl[i])
	return out


## Что открывает уровень level класса cls (с веткой branch): {weapon | melee | perk} или {"choose": true} — выбор ветки ещё не сделан.
static func unlock_at(cls: String, level: int, branch: String = "") -> Dictionary:
	if level >= Tuning.SQUAD_BRANCH_LEVEL and branch == "":
		return {"choose": true} if level == Tuning.SQUAD_BRANCH_LEVEL else {}
	var u := unlocks_of(cls, level, branch)
	return u[level - 1] if level - 1 < u.size() else {}


## Что открыто у класса cls на уровне level с веткой branch: {weapon (огнестрел, "" — нет), melee (рукопашное, "" — нет), perks {id: раз}}.
static func kit_of(cls: String, level: int, branch: String = "") -> Dictionary:
	var out := {"weapon": "", "melee": "", "perks": {}}
	for u in unlocks_of(cls, level, branch):
		if (u as Dictionary).has("weapon"):
			out["weapon"] = String(u["weapon"])
		if (u as Dictionary).has("melee"):
			out["melee"] = String(u["melee"])
		if (u as Dictionary).has("perk"):
			var perks: Dictionary = out["perks"]
			perks[String(u["perk"])] = int(perks.get(String(u["perk"]), 0)) + 1
	return out


## Набор куклы сейчас (по её классу, ветке и уровню).
func kit(pi: int) -> Dictionary:
	var lo := loadout(pi)
	return kit_of(String(lo["class"]), int(lo["level"]), String(lo["branch"]))


## Уровень по опыту (1…SQUAD_XP_LEVELS.size()).
static func level_for(xp: float) -> int:
	var lv := 1
	for i in range(Tuning.SQUAD_XP_LEVELS.size()):
		if xp >= float(Tuning.SQUAD_XP_LEVELS[i]):
			lv = i + 1
	return lv


## Доля пути к следующему уровню 0..1 (1 — последний уровень).
func xp_progress(pi: int) -> float:
	var lo := loadout(pi)
	var lv := int(lo["level"])
	if lv >= Tuning.SQUAD_XP_LEVELS.size():
		return 1.0
	var a := float(Tuning.SQUAD_XP_LEVELS[lv - 1])
	var b := float(Tuning.SQUAD_XP_LEVELS[lv])
	return clampf((float(lo["xp"]) - a) / maxf(b - a, 1.0), 0.0, 1.0)


## Опыт: уровень растёт сам; каждый новый уровень — открытие класса (leveled) и сразу у живого бойца. На SQUAD_BRANCH_LEVEL без ветки —
## выбор: бот выбирает сразу, игроку — branch_pending и SQUAD_BRANCH_AUTO_S на выбор.
func add_xp(pi: int, amount: float) -> void:
	if amount <= 0.0:
		return
	var lo := loadout(pi)
	lo["xp"] = float(lo["xp"]) + amount
	var lv := level_for(float(lo["xp"]))
	while int(lo["level"]) < lv:
		lo["level"] = int(lo["level"]) + 1
		var unlock := unlock_at(String(lo["class"]), int(lo["level"]), String(lo["branch"]))
		if unlock.has("choose"):
			var d0 := _doll_of_index(pi)
			if d0 != null and d0.external_input:
				choose_branch(pi, bot_branch(pi, String(lo["class"])))
				continue
			branch_wait[pi] = Tuning.SQUAD_BRANCH_AUTO_S
			leveled.emit(pi, int(lo["level"]), unlock)
			branch_pending.emit(pi, String(lo["class"]))
			continue
		_grant(pi, unlock)
		leveled.emit(pi, int(lo["level"]), unlock)
	xp_changed.emit(pi, float(lo["xp"]), int(lo["level"]))


## Открытие уровня у живого бойца: оружие и усиления (патроны остаются), броня «броня», запас «запас».
func _grant(pi: int, unlock: Dictionary) -> void:
	var d := _doll_of_index(pi)
	if d == null or not d.alive:
		return
	_equip(d, true)
	match String(unlock.get("perk", "")):
		"tough":
			add_armor(d, float(Tuning.SQUAD_PERKS["tough"]["armor"]))
		"hp":
			var add := float(Tuning.SQUAD_PERKS["hp"]["hp"]) * _hp_scale()
			d.max_hp += add
			d.hp = minf(d.hp + add, d.max_hp)
			hp_changed.emit(d, d.hp, d.max_hp)


## Ветка (подкласс) бота: по очереди веток класса — от матча к матчу (round_n) и по месту в команде; у обеих команд одна и та же.
func bot_branch(pi: int, cls: String) -> String:
	var order: Array = (Tuning.SQUAD_CLASSES[cls] as Dictionary).get("branch_order", [])
	if order.is_empty():
		return ""
	return String(order[(round_n + pi / 2) % order.size()])


## Выбрать ветку класса (клавиша игрока, бот, время вышло): всё открытое веткой до текущего уровня — сразу.
func choose_branch(pi: int, branch: String) -> bool:
	var lo := loadout(pi)
	var c: Dictionary = Tuning.SQUAD_CLASSES[String(lo["class"])]
	if String(lo["branch"]) != "" or not (c.get("branches", {}) as Dictionary).has(branch) or int(lo["level"]) < Tuning.SQUAD_BRANCH_LEVEL:
		return false
	lo["branch"] = branch
	branch_wait.erase(pi)
	for lv in range(Tuning.SQUAD_BRANCH_LEVEL, int(lo["level"]) + 1):
		var unlock := unlock_at(String(lo["class"]), lv, branch)
		_grant(pi, unlock)
		var u := unlock.duplicate()
		u["branch"] = branch
		leveled.emit(pi, lv, u)
	return true


## Ветка ждёт выбора игрока (HUD): осталось секунд, −1 — не ждёт.
func branch_left(pi: int) -> float:
	return float(branch_wait.get(pi, -1.0))


func _tick_branch_wait(delta: float) -> void:
	for pi in branch_wait.keys():
		branch_wait[pi] = float(branch_wait[pi]) - delta
		if float(branch_wait[pi]) <= 0.0:
			var lo := loadout(int(pi))
			var order: Array = (Tuning.SQUAD_CLASSES[String(lo["class"])] as Dictionary).get("branch_order", [])
			if order.is_empty():
				branch_wait.erase(pi)
			else:
				choose_branch(int(pi), String(order[0]))


## Сменить класс: на отсчёте — сразу (оружие, запас HP, броня, вид), в бою — с возрождения (живому — «сменится при возврате»).
## Ветка — заново (у другого класса свои ветки): уровень SQUAD_BRANCH_LEVEL и выше — снова выбор.
func set_class(pi: int, cls: String) -> bool:
	if not Tuning.SQUAD_CLASSES.has(cls):
		return false
	var lo := loadout(pi)
	lo["next_class"] = cls
	var d := _doll_of_index(pi)
	var now := play_state != "play" or d == null
	if now:
		_switch_class(pi)
		if d != null:
			_apply_class_stats(d)
			_equip(d)
			_look(d, true)
	class_changed.emit(pi, cls, not now)
	return true


## Класс ← следующий класс; другой класс — ветка заново (дальше уровня выбора — ждёт выбора, у бота — сразу).
func _switch_class(pi: int) -> void:
	var lo := loadout(pi)
	if String(lo["class"]) == String(lo["next_class"]):
		return
	lo["class"] = String(lo["next_class"])
	lo["branch"] = ""
	branch_wait.erase(pi)
	if int(lo["level"]) >= Tuning.SQUAD_BRANCH_LEVEL:
		var d := _doll_of_index(pi)
		if d != null and d.external_input:
			lo["branch"] = bot_branch(pi, String(lo["class"]))
		else:
			branch_wait[pi] = Tuning.SQUAD_BRANCH_AUTO_S
			branch_pending.emit(pi, String(lo["class"]))


## Запас HP с ДРАЙВОМ — в той же пропорции, что у обычной куклы.
func _hp_scale() -> float:
	return Tuning.DRIVE_MAX_HP / Tuning.MAX_HP if Drive.on else 1.0


## Запас HP класса (+ усиления «запас») и броня возврата (класс + усиления «броня»).
func _apply_class_stats(d: Doll) -> void:
	var lo := loadout(d.player_index)
	var c: Dictionary = Tuning.SQUAD_CLASSES[String(lo["class"])]
	var perks: Dictionary = kit(d.player_index)["perks"]
	var hp := (float(c["hp"]) + float(Tuning.SQUAD_PERKS["hp"]["hp"]) * int(perks.get("hp", 0))) * _hp_scale()
	d.max_hp = hp
	d.hp = hp
	armor[d.player_index] = 0.0
	d.incoming_mult = 1.0
	var a := float(c["armor"]) + float(Tuning.SQUAD_PERKS["tough"]["armor"]) * int(perks.get("tough", 0))
	if a > 0.0:
		add_armor(d, a)
	hp_changed.emit(d, d.hp, d.max_hp)


## Оружие куклы по набору: стрелку — SquadGun.equip (keep_ammo — усиление посреди боя: патроны остаются), громиле — SquadMelee.
func _equip(d: Doll, keep_ammo := false) -> void:
	var k := kit(d.player_index)
	var g := gun_of(d)
	if g != null:
		if String(k["weapon"]) == "":
			g.disarm()
		elif keep_ammo and g.weapon == String(k["weapon"]):
			var m := g.mag
			var r := g.reserve
			g.equip(String(k["weapon"]), k["perks"])
			g.mag = mini(m, g.mag_max)
			g.reserve = mini(maxi(r, g.reserve), g.reserve_max)
		else:
			g.equip(String(k["weapon"]), k["perks"])
	var ml := melee_of(d)
	if ml != null:
		var n := int((k["perks"] as Dictionary).get("dash", 0))
		ml.equip(String(k["melee"]), pow(float(Tuning.SQUAD_PERKS["dash"]["dash"]), n))


## Зум камеры игрока d: класс (снайпер дальше) × бонус «обзор».
func view_zoom(d: Doll) -> float:
	if d == null or not is_instance_valid(d):
		return 1.0
	var c: Dictionary = Tuning.SQUAD_CLASSES[String(loadout(d.player_index)["class"])]
	return float(c.get("zoom", 1.0)) * boost_mult(d, "zoom")


func _doll_of_index(pi: int) -> Doll:
	for d in dolls():
		if (d as Doll).player_index == pi:
			return d
	return null


# --- бонусы ---

## Множитель бонуса kind у бойца d (Tuning.SQUAD_SUPPLY[kind].mult, пока бонус идёт; иначе 1).
func boost_mult(d: Object, kind: String) -> float:
	if d == null or not is_instance_valid(d) or not (d is Doll):
		return 1.0
	return float(Tuning.SQUAD_SUPPLY[kind]["mult"]) if boost_left(d as Doll, kind) > 0.0 else 1.0


## Осталось бонуса kind у бойца (с), 0 — нет.
func boost_left(d: Doll, kind: String) -> float:
	var b: Dictionary = boosts_active.get(d.player_index, {})
	return float(b.get(kind, 0.0))


func _tick_boosts(delta: float) -> void:
	for pi in boosts_active.keys():
		var b: Dictionary = boosts_active[pi]
		for k in b.keys():
			b[k] = float(b[k]) - delta
			if float(b[k]) <= 0.0:
				b.erase(k)
	for d in dolls():
		var dd := d as Doll
		var carry := Tuning.SQUAD_FLAG_CARRIER_THRUST if carried_flag(dd) != null else 1.0
		var haste := boost_mult(dd, "haste")
		dd.thrust_mult = haste * carry
		var ml := melee_of(dd)
		if ml == null or not ml.dashing:
			dd.speed_cap_mult = haste


# --- ящики снабжения ---

func _tick_supplies(delta: float) -> void:
	if not supplies:
		return
	_supply_t += delta
	if _supply_t < Tuning.SQUAD_SUPPLY_EVERY_S:
		return
	_supply_t = 0.0
	var live := get_tree().get_nodes_in_group(SUPPLY_GROUP)
	if live.size() >= Tuning.SQUAD_SUPPLY_MAX:
		return
	var a := _arena()
	if a == null or not a.has_method("supply_points"):
		return
	var free: Array = []
	for p in a.call("supply_points"):
		var taken := false
		for c in live:
			if (c as Node3D).global_position.distance_to(p) < 1.5:
				taken = true
		if not taken:
			free.append(p)
	if free.is_empty():
		return
	spawn_supply(_pick_kind(), free[_rng.randi_range(0, free.size() - 1)])


func _pick_kind() -> String:
	var kinds: Array = []
	for k in Tuning.SQUAD_SUPPLY:
		if boosts or not Tuning.SQUAD_BOOSTS.has(k):
			kinds.append(k)
	var total := 0.0
	for k in kinds:
		total += float(Tuning.SQUAD_SUPPLY[k]["weight"])
	var r := _rng.randf() * total
	for k in kinds:
		r -= float(Tuning.SQUAD_SUPPLY[k]["weight"])
		if r <= 0.0:
			return k
	return "ammo"


## Ящик вида kind ("ammo" | "health" | "armor") в точке at.
func spawn_supply(kind: String, at: Vector3) -> SupplyCrate:
	var c := SupplyCrate.make(kind, at)
	var parent: Node = _arena() if _arena() != null else get_parent()
	parent.add_child(c)
	supplies_spawned += 1
	return c


func _clear_supplies() -> void:
	for c in get_tree().get_nodes_in_group(SUPPLY_GROUP):
		(c as Node).queue_free()


## Боец d коснулся ящика kind: true — взял (ящик исчезает), false — не нужен (полный запас / полные жизни / полная броня). Бонус берётся
## всегда (время — заново). Оторваны конечности — любой ящик возвращает их (рука снова с оружием) и берётся, даже если своё не нужно.
func take_supply(d: Doll, kind: String) -> bool:
	if not is_instance_valid(d) or not d.alive or play_state != "play" or not Tuning.SQUAD_SUPPLY.has(kind):
		return false
	var def: Dictionary = Tuning.SQUAD_SUPPLY[kind]
	var limbs := _restore_limbs(d)
	var used := limbs
	match kind:
		"ammo":
			var g := gun_of(d)
			if g != null and g.weapon != "" and g.reserve < g.reserve_max:
				g.add_ammo(float(def["amount"]))
				used = true
		"health":
			if d.hp < d.max_hp - 0.5:
				d.hp = minf(d.hp + float(def["amount"]) * _hp_scale(), d.max_hp)
				hp_changed.emit(d, d.hp, d.max_hp)
				used = true
		"armor":
			if armor_of(d) < Tuning.SQUAD_ARMOR_MAX - 0.5:
				add_armor(d, float(def["amount"]))
				used = true
		_:
			if not boosts_active.has(d.player_index):
				boosts_active[d.player_index] = {}
			(boosts_active[d.player_index] as Dictionary)[kind] = float(def["seconds"])
			used = true
	if not used:
		return false
	supplies_taken[kind] = int(supplies_taken.get(kind, 0)) + 1
	supply_taken.emit(d, kind)
	if feel_enabled:
		_play("equip", -6.0 if _is_human(d) else -12.0, 1.0, d.centre_of_mass())
	return true


# --- захват флага ---

func is_ctf() -> bool:
	return mode == "ctf"


## Флаги у баз (захват флага) — на begin: старые убираются, новые ставятся домой; в перестрелке флагов нет.
func _setup_flags() -> void:
	for f in flags:
		if is_instance_valid(f):
			(f as Node).queue_free()
	flags.clear()
	if not is_ctf():
		return
	var a := _arena()
	for t in 2:
		var at: Vector3 = a.call("flag_point", t) if a != null and a.has_method("flag_point") else Vector3(30.0 * (-1.0 if t == 0 else 1.0), 3.7, 0.0)
		var f := SquadFlag.make(t, at)
		(a if a != null else get_parent()).add_child(f)
		flags.append(f)


## Флаг, который несёт d (чужой), или null.
func carried_flag(d: Doll) -> SquadFlag:
	for f in flags:
		if is_instance_valid(f) and (f as SquadFlag).state == "carried" and (f as SquadFlag).carrier == d:
			return f
	return null


## Флаг команды t (или null вне захвата).
func flag_of(t: int) -> SquadFlag:
	return flags[t] if t >= 0 and t < flags.size() and is_instance_valid(flags[t]) else null


## Касание флага бойцом: любая деталь ближе SQUAD_FLAG_PICK_M к точке флага.
func _touches(d: Doll, at: Vector3) -> bool:
	if d.centre_of_mass().distance_to(at) > 3.0:
		return false
	var r2 := Tuning.SQUAD_FLAG_PICK_M * Tuning.SQUAD_FLAG_PICK_M
	for p in d.parts.values():
		if is_instance_valid(p) and (p as Node3D).global_position.distance_squared_to(at) <= r2:
			return true
	return false


## Правила флагов за тик: дома — чужой касанием берёт; несут — несущий выбыл → флаг падает, донёс до своего флага (тот дома) —
## очко; лежит — свой касанием возвращает домой, чужой — снова берёт, время вышло — домой.
func _tick_flags(delta: float) -> void:
	if not is_ctf() or play_state != "play":
		return
	for t in flags.size():
		var f := flag_of(t)
		if f == null:
			continue
		match f.state:
			"carried":
				var c := f.carrier
				if c == null or not is_instance_valid(c) or not c.alive:
					f.drop(f.global_position)
					flag_event.emit(t, "dropped", c if is_instance_valid(c) else null)
					continue
				var own := flag_of(team_of(c))
				if own != null and own.state == "home" and _touches(c, own.home):
					_capture(c, f)
			"dropped":
				f.left -= delta
				if f.left <= 0.0:
					f.go_home()
					flag_event.emit(t, "returned", null)
					continue
				for d in alive_dolls():
					var dd := d as Doll
					if not _touches(dd, f.global_position):
						continue
					if team_of(dd) == t:
						f.go_home()
						add_xp(dd.player_index, Tuning.SQUAD_XP_PER_RETURN)
						flag_event.emit(t, "returned", dd)
					else:
						f.carry(dd)
						flag_event.emit(t, "taken", dd)
					break
			_:
				for d in team_alive(1 - t):
					if _touches(d as Doll, f.home) and carried_flag(d as Doll) == null:
						f.carry(d as Doll)
						flag_event.emit(t, "taken", d as Doll)
						break


## Доставка: очко команде несущего, опыт, флаг соперника — домой; до score_to_win — конец.
func _capture(c: Doll, f: SquadFlag) -> void:
	var t := team_of(c)
	f.go_home()
	score[t] = int(score[t]) + 1
	_tally(c.player_index, "captures", 1)
	add_xp(c.player_index, Tuning.SQUAD_XP_PER_CAPTURE)
	frags.append({"t": snappedf(fight_time, 0.01), "capture": c.player_index, "team": t, "score": score.duplicate()})
	score_changed.emit(score.duplicate())
	flag_event.emit(f.team, "captured", c)
	if feel_enabled:
		_play("equip", -2.0, 0.8, c.centre_of_mass())
	if int(score[t]) >= score_to_win:
		call_deferred("_finish", "score")


# --- конечности ---

## Вернуть оторванные конечности бойца (Doll.reattach_part — со свежим запасом суставов; вложенные — от корня: сначала
## предплечье, потом кисть). Рука с оружием снова держит его: ствол — сам (ArmAssist заново берёт кисть), рукопашное — rearm.
## true — что-то вернулось.
func _restore_limbs(d: Doll) -> bool:
	if not is_instance_valid(d) or not d.alive:
		return false
	var any := false
	for _i in 6:
		var changed := false
		for root in d.detached_parts():
			if d.reattach_part(root as RigidBody3D):
				changed = true
				any = true
				limbs_restored += 1
		if not changed:
			break
	if any:
		var ml := melee_of(d)
		if ml != null:
			ml.rearm.call_deferred()   # ArmAssist перепривязывает кисть на part_reattached — оружие варим после
	return any


## Рука с оружием на месте (прочность суставов могла её оторвать).
func has_weapon_arm(d: Doll) -> bool:
	if not is_instance_valid(d):
		return false
	var g := gun_of(d)
	var a := g.arm() if g != null else null
	return a != null and a.part != null and is_instance_valid(a.part) and d.parts.has(a.part_name)


# --- осанка ---

## Корпус к вертикали (Tuning.SQUAD_UPRIGHT; тот же PD, что Doll._tick_posture с ControlFeel upright): иначе рука с оружием не
## достаёт целей выше головы. Молчит у мёртвых, без управления, в стане, раскрутке и полёте после удара.
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
	if not is_ctf():
		score[other] = int(score[other]) + 1   # в захвате флага очки — только за доставку
	var cf := carried_flag(victim)
	if cf != null:
		cf.drop(victim.centre_of_mass())
		flag_event.emit(cf.team, "dropped", victim)
	boosts_active.erase(victim.player_index)
	_tally(victim.player_index, "deaths", 1)
	if killer != null:
		_tally(killer.player_index, "kills", 1)
		add_xp(killer.player_index, Tuning.SQUAD_XP_PER_FRAG)
	frags.append({"t": snappedf(fight_time, 0.01), "victim": victim.player_index, "killer": killer.player_index if killer != null else -1,
		"team": other, "kind": String(record.get("kind", "")), "weapon": weapon_name(killer), "score": score.duplicate()})
	score_changed.emit(score.duplicate())
	frag.emit(killer, victim, other)
	if feel and (_is_human(victim) or _is_human(killer)):
		_camera_fx(25.0, record.get("position", victim.centre_of_mass()))
		if FxPreset.time_fx():
			_time_effect(Tuning.KO_SLOWMO_SCALE, Tuning.SQUAD_KO_SLOWMO_S)
	if not is_ctf() and int(score[other]) >= score_to_win:
		call_deferred("_finish", "score")
		return
	_respawns.append([victim, respawn_s])
	respawn_queued.emit(victim, respawn_s)


static func _is_human(d: Object) -> bool:
	return d != null and is_instance_valid(d) and d is Doll and not (d as Doll).external_input


func _tally(pi: int, key: String, v: float) -> void:
	if not tally.has(pi):
		tally[pi] = _fresh_tally()
	var t: Dictionary = tally[pi]
	t[key] = (t[key] + int(v)) if t[key] is int else (float(t[key]) + v)


## Урон по соперникам: в таблицу итогов и в опыт.
func _on_hit_tally(victim: Doll, attacker: Node, damage: float, _kind: String, _pos: Vector3) -> void:
	if not (attacker is Doll) or not is_instance_valid(attacker) or attacker == victim or team_of(attacker) == team_of(victim):
		return
	var pi := (attacker as Doll).player_index
	_tally(pi, "damage", damage)
	add_xp(pi, damage * Tuning.SQUAD_XP_PER_DAMAGE)


## Название оружия куклы для ленты (огнестрел, рукопашное, «руки») — ключ перевода.
func weapon_name(d: Object) -> String:
	if d == null or not is_instance_valid(d):
		return ""
	var g := gun_of(d)
	if g != null and g.weapon != "":
		return String(Tuning.SQUAD_WEAPONS[g.weapon]["title"])
	var ml := melee_of(d)
	if ml != null and ml.weapon_id != "":
		return String((Tuning.SQUAD_MELEE.get(ml.weapon_id, {}) as Dictionary).get("title", ""))
	return "РУКИ"


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
			_switch_class((d as Doll).player_index)   # новый класс — с возрождения
			var nd := respawn_doll(d as Doll)
			nd.control_enabled = true
			nd.grace_until = maxf(nd.grace_until, Tuning.SQUAD_SPAWN_SHIELD_S)   # _time новой куклы ≈ 0 (запас и броня класса — register)
			doll_respawned.emit(nd)


# --- итоги ---

## Итоги: базовые (места по HP, медали) + счёт команд, победившая команда, фраги кукол. HUD стычки показывает свою таблицу.
func build_results(reason: String = "timeout") -> Dictionary:
	var r := super.build_results(reason)
	r["score"] = score.duplicate()
	r["winner_team"] = -1 if int(score[0]) == int(score[1]) else (0 if int(score[0]) > int(score[1]) else 1)
	r["draw"] = int(score[0]) == int(score[1])
	r["tally"] = tally.duplicate(true)
	r["frags"] = frags.duplicate(true)
	r["loadouts"] = loadouts.duplicate(true)
	r["mode"] = mode
	return r
