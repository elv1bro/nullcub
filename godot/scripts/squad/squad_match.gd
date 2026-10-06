## Матч «Стычка 3 на 3» (docs/plan-demo/SQUAD.md; автор 05.10: «карта побольше, стычки 3 на 3 как в шутерах»; второй заход 05.10:
## пистолет у всех, ветка из трёх развитий, патроны и перезарядка, ящики с патронами, жизнями и бронёй, «слишком трясётся»).
## Наследник Match: от него — регистрация кукол (DollCombat), удары телом и их эффекты, надписи, отсчёт. Своё — команды и счёт, как в
## командном бою шутеров:
##   • команда — чётность player_index (team_of): 0 — синие (P1 и боты 2, 4), 1 — красные (боты 1, 3, 5). Doll.team "squad_N",
##     team_damage_mult 0 — свои не ранят и не оглушают, толкают полностью; группы squad_0 / squad_1 (цели и разнос ботов, камера);
##     рубашка и обводка — цвет команды (Tuning.SQUAD_COLORS);
##   • выбыл (пуля, удар, падение, взрыв) — очко команде соперника; фраг — тому, кто добил (если он из другой команды); кукла
##     возвращается на свою точку базы через SQUAD_RESPAWN_S, первые SQUAD_SPAWN_SHIELD_S урон не проходит;
##   • конец: SQUAD_SCORE_TO_WIN очков, или время SQUAD_TIME_LIMIT_S — ведущий победил, равный счёт — ничья. Last man standing базового
##     Match выключен (_check_over), Sudden Death тоже;
##   • оружие — SquadGun (стрелки) или SquadMelee (громила) на кукле; урон пули идёт через bullet_hit, удар телом и оружием — через
##     свой on_hit: без тряски и толчков камеры, стоп-кадров и замедлений (с ДРАЙВОМ каждая пуля и каждое касание дёргали кадр и
##     время — «слишком трясётся… и не прерывается»), только искры, звук и сигнал hit; камеру чуть трясёт сильный удар с человеком;
##   • классы и опыт (loadout по player_index: класс, следующий класс, опыт, уровень; сбрасываются на begin): опыт — за урон по
##     соперникам и за фраг (SQUAD_XP_*), уровень растёт сам по SQUAD_XP_LEVELS и сразу открывает, что записано в классе
##     (SQUAD_CLASSES: оружие, рукопашное оружие, усиление) — сигнал leveled для HUD «что ты теперь можешь»; класс меняется
##     set_class (на отсчёте — сразу, в бою — с возрождения), опыт и уровень остаются; запас HP и броня при возврате — по классу;
##   • броня (armor по player_index, на возрождении — 0): пока она есть, Doll.incoming_mult = SQUAD_ARMOR_MULT, прошедший урон снимается
##     и с брони; ящики снабжения (SupplyCrate) — раз в SQUAD_SUPPLY_EVERY_S на свободной точке карты, take_supply решает, нужен ли;
##   • KO: замедление короче (SQUAD_KO_SLOWMO_S) и только когда в нокауте участвует человек; крит-кино выключено;
##   • корпус бойцов держится вертикально (SQUAD_UPRIGHT, _posture) — иначе рука с оружием не достаёт целей над головой.
## Сигналы для HUD (scenes/squad/squad_hud.gd): score_changed, frag, respawn_queued, doll_respawned, xp_changed, leveled,
## class_changed, bullet_landed, melee_landed, supply_taken + унаследованные. tally — счёт кукол по player_index: {kills, deaths, damage}; frags — журнал проб.
class_name SquadMatch
extends Match

signal score_changed(score: Array)
signal frag(killer: Doll, victim: Doll, team: int)
signal respawn_queued(victim: Doll, seconds: float)
signal doll_respawned(doll: Doll)
signal xp_changed(player_index: int, xp: float, level: int)
signal leveled(player_index: int, level: int, unlock: Dictionary)
signal class_changed(player_index: int, class_id: String, pending: bool)
signal bullet_landed(victim: Doll, shooter: Doll, damage: float, position: Vector3)
signal melee_landed(victim: Doll, attacker: Doll, damage: float, position: Vector3)
signal supply_taken(doll: Doll, kind: String)

const GROUP_PREFIX := "squad_"
const SUPPLY_GROUP := "squad_supply"

@export var score_to_win: int = Tuning.SQUAD_SCORE_TO_WIN
@export var respawn_s: float = Tuning.SQUAD_RESPAWN_S
## Ящики снабжения (пробы правил выключают, чтобы не мешали счёту).
@export var supplies := true

var score := [0, 0]
## idle | countdown | play | over
var play_state := "idle"
var frags: Array = []
var tally: Dictionary = {}          # player_index → {kills, deaths, damage}
var winner_team := -1
## Кукла «я» для HUD и камеры, когда людей нет (пробы и снимки: за P1 играет бот): player_index или −1.
var focus_index := -1
## player_index → {class, next_class, xp, level}
var loadouts: Dictionary = {}
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
		tally[d.player_index] = {"kills": 0, "deaths": 0, "damage": 0.0}
	_apply_class_stats(d)
	d.damaged.connect(_on_armor_damaged.bind(d))


## Цвет команды: рубашка (Doll._recolor поверх цвета игрока по player_index — их всего 4) и обводка (раньше HitJuice: он красил бы
## обводку цветом игрока, а P5 и P6 — жёлтые).
func _dress(d: Doll) -> void:
	if not is_instance_valid(d):
		return
	var c := team_colour(team_of(d))
	d._recolor(d, Doll.SHIRT_MATERIAL, c)
	DollOutline.ensure(d, c)


# --- фазы ---

func begin() -> void:
	score = [0, 0]
	frags.clear()
	winner_team = -1
	_respawns.clear()
	for k in tally.keys():
		tally[k] = {"kills": 0, "deaths": 0, "damage": 0.0}
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
		_apply_class_stats(d as Doll)
		_equip(d as Doll)
		xp_changed.emit((d as Doll).player_index, 0.0, 1)
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
	if not feel_enabled:
		return
	_play("hit_m" if damage >= 10.0 else "hit_l", -8.0 + minf(damage, 30.0) * 0.2, randf_range(0.95, 1.1), position)
	if damage >= Tuning.SQUAD_MELEE_SHAKE_MIN and (_is_human(victim) or _is_human(attacker)):
		melee_shakes += 1
		_camera_fx(minf(damage, 40.0) * Tuning.SQUAD_MELEE_SHAKE_MULT, position)


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
	var c := cls if Tuning.SQUAD_CLASSES.has(cls) else "assault"
	return {"class": c, "next_class": c, "xp": 0.0, "level": 1}


## Класс, опыт и уровень куклы player_index (новой — класс бота по SQUAD_BOT_CLASSES, у P1 — штурмовик).
func loadout(pi: int) -> Dictionary:
	if not loadouts.has(pi):
		loadouts[pi] = _fresh_loadout(String(Tuning.SQUAD_BOT_CLASSES.get(pi, "assault")))
	return loadouts[pi]


## Что открыто у класса cls на уровне level: {weapon (огнестрел, "" — нет), melee (рукопашное, "" — нет), perks {id: раз}}.
static func kit_of(cls: String, level: int) -> Dictionary:
	var c: Dictionary = Tuning.SQUAD_CLASSES.get(cls, Tuning.SQUAD_CLASSES["assault"])
	var out := {"weapon": "", "melee": "", "perks": {}}
	var levels: Array = c["levels"]
	for i in range(mini(level, levels.size())):
		var u: Dictionary = levels[i]
		if u.has("weapon"):
			out["weapon"] = String(u["weapon"])
		if u.has("melee"):
			out["melee"] = String(u["melee"])
		if u.has("perk"):
			var perks: Dictionary = out["perks"]
			perks[String(u["perk"])] = int(perks.get(String(u["perk"]), 0)) + 1
	return out


## Набор куклы сейчас (по её классу и уровню).
func kit(pi: int) -> Dictionary:
	var lo := loadout(pi)
	return kit_of(String(lo["class"]), int(lo["level"]))


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


## Опыт: уровень растёт сам; каждый новый уровень — открытие класса (leveled) и сразу у живого бойца.
func add_xp(pi: int, amount: float) -> void:
	if amount <= 0.0:
		return
	var lo := loadout(pi)
	lo["xp"] = float(lo["xp"]) + amount
	var lv := level_for(float(lo["xp"]))
	while int(lo["level"]) < lv:
		lo["level"] = int(lo["level"]) + 1
		var c: Dictionary = Tuning.SQUAD_CLASSES[String(lo["class"])]
		var levels: Array = c["levels"]
		var unlock: Dictionary = levels[int(lo["level"]) - 1] if int(lo["level"]) - 1 < levels.size() else {}
		var d := _doll_of_index(pi)
		if d != null and d.alive:
			_equip(d, true)
			if String(unlock.get("perk", "")) == "tough":
				add_armor(d, float(Tuning.SQUAD_PERKS["tough"]["armor"]))
		leveled.emit(pi, int(lo["level"]), unlock)
	xp_changed.emit(pi, float(lo["xp"]), int(lo["level"]))


## Сменить класс: на отсчёте — сразу (оружие, запас HP, броня), в бою — с возрождения (живому — «сменится при возврате»).
func set_class(pi: int, cls: String) -> bool:
	if not Tuning.SQUAD_CLASSES.has(cls):
		return false
	var lo := loadout(pi)
	lo["next_class"] = cls
	var d := _doll_of_index(pi)
	var now := play_state != "play" or d == null
	if now:
		lo["class"] = cls
		if d != null:
			_apply_class_stats(d)
			_equip(d)
	class_changed.emit(pi, cls, not now)
	return true


## Запас HP класса (с ДРАЙВОМ — в той же пропорции, что у обычной куклы) и броня возврата (класс + усиления «броня»).
func _apply_class_stats(d: Doll) -> void:
	var lo := loadout(d.player_index)
	var c: Dictionary = Tuning.SQUAD_CLASSES[String(lo["class"])]
	var hp := float(c["hp"]) * (Tuning.DRIVE_MAX_HP / Tuning.MAX_HP if Drive.on else 1.0)
	d.max_hp = hp
	d.hp = hp
	armor[d.player_index] = 0.0
	d.incoming_mult = 1.0
	var tough := int((kit(d.player_index)["perks"] as Dictionary).get("tough", 0))
	var a := float(c["armor"]) + float(Tuning.SQUAD_PERKS["tough"]["armor"]) * tough
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
		var lunges := int((k["perks"] as Dictionary).get("lunge", 0))
		ml.equip(String(k["melee"]), pow(float(Tuning.SQUAD_PERKS["lunge"]["lunge"]), lunges))


func _doll_of_index(pi: int) -> Doll:
	for d in dolls():
		if (d as Doll).player_index == pi:
			return d
	return null


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
	var total := 0.0
	for k in Tuning.SQUAD_SUPPLY:
		total += float(Tuning.SQUAD_SUPPLY[k]["weight"])
	var r := _rng.randf() * total
	for k in Tuning.SQUAD_SUPPLY:
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


## Боец d коснулся ящика kind: true — взял (ящик исчезает), false — не нужен (полный запас / полные жизни / полная броня).
func take_supply(d: Doll, kind: String) -> bool:
	if not is_instance_valid(d) or not d.alive or play_state != "play":
		return false
	var amount := float((Tuning.SQUAD_SUPPLY[kind] as Dictionary)["amount"])
	match kind:
		"ammo":
			var g := gun_of(d)
			if g == null or g.weapon == "" or g.reserve >= g.reserve_max:
				return false
			g.add_ammo(amount)
		"health":
			if d.hp >= d.max_hp - 0.5:
				return false
			d.hp = minf(d.hp + amount, d.max_hp)
			hp_changed.emit(d, d.hp, d.max_hp)
		"armor":
			if armor_of(d) >= Tuning.SQUAD_ARMOR_MAX - 0.5:
				return false
			add_armor(d, amount)
		_:
			return false
	supplies_taken[kind] = int(supplies_taken.get(kind, 0)) + 1
	supply_taken.emit(d, kind)
	if feel_enabled:
		_play("equip", -6.0 if _is_human(d) else -12.0, 1.0, d.centre_of_mass())
	return true


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
	score[other] = int(score[other]) + 1
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


## Урон по соперникам: в таблицу итогов и в опыт.
func _on_hit_tally(victim: Doll, attacker: Node, damage: float, _kind: String, _pos: Vector3) -> void:
	if not (attacker is Doll) or not is_instance_valid(attacker) or attacker == victim or team_of(attacker) == team_of(victim):
		return
	var pi := (attacker as Doll).player_index
	_tally(pi, "damage", damage)
	add_xp(pi, damage * Tuning.SQUAD_XP_PER_DAMAGE)


## Название оружия куклы для ленты (огнестрел, рукопашное, «руки»).
func weapon_name(d: Object) -> String:
	if d == null or not is_instance_valid(d):
		return ""
	var g := gun_of(d)
	if g != null and g.weapon != "":
		return String(Tuning.SQUAD_WEAPONS[g.weapon]["title"])
	var ml := melee_of(d)
	if ml != null and ml.weapon_id != "":
		return String(Tuning.SQUAD_MELEE.get(ml.weapon_id, ""))
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
			var lo := loadout((d as Doll).player_index)
			lo["class"] = String(lo["next_class"])   # новый класс — с возрождения
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
	return r
