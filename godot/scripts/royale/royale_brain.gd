## Бот «Королевской битвы» (docs/plan-demo/ROYALE.md; MODES_PACK.md §2: «сначала к ближнему ящику, потом держатся внутри зоны и бьют
## ближнего, у края зоны — уходят внутрь»). Наследник SquadBrain стычки: держит дистанцию своего оружия, стреляет, когда ствол на цели,
## гаусс копит заряд, перезарядка, застревание, ящики. Своё:
##   • каждый сам за себя: цели — все живые бойцы, кроме себя (группа RoyaleMatch.FIGHTERS_GROUP), разноса «со своими» нет, на линии
##     огня своих нет (_is_friend); сторона от цели — та, где бот уже есть (ствол перекладывается в руку стороны цели — RoyaleArm);
##   • зона: все цели движения (_clamp_goal) — внутри стен «через ROYALE_BOT_LOOK_AHEAD_S с» с запасом ROYALE_BOT_EDGE_M; снаружи этих стен —
##     состояние «zone»: внутрь полной тягой (снаружи настоящих стен — с рывком), по дороге стреляет; ящики снаружи — не берёт;
##   • ящики (_pick_crate): без оружия (или без патронов) — к ближнему ящику с оружием, где бы он ни был; с оружием — к оружию рангом выше
##     ближе ROYALE_BOT_UPGRADE_M, к своему же оружию за патронами, к жизням / броне / бонусу рядом (как в стычке); ящик, к которому
##     соперник ближе на ROYALE_BOT_YIELD_M, — в последнюю очередь (не толпятся у одного);
##   • без оружия и без ящика — рукопашная: к цели с наскоком, рука — на цель (бьёт кистью и телом).
class_name RoyaleBrain
extends SquadBrain

const NONE_GROUP := "royale_none"     # разнос «со своими» — пустая группа
const PUNCH_DASH_M := 6.0             # рукопашная: ближе — наскок с ускорением
const ROAM_M := 5.0                   # без цели: раз в ROAM_S новая точка в пределах ± стольких метров от прежней (внутри будущей зоны)
const ROAM_S := 7.0
const PICK_EVERY_S := 0.25            # выбор ящика — не чаще
const NAV_EVERY_S := 0.3              # план пути через метки — не чаще
const NAV_ARRIVE_M := 1.2             # у метки ближе этого — она пройдена

var _pick_next := -1.0
var _nav_next := -1.0
var _nav_goal := Vector2(INF, INF)
var _nav_wp := Vector2.ZERO
var _nav_direct := true
var _ends: Dictionary = {}            # Vector2i(округлённая цель) → {метка: расстояние}
var _roam_next := -1.0
var _roam_y := 0.0

## Кто ранил последним и до какого _time он виден, где бы ни был.
var _grudge: Doll = null
var _grudge_until := -1.0
## Своя точка по x, у которой бот держится без цели (внутри будущей зоны).
var _anchor_x := NAN


func _brain_ready() -> void:
	super._brain_ready()
	players_group = RoyaleMatch.FIGHTERS_GROUP
	enemies_group = NONE_GROUP
	_lane = float(LANE_Y[int(doll.player_index) % LANE_Y.size()])
	_phase = float(doll.player_index) * 1.3


func _on_damaged(_amount: float, attacker: Node, _part: String, _pos: Vector3, _kind: String) -> void:
	if attacker is Doll and attacker != doll and is_instance_valid(attacker):
		_grudge = attacker as Doll
		_grudge_until = _time + Tuning.ROYALE_BOT_GRUDGE_S


## Докуда бот видит соперников: ROYALE_BOT_SEE_M, с дальнобойным стволом — до его дальности боя, но не дальше ROYALE_BOT_SEE_FAR_M;
## в сборе (первые ROYALE_BOT_CALM_S боя) — только вплотную.
func see_m() -> float:
	var m := rm()
	if m != null and m.fight_time < Tuning.ROYALE_BOT_CALM_S:
		return Tuning.ROYALE_BOT_CALM_SEE_M
	var r := Tuning.ROYALE_BOT_SEE_M
	var g := gun()
	if g != null and g.weapon != "":
		r = clampf((Tuning.SQUAD_BOT_RANGE.get(g.weapon, Vector2(6.0, 11.0)) as Vector2).y, r, Tuning.ROYALE_BOT_SEE_FAR_M)
	return r


func rm() -> RoyaleMatch:
	return get_tree().get_first_node_in_group(Match.GROUP) as RoyaleMatch


func zone() -> RoyaleZone:
	var m := rm()
	return m.zone if m != null else null


## Цели — живые бойцы, кроме себя, ближе see_m() (текущая цель — до × 1.5: не теряет её на краю зрения); и тот, кто ранил недавно,
## где бы ни был.
func players() -> Array:
	var out := super.players()
	out.erase(doll)
	var me := my_pos()
	var lim := see_m()
	return out.filter(func(p: Variant) -> bool:
		var dist := me.distance_to(com2(p as Doll))
		return dist <= lim or (p == target and dist <= lim * 1.5) or (p == _grudge and _time < _grudge_until))


## Дистанция боя — не дальше, чем бот видит после сбора (иначе снайпер отходил бы за край зрения и терял цель).
func _hold_range(tp: Vector2, dist: float) -> Vector2:
	var g := gun()
	var far := Tuning.ROYALE_BOT_SEE_M
	if g != null and g.weapon != "":
		far = clampf((Tuning.SQUAD_BOT_RANGE.get(g.weapon, Vector2(6.0, 11.0)) as Vector2).y, far, Tuning.ROYALE_BOT_SEE_FAR_M)
	return super._hold_range(tp, minf(dist, far - 2.0))


func _is_friend(_who: Doll) -> bool:
	return false


## Сторона от цели — где бот уже есть (без цели — сторона от середины зоны).
func _side() -> float:
	if target != null and is_instance_valid(target) and target.alive:
		return -1.0 if my_pos().x < com2(target).x else 1.0
	var z := zone()
	var mid := z.centre() if z != null else 0.0
	return -1.0 if my_pos().x < mid else 1.0


## Безопасный коридор по x: стены зоны через ROYALE_BOT_LOOK_AHEAD_S с, ужатые на ROYALE_BOT_EDGE_M (узкий — его середина).
func safe_x() -> Vector2:
	var z := zone()
	if z == null:
		var b := arena_bounds()
		return Vector2(b.position.x + 1.5, b.end.x - 1.5)
	var e := z.edges_at(Tuning.ROYALE_BOT_LOOK_AHEAD_S)
	var m := Tuning.ROYALE_BOT_EDGE_M
	if e.y - e.x <= m * 2.0 + 0.5:
		var c := (e.x + e.y) * 0.5
		return Vector2(c - 0.25, c + 0.25)
	return Vector2(e.x + m, e.y - m)


## Цель движения: в границах карты и внутри безопасного коридора зоны; прямой путь закрыт (плита, настил башни) — промежуточная
## точка по графу меток (_nav_to).
func _clamp_goal(g: Vector2) -> Vector2:
	var out := super._clamp_goal(g)
	var s := safe_x()
	out.x = clampf(out.x, s.x, s.y)
	return _nav_to(out)


## Куда лететь к goal: прямо, если толстый луч чист; иначе — к видимой метке RaceNav, от которой путь по графу до меток, видных от
## goal, короче всего (без поиска пути бот бился снизу в плиты под ящиками). План — не чаще NAV_EVERY_S или при новой цели.
func _nav_to(goal: Vector2) -> Vector2:
	if _time < _nav_next and goal.distance_to(_nav_goal) < 1.0:
		return goal if _nav_direct else _nav_wp
	_nav_next = _time + NAV_EVERY_S
	_nav_goal = goal
	_nav_direct = true
	var space := doll.get_world_3d().direct_space_state if doll.is_inside_tree() else null
	var me := my_pos()
	if space == null or RaceNav.clear(space, me, goal):
		return goal
	var m := rm()
	var nv := m.nav() if m != null else null
	if nv == null or not nv.ready():
		return goal
	var ends := _ends_of(space, nv, goal)
	if ends.is_empty():
		return goal
	var best := -1
	var best_c := INF
	for i in nv.marks.size():
		var mi := Vector2(nv.marks[i].x, nv.marks[i].y)
		var dm := me.distance_to(mi)
		if dm < NAV_ARRIVE_M:
			continue   # уже у этой метки — дальше по графу
		var rest := INF
		for j in ends:
			rest = minf(rest, nv.path_len(i, int(j)) + float(ends[j]))
		if rest == INF or dm + rest >= best_c:
			continue
		if RaceNav.clear(space, me, mi):
			best_c = dm + rest
			best = i
	if best < 0:
		return goal
	_nav_direct = false
	_nav_wp = Vector2(nv.marks[best].x, nv.marks[best].y)
	counters["nav"] = int(counters.get("nav", 0)) + 1
	return _nav_wp


## Метки, видные от точки goal: {индекс: расстояние} (кэш по округлённой точке — ящики стоят на месте).
func _ends_of(space: PhysicsDirectSpaceState3D, nv: RaceNav, goal: Vector2) -> Dictionary:
	var key := Vector2i(int(round(goal.x * 2.0)), int(round(goal.y * 2.0)))
	if _ends.has(key):
		return _ends[key]
	var out := {}
	for j in nv.marks.size():
		var mj := Vector2(nv.marks[j].x, nv.marks[j].y)
		if RaceNav.clear(space, mj, goal):
			out[j] = mj.distance_to(goal)
	if _ends.size() > 64:
		_ends.clear()
	_ends[key] = out
	return out


func _crate_safe(c: Node3D) -> bool:
	var s := safe_x()
	return c.global_position.x >= s.x - 0.5 and c.global_position.x <= s.y + 0.5


func _think(delta: float) -> void:
	var g := gun()
	var has_target := target != null and is_instance_valid(target) and target.alive
	var z := zone()
	if z != null and z.running:
		var me := my_pos()
		var s := safe_x()
		var out_now := not z.inside(me.x)
		if out_now or me.x < s.x - 0.75 or me.x > s.y + 0.75:
			go("zone")
			var gx := clampf(me.x, s.x, s.y)
			want = steer_speed(Vector2(gx, clampf(me.y, FLOOR_Y + 0.6, arena_bounds().end.y - CEIL_MARGIN)), 9.0, 1.0)
			if out_now:
				dash()
			_fight_on_the_way(g, has_target)
			return
	if g == null or g.weapon == "":
		_unarmed(delta, g, has_target)
		return
	super._think(delta)


## Без оружия: к ящику с оружием (по дороге бьёт рукой, если цель рядом); ящиков нет — рукопашная.
func _unarmed(delta: float, g: SquadGun, has_target: bool) -> void:
	var had := crate
	_pick_crate(g, false)
	if crate != null and crate == had:
		_crate_t += delta
		if _crate_t > CRATE_GIVE_UP_S:
			_crate_skip[crate.get_instance_id()] = _time + CRATE_SKIP_S
			crate = null
			_crate_t = 0.0
	else:
		_crate_t = 0.0
	_trigger(false)
	if crate != null:
		go("supply")
		var cp := crate.global_position
		want = steer_speed(_clamp_goal(Vector2(cp.x, cp.y)), 7.0, max_in)
		if my_pos().distance_to(Vector2(cp.x, cp.y)) > 9.0:
			dash()
		if has_target and my_pos().distance_to(com2(target)) < Tuning.SQUAD_BOT_MELEE_M * 1.5:
			_aim(predicted())
		else:
			_release_arm()
		return
	if not has_target:
		_advance()
		_release_arm()
		return
	go("melee")
	var tp := predicted()
	want = steer(_clamp_goal(tp), 1.0)
	_aim(tp)
	if my_pos().distance_to(com2(target)) < PUNCH_DASH_M and state_t > MELEE_S:
		state_t = 0.0
		note_attack()
		dash()


## Переход: к сопернику, которого видит (со своей стороны), на своей полке высоты; никого не видит — держится у своей точки внутри
## будущей зоны (куда идут стены): не летит через всю карту, а сходится с остальными по мере сжатия.
func _advance() -> void:
	if state != "advance":
		go("advance")
	var goal := _roam_goal()
	if target != null and is_instance_valid(target) and target.alive:
		goal = Vector2(com2(target).x + _side() * 4.0, _lane)
	want = steer_speed(_clamp_goal(goal), 5.0, max_in)


## Патруль без цели: раз в ROAM_S — новая точка в ± ROAM_M по x от прежней и новая высота (полки LANE_Y), всё внутри будущей зоны
## (стены, куда идёт сжатие). Висеть на одном месте нельзя: бот у стены укрытия упирался в неё десятки секунд (проба 06.10).
func _roam_goal() -> Vector2:
	var z := zone()
	var lo := arena_bounds().position.x + 2.0
	var hi := arena_bounds().end.x - 2.0
	if z != null:
		var n := z.next_edges()
		var m := minf(Tuning.ROYALE_BOT_EDGE_M + 1.0, (n.y - n.x) * 0.3)
		lo = n.x + m
		hi = maxf(n.y - m, lo)
	if is_nan(_anchor_x) or _time >= _roam_next:
		var base := my_pos().x if is_nan(_anchor_x) else _anchor_x
		_anchor_x = base + _rng.randf_range(-ROAM_M, ROAM_M)
		_roam_y = float(LANE_Y[_rng.randi_range(0, LANE_Y.size() - 1)])
		_roam_next = _time + ROAM_S * _rng.randf_range(0.7, 1.3)
	_anchor_x = clampf(_anchor_x, lo, hi)
	return Vector2(_anchor_x, _roam_y)


## Ящик, за которым идти (или null): см. шапку. Ящики за стенами зоны (через ROYALE_BOT_LOOK_AHEAD_S) — нет. Выбор — не чаще
## PICK_EVERY_S (перебор ящиков × соперников каждый тик у восьми ботов — заметные доли миллисекунды), ящик пропал — сразу.
func _pick_crate(g: SquadGun, armless := false) -> void:
	if crate != null and (not is_instance_valid(crate) or crate.is_queued_for_deletion()):
		crate = null
		_pick_next = -1.0
	if _time < _pick_next:
		return
	_pick_next = _time + PICK_EVERY_S
	var m := rm()
	var unarmed := g == null or g.weapon == ""
	var no_ammo := g != null and g.out_of_ammo()
	var me := my_pos()
	var best: SupplyCrate = null
	var best_cost := INF
	for n in get_tree().get_nodes_in_group(SquadMatch.SUPPLY_GROUP):
		var c := n as SupplyCrate
		if c == null or c.is_queued_for_deletion() or float(_crate_skip.get(c.get_instance_id(), -1.0)) > _time or not _crate_safe(c):
			continue
		var cp := Vector2(c.global_position.x, c.global_position.y)
		var dd := me.distance_to(cp)
		var rc := c as RoyaleCrate
		var cost := INF
		if rc != null and rc.is_weapon():
			if unarmed or no_ammo:
				cost = dd - 1000.0
			elif m != null and RoyaleMatch.tier(rc.weapon_id) > RoyaleMatch.tier(g.weapon) and dd < Tuning.ROYALE_BOT_UPGRADE_M:
				cost = dd - 50.0
			elif rc.weapon_id == g.weapon and g.reserve < g.mag_max and dd < Tuning.SQUAD_BOT_SUPPLY_M:
				cost = dd
		else:
			match c.kind:
				"ammo":
					if not unarmed and (no_ammo or (g.reserve < g.mag_max and dd < Tuning.SQUAD_BOT_SUPPLY_M)):
						cost = dd - (500.0 if no_ammo else 0.0)
				"health":
					if (doll.hp < doll.max_hp * LOW_HP or armless) and dd < Tuning.SQUAD_BOT_SUPPLY_M:
						cost = dd
				"armor":
					if m != null and m.armor_of(doll) <= 0.0 and dd < Tuning.SQUAD_BOT_SUPPLY_M * (0.6 if unarmed else 1.0):
						cost = dd
				_:
					if dd < Tuning.SQUAD_BOT_SUPPLY_M * (0.6 if unarmed else 1.0):
						cost = dd
			if armless and cost == INF:
				cost = dd   # любой ящик вернёт руку
		if cost == INF:
			continue
		if _rival_closer(c, dd):
			cost += 60.0   # соперник ближе — этот ящик в последнюю очередь
		if cost < best_cost:
			best_cost = cost
			best = c
	crate = best


## Другой живой боец ближе к ящику на ROYALE_BOT_YIELD_M.
func _rival_closer(c: Node3D, my_d: float) -> bool:
	var cp := Vector2(c.global_position.x, c.global_position.y)
	for n in get_tree().get_nodes_in_group(RoyaleMatch.FIGHTERS_GROUP):
		if n == doll or not (n is Doll) or not (n as Doll).alive:
			continue
		if com2(n as Doll).distance_to(cp) + Tuning.ROYALE_BOT_YIELD_M < my_d:
			return true
	return false


func _stuck_allowed() -> bool:
	return state in ["advance", "engage", "reload", "supply", "brawl", "objective", "zone", "melee"]
