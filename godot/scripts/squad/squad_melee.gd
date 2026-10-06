## Рукопашное оружие громилы «Стычки 3 на 3» (docs/plan-demo/SQUAD.md; автор 06.10: «рукопашные — один из классов, и будет
## улучшаться ему оружие»). Узел-ребёнок куклы; у стрелков молчит (weapon_id ""). Оружие — настоящее оружие игры (Weapon: сковорода,
## молот, меч, топор — Tuning.WEAPON, бьёт физикой через DollCombat, как в обычном бою), приваренное к кисти руки с оружием (ArmAssist
## куклы, Tuning.SQUAD_GUN_HAND) через WeaponPickup; рука тянется к курсору (игрок) или к цели (бот) — махи мышью бьют.
## Полёт (автор 06.10: «выпад сделай как молот Тора — резкое ускорение на 5 секунд в сторону оружия»): ЛКМ зажата — оружие тянет
## бойца к точке (курсор игрока, цель бота): скорость до SQUAD_DASH_SPEED × сила, разгон SQUAD_DASH_ACCEL, кисть с оружием впереди
## (× SQUAD_DASH_HAND); полёт длится, пока держишь, но не дольше SQUAD_DASH_S, потом пауза SQUAD_DASH_COOLDOWN_S. Сила и пауза — по
## оружию (Tuning.SQUAD_MELEE: меч быстрее и чаще, молот тяжелее), усилениям «полёт» и бонусу «форсаж». Потолок урона удара в полёте
## и редкость ударов по одному бойцу — SquadMatch.adjust_hit_damage, ударная волна молота — SquadMatch.on_hit.
## Своё у оружия: топору — износ суставов × joint_mult (PartMods «wear_mult» на теле оружия).
## Match.respawn_doll создаёт узел заново: оружие и силу берёт у матча (SquadMatch.kit). Оружие выбывшего гаснет через DROP_FREE_S.
class_name SquadMelee
extends Node

signal dash_started
signal dash_ended

const DROP_FREE_S := 1.5
const DASH_TAIL_S := 0.3          # после конца полёта удар ещё считается «в полёте» (инерция)

var doll: Doll
var weapon_id := ""
var weapon: Weapon = null
## Сила полёта от усилений «полёт» (× скорости, пауза делится).
var dash_mult := 1.0
var cooldown := 0.0
var dashing := false
var dash_t := 0.0
var dash_at := Vector3.ZERO
var dashes := 0
## Конец последнего полёта (doll._time) — удар сразу после ещё «в полёте».
var dash_end_t := -10.0
## Ударная волна молота уже была в этом полёте.
var wave_done := false
var _match: Node = null


func _ready() -> void:
	doll = get_parent() as Doll
	if doll == null:
		queue_free()
		return
	for c in doll.get_children():   # Match.respawn_doll копирует узел — второй экземпляр уходит сам
		if c is SquadMelee and c != self and not c.is_queued_for_deletion():
			queue_free()
			return
	_match = get_tree().get_first_node_in_group(Match.GROUP)
	doll.knocked_out.connect(func(_a: Node, _r: Dictionary) -> void: _on_ko())
	_setup.call_deferred()   # после всех детей-копий (рука, WeaponPickup) и сборки тела


func _setup() -> void:
	if not is_instance_valid(doll):
		return
	var k: Dictionary = _match.call("kit", doll.player_index) if _match != null and _match.has_method("kit") else {}
	var n := int((k.get("perks", {}) as Dictionary).get("dash", 0))
	equip(String(k.get("melee", "")), pow(float(Tuning.SQUAD_PERKS["dash"]["dash"]), n))


func _exit_tree() -> void:
	_free_weapon()


## Свойство оружия громилы (Tuning.SQUAD_MELEE[weapon_id][key]) или def.
func prop(key: String, def: Variant = 1.0) -> Variant:
	return (Tuning.SQUAD_MELEE.get(weapon_id, {}) as Dictionary).get(key, def)


## Подбор оружия куклы (свой, без автоподбора: валяющееся чужое оружие громила сам не хватает).
func pickup() -> WeaponPickup:
	for c in doll.get_children():
		if c is WeaponPickup and not c.is_queued_for_deletion():
			(c as WeaponPickup).auto_pickup = false
			return c
	var p := WeaponPickup.new()
	p.name = "WeaponPickup"
	p.auto_pickup = false
	doll.add_child(p)
	return p


func arm() -> ArmAssist:
	for c in doll.get_children():
		if c is ArmAssist and not c.is_queued_for_deletion():
			return c
	return null


## Оружие id (Weapon.IDS; "" — без оружия) и сила полёта. Прежнее оружие убирается.
func equip(id: String, mult: float = 1.0) -> void:
	dash_mult = maxf(mult, 0.1)
	if id == weapon_id and is_instance_valid(weapon) and weapon.is_held():
		return
	_free_weapon()
	weapon_id = id if Weapon.IDS.has(id) else ""
	if weapon_id == "" or not doll.alive:
		for c in doll.get_children():
			if c is WeaponPickup:
				(c as WeaponPickup).auto_pickup = false
		return
	var a := arm()
	if a == null or a.part == null or not is_instance_valid(a.part):
		if a != null and a.part_name != "" and not doll.parts.has(a.part_name):
			return   # руки нет (оторвана): оружие вернётся с рукой (rearm из SquadMatch.restore_arm)
		weapon_id = ""
		_setup.call_deferred()   # рука ещё не собрана — позже
		return
	var w := Weapon.spawn(weapon_id, doll.get_parent(), a.grip_global(), 0.0)
	if w == null:
		weapon_id = ""
		return
	w.add_to_group("squad_melee_weapon")
	var jm := float(prop("joint_mult", 1.0))
	if jm != 1.0:
		w.set_meta(PartMods.META, {"wear_mult": jm})   # топор рубит суставы (Doll.take_damage → износ × wear_mult бьющего тела)
	if pickup().attach(a.part_name, w):
		weapon = w
	else:
		w.queue_free()
		weapon_id = ""


## Рука вернулась (SquadMatch.restore_arm): оружие снова в кисть — лежащее приваривается, пропавшее создаётся заново.
func rearm() -> void:
	if weapon_id == "":
		return
	var a := arm()
	if a == null or a.part == null or not is_instance_valid(a.part):
		return
	if is_instance_valid(weapon) and not weapon.is_held():
		weapon.global_position = a.grip_global()
		if pickup().attach(a.part_name, weapon):
			return
	var id := weapon_id
	weapon_id = ""
	equip(id, dash_mult)


func _free_weapon() -> void:
	if weapon != null and is_instance_valid(weapon):
		if weapon.is_held():
			weapon.drop()
		weapon.queue_free()
	weapon = null


## Выбыл: оружие выпадает (Doll.break_apart → WeaponPickup.drop_all) и гаснет через DROP_FREE_S.
func _on_ko() -> void:
	end_dash()
	var w := weapon
	weapon = null
	if w != null and is_instance_valid(w):
		get_tree().create_timer(DROP_FREE_S).timeout.connect(func() -> void:
			if is_instance_valid(w):
				w.queue_free())


## Оружие в руке (рука на месте и держит его).
func armed() -> bool:
	return weapon_id != "" and is_instance_valid(weapon) and weapon.is_held()


func can_dash() -> bool:
	return armed() and not dashing and cooldown <= 0.0 and doll.alive and not doll.is_broken() and doll.control_enabled \
		and not doll.is_stunned()


## Скорость полёта (м/с): база × оружие × усиления × бонус «форсаж».
func dash_speed() -> float:
	return Tuning.SQUAD_DASH_SPEED * float(prop("speed", 1.0)) * dash_mult * _haste()


## Пауза после полёта (с).
func dash_cooldown() -> float:
	return Tuning.SQUAD_DASH_COOLDOWN_S * float(prop("cooldown", 1.0)) / dash_mult / _haste()


func _haste() -> float:
	return float(_match.call("boost_mult", doll, "haste")) if _match != null and _match.has_method("boost_mult") else 1.0


## Полёт к точке at (курсор / цель): начать (ЛКМ нажата) — false, если рано или нельзя.
func start_dash(at: Vector3) -> bool:
	if not can_dash():
		return false
	dashing = true
	dash_t = 0.0
	dash_at = at
	wave_done = false
	dashes += 1
	if _match != null and _match.has_method("lunge_sound"):
		_match.call("lunge_sound", doll)
	dash_started.emit()
	return true


## Полёт идёт: точка, куда тянет оружие (каждый тик, пока ЛКМ зажата).
func steer_dash(at: Vector3) -> void:
	dash_at = at


## Конец полёта (отпустил, кончилось время, выбыл, стан) — пауза.
func end_dash() -> void:
	if not dashing:
		return
	dashing = false
	dash_end_t = doll._time if is_instance_valid(doll) else 0.0
	cooldown = dash_cooldown()
	if is_instance_valid(doll):
		doll.speed_cap_mult = 1.0
		doll.brake_off = false
	dash_ended.emit()


## Удар сейчас считается ударом в полёте (полёт или DASH_TAIL_S после).
func in_dash() -> bool:
	return dashing or (is_instance_valid(doll) and doll._time - dash_end_t <= DASH_TAIL_S)


func _physics_process(dt: float) -> void:
	cooldown = maxf(cooldown - dt, 0.0)
	if not dashing:
		return
	if not doll.alive or doll.is_broken() or doll.is_stunned() or not doll.control_enabled or not armed():
		end_dash()
		return
	dash_t += dt
	if dash_t >= Tuning.SQUAD_DASH_S:
		end_dash()
		return
	var c := doll.centre_of_mass()
	var d := Vector3(dash_at.x - c.x, dash_at.y - c.y, 0.0)
	if d.length() < 0.6:
		d = Vector3.ZERO   # долетел до точки — висит у неё, тянет только оружие
	else:
		d = d.normalized()
	var speed := dash_speed()
	doll.speed_cap_mult = maxf(speed / maxf(ControlFeel.max_speed(), 0.1), 1.0) * 1.1   # потолок скорости тяги не режет полёт
	doll.brake_off = true   # тормоз торса без ввода не гасит полёт
	var a := arm()
	var hand: RigidBody3D = a.part if a != null and a.part != null and is_instance_valid(a.part) else null
	var step := Tuning.SQUAD_DASH_ACCEL * dt
	for b in doll.parts.values():
		var rb := b as RigidBody3D
		if rb == null or not is_instance_valid(rb):
			continue
		var lead := Tuning.SQUAD_DASH_HAND if rb == hand else 1.0
		var want := d * speed * lead
		var dv := (want - rb.linear_velocity)
		dv.z = 0.0
		if d == Vector3.ZERO:
			dv *= 0.25   # у точки — гасит скорость, а не разгоняет
		rb.linear_velocity += dv.limit_length(step * lead)


## Доля паузы полёта 0..1 (HUD): 1 — готов; во время полёта — сколько осталось лететь.
func ready_frac() -> float:
	if dashing:
		return 1.0 - clampf(dash_t / Tuning.SQUAD_DASH_S, 0.0, 1.0)
	var full := dash_cooldown()
	return 1.0 - clampf(cooldown / maxf(full, 0.01), 0.0, 1.0)
