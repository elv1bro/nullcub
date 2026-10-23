## Бой Испытания (docs/plan-demo/GAUNTLET.md): бой кампании (campaign_fight.gd — P1 сборка игрока + ArmAssist, P2 соперник с
## мозгом, крафтовое оружие, итоги HUD → fight_finished), но арена — по кругу из Быстрого боя (Tuning.GAUNTLET_ARENAS: купол,
## Руины, Свалка, Void, Мастерская; ставится в setup_gauntlet до add_child — узел "Arena" первым ребёнком), без выхода бойцов и N0.
## Детали не чинятся: P1 собирается без оторванного (missing_parts = GauntletRun.lost); на FIGHT! запас P1 = max − накопленный урон
## (GauntletRun.start_hp), суставы — с износом; соперник — тяга × thrust ступени, запас × hp ступени, бот уровня ступени
## (GauntletBrain, 5 — Tuning.GAUNTLET_LEVEL5). Конец матча — снимок P1 (GauntletRun.snapshot) в outcome["snapshot"].
## Esc — пауза Flow (ПРОДОЛЖИТЬ / ЗАНОВО — сдаться, забег сначала / В ГАРАЖ).
extends "res://scenes/campaign/campaign_fight.gd"

var run: GauntletRun
var index := 0
var arena_key := ""
var bot_player := false
## Пробы: короче основное время боя (−1 — как в Быстром бою) и пауза итогов HUD.
var time_limit_s := -1.0
var result_delay_s: float = Tuning.GAUNTLET_RESULT_DELAY_S
var start_hp := 0.0                 # запас P1 на FIGHT! (после переноса урона)
var rival_hp := 0.0                 # запас P2 на FIGHT!
var _applied := false


## До add_child: арена боя i, сборка игрока с оторванным из run, соперник ступени i. bot = автопилот за игрока (пробы).
func setup_gauntlet(player_bp: BodyBlueprint, r: GauntletRun, i: int, bot := false) -> void:
	run = r
	index = i
	bot_player = bot
	entrance_enabled = false
	arena_key = GauntletRun.arena(i)
	var a: Dictionary = Tuning.GAUNTLET_ARENA[arena_key]
	var arena_node := (load(String(a["scene"])) as PackedScene).instantiate() as Node3D
	arena_node.name = "Arena"
	arena_node.add_to_group("arena", true)
	add_child(arena_node)
	move_child(arena_node, 0)
	var c := $Camera as Camera3D
	var cfg: Dictionary = a.get("cam", {})
	for k in cfg:
		if k == "pos":
			c.position = cfg[k]
		else:
			c.set(String(k), cfg[k])
	var spawn: Array = a.get("spawn", [])
	var d1 := $P1 as ModularDoll
	var d2 := $P2 as ModularDoll
	if spawn.size() >= 2:
		d1.position = spawn[0]
		d2.position = spawn[1]
	d1.blueprint = CraftEdit.dup_body(player_bp)
	d1.missing_parts = PackedStringArray(r.lost)
	rival = GauntletRun.rival(i)
	d2.blueprint = GauntletRun.rival_blueprint(i)
	d2.thrust_mult = float(rival.get("thrust", 1.0))
	($P2/Brain as GauntletBrain).level = int(rival.get("level", 1))
	var preset := String(rival.get("preset", ""))
	if preset.begins_with("league_") or preset.begins_with("aoe_"):
		var look := LeagueLook.new()
		look.name = "LeagueLook"
		d2.add_child(look)
	if bot:
		var pb := GauntletBrain.new()
		pb.name = "AutoBrain"
		pb.level = Tuning.GAUNTLET_BOT_PLAYER_LEVEL
		pb.as_player = true
		d1.add_child(pb)
	if time_limit_s > 0.0:
		var m := $Match as Match
		m.time_limit_s = time_limit_s
		m.hard_timeout_s = time_limit_s * 2.0
	# Фишка плашек LowerThirds — номер боя забега, а не «СЕРИЯ 0 – 0» сессии (VISUAL_PASS_2310, G-3).
	info = {"player_name": tr("Игрок"), "rival_title": GauntletRun.rival_title(i),
		"player_record": tr("бой %d из %d") % [i + 1, GauntletRun.fights()],
		"rival_record": tr("соперник %d из %d") % [i + 1, GauntletRun.fights()]}
	($UI/Hint as Label).text = tr("Испытание · бой %d из %d · %s · WASD + Shift + Space, мышь — тяги · Esc — пауза") % [
		i + 1, GauntletRun.fights(), GauntletRun.arena_title(i)]


func _ready() -> void:
	super._ready()
	for w in (Tuning.GAUNTLET_ARENA.get(arena_key, {}) as Dictionary).get("weapons", []):
		Weapon.spawn(String(w[0]), weapons_root, w[1], float(w[2]))
	_set_gi_dynamic(weapons_root)
	match_node.phase_changed.connect(_on_gauntlet_phase)


## FIGHT!: Match._start_fight уже вернул всем полный запас (reset_for_match) — здесь перенос урона P1 и запас соперника по ступени;
## hp_changed для HUD Match шлёт сразу после смены фазы.
func _on_gauntlet_phase(p: int) -> void:
	if p != Match.Phase.FIGHT or _applied:
		return
	_applied = true
	if run != null and is_instance_valid(p1):
		run.body_map(p1)
		run.hp_scale = p1.max_hp / maxf(run.pool_max(), 1.0)
		p1.hp = run.start_hp(p1.max_hp)
		for n in run.wear:
			if p1.joint_hp.has(n):
				p1.joint_hp[n] = maxf(float(p1.joint_hp_max[n]) - float(run.wear[n]), 1.0)
		start_hp = p1.hp
	if is_instance_valid(p2):
		p2.max_hp = maxf(roundf(p2.max_hp * float(rival.get("hp", 1.0))), 1.0)
		p2.hp = p2.max_hp
		rival_hp = p2.hp


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				if not finished:
					Flow.toggle_pause(_give_up)
			KEY_H:
				cycle_hud_skin()


## «ЗАНОВО» в паузе: сдаться — забег кончается, Испытание начинается сначала (GauntletPlayground.on_abandoned).
func _give_up() -> void:
	if finished:
		return
	finished = true
	fight_abandoned.emit()


func _on_match_over(winner: Doll, results: Dictionary) -> void:
	if finished:
		return
	finished = true
	outcome = {"won": player_won(winner), "draw": bool(results.get("draw", false)), "reason": String(results.get("reason", "")),
		"duration_s": float(results.get("duration_s", match_node.fight_time)),
		"snapshot": GauntletRun.snapshot(p1) if is_instance_valid(p1) else {}}
	var t := get_tree().create_timer(result_delay_s, true, false, true)
	t.timeout.connect(func() -> void:
		if is_inside_tree():
			fight_finished.emit(bool(outcome["won"]), outcome))
