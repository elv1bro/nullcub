## Матч «Королевская битва» (docs/plan-demo/ROYALE.md; MODES_PACK.md §2; автор 06.10: «королевская битва тоже можно»; «можно оружие
## из ящиков разное + бонусы типа жизни и броню находить»). Наследник SquadMatch: от стычки — пули (bullet_hit без тряски), удар без
## тряски (on_hit), броня, ящики и бонусы (take_supply), прочность суставов × SQUAD_JOINT_HP_MULT и возврат конечностей ящиком, корпус
## вертикально, звук выстрелов. Своё:
##   • каждый сам за себя: Doll.team "royale_<индекс>" (все друг другу враги, урон полный), группа FIGHTERS_GROUP (цели ботов), рубашка
##     и обводка — цвет бойца (Tuning.ROYALE_COLORS), вид — «Человек» без вида класса; колорит ствола и трассеров — colour_of
##     (крючок SquadGun);
##   • классов нет: у всех ROYALE_HP, без брони и без оружия (kit — оружие, взятое из ящика; опыта и уровней нет — add_xp молчит);
##   • ящики: на старте Tuning.ROYALE_CRATES по точкам карты (оружие — через точку по ширине карты, остальное — в промежутках), редко —
##     новый внутри зоны (ROYALE_SUPPLY_*); ящик с оружием (RoyaleCrate) — take_crate: без оружия — берёшь, то же — как патроны, ранг выше
##     (или у твоего нет патронов) — меняешь, твоё остаётся ящиком; выбыл с оружием — оно остаётся ящиком (ROYALE_DROP_ON_KO);
##   • зона (RoyaleZone, ребёнок): стадии с FIGHT!; снаружи стен — урон зоны раз в ROYALE_ZONE_TICK_S (броня не гасит и не тратится);
##     счёт времени снаружи у каждого (outside_s / outside_max — пробы: бот не стоит снаружи);
##   • без возрождения: выбыл — место = живых + 1 (eliminated: кто, кем, место, сколько осталось, причина); последний живой — победа
##     (_check_over); места в итогах — Match.build_results (выбывшие в одном тике делят место), places по player_index;
##   • точки появления — Tuning.ROYALE_SPAWN, перемешаны на каждый бой (spawn_point_for); камера зума — оружие (ROYALE_WEAPONS.zoom) × бонус
##     «обзор».
## Сигналы для HUD (scenes/royale/royale_hud.gd): eliminated, weapon_taken, zone_stage + унаследованные (supply_taken, bullet_landed …).
class_name RoyaleMatch
extends SquadMatch

signal eliminated(victim: Doll, killer: Doll, place: int, left: int, cause: String)
signal weapon_taken(doll: Doll, weapon_id: String, from_id: String)
signal zone_stage(stage: int, shrinking: bool)

const FIGHTERS_GROUP := "royale_fighters"
## Метки навигации ботов на Полигоне (RaceNav — граф видимости): те же точки в открытом воздухе, что у «Гонки» на этой карте
## (scenes/playground_race.tscn, узел RaceMarks; связность графа проверяет race_probe). Без них бот снизу не долетал до ящиков над
## плитами и башней (прямой путь закрыт, поиска пути нет).
const NAV_MARKS := [Vector2(0.0, 1.9), Vector2(0.0, 8.0), Vector2(-6.0, 2.6), Vector2(6.0, 2.6), Vector2(-8.0, 10.5), Vector2(8.0, 10.5),
	Vector2(-11.0, 3.4), Vector2(11.0, 3.4), Vector2(-16.0, 2.1), Vector2(16.0, 2.1), Vector2(-16.0, 6.3), Vector2(16.0, 6.3),
	Vector2(-21.0, 3.9), Vector2(21.0, 3.9), Vector2(-23.0, 8.5), Vector2(23.0, 8.5), Vector2(-24.5, 1.7), Vector2(24.5, 1.7),
	Vector2(-28.0, 4.5), Vector2(28.0, 4.5)]

## Зерно случайностей боя (точки появления, ящики, окно зоны); 0 — случайное.
@export var rng_seed := 0

var zone: RoyaleZone
## player_index → место (1 — победитель): выбывшие — сразу, живые — в итогах.
var places: Dictionary = {}
var winner_index := -1
## Зона: player_index → всего с снаружи / текущая серия / длиннейшая серия / урон зоной.
var outside_s: Dictionary = {}
var outside_run: Dictionary = {}
var outside_max: Dictionary = {}
var zone_damage: Dictionary = {}
## Счётчики для проб и итогов.
var crates_spawned := 0
var crates_resupplied := 0
var drops := 0
var weapons_taken := 0
var weapon_swaps := 0
var _nav: RaceNav = null
var _weapons: Dictionary = {}       # player_index → id оружия из ящика ("" — нет)
var _slots: Array = []              # player_index → номер точки Tuning.ROYALE_SPAWN
var _zone_acc := 0.0
var _resupply_t := 0.0
var _zone_hitting := false


func _ready() -> void:
	super._ready()
	time_limit_s = Tuning.ROYALE_TIME_LIMIT_S
	hard_timeout_s = Tuning.ROYALE_TIME_LIMIT_S
	supplies = false            # ящики стычки «раз в 6 с» — нет: свои (старт + редко внутри зоны)
	score_to_win = 1 << 30
	respawn_s = -1.0
	_rng.seed = rng_seed if rng_seed != 0 else int(Time.get_ticks_usec())
	zone = RoyaleZone.new()
	zone.name = "Zone"
	add_child(zone)
	zone.stage_changed.connect(func(st: int, sh: bool) -> void: zone_stage.emit(st, sh))
	_shuffle_slots()


# --- бойцы ---

static func colour_for(pi: int) -> Color:
	return Tuning.ROYALE_COLORS[posmod(pi, Tuning.ROYALE_COLORS.size())]


## Цвет бойца (крючок SquadGun: накладки ствола, ореол трассера).
func colour_of(d: Object) -> Color:
	if d == null or not is_instance_valid(d) or not (d is Doll):
		return Color.WHITE
	return colour_for((d as Doll).player_index)


## Имя бойца для ленты и меток: P1…P8.
static func fighter_name(d: Object) -> String:
	if d == null or not is_instance_valid(d) or not (d is Doll):
		return ""
	return "P%d" % ((d as Doll).player_index + 1)


## Ранг оружия (Tuning.ROYALE_WEAPONS.tier); нет оружия — 0.
static func tier(id: String) -> int:
	return int((Tuning.ROYALE_WEAPONS.get(id, {}) as Dictionary).get("tier", 0)) if id != "" else 0


func register(d: Doll) -> void:
	var fresh := not _order.has(d)
	super.register(d)
	if not fresh:
		return
	d.team = "royale_%d" % d.player_index
	d.team_damage_mult = 1.0
	for g in [team_group(0), team_group(1)]:
		if d.is_in_group(g):
			d.remove_from_group(g)
	d.add_to_group(FIGHTERS_GROUP)


## Цвет бойца: рубашка и обводка (вида класса нет — «Человек»).
func _dress(d: Doll) -> void:
	if not is_instance_valid(d):
		return
	var c := colour_for(d.player_index)
	d._recolor(d, Doll.SHIRT_MATERIAL, c)
	DollOutline.ensure(d, c)
	_scale_joints(d)


func _look(_d: Doll, _fresh := false) -> void:
	pass


## Класс стычки для общего кода (bullet_hit читает bullet_mult класса места: у громилы пули × 0.5 — места 4 и 5 получали бы половину
## урона): у всех один — без множителей (пули × 1, обзор × 1). Числа бойца — _apply_class_stats.
const NEUTRAL_CLASS := "raider"


func loadout(pi: int) -> Dictionary:
	if not loadouts.has(pi):
		loadouts[pi] = _fresh_loadout(NEUTRAL_CLASS)
	return loadouts[pi]


## Набор: только оружие из ящика (без рукопашного и усилений).
func kit(pi: int) -> Dictionary:
	return {"weapon": String(_weapons.get(pi, "")), "melee": "", "perks": {}}


func weapon_of(d: Doll) -> String:
	return String(_weapons.get(d.player_index, "")) if is_instance_valid(d) else ""


## Один класс на всех: запас ROYALE_HP (с ДРАЙВОМ — в той же пропорции), без брони.
func _apply_class_stats(d: Doll) -> void:
	var hp := Tuning.ROYALE_HP * _hp_scale()
	d.max_hp = hp
	d.hp = hp
	armor[d.player_index] = 0.0
	d.incoming_mult = 1.0
	hp_changed.emit(d, d.hp, d.max_hp)


## Опыта и уровней в битве нет.
func add_xp(_pi: int, _amount: float) -> void:
	pass


## Урон пули — как в стычке (броня тела и стычки, без тряски), × Tuning.ROYALE_BULLET_MULT.
func bullet_hit(victim: Doll, shooter: Doll, amount: float, part: String, pos: Vector3, normal: Vector3, weapon_id: String) -> float:
	return super.bullet_hit(victim, shooter, amount * Tuning.ROYALE_BULLET_MULT, part, pos, normal, weapon_id)


## Урон по любому другому бойцу — в таблицу итогов.
func _on_hit_tally(victim: Doll, attacker: Node, damage: float, _kind: String, _pos: Vector3) -> void:
	if not (attacker is Doll) or not is_instance_valid(attacker) or attacker == victim:
		return
	_tally((attacker as Doll).player_index, "damage", damage)


## Зум камеры игрока: оружие (ROYALE_WEAPONS.zoom — винтовки дальше) × бонус «обзор».
func view_zoom(d: Doll) -> float:
	if d == null or not is_instance_valid(d):
		return 1.0
	var g := gun_of(d)
	var z := float((Tuning.ROYALE_WEAPONS.get(g.weapon, {}) as Dictionary).get("zoom", 1.0)) if g != null and g.weapon != "" else 1.0
	return z * boost_mult(d, "zoom")


# --- точки появления ---

func _shuffle_slots() -> void:
	_slots.clear()
	for i in Tuning.ROYALE_SPAWN.size():
		_slots.append(i)
	for i in range(_slots.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t: Variant = _slots[i]
		_slots[i] = _slots[j]
		_slots[j] = t


## Точка появления бойца pi в этом бою.
func slot_point(pi: int) -> Vector3:
	if _slots.is_empty():
		_shuffle_slots()
	var p: Vector2 = Tuning.ROYALE_SPAWN[int(_slots[posmod(pi, _slots.size())])]
	return Vector3(p.x, p.y, 0.0)


func spawn_point_for(d: Doll) -> Vector3:
	return slot_point(d.player_index)


## Заново (R): новые точки появления, потом как Match (все куклы заново, begin).
func restart() -> void:
	_shuffle_slots()
	super.restart()


# --- фазы ---

func begin() -> void:
	_weapons.clear()
	places.clear()
	winner_index = -1
	outside_s.clear()
	outside_run.clear()
	outside_max.clear()
	zone_damage.clear()
	crates_spawned = 0
	crates_resupplied = 0
	drops = 0
	weapons_taken = 0
	weapon_swaps = 0
	_zone_acc = 0.0
	_resupply_t = 0.0
	super.begin()
	var b := _map_bounds()
	zone.setup(b.position.x, b.end.x, _rng)
	_spawn_crates()


func _start_fight() -> void:
	super._start_fight()
	zone.start()


func _finish(reason: String) -> void:
	if phase == Phase.OVER:
		return
	zone.stop()
	super._finish(reason)


## Граф видимости по NAV_MARKS для ботов — строится при первом запросе (в тике физики: нужна direct_space_state).
func nav() -> RaceNav:
	if _nav == null:
		var a := _arena() as Node3D
		var space := a.get_world_3d().direct_space_state if a != null and a.is_inside_tree() else null
		if space == null:
			return null
		var pts: Array[Vector3] = []
		for p in NAV_MARKS:
			pts.append(Vector3((p as Vector2).x, (p as Vector2).y, 0.0))
		_nav = RaceNav.new()
		_nav.build(space, pts)
	return _nav


func _map_bounds() -> AABB:
	var a := _arena()
	if a != null and a.has_method("bounds"):
		return a.call("bounds")
	return AABB(Vector3(-32.0, -2.0, -1.0), Vector3(64.0, 18.0, 2.0))


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if phase != Phase.FIGHT or play_state != "play":
		return
	zone.tick(delta)
	_tick_zone(delta)
	_tick_resupply(delta)


# --- зона ---

## Время снаружи (каждый тик) и урон зоны (порциями раз в ROYALE_ZONE_TICK_S).
func _tick_zone(delta: float) -> void:
	_zone_acc += delta
	var hit_now := _zone_acc >= Tuning.ROYALE_ZONE_TICK_S
	var step := _zone_acc
	if hit_now:
		_zone_acc = 0.0
	var dps := zone.dps()
	for d in alive_dolls():
		var dd := d as Doll
		var pi := dd.player_index
		if zone.inside(dd.centre_of_mass().x):
			outside_run[pi] = 0.0
			continue
		outside_s[pi] = float(outside_s.get(pi, 0.0)) + delta
		outside_run[pi] = float(outside_run.get(pi, 0.0)) + delta
		outside_max[pi] = maxf(float(outside_max.get(pi, 0.0)), float(outside_run[pi]))
		if hit_now and dps > 0.0:
			zone_hit(dd, dps * step)


## Урон зоны amount HP: броня его не гасит (incoming_mult на время — 1) и не тратится (_on_armor_damaged молчит); выбыл — причина
## «zone» (запись удара — hit_meta.zone). Возвращает снятое.
func zone_hit(d: Doll, amount: float) -> float:
	if not is_instance_valid(d) or not d.can_take_damage() or amount <= 0.0:
		return 0.0
	var hp0 := d.hp
	var m := d.incoming_mult
	d.incoming_mult = 1.0
	_zone_hitting = true
	d.hit_meta = {"zone": true}
	d.take_damage(amount, null, "Torso", d.centre_of_mass(), Vector3.UP, "environment")
	_zone_hitting = false
	if not is_instance_valid(d):
		return amount
	if d.alive:
		d.incoming_mult = m
	var dealt := hp0 - d.hp
	zone_damage[d.player_index] = float(zone_damage.get(d.player_index, 0.0)) + dealt
	return dealt


func _on_armor_damaged(amount: float, attacker: Node, part: String, pos: Vector3, kind: String, d: Doll) -> void:
	if _zone_hitting:
		return
	super._on_armor_damaged(amount, attacker, part, pos, kind, d)


# --- ящики ---

## Ящики на старте: оружие — на точки через одну по ширине карты (у каждого кусочка карты — ствол), остальные виды — на промежутки.
func _spawn_crates() -> void:
	var a := _arena()
	if a == null or not a.has_method("supply_points"):
		return
	var pts: Array = a.call("supply_points")
	pts.sort_custom(func(p: Vector3, q: Vector3) -> bool: return p.x < q.x)
	var n_w := int(Tuning.ROYALE_CRATES.get("weapon", 0))
	var w_at: Array = []
	if n_w > 0:
		for i in n_w:
			var k := int(round(float(i) * float(pts.size() - 1) / float(maxi(n_w - 1, 1))))
			if not w_at.has(k):
				w_at.append(k)
	var rest: Array = []
	for i in pts.size():
		if not w_at.has(i):
			rest.append(pts[i])
	for k in w_at:
		spawn_crate("weapon", pts[k])
	var kinds: Array = []
	for kind in Tuning.ROYALE_CRATES:
		if String(kind) != "weapon":
			for _i in int(Tuning.ROYALE_CRATES[kind]):
				kinds.append(String(kind))
	_shuffle(rest)
	for i in mini(kinds.size(), rest.size()):
		spawn_crate(String(kinds[i]), rest[i])


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t


## Ящик вида kind ("weapon" — случайное оружие по весам, "boost" — случайный бонус стычки, иначе вид стычки) в точке at.
func spawn_crate(kind: String, at: Vector3) -> RoyaleCrate:
	var c: RoyaleCrate
	match kind:
		"weapon":
			c = RoyaleCrate.make_weapon(_pick_weapon(), at)
		"boost":
			c = RoyaleCrate.make_kind(String(Tuning.SQUAD_BOOSTS[_rng.randi_range(0, Tuning.SQUAD_BOOSTS.size() - 1)]), at)
		_:
			c = RoyaleCrate.make_kind(kind, at)
	_add_crate(c)
	return c


func spawn_weapon_crate(id: String, at: Vector3, m := -1, r := -1) -> RoyaleCrate:
	var c := RoyaleCrate.make_weapon(id, at, m, r)
	_add_crate(c)
	return c


func _add_crate(c: RoyaleCrate) -> void:
	var parent: Node = _arena() if _arena() != null else get_parent()
	parent.add_child(c)
	crates_spawned += 1


func _pick_weapon() -> String:
	var total := 0.0
	for id in Tuning.ROYALE_WEAPONS:
		total += float(Tuning.ROYALE_WEAPONS[id]["weight"])
	var r := _rng.randf() * total
	for id in Tuning.ROYALE_WEAPONS:
		r -= float(Tuning.ROYALE_WEAPONS[id]["weight"])
		if r <= 0.0:
			return String(id)
	return Tuning.SQUAD_START_WEAPON


## Редкий новый ящик (ROYALE_SUPPLY_*): на свободной точке внутри стен, к которым идёт зона.
func _tick_resupply(delta: float) -> void:
	if Tuning.ROYALE_SUPPLY_EVERY_S <= 0.0:
		return
	_resupply_t += delta
	if _resupply_t < Tuning.ROYALE_SUPPLY_EVERY_S:
		return
	_resupply_t = 0.0
	var live := get_tree().get_nodes_in_group(SUPPLY_GROUP)
	if live.size() >= Tuning.ROYALE_SUPPLY_MAX:
		return
	var a := _arena()
	if a == null or not a.has_method("supply_points"):
		return
	var e := zone.next_edges()
	var free: Array = []
	for p in a.call("supply_points"):
		var pv := p as Vector3
		if pv.x < e.x + 1.0 or pv.x > e.y - 1.0:
			continue
		var taken := false
		for c in live:
			if (c as Node3D).global_position.distance_to(pv) < 1.5:
				taken = true
		if not taken:
			free.append(pv)
	if free.is_empty():
		return
	var total := 0.0
	for k in Tuning.ROYALE_SUPPLY_KINDS:
		total += float(Tuning.ROYALE_SUPPLY_KINDS[k])
	var r := _rng.randf() * total
	var kind := "ammo"
	for k in Tuning.ROYALE_SUPPLY_KINDS:
		r -= float(Tuning.ROYALE_SUPPLY_KINDS[k])
		if r <= 0.0:
			kind = String(k)
			break
	spawn_crate(kind, free[_rng.randi_range(0, free.size() - 1)])
	crates_resupplied += 1


## Боец d коснулся ящика c: true — взял (ящик исчезает). Не оружие — как в стычке (take_supply: патроны, жизни, броня, бонус, возврат
## конечностей). Оружие: без своего — берёшь; то же — патроны из ящика в запас; ранг выше (или у твоего нет патронов совсем) — меняешь,
## а твоё (с его патронами) остаётся ящиком на этом месте; иначе ящик не тратится.
func take_crate(d: Doll, c: RoyaleCrate) -> bool:
	if not is_instance_valid(d) or not d.alive or play_state != "play" or c == null:
		return false
	if not c.is_weapon():
		return take_supply(d, c.kind)
	var g := gun_of(d)
	if g == null:
		return false
	var cur := g.weapon
	if cur == c.weapon_id:
		if g.reserve >= g.reserve_max:
			return false
		var add := (g.mag_max if c.mag < 0 else c.mag) + (g.reserve_max if c.reserve < 0 else c.reserve)
		g.reserve = mini(g.reserve + maxi(add, 1), g.reserve_max)
		if g.mag <= 0 and g.reloading <= 0.0:
			g.reload()
		supplies_taken["ammo"] = int(supplies_taken.get("ammo", 0)) + 1
		supply_taken.emit(d, "ammo")
		if feel_enabled:
			_play("equip", -6.0 if _is_human(d) else -12.0, 1.0, d.centre_of_mass())
		return true
	if cur != "" and not g.out_of_ammo() and tier(c.weapon_id) <= tier(cur):
		return false
	var old_mag := g.mag
	var old_res := g.reserve
	_weapons[d.player_index] = c.weapon_id
	_equip(d)
	if c.mag >= 0:
		g.mag = mini(c.mag, g.mag_max)
	if c.reserve >= 0:
		g.reserve = mini(c.reserve, g.reserve_max)
	if g.mag <= 0 and g.reserve > 0:
		g.reload()
	weapons_taken += 1
	if cur != "" and old_mag + old_res > 0:
		spawn_weapon_crate(cur, c.home, old_mag, old_res)
		weapon_swaps += 1
	weapon_taken.emit(d, c.weapon_id, cur)
	if feel_enabled:
		_play("equip", -4.0 if _is_human(d) else -12.0, 0.9, d.centre_of_mass())
	return true


## Выбыл с оружием (и патронами) — оно остаётся ящиком на месте выбывания.
func _drop_weapon(victim: Doll) -> void:
	var g := gun_of(victim)
	if g == null or g.weapon == "":
		return
	var m := g.mag
	var r := g.reserve
	var id := g.weapon
	_weapons.erase(victim.player_index)
	if not Tuning.ROYALE_DROP_ON_KO or m + r <= 0:
		return
	var b := _map_bounds()
	var at: Vector3 = victim.last_ko_record.get("position", victim.centre_of_mass())
	at = Vector3(clampf(at.x, b.position.x + 1.0, b.end.x - 1.0), clampf(at.y, 0.9, b.end.y - 1.5), 0.0)
	spawn_weapon_crate(id, at, m, r)
	drops += 1


# --- выбывание и конец ---

func _on_doll_ko(attacker: Node, record: Dictionary, victim: Doll) -> void:
	if phase == Phase.OVER or play_state != "play":
		return
	var feel := feel_enabled
	feel_enabled = false
	_match_on_doll_ko(attacker, record, victim)   # Match: запись, KO, сигнал ko, проверка конца (_check_over — ниже)
	feel_enabled = feel
	var killer: Doll = attacker as Doll if attacker is Doll and is_instance_valid(attacker) and attacker != victim else null
	var cause := "zone" if bool(record.get("zone", false)) else ("kill" if killer != null else String(record.get("kind", "self")))
	boosts_active.erase(victim.player_index)
	_tally(victim.player_index, "deaths", 1)
	if killer != null:
		_tally(killer.player_index, "kills", 1)
	var left := alive_dolls().size()
	var place := left + 1
	places[victim.player_index] = place
	frags.append({"t": snappedf(fight_time, 0.01), "victim": victim.player_index, "killer": killer.player_index if killer != null else -1,
		"weapon": weapon_name(killer) if killer != null else "", "place": place, "left": left, "cause": cause})
	_drop_weapon(victim)
	eliminated.emit(victim, killer, place, left, cause)
	if feel and (_is_human(victim) or _is_human(killer)):
		_camera_fx(25.0, record.get("position", victim.centre_of_mass()))
		if FxPreset.time_fx():
			_time_effect(Tuning.KO_SLOWMO_SCALE, Tuning.SQUAD_KO_SLOWMO_S)


## Последний живой — победа (все выбыли в одном тике — ничья: Match.build_results).
func _check_over() -> void:
	if combat_active() and play_state == "play" and alive_dolls().size() <= 1:
		_finish("ko")


func alive_count() -> int:
	return alive_dolls().size()


## Место бойца: выбывший — его место, живой — 0 (ещё в бою).
func place_of(d: Doll) -> int:
	return int(places.get(d.player_index, 0)) if is_instance_valid(d) else 0


## Итоги: базовые (места: живые по HP, выбывшие — от последнего к первому, в одном тике — одно место) + места по player_index,
## победитель, фраги, урон зоной, оружие.
func build_results(reason: String = "timeout") -> Dictionary:
	var r := super.build_results(reason)
	var pl := {}
	var plc: Array = r["places"]
	var ranks: Array = r["ranks"]
	for i in plc.size():
		pl[(plc[i] as Doll).player_index] = int(ranks[i]) + 1
	places = pl
	var w: Variant = r["winner"]
	winner_index = (w as Doll).player_index if w != null and is_instance_valid(w) else -1
	r["royale_places"] = pl.duplicate()
	r["winner_index"] = winner_index
	r["zone_stage"] = zone.stage_no()
	r["zone_damage"] = zone_damage.duplicate()
	r["outside_max"] = outside_max.duplicate()
	r["weapons"] = _weapons.duplicate()
	r["mode"] = "royale"
	return r
