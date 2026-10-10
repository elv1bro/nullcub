## Клюшки хоккея (docs/plan-demo/HOCKEY.md): узел-ребёнок SportMatch, живёт только при виде "hockey" (SportMatch._apply_sport).
## Каждой кукле — клюшка (оружие "stick", scenes/weapons/weapon_stick.tscn) в кисть preferred_hand через WeaponPickup
## (attach_to + attach; угол хвата HOCKEY_STICK_HOLD_DEG — крюк достаёт до льда). Раз в HOCKEY_STICK_CHECK_S сверяет:
##   • у живой куклы нет клюшки (старт, расстановка после гола — Match.respawn_doll создаёт куклу заново, нокаут — то же,
##     кисть оторвана вместе с клюшкой) дольше HOCKEY_STICK_REGIVE_S — новая в свободную кисть (preferred_hand, иначе любую);
##   • ничья клюшка (хозяин пересоздан или её выронили) лежит дольше HOCKEY_STICK_ORPHAN_S — убирается: на льду не копятся.
## Клюшка — обычное оружие: бьёт шайбу и соперника (урон × 0.5, Tuning.WEAPON["stick"]), DollCombat считает удары как оружием.
## given — счётчик выданных клюшек (пробы).
class_name HockeySticks
extends Node

const STICK_ID := "stick"

var sm: SportMatch
var given := 0
var _t := 0.0
var _without: Dictionary = {}     # instance_id куклы → секунд без клюшки
var _orphan: Dictionary = {}      # instance_id клюшки → секунд ничьей


func _ready() -> void:
	sm = get_parent() as SportMatch


func _exit_tree() -> void:
	for w in sticks():
		_remove(w)


## Все клюшки сцены.
func sticks() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group(Weapon.GROUP):
		var w := n as Weapon
		if w != null and is_instance_valid(w) and w.weapon_id == STICK_ID:
			out.append(w)
	return out


static func stick_of(d: Doll) -> Weapon:
	var wp := pickup_of(d)
	if wp == null:
		return null
	for hn in wp.held.keys():
		var w: Weapon = wp.held[hn]["weapon"]
		if is_instance_valid(w) and w.weapon_id == STICK_ID:
			return w
	return null


static func pickup_of(d: Doll) -> WeaponPickup:
	return d.get_node_or_null("WeaponPickup") as WeaponPickup


func _physics_process(delta: float) -> void:
	if sm == null or not sm._started:
		return
	_t += delta
	if _t < Tuning.HOCKEY_STICK_CHECK_S:
		return
	var step := _t
	_t = 0.0
	var alive_ids := {}
	for d in sm.dolls():
		var dd := d as Doll
		if not dd.alive or not dd.is_inside_tree():
			continue
		alive_ids[dd.get_instance_id()] = true
		if stick_of(dd) != null:
			_without.erase(dd.get_instance_id())
			continue
		var s := float(_without.get(dd.get_instance_id(), 0.0)) + step
		# первая выдача (старт, расстановка, возврат после нокаута) — сразу; потеря в игре — через HOCKEY_STICK_REGIVE_S
		if not _without.has(dd.get_instance_id()) or s >= Tuning.HOCKEY_STICK_REGIVE_S:
			if give(dd):
				_without.erase(dd.get_instance_id())
				continue
		_without[dd.get_instance_id()] = s
	for k in _without.keys():
		if not alive_ids.has(k):
			_without.erase(k)
	var seen := {}
	for w in sticks():
		var ww := w as Weapon
		if ww.is_held():
			continue
		var id := ww.get_instance_id()
		seen[id] = true
		var s := float(_orphan.get(id, 0.0)) + step
		if s >= Tuning.HOCKEY_STICK_ORPHAN_S:
			_remove(ww)
			_orphan.erase(id)
		else:
			_orphan[id] = s
	for k in _orphan.keys():
		if not seen.has(k):
			_orphan.erase(k)


## Кисть для клюшки: у куклы с рукой мышью (ArmAssist, человек P1) — управляемая HOCKEY_STICK_HAND, клюшкой водит мышь; у
## остальных — кисть со стороны атаки (кукла смотрит в камеру: левая — +X), иначе клюшка волочится за спиной и бьёт не туда.
static func preferred_hand(d: Doll) -> String:
	if d.get_node_or_null("ArmAssist") != null:
		return Tuning.HOCKEY_STICK_HAND
	return "Hand_L" if SportMatch.team_of(d) == 0 else "Hand_R"


## Новая клюшка в кисть куклы. false — кисти нет (оторваны обе) или кукла держит что-то в обеих.
func give(d: Doll) -> bool:
	if d == null or not is_instance_valid(d) or not d.alive:
		return false
	var wp := pickup_of(d)
	if wp == null:
		wp = WeaponPickup.attach_to(d)
	wp.hold_angle_deg = Tuning.HOCKEY_STICK_HOLD_DEG
	var hand := ""
	var names: Array = wp.hand_names()
	var pref := preferred_hand(d)
	if names.has(pref) and not wp.is_holding(pref):
		hand = pref
	else:
		for hn in names:
			if not wp.is_holding(String(hn)):
				hand = String(hn)
				break
	if hand == "":
		return false
	var parent: Node = sm.get_parent()
	var holder := parent.get_node_or_null("Weapons")
	var w := Weapon.spawn(STICK_ID, holder if holder != null else parent, wp.hand_grip_global(hand))
	if w == null:
		return false
	if not wp.attach(hand, w):
		w.queue_free()
		return false
	given += 1
	return true


func _remove(w: Weapon) -> void:
	if w == null or not is_instance_valid(w):
		return
	if w.is_held():
		w.drop()
	if w.is_inside_tree():
		w.get_parent().remove_child(w)
	w.queue_free()
