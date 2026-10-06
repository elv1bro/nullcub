## Рукопашное оружие громилы «Стычки 3 на 3» (docs/plan-demo/SQUAD.md; автор 06.10: «добавим рукопашных бойцов как один из классов, и
## будет улучшаться ему оружие»). Узел-ребёнок куклы; у стрелков молчит (weapon_id ""). Оружие — настоящее оружие игры (Weapon:
## сковорода, меч, топор, булава, молот — Tuning.WEAPON, бьёт физикой через DollCombat, как в обычном бою), приваренное к кисти руки с
## оружием (ArmAssist куклы, Tuning.SQUAD_GUN_HAND) через WeaponPickup; рука тянется к курсору (игрок) или к цели (бот) — махи мышью
## бьют. Выпад (ЛКМ / I у игрока, мозг у бота) — толчок торса и кисти к точке: Δv SQUAD_LUNGE_DV × сила (усиление «выпад»), пауза
## SQUAD_LUNGE_COOLDOWN_S / сила. Новое оружие уровня — equip: прежнее убирается, новое ставится в руку.
## Match.respawn_doll создаёт узел заново: оружие и силу выпада берёт у матча (SquadMatch.kit). Оружие выбывшего гаснет через
## DROP_FREE_S, чтобы не валялось и его не подбирали.
class_name SquadMelee
extends Node

const DROP_FREE_S := 1.5

var doll: Doll
var weapon_id := ""
var weapon: Weapon = null
var lunge_mult := 1.0
var cooldown := 0.0
var lunges := 0
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
	var lunge_n := int((k.get("perks", {}) as Dictionary).get("lunge", 0))
	equip(String(k.get("melee", "")), pow(float(Tuning.SQUAD_PERKS["lunge"]["lunge"]), lunge_n))


func _exit_tree() -> void:
	_free_weapon()


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


## Оружие id (Weapon.IDS; "" — без оружия) и сила выпада. Прежнее оружие убирается.
func equip(id: String, mult: float = 1.0) -> void:
	lunge_mult = maxf(mult, 0.1)
	if id == weapon_id and is_instance_valid(weapon):
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
		_setup.call_deferred()   # рука ещё не собрана — позже
		weapon_id = ""
		return
	var w := Weapon.spawn(weapon_id, doll.get_parent(), a.grip_global(), 0.0)
	if w == null:
		weapon_id = ""
		return
	w.add_to_group("squad_melee_weapon")
	if pickup().attach(a.part_name, w):
		weapon = w
	else:
		w.queue_free()
		weapon_id = ""


func _free_weapon() -> void:
	if weapon != null and is_instance_valid(weapon):
		if weapon.is_held():
			weapon.drop()
		weapon.queue_free()
	weapon = null


## Выбыл: оружие выпадает (Doll.break_apart → WeaponPickup.drop_all) и гаснет через DROP_FREE_S.
func _on_ko() -> void:
	var w := weapon
	weapon = null
	if w != null and is_instance_valid(w):
		get_tree().create_timer(DROP_FREE_S).timeout.connect(func() -> void:
			if is_instance_valid(w):
				w.queue_free())


func can_lunge() -> bool:
	return weapon_id != "" and cooldown <= 0.0 and doll.alive and not doll.is_broken() and doll.control_enabled and not doll.is_stunned()


## Выпад к точке at: торсу — Δv SQUAD_LUNGE_DV × сила в сторону точки, кисти с оружием — больше (мах). false — рано или нельзя.
func lunge(at: Vector3) -> bool:
	if not can_lunge():
		return false
	var c := doll.centre_of_mass()
	var d := Vector3(at.x - c.x, at.y - c.y, 0.0)
	if d.length_squared() < 1e-4:
		return false
	d = d.normalized()
	var dv := Tuning.SQUAD_LUNGE_DV * lunge_mult
	for b in doll.parts.values():
		var rb := b as RigidBody3D
		if rb != null and is_instance_valid(rb):
			rb.linear_velocity += d * dv
	var a := arm()
	if a != null and a.part != null and is_instance_valid(a.part):
		a.part.linear_velocity += d * dv * (Tuning.SQUAD_LUNGE_HAND - 1.0)
	cooldown = Tuning.SQUAD_LUNGE_COOLDOWN_S / lunge_mult
	lunges += 1
	if _match != null and _match.has_method("lunge_sound"):
		_match.call("lunge_sound", doll)
	return true


func _physics_process(dt: float) -> void:
	cooldown = maxf(cooldown - dt, 0.0)


## Доля паузы выпада 0..1 (HUD): 1 — готов.
func ready_frac() -> float:
	var full := Tuning.SQUAD_LUNGE_COOLDOWN_S / lunge_mult
	return 1.0 - clampf(cooldown / maxf(full, 0.01), 0.0, 1.0)
