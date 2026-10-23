## Бот Испытания (docs/plan-demo/GAUNTLET.md): наскок RivalBrain (бот-соперник кампании), но уровень 1..5 — уровень 5 из
## Tuning.GAUNTLET_LEVEL5 (сверх финала лиги). as_player = true — автопилот за игрока (проба bots): цель — "rivals", свои — "players".
class_name GauntletBrain
extends RivalBrain

@export var as_player := false


func _brain_ready() -> void:
	super._brain_ready()
	var p := GauntletRun.level_params(level)
	reaction_s = float(p.get("reaction_s", reaction_s))
	aim_error_m = float(p.get("aim_error_m", aim_error_m))
	lead_s = float(p.get("lead_s", lead_s))
	retreat_s = float(p.get("retreat_s", retreat_s))
	use_dash = bool(p.get("dash", true))
	if as_player:
		players_group = "rivals"
		enemies_group = "players"
