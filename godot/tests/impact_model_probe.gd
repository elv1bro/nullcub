## Проба модели удара (docs/plan-demo/IMPACT_MODEL.md): масса против скорости в числах. Только headless.
##   godot --headless --path godot --fixed-fps 60 res://tests/impact_model_probe.tscn -- "mode=ram"
## Режимы (аргумент mode=, через «;» — другие ключи):
##   roster — массы, запас, порог отрыва головы и разгон сборок-пресетов (ids=a,b,…);
##   ram    — управляемые налёты в Void: бьющий (A) запускается со скоростью v в стоящего соперника (D) головой в торс / головой в
##            голову / телом; печатает урон D, урон себе, отлёт D (Δv ЦМ и смещение за 1 с), стан. pairs=a:d,…; v=4,8,12,16;
##   ko     — повторные налёты головой на v (16) до KO одной из кукол (без лечения между налётами) — «разогнался и в нокаут»;
##   matrix — бот против бота (RivalBrain на обоих) в куполе Быстрого боя: победы, длина боя, удары/мин, станы, камбэки,
##            доля урона по бьющей части, доля ударов в ускорении, урон себе. pairs=a:b,…; seeds=1,2,3; max_s=90; level=3.
## Итог каждого режима — строки IMPACT_* (для docs/plan-demo/IMPACT_MODEL.md); exit 0, если проба доработала.
extends Node3D

const PRESET := "res://scenes/body/presets/%s.tscn"
const VOID := "res://scenes/playground_void.tscn"
const HALL := "res://scenes/playground_null_hall.tscn"

var args := {}


## Бот для пары бот-против-бота: цель — группа target_group, своя — own_group (RivalBrain всегда бьёт «players»).
class DuelBrain extends RivalBrain:
	var target_group := "duel_b"
	var own_group := "duel_a"

	func _brain_ready() -> void:
		super._brain_ready()
		players_group = target_group
		enemies_group = own_group


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		for kv in String(a).split(";"):
			var eq := String(kv).find("=")
			if eq > 0:
				args[String(kv).substr(0, eq)] = String(kv).substr(eq + 1)
	if args.has("impact"):   # impact=0 — старая формула (до 23.10), impact=1 — удар по массе
		ImpactModel.on = String(args["impact"]) == "1"
	_run.call_deferred()


func _run() -> void:
	var mode := String(args.get("mode", "roster"))
	print("IMPACT_MODEL drive=%s parthp=%s impact=%s" % [Drive.on, PartHp.on, ImpactModel.on])
	match mode:
		"roster":
			await _roster()
		"ram":
			await _ram()
		"ko":
			await _ko()
		"matrix":
			await _matrix()
		_:
			push_error("impact_model_probe: unknown mode " + mode)
	Engine.time_scale = 1.0
	get_tree().quit(0)


func _list(key: String, def: String) -> PackedStringArray:
	return String(args.get(key, def)).split(",", false)


func _pairs(def: String) -> Array:
	var out: Array = []
	for p in _list("pairs", def):
		var ab := String(p).split(":")
		if ab.size() == 2:
			out.append([ab[0], ab[1]])
	return out


# --- roster ---

func _roster() -> void:
	var ids := _list("ids", "")
	if ids.is_empty():
		ids = PackedStringArray(Array(CraftEdit.BODY_PRESETS) + ["boss_titan"])
	for id in ids:
		var path := PRESET % id
		if not ResourceLoader.exists(path):
			print("ROSTER ", id, " missing")
			continue
		var d := (load(path) as PackedScene).instantiate() as Doll
		add_child(d)
		await get_tree().physics_frame
		var head := d.parts.get("Head") as RigidBody3D
		var torso := d.torso()
		var hhp := float(d.part_hp.get("Head", 0.0))
		print("ROSTER %-16s m=%6.1f n=%2d torso=%5.1f head=%4.1f hp=%5.0f head_hp=%3.0f head_break=%5.1f accel=%5.2f" % [id, d.total_mass,
			d.parts.size(), torso.mass if torso else 0.0, head.mass if head else 0.0, d.parts_hp_total(), hhp, PartHp.break_hp(hhp, true),
			d.thrust_mass() * Tuning.MOVE_FORCE_PER_KG / maxf(d.total_mass, 1.0)])
		if args.get("parts", "") == "1":
			for n in d.parts:
				var b := d.parts[n] as RigidBody3D
				print("  PART %-14s m=%5.2f bm=%4.2f shape=%4.2f/%s armor=%4.2f tm=%4.2f hp=%3.0f" % [n, b.mass, Damage.body_mult_of_body(b),
					float(b.get_meta("shape_mult", 1.0)), String(b.get_meta("shape_profile", "")), float(b.get_meta("armor", 0.0)),
					Damage.target_mult_of_body(b), float(d.part_hp.get(n, 0.0))])
		d.queue_free()
		await get_tree().physics_frame


# --- сцена с двумя пресетами ---

func _swap(root: Node, pname: String, id: String) -> Doll:
	var old := root.get_node_or_null(pname) as Doll
	var path := PRESET % id
	if old == null or not ResourceLoader.exists(path):
		push_error("impact_model_probe: нет %s или %s" % [pname, path])
		return null
	var d := (load(path) as PackedScene).instantiate() as Doll
	d.transform = old.transform
	d.player_index = old.player_index
	d.input_prefix = old.input_prefix
	for g in old.get_groups():
		d.add_to_group(g)
	for c in old.get_children():
		if not (c is RigidBody3D or c is Joint3D) and c.get_script() != null:
			var n: Node = (c.get_script() as Script).new()
			n.name = c.name
			d.add_child(n)
	var idx := old.get_index()
	root.remove_child(old)
	old.free()
	d.name = pname
	root.add_child(d)
	root.move_child(d, idx)
	return d


func _scene(path: String, a_id: String, d_id: String) -> Dictionary:
	var pg := (load(path) as PackedScene).instantiate()
	var a := _swap(pg, "P1", a_id)
	var d := _swap(pg, "P2", d_id)
	var m := pg.get_node("Match") as Match
	m.countdown_s = 0.2
	m.time_limit_s = 100000.0
	m.hard_timeout_s = 100000.0
	add_child(pg)
	return {"pg": pg, "a": a, "d": d, "m": m}


func _free_scene(s: Dictionary) -> void:
	(s["pg"] as Node).queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Engine.time_scale = 1.0


func _wait_fight(m: Match) -> void:
	var guard := 0
	while m.phase != Match.Phase.FIGHT and guard < 600:
		guard += 1
		await get_tree().physics_frame


func _frames(n: int) -> void:
	for i in n:
		Engine.time_scale = 1.0   # стоп-кадры и замедления не меняют физику пробы
		await get_tree().physics_frame


# --- управляемый налёт ---

## Положения частей относительно торса.
func _capture(d: Doll) -> Dictionary:
	var t := d.torso().global_transform
	var r := {}
	for n in d.parts:
		r[n] = t.affine_inverse() * (d.parts[n] as RigidBody3D).global_transform
	return {"rel": r, "torso": t}


func _place(d: Doll, cap: Dictionary, torso_xf: Transform3D, vel: Vector3) -> void:
	var rel: Dictionary = cap["rel"]
	for n in rel:
		var b := d.parts.get(n) as RigidBody3D
		if b == null or not is_instance_valid(b):
			continue
		b.global_transform = torso_xf * (rel[n] as Transform3D)
		b.linear_velocity = vel
		b.angular_velocity = Vector3.ZERO
		DollCombat.prev_vel[b] = [vel, Vector3.ZERO]


func _part_pos(cap: Dictionary, torso_xf: Transform3D, part: String) -> Vector3:
	var rel: Dictionary = cap["rel"]
	if not rel.has(part):
		return torso_xf.origin
	return (torso_xf * (rel[part] as Transform3D)).origin


func _x_extent(positions: Array, maxx: bool) -> float:
	var e := -INF if maxx else INF
	for p in positions:
		e = maxf(e, (p as Vector3).x) if maxx else minf(e, (p as Vector3).x)
	return e


## Запуск A в D со скоростью v по +x: kind head_torso | head_head (голова вперёд) | body | torso_head (торсом в торс / в голову D).
func _launch(a: Doll, cap_a: Dictionary, d: Doll, kind: String, v: float) -> void:
	var t0: Transform3D = cap_a["torso"]
	var basis := t0.basis
	var lead := "Torso"
	var target := d.torso().global_position
	if kind.begins_with("head"):
		basis = Basis(Vector3(0, 0, 1), -PI / 2.0) * t0.basis   # голова вперёд (+x)
		lead = "Head"
	if kind.ends_with("_head") and d.parts.has("Head"):
		target = (d.parts["Head"] as RigidBody3D).global_position
	var xf := Transform3D(basis, Vector3.ZERO)
	var lp := _part_pos(cap_a, xf, lead)
	xf.origin = Vector3(target.x - lp.x, target.y - lp.y, t0.origin.z)
	# зазор: самая правая часть A левее самой левой части D на 0.12 м (радиусы ≈ 0.18)
	var pa: Array = []
	for n in cap_a["rel"]:
		pa.append(_part_pos(cap_a, xf, n))
	var pd: Array = []
	for b in d.parts.values():
		pd.append((b as RigidBody3D).global_position)
	var shift := (_x_extent(pa, true) + 0.18) - (_x_extent(pd, false) - 0.18) + 0.12
	xf.origin.x -= shift
	_place(a, cap_a, xf, Vector3(v, 0.0, 0.0))


## Чистый налёт (clean=1, по умолчанию): с куклой D сталкивается только ведущая часть A (голова / торс), и не с руками D —
## иначе первым касается чужая кисть-«блок» или своё плечо, и кулдаун пары съедает удар головой (это видно в бою, см. matrix).
func _clean_exceptions(a: Doll, d: Doll, kind: String) -> Array:
	var lead := "Head" if kind.begins_with("head") else "Torso"
	var out: Array = []
	for an in a.parts:
		var ab := a.parts[an] as RigidBody3D
		for dn in d.parts:
			var base := Doll.part_base_name(String(dn))
			var arm := base == "UpperArm" or base == "LowerArm" or base == "Hand"
			if String(an) != lead or arm:
				var db := d.parts[dn] as RigidBody3D
				ab.add_collision_exception_with(db)
				out.append([ab, db])
	return out


func _reset_doll(d: Doll, cap: Dictionary) -> void:
	d.reset_for_match()
	d.refresh_wear()
	d.hp = d.max_hp
	var c := DollCombat.combat_of(d)
	if c != null:
		c.reset()
	_place(d, cap, cap["torso"], Vector3.ZERO)


func _ram() -> void:
	var pairs := _pairs("legless:kit_horned,kit_horned:legless,kit_human:kit_human,junk:kit_king,kit_king:junk")
	var kinds := _list("kinds", "head_torso,head_head,body,torso_head")
	var speeds: Array = []
	for s in _list("v", "4,8,12,16"):
		speeds.append(float(s))
	print("IMPACT_RAM_HEAD pair kind v | hit_v striker dmg_D self_A | D_dv D_dx1s stun | A_vx_after | mA mD")
	for pr in pairs:
		var s := _scene(VOID, pr[0], pr[1])
		var a: Doll = s["a"]
		var d: Doll = s["d"]
		var m: Match = s["m"]
		if a == null or d == null:
			continue
		await _wait_fight(m)
		a.external_input = true
		d.external_input = true
		a.input_vec = Vector2.ZERO
		d.input_vec = Vector2.ZERO
		await _frames(50)
		var cap_a := _capture(a)
		var cap_d := _capture(d)
		for kind in kinds:
			for v in speeds:
				_reset_doll(a, cap_a)
				_reset_doll(d, cap_d)
				a.control_enabled = true
				await _frames(48)   # grace 0.7 с, кукла D встаёт
				var r := await _one_ram(a, cap_a, d, kind, v)
				print("IMPACT_RAM %s>%s %-10s v=%4.1f | hit_v=%5.2f %-10s dmg_D=%5.1f self_A=%5.1f | D_dv=%4.2f D_dx=%5.2f stun=%3.1f | A_vx=%5.2f | mA=%4.1f mD=%4.1f hits=%d" % [
					pr[0], pr[1], kind, v, r["hit_v"], r["striker"], r["dmg_d"], r["self_a"], r["d_dv"], r["d_dx"], r["stun"], r["a_vx"],
					a.total_mass, d.total_mass, r["n"]])
		await _free_scene(s)


## Один налёт: 1.2 с наблюдения от запуска. Урон считается по сигналу damaged (A ↔ D).
func _one_ram(a: Doll, cap_a: Dictionary, d: Doll, kind: String, v: float) -> Dictionary:
	var r := {"dmg_d": 0.0, "self_a": 0.0, "hit_v": 0.0, "striker": "-", "stun": 0.0, "d_dv": 0.0, "d_dx": 0.0, "a_vx": 0.0, "n": 0, "t_hit": -1}
	var on_d := func(amount: float, attacker: Node, _p: String, _pos: Vector3, _k: String) -> void:
		if attacker == a:
			r["dmg_d"] = float(r["dmg_d"]) + amount
			r["n"] = int(r["n"]) + 1
			if int(r["t_hit"]) < 0:
				r["t_hit"] = 0
				r["hit_v"] = float(d.last_hit.get("speed", 0.0))
				r["striker"] = Doll.part_base_name(String(d.last_hit.get("striker_name", "")))
				if args.get("debug", "") == "1":
					print("  DEBUG last_hit ", d.last_hit)
			r["stun"] = maxf(float(r["stun"]), float(d.last_hit.get("stun_s", 0.0)))
	var on_a := func(amount: float, attacker: Node, _p: String, _pos: Vector3, _k: String) -> void:
		if attacker == d:
			r["self_a"] = float(r["self_a"]) + amount
	d.damaged.connect(on_d)
	a.damaged.connect(on_a)
	a.control_enabled = false
	a.brake_off = true
	var com0 := d.centre_of_mass()
	var v0 := _com_vel(d)
	var ex := _clean_exceptions(a, d, kind) if args.get("clean", "1") == "1" else []
	_launch(a, cap_a, d, kind, v)
	var hit_frame := -1
	for f in 90:
		await _frames(1)
		if int(r["t_hit"]) >= 0 and hit_frame < 0:
			hit_frame = f
			com0 = d.centre_of_mass()
		if hit_frame >= 0:
			r["d_dv"] = maxf(float(r["d_dv"]), (_com_vel(d) - v0).length())
			if f - hit_frame == 12:
				r["a_vx"] = _com_vel(a).x
			if f - hit_frame == 60:
				r["d_dx"] = d.centre_of_mass().x - com0.x
	for pair in ex:
		if is_instance_valid(pair[0]) and is_instance_valid(pair[1]):
			(pair[0] as PhysicsBody3D).remove_collision_exception_with(pair[1])
	d.damaged.disconnect(on_d)
	a.damaged.disconnect(on_a)
	a.brake_off = false
	return r


func _com_vel(d: Doll) -> Vector3:
	var p := Vector3.ZERO
	for b in d.parts.values():
		p += (b as RigidBody3D).linear_velocity * (b as RigidBody3D).mass
	return p / maxf(d.total_mass, 0.001)


# --- налёты до KO ---

func _ko() -> void:
	var pairs := _pairs("legless:kit_horned,junk:kit_king,kit_human:kit_king,kit_human:kit_human,kit_horned:legless")
	var kinds := _list("kinds", "head_torso,head_head,torso_head")
	var v := float(args.get("v", "16"))
	var max_rams := int(args.get("rams", "30"))
	for pr in pairs:
		for kind in kinds:
			var s := _scene(VOID, pr[0], pr[1])
			var a: Doll = s["a"]
			var d: Doll = s["d"]
			var m: Match = s["m"]
			if a == null or d == null:
				continue
			await _wait_fight(m)
			a.external_input = true
			d.external_input = true
			a.input_vec = Vector2.ZERO
			d.input_vec = Vector2.ZERO
			await _frames(50)
			var cap_a := _capture(a)
			var ko_why := {"A": "-", "D": "-"}   # причина KO: kind последнего удара / reason (bounds — вылет)
			a.knocked_out.connect(func(by: Node, rec: Dictionary) -> void:
				ko_why["A"] = "%s/%s/%s" % [rec.get("kind", "?"), rec.get("reason", ""), "D" if by == d else ("A" if by == a else "-")])
			d.knocked_out.connect(func(by: Node, rec: Dictionary) -> void:
				ko_why["D"] = "%s/%s/%s" % [rec.get("kind", "?"), rec.get("reason", ""), "A" if by == a else ("D" if by == d else "-")])
			var dmg_tot := 0.0
			var self_tot := 0.0
			var rams := 0
			var first := 0.0
			var who := "none"
			while rams < max_rams:
				if not a.alive or not d.alive or a.is_broken() or d.is_broken():
					break
				rams += 1
				var r := await _one_ram(a, cap_a, d, kind, v)
				if rams == 1:
					first = float(r["dmg_d"])
				dmg_tot += float(r["dmg_d"])
				self_tot += float(r["self_a"])
				await _frames(20)
			if not d.alive:
				who = "D"
			elif not a.alive:
				who = "A"
			print("IMPACT_KO %s>%s %-10s v=%4.1f rams=%2d ko=%s first=%5.1f dmg_D=%6.1f self_A=%6.1f hpD=%5.1f/%5.1f hpA=%5.1f/%5.1f headA=%s headD=%s why=%s" % [
				pr[0], pr[1], kind, v, rams, who, first, dmg_tot, self_tot, d.hp, d.max_hp, a.hp, a.max_hp,
				"on" if a.parts.has("Head") else "OFF", "on" if d.parts.has("Head") else "OFF", ko_why[who] if who != "none" else "-"])
			await _free_scene(s)


# --- бот против бота ---

var _mx: Dictionary = {}


func _matrix() -> void:
	var pairs := _pairs("legless:kit_horned,junk:kit_king,kit_human:kit_king,kit_human:kit_human,kit_horned:kit_king")
	var seeds := _list("seeds", "1,2,3")
	var max_s := float(args.get("max_s", "90"))
	var level := int(args.get("level", "3"))
	var all_hits: Array = []
	for pr in pairs:
		var agg := {"games": 0, "win_a": 0, "win_b": 0, "draw": 0, "len": [], "hits": 0, "stuns": 0, "comebacks": 0, "fight_s": 0.0,
			"dmg_a": 0.0, "dmg_b": 0.0, "ko": 0}
		for sd in seeds:
			for flip in [false, true]:   # обе стороны арены
				var res := await _duel(pr[0], pr[1], int(sd), flip, max_s, level, all_hits)
				agg["games"] = int(agg["games"]) + 1
				if res["winner"] == "A":
					agg["win_a"] = int(agg["win_a"]) + 1
				elif res["winner"] == "B":
					agg["win_b"] = int(agg["win_b"]) + 1
				else:
					agg["draw"] = int(agg["draw"]) + 1
				(agg["len"] as Array).append(float(res["t"]))
				agg["fight_s"] = float(agg["fight_s"]) + float(res["t"])
				agg["hits"] = int(agg["hits"]) + int(res["hits"])
				agg["stuns"] = int(agg["stuns"]) + int(res["stuns"])
				agg["comebacks"] = int(agg["comebacks"]) + (1 if bool(res["comeback"]) else 0)
				agg["dmg_a"] = float(agg["dmg_a"]) + float(res["dmg_a"])
				agg["dmg_b"] = float(agg["dmg_b"]) + float(res["dmg_b"])
				agg["ko"] = int(agg["ko"]) + (1 if bool(res["ko"]) else 0)
				print("IMPACT_DUEL %s:%s seed=%s flip=%s winner=%s ko=%s t=%5.1f hits=%d stuns=%d comeback=%s dmgA=%5.1f dmgB=%5.1f hpA=%5.1f hpB=%5.1f react=%4.1f" % [
					pr[0], pr[1], sd, flip, res["winner"], res["ko"], res["t"], res["hits"], res["stuns"], res["comeback"], res["dmg_a"],
					res["dmg_b"], res["hp_a"], res["hp_b"], res["react"]])
		var lens: Array = agg["len"]
		lens.sort()
		var fs := maxf(float(agg["fight_s"]), 1.0)
		print("IMPACT_MATRIX %s:%s games=%d winA=%d winB=%d draw=%d ko=%d median_s=%5.1f hits_min=%5.1f stuns_min=%4.2f comebacks=%d dmg_by_A=%5.1f dmg_by_B=%5.1f" % [
			pr[0], pr[1], agg["games"], agg["win_a"], agg["win_b"], agg["draw"], agg["ko"], float(lens[lens.size() / 2]) if not lens.is_empty() else 0.0,
			float(agg["hits"]) * 60.0 / fs, float(agg["stuns"]) * 60.0 / fs, agg["comebacks"], float(agg["dmg_a"]) / float(agg["games"]),
			float(agg["dmg_b"]) / float(agg["games"])])
	_hit_summary(all_hits)


func _duel(a_id: String, b_id: String, sd: int, flip: bool, max_s: float, level: int, all_hits: Array) -> Dictionary:
	var s := _scene(HALL, b_id if flip else a_id, a_id if flip else b_id)
	var pa: Doll = s["d"] if flip else s["a"]
	var pb: Doll = s["a"] if flip else s["d"]
	var m: Match = s["m"]
	var res := {"winner": "", "ko": false, "t": 0.0, "hits": 0, "stuns": 0, "comeback": false, "dmg_a": 0.0, "dmg_b": 0.0, "hp_a": 0.0, "hp_b": 0.0,
		"react": 0.0}
	if pa == null or pb == null:
		await _free_scene(s)
		return res
	pa.add_to_group("duel_a")
	pb.add_to_group("duel_b")
	for pair in [[pa, "duel_b", "duel_a"], [pb, "duel_a", "duel_b"]]:
		var br := DuelBrain.new()
		br.name = "DuelBrain"
		br.level = level
		br.target_group = pair[1]
		br.own_group = pair[2]
		(pair[0] as Doll).add_child(br)
		br._rng.seed = hash("%d:%s" % [sd, pair[1]])
	var over := {"done": false, "winner": null}
	m.match_over.connect(func(w: Doll, _r: Dictionary) -> void:
		over["done"] = true
		over["winner"] = w)
	var worst := {"A": 0.0, "B": 0.0}   # наибольшее отставание по доле HP
	var on_hit := func(victim: Doll, attacker: Node, amount: float, kind: String, side_v: String, vpart: String) -> void:
		if not (attacker is Doll) or attacker == victim or m.phase != Match.Phase.FIGHT:
			return
		if kind == "self":   # отдача своей головы (ImpactModel) — не удар соперника
			all_hits.append({"react": true, "dmg": amount})
			res["react"] = float(res["react"]) + amount
			return
		var lh: Dictionary = victim.last_hit
		var sname := String(lh.get("striker_name", ""))
		var st: Object = lh.get("striker") if lh.get("striker") is Object else null
		var base := "Weapon" if st is Weapon else Doll.part_base_name(sname)
		var att := attacker as Doll
		all_hits.append({"dmg": amount, "base": base, "kind": kind, "dash": att.is_dashing(), "speed": float(lh.get("speed", 0.0)),
			"m_att": att.total_mass, "m_vic": victim.total_mass, "stun": float(lh.get("stun_s", 0.0)), "target": Doll.part_base_name(vpart)})
		res["hits"] = int(res["hits"]) + 1
		if float(lh.get("stun_s", 0.0)) > 0.0:
			res["stuns"] = int(res["stuns"]) + 1
		if side_v == "A":
			res["dmg_b"] = float(res["dmg_b"]) + amount
		else:
			res["dmg_a"] = float(res["dmg_a"]) + amount
	var cb_a := func(amount: float, attacker: Node, vp: String, _pos: Vector3, kind: String) -> void:
		on_hit.call(pa, attacker, amount, kind, "A", vp)
	var cb_b := func(amount: float, attacker: Node, vp: String, _pos: Vector3, kind: String) -> void:
		on_hit.call(pb, attacker, amount, kind, "B", vp)
	pa.damaged.connect(cb_a)
	pb.damaged.connect(cb_b)
	await _wait_fight(m)
	var guard := 0
	while not bool(over["done"]) and m.fight_time < max_s and guard < 60 * 600:
		guard += 1
		Engine.time_scale = 1.0
		await get_tree().physics_frame
		if is_instance_valid(pa) and is_instance_valid(pb) and pa.max_hp > 0.0 and pb.max_hp > 0.0:
			var fa := pa.hp / pa.max_hp
			var fb := pb.hp / pb.max_hp
			worst["A"] = maxf(float(worst["A"]), fb - fa)
			worst["B"] = maxf(float(worst["B"]), fa - fb)
	res["t"] = m.fight_time
	res["hp_a"] = pa.hp if is_instance_valid(pa) else 0.0
	res["hp_b"] = pb.hp if is_instance_valid(pb) else 0.0
	var w: Variant = over["winner"]
	if bool(over["done"]):
		res["ko"] = (is_instance_valid(pa) and not pa.alive) or (is_instance_valid(pb) and not pb.alive)
	if w is Doll and is_instance_valid(w):
		res["winner"] = "A" if w == pa else ("B" if w == pb else "")
	elif not bool(over["done"]) and is_instance_valid(pa) and is_instance_valid(pb):
		var fa := pa.hp / maxf(pa.max_hp, 1.0)
		var fb := pb.hp / maxf(pb.max_hp, 1.0)
		res["winner"] = "A" if fa > fb + 0.02 else ("B" if fb > fa + 0.02 else "")
	if res["winner"] != "":
		res["comeback"] = float(worst[res["winner"]]) >= 0.25   # победитель отставал на ≥ 25 % HP
	await _free_scene(s)
	return res


func _hit_summary(all: Array) -> void:
	var hits: Array = []
	var react := [0, 0.0]
	for h in all:
		if bool(h.get("react", false)):
			react[0] += 1
			react[1] += float(h["dmg"])
		else:
			hits.append(h)
	print("IMPACT_REACT n=%d total=%.0f" % [react[0], react[1]])
	if hits.is_empty():
		print("IMPACT_HITS none")
		return
	var tot := 0.0
	var by_base: Dictionary = {}
	var dash_dmg := 0.0
	var dash_n := 0
	var big := 0
	var dmgs: Array = []
	for h in hits:
		var dm := float(h["dmg"])
		tot += dm
		dmgs.append(dm)
		var b := String(h["base"])
		if not by_base.has(b):
			by_base[b] = [0, 0.0]
		by_base[b][0] += 1
		by_base[b][1] += dm
		if bool(h["dash"]):
			dash_n += 1
			dash_dmg += dm
		if dm >= 20.0:
			big += 1
	dmgs.sort()
	print("IMPACT_HITS n=%d total=%.0f mean=%.1f p50=%.1f p90=%.1f p99=%.1f max=%.1f big20=%d dash_share_n=%.2f dash_share_dmg=%.2f" % [
		hits.size(), tot, tot / hits.size(), dmgs[dmgs.size() / 2], dmgs[int(dmgs.size() * 0.9)], dmgs[mini(int(dmgs.size() * 0.99), dmgs.size() - 1)],
		dmgs[-1], big, float(dash_n) / hits.size(), dash_dmg / maxf(tot, 0.001)])
	var keys := by_base.keys()
	keys.sort_custom(func(x, y) -> bool: return float(by_base[x][1]) > float(by_base[y][1]))
	for k in keys:
		print("IMPACT_PART %-10s n=%4d share_n=%.2f share_dmg=%.2f mean=%.1f" % [k, by_base[k][0], float(by_base[k][0]) / hits.size(),
			float(by_base[k][1]) / maxf(tot, 0.001), float(by_base[k][1]) / maxf(float(by_base[k][0]), 1.0)])
	# урон по соотношению масс: лёгкий бьёт тяжёлого и наоборот
	var lh := [0, 0.0]
	var hl := [0, 0.0]
	for h in hits:
		var ratio := float(h["m_att"]) / maxf(float(h["m_vic"]), 1.0)
		if ratio < 0.7:
			lh[0] += 1
			lh[1] += float(h["dmg"])
		elif ratio > 1.4:
			hl[0] += 1
			hl[1] += float(h["dmg"])
	print("IMPACT_MASS light_hits_heavy n=%d mean=%.1f | heavy_hits_light n=%d mean=%.1f" % [lh[0], lh[1] / maxf(lh[0], 1.0), hl[0], hl[1] / maxf(hl[0], 1.0)])
	# по какой детали попадают: доля ударов и урона в голову
	var tg: Dictionary = {}
	for h in hits:
		var t := String(h.get("target", "?"))
		if not tg.has(t):
			tg[t] = [0, 0.0]
		tg[t][0] += 1
		tg[t][1] += float(h["dmg"])
	var tk := tg.keys()
	tk.sort_custom(func(x, y) -> bool: return float(tg[x][1]) > float(tg[y][1]))
	for k in tk:
		print("IMPACT_TARGET %-10s n=%4d share_n=%.2f share_dmg=%.2f mean=%.1f" % [k, tg[k][0], float(tg[k][0]) / hits.size(),
			float(tg[k][1]) / maxf(tot, 0.001), float(tg[k][1]) / maxf(float(tg[k][0]), 1.0)])
