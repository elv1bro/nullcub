## Бой кампании «История» (docs/plan-demo/17-career-trophy.md): купол Old NULL Hall (все бои кампании — в куполе, автор 30.09),
## игрок P1 — ModularDoll по сборке из мастерской (WASD + Shift + Space, мышь — тяги ArmAssist, оружие — из чертежа), соперник
## P2 — ModularDoll по чертежу лиги с мозгом RivalBrain (уровень ступени). Дерево — scenes/campaign/campaign_fight.tscn (правило 2
## ASSET_PIPELINE), чертежи и уровень ставит CampaignFlow до add_child (setup) — сборка ModularDoll идёт в её _ready.
## Поведение площадки — как у playground.gd (пропасть → KO, молот Sudden Death), но без смены арен и R: исход боя решает кампания.
## Перед боем — выход бойцов (Entrance, FighterEntrance, этап 16; у Match autostart = false — бой начинает конец выхода), в бою —
## голосование зрителей (AudienceVote, этап 15; у соперника с anomaly "vote_mismatch" — аномалия §14).
## Конец матча → итоги HUD Tuning.CAMPAIGN_RESULT_DELAY_S реальных секунд → сигнал fight_finished(won, info). Esc — сдаться
## и вернуться к лестнице (fight_abandoned, бой не засчитывается).
extends "res://scenes/playground.gd"

signal fight_finished(won: bool, info: Dictionary)
signal fight_abandoned

var rival: Dictionary = {}
var info: Dictionary = {}
var finished := false
var outcome: Dictionary = {}
## false — без выхода бойцов (пробы боя): матч начинается сразу.
var entrance_enabled := true

@onready var p1: ModularDoll = $P1
@onready var p2: ModularDoll = $P2


## До add_child: чертежи бойцов и соперник лестницы (CampaignLeague.LADDER). extra — карточки выхода: player_name, player_build,
## player_record, rival_record; entrance (false — без выхода).
func setup(player_bp: BodyBlueprint, rival_bp: BodyBlueprint, r: Dictionary, rival_title: String, extra: Dictionary = {}) -> void:
	rival = r
	info = extra.duplicate()
	info["rival_title"] = rival_title
	entrance_enabled = bool(extra.get("entrance", true))
	($P1 as ModularDoll).blueprint = CraftEdit.dup_body(player_bp)
	($P2 as ModularDoll).blueprint = rival_bp
	($P2/Brain as RivalBrain).level = int(r.get("level", 1))
	($AudienceVote as AudienceVote).anomaly = String(r.get("anomaly", ""))
	($UI/Hint as Label).text = tr("Кампания · %s · WASD + Shift + Space, мышь — тяги · Esc — сдаться и к лестнице") % rival_title


func _ready() -> void:
	super._ready()
	hud.set_player_name(0, String(info.get("player_name", tr("Игрок"))))
	hud.set_player_name(1, String(info.get("rival_title", "")))
	ArmAssist.attach_to(p1)
	for d in [p1, p2]:
		_equip_crafted(d as ModularDoll)
	match_node.match_over.connect(_on_match_over)
	_start.call_deferred()


## Выход бойцов, потом отсчёт (Match.begin). Без выхода — сразу отсчёт.
func _start() -> void:
	var ent := get_node_or_null("Entrance") as FighterEntrance
	if not entrance_enabled or ent == null:
		match_node.begin()
		return
	ent.finished.connect(func(_skipped: bool) -> void: match_node.begin(), CONNECT_ONE_SHOT)
	ent.play([
		{"doll": p1, "name": String(info.get("player_name", tr("Игрок"))), "build": String(info.get("player_build", p1.blueprint.title)),
			"mass": p1.blueprint.total_mass(), "parts": p1.blueprint.nodes.size(), "record": String(info.get("player_record", ""))},
		{"doll": p2, "name": String(info.get("rival_title", p2.blueprint.title)), "build": String(info.get("rival_build", "")),
			"mass": p2.blueprint.total_mass(), "parts": p2.blueprint.nodes.size(), "record": String(info.get("rival_record", ""))},
	])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				if not finished:
					finished = true
					fight_abandoned.emit()
			KEY_F10:
				cycle_fx_preset()
			KEY_H:
				cycle_hud_skin()


func player_won(winner: Doll) -> bool:
	return winner != null and is_instance_valid(winner) and winner.is_in_group("players")


func _on_match_over(winner: Doll, results: Dictionary) -> void:
	if finished:
		return
	finished = true
	outcome = {"won": player_won(winner), "draw": bool(results.get("draw", false)), "reason": String(results.get("reason", "")),
		"duration_s": float(results.get("duration_s", match_node.fight_time))}
	var t := get_tree().create_timer(Tuning.CAMPAIGN_RESULT_DELAY_S, true, false, true)
	t.timeout.connect(func() -> void: fight_finished.emit(bool(outcome["won"]), outcome))


# --- крафтовое оружие из чертежа (как испытание мастерской: WorkshopBuild.start_test / _mount / grip_offset / mount_transform) ---

func _equip_crafted(d: ModularDoll) -> void:
	var bp := d.blueprint
	if bp == null or not (bp.weapon is WeaponBlueprint):
		return
	var m := _mount(bp, d)
	if String(m["uid"]) == "":
		return
	var pickup := d.get_node_or_null("WeaponPickup") as WeaponPickup
	if pickup == null:
		pickup = WeaponPickup.attach_to(d)
	var w := CraftedWeapon.create(CraftEdit.dup_weapon(bp.weapon as WeaponBlueprint))
	w.name = "CraftedWeapon_%s" % d.name
	weapons_root.add_child(w)
	w.global_transform = _mount_xf(d, m)
	var saved := pickup.hand_grip_offset
	pickup.hand_grip_offset = _grip(d, m)
	pickup.attach(String(d.uid_body[String(m["uid"])]), w)
	pickup.hand_grip_offset = saved


static func _mount(bp: BodyBlueprint, d: ModularDoll) -> Dictionary:
	var m := CraftEdit.weapon_mount(bp)
	if bp.weapon_on != "" and not CraftEdit.find(bp, bp.weapon_on).is_empty() and not CraftEdit.is_fixed(bp, bp.weapon_on):
		var pd := CraftEdit.def_of(bp, bp.weapon_on)
		m = {"uid": bp.weapon_on, "kind": "hand" if pd != null and pd.kind == "hand" else "end", "reason": ""}
	if String(m.get("uid", "")) == "" or not d.uid_body.has(String(m["uid"])):
		return {"uid": "", "kind": ""}
	return m


static func _grip(d: ModularDoll, m: Dictionary) -> Vector3:
	if String(m.get("kind", "")) == "hand":
		return WorkshopBuild.HAND_GRIP
	var body := d.parts.get(String(d.uid_body.get(String(m["uid"]), ""))) as RigidBody3D
	var best := Vector3.ZERO
	var found := false
	if body != null:
		for c in body.get_children():
			if c is Marker3D and String(c.name).begins_with("Anchor_") and (not found or (c as Marker3D).position.y < best.y):
				best = (c as Marker3D).position
				found = true
		if not found:
			best = Vector3(0, -ModularDoll._local_extent(body).y * 0.5, 0)
	return best


static func _mount_xf(d: ModularDoll, m: Dictionary) -> Transform3D:
	var bn := String(d.uid_body[String(m["uid"])])
	var h := d.parts[bn] as RigidBody3D
	var side := 1.0 if bn.ends_with("L") else -1.0
	var basis := h.global_transform.basis * Basis(Vector3(0, 0, 1), deg_to_rad(-90.0 + WorkshopBuild.HOLD_ANGLE_DEG * side))
	return Transform3D(basis, h.to_global(_grip(d, m)))
