## Headless-проба временного хука ударных VFX площадки (scenes/playground.gd): P2 (орех) переносится на каменный мост рядом
## с P1 и толкается в неё; удар часть-о-часть с относительной скоростью ≥ IMPACT_SPEED должен породить ImpactFx
## (pg.fx_spawned ≥ 1). Печатает JSON и выходит 0/1.
## Запуск: godot --headless --path . --fixed-fps 60 res://tests/playground_fx_probe.tscn -- "until=3.0"
extends Node3D

const PG := "res://scenes/playground.tscn"

var pg: Node3D
var p1: Doll
var p2: Doll
var t := 0.0
var until := 3.0
var min_dist := INF
var max_speed := 0.0
var done := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "until":
				until = float(p[1])
	pg = load(PG).instantiate()
	add_child(pg)
	p1 = pg.get_node("P1")
	p2 = pg.get_node("P2")
	p1.external_input = true
	p2.external_input = true
	p2.position = Vector3(2.3, 4.05, 0)   # на каменный мост, справа от P1 (-1.5, 4.05)


func _physics_process(delta: float) -> void:
	if done:
		return
	t += delta
	p1.input_vec = Vector2.ZERO
	p2.input_vec = Vector2(-1.0, 0.25) if (t > 0.3 and t < 1.3) else Vector2.ZERO
	min_dist = minf(min_dist, p1.centre_of_mass().distance_to(p2.centre_of_mass()))
	max_speed = maxf(max_speed, maxf(p1.max_part_speed(), p2.max_part_speed()))
	if t >= until:
		done = true
		var fx: int = pg.get("fx_spawned")
		var monitored := 0
		for d in [p1, p2]:
			for b in d.parts.values():
				if (b as RigidBody3D).contact_monitor:
					monitored += 1
		var report := {
			"ok": fx >= 1 and monitored == 12 and max_speed < 20.0,
			"fx_spawned": fx, "contact_monitor_parts": monitored, "min_com_distance": snappedf(min_dist, 0.01),
			"max_part_speed": snappedf(max_speed, 0.01), "p1_scene": p1.scene_file_path, "p2_scene": p2.scene_file_path,
		}
		print(JSON.stringify(report))
		get_tree().quit(0 if report["ok"] else 1)
