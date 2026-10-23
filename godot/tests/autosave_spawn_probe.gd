## Проба спавна чертежа из мастерской (P2, 23.10, docs/plan-demo/GAUNTLET.md «Автосейв мастерской»): автосейв игрока разлетался
## в первые кадры после спавна — ЦМ P1 из (−5, 1) в (−1, 30), тела в NaN. Фикстура tests/fixtures/blueprints/autosave_exploding.tres —
## копия того автосейва («Человек (кукла v3) *», 12 деталей, трос T↔A с концами на z = +0.12 и +0.07). Причина — связка, чьи концы
## не в плоскости боя (LinkBuilder.flat_ends). Проверки (кукла на полу, SECONDS физики; ЦМ конечен, ушёл ≤ MAX_DRIFT_M, поднялся ≤ MAX_RISE_M):
##   control — кит «Человек» без связок;
##   fixture — фикстура SPAWNS раз (взрыв не каждый спавн: зависел от мелочей позиции), ещё 2 раза с запасом из деталей (PartHp);
##   offplane — кит «Человек» + связка каждого вида (rod, bar, spring, rope, piston) торс спереди (z +0.12) → бедро сзади (z −0.05).
##   godot --headless --path godot --fixed-fps 60 res://tests/autosave_spawn_probe.tscn
##   -- "bisect=1" — ещё варианты фикстуры без каждого узла / без связок (диагностика, не проверки);
##   -- "trace=N" — N спавнов фикстуры, первые 14 кадров: связки, самые быстрые тела, нечисла (только печать).
## → JSON между === AUTOSAVE SPAWN PROBE === и === OK / FAIL ===, exit 0/1.
extends Node3D

const DOLL := preload("res://scenes/body/modular_doll.tscn")
const FIXTURE := "res://tests/fixtures/blueprints/autosave_exploding.tres"
const HUMAN := "res://data/body/blueprints/kit_human.tres"
const SECONDS := 3.0
const SPAWNS := 4
const MAX_DRIFT_M := 1.5
const MAX_RISE_M := 1.0

var ok := true
var checks: Array = []
var info := {}
var _x := 0.0


func _check(cond: bool, name: String, value: Variant = null) -> void:
	checks.append({"ok": cond, "name": name, "value": value})
	if not cond:
		ok = false


func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		for kv in String(a).split(",", false):
			var p := kv.split("=")
			out[p[0]] = p[1] if p.size() > 1 else "1"
	return out


static func com_of(d: Doll) -> Vector3:
	var m := 0.0
	var s := Vector3.ZERO
	for n in d.parts:
		var b := d.parts[n] as RigidBody3D
		if b == null or not is_instance_valid(b):
			continue
		s += (b.global_transform * b.center_of_mass) * b.mass
		m += b.mass
	return s / maxf(m, 1e-6)


func _spawn(bp: BodyBlueprint) -> ModularDoll:
	var d := DOLL.instantiate() as ModularDoll
	d.blueprint = bp
	d.external_input = true
	d.position = Vector3(_x, 0.0, 0.0)
	_x += 12.0
	add_child(d)
	d.grace_until = -1.0
	return d


## Спавн чертежа и SECONDS физики: {finite, drift, rise, first (кадр, где ЦМ ушёл > 0.5 м), fast, c0, c1, links, errors}.
func _run(bp: BodyBlueprint) -> Dictionary:
	var d := _spawn(bp)
	await get_tree().physics_frame
	var c0 := com_of(d)
	var finite := c0.is_finite()
	var drift := 0.0
	var rise := 0.0
	var first := -1
	var fast := ""
	for i in range(int(SECONDS * 60.0)):
		await get_tree().physics_frame
		var c := com_of(d)
		if not c.is_finite():
			finite = false
			continue
		drift = maxf(drift, c.distance_to(c0))
		rise = maxf(rise, c.y - c0.y)
		if first < 0 and c.distance_to(c0) > 0.5:
			first = i
			var far := 0.0
			for n in d.parts:
				var b := d.parts[n] as RigidBody3D
				if b != null and b.linear_velocity.length() > far:
					far = b.linear_velocity.length()
					fast = "%s v=%.1f" % [n, far]
	var c1 := com_of(d)
	var r := {"finite": finite and c1.is_finite(), "c0": [snappedf(c0.x - d.position.x, 0.01), snappedf(c0.y, 0.01)],
		"c1": [snappedf(c1.x - d.position.x, 0.01), snappedf(c1.y, 0.01)], "drift": snappedf(drift, 0.01), "rise": snappedf(rise, 0.01),
		"first": first, "fast": fast, "links": d.links_rt.size(), "errors": Array(d.build_errors), "bodies": d.parts.size()}
	d.queue_free()
	await get_tree().physics_frame
	return r


static func _sane(r: Dictionary) -> bool:
	return bool(r["finite"]) and float(r["drift"]) < MAX_DRIFT_M and float(r["rise"]) < MAX_RISE_M


static func _brief(r: Dictionary) -> Array:
	return [r["finite"], r["drift"], r["rise"], r["first"], r["fast"]]


func _ready() -> void:
	var floor := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(800.0, 1.0, 8.0)
	cs.shape = bx
	floor.add_child(cs)
	floor.position = Vector3(300.0, -0.5, 0.0)
	add_child(floor)
	var args := _args()
	if args.has("trace"):
		await _trace(int(args["trace"]))
		get_tree().quit(0)
		return
	var was_parts := PartHp.on
	PartHp.set_on(false)

	# control
	var human := await _run(load(HUMAN) as BodyBlueprint)
	info["kit_human"] = human
	_check(_sane(human), "кит «Человек» стоит (контроль)", _brief(human))

	# fixture
	var fx := load(FIXTURE) as BodyBlueprint
	info["fixture_structural_errors"] = Array(CraftEdit.structural_errors(fx))
	_check(CraftEdit.structural_errors(fx).is_empty() and fx.validate().is_empty(), "фикстура — целый чертёж (проходит structural_errors и validate)",
		info["fixture_structural_errors"])
	var runs: Array = []
	for k in range(SPAWNS + 2):
		PartHp.set_on(k >= SPAWNS)
		var r := await _run(fx.duplicate(true) as BodyBlueprint)
		r["parthp"] = k >= SPAWNS
		runs.append(r)
		_check(_sane(r) and int(r["links"]) == 1,
			"автосейв из фикстуры, спавн %d%s: ЦМ конечен, за %.0f с ушёл ≤ %.1f м, поднялся ≤ %.1f м; трос собран" % [k + 1,
			" (PartHp)" if k >= SPAWNS else "", SECONDS, MAX_DRIFT_M, MAX_RISE_M], _brief(r) + [r["links"]])
	PartHp.set_on(false)
	info["fixture"] = runs

	# offplane: каждый вид связки, концы на разной глубине
	var off := {}
	for t in KitLink.ORDER:
		var bp := (load(HUMAN) as BodyBlueprint).duplicate(true) as BodyBlueprint
		bp.id = "autosave_spawn_probe_" + String(t)
		bp.energy_budget = 1000
		var ls: Array[Dictionary] = [{"id": "1", "type": String(t), "a": "T", "pa": Vector3(-0.07, -0.2, 0.12), "b": "4",
			"pb": Vector3(0.0, 0.05, -0.05), "len": 0.3}]
		bp.links = ls
		var r := await _run(bp)
		off[t] = r
		_check(_sane(r) and int(r["links"]) == 1, "связка «%s» торс (z +0.12) → бедро (z −0.05): кукла стоит, ЦМ конечен" % t,
			_brief(r) + [r["links"]])
	info["offplane"] = off

	if args.has("bisect"):
		info["bisect"] = await _bisect(fx)

	PartHp.set_on(was_parts)
	print("=== AUTOSAVE SPAWN PROBE ===")
	print(JSON.stringify({"ok": ok, "checks": checks, "info": info}, " "))
	print("=== %s ===" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


## Фикстура без связок и без каждого узла (с веткой): что из чертежа разносит куклу.
func _bisect(fx: BodyBlueprint) -> Dictionary:
	var bis := {}
	var nl := fx.duplicate(true) as BodyBlueprint
	nl.links = [] as Array[Dictionary]
	bis["no_links"] = await _run(nl)
	for n in fx.nodes:
		var uid := String(n["uid"])
		if uid == "T" or uid == "H":
			continue
		var v := fx.duplicate(true) as BodyBlueprint
		var drop := {uid: true}
		var changed := true
		while changed:
			changed = false
			for m in v.nodes:
				if not drop.has(String(m["uid"])) and drop.has(String(m.get("parent", ""))):
					drop[String(m["uid"])] = true
					changed = true
		var keep: Array[Dictionary] = []
		for m in v.nodes:
			if not drop.has(String(m["uid"])):
				keep.append(m)
		v.nodes = keep
		var kl: Array[Dictionary] = []
		for l in v.links:
			if not drop.has(String(l["a"])) and not drop.has(String(l["b"])):
				kl.append(l)
		v.links = kl
		bis["drop_%s_%s" % [uid, String(n["part"])]] = await _run(v)
	return bis


## Диагностика: n спавнов фикстуры, первые кадры — связки, самые быстрые тела, нечисла.
func _trace(n: int) -> void:
	var fx := load(FIXTURE) as BodyBlueprint
	for k in range(n):
		var d := _spawn(fx.duplicate(true) as BodyBlueprint)
		for ln in d.links_rt:
			var rec: Dictionary = d.links_rt[ln]
			var s := "spawn %d %s len=%.3f bodies=%d:" % [k, ln, float(rec["len"]), (rec["bodies"] as Array).size()]
			for b in rec["bodies"]:
				var rb := b as RigidBody3D
				s += " %s m=%.3f p=%s" % [rb.name, rb.mass, str(rb.position)]
			print(s)
			for j in rec["joints"]:
				var jj := j as Generic6DOFJoint3D
				print("   joint %s at %s a=%s b=%s" % [jj.name, str(jj.position), jj.node_a, jj.node_b])
		for f in range(14):
			await get_tree().physics_frame
			var worst := ""
			var wv := -1.0
			var bad: Array = []
			for pn in d.parts:
				var rb := d.parts[pn] as RigidBody3D
				var v := rb.linear_velocity.length()
				if not is_finite(v) or not rb.global_position.is_finite():
					bad.append(pn)
				elif v > wv:
					wv = v
					worst = pn
			print("  f%d com=%s worst=%s v=%.2f bad=%s" % [f, str(com_of(d) - d.position), worst, wv, str(bad)])
		d.queue_free()
		await get_tree().physics_frame
