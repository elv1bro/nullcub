## Цель камеры в PvE (scenes/playground_pve.tscn). DynamicCamera (scenes/camera/dynamic_camera.gd) держит в кадре ВСЕ куклы своей
## группы target_group — с многими куклами она работает (AABB ЦМ живых + упреждение летящих), но 5 врагов по всей Свалке
## отодвинули бы камеру на полный отъезд и игрок стал бы точкой. Поэтому у камеры PvE своя группа focus_group, и этот узел каждый
## тик решает, кто в неё входит (dynamic_camera.gd не меняется):
##   • все игроки (живые; если живых нет — все, камера сама берёт мёртвых);
##   • враги ближе focus_radius_m к кому-нибудь из игроков, не больше max_enemies ближайших (они сейчас дерутся);
##   • только что выпавшие из желоба — первые spawn_show_s секунд (видно, откуда пришла волна).
class_name PveFocus
extends Node

@export var focus_group := "pve_focus"
@export var players_group := "players"
@export var enemies_group := "enemies"
@export var focus_radius_m := 8.0
@export var max_enemies := 3
@export var spawn_show_s := 1.6

var _time := 0.0
var _born: Dictionary = {}     # instance id врага -> время первого появления


func _physics_process(delta: float) -> void:
	_time += delta
	var tree := get_tree()
	var players: Array = []
	for n in tree.get_nodes_in_group(players_group):
		if n is Doll and n.is_inside_tree():
			players.append(n)
	var want: Dictionary = {}
	var any_alive := false
	for p in players:
		if (p as Doll).alive:
			any_alive = true
	var pts: Array = []
	for p in players:
		if (p as Doll).alive or not any_alive:
			want[p] = true
			if (p as Doll).alive:
				pts.append((p as Doll).centre_of_mass())
	var near: Array = []
	for n in tree.get_nodes_in_group(enemies_group):
		var e := n as Doll
		if e == null or not e.is_inside_tree() or not e.alive:
			continue
		var id := e.get_instance_id()
		if not _born.has(id):
			_born[id] = _time
		var c := e.centre_of_mass()
		if _time - float(_born[id]) < spawn_show_s:
			want[e] = true
			continue
		var best := INF
		for p in pts:
			best = minf(best, c.distance_to(p))
		if best <= focus_radius_m:
			near.append([best, e])
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i in range(mini(near.size(), max_enemies)):
		want[near[i][1]] = true
	for n in tree.get_nodes_in_group(focus_group):
		if not want.has(n):
			n.remove_from_group(focus_group)
	for n in want.keys():
		if is_instance_valid(n) and not (n as Node).is_in_group(focus_group):
			(n as Node).add_to_group(focus_group)
	if _born.size() > 64:
		var alive_ids := {}
		for n in tree.get_nodes_in_group(enemies_group):
			alive_ids[n.get_instance_id()] = true
		for k in _born.keys():
			if not alive_ids.has(k):
				_born.erase(k)
