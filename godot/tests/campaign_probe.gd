## Проба кампании «История», этап 17 (docs/plan-demo/17-career-trophy.md): правила, сохранение, поток экранов, бой в куполе.
##   godot --headless --path godot --fixed-fps 60 res://tests/campaign_probe.tscn            (fight=0 — без настоящего боя ботов)
## Проверки (exit 1, если не прошли), отчёт — tests/campaign_probe_report.json:
##   new_game          новая кампания: шаг 0, стартовая сборка собирается и готова к бою, бюджет = регламент лиги
##   ladder_budget     все соперники лестницы влезают в регламент лиги и готовы к бою
##   trophy_rule       трофей — деталь соперника, не голова / ядро / скрытая с полок; сначала новая для игрока; при тех же
##                     зерне, шаге и числе поражений — та же деталь
##   loss_no_advance   поражение: шаг тот же, поражений +1, трофея нет
##   win_advance       победа: шаг +1, трофей на полке
##   save_load         сохранение → загрузка: шаг, победы, поражения, трофеи, журнал и сборка те же
##   weapon_energy     регламент: оружие в руке ест энергию по массе (киянка 2.1 кг → 11, стартовое тело + киянка в бюджете,
##                     + молот — перерасход и «не готова к бою»; в «Запасе из деталей» голова не стоит энергии — перерасход даёт
##                     кистень); без регламента (свободная мастерская) оружие энергию не ест
##   flow_ladder       сцена кампании открывается лестницей, 4 соперника, кнопка «В БОЙ» активна
##   flow_fight        «В БОЙ»: в Stage сцена боя, P1 — сборка игрока, P2 — чертёж соперника с RivalBrain уровня шага
##   rival_fights      соперник ищет игрока: за 25 с боя подлетает ближе 2 м и бьёт (Match.hit от P2 ≥ 1)
##   flow_outcome      итог боя → экран исхода, трофей в кампании, сохранение на диске
##   workshop_shelf    мастерская из кампании: на полках только стартовый кит и трофеи, шаблоны тела и оружия закрыты и
##                     спрятаны, верстак пуст, сборка — кампании
##   workshop_back     выход из мастерской: фильтр снят, шаблоны открыты, сборка вернулась в кампанию, лестница
##   ladder_complete   4 победы → лига пройдена, «В БОЙ» выключена, бой не начинается
##   real_fight        (fight=1) настоящий бой двух ботов в куполе до конца матча → fight_finished → запись в кампанию
extends Node

const CAMPAIGN := preload("res://scenes/campaign/campaign.tscn")
const SAVE := "user://campaign_probe.tres"
const BP := "_campaign_probe"
const RIVAL_WINDOW_S := 25.0
const REAL_FIGHT_MAX_S := 240.0

var checks: Array = []
var info := {}
var real_fight := true


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		for kv in a.split(","):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "fight":
				real_fight = p[1] != "0"
	await _run()


func _run() -> void:
	CampaignState.erase(SAVE, BP)
	_rules()
	await _flow()
	CampaignState.erase(SAVE, BP)
	_finish()


# ------------------------------------------------------------------ правила

func _rules() -> void:
	var s := CampaignState.new_game(42, BP)
	var budget := CampaignLeague.energy_budget(s.tier)
	var errs := CraftEdit.friendly_errors(s.blueprint)
	_check("new_game", s.step == 0 and s.wins == 0 and s.trophies.is_empty() and errs.is_empty() and s.blueprint.energy_budget == budget,
		"шаг %d, ошибки %s, бюджет %d (лига %d), энергия %d" % [s.step, errs, s.blueprint.energy_budget, budget, s.blueprint.energy_used()])

	var bad: PackedStringArray = []
	for r in CampaignLeague.ladder():
		var bp := CampaignLeague.rival_blueprint(s.tier, r)
		var e := CraftEdit.friendly_errors(bp)
		if bp == null or not e.is_empty() or bp.energy_used() > budget:
			bad.append("%s: %s, энергия %d" % [r["id"], e, bp.energy_used() if bp else -1])
	_check("ladder_budget", bad.is_empty() and CampaignLeague.ladder().size() == 4, "лестница %d, нарушения %s" % [CampaignLeague.ladder().size(), bad])

	var ok := true
	var notes: PackedStringArray = []
	var rng := RandomNumberGenerator.new()
	for r in CampaignLeague.ladder():
		var bp := CampaignLeague.rival_blueprint(s.tier, r)
		var cands := CampaignLeague.trophy_candidates(bp)
		for i in 20:
			rng.seed = 1000 + i
			var t := CampaignLeague.roll_trophy(bp, s.shelf_parts(), rng)
			var d := BodyBlueprint.part_def(t)
			if not cands.has(t) or d == null or d.kind in CampaignLeague.TROPHY_EXCLUDED_KINDS or t.begins_with("kit_human_"):
				ok = false
				notes.append("%s → %s" % [r["id"], t])
			if s.shelf_parts().has(t) and Array(cands).any(func(c: String) -> bool: return not s.shelf_parts().has(c)):
				ok = false
				notes.append("%s: выпала уже известная %s" % [r["id"], t])
		# все, кроме одной, уже есть — выпадает она
		var owned := PackedStringArray(cands.slice(1))
		rng.seed = 7
		if CampaignLeague.roll_trophy(bp, owned, rng) != cands[0]:
			ok = false
			notes.append("%s: не выбрана единственная новая %s" % [r["id"], cands[0]])
	var a := CampaignState.new_game(99, BP)
	var b := CampaignState.new_game(99, BP)
	var ta := a.record_result(true, {})
	var tb := b.record_result(true, {})
	_check("trophy_rule", ok and ta == tb and ta != "", "ошибки %s; одинаковое зерно → %s / %s" % [notes, ta, tb])

	var l := CampaignState.new_game(5, BP)
	var lt := l.record_result(false, {"reason": "ko"})
	_check("loss_no_advance", l.step == 0 and l.losses == 1 and lt == "" and l.trophies.is_empty() and l.fights.size() == 1,
		"шаг %d, поражений %d, трофей «%s»" % [l.step, l.losses, lt])

	var w := CampaignState.new_game(5, BP)
	var wt := w.record_result(true, {"reason": "ko", "duration_s": 31.4})
	_check("win_advance", w.step == 1 and w.wins == 1 and wt != "" and w.shelf_parts().has(wt) and int(w.fights[0]["step"]) == 0,
		"шаг %d, трофей %s, журнал %s" % [w.step, wt, w.fights])

	w.record_result(false, {})
	w.save(SAVE)
	var back := CampaignState.load_from(SAVE)
	var same := back != null and back.step == w.step and back.wins == w.wins and back.losses == w.losses \
		and back.trophies == w.trophies and back.fights.size() == w.fights.size() and back.rng_seed == w.rng_seed \
		and back.blueprint != null and back.blueprint.nodes.size() == w.blueprint.nodes.size()
	_check("save_load", same, "шаг %d/%d, трофеи %s/%s, узлов %d/%d" % [back.step if back else -1, w.step,
		back.trophies if back else [], w.trophies, back.blueprint.nodes.size() if back and back.blueprint else -1, w.blueprint.nodes.size()])
	CampaignState.erase(SAVE, BP)

	var k := CampaignLeague.start_blueprint()
	var body_e := k.energy_used()
	k.weapon = CraftEdit.load_weapon_preset("mallet")
	var mallet_e := k.weapon_energy()
	var mallet_total := k.energy_used()
	var mallet_ok := CraftEdit.friendly_errors(k).is_empty()
	var kd := CraftEdit.dup_body(k)
	# перерасход: в «Запасе из деталей» (стандарт с 06.10) голова энергии не стоит — тело на 10 дешевле, молот (+21) влезает; не влезает
	# кистень (+33). Без режима — молот, как раньше.
	var heavy := "flail" if PartHp.on else "hammer"
	var heavy_e := 33 if PartHp.on else 21
	k.weapon = CraftEdit.load_weapon_preset(heavy)
	var hammer_total := k.energy_used()
	var hammer_bad := not CraftEdit.friendly_errors(k).is_empty()
	var free := CraftEdit.load_body_preset("kit_human")
	var free_body := free.energy_used()
	free.weapon = CraftEdit.load_weapon_preset("hammer")
	_check("weapon_energy", mallet_e == 11 and mallet_total == body_e + 11 and mallet_ok and kd.energy_used() == mallet_total
		and hammer_total == body_e + heavy_e and hammer_bad and free.energy_used() == free_body,
		"тело %d; киянка +%d = %d (готова %s, копия %d); %s = %d (перерасход %s); без регламента с молотом %d" % [
		body_e, mallet_e, mallet_total, mallet_ok, kd.energy_used(), heavy, hammer_total, hammer_bad, free.energy_used()])


# ------------------------------------------------------------------ поток экранов

func _flow() -> void:
	var c := CAMPAIGN.instantiate()
	c.set("save_path", SAVE)
	c.set("bp_name", BP)
	c.set("load_save", false)
	c.set("entrance_enabled", false)   # выход бойцов — своя проба (arena_events_probe)
	add_child(c)
	await _phys(2)
	var st: CampaignState = c.get("state")
	var rows: int = (c.get_node("%Rivals") as Node).get_child_count()
	_check("flow_ladder", (c.get_node("%Ladder") as Control).visible and rows == 4 and not (c.get_node("%FightButton") as Button).disabled,
		"лестница видна %s, строк %d" % [(c.get_node("%Ladder") as Control).visible, rows])

	# бой
	var started: bool = c.call("start_fight")
	await _phys(3)
	var fight: Node = c.get("fight")
	var p1: ModularDoll = fight.get_node_or_null("P1") if fight else null
	var p2: ModularDoll = fight.get_node_or_null("P2") if fight else null
	var brain: RivalBrain = p2.get_node_or_null("Brain") if p2 else null
	var r := st.current_rival()
	var rival_bp := CampaignLeague.rival_blueprint(st.tier, r)
	_check("flow_fight", started and fight != null and fight.get_parent() == c.get_node("Stage") and p1 != null and p2 != null
		and p1.blueprint.nodes.size() == st.blueprint.nodes.size() and p2.blueprint.title == rival_bp.title and brain != null
		and brain.level == int(r["level"]) and not (c.get_node("%Ladder") as Control).visible,
		"бой %s, P1 узлов %d, P2 «%s», мозг уровня %s" % [started, p1.blueprint.nodes.size() if p1 else -1,
		p2.blueprint.title if p2 else "?", brain.level if brain else -1])

	var m: Match = fight.get_node("Match")
	m.feel_enabled = false
	var hits_by_p2 := [0]
	m.hit.connect(func(_v: Doll, a: Node, _d: float, _k: String, _p: Vector3) -> void:
		if a == p2 or (a is Node and p2.is_ancestor_of(a)):
			hits_by_p2[0] += 1)
	var closest := INF
	var t := 0.0
	while t < RIVAL_WINDOW_S + Tuning.COUNTDOWN_S and hits_by_p2[0] == 0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if is_instance_valid(p1) and is_instance_valid(p2) and m.combat_active():
			closest = minf(closest, EnemyBrain.com2(p1).distance_to(EnemyBrain.com2(p2)))
	info["rival_hits"] = hits_by_p2[0]
	info["rival_closest_m"] = snappedf(closest, 0.01)
	info["rival_counters"] = brain.counters if brain else {}
	_check("rival_fights", closest < 2.0 and hits_by_p2[0] >= 1, "ближе всего %.2f м, ударов P2 %d за %.1f с" % [closest, hits_by_p2[0], t])

	# итог (напрямую — как сигнал сцены боя)
	c.call("finish_fight", true, {"reason": "ko", "duration_s": t})
	await _phys(2)
	st = c.get("state")
	var tr: String = c.get("last_trophy")
	var disk := CampaignState.load_from(SAVE)
	_check("flow_outcome", (c.get_node("%Outcome") as Control).visible and c.get("fight") == null and st.step == 1 and tr != ""
		and st.trophies.has(tr) and disk != null and disk.step == 1 and disk.trophies.has(tr),
		"исход виден %s, шаг %d, трофей %s, на диске шаг %d" % [(c.get_node("%Outcome") as Control).visible, st.step, tr, disk.step if disk else -1])

	# мастерская
	c.call("open_workshop")
	await _phys(3)
	var ws: WorkshopBuild = c.get("workshop")
	var shelf := st.shelf_parts()
	var extra: PackedStringArray = []
	for d in CraftEdit.parts_of_kinds(CraftEdit.KIND_ORDER):
		if not shelf.has(d.id):
			extra.append(d.id)
	var tr_on_shelf := CraftEdit.parts_of_kinds(CraftEdit.KIND_ORDER).any(func(d: PartDef) -> bool: return d.id == tr)
	# UI мастерской v0.3: шаблоны — стрелки ‹ › у имени и плитки во всплывашке имени
	var tiles_hidden := false
	if ws != null and ws.ui != null:
		ws.ui.call("_fill_templates")
		await _phys(2)
		var grid: Control = ws.ui.get("templates_grid")
		var prev_b: Control = ws.ui.get("prev_template")
		tiles_hidden = grid != null and grid.get_child_count() == 0 and prev_b != null and not prev_b.visible
	var bench_empty := ws != null and ws.weapon_bp != null and ws.weapon_bp.nodes.is_empty()
	_check("workshop_shelf", ws != null and ws.get_parent() == c.get_node("Stage") and extra.is_empty() and tr_on_shelf
		and CraftEdit.load_body_preset("kit_king") == null and CraftEdit.load_weapon_preset("hammer") == null and tiles_hidden
		and bench_empty and ws.blueprint.nodes.size() == st.blueprint.nodes.size() and ws.blueprint.weapon_energy_per_kg > 0.0
		and (c.get_node("%WorkshopBar") as Control).visible,
		"лишние на полке %s, трофей на полке %s, шаблоны тела / оружия закрыты %s / %s, плитки спрятаны %s, верстак пуст %s" % [
		extra, tr_on_shelf, CraftEdit.load_body_preset("kit_king") == null, CraftEdit.load_weapon_preset("hammer") == null,
		tiles_hidden, bench_empty])
	c.call("close_workshop")
	c.call("show_ladder")
	await _phys(2)
	_check("workshop_back", c.get("workshop") == null and CraftEdit.campaign_shelf.is_empty() and CraftEdit.load_body_preset("kit_king") != null
		and CraftEdit.load_weapon_preset("hammer") != null
		and (c.get_node("%Ladder") as Control).visible and CraftEdit.friendly_errors(st.blueprint).is_empty(),
		"мастерская закрыта %s, фильтр %s" % [c.get("workshop") == null, CraftEdit.campaign_shelf])

	# настоящий бой (fight=1): оба — боты, до конца матча
	if real_fight:
		await _real_fight(c)

	# лестница до конца
	st = c.get("state")
	while not st.finished():
		c.call("finish_fight", true, {"reason": "probe"})
		st = c.get("state")
	c.call("show_ladder")
	await _phys(1)
	var began: bool = c.call("start_fight")
	_check("ladder_complete", st.finished() and (c.get_node("%FightButton") as Button).disabled and not began and st.wins >= 4,
		"пройдена %s, побед %d, трофеи %s" % [st.finished(), st.wins, st.trophies])
	c.queue_free()
	await _phys(2)


func _real_fight(c: Node) -> void:
	var st: CampaignState = c.get("state")
	var step0 := st.step
	var fights0 := st.fights.size()
	c.call("start_fight")
	await _phys(2)
	var fight: Node = c.get("fight")
	var p1: ModularDoll = fight.get_node("P1")
	var m: Match = fight.get_node("Match")
	m.feel_enabled = false
	# игрок — тоже бот: RivalBrain уровня 4 с целью «соперники»
	var pb := RivalBrain.new()
	pb.name = "ProbeBrain"
	pb.level = 4
	p1.add_child(pb)
	await _phys(2)
	pb.players_group = "rivals"
	pb.enemies_group = "players"
	var done := [false, false]
	fight.connect("fight_finished", func(won: bool, _i: Dictionary) -> void:
		done[0] = true
		done[1] = won)
	var t := 0.0
	while t < REAL_FIGHT_MAX_S and c.get("fight") != null:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	st = c.get("state")
	var rec: Dictionary = st.fights[st.fights.size() - 1] if st.fights.size() > fights0 else {}
	info["real_fight"] = {"t": snappedf(t, 0.1), "record": rec, "hits": m.hit_fx_count if is_instance_valid(m) else -1}
	var advanced := st.step == step0 + 1 if bool(rec.get("won", false)) else st.step == step0
	_check("real_fight", done[0] and not rec.is_empty() and advanced and (c.get_node("%Outcome") as Control).visible,
		"конец за %.1f с, запись %s" % [t, rec])
	c.call("show_ladder")


# ------------------------------------------------------------------ служебное

func _phys(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _check(id: String, ok: bool, text: String) -> void:
	checks.append({"id": id, "ok": ok, "info": text})
	print("%s %s — %s" % ["PASS" if ok else "FAIL", id, text])


func _finish() -> void:
	var ok := true
	for c in checks:
		ok = ok and bool(c["ok"])
	var f := FileAccess.open("res://tests/campaign_probe_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"ok": ok, "checks": checks, "info": info}, "  "))
	f.close()
	print("campaign_probe: %s (%d checks)" % ["OK" if ok else "FAIL", checks.size()])
	get_tree().quit(0 if ok else 1)
