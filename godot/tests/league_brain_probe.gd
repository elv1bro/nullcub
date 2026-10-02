## Проба чемпиона лиги (scripts/league/league_brain.gd; docs/plan-demo/ACTIVE_BLOCKS.md «Боты»): площадка Old NULL Hall с матчем,
## вызов чемпиона (NullHallArena.call_champion — клавиша L), BATTLE_S секунд боя против кукол площадки (без ввода — стоят).
## Headless: godot --headless --path godot --fixed-fps 60 res://tests/league_brain_probe.tscn → tests/league_brain_probe_report.json, exit 0/1
## Проверки: чемпион появился (LeagueBrain, DollCombat от матча, вид лиги, команда league, автопилот каналов включён); подошёл к цели
## ближе 2 м; атаковал (stat.attacks); нанёс урон куклам площадки; сам жал особый модуль (заряд потрачен); без NaN; повторный вызов —
## следующий чемпион, прежнего нет. Кадр боя (окно): -- "shot=/abs/champion.png" — снимок камерой площадки через SHOT_S после вызова.
extends Node

const PLAYGROUND := "res://scenes/playground_null_hall.tscn"
const WARM_S := 1.5
const BATTLE_S := 12.0
const SHOT_S := 4.0

var checks: Array = []
var pg: Node
var arena: NullHallArena
var champ: ModularDoll
var brain: LeagueBrain
var t := 0.0
var min_d := INF
var taken0 := 0.0
var nan := false
var stage := 0
var shot := ""
var shot_done := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		for kv in String(a).split(","):
			var p := String(kv).split("=")
			if p.size() == 2 and p[0] == "shot":
				shot = p[1]
	pg = (load(PLAYGROUND) as PackedScene).instantiate()
	add_child(pg)
	arena = get_tree().get_first_node_in_group("arena") as NullHallArena


func _others() -> Array:
	return get_tree().get_nodes_in_group("dolls").filter(func(n: Node) -> bool: return n is Doll and n != champ)


func _physics_process(dt: float) -> void:
	t += dt
	if stage == 0 and t >= WARM_S:
		stage = 1
		champ = arena.call_champion() as ModularDoll
		for o in _others():
			taken0 += float((o as Doll).stats.get("damage_taken", 0.0))
		return
	if stage == 1 and is_instance_valid(champ):
		if brain == null:
			brain = champ.get_node_or_null("LeagueBrain") as LeagueBrain
		var c := champ.centre_of_mass()
		if not c.is_finite():
			nan = true
		for o in _others():
			if (o as Doll).alive:
				min_d = minf(min_d, c.distance_to((o as Doll).centre_of_mass()))
		if shot != "" and not shot_done and t >= WARM_S + SHOT_S:
			shot_done = true
			_shot()
		if t >= WARM_S + BATTLE_S:
			stage = 2
			_checks()


func _checks() -> void:
	var rig := champ.active_rig
	var look := champ.get_node_or_null("LeagueLook") as LeagueLook
	_check("champion_spawned", brain != null and Match.combat_of(champ) != null and look != null and look.applied and champ.team == "league"
		and rig != null and rig.auto, "%s: мозг %s, DollCombat %s, вид лиги %s, команда «%s», автопилот %s" % [champ.blueprint.id, brain != null,
		Match.combat_of(champ) != null, look != null and look.applied, champ.team, rig != null and rig.auto])
	_check("approaches", min_d < 2.0, "ближе всего к цели %.2f м" % min_d)
	var attacks := int(brain.stat["attacks"]) if brain != null else 0
	_check("attacks", attacks >= 1, "атак %d за %.0f с" % [attacks, BATTLE_S])
	var taken := 0.0
	for o in _others():
		taken += float((o as Doll).stats.get("damage_taken", 0.0))
	_check("deals_damage", taken - taken0 > 0.0, "урон по куклам площадки %.1f HP" % (taken - taken0))
	_check("uses_module", rig != null and rig.spent > 0.0, "потрачено заряда на модуль %.1f" % (rig.spent if rig != null else 0.0))
	_check("no_nan", not nan, "ЦМ конечен")
	var first := champ
	var first_id := String(champ.blueprint.id)
	var second := arena.call_champion() as ModularDoll
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("next_champion", second != null and String(second.blueprint.id) != first_id and not is_instance_valid(first),
		"следующий: %s, прежний ушёл: %s" % [second.blueprint.id if second != null else "—", not is_instance_valid(first)])
	var ok := true
	for c in checks:
		ok = ok and bool(c["ok"])
	var f := FileAccess.open("res://tests/league_brain_probe_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"ok": ok, "checks": checks}, "  "))
	f.close()
	print("league_brain_probe: %s (%d checks)" % ["OK" if ok else "FAIL", checks.size()])
	get_tree().quit(0 if ok else 1)


func _shot() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot)
	print("shot → ", shot)


func _check(id: String, ok: bool, info: String) -> void:
	checks.append({"id": id, "ok": ok, "info": info})
	print("%s %s — %s" % ["PASS" if ok else "FAIL", id, info])
