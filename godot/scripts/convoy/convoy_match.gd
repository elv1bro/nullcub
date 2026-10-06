## Матч пробы «Перегон» (docs/plan-demo/CONVOY.md): наследник Match ради общего — регистрация кукол, DollCombat (толчки), звук и
## эффекты, пауза Flow. Как у головоломок (PuzzleMatch):
##   • отсчёта и часов нет (countdown 0, предел времени — бесконечность), Sudden Death не наступает; время участка считает площадка;
##   • урона и отброса от ударов нет: Doll.incoming_mult = 0, knockback_mult() = 0 — куклы толкают машину и друг друга телом;
##   • KO (только если кукла выбыла скриптом) не кончает матч: кукла возвращается через RESPAWN_S к машине (spawn_points площадки);
##   • толпы нет, СТАЗИСА нет (машина едет, пока жмёшь газ, — замирание мира тут только мешает).
class_name ConvoyMatch
extends Match

const RESPAWN_S := 1.0


func _ready() -> void:
	time_limit_s = 1.0e9
	hard_timeout_s = 1.0e9
	countdown_s = 0.0
	super._ready()
	crit_enabled = false
	var crowd := get_node_or_null("CrowdDirector")
	if crowd != null:
		remove_child(crowd)
		crowd.free()   # сразу: его отложенный _bind на освобождённом узле не вызовется


func register(d: Doll) -> void:
	super.register(d)
	d.incoming_mult = 0.0


func respawn_doll(old: Doll, keep_lost := false) -> Doll:
	var d := super.respawn_doll(old, keep_lost)
	d.incoming_mult = 0.0
	return d


func _on_doll_ko(_attacker: Node, _record: Dictionary, victim: Doll) -> void:
	if phase == Phase.OVER:
		return
	get_tree().create_timer(RESPAWN_S).timeout.connect(func() -> void:
		if is_instance_valid(victim) and victim.is_inside_tree() and not victim.alive:
			respawn_doll(victim))


func _check_over() -> void:
	pass


func knockback_mult() -> float:
	return 0.0


func stasis_allowed() -> bool:
	return false
