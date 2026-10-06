## Матч пробы «Подъём: стена» (docs/plan-demo/CLIMB.md, MODES_PACK.md §8; автор 06.10: «PEAK тоже»). Наследник Match ради общего —
## регистрация кукол, DollCombat (толчки), звук и эффекты, пауза Flow. Своё:
##   • отсчёта и часов боя нет (countdown 0, предел — бесконечность), урона и отброса от ударов нет (incoming_mult 0, knockback_mult 0),
##     крит и СТАЗИС выключены, толпы нет (стена — не арена);
##   • каждой кукле — снаряжение «Подъёма» (rig): две руки ArmAssist с хватом за стену (ЛКМ — Hand_R, левая на экране; ПКМ — Hand_L),
##     запас тяги ThrustStamina, у P2-человека — руки с клавиатуры ClimbKeyHands. Respawn_doll переносит детей куклы без настроек
##     (script.new()), поэтому register снимает их и вешает заново;
##   • по каждому игроку: высота ног (ЦМ − COM_STAND_M), рекорд высоты, время (часы идут с первого отрыва от пола или хвата), финиш —
##     ЦМ на плато (ClimbWall.at_finish), срывы (упал ≥ Tuning-порога FALL_M с последней опоры — сигнал fell, без травм);
##   • лучшие время и высота за сессию — static (в файл не пишутся).
class_name ClimbMatch
extends Match

signal finished(d: Doll, seconds: float)
signal fell(d: Doll, metres: float)
signal climb_reset

## ЦМ стоящей куклы над ногами, м (высота на HUD — ноги).
const COM_STAND_M := 1.0
## Падение с последней опоры больше этого — «сорвался» (HUD, пробы).
const FALL_M := 3.0
## Часы игрока идут, когда ЦМ поднялся над стартом на столько (или первая рука на стене).
const START_RISE_M := 0.5

var wall: ClimbWall
## player_index → {doll, t, started, done, done_t, h, best_h, peak, falls, max_fall, start_y}
var players: Dictionary = {}
static var best_time := -1.0
static var best_height := 0.0


func _ready() -> void:
	time_limit_s = 1.0e9
	hard_timeout_s = 1.0e9
	countdown_s = 0.0
	super._ready()
	crit_enabled = false
	var crowd := get_node_or_null("CrowdDirector")
	if crowd != null:
		remove_child(crowd)
		crowd.free()


func _find_wall() -> ClimbWall:
	if wall != null and is_instance_valid(wall):
		return wall
	var a := _arena()
	wall = a as ClimbWall
	return wall


func register(d: Doll) -> void:
	var fresh := not _order.has(d)
	super.register(d)
	if not fresh:
		return
	d.incoming_mult = 0.0
	rig(d)
	var pi := d.player_index
	if not players.has(pi):
		players[pi] = _new_player()
	players[pi]["doll"] = d
	players[pi]["start_y"] = d.global_position.y + COM_STAND_M


## Снаряжение «Подъёма»: две руки с хватом за стену, запас тяги, руки P2 с клавиатуры. Старые узлы (перенесённые respawn_doll без
## настроек) снимаются сразу.
static func rig(d: Doll) -> void:
	for c in d.get_children():
		if c is ArmAssist or c is ThrustStamina or c is ClimbKeyHands:
			d.remove_child(c)
			c.queue_free()
	var left := ArmAssist.new()
	left.name = "ArmAssist"
	left.control_part = "Hand_R" if d.parts.has("Hand_R") else ""
	left.button = "lmb"
	left.wall_grip = true
	d.add_child(left)
	if d.parts.has("Hand_L"):
		var right := ArmAssist.new()
		right.name = "ArmAssistR"
		right.control_part = "Hand_L"
		right.button = "rmb"
		right.primary = false
		right.wall_grip = true
		d.add_child(right)
	ThrustStamina.attach_to(d)
	if d.input_prefix == "p2" and not d.external_input:
		ClimbKeyHands.attach_to(d)


## Руки куклы со стены (по порядку: ЛКМ — Hand_R, ПКМ — Hand_L).
static func wall_arms(d: Doll) -> Array:
	var out: Array = []
	if d == null or not is_instance_valid(d):
		return out
	for n in ["Hand_R", "Hand_L"]:
		for c in d.get_children():
			if c is ArmAssist and (c as ArmAssist).wall_grip and (c as ArmAssist).part_name == n:
				out.append(c)
	return out


static func _new_player() -> Dictionary:
	return {"doll": null, "t": 0.0, "started": false, "done": false, "done_t": 0.0, "h": 0.0, "best_h": 0.0, "peak": 0.0,
		"falls": 0, "max_fall": 0.0, "start_y": COM_STAND_M}


func respawn_doll(old: Doll, keep_lost := false) -> Doll:
	var d := super.respawn_doll(old, keep_lost)
	d.incoming_mult = 0.0
	return d


func begin() -> void:
	for pi in players:
		var d: Variant = players[pi]["doll"]
		players[pi] = _new_player()
		players[pi]["doll"] = d
	super.begin()
	for d in dolls():
		var dd := d as Doll
		if dd.stamina != null:
			dd.stamina.refill()
		if players.has(dd.player_index):
			players[dd.player_index]["start_y"] = dd.centre_of_mass().y
			players[dd.player_index]["peak"] = dd.centre_of_mass().y
	climb_reset.emit()


func stasis_allowed() -> bool:
	return false


func _check_over() -> void:
	pass


## Отброса от ударов нет: подъём — не бой (толкнуть соседа телом всё равно можно — физика).
func knockback_mult() -> float:
	return 0.0


func doll_of_index(pi: int) -> Doll:
	var d: Variant = players.get(pi, {}).get("doll", null)
	return d as Doll if d != null and is_instance_valid(d) else null


## Высота ног над полом старта по ЦМ, м.
static func height_of(d: Doll) -> float:
	return maxf(d.centre_of_mass().y - COM_STAND_M, 0.0)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not _started or phase == Phase.OVER:
		return
	_find_wall()
	for pi in players:
		var p: Dictionary = players[pi]
		var d := doll_of_index(pi)
		if d == null or not d.is_inside_tree() or not d.alive:
			continue
		var com := d.centre_of_mass()
		var h := maxf(com.y - COM_STAND_M, 0.0)
		p["h"] = h
		p["best_h"] = maxf(float(p["best_h"]), h)
		best_height = maxf(best_height, h)
		var on_wall := false
		for a in wall_arms(d):
			if (a as ArmAssist).is_wall_holding():
				on_wall = true
		if not bool(p["started"]) and (com.y > float(p["start_y"]) + START_RISE_M or on_wall):
			p["started"] = true
		if bool(p["started"]) and not bool(p["done"]):
			p["t"] = float(p["t"]) + delta
		# срыв: упал с последней опоры (рука на стене или уступ) больше FALL_M
		var supported := on_wall or (d.stamina != null and d.stamina.on_ledge)
		if supported:
			var drop := float(p["peak"]) - com.y
			if drop >= FALL_M:
				p["falls"] = int(p["falls"]) + 1
				p["max_fall"] = maxf(float(p["max_fall"]), drop)
				fell.emit(d, drop)
			p["peak"] = com.y
		else:
			p["peak"] = maxf(float(p["peak"]), com.y)
		if not bool(p["done"]) and ClimbWall.at_finish(com):
			p["done"] = true
			p["done_t"] = float(p["t"])
			if best_time < 0.0 or float(p["t"]) < best_time:
				best_time = float(p["t"])
			finished.emit(d, float(p["t"]))
			announce.emit(tr("ВЕРХ!"), ANNOUNCE_COLORS["fight"], "fight")
