## Матч демо «Головоломки вдвоём» (docs/plan-demo/PUZZLE.md): наследник Match ради общего — регистрация кукол, DollCombat (толчки),
## звук и эффекты, пауза Flow. Своё:
##   • отсчёта и часов нет (countdown 0, предел времени — бесконечность): сразу «бой», Sudden Death не наступает;
##   • урона и отброса от ударов нет: Doll.incoming_mult = 0 у всех, knockback_mult() = 0 (взрыв бочки отбрасывает сам), крит-кино
##     выключено;
##   • KO (только если кукла выбыла скриптом) не кончает матч: кукла возвращается в текущую комнату через RESPAWN_S;
##   • толпы нет (CrowdDirector убирается) — комнаты пустые, это не арена.
## Точки появления — текущая комната (spawn_points() площадки, она же «арена» для Match и камеры).
class_name PuzzleMatch
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
		crowd.free()   # сразу: его отложенный _bind на освобождённом узле не вызовется (вне дерева он упал бы на get_tree())


func register(d: Doll) -> void:
	super.register(d)
	d.incoming_mult = 0.0


## Возврат куклы (KO, застряла): новая кукла на точке текущей комнаты.
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


## Отброса от ударов нет (DollCombat × knockback_mult): головоломки — не бой; столкнулись двое с ящиком в руках — не разлетаются.
## Тела толкаются физикой как обычно, взрыв бочки отбрасывает сам (Explosion).
func knockback_mult() -> float:
	return 0.0
