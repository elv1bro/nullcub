## Оружие бойца «Стычки 3 на 3» (docs/plan-demo/SQUAD.md, автор 05.10: «стрелять на активную клавишу, пока зажата; перезарядка и
## сколько осталось патронов; между выстрелами минимальная пауза; закончились пули — рукопашная»). Узел-ребёнок куклы. Числа —
## Tuning.SQUAD_WEAPONS × усиления (SquadMatch.kit по классу, ветке и уровню).
##   • ствол в руке с оружием (ArmAssist куклы — кисть Tuning.SQUAD_GUN_HAND команды) и смотрит по руке: плечо → кисть. У игрока
##     рука всегда тянется к курсору (площадка), у бота — к цели. Руку оторвало (прочность суставов) — ствола нет, пока ящик не вернёт;
##   • trigger — «спуск зажат» на этот тик (P1 — клавиша, бот — мозг): выстрел не чаще interval; магазин mag, запас reserve;
##     пустой магазин — перезарядка reload_s сама (или reload()), пока она идёт, ствол молчит; нет ни магазина, ни запаса —
##     out_of_ammo(), только рукопашная;
##   • выстрел — pellets пуль с разбросом spread_deg из дула (кончик ствола); пуля — трассер, летит со скоростью speed и каждый тик
##     проверяет свой отрезок пути лучом — свои детали не задевает; пробитие (pierce) — дальше сквозь бойцов; в тело — импульс, в
##     бойца — SquadMatch.bullet_hit (урон без тряски камеры), Breakable — урон (ящик ломается, бочка загорается); прошла range — гаснет;
##     стрелку — отдача в кисть, вспышка у дула, звук;
##   • гаусс (def.charge_s > 0, автор 06.10: «мощность зависит от того, сколько было зажато; бьёт сквозь всех, но каждое препятствие —
##     минус процент урона»): пока спуск зажат — копится charge (0..1 за charge_s), отпустил — выстрел с уроном damage_min…damage по
##     заряду (и толще трассер); пуля летит сквозь бойцов и стены (through_walls): каждая стена или пропс — × (1 − wall_loss), каждый
##     боец — × (1 − body_loss);
##   • state(), cooldown_frac(), aim_end() — для прицела HUD (готов / пауза между выстрелами / перезарядка / пусто / заряд; куда долетит);
##   • молчит, пока кукла не жива, разбита, без управления (отсчёт, итоги) или в стане.
## Match.respawn_doll создаёт узел заново (script.new()): оружие и усиления он берёт у матча, патроны — полные. У громилы ствола нет:
## disarm() — узел молчит, модели нет. Модель ствола — build_model (простые формы; её же рисует картинка оружия SquadIcons).
class_name SquadGun
extends Node

signal fired(origin: Vector3, dir: Vector3)
signal reload_started(seconds: float)

const FLASH_LIFE_S := 0.05
const PIERCE_MAX := 3
const THROUGH_MAX := 8            # гаусс: сколько стен и бойцов пуля проходит за полёт
const THROUGH_STEP := 0.04        # м: шаг внутрь стены после попадания (луч из-под поверхности её уже не видит)
const GAUSS_MIN_FRAC := 0.08      # заряд меньше — выстрел не уходит (случайный щелчок)
const MODEL_SCALE := 1.5          # модель ствола крупнее руки: на общем плане 64-метровой карты ствол в 0.3 м не читается

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
## Заряд гаусса 0..1 (копится, пока спуск зажат; отпустил — выстрел).
var charge := 0.0
var _held := false
## Для проб и HUD.
var shots := 0
var pellets_hit := 0
var damage_dealt := 0.0
var walls_pierced := 0
var last_charge := 0.0
var _rng := RandomNumberGenerator.new()
var _model: Node3D = null
var _flash: MeshInstance3D = null
var _flash_t := 0.0
var _arm: ArmAssist = null
var _match: Node = null
## Пули в полёте: [{pos, vel, left (м до range), ex (RID, которые не задевать), pierced, through, node, damage…}].
var balls: Array = []
static var _glow: Dictionary = {}   # цвет оружия / команда / яркость → материал (не новый на каждую пулю)
static var _streak_mesh: QuadMesh = null
static var _streak_shader: Shader = null
## Толщина квада трассера × ball оружия (ядро — треть, остальное — ореол) и длина хвоста × streak.
const WIDTH_MULT := 3.2
const STREAK_MULT := 1.5
## Трассер пули: квад в плоскости боя вдоль полёта; голова (UV.x = 1) — горячее белое ядро цвета оружия (tint), вокруг — ореол
## цвета команды (rim: видно, чья пуля), хвост гаснет к UV.x = 0. Смешение обычное, не сложение, и днём яркость около 1: на светлом
## камне сложение и пересвет выбеливали трассер в бледную нитку (кадры 06.10). Ночью ярче — светится (ProvingGround.night_now).
const STREAK_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.4, 1.0);
uniform vec4 rim : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform float energy = 1.1;
void fragment() {
	float along = UV.x;
	float across = abs(UV.y - 0.5) * 2.0;
	float tail = pow(along, 1.2);
	float core = 1.0 - smoothstep(0.2, 0.45, across);
	float halo = 1.0 - smoothstep(0.45, 1.0, across);
	float tip = smoothstep(0.75, 1.0, along);
	vec3 hot = mix(tint.rgb, vec3(1.0), 0.35 + 0.45 * tip);
	ALBEDO = mix(rim.rgb, hot, core) * energy * (0.9 + tip * 0.5);
	ALPHA = clamp(max(core, halo * 0.85) * (0.25 + 0.75 * tail) + tip * core * 0.5, 0.0, 1.0);
}
"""
const ENERGY_DAY := 1.1
const ENERGY_NIGHT := 2.2


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
	var k: Dictionary = _match.call("kit", doll.player_index) if _match != null and _match.has_method("kit") else {"weapon": Tuning.SQUAD_START_WEAPON}
	if String(k.get("weapon", "")) == "":
		disarm()
	else:
		equip(String(k["weapon"]), k.get("perks", {}))


## Без ствола (рукопашный класс): стрелять нечем, модели нет, патронов нет.
func disarm() -> void:
	weapon = ""
	def = {}
	mag = 0
	reserve = 0
	mag_max = 0
	reserve_max = 0
	reloading = 0.0
	charge = 0.0
	trigger = false
	if _model != null and is_instance_valid(_model):
		_model.queue_free()
	_model = null


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
	charge = 0.0
	_build_model()


## Числа оружия id с усилениями (множители складываются умножением); mag и reserve — целые, не меньше 1.
static func stats_of(id: String, perks: Dictionary = {}) -> Dictionary:
	var d: Dictionary = (Tuning.SQUAD_WEAPONS.get(id, Tuning.SQUAD_WEAPONS[Tuning.SQUAD_START_WEAPON]) as Dictionary).duplicate()
	for p in perks:
		var pd: Dictionary = Tuning.SQUAD_PERKS.get(p, {})
		var mult: Dictionary = pd.get("mult", {})
		for k in mult:
			if d.has(k):
				d[k] = float(d[k]) * pow(float(mult[k]), int(perks[p]))
	d["mag"] = maxi(int(round(float(d["mag"]))), 1)
	d["reserve"] = maxi(int(round(float(d["reserve"]))), 0)
	return d


func out_of_ammo() -> bool:
	return weapon != "" and mag <= 0 and reserve <= 0 and reloading <= 0.0


## Перезарядка (клавиша): магазин не полный и запас есть.
func reload() -> bool:
	if weapon == "" or reloading > 0.0 or mag >= mag_max or reserve <= 0:
		return false
	reloading = float(def["reload_s"])
	charge = 0.0
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


## Дуло и направление ствола: [origin, dir] (dir — плечо → кисть, в плоскости боя) или пусто (руки нет / не готова / оторвана).
func aim_ray() -> Array:
	var a := arm()
	if a == null or a.part == null or not is_instance_valid(a.part) or not doll.parts.has(a.part_name):
		return []
	var root := a.root_point()
	var grip := a.grip_global()
	var dir := grip - root
	dir.z = 0.0
	if dir.length_squared() < 1e-4:
		return []
	dir = dir.normalized()
	var o := grip + dir * float(def.get("len", 0.15)) * MODEL_SCALE   # дуло — кончик модели ствола
	return [Vector3(o.x, o.y, 0.0), dir]


func can_fire() -> bool:
	return doll.alive and not doll.is_broken() and doll.control_enabled and not doll.is_stunned() and mag > 0 \
		and cooldown <= 0.0 and reloading <= 0.0


## Оружие копит заряд (гаусс).
func charges() -> bool:
	return float(def.get("charge_s", 0.0)) > 0.0


## Состояние для прицела: ready | cooldown (пауза между выстрелами) | reload | empty (нет патронов совсем) | charging | none (нет ствола
## или руки).
func state() -> String:
	if weapon == "" or aim_ray().is_empty():
		return "none"
	if out_of_ammo():
		return "empty"
	if reloading > 0.0 or mag <= 0:
		return "reload"
	if charge > 0.0:
		return "charging"
	if cooldown > 0.0:
		return "cooldown"
	return "ready"


## Доля паузы между выстрелами 0..1 (1 — можно стрелять).
func cooldown_frac() -> float:
	return 1.0 - clampf(cooldown / maxf(float(def.get("interval", 0.1)), 0.01), 0.0, 1.0)


## Куда долетит выстрел сейчас (прицел HUD): по стволу до дальности, у обычной пули — до первой стены или пропса (не бойца).
## [точка, упёрся ли в препятствие] или пусто.
func aim_end() -> Array:
	var ray := aim_ray()
	if ray.is_empty() or def.is_empty():
		return []
	var o := ray[0] as Vector3
	var dir := ray[1] as Vector3
	var end := o + dir * float(def["range"])
	if bool(def.get("through_walls", false)) or not doll.is_inside_tree():
		return [end, false]
	var q := PhysicsRayQueryParameters3D.create(o, end)
	var ex: Array[RID] = []
	for d in get_tree().get_nodes_in_group("dolls"):
		for p in (d as Doll).parts.values():
			if is_instance_valid(p):
				ex.append((p as RigidBody3D).get_rid())
	q.exclude = ex
	var hit := doll.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return [end, false]
	return [hit["position"] as Vector3, true]


func _physics_process(dt: float) -> void:
	if doll == null or not is_instance_valid(doll):
		return
	if def.is_empty():
		_step_balls(dt)   # громила: свои пули, выпущенные до смены класса, долетают
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
	if charges():
		_tick_charge(dt)
	elif trigger and can_fire():
		_fire(1.0)
	_held = trigger
	_step_balls(dt)


## Гаусс: спуск зажат и можно стрелять — заряд растёт; отпустил — выстрел с этим зарядом (меньше GAUSS_MIN_FRAC — не уходит).
func _tick_charge(dt: float) -> void:
	if trigger and can_fire():
		charge = minf(charge + dt / maxf(float(def["charge_s"]), 0.05), 1.0)
	elif not trigger and _held and charge > 0.0:
		if charge >= GAUSS_MIN_FRAC and can_fire():
			_fire(charge)
		charge = 0.0
	elif not can_fire():
		charge = 0.0



func _fire(power: float) -> void:
	var ray := aim_ray()
	if ray.is_empty():
		return
	var o := ray[0] as Vector3
	var dir := ray[1] as Vector3
	mag -= 1
	cooldown = float(def["interval"])
	shots += 1
	last_charge = power
	var ex: Array[RID] = []
	for p in doll.parts.values():
		if is_instance_valid(p):
			ex.append((p as RigidBody3D).get_rid())
	var dmg := float(def["damage"])
	if charges():
		dmg = lerpf(float(def.get("damage_min", dmg * 0.2)), dmg, power)
	for i in int(def["pellets"]):
		var d := dir.rotated(Vector3.BACK, deg_to_rad(_rng.randf_range(-1.0, 1.0) * float(def["spread_deg"])))
		_spawn_ball(o, d, ex.duplicate(), dmg, power)
	var hand := arm().part if arm() != null else null
	if hand != null and is_instance_valid(hand):
		hand.apply_impulse(-dir * float(def["recoil"]) * (0.4 + 0.6 * power), o - hand.global_position)
	_show_flash(o)
	fired.emit(o, dir)
	if _match != null and _match.has_method("gun_sound"):
		_match.call("gun_sound", doll, def)


## Пуля: светящийся трассер своего цвета (квад вдоль полёта, STREAK_SHADER), летит из o по d со скоростью оружия. Длина хвоста —
## streak, но не больше пройденного пути (у дула хвост не торчит назад сквозь ствол). power — заряд (гаусс: толщина трассера).
func _spawn_ball(o: Vector3, d: Vector3, ex: Array[RID], dmg: float, power := 1.0) -> void:
	var mi := MeshInstance3D.new()
	if _streak_mesh == null:
		_streak_mesh = QuadMesh.new()
		_streak_mesh.size = Vector2.ONE
		_streak_mesh.center_offset = Vector3(-0.5, 0.0, 0.0)   # голова — в начале координат узла, хвост — назад по −X
	mi.mesh = _streak_mesh
	var col: Color = def["tracer"]
	var team := SquadMatch.team_of(doll)
	var energy := ENERGY_NIGHT if ProvingGround.night_now else ENERGY_DAY
	var key := "%s/%d/%.1f" % [col.to_html(), team, energy]
	if not _glow.has(key):
		if _streak_shader == null:
			_streak_shader = Shader.new()
			_streak_shader.code = STREAK_SHADER
		var sm := ShaderMaterial.new()
		sm.shader = _streak_shader
		sm.set_shader_parameter("tint", col)
		sm.set_shader_parameter("rim", SquadMatch.team_colour(team).lightened(0.15) if team >= 0 else col)
		sm.set_shader_parameter("energy", energy)
		_glow[key] = sm
	mi.material_override = _glow[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	add_child(mi)
	var w := float(def["ball"]) * WIDTH_MULT * (0.45 + 0.55 * power if charges() else 1.0)
	var b := {"pos": o, "vel": d * float(def["speed"]), "left": float(def["range"]), "ex": ex, "pierced": 0, "through": 0, "node": mi,
		"weapon": weapon, "damage": dmg, "impulse": float(def["impulse"]) * (power if charges() else 1.0), "pierce": bool(def["pierce"]),
		"walls": bool(def.get("through_walls", false)), "wall_loss": float(def.get("wall_loss", 0.0)), "body_loss": float(def.get("body_loss", 0.0)),
		"streak": float(def.get("streak", 0.5)) * STREAK_MULT, "width": w, "flown": 0.0}
	balls.append(b)
	_place_streak(b)


## Трассер пули b: голова в точке пули, ось X — по полёту, длина — min(streak, пройдено), толщина — width (квад в плоскости боя).
func _place_streak(b: Dictionary) -> void:
	var node := b["node"] as Node3D
	if not is_instance_valid(node):
		return
	var d := (b["vel"] as Vector3).normalized()
	var x := d
	var z := Vector3.BACK
	var y := z.cross(x).normalized()
	var length := clampf(float(b["flown"]), 0.05, float(b["streak"]))
	node.global_transform = Transform3D(Basis(x * length, y * float(b["width"]), z), b["pos"])


## Полёт пуль за тик: отрезок пути — луч (свои детали и уже пробитые бойцы — мимо); попала — урон и импульс, пробивающая летит
## дальше (гаусс — и сквозь стены, теряя урон); прошла range — гаснет.
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
		var d := step.normalized()
		var to := from + d * len
		var done := len <= 0.001 or space == null
		var guard := 0
		while not done and guard < THROUGH_MAX + 2:
			guard += 1
			var q := PhysicsRayQueryParameters3D.create(from, to)
			q.exclude = b["ex"]
			q.hit_back_faces = false   # гаусс выходит из стены изнутри — выход не считается второй стеной
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				break
			var at: Vector3 = hit["position"]
			var body := hit["collider"] as Node
			var victim := _doll_of(body)
			if body is RigidBody3D and not (body as RigidBody3D).freeze:
				(body as RigidBody3D).apply_impulse(d * float(b["impulse"]), at - (body as RigidBody3D).global_position)
			if victim != null and victim != doll:
				var dealt := 0.0
				if _match != null and _match.has_method("bullet_hit"):
					dealt = float(_match.call("bullet_hit", victim, doll, float(b["damage"]), String(body.name), at, hit["normal"],
						String(b["weapon"])))
				pellets_hit += 1
				damage_dealt += dealt
				var limit := THROUGH_MAX if bool(b["walls"]) else PIERCE_MAX
				if bool(b["pierce"]) and int(b["pierced"]) < limit:
					b["pierced"] = int(b["pierced"]) + 1
					b["damage"] = float(b["damage"]) * (1.0 - float(b["body_loss"]))
					var ex: Array[RID] = b["ex"]
					for p in victim.parts.values():   # дальше — сквозь всего бойца
						if is_instance_valid(p):
							ex.append((p as RigidBody3D).get_rid())
					from = at
					continue
			else:
				if body is Breakable:
					(body as Breakable).take_damage(float(b["damage"]))
				if bool(b["walls"]) and int(b["through"]) < THROUGH_MAX and victim == null:
					# гаусс: сквозь стену — минус wall_loss урона; луч дальше из-под поверхности (ту же стену он уже не видит)
					b["through"] = int(b["through"]) + 1
					walls_pierced += 1
					b["damage"] = float(b["damage"]) * (1.0 - float(b["wall_loss"]))
					if body is PhysicsBody3D and not (body is StaticBody3D):
						(b["ex"] as Array[RID]).append((body as PhysicsBody3D).get_rid())
					from = at + d * THROUGH_STEP
					if float(b["damage"]) < 1.0 or from.distance_to(start) >= len:
						to = at
						done = true
					continue
			to = at
			done = true
		b["left"] = float(b["left"]) - start.distance_to(to) if not done else 0.0
		b["flown"] = float(b["flown"]) + start.distance_to(to)
		b["pos"] = to
		var node := b["node"] as Node3D
		_place_streak(b)
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
	var shake := Vector3(0.0, 0.0, 0.0)
	if charge > 0.0:
		shake = Vector3(sin(Time.get_ticks_msec() * 0.09), cos(Time.get_ticks_msec() * 0.11), 0.0) * 0.006 * charge   # гаусс гудит
	_model.global_transform = Transform3D(Basis(x, y, z).scaled(Vector3.ONE * MODEL_SCALE), Vector3(grip.x, grip.y, 0.06) + shake)


func _build_model() -> void:
	if _model != null and is_instance_valid(_model):
		_model.queue_free()
	var team := SquadMatch.team_colour(SquadMatch.team_of(doll)) if doll != null else Color.WHITE
	_model = build_model(weapon, team)
	_model.name = "GunModel"
	_model.top_level = true
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)
	if _flash == null:
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


## Модель ствола id из простых форм (своих моделей оружия нет): корпус, ствол, рукоять, магазин / барабан / прицел / катушки по виду;
## team — цвет накладок. Ствол — вдоль +X, рукоять у начала координат. Без масштаба (SquadIcons рисует её сам).
static func build_model(id: String, team: Color) -> Node3D:
	var root := Node3D.new()
	var metal := _mat(Color(0.16, 0.17, 0.19), 0.55)
	var accent := _mat(team.lightened(0.15), 0.4)
	var l := float((Tuning.SQUAD_WEAPONS.get(id, {}) as Dictionary).get("len", 0.3))
	match id:
		"sawnoff", "shotgun":
			for k in [-1.0, 1.0]:
				_part(root, CylinderMesh.new(), Vector3(l * 0.5, 0.0, k * 0.018), Vector3(0.022, l, 0.022), metal, true)
			_part(root, BoxMesh.new(), Vector3(-0.04, -0.03, 0.0), Vector3(0.14, 0.05, 0.06), accent)
			if id == "shotgun":
				_part(root, BoxMesh.new(), Vector3(l * 0.55, -0.035, 0.0), Vector3(l * 0.3, 0.035, 0.05), accent)   # цевьё
		"gauss":
			_part(root, BoxMesh.new(), Vector3(l * 0.42, 0.0, 0.0), Vector3(l * 0.95, 0.06, 0.055), metal)
			for k in 4:
				_part(root, CylinderMesh.new(), Vector3(l * (0.22 + 0.2 * k), 0.0, 0.0), Vector3(0.085, 0.035, 0.085),
					_mat(Color(0.35, 0.9, 1.0), 0.2, 3.0), true)
			_part(root, BoxMesh.new(), Vector3(0.0, -0.05, 0.0), Vector3(0.05, 0.09, 0.045), accent)
		_:
			_part(root, BoxMesh.new(), Vector3(l * 0.32, 0.01, 0.0), Vector3(l * 0.64, 0.06, 0.045), metal)
			_part(root, CylinderMesh.new(), Vector3(l * 0.78, 0.015, 0.0), Vector3(0.022, l * 0.44, 0.022), metal, true)
			_part(root, BoxMesh.new(), Vector3(0.0, -0.05, 0.0), Vector3(0.045, 0.09, 0.04), accent)
			if id == "smg":
				_part(root, BoxMesh.new(), Vector3(l * 0.3, -0.07, 0.0), Vector3(0.04, 0.1, 0.035), accent)
			if id in ["rifle", "marksman"]:
				_part(root, CylinderMesh.new(), Vector3(l * 0.35, 0.06, 0.0), Vector3(0.035, 0.2, 0.035), accent, true)   # прицел
				_part(root, BoxMesh.new(), Vector3(-0.08, -0.01, 0.0), Vector3(0.16, 0.05, 0.04), metal)   # приклад
			if id == "marksman":
				_part(root, BoxMesh.new(), Vector3(l * 0.4, -0.06, 0.0), Vector3(0.04, 0.08, 0.03), accent)
	return root


static func _part(parent: Node3D, mesh: PrimitiveMesh, pos: Vector3, size: Vector3, mat: Material, along_x := false) -> void:
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
