## Магнит трассы (docs/plan-demo/RACE_TRACK.md, участок 2): MagnetMachine Свалки тянет только железо, а кукла «Человек» — не железная;
## на трассе магнит тянет куклу целиком. Узел смотрит на машину machine_path (её цикл OFF → WARNING → ACTIVE → COOLDOWN и полюс
## pole_global()) и, пока она включена, тянет каждую куклу ближе Tuning.TRACK_MAGNET_RADIUS к полюсу: сила до TRACK_MAGNET_FORCE (Н,
## тяга куклы ~480 Н — вырваться можно, но лететь мимо тяжело), спад к краю радиуса, вплотную слабее; делится по деталям по массе
## (кукла не рвётся). Мощность нарастает RAMP_S в начале ACTIVE и гаснет RELEASE_S в COOLDOWN (как у самой машины).
class_name TrackMagnetPull
extends Node

const RAMP_S := 0.3
const RELEASE_S := 0.35
const NEAR_M := 1.0

@export var machine_path: NodePath

var machine: MagnetMachine
## Для проб: последняя сила на куклу (Н) и сколько тиков тянул.
var last_force := 0.0
var pull_ticks := 0


func _ready() -> void:
	machine = get_node_or_null(machine_path) as MagnetMachine


func power() -> float:
	if machine == null:
		return 0.0
	match machine.state:
		ScrapMachine.State.ACTIVE:
			return minf(machine.state_t / RAMP_S, 1.0)
		ScrapMachine.State.COOLDOWN:
			return maxf(1.0 - machine.state_t / RELEASE_S, 0.0)
	return 0.0


func _physics_process(_delta: float) -> void:
	last_force = 0.0
	var pw := power()
	if pw <= 0.0:
		return
	var pole3 := machine.pole_global()
	var pole := Vector2(pole3.x, pole3.y)
	var r_max := Tuning.TRACK_MAGNET_RADIUS
	for d in get_tree().get_nodes_in_group("dolls"):
		var doll := d as Doll
		if doll == null or not doll.alive or not doll.is_inside_tree() or doll.total_mass <= 0.0:
			continue
		var c := doll.centre_of_mass()
		var to := pole - Vector2(c.x, c.y)
		var r := to.length()
		if r > r_max or r < 0.01:
			continue
		var fall := smoothstep(r_max, r_max * 0.5, r)
		var near := clampf(r / NEAR_M, 0.3, 1.0)
		var f := Tuning.TRACK_MAGNET_FORCE * fall * near * pw
		var dir := to / r
		for p in doll.parts.values():
			var b := p as RigidBody3D
			if b != null and is_instance_valid(b):
				b.apply_central_force(Vector3(dir.x, dir.y, 0.0) * f * b.mass / doll.total_mass)
		last_force = maxf(last_force, f)
		pull_ticks += 1
