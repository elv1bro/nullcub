## Гейт боя (план 06): headless, --fixed-fps 60, плоский пол, стены на x = ±8, скриптованный ввод, без HUD.
## Запуск: tests/run_combat_gate.sh  →  печатает таблицу калибровки и JSON, пишет tests/combat_gate_report.json, exit 0/1.
## Проверки (checks[].id):
##   calib_*        — таблица Damage.CALIBRATION в полосах концепта (чистая формула); строки окружения при ENV_DAMAGE_ENABLED = false
##                    ждут 0, а calib_*_if_enabled — что env_formula осталась в своей полосе (на случай, если урон вернут);
##   rush_damage    — две куклы 15 с бегут друг на друга: суммарный урон 20–120 HP, ни одного удара kind environment;
##   band_torso     — контролируемый наезд 3 м/с (скорости всех частей заданы): первый удар 0.5–5 HP;
##   band_hand      — наезд 10 м/с: первый удар (конечность) 6–18 HP;
##   band_hammer    — кукла с молотом в левой кисти (WeaponPickup.attach, молот нацелен по +X на цель) наезжает 8 м/с: первый удар
##                    оружием 15–40 HP (в голову — 30–50, как hammer_head_8), kind weapon;
##   idle_no_damage — 60 с две куклы стоят порознь: урон 0;
## Урон от окружения выключен (Tuning.ENV_DAMAGE_ENABLED = false, решение автора 28.09). Сценарии ниже идут с Match (FIGHT, feel on)
## и заглушкой камеры в группе "camera": удар окружения не должен дать ни урона, ни стана, ни отброса, ни надписи, ни hit_feel.
##   env_wall       — кукла летит 15 м/с в стену: env-урон 0, hp == MAX, kind environment нет ни в damaged, ни в Match.hit,
##                    wall_collisions ≥ 1, через 0.2 с после касания не в стане и не в полёте от отброса, камера не трясётся;
##                    контакт реальный: DollCombat.env_ignored_max_speed ≥ 10 м/с (при включённом флаге — 7.6+ HP, на 15 м/с 15–40 HP);
##   prop_push      — ящик (Breakable crate.tscn, 10 кг) влетает в стоящую куклу на 10 м/с без атрибуции (как толкнутый другой
##                    куклой): урон 0, hp == MAX, без стана/отброса/надписей/тряски; удар ≥ ENV_MIN_IMPACT_SPEED подтверждён Breakable.hit;
##   loose_weapon   — ничей молот (не держали, attacker() == null) влетает в куклу на 10 м/с: урон 0 (kind environment без атрибуции;
##                    без фикса 28.09 этот сценарий давал 21 HP kind environment со станом, отбросом и тряской камеры),
##                    контакт ≥ 4 м/с виден DollCombat.env_ignored_max_speed;
##   weapon_still   — молот в руке бьёт стоящую куклу (8 м/с) при тех же Match/камере: урон > 0, kind weapon, атакующий — владелец,
##                    Match.hit weapon, надпись BLOW, тряска камеры (доказывает, что заглушки env-сценариев не глухие);
##   weapon_thrown  — молот, отпущенный куклой B 0.5 с назад (окно WEAPON_ATTACKER_WINDOW_S), летит в A на 10 м/с: kind weapon, урон > 0,
##                    зачёт B (stats.weapon_hits);
##   ko_burst       — hp 5 → удар: knocked_out, суставов 0, частей 14, части разлетелись;
##   sd_step        — Match с time_limit 5 с: фаза SUDDEN_DEATH, через 10 с шага knockback ×1.25, стабильность ×0.85;
##   match_over     — Match, у одной куклы hp 10: match_over с winner, places/medals/combo_score, time_scale вернулся к 1;
##                    затем restart(): куклы пересозданы на точках спавна, живые, hp 100, фаза FIGHT;
##   double_ko      — одновременный KO (06-combat-hud.md «Одновременный KO»): Match + HUD, обе куклы с hp DKO_HP лежат в воздухе
##                    головами навстречу (руки Т-позы поперёк — первой касается голова), наезд по DKO_SPEED каждая: голова о голову бьёт
##                    обоих (~6 HP) → KO обоих в одном тике физики; ждём ничью: match_over(null), draw, reason ko, ranks [0, 0], медали
##                    Winner нет, HUD — корон не прибавилось, итоги «DRAW!» без короны, оба «1ST» с KO на портретах;
##   double_ko_rev  — то же, но B добавлена в дерево раньше A (её DollCombat разрешает очередь первой): итог не зависит от порядка.
extends Node3D

const DollScene := preload("res://scenes/doll/doll.tscn")
const DollDarkScene := preload("res://scenes/doll/doll_dark.tscn")
const PickupScript := preload("res://scenes/weapons/weapon_pickup.gd")
const CrateScene := preload("res://scenes/props/crate.tscn")
const HudScene := preload("res://scenes/ui/hud.tscn")
const WALL_X := 8.0
const PROBE_AFTER_S := 0.2       # через столько после касания стены/пропса проверяем стан и отброс
const SETTLE_AFTER_S := 1.5      # итог env-сценариев: касание + падение на пол
const BLOW_KINDS := ["head", "body", "double", "combo"]
const DKO_HP := 2.0              # double_ko: hp обеих к FIGHT; голова о голову на 6 м/с — 4 кг × 4.5 × 0.95 × Head 0.35 ≈ 6 HP каждой
const DKO_SPEED := 6.0
const DKO_X := 2.1               # начало куклы (стопы) на ∓DKO_X, повёрнута на ∓90°: макушки (1.775 м от начала) в 0.65 м друг от друга
const DKO_Y := 2.5
const DKO_RESULTS_S := 2.0       # итоги HUD — через карточку KO (1.2 с) + 0.15 с


## Заглушка DynamicCamera: Match.hit_feel ищет камеру в группе "camera" и зовёт shake / zoom_impulse.
class CameraStub extends Node3D:
	var shakes := 0
	var zooms := 0

	func shake(_metres: float) -> void:
		shakes += 1

	func zoom_impulse(_frac: float = -0.05, _seconds: float = 0.2) -> void:
		zooms += 1
const LIMB_PREFIXES := ["Hand", "Foot", "LowerArm", "LowerLeg", "UpperArm", "UpperLeg"]

var scenarios := ["rush_damage", "band_torso", "band_hand", "band_hammer", "idle_no_damage", "env_wall", "prop_push", "loose_weapon",
	"weapon_still", "weapon_thrown", "ko_burst", "sd_step", "match_over", "double_ko", "double_ko_rev"]
var only := ""
var idx := -1
var t := 0.0
var report := {"ok": true, "checks": [], "info": {}}
var world: Node3D
var a: Doll
var b: Doll
var m: Match
var hammer: Weapon
var hits_a: Array = []     # удары по A: {amount, kind, part, striker, t}
var hits_b: Array = []
var events: Array = []     # announce / ko / match_over / phase
var first_hit_t := -1.0
var injecting := false
var inject_v := Vector3.ZERO
var ko_fired := false
var ko_t := -1.0
var over_fired := false
var over_t := -1.0
var over_winner: Doll = null
var over_results: Dictionary = {}
var restart_t := -1.0
var old_ids: Array = []
var total_ticks := 0
var wall_start_usec := 0
var min_time_scale := 1.0
var wall_right: StaticBody3D
# env / prop / weapon сценарии
var cam: CameraStub = null
var hud: Hud = null
var match_hits: Array = []      # Match.hit: {kind, damage, victim, attacker}
var stun_events: Array = []     # Doll.stunned: {doll, seconds, t}
var scen_min_ts := 1.0          # min Engine.time_scale за сценарий (hit stop / slow-mo)
var prop: RigidBody3D = null    # летящий ящик / молот
var prop_speed := 0.0           # скорость пропса, заданная до касания
var prop_hit_speed := 0.0       # Breakable.hit ящика от части куклы: скорость сближения по импульсу контакта (независимый замер)
var impact_t := -1.0            # первое касание стены / пропса
var impact_info: Dictionary = {}
var probe_info: Dictionary = {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "only":
				only = p[1]
	if only != "":
		scenarios = [only]
	_make_arena()
	_calibration()
	wall_start_usec = Time.get_ticks_usec()
	_next()


func _make_arena() -> void:
	_static_box(Vector3(0, -0.5, 0), Vector3(60, 1, 10))
	wall_right = _static_box(Vector3(WALL_X + 0.5, 6.0, 0), Vector3(1, 12, 10))
	_static_box(Vector3(-WALL_X - 0.5, 6.0, 0), Vector3(1, 12, 10))


func _static_box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var f := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	f.add_child(cs)
	f.position = pos
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	f.physics_material_override = pm
	add_child(f)
	return f


func _calibration() -> void:
	Damage.print_calibration_table()
	var rows := Damage.calibration_table()
	report["info"]["calibration"] = rows
	for r in rows:
		_check("calib_" + String(r["id"]), float(r["hp"]), float(r["lo"]), "gte", "calibration row %s >= band low" % r["id"])
		_check("calib_" + String(r["id"]) + "_hi", float(r["hp"]), float(r["hi"]), "lte", "calibration row %s <= band high" % r["id"])
		if r.has("formula_hp"):
			var band: Array = r["band_if_enabled"]
			_check("calib_" + String(r["id"]) + "_if_enabled", 1.0 if bool(r["formula_ok"]) else 0.0, 1.0, "eq",
				"env damage off; env_formula %.2f HP stays in band %.0f-%.0f for a re-enable" % [float(r["formula_hp"]), float(band[0]), float(band[1])])


# --- сценарии ---

func _spawn_doll(scene: PackedScene, index: int, pos: Vector3) -> Doll:
	var d: Doll = scene.instantiate()
	d.player_index = index
	d.external_input = true
	d.add_to_group("dolls")
	world.add_child(d)
	d.position = pos
	var c := DollCombat.new()
	c.name = "DollCombat"
	d.add_child(c)
	return d


func _hook(d: Doll, store: Array) -> void:
	d.damaged.connect(func(amount: float, _attacker: Node, part: String, _position: Vector3, kind: String) -> void:
		var striker: Object = d.last_hit.get("striker", null)
		store.append({"amount": snappedf(amount, 0.01), "kind": kind, "part": part, "striker": striker.name if striker != null and is_instance_valid(striker) else "", "t": snappedf(t, 0.01)})
		if first_hit_t < 0.0:
			first_hit_t = t)
	d.stunned.connect(func(seconds: float) -> void:
		stun_events.append({"doll": d.name, "seconds": snappedf(seconds, 0.01), "t": snappedf(t, 0.01)}))
	d.knocked_out.connect(func(_attacker: Node, record: Dictionary) -> void:
		ko_fired = true
		ko_t = t
		events.append({"ko": record.get("kind", ""), "damage": record.get("damage", 0.0), "t": snappedf(t, 0.01)}))


func _make_match(time_limit: float, countdown: float, feel: bool) -> Match:
	var mm := Match.new()
	mm.name = "Match"
	mm.time_limit_s = time_limit
	mm.hard_timeout_s = maxf(time_limit + 60.0, 180.0)
	mm.countdown_s = countdown
	mm.feel_enabled = feel
	mm.announce.connect(func(text: String, _color: Color, kind: String) -> void:
		events.append({"announce": text, "kind": kind, "t": snappedf(t, 0.01)}))
	mm.phase_changed.connect(func(p: int) -> void:
		events.append({"phase": p, "t": snappedf(t, 0.01)}))
	mm.match_over.connect(func(winner: Doll, results: Dictionary) -> void:
		over_fired = true
		over_t = t
		over_winner = winner
		over_results = results)
	mm.hit.connect(func(victim: Doll, attacker: Node, damage: float, kind: String, _position: Vector3) -> void:
		match_hits.append({"kind": kind, "damage": snappedf(damage, 0.01), "victim": victim.name, "attacker": attacker.name if attacker != null else "", "t": snappedf(t, 0.01)}))
	world.add_child(mm)
	return mm


## Match в FIGHT без отсчёта, с подачей удара (тряска/зум/hit stop) и заглушкой камеры — как в игре.
func _make_feel_match() -> void:
	m = _make_match(90.0, 0.0, true)
	cam = CameraStub.new()
	cam.name = "CameraStub"
	cam.add_to_group("camera")
	world.add_child(cam)


func _next() -> void:
	idx += 1
	if world != null:
		remove_child(world)
		world.queue_free()
		world = null
	a = null
	b = null
	m = null
	hammer = null
	hits_a = []
	hits_b = []
	events = []
	first_hit_t = -1.0
	injecting = false
	ko_fired = false
	ko_t = -1.0
	over_fired = false
	over_t = -1.0
	over_winner = null
	over_results = {}
	restart_t = -1.0
	old_ids = []
	rush_retreat = {}
	cam = null
	hud = null
	match_hits = []
	stun_events = []
	scen_min_ts = 1.0
	prop = null
	prop_speed = 0.0
	prop_hit_speed = 0.0
	impact_t = -1.0
	impact_info = {}
	probe_info = {}
	t = 0.0
	Engine.time_scale = 1.0
	if idx >= scenarios.size():
		_finish()
		return
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	var s: String = scenarios[idx]
	print("--- scenario %s ---" % s)
	match s:
		"rush_damage":
			a = _spawn_doll(DollScene, 0, Vector3(-2.5, 0, 0))
			b = _spawn_doll(DollDarkScene, 1, Vector3(2.5, 0, 0))
		"band_torso":
			# v7: куклы спавнятся сразу в Т-позе (Doll.spawn_in_pose), размах 1.94 м: при ±0.9 кисти рождались друг в друге (0.14 м) и
			# расталкивались ещё в grace — первый удар был скользящим касанием кисти о предплечье (0.17 HP). ±1.0 — кисть в кисть 1.42 HP
			# (формула 0.5 кг × 1.5 м/с × 0.95 × Hand 2.0 = 1.43); полосы не менялись
			a = _spawn_doll(DollScene, 0, Vector3(-1.0, 0, 0))
			b = _spawn_doll(DollDarkScene, 1, Vector3(1.0, 0, 0))
		"band_hand":
			a = _spawn_doll(DollScene, 0, Vector3(-1.5, 0, 0))
			b = _spawn_doll(DollDarkScene, 1, Vector3(1.0, 0, 0))
		"band_hammer":
			a = _spawn_doll(DollScene, 0, Vector3(-2.0, 0, 0))
			b = _spawn_doll(DollDarkScene, 1, Vector3(1.2, 0, 0))
		"idle_no_damage":
			a = _spawn_doll(DollScene, 0, Vector3(-2.0, 0, 0))
			b = _spawn_doll(DollDarkScene, 1, Vector3(2.0, 0, 0))
		"env_wall":
			a = _spawn_doll(DollScene, 0, Vector3(4.5, 0, 0))
			_make_feel_match()
		"prop_push", "loose_weapon":
			a = _spawn_doll(DollScene, 0, Vector3(1.0, 0, 0))
			_make_feel_match()
		"weapon_still":
			a = _spawn_doll(DollScene, 0, Vector3(-2.0, 0, 0))
			b = _spawn_doll(DollDarkScene, 1, Vector3(1.2, 0, 0))
			_make_feel_match()
		"weapon_thrown":
			a = _spawn_doll(DollScene, 0, Vector3(1.0, 0, 0))
			b = _spawn_doll(DollDarkScene, 1, Vector3(-4.5, 0, 0))
			_make_feel_match()
		"ko_burst":
			a = _spawn_doll(DollScene, 0, Vector3(-1.5, 0, 0))
			b = _spawn_doll(DollDarkScene, 1, Vector3(1.0, 0, 0))
		"sd_step":
			a = _spawn_doll(DollScene, 0, Vector3(-5.0, 0, 0))
			b = _spawn_doll(DollDarkScene, 1, Vector3(5.0, 0, 0))
			m = _make_match(5.0, 0.0, false)
		"match_over":
			a = _spawn_doll(DollScene, 0, Vector3(-2.5, 0, 0))
			b = _spawn_doll(DollDarkScene, 1, Vector3(2.5, 0, 0))
			m = _make_match(90.0, 0.0, true)
			m.phase_changed.connect(func(p: int) -> void:
				if p == Match.Phase.FIGHT and is_instance_valid(b):
					b.hp = 10.0)
		"double_ko", "double_ko_rev":
			if s == "double_ko_rev":
				b = _spawn_doll(DollDarkScene, 1, Vector3(DKO_X, DKO_Y, 0))
				a = _spawn_doll(DollScene, 0, Vector3(-DKO_X, DKO_Y, 0))
			else:
				a = _spawn_doll(DollScene, 0, Vector3(-DKO_X, DKO_Y, 0))
				b = _spawn_doll(DollDarkScene, 1, Vector3(DKO_X, DKO_Y, 0))
			a.rotation.z = -PI * 0.5   # голова к +X
			b.rotation.z = PI * 0.5    # голова к −X
			m = _make_match(90.0, 0.0, false)
			hud = HudScene.instantiate()
			world.add_child(hud)
			hud.bind(m)
			m.phase_changed.connect(func(p: int) -> void:
				if p == Match.Phase.FIGHT:
					for d in [a, b]:
						if is_instance_valid(d):
							(d as Doll).hp = DKO_HP)
	if a != null:
		_hook(a, hits_a)
	if b != null:
		_hook(b, hits_b)


func _check(id: String, value: float, limit: float, cmp: String, detail: String) -> void:
	var ok := false
	match cmp:
		"lt": ok = value < limit
		"gt": ok = value > limit
		"lte": ok = value <= limit
		"gte": ok = value >= limit
		"eq": ok = is_equal_approx(value, limit)
	report["checks"].append({"id": id, "value": snappedf(value, 0.001), "limit": limit, "cmp": cmp, "ok": ok, "detail": detail})
	if not ok:
		report["ok"] = false
		print("  FAIL %s: %s %s %s (%s)" % [id, snappedf(value, 0.001), cmp, limit, detail])
	else:
		print("  ok   %s: %s %s %s" % [id, snappedf(value, 0.001), cmp, limit])


## Наскок: разбег на соперника; ближе RUSH_NEAR — короткий полутяговый подскок назад на RUSH_RETREAT_S и снова разбег (иначе две
## куклы, упёршиеся друг в друга, стоят в равновесии и урона нет; отход на полной тяге загонял бы их в стены ±8 м). Первую секунду
## (spawn grace) — стоим.
const RUSH_NEAR := 1.3
const RUSH_RETREAT_S := 0.8
var rush_retreat: Dictionary = {}   # doll -> время конца отхода

func _rush(d: Doll, other: Doll) -> void:
	if d == null or other == null or not d.alive:
		return
	if t < 1.0:
		d.input_vec = Vector2.ZERO
		return
	var dx := other.centre_of_mass().x - d.centre_of_mass().x
	var sgn := signf(dx) if absf(dx) > 0.05 else 1.0
	var until := float(rush_retreat.get(d, -1.0))
	if t < until:
		d.input_vec = Vector2(-0.5 * sgn, 0.0)
	elif absf(dx) < RUSH_NEAR:
		rush_retreat[d] = t + RUSH_RETREAT_S
		d.input_vec = Vector2(-0.5 * sgn, 0.0)
	else:
		d.input_vec = Vector2(sgn, 0.0)


func _inject(d: Doll, v: Vector3) -> void:
	for p in d.parts.values():
		(p as RigidBody3D).linear_velocity = v
		(p as RigidBody3D).angular_velocity = Vector3.ZERO
	if hammer != null and is_instance_valid(hammer) and hammer.is_held():
		hammer.linear_velocity = v
		hammer.angular_velocity = Vector3.ZERO


func _sum(store: Array, kind_filter: String = "") -> float:
	var s := 0.0
	for h in store:
		if kind_filter == "" or h["kind"] == kind_filter:
			s += float(h["amount"])
	return s


func _first(store: Array) -> Dictionary:
	return store[0] if not store.is_empty() else {"amount": 0.0, "kind": "", "part": "", "striker": ""}


func _max_hit(store: Array) -> float:
	var mx := 0.0
	for h in store:
		mx = maxf(mx, float(h["amount"]))
	return mx


func _first_kind(store: Array, kind: String) -> Dictionary:
	for h in store:
		if h["kind"] == kind:
			return h
	return {"amount": 0.0, "kind": "", "part": "", "striker": ""}


func _count_kind(store: Array, kind: String) -> int:
	var n := 0
	for h in store:
		if h["kind"] == kind:
			n += 1
	return n


func _blow_announces() -> int:
	var n := 0
	for e in events:
		if e.has("announce") and BLOW_KINDS.has(e["kind"]):
			n += 1
	return n


func _stuns_of(d: Doll) -> int:
	var n := 0
	for e in stun_events:
		if e["doll"] == d.name:
			n += 1
	return n


## Касается ли тела body хоть одна часть куклы с contact_monitor (голова, торс, кисти, стопы, предплечья, голени).
func _touching(d: Doll, body: Node) -> bool:
	if d == null or body == null or not is_instance_valid(body):
		return false
	for p in d.parts.values():
		var rb := p as RigidBody3D
		if rb.contact_monitor and rb.get_colliding_bodies().has(body):
			return true
	return false


## Пропс летит скоростью v: задаётся каждый тик до касания — как толчок другой куклой (у пропса атрибуции нет, у ничьего оружия
## Weapon.attacker() == null, так что для DollCombat это одно и то же).
func _fly_prop(v: Vector3) -> void:
	prop.linear_velocity = v
	prop.angular_velocity = Vector3.ZERO
	prop_speed = v.length()


## Молот в левую кисть куклы d (WeaponPickup.attach); hammer — этот молот. Угол хвата подбирается так, чтобы молот смотрел
## вдоль ±X (aim_x — знак, в сторону цели), какой бы ни была поза покоя руки: attach ставит оружие под углом
## φ_кисти − 90° + hold_angle·side (Hand_L: side = +1). Иначе при руках «в стороны» (POSE Shoulder 90°) молот торчит
## вертикально и первым касается кисть — сценарий проверял бы не оружие.
func _attach_hammer(d: Doll, aim_x: float) -> bool:
	var pickup: WeaponPickup = PickupScript.new()
	pickup.name = "WeaponPickup"
	pickup.auto_pickup = false
	d.add_child(pickup)
	var h := pickup.hand("Hand_L")
	var want := 0.0 if aim_x >= 0.0 else PI
	pickup.hold_angle_deg = wrapf(rad_to_deg(want - h.global_rotation.z) + 90.0, -180.0, 180.0)
	report["info"]["hold_angle_" + String(d.name)] = snappedf(pickup.hold_angle_deg, 0.1)
	var grip := pickup.hand_grip_global("Hand_L")
	hammer = Weapon.spawn("hammer", world, grip, 0.0)
	hammer.global_position += grip - hammer.grip_global()
	return pickup.attach("Hand_L", hammer)


func _mark_impact(d: Doll, extra: Dictionary) -> void:
	impact_t = t
	impact_info = {"t": snappedf(t, 0.01), "can_take_damage": d.can_take_damage(), "hp": d.hp, "phase": m.phase if m != null else -1}
	impact_info.merge(extra)


## Через PROBE_AFTER_S после касания: стан и полёт от отброса (Doll.is_flying — окно после apply_knockback).
func _probe(d: Doll) -> void:
	if impact_t >= 0.0 and probe_info.is_empty() and t >= impact_t + PROBE_AFTER_S:
		probe_info = {"stunned": d.is_stunned(), "flying": d.is_flying(), "hp": d.hp, "t": snappedf(t, 0.01)}


## Общий вердикт «окружение не бьёт» для env_wall / prop_push / loose_weapon (жертва — A, хиты в hits_a).
## Скорость контакта: DollCombat.env_ignored_max_speed; для ящика — ещё и его Breakable.hit (extra_speed): пропсов нет в
## DollCombat.prev_vel, и после решения контакта их скорость уже погашена, так что DollCombat видит ящик медленным.
func _env_checks(id: String, d: Doll, min_speed: float, what: String, extra_speed: float) -> void:
	var dc := DollCombat.combat_of(d)
	var env_n := _count_kind(hits_a, "environment") + _count_kind(match_hits, "environment")
	if String(d.last_hit.get("kind", "")) == "environment":
		env_n += 1
	_check(id + "_contact", 1.0 if impact_t >= 0.0 else 0.0, 1.0, "eq", "%s: contact happened" % what)
	_check(id + "_grace", 1.0 if bool(impact_info.get("can_take_damage", false)) else 0.0, 1.0, "eq", "doll could take damage at contact (FIGHT, no spawn grace)")
	var v := maxf(dc.env_ignored_max_speed if dc != null else 0.0, extra_speed)
	_check(id + "_speed", v, min_speed, "gte", "contact speed (m/s) is above the env threshold: it would hit with ENV_DAMAGE_ENABLED")
	_check(id, _sum(hits_a, "environment"), 0.0, "lte", "%s: environment damage == 0" % what)
	_check(id + "_total", _sum(hits_a), 0.0, "lte", "%s: total damage == 0 (%d hit events)" % [what, hits_a.size()])
	_check(id + "_hp", d.hp, Tuning.MAX_HP, "eq", "hp == MAX_HP")
	_check(id + "_kind", float(env_n), 0.0, "lte", "no hit of kind environment (damaged, Match.hit, last_hit)")
	var stunned := bool(probe_info.get("stunned", true)) or _stuns_of(d) > 0
	_check(id + "_stun", 1.0 if stunned else 0.0, 0.0, "eq", "not stunned %.1f s after contact, no stunned signal" % PROBE_AFTER_S)
	_check(id + "_knockback", 1.0 if bool(probe_info.get("flying", true)) else 0.0, 0.0, "eq", "no knockback flight %.1f s after contact" % PROBE_AFTER_S)
	var feel := float(cam.shakes + cam.zooms + match_hits.size()) + (1.0 - scen_min_ts)
	_check(id + "_feel", feel, 0.0, "lte", "no hit_feel: camera shake/zoom %d/%d, Match.hit %d, min time_scale %.2f" % [cam.shakes, cam.zooms, match_hits.size(), scen_min_ts])
	_check(id + "_announce", float(_blow_announces()), 0.0, "lte", "no HEAD/BODY/DOUBLE BLOW announce")


func _env_info(d: Doll) -> Dictionary:
	var dc := DollCombat.combat_of(d)
	return {"hits": hits_a.slice(0, 6), "match_hits": match_hits.slice(0, 6), "impact": impact_info, "probe": probe_info, "hp": d.hp,
		"wall_collisions": d.stats["wall_collisions"], "env_ignored": dc.env_ignored if dc != null else -1,
		"env_ignored_max_speed": snappedf(dc.env_ignored_max_speed, 0.01) if dc != null else -1.0, "stuns": stun_events,
		"prop_hit_speed": snappedf(prop_hit_speed, 0.01), "shakes": cam.shakes if cam != null else -1, "com_x": snappedf(d.centre_of_mass().x, 0.01),
		"events": events.slice(0, 6)}


func _joint_nodes(d: Doll) -> int:
	var n := 0
	for c in d.get_children():
		if c is Generic6DOFJoint3D:
			n += 1
	return n


func _part_spread(d: Doll) -> float:
	var mx := 0.0
	var list: Array = d.parts.values()
	for i in range(list.size()):
		for j in range(i + 1, list.size()):
			mx = maxf(mx, (list[i] as RigidBody3D).global_position.distance_to((list[j] as RigidBody3D).global_position))
	return mx


func _physics_process(delta: float) -> void:
	if idx >= scenarios.size() or world == null:
		return
	t += delta
	total_ticks += 1
	min_time_scale = minf(min_time_scale, Engine.time_scale)
	scen_min_ts = minf(scen_min_ts, Engine.time_scale)
	var s: String = scenarios[idx]
	match s:
		"rush_damage":
			_rush(a, b)
			_rush(b, a)
			if t >= 15.0:
				var total := _sum(hits_a) + _sum(hits_b)
				_check("rush_damage", total, 20.0, "gte", "two dolls rushing each other 15 s: total damage (HP) >= 20")
				_check("rush_damage_hi", total, 120.0, "lte", "two dolls rushing each other 15 s: total damage (HP) <= 120")
				_check("rush_no_env", float(_count_kind(hits_a, "environment") + _count_kind(hits_b, "environment")), 0.0, "lte",
					"15 s of rushing (floor, walls ±8 m): no hit of kind environment")
				report["info"]["rush"] = {"damage_a": _sum(hits_a), "damage_b": _sum(hits_b), "hits_a": hits_a.size(), "hits_b": hits_b.size(),
					"env_damage": _sum(hits_a, "environment") + _sum(hits_b, "environment"),
					"max_hit": maxf(_max_hit(hits_a), _max_hit(hits_b)), "hits_b_list": hits_b.slice(0, 30), "hits_a_list": hits_a.slice(0, 30),
					"a_alive": a.alive, "b_alive": b.alive, "a_max_speed": a.stats["max_speed"], "flight_b": b.stats["flight_distance"], "flight_a": a.stats["flight_distance"],
					"air_a": a.stats["air_time"], "combo_max_a": a.stats["combo_max"], "combo_max_b": b.stats["combo_max"]}
				_next()
		"band_torso", "band_hand", "band_hammer":
			var speed := 3.0 if s == "band_torso" else (10.0 if s == "band_hand" else 8.0)
			if s == "band_hammer" and hammer == null and t >= 0.5:
				report["info"]["hammer_attached"] = _attach_hammer(a, 1.0)
			if t >= 1.0 and hits_b.is_empty():
				injecting = true
			if injecting:
				if hits_b.is_empty():
					_inject(a, Vector3(speed, 0, 0))
				else:
					injecting = false
			var window := 0.5
			if first_hit_t >= 0.0 and t >= first_hit_t + window or t >= 8.0:
				var f := _first(hits_b)
				var info := {"first": f, "all": hits_b.slice(0, 6), "first_hit_t": first_hit_t, "a_hp": a.hp, "b_hp": b.hp}
				match s:
					"band_torso":
						_check("band_torso", float(f["amount"]), 0.5, "gte", "3 m/s bump: first hit >= 0.5 HP (%s by %s)" % [f["part"], f["striker"]])
						_check("band_torso_hi", float(f["amount"]), 5.0, "lte", "3 m/s bump: first hit <= 5 HP")
					"band_hand":
						_check("band_hand", float(f["amount"]), 6.0, "gte", "10 m/s limb strike: first hit >= 6 HP (%s by %s)" % [f["part"], f["striker"]])
						_check("band_hand_hi", float(f["amount"]), 18.0, "lte", "10 m/s limb strike: first hit <= 18 HP")
						_check("band_hand_limb", 1.0 if _is_limb(String(f["striker"])) else 0.0, 1.0, "eq", "striker is a limb (%s)" % f["striker"])
						info["flight_b"] = b.stats["flight_distance"]
					"band_hammer":
						var wf := {"amount": 0.0, "kind": "", "part": "", "striker": ""}
						for h in hits_b:
							if h["kind"] == "weapon":
								wf = h
								break
						# полоса по ударенной части: в голову ×HEAD_HIT_MULT — строка калибровки hammer_head_8 (30–50), иначе 15–40
						var head := String(wf["part"]).begins_with("Head")
						var lo := 30.0 if head else 15.0
						var hi := 50.0 if head else 40.0
						_check("band_hammer", float(wf["amount"]), lo, "gte", "hammer at 8 m/s: first weapon hit >= %.0f HP (%s)" % [lo, wf["part"]])
						_check("band_hammer_hi", float(wf["amount"]), hi, "lte", "hammer at 8 m/s: first weapon hit <= %.0f HP (%s)" % [hi, wf["part"]])
						_check("band_hammer_kind", 1.0 if wf["kind"] == "weapon" else 0.0, 1.0, "eq", "hit kind is weapon")
						_check("band_hammer_stat", float(a.stats["weapon_hits"]), 1.0, "gte", "attacker stats.weapon_hits >= 1")
						info["hold_distance"] = (a.get_node("WeaponPickup") as WeaponPickup).hold_distance("Hand_L")
				report["info"][s] = info
				_next()
		"idle_no_damage":
			a.input_vec = Vector2.ZERO
			b.input_vec = Vector2.ZERO
			if t >= 60.0:
				_check("idle_no_damage", _sum(hits_a) + _sum(hits_b), 0.0, "lte", "60 s idle apart: total damage == 0")
				_check("idle_no_hits", float(hits_a.size() + hits_b.size()), 0.0, "lte", "60 s idle: hit events == 0")
				_check("idle_alive", 1.0 if a.alive and b.alive else 0.0, 1.0, "eq", "both alive")
				report["info"]["idle"] = {"a_hp": a.hp, "b_hp": b.hp, "air_a": a.stats["air_time"], "wall_a": a.stats["wall_collisions"]}
				_next()
		"env_wall":
			if t >= 1.0 and impact_t < 0.0 and t < 4.0:
				if _touching(a, wall_right):
					_mark_impact(a, {"torso_vx": snappedf(a.torso().linear_velocity.x, 0.01)})
				else:
					_inject(a, Vector3(15.0, 0, 0))
			_probe(a)
			if impact_t >= 0.0 and t >= impact_t + SETTLE_AFTER_S or t >= 6.0:
				_env_checks("env_wall", a, 10.0, "15 m/s into wall", -1.0)
				_check("env_wall_stat", float(a.stats["wall_collisions"]), 1.0, "gte", "stats.wall_collisions >= 1 (Wall Inspector stays)")
				report["info"]["env_wall"] = _env_info(a)
				_next()
		"prop_push", "loose_weapon":
			if t >= 1.0 and prop == null:
				var tp := a.torso().global_position
				if s == "prop_push":
					prop = CrateScene.instantiate()
					prop.name = "Crate"
					(prop as Breakable).hit.connect(func(speed: float, _dmg: float, by: Node) -> void:
						if by != null and is_instance_valid(by) and by.get_parent() == a:
							prop_hit_speed = maxf(prop_hit_speed, speed))
					world.add_child(prop)
					prop.global_position = Vector3(tp.x - 2.2, 0.75, 0.0)   # origin ящика — низ, коробка 0.7 м: торс 0.9–1.45
				else:
					prop = Weapon.spawn("hammer", world, Vector3(tp.x - 2.2, tp.y, 0.0), 0.0)   # боёк (+X) впереди
			if prop != null and impact_t < 0.0 and t < 4.0:
				if _touching(a, prop):
					var extra := {"prop_speed": prop_speed, "prop": prop.name}
					if prop is Weapon:
						extra["attacker"] = str((prop as Weapon).attacker(Tuning.WEAPON_ATTACKER_WINDOW_S))
					_mark_impact(a, extra)
				else:
					_fly_prop(Vector3(10.0, 0, 0))
			_probe(a)
			if impact_t >= 0.0 and t >= impact_t + SETTLE_AFTER_S or t >= 6.0:
				var what := "crate 10 kg at 10 m/s, no attribution" if s == "prop_push" else "loose hammer at 10 m/s, attacker() == null"
				# пороги «ударило бы»: ничей молот — 4 м/с (по формуле оружия ≥ 11 HP; угол контакта с кистью гуляет 5–10 м/с),
				# ящик — ENV_MIN_IMPACT_SPEED по его Breakable.hit
				_env_checks(s, a, 4.0 if s == "loose_weapon" else Tuning.ENV_MIN_IMPACT_SPEED, what, prop_hit_speed if s == "prop_push" else -1.0)
				if s == "loose_weapon":
					_check("loose_weapon_unattributed", 1.0 if impact_info.get("attacker", "?") == "<null>" else 0.0, 1.0, "eq",
						"hammer never held: Weapon.attacker() == null at contact (%s)" % impact_info.get("attacker", "?"))
				report["info"][s] = _env_info(a)
				_next()
		"weapon_still":
			if hammer == null and t >= 0.5:
				report["info"]["weapon_still_attached"] = _attach_hammer(a, 1.0)
			if t >= 1.0 and impact_t < 0.0 and t < 6.0:
				if hits_b.is_empty():
					_inject(a, Vector3(8.0, 0, 0))
				else:
					_mark_impact(b, {})
			if impact_t >= 0.0 and t >= impact_t + 0.5 or t >= 8.0:
				var wf := _first_kind(hits_b, "weapon")
				_check("weapon_still", float(wf["amount"]), 0.0, "gt", "held hammer at 8 m/s: weapon hit > 0 HP (%s, %s HP)" % [wf["part"], wf["amount"]])
				_check("weapon_still_kind", 1.0 if wf["kind"] == "weapon" else 0.0, 1.0, "eq", "hit kind is weapon (first hit kind %s)" % _first(hits_b)["kind"])
				_check("weapon_still_hp", b.hp, Tuning.MAX_HP, "lt", "victim hp < MAX_HP")
				_check("weapon_still_credit", float(a.stats["weapon_hits"]), 1.0, "gte", "holder stats.weapon_hits >= 1")
				_check("weapon_still_match", float(_count_kind(match_hits, "weapon")), 1.0, "gte", "Match.hit kind weapon emitted")
				_check("weapon_still_feel", float(cam.shakes), 1.0, "gte", "hit_feel shook the camera stub (env scenarios' zero is not a deaf stub)")
				_check("weapon_still_announce", float(_blow_announces()), 1.0, "gte", "HEAD/BODY/DOUBLE BLOW announced")
				var stun_ok := float(wf["amount"]) < Tuning.STUN_DAMAGE_THRESHOLD or _stuns_of(b) >= 1
				_check("weapon_still_stun", 1.0 if stun_ok else 0.0, 1.0, "eq", "hit >= STUN_DAMAGE_THRESHOLD stuns the victim (%d stun events)" % _stuns_of(b))
				report["info"]["weapon_still"] = {"hits_b": hits_b.slice(0, 6), "match_hits": match_hits.slice(0, 6), "shakes": cam.shakes, "zooms": cam.zooms,
					"stuns": stun_events, "b_hp": b.hp, "min_time_scale": scen_min_ts, "events": events.slice(0, 10)}
				_next()
		"weapon_thrown":
			if hammer == null and t >= 0.5:
				report["info"]["weapon_thrown_attached"] = _attach_hammer(b, 1.0)
			if hammer != null and hammer.is_held() and t >= 0.7:
				(b.get_node("WeaponPickup") as WeaponPickup).drop("Hand_L")
				report["info"]["weapon_thrown_dropped_t"] = snappedf(t, 0.01)
			if hammer != null and not hammer.is_held() and t >= 1.2 and impact_t < 0.0 and t < 4.0:
				if prop == null:
					prop = hammer   # отпущенный 0.5 с назад молот переносим к A и бросаем
					var tp := a.torso().global_position
					hammer.global_transform = Transform3D(Basis.IDENTITY, Vector3(tp.x - 2.2, tp.y, 0.0))
				if not hits_a.is_empty() or _touching(a, hammer):
					var who: Node = hammer.attacker(Tuning.WEAPON_ATTACKER_WINDOW_S)
					var who_doll: Variant = who.get("doll") if who != null else null
					_mark_impact(a, {"prop_speed": prop_speed, "attacker_is_b": who_doll == b})
				else:
					_fly_prop(Vector3(10.0, 0, 0))
			if impact_t >= 0.0 and t >= impact_t + 0.5 or t >= 6.0:
				var wf := _first_kind(hits_a, "weapon")
				_check("weapon_thrown_attr", 1.0 if bool(impact_info.get("attacker_is_b", false)) else 0.0, 1.0, "eq",
					"released 0.5 s ago: Weapon.attacker() is the thrower within WEAPON_ATTACKER_WINDOW_S")
				_check("weapon_thrown", float(wf["amount"]), 0.0, "gt", "thrown hammer at 10 m/s: weapon hit > 0 HP (%s, %s HP)" % [wf["part"], wf["amount"]])
				_check("weapon_thrown_kind", float(_count_kind(hits_a, "environment")), 0.0, "lte", "no environment-kind hits (first kind %s)" % _first(hits_a)["kind"])
				_check("weapon_thrown_credit", float(b.stats["weapon_hits"]), 1.0, "gte", "thrower stats.weapon_hits >= 1")
				report["info"]["weapon_thrown"] = {"hits_a": hits_a.slice(0, 6), "match_hits": match_hits.slice(0, 6), "impact": impact_info, "a_hp": a.hp}
				_next()
		"ko_burst":
			if t >= 1.0 and not ko_fired and b.hp > 5.0:
				b.hp = 5.0
			if t >= 1.0 and not ko_fired:
				_inject(a, Vector3(10.0, 0, 0))
			if ko_fired and t >= ko_t + 1.0 or t >= 8.0:
				_check("ko_fired", 1.0 if ko_fired else 0.0, 1.0, "eq", "knocked_out emitted after a hit at hp 5")
				_check("ko_joints", float(b.joints.size()), 0.0, "lte", "Doll.joints empty after KO")
				_check("ko_joint_nodes", float(_joint_nodes(b)), 0.0, "lte", "Generic6DOFJoint3D children freed after KO")
				var valid := 0
				for p in b.parts.values():
					if is_instance_valid(p) and (p as Node).is_inside_tree():
						valid += 1
				_check("ko_parts", float(valid), 14.0, "eq", "14 parts still in the tree after KO")
				_check("ko_alive", 0.0 if b.alive else 1.0, 1.0, "eq", "victim not alive")
				_check("ko_spread", _part_spread(b), 1.5, "gte", "parts spread (max pair distance, m) >= 1.5 one second after KO")
				report["info"]["ko"] = {"hits_b": hits_b.slice(0, 4), "record": _record_summary(b.last_ko_record), "spread": _part_spread(b), "events": events}
				_next()
		"sd_step":
			a.input_vec = Vector2.ZERO
			b.input_vec = Vector2.ZERO
			if m.fight_time >= 5.0 + Tuning.SUDDEN_DEATH_STEP_S + 0.5 or t >= 30.0:
				_check("sd_phase", 1.0 if m.phase == Match.Phase.SUDDEN_DEATH else 0.0, 1.0, "eq", "phase SUDDEN_DEATH after time_limit 5 s (phase=%d)" % m.phase)
				_check("sd_knockback", m.knockback_mult(), 1.25, "eq", "knockback mult 1.25 ten seconds into SD (step %d)" % m.sd_step)
				_check("sd_stability", a.stability_mult, 0.85, "eq", "doll stability mult 0.85 at SD step 1")
				_check("sd_announce", 1.0 if _has_announce("sudden_death") else 0.0, 1.0, "eq", "SUDDEN DEATH announced")
				_check("fight_announce", 1.0 if _has_announce("fight") else 0.0, 1.0, "eq", "FIGHT! announced")
				_check("sd_no_damage", _sum(hits_a) + _sum(hits_b), 0.0, "lte", "idle dolls take no damage during SD")
				report["info"]["sd"] = {"fight_time": m.fight_time, "sd_step": m.sd_step, "events": events, "k_a": a._k, "time_left": m.time_left_s()}
				_next()
		"match_over":
			if not over_fired:
				_rush(a, b)
				_rush(b, a)
			if over_fired and restart_t < 0.0 and t >= over_t + 2.0:
				_checks_match_over()
				old_ids = [a.get_instance_id(), b.get_instance_id()]
				m.restart()
				restart_t = t
			if restart_t >= 0.0 and t >= restart_t + 0.5 or t >= 40.0:
				if restart_t < 0.0:
					_checks_match_over()
				var ds := m.dolls()
				_check("restart_dolls", float(ds.size()), 2.0, "eq", "after restart(): Match.dolls() has 2 dolls")
				var fresh := 0
				var alive := 0
				var on_spawn := 0
				var full_hp := 0
				for d in ds:
					var dd := d as Doll
					if not old_ids.has(dd.get_instance_id()):
						fresh += 1
					if dd.alive and not dd.is_broken():
						alive += 1
					if is_equal_approx(dd.hp, Tuning.MAX_HP):
						full_hp += 1
					var sx := -2.5 if dd.player_index == 0 else 2.5
					if absf(dd.centre_of_mass().x - sx) < 0.6:
						on_spawn += 1
				_check("restart_fresh", float(fresh), 2.0, "eq", "both dolls are new instances")
				_check("restart_alive", float(alive), 2.0, "eq", "both alive and unbroken")
				_check("restart_hp", float(full_hp), 2.0, "eq", "both at MAX_HP")
				_check("restart_spawn", float(on_spawn), 2.0, "eq", "both near their spawn x (±2.5)")
				_check("restart_phase", 1.0 if m.phase == Match.Phase.FIGHT else 0.0, 1.0, "eq", "phase FIGHT after restart with countdown 0 (phase=%d)" % m.phase)
				_check("restart_group", float(get_tree().get_nodes_in_group("dolls").size()), 2.0, "eq", "group dolls has exactly 2 (old freed)")
				_next()
		"double_ko", "double_ko_rev":
			if t >= 1.0 and t < 6.0 and not ko_fired and hits_a.is_empty() and hits_b.is_empty():
				_inject(a, Vector3(DKO_SPEED, 0, 0))
				_inject(b, Vector3(-DKO_SPEED, 0, 0))
			if over_fired and t >= over_t + DKO_RESULTS_S or t >= 10.0:
				_checks_double_ko(s)
				_next()


func _checks_match_over() -> void:
	_check("match_over", 1.0 if over_fired else 0.0, 1.0, "eq", "match_over emitted")
	_check("match_winner", 1.0 if over_winner != null else 0.0, 1.0, "eq", "winner is not null")
	_check("match_winner_a", 1.0 if over_winner == a else 0.0, 1.0, "eq", "winner is the 100 HP doll")
	var places: Array = over_results.get("places", [])
	_check("match_places", float(places.size()), 2.0, "eq", "results.places has 2 dolls")
	_check("match_places_first", 1.0 if not places.is_empty() and places[0] == over_winner else 0.0, 1.0, "eq", "places[0] == winner")
	var medals: Dictionary = over_results.get("medals", {})
	_check("match_medal_winner", 1.0 if medals.get("Winner", null) == over_winner else 0.0, 1.0, "eq", "medals.Winner == winner")
	_check("match_medal_hardest", 1.0 if medals.has("Hardest Hit") else 0.0, 1.0, "eq", "medals.Hardest Hit given")
	_check("match_combo_score", 1.0 if over_results.has("combo_score") and over_results["combo_score"].size() == 2 else 0.0, 1.0, "eq", "results.combo_score for both")
	var stats: Dictionary = over_results.get("stats", {})
	_check("match_stats", float(stats.size()), 2.0, "eq", "results.stats for both dolls")
	_check("ko_announce", 1.0 if _has_announce("ko") else 0.0, 1.0, "eq", "KO! announced")
	_check("time_scale_restored", Engine.time_scale, 1.0, "eq", "Engine.time_scale back to 1 after KO slow-mo")
	_check("time_scale_used", min_time_scale, 1.0, "lt", "hit stop / slow-mo actually lowered time_scale")
	var medal_names: Array = []
	for k in medals.keys():
		medal_names.append("%s:P%d" % [k, (medals[k] as Doll).player_index + 1])
	report["info"]["match"] = {"over_t": over_t, "duration": over_results.get("duration_s", -1.0), "reason": over_results.get("reason", ""),
		"medals": medal_names, "stats_a": a.stats.duplicate(), "stats_b": b.stats.duplicate(), "events": events.slice(0, 20), "hits_b": hits_b.slice(0, 5),
		"min_time_scale": min_time_scale}


func _checks_double_ko(id: String) -> void:
	var recs: Array = m.ko_records
	var frames: Array = []
	var head_head := 0
	for r in recs:
		frames.append(int((r as Dictionary).get("physics_frame", -1)))
		if String((r as Dictionary).get("part", "")).begins_with("Head") and (r as Dictionary).get("kind", "") == "head":
			head_head += 1
	_check(id + "_both_ko", float(int(not a.alive) + int(not b.alive)), 2.0, "eq", "both dolls knocked out")
	_check(id + "_same_tick", 1.0 if frames.size() == 2 and frames[0] == frames[1] else 0.0, 1.0, "eq",
		"two KO records in the same physics tick (frames %s)" % str(frames))
	_check(id + "_head_head", float(head_head), 2.0, "eq", "both KOs by a head-to-head clash (part Head, kind head)")
	_check(id + "_over", 1.0 if over_fired else 0.0, 1.0, "eq", "match_over emitted")
	_check(id + "_draw", 1.0 if bool(over_results.get("draw", false)) else 0.0, 1.0, "eq", "results.draw (no living doll)")
	_check(id + "_winner_null", 1.0 if over_fired and over_winner == null and over_results.get("winner", 0) == null else 0.0, 1.0, "eq",
		"match_over winner and results.winner are null (a dead doll is never the winner)")
	_check(id + "_reason", 1.0 if over_results.get("reason", "") == "ko" else 0.0, 1.0, "eq", "results.reason == ko (%s)" % over_results.get("reason", ""))
	var medals: Dictionary = over_results.get("medals", {})
	_check(id + "_no_winner_medal", 0.0 if medals.has("Winner") else 1.0, 1.0, "eq", "no Winner medal")
	var places: Array = over_results.get("places", [])
	var ranks: Array = over_results.get("ranks", [])
	_check(id + "_ranks", 1.0 if places.size() == 2 and ranks == [0, 0] else 0.0, 1.0, "eq", "both share first place: ranks %s" % str(ranks))
	var crowns := 0
	for k in hud.wins:
		crowns += int(hud.wins[k])
	_check(id + "_hud_no_crown", float(crowns), 0.0, "eq", "HUD awarded no round crown (wins %s)" % str(hud.wins))
	var rp := hud.results
	_check(id + "_hud_draw", 1.0 if rp.visible and rp.winner_name.text == "DRAW!" and not rp.crown.visible else 0.0, 1.0, "eq",
		"HUD results visible with DRAW! and no crown (visible %s, text %s, crown %s)" % [rp.visible, rp.winner_name.text, rp.crown.visible])
	var firsts := 0
	var ko_marks := 0
	for col in rp.places_row.get_children():
		for c in col.get_children():
			if c is Label and (c as Label).text == "1ST":
				firsts += 1
			if c is Portrait and (c as Portrait).knocked_out:
				ko_marks += 1
	_check(id + "_hud_places", float(firsts), 2.0, "eq", "HUD places: both 1ST")
	_check(id + "_hud_ko_marks", float(ko_marks), 2.0, "eq", "HUD places: both portraits knocked out")
	var rec_info: Array = []
	for r in recs:
		rec_info.append(_record_summary(r))
	report["info"][id] = {"ko_frames": frames, "records": rec_info, "over_t": over_t, "hits_a": hits_a.slice(0, 4), "hits_b": hits_b.slice(0, 4),
		"ranks": ranks, "draw": over_results.get("draw", null), "events": events.slice(0, 12)}


func _is_limb(name_: String) -> bool:
	for p in LIMB_PREFIXES:
		if name_.begins_with(p):
			return true
	return false


func _has_announce(kind: String) -> bool:
	for e in events:
		if e.has("announce") and e["kind"] == kind:
			return true
	return false


func _record_summary(r: Dictionary) -> Dictionary:
	var out := {}
	for k in ["kind", "damage", "speed", "weapon_id", "part", "time"]:
		if r.has(k):
			out[k] = r[k]
	var att: Object = r.get("attacker", null)
	out["attacker"] = att.name if att != null and is_instance_valid(att) else ""
	return out


func _finish() -> void:
	var wall_ms := (Time.get_ticks_usec() - wall_start_usec) / 1000.0
	report["info"]["wall_ms_per_tick_avg"] = snappedf(wall_ms / max(total_ticks, 1), 0.001)
	report["info"]["ticks"] = total_ticks
	report["info"]["tuning"] = {"DAMAGE_COEF": Tuning.DAMAGE_COEF, "MIN_IMPACT_SPEED": Tuning.MIN_IMPACT_SPEED, "MASS_CAP": Tuning.MASS_CAP,
		"KNOCKBACK_PER_DAMAGE": Tuning.KNOCKBACK_PER_DAMAGE, "BODY_MULT": Tuning.BODY_MULT, "GRAVITY": Tuning.GRAVITY}
	report["info"]["godot"] = Engine.get_version_info()["string"]
	var js := JSON.stringify(report, "  ")
	print("=== COMBAT GATE ===")
	print(js)
	var f := FileAccess.open("res://tests/combat_gate_report.json", FileAccess.WRITE)
	if f:
		f.store_string(js)
		f.close()
	print("=== %s ===" % ("OK" if report["ok"] else "FAIL"))
	get_tree().quit(0 if report["ok"] else 1)
