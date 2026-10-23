## Матч «Собери себя» (docs/plan-demo/SCAVENGER.md; MODES_IDEAS.md Б6: «все стартуют торсом с головой, конечности лежат на карте —
## кто быстрее соберёт себя»). Наследник Match: от него — регистрация кукол (DollCombat), удары с уроном, отрыв по запасу деталей
## (PartHp), KO, отсчёт, надписи. Своё:
##   • пятеро «Человеков», все против всех (Doll.team "scav_N" у каждого свой), рубашка — Tuning.SCAV_COLORS[player_index];
##   • старт (begin): у каждой куклы откручиваются все конечности (лист → корень: кисть/стопа, предплечье/голень, плечо/бедро) и
##     прячутся «в запас» (stash: невидимы, заморожены, без коллизий, далеко за ареной) — у куклы остаются торс и голова;
##     на карте по точкам MARKS лежат Tuning.SCAV_PARTS_N деталей-«жетонов» (сцены кита kit_human_<вид>.tscn, группа scav_parts,
##     подсветка — общий материал-оболочка с пульсом);
##   • подбор: любая деталь живой куклы ближе SCAV_PICK_M к жетону, у куклы в запасе есть деталь того же вида, а её родитель
##     прикручен (кисть — только на предплечье, предплечье — на плечо) → своя спрятанная деталь возвращается на место
##     (Doll.reattach_part: поза сборки, ❤ детали — снова в запасе), жетон исчезает; вспышка цвета куклы (ImpactLight + AirShock),
##     звук прикрутки (DollAudio «attach») и, у человека, нарастающий «combo»;
##   • ход: голый торс — × SCAV_BARE_SPEED, полный набор — × SCAV_FULL_SPEED (Doll.speed_cap_mult), тяга — на массу сборки
##     (Doll.thrust_mult: разгон как у полной куклы × тот же множитель, без деталей не «ракета»);
##   • оторванное в бою (Doll.part_detached) снова становится жетонами там, где отлетело (ветка — по жетону на каждую деталь),
##     а сами тела — в запас этой куклы; своё нельзя поднять SCAV_OWN_LOCK_S, чужим — SCAV_DROP_LOCK_S;
##   • KO (оторвана голова или запас ❤ = 0, пропасть): все конечности выбитого рассыпаются жетонами (разлёт SCAV_KO_BURST) —
##     бери кто хочет; возврата нет;
##   • конец: остался один живой — победа ему; Tuning.SCAV_TIME_S вышло — места по: жив → деталей больше → запас больше → выбыл позже;
##     равны первые двое — ничья. Sudden Death базового Match выключен;
##   • эффекты удара и KO (тряска, стоп-кадр) — только если участвует человек (как в «Охоте за головами»); крит-кино выключено.
## Инвариант (проба): жетонов на карте + деталей на живых куклах = SCAV_PARTS_N (детали не появляются и не пропадают).
## Сигналы для HUD, площадки и проб: part_attached, parts_changed, tokens_changed + унаследованные.
## Журналы для проб: pickups [{t, pi, kind, count}], kos [{t, victim, attacker, parts}], drops [{t, pi, n, why}].
class_name ScavMatch
extends Match

signal part_attached(doll: Doll, kind: String, count: int)
signal parts_changed(doll: Doll, count: int)
signal tokens_changed(n: int)

const PARTS_GROUP := "scav_parts"
const TEAM_PREFIX := "scav_"
## Базовое имя тела куклы → вид детали (meta kind сцен кита).
const KIND_OF := {"UpperArm": "upper_arm", "LowerArm": "lower_arm", "Hand": "hand", "UpperLeg": "upper_leg", "LowerLeg": "lower_leg",
	"Foot": "foot"}
const KIND_SCENE := "res://scenes/body/kit/kit_human_%s.tscn"
## Порядок открутки на старте: лист → корень (у каждой детали своя запись запаса, по одной на тело).
const STRIP_ORDER := ["Hand", "Foot", "LowerArm", "LowerLeg", "UpperArm", "UpperLeg"]
## Точки, где лежат детали: свободный воздух над полом и уступами Свалки (как метки гонки, без точки над пропастью).
const MARKS := [Vector2(-16.0, 6.6), Vector2(-12.0, 3.4), Vector2(-7.0, 8.2), Vector2(-5.0, 3.6), Vector2(-2.8, 5.5), Vector2(0.0, 2.6),
	Vector2(2.5, 6.6), Vector2(2.5, 3.0), Vector2(6.8, 2.7), Vector2(8.5, 8.5), Vector2(11.6, 9.5), Vector2(13.0, 7.7), Vector2(16.5, 8.6),
	Vector2(15.5, 1.8), Vector2(0.0, 10.5), Vector2(-12.0, 10.0)]
const STASH_AT := Vector3(1000.0, -400.0, 0.0)
const BOUNDS_CHECK_S := 0.25

@export var parts_n: int = Tuning.SCAV_PARTS_N
@export var rng_seed := 0

## idle | countdown | play | over
var play_state := "idle"
## player_index → {parts (на конец / на момент KO), picked, kos, kos_taken, max_parts, lost}
var tally: Dictionary = {}
var pickups: Array = []
var kos: Array = []
var drops: Array = []
var fx_count := 0
var parts_root: Node3D
var _sfx: Node = null
var _quiet := 0
var _rng := RandomNumberGenerator.new()
var _accel0: Dictionary = {}       # instance_id куклы → разгон полной куклы (thrust_mass / total_mass)
var _ko_t: Dictionary = {}         # instance_id куклы → fight_time KO
var _sweep_wait: Dictionary = {}   # instance_id куклы → true: разбор оторванного уже запланирован
var _glow: StandardMaterial3D
var _glow_t := 0.0
var _scenes: Dictionary = {}
var _stash_n := 0
var _token_n := 0
var _bounds_t := 0.0


func _ready() -> void:
	time_limit_s = Tuning.SCAV_TIME_S
	hard_timeout_s = Tuning.SCAV_TIME_S
	super._ready()
	crit_enabled = false
	for k in KIND_OF.values():
		_scenes[k] = load(KIND_SCENE % k)
	_glow = StandardMaterial3D.new()
	_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow.cull_mode = BaseMaterial3D.CULL_FRONT
	_glow.grow = true
	_glow.grow_amount = Tuning.SCAV_GLOW_GROW_M
	_glow.albedo_color = Tuning.SCAV_GLOW_COLOR
	var host := get_parent().get_node_or_null("Parts") if get_parent() != null else null
	if host is Node3D:
		parts_root = host
	else:
		parts_root = Node3D.new()
		parts_root.name = "Parts"
		add_child(parts_root)


# --- куклы ---

static func doll_name(d: Object) -> String:
	if d == null or not is_instance_valid(d):
		return "—"
	return "P%d" % (int(d.get("player_index")) + 1)


static func colour_of(d: Object) -> Color:
	if d == null or not is_instance_valid(d):
		return Color.WHITE
	return Tuning.SCAV_COLORS[posmod(int(d.get("player_index")), Tuning.SCAV_COLORS.size())]


static func _is_human(d: Object) -> bool:
	return d != null and is_instance_valid(d) and d is Doll and not (d as Doll).external_input


## Вид детали по телу куклы или жетону ("" — торс, голова, не деталь кита).
static func kind_of_body(b: Object) -> String:
	if b == null or not is_instance_valid(b) or not (b is Node):
		return ""
	var n := b as Node
	if n.has_meta("scav_kind"):
		return String(n.get_meta("scav_kind"))
	return String(KIND_OF.get(Doll.part_base_name(String(n.name)), ""))


## Деталей на кукле (конечности, без торса и головы); выбитая — сколько было на момент KO.
func parts_count(d: Object) -> int:
	if d == null or not is_instance_valid(d) or not (d is Doll):
		return 0
	var dd := d as Doll
	if not dd.alive:
		return int((tally.get(dd.player_index, {}) as Dictionary).get("parts", 0))
	var n := 0
	for k in dd.parts.keys():
		if KIND_OF.has(Doll.part_base_name(String(k))):
			n += 1
	return n


func register(d: Doll) -> void:
	var fresh := not _order.has(d)
	super.register(d)
	if not fresh:
		return
	d.team = TEAM_PREFIX + str(d.player_index)
	if not d.part_detached.is_connected(_on_part_detached):
		d.part_detached.connect(_on_part_detached.bind(d))
	if d.is_node_ready():
		_dress(d)
	else:
		d.ready.connect(_dress.bind(d), CONNECT_ONE_SHOT)
	if not tally.has(d.player_index):
		tally[d.player_index] = _fresh_tally()


static func _fresh_tally() -> Dictionary:
	return {"parts": 0, "picked": 0, "kos": 0, "kos_taken": 0, "max_parts": 0, "lost": 0}


func _dress(d: Doll) -> void:
	if is_instance_valid(d):
		d._recolor(d, Doll.SHIRT_MATERIAL, colour_of(d))


func spawn_point_for(d: Doll) -> Vector3:
	var pts: Array = Tuning.SCAV_SPAWN
	if d.player_index >= 0 and d.player_index < pts.size():
		var p: Vector2 = pts[d.player_index]
		return Vector3(p.x, p.y, 0.0)
	return super.spawn_point_for(d)


## Кукла «я» для HUD: человек с меньшим player_index, иначе null.
func me() -> Doll:
	var best: Doll = null
	for d in dolls():
		var dd := d as Doll
		if not dd.external_input and (best == null or dd.player_index < best.player_index):
			best = dd
	return best


# --- фазы ---

func begin() -> void:
	play_state = "countdown"
	pickups.clear()
	kos.clear()
	drops.clear()
	_ko_t.clear()
	_sweep_wait.clear()
	fx_count = 0
	for k in tally.keys():
		tally[k] = _fresh_tally()
	_clear_tokens()
	for d in dolls():   # begin() без restart(): кукла с открученным — заново целиком
		var dd := d as Doll
		if not dd.is_broken() and not dd.detached_parts().is_empty():
			respawn_doll(dd)
	_rng.seed = rng_seed if rng_seed != 0 else int(Time.get_ticks_usec())
	super.begin()
	for d in dolls():
		_strip(d as Doll)
	_scatter_initial()


func restart() -> void:
	_clear_tokens()
	super.restart()


func _start_fight() -> void:
	super._start_fight()
	play_state = "play"
	for d in dolls():
		_apply_speed(d as Doll)


func _finish(reason: String) -> void:
	if phase == Phase.OVER:
		return
	play_state = "over"
	for d in dolls():
		var dd := d as Doll
		dd.control_enabled = false
		if dd.alive:
			(tally[dd.player_index] as Dictionary)["parts"] = parts_count(dd)
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
			if play_state == "play":
				_tick_pickups()
			_bounds_t += delta
			if _bounds_t >= BOUNDS_CHECK_S:
				_bounds_t = 0.0
				_check_token_bounds()
			if play_state == "play" and fight_time >= time_limit_s:
				_finish("timeout")


func _process(delta: float) -> void:
	super._process(delta)
	var real := delta / maxf(Engine.time_scale, 0.01)
	_glow_t += real
	var s := 0.5 + 0.5 * sin(TAU * Tuning.SCAV_GLOW_HZ * _glow_t)
	var c := Tuning.SCAV_GLOW_COLOR
	c.a = lerpf(Tuning.SCAV_GLOW_ALPHA.x, Tuning.SCAV_GLOW_ALPHA.y, s)
	_glow.albedo_color = c
	_glow.grow_amount = Tuning.SCAV_GLOW_GROW_M * (0.6 + 0.8 * s)


# --- запас (спрятанные свои детали) ---

## Открутить у куклы все конечности (лист → корень) и спрятать их в запас. Тихо: без звука и разбора part_detached.
func _strip(d: Doll) -> void:
	if d == null or not is_instance_valid(d) or d.is_broken():
		return
	_accel0[d.get_instance_id()] = d.thrust_mass() / maxf(d.total_mass, 0.1)
	_quiet += 1
	var audio := _mute(d)
	for base in STRIP_ORDER:
		for k in d.parts.keys():
			if Doll.part_base_name(String(k)) != base:
				continue
			var b := d.detach_part(String(k))
			if b != null and is_instance_valid(b):
				_stash(d, b)
	_unmute(audio)
	_quiet -= 1
	_apply_speed(d)
	parts_changed.emit(d, parts_count(d))


## Звук прикрутки/открутки куклы (DollAudio) — выключить на время тихой операции: [узел, его sfx].
func _mute(d: Doll) -> Array:
	for c in d.get_children():
		if is_instance_valid(c) and c is DollAudio:
			var a := c as DollAudio
			var was: Variant = a.sfx
			a.sfx = null
			return [a, was]
	return []


func _unmute(m: Array) -> void:
	if m.size() == 2 and is_instance_valid(m[0]):
		(m[0] as DollAudio).sfx = m[1]


## Спрятать оторванный корень (и всё поддерево его записи) в запас куклы.
func _stash(d: Doll, root: RigidBody3D) -> void:
	var rec: Dictionary = d._detached.get(root, {})
	var sub: Array = rec.get("sub", [root])
	root.set_meta("scav_stash", true)
	for s in sub:
		if not is_instance_valid(s):
			continue
		var b := s as RigidBody3D
		if not b.has_meta("scav_layers"):
			b.set_meta("scav_layers", [b.collision_layer, b.collision_mask])
		b.collision_layer = 0
		b.collision_mask = 0
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
		b.freeze = true
		b.visible = false
		_stash_n += 1
		b.global_position = STASH_AT + Vector3(float(_stash_n % 64) * 3.0, float(d.player_index) * 6.0, 0.0)
		b.reset_physics_interpolation()


func _unstash(d: Doll, root: RigidBody3D) -> void:
	var rec: Dictionary = d._detached.get(root, {})
	var sub: Array = rec.get("sub", [root])
	root.remove_meta("scav_stash")
	for s in sub:
		if not is_instance_valid(s):
			continue
		var b := s as RigidBody3D
		var lm: Variant = b.get_meta("scav_layers", null)
		if lm is Array and (lm as Array).size() == 2:
			b.collision_layer = int(lm[0])
			b.collision_mask = int(lm[1])
			b.remove_meta("scav_layers")
		b.freeze = false
		b.visible = true


## Спрятанные корни куклы.
func stash_of(d: Doll) -> Array:
	var out: Array = []
	if d == null or not is_instance_valid(d):
		return out
	for b in d.detached_parts():
		if (b as Node).has_meta("scav_stash"):
			out.append(b)
	return out


## Спрятанная деталь вида kind, которую можно прикрутить сейчас (родитель на кукле), — ближайшая родителем к точке near; null — нет.
func takeable(d: Doll, kind: String, near := Vector3.INF) -> RigidBody3D:
	if d == null or not is_instance_valid(d) or not d.alive or d.is_broken():
		return null
	var best: RigidBody3D = null
	var best_d := INF
	var attached: Array = d.parts.values()
	for b in stash_of(d):
		if kind_of_body(b) != kind:
			continue
		var rec: Dictionary = d._detached.get(b, {})
		var a: Variant = rec.get("parent", null)
		if a == null or not is_instance_valid(a) or not attached.has(a):
			continue
		var dist := 0.0 if near == Vector3.INF else (a as Node3D).global_position.distance_to(near)
		if best == null or dist < best_d:
			best = b
			best_d = dist
	return best


# --- жетоны (детали на карте) ---

func tokens() -> Array:
	var out: Array = []
	if parts_root == null or not is_instance_valid(parts_root):
		return out
	for c in parts_root.get_children():
		if is_instance_valid(c) and (c as Node).is_in_group(PARTS_GROUP) and not (c as Node).is_queued_for_deletion():
			out.append(c)
	return out


func _clear_tokens() -> void:
	for t in tokens():
		parts_root.remove_child(t)
		(t as Node).queue_free()
	tokens_changed.emit(0)


## Жетон можно взять кукле d сейчас (замки броска и «своё только что оторвали»).
func token_free_for(t: Object, d: Doll) -> bool:
	if t == null or not is_instance_valid(t) or not (t is Node):
		return false
	var n := t as Node
	if fight_time < float(n.get_meta("scav_lock_until", 0.0)):
		return false
	if d != null and int(n.get_meta("scav_owner", 0)) == d.get_instance_id() and fight_time < float(n.get_meta("scav_owner_until", 0.0)):
		return false
	return true


## Жетон нужен кукле d: свободен для неё и есть куда прикрутить.
func token_wanted_by(t: Object, d: Doll) -> bool:
	return token_free_for(t, d) and takeable(d, kind_of_body(t)) != null


func _spawn_token(kind: String, xf: Transform3D, vel: Vector3, ang: Vector3, lock_s: float, owner: Doll = null,
		own_lock_s := 0.0) -> RigidBody3D:
	var ps := _scenes.get(kind) as PackedScene
	if ps == null:
		return null
	var t := ps.instantiate() as RigidBody3D
	_token_n += 1
	t.name = "Part_%s_%d" % [kind, _token_n]
	t.set_meta("scav_kind", kind)
	t.set_meta("scav_lock_until", fight_time + lock_s)
	if owner != null and is_instance_valid(owner):
		t.set_meta("scav_owner", owner.get_instance_id())
		t.set_meta("scav_owner_until", fight_time + own_lock_s)
	t.add_to_group(PARTS_GROUP)
	t.continuous_cd = true
	parts_root.add_child(t)
	var x := xf
	x.origin.z = 0.0
	t.global_transform = x
	t.linear_velocity = Vector3(vel.x, vel.y, 0.0)
	t.angular_velocity = Vector3(0.0, 0.0, ang.z)
	t.reset_physics_interpolation()
	for m in t.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_overlay = _glow
	return t


## Начальная раскладка: SCAV_PARTS_N деталей по точкам MARKS по кругу (виды — SCAV_SCATTER_KINDS), разброс по x.
## Старт: детали только на метках вдали от точек появления (start_marks) — никому не достаётся деталь «даром» на 0-й секунде.
func _scatter_initial() -> void:
	var kinds: Array = Tuning.SCAV_SCATTER_KINDS
	var marks := start_marks()
	var off := _rng.randi_range(0, marks.size() - 1)
	for i in parts_n:
		var m: Vector2 = marks[(i + off) % marks.size()]
		_spawn_token(String(kinds[i % kinds.size()]), _drop_xform(m), Vector3.ZERO, Vector3.ZERO, 0.0)
	tokens_changed.emit(tokens().size())


## Метки MARKS не ближе SCAV_START_CLEAR_M к точкам SCAV_SPAWN и не под ними (кукла на отсчёте оседает вниз).
static func start_marks() -> Array:
	var out: Array = []
	for m in MARKS:
		var ok := true
		for s in Tuning.SCAV_SPAWN:
			var dv: Vector2 = (m as Vector2) - (s as Vector2)
			if dv.length() < Tuning.SCAV_START_CLEAR_M or (absf(dv.x) < Tuning.SCAV_START_CLEAR_M * 0.5 and dv.y < 0.0):
				ok = false
				break
		if ok:
			out.append(m)
	return out if not out.is_empty() else MARKS.duplicate()


func _drop_xform(m: Vector2) -> Transform3D:
	var x := m.x + _rng.randf_range(-Tuning.SCAV_SCATTER_JITTER_M, Tuning.SCAV_SCATTER_JITTER_M)
	var pr := _pit()
	if x > pr.position.x - 0.6 and x < pr.end.x + 0.6:   # не над пропастью
		x = pr.position.x - 0.6 if x < pr.get_center().x else pr.end.x + 0.6
	var y := m.y + _rng.randf_range(0.0, Tuning.SCAV_DROP_LIFT_M)
	return Transform3D(Basis(Vector3.BACK, _rng.randf_range(-PI, PI)), Vector3(x, y, 0.0))


func _pit() -> Rect2:
	var a := _arena()
	if a != null and a.get("pit_rect") is Rect2:
		return a.get("pit_rect")
	return Rect2(-9.5, -3.0, 3.0, 3.0)


func _arena_box() -> AABB:
	var a := _arena()
	if a != null and a.has_method("bounds"):
		return a.call("bounds")
	return AABB(Vector3(-18.0, -6.0, -1.0), Vector3(36.0, 20.0, 2.0))


## Жетон в пропасти или за границей арены — снова на случайную точку.
func redrop(t: Object, why := "pit") -> void:
	if t == null or not is_instance_valid(t) or not (t is RigidBody3D) or not (t as Node).is_in_group(PARTS_GROUP):
		return
	var b := t as RigidBody3D
	b.global_transform = _drop_xform(MARKS[_rng.randi_range(0, MARKS.size() - 1)])
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO
	b.reset_physics_interpolation()
	b.set_meta("scav_lock_until", fight_time)
	drops.append({"t": snappedf(fight_time, 0.01), "pi": -1, "n": 1, "why": why})


func _check_token_bounds() -> void:
	var box := _arena_box()
	var pr := _pit()
	for t in tokens():
		var p := (t as Node3D).global_position
		var out := p.x < box.position.x - 0.5 or p.x > box.end.x + 0.5 or p.y < box.position.y or p.y > box.end.y + 1.0
		var pit := p.y < -0.5 and p.x > pr.position.x - 0.2 and p.x < pr.end.x + 0.2
		if out or pit:
			redrop(t, "pit" if pit else "out")


# --- подбор ---

func _tick_pickups() -> void:
	var alive := alive_dolls()
	if alive.is_empty():
		return
	var r := Tuning.SCAV_PICK_M
	for t in tokens():
		var tp := (t as Node3D).global_position
		var kind := kind_of_body(t)
		var best: Doll = null
		var best_d := r
		for d in alive:
			var dd := d as Doll
			if dd.centre_of_mass().distance_to(tp) > r + 2.5:
				continue
			if not token_free_for(t, dd) or takeable(dd, kind) == null:
				continue
			for p in dd.parts.values():
				var dist := (p as Node3D).global_position.distance_to(tp)
				if dist < best_d:
					best_d = dist
					best = dd
		if best != null:
			attach_token(best, t as RigidBody3D)


## Прикрутить кукле d деталь вида жетона t (своя из запаса), жетон убрать. false — некуда/нельзя.
func attach_token(d: Doll, t: RigidBody3D) -> bool:
	if d == null or not is_instance_valid(d) or t == null or not is_instance_valid(t):
		return false
	var kind := kind_of_body(t)
	var b := takeable(d, kind, t.global_position)
	if b == null:
		return false
	_unstash(d, b)
	if not d.reattach_part(b):
		_stash(d, b)
		return false
	var at := t.global_position
	parts_root.remove_child(t)
	t.queue_free()
	var n := parts_count(d)
	var tl: Dictionary = tally.get(d.player_index, _fresh_tally())
	tl["picked"] = int(tl["picked"]) + 1
	tl["max_parts"] = maxi(int(tl["max_parts"]), n)
	tl["parts"] = n
	tally[d.player_index] = tl
	pickups.append({"t": snappedf(fight_time, 0.01), "pi": d.player_index, "kind": kind, "count": n})
	_apply_speed(d)
	part_attached.emit(d, kind, n)
	parts_changed.emit(d, n)
	tokens_changed.emit(tokens().size())
	_attach_fx(d, b, at, n)
	return true


func _attach_fx(d: Doll, b: RigidBody3D, from: Vector3, n: int) -> void:
	fx_count += 1
	var host: Node = get_parent() if get_parent() != null else self
	var at := b.global_position if is_instance_valid(b) else from
	ImpactLight.flash(host, at, 2.4, 3.2, 0.28, colour_of(d).lightened(0.35))
	AirShock.spawn(host, at, 0.9, 0.3, 0.02)
	if not feel_enabled:
		return
	if _sfx == null or not is_instance_valid(_sfx):
		_sfx = get_tree().get_first_node_in_group(SfxDirector.GROUP)
		if _sfx == null:
			return
	if _is_human(d):
		_sfx.call("play_layer", "combo", -2.0, clampf(0.9 + 0.05 * float(n), 0.9, 1.5), SfxDirector.BUS_UI, 0.0)
		if n >= Tuning.SCAV_MAX_PARTS:
			_sfx.call("play_layer", "bell", 0.0, 1.0, SfxDirector.BUS_UI, 0.0)


## Ход по числу деталей: голый — × SCAV_BARE_SPEED, полный — × SCAV_FULL_SPEED; разгон — как у полной куклы × тот же множитель.
func speed_factor(d: Doll) -> float:
	return lerpf(Tuning.SCAV_BARE_SPEED, Tuning.SCAV_FULL_SPEED, clampf(float(parts_count(d)) / float(Tuning.SCAV_MAX_PARTS), 0.0, 1.0))


func _apply_speed(d: Doll) -> void:
	if d == null or not is_instance_valid(d) or not d.alive:
		return
	var f := speed_factor(d)
	var a0 := float(_accel0.get(d.get_instance_id(), 0.0))
	var tm := d.thrust_mass()
	if a0 > 0.0 and tm > 0.0:
		d.thrust_mult = f * a0 * d.total_mass / tm
	else:
		d.thrust_mult = f
	d.speed_cap_mult = f


# --- отрыв в бою и KO ---

func _on_part_detached(_part: String, _by: Node, d: Doll) -> void:
	if _quiet > 0 or play_state == "idle" or not is_instance_valid(d):
		return
	var id := d.get_instance_id()
	if _sweep_wait.has(id):
		return
	_sweep_wait[id] = true
	call_deferred("_sweep", id)


func _sweep(id: int) -> void:
	_sweep_wait.erase(id)
	var o := instance_from_id(id)
	if o == null or not is_instance_valid(o) or not (o is Doll):
		return
	var d := o as Doll
	if not d.is_inside_tree() or not _order.has(d):
		return
	if d.alive:
		_tear_alive(d)
	else:
		_scatter_dead(d)


## Живая кукла потеряла ветку: по жетону на каждую деталь ветки там, где она летит; тела — в запас (по одной записи на тело).
func _tear_alive(d: Doll) -> void:
	var n := 0
	for root in d.detached_parts():
		var rb := root as RigidBody3D
		if rb.has_meta("scav_stash"):
			continue
		var rec: Dictionary = d._detached.get(rb, {})
		var sub: Array = (rec.get("sub", [rb]) as Array).duplicate()
		var drops_now: Array = []
		for s in sub:
			if is_instance_valid(s):
				var sb := s as RigidBody3D
				drops_now.append([kind_of_body(sb), sb.global_transform, sb.linear_velocity, sb.angular_velocity])
		_quiet += 1
		var audio := _mute(d)
		if sub.size() > 1 and d.reattach_part(rb):
			for i in range(sub.size() - 1, -1, -1):
				if not is_instance_valid(sub[i]):
					continue
				var b := d.detach_part(String((sub[i] as Node).name))
				if b != null and is_instance_valid(b):
					_stash(d, b)
		else:
			_stash(d, rb)
		_unmute(audio)
		_quiet -= 1
		for e in drops_now:
			if String(e[0]) != "":
				_spawn_token(String(e[0]), e[1], e[2], e[3], Tuning.SCAV_DROP_LOCK_S, d, Tuning.SCAV_OWN_LOCK_S)
				n += 1
	if n > 0:
		var tl: Dictionary = tally.get(d.player_index, _fresh_tally())
		tl["lost"] = int(tl["lost"]) + n
		tl["parts"] = parts_count(d)
		tally[d.player_index] = tl
		drops.append({"t": snappedf(fight_time, 0.01), "pi": d.player_index, "n": n, "why": "tear"})
		_apply_speed(d)
		parts_changed.emit(d, parts_count(d))
		tokens_changed.emit(tokens().size())


## Выбитая кукла: все её конечности (на ней и только что оторванные) — жетоны с разлётом; тела гаснут (торс и голова — обломок).
func _scatter_dead(d: Doll) -> void:
	var bodies: Array = []
	for p in d.parts.values():
		bodies.append(p)
	for root in d.detached_parts():
		if (root as Node).has_meta("scav_stash"):
			continue
		var rec: Dictionary = d._detached.get(root, {})
		for s in rec.get("sub", [root]):
			if not bodies.has(s):
				bodies.append(s)
	var n := 0
	var c := d.centre_of_mass()
	for s in bodies:
		if not is_instance_valid(s):
			continue
		var b := s as RigidBody3D
		if b.has_meta("scav_gone"):
			continue
		var kind := kind_of_body(b)
		if kind == "":
			continue
		var out := b.global_position - c
		out.z = 0.0
		var dir := out.normalized() if out.length() > 0.05 else Vector3(_rng.randf_range(-1.0, 1.0), 1.0, 0.0).normalized()
		dir = (dir + Vector3(0.0, 0.6, 0.0)).normalized()
		var v := b.linear_velocity + dir * _rng.randf_range(Tuning.SCAV_KO_BURST.x, Tuning.SCAV_KO_BURST.y)
		_spawn_token(kind, b.global_transform, v, b.angular_velocity, Tuning.SCAV_KO_LOCK_S)
		b.set_meta("scav_gone", true)
		b.collision_layer = 0
		b.collision_mask = 0
		b.freeze = true
		b.visible = false
		n += 1
	if n > 0:
		drops.append({"t": snappedf(fight_time, 0.01), "pi": d.player_index, "n": n, "why": "ko"})
		tokens_changed.emit(tokens().size())


func _check_over() -> void:
	if play_state == "play" and phase != Phase.OVER and alive_dolls().size() <= 1:
		_finish("last")


func _on_doll_ko(attacker: Node, record: Dictionary, victim: Doll) -> void:
	if phase == Phase.OVER or play_state != "play":
		return
	var feel := feel_enabled
	var human := _is_human(victim) or _is_human(attacker)
	var had := 0
	for k in victim.parts.keys():
		if KIND_OF.has(Doll.part_base_name(String(k))):
			had += 1
	feel_enabled = false
	super._on_doll_ko(attacker, record, victim)
	feel_enabled = feel
	var killer: Doll = null
	if attacker != null and is_instance_valid(attacker) and attacker is Doll and attacker != victim:
		killer = attacker as Doll
	var tv: Dictionary = tally.get(victim.player_index, _fresh_tally())
	tv["kos_taken"] = int(tv["kos_taken"]) + 1
	tv["parts"] = had
	tally[victim.player_index] = tv
	if killer != null and tally.has(killer.player_index):
		(tally[killer.player_index] as Dictionary)["kos"] = int(tally[killer.player_index]["kos"]) + 1
	_ko_t[victim.get_instance_id()] = fight_time
	kos.append({"t": snappedf(fight_time, 0.01), "victim": victim.player_index, "attacker": killer.player_index if killer != null else -1,
		"parts": had, "kind": String(record.get("kind", ""))})
	var id := victim.get_instance_id()
	if not _sweep_wait.has(id):
		_sweep_wait[id] = true
		call_deferred("_sweep", id)
	if feel and human:
		_camera_fx(30.0, record.get("position", victim.centre_of_mass()))
		if FxPreset.time_fx():
			_time_effect(Tuning.KO_SLOWMO_SCALE, Tuning.SCAV_KO_SLOWMO_S)


# --- удары ---

## Удар с человеком — как в бою (тряска, стоп-кадр, надписи); боты между собой — только сигнал hit, Заряд и тихий звук.
func on_hit(victim: Doll, attacker: Node, damage: float, kind: String, position: Vector3, combo_n: int, double_blow: bool, weapon_id: String, speed: float) -> void:
	if _is_human(victim) or _is_human(attacker):
		super.on_hit(victim, attacker, damage, kind, position, combo_n, double_blow, weapon_id, speed)
		return
	hit.emit(victim, attacker, damage, kind, position)
	if victim == null or not is_instance_valid(victim) or damage <= 0.0 or kind == "environment":
		return
	Charge.apply_hit(make_hit_ctx(victim, attacker, damage, kind, position, combo_n, double_blow, weapon_id, speed))
	if feel_enabled:
		_play_at("hit_m" if damage >= 10.0 else "hit_l", -10.0 + minf(damage, 30.0) * 0.2, randf_range(0.95, 1.1), position)


func _emit_env_slam(ctx: Dictionary) -> void:
	if _is_human(ctx.get("doll")):
		super._emit_env_slam(ctx)


func _play_at(layer: String, db: float, pitch: float, at: Vector3) -> void:
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


# --- итоги ---

## Ключ места: жив → деталей → запас → выбыл позже. Больше — лучше.
func place_key(d: Doll) -> Array:
	if d.alive:
		return [1.0, float(parts_count(d)), roundf(d.hp), 0.0]
	return [0.0, 0.0, 0.0, float(_ko_t.get(d.get_instance_id(), -1.0))]


## Итоги: базовые (статистика, медали) + места по place_key, победитель (первый, если не делит место), ничья, таблица tally.
func build_results(reason: String = "timeout") -> Dictionary:
	var r := super.build_results(reason)
	var all := dolls()
	all.sort_custom(func(a: Doll, b: Doll) -> bool:
		var ka := place_key(a)
		var kb := place_key(b)
		if _key_eq(ka, kb):
			return a.player_index < b.player_index
		return _key_gt(ka, kb))
	var ranks: Array = []
	for i in all.size():
		var tied := i > 0 and _key_eq(place_key(all[i]), place_key(all[i - 1]))
		ranks.append(ranks[i - 1] if tied else i)
	var winner: Doll = null
	if not all.is_empty() and (all[0] as Doll).alive and (all.size() < 2 or int(ranks[1]) != 0):
		winner = all[0]
	r["places"] = all
	r["ranks"] = ranks
	r["winner"] = winner
	r["draw"] = winner == null
	var medals: Dictionary = r.get("medals", {})
	medals.erase("Winner")
	medals.erase("Survivor")
	if winner != null:
		medals["Winner"] = winner
	r["medals"] = medals
	var t := tally.duplicate(true)
	for d in all:
		var dd := d as Doll
		if dd.alive and t.has(dd.player_index):
			(t[dd.player_index] as Dictionary)["parts"] = parts_count(dd)
	r["tally"] = t
	r["pickups"] = pickups.duplicate(true)
	r["kos_log"] = kos.duplicate(true)
	r["max_parts"] = Tuning.SCAV_MAX_PARTS
	return r


static func _key_eq(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not is_equal_approx(float(a[i]), float(b[i])):
			return false
	return true


## Лексикографически: a лучше b.
static func _key_gt(a: Array, b: Array) -> bool:
	for i in mini(a.size(), b.size()):
		if is_equal_approx(float(a[i]), float(b[i])):
			continue
		return float(a[i]) > float(b[i])
	return false
