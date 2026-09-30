## Проба активных блоков (docs/plan-demo/ACTIVE_BLOCKS.md; scripts/active/active_blocks.gd, active_rig.gd).
## Headless: godot --headless --path godot --fixed-fps 60 res://tests/active_blocks_probe.tscn → tests/active_blocks_probe_report.json, exit 0/1
## Сценарии — каждый в своём месте пола (x через SPACING), куклы — kit_human + блоки на канале 1 (ввод ботом: ActiveRig.held):
##   ранец поднимает (ЦМ выше двойника без ввода), заряд тратится по cost; огнемёт и пулемёт наносят урон кукле сбоку (правая рука
##   смотрит в −X), свой урон блоков заряда не даёт; щит: урон × 0.25; фаза: исключения столкновений есть, пока канал зажат, и сняты
##   после; ремонт: HP растёт; удар (stats) даёт заряд; пустой заряд — канал молчит; стенд (control_enabled = false) — молчит;
##   гравиядро и магнит тянут чужих; пассивы ядер лиги; второй ActiveRig / LeagueLook (Match.respawn_doll) освобождается.
extends Node3D

const DOLL := preload("res://scenes/body/modular_doll.tscn")
const HUMAN := "res://data/body/blueprints/kit_human.tres"
const SPACING := 9.0
const HOLD_FROM := 1.0
const HOLD_TO := 2.5
const END_T := 3.0

var checks: Array = []
var t := 0.0
var s := {}          # сценарий → {a: ModularDoll, b: Doll-жертва/двойник, …}
var marks := {}      # замеры по ходу
var once := {}


func _ready() -> void:
	_floor()
	ActiveBlocks.ensure_input_actions()
	var i := 0
	s["jet"] = {"a": _doll(i, [["kit_active_jetpack", "T", "Anchor_Back"]]), "b": _doll(i, [], 2.0)}
	i += 1
	s["flame"] = {"a": _doll(i, [["kit_active_flamer", "8", "Anchor_Deco"]]), "b": _doll(i, [], -1.25)}
	i += 1
	s["gun"] = {"a": _doll(i, [["kit_active_gun", "8", "Anchor_Deco"]]), "b": _doll(i, [], -2.2)}
	i += 1
	s["shield"] = {"a": _doll(i, [["kit_active_league_shield", "2", "Anchor_Deco"]]), "b": _doll(i, [["kit_active_league_shield", "2", "Anchor_Deco"]], 3.0)}
	i += 1
	s["phase"] = {"a": _doll(i, [["kit_active_league_phase", "T", "Anchor_Back"]]), "b": _doll(i, [], -1.6)}
	i += 1
	s["repair"] = {"a": _doll(i, [["kit_active_league_repair", "T", "Anchor_Back"]])}
	i += 1
	s["hits"] = {"a": _doll(i, [["kit_active_booster", "2", "Anchor_Deco"]])}
	i += 1
	s["empty"] = {"a": _doll(i, [["kit_active_jetpack", "T", "Anchor_Back"]]), "b": _doll(i, [], 2.0)}
	i += 1
	s["stand"] = {"a": _doll(i, [["kit_active_jetpack", "T", "Anchor_Back"]])}
	(s["stand"]["a"] as ModularDoll).control_enabled = false
	i += 1
	s["gravity"] = {"a": _doll(i, [["kit_active_league_gravity", "T", "Anchor_Back"]]), "b": _doll(i, [], -2.0)}
	i += 1
	s["magnet"] = {"a": _doll(i, [["kit_active_magnet", "8", "Anchor_Deco"]]), "b": _preset(i, "kit_horned", -1.4)}
	i += 1
	s["passive"] = {"crystal": _preset(i, "league_crystal", 0.0), "portal": _preset(i, "league_portal", 3.0),
		"deep": _preset(i + 1, "league_deep", 0.0), "reaper": _preset(i + 1, "league_reaper", 3.0)}
	i += 2
	s["plain"] = {"a": _doll(i, [])}


func _doll(i: int, actives: Array, dx: float = 0.0) -> ModularDoll:
	var bp := (load(HUMAN) as BodyBlueprint).duplicate(true) as BodyBlueprint
	var nodes: Array[Dictionary] = []
	for n in bp.nodes:
		nodes.append((n as Dictionary).duplicate(true))
	var uids := "DEFGIJKLMN"
	for k in range(actives.size()):
		var a: Array = actives[k]
		nodes.append({"uid": uids[k], "part": String(a[0]), "parent": String(a[1]), "anchor": String(a[2]), "channel": 1})
	bp.nodes = nodes
	bp.energy_budget = 1000
	bp.id = "probe_%d_%d" % [i, int(dx * 10)]
	var d := DOLL.instantiate() as ModularDoll
	d.blueprint = bp
	d.external_input = true
	d.position = Vector3(i * SPACING + dx, 0.0, 0.0)
	add_child(d)
	return d


func _preset(i: int, id: String, dx: float) -> ModularDoll:
	var d := (load("res://scenes/body/presets/%s.tscn" % id) as PackedScene).instantiate() as ModularDoll
	d.external_input = true
	d.position = Vector3(i * SPACING + dx, 0.0, 0.0)
	add_child(d)
	return d


func _rig(d: Node) -> ActiveRig:
	return (d as ModularDoll).active_rig


func _hold(name: String, on: bool) -> void:
	var r := _rig(s[name]["a"])
	if r != null:
		r.held[0] = on


func _physics_process(dt: float) -> void:
	t += dt
	if not once.has("setup") and t >= HOLD_FROM:
		once["setup"] = true
		_start()
	if once.has("setup") and not once.has("mid") and t >= HOLD_FROM + 0.5:
		once["mid"] = true
		_mid()
	if not once.has("release") and t >= HOLD_TO:
		once["release"] = true
		_release()
	if t >= END_T and not once.has("end"):
		once["end"] = true
		_end()


func _start() -> void:
	for n in ["jet", "flame", "gun", "shield", "phase", "repair", "empty", "stand", "gravity", "magnet"]:
		_hold(n, true)
	marks["jet_spent0"] = _rig(s["jet"]["a"]).spent
	var rep := s["repair"]["a"] as ModularDoll
	rep.hp = 50.0
	var e := _rig(s["empty"]["a"])
	e.charge = 0.0
	e.regen = 0.0
	var h := _rig(s["hits"]["a"])
	h.charge = 0.0
	h.regen = 0.0
	var hd := s["hits"]["a"] as ModularDoll
	hd.stats["damage_dealt"] = float(hd.stats["damage_dealt"]) + 10.0
	hd.stats["damage_taken"] = float(hd.stats["damage_taken"]) + 10.0
	marks["grav_b0"] = (s["gravity"]["b"] as Doll).centre_of_mass()
	marks["mag_b0"] = (s["magnet"]["b"] as Doll).centre_of_mass()
	var deep := s["passive"]["deep"] as ModularDoll
	deep.hp = 80.0
	marks["deep_hp0"] = deep.hp


func _mid() -> void:
	# щит: зажат у a, не зажат у b — одинаковый удар 20 HP
	var a := s["shield"]["a"] as ModularDoll
	var b := s["shield"]["b"] as ModularDoll
	var h0a := a.hp
	var h0b := b.hp
	a.take_damage(20.0, null, "Torso", a.centre_of_mass(), Vector3.UP, "environment")
	b.take_damage(20.0, null, "Torso", b.centre_of_mass(), Vector3.UP, "environment")
	_check("shield_mult", is_equal_approx(h0a - a.hp, 5.0) and is_equal_approx(h0b - b.hp, 20.0),
		"со щитом −%.2f HP, без −%.2f HP (удар 20)" % [h0a - a.hp, h0b - b.hp])
	var p := _rig(s["phase"]["a"])
	_check("phase_on", p._phase_pairs.size() > 0 and is_equal_approx(p.incoming_mult(), 0.0),
		"исключений %d, входящий × %.2f" % [p._phase_pairs.size(), p.incoming_mult()])
	var h := _rig(s["hits"]["a"])
	_check("charge_from_hits", h.gained_hits >= 13.9 and h.gained_hits <= 14.1,
		"+%.2f заряда за 10 HP нанесённого и 10 HP полученного (ждём 10 × 1.0 + 10 × 0.4 = 14)" % h.gained_hits)
	var e := _rig(s["empty"]["a"])
	_check("empty_silent", not e.running[0] and e.charge >= 0.0 and e.spent == 0.0, "running %s, заряд %.2f, потрачено %.2f"
		% [e.running[0], e.charge, e.spent])
	var st := _rig(s["stand"]["a"])
	_check("stand_silent", not st.running[0] and st.spent == 0.0, "running %s, потрачено %.2f" % [st.running[0], st.spent])


func _release() -> void:
	for n in ["jet", "flame", "gun", "shield", "phase", "repair", "empty", "stand", "gravity", "magnet"]:
		_hold(n, false)
	var j := _rig(s["jet"]["a"])
	var dy := (s["jet"]["a"] as Doll).centre_of_mass().y - (s["jet"]["b"] as Doll).centre_of_mass().y
	var spent := j.spent - float(marks["jet_spent0"])
	var want := 22.0 * (HOLD_TO - HOLD_FROM)
	_check("jetpack_lifts", dy > 0.25, "ЦМ выше двойника на %.2f м" % dy)
	_check("jetpack_cost", absf(spent - want) <= want * 0.08, "потрачено %.1f заряда, ждём ≈ %.1f" % [spent, want])
	var fa := _rig(s["flame"]["a"])
	var fb := s["flame"]["b"] as Doll
	_check("flame_damage", fb.hp <= fb.max_hp - 10.0 and fa.block_damage > 0.0 and fa.gained_hits == 0.0,
		"жертва %.1f HP, урон блоком %.1f, заряд от своего урона %.2f" % [fb.hp, fa.block_damage, fa.gained_hits])
	var ga := _rig(s["gun"]["a"])
	var gb := s["gun"]["b"] as Doll
	_check("gun_fires", ga.shots >= 15 and ga.shots <= 20 and gb.hp < gb.max_hp, "выстрелов %d (12/с × 1.5 с), жертва %.1f HP"
		% [ga.shots, gb.hp])
	var rep := s["repair"]["a"] as ModularDoll
	_check("repair_heals", rep.hp >= 50.0 + 8.0 * 1.4 and rep.hp <= 50.0 + 8.0 * 1.6 + 0.1, "HP 50 → %.1f (8/с × 1.5 с)" % rep.hp)
	var gv := (s["gravity"]["b"] as Doll).centre_of_mass() - (marks["grav_b0"] as Vector3)
	_check("gravity_pulls", gv.x > 0.15, "жертва сместилась к гравиядру на %.2f м" % gv.x)
	var mv := (s["magnet"]["b"] as Doll).centre_of_mass() - (marks["mag_b0"] as Vector3)
	_check("magnet_pulls_iron", mv.x > 0.03, "железный боец сместился к магниту на %.3f м" % mv.x)
	var deep := s["passive"]["deep"] as ModularDoll
	_check("passive_flesh_regen", deep.hp > float(marks["deep_hp0"]) + 1.2, "живое ядро: HP 80 → %.1f за 1.5 с" % deep.hp)


func _end() -> void:
	var p := _rig(s["phase"]["a"])
	var transparent := 0
	for mi in (s["phase"]["a"] as Node).find_children("*", "GeometryInstance3D", true, false):
		if (mi as GeometryInstance3D).transparency > 0.0 and not String(mi.get_path()).contains("ActiveRig"):
			transparent += 1
	_check("phase_off", p._phase_pairs.is_empty() and transparent == 0, "исключений %d, прозрачных мешей %d" % [p._phase_pairs.size(),
		transparent])
	_check("rig_only_with_blocks", _rig(s["plain"]["a"]) == null and _rig(s["jet"]["a"]) != null and _rig(s["jet"]["a"]).blocks.size() == 1,
		"kit_human без блоков — без ActiveRig; с ранцем — 1 блок")
	var c := _rig(s["passive"]["crystal"])
	var g := _rig(s["passive"]["portal"])
	var rp := _rig(s["passive"]["reaper"])
	_check("passive_cores", c != null and is_equal_approx(c.charge_max, 150.0) and g != null and is_equal_approx(g.regen, 7.0)
		and rp != null and is_equal_approx(rp.dealt_mult, 1.5), "кристалл: запас %.0f, гироскоп: реген %.1f, око: × %.1f"
		% [c.charge_max if c else -1.0, g.regen if g else -1.0, rp.dealt_mult if rp else -1.0])
	var league_blocks := 0
	for k in ["crystal", "portal", "deep", "reaper"]:
		var r := _rig(s["passive"][k])
		if r != null and r.blocks.size() == 1 and int(r.blocks[0]["channel"]) == 1:
			league_blocks += 1
	_check("league_specials", league_blocks == 4, "у %d из 4 бойцов лиги особый модуль на канале 1" % league_blocks)
	var acts := 0
	for pi in range(1, 5):
		for ch in range(1, 4):
			if InputMap.has_action(ActiveBlocks.action_name("p%d" % pi, ch)):
				acts += 1
	_check("input_actions", acts == 12 and ActiveBlocks.key_label("p1", 1) == "Q", "экшенов %d / 12, P1: %s %s %s" % [acts,
		ActiveBlocks.key_label("p1", 1), ActiveBlocks.key_label("p1", 2), ActiveBlocks.key_label("p1", 3)])
	_workshop_checks()
	# второй экземпляр (как Match.respawn_doll: новый объект того же скрипта) освобождается сам
	var jd := s["jet"]["a"] as ModularDoll
	var extra := ActiveRig.new()
	extra.name = "ActiveRig"
	jd.add_child(extra)
	var ld := s["passive"]["crystal"] as ModularDoll
	var con := ld.find_children("Connector_*", "Node3D", true, false)
	var sc0 := (con[0] as Node3D).scale.x if not con.is_empty() else -1.0
	var extra_look := LeagueLook.new()
	extra_look.name = "LeagueLook"
	ld.add_child(extra_look)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var rigs := jd.get_children().filter(func(n: Node) -> bool: return n is ActiveRig and not n.is_queued_for_deletion())
	var looks := ld.get_children().filter(func(n: Node) -> bool: return n is LeagueLook and not n.is_queued_for_deletion())
	var sc1 := (con[0] as Node3D).scale.x if not con.is_empty() else -1.0
	_check("respawn_no_duplicates", rigs.size() == 1 and looks.size() == 1 and is_equal_approx(sc0, sc1),
		"ActiveRig %d, LeagueLook %d, шар сустава %.3f → %.3f" % [rigs.size(), looks.size(), sc0, sc1])
	var ok := true
	for ch in checks:
		ok = ok and bool(ch["ok"])
	var f := FileAccess.open("res://tests/active_blocks_probe_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"ok": ok, "checks": checks}, "  "))
	f.close()
	print("active_blocks_probe: %s (%d checks)" % ["OK" if ok else "FAIL", checks.size()])
	get_tree().quit(0 if ok else 1)


## Мастерская (CraftEdit, данные — без экрана): полки «Активные» / «Декор», канал 1 у нового блока, зеркало и дубликат несут канал,
## замена на обычный декор канал снимает, подпись чертежа видит канал.
func _workshop_checks() -> void:
	var act := CraftEdit.shelf_of(CraftEdit.BODY_SHELVES, "active")
	var dec := CraftEdit.shelf_of(CraftEdit.BODY_SHELVES, "deco")
	var n_act := CraftEdit.parts_of_kinds(act.get("kinds", [])).filter(func(d: PartDef) -> bool: return CraftEdit.shelf_allows(act, d)).size()
	var n_dec_act := CraftEdit.parts_of_kinds(dec.get("kinds", [])).filter(func(d: PartDef) -> bool:
		return CraftEdit.shelf_allows(dec, d) and ActiveBlocks.is_active(d.id)).size()
	_check("shelf_active", n_act == ActiveBlocks.DEFS.size() and n_dec_act == 0, "на полке «Активные» %d / %d, в «Декоре» активных %d"
		% [n_act, ActiveBlocks.DEFS.size(), n_dec_act])
	var bp := (load(HUMAN) as BodyBlueprint).duplicate(true) as BodyBlueprint
	var nodes: Array[Dictionary] = []
	for n in bp.nodes:
		nodes.append((n as Dictionary).duplicate(true))
	bp.nodes = nodes
	bp.energy_budget = 1000
	var r := CraftEdit.attach(bp, "kit_active_booster", "8", "Anchor_Deco")
	var uid := String(r.get("uid", ""))
	var ch0 := ActiveBlocks.channel_of(CraftEdit.find(bp, uid))
	CraftEdit.set_channel(bp, uid, 3)
	var ch3 := ActiveBlocks.channel_of(CraftEdit.find(bp, uid))
	var sig_has := "|3" in "\n".join(CraftEdit.signature(bp))
	var m := CraftEdit.mirror_subtree(bp, uid)
	var mir := ""
	for n in bp.nodes:
		if String(n.get("part", "")) == "kit_active_booster" and String(n.get("uid", "")) != uid:
			mir = String(n.get("uid", ""))
	var chm := ActiveBlocks.channel_of(CraftEdit.find(bp, mir)) if mir != "" else -1
	CraftEdit.set_channel(bp, uid, 0)
	var ch_off := CraftEdit.find(bp, uid).has(ActiveBlocks.NODE_KEY)
	CraftEdit.set_channel(bp, uid, 2)
	CraftEdit._replace(bp, uid, "kit_deco_crown")
	var ch_repl := CraftEdit.find(bp, uid).has(ActiveBlocks.NODE_KEY)
	_check("workshop_channel", bool(r.get("ok", false)) and ch0 == 1 and ch3 == 3 and sig_has and bool(m.get("ok", false)) and chm == 3
		and not ch_off and not ch_repl, "новый блок: канал %d; set 3 → %d; в подписи — %s; зеркало (%s) → канал %d; 0 — ключ снят: %s; "
		% [ch0, ch3, sig_has, m.get("ok", false), chm, not ch_off] + "замена на корону — канал снят: %s" % [not ch_repl])
	_check("desc_active", CraftEdit.part_desc(CraftEdit.part("kit_active_gun")).contains("за выстрел")
		and CraftEdit.part_desc(CraftEdit.part("kit_core_league_crystal")).contains("Особое свойство"), "описание блока и пассива в паспорте")


func _floor() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(200.0, 1.0, 20.0)
	cs.shape = bs
	body.add_child(cs)
	body.position = Vector3(60.0, -0.5, 0.0)
	add_child(body)


func _check(id: String, ok: bool, info: String) -> void:
	checks.append({"id": id, "ok": ok, "info": info})
	print("%s %s — %s" % ["PASS" if ok else "FAIL", id, info])
