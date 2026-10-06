## Оружие бойца «Стычки 3 на 3» (docs/plan-demo/SQUAD.md, автор 05.10: «первое оружие у всех пистолет, потом ветка из 3 развитий;
## стрелять на активную клавишу, пока зажата; перезарядка и сколько осталось патронов; между выстрелами минимальная пауза;
## закончились пули — рукопашная»). Узел-ребёнок куклы. Числа — Tuning.SQUAD_WEAPONS × усиления (SquadMatch.loadout).
##   • ствол в руке с оружием (ArmAssist куклы — кисть Tuning.SQUAD_GUN_HAND команды) и смотрит по руке: плечо → кисть. У игрока
##     рука всегда тянется к курсору (площадка), у бота — к цели;
##   • trigger — «спуск зажат» на этот тик (P1 — клавиша, бот — мозг): выстрел не чаще interval; магазин mag, запас reserve;
##     пустой магазин — перезарядка reload_s сама (или reload()), пока она идёт, ствол молчит; нет ни магазина, ни запаса —
##     out_of_ammo(), только рукопашная;
##   • выстрел — pellets пуль-шариков с разбросом spread_deg из дула (кончик ствола); пуля летит со скоростью speed (автор 05.10:
##     «снаряды именно как шарики, а не линии») и каждый тик проверяет свой отрезок пути лучом — свои детали не задевает; пробитие
##     (pierce) — летит дальше сквозь бойцов; в тело — импульс, в бойца — SquadMatch.bullet_hit (урон без тряски камеры), Breakable —
##     урон (ящик ломается, взрывная бочка загорается); прошла range — гаснет; стрелку — отдача в кисть, вспышка у дула, звук;
##   • молчит, пока кукла не жива, разбита, без управления (отсчёт, итоги) или в стане.
## Match.respawn_doll создаёт узел заново (script.new()): оружие и усиления он берёт у матча (SquadMatch.loadout по player_index),
## патроны — полные.
class_name SquadGun
extends Node

signal fired(origin: Vector3, dir: Vector3)
signal reload_started(seconds: float)

const FLASH_LIFE_S := 0.05
const PIERCE_MAX := 3
const MODEL_SCALE := 1.5        # модель ствола крупнее руки: на общем плане 64-метровой карты ствол в 0.3 м не читается

var doll: Doll
var weapon := ""
var def: Dictionary = {}
var mag := 0
var reserve := 0
var mag_max := 0
var reserve_max := 0
## Спуск зажат в этот тик (P1 — клавиша, бот — мозг).
var trigger := false
var cooldown := 0.0
## Осталось перезаряжаться (с); 0 — не перезаряжается.
var reloading := 0.0
## Для проб и HUD.
var shots := 0
var pellets_hit := 0
var damage_dealt := 0.0
var _rng := RandomNumberGenerator.new()
var _model: Node3D = null
var _flash: MeshInstance3D = null
var _flash_t := 0.0
var _arm: ArmAssist = null
var _match: Node = null
## Пули в полёте: [{pos, vel, left (м до range), ex (RID, которые не задевать), pierced, node}].
var balls: Array = []
static var _glow: Dictionary = {}   # цвет шарика → материал (не новый на каждую пулю)
static var _ball_mesh: SphereMesh = null


func _ready() -> void:
	doll = get_parent() as Doll
	if doll == null:
		queue_free()
		return
	for c in doll.get_children():   # Match.respawn_doll копирует узел — второй экземпляр уходит сам
		if c is SquadGun and c != self and not c.is_queued_for_deletion():
			queue_free()
			return
	_rng.seed = hash(String(doll.name)) ^ 0x6a17
	_match = get_tree().get_first_node_in_group(Match.GROUP)
	var lo: Dictionary = _match.call("loadout", doll.player_index) if _match != null and _match.has_method("loadout") else {}
	equip(String(lo.get("weapon", Tuning.SQUAD_START_WEAPON)), lo.get("perks", {}))


## Оружие id с усилениями perks ({id усиления: раз}); патроны — полные.
func equip(id: String, perks: Dictionary = {}) -> void:
	weapon = id if Tuning.SQUAD_WEAPONS.has(id) else Tuning.SQUAD_START_WEAPON
	def = stats_of(weapon, perks)
	mag_max = int(def["mag"])
	reserve_max = int(def["reserve"])
	mag = mag_max
	reserve = reserve_max
	cooldown = 0.0
	reloading = 0.0
	_build_model()


## Числа оружия id с усилениями (множители складываются умножением); mag и reserve — целые, не меньше 1.
static func stats_of(id: String, perks: Dictionary = {}) -> Dictionary:
	var d: Dictionary = (Tuning.SQUAD_WEAPONS.get(id, Tuning.SQUAD_WEAPONS[Tuning.SQUAD_START_WEAPON]) as Dictionary).duplicate()
	for p in perks:
		var pd: Dictionary = Tuning.SQUAD_PERKS.get(p, {})
		var mult: Dictionary = pd.get("mult", {})
		for k in mult:
			d[k] = float(d[k]) * pow(float(mult[k]), int(perks[p]))
	d["mag"] = maxi(int(round(float(d["mag"]))), 1)
	d["reserve"] = maxi(int(round(float(d["reserve"]))), 0)
	return d


func out_of_ammo() -> bool:
	return mag <= 0 and reserve <= 0 and reloading <= 0.0


## Перезарядка (клавиша): магазин не полный и запас есть.
func reload() -> bool:
	if reloading > 0.0 or mag >= mag_max or reserve <= 0:
		return false
	reloading = float(def["reload_s"])
	reload_started.emit(reloading)
	return true


## Доля перезарядки 0..1 (для HUD), −1 — не перезаряжается.
func reload_progress() -> float:
	if reloading <= 0.0:
		return -1.0
	return 1.0 - reloading / maxf(float(def["reload_s"]), 0.01)


## Добавить патроны в запас (ящик): доля полного запаса оружия, не выше полного. Возвращает, сколько добавлено.
func add_ammo(frac: float) -> int:
	var before := reserve
	reserve = mini(reserve + maxi(int(ceil(float(reserve_max) * frac)), 1), reserve_max)
	if mag <= 0 and reloading <= 0.0:
		reload()
	return reserve - before


func arm() -> ArmAssist:
	if _arm == null or not is_instance_valid(_arm):
		_arm = null
		for c in doll.get_children():
			if c is ArmAssist and not c.is_queued_for_deletion():
				_arm = c
				break
	return _arm


## Дуло и направление ствола: [origin, dir] (dir — плечо → кисть, в плоскости боя) или пусто (руки нет / не готова).
func aim_ray() -> Array:
	var a := arm()
	if a == null or a.part == null or not is_instance_valid(a.part):
		return []
	var root := a.root_point()
	var grip := a.grip_global()
	var dir := grip - root
	dir.z = 0.0
	if dir.length_squared() < 1e-4:
		return []
	dir = dir.normalized()
	var o := grip + dir * float(def.get("len", 0.3)) * MODEL_SCALE   # дуло — кончик модели ствола
	return [Vector3(o.x, o.y, 0.0), dir]


func can_fire() -> bool:
	return doll.alive and not doll.is_broken() and doll.control_enabled and not doll.is_stunned() and mag > 0 \
		and cooldown <= 0.0 and reloading <= 0.0


func _physics_process(dt: float) -> void:
	if doll == null or not is_instance_valid(doll) or def.is_empty():
		return
	cooldown = maxf(cooldown - dt, 0.0)
	if reloading > 0.0:
		reloading -= dt
		if reloading <= 0.0:
			reloading = 0.0
			var take := mini(mag_max - mag, reserve)
			mag += take
			reserve -= take
	elif mag <= 0 and reserve > 0 and doll.alive:
		reload()
	if trigger and can_fire():
		_fire()
	_step_balls(dt)


func _fire() -> void:
	var ray := aim_ray()
	if ray.is_empty():
		return
	var o := ray[0] as Vector3
	var dir := ray[1] as Vector3
	mag -= 1
	cooldown = float(def["interval"])
	shots += 1
	var ex: Array[RID] = []
	for p in doll.parts.values():
		if is_instance_valid(p):
			ex.append((p as RigidBody3D).get_rid())
	for i in int(def["pellets"]):
		var d := dir.rotated(Vector3.BACK, deg_to_rad(_rng.randf_range(-1.0, 1.0) * float(def["spread_deg"])))
		_spawn_ball(o, d, ex.duplicate())
	var hand := arm().part if arm() != null else null
	if hand != null and is_instance_valid(hand):
		hand.apply_impulse(-dir * float(def["recoil"]), o - hand.global_position)
	_show_flash(o)
	fired.emit(o, dir)
	if _match != null and _match.has_method("gun_sound"):
		_match.call("gun_sound", doll, def)


## Пуля-шарик: светящаяся сфера своего цвета, летит из o по d со скоростью оружия.
func _spawn_ball(o: Vector3, d: Vector3, ex: Array[RID]) -> void:
	var mi := MeshInstance3D.new()
	if _ball_mesh == null:
		_ball_mesh = SphereMesh.new()
		_ball_mesh.radius = 0.5
		_ball_mesh.height = 1.0
		_ball_mesh.radial_segments = 10
		_ball_mesh.rings = 6
	mi.mesh = _ball_mesh
	var col: Color = def["tracer"]
	var key := col.to_html()
	if not _glow.has(key):
		_glow[key] = _mat(col, 0.0, 4.0)
	mi.material_override = _glow[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.scale = Vector3.ONE * float(def["ball"]) * 2.0
	add_child(mi)
	mi.global_position = o
	balls.append({"pos": o, "vel": d * float(def["speed"]), "left": float(def["range"]), "ex": ex, "pierced": 0, "node": mi,
		"weapon": weapon, "damage": float(def["damage"]), "impulse": float(def["impulse"]), "pierce": bool(def["pierce"])})


## Полёт пуль за тик: отрезок пути — луч (свои детали и уже пробитые бойцы — мимо); попала — урон и импульс, пробивающая летит
## дальше; прошла range — гаснет.
func _step_balls(dt: float) -> void:
	if balls.is_empty():
		return
	var space := doll.get_world_3d().direct_space_state if is_instance_valid(doll) and doll.is_inside_tree() else null
	var i := 0
	while i < balls.size():
		var b: Dictionary = balls[i]
		var start := b["pos"] as Vector3
		var from := start
		var step := (b["vel"] as Vector3) * dt
		var len := minf(step.length(), float(b["left"]))
		var to := from + step.normalized() * len
		var done := len <= 0.001 or space == null
		var guard := 0
		while not done and guard < PIERCE_MAX + 2:
			guard += 1
			var q := PhysicsRayQueryParameters3D.create(from, to)
			q.exclude = b["ex"]
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				break
			var at: Vector3 = hit["position"]
			var body := hit["collider"] as Node
			var victim := _doll_of(body)
			var d := (b["vel"] as Vector3).normalized()
			if body is RigidBody3D and not (body as RigidBody3D).freeze:
				(body as RigidBody3D).apply_impulse(d * float(b["impulse"]), at - (body as RigidBody3D).global_position)
			if victim != null and victim != doll:
				var dealt := 0.0
				if _match != null and _match.has_method("bullet_hit"):
					dealt = float(_match.call("bullet_hit", victim, doll, float(b["damage"]), String(body.name), at, hit["normal"],
						String(b["weapon"])))
				pellets_hit += 1
				damage_dealt += dealt
				if bool(b["pierce"]) and int(b["pierced"]) < PIERCE_MAX:
					b["pierced"] = int(b["pierced"]) + 1
					var ex: Array[RID] = b["ex"]
					for p in victim.parts.values():   # дальше — сквозь всего бойца
						if is_instance_valid(p):
							ex.append((p as RigidBody3D).get_rid())
					from = at
					continue
			elif body is Breakable:
				(body as Breakable).take_damage(float(b["damage"]))
			to = at
			done = true
		b["left"] = float(b["left"]) - start.distance_to(to) if not done else 0.0
		b["pos"] = to
		var node := b["node"] as Node3D
		if is_instance_valid(node):
			node.global_position = to
		if done or float(b["left"]) <= 0.0:
			if is_instance_valid(node):
				node.queue_free()
			balls.remove_at(i)
		else:
			i += 1


## Пуль в полёте (пробы).
func balls_in_flight() -> int:
	return balls.size()


static func _doll_of(n: Node) -> Doll:
	while n != null:
		if n is Doll:
			return n as Doll
		n = n.get_parent()
	return null


# --- вид ---

func _process(delta: float) -> void:
	if _flash != null:
		_flash_t -= delta
		_flash.visible = _flash_t > 0.0
	if _model == null:
		return
	var ray := aim_ray()
	var show := doll != null and is_instance_valid(doll) and doll.alive and not ray.is_empty()
	_model.visible = show
	if not show:
		return
	var dir := ray[1] as Vector3
	var a := arm()
	var grip := a.grip_global()
	# ствол вдоль +X модели: базис — x по направлению, y вверх от плоскости (z к камере)
	var x := dir
	var z := Vector3.BACK
	var y := z.cross(x).normalized()
	_model.global_transform = Transform3D(Basis(x, y, z).scaled(Vector3.ONE * MODEL_SCALE), Vector3(grip.x, grip.y, 0.06))


## Модель ствола из простых форм (проба: своих моделей оружия нет): корпус, ствол, рукоять, магазин / барабан / прицел по виду.
func _build_model() -> void:
	if _model != null and is_instance_valid(_model):
		_model.queue_free()
	_model = Node3D.new()
	_model.name = "GunModel"
	_model.top_level = true
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)
	var metal := _mat(Color(0.16, 0.17, 0.19), 0.55)
	var team := SquadMatch.team_colour(SquadMatch.team_of(doll)) if doll != null else Color.WHITE
	var accent := _mat(team.lightened(0.15), 0.4)
	var l := float(def.get("len", 0.3))
	match weapon:
		"sawnoff", "shotgun":
			for k in [-1.0, 1.0]:
				_part(_model, CylinderMesh.new(), Vector3(l * 0.5, 0.0, k * 0.018), Vector3(0.022, l, 0.022), metal, true)
			_part(_model, BoxMesh.new(), Vector3(-0.04, -0.03, 0.0), Vector3(0.14, 0.05, 0.06), accent)
		"rail":
			_part(_model, BoxMesh.new(), Vector3(l * 0.45, 0.0, 0.0), Vector3(l, 0.05, 0.05), metal)
			for k in 3:
				_part(_model, CylinderMesh.new(), Vector3(l * (0.3 + 0.22 * k), 0.0, 0.0), Vector3(0.075, 0.03, 0.075),
					_mat(Color(0.35, 0.9, 1.0), 0.2, 3.0), true)
		_:
			_part(_model, BoxMesh.new(), Vector3(l * 0.32, 0.01, 0.0), Vector3(l * 0.64, 0.06, 0.045), metal)
			_part(_model, CylinderMesh.new(), Vector3(l * 0.78, 0.015, 0.0), Vector3(0.022, l * 0.44, 0.022), metal, true)
			_part(_model, BoxMesh.new(), Vector3(0.0, -0.05, 0.0), Vector3(0.045, 0.09, 0.04), accent)
			if weapon in ["smg", "mg"]:
				_part(_model, BoxMesh.new(), Vector3(l * 0.3, -0.07, 0.0), Vector3(0.04, 0.1 if weapon == "smg" else 0.14, 0.035), accent)
			if weapon == "mg":
				_part(_model, CylinderMesh.new(), Vector3(l * 0.3, -0.06, 0.0), Vector3(0.12, 0.05, 0.12), metal)
			if weapon == "rifle":
				_part(_model, CylinderMesh.new(), Vector3(l * 0.35, 0.06, 0.0), Vector3(0.035, 0.2, 0.035), accent, true)
	_flash = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	_flash.mesh = sm
	_flash.material_override = _mat(Color(1.0, 0.85, 0.45), 0.0, 6.0)
	_flash.top_level = true
	_flash.visible = false
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flash)


func _part(parent: Node3D, mesh: PrimitiveMesh, pos: Vector3, size: Vector3, mat: Material, along_x := false) -> void:
	var mi := MeshInstance3D.new()
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = size
	elif mesh is CylinderMesh:
		(mesh as CylinderMesh).top_radius = size.x * 0.5
		(mesh as CylinderMesh).bottom_radius = size.x * 0.5
		(mesh as CylinderMesh).height = size.y
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	mi.position = pos
	if along_x:
		mi.rotation_degrees = Vector3(0.0, 0.0, 90.0)   # цилиндр стоит по Y — кладём вдоль ствола
	parent.add_child(mi)


static func _mat(c: Color, rough: float, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = 0.3 if emission <= 0.0 else 0.0
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _show_flash(at: Vector3) -> void:
	if _flash == null:
		return
	_flash.global_position = at
	_flash.visible = true
	_flash_t = FLASH_LIFE_S
